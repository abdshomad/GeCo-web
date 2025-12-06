#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PID_FILE=".geco.pid"
LOG_DIR="logs"
STDOUT_LOG="$LOG_DIR/stdout.log"
STDERR_LOG="$LOG_DIR/stderr.log"

echo "=== GeCo Web App Monitor ==="
echo ""

# Check if PID file exists
if [ ! -f "$PID_FILE" ]; then
    echo "Status: NOT RUNNING"
    echo "No PID file found. The web app is not running."
    exit 0
fi

PID=$(cat "$PID_FILE")

if [ -z "$PID" ]; then
    echo "Status: ERROR"
    echo "PID file is empty or invalid."
    exit 1
fi

# Check if process is running
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "Status: NOT RUNNING"
    echo "Process $PID is not running (stale PID file)."
    echo "You may want to remove the PID file: rm $PID_FILE"
    exit 0
fi

echo "Status: RUNNING"
echo "PID: $PID"
echo ""

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Set default port
DEFAULT_PORT="${PORT:-8013}"

# Try to detect port from process or logs
PORT="$DEFAULT_PORT"
if [ -f "$STDOUT_LOG" ]; then
    DETECTED_PORT=$(grep -oP "Uvicorn running on.*:(\d+)" "$STDOUT_LOG" 2>/dev/null | grep -oP "\d+" | tail -n 1)
    if [ -n "$DETECTED_PORT" ]; then
        PORT="$DETECTED_PORT"
    fi
fi

HOST="0.0.0.0"
if [ -f "$STDOUT_LOG" ]; then
    DETECTED_HOST=$(grep -oP "Uvicorn running on ([\d.]+):" "$STDOUT_LOG" 2>/dev/null | grep -oP "[\d.]+" | tail -n 1)
    if [ -n "$DETECTED_HOST" ]; then
        HOST="$DETECTED_HOST"
    fi
fi

echo "Web App URL: http://$HOST:$PORT"
echo ""

# Get process information
if command -v ps > /dev/null 2>&1; then
    echo "Process Information:"
    ps -p "$PID" -o pid,ppid,user,%cpu,%mem,etime,cmd 2>/dev/null || echo "  Unable to get process details"
    echo ""
fi

# Calculate runtime if possible
if command -v ps > /dev/null 2>&1; then
    RUNTIME=$(ps -p "$PID" -o etime= 2>/dev/null | tr -d ' ')
    if [ -n "$RUNTIME" ]; then
        echo "Runtime: $RUNTIME"
    fi
fi

# Show resource usage if available
if command -v ps > /dev/null 2>&1; then
    CPU_MEM=$(ps -p "$PID" -o %cpu,%mem= 2>/dev/null | tr -d ' ')
    if [ -n "$CPU_MEM" ]; then
        echo "CPU/Memory: $CPU_MEM"
    fi
fi

echo ""

# Show recent log output
if [ -f "$STDOUT_LOG" ]; then
    echo "=== Recent stdout (last 10 lines) ==="
    tail -n 10 "$STDOUT_LOG" 2>/dev/null || echo "  No stdout output yet"
    echo ""
fi

if [ -f "$STDERR_LOG" ]; then
    STDERR_SIZE=$(stat -f%z "$STDERR_LOG" 2>/dev/null || stat -c%s "$STDERR_LOG" 2>/dev/null || echo "0")
    if [ "$STDERR_SIZE" -gt 0 ]; then
        echo "=== Recent stderr (last 10 lines) ==="
        tail -n 10 "$STDERR_LOG" 2>/dev/null || echo "  No stderr output yet"
        echo ""
    fi
fi

echo "Log files:"
echo "  stdout: $STDOUT_LOG"
echo "  stderr: $STDERR_LOG"
echo ""
echo "Use './stop.sh' to stop the web app"
echo "Access the web app at: http://$HOST:$PORT"

