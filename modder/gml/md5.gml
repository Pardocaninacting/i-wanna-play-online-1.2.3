///// script @md5_begin
// Internal: initialize the streaming context. GM8 has no struct type, so the
// context lives in globals. All 32-bit words are stored as unsigned doubles
// in [0, 4294967296). Usage: @md5_begin, then any number of
// @md5_update_string / @md5_update_file, then @md5_finish_hex.
global.@md5_state[0] = 1732584193; // 0x67452301
global.@md5_state[1] = 4023233417; // 0xefcdab89
global.@md5_state[2] = 2562383102; // 0x98badcfe
global.@md5_state[3] = 271733878;  // 0x10325476
global.@md5_len = 0;    // total message bytes (exact double up to 2^53)
global.@md5_buflen = 0; // pending bytes in global.@md5_buf[0..63]

///// script @md5_transform
// Internal: mix the 64-byte block in global.@md5_buf[0..63] into
// global.@md5_state[0..3]. GM8 note: &, |, ^ and << work on the low 32 bits
// but return SIGNED results, so every bitwise expression and every sum is
// normalized with "mod 4294967296" (GM "mod" is floor-based and therefore
// also maps negative values back to unsigned). (x ^ 4294967295) is 32-bit
// NOT. Left rotation by s: low part (x << s) mod 2^32, high part
// floor(x / 2^(32-s)) (unsigned right shift); the two parts never overlap.
var a, b, c, d, t;
var m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10, m11, m12, m13, m14, m15;
// unpack the block as 16 little-endian 32-bit words
m0 = (global.@md5_buf[0] | (global.@md5_buf[1] << 8) | (global.@md5_buf[2] << 16) | (global.@md5_buf[3] << 24)) mod 4294967296;
m1 = (global.@md5_buf[4] | (global.@md5_buf[5] << 8) | (global.@md5_buf[6] << 16) | (global.@md5_buf[7] << 24)) mod 4294967296;
m2 = (global.@md5_buf[8] | (global.@md5_buf[9] << 8) | (global.@md5_buf[10] << 16) | (global.@md5_buf[11] << 24)) mod 4294967296;
m3 = (global.@md5_buf[12] | (global.@md5_buf[13] << 8) | (global.@md5_buf[14] << 16) | (global.@md5_buf[15] << 24)) mod 4294967296;
m4 = (global.@md5_buf[16] | (global.@md5_buf[17] << 8) | (global.@md5_buf[18] << 16) | (global.@md5_buf[19] << 24)) mod 4294967296;
m5 = (global.@md5_buf[20] | (global.@md5_buf[21] << 8) | (global.@md5_buf[22] << 16) | (global.@md5_buf[23] << 24)) mod 4294967296;
m6 = (global.@md5_buf[24] | (global.@md5_buf[25] << 8) | (global.@md5_buf[26] << 16) | (global.@md5_buf[27] << 24)) mod 4294967296;
m7 = (global.@md5_buf[28] | (global.@md5_buf[29] << 8) | (global.@md5_buf[30] << 16) | (global.@md5_buf[31] << 24)) mod 4294967296;
m8 = (global.@md5_buf[32] | (global.@md5_buf[33] << 8) | (global.@md5_buf[34] << 16) | (global.@md5_buf[35] << 24)) mod 4294967296;
m9 = (global.@md5_buf[36] | (global.@md5_buf[37] << 8) | (global.@md5_buf[38] << 16) | (global.@md5_buf[39] << 24)) mod 4294967296;
m10 = (global.@md5_buf[40] | (global.@md5_buf[41] << 8) | (global.@md5_buf[42] << 16) | (global.@md5_buf[43] << 24)) mod 4294967296;
m11 = (global.@md5_buf[44] | (global.@md5_buf[45] << 8) | (global.@md5_buf[46] << 16) | (global.@md5_buf[47] << 24)) mod 4294967296;
m12 = (global.@md5_buf[48] | (global.@md5_buf[49] << 8) | (global.@md5_buf[50] << 16) | (global.@md5_buf[51] << 24)) mod 4294967296;
m13 = (global.@md5_buf[52] | (global.@md5_buf[53] << 8) | (global.@md5_buf[54] << 16) | (global.@md5_buf[55] << 24)) mod 4294967296;
m14 = (global.@md5_buf[56] | (global.@md5_buf[57] << 8) | (global.@md5_buf[58] << 16) | (global.@md5_buf[59] << 24)) mod 4294967296;
m15 = (global.@md5_buf[60] | (global.@md5_buf[61] << 8) | (global.@md5_buf[62] << 16) | (global.@md5_buf[63] << 24)) mod 4294967296;
a = global.@md5_state[0];
b = global.@md5_state[1];
c = global.@md5_state[2];
d = global.@md5_state[3];
// round 1
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 3614090360 + m0) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 7) mod 4294967296) + floor(t / 33554432))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 3905402710 + m1) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 12) mod 4294967296) + floor(t / 1048576))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 606105819 + m2) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 17) mod 4294967296) + floor(t / 32768))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 3250441966 + m3) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 22) mod 4294967296) + floor(t / 1024))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 4118548399 + m4) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 7) mod 4294967296) + floor(t / 33554432))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 1200080426 + m5) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 12) mod 4294967296) + floor(t / 1048576))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 2821735955 + m6) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 17) mod 4294967296) + floor(t / 32768))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 4249261313 + m7) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 22) mod 4294967296) + floor(t / 1024))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 1770035416 + m8) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 7) mod 4294967296) + floor(t / 33554432))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 2336552879 + m9) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 12) mod 4294967296) + floor(t / 1048576))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 4294925233 + m10) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 17) mod 4294967296) + floor(t / 32768))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 2304563134 + m11) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 22) mod 4294967296) + floor(t / 1024))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 1804603682 + m12) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 7) mod 4294967296) + floor(t / 33554432))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 4254626195 + m13) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 12) mod 4294967296) + floor(t / 1048576))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 2792965006 + m14) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 17) mod 4294967296) + floor(t / 32768))) mod 4294967296;
t = (a + (((b & c) | ((b ^ 4294967295) & d)) mod 4294967296) + 1236535329 + m15) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 22) mod 4294967296) + floor(t / 1024))) mod 4294967296;
// round 2
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 4129170786 + m1) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 5) mod 4294967296) + floor(t / 134217728))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3225465664 + m6) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 9) mod 4294967296) + floor(t / 8388608))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 643717713 + m11) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 14) mod 4294967296) + floor(t / 262144))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3921069994 + m0) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 20) mod 4294967296) + floor(t / 4096))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3593408605 + m5) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 5) mod 4294967296) + floor(t / 134217728))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 38016083 + m10) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 9) mod 4294967296) + floor(t / 8388608))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3634488961 + m15) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 14) mod 4294967296) + floor(t / 262144))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3889429448 + m4) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 20) mod 4294967296) + floor(t / 4096))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 568446438 + m9) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 5) mod 4294967296) + floor(t / 134217728))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 3275163606 + m14) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 9) mod 4294967296) + floor(t / 8388608))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 4107603335 + m3) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 14) mod 4294967296) + floor(t / 262144))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 1163531501 + m8) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 20) mod 4294967296) + floor(t / 4096))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 2850285829 + m13) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 5) mod 4294967296) + floor(t / 134217728))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 4243563512 + m2) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 9) mod 4294967296) + floor(t / 8388608))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 1735328473 + m7) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 14) mod 4294967296) + floor(t / 262144))) mod 4294967296;
t = (a + (((d & b) | ((d ^ 4294967295) & c)) mod 4294967296) + 2368359562 + m12) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 20) mod 4294967296) + floor(t / 4096))) mod 4294967296;
// round 3
t = (a + (((b ^ c) ^ d) mod 4294967296) + 4294588738 + m5) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 4) mod 4294967296) + floor(t / 268435456))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 2272392833 + m8) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 11) mod 4294967296) + floor(t / 2097152))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 1839030562 + m11) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 16) mod 4294967296) + floor(t / 65536))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 4259657740 + m14) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 23) mod 4294967296) + floor(t / 512))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 2763975236 + m1) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 4) mod 4294967296) + floor(t / 268435456))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 1272893353 + m4) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 11) mod 4294967296) + floor(t / 2097152))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 4139469664 + m7) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 16) mod 4294967296) + floor(t / 65536))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3200236656 + m10) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 23) mod 4294967296) + floor(t / 512))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 681279174 + m13) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 4) mod 4294967296) + floor(t / 268435456))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3936430074 + m0) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 11) mod 4294967296) + floor(t / 2097152))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3572445317 + m3) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 16) mod 4294967296) + floor(t / 65536))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 76029189 + m6) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 23) mod 4294967296) + floor(t / 512))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3654602809 + m9) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 4) mod 4294967296) + floor(t / 268435456))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3873151461 + m12) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 11) mod 4294967296) + floor(t / 2097152))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 530742520 + m15) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 16) mod 4294967296) + floor(t / 65536))) mod 4294967296;
t = (a + (((b ^ c) ^ d) mod 4294967296) + 3299628645 + m2) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 23) mod 4294967296) + floor(t / 512))) mod 4294967296;
// round 4
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 4096336452 + m0) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 6) mod 4294967296) + floor(t / 67108864))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 1126891415 + m7) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 10) mod 4294967296) + floor(t / 4194304))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 2878612391 + m14) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 15) mod 4294967296) + floor(t / 131072))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 4237533241 + m5) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 21) mod 4294967296) + floor(t / 2048))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 1700485571 + m12) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 6) mod 4294967296) + floor(t / 67108864))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 2399980690 + m3) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 10) mod 4294967296) + floor(t / 4194304))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 4293915773 + m10) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 15) mod 4294967296) + floor(t / 131072))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 2240044497 + m1) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 21) mod 4294967296) + floor(t / 2048))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 1873313359 + m8) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 6) mod 4294967296) + floor(t / 67108864))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 4264355552 + m15) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 10) mod 4294967296) + floor(t / 4194304))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 2734768916 + m6) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 15) mod 4294967296) + floor(t / 131072))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 1309151649 + m13) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 21) mod 4294967296) + floor(t / 2048))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 4149444226 + m4) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 6) mod 4294967296) + floor(t / 67108864))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 3174756917 + m11) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 10) mod 4294967296) + floor(t / 4194304))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 718787259 + m2) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 15) mod 4294967296) + floor(t / 131072))) mod 4294967296;
t = (a + ((c ^ (b | (d ^ 4294967295))) mod 4294967296) + 3951481745 + m9) mod 4294967296;
a = d; d = c; c = b;
b = (b + (((t << 21) mod 4294967296) + floor(t / 2048))) mod 4294967296;
global.@md5_state[0] = (global.@md5_state[0] + a) mod 4294967296;
global.@md5_state[1] = (global.@md5_state[1] + b) mod 4294967296;
global.@md5_state[2] = (global.@md5_state[2] + c) mod 4294967296;
global.@md5_state[3] = (global.@md5_state[3] + d) mod 4294967296;

///// script @md5_update_string
// Internal: feed the bytes of argument0 (a raw byte string) into the stream.
var i, n;
n = string_length(argument0);
for (i = 1; i <= n; i += 1) {
    global.@md5_buf[global.@md5_buflen] = ord(string_char_at(argument0, i));
    global.@md5_buflen += 1;
    if (global.@md5_buflen == 64) {
        @md5_transform();
        global.@md5_buflen = 0;
    }
}
global.@md5_len += n;
return 1;

///// script @md5_update_byte
// Internal: feed a single byte value (0-255) into the stream. Used for the
// name/content separator in @skin_hash_dir instead of
// @md5_update_string(chr(0)): GMS strings cannot hold byte 0 (chr(0) is an
// EMPTY string there), which silently dropped the separator and produced a
// different package hash than GM8 for identical files.
global.@md5_buf[global.@md5_buflen] = argument0;
global.@md5_buflen += 1;
if (global.@md5_buflen == 64) {
    @md5_transform();
    global.@md5_buflen = 0;
}
global.@md5_len += 1;
return 1;

///// script @md5_update_file
// Internal: feed the raw bytes of file argument0 into the stream.
// Returns 1 on success, 0 when the file does not exist or cannot be read.
var f, sz, i;
if (!file_exists(argument0)) return 0;
f = file_bin_open(argument0, 0);
sz = file_bin_size(f);
for (i = 0; i < sz; i += 1) {
    global.@md5_buf[global.@md5_buflen] = file_bin_read_byte(f);
    global.@md5_buflen += 1;
    if (global.@md5_buflen == 64) {
        @md5_transform();
        global.@md5_buflen = 0;
    }
}
file_bin_close(f);
global.@md5_len += sz;
return 1;

///// script @md5_finish_hex
// Internal: pad the message, append the 64-bit little-endian bit length,
// finalize and return the digest as 32 lowercase hex chars. The scalars are
// reset afterwards; the buffer array stays allocated (reused by next begin).
var bitlen, i, k, j, wv, bt, h, out;
// append 0x80, then zeros until 56 bytes are pending in the block
global.@md5_buf[global.@md5_buflen] = 128;
global.@md5_buflen += 1;
if (global.@md5_buflen == 64) {
    @md5_transform();
    global.@md5_buflen = 0;
}
while (global.@md5_buflen != 56) {
    global.@md5_buf[global.@md5_buflen] = 0;
    global.@md5_buflen += 1;
    if (global.@md5_buflen == 64) {
        @md5_transform();
        global.@md5_buflen = 0;
    }
}
// append the message length in bits, 8 bytes little-endian
bitlen = global.@md5_len * 8;
for (i = 0; i < 8; i += 1) {
    global.@md5_buf[global.@md5_buflen] = bitlen mod 256;
    bitlen = floor(bitlen / 256);
    global.@md5_buflen += 1;
    if (global.@md5_buflen == 64) {
        @md5_transform();
        global.@md5_buflen = 0;
    }
}
// digest = the 4 state words, each as 4 little-endian bytes, hex per byte
h = "0123456789abcdef";
out = "";
for (k = 0; k < 4; k += 1) {
    wv = global.@md5_state[k];
    for (j = 0; j < 4; j += 1) {
        bt = wv mod 256;
        wv = floor(wv / 256);
        out += string_copy(h, floor(bt / 16) + 1, 1);
        out += string_copy(h, (bt mod 16) + 1, 1);
    }
}
global.@md5_len = 0;
global.@md5_buflen = 0;
return out;

///// script @md5_hex
// argument0: raw byte string. Returns its md5 as 32 lowercase hex chars.
// Pure GML on both GM8 and GMS on purpose: the GMS built-in string hash
// (md5_string_unicode) hashes UTF-16 text and would NOT match the GM8 end,
// so string hashing uses this identical implementation on both ends.
@md5_begin();
@md5_update_string(argument0);
return @md5_finish_hex();

///// script @md5_file_hex
// argument0: file path. Returns the md5 of the raw file bytes as 32
// lowercase hex chars, or "" when the file does not exist, is a directory
// or cannot be read. GMS uses the built-in md5_file on the raw file bytes
// (same semantics, much faster); GM8 streams the file through the pure
// GML implementation. Only this single-file hash has a GMS fast path.
#if STUDIO
if (!file_exists(argument0)) return "";
if (directory_exists(argument0)) return "";
return md5_file(argument0);
#endif
#if not STUDIO
if (!file_exists(argument0)) return "";
if (directory_exists(argument0)) return "";
@md5_begin();
if (!@md5_update_file(argument0)) return "";
return @md5_finish_hex();
#endif

///// script @skin_hash_dir
// argument0: directory path ending with a backslash. Returns the normalized
// package hash: md5 over (file name + byte 0 + file bytes) for every regular
// file directly inside the directory, with names sorted by byte order
// (ascending ord, compared byte by byte). Subdirectories are skipped.
// Returns "" when a file cannot be read. Pure GML on both GM8 and GMS.
// P2: when the http_dll md5_dir export is available (native, byte-identical
// semantics), it answers first; any "" falls through to the pure-GML walk.
var name, count, i, j, tmp, a, la, lb, lt, k, ka, kb, cmp, @skNHash;
#if MD5DIR
if(global.@md5DirOk){
    @skNHash = __ONLINE_md5_dir(argument0);
    if(@skNHash != ""){
        return @skNHash;
    }
}
#endif
count = 0;
name = file_find_first(argument0 + "*.*", 0);
while (name != "") {
    if (!directory_exists(argument0 + name)) {
        global.@md5_names[count] = name;
        count += 1;
    }
    name = file_find_next();
}
file_find_close();
// insertion sort by byte order (few files; manual ord compare, no reliance
// on the string < operator whose case rules differ between GM versions)
for (i = 1; i < count; i += 1) {
    tmp = global.@md5_names[i];
    j = i;
    while (j > 0) {
        a = global.@md5_names[j - 1];
        la = string_length(a);
        lb = string_length(tmp);
        if (la < lb) lt = la; else lt = lb;
        cmp = 0;
        k = 1;
        while (k <= lt) {
            ka = ord(string_char_at(a, k));
            kb = ord(string_char_at(tmp, k));
            if (ka != kb) {
                cmp = ka - kb;
                break;
            }
            k += 1;
        }
        if (cmp == 0) cmp = la - lb;
        if (cmp <= 0) break;
        global.@md5_names[j] = global.@md5_names[j - 1];
        j -= 1;
    }
    global.@md5_names[j] = tmp;
}
// stream name + byte 0 + file bytes for each file, in sorted order
@md5_begin();
for (i = 0; i < count; i += 1) {
    @md5_update_string(global.@md5_names[i]);
    @md5_update_byte(0);
    if (!@md5_update_file(argument0 + global.@md5_names[i])) return "";
}
return @md5_finish_hex();
