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
	public addStepCode(GML: Buffer): void {
		this.addCode(GML, 3, 0);
	}
	public addEndStepCode(GML: Buffer): void {
		this.addCode(GML, 3, 2);
	}
	public addDrawCode(GML: Buffer): void {
		this.addCode(GML, 8, 0);
	}
	// GM8.2-native Draw GUI event (event group 11, the trigger group GM8.2
	// repurposed): runs once per frame after all regular draws, in window pixel
	// coordinates. The subtype must match the index of the game's "Draw GUI"
	// trigger asset - the runner dispatches Draw GUI at that subtype only
	// (TV: 0, DLDC: 1). GM8.0/8.1 runners keep group 11 as triggers and never
	// dispatch it as a draw event - attaching HUD code there silently never
	// runs (E2 regression). Only use when isGM82 detection fired.
	public addDrawGuiCode(GML: Buffer, subType: number = 0): void {
		this.addCode(GML, 11, subType);
	}
	public addGameEndCode(GML: Buffer): void {
		this.addCode(GML, 7, 3);
	}
	// Read-only event presence check. Category/subtype are raw GM8 numbers
	// (Create = 0/0, Draw = 8/0); true when the object carries the event with at
	// least one action. Used by the skin injector to pick replace vs overlay
	// draw code without disturbing the existing event list.
	public hasEvent(event: number, type: number): boolean {
		return this.events[event].findIndex(element => element[0] == type && element[1].length > 0) >= 0;
	}
	// C4 (TheBiob object.ts heritage): checks whether any code action of the
	// given event contains searchStr. Category/subtype are raw GM8 numbers
	// (Create = 0/0, Draw = 8/0). Matches require an identifier boundary on the
	// left (so "xscale=1" does not match inside "image_xscale=1") and no digit/
	// dot on the right (so "facing=1" does not match "facing=10").
	public hasStringInEvent(event: number, type: number, searchStr: string, ignoreWhitespace: boolean = false): boolean {
		if (ignoreWhitespace)
			searchStr = searchStr.replace(/\s/g, '');
		const isIdentChar = function(ch: string): boolean {
			return ch >= 'A' && ch <= 'Z' || ch >= 'a' && ch <= 'z' || ch >= '0' && ch <= '9' || ch == '_';
		}
		const search = function(input: Buffer): boolean {
			let eventCode: string = input.toString();
			if (ignoreWhitespace)
				eventCode = eventCode.replace(/\s/g, '');
			let idx: number = eventCode.indexOf(searchStr);
			while (idx >= 0) {
				const leftOk: boolean = idx == 0 || !isIdentChar(eventCode[idx-1]);
				const rightIdx: number = idx + searchStr.length;
				const rightCh: string = rightIdx < eventCode.length ? eventCode[rightIdx] : "";
				const rightOk: boolean = rightCh == "" || !(rightCh >= '0' && rightCh <= '9' || rightCh == '.');
				if (leftOk && rightOk)
					return true;
				idx = eventCode.indexOf(searchStr, idx + 1);
			}
			return false;
		}
		return this.events[event].findIndex(element =>
			element[0] == type
			&& element[1].findIndex(action =>
				action.actionKind == 7
				&& typeof(action.paramStrings[0]) !== 'undefined'
				&& search(action.paramStrings[0])) >= 0) >= 0;
	}
}
