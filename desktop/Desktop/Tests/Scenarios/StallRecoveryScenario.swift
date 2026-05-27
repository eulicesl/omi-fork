import Foundation

@testable import Omi_Computer

// MARK: - StallRecoveryScenario (PR 7 scaffolding)
//
// Scenario #6 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Behavioral scenario — exercises PRs 1 + 3 + 4 end-to-end against
// FakeAgentBridge (no real LLM, no auth, no VM). Verifies the stall
// signal pipeline works as designed:
//
//   1. Start a turn.
//   2. FakeAgentBridge fires a tool-call-started event, then deliberately
//      withholds further events past `slowGapMs` (8s by default).
//   3. ChatProvider's StallDetector advances the tool-call status from
//      `.running` -> `.slow`.
//   4. Beyond `stalledGapMs` (20s), status advances to `.stalled`.
//   5. The runner then completes the turn (timeout fires per PR 3),
//      assertions confirm:
//        - the final tool-call status was `.stalled` before it was
//          surfaced as `.failed` due to timeout
//        - `currentError` lands on `.timeout(toolName:)` per PR 4
//        - the recovery card's primary action is `.retry`
//
// Runs against BOTH modes. Mode is treated as a transparent label
// here because the stall signal pipeline is mode-agnostic (the bridge
// is fake either way).

enum StallRecoveryScenario: ChatScenario {
  static let id = "stall_recovery"

  static let description =
    "FakeAgentBridge withholds events past slowGapMs and stalledGapMs " +
    "thresholds; assert tool-call status transitions running -> slow -> " +
    "stalled and the timeout recovery card lands on .retry."

  /// The synthetic prompt sent through ChatProvider. Content is
  /// irrelevant — FakeAgentBridge ignores it; the assertions are
  /// about state transitions, not response content.
  static let userPrompt = "[stall-recovery harness — prompt content unused]"

  /// Expected tool-call status sequence observed via ChatProvider.
  /// The runner asserts each transition happens within an explicit
  /// time window from the prior state.
  static let expectedStatusSequence: [String] = ["running", "slow", "stalled", "failed"]

  /// Wall-clock ceiling. Must exceed `stalledGapMs` + the timeout
  /// policy ceiling for the synthetic tool, with a comfortable
  /// buffer for test-host jitter.
  static let timeoutSeconds: Int = 60

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    let startedAt = Date()
    let durationMs = { Int(Date().timeIntervalSince(startedAt) * 1000) }

    // FakeBridgeScenario.neverReturningTool default waits 60s — well past
    // stalledGapMs (20s). Detector must promote both the inter-event
    // gap AND the per-tool timer through running -> slow -> stalled.
    let script = FakeBridgeScenario.neverReturningTool(toolName: "execute_sql")
    let result = await BehavioralRunner.drive(script)

    // Assert: the inter-event state promoted to a "something is wrong"
    // signal — either `.stalled` (PR 1) or `.bridgeUnresponsive` (PR 8).
    // The neverReturningTool script doesn't emit heartbeats, so the
    // detector classifies the trailing silence as `.bridgeUnresponsive`
    // (consistent with "bridge probably dead"). A variant of this
    // scenario with heartbeats would land at `.stalled` instead.
    // Either is a valid stall signal that the recovery card handles.
    let interEventReachedStallOrUnresponsive =
      BehavioralRunner.transitionsReachedInterEvent(result.transitions, target: .stalled)
      || BehavioralRunner.transitionsReachedInterEvent(result.transitions, target: .bridgeUnresponsive)
    if !interEventReachedStallOrUnresponsive {
      return ChatScenarioOutcome(
        scenarioId: Self.id, mode: mode,
        outcome: .failed(reason:
          "expected inter-event state to promote to .stalled or .bridgeUnresponsive; final state was \(result.finalInterEventState)"
        ),
        durationMs: durationMs()
      )
    }

    // Assert: the per-tool timer also reached `.stalled`. Per-tool
    // stalls are how PR 1 surfaces "this specific tool is hanging".
    let toolReachedStalled = BehavioralRunner.transitionsReachedTool(
      result.transitions, target: .stalled
    )
    if !toolReachedStalled {
      return ChatScenarioOutcome(
        scenarioId: Self.id, mode: mode,
        outcome: .failed(reason:
          "expected per-tool state to promote to .stalled; tool states ended at \(result.finalToolStates)"
        ),
        durationMs: durationMs()
      )
    }

    // Assert: the terminal BridgeError maps to a ChatErrorState whose
    // primaryRecovery is `.retry` (per PR 4). The
    // `neverReturningTool` script ends with `.error("fake_scenario_never_returning_tool")`
    // which the BehavioralRunner routes to `BridgeError.timeout`.
    guard let terminalError = result.terminalError else {
      return ChatScenarioOutcome(
        scenarioId: Self.id, mode: mode,
        outcome: .failed(reason: "expected a terminal BridgeError from the script but got none"),
        durationMs: durationMs()
      )
    }
    guard let errorState = ChatErrorState.from(terminalError) else {
      return ChatScenarioOutcome(
        scenarioId: Self.id, mode: mode,
        outcome: .failed(reason:
          "expected terminal error to map to a ChatErrorState; \(terminalError) was unmappable"
        ),
        durationMs: durationMs()
      )
    }
    if errorState.primaryRecovery != ChatErrorRecoveryAction.retry {
      return ChatScenarioOutcome(
        scenarioId: Self.id, mode: mode,
        outcome: .failed(reason:
          "expected primaryRecovery = .retry, got \(errorState.primaryRecovery)"
        ),
        durationMs: durationMs()
      )
    }

    return ChatScenarioOutcome(
      scenarioId: Self.id, mode: mode,
      outcome: .passed,
      durationMs: durationMs()
    )
  }
}
