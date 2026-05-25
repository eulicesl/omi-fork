import Foundation

/// Prompt fragments for the "Execute" button on a proactive task notification.
///
/// The floating-bar agent normally lives under `floatingBarSystemPromptPrefix`,
/// which tells it to answer in 1–2 sentences and never ask follow-ups. That's
/// the opposite of what we want when the user explicitly clicks **Execute** —
/// the user wants the task *done*, not described.
///
/// `systemPromptSuffix` is appended after the main system prompt so it takes
/// precedence over the floating-bar concise-answer rules, and `buildQuery`
/// rewrites the prompt as an imperative.
enum ProactiveTaskExecute {
    /// Model to use for Execute pills, regardless of the user's selected
    /// floating-bar model. Execute is the highest-tool-count agentic surface
    /// in the app — Opus's planning quality on multi-step tool use is the
    /// exact reliability uplift we want to pay for here. Inline-bar answers
    /// keep using whatever the user picked in ShortcutSettings.
    ///
    /// Overridable via `defaults write com.omi.<bundle> OmiExecuteModel "<id>"`
    /// for power users who want to A/B against other models.
    static let preferredModel = "claude-opus-4-6"

    /// Resolve the model for an Execute pill: honors a user override if set,
    /// otherwise pins to `preferredModel`. Never falls back to the inline-bar
    /// model selection — see `preferredModel` for rationale.
    static func resolveModel() -> String {
        let override = UserDefaults.standard.string(forKey: "OmiExecuteModel")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let override, !override.isEmpty {
            return override
        }
        return preferredModel
    }

    /// Imperative restatement of the task. Tells the agent the user already
    /// chose to act — so finish the work end-to-end (which may legitimately
    /// include summarizing, drafting, or describing if that *is* the task).
    ///
    /// `context` (when present) carries the same `FloatingBarNotificationContext`
    /// the floating-bar follow-up chat already receives — `sourceApp`,
    /// `windowTitle`, `contextSummary`, `currentActivity`, `reasoning`,
    /// `detail`. Without it the agent had to re-derive the target with
    /// `semantic_search` / `get_memories` / `execute_sql`, which is slow and
    /// the single most common cause of "Sent the summary to the wrong Daniel."
    static func buildQuery(
        title: String,
        message: String,
        context: FloatingBarNotificationContext? = nil
    ) -> String {
        var sections: [String] = []

        if let ctx = context, let block = formatContextBlock(ctx) {
            sections.append(block)
        }

        sections.append("""
        # EXECUTE
        Execute this task end-to-end now.

        Task: \(title)
        Details: \(message)
        """)

        return sections.joined(separator: "\n\n")
    }

    /// Render the context block. Returns nil when every field is empty so we
    /// don't waste tokens on a heading with no body.
    private static func formatContextBlock(_ ctx: FloatingBarNotificationContext) -> String? {
        var lines: [String] = []
        if let app = ctx.sourceApp, !app.isEmpty {
            lines.append("- Source app: \(app)")
        }
        if let window = ctx.windowTitle, !window.isEmpty {
            lines.append("- Window: \(window)")
        }
        if let detail = ctx.detail, !detail.isEmpty {
            lines.append("- Detail: \(detail)")
        }
        if let activity = ctx.currentActivity, !activity.isEmpty {
            lines.append("- Activity at the time the task was promoted: \(activity)")
        }
        if let summary = ctx.contextSummary, !summary.isEmpty {
            lines.append("- Context summary: \(summary)")
        }
        if let reasoning = ctx.reasoning, !reasoning.isEmpty {
            lines.append("- Reasoning: \(reasoning)")
        }

        guard !lines.isEmpty else { return nil }
        return """
        # TASK CONTEXT
        Use this context to pick the right target (channel, recipient, file,
        thread). Do not call `semantic_search` / `get_memories` / `execute_sql`
        for facts that are already given here.

        \(lines.joined(separator: "\n"))
        """
    }

    // MARK: - Direct-action fast path

    /// Deterministic local actions that don't need an LLM turn — opening
    /// apps and URLs. Detected at the Execute click site so we can short
    /// the highest-confidence intents straight to `open(1)` instead of
    /// paying for a model round trip that can refuse.
    enum DirectDesktopAction: Equatable {
        case openApplication(name: String)
        case openURL(url: URL, browserName: String?)
    }

    /// Multi-step deferral pattern (fast-path → LLM fallback). Triggers on:
    /// - a coordinating conjunction (`and|then|also`) followed by content, or
    /// - any secondary action verb that suggests more work after the open.
    /// Kept as a single alternation regex so the check is one pass.
    /// `open` is intentionally excluded — we already matched it as the
    /// primary verb; including it would defer "Open Chrome please open
    /// quickly" (rare, but unambiguously single-action).
    private static let multiStepPattern =
        #"\b(?:and|then|also|"# +
        #"send|reply|respond|message|text|email|ping|dm|"# +
        #"create|make|build|generate|draft|compose|write|"# +
        #"schedule|book|plan|"# +
        #"post|publish|share|"# +
        #"remove|delete|"# +
        #"update|change|edit|modify|set|add|"# +
        #"remind|notify|"# +
        #"buy|order|purchase|"# +
        #"save|download|upload"# +
        #")\b"#

    /// Inspect a notification's user-meaningful imperative for a
    /// high-confidence "open X" intent. Returns nil whenever in doubt — the
    /// agent path is always the fallback, so a missed match merely degrades
    /// to today's behavior. A false positive would surprise the user, so
    /// the matcher only fires when the verbs *and* targets are unambiguous.
    ///
    /// Scope note: we deliberately ignore `FloatingBarNotificationContext`
    /// (`sourceApp`, `windowTitle`, `reasoning`, `detail`, …) — those are
    /// observational, not the user's stated intent. Including them led to
    /// false positives like "Summarize the tabs I have **open** in
    /// **Chrome**" hijacking the fast path. The `title` and `message` carry
    /// the imperative; nothing else.
    static func directDesktopAction(
        title: String,
        message: String
    ) -> DirectDesktopAction? {
        let intentText = (title + " " + message)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fullRange = NSRange(location: 0, length: (intentText as NSString).length)

        // Strict adjacency guard. The verb ("open"/"launch") must sit next
        // to a recognized target, separated only by a small filler word
        // ("up", "the", "a"). Rejects descriptive uses like
        // "tabs I have open in Chrome" or "the launch I'm planning" —
        // those have "open"/"launch" in the text but not as an imperative
        // adjacent to a known target.
        //
        // Patterns match case-insensitively against the *original* intent
        // text so URL capture preserves the original case — critical for
        // case-sensitive paths, query params, and signed tokens.
        let appPattern = #"\b(?:open|launch)(?:\s+(?:up|the|a))?\s+(google chrome|chrome|safari|finder|react docs)\b"#
        let urlPattern = #"\b(?:open|launch)(?:\s+(?:up|the|a))?\s+(https?://\S+)"#
        let opts: NSRegularExpression.Options = [.caseInsensitive]

        let appMatch = (try? NSRegularExpression(pattern: appPattern, options: opts))?
            .firstMatch(in: intentText, range: fullRange)
        let urlMatch = (try? NSRegularExpression(pattern: urlPattern, options: opts))?
            .firstMatch(in: intentText, range: fullRange)
        guard appMatch != nil || urlMatch != nil else { return nil }

        // Multi-step guard. If the user's imperative chains more work after
        // the open phrase — e.g. "Open Chrome and send Daniel the summary",
        // "Launch Safari then check email", or just "Open Chrome" + "Send
        // Daniel ..." in separate title/message fields with no conjunction
        // at all — defer to the agent path so downstream work isn't
        // silently dropped. Two signals trigger deferral:
        //
        // 1. A coordinating conjunction (`and|then|also`) followed by
        //    content. Catches "Open Chrome and Safari" where the trailing
        //    target isn't a recognized action verb.
        // 2. Any *secondary action verb* in the text after the matched open
        //    phrase. Catches sentence-break and title/message-split
        //    multi-step cases like "Open Chrome. Send Daniel ..." that
        //    have no leading conjunction.
        //
        // Both checks are scoped to text *after* the matched open phrase
        // so a URL whose path contains the literal "and" or "send" (e.g.
        // ".../this-and-that", "/send/") doesn't false-trip.
        //
        // Conservative-by-design: a false positive (deferring something we
        // could have fast-pathed) just costs an LLM round trip; a false
        // negative silently drops user-requested work.
        let matchEndUTF16: Int = {
            if let appMatch { return NSMaxRange(appMatch.range) }
            if let urlMatch { return NSMaxRange(urlMatch.range) }
            return (intentText as NSString).length
        }()
        let afterText = (intentText as NSString)
            .substring(from: matchEndUTF16)
        if afterText.range(
            of: multiStepPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return nil
        }

        // Browser inference, two-source rule. We only set `browserName`
        // when the user *explicitly* named a browser; otherwise we let
        // open(1) fall back to the system default. Two signals count:
        //
        // 1. The app-phrase regex captured "chrome"/"safari" — the user
        //    wrote "Open Chrome" or "Launch Safari" directly.
        // 2. The intent contains an "in <Browser>" suffix — anchored by
        //    `\bin\s+` so it can't match inside hostnames like
        //    `developer.chrome.com` or `safari-extensions.example.com`.
        //
        // Substring scans like `lower.contains("chrome")` are wrong here:
        // they hijack any URL whose host happens to mention a browser.
        var browserName: String?
        if let appMatch,
           let captureRange = Range(appMatch.range(at: 1), in: intentText) {
            switch String(intentText[captureRange]).lowercased() {
            case "google chrome", "chrome":
                browserName = "Google Chrome"
            case "safari":
                browserName = "Safari"
            default:
                break
            }
        }
        if browserName == nil {
            let chromeSuffix = #"\bin\s+(?:google\s+)?chrome\b"#
            let safariSuffix = #"\bin\s+safari\b"#
            if intentText.range(of: chromeSuffix, options: [.regularExpression, .caseInsensitive]) != nil {
                browserName = "Google Chrome"
            } else if intentText.range(of: safariSuffix, options: [.regularExpression, .caseInsensitive]) != nil {
                browserName = "Safari"
            }
        }

        // "open <URL>" — primary target is the URL itself; the app phrase
        // (if also present) just picks the browser via `browserName`.
        // URL is captured from the original intent text (not lowercased),
        // so case-sensitive paths and signed tokens survive intact.
        if let urlMatch, let urlRange = Range(urlMatch.range(at: 1), in: intentText) {
            let urlString = trimTrailingNoise(from: String(intentText[urlRange]))
            if let url = URL(string: urlString) {
                return .openURL(url: url, browserName: browserName)
            }
        }

        // Otherwise the user explicitly named an app. Route by the exact
        // target the regex captured, so an incidental link in the body
        // never overrides an explicit app open.
        if let appMatch, let targetRange = Range(appMatch.range(at: 1), in: intentText) {
            switch String(intentText[targetRange]).lowercased() {
            case "google chrome", "chrome":
                return .openApplication(name: "Google Chrome")
            case "safari":
                return .openApplication(name: "Safari")
            case "finder":
                return .openApplication(name: "Finder")
            case "react docs":
                return .openURL(url: URL(string: "https://react.dev")!, browserName: browserName)
            default:
                return nil
            }
        }
        return nil
    }

    /// Execute a direct desktop action via `/usr/bin/open`. Returns a short
    /// human-readable summary suitable for the pill's `latestActivity`.
    /// Throws on non-zero exit so the caller can surface the failure.
    static func perform(_ action: DirectDesktopAction) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        switch action {
        case .openApplication(let name):
            process.arguments = ["-a", name]
        case .openURL(let url, let browserName):
            if let browserName, !browserName.isEmpty {
                process.arguments = ["-a", browserName, url.absoluteString]
            } else {
                process.arguments = [url.absoluteString]
            }
        }

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "ProactiveTaskExecute",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "open exited with status \(process.terminationStatus)"]
            )
        }

        switch action {
        case .openApplication(let name):
            return "Opened \(name)."
        case .openURL(let url, let browserName):
            if let browserName, !browserName.isEmpty {
                return "Opened \(url.absoluteString) in \(browserName)."
            }
            return "Opened \(url.absoluteString)."
        }
    }

    /// Normalize a pill's terminal activity text — trim, fall back to "Done"
    /// when empty. Kept here so direct-action and LLM-path pills share the
    /// same shape.
    static func completionActivityText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Done" : trimmed
    }

    /// Trim trailing sentence-noise off a captured URL. The capture is
    /// `\S+`, which greedily includes any closing characters at the end
    /// of the surrounding sentence — but those characters are sometimes
    /// part of the URL (Wikipedia disambig paths end in `)`, regex docs
    /// use `]`). Strip unambiguous sentence punctuation always, and
    /// strip closing brackets only when they're *unmatched* (i.e. there
    /// are more closes than opens in the URL).
    private static func trimTrailingNoise(from rawURL: String) -> String {
        var url = rawURL
        // Unambiguous sentence terminators that never appear at the end
        // of a real URL.
        let always: Set<Character> = [".", ",", ";", "!", "?", ":", "\"", "'"]
        while let last = url.last, always.contains(last) {
            url.removeLast()
        }
        // Closing brackets — strip only if the URL has more closes than
        // opens of that bracket type. Wikipedia URLs like
        // `/wiki/Foo_(bar)` are balanced and must survive.
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}")] {
            while url.hasSuffix(close) {
                let opens = url.filter { String($0) == open }.count
                let closes = url.filter { String($0) == close }.count
                if closes > opens {
                    url.removeLast()
                } else {
                    break
                }
            }
        }
        return url
    }

    /// Sprint 3 / P8 — programmatic verification follow-up. Fired on the same
    /// warm session after the main turn returns and the local verification
    /// gate (P2) says a write tool was called. Forces the model to produce
    /// a structured `{verified, evidence}` JSON object that the host can
    /// parse and that the pill UI surfaces as "Done — Sent (last message:
    /// 'Hey Daniel…')." Demotes to retry / failed when verified is false.
    static let verificationPrompt = """
    Verify the work you just claimed to do. Call exactly one cheap tool that
    proves it happened — for example:
    - read back the last message in the conversation,
    - `ls -la` or `stat` the file you wrote,
    - fetch the calendar event you created,
    - take a screenshot of the active app window.

    Then reply with a SINGLE-LINE JSON object, no prose, no markdown fences:

    {"verified": true|false, "evidence": "<one short sentence describing what you saw>"}

    If you cannot verify (the tool failed, the message wasn't actually sent,
    the file isn't there, the event didn't land) return verified: false with
    a short evidence line explaining what went wrong.
    """

    /// Parse the model's verification reply. Tolerant of leading prose and
    /// ```json fences``` because Haiku-class models occasionally ignore the
    /// "no markdown" instruction. Mirrors the defensive extraction in
    /// AgentPillsManager.runRouterCall.
    struct VerificationResult: Equatable {
        let verified: Bool
        let evidence: String
    }

    static func parseVerification(_ text: String) -> VerificationResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonBody: String
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            jsonBody = String(trimmed[firstBrace...lastBrace])
        } else {
            jsonBody = trimmed
        }
        guard let data = jsonBody.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // `verified` is required. Accept bool, string ("true"/"false"), or
        // 0/1 — models are inconsistent about this.
        let verified: Bool
        if let b = json["verified"] as? Bool {
            verified = b
        } else if let n = json["verified"] as? NSNumber {
            verified = n.boolValue
        } else if let s = json["verified"] as? String {
            verified = s.lowercased() == "true" || s == "1"
        } else {
            return nil
        }

        let evidence = (json["evidence"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        return VerificationResult(verified: verified, evidence: String(evidence.prefix(200)))
    }

    /// Appended to the system prompt for execute-mode pills only. Overrides
    /// the floating-bar "1-2 sentence concise answer" stance for this pill —
    /// the user already chose to act, so finish the work with tools rather
    /// than asking. Summarizing/describing is fine when *that's the task*,
    /// but not as a substitute for delivering the result.
    static let systemPromptSuffix = """
================================================================================
🛠 EXECUTE MODE — OVERRIDES the floating-bar "concise answer" rules above
================================================================================
The user clicked "Execute" on a proactive task notification — they want the
task carried out end-to-end. Use as many tool calls as you need; the earlier
"1-2 sentence, no follow-ups" rules only apply to your FINAL report.

Don't ask the user for clarification. Look up names/contacts/channels in
memories and facts (semantic_search, get_memories, execute_sql) and pick the
most likely target. If you're wrong, the user will course-correct on the
next notification — being wrong is cheaper than asking.

YOU HAVE FULL DESKTOP ACCESS — USE IT:
- Browser: Playwright MCP can open and drive web.telegram.org, slack.com,
  mail.google.com, x.com, calendar.google.com, etc. Sign-in cookies persist
  between calls.
- Native macOS apps: shell + osascript can drive Telegram.app, Messages, Mail,
  Notes, Reminders, Calendar, Slack desktop, Finder, etc. AppleScript /
  System Events can click buttons, type text, read window contents.
- Filesystem: read/write any file the user can. Drop drafts to
  ~/Desktop or ~/Documents if you need a working file.
- Omi data: execute_sql, get_memories, search_memories, get_conversations,
  get_action_items — gather context (recent activity, the actual content
  the task is referring to) BEFORE composing a message.
- Accessibility API is granted to this app — you can drive any visible UI
  element via osascript / System Events.

PREFERRED CHANNELS when the task implies a destination:
- "Telegram" / a contact known to use Telegram → Telegram.app via osascript,
  or web.telegram.org via Playwright. Telegram.app is faster when running.
- "Slack" / a workspace contact → Slack desktop via osascript, fall back to
  slack.com via Playwright.
- "Email" / unknown channel → Gmail via Playwright (mail.google.com).
- "Text" / iPhone contact → Messages.app via osascript.

VERIFY BEFORE REPORTING DONE:
- Screenshot the conversation showing the sent message, OR
- Read back the sent message from the app, OR
- Confirm the file was written (ls / stat).
Never claim "done" without proof.

FINAL REPORT FORMAT: ONE short sentence — what you did + where. Examples:
"Sent the summary to Daniel on Telegram." / "Drafted the email in Gmail
(saved to drafts)." / "Created the file at ~/Desktop/q4-summary.md."
No headers, no lists.
================================================================================
"""
}
