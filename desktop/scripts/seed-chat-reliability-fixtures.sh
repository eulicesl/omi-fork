#!/bin/bash
# seed-chat-reliability-fixtures.sh — seed deterministic Firestore fixtures
# for the PR 7 chat-reliability scenario suite.
#
# Seeds five Firestore fixtures (all tagged `source: "chat-reliability-fixture"`)
# under the dedicated eval Firebase UID. Reach chat via the
# Firestore -> API (getActionItems/getMemories) -> local SQLite -> sync -> VM
# pipeline; runner triggers TasksStore.loadTasks() + AgentSyncService.syncTick()
# at scenario start.
#   1. memory                — "User Eulices is testing chat reliability fixtures"
#   2. active action_item    — "Verify scenario suite [chat-reliability-fixture]"
#   3. completed action_item — "Set up chat-reliability fixtures [chat-reliability-fixture]"
#   4. no-result sentinel    — action_item containing "ZZZ_NO_RESULTS_SENTINEL_XYZ_unique_string_99999"
#   5. daily-recap           — action_item created today
#
# The semantic-search fixture (scenario #4) lives in local SQLite only —
# screenshots are local-first; no Firestore->local pull path exists. Seeded
# in-process by ChatReliabilityFixtures.seedScreenshotFixture() (Swift).
#
# SAFETY:
#   - Hardcodes the V1 eval UID (rg0PvY9mhKRARcYxkHHYh4iAkc12). Personal account;
#     swap to a dedicated omi-eval UID before this branch upstreams to BasedHardware/omi.
#   - REFUSES to run unless the named-bundle (com.omi.omi-chat-reliability)
#     UserDefaults auth_userId matches that UID.
#   - REFUSES to run if backend/google-credentials.json is missing.
#   - Idempotent: deletes prior fixtures (tag-matched) before reseeding.
#   - Only writes inside users/<EVAL_UID>/<subcollection>/.
#
# Usage: seed-chat-reliability-fixtures.sh
set -euo pipefail

# ----- locked values -----------------------------------------------------------
EVAL_UID="rg0PvY9mhKRARcYxkHHYh4iAkc12"
EVAL_BUNDLE_ID="com.omi.omi-chat-reliability"
FIXTURE_TAG="chat-reliability-fixture"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CREDS="$REPO_ROOT/backend/google-credentials.json"
VENV_ACTIVATE="$REPO_ROOT/backend/venv/bin/activate"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--help]

Seeds five deterministic Firestore fixtures for the PR 7 chat-reliability
scenario suite. All fixtures carry source="${FIXTURE_TAG}" so the companion
teardown script can wipe them safely.

(The semantic-search screenshot fixture is seeded in-process by the
runner via ChatReliabilityFixtures.swift, not here — screenshots are
local-first and have no Firestore->local pull path.)

Guards (script exits non-zero with a clear message if any fail):
  - backend/google-credentials.json must exist at ${CREDS}
  - The named bundle ${EVAL_BUNDLE_ID} must currently be signed into UID
    ${EVAL_UID} (read via 'defaults read ${EVAL_BUNDLE_ID} auth_userId').

What it writes (under users/${EVAL_UID}/...):
  memories/<id>      — known memory
  action_items/<id>  — active task
  action_items/<id>  — completed task
  action_items/<id>  — no-result sentinel
  action_items/<id>  — daily-recap item created today

Idempotent: any docs already tagged source="${FIXTURE_TAG}" inside the eval
UID's subcollections are deleted before reseeding.

This script is safe to re-run. If you only want to clean up, run
teardown-chat-reliability-fixtures.sh instead.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage; echo; echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
esac

# ----- guard: credentials present ---------------------------------------------
if [[ ! -f "$CREDS" ]]; then
  echo "ERROR: missing Firebase Admin SDK credentials at:" >&2
  echo "       $CREDS" >&2
  echo "       Cannot seed fixtures without Firestore access. Aborting." >&2
  exit 3
fi

# ----- guard: signed-in UID matches eval UID ----------------------------------
SIGNED_IN_UID="$(defaults read "$EVAL_BUNDLE_ID" auth_userId 2>/dev/null || true)"
if [[ -z "$SIGNED_IN_UID" ]]; then
  echo "ERROR: could not read auth_userId from bundle '$EVAL_BUNDLE_ID'." >&2
  echo "       Is the named eval bundle installed and signed in?" >&2
  echo "       (Run ./run.sh with OMI_APP_NAME=omi-chat-reliability, then sign in.)" >&2
  exit 4
fi
if [[ "$SIGNED_IN_UID" != "$EVAL_UID" ]]; then
  echo "ERROR: signed-in UID does not match the locked eval UID." >&2
  echo "       Expected: $EVAL_UID" >&2
  echo "       Found:    $SIGNED_IN_UID  (bundle: $EVAL_BUNDLE_ID)" >&2
  echo "       Refusing to seed fixtures into the wrong account." >&2
  exit 5
fi

# ----- activate backend venv (Python is the established pattern) --------------
if [[ ! -f "$VENV_ACTIVATE" ]]; then
  echo "ERROR: backend venv not found at $VENV_ACTIVATE" >&2
  echo "       Create it per backend/CLAUDE.md before running this script." >&2
  exit 6
fi
# shellcheck disable=SC1090
source "$VENV_ACTIVATE"

echo "==> Seeding chat-reliability fixtures into users/$EVAL_UID/..."
echo "    credentials: $CREDS"
echo "    tag:         source=\"$FIXTURE_TAG\""
echo

python3 - "$CREDS" "$EVAL_UID" "$FIXTURE_TAG" <<'PY'
import sys
import time
import uuid
from datetime import datetime, timezone

import firebase_admin
from firebase_admin import credentials, firestore

creds_path, uid, tag = sys.argv[1], sys.argv[2], sys.argv[3]

cred = credentials.Certificate(creds_path)
try:
    firebase_admin.initialize_app(cred)
except ValueError:
    pass
db = firestore.client()

# Subcollections that may carry the fixture tag. `screenshots` retained
# here (not in the seed path below) because earlier seed runs may have
# written there; the idempotent cleanup pass should still find and remove
# those stale fixtures even though new runs no longer write them.
SUBCOLLECTIONS = ["memories", "action_items", "screenshots"]

user_ref = db.collection("users").document(uid)

# ----- 1. Idempotent teardown of any prior fixtures ---------------------------
deleted = 0
for sub in SUBCOLLECTIONS:
    q = user_ref.collection(sub).where("source", "==", tag)
    for doc in q.stream():
        print(f"  [delete] users/{uid}/{sub}/{doc.id}")
        doc.reference.delete()
        deleted += 1
print(f"  ({deleted} prior fixture doc(s) removed)\n")

now = datetime.now(timezone.utc)
now_iso = now.isoformat()
created_at_ts = firestore.SERVER_TIMESTAMP

def new_id(prefix: str) -> str:
    return f"fixture-{prefix}-{uuid.uuid4().hex[:12]}"

def write(sub: str, doc_id: str, payload: dict):
    payload = dict(payload)
    payload["source"] = tag
    payload["fixture_seeded_at"] = created_at_ts
    ref = user_ref.collection(sub).document(doc_id)
    ref.set(payload)
    print(f"  [write]  users/{uid}/{sub}/{doc_id}")

# ----- 2. Seed the six fixtures -----------------------------------------------

# (a) Known memory
mem_id = new_id("mem")
write("memories", mem_id, {
    "id": mem_id,
    "content": "User Eulices is testing chat reliability fixtures",
    "category": "fixture",
    "created_at": now_iso,
    "user_review": None,
    "deleted": False,
    "visibility": "private",
})

# (b) Active task
active_task_id = new_id("active-task")
write("action_items", active_task_id, {
    "id": active_task_id,
    "description": "Verify scenario suite [chat-reliability-fixture]",
    "priority": "medium",
    "completed": False,
    "created_at": now_iso,
    "updated_at": now_iso,
    "category": "fixture",
})

# (c) Completed task
done_task_id = new_id("done-task")
write("action_items", done_task_id, {
    "id": done_task_id,
    "description": "Set up chat-reliability fixtures [chat-reliability-fixture]",
    "priority": "medium",
    "completed": True,
    "created_at": now_iso,
    "updated_at": now_iso,
    "completed_at": now_iso,
    "category": "fixture",
})

# (d) No-result sentinel — its unique string must NOT fuzzy-match anything else.
sentinel_id = new_id("sentinel")
write("action_items", sentinel_id, {
    "id": sentinel_id,
    "description": "ZZZ_NO_RESULTS_SENTINEL_XYZ_unique_string_99999",
    "priority": "low",
    "completed": True,
    "created_at": now_iso,
    "updated_at": now_iso,
    "category": "fixture",
    "note": (
        "Scenario #5 queries for a string that exists nowhere; the unique "
        "marker is here so a teardown can find/remove this doc reliably."
    ),
})

# NOTE: the semantic-search fixture (scenario #4) is NOT seeded here.
# Screenshots in the desktop app are local-first (captured by Rewind into
# local SQLite, then pushed UP to the VM via AgentSyncService). There is
# no Firestore -> local pull path for screenshots, so seeding a Firestore
# `screenshots/<id>` doc would never reach chat. The scenario runner seeds
# that fixture via the Swift helper ChatReliabilityFixtures.seedScreenshotFixture()
# instead, which writes directly to local SQLite via GRDB.

# (e) Daily-recap fixture (action_item created today)
recap_id = new_id("recap")
write("action_items", recap_id, {
    "id": recap_id,
    "description": "Fixture: today's chat-reliability scenario item",
    "priority": "medium",
    "completed": False,
    "created_at": now_iso,
    "updated_at": now_iso,
    "category": "fixture",
})

print()
print("Seeded fixtures:")
print(f"  memory             = {mem_id}")
print(f"  active task        = {active_task_id}")
print(f"  completed task     = {done_task_id}")
print(f"  no-result sentinel = {sentinel_id}")
print(f"  daily recap        = {recap_id}")
print()
print("Screenshots fixture (scenario #4) is seeded by the in-process")
print("runner via ChatReliabilityFixtures.seedScreenshotFixture() — not")
print("here. See desktop/Desktop/Tests/Scenarios/ChatReliabilityFixtures.swift.")
PY

echo
echo "==> Done. To remove these fixtures later, run:"
echo "    $SCRIPT_DIR/teardown-chat-reliability-fixtures.sh"
