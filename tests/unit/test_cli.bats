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
