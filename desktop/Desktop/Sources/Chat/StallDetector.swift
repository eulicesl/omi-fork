import Foundation

/// Tracks whether the active chat turn is making forward progress and
/// surfaces transitions to `.slow` / `.stalled` so the UI can render
/// progress affordances and a Cancel banner.
///
/// Two timers track independently:
///   - **Inter-event gap** — ms since the last event of any kind.
///     Captures "the bridge stopped streaming."
///   - **Per-tool duration** — ms since each in-flight tool started.
///     Captures "this specific tool is hanging."
///
/// The detector is pure logic: time is passed in as a parameter on
/// every operation, so tests can drive it instantly without wall-clock
/// waits and production wraps it in a periodic `tick(atMs:)` task.
///
/// Wiring (Commit D of PR 1):
///   - On every bridge callback, `ChatProvider` calls
///     `await detector.step(kind: .other, atMs: now)` (or
///     `.toolStarted(id:)` / `.toolCompleted(id:)` for tool events).
///   - A background task running while the turn is active calls
///     `await detector.tick(atMs: now)` every ~500ms so promotions
///     surface even when no new events arrive.
///   - Returned transitions drive `ToolCallStatus` updates and the
///     message-level Cancel banner.
actor StallDetector {

  // MARK: - Public types

  enum State: Equatable, Sendable {
    case running
    case slow
    case stalled
    /// PR 8: inter-event gap exceeded `slowGapMs` AND a bridge
    /// heartbeat arrived within `bridgeUnresponsiveMs`. The model is
    /// slow but the bridge subprocess is alive.
    case upstreamSlow
    /// PR 8: the bridge has not emitted a heartbeat in
    /// `bridgeUnresponsiveMs` (and the turn is in flight). The
    /// subprocess is probably dead or the heartbeat timer has stopped
    /// firing. UI surfaces a more severe affordance than `.stalled`.
    case bridgeUnresponsive
  }

  /// What kind of event observation is being recorded.
  enum EventKind: Equatable, Sendable {
    /// Any non-tool event (text_delta, thinking_delta, init, heartbeat).
    /// Resets the inter-event gap timer.
    case other

    /// A `tool_use` was emitted; the tool is now in flight. Starts the
    /// per-tool timer for `id` (typically the `toolUseId`).
    case toolStarted(id: String)

    /// A `tool_activity` with status `completed` (or `failed` /
    /// `cancelled`) arrived. Clears the per-tool timer for `id` and
    /// emits a transition back to `.running` if the tool was promoted.
    case toolCompleted(id: String)
  }

  /// A state change emitted by `step` or `tick`. Consumers (Commit D)
  /// translate these into `ToolCallStatus` updates and banner state.
  enum Transition: Equatable, Sendable {
    /// The whole-turn inter-event timer changed state.
    case interEvent(from: State, to: State)

    /// A specific in-flight tool's per-tool timer changed state.
    /// `id` matches the `toolUseId` from the bridge.
    case tool(id: String, from: State, to: State)
  }

  // MARK: - Configuration

  let thresholds: StallThresholds

  // MARK: - State (actor-isolated)

  private(set) var interEventState: State = .running
  private var lastEventAtMs: Int

  /// In-flight tools keyed by `toolUseId`. Removed on completion.
  private var toolStartedAtMs: [String: Int] = [:]
  private var toolStates: [String: State] = [:]

  /// PR 8: timestamp of the most recent bridge heartbeat, or `nil` if
  /// no heartbeat has been observed yet. The inter-event promotion
  /// rule uses this to distinguish `.upstreamSlow` (heartbeat fresh,
  /// model output stalled) from `.bridgeUnresponsive` (heartbeat
  /// missing past `bridgeUnresponsiveMs`).
  private(set) var lastHeartbeatAtMs: Int?

  // MARK: - Init

  /// `startedAtMs` is the simulated/wall-clock time of turn start. The
  /// inter-event gap clock counts from this until the first event.
  init(thresholds: StallThresholds = .v1Defaults, startedAtMs: Int) {
    self.thresholds = thresholds
    self.lastEventAtMs = startedAtMs
  }

  // MARK: - Read-only state queries

  /// Current promoted state for a specific tool, or `.running` if the
  /// tool isn't currently tracked (either never started or already
  /// completed).
  func currentToolState(id: String) -> State {
    toolStates[id] ?? .running
  }

  /// Snapshot of all in-flight tool states. Useful for the UI's "any
  /// tool stalled?" check that gates the message-level banner.
  func snapshotToolStates() -> [String: State] {
    toolStates
  }

  // MARK: - Observation

  /// Record an event at simulated time `atMs` and return any state
  /// transitions caused by both the observation itself (e.g. a new
  /// event arriving while the detector was `.stalled` flips it back to
  /// `.running`) and by elapsed time up to `atMs`.
  ///
  /// `step` is the entry point production wiring uses on every bridge
  /// callback. Tests may use `step` and `tick` interchangeably; `step`
  /// = observe + tick in a single actor hop.
  func step(kind: EventKind, atMs: Int) -> [Transition] {
    var transitions = observe(kind: kind, atMs: atMs)
    transitions.append(contentsOf: evaluate(atMs: atMs))
    return transitions
  }

  /// Advance to `atMs` without recording a new event. Returns any
  /// transitions caused by elapsed time crossing a threshold. Idempotent
  /// — calling `tick` repeatedly with the same `atMs` returns each
  /// transition exactly once (subsequent calls with the same `atMs`
  /// return an empty array).
  ///
  /// Production wraps this in a periodic background task while a turn
  /// is active so promotions surface even when no new events arrive.
  func tick(atMs: Int) -> [Transition] {
    evaluate(atMs: atMs)
  }

  /// PR 8: record a bridge heartbeat arrival. Heartbeats are out-of-band
  /// liveness pulses — they do NOT reset the inter-event gap timer
  /// (which tracks model output, not bridge liveness), but they DO
  /// inform the inter-event promotion rule: a long gap with fresh
  /// heartbeats promotes to `.upstreamSlow`; a long gap with stale
  /// heartbeats promotes to `.bridgeUnresponsive`.
  ///
  /// Heartbeats are also a recovery signal: if the inter-event state
  /// was `.bridgeUnresponsive` and a fresh heartbeat arrives, the
  /// next `tick()` can reclassify back to `.upstreamSlow` (or to
  /// `.running` if a real event has also arrived since).
  func observeHeartbeat(atMs: Int) -> [Transition] {
    lastHeartbeatAtMs = atMs
    return evaluate(atMs: atMs)
  }

  // MARK: - Internal

  private func observe(kind: EventKind, atMs: Int) -> [Transition] {
    var transitions: [Transition] = []

    // Any event resets the inter-event gap to .running.
    if interEventState != .running {
      transitions.append(.interEvent(from: interEventState, to: .running))
      interEventState = .running
    }
    lastEventAtMs = atMs

    switch kind {
    case .other:
      break

    case .toolStarted(let id):
      toolStartedAtMs[id] = atMs
      if let old = toolStates[id], old != .running {
        // Re-starting a tool that had been promoted (unusual but
        // possible if the bridge re-emits) — emit a back-to-running
        // transition for the UI.
        transitions.append(.tool(id: id, from: old, to: .running))
      }
      toolStates[id] = .running

    case .toolCompleted(let id):
      toolStartedAtMs.removeValue(forKey: id)
      let old = toolStates.removeValue(forKey: id) ?? .running
      if old != .running {
        // Tool completed while promoted (slow/stalled → done) — UI
        // should clear the slow/stalled annotation.
        transitions.append(.tool(id: id, from: old, to: .running))
      }
    }

    return transitions
  }

  private func evaluate(atMs: Int) -> [Transition] {
    var transitions: [Transition] = []

    // Inter-event timer — PR 8 uses heartbeat awareness when picking
    // between `.upstreamSlow` and `.bridgeUnresponsive`.
    let interGap = atMs - lastEventAtMs
    let newInter = promotedInterEventState(
      forElapsedGapMs: interGap,
      atMs: atMs
    )
    if newInter != interEventState {
      transitions.append(.interEvent(from: interEventState, to: newInter))
      interEventState = newInter
    }

    // Per-tool timers continue to use the original 3-state promotion
    // (running / slow / stalled). Heartbeat health is a turn-level
    // signal, not a per-tool one — a specific tool can be slow for
    // its own reasons regardless of bridge liveness.
    for (toolId, startedAt) in toolStartedAtMs {
      let duration = atMs - startedAt
      let newToolState = promotedToolState(forElapsedMs: duration)
      let oldToolState = toolStates[toolId] ?? .running
      if newToolState != oldToolState {
        transitions.append(.tool(id: toolId, from: oldToolState, to: newToolState))
        toolStates[toolId] = newToolState
      }
    }

    return transitions
  }

  /// PR 1 promotion rule for per-tool timers (unchanged).
  private func promotedToolState(forElapsedMs elapsed: Int) -> State {
    if elapsed >= thresholds.stalledGapMs { return .stalled }
    if elapsed >= thresholds.slowGapMs { return .slow }
    return .running
  }

  /// PR 8 promotion rule for the inter-event gap:
  ///
  /// 1. Gap < `slowGapMs` → `.running` (regardless of heartbeat status).
  /// 2. Gap ≥ `slowGapMs` AND heartbeat is fresh (within
  ///    `bridgeUnresponsiveMs`) → `.upstreamSlow` — bridge alive,
  ///    upstream model is slow.
  /// 3. Gap ≥ `slowGapMs` AND heartbeat is stale (or never received)
  ///    → `.bridgeUnresponsive` — subprocess probably dead.
  ///
  /// Pre-PR-8 sessions never observe a heartbeat, so they end up in
  /// `.bridgeUnresponsive` on a long gap — which is technically less
  /// accurate than the old `.stalled`, but the PR 8 docstring lets
  /// the UI choose the right copy for either case.
  private func promotedInterEventState(
    forElapsedGapMs elapsed: Int,
    atMs: Int
  ) -> State {
    guard elapsed >= thresholds.slowGapMs else { return .running }
    if let last = lastHeartbeatAtMs,
       atMs - last < thresholds.bridgeUnresponsiveMs {
      return .upstreamSlow
    }
    return .bridgeUnresponsive
  }
}
