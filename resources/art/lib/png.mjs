/** Minimal RGBA8 PNG codec. Only Node built-ins; no timestamps or ancillary metadata. */
import { deflateSync, inflateSync } from 'node:zlib';

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, n) => {
  for (let i = 0; i < 8; i++) n = (n & 1) ? (0xedb88320 ^ (n >>> 1)) : n >>> 1;
  return n >>> 0;
});
export function crc32(data) {
  let crc = 0xffffffff;
  for (const byte of data) crc = CRC_TABLE[(crc ^ byte) & 255] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const name = Buffer.from(type, 'ascii');
  const result = Buffer.alloc(data.length + 12);
  result.writeUInt32BE(data.length, 0); name.copy(result, 4); data.copy(result, 8);
  result.writeUInt32BE(crc32(Buffer.concat([name, data])), data.length + 8);
  return result;
}
function validSize(width, height) {
  if (!Number.isSafeInteger(width) || !Number.isSafeInteger(height) || width < 1 || height < 1 || width * height > 16_777_216) throw new Error('Invalid PNG dimensions');
}
export function encodePNG({ width, height, data }) {
  validSize(width, height);
  if (!(data instanceof Uint8Array) || data.length !== width * height * 4) throw new Error('RGBA data length mismatch');
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8; ihdr[9] = 6;
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) rows.set(data.subarray(y * width * 4, (y + 1) * width * 4), y * (width * 4 + 1) + 1);
  return Buffer.concat([SIGNATURE, chunk('IHDR', ihdr), chunk('IDAT', deflateSync(rows, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}
function paeth(a, b, c) {
  const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}
export function decodePNG(input) {
  const bytes = Buffer.from(input);
  if (bytes.length < 33 || !bytes.subarray(0, 8).equals(SIGNATURE)) throw new Error('Invalid PNG signature');
  let offset = 8, width, height, ended = false, seenIDAT = false, idatEnded = false;
  const compressed = [];
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw new Error('Truncated PNG chunk');
    const length = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    if (offset + 12 + length > bytes.length) throw new Error('Truncated PNG data');
    const payload = bytes.subarray(offset + 8, offset + 8 + length);
    if (bytes.readUInt32BE(offset + 8 + length) !== crc32(bytes.subarray(offset + 4, offset + 8 + length))) throw new Error(`PNG CRC mismatch: ${type}`);
    if (offset === 8 && type !== 'IHDR') throw new Error('PNG must start with IHDR');
    if (type === 'IHDR') {
      if (width !== undefined || length !== 13) throw new Error('Invalid PNG IHDR');
      width = payload.readUInt32BE(0); height = payload.readUInt32BE(4); validSize(width, height);
      if (payload[8] !== 8 || payload[9] !== 6 || payload[10] !== 0 || payload[11] !== 0 || payload[12] !== 0) throw new Error('Only non-interlaced RGBA8 PNG is supported');
    } else if (type === 'IDAT') {
      if (idatEnded) throw new Error('PNG IDAT chunks must be consecutive');
      seenIDAT = true; compressed.push(payload);
    } else if (type === 'IEND') {
      if (length || !seenIDAT || offset + 12 !== bytes.length) throw new Error('Invalid PNG end');
      ended = true; break;
    } else {
      if (seenIDAT) idatEnded = true;
      if (type[0] === type[0].toUpperCase()) throw new Error(`Unsupported critical PNG chunk: ${type}`);
    }
    offset += length + 12;
  }
  if (!ended) throw new Error('Missing PNG IEND');
  const stride = width * 4, expected = height * (stride + 1);
  const raw = inflateSync(Buffer.concat(compressed), { maxOutputLength: expected });
  if (raw.length !== expected) throw new Error('PNG decompressed length mismatch');
  const data = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    if (filter > 4) throw new Error('Unsupported PNG filter');
    for (let x = 0; x < stride; x++) {
      const target = y * stride + x, left = x >= 4 ? data[target - 4] : 0, above = y ? data[target - stride] : 0, corner = x >= 4 && y ? data[target - stride - 4] : 0;
      const predict = [0, left, above, Math.floor((left + above) / 2), paeth(left, above, corner)][filter];
      data[target] = (raw[y * (stride + 1) + 1 + x] + predict) & 255;
    }
  }
  return { width, height, data };
}
