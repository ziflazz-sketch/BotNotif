# BotNotif - ZiVPN Multi Server Monitor Bot

BotNotif adalah bot Telegram untuk monitoring banyak server ZiVPN dari 1 VPS pusat.

Sistem ini memakai konsep:

```text
VPS BOT PUSAT
  └─ Bot Telegram monitor
       ├─ cek Agent Server 1
       ├─ cek Agent Server 2
       ├─ cek Agent Server 3
       └─ dst sampai semua server ZiVPN

SETIAP VPS ZIVPN
  └─ Agent kecil port 5890
```

Versi ini dibuat lebih aman untuk grup Telegram karena **tidak menampilkan data sensitif** seperti:

```text
❌ Jumlah akun aktif / expired
❌ Status service internal VPS
❌ Port internal VPS
❌ IP/domain server di pesan Telegram
```

Yang dikirim ke grup Telegram hanya:

```text
✅ Nama server
✅ Online / offline
✅ CPU
✅ RAM
✅ Disk / SSD
✅ Load average
✅ Uptime
✅ Latency agent
✅ Waktu pengecekan
```

---

## Repository

```bash
https://github.com/ziflazz-sketch/BotNotif.git
```

---

## Syarat VPS

Gunakan OS Debian/Ubuntu dan login sebagai `root`.

Paket yang otomatis dipasang:

```text
git
curl
nano
nodejs
npm
pm2
```

---

# Cara Install

## 1. Install Jika Sudah Login Sebagai Root

Login ke VPS via Termius sebagai `root`, lalu jalankan salah satu perintah di bawah.

---

## 2. Install Sekali Jalan via curl

### Install BOT PUSAT

Jalankan ini di VPS khusus bot Telegram:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

### Install AGENT SERVER

Jalankan ini di setiap VPS ZiVPN yang ingin dimonitor:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

### Install Interaktif

Kalau ingin pilih menu install bot/agent:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh)
```

---

## 3. Install via git clone

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif
bash install.sh
```

Atau langsung pilih mode:

### BOT PUSAT

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif
bash install.sh bot
```

### AGENT SERVER

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif
bash install.sh agent
```

---

## 4. Install Langsung Manual

Kalau file sudah ada di VPS:

### BOT PUSAT

```bash
cd BotNotif/bot
bash install-bot.sh
```

### AGENT SERVER

```bash
cd BotNotif/agent
bash install-agent.sh
```

---

# Cara Pakai

## A. Install Agent di Semua Server ZiVPN

Di setiap VPS ZiVPN, jalankan:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

Setelah selesai, lihat token agent:

```bash
zivpn-agent-token
```

Contoh output:

```env
AGENT_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxx
AGENT_PORT=5890
SERVER_NAME=ID-BIZNET-1
```

Data ini nanti dimasukkan ke panel bot pusat.

---

## B. Install Bot Pusat

Di VPS khusus bot Telegram, jalankan:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

Setelah install, panel akan otomatis muncul saat login root via Termius.

Buka panel manual:

```bash
zivpn-monitor-panel
```

---

## C. Setting BOT_TOKEN dan CHAT_ID

Masuk panel:

```bash
zivpn-monitor-panel
```

Pilih menu:

```text
9) Setting Bot Telegram
```

Atau edit manual:

```bash
nano /root/zivpn-monitor-bot/.env
```

Contoh isi:

```env
BOT_TOKEN=123456:ABCDEF_TOKEN_BOT
CHAT_ID=-1001234567890
CHECK_INTERVAL=30000
CPU_THRESHOLD=90
RAM_THRESHOLD=90
DISK_THRESHOLD=90
ALERT_ON_FIRST_CHECK=true
```

Keterangan:

```text
BOT_TOKEN             Token bot dari BotFather
CHAT_ID               ID grup Telegram
CHECK_INTERVAL        Jeda cek server, default 30000 ms / 30 detik
CPU_THRESHOLD         Alert CPU jika lewat batas
RAM_THRESHOLD         Alert RAM jika lewat batas
DISK_THRESHOLD        Alert disk jika lewat batas
ALERT_ON_FIRST_CHECK  Kirim status saat pertama bot jalan
```

---

## D. Tambah Server ZiVPN ke Bot Pusat

Masuk panel:

```bash
zivpn-monitor-panel
```

Pilih:

```text
5) Tambah Server
```

Masukkan data:

```text
Nama server
IP/domain server
Port agent, default 5890
Token agent
```

File daftar server berada di:

```bash
/root/zivpn-monitor-bot/servers.json
```

Contoh format:

```json
[
  {
    "name": "ID BIZNET 1",
    "host": "1.2.3.4",
    "agentPort": 5890,
    "token": "TOKEN_AGENT_SERVER_1"
  },
  {
    "name": "SG DO 1",
    "host": "example.com",
    "agentPort": 5890,
    "token": "TOKEN_AGENT_SERVER_2"
  }
]
```

Catatan: `host` dan `agentPort` dipakai hanya untuk koneksi bot pusat ke agent. Data ini **tidak dikirim ke grup Telegram**.

---

# Panel Menu VPS

Setelah bot pusat terinstall, saat login root via Termius akan otomatis masuk panel.

Menu panel:

```text
1) Status PM2 Bot
2) Start Bot
3) Stop Bot
4) Restart Bot
5) Tambah Server
6) Edit Server
7) Hapus Server
8) List Server
9) Setting Bot Telegram
10) Test Semua Server
11) Lihat Log Bot
12) Edit servers.json manual
13) Edit .env manual
14) Aktifkan Auto Panel saat Login
15) Nonaktifkan Auto Panel saat Login
0) Keluar ke Terminal
```

Buka panel manual:

```bash
zivpn-monitor-panel
```

---

# Command Telegram

```text
/id       Ambil chat ID grup
/menu     Tampilkan tombol menu
/status   Cek semua server
/down     Lihat server offline
/list     Lihat daftar server
/server NAMA_SERVER
/reload   Reload config server
/help     Bantuan
```

---

# Perintah Penting VPS Bot Pusat

Start bot:

```bash
zivpn-monitor-start
```

Stop bot:

```bash
zivpn-monitor-stop
```

Restart bot:

```bash
zivpn-monitor-restart
```

Lihat log:

```bash
zivpn-monitor-logs
```

Buka panel:

```bash
zivpn-monitor-panel
```

---

# Perintah Penting VPS Agent

Lihat token agent:

```bash
zivpn-agent-token
```

Lihat status PM2 agent:

```bash
pm2 status zivpn-monitor-agent
```

Lihat log agent:

```bash
pm2 logs zivpn-monitor-agent
```

Restart agent:

```bash
pm2 restart zivpn-monitor-agent
```

---

# Keamanan

Agar lebih aman, batasi port agent `5890` hanya bisa diakses dari IP VPS bot pusat.

Jalankan di setiap server ZiVPN:

```bash
iptables -A INPUT -p tcp --dport 5890 -s IP_VPS_BOT_PUSAT -j ACCEPT
iptables -A INPUT -p tcp --dport 5890 -j DROP
netfilter-persistent save 2>/dev/null || true
```

Ganti `IP_VPS_BOT_PUSAT` dengan IP VPS bot pusat kamu.

---

# Update Source dari GitHub

Kalau repo sudah diperbarui, install ulang dengan perintah yang sama:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

atau untuk agent:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

Data `.env` dan `servers.json` lama tetap aman karena installer tidak menimpa file konfigurasi yang sudah ada.
