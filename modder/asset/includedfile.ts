import { SmartBuffer } from "smart-buffer"
import { Asset } from "../asset"
import { GameConfig} from "../gamedata"

const VERSION = 800;

enum ExportSetting {
    NoExport,
    TempFolder,
    GameFolder,
    CustomFolder,
}

export class IncludedFile extends Asset {
	public fileName: Buffer;
	public sourcePath: Buffer;
	public dataExists: boolean;
	public sourceLength: number;
	public storedInGmk: boolean;
	public embeddedData: Buffer | null;
	public exportSettings: ExportSetting;
	public customFolder: Buffer | null;
	public overwriteFile: boolean;
	public freeMemory: boolean;
	public removeAtEnd: boolean;
	public static deserialize(data: SmartBuffer, gameConfig: GameConfig): IncludedFile {
		let version = data.readUInt32LE();
		if (version != 800)
			throw new Error("Incorrect version for included files");
		let includedfile = new IncludedFile();
		includedfile.fileName = data.readBuffer(data.readUInt32LE());
		includedfile.sourcePath = data.readBuffer(data.readUInt32LE());
		includedfile.dataExists = data.readUInt32LE() != 0;
		includedfile.sourceLength = data.readUInt32LE();
		includedfile.storedInGmk = data.readUInt32LE() != 0;
		includedfile.embeddedData = (includedfile.dataExists && includedfile.storedInGmk) ? data.readBuffer(data.readUInt32LE()) : null;
		switch(data.readUInt32LE()){
			case 0:
				includedfile.exportSettings = ExportSetting.NoExport
				break;
			case 1:
				includedfile.exportSettings = ExportSetting.TempFolder
				break;
			case 2:
				includedfile.exportSettings = ExportSetting.GameFolder
				break;
			default:
				includedfile.exportSettings = ExportSetting.CustomFolder
				break;
		}
		includedfile.customFolder = data.readBuffer(data.readUInt32LE());
		includedfile.overwriteFile = data.readUInt32LE() != 0;
		includedfile.freeMemory = data.readUInt32LE() != 0;
		includedfile.removeAtEnd = data.readUInt32LE() != 0;
		return includedfile;
	}

	public serialize(data: SmartBuffer): void {
		data.writeUInt32LE(VERSION);
		data.writeUInt32LE(this.fileName.length);
		data.writeBuffer(this.fileName);
		data.writeUInt32LE(this.sourcePath.length);
		data.writeBuffer(this.sourcePath);
		data.writeUInt32LE(Number(this.dataExists));
		data.writeUInt32LE(this.sourceLength);
		data.writeUInt32LE(Number(this.storedInGmk));
		if(this.embeddedData !== null){
			data.writeUInt32LE(this.embeddedData.length);
			data.writeBuffer(this.embeddedData);
		}
		data.writeUInt32LE(Number(this.exportSettings));
		data.writeUInt32LE(this.customFolder.length);
		data.writeBuffer(this.customFolder);
		data.writeUInt32LE(Number(this.overwriteFile));
		data.writeUInt32LE(Number(this.freeMemory));
		data.writeUInt32LE(Number(this.removeAtEnd));
	}
}