import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata"

const VERSION: number = 800;

export class Font extends Asset {
	public name: Buffer;
	public content: Buffer;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Font {
		const from: number = data.readOffset;
		const font: Font = new Font();
		font.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Font version is incorrect");
		const sysName = data.readString(data.readUInt32LE());
		const size = data.readUInt32LE();
		const bold = data.readUInt32LE() != 0;
		const italic = data.readUInt32LE() != 0;
		const rangeStart = data.readUInt32LE();
		const rangeEnd = data.readUInt32LE();
		const charset = 0;
		const aaLevel = 0;
		const dMap = new Array(0x600).fill(0);
		for(let i: number = 0; i < 0x600; ++i)
			dMap[i] = data.readUInt32LE();
		const mapWidth = data.readUInt32LE();
		const mapHeight = data.readUInt32LE();
		const length: number = data.readUInt32LE();
		const pixelMap: Buffer = data.readBuffer(length);
		const to: number = data.readOffset;
			font.content = data.internalBuffer.subarray(from, to);
		return font;
	}
	public serialize(data: SmartBuffer): void {
		data.writeBuffer(this.content);
	}
}
