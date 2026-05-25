import CryptoKit
import Foundation

/// HMAC-SHA256 user-id hasher for chat-reliability telemetry.
///
/// Reads the salt from `OMI_TELEMETRY_HMAC_SALT` (env var, locked
/// in `MACOS_CHAT_RELIABILITY_ROADMAP.md`). When the env var is
/// unset, falls back to the literal `dev-local-salt-do-not-use-in-prod`
/// and flags itself as a dev fallback so a startup warning fires.
///
/// The same warning ALSO fires when the env var is set but its value
/// equals the dev-local literal — catches a bad copy-paste of the
/// fallback into a real prod env config at startup rather than after
/// data has been hashed. PR 0a's redaction tests assert the prod salt
/// is **not** that literal.
///
/// Output is base64-encoded SHA256 HMAC (44 chars including padding).
struct TelemetryUserIdHasher: Sendable {
  static let saltEnvVar = "OMI_TELEMETRY_HMAC_SALT"
  static let devLocalFallback = "dev-local-salt-do-not-use-in-prod"

  let salt: String
  let isDevFallback: Bool

  init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    if let envSalt = environment[Self.saltEnvVar], !envSalt.isEmpty {
      self.salt = envSalt
      // Dual-warning trigger: env var was set, but to the literal
      // fallback string. Means somebody copy-pasted the dev fallback
      // into a real prod env config.
      self.isDevFallback = envSalt == Self.devLocalFallback
    } else {
      self.salt = Self.devLocalFallback
      self.isDevFallback = true
    }
  }

  /// HMAC-SHA256 over `userId` keyed by `salt`. Returns base64-encoded
  /// digest (44 characters with `=` padding).
  func hash(_ userId: String) -> String {
    let key = SymmetricKey(data: Data(salt.utf8))
    let signature = HMAC<SHA256>.authenticationCode(
      for: Data(userId.utf8),
      using: key
    )
    return Data(signature).base64EncodedString()
  }

  /// Fire-once startup warning when the hasher is using the dev
  /// fallback. Idempotent across this process so noisy callers don't
  /// flood the log.
  static func emitStartupWarningIfNeeded(
    logger: (String) -> Void = { msg in log(msg) }
  ) {
    guard !warningEmitted else { return }
    warningEmitted = true
    let hasher = TelemetryUserIdHasher()
    guard hasher.isDevFallback else { return }
    if ProcessInfo.processInfo.environment[saltEnvVar]?.isEmpty == false {
      // Env var was set to the literal fallback string.
      logger(
        "TelemetryUserIdHasher: WARNING — \(saltEnvVar) is set to the dev-local fallback literal. "
          + "Prod environments must use a long-lived per-environment secret, not this string."
      )
    } else {
      // Env var was unset entirely.
      logger(
        "TelemetryUserIdHasher: WARNING — \(saltEnvVar) is unset; falling back to dev-local literal. "
          + "Prod environments must set it to a long-lived per-environment secret."
      )
    }
  }

  private static var warningEmitted = false
}
