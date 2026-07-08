# Developer Access

Internal services (PostgreSQL and the raw Odoo port) are bound to `127.0.0.1`
on the VPS and are **not** exposed to the internet. Developers reach them
through an **SSH tunnel**, so nothing sensitive is published.

Replace `deploy@YOUR_VPS_IP` with your SSH user and VPS address below.

## 1. SSH tunnels

### PostgreSQL (5432)
```bash
ssh -N -L 5432:127.0.0.1:5432 deploy@YOUR_VPS_IP
```
Connect any client to `localhost:5432` with `POSTGRES_USER` /
`POSTGRES_PASSWORD` / `POSTGRES_DB` from `.env`.

### Odoo web — bypass the proxy (8069)
```bash
ssh -N -L 8069:127.0.0.1:8069 deploy@YOUR_VPS_IP
# then open http://localhost:8069
```

### Run tunnels in the background
```bash
ssh -fN -L 5432:127.0.0.1:5432 deploy@YOUR_VPS_IP   # detaches
pkill -f 'ssh -fN'                                   # stop all
```

## 2. PyCharm

### Database (Professional)
Database tool window → **+ → Data Source → PostgreSQL**
- Host `localhost`, Port `5432`, user/pass/db from `.env`.
- Or open the **SSH/SSL** tab and let PyCharm create the tunnel to the VPS
  (no manual `ssh` needed).

### Remote interpreter (runs inside the Odoo container)
Settings → **Python Interpreter → Add → Docker Compose**
- Server: *Docker via SSH* → `ssh://deploy@YOUR_VPS_IP`
- Configuration file: `docker-compose.yml` · Service: `odoo`
Run/debug then uses the container's Python and Odoo libraries.

## 3. VS Code

### Use the VPS as a dev VM (Remote-SSH)
1. Install **Remote - SSH**.
2. `Ctrl+Shift+P → Remote-SSH: Connect to Host` → `deploy@YOUR_VPS_IP`.
3. Open the project folder on the VPS and edit directly.

### Attach to a running container (Dev Containers)
1. Install **Dev Containers** + **Docker** extensions.
2. Docker view → right-click `odoo18-app` → **Attach Visual Studio Code**.
3. Edit and debug from inside the container.

## 4. Direct container access
```bash
# Odoo interactive shell (ORM available)
docker exec -it odoo18-app odoo shell -c /etc/odoo/odoo.conf -d odoo18

# Bash inside the Odoo container
docker exec -it odoo18-app bash

# psql inside the PostgreSQL container
docker exec -it odoo18-db psql -U odoo -d odoo18
```

## 5. Live debugging with debugpy
1. Temporarily publish the debug port — add to the `odoo` service in
   `docker-compose.yml` (dev only) and redeploy:
   ```yaml
       ports:
         - "127.0.0.1:5678:5678"
   ```
2. Start Odoo under debugpy:
   ```bash
   docker exec -it odoo18-app pip install debugpy
   docker exec -it odoo18-app python -m debugpy --listen 0.0.0.0:5678 \
     /usr/bin/odoo -c /etc/odoo/odoo.conf -d odoo18 --dev=all
   ```
3. Tunnel the port and attach:
   ```bash
   ssh -N -L 5678:127.0.0.1:5678 deploy@YOUR_VPS_IP
   ```
   VS Code: **Python: Remote Attach** → host `localhost`, port `5678`.
   PyCharm: **Python Debug Server** on `localhost:5678`.

> Remove the `5678` port mapping when you're done debugging.

## 6. Importing the live database
Fill the `REMOTE_*` values in `.env`, then on the VPS:
```bash
./scripts/restore-db.sh --drop                     # download + replace dev DB
./scripts/restore-db.sh --file backups/live.dump   # restore an existing local dump
docker compose restart odoo
```
Formats: `.sql`, `.sql.gz`, custom `pg_dump` (`.dump/.backup`), and Odoo `.zip`
(restores `dump.sql` + filestore). The script also disables outgoing mail so the
dev copy can't email real customers.
