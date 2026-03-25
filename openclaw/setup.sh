#!/usr/bin/env bash
# OpenClaw Ubuntu Setup Script
# Installs OpenClaw on the host OS with agents running in isolated Docker containers.
# Tested on Ubuntu 22.04 / 24.04.

set -euo pipefail

OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
WORKSPACE_DIR="$HOME/openclaw/workspace"

###############################################################################
# Helpers
###############################################################################

log()  { echo "[openclaw-setup] $*"; }
die()  { echo "[openclaw-setup] ERROR: $*" >&2; exit 1; }

require_root_or_sudo() {
  if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
    die "This script needs sudo privileges. Run with a user that has sudo access."
  fi
}

###############################################################################
# 1. System dependencies
###############################################################################

install_system_deps() {
  log "Updating apt and installing system dependencies..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    curl \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    build-essential
}

###############################################################################
# 2. Docker (CE)
###############################################################################

install_docker() {
  if command -v docker &>/dev/null; then
    log "Docker already installed: $(docker --version)"
    return
  fi

  log "Installing Docker CE..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

  # Allow current user to use Docker without sudo
  sudo usermod -aG docker "$USER"
  log "Docker installed. NOTE: log out and back in (or run 'newgrp docker') for group changes to take effect."
}

###############################################################################
# 3. Node.js 24 via nvm
###############################################################################

install_node() {
  if command -v node &>/dev/null && node -e "process.exit(parseInt(process.version.slice(1)) >= 22 ? 0 : 1)" 2>/dev/null; then
    log "Node.js already installed: $(node --version)"
    return
  fi

  log "Installing nvm and Node.js 24..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash

  # Source nvm in current shell
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  nvm install 24
  nvm use 24
  nvm alias default 24

  log "Node.js installed: $(node --version)"
}

###############################################################################
# 4. OpenClaw (global npm install)
###############################################################################

install_openclaw() {
  # Ensure nvm is loaded if running in a non-interactive shell
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  log "Installing OpenClaw..."
  npm install -g openclaw@latest

  log "OpenClaw installed: $(openclaw --version 2>/dev/null || echo 'version unknown')"
}

###############################################################################
# 5. Create workspace and config directories
###############################################################################

create_dirs() {
  log "Creating workspace and config directories..."
  mkdir -p "$OPENCLAW_CONFIG_DIR"
  mkdir -p "$WORKSPACE_DIR"
  chmod 700 "$OPENCLAW_CONFIG_DIR"
}

###############################################################################
# 6. Build the sandbox Docker image
###############################################################################

build_sandbox_image() {
  local image_name="openclaw-sandbox:latest"

  if docker image inspect "$image_name" &>/dev/null; then
    log "Sandbox image '$image_name' already exists. Skipping build."
    return
  fi

  log "Building OpenClaw sandbox Docker image..."

  # Clone OpenClaw source temporarily to get the sandbox Dockerfile
  local tmp_dir
  tmp_dir=$(mktemp -d)
  git clone --depth 1 https://github.com/openclaw/openclaw.git "$tmp_dir/openclaw-src" 2>/dev/null \
    || { log "Could not clone source; sandbox image will be built on first agent launch."; return; }

  if [[ -f "$tmp_dir/openclaw-src/Dockerfile.sandbox" ]]; then
    docker build \
      -t "$image_name" \
      -f "$tmp_dir/openclaw-src/Dockerfile.sandbox" \
      "$tmp_dir/openclaw-src"
    log "Sandbox image built: $image_name"
  else
    log "Dockerfile.sandbox not found in repo; will use default image on first run."
  fi

  rm -rf "$tmp_dir"
}

###############################################################################
# 7. Write openclaw config with sandbox enabled
###############################################################################

write_config() {
  local config_file="$OPENCLAW_CONFIG_DIR/config.yaml"

  if [[ -f "$config_file" ]]; then
    log "Config file already exists at $config_file — skipping (edit manually if needed)."
    return
  fi

  log "Writing default config to $config_file ..."
  cp "$(dirname "$0")/config.yaml" "$config_file"
  chmod 600 "$config_file"
  log "Config written. Edit $config_file to set your API key, model, and channel tokens."
}

###############################################################################
# 8. Install OpenClaw as a systemd user service (daemon)
###############################################################################

install_daemon() {
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1091
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

  log "Installing OpenClaw gateway daemon (systemd user service)..."
  openclaw onboard --install-daemon --non-interactive 2>/dev/null || true

  # Enable lingering so the user service starts at boot without login
  sudo loginctl enable-linger "$USER"

  log "Daemon installed. Start with: systemctl --user start openclaw-gateway"
}

###############################################################################
# Main
###############################################################################

main() {
  require_root_or_sudo

  log "=== OpenClaw Ubuntu + Container-per-Agent Setup ==="

  install_system_deps
  install_docker
  install_node
  install_openclaw
  create_dirs
  build_sandbox_image
  write_config
  install_daemon

  echo ""
  echo "============================================================"
  echo "  OpenClaw setup complete!"
  echo "============================================================"
  echo ""
  echo "  Next steps:"
  echo "  1. Edit ~/.openclaw/config.yaml with your API key, model,"
  echo "     messaging channel tokens, and review sandbox settings."
  echo "  2. Log out and back in (or run 'newgrp docker') so your"
  echo "     user can run Docker without sudo."
  echo "  3. Start the gateway:"
  echo "       systemctl --user start openclaw-gateway"
  echo "  4. Watch logs:"
  echo "       journalctl --user -u openclaw-gateway -f"
  echo "  5. Open the web UI at http://localhost:18789"
  echo ""
  echo "  Each agent session will automatically launch its own"
  echo "  isolated Docker container (sandbox mode is enabled)."
  echo "============================================================"
}

main "$@"
