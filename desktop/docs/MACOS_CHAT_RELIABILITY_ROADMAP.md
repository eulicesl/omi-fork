# macOS Chat Reliability Roadmap

Branch of record: `feature/macos-chat-reliability-80`
Worktree-local source of truth. No reliance on `BasedHardware/omi` upstream or any remote snapshot for verification — every claim, file path, and line number in this doc references the local worktree.

This roadmap is phased: **V1 ships now**; V2/V3/V4 are follow-on coding sprints with their own kickoffs. Implementation does not begin until this document is committed.

---

## Phased shape

| Phase | Theme | Goal |
|---|---|---|
| V1 | Reliability foundation | Trust, stalls, timeouts, persistence, and proof. Stop the app from feeling misleading, stuck, or fragile. |
| V2 | Runtime hardening | Make chat hard to break across restart, sleep/wake, bridge restart, token refresh, network drop, partial response, cancelled turn, mode switch, SQLite lock, save failure. |
| V3 | Premium assistant UX | Approach ChatGPT/Claude-level clarity, mode awareness, grounded answers, and user trust. |
| V4 | Continuous reliability | Operate chat reliability as a platform — alerts, regressions, rollbacks, scorecards. |

V1 fixes current pain and proves the metric movement. V2 hardens the runtime under it. V3 makes the assistant feel premium. V4 makes the whole thing continuous. Do not implement V2/V3/V4 inside V1.

---

# V1 — Reliability Foundation

## Cross-cutting rules (apply to every V1 PR)

### Local verification workflow

Per `AGENTS.md:23, 127-180`. Every PR follows this loop.

1. **Never target the prod app.** No `Omi.app`, no `Omi Beta.app`, no bundle id `com.omi.computer-macos`.
2. **Named bundle only:**
   ```bash
   OMI_APP_NAME="omi-chat-reliability" ./run.sh --yolo
   ```
   Run from `desktop/`. `--yolo` skips local backend; the named bundle talks to the prod backend (`api.omi.me`) and the prod PostHog project. This is intentional — see "Dev/prod telemetry separation" below.
3. **Compile check after every workstream:**
   ```bash
   cd desktop && xcrun swift build -c debug --package-path Desktop
   ```
4. **Seed auth into the named bundle** (after a one-time "Omi Dev" sign-in):
   ```bash
   cd desktop && ./scripts/omi-auth-dump.sh && ./scripts/omi-auth-seed.sh com.omi.omi-chat-reliability
   ```
5. **Drive and verify UI only via the named bundle:**
   ```bash
   agent-swift connect --bundle-id com.omi.omi-chat-reliability
   agent-swift snapshot -i
   agent-swift screenshot /tmp/<pr-name>-evidence.png
   ```

Every PR description must include:
- Last successful build SHA
- Named bundle id tested (`com.omi.omi-chat-reliability`)
- Evidence screenshot path(s)
- `piMono` / `userClaude` mode coverage statement (one or both, never silent)

### Telemetry contract

PR 0a owns this. Every later PR must comply.

**Allowed event fields (allow-list):**
- `turnId` (UUID)
- `bridgeMode` (enum)
- `model` (string from a fixed allow-list)
- Duration and count fields (ms, integers)
- Status enums
- Tool names from a fixed allow-list of the 7 in `ChatPrompts.swift:474-509`
- Error class enums
- Hashed user id (see "User-id hashing" below)
- `build_dev_bundle` (boolean) — uses the `build_` prefix to match
  the existing PostHog domain-prefix convention (`chat_*`,
  `floating_*`, `memory_*`, `advice_*`) and describe what these are
  (build metadata)
- `build_bundle_id`, `build_app_name`, `build_git_sha`, `build_branch`, `build_environment`
  — note `build_app_name` deliberately doesn't collide with the
  existing bare `app_name` property (which is set elsewhere)

**Forbidden in any event, ever:**
- Raw user prompts or any prefix/suffix
- SQL query strings (only the tool name `execute_sql` + row count + duration)
- Memory text, conversation transcript text, screenshot OCR text
- Tool input arguments or tool output payloads (only sizes/counts/status)
- File paths from `indexed_files` or `workingDirectory`
- Knowledge-graph node labels
- Attachment content or filenames (only count and total bytes)

**Enforcement: typed redacted event payloads, not `[String: Any]`.**

Each event is a dedicated Swift `struct`. Examples for V1:
- `ChatTurnStartedPayload`
- `ChatTurnCompletedPayload`
- `ChatTurnFeedbackPayload`
- `ChatStallEventPayload`
- `ChatScenarioRunPayload`

`AnalyticsRedactionTests` reflects over each payload struct and fails CI if any field name matches `prompt|sql|query|text|content|path|label|args|input|output|memory|transcript|ocr` unless explicitly allow-listed.

### `chat.turn.started` semantics (locked)

- Emitted **synchronously** when `sendMessage` commits the user turn locally.
- Emitted **before** any bridge call, tool call, auth check, or model stream begins.
- Rationale: `started − completed` is the orphan/stuck/crashed-turn detector. If `started` fired after the bridge handed back its first event, bridge-startup failures would emit zero events and look like nothing happened.

### User-id hashing (locked)

- Algorithm: **HMAC-SHA256**.
- Salt: **long-lived per-environment secret** stored outside the repo (CI secret + dev `.env.local`, never committed).
- Env var name: **`OMI_TELEMETRY_HMAC_SALT`** (locked).
- Dev/local fallback: when the env var is unset, use the literal
  string `dev-local-salt-do-not-use-in-prod`. Log a warning at
  startup so missing prod configuration is loud. The warning ALSO
  fires when the env var IS set but its value equals the dev-local
  literal — catches a bad copy-paste of the fallback into a real
  prod env config at startup, not after data has been hashed. PR 0a's
  redaction tests assert the prod salt is **not** that literal
  string.
- The secret is never logged anywhere, including crash reports.
- Rotated only on compromise — rotation breaks longitudinal cohort tracking, so it is not routine maintenance.

### Dev/prod telemetry separation (defense in depth)

Two layers; **both** are required.

**Client-side tagging (every event from the named bundle):**
```
build_dev_bundle  = true
build_bundle_id   = com.omi.omi-chat-reliability
build_app_name    = omi-chat-reliability
build_git_sha     = <current commit>
build_branch      = feature/macos-chat-reliability-80
build_environment = "named-bundle-dev"
```

**Server-side / dashboard rule (PostHog):**
- Production reliability dashboards filter `build_dev_bundle != true`
  (NOT `= false`). HogQL treats missing ≠ false — using `= false`
  would exclude every event predating PR 0a's emission, blanking
  the charts. `!= true` correctly matches both "property absent"
  (existing data) and "property explicitly false" (future
  non-dev-bundle emits).
- PR validation dashboards filter `build_dev_bundle = true AND build_git_sha = <PR SHA>` for per-PR canary slicing.
- **Existing-dashboard retrofit (PR 0a acceptance gate):** none of
  the 14 existing insights on the source-of-truth dashboard
  (`https://us.posthog.com/project/302298/dashboard/1624254`)
  currently filter against `build_dev_bundle` (the property doesn't
  exist yet — PR 0a is what introduces it). PR 0a must add the
  `build_dev_bundle != true` filter to every insight on that
  dashboard in the same PR that ships the named-bundle telemetry
  plumbing — otherwise dev sessions contaminate the production
  metric the moment PR 0a starts emitting tagged events.

A misconfigured client emit cannot contaminate production metrics because the dashboard rule is the gate, not the client tag.

### Scenario coverage requirement

Per `ChatProvider.swift:566-571`, two production-meaningful modes:
- `piMono` — default. Seven tools per `ChatPrompts.swift:471-597`. No file/code read.
- `userClaude` — opt-in. Claude Agent SDK with `workingDirectory` per `ChatProvider.swift:523-525`. Real `Read`/`Bash` tools.

Every fix PR's acceptance section calls out behavior in **both** modes, or explicitly states "userClaude path unaffected, verified by …".

---

## V1 PR map

PRs 0a and 0b are **parallel foundation work**. PR 0b is a blocker for PRs 1, 3, 4, 7, and 8 — it is not a successor to PR 0a. PR 0a is a blocker only for PR 5 and PR 9 (everything that depends on the telemetry pipeline).

| # | Title | Type | Depends on |
|---|---|---|---|
| 0a | Per-turn telemetry + privacy contract | infra | — |
| 0b | Deterministic fake bridge / test harness | infra | — |
| 1 | Client-side stall detection (`.slow` / `.stalled`) | feat | 0b |
| 2 | Empty-state + starter-prompt honesty | feat | — |
| 3 | Tool-call timeout policy + interrupt correctness | fix | 0b, 1 |
| 4 | Error recovery UX | feat | 0b, 3 |
| 5 | `saveMessage` vs. poll race fix | fix | 0a |
| 6 | Prompt ↔ schema regression tests | test | — |
| 7 | Scenario / eval tests across `piMono` + `userClaude` | test | 0b, 1, 3, 4, 5 |
| 8 | Bridge heartbeat protocol | feat | 0b, 1 |
| 9 | Sprint exit review + threshold tuning | chore | 0a, 1, 3, 4, 5, 7, 8 |

PRs 2 and 6 can ship in parallel with the 0a/0b → 1 critical path.

---

## PR 0a — Per-turn telemetry + privacy contract

**Problem.** No per-turn outcome signal exists. `AnalyticsManager` (`ChatProvider.swift:930, 991, 2708`) emits coarse events but nothing closes the loop on "did this turn succeed and was the user happy". Can't prove W4 movement without it.

**Scope.**
- Extend `AnalyticsManager` with three V1 events plus payload structs:
  - `chat.turn.started` → `ChatTurnStartedPayload` — emitted synchronously in `sendMessage` *before* any bridge work (see "`chat.turn.started` semantics" above).
  - `chat.turn.completed` → `ChatTurnCompletedPayload` — emitted on turn finalize (success/failure/interrupt/timeout).
  - `chat.turn.feedback` → `ChatTurnFeedbackPayload` — emitted on thumbs 👍/👎, keyed by `turnId`.
- `ChatTurnTelemetry` collector hooked into `ChatProvider.sendMessage` (~`:2429-end`) using existing stream callbacks (`onTextDelta`, `onToolCall`, `onToolActivity` per `AgentBridge.swift:427-429`).
- Client-side build-metadata tags on every event using the `build_*` prefix (`build_dev_bundle`, `build_bundle_id`, `build_app_name`, `build_git_sha`, `build_branch`, `build_environment`). See "Dev/prod telemetry separation" above for verification context.
- `AnalyticsRedactionTests` reflects over each payload struct and rejects forbidden field names.
- HMAC-SHA256 user-id hashing with per-env secret (`OMI_TELEMETRY_HMAC_SALT`). Startup warning fires both when unset and when set-but-equals the dev-local literal — catches bad copy-paste into prod config.
- Eval Firebase UID locked at `rg0PvY9mhKRARcYxkHHYh4iAkc12` for V1 (user's personal account, data-mixing accepted). The PR 7 seed script hardcodes this UID; before this branch upstreams to `BasedHardware/omi`, swap to a dedicated `omi-eval@…` UID.
- **Retrofit the existing PostHog source-of-truth dashboard** (`https://us.posthog.com/project/302298/dashboard/1624254`, 14 insights) to filter `build_dev_bundle != true` on every insight. NOT `= false` — HogQL treats missing ≠ false, so `= false` would exclude every event predating PR 0a's emission and blank the charts. Must land in the same PR as the telemetry plumbing — otherwise dev-tagged events from named bundles contaminate the production metric the moment emission starts.
- **Deprecate the bare `build` and `build_number` properties.** Audited 2026-05-25 by user: over 30 days on macOS, `build` appears on 34 events out of 7.6M (0.0004%), `build_number` on 1 event. PostHog's auto-captured `$app_build` appears on 4,975,946 events — and 100% of the events carrying `build` (34/34) also carry `$app_build` with identical values. Confirmed redundant. Remove the emit sites in this PR.

**Local verification gate.**
- Standard 5-step.
- Drive 3 turns via `agent-swift` (good / tool-heavy / cancelled mid-stream). Capture screenshots.
- Verify in PostHog (filtered `build_dev_bundle = true AND build_git_sha = <SHA>`) that exactly 3 `chat.turn.completed` events arrive with correct `outcome` and exactly 3 `chat.turn.started` precede them.
- Verify the production dashboard view (`build_dev_bundle != true`) does **not** count any of these events.

**Tests.**
- Unit `ChatTurnTelemetryTests` — four outcomes (`.completed`, `.interrupted`, `.errored`, `.timeout`); `firstTokenMs` and `interEventGapsMs` populated; `started` always precedes `completed` for the same `turnId`.
- Unit `AnalyticsRedactionTests` — reflection over every payload struct; forbidden field names fail.
- Unit `UserIdHashTests` — same input + salt → same hash; different envs (different salts) → different hash; salt is not present in any encoded output.

**Acceptance.**
- 100% of started turns emit exactly one `chat.turn.started`.
- 100% of finalized turns emit exactly one `chat.turn.completed`.
- Thumbs feedback within 24h emits matched `chat.turn.feedback` keyed on `turnId`.
- Orphan detector: `count(started) − count(completed) ≈ 0` over a settled window.
- Redaction tests pass; no raw text in any emitted event.
- Production dashboard (`build_dev_bundle != true`) is live: `like_ratio` by `bridgeMode` × `outcome`. PR validation dashboard (`build_dev_bundle = true AND build_git_sha`) is also live.

**Rollback.** Feature flag `CHAT_TELEMETRY_V2` gates emit for first 24h. Pure addition; reverts cleanly.

---

## PR 0b — Deterministic fake bridge / test harness

**Problem.** PRs 1, 3, 4, 7, 8 each need to simulate bridge or tool misbehavior. Manual injection is flaky. Without a deterministic test harness, the rest of the sprint's tests will be unreliable.

**Scope.** A `FakeAgentBridge` (Swift) and a fake adapter under `desktop/agent/tests/` that can simulate, on demand:
- First-token delay
- Mid-stream stall (gap between deltas)
- Never-returning tool call
- Malformed bridge message
- Bridge process crash mid-turn
- Heartbeat loss (after PR 8)
- `auth_required` event
- Interrupt arriving during tool execution
- Delayed final result after all deltas
- Empty tool result

Each scenario is a named factory method with deterministic timing (no wall clock).

**Local verification gate.**
- Standard 5-step build.
- Unit-test harness only — no UI in this PR.

**Tests.**
- `FakeAgentBridgeTests` — every scenario fires the expected sequence of callbacks in the expected order with the expected timing.

**Acceptance.**
- Later PRs use these scenarios instead of manual injection.
- Tests built on the fake harness are deterministic across 100 consecutive runs (CI assertion).

**Rollback.** Test-only. Never revert.

---

## PR 1 — Client-side stall detection

**Problem.** `ToolCallStatus` (`ChatProvider.swift:194-197`) has only `.running` / `.completed`. Spinner with no progress signal is a primary source of 👎. No bridge change needed — `AgentBridge.swift:427-429` already provides enough timestamped events to detect inter-event gaps and per-tool durations.

**Scope.**
- Extend `ToolCallStatus`:
  ```swift
  enum ToolCallStatus { case running, slow, stalled, completed, failed }
  ```
- `StallDetector` actor owned by `ChatProvider`. Two timers per turn:
  - Inter-event gap timer (resets on any delta/activity event).
  - Per-tool duration timer (started on `tool_use`, cleared on tool result).
- Named thresholds (tuned in PR 9):
  - `StallThresholds.slowGapMs = 8_000`
  - `StallThresholds.stalledGapMs = 20_000`
- UI affordance on tool-call rows and message-level banner: "Still working…" / "This is taking longer than usual — keep waiting or cancel." Cancel wired to `AgentBridge.interrupt()` (`AgentBridge.swift:595`).
- No feature flag — UX affordance, not behavior change.

**Local verification gate.**
- Standard 5-step.
- Use the PR 0b fake bridge to drive `.running` → `.slow` → `.stalled` deterministically. Screenshot each state.
- Repeat against a `userClaude` session (mode toggle in settings). The detector fires equivalently.

**Tests.**
- Unit `StallDetectorTests` — promotion thresholds; resets on `onTextDelta` and `onToolActivity`; per-tool timer independent; interrupt halts all timers and emits no further state changes.
- Snapshot tests for `.slow` and `.stalled` rows.

**Privacy check.** Stall events emit only `ChatStallEventPayload { turnId, kind: .gap | .tool, elapsedMs, toolName? }`. No prompt or output text.

**Acceptance.**
- 8s gap → row `.slow`. 20s gap → row `.stalled` + banner with working Cancel.
- `chat.turn.completed` includes `stallEventsEmitted` count.
- Both `piMono` and `userClaude` paths verified.

**Rollback.** Tune thresholds, don't revert.

---

## PR 2 — Empty-state + starter-prompt honesty

**Problem.** Default `piMono` chat has no file/code-read tool. The 7 real tools per `ChatPrompts.swift:474-509` cover memories, conversations, daily recap, tasks, screen history. `indexed_files` (`IndexedFileRecord.swift:47-104`) holds only metadata; no contents. Any starter prompt or empty-state hero implying "ask about your code/files" produces immediate 👎.

**Scope.**
- Audit `OnboardingChatView.swift`, `ChatPage.swift`, and the starter-prompt source.
- Replace anything not backed by one of the 7 real `piMono` tools.
- `BridgeMode`-conditional starter sets: only `userClaude` shows code/file starters (it has `workingDirectory` + Read/Bash per `ChatProvider.swift:523-525`).

**Local verification gate.**
- Standard 5-step.
- Evidence shots of empty state and starter prompts in default `piMono`.
- Toggle to `userClaude`; second evidence shot showing the code/file starters appear.

**Tests.**
- Extend `ChatDiscoverabilityTests.swift` (already exists under `desktop/Desktop/Tests/`): every starter prompt's claimed capability must map to a real tool name in the active mode's tool block.
- Snapshot test of empty state in both modes.

**Privacy check.** No telemetry change.

**Acceptance.** No starter prompt references a capability absent from the active mode's tool set. CI fails on new prompts that name nonexistent tools.

**Rollback.** Copy revert.

---

## PR 3 — Tool-call timeout policy + interrupt correctness

**Problem.** Two failure modes:
1. No per-tool ceiling. The only safety bounds today are an attachment-upload timer (`ChatProvider.swift:2409`) and an ACP session-level timeout (`ChatProvider.swift:2899-2900`).
2. `interrupt()` (`AgentBridge.swift:594-598`) sets a flag; `query()` drains tool results (`:522-527`), but UI rows can be left `.running` if the drain races the interrupt.

**Scope — piMono tools (the 7 in `ChatPrompts.swift:474-509`):**

| Tool | Timeout |
|---|---|
| `execute_sql` | 15s |
| `semantic_search` | 20s |
| `search_tasks` | 20s |
| `get_daily_recap` | 25s |
| `complete_task` | 5s |
| `delete_task` | 5s |
| `save_knowledge_graph` | 30s |

On timeout: cancel the tool if safe, emit a synthetic `tool_result` with structured error `{ error: "tool_timeout", tool, elapsedMs }`, set the UI row `.failed`, classify the turn outcome as `.timeout`.

On `interrupt()`: walk every `.running` / `.slow` / `.stalled` row for the active turn → `.failed(.interrupted)`. Preserve partial assistant text. Stop further state mutation from stale deltas.

**userClaude scope (explicit carve-out).**
V1 does **not** apply aggressive timeouts to legitimate long-running Claude Code / Bash / file-system work in `userClaude`. For `userClaude`, V1 verifies only:
- Stall UI (PR 1) renders correctly when work is genuinely slow.
- Interrupt cleanup leaves no rows in `.running` / `.slow` / `.stalled`.
- Partial assistant text is preserved on interrupt.

The full `userClaude` tool execution contract (per-tool timeouts, retry, idempotency) is **V2**, not V1.

**Local verification gate.**
- Standard 5-step.
- Drive timeout scenarios via the PR 0b fake bridge.
- Mid-turn `agent-swift click` the Cancel banner; confirm all rows resolve, partial text preserved. Screenshots.

**Tests.**
- `ToolTimeoutTests` — never-returning tool times out within ±200ms of its constant; synthetic error reaches the agent; UI row ends `.failed`.
- `InterruptCorrectnessTests` — two in-flight tools, interrupt arrives, both become `.failed(.interrupted)`; partial text retained; no further deltas mutate state.

**Privacy check.** Timeout event uses only `{ turnId, toolName, elapsedMs, reason }`.

**Acceptance.**
- No `piMono` tool row outlives its timeout.
- No row stays `.running` / `.slow` / `.stalled` after interrupt in either mode.
- `outcome = .timeout` populated correctly.

**Rollback.** Per-tool constants; bump generous to disable.

---

## PR 4 — Error recovery UX

**Problem.** Today's failures appear as infinite spinners, raw error strings, or vague red banners. Five user-visible failure classes need explicit, recoverable surfaces.

| Class | Trigger | Source |
|---|---|---|
| Auth required | Anthropic OAuth lapsed (`userClaude`) or Firebase token expired (`piMono`) | `AgentBridge.swift` `auth_required` path (`:432`) |
| Timeout | Tool or turn timeout from PR 3 | new in PR 3 |
| Bridge unavailable | `AgentBridge` start failure (`ChatProvider.swift:930`); "Node.js not found" / "AI components missing" (`AgentBridge.swift:1009-1013`) | existing |
| Interrupted | User-initiated `interrupt()` | PR 3 |
| No data found | Tool returns empty results | partly handled in prompt (`ChatPrompts.swift:320-328`); needs a UI affordance |

Network / API failure surfaces in existing paths are folded into "Bridge unavailable" or "Timeout" depending on the actual cause.

**Scope.**
- `ChatErrorState` enum with the 5 cases, each carrying a `recovery` action: `retry`, `signIn`, `openSettings`, `installRuntime`, `dismiss`, `switchMode` (where appropriate).
- Inline message-level error card replaces ad-hoc red banners. Card surface: short cause, recovery CTA, optional "Show details" disclosure with the redacted error class only.
- Retry policy: replays the last user turn with a **fresh** `turnId` (so telemetry doesn't double-count).
- Empty-result case: friendly inline note ("I don't have anything on that") that feels intentional, not broken.

**Local verification gate.**
- Standard 5-step.
- Drive every failure class via the PR 0b fake bridge:
  - Auth: revoke or simulate `auth_required` → screenshot Auth card → recover.
  - Timeout: PR 3 fake never-returning tool.
  - Bridge unavailable: PR 0b crash scenario.
  - Interrupt: send a turn, cancel mid-stream.
  - No data: query a sentinel string with zero results.
- Both modes.

**Tests.**
- `ChatErrorStateTests` — every failure class maps to the right `ChatErrorState`; recovery action wires to the right handler.
- Snapshot tests for each card.

**Privacy check.** Error events emit `{ turnId, errorClass: enum, isRecoverable, recoveryTaken? }` only. Raw `rawError` strings from `chatAgentError` are gated through an error classifier that maps to enum cases before any analytics emit.

**Acceptance.**
- Each failure class shows a card with a working recovery CTA. No more ad-hoc red banners.
- PostHog `chat.turn.completed` `outcome` aligns with the displayed error state.
- Both modes.

**Rollback.** Each card is independently revertable behind a per-state flag during initial rollout.

---

## PR 5 — `saveMessage` vs. poll race fix

**Problem.** Race notes at `ChatProvider.swift:2125` ("poll can run while saveMessage() is still in-flight — see the race note below") and `:2790` flag a known race. Five `saveMessage` call sites exist: `:2253, :2293, :2547, :2809, :2924`. Five sites is not normal — each likely represents a distinct message-lifecycle state (user msg / AI partial / AI final / error / attachment). Likely cause of duplicate or "ghost" messages.

**Scope.**
- **Step 1 (no code yet): document why each of the five `saveMessage` call sites exists.** Add this characterization to the PR description. Do not collapse lifecycle states casually — collapsing two call sites that look similar can mask a different race.
- **Step 2: write the reproducer test before any fix.**
- **Step 3: apply a narrow synchronization fix.** Likely shape: per-conversation `AsyncSemaphore`, an in-flight save guard, or a `lastSavedTurnId` the poll respects. Choose only after reading the race notes in full.
- **Call-site consolidation is deferred to V2** unless required to make the narrow race fix work. If consolidation is required, the PR description must justify why.

**Local verification gate.**
- Standard 5-step.
- `agent-swift`-driven 20 back-to-back turns. After, query the named bundle's `omi.db` `messages` table and assert zero duplicate `messageId`. Screenshot the count query.
- Both modes (same persistence path).

**Tests.**
- `MessagePersistenceRaceTests` — fake `APIClient.saveMessage` resolves after the poll fires; assert no duplicate or removal.

**Privacy check.** Test fixtures use synthetic content only.

**Acceptance.**
- Reproducer fails on current `main`, passes after fix.
- Per-call-site rationale documented in the PR description.
- 20-turn smoke produces zero duplicates / zero missing.

**Rollback.** Single synchronization primitive — narrow revert.

---

## PR 6 — Prompt ↔ schema regression tests

**Problem.** `agenticQA` (`ChatPrompts.swift:474-596`) hard-codes table names, column names, and SQL snippets. A schema migration that renames a column silently breaks chat — the model emits the old SQL and returns errors the user reads as "the AI is dumb".

**Scope.**
- `PromptSchemaConsistencyTests`:
  - Parse SQL snippets from `agenticQA` and `agenticQACompact`.
  - Validate every table/column reference against live `omi.db` introspection (reuse the path at `ChatProvider.swift:1504-1523`).
  - Validate every tool name in the prompt `<tools>` block exists in the actual tool registry the bridge wires up.
  - Validate every starter prompt's claimed capability against the active mode's tool set (overlaps with PR 2 — the test lives here, the policy lives there).

**Local verification gate.** Standard 5-step build; test target run only. No UI.

**Tests.** The test itself.

**Privacy check.** N/A.

**Acceptance.** Passes on current local worktree. Fails if a column is renamed, a tool is removed, or a starter prompt claims a missing capability.

**Rollback.** Test-only. Never revert.

---

## PR 7 — Scenario / eval tests across `piMono` + `userClaude`

**Problem.** Unit tests catch component bugs; they do not catch "chat feels broken end-to-end". The 80% target lives at the flow level.

**Scope.**
- Scenario harness in `desktop/Desktop/Tests/Scenarios/` driven by `agent-swift` against the named bundle.
- **Fixture seeding script** at `desktop/scripts/seed-chat-reliability-fixtures.sh`:
  - Hardcodes the dedicated chat-reliability eval Firebase UID provisioned in PR 0a.
  - **Refuses to run if the signed-in UID does not match** — top-of-script assertion exits non-zero with a clear message.
  - Idempotent: each scenario deletes its prior fixtures before reseeding, identified by sentinel tag `source: "chat-reliability-fixture"`.
  - Teardown command (`desktop/scripts/teardown-chat-reliability-fixtures.sh`) wipes all `source: "chat-reliability-fixture"` records.
- Seeded fixtures:
  - One known memory
  - One known active task
  - One known completed task
  - A no-result sentinel ("query this string, expect zero results")
  - A semantic-search fixture if feasible
  - A daily-recap fixture if feasible
- Initial scenarios — each runs once per mode (`piMono`, `userClaude`):
  1. Personal fact recall
  2. Daily recap
  3. Task create / list / complete
  4. Semantic search
  5. Empty-result graceful response (no fabrication)
  6. Stall recovery (PR 1 + PR 3 + PR 4 verified end-to-end)
  7. Auth recovery (PR 4)
  8. Mode parity (same prompt, both modes succeed)
- Each scenario emits `chat.scenario.run` with `ChatScenarioRunPayload { scenarioId, mode, outcome, durationMs }`.

**Local verification gate.**
- Standard 5-step.
- Full suite green in both modes.
- Evidence tarball at `/tmp/chat-reliability-v1/scenarios/` containing one screenshot per scenario per mode.

**Tests.** This *is* the test PR.

**Privacy check.** Scenario fixtures are synthetic. Redaction allow-list extended for `ChatScenarioRunPayload` only.

**Acceptance.**
- Suite green twice in a row (no flakes) in both modes before merge.
- Seven consecutive nightly green runs required for V1 exit (see V1 exit gate).

**Rollback.** Test-only.

---

## PR 8 — Bridge heartbeat protocol

**Problem.** PR 1's client detector cannot distinguish "model is slow" from "bridge is dead". A bridge-emitted heartbeat closes that gap and surfaces upstream stalls *before* the first delta.

**Scope.**
- Add `HeartbeatMessage` to `desktop/agent/src/protocol.ts`:
  ```ts
  export interface HeartbeatMessage { type: "heartbeat"; turnId: string; uptimeMs: number; upstreamLastEventMs: number }
  ```
- Node bridge emits a heartbeat every **5 seconds** while a turn is in flight. (Tuned in PR 9.)
- Swift `AgentBridge` parses the message. Verify graceful handling of unknown message types as a precursor — if missing, fix it first.
- `StallDetector` (PR 1) gains two new states:
  - `.upstreamSlow` — bridge alive (heartbeat arriving), no model output for `slowGapMs`.
  - `.bridgeUnresponsive` — no heartbeat for **>12s** (the bridge-unresponsive threshold). Tuned in PR 9.

**Local verification gate.**
- Standard 5-step.
- Use the PR 0b fake bridge to inject artificial upstream delay → confirm `.upstreamSlow` UI within `slowGapMs`.
- Use the PR 0b crash scenario → confirm `.bridgeUnresponsive` UI within 12s.
- Screenshots of both. Both modes.

**Tests.**
- `desktop/agent/tests/heartbeat.test.ts` — bridge emits heartbeats at 5s ± jitter while a turn is active; stops on turn end.
- Swift `BridgeHeartbeatTests` — missing heartbeat for >12s sets `.bridgeUnresponsive`; arriving heartbeats reset the bridge-health timer independently from the inter-event gap timer.
- Back-compat: Swift tolerates the heartbeat type disappearing (older bridge) without crashing.

**Privacy check.** Heartbeat payload carries `{ turnId, uptimeMs, upstreamLastEventMs }`. No content.

**Acceptance.** Simulated upstream stall produces `.upstreamSlow` within 8s (vs. PR 1's 20s for `.stalled`). Killed bridge produces `.bridgeUnresponsive` within 12s.

**Rollback.** Client must tolerate the heartbeat message disappearing if the bridge is rolled back — verified in tests.

---

## PR 9 — Sprint exit review + threshold tuning

**Scope.** After at least 5 days of telemetry post-PR 8 merge, pull the production dashboard data (filtered `build_dev_bundle != true`) and set:
- `slowGapMs = p90(interEventGapsMs | outcome = completed)`
- `stalledGapMs = p99(interEventGapsMs | outcome = completed)`
- Per-`piMono`-tool timeouts at `p95(toolDurationsMs[name] | outcome = completed) × 1.5`
- Heartbeat interval and `bridgeUnresponsive` threshold (default 5s / 12s) confirmed or adjusted based on observed jitter.

**Local verification gate.** Standard 5-step build check. No new code paths.

**Tests.** Existing tests adjust to new threshold values.

**Acceptance.** Constants updated only. Dashboard link in the PR body. No other changes.

---

## V1 exit gate

V1 is done only when **all** of:

1. PR 0a dashboard live for ≥7 days post-PR 8 merge.
2. **`like_ratio` on `bridgeMode = piMono, build_dev_bundle != true` ≥ 75%.** Target remains 80%. **If V1 exits below 80%, V2 must include a documented "close the remaining gap" workstream as PR 10 or earlier.**
3. `outcome = .timeout` rate < 2% of turns.
4. `outcome = .errored` rate < 1% of turns.
5. Zero `chat.turn.completed` events where any tool row was still `.running` at turn end.
6. PR 7 scenario suite green for 7 consecutive nightly runs in both modes.
7. No private or raw content appears in any production telemetry (audited by `AnalyticsRedactionTests` + a manual PostHog spot check at exit).
8. No known silent-hang reproducer remains open.

If any of 3 / 4 / 5 / 6 misses, V1 is **not** done — open a diagnostic PR against the worst offender before declaring exit.

---

## V1 hard exclusions

Do **not** include these in V1:
- No file/code-read tool added to `piMono`. (Discussed; lives in V3 with security review.)
- **No backend code changes in V1. Backend behavior is treated as external/stable for this desktop-client sprint. Any backend-required change becomes a separate explicit exception, justified in the PR.**
- No broad prompt rewrite. (PR 2 honesty pass is the only prompt edit.)
- No full `userClaude` / Claude Code tool execution contract. (V2.)
- No major memory system redesign.

---

# V2 — Runtime Hardening and Recovery

**Theme.** Make chat hard to break.
**Goal.** Make every turn durable and self-healing across restart, sleep/wake, bridge restart, token refresh, network drop, partial response, cancelled turn, mode switch, SQLite lock, and save failure.

**PR-sized milestones:**

10. Formal chat-turn state machine (explicit states: `idle, queued, starting, streaming, usingTool, slow, stalled, recovering, completed, failed, cancelled, orphaned`)
11. Durable local turn ledger (`turnId, conversationId, bridgeMode, startedAt, finalizedAt, state, lastEventAt, toolCalls, retryCount, persistenceState`)
12. Bridge restart + resume recovery
13. Auth refresh recovery
14. `userClaude` tool execution contract (timeout, retry, idempotency, privacy level, max result size, fallback message)
15. Retry and backoff policy
16. Offline / degraded-mode handling
17. Conversation reconciliation (server ↔ local truth)
18. Crash / turn correlation
19. Runtime soak tests
20. **Reliability checklist in PR template** (moved up from V4 — cheap leverage)
21. "Close the 5-point gap" workstream if V1 exited below 80% (conditional)

**V2 exit gates:**
- ≥99% of turns reach a terminal state.
- Bridge-crash recovery success >95%.
- Orphaned turns <0.5%.
- Zero known duplicate / missing message reproducers.
- Zero raw user-facing error strings in normal mode.
- 100-turn soak test passes twice in both modes.

---

# V3 — Premium Assistant UX and Quality

**Theme.** Make the app feel like a polished assistant, not a dev tool.
**Goal.** Approach ChatGPT/Claude-level clarity, mode awareness, grounded answer quality, and user trust.

**PR-sized milestones:**

22. Capability manifest + router (the source of truth for what each mode can do)
23. Mode-aware assistant UX (UI and prompts generated from the manifest)
24. Tool provenance in answers ("from your memories, last Tuesday…")
25. No-data and low-confidence answer policy
26. Memory / data quality scoring
27. Eval-driven answer-quality suite
28. Prompt-quality hardening
29. Long-running task UX
30. Polished chat states (typing indicator, partial-message recovery, animation polish)
31. Product quality review (cross-functional)

**Capability matrix (locked by PR 22):**

| Capability | `piMono` | `userClaude` |
|---|---|---|
| Memories | ✓ | ✓ |
| Tasks | ✓ | ✓ |
| Daily recap | ✓ | ✓ |
| Screen history | ✓ | ✓ |
| File metadata | ✓ | ✓ |
| File contents | ✗ | ✓ |
| Code reading | ✗ | ✓ |
| Bash / write tools | ✗ | ✓ |
| Project working directory | ✗ | ✓ |

**V3 goals:**
- UI and prompts generated from the active capability manifest. `piMono` never advertises file/code reading.
- Answers show provenance when grounded in local data.
- No-data answers are clear and non-hallucinated.
- Eval pass rate ≥95% in both modes.
- `piMono` and `userClaude` like ratios both ≥80%.

---

# V4 — Assistant Platform Maturity

**Theme.** Make reliability continuous.
**Goal.** Operate chat reliability like a platform, not a one-time sprint.

**PR-sized milestones:**

32. Canary release framework
33. Reliability dashboard pack (by mode, tool, error class, app version, scenario)
34. Alerting and regression detection
35. Automated nightly reliability suite (scenario harness running on CI hardware)
36. Feedback triage loop (cluster 👎 by error class)
37. Release rollback runbook (tested end-to-end)
38. Quarterly prompt / tool audit (calendared)

**V4 exit gates:**
- Nightly reliability suite automated and green.
- Regression alerts live with documented and tested rollback.
- Feedback clustered by failure mode.
- Dashboard views exist by mode, tool, error class, app version, and scenario.

---

## Execution guidance

- Implement V1 now. Start with **PR 0a and PR 0b in parallel** — they are independent.
- Do not implement V2 / V3 / V4 work inside V1, including the temptation to "fix something small" outside V1 scope.
- Every PR runs the local verification workflow above. Skipping is not a senior-engineer shortcut; it is the failure mode the sprint exists to prevent.
- V1 fixes current pain and proves the metric movement.
- V2 hardens the runtime.
- V3 makes the assistant experience premium.
- V4 makes reliability continuous.

---

## Locked values (fill in during PR 0a)

These are recorded here once provisioned. Do not start PR 7 until these are present.

| Value | Lookup |
|---|---|
| Chat-reliability eval Firebase UID | **`rg0PvY9mhKRARcYxkHHYh4iAkc12`** — user's personal account; data mixing accepted for V1. **Before this branch ever upstreams to `BasedHardware/omi`, swap to a dedicated `omi-eval@…` UID** — the personal UID identifies a real user and shouldn't ship in a public repo. |
| PostHog source-of-truth dashboard | `https://us.posthog.com/project/302298/dashboard/1624254` (14 insights, retrofit `build_dev_bundle != true` filter in PR 0a — see notes below on `!=` vs `=`) |
| PostHog production dashboard view filter | `build_dev_bundle != true` (NOT `= false` — HogQL treats missing ≠ false; `= false` would exclude every event predating PR 0a's emission) |
| PostHog PR validation dashboard view filter | `build_dev_bundle = true AND build_git_sha = <PR SHA>` |
| HMAC user-id salt — environment variable | **`OMI_TELEMETRY_HMAC_SALT`** |
| HMAC salt — dev/local fallback | Literal string `dev-local-salt-do-not-use-in-prod` (warn at startup if unset OR if set-but-equals-this-literal; redaction tests assert prod doesn't use this) |
| PostHog property prefix convention | `build_*` for build/release metadata (`build_dev_bundle`, `build_bundle_id`, `build_app_name`, `build_git_sha`, `build_branch`, `build_environment`). Verified against PostHog's actual property inventory (0 of 159 properties use `omi_*`; the existing convention is domain-prefix `chat_*`/`floating_*`/`memory_*` or bare names `app_name`/`app_version`/`build`/`build_number`). `build_app_name` deliberately differs from the existing bare `app_name` to avoid collision. Note: bare `build` (9 events / 7 days) and `build_number` (1 event / 7 days) coexist with the `build_*` prefix without technical collision — distinguishable property names — but PR 0a investigates whether either is vestigial (likely redundant with PostHog's auto-captured `$app_build`) and deprecates if so. |
| Heartbeat interval default | 5s (tuned in PR 9) |
| Bridge-unresponsive threshold default | 12s (tuned in PR 9) |
| `slowGapMs` default | 8000 (tuned in PR 9) |
| `stalledGapMs` default | 20000 (tuned in PR 9) |

**Embedded individual insights (for reference; all are tiles on the source-of-truth dashboard above):**

- [KPI] Weekly thumbs_up/down/% positive — `https://us.posthog.com/project/302298/insights/Gp54lX8e`
- [KPI] 28d rolling % positive — `https://us.posthog.com/project/302298/insights/x82ya40I`
- [KPI] 28d rolling % positive (clean) — `https://us.posthog.com/project/302298/insights/5BZ9xiaI`
- [Scoreboard] Last 14d vs Prior 14d — `https://us.posthog.com/project/302298/insights/cWl5O56I`
- [Release] Daily % positive (60d tracker) — `https://us.posthog.com/project/302298/insights/t2JTkmjK`
- [Validation] thumbs_up vs thumbs_down daily counts — `https://us.posthog.com/project/302298/insights/KkgTTmI2`
- [Diagnostic] ratio by app version — `https://us.posthog.com/project/302298/insights/pRG3hruC`
- [Reliability] chat_agent_error rate — `https://us.posthog.com/project/302298/insights/LXEMscAj`
- [Reliability] PTT completion rate — `https://us.posthog.com/project/302298/insights/5l2a83hh`
- [Reliability] tool-call/agent-query/error volume — `https://us.posthog.com/project/302298/insights/O7I9Iljr`
- [Cohort] new-user % positive in first 7 days — `https://us.posthog.com/project/302298/insights/sHSaDIN6`
- [Pending] Chat Unavailable Shown (placeholder) — `https://us.posthog.com/project/302298/insights/J38pgyjd`
- [Pending] Chat Scroll Stuck Detected (placeholder) — `https://us.posthog.com/project/302298/insights/TQbRGiCG`
- [Pending] tool-call/agent-query START events (placeholder) — `https://us.posthog.com/project/302298/insights/mJZBso3r`
