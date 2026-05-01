'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const APP_DIR = process.env.APP_DIR || '/root/zivpn-monitor-bot';
const ENV_PATH = path.join(APP_DIR, '.env');
const SERVERS_PATH = path.join(APP_DIR, 'servers.json');
const STATE_PATH = path.join(APP_DIR, 'state.json');

function loadEnv(file) {
  try {
    const raw = fs.readFileSync(file, 'utf8');
    raw.split(/\r?\n/).forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const idx = trimmed.indexOf('=');
      if (idx === -1) return;
      const key = trimmed.slice(0, idx).trim();
      const value = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
      process.env[key] = value;
    });
  } catch (err) {
    console.error('Gagal membaca .env:', err.message);
  }
}

loadEnv(ENV_PATH);

const BOT_TOKEN = process.env.BOT_TOKEN || '';
const CHAT_ID = String(process.env.CHAT_ID || '').trim();
const CHECK_INTERVAL = Math.max(10000, Number(process.env.CHECK_INTERVAL || 30000));
const CPU_THRESHOLD = Number(process.env.CPU_THRESHOLD || 90);
const RAM_THRESHOLD = Number(process.env.RAM_THRESHOLD || 90);
const DISK_THRESHOLD = Number(process.env.DISK_THRESHOLD || 90);
const ALERT_ON_FIRST_CHECK = String(process.env.ALERT_ON_FIRST_CHECK || 'true').toLowerCase() === 'true';

let servers = [];
let statusCache = new Map();
let lastUpdateId = 0;
let monitoringTimer = null;

function configuredThreadId() {
  const raw = String(process.env.MESSAGE_THREAD_ID || process.env.THREAD_ID || '').trim();
  if (!raw || raw === '-' || raw === '0') return null;
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : null;
}

function setEnvValue(key, value) {
  try {
    let raw = '';
    try { raw = fs.readFileSync(ENV_PATH, 'utf8'); } catch (_) {}
    const lines = raw.split(/\r?\n/).filter((line) => line.length > 0);
    let found = false;
    const updated = lines.map((line) => {
      if (line.startsWith(`${key}=`)) {
        found = true;
        return `${key}=${value}`;
      }
      return line;
    });
    if (!found) updated.push(`${key}=${value}`);
    fs.writeFileSync(ENV_PATH, updated.join('\n') + '\n');
    process.env[key] = String(value);
    return true;
  } catch (err) {
    console.error('Gagal update .env:', err.message);
    return false;
  }
}

function escapeHtml(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function loadServers() {
  try {
    const raw = fs.readFileSync(SERVERS_PATH, 'utf8');
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) throw new Error('servers.json harus array');
    servers = parsed
      .filter((s) => s && s.name && s.host && s.token)
      .map((s) => ({
        name: String(s.name),
        host: String(s.host),
        agentPort: Number(s.agentPort || s.port || 5890),
        token: String(s.token),
        disabled: Boolean(s.disabled)
      }))
      .filter((s) => !s.disabled);
    console.log(`Loaded ${servers.length} server(s).`);
  } catch (err) {
    console.error('Gagal membaca servers.json:', err.message);
    servers = [];
  }
}

function loadState() {
  try {
    const raw = fs.readFileSync(STATE_PATH, 'utf8');
    const obj = JSON.parse(raw);
    Object.entries(obj).forEach(([name, value]) => statusCache.set(name, value));
  } catch (_) {}
}

function saveState() {
  try {
    const obj = {};
    statusCache.forEach((value, key) => {
      obj[key] = {
        online: value.online,
        alertKey: value.alertKey || '',
        lastChecked: value.lastChecked || new Date().toISOString()
      };
    });
    fs.writeFileSync(STATE_PATH, JSON.stringify(obj, null, 2));
  } catch (err) {
    console.error('Gagal menyimpan state:', err.message);
  }
}

function requestJson(url, options = {}) {
  return new Promise((resolve, reject) => {
    const lib = url.startsWith('https:') ? https : http;
    const req = lib.request(url, {
      method: options.method || 'GET',
      headers: options.headers || {},
      timeout: options.timeout || 7000
    }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        try {
          const data = body ? JSON.parse(body) : {};
          if (res.statusCode >= 200 && res.statusCode < 300) resolve(data);
          else {
            const err = new Error(data.description || data.error || `HTTP ${res.statusCode}`);
            err.statusCode = res.statusCode;
            err.data = data;
            reject(err);
          }
        } catch (_) {
          reject(new Error('Invalid JSON response'));
        }
      });
    });
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.on('error', reject);
    if (options.body) req.write(options.body);
    req.end();
  });
}

async function telegram(method, payload) {
  if (!BOT_TOKEN || BOT_TOKEN.includes('ISI_TOKEN')) {
    console.error('BOT_TOKEN belum diisi.');
    return null;
  }
  const body = JSON.stringify(payload || {});
  return requestJson(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: 'POST',
    timeout: 15000,
    headers: {
      'Content-Type': 'application/json',
      'Content-Length': Buffer.byteLength(body)
    },
    body
  });
}

async function sendMessage(chatId, text, extra = {}, threadId = null) {
  const targetChatId = chatId || CHAT_ID;
  const payload = {
    chat_id: targetChatId,
    text,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
    ...extra
  };

  const finalThreadId = threadId || payload.message_thread_id || configuredThreadId();
  if (finalThreadId && String(targetChatId) === String(CHAT_ID)) {
    payload.message_thread_id = Number(finalThreadId);
  }

  return telegram('sendMessage', payload).catch((err) => console.error('Send message error:', err.message));
}

async function answerCallbackQuery(callbackQueryId, text) {
  return telegram('answerCallbackQuery', {
    callback_query_id: callbackQueryId,
    text: text || ''
  }).catch(() => null);
}

async function editMessageText(chatId, messageId, text, extra = {}, threadId = null) {
  return telegram('editMessageText', {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: 'HTML',
    disable_web_page_preview: true,
    ...extra
  }).catch(() => sendMessage(chatId, text, extra, threadId));
}

function isAllowedChat(chatId) {
  if (!CHAT_ID || CHAT_ID.includes('ISI_CHAT')) return true;
  return String(chatId) === CHAT_ID;
}

function agentUrl(server) {
  return `http://${server.host}:${server.agentPort}/health`;
}

async function checkServer(server) {
  const start = Date.now();
  try {
    const data = await requestJson(agentUrl(server), {
      timeout: 8000,
      headers: {
        Authorization: `Bearer ${server.token}`,
        'X-Agent-Token': server.token
      }
    });
    if (!data || !data.ok || !data.metrics) throw new Error('agent_not_ok');
    return {
      name: server.name,
      online: true,
      latencyMs: Date.now() - start,
      metrics: data.metrics,
      error: null,
      checkedAt: new Date().toISOString()
    };
  } catch (err) {
    return {
      name: server.name,
      online: false,
      latencyMs: Date.now() - start,
      metrics: null,
      error: err.message || 'offline',
      checkedAt: new Date().toISOString()
    };
  }
}

function getAlertKey(result) {
  if (!result.online) return 'OFFLINE';
  const m = result.metrics || {};
  const alerts = [];
  if (Number(m.cpuPercent || 0) >= CPU_THRESHOLD) alerts.push('CPU');
  if (Number(m.ramPercent || 0) >= RAM_THRESHOLD) alerts.push('RAM');
  if (Number(m.diskPercent || 0) >= DISK_THRESHOLD) alerts.push('DISK');
  return alerts.length ? `HIGH_${alerts.join('_')}` : 'OK';
}

function formatMetricLine(m) {
  if (!m) return 'Tidak ada data.';
  return [
    `CPU: <b>${m.cpuPercent}%</b>`,
    `RAM: <b>${m.ramPercent}%</b> (${m.ramUsedGb}/${m.ramTotalGb} GB)`,
    `Disk: <b>${m.diskPercent}%</b> (${m.diskUsedGb}/${m.diskTotalGb} GB)`,
    `Load: <b>${m.load1}</b> / ${m.load5} / ${m.load15}`,
    `Uptime: <b>${escapeHtml(m.uptimeHuman)}</b>`
  ].join('\n');
}

function formatServerStatus(result) {
  const icon = result.online ? '🟢' : '🔴';
  if (!result.online) return `${icon} <b>${escapeHtml(result.name)}</b>\nStatus: <b>OFFLINE</b>\nLatency: ${result.latencyMs}ms`;
  return `${icon} <b>${escapeHtml(result.name)}</b>\nStatus: <b>ONLINE</b>\nLatency: ${result.latencyMs}ms\n${formatMetricLine(result.metrics)}`;
}

function chunkText(text, limit = 3800) {
  const parts = [];
  let current = '';
  for (const block of text.split('\n\n')) {
    if ((current + '\n\n' + block).length > limit) {
      if (current) parts.push(current);
      current = block;
    } else {
      current = current ? `${current}\n\n${block}` : block;
    }
  }
  if (current) parts.push(current);
  return parts;
}

async function checkAllServers() {
  const results = [];
  for (const server of servers) results.push(await checkServer(server));
  return results;
}

function formatSummary(results) {
  const online = results.filter((r) => r.online).length;
  const offline = results.length - online;
  const header = [
    '📡 <b>ZiVPN Multi Server Monitor</b>',
    `Total: <b>${results.length}</b> | Online: <b>${online}</b> | Offline: <b>${offline}</b>`,
    `Update: <code>${new Date().toLocaleString('id-ID', { timeZone: 'Asia/Jakarta' })}</code>`
  ].join('\n');

  const body = results.map((r, i) => {
    if (!r.online) return `${i + 1}. 🔴 <b>${escapeHtml(r.name)}</b> — OFFLINE`;
    const m = r.metrics || {};
    return `${i + 1}. 🟢 <b>${escapeHtml(r.name)}</b> — CPU ${m.cpuPercent}% | RAM ${m.ramPercent}% | Disk ${m.diskPercent}% | Up ${escapeHtml(m.uptimeHuman || '-')}`;
  }).join('\n');

  return `${header}\n\n${body || 'Belum ada server.'}`;
}

function formatDown(results) {
  const down = results.filter((r) => !r.online);
  if (!down.length) return '✅ Semua server terpantau online.';
  return '🔴 <b>Server Offline</b>\n\n' + down.map((r, i) => `${i + 1}. <b>${escapeHtml(r.name)}</b>\nLatency: ${r.latencyMs}ms`).join('\n\n');
}

async function monitorLoop() {
  if (!servers.length) {
    console.log('Belum ada server di servers.json');
    return;
  }

  const results = await checkAllServers();
  for (const result of results) {
    const previous = statusCache.get(result.name);
    const alertKey = getAlertKey(result);
    const firstCheck = !previous;
    const shouldAlertFirst = firstCheck && ALERT_ON_FIRST_CHECK && alertKey !== 'OK';
    const statusChanged = previous && previous.online !== result.online;
    const alertChanged = previous && previous.alertKey !== alertKey;

    if (shouldAlertFirst || statusChanged || alertChanged) {
      let title = 'ℹ️ <b>Update Server</b>';
      if (!result.online) title = '🚨 <b>SERVER OFFLINE</b>';
      else if (previous && previous.online === false) title = '✅ <b>SERVER NORMAL KEMBALI</b>';
      else if (alertKey !== 'OK') title = '⚠️ <b>RESOURCE TINGGI</b>';
      else if (previous && previous.alertKey && previous.alertKey !== 'OK') title = '✅ <b>RESOURCE NORMAL KEMBALI</b>';
      await sendMessage(CHAT_ID, `${title}\n\n${formatServerStatus(result)}`);
    }

    statusCache.set(result.name, {
      online: result.online,
      alertKey,
      lastChecked: result.checkedAt
    });
  }
  saveState();
}

function mainKeyboard() {
  return {
    inline_keyboard: [
      [
        { text: '📡 Status Semua', callback_data: 'status' },
        { text: '🔴 Server Down', callback_data: 'down' }
      ],
      [
        { text: '📋 List Server', callback_data: 'list' },
        { text: '🔄 Reload Config', callback_data: 'reload' }
      ],
      [{ text: 'ℹ️ Bantuan', callback_data: 'help' }]
    ]
  };
}

async function handleCommand(chatId, text, messageId, messageThreadId = null) {
  const parts = String(text || '').trim().split(/\s+/);
  const cmd = (parts[0] || '').split('@')[0].toLowerCase();
  const args = parts.slice(1).join(' ');
  const replyThreadId = messageThreadId || configuredThreadId();

  if (cmd === '/id') {
    return sendMessage(chatId, [
      '📌 <b>ID Telegram</b>',
      '',
      `CHAT_ID: <code>${chatId}</code>`,
      `THREAD_ID_TOPIK_INI: <code>${messageThreadId || '-'}</code>`,
      `THREAD_ID_ENV: <code>${configuredThreadId() || '-'}</code>`,
      '',
      'Kirim <code>/setthread</code> di topik Cek Server untuk mengunci semua notif otomatis ke topik ini.'
    ].join('\n'), {}, messageThreadId);
  }

  if (cmd === '/setthread') {
    if (!messageThreadId) {
      return sendMessage(chatId, '❌ THREAD_ID tidak terdeteksi. Pastikan grup memakai forum/topik dan kirim command ini di dalam topik Cek Server.', {}, messageThreadId);
    }
    const ok = setEnvValue('MESSAGE_THREAD_ID', messageThreadId);
    return sendMessage(chatId, ok
      ? `✅ THREAD_ID berhasil disimpan: <code>${messageThreadId}</code>\n\nMulai sekarang notif otomatis dikirim ke topik ini.`
      : '❌ Gagal menyimpan THREAD_ID ke .env.', {}, messageThreadId);
  }

  if (!isAllowedChat(chatId)) {
    return sendMessage(chatId, 'Akses ditolak. Bot ini hanya untuk grup yang sudah diatur.', {}, replyThreadId);
  }

  if (cmd === '/start' || cmd === '/menu') {
    return sendMessage(chatId, '📡 <b>Panel Monitor ZiVPN</b>\nPilih menu di bawah ini:', { reply_markup: mainKeyboard() }, replyThreadId);
  }

  if (cmd === '/status') {
    const msg = await sendMessage(chatId, '⏳ Mengecek semua server...', {}, replyThreadId);
    const results = await checkAllServers();
    const chunks = chunkText(formatSummary(results));
    if (msg && msg.result && chunks[0]) {
      await editMessageText(chatId, msg.result.message_id, chunks[0], {}, replyThreadId);
      for (const extra of chunks.slice(1)) await sendMessage(chatId, extra, {}, replyThreadId);
    } else {
      for (const chunk of chunks) await sendMessage(chatId, chunk, {}, replyThreadId);
    }
    return;
  }

  if (cmd === '/down') {
    const results = await checkAllServers();
    return sendMessage(chatId, formatDown(results), {}, replyThreadId);
  }

  if (cmd === '/list') {
    const body = servers.length ? servers.map((s, i) => `${i + 1}. <b>${escapeHtml(s.name)}</b>`).join('\n') : 'Belum ada server.';
    return sendMessage(chatId, `📋 <b>Daftar Server</b>\n\n${body}`, {}, replyThreadId);
  }

  if (cmd === '/server') {
    if (!args) return sendMessage(chatId, 'Format:\n<code>/server NAMA_SERVER</code>', {}, replyThreadId);
    const server = servers.find((s) => s.name.toLowerCase() === args.toLowerCase()) || servers.find((s) => s.name.toLowerCase().includes(args.toLowerCase()));
    if (!server) return sendMessage(chatId, 'Server tidak ditemukan. Cek /list', {}, replyThreadId);
    const result = await checkServer(server);
    return sendMessage(chatId, formatServerStatus(result), {}, replyThreadId);
  }

  if (cmd === '/reload') {
    loadEnv(ENV_PATH);
    loadServers();
    return sendMessage(chatId, `✅ Config server berhasil direload. Total server: <b>${servers.length}</b>`, {}, replyThreadId);
  }

  if (cmd === '/help') {
    return sendMessage(chatId, [
      '📖 <b>Bantuan ZiVPN Monitor</b>',
      '',
      '<code>/menu</code> - tombol menu',
      '<code>/status</code> - cek semua server',
      '<code>/down</code> - cek server offline',
      '<code>/list</code> - daftar nama server',
      '<code>/server NAMA</code> - detail 1 server',
      '<code>/reload</code> - reload servers.json',
      '<code>/id</code> - ambil chat ID dan THREAD_ID',
      '<code>/setthread</code> - set topik tujuan notif otomatis',
      '',
      'Data sensitif seperti IP/domain, port, service, dan jumlah akun tidak ditampilkan di Telegram.'
    ].join('\n'), {}, replyThreadId);
  }
}

async function handleCallback(callback) {
  const chatId = callback.message.chat.id;
  const messageId = callback.message.message_id;
  const threadId = callback.message.message_thread_id || configuredThreadId();
  const data = callback.data;
  await answerCallbackQuery(callback.id, 'Diproses...');
  if (!isAllowedChat(chatId)) return;

  if (data === 'status') {
    const results = await checkAllServers();
    return editMessageText(chatId, messageId, formatSummary(results), { reply_markup: mainKeyboard() }, threadId);
  }
  if (data === 'down') {
    const results = await checkAllServers();
    return editMessageText(chatId, messageId, formatDown(results), { reply_markup: mainKeyboard() }, threadId);
  }
  if (data === 'list') {
    const body = servers.length ? servers.map((s, i) => `${i + 1}. <b>${escapeHtml(s.name)}</b>`).join('\n') : 'Belum ada server.';
    return editMessageText(chatId, messageId, `📋 <b>Daftar Server</b>\n\n${body}`, { reply_markup: mainKeyboard() }, threadId);
  }
  if (data === 'reload') {
    loadServers();
    return editMessageText(chatId, messageId, `✅ Config server direload. Total server: <b>${servers.length}</b>`, { reply_markup: mainKeyboard() }, threadId);
  }
  if (data === 'help') {
    return editMessageText(chatId, messageId, [
      '📖 <b>Bantuan ZiVPN Monitor</b>',
      '',
      'Gunakan /status, /down, /list, /server NAMA_SERVER, /reload.',
      'Gunakan /setthread di topik Cek Server agar notif otomatis masuk ke topik itu.',
      '',
      'Data sensitif tidak ditampilkan di grup.'
    ].join('\n'), { reply_markup: mainKeyboard() }, threadId);
  }
}

async function pollTelegram() {
  if (!BOT_TOKEN || BOT_TOKEN.includes('ISI_TOKEN')) return;
  try {
    const data = await telegram('getUpdates', {
      offset: lastUpdateId + 1,
      timeout: 25,
      allowed_updates: ['message', 'callback_query']
    });
    const updates = data && data.result ? data.result : [];
    for (const update of updates) {
      lastUpdateId = Math.max(lastUpdateId, update.update_id);
      if (update.message && update.message.text) {
        await handleCommand(update.message.chat.id, update.message.text, update.message.message_id, update.message.message_thread_id || null);
      } else if (update.callback_query) {
        await handleCallback(update.callback_query);
      }
    }
  } catch (err) {
    console.error('Polling error:', err.message);
  } finally {
    setTimeout(pollTelegram, 1500);
  }
}

function startMonitor() {
  if (monitoringTimer) clearInterval(monitoringTimer);
  monitorLoop().catch((err) => console.error('Monitor loop error:', err.message));
  monitoringTimer = setInterval(() => monitorLoop().catch((err) => console.error('Monitor loop error:', err.message)), CHECK_INTERVAL);
}

process.on('SIGINT', () => process.exit(0));
process.on('SIGTERM', () => process.exit(0));

loadServers();
loadState();

console.log('ZiVPN Multi Server Monitor Bot Safe started.');
console.log(`Check interval: ${CHECK_INTERVAL} ms`);
console.log(`Servers: ${servers.length}`);
console.log(`Message thread ID: ${configuredThreadId() || '-'}`);

if (CHAT_ID && !CHAT_ID.includes('ISI_CHAT')) {
  sendMessage(CHAT_ID, `✅ <b>ZiVPN Monitor Bot aktif</b>\nTotal server: <b>${servers.length}</b>\nMode: <b>Safe</b>\nThread: <b>${configuredThreadId() || '-'}</b>`).catch(() => null);
}

startMonitor();
pollTelegram();
