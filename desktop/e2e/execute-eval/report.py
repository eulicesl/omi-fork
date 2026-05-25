#!/usr/bin/env python3
"""
Eval report aggregator. Reads a JSONL produced by run-eval.sh and prints:

  - Aggregate pass rate.
  - Per-category pass rate.
  - Per-task pass rate.
  - Gate verdict: PASS when aggregate >= 80%.
  - For repeated-trial suites, also require no task < 60%.

Usage: python3 report.py results/latest.jsonl
"""

from __future__ import annotations
import argparse, json, sys
from collections import defaultdict
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("path", type=Path)
    args = ap.parse_args()

    by_task: dict[str, list[str]] = defaultdict(list)
    by_category: dict[str, list[str]] = defaultdict(list)
    by_task_category: dict[str, str] = {}

    with args.path.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row.get("status") == "skipped":
                continue
            result = row.get("result")
            if result not in ("pass", "fail"):
                continue
            task_id = row["task_id"]
            category = row["category"]
            by_task[task_id].append(result)
            by_category[category].append(result)
            by_task_category[task_id] = category

    total = sum(len(v) for v in by_task.values())
    if total == 0:
        print("No trials in", args.path)
        return 2
    aggregate_pass = sum(r == "pass" for v in by_task.values() for r in v) / total

    print(f"\nExecute reliability eval — {args.path}")
    print(f"  total trials:    {total}")
    print(f"  aggregate pass:  {aggregate_pass:.1%}")
    print()

    print("Per category:")
    for cat in sorted(by_category):
        rs = by_category[cat]
        r = sum(x == "pass" for x in rs) / len(rs)
        print(f"  {cat:14s}  {r:6.1%}   ({sum(x == 'pass' for x in rs)}/{len(rs)})")
    print()

    print("Per task:")
    weakest_rate = 1.0
    weakest_task = ""
    for task_id in sorted(by_task):
        rs = by_task[task_id]
        r = sum(x == "pass" for x in rs) / len(rs)
        cat = by_task_category[task_id]
        flag = "" if r >= 0.60 else "  ←  below 60% floor"
        print(f"  [{cat:10s}] {task_id:38s}  {r:6.1%}   ({sum(x == 'pass' for x in rs)}/{len(rs)}){flag}")
        if r < weakest_rate:
            weakest_rate = r
            weakest_task = task_id
    print()

    min_trials_per_task = min((len(v) for v in by_task.values()), default=0)
    use_task_floor = min_trials_per_task >= 2
    gate_pass = aggregate_pass >= 0.80 and (not use_task_floor or weakest_rate >= 0.60)
    floor_text = " AND no task < 60%" if use_task_floor else ""
    print(f"Gate: aggregate >= 80%{floor_text}")
    print(f"  aggregate {aggregate_pass:.1%}, weakest task {weakest_task} at {weakest_rate:.1%}")
    print(f"  verdict:  {'PASS ✓' if gate_pass else 'FAIL ✗'}")
    return 0 if gate_pass else 1


if __name__ == "__main__":
    sys.exit(main())
