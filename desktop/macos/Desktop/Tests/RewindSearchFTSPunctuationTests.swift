import XCTest

@testable import Omi_Computer

/// BUG-015 verification (audit fff46934). DRAFT — authored in a Linux container and
/// NOT compiled; verify the build on macOS before trusting a red/green result.
///
/// Designed to FAIL against the current, unfixed code — a failure IS the confirmation.
///
/// Root cause: `RewindDatabase.expandSearchQuery` appends `*` to raw user tokens and
/// binds the result into `screenshots_fts MATCH ?`. Parameter binding stops SQL
/// injection but NOT FTS5 query-syntax errors: tokens containing `'`, `-`, `.`, `:`
/// (e.g. `don't`, `e-mail`, `3:30pm`, `api.omi.me`) make `search` throw SQLITE_ERROR.
/// `ActionItemStorage.searchFTS` sanitizes; the screenshots search never got it.
final class RewindSearchFTSPunctuationTests: XCTestCase {

  private var testUserId: String!
  private var userDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    testUserId = "fts-punctuation-test-\(UUID().uuidString)"
    RewindDatabase.currentUserId = testUserId
    try await RewindDatabase.shared.initialize()

    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    userDir = appSupport
      .appendingPathComponent("Omi", isDirectory: true)
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(testUserId, isDirectory: true)

    // Seed one indexable row so screenshots_fts has content (the throw does not depend
    // on matches — a malformed MATCH expression fails at parse time regardless).
    _ = try await RewindDatabase.shared.insertScreenshot(
      Screenshot(
        timestamp: Date(), appName: "FTSTest",
        ocrText: "please don't email me at 3:30pm about e-mail or api.omi.me",
        isIndexed: true))
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    if let userDir { try? FileManager.default.removeItem(at: userDir) }
    RewindDatabase.currentUserId = nil
    try await super.tearDown()
  }

  /// `search` is actor-isolated, so it must be `await`ed — which cannot go inside
  /// `XCTAssertNoThrow`'s autoclosure. Assert non-throwing with an explicit do/catch.
  private func assertSearchDoesNotThrow(_ query: String) async {
    do {
      _ = try await RewindDatabase.shared.search(query: query)
    } catch {
      XCTFail(
        "BUG-015: search must not throw on query \"\(query)\" — expandSearchQuery emits an unescaped FTS5 MATCH expression (\(error))")
    }
  }

  /// EXPECTED TO FAIL on current code: `don't` -> `don't*` is invalid FTS5 syntax -> throws.
  func testSearchWithApostropheDoesNotThrow() async {
    await assertSearchDoesNotThrow("don't")
  }

  /// EXPECTED TO FAIL on current code for each punctuated token.
  func testSearchWithHyphenColonAndDotDoesNotThrow() async {
    for query in ["e-mail", "3:30pm", "api.omi.me"] {
      await assertSearchDoesNotThrow(query)
    }
  }
}
