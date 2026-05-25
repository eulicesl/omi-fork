import Foundation

/// Test-only mirror of `AgentBridge.InboundMessage` extended with out-of-band
/// signals that real bridge runs don't surface as discrete events:
///
/// - `heartbeat` — emitted by the Node bridge in PR 8 to distinguish
///   bridge-dead from upstream-slow.
/// - `malformed` — a stdout line that didn't parse as JSON or didn't
///   match any known message type. The real bridge logs and skips; the
///   fake surfaces it so tests can observe the parser's recovery path.
/// - `bridgeCrash` — the bridge subprocess died mid-turn. The real path
///   surfaces this as process termination; the fake fires this as a
///   discrete event so consumers can observe it without spawning a real
///   subprocess.
///
/// Fidelity tradeoff: `toolUse` / `toolActivity` inputs and `authRequired`
/// methods use `[String: String]` / `[String]` here instead of the real
/// `[String: Any]` / `[[String: Any]]`. Conforming to `Equatable` is
/// worth more than perfect fidelity for the failure modes PR 0b through
/// PR 8 actually exercise. Extend the types if a downstream PR needs
/// richer payloads.
enum FakeBridgeEvent: Equatable {
  case initSession(sessionId: String)
  case textDelta(text: String)
  case thinkingDelta(text: String)
  case toolUse(callId: String, name: String, input: [String: String])
  case toolActivity(name: String, status: String, toolUseId: String?, input: [String: String]?)
  case toolResultDisplay(toolUseId: String, name: String, output: String)
  case result(
    text: String,
    sessionId: String,
    costUsd: Double?,
    inputTokens: Int,
    outputTokens: Int,
    cacheReadTokens: Int,
    cacheWriteTokens: Int
  )
  case error(message: String)
  case authRequired(methods: [String], authUrl: String?)
  case authSuccess

  /// PR 8 heartbeat: bridge uptime and ms since the last upstream event.
  case heartbeat(uptimeMs: Int, upstreamLastEventMs: Int)

  /// Stdout line that didn't parse / didn't match a known message type.
  case malformed(rawLine: String)

  /// Bridge subprocess died mid-turn. Terminates the script.
  case bridgeCrash
}
