/**
 * Run-length encoding for chunk arrays. Chunks are mostly long runs of stone
 * and air, so this typically shrinks 32 KiB to a few hundred bytes.
 * Format: repeated (runLength: 1..255, value) byte pairs.
 */

/** @param {Uint8Array} data @returns {Uint8Array} */
export function rleEncode(data) {
  const out = new Uint8Array(data.length * 2);
  let o = 0;
  let i = 0;
  while (i < data.length) {
    const v = data[i];
    let run = 1;
    while (run < 255 && i + run < data.length && data[i + run] === v) run++;
    out[o++] = run;
    out[o++] = v;
    i += run;
  }
  return out.slice(0, o);
}

/**
 * @param {Uint8Array} encoded
 * @param {number} length expected decoded length
 * @returns {Uint8Array}
 */
export function rleDecode(encoded, length) {
  const out = new Uint8Array(length);
  let o = 0;
  for (let i = 0; i + 1 < encoded.length; i += 2) {
    const run = encoded[i], v = encoded[i + 1];
    if (o + run > length) throw new Error('RLE data overflows target length');
    out.fill(v, o, o + run);
    o += run;
  }
  if (o !== length) throw new Error(`RLE decoded ${o} bytes, expected ${length}`);
  return out;
}
