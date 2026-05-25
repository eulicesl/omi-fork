import Foundation

/// Programmable replacement for `AgentBridge` used by chat-reliability
/// tests. Runs a `FakeBridgeScript` and dispatches each event to the
/// matching test callback, recording the dispatch sequence for assertion.
///
/// PR 0b ships instant-mode only: every event fires synchronously in
/// script order with no inter-event delay. This makes scenarios
/// deterministic across arbitrarily many runs — required by the
/// "100-run determinism" exit criterion. Real-time and simulated-clock
/// modes are deferred to PR 1, which owns the clock abstraction the
/// stall detector consumes.
///
/// The fake does not implement the full `AgentBridge` actor surface (no
/// process lifecycle, no warmup, no token refresh) — only the
/// callback-dispatch path PRs 1, 3, 4, 7, and 8 need.
actor FakeAgentBridge {
  let script: FakeBridgeScript

  /// True once `interrupt()` is called or the scheduled interrupt fires.
  private(set) var interrupted = false

  /// If set, `runInstant` flips `interrupted` to true on the first event
  /// whose `atMs` is >= this value. Drives interrupt-during-tool tests
  /// without wall-clock racing.
  private var interruptAtMs: Int?

  init(script: FakeBridgeScript) {
    self.script = script
  }

  func scheduleInterrupt(atMs: Int) {
    self.interruptAtMs = atMs
  }

  /// Mirrors `AgentBridge.interrupt()`. Idempotent.
  func interrupt() {
    self.interrupted = true
  }

  // MARK: - Run record

  enum Outcome: Equatable {
    /// Script reached a `.result` event. The associated value is the
    /// raw `FakeBridgeEvent.result` for assertion convenience.
    case completed(result: FakeBridgeEvent)
    /// Script reached a `.error` event.
    case errored(message: String)
    /// Script was interrupted before reaching a terminal event.
    case interrupted
    /// Script reached a `.bridgeCrash` event.
    case crashed
    /// Script's last event was non-terminal — the bridge effectively
    /// hung. Matches the never-returning-tool scenario when it doesn't
    /// emit a trailing error.
    case neverTerminated
  }

  struct RunRecord: Equatable {
    let scenarioName: String
    let callbacks: [Callback]
    let outcome: Outcome

    /// Test-facing record of which callback fired with which key data.
    /// Drops `[String: String]` tool inputs from comparison to keep
    /// records compact; the original event is in `script.events` if a
    /// test needs the full payload.
    enum Callback: Equatable {
      case initSession(sessionId: String)
      case textDelta(String)
      case thinkingDelta(String)
      case toolUse(callId: String, name: String)
      case toolActivity(name: String, status: String, toolUseId: String?)
      case toolResultDisplay(toolUseId: String, name: String, output: String)
      case authRequired
      case authSuccess
      case heartbeat(uptimeMs: Int, upstreamLastEventMs: Int)
      case malformed(rawLine: String)
      case crash
    }
  }

  // MARK: - Instant runner

  /// Run the script with no inter-event delay, dispatching each event in
  /// order to the matching callback. Returns the recorded callback
  /// sequence and the terminal outcome.
  ///
  /// All callbacks are optional. Callers wire only the ones they care
  /// about; unwired events still appear in the returned record.
  func runInstant(
    onInit: ((String) -> Void)? = nil,
    onTextDelta: ((String) -> Void)? = nil,
    onThinkingDelta: ((String) -> Void)? = nil,
    onToolUse: ((String, String, [String: String]) async -> String)? = nil,
    onToolActivity: ((String, String, String?, [String: String]?) -> Void)? = nil,
    onToolResultDisplay: ((String, String, String) -> Void)? = nil,
    onAuthRequired: (([String], String?) -> Void)? = nil,
    onAuthSuccess: (() -> Void)? = nil,
    onHeartbeat: ((Int, Int) -> Void)? = nil,
    onMalformed: ((String) -> Void)? = nil,
    onCrash: (() -> Void)? = nil
  ) async -> RunRecord {
    var recorded: [RunRecord.Callback] = []

    for timed in script.events {
      // Honor scheduled interrupt: if this event lies on/after the
      // scheduled mark, flip the flag before dispatching.
      if let mark = interruptAtMs, timed.atMs >= mark {
        interrupted = true
      }
      if interrupted {
        return RunRecord(
          scenarioName: script.name,
          callbacks: recorded,
          outcome: .interrupted
        )
      }

      switch timed.event {
      case .initSession(let sessionId):
        recorded.append(.initSession(sessionId: sessionId))
        onInit?(sessionId)

      case .textDelta(let text):
        recorded.append(.textDelta(text))
        onTextDelta?(text)

      case .thinkingDelta(let text):
        recorded.append(.thinkingDelta(text))
        onThinkingDelta?(text)

      case .toolUse(let callId, let name, let input):
        recorded.append(.toolUse(callId: callId, name: name))
        _ = await onToolUse?(callId, name, input)

      case .toolActivity(let name, let status, let toolUseId, let input):
        recorded.append(.toolActivity(
          name: name, status: status, toolUseId: toolUseId
        ))
        onToolActivity?(name, status, toolUseId, input)

      case .toolResultDisplay(let toolUseId, let name, let output):
        recorded.append(.toolResultDisplay(
          toolUseId: toolUseId, name: name, output: output
        ))
        onToolResultDisplay?(toolUseId, name, output)

      case .result:
        // Terminal. Do not record result as a callback — it's the
        // outcome.
        return RunRecord(
          scenarioName: script.name,
          callbacks: recorded,
          outcome: .completed(result: timed.event)
        )

      case .error(let message):
        return RunRecord(
          scenarioName: script.name,
          callbacks: recorded,
          outcome: .errored(message: message)
        )

      case .authRequired(let methods, let authUrl):
        recorded.append(.authRequired)
        onAuthRequired?(methods, authUrl)

      case .authSuccess:
        recorded.append(.authSuccess)
        onAuthSuccess?()

      case .heartbeat(let uptimeMs, let upstreamLastEventMs):
        recorded.append(.heartbeat(
          uptimeMs: uptimeMs,
          upstreamLastEventMs: upstreamLastEventMs
        ))
        onHeartbeat?(uptimeMs, upstreamLastEventMs)

      case .malformed(let rawLine):
        recorded.append(.malformed(rawLine: rawLine))
        onMalformed?(rawLine)

      case .bridgeCrash:
        recorded.append(.crash)
        onCrash?()
        return RunRecord(
          scenarioName: script.name,
          callbacks: recorded,
          outcome: .crashed
        )
      }
    }

    // Script exhausted without hitting a terminal event.
    return RunRecord(
      scenarioName: script.name,
      callbacks: recorded,
      outcome: .neverTerminated
    )
  }
}
