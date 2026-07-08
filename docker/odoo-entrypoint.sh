#!/bin/sh
# Renders /etc/odoo/odoo.conf from odoo.conf.template using the container's
# own environment variables, then hands off to the image's real entrypoint.
#
# This runs on every container start (Dokploy, plain docker compose, etc.) so
# the stack never depends on a host-side script having rendered the file
# beforehand.
set -e

python3 -c "
import os
with open('/etc/odoo/odoo.conf.template') as f:
    tpl = f.read()
with open('/etc/odoo/odoo.conf', 'w') as f:
    f.write(os.path.expandvars(tpl))
"

exec /entrypoint.sh "$@"
