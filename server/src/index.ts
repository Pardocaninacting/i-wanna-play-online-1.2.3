import { createServer, Socket } from "node:net";
import { createServer as createHttpServer } from "node:http";
import { createSocket, RemoteInfo } from "node:dgram";
import { SmartBuffer } from "smart-buffer";
import { Logger } from "tslog";
import {
    PORT_HTTP, PORT_TCP, PORT_UDP, MIN_CLIENT_VERSION, PROTOCOL_VERSION, MIN_PROTOCOL_VERSION,
    MAX_PLAYERS_PER_IP, HEARTBEAT_INTERVAL_SEC, HEARTBEAT_TIMEOUT_SEC,
    UDP_CLEANUP_INTERVAL_MIN, UDP_EXPIRY_MIN,
    MAX_TCP_MESSAGE, MAX_TCP_BUFFER, MAX_UDP_MESSAGE, MAX_CUSTOM_SLOTS, MAX_PER_ENTRY_SLOTS,
    MAX_SYNC_ENTRIES, MAX_SYNC_NAME_LEN, MAX_TEAMS,
    TCP_RATE_LIMIT, UDP_RATE_LIMIT,
    RATING_COOLDOWN_SEC, RATING_MAX_PER_GAME, RATING_DATA_DIR,
} from "./config.js";
import { TcpMsg, UdpMsg, varintByteLen, readVarint, frameMessage } from "./protocol.js";
import { existsSync, mkdirSync, readFileSync, readdirSync } from "node:fs";
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
            const now = Date.now();
            if (now - player.msgWindowStart > 1000) {
                player.msgCount = 0;
                player.msgWindowStart = now;
            }
            player.msgCount++;
            if (player.msgCount > TCP_RATE_LIMIT) { quitPlayer(player, "tcp_rate_limit"); break; }
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
