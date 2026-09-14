// Build modder/lib/__ONLINE_font.gbk (the compact-keyed glyph index used by the
// pure-GML CJK atlas renderer in gml/cjkAtlas.gml) from the GaseousMarble atlas
// index (modder/lib/__ONLINE_font.gly).
//
// Run from the repository root:
//   node modder/tools/gly_to_gbk.mjs modder/lib/__ONLINE_font.gly modder/lib/__ONLINE_font.gbk
//
// Source .gly layout (written by GaseousMarble's tools/generate_font.py):
//   header 14 B : "GLY" u8 major u8 minor u8 reserved | u16 lineHeight | i16 minGlyphTop | u32 count
//   record 14 B : u32 codepoint | u16 x | u16 y | u16 w | u16 advance | i16 rawLeft
// (records are sorted per input font, NOT globally - hence this offline index)
//
// Output .gbk layout (read by cjkAtlas.gml):
//   header 12 B : "CGA1" | u16 lineHeight | u16 reserved | u32 count
//   record 12 B : u16 key | u16 x | u16 y | u16 w | u16 advance | i16 rawLeft
//
import fs from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const iconv = require('D:/lab/modder/node_modules/iconv-lite');

const [inPath, outPath] = process.argv.slice(2);
const g = fs.readFileSync(inPath);
if (g.slice(0, 3).toString('latin1') !== 'GLY') throw new Error('bad .gly magic');
const lineHeight = g.readUInt16LE(6);
const minGlyphTop = g.readInt16LE(8);
const count = g.readUInt32LE(10);
if (g.length !== 14 + 14 * count) throw new Error(`size mismatch: ${g.length} vs ${14 + 14 * count}`);

const records = [];
let skipped = 0;
const seen = new Set();
for (let i = 0; i < count; i++) {
    const o = 14 + i * 14;
    const cp = g.readUInt32LE(o);
    const x = g.readUInt16LE(o + 4), y = g.readUInt16LE(o + 6), w = g.readUInt16LE(o + 8);
    const adv = g.readUInt16LE(o + 10), left = g.readInt16LE(o + 12);
    let key;
    if (cp < 0x80) {
        key = cp;
    } else {
        const bytes = iconv.encode(String.fromCodePoint(cp), 'gbk');
        if (bytes.length !== 2) { skipped++; continue; }   // not representable in GBK
        // iconv maps unmappable chars to '?' (0x3F) - reject those too
        if (bytes[0] === 0x3F || bytes[1] === 0x3F) { skipped++; continue; }
        const b0 = bytes[0] - 0x81, b1 = bytes[1] - 0x40;
        if (b0 < 0 || b0 > 125 || b1 < 0 || b1 > 190) { skipped++; continue; }
        key = 1000 + b0 * 191 + b1;
    }
    if (seen.has(key)) { skipped++; continue; }
    seen.add(key);
    records.push({ key, x, y, w, adv, left, cp });
}
records.sort((a, b) => a.key - b.key);

const out = Buffer.alloc(12 + records.length * 12);
out.write('CGA1', 0, 'latin1');
out.writeUInt16LE(lineHeight, 4);
out.writeUInt16LE(0, 6);
out.writeUInt32LE(records.length, 8);
records.forEach((r, i) => {
    const o = 12 + i * 12;
    out.writeUInt16LE(r.key, o);
    out.writeUInt16LE(r.x, o + 2);
    out.writeUInt16LE(r.y, o + 4);
    out.writeUInt16LE(r.w, o + 6);
    out.writeUInt16LE(r.adv, o + 8);
    out.writeInt16LE(r.left, o + 10);
});
fs.writeFileSync(outPath, out);
console.log(`${inPath} -> ${outPath}`);
console.log(`  glyphs in=${count} out=${records.length} skipped(unmappable/dup)=${skipped} lineHeight=${lineHeight} minGlyphTop=${minGlyphTop}`);
console.log(`  size=${out.length} B (12 + 12*${records.length})`);

// round-trip verification: decode a few keys back to characters
const check = ['A', 'a', '0', '\u4e2d', '\u6587', '\u4f60', '\u597d', '\uff0c', '\u3002', '\uff01'];
for (const ch of check) {
    const bytes = iconv.encode(ch, 'gbk');
    const key = bytes.length === 2 ? (1000 + (bytes[0] - 0x81) * 191 + (bytes[1] - 0x40)) : bytes[0];
    let lo = 0, hi = records.length - 1, hit = null;
    while (lo <= hi) {
        const mid = (lo + hi) >> 1;
        if (records[mid].key === key) { hit = records[mid]; break; }
        if (records[mid].key < key) lo = mid + 1; else hi = mid - 1;
    }
    console.log(`  '${ch}' key=0x${key.toString(16)} -> ${hit ? `x=${hit.x} y=${hit.y} w=${hit.w} adv=${hit.adv} left=${hit.left}` : 'MISSING'}`);
}


