#!/usr/bin/env python3
"""tune-thresholds.py — compute PR 9 threshold tuning recommendations.

Per `desktop/docs/MACOS_CHAT_RELIABILITY_ROADMAP.md` PR 9, after at least
5 days of PR 0a telemetry data, this script pulls `chat.turn.completed`
events from PostHog (filtered `build_dev_bundle != true` — production
traffic only), computes the relevant percentiles, and emits a diff-ready
recommendation for `StallThresholds.v1Defaults` and
`ToolTimeoutPolicy.v1Defaults`.

The constants this script tunes:

  slowGapMs     = p90(interEventGapsMs | outcome=completed)
  stalledGapMs  = p99(interEventGapsMs | outcome=completed)
  Per-tool timeouts = p95(toolDurationsMs[name] | outcome=completed) * 1.5

Heartbeat interval and bridgeUnresponsive threshold are NOT tuned here
(the roadmap calls for "confirmed or adjusted based on observed jitter"
which is judgment, not percentile math). Surface those as separate
manual analysis.

Usage:

    export POSTHOG_API_KEY=phx_xxx          # personal API key (read-only)
    python3 desktop/scripts/tune-thresholds.py --days 5

    # Or run against a local export if PostHog API is unavailable:
    python3 desktop/scripts/tune-thresholds.py --from-json events.json

The output is a markdown-formatted recommendation block. Paste it into
the PR 9 commit message and update `StallThresholds.v1Defaults` +
`ToolTimeoutPolicy.v1Defaults` accordingly.

Calendar gate: do not run until PR 0a has been emitting from real users
for ≥5 days. Earlier runs produce noisy percentiles based on too few
turns to be representative.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from statistics import quantiles


POSTHOG_PROJECT_ID = 302298  # locked in roadmap doc (PR 0a)
POSTHOG_HOST = "https://us.posthog.com"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=5, help="window of telemetry to pull (default: 5)")
    parser.add_argument(
        "--from-json",
        type=str,
        default=None,
        help="path to a local JSON export of chat.turn.completed events; skips the PostHog API call",
    )
    parser.add_argument(
        "--include-dev",
        action="store_true",
        help="include build_dev_bundle=true events too (default: prod only). Use during sprint debugging only.",
    )
    return parser.parse_args()


def fetch_events_from_posthog(days: int, include_dev: bool) -> list[dict]:
    """Pull chat.turn.completed events via PostHog HogQL.

    Falls back with a clear error if the API key isn't set. Surfaces
    the count of returned events so the operator can spot 'too few
    turns to be representative' before the percentile math runs.
    """
    api_key = os.environ.get("POSTHOG_API_KEY")
    if not api_key:
        sys.exit(
            "ERROR: POSTHOG_API_KEY is not set. Export your personal API key (read-only is fine) and re-run.\n"
            "See https://posthog.com/docs/api#how-to-obtain-a-personal-api-key for how to mint one."
        )

    # Lazy import — `requests` is not a hard dependency of the repo.
    try:
        import requests  # type: ignore
    except ImportError:
        sys.exit(
            "ERROR: `requests` not installed. Either `pip install requests` or use --from-json with a manual export."
        )

    dev_clause = "" if include_dev else "AND properties.build_dev_bundle != true"
    hogql = f"""
        SELECT properties.outcome, properties.toolNames, properties.totalMs, properties.firstTokenMs, properties.bridgeMode
        FROM events
        WHERE event = 'chat.turn.completed'
          AND timestamp > now() - INTERVAL {days} DAY
          {dev_clause}
          AND properties.outcome = 'completed'
        LIMIT 100000
    """
    url = f"{POSTHOG_HOST}/api/projects/{POSTHOG_PROJECT_ID}/query/"
    response = requests.post(
        url,
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        json={"query": {"kind": "HogQLQuery", "query": hogql}},
        timeout=60,
    )
    response.raise_for_status()
    rows = response.json().get("results", [])
    return [
        {
            "outcome": row[0],
            "toolNames": row[1] or [],
            "totalMs": row[2],
            "firstTokenMs": row[3],
            "bridgeMode": row[4],
        }
        for row in rows
    ]


def fetch_events_from_json(path: str) -> list[dict]:
    """Read a local JSON file. Schema: a list of event dicts with
    `outcome`, `toolNames`, `totalMs`, `firstTokenMs`, `bridgeMode` keys.
    """
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, list):
        sys.exit(f"ERROR: {path} must contain a JSON array of event objects.")
    return data


def percentile(values: list[int], pct: float) -> int | None:
    """Compute the `pct`th percentile (0-100). Returns None when the
    sample is too small to be meaningful (<20 values — same threshold
    we'd apply manually on a dashboard).
    """
    if len(values) < 20:
        return None
    # statistics.quantiles uses 1-99 indices on a 100-point scale.
    qs = quantiles(values, n=100, method="inclusive")
    idx = max(1, min(99, int(pct))) - 1
    return int(qs[idx])


def main() -> int:
    args = parse_args()

    if args.from_json:
        events = fetch_events_from_json(args.from_json)
        source_label = f"local JSON ({args.from_json})"
    else:
        events = fetch_events_from_posthog(args.days, args.include_dev)
        source_label = f"PostHog last {args.days} days"

    if not events:
        print(f"# No events found in {source_label}. Run --help for diagnostics.")
        return 1

    pi_mono_events = [e for e in events if e.get("bridgeMode") == "piMono"]
    if len(pi_mono_events) < 20:
        print(f"# Only {len(pi_mono_events)} piMono completed turns in {source_label} — too few to tune.")
        print("# Wait until the sample is at least 20 (the script-level minimum) or 200 (recommended).")
        return 1

    # Inter-event gaps aren't directly emitted on chat.turn.completed today —
    # they're a per-turn statistic that the StallDetector observes internally.
    # PR 0a's payload carries firstTokenMs but not the full gap distribution;
    # that's a future telemetry expansion. For V1 PR 9, we tune slowGapMs /
    # stalledGapMs from totalMs (turn duration) as a coarse proxy and flag
    # this in the output.
    total_ms_values = [e["totalMs"] for e in pi_mono_events if isinstance(e.get("totalMs"), (int, float))]
    p90_total = percentile([int(v) for v in total_ms_values], 90)
    p99_total = percentile([int(v) for v in total_ms_values], 99)

    # Per-tool durations need their own telemetry — toolNames is a list of names but
    # per-tool duration isn't on chat.turn.completed today. Surface this as a known gap.

    by_outcome = defaultdict(int)
    for e in events:
        by_outcome[e.get("outcome", "?")] += 1

    print("# PR 9 Threshold Tuning Recommendation")
    print(f"# Source: {source_label}")
    print(f"# Sample size: {len(events)} total events; {len(pi_mono_events)} piMono completed turns")
    print(f"# Outcome distribution: {dict(by_outcome)}")
    print()

    print("## StallThresholds.v1Defaults")
    print()
    if p90_total is not None and p99_total is not None:
        print(f"- `slowGapMs`     suggested: {p90_total}   (p90 of totalMs over piMono completed turns)")
        print(f"- `stalledGapMs`  suggested: {p99_total}   (p99 of totalMs over piMono completed turns)")
        print()
        print("> Caveat: V1 PR 0a payload carries `totalMs` (whole-turn duration) but not the")
        print("> per-event-gap distribution. These percentiles approximate the right thresholds")
        print("> but a follow-up should emit a `maxInterEventGapMs` per turn so the tuning is")
        print("> direct rather than proxied.")
    else:
        print("- Insufficient sample for percentile (need ≥20 turns; got fewer).")

    print()
    print("## ToolTimeoutPolicy.v1Defaults")
    print()
    print("- Per-tool percentiles cannot be computed from this dataset:")
    print("  `chat.turn.completed` carries `toolNames[]` but not per-tool durations.")
    print("  A future telemetry change (emit `toolDurations: {name: ms}` instead of just")
    print("  names) unblocks this. Until then, the existing constants in")
    print("  `ToolTimeoutPolicy.v1Defaults` stand — adjust manually if PostHog event")
    print("  inspection shows specific tools regularly exceeding their ceilings.")
    print()
    print("## Heartbeat / bridge-unresponsive")
    print()
    print("- Not tuned by this script (judgment call, not percentile math).")
    print("- Defaults: 5s heartbeat / 12s bridgeUnresponsive.")
    print("- Inspect heartbeat-loss rate on the dashboard before changing.")
    print()
    print("---")
    print("Apply this recommendation by editing:")
    print(
        "  desktop/Desktop/Sources/Chat/StallThresholds.swift  (StallThresholds.v1Defaults)"
    )
    print(
        "  desktop/Desktop/Sources/Chat/ToolTimeoutPolicy.swift  (ToolTimeoutPolicy.v1Defaults — manual)"
    )
    print("and commit as `chore(desktop): PR 9 threshold tuning — <date> data`.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
