import XCTest
@testable import Omi_Computer

/// Sprint 1 reliability changes for the Execute pill — see
/// `desktop/docs/TASK_EXEC_RELIABILITY_SPRINTS.md` for the full plan.
///
/// These tests pin down the prompt-shape and model-selection contract so
/// future refactors of `ProactiveTaskExecute` don't silently regress what
/// the reliability eval depends on.
final class ProactiveTaskExecuteTests: XCTestCase {

    // MARK: - P1 · Notification context plumbed into the prompt

    func testBuildQueryWithoutContextOmitsContextBlock() {
        let q = ProactiveTaskExecute.buildQuery(
            title: "Send Daniel the standup summary",
            message: "Daniel asked for the bullet summary of yesterday's standup."
        )

        XCTAssertFalse(q.contains("# TASK CONTEXT"))
        XCTAssertTrue(q.contains("# EXECUTE"))
        XCTAssertTrue(q.contains("Task: Send Daniel the standup summary"))
        XCTAssertTrue(q.contains("Details: Daniel asked for the bullet summary of yesterday's standup."))
    }

    func testBuildQueryWithFullContextIncludesContextBlock() {
        let ctx = FloatingBarNotificationContext(
            sourceTitle: "Task",
            assistantId: "task",
            sourceApp: "Telegram",
            windowTitle: "Chat with Daniel",
            contextSummary: "Standup discussion with the design team.",
            currentActivity: "Reviewing yesterday's notes",
            reasoning: "Promoted from staged tasks (priority=high, source=conversation)",
            detail: "Send Daniel the bullet summary of yesterday's standup"
        )

        let q = ProactiveTaskExecute.buildQuery(
            title: "Send Daniel",
            message: "Send the standup summary.",
            context: ctx
        )

        // Context block comes first so the model sees it before the imperative.
        let contextRange = q.range(of: "# TASK CONTEXT")
        let executeRange = q.range(of: "# EXECUTE")
        XCTAssertNotNil(contextRange)
        XCTAssertNotNil(executeRange)
        if let c = contextRange, let e = executeRange {
            XCTAssertLessThan(c.lowerBound, e.lowerBound)
        }

        // Every non-nil field surfaces in the prompt so the model doesn't have
        // to fall back to semantic_search / get_memories / execute_sql.
        XCTAssertTrue(q.contains("Source app: Telegram"))
        XCTAssertTrue(q.contains("Window: Chat with Daniel"))
        XCTAssertTrue(q.contains("Detail: Send Daniel the bullet summary of yesterday's standup"))
        XCTAssertTrue(q.contains("Activity at the time the task was promoted: Reviewing yesterday's notes"))
        XCTAssertTrue(q.contains("Context summary: Standup discussion with the design team."))
        XCTAssertTrue(q.contains("Reasoning: Promoted from staged tasks (priority=high, source=conversation)"))
    }

    func testBuildQueryOmitsEmptyContextFields() {
        let ctx = FloatingBarNotificationContext(
            sourceTitle: "Task",
            assistantId: "task",
            sourceApp: "Telegram",
            windowTitle: nil,
            contextSummary: "",
            currentActivity: nil,
            reasoning: nil,
            detail: nil
        )

        let q = ProactiveTaskExecute.buildQuery(
            title: "Send Daniel",
            message: "Send the summary.",
            context: ctx
        )

        XCTAssertTrue(q.contains("# TASK CONTEXT"))
        XCTAssertTrue(q.contains("Source app: Telegram"))
        XCTAssertFalse(q.contains("Window:"), "empty windowTitle should not render")
        XCTAssertFalse(q.contains("Context summary:"), "empty contextSummary should not render")
        XCTAssertFalse(q.contains("Reasoning:"), "nil reasoning should not render")
    }

    func testBuildQueryOmitsContextBlockEntirelyWhenAllFieldsEmpty() {
        let ctx = FloatingBarNotificationContext(
            sourceTitle: "Task",
            assistantId: "task",
            sourceApp: nil,
            windowTitle: nil,
            contextSummary: nil,
            currentActivity: nil,
            reasoning: nil,
            detail: nil
        )

        let q = ProactiveTaskExecute.buildQuery(
            title: "Do thing",
            message: "Do it.",
            context: ctx
        )

        XCTAssertFalse(q.contains("# TASK CONTEXT"), "no heading when every field is empty")
    }

    // MARK: - P5 · Model selection pins Opus

    func testResolveModelDefaultsToOpus() {
        // Defensive: clear any test-leaked override.
        UserDefaults.standard.removeObject(forKey: "OmiExecuteModel")

        XCTAssertEqual(ProactiveTaskExecute.resolveModel(), "claude-opus-4-6")
        XCTAssertEqual(ProactiveTaskExecute.preferredModel, "claude-opus-4-6")
    }

    func testResolveModelHonorsUserDefaultsOverride() {
        UserDefaults.standard.set("claude-sonnet-4-6", forKey: "OmiExecuteModel")
        defer { UserDefaults.standard.removeObject(forKey: "OmiExecuteModel") }

        XCTAssertEqual(ProactiveTaskExecute.resolveModel(), "claude-sonnet-4-6")
    }

    func testResolveModelIgnoresEmptyOverride() {
        UserDefaults.standard.set("   ", forKey: "OmiExecuteModel")
        defer { UserDefaults.standard.removeObject(forKey: "OmiExecuteModel") }

        XCTAssertEqual(
            ProactiveTaskExecute.resolveModel(),
            "claude-opus-4-6",
            "whitespace-only override should fall back to preferredModel"
        )
    }

    // MARK: - System prompt suffix shape (regression guard)

    func testSystemPromptSuffixDeclaresExecuteMode() {
        let s = ProactiveTaskExecute.systemPromptSuffix
        XCTAssertTrue(s.contains("EXECUTE MODE"))
        XCTAssertTrue(s.contains("Never claim \"done\" without proof"))
        XCTAssertTrue(s.contains("PREFERRED CHANNELS"))
    }

    // MARK: - Direct desktop action detector (Chrome refusal fix)

    func testDirectDesktopActionDetectsOpenChromeTask() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open Chrome",
            message: "Open Google Chrome so I can continue browsing."
        )
        XCTAssertEqual(action, .openApplication(name: "Google Chrome"))
    }

    func testDirectDesktopActionDetectsUrlInChromeTask() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open docs",
            message: "Open https://react.dev/learn in Chrome"
        )
        XCTAssertEqual(
            action,
            .openURL(url: URL(string: "https://react.dev/learn")!, browserName: "Google Chrome")
        )
    }

    func testDirectDesktopActionMapsReactDocsRequestToReactURL() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Task",
            message: "Open the React docs in Chrome"
        )
        XCTAssertEqual(
            action,
            .openURL(url: URL(string: "https://react.dev")!, browserName: "Google Chrome")
        )
    }

    func testDirectDesktopActionDetectsSafari() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open Safari",
            message: "Launch Safari"
        )
        XCTAssertEqual(action, .openApplication(name: "Safari"))
    }

    func testDirectDesktopActionDetectsFinder() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open Finder",
            message: "Show me Finder"
        )
        XCTAssertEqual(action, .openApplication(name: "Finder"))
    }

    func testDirectDesktopActionIgnoresUnrelatedTasks() {
        // Conservative-by-design: anything without "open" or "launch" + a
        // known target must defer to the agent path.
        let nilCases: [(String, String)] = [
            ("Send Daniel the standup summary", "Daniel asked for the bullet summary."),
            ("Create /tmp/file.txt", "Write 'hello' to a file"),
            ("Schedule lunch with Anna", "Block 12:30-1:30 tomorrow"),
        ]
        for (title, message) in nilCases {
            XCTAssertNil(
                ProactiveTaskExecute.directDesktopAction(title: title, message: message),
                "expected no direct-action match for: \(title)"
            )
        }
    }

    /// Review feedback (Gemini, P1): the prior detector mixed
    /// notification-context fields (sourceApp, reasoning, detail…) into the
    /// trigger string. A "Summarize the tabs I have open in Chrome" task
    /// whose context happens to mention "open" + "chrome" would get
    /// hijacked. The detector must now key strictly on title + message.
    func testDirectDesktopActionDoesNotTriggerOnAmbientChromeMention() {
        XCTAssertNil(
            ProactiveTaskExecute.directDesktopAction(
                title: "Summarize my tabs",
                message: "Give me a one-line summary of each tab I have open in Chrome right now."
            ),
            "the verb 'open' here describes a state, not an imperative — must defer to the agent"
        )

        XCTAssertNil(
            ProactiveTaskExecute.directDesktopAction(
                title: "Draft an email",
                message: "Write Daniel a reply about the launch I'm planning."
            ),
            "'launch' as a noun in a draft task must not trigger the fast path"
        )
    }

    /// Review feedback (Gemini, P1): "Open https://example.dev in Safari"
    /// used to find the URL but set browserName=nil — routing to the system
    /// default browser instead of Safari. Safari must be detected alongside
    /// Chrome.
    func testDirectDesktopActionRoutesUrlToSafariWhenRequested() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open docs",
            message: "Open https://example.dev in Safari"
        )
        XCTAssertEqual(
            action,
            .openURL(url: URL(string: "https://example.dev")!, browserName: "Safari")
        )
    }

    func testDirectDesktopActionLeavesBrowserNilWhenUnspecified() {
        // No browser mentioned → defer to the system default browser via
        // open(1)'s no-app form. Encoded so a future "always pick Chrome"
        // regression gets caught.
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open the docs",
            message: "Open https://example.dev"
        )
        XCTAssertEqual(
            action,
            .openURL(url: URL(string: "https://example.dev")!, browserName: nil)
        )
    }

    /// Review feedback (Codex P1): the prior detector lowercased the whole
    /// intent text and built the URL from the lowercased slice, mangling
    /// case-sensitive paths, query params, and signed tokens. URL casing
    /// must survive intact end-to-end.
    func testDirectDesktopActionPreservesUrlCasing() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open file",
            message: "Open https://example.com/ApiKey/AbC123?Sig=XyZ"
        )
        XCTAssertEqual(
            action,
            .openURL(
                url: URL(string: "https://example.com/ApiKey/AbC123?Sig=XyZ")!,
                browserName: nil
            )
        )
    }

    /// Review feedback (Codex P2): the prior `lower.contains("chrome")`
    /// scan matched substrings inside hostnames like `developer.chrome.com`
    /// and forced Chrome even when the user didn't ask for it. Browser
    /// inference must require explicit phrasing — the URL host alone is
    /// not consent to override the system default browser.
    func testDirectDesktopActionDoesNotHijackBrowserFromUrlHost() {
        let chromeHost = ProactiveTaskExecute.directDesktopAction(
            title: "Open docs",
            message: "Open https://developer.chrome.com/docs/extensions"
        )
        XCTAssertEqual(
            chromeHost,
            .openURL(
                url: URL(string: "https://developer.chrome.com/docs/extensions")!,
                browserName: nil
            ),
            "URL host containing 'chrome' must not pick Chrome as the browser"
        )

        let safariHost = ProactiveTaskExecute.directDesktopAction(
            title: "Open page",
            message: "Open https://safari-extensions.example.com/release-notes"
        )
        XCTAssertEqual(
            safariHost,
            .openURL(
                url: URL(string: "https://safari-extensions.example.com/release-notes")!,
                browserName: nil
            ),
            "URL host containing 'safari' must not pick Safari as the browser"
        )
    }

    /// Companion: confirms the explicit "in <Browser>" suffix still routes
    /// correctly even when the URL host doesn't mention any browser — so
    /// we know the inference fix didn't accidentally break the supported
    /// "open <URL> in Chrome" pattern.
    func testDirectDesktopActionRoutesUrlToChromeViaSuffix() {
        let action = ProactiveTaskExecute.directDesktopAction(
            title: "Open page",
            message: "Open https://example.dev/path in Google Chrome"
        )
        XCTAssertEqual(
            action,
            .openURL(
                url: URL(string: "https://example.dev/path")!,
                browserName: "Google Chrome"
            )
        )
    }

    func testCompletionActivityTextDoesNotTruncateFinalMessage() {
        let long = String(repeating: "Final task result with enough detail. ", count: 8)
        XCTAssertEqual(
            ProactiveTaskExecute.completionActivityText(from: long),
            long.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func testCompletionActivityTextFallsBackToDoneOnEmptyInput() {
        XCTAssertEqual(ProactiveTaskExecute.completionActivityText(from: ""), "Done")
        XCTAssertEqual(ProactiveTaskExecute.completionActivityText(from: "   \n  "), "Done")
    }

    /// Review feedback (Gemini P1 / Codex P2): a failed direct action must
    /// surface as a `.failed` pill rather than a misleading `.done`. The
    /// contract that makes that possible is `perform(_:)` throwing on a
    /// non-zero `open(1)` exit. Pins that contract — if it ever stops
    /// throwing for an unknown app, `spawnDirectActionForNotification`
    /// silently regresses to "lying success" without any test failing.
    func testPerformThrowsForUnknownApplication() async {
        let unknownAppName = "OmiFastpathTestNonexistentApp987"
        do {
            _ = try await ProactiveTaskExecute.perform(.openApplication(name: unknownAppName))
            XCTFail("perform should throw for an unknown application")
        } catch {
            // Expected. Error message comes from open(1)'s non-zero exit,
            // which we surface back to the user verbatim.
        }
    }
}
