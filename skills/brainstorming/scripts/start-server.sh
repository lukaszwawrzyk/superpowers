#!/usr/bin/env bash
# Start the brainstorm server and output connection info.
# Usage: start-server.sh [--project-dir <path>] [--host <bind-host>] [--url-host <display-host>]
#
# This fork is used from Exeggcute/Codex tool sessions. Run the server in the
# foreground so the tool session owns its lifetime, and do not set
# BRAINSTORM_OWNER_PID because short-lived launcher processes can disappear
# while the tool session is still active.

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

mkdir -p "${SESSION_DIR}/content" "$STATE_DIR"
echo "$$" > "$PID_FILE"

cd "$SCRIPT_DIR"
exec env \
  BRAINSTORM_DIR="$SESSION_DIR" \
  BRAINSTORM_HOST="$BIND_HOST" \
  BRAINSTORM_URL_HOST="$URL_HOST" \
  node server.cjs
