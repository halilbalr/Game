/**
 * Deterministic pseudo-random helpers. Everything in world generation must be
 * reproducible from the world seed, so nothing here touches Math.random.
 */

/**
 * Hashes an arbitrary string (e.g. a player-typed seed) to a 32-bit unsigned int.
 * Numeric strings hash to themselves so "12345" behaves like the number 12345.
 * @param {string|number} input
 * @returns {number}
 */
export function seedFromString(input) {
  const str = String(input ?? '').trim();
  if (/^-?\d+$/.test(str)) return Number(BigInt.asUintN(32, BigInt(str)));
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  h = Math.imul(h ^ (h >>> 16), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return (h ^ (h >>> 16)) >>> 0;
}

/**
 * Mulberry32 generator.
 * @param {number} seed 32-bit seed
 * @returns {() => number} function returning floats in [0, 1)
 */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Integer hash of up to three coordinates plus a seed, returning a uint32.
 * Used for per-column decisions (tree placement, flowers) that must not depend
 * on generation order.
 * @param {number} seed
 * @param {number} x
 * @param {number} y
 * @param {number} z
 * @returns {number}
 */
export function hash3(seed, x, y, z) {
  let h = seed >>> 0;
  h = Math.imul(h ^ (x | 0), 0x27d4eb2d);
  h = (h ^ (h >>> 15)) >>> 0;
  h = Math.imul(h ^ (y | 0), 0x85ebca6b);
  h = (h ^ (h >>> 13)) >>> 0;
  h = Math.imul(h ^ (z | 0), 0xc2b2ae35);
  h = (h ^ (h >>> 16)) >>> 0;
  h = Math.imul(h, 0x9e3779b1);
  return (h ^ (h >>> 15)) >>> 0;
}

/**
 * Same as {@link hash3} but scaled to a float in [0, 1).
 * @returns {number}
 */
export function hashFloat(seed, x, y, z) {
  return hash3(seed, x, y, z) / 4294967296;
}
