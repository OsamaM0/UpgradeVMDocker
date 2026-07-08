# Security Recommendations

Secure-by-default choices baked into this project, plus hardening you should
apply on the VPS.

## Secrets
- All secrets live in `.env` (chmod 600) or Dokploy's env store — **never** in Git.
- `.gitignore` excludes `.env`, the rendered `config/odoo.conf`, and `backups/`.
- `scripts/setup-vps.sh` generates strong random `ODOO_ADMIN_PASSWD` and
  `POSTGRES_PASSWORD`.
- Rotate credentials before any live-like use; never reuse production passwords.

## Ports & exposure
| Port | Exposure | Purpose |
|------|----------|---------|
| 80 / 443 | Public (Traefik) | Odoo via domain + HTTPS |
| 8069 | `127.0.0.1` only | Dev bypass via SSH tunnel |
| 5432 | `127.0.0.1` only | PostgreSQL via SSH tunnel |
| 22 | Public (restrict) | SSH administration |

PostgreSQL and the raw Odoo port are bound to loopback — unreachable from the
internet. Use SSH tunnels (see [DEVELOPER_ACCESS.md](DEVELOPER_ACCESS.md)).

## Firewall (UFW)
```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw enable
```
`setup-vps.sh` applies this automatically (set `CONFIGURE_UFW=no` to skip).

## SSH hardening
- Prefer key-based auth; disable passwords in `/etc/ssh/sshd_config`:
  ```
  PasswordAuthentication no
  PermitRootLogin no
  ```
- Use a non-root `deploy` user with `sudo`.
- Optional: change the SSH port and install `fail2ban`.
- For DB transfers, use a key restricted to the backup path on the live VPS.

## Odoo hardening
- Set `LIST_DB=False` once the target DB exists → hides the DB manager.
- Keep `proxy_mode = True` (already set) so Odoo trusts Traefik headers.
- The master password (`admin_passwd`) gates DB create/drop/restore — keep it strong.
- `restore-db.sh` disables outgoing mail/fetchmail after import so the dev copy
  cannot email real customers.

## Data & updates
- Snapshot the `db-data` and `odoo-web-data` volumes regularly.
- Update images: `docker compose pull && docker compose up -d`.
- Patch the host: `apt update && apt upgrade`.
- Keep dumps in `backups/` off Git and delete them when no longer needed.

## What is NOT publicly exposed
- PostgreSQL (loopback only)
- The raw Odoo `8069` dev port (loopback only)
- debugpy `5678` (only when you temporarily add it, and via tunnel)
Only Traefik (80/443) faces the internet.
