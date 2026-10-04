/**
 * Inventory icons drawn on 2D canvases from the texture atlas: isometric cubes
 * for blocks, flat pixel sprites for items. Cached as data URLs.
 */
import { RENDER } from '../world/constants.js';
import { TINT_ALPHA } from '../render/textures.js';

const SIZE = 64;

export class IconRenderer {
  /**
   * @param {object} deps
   * @param {import('../world/registry.js').BlockRegistry} deps.blocks
   * @param {import('../world/registry.js').ItemRegistry} deps.items
   * @param {object} deps.atlas
   * @param {import('../render/itemmodel.js').ItemModels} deps.itemModels
   * @param {number[]} deps.grassTint
   * @param {number[]} deps.foliageTint
   */
  constructor({ blocks, items, atlas, itemModels, grassTint, foliageTint }) {
    this.blocks = blocks;
    this.items = items;
    this.atlas = atlas;
    this.itemModels = itemModels;
    this.grassTint = grassTint;
    this.foliageTint = foliageTint;
    this.cache = new Map();
    this.tileCanvases = new Map();
  }

  _tileCanvas(tile, tint) {
    const key = `${tile}:${tint ? tint.join(',') : ''}`;
    if (this.tileCanvases.has(key)) return this.tileCanvases.get(key);
    const name = this._tileName(tile);
    const img = this.atlas.tileImage(name);
    const c = document.createElement('canvas');
    c.width = c.height = img.size;
    const ctx = c.getContext('2d');
    const data = ctx.createImageData(img.size, img.size);
    data.data.set(img.data);
    for (let i = 0; i < data.data.length; i += 4) {
      if (data.data[i + 3] === TINT_ALPHA) {
        const t = tint ?? this.grassTint;
        data.data[i] = (data.data[i] * t[0]) / 255;
        data.data[i + 1] = (data.data[i + 1] * t[1]) / 255;
        data.data[i + 2] = (data.data[i + 2] * t[2]) / 255;
        data.data[i + 3] = 255;
      }
    }
    ctx.putImageData(data, 0, 0);
    this.tileCanvases.set(key, c);
    return c;
  }

  _tileName(tile) {
    if (!this._names) {
      this._names = new Map();
      for (const [n, i] of this.atlas.tiles) this._names.set(i, n);
    }
    return this._names.get(tile);
  }

  /** Data URL of the icon for an item id. */
  url(id) {
    if (this.cache.has(id)) return this.cache.get(id);
    const c = document.createElement('canvas');
    c.width = c.height = SIZE;
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    const item = this.items.get(id);
    if (!item) return '';
    if (this.itemModels.isCube(id) && this.blocks.render[item.blockId] !== RENDER.liquid) this._cube(ctx, item.blockId);
    else {
      const tile = this.itemModels.spriteTile(id);
      const tint = item.isBlock && this.blocks.foliage[item.blockId] ? this.foliageTint : this.grassTint;
      ctx.drawImage(this._tileCanvas(tile, tint), 4, 4, SIZE - 8, SIZE - 8);
    }
    const url = c.toDataURL();
    this.cache.set(id, url);
    return url;
  }

  _cube(ctx, blockId) {
    const B = this.blocks;
    const tint = B.foliage[blockId] ? this.foliageTint : this.grassTint;
    const def = B.defs[blockId];
    const h = def.renderId === RENDER.box ? (def.box[4] - def.box[1]) / 16 : 1;
    const S = SIZE / 64;
    const top = { x: 32 * S, y: 4 * S }, right = { x: 60 * S, y: 18 * S }, left = { x: 4 * S, y: 18 * S }, mid = { x: 32 * S, y: 32 * S };
    const H = 28 * S * h;
    const drop = 28 * S * (1 - h);
    // Each face is drawn on its own layer so the shading overlay only touches that face.
    const layer = document.createElement('canvas');
    layer.width = layer.height = SIZE;
    const lctx = layer.getContext('2d');
    lctx.imageSmoothingEnabled = false;
    const face = (tile, ax, ay, ux, uy, vx, vy, shade) => {
      lctx.setTransform(1, 0, 0, 1, 0, 0);
      lctx.globalCompositeOperation = 'source-over';
      lctx.clearRect(0, 0, SIZE, SIZE);
      lctx.setTransform(ux / 16, uy / 16, vx / 16, vy / 16, ax, ay);
      lctx.drawImage(this._tileCanvas(tile, tint), 0, 0);
      if (shade > 0) {
        lctx.globalCompositeOperation = 'source-atop';
        lctx.fillStyle = `rgba(0,0,0,${shade})`;
        lctx.fillRect(0, 0, 16, 16);
      }
      ctx.drawImage(layer, 0, 0);
    };
    const frontMeta = B.orient[blockId] ? 3 : 0;
    face(B.tileFor(blockId, 0, frontMeta), top.x, top.y + drop, right.x - top.x, right.y - top.y, left.x - top.x, left.y - top.y, 0);
    face(B.tileFor(blockId, 3, frontMeta), left.x, left.y + drop, mid.x - left.x, mid.y - left.y, 0, H, 0.2);
    face(B.tileFor(blockId, 5, frontMeta), mid.x, mid.y + drop, right.x - mid.x, right.y - mid.y, 0, H, 0.4);
  }
}
