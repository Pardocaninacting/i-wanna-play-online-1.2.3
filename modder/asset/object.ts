import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { CodeAction } from "./codeaction"
import { GameConfig } from "../gamedata"

const VERSION: number = 430;
const VERSION_EVENT: number = 400;

export class GMObject extends Asset {
	public name: Buffer;
	public spriteIndex: number;
	public solid: boolean;
	public visible: boolean;
	public depth: number;
	public persistent: boolean;
	public parentIndex: number;
	public maskIndex: number;
	public events: Array<Array<[number, Array<CodeAction>]>>;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): GMObject {
		const object: GMObject = new GMObject();
		object.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Object version is incorrect");
		object.spriteIndex = data.readInt32LE();
		object.solid = data.readUInt32LE() != 0;
		object.visible = data.readUInt32LE() != 0;
		object.depth = data.readInt32LE();
		object.persistent = data.readUInt32LE() != 0;
		object.parentIndex = data.readInt32LE();
		object.maskIndex = data.readInt32LE();
		const eventListCount: number = data.readUInt32LE();
		if(eventListCount != 11)
			throw new Error("Malformed data");
		object.events = new Array(eventListCount+1);
		for(let i: number = 0; i <= eventListCount; ++i){
			const subEventList: Array<[number, Array<CodeAction>]> = new Array(0);
			while(true){
				const index: number = data.readInt32LE();
				if(index == -1)
					break;
				if(data.readUInt32LE() != VERSION_EVENT)
					throw new Error("Object event version is incorrect");
				const actionCount: number = data.readUInt32LE();
				const actions: Array<CodeAction> = new Array(actionCount);
				for(let j: number = 0; j < actionCount; ++j)
					actions[j] = CodeAction.fromCur(data);
				subEventList.push([index, actions]);
			}
			object.events[i] = subEventList;
		}
		return object;
	}
	public serialize(data: SmartBuffer): void {
		data.writeUInt32LE(Buffer.from(this.name).length);
		data.writeBuffer(this.name);
		data.writeUInt32LE(VERSION);
		data.writeInt32LE(this.spriteIndex);
		data.writeUInt32LE(Number(this.solid));
		data.writeUInt32LE(Number(this.visible));
		data.writeInt32LE(this.depth);
		data.writeUInt32LE(Number(this.persistent));
		data.writeInt32LE(this.parentIndex);
		data.writeInt32LE(this.maskIndex);
		data.writeUInt32LE(this.events.length-1);
		for(let i: number = 0, n: number = this.events.length; i < n; ++i){
			const subList: Array<[number, Array<CodeAction>]> = this.events[i];
			for(let j: number = 0, m: number = subList.length; j < m; ++j){
				const [sub, actions]: [number, Array<CodeAction>] = subList[j];
				data.writeUInt32LE(sub);
				data.writeUInt32LE(VERSION_EVENT);
				data.writeUInt32LE(actions.length);
				for(let k: number = 0, o: number = actions.length; k < o; ++k)
					actions[k].writeTo(data);
			}
			data.writeInt32LE(-1);
		}
	}
	private addCode(GML: Buffer, category: number, value: number): void {
		if(GML.slice(0, 1).equals(Buffer.from("\n", "ascii")))
			GML = GML.slice(1, GML.length);
		if(GML.slice(0, 2).equals(Buffer.from("\n\t", "ascii")))
			GML = GML.slice(2, GML.length);
		if(GML.slice(0, 3).equals(Buffer.from("\n\t\t", "ascii")))
			GML = GML.slice(3, GML.length);
		if(this.events[category].filter(element => element[0] == value).length == 0)
			this.events[category].push([value, [CodeAction.pieceOfCode(GML)]]);
		else
			this.events[category].filter(element => element[0] == value)[0][1].push(CodeAction.pieceOfCode(GML));
	}
	public addCreateCode(GML: Buffer): void {
		this.addCode(GML, 0, 0);
	}
	public addEndStepCode(GML: Buffer): void {
		this.addCode(GML, 3, 2);
	}
	public addDrawCode(GML: Buffer): void {
		this.addCode(GML, 8, 0);
	}
	public addGameEndCode(GML: Buffer): void {
		this.addCode(GML, 7, 3);
	}
}
