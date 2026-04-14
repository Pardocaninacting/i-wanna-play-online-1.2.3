import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata";
import { CodeAction } from "./codeaction"

const VERSION: number = 500;
const VERSION_MOMENT: number = 400;

export class Timeline extends Asset {
	public name: Buffer;
	public moments: Array<[number, Array<CodeAction>]>;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Timeline {
		const timeline: Timeline = new Timeline();
		timeline.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Timeline version is incorrect");
		const momentCount: number = data.readUInt32LE();
		timeline.moments = new Array(momentCount);
		for(let i: number = 0; i < momentCount; ++i){
			const momentIndex: number = data.readUInt32LE();
			if(data.readUInt32LE() != VERSION_MOMENT)
				throw new Error("Timeline moment version is incorrect");
			const actionCount: number = data.readUInt32LE();
			const actions: Array<CodeAction> = new Array(actionCount);
			for(let j: number = 0; j < actionCount; ++j)
				actions[j] = CodeAction.fromCur(data);
			timeline.moments[i] = [momentIndex, actions];
		}
		return timeline;
	}
	public serialize(data: SmartBuffer): void {
		// 
	}
}
