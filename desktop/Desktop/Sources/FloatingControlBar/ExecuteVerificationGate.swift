import Foundation

/// Sprint 2 / P2 — verifies that an Execute pill actually *did* something
/// before we let it flip to `.done`.
///
/// Background (see `TASK_EXEC_RELIABILITY_REVIEW.md` §F1):
///   The agent's prompt asks the model to call a write/send tool and verify
///   the work before reporting done. Nothing in the host enforces that. A
///   non-trivial slice of "Sent the summary to Daniel on Telegram" replies
///   are pure fiction — no Telegram-touching tool ever fired.
///
/// This gate is a heuristic, not a proof. It does two things:
///
/// 1. **Classifies the query.** If the first imperative verb is "send / reply
///    / create / schedule / draft / post / email / message / book", we expect
///    the agent to call a tool. If not (research / lookup / summarize), no
///    tool is required and the gate stays out of the way.
///
/// 2. **Walks the pill's tool transcript.** If the action is `.actionable` and
///    no tool from `writeToolSet` was invoked, the gate returns `.unverified`
///    so the caller can either retry (Sprint 2 / P3) or demote to `.failed`.
///
/// The gate operates on tool *names* rather than tool *results* because we
/// don't have a reliable host-side way to inspect tool outputs from the
/// pi-mono / ACP stream uniformly. P8 (Sprint 3) layers a programmatic
/// verification turn on top of this for proof-quality evidence.
enum ExecuteVerificationGate {

    /// Tools that constitute "the agent took action on the user's behalf".
    /// Includes shell / osascript (drive native apps), Playwright variants
    /// (drive the browser), file write, calendar/notes/mail/messages MCPs.
    /// Kept as a static `Set` so membership checks are O(1) on a hot path.
    ///
    /// Tool names are matched case-insensitively, and the check is "any tool
    /// invoked has a name that *starts with* one of these prefixes" — this
    /// catches Playwright's `browser_click`, `browser_navigate`, etc. and
    /// pi-mono's prefixed tool names without hardcoding every variant.
    static let writeToolPrefixes: Set<String> = [
        "shell",
        "bash",
        "osascript",
        "execute_shell",
        "write",
        "write_file",
        "edit_file",
        "create_file",
        "apple_notes_add",
        "apple_notes_update",
        "apple_mail_send",
        "send_imessage",
        "slack_send",
        "slack_post",
        "playwright",
        "browser_",
        "create_event",
        "update_event",
        "add_event",
        "schedule_event",
        "create_action_item",
        "update_action_item",
        "complete_task",
    ]

    /// Verbs that imply a write/send/create side effect.
    private static let actionVerbs: Set<String> = [
        "send", "reply", "respond", "answer",
        "create", "make", "build", "generate",
        "schedule", "book", "plan",
        "draft", "compose", "write",
        "post", "publish", "share",
        "email", "message", "text", "ping", "dm",
        "add", "remove", "delete",
        "set", "update", "change", "edit", "modify",
        "open", "close",
        "remind", "notify",
        "buy", "order", "purchase",
        "save", "download", "upload",
    ]

    /// First-verb classifier. Returns `.actionable` when *either* the Title
    /// line *or* the Details line of the EXECUTE preamble (or, for a bare
    /// query string, the raw query) starts with an imperative verb that
    /// demands an external side effect.
    ///
    /// Why we look at both lines: production proactive task notifications
    /// hardcode `title: "Task"` (see TaskPromotionService.swift) and put the
    /// real imperative in `message: "New task: Send Daniel ..."`. Reading
    /// only the Title line would classify every real Execute click as
    /// `.research` and bypass the gate / retry / verification turn entirely.
    static func classify(query: String) -> AgentPill.ActionClass {
        let candidates = candidateImperativeTexts(from: query)
        for candidate in candidates {
            if firstTokenIsActionVerb(candidate) {
                return .actionable
            }
        }
        return .research
    }

    /// Verification result.
    enum Result: Equatable {
        /// Action expected and a write tool fired (or no action expected).
        /// The pill is allowed to flip to `.done`.
        case verified
        /// Action was expected but no write tool was invoked. The caller
        /// should either retry or demote to `.failed`. The associated
        /// message is suitable for surfacing in `pill.latestActivity`.
        case unverified(reason: String)
    }

    /// Run the gate against a pill's tool-call transcript.
    ///
    /// `invokedToolNames` is the union of every tool name the pill's
    /// `ChatProvider` emitted a `toolActivity` event for during the run.
    /// Case-insensitive; duplicates are fine.
    static func evaluate(
        actionClass: AgentPill.ActionClass,
        invokedToolNames: [String]
    ) -> Result {
        if actionClass == .research {
            return .verified
        }
        let lowered = invokedToolNames.map { $0.lowercased() }
        let matched = lowered.contains { name in
            writeToolPrefixes.contains { prefix in
                name == prefix || name.hasPrefix(prefix)
            }
        }
        if matched {
            return .verified
        }
        return .unverified(
            reason: "Agent claimed completion without taking action. No write/send/script tool was invoked."
        )
    }

    // MARK: - Helpers

    /// Candidate imperative phrases to feed the verb classifier. Tries the
    /// Title line and the Details line of a `ProactiveTaskExecute.buildQuery`
    /// preamble; falls back to the raw query for bare strings. Stripped of
    /// the `"New task: "` prefix TaskPromotionService prepends to every
    /// notification message in production.
    private static func candidateImperativeTexts(from query: String) -> [String] {
        var candidates: [String] = []
        if let title = extractLine(prefixedBy: "Task: ", in: query) {
            candidates.append(title)
        }
        if let details = extractLine(prefixedBy: "Details: ", in: query) {
            candidates.append(stripLeadingNewTaskPrefix(details))
        }
        if candidates.isEmpty {
            candidates.append(query)
        }
        return candidates
    }

    /// Pull the single-line value after `prefix` (up to the next newline).
    /// Returns nil when the prefix is absent — callers fall through to the
    /// next candidate.
    private static func extractLine(prefixedBy prefix: String, in query: String) -> String? {
        guard let range = query.range(of: prefix) else { return nil }
        let after = query[range.upperBound...]
        if let newline = after.range(of: "\n") {
            return String(after[..<newline.lowerBound])
        }
        return String(after)
    }

    /// `TaskPromotionService.swift:102` formats every proactive task
    /// notification's message as `"New task: <description>"`. Strip that
    /// prefix so the classifier sees the verb in `<description>` instead
    /// of always seeing the literal noun "task".
    private static func stripLeadingNewTaskPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = trimmed.range(
            of: #"^new task:\s*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            return String(trimmed[range.upperBound...])
        }
        return trimmed
    }

    /// True when the first letter-only token in `text` is one of our
    /// recognized side-effect verbs.
    private static func firstTokenIsActionVerb(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstToken = normalized
            .split(whereSeparator: { !$0.isLetter })
            .first
            .map(String.init)
        else {
            return false
        }
        return actionVerbs.contains(firstToken)
    }
}
