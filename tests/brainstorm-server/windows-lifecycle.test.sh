#!/usr/bin/env bash
# Smoke tests for the Exeggcute-friendly brainstorm start wrapper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SUPERPOWERS_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
START_SCRIPT="$REPO_ROOT/skills/brainstorming/scripts/start-server.sh"
TEST_DIR="${TMPDIR:-/tmp}/brainstorm-start-test-$$"

SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

wait_for_info() {
  local state_dir="$1"
  for _ in $(seq 1 50); do
    if [[ -f "$state_dir/server-info" ]]; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_session_dir() {
  local root="$1"
  for _ in $(seq 1 50); do
    local session_dir
    session_dir="$(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -1)"
    if [[ -n "$session_dir" ]]; then
      echo "$session_dir"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

mkdir -p "$TEST_DIR"

echo "=== Brainstorm start wrapper tests ==="

started_json="$(
"$START_SCRIPT" \
  --project-dir "$TEST_DIR/project" \
  --host 127.0.0.1 \
  --url-host localhost
)"

SESSION_DIR="$(wait_for_session_dir "$TEST_DIR/project/.superpowers/brainstorm")"
STATE_DIR="$SESSION_DIR/state"

if ! wait_for_info "$STATE_DIR"; then
  echo "  FAIL: server-info was not written"
  echo "$started_json"
  exit 1
fi
echo "  PASS: writes state/server-info"

case "$started_json" in
  *'"type":"server-started"'* ) echo "  PASS: prints server-started JSON" ;;
  * ) echo "  FAIL: did not print server-started JSON"; echo "$started_json"; exit 1 ;;
esac

if [[ ! -f "$STATE_DIR/server.pid" ]]; then
  echo "  FAIL: server.pid was not written"
  exit 1
fi
SERVER_PID="$(cat "$STATE_DIR/server.pid")"
if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "  FAIL: detached server process is not alive"
  exit 1
fi
echo "  PASS: detached server process stays alive after wrapper exits"

PORT="$(grep -o '"port":[0-9]*' "$STATE_DIR/server-info" | head -1 | sed 's/"port"://')"
node -e "
  const http = require('http');
  http.get('http://127.0.0.1:$PORT/', (res) => process.exit(res.statusCode === 200 ? 0 : 1))
    .on('error', () => process.exit(1));
"
echo "  PASS: server responds over HTTP"

echo "=== Results: passed ==="
