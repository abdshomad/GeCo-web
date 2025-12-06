#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE=".geco.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "No PID file found. GeCo web app is not running."
    exit 0
fi

PID=$(cat "$PID_FILE")

if [ -z "$PID" ]; then
    echo "Error: PID file is empty."
    rm -f "$PID_FILE"
    exit 1
fi

# Check if process is still running
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Process $PID is not running. Removing stale PID file."
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping GeCo web app (PID: $PID)..."

# Try graceful termination first (SIGTERM)
kill "$PID" 2>/dev/null || true

# Wait for process to terminate
WAIT_TIME=0
MAX_WAIT=10
while ps -p "$PID" > /dev/null 2>&1 && [ $WAIT_TIME -lt $MAX_WAIT ]; do
    sleep 1
    WAIT_TIME=$((WAIT_TIME + 1))
done

# Force kill if still running
if ps -p "$PID" > /dev/null 2>&1; then
    echo "Process did not terminate gracefully. Force killing..."
    kill -9 "$PID" 2>/dev/null || true
    sleep 1
fi

# Verify process is stopped
if ps -p "$PID" > /dev/null 2>&1; then
    echo "Error: Failed to stop process $PID"
    exit 1
else
    echo "GeCo web app stopped successfully."
    rm -f "$PID_FILE"
fi

