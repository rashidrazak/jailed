#!/bin/bash
set -e

USERNAME="${JAILED_USER:-coder}"

# --- UID/GID remapping ---
TARGET_UID="${HOST_UID:-1000}"
TARGET_GID="${HOST_GID:-1000}"
CURRENT_UID=$(id -u "$USERNAME")
CURRENT_GID=$(id -g "$USERNAME")

if [ "$TARGET_GID" != "$CURRENT_GID" ]; then
    groupmod -g "$TARGET_GID" "$USERNAME" 2>/dev/null || true
fi

if [ "$TARGET_UID" != "$CURRENT_UID" ]; then
    usermod -u "$TARGET_UID" "$USERNAME" 2>/dev/null || true
fi

chown -R "$USERNAME:$USERNAME" "/home/$USERNAME" 2>/dev/null || true

# --- Docker/Podman socket permissions ---
if [ -S /var/run/docker.sock ]; then
    DOCKER_SOCK_GID=$(stat -c '%g' /var/run/docker.sock)
    if ! getent group "$DOCKER_SOCK_GID" >/dev/null 2>&1; then
        groupadd -g "$DOCKER_SOCK_GID" -o docker_host 2>/dev/null || true
    fi
    usermod -aG "$DOCKER_SOCK_GID" "$USERNAME" 2>/dev/null || true
fi

# --- Drop privileges and exec shell ---
export HOME="/home/$USERNAME"
export USER="$USERNAME"

exec gosu "$USERNAME" zsh -l
