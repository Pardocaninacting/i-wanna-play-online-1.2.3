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
    BULLET      = 18, // C→S: u8 count(1..8), then room + per-bullet body: u16 room, [i32 id, i32 x, i32 y, f32 direction, f32 speed] × count. Bullet sharing, gated like skins (protocol v3+).
    BULLET_NOTIFY = 19, // S→C: stringNT senderId, u8 count, then the exact room + per-bullet body from the client (u16 room, [i32 id, i32 x, i32 y, f32 direction, f32 speed] × count).
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
