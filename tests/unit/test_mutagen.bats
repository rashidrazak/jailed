#!/usr/bin/env bats
# test_mutagen.bats - unit tests for mutagen sync helpers

load test_helpers

# ---------------------------------------------------------------------------
# stop_mutagen_sync_strict() tests
# ---------------------------------------------------------------------------

@test "stop_mutagen_sync_strict fails when mutagen not available" {
    # Remove homebrew bin (where mutagen lives) from PATH
    local clean_path
    clean_path="$(echo "$PATH" | tr ':' '\n' | grep -v '/opt/homebrew/bin' | tr '\n' ':')"

    # Test wrapper should fail when mutagen is not in PATH
    run env PATH="$clean_path" test_strict_sync "test-container" "test-project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Mutagen not found"* ]]
}

@test "stop_mutagen_sync_strict returns 0 when session does not exist" {
    # Create stub mutagen that reports no session
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                # Simulate session not found
                exit 1
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    run test_strict_sync "test-container" "test-project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"No sync session found"* ]]
}

@test "stop_mutagen_sync_strict fails when flush fails" {
    # Create stub mutagen where flush fails
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                # Session exists
                exit 0
                ;;
            flush)
                # Flush fails
                exit 1
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    run test_strict_sync "test-container" "test-project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sync flush failed"* ]]
}

@test "stop_mutagen_sync_strict fails when terminate fails" {
    # Create stub mutagen where terminate fails
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                # Session exists
                exit 0
                ;;
            flush)
                # Flush succeeds
                exit 0
                ;;
            terminate)
                # Terminate fails
                exit 1
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    run test_strict_sync "test-container" "test-project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sync terminate failed"* ]]
}

@test "stop_mutagen_sync_strict fails when session still exists after terminate" {
    # Create stub mutagen where session persists after terminate
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    sync)
        case "$2" in
            list)
                # Session always exists (even after terminate)
                exit 0
                ;;
            flush)
                # Flush succeeds
                exit 0
                ;;
            terminate)
                # Terminate succeeds but session persists
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    run test_strict_sync "test-container" "test-project"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Sync session still exists"* ]]
}

@test "stop_mutagen_sync_strict succeeds on happy path" {
    # Create stub mutagen with full happy path
    cat > "${STUB_BIN_DIR}/mutagen" <<'STUB'
#!/usr/bin/env bash
# Track calls to verify session is removed
CALL_COUNT_FILE="${TMPDIR:-/tmp}/mutagen_calls"
call_num=$(($(cat "$CALL_COUNT_FILE" 2>/dev/null || echo 0) + 1))
echo $call_num > "$CALL_COUNT_FILE"

case "$1" in
    sync)
        case "$2" in
            list)
                # First call: session exists
                # Fourth call (verification): session gone
                if [ "$call_num" -le 1 ]; then
                    exit 0  # Session exists
                else
                    exit 1  # Session gone after terminate
                fi
                ;;
            flush)
                # Flush succeeds
                exit 0
                ;;
            terminate)
                # Terminate succeeds
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"

    # Clean up any previous call tracking
    rm -f "${TMPDIR:-/tmp}/mutagen_calls"

    run test_strict_sync "test-container" "test-project"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Flushing sync"* ]]
    [[ "$output" == *"Terminating sync"* ]]
}
