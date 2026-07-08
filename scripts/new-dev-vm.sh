#!/usr/bin/env bash
#
# new-dev-vm.sh — Scaffold a new isolated Developer VM (Odoo 18 + Postgres + SSH).
#
# Copies devs/_template into devs/<name>, assigns unique ports, generates a
# fresh SSH keypair for the developer, fills random secrets, and prints the
# connection details. Safe to re-run for different names; refuses to
# overwrite an existing devs/<name> folder.
#
# Usage:
#   ./scripts/new-dev-vm.sh <name> [ssh_port] [odoo_port] [postgres_port]
#
# Example:
#   ./scripts/new-dev-vm.sh dev3
#   ./scripts/new-dev-vm.sh sara 2203 18071 15434
#
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVS_DIR="$ROOT_DIR/devs"

NAME="${1:-}"
[[ -n "$NAME" ]] || die "Usage: $0 <name> [ssh_port] [odoo_port] [postgres_port]"
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || die "Name must be alphanumeric (dashes/underscores OK): $NAME"

TARGET_DIR="$DEVS_DIR/$NAME"
[[ ! -d "$TARGET_DIR" ]] || die "devs/$NAME already exists — pick another name or remove it first."

# --------------------------------------------------------------------------
# Auto-assign the next free ports (slot = number of existing devs/* dirs,
# excluding _template) unless the caller supplied explicit ports.
# --------------------------------------------------------------------------
SLOT=0
if [[ -d "$DEVS_DIR" ]]; then
  SLOT=$(find "$DEVS_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '_template' | wc -l)
fi

SSH_PORT="${2:-$((2201 + SLOT))}"
ODOO_PORT="${3:-$((18069 + SLOT))}"
POSTGRES_PORT="${4:-$((15432 + SLOT))}"

rand() { openssl rand -base64 "${1:-32}" | tr -d '\n/+=' | cut -c1-"${2:-30}"; }

log "Scaffolding devs/$NAME (SSH=$SSH_PORT, Odoo=$ODOO_PORT, Postgres=$POSTGRES_PORT)..."
mkdir -p "$TARGET_DIR/addons" "$TARGET_DIR/keys"
cp "$DEVS_DIR/_template/docker-compose.yml" "$TARGET_DIR/docker-compose.yml"
touch "$TARGET_DIR/addons/.gitkeep"

ODOO_ADMIN_PASSWD="$(rand 32 30)"
POSTGRES_PASSWORD="$(rand 32 30)"

# --------------------------------------------------------------------------
# SSH keypair for this developer (private key never printed to the terminal).
# The public key is written straight into DEV_SSH_PUBLIC_KEY in .env — the
# entrypoint installs it as authorized_keys on container start. Nothing
# key-related needs to be committed to git.
# --------------------------------------------------------------------------
KEY_PATH="$TARGET_DIR/keys/${NAME}_id_ed25519"
ssh-keygen -t ed25519 -N "" -C "$NAME" -f "$KEY_PATH" -q
chmod 600 "$KEY_PATH"; chmod 644 "${KEY_PATH}.pub"
PUBLIC_KEY="$(cat "${KEY_PATH}.pub")"

sed \
  -e "s/^PROJECT_NAME=.*/PROJECT_NAME=${NAME}/" \
  -e "s/^DOMAIN=.*/DOMAIN=${NAME}.example.com/" \
  -e "s/^SSH_PORT=.*/SSH_PORT=${SSH_PORT}/" \
  -e "s|^DEV_SSH_PUBLIC_KEY=.*|DEV_SSH_PUBLIC_KEY=${PUBLIC_KEY}|" \
  -e "s/^ODOO_PORT=.*/ODOO_PORT=${ODOO_PORT}/" \
  -e "s/^ODOO_ADMIN_PASSWD=.*/ODOO_ADMIN_PASSWD=${ODOO_ADMIN_PASSWD}/" \
  -e "s/^POSTGRES_USER=.*/POSTGRES_USER=${NAME}/" \
  -e "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=${POSTGRES_PASSWORD}/" \
  -e "s/^POSTGRES_DB=.*/POSTGRES_DB=${NAME}/" \
  -e "s/^POSTGRES_PORT=.*/POSTGRES_PORT=${POSTGRES_PORT}/" \
  "$DEVS_DIR/_template/.env.example" > "$TARGET_DIR/.env.example"

cp "$TARGET_DIR/.env.example" "$TARGET_DIR/.env"
chmod 600 "$TARGET_DIR/.env"

log "Done."
echo
echo "  Folder          : devs/$NAME/"
echo "  Domain           : ${NAME}.example.com  (edit devs/$NAME/.env, point DNS at this VPS)"
echo "  SSH (the VM)     : ssh -p ${SSH_PORT} -i devs/$NAME/keys/${NAME}_id_ed25519 developer@<VPS_IP>"
echo "  Odoo (tunnel)    : ssh -p ${SSH_PORT} -i devs/$NAME/keys/${NAME}_id_ed25519 -L 8069:127.0.0.1:${ODOO_PORT} developer@<VPS_IP>"
echo "  Private key      : devs/$NAME/keys/${NAME}_id_ed25519  (hand this to the developer securely, then delete it here)"
echo
echo "  Next steps:"
echo "    1. Edit devs/$NAME/.env  -> set the real DOMAIN."
echo "    2. cd devs/$NAME && docker compose up -d --build"
echo "    3. Point DNS A record for the domain at this VPS (for HTTPS via Traefik)."
