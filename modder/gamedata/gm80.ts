import crypto from "crypto"
import { SmartBuffer } from "smart-buffer"
import { Utils } from "../utils"

export class GM80 {
	public static check(exe: SmartBuffer): boolean {
		if(exe.length < 0x144AC4)
			return false;
		exe.readOffset = 0x000A49BE;
		if(exe.readBuffer(8).compare(Buffer.from([0x8B, 0x45, 0xF4, 0xE8, 0x2A, 0xBD, 0xFD, 0xFF])) == 0){
			let gm80Magic: number;
			switch(exe.readUInt8()){
				case 0x3D:
					const magic: number = exe.readUInt32LE();
					if(exe.readBuffer(6).compare(Buffer.from([0x0F, 0x85, 0x18, 0x01, 0x00, 0x00])) == 0){
						gm80Magic = magic;
					}else{
						gm80Magic = null;
					}
					break;
				case 0x90:
					exe.readOffset += 4;
					gm80Magic = null;
					break;
				default:
					return false;
			}
			let gm80HeaderVer: number;
			exe.readOffset = 0x000A49E2;
			if(exe.readBuffer(7).compare(Buffer.from([0x8B, 0xC6, 0xE8, 0x07, 0xBD, 0xFD, 0xFF])) == 0){
				switch(exe.readUInt8()){
					case 0x3D:
						const magic: number = exe.readUInt32LE();
						if(exe.readBuffer(6).compare(Buffer.from([0x0F, 0x85, 0xF5, 0x00, 0x00, 0x00])) == 0){
							gm80HeaderVer = magic;
						}else{
							gm80HeaderVer = null;
						}
						break;
					case 0x90:
						exe.readOffset += 4;
						gm80HeaderVer = null;
						break;
					default:
						return false;
				}
			}else{
				gm80HeaderVer = null;
			}
			exe.readOffset = 0x144AC0;
			const headerStart: number = exe.readUInt32LE();
			exe.readOffset = headerStart;
			if(gm80Magic === null){
				exe.readOffset += 4;
			}else{
				while(true){
					if(exe.readOffset+4 > exe.length)
						return false;
					const header1: number = exe.readUInt32LE();
					if(header1 == gm80Magic)
						break;
					else
						exe.readOffset += 10000-4;
				}
			}
			if(gm80HeaderVer === null){
				exe.readOffset += 4;
			}else{
				const header2: number = exe.readUInt32LE();
				if(header2 != gm80HeaderVer)
					return false;
			}
			exe.readOffset += 8;
			return true;
		}
		return false;
	}
	public static decrypt(exe: SmartBuffer): string {
		const reverseTable: Array<number> = new Array(256).fill(0);
		const garbageSize1: number = exe.readUInt32LE()*4;
		const garbageSize2: number = exe.readUInt32LE()*4;
		const uniqueKey: string = crypto.createHash("md5").update(exe.readBuffer(garbageSize1)).digest("hex");
		const swapTable: Array<number> = [...exe.readBuffer(256)];
		exe.readOffset += garbageSize2;
		for(let i: number = 0; i < 256; ++i)
			reverseTable[swapTable[i]] = i;
		const length: number = exe.readUInt32LE();
		const pos: number = exe.readOffset;
		for(let i: number = length+pos; i > pos; --i){
			exe.internalBuffer[i-1] = Utils.overflowingSub(
				reverseTable[exe.internalBuffer[i-1]],
				Utils.overflowingAdd(
					exe.internalBuffer[i-2],
					Utils.overflowingSub(
						i,
						pos+1,
					8)[0],
				8)[0],
			8)[0];
		}
		for(let i: number = pos+length-1; i >= pos; --i){
			const b: number = Math.max(i-swapTable[((i-pos) & 0xFF) >>> 0], pos);
			const a: number = exe.internalBuffer[i];
			exe.internalBuffer[i] = exe.internalBuffer[b];
			exe.internalBuffer[b] = a;
		}
		return uniqueKey;
	}
	public static encrypt(exe: SmartBuffer): void {
		const reverseTable: Array<number> = new Array(256).fill(0);
		const garbageSize1: number = exe.readUInt32LE()*4;
		const garbageSize2: number = exe.readUInt32LE()*4;
		exe.readOffset += garbageSize1;
		const swapTable: Array<number> = [...exe.readBuffer(256)];
		exe.readOffset += garbageSize2;
		for(let i: number = 0; i < 256; ++i)
			reverseTable[swapTable[i]] = i;
		let length: number = exe.readUInt32LE();
		const pos: number = exe.readOffset;
		length = exe.length-pos;
		exe.writeOffset = pos-4;
		exe.writeUInt32LE(length);
		for(let i: number = pos; i < pos+length; ++i){
			const b: number = Math.max(i-swapTable[((i-pos) & 0xFF) >>> 0], pos);
			const a: number = exe.internalBuffer[i];
			exe.internalBuffer[i] = exe.internalBuffer[b];
			exe.internalBuffer[b] = a;
		}
		for(let i: number = pos; i < pos+length; ++i){
			exe.internalBuffer[i] = swapTable[Utils.overflowingAdd(
				exe.internalBuffer[i],
				Utils.overflowingAdd(
					i-pos,
					exe.internalBuffer[i-1],
				8)[0],
			8)[0]];
		}
	}
}
