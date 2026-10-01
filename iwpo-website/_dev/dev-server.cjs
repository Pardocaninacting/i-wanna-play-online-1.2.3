/* ============================================================
   IWPO 站点 — 本地开发服务器（仅本地测试用，不随站点部署）
   ------------------------------------------------------------
   站点本身是纯静态的，生产环境靠 nginx 把若干路径代理到后端服务。
   本地没有那些服务，所以这个零依赖 Node 服务把同一批 URL
   按前端期望的契约补齐；数据取自可选的 _dev/data/（不入库，缺失时返回空列表）：

     POST /version                     → { success, version }      ← data/version.txt
     GET  /ratings/api                 → { ratings: [...] }        ← data/ratings/*.json
     GET  /ratings/api/:gameID         → 同上，按 gameID 过滤
     GET  /skins                       → { success, skins: [...] } ← data/skins/*
     GET  /skins/<hash>/file/<s>.png   → 条带 PNG
     GET  /skins/<hash>.zip            → 打包下载（store 模式 zip）
     POST /skins/upload                → 本地禁用
     POST /getGames                    → 示例房间（IWPO_LIVE=1 时改用线上真实数据）
     其余路径                          → 站点静态文件

   用法：
     node _dev/dev-server.cjs            # http://127.0.0.1:8199/
     PORT=8300 node _dev/dev-server.cjs
     IWPO_LIVE=1 node _dev/dev-server.cjs   # /getGames 走公网真实数据
   ============================================================ */

const http = require("http");
const https = require("https");
const fs = require("fs");
const path = require("path");

const SITE = path.resolve(__dirname, "..");
const DATA = path.join(__dirname, "data");
const PORT = Number(process.env.PORT || 8199);
const LIVE = process.env.IWPO_LIVE === "1";

const MIME = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".svg": "image/svg+xml",
  ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8",
  ".ico": "image/x-icon",
  ".zip": "application/zip",
};

/* ---------- helpers ---------- */
function sendJSON(res, obj, status = 200) {
  const body = Buffer.from(JSON.stringify(obj));
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" });
  res.end(body);
}

function sendFile(res, file, download) {
  fs.readFile(file, (err, buf) => {
    if (err) { res.writeHead(404); res.end("not found"); return; }
    const head = { "Content-Type": MIME[path.extname(file).toLowerCase()] || "application/octet-stream" };
    if (download) head["Content-Disposition"] = 'attachment; filename="' + path.basename(file) + '"';
    res.writeHead(200, head);
    res.end(buf);
  });
}

/** 极简 ini 读取：只需要 [section] key = value */
function readIni(file) {
  const out = {};
  let section = "";
  for (const raw of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith(";") || line.startsWith("#")) continue;
    const sec = line.match(/^\[(.+)\]$/);
    if (sec) { section = sec[1].trim(); out[section] = out[section] || {}; continue; }
    const kv = line.match(/^([^=]+)=(.+)$/);
    if (kv && section) out[section][kv[1].trim().toLowerCase()] = kv[2].trim();
  }
  return out;
}

/* ---------- skins ---------- */
const SKIN_DIR = path.join(DATA, "skins");
let skinIndex = null;

function loadSkins() {
  if (skinIndex) return skinIndex;
  const list = [];
  if (!fs.existsSync(SKIN_DIR)) return (skinIndex = list);
  for (const hash of fs.readdirSync(SKIN_DIR)) {
    const dir = path.join(SKIN_DIR, hash);
    if (!fs.statSync(dir).isDirectory()) continue;
    const iniPath = path.join(dir, "info.ini");
    let ini = {};
    try { ini = readIni(iniPath); } catch { /* 无 info.ini 的包仍然列出 */ }
    const meta = ini.skin || {};
    const states = {};
    for (const [key, val] of Object.entries(ini)) {
      if (key === "skin") continue;
      if (!fs.existsSync(path.join(dir, key + ".png"))) continue;
      states[key] = {
        frames: Number(val.frames) || 1,
        framewidth: Number(val.framewidth) || 32,
        originx: Number(val.originx) || 17,
        originy: Number(val.originy) || 23,
      };
    }
    list.push({
      hash,
      name: meta.name || hash.slice(0, 8),
      maker: meta.maker || "",
      source: meta.source || "",
      states,
    });
  }
  list.sort((a, b) => a.name.localeCompare(b.name, "zh"));
  return (skinIndex = list);
}

/* ---------- zip（store 模式，够本地下载用） ---------- */
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

/** @param {{name:string, data:Buffer}[]} entries */
function makeZip(entries) {
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name, "utf8");
    const crc = crc32(e.data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);            // version needed
    local.writeUInt16LE(0, 6);             // flags
    local.writeUInt16LE(0, 8);             // store
    local.writeUInt16LE(0, 10);            // time
    local.writeUInt16LE(0x21, 12);         // date (1980-01-01)
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(e.data.length, 18);
    local.writeUInt32LE(e.data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, e.data);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0, 8);
    central.writeUInt16LE(0, 10);
    central.writeUInt16LE(0, 12);
    central.writeUInt16LE(0x21, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(e.data.length, 20);
    central.writeUInt32LE(e.data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(0, 42 - 4);      // relative offset placeholder (set below)
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += local.length + name.length + e.data.length;
  }
  const centralBuf = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuf.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, centralBuf, end]);
}

function skinZip(hash) {
  const dir = path.join(SKIN_DIR, hash);
  if (!fs.existsSync(dir)) return null;
  const entries = fs.readdirSync(dir)
    .filter((f) => !f.startsWith("."))
    .map((f) => ({ name: f, data: fs.readFileSync(path.join(dir, f)) }));
  return makeZip(entries);
}

/* ---------- ratings ---------- */
let ratingsCache = null;
function loadRatings() {
  if (ratingsCache) return ratingsCache;
  const dir = path.join(DATA, "ratings");
  const out = [];
  if (fs.existsSync(dir)) {
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith(".json")) continue;
      try {
        const parsed = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8"));
        if (Array.isArray(parsed)) out.push(...parsed);
      } catch { /* 跳过坏文件 */ }
    }
  }
  return (ratingsCache = out);
}

/* ---------- 示例房间（本地没有游戏服务器） ---------- */
const SAMPLE_GAMES = [
  { name: "I wanna be the Guy", players: 3, hasPassword: false },
  { name: "Not Another Needle Game", players: 2, hasPassword: false },
  { name: "", players: 2, hasPassword: true },
  { name: "I wanna be the Boshy", players: 1, hasPassword: false },
];

function liveGames() {
  return new Promise((resolve, reject) => {
    const req = https.request(
      "https://iwannaplay.online/getGames",
      { method: "POST", headers: { "Content-Length": 0 }, timeout: 8000 },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); }
          catch (e) { reject(e); }
        });
      }
    );
    req.on("error", reject);
    req.on("timeout", () => req.destroy(new Error("timeout")));
    req.end();
  });
}

/* ---------- static ---------- */
function serveStatic(req, res, urlPath) {
  let rel = decodeURIComponent(urlPath.split("?")[0]);
  if (rel === "/") rel = "/index.html";
  const file = path.join(SITE, rel);
  if (file !== SITE && !file.startsWith(SITE + path.sep)) { res.writeHead(403); res.end("forbidden"); return; }
  fs.stat(file, (err, st) => {
    if (!err && st.isFile()) { sendFile(res, file); return; }
    if (!err && st.isDirectory()) {
      const idx = path.join(file, "index.html");
      if (fs.existsSync(idx)) { sendFile(res, idx); return; }
    }
    // 无扩展名的路径按 .html 处理（与 nginx 行为一致）
    if (!path.extname(file) && fs.existsSync(file + ".html")) { sendFile(res, file + ".html"); return; }
    res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
    res.end("<h1>404</h1><p>本地开发服务器：没有这个路径。</p>");
  });
}

/* ---------- router ---------- */
const server = http.createServer(async (req, res) => {
  const url = req.url.split("?")[0];
  const log = (what) => console.log(`${req.method} ${req.url}  → ${what}`);

  // version
  if (url === "/version" && req.method === "POST") {
    let version = "1.2.3_beta_6";
    try { version = fs.readFileSync(path.join(DATA, "version.txt"), "utf8").trim(); } catch { /* 默认值 */ }
    log("version " + version);
    return sendJSON(res, { success: true, version });
  }

  // ratings
  if (url === "/ratings/api" && req.method === "GET") {
    const ratings = loadRatings();
    log(ratings.length + " 条评分");
    return sendJSON(res, { ratings });
  }
  const rt = url.match(/^\/ratings\/api\/(.+)$/);
  if (rt && req.method === "GET") {
    const id = decodeURIComponent(rt[1]);
    const ratings = loadRatings().filter((r) => String(r.gameID) === id);
    log(ratings.length + " 条评分（" + id + "）");
    return sendJSON(res, { ratings });
  }

  // skins
  if (url === "/skins" && req.method === "GET") {
    const skins = loadSkins();
    log(skins.length + " 套皮肤");
    return sendJSON(res, { success: true, count: skins.length, skins });
  }
  const sf = url.match(/^\/skins\/([0-9a-f]{32})\/file\/([a-z]+)\.png$/);
  if (sf && req.method === "GET") {
    log("皮肤帧 " + sf[2]);
    return sendFile(res, path.join(SKIN_DIR, sf[1], sf[2] + ".png"));
  }
  const sz = url.match(/^\/skins\/([0-9a-f]{32})\.zip$/);
  if (sz && req.method === "GET") {
    const zip = skinZip(sz[1]);
    if (!zip) { res.writeHead(404); res.end("no such skin"); return; }
    log("皮肤包 zip " + (zip.length / 1024).toFixed(0) + "KB");
    res.writeHead(200, { "Content-Type": "application/zip", "Content-Disposition": 'attachment; filename="' + sz[1] + '.zip"' });
    return res.end(zip);
  }
  if (url === "/skins/upload" && req.method === "POST") {
    log("上传（本地禁用）");
    return sendJSON(res, { success: false, error: "本地开发模式未启用上传" }, 501);
  }

  // games
  if (url === "/getGames" && req.method === "POST") {
    if (LIVE) {
      try {
        const data = await liveGames();
        log("线上房间 " + (data.games || []).length);
        return sendJSON(res, data);
      } catch (e) {
        log("线上失败，回退示例数据（" + e.message + "）");
      }
    } else {
      log("示例房间 " + SAMPLE_GAMES.length);
    }
    return sendJSON(res, { success: true, games: SAMPLE_GAMES });
  }

  // 安装包：生产环境由 nginx 提供 /files/，本地没有这些大文件
  if (url.startsWith("/files/")) {
    log("安装包（本地未提供）");
    res.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
    return res.end("本地开发服务器未包含安装包。生产环境由 nginx 提供 /files/ 下载目录。\n");
  }

  return serveStatic(req, res, url);
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`IWPO 本地开发服务器  http://127.0.0.1:${PORT}/`);
  console.log(`  站点目录 ${SITE}`);
  console.log(`  数据目录 ${DATA}${LIVE ? "   /getGames 使用线上真实数据" : ""}`);
  console.log("  可用页面：/ (大厅) · /download.html · /skins.html · /ratings.html · /about.html");
});
