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

    /// First-verb classifier. Returns `.actionable` when the query begins with
    /// an imperative verb that demands an external side effect.
    static func classify(query: String) -> AgentPill.ActionClass {
        // Strip an optional markdown heading + leading "Execute this task
        // end-to-end now." preamble that ProactiveTaskExecute.buildQuery
        // adds, so we classify on the real task description.
        let normalized = stripExecutePreamble(query)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstToken = normalized
            .split(whereSeparator: { !$0.isLetter })
            .first
            .map(String.init)
        else {
            return .research
        }

        // Verbs that imply a write/send/create side effect.
        let actionVerbs: Set<String> = [
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
        return actionVerbs.contains(firstToken) ? .actionable : .research
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

    /// Strip ProactiveTaskExecute's `# EXECUTE` preamble so the verb
    /// classifier doesn't always see "execute" as the first verb.
    private static func stripExecutePreamble(_ query: String) -> String {
        // The preamble is the literal "Task: <title>" line. Pull just the
        // title, since that's the user-meaningful imperative.
        guard let taskRange = query.range(of: "Task: ") else { return query }
        let afterTask = query[taskRange.upperBound...]
        if let newlineRange = afterTask.range(of: "\n") {
            return String(afterTask[..<newlineRange.lowerBound])
        }
        return String(afterTask)
    }
}
