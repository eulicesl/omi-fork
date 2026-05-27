import XCTest

@testable import Omi_Computer

/// XCTest wrappers that actually invoke the two behavioral
/// chat-reliability scenarios. Capability scenarios skip with
/// `.auth_bootstrap_required` until Phase 2; these run today because
/// they go through FakeAgentBridge — no auth, no VM, no network.
///
/// Each test runs the scenario against BOTH bridge modes and asserts
/// the outcome is `.passed`. A failure in either mode fails the test
/// with the scenario's `reason` string surfaced for triage.
final class BehavioralScenarioTests: XCTestCase {

  // MARK: - #6 StallRecoveryScenario

  func testStallRecoveryScenarioPassesInPiMonoMode() async throws {
    let outcome = try await StallRecoveryScenario.run(in: .piMono)
    assertPassed(outcome, scenarioId: StallRecoveryScenario.id, mode: .piMono)
  }

  func testStallRecoveryScenarioPassesInUserClaudeMode() async throws {
    let outcome = try await StallRecoveryScenario.run(in: .userClaude)
    assertPassed(outcome, scenarioId: StallRecoveryScenario.id, mode: .userClaude)
  }

  // MARK: - #7 AuthRecoveryScenario

  func testAuthRecoveryScenarioPassesInPiMonoMode() async throws {
    let outcome = try await AuthRecoveryScenario.run(in: .piMono)
    assertPassed(outcome, scenarioId: AuthRecoveryScenario.id, mode: .piMono)
  }

  func testAuthRecoveryScenarioPassesInUserClaudeMode() async throws {
    let outcome = try await AuthRecoveryScenario.run(in: .userClaude)
    assertPassed(outcome, scenarioId: AuthRecoveryScenario.id, mode: .userClaude)
  }

  // MARK: - Helpers

  /// Assert the outcome's `outcome` is `.passed`. On failure, surface
  /// the scenario id, mode, and the scenario's own `reason` string so
  /// the test report tells the reader exactly which assertion broke.
  private func assertPassed(
    _ outcome: ChatScenarioOutcome,
    scenarioId: String,
    mode: BridgeMode,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(
      outcome.scenarioId, scenarioId,
      "outcome.scenarioId should echo the scenario's id",
      file: file, line: line
    )
    XCTAssertEqual(
      outcome.mode, mode,
      "outcome.mode should echo the mode the scenario was run with",
      file: file, line: line
    )

    switch outcome.outcome {
    case .passed:
      return
    case .failed(let reason):
      XCTFail(
        "scenario \(scenarioId) in \(mode) failed: \(reason)",
        file: file, line: line
      )
    case .skipped(let reason):
      XCTFail(
        "scenario \(scenarioId) in \(mode) unexpectedly skipped: \(reason). Behavioral scenarios should not skip.",
        file: file, line: line
      )
    }
  }
}
