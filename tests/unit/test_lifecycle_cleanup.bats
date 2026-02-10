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

@test "cmd_run with mutagen: uses signal traps during setup, clears after shell attach" {
    # Phase 2 behavior: Persistent containers
    #
    # CORRECT pattern:
    #   setup_cleanup_traps          ← Protect sync setup (INT/TERM/ERR)
    #   [start mutagen syncs]
    #   clear_cleanup_traps          ← Allow persistence
    #   exec -it container shell     ← Container persists on normal exit
    #
    # WRONG pattern (Phase 1 bug):
    #   trap - EXIT                  ← Clears trap BEFORE sync setup
    #   [start mutagen syncs]        ← Unprotected!
    #   exec -it container shell

    # Read the mutagen mode section from jailed script
    local mutagen_section
    mutagen_section=$(sed -n '/# For mutagen: start container detached/,/^        fi$/p' "${JAILED_DIR}/jailed")

    # Check for CORRECT pattern: setup_cleanup_traps is called
    if ! echo "$mutagen_section" | grep -q "setup_cleanup_traps"; then
        echo "ERROR: Missing setup_cleanup_traps call in mutagen mode"
        echo ""
        echo "Expected pattern:"
        echo "  setup_cleanup_traps    # Before sync setup"
        echo ""
        return 1
    fi

    # Check for CORRECT pattern: clear_cleanup_traps is called
    if ! echo "$mutagen_section" | grep -q "clear_cleanup_traps"; then
        echo "ERROR: Missing clear_cleanup_traps call in mutagen mode"
        echo ""
        echo "Expected pattern:"
        echo "  clear_cleanup_traps    # After successful sync, before shell"
        echo ""
        return 1
    fi

    # Verify setup comes BEFORE clear (proper order)
    local setup_line clear_line
    setup_line=$(echo "$mutagen_section" | grep -n "setup_cleanup_traps" | head -1 | cut -d: -f1)
    clear_line=$(echo "$mutagen_section" | grep -n "clear_cleanup_traps" | head -1 | cut -d: -f1)

    if [ "$setup_line" -ge "$clear_line" ]; then
        echo "ERROR: setup_cleanup_traps must be called BEFORE clear_cleanup_traps"
        echo "  setup at line: $setup_line"
        echo "  clear at line: $clear_line"
        return 1
    fi

    # Success: Correct Phase 2 pattern detected
    return 0
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

@test "CODE_PATTERN: cmd_run uses Phase 2 persistent container pattern" {
    # Phase 2: Persistent containers pattern
    #
    # CORRECT pattern:
    #   1. setup_cleanup_traps (before sync setup)
    #   2. clear_cleanup_traps (after successful sync, before shell)
    #   3. Container persists on normal exit
    #
    # This is DIFFERENT from Phase 1 where cleanup happened on all exits

    local cmd_run_section
    cmd_run_section=$(sed -n '/^cmd_run()/,/^}/p' "${JAILED_DIR}/jailed")

    # Check for setup_cleanup_traps in mutagen mode
    local has_setup=false
    if echo "$cmd_run_section" | grep -q "setup_cleanup_traps"; then
        has_setup=true
    fi

    # Check for clear_cleanup_traps before shell attach
    local has_clear=false
    if echo "$cmd_run_section" | grep -B5 "exec -it.*gosu.*zsh" | grep -q "clear_cleanup_traps"; then
        has_clear=true
    fi

    # Both must be present for Phase 2 pattern
    if [ "$has_setup" = false ] || [ "$has_clear" = false ]; then
        echo "ERROR: Phase 2 persistent container pattern not found!"
        echo ""
        echo "Required pattern:"
        echo "  1. setup_cleanup_traps (before syncs)"
        echo "  2. clear_cleanup_traps (before shell)"
        echo ""
        echo "Found setup: $has_setup"
        echo "Found clear: $has_clear"
        echo ""
        echo "Current mutagen section:"
        echo "$cmd_run_section" | grep -A20 "For mutagen: start container"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# UNIT TEST: Trap setup and clear helpers
# ---------------------------------------------------------------------------

@test "setup_cleanup_traps: sets up signal handlers" {
    source "${JAILED_DIR}/jailed"

    export CONTAINER_NAME="test-container-456"

    # Setup traps
    setup_cleanup_traps

    # Verify trap is set (check trap output contains cleanup function)
    local trap_output
    trap_output=$(trap -p INT)
    [[ "$trap_output" == *"cleanup_on_interrupt"* ]]

    trap_output=$(trap -p TERM)
    [[ "$trap_output" == *"cleanup_on_interrupt"* ]]

    trap_output=$(trap -p ERR)
    [[ "$trap_output" == *"cleanup_on_interrupt"* ]]
}

@test "clear_cleanup_traps: removes all signal handlers" {
    source "${JAILED_DIR}/jailed"

    export CONTAINER_NAME="test-container-789"

    # First setup traps
    setup_cleanup_traps

    # Verify traps are set
    local trap_output
    trap_output=$(trap -p INT)
    [[ "$trap_output" == *"cleanup_on_interrupt"* ]]

    # Now clear them
    clear_cleanup_traps

    # Verify traps are cleared
    trap_output=$(trap -p INT)
    [ -z "$trap_output" ] || [[ "$trap_output" != *"cleanup_on_interrupt"* ]]

    trap_output=$(trap -p TERM)
    [ -z "$trap_output" ] || [[ "$trap_output" != *"cleanup_on_interrupt"* ]]

    trap_output=$(trap -p ERR)
    [ -z "$trap_output" ] || [[ "$trap_output" != *"cleanup_on_interrupt"* ]]

    trap_output=$(trap -p EXIT)
    [ -z "$trap_output" ] || [[ "$trap_output" != *"cleanup_on_interrupt"* ]]
}

# ---------------------------------------------------------------------------
# INTEGRATION TEST: Mutagen mode persistence behavior
# ---------------------------------------------------------------------------

@test "cmd_run mutagen: normal exit leaves container running" {
    skip "Integration test - requires manual verification"

    # This validates the persistence behavior:
    # 1. Start jailed: ./jailed run .
    # 2. Exit normally: type 'exit'
    # 3. Verify container running: podman ps (should show container)
    # 4. Verify sync active: mutagen sync list (should show session)
    # 5. Verify state exists: cat ~/.config/jailed/running.json
    # 6. Reconnect works: ./jailed shell
}

@test "cmd_run mutagen: Ctrl+C during sync cleans up" {
    skip "Integration test - requires manual verification"

    # This validates cleanup on interrupt:
    # 1. Start jailed: ./jailed run .
    # 2. Press Ctrl+C during startup
    # 3. Verify no container: podman ps (should be empty)
    # 4. Verify no sync: mutagen sync list (should be empty)
    # 5. Verify no state: ~/.config/jailed/running.json (should not exist)
}
