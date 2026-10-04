/**
 * Voxel ray traversal (Amanatides & Woo) used to find the targeted block.
 */
import { RENDER } from '../world/constants.js';

const FACE_FROM_STEP = {
  x: [5, 4], // stepping +x enters through the west face of the next block -> hit face = WEST(4); -x -> EAST(5)
  y: [1, 0],
  z: [3, 2],
};

/**
 * Casts a ray through the voxel grid.
 * @param {object} world exposes getBlock(x,y,z) and getMeta
 * @param {(id:number, x:number, y:number, z:number) => boolean} isTarget whether a block stops the ray
 * @param {{x:number,y:number,z:number}} o origin
 * @param {{x:number,y:number,z:number}} d direction (normalised)
 * @param {number} maxDist
 * @param {(id:number) => number[]} [bounds] optional per-block hit box for non-full blocks
 * @returns {{x:number,y:number,z:number,id:number,face:number,dist:number,normal:number[]}|null}
 */
export function raycastBlocks(world, isTarget, o, d, maxDist, bounds) {
  let x = Math.floor(o.x), y = Math.floor(o.y), z = Math.floor(o.z);
  const stepX = d.x > 0 ? 1 : -1, stepY = d.y > 0 ? 1 : -1, stepZ = d.z > 0 ? 1 : -1;
  const tDeltaX = d.x !== 0 ? Math.abs(1 / d.x) : Infinity;
  const tDeltaY = d.y !== 0 ? Math.abs(1 / d.y) : Infinity;
  const tDeltaZ = d.z !== 0 ? Math.abs(1 / d.z) : Infinity;
  let tMaxX = d.x !== 0 ? ((stepX > 0 ? x + 1 - o.x : o.x - x) * tDeltaX) : Infinity;
  let tMaxY = d.y !== 0 ? ((stepY > 0 ? y + 1 - o.y : o.y - y) * tDeltaY) : Infinity;
  let tMaxZ = d.z !== 0 ? ((stepZ > 0 ? z + 1 - o.z : o.z - z) * tDeltaZ) : Infinity;
  let face = -1, t = 0;
  for (let i = 0; i < 256 && t <= maxDist; i++) {
    const id = world.getBlock(x, y, z);
    if (id !== 0 && isTarget(id, x, y, z)) {
      const b = bounds ? bounds(id) : null;
      if (!b || (b[0] === 0 && b[1] === 0 && b[2] === 0 && b[3] === 1 && b[4] === 1 && b[5] === 1)) {
        if (face >= 0 || i === 0) return hit(x, y, z, id, face < 0 ? 0 : face, t);
      } else {
        const r = rayBox(o, d, x + b[0], y + b[1], z + b[2], x + b[3], y + b[4], z + b[5]);
        if (r && r.t <= maxDist) return hit(x, y, z, id, r.face, r.t);
      }
    }
    if (tMaxX < tMaxY && tMaxX < tMaxZ) {
      x += stepX; t = tMaxX; tMaxX += tDeltaX; face = FACE_FROM_STEP.x[stepX > 0 ? 1 : 0];
    } else if (tMaxY < tMaxZ) {
      y += stepY; t = tMaxY; tMaxY += tDeltaY; face = FACE_FROM_STEP.y[stepY > 0 ? 0 : 1];
    } else {
      z += stepZ; t = tMaxZ; tMaxZ += tDeltaZ; face = FACE_FROM_STEP.z[stepZ > 0 ? 1 : 0];
    }
  }
  return null;
}

const NORMALS = [[0, 1, 0], [0, -1, 0], [0, 0, -1], [0, 0, 1], [-1, 0, 0], [1, 0, 0]];

function hit(x, y, z, id, face, dist) {
  return { x, y, z, id, face, dist, normal: NORMALS[face] };
}

/** Slab test returning entry distance and the face that was hit. */
export function rayBox(o, d, x0, y0, z0, x1, y1, z1) {
  let tmin = -Infinity, tmax = Infinity, face = -1;
  const axes = [[o.x, d.x, x0, x1, 4, 5], [o.y, d.y, y0, y1, 1, 0], [o.z, d.z, z0, z1, 2, 3]];
  for (const [oo, dd, lo, hi, faceLo, faceHi] of axes) {
    if (Math.abs(dd) < 1e-12) {
      if (oo < lo || oo > hi) return null;
      continue;
    }
    let t1 = (lo - oo) / dd, t2 = (hi - oo) / dd;
    let f1 = faceLo, f2 = faceHi;
    if (t1 > t2) { [t1, t2] = [t2, t1]; [f1, f2] = [f2, f1]; }
    if (t1 > tmin) { tmin = t1; face = f1; }
    if (t2 < tmax) tmax = t2;
    if (tmin > tmax) return null;
  }
  if (tmax < 0) return null;
  return { t: Math.max(0, tmin), face: face < 0 ? 0 : face };
}

/** Default hit box lookup for non-cube blocks. */
export function makeBoundsLookup(blocks) {
  return (id) => {
    const def = blocks.defs[id];
    switch (blocks.render[id]) {
      case RENDER.box: return def.box.map((v) => v / 16);
      case RENDER.cross: case RENDER.crop: return [0.15, 0, 0.15, 0.85, 0.8, 0.85];
      case RENDER.torch: return [0.38, 0, 0.38, 0.62, 0.65, 0.62];
      case RENDER.cactus: return [1 / 16, 0, 1 / 16, 15 / 16, 1, 15 / 16];
      default: return null;
    }
  };
}
