# ZiVPN Multi Server Monitor Bot - Safe Version

Bot Telegram untuk monitoring banyak server ZiVPN dari 1 VPS pusat.

Versi ini dibuat lebih aman untuk grup Telegram karena tidak menampilkan data sensitif seperti:

- Jumlah akun aktif / expired
- Status service internal
- Port internal VPS
- IP/domain server di pesan Telegram

Yang ditampilkan hanya:

- Online / offline server
- CPU
- RAM
- Disk
- Load average
- Uptime
- Waktu pengecekan

## Skema

```text
VPS BOT PUSAT
  └─ Bot Telegram monitor
       ├─ cek Agent Server 1
       ├─ cek Agent Server 2
       ├─ cek Agent Server 3
       └─ dst sampai 24 server

SETIAP VPS ZIVPN
  └─ Agent kecil port 5890
```

## 1. Install Agent di setiap VPS ZiVPN

Upload folder `agent` ke setiap server ZiVPN, lalu jalankan:

```bash
cd agent
bash install-agent.sh
```

Setelah selesai, catat token agent:

```bash
cat /root/zivpn-monitor-agent/.env
```

Yang dibutuhkan untuk bot pusat:

```env
AGENT_TOKEN=xxxxx
AGENT_PORT=5890
```

## 2. Install Bot di VPS Pusat

Upload folder `bot` ke VPS khusus bot, lalu jalankan:

```bash
cd bot
bash install-bot.sh
```

Setelah install, menu panel akan otomatis muncul saat login root via Termius.

Buka panel manual:

```bash
zivpn-monitor-panel
```

## 3. Isi BOT_TOKEN dan CHAT_ID

Di panel pilih:

```text
8) Setting Bot Telegram
```

Atau edit manual:

```bash
nano /root/zivpn-monitor-bot/.env
```

Contoh:

```env
BOT_TOKEN=123456:ABCDEF
CHAT_ID=-1001234567890
CHECK_INTERVAL=30000
CPU_THRESHOLD=90
RAM_THRESHOLD=90
DISK_THRESHOLD=90
```

## 4. Tambah 24 Server

Lewat panel pilih:

```text
5) Tambah Server
```

Data yang dimasukkan:

```text
Nama server
IP/domain server
Port agent, default 5890
Token agent
```

File daftar server ada di:

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
    "token": "TOKEN_AGENT_SERVER"
  }
]
```

## 5. Jalankan Bot

```bash
zivpn-monitor-start
```

Restart bot:

```bash
zivpn-monitor-restart
```

Lihat log:

```bash
zivpn-monitor-logs
```

## Command Telegram

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

## Keamanan

- Token agent wajib berbeda atau minimal rahasia.
- Bot tidak mengirim IP/domain server ke grup.
- Bot tidak mengirim port, service, atau jumlah akun.
- Disarankan batasi akses port agent hanya dari IP VPS bot pusat jika memungkinkan.

Contoh iptables di setiap server ZiVPN:

```bash
iptables -A INPUT -p tcp --dport 5890 -s IP_VPS_BOT_PUSAT -j ACCEPT
iptables -A INPUT -p tcp --dport 5890 -j DROP
netfilter-persistent save 2>/dev/null || true
```
