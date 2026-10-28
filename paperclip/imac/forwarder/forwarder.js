'use strict';
// S12 ② 触发转发程序（代替 tailscale Serve）。失败方式和对应的防法见同目录 FAILURE-MODES.md（下称 F<n>）。
//
// 只听 iMac tailnet IPv4 的 8110 端口，只放行
//   POST /api/routine-triggers/public/<24 位小写十六进制>/fire   （HTTP/1.1，原样路径整串匹配，没有查询串）
// 转给 http://127.0.0.1:3110，只带 Authorization、Content-Type、Idempotency-Key 三个头，Host 固定写本机。
// 其余请求一律 404，正文固定。只用 node 自带模块。
//
// 正式运行（LaunchAgent）不带参数：监听地址只能是 tailnet IPv4:8110，上游只能是 127.0.0.1:3110（F25）。
// 本地自查用：--dev-listen 127.0.0.1:<端口> --dev-upstream 127.0.0.1:<端口>，两个都只接受 127.0.0.1，日志写到 stdout。

const http = require('node:http');
const net = require('node:net');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');

const LISTEN_PORT = 8110;
const UPSTREAM_HOST = '127.0.0.1';
const UPSTREAM_PORT = 3110;
const TAILSCALE = '/usr/local/bin/tailscale';
const LOG_FILE = path.join(os.homedir(), 'Library', 'Logs', 'paperclip-ops-forwarder', 'forwarder.log');

// G1、G2：publicId 是 randomBytes(12) 的小写十六进制；比 Paperclip 自己的免身份规则更窄。
const ALLOWED_PATH = /^\/api\/routine-triggers\/public\/[0-9a-f]{24}\/fire$/;
const FORWARD_HEADERS = ['authorization', 'content-type', 'idempotency-key'];

const MAX_BODY = 64 * 1024;
const MAX_UPSTREAM_BODY = 256 * 1024;
const MAX_HEADER_BYTES = 8 * 1024;
const MAX_HEADERS_COUNT = 50;
const MAX_CONNECTIONS = 16;
const HEADERS_TIMEOUT_MS = 5000;
const REQUEST_TIMEOUT_MS = 10000;
const UPSTREAM_TIMEOUT_MS = 15000; // 小于发送方的 20 秒（F18、F20）
// 等上游时客户端那边没有数据，socket 的空闲超时必须比等上游长，否则 504 还没写出去连接就被关了（自查实测过）。
const SOCKET_IDLE_MS = UPSTREAM_TIMEOUT_MS + 5000;
const ADDRESS_RECHECK_MS = 30000;
const TAILSCALE_TIMEOUT_MS = 5000;
const LOG_MAX_BYTES = 1024 * 1024;

const FIXED_BODY = {
  404: 'not found\n',
  408: 'request timeout\n',
  413: 'payload too large\n',
  502: 'bad gateway\n',
  504: 'gateway timeout\n',
};
const KNOWN_METHODS = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'CONNECT', 'TRACE']);

// ---- 日志：只写时间、方法、是否放行、状态码、耗时和固定的事件名（F17），1 MiB 轮换一次（F28）----

let logToStdout = false;

function writeLog(text) {
  const line = `${new Date().toISOString()} ${text}\n`;
  if (logToStdout) {
    process.stdout.write(line);
    return;
  }
  try {
    const st = fs.statSync(LOG_FILE, { throwIfNoEntry: false });
    if (st && st.size > LOG_MAX_BYTES) fs.renameSync(LOG_FILE, `${LOG_FILE}.1`);
    fs.appendFileSync(LOG_FILE, line, { mode: 0o600 });
  } catch {
    // 写不了日志不影响转发。
  }
}

// launchd 的 stdout/stderr（StandardOutPath、StandardErrorPath）不经过 writeLog。launchd 每次起进程时重新打开它们，
// 所以启动时超过 1 MiB 就改名成 .1，下一次启动写新文件（第 1 轮验收新风险第 6 条）。
function rotateLaunchdLogs() {
  for (const name of ['launchd.out.log', 'launchd.err.log']) {
    const file = path.join(path.dirname(LOG_FILE), name);
    try {
      const st = fs.statSync(file, { throwIfNoEntry: false });
      if (st && st.size > LOG_MAX_BYTES) fs.renameSync(file, `${file}.1`);
    } catch {
      // 转不了不影响转发。
    }
  }
}

function logRequest(method, allowed, status, startedAt, error) {
  const m = KNOWN_METHODS.has(method) ? method : 'OTHER';
  const ms = Date.now() - startedAt;
  writeLog(`method=${m} allowed=${allowed ? 'yes' : 'no'} status=${status} ms=${ms}${error ? ` error=${error}` : ''}`);
}

function exitWith(code, event) {
  writeLog(`event=exit reason=${event} code=${code}`);
  process.exit(code);
}

// ---- 地址 ----

function isTailnetIPv4(addr) {
  if (!net.isIPv4(addr)) return false;
  const [a, b] = addr.split('.').map(Number);
  return a === 100 && b >= 64 && b <= 127; // 100.64.0.0/10
}

function onLocalInterface(addr) {
  return Object.values(os.networkInterfaces())
    .flat()
    .some((i) => i && (i.family === 'IPv4' || i.family === 4) && i.address === addr);
}

// F1、F2：地址只从 `tailscale ip -4` 取；取不到或核对不过返回 null，调用方退出，没有退回别的地址的分支。
function tailscaleIPv4() {
  return new Promise((resolve) => {
    execFile(TAILSCALE, ['ip', '-4'], { timeout: TAILSCALE_TIMEOUT_MS, env: process.env }, (err, stdout) => {
      if (err) return resolve(null);
      const lines = String(stdout).split('\n').map((s) => s.trim()).filter(Boolean);
      if (lines.length !== 1 || !isTailnetIPv4(lines[0])) return resolve(null);
      resolve(lines[0]);
    });
  });
}

function parseLoopbackPort(value, flag) {
  const m = /^127\.0\.0\.1:(\d{1,5})$/.exec(value || '');
  const port = m ? Number(m[1]) : 0;
  if (!port || port > 65535) {
    process.stderr.write(`forwarder: ${flag} 只接受 127.0.0.1:<端口>\n`);
    process.exit(2);
  }
  return port;
}

function parseArgs(argv) {
  const opts = { dev: false };
  for (let i = 0; i < argv.length; i += 2) {
    const flag = argv[i];
    if (flag === '--dev-listen') opts.devListenPort = parseLoopbackPort(argv[i + 1], flag);
    else if (flag === '--dev-upstream') opts.devUpstreamPort = parseLoopbackPort(argv[i + 1], flag);
    else {
      process.stderr.write('用法: forwarder.js  或  forwarder.js --dev-listen 127.0.0.1:<端口> --dev-upstream 127.0.0.1:<端口>\n');
      process.exit(2);
    }
  }
  if ((opts.devListenPort === undefined) !== (opts.devUpstreamPort === undefined)) {
    process.stderr.write('forwarder: --dev-listen 和 --dev-upstream 要一起给\n');
    process.exit(2);
  }
  opts.dev = opts.devListenPort !== undefined;
  return opts;
}

// ---- 请求 ----

function reply(res, status) {
  const body = FIXED_BODY[status];
  res.writeHead(status, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    Connection: 'close',
  });
  res.end(body);
}

function headerCount(req, name) {
  let n = 0;
  for (let i = 0; i < req.rawHeaders.length; i += 2) {
    if (req.rawHeaders[i].toLowerCase() === name) n += 1;
  }
  return n;
}

// 返回 0 表示放行，否则返回要回的状态码。顺序：先判 404 的各项，最后判 413。
function gate(req) {
  if (req.method !== 'POST') return 404; // F6
  if (req.httpVersion !== '1.1') return 404; // F7
  if (!ALLOWED_PATH.test(req.url)) return 404; // F5：原样的请求目标，不解码、不规范化
  if (req.headers['transfer-encoding'] !== undefined) return 404; // F8、F9
  if (headerCount(req, 'content-length') !== 1) return 404;
  for (const name of FORWARD_HEADERS) {
    if (headerCount(req, name) > 1) return 404; // F12：同名头出现两次不放行
  }
  const len = Number(req.headers['content-length']);
  if (!Number.isSafeInteger(len) || len < 0) return 404;
  if (len > MAX_BODY) return 413; // F15
  return 0;
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = [];
    let total = 0;
    let settled = false;
    const settle = (v) => {
      if (!settled) {
        settled = true;
        resolve(v);
      }
    };
    req.on('data', (chunk) => {
      total += chunk.length;
      if (total > MAX_BODY) {
        settle('too_large');
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => settle(Buffer.concat(chunks, total)));
    req.on('error', () => settle('aborted'));
    req.on('close', () => settle('aborted'));
  });
}

function forward(req, body, upstreamPort) {
  return new Promise((resolve) => {
    const headers = {
      Host: `${UPSTREAM_HOST}:${UPSTREAM_PORT}`, // F13：自查时上游端口不同，Host 仍写正式值
      'Content-Length': String(body.length),
      Connection: 'close',
    };
    for (const name of FORWARD_HEADERS) {
      const v = req.headers[name];
      if (v !== undefined) headers[name] = v;
    }
    let settled = false;
    const settle = (v) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        resolve(v);
      }
    };
    const upReq = http.request(
      { host: UPSTREAM_HOST, port: upstreamPort, method: 'POST', path: req.url, headers, agent: false },
      (upRes) => {
        const chunks = [];
        let total = 0;
        upRes.on('data', (chunk) => {
          total += chunk.length;
          if (total > MAX_UPSTREAM_BODY) {
            upReq.destroy();
            settle({ status: 502, error: 'upstream_body_too_large' }); // F29
            return;
          }
          chunks.push(chunk);
        });
        upRes.on('end', () =>
          settle({
            status: upRes.statusCode,
            contentType: upRes.headers['content-type'],
            body: Buffer.concat(chunks, total),
          }),
        );
        upRes.on('error', () => settle({ status: 502, error: 'upstream_reset' }));
      },
    );
    const timer = setTimeout(() => {
      settle({ status: 504, error: 'upstream_timeout' }); // F18
      upReq.destroy();
    }, UPSTREAM_TIMEOUT_MS);
    upReq.on('error', (err) =>
      settle({ status: 502, error: err && err.code === 'ECONNREFUSED' ? 'upstream_refused' : 'upstream_error' }),
    );
    upReq.end(body);
  });
}

async function handleAllowed(req, res, startedAt, upstreamPort) {
  const body = await readBody(req);
  if (body === 'too_large') {
    reply(res, 413);
    res.on('finish', () => req.socket.destroy());
    logRequest(req.method, false, 413, startedAt);
    return;
  }
  if (body === 'aborted') {
    req.socket.destroy();
    logRequest(req.method, true, 0, startedAt, 'client_aborted');
    return;
  }
  const up = await forward(req, body, upstreamPort);
  if (up.error) {
    reply(res, up.status);
    logRequest(req.method, true, up.status, startedAt, up.error);
    return;
  }
  // 只回传状态码、Content-Type 和正文（F29）。
  const headers = { 'Content-Length': up.body.length, Connection: 'close' };
  if (up.contentType) headers['Content-Type'] = up.contentType;
  res.writeHead(up.status, headers);
  res.end(up.body);
  logRequest(req.method, true, up.status, startedAt);
}

function makeServer(upstreamPort) {
  const server = http.createServer({
    maxHeaderSize: MAX_HEADER_BYTES,
    requireHostHeader: false, // 不靠 Node 的 400，缺 Host 的请求照样走下面的判断（Host 本来就不转）
    headersTimeout: HEADERS_TIMEOUT_MS,
    requestTimeout: REQUEST_TIMEOUT_MS,
    connectionsCheckingInterval: 1000, // F14：默认 30 秒检查一次，上面两个超时会不准
  });
  server.maxConnections = MAX_CONNECTIONS; // F16
  server.maxHeadersCount = MAX_HEADERS_COUNT; // F30
  server.maxRequestsPerSocket = 1; // F11
  server.keepAliveTimeout = 1;
  server.timeout = SOCKET_IDLE_MS;

  const onRequest = (req, res, isExpectContinue) => {
    const startedAt = Date.now();
    try {
      const verdict = gate(req);
      if (verdict) {
        reply(res, verdict);
        logRequest(req.method, false, verdict, startedAt);
        return;
      }
      if (isExpectContinue) res.writeContinue(); // F10：检查都过了才回 100
      handleAllowed(req, res, startedAt, upstreamPort).catch(() => {
        if (!res.headersSent) reply(res, 502);
        logRequest(req.method, true, 502, startedAt, 'internal');
      });
    } catch {
      if (!res.headersSent) reply(res, 502); // F31
      logRequest(req.method, false, 502, startedAt, 'internal');
    }
  };

  server.on('request', (req, res) => onRequest(req, res, false));
  server.on('checkContinue', (req, res) => onRequest(req, res, true));
  server.on('checkExpectation', (req, res) => {
    reply(res, 404);
    logRequest(req.method, false, 404, Date.now());
  });
  // 解析错误（走私、非法头、头太大）和读请求超时：回固定响应并关连接（F8、F14、F30）。
  server.on('clientError', (err, socket) => {
    const status = err && err.code === 'ERR_HTTP_REQUEST_TIMEOUT' ? 408 : 404;
    if (socket.writable && !(err && err.code === 'ECONNRESET')) {
      const body = FIXED_BODY[status];
      const text = status === 408 ? 'Request Timeout' : 'Not Found';
      socket.end(
        `HTTP/1.1 ${status} ${text}\r\nContent-Type: text/plain; charset=utf-8\r\n` +
          `Content-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`,
      );
    }
    socket.destroy();
    logRequest('-', false, status, Date.now(), status === 408 ? 'client_timeout' : 'client_parse_error');
  });
  server.on('drop', () => writeLog('event=drop reason=max_connections'));
  return server;
}

// ---- 启动 ----

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  logToStdout = opts.dev;
  if (!opts.dev) {
    fs.mkdirSync(path.dirname(LOG_FILE), { recursive: true, mode: 0o700 });
    rotateLaunchdLogs();
  }

  // F23：LaunchAgent 用 env -i 起，正常不会有；万一有就不起。
  if (Object.keys(process.env).some((k) => k.startsWith('ORCA_'))) exitWith(1, 'orca_env_present');

  let listenHost;
  let listenPort;
  let upstreamPort;
  if (opts.dev) {
    listenHost = '127.0.0.1';
    listenPort = opts.devListenPort;
    upstreamPort = opts.devUpstreamPort;
  } else {
    const addr = await tailscaleIPv4();
    if (!addr) exitWith(1, 'no_tailnet_address');
    if (!onLocalInterface(addr)) exitWith(1, 'tailnet_address_not_on_interface');
    listenHost = addr;
    listenPort = LISTEN_PORT;
    upstreamPort = UPSTREAM_PORT;
  }

  const server = makeServer(upstreamPort);
  server.on('error', (err) => exitWith(1, `listen_failed_${(err && err.code) || 'unknown'}`)); // F27
  server.listen({ host: listenHost, port: listenPort, exclusive: true }, () => {
    writeLog(`event=start mode=${opts.dev ? 'dev' : 'prod'} listen=${opts.dev ? 'loopback' : 'tailnet'}:${listenPort} node=${process.version}`);
  });

  if (!opts.dev) {
    // F4：地址不在网卡上了，或者 tailscale 给出了别的地址，就退出，由 launchd 用新地址重起。
    setInterval(async () => {
      if (!onLocalInterface(listenHost)) exitWith(3, 'tailnet_address_gone');
      const now = await tailscaleIPv4();
      if (now && now !== listenHost) exitWith(3, 'tailnet_address_changed');
    }, ADDRESS_RECHECK_MS);
  }

  const stop = (sig) => {
    writeLog(`event=stop signal=${sig}`);
    server.close();
    process.exit(0);
  };
  process.on('SIGTERM', () => stop('SIGTERM'));
  process.on('SIGINT', () => stop('SIGINT'));
}

main().catch(() => exitWith(1, 'startup_error'));
