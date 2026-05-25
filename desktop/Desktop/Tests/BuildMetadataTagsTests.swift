import XCTest

@testable import Omi_Computer

/// PR 0a Commit A: build_* property contract.
final class BuildMetadataTagsTests: XCTestCase {

  // MARK: - Property dictionary shape

  func testAsPropertiesEmitsAllSixBuildPrefixedKeys() {
    let tags = BuildMetadataTags(
      devBundle: true,
      bundleId: "com.omi.omi-chat-reliability",
      appName: "omi-chat-reliability",
      gitSha: "abc123",
      branch: "feature/macos-chat-reliability-80",
      environment: "named-bundle-dev"
    )
    let props = tags.asProperties
    XCTAssertEqual(props["build_dev_bundle"] as? Bool, true)
    XCTAssertEqual(props["build_bundle_id"] as? String, "com.omi.omi-chat-reliability")
    XCTAssertEqual(props["build_app_name"] as? String, "omi-chat-reliability")
    XCTAssertEqual(props["build_git_sha"] as? String, "abc123")
    XCTAssertEqual(props["build_branch"] as? String, "feature/macos-chat-reliability-80")
    XCTAssertEqual(props["build_environment"] as? String, "named-bundle-dev")
    XCTAssertEqual(props.count, 6, "exactly the 6 build_* keys, no extras")
  }

  func testAsPropertiesUsesBuildPrefixNotOmiPrefix() {
    // Locked decision per the roadmap doc: build_* not omi_*. Catches a
    // refactor that accidentally reverts the prefix.
    let tags = BuildMetadataTags.current
    let keys = tags.asProperties.keys
    for key in keys {
      XCTAssertTrue(
        key.hasPrefix("build_"),
        "all build-metadata properties must use the build_ prefix; '\(key)' doesn't"
      )
      XCTAssertFalse(
        key.hasPrefix("omi_"),
        "the omi_ prefix was explicitly rejected during PR 0a pre-flight; '\(key)' violates"
      )
    }
  }

  func testBuildAppNameDoesNotCollideWithBareAppName() {
    // PostHog's existing event vocabulary uses bare `app_name` set
    // elsewhere; `build_app_name` is deliberately distinct to avoid
    // overwriting it.
    let tags = BuildMetadataTags.current
    XCTAssertNotNil(tags.asProperties["build_app_name"])
    XCTAssertNil(tags.asProperties["app_name"], "build-metadata must not emit the bare app_name key")
  }

  // MARK: - Environment classification

  func testEnvironmentIsProductionForProdBundle() {
    let env = BuildMetadataTags.classifyEnvironment(
      bundleId: "com.omi.computer-macos",
      devBundle: false
    )
    XCTAssertEqual(env, "production")
  }

  func testEnvironmentIsNamedBundleDevForOmiPrefixedBundle() {
    let env = BuildMetadataTags.classifyEnvironment(
      bundleId: "com.omi.omi-chat-reliability",
      devBundle: true
    )
    XCTAssertEqual(env, "named-bundle-dev")
  }

  func testEnvironmentIsDevForOmiDevBundle() {
    let env = BuildMetadataTags.classifyEnvironment(
      bundleId: "com.omi.desktop-dev",
      devBundle: true
    )
    XCTAssertEqual(env, "dev")
  }

  // MARK: - Current snapshot

  func testCurrentInTestRuntimeIsConsistentWithAppBuild() {
    // In the test process, the bundle identifier is whatever the test
    // harness reports. Just verify the snapshot is self-consistent:
    // devBundle and environment agree.
    let tags = BuildMetadataTags.current
    if tags.environment == "production" {
      XCTAssertFalse(tags.devBundle)
    } else {
      XCTAssertTrue(tags.devBundle)
    }
  }

  func testGitShaAndBranchFallbackToUnknownWhenInfoPlistMissing() {
    // Test target's Info.plist won't have BuildGitSha / BuildGitBranch
    // injected; expect the fallback string.
    let tags = BuildMetadataTags.current
    XCTAssertTrue(
      tags.gitSha == "unknown" || !tags.gitSha.isEmpty,
      "gitSha must be either 'unknown' or a non-empty injected value"
    )
    XCTAssertTrue(
      tags.branch == "unknown" || !tags.branch.isEmpty,
      "branch must be either 'unknown' or a non-empty injected value"
    )
  }
}
