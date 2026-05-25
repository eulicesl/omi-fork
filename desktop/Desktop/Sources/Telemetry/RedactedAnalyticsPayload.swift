import Foundation

/// Marker protocol for chat-reliability telemetry payloads.
///
/// Strongly-typed payload structs (not `[String: Any]` dictionaries)
/// are how PR 0a enforces the privacy contract from
/// `MACOS_CHAT_RELIABILITY_ROADMAP.md`. Every chat-reliability event
/// is a Swift struct conforming to this protocol; reflection-based
/// tests scan the field names and fail CI if any matches the
/// redaction regex `prompt|sql|query|text|content|path|label|args|input|output|memory|transcript|ocr`.
///
/// The protocol itself is intentionally minimal — it just declares the
/// event name. The fields a payload exposes are validated entirely by
/// `AnalyticsRedactionTests` walking the struct's `Mirror`.
///
/// Implementations also expose an `asProperties` dictionary that gets
/// merged with `BuildMetadataTags.current.asProperties` at emit time.
/// That conversion happens in one place (`AnalyticsManager`) so the
/// struct authors don't have to think about PostHog's dictionary shape.
protocol RedactedAnalyticsPayload {
  /// The PostHog event name. Must be stable across releases — it's
  /// what dashboards filter on.
  static var eventName: String { get }

  /// Convert the strongly-typed fields into PostHog's property
  /// dictionary. Implementations should serialize their fields with
  /// the same keys the struct uses (no rewrites here — the reflection
  /// test validates the struct, not this dictionary).
  var asProperties: [String: Any] { get }
}
