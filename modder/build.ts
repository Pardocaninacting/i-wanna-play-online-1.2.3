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
	console.log("Cleaning the build directory...");
	await Utils.rimraf(buildDir);
	console.log("Merging the javascript files into one...");
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
	console.log("Copying files...");
	await Promise.all([
		await Utils.rimraf(path.join(dataDir, "linux")),
		await Utils.rimraf(path.join(dataDir, "win", "ia32")),
		await fs.unlink(path.join(dataDir, "7x.sh")),
		await fs.unlink(path.join(dataDir, "7za")),
		await fs.copyFile(path.join(__dirname, "launcher.exe"), path.join(unpackedDir, "iwpo.exe")),
		await fs.copyFile(path.join(__dirname, "README.txt"), path.join(unpackedDir, "README.txt")),
		await fs.copyFile(path.join(__dirname, "node-portable.exe"), path.join(dataDir, "node-portable.exe")),
		await Utils.rimraf(path.join(dataDir, "tmp")),
		await fs.mkdir(path.join(dataDir, "tmp")),
		await fs.mkdir(path.join(dataDir, "gml")),
		await Utils.copyDir(path.join(__dirname, "gml"), path.join(dataDir, "gml")),
		await Utils.copyDir(path.join(__dirname, "lib"), path.join(dataDir, "lib")),
	]);
	const readmeFilename: string = path.join(unpackedDir, "README.txt");
	const readme: Array<string> = (await fs.readFile(readmeFilename, "utf8")).split(/\r\n|\r|\n/g);
	readme[0] += Utils.getVersion();
	await fs.writeFile(readmeFilename, readme.join("\r\n"), "utf8");
	await fs.writeFile(path.join(unpackedDir, "iwpo-settings.ini"), "[settings]\nserver=212.64.24.80\n", "utf8");
	console.log("Compressing the tool...");
	await zip(unpackedDir, path.join(buildDir, `iwpo ${Utils.getVersion()}.zip`));
	return "Success!";
}

build()
.then(console.log)
.catch(console.error);
