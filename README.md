<p align="center">
  <img src="docs/images/logo.jpeg" alt="jailed logo" width="180" style="border-radius: 24px;">
</p>

<h1 align="center">jailed</h1>

<p align="center">
  <b>Secure, isolated container environment with 7 AI coding assistants</b>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20WSL2-lightgrey.svg" alt="Platform">
  <img src="https://img.shields.io/badge/runtime-Docker%20%7C%20Podman-2496ED?logo=docker&logoColor=white" alt="Runtime">
  <img src="https://img.shields.io/badge/shell-bash-4EAA25?logo=gnubash&logoColor=white" alt="Shell">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Claude%20Code-000000?logo=anthropic&logoColor=white" alt="Claude Code">
  <img src="https://img.shields.io/badge/OpenCode-FF6B6B?logo=opencode&logoColor=white" alt="OpenCode">
  <img src="https://img.shields.io/badge/Aider-3776AB?logo=python&logoColor=white" alt="Aider">
  <img src="https://img.shields.io/badge/Kimi%20Code-1E90FF?logo=moonshot&logoColor=white" alt="Kimi Code">
  <img src="https://img.shields.io/badge/Gemini%20CLI-4285F4?logo=google&logoColor=white" alt="Gemini CLI">
  <img src="https://img.shields.io/badge/Codex%20CLI-412991?logo=openai&logoColor=white" alt="Codex CLI">
  <img src="https://img.shields.io/badge/GitHub%20Copilot-000000?logo=github&logoColor=white" alt="GitHub Copilot">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Rust-orange?logo=rust&logoColor=white" alt="Rust">
  <img src="https://img.shields.io/badge/Node.js-339933?logo=nodedotjs&logoColor=white" alt="Node.js">
  <img src="https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/Go-EF3939?logo=go&logoColor=white" alt="uv">
</p>

---

**jailed** is a CLI tool that spawns a secure, isolated container environment pre-loaded with seven AI coding assistants — no AI tools need to be installed on your host machine. The only prerequisite is a container runtime (Docker or Podman). All agent configurations, authentication tokens, and session data persist on the host filesystem and are portable across machines.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [AI Agents](#ai-agents)
- [Configuration](#configuration)
- [Security](#security)
- [Testcontainers Support](#testcontainers-support)
- [Podman Support](#podman-support)
- [Filesystem Sync](#filesystem-sync)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Quick Start

```bash
# 1. Build the container image
jailed build

# 2. Launch jailed in your project directory
jailed /path/to/your/project

# 3. Authenticate agents inside the container
claude login
```

On first run, if no image is found, jailed will prompt you to build one automatically.

---

## Prerequisites

You need one of the following container runtimes installed on your host:

- **Docker** (Docker Engine or Docker Desktop)
- **Podman** (rootless or rootful)

Optional but recommended:

- **Mutagen** -- for high-performance bidirectional file sync (especially on macOS and Windows). If mutagen is not found, jailed falls back to bind mounts automatically.
  - macOS: `brew install mutagen-io/mutagen/mutagen`
  - Linux: download from [mutagen releases](https://github.com/mutagen-io/mutagen/releases)

---

## Installation

Clone the repository:

```bash
git clone https://github.com/rashidrazak/jailed.git
cd jailed
```

Optionally, add jailed to your PATH for global access:

```bash
# Add to ~/.bashrc, ~/.zshrc, or equivalent
export PATH="$PATH:/path/to/jailed"
```

Or create a symlink:

```bash
ln -s /path/to/jailed/jailed /usr/local/bin/jailed
```

Verify the installation:

```bash
jailed version
```

---

## Usage

### Start a Container

```bash
# Launch in the current directory
jailed .

# Launch with a specific project directory
jailed /path/to/project
```

### Build the Image

```bash
# Build with default settings (username: coder)
jailed build

# Build with a custom username
jailed build --name myuser
```

### Specify a Container Runtime

```bash
# Explicitly use Docker
jailed --runtime docker

# Explicitly use Podman
jailed --runtime podman
```

Runtime auto-detection order: `--runtime` flag, then `JAILED_RUNTIME` environment variable, then Podman if found in PATH, then Docker, then error.

### Choose a Sync Strategy

```bash
# Use mutagen (default, recommended for macOS)
jailed --sync mutagen

# Use bind mount (simpler, recommended for Linux)
jailed --sync bind
```

### Enable Testcontainers

```bash
# Mount the container runtime socket for Testcontainers support
jailed --testcontainers
```

### Other Commands

```bash
# Show version
jailed version

# Show help
jailed help
```

### Combining Flags

Flags can be combined freely:

```bash
jailed --runtime podman --sync bind --testcontainers /path/to/project
```

---

## AI Agents

All agents are pre-installed in the container image. No AI tools need to be installed on the host.

### Agent Reference

| Agent | Installation Method | Auth Command | Version Check |
|-------|-------------------|--------------|---------------|
| Claude Code | Native binary (curl installer) | `claude login` | `claude --version` |
| OpenCode | Native binary (GitHub releases) | `opencode auth login` | `opencode --version` |
| Aider | Python via uv (`uv tool install aider-chat`) | Set `OPENAI_API_KEY` or `ANTHROPIC_API_KEY` env var | `aider --version` |
| Kimi Code | Native binary (official installer) | `kimi auth login` | `kimi --version` |
| Gemini CLI | NPM (`@google/gemini-cli`) | `gemini auth` | `gemini --version` |
| Codex CLI | NPM (`@openai/codex`) | Set `OPENAI_API_KEY` env var | `codex --version` |
| GitHub Copilot CLI | GitHub CLI extension | `gh auth login` | `gh copilot --version` |

### Authentication

Authentication happens inside the running container. Credentials are written to config directories that are bind-mounted to the host, so they persist across container restarts and rebuilds:

```bash
# Start jailed, then run these inside the container:
claude login                  # Anthropic authentication
opencode auth login           # OpenCode authentication
gh auth login                 # GitHub authentication (for Copilot)
gemini auth                   # Google authentication (for Gemini CLI)
```

### Updating Agents

Updates made inside a running container are ephemeral -- they are lost when the container is destroyed. To persist updated agent versions, rebuild the image:

```bash
jailed build
```

For temporary in-container updates:

```bash
claude update                        # Claude Code self-update
aider --install-main-branch          # Aider update
gh extension upgrade copilot         # Copilot CLI update
npm update -g @google/gemini-cli     # Gemini CLI update
npm update -g @openai/codex          # Codex CLI update
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JAILED_RUNTIME` | Auto-detect | Force container runtime (`docker` or `podman`) |
| `JAILED_IMAGE` | `jailed:latest` | Custom image name and tag |
| `JAILED_USER` | `coder` | Username inside the container |
| `JAILED_CONFIG_DIR` | `$XDG_CONFIG_HOME/jailed` or `~/.config/jailed` | Override the config directory path |
| `JAILED_SYNC_STRATEGY` | `mutagen` | Sync strategy (`mutagen` or `bind`) |

An example `.env` file is provided at `.env.example` in the repository root.

### Config Directory Structure

All persistent data is stored under a single config directory:

```
~/.config/jailed/
  agents/
    claude/              # Claude Code config and auth (~/.claude)
    opencode/            # OpenCode config (~/.config/opencode)
    opencode-data/       # OpenCode data (~/.local/share/opencode)
    aider/               # Aider config (~/.aider)
    kimi/                # Kimi Code config (~/.kimi)
    gemini/              # Gemini CLI config (~/.gemini)
    codex/               # Codex CLI config (~/.codex)
    copilot/             # GitHub Copilot config (~/.config/github-copilot)
    gh/                  # GitHub CLI config (~/.config/gh)
  sessions/              # Session logs and history
  cache/                 # Shared cache (pip, npm, go modules)
```

### Portability

All agent configs, auth tokens, and session data are contained within the single `jailed/` directory. To migrate to another machine:

```bash
# On the source machine
tar czf jailed-config.tar.gz -C "${XDG_CONFIG_HOME:-$HOME/.config}" jailed/

# On the target machine
tar xzf jailed-config.tar.gz -C "${XDG_CONFIG_HOME:-$HOME/.config}"
```

---

## Security

jailed is designed with defense-in-depth. The container is locked down by default with multiple overlapping security controls.

### Isolation

- **Filesystem**: Only the synced project directory and bind-mounted config directories are accessible. The container has no access to the host `$HOME` or system files.
- **Network**: Unrestricted outbound (required for LLM API calls and package downloads). No inbound ports exposed by default.
- **Process**: The container runs as a non-root user (`coder` by default) with UID/GID matching the host user.

### Docker Security Flags

When using Docker, the following hardening flags are applied automatically:

- `--security-opt no-new-privileges` -- prevents privilege escalation
- `--cap-drop ALL` -- drops all Linux capabilities
- `--read-only` -- enforces a read-only root filesystem
- `--tmpfs /tmp --tmpfs /run` -- provides writable temporary filesystems where needed
- No `--privileged` flag is ever used

### Podman Security

When using Podman, rootless mode provides additional isolation:

- `--userns=keep-id` -- maps the container user to the host user without root escalation
- `:z` SELinux labels on bind mounts for SELinux-enabled hosts
- No `--privileged` flag is ever used

### Blast Radius

- `rm -rf /` inside the container destroys only the container filesystem. Host files remain at the last-synced state.
- `rm -rf /workspace` affects only the synced project files, which is the intended writable scope.
- No host SSH keys, GPG keys, or other credentials are mounted unless explicitly configured.

### Socket Mounting

The container runtime socket (Docker or Podman) is never mounted by default. It is only available when explicitly requested via the `--testcontainers` flag.

---

## Testcontainers Support

jailed supports mounting the host's container runtime socket into the container, allowing Testcontainers libraries to create and manage sibling containers on the host.

### Enabling Testcontainers

```bash
jailed --testcontainers
```

### How It Works

1. The host's container runtime socket is bind-mounted into the container at `/var/run/docker.sock`.
2. The `DOCKER_HOST` environment variable is set inside the container to point to the socket.
3. Testcontainers libraries detect the socket and use it to create containers on the host.
4. Test containers appear in `docker ps` / `podman ps` on the host.
5. Testcontainers cleanup hooks automatically remove containers after tests complete.

### Socket Paths

| Runtime | Host Socket Path | Container Mount Target |
|---------|-----------------|----------------------|
| Docker | `/var/run/docker.sock` | `/var/run/docker.sock` |
| Rootless Podman | `/run/user/$UID/podman/podman.sock` | `/var/run/docker.sock` |
| Rootful Podman | `/run/podman/podman.sock` | `/var/run/docker.sock` |

The mount target is always `/var/run/docker.sock` because Testcontainers libraries default to that path.

### Example: Node.js

```javascript
const { GenericContainer } = require("testcontainers");

const container = await new GenericContainer("postgres:15-alpine")
  .withExposedPorts(5432)
  .start();
```

### Example: Python

```python
from testcontainers.postgres import PostgresContainer

with PostgresContainer("postgres:15-alpine") as postgres:
    connection_url = postgres.get_connection_url()
```

### Example: Java

```java
@Container
static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:15-alpine");

@Container
static GenericContainer<?> redis = new GenericContainer<>("redis:7-alpine")
    .withExposedPorts(6379);
```

### Important Notes

- Test containers run on the **host**, not nested inside the jailed container.
- Volume mounts specified in Testcontainers code reference **host** paths, not container paths.
- Downloaded images are shared with the host's image cache.

---

## Podman Support

jailed has first-class support for Podman, including rootless mode.

### Rootless Podman

Podman runs entirely in user space without requiring root privileges. jailed uses `--userns=keep-id` to map the container user to the host user transparently.

```bash
jailed --runtime podman
```

### SELinux

On SELinux-enabled hosts (Fedora, RHEL, CentOS), jailed automatically applies the `:z` suffix to bind mounts so that the container has the correct security context to access mounted volumes.

### Mutagen with Podman

When using mutagen sync with Podman, jailed sets the `DOCKER_HOST` environment variable to point to the Podman socket so that mutagen can communicate with the Podman daemon via the Docker-compatible API:

```
DOCKER_HOST=unix:///run/user/$UID/podman/podman.sock
```

Make sure the Podman socket is active:

```bash
systemctl --user enable --now podman.socket
```

### Runtime Auto-Detection

If both Docker and Podman are installed, jailed prefers Podman. Override this with `--runtime docker` or `JAILED_RUNTIME=docker`.

---

## Filesystem Sync

jailed supports two strategies for syncing the project directory into the container.

### Mutagen (Default)

Mutagen provides bidirectional file synchronization with near-native filesystem performance inside the container.

**When to use mutagen:**
- macOS (Docker Desktop) -- bind mount performance is significantly slower for file-heavy operations like `npm install` or `go build`
- Windows (WSL2 + Docker Desktop)
- Any environment where bind mount I/O is a bottleneck

**How it works:**
- jailed starts the container, then creates a mutagen sync session between the host project directory and `/workspace` inside the container.
- Changes propagate bidirectionally with minimal latency.
- The sync session is automatically terminated when the container exits.
- The `.git` directory is ignored by mutagen to avoid conflicts.

```bash
jailed --sync mutagen /path/to/project
```

### Bind Mount

A traditional Docker/Podman bind mount maps the host directory directly into the container.

**When to use bind mounts:**
- Linux -- bind mount performance is native and there is no overhead
- Simple setups where mutagen installation is not desired
- Debugging scenarios where instant filesystem consistency is required

```bash
jailed --sync bind /path/to/project
```

### Fallback Behavior

If mutagen is selected but not installed on the host, jailed prints a warning with installation instructions and falls back to bind mount automatically.

---

## Troubleshooting

### Image not found

```
[jailed] Image 'jailed:latest' not found.
```

**Solution:** Run `jailed build` to build the container image. On first run, jailed will also prompt you to build automatically.

### Neither docker nor podman found

```
Neither 'docker' nor 'podman' found in PATH.
```

**Solution:** Install Docker or Podman. On macOS, install Docker Desktop or Podman via `brew install podman`. On Linux, install via your package manager.

### Mutagen not found

```
[jailed] Mutagen not found. Install it for better file sync performance.
```

**Solution:** Install mutagen or use bind mounts instead:

```bash
# Install mutagen
brew install mutagen-io/mutagen/mutagen    # macOS

# Or use bind mount as an alternative
jailed --sync bind
```

### Permission denied on socket (Testcontainers)

```
Got permission denied while trying to connect to the Docker daemon socket
```

**Solution:** The entrypoint script handles socket permissions automatically. If the issue persists, verify the socket exists and the host user has access:

```bash
# Docker
ls -la /var/run/docker.sock

# Podman (rootless)
ls -la /run/user/$(id -u)/podman/podman.sock
```

### Files not syncing (Mutagen)

**Solution:** Check the mutagen session status:

```bash
mutagen sync list
```

If the session is paused or errored, terminate it and restart jailed:

```bash
mutagen sync terminate --all
jailed /path/to/project
```

### Container starts but agents are missing

**Solution:** Rebuild the image to pick up the latest agent installations:

```bash
jailed build
```

### UID/GID mismatch (files owned by wrong user)

**Solution:** The entrypoint script remaps the container user's UID/GID to match the host user. If this fails, verify your host UID/GID:

```bash
id -u   # Should match HOST_UID inside container
id -g   # Should match HOST_GID inside container
```

Then rebuild and restart:

```bash
jailed build
jailed /path/to/project
```

### Read-only filesystem errors inside container (Docker)

Docker runs with `--read-only` by default. Writable locations are limited to:
- `/workspace` (your project directory)
- `/tmp`
- `/run`
- `/home/coder/.cache`
- Bind-mounted config directories under `/home/coder/`

If an agent or tool requires writing to another location, this is expected behavior enforcing the security model.

### Podman socket not active

```bash
# Enable the Podman socket (required for mutagen and Testcontainers)
systemctl --user enable --now podman.socket

# Verify
podman info
```

---

## Contributing

Contributions are welcome. To get started:

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/my-feature`.
3. Make your changes.
4. Run the test suite:
   ```bash
   # Unit tests (requires bats)
   bats tests/unit/

   # Integration tests
   npm test --prefix tests/integration/
   ```
5. Commit using conventional commit format: `feat: add feature`, `fix: resolve issue`, etc.
6. Open a pull request with a clear description of the changes.

### Development Tools

- **Shell tests**: [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System)
- **Integration tests**: Testcontainers (Node.js or Python)
- **Linting**: ShellCheck for bash scripts

---

## Credit

Inspired by [glennvdv/opencode-dockerized](https://github.com/glennvdv/opencode-dockerized)

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
