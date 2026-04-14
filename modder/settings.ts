import zlib from "zlib"
import { SmartBuffer } from "smart-buffer"
import { GameConfig, GameVersion } from "./gamedata"

export class Settings {
	public fullscreen: boolean;
	public interpolatePixels: boolean;
	public dontDrawBorder: boolean;
	public displayCursor: boolean;
	public scaling: number;
	public allowResize: boolean;
	public windowOnTop: boolean;
	public clearColour: number;
	public setResolution: boolean;
	public colourDepth: number;
	public resolution: number;
	public frequency: number;
	public dontShowButtons: boolean;
	public vSync: boolean;
	public forceCpuRender: boolean;
	public disableScreensaver: boolean;
	public escCloseGame: boolean;
	public treatCloseAsEsc: boolean;
	public f1HelpMenu: boolean;
	public f4FullscreenToggle: boolean;
	public f5SaveF6Load: boolean;
	public f9Screenshot: boolean;
	public priority: number;
	public freezeOnLoseFocus: boolean;
	public loadingBar: number;
	public backData: Buffer | null;
	public frontData: Buffer | null;
	public customLoadImage: Buffer | null;
	public transparent: boolean;
	public translucency: number;
	public scaleProgressBar: boolean;
	public showErrorMessage: boolean;
	public logErrors: boolean;
	public alwaysAbort: boolean;
	public zeroUninitializedVars: boolean;
	public errorOnUninitializedArgs: boolean;
	public webgl: number | null;
	public swapCreationEvents: boolean | null;
	private version: GameVersion;
	private start: number;
	private length: number;
	public static load(exe: SmartBuffer, gameConfig: GameConfig, start: number, length: number): Settings {
		const readDataMaybe = function(data: SmartBuffer): Buffer | null {
			if(data.readUInt32LE() != 0){
				const length2: number = data.readUInt32LE();
				const start2: number = data.readOffset;
				const result: Buffer = zlib.inflateSync(data.internalBuffer.subarray(start2, start2+length2));
				data.readOffset += length2;
				return result;
			}
			return null;
		}
		const data: SmartBuffer = SmartBuffer.fromBuffer(zlib.inflateSync(exe.internalBuffer.subarray(start, start+length)));
		const settings: Settings = new Settings();
		settings.version = gameConfig.version;
		settings.start = start;
		settings.length = length;
		settings.fullscreen = data.readUInt32LE() != 0;
		settings.interpolatePixels = data.readUInt32LE() != 0;
		settings.dontDrawBorder = data.readUInt32LE() != 0;
		settings.displayCursor = data.readUInt32LE() != 0;
		settings.scaling = data.readInt32LE();
		settings.allowResize = data.readUInt32LE() != 0;
		settings.windowOnTop = data.readUInt32LE() != 0;
		settings.clearColour = data.readUInt32LE();
		settings.setResolution = data.readUInt32LE() != 0;
		settings.colourDepth = data.readUInt32LE();
		settings.resolution = data.readUInt32LE();
		settings.frequency = data.readUInt32LE();
		settings.dontShowButtons = data.readUInt32LE() != 0;
		const vSyncField: number = data.readUInt32LE();
		switch(settings.version){
			case GameVersion.GameMaker80:
				settings.vSync = vSyncField != 0;
				settings.forceCpuRender = true;
				break;
			case GameVersion.GameMaker81:
				settings.vSync = (vSyncField & 1) != 0;
				settings.forceCpuRender = (vSyncField & (1 << 7)) != 0;
				break;
		}
		settings.disableScreensaver = data.readUInt32LE() != 0;
		settings.f4FullscreenToggle = data.readUInt32LE() != 0;
		settings.f1HelpMenu = data.readUInt32LE() != 0;
		settings.escCloseGame = data.readUInt32LE() != 0;
		settings.f5SaveF6Load = data.readUInt32LE() != 0;
		settings.f9Screenshot = data.readUInt32LE() != 0;
		settings.treatCloseAsEsc = data.readUInt32LE() != 0;
		settings.priority = data.readUInt32LE();
		settings.freezeOnLoseFocus = data.readUInt32LE() != 0;
		settings.loadingBar = data.readUInt32LE();
		if(settings.loadingBar != 0){
			settings.backData = readDataMaybe(data);
			settings.frontData = readDataMaybe(data);
		}else{
			settings.backData = null;
			settings.frontData = null;
		}
		settings.customLoadImage = readDataMaybe(data);
		settings.transparent = data.readUInt32LE() != 0;
		settings.translucency = data.readUInt32LE();
		settings.scaleProgressBar = data.readUInt32LE() != 0;
		settings.showErrorMessage = data.readUInt32LE() != 0;
		settings.logErrors = data.readUInt32LE() != 0;
		settings.alwaysAbort = data.readUInt32LE() != 0;
		const x: number = data.readUInt32LE();
		switch(settings.version){
			case GameVersion.GameMaker80:
				settings.zeroUninitializedVars = x != 0;
				settings.errorOnUninitializedArgs = true;
				break;
			case GameVersion.GameMaker81:
				settings.zeroUninitializedVars = (x & 1) >>> 0 != 0;
				settings.errorOnUninitializedArgs = (x & 2) >>> 0 != 0;
				break;
		}
		if (data.remaining() != 0) {
			settings.webgl = data.readUInt32LE();
			settings.swapCreationEvents = data.readUInt32LE() != 0;
		} else {
			settings.webgl = null;
			settings.swapCreationEvents = null;
		}
		exe.readOffset = settings.start+settings.length;
		exe.writeOffset = exe.readOffset;
		return settings;
	}
	public save(exe: SmartBuffer): SmartBuffer {
		const writeDataMaybe = function(data: SmartBuffer, value: Buffer | null): void {
			if (value !== null) {
				data.writeUInt32LE(1);
				const compressed: Buffer = zlib.deflateSync(value);
				data.writeUInt32LE(compressed.length);
				data.writeBuffer(compressed);
			} else {
				data.writeUInt32LE(0);
			}
		}
		const data: SmartBuffer = new SmartBuffer();
		data.writeUInt32LE(Number(this.fullscreen));
		data.writeUInt32LE(Number(this.interpolatePixels));
		data.writeUInt32LE(Number(this.dontDrawBorder));
		data.writeUInt32LE(Number(this.displayCursor));
		data.writeInt32LE(this.scaling);
		data.writeUInt32LE(Number(this.allowResize));
		data.writeUInt32LE(Number(this.windowOnTop));
		data.writeUInt32LE(this.clearColour);
		data.writeUInt32LE(Number(this.setResolution));
		data.writeUInt32LE(this.colourDepth);
		data.writeUInt32LE(this.resolution);
		data.writeUInt32LE(this.frequency);
		data.writeUInt32LE(Number(this.dontShowButtons));
		switch(this.version){
			case GameVersion.GameMaker80:
				data.writeUInt32LE(Number(this.vSync));
				break;
			case GameVersion.GameMaker81:
				data.writeUInt32LE(Number(this.vSync) | (Number(this.forceCpuRender) << 7));
				break;
		}
		data.writeUInt32LE(Number(this.disableScreensaver));
		data.writeUInt32LE(Number(this.f4FullscreenToggle));
		data.writeUInt32LE(Number(this.f1HelpMenu));
		data.writeUInt32LE(Number(this.escCloseGame));
		data.writeUInt32LE(Number(this.f5SaveF6Load));
		data.writeUInt32LE(Number(this.f9Screenshot));
		data.writeUInt32LE(Number(this.treatCloseAsEsc));
		data.writeUInt32LE(this.priority);
		data.writeUInt32LE(Number(this.freezeOnLoseFocus));
		data.writeUInt32LE(this.loadingBar);
		if(this.loadingBar != 0){
			writeDataMaybe(data, this.backData);
			writeDataMaybe(data, this.frontData);
		}
		writeDataMaybe(data, this.customLoadImage);
		data.writeUInt32LE(Number(this.transparent));
		data.writeUInt32LE(this.translucency);
		data.writeUInt32LE(Number(this.scaleProgressBar));
		data.writeUInt32LE(Number(this.showErrorMessage));
		data.writeUInt32LE(Number(this.logErrors));
		data.writeUInt32LE(Number(this.alwaysAbort));
		switch(this.version){
			case GameVersion.GameMaker80:
				data.writeUInt32LE(Number(this.zeroUninitializedVars));
				break;
			case GameVersion.GameMaker81:
				data.writeUInt32LE(Number(this.zeroUninitializedVars)+2*Number(this.errorOnUninitializedArgs));
				break;
		}
		if (this.webgl !== null && this.swapCreationEvents !== null) {
			data.writeUInt32LE(this.webgl);
			data.writeUInt32LE(Number(this.swapCreationEvents));
		}
		const compressedData: Buffer = zlib.deflateSync(data.internalBuffer.subarray(0, data.length));
		const currentExe: Buffer = exe.internalBuffer.subarray(0, exe.length);
		const nextExe: SmartBuffer = SmartBuffer.fromBuffer(Buffer.concat([
			currentExe.subarray(0, this.start),
			compressedData,
			currentExe.subarray(this.start+this.length),
		]));
		data.destroy();
		exe.destroy();
		nextExe.writeOffset = this.start-4;
		nextExe.writeUInt32LE(compressedData.length);
		nextExe.readOffset = compressedData.length;
		nextExe.writeOffset = nextExe.readOffset;
		return nextExe;
	}
}
