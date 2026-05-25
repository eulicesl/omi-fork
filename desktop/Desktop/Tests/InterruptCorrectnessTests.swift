import XCTest

@testable import Omi_Computer

/// PR 3 Commit A: locks the interrupt-correctness contract surfaced
/// during PR 0a runtime verification.
///
/// The Turn 3a/3b hung-turn bug observed in PostHog telemetry
/// (orphan `chat.turn.started` events with no matching
/// `chat.turn.completed`) traced to `AgentBridge.interrupt()` setting
/// a flag without resuming the pending `messageContinuation`. When
/// the user clicks Cancel mid-tool-execution, the bridge's
/// `waitForMessage()` continuation stays parked indefinitely.
///
/// PR 3's fix: `interrupt()` now resumes the continuation with
/// `BridgeError.stopped`, unblocking `query()`'s for-await-in so the
/// catch block can fire and `chat.turn.completed(outcome: .interrupted)`
/// emits as expected.
///
/// We can't construct a real AgentBridge in unit tests (it spawns a
/// subprocess). Tests below verify the contract pieces that the
/// real bridge depends on — the FakeAgentBridge harness from PR 0b
/// covers the end-to-end interrupt-during-tool flow.
final class InterruptCorrectnessTests: XCTestCase {

  /// Fake-bridge scenario validates that an interrupt during a tool's
  /// activity-started phase, BEFORE any subsequent bridge event
  /// arrives, halts the run with `.interrupted` outcome and does NOT
  /// emit a `toolActivity completed` callback.
  func testInterruptDuringActiveToolHaltsWithoutSpuriousCompletion() async {
    let script = FakeBridgeScenario.interruptDuringTool(
      toolName: "execute_sql",
      interruptAfterMs: 2_000
    )
    let bridge = FakeAgentBridge(script: script)
    await bridge.scheduleInterrupt(atMs: 5_000)
    let record = await bridge.runInstant()

    XCTAssertEqual(record.outcome, .interrupted)
    XCTAssertTrue(record.callbacks.contains(.toolUse(callId: "call-1", name: "execute_sql")))
    XCTAssertTrue(record.callbacks.contains(
      .toolActivity(name: "execute_sql", status: "started", toolUseId: "call-1")
    ))
    // The whole point: no spurious tool-completion callback after
    // interrupt. Without the fix, the bridge would hang here and
    // never emit anything else.
    XCTAssertFalse(record.callbacks.contains(
      .toolActivity(name: "execute_sql", status: "completed", toolUseId: "call-1")
    ))
  }

  /// Partial assistant text observed before interrupt must be
  /// preserved in the record — the user shouldn't lose the visible
  /// streaming output just because they cancelled the turn.
  func testInterruptPreservesPartialDeltas() async {
    let script = FakeBridgeScript(
      name: "interrupt_after_partial_text",
      events: [
        .init(atMs: 0, event: .initSession(sessionId: "fake")),
        .init(atMs: 100, event: .textDelta(text: "Hello, ")),
        .init(atMs: 200, event: .textDelta(text: "the answer is")),
        // Long pause; interrupt fires before next event.
        .init(atMs: 30_000, event: .textDelta(text: " 42.")),
        .init(atMs: 30_100, event: .result(
          text: "Hello, the answer is 42.",
          sessionId: "fake",
          costUsd: nil,
          inputTokens: 0,
          outputTokens: 0,
          cacheReadTokens: 0,
          cacheWriteTokens: 0
        )),
      ]
    )
    let bridge = FakeAgentBridge(script: script)
    await bridge.scheduleInterrupt(atMs: 1_000)
    let record = await bridge.runInstant()

    XCTAssertEqual(record.outcome, .interrupted)
    let deltas = record.callbacks.compactMap { cb -> String? in
      if case .textDelta(let s) = cb { return s }
      return nil
    }
    XCTAssertEqual(deltas, ["Hello, ", "the answer is"])
  }

  // MARK: - BridgeError.stopped semantics

  /// Sanity check: BridgeError.stopped exists and is the case
  /// `interrupt()` resumes the continuation with. If a future refactor
  /// renames the case, this test fails and forces the author to
  /// update both interrupt() and ChatProvider's catch block.
  func testBridgeErrorStoppedCaseExists() {
    let error: BridgeError = .stopped
    if case .stopped = error {
      // ok
    } else {
      XCTFail("BridgeError.stopped no longer exists — interrupt() relies on it")
    }
  }
}
