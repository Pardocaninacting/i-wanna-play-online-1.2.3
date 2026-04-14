import { Asset } from "../asset"
import { SmartBuffer } from "smart-buffer"
import { GameConfig } from "../gamedata";

const VERSION: number = 800;

enum TriggerKind {
	Step = 0,
	BeginStep = 1,
	EndStep = 2,
}

const TriggerKindFrom = function(n: number): TriggerKind {
	switch(n){
		case 1:
			return TriggerKind.BeginStep;
		case 2:
			return TriggerKind.EndStep;
		case 0:
		default:
			return TriggerKind.Step;
	}
}

export class Trigger extends Asset {
	public name: Buffer;
	public condition: Buffer;
	public moment: TriggerKind;
	public constantName: Buffer;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Trigger {
		if(data.readUInt32LE() != VERSION)
			throw new Error("Trigger version is incorrect");
		const trigger: Trigger = new Trigger();
		trigger.name = data.readBuffer(data.readUInt32LE());
		trigger.condition = data.readBuffer(data.readUInt32LE());
		trigger.moment = TriggerKindFrom(data.readUInt32LE());
		trigger.constantName = data.readBuffer(data.readUInt32LE());
		return trigger;
	}
	public serialize(data: SmartBuffer): void {
		// 
	}
}
