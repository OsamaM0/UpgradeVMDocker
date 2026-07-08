# Deploying with Dokploy

This stack is built to be deployed by **Dokploy** straight from your GitHub repo.
Dokploy installs and manages **Traefik**, which provides the reverse proxy,
HTTPS / Let's Encrypt certificates, and the shared `dokploy-network`.

## 1. Prerequisites
- Ubuntu 24.04 VPS with Dokploy installed:
  ```bash
  curl -sSL https://dokploy.com/install.sh | sh
  ```
- A domain (e.g. `odoo.example.com`) with a DNS **A record** → VPS IP.
- This repository pushed to GitHub.

## 2. Prepare the VPS (once)
Clone the repo and run the bootstrap so Docker, folders, and `.env` secrets exist.
Let Dokploy own the deployment by skipping the auto-start:
```bash
git clone https://github.com/<you>/<repo>.git odoo18 && cd odoo18
chmod +x scripts/*.sh
START_STACK=no sudo -E ./scripts/setup-vps.sh
```

## 3. Create the Dokploy service
1. Dashboard → **Create Project** → name `odoo18`.
2. **Create Service → Compose**.
3. **Provider: GitHub** → connect account → pick this repo + branch.
4. **Compose Path:** `docker-compose.yml`.

## 4. Environment variables
Service **Environment** tab → paste `.env.example` and set real values:

| Key | Example |
|-----|---------|
| `PROJECT_NAME` | `odoo18` |
| `DOMAIN` | `odoo.example.com` |
| `POSTGRES_USER` | `odoo` |
| `POSTGRES_PASSWORD` | *(strong random)* |
| `POSTGRES_DB` | `odoo18` |
| `ODOO_ADMIN_PASSWD` | *(strong random)* |

Secrets stay in Dokploy's env store — never in Git.

## 5. Domain & HTTPS
The compose file already ships Traefik labels for `${DOMAIN}` (HTTP→HTTPS
redirect, web on 8069, websocket on 8072, `letsencrypt` resolver).
Alternatively use Dokploy's **Domains** tab:
- Host: `odoo.example.com` · Container Port: `8069` · HTTPS: **on** · Cert: **Let's Encrypt**

> Websocket note: keep the `/websocket` router (port 8072) — Odoo 18 live chat,
> discuss, and bus notifications need it.

## 6. Deploy
Click **Deploy**. Dokploy pulls the repo, starts the stack, Traefik issues the
cert. Watch **Logs** until Odoo prints `HTTP service (werkzeug) running`.

## 7. First database
- Fresh: browse `https://odoo.example.com` → DB manager creates one
  (master password = `ODOO_ADMIN_PASSWD`).
- From live VPS: fill `REMOTE_*` in env, then run `./scripts/restore-db.sh --drop`
  on the VPS (see [DEVELOPER_ACCESS.md](DEVELOPER_ACCESS.md)).

## 8. Redeploys
Push to GitHub → **Redeploy** (or enable the auto-deploy webhook).
Named volumes `db-data` and `odoo-web-data` persist across redeploys.

## Troubleshooting
- **502 / no cert:** DNS A record not propagated, or port 80/443 blocked. Check `ufw`.
- **`network dokploy-network not found`:** ensure Dokploy is installed; or
  `docker network create dokploy-network`.
- **Assets/websocket errors:** confirm `proxy_mode = True` (set in `odoo.conf`)
  and the `-ws` router is present.
