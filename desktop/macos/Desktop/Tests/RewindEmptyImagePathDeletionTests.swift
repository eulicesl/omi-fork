import XCTest

@testable import Omi_Computer

/// BUG-001 verification (audit fff46934). DRAFT — authored in a Linux container and
/// NOT compiled; verify the build on macOS before trusting a red/green result.
///
/// Designed to FAIL against the current, unfixed code — a failure IS the confirmation.
///
/// Root cause: video-era screenshots are stored with `imagePath == ""` (the NOT-NULL
/// sentinel, `RewindDatabase.insertScreenshot`). `deleteScreenshotsOlderThan` selects
/// `imagePath IS NOT NULL` (which matches `""`), and `RewindStorage.deleteScreenshot`
/// has no empty-path guard, so `screenshotsDirectory.appendingPathComponent("")`
/// resolves to the Screenshots directory itself and `removeItem` recursively wipes it.
///
/// This mirrors the setup of the existing `RewindRetentionCleanupTests`, which exercises
/// the same `runCleanup()` path but never checks the Screenshots directory — so it does
/// not catch this.
final class RewindEmptyImagePathDeletionTests: XCTestCase {

  private var testUserId: String!
  private var userDir: URL!
  private var savedRetentionDays: Int = 7

  override func setUp() async throws {
    try await super.setUp()
    testUserId = "empty-imagepath-test-\(UUID().uuidString)"
    RewindDatabase.currentUserId = testUserId
    try await RewindDatabase.shared.initialize()
    try await RewindStorage.shared.initialize()

    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    userDir = appSupport
      .appendingPathComponent("Omi", isDirectory: true)
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(testUserId, isDirectory: true)

    savedRetentionDays = RewindSettings.shared.retentionDays
    RewindSettings.shared.retentionDays = 7
  }

  override func tearDown() async throws {
    RewindSettings.shared.retentionDays = savedRetentionDays
    if let userDir { try? FileManager.default.removeItem(at: userDir) }
    RewindDatabase.currentUserId = nil
    try await super.tearDown()
  }

  /// Pure-Foundation proof of the blast-radius mechanism. This always passes and
  /// documents WHY the empty-path delete is catastrophic. No production code involved.
  func testEmptyImagePathComponentResolvesToParentDirectory() throws {
    let dir = userDir.appendingPathComponent("Screenshots", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let resolved = dir.appendingPathComponent("")
    XCTAssertEqual(
      resolved.path, dir.path,
      "appendingPathComponent(\"\") resolves to the directory itself — deleting it wipes the dir")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: resolved.path),
      "fileExists is true for the empty-component path, so deleteScreenshot(\"\") proceeds to removeItem")
  }

  /// End-to-end: an aged video-era row (imagePath "") plus a fresh in-retention JPEG.
  /// Cleanup must delete only expired content and must NOT wipe the Screenshots dir.
  /// EXPECTED TO FAIL on current code (the JPEG is destroyed with the whole directory).
  func testCleanupWithEmptyImagePathDoesNotWipeScreenshotsDirectory() async throws {
    let fm = FileManager.default

    // A fresh, in-retention screenshot backed by a real JPEG on disk.
    let recentJpegRel = try await RewindStorage.shared.saveScreenshot(
      jpegData: Data("fake-jpeg-bytes".utf8), timestamp: Date())
    guard let keptURL = await RewindStorage.shared.getScreenshotURL(relativePath: recentJpegRel) else {
      return XCTFail("precondition: could not resolve the saved JPEG URL")
    }
    XCTAssertTrue(fm.fileExists(atPath: keptURL.path), "precondition: recent JPEG written")

    _ = try await RewindDatabase.shared.insertScreenshot(
      Screenshot(
        timestamp: Date(), appName: "EmptyPathTest", imagePath: recentJpegRel, isIndexed: true))

    // An aged video-era row: imagePath nil -> coalesced to "" by insertScreenshot.
    let oldDate = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
    _ = try await RewindDatabase.shared.insertScreenshot(
      Screenshot(
        timestamp: oldDate, appName: "EmptyPathTest", videoChunkPath: "2000-01-01/chunk_old.mp4",
        frameOffset: 0, isIndexed: true))

    // Real production cleanup path.
    await RewindIndexer.shared.runCleanup()

    XCTAssertTrue(
      fm.fileExists(atPath: keptURL.path),
      "BUG-001: an in-retention JPEG must survive cleanup — it is wiped because the empty imagePath of the aged video row deletes the entire Screenshots directory")
  }
}
