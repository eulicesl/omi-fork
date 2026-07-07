# XCTest Verification Plan

> Drafted for the **automatable verification track** only. These tests target bugs that can be confirmed **headlessly on macOS** (no GUI, no BLE/mic hardware, no visual proof). **None has been compiled or run** — this was authored in a Linux container with no Swift toolchain. Every drafted test is designed to **fail (red) against the current, unfixed code if the audited bug is real**; a failure when run on macOS is the confirmation signal. Do not mark any bug Confirmed until the test actually runs on macOS and produces that evidence.

## Metadata

- Repository: `eulicesl/omi-fork`
- Branch: `claude/omi-macos-audit-skjwgd`
- Source audit commit: `fff46934`
- Verification queue commit: `2b3cddb0`
- Date: 2026-07-07
- Environment limitation: Linux x86_64, no `swift`/`xcrun`/Xcode, no reachable macOS environment. Tests are **drafts** verified against source signatures only, **not compiled**. The one compile-risk mitigation used: each drafted file mirrors an existing, passing test in `Desktop/Tests/` (notably `RewindRetentionCleanupTests.swift`) for conventions, module name (`@testable import Omi_Computer`), and storage-isolation setup.

## Summary

- **Bugs targeted:** 8 — BUG-001, BUG-013, BUG-014, BUG-015, BUG-029, and the injectable portions of BUG-002, BUG-006, BUG-016.
- **Directly testable without production changes (5):** BUG-001, BUG-013, BUG-015, BUG-002, BUG-014. Test files drafted and created under `Desktop/Tests/` for four of these (001, 013, 015, 002); BUG-014 is drafted in this plan only (GRDB-fixture + recovery-interaction risk — see its entry).
- **Requiring a small test seam (3):** BUG-006 (inject the token refresher + a sign-out generation counter), BUG-016 (inject the chat message fetch), BUG-029 (expose `handleSegmentsUpdate` + inject the note trigger). Full test code is in this plan; **no files were created** for these because they reference APIs that do not exist yet and would break the build.
- **Not suitable for XCTest (from the broader queue, out of scope here):** BUG-004 (mic indicator), BUG-005 (TSan), BUG-007 (packet capture), BUG-009 (stable-channel window), BUG-010 (BLE device), BUG-011 (GUI), BUG-030 (key events), BUG-089 (quit lifecycle), BUG-090 (window reopen crash).

## Proposed Test Commands (run on macOS)

Whole verification batch:
```bash
cd desktop/macos
xcrun swift test --package-path Desktop 2>&1 | tee docs/verification/evidence/xctest-run.txt
```

Single bug (SwiftPM filters by test-class or `Class/method`):
```bash
cd desktop/macos
xcrun swift test --package-path Desktop --filter RewindEmptyImagePathDeletionTests
xcrun swift test --package-path Desktop --filter RewindSearchFTSPunctuationTests
xcrun swift test --package-path Desktop --filter RewindVideoChunkRebuildFormatTests
xcrun swift test --package-path Desktop --filter GoalStorageUserSwitchIsolationTests
```
(These four `--filter` names match the drafted files. `swift test` builds the full `Omi Computer` target; the CWebP system library needs `brew install webp`.)

> **Interpreting results:** these are *red-on-purpose* verification tests. A **failure** on current code = the bug reproduced (→ candidate for Confirmed, with the run log as evidence). A **pass** = the bug did **not** reproduce as predicted (→ mark Not Reproducible / Inconclusive and investigate). Capture the full `xcrun swift test` output into `docs/verification/evidence/BUG-XXX/` per bug.

---

## Per-Bug Test Plan

### BUG-001: Retention/empty-imagePath delete wipes the Screenshots directory
- **Audit classification:** High-Confidence Code Inspection Bug · Critical (data loss)
- **Testability:** **Direct XCTest** (no production change). Mirrors the existing `RewindRetentionCleanupTests` setup exactly.
- **Existing files involved:** `Sources/Rewind/Core/RewindDatabase.swift` (`deleteScreenshotsOlderThan:3034`, query `imagePath IS NOT NULL:3043`), `Sources/Rewind/Core/RewindStorage.swift` (`deleteScreenshot:527`, `deleteScreenshots:530`), `Sources/Rewind/Services/RewindIndexer.swift` (`runCleanup:484`).
- **Proposed test file:** `Desktop/Tests/RewindEmptyImagePathDeletionTests.swift` *(created)*.
- **Proposed test names:** `testEmptyImagePathComponentResolvesToParentDirectory` (pure-Foundation mechanism, always runnable), `testCleanupWithEmptyImagePathDoesNotWipeScreenshotsDirectory` (end-to-end).
- **Setup:** isolate to a throwaway `RewindDatabase.currentUserId`; `RewindDatabase.shared.initialize()` + `RewindStorage.shared.initialize()`; write a real JPEG into `Screenshots/` referenced by a **recent, in-retention** row with a valid `imagePath`; insert an **old** row with `imagePath: ""` (the video-era sentinel, exactly what `insertScreenshot` coalesces nil → "").
- **Test steps:** run `RewindIndexer.shared.runCleanup()` (the real production path), then assert the in-retention JPEG still exists and the `Screenshots/` dir still exists.
- **Expected failing assertion on current code:** `XCTAssertTrue(fm.fileExists(atPath: keptJpegPath))` — fails because `deleteScreenshotsOlderThan` returns `""` for the old row and `deleteScreenshot("")` → `screenshotsDirectory.appendingPathComponent("")` → the Screenshots dir → recursive `removeItem`. The mechanism test asserts `appendingPathComponent("").path == screenshotsDir.path`, which is the root cause and always passes (documents the hazard).
- **Evidence if run on macOS:** `xcrun swift test` output showing the end-to-end test red; the mechanism test green documenting the path collision.
- **Committable before fix:** yes (red = confirmation; it is on the audit branch, not main). Turns green when the empty-path guard lands.
- **Still needs manual visual proof:** no.

### BUG-013: Rewind chunk rebuild is a no-op (`.hevc` filter vs `.mp4` writer)
- **Audit classification:** High-Confidence Code Inspection Bug · High
- **Testability:** **Direct XCTest** for the primary no-op (`getAllVideoChunks`); the `parseChunkTimestamp` half needs a small seam (see note).
- **Existing files involved:** `Sources/Rewind/Core/RewindStorage.swift` (`getAllVideoChunks:683`, filter `pathExtension == "hevc":698`, `getVideosDirectory:68`), `Sources/Rewind/Core/VideoChunkEncoder.swift` (`generateChunkPath:459` → `chunk_HHmmss.mp4`), `Sources/Rewind/Services/RewindIndexer.swift` (`parseChunkTimestamp:729`).
- **Proposed test file:** `Desktop/Tests/RewindVideoChunkRebuildFormatTests.swift` *(created)*.
- **Proposed test name:** `testGetAllVideoChunksFindsRealMp4ChunkFiles`.
- **Setup:** initialize storage to a throwaway user; via `getVideosDirectory()`, write a real file named exactly as the encoder produces — `2026-07-07/chunk_143052.mp4`.
- **Test steps:** call `RewindStorage.shared.getAllVideoChunks()`; assert it returns the chunk.
- **Expected failing assertion on current code:** `XCTAssertFalse(chunks.isEmpty)` — fails because the enumerator `guard fileURL.pathExtension == "hevc"` skips every `.mp4`.
- **Small-seam note (parseChunkTimestamp):** it is `private`. To unit-test it directly, change `private func parseChunkTimestamp` → `func parseChunkTimestamp` (internal) in `RewindIndexer.swift` (single-word seam, no behavior change) and assert `parseChunkTimestamp("chunk_143052.mp4") == nil` and `parseChunkTimestamp("2026-07-07/chunk_143052.mp4")`-derived names fail the 26-char `.hevc` check. Documented, **not applied** (no production change in this phase).
- **Evidence if run on macOS:** test output showing `getAllVideoChunks` returned empty for a real `.mp4`.
- **Committable before fix:** yes. **Manual visual proof:** no.

### BUG-014: Fallback corruption recovery produces a DB that fails migrations every launch
- **Audit classification:** High-Confidence Code Inspection Bug · High
- **Testability:** **Direct XCTest with a fixture** — but **drafted in this plan only** (not committed as a file) because it (a) writes a raw GRDB fixture at the per-user `omi.db` path and (b) depends on `RewindDatabase.initialize()` **not** silently re-recovering on the migration throw. Those two runtime interactions carry enough uncertainty that I did not want to risk a build/ђsuite break with an unverified file. Create it on macOS after confirming behavior.
- **Existing files involved:** `Sources/Rewind/Core/RewindDatabase.swift` (`attemptDirectTableRecovery:818`, `migrate:963` registering `createScreenshots` via `db.create(table:)` with no `ifNotExists`, `initialize`).
- **Proposed test file:** `Desktop/Tests/RewindCorruptRecoveryMigrationTests.swift` *(draft below; create on macOS)*.
- **Proposed test name:** `testDatabaseWithScreenshotsTableButNoMigrationsFailsToInitialize`.
- **Setup:** compute the per-user dir `…/Application Support/Omi/users/{uid}/`; create it; write an `omi.db` there containing only a `screenshots` table and **no** `grdb_migrations` table (author it with a plain GRDB `DatabaseQueue`); set `RewindDatabase.currentUserId = uid`.
- **Test steps:** call `try await RewindDatabase.shared.initialize()`; assert it throws (migration collision: `table screenshots already exists`), and a second `initialize()` also throws (reproduces the "bricked every launch" property).
- **Expected failing assertion on current code:** depends on how you frame it — assert that init **succeeds** (`XCTAssertNoThrow`) to make it red today, OR assert it throws today and mark the *fix* as flipping it. Recommended: `await XCTAssertThrowsError(try initialize())` documenting current behavior, plus a comment that the fix must make this a clean recovery. **Runtime caveat to confirm first:** if `initialize()` catches the migration error and re-runs recovery, the throw won't surface — verify the actual path on macOS before finalizing the assertion.
- **Draft code:**
```swift
import XCTest
import GRDB
@testable import Omi_Computer

/// BUG-014 (draft — verify on macOS before relying): a recovered DB that carries a
/// `screenshots` table but no `grdb_migrations` re-runs migration 1 (`createScreenshots`,
/// no `ifNotExists`) → "table already exists" on every launch.
final class RewindCorruptRecoveryMigrationTests: XCTestCase {
  private var testUserId: String!
  private var userDir: URL!

  override func setUp() async throws {
    try await super.setUp()
    testUserId = "corrupt-recovery-test-\(UUID().uuidString)"
    let appSupport = FileManager.default
      .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    userDir = appSupport
      .appendingPathComponent("Omi", isDirectory: true)
      .appendingPathComponent("users", isDirectory: true)
      .appendingPathComponent(testUserId, isDirectory: true)
    try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)

    // Fixture: a DB with the screenshots table but NO grdb_migrations (mimics attemptDirectTableRecovery output).
    let dbPath = userDir.appendingPathComponent("omi.db").path
    let queue = try DatabaseQueue(path: dbPath)
    try queue.write { db in
      try db.execute(sql: "CREATE TABLE screenshots (id INTEGER PRIMARY KEY, timestamp DOUBLE, appName TEXT, imagePath TEXT NOT NULL DEFAULT '')")
    }
    // Ensure the queue is released so RewindDatabase can reopen the same file.
  }

  override func tearDown() async throws {
    await RewindDatabase.shared.close()
    RewindDatabase.currentUserId = nil
    if let userDir { try? FileManager.default.removeItem(at: userDir) }
    try await super.tearDown()
  }

  func testDatabaseWithScreenshotsTableButNoMigrationsFailsToInitialize() async throws {
    RewindDatabase.currentUserId = testUserId
    // Current (buggy) behavior predicted: migrator re-runs createScreenshots → throws.
    // Frame the assertion to be RED today; flip when the fix lands.
    do {
      try await RewindDatabase.shared.initialize()
      // If we reach here, init did NOT throw — either the bug is absent or recovery masked it.
      XCTFail("BUG-014: expected initialize() to fail on a migration-less recovered DB; it succeeded (bug absent or recovery masked the throw — investigate)")
    } catch {
      // Reproduced: document the error as evidence. This is the confirmation.
      throw XCTSkip("BUG-014 reproduced: initialize() threw as predicted (\(error)). Convert to a passing assertion once the fix makes recovery clean.")
    }
  }
}
```
- **Committable before fix:** only after the runtime path is confirmed on macOS (hence draft-only here). **Manual visual proof:** no.

### BUG-015: Rewind FTS search throws on common punctuation
- **Audit classification:** High-Confidence Code Inspection Bug · High (Medium-High)
- **Testability:** **Direct XCTest** — cleanest of the set; `search(query:)` is internal and `throws`.
- **Existing files involved:** `Sources/Rewind/Core/RewindDatabase.swift` (`expandSearchQuery:2879` interpolates raw `word*`, `search:2966` binds it into `screenshots_fts MATCH ?`).
- **Proposed test file:** `Desktop/Tests/RewindSearchFTSPunctuationTests.swift` *(created)*.
- **Proposed test names:** `testSearchWithApostropheDoesNotThrow`, `testSearchWithHyphenColonAndDotDoesNotThrow`.
- **Setup:** initialize DB to a throwaway user; insert one screenshot with `ocrText: "please don't email me at 3:30pm about e-mail or api.omi.me"` (FTS triggers populate `screenshots_fts` on insert).
- **Test steps:** call `try RewindDatabase.shared.search(query: "don't")` (and `"e-mail"`, `"3:30pm"`, `"api.omi.me"`); assert none throw.
- **Expected failing assertion on current code:** `XCTAssertNoThrow(try search(query: "don't"))` — fails; `expandSearchQuery` yields `don't*`, which FTS5 parses as a MATCH expression → `SQLITE_ERROR`.
- **Evidence if run on macOS:** test output showing the thrown `DatabaseError`/`SQLITE_ERROR`.
- **Committable before fix:** yes. **Manual visual proof:** no (the "stale results shown" UI symptom is separate; this test isolates the throw).

### BUG-029: Live notes stop generating after ~500 words
- **Audit classification:** High-Confidence Code Inspection Bug · High
- **Testability:** **XCTest with a small seam.** `handleSegmentsUpdate` is `private`, `generateNote` calls the real `geminiClient` (network), and the counters are `private`.
- **Existing files involved:** `Sources/LiveNotes/LiveNotesMonitor.swift` (`handleSegmentsUpdate:213`, `wordBuffer/maxWordBufferSize(500)/lastProcessedSegmentOrder/wordThreshold(50)`, `generateNote:256`, `wordBufferCount:354`).
- **Smallest safe seam (documented, not applied):**
  1. Change `private func handleSegmentsUpdate` → `func handleSegmentsUpdate` (internal) so a test can drive it.
  2. Add an injectable note-trigger so the test observes generation attempts without Gemini, e.g. `var onNoteTriggeredForTesting: (() -> Void)?` invoked at the top of `generateNote` (guard it behind `#if DEBUG` or leave it nil in prod — no behavior change). Alternatively expose a testable `struct` with the pure counter logic and unit-test that.
- **Proposed test file (after seam):** `Desktop/Tests/LiveNotesWordBudgetTests.swift`.
- **Proposed test name:** `testNotesStillGenerateAfterFiveHundredWords`.
- **Test steps:** enable AI + a session; feed synthetic `SpeakerSegment`s in 50-word increments up to >600 words (monotonically increasing `end` timestamps so the cursor advances); count `onNoteTriggeredForTesting` calls; assert at least one note fires after the 500-word mark.
- **Expected failing assertion on current code:** note-trigger count stops incrementing after `wordBuffer` saturates at 500 (`wordsSinceLastNote = 500 - 500 = 0 < 50`).
- **Draft code (requires the seam above):**
```swift
import XCTest
@testable import Omi_Computer

/// BUG-029 (requires the documented seam): once wordBuffer saturates at maxWordBufferSize (500),
/// lastProcessedSegmentOrder pins to 500 and wordsSinceLastNote can never reach the 50 threshold.
@MainActor
final class LiveNotesWordBudgetTests: XCTestCase {
  func testNotesStillGenerateAfterFiveHundredWords() async throws {
    let monitor = LiveNotesMonitor()   // confirm the initializer / how to enable AI + session
    var noteTriggers = 0
    monitor.onNoteTriggeredForTesting = { noteTriggers += 1 }   // seam
    // monitor.startForTesting(sessionId: "t", aiEnabled: true)  // confirm the enabling API

    var end = 0.0
    for batch in 0..<14 {                     // 14 * 50 = 700 words
      let words = (0..<50).map { "word\(batch)_\($0)" }.joined(separator: " ")
      end += 5
      monitor.handleSegmentsUpdate([SpeakerSegment(/* text: words, end: end, … confirm fields */)])
    }
    XCTAssertGreaterThan(noteTriggers, 10,
      "BUG-029: notes must keep generating past 500 words; they stop once the buffer saturates")
  }
}
```
- **Committable before fix:** only after the seam is added (which is itself a small production change → belongs in the fix/seam PR, not this phase). **Manual visual proof:** no (behavioral; the AUTO test replaces it).

### BUG-002 (injectable portion): storage actors reuse the prior user's DB pool
- **Audit classification:** High-Confidence Code Inspection Bug · Critical (privacy)
- **Testability:** **Direct XCTest** — `GoalStorage` is an actor exposing `insertLocalGoal`, `getLocalGoals`, `invalidateCache`; the bug is that the sign-out path never calls `invalidateCache`, and this test reproduces the underlying stale-pool leak by omitting that call across a user switch.
- **Existing files involved:** `Sources/Rewind/Core/GoalStorage.swift` (`ensureInitialized:40` caches `_dbQueue`, `invalidateCache:34` — never called from `AuthService.swift:2090-2095`), `Sources/Rewind/Core/RewindDatabase.swift` (`configure/close`, per-user pool).
- **Proposed test file:** `Desktop/Tests/GoalStorageUserSwitchIsolationTests.swift` *(created)*.
- **Proposed test name:** `testGoalStorageDoesNotServePreviousUsersGoalsAfterSwitch`.
- **Setup:** configure DB to user A, insert a goal via `GoalStorage.shared.insertLocalGoal` (this caches A's pool). Switch: `RewindDatabase.shared.close()` → `RewindDatabase.currentUserId = B` → `initialize()`. **Do not** call `GoalStorage.shared.invalidateCache()` (models the missing sign-out call).
- **Test steps:** `let goalsForB = try await GoalStorage.shared.getLocalGoals()`; assert it is empty.
- **Expected failing assertion on current code:** `XCTAssertTrue(goalsForB.isEmpty)` — fails if the cached A pool stays open and returns A's goal. (Documented alternative outcome: if `close()` tore down the shared pool object GoalStorage cached, `getLocalGoals()` may **throw** instead — also a non-green signal; the test notes both.)
- **Committable before fix:** yes (turns green once `invalidateCache()` is wired into sign-out and the test additionally calls it — see the file's comment on how the fix flips it).
- **Manual visual proof:** no; the two-account manual repro in the RUNBOOK is the complementary end-to-end check.

### BUG-006 (injectable portion): sign-out re-persists an in-flight token refresh
- **Audit classification:** High-Confidence Code Inspection Bug · Critical (security)
- **Testability:** **XCTest with a small seam.** `AuthService.refreshIdToken` uses `URLSession.shared` directly (no injection) and there is no sign-out generation counter, so the race is not reproducible without a seam.
- **Existing files involved:** `Sources/AuthService.swift` (`refreshIdToken:1883`, `saveTokens:1659`, `signOut:2049`, `getIdToken:1946`).
- **Smallest safe seam (documented, not applied):**
  1. A `sessionGeneration` counter bumped in `signOut()`, captured by `refreshIdToken` before its network await and re-checked before `saveTokens` (this is *also the fix*, so the test and fix ship together).
  2. An injectable token fetch — e.g. `var tokenExchangeForTesting: ((_ refreshToken: String) async throws -> (idToken: String, refreshToken: String, expiresIn: Int))?` — so the test can hold the refresh open while it calls `signOut()`.
- **Proposed test file (after seam):** `Desktop/Tests/AuthSignOutTokenRaceTests.swift`.
- **Proposed test name:** `testRefreshResumingAfterSignOutDoesNotRepersistTokens`.
- **Test steps:** seed a signed-in state; start `refreshIdToken()` with the injected exchange blocked on a continuation; call `signOut()`; release the continuation; assert Keychain/UserDefaults hold no tokens and `auth_userId` is absent.
- **Expected failing assertion on current code (with seam):** tokens/`auth_userId` present after signout → assertion fails.
- **Committable before fix:** the seam is the fix, so this test belongs in the BUG-006 fix PR. **Manual visual proof:** no.

### BUG-016 (injectable portion): rapid session switch shows the wrong session's messages
- **Audit classification:** High-Confidence Code Inspection Bug · High
- **Testability:** **XCTest with a small seam.** `ChatProvider.selectSession` calls `APIClient.shared.getMessages` (singleton, network); no generation guard.
- **Existing files involved:** `Sources/Providers/ChatProvider.swift` (`selectSession:1717`, `messages`, `messagesPaginationOffset`), `Sources/APIClient.swift` (`getMessages`).
- **Smallest safe seam (documented, not applied):** inject the message fetch — e.g. a `var messageFetcherForTesting: ((_ sessionId: String) async throws -> [ChatMessage])?` on `ChatProvider`, used by `selectSession` when set — so the test can make session A's fetch resolve slowly and B's quickly.
- **Proposed test file (after seam):** `Desktop/Tests/ChatProviderSessionSwitchRaceTests.swift`.
- **Proposed test name:** `testLateResponseFromPreviousSessionDoesNotOverwriteCurrent`.
- **Test steps:** `selectSession(A)` with a slow fetch; immediately `selectSession(B)` with a fast fetch; await both; assert `currentSession?.id == B` **and** `messages` are B's.
- **Expected failing assertion on current code (with seam):** A's late response overwrites `messages` → assertion fails.
- **Committable before fix:** the seam + `sessionLoadGeneration` guard is the fix (also covers BUG-017/018/051), so this test ships with that PR. **Manual visual proof:** no (the RUNBOOK manual switch is complementary).

---

## Proposed Test Files (created in `Desktop/Tests/`)

Four files were created for the directly-testable bugs (001, 013, 015, 002). Each carries a header: *draft authored on Linux, not compiled — verify the build on macOS before relying; designed to fail red on current code as the confirmation signal.* Their full source is in the repo; the drafts for BUG-014 (fixture-risk) and the three seam bugs (006/016/029) live in this plan above and were intentionally **not** committed as files (they would not compile against current APIs).

**Build-safety caveat:** because nothing was compiled here, run `xcrun swift test --package-path Desktop` once on macOS and fix any signature drift **before** trusting a red/green result. If a drafted file fails to *compile* (as opposed to fails to *assert*), that is a drafting error, not a bug reproduction — correct the symbol and re-run.

## Codemagic / self-hosted Mac runner

These headless XCTests are the subset runnable in CI without a human:
- **Machine type:** macOS (Codemagic `mac_mini_m2` / `mac_pro`, or a self-hosted Apple-silicon runner). The desktop release already builds on a Mac mini M2 (see `desktop/macos/AGENTS.md`).
- **Xcode version:** match the release pipeline's Xcode (whatever `codemagic.yaml`'s `omi-desktop-swift-release` uses); Swift tools 5.9+, macOS 14 SDK (from `Package.swift` `platforms: .macOS("14.0")`).
- **Pre-step:** `brew install webp` (CWebP system library dependency).
- **Command:**
  ```bash
  cd desktop/macos
  xcrun swift test --package-path Desktop --filter RewindEmptyImagePathDeletionTests \
                                          --filter RewindSearchFTSPunctuationTests \
                                          --filter RewindVideoChunkRebuildFormatTests \
                                          --filter GoalStorageUserSwitchIsolationTests \
    2>&1 | tee docs/verification/evidence/xctest-run.txt
  ```
  (Or run the whole target and grep for the four classes.)
- **Expected artifacts:** the `xcrun swift test` log (JUnit if you add `--xunit-output`), captured as the verification evidence. Because these are red-on-purpose, configure the CI step to **not fail the pipeline** on their failure (e.g. `|| true` with the log archived) — the log *is* the deliverable, not a green build.
- **Where to upload:** `desktop/macos/docs/verification/evidence/BUG-XXX/` (and the combined `xctest-run.txt`). Attach the log to the filled `REPORT-TEMPLATE.md`.
- **Note:** a headless SwiftPM test host has no GUI/TCC context. The DB/file tests run fine (they use Application Support paths); if any test unexpectedly needs entitlements or a signed host, fall back to running it from the app's test scheme on a logged-in Mac.

## Final Recommendation

- **First XCTest verification batch (run now on macOS, no seams, no production changes):** BUG-015 (FTS throw — cleanest), BUG-001 (data-loss — highest impact), BUG-013 (rebuild no-op). These three are the fastest, lowest-risk confirmations and cover a Critical data-loss bug and two High bugs. Add BUG-002 (cross-user leak) as the fourth once its two possible failure modes are observed. Confirm BUG-014's runtime path, then create its file.
- **Second (seam) batch — belongs in the fix PRs, not this phase:** BUG-029, BUG-006, BUG-016 each need a tiny production seam that is effectively part of their fix; write the test alongside the fix.
- **First manual UI verification batch afterward (from the RUNBOOK, needs a human/device):** BUG-011 (settings unreachable — quick GUI check), BUG-009 (stable-channel window matching), BUG-090 (Report-Issue reopen crash). Then the hardware/instrumented set: BUG-004 (mic indicator), BUG-005 (TSan), BUG-010 (BLE device).
- **Do not open fix PRs and do not mark anything Confirmed** until these tests actually run on macOS and produce logs. This document and the four drafted files are planning + drafting only.
