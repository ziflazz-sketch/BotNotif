#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/root/zivpn-monitor-bot"
SERVICE_NAME="zivpn-monitor-bot"

if [ "$(id -u)" -ne 0 ]; then
  echo "Jalankan sebagai root."
  exit 1
fi

echo "==============================================="
echo " Install ZiVPN Multi Server Monitor Bot - Safe"
echo "==============================================="

apt update -y
apt install -y curl nano nodejs npm
npm install -g pm2 >/dev/null 2>&1 || true

mkdir -p "$APP_DIR"
cp app.js package.json panel.sh .env.example servers.example.json "$APP_DIR"/
chmod +x "$APP_DIR/panel.sh"

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

pm2 startup systemd -u root --hp /root >/dev/null 2>&1 || true

# Auto open panel on root interactive login via Termius/SSH
sed -i '/# ZIVPN_MONITOR_PANEL_START/,/# ZIVPN_MONITOR_PANEL_END/d' /root/.bashrc 2>/dev/null || true
cat >> /root/.bashrc <<'EOC'
# ZIVPN_MONITOR_PANEL_START
if [ -t 1 ] && [ -z "$ZIVPN_PANEL_OPENED" ] && [ -x /usr/local/bin/zivpn-monitor-panel ]; then
  export ZIVPN_PANEL_OPENED=1
  /usr/local/bin/zivpn-monitor-panel
fi
# ZIVPN_MONITOR_PANEL_END
EOC

echo
echo "Install selesai."
echo "Panel otomatis aktif saat login root via Termius/SSH."
echo
echo "Buka panel sekarang:"
echo "  zivpn-monitor-panel"
echo
echo "Setelah isi BOT_TOKEN, CHAT_ID, dan daftar server, jalankan:"
echo "  zivpn-monitor-start"
echo
read -rp "Buka panel sekarang? [Y/n]: " open_panel
case "${open_panel:-Y}" in
  y|Y|yes|YES) /usr/local/bin/zivpn-monitor-panel ;;
  *) echo "Selesai." ;;
esac
