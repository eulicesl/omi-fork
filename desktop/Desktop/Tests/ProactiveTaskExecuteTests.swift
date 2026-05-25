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
}
