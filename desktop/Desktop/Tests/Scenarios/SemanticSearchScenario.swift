import Foundation

// MARK: - SemanticSearchScenario (PR 7 scaffolding)
//
// Scenario #4 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Validates that when the user asks a semantic question about content
// stored in screenshots (Rewind data), the model:
//   1. Invokes a semantic-search tool (`semantic_search`) OR an FTS5
//      query against `screenshots_fts` via `execute_sql`.
//   2. Surfaces the seeded screenshot fixture (the one
//      ChatReliabilityFixtures.seedScreenshotFixture writes — OCR text
//      mentions "machine learning research notes").
//   3. Completes within `Self.timeoutSeconds`.
//
// IMPORTANT: This scenario's fixture lives in local SQLite (no
// Firestore->local pull exists for screenshots). The runner must call
// ChatReliabilityFixtures.seedScreenshotFixture() at setUp.

enum SemanticSearchScenario: ChatScenario {
  static let id = "semantic_search"

  static let description =
    "Ask 'what notes have I seen about machine learning research?' — " +
    "assert AI runs semantic search or FTS over screenshots and " +
    "surfaces the seeded fixture row."

  static let userPrompt = "what notes have I seen about machine learning research?"

  /// Acceptable tool names. The runner asserts the AI used at least
  /// one of these — not which one, because the model's choice is
  /// legitimately mode-dependent (piMono has both; userClaude may
  /// route differently).
  static let acceptedToolNames: [String] = [
    "semantic_search",
    "execute_sql",  // valid when paired with screenshots_fts MATCH
  ]

  /// The OCR text the fixture seeds (kept in sync with
  /// ChatReliabilityFixtures.semanticSearchOCRText). Loose match — the
  /// model paraphrases.
  static let expectedResponseKeywords: [String] = [
    "machine learning",
    "research",
  ]

  static let timeoutSeconds: Int = 30

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .capability)
  }
}
