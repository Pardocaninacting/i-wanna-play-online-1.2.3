import fs from "fs-extra"
import path from "path"
import ncc from "@zeit/ncc"
import process from "process"
import _7zip from "7zip-min"
import { Utils } from "./utils"

const zip = function(folder: string, file: string): Promise<void> {
	return new Promise((resolve, reject) => {
		_7zip.pack(folder, file, function(err): void {
			if(err)
				reject(err);
			else
				resolve();
		});
	});
}

const build = async function(): Promise<string> {
	const buildDir: string = path.join(__dirname, "build");
	const unpackedDir: string = path.join(buildDir, "iwpo");
	const dataDir: string = path.join(unpackedDir, "data");
	const nccCli: string = path.join(__dirname, "node_modules", "@zeit", "ncc", "dist", "ncc", "cli.js");
	const nodeMajorVersion: number = Number(process.versions.node.split(".")[0]);
	const nodeCompatFlags: Array<string> = nodeMajorVersion >= 17 ? ["--openssl-legacy-provider"] : [];
	console.log("Cleaning build directory...");
	// N4 review: gml templates are ASCII-only by contract (getGMLCode.ts). A
	// stray non-ASCII byte once cost us a conversion-time compile error, so
	// fail the build instead of shipping one.
	{
		const gmlDir: string = path.join(__dirname, "gml");
		for(const f of fs.readdirSync(gmlDir)){
			if(!f.endsWith(".gml")) continue;
			const content: string = fs.readFileSync(path.join(gmlDir, f), "latin1");
			// eslint-disable-next-line no-control-regex
			if(/[^\x00-\x7F]/.test(content))
				throw new Error(`gml/${f} contains non-ASCII characters (templates must be ASCII-only)`);
		}
		console.log("GML ASCII check passed");
	}
	// IW69 lesson: a string literal ending in an odd-length backslash run
	// (e.g. "...\") escapes its own closing quote under the GMS2.3 lexer,
	// which then swallows every following line into the string and fails the
	// whole conversion with "Direct newline found in string". GM8 tolerates
	// it, so without this guard it only ever blows up on the GMS path.
	{
		const gmlDir: string = path.join(__dirname, "gml");
		const badEscape: RegExp = /(?:^|[^\\])(?:\\\\)*\\"/;
		for(const f of fs.readdirSync(gmlDir)){
			if(!f.endsWith(".gml")) continue;
			const lines: Array<string> = fs.readFileSync(path.join(gmlDir, f), "latin1").split(/\r\n|\r|\n/);
			for(let li: number = 0; li < lines.length; ++li){
				if(badEscape.test(lines[li]))
					throw new Error(`gml/${f}:${li + 1} has a string literal ending in a backslash (breaks the GMS2 compiler; use chr(92) concatenation instead)`);
			}
		}
		console.log("GML string-escape check passed");
	}
	await Utils.rimraf(buildDir);
	console.log("Bundling JavaScript...");
	await fs.mkdir(buildDir);
	await fs.mkdir(unpackedDir);
	await Utils.exec([
		`"${process.execPath}"`,
		...nodeCompatFlags,
		`"${nccCli}"`,
		"build",
		`"${path.join(__dirname, "index.js")}"`,
		"-o",
		`"${dataDir}"`,
	].join(" "), __dirname);
	console.log("Copying runtime files...");
	await Promise.all([
		await Utils.rimraf(path.join(dataDir, "linux")),
		await Utils.rimraf(path.join(dataDir, "win", "ia32")),
		await fs.unlink(path.join(dataDir, "7x.sh")),
		await fs.unlink(path.join(dataDir, "7za")),
		await fs.copyFile(path.join(__dirname, "launcher.exe"), path.join(unpackedDir, "iwpo.exe")),
		await fs.copyFile(path.join(__dirname, "README.txt"), path.join(unpackedDir, "README.txt")),
		await fs.copyFile(path.join(__dirname, "PLAYER_GUIDE.txt"), path.join(unpackedDir, "PLAYER_GUIDE.txt")),
		await fs.copyFile(path.join(__dirname, "node-portable.exe"), path.join(dataDir, "node-portable.exe")),
		await Utils.rimraf(path.join(dataDir, "tmp")),
		await fs.mkdir(path.join(dataDir, "tmp")),
		await fs.mkdir(path.join(dataDir, "gml")),
		await Utils.copyDir(path.join(__dirname, "gml"), path.join(dataDir, "gml")),
		await Utils.copyDir(path.join(__dirname, "lib"), path.join(dataDir, "lib")),
		// i18n language files ride next to gml/ inside data/ (the converter deploys
		// them beside the game); the skin library is top-level so players can find it
		await Utils.copyDir(path.join(__dirname, "lang"), path.join(dataDir, "lang")),
		await Utils.copyDir(path.join(__dirname, "iwposkins"), path.join(unpackedDir, "iwposkins")),
		// Per-game define overrides (readGameDefines reads ../games/<gameName>.ini).
		await fs.copy(path.join(__dirname, "games"), path.join(unpackedDir, "games")),
	]);
	const readmeFilename: string = path.join(unpackedDir, "README.txt");
	const readme: Array<string> = (await fs.readFile(readmeFilename, "utf8")).split(/\r\n|\r|\n/g);
	readme[0] += Utils.getVersion();
	await fs.writeFile(readmeFilename, readme.join("\r\n"), "utf8");
	await fs.writeFile(path.join(unpackedDir, "iwpo-settings.ini"), [
		"[settings]",
		"server=212.64.24.80",
		"; inject_into_step=1",
		"",
		"[iwpo]",
		"; GM8.0 CJK rendering via the built-in bitmap atlas (FoxWriting is",
		"; unmaintained and crashes on current GPU drivers). Delete to re-enable fw.",
		"cjk_atlas=1",
	].join("\n") + "\n", "utf8");
	console.log("Packing release archive...");
	await zip(unpackedDir, path.join(buildDir, `iwpo ${Utils.getVersion()}.zip`));
	return "Success!";
}

build()
.then(console.log)
.catch(console.error);
