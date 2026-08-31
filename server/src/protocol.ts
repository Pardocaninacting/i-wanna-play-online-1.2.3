export enum TcpMsg {
    CREATED     = 0,
    DESTROYED   = 1,
    HEARTBEAT   = 2, // C→S: heartbeat; S→C(2): incompatible version
    NAME        = 3,
    CHAT        = 4,
    SAVE        = 5,
    SELF_ID     = 6,
    CUSTOM_DATA = 7,
    TEAM        = 8,
    RATING      = 9,
    LIST        = 10, // C→S: request roster (no payload); S→C: u16 count, [stringNT id, stringNT name, u8 team] × count
    PING        = 11, // C→S: [i32 room?] f32 x, f32 y, u8 type;  S→C: stringNT senderId, [i32 room?] f32 x, f32 y, u8 type
                      // Legacy clients send 9 bytes (no room); current clients send 13 bytes (room first).
    SKIN        = 12, // C→S: 16-byte hash + stringNT dir-name hint (all-zero hash = no skin). Protocol v3+.
    SKIN_NOTIFY = 13, // S→C: stringNT playerId, 16-byte hash, stringNT dir hint. Only sent to protocol v3+ clients.
    SKIN_GET    = 14, // C→S: 16-byte hash. Requests the package manifest from the server skin library. Protocol v3+.
    SKIN_MANIFEST = 15, // S→C: 16-byte hash, u8 status (0=ok, 1=not found/invalid); when ok: u8 fileCount, [stringNT name, u32 size] × count.
    SKIN_FILE_REQ = 16, // C→S: 16-byte hash + stringNT file name (must be one of the manifest entries). Protocol v3+.
    SKIN_FILE   = 17, // S→C: 16-byte hash, stringNT name, u8 status; when ok: u32 totalSize, u32 offset, u16 chunkLen, chunkLen raw bytes (16 KiB chunks, in order).
    BULLET      = 18, // C→S: u8 count(1..8, OR'd with 0x80 in wire format v2), then room + per-bullet body: u16 room, [i32 id, i32 x, i32 y, f32 direction, f32 speed] × count (v2 adds f32 face [image_xscale reconciled with travel direction] + f32 image_angle per bullet). Bullet sharing, gated like skins (protocol v3+).
    BULLET_NOTIFY = 19, // S→C: stringNT senderId, u8 count (v2 flag preserved), then the exact room + per-bullet body from the client. V2 receivers parse both strides; v1 receivers drop flagged messages (count > 8).
    NOTE        = 20, // Notes/annotations (protocol v5+). Same opcode both directions (PING pattern): C→S is u8 subType, i32 room, u16 seq, then per-subtype body — 0=ICON(f32 x, f32 y, u8 iconId); 1=POLYLINE(u8 flags, u8 n(2..24), n×(f32 x, f32 y)); 2=STROKE(u8 strokeId, u8 chunk(bit6=pen-up start, bit7=final), u8 n(1..240), i32 x0, i32 y0, (n-1)×(i16 dx, i16 dy)); 3=TEXT(f32 x, f32 y, stringNT utf8, <=300 bytes); 4=DELETE(no body: drops the sender's note (by seq) from the server cache, never relayed). S→C prepends stringNT senderId to the verbatim body; sync replays set subType|0x20.
    NOTE_SYNC   = 21, // C→S: i32 room. Requests a replay of the server's cached notes for that room of the sender's game (per-note NOTE messages with subType|0x20). Protocol v5+, heavily throttled.
    SERVER_HELLO = 22, // S→C: u8 serverProtocolVersion, sent once on connect. Clients gate NOTE/NOTE_SYNC sends on it (old servers never see opcode 20/21). Old clients drop the unknown opcode via their default case.
}

export enum UdpMsg {
    INIT     = 0,
    POSITION = 1,
}

/* ── VarInt encoding (compatible with SmartBuffer.readUIntV/insertUIntV) ── */

const OFFSETS = [0x000000, 0x000080, 0x004080, 0x204080];
const BITS    = [1, 2, 3, 3];
const PREFIX  = [1, 2, 4, 0];

/** Determine how many bytes the VarInt header occupies from its first byte. */
export function varintByteLen(firstByte: number): number {
    if (firstByte & 1) return 1;
    if (firstByte & 2) return 2;
    if (firstByte & 4) return 3;
    return 4;
}

/** Read a VarInt value starting at `offset` in `buf`, given the known `byteLen`. */
export function readVarint(buf: Buffer, offset: number, byteLen: number): number {
    return (buf.readUIntLE(offset, byteLen) >> BITS[byteLen - 1]) + OFFSETS[byteLen - 1];
}

/** Prepend a VarInt length header to `payload` and return the framed buffer. */
export function frameMessage(payload: Buffer): Buffer {
    const value = payload.length;
    let len = 4;
    if (value < OFFSETS[1]) len = 1;
    else if (value < OFFSETS[2]) len = 2;
    else if (value < OFFSETS[3]) len = 3;
    const header = Buffer.alloc(len);
    header.writeUIntLE(((value - OFFSETS[len - 1]) << BITS[len - 1]) | PREFIX[len - 1], 0, len);
    return Buffer.concat([header, payload]);
}
