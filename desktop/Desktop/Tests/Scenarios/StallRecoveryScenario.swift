import Foundation

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
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .behavioral)
  }
}
