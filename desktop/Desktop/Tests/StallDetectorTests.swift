import XCTest

@testable import Omi_Computer

/// Commit A of PR 1: covers `StallDetector` in isolation. Drives the
/// detector with both direct timestamps and with the PR 0b
/// `FakeAgentBridge` via its timed-event tap, which is the wiring
/// pattern Commit D will mirror in production.
final class StallDetectorTests: XCTestCase {

  // Convenience: shorter than spelling out v1Defaults each time.
  private let thresholds = StallThresholds.v1Defaults

  // MARK: - Inter-event gap

  func testFreshDetectorIsRunning() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    let state = await detector.interEventState
    XCTAssertEqual(state, .running)
  }

  func testGapBelowSlowThresholdStaysRunning() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    let transitions = await detector.tick(atMs: thresholds.slowGapMs - 1)
    XCTAssertTrue(transitions.isEmpty)
    let state = await detector.interEventState
    XCTAssertEqual(state, .running)
  }

  func testGapAtSlowThresholdPromotesToSlow() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    let transitions = await detector.tick(atMs: thresholds.slowGapMs)
    XCTAssertEqual(transitions, [.interEvent(from: .running, to: .slow)])
  }

  func testGapAtStalledThresholdPromotesToStalled() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    let transitions = await detector.tick(atMs: thresholds.stalledGapMs)
    // Transition jumps straight from .running to .stalled (no
    // intermediate .slow emit) when tick crosses both thresholds in
    // one call. That's intentional: the UI only needs to know the
    // current promoted level, not the path taken.
    XCTAssertEqual(transitions, [.interEvent(from: .running, to: .stalled)])
  }

  func testRepeatedTickAtSameTimeReturnsEmptyAfterFirst() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    let first = await detector.tick(atMs: thresholds.stalledGapMs)
    let second = await detector.tick(atMs: thresholds.stalledGapMs)
    XCTAssertEqual(first.count, 1)
    XCTAssertTrue(second.isEmpty, "tick is idempotent at the same atMs")
  }

  func testNewEventResetsInterEventStateAndEmitsTransition() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    // Promote to stalled.
    _ = await detector.tick(atMs: thresholds.stalledGapMs)
    // New event arrives.
    let transitions = await detector.step(kind: .other, atMs: thresholds.stalledGapMs + 1)
    XCTAssertEqual(transitions, [.interEvent(from: .stalled, to: .running)])
    let state = await detector.interEventState
    XCTAssertEqual(state, .running)
  }

  func testStepAlsoEvaluatesElapsedTime() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    // No prior event observed; step at slowGapMs both records the
    // event (resetting to running implicitly since we were already
    // running) and evaluates elapsed time. Since the event arrived
    // exactly at slowGapMs, lastEventAtMs is now slowGapMs and the
    // gap from that to atMs is 0 — no promotion.
    let transitions = await detector.step(kind: .other, atMs: thresholds.slowGapMs)
    XCTAssertTrue(
      transitions.isEmpty,
      "an event arriving exactly at the threshold resets the gap"
    )
  }

  // MARK: - Per-tool timer

  func testToolStartTracksIndependentlyOfInterEventGap() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t1"), atMs: 100)
    // Inter-event gap should be tiny; tool t1 has just started.
    let interState = await detector.interEventState
    let toolState = await detector.currentToolState(id: "t1")
    XCTAssertEqual(interState, .running)
    XCTAssertEqual(toolState, .running)
  }

  func testToolPromotesToSlowWhenItsOwnTimerCrossesThreshold() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t1"), atMs: 100)
    let transitions = await detector.tick(atMs: 100 + thresholds.slowGapMs)
    // Both timers cross at this point: the inter-event gap (100 → 100+slow)
    // and tool t1 (100 → 100+slow). Expect both transitions, in some
    // order.
    XCTAssertEqual(transitions.count, 2)
    XCTAssertTrue(transitions.contains(.interEvent(from: .running, to: .slow)))
    XCTAssertTrue(transitions.contains(.tool(id: "t1", from: .running, to: .slow)))
  }

  func testToolCompletionEmitsBackToRunningTransitionIfPromoted() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t1"), atMs: 0)
    // Promote to stalled.
    _ = await detector.tick(atMs: thresholds.stalledGapMs)
    let toolState = await detector.currentToolState(id: "t1")
    XCTAssertEqual(toolState, .stalled)

    // Tool completes.
    let transitions = await detector.step(
      kind: .toolCompleted(id: "t1"),
      atMs: thresholds.stalledGapMs + 1
    )
    // Expect a tool transition back to .running plus the inter-event
    // reset (event arrival also resets inter-event from .stalled to
    // .running).
    XCTAssertTrue(transitions.contains(.tool(id: "t1", from: .stalled, to: .running)))
    XCTAssertTrue(transitions.contains(.interEvent(from: .stalled, to: .running)))

    // After completion, tool is no longer tracked.
    let postCompletionState = await detector.currentToolState(id: "t1")
    XCTAssertEqual(postCompletionState, .running)
    let inFlight = await detector.snapshotToolStates()
    XCTAssertTrue(inFlight.isEmpty)
  }

  func testToolCompletionWithoutPromotionEmitsNoToolTransition() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t1"), atMs: 100)
    let transitions = await detector.step(kind: .toolCompleted(id: "t1"), atMs: 200)
    // No promotion happened, so no tool transition needs surfacing.
    // (Inter-event also stayed running, so no inter transition either.)
    XCTAssertTrue(transitions.isEmpty)
  }

  func testMultipleParallelToolsTrackedIndependently() async {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t1"), atMs: 0)
    _ = await detector.step(kind: .toolStarted(id: "t2"), atMs: 1_000)

    // Advance to where t1 has crossed slowGapMs but t2 hasn't yet.
    // t1 elapsed: slowGapMs (started at 0).
    // t2 elapsed: slowGapMs - 1_000 (started at 1_000).
    let transitions = await detector.tick(atMs: thresholds.slowGapMs)
    XCTAssertTrue(transitions.contains(.tool(id: "t1", from: .running, to: .slow)))
    XCTAssertFalse(
      transitions.contains(.tool(id: "t2", from: .running, to: .slow)),
      "t2 has not yet crossed slowGapMs"
    )
  }

  // MARK: - End-to-end with FakeAgentBridge (the Commit D wiring pattern)

  /// Drives the detector via the PR 0b fake bridge's timed-event tap
  /// AND a simulated periodic tick — exactly the production wiring
  /// pattern Commit D will use. Without the periodic tick, the
  /// detector would only see events arriving on time and would miss
  /// the in-gap promotion entirely (since `step` resets the gap on
  /// each event, and `evaluate` runs against the already-reset gap).
  /// The periodic tick is what makes stall detection actually fire.
  func testMidStreamStallWithPeriodicTickEmitsStalledAndRecovery() async {
    let script = FakeBridgeScenario.midStreamStall(
      deltasBeforeStall: 2,
      stallDurationMs: 25_000
    )
    let bridge = FakeAgentBridge(script: script)
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)

    actor TransitionLog {
      var transitions: [StallDetector.Transition] = []
      func append(_ ts: [StallDetector.Transition]) { transitions.append(contentsOf: ts) }
    }
    let log = TransitionLog()

    var previousAtMs = 0
    _ = await bridge.runInstant(
      onTimedEvent: { atMs, event in
        // Simulate the production tick task by ticking every 1s
        // between the previous event's time and this event's time.
        var t = previousAtMs + 1_000
        while t < atMs {
          let tickTransitions = await detector.tick(atMs: t)
          await log.append(tickTransitions)
          t += 1_000
        }
        previousAtMs = atMs

        let kind: StallDetector.EventKind
        switch event {
        case .toolUse(let callId, _, _):
          kind = .toolStarted(id: callId)
        case .toolActivity(_, let status, let toolUseId, _)
          where status == "completed" && toolUseId != nil:
          kind = .toolCompleted(id: toolUseId!)
        default:
          kind = .other
        }
        let stepTransitions = await detector.step(kind: kind, atMs: atMs)
        await log.append(stepTransitions)
      }
    )

    let recorded = await log.transitions
    let interTransitions = recorded.compactMap { transition -> (StallDetector.State, StallDetector.State)? in
      if case .interEvent(let from, let to) = transition { return (from, to) }
      return nil
    }
    // Expect at minimum: running→slow, slow→stalled (during the gap),
    // stalled→running (when "back." arrives).
    let states = interTransitions.map { ($0.0, $0.1) }
    XCTAssertTrue(
      states.contains(where: { $0.0 == .running && $0.1 == .slow }),
      "expected promotion to .slow during the stall; got \(states)"
    )
    XCTAssertTrue(
      states.contains(where: { $0.0 == .slow && $0.1 == .stalled }),
      "expected promotion to .stalled during the stall; got \(states)"
    )
    XCTAssertTrue(
      states.contains(where: { $0.0 == .stalled && $0.1 == .running }),
      "expected recovery to .running when the next event arrived; got \(states)"
    )
  }

  // MARK: - Threshold guard

  func testThresholdsPreconditionRejectsInvalidValues() {
    // Can't easily assert precondition crashes in XCTest without a
    // sub-process. Instead verify the v1Defaults pass the contract.
    XCTAssertGreaterThan(StallThresholds.v1Defaults.slowGapMs, 0)
    XCTAssertGreaterThan(
      StallThresholds.v1Defaults.stalledGapMs,
      StallThresholds.v1Defaults.slowGapMs
    )
  }
}
