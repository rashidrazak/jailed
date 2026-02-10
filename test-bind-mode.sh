#!/usr/bin/env bash
set -euo pipefail

JAILED="/Users/rashidrazak/Downloads/jailed/jailed"
STATE_FILE="$HOME/.config/jailed/running.json"

echo "=== Test 1: Bind mode normal exit ==="
echo "Starting bind mode container..."
echo "exit" | "$JAILED" run --sync bind /Users/rashidrazak/Downloads/jailed

echo ""
echo "Checking for containers..."
if /opt/podman/bin/podman ps -a --format "{{.Names}}" | grep -q "^jailed-"; then
    echo "FAIL: Container still exists (should be auto-removed by --rm)"
    /opt/podman/bin/podman ps -a | grep jailed-
    exit 1
else
    echo "PASS: No containers (--rm worked)"
fi

echo ""
echo "Checking for state file..."
if [ -f "$STATE_FILE" ]; then
    echo "FAIL: State file still exists at $STATE_FILE"
    cat "$STATE_FILE"
    exit 1
else
    echo "PASS: State file cleaned up"
fi

echo ""
echo "=== Test 2: Verify --rm flag is set ==="
# Start a container in the background
echo "ls" | "$JAILED" run --sync bind /Users/rashidrazak/Downloads/jailed &
jailed_pid=$!

# Wait a moment for container to start
sleep 2

# Find the container
container_name=$(/opt/podman/bin/podman ps --format "{{.Names}}" | grep "^jailed-" || true)

if [ -z "$container_name" ]; then
    echo "SKIP: Container already exited (too fast)"
else
    # Check if AutoRemove is set
    auto_remove=$(/opt/podman/bin/podman inspect "$container_name" --format '{{.HostConfig.AutoRemove}}')

    if [ "$auto_remove" = "true" ]; then
        echo "PASS: Container has --rm flag (AutoRemove=true)"
    else
        echo "FAIL: Container missing --rm flag (AutoRemove=false)"
        /opt/podman/bin/podman stop "$container_name" || true
        exit 1
    fi

    # Stop the container to trigger auto-removal
    /opt/podman/bin/podman stop "$container_name"

    # Verify it was auto-removed
    sleep 1
    if /opt/podman/bin/podman ps -a --format "{{.Names}}" | grep -q "^$container_name$"; then
        echo "FAIL: Container not auto-removed after stop"
        exit 1
    else
        echo "PASS: Container auto-removed after stop"
    fi
fi

# Wait for background jailed process
wait $jailed_pid 2>/dev/null || true

echo ""
echo "=== All tests passed! ==="
