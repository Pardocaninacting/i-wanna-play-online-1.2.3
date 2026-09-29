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
	injectIntoStep?: boolean;
	customSlot?: CustomSlotConfig | null;
	defines?: Map<string, string>;
}

const readToolSettings = async function(): Promise<ToolSettings> {
	const settingsPath: string = path.join(__dirname, "..", "iwpo-settings.ini");
	if(!await fs.exists(settingsPath))
		return {};
	const content: string = await fs.readFile(settingsPath, "utf8");
	const result: ToolSettings = {};
	let currentSection: string = "";
	const modSection: Record<string, string> = {};
	const defines: Map<string, string> = new Map<string, string>();
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
				// dead parameter (only logged, never changed behaviour); kept out of the
				// config like the extension_packages bisection switches above.
				case "force_external_dll":
					console.log(`iwpo-settings.ini: [settings] ${key} is retired and ignored (no effect)`);
					break;
				// extension_packages / no_extension_packages are deliberately NOT accepted
				// here any more: they are bisection switches, and a persisted global wd_only
				// once silently killed all CJK rendering for a player. Use the per-game ini
				// (games/<game>.ini [iwpo] extension_packages=...) or the env var.
				case "no_extension_packages":
				case "extension_packages":
					console.log(`iwpo-settings.ini: [settings] ${key} is ignored (bisection switch; set it per-game in games/<game>.ini [iwpo] instead)`);
					break;
				case "inject_into_step": result.injectIntoStep = val === "1" || val.toLowerCase() === "true"; break;
			}
		}else if(currentSection === "mod"){
			modSection[key.toLowerCase()] = val;
		}else if(currentSection === "iwpo"){
			// TheBiob-style iwpo.* defines (case-sensitive keys, e.g. saveGame=mySaveScript).
			if(val) defines.set(`iwpo.${key}`, val);
		}
	}
	if(hasModSection){
		result.customSlot = parseCustomSlotConfig(modSection);
	}
	result.defines = defines;
	return result;
}

// Per-game define overrides, loaded from games/<gameName>.ini next to iwpo-settings.ini.
// Only the [iwpo] section is honored; values override the global settings file.
const readGameDefines = async function(gameName: string, defines: Map<string, string>): Promise<void> {
	const gameIniPath: string = path.join(__dirname, "..", "games", gameName + ".ini");
	if(!await fs.exists(gameIniPath))
		return;
	console.log(`Reading per-game config 'games/${gameName}.ini'`);
	const content: string = await fs.readFile(gameIniPath, "utf8");
	let currentSection: string = "";
	for(const line of content.split(/\r?\n/)){
		const trimmed: string = line.trim();
		if(trimmed.startsWith("[") && trimmed.endsWith("]")){
			currentSection = trimmed.slice(1, -1).toLowerCase();
			continue;
		}
		if(!trimmed || trimmed.startsWith(";") || trimmed.startsWith("#")) continue;
		const eq: number = trimmed.indexOf("=");
		if(eq < 0) continue;
		if(currentSection !== "iwpo") continue;
		const key: string = trimmed.slice(0, eq).trim();
		const val: string = trimmed.slice(eq + 1).trim();
		if(val) defines.set(`iwpo.${key}`, val);
	}
}

const getServer = async function(): Promise<{server: string, ports: Ports, forceExternalDll: boolean, noExtensionPackages: boolean, extensionPackages: string | null, injectIntoStep: boolean, customSlot: CustomSlotConfig | null, defines: Map<string, string>}> {
	let server: string = "localhost";
	let ports: Ports = {
		tcp: 8002,
		udp: 8003,
	}
	let forceExternalDll: boolean = false;
	let noExtensionPackages: boolean = false;
	let extensionPackages: string | null = null;
	let injectIntoStep: boolean = false;
	const toolSettings = await readToolSettings();
	if(toolSettings.server) server = toolSettings.server;
	if(toolSettings.tcpPort) ports.tcp = toolSettings.tcpPort;
	if(toolSettings.udpPort) ports.udp = toolSettings.udpPort;
	if(toolSettings.forceExternalDll) forceExternalDll = true;
	if(toolSettings.noExtensionPackages) noExtensionPackages = true;
	if(toolSettings.extensionPackages) extensionPackages = toolSettings.extensionPackages;
	if(toolSettings.injectIntoStep) injectIntoStep = true;
	const customSlot: CustomSlotConfig | null = toolSettings.customSlot ? toolSettings.customSlot : null;
	const defines: Map<string, string> = toolSettings.defines ? toolSettings.defines : new Map<string, string>();
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
	return {server, ports, forceExternalDll, noExtensionPackages, extensionPackages, injectIntoStep, customSlot, defines};
}

const main = async function(): Promise<string> {
	const input: string = await getInputGame();
	const gameName: string = path.basename(input, ".exe");
	const {server, ports, forceExternalDll, noExtensionPackages, extensionPackages, injectIntoStep, customSlot, defines} = await getServer();
	// Define overrides: per-game ini overrides global settings, --define wins over both.
	await readGameDefines(gameName, defines);
	for(const arg of process.argv){
		if(arg.startsWith("--define:")){
			const pair: Array<string> = arg.substring("--define:".length).split("=");
			if(pair.length >= 2){
				// CLI keys get the same iwpo. prefix the ini sections apply implicitly.
				const key: string = pair[0].startsWith("iwpo.") ? pair[0] : `iwpo.${pair[0]}`;
				defines.set(key, pair.slice(1).join("="));
			}
		}
	}
	console.log(`Server: ${server} (TCP ${ports.tcp}, UDP ${ports.udp})`);
	if(customSlot){
		const totalSlots = customSlot.entries.reduce((s, e) => s + Math.ceil(e.count / 32), 0);
		console.log(`Sync defaults: ${customSlot.entries.length} entries, ${totalSlots} slots`);
	}
	// Unity games are not supported: their architecture differs fundamentally from
	// GameMaker, and conversion would silently produce a broken result (TheBiob b22
	// implemented full Unity support; we deliberately only detect and refuse).
	if(await fs.exists(path.join(path.dirname(input), "UnityPlayer.dll"))){
		throw new Error("Unity engine detected (UnityPlayer.dll found next to the game). Unity games are not supported by IWPO.");
	}
	if(await IsGMS(input)){
		console.log("Target: GameMaker Studio");
		await ConverterGMS(input, gameName, server, ports, customSlot, defines);
	}else{
		console.log("Target: Game Maker 8");
		if(forceExternalDll)
			console.log("HTTP DLL: external");
		if(injectIntoStep)
			console.log("Tick injection: Step + world helper scheduler");
		if(noExtensionPackages){
			process.env.IWPO_NO_EXTENSION_PACKAGES = "1";
			console.log("GM8 extension packages: disabled");
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
		await ConverterGM8(input, gameName, server, ports, forceExternalDll, customSlot, injectIntoStep, defines);
	}
	return "Success!";
}

main()
.then(console.log)
.catch(err => console.error(err.toString()))
// update notice after the outcome line, before the pause; it never fails the run
.then(() => Utils.checkForUpdate())
.then(() => Utils.getString("Press enter to quit\n"))
