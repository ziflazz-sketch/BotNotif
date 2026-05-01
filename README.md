# BotNotif - ZiVPN Multi Server Monitor Safe

BotNotif adalah bot Telegram untuk monitoring banyak server ZiVPN dari VPS pusat. Sistem ini memakai model:

```text
VPS BOT PUSAT
  └── Bot Telegram monitor

24 SERVER ZIVPN
  └── Agent kecil per server
```

Bot pusat akan mengambil data dari agent tiap server melalui IP/domain + token agent. Data yang dikirim ke grup Telegram dibuat aman.

## Data yang Ditampilkan di Telegram

```text
✅ Nama server
✅ Status online/offline
✅ CPU
✅ RAM
✅ Disk/SSD
✅ Load
✅ Uptime
✅ Latency agent
```

## Data Sensitif yang Tidak Ditampilkan

```text
❌ Jumlah akun aktif/expired
❌ Service zivpn.service
❌ Service zivpn-api.service
❌ Service badvpn-udpgw.service
❌ Port 22
❌ Port 5888
❌ Port 5667
❌ Port 7300
❌ IP/domain server di pesan Telegram
```

## Support OS

Installer dibuat untuk OS berbasis Debian/Ubuntu/Kali:

```text
✅ Ubuntu 20.04
✅ Ubuntu 22.04
✅ Ubuntu 24.04
✅ Debian 10
✅ Debian 11
✅ Debian 12
✅ Kali Linux
```

Script menggunakan `apt-get`, jadi wajib dijalankan sebagai `root`.

## APT Update & Upgrade

Installer sudah ditambahkan `apt update` dan `apt upgrade` otomatis sebelum install dependensi.

Yang dijalankan installer:

```bash
apt-get update -y
apt-get upgrade -y
```

Tujuannya supaya repository dan package OS siap sebelum install Node.js, npm, git, curl, dan PM2.

Rekomendasi:

```text
✅ VPS baru: biarkan apt upgrade aktif
✅ VPS production/ramai dipakai: boleh lewati apt upgrade agar lebih cepat
```

Untuk melewati `apt upgrade`, gunakan:

```bash
RUN_APT_UPGRADE=false bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

Untuk agent:

```bash
RUN_APT_UPGRADE=false bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

## Struktur Repository

Upload semua file ke repository GitHub seperti ini:

```text
BotNotif/
├── install.sh
├── README.md
├── bot/
│   ├── app.js
│   ├── package.json
│   ├── panel.sh
│   ├── install-bot.sh
│   ├── .env.example
│   └── servers.example.json
└── agent/
    ├── agent.js
    ├── package.json
    ├── install-agent.sh
    └── .env.example
```

> Catatan: file `.env.example` itu file tersembunyi karena diawali titik. Pastikan ikut terupload ke GitHub. Jika lupa, installer versi baru tetap aman karena otomatis membuat file default.

## Install BOT PUSAT via Curl

Jalankan di VPS khusus bot pusat:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

Setelah selesai, panel otomatis aktif saat login root via Termius/SSH.

Buka panel manual:

```bash
zivpn-monitor-panel
```

Jalankan bot:

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

Lihat log bot:

```bash
zivpn-monitor-logs
```

## Install AGENT di Setiap VPS ZiVPN via Curl

Jalankan di setiap VPS ZiVPN:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

Lihat token agent:

```bash
zivpn-agent-token
```

Contoh output:

```env
AGENT_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
AGENT_PORT=5890
SERVER_NAME=ID-BIZNET-1
```

Data ini dimasukkan ke panel bot pusat.

## Install via Git Clone

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif
bash install.sh
```

Atau langsung pilih mode:

```bash
bash install.sh bot
```

```bash
bash install.sh agent
```

## Install Manual BOT PUSAT

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif/bot
bash install-bot.sh
```

## Install Manual AGENT

```bash
git clone https://github.com/ziflazz-sketch/BotNotif.git
cd BotNotif/agent
bash install-agent.sh
```

## Cara Setting Bot Telegram

1. Buat bot di Telegram lewat `@BotFather`.
2. Ambil token bot.
3. Masukkan bot ke grup Telegram.
4. Jadikan bot sebagai admin grup.
5. Kirim pesan di grup:

```text
/id
/setthread
```

6. Salin `CHAT_ID` yang dikirim bot.
7. Masuk ke panel VPS bot pusat:

```bash
zivpn-monitor-panel
```

8. Pilih menu:

```text
9) Setting Bot Telegram / THREAD_ID
```

Masukkan:

```text
BOT_TOKEN
CHAT_ID
CHECK_INTERVAL
CPU_THRESHOLD
RAM_THRESHOLD
DISK_THRESHOLD
```

## Cara Tambah Server

Di VPS bot pusat:

```bash
zivpn-monitor-panel
```

Pilih:

```text
5) Tambah Server
```

Masukkan:

```text
Nama server
IP/domain server
Port agent: 5890
Token agent
```

## Menu Panel VPS

```text
1) Status PM2 Bot
2) Start Bot
3) Stop Bot
4) Restart Bot
5) Tambah Server
6) Edit Server
7) Hapus Server
8) List Server
9) Setting Bot Telegram / THREAD_ID
10) Test Semua Server
11) Lihat Log Bot
12) Edit servers.json manual
13) Edit .env manual
14) Aktifkan Auto Panel saat Login
15) Nonaktifkan Auto Panel saat Login
0) Keluar ke Terminal
```

## Command Telegram

```text
/menu
/status
/down
/list
/server NAMA_SERVER
/reload
/id
/setthread
/help
```

## Cara Memperbaiki Error `.env.example` Tidak Ada

Jika muncul:

```text
cp: cannot stat '.env.example': No such file or directory
```

Artinya file `.env.example` tidak ada di folder yang sedang dipakai installer. Penyebab umum:

```text
1. File .env.example belum terupload ke GitHub.
2. Installer dijalankan dari folder yang salah.
3. Folder bot/agent belum lengkap di repository.
4. File tersembunyi tidak ikut dipilih saat upload manual.
```

Solusi terbaik:

```bash
cd /root
rm -rf BotNotif
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) bot
```

Untuk agent:

```bash
cd /root
rm -rf BotNotif
bash <(curl -fsSL https://raw.githubusercontent.com/ziflazz-sketch/BotNotif/main/install.sh) agent
```

Installer versi baru tetap akan membuat `.env.example` default otomatis walaupun file itu belum ada.

## Catatan Keamanan

Agent membuka endpoint:

```text
http://IP_SERVER:5890/health
```

Endpoint wajib memakai token agent. Tanpa token, request akan ditolak.

Bot Telegram tidak menampilkan IP/domain, port ZiVPN, service internal, atau jumlah akun ke grup.

## Troubleshooting

Cek status bot pusat:

```bash
pm2 status zivpn-monitor-bot
```

Cek log bot pusat:

```bash
pm2 logs zivpn-monitor-bot
```

Cek status agent:

```bash
pm2 status zivpn-monitor-agent
```

Cek log agent:

```bash
pm2 logs zivpn-monitor-agent
```

Tes agent dari VPS bot pusat:

```bash
curl -H "Authorization: Bearer TOKEN_AGENT" http://IP_SERVER:5890/health
```

Jika tidak bisa connect, cek firewall provider VPS dan pastikan port `5890/tcp` dibuka.

## Cara Kirim Status ke Topik Cek Server

Kalau grup Telegram memakai forum/topik seperti `TRX Bot` dan `Cek Server`, bot harus memakai `MESSAGE_THREAD_ID`. Jangan langsung memakai angka dari link `https://t.me/nama_grup/3302`, karena angka itu sering hanya `message_id`, bukan `thread_id` tujuan.

Cara paling aman:

```text
1. Buka topik Cek Server di grup Telegram
2. Kirim /id
/setthread di topik Cek Server
3. Lihat bagian THREAD_ID_TOPIK_INI
4. Kirim /setthread di topik Cek Server
5. Restart bot jika diperlukan: zivpn-monitor-restart
```

Setelah `/setthread`, bot otomatis menyimpan nilai ini ke `.env`:

```env
MESSAGE_THREAD_ID=isi_thread_id_cek_server
```

Cek manual:

```bash
grep MESSAGE_THREAD_ID /root/zivpn-monitor-bot/.env
```

Restart bot:

```bash
zivpn-monitor-restart
```

Command Telegram versi topic support:

```text
/menu
/status
/down
/list
/server NAMA_SERVER
/reload
/id
/setthread
/help
```
