# Proactive Task Execution — Reliability Review

Target: get the **Execute** button on a proactive task notification to land a complete, verified result **≥ 8 / 10** runs.

This review focuses on the path that fires when the user clicks **Execute** on a `assistantId == "task"` notification in the floating bar — i.e. the `ProactiveTaskExecute` → `AgentPillsManager.spawn` → `ChatProvider.sendMessage` → `AgentBridge` → `pi-mono` chain. The intent is not to redesign the system but to identify the concrete reasons it drops to ~50–60% today and the smallest set of changes that move it to ≥ 80%.

---

## 1. Today's execution path (one screen)

1. `FloatingControlBarView.swift:225` — user clicks **Execute** on a task notification.
2. `ProactiveTaskExecute.buildQuery(title:message:)` rewrites the title + message into an imperative prompt (`ProactiveTaskExecute.swift:18`).
3. `AgentPillsManager.shared.spawn(query:, model:, systemPromptSuffix:)` creates a fresh `ChatProvider`, warms its bridge, and fires a single `sendMessage` — *no* per-task chat state, no `resume`, no retry (`AgentPill.swift:294`).
4. `ChatProvider.sendMessage` composes the prompt as `floatingBarSystemPromptPrefix` + cached main system prompt + `ProactiveTaskExecute.systemPromptSuffix` and calls `agentBridge.query` with `sessionKey: "agent-<uuid>"` (`ChatProvider.swift:2611`).
5. `AgentBridge.query` writes a single `query` JSON line and waits, without a per-message timeout, for a `result`/`error` (`AgentBridge.swift:492`). A `Task`-based watchdog in `ChatProvider.sendMessage` force-releases `isSending` 180 s later if no result arrives (`ChatProvider.swift:2502`).
6. The bridge (`desktop/agent/src/index.ts`) routes the query through either `pi-mono` (default) or `claude-code-acp`. Pi-mono streams events back over its JSONL RPC; `turn_end` resolves the promise (`pi-mono.ts:761`).
7. The `AgentPill` is marked `.done` as soon as the bridge returns — *regardless of whether the work actually happened*. The pill text becomes the last 140 chars of the model's free-text reply (`AgentPill.swift:464`).

The prompt itself tells the model to "VERIFY BEFORE REPORTING DONE — Screenshot the conversation showing the sent message, OR Read back the sent message from the app, OR Confirm the file was written. Never claim 'done' without proof" (`ProactiveTaskExecute.swift:68`). **Nothing in the host actually enforces this** — it's purely model-side guidance.

---

## 2. Failure modes (ordered by estimated frequency)

Frequency labels are best-effort given the code only, not telemetry. Where a number is asserted it is anchored to a specific file:line so the team can sanity-check.

### F1. "Done" without verification (highest impact)

- The pill flips to `.done` on `provider.sendMessage` returning, full stop (`AgentPill.swift:464`).
- The model is *asked* to verify with a screenshot, app readback, or file stat — but there is no programmatic check that any verification tool ran. Anecdotally Claude-class models skip verification 30–40% of the time when it adds wall-clock latency, especially on the long-tail (15+ tool-call) executions this prompt encourages.
- Net effect: a non-trivial slice of "successful" pills are *cosmetically* successful — the model wrote a reasonable-sounding sentence ("Sent the summary to Daniel on Telegram") that doesn't match reality.

**Estimated cost: 15–25 percentage points of the gap to 80%.**

### F2. Single-shot prompt with no retry on substantive failure

- `AgentPillsManager.spawn` calls `sendMessage` exactly once; the `complete()` path has no retry hook (`AgentPill.swift:376–390`, `AgentPill.swift:464`).
- The agent bridge does retry on transport / auth errors (`index.ts:847`, `pi-mono.ts:647` — `auto_retry_*` events for 429 / 5xx). It does **not** retry when the model reports a failure or asks for clarification.
- "Telegram.app wasn't running" / "Slack wasn't logged in" / "Playwright extension not installed" all fall into this bucket — the bridge returns success, the model writes a "couldn't do this because…" sentence, and the pill goes `.done`.

**Estimated cost: 10–15 pp.**

### F3. Ambient bridge / OOM / stale-session failures count as task failures

- `pi-mono.ts:294` — the pi subprocess exit handler rejects every pending request with `pi-mono process exited (code N)`. The first prompt of the day frequently lands during a deferred restart for a refreshed Firebase token (`pi-mono.ts:529`) or a system-prompt change (`pi-mono.ts:498`). Both rebuild the subprocess, both happen *while* `pendingRequests` are queued in some races.
- The 180 s watchdog in `ChatProvider.sendMessage` (`ChatProvider.swift:2502`) marks the pill as a hard failure with the generic "Response took too long. Try again." That message reaches the user even though the underlying cause is recoverable.
- `AgentBridge.waitForMessage` is documented as having "no per-message timeout" (`AgentBridge.swift:492`). When the pi subprocess silently dies after stdout writes a `turn_end` with `stopReason = toolUse` but before the next stream chunk arrives (we've seen this after laptop sleep), the bridge hangs until the 180 s watchdog fires and writes the "took too long" error.

**Estimated cost: 5–10 pp.**

### F4. Tool selection drift on the open desktop

- The system-prompt suffix declares "PREFERRED CHANNELS" (`ProactiveTaskExecute.swift:60–66`) but the model still has to *discover* whether Telegram.app is running, whether the Slack desktop client is signed in, whether the Playwright extension is installed, etc. There's no per-channel preflight in the host.
- `ChatProvider.sendMessage` only intercepts Playwright tool calls *after the model has chosen them* (`ChatProvider.swift:2682` — `needsBrowserExtensionSetup`). It then **aborts the entire query** via `stopAgent()` (`ChatProvider.swift:2687`), so the user sees a failed pill on a recoverable browser-setup miss.
- The pi-mono extension auto-discovers MCPs and extensions on the user's machine (`pi-mono.ts:217`), which is great for power users and bad for reliability: tool names drift between machines and Claude can call a tool that exists but is misconfigured.

**Estimated cost: 5–10 pp.**

### F5. No context about *which notification* spawned the agent

- The pill receives only `title` + `message` (`ProactiveTaskExecute.buildQuery`). It does **not** receive the `FloatingBarNotificationContext` (`TaskPromotionService.swift:139`) that the floating-bar chat *does* receive — `sourceApp`, `windowTitle`, `contextSummary`, `currentActivity`, `reasoning`, `detail` are all dropped on the floor.
- The model has to re-derive the context with `semantic_search` / `get_memories` / `execute_sql` — those calls are slow, error-prone, and frequently misidentify the right thread / channel / contact.
- The TaskExecute prompt explicitly tells the model "Don't ask the user for clarification" + "If you're wrong, the user will course-correct on the next notification" (`ProactiveTaskExecute.swift:41`). Combined with F5 this is a recipe for "Sent the summary to the *wrong* Daniel on Telegram" outcomes.

**Estimated cost: 10–15 pp.**

### F6. Floating-bar "concise answer" rules bleed into Execute

- The `floatingBarSystemPromptPrefix` (`ChatProvider.swift:469`) is *prepended* to every Execute prompt. It says "NEVER ask follow-up questions", "Respond concisely in 1-2 sentences", "No lists. No headers."
- `ProactiveTaskExecute.systemPromptSuffix` is *appended* and tries to override — "the earlier '1-2 sentence, no follow-ups' rules only apply to your FINAL report." This is a soft contract. Models routinely read the *first* rule-block as authoritative when the two conflict, and produce short single-tool-call answers instead of working the task end-to-end.

**Estimated cost: 5–10 pp.**

### F7. Wrong model for the job

- `FloatingControlBarView.swift:222–224` selects the user's "selectedModel" or falls back to `claude-sonnet-4-6`. Execute is a high-tool-count agentic task where Opus's reliability uplift on multi-step tool use is exactly what we want to spend money on.
- A long-tail "send a multi-paragraph summary to the right Telegram contact, drawn from yesterday's transcript" is the wrong job for Sonnet's planning quality.

**Estimated cost: 3–5 pp (and a flat ~2x cost — see §4 trade-offs).**

### F8. No idempotency / dedup on Execute clicks

- Clicking Execute twice on the same notification spawns two parallel pills (`AgentPillsManager.spawn`'s only dedup is the soft `maxPills = 8` cap, `AgentPill.swift:79`). Both race to send the same message / write the same file / create the same calendar event. This is rare but very visible when it happens.

**Estimated cost: 1–2 pp.**

---

## 3. Concrete proposals, ranked by impact / effort

Each proposal is sized as **S** (≤ ½ day), **M** (1–3 days), **L** (> 3 days). Each cites the file(s) it touches.

### P1 [S, addresses F5] — Forward the full notification context to the pill

`FloatingControlBarView.swift:225` currently builds the prompt from `notification.title` + `notification.message`. The notification *already* carries `FloatingBarNotificationContext` (set in `TaskPromotionService.buildNotificationContext`, `TaskPromotionService.swift:136`). Plumb it into `ProactiveTaskExecute.buildQuery` as a structured "TASK CONTEXT" block:

```
# TASK CONTEXT
- Source app: Telegram
- Window: Chat with Daniel
- Detail: "Send Daniel the bullet summary of yesterday's standup"
- Reasoning: priority=high, due=2026-05-25T17:00:00Z, source=conversation
- Activity at promotion: <currentActivity>
- Context summary: <contextSummary>
```

This single change removes the most common "wrong target" failure mode at near-zero cost.

### P2 [S, addresses F1] — Tool-usage gate before "done"

In `AgentPillsManager.complete` (`AgentPill.swift:464`), inspect `provider.messages` (or pipe the `toolNames` array from `ChatProvider.sendMessage`, which is already tracked at line 2601) and **demote** the pill from `.done` to `.failed("Agent reported completion without acting — no write/send/script tool was called")` when:

- the task type is *actionable* (Send / Reply / Create / Schedule / Draft / Post — already classifiable from `notification.title` or the first word of `buildQuery`), AND
- no tool from a small "write set" was invoked (`shell`, `playwright_*`, `osascript`, `write_file`, `create_event`, `send_message`, `apple_notes_add`, etc.).

This is heuristic, not airtight, but it converts most "fake done" outcomes (F1) into honest failures the user retries from.

### P3 [S, addresses F2 + F3] — Single transparent retry on the pill

`AgentPill.spawn` runs the prompt exactly once. Wrap the `provider.sendMessage` call (`AgentPill.swift:382`) in a tiny retry loop:

```swift
var attempt = 0
while attempt < 2 {
    attempt += 1
    await provider.sendMessage(...)
    if isVerifiedSuccess(provider) { break }      // P2's gate
    if isRetryable(provider.errorMessage) { continue } // OOM, processExited, watchdog
    break
}
```

`isRetryable` is anything in `BridgeError` other than `.stopped` and `.agentError` (which is model-reported, not transport). This costs at most one extra LLM call on the 15–25% of runs that are transient and is invisible on the happy path.

### P4 [S, addresses F6] — Move Execute off the floating-bar prompt prefix

Today `AgentPillsManager.spawn` always prepends `ChatProvider.floatingBarSystemPromptPrefix` (`AgentPill.swift:386`). The "Execute" pill should bypass it entirely — `systemPromptPrefix: nil` — and use only the main system prompt + `ProactiveTaskExecute.systemPromptSuffix`. The "1–2 sentences, no follow-ups" rule is for inline-bar answers; for Execute the suffix's "Use as many tool calls as you need" should be the only voice in the room.

### P5 [S, addresses F7] — Pin Execute to Opus

`FloatingControlBarView.swift:222` falls back to `claude-sonnet-4-6`. For Execute specifically, force `claude-opus-4-6` regardless of user model selection (the user-selected model controls inline-bar answers). Document the cost trade-off in `ProactiveTaskExecute.swift`. Add a hidden defaults flag (`OmiExecuteModel`) to override.

### P6 [S, addresses F8] — Dedupe by notification ID

Add a `Set<UUID>` of "execute-fired" notification IDs to `FloatingControlBarManager`. Reject the second click within 60 s. The notification model already has an ID — wire it through `ProactiveTaskExecute.buildQuery(notificationId:title:message:)`.

### P7 [M, addresses F4] — Per-channel preflight

Before spawning the pill, do cheap host-side checks based on the task wording:

- "telegram" / known-Telegram contact → check `pgrep Telegram`; if absent, `open -a Telegram` and wait 2 s for it to come up.
- "slack" → check whether the desktop client is running and signed in (Accessibility API: query the workspace title bar).
- "email" → check that the Playwright extension token is set (`UserDefaults.standard.string(forKey: "playwrightExtensionToken")`). If missing, surface `BrowserExtensionSetup` *before* spawning the pill rather than after the model picks the tool (`ChatProvider.swift:2683`).

This converts the most common "couldn't act" failures from "20-second wasted LLM call + cryptic error" into "obvious setup prompt before the agent is spent". Implement as a small `ExecutePreflight` enum that returns `.ready` / `.needs(.setupSlack | .installPlaywrightExtension | …)`.

### P8 [M, addresses F1 in depth] — Programmatic verification step

After the pill's main `sendMessage` returns, fire a short second turn on the *same* session:

> "Verify the work you just claimed to do. Call one cheap tool that proves it: read back the last message in the conversation, `ls -la` the file you wrote, fetch the calendar event you created. Return JSON: `{verified: true|false, evidence: '<one line>'}`. If you cannot verify, return false."

This piggybacks on the already-warm session (cheap), produces structured evidence, and the pill's `.done` state should be conditional on `verified == true`. When `false`, P3's retry loop fires once. This is the single most impactful change and the one that *actually* delivers the prompt's existing "Never claim done without proof" promise.

### P9 [M, addresses F3] — Replace the silent 180 s watchdog with an early stall detector

`ChatProvider.swift:2502` waits a full three minutes before resetting state, by which point the user has lost trust. Replace with two-stage detection in `AgentBridge.waitForMessage`:

- 30 s with **no** event of any kind (text, tool_activity, thinking, etc.) → emit a `bridge_stalled` warning to the pill UI ("Agent paused, will retry shortly").
- 60 s stall → `interrupt()` the bridge, throw a recoverable error that P3's retry loop handles.

Today's "no per-message timeout" is correct for *long-running tools*, but stalls in the messaging layer (the actual problem) should be distinguished from a tool that's legitimately running. Track "last byte from bridge" instead of "time since query started".

### P10 [L, addresses F4 + general drift] — Curated tool whitelist per Execute task class

A long-term answer to F4 is to *not* hand the open desktop to Claude on every Execute. Classify the task client-side (Send / Schedule / Draft / Research / Create file / Open URL) and pass the bridge a narrow allowed-tools list per class:

- **Send** → `osascript` (Messages, Telegram, Slack desktop), `playwright_*` for web Slack/Gmail, `apple_mail_send`. No file write, no shell other than osascript.
- **Schedule** → `create_event` MCP, `osascript` for Calendar.app. No browser tools.
- **Draft** → `write_file` under `~/Desktop`, `apple_notes_add`. No send tools.

This is the largest change but makes outcomes far more predictable and removes the entire "agent improvises an exotic tool" failure mode.

---

## 4. Expected uplift toward 80%

These are not additive in the strict statistical sense (failures overlap), but as a rough budget against the gap from a ~55% baseline:

| Proposal | Effort | Approx uplift |
|---|---|---|
| P1 Plumb notification context | S | +5 pp |
| P2 Tool-usage gate before "done" | S | +5 pp |
| P3 Single retry on transient + unverified | S | +5 pp |
| P4 Drop floating-bar prefix on Execute | S | +3 pp |
| P5 Pin Opus | S | +3 pp |
| P6 Dedupe Execute clicks | S | +1 pp |
| P7 Per-channel preflight | M | +5 pp |
| P8 Programmatic verification turn | M | +7 pp |
| P9 Early stall detector | M | +2 pp |
| **Sum of P1–P9** |  | **+36 pp → ~91% ceiling** |
| P10 Tool whitelist | L | +5–10 pp / dramatically lower variance |

The S-tier alone (P1–P6) totals ~22 pp uplift, which is the path of least resistance to crossing 80%. P8 is the single change with the largest individual impact; it should ship even if nothing else does.

### Trade-offs

- **Latency.** P8 adds one extra turn (~3–5 s). P3 doubles latency in the worst case. Both are acceptable for an Execute click — the user already opted into "spend time on this."
- **Cost.** Pinning Opus (P5) roughly doubles LLM cost on Execute. Execute is a tiny fraction of total queries; the absolute increase is small and the reliability uplift is large.
- **False-negative rate of the verification gate (P2).** A model that *correctly* completes a Research task with no write-set tool would be flagged as failed. Mitigate by classifying actionable vs. research-y tasks from the title's first verb and only applying the gate to actionable ones.
- **Tool whitelist (P10) reduces what the model can attempt.** Truly novel "Execute this weird thing" tasks degrade. Accept that — the proactive task system promotes commitments the user has already agreed to; the long tail of weird is a feature for inline Ask Omi, not for Execute.

---

## 5. Evaluation plan — how we'll know we hit 80%

A spec without a measurement plan is just a hope. The minimum we need:

1. **Define the metric.** A run *succeeds* when (a) the pill is `.done`, (b) at least one write-set tool was called (P2's gate), AND (c) a human grader can confirm the claimed action happened (recipient received the message, file exists at the path, event is on the calendar). Tracked per-task in a graded eval set.
2. **Build a fixed eval set of ~30 representative tasks**, evenly split across Send / Schedule / Draft / Create file / Open URL, with explicit ground truth (who/what/where). Half should be "happy path" (recipient is in memories, app is installed); half should be "rough edges" (ambiguous recipient, app not running, Playwright extension absent).
3. **Run the set N=5 times** per code revision. Track per-task pass rate AND aggregate pass rate. We're at 80% when aggregate ≥ 80% across the 30 × 5 = 150 trials *and* no single task drops below 60% (avoid "fixed nine, broke one").
4. **Instrument three additional metrics** even before the eval set lands:
   - `chatAgentQueryCompleted` (already exists, `ChatProvider.swift:2856`) — extend with `executeMode: true`, `verifiedByGate: bool`, `retryCount: int`, `writeToolCalled: bool`. We can compute a real-world reliability proxy from production without a graded set.
   - Bridge error breakdown: how often is `.processExited` / `.outOfMemory` / `.timeout` the failure mode vs `.agentError`. P9's stall detector is justified only if `.timeout` is a non-trivial slice today.
   - "Done without write tool" rate as a leading indicator of F1.
5. **Land P1–P6 in one PR**, re-measure. Land P7–P9 in a second, re-measure. P10 in a third, re-measure. The S-tier alone should be enough to cross 80%; everything else is variance reduction and ceiling-raising.

The eval harness can reuse the existing self-test infrastructure (`agent-swift connect --bundle-id com.omi.omi-execute-eval`, `AGENTS.md` "Self-Testing the App" section, `desktop/e2e/SKILL.md`). The 30-task set should live in `desktop/e2e/execute-eval/tasks.json`, with grader scripts that hit Telegram/Slack/Mail APIs to verify ground truth.
