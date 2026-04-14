import fs from "fs-extra"
import path from "path"
import { SmartBuffer } from "smart-buffer"
import { Utils } from "./utils"
// import Jimp from "jimp"

export interface PESection {
	virtualSize: number;
	virtualAddress: number;
	diskSize: number;
	diskAddress: number;
}

export interface WindowsIcon {
	width: number,
	height: number,
	originalBPP: number;
	bgraData: Array<number>;
}

export class Icon {
	public static async save(iconData: Array<WindowsIcon>, dir: string): Promise<void> {
		await fs.remove(dir);
		await fs.mkdir(dir);
		for(const icon of iconData){
			if(icon.bgraData.length == 0)
				continue;
			const output: string = path.join(dir, `icon_${icon.width}x${icon.height}.png`);
			if(await fs.exists(output))
				continue;
			// const image = new Jimp({
			// 	data: Buffer.from(icon.bgraData),
			// 	width: icon.width,
			// 	height: icon.height,
			// });
			// await image.flip(false, true);
			// await image.write(output);
		}
	}
	private static writeArray(buff: SmartBuffer, arr: Array<number>): void {
		for(let i: number = 0; i < arr.length; ++i)
			buff.writeUInt8(arr[i]);
	}
	public static find(exe: SmartBuffer, sections: Array<PESection>): [Array<WindowsIcon>, Array<number>] {
		const rsrcBase: number = exe.readOffset;
		exe.readOffset += 12;
		const nameCount: number = exe.readUInt16LE();
		const idCount: number = exe.readUInt16LE();
		exe.readOffset += nameCount*8;
		let icons: Array<[number, number, number]> = [];
		for(let i: number = 0; i < idCount; ++i){
			const id: number = exe.readUInt32LE();
			const offset: number = exe.readUInt32LE() & 0x7FFFFFFF;
			if(id == 3){
				const topLevelPos: number = exe.readOffset;
				exe.readOffset = offset+rsrcBase+14;
				const leafCount: number = exe.readUInt16LE();
				if(leafCount == 0)
					return [[], []];
				for(let j: number = 0; j < leafCount; ++j){
					const leafPos: number = exe.readOffset;
					const iconID: number = exe.readUInt32LE();
					const languageOffset: number = exe.readUInt32LE() & 0x7FFFFFFF;
					exe.readOffset = languageOffset+rsrcBase+20;
					const leaf: number = exe.readUInt32LE();
					exe.readOffset = leaf+rsrcBase;
					const rva: number = exe.readUInt32LE();
					const size: number = exe.readUInt32LE();
					icons.push([iconID, rva, size]);
					exe.readOffset = leafPos+8;
				}
				exe.readOffset = topLevelPos;
			}else if(id == 14){
				exe.readOffset = offset+rsrcBase+12;
				const leafCount: number = exe.readUInt16LE()+exe.readUInt16LE();
				if(leafCount == 0)
					return [[], []];
				exe.readOffset += 4;
				const languageOffset: number = exe.readUInt32LE() & 0x7FFFFFFF;
				exe.readOffset = languageOffset+rsrcBase+20;
				const leaf: number = exe.readUInt32LE();
				exe.readOffset = leaf+rsrcBase;
				const rva: number = exe.readUInt32LE();
				const size: number = exe.readUInt32LE();
				const v: Array<number> = Icon.extractVirtualBytes(exe, sections, rva, size);
				if(v !== null){
					const icoHeader: SmartBuffer = SmartBuffer.fromBuffer(Buffer.from(v));
					icoHeader.readOffset += 4;
					const imageCount: number = icoHeader.readUInt16LE();
					const iconGroup: Array<WindowsIcon> = [];
					const rawHeaderSize: number = 6+imageCount*16;
					const rawBodySize: number = icons.map(t => t[2]).reduce((a: number, b: number) => a+b, 0);
					const rawFile: SmartBuffer = SmartBuffer.fromSize(rawHeaderSize+rawBodySize); 
					const rawFileBody: SmartBuffer = SmartBuffer.fromSize(rawBodySize);
					Icon.writeArray(rawFile, v.slice(0, 6));
					for(let j: number = 0; j < imageCount; ++j){
						const pos: number = icoHeader.readOffset;
						Icon.writeArray(rawFile, v.slice(pos, pos+12));
						rawFile.writeUInt32LE(rawHeaderSize+rawFileBody.length);
						const width: number = icoHeader.readUInt8();
						const height: number = icoHeader.readUInt8();
						icoHeader.readOffset += 4;
						icoHeader.readUInt16LE();
						icoHeader.readOffset += 4;
						const ordinal: number = icoHeader.readUInt16LE();
						for(const icon of icons){
							if(icon[0] == ordinal && icon[2] >= 40){
								const v2: Array<number> = Icon.extractVirtualBytes(exe, sections, icon[1], icon[2]);
								if(v2 !== null){
									Icon.writeArray(rawFileBody, v2);
									const i: WindowsIcon = Icon.make(width, height, v2);
									if(i !== null){
										for(let k = 0; k < i.bgraData.length; k += 4){
											const a: number = i.bgraData[k];
											i.bgraData[k] = i.bgraData[k+2];
											i.bgraData[k+2] = a;
										}
										iconGroup.push(i);
									}
								}
								break;
							}
						}
					}
					rawFile.writeBuffer(rawFileBody.toBuffer());
					const res: [Array<WindowsIcon>, Array<number>] = [iconGroup, [...rawFile.toBuffer()]]
					icoHeader.destroy();
					rawFile.destroy();
					rawFileBody.destroy();
					return res;
				}
			}
		}
		return [[], []];
	}
	private static make(width: number, height: number, blob: Array<number>): WindowsIcon {
		const data: SmartBuffer = SmartBuffer.fromBuffer(Buffer.from(blob));
		const dataStart = data.readUInt32LE();
		data.readOffset = 14;
		const bpp: number = data.readUInt16LE();
		data.readOffset = dataStart;
		const icoWH: (n: number) => number = n => n == 0 ? 256 : n;
		switch(bpp){
			case 32:
				const d: Buffer = data.toBuffer().subarray(dataStart, dataStart+width*height*4);
				data.destroy();
				if(d !== null)
					return {
						width: icoWH(width),
						height: icoWH(height),
						originalBPP: bpp,
						bgraData: [...d],
					}
				else
					return null;
			case 8:
				const pixelCount: number = width*height;
				const bgraData: SmartBuffer = SmartBuffer.fromSize(pixelCount*4);
				data.readOffset += 1024;
				for(let i: number = 0; i < pixelCount; ++i){
					const lutPos = dataStart+data.readUInt8()*4;
					Icon.writeArray(bgraData, blob.slice(lutPos, lutPos+4));
				}
				let cursor: number = 0;
				while(cursor+4*8 <= bgraData.length){
					let bitmask: number = data.readUInt8();
					for(let i: number = 0; i < 8; ++i){
						const [m, b] = Utils.overflowingAdd(bitmask, bitmask, 8);
						bitmask = m;
						bgraData.internalBuffer[cursor+3] = b ? 0x0 : 0xFF;
						cursor += 4;
					}
				}
				if(cursor < bgraData.length){
					let bitmask: number = data.readUInt8();
					while(cursor < bgraData.length){
						const [m, b] = Utils.overflowingAdd(bitmask, bitmask, 8);
						bitmask = m;
						bgraData.internalBuffer[cursor+3] = b ? 0x0 : 0xFF;
						cursor += 4;
					}
				}
				const res: WindowsIcon = {
					width: icoWH(width),
					height: icoWH(height),
					originalBPP: bpp,
					bgraData: [...bgraData.toBuffer()],
				}
				data.destroy();
				bgraData.destroy();
				return res;
		}
		data.destroy();
		return null;
	}
	private static extractVirtualBytes(exe: SmartBuffer, sections: Array<PESection>, rva: number, size: number): Array<number> {
		for(const section of sections){
			if(rva >= section.virtualAddress && rva+size < section.virtualAddress+section.virtualSize){
				const offsetOnDisk: number = rva-section.virtualAddress;
				const dataLocation: number = section.diskAddress+offsetOnDisk;
				const readOffsetBackup: number = exe.readOffset;
				exe.readOffset = dataLocation;
				const arr: Buffer = exe.readBuffer(size);
				exe.readOffset = readOffsetBackup;
				return [...arr];
			}
		}
		return null;
	}
}
