/**
 * Axis-aligned bounding box collision against the voxel grid. Movement is
 * resolved one axis at a time (Y, then X, then Z) by clipping the displacement
 * against every block box in the swept region - the classic approach that
 * makes walking along walls and landing on edges behave predictably.
 */
import { RENDER, WORLD_HEIGHT } from '../world/constants.js';

/** Mutable AABB. */
export class AABB {
  constructor(minX, minY, minZ, maxX, maxY, maxZ) {
    this.minX = minX; this.minY = minY; this.minZ = minZ;
    this.maxX = maxX; this.maxY = maxY; this.maxZ = maxZ;
  }
  /** AABB of an entity whose feet are centred at (x, y, z). */
  static fromFeet(x, y, z, halfWidth, height) {
    return new AABB(x - halfWidth, y, z - halfWidth, x + halfWidth, y + height, z + halfWidth);
  }
  clone() { return new AABB(this.minX, this.minY, this.minZ, this.maxX, this.maxY, this.maxZ); }
  offset(dx, dy, dz) {
    this.minX += dx; this.maxX += dx; this.minY += dy; this.maxY += dy; this.minZ += dz; this.maxZ += dz;
    return this;
  }
  intersects(o) {
    return this.minX < o.maxX && this.maxX > o.minX && this.minY < o.maxY && this.maxY > o.minY
      && this.minZ < o.maxZ && this.maxZ > o.minZ;
  }
}

const EPS = 1e-7;

/**
 * Collision geometry provider for blocks.
 */
export class BlockColliders {
  /**
   * @param {import('../world/registry.js').BlockRegistry} blocks
   */
  constructor(blocks) {
    this.blocks = blocks;
    /** Per block id: null (no collision) or [x0,y0,z0,x1,y1,z1] in block units. */
    this.shapes = blocks.defs.map((def) => {
      if (!def || !def.solid) return null;
      if (def.renderId === RENDER.box) return def.box.map((v) => v / 16);
      if (def.renderId === RENDER.cactus) return [1 / 16, 0, 1 / 16, 15 / 16, 1, 15 / 16];
      return [0, 0, 0, 1, 1, 1];
    });
  }

  /**
   * Collects block boxes overlapping `box`. Unloaded chunks count as solid so
   * nothing falls out of the world while terrain streams in.
   * @param {{getBlock:Function, isLoaded:Function}} world
   * @param {AABB} box
   * @param {AABB[]} out reused output array
   */
  collect(world, box, out) {
    out.length = 0;
    const x0 = Math.floor(box.minX), x1 = Math.floor(box.maxX - EPS);
    const y0 = Math.max(0, Math.floor(box.minY) - 1), y1 = Math.min(WORLD_HEIGHT - 1, Math.floor(box.maxY - EPS));
    const z0 = Math.floor(box.minZ), z1 = Math.floor(box.maxZ - EPS);
    for (let x = x0; x <= x1; x++) {
      for (let z = z0; z <= z1; z++) {
        if (!world.isLoaded(x, z)) {
          out.push(new AABB(x, 0, z, x + 1, WORLD_HEIGHT + 8, z + 1));
          continue;
        }
        for (let y = y0; y <= y1; y++) {
          const s = this.shapes[world.getBlock(x, y, z)];
          if (!s) continue;
          out.push(new AABB(x + s[0], y + s[1], z + s[2], x + s[3], y + s[4], z + s[5]));
        }
      }
    }
    if (box.minY < 0) out.push(new AABB(box.minX - 1, -64, box.minZ - 1, box.maxX + 1, 0, box.maxZ + 1));
    return out;
  }

  /** True if any block box intersects `box`. */
  collides(world, box) {
    const list = this.collect(world, box, this._tmp ?? (this._tmp = []));
    for (const b of list) if (b.intersects(box)) return true;
    return false;
  }
}

function clipY(b, box, dy) {
  if (box.maxX <= b.minX || box.minX >= b.maxX || box.maxZ <= b.minZ || box.minZ >= b.maxZ) return dy;
  if (dy > 0 && box.maxY <= b.minY + EPS) { const d = b.minY - box.maxY; if (d < dy) dy = d; }
  else if (dy < 0 && box.minY >= b.maxY - EPS) { const d = b.maxY - box.minY; if (d > dy) dy = d; }
  return dy;
}
function clipX(b, box, dx) {
  if (box.maxY <= b.minY || box.minY >= b.maxY || box.maxZ <= b.minZ || box.minZ >= b.maxZ) return dx;
  if (dx > 0 && box.maxX <= b.minX + EPS) { const d = b.minX - box.maxX; if (d < dx) dx = d; }
  else if (dx < 0 && box.minX >= b.maxX - EPS) { const d = b.maxX - box.minX; if (d > dx) dx = d; }
  return dx;
}
function clipZ(b, box, dz) {
  if (box.maxY <= b.minY || box.minY >= b.maxY || box.maxX <= b.minX || box.minX >= b.maxX) return dz;
  if (dz > 0 && box.maxZ <= b.minZ + EPS) { const d = b.minZ - box.maxZ; if (d < dz) dz = d; }
  else if (dz < 0 && box.minZ >= b.maxZ - EPS) { const d = b.maxZ - box.minZ; if (d > dz) dz = d; }
  return dz;
}

/**
 * Moves a box by (dx, dy, dz) against the world.
 * @param {BlockColliders} colliders
 * @param {object} world
 * @param {AABB} box mutated in place
 * @param {number} dx
 * @param {number} dy
 * @param {number} dz
 * @param {number} [stepHeight] allow stepping up this far when on the ground
 * @param {boolean} [onGround]
 * @returns {{dx:number, dy:number, dz:number, hitX:boolean, hitY:boolean, hitZ:boolean, onGround:boolean}}
 */
export function moveBox(colliders, world, box, dx, dy, dz, stepHeight = 0, onGround = false) {
  const swept = box.clone();
  if (dx < 0) swept.minX += dx; else swept.maxX += dx;
  if (dy < 0) swept.minY += dy; else swept.maxY += dy;
  if (dz < 0) swept.minZ += dz; else swept.maxZ += dz;
  if (stepHeight > 0) swept.maxY += stepHeight;
  const list = colliders.collect(world, swept, []);
  const start = box.clone();
  const ody = dy, odx = dx, odz = dz;

  for (const b of list) dy = clipY(b, box, dy);
  box.offset(0, dy, 0);
  for (const b of list) dx = clipX(b, box, dx);
  box.offset(dx, 0, 0);
  for (const b of list) dz = clipZ(b, box, dz);
  box.offset(0, 0, dz);

  const grounded = onGround || (ody < 0 && dy !== ody);
  if (stepHeight > 0 && grounded && (dx !== odx || dz !== odz)) {
    // Try the same move raised by the step height, then settle back down.
    const alt = start.clone();
    let sy = stepHeight, sx = odx, sz = odz;
    for (const b of list) sy = clipY(b, alt, sy);
    alt.offset(0, sy, 0);
    for (const b of list) sx = clipX(b, alt, sx);
    alt.offset(sx, 0, 0);
    for (const b of list) sz = clipZ(b, alt, sz);
    alt.offset(0, 0, sz);
    let down = -sy + Math.min(0, ody);
    for (const b of list) down = clipY(b, alt, down);
    alt.offset(0, down, 0);
    if (sx * sx + sz * sz > dx * dx + dz * dz + 1e-9) {
      box.minX = alt.minX; box.minY = alt.minY; box.minZ = alt.minZ;
      box.maxX = alt.maxX; box.maxY = alt.maxY; box.maxZ = alt.maxZ;
      dx = sx; dz = sz; dy = sy + down;
    }
  }
  return {
    dx, dy, dz,
    hitX: dx !== odx, hitY: dy !== ody, hitZ: dz !== odz,
    onGround: ody < 0 && dy !== ody && dy > ody,
  };
}
