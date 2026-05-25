#!/usr/bin/env python3
"""
Grader for `send` tasks. Dispatches to a per-platform check:

  telegram → Bot API getUpdates / messages.history
  slack    → conversations.history
  messages → reads ~/Library/Messages/chat.db (requires Full Disk Access)
  gmail    → Gmail API users.messages.list

Reads the task JSON object on stdin, prints a one-line evidence string, and
exits 0 on pass, 1 on fail. Skips with exit 2 if the platform credentials
are missing — run-eval.sh's outer logic treats skip as fail-by-default.

NOTE: this is the SCAFFOLD. The real API plumbing is intentionally left as
stubs — the team needs to wire in their own creds before running the eval.
"""

from __future__ import annotations
import json, os, sys


PLATFORM_DISPATCH = {
    "telegram": "_grade_telegram",
    "slack":    "_grade_slack",
    "messages": "_grade_imessage",
    "gmail":    "_grade_gmail",
}


def _grade_telegram(gt: dict) -> tuple[bool, str]:
    bot = os.environ.get("TELEGRAM_BOT_TOKEN")
    if not bot:
        return False, "no TELEGRAM_BOT_TOKEN; skipping (counts as fail until configured)"
    # TODO: hit https://api.telegram.org/bot$TOKEN/getUpdates, find latest
    # message in the recipient's chat, assert substring match.
    return False, "telegram grader stub — implement Bot API check"


def _grade_slack(gt: dict) -> tuple[bool, str]:
    token = os.environ.get("SLACK_USER_TOKEN")
    if not token:
        return False, "no SLACK_USER_TOKEN; skipping"
    # TODO: GET /conversations.history?channel=…&limit=1
    return False, "slack grader stub — implement conversations.history check"


def _grade_imessage(gt: dict) -> tuple[bool, str]:
    # TODO: open ~/Library/Messages/chat.db (SQLite), find latest message in
    # the recipient's handle, assert substring match. Requires Full Disk Access.
    return False, "imessage grader stub — implement chat.db check"


def _grade_gmail(gt: dict) -> tuple[bool, str]:
    refresh = os.environ.get("GMAIL_REFRESH_TOKEN")
    if not refresh:
        return False, "no GMAIL_REFRESH_TOKEN; skipping"
    # TODO: OAuth refresh, then users.messages.list q=newer_than:5m
    return False, "gmail grader stub — implement Gmail API check"


def main() -> int:
    task = json.load(sys.stdin)
    gt = task.get("ground_truth", {})
    platform = gt.get("platform", "")
    fn = PLATFORM_DISPATCH.get(platform)
    if not fn:
        print(f"grader: unsupported platform {platform!r}")
        return 1
    passed, evidence = globals()[fn](gt)
    print(f"grader[{platform}]: {evidence}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
