import XCTest

@testable import Omi_Computer

/// PR 3 Commit B: contract tests for the per-tool timeout policy.
final class ToolTimeoutPolicyTests: XCTestCase {

  // MARK: - Lookup

  func testLookupReturnsConfiguredTimeoutForEachPiMonoTool() {
    let p = ToolTimeoutPolicy.v1Defaults
    XCTAssertEqual(p.seconds(for: "execute_sql"), 15)
    XCTAssertEqual(p.seconds(for: "semantic_search"), 20)
    XCTAssertEqual(p.seconds(for: "search_tasks"), 20)
    XCTAssertEqual(p.seconds(for: "get_daily_recap"), 25)
    XCTAssertEqual(p.seconds(for: "complete_task"), 5)
    XCTAssertEqual(p.seconds(for: "delete_task"), 5)
    XCTAssertEqual(p.seconds(for: "save_knowledge_graph"), 30)
  }

  func testLookupReturnsDefaultForUnknownTool() {
    let p = ToolTimeoutPolicy.v1Defaults
    XCTAssertEqual(p.seconds(for: "some_future_tool"), p.defaultSeconds)
  }

  /// Tools delivered through the MCP relay arrive with names like
  /// `mcp__omi-tools__execute_sql`. The policy strips the `mcp__`
  /// prefix so a single configured key covers both delivery paths.
  func testLookupStripsMcpPrefix() {
    let p = ToolTimeoutPolicy.v1Defaults
    XCTAssertEqual(p.seconds(for: "mcp__omi-tools__execute_sql"), 15)
    XCTAssertEqual(p.seconds(for: "mcp__anything__delete_task"), 5)
  }

  /// Every tool advertised in the piMono `<tools>` block of
  /// `ChatPrompts.desktopChat` (via `ChatToolExecutor.piMonoChatToolNames`)
  /// must have a configured timeout — no piMono tool falls back to
  /// the generic default unless that's intentional.
  func testEveryPiMonoToolHasAConfiguredTimeout() {
    let p = ToolTimeoutPolicy.v1Defaults
    for tool in ChatToolExecutor.piMonoChatToolNames {
      XCTAssertNotNil(
        p.timeoutsSeconds[tool],
        "ToolTimeoutPolicy.v1Defaults is missing a timeout for '\(tool)'. "
          + "Either add a timeout or document why this tool should use the generic default."
      )
    }
  }

  // MARK: - withToolTimeout helper

  /// Fast operation returns success, not timeout. Uses a tiny sleep so
  /// the operation actually awaits — synchronous return paths can
  /// short-circuit task-group scheduling and mask real bugs.
  func testWithToolTimeoutReturnsSuccessForFastOperation() async {
    let outcome = await withToolTimeout(
      seconds: 5,
      operation: {
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
        return "done"
      }
    )
    if case .success(let value) = outcome {
      XCTAssertEqual(value, "done")
    } else {
      XCTFail("expected .success, got \(outcome)")
    }
  }

  /// Operation longer than the deadline returns timeout.
  /// Uses a 1s deadline + 3s operation to keep the test fast while
  /// still exercising the real timer path.
  func testWithToolTimeoutReturnsTimedOutForSlowOperation() async {
    let outcome = await withToolTimeout(
      seconds: 1,
      operation: {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return "should-never-be-returned"
      }
    )
    if case .timedOut(let elapsed) = outcome {
      XCTAssertEqual(elapsed, 1)
    } else {
      XCTFail("expected .timedOut, got \(outcome)")
    }
  }
}
