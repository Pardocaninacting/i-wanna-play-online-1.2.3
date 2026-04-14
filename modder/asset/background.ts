import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata"

const VERSION1: number = 710;
const VERSION2: number = 800;

export class Background extends Asset {
	public name: Buffer;
	public width: number;
	public height: number;
	public data: Array<number>;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Background {
		const background: Background = new Background();
		background.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION1)
			throw new Error("Background version1 is incorrect");
		if(data.readUInt32LE() != VERSION2)
			throw new Error("Background version2 is incorrect");
			background.width = data.readUInt32LE();
		background.height = data.readUInt32LE();
		background.data = [];
		if(background.width > 0 && background.height > 0){
			const dataLength: number = data.readUInt32LE();
			if(dataLength != background.width*background.height*4)
				throw new Error("Malformed data");
			/*background.data = [...*/data.readBuffer(dataLength)/*]*/;
		}
		return background;
	}
	public serialize(data: SmartBuffer): void {
		// 
	}
}
