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

  // MARK: - Runtime driver (the "HOW") — TODO

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    // TODO(runner): Wire this to `agent-swift` against the named bundle.
    //
    // Sketch of the future driver (rough — flag names finalised when the
    // runner PR lands):
    //
    //   1. Pre-flight:
    //        agent-swift doctor
    //        agent-swift connect --bundle-id com.omi.omi-chat-reliability
    //      Skip if either fails (return .skipped with the reason).
    //
    //   2. Ensure the right `bridgeMode` is selected. The cheapest path
    //      is the automation CLI (see desktop/CLAUDE.md):
    //        ./scripts/omi-ctl set-bridge-mode \(mode.rawValue)
    //      Until that subcommand exists, drive the Settings UI via
    //      `agent-swift` + the existing snapshot/click flow.
    //
    //   3. Navigate to chat + send the prompt:
    //        ./scripts/omi-ctl navigate chat
    //        agent-swift fill <chat-input-ref> "\(userPrompt)"
    //        agent-swift press <send-button-ref>
    //
    //   4. Wait for the assistant turn to terminate (poll the turn-state
    //      ledger from PR 11, or fall back to `agent-swift wait text` on
    //      the final-message anchor). Bounded by `timeoutSeconds`.
    //
    //   5. Pull the recorded tool-call payload from the local turn
    //      ledger (or scrape `/private/tmp/omi-dev.log`) and assert:
    //        - exactly one `execute_sql` call
    //        - the SQL string references `expectedSqlTable`
    //
    //   6. Pull the assistant's final message text and assert:
    //        - non-empty
    //        - contains every entry in `expectedResponseKeywords`
    //          (case-insensitive)
    //
    //   7. Stamp `durationMs` from wall-clock start → terminal check.
    //
    // Until the runner lands, the scenario reports `.skipped` so it can
    // be enumerated by the nightly harness without failing the build.
    let startedAt = Date()
    let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

    return ChatScenarioOutcome(
      scenarioId: Self.id,
      mode: mode,
      outcome: .skipped(reason: "runner_not_implemented"),
      durationMs: durationMs
    )
  }
}
