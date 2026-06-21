#!/usr/bin/env bash
# Start the brainstorm server and output connection info.
# Usage: start-server.sh [--project-dir <path>] [--host <bind-host>] [--url-host <display-host>]
#
# This fork is used from Exeggcute/Codex tool sessions. Start the server as a
# detached process so it survives after the agent response, and do not set
# BRAINSTORM_OWNER_PID because short-lived launcher processes can disappear
# while the browser companion should keep running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_DIR=""
BIND_HOST="127.0.0.1"
URL_HOST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --host)
      BIND_HOST="$2"
      shift 2
      ;;
    --url-host)
      URL_HOST="$2"
      shift 2
      ;;
    *)
      echo "{\"error\": \"Unknown argument: $1\"}"
      exit 1
      ;;
  esac
done

if [[ -z "$URL_HOST" ]]; then
  if [[ "$BIND_HOST" == "127.0.0.1" || "$BIND_HOST" == "localhost" ]]; then
    URL_HOST="localhost"
  else
    URL_HOST="$BIND_HOST"
  fi
fi

SESSION_ID="$$-$(date +%s)"
if [[ -n "$PROJECT_DIR" ]]; then
  SESSION_DIR="${PROJECT_DIR}/.superpowers/brainstorm/${SESSION_ID}"
else
  SESSION_DIR="/tmp/brainstorm-${SESSION_ID}"
fi

STATE_DIR="${SESSION_DIR}/state"
PID_FILE="${STATE_DIR}/server.pid"
LOG_FILE="${STATE_DIR}/server.log"

mkdir -p "${SESSION_DIR}/content" "$STATE_DIR"

cd "$SCRIPT_DIR"
setsid -f bash -c '
  BRAINSTORM_DIR="$1" \
  BRAINSTORM_HOST="$2" \
  BRAINSTORM_URL_HOST="$3" \
    node server.cjs > "$4" 2>&1 &
  echo "$!" > "$5"
' -- "$SESSION_DIR" "$BIND_HOST" "$URL_HOST" "$LOG_FILE" "$PID_FILE"

for _ in $(seq 1 50); do
  if [[ -f "$STATE_DIR/server-info" ]]; then
    cat "$STATE_DIR/server-info"
    exit 0
  fi
  if [[ -f "$STATE_DIR/server-stopped" ]]; then
    echo "{\"error\": \"Server stopped during startup\", \"log\": \"$LOG_FILE\"}"
    exit 1
  fi
  sleep 0.1
done

echo "{\"error\": \"Server failed to start within 5 seconds\", \"log\": \"$LOG_FILE\"}"
exit 1
