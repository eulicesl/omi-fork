import XCTest

@testable import Omi_Computer

/// PR 0a Commit B: enforces the privacy contract from
/// `MACOS_CHAT_RELIABILITY_ROADMAP.md`.
///
/// Every chat-reliability telemetry payload is a Swift struct
/// conforming to `RedactedAnalyticsPayload`. This test class walks
/// each struct's fields via `Mirror` and fails CI if any field name
/// matches the redaction regex
/// `prompt|sql|query|text|content|path|label|args|input|output|memory|transcript|ocr`.
///
/// The same check is applied to `asProperties` keys — catches the
/// case where a struct field is renamed safely but the
/// dictionary-emit path still uses the forbidden key.
final class AnalyticsRedactionTests: XCTestCase {

  /// Forbidden substrings (lowercased) inside ANY field name on a
  /// chat-reliability payload. Drawn directly from the contract in
  /// the roadmap doc — kept narrow so allowlisted identifiers like
  /// `turnId`, `bridgeMode`, `model`, `outcome`, `toolNames` pass.
  private let forbiddenSubstrings = [
    "prompt",
    "sql",
    "query",
    "text",
    "content",
    "path",
    "label",
    "args",
    "input",
    "output",
    "memory",
    "transcript",
    "ocr",
  ]

  // MARK: - Per-payload contract

  func testChatTurnStartedPayloadFieldNamesAreAllowed() {
    let payload = ChatTurnStartedPayload(
      turnId: "t1",
      bridgeMode: "piMono",
      model: "claude-sonnet-4-6",
      hashedUserId: "abc123=="
    )
    assertRedaction(payload)
  }

  func testChatTurnCompletedPayloadFieldNamesAreAllowed() {
    let payload = ChatTurnCompletedPayload(
      turnId: "t1",
      bridgeMode: "piMono",
      model: "claude-sonnet-4-6",
      hashedUserId: "abc123==",
      outcome: .completed,
      totalMs: 3400,
      firstTokenMs: 250,
      toolCallCount: 2,
      toolNames: ["execute_sql", "semantic_search"],
      stallEventsEmitted: 0,
      errorClass: nil
    )
    assertRedaction(payload)
  }

  func testChatTurnFeedbackPayloadFieldNamesAreAllowed() {
    let payload = ChatTurnFeedbackPayload(
      turnId: "t1",
      bridgeMode: "piMono",
      hashedUserId: "abc123==",
      rating: .thumbsUp
    )
    assertRedaction(payload)
  }

  // MARK: - Build metadata also passes

  func testBuildMetadataTagsAsPropertiesKeysAreAllowed() {
    // BuildMetadataTags isn't a RedactedAnalyticsPayload, but its
    // `asProperties` keys get merged into every chat-reliability
    // emit. They must obey the same contract.
    let props = BuildMetadataTags.current.asProperties
    for key in props.keys {
      assertNoForbiddenSubstring(in: key, contextLabel: "BuildMetadataTags property key")
    }
  }

  // MARK: - Negative test (the test itself works)

  /// Sanity check: a payload with a forbidden field name actually
  /// trips the redaction check. Without this, a bug in the assertion
  /// helper would silently pass everything.
  func testRedactionAssertionCatchesObviousViolations() {
    struct ContrabandPayload: RedactedAnalyticsPayload {
      static let eventName = "test.contraband"
      let turnId: String
      let userPrompt: String  // <- "prompt" substring; must fail.
      var asProperties: [String: Any] { ["turnId": turnId, "userPrompt": userPrompt] }
    }
    let contraband = ContrabandPayload(turnId: "t1", userPrompt: "hello")
    var caught = false
    inspectFields(contraband) { fieldName in
      if forbiddenSubstrings.contains(where: { fieldName.lowercased().contains($0) }) {
        caught = true
      }
    }
    XCTAssertTrue(
      caught,
      "redaction assertion helper failed to detect 'userPrompt' as a violation — assertion logic is broken, not the payloads"
    )
  }

  // MARK: - Helpers

  private func assertRedaction<P: RedactedAnalyticsPayload>(_ payload: P) {
    // Check struct field names.
    inspectFields(payload) { fieldName in
      assertNoForbiddenSubstring(
        in: fieldName,
        contextLabel: "\(type(of: payload)) field"
      )
    }
    // Check `asProperties` keys — defense in depth in case a struct
    // emits a different key name than its Swift property.
    for key in payload.asProperties.keys {
      assertNoForbiddenSubstring(
        in: key,
        contextLabel: "\(type(of: payload)).asProperties key"
      )
    }
  }

  private func assertNoForbiddenSubstring(in name: String, contextLabel: String) {
    let lower = name.lowercased()
    for forbidden in forbiddenSubstrings {
      XCTAssertFalse(
        lower.contains(forbidden),
        """
        \(contextLabel) '\(name)' contains forbidden substring '\(forbidden)'.
        Chat-reliability telemetry forbids any field whose name hints \
        at carrying raw user content. Rename the field (e.g. text → outcome, \
        sql → toolName) or — if this really is structural metadata — \
        add an explicit allowlist exception to AnalyticsRedactionTests \
        with a written justification.
        """
      )
    }
  }

  private func inspectFields<P>(_ payload: P, _ visit: (String) -> Void) {
    let mirror = Mirror(reflecting: payload)
    for child in mirror.children {
      guard let label = child.label else { continue }
      visit(label)
    }
  }
}
