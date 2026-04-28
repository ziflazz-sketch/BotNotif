#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ziflazz-sketch/BotNotif.git}"
TMP_DIR="/tmp/botnotif-install-$$"
MODE="${1:-}"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[0;34m'
nc='\033[0m'

info() { echo -e "${blue}[INFO]${nc} $*"; }
ok() { echo -e "${green}[OK]${nc} $*"; }
warn() { echo -e "${yellow}[PERHATIAN]${nc} $*"; }
err() { echo -e "${red}[ERROR]${nc} $*"; }

cleanup() {
  rm -rf "$TMP_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Script ini wajib dijalankan sebagai root."
    echo "Login root dulu di Termius, lalu jalankan ulang script ini."
    exit 1
  fi
}

install_base_deps() {
  info "Menyiapkan dependensi dasar..."
  export DEBIAN_FRONTEND=noninteractive
  apt update -y
  apt install -y git curl ca-certificates nano
}

choose_mode() {
  if [ -n "$MODE" ]; then
    case "$MODE" in
      bot|BOT|pusat|PUSAT)
        MODE="bot"
        return
        ;;
      agent|AGENT|server|SERVER)
        MODE="agent"
        return
        ;;
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
  echo "   Fungsinya monitor semua server ZiVPN."
  echo
  echo "2) Install AGENT SERVER"
  echo "   Dipasang di setiap VPS ZiVPN."
  echo "   Fungsinya kirim data CPU/RAM/Disk ke bot pusat."
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
  choose_mode
  install_base_deps
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
