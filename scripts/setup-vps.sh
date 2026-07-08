#!/usr/bin/env bash
#
# setup-vps.sh — Prepare an Ubuntu 24.04 VPS for the Odoo 18 Docker stack.
#
# Idempotent: safe to re-run. It installs Docker + Compose, prepares folders,
# generates strong secrets in .env, renders config/odoo.conf, ensures the
# Dokploy network exists, applies a basic firewall, and (optionally) starts
# the stack.
#
# Usage:
#   sudo ./scripts/setup-vps.sh
#
# Env toggles:
#   START_STACK=no     Prepare everything but let Dokploy start the stack.
#   CONFIGURE_UFW=no   Skip firewall configuration.
#
set -euo pipefail

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

[[ $EUID -eq 0 ]] || die "Run as root:  sudo ./scripts/setup-vps.sh"

# Strong secret: base64, stripped of shell/URL-unfriendly chars.
rand() { openssl rand -base64 "${1:-32}" | tr -d '\n/+=' | cut -c1-"${2:-30}"; }

set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    echo "${key}=${val}" >> .env
  fi
}

# --------------------------------------------------------------------------
# 1. System update + base packages
# --------------------------------------------------------------------------
log "Updating apt packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg openssl gettext-base rsync ufw unzip sshpass

# --------------------------------------------------------------------------
# 2. Docker Engine + Compose plugin
# --------------------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine..."
  curl -fsSL https://get.docker.com | sh
else
  log "Docker already installed: $(docker --version)"
fi

if ! docker compose version >/dev/null 2>&1; then
  log "Installing Docker Compose plugin..."
  apt-get install -y docker-compose-plugin
else
  log "Docker Compose available: $(docker compose version | head -n1)"
fi

systemctl enable --now docker

# --------------------------------------------------------------------------
# 3. Project folders + permissions
# --------------------------------------------------------------------------
log "Preparing project folders..."
mkdir -p addons backups config
touch addons/.gitkeep backups/.gitkeep
chmod -R 0775 addons backups

# --------------------------------------------------------------------------
# 4. .env with secure secrets
# --------------------------------------------------------------------------
if [[ ! -f .env ]]; then
  log "Creating .env from .env.example with random secrets..."
  cp .env.example .env
  set_env ODOO_ADMIN_PASSWD "$(rand 32 30)"
  set_env POSTGRES_PASSWORD "$(rand 32 30)"
  chmod 600 .env
else
  warn ".env already exists — leaving existing secrets untouched."
fi

# --------------------------------------------------------------------------
# 5. Render odoo.conf from template (keeps the master password out of git)
# --------------------------------------------------------------------------
log "Rendering config/odoo.conf..."
set -a; . ./.env; set +a
envsubst < config/odoo.conf.template > config/odoo.conf
chmod 640 config/odoo.conf

# --------------------------------------------------------------------------
# 6. Ensure the external Dokploy network exists
# --------------------------------------------------------------------------
if ! docker network inspect dokploy-network >/dev/null 2>&1; then
  warn "dokploy-network not found — creating it."
  docker network create dokploy-network
fi

# --------------------------------------------------------------------------
# 7. Firewall (recommended)
# --------------------------------------------------------------------------
if [[ "${CONFIGURE_UFW:-yes}" == "yes" ]]; then
  log "Configuring UFW (allow 22, 80, 443)..."
  ufw allow OpenSSH || true
  ufw allow 80/tcp  || true
  ufw allow 443/tcp || true
  yes | ufw enable  || true
fi

# --------------------------------------------------------------------------
# 8. Start the stack (skip when Dokploy owns the deployment)
# --------------------------------------------------------------------------
if [[ "${START_STACK:-yes}" == "yes" ]]; then
  log "Starting the Docker Compose stack..."
  docker compose up -d
else
  warn "START_STACK=no — deploy via Dokploy instead."
fi

# --------------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------------
log "Setup complete."
echo
echo "  Domain        : $(grep '^DOMAIN=' .env | cut -d= -f2)"
echo "  Odoo (local)  : http://127.0.0.1:$(grep '^ODOO_PORT=' .env | cut -d= -f2)  (SSH tunnel only)"
echo "  Postgres      : 127.0.0.1:$(grep '^POSTGRES_PORT=' .env | cut -d= -f2)     (SSH tunnel only)"
echo
echo "  Secrets are stored in .env (chmod 600). Keep it off Git."
echo "  Next steps:"
echo "    - Point DNS A-record for the domain at this VPS, deploy via Dokploy (docs/DOKPLOY.md)."
echo "    - Import a database once remote details are set: ./scripts/restore-db.sh --drop"
