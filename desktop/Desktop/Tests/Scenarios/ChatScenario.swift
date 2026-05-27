import Foundation

@testable import Omi_Computer

// MARK: - ChatScenario harness (PR 7 scaffolding)
//
// Scaffolding ONLY — not wired into the test target yet, not expected to
// PASS in CI today. The runtime driver (shelling out to `agent-swift`
// against a named bundle + seeded fixtures) lands in a follow-up PR.
//
// Manual-only scenarios. They require, at minimum:
//   - The PR 7 fixture seeding script (`desktop/scripts/seed-chat-reliability-fixtures.sh`)
//     to have run against the dedicated eval Firebase UID.
//   - A running named bundle (`OMI_APP_NAME="omi-chat-reliability" ./run.sh`).
//   - `agent-swift` installed and connected to that bundle.
//
// These scenarios are documentation-as-code: each file declares WHAT it
// validates (prompt + assertions + timeout), with the HOW (shell-out
// command) left as a TODO until the harness runner is implemented.
//
// -----------------------------------------------------------------------
// Roadmap inventory — 8 scenarios per mode (piMono + userClaude), from
// `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md` § PR 7. All
// scaffolded; the runner (ChatScenarioRunner) currently returns
// `.skipped` for both flavors until execution paths are wired:
//
//   #  Scenario                                File                              Flavor
//   1. Personal fact recall                    PersonalFactRecallScenario.swift  capability
//   2. Daily recap                             DailyRecapScenario.swift          capability
//   3. Task create / list / complete           TaskLifecycleScenario.swift       capability
//   4. Semantic search                         SemanticSearchScenario.swift      capability
//   5. Empty-result graceful response          EmptyResultGracefulScenario.swift capability
//   6. Stall recovery (PR 1 + PR 3 + PR 4)     StallRecoveryScenario.swift       behavioral
//   7. Auth recovery (PR 4)                    AuthRecoveryScenario.swift        behavioral
//   8. Mode parity (same prompt, both modes)   ModeParityScenario.swift          capability
//
// Capability scenarios need real auth bootstrap + Firestore fixtures +
// VM reachability. Behavioral scenarios run against FakeAgentBridge
// only — no auth, no VM, no network.
//
// Each scenario emits a `chat.scenario.run` telemetry event with payload
// `ChatScenarioRunPayload { scenarioId, mode, outcome, durationMs }` —
// see ChatScenarioOutcome below for the in-process equivalent.
// -----------------------------------------------------------------------

// MARK: - BridgeMode alias
//
// Reuses `ChatProvider.BridgeMode` so scenario callers and the existing
// chat surface share a single source of truth. The harness only cares
// about the two production modes (`piMono`, `userClaude`); the legacy
// `omiAI` raw value is auto-migrated to `piMono` at startup and is not a
// valid scenario target.
typealias BridgeMode = ChatProvider.BridgeMode

// MARK: - ChatScenarioOutcome

/// Terminal result for a single scenario run.
///
/// Mirrors the shape of the `ChatScenarioRunPayload` telemetry event so
/// the in-process value and the wire payload stay aligned. The redaction
/// allow-list in PR 7 extends `AnalyticsRedactionTests` to permit this
/// payload shape (and only this shape).
struct ChatScenarioOutcome: Sendable, Equatable {
  /// Stable identifier matching `ChatScenario.id`. Used as the
  /// `scenarioId` field on the emitted telemetry event.
  let scenarioId: String

  /// Which bridge mode the scenario was executed against. Each scenario
  /// runs once per mode per nightly invocation.
  let mode: BridgeMode

  /// The terminal classification. `.skipped` is reserved for cases where
  /// the prerequisites (fixture seeding, signed-in eval UID, named
  /// bundle reachability) are missing — those must NOT be counted as
  /// failures in the V1-exit nightly aggregate.
  let outcome: Result

  /// Wall-clock duration of the scenario run, in milliseconds.
  /// Includes prompt submission through terminal assertion check.
  let durationMs: Int

  /// The three terminal classifications a scenario can report.
  ///
  /// - `.passed`: all assertions held within the scenario's timeout.
  /// - `.failed(reason:)`: at least one assertion failed; `reason` is a
  ///   human-readable explanation suitable for the nightly report.
  /// - `.skipped(reason:)`: prerequisites not met (e.g. fixtures not
  ///   seeded, wrong signed-in UID). Excluded from pass/fail rates.
  enum Result: Sendable, Equatable {
    case passed
    case failed(reason: String)
    case skipped(reason: String)
  }
}

// MARK: - ChatScenario protocol

/// A single end-to-end scenario the chat surface must pass.
///
/// Conformers are types (not instances) — each scenario is a static
/// definition with no per-run state. The runner picks up every type
/// conforming to `ChatScenario`, runs `run(in:)` once per `BridgeMode`,
/// and aggregates `ChatScenarioOutcome`s into the nightly report.
///
/// Implementation contract (when the runner lands):
///   - `id` is stable across runs and matches the analytics `scenarioId`.
///   - `description` is a one-line summary for the nightly report.
///   - `run(in:)` is responsible for its own timeout — it must return
///     `ChatScenarioOutcome` rather than `throw` on assertion failure
///     (throws are reserved for unrecoverable harness errors like
///     "agent-swift binary not found").
protocol ChatScenario {
  /// Stable identifier, e.g. `"personal_fact_recall"`. Becomes the
  /// `scenarioId` field on the emitted telemetry event.
  static var id: String { get }

  /// One-line human-readable summary for the nightly report.
  static var description: String { get }

  /// Execute the scenario against the given bridge mode.
  ///
  /// Returns a `ChatScenarioOutcome` describing what happened. Throws
  /// only for unrecoverable harness errors (missing CLI, named bundle
  /// unreachable, etc.) — assertion failures are surfaced as
  /// `.failed(reason:)` so the nightly suite can aggregate them
  /// alongside passes and skips.
  static func run(in mode: BridgeMode) async throws -> ChatScenarioOutcome
}
