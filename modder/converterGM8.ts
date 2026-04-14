import fs from "fs-extra"
import path from "path"
import zlib from "zlib"
import { SmartBuffer } from "smart-buffer"
import { PESection, WindowsIcon, Icon } from "./icon"
import { GameConfig, GameData, GameVersion } from "./gamedata"
import { GM80 } from "./gamedata/gm80"
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

const HTTP_DLL_FILENAME: string = "http_dll_2_3.dll";
const HTTP_DLL_X86_PROJECT_DIR: string = path.join(__dirname, "native", "http_dll_2_3_x86");

const EnsureX86HttpDllBuilt = async function(): Promise<void> {
	const outputDll: string = path.join(__dirname, "lib", HTTP_DLL_FILENAME);
	if(await fs.exists(outputDll))
		return;
	const projectFile: string = path.join(HTTP_DLL_X86_PROJECT_DIR, "HttpDll23X86.csproj");
	if(!await fs.exists(projectFile))
		throw new Error(`Cannot find ${HTTP_DLL_FILENAME} or its NativeAOT project. Place the pre-built DLL in lib/ or ensure the NativeAOT project exists in native/http_dll_2_3_x86/`);
	console.log("Building network DLL...");
	try{
		await Utils.exec("dotnet publish -c Release", HTTP_DLL_X86_PROJECT_DIR);
	}catch(e){
		throw new Error(`Failed to build ${HTTP_DLL_FILENAME}. Ensure .NET 10+ SDK (with NativeAOT workload) and VS2022 Build Tools are installed. Error: ${e}`);
	}
	const publishedDll: string = path.join(HTTP_DLL_X86_PROJECT_DIR, "bin", "Release", "net10.0", "win-x86", "publish", HTTP_DLL_FILENAME);
	if(!await fs.exists(publishedDll))
		throw new Error(`NativeAOT publish succeeded but ${HTTP_DLL_FILENAME} was not found at expected path: ${publishedDll}`);
	await fs.copyFile(publishedDll, outputDll);
	console.log("Network DLL ready.");
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

export const ConverterGM8 = async function(input: string, gameName: string, server: string, ports: Ports, forceExternalDll: boolean): Promise<void> {
	const configFilename: string = "__ONLINE_config.ini";
	console.log("Reading file...");
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
	// let rsrcLocation: number = null;
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
		// if(sectionName.compare(Buffer.from([0x2E, 0x72, 0x73, 0x72, 0x63, 0x00, 0x00, 0x00])) == 0)
		// 	rsrcLocation = diskAddress;
		sections.push({
			virtualSize: virtualSize,
			virtualAddress: virtualAddress,
			diskSize: diskSize,
			diskAddress: diskAddress,
		});
	}
	// let iconData: Array<WindowsIcon> = [];
	// let icoFileRaw: Array<number> = [];
	// if(rsrcLocation !== null){
	// 	const readOffsetBackup = exe.readOffset;
	// 	exe.readOffset = rsrcLocation;
	// 	[iconData, icoFileRaw] = Icon.find(exe, sections);
	// 	exe.readOffset = readOffsetBackup;
	// 	await Icon.save(iconData, path.join(__dirname, "tests", "issou"));
	// }
	let upxData: [number, number] = null;
	if(upx0VirtualLength !== null && upx1Data !== null)
		upxData = [upx0VirtualLength+upx1Data[0], upx1Data[1]];
	console.log("Decrypting...");
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
	const insertGMLScript = function(source: Buffer, code: Buffer) {
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
		for(let i: number = openIdx; i < str.length; ++i){
			const ch: string = str[i];
			if(ch === '"' || ch === "'"){
				i = str.indexOf(ch, i + 1);
				if(i === -1) break;
			}else if(ch === '/' && str[i+1] === '/'){
				i = str.indexOf('\n', i + 2);
				if(i === -1) break;
			}else if(ch === '/' && str[i+1] === '*'){
				i = str.indexOf('*/', i + 2);
				if(i === -1) break;
				i++; // skip past '*/'
			}else if(ch === '{'){
				depth++;
			}else if(ch === '}'){
				depth--;
				if(depth === 0){ closeIdx = i; break; }
			}
		}
		if(closeIdx !== -1 && str.substring(closeIdx + 1).trim().length === 0)
			return concatBuffers([source.slice(0, closeIdx), Buffer.from("\n", 'ascii'), code, Buffer.from("}", 'ascii')]);
		return concatBuffers([source, code]);
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
	if(!hasWindowsDialogs)
		await addExtension(exe, extensions, "gm_windows_dialog8");
	// http_dll8 extension is no longer used – the NativeAOT x86 DLL (external_define)
	// is always used instead, because it performs ANSI↔UTF-8 conversion at the
	// GM8↔DLL boundary which is required for Chinese text to survive the server's
	// UTF-8 re-encoding on TCP messages (chat, saves, etc.).
	if (!hasGm8FoxWriting && gameConfig.version === GameVersion.GameMaker80)
		await addExtension(exe, extensions, "ChineseChatSupport8");

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
	let sprites: Array<Sprite> = getAssets(exe, Sprite.deserialize) as Array<Sprite>;
	sprites = null;
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
			{ name: "buffer_read_u64", dllName: "buffer_read_uint64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i16", dllName: "buffer_read_int16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_i32", dllName: "buffer_read_int32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float", dllName: "buffer_read_float32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_double", dllName: "buffer_read_float64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_string", dllName: "buffer_read_string", ret: "ty_string", args: ["ty_real"] },
			{ name: "buffer_write_u8", dllName: "buffer_write_uint8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_u16", dllName: "buffer_write_uint16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_u64", dllName: "buffer_write_uint64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i16", dllName: "buffer_write_int16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_i32", dllName: "buffer_write_int32", ret: "ty_real", args: ["ty_real", "ty_real"] },
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
			{ name: "buffer_read_uint64", dllName: "buffer_read_uint64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int16", dllName: "buffer_read_int16", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_int32", dllName: "buffer_read_int32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float32", dllName: "buffer_read_float32", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_float64", dllName: "buffer_read_float64", ret: "ty_real", args: ["ty_real"] },
			{ name: "buffer_read_string", dllName: "buffer_read_string", ret: "ty_string", args: ["ty_real"] },
			{ name: "buffer_write_uint8", dllName: "buffer_write_uint8", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_uint16", dllName: "buffer_write_uint16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_uint64", dllName: "buffer_write_uint64", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int16", dllName: "buffer_write_int16", ret: "ty_real", args: ["ty_real", "ty_real"] },
			{ name: "buffer_write_int32", dllName: "buffer_write_int32", ret: "ty_real", args: ["ty_real", "ty_real"] },
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
	if (hasGm82snd) {
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
		includedfiles.push(newIncludedfile("__ONLINE_sndChatbox.wav"));
		includedfiles.push(newIncludedfile("__ONLINE_sndSaved.wav"));
		replaceChunk(exe, includedfilesOffsets, putAssetRefs(exe, includedfiles));
	}
	world.addCreateCode(await GMLCode.getGML("worldCreate", Buffer.from(uniqueKey,'ascii'), Buffer.from(server,'ascii'), Buffer.from(ports.tcp.toString(), 'ascii'), Buffer.from(ports.udp.toString(),'ascii'), Buffer.from(gameName), Buffer.from(Utils.getVersion(), 'ascii')));
	world.addEndStepCode(await GMLCode.getGML("worldEndStep", player.name, player2 ? player2.name : Buffer.from("")));
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
	onlinePlayer.addEndStepCode(await GMLCode.getGML("onlinePlayerEndStep", player.name, player2 ? player2.name : Buffer.from(""), world.name));
	onlinePlayer.addDrawCode(await GMLCode.getGML("onlinePlayerDraw", world.name));
	const chatbox: GMObject = newObject(Buffer.from("__ONLINE_chatbox",'ascii'), true, -11, true);
	chatbox.addCreateCode(await GMLCode.getGML("chatboxCreate"));
	chatbox.addEndStepCode(await GMLCode.getGML("chatboxEndStep", player.name, player2 ? player2.name : Buffer.from("")));
	chatbox.addDrawCode(await GMLCode.getGML("chatboxDraw"));
	const playerSaved: GMObject = newObject(Buffer.from("__ONLINE_playerSaved",'ascii'), true, -10, false);
	playerSaved.addCreateCode(await GMLCode.getGML("playerSavedCreate"));
	playerSaved.addEndStepCode(await GMLCode.getGML("playerSavedEndStep"));
	playerSaved.addDrawCode(await GMLCode.getGML("playerSavedDraw"));
	const ui: GMObject = newObject(Buffer.from("__ONLINE_userInterface",'ascii'), true, -2147483648, true);
	const drawGml: Buffer = await GMLCode.getGML("worldDraw");
	const worldName: string = world.name.toString('ascii');
	const wrappedDraw: Buffer = Buffer.concat([
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
	saveGame.source = insertGMLScript(saveGame.source, await GMLCode.getGML("saveGame", world.name, player.name, player2 ? player2.name : Buffer.from(""), Buffer.from(roomGuard, 'ascii')));
	loadGame.source = insertGMLScript(loadGame.source, await GMLCode.getGML("saveGame2", world.name, player.name, player2 ? player2.name : Buffer.from("")));
	const loadGameContent: Buffer = await GMLCode.getGML("loadGame", world.name, player.name, player2 ? player2.name : Buffer.from(""));
	if(saveExe == undefined && tempExe == undefined){
		loadGame.source = insertGMLScript(loadGame.source, loadGameContent);
	}else{
		if(tempExe !== undefined)
			tempExe.source = insertGMLScript(tempExe.source, loadGameContent);
		else
			saveExe.source = insertGMLScript(saveExe.source, loadGameContent);
	}
	// GBK-safe string truncation helper for Chinese text in GM8.
	// GM8 string_copy operates on bytes; this iterates forward tracking 2-byte GBK boundaries.
	if (gameConfig.version === GameVersion.GameMaker80) {
		const gbkTruncScript: Script = new Script();
		gbkTruncScript.name = Buffer.from("__ONLINE_gbk_trunc", "ascii");
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
		scripts.push(gbkTruncScript);
		// GBK CJK detection: returns 1 if any byte >= $81 (GBK lead byte), else 0
		const hasCjkScript: Script = new Script();
		hasCjkScript.name = Buffer.from("__ONLINE_has_cjk", "ascii");
		hasCjkScript.source = Buffer.from([
			"// __ONLINE_has_cjk(str) → 1 if contains GBK high bytes, 0 otherwise",
			"var i;",
			"for(i = 1; i <= string_length(argument0); i += 1){",
			"  if(ord(string_copy(argument0, i, 1)) >= $81) return 1;",
			"}",
			"return 0;",
		].join("\r\n"), "ascii");
		scripts.push(hasCjkScript);
		// NoisyFox font selector: Berlin for ASCII, YaHei for CJK
		const fwUseFontScript: Script = new Script();
		fwUseFontScript.name = Buffer.from("__ONLINE_fw_use_font", "ascii");
		fwUseFontScript.source = Buffer.from([
			"// __ONLINE_fw_use_font(str) — sets NoisyFox font based on content",
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
	console.log("Encrypting...");
	GM80.encrypt(exe);
	exe = settings.save(exe);
	GameData.encrypt(exe, gameConfig);
	console.log("Writing...");
	const outputDir: string = path.dirname(input);
	await fs.writeFile(path.join(outputDir, `${gameName}_online.exe`), getExeBuffer());
	const configContent: string = `[config]\nserver=${server}\nkey_chat=32\nkey_visibility=86\nkey_save=84\nkey_playerlist=76\nkey_settings=79\nkey_rating=85\nteam=0\nlerp=1`;
	await fs.writeFile(path.join(outputDir, configFilename), configContent, "utf8");
	if (!hasGm82buf){
		await EnsureX86HttpDllBuilt();
		await fs.copyFile(path.join(__dirname, "lib", HTTP_DLL_FILENAME), path.join(outputDir, HTTP_DLL_FILENAME));
	}
}
