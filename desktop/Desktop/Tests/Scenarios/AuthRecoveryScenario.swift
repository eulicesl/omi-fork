import Foundation

// MARK: - AuthRecoveryScenario (PR 7 scaffolding)
//
// Scenario #7 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Behavioral scenario — exercises PR 4's auth-error recovery path
// using FakeAgentBridge. Verifies that:
//
//   1. A turn starts.
//   2. FakeAgentBridge synthesizes an `auth_missing` failure event.
//   3. ChatProvider's catch block maps `BridgeError.authMissing` to
//      `.authRequired` and sets `currentError` accordingly.
//   4. The recovery card's primary action is `.signIn` (matching
//      `ChatErrorState.authRequired.primaryRecovery`).
//
// Runs against BOTH modes; the mapping behavior is mode-agnostic.

enum AuthRecoveryScenario: ChatScenario {
  static let id = "auth_recovery"

  static let description =
    "FakeAgentBridge injects BridgeError.authMissing during a turn; " +
    "assert ChatProvider.currentError = .authRequired and the recovery " +
    "card's primaryRecovery is .signIn."

  /// The synthetic prompt. Content is irrelevant; assertions are
  /// about error-state mapping, not response.
  static let userPrompt = "[auth-recovery harness — prompt content unused]"

  /// The ChatErrorState the runner asserts ChatProvider lands on
  /// after the synthetic auth_missing event. String form because the
  /// enum's `.authRequired` case has no associated value.
  static let expectedErrorState = "authRequired"

  /// The ChatErrorRecoveryAction the recovery card's `primaryRecovery`
  /// must equal.
  static let expectedPrimaryRecovery = "signIn"

  static let timeoutSeconds: Int = 10  // pure mapping, no real wait needed

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .behavioral)
  }
}
