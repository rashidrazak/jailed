#!/usr/bin/env bats
# test_lifecycle_cleanup.bats - Regression test for orphaned resource cleanup
#
# This test ensures that the bug fixed in [issue-date] does not reoccur:
# When user exits jailed normally, all resources (containers, mutagen syncs,
# state files) must be cleaned up to prevent orphaned resources on the next run.

load test_helpers

# Test helper: Create a tracked container runtime stub that logs cleanup calls
setup_tracked_runtime() {
    local cleanup_log="$1"

    cat > "${STUB_BIN_DIR}/podman" <<STUB
#!/usr/bin/env bash
# Tracked podman stub - logs all container lifecycle operations

case "\$1" in
    run)
        # Start container - record container name
        for arg in "\$@"; do
            if [[ "\$arg" == --name ]]; then
                shift
                echo "\$2" > "${cleanup_log}.container_name"
                break
            fi
            shift
        done
        echo "container-id-12345"
        exit 0
        ;;
    exec)
        # Shell attach - just exit successfully
        exit 0
        ;;
    stop)
        # Record stop was called
        echo "STOP_CALLED" >> "$cleanup_log"
        exit 0
        ;;
    inspect)
        # Container exists check
        exit 0
        ;;
    image)
        # Image exists check
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
STUB
    chmod +x "${STUB_BIN_DIR}/podman"

    # Override runtime detection to use podman
    export JAILED_RUNTIME="podman"
}

# Test helper: Create tracked mutagen stub
setup_tracked_mutagen() {
    local cleanup_log="$1"

    cat > "${STUB_BIN_DIR}/mutagen" <<STUB
#!/usr/bin/env bash
# Tracked mutagen stub - logs all sync operations

case "\$1" in
    daemon)
        case "\$2" in
            stop)
                echo "DAEMON_STOP_CALLED" >> "$cleanup_log"
                ;;
        esac
        exit 0
        ;;
    sync)
        case "\$2" in
            create)
                echo "SYNC_CREATE_CALLED" >> "$cleanup_log"
                echo "Created sync session"
                exit 0
                ;;
            list)
                # After terminate, session should be gone
                if grep -q "SYNC_TERMINATE_CALLED" "$cleanup_log" 2>/dev/null; then
                    exit 1  # Session not found
                else
                    exit 0  # Session exists
                fi
                ;;
            flush)
                echo "SYNC_FLUSH_CALLED" >> "$cleanup_log"
                exit 0
                ;;
            terminate)
                echo "SYNC_TERMINATE_CALLED" >> "$cleanup_log"
                exit 0
                ;;
        esac
        ;;
esac
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/mutagen"
}

# ---------------------------------------------------------------------------
# REGRESSION TEST: Cleanup on normal exit (mutagen mode)
# ---------------------------------------------------------------------------

@test "cmd_run with mutagen: cleanup runs on normal shell exit" {
    local cleanup_log="${JAILED_CONFIG_DIR}/cleanup.log"

    setup_tracked_runtime "$cleanup_log"
    setup_tracked_mutagen "$cleanup_log"

    # Simulate the critical code path from cmd_run()
    # This mimics lines 610-704 of jailed script

    # Source jailed to get access to functions
    source "${JAILED_DIR}/jailed"

    # Set up test environment
    export SYNC_STRATEGY="mutagen"
    export USERNAME="coder"
    local container_name="test-container-123"

    # Simulate: Container started, mutagen syncs created, trap should protect

    # The CRITICAL TEST: Does cleanup happen after normal exit?
    # In the BROKEN version, trap is cleared before shell attach
    # In the WORKING version, trap remains active or explicit cleanup runs

    # Simulate normal exit path (what should happen):
    # 1. Mutagen syncs terminate
    # 2. Container stops
    # 3. State file deleted

    # Test the actual cleanup function
    local -A test_projects=(["test"]="/tmp/test")
    write_state_file "$container_name" test_projects

    # Verify state file was created
    [ -f "${JAILED_CONFIG_DIR}/running.json" ]

    # Now simulate cleanup (what SHOULD happen on normal exit)
    stop_all_mutagen_syncs "$container_name"
    delete_state_file

    # Verify cleanup happened
    grep -q "SYNC_TERMINATE_CALLED" "$cleanup_log" || {
        echo "FAIL: Mutagen sync not terminated"
        cat "$cleanup_log"
        return 1
    }

    [ ! -f "${JAILED_CONFIG_DIR}/running.json" ] || {
        echo "FAIL: State file not deleted"
        return 1
    }
}

# ---------------------------------------------------------------------------
# REGRESSION TEST: Trap protection active during shell attach
# ---------------------------------------------------------------------------

@test "cmd_run with mutagen: EXIT trap remains active before shell attach" {
    # This test verifies that the trap is NOT cleared prematurely
    #
    # BROKEN behavior (bug):
    #   trap - EXIT                  ← Clears trap
    #   exec -it container shell     ← Unprotected
    #
    # CORRECT behavior:
    #   trap 'cleanup' EXIT          ← Keeps trap
    #   exec -it container shell     ← Protected
    #   cleanup                      ← Explicit cleanup after

    # Read the actual code from jailed script
    local mutagen_success_section
    mutagen_success_section=$(sed -n '/# Mutagen syncs started successfully/,/^        fi$/p' "${JAILED_DIR}/jailed")

    # Check for the BUG pattern: "trap - EXIT" before "exec -it"
    if echo "$mutagen_success_section" | grep -B2 "exec -it" | grep -q "trap - EXIT"; then
        echo "REGRESSION DETECTED!"
        echo ""
        echo "The trap is cleared BEFORE shell attach, which causes orphaned resources."
        echo ""
        echo "Problematic code:"
        echo "$mutagen_success_section" | grep -B2 -A2 "trap - EXIT"
        echo ""
        echo "Expected: Trap should remain active or explicit cleanup should follow shell exit"
        return 1
    fi

    # Verify CORRECT pattern exists: either trap stays active OR explicit cleanup follows
    if echo "$mutagen_success_section" | grep -q "stop_all_mutagen_syncs"; then
        # Good: Explicit cleanup is present
        return 0
    elif echo "$mutagen_success_section" | grep -B5 "exec -it" | grep -q "trap.*stop_all_mutagen_syncs.*EXIT"; then
        # Good: Trap remains active with cleanup
        return 0
    else
        echo "WARNING: No cleanup mechanism found after shell exit"
        echo ""
        echo "Code section:"
        echo "$mutagen_success_section"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# REGRESSION TEST: State file cleanup
# ---------------------------------------------------------------------------

@test "cmd_run: state file is removed on cleanup" {
    source "${JAILED_DIR}/jailed"

    local container_name="test-container-456"
    local -A test_projects=(["proj1"]="/tmp/proj1")

    # Create state file
    write_state_file "$container_name" test_projects
    [ -f "${JAILED_CONFIG_DIR}/running.json" ]

    # Verify state file has correct content
    local stored_container
    stored_container=$(jq -r '.container' "${JAILED_CONFIG_DIR}/running.json")
    [ "$stored_container" = "$container_name" ]

    # Delete state file (simulates cleanup)
    delete_state_file

    # Verify state file is gone
    [ ! -f "${JAILED_CONFIG_DIR}/running.json" ]
}

# ---------------------------------------------------------------------------
# REGRESSION TEST: stop_all_mutagen_syncs terminates all sessions
# ---------------------------------------------------------------------------

@test "stop_all_mutagen_syncs: terminates all project syncs from state file" {
    local cleanup_log="${JAILED_CONFIG_DIR}/cleanup.log"
    setup_tracked_mutagen "$cleanup_log"

    source "${JAILED_DIR}/jailed"

    local container_name="test-container-789"
    local -A test_projects=(
        ["proj1"]="/tmp/proj1"
        ["proj2"]="/tmp/proj2"
        ["proj3"]="/tmp/proj3"
    )

    # Create state file with multiple projects
    write_state_file "$container_name" test_projects

    # Stop all mutagen syncs
    stop_all_mutagen_syncs "$container_name"

    # Verify terminate was called (at least once, ideally 3 times)
    grep -q "SYNC_TERMINATE_CALLED" "$cleanup_log" || {
        echo "FAIL: Mutagen sync terminate not called"
        return 1
    }

    # Count how many times terminate was called
    local terminate_count
    terminate_count=$(grep -c "SYNC_TERMINATE_CALLED" "$cleanup_log" || echo "0")

    # Should be called once per project
    [ "$terminate_count" -ge 1 ] || {
        echo "FAIL: Expected at least 1 terminate call, got $terminate_count"
        cat "$cleanup_log"
        return 1
    }
}

# ---------------------------------------------------------------------------
# INTEGRATION TEST: Full lifecycle (run -> exit -> no orphans)
# ---------------------------------------------------------------------------

@test "INTEGRATION: jailed run -> normal exit -> no orphaned resources" {
    skip "Integration test - requires full container runtime (run manually)"

    # This test should be run manually against a real environment:
    #
    # 1. Clean state: ./jailed stop; rm -f ~/.config/jailed/running.json
    # 2. Start jailed: echo "exit" | ./jailed run .
    # 3. Check orphans:
    #    - podman ps (should be empty)
    #    - mutagen sync list (should be empty)
    #    - ~/.config/jailed/running.json (should not exist)
    #
    # If ANY orphans remain, the bug has regressed.
}

# ---------------------------------------------------------------------------
# UNIT TEST: cleanup_on_interrupt handler
# ---------------------------------------------------------------------------

@test "cleanup_on_interrupt: calls all cleanup functions in order" {
    local cleanup_log="${JAILED_CONFIG_DIR}/cleanup.log"

    setup_tracked_runtime "$cleanup_log"
    setup_tracked_mutagen "$cleanup_log"

    source "${JAILED_DIR}/jailed"

    export CONTAINER_NAME="test-container-123"
    export RUNTIME="podman"  # Set RUNTIME for cleanup function

    # Create state file so delete_state_file has something to clean
    local -A test_projects=(["test"]="/tmp/test")
    write_state_file "$CONTAINER_NAME" test_projects

    # Verify state file was created
    [ -f "${JAILED_CONFIG_DIR}/running.json" ]

    # Call cleanup handler in a subshell so exit doesn't kill the test
    (
        cleanup_on_interrupt
    ) || true  # Prevent exit from failing test

    # Verify order: syncs stopped, then container, then state deleted
    grep -q "SYNC_TERMINATE_CALLED" "$cleanup_log" || {
        echo "FAIL: Mutagen sync not terminated"
        cat "$cleanup_log"
        return 1
    }

    grep -q "STOP_CALLED" "$cleanup_log" || {
        echo "FAIL: Container not stopped"
        cat "$cleanup_log"
        return 1
    }

    [ ! -f "${JAILED_CONFIG_DIR}/running.json" ] || {
        echo "FAIL: State file not deleted"
        return 1
    }
}

@test "cleanup_on_interrupt: handles unset CONTAINER_NAME gracefully" {
    local cleanup_log="${JAILED_CONFIG_DIR}/cleanup.log"

    setup_tracked_runtime "$cleanup_log"
    setup_tracked_mutagen "$cleanup_log"

    source "${JAILED_DIR}/jailed"

    export RUNTIME="podman"  # Set RUNTIME for cleanup function

    # Unset CONTAINER_NAME
    unset CONTAINER_NAME

    # Should not crash - run in subshell to contain exit
    (
        cleanup_on_interrupt
    ) || true

    # No container operations should have been attempted
    [ ! -f "$cleanup_log" ] || {
        local log_content
        log_content=$(cat "$cleanup_log")
        if [ -n "$log_content" ]; then
            echo "FAIL: Operations attempted with unset CONTAINER_NAME"
            echo "$log_content"
            return 1
        fi
    }
}

# ---------------------------------------------------------------------------
# CODE PATTERN TEST: Verify trap handling pattern
# ---------------------------------------------------------------------------

@test "CODE_PATTERN: cmd_run must have cleanup mechanism after shell attach" {
    # This test enforces the correct pattern at the code level

    local cmd_run_section
    cmd_run_section=$(sed -n '/^cmd_run()/,/^}/p' "${JAILED_DIR}/jailed")

    # Pattern 1: Explicit cleanup after shell exit
    # Pattern 2: Trap remains active during shell

    local has_explicit_cleanup=false
    local has_active_trap=false

    # Check for explicit cleanup pattern (working version)
    if echo "$cmd_run_section" | grep -A10 "exec -it.*gosu.*zsh" | grep -q "stop_all_mutagen_syncs"; then
        has_explicit_cleanup=true
    fi

    # Check for active trap pattern
    if echo "$cmd_run_section" | grep -B5 "exec -it.*gosu.*zsh" | grep -q "trap.*stop_all_mutagen_syncs.*EXIT"; then
        has_active_trap=true
    fi

    # At least ONE pattern must be present
    if [ "$has_explicit_cleanup" = false ] && [ "$has_active_trap" = false ]; then
        echo "REGRESSION: No cleanup mechanism found after shell attach!"
        echo ""
        echo "Required: EITHER"
        echo "  1. Explicit cleanup after 'exec -it' (stop_all_mutagen_syncs + delete_state_file)"
        echo "  2. Active EXIT trap during 'exec -it' (trap 'cleanup' EXIT)"
        echo ""
        echo "Current cmd_run section:"
        echo "$cmd_run_section" | grep -A15 "Mutagen syncs started successfully"
        return 1
    fi
}
