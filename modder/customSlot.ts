// Custom-variable progress sync — runtime configuration (v1.2.3-beta.4 §11 v2)
//
// At BUILD time the publisher may pre-fill default sync entries via the
// [mod] section of iwpo-settings.ini:
//
//   [mod]
//   sync0 = boss:8
//   sync1 = item:16
//   sync2 = secret:50
//
// We translate this into a default `[sync]` block that gets written next to
// the produced EXE/data into `__ONLINE_config.ini`. The player can later edit
// it via the in-game Sync tab. There is NO build-time GML codegen any more; the
// pack/send loop lives in saveGame.gml and is fully driven by the runtime
// `[sync]` section.

const NAME_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
export const MAX_PER_ENTRY_COUNT = 512;       // = 16 uint32 slots
export const MAX_TOTAL_SLOTS     = 128;       // sum of ceil(count/32) across all entries
export const MAX_ENTRIES         = 16;
export const MAX_NAME_LEN        = 32;

export interface CustomSlotEntry {
	name: string;
	count: number;
}

export interface CustomSlotConfig {
	entries: CustomSlotEntry[];
}

/**
 * Parse the [mod] section of iwpo-settings.ini. Returns null if no entries.
 * Throws on malformed input.
 *
 * Syntax per key: `syncN = <name>:<count>`
 *   name  : matches /^[a-zA-Z_][a-zA-Z0-9_]*$/, length 1..32
 *   count : integer, 1..512
 */
export function parseCustomSlotConfig(modSection: Record<string, string> | undefined): CustomSlotConfig | null {
	if(!modSection) return null;
	const entries: CustomSlotEntry[] = [];
	const keys = Object.keys(modSection).filter(k => /^sync\d+$/i.test(k))
		.sort((a, b) => parseInt(a.slice(4)) - parseInt(b.slice(4)));
	for(const k of keys){
		const raw = modSection[k].trim();
		const m = raw.match(/^([a-zA-Z_][a-zA-Z0-9_]*)\s*:\s*(\d+)\s*$/);
		if(!m) throw new Error(`[mod].${k} malformed: "${raw}" (expected name:count)`);
		const name = m[1];
		const count = parseInt(m[2]);
		if(!NAME_RE.test(name)) throw new Error(`[mod].${k}: invalid array name "${name}"`);
		if(name.length > MAX_NAME_LEN) throw new Error(`[mod].${k}: name "${name}" exceeds ${MAX_NAME_LEN} chars`);
		if(count < 1 || count > MAX_PER_ENTRY_COUNT) throw new Error(`[mod].${k}: count ${count} out of range 1..${MAX_PER_ENTRY_COUNT}`);
		entries.push({ name, count });
	}
	if(entries.length === 0) return null;
	if(entries.length > MAX_ENTRIES) throw new Error(`[mod] too many sync entries: ${entries.length} > ${MAX_ENTRIES}`);
	const totalSlots = entries.reduce((s, e) => s + Math.ceil(e.count / 32), 0);
	if(totalSlots > MAX_TOTAL_SLOTS) throw new Error(`[mod] total uint32 slot count ${totalSlots} exceeds max ${MAX_TOTAL_SLOTS}`);
	return { entries };
}

/**
 * Render the cfg as the textual `[sync]` section to drop into `__ONLINE_config.ini`.
 * Always includes `sync_enabled = 1`.
 */
export function formatSyncIniSection(cfg: CustomSlotConfig): string {
	const lines: string[] = [];
	lines.push("[sync]");
	lines.push(`entryCount = ${cfg.entries.length}`);
	lines.push("sync_enabled = 1");
	for(let i = 0; i < cfg.entries.length; i++){
		lines.push(`sync${i}_name = ${cfg.entries[i].name}`);
		lines.push(`sync${i}_count = ${cfg.entries[i].count}`);
	}
	return lines.join("\r\n");
}

/**
 * Merge the `[sync]` section into existing INI text (or produce a new `__ONLINE_config.ini` body).
 * If the existing body already has a `[sync]` section it is REPLACED.
 * Other sections are preserved verbatim.
 */
export function mergeSyncIntoIni(existingIni: string, cfg: CustomSlotConfig): string {
	const syncBlock = formatSyncIniSection(cfg);
	if(!existingIni || existingIni.trim().length === 0) return syncBlock + "\r\n";
	// Split sections by `[name]` headings while preserving them.
	const lines = existingIni.split(/\r?\n/);
	const out: string[] = [];
	let inSync = false;
	let replaced = false;
	for(const line of lines){
		const m = line.match(/^\s*\[([^\]]+)\]\s*$/);
		if(m){
			if(m[1].toLowerCase() === "sync"){
				inSync = true;
				if(!replaced){
					out.push(syncBlock);
					replaced = true;
				}
				continue;
			}
			inSync = false;
			out.push(line);
			continue;
		}
		if(inSync) continue;
		out.push(line);
	}
	if(!replaced){
		// Append at end, separated by a blank line if needed.
		if(out.length > 0 && out[out.length - 1].trim() !== "") out.push("");
		out.push(syncBlock);
	}
	return out.join("\r\n");
}

export const CustomSlot = {
	parseCustomSlotConfig,
	formatSyncIniSection,
	mergeSyncIntoIni,
	MAX_PER_ENTRY_COUNT,
	MAX_TOTAL_SLOTS,
	MAX_ENTRIES,
	MAX_NAME_LEN,
};
