import { SmartBuffer } from "smart-buffer"
import { Utils } from "../utils"

export interface AntidecMetadata {
	exeLoadOffset: number;
	headerStart: number;
	xorMask: number;
	addMask: number;
	subMask: number;
}

export class Antidec {
	public static check80(exe: SmartBuffer): AntidecMetadata {
		if(exe.length < 0x144AC4)
			return null;
		exe.readOffset = 0x00032337;
		if(exe.readBuffer(8).compare(Buffer.from([0xE2, 0xF7, 0xC7, 0x05, 0x2E, 0x2F, 0x43, 0x00])) == 0){
			exe.readOffset -= 9;
			const byteXorMask: number = exe.readUInt8();
			const dwordXorMask: number = Utils.bytesToU32([byteXorMask, byteXorMask, byteXorMask, byteXorMask]);
			exe.readOffset = 0x000322A9;
			const exeLoadOffset: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x00144AC0;
			const headerStart: number = exe.readUInt32LE();
			exe.readOffset = 0x000322D3;
			const xorMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x000322D8;
			const addMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x000322E4;
			const subMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			return {
				exeLoadOffset: exeLoadOffset,
				headerStart: headerStart,
				xorMask: xorMask,
				addMask: addMask,
				subMask: subMask,
			}
		}
		return null;
	}
	public static check81(exe: SmartBuffer): AntidecMetadata {
		if(exe.length < 0x1F0C53)
			return null;
		exe.readOffset = 0x000462CC;
		const buffer: Buffer = exe.readBuffer(7);
		const byteXorMask: number = buffer[3];
		if(buffer.compare(Buffer.from([0x80, 0x34, 0x08, byteXorMask, 0xE2, 0xFA, 0xE9])) == 0){
			const dwordXorMask: number = Utils.bytesToU32([byteXorMask, byteXorMask, byteXorMask, byteXorMask]);
			exe.readOffset = 0x00046255;
			const exeLoadOffset: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x001F0C53;
			const headerStart: number = exe.readUInt32LE();
			exe.readOffset = 0x00046283;
			const xorMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x00046274;
			const addMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			exe.readOffset = 0x00046293;
			const subMask: number = (exe.readUInt32LE() ^ dwordXorMask) >>> 0;
			return {
				exeLoadOffset: exeLoadOffset,
				headerStart: headerStart,
				xorMask: xorMask,
				addMask: addMask,
				subMask: subMask,
			}
		}
		return null;
	}
	public static decrypt(exe: SmartBuffer, settings: AntidecMetadata): boolean {
		const offset: number = settings.exeLoadOffset+settings.headerStart;
		let xorMask: number = settings.xorMask;
		let addMask: number = settings.addMask;
		for(let loopOffset: number = exe.length-4; loopOffset >= offset-4; loopOffset -= 4){
			exe.readOffset = loopOffset;
			exe.writeOffset = loopOffset;
			let value: number = exe.readUInt32LE();
			value = Utils.swapBytes32(Utils.overflowingAdd((value ^ xorMask) >>> 0, addMask, 32)[0]);
			xorMask = Utils.overflowingSub(xorMask, settings.subMask, 32)[0];
			addMask = Utils.overflowingAdd(Utils.swapBytes32(addMask), 1, 32)[0];
			exe.writeUInt32LE(value);
		}
		exe.readOffset = offset;
		return true;
	}
	public static encrypt(exe: SmartBuffer, settings: AntidecMetadata): void {
		exe.writeOffset = exe.length;
		while(exe.length % 4 != 0)
			exe.writeInt8(0);
		const offset: number = settings.exeLoadOffset+settings.headerStart;
		let xorMask: number = settings.xorMask;
		let addMask: number = settings.addMask;
		for(let loopOffset: number = exe.length-4; loopOffset >= offset-4; loopOffset -= 4){
			exe.readOffset = loopOffset;
			exe.writeOffset = loopOffset;
			let value: number = exe.readUInt32LE();
			value = (Utils.overflowingSub(Utils.swapBytes32(value), addMask, 32)[0] ^ xorMask) >>> 0;
			xorMask = Utils.overflowingSub(xorMask, settings.subMask, 32)[0];
			addMask = Utils.overflowingAdd(Utils.swapBytes32(addMask), 1, 32)[0];
			exe.writeUInt32LE(value);
		}
		exe.readOffset = offset;
	}
}
