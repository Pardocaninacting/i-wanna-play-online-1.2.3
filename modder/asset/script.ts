import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata"

const VERSION: number = 800;

export class Script extends Asset {
	public name: Buffer;
	public source: Buffer;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Script {
		const script: Script = new Script();
		script.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Script version is incorrect");
		script.source = data.readBuffer(data.readUInt32LE());
		return script;
	}
	public serialize(data: SmartBuffer): void {
		data.writeUInt32LE(Buffer.from(this.name).length);
		data.writeBuffer(this.name);
		data.writeUInt32LE(VERSION);
		data.writeUInt32LE(Buffer.from(this.source).length);
		data.writeBuffer(this.source);
	}
}
