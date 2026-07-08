#!/bin/sh
# Renders odoo.conf from odoo.conf.template using the container's own
# environment variables, then hands off to the image's real entrypoint.
#
# Rendered to $ODOO_RC (in /tmp, always writable) rather than back into the
# host-mounted /etc/odoo directory, since the container user may not own
# that bind mount. Both the entrypoint's wait-for-psql.py and the `odoo`
# binary itself read the ODOO_RC env var natively, so no -c flag is needed.
#
# This runs on every container start (Dokploy, plain docker compose, etc.) so
# the stack never depends on a host-side script having rendered the file
# beforehand.
set -e

export ODOO_RC=/tmp/odoo.conf

python3 -c "
import os
with open('/etc/odoo/odoo.conf.template') as f:
    tpl = f.read()
with open(os.environ['ODOO_RC'], 'w') as f:
    f.write(os.path.expandvars(tpl))
"

exec /entrypoint.sh "$@"
