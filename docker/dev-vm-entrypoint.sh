#!/bin/bash
# Entrypoint for a Developer VM container (Odoo 18 + sshd).
#
# 1. Ensures SSH host keys exist (persisted on the sshd-keys volume so they
#    survive rebuilds/restarts and stay unique per developer instance).
# 2. Installs the developer's public key(s) as authorized_keys.
# 3. Starts sshd in the background.
# 4. Hands off to the existing odoo-entrypoint.sh (renders odoo.conf, ensures
#    the database exists, then execs the base image's real entrypoint) which
#    becomes PID 1's foreground process.
set -e

DEV_USER="${DEV_USER:-developer}"
HOME_DIR="/home/${DEV_USER}"
AUTH_KEYS_FILE="${HOME_DIR}/.ssh/authorized_keys"

# --- 1. SSH host keys (idempotent; only generates missing types) ---
ssh-keygen -A

# --- 2. Authorized keys come from the DEV_SSH_PUBLIC_KEY env var (one or more
#         keys, one per line) — set it in devs/<name>/.env or the Dokploy
#         Environment tab. Nothing key-related needs to be committed to git. ---
if [ -n "${DEV_SSH_PUBLIC_KEY:-}" ]; then
    printf '%s\n' "${DEV_SSH_PUBLIC_KEY}" > "$AUTH_KEYS_FILE"
fi

if [ -s "$AUTH_KEYS_FILE" ]; then
    chmod 600 "$AUTH_KEYS_FILE"
    chown "${DEV_USER}:${DEV_USER}" "$AUTH_KEYS_FILE"
    echo "dev-vm-entrypoint: authorized_keys installed for ${DEV_USER}."
else
    echo "dev-vm-entrypoint: WARNING - no SSH public key provided; set DEV_SSH_PUBLIC_KEY to enable SSH login." >&2
fi

# --- 3. Start sshd in the background (PID 1 stays Odoo, started below) ---
/usr/sbin/sshd

# --- 4. Render odoo.conf, ensure DB exists, exec the real Odoo entrypoint ---
exec /bin/sh /opt/odoo-entrypoint.sh "$@"
