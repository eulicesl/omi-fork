import XCTest
@testable import Omi_Computer

/// Sprint 2 / P2 — pins the gate's classification and verification rules so
/// future refactors don't quietly let "fake done" runs through.
final class ExecuteVerificationGateTests: XCTestCase {

    // MARK: - classify(query:)

    func testClassifyActionableVerbs() {
        let cases: [(String, String)] = [
            ("Send Daniel the standup summary", "send"),
            ("Reply to the email from Jess", "reply"),
            ("Create a file at ~/Desktop/notes.md", "create"),
            ("Schedule the design review for Friday", "schedule"),
            ("Draft a 200-word product update", "draft"),
            ("Post the Q4 metrics to #announce", "post"),
            ("Email the board the latest deck", "email"),
            ("Add the task to my Linear backlog", "add"),
        ]
        for (q, verb) in cases {
            XCTAssertEqual(
                ExecuteVerificationGate.classify(query: q),
                .actionable,
                "expected '\(verb)' to be actionable in query: \(q)"
            )
        }
    }

    func testClassifyResearchVerbs() {
        let cases = [
            "Summarize yesterday's standup",
            "Find references to the Q4 plan",
            "Look up Daniel's email",
            "Explain how the retrieval pipeline works",
            "Tell me who's on the design review",
            "What did Jess say in the thread",
        ]
        for q in cases {
            XCTAssertEqual(
                ExecuteVerificationGate.classify(query: q),
                .research,
                "expected research classification for: \(q)"
            )
        }
    }

    func testClassifyHandlesExecutePreamble() {
        // ProactiveTaskExecute wraps the title in a preamble. The gate must
        // classify on the *title*, not the preamble's "Execute" verb.
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Send Daniel the standup summary
        Details: He asked for the bullet list.
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .actionable
        )
    }

    func testClassifyHandlesExecutePreambleWithResearchTitle() {
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Summarize the design doc
        Details: Pull the highlights.
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research
        )
    }

    func testClassifyEmptyQueryIsResearch() {
        XCTAssertEqual(ExecuteVerificationGate.classify(query: ""), .research)
        XCTAssertEqual(ExecuteVerificationGate.classify(query: "   \n  "), .research)
    }

    // MARK: - Production-shape preambles (TaskPromotionService title="Task")

    /// Regression guard for the bug surfaced by the May 24 baseline eval:
    /// every proactive task notification ships with `title: "Task"` (literal)
    /// from TaskPromotionService, so classifying on the Title line alone made
    /// classify() return `.research` for every actionable production
    /// notification. The gate / retry loop / verification turn (P2/P3/P8)
    /// silently bypassed every real Execute click. Classify must now also
    /// read the Details line, with the production `"New task: "` prefix
    /// stripped.
    func testClassifyUsesDetailsWhenTitleIsLiteralTaskPlaceholder() {
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Task
        Details: New task: Send Daniel the standup summary
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .actionable,
            "Production proactive-task notifications use title='Task' literal — classify must fall through to Details"
        )
    }

    func testClassifyUsesDetailsForProductionCreateTask() {
        // Mirrors the eval's create_file task shape (title="Task",
        // message="Create /tmp/..."). Pre-fix this returned .research and
        // the gate never fired against any of the 10 create_file rows.
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Task
        Details: Create /tmp/omi-execute-eval/alpha.txt with exact text EXECUTE_ALPHA_OK
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .actionable
        )
    }

    func testClassifyStripsNewTaskPrefixCaseInsensitively() {
        // The literal prefix is "New task: " but be tolerant to capitalization
        // drift — TaskPromotionService is the only producer today, but the
        // strip rule shouldn't break if a future caller uses "NEW TASK:".
        for prefix in ["New task: ", "NEW TASK: ", "new task:  "] {
            let prompted = """
            # EXECUTE
            Execute this task end-to-end now.

            Task: Task
            Details: \(prefix)Reply to Jess about the launch
            """
            XCTAssertEqual(
                ExecuteVerificationGate.classify(query: prompted),
                .actionable,
                "prefix '\(prefix)' must be stripped before classification"
            )
        }
    }

    func testClassifyStaysResearchWhenBothLinesAreResearch() {
        // Production title is generic and Details is a research-y phrasing —
        // gate should stay out of the way (no false-positive "actionable").
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Task
        Details: New task: Look up Daniel's email
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research
        )
    }

    /// Actionable-wins semantics: when the Title line is research-y but the
    /// Details line carries the imperative, classify as actionable. This is
    /// the design choice that makes production work — see
    /// `testClassifyUsesDetailsWhenTitleIsLiteralTaskPlaceholder`. Pinning
    /// it as a separate test so a future reviewer who wants "Title wins"
    /// has to consciously delete this case.
    func testClassifyPrefersActionableDetailsOverResearchTitle() {
        let prompted = """
        # EXECUTE
        Execute this task end-to-end now.

        Task: Summarize the design doc
        Details: Send the summary to the channel when you're done.
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .actionable
        )
    }

    /// Review feedback (Codex P2): the v1 `extractLine` used
    /// `query.range(of: prefix)` which returns the FIRST substring match
    /// anywhere in the query. The TASK CONTEXT block has a free-text
    /// `- Detail:` bullet that can contain a literal `Task: ...` from
    /// a user's task description. Without line-anchoring the classifier
    /// pulled the wrong line and — combined with actionable-wins
    /// semantics — could misclassify the verdict. Pin the anchored
    /// behavior with a preamble whose context body contains a deceptive
    /// `Task: ` substring.
    func testClassifyIgnoresFakeTaskPrefixInsideContextBullet() {
        let prompted = """
        # TASK CONTEXT
        - Detail: Earlier the user said "Task: Send Daniel" — but that's
          stale context from a prior conversation.

        # EXECUTE
        Execute this task end-to-end now.

        Task: Summarize the design doc
        Details: Pull the highlights.
        """
        // Pre-fix, extractLine("Task: ") would grab "Send Daniel" from
        // the context bullet → actionable. After the anchor fix it
        // correctly reads "Summarize the design doc" from the EXECUTE
        // block.
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research,
            "extractLine must be line-anchored — a 'Task: ' substring inside a context bullet must not hijack classification"
        )
    }

    func testClassifyIgnoresFakeDetailsPrefixInsideContextBullet() {
        // Symmetric case: a context bullet contains a literal
        // "Details: " substring (less common since the singular
        // "Detail:" is what the context formatter uses, but a user's
        // free-text description could include it). Must not be picked
        // up.
        let prompted = """
        # TASK CONTEXT
        - Detail: The user wrote "Details: Send everyone a reply" in a
          past message, which is no longer relevant.

        # EXECUTE
        Execute this task end-to-end now.

        Task: Task
        Details: New task: Look up Daniel's email
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research,
            "extractLine must isolate the real Details: line in the EXECUTE block, not the substring inside the context bullet"
        )
    }

    /// Review feedback (Codex P2 on v2): line anchoring isn't enough
    /// when a context field's free-text value contains an actual
    /// newline followed by `Details: ...` (or `Task: ...`). The
    /// injected line starts at column 0 of its own line, so a pure
    /// line-anchored regex matches it. Scoping extraction to the
    /// EXECUTE block — the section the prompt-builder fully controls —
    /// closes that hole.
    ///
    /// Concretely: `ctx.detail` formats verbatim into `- Detail: <text>`,
    /// and `<text>` is whatever the user's task description says. A
    /// description like `"First line\nDetails: Send a message now"`
    /// would, pre-fix, plant a real-looking `Details: Send a message
    /// now` line above the EXECUTE block, and actionable-wins would
    /// force the verdict to actionable.
    func testClassifyIgnoresInjectedDetailsLineInContextField() {
        let prompted = """
        # TASK CONTEXT
        - Detail: First line of the description
        Details: Send a message now

        # EXECUTE
        Execute this task end-to-end now.

        Task: Task
        Details: Look up Daniel's email
        """
        // Pre-fix the injected "Details: Send a message now" line above
        // the EXECUTE block would hijack to .actionable. After scoping
        // to the EXECUTE block we read "Look up Daniel's email" →
        // .research.
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research,
            "extractLine must scope to the EXECUTE block; an injected newline+prefix in a context field must not hijack"
        )
    }

    func testClassifyIgnoresInjectedTaskLineInContextField() {
        // Same hijack for the Task: line.
        let prompted = """
        # TASK CONTEXT
        - Detail: previous notes
        Task: Send everyone a reply

        # EXECUTE
        Execute this task end-to-end now.

        Task: Summarize the design doc
        Details: Pull the highlights.
        """
        XCTAssertEqual(
            ExecuteVerificationGate.classify(query: prompted),
            .research,
            "an injected Task: line in a context field must not hijack the real Task: line in the EXECUTE block"
        )
    }

    // MARK: - evaluate(actionClass:invokedToolNames:)

    func testEvaluateResearchIsAlwaysVerified() {
        let res = ExecuteVerificationGate.evaluate(
            actionClass: .research,
            invokedToolNames: []
        )
        XCTAssertEqual(res, .verified)
    }

    func testEvaluateActionableWithNoToolsIsUnverified() {
        let res = ExecuteVerificationGate.evaluate(
            actionClass: .actionable,
            invokedToolNames: []
        )
        switch res {
        case .unverified(let reason):
            XCTAssertTrue(reason.contains("without taking action"))
        case .verified:
            XCTFail("Expected .unverified, got .verified")
        }
    }

    func testEvaluateActionableWithReadOnlyToolsIsUnverified() {
        // semantic_search / get_memories / execute_sql are read-only — they
        // don't satisfy the gate. The model must call a write tool.
        let res = ExecuteVerificationGate.evaluate(
            actionClass: .actionable,
            invokedToolNames: ["semantic_search", "get_memories", "execute_sql"]
        )
        XCTAssertNotEqual(res, .verified)
    }

    func testEvaluateActionableWithWriteToolIsVerified() {
        let writes = [
            "shell",
            "bash",
            "osascript",
            "write_file",
            "apple_notes_add",
            "send_imessage",
            "playwright_navigate",
            "browser_click",
            "create_event",
            "create_action_item",
        ]
        for tool in writes {
            let res = ExecuteVerificationGate.evaluate(
                actionClass: .actionable,
                invokedToolNames: ["semantic_search", tool, "get_memories"]
            )
            XCTAssertEqual(res, .verified, "expected \(tool) to satisfy the gate")
        }
    }

    func testEvaluateMatchesCaseInsensitively() {
        let res = ExecuteVerificationGate.evaluate(
            actionClass: .actionable,
            invokedToolNames: ["BROWSER_CLICK"]
        )
        XCTAssertEqual(res, .verified)
    }

    // MARK: - AgentPillsManager.isRetryableErrorText

    @MainActor
    func testRetryableErrorClassification() {
        XCTAssertTrue(AgentPillsManager.isRetryableErrorText("Response took too long. Try again."))
        XCTAssertTrue(AgentPillsManager.isRetryableErrorText("pi-mono process exited (code 134)"))
        XCTAssertTrue(AgentPillsManager.isRetryableErrorText("AI not available: bridge failed to start"))
        XCTAssertTrue(AgentPillsManager.isRetryableErrorText("connection reset by peer"))
        XCTAssertTrue(AgentPillsManager.isRetryableErrorText("Bridge stalled — no activity for 60s"))

        XCTAssertFalse(AgentPillsManager.isRetryableErrorText("You've reached your monthly free-tier limit. Upgrade to keep chatting."))
        XCTAssertFalse(AgentPillsManager.isRetryableErrorText("Stopped by user"))
        // Plain old "agent said this task is impossible" — not retryable.
        XCTAssertFalse(AgentPillsManager.isRetryableErrorText("That contact isn't in your address book."))
    }
}
