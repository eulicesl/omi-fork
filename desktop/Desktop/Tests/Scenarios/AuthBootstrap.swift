import Foundation
import FirebaseCore

@testable import Omi_Computer

// MARK: - AuthBootstrap (PR 7 — Phase 2 prep)
//
// Bootstraps a test process to the point where capability scenarios
// CAN run against the real backend. Reads the auth state captured by
// `desktop/scripts/omi-auth-dump.sh`, populates the test process's
// own UserDefaults (the xctest binary has its own preferences domain
// — separate from any named bundle), and configures Firebase from
// `Sources/GoogleService-Info-Dev.plist`.
//
// What this does NOT do (out of scope for this helper):
//   - Sign in / refresh tokens. The auth-dump file carries whatever
//     credentials existed when it was captured; expired tokens are
//     reported but not refreshed (the operator re-runs auth-dump).
//   - Construct a ChatProvider. ChatProvider has no DI seam for the
//     bridge today; capability scenarios use ChatProvider.shared if
//     they choose to, but that lifts in a follow-up PR.
//   - Talk to the VM. AgentVMService boot is gated on auth + network;
//     once this helper succeeds, capability scenarios can attempt VM
//     work and surface clean errors if the VM is unreachable.
//
// **Idempotent**: safe to call from XCTest setUp() in every test;
// FirebaseApp.configure() is no-op'd if a default app already exists.
//
// **Manual prerequisite** (the operator does this before running
// capability scenarios):
//   1. Sign into the named bundle once: launch
//      `OMI_APP_NAME="omi-chat-reliability" ./run.sh`, sign in as the
//      eval UID rg0PvY9mhKRARcYxkHHYh4iAkc12.
//   2. Run `desktop/scripts/omi-auth-dump.sh com.omi.omi-chat-reliability`
//      to capture the session to `desktop/tmp/desktop-auth.json`.
//   3. Run capability scenarios within ~1h before the idToken expires.

enum AuthBootstrap {

  // MARK: - Public surface

  /// Outcome of `bootstrap()`. Has enough detail that the operator can
  /// fix specific blockers without re-running tests blindly.
  struct Result: Sendable {
    /// Overall status. `.ready` only when every blocker is clear.
    let status: Status

    /// Subset of auth keys missing from the dump file (empty list when
    /// the dump is complete OR when no file was found — see `status`).
    let missingFields: [String]

    /// Whether FirebaseApp.configure(...) succeeded (or the default
    /// app was already configured from a prior test).
    let firebaseConfigured: Bool

    /// Seconds until the captured idToken expires. Negative means
    /// already expired. `nil` when no token was loaded.
    let tokenExpiresInSeconds: TimeInterval?

    /// Path of the JSON file read (or attempted). Useful for the
    /// operator to know exactly which file to refresh.
    let dumpFilePath: String

    /// Human-readable single-line summary. Stable enough to grep in
    /// test output: `"[AuthBootstrap] status=<...> blockers=<...>"`.
    var summary: String {
      var blockers: [String] = []
      if status == .noDumpFile { blockers.append("no auth-dump file") }
      if status == .emptyDumpFile { blockers.append("auth-dump file is empty") }
      if !missingFields.isEmpty { blockers.append("missing fields: \(missingFields.joined(separator: ","))") }
      if let expiry = tokenExpiresInSeconds, expiry <= 0 { blockers.append("token expired \(Int(-expiry))s ago") }
      if !firebaseConfigured { blockers.append("firebase not configured") }
      let blockerStr = blockers.isEmpty ? "none" : blockers.joined(separator: "; ")
      return "[AuthBootstrap] status=\(status.rawValue) blockers=\(blockerStr) path=\(dumpFilePath)"
    }
  }

  enum Status: String, Sendable {
    /// All prerequisites met — capability scenarios may proceed.
    case ready

    /// `desktop/tmp/desktop-auth.json` does not exist. Operator runs
    /// `omi-auth-dump.sh <named-bundle>` first.
    case noDumpFile

    /// The dump file exists but is `{}` or has no `auth_*` keys.
    /// Operator likely ran auth-dump before signing into the named
    /// bundle.
    case emptyDumpFile

    /// Dump file present, but one or more required `auth_*` keys are
    /// missing. See `missingFields`.
    case incompleteDumpFile

    /// Dump file complete but the idToken has expired. Operator
    /// re-signs in and re-runs auth-dump.
    case tokenExpired

    /// FirebaseApp.configure(...) failed (typically because the
    /// GoogleService-Info-Dev.plist isn't reachable from the test
    /// process's CWD).
    case firebaseConfigureFailed
  }

  // MARK: - Constants

  /// Keys the auth-dump script captures. The test process needs
  /// every one of these populated for AuthService.restoreAuthState()
  /// to recover a signed-in session.
  static let requiredAuthKeys: [String] = [
    "auth_isSignedIn",
    "auth_userEmail",
    "auth_userId",
    "auth_idToken",
    "auth_refreshToken",
    "auth_tokenExpiry",
    "auth_tokenUserId",
  ]

  // MARK: - Entry point

  /// Run the full bootstrap. Idempotent. Returns a Result describing
  /// what worked and what didn't. Never throws — every blocker is
  /// reported via `status` + `missingFields`.
  ///
  /// - Parameter dumpFilePath: absolute path to the auth-dump JSON.
  ///   Default: `<repo>/desktop/tmp/desktop-auth.json` based on the
  ///   test process's CWD (which is the SwiftPM package root when
  ///   tests run via `xcrun swift test`).
  static func bootstrap(dumpFilePath: String? = nil) async -> Result {
    let path = dumpFilePath ?? defaultDumpPath()

    // -- Step 1: load auth-dump JSON --
    guard FileManager.default.fileExists(atPath: path) else {
      return Result(
        status: .noDumpFile,
        missingFields: requiredAuthKeys,
        firebaseConfigured: false,
        tokenExpiresInSeconds: nil,
        dumpFilePath: path
      )
    }
    guard
      let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
    else {
      return Result(
        status: .emptyDumpFile,
        missingFields: requiredAuthKeys,
        firebaseConfigured: false,
        tokenExpiresInSeconds: nil,
        dumpFilePath: path
      )
    }
    if json.isEmpty {
      return Result(
        status: .emptyDumpFile,
        missingFields: requiredAuthKeys,
        firebaseConfigured: false,
        tokenExpiresInSeconds: nil,
        dumpFilePath: path
      )
    }

    // -- Step 2: confirm every required key is present --
    let missingFields = requiredAuthKeys.filter { json[$0] == nil }
    if !missingFields.isEmpty {
      return Result(
        status: .incompleteDumpFile,
        missingFields: missingFields,
        firebaseConfigured: false,
        tokenExpiresInSeconds: nil,
        dumpFilePath: path
      )
    }

    // -- Step 3: populate test process's UserDefaults.standard --
    populateUserDefaults(from: json)

    // -- Step 4: parse + check token expiry --
    let tokenExpiresInSeconds = parseTokenExpiry(from: json)
    if let expiry = tokenExpiresInSeconds, expiry <= 0 {
      // Configure Firebase anyway so the operator can verify the
      // rest of the chain works after re-dumping auth.
      let firebaseOK = configureFirebase()
      return Result(
        status: .tokenExpired,
        missingFields: [],
        firebaseConfigured: firebaseOK,
        tokenExpiresInSeconds: expiry,
        dumpFilePath: path
      )
    }

    // -- Step 5: configure Firebase --
    let firebaseOK = configureFirebase()
    if !firebaseOK {
      return Result(
        status: .firebaseConfigureFailed,
        missingFields: [],
        firebaseConfigured: false,
        tokenExpiresInSeconds: tokenExpiresInSeconds,
        dumpFilePath: path
      )
    }

    return Result(
      status: .ready,
      missingFields: [],
      firebaseConfigured: true,
      tokenExpiresInSeconds: tokenExpiresInSeconds,
      dumpFilePath: path
    )
  }

  // MARK: - Internal helpers

  /// Default path under which auth-dump.sh writes. Resolved relative
  /// to the test process's CWD (`desktop/Desktop/` when tests run via
  /// `xcrun swift test`). The dump script writes to `desktop/tmp/`,
  /// which is `../tmp/` from the test CWD.
  private static func defaultDumpPath() -> String {
    let cwd = FileManager.default.currentDirectoryPath
    return "\(cwd)/../tmp/desktop-auth.json"
  }

  /// Write each key/value into UserDefaults.standard, converting
  /// string-encoded values back to their original type per the dump
  /// file's `type` annotation.
  private static func populateUserDefaults(from json: [String: [String: String]]) {
    let defaults = UserDefaults.standard
    for (key, info) in json {
      guard let type = info["type"], let value = info["value"] else { continue }
      switch type {
      case "boolean":
        let v = value.lowercased()
        defaults.set(v == "1" || v == "true" || v == "yes", forKey: key)
      case "integer":
        if let i = Int(value) { defaults.set(i, forKey: key) }
      case "float":
        if let f = Double(value) { defaults.set(f, forKey: key) }
      default:
        defaults.set(value, forKey: key)
      }
    }
  }

  /// Seconds until the idToken expires, based on the
  /// `auth_tokenExpiry` field. `defaults` writes dates as a
  /// human-readable ISO-8601 timestamp; we parse loosely because
  /// the format has shifted across macOS versions.
  private static func parseTokenExpiry(from json: [String: [String: String]]) -> TimeInterval? {
    guard let raw = json["auth_tokenExpiry"]?["value"] else { return nil }

    // Try ISO-8601 (e.g. "2026-05-28T12:34:56Z")
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime]
    if let date = isoFormatter.date(from: raw) {
      return date.timeIntervalSinceNow
    }

    // Try `defaults`'s default format ("2026-05-28 12:34:56 +0000")
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    if let date = formatter.date(from: raw) {
      return date.timeIntervalSinceNow
    }

    // Try Unix epoch seconds (some captures store as double)
    if let seconds = Double(raw) {
      return Date(timeIntervalSince1970: seconds).timeIntervalSinceNow
    }

    return nil
  }

  /// Configure FirebaseApp from the dev plist if not already
  /// configured. Idempotent — returns true when the default app is
  /// reachable after this call, regardless of who configured it.
  private static func configureFirebase() -> Bool {
    if FirebaseApp.app() != nil { return true }

    // Test process's Bundle.main is the xctest binary, which doesn't
    // package the plist. Resolve it from CWD (the SwiftPM package
    // root — `desktop/Desktop/` when tests run via `xcrun swift test`).
    let cwd = FileManager.default.currentDirectoryPath
    let plistPath = "\(cwd)/Sources/GoogleService-Info-Dev.plist"

    guard FileManager.default.fileExists(atPath: plistPath) else {
      return false
    }
    guard let options = FirebaseOptions(contentsOfFile: plistPath) else {
      return false
    }
    FirebaseApp.configure(options: options)
    return FirebaseApp.app() != nil
  }
}
