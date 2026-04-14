import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata"

const VERSION: number = 800;
const VERSION_COLLISION: number = 800;
const VERSION_FRAME: number = 800;

interface Frame {
	width: number;
	height: number;
	data: Array<number>;
}

interface CollisionMap {
	width: number;
	height: number;
	bBoxLeft: number;
	bBoxTop: number;
	bBoxRight: number;
	bBoxBottom: number;
	data: Array<boolean>;
}

export class Sprite extends Asset {
	public name: Buffer;
	public originX: number;
	public originY: number;
	public frames: Array<Frame>;
	public colliders: Array<CollisionMap>;
	public perFrameColliders: boolean;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Sprite {
		const sprite: Sprite = new Sprite();
		sprite.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Sprite version is incorrect");
		sprite.originX = data.readInt32LE();
		sprite.originY = data.readInt32LE();
		const frameCount: number = data.readUInt32LE();
		sprite.frames = [];
		sprite.colliders = [];
		sprite.perFrameColliders = false;
		if(frameCount != 0){
			sprite.frames = new Array(frameCount);
			for(let i: number = 0; i < frameCount; ++i){
				if(data.readUInt32LE() != VERSION_FRAME)
					throw new Error("Sprite frame version is incorrect");
				const frameWidth: number = data.readUInt32LE();
				const frameHeight: number = data.readUInt32LE();
				const pixelDataLength: number = data.readUInt32LE();
				/*const frameData: Array<number> = [...*/data.readBuffer(pixelDataLength)/*]*/;
				sprite.frames[i] = {
					width: frameCount,
					height: frameHeight,
					data: []/*frameData*/,
				}
			}
			const readCollision = function(data: SmartBuffer): CollisionMap {
				if(data.readUInt32LE() != VERSION_COLLISION)
					throw new Error("Sprite collision version is incorrect");
				const width: number = data.readUInt32LE();
				const height: number = data.readUInt32LE();
				const bBoxLeft: number = data.readUInt32LE();
				const bBoxRight: number = data.readUInt32LE();
				const bBoxTop: number = data.readUInt32LE();
				const bBoxBottom: number = data.readUInt32LE();
				const maskSize: number = width*height;
				const mask: Array<boolean> = [...data.readBuffer(maskSize*4)].map(n => n != 0);
				return {
					width: width,
					height: height,
					bBoxLeft: bBoxLeft,
					bBoxRight: bBoxRight,
					bBoxTop: bBoxTop,
					bBoxBottom: bBoxBottom,
					data: mask,
				}
			}
			sprite.perFrameColliders = data.readUInt32LE() != 0;
			if(sprite.perFrameColliders){
				sprite.colliders = new Array(frameCount);
				for(let i: number; i < frameCount; ++i)
					/*sprite.colliders[i] = */readCollision(data);
			}else{
				sprite.colliders = [readCollision(data)];
			}
		}
		return sprite;
	}
	public serialize(data: SmartBuffer): void {
		// 
	}
}
