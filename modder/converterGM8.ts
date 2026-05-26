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
			const match: RegExpExecArray = /^return[ \t]+(?:true(?![A-Za-z0-9_])|1(?![0-9.]))[ \t]*;?/i.exec(str.slice(cursor));
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

export const ConverterGM8 = async function(input: string, gameName: string, server: string, ports: Ports, forceExternalDll: boolean, customSlot: CustomSlotConfig | null = null, injectIntoStep: boolean = false): Promise<void> {
	const configFilename: string = "__ONLINE_config.ini";
	console.log("Reading executable...");
	const fishClassGame: boolean = isFishClassGame(gameName);
	let fishCjkRuntimeBlocked: boolean = false;
	const head: Buffer = Buffer.alloc(0x400);
	const fh = await fs.open(input, "r");
	try { await fs.read(fh, head as unknown as Uint8Array, 0, head.length, 0); }
	finally { await fs.close(fh); }
	const isUpxPacked: boolean = head.includes(Buffer.from("UPX0")) || head.includes(Buffer.from("UPX1"));
	if(fishClassGame && isUpxPacked){
		const antidec: boolean = await isAntidecProtected(input);
		if(antidec){
			console.log("Fish-class UPX + Antidec runner detected; disabling native CJK plugins and using the safe stub fallback.");
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
	const findAsset = function(assets: Array<Asset>, names: Array<string>): Asset {
		let result: Asset;
		for(let i: number = 0; i < names.length; ++i){
			const target: string = names[i].toLowerCase();
			result = assets.filter(asset => asset && asset["name"].toString('ascii').toLowerCase() === target)[0];
			if(result !== undefined)
				break;
		}
		return result;
	}
	const findAssetInteractive = async function(assets: Array<Asset>, names: Array<string>, typeName: string, required: boolean = true): Promise<Asset | undefined> {
		let result: Asset = findAsset(assets, names);
		if(result !== undefined) return result;
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
		if(extNameIs(extensions[i], "Noisyfox's Writing") && extensions[i].folderName.toString('ascii').toLowerCase() === "fw")
			hasGm8FoxWriting = true;
		if(extNameIs(extensions[i], "Http Dll 2.3") && extensions[i].folderName.toString('ascii').toLowerCase() === "http_dll_2_3")
			throw new Error("This game is already an online version");
	}
	const addExtension = async function(exe: SmartBuffer, extensions: Array<Extension>, file: string): Promise<void> {
		const pos: number = exe.readOffset;
		const extensionData: Buffer = await fs.readFile(path.join(__dirname, "lib", file));
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
		console.log("Fish-class host detected; disabling native FoxWriting injection and using the safe GM8.0 stub path.");
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
	console.log(`CJK backend: ${cjkBackend} (loadedFW=${loadedFW}, loadedGM=${loadedGM}, useUtf8=${useUtf8})`);

	exe.writeOffset = extensionCountPos;
	exe.writeUInt32LE(extensions.length);
	extensions = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Triggers header");
	let triggers: Array<Trigger> = getAssets(exe, Trigger.deserialize) as Array<Trigger>;
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
	if(exe.readUInt32LE() != 800)
		throw new Error("Sprites header");
	getAssetRefs(exe); // skip sprites section (no modification needed)

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
	timelines = null;
	if(exe.readUInt32LE() != 800)
		throw new Error("Objects header");
	const objectsOffsets: [number, number] = [exe.readOffset, 0];
	let objects: Array<GMObject> = getAssets(exe, GMObject.deserialize) as Array<GMObject>;
	objectsOffsets[1] = exe.readOffset;
	if(objects.some(obj => obj && obj.name.toString('ascii').startsWith("__ONLINE_")))
		throw new Error("This game is already an online version");
	const world: GMObject = await findAssetInteractive(objects, ["world", "World", "objWorld", "oWorld"], "object world") as GMObject;
	const player: GMObject = await findAssetInteractive(objects, ["player", "Player", "objPlayer", "oPlayer", "objplayer"], "object player") as GMObject;
	const player2: GMObject = findAsset(objects, ["player2", "objPlayer2", "oPlayer2"]) as GMObject;
	GMLCode.addVariables("GM8");
	if (gameConfig.version === GameVersion.GameMaker80) {
		GMLCode.addVariables("GM80");
	}
	if (cjkBackend === 'gm') {
		GMLCode.addVariables("CJKTEXT");
	}
	GMLCode.addVariables("TEMPFILE");
	if (hasGm82net || hasGm82buf){
		GMLCode.addVariables("GMNET");
	}
	if (hasGm82net){
		GMLCode.addVariables("GM82NET");
	}
	if (scripts.some(script => script && (
		script.name.equals(ascii("save_save")) ||
		script.name.equals(ascii("player_air_jump")))))
		GMLCode.addVariables("RENEX");
	if (world.name.equals(ascii("objWorld")))
		GMLCode.addVariables("GM8YY");
	if (hasGm82snd)
		GMLCode.addVariables("GMSND");
	if(player2 != undefined)
		GMLCode.addVariables("PLAYER2");
	// Use a specific script name to detect Nikaple's Engine
	if(scripts.some(script => script && script.name.equals(ascii("audio_togglesoundmuted"))))
		GMLCode.addVariables("NIKAPLE");
	// Use external_define/external_call for the NativeAOT x86 DLL.
	// This DLL performs ANSI↔UTF-8 conversion needed for Chinese text support.
	// GM82NET games use aliased function names; others use standard DLL export names.
	if (!hasGm82buf) {
		GMLCode.addVariables("HTTPDLL_INIT");
		const HTTP_DLL_NAME: string = "http_dll_2_3.dll";
		interface DllFunc { name: string; dllName: string; ret: string; args: Array<string>; }
		// Map GML-visible function names to http_dll DLL export names + signatures
		const fns: Array<DllFunc> = hasGm82net ? [
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
		];
		// UTF-8 helpers from http_dll are needed whenever the runtime string mode is UTF-8.
		// This is true for GM 8.1+ by default, and also for GM 8.0 hosts routed through
		// the GaseousMarble CJK backend (worldCreate.gml's `#if CJKTEXT` block calls
		// `set_utf8_mode(1)` to switch http_dll into UTF-8 interpretation).
		if (useUtf8) {
			fns.push({ name: "ansi_to_utf8", dllName: "ansi_to_utf8", ret: "ty_string", args: ["ty_string"] });
			fns.push({ name: "set_utf8_mode", dllName: "set_utf8_mode", ret: "ty_real", args: ["ty_real"] });
		}
		// Generate init script
		const initLines: Array<string> = [`var dll; dll = "${HTTP_DLL_NAME}";`];
		for (const fn of fns) {
			const argTypes: string = fn.args.length > 0 ? "," + fn.args.join(",") : "";
			initLines.push(`global.__od_${fn.dllName} = external_define(dll,'${fn.dllName}',dll_cdecl,${fn.ret},${fn.args.length}${argTypes});`);
		}
		const initScript: Script = new Script();
		initScript.name = Buffer.from("__ONLINE_httpdll_init", "ascii");
		initScript.source = Buffer.from(initLines.join("\r\n"), "ascii");
		scripts.push(initScript);
		// Generate wrapper scripts for each function
		for (const fn of fns) {
			const wrapper: Script = new Script();
			wrapper.name = Buffer.from(fn.name, "ascii");
			const argList: string = fn.args.map((_, i) => `argument${i}`).join(",");
			const callArgs: string = fn.args.length > 0 ? "," + argList : "";
			wrapper.source = Buffer.from(`return external_call(global.__od_${fn.dllName}${callArgs});`, "ascii");
			scripts.push(wrapper);
		}
	} else if (gameConfig.version !== GameVersion.GameMaker80) {
		// GM8.2 with gm82buf: load http_dll only for ansi_to_utf8 + set_utf8_mode
		GMLCode.addVariables("HTTPDLL_INIT");
		const HTTP_DLL_NAME: string = "http_dll_2_3.dll";
		const miniInitLines: Array<string> = [
			`var dll; dll = "${HTTP_DLL_NAME}";`,
			`global.__od_ansi_to_utf8 = external_define(dll,'ansi_to_utf8',dll_cdecl,ty_string,1,ty_string);`,
			`global.__od_set_utf8_mode = external_define(dll,'set_utf8_mode',dll_cdecl,ty_real,1,ty_real);`,
		];
		const miniInitScript: Script = new Script();
		miniInitScript.name = Buffer.from("__ONLINE_httpdll_init", "ascii");
		miniInitScript.source = Buffer.from(miniInitLines.join("\r\n"), "ascii");
		scripts.push(miniInitScript);
		const ansiWrapper: Script = new Script();
		ansiWrapper.name = Buffer.from("ansi_to_utf8", "ascii");
		ansiWrapper.source = Buffer.from("return external_call(global.__od_ansi_to_utf8, argument0);", "ascii");
		scripts.push(ansiWrapper);
		const utfModeWrapper: Script = new Script();
		utfModeWrapper.name = Buffer.from("set_utf8_mode", "ascii");
		utfModeWrapper.source = Buffer.from("return external_call(global.__od_set_utf8_mode, argument0);", "ascii");
		scripts.push(utfModeWrapper);
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
		if(cjkBackend === 'fw' && !loadedFW){
			addStubScript("fw_add_font_from_file", "return -1;");
			addStubScript("fw_add_font", "return -1;");
			addStubScript("fw_set_font_offset", "return 0;");
			addStubScript("fw_draw_set_font", "return 0;");
			addStubScript("fw_draw_set_halign", "draw_set_halign(argument0); return 0;");
			addStubScript("fw_draw_set_valign", "draw_set_valign(argument0); return 0;");
			addStubScript("fw_draw_set_line_spacing", "return 0;");
			addStubScript("fw_draw_text_ext", "draw_text_ext(argument0, argument1, argument2, -1, argument3); return 0;");
			addStubScript("fw_string_width", "return string_width(argument0);");
			addStubScript("fw_string_width_ext", "return string_width_ext(argument0, argument1, argument2);");
			addStubScript("fw_string_height_ext", "return string_height_ext(argument0, argument1, argument2);");
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
	const roomRefs: Array<Buffer> = getAssetRefs(exe);
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
		? "if(" + existingMenuRooms.map(r => `room != ${r}`).join(" && ") + "){"
		: "if(true){";
	// Included files: always read through the section. Inject sound files for gm82snd,
	// and inject GaseousMarble font files for CJK text rendering.
	{
		exe.readInt32LE(); //last_instance_id
		exe.readInt32LE(); //last_tile_id
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
		if (gm80AsciiFontPath !== null) {
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

		replaceChunk(exe, includedfilesOffsets, putAssetRefs(exe, includedfiles));
	}
	// gameName encoding: tied to the runtime string mode chosen by the CJK backend.
	//   useUtf8 == true  (GM 8.1+ default, or GM 8.0+'gm' backend with set_utf8_mode(1)):
	//     emit UTF-8 directly; http_dll, GaseousMarble and GM string ops all agree.
	//   useUtf8 == false (GM 8.0 + 'fw'|'none'):
	//     emit GBK byte pairs; FoxWriting and http_dll (no UTF-8 mode) both expect GBK.
	const gameNameBuf: Buffer = useUtf8
		? Buffer.from(gameName)
		: iconv.encode(gameName, "gbk");
	world.addCreateCode(await GMLCode.getGML("worldCreate", Buffer.from(uniqueKey,'ascii'), Buffer.from(server,'ascii'), Buffer.from(ports.tcp.toString(), 'ascii'), Buffer.from(ports.udp.toString(),'ascii'), gameNameBuf, Buffer.from(Utils.getVersion(), 'ascii')));
	// Opt-in compatibility path: keep EndStep as the default, but allow Step
	// injection for GM8.2-mod edge cases where the default tick does not run.
	const addTick = function(obj: GMObject, gml: Buffer): void {
		if(injectIntoStep) obj.addStepCode(gml);
		else obj.addEndStepCode(gml);
	};
	addTick(world, await GMLCode.getGML("worldEndStep", player.name, player2 ? player2.name : Buffer.from("")));
	world.addGameEndCode(await GMLCode.getGML("worldGameEnd"));
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
	const onlinePlayer: GMObject = newObject(Buffer.from("__ONLINE_onlinePlayer", 'ascii'), false, -10, true);
	onlinePlayer.addCreateCode(await GMLCode.getGML("onlinePlayerCreate"));
	const onlinePlayerTick: Buffer = await GMLCode.getGML("onlinePlayerEndStep", player.name, player2 ? player2.name : Buffer.from(""), world.name);
	addTick(onlinePlayer, onlinePlayerTick);
	onlinePlayer.addDrawCode(await GMLCode.getGML("onlinePlayerDraw", world.name));
	const chatbox: GMObject = newObject(Buffer.from("__ONLINE_chatbox",'ascii'), true, -11, true);
	chatbox.addCreateCode(await GMLCode.getGML("chatboxCreate"));
	const chatboxTick: Buffer = await GMLCode.getGML("chatboxEndStep", player.name, player2 ? player2.name : Buffer.from(""), world.name);
	addTick(chatbox, chatboxTick);
	chatbox.addDrawCode(await GMLCode.getGML("chatboxDraw"));
	const playerSaved: GMObject = newObject(Buffer.from("__ONLINE_playerSaved",'ascii'), true, -10, false);
	playerSaved.addCreateCode(await GMLCode.getGML("playerSavedCreate"));
	const playerSavedTick: Buffer = await GMLCode.getGML("playerSavedEndStep");
	addTick(playerSaved, playerSavedTick);
	playerSaved.addDrawCode(await GMLCode.getGML("playerSavedDraw"));
	const ui: GMObject = newObject(Buffer.from("__ONLINE_userInterface",'ascii'), true, -2147483648, true);
	const drawGml: Buffer = await GMLCode.getGML("worldDraw");
	const worldName: string = world.name.toString('ascii');
	const wrappedDraw: Buffer = concatBuffers([
		Buffer.from(`if(instance_exists(${worldName})){\r\nwith(instance_find(${worldName}, 0)){\r\n`, 'utf8'),
		drawGml,
		Buffer.from(`\r\n}\r\n}\r\n`, 'utf8')
	]);
	ui.addDrawCode(wrappedDraw);
	objects.push(onlinePlayer);
	objects.push(chatbox);
	objects.push(playerSaved);
	objects.push(ui);
	replaceChunk(exe, objectsOffsets, putAssets(exe, objects));
	objects = null;
	const saveGame: Script = await findAssetInteractive(scripts, ["save_save", "savegame", "saveGame", "savedata_save", "scrSaveGame", "SaveGame"], "script saveGame") as Script;
	const loadGame: Script = await findAssetInteractive(scripts, ["save_load", "loadgame", "loadGame", "savedata_load", "scrLoadGame", "LoadGame"], "script loadGame") as Script;
	const saveExe: Script = findAsset(scripts, ["saveExe", "scrSaveExe"]) as Script;
	const tempExe: Script = findAsset(scripts, ["tempExe", "scrTempExe"]) as Script;
	saveGame.source = insertGMLScriptBeforeSuccessfulReturn(saveGame.source, await GMLCode.getGML("saveGame", world.name, player.name, player2 ? player2.name : Buffer.from(""), Buffer.from(roomGuard, 'ascii')));
	// v2 (§11): runtime sync is fully driven by `__ONLINE_config.ini [sync]`; no GML codegen here.
	loadGame.source = insertGMLScript(loadGame.source, await GMLCode.getGML("saveGame2", world.name, player.name, player2 ? player2.name : Buffer.from("")));
	const loadGameContent: Buffer = await GMLCode.getGML("loadGame", world.name, player.name, player2 ? player2.name : Buffer.from(""));
	loadGame.source = insertGMLScript(loadGame.source, loadGameContent);
	if(saveExe !== undefined || tempExe !== undefined){
		if(tempExe !== undefined)
			tempExe.source = insertGMLScript(tempExe.source, loadGameContent);
		else
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
	const configContent: string = `[config]\nserver=${server}\nkey_chat=32\nkey_visibility=86\nkey_save=84\nkey_playerlist=76\nkey_settings=79\nkey_rating=85\nkey_fastload=70\nteam=0\nlerp=1\nfast_load=1`;
	await fs.writeFile(runtimeConfigPath, configContent, "utf8");
	if(customSlot){
		// Write/merge the runtime `[sync]` section into `__ONLINE_config.ini` next to the produced EXE.
		let existing: string = "";
		if(await fs.exists(runtimeConfigPath)) existing = await fs.readFile(runtimeConfigPath, "utf8");
		await fs.writeFile(runtimeConfigPath, mergeSyncIntoIni(existing, customSlot), "utf8");
	}
	await EnsureX86HttpDllBuilt();
	await fs.copyFile(path.join(__dirname, "lib", HTTP_DLL_FILENAME), path.join(outputDir, HTTP_DLL_FILENAME));
}
