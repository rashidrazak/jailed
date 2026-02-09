#!/usr/bin/env bash
# test_helpers.bash - shared setup/teardown for jailed bats tests

# Project root (two levels up from tests/unit/)
JAILED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Make the jailed CLI callable by adding project root to PATH
export PATH="${JAILED_DIR}:${PATH}"

setup() {
    # Create a temporary config directory for each test
    JAILED_CONFIG_DIR="$(mktemp -d)"
    export JAILED_CONFIG_DIR

    # Create a temp bin directory with a stub "docker" so detect_runtime
    # succeeds even when no real container runtime is installed.
    STUB_BIN_DIR="$(mktemp -d)"
    cat > "${STUB_BIN_DIR}/docker" <<'STUB'
#!/usr/bin/env bash
# Stub docker binary for testing - exits successfully for any invocation
exit 0
STUB
    chmod +x "${STUB_BIN_DIR}/docker"

    # Create a stub "jq" for testing - outputs empty JSON for reads
    cat > "${STUB_BIN_DIR}/jq" <<'STUB'
#!/usr/bin/env bash
# Stub jq for testing - outputs empty JSON for reads
echo "{}"
STUB
    chmod +x "${STUB_BIN_DIR}/jq"

    export PATH="${STUB_BIN_DIR}:${PATH}"
}

teardown() {
    # Remove the temporary config directory
    if [ -n "${JAILED_CONFIG_DIR:-}" ] && [ -d "$JAILED_CONFIG_DIR" ]; then
        rm -rf "$JAILED_CONFIG_DIR"
    fi

    # Remove the stub bin directory
    if [ -n "${STUB_BIN_DIR:-}" ] && [ -d "$STUB_BIN_DIR" ]; then
        rm -rf "$STUB_BIN_DIR"
    fi
}
