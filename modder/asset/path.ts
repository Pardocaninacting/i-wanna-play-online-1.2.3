import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig } from "../gamedata"

const VERSION: number = 530;

enum ConnectionKind {
	StraightLine = 0,
	SmoothCurve = 1,
}

interface Point {
	x: number;
	y: number;
	speed: number;
}

const ConnectionKindFrom = function(n: number): ConnectionKind {
	switch(n){
		case 0:
			return ConnectionKind.StraightLine;
		case 1:
		default:
			return ConnectionKind.SmoothCurve;
	}
}

export class Path extends Asset {
	public name: Buffer;
	public connection: ConnectionKind;
	public precision: number;
	public closed: boolean;
	public points: Array<Point>;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Path {
		const path: Path = new Path();
		path.name = data.readBuffer(data.readUInt32LE());
		if(data.readUInt32LE() != VERSION)
			throw new Error("Path version is incorrect");
		path.connection = ConnectionKindFrom(data.readUInt32LE());
		path.closed = data.readUInt32LE() != 0;
		path.precision = data.readUInt32LE();
		const pointCount = data.readUInt32LE();
		path.points = new Array(pointCount);
		for(let i: number = 0; i < pointCount; ++i){
			path.points[i] = {
				x: data.readDoubleLE(),
				y: data.readDoubleLE(),
				speed: data.readDoubleLE(),
			}
		}
		return path;
	}
	public serialize(data: SmartBuffer): void {
		// 
	}
}
