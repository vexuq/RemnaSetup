#!/bin/bash

source "/opt/remnasetup/scripts/common/languages.sh"
source "/opt/remnasetup/scripts/common/colors.sh"
source "/opt/remnasetup/scripts/common/functions.sh"

# Load pinned digests (clone install)
LOCK_FILE="/opt/remnasetup/data/versions.lock"
if [ -f "$LOCK_FILE" ]; then
    # shellcheck disable=SC1090
    source "$LOCK_FILE"
else
    warn "versions.lock not found: $LOCK_FILE"
fi

REINSTALL_PANEL=false

check_component() {
    if [ -f "/opt/remnawave/docker-compose.yml" ] && (cd /opt/remnawave && docker compose ps -q | grep -q "remnawave\|remnawave-db\|remnawave-redis") || [ -f "/opt/remnawave/.env" ]; then
        info "$(get_string "install_panel_detected")"
        while true; do
            question "$(get_string "install_panel_reinstall")"
            REINSTALL="$REPLY"
            if [[ "$REINSTALL" == "y" || "$REINSTALL" == "Y" ]]; then
                warn "$(get_string "install_panel_stopping")"
                cd /opt/remnawave && docker compose down

                # Best-effort cleanup (safe if not present)
                docker rmi remnawave/backend:latest postgres:17 valkey/valkey:8.0.2-alpine 2>/dev/null || true
                docker volume rm remnawave-db-data remnawave-redis-data 2>/dev/null || true
                rm -f /opt/remnawave/.env
                rm -f /opt/remnawave/docker-compose.yml

                REINSTALL_PANEL=true
                break
            elif [[ "$REINSTALL" == "n" || "$REINSTALL" == "N" ]]; then
                info "$(get_string "install_panel_reinstall_denied")"
                read -n 1 -s -r -p "$(get_string "install_panel_press_key")"
                exit 1
            else
                warn "$(get_string "install_panel_please_enter_yn")"
            fi
        done
    else
        REINSTALL_PANEL=true
    fi
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        info "$(get_string "install_panel_installing_docker")"
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm -f get-docker.sh
    fi
}

generate_64() { openssl rand -hex 64; }
generate_24() { openssl rand -hex 24; }
generate_login() { tr -dc 'a-zA-Z' < /dev/urandom | head -c 15; }

apply_pinned_images() {
    # Replace template tags with pinned digests (if present)
    if [ -n "${REMNAWAVE_BACKEND_IMAGE:-}" ] && [ -n "${REMNAWAVE_POSTGRES_IMAGE:-}" ] && [ -n "${REMNAWAVE_REDIS_IMAGE:-}" ]; then
        info "Applying pinned image digests from versions.lock"
        sed -i \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)remnawave/backend.*$|\1${REMNAWAVE_BACKEND_IMAGE}|g" \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)postgres.*$|\1${REMNAWAVE_POSTGRES_IMAGE}|g" \
          -e "s|^\([[:space:]]*image:[[:space:]]*\)valkey/valkey.*$|\1${REMNAWAVE_REDIS_IMAGE}|g" \
          docker-compose.yml
    else
        warn "Pinned image variables not set — using template images."
    fi
}

install_panel() {
    if [ "$REINSTALL_PANEL" = true ]; then
        info "$(get_string "install_panel_installing")"
        mkdir -p /opt/remnawave
        cd /opt/remnawave || exit 1

        cp "/opt/remnasetup/data/docker/panel.env" .env
        cp "/opt/remnasetup/data/docker/panel-compose.yml" docker-compose.yml

        # Apply pinned digests
        apply_pinned_images

        JWT_AUTH_SECRET=$(generate_64)
        JWT_API_TOKENS_SECRET=$(generate_64)
        METRICS_USER=$(generate_login)
        METRICS_PASS=$(generate_64)
        WEBHOOK_SECRET_HEADER=$(generate_64)
        DB_USER=$(generate_login)
        DB_PASSWORD=$(generate_24)

        sed -i "s|\$PANEL_DOMAIN|$PANEL_DOMAIN|g" .env
        sed -i "s|\$PANEL_PORT|$PANEL_PORT|g" .env
        sed -i "s|\$DB_USER|$DB_USER|g" .env
        sed -i "s|\$DB_PASSWORD|$DB_PASSWORD|g" .env
        sed -i "s|\$JWT_AUTH_SECRET|$JWT_AUTH_SECRET|g" .env
        sed -i "s|\$JWT_API_TOKENS_SECRET|$JWT_API_TOKENS_SECRET|g" .env
        sed -i "s|\$SUB_DOMAIN|$SUB_DOMAIN|g" .env
        sed -i "s|\$METRICS_USER|$METRICS_USER|g" .env
        sed -i "s|\$METRICS_PASS|$METRICS_PASS|g" .env
        sed -i "s|\$WEBHOOK_SECRET_HEADER|$WEBHOOK_SECRET_HEADER|g" .env

        sed -i "s|\$PANEL_PORT|$PANEL_PORT|g" docker-compose.yml

        docker compose up -d
    fi
}

check_docker() {
    if command -v docker >/dev/null 2>&1; then
        info "$(get_string "install_panel_docker_installed")"
        return 0
    else
        return 1
    fi
}

main() {
    check_component

    while true; do
        question "$(get_string "install_panel_enter_panel_domain")"
        PANEL_DOMAIN="$REPLY"
        [[ -n "$PANEL_DOMAIN" ]] && break
        warn "$(get_string "install_panel_domain_empty")"
    done

    while true; do
        question "$(get_string "install_panel_enter_sub_domain")"
        SUB_DOMAIN="$REPLY"
        [[ -n "$SUB_DOMAIN" ]] && break
        warn "$(get_string "install_panel_domain_empty")"
    done

    question "$(get_string "install_panel_enter_panel_port")"
    PANEL_PORT="$REPLY"
    PANEL_PORT=${PANEL_PORT:-3000}

    if ! check_docker; then
        install_docker
    fi
    install_panel

    success "$(get_string "install_panel_complete")"
    read -n 1 -s -r -p "$(get_string "install_panel_press_key")"
    exit 0
}

main
