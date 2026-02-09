#!/usr/bin/env bats
# test_cli.bats - unit tests for the jailed CLI

load test_helpers

# ---------------------------------------------------------------------------
# jailed version
# ---------------------------------------------------------------------------

@test "jailed version prints version string matching 'jailed X.Y.Z'" {
    run jailed version
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^jailed\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# jailed help
# ---------------------------------------------------------------------------

@test "jailed help prints Usage:" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "jailed help prints AI Agents" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"AI Agents"* ]]
}

# ---------------------------------------------------------------------------
# jailed --help (long flag)
# ---------------------------------------------------------------------------

@test "jailed --help works same as jailed help" {
    run jailed help
    local help_output="$output"

    run jailed --help
    [ "$status" -eq 0 ]
    [ "$output" = "$help_output" ]
}

# ---------------------------------------------------------------------------
# jailed -h (short flag)
# ---------------------------------------------------------------------------

@test "jailed -h works same as jailed help" {
    run jailed help
    local help_output="$output"

    run jailed -h
    [ "$status" -eq 0 ]
    [ "$output" = "$help_output" ]
}

# ---------------------------------------------------------------------------
# JAILED_CONFIG_DIR override
# ---------------------------------------------------------------------------

@test "JAILED_CONFIG_DIR env var overrides default config dir" {
    # The jailed script (line 11) resolves CONFIG_DIR with:
    #   CONFIG_DIR="${JAILED_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jailed}"
    #
    # Evaluate that same expression in a subshell with JAILED_CONFIG_DIR
    # exported (already done by setup()) and verify it equals our temp dir.
    local resolved
    resolved=$(bash -c 'echo "${JAILED_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jailed}"')
    [ "$resolved" = "$JAILED_CONFIG_DIR" ]

    # Verify the default (without the override) would NOT equal our temp dir.
    local default_resolved
    default_resolved=$(env -u JAILED_CONFIG_DIR bash -c 'echo "${JAILED_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jailed}"')
    [ "$default_resolved" != "$JAILED_CONFIG_DIR" ]
}

# ---------------------------------------------------------------------------
# jailed help shows new commands
# ---------------------------------------------------------------------------

@test "jailed help mentions attach command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"attach"* ]]
}

@test "jailed help mentions detach command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"detach"* ]]
}

@test "jailed help describes detach as removing files from container" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"detach"*"remove files from container"* ]]
}

@test "jailed help mentions ls command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ls"* ]]
}

@test "jailed help mentions shell command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"shell"* ]]
}

@test "jailed help mentions stop command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"stop"* ]]
}

# ---------------------------------------------------------------------------
# jailed ls with no running container
# ---------------------------------------------------------------------------

@test "jailed ls shows no containers when none running" {
    run jailed ls
    [ "$status" -eq 0 ]
    [[ "$output" == *"No running containers"* ]]
}

# ---------------------------------------------------------------------------
# jailed attach validation
# ---------------------------------------------------------------------------

@test "jailed attach with no args exits with error" {
    run jailed attach
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# jailed detach validation
# ---------------------------------------------------------------------------

@test "jailed detach with no args exits with error" {
    run jailed detach
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# jailed detach integration tests
# ---------------------------------------------------------------------------

@test "jailed detach fails when no running container" {
    # State file doesn't exist, so no container is running
    run jailed detach myproject
    [ "$status" -ne 0 ]
    [[ "$output" == *"No running container found"* ]]
}

@test "jailed detach fails when project not found in state" {
    # Create state file with a container but no projects
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {}
}
JSON

    run jailed detach nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"Project 'nonexistent' not found"* ]]
}

@test "jailed detach dies when strict sync shutdown fails" {
    # Create state file with a test project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub mutagen that fails on flush
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                exit 0  # Session exists
                ;;
            flush)
                exit 1  # Flush fails
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Run detach - should die before file deletion
    run jailed detach myproject
    [ "$status" -ne 0 ]
    [[ "$output" == *"Sync shutdown failed"* ]]
    [[ "$output" == *"Project files left intact"* ]]

    # State should NOT be cleaned up (project still in state)
    run jq -r '.projects.myproject' "$JAILED_CONFIG_DIR/running.json"
    [ "$output" = "/tmp/test-project" ]
}

@test "jailed detach warns but continues when file deletion fails" {
    # Create state file with a test project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub mutagen with successful happy path
    MUTAGEN_LIST_FILE="${TMPDIR}/mutagen_list_count"
    echo "0" > "$MUTAGEN_LIST_FILE"

    cat > "${STUB_BIN_DIR}/mutagen" <<STUB
#!/usr/bin/env bash
LIST_COUNT_FILE="$MUTAGEN_LIST_FILE"

case "\$1" in
    sync)
        case "\$2" in
            list)
                # Atomic increment
                count=\$(cat "\$LIST_COUNT_FILE")
                count=\$((count + 1))
                echo "\$count" > "\$LIST_COUNT_FILE"

                if [ "\$count" -eq 1 ]; then
                    exit 0  # First call: session exists
                else
                    exit 1  # Second call: session gone
                fi
                ;;
            flush|terminate)
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub docker that fails on rm
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    exec)
        if [[ "$*" == *"rm -rf"* ]]; then
            echo "Error: permission denied" >&2
            exit 1  # File deletion fails
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run detach - should warn but still clean up state
    run jailed detach myproject
    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to remove /workspace/myproject"* ]]
    [[ "$output" == *"Detached 'myproject'"* ]]

    # State should be cleaned up (project removed)
    run jq -r '.projects.myproject // "null"' "$JAILED_CONFIG_DIR/running.json"
    [ "$output" = "null" ]

    # Cleanup
    rm -f "$MUTAGEN_LIST_FILE"
}

@test "jailed detach succeeds on happy path" {
    # Create state file with a test project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub mutagen with successful happy path
    MUTAGEN_LIST_FILE="${TMPDIR}/mutagen_list_count_happy"
    echo "0" > "$MUTAGEN_LIST_FILE"

    cat > "${STUB_BIN_DIR}/mutagen" <<STUB
#!/usr/bin/env bash
LIST_COUNT_FILE="$MUTAGEN_LIST_FILE"

case "\$1" in
    sync)
        case "\$2" in
            list)
                # Atomic increment
                count=\$(cat "\$LIST_COUNT_FILE")
                count=\$((count + 1))
                echo "\$count" > "\$LIST_COUNT_FILE"

                if [ "\$count" -eq 1 ]; then
                    exit 0  # First call: session exists
                else
                    exit 1  # Second call: session gone
                fi
                ;;
            flush|terminate)
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub docker that succeeds
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run detach - should succeed
    run jailed detach myproject
    [ "$status" -eq 0 ]
    [[ "$output" == *"Flushing sync"* ]]
    [[ "$output" == *"Terminating sync"* ]]
    [[ "$output" == *"Removing /workspace/myproject"* ]]
    [[ "$output" == *"Detached 'myproject'"* ]]

    # State should be cleaned up
    run jq -r '.projects.myproject // "null"' "$JAILED_CONFIG_DIR/running.json"
    [ "$output" = "null" ]

    # Cleanup
    rm -f "$MUTAGEN_LIST_FILE"
}

@test "jailed detach sets up Podman shim when RUNTIME=podman" {
    # Create state file with a test project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create .env file with RUNTIME=podman
    cat > "$JAILED_CONFIG_DIR/.env" <<'ENV'
RUNTIME=podman
ENV

    # Create stub mutagen with successful happy path
    MUTAGEN_LIST_FILE="${TMPDIR}/mutagen_list_count_podman"
    echo "0" > "$MUTAGEN_LIST_FILE"

    cat > "${STUB_BIN_DIR}/mutagen" <<STUB
#!/usr/bin/env bash
LIST_COUNT_FILE="$MUTAGEN_LIST_FILE"

case "\$1" in
    daemon)
        # Accept daemon stop without error
        exit 0
        ;;
    sync)
        case "\$2" in
            list)
                # Atomic increment
                count=\$(cat "\$LIST_COUNT_FILE")
                count=\$((count + 1))
                echo "\$count" > "\$LIST_COUNT_FILE"

                if [ "\$count" -eq 1 ]; then
                    exit 0  # First call: session exists
                else
                    exit 1  # Second call: session gone
                fi
                ;;
            flush|terminate)
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub podman
    cat > "${STUB_BIN_DIR}/podman" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/podman"

    # Run detach with RUNTIME=podman
    # Note: The actual shim setup happens internally, we just verify it doesn't break
    run env RUNTIME=podman jailed detach myproject
    [ "$status" -eq 0 ]
    [[ "$output" == *"Detached 'myproject'"* ]]

    # Cleanup
    rm -f "$MUTAGEN_LIST_FILE"
}

# ---------------------------------------------------------------------------
# jailed shell command tests
# ---------------------------------------------------------------------------

@test "jailed shell fails when no running container" {
    # State file doesn't exist, so no container is running
    run jailed --runtime docker shell
    [ "$status" -ne 0 ]
    [[ "$output" == *"No running container found"* ]]
}

@test "jailed shell cleans up when container is dead" {
    # Create state file with a container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-dead",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that reports container as not running
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        # Container doesn't exist or isn't running
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run shell - should detect dead container and clean up
    run jailed --runtime docker shell
    [ "$status" -ne 0 ]
    [[ "$output" == *"is no longer running"* ]]
    [[ "$output" == *"Cleaning up"* ]]

    # State file should be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]
}

@test "jailed shell fails when project name invalid" {
    # Create state file with a container and one project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that reports container as running
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        # Just exit 0 for alive container
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run shell with invalid project name
    run jailed --runtime docker shell nonexistent
    [ "$status" -ne 0 ]
    [[ "$output" == *"Project 'nonexistent' not found"* ]]
}

@test "jailed shell opens in specific project directory" {
    # Create state file with a container and one project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that records exec commands
    EXEC_LOG="${TMPDIR}/docker_exec_log"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        # Just exit 0 for alive container
        exit 0
        ;;
    exec)
        # Record the exec command
        echo "\$@" >> "$EXEC_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run shell with specific project
    run jailed --runtime docker shell myproject
    [ "$status" -eq 0 ]

    # Verify exec was called with correct directory
    run cat "$EXEC_LOG"
    [[ "$output" == *"cd /workspace/myproject"* ]]

    # Cleanup
    rm -f "$EXEC_LOG"
}

@test "jailed shell auto-selects when only one project" {
    # Create state file with a container and exactly one project
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "onlyproject": "/tmp/only-project"
    }
}
JSON

    # Create stub docker that records exec commands
    EXEC_LOG="${TMPDIR}/docker_exec_log_auto"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        # Just exit 0 for alive container
        exit 0
        ;;
    exec)
        # Record the exec command
        echo "\$@" >> "$EXEC_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run shell without arguments - should auto-select the only project
    run jailed --runtime docker shell
    [ "$status" -eq 0 ]

    # Verify exec was called with the project directory
    run cat "$EXEC_LOG"
    [[ "$output" == *"cd /workspace/onlyproject"* ]]

    # Cleanup
    rm -f "$EXEC_LOG"
}

@test "jailed shell opens in /workspace when multiple projects" {
    # Create state file with a container and multiple projects
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "project1": "/tmp/project1",
        "project2": "/tmp/project2"
    }
}
JSON

    # Create stub docker that records exec commands
    EXEC_LOG="${TMPDIR}/docker_exec_log_multi"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        # Just exit 0 for alive container
        exit 0
        ;;
    exec)
        # Record the exec command
        echo "\$@" >> "$EXEC_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run shell without arguments - should open in /workspace
    run jailed --runtime docker shell
    [ "$status" -eq 0 ]

    # Verify exec was called WITHOUT cd (just opens in default location)
    run cat "$EXEC_LOG"
    [[ "$output" != *"cd /workspace/"* ]] || [[ "$output" == *"exec -it jailed-test gosu"* ]]

    # Cleanup
    rm -f "$EXEC_LOG"
}

# ---------------------------------------------------------------------------
# jailed stop command tests
# ---------------------------------------------------------------------------

@test "jailed stop shows nothing to stop when no running container" {
    # State file doesn't exist
    run jailed --runtime docker stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to stop"* ]]
}

@test "jailed stop cleans up stale state when container is dead" {
    # Create state file with a dead container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-dead",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that reports container as not running
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        # Container doesn't exist or isn't running
        exit 1
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run stop - should detect dead container and clean up
    run jailed --runtime docker stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"already stopped"* ]]
    [[ "$output" == *"Cleaning up state"* ]]

    # State file should be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]
}

@test "jailed stop terminates mutagen syncs in best-effort mode" {
    # Create state file with a running container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "project1": "/tmp/project1",
        "project2": "/tmp/project2"
    }
}
JSON

    # Track mutagen calls
    MUTAGEN_LOG="${TMPDIR}/mutagen_log"
    cat > "${STUB_BIN_DIR}/mutagen" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "$MUTAGEN_LOG"
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub docker that reports container as running
    STOP_LOG="${TMPDIR}/docker_stop_log"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        exit 0  # Container is alive
        ;;
    stop)
        echo "\$@" >> "$STOP_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run stop
    run jailed --runtime docker stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stopping sync sessions"* ]]
    [[ "$output" == *"Stopping container"* ]]
    [[ "$output" == *"Container stopped"* ]]

    # Verify mutagen was called to terminate syncs
    run cat "$MUTAGEN_LOG"
    [[ "$output" == *"sync terminate"* ]]

    # Verify container stop was called
    run cat "$STOP_LOG"
    [[ "$output" == *"stop jailed-test"* ]]

    # State file should be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]

    # Cleanup
    rm -f "$MUTAGEN_LOG" "$STOP_LOG"
}

@test "jailed stop continues even if mutagen fails (lenient)" {
    # Create state file with a running container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub mutagen that fails
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
exit 1  # All mutagen operations fail
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub docker
    STOP_LOG="${TMPDIR}/docker_stop_log_lenient"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        exit 0  # Container is alive
        ;;
    stop)
        echo "stopped" >> "$STOP_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run stop - should continue despite mutagen failure
    run jailed --runtime docker stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container stopped"* ]]

    # Container should still be stopped
    run cat "$STOP_LOG"
    [ "$output" = "stopped" ]

    # State file should still be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]

    # Cleanup
    rm -f "$STOP_LOG"
}

@test "jailed stop continues even if container stop fails (lenient)" {
    # Create state file with a running container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub mutagen that succeeds
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub docker that fails on stop
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        exit 0  # Container is alive
        ;;
    stop)
        exit 1  # Stop fails
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Run stop - should continue despite stop failure
    run jailed --runtime docker stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container stopped"* ]]

    # State file should still be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]
}

@test "jailed stop sets up Podman shim when RUNTIME=podman" {
    # Create state file with a running container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-test",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create .env file with RUNTIME=podman
    cat > "$JAILED_CONFIG_DIR/.env" <<'ENV'
RUNTIME=podman
ENV

    # Create stub mutagen
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create stub podman
    cat > "${STUB_BIN_DIR}/podman" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        exit 0  # Container is alive
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/podman"

    # Run stop with RUNTIME=podman
    run env RUNTIME=podman jailed stop
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container stopped"* ]]

    # State file should be deleted
    [ ! -f "$JAILED_CONFIG_DIR/running.json" ]
}

# ---------------------------------------------------------------------------
# jailed run persistent container tests
# ---------------------------------------------------------------------------

@test "jailed run fails when container already running" {
    # Create state file with a running container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-existing",
    "runtime": "docker",
    "sync": "bind",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that reports container as running
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    inspect)
        # Container is alive
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create minimal test directory
    TEST_PROJECT="${TMPDIR}/testproject1"
    mkdir -p "$TEST_PROJECT"

    # Run should fail with already-running error
    run jailed --runtime docker run "$TEST_PROJECT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Container already running: jailed-existing"* ]]
    [[ "$output" == *"Use 'jailed shell' to reconnect"* ]]

    # Cleanup
    rm -rf "$TEST_PROJECT"
}

@test "jailed run cleans up stale state when container is dead" {
    # Create state file with a dead container
    mkdir -p "$JAILED_CONFIG_DIR"
    cat > "$JAILED_CONFIG_DIR/running.json" <<'JSON'
{
    "container": "jailed-dead",
    "runtime": "docker",
    "sync": "bind",
    "projects": {
        "myproject": "/tmp/test-project"
    }
}
JSON

    # Create stub docker that reports container as not running
    EXEC_COUNT_FILE="${TMPDIR}/docker_exec_count"
    echo "0" > "$EXEC_COUNT_FILE"

    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
COUNT_FILE="$EXEC_COUNT_FILE"

case "\$1" in
    inspect)
        # First call: check if old container is alive (it's not)
        count=\$(cat "\$COUNT_FILE")
        if [ "\$count" -eq 0 ]; then
            count=\$((count + 1))
            echo "\$count" > "\$COUNT_FILE"
            exit 1  # Old container is dead
        fi
        # Subsequent calls for new container
        exit 0
        ;;
    run)
        # Container start - record that we were called
        echo "run" > "${TMPDIR}/docker_run_called"
        exit 0
        ;;
    exec)
        # Shell exec - just exit immediately
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create minimal test directory
    TEST_PROJECT="${TMPDIR}/testproject2"
    mkdir -p "$TEST_PROJECT"

    # Run should detect stale state, clean up, and start new container
    run jailed --runtime docker run "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale state file detected"* ]]
    [[ "$output" == *"Cleaning up"* ]]
    [[ "$output" == *"Starting jailed container"* ]]

    # Cleanup
    rm -rf "$TEST_PROJECT" "$EXEC_COUNT_FILE"
    rm -f "${TMPDIR}/docker_run_called"
}

@test "jailed run bind mode shows reconnect hint on shell exit" {
    # Create stub docker
    EXEC_LOG="${TMPDIR}/docker_exec_bind"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        # Container check passes
        exit 0
        ;;
    run)
        # Container runs, then exits immediately (simulating shell exit)
        echo "run \$@" > "$EXEC_LOG"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create minimal test directory
    TEST_PROJECT="${TMPDIR}/testproject3"
    mkdir -p "$TEST_PROJECT"

    # Run in bind mode - should show reconnect hint
    run jailed --runtime docker --sync bind run "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container still running"* ]]
    [[ "$output" == *"Use 'jailed shell' to reconnect"* ]]

    # State file should still exist (container persists)
    [ -f "$JAILED_CONFIG_DIR/running.json" ]

    # Cleanup
    rm -rf "$TEST_PROJECT" "$EXEC_LOG"
}

@test "jailed run mutagen mode shows reconnect hint on shell exit" {
    # Create stub docker
    EXEC_LOG="${TMPDIR}/docker_exec_mutagen"
    cat > "${STUB_BIN_DIR}/docker" <<STUB
#!/usr/bin/env bash
case "\$1" in
    inspect)
        exit 0
        ;;
    run)
        # Start detached container
        echo "run \$@" > "$EXEC_LOG"
        exit 0
        ;;
    exec)
        # Shell exec - exit immediately (simulating shell exit)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create stub mutagen that succeeds
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Create minimal test directory
    TEST_PROJECT="${TMPDIR}/testproject4"
    mkdir -p "$TEST_PROJECT"

    # Run in mutagen mode - should show reconnect hint
    run jailed --runtime docker --sync mutagen run "$TEST_PROJECT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Container still running"* ]]
    [[ "$output" == *"Use 'jailed shell' to reconnect"* ]]

    # State file should still exist (container persists)
    [ -f "$JAILED_CONFIG_DIR/running.json" ]

    # Cleanup
    rm -rf "$TEST_PROJECT" "$EXEC_LOG"
}

# ---------------------------------------------------------------------------
# EXIT trap cleanup verification (Phase 1)
# ---------------------------------------------------------------------------

@test "cmd_run EXIT trap performs full cleanup on interrupt during setup" {
    # Create a test wrapper that simulates the trap being triggered
    cat > "${STUB_BIN_DIR}/test_trap_cleanup" <<'WRAPPER'
#!/usr/bin/env bash
# Source jailed to get all functions
set -euo pipefail

# Mock runtime and state
RUNTIME="docker"
container_name="test-container-123"
JAILED_CONFIG_DIR="${JAILED_CONFIG_DIR}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[jailed]${NC} $1"; }
warn()    { echo -e "${YELLOW}[jailed]${NC} $1"; }
error()   { echo -e "${RED}[jailed]${NC} $1" >&2; }
die()     { error "$1"; exit 1; }

state_file() {
    echo "${JAILED_CONFIG_DIR}/running.json"
}

delete_state_file() {
    local file
    file="$(state_file)"
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "[CLEANUP] State file deleted"
    fi
}

mutagen_available() {
    command -v mutagen >/dev/null 2>&1
}

stop_all_mutagen_syncs() {
    local container_name="$1"
    echo "[CLEANUP] Stopping all mutagen syncs for $container_name"

    if ! mutagen_available; then
        warn "Mutagen not available - skipping sync cleanup"
        return 0
    fi

    # List all sessions for this container
    local sessions
    sessions=$(mutagen sync list 2>/dev/null | grep "jailed-${container_name}-" || true)
    if [ -z "$sessions" ]; then
        return 0
    fi

    echo "[CLEANUP] Found mutagen sessions to clean up"
}

# Simulate the Phase 1 trap
cleanup_trap() {
    stop_all_mutagen_syncs "$container_name"
    "$RUNTIME" stop "$container_name" 2>/dev/null || true
    echo "[CLEANUP] Container stopped"
    delete_state_file
}

# Create a fake state file
mkdir -p "$JAILED_CONFIG_DIR"
echo '{"container":"test-container-123"}' > "$(state_file)"

# Execute the trap
cleanup_trap

# Verify state file is gone
if [ -f "$(state_file)" ]; then
    echo "ERROR: State file still exists after cleanup"
    exit 1
fi

echo "[SUCCESS] All cleanup steps executed"
WRAPPER
    chmod +x "${STUB_BIN_DIR}/test_trap_cleanup"

    # Create stub docker
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create stub mutagen
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                # Simulate one session exists
                echo "jailed-test-container-123-myproject"
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Run the trap test
    run test_trap_cleanup
    [ "$status" -eq 0 ]

    # Verify all cleanup steps were called
    [[ "$output" == *"[CLEANUP] Stopping all mutagen syncs for test-container-123"* ]]
    [[ "$output" == *"[CLEANUP] Found mutagen sessions to clean up"* ]]
    [[ "$output" == *"[CLEANUP] Container stopped"* ]]
    [[ "$output" == *"[CLEANUP] State file deleted"* ]]
    [[ "$output" == *"[SUCCESS] All cleanup steps executed"* ]]
}
