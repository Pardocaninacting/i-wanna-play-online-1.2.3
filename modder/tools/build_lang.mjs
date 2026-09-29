// build_lang.mjs - keeps lang/*.ini hash lines in sync with the English
// fallbacks in the GML, and scaffolds missing keys.
//
// The registry (gml/langLib.gml) maps LK constants to ini keys; every call
// site carries its English fallback as @L(global.__ONLINE_LK_*, "text"). This
// tool joins the two, so a language file can record which source text each
// translation was written against:
//
//   [menu.row.save]
//   hash = a1b2c3      <- md5(fallback)[0..6], regenerated here
//   text = 存档
//
// A hash mismatch at gate time means the English text moved under the
// translation (stale translation warning, not an error - the old text still
// shows until retranslated).
//
//   node modder/tools/build_lang.mjs          rewrite hash lines in place
//   node modder/tools/build_lang.mjs --check  exit 1 on any mismatch/missing
//
// Deliberately dependency-free (crypto is built in).

import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const GML_DIR = path.join(ROOT, 'gml');
const LANG_DIR = path.join(ROOT, 'lang');
const checkOnly = process.argv.includes('--check');

// 1. registry: LK constant -> ini key
const langLib = fs.readFileSync(path.join(GML_DIR, 'langLib.gml'), 'latin1');
const lkConst = new Map();  // __ONLINE_LK_X -> index
for (const m of langLib.matchAll(/__ONLINE_LK_([A-Z_0-9]+) = (\d+);/g)) lkConst.set(m[1], +m[2]);
const keyByIndex = new Map();
for (const m of langLib.matchAll(/__ONLINE_LangKey\[(\d+)\] = "([^"]+)";/g)) keyByIndex.set(+m[1], m[2]);

// 2. fallbacks: ini key -> Set of English texts (a key may legitimately have
//    per-site variants, e.g. a STUDIO prompt vs a wd title)
const fallbacks = new Map();
const callRe = /@L\(global\.__ONLINE_LK_([A-Z_0-9]+),\s*"((?:[^"\\]|\\.)*)"\)/g;
for (const f of fs.readdirSync(GML_DIR).filter(f => f.endsWith('.gml'))) {
  const src = fs.readFileSync(path.join(GML_DIR, f), 'latin1');
  for (const m of src.matchAll(callRe)) {
    const idx = lkConst.get(m[1]);
    if (idx === undefined) continue;
    const key = keyByIndex.get(idx);
    if (!key) continue;
    if (!fallbacks.has(key)) fallbacks.set(key, new Set());
    fallbacks.get(key).add(m[2]);
  }
}

const hashOf = (s) => crypto.createHash('md5').update(s, 'latin1').digest('hex').slice(0, 6);

// 3. per-file pass
const problems = [];
for (const f of fs.readdirSync(LANG_DIR).filter(f => f.endsWith('.ini'))) {
  const p = path.join(LANG_DIR, f);
  const lines = fs.readFileSync(p, 'utf8').split('\n');
  const out = [];
  let cur = null;           // current [section]
  let body = [];            // buffered lines of the current section
  let sawHash = false;
  let hasText = false;
  const flush = () => {
    if (cur && cur !== 'meta') {
      const fb = fallbacks.get(cur);
      if (!fb) {
        problems.push(`${f}: [${cur}] is not a registered key`);
        out.push(...body);
      } else {
        const want = hashOf([...fb].sort()[0]);
        if (!hasText) problems.push(`${f}: [${cur}] has no text= line`);
        if (!sawHash) problems.push(`${f}: [${cur}] missing hash (want ${want})`);
        else if (sawHash !== want) problems.push(`${f}: [${cur}] stale translation (file ${sawHash}, source ${want})`);
        if (checkOnly) out.push(...body);
        else out.push(`hash = ${want}`, ...body.filter(l => !/^hash\s*=/.test(l.trim())));
      }
    } else {
      out.push(...body);
    }
    body = [];
    cur = null; sawHash = false; hasText = false;
  };
  for (const line of lines) {
    const sec = /^\[([^\]]+)\]\s*$/.exec(line);
    if (sec) {
      flush();
      cur = sec[1];
      out.push(line);
      continue;
    }
    const hv = /^hash\s*=\s*(\w+)\s*$/.exec(line.trim());
    if (hv && cur && cur !== 'meta') { sawHash = hv[1]; continue; }
    if (/^text\s*=/.test(line.trim())) hasText = true;
    body.push(line);
  }
  flush();
  // scaffold: registered keys with a fallback but no section yet
  if (!checkOnly) {
    const present = new Set([...out.join('\n').matchAll(/^\[([^\]]+)\]/gm)].map(m => m[1]));
    for (const [key, fb] of [...fallbacks.entries()].sort()) {
      if (present.has(key) || key === 'meta') continue;
      out.push('', `[${key}]`, `hash = ${hashOf([...fb].sort()[0])}`, `text = ${[...fb].sort()[0]}   ; TODO translate`);
      problems.push(`${f}: [${key}] scaffolded (needs translation)`);
    }
  }
  if (!checkOnly) fs.writeFileSync(p, out.join('\n'), 'utf8');
}

for (const p of problems) console.log(p);
if (checkOnly && problems.length) process.exit(1);
if (!checkOnly) console.log(`hashes refreshed (${problems.length} note(s))`);
