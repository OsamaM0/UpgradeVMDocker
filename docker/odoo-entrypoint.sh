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

# Self-heal: ensure the target database exists even if the Postgres volume
# was previously initialized without it (stale volume, changed POSTGRES_DB,
# etc). Connects to the always-present 'postgres' system db to check/create.
python3 -c "
import os, sys, time
import psycopg2

host = os.environ.get('HOST', 'db')
port = os.environ.get('PORT', '5432')
user = os.environ['POSTGRES_USER']
password = os.environ['POSTGRES_PASSWORD']
dbname = os.environ.get('POSTGRES_DB', 'odoo18')

conn = None
last_err = None
for _ in range(30):
    try:
        conn = psycopg2.connect(host=host, port=port, user=user, password=password, dbname='postgres')
        break
    except psycopg2.OperationalError as e:
        last_err = e
        time.sleep(2)
if conn is None:
    sys.exit('odoo-entrypoint: could not reach Postgres to ensure database \"%s\" exists: %s' % (dbname, last_err))

conn.autocommit = True
cur = conn.cursor()
cur.execute('SELECT 1 FROM pg_database WHERE datname = %s', (dbname,))
if not cur.fetchone():
    cur.execute('CREATE DATABASE \"%s\" OWNER \"%s\"' % (dbname, user))
conn.close()
"

exec /entrypoint.sh "$@"
