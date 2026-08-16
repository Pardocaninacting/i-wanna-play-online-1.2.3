import fs from "fs-extra"
import path from "path"

export class GMLCode {
	private static prefix: string = "__ONLINE_";
	private static variables: Array<string> = [];
	public static addVariables(...variables: Array<string>): void {
		GMLCode.variables.splice(0, 0, ...variables);
	}
	public static is(variable: string): boolean {
		return GMLCode.variables.indexOf(variable) != -1;
	}
	private static parseGML(lines: Array<string>): [Array<string>, number] {
		let linesRead: number = 0;
		for(let i: number = 0; i < lines.length; ++i){
			const line: string = lines[i].trim();
			linesRead++;
			if(line.slice(0, 6) == "#endif"){
				return [lines.slice(0, i), linesRead-1];
			}else if(line.slice(0, 4) == "#if "){
				const beginIf: number = i;
				const not: boolean = line.slice(0, 8) == "#if not ";
				const variable: string = line.slice(not ? 8 : 4, line.length);
				const keep: boolean = not ? !GMLCode.is(variable) : GMLCode.is(variable);
				const [ifSection, lengthOfSection]: [Array<string>, number] = GMLCode.parseGML(lines.slice(i+1, lines.length));
				linesRead += lengthOfSection+1;
				if(lines[i+lengthOfSection+1].trim() != "#endif")
					throw new Error("Unexpected error in GML");
				lines.splice(beginIf, lengthOfSection+2);
				i = beginIf;
				if(keep){
					lines.splice(i, 0, ...ifSection);
					i += ifSection.length;
				}
				--i;
			}
		}
		return [lines, linesRead];
	}
	public static async getGML(filename: string, ...args: Array<Buffer>): Promise<Buffer> {
		// Read & process as latin-1 so every byte maps to a single JS code unit (0x00-0xFF).
		// This preserves arbitrary byte sequences in args (e.g. GBK-encoded gameName for GM8.0)
		// across the regex substitution and #if-directive parsing. Source files MUST contain
		// only ASCII bytes (any high-byte content like CJK comments must be stripped).
		let gml: string = await fs.readFile(path.join(__dirname, "gml", `${filename}.gml`), "latin1");
		gml = gml.replace(/@/g, GMLCode.prefix);
		gml = gml.replace(/\t/g, "");
		// The negative lookahead keeps %arg1 from eating the prefix of %arg10+:
		// without it, substituting %arg1 rewrites %arg10 into <arg1>0 before the
		// i=10 pass runs (the C# RenderTemplate uses literal Replace and is safe).
		for(let i: number = 0; i < args.length; ++i)
			gml = gml.replace(new RegExp(`%arg${i}(?![0-9])`, "g"), args[i].toString('latin1'));
		gml = GMLCode.parseGML(gml.split(/\r\n|\r|\n/g))[0].join("\r\n");
		return Buffer.from(gml,'latin1');
	}
	/**
	 * Same processing pipeline as getGML, but operates on a literal source string
	 * instead of reading from disk. Used for build-time-generated GML (e.g. the
	 * [mod] customSlot pack code).
	 */
	public static async getGMLFromString(source: string, ...args: Array<Buffer>): Promise<Buffer> {
		let gml: string = source;
		gml = gml.replace(/@/g, GMLCode.prefix);
		gml = gml.replace(/\t/g, "");
		for(let i: number = 0; i < args.length; ++i)
			gml = gml.replace(new RegExp(`%arg${i}(?![0-9])`, "g"), args[i].toString('latin1'));
		gml = GMLCode.parseGML(gml.split(/\r\n|\r|\n/g))[0].join("\r\n");
		return Buffer.from(gml, 'latin1');
	}
}
