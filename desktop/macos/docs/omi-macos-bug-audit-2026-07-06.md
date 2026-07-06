# Omi macOS Bug Audit Report

> Audit-only deliverable. No code was changed; this is a prioritized, evidence-backed bug inventory to work through.

## Audit Metadata

| Field | Value |
|---|---|
| Repository | `eulicesl/omi-fork` (fork of `BasedHardware/omi`) |
| Branch | `claude/omi-macos-audit-skjwgd` |
| Commit SHA | `35cba7b233b94a68aa86aab8490bf6bee5f75b1d` (origin/main, tip at audit time) |
| Audit date | 2026-07-06 |
| Target | macOS desktop app only (`desktop/macos/Desktop/`, Swift Package Manager + Rust backend) |
| macOS version | N/A — audit ran in a **Linux container** |
| Xcode / Swift toolchain | **Not available** (no `swift`/`xcrun`); Swift app could not be compiled or run here |
| Rust toolchain | cargo 1.94.1 |
| Build command (attempted) | Rust backend: `cargo check --all-targets` → **passed (exit 0)**, 3 dead-code warnings in test code. Swift app: **not buildable in this environment** |
| Run method | **None** — no runtime reproduction was possible (no macOS, no Swift). All findings are code-inspection based |
| Total audit loops completed | 2 (Loop 1: 11 parallel area audits; Loop 2: cross-cutting pattern sweeps + adversarial source verification of top findings) |

### Critical honesty caveat on "Confirmed"

The task rubric reserves **Confirmed** for bugs *reproduced locally through build/runtime/manual testing*. **This environment has no macOS and no Swift toolchain, so nothing could be run.** Therefore **zero findings are classified "Confirmed."** Every finding below is **High-Confidence Code Inspection**, **Potential Edge Case**, or **False Positive**. Where I write "verified," it means I re-read the exact source lines and the code path provably does the stated thing — not that it was executed. Runtime confirmation on a real Mac is the required next step before fixes ship, and each High/Critical item notes whether visual/runtime proof is needed.

---

## Executive Summary

- **High-confidence code-inspection bugs:** ~120 distinct defects across 11 feature areas (raw agent output before de-dup: ~138).
- **Confirmed (reproduced locally):** 0 — see caveat above (Linux-only environment).
- **Potential edge cases needing verification:** ~18 (device-protocol wire formats, backend echo semantics, Firebase SDK internals, scheduler timing).
- **False positives ruled out:** documented per area (e.g. the two remaining UI force-unwraps are guarded; several settings keys verified string-consistent).
- **Highest-risk areas:** Rewind (data loss + cross-user leakage + broken recovery), Audio/BLE (mic-stays-hot, hangs, data races), Auth/session (sign-out races, cross-account bleed), Chat/agent-runtime (stuck turns, cross-session message bleed, process leaks), Settings routing (whole config sections unreachable).
- **Recommended first PRs (in order):**
  1. **PR-1 Rewind data-loss & recovery** — BUG-001 (retention wipes Screenshots dir), BUG-013 (rebuild-index no-op), BUG-014 (corruption-recovery bricks DB).
  2. **PR-2 Cross-user data isolation** — BUG-002 (5 storage actors never invalidated on sign-out) + BUG-006 (sign-out re-persists refreshed tokens).
  3. **PR-3 Recording safety** — BUG-004 (orphaned mic IOProc stays hot), BUG-005 (audio-thread data races), BUG-010 (BLE disconnect hangs consumers).
  4. **PR-4 Settings reachability** — BUG-011 (AI-chat settings unreachable), plus the sidebar-title match class (BUG-009).

---

## Audit Loop Summary

### Loop 1 — Repository/architecture mapping + 11 parallel feature-area code audits
- **Areas covered:** app lifecycle/windows/menu bar; audio capture/recording/BLE/WAL; auth/session/permissions; settings/persistence/providers; main-window pages/navigation; floating bar/PTT/realtime/live-notes; Rewind/file-indexing; networking/API client/notifications/agent-VM; chat UI; chat agent-runtime bridge; onboarding.
- **New bugs found:** ~138 raw (deduped to ~120 distinct high-confidence + ~18 edge cases).
- **Notes:** Entry point `OmiApp.swift` (`@main`), 381 Swift files, ~200k LOC. Largest surfaces: generated API (8.5k), APIClient (6.1k), TasksPage (5.8k), ChatProvider (5.0k), FloatingControlBarWindow (4.3k). Each area was read by a dedicated skeptical auditor with quoted evidence; per-area raw reports are archived in the scratchpad.

### Loop 2 — Cross-cutting pattern sweeps + adversarial verification
- **Areas covered:** re-scan of every discovered bug *class* across the whole tree; direct source re-read of the top-severity findings.
- **New bugs found:** **0 net-new credible defects.** The sweeps instead *confirmed the extent* of Loop 1's classes and verified six top findings line-by-line against source:
  - `invalidateCache()` sweep → **exactly 11 storage actors define it, only 6 called at sign-out** (confirms BUG-002; the 5 missing are KnowledgeGraph, FileIndexer, StagedTask, Goal, TaskChatMessage).
  - `hasPrefix("Omi")` sweep → **5 case-sensitive sites** vs ~14 correct `lowercased().hasPrefix("omi")` sites; title on stable channel is literally `"omi vX.Y"` (`UpdaterViewModel.swift:31`) — confirms BUG-009.
  - `URLSession(delegate:self)` sweep → **exactly 2 leaking sites** (RealtimeOmniService, RealtimeHubSession); TranscriptionService correctly invalidates — confirms BUG-034.
  - FTS `MATCH` sweep → `ActionItemStorage`/`StagedTaskStorage` sanitize; `RewindDatabase`/`ProactiveStorage`/`TaskChatMessageStorage` interpolate raw tokens — confirms BUG-015.
  - R1 retention path → video frames stored `imagePath: ""`, delete query filters only `IS NOT NULL`, `deleteScreenshot` has no empty-path guard — confirms BUG-001 (data loss).
  - N2 `$0` shadowing → `$0.appId == $0.id` self-comparison verified verbatim — confirms BUG-024.
- **Notes:** Because a full cross-cutting sweep produced no new credible bug (only breadth confirmation), the discovery loop reached its stop condition.

### Why the audit stopped
Loop 2's whole-tree sweeps for each discovered bug class surfaced no defect not already captured in Loop 1 — they only widened/verified known classes. Combined with the hard constraint that no runtime reproduction is possible here, additional inspection loops would yield diminishing returns. The correct next step is **runtime verification on a real Mac**, not more static passes.

---

## Cross-Bug Patterns (root-cause classes)

These recurring root causes drive most of the inventory; fixing the *class* prevents regressions:

1. **Empty-result used as "filter inactive" proxy** — `!filteredFromDatabase.isEmpty` treated as "a filter is applied." A legitimate zero-match filter then shows the *entire* list instead of an empty state. Instances: BUG-019 (Memories), BUG-020 (Tasks). Grep-confirmed both sites.
2. **Stale async response overwrites newer state (no request-generation guard)** — `await`-then-assign-`@Published` with no check that the input still matches. Instances: BUG-016 (chat selectSession), BUG-017 (chat poll cross-session bleed), BUG-018 (chat loadMore), BUG-025 (conversation search), BUG-026 (task search), BUG-036 (goal drag), BUG-050 (persona username), BUG-035 (omni STT turn). The codebase *has* the correct pattern (`requestFiltersAreCurrent()`, `sendGeneration`) — it just isn't applied consistently.
3. **Storage-actor cache not invalidated on account switch** — pool-caching actors keep the previous user's `DatabasePool`. Instance: BUG-002 (5 actors). Cross-user read/write.
4. **Optimistic mutation with no rollback + swallowed error** — UI/SQLite updated optimistically; API failure only `logError`'d; next server sync silently reverts (or resurrects). Instances: BUG-036/037/038 (goals), BUG-027/028 (conversation delete/title), BUG-042/043 (memory edit/create), BUG-045/046 (task toggle/restore), plus ~142 `logError`-only catch sites in the UI layer, many with no error surface.
5. **Case-sensitive `hasPrefix("Omi")` window matching** — breaks on the stable channel where the title is lowercase. Instance: BUG-009 (5 sites: hotkey reveal, dock reopen, window-width restore, +2).
6. **`URLSession` delegate retain cycle** — `URLSession(delegate:self)` never `invalidateAndCancel()`'d. Instance: BUG-034 (2 sites, per-session/per-turn leak).
7. **`CheckedContinuation` mis-resume** — never-resumed (stuck forever) or double-resumed (`fatalError`). Instances: BUG-012 (query sendJson failure), BUG-010 (BLE disconnect), BUG-033 (device command timeout races).
8. **Dead/unreachable UI behind a hard redirect or missing entry point** — settings/features wired but unreachable. Instances: BUG-011 (AI-chat settings), BUG-029 (merge UI), BUG-048 (goals history), BUG-047 (ChatLab), dead onboarding views.
9. **Diagnostics/logging without a production gate or redaction** — BUG-003 (QueryTracer writes memories to disk), BUG-008 (OAuth code via NSLog), BUG-032 (plaintext token on network).
10. **Offset-based pagination over a mutating dataset / two datasets sharing one cursor** — BUG-021/044 (task pagination), BUG-043 (memory device-scope cursor), BUG-030 (conversations 50-cap).

---

## Complete Bug Inventory

Severity uses the task rubric: **Critical** = crash / data loss / broken core recording-audio-session / security-privacy. **High** = major flow broken, session/permission/recording unreliable, state corruption. **Medium** = important feature bug, wrong persistence, broken navigation. **Low** = cosmetic / minor edge case. All confidence values are **High** or **Medium** *code-inspection* confidence (no runtime confirmation possible here).

### CRITICAL

#### BUG-001 — Rewind retention cleanup (and single-delete) deletes the entire legacy `Screenshots/` directory
- **Severity:** Critical (user data loss) · **Confidence:** High
- **Area:** Rewind / local storage
- **User impact:** All legacy JPEG screenshots — including ones well within the retention window — are recursively deleted once any video-era row ages past retention (default 7 days), or on a single manual delete of any video-based screenshot.
- **Files/symbols:** `Rewind/Core/RewindDatabase.swift:3043` (`deleteScreenshotsOlderThan`, query filters only `imagePath IS NOT NULL`), `Rewind/Core/RewindStorage.swift:95,111,126` (`deleteScreenshot(relativePath:)` — no empty guard), `Rewind/Services/RewindIndexer.swift:251,333,437,680` (`insertScreenshot` stores `imagePath: ""`), `Rewind/UI/RewindViewModel.swift:412-416`.
- **Repro (needs real Mac):** Record with the video pipeline (frames stored `imagePath:""`), wait past retention, trigger cleanup; observe `Screenshots/` recursively removed.
- **Expected:** Only the specific expired screenshot files are deleted.
- **Actual:** `""` → `screenshotsDirectory.appendingPathComponent("")` = the directory itself → `removeItem` wipes everything.
- **Evidence:** query selects `""` rows (they are NOT NULL); the app already knows the guard elsewhere (`imagePath = ''` used at `RewindDatabase.swift:2234,2240`) but not in the delete path.
- **Root cause:** `""` sentinel for "no image" not excluded on the delete path.
- **Fix:** Add `AND imagePath != ''` to both retention/single-delete queries; map `""`→nil in `SingleDeleteResult`; `guard !relativePath.isEmpty` in `RewindStorage.deleteScreenshot`.
- **Tests:** Unit test `deleteScreenshotsOlderThan` returns no `""` paths; `deleteScreenshot("")` is a no-op. **Visual proof:** yes (before/after file tree).
- **PR:** PR-1.

#### BUG-002 — Five storage actors keep the previous user's DB pool after sign-out (cross-user data leakage)
- **Severity:** Critical (privacy / data integrity) · **Confidence:** High
- **Area:** Auth / storage isolation
- **User impact:** After user A signs out and user B signs in on the same Mac, B's goals, staged tasks, task-chat messages, file index, and knowledge graph are read from / written into **A's** database.
- **Files/symbols:** `AuthService.swift:2090-2095` (invalidates only 6 of 11 actors); never-called `invalidateCache()` in `Rewind/Core/GoalStorage.swift`, `Rewind/Core/StagedTaskStorage.swift`, `Rewind/Core/TaskChatMessageStorage.swift`, `FileIndexing/FileIndexerService.swift`, `FileIndexing/KnowledgeGraphStorage.swift`.
- **Expected:** Every per-user storage actor drops its cached pool on account switch.
- **Actual:** 5 actors cache `_dbQueue` forever; `GoalStorage`'s own doc comment says it should be invalidated "on user switch/sign-out."
- **Evidence:** Loop-2 grep — 11 `func invalidateCache` defined, only 6 call sites (all in AuthService).
- **Root cause:** Manual invalidation list drifted from the set of pool-caching actors.
- **Fix:** Add the 5 missing `invalidateCache()` calls to the sign-out block; better, validate pool generation against `RewindDatabase` per access.
- **Tests:** Sign-out test asserts each actor's pool is nil'd. **Visual proof:** no (data-integrity test). **PR:** PR-2.

#### BUG-003 — QueryTracer writes full system prompt (memories/goals/tasks), history, responses, tool I/O to a plaintext log for every floating-bar/PTT query
- **Severity:** Critical (privacy) · **Confidence:** High (that it happens); local-disk only (never uploaded — verified)
- **Area:** Diagnostics / privacy
- **User impact:** Any process/backup tool with read access to `~/Library/Logs/Omi/traces.jsonl` gets the user's private memories, goals, tasks, and conversations in cleartext.
- **Files/symbols:** `Services/QueryTracer.swift:254-285,444-474`; always-on call sites `FloatingControlBar/FloatingControlBarWindow.swift:2847-2850`, `FloatingControlBar/PushToTalkManager.swift:524` (`?? QueryTracer(...)` — no opt-in gate).
- **Root cause:** Diagnostics capture has no production gate and no redaction.
- **Fix:** Gate full request/response capture behind a debug default (keep timing spans in prod), or redact `system_prompt`/`messages` in release builds.
- **Tests:** Release-config test asserts no message/prompt bodies written. **Visual proof:** no. **PR:** PR-2 (privacy).

#### BUG-004 — Pending device-change reconfigure restarts the mic after `stopCapture()` → orphaned CoreAudio IOProc (mic stays hot)
- **Severity:** Critical (privacy + core recording) · **Confidence:** High
- **Area:** Audio capture
- **User impact:** After an input-device change, if the user stops recording within the ~0.3–3s reconfigure window, the mic HAL device is restarted with no consumer — the orange "mic in use" indicator stays on until app quit; `deinit` skips cleanup because `isCapturing` is already false.
- **Files/symbols:** `AudioCaptureService.swift:773-851` (`reconfigureAfterChange` — no `isCapturing` guard), `:344-379` (`stopCapture`), `:979-994` (`deinit`). Reachable via meeting-gated `reconcileCapture()` and `handleSilentMicFallback`.
- **Root cause:** Reconfigure continuation doesn't re-check session liveness after its delay.
- **Fix:** `guard isCapturing else { isReconfiguring = false; return }` at the top of `reconfigureAfterChange`/retry; bump a generation counter in `stopCapture`.
- **Tests:** Simulate config-change-then-stop; assert no `AudioDeviceStart` after stop. **Visual proof:** yes (mic indicator). **PR:** PR-3.

#### BUG-005 — Data races on turn audio buffers between the CoreAudio IOProc thread and the main actor
- **Severity:** Critical (memory-unsafety → crash) · **Confidence:** Medium-High
- **Area:** Realtime / PTT audio
- **User impact:** During a barge-in replacement or the omni pre-connect window, the audio thread appends to a Swift `Array`/`Data` while the main thread copies/clears it → undefined behavior (intermittent `malloc`/`EXC_BAD_ACCESS`) or lost first-words audio.
- **Files/symbols:** `FloatingControlBar/PushToTalkManager.swift:1393-1402` vs `1636-1646` (`omniPreconnectBuffer`, no lock); `FloatingControlBar/RealtimeHubController.swift:1111-1128` vs `922-937` (`pendingBargeInReplacement`); `RealtimeOmni/RealtimeOmniService.swift:176-192` vs `366-382` (`pendingAudio`). `AudioCaptureService.swift:638` invokes the chunk callback directly on the IOProc thread; the code comment admits `@MainActor` isn't enforced.
- **Root cause:** Only `batchAudioBuffer` is lock-protected; the other three shared buffers are touched from two threads with no synchronization.
- **Fix:** Hop the entire chunk-callback/`feedAudio` body to the main actor, or guard each buffer with the same lock discipline as `batchAudioBuffer`.
- **Tests:** TSan run over a barge-in + omni-preconnect sequence. **Visual proof:** no (TSan/crash log). **PR:** PR-3.

#### BUG-006 — Sign-out races with in-flight token refresh → refreshed credentials re-persisted to Keychain/UserDefaults after logout
- **Severity:** Critical (security) · **Confidence:** High
- **Area:** Auth / session
- **User impact:** On a shared Mac, "Sign Out" can leave a valid ID+refresh token on disk for the signed-out account; `getIdToken` even "backfills" `auth_userId` for the signed-out session.
- **Files/symbols:** `AuthService.swift:1883-1942` (`refreshIdToken`, no session-generation guard), `:1659-1684` (`saveTokens`), `:2049-2121` (`signOut`), `:1946-2013` (`getIdToken` backfill at 1956-1959).
- **Root cause:** No refresh single-flighting and no sign-out generation check; a refresh that resumes after `signOut()` unconditionally `saveTokens(...)`.
- **Fix:** Single in-flight refresh `Task` on the actor; bump `sessionGeneration` in `signOut()` and drop the refresh result if it changed.
- **Tests:** Concurrent refresh+signOut test asserts no tokens persist post-signout. **Visual proof:** no. **PR:** PR-2.

#### BUG-007 — Plaintext Firebase ID token + full local DB uploaded over HTTP to the agent VM (token also in URL query string)
- **Severity:** Critical (security/privacy) · **Confidence:** High (code); Medium (that the VM IP is publicly routable)
- **Area:** Agent VM networking
- **User impact:** On-path attacker (public Wi-Fi) captures a bearer token granting full Omi API access, plus the user's entire local database.
- **Files/symbols:** `AgentVMService.swift:137,232,241,246,283-291` (`http://<vmIP>:8080/upload?token=...`, `/auth?token=...`, `["firebaseToken": idToken]`), `AgentSyncService.swift:211,234,364`.
- **Root cause:** VM endpoint speaks plain HTTP; token duplicated into the query string.
- **Fix:** Route desktop→VM through the existing `agent-proxy` (wss, token-validated) or TLS on the VM; drop the query-string token.
- **Tests:** Assert no `http://` VM URLs and no token query params. **Visual proof:** no. **PR:** dedicated security PR (coordinate with backend on VM IP exposure).

### HIGH

#### BUG-008 — OAuth authorization code logged in full via NSLog
- Severity: High (security) · Confidence: High · `AuthService.swift:1327` (`handleOAuthCallback` logs `url.absoluteString` incl. `code=`/`state` to the unified system log). Fix: log a redacted form. PR-2.

#### BUG-009 — Case-sensitive `hasPrefix("Omi")` window matching breaks Rewind hotkey / dock reopen / window-width restore on the stable channel
- Severity: High · Confidence: High · `OmiApp.swift:803,1257`, `MainWindow/DesktopHomeView.swift:681`, `Onboarding/OnboardingChatView.swift:1540`, `Providers/ChatProvider.swift:3728`. Stable title is `"omi vX.Y"` (`UpdaterViewModel.swift:31`); a correct helper exists (`OmiApp.swift:712`). Impact: for the largest cohort the Rewind hotkey looks dead, dock reopen skips deminiaturize, saved window width never restores. Fix: route all matches through `isMainOmiWindow`. PR-4.

#### BUG-010 — Unexpected BLE disconnect never finishes characteristic streams or cancels pending continuations → consumers hang forever
- Severity: High · Confidence: High · `Bluetooth/Transports/BleTransport.swift:107-113` (`handleDisconnection`) vs `160-193` (`disconnect`). Impact: `StorageSyncService.performSync` hangs with `isSyncing==true` until app restart; `getAudioCodec`/`writeToStorage` awaiters block forever. Fix: extract the stream-finish + continuation-cancel block from `disconnect()` and call it from `handleDisconnection`. PR-3.

#### BUG-011 — AI-chat settings (Ask Mode, CLAUDE.md toggles, per-skill enable) are unreachable but still applied
- Severity: High · Confidence: High · `SettingsPage.swift:498-527`, `SettingsSidebar.swift:529-531` (hard redirect aiChat→advanced), toggles live only in dead `aiChatSection` (`SettingsContentView+FloatingBarAndChat.swift:214-239,309-417,420-574`). Impact: a user who enabled Ask Mode / disabled a skill is stuck with it; new users can never configure CLAUDE.md/Skills. Fix: move the 3 cards into `aiSetupSubsection`; delete the dead section. PR-4.

#### BUG-012 — `AgentRuntimeProcess.query()` ignores `sendJson` failure → chat stuck "thinking" forever
- Severity: High · Confidence: High · `Chat/AgentRuntimeProcess.swift:669`. If the node process dies right after `init`, `query` inserts its request then calls `sendJson` (returns false, discarded); the continuation is never resumed and `restart()` throws `.requestAlreadyActive` thereafter. Siblings check the result (`453-456`, `486-489`, `564-567`); `query` alone doesn't. Fix: check `sent`, resume throwing `.notRunning`. PR-6 (chat runtime).

#### BUG-013 — Rewind "Rebuild Index" recovery scans for `.hevc` chunks but the encoder writes `.mp4` → guaranteed no-op
- Severity: High · Confidence: High · `Rewind/Core/RewindStorage.swift:697-698`, `Rewind/Core/VideoChunkEncoder.swift:459-469`, `Rewind/Services/RewindIndexer.swift:703-750`. After corruption, "Rebuild Index" finds zero chunks (wrong extension, and `parseChunkTimestamp` expects an old 26-char name) → progress jumps to 100%, weeks of video never re-indexed. Fix: filter `mp4`, parse `chunk_HHmmss` + parent `yyyy-MM-dd`; add a regression test. PR-1.

#### BUG-014 — Fallback corruption recovery produces a DB that permanently fails migrations (Rewind bricked)
- Severity: High · Confidence: Medium-High · `Rewind/Core/RewindDatabase.swift:677-743,818-894,959-981`. `attemptDirectTableRecovery` writes a `screenshots` table with no `grdb_migrations`; next launch the migrator runs `createScreenshots` (no `ifNotExists`) → "table already exists" → every launch fails, Rewind dead until manual file deletion. Fix: run `migrate()` on the new file first, then bulk-insert. PR-1.

#### BUG-015 — Rewind (and Proactive/TaskChat) FTS search not escaped → common punctuation throws, search silently shows stale results
- Severity: High · Confidence: High · `Rewind/Core/RewindDatabase.swift:2879-2912` (`expandSearchQuery` interpolates raw `word*`); same class in `Rewind/Core/ProactiveStorage.swift:244`, `Rewind/Core/TaskChatMessageStorage.swift:352`. Queries with `' - . : " ( /` (e.g. `don't`, `e-mail`, `3:30pm`) → `fts5: syntax error`; caught and only logged, previous results left on screen. `ActionItemStorage`/`StagedTaskStorage` already sanitize correctly (`searchFTS`). Fix: reuse that sanitizer; surface errors. PR-5 (search).

#### BUG-016 — Chat `selectSession` has no request-generation guard → rapid switches show the wrong session's messages
- Severity: High · Confidence: High · `Providers/ChatProvider.swift:1717-1745` (also `loadDefaultChatMessages` 2656-2693). Slow A + fast B: A's late response overwrites `messages`/pagination while `currentSession` is B. Fix: `sessionLoadGeneration` counter. PR-6.

#### BUG-017 — `pollForNewMessages` merges fetched messages into whatever session is current after the await → cross-session bleed
- Severity: High · Confidence: High · `Providers/ChatProvider.swift:2757-2833`. Poll for A in flight; user selects B; A's messages appended into B's transcript (persisted). Fix: capture `polledSessionId` before the await, guard after. PR-6.

#### BUG-018 — Chat `loadMoreMessages` survives session switches → appends pages into the new session, corrupts pagination
- Severity: High (Medium user-visibility) · Confidence: High · `Providers/ChatProvider.swift:1748-1808`. Fix: capture session identity at entry, abort after each await if it changed. PR-6.

#### BUG-019 — Memories category filter with zero matches shows ALL memories instead of "No Results"
- Severity: High · Confidence: High · `MainWindow/Pages/MemoriesPage.swift:660-679` (`recomputeFilteredMemories` uses `!filteredFromDatabase.isEmpty` as filter-active proxy). Fix: branch on `!selectedTags.isEmpty`. PR-5.

#### BUG-020 — Tasks category/source/priority filter with zero matches shows the entire task list
- Severity: High · Confidence: High · `MainWindow/Pages/TasksPage.swift:1755-1784`. Same class as BUG-019; the in-memory fallback only re-applies status filters. Fix: explicit `hasLoadedFilteredFromDatabase` flag / Optional. PR-5.

#### BUG-021 — Tasks "Removed by AI / by me" list applies SQL LIMIT before the deleted filter → shows a subset or nothing
- Severity: High · Confidence: High · `Stores/TasksStore.swift:771-784,804-814`; `ActionItemStorage.getLocalActionItems(includeDeleted:true)` fetches the first 100 of *all* rows then filters `deleted==true` in memory. Fix: add a `deletedOnly` SQL predicate. PR-5.

#### BUG-022 — Onboarding file-scan step dead-ends with a permanent "Scanning your workspace…" on 0 files or scan error (no retry, no error UI)
- Severity: High · Confidence: High · `Onboarding/OnboardingFileScanStepView.swift:43-68`, `Onboarding/OnboardingPagedIntroCoordinator.swift:478-508`. Continue is gated on `scanSnapshot != nil` (nil when 0 files); `.failed` is terminal with no path back to `.idle`. Fix: gate Continue on `.complete`; render `.failed` with a Try-again that resets to `.idle`. PR-7 (onboarding).

#### BUG-023 — Focus page enters an infinite load/refresh loop for users with no focus history
- Severity: High · Confidence: High · `MainWindow/Pages/FocusPage.swift:72-87,100-117,203-205`. `isLoading` controls the structural identity of the view whose `.task` drives the load; empty result never satisfies the early-return → loading↔content flicker, continuous SQLite queries, `.focusPageDidLoad` spammed. Fix: `hasLoadedOnce` flag or overlay the spinner instead of replacing content. PR-8 (page state).

#### BUG-024 — "Try with Apps" filter compares an app result against itself (`$0` shadowing) → section broken whenever any app result exists
- Severity: High (feature broken) · Confidence: High · `MainWindow/Pages/ConversationDetailView.swift:950-953`: `!displayConversation.appsResults.contains(where: { $0.appId == $0.id })` — inner `$0` shadows the outer app. Fix: name the parameters. PR-8.

#### BUG-025 — Conversation search has no stale-request guard → out-of-order responses show wrong results
- Severity: High (Medium impact) · Confidence: High · `MainWindow/Pages/ConversationsPage.swift:436-466`. Fix: generation counter / compare `query`. PR-5.

#### BUG-026 — Task search-as-you-type has no request-generation guard → stale results overwrite newer
- Severity: Medium-High · Confidence: High · `MainWindow/Pages/TasksPage.swift:467-476,1714-1742`. Fix: cancel prior `searchTask` + equality guard. PR-5.

#### BUG-027 — Detail-view conversation delete skips the local SQLite soft-delete → deleted conversation resurrects from cache
- Severity: High · Confidence: High · `MainWindow/Pages/ConversationDetailView.swift:553-569` (vs the row view `ConversationRowView.swift:165-187` which soft-deletes with an explanatory comment). Same asymmetry for `updateTitle()`. Fix: call `TranscriptionStorage.deleteByBackendId` / `updateTitleByBackendId` in the detail view. PR-8.

#### BUG-028 — Editing a conversation title in the detail view never updates the visible header
- Severity: Medium-High · Confidence: High · `ConversationDetailView.swift:540-551` (`displayConversation = loadedConversation ?? conversation`; neither mutated on save). Fix: mutate `loadedConversation` on success + sync local storage; surface failures. PR-8.

#### BUG-029 — Live notes silently stop generating after ~500 words (~10 notes) per session
- Severity: High · Confidence: High · `LiveNotes/LiveNotesMonitor.swift:243-252,317`. `lastProcessedSegmentOrder` is an absolute index into a buffer trimmed at the front and never rebased → `wordsSinceLastNote` pins to 0 after 500 words. Fix: rebase the watermark on trim, or use a simple counter reset after each note. PR-9 (live notes).

#### BUG-030 — Chord (key+modifier) PTT shortcut: key-up missed if modifiers release first → stuck recording, system audio stays muted
- Severity: High · Confidence: High · `FloatingControlBar/ShortcutSettings.swift:131-134` (`matchesKeyUp` requires exact modifier equality), `FloatingControlBar/PushToTalkManager.swift:183-220`. Releasing ⌘⇧Space naturally drops modifiers before the Space keyUp → `handleShortcutUp` never fires → PTT stuck `.listening`, `pttMuteSystemAudio` keeps music muted. Fix: `matchesKeyUp` on keyCode alone. PR-9.

### MEDIUM (grouped by area; each is High/Medium code-inspection confidence)

**Auth / permissions**
- BUG-031 — `signOut()` aborts all local cleanup if the Firebase SDK `signOut()` throws (keychainError), and every caller uses `try?` → "Sign Out" silently no-ops while analytics/Sentry already reset. `AuthService.swift:2049-2065`, `OmiApp.swift:1090-1094`. Fix: wrap SDK call in its own do/catch, make cleanup unconditional.
- BUG-032 — Auth-state listener blindly trusts the SDK user and overwrites `auth_userId` → can flip the app to a stale account when SDK/REST sessions diverge. `AuthService.swift:650-686`.
- BUG-033 — Token migration deletes the only copy of legacy tokens when the Keychain write fails; transient Keychain read failure is negatively cached for the whole session. `AuthService.swift:1760-1789,371-377`.
- BUG-034 — Notification permission `.notDetermined` misclassified as "Denied" after onboarding → recovery UI dead-ends in System Settings, hides the only prompt path. `AppState/AppState+TrialPaywall.swift:204-209`, `PermissionsPage.swift:658-661,737-814`.

**Audio / BLE / WAL**
- BUG-035 — Stale auth task in `startOmniTranscription` can overwrite a newer turn's omni service → orphaned live websocket + doubled transcripts. `PushToTalkManager.swift:1616-1655`.
- BUG-036 — `URLSession` delegate retain cycle leaks a session per OpenAI hub session and per omni PTT turn. `RealtimeHubSession.swift:85`, `RealtimeOmniService.swift:47` (never `invalidateAndCancel`).
- BUG-037 — `getCharacteristicStream` caches a single-consumer `AsyncThrowingStream` → reuse returns a dead stream (WiFi sync breaks, 2nd SD sync hangs). `BleTransport.swift:216-244`, `OmiDeviceConnection.swift:313-440`.
- BUG-038 — `BleAudioProcessor.framesBuffer` grows unbounded for the whole BLE session (never read). `Audio/BleAudioProcessor.swift:65,283-296`.
- BUG-039 — Checked-continuation double-resume races in Limitless/Plaud/Bee device command+timeout paths (`fatalError` risk). `LimitlessDeviceConnection.swift:860-870,618-622`, `PlaudDeviceConnection.swift:135-149`, `BeeDeviceConnection.swift:163-172`.
- BUG-040 — `SystemAudioCaptureService` declares a 2-channel converter input but fills only channel 0 → system audio at ~half amplitude (or noise) to STT. `SystemAudioCaptureService.swift:183-192,318-343,363`.
- BUG-041 — `StorageSyncService` can end with `isSyncing` stuck true (stream finishes without EOT), and transfer speed is always 0 (elapsed computed against the just-updated timestamp). `WAL/StorageSyncService.swift:173-225,327-363`.
- BUG-042 — WAL duplicate-ID overwrite (1s id resolution), write-failure drops audio, stub cloud-sync marks `.synced` then deletes. `WAL/WALService.swift:253-330,423-512`. (High if WAL is ever relied on for recovery; currently fed only by dormant paths.)
- BUG-043 — `AudioSourceManager.switchSource` can never restart streaming (`onStereoAudio` nil'd before the restart check) → BLE-disconnect fallback silently stops audio. `Audio/AudioSourceManager.swift:156-198,404-414` (dormant path).
- BUG-044 — `DeviceProvider` never assigns `connection.delegate` → fall-detection notification can never fire. `Providers/DeviceProvider.swift:214-277,681-708`.
- BUG-045 — Friend Pendant LC3 decoder returns silence but reports the codec as supported → silent recordings, empty transcripts, no error. `Audio/AudioCodecDecoder.swift:506-577`.

**Chat / agent runtime**
- BUG-046 — stdout chunks dispatched as unordered `Task`s → JSON-line reassembly can interleave and drop the terminal `result`. `Chat/AgentRuntimeProcess.swift:1027-1067`.
- BUG-047 — Actor-reentrant `startProcess` can spawn two node processes; the first is orphaned and leaks (`--max-old-space-size=256`). `Chat/AgentRuntimeProcess.swift:673-824`.
- BUG-048 — `turnRecordedHandlers` grows forever across bridge restarts → `turn_recorded` applied N times → duplicate chat messages persisted. `Chat/AgentRuntimeProcess.swift:392-394`, `ChatProvider.swift:1335`.
- BUG-049 — Permanent control clients never unregistered → `switchBridgeMode`'s "stop and wait" reuses the old process with stale env (BYOK keys, tokens). `Chat/AgentControlService.swift:32-37`, `DesktopCoordinatorService.swift:561-568`, `AgentRuntimeProcess.swift:217-240`.
- BUG-050 — Attachment-only chat send is a silent no-op (send button lit, `sendMessage("")` returns nil). `ChatInputView.swift:180-202`, `ChatProvider.swift:3311-3312`.
- BUG-051 — Session title generated from the wrong session's messages after a mid-turn switch (reads live `messages`, not the captured turn). `ChatProvider.swift:3963-3966,4195-4211`.
- BUG-052 — ChatLab prompt history: hardcoded dev path `/Users/nik/projects/omi` + stale paths → dead feature; git subprocess blocks the main thread and can deadlock on a >64KB pipe. `MainWindow/Pages/ChatLabView.swift:147-158,222-238`.
- BUG-053 — Shared single-slot streaming buffer can splice one message's text into another when a stale stream overlaps a new turn. `ChatProvider.swift:4260-4320`.

**Networking / API**
- BUG-054 — PATCH/DELETE + hand-rolled endpoints lack the 401 refresh-and-retry that GET/POST have; several swallow error bodies and report status 0. `APIClient.swift:2288-2304,304-329` + ~10 manual endpoints. Impact: star/rename/move/complete-goal/rate silently fail on a stale token while reads work.
- BUG-055 — Unencoded user input interpolated into URL query strings (`&`,`#`,`+`) → persona username check validates the wrong string. `APIClient.swift:4196-4198`, `PersonaPage.swift:592-608`.
- BUG-056 — Notification "repair" fallback opens System Settings on a fixed 4–5s timer while the OS prompt may still be on screen. `AppState/AppState+Permissions.swift:46-104`.
- BUG-057 — `NotificationService.notificationMetadata` grows unboundedly (removed only on interaction). `ProactiveAssistants/Services/NotificationService.swift:97,358-359`.
- BUG-058 — `AgentVMService.uploadDatabase` blocks a cooperative thread for the whole gzip; concurrent re-upload races on one fixed temp file → truncated DB on the VM. `AgentVMService.swift:195-247`.
- BUG-059 — Snooze gate suppresses *functional* notifications (support replies, screen-recording repair) and pre-sets the once-per-episode flag before the early-return → repair prompt never re-sent. `NotificationService.swift:271-276`.

**Settings / persistence**
- BUG-060 — Assistant prompt-version migrations defeated by server settings sync (stale default prompt resurrected forever). `FocusAssistantSettings.swift:53-73`, `InsightAssistantSettings.swift:88-107`, `SettingsSyncManager.swift:46-160`.
- BUG-061 — `RewindSettings` shared store read from background actors while mutated on the main thread — unsynchronized data race. `Rewind/Core/RewindModels.swift:342-443`, `VideoChunkEncoder.swift:19-22`, `TaskAssistant.swift:260`.
- BUG-062 — "Single Language (Better Accuracy)" silently reverts to Auto-Detect for the 10 most common languages. `SettingsContentView+Transcription.swift:102-118`.
- BUG-063 — Clearing the last entry of Task-assistant allow-lists silently resurrects the entire default list (empty == "never customized"). `TaskAssistantSettings.swift:364-390`.
- BUG-064 — `KeyboardShortcut` Codable has no schema tolerance → any added field silently resets users' custom shortcuts. `FloatingControlBar/ShortcutSettings.swift:12-36,582-596`.
- BUG-065 — Notifications frequency UI default (Balanced/on) disagrees with the effective local default (Off) when backend load fails. `SettingsPage.swift:211-212`, `NotificationService.swift:93,396-430`.

**Tasks / dashboard**
- BUG-066 — Task pagination mixes local-cache row counts with API dataset offsets → skipped/duplicated tasks on "Load more." `Stores/TasksStore.swift:616-623,1059-1089`.
- BUG-067 — Done-tab cache pagination off-by-N after completing/uncompleting (offset not adjusted on optimistic insert/remove). `Stores/TasksStore.swift:1216-1218,1104-1117`.
- BUG-068 — `toggleTask` failure revert (and delete paths) leave Dashboard task slices showing the un-reverted state. `Stores/TasksStore.swift:1275-1290`.
- BUG-069 — Undo-delete (`restoreTask`) re-creates the task with only description/dueAt/priority → loses source/tags/recurrence/completed and can duplicate the row. `Stores/TasksStore.swift:1432-1461`.
- BUG-070 — Goal "current" value silently dropped on create (edit path works). `DashboardPage.swift:130-144,1390-1398`.
- BUG-071 — Goal progress drag: optimistic update never rolled back on API failure → silent snap-back on next sync. `DashboardPage.swift:146-177`.
- BUG-072 — Failed goal delete silently resurrects the goal on next sync (no pending-delete marker). `DashboardPage.swift:199-209`, `GoalStorage.swift:88-98`.
- BUG-073 — "Generate AI Goal" failure is completely silent (spinner stops, nothing happens). `Components/GoalsWidget.swift:134-140`, `GoalGenerationService.swift:83-128`.
- BUG-074 — Goal linked-tasks capped at the first 100 action items + N×100 fetch per row. `Components/GoalsWidget.swift:347-361`.

**Apps / memories / conversations**
- BUG-075 — AppDetailSheet "Open" button silently uninstalls installed non-external apps. `MainWindow/Pages/AppsPage.swift:2580-2616`, `AppProvider.swift:362-364`.
- BUG-076 — AppDetailSheet toggle uses the stale captured `app` struct → trash re-enables instead of uninstalling. `AppsPage.swift:2489-2506,2586-2631`.
- BUG-077 — Memories stale-scope guards leave `isSearching`/`isLoadingFiltered` stuck true → permanent spinner. `MemoriesPage.swift:619-651,715-752`.
- BUG-078 — MemoryDetailSheet inline edit reverts to old content after Save (stale `selectedMemory`). `MemoriesPage.swift:1240-1255`.
- BUG-079 — `createMemory`/`saveEditedMemory` swallow API errors; Add allows duplicate double-submit. `MemoriesPage.swift:1128-1139,1252-1254`.
- BUG-080 — Toggling "This device" while a load is in flight is silently dropped (filter shows active, list never updates). `MemoriesPage.swift:140-147,779-786`.
- BUG-081 — AppsPage never surfaces `AppProvider.errorMessage`; failed search shows stale results under the new query's title. `AppsPage.swift:132-364`, `AppProvider.swift:281-285`.
- BUG-082 — Detail view shows the previous conversation's data when `selectedConversation` changes without dismissal (automation deep-link; non-keyed `.task`). `ConversationDetailView.swift:31,174-236`.
- BUG-083 — Conversations list hard-capped at 50 with no pagination. `AppState/AppState+DataLoading.swift:110-119`, `ConversationListView.swift`.
- BUG-084 — Multi-select/merge UI is unreachable dead code, and its "Select All" operates on the wrong collection in search results. `ConversationsPage.swift:59,608-733`.
- BUG-085 — Tier-gating redirect logic contradicts the tier definitions (redirect target is itself locked; unlocked pages get bounced). `MainWindow/DesktopHomeView.swift:533-554`, `SidebarView.swift:54-64,330-340`.
- BUG-086 — Memory auto-refresh corrupts the device-scoped pagination cursor (`rawBackendOffset`). `MemoriesPage.swift:528-553`.

**Lifecycle / windows / onboarding**
- BUG-087 — Menu-bar "Reset Onboarding…" builds a throwaway `AppState()` that hijacks `AppState.current`; if a Sparkle update is mid-flight the app keeps running in a half-reset state. `OmiApp.swift:1082`, `AppState.swift:383-425`.
- BUG-088 — Two long-lived `AppState` instances → duplicated lifecycle observers and a launch-time race over `AppState.current`. `OmiApp.swift:87,522-525`, `DesktopHomeView.swift:21`.
- BUG-089 — Quit-time transcription cleanup never runs (work wrapped in `Task { @MainActor }` while `applicationWillTerminate` blocks main on a semaphore) → session left "open," recovered as crashed. `AppState.swift:513-537`, `OmiApp.swift:1316-1323`.
- BUG-090 — `FeedbackWindow` keeps a strong static `NSWindow` ref with default `isReleasedWhenClosed = true` → over-release/UAF crash on reopen. `FeedbackView.swift:8-33`.
- BUG-091 — Menu-bar "Open omi" can foreground the floating panel (382×≥250) or the Report-Issue window instead of the main window and skip opening it. `OmiApp.swift:1047-1073`.
- BUG-092 — ChatGPT/Claude memory-log import state leaks across accounts/resets → second user permanently blocked from importing. `OnboardingPagedIntroCoordinator.swift:121-125`, `AuthService.swift:2103-2112`.
- BUG-093 — Onboarding goal step: `goalSaved=false` reset + missing in-flight guard allows duplicate goal creation. `OnboardingGoalStepView.swift:112-123`, coordinator `1173-1230`.
- BUG-094 — DataSources onboarding step gates Continue on an unbounded background pipeline with no timeout (spinner forever on a wedged bridge). `OnboardingDataSourcesStepView.swift:39-55`, coordinator `679-964`.

### LOW (cosmetic / minor edge cases)
- BUG-095 — `@State` mutated off the main actor after `await` in `triggerGoalGeneration`. `GoalsWidget.swift:134-140`.
- BUG-096 — Citation tap: modal spinner with no cancel/timeout, error swallowed. `DashboardPage.swift:408-423,1248-1270`.
- BUG-097 — `GoalsHistoryPage` unreachable (`showingHistory` never set true). `GoalsWidget.swift:15,128-131`.
- BUG-098 — `DashboardViewModel.isLoading`/`error` are dead — dashboard has no loading/error states. `DashboardPage.swift:13-16,49-96`.
- BUG-099 — Locale-dependent number parsing silently corrupts goal values (`Double("2,5")==nil`→fallback). `GoalsWidget.swift:676-680`.
- BUG-100 — Persona creation failure gives zero feedback inside the sheet; `checkUsername` stale-response race. `PersonaPage.swift:536-551,592-608`.
- BUG-101 — Silent failures + unused `isDeleting` on destructive detail-view actions; reprocess never refetches. `ConversationDetailView.swift:553-569,988-1007`.
- BUG-102 — Search shows "No conversations found" during the debounce window before any search runs. `ConversationsPage.swift:296-299`.
- BUG-103 — Conversation list groups by `createdAt` but rows display `startedAt` → cross-midnight items under the wrong day header. `ConversationListView.swift:56-67`, `ConversationRowView.swift:33-35`.
- BUG-104 — Rating failure reverts to `nil` instead of the previous rating, then blocks re-submitting the same rating. `ChatProvider.swift:4690-4712`, `ChatPage.swift:813-817`.
- BUG-105 — Toggling the "Starred" filter while in Synced Chat silently switches the user into a session. `ChatProvider.swift:1609-1650`.
- BUG-106 — Stale `isSending` at submit time silently discards the typed message. `ChatInputView.swift:193-202`.
- BUG-107 — Chat prepend-position restore is dead (guard `scrollMode != .freeScrolling` always bails in the only flow that matters) + false "new activity" pulse. `ChatMessagesView.swift:290-308,234-240`.
- BUG-108 — "Load earlier messages" misdetected as a conversation switch → scroll yanked to bottom. `ChatMessagesView.swift:184-201`.
- BUG-109 — Chat `selectSession` failure renders as an empty "welcome" chat with no error/retry. `ChatProvider.swift:1738-1742`.
- BUG-110 — Live notes ingest duplicated words (end-time cursor re-reads whole upserted segments). `LiveNotesMonitor.swift:220-241`.
- BUG-111 — Modifier-only PTT: pressing a second modifier mid-hold finalizes early, then starts a phantom second turn. `ShortcutSettings.swift:136-144`, `PushToTalkManager.swift:188-219`.
- BUG-112 — Mic permission granted mid-turn never starts capture (grant only logs). `PushToTalkManager.swift:1140-1153`.
- BUG-113 — Full-screen capture on the main thread at PTT key-down adds latency. `PushToTalkManager.swift:336`.
- BUG-114 — `SpatialOverlayScreen.id = localizedName` → identical external monitors collide. `SpatialOverlay/SpatialOverlayGeometry.swift:6`.
- BUG-115 — `NSAppleScript` created/executed on background threads (main-thread-only API). `AppState/AppState+Permissions.swift:116-150,389-405`.
- BUG-116 — `KernelTurnProjection` dedup pruning keeps an arbitrary half of an unordered `Set`. `Chat/KernelTurnProjection.swift:33-39`.
- BUG-117 — `expectedCancelledRequests` / `findNodeBinary` actor-blocking + leak nits. `Chat/AgentRuntimeProcess.swift:190,1514-1527`.
- BUG-118 — `cleanupFailedStart` can tear down a newer process's pipes across the ~1s kill-loop await. `Chat/AgentRuntimeProcess.swift:932-953`.
- BUG-119 — Incremental file-index rescan deletes the whole index for any folder that becomes unreadable (TCC revoked / iCloud offline). `FileIndexing/FileIndexerService.swift:198-257,415-439`.
- BUG-120 — Onboarding file indexing marks itself complete when the DB failed to init → permanently disables indexing. `FileIndexing/FileIndexerService.swift:102-109,171-177`.
- BUG-121 — Orphaned Rewind video chunks leak permanently if cleanup dies between DB delete and file delete. `RewindIndexer.swift:503-516`.
- BUG-122 — `VideoChunkEncoder.addFrame` doesn't roll back offset/timestamp on write failure → later frames in the chunk map to the wrong video frame. `VideoChunkEncoder.swift:206-267`.
- BUG-123 — `frameRate` re-read per frame → battery→AC transition mid-chunk yields non-monotonic PTS. `VideoChunkEncoder.swift:19-22,378`.
- BUG-124 — Onboarding progress bar shows 100% for steps 14–18 (`introStepCount`=13). `OnboardingView.swift:385-453`, `OnboardingFlow.swift:25`.
- BUG-125 — `--export-onboarding` clobbers the real user's `@AppStorage` onboarding state. `ViewExporter.swift:175-187`.
- BUG-126 — Lazy-dev-permissions builds start screen monitoring anyway via the completed-branch `onAppear`. `OnboardingView.swift:44-58`.
- BUG-127 — Analytics reads settings with wrong fallback defaults (`chat_bridge_mode`→removed `agentSDK`; `rewind_capture_interval`→1.0 vs actual 3.0). `AnalyticsManager.swift:829-833`.
- BUG-128 — `rewindCaptureInterval` default mismatch (3.0 vs 1.0) + duplicate dead Rewind settings UI writing keys the singleton never re-reads. `RewindModels.swift:396`, `RewindOnlyView.swift:187`.
- BUG-129 — `omiAICumulativeCostUsd` global, per-machine, never cleared on sign-out → "$50 upgrade" nudge can misfire for the next account. `ChatProvider.swift:1013`.
- BUG-130 — Dead/duplicate paired-BLE-device persistence (`pairedBtDevice` vs `pairedDeviceId/Name/Type`). `Bluetooth/BtDevice.swift:253-274`.
- BUG-131 — Auth-failure chat auto-retry ignores a Stop pressed during token refresh; retry uses untracked handlers. `Chat/AgentBridge.swift:385-433`.
- BUG-132 — `BleTransport` leaks two block-based NotificationCenter observers per instance (accumulate on reconnect storms). `BleTransport.swift:53-120`.
- BUG-133 — Limitless `rawDataBuffer`/`fragmentBuffer` accumulate unparseable packets/fragments forever. `LimitlessDeviceConnection.swift:140,155-167`.
- BUG-134 — Dead onboarding views (`OnboardingChatView` 2166 lines, `OnboardingNotificationStepView`) with latent Continue-blocking bugs if revived. `Onboarding/OnboardingChatView.swift`.

---

## Potential Edge Cases Needing More Verification
- **Device-protocol wire formats** — WifiSync 440-byte block alignment (`WifiSyncService.parseFrames:352-397`), Limitless protobuf field numbers, Bee ADTS multi-frame packets. Need device captures.
- **Firebase SDK internals** — BUG-032's worst case depends on `currentUser` behavior after a failed `signIn(withCustomToken:)` + thrown `signOut()`.
- **Backend echo semantics** — BUG-060 assumes `AssistantSettingsResponse` returns the pushed `analysisPrompt` verbatim (Python backend not read).
- **`AppStorage` caching** — BUG-011's "still applied" and cost accounting assume live UserDefaults reads per access.
- **Node bridge (out of Swift scope)** — whether `turn_recorded` always carries `idempotencyKey` (governs BUG-048 visible duplicates), stdin-EOF exit (BUG-047 orphan lifetime), guaranteed `cancelled` result after `interrupt` (BUG-117 leak rate).
- **PTT re-init after onboarding** — `OnboardingVoiceShortcutStepView.onAppear` calls `PushToTalkManager.cleanup()`; where PTT is re-initialized for normal use is unverified.
- **App-quit node teardown** — no explicit kill of the node subprocess on app termination found in the audited files (`stopProcess` only on last unregister, which per BUG-049 may never happen).

## False Positives / Ruled Out
- Two remaining UI force-unwraps are guarded: `TasksPage.swift:3719` (`displayTasks.last!` inside the last-row `onAppear`), `MemoriesPage.swift:1683` (`selectedTags.first!` guarded by `count == 1`).
- `TaskChatPanel.swift:89` `task!.chatContext` is nil-guarded in the same expression.
- All 1,105 `forKey:` sites use `UserDefaults.standard` — no suite divergence; high-fanout keys (`auth_userId`, `hasCompletedOnboarding`, etc.) verified string-consistent.
- `chatBridgeMode` "agentSDK" legacy value is correctly migrated in `ChatProvider.init`; `update_channel` legacy values normalized by all readers; BYOK keys consistent onboarding↔Settings; `shortcut_selectedModel` sanitized against available models.
- `LocalAgentAPIServer` — loopback bind, constant-time token compare, size caps: no defect. `screenAnalysisEnabled`/`transcriptionEnabled` routed consistently. PTT event monitors installed/removed symmetrically; `GlobalShortcutManager` unregisters before re-register (no Carbon hotkey accumulation); no `NSScreen.main!` force unwraps in scope. `DashboardTaskRefreshService`/`Policy` pagination/day-window math correct.

---

## Recommended PR Plan

| PR | Title | Bugs | Why grouped | Risk | Files | Verification | Visual proof |
|---|---|---|---|---|---|---|---|
| PR-1 | Rewind data-loss & recovery | 001, 013, 014, 121 | All Rewind DB/file lifecycle; highest-severity data loss | High | RewindDatabase, RewindStorage, RewindIndexer, VideoChunkEncoder | Unit tests on delete/rebuild/recover; run Rewind end-to-end | Yes |
| PR-2 | Account isolation & auth security | 002, 003, 006, 008, 129 | Sign-out/account-switch data & credential leakage | High | AuthService, 5 storage actors, QueryTracer, ChatProvider | Sign-out/switch integration test; on-disk inspection | No |
| PR-3 | Recording safety | 004, 005, 010, 040, 041 | Mic-hot, audio-thread races, BLE/sync hangs | High | AudioCaptureService, SystemAudioCaptureService, PushToTalkManager, RealtimeHubController, BleTransport, StorageSyncService | TSan; mic-indicator check; BLE disconnect drill | Yes (mic) |
| PR-4 | Settings & window reachability | 009, 011, 085, 091 | Users can't reach/return-from features; window matching | Medium | SettingsPage/Sidebar/Sections, OmiApp, DesktopHomeView, SidebarView | Manual nav on stable-channel build | Yes |
| PR-5 | Filters, search & pagination correctness | 015, 019, 020, 021, 025, 026, 066, 067 | Empty-filter + stale-search + FTS + pagination classes | Medium | MemoriesPage, TasksPage, ConversationsPage, TasksStore, RewindDatabase, ProactiveStorage | Unit tests for zero-match + out-of-order search | Yes |
| PR-6 | Chat session integrity | 012, 016, 017, 018, 046-053 | Cross-session bleed, stuck turns, process leaks | High | ChatProvider, AgentRuntimeProcess, AgentBridge, AgentControlService | Rapid session-switch + bridge-restart drills | Yes |
| PR-7 | Onboarding dead-ends | 022, 092, 093, 094, 124 | First-run blockers + per-account leakage | Medium | Onboarding/* | Fresh-install + denied-permission runs | Yes |
| PR-8 | Conversation/page state | 023, 024, 027, 028, 082, 083, 084 | Detail-view persistence + navigation | Medium | ConversationDetailView, ConversationsPage, FocusPage | Manual per-flow | Yes |
| PR-9 | Live notes & PTT input | 029, 030, 110, 111 | Live-notes watermark + PTT key-up | Medium | LiveNotesMonitor, PushToTalkManager, ShortcutSettings | Long-session + chord-release drills | Yes |
| PR-10 | Cleanups (Low) | remaining Low bugs | Low-risk, independently revertable | Low | various | Spot checks | Per item |

---

## Full Verification Checklist (work each bug through this)
1. **Build verification** — `cd desktop/macos && OMI_APP_NAME="omi-audit-fix" ./run.sh` (named bundle); for signature/type changes run a clean release build `rm -rf .build && xcrun swift build -c release --triple arm64-apple-macosx`.
2. **Manual reproduction** — reproduce the "Actual" behavior on a real Mac *before* fixing (this audit could not).
3. **Screenshot/video proof** — capture for every bug marked "Visual proof: Yes" (mic indicator, file tree, wrong list, stuck spinner).
4. **Fix validation** — exercise the real user-facing path (`omi-ctl`/agent-swift), not just compile.
5. **Regression validation** — add the regression test that would have caught it (mandatory per AGENTS.md Definition of Done); confirm it runs in the component suite.
6. **PR readiness** — pre-commit hook installed; changelog fragment for user-visible desktop changes (`desktop/macos/changelog/unreleased/*.json`); docs updated if behavior/setup changed; verification evidence in the PR body.

## Final Audit Stop Condition
- **Loops completed:** 2 (11-way area audit + whole-tree cross-cutting sweeps/verification).
- **Did the final loop find zero new bugs?** Yes — Loop 2 produced no net-new credible defect; it only widened and verified the classes from Loop 1 (and confirmed 6 top findings line-by-line against source).
- **Most likely to still hide bugs (needs runtime + device):** BLE device-protocol wire formats; the Node agent bridge (TypeScript, out of Swift scope); SwiftUI state-desync in the large partially-read views (`FloatingControlBarView`, `AgentPill`, `TasksPage` 5000-5798); Firebase SDK edge behavior; backend echo semantics for settings sync.
- **What to audit next:** (1) reproduce and fix the Critical set on a real Mac with runtime proof; (2) a device-in-hand BLE protocol pass; (3) a TSan build to confirm the data-race findings (BUG-005, BUG-061, BUG-039); (4) audit the Node bridge repo for the `idempotencyKey`/EOF/`cancelled` assumptions that gate BUG-047/048/117.
