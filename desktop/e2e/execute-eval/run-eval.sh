#!/usr/bin/env bash
# Execute reliability eval driver.
#
# Drives the app through the local HTTP automation bridge instead of scraping
# the floating-bar UI. This keeps the core reliability proof independent from
# agent-swift while still exercising the same Execute-mode AgentPill path.

set -euo pipefail

BUNDLE="omi-execute-eval"
PORT="47778"
TRIALS=1
TASKS_FILE="$(dirname "$0")/tasks.local.json"
RESULTS_DIR="$(dirname "$0")/results"
GRADERS_DIR="$(dirname "$0")/graders"
LAUNCH_APP=1
SEED_FROM_BUNDLE=""
TIMEOUT_SECONDS=240

while [[ $# -gt 0 ]]; do
  case "$1" in
    --trials) TRIALS="$2"; shift 2 ;;
    --bundle) BUNDLE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --tasks) TASKS_FILE="$2"; shift 2 ;;
    --no-launch) LAUNCH_APP=0; shift ;;
    --seed-from-bundle) SEED_FROM_BUNDLE="$2"; shift 2 ;;
    --timeout) TIMEOUT_SECONDS="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }

case "$BUNDLE" in
  omi-*) ;;
  *) echo "Bundle name must start with omi- (got: $BUNDLE)" >&2; exit 2 ;;
esac

mkdir -p "$RESULTS_DIR"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
out="$RESULTS_DIR/$ts.jsonl"
desktop_dir="$(cd "$(dirname "$0")/../.." && pwd)"

run_pid=""
cleanup() {
  if [[ -n "$run_pid" ]]; then
    echo "Eval cleanup: stopping $BUNDLE run process (pid=$run_pid)" >&2
    kill "$run_pid" 2>/dev/null || true
    wait "$run_pid" 2>/dev/null || true
  fi
  pkill -f "/Applications/${BUNDLE}.app/Contents/MacOS/Omi Computer" 2>/dev/null || true
}
trap cleanup EXIT

request_json() {
  local path="$1"
  local body="$2"
  curl -fsS \
    -H "Content-Type: application/json" \
    --data "$body" \
    "http://127.0.0.1:${PORT}${path}"
}

wait_for_bridge() {
  local deadline=$((SECONDS + 120))
  until curl -fsS "http://127.0.0.1:${PORT}/state" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Automation bridge did not come up on port $PORT" >&2
      return 1
    fi
    sleep 2
  done
}

if [[ -n "$SEED_FROM_BUNDLE" ]]; then
  echo "Seeding auth from $SEED_FROM_BUNDLE into com.omi.$BUNDLE" >&2
  auth_json="$desktop_dir/tmp/${BUNDLE}-auth.json"
  mkdir -p "$desktop_dir/tmp"
  "$desktop_dir/scripts/omi-auth-dump.sh" "$SEED_FROM_BUNDLE" "$auth_json" >/dev/null
  "$desktop_dir/scripts/omi-auth-seed.sh" "com.omi.$BUNDLE" "$auth_json" >/dev/null
fi

if (( LAUNCH_APP == 1 )); then
  echo "Launching $BUNDLE on automation port $PORT" >&2
  (
    cd "$desktop_dir"
    OMI_APP_NAME="$BUNDLE" \
      OMI_AUTOMATION_PORT="$PORT" \
      OMI_SKIP_BACKEND=1 \
      OMI_SKIP_TUNNEL=1 \
      ./run.sh --yolo
  ) &
  run_pid=$!
fi

wait_for_bridge

signed_in_deadline=$((SECONDS + 90))
state="$(curl -fsS "http://127.0.0.1:${PORT}/state")"
while [[ "$(echo "$state" | jq -r '.result.isSignedIn')" != "true" ]]; do
  if (( SECONDS >= signed_in_deadline )); then
    break
  fi
  sleep 2
  state="$(curl -fsS "http://127.0.0.1:${PORT}/state")"
done

if [[ "$(echo "$state" | jq -r '.result.isSignedIn')" != "true" ]]; then
  echo "App is not signed in; seed auth first or pass --seed-from-bundle <bundle-id>" >&2
  echo "$state" >&2
  exit 1
fi

echo "Eval starting: bundle=$BUNDLE port=$PORT trials=$TRIALS tasks=$TASKS_FILE" >&2
echo "Writing results to $out" >&2

task_ids=$(jq -r '.tasks[].id' "$TASKS_FILE")
for task_id in $task_ids; do
  task=$(jq --arg id "$task_id" '.tasks[] | select(.id == $id)' "$TASKS_FILE")
  category=$(echo "$task" | jq -r '.category')

  for trial in $(seq 1 "$TRIALS"); do
    echo "[$task_id #$trial/$TRIALS] spawning Execute pill..." >&2
    setup=$(echo "$task" | jq -r '.setup_command // empty')
    if [[ -n "$setup" ]]; then
      bash -lc "$setup"
    fi

    spawn_body=$(jq -n --argjson task "$task" '{notification: $task.notification}')
    spawn_response=$(request_json "/execute/spawn" "$spawn_body")
    pill_id=$(echo "$spawn_response" | jq -r '.result.pillId')
    pill_status="unknown"
    pill_error=""
    pill_activity=""
    verification="null"

    deadline=$((SECONDS + TIMEOUT_SECONDS))
    while true; do
      status_response=$(request_json "/execute/status" "$(jq -n --arg id "$pill_id" '{pillId: $id}')")
      pill_status=$(echo "$status_response" | jq -r '.result.status')
      pill_error=$(echo "$status_response" | jq -r '.result.error // ""')
      pill_activity=$(echo "$status_response" | jq -r '.result.latestActivity // ""')
      verification=$(echo "$status_response" | jq -c '.result.verificationVerified')

      case "$pill_status" in
        done|failed) break ;;
      esac
      if (( SECONDS >= deadline )); then
        pill_status="timeout"
        pill_error="timed out after ${TIMEOUT_SECONDS}s"
        break
      fi
      sleep 3
    done

    grader="$GRADERS_DIR/${category}.py"
    grader_verdict="unknown"
    grader_evidence=""
    if [[ -x "$grader" ]]; then
      if grader_output=$(echo "$task" | python3 "$grader" 2>&1); then
        grader_verdict="passed"
      else
        grader_verdict="failed"
      fi
      grader_evidence="$grader_output"
    else
      grader_evidence="grader missing or not executable: $grader"
    fi

    overall=$([[ "$pill_status" == "done" && "$grader_verdict" == "passed" ]] && echo "pass" || echo "fail")
    jq -nc \
      --arg id "$task_id" \
      --argjson trial "$trial" \
      --arg category "$category" \
      --arg pill "$pill_status" \
      --arg pill_id "$pill_id" \
      --arg error "$pill_error" \
      --arg activity "$pill_activity" \
      --arg grader "$grader_verdict" \
      --arg evidence "$grader_evidence" \
      --arg overall "$overall" \
      --argjson verification "$verification" \
      '{
        task_id: $id,
        trial: $trial,
        category: $category,
        pill_id: $pill_id,
        pill_status: $pill,
        pill_error: $error,
        latest_activity: $activity,
        verification: $verification,
        grader: $grader,
        grader_evidence: $evidence,
        result: $overall
      }' >> "$out"
  done
done

ln -sf "$(basename "$out")" "$RESULTS_DIR/latest.jsonl"
echo "Eval complete. Summary:" >&2
python3 "$(dirname "$0")/report.py" "$out"
