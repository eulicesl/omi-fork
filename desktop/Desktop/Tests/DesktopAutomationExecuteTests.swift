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
}
