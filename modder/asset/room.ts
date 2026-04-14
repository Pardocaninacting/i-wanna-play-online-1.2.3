import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig, GameVersion } from "../gamedata"

interface Colour {
    r: number;
    g: number;
    b: number;
    a: number;
}

interface Background {
    visibleOnStart: boolean;
    isForeground: boolean;
    sourceBg: number;
    xoffset: number;
    yoffset: number;
    tileHorz: boolean;
    tileVert: boolean;
    hspeed: number;
    vspeed: number;
    stretch: boolean;
}

interface Instance {
    x: number;
    y: number;
    object: number;
    id: number;
    creationCode: Buffer;
    xscale: number;
    yscale: number;
    blend: number;
    angle: number;
}

interface Tile {
    x: number;
    y: number;
    sourceBg: number;
    tilex: number;
    tiley: number;
    width: number;
    height: number;
    depth: number;
    id: number;
    xscale: number;
    yscale: number;
    blend: number;
}

interface ViewFollowData {
    hborder: number;
    vborder: number;
    hspeed: number;
    vspeed: number;
    target: number;
}

interface View {
    visible: boolean;
    sourcex: number;
    sourcey: number;
    sourcew: number;
    sourceh: number;
    portx: number;
    porty: number;
    portw: number;
    porth: number;
    following: ViewFollowData;
}

export class Room extends Asset {
    public name: Buffer;
    public caption: Buffer;
    public width: number;
    public height: number;
    public speed: number;
    public persistent: boolean;
    public bgColour: Colour;
    public clearScreen: boolean;
    public clearRegion: boolean;
    public creationCode: Buffer;
    public backgrounds: Array<Background>;
    public viewsEnabled: boolean;
    public views: Array<View>;
    public instances: Array<Instance>;
    public tiles: Array<Tile>;

	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): Room {
		const room: Room = new Room();
		room.name = data.readBuffer(data.readUInt32LE());
        let entryVersion = data.readUInt32LE();
        room.caption = data.readBuffer(data.readUInt32LE());
        room.width = data.readUInt32LE();
        room.height = data.readUInt32LE();
        room.speed = data.readUInt32LE();
        room.persistent = data.readUInt32LE() != 0;
        room.bgColour = { a: data.readUInt8(), b: data.readUInt8(), g: data.readUInt8(), r: data.readUInt8() };
        switch(gameConfig.version){
			case GameVersion.GameMaker80:
                room.clearScreen = data.readUInt32LE() != 0;
                room.clearRegion = true;
                break;
			case GameVersion.GameMaker81:
                let x: number = data.readUInt32LE();
                room.clearScreen = (x & 1) != 0;
                room.clearRegion = (x & 2) == 0;
                break;
        }
        room.creationCode = data.readBuffer(data.readUInt32LE());
        let backgroundCount = data.readUInt32LE();
		room.backgrounds = new Array(backgroundCount);
		for(let i: number = 0; i < backgroundCount; i++){
            room.backgrounds[i] = {
                visibleOnStart: data.readUInt32LE() != 0,
                isForeground: data.readUInt32LE() != 0,
                sourceBg: data.readInt32LE(),
                xoffset: data.readInt32LE(),
                yoffset: data.readInt32LE(),
                tileHorz: data.readUInt32LE() != 0,
                tileVert: data.readUInt32LE() != 0,
                hspeed: data.readInt32LE(),
                vspeed: data.readInt32LE(),
                stretch: data.readUInt32LE() != 0,
            }
        }
        room.viewsEnabled = data.readUInt32LE() != 0;
        let viewCount: number =  data.readUInt32LE();
        room.views = new Array(viewCount);
        for(let i: number = 0; i < viewCount; i++){
            room.views[i] = {
                visible: data.readUInt32LE() != 0,
                sourcex: data.readInt32LE(),
                sourcey: data.readInt32LE(),
                sourcew: data.readUInt32LE(),
                sourceh: data.readUInt32LE(),
                portx: data.readInt32LE(),
                porty: data.readInt32LE(),
                portw: data.readUInt32LE(),
                porth: data.readUInt32LE(),
                following: {
                    hborder: data.readInt32LE(),
                    vborder: data.readInt32LE(),
                    hspeed: data.readInt32LE(),
                    vspeed: data.readInt32LE(),
                    target: data.readInt32LE(),
                }
            }
        }
        let instanceCount = data.readUInt32LE();
        room.instances = new Array(instanceCount);
        for(let i: number = 0; i < instanceCount; i++){
            room.instances[i] = {
                x: data.readInt32LE(),
                y: data.readInt32LE(),
                object: data.readInt32LE(),
                id: data.readInt32LE(),
                creationCode: data.readBuffer(data.readUInt32LE()),
                xscale: (entryVersion >= 810) ? data.readDoubleLE() : 1.0,
                yscale: (entryVersion >= 810) ? data.readDoubleLE() : 1.0,
                blend: (entryVersion >= 810) ? data.readUInt32LE() : 4294967295,
                angle: (entryVersion >= 811) ? data.readDoubleLE() : 0.0,
            }
        }
        let tileCount = data.readUInt32LE();
        room.tiles = new Array(tileCount);
        for(let i: number = 0; i < tileCount; i++){
            room.tiles[i] = {
                x: data.readInt32LE(),
                y: data.readInt32LE(),
                sourceBg: data.readInt32LE(),
                tilex: data.readUInt32LE(),
                tiley: data.readUInt32LE(),
                width: data.readUInt32LE(),
                height: data.readUInt32LE(),
                depth: data.readInt32LE(),
                id: data.readInt32LE(),
                xscale: (entryVersion >= 810) ? data.readDoubleLE() : 1.0,
                yscale: (entryVersion >= 810) ? data.readDoubleLE() : 1.0,
                blend: (entryVersion >= 810) ? data.readUInt32LE() : 4294967295,
            }
        }
        return room;
    }

	public serialize(data: SmartBuffer): void {
		// 
	}
}