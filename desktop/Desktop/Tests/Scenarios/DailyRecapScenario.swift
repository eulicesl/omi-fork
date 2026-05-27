import Foundation

// MARK: - DailyRecapScenario (PR 7 scaffolding)
//
// Scenario #2 from MACOS_CHAT_RELIABILITY_ROADMAP.md § PR 7.
//
// Validates that when the user asks for a recap of today's items, the
// model:
//   1. Invokes `execute_sql` against `action_items` with a date filter
//      that covers today.
//   2. Surfaces the seeded daily-recap fixture (action_items row written
//      by the seed script with `created_at = today`).
//   3. Returns a structured (typically bulleted) response.
//   4. Completes within `Self.timeoutSeconds`.

enum DailyRecapScenario: ChatScenario {
  static let id = "daily_recap"

  static let description =
    "Ask 'what did I do today' — assert AI queries action_items with " +
    "today's date filter and surfaces the seeded recap fixture."

  static let userPrompt = "what did I do today"
  static let expectedSqlTable = "action_items"
  static let expectedToolName = "execute_sql"

  /// Substring the response must contain. The seeded recap fixture's
  /// description is "Fixture: today's chat-reliability scenario item";
  /// the model should mention enough of it that this keyword check
  /// passes without being overly fragile to phrasing.
  static let expectedResponseKeywords: [String] = ["chat-reliability scenario item"]

  static let timeoutSeconds: Int = 30

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .capability)
  }
}
