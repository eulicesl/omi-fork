# Proactive Task Execution — Reliability Sprints

Plan to take the **Execute** button on a proactive task notification from a ~55% reliability baseline to ≥ 80%. Source for the failure-mode analysis and per-change reasoning: [`TASK_EXEC_RELIABILITY_REVIEW.md`](./TASK_EXEC_RELIABILITY_REVIEW.md).

Branch: `feature/macos-task-exec-reliability` (already cut).

| Sprint | Items | Effort | Expected uplift | Risk |
|---|---|---|---|---|
| 1 | P1 + P4 + P5 + P6 | ½–1 day | ~+12 pp | Low (prompt/wiring) |
| 2 | P2 + P3 | 1–2 days | ~+10 pp | Medium (control-flow) |
| 3 | P7 + P8 + P9 | 3–4 days | ~+14 pp | Medium-High |
| 4 | Eval harness | 2–3 days | Measurement only | Low |

Total budgeted uplift if everything lands: **~+36 pp → ceiling ~91%**. The S-tier (Sprints 1 + 2 = 4 changes) is sufficient on its own to cross 80%; Sprint 3 raises the ceiling and reduces variance; Sprint 4 is how we *prove* we hit 80%.

Each sprint ends with a self-test pass against a named bundle (`OMI_APP_NAME=omi-execute-rel-s1 ./run.sh`) and a hand-graded mini-set of ~6 tasks before opening a PR. Sprint 4's full eval harness replaces the hand-grading after it lands.

---

## Sprint 1 — Low-risk wins (½–1 day)

Goal: stop dropping context and stop fighting our own system prompt. Pure wiring + prompt changes.

### P1 · Plumb notification context into the Execute prompt

**Problem.** `ProactiveTaskExecute.buildQuery` only sees `title` + `message`. The richer `FloatingBarNotificationContext` built in `TaskPromotionService.buildNotificationContext` (`TaskPromotionService.swift:139`) — `sourceApp`, `windowTitle`, `contextSummary`, `currentActivity`, `reasoning`, `detail` — is dropped on the floor at the Execute click site.

**Change.**

1. `ProactiveTaskExecute.buildQuery(title:message:)` → `buildQuery(title:message:context:)`. New context arg is `FloatingBarNotificationContext?`. When present, prepend a `# TASK CONTEXT` block before the imperative restatement.
2. `FloatingControlBarView.swift:225` — pass `notification.context` to the new arg.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/ProactiveTaskExecute.swift`, `desktop/Desktop/Sources/FloatingControlBar/FloatingControlBarView.swift`.

### P4 · Drop the floating-bar prefix on Execute

**Problem.** `AgentPillsManager.spawn` always prepends `ChatProvider.floatingBarSystemPromptPrefix` (`AgentPill.swift:386`). That prefix says "1-2 sentences, no follow-ups" — directly contradicting Execute's "Use as many tool calls as you need." The suffix overrides on paper; in practice models latch onto the first authoritative-sounding block.

**Change.** Extend `AgentPillsManager.spawn` with `systemPromptPrefix: String? = ChatProvider.floatingBarSystemPromptPrefix`. The Execute call site (`FloatingControlBarView.swift:229`) passes `systemPromptPrefix: nil`. All other call sites keep the default.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/AgentPill.swift`, `desktop/Desktop/Sources/FloatingControlBar/FloatingControlBarView.swift`.

### P5 · Pin Execute to Opus

**Problem.** `FloatingControlBarView.swift:222–224` reads `ShortcutSettings.selectedModel` or falls back to Sonnet. Execute is the highest-tool-count agentic task surface in the app; Opus's planning quality is exactly what we want to spend money on here.

**Change.**

1. New constant `ProactiveTaskExecute.preferredModel = "claude-opus-4-6"`.
2. Read `UserDefaults.standard.string(forKey: "OmiExecuteModel")` first so power users can override.
3. Execute click site uses that, ignoring `ShortcutSettings.selectedModel` (which still controls inline-bar answers).

**Files.** `desktop/Desktop/Sources/FloatingControlBar/ProactiveTaskExecute.swift`, `desktop/Desktop/Sources/FloatingControlBar/FloatingControlBarView.swift`.

### P6 · Dedup Execute clicks by notification ID

**Problem.** Two clicks within a few seconds spawn two parallel pills racing to send the same message / create the same event. `AgentPillsManager.spawn` has no per-notification dedup; the only guard is `maxPills = 8`.

**Change.**

1. Add a `Set<UUID>` of recently-fired notification IDs to `AgentPillsManager`, with a 60 s TTL (`DispatchQueue.main.asyncAfter` removal).
2. New API: `AgentPillsManager.spawnForNotification(notificationId:query:model:systemPromptSuffix:)`. Returns `nil` (and logs) when the notification ID is already in the set.
3. Execute click site uses the new API; `FloatingControlBarManager.dismissCurrentNotification()` still runs on the rejected click so the UI doesn't get stuck.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/AgentPill.swift`, `desktop/Desktop/Sources/FloatingControlBar/FloatingControlBarView.swift`.

### Sprint 1 acceptance

- `xcrun swift build -c debug --package-path Desktop` clean.
- Self-test against `OMI_APP_NAME=omi-execute-rel-s1 ./run.sh`: trigger a task notification, click Execute, confirm via `/private/tmp/omi-dev.log` that the prompt now includes the TASK CONTEXT block, the model is `claude-opus-4-6`, and the floating prefix is absent.
- Double-click Execute on the same notification — second click logs "duplicate execute ignored" and no second pill appears.
- Hand-graded 6-task mini-set: ≥ 5/6 pass.

---

## Sprint 2 — Verification gate + retry (1–2 days)

Goal: turn the model's "I did it" claim into something we can falsify, and retry the falsifiable failures.

### P2 · Tool-usage gate before "done"

**Problem.** `AgentPillsManager.complete` (`AgentPill.swift:464`) flips the pill to `.done` whenever the bridge returns text — even if zero write/send tools fired. Models routinely write a confident "Sent the summary to Daniel on Telegram" sentence with no Telegram-touching tool in the transcript.

**Change.**

1. New `enum AgentPill.ActionClass { case actionable, research }`. Derive from the first verb of the query (`send|reply|create|schedule|draft|post|email|message|text|book|add` → `.actionable`).
2. Define `AgentPill.writeToolSet`: `osascript`, `shell`, `bash`, `playwright_*`, `browser_*`, `write_file`, `apple_notes_add`, `apple_mail_send`, `create_event`, `send_imessage`, `slack_send_message`, etc. (concrete list lives next to the constant — easy to extend.)
3. Expose tool-call names from `ChatProvider` to the pill. Today `toolNames` is local to `sendMessage` (`ChatProvider.swift:2601`). Either (a) `@Published var invokedToolNames: [String]` on `ChatProvider`, append on every `toolActivity status=="started"`, OR (b) reuse the pill's `messages` stream and walk `contentBlocks` for `.toolCall` blocks. Option (b) is zero-API and preferred.
4. In `AgentPillsManager.complete`, after determining provider.errorMessage:
   - If `pill.actionClass == .actionable` AND no write-set tool was invoked AND provider.errorMessage is nil → demote to `pill.status = .failed("Agent claimed completion without taking action.")`.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/AgentPill.swift`.

### P3 · Single transparent retry

**Problem.** `AgentPillsManager.spawn` calls `sendMessage` exactly once. Transient bridge errors (`.processExited`, `.outOfMemory`, the 180 s watchdog) and gate-flagged "fake done" both surface as visible failures with no recovery.

**Change.**

1. Wrap the spawn's `provider.sendMessage` call (`AgentPill.swift:382`) in a `for attempt in 1...maxAttempts` loop with `maxAttempts = 2`.
2. After each attempt: classify the result with `RetryDecision`:
   - `.success` → break.
   - `.retryBridge` (BridgeError except `.stopped` and `.agentError`) → loop.
   - `.retryGate` (P2 fired) → loop with a brand-new sessionKey so we don't reuse a broken session.
   - `.fatal` (user pressed stop, model returned an agentError saying the task is impossible) → break with failure preserved.
3. UI nicety: while retrying, show "Retrying… (attempt 2/2)" in `pill.latestActivity` so the user sees we're working, not stuck.
4. Sentry-friendly: log retry count + reason at every transition.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/AgentPill.swift`.

### Sprint 2 acceptance

- Build clean.
- Self-test: trigger a task where the model is likely to "fake done" (e.g. a Slack task with no Slack signed in). Confirm pill is now `.failed` with the gate message, not `.done`.
- Self-test: kill the pi-mono process mid-prompt (`pkill -f pi-coding-agent`). Confirm the retry loop fires and the pill recovers.
- Hand-graded 6-task mini-set: ≥ 5/6 pass; cumulative across Sprints 1 + 2 should be near the 80% target on hand-graded.

---

## Sprint 3 — Verification turn + preflight + stall detector (3–4 days)

Goal: deliver the prompt's existing "Never claim done without proof" promise programmatically, and stop spending LLM calls on setup misses.

### P8 · Programmatic verification turn (highest single-change impact)

**Problem.** P2 catches "no tool called at all"; it does not catch "wrong tool called" or "tool returned an error the model glossed over."

**Change.**

1. After Sprint-2's main `sendMessage` returns and the gate is satisfied (a write-set tool *was* called), fire a second short turn on the **same** session (cheap — already warm, cached):

   > "Verify the work you just claimed to do. Call exactly one cheap tool that proves it: read back the last message in the conversation, `ls -la` the file you wrote, fetch the calendar event you created. Reply with a single-line JSON object: `{\"verified\": true|false, \"evidence\": \"<one short line>\"}`. If you can't verify, return verified: false."

2. Parse the response with the same defensive `firstIndex(of: "{")` … `lastIndex(of: "}")` extraction `AgentPillsManager.runRouterCall` already uses (`AgentPill.swift:181`).
3. `pill.status = .done` only when `verified == true`. Otherwise → P3's retry loop fires; on retry exhaustion, `.failed("Could not verify: \(evidence)")`.
4. Append the evidence line to `pill.latestActivity` so the user sees "Done — Sent (verified: last message at 15:42 reads 'Hey Daniel, here's…')".

**Files.** `desktop/Desktop/Sources/FloatingControlBar/AgentPill.swift`, `desktop/Desktop/Sources/FloatingControlBar/ProactiveTaskExecute.swift` (the verification prompt template lives here next to the system suffix).

### P7 · Per-channel preflight

**Problem.** "Couldn't sign you in to Slack" comes back as a wasted 20-second LLM call instead of a fast, obvious setup prompt. `ChatProvider.sendMessage` only catches the Playwright case, and only *after* the model has picked the tool (`ChatProvider.swift:2682`).

**Change.**

1. New `enum ExecutePreflight { case ready; case needs(Requirement) }` with `enum Requirement { case launchTelegram, signInSlack, installPlaywrightExtension, signInGmail }`.
2. `ExecutePreflight.check(for query: String, context: FloatingBarNotificationContext?) -> Preflight` runs cheap host-side checks:
   - "telegram" in query OR `sourceApp == "Telegram"` → `pgrep Telegram`. Missing → `open -a Telegram`, wait 2 s, recheck. Still missing → `.needs(.launchTelegram)`.
   - "slack" in query OR `sourceApp == "Slack"` → check Slack desktop is running and AX-queryable (workspace title visible).
   - "email" OR "gmail" OR explicit Playwright-needed task → check `UserDefaults.standard.string(forKey: "playwrightExtensionToken")` is non-empty.
3. Execute click site runs the preflight before `spawnForNotification`. On `.needs(.installPlaywrightExtension)`, surface `BrowserExtensionSetup` (the same UI `ChatProvider` does, just earlier). On `.needs(.signInSlack)` / `.needs(.signInGmail)`, surface a small "Click to sign in" sheet that opens the right URL in Chrome.
4. Telemetry: record which preflight requirements fire most so we know where to invest.

**Files.** `desktop/Desktop/Sources/FloatingControlBar/ExecutePreflight.swift` (new), `desktop/Desktop/Sources/FloatingControlBar/FloatingControlBarView.swift`.

### P9 · Early stall detector

**Problem.** `ChatProvider.swift:2502` waits 180 s before resetting state, by which point the user has lost trust. `AgentBridge.waitForMessage` is documented as "no per-message timeout" (`AgentBridge.swift:492`) — correct for long-running tools, but wrong for bridge-layer stalls.

**Change.**

1. Replace "time since query started" tracking with "time since last byte from bridge" in `AgentBridge`. Update a `lastBridgeActivityAt` on every received message of any kind (text_delta, tool_activity, thinking_delta, anything).
2. Two-stage detection in `AgentBridge`:
   - 30 s no event → emit a synthetic `bridge_stalled` notification that `ChatProvider`/`AgentPillsManager` surfaces as `pill.latestActivity = "Agent paused, retrying soon…"`.
   - 60 s no event → call `interrupt()` and throw a new `BridgeError.stalled` that P3 treats as retryable.
3. Delete the 180 s watchdog in `ChatProvider.sendMessage:2502` (or keep it as a 300 s belt-and-suspenders for true unrecoverable hangs).

**Files.** `desktop/Desktop/Sources/Chat/AgentBridge.swift`, `desktop/Desktop/Sources/Providers/ChatProvider.swift`.

### Sprint 3 acceptance

- Build clean.
- Self-test: Execute a "send Telegram" task without Telegram running → see preflight launch it, then proceed. Without Playwright extension → see the setup sheet *before* any LLM call.
- Self-test: send a task that does a real Telegram send → see the verification turn fire, pill flips to `.done` with the "Sent — last message reads…" evidence. Manually corrupt the verification (e.g. delete the sent message before the verification turn runs) → confirm pill flips to `.failed`.
- Self-test: SIGSTOP the pi-mono subprocess for 70 s → confirm the 30 s warn, the 60 s interrupt + retry, and a clean recovery.
- Hand-graded mini-set: ≥ 5/6 pass with verification evidence on every `.done`.

---

## Sprint 4 — Eval harness (2–3 days)

Goal: prove ≥ 80% with numbers, not vibes.

### Deliverables

1. `desktop/e2e/execute-eval/tasks.json` — 30 tasks, 6 per category (Send / Schedule / Draft / Create file / Open URL), half happy-path and half rough-edges (ambiguous recipient, app not running, extension absent). Each task carries ground-truth metadata: expected recipient, expected file path, expected calendar event title, etc.
2. `desktop/e2e/execute-eval/run-eval.sh` — driver that, for each task × N = 5 trials:
   - Boots a named bundle (`OMI_APP_NAME=omi-execute-eval ./run.sh` once at start).
   - Synthesizes a proactive task notification (call `NotificationService.shared.sendNotification` via the automation bridge — bypasses the real TaskAssistant promotion loop so trials are deterministic).
   - Clicks Execute via `agent-swift click @e<ref>`.
   - Waits for pill completion (poll `omi-ctl state` or `agent-swift wait text "Done"`).
   - Captures pill status + transcript + `chatAgentQueryCompleted` analytics row.
   - Calls a per-category grader (`grade_send.sh`, `grade_schedule.sh`, …) that uses the relevant API (Telegram bot, Slack API, Gmail API, GCal API, `stat` for files) to verify ground truth.
3. `desktop/e2e/execute-eval/report.py` — aggregates results to per-task pass rate, per-category pass rate, and headline aggregate. Gate: aggregate ≥ 80% AND no single task < 60%.
4. Production telemetry: extend `AnalyticsManager.chatAgentQueryCompleted` (`ChatProvider.swift:2856`) with `executeMode: Bool`, `verifiedByGate: Bool`, `verifiedByTurn: Bool`, `retryCount: Int`, `writeToolCalled: Bool`. Add a Posthog dashboard for the same metric on the live install base.

### Runs

- **Baseline run** against `main` (before any of P1–P9) to establish the starting number — required so the uplift numbers in the review have a real anchor.
- **Post-Sprint-2 run** — gate is ≥ 80%.
- **Post-Sprint-3 run** — gate is ≥ 85% and per-task floor ≥ 70%.

---

## Release & rollout

- Sprints land as individual PRs into `feature/macos-task-exec-reliability`. Per `AGENTS.md`: individual commits per file, no squash, regular merge.
- Final merge into `main` only after Sprint 4's post-Sprint-3 run passes.
- Promote channels per `desktop/scripts/promote_release.sh <tag>` after one week of stable production telemetry on staging.
