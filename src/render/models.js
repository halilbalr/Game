/**
 * Blocky mob models assembled from boxes described in data/mobs.json. Each mob
 * kind gets one procedurally painted texture sheet; each instance gets its own
 * material so brightness and hurt flashes can differ per mob.
 */
import * as THREE from 'three';
import { mulberry32, seedFromString } from '../core/random.js';
import { hex } from './textures.js';

const SHEET = 128;
// BoxGeometry face order: +x, -x, +y, -y, +z, -z.
const FACE_DIMS = [(s) => [s[2], s[1]], (s) => [s[2], s[1]], (s) => [s[0], s[2]], (s) => [s[0], s[2]], (s) => [s[0], s[1]], (s) => [s[0], s[1]]];

export class MobModels {
  /** @param {object} mobData parsed mobs.json */
  constructor(mobData) {
    this.data = mobData;
    this.kinds = new Map();
  }

  _prepare(kind) {
    if (this.kinds.has(kind)) return this.kinds.get(kind);
    const def = this.data.mobs[kind];
    const canvas = document.createElement('canvas');
    canvas.width = canvas.height = SHEET;
    const ctx = canvas.getContext('2d');
    const rand = mulberry32(seedFromString(kind));
    let cx = 0, cy = 0, rowH = 0;
    const parts = def.model.parts.map((p) => {
      const regions = FACE_DIMS.map((dim, f) => {
        const [w, h] = dim(p.size).map((v) => Math.max(1, Math.ceil(v)));
        if (cx + w > SHEET) { cx = 0; cy += rowH; rowH = 0; }
        const r = { x: cx, y: cy, w, h };
        cx += w; rowH = Math.max(rowH, h);
        this._paintFace(ctx, r, p, f, rand);
        return r;
      });
      return { ...p, regions };
    });
    const texture = new THREE.CanvasTexture(canvas);
    texture.magFilter = THREE.NearestFilter;
    texture.minFilter = THREE.NearestFilter;
    texture.generateMipmaps = false;
    texture.colorSpace = THREE.NoColorSpace;
    const geos = parts.map((p) => {
      const g = new THREE.BoxGeometry(p.size[0] / 16, p.size[1] / 16, p.size[2] / 16);
      const uv = g.attributes.uv;
      for (let f = 0; f < 6; f++) {
        const r = p.regions[f];
        for (let k = 0; k < 4; k++) {
          const i = f * 4 + k;
          const u = uv.getX(i), v = uv.getY(i);
          uv.setXY(i, (r.x + u * r.w) / SHEET, 1 - (r.y + (1 - v) * r.h) / SHEET);
        }
      }
      return g;
    });
    const entry = { def, parts, texture, geos };
    this.kinds.set(kind, entry);
    return entry;
  }

  _paintFace(ctx, r, part, face, rand) {
    const base = hex(part.color);
    const noise = part.noise ?? 0.07;
    const img = ctx.createImageData(r.w, r.h);
    const spots = part.spots ? hex(part.spots) : null;
    const spotCells = new Set();
    if (spots) {
      for (let k = 0; k < Math.max(1, Math.floor(r.w * r.h / 18)); k++) {
        const sx = Math.floor(rand() * r.w), sy = Math.floor(rand() * r.h);
        for (let dy = 0; dy < 3; dy++) for (let dx = 0; dx < 3; dx++) if (rand() < 0.7) spotCells.add(`${sx + dx},${sy + dy}`);
      }
    }
    for (let y = 0; y < r.h; y++) {
      for (let x = 0; x < r.w; x++) {
        const c = spotCells.has(`${x},${y}`) ? spots : base;
        const f = 1 + (rand() * 2 - 1) * noise;
        const i = (y * r.w + x) * 4;
        img.data[i] = c[0] * f; img.data[i + 1] = c[1] * f; img.data[i + 2] = c[2] * f; img.data[i + 3] = 255;
      }
    }
    if (part.face && face === 5) {
      const fd = this.data.faces[part.face];
      const fh = fd.rows.length, fw = fd.rows[0].length;
      const ox = Math.floor((r.w - fw) / 2), oy = Math.floor((r.h - fh) / 2);
      for (let y = 0; y < fh; y++) {
        for (let x = 0; x < fw; x++) {
          const ch = fd.rows[y][x];
          if (ch === '.') continue;
          const c = hex(fd.palette[ch]);
          const px = ox + x, py = oy + y;
          if (px < 0 || py < 0 || px >= r.w || py >= r.h) continue;
          const i = (py * r.w + px) * 4;
          img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2];
        }
      }
    }
    ctx.putImageData(img, r.x, r.y);
  }

  /**
   * Creates a model instance.
   * @returns {{root: THREE.Group, body: THREE.Group, material: THREE.MeshBasicMaterial, parts: object[], kind: string}}
   */
  create(kind) {
    const k = this._prepare(kind);
    const material = new THREE.MeshBasicMaterial({ map: k.texture });
    const root = new THREE.Group();
    const body = new THREE.Group();
    root.add(body);
    const parts = [];
    let headPivot = null;
    const pivots = [];
    k.parts.forEach((p, i) => {
      const mesh = new THREE.Mesh(k.geos[i], material);
      const pivot = new THREE.Group();
      const [px, py, pz] = p.pos.map((v) => v / 16);
      const halfH = p.size[1] / 32;
      if (p.pivotTop) {
        pivot.position.set(px, py + halfH, pz);
        mesh.position.set(0, -halfH, 0);
      } else {
        pivot.position.set(px, py, pz);
      }
      if (p.rest) pivot.rotation.set(...p.rest.map((d) => (d * Math.PI) / 180));
      pivot.add(mesh);
      pivots.push(pivot);
      parts.push({ def: p, pivot, rest: pivot.rotation.clone() });
      if (p.head) headPivot = pivot;
    });
    // Attach horns/beaks to the head so they turn with it.
    k.parts.forEach((p, i) => {
      if (p.attach === 'head' && headPivot) {
        const pv = pivots[i];
        pv.position.sub(headPivot.position);
        headPivot.add(pv);
      } else {
        body.add(pivots[i]);
      }
    });
    return { root, body, material, parts, head: headPivot, kind };
  }
}
