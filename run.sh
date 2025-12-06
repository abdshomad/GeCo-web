#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE=".geco.pid"
LOG_DIR="logs"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set defaults
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8013}"

# Check if virtual environment exists
if [ ! -d ".venv" ]; then
    echo "Error: Virtual environment not found. Please run ./install.sh first."
    exit 1
fi

# Check if process is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Error: GeCo web app is already running (PID: $OLD_PID)"
        echo "Use ./stop.sh to stop it first, or ./restart.sh to restart it."
        exit 1
    else
        echo "Removing stale PID file..."
        rm -f "$PID_FILE"
    fi
fi

# Create logs directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Check if app.py exists
if [ ! -f "app.py" ]; then
    echo "Error: app.py not found. Please ensure you're in the correct directory."
    exit 1
fi

# Build command arguments
# If arguments are provided, use them; otherwise use defaults
if [ $# -eq 0 ]; then
    ARGS="--host $HOST --port $PORT"
else
    ARGS="$@"
fi

# Activate virtual environment and run FastAPI app in background
echo "Starting GeCo web app..."
echo "Host: $HOST"
echo "Port: $PORT"
echo "Logs will be written to: $STDOUT_LOG and $STDERR_LOG"

# Use uv run to execute uvicorn in the virtual environment
nohup uv run uvicorn app:app $ARGS > "$STDOUT_LOG" 2> "$STDERR_LOG" &
APP_PID=$!

# Save PID
echo "$APP_PID" > "$PID_FILE"

# Wait a moment to check if process started successfully
sleep 2

if ps -p "$APP_PID" > /dev/null 2>&1; then
    echo "GeCo web app started successfully (PID: $APP_PID)"
    echo "Access the web app at: http://$HOST:$PORT"
    echo "Use ./monitor.sh to check status"
    echo "Use ./stop.sh to stop it"
else
    echo "Error: Failed to start GeCo web app. Check logs for details:"
    echo "  stdout: $STDOUT_LOG"
    echo "  stderr: $STDERR_LOG"
    rm -f "$PID_FILE"
    exit 1
fi

