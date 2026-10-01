import { exec } from "child_process"
import { ncp } from "ncp"
import readline from "readline"
import rimraf from "rimraf"
import process from "process"
import fs from "fs"
import path from "path"
import http from "http"
import https from "https"

export interface Ports {
	tcp: number,
	udp: number,
}

export class Utils {
	public static overflowingAdd = function(n1: number, n2: number, bits: number): [number, boolean] {
		const max: number = Math.pow(2, bits);
		n1 += n2;
		return [n1%max, n1 >= max];
	}
	public static overflowingSub = function(n1: number, n2: number, bits: number): [number, boolean] {
		const max: number = Math.pow(2, bits);
		n1 -= n2;
		return [((n1%max)+max)%max, n1 < 0];
	}
	public static bytesToU32(bytes: [number, number, number, number]): number {
		let result: number = 0;
		const bytesCount: number = 4;
		for(let i = 0; i < bytesCount; ++i)
			result += (bytes[i] << 8*(bytesCount-i-1)) >>> 0;
		return result;
	}
	public static u32ToBytes(u32: number): [number, number, number, number] {
		const result: [number, number, number, number] = [0, 0, 0, 0];
		const bytesCount: number = 4;
		for(let i = 0; i < bytesCount; ++i)
			result[i] = ((u32 >> (8*(bytesCount-i-1))) & 0xFF) >>> 0;
		return result;
	}
	public static swapBytes32(input: number): number {
		const [a, b, c, d]: [number, number, number, number] = Utils.u32ToBytes(input);
		return Utils.bytesToU32([d, c, b, a]);
	}
	public static exec(cmd: string, cwd: string, verbose: boolean = false): Promise<string> {
		return new Promise((resolve, reject) => {
			const std = {
				out: "",
				err: "",
			}
			const process = exec(cmd, {
				cwd: cwd,
				windowsHide: true,
				maxBuffer: 16*1024*1024,
			});
			for(const stream in std)
				process[`std${stream}`].on("data", function(data: string): void {
					if(verbose){
						if(stream == "out")
							console.log(data);
						else
							console.error(data);
					}
					std[stream] += data;
				});
			process.on("error", function(err: Error): void {
				reject(err);
			});
			process.on("close", function(code: number): void {
				if(code){
					const outputChunks: Array<string> = [std.err.trim(), std.out.trim()].filter(Boolean);
					const output: string = outputChunks.join("\n") || `Command failed with exit code ${code}`;
					reject(new Error(output));
				}else
					resolve(std.out);
			});
		});
	}
	public static rimraf(dir: string): Promise<string> {
		return new Promise(function(resolve: (a: undefined) => void, reject: (err: NodeJS.ErrnoException) => void): void {
			rimraf(dir, function(err): void {
				if(err)
					reject(err);
				else
					resolve(undefined);
			});
		});
	}
	public static copyDir(srcDir: string, destDir: string): Promise<void> {
		return new Promise(function(resolve, reject): void {
			ncp(srcDir, destDir, function(err: any): void {
				if(err)
					reject(err);
				else
					resolve();
			});
		});
	}
	// Resolves a tool-data subdir across the two layouts the converter runs in:
	// dev (modder/<name>, __dirname = modder/) and packaged (build/iwpo/<name>
	// at the top level next to iwpo.exe, __dirname = data/). Returns "" when the
	// subdir exists in neither (the caller then skips the deployment).
	public static resolveToolSubdir(name: string): string {
		const dev: string = path.join(__dirname, name);
		if(fs.existsSync(dev)) return dev;
		const packaged: string = path.join(__dirname, "..", name);
		if(fs.existsSync(packaged)) return packaged;
		return "";
	}
	public static getString(message: string): Promise<string> {
		const rl = readline.createInterface({
			input: process.stdin,
			output: process.stdout,
		});
		return new Promise((resolve, _) => {
			rl.question(message, function(answer: string): void {
				rl.close();
				resolve(answer);
			});
		});
	}
	public static getVersion(): string {
		return require("./package.json").version;
	}
	// Update check, run between "Success!" and the enter prompt: fetch the
	// version marker hosted on the site and say so when it differs from the
	// local build. Any failure (offline, DNS, timeout) is silent - converting
	// the game is the point, the notice is a courtesy.
	public static checkForUpdate(): Promise<void> {
		const url: string = "https://iwannaplay.online/version.txt";
		// node-portable is Node 10 with a 2018 root store: when the site's
		// certificate chain stops validating there, ask over plain HTTP. The
		// strict version pattern is what keeps that answer harmless.
		return Utils.fetchText(url)
			.catch(function(err: NodeJS.ErrnoException): Promise<string> {
				if(/CERT|ISSUER|SIGNATURE|SELF_SIGNED|EPROTO/.test(err.code || ""))
					return Utils.fetchText(url.replace(/^https:/, "http:"));
				throw err;
			})
			.then(function(body: string): void {
				const latest: string = body.trim();
				const local: string = Utils.getVersion();
				if(/^\d+\.\d+\.\d+(_[a-z]+_\d+)?$/i.test(latest) && latest !== local)
					console.log(`A newer version is available: ${latest} (you have ${local}) - https://iwannaplay.online`);
			})
			.catch(function(): void {});
	}
	private static fetchText(url: string): Promise<string> {
		return new Promise(function(resolve, reject): void {
			const get = url.startsWith("https:") ? https.get : http.get;
			const req = get(url, { timeout: 4000 }, function(res) {
				if(res.statusCode !== 200){ res.resume(); reject(new Error(`HTTP ${res.statusCode}`)); return; }
				let body: string = "";
				res.setEncoding("utf8");
				res.on("data", function(chunk: string){ body += chunk; });
				res.on("end", function(){ resolve(body); });
				res.on("error", reject);
			});
			req.on("timeout", function(){ req.abort(); reject(new Error("timeout")); });
			req.on("error", reject);
		});
	}
}
