/**
 * Builds vertex data for one 16x16x16 chunk section. Pure data in, typed arrays
 * out - no Three.js here, so meshing is unit-testable and could move to a
 * worker unchanged.
 *
 * Per-vertex attributes:
 *   position  float32 x3  (section-local)
 *   uv        float32 x2  (atlas)
 *   light     uint8   x4  (sky*17, block*17, ambient-occlusion * face shade, unused)
 *   tint      uint8   x4  (biome colour applied to tint-masked texels)
 */
import { WORLD_HEIGHT, RENDER, FACE } from '../world/constants.js';

const P = 18;
const SX = 1, SZ = P, SY = P * P;
const AO_CURVE = [0.42, 0.62, 0.8, 1.0];
const FACE_SHADE = [1.0, 0.5, 0.8, 0.8, 0.62, 0.62];
const CROSS_OFFSET = 0.18;

/** Corner coordinates, UV mapping and AO axes for each cube face. */
const FACES = [
  { n: [0, 1, 0], verts: [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]], axes: [0, 2], uv: (x, y, z) => [x, z] },
  { n: [0, -1, 0], verts: [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]], axes: [0, 2], uv: (x, y, z) => [x, z] },
  { n: [0, 0, -1], verts: [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0]], axes: [0, 1], uv: (x, y) => [1 - x, 1 - y] },
  { n: [0, 0, 1], verts: [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], axes: [0, 1], uv: (x, y) => [x, 1 - y] },
  { n: [-1, 0, 0], verts: [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]], axes: [2, 1], uv: (x, y, z) => [z, 1 - y] },
  { n: [1, 0, 0], verts: [[1, 0, 1], [1, 0, 0], [1, 1, 0], [1, 1, 1]], axes: [2, 1], uv: (x, y, z) => [1 - z, 1 - y] },
];
const STRIDES = [SX, SY, SZ];
for (const f of FACES) {
  f.front = f.n[0] * SX + f.n[1] * SY + f.n[2] * SZ;
  f.offsets = f.verts.map((v) => [
    (v[f.axes[0]] === 1 ? 1 : -1) * STRIDES[f.axes[0]],
    (v[f.axes[1]] === 1 ? 1 : -1) * STRIDES[f.axes[1]],
  ]);
}

/** Top-face UV rotation for oriented blocks, keyed by facing (FACE index). */
const TOP_ROTATION = {
  [FACE.NORTH]: (u, v) => [u, v],
  [FACE.SOUTH]: (u, v) => [1 - u, 1 - v],
  [FACE.WEST]: (u, v) => [v, u],
  [FACE.EAST]: (u, v) => [1 - v, 1 - u],
};

/** Growable vertex/index storage for one mesh. */
class GeometryBuffer {
  constructor(capacity = 4096) {
    this._alloc(capacity);
    this.vertexCount = 0;
    this.indexCount = 0;
  }
  _alloc(cap) {
    const old = this.pos ? this : null;
    this.capacity = cap;
    const pos = new Float32Array(cap * 3), uv = new Float32Array(cap * 2);
    const light = new Uint8Array(cap * 4), tint = new Uint8Array(cap * 4);
    const index = new Uint32Array(Math.ceil(cap * 1.5));
    if (old) {
      pos.set(old.pos.subarray(0, this.vertexCount * 3));
      uv.set(old.uv.subarray(0, this.vertexCount * 2));
      light.set(old.light.subarray(0, this.vertexCount * 4));
      tint.set(old.tint.subarray(0, this.vertexCount * 4));
      index.set(old.index.subarray(0, this.indexCount));
    }
    this.pos = pos; this.uv = uv; this.light = light; this.tint = tint; this.index = index;
  }
  reset() { this.vertexCount = 0; this.indexCount = 0; }
  reserve(n) {
    if (this.vertexCount + n > this.capacity) this._alloc(Math.max(this.capacity * 2, this.vertexCount + n));
  }
  vertex(x, y, z, u, v, sky, block, shade, tint) {
    const i = this.vertexCount++;
    this.pos[i * 3] = x; this.pos[i * 3 + 1] = y; this.pos[i * 3 + 2] = z;
    this.uv[i * 2] = u; this.uv[i * 2 + 1] = v;
    this.light[i * 4] = sky; this.light[i * 4 + 1] = block; this.light[i * 4 + 2] = shade; this.light[i * 4 + 3] = 255;
    this.tint[i * 4] = tint[0]; this.tint[i * 4 + 1] = tint[1]; this.tint[i * 4 + 2] = tint[2]; this.tint[i * 4 + 3] = 255;
  }
  /** Indexes the last four vertices as a quad; `flip` swaps the diagonal. */
  quad(flip) {
    const b = this.vertexCount - 4;
    const ix = this.index;
    let k = this.indexCount;
    if (flip) {
      ix[k++] = b + 1; ix[k++] = b + 2; ix[k++] = b + 3;
      ix[k++] = b + 1; ix[k++] = b + 3; ix[k++] = b;
    } else {
      ix[k++] = b; ix[k++] = b + 1; ix[k++] = b + 2;
      ix[k++] = b; ix[k++] = b + 2; ix[k++] = b + 3;
    }
    this.indexCount = k;
  }
  /** Trimmed copies of the data, or null when empty. */
  result() {
    if (this.vertexCount === 0) return null;
    const n = this.vertexCount;
    return {
      position: this.pos.slice(0, n * 3),
      uv: this.uv.slice(0, n * 2),
      light: this.light.slice(0, n * 4),
      tint: this.tint.slice(0, n * 4),
      index: n > 65535 ? this.index.slice(0, this.indexCount) : Uint16Array.from(this.index.subarray(0, this.indexCount)),
      vertexCount: n,
    };
  }
}

export class Mesher {
  /**
   * @param {import('../world/registry.js').BlockRegistry} blocks registry with atlas bound
   * @param {{tileSize:number, tilesPerRow:number}} atlas atlas layout
   */
  constructor(blocks, atlas) {
    this.blocks = blocks;
    this.tilesPerRow = atlas.tilesPerRow;
    this.tileUV = 1 / atlas.tilesPerRow;
    this.pb = new Uint8Array(P * P * P);
    this.pm = new Uint8Array(P * P * P);
    this.pl = new Uint8Array(P * P * P);
    this.opaqueBuf = new GeometryBuffer(16384);
    this.transBuf = new GeometryBuffer(4096);
    this._tintG = [255, 255, 255];
    this._tintF = [255, 255, 255];
    this._white = [255, 255, 255];
    this.bedrockId = blocks.id('bedrock');
    this.cactusId = blocks.id('cactus');
    this.bedIds = new Set([blocks.id('bed_foot'), blocks.id('bed_head')]);
  }

  /**
   * Builds meshes for one section. Requires the chunk's eight neighbours to be loaded.
   * @param {import('../world/world.js').World} world
   * @param {import('../world/chunk.js').Chunk} chunk
   * @param {number} sy section index
   * @returns {{opaque: object|null, translucent: object|null}}
   */
  build(world, chunk, sy) {
    this.opaqueBuf.reset();
    this.transBuf.reset();
    if (chunk.sectionCounts[sy] === 0) return { opaque: null, translucent: null };
    this._fill(world, chunk, sy);
    const B = this.blocks;
    const pb = this.pb;
    for (let y = 0; y < 16; y++) {
      for (let z = 0; z < 16; z++) {
        for (let x = 0; x < 16; x++) {
          const i = (y + 1) * SY + (z + 1) * SZ + (x + 1);
          const id = pb[i];
          if (id === 0) continue;
          const r = B.render[id];
          const ci = ((z << 4) | x) * 3;
          const tg = this._tintG, tf = this._tintF;
          tg[0] = chunk.grassTint[ci]; tg[1] = chunk.grassTint[ci + 1]; tg[2] = chunk.grassTint[ci + 2];
          tf[0] = chunk.foliageTint[ci]; tf[1] = chunk.foliageTint[ci + 1]; tf[2] = chunk.foliageTint[ci + 2];
          const tint = B.foliage[id] ? tf : tg;
          switch (r) {
            case RENDER.cube: this._cube(i, x, y, z, id, tint, null); break;
            case RENDER.box: this._cube(i, x, y, z, id, tint, B.defs[id].box); break;
            case RENDER.cactus: this._cube(i, x, y, z, id, tint, 'cactus'); break;
            case RENDER.cross: this._cross(i, x, y, z, id, tint, chunk); break;
            case RENDER.crop: this._crop(i, x, y, z, id); break;
            case RENDER.torch: this._torch(i, x, y, z, id); break;
            case RENDER.liquid: this._liquid(i, x, y, z, id); break;
            default: break;
          }
        }
      }
    }
    return { opaque: this.opaqueBuf.result(), translucent: this.transBuf.result() };
  }

  /** Copies the section plus a one-block border into padded scratch arrays. */
  _fill(world, chunk, sy) {
    const near = [];
    for (let dz = -1; dz <= 1; dz++) for (let dx = -1; dx <= 1; dx++) near.push(world.getChunk(chunk.cx + dx, chunk.cz + dz));
    const pb = this.pb, pm = this.pm, pl = this.pl;
    const y0 = sy * 16;
    for (let pz = 0; pz < P; pz++) {
      const lz = pz - 1;
      const dz = lz < 0 ? 0 : lz > 15 ? 2 : 1;
      const cz = (lz + 16) & 15;
      for (let px = 0; px < P; px++) {
        const lx = px - 1;
        const dx = lx < 0 ? 0 : lx > 15 ? 2 : 1;
        const cx = (lx + 16) & 15;
        const c = near[dz * 3 + dx];
        for (let py = 0; py < P; py++) {
          const wy = y0 + py - 1;
          const pi = py * SY + pz * SZ + px;
          if (wy < 0) { pb[pi] = this.bedrockId; pm[pi] = 0; pl[pi] = 0; continue; }
          if (wy >= WORLD_HEIGHT || !c) { pb[pi] = 0; pm[pi] = 0; pl[pi] = 0xf0; continue; }
          const ci = (wy << 8) | (cz << 4) | cx;
          pb[pi] = c.blocks[ci];
          pm[pi] = c.meta[ci];
          pl[pi] = c.light[ci];
        }
      }
    }
  }

  _uv(tile, u, v) {
    const tx = tile % this.tilesPerRow, ty = Math.floor(tile / this.tilesPerRow);
    // Tiny inset keeps nearest sampling from bleeding into neighbouring tiles.
    const e = 0.0005;
    return [(tx + Math.min(1 - e, Math.max(e, u))) * this.tileUV, (ty + Math.min(1 - e, Math.max(e, v))) * this.tileUV];
  }

  /**
   * Full cube, a sub-box (chest, farmland, bed) or the inset cactus shape.
   * @param {number[]|string|null} box [x0,y0,z0,x1,y1,z1] in 1/16, 'cactus', or null for a cube
   */
  _cube(i, x, y, z, id, tint, box) {
    const B = this.blocks, pb = this.pb, pm = this.pm, pl = this.pl;
    const opaque = B.opaque;
    const meta = pm[i];
    let x0 = 0, y0 = 0, z0 = 0, x1 = 1, y1 = 1, z1 = 1;
    let inset = 0;
    if (box === 'cactus') inset = 1 / 16;
    else if (box) { x0 = box[0] / 16; y0 = box[1] / 16; z0 = box[2] / 16; x1 = box[3] / 16; y1 = box[4] / 16; z1 = box[5] / 16; }
    const buf = B.translucent[id] ? this.transBuf : this.opaqueBuf;
    for (let f = 0; f < 6; f++) {
      const F = FACES[f];
      const ni = i + F.front;
      const nid = pb[ni];
      // Faces flush with the block boundary may be hidden by the neighbour.
      const flush = box === null
        || (box === 'cactus' ? f < 2 : (
          (f === FACE.TOP && y1 === 1) || (f === FACE.BOTTOM && y0 === 0)
          || (f === FACE.NORTH && z0 === 0) || (f === FACE.SOUTH && z1 === 1)
          || (f === FACE.WEST && x0 === 0) || (f === FACE.EAST && x1 === 1)));
      if (flush) {
        if (opaque[nid]) continue;
        if (nid === id && B.cullSame[id]) continue;
        if (box === 'cactus' && nid === id) continue;
      }
      if (this.bedIds.has(id) && this.bedIds.has(nid) && f >= 2) continue;
      const tile = B.tileFor(id, f, meta);
      const shadeF = FACE_SHADE[f];
      buf.reserve(4);
      let aoSum02 = 0, aoSum13 = 0;
      for (let k = 0; k < 4; k++) {
        const v = F.verts[k];
        let vx = v[0] ? x1 : x0, vy = v[1] ? y1 : y0, vz = v[2] ? z1 : z0;
        if (inset) {
          if (f === FACE.NORTH) vz = inset; else if (f === FACE.SOUTH) vz = 1 - inset;
          else if (f === FACE.WEST) vx = inset; else if (f === FACE.EAST) vx = 1 - inset;
        }
        const [o1, o2] = F.offsets[k];
        // Sample light from the open side; fall back to the block's own cell against a wall.
        const front = opaque[nid] ? i : ni;
        const s1 = front + o1, s2 = front + o2, c = front + o1 + o2;
        const b1 = opaque[pb[s1]], b2 = opaque[pb[s2]], bc = opaque[pb[c]];
        const ao = b1 && b2 ? 0 : 3 - (b1 + b2 + bc);
        let sky = pl[front] >> 4, blk = pl[front] & 15, n = 1;
        if (!b1) { sky += pl[s1] >> 4; blk += pl[s1] & 15; n++; }
        if (!b2) { sky += pl[s2] >> 4; blk += pl[s2] & 15; n++; }
        if (!bc && !(b1 && b2)) { sky += pl[c] >> 4; blk += pl[c] & 15; n++; }
        let [u, vv] = F.uv(vx, vy, vz);
        if (f === FACE.TOP && B.orient[id]) [u, vv] = (TOP_ROTATION[meta & 7] ?? TOP_ROTATION[FACE.NORTH])(u, vv);
        const [tu, tv] = this._uv(tile, u, vv);
        if (k === 0 || k === 2) aoSum02 += ao; else aoSum13 += ao;
        buf.vertex(x + vx, y + vy, z + vz, tu, tv, Math.round((sky / n) * 17), Math.round((blk / n) * 17),
          Math.round(255 * AO_CURVE[ao] * shadeF), tint);
      }
      buf.quad(aoSum02 < aoSum13);
    }
  }

  _flatLight(i) {
    const l = this.pl[i];
    return [(l >> 4) * 17, (l & 15) * 17];
  }

  /** Two diagonal quads, each emitted with both windings. */
  _cross(i, x, y, z, id, tint, chunk) {
    const B = this.blocks;
    const tile = B.tileFor(id, 0, 0);
    const [sky, blk] = this._flatLight(i);
    const shade = 230;
    // Deterministic jitter so flowers and grass do not sit on a perfect grid.
    const wx = chunk.cx * 16 + x, wz = chunk.cz * 16 + z;
    const h = Math.imul(wx * 73856093 ^ wz * 19349663, 0x9e3779b1) >>> 0;
    const ox = ((h & 255) / 255 - 0.5) * CROSS_OFFSET * 2, oz = (((h >> 8) & 255) / 255 - 0.5) * CROSS_OFFSET * 2;
    const buf = this.opaqueBuf;
    const quads = [
      [[0.15, 0, 0.15], [0.85, 0, 0.85], [0.85, 1, 0.85], [0.15, 1, 0.15]],
      [[0.85, 0, 0.15], [0.15, 0, 0.85], [0.15, 1, 0.85], [0.85, 1, 0.15]],
    ];
    for (const q of quads) {
      for (const order of [[0, 1, 2, 3], [1, 0, 3, 2]]) {
        buf.reserve(4);
        for (const k of order) {
          const p = q[k];
          const u = k === 0 || k === 3 ? 0 : 1, v = p[1] ? 0 : 1;
          const [tu, tv] = this._uv(tile, u, v);
          buf.vertex(x + p[0] + ox, y + p[1], z + p[2] + oz, tu, tv, sky, blk, shade, tint);
        }
        buf.quad(false);
      }
    }
  }

  /** Crops: four vertical planes in a # pattern, sunk 1/16 into the farmland. */
  _crop(i, x, y, z, id) {
    const B = this.blocks;
    const tile = B.tileFor(id, 0, this.pm[i]);
    const [sky, blk] = this._flatLight(i);
    const buf = this.opaqueBuf;
    const yo = -1 / 16;
    const planes = [];
    for (const p of [0.25, 0.75]) {
      planes.push([[p, 0, 0], [p, 0, 1], [p, 1, 1], [p, 1, 0]]);
      planes.push([[0, 0, p], [1, 0, p], [1, 1, p], [0, 1, p]]);
    }
    for (const q of planes) {
      for (const order of [[0, 1, 2, 3], [1, 0, 3, 2]]) {
        buf.reserve(4);
        for (const k of order) {
          const pnt = q[k];
          const u = k === 0 || k === 3 ? 0 : 1, v = pnt[1] ? 0 : 1;
          const [tu, tv] = this._uv(tile, u, v);
          buf.vertex(x + pnt[0], y + pnt[1] + yo, z + pnt[2], tu, tv, sky, blk, 220, this._white);
        }
        buf.quad(false);
      }
    }
  }

  /** Torch: a thin stick, leaning away from the wall when wall-mounted. */
  _torch(i, x, y, z, id) {
    const B = this.blocks;
    const tile = B.tileFor(id, 0, 0);
    const meta = this.pm[i];
    const [, blkOwn] = this._flatLight(i);
    const sky = (this.pl[i] >> 4) * 17;
    const buf = this.opaqueBuf;
    const w = 1 / 16, h = 10 / 16;
    let baseX = 0.5, baseZ = 0.5, baseY = 0, leanX = 0, leanZ = 0;
    if (meta >= 2) {
      const d = meta === FACE.NORTH || meta === FACE.WEST ? -1 : 1;
      const along = d * 0.34;
      baseY = 0.2;
      if (meta === FACE.NORTH || meta === FACE.SOUTH) { baseZ += along; leanZ = -d * 0.22; }
      else { baseX += along; leanX = -d * 0.22; }
    }
    const pos = (vx, vy, vz) => {
      const t = vy;
      return [baseX + (vx - 0.5) * 2 * w + leanX * t / h, baseY + vy, baseZ + (vz - 0.5) * 2 * w + leanZ * t / h];
    };
    for (let f = 0; f < 6; f++) {
      if (f === FACE.BOTTOM && meta < 2) continue;
      const F = FACES[f];
      buf.reserve(4);
      for (let k = 0; k < 4; k++) {
        const v = F.verts[k];
        const [px, py, pz] = pos(v[0], v[1] * h, v[2]);
        // Map onto the stick (columns 7-8) and flame (rows 6-8) of the sprite.
        let u, vv;
        if (f === FACE.TOP || f === FACE.BOTTOM) { u = (7 + v[0] * 2) / 16; vv = (6 + v[2] * 2) / 16; }
        else { u = (7 + (k === 1 || k === 2 ? 2 : 0)) / 16; vv = (6 + (1 - v[1]) * 10) / 16; }
        const [tu, tv] = this._uv(tile, u, vv);
        buf.vertex(x + px, y + py, z + pz, tu, tv, sky, Math.max(blkOwn, 14 * 17), Math.round(255 * FACE_SHADE[f]), this._white);
      }
      buf.quad(false);
    }
  }

  _liquidHeight(pi, id) {
    const pb = this.pb;
    if (pb[pi] !== id) return -1;
    if (pb[pi + SY] === id) return 1;
    const m = this.pm[pi];
    return m === 0 || m === 8 ? 8 / 9 : Math.max(1 / 9, (8 - m) / 9);
  }

  /** Corner height averaged from the four columns sharing the corner. */
  _cornerHeight(i, id, dx, dz) {
    let sum = 0, n = 0;
    for (const [ox, oz] of [[0, 0], [dx, 0], [0, dz], [dx, dz]]) {
      const pi = i + ox * SX + oz * SZ;
      if (this.pb[pi + SY] === id) return 1;
      const h = this._liquidHeight(pi, id);
      if (h >= 0) { sum += h; n++; }
    }
    return n ? sum / n : 8 / 9;
  }

  _liquid(i, x, y, z, id) {
    const B = this.blocks, pb = this.pb;
    const translucent = B.translucent[id];
    const buf = translucent ? this.transBuf : this.opaqueBuf;
    const tile = B.tileFor(id, 0, 0);
    const full = pb[i + SY] === id;
    const h00 = full ? 1 : this._cornerHeight(i, id, -1, -1);
    const h10 = full ? 1 : this._cornerHeight(i, id, 1, -1);
    const h11 = full ? 1 : this._cornerHeight(i, id, 1, 1);
    const h01 = full ? 1 : this._cornerHeight(i, id, -1, 1);
    const heightAt = (vx, vz) => (vx ? (vz ? h11 : h10) : (vz ? h01 : h00));
    for (let f = 0; f < 6; f++) {
      const F = FACES[f];
      const ni = i + F.front;
      const nid = pb[ni];
      if (nid === id) continue;
      if (f !== FACE.TOP && B.opaque[nid]) continue;
      if (f === FACE.TOP && full) continue;
      const li = f === FACE.TOP ? ni : (B.opaque[nid] ? i : ni);
      const l = this.pl[li] > this.pl[i] ? this.pl[li] : this.pl[i];
      const sky = (l >> 4) * 17, blk = Math.max(l & 15, B.emission[id]) * 17;
      const shade = Math.round(255 * FACE_SHADE[f]);
      buf.reserve(4);
      for (let k = 0; k < 4; k++) {
        const v = F.verts[k];
        const vy = v[1] ? heightAt(v[0], v[2]) : 0;
        const [u, vv] = F.uv(v[0], vy, v[2]);
        const [tu, tv] = this._uv(tile, u, vv);
        buf.vertex(x + v[0], y + vy, z + v[2], tu, tv, sky, blk, shade, this._white);
      }
      buf.quad(false);
    }
  }
}
