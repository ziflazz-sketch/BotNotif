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

APP_DIR="/root/zivpn-monitor-agent"
SERVICE_NAME="zivpn-monitor-agent"
PORT_DEFAULT="5890"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root."
  exit 1
fi

cd "$SCRIPT_DIR"

echo "======================================"
echo " Install ZiVPN Monitor Agent - Safe"
echo "======================================"

# Dependensi dipasang juga di sini agar aman jika file ini dijalankan langsung.
apt_update_upgrade_direct
if command -v apt-get >/dev/null 2>&1; then
  apt-get install -y curl ca-certificates openssl nodejs npm procps lsof iproute2 || true
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

[ -f agent.js ] || { echo "ERROR: agent.js tidak ditemukan di folder agent."; exit 1; }
[ -f package.json ] || cat > package.json <<'EOP'
{"name":"zivpn-monitor-agent","version":"2.0.0","main":"agent.js","scripts":{"start":"node agent.js"}}
EOP

cp agent.js package.json "$APP_DIR"/

# Jangan gagal walaupun .env.example tidak ada di repo.
if [ -f .env.example ]; then
  cp .env.example "$APP_DIR/.env.example"
else
  cat > "$APP_DIR/.env.example" <<'EOP'
AGENT_TOKEN=change_me
AGENT_PORT=5890
SERVER_NAME=ZiVPN Server
EOP
fi

cd "$APP_DIR"

if [ ! -f .env ]; then
  TOKEN="${AGENT_TOKEN:-$(openssl rand -hex 24)}"
  PORT="${AGENT_PORT:-$PORT_DEFAULT}"
  HOSTNAME_NOW="$(hostname)"
  cat > .env <<EOC
AGENT_TOKEN=$TOKEN
AGENT_PORT=$PORT
SERVER_NAME=$HOSTNAME_NOW
EOC
fi

pm2 delete "$SERVICE_NAME" >/dev/null 2>&1 || true
pm2 start "$APP_DIR/agent.js" --name "$SERVICE_NAME" --time
pm2 save >/dev/null 2>&1 || true
pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true

cat > /usr/local/bin/zivpn-agent-token <<'EOC'
#!/usr/bin/env bash
cat /root/zivpn-monitor-agent/.env
EOC
chmod +x /usr/local/bin/zivpn-agent-token

cat > /usr/local/bin/zivpn-agent-restart <<'EOC'
#!/usr/bin/env bash
pm2 restart zivpn-monitor-agent || true
pm2 save >/dev/null 2>&1 || true
EOC
chmod +x /usr/local/bin/zivpn-agent-restart

cat > /usr/local/bin/zivpn-agent-logs <<'EOC'
#!/usr/bin/env bash
pm2 logs zivpn-monitor-agent
EOC
chmod +x /usr/local/bin/zivpn-agent-logs

AGENT_PORT_NOW="$(grep '^AGENT_PORT=' /root/zivpn-monitor-agent/.env | cut -d= -f2 || echo 5890)"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "${AGENT_PORT_NOW}/tcp" >/dev/null 2>&1 || true
fi

echo
echo "Agent berhasil dipasang."
echo "Token dan port agent:"
echo "--------------------------------------"
cat /root/zivpn-monitor-agent/.env
echo "--------------------------------------"
echo
echo "Masukkan data di atas ke panel bot pusat."
echo "Cek token: zivpn-agent-token"
echo "Cek log: pm2 logs $SERVICE_NAME"
echo
