#!/usr/bin/env bash
#
# restore-db.sh — Fetch a database dump from a remote/live VPS and restore it
# into the local PostgreSQL container of the Odoo 18 stack.
#
# Remote details come from .env (fill them in when available) and can be
# overridden with flags. Supported dump formats:
#   *.sql                plain SQL                (psql)
#   *.sql.gz / *.gz      gzipped SQL              (gunzip | psql)
#   *.dump/.backup       custom pg_dump -Fc       (pg_restore)
#   *.zip                Odoo backup: dump.sql (+ filestore) restored together
#
# Usage:
#   ./scripts/restore-db.sh                 # download from remote + restore
#   ./scripts/restore-db.sh --drop          # replace existing dev database
#   ./scripts/restore-db.sh --file PATH     # restore a local dump (no download)
#   ./scripts/restore-db.sh --db name       # override target database name
#
set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

[[ -f .env ]] || die ".env not found. Run scripts/setup-vps.sh first."
set -a; . ./.env; set +a

# --------------------------------------------------------------------------
# CLI parsing
# --------------------------------------------------------------------------
DROP_DB="no"
LOCAL_FILE=""

usage() { sed -n '2,30p' "$0"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --drop)      DROP_DB="yes"; shift;;
    --file)      LOCAL_FILE="${2:-}"; shift 2;;
    --db)        TARGET_DB="${2:-}"; shift 2;;
    -h|--help)   usage; exit 0;;
    *)           die "Unknown option: $1  (see --help)";;
  esac
done

TARGET_DB="${TARGET_DB:-${POSTGRES_DB:-odoo18}}"
DB_CONTAINER="${PROJECT_NAME:-odoo18}-db"
ODOO_CONTAINER="${PROJECT_NAME:-odoo18}-app"
mkdir -p "${LOCAL_DUMP_PATH:-./backups}"

# --------------------------------------------------------------------------
# 1. Obtain the dump
# --------------------------------------------------------------------------
if [[ -n "$LOCAL_FILE" ]]; then
  [[ -f "$LOCAL_FILE" ]] || die "Local file not found: $LOCAL_FILE"
  DUMP="$LOCAL_FILE"
  log "Using local dump: $DUMP"
else
  [[ -n "${REMOTE_HOST:-}" ]]      || die "REMOTE_HOST not set in .env"
  [[ -n "${REMOTE_SSH_USER:-}" ]]  || die "REMOTE_SSH_USER not set in .env"
  [[ -n "${REMOTE_DUMP_PATH:-}" ]] || die "REMOTE_DUMP_PATH not set in .env"

  DUMP="${LOCAL_DUMP_PATH:-./backups}/$(basename "$REMOTE_DUMP_PATH")"
  PORT="${REMOTE_SSH_PORT:-22}"

  log "Downloading ${REMOTE_SSH_USER}@${REMOTE_HOST}:${REMOTE_DUMP_PATH} ..."
  if [[ -n "${REMOTE_SSH_KEY:-}" ]]; then
    scp -P "$PORT" -i "$REMOTE_SSH_KEY" -o StrictHostKeyChecking=accept-new \
      "${REMOTE_SSH_USER}@${REMOTE_HOST}:${REMOTE_DUMP_PATH}" "$DUMP"
  elif [[ -n "${REMOTE_SSH_PASSWORD:-}" ]]; then
    command -v sshpass >/dev/null 2>&1 || die "sshpass required: apt-get install -y sshpass"
    sshpass -p "$REMOTE_SSH_PASSWORD" scp -P "$PORT" -o StrictHostKeyChecking=accept-new \
      "${REMOTE_SSH_USER}@${REMOTE_HOST}:${REMOTE_DUMP_PATH}" "$DUMP"
  else
    die "Provide REMOTE_SSH_KEY (preferred) or REMOTE_SSH_PASSWORD in .env"
  fi
  log "Saved to $DUMP"
fi

# --------------------------------------------------------------------------
# 2. Verify DB container
# --------------------------------------------------------------------------
docker inspect "$DB_CONTAINER" >/dev/null 2>&1 \
  || die "DB container '$DB_CONTAINER' is not running. Start the stack first."

psql_admin() { docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d postgres "$@"; }
psql_target(){ docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$TARGET_DB" "$@"; }

# --------------------------------------------------------------------------
# 3. Optionally drop + (re)create the target database
# --------------------------------------------------------------------------
if [[ "$DROP_DB" == "yes" ]]; then
  warn "Dropping database '$TARGET_DB' (terminating connections)..."
  psql_admin -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${TARGET_DB}' AND pid<>pg_backend_pid();" >/dev/null || true
  psql_admin -c "DROP DATABASE IF EXISTS \"${TARGET_DB}\";"
fi

if ! psql_admin -tAc "SELECT 1 FROM pg_database WHERE datname='${TARGET_DB}'" | grep -q 1; then
  log "Creating database '$TARGET_DB'..."
  psql_admin -c "CREATE DATABASE \"${TARGET_DB}\" OWNER \"${POSTGRES_USER}\";"
fi

# --------------------------------------------------------------------------
# 4. Restore based on file type
# --------------------------------------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

restore_sql()  { docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$DB_CONTAINER" psql -U "$POSTGRES_USER" -d "$TARGET_DB"; }
restore_dump() { docker exec -e PGPASSWORD="$POSTGRES_PASSWORD" -i "$DB_CONTAINER" pg_restore -U "$POSTGRES_USER" -d "$TARGET_DB" --no-owner --role="$POSTGRES_USER"; }

case "$DUMP" in
  *.sql)
    log "Restoring plain SQL dump..."
    restore_sql < "$DUMP"
    ;;
  *.sql.gz|*.gz)
    log "Restoring gzipped SQL dump..."
    gunzip -c "$DUMP" | restore_sql
    ;;
  *.dump|*.backup|*.custom)
    log "Restoring custom-format dump (pg_restore)..."
    restore_dump < "$DUMP"
    ;;
  *.zip)
    log "Extracting Odoo .zip backup..."
    command -v unzip >/dev/null 2>&1 || die "unzip required: apt-get install -y unzip"
    unzip -q -o "$DUMP" -d "$TMP"
    [[ -f "$TMP/dump.sql" ]] || die "dump.sql not found inside the zip"
    log "Restoring dump.sql..."
    restore_sql < "$TMP/dump.sql"
    if [[ -d "$TMP/filestore" ]]; then
      log "Restoring filestore into the Odoo volume..."
      docker exec "$ODOO_CONTAINER" mkdir -p "/var/lib/odoo/filestore/${TARGET_DB}"
      docker cp "$TMP/filestore/." "${ODOO_CONTAINER}:/var/lib/odoo/filestore/${TARGET_DB}/"
      docker exec -u root "$ODOO_CONTAINER" chown -R odoo:odoo "/var/lib/odoo/filestore/${TARGET_DB}" || true
    fi
    ;;
  *)
    die "Unsupported dump format: $DUMP"
    ;;
esac

# --------------------------------------------------------------------------
# 5. Neutralize production settings (dev-VM safety)
# --------------------------------------------------------------------------
log "Disabling outgoing mail & fetchmail servers (dev safety)..."
psql_target -c "UPDATE ir_mail_server SET active=false;" >/dev/null 2>&1 || true
psql_target -c "UPDATE fetchmail_server SET active=false;" >/dev/null 2>&1 || true

log "Restore complete → database '$TARGET_DB'."
log "Apply it:  docker compose restart odoo"
