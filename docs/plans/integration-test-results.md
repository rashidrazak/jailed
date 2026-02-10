# Persistent Containers Integration Test Results

**Status:** Manual Testing Required
**Date:** 2026-02-10
**Phase:** Phase 6 - Integration Testing

## Overview

This document outlines the manual integration tests for the persistent containers feature. These tests verify the complete workflow including normal usage, interrupt handling, multi-project support, and attach/detach functionality.

**All automated unit tests (68 tests) are passing.** These manual tests verify the full end-to-end workflows.

---

## Test Procedures

### Test 1: Normal Workflow

**Purpose:** Verify container persists after exit, shell reconnection works, and state is maintained between sessions.

**Steps:**

```bash
# Clean slate
./jailed stop || true
podman ps -a -q | xargs -r podman rm -f
mutagen sync terminate --all 2>/dev/null || true

# Start container
./jailed run .
pwd
ls -la /workspace
echo "test content" > /workspace/jailed/test.txt
cat /workspace/jailed/test.txt
exit

# Verify persistence
podman ps  # Should show running container
mutagen sync list  # Should show active session
cat ~/.config/jailed/running.json  # Should exist

# Reconnect
./jailed shell
cat /workspace/jailed/test.txt  # Should show "test content"
exit

# Cleanup
./jailed stop
podman ps  # Should be empty
mutagen sync list  # Should be empty
```

**Expected Results:**
- Container persists after first exit
- State file exists at ~/.config/jailed/running.json
- Mutagen sync remains active
- Reconnection via `shell` command works
- Test file content persists across sessions
- `stop` command cleans up all resources

**Status:** ⏸️ PENDING MANUAL TEST

---

### Test 2: Interrupt Handling

**Purpose:** Verify Ctrl+C during startup properly cleans up all resources.

**Steps:**

```bash
# Test Ctrl+C during startup
./jailed run .
# Press Ctrl+C after "Creating session..." appears

# Verify cleanup
podman ps  # Should be empty
mutagen sync list  # Should be empty
cat ~/.config/jailed/running.json  # Should not exist
```

**Expected Results:**
- No orphaned containers
- No orphaned mutagen sessions
- No state file left behind
- Clean exit with proper cleanup

**Status:** ⏸️ PENDING MANUAL TEST

---

### Test 3: Multi-Project Workflow

**Purpose:** Verify multiple projects can be managed simultaneously with project-specific shells.

**Steps:**

```bash
mkdir -p /tmp/proj-a /tmp/proj-b

# Start with multiple projects
./jailed run . /tmp/proj-a /tmp/proj-b
ls /workspace
# Should show: jailed, proj-a, proj-b
exit

# List projects
./jailed ls
# Should show all 3 projects

# Reconnect to specific project
./jailed shell proj-a
pwd  # Should be /workspace/proj-a
exit

# Stop all
./jailed stop
mutagen sync list  # Should be empty (all 3 syncs terminated)
```

**Expected Results:**
- All three projects mounted in /workspace
- `ls` command shows all projects
- `shell <project>` opens shell in correct working directory
- `stop` terminates all mutagen sessions (3 total)
- Complete cleanup of all resources

**Status:** ⏸️ PENDING MANUAL TEST

---

### Test 4: Attach/Detach with Persistence

**Purpose:** Verify hot-attach/detach functionality with running containers.

**Steps:**

```bash
./jailed run .
exit

# Hot-attach new project
./jailed attach /tmp/new-project
ls /workspace
# Should show: jailed, new-project
exit

# Reconnect and verify
./jailed shell
ls /workspace  # Both projects present
exit

# Detach project
./jailed detach new-project
./jailed shell
ls /workspace  # Only jailed remains
exit

./jailed stop
```

**Expected Results:**
- `attach` command works with running container
- New project visible in /workspace immediately
- State persists across shell reconnections
- `detach` removes project and terminates its sync
- State file updated correctly after attach/detach
- Detached project no longer accessible

**Status:** ⏸️ PENDING MANUAL TEST

---

## Test Execution Instructions

To run these tests manually:

1. **Prerequisites:**
   - Ensure Podman is running
   - Ensure Mutagen daemon is running
   - Clean any existing jailed resources: `./jailed stop || true`

2. **Run each test in sequence:**
   - Copy/paste commands from each test section
   - Verify expected results at each checkpoint
   - Document any failures or unexpected behavior below

3. **Record results:**
   - Update each test status (PASS ✅ / FAIL ❌)
   - Document any issues found
   - Note any deviations from expected behavior

---

## Test Results

### Summary Table

| Test | Status | Notes |
|------|--------|-------|
| Normal Workflow | ⏸️ PENDING | - |
| Interrupt Handling | ⏸️ PENDING | - |
| Multi-Project Workflow | ⏸️ PENDING | - |
| Attach/Detach Persistence | ⏸️ PENDING | - |

### Issues Found

_Document any issues discovered during testing:_

- **Issue 1:** [Description]
  - **Severity:** [Critical/High/Medium/Low]
  - **Reproduction:** [Steps]
  - **Workaround:** [If applicable]

- **Issue 2:** [Description]
  - **Severity:** [Critical/High/Medium/Low]
  - **Reproduction:** [Steps]
  - **Workaround:** [If applicable]

### Notes

_Additional observations during testing:_

- Performance notes
- Unexpected behaviors (non-critical)
- Suggestions for improvements

---

## Overall Status

**Status:** ⏸️ PENDING MANUAL TESTING

Once all tests pass:

**Overall: PASS ✅**

---

## Related Documentation

- [Persistent Containers Design](/Users/rashidrazak/Downloads/jailed/docs/plans/2026-02-10-persistent-containers-proper-cleanup.md)
- [Multi-Project Support](/Users/rashidrazak/Downloads/jailed/docs/plans/2026-02-10-multi-project-support.md)
- [Lifecycle QoL Design](/Users/rashidrazak/Downloads/jailed/docs/plans/2026-02-10-lifecycle-qol-design.md)

## Automated Test Coverage

All 68 automated unit tests passing:
- CLI argument parsing
- State file operations
- Container lifecycle
- Mutagen sync management
- Error handling
- Cleanup routines
- Multi-project support
- Attach/detach operations

These manual integration tests complement the automated test suite by verifying real-world end-to-end workflows.
