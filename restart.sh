#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Restarting GeCo web app..."

# Stop the current process if running
if [ -f ".geco.pid" ]; then
    echo "Stopping current process..."
    ./stop.sh
    echo "Waiting 2 seconds before restarting..."
    sleep 2
else
    echo "No running process found."
fi

# Start the process
echo "Starting GeCo web app..."
./run.sh "$@"

