import Foundation

// PR 0a payload structs for the three chat-reliability events
// (`chat.turn.started`, `chat.turn.completed`, `chat.turn.feedback`).
// Every field name is policed by `AnalyticsRedactionTests` against the
// privacy contract — see `RedactedAnalyticsPayload`.

/// Fired synchronously when `ChatProvider.sendMessage` commits a turn,
/// *before* any bridge call, tool call, auth check, or model stream
/// begins. `started − completed` is the orphan / stuck-turn detector.
struct ChatTurnStartedPayload: RedactedAnalyticsPayload, Equatable {
  static let eventName = "chat.turn.started"

  let turnId: String
  let bridgeMode: String
  let model: String?
  /// HMAC-SHA256 over the Firebase UID with the per-env salt
  /// (`OMI_TELEMETRY_HMAC_SALT`). Never contains the raw UID.
  let hashedUserId: String?

  var asProperties: [String: Any] {
    var props: [String: Any] = [
      "turnId": turnId,
      "bridgeMode": bridgeMode,
    ]
    if let model { props["model"] = model }
    if let hashedUserId { props["hashedUserId"] = hashedUserId }
    return props
  }
}

/// Fired on turn finalize — success, failure, interrupt, or timeout.
/// Joined to `chat.turn.started` by `turnId`. The redaction contract
/// forbids any raw text fields here; what's allowed is sizes, counts,
/// status enums, tool names from the fixed allow-list, and durations.
struct ChatTurnCompletedPayload: RedactedAnalyticsPayload, Equatable {
  static let eventName = "chat.turn.completed"

  enum Outcome: String, Sendable {
    case completed
    case interrupted
    case errored
    case timeout
  }

  let turnId: String
  let bridgeMode: String
  let model: String?
  let hashedUserId: String?
  let outcome: Outcome
  let totalMs: Int
  let firstTokenMs: Int?
  let toolCallCount: Int
  /// Tool names invoked during the turn. Must be a subset of
  /// `ChatToolExecutor.allRegisteredToolNames` — the redaction test
  /// will allow these names through the field-name regex because
  /// they're an enum-like fixed allow-list.
  let toolNames: [String]
  /// Count of stall transitions surfaced during this turn (any of
  /// .slow, .stalled, .upstreamSlow, .bridgeUnresponsive). Drives PR 1
  /// → PR 8 telemetry: how often does stall detection fire in prod.
  let stallEventsEmitted: Int
  /// `errorClass` only when `outcome == .errored` or `.timeout`. Must
  /// be an enum-shaped string, not a free-form error message.
  let errorClass: String?

  var asProperties: [String: Any] {
    var props: [String: Any] = [
      "turnId": turnId,
      "bridgeMode": bridgeMode,
      "outcome": outcome.rawValue,
      "totalMs": totalMs,
      "toolCallCount": toolCallCount,
      "toolNames": toolNames,
      "stallEventsEmitted": stallEventsEmitted,
    ]
    if let model { props["model"] = model }
    if let hashedUserId { props["hashedUserId"] = hashedUserId }
    if let firstTokenMs { props["firstTokenMs"] = firstTokenMs }
    if let errorClass { props["errorClass"] = errorClass }
    return props
  }
}

/// Fired on thumbs 👍 / 👎. Joined to `chat.turn.completed` by
/// `turnId` so the dashboard can compute like_ratio per cohort.
struct ChatTurnFeedbackPayload: RedactedAnalyticsPayload, Equatable {
  static let eventName = "chat.turn.feedback"

  enum Rating: String, Sendable {
    case thumbsUp
    case thumbsDown
  }

  let turnId: String
  let bridgeMode: String
  let hashedUserId: String?
  let rating: Rating

  var asProperties: [String: Any] {
    var props: [String: Any] = [
      "turnId": turnId,
      "bridgeMode": bridgeMode,
      "rating": rating.rawValue,
    ]
    if let hashedUserId { props["hashedUserId"] = hashedUserId }
    return props
  }
}
