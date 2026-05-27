import Foundation

@testable import Omi_Computer

// MARK: - BehavioralRunner (PR 7)
//
// Drives a `FakeBridgeScript` through a freshly-constructed
// `StallDetector` and returns the observed state-transition trace +
// terminal outcome. Used by behavioral scenarios (#6 stall-recovery,
// #7 auth-recovery) to verify the cross-component contract:
//
//   FakeAgentBridge events → StallDetector state transitions
//   FakeAgentBridge terminal events → BridgeError → ChatErrorState → recovery
//
// This is *component-stack* end-to-end, one layer below the full
// `ChatProvider` integration. ChatProvider is too heavy to instantiate
// cleanly in tests (no DI seam for the bridge, lazy init touches
// Firebase/Settings, etc.); a future PR can introduce DI and lift
// these scenarios into a full-provider harness. Until then, this
// runner gives the next-best deterministic coverage of the
// stall-detector + error-mapping chain.
//
// The detector is constructed with `StallThresholds.v1Defaults`
// (slowGapMs=8000, stalledGapMs=20000, bridgeUnresponsiveMs=12000).
// All event timestamps are simulated (driven by `script.events[].atMs`),
// so the runner completes in well under a second regardless of how
// long the scripted "wait" is.

enum BehavioralRunner {

  /// Drive `script` through a fresh `StallDetector`. Maps each event
  /// to the appropriate detector observation, records the resulting
  /// transition sequence, and identifies a terminal `BridgeError`
  /// when the script ends with `.error`, `.authRequired`, or
  /// `.bridgeCrash`.
  ///
  /// After the last event, the runner advances the detector's clock
  /// 60s beyond the last event so any time-based promotions caused
  /// by the trailing gap surface in the transition trace.
  static func drive(
    _ script: FakeBridgeScript,
    thresholds: StallThresholds = .v1Defaults
  ) async -> DriveResult {
    let detector = StallDetector(thresholds: thresholds, startedAtMs: 0)
    var allTransitions: [StallDetector.Transition] = []
    var terminalError: BridgeError?
    var lastEventAtMs = 0

    for timed in script.events {
      lastEventAtMs = timed.atMs

      // Before observing the event, tick to its timestamp to capture
      // any time-based promotions that happened in the gap *before*
      // this event.
      let preTick = await detector.tick(atMs: timed.atMs)
      allTransitions.append(contentsOf: preTick)

      // Map the event to the right detector call.
      switch timed.event {
      case .initSession, .textDelta, .thinkingDelta, .toolResultDisplay, .result, .authSuccess:
        let transitions = await detector.step(kind: .other, atMs: timed.atMs)
        allTransitions.append(contentsOf: transitions)

      case .toolUse(let callId, _, _):
        let transitions = await detector.step(
          kind: .toolStarted(id: callId), atMs: timed.atMs
        )
        allTransitions.append(contentsOf: transitions)

      case .toolActivity(_, let status, let toolUseId, _):
        // A tool_activity with a terminal status closes that tool's
        // per-tool timer; any other status is a generic event.
        if let id = toolUseId,
          status == "completed" || status == "failed" || status == "cancelled"
        {
          let transitions = await detector.step(
            kind: .toolCompleted(id: id), atMs: timed.atMs
          )
          allTransitions.append(contentsOf: transitions)
        } else {
          let transitions = await detector.step(kind: .other, atMs: timed.atMs)
          allTransitions.append(contentsOf: transitions)
        }

      case .heartbeat:
        let transitions = await detector.observeHeartbeat(atMs: timed.atMs)
        allTransitions.append(contentsOf: transitions)

      case .error(let message):
        terminalError = mapErrorMessage(message)

      case .authRequired:
        terminalError = .authMissing

      case .bridgeCrash:
        terminalError = .processExited

      case .malformed:
        // Malformed lines are logged-and-skipped in production; the
        // detector sees no observation for them. Intentional no-op.
        break
      }
    }

    // After the script ends, advance the clock 60s to surface any
    // trailing time-based promotions. Without this, a `neverReturningTool`
    // script whose final `.error` event is BEFORE `stalledGapMs` from
    // the last tool-start would show only `.slow`, not `.stalled`.
    let finalTime = lastEventAtMs + 60_000
    let trailingTick = await detector.tick(atMs: finalTime)
    allTransitions.append(contentsOf: trailingTick)

    let finalInterEventState = await detector.interEventState
    let finalToolStates = await detector.snapshotToolStates()

    return DriveResult(
      transitions: allTransitions,
      terminalError: terminalError,
      finalInterEventState: finalInterEventState,
      finalToolStates: finalToolStates
    )
  }

  // MARK: - Helpers

  /// Map a `.error(message:)` payload to the most-specific BridgeError
  /// case. Most fake-bridge `.error` events carry opaque messages, so
  /// the default is `.agentError(message)`. Specific message prefixes
  /// route to dedicated cases for parity with the real bridge's
  /// classification.
  static func mapErrorMessage(_ message: String) -> BridgeError {
    let lowered = message.lowercased()
    if lowered.contains("auth") && lowered.contains("required") { return .authMissing }
    if lowered.contains("timeout") { return .timeout }
    if lowered.contains("never_returning") { return .timeout }
    return .agentError(message)
  }

  /// Convenience: whether any transition in `transitions` promoted
  /// the inter-event state to `target`.
  static func transitionsReachedInterEvent(
    _ transitions: [StallDetector.Transition],
    target: StallDetector.State
  ) -> Bool {
    for transition in transitions {
      if case .interEvent(_, let to) = transition, to == target { return true }
    }
    return false
  }

  /// Convenience: whether any transition promoted any tool's
  /// per-tool state to `target`.
  static func transitionsReachedTool(
    _ transitions: [StallDetector.Transition],
    target: StallDetector.State
  ) -> Bool {
    for transition in transitions {
      if case .tool(_, _, let to) = transition, to == target { return true }
    }
    return false
  }
}

// MARK: - DriveResult

extension BehavioralRunner {
  /// Output of `drive(_:)`. Carries enough state for any behavioral
  /// scenario to assert without re-reading the detector.
  struct DriveResult: Sendable {
    /// Every transition the detector emitted, in observation order.
    let transitions: [StallDetector.Transition]

    /// `BridgeError` corresponding to the script's terminal failure
    /// event, or `nil` if the script ended without a terminal failure
    /// (e.g. a `.result` event ends a happy-path script).
    let terminalError: BridgeError?

    /// Detector's `interEventState` after the trailing time advance.
    let finalInterEventState: StallDetector.State

    /// Per-tool states after the trailing time advance. Empty when no
    /// tool was ever started.
    let finalToolStates: [String: StallDetector.State]
  }
}
