import XCTest
@testable import Omi_Computer

final class DesktopAutomationExecuteTests: XCTestCase {
    func testExecuteSpawnRequestDecodesSnakeCaseContextAndBuildsQuery() throws {
        let json = """
        {
          "notification_id": "11111111-1111-1111-1111-111111111111",
          "model": "claude-sonnet-4-6",
          "notification": {
            "title": "Task",
            "message": "Create /tmp/omi-eval/a.txt with hello",
            "context": {
              "source_app": "Codex",
              "window_title": "Eval",
              "context_summary": "Local reliability test",
              "current_activity": "Running the deterministic eval",
              "reasoning": "Prove Execute completion",
              "detail": "Write the requested file"
            }
          }
        }
        """

        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(request.notificationId?.uuidString, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(request.model, "claude-sonnet-4-6")
        XCTAssertTrue(request.query.contains("# TASK CONTEXT"))
        XCTAssertTrue(request.query.contains("Source app: Codex"))
        XCTAssertTrue(request.query.contains("Window: Eval"))
        XCTAssertTrue(request.query.contains("Details: Create /tmp/omi-eval/a.txt with hello"))
    }

    func testExecuteSpawnRequestOmitsEmptyContextBlock() throws {
        let json = """
        {
          "notification": {
            "title": "Task",
            "message": "Create /tmp/omi-eval/a.txt with hello",
            "context": {}
          }
        }
        """

        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )

        XCTAssertFalse(request.query.contains("# TASK CONTEXT"))
        XCTAssertTrue(request.query.contains("# EXECUTE"))
    }

    // MARK: - Direct desktop action exposure (bridge ↔ UI parity)

    /// Mirrors `FloatingControlBarView`'s Execute button — bridge callers
    /// (eval harness, external automation) must see the same fast-path
    /// classification UI clicks do. Without this accessor the bridge would
    /// silently send "Open Chrome" through the LLM (the regression the
    /// detector exists to fix).
    func testExecuteSpawnRequestExposesDirectDesktopActionForOpenChrome() throws {
        let json = """
        {
          "notification": {
            "title": "Open Chrome",
            "message": "Open Google Chrome so I can keep browsing."
          }
        }
        """
        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(request.directDesktopAction, .openApplication(name: "Google Chrome"))
    }

    func testExecuteSpawnRequestExposesDirectDesktopActionForOpenUrlInSafari() throws {
        let json = """
        {
          "notification": {
            "title": "Open page",
            "message": "Open https://example.dev/path in Safari"
          }
        }
        """
        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(
            request.directDesktopAction,
            .openURL(url: URL(string: "https://example.dev/path")!, browserName: "Safari")
        )
    }

    /// The detector deliberately ignores notification context — the bridge
    /// accessor must too. This guards against a future regression where
    /// somebody re-introduces context into the bridge-side path "for
    /// completeness," reviving the false-positive class the PR review
    /// resolved (an incidental "open" in `reasoning` hijacking the fast
    /// path).
    func testExecuteSpawnRequestDirectDesktopActionIgnoresContext() throws {
        let json = """
        {
          "notification": {
            "title": "Summarize my tabs",
            "message": "Give me a one-line summary of each tab.",
            "context": {
              "source_app": "Google Chrome",
              "reasoning": "User opened Chrome a moment ago",
              "detail": "Launch a summary"
            }
          }
        }
        """
        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(
            request.directDesktopAction,
            "context-only 'open'/'launch'/'chrome' mentions must not trigger the fast path"
        )
    }

    func testExecuteSpawnRequestDirectDesktopActionDefersWhenNoMatch() throws {
        let json = """
        {
          "notification": {
            "title": "Send Daniel the standup summary",
            "message": "Reply to Daniel on Telegram with the bullet summary."
          }
        }
        """
        let request = try JSONDecoder().decode(
            DesktopAutomationExecuteSpawnRequest.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(request.directDesktopAction, "actionable LLM task must defer to the agent path")
    }
}
