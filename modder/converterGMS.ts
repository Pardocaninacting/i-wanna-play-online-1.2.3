import fs from "fs-extra"
import path from "path"
import md5 from "md5"
import _7zip from "7zip-min"
import { spawn } from "child_process"
import { Utils, Ports } from "./utils"
import { CustomSlotConfig, formatSyncIniSection, mergeSyncIntoIni } from "./customSlot"

const TMP_FOLDER: string = path.join(__dirname, "tmp");
const GMS_DETECT_FOLDER: string = path.join(TMP_FOLDER, "gms-detect");
const GMS_WORK_FOLDER: string = path.join(TMP_FOLDER, "gms-work");
const CONFIG_FILENAME: string = "__ONLINE_config.ini";

/** Write/merge the runtime `[sync]` section into `__ONLINE_config.ini` next to the produced game. */
async function WriteRuntimeSyncDefaults(outputDir: string, customSlot: CustomSlotConfig): Promise<void> {
	const p: string = path.join(outputDir, CONFIG_FILENAME);
	let existing: string = "";
	if(await fs.exists(p)) existing = await fs.readFile(p, "utf8");
	const merged: string = mergeSyncIntoIni(existing, customSlot);
	await fs.writeFile(p, merged, "utf8");
}
const HTTP_DLL_FILENAME: string = "http_dll_2_3.dll";
const HTTP_DLL_X64_FILENAME: string = "http_dll_2_3_x64.dll";
const HTTP_DLL_X64_PROJECT_DIR: string = path.join(__dirname, "native", "http_dll_2_3_x64");
const CONVERTER_GMS2_DIR: string = path.join(__dirname, "lib", "converterGMS2");
const CONVERTER_GMS2_EXE: string = path.join(CONVERTER_GMS2_DIR, "converterGMS2.exe");
const UTMT_CONFIG_FILENAME: string = "__ONLINE_utmt_config.json";

interface ConverterGMSConfig {
	gameId: string,
	server: string,
	tcpPort: number,
	udpPort: number,
	gameName: string,
	version: string,
	gmlDirectory: string,
	resourceDirectory: string,
	useX64NativeHttpDll: boolean,
	successMarkerPath: string,
}

const Unpack = async function(file: string, folder: string): Promise<boolean> {
	return new Promise((resolve, _) => {
		_7zip.unpack(file, folder, function(err): void {
			if(err)
				resolve(false);
			else
				resolve(true);
		});
	});
}

const IsAlreadyOnlineGmsDataWin = async function(file: string): Promise<boolean> {
	const content: Buffer = await fs.readFile(file);
	const markers: Array<Buffer> = [
		Buffer.from("__ONLINE_onlinePlayer", "ascii"),
		Buffer.from("__ONLINE_chatbox", "ascii"),
		Buffer.from("Http Dll 2.3", "ascii"),
	];
	return markers.every((marker: Buffer) => content.includes(marker));
}

const GetExecutableArchitecture = async function(file: string): Promise<"x86" | "x64"> {
	const handle = await fs.open(file, "r");
	try{
		const dosHeader: Buffer = Buffer.alloc(64);
		await fs.read(handle, dosHeader, 0, dosHeader.length, 0);
		const peOffset: number = dosHeader.readUInt32LE(0x3C);
		const peHeader: Buffer = Buffer.alloc(6);
		await fs.read(handle, peHeader, 0, peHeader.length, peOffset);
		if(peHeader.toString("ascii", 0, 4) !== "PE\0\0")
			throw new Error("Invalid PE signature");
		const machine: number = peHeader.readUInt16LE(4);
		if(machine === 0x8664)
			return "x64";
		return "x86";
	}finally{
		await fs.close(handle);
	}
}

const CopyHttpDll = async function(to: string, useX64NativeHttpDll: boolean): Promise<void> {
	const sourceFile: string = useX64NativeHttpDll ? HTTP_DLL_X64_FILENAME : HTTP_DLL_FILENAME;
	await fs.copyFile(path.join(__dirname, "lib", sourceFile), path.join(to, HTTP_DLL_FILENAME));
}

const EnsureX64HttpDllBuilt = async function(): Promise<void> {
	const outputDll: string = path.join(__dirname, "lib", HTTP_DLL_X64_FILENAME);
	if(await fs.exists(outputDll))
		return;
	const projectFile: string = path.join(HTTP_DLL_X64_PROJECT_DIR, "HttpDll23X64.csproj");
	if(!await fs.exists(projectFile))
		throw new Error(`Cannot find ${HTTP_DLL_X64_FILENAME} or its NativeAOT project. Place the pre-built DLL in lib/ or ensure the NativeAOT project exists in native/http_dll_2_3_x64/`);
	console.log("HTTP DLL: building...");
	try{
		await Utils.exec("dotnet publish -c Release", HTTP_DLL_X64_PROJECT_DIR);
	}catch(e){
		throw new Error(`Failed to build ${HTTP_DLL_X64_FILENAME}. Ensure .NET 8 SDK (with NativeAOT workload) is installed. Error: ${e}`);
	}
	const publishedDll: string = path.join(HTTP_DLL_X64_PROJECT_DIR, "bin", "Release", "net8.0", "win-x64", "publish", HTTP_DLL_X64_FILENAME);
	if(!await fs.exists(publishedDll))
		throw new Error(`NativeAOT publish succeeded but ${HTTP_DLL_X64_FILENAME} was not found at expected path: ${publishedDll}`);
	await fs.copyFile(publishedDll, outputDll);
	console.log("HTTP DLL: ready");
}

const WriteConverterConfig = async function(dataWin: string, config: ConverterGMSConfig): Promise<string> {
	const configPath: string = path.join(path.dirname(dataWin), UTMT_CONFIG_FILENAME);
	await fs.writeJson(configPath, config, { spaces: 2 });
	return configPath;
}

const ConvertDataWin = async function(input: string, output: string, gameName: string, gameId: string, server: string, ports: Ports, useX64NativeHttpDll: boolean, customSlot: CustomSlotConfig | null): Promise<void> {
	if(!await fs.exists(CONVERTER_GMS2_EXE))
		throw new Error(`Cannot find converterGMS2.exe in lib/converterGMS2/`);
	const successMarkerPath: string = path.join(path.dirname(input), "__ONLINE_utmt_success.txt");
	if(await fs.exists(successMarkerPath))
		await fs.unlink(successMarkerPath);
	// v2 (§11): runtime sync is fully driven by `__ONLINE_config.ini [sync]`; no GML codegen.
	let gmlDir: string = path.join(__dirname, "gml");
	const configPath: string = await WriteConverterConfig(input, {
		gameId: gameId,
		server: server,
		tcpPort: ports.tcp,
		udpPort: ports.udp,
		gameName: gameName,
		version: Utils.getVersion(),
		gmlDirectory: gmlDir,
		resourceDirectory: path.join(__dirname, "lib"),
		useX64NativeHttpDll: useX64NativeHttpDll,
		successMarkerPath: successMarkerPath,
	});
	try{
		await new Promise<void>((resolve, reject) => {
			const proc = spawn(CONVERTER_GMS2_EXE, [input, output, configPath], {
				cwd: CONVERTER_GMS2_DIR,
				stdio: ['inherit', 'inherit', 'pipe'],
				windowsHide: true,
			});
			let stderr = '';
			proc.stderr.on('data', (data: Buffer) => { stderr += data.toString(); });
			proc.on('error', reject);
			proc.on('close', (code: number) => {
				if(code){
					reject(new Error(stderr.trim() || `Converter failed with exit code ${code}`));
				}else{
					resolve();
				}
			});
		});
	}finally{
		if(await fs.exists(configPath))
			await fs.unlink(configPath);
	}
	if(!await fs.exists(successMarkerPath))
		throw new Error("The GMS converter did not confirm a successful conversion.");
	await fs.unlink(successMarkerPath);
}

export const IsGMS = async function(input: string): Promise<boolean> {
	await Utils.rimraf(GMS_DETECT_FOLDER);
	await fs.mkdirp(GMS_DETECT_FOLDER);
	const isPacked: boolean = await Unpack(input, GMS_DETECT_FOLDER);
	await Utils.rimraf(GMS_DETECT_FOLDER);
	return isPacked || fs.exists(path.join(path.dirname(input), "data.win"));
}

export const ConverterGMS = async function(input: string, gameName: string, server: string, ports: Ports, customSlot: CustomSlotConfig | null = null): Promise<void> {
	await Utils.rimraf(GMS_WORK_FOLDER);
	await fs.mkdirp(GMS_WORK_FOLDER);
	console.log("Reading executable...");
	const executableArchitecture: "x86" | "x64" = await GetExecutableArchitecture(input);
	const useX64NativeHttpDll: boolean = executableArchitecture === "x64";
	if(useX64NativeHttpDll)
		console.log("HTTP DLL mode: native x64");
	if(useX64NativeHttpDll)
		await EnsureX64HttpDllBuilt();
	const isPacked: boolean = await Unpack(input, GMS_WORK_FOLDER);
	const oldDataWin: string = path.join(GMS_WORK_FOLDER, "data2.win");
	const newDataWin: string = path.join(GMS_WORK_FOLDER, "data.win");
	if(isPacked){
		const tmpDataWin: string = path.join(GMS_WORK_FOLDER, "data.win");
		if(!await fs.exists(tmpDataWin))
			throw new Error("Cannot find data.win");
		await fs.rename(tmpDataWin, oldDataWin);
	}else{
		await fs.copyFile(path.join(path.dirname(input), "data.win"), oldDataWin);
	}
	if(await IsAlreadyOnlineGmsDataWin(oldDataWin))
		throw new Error("This game is already an online version. For unpacked GMS games, restore data_backup.win to data.win before converting again.");
	console.log("Generating game key...");
	const uniqueKey: string = md5(`${gameName}\0${(await fs.stat(oldDataWin)).size}`);
	console.log("Converting data.win...");
	await ConvertDataWin(oldDataWin, newDataWin, gameName, uniqueKey, server, ports, useX64NativeHttpDll, customSlot);
	await fs.unlink(oldDataWin);
	if(isPacked){
		const onlineDir: string = path.join(path.dirname(input), `${gameName}_online`);
		await Utils.rimraf(onlineDir);
		await Utils.copyDir(GMS_WORK_FOLDER, onlineDir);
		await CopyHttpDll(onlineDir, useX64NativeHttpDll);
		const configContent: string = `[config]\nserver=${server}\nkey_chat=32\nkey_visibility=86\nkey_save=84\nkey_playerlist=76\nkey_settings=79\nkey_fastload=70\nteam=0\nlerp=1\nfast_load=1`;
		await fs.writeFile(path.join(onlineDir, CONFIG_FILENAME), configContent, "utf8");
		if(customSlot) await WriteRuntimeSyncDefaults(onlineDir, customSlot);
	}else{
		const tmpDataWin: string = path.join(path.dirname(input), "data.win");
		await fs.rename(tmpDataWin, path.join(path.dirname(input), "data_backup.win"));
		await fs.copyFile(newDataWin, tmpDataWin);
		await CopyHttpDll(path.dirname(input), useX64NativeHttpDll);
		const configContent: string = `[config]\nserver=${server}\nkey_chat=32\nkey_visibility=86\nkey_save=84\nkey_playerlist=76\nkey_settings=79\nkey_fastload=70\nteam=0\nlerp=1\nfast_load=1`;
		await fs.writeFile(path.join(path.dirname(input), CONFIG_FILENAME), configContent, "utf8");
		if(customSlot) await WriteRuntimeSyncDefaults(path.dirname(input), customSlot);
	}
	await Utils.rimraf(GMS_WORK_FOLDER);
}
