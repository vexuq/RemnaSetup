#!/bin/bash

# =========================
# Common includes
# =========================
source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"
source "/opt/remnasetup/scripts/common/languages.sh"

# =========================
# Load pinned versions (clone install)
# =========================
LOCK_FILE="/opt/remnasetup/data/versions.lock"
if [ -f "$LOCK_FILE" ]; then
    # shellcheck disable=SC1090
    source "$LOCK_FILE"
else
    warn "versions.lock not found — images will be taken from template"
fi

REINSTALL_PANEL=false
REINSTALL_CADDY=false

# =========================
# Checks
# =========================
check_panel() {
    if [ -f "/opt/remnawave/docker-compose.yml" ] || [ -f "/opt/remnawave/.env" ]; then
        info "$(get_string install_full_detected)"
        question "$(get_string install_full_reinstall)"
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            return
        fi
        cd /opt/remnawave && docker compose down || true
        docker volume rm remnawave-db-data remnawave-redis-data 2>/dev/null || true
        rm -f /opt/remnawave/docker-compose.yml /opt/remnawave/.env
        REINSTALL_PANEL=true
    else
        REINSTALL_PANEL=true
    fi
}

check_caddy() {
    if [ -d "/opt/remnawave/caddy" ]; then
        info "$(get_string install_full_caddy_detected)"
        question "$(get_string install_full_caddy_reinstall)"
        if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
            return
        fi
        cd /opt/remnawave/caddy && docker compose down 2>/dev/null || true
        rm -rf /opt/remnawave/caddy
        REINSTALL_CADDY=true
    else
        REINSTALL_CADDY=true
    fi
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        info "$(get_string install_full_installing_docker)"
        curl -fsSL https://get.docker.com | sh
    fi
}

# =========================
# Helpers
# =========================
generate_64() { openssl rand -hex 64; }
generate_24() { openssl rand -hex 24; }
generate_login() { tr -dc 'a-zA-Z' < /dev/urandom | head -c 15; }

apply_pinned_images() {
    if [ -n "${REMNAWAVE_BACKEND_IMAGE:-}" ] && \
       [ -n "${REMNAWAVE_POSTGRES_IMAGE:-}" ] && \
       [ -n "${REMNAWAVE_REDIS_IMAGE:-}" ]; then

        info "Applying pinned image digests from versions.lock"
        sed -i \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)remnawave/backend.*$|\1${REMNAWAVE_BACKEND_IMAGE}|g" \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)postgres.*$|\1${REMNAWAVE_POSTGRES_IMAGE}|g" \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)valkey/valkey.*$|\1${REMNAWAVE_REDIS_IMAGE}|g" \
          docker-compose.yml
    fi
}

# =========================
# Install panel
# =========================
install_panel() {
    mkdir -p /opt/remnawave
    cd /opt/remnawave || exit 1

    cp /opt/remnasetup/data/docker/panel.env .env
    cp /opt/remnasetup/data/docker/panel-compose.yml docker-compose.yml

    apply_pinned_images

    JWT_AUTH_SECRET=$(generate_64)
    JWT_API_TOKENS_SECRET=$(generate_64)
    METRICS_USER=$(generate_login)
    METRICS_PASS=$(generate_64)
    WEBHOOK_SECRET_HEADER=$(generate_64)
    DB_USER=$(generate_login)
    DB_PASSWORD=$(generate_24)

    sed -i "s|\$PANEL_DOMAIN|$PANEL_DOMAIN|g" .env
    sed -i "s|\$SUB_DOMAIN|$SUB_DOMAIN|g" .env
    sed -i "s|\$PANEL_PORT|$PANEL_PORT|g" .env
    sed -i "s|\$DB_USER|$DB_USER|g" .env
    sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" .env
    sed -i "s|\$JWT_AUTH_SECRET|$JWT_AUTH_SECRET|g" .env
    sed -i "s|\$JWT_API_TOKENS_SECRET|$JWT_API_TOKENS_SECRET|g" .env
    sed -i "s|\$METRICS_USER|$METRICS_USER|g" .env
    sed -i "s|\$METRICS_PASS|$METRICS_PASS|g" .env
    sed -i "s|\$WEBHOOK_SECRET_HEADER|$WEBHOOK_SECRET_HEADER|g" .env

    sed -i "s|\$PANEL_PORT|$PANEL_PORT|g" docker-compose.yml

    docker compose up -d
}

# =========================
# Install caddy
# =========================
install_caddy() {
    mkdir -p /opt/remnawave/caddy
    cd /opt/remnawave/caddy || exit 1

    cp /opt/remnasetup/data/caddy/caddyfile Caddyfile
    cp /opt/remnasetup/data/docker/caddy-compose.yml docker-compose.yml

    sed -i "s|\$PANEL_DOMAIN|$PANEL_DOMAIN|g" Caddyfile
    sed -i "s|\$PANEL_PORT|$PANEL_PORT|g" Caddyfile

    docker compose up -d
}

# =========================
# Main
# =========================
main() {
    check_panel
    check_caddy

    while true; do
        question "$(get_string install_full_enter_panel_domain)"
        PANEL_DOMAIN="$REPLY"
        [[ -n "$PANEL_DOMAIN" ]] && break
    done

    while true; do
        question "$(get_string install_full_enter_sub_domain)"
        SUB_DOMAIN="$REPLY"
        [[ -n "$SUB_DOMAIN" ]] && break
    done

    question "$(get_string install_full_enter_panel_port)"
    PANEL_PORT=${REPLY:-3000}

    install_docker

    [ "$REINSTALL_PANEL" = true ] && install_panel
    [ "$REINSTALL_CADDY" = true ] && install_caddy

    success "$(get_string install_full_complete)"
    read -n 1 -s -r -p "$(get_string install_full_press_key)"
}

main
