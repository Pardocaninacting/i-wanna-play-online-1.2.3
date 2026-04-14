import { SmartBuffer } from "smart-buffer"

const VERSION: number = 440;
const PARAM_COUNT: number = 8;

export class CodeAction {
	public id: number;
	public appliesTo: number;
	public isCondition: boolean;
	public invertCondition: boolean;
	public isRelative: boolean;
	public libID: number;
	public actionKind: number;
	public actionIDX: number;
	public canBeRelative: number;
	public appliesToSomething: boolean;
	public fnName: Buffer;
	public fnCode: Buffer;
	public paramCount: number;
	public paramTypes: Array<number>;
	public paramStrings: Array<Buffer>;
	public static pieceOfCode(GML: Buffer): CodeAction {
		const codeAction: CodeAction = new CodeAction();
		codeAction.libID = 1;
		codeAction.id = 603;
		codeAction.actionKind = 7;
		codeAction.canBeRelative = 0;
		codeAction.isCondition = false;
		codeAction.appliesToSomething = true;
		codeAction.actionIDX = 2;
		codeAction.fnName = Buffer.from("");
		codeAction.fnCode = Buffer.from("");
		codeAction.paramCount = 1;
		codeAction.paramTypes = [1, 0, 0, 0, 0, 0, 0, 0];
		codeAction.appliesTo = -1;
		codeAction.isRelative = false;
		codeAction.paramStrings = new Array(8).fill(Buffer.from("0", 'ascii'));
		codeAction.paramStrings[0] = GML;
		codeAction.invertCondition = false;
		return codeAction;
	}
	public static fromCur(data: SmartBuffer): CodeAction {
		const a: number = data.readOffset;
		if(data.readUInt32LE() != VERSION)
			throw new Error("CodeAction version is incorrect");
		const codeAction: CodeAction = new CodeAction();
		codeAction.libID = data.readUInt32LE();
		codeAction.id = data.readUInt32LE();
		codeAction.actionKind = data.readUInt32LE();
		codeAction.canBeRelative = data.readUInt32LE();
		codeAction.isCondition = data.readUInt32LE() != 0;
		codeAction.appliesToSomething = data.readUInt32LE() != 0;
		codeAction.actionIDX = data.readUInt32LE();
		codeAction.fnName = data.readBuffer(data.readUInt32LE());
		codeAction.fnCode = data.readBuffer(data.readUInt32LE());
		codeAction.paramCount = data.readUInt32LE();
		if(codeAction.paramCount > PARAM_COUNT)
			throw new Error("Param count too large");
		if(data.readUInt32LE() != PARAM_COUNT)
			throw new Error("CodeAction param count is incorrect");
		codeAction.paramTypes = new Array(PARAM_COUNT);
		for(let i: number = 0; i < PARAM_COUNT; ++i)
			codeAction.paramTypes[i] = data.readUInt32LE();
		codeAction.appliesTo = data.readInt32LE();
		codeAction.isRelative = data.readUInt32LE() != 0;
		if(data.readUInt32LE() != PARAM_COUNT)
			throw new Error("CodeAction param count 2 is incorrect");
		codeAction.paramStrings = new Array(PARAM_COUNT);
		for(let i: number = 0; i < PARAM_COUNT; ++i)
			codeAction.paramStrings[i] = data.readBuffer(data.readUInt32LE());
		codeAction.invertCondition = data.readUInt32LE() != 0;
		return codeAction;
	}
	public writeTo(data: SmartBuffer): void {
		data.writeUInt32LE(VERSION);
		data.writeUInt32LE(this.libID);
		data.writeUInt32LE(this.id);
		data.writeUInt32LE(this.actionKind);
		data.writeUInt32LE(this.canBeRelative);
		data.writeUInt32LE(Number(this.isCondition));
		data.writeUInt32LE(Number(this.appliesToSomething));
		data.writeUInt32LE(this.actionIDX);
		data.writeUInt32LE(this.fnName.length);
		data.writeBuffer(this.fnName);
		data.writeUInt32LE(this.fnCode.length);
		data.writeBuffer(this.fnCode);
		data.writeUInt32LE(this.paramCount);
		data.writeUInt32LE(PARAM_COUNT);
		for(let i: number = 0, n: number = this.paramTypes.length; i < n; ++i)
			data.writeUInt32LE(this.paramTypes[i]);
		data.writeInt32LE(this.appliesTo);
		data.writeUInt32LE(Number(this.isRelative));
		data.writeUInt32LE(PARAM_COUNT);
		for(let i: number = 0, n: number = this.paramStrings.length; i < n; ++i){
			data.writeUInt32LE(this.paramStrings[i].length);
			data.writeBuffer(this.paramStrings[i]);
		}
		data.writeUInt32LE(Number(this.invertCondition));
	}
}
