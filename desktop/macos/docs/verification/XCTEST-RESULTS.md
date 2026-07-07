# XCTest Verification Results

> **Status: RUN BLOCKED — no macOS runner available.** The four no-seam tests were **not compiled and not executed**. This session is a Linux container with no `swift`/`xcrun`/`xcodebuild` and no reachable macOS environment, so `xcrun swift test` cannot run here. No bug can be marked Confirmed. Per the phase rules, this is recommendation **#4 (macOS runner unavailable → runtime verification still blocked)**. No results were fabricated.

## Metadata

- Repository: `eulicesl/omi-fork`
- Branch: `claude/omi-macos-audit-skjwgd`
- Commit SHA: `f327a2a630345311ec40db7d96c9c9975baa6461`
- macOS version: **N/A — not macOS** (`uname -srm` → `Linux 6.18.5 x86_64`)
- Xcode version: **N/A — `xcodebuild` not found**
- Swift version: **N/A — `swift`/`swiftc` not found**
- Test date: 2026-07-07
- Run method: attempted `xcrun swift test --package-path desktop/macos --filter <Class>` and fallback `swift test --filter <Class>` — **both failed with `command not found` (exit 127)**. Raw attempt logs saved per bug (see evidence paths).

## Summary

- Tests attempted (commands issued): 4
- Tests compiled: **0** (no toolchain)
- Tests failed as expected: **0** (not run)
- Tests passed unexpectedly: **0** (not run)
- Tests failed due to test-draft issues: **0 observed** — cannot be determined without a compiler; the drafts remain unverified against the Swift compiler
- Bugs confirmed: **0**
- Bugs still unconfirmed: **4** (BUG-001, BUG-015, BUG-013, BUG-002) — all blocked on a macOS runner

## Results

### BUG-001: Retention/empty-imagePath delete wipes the Screenshots directory
- Test class: `RewindEmptyImagePathDeletionTests`
- Command: `xcrun swift test --package-path desktop/macos --filter RewindEmptyImagePathDeletionTests`
- Compile result: **Not attempted** — `xcrun`/`swift` not present on this Linux host
- Runtime result: **Not run** (exit 127, `command not found`)
- Expected failure: `testCleanupWithEmptyImagePathDoesNotWipeScreenshotsDirectory` should fail red — the in-retention JPEG is deleted when the aged `imagePath:""` row wipes the whole `Screenshots/` dir. (`testEmptyImagePathComponentResolvesToParentDirectory` should pass, documenting the mechanism.)
- Actual failure: **None observed** — test did not execute
- Evidence path: `desktop/macos/docs/verification/evidence/BUG-001/xctest-attempt.txt`
- Verification verdict: **Inconclusive** (macOS runner unavailable — not Confirmed, not Not-confirmed)
- Notes: Draft mirrors the existing passing `RewindRetentionCleanupTests` setup; signatures were verified against source but never compiled.

### BUG-015: Rewind FTS search throws on common punctuation
- Test class: `RewindSearchFTSPunctuationTests`
- Command: `xcrun swift test --package-path desktop/macos --filter RewindSearchFTSPunctuationTests`
- Compile result: **Not attempted** — no toolchain
- Runtime result: **Not run** (exit 127)
- Expected failure: `testSearchWithApostropheDoesNotThrow` / `testSearchWithHyphenColonAndDotDoesNotThrow` should fail red — `search("don't")` etc. throw `SQLITE_ERROR` from the unescaped FTS5 MATCH
- Actual failure: **None observed**
- Evidence path: `desktop/macos/docs/verification/evidence/BUG-015/xctest-attempt.txt`
- Verification verdict: **Inconclusive** (runner unavailable)
- Notes: `RewindDatabase` is an actor; the draft was written to `await search(...)` in an async do/catch (the earlier `XCTAssertNoThrow` form would not have compiled). This actor-await correctness is itself unverified until compiled on macOS.

### BUG-013: Rewind chunk rebuild is a no-op (`.hevc` filter vs `.mp4` writer)
- Test class: `RewindVideoChunkRebuildFormatTests`
- Command: `xcrun swift test --package-path desktop/macos --filter RewindVideoChunkRebuildFormatTests`
- Compile result: **Not attempted** — no toolchain
- Runtime result: **Not run** (exit 127)
- Expected failure: `testGetAllVideoChunksFindsRealMp4ChunkFiles` should fail red — `getAllVideoChunks()` returns empty for a real `.mp4` because it enumerates only `.hevc`
- Actual failure: **None observed**
- Evidence path: `desktop/macos/docs/verification/evidence/BUG-013/xctest-attempt.txt`
- Verification verdict: **Inconclusive** (runner unavailable)
- Notes: Uses the public `getVideosDirectory()` accessor to place the fixture; no path assumptions beyond that.

### BUG-002: Storage actors reuse the prior user's DB pool after a user switch
- Test class: `GoalStorageUserSwitchIsolationTests`
- Command: `xcrun swift test --package-path desktop/macos --filter GoalStorageUserSwitchIsolationTests`
- Compile result: **Not attempted** — no toolchain
- Runtime result: **Not run** (exit 127)
- Expected failure: `testGoalStorageDoesNotServePreviousUsersGoalsAfterSwitch` should fail red (user B sees user A's goal) — or **error** if the cached pool was torn down by `close()` (documented alternative; either outcome is non-green)
- Actual failure: **None observed**
- Evidence path: `desktop/macos/docs/verification/evidence/BUG-002/xctest-attempt.txt`
- Verification verdict: **Inconclusive** (runner unavailable)
- Notes: `GoalRecord` initializer mirrors the proven-compiling `GoalRecord.from(_:)` call site (omits `id:`), reducing compile risk; still unverified.

## Recommended Next Step

**#4 — The macOS runner is unavailable, so runtime verification is still blocked.** Nothing was compiled or executed; all four bugs remain **Inconclusive**, not Confirmed.

### Next executable path: Codemagic macOS CI (workflow drafted)

Because this Linux session cannot run Swift/Xcode, the next executable path is a **verification-only Codemagic macOS workflow**, now drafted at `desktop/macos/docs/verification/codemagic-xctest-workflow.yaml` (workflow id **`omi-desktop-xctest-verify`**, `mac_mini_m2`, `xcode: 16.4`). It runs each of the four test classes with `xcrun swift test --package-path Desktop --filter <Class>` from `working_directory: desktop/macos`, writes per-bug logs into `evidence/BUG-XXX/`, and uploads them as artifacts. It has **no** signing/notarization/publishing and **no** auto-trigger (manual only). Run it, download the artifacts into the matching `evidence/BUG-XXX/` folders (replacing the `xctest-attempt.txt` placeholders), and I will fill in the real compile/runtime verdicts here.

To unblock without CI, the same commands run on any macOS/Xcode machine or self-hosted Apple-silicon runner. Prereq: `brew install webp` (CWebP system dependency).

Two outcomes to watch for when it runs:
- **Compile error** on any drafted file → classify as a **test-draft issue** (not bug confirmation); I correct the test and it re-runs. The likeliest spots are the actor-await forms (BUG-015) and the `GoalRecord` initializer (BUG-002), both written against verified signatures but never compiler-checked.
- **Unexpected pass** → the audit finding may be wrong, already fixed at the tested SHA, or the test isn't exercising the bug → re-audit that specific finding before any fix.

No production code was changed, no seams were drafted, and no PR was opened.
