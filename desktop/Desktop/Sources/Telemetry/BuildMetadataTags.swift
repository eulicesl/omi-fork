import Foundation

/// Build/release metadata tagged onto every chat-reliability telemetry
/// event so the PostHog dashboards can distinguish dev-bundle traffic
/// from real users.
///
/// Property naming follows the `build_*` prefix convention locked in
/// `MACOS_CHAT_RELIABILITY_ROADMAP.md` — verified against PostHog's
/// actual property inventory (0/159 events use `omi_*`; existing
/// convention is domain-prefix or bare names). `build_app_name`
/// deliberately differs from the bare `app_name` property emitted
/// elsewhere to avoid collision.
///
/// Production dashboards filter `build_dev_bundle != true` (NOT
/// `= false`). HogQL treats missing ≠ false, so `= false` would
/// exclude every event predating PR 0a's emission. The `!= true`
/// form correctly matches both "property absent" (historical data)
/// and "property explicitly false" (future non-dev-bundle emits).
struct BuildMetadataTags: Sendable, Equatable {
  /// True for named bundles (`com.omi.omi-*`) and "Omi Dev"
  /// (`com.omi.desktop-dev`); false for production
  /// (`com.omi.computer-macos`). Matches `AppBuild.isNonProduction`.
  let devBundle: Bool

  /// Full bundle identifier (e.g. `com.omi.omi-chat-reliability`).
  let bundleId: String

  /// Display name from `CFBundleName` (or `CFBundleDisplayName` if
  /// set). For named bundles this matches `OMI_APP_NAME` (e.g.
  /// `omi-chat-reliability`); for prod it's `omi`.
  let appName: String

  /// Git commit SHA the build was produced from. Read from
  /// `BuildGitSha` Info.plist key when present; falls back to
  /// `"unknown"` for local builds without injection. Future work:
  /// have `run.sh` inject this so named-bundle telemetry can be
  /// sliced per-PR.
  let gitSha: String

  /// Git branch the build was produced from. Read from `BuildGitBranch`
  /// Info.plist key with the same fallback story as `gitSha`.
  let branch: String

  /// Coarse environment classifier:
  /// - `"production"` for the prod bundle id.
  /// - `"named-bundle-dev"` for any `com.omi.omi-*` named bundle.
  /// - `"dev"` for any other non-production bundle (e.g. `Omi Dev`).
  let environment: String

  /// PostHog-shaped property dictionary. Keys carry the `build_*`
  /// prefix; the names here intentionally don't match the Swift
  /// property names because the wire format is what PostHog
  /// dashboards filter on.
  var asProperties: [String: Any] {
    [
      "build_dev_bundle": devBundle,
      "build_bundle_id": bundleId,
      "build_app_name": appName,
      "build_git_sha": gitSha,
      "build_branch": branch,
      "build_environment": environment,
    ]
  }

  /// Singleton-style accessor — production code uses this. Tests can
  /// construct instances directly.
  static let current: BuildMetadataTags = {
    let bundleId = AppBuild.bundleIdentifier
    let devBundle = AppBuild.isNonProduction
    return BuildMetadataTags(
      devBundle: devBundle,
      bundleId: bundleId,
      appName: AppBuild.displayName,
      gitSha: infoPlistString(forKey: "BuildGitSha") ?? "unknown",
      branch: infoPlistString(forKey: "BuildGitBranch") ?? "unknown",
      environment: classifyEnvironment(bundleId: bundleId, devBundle: devBundle)
    )
  }()

  static func classifyEnvironment(bundleId: String, devBundle: Bool) -> String {
    if !devBundle { return "production" }
    if bundleId.hasPrefix("com.omi.omi-") { return "named-bundle-dev" }
    return "dev"
  }

  private static func infoPlistString(forKey key: String) -> String? {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty
    else { return nil }
    return value
  }
}
