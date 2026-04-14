import { SmartBuffer } from "smart-buffer"
import { Unpack } from "./upx"
import { Antidec, AntidecMetadata } from "./gamedata/antidec"
import { GM81, XorMethod } from "./gamedata/gm81"
import { GM80 } from "./gamedata/gm80"

export enum GameVersion {
	GameMaker80,
	GameMaker81,
}

export interface GameConfig {
	version: GameVersion;
	antidecSettings: AntidecMetadata;
}

export class GameData {
	public static decrypt(exe: SmartBuffer, upxData: [number, number]): GameConfig {
		let unpacked: SmartBuffer = exe;
		const config: GameConfig = {
			version: GameVersion.GameMaker80,
			antidecSettings: null,
		};
		if(upxData !== null){
			const maxSize: number = upxData[0];
			const diskOffset: number = upxData[1];
			unpacked = SmartBuffer.fromBuffer(Unpack(exe, maxSize, diskOffset));
		}
		config.antidecSettings = Antidec.check80(unpacked);
		if(config.antidecSettings === null){
			Antidec.check81(unpacked);
			config.version = GameVersion.GameMaker81;
		}
		if(upxData !== null)
			unpacked.destroy();
		if(config.antidecSettings === null){
			config.version = GameVersion.GameMaker80;
			if(GM80.check(exe))
				return config;
			config.version = GameVersion.GameMaker81;
			if(GM81.check(exe))
				return config;
			if(GM81.checkLazy(exe))
				return config;
			throw new Error("Unknown format");
		}
		if(!Antidec.decrypt(exe, config.antidecSettings))
			throw new Error("Unknown format");
		if(config.version == GameVersion.GameMaker81){
			if(GM81.seekValue(exe, 0xF7140067) !== null){
				GM81.decrypt(exe, XorMethod.Normal);
				exe.readOffset += 4;
			}else{
				throw new Error("Unknown format");
			}
		}
		exe.readOffset += 16;
		return config;
	}
	// FIND THE POST-DECRYPTION INTEGRITY CHECK (JE) IN THE RUNNER
	// Pattern: CMP EAX,[EBP-8] / JE +5 / CALL xx / XOR EAX,EAX
	// Bytes:   3B 45 F8        / 74 05 / E8 xx xx xx xx / 33 C0
	// The JE byte is at pattern_offset + 3
	private static findIntegrityCheckJE(exe: SmartBuffer): number {
		const buf: Buffer = exe.internalBuffer;
		const limit: number = Math.min(exe.length - 12, 0x300000);
		for(let i: number = 0x100000; i < limit; ++i){
			if(buf[i] === 0x3B && buf[i+1] === 0x45 && buf[i+2] === 0xF8
				&& buf[i+3] === 0x74 && buf[i+4] === 0x05 && buf[i+5] === 0xE8
				&& buf[i+10] === 0x33 && buf[i+11] === 0xC0)
				return i + 3;
		}
		return -1;
	}
	public static encrypt(exe: SmartBuffer, config: GameConfig): void {
		if(config.antidecSettings === null){
			if(config.version == GameVersion.GameMaker81){
				if(!GM81.check(exe))
					GM81.checkLazy(exe);
				const jeOffset: number = GameData.findIntegrityCheckJE(exe);
				if(jeOffset >= 0){
					exe.readOffset = jeOffset;
					const curValue: number = exe.readUInt8();
					if(curValue == 0x74){
						exe.writeOffset = jeOffset;
						exe.writeUInt8(0xEB);
					}
				}
			}
		}else{
			if(config.version == GameVersion.GameMaker81){
				if(GM81.seekValue(exe, 0xF7140067) !== null)
					GM81.decrypt(exe, XorMethod.Normal);
			}
			Antidec.encrypt(exe, config.antidecSettings);
		}
	}
}
