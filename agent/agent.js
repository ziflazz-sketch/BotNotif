'use strict';

const http = require('http');
const os = require('os');
const fs = require('fs');
const { execFile } = require('child_process');

const ENV_PATH = process.env.ENV_PATH || '/root/zivpn-monitor-agent/.env';

function loadEnv(path) {
  try {
    const raw = fs.readFileSync(path, 'utf8');
    raw.split(/\r?\n/).forEach((line) => {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) return;
      const idx = trimmed.indexOf('=');
      if (idx === -1) return;
      const key = trimmed.slice(0, idx).trim();
      const value = trimmed.slice(idx + 1).trim().replace(/^['"]|['"]$/g, '');
      if (!process.env[key]) process.env[key] = value;
    });
  } catch (_) {}
}

loadEnv(ENV_PATH);

const TOKEN = process.env.AGENT_TOKEN || 'change_me';
const PORT = Number(process.env.AGENT_PORT || 5890);
const SERVER_NAME = process.env.SERVER_NAME || os.hostname();

function json(res, status, data) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  res.end(JSON.stringify(data));
}

function unauthorized(res) {
  json(res, 401, { ok: false, error: 'unauthorized' });
}

function getToken(req, urlObj) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7).trim();
  if (req.headers['x-agent-token']) return String(req.headers['x-agent-token']).trim();
  return (urlObj.searchParams.get('token') || '').trim();
}

function readProcStat() {
  const line = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0].trim();
  const parts = line.split(/\s+/).slice(1).map(Number);
  const idle = parts[3] + (parts[4] || 0);
  const total = parts.reduce((a, b) => a + b, 0);
  return { idle, total };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function cpuUsagePercent() {
  try {
    const a = readProcStat();
    await sleep(350);
    const b = readProcStat();
    const idle = b.idle - a.idle;
    const total = b.total - a.total;
    if (!total) return 0;
    return Math.max(0, Math.min(100, Number(((1 - idle / total) * 100).toFixed(1))));
  } catch (_) {
    const loads = os.loadavg();
    const cores = os.cpus().length || 1;
    return Math.max(0, Math.min(100, Number(((loads[0] / cores) * 100).toFixed(1))));
  }
}

function diskUsage() {
  return new Promise((resolve) => {
    execFile('df', ['-P', '/'], { timeout: 3000 }, (err, stdout) => {
      if (err || !stdout) {
        resolve({ usedPercent: 0, total: '-', used: '-', available: '-' });
        return;
      }
      const lines = stdout.trim().split('\n');
      const row = lines[1] ? lines[1].split(/\s+/) : [];
      const usedPercent = row[4] ? Number(String(row[4]).replace('%', '')) : 0;
      resolve({
        usedPercent,
        totalKb: Number(row[1] || 0),
        usedKb: Number(row[2] || 0),
        availableKb: Number(row[3] || 0)
      });
    });
  });
}

function kbToGb(kb) {
  if (!kb) return 0;
  return Number((kb / 1024 / 1024).toFixed(2));
}

function secondsToUptime(sec) {
  sec = Math.floor(sec || 0);
  const d = Math.floor(sec / 86400);
  sec %= 86400;
  const h = Math.floor(sec / 3600);
  sec %= 3600;
  const m = Math.floor(sec / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

async function collectMetrics() {
  const cpu = await cpuUsagePercent();
  const totalMem = os.totalmem();
  const freeMem = os.freemem();
  const usedMem = totalMem - freeMem;
  const ramPercent = totalMem ? Number(((usedMem / totalMem) * 100).toFixed(1)) : 0;
  const disk = await diskUsage();
  const load = os.loadavg().map((v) => Number(v.toFixed(2)));

  return {
    cpuPercent: cpu,
    ramPercent,
    ramTotalGb: Number((totalMem / 1024 / 1024 / 1024).toFixed(2)),
    ramUsedGb: Number((usedMem / 1024 / 1024 / 1024).toFixed(2)),
    diskPercent: Number(disk.usedPercent || 0),
    diskTotalGb: kbToGb(disk.totalKb),
    diskUsedGb: kbToGb(disk.usedKb),
    load1: load[0],
    load5: load[1],
    load15: load[2],
    uptimeSeconds: Math.floor(os.uptime()),
    uptimeHuman: secondsToUptime(os.uptime()),
    checkedAt: new Date().toISOString()
  };
}

const server = http.createServer(async (req, res) => {
  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (urlObj.pathname === '/') {
    return json(res, 200, { ok: true, name: SERVER_NAME, message: 'ZiVPN Monitor Agent Safe' });
  }

  if (urlObj.pathname !== '/health') {
    return json(res, 404, { ok: false, error: 'not_found' });
  }

  if (TOKEN === 'change_me' || getToken(req, urlObj) !== TOKEN) {
    return unauthorized(res);
  }

  try {
    const metrics = await collectMetrics();
    return json(res, 200, {
      ok: true,
      name: SERVER_NAME,
      hostname: os.hostname(),
      metrics
    });
  } catch (err) {
    return json(res, 500, { ok: false, error: err.message || 'metrics_error' });
  }
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`ZiVPN Monitor Agent Safe running on port ${PORT}`);
});
