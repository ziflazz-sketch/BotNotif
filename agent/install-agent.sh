#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/root/zivpn-monitor-agent"
SERVICE_NAME="zivpn-monitor-agent"
PORT_DEFAULT="5890"

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root."
  exit 1
fi

echo "======================================"
echo " Install ZiVPN Monitor Agent - Safe"
echo "======================================"

apt update -y
apt install -y curl openssl nodejs npm
npm install -g pm2 >/dev/null 2>&1 || true

mkdir -p "$APP_DIR"
cp agent.js package.json .env.example "$APP_DIR"/
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

if command -v ufw >/dev/null 2>&1; then
  ufw allow "$(grep '^AGENT_PORT=' /root/zivpn-monitor-agent/.env | cut -d= -f2)/tcp" >/dev/null 2>&1 || true
fi

echo
echo "Agent berhasil dipasang."
echo "Token dan port agent:"
echo "--------------------------------------"
cat /root/zivpn-monitor-agent/.env
echo "--------------------------------------"
echo
echo "Masukkan data di atas ke panel bot pusat."
echo "Cek log: pm2 logs $SERVICE_NAME"
