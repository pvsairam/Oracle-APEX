#!/usr/bin/env bash
set -euo pipefail

# Full Oracle APEX installer for Ubuntu 22.04
# Installs: Docker, Oracle Database Free container, Oracle APEX, ORDS, Java 17, Nginx
# Default access: http://SERVER_IP/ords/

APP_DIR="/opt/oracle-apex-stack"
ORDS_DIR="/opt/ords"
ORDS_CONFIG="/etc/ords/config"
APEX_ZIP_URL="https://download.oracle.com/otn_software/apex/apex_26.1_en.zip"
ORDS_ZIP_URL="https://download.oracle.com/otn_software/java/ords/ords-latest.zip"
DB_IMAGE="gvenzl/oracle-free:latest"
DB_CONTAINER="oracle-free-apex"
PDB_NAME="FREEPDB1"
DB_PORT="1521"
ORDS_PORT="8181"
APEX_ADMIN_USER="ADMIN"
APEX_ADMIN_EMAIL="admin@example.com"

log(){ echo -e "\n[APEX-INSTALL] $*"; }
fail(){ echo -e "\n[FAILED] $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  fail "Please run this script with sudo: sudo bash install_full_apex_ubuntu22.sh"
fi

if ! grep -q "22.04" /etc/os-release; then
  echo "[WARNING] This script was prepared for Ubuntu 22.04. Continuing anyway."
fi

SERVER_IP=$(curl -fsS https://api.ipify.org || hostname -I | awk '{print $1}')
DB_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)"Aa1#"
APEX_ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)"Aa1#"
APEX_PUBLIC_PASSWORD=$(openssl rand -base64 18 | tr -dc 'A-Za-z0-9' | head -c 16)"Aa1#"

log "Installing required Linux packages"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget unzip openssl gnupg lsb-release \
  openjdk-17-jdk nginx ufw apt-transport-https software-properties-common

log "Installing Docker if missing"
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

log "Preparing folders"
mkdir -p "$APP_DIR" "$ORDS_DIR" "$ORDS_CONFIG" /var/log/ords /var/lib/ords
cd "$APP_DIR"

log "Starting Oracle Database Free container"
if docker ps -a --format '{{.Names}}' | grep -qx "$DB_CONTAINER"; then
  docker rm -f "$DB_CONTAINER" >/dev/null
fi

docker run -d \
  --name "$DB_CONTAINER" \
  -p "$DB_PORT:1521" \
  -e ORACLE_PASSWORD="$DB_PASSWORD" \
  -e APP_USER=APEXDEMO \
  -e APP_USER_PASSWORD="$DB_PASSWORD" \
  -v oracle-free-apex-data:/opt/oracle/oradata \
  --restart unless-stopped \
  "$DB_IMAGE"

log "Waiting for database to become healthy. This can take several minutes on first start."
for i in {1..90}; do
  STATUS=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "$DB_CONTAINER" 2>/dev/null || true)
  if [[ "$STATUS" == "healthy" ]]; then
    break
  fi
  sleep 20
  echo "Database status: $STATUS"
done
STATUS=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}starting{{end}}' "$DB_CONTAINER")
[[ "$STATUS" == "healthy" ]] || fail "Database did not become healthy. Check: docker logs $DB_CONTAINER"

log "Downloading Oracle APEX 26.1"
rm -rf "$APP_DIR/apex" "$APP_DIR/apex.zip"
wget -q --show-progress -O "$APP_DIR/apex.zip" "$APEX_ZIP_URL"
unzip -q "$APP_DIR/apex.zip" -d "$APP_DIR"

docker cp "$APP_DIR/apex" "$DB_CONTAINER:/tmp/apex"

log "Installing APEX into pluggable database $PDB_NAME"
docker exec -i "$DB_CONTAINER" bash -lc "cd /tmp/apex && sqlplus -s / as sysdba" <<SQL
whenever sqlerror exit sql.sqlcode
alter session set container=$PDB_NAME;
@apexins.sql SYSAUX SYSAUX TEMP /i/
exit
SQL

log "Configuring APEX REST users and ADMIN user"
docker exec -i "$DB_CONTAINER" bash -lc "cd /tmp/apex && sqlplus -s / as sysdba" <<SQL
whenever sqlerror exit sql.sqlcode
alter session set container=$PDB_NAME;
alter user APEX_PUBLIC_USER identified by "$APEX_PUBLIC_PASSWORD" account unlock;
alter user APEX_REST_PUBLIC_USER identified by "$APEX_PUBLIC_PASSWORD" account unlock;
alter user APEX_LISTENER identified by "$APEX_PUBLIC_PASSWORD" account unlock;
begin
  apex_util.set_security_group_id(10);
  begin
    apex_util.create_user(
      p_user_name => '$APEX_ADMIN_USER',
      p_email_address => '$APEX_ADMIN_EMAIL',
      p_web_password => '$APEX_ADMIN_PASSWORD',
      p_developer_privs => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL'
    );
  exception
    when others then
      apex_util.edit_user(
        p_user_name => '$APEX_ADMIN_USER',
        p_email_address => '$APEX_ADMIN_EMAIL',
        p_web_password => '$APEX_ADMIN_PASSWORD',
        p_developer_privs => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
        p_account_locked => 'N',
        p_failed_access_attempts => 0
      );
  end;
  commit;
end;
/
exit
SQL

log "Downloading and installing ORDS"
rm -rf "$ORDS_DIR"/* "$APP_DIR/ords.zip"
wget -q --show-progress -O "$APP_DIR/ords.zip" "$ORDS_ZIP_URL"
unzip -q "$APP_DIR/ords.zip" -d "$ORDS_DIR"
chmod +x "$ORDS_DIR/bin/ords" || true
ln -sf "$ORDS_DIR/bin/ords" /usr/local/bin/ords
cp -r "$APP_DIR/apex/images" "$ORDS_DIR/images"

log "Configuring ORDS non-interactively"
cat > /tmp/ords_passwords.txt <<PASS
$DB_PASSWORD
$APEX_PUBLIC_PASSWORD
PASS
ords --config "$ORDS_CONFIG" install \
  --log-folder /var/log/ords \
  --admin-user SYS \
  --db-hostname localhost \
  --db-port "$DB_PORT" \
  --db-servicename "$PDB_NAME" \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --feature-sdw true \
  --gateway-mode proxied \
  --gateway-user APEX_PUBLIC_USER \
  --password-stdin < /tmp/ords_passwords.txt
rm -f /tmp/ords_passwords.txt

ords --config "$ORDS_CONFIG" config set standalone.http.port "$ORDS_PORT"
ords --config "$ORDS_CONFIG" config set standalone.static.path "$ORDS_DIR/images"
ords --config "$ORDS_CONFIG" config set security.externalSessionTrustedOrigins "http://$SERVER_IP,https://$SERVER_IP"

log "Creating ORDS systemd service"
cat > /etc/systemd/system/ords.service <<SERVICE
[Unit]
Description=Oracle REST Data Services
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=$ORDS_DIR
ExecStart=/usr/local/bin/ords --config $ORDS_CONFIG serve
Restart=always
RestartSec=10
StandardOutput=append:/var/log/ords/ords.log
StandardError=append:/var/log/ords/ords-error.log

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable --now ords
sleep 20

log "Configuring Nginx reverse proxy"
cat > /etc/nginx/sites-available/apex <<NGINX
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 200M;

    location /ords/ {
        proxy_pass http://127.0.0.1:$ORDS_PORT/ords/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /i/ {
        alias $ORDS_DIR/images/;
    }

    location / {
        return 302 /ords/;
    }
}
NGINX
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/apex /etc/nginx/sites-enabled/apex
nginx -t
systemctl enable --now nginx
systemctl restart nginx

log "Configuring firewall"
ufw allow OpenSSH >/dev/null || true
ufw allow 80/tcp >/dev/null || true
ufw allow 443/tcp >/dev/null || true
ufw allow "$ORDS_PORT/tcp" >/dev/null || true
ufw --force enable >/dev/null || true

SUMMARY_FILE="$APP_DIR/install-summary.txt"
cat > "$SUMMARY_FILE" <<SUMMARY
Oracle APEX full stack installation completed successfully.

Access URLs:
  APEX via Nginx:      http://$SERVER_IP/ords/
  APEX direct ORDS:    http://$SERVER_IP:$ORDS_PORT/ords/

APEX INTERNAL workspace login:
  Workspace:           INTERNAL
  Username:            $APEX_ADMIN_USER
  Password:            $APEX_ADMIN_PASSWORD

Database details:
  Host:                $SERVER_IP
  Port:                $DB_PORT
  Service Name:        $PDB_NAME
  SYS/SYSTEM Password: $DB_PASSWORD
  Demo Schema:         APEXDEMO
  Demo Schema Password:$DB_PASSWORD

Installed components:
  Oracle Database:     Docker image $DB_IMAGE
  Oracle APEX:         26.1 from $APEX_ZIP_URL
  ORDS:                Latest from $ORDS_ZIP_URL
  Java:                OpenJDK 17
  Reverse Proxy:       Nginx

Useful commands:
  Check database:      docker ps
  Database logs:       docker logs -f $DB_CONTAINER
  Check ORDS:          systemctl status ords
  ORDS logs:           tail -f /var/log/ords/ords.log
  Restart ORDS:        systemctl restart ords
  Restart Nginx:       systemctl restart nginx

Important:
  Keep this file safe. It contains passwords.
  File path: $SUMMARY_FILE
SUMMARY
chmod 600 "$SUMMARY_FILE"

cat "$SUMMARY_FILE"
