// GML function-availability checker for the shared templates.
//
// Why this exists: the modder injects GML through GM8's "execute a piece of code"
// action (asset/codeaction.ts, id 603), so the GM8 RUNNER compiles it at runtime.
// An unavailable builtin therefore does NOT fail the conversion - it aborts the
// game later with "Unknown function or script" (that is exactly how
// point_in_rectangle shipped once). Neither the GM8 side nor the GameMaker MCP
// tooling can see this class of bug, so the check lives here.
//
// Data: _workspace/reference/derived/gm81_functions.json, extracted from
// OpenGMK's GameMaker Classic function table (see modder/GML_COMPAT.md).
//
//   node modder/tools/check_gml_functions.mjs [--verbose]
//
// Reported:
//   * calls that are absent from the GM8.1 table and NOT inside a modern-engine
//     #if branch  -> hard failures on GM8.0/8.1
//   * the same, but inside a gate        -> informational
// Known-safe non-builtins (our own scripts, DLL extensions, GMS natives) are
// allowlisted below; extend the list deliberately, never by reflex.

import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '..');
const GML_DIR = path.join(ROOT, 'gml');
const TABLE = 'D:/lab/_workspace/reference/derived/gm81_functions.json';

const verbose = process.argv.includes('--verbose');

// Keywords that look like calls but are not functions.
const KEYWORDS = new Set(['if', 'while', 'for', 'repeat', 'switch', 'with', 'return', 'case', 'do',
    'until', 'else', 'var', 'globalvar', 'function', 'break', 'continue', 'exit', 'and', 'or', 'not',
    'div', 'mod', 'then', 'begin', 'end', 'default']);

// Non-builtins that legitimately appear in the templates. Deliberately narrow:
// families like draw_*/ds_*/string_* are real GM8 builtins and must be checked
// against the table, otherwise the check would be worthless.
const ALLOW = [
    /^__ONLINE_/,          // our own injected scripts (spelled in full in templates)
    /^fw_/,                // FoxWriting DLL
    /^wd_/,                // gm_windows_dialog8 DLL
    /^hbuffer_/,           // GMS-side buffer wrapper names
];

// Templates that are only ever rendered for a non-GM8 engine: their calls are
// reported informationally instead of failing the gate.
const NON_GM8_TEMPLATES = new Set(['worldCreateGMS.gml']);

if (!fs.existsSync(TABLE)) {
    console.error(`missing dataset: ${TABLE}`);
    console.error('regenerate it with:  node _workspace/tmp/cloud/extract_gm8_table.js');
    console.error('(it parses OpenGMK\'s GameMaker Classic function table; see modder/GML_COMPAT.md)');
    process.exit(2);
}
const table = JSON.parse(fs.readFileSync(TABLE, 'utf8'));
const KNOWN = new Set(table.functions);

// GM8.0 baseline (from the installed IDE's own name table) and the 71 functions
// that only exist from 8.1 on. A GM8.1-only call is fine when it is gated behind
// "#if not GM80" (the converter defines GM80 only for 8.0 targets).
const GM80_TABLE = 'D:/lab/_workspace/reference/derived/gm80_functions.json';
const GM81_ONLY_TABLE = 'D:/lab/_workspace/reference/derived/gm81_only.json';
let GM80 = null, GM81_ONLY = new Set();
if (fs.existsSync(GM80_TABLE)) GM80 = new Set(JSON.parse(fs.readFileSync(GM80_TABLE, 'utf8')).functions);
if (fs.existsSync(GM81_ONLY_TABLE)) GM81_ONLY = new Set(JSON.parse(fs.readFileSync(GM81_ONLY_TABLE, 'utf8')).functions);

// #if flags that mean "this branch is not the GM8.0/8.1 configuration".
// GMSND is set for GM8.2 sound games (gm82 sound API: sound_add_included), so
// those calls are gated too.
const MODERN_FLAGS = /STUDIO|GMS2|GM8GUI|GM82|GM82NET|GMSND|NIKAPLE/;

function gatedByModern(lines, upTo) {
    const stack = [];
    for (let i = 0; i <= upTo; i++) {
        const t = lines[i].trim();
        if (t.startsWith('#if ')) {
            const neg = t.startsWith('#if not ');
            const flag = t.replace(/^#if (not )?/, '').trim();
            stack.push({ flag, neg });
        } else if (t.startsWith('#endif')) {
            stack.pop();
        }
    }
    // Active for a modern engine when the flag matches and it is not negated, or
    // the flag is negated and it is a legacy flag.
    return stack.some(f => MODERN_FLAGS.test(f.flag) !== f.neg);
}

let hard = 0, info = 0, soft = 0, checked = 0;
const files = fs.readdirSync(GML_DIR).filter(f => f.endsWith('.gml'));
for (const file of files) {
    const lines = fs.readFileSync(path.join(GML_DIR, file), 'latin1').split(/\r?\n/);
    const engineSpecific = NON_GM8_TEMPLATES.has(file);
    lines.forEach((line, i) => {
        if (line.trim().startsWith('//')) return;
        // Strip strings first, then trailing comments (a bare word like
        // "transient()" in prose must not be read as a call).
        const code = line
            .replace(/"(?:\\.|[^"\\])*"/g, '""')
            .replace(/\/\/.*$/, '');
        for (const m of code.matchAll(/(?<![@\w.$])([a-z_][a-z_0-9]*)\s*\(/g)) {
            const name = m[1];
            if (KEYWORDS.has(name)) continue;
            if (ALLOW.some(re => re.test(name))) continue;
            checked++;
            const gated = engineSpecific || gatedByModern(lines, i);
            if (!KNOWN.has(name)) {
                if (gated) {
                    info++;
                    if (verbose) console.log(`  [gated] ${file}:${i + 1}  ${name}()`);
                } else {
                    hard++;
                    console.log(`  MISSING  ${file}:${i + 1}  ${name}()  - not in the GM8.1 builtin table`);
                }
                continue;
            }
            // Present in GM8.1: does GM8.0 have it too?
            if (GM80 && GM81_ONLY.has(name) && !GM80.has(name) && !gated) {
                soft++;
                console.log(`  GM81ONLY ${file}:${i + 1}  ${name}()  - 8.1+ only; aborts on GM8.0 targets ` +
                    `(gate it with #if not GM80 or avoid it)`);
            }
        }
    });
}

console.log(`\nchecked ${checked} call sites in ${files.length} templates; ` +
    `${hard} unavailable, ${soft} GM8.1-only, ${info} gated behind a modern-engine flag`);


if (hard) {
    console.log('Unavailable calls abort the game at runtime on GM8.0/8.1 ("Unknown function or script").');
    console.log('Either implement them in a pack, or move the call under the right #if branch.');
}
process.exit(hard ? 1 : 0);
