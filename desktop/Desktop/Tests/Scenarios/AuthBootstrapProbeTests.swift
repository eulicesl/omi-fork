import XCTest

@testable import Omi_Computer

/// Reports the test process's Phase 2 readiness state.
///
/// This is a PROBE, not a strict pass/fail test — running it never
/// fails the suite. It always passes; the value is the structured
/// log output that tells the operator exactly which Phase 2
/// blockers remain. Capability scenarios skip themselves with a
/// matching reason, so the probe is the single place to inspect.
///
/// Pattern: open the test output, search for `[AuthBootstrap]` —
/// the one-line summary tells you every blocker in priority order.
final class AuthBootstrapProbeTests: XCTestCase {

  /// Run the bootstrap and print the summary to test output. This
  /// always passes — the test's purpose is the diagnostic log line,
  /// not a hard gate.
  func testProbeReportsBootstrapState() async throws {
    let result = await AuthBootstrap.bootstrap()
    print(result.summary)

    // Detailed breakdown to make field-by-field state visible:
    print("  status:                    \(result.status.rawValue)")
    print("  dumpFilePath:              \(result.dumpFilePath)")
    print("  firebaseConfigured:        \(result.firebaseConfigured)")
    if let expiry = result.tokenExpiresInSeconds {
      let expiryDesc =
        expiry > 0
        ? "expires in \(Int(expiry))s (\(Int(expiry / 60)) min)"
        : "expired \(Int(-expiry))s ago"
      print("  tokenExpiresInSeconds:     \(expiryDesc)")
    } else {
      print("  tokenExpiresInSeconds:     <nil>")
    }
    if !result.missingFields.isEmpty {
      print("  missingFields:             \(result.missingFields.joined(separator: ", "))")
    }

    // Always assert true — the value is the printed summary, not a
    // pass/fail signal. A future PR can flip this to an assert once
    // Phase 2 is provisioned and `status = .ready` becomes the
    // default expectation.
    XCTAssertTrue(true, "Probe always passes; check test log for the diagnostic line above.")
  }

  /// Sanity-check that AuthBootstrap.requiredAuthKeys covers exactly
  /// what omi-auth-dump.sh captures. Drift between the two would
  /// silently make capability scenarios fail with a confusing skip
  /// reason instead of a clear "missing field" report.
  func testRequiredAuthKeysMatchDumpScriptInventory() {
    let expected: Set<String> = [
      "auth_isSignedIn",
      "auth_userEmail",
      "auth_userId",
      "auth_idToken",
      "auth_refreshToken",
      "auth_tokenExpiry",
      "auth_tokenUserId",
    ]
    XCTAssertEqual(
      Set(AuthBootstrap.requiredAuthKeys), expected,
      "AuthBootstrap.requiredAuthKeys drifted from omi-auth-dump.sh's KEYS array. Update one to match the other."
    )
  }
}
