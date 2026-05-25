# Execute Reliability Eval

How we prove the proactive-task **Execute** path lands ≥ 8 / 10 trials.

See [`desktop/docs/TASK_EXEC_RELIABILITY_REVIEW.md`](../../docs/TASK_EXEC_RELIABILITY_REVIEW.md) §5 for the methodology and [`desktop/docs/TASK_EXEC_RELIABILITY_SPRINTS.md`](../../docs/TASK_EXEC_RELIABILITY_SPRINTS.md) for the sprint plan that produced this harness.

## Files

| File | Purpose |
|---|---|
| `tasks.local.json` | 10 deterministic local file-writing tasks under `/tmp/omi-execute-eval/`. This is the fast proof gate for ≥ 8 / 10 completion before external-account tasks are measured. |
| `tasks.json` | 30 representative tasks with ground truth. Split 6 per category (Send / Schedule / Draft / Create file / Open URL), half happy-path and half rough-edges. Requires real external graders before it can be treated as product proof. |
| `run-eval.sh` | Driver: boots a named bundle, fires each task via the local HTTP automation bridge, polls pill status, captures transcript/evidence, dispatches to a per-category grader. |
| `graders/` | One grader per category. Hits the relevant API (Telegram bot, Slack, Gmail, GCal, `stat`) to verify ground truth. **You must fill in API keys / tokens before running** — see `graders/.env.example`. |
| `report.py` | Aggregates results into per-task pass rate, per-category pass rate, and aggregate. Prints the gate verdict: `PASS` when aggregate ≥ 80%; repeated-trial suites also require no single task < 60%. |

## Running

```bash
# Fast local proof: 10 deterministic local file tasks. The default task file is
# tasks.local.json and does not require agent-swift or external credentials.
./run-eval.sh --trials 1 --bundle omi-execute-eval --seed-from-bundle com.omi.computer-macos

# Full external-account proof needs grader credentials (one-time, .env never committed).
cp graders/.env.example graders/.env
$EDITOR graders/.env

# Run the broader representative set once those graders are implemented.
./run-eval.sh --trials 5 --bundle omi-execute-eval --tasks tasks.json

# Print the report.
python3 report.py results/latest.jsonl
```

The local proof pass (10 tasks × 1 trial) is the current merge gate for the
automation harness. A full external pass (30 tasks × 5 trials × ~30 s each)
takes ~75 minutes once the non-file graders are real.

## Snapshot pipeline

We hold three snapshots in `results/`:

- `pre-sprint-1.jsonl` — baseline against `main` *before* the reliability work, so the uplift numbers in the review document have a real anchor.
- `post-sprint-2.jsonl` — after Sprints 1 + 2 land. Gate: aggregate ≥ 80%.
- `post-sprint-3.jsonl` — after Sprint 3 lands. Gate: aggregate ≥ 85% AND per-task floor ≥ 70%.

Each snapshot needs ≥ 150 trials (30 × 5). Re-run on any change to `ProactiveTaskExecute.swift`, `AgentPill.swift`, `ExecuteVerificationGate.swift`, `ExecutePreflight.swift`, or the agent bridge.

## What "ground truth" looks like

Each task in `tasks.json` carries:

- `id` — short slug, used as the eval ID.
- `category` — `send` / `schedule` / `draft` / `create_file` / `open_url`.
- `difficulty` — `happy_path` / `rough_edges`. Half the set is each.
- `notification` — exact `{title, message, context}` to inject via the automation bridge. Skips the real `TaskAssistant` promotion loop so trials are deterministic.
- `ground_truth` — what the grader checks. Shape depends on `category`:
  - **send** → `{platform: "telegram"|"slack"|"messages"|"gmail", recipient, expected_substring}` — the grader reads the latest message in that thread and asserts substring match.
  - **schedule** → `{calendar, title, expected_window_iso}` — grader fetches events in the window and asserts the title appears.
  - **draft** → `{platform, expected_substring}` — grader reads the drafts folder.
  - **create_file** → `{path, expected_substring}` — grader `stat`s + `head`s.
  - **open_url** → `{expected_url_prefix}` — grader inspects `lsof` for the Chrome PID or reads the active tab via the chrome extension.

A trial **passes** when (a) the pill is `.done`, (b) the verification gate (P2) reports `verified`, AND (c) the grader confirms ground truth. (a) and (b) are read from the analytics row (see Sprint 4 telemetry below); (c) is the per-category grader.

## Telemetry

Sprint 4 extends `AnalyticsManager.chatAgentQueryCompleted` with:

- `executeMode: Bool` — true when the run originated from `spawnForNotification`.
- `actionClass: String` — `"actionable"` / `"research"`.
- `writeToolCalled: Bool` — P2 gate input.
- `verifiedByGate: Bool` — P2 gate verdict.
- `verifiedByTurn: Bool?` — P8 verification turn verdict; nil when skipped.
- `retryCount: Int` — number of attempts (1 on happy path).
- `preflightOutcome: String?` — `"ready"` / `"needs.launchTelegram"` / etc.

This lets us compute a real-world reliability proxy from Posthog without the graded set, useful as a leading indicator between graded runs.
