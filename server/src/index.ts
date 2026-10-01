import { createServer, Socket } from "node:net";
import { createServer as createHttpServer } from "node:http";
import { createSocket, RemoteInfo } from "node:dgram";
import { SmartBuffer } from "smart-buffer";
import { Logger } from "tslog";
import {
    PORT_HTTP, PORT_TCP, PORT_UDP, MIN_CLIENT_VERSION, PROTOCOL_VERSION, MIN_PROTOCOL_VERSION,
    NOTE_CACHE_MAX_PER_GAME, NOTE_SYNC_MIN_MS, GAME_CACHE_EXPIRY_MS, SAVE_CACHE_MAX_AGE_MS,
    MAX_PLAYERS_PER_IP, HEARTBEAT_INTERVAL_SEC, HEARTBEAT_TIMEOUT_SEC,
    UDP_CLEANUP_INTERVAL_MIN, UDP_EXPIRY_MIN,
    MAX_TCP_MESSAGE, MAX_TCP_BUFFER, MAX_UDP_MESSAGE, MAX_CUSTOM_SLOTS, MAX_PER_ENTRY_SLOTS,
    MAX_SYNC_ENTRIES, MAX_SYNC_NAME_LEN, MAX_TEAMS,
    TCP_RATE_LIMIT, UDP_RATE_LIMIT,
    RATING_COOLDOWN_SEC, RATING_MAX_PER_GAME, RATING_DATA_DIR,
    SKIN_DATA_DIR, SKIN_MAX_FILES, SKIN_MAX_FILE_SIZE, SKIN_MAX_TOTAL_SIZE,
    SKIN_CHUNK, SKIN_DL_MAX_REQ_PER_MIN, SKIN_DL_MAX_BYTES_PER_MIN,
} from "./config.js";
import { TcpMsg, UdpMsg, varintByteLen, readVarint, frameMessage } from "./protocol.js";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";

const log = new Logger();

/* ── Types ─────────────────────────────────────────── */

interface UdpEndpoint {
    address: string;
    port: number;
    id: string | null;
    game: string | null;
    room: number | null;
    prevRoom: number | null;
    lastActivity: number;
    msgCount: number;
    msgWindowStart: number;
    killed: boolean;
}

interface TcpPlayer {
    readonly address: string;
    readonly id: string;
    readonly socket: Socket;
    name: string;
    game: string;
    gameName: string;
    hasPassword: boolean;
    msgCount: number;
    msgWindowStart: number;
    lastHeartbeat: number;
    customSlots: Uint32Array | null;
    /** True once we've replayed the team-shared sync snapshot to this player. */
    syncReplayed: boolean;
    protocolVersion: number;
    team: number;
    spectating: boolean;
    quitted: boolean;
    recvBuf: Buffer;
    /** Has the client sent its first CREATED message yet? Used to gate roster replay. */
    rosterSent: boolean;
    /** 16-byte skin hash + directory-name hint; null hash = no skin selected. */
    skinHash: Buffer | null;
    skinHint: string;
    /** Skin-download rate limiting window (SKIN_GET / SKIN_FILE_REQ). */
    skinDlWindowStart: number;
    skinDlReqs: number;
    skinDlBytes: number;
    skinDlLimited: boolean;
    /** Bullet-share rate limiting window (BULLET, high-frequency). */
    bulletWindowStart: number;
    bulletCount: number;
    /** Note relay rate limiting windows (NOTE), one bucket per subtype. */
    noteWindowStart: number[];
    noteCount: number[];
    /** NOTE_SYNC pull throttle timestamp. */
    noteSyncAt: number;
    /** Consecutive NOTE messages dropped by the per-subtype buckets. */
    noteDropStreak: number;
    /** Bitmask of teams whose cached last-save was already sent to this client. */
    saveCacheSentTeams: number;
}

/* ── State ─────────────────────────────────────────── */

const tcpPlayers: TcpPlayer[] = [];
const udpEndpoints: UdpEndpoint[] = [];
const udpByGame = new Map<string, Set<UdpEndpoint>>();

/* ── Sync (CUSTOM_DATA v2) shared state ────────────── */

interface SyncEntry {
    count: number;        // 1..512  (bit count)
    slotCount: number;    // ceil(count/32), 1..MAX_PER_ENTRY_SLOTS
    bits: Uint32Array;    // length === slotCount
}
// gameID → team → name → entry
const syncState: Map<string, Map<number, Map<string, SyncEntry>>> = new Map();
const SYNC_NAME_RE = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
const CUSTOM_DATA_V2_PROTOCOL_VERSION = 2;

function supportsCustomDataV2(player: TcpPlayer): boolean {
    return player.protocolVersion >= CUSTOM_DATA_V2_PROTOCOL_VERSION;
}

// Skin exchange (SKIN / SKIN_NOTIFY) is gated on protocol v3: older clients
// are never sent opcode 13 (they would kick themselves on the unknown opcode).
const SKIN_PROTOCOL_VERSION = 3;

function supportsSkins(player: TcpPlayer): boolean {
    return player.protocolVersion >= SKIN_PROTOCOL_VERSION;
}

// Notes/annotations (NOTE) are gated on protocol v5: older clients are never
// sent opcode 20 (unknown opcodes kick the receiver).
const NOTE_PROTOCOL_VERSION = 5;
// Per-subtype drop-not-kick limits per 10s window (BULLET pattern): one
// spammed category must not starve the others. STROKE is counted per chunk.
const NOTE_RATE_LIMITS = [20, 20, 100, 10, 20];

function supportsNotes(player: TcpPlayer): boolean {
    return player.protocolVersion >= NOTE_PROTOCOL_VERSION;
}

/* ── Skin library (hash-addressed read-only store) ─── */

interface SkinFileEntry { name: string; size: number; }

const skinManifestCache = new Map<string, SkinFileEntry[]>();
// Manifests mirror the client-side package hash scope: regular files directly
// inside the package dir (subdirectories are not part of the hash).
const SKIN_NAME_RE = /^[A-Za-z0-9_][A-Za-z0-9_.\-]{0,63}$/;

if (!existsSync(SKIN_DATA_DIR)) mkdirSync(SKIN_DATA_DIR, { recursive: true });

function skinManifest(hex: string): SkinFileEntry[] | null {
    const cached = skinManifestCache.get(hex);
    if (cached) return cached;
    let manifest: SkinFileEntry[] | null = null;
    if (/^[0-9a-f]{32}$/.test(hex)) {
        try {
            const dir = join(SKIN_DATA_DIR, hex);
            const entries: SkinFileEntry[] = [];
            let total = 0;
            for (const f of readdirSync(dir)) {
                if (!SKIN_NAME_RE.test(f) || f.includes("..")) continue;
                const st = statSync(join(dir, f));
                if (!st.isFile()) continue;
                entries.push({ name: f, size: st.size });
                total += st.size;
            }
            if (entries.length > 0 && entries.length <= SKIN_MAX_FILES && total <= SKIN_MAX_TOTAL_SIZE
                && entries.every(e => e.size <= SKIN_MAX_FILE_SIZE)) {
                entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
                manifest = entries;
            }
        } catch {}
    }
    // misses are not cached: a package approved later must become visible
    // without a restart (lookups are already rate-limited per player)
    if (manifest) skinManifestCache.set(hex, manifest);
    return manifest;
}

// Per-player download budget. Over-limit requests are dropped silently (the
// client times out and stays in its explicit-missing state) — a misbehaving
// or buggy client must not be able to amplify traffic through file chunks.
function skinDlAllow(player: TcpPlayer, bytes: number): boolean {
    const now = Date.now();
    if (now - player.skinDlWindowStart >= 60000) {
        player.skinDlWindowStart = now;
        player.skinDlReqs = 0;
        player.skinDlBytes = 0;
        player.skinDlLimited = false;
    }
    player.skinDlReqs += 1;
    player.skinDlBytes += bytes;
    if (player.skinDlReqs > SKIN_DL_MAX_REQ_PER_MIN || player.skinDlBytes > SKIN_DL_MAX_BYTES_PER_MIN) {
        if (!player.skinDlLimited) {
            player.skinDlLimited = true;
            log.info(`SKIN_DL rate limited ${player.id} (${JSON.stringify(player.name)})`);
        }
        return false;
    }
    return true;
}

function getTeamSync(game: string, team: number, create: boolean): Map<string, SyncEntry> | null {
    let g = syncState.get(game);
    if (!g) {
        if (!create) return null;
        g = new Map(); syncState.set(game, g);
    }
    let t = g.get(team);
    if (!t) {
        if (!create) return null;
        t = new Map(); g.set(team, t);
    }
    return t;
}

function encodeSyncSnapshot(ownerID: string, team: Map<string, SyncEntry>): SmartBuffer {
    const reply = new SmartBuffer();
    reply.writeUInt8(TcpMsg.CUSTOM_DATA);
    reply.writeUInt8(1);                     // v2flag
    reply.writeStringNT(ownerID);
    reply.writeUInt8(team.size);
    for (const [name, e] of team) {
        reply.writeStringNT(name);
        reply.writeUInt16LE(e.count);
        reply.writeUInt16LE(e.slotCount);
        for (let i = 0; i < e.slotCount; i++) reply.writeUInt32LE(e.bits[i]);
    }
    return reply;
}

function replaySyncTo(player: TcpPlayer): void {
    if (player.game === "" || !supportsCustomDataV2(player)) return;
    const team = getTeamSync(player.game, player.team, false);
    if (!team || team.size === 0) return;
    sendTo(player, encodeSyncSnapshot("", team));
}

function cleanupSyncForGameIfEmpty(game: string): void {
    if (game === "") return;
    for (const p of tcpPlayers) {
        if (p.game === game && !p.quitted) return;
    }
    syncState.delete(game);
}

/* ── Rating storage ────────────────────────────────── */

interface Rating {
    playerID: string;
    gameID: string;
    gameName: string;
    playerName: string;
    stars: number;        // 1-5
    cleared: number;      // 0/1
    timestamp: number;    // UNIX seconds
}

// In-memory: gameID → Rating[]
const ratings = new Map<string, Rating[]>();
// Cooldown: playerID → last submit timestamp (ms)
const ratingCooldowns = new Map<string, number>();

if (!existsSync(RATING_DATA_DIR)) mkdirSync(RATING_DATA_DIR, { recursive: true });

function ratingFilePath(gameID: string): string {
    // Sanitize gameID for filesystem safety
    const safe = gameID.replace(/[^a-zA-Z0-9_\-]/g, "_").slice(0, 64);
    return join(RATING_DATA_DIR, `${safe}.json`);
}

function loadRatings(gameID: string): Rating[] {
    if (ratings.has(gameID)) return ratings.get(gameID)!;
    const fp = ratingFilePath(gameID);
    let list: Rating[] = [];
    if (existsSync(fp)) {
        try { list = JSON.parse(readFileSync(fp, "utf-8")); } catch { list = []; }
    }
    ratings.set(gameID, list);
    return list;
}

function saveRatings(gameID: string): void {
    const list = ratings.get(gameID);
    if (!list) return;
    writeFile(ratingFilePath(gameID), JSON.stringify(list)).catch(() => {});
}

function addRating(player: TcpPlayer, stars: number, cleared: number): boolean {
    const now = Date.now();
    const lastSubmit = ratingCooldowns.get(player.id) || 0;
    if (now - lastSubmit < RATING_COOLDOWN_SEC * 1000) return false;
    ratingCooldowns.set(player.id, now);

    const list = loadRatings(player.game);
    // Remove previous rating from same playerID for this game
    for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].playerID === player.id) { list.splice(i, 1); break; }
    }
    list.push({
        playerID: player.id,
        gameID: player.game,
        gameName: player.gameName,
        playerName: player.name,
        stars,
        cleared,
        timestamp: Math.floor(now / 1000),
    });
    // Trim oldest if over limit
    while (list.length > RATING_MAX_PER_GAME) list.shift();
    saveRatings(player.game);
    return true;
}

/* ── Helpers ───────────────────────────────────────── */

function removeById<T extends { id: string | null }>(list: T[], id: string): void {
    for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].id === id) list.splice(i, 1);
    }
}

function parseLegacyVersion(version: string): [number, number, number] | null {
    const parts = version.split(".");
    if (parts.length < 3) return null;
    const parsed = parts.slice(0, 3).map((part) => {
        const match = part.match(/^\d+/);
        return match ? Number(match[0]) : Number.NaN;
    });
    if (parsed.some(Number.isNaN)) return null;
    return [parsed[0], parsed[1], parsed[2]];
}

function isVersionCompatible(version: string): boolean {
    const v = parseLegacyVersion(version);
    const min = parseLegacyVersion(MIN_CLIENT_VERSION);
    if (!v || !min) return false;
    for (let i = 0; i < 3; i++) {
        if (v[i] < min[i]) return false;
        if (v[i] > min[i]) return true;
    }
    return true;
}

/* ── TCP framing ───────────────────────────────────── */

function sendTo(player: TcpPlayer, msg: SmartBuffer): void {
    if (player.quitted) return;
    player.socket.write(frameMessage(msg.toBuffer()));
    msg.destroy();
}

function sendRosterTo(player: TcpPlayer): void {
    if (player.quitted || player.game === "" || player.name === "") return;
    const peers = tcpPlayers.filter(p =>
        p.id !== player.id && p.game === player.game && !p.quitted && p.name !== ""
    );
    const reply = new SmartBuffer();
    reply.writeUInt8(TcpMsg.LIST);
    reply.writeUInt16LE(peers.length);
    for (const p of peers) {
        reply.writeStringNT(p.id);
        reply.writeStringNT(p.name);
        reply.writeUInt8(p.team);
    }
    sendTo(player, reply);
    for (const p of peers) {
        if (!p.spectating) continue;
        const spectatingMsg = new SmartBuffer();
        spectatingMsg.writeUInt8(TcpMsg.TEAM);
        spectatingMsg.writeStringNT(p.id);
        spectatingMsg.writeUInt8(0xFE);
        sendTo(player, spectatingMsg);
    }
    // Replay skin state: LIST responses double as the skin catch-up channel
    // (join, periodic reconcile and post-game_restart room-change requests all
    // land here), so remote skins recover without a dedicated resync path.
    if (supportsSkins(player)) {
        let skinCount = 0;
        for (const p of peers) {
            if (!p.skinHash) continue;
            const skinMsg = new SmartBuffer();
            skinMsg.writeUInt8(TcpMsg.SKIN_NOTIFY);
            skinMsg.writeStringNT(p.id);
            skinMsg.writeBuffer(p.skinHash);
            skinMsg.writeStringNT(p.skinHint);
            sendTo(player, skinMsg);
            skinCount++;
        }
        if (skinCount > 0) log.info(`roster skins -> ${player.id} (${JSON.stringify(player.name)}): ${skinCount}`);
    }
}

function broadcastRoster(game: string): void {
    if (game === "") return;
    for (const p of tcpPlayers) {
        if (p.quitted || p.game !== game || p.name === "") continue;
        sendRosterTo(p);
    }
}

function broadcastFrom(sender: TcpPlayer, msg: SmartBuffer): void {
    const framed = frameMessage(msg.toBuffer());
    for (const p of tcpPlayers) {
        if (p.id === sender.id || p.game !== sender.game || sender.game === "") continue;
        if (!p.quitted) p.socket.write(framed);
    }
    msg.destroy();
}

function broadcastFromSameTeam(sender: TcpPlayer, msg: SmartBuffer): void {
    const framed = frameMessage(msg.toBuffer());
    for (const p of tcpPlayers) {
        if (p.id === sender.id || p.game !== sender.game || sender.game === "") continue;
        if (p.team !== sender.team) continue;
        if (!p.quitted) p.socket.write(framed);
    }
    msg.destroy();
}

function quitPlayer(player: TcpPlayer, reason: string = "unknown"): void {
    if (player.quitted) return;
    player.quitted = true;
    log.info(`quit ${player.id} name=${JSON.stringify(player.name)} game=${JSON.stringify(player.game)} team=${player.team} reason=${reason}`);
    // Clean udpByGame index before removing
    for (let i = udpEndpoints.length - 1; i >= 0; i--) {
        if (udpEndpoints[i].id === player.id) {
            const ep = udpEndpoints[i];
            if (ep.game !== null) {
                const s = udpByGame.get(ep.game);
                if (s) { s.delete(ep); if (s.size === 0) udpByGame.delete(ep.game); }
            }
            udpEndpoints.splice(i, 1);
        }
    }
    removeById(tcpPlayers, player.id);
    const msg = new SmartBuffer();
    msg.writeUInt8(TcpMsg.DESTROYED);
    msg.writeStringNT(player.id);
    broadcastFrom(player, msg);
    broadcastRoster(player.game);
    player.socket.destroy();
    cleanupSyncForGameIfEmpty(player.game);
}

/**
 * Extract complete VarInt-framed messages from the player's receive buffer.
 * Handles TCP stream reassembly: partial messages remain in the buffer
 * until enough data arrives.
 */
function extractMessages(player: TcpPlayer): SmartBuffer[] {
    const out: SmartBuffer[] = [];
    while (player.recvBuf.length > 0) {
        const vLen = varintByteLen(player.recvBuf[0]);
        if (player.recvBuf.length < vLen) break; // need more data for VarInt
        const payloadLen = readVarint(player.recvBuf, 0, vLen);
        if (payloadLen > MAX_TCP_MESSAGE) {
            quitPlayer(player, `frame_too_large(${payloadLen})`);
            return out;
        }
        const totalLen = vLen + payloadLen;
        if (player.recvBuf.length < totalLen) break; // need more data for payload
        out.push(SmartBuffer.fromBuffer(Buffer.from(player.recvBuf.subarray(vLen, totalLen))));
        player.recvBuf = player.recvBuf.subarray(totalLen);
    }
    return out;
}

/* ── TCP message handler ───────────────────────────── */


/* -- Session caches (N4): per-game note ring + last save ---------------- */

interface NoteCacheEntry {
    senderId: string;
    seq: number;
    room: number;
    /** body as read from the wire: subType, room, seq, payload (verbatim). */
    body: Buffer;
    ts: number;
}

const noteCache = new Map<string, NoteCacheEntry[]>();
const saveCache = new Map<string, Map<number, { gravity: number; name: string; x: number; y: number; room: number; ts: number }>>();
const gameEmptySince = new Map<string, number>();

function noteCacheAdd(game: string, senderId: string, seq: number, room: number, body: Buffer): void {
    if (game === "") return;
    let ring = noteCache.get(game);
    if (!ring) { ring = []; noteCache.set(game, ring); }
    ring.push({ senderId, seq, room, body: Buffer.from(body), ts: Date.now() });
    if (ring.length > NOTE_CACHE_MAX_PER_GAME) ring.shift();
}

function noteCacheDelete(game: string, senderId: string, seq: number): void {
    const ring = noteCache.get(game);
    if (!ring) return;
    for (let i = ring.length - 1; i >= 0; i--) {
        if (ring[i].senderId === senderId && ring[i].seq === seq) ring.splice(i, 1);
    }
}

function gameCacheSweep(): void {
    // Drop the caches of games that have been empty for GAME_CACHE_EXPIRY_MS.
    const now = Date.now();
    const games = new Set<string>([...noteCache.keys(), ...saveCache.keys()]);
    for (const g of games) {
        const alive = tcpPlayers.some(p => !p.quitted && p.game === g);
        if (alive) { gameEmptySince.delete(g); continue; }
        const since = gameEmptySince.get(g) ?? now;
        gameEmptySince.set(g, since);
        if (now - since >= GAME_CACHE_EXPIRY_MS) {
            noteCache.delete(g);
            saveCache.delete(g);
            gameEmptySince.delete(g);
            log.info('cache expired for game ' + JSON.stringify(g));
        }
    }
}

function handleTcpMessage(player: TcpPlayer, msg: SmartBuffer): void {
    let reply: SmartBuffer;
    switch (msg.readUInt8()) {
        case TcpMsg.CREATED:
            if (msg.remaining() > 0) { quitPlayer(player, "created_extra_bytes"); return; }
            reply = new SmartBuffer();
            reply.writeUInt8(TcpMsg.CREATED);
            reply.writeStringNT(player.id);
            reply.writeStringNT(player.name);
            broadcastFrom(player, reply);
            // On the FIRST CREATED from this player, replay the full roster
            // (existing players + their teams) so the new joiner sees everyone
            // even if they're idle. Subsequent CREATEDs (e.g. respawn) skip this.
            if (!player.rosterSent) {
                player.rosterSent = true;
                for (const p of tcpPlayers) {
                    if (p.id === player.id || p.game !== player.game || p.quitted) continue;
                    if (p.name === "") continue; // not yet registered (no NAME)
                    const cMsg = new SmartBuffer();
                    cMsg.writeUInt8(TcpMsg.CREATED);
                    cMsg.writeStringNT(p.id);
                    cMsg.writeStringNT(p.name);
                    sendTo(player, cMsg);
                    if (p.team > 0) {
                        const teamMsg = new SmartBuffer();
                        teamMsg.writeUInt8(TcpMsg.TEAM);
                        teamMsg.writeStringNT(p.id);
                        teamMsg.writeUInt8(p.team);
                        sendTo(player, teamMsg);
                    }
                    if (p.spectating) {
                        const spectatingMsg = new SmartBuffer();
                        spectatingMsg.writeUInt8(TcpMsg.TEAM);
                        spectatingMsg.writeStringNT(p.id);
                        spectatingMsg.writeUInt8(0xFE);
                        sendTo(player, spectatingMsg);
                    }
                }
            }
            // Replay current team-shared sync snapshot once on first CREATED.
            if (!player.syncReplayed) {
                player.syncReplayed = true;
                replaySyncTo(player);
            }
            break;

        case TcpMsg.DESTROYED:
            if (msg.remaining() > 0) { quitPlayer(player, "destroyed_extra_bytes"); return; }
            reply = new SmartBuffer();
            reply.writeUInt8(TcpMsg.DESTROYED);
            reply.writeStringNT(player.id);
            broadcastFrom(player, reply);
            break;

        case TcpMsg.HEARTBEAT:
            if (msg.remaining() > 0) quitPlayer(player, "heartbeat_extra_bytes");
            break;

        case TcpMsg.NAME:
            if (msg.remaining() > 990) { quitPlayer(player, "name_too_large"); return; }
            player.name = msg.readStringNT();
            player.game = msg.readStringNT();
            player.gameName = msg.readStringNT();
            {
                const version = msg.readStringNT();
                player.hasPassword = msg.readUInt8() === 1;
                player.protocolVersion = msg.remaining() > 0 ? msg.readUInt8() : 0;
                const compatible = player.protocolVersion > 0
                    ? player.protocolVersion >= MIN_PROTOCOL_VERSION
                    : isVersionCompatible(version);
                if (!compatible) {
                    reply = new SmartBuffer();
                    reply.writeUInt8(2); // Incompatible version (server→client)
                    reply.writeStringNT(MIN_CLIENT_VERSION);
                    sendTo(player, reply);
                    setTimeout(() => quitPlayer(player, `incompatible_version(${version})`), 1000);
                } else {
                    broadcastRoster(player.game);
                }
            }
            break;

        case TcpMsg.CHAT:
            if (msg.remaining() > 990) { quitPlayer(player, "chat_too_large"); return; }
            {
                let text = msg.readStringNT().replace(/[\uD800-\uDFFF]/g, "");
                if (text.length > 300) text = text.slice(0, 300);
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.CHAT);
                reply.writeStringNT(player.id);
                reply.writeStringNT(text);
                broadcastFrom(player, reply);
            }
            break;

        case TcpMsg.SAVE:
            if (msg.remaining() > 80) { quitPlayer(player, "save_too_large"); return; }
            {
                const gravity = msg.readUInt8();
                const x = msg.readInt32LE();
                const y = msg.readDoubleLE();
                const room = msg.readUInt16LE();
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.SAVE);
                reply.writeUInt8(gravity);
                reply.writeStringNT(player.name);
                reply.writeInt32LE(x);
                reply.writeDoubleLE(y);
                reply.writeInt16LE(room);
                broadcastFromSameTeam(player, reply);
                if (player.game !== "") {
                    let perTeam = saveCache.get(player.game);
                    if (!perTeam) { perTeam = new Map(); saveCache.set(player.game, perTeam); }
                    perTeam.set(player.team, { gravity, name: player.name, x, y, room, ts: Date.now() });
                }
            }
            break;

        case TcpMsg.CUSTOM_DATA:
            // Backward-compat: silently drop legacy v1 frames or any malformed
            // payload instead of disconnecting. Old clients (beta3 and earlier)
            // sent `[u16 1][i32 customSlot]` here, which would otherwise be
            // mis-parsed as v2 and trigger a kick on first save.
            if (msg.remaining() < 2) return;
            if (!supportsCustomDataV2(player)) return;
            {
                const v2flag = msg.readUInt8();
                if (v2flag !== 1) return;
                const entryCount = msg.readUInt8();
                if (entryCount === 0 || entryCount > MAX_SYNC_ENTRIES) return;
                // Parse first; silently drop the frame on any validation failure.
                const incoming: { name: string; count: number; slotCount: number; bits: Uint32Array }[] = [];
                let totalSlots = 0;
                for (let k = 0; k < entryCount; k++) {
                    if (msg.remaining() < 5) return; // name(>=1) + count(2) + slotCount(2)
                    const name = msg.readStringNT();
                    if (name.length === 0 || name.length > MAX_SYNC_NAME_LEN || !SYNC_NAME_RE.test(name)) {
                        return;
                    }
                    const count = msg.readUInt16LE();
                    const slotCount = msg.readUInt16LE();
                    if (count === 0 || count > 512) return;
                    const expectSlots = (count + 31) >>> 5;
                    if (slotCount !== expectSlots || slotCount > MAX_PER_ENTRY_SLOTS) return;
                    totalSlots += slotCount;
                    if (totalSlots > MAX_CUSTOM_SLOTS) return;
                    if (msg.remaining() < slotCount * 4) return;
                    const bits = new Uint32Array(slotCount);
                    for (let i = 0; i < slotCount; i++) bits[i] = msg.readUInt32LE();
                    incoming.push({ name, count, slotCount, bits });
                }
                // Merge (OR) into team-shared state.
                const team = getTeamSync(player.game, player.team, true)!;
                for (const inc of incoming) {
                    let cur = team.get(inc.name);
                    if (!cur) {
                        // enforce per-team entry cap
                        if (team.size >= MAX_SYNC_ENTRIES) return;
                        cur = { count: inc.count, slotCount: inc.slotCount, bits: new Uint32Array(inc.bits) };
                        team.set(inc.name, cur);
                        continue;
                    }
                    if (inc.count > cur.count) {
                        // grow
                        const grown = new Uint32Array(inc.slotCount);
                        grown.set(cur.bits);
                        cur.bits = grown;
                        cur.count = inc.count;
                        cur.slotCount = inc.slotCount;
                    }
                    for (let i = 0; i < inc.slotCount; i++) cur.bits[i] = (cur.bits[i] | inc.bits[i]) >>> 0;
                }
                // Broadcast merged snapshot to all teammates (incl. sender).
                // Sync is bucketed strictly by (game, team), so only same-team peers receive.
                const framed = frameMessage(encodeSyncSnapshot(player.id, team).toBuffer());
                for (const p of tcpPlayers) {
                    if (p.game !== player.game || p.quitted) continue;
                    if (p.team !== player.team) continue;
                    if (!supportsCustomDataV2(p)) continue;
                    p.socket.write(framed);
                }
            }
            break;

        case TcpMsg.TEAM:
            if (msg.remaining() !== 1) { quitPlayer(player, "team_bad_size"); return; }
            {
                const team = msg.readUInt8();
                // 0xFE = spectator-on marker (sent by client when entering spectator).
                // Keep the player's real team for sync/save routing, but persist the
                // spectator flag so CREATED replay and LIST can rebuild the state.
                if (team === 0xFE) {
                    player.spectating = true;
                } else {
                    if (team >= MAX_TEAMS) { quitPlayer(player, `team_out_of_range(${team})`); return; }
                    player.spectating = false;
                    if (team !== player.team) {
                        player.team = team;
                        // Replay the new team's shared sync snapshot.
                        replaySyncTo(player);
                    }
                }
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.TEAM);
                reply.writeStringNT(player.id);
                reply.writeUInt8(team);
                broadcastFrom(player, reply);
            }

                if (player.game !== "" && (player.saveCacheSentTeams & (1 << player.team)) === 0) {
                    player.saveCacheSentTeams |= (1 << player.team); // team is 0..7 (MAX_TEAMS), so the shift stays in range
                    const cached = saveCache.get(player.game)?.get(player.team);
                    if (cached && Date.now() - cached.ts < SAVE_CACHE_MAX_AGE_MS) {
                        const sMsg = new SmartBuffer();
                        sMsg.writeUInt8(TcpMsg.SAVE);
                        sMsg.writeUInt8(cached.gravity);
                        sMsg.writeStringNT(cached.name);
                        sMsg.writeInt32LE(cached.x);
                        sMsg.writeDoubleLE(cached.y);
                        sMsg.writeInt16LE(cached.room);
                        sendTo(player, sMsg);
                        log.info('SAVE cache -> ' + player.id + ' (' + JSON.stringify(player.name) + ') game=' + JSON.stringify(player.game) + ' team=' + player.team);
                    }
                }
                        break;

        case TcpMsg.RATING:
            if (msg.remaining() < 2) { quitPlayer(player, "rating_short"); return; }
            if (player.game === "" || player.name === "") break;
            {
                const stars = msg.readUInt8();
                const cleared = msg.readUInt8();
                if (stars < 1 || stars > 5 || cleared > 1) { quitPlayer(player, `rating_bad(${stars},${cleared})`); return; }
                const ok = addRating(player, stars, cleared);
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.RATING);
                reply.writeUInt8(ok ? 1 : 0);
                sendTo(player, reply);
            }
            break;

        case TcpMsg.PING:
            // Map ping. Whole-game broadcast (not team-restricted).
            // Legacy client: 9 bytes [f32 x][f32 y][u8 type] — no room id, peers may render off-screen.
            // Current client: 13 bytes [i32 room][f32 x][f32 y][u8 type] — receivers filter by room.
            if (msg.remaining() !== 9 && msg.remaining() !== 13) { quitPlayer(player, "ping_bad_size"); return; }
            if (player.game === "" || player.name === "") { log.info(`PING dropped from ${player.id}: game=${JSON.stringify(player.game)} name=${JSON.stringify(player.name)}`); break; }
            {
                const hasRoom = msg.remaining() === 13;
                const room = hasRoom ? msg.readInt32LE() : -1;
                const px = msg.readFloatLE();
                const py = msg.readFloatLE();
                const pt = msg.readUInt8();
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.PING);
                reply.writeStringNT(player.id);
                if (hasRoom) reply.writeInt32LE(room);
                reply.writeFloatLE(px);
                reply.writeFloatLE(py);
                reply.writeUInt8(pt);
                let recipientCount = 0;
                for (const p of tcpPlayers) {
                    if (p.id === player.id || p.game !== player.game || player.game === "") continue;
                    if (!p.quitted) recipientCount++;
                }
                log.info(`PING from ${player.id} (${JSON.stringify(player.name)}) game=${JSON.stringify(player.game)} hasRoom=${hasRoom} room=${room} pt=${pt} -> ${recipientCount} peers`);
                broadcastFrom(player, reply);
            }
            break;

        case TcpMsg.LIST:
            // Roster reconciliation request. Newer clients append their SELF_ID so
            // the server can assert the request is bound to the expected connection.
            if (msg.remaining() > 0) {
                const requestedBy = msg.readStringNT();
                if (msg.remaining() > 0) { quitPlayer(player, "list_extra_bytes"); return; }
                if (requestedBy !== "" && requestedBy !== player.id) {
                    quitPlayer(player, `list_id_mismatch(${JSON.stringify(requestedBy)})`);
                    return;
                }
            }
            if (player.game === "") break;
            sendRosterTo(player);
            break;

        case TcpMsg.SKIN:
            // 16-byte hash + stringNT dir-name hint. All-zero hash = no skin.
            if (msg.remaining() < 17 || msg.remaining() > 300) { quitPlayer(player, "skin_bad_size"); return; }
            {
                const hash = msg.readBuffer(16);
                const hint = msg.readStringNT().slice(0, 255);
                if (msg.remaining() > 0) { quitPlayer(player, "skin_extra_bytes"); return; }
                player.skinHint = hint;
                player.skinHash = hash.every(b => b === 0) ? null : hash;
                log.info(`SKIN from ${player.id} (${JSON.stringify(player.name)}) game=${JSON.stringify(player.game)} hash=${player.skinHash ? player.skinHash.toString("hex").slice(0, 8) : "-"} hint=${JSON.stringify(player.skinHint)}`);
                // Relay to same-game peers that understand skins (version gate:
                // older clients must never see opcode 13).
                const notify = new SmartBuffer();
                notify.writeUInt8(TcpMsg.SKIN_NOTIFY);
                notify.writeStringNT(player.id);
                notify.writeBuffer(hash);
                notify.writeStringNT(player.skinHint);
                const framed = frameMessage(notify.toBuffer());
                notify.destroy();
                let relayCount = 0;
                for (const p of tcpPlayers) {
                    if (p.id === player.id || p.game !== player.game || player.game === "") continue;
                    if (p.quitted || !supportsSkins(p)) continue;
                    p.socket.write(framed);
                    relayCount++;
                }
                if (relayCount > 0) log.info(`SKIN relay ${player.id} -> ${relayCount} peers`);
            }
            break;

        case TcpMsg.SKIN_GET:
            // 16-byte hash -> package manifest from the server skin library.
            if (!supportsSkins(player)) { quitPlayer(player, "skin_get_version"); return; }
            if (msg.remaining() !== 16) { quitPlayer(player, "skin_get_bad_size"); return; }
            {
                const hash = msg.readBuffer(16);
                const hex = hash.toString("hex");
                if (!skinDlAllow(player, 0)) break;
                const reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.SKIN_MANIFEST);
                reply.writeBuffer(hash);
                const manifest = skinManifest(hex);
                if (!manifest) {
                    reply.writeUInt8(1);
                    sendTo(player, reply);
                    log.info(`SKIN_GET ${player.id} (${JSON.stringify(player.name)}) hash=${hex.slice(0, 8)} -> not found`);
                    break;
                }
                reply.writeUInt8(0);
                reply.writeUInt8(manifest.length);
                for (const f of manifest) {
                    reply.writeStringNT(f.name);
                    reply.writeUInt32LE(f.size);
                }
                sendTo(player, reply);
                log.info(`SKIN_GET ${player.id} (${JSON.stringify(player.name)}) hash=${hex.slice(0, 8)} -> ${manifest.length} files`);
            }
            break;

        case TcpMsg.SKIN_FILE_REQ:
            // 16-byte hash + stringNT name (must be a manifest entry) -> file
            // content in 16 KiB SKIN_FILE chunks (offset-ordered).
            if (!supportsSkins(player)) { quitPlayer(player, "skin_file_version"); return; }
            if (msg.remaining() < 17 || msg.remaining() > 120) { quitPlayer(player, "skin_file_bad_size"); return; }
            {
                const hash = msg.readBuffer(16);
                const name = msg.readStringNT();
                if (msg.remaining() > 0) { quitPlayer(player, "skin_file_extra"); return; }
                const hex = hash.toString("hex");
                const manifest = skinManifest(hex);
                const entry = manifest ? manifest.find(f => f.name === name) : undefined;
                let data: Buffer | null = null;
                if (entry) {
                    try { data = readFileSync(join(SKIN_DATA_DIR, hex, name)); } catch { data = null; }
                }
                if (!entry || data === null) {
                    if (!skinDlAllow(player, 0)) break;
                    const reply = new SmartBuffer();
                    reply.writeUInt8(TcpMsg.SKIN_FILE);
                    reply.writeBuffer(hash);
                    reply.writeStringNT(name.slice(0, 64));
                    reply.writeUInt8(1); // not found / unreadable
                    sendTo(player, reply);
                    break;
                }
                if (!skinDlAllow(player, data.length)) break; // limiter drop: client times out
                log.info(`SKIN_FILE_REQ ${player.id} (${JSON.stringify(player.name)}) hash=${hex.slice(0, 8)} file=${JSON.stringify(name)} (${data.length}B)`);
                // Empty files still get one terminal chunk so the client sees pos==size.
                for (let off = 0; off < Math.max(data.length, 1); off += SKIN_CHUNK) {
                    const chunk = data.subarray(off, Math.min(off + SKIN_CHUNK, data.length));
                    const m = new SmartBuffer();
                    m.writeUInt8(TcpMsg.SKIN_FILE);
                    m.writeBuffer(hash);
                    m.writeStringNT(name);
                    m.writeUInt8(0);
                    m.writeUInt32LE(data.length);
                    m.writeUInt32LE(off);
                    m.writeUInt16LE(chunk.length);
                    m.writeBuffer(chunk);
                    sendTo(player, m);
                    if (data.length === 0) break;
                }
            }
            break;

        case TcpMsg.BULLET:
            // Bullet sharing: u8 count(1..8, OR'd with 0x80 in wire format
            // v2), u16 room, then per bullet: i32 id, i32 x, i32 y,
            // f32 direction, f32 speed (v1, 20 bytes) plus f32 image_xscale,
            // f32 image_angle (v2, 28 bytes). High-frequency relay (one
            // message per frame while the sender has bullets) — relayed to
            // same-game peers that understand skins, sender id prepended.
            // The 0x80 flag is relayed verbatim: v2 clients parse both
            // formats, v1 clients drop flagged messages (count > 8 fails
            // their range check), so mixed-version rooms degrade to
            // flip-less bullets instead of misparsing. No info logging
            // (too noisy).
            if (!supportsSkins(player)) { quitPlayer(player, "bullet_version"); return; }
            // Largest legal payload: count(1) + room(2) + 8*28 = 227 bytes.
            if (msg.remaining() < 3 || msg.remaining() > 227) { quitPlayer(player, "bullet_bad_size"); return; }
            {
                const rawCount = msg.readUInt8();
                const v2 = (rawCount & 0x80) !== 0;
                const count = rawCount & 0x7f;
                const stride = v2 ? 28 : 20;
                if (count < 1 || count > 8 || msg.remaining() !== 2 + stride * count) {
                    quitPlayer(player, "bullet_bad_size");
                    return;
                }
                // Per-player rate limit: ~1 msg/frame/player is legit; drop the
                // burst instead of kicking (a lost relay just skips a frame).
                const now = Date.now();
                if (now - player.bulletWindowStart >= 10000) {
                    player.bulletWindowStart = now;
                    player.bulletCount = 0;
                }
                player.bulletCount += 1;
                if (player.bulletCount > 600) break;
                // NOTE: SmartBuffer.toBuffer() returns the WHOLE buffer (incl.
                // the opcode byte); readBuffer(remaining) yields exactly the
                // room + per-bullet body that gets relayed.
                const body = msg.readBuffer(msg.remaining());
                const notify = new SmartBuffer();
                notify.writeUInt8(TcpMsg.BULLET_NOTIFY);
                notify.writeStringNT(player.id);
                notify.writeUInt8(rawCount); // keep the v2 flag for the receivers
                notify.writeBuffer(body); // room + per-bullet state
                const framed = frameMessage(notify.toBuffer());
                notify.destroy();
                let relayCount = 0;
                for (const p of tcpPlayers) {
                    if (p.id === player.id || p.game !== player.game || player.game === "") continue;
                    if (p.quitted || !supportsSkins(p)) continue;
                    p.socket.write(framed);
                    relayCount++;
                }
                if (relayCount > 0 && process.env.DSH_BULLET_DEBUG) {
                    log.debug(`BULLET ${player.id} -> ${relayCount} peers (count=${count})`);
                }
            }
            break;

        case TcpMsg.NOTE:
            // Notes/annotations relay + per-game session cache (protocol
            // v5+). Wire header: u8 subType, i32 room, u16 seq, then the
            // per-subtype body. S→C prepends stringNT senderId; sync replays
            // (NOTE_SYNC) set subType|0x20 so receivers store them already
            // past-toast. sub 4 = DELETE (no body): drops the sender's note
            // (matched by seq) from the server cache only, never relayed.
            if (!supportsNotes(player)) { quitPlayer(player, "note_version"); return; }
            // Smallest legal: header(7) only (DELETE). Largest: STROKE chunk
            // = 7 + strokeId(1)+chunk(1)+n(1)+8+239*4 = 974.
            if (msg.remaining() < 7 || msg.remaining() > 980) { quitPlayer(player, "note_bad_size"); return; }
            {
                const bodyStart = msg.readOffset;
                const subType = msg.readUInt8();
                if (subType > 4) { quitPlayer(player, "note_bad_subtype"); return; }
                const room = msg.readInt32LE();
                const seq = msg.readUInt16LE();
                let ok = false;
                if (subType === 0) {
                    // ICON: f32 x, f32 y, u8 iconId
                    ok = msg.remaining() === 9;
                } else if (subType === 1) {
                    // POLYLINE: u8 flags, u8 n(2..24), n×(f32 x, f32 y)
                    if (msg.remaining() < 2) { ok = false; }
                    else {
                        msg.readOffset += 1; // flags
                        const n = msg.readUInt8();
                        ok = n >= 2 && n <= 24 && msg.remaining() === 8 * n;
                    }
                } else if (subType === 2) {
                    // STROKE chunk: u8 strokeId, u8 chunk(bit6=pen-up, bit7=last),
                    // u8 n(1..240), i32 x0, i32 y0, then (n-1)×(i16 dx, i16 dy)
                    if (msg.remaining() < 3) { ok = false; }
                    else {
                        msg.readOffset += 2; // strokeId + chunk
                        const n = msg.readUInt8();
                        ok = n >= 1 && n <= 240 && msg.remaining() === 8 + 4 * (n - 1);
                    }
                } else if (subType === 3) {
                    // TEXT: f32 x, f32 y, stringNT utf8 (<=300 bytes of text)
                    if (msg.remaining() >= 10) {
                        msg.readOffset += 8; // x, y
                        const text = msg.readStringNT();
                        ok = msg.remaining() === 0 && Buffer.byteLength(text, "utf8") <= 300;
                    }
                } else {
                    // DELETE: no body beyond the header
                    ok = msg.remaining() === 0;
                }
                if (!ok) { quitPlayer(player, "note_bad_body"); return; }
                // Per-subtype drop-not-kick buckets (BULLET pattern); DELETE
                // shares the ICON bucket (both are small, human-rate messages).
                const now = Date.now();
                const bucket = subType;
                if (now - player.noteWindowStart[bucket] >= 10000) {
                    player.noteWindowStart[bucket] = now;
                    player.noteCount[bucket] = 0;
                }
                player.noteCount[bucket] += 1;
                if (player.noteCount[bucket] > NOTE_RATE_LIMITS[bucket]) {
                    player.noteDropStreak += 1;
                    if (player.noteDropStreak > 40) { quitPlayer(player, "note_flood"); return; }
                    break;
                }
                player.noteDropStreak = 0;
                if (subType === 4) {
                    noteCacheDelete(player.game, player.id, seq);
                    break;
                }
                msg.readOffset = bodyStart;
                const body = msg.readBuffer(msg.remaining()); // subType..payload
                noteCacheAdd(player.game, player.id, seq, room, body);
                const notify = new SmartBuffer();
                notify.writeUInt8(TcpMsg.NOTE);
                notify.writeStringNT(player.id);
                notify.writeBuffer(body);
                const framed = frameMessage(notify.toBuffer());
                notify.destroy();
                let relayCount = 0;
                for (const p of tcpPlayers) {
                    if (p.id === player.id || p.game !== player.game || player.game === "") continue;
                    if (p.quitted || !supportsNotes(p)) continue;
                    p.socket.write(framed);
                    relayCount++;
                }
                if (relayCount > 0 && process.env.DSH_NOTE_DEBUG) {
                    log.debug(`NOTE ${player.id} -> ${relayCount} peers (sub=${subType})`);
                }
                // Legacy bridge: an ICON note with a legacy-compatible iconId
                // (0..8) is synthesized into an opcode 11 PING for pre-v5
                // peers, so old clients keep seeing markers. Each peer gets
                // exactly one format (NOTE xor PING), so no dedup is needed.
                if (subType === 0) {
                    const iconId = body.readUInt8(15);
                    if (iconId <= 8) {
                        const ping = new SmartBuffer();
                        ping.writeUInt8(TcpMsg.PING);
                        ping.writeStringNT(player.id);
                        ping.writeInt32LE(room);
                        ping.writeFloatLE(body.readFloatLE(7));  // x
                        ping.writeFloatLE(body.readFloatLE(11)); // y
                        ping.writeUInt8(iconId);
                        const pingFramed = frameMessage(ping.toBuffer());
                        ping.destroy();
                        for (const p of tcpPlayers) {
                            if (p.id === player.id || p.game !== player.game || player.game === "") continue;
                            if (p.quitted || supportsNotes(p)) continue;
                            p.socket.write(pingFramed);
                        }
                    }
                }
            }
            break;

        case TcpMsg.NOTE_SYNC:
            // C→S: i32 room — replay the cached notes for that room of the
            // sender's game, each as a NOTE with subType|0x20 (past-toast).
            // Pull model: the server never tracks the client's current room.
            if (!supportsNotes(player)) { quitPlayer(player, "note_sync_version"); return; }
            if (msg.remaining() !== 4) { quitPlayer(player, "note_sync_bad_size"); return; }
            {
                const syncRoom = msg.readInt32LE();
                const now = Date.now();
                if (now - player.noteSyncAt < NOTE_SYNC_MIN_MS) break;
                player.noteSyncAt = now;
                const ring = noteCache.get(player.game);
                if (!ring) break;
                let sent = 0;
                const NOTE_SYNC_MAX = 64; // amplification cap: replay the newest 64
                const roomEntries = ring.filter(e => e.room === syncRoom && e.senderId !== player.id); // own notes are local already
                for (const e of roomEntries.slice(-NOTE_SYNC_MAX)) {
                    const m = new SmartBuffer();
                    m.writeUInt8(TcpMsg.NOTE);
                    m.writeStringNT(e.senderId);
                    const replayBody = Buffer.from(e.body);
                    replayBody[0] |= 0x20; // past-toast replay marker
                    m.writeBuffer(replayBody);
                    sendTo(player, m);
                    sent++;
                }
                if (sent > 0 && process.env.DSH_NOTE_DEBUG) log.debug(`NOTE_SYNC ${player.id} (${JSON.stringify(player.name)}) room=${syncRoom} -> ${sent} notes`);
            }
            break;


        default:
            quitPlayer(player, "unknown_opcode");
    }
}

/* ── TCP server ────────────────────────────────────── */

createServer((socket: Socket) => {
    const player: TcpPlayer = {
        address: socket.remoteAddress || "",
        id: `${socket.remoteAddress}${socket.remotePort}`,
        socket,
        name: "",
        game: "",
        gameName: "",
        hasPassword: false,
        msgCount: 0,
        msgWindowStart: Date.now(),
        lastHeartbeat: Date.now(),
        customSlots: null,
        syncReplayed: false,
        protocolVersion: 0,
        team: 0,
        spectating: false,
        quitted: false,
        recvBuf: Buffer.alloc(0),
        rosterSent: false,
        skinHash: null,
        skinHint: "",
        skinDlWindowStart: 0,
        skinDlReqs: 0,
        skinDlBytes: 0,
        skinDlLimited: false,
        bulletWindowStart: 0,
        bulletCount: 0,
        noteWindowStart: [0, 0, 0, 0, 0],
        noteCount: [0, 0, 0, 0, 0],
        noteSyncAt: 0,
        noteDropStreak: 0,
        saveCacheSentTeams: 0,
    };

    tcpPlayers.push(player);

    if (tcpPlayers.filter(p => p.address === player.address).length > MAX_PLAYERS_PER_IP) {
        quitPlayer(player, "max_players_per_ip");
        return;
    }

    const idMsg = new SmartBuffer();
    idMsg.writeUInt8(TcpMsg.SELF_ID);
    idMsg.writeStringNT(player.id);
    sendTo(player, idMsg);

    // Capability advertisement (protocol v5+ clients read this; older clients
    // silently drop the unknown opcode via their default case).
    const hello = new SmartBuffer();
    hello.writeUInt8(TcpMsg.SERVER_HELLO);
    hello.writeUInt8(PROTOCOL_VERSION);
    sendTo(player, hello);

    socket.on("data", (chunk: Buffer) => {
        if (player.quitted) return;
        player.lastHeartbeat = Date.now();

        player.recvBuf = Buffer.concat([player.recvBuf, chunk]);
        if (player.recvBuf.length > MAX_TCP_BUFFER) {
            quitPlayer(player, `recv_buf_overflow(${player.recvBuf.length})`);
            return;
        }

        for (const msg of extractMessages(player)) {
            if (player.quitted) break;
            // Rate limit per message (sliding 1-second window).
            // Reset the window FIRST so accumulated counts from previous
            // bursts don't kill an otherwise-quiet player as soon as a 1 s
            // gap appears.
            // BULLET is exempt from this message-level limit: it is a
            // high-frequency channel (one message per frame while firing,
            // up to 60/s at 60fps) with its OWN drop-not-kick limiter
            // (600/10s) inside the BULLET case. Counting it here would kick
            // legitimately fast firing players.
            const now = Date.now();
            if (now - player.msgWindowStart > 1000) {
                player.msgCount = 0;
                player.msgWindowStart = now;
            }
            // Peek the opcode without consuming it (smart-buffer has no peek).
            const savedOffset = msg.readOffset;
            const peekOp = msg.readUInt8();
            msg.readOffset = savedOffset;
            if (peekOp !== TcpMsg.BULLET && peekOp !== TcpMsg.NOTE) {
                player.msgCount++;
                if (player.msgCount > TCP_RATE_LIMIT) { quitPlayer(player, "tcp_rate_limit"); break; }
            }
            try {
                handleTcpMessage(player, msg);
            } catch (e) {
                quitPlayer(player, `handler_throw(${(e as Error)?.message || e})`);
            }
            msg.destroy();
        }
    });

    socket.on("close", (hadError) => quitPlayer(player, `socket_close(hadError=${hadError})`));
    socket.on("timeout", () => quitPlayer(player, "socket_timeout"));
    socket.on("error", (err) => quitPlayer(player, `socket_error(${err.message})`));
    socket.on("end", () => quitPlayer(player, "socket_end"));
}).listen(PORT_TCP, () => log.info(`TCP server on port ${PORT_TCP}`));

// Heartbeat check
setInterval(() => {
    const now = Date.now();
    const expired = tcpPlayers.filter(p => p.lastHeartbeat + HEARTBEAT_TIMEOUT_SEC * 1000 < now);
    for (const p of expired) quitPlayer(p, `heartbeat_timeout(idle=${Math.floor((now - p.lastHeartbeat)/1000)}s)`);
    gameCacheSweep();
}, HEARTBEAT_INTERVAL_SEC * 1000);

/* ── UDP server ────────────────────────────────────── */

const udpSocket = createSocket("udp4");

udpSocket.on("error", (err) => {
    log.error(`UDP error: ${err.stack}`);
    udpSocket.close();
    process.exit(1);
});

udpSocket.on("message", (data: Buffer, remote: RemoteInfo) => {
    if (data.length > MAX_UDP_MESSAGE) return;

    let ep = udpEndpoints.find(e => e.address === remote.address && e.port === remote.port);
    if (!ep) {
        ep = {
            address: remote.address,
            port: remote.port,
            id: null,
            game: null,
            room: null,
            prevRoom: null,
            lastActivity: Date.now(),
            msgCount: 0,
            msgWindowStart: Date.now(),
            killed: false,
        };
        udpEndpoints.push(ep);
    }

    if (ep.killed) return;

    // Rate limit (sliding 1-second window).
    // Reset BEFORE counting so a prior burst followed by an idle gap
    // doesn't immediately trip on the next packet.
    ep.lastActivity = Date.now();
    if (ep.lastActivity - ep.msgWindowStart > 1000) {
        ep.msgCount = 0;
        ep.msgWindowStart = ep.lastActivity;
    }
    ep.msgCount++;
    if (ep.msgCount > UDP_RATE_LIMIT) {
        ep.killed = true;
        if (ep.id) {
            const tcp = tcpPlayers.find(p => p.id === ep!.id);
            if (tcp) quitPlayer(tcp, "udp_rate_limit");
        }
        return;
    }

    const msg = SmartBuffer.fromBuffer(data);
    switch (msg.readUInt8()) {
        case UdpMsg.INIT:
            if (msg.remaining() > 0) ep.killed = true;
            break;

        case UdpMsg.POSITION:
            ep.id = msg.readStringNT();
            {
                const newGame = msg.readStringNT();
                if (newGame !== ep.game) {
                    if (ep.game !== null) {
                        const oldSet = udpByGame.get(ep.game);
                        if (oldSet) { oldSet.delete(ep); if (oldSet.size === 0) udpByGame.delete(ep.game); }
                    }
                    ep.game = newGame;
                    if (ep.game !== null) {
                        let s = udpByGame.get(ep.game);
                        if (!s) { s = new Set(); udpByGame.set(ep.game, s); }
                        s.add(ep);
                    }
                }
            }
            ep.room = msg.readUInt16LE();
            {
                const peers = udpByGame.get(ep.game!);
                if (peers) {
                    for (const other of peers) {
                        if (other.id === null || other.id === ep.id) continue;
                        if (other.killed) continue;
                        udpSocket.send(data, other.port, other.address);
                    }
                }
            }
            ep.prevRoom = ep.room;
            break;

        default:
            ep.killed = true;
    }
    msg.destroy();
});

// UDP cleanup
setInterval(() => {
    const now = Date.now();
    for (let i = udpEndpoints.length - 1; i >= 0; i--) {
        if (udpEndpoints[i].lastActivity + UDP_EXPIRY_MIN * 60000 < now || udpEndpoints[i].killed) {
            const removed = udpEndpoints[i];
            if (removed.game !== null) {
                const s = udpByGame.get(removed.game);
                if (s) { s.delete(removed); if (s.size === 0) udpByGame.delete(removed.game); }
            }
            udpEndpoints.splice(i, 1);
        }
    }
}, UDP_CLEANUP_INTERVAL_MIN * 60000);

udpSocket.bind(PORT_UDP, () => log.info(`UDP server on port ${PORT_UDP}`));

/* ── HTTP API ──────────────────────────────────────── */

function getGames(): { players: number; name: string; hasPassword: boolean }[] {
    const groups = new Map<string, { name: string; count: number; hasPassword: boolean }[]>();
    for (const p of tcpPlayers) {
        if (p.gameName === "") continue;
        let list = groups.get(p.game);
        if (!list) { list = []; groups.set(p.game, list); }
        const entry = list.find(e => e.name === p.gameName);
        if (entry) entry.count++;
        else list.push({ name: p.gameName, count: 1, hasPassword: p.hasPassword });
    }
    const result: { players: number; name: string; hasPassword: boolean }[] = [];
    for (const entries of groups.values()) {
        let total = 0, bestName = "", bestCount = 0;
        const hasPassword = entries[0].hasPassword;
        for (const e of entries) {
            total += e.count;
            if (e.count > bestCount) { bestName = e.name; bestCount = e.count; }
        }
        result.push({ players: total, name: hasPassword ? "" : bestName, hasPassword });
    }
    return result;
}

createHttpServer((req, res) => {
    const url = new URL(req.url || "/", `http://${req.headers.host || "localhost"}`);
    if (url.pathname === "/") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ games: getGames() }));
    } else if (url.pathname === "/api/games") {
        res.writeHead(200, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
        res.end(JSON.stringify({ games: getGames() }));
    } else if (url.pathname === "/api/ratings" || url.pathname === "/api/ratings/") {
        // Return all ratings across all games
        res.writeHead(200, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
        const allRatings: Rating[] = [];
        try {
            for (const f of readdirSync(RATING_DATA_DIR)) {
                if (!f.endsWith(".json")) continue;
                const gid = f.slice(0, -5);
                const list = loadRatings(gid);
                allRatings.push(...list);
            }
        } catch {}
        const safe = allRatings.map(({ playerID, ...rest }) => rest);
        res.end(JSON.stringify({ ratings: safe }));
    } else if (url.pathname.startsWith("/api/ratings/")) {
        const rawID = decodeURIComponent(url.pathname.slice("/api/ratings/".length)).replace(/[^a-zA-Z0-9_\-]/g, "_").slice(0, 64);
        res.writeHead(200, { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" });
        // Hash is first 32 chars; aggregate all gameIDs sharing the same hash
        const hash = rawID.slice(0, 32);
        const combined: Rating[] = [];
        try {
            for (const f of readdirSync(RATING_DATA_DIR)) {
                if (!f.endsWith(".json")) continue;
                const gid = f.slice(0, -5);
                if (gid.slice(0, 32) === hash) combined.push(...loadRatings(gid));
            }
        } catch {}
        const safe = combined.map(({ playerID, ...rest }) => rest);
        res.end(JSON.stringify({ ratings: safe }));
    } else {
        res.writeHead(404, { "Content-Type": "text/plain" });
        res.end("Not Found");
    }
}).listen(PORT_HTTP, () => log.info(`HTTP server on port ${PORT_HTTP}`));
