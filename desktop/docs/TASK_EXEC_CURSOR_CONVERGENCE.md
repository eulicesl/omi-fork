# Task-Execution Reliability ↔ Cursor Overlay — Convergence Decision

**Status:** Decided (Option A + reattachment). Implementation in progress.
**Date:** 2026-05-31
**Author:** Eulices (with Claude)
**Context:** After syncing this branch to `BasedHardware/omi` (181 commits), upstream
PR #7453 ("replace floating pill bar with an AI cursor") + #7493 ("semantic /action
command API") landed. This doc records why our task-execution reliability work
(P1–P9 + the 429 backoff) keeps its engine and gets *reattached*, rather than being
ported onto the new computer-use path.

---

## What changed upstream

`#7453` replaced the **visible** floating control bar with a full-screen **cursor
overlay** (`CursorPTTOverlayManager` + `CursorBubbleView`) and added a voice/chat
**computer-use** path (`OmiActionExecutor` + `CuaActionDriver` + `OmiComputerUseTool`).

Critically, our feature's surface was **displaced, not deleted**:

- `FloatingControlBarView` (which hosts the **Execute** button) is still compiled,
  but its window is now kept **hidden** — `presentNotification`
  (`FloatingControlBarWindow.swift:1386`) calls `CursorPTTOverlayManager.showNotification`
  for the visible bubble and only syncs the hidden bar's state "so the dismiss queue
  and analytics remain consistent." It never orders the bar front.
- The visible notification surface is the cursor overlay's **amber bubble**
  (`phase == .notifying`). It has **no Execute affordance** — `CursorBubbleView` has no
  button/tap for notifications, and `openNotificationAsChat` is wired only from the
  hidden `FloatingControlBarView:176`.
- Net: **proactive task notifications currently have no execution path in the visible
  UI at all.** The Execute button was removed and nothing replaced it.

## The two execution models

| | **Pill Execute** (ours: P1–P8 + backoff) | **Computer-use** (upstream) |
|---|---|---|
| Trigger | Proactive task notification | Voice/chat: user asks "do X" |
| Engine | pi-mono **agent** loops with tools (bash/osascript/playwright) | Replays scripted steps (click/type/shortcut/scroll/openApp) via CGEvents/AX |
| Plan | Agent decides autonomously, multi-turn | One `<computer_use>` block in a single reply |
| Completion | gate → programmatic **verification turn** → retry | "all steps ran without throwing" |
| Verifiability | High (warm tool session, reads back proof) | Low (a click returns nothing) |

### Decisive findings

1. **Computer-use plans are generated through `ChatProvider.sendMessage`**
   (`ChatProvider.swift:1703` injects `OmiComputerUseTool.systemPromptFragment`; when a
   reply contains `<computer_use>`, `ChatProvider.swift:2768` fires the executor). Our
   429 backoff lives in the *pill* retry loop, **not** generic `sendMessage` — so
   **computer-use still has the same 429 fragility** we fixed for pills. (Their bug to
   fix; flagged, not ours.)
2. **No proactive notification can reach computer-use.** Its only trigger is a chat/voice
   reply containing `<computer_use>`.
3. **The two paths share no execution code.** Our reliability logic is welded to
   `AgentPillsManager.spawn → provider.sendMessage`; computer-use is a separate
   generate-then-replay-clicks substrate with no warm session to verify against.

## Decision: Option A + reattachment

**Keep** the hardened pill engine (P1–P8 + 429 backoff) as the **proactive task
execution engine**, reachable headlessly via the `/execute/spawn` automation route, and
**reattach a user-facing trigger** to the cursor-overlay notification — the actual gap.

### Why not Option B (port onto computer-use)

Computer-use and proactive-task Execute are **different products** (user-present voice
scripting vs. background autonomous task completion). Porting gate/verify/retry there
would not serve the proactive use case, and computer-use's click model is the *hardest*
thing to verify — precisely our strength, wasted. Option B is a high-cost rewrite for a
worse fit. Revisit convergence only if the product later merges the two interaction
models.

## Interaction model: **click-to-confirm** (not auto-execute)

The reattached affordance preserves the **explicit-intent** semantics of the removed
Execute button: a task notification (`assistantId == "task"`) shows an **Execute**
action on the cursor bubble; the agent runs only on user click. Auto-executing
background tasks that send real messages / create real events without consent is a
safety regression and is rejected.

## Implementation plan

1. **Extract the dispatch logic** currently inlined in `FloatingControlBarView`'s button
   action (resolveModel → buildQuery → `directDesktopAction` fast path →
   `ExecutePreflight.check` → `spawnForNotification`) into a single reusable, testable
   entry point — `ProactiveTaskExecute.dispatch(notification:)` returning a typed
   outcome (`.directAction` / `.needsPreflight(Requirement)` / `.spawned(pill)` /
   `.duplicate`). Both the (hidden) legacy button and the new cursor affordance call it.
   *DRY + unit-testable decision logic.*
2. **Add the Execute affordance** to the cursor overlay's `.notifying` bubble for task
   notifications (`CursorBubbleView` + a tap/`Execute` button; `CursorPTTOverlayManager`
   gains the current notification + a tap handler).
3. **Surface progress/result in the overlay**: on Execute, transition to an execution
   state bound to the spawned `AgentPill` — show `pill.latestActivity` (incl. "Rate
   limited — retrying in 15s…") and the terminal result ("Done — verified…" /
   "Couldn't: needs Slack sign-in").
4. **Tests**: unit-test the extracted `dispatch` decision logic and the actionable
   gate; the overlay UI + progress surfacing verified at runtime.

### Out of scope / follow-ups

- **#4 lint debt** in `DesktopAutomationBridge` route dispatcher — before PR.
- **#2 P9 stall detector** — only if the pill path survives review; otherwise reframed.
- **Eval re-baseline** — blocked on quota (BYOK key or quieted bundle); see
  `TASK_EXEC_RELIABILITY_SPRINTS.md` Sprint 4.
- **Computer-use 429 hardening** — generalize the backoff to `sendMessage` if upstream
  wants it (their feature).
