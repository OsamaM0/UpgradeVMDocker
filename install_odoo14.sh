#!/bin/bash
# VARS
ODOO_USER="odoo14"
ODOO_HOME="/opt/odoo14-custom"
ODOO_PORT=8071
PG_VERSION=13
ODOO_PG_USER="odoo14"
ODOO_PG_PASS="odoo14pass"

echo "-------------------------"
echo "🧰 Updating system..."
echo "-------------------------"
sudo apt update && sudo apt upgrade -y

echo "-------------------------"
echo "🐘 Installing PostgreSQL $PG_VERSION..."
echo "-------------------------"
# Add PostgreSQL apt repo
sudo apt install -y wget gnupg2 curl ca-certificates
wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /usr/share/keyrings/postgresql.gpg
echo "deb [signed-by=/usr/share/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt noble-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
sudo apt update
sudo apt install -y postgresql-$PG_VERSION
sudo systemctl enable postgresql
sudo systemctl start postgresql

echo "Creating PostgreSQL user..."
sudo -u postgres psql -c "CREATE USER $ODOO_PG_USER WITH CREATEDB PASSWORD '$ODOO_PG_PASS';"

echo "-------------------------"
echo "🐍 Installing Python 3.7..."
echo "-------------------------"
cd /usr/src
sudo wget https://www.python.org/ftp/python/3.7.17/Python-3.7.17.tgz
sudo tar xzf Python-3.7.17.tgz
cd Python-3.7.17
# FIXED: Added --with-ensurepip flag
sudo ./configure --enable-optimizations --with-ensurepip=install
sudo make -j$(nproc)
sudo make altinstall

echo "-------------------------"
echo "📦 Installing dependencies..."
echo "-------------------------"
sudo apt install -y git build-essential libssl-dev libffi-dev \
libxml2-dev libxslt1-dev zlib1g-dev libjpeg-dev libpq-dev libsasl2-dev \
libldap2-dev libtiff5-dev libopenjp2-7-dev libwebp-dev libharfbuzz-dev \
libfribidi-dev libxcb1-dev libpng-dev libreadline-dev libbz2-dev \
libsqlite3-dev libncurses5-dev libnss3-dev

echo "-------------------------"
echo "👤 Creating Odoo user & folders..."
echo "-------------------------"
sudo useradd -m -d $ODOO_HOME -U -r -s /bin/bash $ODOO_USER
sudo mkdir -p $ODOO_HOME/custom_addons
sudo chown -R $ODOO_USER: $ODOO_HOME

echo "-------------------------"
echo "🐍 Creating Python 3.7 virtualenv..."
echo "-------------------------"
sudo -u $ODOO_USER /usr/local/bin/python3.7 -m venv $ODOO_HOME/venv
sudo -u $ODOO_USER bash -c "source $ODOO_HOME/venv/bin/activate && pip install --upgrade pip"

echo "-------------------------"
echo "📥 Cloning Odoo 14 source..."
echo "-------------------------"
sudo -u $ODOO_USER git clone https://www.github.com/odoo/odoo --depth 1 --branch 14.0 --single-branch $ODOO_HOME/src

echo "-------------------------"
echo "📦 Installing Python requirements..."
echo "-------------------------"
sudo -u $ODOO_USER bash -c "source $ODOO_HOME/venv/bin/activate && pip install wheel && pip install -r $ODOO_HOME/src/requirements.txt"

echo "-------------------------"
echo "⚙️  Creating config file..."
echo "-------------------------"
cat <<EOF | sudo tee /etc/odoo14.conf
[options]
admin_passwd = admin
db_host = False
db_port = False
db_user = $ODOO_PG_USER
db_password = $ODOO_PG_PASS
addons_path = $ODOO_HOME/src/addons,$ODOO_HOME/custom_addons
xmlrpc_port = $ODOO_PORT
logfile = /var/log/odoo14.log
EOF

sudo touch /var/log/odoo14.log
sudo chown $ODOO_USER: /var/log/odoo14.log

echo "-------------------------"
echo "🧱 Creating systemd service..."
echo "-------------------------"
cat <<EOF | sudo tee /etc/systemd/system/odoo14.service
[Unit]
Description=Odoo 14 Custom
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo14
PermissionsStartOnly=true
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_HOME/venv/bin/python3 $ODOO_HOME/src/odoo-bin -c /etc/odoo14.conf
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable odoo14
sudo systemctl start odoo14

echo "-------------------------"
echo "✅ Odoo 14 is installed!"
echo "🌐 Visit: http://<your-server-ip>:$ODOO_PORT"
echo "-------------------------"