import Foundation

// MARK: - ModeParityScenario (PR 7 scaffolding)
//
// Scenario #8 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Validates that the same prompt produces a useful answer in BOTH
// modes (piMono, userClaude). The bar isn't "same answer" — the bar
// is "both modes return a non-empty, non-error response that mentions
// the seeded fact". This catches mode-specific regressions where one
// mode silently breaks while the other keeps working.
//
// Runs differently from the other scenarios: it executes once per
// mode, then reconciles the two outcomes. The runner's
// `runScenario(_:in:flavor:)` returns a single per-mode outcome; the
// "parity" check happens at the nightly-aggregation layer (compare
// piMono + userClaude outcomes for the same scenarioId).
//
// V1 implementation strategy: emit two separate
// `chat.scenario.run` events (one per mode) with `scenarioId =
// "mode_parity"`; nightly report cross-references them.

enum ModeParityScenario: ChatScenario {
  static let id = "mode_parity"

  static let description =
    "Send the same prompt to both modes; assert each returns a non-error " +
    "non-empty response mentioning the seeded canonical fact."

  /// The same prompt sent through both modes. Chosen to be answerable
  /// from the seeded memory fixture (avoids depending on real cloud
  /// data state that varies between accounts).
  static let userPrompt = "what's my name"

  /// Keyword every successful mode response must contain
  /// (case-insensitive). Mirrors PersonalFactRecallScenario but the
  /// assertion bar is looser — this scenario is about presence of an
  /// answer, not about the SQL path the model took to find it.
  static let expectedResponseKeywords: [String] = ["Eulices"]

  static let timeoutSeconds: Int = 30

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .capability)
  }
}
