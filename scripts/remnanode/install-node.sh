#!/bin/bash

source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# ----------------------------
# Versions lock (clone mode)
# ----------------------------
LOCK_FILE="/opt/remnasetup/data/versions.lock"
if [ -f "$LOCK_FILE" ]; then
  # shellcheck disable=SC1090
  source "$LOCK_FILE"
fi

apply_remnanode_image_pin() {
  if [ -n "${REMNANODE_IMAGE:-}" ]; then
    # replace tag form
    sed -i -E "s|^([[:space:]]*image:[[:space:]]*)remnawave/node:.*$|\1${REMNANODE_IMAGE}|g" docker-compose.yml
    # replace digest form (if template ever changes)
    sed -i -E "s|^([[:space:]]*image:[[:space:]]*)remnawave/node@sha256:.*$|\1${REMNANODE_IMAGE}|g" docker-compose.yml
  fi
}

check_docker() {
  command -v docker >/dev/null 2>&1
}

install_docker() {
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh || {
    error "Docker installation failed"
    exit 1
  }
  success "Docker installed"
}

main() {
  # Ask settings
  while true; do
    question "Enter RemnaNode port (default 3001): "
    NODE_PORT="$REPLY"
    NODE_PORT=${NODE_PORT:-3001}
    [[ "$NODE_PORT" =~ ^[0-9]+$ ]] && break
    warn "Port must be a number"
  done

  while true; do
    question "Enter Secret Key (required): "
    SECRET_KEY="$REPLY"
    [[ -n "$SECRET_KEY" ]] && break
    warn "Secret Key cannot be empty"
  done

  if ! check_docker; then
    install_docker
  fi

  mkdir -p /opt/remnanode
  cd /opt/remnanode || exit 1

  # Use template
  cp "/opt/remnasetup/data/docker/node-compose.yml" docker-compose.yml

  # Substitute vars used by template
  sed -i "s|\$NODE_PORT|$NODE_PORT|g" docker-compose.yml
  sed -i "s|\$SECRET_KEY|$SECRET_KEY|g" docker-compose.yml

  # Apply pinned image
  apply_remnanode_image_pin

  docker compose up -d || {
    error "RemnaNode start failed"
    exit 1
  }

  success "RemnaNode installed"
  read -n 1 -s -r -p "Press any key..."
  echo
}

main
