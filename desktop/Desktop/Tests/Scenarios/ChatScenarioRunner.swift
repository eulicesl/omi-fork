import Foundation

@testable import Omi_Computer

// MARK: - ChatScenarioRunner (PR 7 scaffolding)
//
// In-process execution layer for chat-reliability scenarios. Two
// scenario flavors with different prerequisite shapes:
//
//   - **Behavioral scenarios** (#6 stall-recovery, #7 auth-recovery)
//     test ChatProvider's handling of bridge events. They run against
//     FakeAgentBridge (PR 0b) and need NO real auth, NO VM, and NO
//     network. The runner can execute these today.
//
//   - **Capability scenarios** (#1 personal-fact, #2 daily-recap,
//     #3 task-lifecycle, #4 semantic-search, #5 empty-result, #8 mode-
//     parity) test that the LLM + tool stack produces correct chat
//     answers. They run against a real AgentBridge (piMono or
//     userClaude) and require:
//       (a) auth bootstrap of the test process so it can talk to the
//           backend API and the VM (auth_userId, Firebase token, etc.),
//       (b) the V1 eval Firebase UID's Firestore fixtures seeded by
//           `desktop/scripts/seed-chat-reliability-fixtures.sh`, and
//       (c) the local-only screenshot fixture seeded by
//           ChatReliabilityFixtures.seedScreenshotFixture().
//     Until (a) lands, capability scenarios skip with
//     `.skipped(reason: "auth_bootstrap_required")`.
//
// The runner is **not** an XCTestCase — scenarios are documentation-as-
// code types, and the runner is invoked from per-scenario XCTestCase
// wrappers when those are added.

enum ChatScenarioRunner {

  /// Prerequisite state of the test process. Populated by
  /// `detectPrerequisites()` at the top of each `runScenario` call so
  /// the skip reason is derived from observed state, not assumed.
  struct Prerequisites: Sendable, Equatable {
    let hasAuthBootstrap: Bool
    let hasFixtureSeeding: Bool
    let canReachVM: Bool
  }

  /// Why a scenario was skipped. Stable enough that a CI report can
  /// group skips by cause and tell a reviewer what to provision next.
  enum SkipReason: String, Sendable {
    case authBootstrapRequired = "auth_bootstrap_required"
    case fixturesNotSeeded = "fixtures_not_seeded"
    case vmUnreachable = "vm_unreachable"
    case runnerNotImplemented = "runner_not_implemented"
  }

  /// Whether a scenario needs the heavy real-bridge stack or can run
  /// fully in-process with FakeAgentBridge.
  enum Flavor: Sendable {
    /// Real AgentBridge, real auth, real VM, real LLM. Needs Phase 2
    /// auth-bootstrap. Six of the eight V1 scenarios.
    case capability

    /// FakeAgentBridge-driven; needs none of the above. Two of the
    /// eight V1 scenarios (#6 stall, #7 auth-recovery).
    case behavioral
  }

  // MARK: - Public entry point

  /// Run a scenario against the given bridge mode. Returns an outcome
  /// rather than throwing for assertion failures — throws are reserved
  /// for unrecoverable harness errors (e.g. fixture seeding crashed).
  ///
  /// The runner is currently a SKELETON: every call returns
  /// `.skipped(reason: .runnerNotImplemented)` for capability scenarios
  /// and `.skipped(reason: .runnerNotImplemented)` for behavioral
  /// scenarios too, because neither the capability execution path nor
  /// the FakeAgentBridge wiring is implemented yet. Both are explicit
  /// follow-up work.
  ///
  /// The contract the runner WILL fulfil when implemented:
  ///
  ///   capability flavor:
  ///     1. detectPrerequisites() → skip if any missing
  ///     2. ChatReliabilityFixtures.seedScreenshotFixture() if scenario needs it
  ///     3. construct ChatProvider with real AgentBridge in target mode
  ///     4. TasksStore.shared.loadTasks() — pull cloud → local
  ///     5. AgentSyncService.shared.syncTick() — push local → VM
  ///     6. wait for VM /health databaseReady
  ///     7. provider.sendMessage(scenario.prompt)
  ///     8. wait for !provider.isAgentResponding within scenario.timeout
  ///     9. assert per-scenario (tool used, response contains keyword, etc.)
  ///    10. return .passed / .failed(reason:)
  ///
  ///   behavioral flavor:
  ///     1. construct ChatProvider with FakeAgentBridge configured for
  ///        the scenario's event stream
  ///     2. provider.sendMessage(scenario.prompt)
  ///     3. observe ChatProvider state (currentError, messages,
  ///        toolCall statuses)
  ///     4. assert against expected state transitions
  ///     5. return outcome
  static func runScenario(
    _ scenario: any ChatScenario.Type,
    in mode: BridgeMode,
    flavor: Flavor,
    startTime: Date = Date()
  ) async -> ChatScenarioOutcome {
    let elapsedMs = { Int(Date().timeIntervalSince(startTime) * 1000) }

    let skipReason: SkipReason
    switch flavor {
    case .capability:
      let prereqs = await detectPrerequisites()
      if !prereqs.hasAuthBootstrap {
        skipReason = .authBootstrapRequired
      } else if !prereqs.hasFixtureSeeding {
        skipReason = .fixturesNotSeeded
      } else if !prereqs.canReachVM {
        skipReason = .vmUnreachable
      } else {
        skipReason = .runnerNotImplemented
      }
    case .behavioral:
      skipReason = .runnerNotImplemented
    }

    return ChatScenarioOutcome(
      scenarioId: scenario.id,
      mode: mode,
      outcome: .skipped(reason: skipReason.rawValue),
      durationMs: elapsedMs()
    )
  }

  // MARK: - Prerequisite detection

  /// Inspect the test process for the auth + fixture + VM state
  /// needed by capability scenarios. **Best-effort only**: false
  /// negatives are fine (we'll skip when in doubt), false positives
  /// would let a scenario run and fail mid-flight with a confusing
  /// error, so the bar for `true` is high.
  static func detectPrerequisites() async -> Prerequisites {
    // Auth bootstrap: the test process needs a UserDefaults
    // auth_userId for the eval UID. Without it, AuthService.shared
    // can't sign API requests.
    let userDefaults = UserDefaults.standard
    let signedInUid = userDefaults.string(forKey: "auth_userId")
    let evalUid = "rg0PvY9mhKRARcYxkHHYh4iAkc12"  // V1 locked value
    let hasAuthBootstrap = (signedInUid == evalUid)

    // Fixture seeding: heuristic — does the local screenshots table
    // contain a row tagged with our fixture appName? Cheap query and
    // a reliable indicator the test setup ran.
    var hasFixtureSeeding = false
    do {
      let epoch = Date(timeIntervalSince1970: 0)
      let farFuture = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
      let rows = try await RewindDatabase.shared.getScreenshots(
        from: epoch, to: farFuture, limit: 50
      )
      hasFixtureSeeding = rows.contains { $0.appName == ChatReliabilityFixtures.fixtureAppName }
    } catch {
      // Database may not be initialised in a fresh test process —
      // treat as "fixtures not seeded" rather than crash. The runner
      // surfaces the skip cleanly.
      hasFixtureSeeding = false
    }

    // VM reachability: out of scope to probe from the test process
    // (would require AgentVMService.shared which itself needs auth).
    // Mark as unknown-but-assume-true when auth is present; if the
    // real bridge can't reach the VM, scenario execution will fail
    // with a clean error, not a misleading skip.
    let canReachVM = hasAuthBootstrap

    return Prerequisites(
      hasAuthBootstrap: hasAuthBootstrap,
      hasFixtureSeeding: hasFixtureSeeding,
      canReachVM: canReachVM
    )
  }
}
