import fs from "fs-extra"
import path from "path"
import process from "process"
import { ConverterGM8 } from "./converterGM8"
import { ConverterGMS, IsGMS } from "./converterGMS"
import { Utils, Ports } from "./utils"
import { CustomSlotConfig, parseCustomSlotConfig } from "./customSlot"

const getInputGame = async function(): Promise<string> {
	let input: string = "";
	if(process.argv.length > 2)
		input = process.argv[2];
	if(input == "")
		throw new Error("Please drag and drop a game executable on this program in order to use it");
	if(path.extname(input) != ".exe")
		throw new Error("The game has to be an executable");
	if(!await fs.exists(input))
		throw new Error(`Cannot find the file ${input}`);
	const baseName: string = path.basename(input).toLowerCase();
	if(baseName === "iwpo-config-editor.exe")
		throw new Error("This is the config editor, not a game. Please drag a game executable instead.");
	return input;
}

interface ToolSettings {
	server?: string;
	tcpPort?: number;
	udpPort?: number;
	forceExternalDll?: boolean;
	noExtensionPackages?: boolean;
	extensionPackages?: string;
	customSlot?: CustomSlotConfig | null;
}

const readToolSettings = async function(): Promise<ToolSettings> {
	const settingsPath: string = path.join(__dirname, "..", "iwpo-settings.ini");
	if(!await fs.exists(settingsPath))
		return {};
	const content: string = await fs.readFile(settingsPath, "utf8");
	const result: ToolSettings = {};
	let currentSection: string = "";
	const modSection: Record<string, string> = {};
	let hasModSection: boolean = false;
	for(const line of content.split(/\r?\n/)){
		const trimmed: string = line.trim();
		if(trimmed.startsWith("[") && trimmed.endsWith("]")){
			currentSection = trimmed.slice(1, -1).toLowerCase();
			if(currentSection === "mod") hasModSection = true;
			continue;
		}
		if(!trimmed || trimmed.startsWith(";") || trimmed.startsWith("#")) continue;
		const eq: number = trimmed.indexOf("=");
		if(eq < 0) continue;
		const key: string = trimmed.slice(0, eq).trim();
		const val: string = trimmed.slice(eq + 1).trim();
		if(currentSection === "settings"){
			if(!val) continue;
			switch(key){
				case "server": result.server = val; break;
				case "tcp_port": result.tcpPort = Number(val); break;
				case "udp_port": result.udpPort = Number(val); break;
				case "force_external_dll": result.forceExternalDll = val === "1" || val.toLowerCase() === "true"; break;
				case "no_extension_packages": result.noExtensionPackages = val === "1" || val.toLowerCase() === "true"; break;
				case "extension_packages": result.extensionPackages = val.toLowerCase(); break;
			}
		}else if(currentSection === "mod"){
			modSection[key.toLowerCase()] = val;
		}
	}
	if(hasModSection){
		result.customSlot = parseCustomSlotConfig(modSection);
	}
	return result;
}

const getServer = async function(): Promise<{server: string, ports: Ports, forceExternalDll: boolean, noExtensionPackages: boolean, extensionPackages: string | null, customSlot: CustomSlotConfig | null}> {
	let server: string = "localhost";
	let ports: Ports = {
		tcp: 8002,
		udp: 8003,
	}
	let forceExternalDll: boolean = false;
	let noExtensionPackages: boolean = false;
	let extensionPackages: string | null = null;
	const toolSettings = await readToolSettings();
	if(toolSettings.server) server = toolSettings.server;
	if(toolSettings.tcpPort) ports.tcp = toolSettings.tcpPort;
	if(toolSettings.udpPort) ports.udp = toolSettings.udpPort;
	if(toolSettings.forceExternalDll) forceExternalDll = true;
	if(toolSettings.noExtensionPackages) noExtensionPackages = true;
	if(toolSettings.extensionPackages) extensionPackages = toolSettings.extensionPackages;
	const customSlot: CustomSlotConfig | null = toolSettings.customSlot ? toolSettings.customSlot : null;
	const keyword: string = "server=";
	for(const arg of process.argv){
		if(arg.slice(0, keyword.length) == keyword){
			const splits = arg.slice(keyword.length).split(/,/g);
			server = splits[0];
			if(splits.length > 1)
				ports.tcp = Number(splits[1]);
			if(splits.length > 2)
				ports.udp = Number(splits[2]);
			break;
		}
	}
	return {server, ports, forceExternalDll, noExtensionPackages, extensionPackages, customSlot};
}

const main = async function(): Promise<string> {
	const input: string = await getInputGame();
	const gameName: string = path.basename(input, ".exe");
	const {server, ports, forceExternalDll, noExtensionPackages, extensionPackages, customSlot} = await getServer();
	console.log(`Server: ${server} (TCP ${ports.tcp}, UDP ${ports.udp})`);
	if(customSlot){
		const totalSlots = customSlot.entries.reduce((s, e) => s + Math.ceil(e.count / 32), 0);
		console.log(`Progress sync: ${customSlot.entries.length} entries, ${totalSlots} uint32 slots -> default [sync] in __ONLINE_config.ini`);
	}
	if(await IsGMS(input)){
		console.log("Target: GameMaker Studio");
		await ConverterGMS(input, gameName, server, ports, customSlot);
	}else{
		console.log("Target: Game Maker 8");
		if(forceExternalDll)
			console.log("HTTP DLL mode: external (force_external_dll)");
		if(noExtensionPackages){
			process.env.IWPO_NO_EXTENSION_PACKAGES = "1";
			console.log("GM8 extension packages: disabled (no_extension_packages)");
		}
		if(extensionPackages){
			const mode: string = extensionPackages;
			const valid: Set<string> = new Set(["auto", "all", "fw_only", "wd_only", "gm_only", "none"]);
			if(!valid.has(mode)){
				console.log(`GM8 extension packages: ignoring unknown value "${mode}" (use auto|fw_only|wd_only|gm_only|none)`);
			}else{
				process.env.IWPO_EXT_PACKAGES = mode;
				console.log(`GM8 extension packages: ${mode}`);
			}
		}
		await ConverterGM8(input, gameName, server, ports, forceExternalDll, customSlot);
	}
	return "Success!";
}

main()
.then(console.log)
.catch(err => console.error(err.toString()))
.then(() => Utils.getString("Press enter to quit\n"))
