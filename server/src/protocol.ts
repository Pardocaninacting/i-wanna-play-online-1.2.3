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
