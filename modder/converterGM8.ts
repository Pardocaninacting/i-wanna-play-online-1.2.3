import fs from "fs-extra"
import path from "path"
import zlib from "zlib"
import { SmartBuffer } from "smart-buffer"
import { PESection, WindowsIcon, Icon } from "./icon"
import { GameConfig, GameData, GameVersion } from "./gamedata"
import { GM80 } from "./gamedata/gm80"
import { Antidec } from "./gamedata/antidec"
import { Unpack as UpxUnpack } from "./upx"
import { Settings } from "./settings"
import { Asset } from "./asset"
import { Extension } from "./asset/extension"
import { Trigger } from "./asset/trigger"
import { Constant } from "./asset/constant"
import { Sound } from "./asset/sound"
import { Sprite } from "./asset/sprite"
import { Background } from "./asset/background"
import { Path } from "./asset/path"
import { Script } from "./asset/script"
import { Font } from "./asset/font"
import { Timeline } from "./asset/timeline"
import { GMObject } from "./asset/object"
import { Room } from "./asset/room"
import { IncludedFile } from "./asset/includedfile"
import { GMLCode } from "./getGMLCode"
import { Utils, Ports } from "./utils"
import { CustomSlotConfig, formatSyncIniSection, mergeSyncIntoIni } from "./customSlot"
import iconv from "iconv-lite"

const HTTP_DLL_FILENAME: string = "http_dll_2_3.dll";
const HTTP_DLL_X86_PROJECT_DIR: string = path.join(__dirname, "native", "http_dll_2_3_x86");

// P2: architecture-independent PE export-table walk. Returns whether the DLL
// binary at dllPath exports funcName. The runtime external_define on a missing
// export is a hard startup error (GM8), so the converter verifies the export
// at build time instead of hoping the marker/shipped DLL line up.
export const dllExportsFunction = function (dllPath: string, funcName: string): boolean {
	try {
		const data: Buffer = fs.readFileSync(dllPath);
		if (data.length < 0x40 || data[0] !== 0x4D || data[1] !== 0x5A) return false;
		const peOff = data.readUInt32LE(0x3C);
		if (peOff <= 0 || peOff + 24 > data.length || data.toString("ascii", peOff, peOff + 2) !== "PE") return false;
		const numSections = data.readUInt16LE(peOff + 6);
		const optSize = data.readUInt16LE(peOff + 20);
		const optOff = peOff + 24;
		if (optOff + optSize > data.length) return false;
		// 16-bit optional-header magic: 0x10B = PE32, 0x20B = PE32+; the low
		// byte alone is 0x0B for both.
		const pe32Plus = data.readUInt16LE(optOff) === 0x20B;
		const dataDirOff = optOff + (pe32Plus ? 112 : 96);
		if (dataDirOff + 4 > data.length) return false;
		const exportRva = data.readUInt32LE(dataDirOff);
		if (exportRva === 0) return false;
		const secOff = optOff + optSize;
		let va = 0, raw = 0;
		for (let s = 0; s < numSections; s++) {
			const sh = secOff + s * 40;
			if (sh + 40 > data.length) return false;
			const vsize = data.readUInt32LE(sh + 8);
			const vaddr = data.readUInt32LE(sh + 12);
			const rawsize = data.readUInt32LE(sh + 16);
			const rawptr = data.readUInt32LE(sh + 20);
			if (exportRva >= vaddr && exportRva < vaddr + Math.max(vsize, rawsize)) {
				va = vaddr;
				raw = rawptr;
				break;
			}
		}
		if (raw === 0) return false;
		const expOff = exportRva - va + raw;
		if (expOff + 40 > data.length) return false;
		const numNames = data.readUInt32LE(expOff + 24);
		const addrNames = data.readUInt32LE(expOff + 32);
		if (numNames <= 0 || numNames > 65536) return false;
		let namesOff = addrNames - va + raw;
		for (let n = 0; n < numNames; n++) {
			if (namesOff + 4 > data.length) return false;
			const nameRva = data.readUInt32LE(namesOff);
			namesOff += 4;
			const noff = nameRva - va + raw;
			if (noff <= 0 || noff >= data.length) continue;
			let end = noff;
			while (end < data.length && data[end] !== 0 && end - noff < 256) end++;
			if (end - noff !== funcName.length) continue;
			if (data.toString("ascii", noff, end) === funcName) return true;
		}
		return false;
	} catch {
		return false;
	}
};

const EnsureX86HttpDllBuilt = async function(): Promise<void> {
	const outputDll: string = path.join(__dirname, "lib", HTTP_DLL_FILENAME);
	const sourceFile: string = path.join(__dirname, "native", "http_dll_2_3_x64", "Exports.cs");
	let needsBuild: boolean = !await fs.exists(outputDll);
	if(!needsBuild && await fs.exists(sourceFile)){
		const [dllStat, srcStat] = await Promise.all([fs.stat(outputDll), fs.stat(sourceFile)]);
		needsBuild = srcStat.mtimeMs > dllStat.mtimeMs;
	}
	const projectFile: string = path.join(HTTP_DLL_X86_PROJECT_DIR, "HttpDll23X86.csproj");
	if(!needsBuild)
		return;
	if(!await fs.exists(projectFile))
		throw new Error(`Cannot find ${HTTP_DLL_FILENAME} or its NativeAOT project. Place the pre-built DLL in lib/ or ensure the NativeAOT project exists in native/http_dll_2_3_x86/`);
	console.log("HTTP DLL: building...");
	try{
		await Utils.exec("dotnet publish -c Release", HTTP_DLL_X86_PROJECT_DIR);
	}catch(e){
		throw new Error(`Failed to build ${HTTP_DLL_FILENAME}. Ensure .NET 10+ SDK (with NativeAOT workload) and VS2022 Build Tools are installed. Error: ${e}`);
	}
	const publishedDll: string = path.join(HTTP_DLL_X86_PROJECT_DIR, "bin", "Release", "net10.0", "win-x86", "publish", HTTP_DLL_FILENAME);
	if(!await fs.exists(publishedDll))
		throw new Error(`NativeAOT publish succeeded but ${HTTP_DLL_FILENAME} was not found at expected path: ${publishedDll}`);
	await fs.copyFile(publishedDll, outputDll);
	console.log("HTTP DLL: ready");
}

const asUint8Array = function(buffer: Buffer): Uint8Array {
	return buffer as unknown as Uint8Array;
}

const ascii = function(value: string): Uint8Array {
	return asUint8Array(Buffer.from(value, 'ascii'));
}

const bytes = function(value: Array<number>): Uint8Array {
	return asUint8Array(Buffer.from(value));
}

const inflateBuffer = function(buffer: Buffer): Buffer {
	return zlib.inflateSync(asUint8Array(buffer));
}

const deflateBuffer = function(buffer: Buffer): Buffer {
	return zlib.deflateSync(asUint8Array(buffer));
}

const concatBuffers = function(buffers: Array<Buffer>): Buffer {
	return Buffer.concat(buffers as unknown as Array<Uint8Array>);
}

type TickEventName = "step" | "endstep";

const withGMLObject = function(objectName: Buffer, code: Buffer): Buffer {
	return concatBuffers([
		Buffer.from(`with(${objectName.toString('ascii')}){\r\n`, 'ascii'),
		code,
		Buffer.from("\r\n}\r\n", 'ascii'),
	]);
}

const localizeExitForWith = function(code: Buffer): Buffer {
	const source: string = code.toString('latin1');
	if(!/\bexit\s*;/.test(source)) return code;
	return Buffer.from([
		"for(__ONLINE_iwpo_scheduler_exit = 0; __ONLINE_iwpo_scheduler_exit < 1; __ONLINE_iwpo_scheduler_exit += 1){",
		source.replace(/\bexit\s*;/g, "break;"),
		"}",
	].join("\r\n"), 'latin1');
}

// Splits a rendered GML blob into named sections introduced by marker lines of
// the form `///// <kind> <name>` ("script" for md5.gml/skinLib.gml, "mode" for
// playerDrawInject.gml). Content before the first marker is dropped. The input
// must already be rendered through GMLCode.getGML, so section names carry the
// final __ONLINE_ prefix (the source marker `@` has been rewritten by then).
const splitMarkedSections = function(rendered: Buffer, kind: string): Array<{name: string, code: Buffer}> {
	const lines: Array<string> = rendered.toString('latin1').split(/\r\n|\r|\n/g);
	const marker: RegExp = new RegExp(`^/////\\s+${kind}\\s+([A-Za-z0-9_]+)\\s*$`);
	const sections: Array<{name: string, code: Buffer}> = [];
	let currentName: string = null;
	let currentLines: Array<string> = [];
	const flush = function(): void {
		if(currentName === null)
			return;
		// Trim blank padding lines; keep inner formatting intact.
		while(currentLines.length > 0 && currentLines[0].trim() === "") currentLines.shift();
		while(currentLines.length > 0 && currentLines[currentLines.length-1].trim() === "") currentLines.pop();
		sections.push({name: currentName, code: Buffer.from(currentLines.join("\r\n"), 'latin1')});
		currentName = null;
		currentLines = [];
	}
	for(const line of lines){
		const match: RegExpExecArray = marker.exec(line.trim());
		if(match){
			flush();
			currentName = match[1];
			currentLines = [];
		}else if(currentName !== null){
			currentLines.push(line);
		}
	}
	flush();
	return sections;
}

// T1: split a rendered script-pack GML (md5.gml / skinLib.gml) into one entry
// per `///// script <name>` section; each entry becomes a standalone GM8 script
// asset. Exported for conversion-time verification harnesses.
export const splitMarkedScripts = function(rendered: Buffer): Array<{name: string, code: Buffer}> {
	return splitMarkedSections(rendered, "script");
}

// Renders a skin-system GML file through the standard pipeline. These files are
// delivered as a parallel GML pack; a missing file must surface as a clear
// conversion-time error, not a raw ENOENT.
const renderSkinGml = async function(filename: string): Promise<Buffer> {
	if(!await fs.exists(path.join(__dirname, "gml", `${filename}.gml`)))
		throw new Error(`Skin system GML missing: gml/${filename}.gml. The skin feature requires md5.gml, skinLib.gml and playerDrawInject.gml in the gml/ folder; convert with iwpo.no_skins=true to build without skin support.`);
	return GMLCode.getGML(filename);
}

// Animation states indexed 0-6, the shared contract with the skin GML
// (global.__ONLINE_mapSpr[st] / global.__ONLINE_mapFrames[st]).
const SKIN_MAP_STATES: Array<string> = ["idle", "run", "jump", "fall", "slide", "bow", "bullet"];
// Default sprite-name candidates per state (matched case-insensitively).
// Per-game override: define iwpo.skins.map.<state>=<spriteName>.
const SKIN_SPRITE_CANDIDATES: {[state: string]: Array<string>} = {
	idle: ["playeridle", "sprplayeridle", "player_idle", "spr_player_idle", "splayeridle"],
	run: ["playerrunning", "playerrun", "sprplayerrun", "sprplayerrunning", "player_running", "splayerrunning", "splayerrun"],
	jump: ["playerjump", "sprplayerjump", "player_jump", "splayerjump"],
	fall: ["playerfall", "sprplayerfall", "player_fall", "splayerfall"],
	slide: ["playersliding", "playerslide", "sprplayersliding", "sprplayerslide", "playerclimb", "sprplayerclimb", "splayersliding", "splayerslide"],
	bow: ["playerbow", "sprplayerbow", "sbow"],
	bullet: ["sprbullet", "playerbullet", "sprplayerbullet", "bullet", "sbullet"],
};

// T3: resolve the game-sprite -> animation-state map and emit the world-Create
// assignment block. Unmatched states are written as -1/0 (the GML-side default),
// keeping the injected block fully deterministic. Sprite indices are compile-time
// constants: the position inside the game's sprite table. The emitted code must
// spell __ONLINE_ names in full — it is injected verbatim via addCreateCode and
// never passes through the @ -> __ONLINE_ substitution. Exported for
// conversion-time verification harnesses.
export const buildSkinSpriteMap = function(sprites: Array<Sprite>, defines: Map<string, string>): string {
	const findSprite = function(name: string): number {
		const target: string = name.toLowerCase();
		for(let i: number = 0; i < sprites.length; ++i)
			if(sprites[i] && sprites[i].name.toString('ascii').toLowerCase() === target)
				return i;
		return -1;
	}
	const lines: Array<string> = ["// [iwpo] skin sprite-state map (generated at convert time)"];
	console.log("Skin sprite map:");
	for(let st: number = 0; st < SKIN_MAP_STATES.length; ++st){
		const state: string = SKIN_MAP_STATES[st];
		const defineKey: string = `iwpo.skins.map.${state}`;
		let spriteIndex: number = -1;
		let source: string = "";
		if(defines.has(defineKey)){
			const defineValue: string = (defines.get(defineKey) as string).trim();
			if(defineValue !== ""){
				spriteIndex = findSprite(defineValue);
				if(spriteIndex >= 0)
					source = `define ${defineKey}=${defineValue}`;
				else
					console.warn(`[skins] ${defineKey}=${defineValue}: no such sprite in this game, falling back to default candidates`);
			}
		}
		if(spriteIndex < 0){
			for(const candidate of SKIN_SPRITE_CANDIDATES[state]){
				spriteIndex = findSprite(candidate);
				if(spriteIndex >= 0){
					source = `candidate "${candidate}"`;
					break;
				}
			}
		}
		if(spriteIndex >= 0){
			const frames: number = sprites[spriteIndex].frames.length;
			lines.push(`global.__ONLINE_mapSpr[${st}] = ${spriteIndex}; global.__ONLINE_mapFrames[${st}] = ${frames};`);
			console.log(`  [skins] ${state} -> ${sprites[spriteIndex].name.toString('ascii')} (index ${spriteIndex}, ${frames} frame(s)) [${source}]`);
		}else{
			lines.push(`global.__ONLINE_mapSpr[${st}] = -1; global.__ONLINE_mapFrames[${st}] = 0;`);
			console.log(`  [skins] ${state} -> no matching sprite (-1)`);
		}
	}
	return lines.join("\r\n");
}

// S4: resolve the bullet sprite index (the native-bullet draw fallback and
// the default-sprite matching key), exactly like buildSkinSpriteMap does for
// state 6 (same candidate table; iwpo.skins.map.bullet override). A define
// that names no sprite warns and falls back to the candidate table (matching
// buildSkinSpriteMap's behaviour). Deterministic; exported for harnesses.
export const resolveBulletSprite = function(sprites: Array<Sprite>, defines: Map<string, string>): number {
	const findSpriteByName = function(name: string): number {
		const target: string = name.toLowerCase();
		for(let i: number = 0; i < sprites.length; ++i)
			if(sprites[i] && sprites[i].name.toString('ascii').toLowerCase() === target)
				return i;
		return -1;
	}
	let bulletSpr: number = -1;
	const mapDefine: string = "iwpo.skins.map.bullet";
	if(defines.has(mapDefine)){
		const defineValue: string = (defines.get(mapDefine) as string).trim();
		if(defineValue !== ""){
			bulletSpr = findSpriteByName(defineValue);
			if(bulletSpr < 0)
				console.warn(`[bullets] ${mapDefine}=${defineValue}: no such sprite, falling back to default candidates`);
		}
	}
	if(bulletSpr < 0){
		for(const candidate of SKIN_SPRITE_CANDIDATES.bullet){
			bulletSpr = findSpriteByName(candidate);
			if(bulletSpr >= 0)
				break;
		}
	}
	return bulletSpr;
}

// S4: resolve the game's bullet object index for bullet sharing. Priority:
// 1. the iwpo.bullet_object=<objectName> define ("-" = explicitly disabled,
//    matching the findAsset convention); 2. the object whose DEFAULT sprite
//    is the resolved bullet sprite; 3. -1 (sharing disabled at runtime,
//    every bulletShare entry inert). Deterministic; exported for harnesses.
export const resolveBulletObject = function(objects: Array<GMObject>, sprites: Array<Sprite>, defines: Map<string, string>): number {
	const bulletSpr: number = resolveBulletSprite(sprites, defines);
	let bulletObj: number = -1;
	const objDefine: string = "iwpo.bullet_object";
	if(defines.has(objDefine)){
		const defineValue: string = (defines.get(objDefine) as string).trim();
		if(defineValue === "-"){
			// Explicitly disabled (findAsset convention: "-" = off).
			console.log(`[bullets] ${objDefine}=- -> bullet sharing disabled`);
			return -1;
		}
		if(defineValue !== ""){
			for(let i: number = 0; i < objects.length; ++i){
				if(objects[i] && objects[i].name.toString('ascii').toLowerCase() === defineValue.toLowerCase()){
					bulletObj = i;
					break;
				}
			}
			if(bulletObj < 0)
				console.warn(`[bullets] ${objDefine}=${defineValue}: no such object, falling back to default-sprite matching`);
		}
	}
	if(bulletObj < 0 && bulletSpr >= 0){
		const hits: Array<number> = [];
		for(let i: number = 0; i < objects.length; ++i)
			if(objects[i] && objects[i].spriteIndex === bulletSpr)
				hits.push(i);
		if(hits.length > 0){
			bulletObj = hits[0];
			if(hits.length > 1)
				console.warn(`[bullets] ${hits.length} objects share the bullet sprite: ${hits.map(i => objects[i].name.toString('ascii')).join(", ")}; using ${objects[hits[0]].name.toString('ascii')} (override with ${objDefine})`);
		}
	}
	return bulletObj;
}

// S5 (PVP): resolve the game's kill script for the PVP bullet-hit call.
// Detection chain (RESEARCH_PVP_Design.md §3): 1. iwpo.pvp.killscript=<name>
// define ("-" = explicitly disabled); 2. scan every collision event (group 4)
// for calls to kill-ish scripts (name contains "kill", excluding save/load/
// count/time) and take the most-called one - the game's own killer collisions
// vote for the right script, so exotic names (SMB: scrKillPlayer) and
// per-area scripts (TUNNEL VISION: player_kill) resolve without guessing;
// 3. exact name candidates; 4. "" (PVP unavailable, settings row shows N/A).
// Deterministic; exported for harnesses.
export const resolvePvpKillScript = function(objects: Array<GMObject>, scripts: Array<Script>, defines: Map<string, string>): string {
	const scriptNames: Map<string, string> = new Map();
	for(const s of scripts)
		if(s && s.name) scriptNames.set(s.name.toString('latin1').toLowerCase(), s.name.toString('latin1'));
	const killDefine: string = "iwpo.pvp.killscript";
	if(defines.has(killDefine)){
		const defineValue: string = (defines.get(killDefine) as string).trim();
		if(defineValue === "-"){
			console.log(`[pvp] ${killDefine}=- -> PVP disabled`);
			return "";
		}
		if(defineValue !== ""){
			const hit: string | undefined = scriptNames.get(defineValue.toLowerCase());
			if(hit !== undefined) return hit;
			console.warn(`[pvp] ${killDefine}=${defineValue}: no such script, falling back to detection`);
		}
	}
	const isKillish = function(n: string): boolean { return /kill/i.test(n) && !/save|load|count|time/i.test(n); };
	const tally: Map<string, number> = new Map();
	const callRe: RegExp = /([A-Za-z_][A-Za-z0-9_]*)\s*\(/g;
	for(const o of objects){
		if(!o || !o.events || !o.events[4]) continue;
		for(const [, actions] of o.events[4]){
			for(const a of actions){
				const code: string = a.paramStrings && a.paramStrings[0] ? a.paramStrings[0].toString('latin1') : "";
				if(code === "") continue;
				callRe.lastIndex = 0;
				let m: RegExpExecArray | null;
				while((m = callRe.exec(code)) !== null){
					const name: string | undefined = scriptNames.get(m[1].toLowerCase());
					if(name !== undefined && isKillish(name)) tally.set(name, (tally.get(name) || 0) + 1);
				}
			}
		}
	}
	let best: string = "", bestN: number = 0;
	for(const [n, c] of tally){
		if(c > bestN){ best = n; bestN = c; }
	}
	if(best !== "") return best;
	for(const cand of ["killPlayer", "scrKillPlayer", "player_kill", "kill_player"]){
		const hit: string | undefined = scriptNames.get(cand.toLowerCase());
		if(hit !== undefined) return hit;
	}
	return "";
}

// S4: emit the world-Create constant block consumed by the bulletShare GML
// (global.__ONLINE_bulletObj / global.__ONLINE_bulletSpr). Kept for
// verification harnesses; production bakes the same values into the
// worldCreate template args (%arg9/%arg10) instead of a post-template block.
export const buildBulletMap = function(objects: Array<GMObject>, sprites: Array<Sprite>, defines: Map<string, string>): string {
	const bulletSpr: number = resolveBulletSprite(sprites, defines);
	const bulletObj: number = resolveBulletObject(objects, sprites, defines);
	const lines: Array<string> = ["// [iwpo] bullet sharing (generated at convert time)"];
	lines.push(`global.__ONLINE_bulletObj = ${bulletObj}; global.__ONLINE_bulletSpr = ${bulletSpr};`);
	if(bulletObj >= 0)
		console.log(`[bullets] bullet object -> ${objects[bulletObj].name.toString('ascii')} (index ${bulletObj}, sprite ${bulletSpr})`);
	else
		console.log(`[bullets] no bullet object resolved; bullet sharing disabled`);
	return lines.join("\r\n");
}

const isIdentChar = function(ch: string): boolean {
	return ch !== undefined && /[A-Za-z0-9_]/.test(ch);
}

const skipQuotedString = function(source: string, start: number): number {
	const quote: string = source[start];
	for(let cursor: number = start + 1; cursor < source.length; ++cursor){
		if(source[cursor] === "\\"){
			cursor += 1;
		}else if(source[cursor] === quote){
			return cursor;
		}
	}
	return source.length;
}

export const insertGMLScript = function(source: Buffer, code: Buffer): Buffer {
	// GM8 quirk: if a script starts with `{`, only code inside that matching
	// `{}` block executes. We insert our code before the closing `}` so it
	// runs within the block. Depth-aware matching avoids nested brace mismatches
	// (the old v1.1.9 code used lastIndexOf+regex with /m flag, which could
	// pick a non-root `}` on scripts that didn't truly start with `{`).
	const str: string = source.toString('ascii');
	const openIdx: number = str.indexOf('{');
	if(openIdx === -1 || str.substring(0, openIdx).trim().length > 0)
		return concatBuffers([source, code]);
	// Find matching closing brace, skipping strings and comments
	let depth: number = 0;
	let closeIdx: number = -1;
	for(let cursor: number = openIdx; cursor < str.length; ++cursor){
		const ch: string = str[cursor];
		if(ch === '"' || ch === "'"){
			cursor = skipQuotedString(str, cursor);
			if(cursor >= str.length) break;
		}else if(ch === '/' && str[cursor+1] === '/'){
			cursor = str.indexOf('\n', cursor + 2);
			if(cursor === -1) break;
		}else if(ch === '/' && str[cursor+1] === '*'){
			cursor = str.indexOf('*/', cursor + 2);
			if(cursor === -1) break;
			cursor++; // skip past '*/'
		}else if(ch === '{'){
			depth++;
		}else if(ch === '}'){
			depth--;
			if(depth === 0){ closeIdx = cursor; break; }
		}
	}
	if(closeIdx !== -1 && str.substring(closeIdx + 1).trim().length === 0)
		return concatBuffers([source.slice(0, closeIdx), Buffer.from("\n", 'ascii'), code, Buffer.from("}", 'ascii')]);
	return concatBuffers([source, code]);
}

export const insertGMLScriptBeforeSuccessfulReturn = function(source: Buffer, code: Buffer): Buffer {
	const str: string = source.toString('ascii');
	const pieces: Array<Buffer> = [];
	let lastWritten: number = 0;
	for(let cursor: number = 0; cursor < str.length; ++cursor){
		const ch: string = str[cursor];
		if(ch === '"' || ch === "'"){
			cursor = skipQuotedString(str, cursor);
			if(cursor >= str.length) break;
		}else if(ch === '/' && str[cursor+1] === '/'){
			cursor = str.indexOf('\n', cursor + 2);
			if(cursor === -1) break;
		}else if(ch === '/' && str[cursor+1] === '*'){
			cursor = str.indexOf('*/', cursor + 2);
			if(cursor === -1) break;
			cursor++;
		}else if(!isIdentChar(str[cursor-1]) && str.slice(cursor, cursor + 6).toLowerCase() === "return" && !isIdentChar(str[cursor+6])){
			const match: RegExpExecArray = /^return[ \t\r\n]*(?:\([ \t]*)?(?:true(?![A-Za-z0-9_])|1(?:\.0+)?(?![0-9.]))[ \t]*\)?[ \t]*;?/i.exec(str.slice(cursor));
			if(match){
				const returnEnd: number = cursor + match[0].length;
				pieces.push(source.slice(lastWritten, cursor));
				pieces.push(Buffer.from("{\n", 'ascii'));
				pieces.push(code);
				pieces.push(Buffer.from("\n", 'ascii'));
				pieces.push(source.slice(cursor, returnEnd));
				pieces.push(Buffer.from("\n}", 'ascii'));
				lastWritten = returnEnd;
				cursor = returnEnd - 1;
			}
		}
	}
	if(pieces.length > 0){
		pieces.push(source.slice(lastWritten));
		return concatBuffers(pieces);
	}
	return insertGMLScript(source, code);
}

const isAntidecProtected = async function(input: string): Promise<boolean> {
	try {
		const raw: SmartBuffer = SmartBuffer.fromBuffer(await fs.readFile(input));
		if(raw.readString(2) != "MZ") return false;
		raw.readOffset = 0x3C;
		raw.readOffset = raw.readUInt32LE();
		if(raw.readString(6) != "PE\0\0\x4C\x01") return false;
		const sectionCount: number = raw.readUInt16LE();
		raw.readOffset += 12;
		const optionalLength: number = raw.readUInt16LE();
		raw.readOffset += optionalLength + 2;
		let upx0VirtualLength: number = null;
		let upx1Data: [number, number] = null;
		for(let i: number = 0; i < sectionCount; ++i){
			const sectionName: Buffer = raw.readBuffer(8);
			const virtualSize: number = raw.readUInt32LE();
			raw.readOffset += 4;
			const diskSize: number = raw.readUInt32LE();
			const diskAddress: number = raw.readUInt32LE();
			raw.readOffset += 16;
			void diskSize;
			if(sectionName.compare(bytes([0x55,0x50,0x58,0x30,0x00,0x00,0x00,0x00])) == 0)
				upx0VirtualLength = virtualSize;
			if(sectionName.compare(bytes([0x55,0x50,0x58,0x31,0x00,0x00,0x00,0x00])) == 0)
				upx1Data = [virtualSize, diskAddress];
		}
		if(upx0VirtualLength === null || upx1Data === null) return false;
		const unpacked: SmartBuffer = SmartBuffer.fromBuffer(UpxUnpack(raw, upx0VirtualLength + upx1Data[0], upx1Data[1]));
		const hit80: boolean = Antidec.check80(unpacked) !== null;
		let hit81: boolean = false;
		if(!hit80) hit81 = Antidec.check81(unpacked) !== null;
		unpacked.destroy();
		raw.destroy();
		return hit80 || hit81;
	} catch(_e) {
		return false;
	}
}

const isFishClassGame = function(gameName: string): boolean {
	const normalizedName: string = gameName.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
	return normalizedName.includes("i wanna be the fish");
}

export const ConverterGM8 = async function(input: string, gameName: string, server: string, ports: Ports, forceExternalDll: boolean, customSlot: CustomSlotConfig | null = null, injectIntoStep: boolean = false, defines: Map<string, string> = new Map<string, string>()): Promise<void> {
	const configFilename: string = "__ONLINE_config.ini";
	console.log("Reading executable...");
	const fishClassGame: boolean = isFishClassGame(gameName);
	let fishCjkRuntimeBlocked: boolean = false;
	const head: Buffer = Buffer.alloc(0x400);
	const fh = await fs.open(input, "r");
	try { await fs.read(fh, head as unknown as Uint8Array, 0, head.length, 0); }
	finally { await fs.close(fh); }
	const isUpxPacked: boolean = head.includes(Buffer.from("UPX0")) || head.includes(Buffer.from("UPX1"));
	// The FoxWriting (fw) host hazard is STRUCTURAL, not name-based: a UPX-packed +
	// Antidec-protected GM8.0 exe cannot host the native CJK plugin - the plugin's
	// GMAPI/GDI+ init fails against that runner image. Historically only the game
	// whose name matched "i wanna be the fish" was gated, so other members of the
	// same structural class (e.g. "I wanna go the Frontline ver1.01", verified
	// UPX+Antidec) got fw injected and died at startup: the rebuild shipped since
	// be9d306 turns that into a hard GM8 "unexpected error occured when running the
	// game" (the pre-rebuild DLL only produced a recoverable "Error defining an
	// external function"). Detect the class by structure so any such game falls
	// back to the stub CJK path instead.
	if(isUpxPacked){
		const antidec: boolean = await isAntidecProtected(input);
		if(antidec){
			console.log(`UPX + Antidec GM8.0 host detected${fishClassGame ? " (fish-class)" : ""}; FoxWriting cannot initialize on this runner image, using the GML atlas CJK renderer.`);
			fishCjkRuntimeBlocked = true;
		}
	}

	let exe: SmartBuffer = SmartBuffer.fromBuffer(await fs.readFile(input));
	const getExeBuffer = function(): Buffer {
		return exe.internalBuffer.subarray(0, exe.length);
	}
	const replaceExeRange = function(start: number, end: number, newData: Buffer): void {
		const currentExe: Buffer = getExeBuffer();
		const updatedExe: Buffer = concatBuffers([
			currentExe.subarray(0, start),
			newData,
			currentExe.subarray(end),
		]);
		exe.destroy();
		exe = SmartBuffer.fromBuffer(updatedExe);
		exe.readOffset = start+newData.length;
		exe.writeOffset = exe.readOffset;
	}
	if(exe.readString(2) != "MZ")
		throw new Error("Invalid exe header");
	exe.readOffset = 0x3C;
	exe.readOffset = exe.readUInt32LE();
	if(exe.readString(6) != "PE\0\0\x4C\x01")
		throw new Error("Invalid PE header");
	const sectionCount: number = exe.readUInt16LE();
	exe.readOffset += 12;
	const optionalLength: number = exe.readUInt16LE();
	exe.readOffset += optionalLength+2;
	let upx0VirtualLength: number = null;
	let upx1Data: [number, number] = null;
	const sections: Array<PESection> = [];
	for(let i: number = 0; i < sectionCount; ++i){
		let sectionName: Buffer = exe.readBuffer(8);
		const virtualSize: number = exe.readUInt32LE();
		const virtualAddress: number = exe.readUInt32LE();
		const diskSize: number = exe.readUInt32LE();
		const diskAddress: number = exe.readUInt32LE();
		exe.readOffset += 16;
		if(sectionName.compare(bytes([0x55, 0x50, 0x58, 0x30, 0x00, 0x00, 0x00, 0x00])) == 0)
			upx0VirtualLength = virtualSize;
		if(sectionName.compare(bytes([0x55, 0x50, 0x58, 0x31, 0x00, 0x00, 0x00, 0x00])) == 0)
			upx1Data = [virtualSize, diskAddress];
		sections.push({
			virtualSize: virtualSize,
			virtualAddress: virtualAddress,
			diskSize: diskSize,
			diskAddress: diskAddress,
		});
	}
	let upxData: [number, number] = null;
	if(upx0VirtualLength !== null && upx1Data !== null)
		upxData = [upx0VirtualLength+upx1Data[0], upx1Data[1]];
	console.log("Decrypting executable...");
	const gameConfig: GameConfig = GameData.decrypt(exe, upxData);
	const settingsLength: number = exe.readUInt32LE();
	const settingsStart: number = exe.readOffset;
	const settings: Settings = Settings.load(exe, gameConfig, settingsStart, settingsLength);
	settings.showErrorMessage = true;
	settings.alwaysAbort = false;
	settings.treatCloseAsEsc = true;
	settings.logErrors = false;
	settings.dontShowButtons = false;
	settings.f4FullscreenToggle = true;
	settings.allowResize = true;
	settings.scaling = -1;
	settings.displayCursor = true;
	settings.zeroUninitializedVars = true;
	const dllNameLength: number = exe.readUInt32LE();
	exe.readOffset += dllNameLength;
	const dxDll: Buffer = exe.readBuffer(exe.readUInt32LE());
	const encryptionStartGM80: number = exe.readOffset;
	const uniqueKey: string = GM80.decrypt(exe);
	const garbageDWords = exe.readUInt32LE();
	exe.readOffset += garbageDWords*4;
	exe.writeOffset = exe.readOffset;
	exe.writeUInt32LE(Number(true));
	const proFlag: boolean = exe.readUInt32LE() != 0;
	const gameID: number = exe.readUInt32LE();
	const guid: [number, number, number, number] = [
		exe.readUInt32LE(),
		exe.readUInt32LE(),
		exe.readUInt32LE(),
		exe.readUInt32LE(),
	];
	const getAssetRefs = function(src: SmartBuffer): Array<Buffer> {
		const count: number = src.readUInt32LE();
		const refs: Array<Buffer> = new Array(count);
		for(let i: number = 0; i < count; ++i){
			const length: number = src.readUInt32LE();
			const data: Buffer = src.readBuffer(length);
			refs[i] = data;
		}
		return refs;
	}
	const getAssets = function(src: SmartBuffer, deserializer: (data: SmartBuffer, version: GameConfig) => Asset): Array<Asset> {
		const toAsset = function(ch: Buffer): Asset {
			const data: Buffer = inflateBuffer(ch);
			if(data.length < 4)
				throw new Error("Malformed data");
			if(data.slice(0, 4).compare(bytes([0, 0, 0, 0])) == 0)
				return null;
			const sBuffer: SmartBuffer = SmartBuffer.fromBuffer(data.slice(4));
			const asset: Asset = deserializer(sBuffer, gameConfig);
			sBuffer.destroy();
			return asset;
		}
		return getAssetRefs(src).map(toAsset);
	}

	const putAssetRefs = function(exe: SmartBuffer, assets: Array<Asset>): Buffer {
		const data: SmartBuffer = new SmartBuffer();
		data.writeUInt32LE(assets.length);
		for(let i: number = 0, n: number = assets.length; i < n; i++){
			const tmpData: SmartBuffer = new SmartBuffer();
			tmpData.writeOffset = 0;
			tmpData.readOffset = 0;
			const asset: Asset = assets.shift();
			asset.serialize(tmpData);
			const tmpData2: Buffer = deflateBuffer(tmpData.internalBuffer.subarray(0, tmpData.length));
			tmpData.destroy();
			data.writeUInt32LE(tmpData2.length);
			data.writeBuffer(tmpData2);
		}
		return data.internalBuffer.subarray(0, data.length);
	}

	const putAssets = function(exe: SmartBuffer, assets: Array<Asset>): Buffer {
		const data: SmartBuffer = new SmartBuffer();
		data.writeUInt32LE(assets.length);
		for(let i: number = 0, n: number = assets.length; i < n; ++i){
			const tmpData: SmartBuffer = new SmartBuffer();
			tmpData.writeOffset = 0;
			tmpData.readOffset = 0;
			const asset: Asset = assets.shift();
			if(asset !== null){
				tmpData.writeBuffer(Buffer.from([1, 0, 0, 0]));
				asset.serialize(tmpData);
			}else{
				tmpData.writeBuffer(Buffer.from([0, 0, 0, 0]));
			}
			const tmpData2: Buffer = deflateBuffer(tmpData.internalBuffer.subarray(0, tmpData.length));
			tmpData.destroy();
			data.writeUInt32LE(tmpData2.length);
			data.writeBuffer(tmpData2);
		}
		return data.internalBuffer.subarray(0, data.length);
	}
	const replaceChunk = function(exe: SmartBuffer, offsets: [number, number], newData: Buffer): void {
		replaceExeRange(offsets[0], offsets[1], newData);
	}
	const findAsset = function(assets: Array<Asset>, names: Array<string>, defineKey?: string): Asset {
		if(defineKey !== undefined && defines.has(defineKey)){
			const defineValue: string = defines.get(defineKey) as string;
			if(defineValue === "-") return undefined; // explicitly disabled via per-game ini / --define
			const defineTarget: string = defineValue.toLowerCase();
			return assets.filter(asset => asset && asset["name"].toString('ascii').toLowerCase() === defineTarget)[0];
		}
		let result: Asset;
		for(let i: number = 0; i < names.length; ++i){
			const target: string = names[i].toLowerCase();
			result = assets.filter(asset => asset && asset["name"].toString('ascii').toLowerCase() === target)[0];
			if(result !== undefined)
				break;
		}
		return result;
	}
	const findAssetInteractive = async function(assets: Array<Asset>, names: Array<string>, typeName: string, required: boolean = true, defineKey?: string): Promise<Asset | undefined> {
		let result: Asset = findAsset(assets, names, defineKey);
		if(result !== undefined) return result;
		if(defineKey !== undefined && defines.has(defineKey))
			throw new Error(`No ${typeName} named '${defines.get(defineKey)}' (from ${defineKey}) found`);
		if(!required) return undefined;
		const validAssets: Array<{index: number, name: string}> = [];
		for(let i = 0; i < assets.length; i++){
			if(assets[i]) validAssets.push({index: i, name: assets[i]["name"].toString('ascii')});
		}
		if(process.stdin.isTTY && validAssets.length > 0){
			console.log(`\nCould not find ${typeName} (tried: ${names.join(", ")})`);
			const confirm: string = await Utils.getString(`Would you like to select from ${validAssets.length} available ${typeName}s? (y/n): `);
			if(confirm.trim().toLowerCase() === 'y'){
				for(let i = 0; i < validAssets.length; i++){
					console.log(`  ${i + 1}. ${validAssets[i].name}`);
				}
				const answer: string = await Utils.getString(`Select ${typeName} by number (or 0 to cancel): `);
				const idx: number = parseInt(answer) - 1;
				if(idx >= 0 && idx < validAssets.length){
					return assets[validAssets[idx].index];
				}
			}
		}
		throw new Error(`No ${typeName} found`);
	}
	console.log("Reading game data...");
	if(exe.readUInt32LE() != 700)
		throw new Error("Extensions header");
	const extensionCountPos: number = exe.readOffset;
	const extensionCount: number = exe.readUInt32LE();
	let extensions: Array<Extension> = new Array(extensionCount);
	let hasWindowsDialogs: boolean = false;
	let hasGm82net: boolean = false;
	let hasGm82buf: boolean = false;
	let hasGm82snd: boolean = false;
	// GM8.2 runner detection: the GM8.2 ecosystem ships "Game Maker 8.2 *"
	// extensions (Core/Network/Buffer/Sound/DirectX9/...). This matters because
	// GM8.2 repurposed object event group 11 (triggers in GM8.0/8.1) as the
	// native Draw GUI event — only GM8.2-runner games may receive group-11
	// injected code. A second signal (native group-11 events with zero trigger
	// assets) is OR-ed in after the objects section is parsed.
	let isGM82: boolean = false;
	let hasGm8FoxWriting: boolean = false;
	const extNameIs = function(ext: Extension, name: string): boolean {
		return ext.name.toString('ascii').toLowerCase() === name.toLowerCase();
	}
	const extNameStartsWith = function(ext: Extension, prefix: string): boolean {
		return ext.name.toString('ascii').toLowerCase().startsWith(prefix.toLowerCase());
	}
	for(let i: number = 0; i < extensionCount; ++i){
		extensions[i] = Extension.read(exe);
		if(extNameIs(extensions[i], "GM Windows Dialogs"))
			hasWindowsDialogs = true;
		if(extNameStartsWith(extensions[i], "Game Maker 8.2 Network"))
			hasGm82net = true;
		if(extNameStartsWith(extensions[i], "Game Maker 8.2 Buffer"))
			hasGm82buf = true;
		if(extNameStartsWith(extensions[i], "Game Maker 8.2 Sound"))
			hasGm82snd = true;
		if(extNameStartsWith(extensions[i], "Game Maker 8.2 "))
			isGM82 = true;
		if(extNameIs(extensions[i], "Noisyfox's Writing") && extensions[i].folderName.toString('ascii').toLowerCase() === "fw")
			hasGm8FoxWriting = true;
		if(extNameIs(extensions[i], "Http Dll 2.3") && extensions[i].folderName.toString('ascii').toLowerCase() === "http_dll_2_3")
			throw new Error("This game is already an online version");
	}
	// Extension function IDs live in one global table and must be unique, or the
	// runner aborts at load with "COMPILATION ERROR in extension package". Our
	// injected blobs carry hardcoded IDs (e.g. GaseousMarble 418-457), so any game
	// whose own extensions occupy that range would collide. Renumber every injected
	// blob to start above the highest ID already in use.
	let nextExtFuncId: number = 17; // GM's IDE starts extension function IDs at 17 (0-16 reserved)
	for(const ext of extensions)
		for(const file of ext.files)
			for(const fn of file.functions)
				if(fn.id >= nextExtFuncId) nextExtFuncId = fn.id + 1;
	// Rewrite all function IDs in an extension blob to a fresh sequential range
	// starting at nextExtFuncId, and advance nextExtFuncId past the used range.
	// Throws on unexpected structure so a malformed blob can never pass through
	// with colliding IDs.
	const renumberExtensionBlob = function(data: Buffer): Buffer {
		let off: number = 0;
		const rd32 = function(): number { const v: number = data.readUInt32LE(off); off += 4; return v; };
		const skipPascal = function(): void { const len: number = rd32(); off += len; };
		const checkVersion = function(what: string): void {
			if(rd32() != 700) throw new Error(`Extension blob ${what} version is incorrect`);
		};
		checkVersion("header");
		skipPascal(); // extension name
		skipPascal(); // folder name
		const fileCount: number = rd32();
		for(let i: number = 0; i < fileCount; ++i){
			checkVersion("file");
			skipPascal(); // file name
			rd32(); // kind
			skipPascal(); // initializer
			skipPascal(); // finalizer
			const functionCount: number = rd32();
			for(let j: number = 0; j < functionCount; ++j){
				checkVersion("function");
				skipPascal(); // function name
				skipPascal(); // external name
				rd32(); // convention
				data.writeUInt32LE(nextExtFuncId, off);
				off += 4; // id
				nextExtFuncId += 1;
				off += 4 + 17 * 4 + 4; // argCount, argTypes, returnType
			}
			const constCount: number = rd32();
			for(let j: number = 0; j < constCount; ++j){
				checkVersion("constant");
				skipPascal(); // constant name
				skipPascal(); // constant value
			}
		}
		return data;
	}
	const addExtension = async function(exe: SmartBuffer, extensions: Array<Extension>, file: string): Promise<void> {
		const pos: number = exe.readOffset;
		const extensionData: Buffer = renumberExtensionBlob(await fs.readFile(path.join(__dirname, "lib", file)));
		replaceExeRange(pos, pos, extensionData);
		extensions.push(null);
	}
	// Extension-package injection policy.
	//   IWPO_NO_EXTENSION_PACKAGES=1   -> skip all (legacy switch, kept for back-compat).
	//   IWPO_EXT_PACKAGES=auto|all     -> inject everything (default).
	//   IWPO_EXT_PACKAGES=fw_only      -> only ChineseChatSupport8 (Chinese rendering).
	//   IWPO_EXT_PACKAGES=wd_only      -> only gm_windows_dialog8 (Windows dialogs).
	//   IWPO_EXT_PACKAGES=gm_only      -> only gaseous_marble8 (GM8.1+ only).
	//   IWPO_EXT_PACKAGES=none         -> skip all (same as IWPO_NO_EXTENSION_PACKAGES=1).
	//   IWPO_DIAG_EXT="wd"|"fw"        -> legacy bisection alias for wd_only / fw_only.
	const __extLegacyNo = process.env.IWPO_NO_EXTENSION_PACKAGES === "1";
	let __extMode: string = (process.env.IWPO_EXT_PACKAGES || "").toLowerCase();
	if(!__extMode){
		const __diag = (process.env.IWPO_DIAG_EXT || "").toLowerCase();
		if(__diag === "wd") __extMode = "wd_only";
		else if(__diag === "fw") __extMode = "fw_only";
		else if(__diag === "none") __extMode = "none";
	}
	if(__extLegacyNo) __extMode = "none";
	if(!__extMode) __extMode = "auto";
	const __extAll = __extMode === "auto" || __extMode === "all";
	const wantWD = __extMode !== "none" && (__extAll || __extMode === "wd_only");
	let wantFW = __extMode !== "none" && (__extAll || __extMode === "fw_only");
	const wantGM = gameConfig.version !== GameVersion.GameMaker80 && __extMode !== "none" && (__extAll || __extMode === "gm_only");
	if(fishCjkRuntimeBlocked && gameConfig.version === GameVersion.GameMaker80 && wantFW){
		console.log("Fish-class host detected; using safe GM8.0 stub path.");
		wantFW = false;
	}
	if(!hasWindowsDialogs && wantWD)
		await addExtension(exe, extensions, "gm_windows_dialog8");
	if(wantGM)
		await addExtension(exe, extensions, "gaseous_marble8");
	if(!hasGm8FoxWriting && gameConfig.version === GameVersion.GameMaker80 && wantFW)
		await addExtension(exe, extensions, "ChineseChatSupport8");
	// Final "is this extension's functions actually defined in the runtime?" flags,
	// used below to decide which stub scripts must be synthesized.
	const loadedWD: boolean = hasWindowsDialogs || wantWD;
	const loadedFW: boolean = hasGm8FoxWriting || wantFW;
	const loadedGM: boolean = wantGM;
	// CJK rendering backend selection. Drives all downstream gating (preprocessor vars,
	// stub generation, font asset deployment, gameName encoding, helper scripts).
	//   'fw' — GM8.0 FoxWriting path (real or stubbed). GBK strings throughout.
	//   'gm' — GaseousMarble path for GM8.1+.
	//   'none' — neither available; CJK characters will render as garbage via plain draw_text.
	const cjkBackend: 'none' | 'fw' | 'gm' =
		gameConfig.version === GameVersion.GameMaker80 ? 'fw' :
		(loadedGM ? 'gm' : 'none');
	const useUtf8: boolean = gameConfig.version !== GameVersion.GameMaker80;
	console.log(`CJK backend: ${cjkBackend}`);
	// Set when FoxWriting cannot be loaded and the GML bitmap-atlas pack takes over
	// the fw_* API (assets must be deployed next to the exe for that).
	let atlasCjkActive: boolean = false;

	exe.writeOffset = extensionCountPos;
	exe.writeUInt32LE(extensions.length);
	extensions = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Triggers header");
	let triggers: Array<Trigger> = getAssets(exe, Trigger.deserialize) as Array<Trigger>;
	const triggerCount: number = triggers.length; // GM8.2 detection signal (see isGM82)
	// GM8.2's native Draw GUI event is group 11 dispatched at the subtype equal
	// to the index of the trigger NAMED "Draw GUI" (the runner keys on the name).
	// It is NOT always 0: DLDC's renex trigger table has it at index 1, so our
	// HUD attached at subtype 0 was bound to the always-on "Early Step" trigger
	// and ran in the step phase - tick alive, but every draw went nowhere.
	let drawGuiSubType: number = 0;
	let drawGuiTriggerFound: boolean = false;
	{
		for(let ti: number = 0; ti < triggers.length; ++ti){
			const tg: Trigger = triggers[ti];
			if(tg && tg.name && tg.name.toString('ascii').toLowerCase() === "draw gui"){
				drawGuiSubType = ti;
				drawGuiTriggerFound = true;
				break;
			}
		}
	}
	triggers = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Constants header");
	const constantCount: number = exe.readUInt32LE();
	const constants: Array<Constant> = new Array(constantCount);
	for(let i: number = 0; i < constantCount; ++i){
		const name: Buffer = exe.readBuffer(exe.readUInt32LE());
		const expression: Buffer = exe.readBuffer(exe.readUInt32LE());
		constants[i] = {
			name: name,
			expression: expression,
		}
	}
	if(exe.readUInt32LE() != 800)
		throw new Error("Sounds header");
	const soundsOffsets: [number, number] = [exe.readOffset, 0];
	let sounds: Array<Sound> = getAssets(exe, Sound.deserialize) as Array<Sound>;
	soundsOffsets[1] = exe.readOffset;
	const newSound = async function(sounds: Array<Sound>, file: string): Promise<void> {
		const sound: Sound = new Sound();
		sound.name = Buffer.from(file, 'ascii');
		sound.content = await fs.readFile(path.join(__dirname, "lib", file));
		sounds.push(sound);
	}
	if (!hasGm82snd) {
		await newSound(sounds, "sound_chatbox8");
		await newSound(sounds, "sound_saved8");
		replaceChunk(exe, soundsOffsets, putAssets(exe, sounds));
	}
	sounds = null;
	// Skin system master switch (covers T1-T4). iwpo.no_skins=true/1 disables all
	// skin-related injection: script assets, player Draw hooks, the sprite-state
	// map constants and the [config] ini keys. With injection skipped, the
	// GML-side global defaults (-1) keep the game safely skinless.
	const noSkinsRaw: string = defines.has("iwpo.no_skins") ? (defines.get("iwpo.no_skins") as string).toLowerCase() : "";
	const skinsEnabled: boolean = noSkinsRaw !== "true" && noSkinsRaw !== "1";
	// Fail fast: md5.gml and skinLib.gml are always required (their script assets
	// are injected unconditionally — worldCreate/worldEndStep call them in every
	// converted game); playerDrawInject.gml is only needed with skins enabled.
	// Abort before any asset rewriting instead of deep into the conversion.
	for(const skinFile of (skinsEnabled ? ["md5", "skinLib", "bulletShare", "notesLib", "playerDrawInject"] : ["md5", "skinLib", "bulletShare", "notesLib"])){
		if(!await fs.exists(path.join(__dirname, "gml", `${skinFile}.gml`)))
			throw new Error(`Skin system GML missing: gml/${skinFile}.gml. md5.gml and skinLib.gml must always be present in the gml/ folder; playerDrawInject.gml too unless converting with iwpo.no_skins=true.`);
	}
	if(exe.readUInt32LE() != 800)
		throw new Error("Sprites header");
	// T3: the skin sprite-state map needs sprite names/indices/frame counts, so
	// the section is deserialized when skins are enabled. Sprites are never
	// written back — with skins disabled keep the old cheap skip.
	let skinMapCode: string = "";
	// S4: bullet-sharing constants are baked into the worldCreate template
	// args (%arg9/%arg10) instead of a post-template block: GM8 reads an
	// unassigned global as 0, which would defeat the -1 disabled state if the
	// assignment ran after @bullet_init (see the resolution site below).
	// Built-in sprite count, baked into worldCreate as the base index for the
	// restart-time dynamic-sprite sweep (0 disables the sweep). The converter
	// never writes sprites back, so this count stays valid in the output game.
	let skinSpriteBase: number = 0;
	let skinSprites: Array<Sprite> = null;
	if(skinsEnabled){
		skinSprites = getAssets(exe, Sprite.deserialize) as Array<Sprite>;
		if(process.env.IWPO_SKIN_LIST_SPRITES)
			for(let si: number = 0; si < skinSprites.length; ++si)
				if(skinSprites[si]) console.log(`[sprite ${si}] ${(skinSprites[si] as Sprite).name.toString('latin1')}`);
		skinMapCode = buildSkinSpriteMap(skinSprites, defines);
		skinSpriteBase = skinSprites.length;
	}else{
		getAssetRefs(exe); // skip sprites section (no modification needed)
	}

	if(exe.readUInt32LE() != 800)
		throw new Error("Backgrounds header");
	let backgrounds: Array<Background> = getAssets(exe, Background.deserialize) as Array<Background>;
	backgrounds = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Paths header");
	let paths: Array<Path> = getAssets(exe, Path.deserialize) as Array<Path>;
	paths = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Scripts header");
	const scriptsOffsets: [number, number] = [exe.readOffset, 0];
	let scripts: Array<Script> = getAssets(exe, Script.deserialize) as Array<Script>;
	scriptsOffsets[1] = exe.readOffset;
	if(exe.readUInt32LE() != 800)
		throw new Error("Fonts header");
	const fontsOffsets: [number, number] = [exe.readOffset, 0];
	let fonts: Array<Font> = getAssets(exe, Font.deserialize) as Array<Font>;
	fontsOffsets[1] = exe.readOffset;
	const newFont = async function(fonts: Array<Font>, file: string): Promise<void> {
		const font: Font = new Font();
		font.name = Buffer.from(file, 'ascii');
		font.content = await fs.readFile(path.join(__dirname, "lib", file));
		fonts.push(font);
	}
	await newFont(fonts, "font_online8");
	replaceChunk(exe, fontsOffsets, putAssets(exe, fonts));
	fonts = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Timelines header");
	let timelines: Array<Timeline> = getAssets(exe, Timeline.deserialize) as Array<Timeline>;
	// Code snippets worth a GAME_D3D scan that live outside objects/scripts
	// (timeline moments here; room creation codes are collected from the room
	// chunks at the scan site). Consumed by the scanD3d block below.
	const extraD3dCode: Array<string> = [];
	for(const tl of timelines){
		if(!tl || !tl.moments) continue;
		for(const [, tlActions] of tl.moments)
			for(const tlAction of tlActions)
				if(tlAction.paramStrings && tlAction.paramStrings[0])
					extraD3dCode.push(tlAction.paramStrings[0].toString('latin1'));
	}
	timelines = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Objects header");
	const objectsOffsets: [number, number] = [exe.readOffset, 0];
	let objects: Array<GMObject> = getAssets(exe, GMObject.deserialize) as Array<GMObject>;
	objectsOffsets[1] = exe.readOffset;
	// GM8.2 detection, signal 2: native group-11 events. In GM8.0/8.1 group 11 is
	// the trigger group, so events there only make sense while trigger assets
	// exist; group-11 code in a game with zero triggers can only be GM8.2's
	// repurposed Draw GUI event (e.g. TUNNEL VISION's overlay objects).
	if(!isGM82 && triggerCount === 0){
		for(const obj of objects){
			if(obj && obj.events[11] && obj.events[11].length > 0){
				isGM82 = true;
				break;
			}
		}
	}
	// S4: bullet-object resolution needs both the sprite table and the object
	// table, so it runs here (after both are deserialized). The constants are
	// baked into the worldCreate template as %arg9/%arg10 - INLINED BEFORE
	// @bullet_init runs later in the template. (addCreateCode would append the
	// block AFTER the template body, and GM8 reads an unassigned global as 0,
	// which would defeat the -1 disabled state; GMS prepends instead, see
	// converter-gms/Program.cs.)
	let bulletObjIdx: number = skinsEnabled ? resolveBulletObject(objects, skinSprites as Array<Sprite>, defines) : -1;
	let bulletSprIdx: number = skinsEnabled ? resolveBulletSprite(skinSprites as Array<Sprite>, defines) : -1;
	if(bulletObjIdx >= 0)
		console.log(`[bullets] bullet object -> ${objects[bulletObjIdx].name.toString('ascii')} (index ${bulletObjIdx}, sprite ${bulletSprIdx})`);
	else
		console.log(`[bullets] no bullet object resolved; bullet sharing disabled`);
	// S5 (PVP): resolve the kill script before any template picks up PVPKILL
	// (worldCreate bakes @pvpAvail, bulletShareEndStep bakes the kill call).
	const pvpKillScript: string = skinsEnabled ? resolvePvpKillScript(objects, scripts, defines) : "";
	if(pvpKillScript !== ""){
		console.log(`[pvp] kill script -> ${pvpKillScript} (PVP available)`);
		GMLCode.addVariables("PVPKILL");
	}else{
		console.log(`[pvp] no kill script resolved; PVP unavailable for this game`);
	}
	if(objects.some(obj => obj && obj.name.toString('ascii').startsWith("__ONLINE_")))
		throw new Error("This game is already an online version");
	const gameWorld: GMObject = await findAssetInteractive(objects, ["world", "World", "objWorld", "oWorld"], "object world") as GMObject;
	// C2 custom world object (TheBiob converterGM8.ts:497-519 heritage, default on).
	// Instead of piggybacking on the game's world object we inject our own invisible
	// persistent object and place it as the first instance of the first room.
	// iwpo.insert_custom_world=false/0 restores the legacy behaviour.
	// inject_into_step implies the legacy object: that flag exists for community-GM8.2-
	// runtime games (yuuutu-era sources, e.g. IWKTS2) where Step/EndStep events of
	// INJECTED objects never dispatch - the custom world is itself such an object,
	// so with C2 on its tick never runs and all online logic dies right after the
	// (working) Create event. An explicit iwpo.insert_custom_world=true still wins.
	const customWorldRaw: string = defines.has("iwpo.insert_custom_world") ? (defines.get("iwpo.insert_custom_world") as string).toLowerCase() : "";
	const customWorld: boolean = customWorldRaw !== "" ? (customWorldRaw !== "false" && customWorldRaw !== "0") : !injectIntoStep;
	if(!customWorld && customWorldRaw === "" && injectIntoStep)
		console.log("[compat] inject_into_step=1: using the game's native world object (custom world cannot tick on this runtime class)");
	let world: GMObject = gameWorld;
	if(customWorld){
		GMLCode.addVariables("CUSTOM_WORLD_OBJ");
		world = new GMObject();
		world.name = Buffer.from("__ONLINE_world", 'ascii');
		world.spriteIndex = -1;
		world.solid = false;
		world.visible = false;
		world.depth = -999999999;
		world.persistent = true;
		world.parentIndex = -1;
		world.maskIndex = -1;
		world.events = [[], [], [], [], [], [], [], [], [], [], [], []];
		// ActiveParent parenting (TheBiob heritage): engines that deactivate instances
		// wholesale tend to spare ActiveParent children.
		const activeParent: GMObject = findAsset(objects, ["ActiveParent"]) as GMObject;
		if(activeParent !== undefined)
			world.parentIndex = objects.indexOf(activeParent);
	}
	// Object index the custom world will occupy once pushed (it is pushed first among
	// the new objects at the objects.push site below). Only meaningful when customWorld.
	const customWorldObjectId: number = objects.length;
	const player: GMObject = await findAssetInteractive(objects, ["player", "Player", "objPlayer", "oPlayer", "objplayer"], "object player") as GMObject;
	const player2: GMObject = findAsset(objects, ["player2", "objPlayer2", "oPlayer2"]) as GMObject;
	GMLCode.addVariables("GM8");
	if (gameConfig.version === GameVersion.GameMaker80) {
		GMLCode.addVariables("GM80");
	}
	if (isGM82) {
		// GM8.2 repurposed object event group 11 (triggers in GM8.0/8.1) as the
		// native Draw GUI event: runs once per frame after all regular draws, in
		// window pixel coordinates. Screen-space HUD lives there because regular
		// Draw output is silently invisible in d3d-started rooms (TUNNEL VISION
		// E1 probe: group-8 text never rasterizes, group-11 does). GM8.0/8.1
		// runners treat group 11 as triggers (never dispatched as a draw event),
		// so they must keep the regular-Draw path.
		console.log("[hud] GM8.2 detected; HUD uses the native Draw GUI event (group 11, subtype " + drawGuiSubType + ")");
		if(triggerCount > 0 && !drawGuiTriggerFound){
			// With a trigger table present but no trigger NAMED "Draw GUI",
			// subtype 0 binds to trigger 0 and our draw code fires in the step
			// phase (invisible). The named trigger should always exist in GM8.2
			// games - warn loudly if it does not.
			console.log("[hud] WARNING: game has triggers but none named 'Draw GUI'; HUD may not render");
		}
		GMLCode.addVariables("GM8GUI");
	}
	if (cjkBackend === 'gm') {
		GMLCode.addVariables("CJKTEXT");
	}
	// Engines known not to use the game_restart+tempfile save flow (TheBiob heritage:
	// scrRestartGame = NANEGM8, saveByte = "I wanna enjoy a Merry Christmas!").
	// For everything else the temp-file online save path stays enabled.
	// iwpo.temp_file (true/false) overrides the heuristic entirely.
	const tempFileDefine: string = defines.has("iwpo.temp_file") ? (defines.get("iwpo.temp_file") as string).toLowerCase() : "";
	if(tempFileDefine === "true" || tempFileDefine === "1"){
		GMLCode.addVariables("TEMPFILE");
	}else if(tempFileDefine !== "false" && tempFileDefine !== "0"){
		if(findAsset(scripts, ["scrRestartGame", "saveByte"]) === undefined)
			GMLCode.addVariables("TEMPFILE");
	}
	if (hasGm82net || hasGm82buf){
		GMLCode.addVariables("GMNET");
	}
	if (hasGm82net){
		GMLCode.addVariables("GM82NET");
		// NOTE: GM82NET is an engine-variant marker introduced with the GM8.2 network
		// path (beta5). No GML currently consumes it (#if GM82NET has zero hits) —
		// kept for future GM8.2-specific branches. Same for the base "GM8" flag above.
	}
	if (scripts.some(script => script && (
		script.name.equals(ascii("save_save")) ||
		script.name.equals(ascii("player_air_jump")))))
		GMLCode.addVariables("RENEX");
	if (gameWorld.name.equals(ascii("objWorld")))
		GMLCode.addVariables("GM8YY");
	// C4 facing detection (TheBiob converterGM8.ts:690-698 heritage): register the
	// facing variable the player's Create event initializes, so the broadcast
	// templates can multiply image_xscale by it instead of falling back to a bare
	// image_xscale. Skipped for GM8YY (objWorld) games — that template branch
	// already hardcodes xScale.
	if (!gameWorld.name.equals(ascii("objWorld"))) {
		let facingVar: string = "";
		if (player.hasStringInEvent(0, 0, "xScale = 1", true)) {
			GMLCode.addVariables("PLAYER_XSCALE");
			facingVar = "xScale";
		} else if (player.hasStringInEvent(0, 0, "xscale = 1", true)) {
			GMLCode.addVariables("PLAYER_XSCALE_LOWER");
			facingVar = "xscale";
		} else if (player.hasStringInEvent(0, 0, "facing=1", true)) {
			GMLCode.addVariables("PLAYER_FACING");
			facingVar = "facing";
		}
		console.log("Facing variable: " + (facingVar || "none (bare image_xscale)"));
	}
	if (hasGm82snd)
		GMLCode.addVariables("GMSND");
	if(player2 != undefined)
		GMLCode.addVariables("PLAYER2");
	// C1 multi-player object list (TheBiob converterGM8.ts:563-589 heritage, adapted).
	// Default on; iwpo.no_player_list=true restores the legacy player/player2-only path.
	// iwpo.alt_player_objects appends comma-separated object names after player/player2.
	// Unlike TheBiob we validate alt names against the object list: GM8 compiles the
	// baked names as constants, so an unknown name would be a hard compile error.
	// Objects receiving the skin Draw injection (T2): exactly the object set the
	// player list covers (player/player2 plus validated iwpo.alt_player_objects
	// entries), or just player/player2 when PLAYER_LIST is disabled.
	const skinTargetObjects: Array<GMObject> = [player];
	if (player2 != undefined)
		skinTargetObjects.push(player2);
	let playerListInitCode: string = "";
	const noPlayerList: string = defines.has("iwpo.no_player_list") ? (defines.get("iwpo.no_player_list") as string).toLowerCase() : "";
	if (noPlayerList !== "true" && noPlayerList !== "1") {
		GMLCode.addVariables("PLAYER_LIST");
		const playerListNames: Array<string> = [player.name.toString('ascii')];
		if (player2 != undefined)
			playerListNames.push(player2.name.toString('ascii'));
		const altPlayerObjects: string = defines.has("iwpo.alt_player_objects") ? (defines.get("iwpo.alt_player_objects") as string) : "";
		for (const altRaw of altPlayerObjects.split(',')) {
			const altName: string = altRaw.trim();
			if (altName === "")
				continue;
			const altObj: GMObject = findAsset(objects, [altName]) as GMObject;
			if (altObj === undefined) {
				console.warn(`[iwpo] alt_player_objects: object "${altName}" not found in this game, skipped`);
				continue;
			}
			const canonicalAlt: string = altObj.name.toString('ascii');
			if (playerListNames.indexOf(canonicalAlt) < 0){
				playerListNames.push(canonicalAlt);
				skinTargetObjects.push(altObj);
			}
		}
		for (const listName of playerListNames)
			playerListInitCode += `ds_list_add(__ONLINE_obj_list, ${listName});\r\n`;
		// Active-player resolver: first listed object with a live instance (object index,
		// noone when none exist). This Buffer is injected verbatim (via %arg6 / script
		// push), so it must use final __ONLINE_ names - the @ prefix substitution in
		// GMLCode.getGML runs before %argN replacement and does not apply here.
		const worldNameStr: string = world.name.toString('ascii');
		const activePlayerScript: Script = new Script();
		activePlayerScript.name = Buffer.from("__ONLINE_get_active_player", "ascii");
		activePlayerScript.source = Buffer.from(
			"var __gap_i, __gap_obj;\r\n" +
			`for (__gap_i = 0; __gap_i < ds_list_size(${worldNameStr}.__ONLINE_obj_list); __gap_i += 1) {\r\n` +
			`__gap_obj = ds_list_find_value(${worldNameStr}.__ONLINE_obj_list, __gap_i);\r\n` +
			"if (instance_exists(__gap_obj)) return __gap_obj;\r\n" +
			"}\r\n" +
			"return noone;", "ascii");
		scripts.push(activePlayerScript);
	}
	// Use a specific script name to detect Nikaple's Engine
	if(scripts.some(script => script && script.name.equals(ascii("audio_togglesoundmuted"))))
		GMLCode.addVariables("NIKAPLE");
	// NOTE: NIKAPLE is upstream heritage; no #if consumes it, but the converter
	// itself reads it when choosing the loadGame injection target (Nikaple
	// engines take the saveExe branch), and README.md documents it in a usage
	// example.
	// Use external_define/external_call for the NativeAOT x86 DLL.
	// This DLL performs ANSI↔UTF-8 conversion needed for Chinese text support.
	// GM82NET/GM82BUF games use aliased (gm82-style) wrapper names; others use
	// standard DLL export names.
	// IMPORTANT: wrapper scripts MUST be named with the __ONLINE_ prefix. Naming a
	// wrapper buffer_create/socket_create/etc. shadows the game's own gm82net
	// extension function of the same name. http_dll and gm82net share the same
	// buffer code but keep SEPARATE static buffer tables, so a buffer created
	// through a shadowing wrapper (http_dll table) is invisible to unwrapped
	// gm82net functions like buffer_save_temp/buffer_get_size/buffer_inflate.
	// This broke RENEX-engine games (e.g. I wanna Land on a Cloud): sound_add_pack
	// mixes buffer_create with buffer_save_temp, and the pack extraction temp file
	// was never written ("File does not exist trying to add a sound: ...wasd.ogg").
	// TheBiob avoids this by only ever adding __ONLINE_*-named wrappers.
	// All buffers/sockets used by IWPO's own protocol therefore live exclusively in
	// http_dll's table; the game's extension functions stay untouched. This also
	// means gm82buf-only games get full socket support from http_dll for free.
	{
		// P2: verify the shipped DLL actually exports md5_dir before wiring the
		// native fast path. external_define on a missing export is a HARD
		// startup error ("Error defining an external function", fish verified),
		// so the define is only generated when the export provably exists; an
		// old DLL in lib/ (or a failed rebuild) silently keeps the pure-GML
		// hash fallback instead of producing a broken exe.
		await EnsureX86HttpDllBuilt();
		const md5DirExportPresent = dllExportsFunction(path.join(__dirname, "lib", HTTP_DLL_FILENAME), "md5_dir");
		console.log(`HTTP DLL md5_dir export: ${md5DirExportPresent ? "available" : "missing"} (native package hash ${md5DirExportPresent ? "enabled" : "falls back to pure GML"})`);
		GMLCode.addVariables("HTTPDLL_INIT");
		// P2: the md5.gml native fast path is guarded by #if MD5DIR. GM8 always
		// registers the flag: the wrapper script __ONLINE_md5_dir exists in every
		// build, and the runtime flag global.__ONLINE_md5DirOk (set from the
		// external_define result in __ONLINE_httpdll_init) keeps a build whose
		// DLL lacked the export on the pure-GML fallback.
		GMLCode.addVariables("MD5DIR");
		const HTTP_DLL_NAME: string = "http_dll_2_3.dll";
		interface DllFunc { name: string; dllName: string; ret: string; args: Array<string>; }
		// Map GML-visible function names to http_dll DLL export names + signatures
		const fns: Array<DllFunc> = (hasGm82net || hasGm82buf) ? [
			{ name: "buffer_create", dllName: "buffer_create", ret: "ty_real", args: [] },
			{ name: "buffer_destroy", dllName: "buffer_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_clear", dllName: "buffer_clear", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_u8", dllName: "buffer_read_uint8", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_u16", dllName: "buffer_read_uint16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_u32", dllName: "buffer_read_uint32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_u64", dllName: "buffer_read_uint64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i8", dllName: "buffer_read_int8", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i16", dllName: "buffer_read_int16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i32", dllName: "buffer_read_int32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i64", dllName: "buffer_read_int64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float", dllName: "buffer_read_float32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_double", dllName: "buffer_read_float64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_string", dllName: "buffer_read_string", ret: "ty_string", args: ["ty_real"] },
			{ name: "buffer_write_u8", dllName: "buffer_write_uint8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_u16", dllName: "buffer_write_uint16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_u32", dllName: "buffer_write_uint32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_u64", dllName: "buffer_write_uint64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i8", dllName: "buffer_write_int8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i16", dllName: "buffer_write_int16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i32", dllName: "buffer_write_int32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i64", dllName: "buffer_write_int64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_float", dllName: "buffer_write_float32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_double", dllName: "buffer_write_float64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_string", dllName: "buffer_write_string", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "buffer_load", dllName: "buffer_read_from_file", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "buffer_save", dllName: "buffer_write_to_file", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "socket_create", dllName: "socket_create", ret: "ty_real", args: [] },
			{ name: "socket_connect", dllName: "socket_connect", ret: "ty_real", args: ["ty_real", "ty_string", "ty_real"] },
			{ name: "socket_destroy", dllName: "socket_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_reset", dllName: "socket_reset", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_get_state", dllName: "socket_get_state", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_receive", dllName: "socket_update_read", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_send", dllName: "socket_update_write", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_read_message", dllName: "socket_read_message", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "socket_write_message", dllName: "socket_write_message", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_create", dllName: "udpsocket_create", ret: "ty_real", args: [] },
			{ name: "udpsocket_destroy", dllName: "udpsocket_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "udpsocket_exists", dllName: "udpsocket_exists", ret: "ty_real", args: ["ty_real"] },
			{ name: "udpsocket_start", dllName: "udpsocket_start", ret: "ty_real", args: ["ty_real", "ty_real", "ty_real"] },
			{ name: "udpsocket_set_destination", dllName: "udpsocket_set_destination", ret: "ty_real", args: ["ty_real", "ty_string", "ty_real"] },
			{ name: "udpsocket_send", dllName: "udpsocket_send", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_receive", dllName: "udpsocket_receive", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_get_state", dllName: "udpsocket_get_state", ret: "ty_real", args: ["ty_real"] },
			{ name: "md5_dir", dllName: "md5_dir", ret: "ty_string", args: ["ty_string"] },
		] : [
			// DLL export names used directly (for normal GM8 games)
			{ name: "buffer_create", dllName: "buffer_create", ret: "ty_real", args: [] },
			{ name: "buffer_destroy", dllName: "buffer_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_clear", dllName: "buffer_clear", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_uint8", dllName: "buffer_read_uint8", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_uint16", dllName: "buffer_read_uint16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_uint32", dllName: "buffer_read_uint32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_uint64", dllName: "buffer_read_uint64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int8", dllName: "buffer_read_int8", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int16", dllName: "buffer_read_int16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int32", dllName: "buffer_read_int32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int64", dllName: "buffer_read_int64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float32", dllName: "buffer_read_float32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float64", dllName: "buffer_read_float64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_string", dllName: "buffer_read_string", ret: "ty_string", args: ["ty_real"] },
			{ name: "buffer_write_uint8", dllName: "buffer_write_uint8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_uint16", dllName: "buffer_write_uint16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_uint32", dllName: "buffer_write_uint32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_uint64", dllName: "buffer_write_uint64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int8", dllName: "buffer_write_int8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int16", dllName: "buffer_write_int16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int32", dllName: "buffer_write_int32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int64", dllName: "buffer_write_int64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_float32", dllName: "buffer_write_float32", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_float64", dllName: "buffer_write_float64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_string", dllName: "buffer_write_string", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "buffer_read_from_file", dllName: "buffer_read_from_file", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "buffer_write_to_file", dllName: "buffer_write_to_file", ret: "ty_real", args: ["ty_real", "ty_string"] },
			{ name: "socket_create", dllName: "socket_create", ret: "ty_real", args: [] },
			{ name: "socket_connect", dllName: "socket_connect", ret: "ty_real", args: ["ty_real", "ty_string", "ty_real"] },
			{ name: "socket_destroy", dllName: "socket_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_reset", dllName: "socket_reset", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_get_state", dllName: "socket_get_state", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_update_read", dllName: "socket_update_read", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_update_write", dllName: "socket_update_write", ret: "ty_real", args: ["ty_real"] },
			{ name: "socket_read_message", dllName: "socket_read_message", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "socket_write_message", dllName: "socket_write_message", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_create", dllName: "udpsocket_create", ret: "ty_real", args: [] },
			{ name: "udpsocket_destroy", dllName: "udpsocket_destroy", ret: "ty_real", args: ["ty_real"] },
			{ name: "udpsocket_exists", dllName: "udpsocket_exists", ret: "ty_real", args: ["ty_real"] },
			{ name: "udpsocket_start", dllName: "udpsocket_start", ret: "ty_real", args: ["ty_real", "ty_real", "ty_real"] },
			{ name: "udpsocket_set_destination", dllName: "udpsocket_set_destination", ret: "ty_real", args: ["ty_real", "ty_string", "ty_real"] },
			{ name: "udpsocket_send", dllName: "udpsocket_send", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_receive", dllName: "udpsocket_receive", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "udpsocket_get_state", dllName: "udpsocket_get_state", ret: "ty_real", args: ["ty_real"] },
			{ name: "md5_dir", dllName: "md5_dir", ret: "ty_string", args: ["ty_string"] },
		];
		// UTF-8 helpers from http_dll are needed whenever the runtime string mode is UTF-8,
		// i.e. GM 8.1+ hosts (worldCreate.gml's `#if CJKTEXT` block calls `set_utf8_mode(1)`
		// to switch http_dll into UTF-8 interpretation). GM 8.0 always uses the FoxWriting
		// backend with useUtf8=false, so these wrappers are never needed there.
		if (useUtf8) {
			fns.push({ name: "ansi_to_utf8", dllName: "ansi_to_utf8", ret: "ty_string", args: ["ty_string"] });
			fns.push({ name: "set_utf8_mode", dllName: "set_utf8_mode", ret: "ty_real", args: ["ty_real"] });
		}
		// Generate init script
		const initLines: Array<string> = [`var dll; dll = "${HTTP_DLL_NAME}";`];
		for (const fn of fns) {
			if (fn.dllName === "md5_dir") {
				// P2: the define is emitted only when the DLL provably exports
				// md5_dir (verified above by walking the DLL's PE export table).
				if (md5DirExportPresent) {
					initLines.push(`global.__od_md5_dir = external_define(dll,'md5_dir',dll_cdecl,ty_string,1,ty_string);`);
				} else {
					initLines.push("global.__od_md5_dir = -1;");
				}
				continue;
			}
			const argTypes: string = fn.args.length > 0 ? "," + fn.args.join(",") : "";
			initLines.push(`global.__od_${fn.dllName} = external_define(dll,'${fn.dllName}',dll_cdecl,${fn.ret},${fn.args.length}${argTypes});`);
		}
		// P2: runtime capability flag for the md5_dir fast path.
		initLines.push("global.__ONLINE_md5DirOk = 0;");
		initLines.push("if(global.__od_md5_dir >= 0) global.__ONLINE_md5DirOk = 1;");
		const initScript: Script = new Script();
		initScript.name = Buffer.from("__ONLINE_httpdll_init", "ascii");
		initScript.source = Buffer.from(initLines.join("\r\n"), "ascii");
		scripts.push(initScript);
		// Generate wrapper scripts for each function
		for (const fn of fns) {
			const wrapper: Script = new Script();
			wrapper.name = Buffer.from("__ONLINE_" + fn.name, "ascii");
			const argList: string = fn.args.map((_, i) => `argument${i}`).join(",");
			const callArgs: string = fn.args.length > 0 ? "," + argList : "";
			wrapper.source = Buffer.from(`return external_call(global.__od_${fn.dllName}${callArgs});`, "ascii");
			scripts.push(wrapper);
		}
	}
	// Synthesize GML stub scripts for any IWPO-required extension function whose
	// extension package wasn't injected. Without these, the converted game would
	// fail to compile injected GML that references e.g. wd_input_box / fw_draw_text_ext.
	{
		const addStubScript = function(name: string, source: string): void {
			const script: Script = new Script();
			script.name = Buffer.from(name, "ascii");
			script.source = Buffer.from(source, "ascii");
			scripts.push(script);
		};
		if(!loadedWD){
			addStubScript("wd_input_box", "return get_string(argument1, argument2);");
			addStubScript("wd_message_simple", "show_message(argument0); return 0;");
			addStubScript("wd_message_set_text", "global.__ONLINE_wdMessageText = argument0; return 0;");
			addStubScript("wd_message_show", "if(variable_global_exists(\"__ONLINE_wdMessageText\")){ show_message(global.__ONLINE_wdMessageText); } return 0;");
		}
		// fw_* stubs are needed whenever the GML emits the fw_* branch (cjkBackend === 'fw'
		// with no real FoxWriting). gm_* stubs are needed when the GML emits the gm_* branch
		// (cjkBackend === 'gm' with no real GaseousMarble — rare; mostly defensive).
		// With FoxWriting unavailable we no longer emit no-op stubs: gml/cjkAtlas.gml is a
		// pure-GML bitmap-atlas pack that implements the same fw_* API surface on top of
		// __ONLINE_font.png + __ONLINE_font.gbk, so CJK text still renders with no DLL.
		// (UPX + Antidec GM8.0 runners cannot host FoxWriting at all - see 945b287.)
		if(cjkBackend === 'fw' && !loadedFW){
			atlasCjkActive = true;
			// Optical baseline shift for the bitmap atlas (iwpo.cjk.yoffset).
			// The 16pt atlas face carries its ink ~6 px higher in the GM line box
			// than the FoxWriting/GDI+ text the HUD and note offsets were tuned
			// against, so the glyphs are dropped by that much by default.
			const cjkYOffsetRaw: string = defines.has("iwpo.cjk.yoffset") ? (defines.get("iwpo.cjk.yoffset") as string).trim() : "";
			let cjkYOffset: number = 6;
			if(cjkYOffsetRaw !== ""){
				const parsed: number = Number(cjkYOffsetRaw);
				if(Number.isFinite(parsed)) cjkYOffset = parsed;
				else console.warn(`[cjk] iwpo.cjk.yoffset="${cjkYOffsetRaw}" is not a number; using ${cjkYOffset}`);
			}
			const atlasSections: Array<{name: string, code: Buffer}> = splitMarkedScripts(await GMLCode.getGML("cjkAtlas", Buffer.from(String(cjkYOffset), 'ascii')));
			if(atlasSections.length === 0)
				throw new Error(`gml/cjkAtlas.gml has no "///// script <name>" sections`);
			for(const section of atlasSections){
				const atlasScript: Script = new Script();
				atlasScript.name = Buffer.from(section.name, 'ascii');
				atlasScript.source = section.code;
				scripts.push(atlasScript);
			}
			console.log(`[cjk] FoxWriting unavailable; GML atlas renderer active (${atlasSections.length} scripts, GB2312 atlas, yOffset=${cjkYOffset}, no DLL)`);
		}
		if(cjkBackend === 'gm' && !loadedGM){
			addStubScript("gm_font", "return 0;");
			addStubScript("gm_set_font", "return 0;");
			addStubScript("gm_set_color", "draw_set_color(argument0); return 0;");
			addStubScript("gm_set_alpha", "draw_set_alpha(argument0); return 0;");
			addStubScript("gm_set_halign", "draw_set_halign(argument0 + 1); return 0;");
			addStubScript("gm_set_valign", "draw_set_valign(argument0 + 1); return 0;");
			addStubScript("gm_set_max_line_length", "global.__ONLINE_gmMaxLineLength = argument0; return 0;");
			addStubScript("gm_draw", "if(!variable_global_exists(\"__ONLINE_gmMaxLineLength\")) global.__ONLINE_gmMaxLineLength = 0; if(global.__ONLINE_gmMaxLineLength > 0) draw_text_ext(argument0, argument1, argument2, -1, global.__ONLINE_gmMaxLineLength); else draw_text(argument0, argument1, argument2); return 0;");
			addStubScript("gm_width", "if(!variable_global_exists(\"__ONLINE_gmMaxLineLength\")) global.__ONLINE_gmMaxLineLength = 0; if(global.__ONLINE_gmMaxLineLength > 0) return string_width_ext(argument0, -1, global.__ONLINE_gmMaxLineLength); return string_width(argument0);");
			addStubScript("gm_height", "if(!variable_global_exists(\"__ONLINE_gmMaxLineLength\")) global.__ONLINE_gmMaxLineLength = 0; if(global.__ONLINE_gmMaxLineLength > 0) return string_height_ext(argument0, -1, global.__ONLINE_gmMaxLineLength); return string_height(argument0);");
		}
	}
	const newIncludedfile = function(file: string): IncludedFile {
		let includedfile = new IncludedFile();
		includedfile.fileName = Buffer.from(file, 'ascii');
		includedfile.sourcePath = Buffer.from("C:\\" + file, 'ascii');
		includedfile.dataExists = true;
		includedfile.sourceLength = fs.statSync(path.join(__dirname, "lib", file))["size"];
		includedfile.storedInGmk = true;
		includedfile.embeddedData = fs.readFileSync(path.join(__dirname, "lib", file));
		includedfile.exportSettings = 0;
		includedfile.customFolder = Buffer.from("");
		includedfile.overwriteFile = true;
		includedfile.freeMemory = true;
		includedfile.removeAtEnd = true;
		return includedfile;
	}
	const newIncludedfileFromPath = function(fileName: string, sourcePath: string): IncludedFile {
		let includedfile = new IncludedFile();
		includedfile.fileName = Buffer.from(fileName, 'ascii');
		includedfile.sourcePath = Buffer.from(sourcePath, 'ascii');
		includedfile.dataExists = true;
		includedfile.sourceLength = fs.statSync(sourcePath)["size"];
		includedfile.storedInGmk = true;
		includedfile.embeddedData = fs.readFileSync(sourcePath);
		includedfile.exportSettings = 0;
		includedfile.customFolder = Buffer.from("");
		includedfile.overwriteFile = true;
		includedfile.freeMemory = true;
		includedfile.removeAtEnd = true;
		return includedfile;
	}
	const gm80AsciiFontCandidates: string[] = [];
	if(typeof process.env.WINDIR === "string" && process.env.WINDIR.length > 0)
		gm80AsciiFontCandidates.push(path.join(process.env.WINDIR, "Fonts", "BRLNSDB.TTF"));
	gm80AsciiFontCandidates.push(path.join("C:\\Windows", "Fonts", "BRLNSDB.TTF"));
	let gm80AsciiFontPath: string | null = null;
	if(gameConfig.version === GameVersion.GameMaker80){
		for(const candidate of gm80AsciiFontCandidates){
			if(fs.existsSync(candidate)){
				gm80AsciiFontPath = candidate;
				break;
			}
		}
	}
	// Parse room names for dynamic save room guards (rooms section follows objects in GM8 format)
	if(exe.readUInt32LE() != 800)
		throw new Error("Rooms header");
	const roomOffsets: [number, number] = [exe.readOffset, 0];
	const roomRefs: Array<Buffer> = getAssetRefs(exe);
	roomOffsets[1] = exe.readOffset;
	const roomNames: Set<string> = new Set<string>();
	for(const ref of roomRefs){
		const inflated: Buffer = inflateBuffer(ref);
		if(inflated.length >= 8 && inflated.readUInt32LE(0) !== 0){
			const nameLen: number = inflated.readUInt32LE(4);
			if(inflated.length >= 8 + nameLen)
				roomNames.add(inflated.slice(8, 8 + nameLen).toString('ascii'));
		}
	}
	const menuRoomPatterns: Array<string> = [
		"rSelectStage", "rInit", "rTitle", "rMenu", "rOptions",
		"rmInit", "rmTitle", "rmMenu", "rmOptions", "rmSelectStage",
	];
	const existingMenuRooms: Array<string> = menuRoomPatterns.filter(name => roomNames.has(name));
	const roomGuard: string = existingMenuRooms.length > 0
		? existingMenuRooms.map(r => `room != ${r}`).join(" && ")
		: "true";
	// Included files: always read through the section. Inject sound files for gm82snd,
	// and inject GaseousMarble font files for CJK text rendering.
	let lastInstanceId: number = -1;
	{
		const lastInstanceIdPos: number = exe.readOffset;
		lastInstanceId = exe.readInt32LE(); //last_instance_id
		exe.readInt32LE(); //last_tile_id
		if(customWorld){
			// Reserve an instance id for the custom world instance inserted below.
			exe.writeOffset = lastInstanceIdPos;
			exe.writeInt32LE(lastInstanceId + 1);
		}
		if(exe.readUInt32LE() != 800)
			throw new Error("Included files header");
		const includedfilesOffsets: [number, number] = [exe.readOffset, 0];
		let includedfiles: Array<IncludedFile> = getAssetRefs(exe).map((chunk: Buffer) => { 
			const data: SmartBuffer = SmartBuffer.fromBuffer(inflateBuffer(chunk));
			return IncludedFile.deserialize(data, gameConfig);
		}) as Array<IncludedFile>;
		includedfilesOffsets[1] = exe.readOffset;
		if (hasGm82snd) {
			includedfiles.push(newIncludedfile("__ONLINE_sndChatbox.wav"));
			includedfiles.push(newIncludedfile("__ONLINE_sndSaved.wav"));
		}
		if (gm80AsciiFontPath !== null && !atlasCjkActive) {
			const asciiFont: IncludedFile = newIncludedfileFromPath("__ONLINE_ascii.ttf", gm80AsciiFontPath);
			asciiFont.exportSettings = 2; // Export to game directory (working_directory)
			includedfiles.push(asciiFont);
		}
		// GaseousMarble font files — deployed whenever the GM backend is selected
		// (works on both GM 8.0 and GM 8.1; the legacy version gate was overly restrictive).
		if (cjkBackend === 'gm') {
			const fontPng: IncludedFile = newIncludedfile("__ONLINE_font.png");
			fontPng.exportSettings = 2; // Export to game directory (working_directory)
			includedfiles.push(fontPng);
			const fontGly: IncludedFile = newIncludedfile("__ONLINE_font.gly");
			fontGly.exportSettings = 2; // Export to game directory (working_directory)
			includedfiles.push(fontGly);
		}
		// GML atlas CJK font (the fw-unavailable fallback): the renderer loads both
		// files from the game directory at first use. The TTF above is not needed in
		// that mode (fw_add_font_from_file is served by the atlas).
		if (atlasCjkActive) {
			const atlasPng: IncludedFile = newIncludedfile("__ONLINE_font.png");
			atlasPng.exportSettings = 2;
			includedfiles.push(atlasPng);
			const atlasIdx: IncludedFile = newIncludedfile("__ONLINE_font.gbk");
			atlasIdx.exportSettings = 2;
			includedfiles.push(atlasIdx);
		}

		replaceChunk(exe, includedfilesOffsets, putAssetRefs(exe, includedfiles));
	}
	// C2: place the custom world object as the first instance of the first room
	// (room_order[0]). asset/room.ts has no serialize path, so this is a byte-level
	// splice: locate the instance count inside the inflated room chunk and insert a
	// raw instance record there; every other byte is preserved verbatim.
	if(customWorld){
		if(exe.readUInt32LE() != 800)
			throw new Error("Help dialog header");
		const helpDialogLength: number = exe.readUInt32LE();
		exe.readOffset += helpDialogLength; // help dialog buffer
		if(exe.readUInt32LE() != 500)
			throw new Error("Action library initialization code header");
		getAssetRefs(exe); // not technically asset references but stored in the same <count> [<len> <buffer>] format
		if(exe.readUInt32LE() != 700)
			throw new Error("Room order lookup header");
		const roomOrderCount: number = exe.readUInt32LE();
		if(roomOrderCount == 0)
			throw new Error("No rooms in exe");
		const firstRoomIndex: number = exe.readInt32LE(); // room_order[0]
		if(firstRoomIndex < 0 || firstRoomIndex >= roomRefs.length)
			throw new Error("First room index out of range");
		const insertWorldInstance = function(chunk: Buffer): Buffer {
			const raw: Buffer = inflateBuffer(chunk);
			if(raw.length < 4 || raw.readUInt32LE(0) === 0)
				throw new Error("First room is null");
			const data: SmartBuffer = SmartBuffer.fromBuffer(raw);
			data.readOffset = 4; // exists flag
			const roomNameLength: number = data.readUInt32LE();
			data.readOffset += roomNameLength; // name
			const entryVersion: number = data.readUInt32LE();
			const captionLength: number = data.readUInt32LE();
			data.readOffset += captionLength; // caption
			const roomWidth: number = data.readUInt32LE();
			const roomHeight: number = data.readUInt32LE();
			data.readOffset += 8; // speed, persistent
			data.readOffset += 4; // bgColour (4 bytes)
			data.readOffset += 4; // clearScreen/clearRegion flags
			const creationCodeLength: number = data.readUInt32LE();
			data.readOffset += creationCodeLength; // room creation code
			const backgroundCount: number = data.readUInt32LE();
			data.readOffset += backgroundCount * 40; // 10 dwords each
			data.readOffset += 4; // viewsEnabled
			const viewCount: number = data.readUInt32LE();
			data.readOffset += viewCount * 56; // 14 dwords each
			const instanceCountPos: number = data.readOffset;
			const instanceCount: number = data.readUInt32LE();
			const inst: SmartBuffer = new SmartBuffer();
			inst.writeInt32LE(Math.floor(roomWidth / 2));
			inst.writeInt32LE(Math.floor(roomHeight / 2));
			inst.writeInt32LE(customWorldObjectId);
			inst.writeInt32LE(lastInstanceId + 1);
			inst.writeUInt32LE(0); // empty creation code
			if(entryVersion >= 810){
				inst.writeDoubleLE(1.0); // xscale
				inst.writeDoubleLE(1.0); // yscale
				inst.writeUInt32LE(0xFFFFFFFF); // blend
			}
			if(entryVersion >= 811){
				inst.writeDoubleLE(0.0); // angle
			}
			const newCount: Buffer = Buffer.alloc(4);
			newCount.writeUInt32LE(instanceCount + 1, 0);
			const updated: Buffer = concatBuffers([
				raw.subarray(0, instanceCountPos),
				newCount,
				inst.internalBuffer.subarray(0, inst.length),
				raw.subarray(instanceCountPos + 4),
			]);
			inst.destroy();
			data.destroy();
			return deflateBuffer(updated);
		}
		roomRefs[firstRoomIndex] = insertWorldInstance(roomRefs[firstRoomIndex]);
		const roomsData: SmartBuffer = new SmartBuffer();
		roomsData.writeUInt32LE(roomRefs.length);
		for(const roomRef of roomRefs){
			roomsData.writeUInt32LE(roomRef.length);
			roomsData.writeBuffer(roomRef);
		}
		replaceChunk(exe, roomOffsets, roomsData.internalBuffer.subarray(0, roomsData.length));
		roomsData.destroy();
	}
	// gameName encoding: tied to the runtime string mode chosen by the CJK backend.
	//   useUtf8 == true  (GM 8.1+ default, or GM 8.0+'gm' backend with set_utf8_mode(1)):
	//     emit UTF-8 directly; http_dll, GaseousMarble and GM string ops all agree.
	//   useUtf8 == false (GM 8.0 + 'fw'|'none'):
	//     emit GBK byte pairs; FoxWriting and http_dll (no UTF-8 mode) both expect GBK.
	const gameNameBuf: Buffer = useUtf8
		? Buffer.from(gameName)
		: iconv.encode(gameName, "gbk");
	// ===== Skin system injection (T1 script assets + T2 player Draw hooks) =====
	// T1 is unconditional: worldCreate/worldEndStep call __ONLINE_skin_scan,
	// __ONLINE_skin_mirror & co. in every converted game, so the script assets
	// must always exist (they stay inert without an iwposkins\ folder). T2/T3
	// remain gated behind iwpo.no_skins.
	{
		// T1: md5.gml and skinLib.gml are section packs — every `///// script <name>`
		// section becomes a standalone script asset (same push pattern as
		// __ONLINE_gbk_trunc below). Section names already carry the __ONLINE_
		// prefix, applied by the render pipeline's @ substitution.
		const skinScriptNames: Set<string> = new Set<string>();
		// Guard against colliding with a game-owned script of the same name
		// (the GMS converter already checks Data.Scripts.ByName).
		for(const existing of scripts){
			if(existing && existing.name){
				const n: string = existing.name.toString('ascii');
				if(n.startsWith("__ONLINE_"))
					skinScriptNames.add(n);
			}
		}
		for(const packFile of ["md5", "skinLib", "bulletShare", "notesLib", "accountLib", "settingsLib", "langLib"]){
			const sections: Array<{name: string, code: Buffer}> = splitMarkedScripts(await renderSkinGml(packFile));
			if(sections.length === 0)
				throw new Error(`Skin system GML gml/${packFile}.gml has no "///// script <name>" sections`);
			for(const section of sections){
				if(!section.name.startsWith("__ONLINE_"))
					console.warn(`[skins] ${packFile}.gml section "${section.name}" lacks the __ONLINE_ prefix; injected as-is`);
				if(skinScriptNames.has(section.name))
					throw new Error(`Skin system GML: duplicate script section "${section.name}"`);
				skinScriptNames.add(section.name);
				const skinScript: Script = new Script();
				skinScript.name = Buffer.from(section.name, 'ascii');
				skinScript.source = section.code;
				scripts.push(skinScript);
			}
			console.log(`[skins] ${packFile}.gml -> ${sections.length} script(s): ${sections.map(section => section.name).join(", ")}`);
		}
	}
	if(skinsEnabled){
		// T2: playerDrawInject.gml carries three `///// mode <name>` sections.
		// Objects without a Draw event get the replace section. Objects that
		// already draw themselves default to preempt: their single code action
		// is textually wrapped so the skin draws INSTEAD of the game's own
		// draw (GM8 `exit` would only leave the current action, hence the
		// if-wrap instead of GMS's prepend+exit). Multi-action Draw events
		// (and iwpo.skins.overlay=1) fall back to the appended overlay.
		const drawSections: Array<{name: string, code: Buffer}> = splitMarkedSections(await renderSkinGml("playerDrawInject"), "mode");
		const findDrawMode = function(modeName: string): Buffer {
			const hits: Array<{name: string, code: Buffer}> = drawSections.filter(section => section.name.toLowerCase() === modeName);
			return hits.length > 0 ? hits[0].code : null;
		}
		const drawReplaceCode: Buffer = findDrawMode("replace");
		const drawPreemptCode: Buffer = findDrawMode("preempt");
		const drawOverlayCode: Buffer = findDrawMode("overlay");
		if(drawReplaceCode === null || drawPreemptCode === null || drawOverlayCode === null)
			throw new Error(`Skin system GML gml/playerDrawInject.gml must contain "///// mode replace", "///// mode preempt" and "///// mode overlay" sections`);
		const overlayRaw: string = defines.has("iwpo.skins.overlay") ? (defines.get("iwpo.skins.overlay") as string).toLowerCase() : "";
		const forceOverlay: boolean = overlayRaw === "true" || overlayRaw === "1";
		for(const skinTarget of skinTargetObjects){
			const skinTargetName: string = skinTarget.name.toString('ascii');
			if(!skinTarget.hasEvent(8, 0)){ // Draw event = category 8, subtype 0
				skinTarget.addDrawCode(drawReplaceCode);
				console.log(`[skins] ${skinTargetName}: no Draw event -> replace injected`);
				continue;
			}
			if(forceOverlay){
				skinTarget.addDrawCode(drawOverlayCode);
				console.log(`[skins] ${skinTargetName}: existing Draw event -> overlay appended (iwpo.skins.overlay)`);
				continue;
			}
			const drawEntry = skinTarget.events[8].find(element => element[0] == 0 && element[1].length > 0);
			const drawActions = drawEntry ? drawEntry[1] : [];
			if(drawActions.length == 1 && drawActions[0].actionKind == 7){
				// Preempt: wrap the game's own draw code so it only runs when
				// no skin was drawn. The wrap literal is post-substitution, so
				// it spells the __ONLINE_ prefix in full.
				const original: Buffer = drawActions[0].paramStrings[0];
				drawActions[0].paramStrings[0] = Buffer.concat([
					drawPreemptCode,
					Buffer.from("\nif(!__ONLINE_skPre){\n", 'ascii'),
					original,
					Buffer.from("\n}", 'ascii'),
				]);
				console.log(`[skins] ${skinTargetName}: existing Draw event -> preempt wrap`);
			}else{
				skinTarget.addDrawCode(drawOverlayCode);
				console.log(`[skins] ${skinTargetName}: multi-action/non-code Draw event -> overlay appended (preempt needs a single code action)`);
			}
		}
	}
	world.addCreateCode(await GMLCode.getGML("worldCreate", Buffer.from(uniqueKey,'ascii'), Buffer.from(server,'ascii'), Buffer.from(ports.tcp.toString(), 'ascii'), Buffer.from(ports.udp.toString(),'ascii'), gameNameBuf, Buffer.from(Utils.getVersion(), 'ascii'), Buffer.from(playerListInitCode, 'ascii'), Buffer.from(skinSpriteBase.toString(), 'ascii'), Buffer.from(bulletObjIdx.toString(), 'ascii'), Buffer.from(bulletSprIdx.toString(), 'ascii')));
	// T3: the generated sprite-state map runs right after the worldCreate template
	// (addCreateCode appends code actions in call order). The block spells
	// __ONLINE_ names in full — it never passes through the @ substitution.
	// (The S4 bullet constants are NOT appended here: they are baked into the
	// template as %arg9/%arg10 so they are assigned BEFORE @bullet_init runs.)
	if(skinsEnabled && skinMapCode !== "")
		world.addCreateCode(Buffer.from(skinMapCode, 'ascii'));
	// Opt-in compatibility path: keep EndStep as the default, but allow Step
	// injection plus world-driven helper ticks for GM8.2/yuuutu edge cases.
	const addTickRaw = function(obj: GMObject, gml: Buffer, tickEventName: TickEventName): void {
		if(tickEventName === "step") obj.addStepCode(gml);
		else obj.addEndStepCode(gml);
	};
	const addTick = function(obj: GMObject, gml: Buffer, tickEventName: TickEventName): void {
		addTickRaw(obj, gml, tickEventName);
	};
	const worldTickEventName: TickEventName = injectIntoStep ? "step" : "endstep";
	const newObject = function(name: Buffer, visible: boolean, depth: number, persistent: boolean): GMObject {
		const obj: GMObject = new GMObject();
		obj.name = name;
		obj.spriteIndex = -1;
		obj.solid = false;
		obj.visible = visible;
		obj.depth = depth;
		obj.persistent = persistent;
		obj.parentIndex = -1;
		obj.maskIndex = -1;
		obj.events = [[], [], [], [], [], [], [], [], [], [], [], []];
		return obj;
	}
	// 3D-HUD research (RESEARCH_GM8_3D_HUD.md): the screen-space HUD runs under a
	// forced window-pixel ortho projection parked on the near plane. In games that
	// use d3d themselves the runner's z-buffer can still be live at that point and
	// eats those primitives (TUNNEL VISION: HUD silently invisible), so GAME_D3D
	// builds wrap the HUD draw in d3d_set_hidden(false)/(true) - the same pattern
	// those games' own 2D overlays use (e.g. objHubTransIn). Must run before the
	// getGML calls below so worldDrawGui/playerSavedDraw pick up the flag.
	// Lighting/culling could still distort the HUD; no known game needs those
	// wraps, so for now just warn at convert time.
	const d3dUse: Set<string> = new Set();
	const scanD3d = function(code: string): void {
		if(/\bd3d_start\s*\(|\bd3d_draw_/.test(code)) d3dUse.add("d3d");
		if(/\bd3d_set_lighting\s*\(\s*(true|1)\b|\bd3d_light_define/.test(code)) d3dUse.add("lighting");
		if(/\bd3d_set_culling\s*\(\s*(true|1)\b/.test(code)) d3dUse.add("culling");
		if(/\bd3d_set_fog\s*\(\s*(true|1)\b/.test(code)) d3dUse.add("fog");
	};
	for(const scanObj of objects){
		if(!scanObj || !scanObj.events) continue;
		for(const scanEvList of scanObj.events){
			for(const [, scanActions] of scanEvList){
				for(const scanAction of scanActions){
					if(scanAction.paramStrings && scanAction.paramStrings[0])
						scanD3d(scanAction.paramStrings[0].toString('latin1'));
				}
			}
		}
	}
	for(const scanScript of scripts){
		if(scanScript && scanScript.source) scanD3d(scanScript.source.toString('latin1'));
	}
	// Timeline moments (collected before the timelines table was dropped).
	for(const extraCode of extraD3dCode) scanD3d(extraCode);
	// Room creation code is the classic d3d_start() location, but only the
	// first room is ever inflated (world instance injection) - inflate every
	// chunk here read-only, walk the header up to the creation code, scan and
	// discard. A missed d3d game would silently lose the z-buffer wrap.
	for(const roomRef of roomRefs){
		try{
			const roomRaw: Buffer = inflateBuffer(roomRef);
			if(roomRaw.length < 4 || roomRaw.readUInt32LE(0) === 0) continue;
			const roomData: SmartBuffer = SmartBuffer.fromBuffer(roomRaw);
			roomData.readOffset = 4; // exists flag
			roomData.readOffset += roomData.readUInt32LE(); // name
			roomData.readOffset += 4; // version
			roomData.readOffset += roomData.readUInt32LE(); // caption
			roomData.readOffset += 24; // w,h / speed,persistent / bgColour / clearFlags
			const roomCodeLen: number = roomData.readUInt32LE();
			if(roomCodeLen > 0 && roomData.readOffset + roomCodeLen <= roomRaw.length)
				scanD3d(roomRaw.toString('latin1', roomData.readOffset, roomData.readOffset + roomCodeLen));
		}catch{ /* malformed room chunk: skip */ }
	}
	if(d3dUse.has("d3d")) GMLCode.addVariables("GAME_D3D");
	if(d3dUse.size > 0)
		console.log(`[hud] game uses ${[...d3dUse].join("/")}` +
			(d3dUse.has("d3d") ? "; HUD z-buffer wrap enabled" : "; window-ortho HUD prelude active") +
			(d3dUse.has("lighting") || d3dUse.has("culling") ? " (WARNING: lighting/culling may distort the HUD - needs state wraps)" : ""));
	const onlinePlayer: GMObject = newObject(Buffer.from("__ONLINE_onlinePlayer", 'ascii'), false, -10, true);
	onlinePlayer.addCreateCode(await GMLCode.getGML("onlinePlayerCreate"));
	const onlinePlayerTick: Buffer = await GMLCode.getGML("onlinePlayerEndStep", player.name, player2 ? player2.name : Buffer.from(""), world.name);
	onlinePlayer.addDrawCode(await GMLCode.getGML("onlinePlayerDraw", world.name));
	const chatbox: GMObject = newObject(Buffer.from("__ONLINE_chatbox",'ascii'), true, -11, true);
	chatbox.addCreateCode(await GMLCode.getGML("chatboxCreate"));
	const chatboxTick: Buffer = await GMLCode.getGML("chatboxEndStep", player.name, player2 ? player2.name : Buffer.from(""), world.name);
	chatbox.addDrawCode(await GMLCode.getGML("chatboxDraw"));
	// Depth just above the UI object (drawn second-to-last): keeps toasts on
	// top of game-side HUD instances and shrinks the projection-leak surface
	// (anything drawn after us in the same view inherits our ortho until the
	// end-of-event restore - at this depth that is only the UI object, which
	// sets its own projection immediately).
	const playerSaved: GMObject = newObject(Buffer.from("__ONLINE_playerSaved",'ascii'), true, -2147483647, false);
	playerSaved.addCreateCode(await GMLCode.getGML("playerSavedCreate"));
	const playerSavedTick: Buffer = await GMLCode.getGML("playerSavedEndStep");
	const playerSavedDrawGml: Buffer = await GMLCode.getGML("playerSavedDraw");
	// Runtime self-heal for isGM82 false positives (a GM8.0/8.1 game whose
	// runner would treat group 11 as never-dispatched triggers): alongside the
	// native Draw GUI copy, register a regular-Draw fallback gated on
	// global.__ONLINE_guiAlive (initialized false in worldCreate). The GUI copy
	// sets the flag on its first run, so on a real GM8.2 runner the fallback
	// draws at most once (frame 1, before the GUI pass); on a misdetected game
	// the GUI event never fires and the fallback keeps the HUD alive instead
	// of vanishing silently (E2). The fallback ends with the same projection
	// restore the GM8.0/8.1 template path uses.
	const guiFallbackRestore: string = "\r\nif(view_enabled){\r\n	d3d_set_projection_ortho(view_xview[view_current], view_yview[view_current], view_wview[view_current], view_hview[view_current], view_angle[view_current]);\r\n}else{\r\n	d3d_set_projection_ortho(0, 0, room_width, room_height, 0);\r\n}\r\n";
	if(isGM82){
		playerSaved.addDrawGuiCode(concatBuffers([
			Buffer.from("global.__ONLINE_guiAlive = true;\r\n", 'ascii'),
			playerSavedDrawGml,
		]), drawGuiSubType); // screen-space: GM8.2 native Draw GUI (see below)
		playerSaved.addDrawCode(concatBuffers([
			Buffer.from("if(!global.__ONLINE_guiAlive){\r\n", 'ascii'),
			playerSavedDrawGml,
			Buffer.from(guiFallbackRestore + "}\r\n", 'ascii'),
		]));
	}else{
		playerSaved.addDrawCode(playerSavedDrawGml);
	}
	addTick(world, await GMLCode.getGML("worldEndStep", player.name, player2 ? player2.name : Buffer.from("")), worldTickEventName);
	if(injectIntoStep){
		const helperScheduler: Buffer = concatBuffers([
			Buffer.from(`instance_activate_object(${onlinePlayer.name.toString('ascii')});\r\ninstance_activate_object(${chatbox.name.toString('ascii')});\r\ninstance_activate_object(${playerSaved.name.toString('ascii')});\r\n`, 'ascii'),
			withGMLObject(onlinePlayer.name, localizeExitForWith(onlinePlayerTick)),
			withGMLObject(chatbox.name, localizeExitForWith(chatboxTick)),
			withGMLObject(playerSaved.name, localizeExitForWith(playerSavedTick)),
		]);
		addTickRaw(world, helperScheduler, worldTickEventName);
	}else{
		addTick(onlinePlayer, onlinePlayerTick, "endstep");
		addTick(chatbox, chatboxTick, "endstep");
		addTick(playerSaved, playerSavedTick, "endstep");
	}
	world.addGameEndCode(await GMLCode.getGML("worldGameEnd"));
	const ui: GMObject = newObject(Buffer.from("__ONLINE_userInterface",'ascii'), true, -2147483648, true);
	const drawGml: Buffer = await GMLCode.getGML("worldDraw");
	const drawGuiGml: Buffer = await GMLCode.getGML("worldDrawGui");
	const worldName: string = world.name.toString('ascii');
	const wrapWithWorld = function(gml: Buffer): Buffer {
		return concatBuffers([
			Buffer.from(`if(instance_exists(${worldName})){\r\nwith(instance_find(${worldName}, 0)){\r\n`, 'utf8'),
			gml,
			Buffer.from(`\r\n}\r\n}\r\n`, 'utf8')
		]);
	};
	// World-space overlays first (they need the game's own projection), then the
	// screen-space HUD. On GM8.2 the HUD goes into the native Draw GUI event
	// (group 11): regular Draw output is silently invisible in d3d-started rooms
	// (TUNNEL VISION E1 probe: group-8 text never rasterizes there, group-11
	// does), and the GUI pass is also what the game's own 2D overlays use.
	// GM8.0/8.1 runners dispatch group 11 as triggers, so they keep the
	// regular-Draw path (verified in 2D rooms).
	ui.addDrawCode(wrapWithWorld(drawGml));
	if(isGM82){
		ui.addDrawGuiCode(concatBuffers([
			Buffer.from("global.__ONLINE_guiAlive = true;\r\n", 'ascii'),
			wrapWithWorld(drawGuiGml),
		]), drawGuiSubType);
		// group-8 self-heal fallback (see the guiAlive note at playerSaved)
		ui.addDrawCode(concatBuffers([
			Buffer.from("if(!global.__ONLINE_guiAlive){\r\n", 'ascii'),
			wrapWithWorld(drawGuiGml),
			Buffer.from(guiFallbackRestore + "}\r\n", 'ascii'),
		]));
	}else{
		ui.addDrawCode(wrapWithWorld(drawGuiGml));
	}
	if(customWorld)
		objects.push(world); // must stay the first of the new objects; its index was reserved as customWorldObjectId
	objects.push(onlinePlayer);
	objects.push(chatbox);
	objects.push(playerSaved);
	objects.push(ui);
	// S4: bullet-sharing proxy object. Sprite/depth/mask are copied from the
	// game's bullet object at convert time (static; object_set_* would be a
	// runtime dependency we do not need), so @bullet_init only creates the
	// registry map. Draw/EndStep templates carry the player/world names and
	// the per-game hit action (iwpo.bullet.hit, empty = no collision action).
	// bulletObjIdx/bulletSprIdx were resolved earlier (skins-enabled only;
	// -1/-1 disables sharing) and are baked into the worldCreate template.
	const bulletProxy: GMObject = newObject(Buffer.from("__ONLINE_bullet", 'ascii'), true, bulletObjIdx >= 0 ? objects[bulletObjIdx].depth : 0, false);
	if(bulletObjIdx >= 0){
		bulletProxy.spriteIndex = objects[bulletObjIdx].spriteIndex;
		bulletProxy.maskIndex = objects[bulletObjIdx].maskIndex;
	}
	bulletProxy.addCreateCode(await GMLCode.getGML("bulletShareCreate"));
	const bulletHitCode: string = defines.has("iwpo.bullet.hit") ? (defines.get("iwpo.bullet.hit") as string) : "";
	// S5: %arg3 = the PVP kill call (e.g. "killPlayer();"), empty when
	// unavailable - the gate in the template then never fires.
	const pvpKillCall: string = pvpKillScript !== "" ? pvpKillScript + "();" : "";
	bulletProxy.addEndStepCode(await GMLCode.getGML("bulletShareEndStep", player.name, player2 ? player2.name : Buffer.from(""), Buffer.from(bulletHitCode, 'ascii'), Buffer.from(pvpKillCall, 'ascii')));
	bulletProxy.addDrawCode(await GMLCode.getGML("bulletShareDraw", world.name));
	objects.push(bulletProxy);
	// S4 local-bullet re-skin: give the GAME's bullet object a Draw event so
	// the local player's own bullets render the selected skin's bullet.png.
	// Only when the object had no Draw event (a Draw event suppresses the
	// engine's automatic sprite draw, so the injected template redraws the
	// native sprite as its fallback). Objects that already draw themselves
	// are left alone (their custom draw wins).
	if(bulletObjIdx >= 0){
		const bulletGameObj: GMObject = objects[bulletObjIdx];
		if(bulletGameObj.hasEvent(8, 0)){
			console.log(`[bullets] ${bulletGameObj.name.toString('ascii')} has its own Draw event; local bullet re-skin skipped`);
		}else{
			bulletGameObj.addDrawCode(await GMLCode.getGML("bulletSelfDraw"));
			console.log(`[bullets] ${bulletGameObj.name.toString('ascii')}: local bullet re-skin Draw injected`);
		}
	}
	// Deactivation whitelist (Seven Colors): engines that cull off-screen
	// instances via instance_deactivate_* would also deactivate the online
	// objects - the independent __ONLINE_world is in no game-side whitelist -
	// which kills networking outright. Append explicit re-activation of our
	// objects to any game code block that calls an instance_deactivate_*
	// function, so our objects ride the same per-frame whitelist the game's
	// own world object enjoys. instance_activate_object on an object with no
	// live instances is a no-op, so firing this early is safe; code blocks
	// that bail out via exit/return before the end would skip it, which no
	// known deactivator does (objDeactive-style sweeps run straight-line).
	{
		const keepAliveNames: Array<string> = [
			world.name.toString('ascii'),
			onlinePlayer.name.toString('ascii'),
			chatbox.name.toString('ascii'),
			playerSaved.name.toString('ascii'),
			ui.name.toString('ascii'),
			bulletProxy.name.toString('ascii'),
		];
		let keepAliveCode: string = "\r\n/// ONLINE\r\n// Keep the online objects active across this deactivation sweep.\r\n";
		for(const kaName of keepAliveNames)
			keepAliveCode += "instance_activate_object(" + kaName + ");\r\n";
		let deactivatorPatched: number = 0;
		for(const actObj of objects){
			if(!actObj || !actObj.events) continue;
			for(const actEvList of actObj.events){
				if(!actEvList) continue;
				for(const [, actActions] of actEvList){
					for(const actAction of actActions){
						if(!actAction || !actAction.paramStrings || !actAction.paramStrings[0]) continue;
						if(actAction.paramStrings[0].indexOf(Buffer.from("instance_deactivate_", 'ascii')) < 0) continue;
						actAction.paramStrings[0] = Buffer.concat([actAction.paramStrings[0], Buffer.from(keepAliveCode, 'ascii')]);
						deactivatorPatched++;
					}
				}
			}
		}
		if(deactivatorPatched > 0)
			console.log(`[compat] patched ${deactivatorPatched} deactivation code block(s) to keep online objects active`);
	}
	replaceChunk(exe, objectsOffsets, putAssets(exe, objects));
	objects = null;
	const saveGame: Script = await findAssetInteractive(scripts, ["save_save", "savegame", "saveGame", "SaveGame", "savedata_save", "scrSaveGame", "SaveFile", "ScsaveGame", "SCR_savegame", "saveSaveData"], "script saveGame", true, "iwpo.saveGame") as Script;
	const loadGame: Script = await findAssetInteractive(scripts, ["save_load", "loadgame", "loadGame", "LoadGame", "savedata_load", "scrLoadGame", "LoadFile", "ScloadGame", "SCR_loadgame", "loadSaveData"], "script loadGame", true, "iwpo.loadGame") as Script;
	const saveExe: Script = findAsset(scripts, ["saveExe", "scrSaveExe", "SCR_saveexe"], "iwpo.saveExe") as Script;
	const tempExe: Script = findAsset(scripts, ["tempExe", "scrTempExe", "SCR_tempexe"], "iwpo.tempExe") as Script;
	// B1 (TheBiob converterGM8.ts:761-781): runtime condition telling real saves apart from
	// fake/auto saves, evaluated inside the injected save block (GM8 path only, via %arg3).
	// iwpo.savePositionVariable overrides the heuristic.
	let savePositionVariable: string = defines.has("iwpo.savePositionVariable") ? (defines.get("iwpo.savePositionVariable") as string) : "";
	if(savePositionVariable === ""){
		const saveGameContent: string = saveGame.source.toString('ascii');
		if(saveGameContent.indexOf("var savePosition") >= 0){
			savePositionVariable = "savePosition";
		}else if(saveGameContent.indexOf("// saveGame(x, y)") >= 0){ // I wanna go shopping
			savePositionVariable = "true";
		}else if(saveGameContent.indexOf("dyingSave = argument0") >= 0 // I wanna Moti Trap
			|| saveGameContent.indexOf("saveByte(f,d,room);") >= 0){ // I wanna enjoy a Merry Christmas!
			savePositionVariable = "!argument0";
		}else if(saveGameContent.indexOf("i = argument0;") >= 0){ // I wanna clear only one stage: argument0 is the save slot, not a save/don't-save flag
			savePositionVariable = "true";
		}else if(saveGameContent.indexOf("argument0") >= 0){
			savePositionVariable = "argument0";
		}else if(gameConfig.version === GameVersion.GameMaker80 || saveGameContent.indexOf("///savedata_save(force)") >= 0){ // renex engine saves (WannaFest22)
			savePositionVariable = "true";
		}else{
			// GM8.2 double trap: a bare `argument0` read makes the script require
			// >=1 args at call time (The Job Won't Save You: save_save() with 0
			// args errored "requires at least 1 arguments"), and the array
			// spelling `argument[0]` is no escape either because GM8's `||` does
			// not short-circuit - the right side is still evaluated with 0 args
			// and errors "Illegal array index". So under GM8.2 no guard that
			// reads the argument is safe. Games reaching this default branch have
			// real save scripts, so broadcast unconditionally there. GM8.0/8.1
			// read a missing argument0 as 0 without erroring, keep the old guard.
			savePositionVariable = isGM82 ? "true" : "(argument_count == 0 || argument0)";
		}
	}
	const saveGuard: string = "if((" + roomGuard + ") && (" + savePositionVariable + ")){";
	saveGame.source = insertGMLScriptBeforeSuccessfulReturn(saveGame.source, await GMLCode.getGML("saveGame", world.name, player.name, player2 ? player2.name : Buffer.from(""), Buffer.from(saveGuard, 'ascii')));
	// v2 (§11): runtime sync is fully driven by `__ONLINE_config.ini [sync]`; no GML codegen here.
	loadGame.source = insertGMLScript(loadGame.source, await GMLCode.getGML("saveGame2", world.name, player.name, player2 ? player2.name : Buffer.from("")));
	// Spectate-disconnect preamble: appended to loadGame for every engine family.
	loadGame.source = insertGMLScript(loadGame.source, await GMLCode.getGML("loadGamePre", world.name, player.name, player2 ? player2.name : Buffer.from("")));
	const loadGameContent: Buffer = await GMLCode.getGML("loadGame", world.name, player.name, player2 ? player2.name : Buffer.from(""));
	// TheBiob parity: engines with the game_restart+tempfile save flow apply the
	// online save AFTER the restart (tempExe > saveExe), never inside loadGame.
	// A pre-restart application is wiped by the restart and, worse, moves the
	// spare player the game's own loadGame creates when only player2 exists,
	// leaving the real player2 behind as a leftover object once global.grav
	// flips it (fish / Seven Colors / yuuutu dual-gravity bug).
	if (GMLCode.is("NIKAPLE") && saveExe !== undefined) {
		saveExe.source = insertGMLScript(saveExe.source, loadGameContent);
	} else if ((saveExe === undefined && tempExe === undefined)
			|| loadGame.source.indexOf(Buffer.from('execute_file')) >= 0) { // If execute_file is used, assume that saveExe and tempExe are unused
		loadGame.source = insertGMLScript(loadGame.source, loadGameContent);
	} else if (tempExe !== undefined) {
		tempExe.source = insertGMLScript(tempExe.source, loadGameContent);
	} else {
		saveExe.source = insertGMLScript(saveExe.source, loadGameContent);
	}
	// Encoding-safe string truncation helper for Chinese text.
	// GM8 string_copy operates on bytes; this iterates forward tracking multi-byte boundaries.
	// GM8.0 uses GBK encoding (2-byte CJK); GM8.1 uses UTF-8 (1-4 byte per char).
	{
		const gbkTruncScript: Script = new Script();
		gbkTruncScript.name = Buffer.from("__ONLINE_gbk_trunc", "ascii");
		if (useUtf8) {
			// UTF-8 truncation (GM 8.1, or GM 8.0 on the GaseousMarble backend)
			gbkTruncScript.source = Buffer.from([
				"// __ONLINE_gbk_trunc(str, maxBytes, suffix) — UTF-8 mode",
				"var p, safe, b, charLen;",
				"if(string_length(argument0) <= argument1) return argument0;",
				"p = 1; safe = 0;",
				"while(p <= string_length(argument0)){",
				"  b = ord(string_copy(argument0, p, 1));",
				"  if(b < $80) charLen = 1;",
				"  else if(b < $C0) { p += 1; continue; }",
				"  else if(b < $E0) charLen = 2;",
				"  else if(b < $F0) charLen = 3;",
				"  else charLen = 4;",
				"  if(p + charLen - 1 <= argument1){ safe = p + charLen - 1; p += charLen; }",
				"  else break;",
				"}",
				"return string_copy(argument0, 1, safe) + argument2;",
			].join("\r\n"), "ascii");
		} else {
			// GBK truncation for GM8.0
			gbkTruncScript.source = Buffer.from([
				"// __ONLINE_gbk_trunc(str, maxBytes, suffix)",
				"var p, safe;",
				"if(string_length(argument0) <= argument1) return argument0;",
				"p = 1; safe = 0;",
				"while(p <= string_length(argument0)){",
				"  if(ord(string_copy(argument0, p, 1)) >= $81){",
				"    if(p + 1 <= argument1){ safe = p + 1; p += 2; }",
				"    else break;",
				"  }else{",
				"    if(p <= argument1){ safe = p; p += 1; }",
				"    else break;",
				"  }",
				"}",
				"return string_copy(argument0, 1, safe) + argument2;",
			].join("\r\n"), "ascii");
		}
		scripts.push(gbkTruncScript);
	}
	// CJK text rendering via GaseousMarble extension (GM8.1+ only).
	// After set_utf8_mode(1), all GM variable strings are UTF-8:
	//   - buffer_read_string returns UTF-8 (http_dll in UTF-8 mode / gm82buf native)
	//   - wd_input_box results converted at storage level via ansi_to_utf8
	// So GaseousMarble receives UTF-8 directly — no conversion needed in draw functions.
	if (cjkBackend === 'gm') {
		const cjkInitLines: Array<string> = [
			"// __ONLINE_cjk_init() — load CJK font via GaseousMarble extension",
			"var _ret;",
		];
		cjkInitLines.push("_ret = gm_font(\"cjk\", \"__ONLINE_font.png\");");
		cjkInitLines.push("if(_ret < 0) { show_message(\"gm_font error: \" + string(_ret)); }");
		cjkInitLines.push("gm_set_font(\"cjk\");");
		cjkInitLines.push(
			"global.__ONLINE_cjkHalign = 0;",
			"global.__ONLINE_cjkValign = 0;"
		);
		const cjkInitScript: Script = new Script();
		cjkInitScript.name = Buffer.from("__ONLINE_cjk_init", "ascii");
		cjkInitScript.source = Buffer.from(cjkInitLines.join("\r\n"), "ascii");
		scripts.push(cjkInitScript);

		// __ONLINE_cjk_draw_text(x, y, str, maxW)
		// GM8 alignment: fa_left=0, fa_center=1, fa_right=2; fa_top=0, fa_middle=1, fa_bottom=2
		// GaseousMarble: left=-1, center=0, right=1; top=-1, middle=0, bottom=1
		// The atlas is built with both fonts at natural positions (no y-offset),
		// so glyphs are visually aligned. GaseousMarble's font.top() = 0 means
		// no vertical shift for fa_top, and top cancels for center/bottom.
		const cjkDrawScript: Script = new Script();
		cjkDrawScript.name = Buffer.from("__ONLINE_cjk_draw_text", "ascii");
		cjkDrawScript.source = Buffer.from([
			"// __ONLINE_cjk_draw_text(x, y, str, maxW)",
			"gm_set_font(\"cjk\");",
			"gm_set_color(draw_get_color());",
			"gm_set_alpha(draw_get_alpha());",
			"gm_set_halign(global.__ONLINE_cjkHalign - 1);",
			"gm_set_valign(global.__ONLINE_cjkValign - 1);",
			"gm_set_max_line_length(argument3);",
			"gm_draw(argument0, argument1, argument2);",
			"return 0;",
		].join("\r\n"), "ascii");
		scripts.push(cjkDrawScript);

		const cjkWidthScript: Script = new Script();
		cjkWidthScript.name = Buffer.from("__ONLINE_cjk_string_width", "ascii");
		cjkWidthScript.source = Buffer.from([
			"// __ONLINE_cjk_string_width(str)",
			"gm_set_font(\"cjk\");",
			"gm_set_max_line_length(0);",
			"return gm_width(argument0);",
		].join("\r\n"), "ascii");
		scripts.push(cjkWidthScript);

		const cjkHeightExtScript: Script = new Script();
		cjkHeightExtScript.name = Buffer.from("__ONLINE_cjk_string_height_ext", "ascii");
		cjkHeightExtScript.source = Buffer.from([
			"// __ONLINE_cjk_string_height_ext(str, sep, maxW)",
			"gm_set_font(\"cjk\");",
			"gm_set_max_line_length(argument2);",
			"return gm_height(argument0);",
		].join("\r\n"), "ascii");
		scripts.push(cjkHeightExtScript);

		const cjkWidthExtScript: Script = new Script();
		cjkWidthExtScript.name = Buffer.from("__ONLINE_cjk_string_width_ext", "ascii");
		cjkWidthExtScript.source = Buffer.from([
			"// __ONLINE_cjk_string_width_ext(str, sep, maxW)",
			"gm_set_font(\"cjk\");",
			"gm_set_max_line_length(argument2);",
			"return gm_width(argument0);",
		].join("\r\n"), "ascii");
		scripts.push(cjkWidthExtScript);
	}
	// FoxWriting helper scripts (CJK detection + dynamic font selection).
	// Needed whenever the fw_* code path is emitted — real or stubbed.
	if (cjkBackend === 'fw') {
		const hasCjkScript: Script = new Script();
		hasCjkScript.name = Buffer.from("__ONLINE_has_cjk", "ascii");
		hasCjkScript.source = Buffer.from([
			"// __ONLINE_has_cjk(str) — returns 1 if string contains GBK high bytes",
			"var i;",
			"for(i = 1; i <= string_length(argument0); i += 1){",
			"  if(ord(string_copy(argument0, i, 1)) >= $81) return 1;",
			"}",
			"return 0;",
		].join("\r\n"), "ascii");
		scripts.push(hasCjkScript);

		const fwUseFontScript: Script = new Script();
		fwUseFontScript.name = Buffer.from("__ONLINE_fw_use_font", "ascii");
		fwUseFontScript.source = Buffer.from([
			"// __ONLINE_fw_use_font(str) — select CJK or Berlin font based on content",
			"if(__ONLINE_has_cjk(argument0)){",
			"  fw_draw_set_font(global.__ONLINE_fwCjk);",
			"}else{",
			"  fw_draw_set_font(global.__ONLINE_fwBerlin);",
			"}",
		].join("\r\n"), "ascii");
		scripts.push(fwUseFontScript);
	}
	replaceChunk(exe, scriptsOffsets, putAssets(exe, scripts));
	scripts = null;
	exe.readOffset = encryptionStartGM80;
	console.log("Encrypting executable...");
	GM80.encrypt(exe);
	exe = settings.save(exe);
	GameData.encrypt(exe, gameConfig);
	console.log("Writing executable...");
	const outputDir: string = path.dirname(input);
	await fs.writeFile(path.join(outputDir, `${gameName}_online.exe`), getExeBuffer());
	const runtimeConfigPath: string = path.join(outputDir, configFilename);
	// T4: factory runtime defaults for the skin system ([config] section):
	// skin= (empty = no skin selected) and skinAutoDL=1 (auto-download on).
	// Omitted entirely when the skin system is disabled (iwpo.no_skins).
	const configContent: string = `[config]\nserver=${server}\nkey_chat=32\nkey_visibility=86\nkey_save=84\nkey_playerlist=76\nkey_settings=79\nkey_fastload=70\nteam=0\nlerp=1\nfast_load=1` + (skinsEnabled ? `\nskin=\nskinAutoDL=1` : ``);
	await fs.writeFile(runtimeConfigPath, configContent, "utf8");
	if(customSlot){
		// Write/merge the runtime `[sync]` section into `__ONLINE_config.ini` next to the produced EXE.
		let existing: string = "";
		if(await fs.exists(runtimeConfigPath)) existing = await fs.readFile(runtimeConfigPath, "utf8");
		await fs.writeFile(runtimeConfigPath, mergeSyncIntoIni(existing, customSlot), "utf8");
	}
	await EnsureX86HttpDllBuilt();
	await fs.copyFile(path.join(__dirname, "lib", HTTP_DLL_FILENAME), path.join(outputDir, HTTP_DLL_FILENAME));
	// N3: built-in notes icon atlas ships with every converted game
	await Utils.copyDir(path.join(__dirname, "lib", "iwponotes"), path.join(outputDir, "iwponotes"));
	// i18n: language files ship next to the exe (lang/<code>.ini, UTF-8). GM8.0
	// additionally gets a GBK byte copy per file - its strings are byte strings
	// and the CJK atlas/FoxWriting are keyed by GBK bytes, so the copy is GBK on
	// every machine, not the player's codepage (PROPOSAL_i18n.md section 3.3).
	{
		const langSrc: string = path.join(__dirname, "lang");
		if(await fs.pathExists(langSrc)){
			const langDst: string = path.join(outputDir, "lang");
			await fs.ensureDir(langDst);
			for(const langFile of await fs.readdir(langSrc)){
				if(!langFile.endsWith(".ini")) continue;
				const langText: string = await fs.readFile(path.join(langSrc, langFile), "utf8");
				await fs.writeFile(path.join(langDst, langFile), langText, "utf8");
				if(gameConfig.version === GameVersion.GameMaker80){
					const gbkName: string = langFile.substring(0, langFile.length - 4) + ".gbk.ini";
					await fs.writeFile(path.join(langDst, gbkName), iconv.encode(langText, "gbk"));
				}
			}
		}
	}
}
