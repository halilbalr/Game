/**
 * Geometry for single items: a textured cube for block items, or an extruded
 * pixel sprite (one side quad per opaque/transparent pixel edge) for flat items
 * and plants - the same chunky look the held tools and dropped items need.
 * Geometries use the terrain shader's attribute layout.
 */
import * as THREE from 'three';
import { RENDER } from '../world/constants.js';
import { itemSpriteKey, TINT_ALPHA } from './textures.js';

const FACE_DEFS = [
  { n: [0, 1, 0], v: [[0, 1, 0], [0, 1, 1], [1, 1, 1], [1, 1, 0]], uv: (x, y, z) => [x, z], shade: 1.0 },
  { n: [0, -1, 0], v: [[0, 0, 0], [1, 0, 0], [1, 0, 1], [0, 0, 1]], uv: (x, y, z) => [x, z], shade: 0.5 },
  { n: [0, 0, -1], v: [[1, 0, 0], [0, 0, 0], [0, 1, 0], [1, 1, 0]], uv: (x, y) => [1 - x, 1 - y], shade: 0.8 },
  { n: [0, 0, 1], v: [[0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]], uv: (x, y) => [x, 1 - y], shade: 0.8 },
  { n: [-1, 0, 0], v: [[0, 0, 0], [0, 0, 1], [0, 1, 1], [0, 1, 0]], uv: (x, y, z) => [z, 1 - y], shade: 0.62 },
  { n: [1, 0, 0], v: [[1, 0, 1], [1, 0, 0], [1, 1, 0], [1, 1, 1]], uv: (x, y, z) => [1 - z, 1 - y], shade: 0.62 },
];

class Builder {
  constructor() { this.pos = []; this.uv = []; this.light = []; this.tint = []; this.index = []; }
  quad(verts, uvs, shade, tint) {
    const b = this.pos.length / 3;
    for (let k = 0; k < 4; k++) {
      this.pos.push(...verts[k]);
      this.uv.push(...uvs[k]);
      this.light.push(255, 0, Math.round(255 * shade), 255);
      this.tint.push(tint[0], tint[1], tint[2], 255);
    }
    this.index.push(b, b + 1, b + 2, b, b + 2, b + 3);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    g.setAttribute('light', new THREE.BufferAttribute(new Uint8Array(this.light), 4, true));
    g.setAttribute('tint', new THREE.BufferAttribute(new Uint8Array(this.tint), 4, true));
    g.setIndex(this.index);
    g.computeBoundingSphere();
    return g;
  }
}

export class ItemModels {
  /**
   * @param {import('../world/registry.js').BlockRegistry} blocks
   * @param {import('../world/registry.js').ItemRegistry} items
   * @param {object} atlas
   * @param {number[]} grassTint default RGB tint for icons and held items
   */
  constructor(blocks, items, atlas, grassTint, foliageTint) {
    this.blocks = blocks;
    this.items = items;
    this.atlas = atlas;
    this.grassTint = grassTint;
    this.foliageTint = foliageTint ?? grassTint;
    this.cache = new Map();
  }

  _tileUV(tile, u, v) {
    const per = this.atlas.tilesPerRow;
    const tx = tile % per, ty = Math.floor(tile / per);
    const e = 0.0005;
    return [(tx + Math.min(1 - e, Math.max(e, u))) / per, (ty + Math.min(1 - e, Math.max(e, v))) / per];
  }

  /** True when the item is drawn as a cube rather than a flat sprite. */
  isCube(id) {
    const item = this.items.get(id);
    if (!item?.isBlock) return false;
    const r = this.blocks.render[item.blockId];
    return r === RENDER.cube || r === RENDER.box || r === RENDER.cactus || r === RENDER.liquid;
  }

  /** Atlas tile used for an item's flat sprite. */
  spriteTile(id) {
    const item = this.items.get(id);
    if (item.isBlock) {
      const def = this.blocks.defs[item.blockId];
      if (def.stageTex) return this.atlas.tile(def.stageTex[def.stageTex.length - 1]);
      return this.blocks.tileFor(item.blockId, 0, 0);
    }
    return this.atlas.tile(itemSpriteKey(item));
  }

  /**
   * Geometry for an item, centred on the origin with unit size.
   * @param {number} id item id
   */
  geometry(id) {
    if (this.cache.has(id)) return this.cache.get(id);
    const g = this.isCube(id) ? this._cube(id) : this._extruded(id);
    this.cache.set(id, g);
    return g;
  }

  _cube(id) {
    const B = this.blocks;
    const blockId = this.items.get(id).blockId;
    const def = B.defs[blockId];
    const box = def.renderId === RENDER.box ? def.box.map((v) => v / 16) : [0, 0, 0, 1, 1, 1];
    const tint = B.foliage[blockId] ? this.foliageTint : this.grassTint;
    const b = new Builder();
    FACE_DEFS.forEach((F, f) => {
      const tile = B.tileFor(blockId, f, f === 2 ? 2 : 0);
      const verts = [], uvs = [];
      for (const v of F.v) {
        const x = v[0] ? box[3] : box[0], y = v[1] ? box[4] : box[1], z = v[2] ? box[5] : box[2];
        verts.push([x - 0.5, y - 0.5, z - 0.5]);
        const [u, vv] = F.uv(x, y, z);
        uvs.push(this._tileUV(tile, u, vv));
      }
      b.quad(verts, uvs, F.shade, tint);
    });
    return b.geometry();
  }

  _extruded(id) {
    const tile = this.spriteTile(id);
    const name = [...this.atlas.tiles.entries()].find(([, i]) => i === tile)?.[0];
    const img = this.atlas.tileImage(name);
    const N = img.size;
    const item = this.items.get(id);
    const tint = item.isBlock && this.blocks.foliage[item.blockId] ? this.foliageTint : this.grassTint;
    const t = 1 / 16;
    const b = new Builder();
    const opaque = (x, y) => x >= 0 && y >= 0 && x < N && y < N && img.alpha(x, y) > 127;
    // Front and back faces covering the whole sprite (transparent texels are discarded).
    const p = (x, y, z) => [x / N - 0.5, 0.5 - y / N, z];
    b.quad([p(0, N, t / 2), p(N, N, t / 2), p(N, 0, t / 2), p(0, 0, t / 2)],
      [this._tileUV(tile, 0, 1), this._tileUV(tile, 1, 1), this._tileUV(tile, 1, 0), this._tileUV(tile, 0, 0)], 1.0, tint);
    b.quad([p(N, N, -t / 2), p(0, N, -t / 2), p(0, 0, -t / 2), p(N, 0, -t / 2)],
      [this._tileUV(tile, 1, 1), this._tileUV(tile, 0, 1), this._tileUV(tile, 0, 0), this._tileUV(tile, 1, 0)], 0.75, tint);
    // Edge strips sample the pixel they belong to.
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        if (!opaque(x, y)) continue;
        const cu = (x + 0.5) / N, cv = (y + 0.5) / N;
        const uv = this._tileUV(tile, cu, cv);
        const uvs = [uv, uv, uv, uv];
        if (!opaque(x, y - 1)) b.quad([p(x, y, t / 2), p(x + 1, y, t / 2), p(x + 1, y, -t / 2), p(x, y, -t / 2)], uvs, 0.95, tint);
        if (!opaque(x, y + 1)) b.quad([p(x, y + 1, -t / 2), p(x + 1, y + 1, -t / 2), p(x + 1, y + 1, t / 2), p(x, y + 1, t / 2)], uvs, 0.55, tint);
        if (!opaque(x - 1, y)) b.quad([p(x, y + 1, -t / 2), p(x, y + 1, t / 2), p(x, y, t / 2), p(x, y, -t / 2)], uvs, 0.7, tint);
        if (!opaque(x + 1, y)) b.quad([p(x + 1, y + 1, t / 2), p(x + 1, y + 1, -t / 2), p(x + 1, y, -t / 2), p(x + 1, y, t / 2)], uvs, 0.7, tint);
      }
    }
    return b.geometry();
  }
}

export { TINT_ALPHA };
