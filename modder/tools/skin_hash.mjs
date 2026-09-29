// skin_hash.mjs - compute the package hash of skin folders, for seeding the
// server skin library (PROPOSAL_skin_upload.md, plan A).
//
// The rule is the game's own (@skin_hash_dir in gml/md5.gml): md5 over
// (file name + 0x00 + file bytes) for every regular file directly inside the
// package folder, names sorted by byte order. Subdirectories are skipped.
//
//   node modder/tools/skin_hash.mjs <skinsDir>            list "hash  folder"
//   node modder/tools/skin_hash.mjs <skinsDir> --rename   rename folders to their hash
//
// After --rename, copy the folders into the server's data/skins/ to seed the
// library. The hash is content-addressed, so a folder that is already named by
// its hash is left alone.

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const dir = process.argv[2];
if (!dir || !fs.existsSync(dir)) {
  console.error('usage: node modder/tools/skin_hash.mjs <skinsDir> [--rename]');
  process.exit(2);
}
const doRename = process.argv.includes('--rename');

// byte-order sort, byte by byte (mirrors the GML insertion sort; no locale)
const byteCmp = (a, b) => {
  const ba = Buffer.from(a, 'latin1'), bb = Buffer.from(b, 'latin1');
  const n = Math.min(ba.length, bb.length);
  for (let i = 0; i < n; i++) if (ba[i] !== bb[i]) return ba[i] - bb[i];
  return ba.length - bb.length;
};

const hashOf = (folder) => {
  const names = fs.readdirSync(folder).filter(f => fs.statSync(path.join(folder, f)).isFile());
  if (names.length === 0) return null;
  names.sort(byteCmp);
  const h = crypto.createHash('md5');
  for (const name of names) {
    h.update(Buffer.from(name, 'latin1'));
    h.update(Buffer.from([0]));
    h.update(fs.readFileSync(path.join(folder, name)));
  }
  return h.digest('hex');
};

for (const entry of fs.readdirSync(dir).sort()) {
  const folder = path.join(dir, entry);
  if (!fs.statSync(folder).isDirectory()) continue;
  const hex = hashOf(folder);
  if (!hex) { console.log(`(empty)  ${entry}`); continue; }
  console.log(`${hex}  ${entry}`);
  if (doRename && entry !== hex) {
    const target = path.join(dir, hex);
    if (fs.existsSync(target)) { console.log(`  ! target exists, skipped: ${entry}`); continue; }
    fs.renameSync(folder, target);
  }
}
