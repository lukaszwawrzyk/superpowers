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

FAKE_NODE_DIR="$TEST_DIR/fake-bin"
mkdir -p "$FAKE_NODE_DIR"
cat > "$FAKE_NODE_DIR/node" <<'FAKENODE'
#!/usr/bin/env bash
echo "DIR=$BRAINSTORM_DIR"
echo "HOST=$BRAINSTORM_HOST"
echo "URL_HOST=$BRAINSTORM_URL_HOST"
echo "OWNER=${BRAINSTORM_OWNER_PID:-__UNSET__}"
exit 0
FAKENODE
chmod +x "$FAKE_NODE_DIR/node"

captured=$(
  PATH="$FAKE_NODE_DIR:$PATH" "$START_SCRIPT" \
    --project-dir "$TEST_DIR/project" \
    --host 0.0.0.0 \
    --url-host localhost
)

case "$captured" in
  *"HOST=0.0.0.0"* ) echo "  PASS: passes bind host" ;;
  * ) echo "  FAIL: bind host not passed"; echo "$captured"; exit 1 ;;
esac
case "$captured" in
  *"URL_HOST=localhost"* ) echo "  PASS: passes URL host" ;;
  * ) echo "  FAIL: URL host not passed"; echo "$captured"; exit 1 ;;
esac
case "$captured" in
  *"OWNER=__UNSET__"* ) echo "  PASS: does not set owner PID" ;;
  * ) echo "  FAIL: owner PID should be unset"; echo "$captured"; exit 1 ;;
esac

rm -rf "$TEST_DIR/project"

"$START_SCRIPT" \
  --project-dir "$TEST_DIR/project" \
  --host 127.0.0.1 \
  --url-host localhost \
  > "$TEST_DIR/server.out" 2> "$TEST_DIR/server.err" &
SERVER_PID=$!

SESSION_DIR="$(wait_for_session_dir "$TEST_DIR/project/.superpowers/brainstorm")"
STATE_DIR="$SESSION_DIR/state"

if ! wait_for_info "$STATE_DIR"; then
  echo "  FAIL: server-info was not written"
  cat "$TEST_DIR/server.out" "$TEST_DIR/server.err"
  exit 1
fi
echo "  PASS: writes state/server-info"

PORT="$(grep -o '"port":[0-9]*' "$STATE_DIR/server-info" | head -1 | sed 's/"port"://')"
node -e "
  const http = require('http');
  http.get('http://127.0.0.1:$PORT/', (res) => process.exit(res.statusCode === 200 ? 0 : 1))
    .on('error', () => process.exit(1));
"
echo "  PASS: server responds over HTTP"

echo "=== Results: passed ==="
