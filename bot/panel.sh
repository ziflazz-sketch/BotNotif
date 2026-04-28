#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/root/zivpn-monitor-bot"
ENV_FILE="$APP_DIR/.env"
SERVERS_FILE="$APP_DIR/servers.json"
SERVICE_NAME="zivpn-monitor-bot"

mkdir -p "$APP_DIR"
[ -f "$SERVERS_FILE" ] || echo '[]' > "$SERVERS_FILE"
[ -f "$ENV_FILE" ] || cp "$APP_DIR/.env.example" "$ENV_FILE" 2>/dev/null || true

pause() {
  echo
  read -rp "Tekan Enter untuk lanjut..." _ || true
}

header() {
  clear || true
  echo "================================================="
  echo "        ZiVPN Multi Server Monitor Panel"
  echo "                 SAFE VERSION"
  echo "================================================="
  echo "Data Telegram: tanpa IP, port, service, jumlah akun"
  echo "APP_DIR: $APP_DIR"
  echo "================================================="
}

pm2_status() {
  pm2 status "$SERVICE_NAME" 2>/dev/null || true
}

set_env_value() {
  local key="$1"
  local value="$2"
  touch "$ENV_FILE"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|g" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

get_env_value() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2- || true
}

list_servers() {
  node - "$SERVERS_FILE" <<'NODE'
const fs = require('fs');
const file = process.argv[2];
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
if (!Array.isArray(arr) || arr.length === 0) {
  console.log('Belum ada server.');
  process.exit(0);
}
arr.forEach((s, i) => {
  const token = s.token ? (String(s.token).slice(0,4) + '...' + String(s.token).slice(-4)) : '-';
  const disabled = s.disabled ? ' [DISABLED]' : '';
  console.log(`${i + 1}. ${s.name || '-'} | ${s.host || '-'}:${s.agentPort || 5890} | token ${token}${disabled}`);
});
NODE
}

add_server() {
  header
  echo "Tambah Server"
  echo "-----------------------------------------------"
  read -rp "Nama server        : " name
  read -rp "IP/domain server   : " host
  read -rp "Port agent [5890]  : " port
  read -rp "Token agent        : " token
  port="${port:-5890}"

  if [ -z "$name" ] || [ -z "$host" ] || [ -z "$token" ]; then
    echo "Nama, host, dan token wajib diisi."
    pause
    return
  fi

  node - "$SERVERS_FILE" "$name" "$host" "$port" "$token" <<'NODE'
const fs = require('fs');
const [file, name, host, port, token] = process.argv.slice(2);
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
if (!Array.isArray(arr)) arr = [];
arr.push({ name, host, agentPort: Number(port) || 5890, token });
fs.writeFileSync(file, JSON.stringify(arr, null, 2));
console.log('Server berhasil ditambahkan.');
NODE
  pause
}

edit_server() {
  header
  echo "Edit Server"
  echo "-----------------------------------------------"
  list_servers
  echo
  read -rp "Pilih nomor server: " num
  [ -z "$num" ] && return

  local current
  current=$(node - "$SERVERS_FILE" "$num" <<'NODE'
const fs = require('fs');
const [file, num] = process.argv.slice(2);
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
const idx = Number(num) - 1;
if (!arr[idx]) process.exit(1);
const s = arr[idx];
console.log([s.name || '', s.host || '', s.agentPort || 5890, s.token || ''].join('\n'));
NODE
) || { echo "Nomor tidak valid."; pause; return; }

  local old_name old_host old_port old_token
  old_name=$(echo "$current" | sed -n '1p')
  old_host=$(echo "$current" | sed -n '2p')
  old_port=$(echo "$current" | sed -n '3p')
  old_token=$(echo "$current" | sed -n '4p')

  read -rp "Nama server [$old_name]      : " name
  read -rp "IP/domain [$old_host]        : " host
  read -rp "Port agent [$old_port]       : " port
  read -rp "Token agent [tetap]          : " token

  name="${name:-$old_name}"
  host="${host:-$old_host}"
  port="${port:-$old_port}"
  token="${token:-$old_token}"

  node - "$SERVERS_FILE" "$num" "$name" "$host" "$port" "$token" <<'NODE'
const fs = require('fs');
const [file, num, name, host, port, token] = process.argv.slice(2);
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
const idx = Number(num) - 1;
if (!arr[idx]) {
  console.error('Nomor tidak valid.');
  process.exit(1);
}
arr[idx] = { ...arr[idx], name, host, agentPort: Number(port) || 5890, token };
fs.writeFileSync(file, JSON.stringify(arr, null, 2));
console.log('Server berhasil diedit.');
NODE
  pause
}

delete_server() {
  header
  echo "Hapus Server"
  echo "-----------------------------------------------"
  list_servers
  echo
  read -rp "Pilih nomor server yang dihapus: " num
  read -rp "Yakin hapus server nomor $num? [y/N]: " confirm
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) echo "Dibatalkan."; pause; return ;;
  esac

  node - "$SERVERS_FILE" "$num" <<'NODE'
const fs = require('fs');
const [file, num] = process.argv.slice(2);
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
const idx = Number(num) - 1;
if (!arr[idx]) {
  console.error('Nomor tidak valid.');
  process.exit(1);
}
const removed = arr.splice(idx, 1)[0];
fs.writeFileSync(file, JSON.stringify(arr, null, 2));
console.log(`Server ${removed.name || num} berhasil dihapus.`);
NODE
  pause
}

setting_bot() {
  header
  echo "Setting Bot Telegram"
  echo "-----------------------------------------------"
  echo "Kosongkan input kalau mau tetap pakai nilai lama."
  echo
  local old_token old_chat old_interval old_cpu old_ram old_disk
  old_token=$(get_env_value BOT_TOKEN)
  old_chat=$(get_env_value CHAT_ID)
  old_interval=$(get_env_value CHECK_INTERVAL)
  old_cpu=$(get_env_value CPU_THRESHOLD)
  old_ram=$(get_env_value RAM_THRESHOLD)
  old_disk=$(get_env_value DISK_THRESHOLD)

  read -rp "BOT_TOKEN [${old_token:0:8}...] : " token
  read -rp "CHAT_ID [$old_chat]             : " chat
  read -rp "Interval ms [$old_interval]     : " interval
  read -rp "CPU alert % [$old_cpu]          : " cpu
  read -rp "RAM alert % [$old_ram]          : " ram
  read -rp "Disk alert % [$old_disk]        : " disk

  [ -n "$token" ] && set_env_value BOT_TOKEN "$token"
  [ -n "$chat" ] && set_env_value CHAT_ID "$chat"
  [ -n "$interval" ] && set_env_value CHECK_INTERVAL "$interval"
  [ -n "$cpu" ] && set_env_value CPU_THRESHOLD "$cpu"
  [ -n "$ram" ] && set_env_value RAM_THRESHOLD "$ram"
  [ -n "$disk" ] && set_env_value DISK_THRESHOLD "$disk"

  echo "Setting berhasil disimpan. Restart bot agar aktif."
  pause
}

start_bot() {
  cd "$APP_DIR"
  pm2 start "$APP_DIR/app.js" --name "$SERVICE_NAME" --time || pm2 restart "$SERVICE_NAME"
  pm2 save >/dev/null 2>&1 || true
  pause
}

stop_bot() {
  pm2 stop "$SERVICE_NAME" || true
  pause
}

restart_bot() {
  pm2 restart "$SERVICE_NAME" || start_bot
  pm2 save >/dev/null 2>&1 || true
  pause
}

logs_bot() {
  echo "Tekan CTRL+C untuk keluar dari log."
  sleep 1
  pm2 logs "$SERVICE_NAME"
}

test_all() {
  header
  echo "Test semua server..."
  echo "-----------------------------------------------"
  node - "$SERVERS_FILE" <<'NODE'
const fs = require('fs');
const http = require('http');
const file = process.argv[2];
let arr = [];
try { arr = JSON.parse(fs.readFileSync(file, 'utf8')); } catch (_) {}
function req(s) {
  return new Promise((resolve) => {
    const url = `http://${s.host}:${s.agentPort || 5890}/health`;
    const r = http.request(url, { headers: { Authorization: `Bearer ${s.token}`, 'X-Agent-Token': s.token }, timeout: 7000 }, res => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          const j = JSON.parse(body);
          resolve({ name: s.name, ok: res.statusCode === 200 && j.ok, metrics: j.metrics });
        } catch (_) { resolve({ name: s.name, ok: false }); }
      });
    });
    r.on('timeout', () => r.destroy(new Error('timeout')));
    r.on('error', () => resolve({ name: s.name, ok: false }));
    r.end();
  });
}
(async () => {
  if (!arr.length) return console.log('Belum ada server.');
  for (let i = 0; i < arr.length; i++) {
    const r = await req(arr[i]);
    if (!r.ok) console.log(`${i + 1}. 🔴 ${r.name} - OFFLINE / TOKEN SALAH / AGENT TIDAK AKTIF`);
    else console.log(`${i + 1}. 🟢 ${r.name} - CPU ${r.metrics.cpuPercent}% | RAM ${r.metrics.ramPercent}% | Disk ${r.metrics.diskPercent}%`);
  }
})();
NODE
  pause
}

disable_auto_panel() {
  sed -i '/# ZIVPN_MONITOR_PANEL_START/,/# ZIVPN_MONITOR_PANEL_END/d' /root/.bashrc 2>/dev/null || true
  echo "Auto panel saat login dinonaktifkan."
  pause
}

enable_auto_panel() {
  sed -i '/# ZIVPN_MONITOR_PANEL_START/,/# ZIVPN_MONITOR_PANEL_END/d' /root/.bashrc 2>/dev/null || true
  cat >> /root/.bashrc <<'EOC'
# ZIVPN_MONITOR_PANEL_START
if [ -t 1 ] && [ -z "$ZIVPN_PANEL_OPENED" ] && [ -x /usr/local/bin/zivpn-monitor-panel ]; then
  export ZIVPN_PANEL_OPENED=1
  /usr/local/bin/zivpn-monitor-panel
fi
# ZIVPN_MONITOR_PANEL_END
EOC
  echo "Auto panel saat login root diaktifkan."
  pause
}

while true; do
  header
  echo "1) Status PM2 Bot"
  echo "2) Start Bot"
  echo "3) Stop Bot"
  echo "4) Restart Bot"
  echo "5) Tambah Server"
  echo "6) Edit Server"
  echo "7) Hapus Server"
  echo "8) List Server"
  echo "9) Setting Bot Telegram"
  echo "10) Test Semua Server"
  echo "11) Lihat Log Bot"
  echo "12) Edit servers.json manual"
  echo "13) Edit .env manual"
  echo "14) Aktifkan Auto Panel saat Login"
  echo "15) Nonaktifkan Auto Panel saat Login"
  echo "0) Keluar ke Terminal"
  echo "================================================="
  read -rp "Pilih menu: " pilih
  case "$pilih" in
    1) header; pm2_status; pause ;;
    2) start_bot ;;
    3) stop_bot ;;
    4) restart_bot ;;
    5) add_server ;;
    6) edit_server ;;
    7) delete_server ;;
    8) header; list_servers; pause ;;
    9) setting_bot ;;
    10) test_all ;;
    11) logs_bot ;;
    12) nano "$SERVERS_FILE" ;;
    13) nano "$ENV_FILE" ;;
    14) enable_auto_panel ;;
    15) disable_auto_panel ;;
    0) clear || true; exit 0 ;;
    *) echo "Pilihan tidak valid."; sleep 1 ;;
  esac
done
