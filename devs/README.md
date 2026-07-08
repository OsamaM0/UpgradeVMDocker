# Developer VMs — isolated Odoo 18 instances

Each folder in `devs/` is a **fully independent** Odoo 18 + PostgreSQL 16 +
SSH stack — a personal "VM" for one developer. Nothing is shared between
instances except the base image definition (`docker/Dockerfile.dev-vm`) and
the odoo.conf template used by the main stack.

```
devs/
├── _template/          # source of truth — copy this to add a new developer
│   ├── docker-compose.yml
│   ├── .env.example
│   └── addons/
├── dev1/                # ready-to-use instance
└── dev2/                # ready-to-use instance
```

## What's isolated per developer
| Resource | Isolation |
|---|---|
| Odoo container | own container, own image build, own filestore volume |
| PostgreSQL | own container, own volume, own db name/user/password |
| Addons | own `devs/<name>/addons/` folder, mounted only into that instance |
| Network | own Docker bridge network (`internal`) |
| SSH | own port, own host keys, own `DEV_SSH_PUBLIC_KEY` |
| Domain | own subdomain (Traefik router), own HTTPS cert |

## Add a new developer
```bash
./scripts/new-dev-vm.sh dev3
cd devs/dev3
# edit .env -> set the real DOMAIN
docker compose up -d --build
```
The script auto-picks free ports, generates random Odoo/Postgres secrets,
and generates a dedicated SSH keypair for that developer.

## Start / stop / rebuild an instance
```bash
cd devs/dev1
docker compose up -d --build   # build the dev-vm image + start
docker compose ps
docker compose logs -f odoo
docker compose down            # stop (keeps volumes/data)
```

## Connect (PyCharm / VS Code) & database import
See [../docs/DEV_VMS.md](../docs/DEV_VMS.md) for full SSH, PyCharm remote
interpreter, and database-restore instructions.
