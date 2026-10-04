/**
 * The voxel world: a sparse map of chunk columns with block, metadata and light
 * access in world coordinates. Generation, lighting and mesh invalidation are
 * coordinated here; persistence and entities live elsewhere.
 */
import { Chunk } from './chunk.js';
import { LightEngine } from './lighting.js';
import { CHUNK_SIZE, WORLD_HEIGHT, SECTIONS, chunkKey } from './constants.js';

export class World {
  /**
   * @param {object} opts
   * @param {import('./registry.js').BlockRegistry} opts.blocks
   * @param {{generate(chunk: Chunk): void}} opts.generator terrain generator
   */
  constructor({ blocks, generator }) {
    this.blocks = blocks;
    this.generator = generator;
    /** @type {Map<number, Chunk>} */
    this.chunks = new Map();
    this.light = new LightEngine(this, blocks);
    /** Keys of chunks with at least one dirty section. */
    this.dirtyChunks = new Set();
    /** Callbacks fired after every block change: (x, y, z, oldId, newId, oldMeta, newMeta). */
    this.listeners = [];
    this._lastChunk = null;
    this._lastKey = -1;
  }

  /** @returns {Chunk|undefined} */
  getChunk(cx, cz) {
    const key = chunkKey(cx, cz);
    if (key === this._lastKey) return this._lastChunk;
    const c = this.chunks.get(key);
    if (c) { this._lastKey = key; this._lastChunk = c; }
    return c;
  }

  /** True when the chunk containing (x, z) is generated and lit. */
  isLoaded(x, z) {
    const c = this.getChunk(Math.floor(x) >> 4, Math.floor(z) >> 4);
    return !!c && c.lit;
  }

  /** Block id at world coordinates; 0 (air) for unloaded or out-of-range cells. */
  getBlock(x, y, z) {
    if (y < 0 || y >= WORLD_HEIGHT) return 0;
    const c = this.getChunk(x >> 4, z >> 4);
    if (!c) return 0;
    return c.blocks[(y << 8) | ((z & 15) << 4) | (x & 15)];
  }

  /** Block metadata at world coordinates. */
  getMeta(x, y, z) {
    if (y < 0 || y >= WORLD_HEIGHT) return 0;
    const c = this.getChunk(x >> 4, z >> 4);
    if (!c) return 0;
    return c.meta[(y << 8) | ((z & 15) << 4) | (x & 15)];
  }

  /** Sky light level (0-15). Above the world counts as full daylight. */
  getSkyLight(x, y, z) {
    return this.light.getLight(x, y, z, true);
  }

  /** Block light level (0-15). */
  getBlockLight(x, y, z) {
    return this.light.getLight(x, y, z, false);
  }

  /**
   * Changes a block, relights, invalidates meshes and notifies listeners.
   * @returns {boolean} true if anything changed
   */
  setBlock(x, y, z, id, meta = 0) {
    if (y < 0 || y >= WORLD_HEIGHT) return false;
    const c = this.getChunk(x >> 4, z >> 4);
    if (!c || !c.generated) return false;
    const lx = x & 15, lz = z & 15;
    const i = (y << 8) | (lz << 4) | lx;
    const oldId = c.blocks[i], oldMeta = c.meta[i];
    if (oldId === id && oldMeta === meta) return false;
    c.setBlock(lx, y, lz, id, meta);
    c.modified = true;
    if (oldId !== id) c.blockEntities.delete(i);
    if (oldId !== id || this.blocks.emission[id]) this.light.onBlockChanged(x, y, z);
    this.markDirtyAt(x, y, z);
    for (const fn of this.listeners) fn(x, y, z, oldId, id, oldMeta, meta);
    return true;
  }

  /** Changes only metadata (crop stage, liquid level) and refreshes the mesh. */
  setMeta(x, y, z, meta) {
    return this.setBlock(x, y, z, this.getBlock(x, y, z), meta);
  }

  /** Block entity (furnace/chest state) at a position, if any. */
  getBlockEntity(x, y, z) {
    const c = this.getChunk(x >> 4, z >> 4);
    if (!c) return undefined;
    return c.blockEntities.get((y << 8) | ((z & 15) << 4) | (x & 15));
  }

  /** Stores a block entity and flags the chunk for saving. */
  setBlockEntity(x, y, z, data) {
    const c = this.getChunk(x >> 4, z >> 4);
    if (!c) return;
    c.blockEntities.set((y << 8) | ((z & 15) << 4) | (x & 15), data);
    c.modified = true;
  }

  /**
   * Marks every mesh section that can see the cell (including diagonal
   * neighbours used by ambient occlusion and smooth lighting) as dirty.
   */
  markDirtyAt(x, y, z) {
    const cx0 = (x - 1) >> 4, cx1 = (x + 1) >> 4;
    const cz0 = (z - 1) >> 4, cz1 = (z + 1) >> 4;
    const s0 = Math.max(0, (y - 1) >> 4), s1 = Math.min(SECTIONS - 1, (y + 1) >> 4);
    let bits = 0;
    for (let s = s0; s <= s1; s++) bits |= 1 << s;
    for (let cx = cx0; cx <= cx1; cx++) {
      for (let cz = cz0; cz <= cz1; cz++) {
        const c = this.getChunk(cx, cz);
        if (!c) continue;
        if ((c.dirtyMask & bits) !== bits) {
          c.dirtyMask |= bits;
          this.dirtyChunks.add(chunkKey(cx, cz));
        }
      }
    }
  }

  /**
   * Generates and lights a new chunk (no-op if it exists).
   * @returns {Chunk}
   */
  generateChunk(cx, cz) {
    const key = chunkKey(cx, cz);
    let c = this.chunks.get(key);
    if (c) return c;
    c = new Chunk(cx, cz);
    this.generator.generate(c);
    this._insert(key, c);
    return c;
  }

  /**
   * Inserts a chunk restored from storage. The tint/biome data is regenerated
   * from the seed, then the saved blocks replace the generated ones.
   * @param {number} cx
   * @param {number} cz
   * @param {{blocks: Uint8Array, meta: Uint8Array, entities?: Array}} data
   */
  insertSavedChunk(cx, cz, data) {
    const key = chunkKey(cx, cz);
    if (this.chunks.has(key)) return this.chunks.get(key);
    const c = new Chunk(cx, cz);
    this.generator.generate(c);
    c.blocks.set(data.blocks);
    c.meta.set(data.meta);
    c.recountSections();
    c.light.fill(0);
    c.modified = false;
    if (data.entities) for (const [idx, ent] of data.entities) c.blockEntities.set(idx, ent);
    this._insert(key, c);
    return c;
  }

  _insert(key, c) {
    this.chunks.set(key, c);
    this._lastKey = -1;
    this.light.lightChunk(c);
    c.dirtyMask = (1 << SECTIONS) - 1;
    this.dirtyChunks.add(key);
  }

  /** Drops a chunk from memory. Persisting it first is the caller's job. */
  removeChunk(cx, cz) {
    const key = chunkKey(cx, cz);
    this.chunks.delete(key);
    this.dirtyChunks.delete(key);
    this._lastKey = -1;
    this._lastChunk = null;
  }

  /** True when the chunk and all eight neighbours are lit, so its mesh is final. */
  isMeshable(cx, cz) {
    for (let dz = -1; dz <= 1; dz++) {
      for (let dx = -1; dx <= 1; dx++) {
        const c = this.getChunk(cx + dx, cz + dz);
        if (!c || !c.lit) return false;
      }
    }
    return true;
  }

  /** Highest y whose block is solid in a column, or -1. */
  topSolidY(x, z) {
    for (let y = WORLD_HEIGHT - 1; y >= 0; y--) {
      if (this.blocks.solid[this.getBlock(x, y, z)]) return y;
    }
    return -1;
  }
}

export { CHUNK_SIZE };
