import { SmartBuffer } from "smart-buffer"
import { Utils } from "../utils"

export enum XorMethod {
	Normal,
	Sudalv,
}

export class GM81 {
	public static check(exe: SmartBuffer): boolean {
		if(exe.length < 0x226D8A)
			return false;
		exe.readOffset = 0x00226CF3;
		if(exe.readBuffer(8).compare(Buffer.from([0xE8, 0x80, 0xF2, 0xDD, 0xFF, 0xC7, 0x45, 0xF0])) == 0){
			const headerStart: number = exe.readUInt32LE();
			exe.readOffset += 125;
			let gm81Magic: number = null;
			if(exe.readBuffer(3).compare(Buffer.from([0x81, 0x7D, 0xEC])) == 0){
				const magic: number = exe.readUInt32LE();
				if(exe.readUInt8() == 0x74)
					gm81Magic = magic;
			}
			exe.readOffset = 0x0010BB83;
			let xorMethod: XorMethod;
			if(exe.readBuffer(8).compare(Buffer.from([0x8B, 0x02, 0xC1, 0xE0, 0x10, 0x8B, 0x11, 0x81])) == 0)
				xorMethod = XorMethod.Sudalv;
			else
				xorMethod = XorMethod.Normal;
			exe.readOffset = headerStart;
			if(gm81Magic !== null){
				if(GM81.seekValue(exe, gm81Magic) === null)
					return false;
			}else{
				exe.readOffset += 8;
			}
			GM81.decrypt(exe, xorMethod);
			exe.readOffset += 20;
			return true;
		}
		return false;
	}
	public static checkLazy(exe: SmartBuffer): boolean {
		exe.readOffset = 3800004;
		if(GM81.seekValue(exe, 0xF7140067) !== null){
			GM81.decrypt(exe, XorMethod.Normal);
			exe.readOffset += 20;
			return true;
		}
		return false;
	}
	public static seekValue(exe: SmartBuffer, value: number): number {
		let pos: number = exe.readOffset;
		while(true){
			exe.readOffset = pos;
			const d1: number = exe.readUInt32LE();
			const d2: number = exe.readUInt32LE();
			const parsedValue: number = ((d1 & 0xFF00FF00) | (d2 & 0x00FF00FF)) >>> 0;
			const parsedXor: number = ((d1 & 0x00FF00FF) | (d2 & 0xFF00FF00)) >>> 0;
			if(parsedValue == value)
				return parsedXor;
			pos++;
			if(pos + 8 >= exe.length)
				return null;
		}
	}
	public static decrypt(exe: SmartBuffer, xorMethod: XorMethod): void {
		const crc32 = function(hashKey: Array<number>, crcTable: Array<number>): number {
			let result: number = 0xFFFFFFFF;
			for(const c of hashKey)
				result = ((result >>> 8) ^ crcTable[((result & 0xFF) ^ c) >>> 0]) >>> 0;
			return result;
		}
		const crc32Reflect = function(value: number, c: number): number {
			let rValue: number = 0;
			for(let i = 1; i <= c; ++i){
				if(((value & 1) >>> 0) != 0)
					rValue = (rValue | (1 << (c-i))) >>> 0;
				value = value >>> 1;
			}
			return rValue;
		}
		const sudalvMagicPoint: number = exe.readOffset-12;
		const hashKey: string = `_MJD${exe.readUInt32LE()}#RWK`;
		const hashKeyUTF16: Array<number> = [...Buffer.from(hashKey)];
		for(let i = hashKeyUTF16.length; i > 0; --i)
			hashKeyUTF16.splice(i, 0, 0);
		let crcTable: Array<number> = new Array(256).fill(0);
		const crcPolynomial: number = 0x04C11DB7;
		for(let i: number = 0; i < 256; ++i){
			crcTable[i] = (crc32Reflect(i, 8) << 24) >>> 0;
			for(let j: number = 0; j < 8; ++j){
				let xorMask: number = 0;
				if((crcTable[i] & (1 << 31)) >>> 0 != 0)
					xorMask = crcPolynomial;
				crcTable[i] = ((crcTable[i] << 1) ^ xorMask) >>> 0;
			}
			crcTable[i] = crc32Reflect(crcTable[i], 32);
		}
		const seed1: number = exe.readUInt32LE();
		const seed2: number = crc32(hashKeyUTF16, crcTable);
		const encryptionStart: number = exe.readOffset+((seed2 & 0xFF) >>> 0)+10;
		const offsetBackup: number = exe.readOffset;
		let generator: MaskGenerator;
		if(xorMethod == XorMethod.Normal){
			generator = new MaskGenerator(seed1, seed2);
		}else{
			const maskData: Array<number> = [...exe.internalBuffer.slice(0, sudalvMagicPoint+4)];
			const rChunksMaskData: Array<[number, number]> = [];
			for(let i: number = maskData.length-2; i >= 0; i -= 2)
				rChunksMaskData.push([maskData[i], maskData[i+1]]);
			const maskCountArray: Array<[[number, number], [number, number]]> = [];
			for(let i: number = 1; i < rChunksMaskData.length; ++i)
				maskCountArray.push([rChunksMaskData[i], rChunksMaskData[i-1]]);
			let maskCount: number = null;
			for(let i: number = 0; i < maskCountArray.length; ++i){
				const a: number = maskCountArray[i][0][0];
				const b: number = maskCountArray[i][0][1];
				const c: number = maskCountArray[i][1][0];
				const d: number = maskCountArray[i][1][1];
				if(a == 0 && b == 0 && c == 0 && d == 0){
					maskCount = i;
					break;
				}
			}
			if(maskCount === null)
				throw new Error("Unable to find the maskCount");
			const iter: Array<number> = [];
			const tmpBuffer: SmartBuffer = new SmartBuffer();
			for(let i: number = 1; i < maskCount+2; ++i){
				const x: [number, number] = rChunksMaskData[i];
				tmpBuffer.writeOffset = 0;
				tmpBuffer.writeUInt8(x[0]);
				tmpBuffer.writeUInt8(x[1]);
				tmpBuffer.readOffset = 0;
				iter.push(tmpBuffer.readUInt16LE());
				tmpBuffer.clear();
			}
			tmpBuffer.destroy();
			generator = new MaskGenerator(seed1, seed2, iter);
		}
		for(let loopOffset: number = encryptionStart; loopOffset <= exe.length-4; loopOffset += 4){
			exe.readOffset = loopOffset;
			exe.writeOffset = loopOffset;
			let chunk: number = exe.readUInt32LE();
			chunk = (chunk ^ generator.next()) >>> 0;
			exe.writeUInt32LE(chunk);
		}
		exe.readOffset = offsetBackup;
	}
}

class MaskGenerator {
	private seed1: number;
	private seed2: number;
	private iter: Array<number>;
	private index: number;
	constructor(seed1: number, seed2: number, iter: Array<number> = null){
		this.seed1 = seed1;
		this.seed2 = seed2;
		this.iter = iter;
		this.index = 0;
	}
	public next(): number {
		let n1: number = 0x9069;
		let n2: number = 0x4650;
		if(this.iter !== null){
			n1 = this.iterNext();
			n2 = this.iterNext();
		}
		this.seed1 = ((0xFFFF & this.seed1) >>> 0)*n1+(this.seed1 >>> 16);
		this.seed2 = ((0xFFFF & this.seed2) >>> 0)*n2+(this.seed2 >>> 16);
		const result: number = ((this.seed1 << 16) >>> 0)+((this.seed2 & 0xFFFF) >>> 0);
		return result;
	}
	public iterNext(): number {
		const result: number = this.iter[this.index++];
		if(this.index >= this.iter.length)
			this.index = 0;
		return result;
	}
}
