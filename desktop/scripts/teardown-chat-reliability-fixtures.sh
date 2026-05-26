#!/bin/bash
# teardown-chat-reliability-fixtures.sh — wipe every Firestore doc tagged
# source="chat-reliability-fixture" inside the dedicated eval UID's
# subcollections.
#
# Companion to seed-chat-reliability-fixtures.sh. Same safety guards.
#
# SAFETY:
#   - Hardcodes the V1 eval UID (rg0PvY9mhKRARcYxkHHYh4iAkc12).
#   - REFUSES to run unless the named-bundle (com.omi.omi-chat-reliability)
#     UserDefaults auth_userId matches that UID.
#   - REFUSES to run if backend/google-credentials.json is missing.
#   - Only deletes inside users/<EVAL_UID>/<subcollection>/ where
#     source == "chat-reliability-fixture". Never touches docs without the tag.
#
# Usage: teardown-chat-reliability-fixtures.sh
set -euo pipefail

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

Deletes every Firestore doc tagged source="${FIXTURE_TAG}" inside
users/${EVAL_UID}/{memories, action_items, screenshots}.

This is the DANGEROUS half of the fixture pair — fail-closed by design.
Guards (script exits non-zero with a clear message if any fail):
  - backend/google-credentials.json must exist at ${CREDS}
  - The named bundle ${EVAL_BUNDLE_ID} must currently be signed into UID
    ${EVAL_UID} (read via 'defaults read ${EVAL_BUNDLE_ID} auth_userId').

A mismatched UID or missing credentials = abort. Never deletes anything
that does not have the explicit fixture tag.
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
  echo "       Cannot reach Firestore without it. Aborting." >&2
  exit 3
fi

# ----- guard: signed-in UID matches eval UID ----------------------------------
SIGNED_IN_UID="$(defaults read "$EVAL_BUNDLE_ID" auth_userId 2>/dev/null || true)"
if [[ -z "$SIGNED_IN_UID" ]]; then
  echo "ERROR: could not read auth_userId from bundle '$EVAL_BUNDLE_ID'." >&2
  echo "       Is the named eval bundle installed and signed in?" >&2
  exit 4
fi
if [[ "$SIGNED_IN_UID" != "$EVAL_UID" ]]; then
  echo "ERROR: signed-in UID does not match the locked eval UID." >&2
  echo "       Expected: $EVAL_UID" >&2
  echo "       Found:    $SIGNED_IN_UID  (bundle: $EVAL_BUNDLE_ID)" >&2
  echo "       Refusing to delete from the wrong account." >&2
  exit 5
fi

if [[ ! -f "$VENV_ACTIVATE" ]]; then
  echo "ERROR: backend venv not found at $VENV_ACTIVATE" >&2
  echo "       Create it per backend/CLAUDE.md before running this script." >&2
  exit 6
fi
# shellcheck disable=SC1090
source "$VENV_ACTIVATE"

echo "==> Deleting fixtures tagged source=\"$FIXTURE_TAG\" under users/$EVAL_UID/"
echo "    credentials: $CREDS"
echo

python3 - "$CREDS" "$EVAL_UID" "$FIXTURE_TAG" <<'PY'
import sys

import firebase_admin
from firebase_admin import credentials, firestore

creds_path, uid, tag = sys.argv[1], sys.argv[2], sys.argv[3]

cred = credentials.Certificate(creds_path)
try:
    firebase_admin.initialize_app(cred)
except ValueError:
    pass
db = firestore.client()

# Mirror seed script's subcollection list. action_items / memories / screenshots
# are the ones the seed script writes; observations and staged_tasks are
# included defensively in case future seed revisions touch them.
SUBCOLLECTIONS = [
    "memories",
    "action_items",
    "screenshots",
    "observations",
    "staged_tasks",
]

user_ref = db.collection("users").document(uid)

total = 0
for sub in SUBCOLLECTIONS:
    q = user_ref.collection(sub).where("source", "==", tag)
    for doc in q.stream():
        print(f"  [delete] users/{uid}/{sub}/{doc.id}")
        doc.reference.delete()
        total += 1

print()
print(f"Removed {total} fixture doc(s).")
PY

echo
echo "==> Done."
