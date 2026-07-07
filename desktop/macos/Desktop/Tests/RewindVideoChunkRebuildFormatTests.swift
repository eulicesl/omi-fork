import XCTest

@testable import Omi_Computer

/// BUG-013 verification (audit fff46934). DRAFT — authored in a Linux container and
/// NOT compiled; verify the build on macOS before trusting a red/green result.
///
/// Designed to FAIL against the current, unfixed code — a failure IS the confirmation.
///
/// Root cause: `VideoChunkEncoder.generateChunkPath` writes `<day>/chunk_HHmmss.mp4`,
/// but `RewindStorage.getAllVideoChunks` enumerates and keeps only `pathExtension == "hevc"`.
/// The "Rebuild Index" recovery therefore finds zero chunks and re-indexes nothing.
/// (A second, independent mismatch lives in `RewindIndexer.parseChunkTimestamp`, which
/// expects the old 26-char `chunk_YYYYMMDD_HHMMSS.hevc` name — testable only after a
/// private->internal seam; see XCTEST-PLAN.md.)
final class RewindVideoChunkRebuildFormatTests: XCTestCase {

  private var testUserId: String!
  private var userDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    testUserId = "rebuild-format-test-\(UUID().uuidString)"
    RewindDatabase.currentUserId = testUserId
    try await RewindDatabase.shared.initialize()
    try await RewindStorage.shared.initialize()

    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    userDir = appSupport
      .appendingPathComponent("Omi", isDirectory: true)
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(testUserId, isDirectory: true)
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    if let userDir { try? FileManager.default.removeItem(at: userDir) }
    RewindDatabase.currentUserId = nil
    try await super.tearDown()
  }

  /// EXPECTED TO FAIL on current code: a real `.mp4` chunk (exactly the encoder's output
  /// format) is skipped by the `.hevc`-only enumerator, so rebuild sees zero chunks.
  func testGetAllVideoChunksFindsRealMp4ChunkFiles() async throws {
    guard let videosDir = await RewindStorage.shared.getVideosDirectory() else {
      return XCTFail("precondition: videos directory not available after initialize()")
    }

    // Name/layout exactly as VideoChunkEncoder.generateChunkPath produces: "<yyyy-MM-dd>/chunk_HHmmss.mp4".
    let chunkRel = "2026-07-07/chunk_143052.mp4"
    let chunkURL = videosDir.appendingPathComponent(chunkRel)
    try FileManager.default.createDirectory(
      at: chunkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("fake-mp4-bytes".utf8).write(to: chunkURL)
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: chunkURL.path), "precondition: mp4 chunk written")

    let chunks = try await RewindStorage.shared.getAllVideoChunks()

    XCTAssertFalse(
      chunks.isEmpty,
      "BUG-013: getAllVideoChunks must discover real .mp4 chunk files — it filters for .hevc, which the encoder never writes, so rebuild-index is a no-op")
  }
}
