/** World dimension constants. These are engine limits, not tunable gameplay. */
export const CHUNK_SIZE = 16;
export const CHUNK_SHIFT = 4;
export const CHUNK_MASK = 15;
export const WORLD_HEIGHT = 128;
export const SECTION_HEIGHT = 16;
export const SECTIONS = WORLD_HEIGHT / SECTION_HEIGHT;
export const CHUNK_VOLUME = CHUNK_SIZE * CHUNK_SIZE * WORLD_HEIGHT;

/** Face indices used by the mesher, raycaster and placement code. */
export const FACE = Object.freeze({ TOP: 0, BOTTOM: 1, NORTH: 2, SOUTH: 3, WEST: 4, EAST: 5 });

/** Outward normal of each face, indexed by FACE value. */
export const FACE_NORMALS = Object.freeze([
  [0, 1, 0], [0, -1, 0], [0, 0, -1], [0, 0, 1], [-1, 0, 0], [1, 0, 0],
]);

/** Render shape identifiers stored per block id. */
export const RENDER = Object.freeze({
  none: 0, cube: 1, cross: 2, liquid: 3, torch: 4, crop: 5, cactus: 6, box: 7,
});

/** Liquid identifiers stored per block id. */
export const LIQUID = Object.freeze({ none: 0, water: 1, lava: 2 });

/** Packs chunk coordinates into a single Map-friendly number. */
export function chunkKey(cx, cz) {
  return (cx + 32768) * 65536 + (cz + 32768);
}

/** Inverse of {@link chunkKey}. */
export function unpackChunkKey(key) {
  return [Math.floor(key / 65536) - 32768, (key % 65536) - 32768];
}
