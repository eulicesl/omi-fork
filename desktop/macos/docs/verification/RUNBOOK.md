# Omi macOS Runtime Verification Runbook (Queue)

> **This queue must be executed on a real macOS/Xcode machine.** It was authored in a Linux container that cannot build or run the Swift app, so **nothing here is verified yet** — every result field below is empty by design. Source of truth: the audit report at commit `fff46934` (`desktop/macos/docs/omi-macos-bug-audit-2026-07-06.md`), "macOS Runtime Verification Required" section.

## How to use this queue

1. Fill in the **Environment** block below on the Mac before starting.
2. Work the bugs **top-to-bottom** — they are ordered by the requested priority (Critical/data-loss → auth/security → recording/audio → onboarding → settings → nav/window → cosmetic).
3. For each bug: run the recipe, capture evidence into `evidence/BUG-XXX/`, then set the **Result** to one of: `Confirmed` / `Not reproducible` / `Inconclusive` / `Needs different setup`. **`Confirmed` requires attached runtime evidence** (screenshot, recording, log excerpt, TSan report, crash trace, or a passing/failing XCTest).
4. Copy each completed block into `REPORT-TEMPLATE.md` (or fill it in place) to produce the final verification report.
5. **Do not fix** anything in this phase. If you add temporary debug logging, do not commit it.

## Two verification tracks

Some bugs are **logic bugs unit-testable headless** (fastest path to real evidence — run on the Mac or on Codemagic CI with `xcrun swift test`, no GUI). Others need **manual GUI / a real device / packet capture / TSan**. Each bug is tagged `[AUTO]` (write a focused XCTest — spec provided) or `[MANUAL]` / `[DEVICE]` / `[TSAN]` / `[CAPTURE]`. Start with `[AUTO]` for the quickest confirmations.

## Environment (fill on macOS)

| Field | Value |
|---|---|
| Repository | `eulicesl/omi-fork` |
| Branch | `claude/omi-macos-audit-skjwgd` |
| Commit SHA under test | `______` (checkout `fff46934` or a descendant; record actual) |
| Audit report commit | `fff46934` |
| macOS version | `______` (`sw_vers`) |
| Xcode version | `______` (`xcodebuild -version`) |
| Build command | `______` (`cd desktop/macos && OMI_APP_NAME="omi-verify" ./run.sh`; unit tests: `xcrun swift test --package-path Desktop`) |
| Run method | `______` (named bundle via run.sh; omi-ctl / agent-swift for driving) |
| Verification date | `______` |

## Common setup (once)

```bash
cd desktop/macos
git checkout fff46934            # or the descendant you are testing; record the SHA
OMI_APP_NAME="omi-verify" ./run.sh          # builds + installs /Applications/omi-verify.app, seeds auth from "Omi Dev"
# drivers:
brew install beastoin/tap/agent-swift       # if not present; grant Accessibility to Terminal
./scripts/omi-ctl state                     # confirm bridge is up
tail -f /private/tmp/omi-dev.log            # app log (dev); or /private/tmp/omi.log
# unit-test track:
xcrun swift test --package-path Desktop      # runs the SwiftPM test target
```

Evidence goes in `desktop/macos/docs/verification/evidence/BUG-XXX/` (screenshots `*.png`, recordings `*.mov`, logs `*.log`, test output `*.txt`).

---

# QUEUE

## Priority 1 — Critical / data-loss

### BUG-001 — Retention delete wipes the Screenshots directory  ·  `[AUTO]` (preferred) + `[MANUAL]` confirm
- **Audit prediction:** `RewindDatabase.swift:3043` retention query returns `imagePath=""` rows; `RewindStorage.swift:516-533` `deleteScreenshot` has no empty guard → `appendingPathComponent("")` targets the Screenshots dir → recursive wipe.
- **`[AUTO]` test spec:** Add a temporary XCTest (do not commit) that (a) inserts a screenshot row with `imagePath: ""` via `RewindDatabase.insertScreenshot`, (b) writes two dummy JPEGs into the user Screenshots dir, one older than retention and one newer, (c) calls `deleteScreenshotsOlderThan(cutoff)` then the storage delete path, (d) asserts the newer JPEG still exists. **Also** unit-test the pure fact: `URL(fileURLWithPath: dir).appendingPathComponent("").path == dir` and `FileManager.fileExists(atPath:)` is true for it — this alone proves the blast-radius mechanism without touching the DB.
- **`[MANUAL]` confirm:** run the app with the video pipeline so real rows have `imagePath:""`; snapshot `ls -R .../Screenshots` before, trigger retention, snapshot after.
- **Expected:** only expired files deleted. **Predicted actual:** entire Screenshots dir removed.
- **Evidence to capture:** XCTest output (`evidence/BUG-001/test.txt`); `ls -R` before/after (`before.txt`/`after.txt`).
- **Pass/fail criterion:** if the newer in-retention JPEG is gone → **Confirmed**.
- **Result:** `______`  **Evidence path:** `evidence/BUG-001/`  **Notes:** `______`

### BUG-013 / BUG-014 — Rewind rebuild no-op / corruption-recovery bricks DB  ·  `[AUTO]`
- **Audit prediction:** rebuild filters `.hevc` while encoder writes `.mp4` (0 chunks); `parseChunkTimestamp` expects the old 26-char name. Recovery writes `screenshots` without `grdb_migrations` → next migrate throws "table already exists" every launch.
- **`[AUTO]` test spec:** (013) unit-test `RewindStorage.getAllVideoChunks()` against a fixture dir containing a real `chunk_HHmmss.mp4` → assert it is **not** returned (proves the no-op); unit-test `RewindIndexer.parseChunkTimestamp("chunk_143052.mp4")` → assert `nil`. (014) build a DB via `attemptDirectTableRecovery`, then call the init/`migrate` path → assert it throws / fails to open, and that a second launch fails identically.
- **Expected:** rebuild re-indexes chunks; recovered DB opens. **Predicted actual:** 0 chunks; migration throws every launch.
- **Evidence:** test output (`evidence/BUG-013/`, `evidence/BUG-014/`).
- **Result:** `______`  **Notes:** `______`

### BUG-002 — Cross-user storage pool reuse after sign-out  ·  `[AUTO]` + `[MANUAL]`
- **Audit prediction:** `AuthService.swift:2090-2095` invalidates 6 actors; Goal/StagedTask/TaskChatMessage/FileIndexer/KnowledgeGraph `invalidateCache()` never called → previous user's `DatabasePool` reused.
- **`[AUTO]` test spec:** unit-test that after `RewindDatabase.configure(userId: A)` and touching e.g. `GoalStorage.shared`, then `configure(userId: B)`, `GoalStorage`'s resolved DB path is B's — expected to FAIL (proving reuse) until invalidateCache is wired.
- **`[MANUAL]`:** sign in as A, create a goal + a staged task + a knowledge-graph entry; sign out; sign in as B; check whether A's goal/task/graph appear.
- **Expected:** B sees only B's data. **Predicted actual:** B reads/writes A's `omi.db`.
- **Evidence:** test output; screen recording of B seeing A's data; log the resolved DB path per actor (`evidence/BUG-002/`).
- **Result:** `______`  **Notes:** `______`

## Priority 2 — Auth / session / security

### BUG-006 — Sign-out re-persists an in-flight token refresh  ·  `[AUTO]`
- **Audit prediction:** `refreshIdToken` (`AuthService.swift:1883-1942`) has no session-generation guard; a refresh resuming after `signOut` calls `saveTokens`; `getIdToken` backfills `auth_userId`.
- **`[AUTO]` test spec:** inject a fake token endpoint that blocks on a signal; start `refreshIdToken()`; call `signOut()`; release the signal; assert Keychain/UserDefaults hold **no** tokens and `auth_userId` is absent. (Needs a seam to substitute the URLSession — add temporary local injection, do not commit.)
- **Expected:** no tokens post-signout. **Predicted actual:** refreshed tokens + `auth_userId` re-persisted.
- **Evidence:** test output; Keychain/UserDefaults dump (`evidence/BUG-006/`).
- **Result:** `______`  **Notes:** `______`

### BUG-007 — Plaintext token + DB to agent VM  ·  `[CAPTURE]`
- **Audit prediction:** `AgentVMService.swift` uses `http://<vmIP>:8080/...?token=...` + Firebase token in cleartext body.
- **`[CAPTURE]` steps:** enable the agent-VM feature; run a DB upload/auth; capture traffic (Charles/mitmproxy/tcpdump on the path). Confirm scheme is `http` and the token appears in URL + body.
- **Expected:** TLS, no token in URL. **Predicted actual:** cleartext HTTP with token in query + body.
- **Evidence:** packet capture excerpt (redact the token) (`evidence/BUG-007/`).
- **Result:** `______`  **Notes:** `______`  **Note:** VM is a private-IP GCE host per the service map — record whether the path is actually interceptable.

## Priority 3 — Recording / audio

### BUG-004 — Orphaned mic IOProc stays hot after stop  ·  `[MANUAL]`
- **Audit prediction:** `reconfigureAfterChange` (`AudioCaptureService.swift:773-851`) has no `isCapturing` guard; stop during the 0.3–3 s reconfigure window restarts the IOProc.
- **Steps:** start recording → change input device (or flip a BT mic profile) → within ~1 s press stop → observe the macOS mic-in-use (orange dot) indicator and Control Center "microphone in use".
- **Expected:** mic released. **Predicted actual:** mic stays hot until quit; subsequent stop is a no-op.
- **Evidence:** screen recording showing the indicator still on after stop; `omi.log` reconfigure lines (`evidence/BUG-004/`).
- **Result:** `______`  **Notes:** `______`

### BUG-005 — Data races on audio turn buffers  ·  `[TSAN]`
- **Audit prediction:** `omniPreconnectBuffer` / `pendingAudio` / `pendingBargeInReplacement` appended on the IOProc thread while read/cleared on main, no lock.
- **Steps:** build with ThreadSanitizer (`xcrun swift build -c debug -Xswiftc -sanitize=thread` or the scheme's TSan option; or run `./scripts/agent-logic-harness.sh` under TSan); exercise a Gemini barge-in replacement and an omni PTT turn.
- **Expected:** no TSan reports. **Predicted actual:** race reported on those buffers.
- **Evidence:** TSan report text (`evidence/BUG-005/tsan.txt`).
- **Result:** `______`  **Notes:** `______`  (Races are nondeterministic — run several times.)

### BUG-010 — BLE disconnect leaves sync/streams hanging  ·  `[DEVICE]`
- **Audit prediction:** `BleTransport.handleDisconnection:107-113` doesn't finish streams / cancel continuations that `disconnect():160-193` does.
- **Steps:** connect a real Omi device; start an SD-card sync (or audio stream); power off / walk out of range mid-transfer.
- **Expected:** sync/stream ends with an error; UI recovers. **Predicted actual:** UI stuck "syncing" (`isSyncing` true) until app restart.
- **Evidence:** screen recording of the stuck state; `omi.log` (`evidence/BUG-010/`).
- **Result:** `______`  **Notes:** `______`

### BUG-030 — Chord PTT stuck-recording on modifier-first release  ·  `[MANUAL]`
- **Audit prediction:** `matchesKeyUp` requires exact modifier equality; releasing ⌘⇧Space drops modifiers before the key-up.
- **Steps:** bind PTT to a key+modifier chord (⌘⇧Space); with `pttMuteSystemAudio` on and music playing, hold the chord, speak, release all keys at once.
- **Expected:** turn ends, mic released, music unmutes. **Predicted actual:** stuck `.listening`, music stays muted until a clean second chord.
- **Evidence:** screen recording (PTT UI + muted audio) (`evidence/BUG-030/`).
- **Result:** `______`  **Notes:** `______`

### BUG-029 — Live notes stop after ~500 words  ·  `[AUTO]` + `[MANUAL]`
- **Audit prediction:** `LiveNotesMonitor:244-317` `lastProcessedSegmentOrder` pins at 500 → `wordsSinceLastNote` stays 0.
- **`[AUTO]` test spec:** drive `LiveNotesMonitor.handleSegmentsUpdate` with synthetic segments totaling >600 words in 50-word steps; assert a note is still generated after word 500.
- **`[MANUAL]`:** run a >5-minute transcription and watch whether AI notes keep appearing.
- **Expected:** notes keep generating. **Predicted actual:** notes stop permanently past 500 words.
- **Evidence:** test output; note-count-vs-word-count log (`evidence/BUG-029/`).
- **Result:** `______`  **Notes:** `______`

### BUG-089 — Quit-while-recording leaves the session unfinalized  ·  `[MANUAL]`
- **Audit prediction:** willTerminate cleanup is wrapped in `Task{@MainActor}` that can't run before `applicationWillTerminate` blocks main on the flush semaphore.
- **Steps:** start recording → ⌘Q → relaunch; inspect the recovery pass and the session's end reason.
- **Expected:** session finalized cleanly (`.userStop`). **Predicted actual:** session left open, recovered as crashed next launch, contradicting `lastSessionCleanExit`.
- **Evidence:** `omi.log` recovery lines across quit+relaunch (`evidence/BUG-089/`).
- **Result:** `______`  **Notes:** `______`

## Priority 4 — Settings persistence / reachability

### BUG-011 — AI-chat settings (Ask Mode / CLAUDE.md / Skills) unreachable  ·  `[MANUAL]`
- **Audit prediction:** `SettingsPage.swift:498-527` redirects `.aiChat`→`.advanced`; the toggles live only in the dead section; `aiSetupSubsection` lacks them.
- **Steps:** open Settings; try to reach Ask Mode, CLAUDE.md enable, and per-skill enable. Use `agent-swift snapshot -i` to confirm the redirect and that the toggles are absent from the advanced section.
- **Expected:** toggles reachable. **Predicted actual:** `.aiChat` immediately redirects; toggles nowhere in the UI.
- **Evidence:** screen recording of the redirect; `agent-swift` snapshot (`evidence/BUG-011/`).
- **Result:** `______`  **Notes:** `______`

### BUG-015 — Rewind search throws on punctuation  ·  `[AUTO]` + `[MANUAL]`
- **Audit prediction:** `RewindDatabase.expandSearchQuery:2879-2912` interpolates raw `word*` into FTS5 MATCH; `don't`/`e-mail`/`3:30pm` throw.
- **`[AUTO]` test spec:** call `RewindDatabase.search(query:)` with `don't`, `e-mail`, `3:30pm`, `a`, `api.omi.me`; assert it throws (or returns cleanly) — expected to throw `SQLITE_ERROR` on the punctuated inputs.
- **`[MANUAL]`:** type those in the Rewind search box; observe stale/no results + `omi.log` FTS error.
- **Expected:** results or clean empty state. **Predicted actual:** FTS syntax error swallowed, previous results left on screen.
- **Evidence:** test output; screen recording; `omi.log` (`evidence/BUG-015/`).
- **Result:** `______`  **Notes:** `______`

## Priority 5 — Navigation / window

### BUG-009 — `hasPrefix("Omi")` misses lowercase stable-channel title  ·  `[MANUAL]`
- **Audit prediction:** stable title is `omi vX.Y`; 5 `hasPrefix("Omi")` sites (hotkey reveal, dock reopen, width restore, onboarding, browser-setup) fail to match.
- **Steps:** on a **stable-channel** build (or a bundle whose window title starts lowercase `omi`): close/hide the main window → press Ctrl+Opt+R (Rewind hotkey); test dock-icon reopen; quit with the task-chat panel open → relaunch and check window width.
- **Expected:** window surfaces / width restored. **Predicted actual:** hotkey looks dead, dock reopen skips deminiaturize, width not restored.
- **Evidence:** screen recording of the dead hotkey on stable vs working on beta (`evidence/BUG-009/`).
- **Result:** `______`  **Notes:** `______`  **Setup note:** needs a stable-channel title; a Dev/Beta build (title "Omi …") will falsely pass.

### BUG-090 — FeedbackWindow reopen over-release/UAF crash  ·  `[MANUAL]`
- **Audit prediction:** `FeedbackView.swift:8-33` retains a static `NSWindow` with default `isReleasedWhenClosed=true`; reopen messages a deallocated window.
- **Steps:** open "Report Issue…" → close with the red X → open "Report Issue…" again. Repeat a few times.
- **Expected:** reopens cleanly. **Predicted actual:** EXC_BAD_ACCESS crash on reopen.
- **Evidence:** crash log / spindump (`evidence/BUG-090/crash.txt`); screen recording.
- **Result:** `______`  **Notes:** `______`

## Priority 6 — Chat session integrity (High, but GUI-race)

### BUG-016 / 017 / 018 — Cross-session message bleed on rapid switch  ·  `[MANUAL]` + `[AUTO]`
- **Audit prediction:** `ChatProvider` mutates `messages` after `await` with no session-generation guard (`selectSession:1717`, `pollForNewMessages:2757`, `loadMoreMessages:1748`).
- **`[MANUAL]`:** create ≥2 sessions with history; click session A then immediately session B (throttle the network to widen the window); also trigger the app-activation poll while switching. Watch for A's messages appearing under B.
- **`[AUTO]` test spec:** with an injected slow `getMessages`, call `selectSession(A)` then `selectSession(B)`; assert `messages` end as B's after both resolve.
- **Expected:** each session shows its own messages. **Predicted actual:** late/stale response overwrites or appends into the wrong session.
- **Evidence:** screen recording of A's messages under B's title; test output (`evidence/BUG-016/`).
- **Result:** `______`  **Notes:** `______`

---

## Result tally (fill in)

| Bug | Track | Result | Evidence? |
|---|---|---|---|
| BUG-001 | AUTO/MANUAL | `___` | `___` |
| BUG-013 | AUTO | `___` | `___` |
| BUG-014 | AUTO | `___` | `___` |
| BUG-002 | AUTO/MANUAL | `___` | `___` |
| BUG-006 | AUTO | `___` | `___` |
| BUG-007 | CAPTURE | `___` | `___` |
| BUG-004 | MANUAL | `___` | `___` |
| BUG-005 | TSAN | `___` | `___` |
| BUG-010 | DEVICE | `___` | `___` |
| BUG-030 | MANUAL | `___` | `___` |
| BUG-029 | AUTO/MANUAL | `___` | `___` |
| BUG-089 | MANUAL | `___` | `___` |
| BUG-011 | MANUAL | `___` | `___` |
| BUG-015 | AUTO/MANUAL | `___` | `___` |
| BUG-009 | MANUAL | `___` | `___` |
| BUG-090 | MANUAL | `___` | `___` |
| BUG-016/017/018 | MANUAL/AUTO | `___` | `___` |

## Fastest path to real "Confirmed" evidence
The `[AUTO]` bugs (**001, 013, 014, 015, 029**, and the injectable halves of **002, 006, 016**) are logic/persistence defects that a focused XCTest confirms **headless** — runnable on the Mac via `xcrun swift test --package-path Desktop`, or on Codemagic macOS CI, with no GUI or device. Do these first: they convert code-inspection findings into executable-test evidence quickly. The `[MANUAL]`/`[DEVICE]`/`[TSAN]`/`[CAPTURE]` bugs need a human at a Mac (and a device / packet capture / TSan build) and cannot be automated the same way.
