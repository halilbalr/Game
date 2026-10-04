/**
 * A 16 x 128 x 16 column of voxels. Block ids, metadata and packed light
 * (sky light in the high nibble, block light in the low nibble) are stored in
 * flat typed arrays indexed by {@link Chunk.index}.
 */
import { CHUNK_SIZE, WORLD_HEIGHT, CHUNK_VOLUME, SECTIONS, SECTION_HEIGHT } from './constants.js';

export class Chunk {
  /**
   * @param {number} cx chunk x coordinate (world x >> 4)
   * @param {number} cz chunk z coordinate (world z >> 4)
   */
  constructor(cx, cz) {
    this.cx = cx;
    this.cz = cz;
    this.blocks = new Uint8Array(CHUNK_VOLUME);
    this.meta = new Uint8Array(CHUNK_VOLUME);
    this.light = new Uint8Array(CHUNK_VOLUME);
    /** Grass/foliage tint per column, RGB triplets. */
    this.grassTint = new Uint8Array(CHUNK_SIZE * CHUNK_SIZE * 3);
    this.foliageTint = new Uint8Array(CHUNK_SIZE * CHUNK_SIZE * 3);
    /** Biome index per column. */
    this.biome = new Uint8Array(CHUNK_SIZE * CHUNK_SIZE);
    /** Highest y + 1 containing any non-air block per section, used to skip empty sections. */
    this.sectionCounts = new Uint16Array(SECTIONS);
    /** Bitmask of sections needing a mesh rebuild. */
    this.dirtyMask = 0;
    /** True once the block contents differ from what the generator produces. */
    this.modified = false;
    /** Lifecycle flags. */
    this.generated = false;
    this.lit = false;
    /** Block entities (furnaces, chests) keyed by local index. */
    this.blockEntities = new Map();
  }

  /** Local index of a voxel. Coordinates must be in range. */
  static index(x, y, z) {
    return (y << 8) | (z << 4) | x;
  }

  /** @returns {number} block id at local coordinates */
  getBlock(x, y, z) {
    if (y < 0 || y >= WORLD_HEIGHT) return 0;
    return this.blocks[(y << 8) | (z << 4) | x];
  }

  /**
   * Sets a block by local coordinates and keeps section counts current.
   * Lighting and mesh invalidation are the World's job.
   */
  setBlock(x, y, z, id, meta = 0) {
    const i = (y << 8) | (z << 4) | x;
    const old = this.blocks[i];
    if (old === 0 && id !== 0) this.sectionCounts[y >> 4]++;
    else if (old !== 0 && id === 0) this.sectionCounts[y >> 4]--;
    this.blocks[i] = id;
    this.meta[i] = meta;
  }

  /** Recomputes per-section non-air counts after bulk writes (generation, loading). */
  recountSections() {
    this.sectionCounts.fill(0);
    const b = this.blocks;
    for (let s = 0; s < SECTIONS; s++) {
      let n = 0;
      const start = s * SECTION_HEIGHT * 256, end = start + SECTION_HEIGHT * 256;
      for (let i = start; i < end; i++) if (b[i] !== 0) n++;
      this.sectionCounts[s] = n;
    }
  }

  /** Highest y with a non-air block in a column, or -1. */
  topBlockY(x, z) {
    for (let y = WORLD_HEIGHT - 1; y >= 0; y--) {
      if (this.blocks[(y << 8) | (z << 4) | x] !== 0) return y;
    }
    return -1;
  }

  getSky(x, y, z) { return this.light[(y << 8) | (z << 4) | x] >> 4; }
  getBlockLight(x, y, z) { return this.light[(y << 8) | (z << 4) | x] & 15; }
}
