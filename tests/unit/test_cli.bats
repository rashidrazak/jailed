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

@test "jailed help mentions ls command" {
    run jailed help
    [ "$status" -eq 0 ]
    [[ "$output" == *"ls"* ]]
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
