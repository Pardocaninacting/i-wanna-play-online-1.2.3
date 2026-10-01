/* ============================================================
   Land mask for the lobby globe → assets/img/land-mask.png
   ------------------------------------------------------------
   Rasterises Natural Earth's 1:50m land polygons (public domain,
   https://www.naturalearthdata.com/) into an equirectangular
   1-bit PNG, white = land. globe.js samples it to place the dots.

   Usage: node _dev/make-land-mask.cjs [width] [local ne_50m_land.geojson]
   ============================================================ */

const https = require("https");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const SOURCE = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_land.geojson";
const OUT = path.resolve(__dirname, "..", "assets", "img", "land-mask.png");
const WIDTH = Number(process.argv[2]) || 960;
const HEIGHT = WIDTH / 2;
const LOCAL_SOURCE = process.argv[3];

function download(url) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: 30000 }, (res) => {
      if (res.statusCode !== 200) {
        res.resume();
        reject(new Error("HTTP " + res.statusCode + " for " + url));
        return;
      }
      const chunks = [];
      res.on("data", (c) => chunks.push(c));
      res.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    });
    req.on("timeout", () => req.destroy(new Error("download timed out; pass a local copy as the second argument")));
    req.on("error", reject);
  });
}

/** Every ring of every land polygon, as [lon, lat] pairs. */
function landRings(geojson) {
  const rings = [];
  for (const feature of geojson.features) {
    const g = feature.geometry;
    if (!g) continue;
    const polygons = g.type === "Polygon" ? [g.coordinates] : g.type === "MultiPolygon" ? g.coordinates : [];
    for (const polygon of polygons) for (const ring of polygon) rings.push(ring);
  }
  return rings;
}

/** Even-odd scanline fill sampled at pixel centres (land polygons never overlap). */
function rasterize(rings) {
  const mask = new Uint8Array(WIDTH * HEIGHT);
  for (let y = 0; y < HEIGHT; y += 1) {
    const lat = 90 - ((y + 0.5) * 180) / HEIGHT;
    const crossings = [];
    for (const ring of rings) {
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i, i += 1) {
        const [x1, y1] = ring[j];
        const [x2, y2] = ring[i];
        if ((y1 <= lat) !== (y2 <= lat)) crossings.push(x1 + ((lat - y1) * (x2 - x1)) / (y2 - y1));
      }
    }
    crossings.sort((a, b) => a - b);
    for (let k = 0; k + 1 < crossings.length; k += 2) {
      const from = Math.max(0, Math.ceil(((crossings[k] + 180) / 360) * WIDTH - 0.5));
      const to = Math.min(WIDTH - 1, Math.floor(((crossings[k + 1] + 180) / 360) * WIDTH - 0.5));
      for (let x = from; x <= to; x += 1) mask[y * WIDTH + x] = 1;
    }
  }
  return mask;
}

const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** 1-bit greyscale PNG, every scanline with filter 0. */
function encodePng(mask) {
  const rowBytes = Math.ceil(WIDTH / 8);
  const raw = Buffer.alloc((rowBytes + 1) * HEIGHT);
  for (let y = 0; y < HEIGHT; y += 1) {
    const row = y * (rowBytes + 1) + 1;
    for (let x = 0; x < WIDTH; x += 1) {
      if (mask[y * WIDTH + x]) raw[row + (x >> 3)] |= 0x80 >> (x & 7);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(WIDTH, 0);
  header.writeUInt32BE(HEIGHT, 4);
  header[8] = 1; // bit depth; colour type, compression, filter and interlace stay 0
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk("IHDR", header),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

(async () => {
  const text = LOCAL_SOURCE ? fs.readFileSync(LOCAL_SOURCE, "utf8") : await download(SOURCE);
  const mask = rasterize(landRings(JSON.parse(text)));
  const png = encodePng(mask);
  fs.writeFileSync(OUT, png);
  const land = mask.reduce((sum, v) => sum + v, 0);
  console.log(`${OUT}: ${WIDTH}x${HEIGHT}, ${((land / mask.length) * 100).toFixed(1)}% land pixels, ${png.length} bytes`);
})().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
