import { createServer, Socket } from "node:net";
import { createServer as createHttpServer } from "node:http";
import { createSocket, RemoteInfo } from "node:dgram";
import { SmartBuffer } from "smart-buffer";
import { Logger } from "tslog";
import {
    PORT_HTTP, PORT_TCP, PORT_UDP, LAST_VERSION, PROTOCOL_VERSION, MIN_PROTOCOL_VERSION,
    MAX_PLAYERS_PER_IP, HEARTBEAT_INTERVAL_SEC, HEARTBEAT_TIMEOUT_SEC,
    UDP_CLEANUP_INTERVAL_MIN, UDP_EXPIRY_MIN,
    MAX_TCP_MESSAGE, MAX_TCP_BUFFER, MAX_UDP_MESSAGE, MAX_CUSTOM_SLOTS, MAX_TEAMS,
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
    protocolVersion: number;
    team: number;
    quitted: boolean;
    recvBuf: Buffer;
}

/* ── State ─────────────────────────────────────────── */

const tcpPlayers: TcpPlayer[] = [];
const udpEndpoints: UdpEndpoint[] = [];
const udpByGame = new Map<string, Set<UdpEndpoint>>();

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

function isVersionCompatible(version: string): boolean {
    try {
        const v = version.split(".").map(Number);
        const min = LAST_VERSION.split(".").map(Number);
        for (let i = 0; i < 3; i++) {
            if (v[i] < min[i]) return false;
            if (v[i] > min[i]) return true;
        }
        return true;
    } catch {
        return false;
    }
}

/* ── TCP framing ───────────────────────────────────── */

function sendTo(player: TcpPlayer, msg: SmartBuffer): void {
    if (player.quitted) return;
    player.socket.write(frameMessage(msg.toBuffer()));
    msg.destroy();
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
        if (sender.team > 0 && p.team > 0 && sender.team !== p.team) continue;
        if (!p.quitted) p.socket.write(framed);
    }
    msg.destroy();
}

function quitPlayer(player: TcpPlayer): void {
    if (player.quitted) return;
    player.quitted = true;
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
    player.socket.destroy();
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
            quitPlayer(player);
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
            if (msg.remaining() > 0) { quitPlayer(player); return; }
            reply = new SmartBuffer();
            reply.writeUInt8(TcpMsg.CREATED);
            reply.writeStringNT(player.id);
            reply.writeStringNT(player.name);
            broadcastFrom(player, reply);
            // Send existing players' teams to the newly joined player
            for (const p of tcpPlayers) {
                if (p.id === player.id || p.game !== player.game || p.quitted) continue;
                if (p.team > 0) {
                    const teamMsg = new SmartBuffer();
                    teamMsg.writeUInt8(TcpMsg.TEAM);
                    teamMsg.writeStringNT(p.id);
                    teamMsg.writeUInt8(p.team);
                    sendTo(player, teamMsg);
                }
            }
            break;

        case TcpMsg.DESTROYED:
            if (msg.remaining() > 0) { quitPlayer(player); return; }
            reply = new SmartBuffer();
            reply.writeUInt8(TcpMsg.DESTROYED);
            reply.writeStringNT(player.id);
            broadcastFrom(player, reply);
            break;

        case TcpMsg.HEARTBEAT:
            if (msg.remaining() > 0) quitPlayer(player);
            break;

        case TcpMsg.NAME:
            if (msg.remaining() > 990) { quitPlayer(player); return; }
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
                    reply.writeStringNT(LAST_VERSION);
                    sendTo(player, reply);
                    setTimeout(() => quitPlayer(player), 1000);
                }
            }
            break;

        case TcpMsg.CHAT:
            if (msg.remaining() > 990) { quitPlayer(player); return; }
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
            if (msg.remaining() > 80) { quitPlayer(player); return; }
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
            if (msg.remaining() < 2) { quitPlayer(player); return; }
            {
                const slotCount = msg.readUInt16LE();
                if (slotCount > MAX_CUSTOM_SLOTS || msg.remaining() < slotCount * 4) {
                    quitPlayer(player);
                    return;
                }
                player.customSlots = new Uint32Array(slotCount);
                for (let i = 0; i < slotCount; i++) {
                    player.customSlots[i] = msg.readUInt32LE();
                }
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.CUSTOM_DATA);
                reply.writeStringNT(player.id);
                reply.writeUInt16LE(slotCount);
                for (let i = 0; i < slotCount; i++) {
                    reply.writeUInt32LE(player.customSlots[i]);
                }
                broadcastFromSameTeam(player, reply);
            }
            break;

        case TcpMsg.TEAM:
            if (msg.remaining() !== 1) { quitPlayer(player); return; }
            {
                const team = msg.readUInt8();
                if (team >= MAX_TEAMS) { quitPlayer(player); return; }
                player.team = team;
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.TEAM);
                reply.writeStringNT(player.id);
                reply.writeUInt8(team);
                broadcastFrom(player, reply);
            }
            break;

        case TcpMsg.RATING:
            if (msg.remaining() < 2) { quitPlayer(player); return; }
            if (player.game === "" || player.name === "") break;
            {
                const stars = msg.readUInt8();
                const cleared = msg.readUInt8();
                if (stars < 1 || stars > 5 || cleared > 1) { quitPlayer(player); return; }
                const ok = addRating(player, stars, cleared);
                reply = new SmartBuffer();
                reply.writeUInt8(TcpMsg.RATING);
                reply.writeUInt8(ok ? 1 : 0);
                sendTo(player, reply);
            }
            break;

        default:
            quitPlayer(player);
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
        protocolVersion: 0,
        team: 0,
        quitted: false,
        recvBuf: Buffer.alloc(0),
    };

    tcpPlayers.push(player);

    if (tcpPlayers.filter(p => p.address === player.address).length > MAX_PLAYERS_PER_IP) {
        quitPlayer(player);
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
            quitPlayer(player);
            return;
        }

        for (const msg of extractMessages(player)) {
            if (player.quitted) break;
            // Rate limit per message
            player.msgCount++;
            const now = Date.now();
            if (now - player.msgWindowStart > 1000) {
                if (player.msgCount > TCP_RATE_LIMIT) { quitPlayer(player); break; }
                player.msgCount = 0;
                player.msgWindowStart = now;
            }
            try {
                handleTcpMessage(player, msg);
            } catch {
                quitPlayer(player);
            }
            msg.destroy();
        }
    });

    const onDisconnect = () => quitPlayer(player);
    socket.on("close", onDisconnect);
    socket.on("timeout", onDisconnect);
    socket.on("error", onDisconnect);
    socket.on("end", onDisconnect);
}).listen(PORT_TCP, () => log.info(`TCP server on port ${PORT_TCP}`));

// Heartbeat check
setInterval(() => {
    const now = Date.now();
    const expired = tcpPlayers.filter(p => p.lastHeartbeat + HEARTBEAT_TIMEOUT_SEC * 1000 < now);
    for (const p of expired) quitPlayer(p);
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

    // Rate limit
    ep.msgCount++;
    ep.lastActivity = Date.now();
    if (ep.lastActivity - ep.msgWindowStart > 1000) {
        if (ep.msgCount > UDP_RATE_LIMIT) {
            ep.killed = true;
            if (ep.id) {
                const tcp = tcpPlayers.find(p => p.id === ep!.id);
                if (tcp) quitPlayer(tcp);
            }
            return;
        }
        ep.msgCount = 0;
        ep.msgWindowStart = ep.lastActivity;
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
