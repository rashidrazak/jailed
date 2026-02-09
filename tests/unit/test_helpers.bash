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

    # Create a wrapper for "jq" that uses real jq but falls back to stub
    cat > "${STUB_BIN_DIR}/jq" <<'STUB'
#!/usr/bin/env bash
# jq wrapper for testing - use real jq if available, otherwise stub
if command -v /usr/bin/jq >/dev/null 2>&1; then
    exec /usr/bin/jq "$@"
elif command -v /opt/homebrew/bin/jq >/dev/null 2>&1; then
    exec /opt/homebrew/bin/jq "$@"
else
    # Fallback stub - outputs empty JSON
    echo "{}"
fi
STUB
    chmod +x "${STUB_BIN_DIR}/jq"

    # Create a test wrapper for stop_mutagen_sync_strict()
    cat > "${STUB_BIN_DIR}/test_strict_sync" <<'WRAPPER'
#!/usr/bin/env bash
# Source jailed functions
set -euo pipefail

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

mutagen_available() {
    command -v mutagen >/dev/null 2>&1
}

stop_mutagen_sync_strict() {
    local container_name="$1"
    local project_name="$2"
    local session_name="jailed-${container_name}-${project_name}"

    if ! mutagen_available; then
        die "Mutagen not found. Cannot safely stop sync for '$project_name'."
    fi

    # 1. Check session exists (already gone = safe)
    if ! mutagen sync list "$session_name" >/dev/null 2>&1; then
        warn "No sync session found for '$project_name'. Skipping sync shutdown."
        return 0
    fi

    # 2. Flush in-flight changes
    info "Flushing sync for '$project_name'..."
    if ! mutagen sync flush "$session_name"; then
        error "Sync flush failed for '$project_name'. Files left intact."
        return 1
    fi

    # 3. Terminate the session
    info "Terminating sync for '$project_name'..."
    if ! mutagen sync terminate "$session_name"; then
        error "Sync terminate failed for '$project_name'. Files left intact."
        return 1
    fi

    # 4. Verify session is gone
    if mutagen sync list "$session_name" >/dev/null 2>&1; then
        error "Sync session still exists for '$project_name'. Refusing to delete files."
        return 1
    fi

    return 0
}

stop_mutagen_sync_strict "$@"
WRAPPER
    chmod +x "${STUB_BIN_DIR}/test_strict_sync"

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
