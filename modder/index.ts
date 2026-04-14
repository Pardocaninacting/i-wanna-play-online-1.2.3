import fs from "fs-extra"
import path from "path"
import process from "process"
import { ConverterGM8 } from "./converterGM8"
import { ConverterGMS, IsGMS } from "./converterGMS"
import { Utils, Ports } from "./utils"

const getInputGame = async function(): Promise<string> {
	let input: string = "";
	// console.log(process.argv);
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
}

const readToolSettings = async function(): Promise<ToolSettings> {
	const settingsPath: string = path.join(__dirname, "..", "iwpo-settings.ini");
	if(!await fs.exists(settingsPath))
		return {};
	const content: string = await fs.readFile(settingsPath, "utf8");
	const result: ToolSettings = {};
	let inSection: boolean = false;
	for(const line of content.split(/\r?\n/)){
		const trimmed: string = line.trim();
		if(trimmed === "[settings]"){ inSection = true; continue; }
		if(trimmed.startsWith("[")){ inSection = false; continue; }
		if(!inSection || !trimmed || trimmed.startsWith(";") || trimmed.startsWith("#")) continue;
		const eq: number = trimmed.indexOf("=");
		if(eq < 0) continue;
		const key: string = trimmed.slice(0, eq).trim();
		const val: string = trimmed.slice(eq + 1).trim();
		if(!val) continue;
		switch(key){
			case "server": result.server = val; break;
			case "tcp_port": result.tcpPort = Number(val); break;
			case "udp_port": result.udpPort = Number(val); break;
			case "force_external_dll": result.forceExternalDll = val === "1" || val.toLowerCase() === "true"; break;
		}
	}
	return result;
}

const getServer = async function(): Promise<{server: string, ports: Ports, forceExternalDll: boolean}> {
	let server: string = "localhost";
	let ports: Ports = {
		tcp: 8002,
		udp: 8003,
	}
	let forceExternalDll: boolean = false;
	const toolSettings = await readToolSettings();
	if(toolSettings.server) server = toolSettings.server;
	if(toolSettings.tcpPort) ports.tcp = toolSettings.tcpPort;
	if(toolSettings.udpPort) ports.udp = toolSettings.udpPort;
	if(toolSettings.forceExternalDll) forceExternalDll = true;
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
	return {server, ports, forceExternalDll};
}

const main = async function(): Promise<string> {
	const input: string = await getInputGame();
	const gameName: string = path.basename(input, ".exe");
	const {server, ports, forceExternalDll} = await getServer();
	console.log(`Using Server ${server}, Ports`, ports);
	if(await IsGMS(input)){
		console.log("GameMaker Studio detected!");
		await ConverterGMS(input, gameName, server, ports);
	}else{
		console.log("Assuming it is Game Maker 8");
		if(forceExternalDll)
			console.log("Using external DLL mode (force_external_dll)");
		await ConverterGM8(input, gameName, server, ports, forceExternalDll);
	}
	return "Success!";
}

main()
.then(console.log)
.catch(err => console.log(err.toString()))
.then(() => Utils.getString("Press enter to quit\n"))
