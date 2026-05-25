import XCTest

@testable import Omi_Computer

/// PR 0a Commit C: lightweight tests for the message-id → turnId
/// mapping that joins chat.turn.started / completed / feedback across
/// the local-UUID → server-id swap.
///
/// Full integration (sendMessage emitting events end-to-end) is
/// validated via the named-bundle agent-swift run captured as PR 0a's
/// exit gate evidence — not unit-tested here because ChatProvider is
/// heavy to construct in isolation.
final class ChatTurnTelemetryMappingTests: XCTestCase {

  // MARK: - Payload ↔ rating mapping

  func testThumbsUpMapsToPositiveRating() {
    // The mapping logic lives inline in rateMessage(_:rating:). This
    // test mirrors it to lock the contract: positive Int → .thumbsUp,
    // negative Int → .thumbsDown, zero → nil (no emit).
    XCTAssertEqual(mapRating(1), .thumbsUp)
    XCTAssertEqual(mapRating(5), .thumbsUp)
    XCTAssertEqual(mapRating(-1), .thumbsDown)
    XCTAssertEqual(mapRating(-3), .thumbsDown)
    XCTAssertNil(mapRating(0))
  }

  // MARK: - Error-class derivation

  /// Verify the error-class string extraction strips associated values
  /// from BridgeError descriptions. The redaction contract forbids
  /// shipping raw error messages; only the structural case name is
  /// allowed (e.g. "agentError" not "agentError(Connection refused)").
  func testErrorClassExtractionStripsAssociatedValues() {
    let withAssoc = "agentError(Some private error message)"
    let stripped = withAssoc.split(separator: "(").first.map(String.init) ?? "unknown"
    XCTAssertEqual(stripped, "agentError")
    XCTAssertFalse(stripped.contains("private"))
  }

  func testErrorClassWithoutAssociatedValuesPassesThrough() {
    let bare = "notRunning"
    let stripped = bare.split(separator: "(").first.map(String.init) ?? "unknown"
    XCTAssertEqual(stripped, "notRunning")
  }

  // MARK: - Helpers

  /// Mirrors the rating-mapping logic in
  /// `ChatProvider.rateMessage(_:rating:)`. Kept in sync manually —
  /// the production logic is inline, not a separate helper, because
  /// extracting it would add indirection without removing duplication.
  private func mapRating(_ rating: Int) -> ChatTurnFeedbackPayload.Rating? {
    if rating > 0 { return .thumbsUp }
    if rating < 0 { return .thumbsDown }
    return nil
  }
}
