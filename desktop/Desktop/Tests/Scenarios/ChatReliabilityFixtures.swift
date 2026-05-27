import Foundation
import GRDB

@testable import Omi_Computer

// MARK: - ChatReliabilityFixtures (PR 7 scaffolding)
//
// In-process fixture helpers for the scenario suite. Covers data that
// CANNOT reach chat via the Firestore -> API -> local SQLite -> sync
// chain — primarily screenshots, which are local-first (captured by
// Rewind into local SQLite, then pushed UP to the VM by
// AgentSyncService). There is no Firestore -> local pull path for
// screenshots, so the shell-script seeder can't help here.
//
// Scope:
//   - Seed local Desktop SQLite rows that the runner needs.
//   - Tag each row with a fixture marker so teardown finds them.
//   - Idempotent: teardown runs before reseed.
//
// Out of scope (must be solved before scenarios actually pass):
//   - The test process is separate from the running named bundle. Its
//     RewindDatabase.shared opens a SEPARATE omi.db at the test process's
//     container path. Seeding here makes the row visible to the test
//     process's in-process ChatProvider, but NOT to the named bundle.
//   - Once a row is in the test process's local SQLite, AgentSyncService
//     can push it to the VM only if the test process has a VM auth
//     token. That requires the auth-bootstrap step that's still pending
//     (Phase 2). Until then, scenarios skip with the appropriate reason.
//
// The fixture marker is encoded into the screenshot's `appName` field
// (`ChatReliabilityFixture`) — `appName` is already indexed by Rewind
// so teardown queries stay fast.
enum ChatReliabilityFixtures {

  /// Sentinel `appName` value for every fixture row this helper writes.
  /// Used by teardown to identify and remove fixture rows without
  /// affecting real captured screenshots.
  static let fixtureAppName = "ChatReliabilityFixture"

  /// The OCR text seeded into the semantic-search fixture row. Scenario
  /// #4 (semantic search) queries chat for content that matches a
  /// substring of this text and asserts the result includes it.
  static let semanticSearchOCRText = """
    fixture: scenario-test-search-document about machine learning \
    research notes — pinned for chat-reliability scenario #4
    """

  /// Seed the semantic-search screenshot fixture into local SQLite.
  ///
  /// Idempotent: removes any prior fixture rows first.
  ///
  /// - Note: This writes to the **test process's** RewindDatabase
  ///   (separate from any running named bundle's DB). The runner is
  ///   responsible for pushing the row to the VM via AgentSyncService
  ///   before running piMono scenarios — see ChatScenarioRunner.
  @discardableResult
  static func seedScreenshotFixture() async throws -> Int64 {
    try await removeFixtureRows()

    let screenshot = Screenshot(
      timestamp: Date(),
      appName: fixtureAppName,
      windowTitle: "chat-reliability-fixture-window",
      imagePath: "",  // empty string per RewindDatabase.insertScreenshot's NOT NULL coalescing
      ocrText: semanticSearchOCRText,
      isIndexed: true
    )

    let inserted = try await RewindDatabase.shared.insertScreenshot(screenshot)
    guard let rowID = inserted.id else {
      throw ChatReliabilityFixturesError.insertFailed("RewindDatabase returned a row without an id")
    }
    return rowID
  }

  /// Remove every fixture row from local SQLite. Safe to call
  /// repeatedly — no-ops when nothing matches.
  ///
  /// Uses the existing `getScreenshots(from:to:)` + `deleteScreenshot(id:)`
  /// public API rather than adding a test-only escape hatch on the
  /// production `RewindDatabase` actor. Slightly slower (per-row
  /// delete) but keeps production surface clean. The fixture row
  /// count stays in single digits, so the cost is irrelevant in
  /// practice.
  static func removeFixtureRows() async throws {
    let epoch = Date(timeIntervalSince1970: 0)
    let farFuture = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)  // +1y from now
    let allRecent = try await RewindDatabase.shared.getScreenshots(
      from: epoch, to: farFuture, limit: 1000
    )
    for screenshot in allRecent where screenshot.appName == fixtureAppName {
      guard let id = screenshot.id else { continue }
      _ = try await RewindDatabase.shared.deleteScreenshot(id: id)
    }
  }
}

// MARK: - Errors

enum ChatReliabilityFixturesError: Error, Equatable {
  /// The insert returned without surfacing an id — should be impossible
  /// given GRDB's autoIncrementedPrimaryKey, but surfaced rather than
  /// force-unwrapped so the runner can log it cleanly.
  case insertFailed(String)
}
