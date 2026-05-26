import Foundation

// MARK: - EmptyResultGracefulScenario (PR 7 scaffolding)
//
// Scenario #5 from `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md` § PR 7.
//
// Manual-only. Not wired into the test target. The runtime driver is a
// TODO — see `// TODO(runner):` markers below. This file is
// documentation-as-code.
//
// Validates the "no fabrication" property: when a query is guaranteed to
// return zero rows from the memories table, the model must:
//   1. Acknowledge the empty result honestly (no invented facts).
//   2. Respond briefly (1-2 lines).
//   3. Complete within `Self.timeoutSeconds` (30s).
//
// The query targets a sentinel string the seed script intentionally
// avoids — guaranteeing an empty result regardless of other fixture
// drift. This is the cheapest possible fabrication-detection scenario.

enum EmptyResultGracefulScenario: ChatScenario {
  // MARK: - ChatScenario conformance

  static let id = "empty_result_graceful"

  static let description =
    "Ask for a memory matching a no-results sentinel — assert the response " +
    "is short, acknowledges no data, and does not fabricate content."

  // MARK: - Scenario surface area (the "WHAT")

  /// The unique sentinel string the seed script GUARANTEES is absent
  /// from every fixture. Querying for content containing this string
  /// reliably returns zero rows.
  ///
  /// Kept in lockstep with `desktop/scripts/seed-chat-reliability-fixtures.sh`.
  /// If the seed script changes the sentinel, this constant must move
  /// with it.
  static let noResultsSentinel = "ZZZ_NO_RESULTS_SENTINEL_XYZ_unique_string_99999"

  /// The user-facing prompt — phrased naturally so the model genuinely
  /// has to decide what to do with an empty result set, rather than
  /// short-circuiting on an obvious "test string".
  static let userPrompt =
    "Find any memory I have that mentions '\(noResultsSentinel)' and tell me about it."

  /// Substrings the final assistant message MUST contain (case-insensitive).
  /// At least one of these phrases must appear — they are the canonical
  /// "no data" acknowledgment forms. The runner asserts ANY match
  /// (not all), because honest models phrase this several different ways.
  static let acknowledgmentPhrases: [String] = [
    "no memories",
    "no memory",
    "no results",
    "couldn't find",
    "could not find",
    "didn't find",
    "did not find",
    "nothing found",
    "no matches",
    "no record",
  ]

  /// Substrings the response MUST NOT contain. The sentinel itself
  /// appearing inside *quoted* assistant text would be invented content.
  ///
  /// NOTE: A correct response may echo the sentinel back to confirm the
  /// query (e.g. "I searched for '\(noResultsSentinel)' and found
  /// nothing"). The runner therefore strips quoted spans before checking
  /// for forbidden substrings — implementation detail for the future
  /// driver, not encoded in this scaffolding.
  static let forbiddenPhrases: [String] = [
    // Add red-flag fabrications here if/when we observe them in nightly
    // runs. Starting empty — the structural assertions (short length,
    // contains an acknowledgment phrase) carry the load on day one.
  ]

  /// Maximum allowed length of the assistant response, in lines. The
  /// honest answer is short ("I couldn't find any memories matching
  /// that."). A 5-paragraph reply is a strong fabrication smell.
  static let maxResponseLines: Int = 2

  /// Hard ceiling on scenario duration.
  static let timeoutSeconds: Int = 30

  // MARK: - Runtime driver (the "HOW") — TODO

  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome {
    // TODO(runner): Wire this to `agent-swift` against the named bundle.
    //
    // Same driver sketch as PersonalFactRecallScenario, with these
    // scenario-specific assertions in step 6:
    //
    //   - Final message line count <= `maxResponseLines`.
    //   - Final message contains at least one entry from
    //     `acknowledgmentPhrases` (case-insensitive).
    //   - Final message contains none of `forbiddenPhrases`.
    //   - Tool call (if any) referenced the memories table with the
    //     sentinel in the WHERE clause — i.e. the model actually tried
    //     to look it up instead of refusing without searching.
    //
    // Until the runner lands, the scenario reports `.skipped`.
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
