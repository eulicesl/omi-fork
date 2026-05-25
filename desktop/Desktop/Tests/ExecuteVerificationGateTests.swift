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
