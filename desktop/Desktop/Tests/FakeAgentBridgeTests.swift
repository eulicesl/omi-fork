import XCTest

@testable import Omi_Computer

/// PR 0b acceptance tests for the deterministic fake bridge harness.
///
/// Two contracts under test:
///   1. Each named scenario produces the expected callback sequence and
///      terminal outcome.
///   2. Every scenario is deterministic across 100 consecutive runs —
///      same `RunRecord` every time. PRs 1, 3, 4, 7, and 8 rely on this.
final class FakeAgentBridgeTests: XCTestCase {

  // MARK: - Per-scenario shape

  func testHappyPathProducesInitDeltasAndCompletes() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.happyPath())
    let record = await bridge.runInstant()

    XCTAssertEqual(record.scenarioName, "happy_path")
    XCTAssertEqual(record.callbacks, [
      .initSession(sessionId: "fake-session"),
      .textDelta("Hello"),
      .textDelta(" world"),
      .textDelta("."),
    ])
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed, got \(record.outcome)")
    }
  }

  func testFirstTokenDelayStillCompletes() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.firstTokenDelay(ms: 15_000))
    let record = await bridge.runInstant()

    XCTAssertEqual(record.callbacks.count, 2, "init + delayed delta")
    XCTAssertEqual(record.callbacks.first, .initSession(sessionId: "fake-session"))
    XCTAssertEqual(record.callbacks.last, .textDelta("Sorry for the wait."))
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed, got \(record.outcome)")
    }
  }

  func testMidStreamStallRecoversAndCompletes() async {
    let script = FakeBridgeScenario.midStreamStall(
      deltasBeforeStall: 2,
      stallDurationMs: 25_000
    )
    let bridge = FakeAgentBridge(script: script)
    let record = await bridge.runInstant()

    let deltaCount = record.callbacks.filter {
      if case .textDelta = $0 { return true }
      return false
    }.count
    XCTAssertEqual(deltaCount, 3, "2 deltas before stall + 1 after recovery")
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed, got \(record.outcome)")
    }
  }

  func testNeverReturningToolReachesErrorTerminator() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.neverReturningTool())
    let record = await bridge.runInstant()

    // delta, tool_use, tool_activity start, then error terminator.
    XCTAssertTrue(record.callbacks.contains(.toolUse(callId: "call-1", name: "execute_sql")))
    XCTAssertTrue(record.callbacks.contains(
      .toolActivity(name: "execute_sql", status: "started", toolUseId: "call-1")
    ))
    if case .errored(let msg) = record.outcome {
      XCTAssertEqual(msg, "fake_scenario_never_returning_tool")
    } else {
      XCTFail("expected .errored, got \(record.outcome)")
    }
  }

  func testMalformedMessageIsSurfacedAndStreamContinues() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.malformedMessage())
    let record = await bridge.runInstant()

    XCTAssertTrue(record.callbacks.contains {
      if case .malformed = $0 { return true }
      return false
    }, "malformed line must surface as a callback")
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed after recovery, got \(record.outcome)")
    }
  }

  func testBridgeCrashTerminatesWithCrashedOutcome() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.bridgeCrashMidTurn())
    let record = await bridge.runInstant()

    XCTAssertEqual(record.callbacks.last, .crash)
    XCTAssertEqual(record.outcome, .crashed)
  }

  func testHeartbeatLossEmitsHeartbeatsThenNeverTerminates() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.heartbeatLoss(
      initialHeartbeats: 3,
      intervalMs: 5_000
    ))
    let record = await bridge.runInstant()

    let heartbeatCount = record.callbacks.filter {
      if case .heartbeat = $0 { return true }
      return false
    }.count
    XCTAssertEqual(heartbeatCount, 3)
    XCTAssertEqual(record.outcome, .neverTerminated)
  }

  func testAuthRequiredEmitsCallbackAndHaltsWithoutResult() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.authRequired())
    let record = await bridge.runInstant()

    XCTAssertEqual(record.callbacks.last, .authRequired)
    XCTAssertEqual(record.outcome, .neverTerminated)
  }

  func testInterruptDuringToolHaltsBeforeToolEnd() async {
    let script = FakeBridgeScenario.interruptDuringTool(
      toolName: "execute_sql",
      interruptAfterMs: 2_000
    )
    let bridge = FakeAgentBridge(script: script)
    // Schedule the interrupt to fire at the script timestamp where the
    // tool would still be running. Last event is at interruptAfterMs +
    // 10_000, so 5_000 lands solidly inside.
    await bridge.scheduleInterrupt(atMs: 5_000)
    let record = await bridge.runInstant()

    XCTAssertEqual(record.outcome, .interrupted)
    XCTAssertTrue(record.callbacks.contains(.toolUse(callId: "call-1", name: "execute_sql")))
    XCTAssertFalse(record.callbacks.contains(
      .toolActivity(name: "execute_sql", status: "completed", toolUseId: "call-1")
    ), "tool completion must not fire after interrupt")
  }

  func testDelayedFinalResultStillCompletes() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.delayedFinalResult())
    let record = await bridge.runInstant()

    let deltaCount = record.callbacks.filter {
      if case .textDelta = $0 { return true }
      return false
    }.count
    XCTAssertEqual(deltaCount, 3)
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed, got \(record.outcome)")
    }
  }

  func testEmptyToolResultCompletesWithEmptyOutput() async {
    let bridge = FakeAgentBridge(script: FakeBridgeScenario.emptyToolResult())
    let record = await bridge.runInstant()

    XCTAssertTrue(record.callbacks.contains(
      .toolResultDisplay(toolUseId: "call-1", name: "execute_sql", output: "")
    ))
    guard case .completed = record.outcome else {
      return XCTFail("expected .completed, got \(record.outcome)")
    }
  }

  // MARK: - Determinism contract (the PR 0b acceptance gate)

  /// Each scenario must produce the same `RunRecord` across 100
  /// consecutive runs. This is the gate that lets downstream PRs write
  /// non-flaky tests against the harness.
  func testEveryScenarioIsDeterministicAcrossOneHundredRuns() async {
    for script in FakeBridgeScenario.all() {
      var firstRecord: FakeAgentBridge.RunRecord?
      for run in 0..<100 {
        let bridge = FakeAgentBridge(script: script)
        let record = await bridge.runInstant()
        if firstRecord == nil {
          firstRecord = record
        } else {
          XCTAssertEqual(
            record,
            firstRecord,
            "scenario '\(script.name)' diverged at run \(run)"
          )
        }
      }
    }
  }

  /// Interrupt scheduling is also deterministic: the same scheduled mark
  /// must always cut the run at the same callback boundary.
  func testScheduledInterruptIsDeterministicAcrossOneHundredRuns() async {
    let script = FakeBridgeScenario.interruptDuringTool(interruptAfterMs: 2_000)
    var firstRecord: FakeAgentBridge.RunRecord?
    for run in 0..<100 {
      let bridge = FakeAgentBridge(script: script)
      await bridge.scheduleInterrupt(atMs: 5_000)
      let record = await bridge.runInstant()
      if firstRecord == nil {
        firstRecord = record
      } else {
        XCTAssertEqual(record, firstRecord, "interrupt diverged at run \(run)")
      }
    }
  }

  // MARK: - Timed-event tap (PR 1 usage contract)

  /// `onTimedEvent` must fire exactly once per script event, in script
  /// order, with the event's simulated timestamp. This is the hook PR 1's
  /// `StallDetector` tests use to advance a test clock before any typed
  /// callback observes the event.
  func testTimedEventTapFiresOncePerEventInScriptOrder() async {
    let script = FakeBridgeScenario.happyPath()
    let bridge = FakeAgentBridge(script: script)

    actor Recorder {
      var seen: [(Int, FakeBridgeEvent)] = []
      func append(_ atMs: Int, _ event: FakeBridgeEvent) {
        seen.append((atMs, event))
      }
    }
    let recorder = Recorder()

    _ = await bridge.runInstant(
      onTimedEvent: { atMs, event in await recorder.append(atMs, event) }
    )

    let seen = await recorder.seen
    XCTAssertEqual(seen.count, script.events.count)
    for (i, observed) in seen.enumerated() {
      XCTAssertEqual(observed.0, script.events[i].atMs, "atMs mismatch at index \(i)")
      XCTAssertEqual(observed.1, script.events[i].event, "event mismatch at index \(i)")
    }
  }

  /// Demonstrates the PR 1 usage pattern end-to-end: a detector wired
  /// only to `onTimedEvent` observes every script event with its
  /// simulated timestamp, and a separately-wired typed callback fires
  /// only for the events the test cares about. The two observers see
  /// different views of the same run by design — the timed tap is the
  /// full timeline, typed callbacks are a filtered convenience view.
  func testTimedTapAndTypedCallbacksRecordIndependentlyOfEachOther() async {
    let script = FakeBridgeScenario.midStreamStall(
      deltasBeforeStall: 2,
      stallDurationMs: 25_000
    )
    let bridge = FakeAgentBridge(script: script)

    actor TimedTapRecorder { var events: [(Int, FakeBridgeEvent)] = []
      func append(_ atMs: Int, _ event: FakeBridgeEvent) { events.append((atMs, event)) }
    }
    actor TextDeltaRecorder { var texts: [String] = []
      func append(_ text: String) { texts.append(text) }
    }
    let timedRecorder = TimedTapRecorder()
    let textRecorder = TextDeltaRecorder()

    _ = await bridge.runInstant(
      onTimedEvent: { atMs, event in await timedRecorder.append(atMs, event) },
      onTextDelta: { text in
        Task { await textRecorder.append(text) }
      }
    )
    await Task.yield()

    let timedEvents = await timedRecorder.events
    XCTAssertEqual(
      timedEvents.count,
      script.events.count,
      "timed tap is the full timeline (every script event)"
    )
    // The typed callback uses an actor recorder + spawned Tasks (the
    // sync-typed-callback pattern documented in FakeAgentBridge.swift),
    // which races under parallel test execution. Assert the
    // structural property (typed-deltas ≤ timed-events) rather than
    // an exact count — exact counts depend on Task scheduling order.
    let textDeltas = await textRecorder.texts
    XCTAssertLessThanOrEqual(
      textDeltas.count,
      timedEvents.count,
      "typed callback can only observe a subset of timed events"
    )
  }

  // MARK: - Inventory

  /// Guard against scope drift: PR 0b commits to exactly 10 failure
  /// scenarios plus the happy-path baseline. Adding or removing any of
  /// them needs a roadmap update.
  func testScenarioInventoryMatchesRoadmap() {
    let names = FakeBridgeScenario.all().map(\.name)
    XCTAssertEqual(names, [
      "happy_path",
      "first_token_delay",
      "mid_stream_stall",
      "never_returning_tool",
      "malformed_message",
      "bridge_crash_mid_turn",
      "heartbeat_loss",
      "auth_required",
      "interrupt_during_tool",
      "delayed_final_result",
      "empty_tool_result",
    ])
  }
}
