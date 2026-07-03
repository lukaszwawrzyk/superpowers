#!/usr/bin/env bash
# Start the brainstorm server and output connection info
# Usage: start-server.sh [--project-dir <path>] [--host <bind-host>] [--url-host <display-host>] [--foreground] [--background]
#
# Starts server on a random high port, outputs JSON with URL.
# Each session gets its own directory to avoid conflicts.
# This fork starts the server detached by default for Exeggcute/Codex tool
# sessions and relies on the idle timeout for cleanup.
#
# Options:
#   --project-dir <path>  Store session files under <path>/.superpowers/brainstorm/
#                         instead of /tmp. Files persist after server stops.
#   --host <bind-host>    Host/interface to bind (default: 127.0.0.1).
#                         Use 0.0.0.0 in remote/containerized environments.
#   --url-host <host>     Hostname shown in returned URL JSON.
#   --idle-timeout-minutes <n>  Shut down after n minutes idle (default 240 = 4h).
#   --open                Auto-open the browser on the first screen (use only
#                         after the user approves the visual companion).
#   --foreground          Run server in the current terminal (no backgrounding).
#   --background          Force detached mode.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse arguments
PROJECT_DIR=""
FOREGROUND="false"
BIND_HOST="127.0.0.1"
URL_HOST=""
IDLE_TIMEOUT_MINUTES=""
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
    --idle-timeout-minutes)
      IDLE_TIMEOUT_MINUTES="$2"
      shift 2
      ;;
    --open)
      export BRAINSTORM_OPEN=1
      shift
      ;;
    --foreground|--no-daemon)
      FOREGROUND="true"
      shift
      ;;
    --background|--daemon)
      FOREGROUND="false"
      shift
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

if [[ -n "$IDLE_TIMEOUT_MINUTES" ]]; then
  if ! [[ "$IDLE_TIMEOUT_MINUTES" =~ ^[0-9]+$ ]] || [[ "$IDLE_TIMEOUT_MINUTES" -lt 1 ]]; then
    echo "{\"error\": \"--idle-timeout-minutes must be a positive integer\"}"
    exit 1
  fi
  export BRAINSTORM_IDLE_TIMEOUT_MS=$(( IDLE_TIMEOUT_MINUTES * 60 * 1000 ))
fi

# Keep session files private to the current user. They can include brainstorm
# content and browser interaction events.
umask 077

# Generate unique session directory
SESSION_ID="$$-$(date +%s)"

if [[ -n "$PROJECT_DIR" ]]; then
  SESSION_DIR="${PROJECT_DIR}/.superpowers/brainstorm/${SESSION_ID}"
  # Persist the bound port per project so a restart reuses it and an already-open
  # browser tab reconnects to the same URL.
  export BRAINSTORM_PORT_FILE="${PROJECT_DIR}/.superpowers/brainstorm/.last-port"
else
  SESSION_DIR="/tmp/brainstorm-${SESSION_ID}"
fi

STATE_DIR="${SESSION_DIR}/state"
PID_FILE="${STATE_DIR}/server.pid"
LOG_FILE="${STATE_DIR}/server.log"
SERVER_ID_FILE="${STATE_DIR}/server-instance-id"

# Create fresh session directory with content and state peers
mkdir -p "${SESSION_DIR}/content" "$STATE_DIR"

SERVER_ID=""
if [[ -r /dev/urandom ]]; then
  SERVER_ID="$(od -An -N24 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' || true)"
fi
if ! [[ "$SERVER_ID" =~ ^[A-Za-z0-9_-]{32,64}$ ]]; then
  SERVER_ID="$(printf '%08x%08x%08x%08x' "$$" "$(date +%s)" "${RANDOM:-0}" "${RANDOM:-0}")"
fi
printf '%s\n' "$SERVER_ID" > "$SERVER_ID_FILE"
chmod 600 "$SERVER_ID_FILE" 2>/dev/null || true

# Kill any existing server
if [[ -f "$PID_FILE" ]]; then
  old_pid=$(cat "$PID_FILE")
  kill "$old_pid" 2>/dev/null
  rm -f "$PID_FILE"
fi

cd "$SCRIPT_DIR" || exit 1

# Foreground mode is explicit only. The server is not tied to the short-lived
# launcher process with BRAINSTORM_OWNER_PID; idle timeout handles cleanup.
if [[ "$FOREGROUND" == "true" ]]; then
  echo "$$" > "$PID_FILE"
  exec env \
    BRAINSTORM_DIR="$SESSION_DIR" \
    BRAINSTORM_HOST="$BIND_HOST" \
    BRAINSTORM_URL_HOST="$URL_HOST" \
    node server.cjs "--brainstorm-server-id=$SERVER_ID"
fi

# Start server detached so it survives after the agent response. Prefer setsid
# when available; fall back to nohup for shells without it.
if command -v setsid >/dev/null 2>&1; then
  setsid -f bash -c '
    BRAINSTORM_DIR="$1" \
    BRAINSTORM_HOST="$2" \
    BRAINSTORM_URL_HOST="$3" \
      node server.cjs "$6" > "$4" 2>&1 &
    echo "$!" > "$5"
  ' -- "$SESSION_DIR" "$BIND_HOST" "$URL_HOST" "$LOG_FILE" "$PID_FILE" "--brainstorm-server-id=$SERVER_ID"
else
  nohup env \
    BRAINSTORM_DIR="$SESSION_DIR" \
    BRAINSTORM_HOST="$BIND_HOST" \
    BRAINSTORM_URL_HOST="$URL_HOST" \
    node server.cjs "--brainstorm-server-id=$SERVER_ID" > "$LOG_FILE" 2>&1 &
  SERVER_PID=$!
  disown "$SERVER_PID" 2>/dev/null || true
  echo "$SERVER_PID" > "$PID_FILE"
fi

# Wait for server-started message (check log file)
for _ in {1..50}; do
  if [[ -f "$STATE_DIR/server-info" ]]; then
    # Verify server is still alive after a short window (catches process reapers)
    SERVER_PID="$(cat "$PID_FILE" 2>/dev/null || true)"
    alive="true"
    for _ in {1..20}; do
      if [[ -z "$SERVER_PID" ]] || ! kill -0 "$SERVER_PID" 2>/dev/null; then
        alive="false"
        break
      fi
      sleep 0.1
    done
    if [[ "$alive" != "true" ]]; then
      echo "{\"error\": \"Server started but was killed. Retry in a persistent terminal with: $SCRIPT_DIR/start-server.sh${PROJECT_DIR:+ --project-dir $PROJECT_DIR} --host $BIND_HOST --url-host $URL_HOST --foreground\"}"
      exit 1
    fi
    cat "$STATE_DIR/server-info"
    exit 0
  fi
  if [[ -f "$STATE_DIR/server-stopped" ]]; then
    echo "{\"error\": \"Server stopped during startup\", \"log\": \"$LOG_FILE\"}"
    exit 1
  fi
  sleep 0.1
done

# Timeout - server didn't start
echo '{"error": "Server failed to start within 5 seconds"}'
exit 1
