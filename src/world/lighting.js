/**
 * Voxel flood-fill lighting with two channels: sky light (high nibble) and
 * block light (low nibble). Light spreads to the six neighbours losing one
 * level per step plus the block's filter value; sky light at full strength
 * travels straight down without loss through fully transparent blocks.
 *
 * Initial lighting of a chunk only ever raises values, so chunks may be lit in
 * any order: each newly lit chunk pulls light in from already-lit neighbours
 * and pushes its own light out into them.
 */
import { WORLD_HEIGHT } from './constants.js';

const DIRS = [
  [1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1],
];
const DOWN = 3;

/** Growable FIFO of integer triples. */
class TripleQueue {
  constructor(capacity = 4096) {
    this.data = new Int32Array(capacity * 4);
    this.head = 0;
    this.tail = 0;
  }
  get size() { return (this.tail - this.head) >> 2; }
  push(x, y, z, v = 0) {
    if (this.tail + 4 > this.data.length) {
      if (this.head > 0) {
        this.data.copyWithin(0, this.head, this.tail);
        this.tail -= this.head;
        this.head = 0;
      }
      if (this.tail + 4 > this.data.length) {
        const bigger = new Int32Array(this.data.length * 2);
        bigger.set(this.data.subarray(0, this.tail));
        this.data = bigger;
      }
    }
    const d = this.data;
    d[this.tail] = x; d[this.tail + 1] = y; d[this.tail + 2] = z; d[this.tail + 3] = v;
    this.tail += 4;
  }
  clear() { this.head = 0; this.tail = 0; }
}

export class LightEngine {
  /**
   * @param {object} world object exposing getChunk(cx, cz) and markDirtyAt(x, y, z)
   * @param {import('./registry.js').BlockRegistry} blocks
   */
  constructor(world, blocks) {
    this.world = world;
    this.blocks = blocks;
    this.addQueue = new TripleQueue();
    this.removeQueue = new TripleQueue();
    /** When false, light changes do not invalidate meshes (used for initial lighting). */
    this.trackDirty = true;
  }

  _chunkAt(x, z) {
    const c = this.world.getChunk(x >> 4, z >> 4);
    return c && c.generated ? c : null;
  }

  /** Reads one light channel (sky = true for sky light). Unloaded cells read 0. */
  getLight(x, y, z, sky) {
    if (y < 0) return 0;
    if (y >= WORLD_HEIGHT) return sky ? 15 : 0;
    const c = this._chunkAt(x, z);
    if (!c) return 0;
    const v = c.light[(y << 8) | ((z & 15) << 4) | (x & 15)];
    return sky ? v >> 4 : v & 15;
  }

  _set(c, idx, x, y, z, sky, value) {
    const v = c.light[idx];
    c.light[idx] = sky ? (v & 15) | (value << 4) : (v & 0xf0) | value;
    if (this.trackDirty) this.world.markDirtyAt(x, y, z);
  }

  /**
   * Computes light for a freshly generated or loaded chunk and exchanges light
   * with any lit neighbours.
   * @param {import('./chunk.js').Chunk} chunk
   */
  lightChunk(chunk) {
    const { blocks } = this;
    const filter = blocks.filter, emission = blocks.emission;
    const b = chunk.blocks, light = chunk.light;
    const x0 = chunk.cx << 4, z0 = chunk.cz << 4;
    const skyQ = this.addQueue;
    skyQ.clear();
    const tops = new Int16Array(256);

    // Column pass: full sky light down to the first obstruction, filtered below it.
    for (let z = 0; z < 16; z++) {
      for (let x = 0; x < 16; x++) {
        let level = 15;
        let top = -1;
        for (let y = WORLD_HEIGHT - 1; y >= 0; y--) {
          const i = (y << 8) | (z << 4) | x;
          const f = filter[b[i]];
          if (f > 0 && top < 0) top = y + 1;
          level = f >= 15 ? 0 : Math.max(0, level - f);
          if (level === 0) break;
          if ((light[i] >> 4) < level) light[i] = (light[i] & 15) | (level << 4);
        }
        tops[(z << 4) | x] = top < 0 ? 0 : top;
      }
    }
    // Seeds: cells that may need to spread sideways.
    for (let z = 0; z < 16; z++) {
      for (let x = 0; x < 16; x++) {
        const border = x === 0 || x === 15 || z === 0 || z === 15;
        let maxNeighbourTop = WORLD_HEIGHT;
        if (!border) {
          maxNeighbourTop = Math.max(
            tops[(z << 4) | (x - 1)], tops[(z << 4) | (x + 1)],
            tops[((z - 1) << 4) | x], tops[((z + 1) << 4) | x],
          );
        }
        const top = tops[(z << 4) | x];
        const limit = Math.min(WORLD_HEIGHT - 1, Math.max(top, maxNeighbourTop));
        for (let y = 0; y <= limit; y++) {
          const i = (y << 8) | (z << 4) | x;
          if ((light[i] >> 4) > 1) skyQ.push(x0 + x, y, z0 + z);
        }
      }
    }
    // Pull light in from lit neighbours across each face.
    this._seedFromNeighbours(chunk, skyQ, true);
    this._propagate(skyQ, true);

    // Block light from emitters.
    const blockQ = this.addQueue;
    blockQ.clear();
    for (let i = 0; i < b.length; i++) {
      const e = emission[b[i]];
      if (e > 0) {
        if ((light[i] & 15) < e) light[i] = (light[i] & 0xf0) | e;
        blockQ.push(x0 + (i & 15), i >> 8, z0 + ((i >> 4) & 15));
      }
    }
    this._seedFromNeighbours(chunk, blockQ, false);
    this._propagate(blockQ, false);
    chunk.lit = true;
  }

  _seedFromNeighbours(chunk, queue, sky) {
    const sides = [
      [-1, 0, 15, -1], [1, 0, 0, -1], [0, -1, -1, 15], [0, 1, -1, 0],
    ];
    for (const [dx, dz, fx, fz] of sides) {
      const n = this.world.getChunk(chunk.cx + dx, chunk.cz + dz);
      if (!n || !n.lit) continue;
      const nx0 = n.cx << 4, nz0 = n.cz << 4;
      for (let y = 0; y < WORLD_HEIGHT; y++) {
        for (let k = 0; k < 16; k++) {
          const lx = fx >= 0 ? fx : k, lz = fz >= 0 ? fz : k;
          const v = n.light[(y << 8) | (lz << 4) | lx];
          const level = sky ? v >> 4 : v & 15;
          if (level > 1) queue.push(nx0 + lx, y, nz0 + lz);
        }
      }
    }
  }

  /** Breadth-first raise-only propagation of one channel. */
  _propagate(queue, sky) {
    const filter = this.blocks.filter;
    const d = () => queue.data;
    let cache = null, cacheCx = 0x7fffffff, cacheCz = 0x7fffffff;
    while (queue.head < queue.tail) {
      const data = d();
      const x = data[queue.head], y = data[queue.head + 1], z = data[queue.head + 2];
      queue.head += 4;
      const cx = x >> 4, cz = z >> 4;
      if (cx !== cacheCx || cz !== cacheCz) { cache = this._chunkAt(x, z); cacheCx = cx; cacheCz = cz; }
      if (!cache) continue;
      const lv = cache.light[(y << 8) | ((z & 15) << 4) | (x & 15)];
      const level = sky ? lv >> 4 : lv & 15;
      if (level <= 1) continue;
      for (let dir = 0; dir < 6; dir++) {
        const D = DIRS[dir];
        const nx = x + D[0], ny = y + D[1], nz = z + D[2];
        if (ny < 0 || ny >= WORLD_HEIGHT) continue;
        const nc = ((nx >> 4) === cx && (nz >> 4) === cz) ? cache : this._chunkAt(nx, nz);
        if (!nc) continue;
        const ni = (ny << 8) | ((nz & 15) << 4) | (nx & 15);
        const f = filter[nc.blocks[ni]];
        if (f >= 15) continue;
        let next;
        if (sky && dir === DOWN && level === 15) next = 15 - f;
        else next = level - 1 - f;
        if (next <= 0) continue;
        const cur = sky ? nc.light[ni] >> 4 : nc.light[ni] & 15;
        if (next > cur) {
          this._set(nc, ni, nx, ny, nz, sky, next);
          queue.push(nx, ny, nz);
        }
      }
    }
    queue.clear();
  }

  /**
   * Updates both channels after the block at (x, y, z) changed. Must be called
   * after the new block id is stored.
   */
  onBlockChanged(x, y, z) {
    const c = this._chunkAt(x, z);
    if (!c || !c.lit) return;
    for (const sky of [true, false]) this._relight(c, x, y, z, sky);
  }

  _relight(c, x, y, z, sky) {
    const idx = (y << 8) | ((z & 15) << 4) | (x & 15);
    const old = sky ? c.light[idx] >> 4 : c.light[idx] & 15;
    const rem = this.removeQueue;
    const add = this.addQueue;
    rem.clear();
    add.clear();
    if (old > 0) {
      this._set(c, idx, x, y, z, sky, 0);
      rem.push(x, y, z, old);
    }
    this._unpropagate(rem, add, sky);
    const id = c.blocks[idx];
    if (!sky) {
      const e = this.blocks.emission[id];
      if (e > 0) {
        this._set(c, idx, x, y, z, false, e);
        add.push(x, y, z);
      }
    } else if (this.blocks.filter[id] < 15 && y === WORLD_HEIGHT - 1) {
      this._set(c, idx, x, y, z, true, 15 - this.blocks.filter[id]);
      add.push(x, y, z);
    }
    // Neighbours re-flood into the changed cell.
    for (const D of DIRS) {
      const nx = x + D[0], ny = y + D[1], nz = z + D[2];
      if (ny < 0 || ny >= WORLD_HEIGHT) continue;
      if (this.getLight(nx, ny, nz, sky) > 0) add.push(nx, ny, nz);
    }
    this._propagate(add, sky);
  }

  _unpropagate(rem, add, sky) {
    while (rem.head < rem.tail) {
      const data = rem.data;
      const x = data[rem.head], y = data[rem.head + 1], z = data[rem.head + 2], level = data[rem.head + 3];
      rem.head += 4;
      for (let dir = 0; dir < 6; dir++) {
        const D = DIRS[dir];
        const nx = x + D[0], ny = y + D[1], nz = z + D[2];
        if (ny < 0 || ny >= WORLD_HEIGHT) continue;
        const nc = this._chunkAt(nx, nz);
        if (!nc) continue;
        const ni = (ny << 8) | ((nz & 15) << 4) | (nx & 15);
        const nl = sky ? nc.light[ni] >> 4 : nc.light[ni] & 15;
        if (nl === 0) continue;
        const fromAbove = sky && dir === DOWN && level === 15 && nl === 15;
        const isSource = !sky && this.blocks.emission[nc.blocks[ni]] >= nl;
        if ((nl < level || fromAbove) && !isSource) {
          this._set(nc, ni, nx, ny, nz, sky, 0);
          rem.push(nx, ny, nz, nl);
        } else {
          add.push(nx, ny, nz);
        }
      }
    }
    rem.clear();
  }
}
