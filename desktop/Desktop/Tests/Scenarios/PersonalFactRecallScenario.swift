import Foundation

// MARK: - PersonalFactRecallScenario (PR 7 scaffolding)
//
// Scenario #1 from `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md` § PR 7.
//
// Manual-only. Not wired into the test target. The actual driving of the
// named bundle via `agent-swift` is a TODO — see `// TODO(runner):`
// markers below. This file is documentation-as-code: it nails down the
// prompt, the SQL surface area, and the success criteria so the future
// runner can be implemented mechanically.
//
// Validates that when the user asks for a personal fact stored in the
// memories table, the model:
//   1. Invokes the `execute_sql` tool against the `memories` table.
//   2. Returns a non-empty natural-language response.
//   3. Completes within `Self.timeoutSeconds` (30s).
//   4. The response contains the seeded fact (the user's name).

enum PersonalFactRecallScenario: ChatScenario {
  // MARK: - ChatScenario conformance

  static let id = "personal_fact_recall"

  static let description =
    "Ask 'what's my name' — assert AI calls execute_sql on memories, " +
    "response is non-empty, completes within 30s, and includes the seeded name."

  // MARK: - Scenario surface area (the "WHAT")

  /// The user-facing prompt sent into the chat surface verbatim.
  static let userPrompt = "what's my name"

  /// The table the `execute_sql` tool call must reference. Asserted by
  /// inspecting the recorded tool-call payload after the turn ends.
  static let expectedSqlTable = "memories"

  /// The tool name the AI is expected to invoke (piMono + userClaude
  /// both expose `execute_sql`).
  static let expectedToolName = "execute_sql"

  /// Substrings the final assistant message must contain (case-insensitive).
  /// Seeded by `desktop/scripts/seed-chat-reliability-fixtures.sh` —
  /// kept in sync with the fixture's `content` field.
  ///
  /// NOTE: This is the canonical seed value. If the seed script changes
  /// it, this constant must move in lockstep.
  static let expectedResponseKeywords: [String] = ["Eulices"]

  /// Hard ceiling on scenario duration. Anything past this is a `.failed`.
  static let timeoutSeconds: Int = 30

  // MARK: - Runtime driver

  /// Capability-flavored scenario: depends on real auth + real LLM
  /// stack via the runner. The runner currently returns `.skipped`
  /// until Phase 2 auth bootstrap lands. See ChatScenarioRunner.
  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    await ChatScenarioRunner.runScenario(Self.self, in: mode, flavor: .capability)
  }
}
