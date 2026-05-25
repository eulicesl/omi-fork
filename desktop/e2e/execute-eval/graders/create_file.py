#!/usr/bin/env python3
"""
Grader for `create_file` tasks.

Reads a task JSON object on stdin (one of the entries from tasks.json) and
asserts the ground_truth file exists and contains the expected substring.
Exit 0 on pass, 1 on fail.
"""

from __future__ import annotations
import json, os, sys
from pathlib import Path


def main() -> int:
    task = json.load(sys.stdin)
    gt = task.get("ground_truth", {})
    path = os.path.expanduser(gt.get("path", ""))
    expected = gt.get("expected_substring", "")

    if not path:
        print("grader: no ground_truth.path", file=sys.stderr)
        return 1

    p = Path(path)
    if not p.exists():
        print(f"grader: file missing at {path}")
        return 1

    try:
        head = p.read_text(errors="replace")[:4096]
    except Exception as e:
        print(f"grader: could not read {path}: {e}")
        return 1

    if expected and expected not in head:
        print(f"grader: substring '{expected}' not in {path}")
        return 1

    print(f"grader: ok — {path} ({p.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
