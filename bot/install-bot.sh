#!/usr/bin/env bash
set -euo pipefail

apt_update_upgrade_direct() {
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  RUN_APT_UPGRADE="${RUN_APT_UPGRADE:-true}"
  if command -v apt-get >/dev/null 2>&1; then
    echo "Menjalankan apt update..."
    apt-get update -y || apt-get update -y --allow-releaseinfo-change || true
    if [ "$RUN_APT_UPGRADE" = "true" ] || [ "$RUN_APT_UPGRADE" = "1" ] || [ "$RUN_APT_UPGRADE" = "yes" ]; then
      echo "Menjalankan apt upgrade -y..."
      apt-get upgrade -y \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" || true
    else
      echo "apt upgrade dilewati karena RUN_APT_UPGRADE=$RUN_APT_UPGRADE"
    fi
  fi
}

APP_DIR="/root/zivpn-monitor-bot"
SERVICE_NAME="zivpn-monitor-bot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root."
  exit 1
fi

cd "$SCRIPT_DIR"

echo "==============================================="
echo " Install ZiVPN Multi Server Monitor Bot - Safe"
echo "==============================================="

# Dependensi dipasang juga di sini agar aman jika file ini dijalankan langsung.
apt_update_upgrade_direct
if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y curl ca-certificates git nano nodejs npm procps lsof iproute2 || true
fi

if ! command -v node >/dev/null 2>&1 || ! node -e "process.exit(parseInt(process.versions.node.split('.')[0]) >= 18 ? 0 : 1)" 2>/dev/null; then
  echo "Node.js versi lama/tidak ada. Mencoba install NodeSource 20.x..."
  if command -v curl >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || true
    apt-get install -y nodejs || true
  fi
fi

if ! command -v node >/dev/null 2>&1 || ! node -e "process.exit(parseInt(process.versions.node.split('.')[0]) >= 18 ? 0 : 1)" 2>/dev/null; then
  echo "ERROR: Node.js minimal versi 18 dibutuhkan. Versi saat ini: $(node -v 2>/dev/null || echo tidak ada)"
  exit 1
fi

npm install -g pm2 >/dev/null 2>&1 || npm install -g pm2

mkdir -p "$APP_DIR"

# Copy file wajib.
[ -f app.js ] || { echo "ERROR: app.js tidak ditemukan di folder bot."; exit 1; }
[ -f package.json ] || cat > package.json <<'EOP'
{"name":"zivpn-monitor-bot","version":"2.0.0","main":"app.js","scripts":{"start":"node app.js"}}
EOP

cp app.js package.json "$APP_DIR"/

if [ -f panel.sh ]; then
  cp panel.sh "$APP_DIR/panel.sh"
else
  cat > "$APP_DIR/panel.sh" <<'EOP'
#!/usr/bin/env bash
APP_DIR="/root/zivpn-monitor-bot"
ENV_FILE="$APP_DIR/.env"
SERVERS_FILE="$APP_DIR/servers.json"
SERVICE_NAME="zivpn-monitor-bot"
while true; do
  clear || true
  echo "================================================="
  echo "        ZiVPN Multi Server Monitor Panel"
  echo "================================================="
  echo "1) Status PM2 Bot"
  echo "2) Start Bot"
  echo "3) Stop Bot"
  echo "4) Restart Bot"
  echo "5) Edit servers.json manual"
  echo "6) Edit .env manual"
  echo "7) Log Bot"
  echo "0) Keluar"
  echo "================================================="
  read -rp "Pilih menu: " p
  case "$p" in
    1) pm2 status "$SERVICE_NAME"; read -rp "Enter..." _ ;;
    2) cd "$APP_DIR" && pm2 start "$APP_DIR/app.js" --name "$SERVICE_NAME" --time || pm2 restart "$SERVICE_NAME"; pm2 save; read -rp "Enter..." _ ;;
    3) pm2 stop "$SERVICE_NAME" || true; read -rp "Enter..." _ ;;
    4) pm2 restart "$SERVICE_NAME" || true; pm2 save; read -rp "Enter..." _ ;;
    5) nano "$SERVERS_FILE" ;;
    6) nano "$ENV_FILE" ;;
    7) pm2 logs "$SERVICE_NAME" ;;
    0) clear || true; exit 0 ;;
  esac
done
EOP
fi
chmod +x "$APP_DIR/panel.sh"

# Jangan gagal walaupun .env.example tidak ada di repo.
if [ -f .env.example ]; then
  cp .env.example "$APP_DIR/.env.example"
else
  cat > "$APP_DIR/.env.example" <<'EOP'
BOT_TOKEN=ISI_TOKEN_BOT_TELEGRAM
CHAT_ID=ISI_CHAT_ID_GRUP
CHECK_INTERVAL=30000
CPU_THRESHOLD=90
RAM_THRESHOLD=90
DISK_THRESHOLD=90
ALERT_ON_FIRST_CHECK=true
EOP
fi

if [ -f servers.example.json ]; then
  cp servers.example.json "$APP_DIR/servers.example.json"
else
  cat > "$APP_DIR/servers.example.json" <<'EOP'
[
  {
    "name": "ID BIZNET 1",
    "host": "1.2.3.4",
    "agentPort": 5890,
    "token": "TOKEN_AGENT_SERVER_1"
  }
]
EOP
fi

if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
fi

if [ ! -f "$APP_DIR/servers.json" ]; then
  echo '[]' > "$APP_DIR/servers.json"
fi

cat > /usr/local/bin/zivpn-monitor-panel <<'EOC'
#!/usr/bin/env bash
bash /root/zivpn-monitor-bot/panel.sh
EOC
chmod +x /usr/local/bin/zivpn-monitor-panel

cat > /usr/local/bin/zivpn-monitor-start <<'EOC'
#!/usr/bin/env bash
cd /root/zivpn-monitor-bot
pm2 start /root/zivpn-monitor-bot/app.js --name zivpn-monitor-bot --time || pm2 restart zivpn-monitor-bot
pm2 save >/dev/null 2>&1 || true
EOC
chmod +x /usr/local/bin/zivpn-monitor-start

cat > /usr/local/bin/zivpn-monitor-stop <<'EOC'
#!/usr/bin/env bash
pm2 stop zivpn-monitor-bot || true
EOC
chmod +x /usr/local/bin/zivpn-monitor-stop

cat > /usr/local/bin/zivpn-monitor-restart <<'EOC'
#!/usr/bin/env bash
pm2 restart zivpn-monitor-bot || zivpn-monitor-start
pm2 save >/dev/null 2>&1 || true
EOC
chmod +x /usr/local/bin/zivpn-monitor-restart

cat > /usr/local/bin/zivpn-monitor-logs <<'EOC'
#!/usr/bin/env bash
pm2 logs zivpn-monitor-bot
EOC
chmod +x /usr/local/bin/zivpn-monitor-logs

# Aktifkan auto panel saat login root via Termius/SSH.
sed -i '/# ZIVPN_MONITOR_PANEL_START/,/# ZIVPN_MONITOR_PANEL_END/d' /root/.bashrc 2>/dev/null || true
cat >> /root/.bashrc <<'EOC'
# ZIVPN_MONITOR_PANEL_START
if [ -t 1 ] && [ -z "$ZIVPN_PANEL_OPENED" ] && [ -x /usr/local/bin/zivpn-monitor-panel ]; then
  export ZIVPN_PANEL_OPENED=1
  /usr/local/bin/zivpn-monitor-panel
fi
# ZIVPN_MONITOR_PANEL_END
EOC

pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true

echo
echo "Bot pusat berhasil dipasang."
echo "Panel otomatis aktif saat login root via Termius/SSH."
echo
echo "Langkah berikutnya:"
echo "1. Buka panel: zivpn-monitor-panel"
echo "2. Isi BOT_TOKEN dan CHAT_ID"
echo "3. Tambahkan server"
echo "4. Start bot"
echo
