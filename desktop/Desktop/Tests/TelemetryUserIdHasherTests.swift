import XCTest

@testable import Omi_Computer

/// PR 0a Commit A: HMAC user-id hashing contract.
final class TelemetryUserIdHasherTests: XCTestCase {

  // MARK: - Determinism + isolation

  func testSameSaltAndUserIdProduceSameHash() {
    let a = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "prod-secret-xyz"])
    let b = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "prod-secret-xyz"])
    XCTAssertEqual(
      a.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12"),
      b.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12")
    )
  }

  /// Different salts must produce different hashes for the same user
  /// — this is what prevents dev hashes from being usable to identify
  /// the same person in prod (cohort tracking isolation).
  func testDifferentSaltsProduceDifferentHashes() {
    let dev = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "dev-secret"])
    let prod = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "prod-secret"])
    XCTAssertNotEqual(
      dev.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12"),
      prod.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12")
    )
  }

  func testHashOutputIsBase64SHA256Sized() {
    let hasher = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "salt"])
    let hashed = hasher.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12")
    // SHA256 → 32 bytes → base64 = 44 chars including padding.
    XCTAssertEqual(hashed.count, 44)
    XCTAssertTrue(hashed.hasSuffix("="), "base64 SHA256 always pads to a multiple of 4")
  }

  // MARK: - Dev-fallback semantics

  func testUnsetEnvVarFallsBackToDevLocalLiteral() {
    let hasher = TelemetryUserIdHasher(environment: [:])
    XCTAssertEqual(hasher.salt, TelemetryUserIdHasher.devLocalFallback)
    XCTAssertTrue(hasher.isDevFallback)
  }

  func testEmptyEnvVarFallsBackToDevLocalLiteral() {
    let hasher = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": ""])
    XCTAssertEqual(hasher.salt, TelemetryUserIdHasher.devLocalFallback)
    XCTAssertTrue(hasher.isDevFallback)
  }

  /// Dual-warning trigger: env var IS set, but to the dev-local literal.
  /// Catches a bad copy-paste of the fallback into a real prod env
  /// config — must be flagged at startup BEFORE any data is hashed.
  func testEnvVarSetToDevLocalLiteralStillTreatedAsDevFallback() {
    let hasher = TelemetryUserIdHasher(environment: [
      "OMI_TELEMETRY_HMAC_SALT": TelemetryUserIdHasher.devLocalFallback,
    ])
    XCTAssertEqual(hasher.salt, TelemetryUserIdHasher.devLocalFallback)
    XCTAssertTrue(
      hasher.isDevFallback,
      "setting OMI_TELEMETRY_HMAC_SALT to the dev-local literal must NOT count as 'configured for prod'"
    )
  }

  func testRealProdSaltIsNotFlaggedAsDevFallback() {
    let hasher = TelemetryUserIdHasher(environment: [
      "OMI_TELEMETRY_HMAC_SALT": "some-long-real-secret-aB3xK9p2QmRfL7wE",
    ])
    XCTAssertFalse(hasher.isDevFallback)
  }

  // MARK: - Privacy contract

  func testSaltIsNotPresentInHashOutput() {
    // The whole point of HMAC: salt is mixed in, never recoverable.
    // Sanity-check: the salt string doesn't appear verbatim in the
    // base64-encoded digest (would mean we accidentally concatenated).
    let salt = "very-distinctive-salt-string-12345"
    let hasher = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": salt])
    let hashed = hasher.hash("rg0PvY9mhKRARcYxkHHYh4iAkc12")
    XCTAssertFalse(hashed.contains(salt))
  }

  func testHashedUserIdDoesNotContainOriginalUserId() {
    // Same logic, applied to the user id itself.
    let userId = "rg0PvY9mhKRARcYxkHHYh4iAkc12"
    let hasher = TelemetryUserIdHasher(environment: ["OMI_TELEMETRY_HMAC_SALT": "salt"])
    let hashed = hasher.hash(userId)
    XCTAssertFalse(hashed.contains(userId))
  }
}
