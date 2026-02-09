# ============================================================
# Stage 1: Builder - download agent binaries
# ============================================================
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates wget unzip \
    && rm -rf /var/lib/apt/lists/*

ARG TARGETARCH

# Download Go
ARG GO_VERSION=1.24.0
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" \
    | tar -C /usr/local -xz

# Download gosu for entrypoint privilege dropping
RUN curl -fsSL "https://github.com/tianon/gosu/releases/latest/download/gosu-${TARGETARCH}" \
    -o /usr/local/bin/gosu && chmod +x /usr/local/bin/gosu

# Download OpenCode binary (installs to ~/.opencode/bin/)
RUN (curl -fsSL https://opencode.ai/install | bash \
    && mv /root/.opencode/bin/opencode /usr/local/bin/opencode) \
    || touch /usr/local/bin/opencode


# ============================================================
# Stage 2: Runtime
# ============================================================
FROM ubuntu:24.04

LABEL maintainer="jailed"
LABEL description="Secure AI coding assistant container with multiple CLI agents"

ARG USERNAME=coder
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ="Asia/Kuala_Lumpur"

# --- System packages ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh \
    git \
    curl \
    wget \
    jq \
    zip \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    build-essential \
    openssh-client \
    locales \
    less \
    vim \
    tree \
    htop \
    ripgrep \
    fd-find \
    && rm -rf /var/lib/apt/lists/*

# --- Locale ---
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

# --- Docker CLI (for Testcontainers socket access) ---
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# --- Node.js LTS (via NodeSource) ---
ARG NODE_VERSION=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- Python 3 + pip + venv + uv ---
ARG PYTHON_VERSION=3
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python3-pip python3-venv python3-full \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx || true

# --- Go (from builder) ---
ARG GO_VERSION=1.24.0
COPY --from=builder /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"

# --- gosu (from builder) ---
COPY --from=builder /usr/local/bin/gosu /usr/local/bin/gosu

# --- Create non-root user ---
# Use -o (non-unique) to handle GID conflicts (e.g. macOS host GID 20 = dialout in Ubuntu)
RUN groupadd -g "${USER_GID}" -o "${USERNAME}" && \
    useradd -m -s /bin/zsh -u "${USER_UID}" -g "${USER_GID}" -o "${USERNAME}" && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# --- Rust (installed as user) ---
ARG RUST_VERSION=stable
USER ${USERNAME}
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain ${RUST_VERSION}
ENV PATH="/home/${USERNAME}/.cargo/bin:${PATH}"
USER root

# --- Install AI agents ---

# 1. OpenCode (native binary from builder, retry install if builder produced empty placeholder)
COPY --from=builder /usr/local/bin/opencode /usr/local/bin/opencode
RUN if [ ! -s /usr/local/bin/opencode ]; then \
        curl -fsSL https://opencode.ai/install | bash \
        && mv /root/.opencode/bin/opencode /usr/local/bin/opencode || true; \
    fi

# 2. Claude Code (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

# 3. Gemini CLI (npm)
RUN npm install -g @google/gemini-cli

# 4. Codex CLI (npm)
RUN npm install -g @openai/codex

# 5. Aider (Python via uv)
RUN uv tool install --python python3 aider-chat

# 6. Kimi Code CLI (native installer)
RUN curl -L code.kimi.com/install.sh | bash || true

# 7. GitHub Copilot CLI (native installer) + GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y --no-install-recommends gh && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://gh.io/copilot-install | bash || true

# --- Make root-installed tools available to all users ---
# Tools installed as root (claude, aider, kimi) land in /root/.local/bin/
# which is inaccessible to non-root users. Copy them to /usr/local/bin/.
RUN for bin in /root/.local/bin/*; do \
        [ -f "$bin" ] && cp "$bin" /usr/local/bin/ || true; \
    done
ENV PATH="/home/${USERNAME}/.local/bin:/usr/local/bin:${PATH}"

# --- Create config directories (will be bind-mounted) ---
RUN mkdir -p "/home/${USERNAME}/.claude" \
    "/home/${USERNAME}/.config/opencode" \
    "/home/${USERNAME}/.local/share/opencode" \
    "/home/${USERNAME}/.aider" \
    "/home/${USERNAME}/.kimi" \
    "/home/${USERNAME}/.gemini" \
    "/home/${USERNAME}/.codex" \
    "/home/${USERNAME}/.config/github-copilot" \
    "/home/${USERNAME}/.config/gh" \
    && chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}"

# --- ZSH configuration ---
COPY --chown=${USERNAME}:${USERNAME} <<'ZSHRC' /home/${USERNAME}/.zshrc
# jailed container ZSH configuration
export HISTFILE=~/.zsh_history
export HISTSIZE=10000
export SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt AUTO_CD
setopt CORRECT

# Prompt
PROMPT='%F{cyan}[jailed]%f %F{green}%n%f:%F{blue}%~%f %# '

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias gs='git status'
alias gd='git diff'

# PATH for tools
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:/usr/local/go/bin:$PATH"

# Tab completion
autoload -Uz compinit && compinit
ZSHRC

# --- Entrypoint ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
