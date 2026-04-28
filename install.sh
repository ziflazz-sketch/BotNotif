#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ziflazz-sketch/BotNotif.git}"
TMP_DIR="/tmp/botnotif-install-$$"
MODE="${1:-}"
NODE_MAJOR="${NODE_MAJOR:-20}"
RUN_APT_UPGRADE="${RUN_APT_UPGRADE:-true}"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
nc='\033[0m'

info() { echo -e "${blue}[INFO]${nc} $*"; }
ok() { echo -e "${green}[OK]${nc} $*"; }
warn() { echo -e "${yellow}[PERHATIAN]${nc} $*"; }
err() { echo -e "${red}[ERROR]${nc} $*"; }

cleanup() { rm -rf "$TMP_DIR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Script ini wajib dijalankan sebagai root."
    echo "Login root dulu di Termius, lalu jalankan ulang script ini."
    exit 1
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    OS_NAME="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
  else
    OS_ID="unknown"
    OS_VERSION="unknown"
    OS_NAME="Unknown Linux"
  fi

  info "OS terdeteksi: $OS_NAME"

  case "$OS_ID" in
    ubuntu)
      case "$OS_VERSION" in
        20.04|22.04|24.04|20|22|24) ok "Ubuntu $OS_VERSION didukung." ;;
        *) warn "Ubuntu $OS_VERSION belum masuk daftar utama, tetap dicoba karena masih keluarga Ubuntu." ;;
      esac
      ;;
    debian)
      case "$OS_VERSION" in
        10|11|12|10.*|11.*|12.*) ok "Debian $OS_VERSION didukung." ;;
        *) warn "Debian $OS_VERSION belum masuk daftar utama, tetap dicoba karena masih keluarga Debian." ;;
      esac
      ;;
    kali)
      ok "Kali Linux didukung."
      ;;
    *)
      warn "OS bukan Ubuntu/Debian/Kali. Installer tetap mencoba jika apt tersedia."
      ;;
  esac

  if ! command -v apt-get >/dev/null 2>&1; then
    err "apt-get tidak ditemukan. Script ini untuk OS berbasis Debian/Ubuntu/Kali."
    exit 1
  fi
}

apt_wait_unlock() {
  local locks=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock)
  local waited=0
  while fuser "${locks[@]}" >/dev/null 2>&1; do
    if [ "$waited" -ge 180 ]; then
      warn "APT masih terkunci setelah 180 detik. Jika stuck, cek proses apt/dpkg yang berjalan."
      break
    fi
    echo "Menunggu proses apt/dpkg selesai... ${waited}s"
    sleep 5
    waited=$((waited + 5))
  done
}

apt_update_upgrade() {
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  apt_wait_unlock
  info "Menjalankan apt update..."
  apt-get update -y || apt-get update -y --allow-releaseinfo-change || true

  if [ "$RUN_APT_UPGRADE" = "true" ] || [ "$RUN_APT_UPGRADE" = "1" ] || [ "$RUN_APT_UPGRADE" = "yes" ]; then
    apt_wait_unlock
    info "Menjalankan apt upgrade -y..."
    apt-get upgrade -y \
      -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" || {
        warn "apt upgrade gagal/terhenti. Installer tetap lanjut ke install dependensi."
      }
  else
    warn "apt upgrade dilewati karena RUN_APT_UPGRADE=$RUN_APT_UPGRADE"
  fi
}

install_base_deps() {
  info "Menyiapkan dependensi dasar..."
  apt_update_upgrade
  apt_wait_unlock
  apt-get install -y ca-certificates curl gnupg git nano openssl procps lsof iproute2 || {
    err "Gagal install dependensi dasar. Cek koneksi internet/repository OS."
    exit 1
  }
}

node_major_version() {
  node -p "parseInt(process.versions.node.split('.')[0], 10)" 2>/dev/null || echo 0
}

node_ok() {
  local major
  major="$(node_major_version)"
  [ "$major" -ge 18 ] 2>/dev/null
}

install_node_pm2() {
  if node_ok && command -v npm >/dev/null 2>&1; then
    ok "Node.js sudah tersedia: $(node -v)"
  else
    info "Menginstall Node.js LTS dari NodeSource..."
    apt_wait_unlock
    if curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; then
      apt_wait_unlock
      apt-get install -y nodejs || true
    fi

    if ! node_ok; then
      warn "NodeSource ${NODE_MAJOR}.x gagal/tidak cocok. Mencoba NodeSource 18.x..."
      apt_wait_unlock
      if curl -fsSL "https://deb.nodesource.com/setup_18.x" | bash -; then
        apt_wait_unlock
        apt-get install -y nodejs || true
      fi
    fi

    if ! node_ok; then
      warn "Fallback ke repository bawaan OS."
      apt_wait_unlock
      apt-get install -y nodejs npm || true
    fi
  fi

  if ! node_ok; then
    err "Node.js minimal versi 18 belum tersedia. Versi saat ini: $(node -v 2>/dev/null || echo tidak ada)"
    echo "Coba update repository OS, lalu jalankan ulang installer."
    exit 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    err "npm tidak ditemukan meskipun node sudah ada. Jalankan: apt-get install -y npm"
    exit 1
  fi

  info "Menginstall PM2..."
  npm install -g pm2 >/dev/null 2>&1 || npm install -g pm2
  ok "Node: $(node -v) | npm: $(npm -v) | pm2: $(pm2 -v)"
}

choose_mode() {
  if [ -n "$MODE" ]; then
    case "$MODE" in
      bot|BOT|pusat|PUSAT) MODE="bot"; return ;;
      agent|AGENT|server|SERVER) MODE="agent"; return ;;
      *)
        err "Mode tidak dikenal: $MODE"
        echo "Gunakan: bash install.sh bot"
        echo "Atau:    bash install.sh agent"
        exit 1
        ;;
    esac
  fi

  clear || true
  echo "================================================="
  echo "        BotNotif ZiVPN Multi Server Monitor"
  echo "================================================="
  echo "Pilih jenis instalasi:"
  echo
  echo "1) Install BOT PUSAT"
  echo "   Dipasang di VPS khusus bot Telegram."
  echo
  echo "2) Install AGENT SERVER"
  echo "   Dipasang di setiap VPS ZiVPN."
  echo
  echo "0) Batal"
  echo "================================================="
  read -rp "Pilih [1/2/0]: " choice

  case "$choice" in
    1) MODE="bot" ;;
    2) MODE="agent" ;;
    0) echo "Dibatalkan."; exit 0 ;;
    *) err "Pilihan tidak valid."; exit 1 ;;
  esac
}

clone_repo() {
  info "Mengambil source dari repository GitHub..."
  rm -rf "$TMP_DIR"
  git clone --depth=1 "$REPO_URL" "$TMP_DIR"
}

install_bot() {
  if [ ! -f "$TMP_DIR/bot/install-bot.sh" ]; then
    err "File bot/install-bot.sh tidak ditemukan di repository."
    echo "Pastikan folder bot sudah diupload ke repository BotNotif."
    exit 1
  fi
  info "Memasang BOT PUSAT..."
  cd "$TMP_DIR/bot"
  bash install-bot.sh
}

install_agent() {
  if [ ! -f "$TMP_DIR/agent/install-agent.sh" ]; then
    err "File agent/install-agent.sh tidak ditemukan di repository."
    echo "Pastikan folder agent sudah diupload ke repository BotNotif."
    exit 1
  fi
  info "Memasang AGENT SERVER..."
  cd "$TMP_DIR/agent"
  bash install-agent.sh
}

main() {
  require_root
  detect_os
  choose_mode
  install_base_deps
  install_node_pm2
  clone_repo

  case "$MODE" in
    bot) install_bot ;;
    agent) install_agent ;;
  esac

  echo
  ok "Instalasi selesai."
  echo
  if [ "$MODE" = "bot" ]; then
    echo "Buka panel bot pusat:"
    echo "  zivpn-monitor-panel"
    echo
    echo "Jalankan bot:"
    echo "  zivpn-monitor-start"
  else
    echo "Lihat token agent untuk dimasukkan ke panel bot pusat:"
    echo "  zivpn-agent-token"
  fi
}

main "$@"
