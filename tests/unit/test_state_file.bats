#!/usr/bin/env bats
# test_state_file.bats - unit tests for state file management

load test_helpers

# ---------------------------------------------------------------------------
# require_jq
# ---------------------------------------------------------------------------

@test "require_jq succeeds when jq is installed" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    run require_jq
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# write_state_file
# ---------------------------------------------------------------------------

@test "write_state_file creates valid JSON with correct structure" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    local projects='{"projectA":"/path/to/projectA"}'
    write_state_file "test-container" "podman" "mutagen" "$projects"

    [ -f "$STATE_FILE" ]

    # Verify JSON structure
    run jq -r '.container' "$STATE_FILE"
    [ "$status" -eq 0 ]
    [ "$output" = "test-container" ]

    run jq -r '.runtime' "$STATE_FILE"
    [ "$output" = "podman" ]

    run jq -r '.sync' "$STATE_FILE"
    [ "$output" = "mutagen" ]

    run jq -r '.projects.projectA' "$STATE_FILE"
    [ "$output" = "/path/to/projectA" ]
}

# ---------------------------------------------------------------------------
# get_running_container
# ---------------------------------------------------------------------------

@test "get_running_container returns empty string when state file missing" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Ensure state file doesn't exist
    rm -f "$STATE_FILE"

    run get_running_container
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "get_running_container returns container name from state file" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    local projects='{"projectA":"/path/to/projectA"}'
    write_state_file "test-container-123" "podman" "mutagen" "$projects"

    run get_running_container
    [ "$status" -eq 0 ]
    [ "$output" = "test-container-123" ]
}

# ---------------------------------------------------------------------------
# is_container_alive
# ---------------------------------------------------------------------------

@test "is_container_alive returns false for empty container name" {
    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    run is_container_alive ""
    [ "$status" -ne 0 ]
}

@test "is_container_alive returns false for non-existent container" {
    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    run is_container_alive "non-existent-container-xyz"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# add_project_to_state
# ---------------------------------------------------------------------------

@test "add_project_to_state adds project to existing state" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Create initial state
    local projects='{"projectA":"/path/to/projectA"}'
    write_state_file "test-container" "podman" "mutagen" "$projects"

    # Add new project
    add_project_to_state "projectB" "/path/to/projectB"

    # Verify both projects exist
    run jq -r '.projects.projectA' "$STATE_FILE"
    [ "$output" = "/path/to/projectA" ]

    run jq -r '.projects.projectB' "$STATE_FILE"
    [ "$output" = "/path/to/projectB" ]
}

@test "add_project_to_state fails when state file missing" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Ensure state file doesn't exist
    rm -f "$STATE_FILE"

    run add_project_to_state "projectB" "/path/to/projectB"
    [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# remove_project_from_state
# ---------------------------------------------------------------------------

@test "remove_project_from_state removes project from state" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Create initial state with two projects
    local projects='{"projectA":"/path/to/projectA","projectB":"/path/to/projectB"}'
    write_state_file "test-container" "podman" "mutagen" "$projects"

    # Remove one project
    remove_project_from_state "projectA"

    # Verify projectA is gone
    run jq -r '.projects.projectA' "$STATE_FILE"
    [ "$output" = "null" ]

    # Verify projectB still exists
    run jq -r '.projects.projectB' "$STATE_FILE"
    [ "$output" = "/path/to/projectB" ]
}

@test "remove_project_from_state handles missing state file gracefully" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Ensure state file doesn't exist
    rm -f "$STATE_FILE"

    run remove_project_from_state "projectA"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# delete_state_file
# ---------------------------------------------------------------------------

@test "delete_state_file removes state file" {
    # Skip if jq is not installed
    if ! command -v jq >/dev/null 2>&1; then
        skip "jq is not installed"
    fi

    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Create state file
    local projects='{"projectA":"/path/to/projectA"}'
    write_state_file "test-container" "podman" "mutagen" "$projects"

    [ -f "$STATE_FILE" ]

    # Delete it
    delete_state_file

    [ ! -f "$STATE_FILE" ]
}

@test "delete_state_file handles missing file gracefully" {
    # Source functions from jailed script
    source "$JAILED_DIR/jailed"

    # Ensure state file doesn't exist
    rm -f "$STATE_FILE"

    run delete_state_file
    [ "$status" -eq 0 ]
}
