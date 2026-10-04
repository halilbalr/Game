/**
 * Procedural terrain generator. Every output is a pure function of the seed and
 * world coordinates, so chunks can be generated in any order (and regenerated
 * after being unloaded) with identical results - including trees that straddle
 * chunk borders.
 */
import { SimplexNoise } from '../core/noise.js';
import { mulberry32, hash3, hashFloat } from '../core/random.js';
import { CHUNK_SIZE, WORLD_HEIGHT } from './constants.js';

const TREE_MARGIN = 3;
const REGION = CHUNK_SIZE + TREE_MARGIN * 2;

function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
function smoothstep(e0, e1, x) {
  const t = clamp((x - e0) / (e1 - e0), 0, 1);
  return t * t * (3 - 2 * t);
}
function lerp(a, b, t) { return a + (b - a) * t; }

export class TerrainGenerator {
  /**
   * @param {number} seed 32-bit world seed
   * @param {object} cfg parsed worldgen.json
   * @param {import('./registry.js').BlockRegistry} blocks
   */
  constructor(seed, cfg, blocks) {
    this.seed = seed >>> 0;
    this.cfg = cfg;
    this.blocks = blocks;
    this.sea = cfg.seaLevel;
    const n = (salt) => new SimplexNoise(hash3(this.seed, salt, 0x51ed, 0x3a7));
    this.nCont = n(1);
    this.nErosion = n(2);
    this.nHill = n(3);
    this.nDetail = n(4);
    this.nMountMask = n(5);
    this.nMount = n(6);
    this.nMountDetail = n(7);
    this.nTemp = n(8);
    this.nHumid = n(9);
    this.nCave1 = n(10);
    this.nCave2 = n(11);
    this.nCave3 = n(12);
    this.nPatch = n(13);

    const id = (name) => {
      const v = blocks.id(name);
      if (v < 0) throw new Error(`worldgen references unknown block "${name}"`);
      return v;
    };
    this.ids = {
      stone: id('stone'), bedrock: id('bedrock'), water: id('water'), lava: id('lava'),
      ice: id('ice'), sand: id('sand'), gravel: id('gravel'), clay: id('clay'), dirt: id('dirt'),
      grass: id('grass_block'), snow: id('snow_block'), cactus: id('cactus'), air: 0,
    };
    /** Biome definitions indexed by numeric biome id. */
    this.biomes = [];
    this.biomeByName = {};
    for (const [name, b] of Object.entries(cfg.biomes)) {
      const biome = {
        ...b,
        name,
        surfaceId: id(b.surface),
        fillerId: id(b.filler),
        deepFillerId: b.deepFiller ? id(b.deepFiller) : -1,
        trees: (b.trees ?? []).map((t) => ({ ...t, def: this._treeDef(t.type, id) })),
        plants: (b.plants ?? []).map((p) => ({ ...p, id: id(p.block) })),
      };
      this.biomes[b.id] = biome;
      this.biomeByName[name] = biome;
    }
    this.treeSoil = new Set(cfg.treeSoil.map(id));
    this.ores = cfg.ores.map((o) => ({ ...o, id: id(o.block) }));
    this.treeDefs = {};
    for (const type of Object.keys(cfg.trees)) this.treeDefs[type] = this._treeDef(type, id);

    // Scratch buffers for one chunk plus a margin for border-crossing trees.
    this._heights = new Int16Array(REGION * REGION);
    this._biome = new Uint8Array(REGION * REGION);
    this._temp = new Float32Array(REGION * REGION);
    this._humid = new Float32Array(REGION * REGION);
    this._mountain = new Float32Array(REGION * REGION);
    const c = cfg.caves;
    this._gx = CHUNK_SIZE / c.gridXZ + 1;
    this._gy = WORLD_HEIGHT / c.gridY + 1;
    this._caveGrid = new Float32Array(this._gx * this._gx * this._gy);
    this._col = { height: 0, mountain: 0, cont: 0, temp: 0, humid: 0, biome: 0 };
  }

  _treeDef(type, id) {
    const t = this.cfg.trees[type];
    if (!t) throw new Error(`Unknown tree type ${type}`);
    return { ...t, type, logId: id(t.log), leavesId: id(t.leaves) };
  }

  /**
   * Samples the climate and height for one column.
   * @param {number} x world x
   * @param {number} z world z
   * @param {object} [out] reused result object
   * @returns {{height:number, mountain:number, cont:number, temp:number, humid:number, biome:number}}
   */
  sampleColumn(x, z, out = this._col) {
    const t = this.cfg.terrain;
    const sea = this.sea;
    let cont = this.nCont.fbm2(x / t.continentScale, z / t.continentScale, t.continentOctaves) * t.continentGain;
    cont = clamp(cont, -1, 1);
    const base = sea + t.baseOffset + (cont > 0 ? cont * t.landRise : cont * t.oceanDepth);
    const erosion = (this.nErosion.fbm2(x / t.erosionScale, z / t.erosionScale, 2) + 1) * 0.5;
    const hills = this.nHill.fbm2(x / t.hillScale, z / t.hillScale, t.hillOctaves) * t.hillAmp * (0.3 + 0.7 * erosion);
    const detail = this.nDetail.fbm2(x / t.detailScale, z / t.detailScale, t.detailOctaves) * t.detailAmp;
    const maskN = this.nMountMask.fbm2(x / t.mountainMaskScale, z / t.mountainMaskScale, 2);
    const mask = smoothstep(t.mountainMaskLow, t.mountainMaskHigh, maskN) * smoothstep(-0.05, 0.3, cont);
    let mountain = 0;
    if (mask > 0) {
      const r = 1 - Math.abs(this.nMount.fbm2(x / t.mountainScale, z / t.mountainScale, 3));
      mountain = mask * (r * r * t.mountainAmp
        + this.nMountDetail.noise2(x / t.mountainDetailScale, z / t.mountainDetailScale) * t.mountainDetailAmp);
    }
    const height = clamp(Math.round(base + hills + detail + mountain), this.cfg.minHeight, this.cfg.maxHeight);

    const cl = this.cfg.climate;
    let temp = clamp(this.nTemp.fbm2(x / cl.temperatureScale, z / cl.temperatureScale, 3) * 1.5, -1, 1);
    if (height > cl.altitudeCoolingStart) temp -= (height - cl.altitudeCoolingStart) / cl.altitudeCooling;
    const humid = clamp(this.nHumid.fbm2(x / cl.humidityScale, z / cl.humidityScale, 3) * 1.5, -1, 1);

    out.height = height;
    out.mountain = mountain;
    out.cont = cont;
    out.temp = temp;
    out.humid = humid;
    out.biome = this._classify(height, mountain, temp, humid);
    return out;
  }

  _classify(height, mountain, temp, humid) {
    const r = this.cfg.biomeRules;
    const B = this.biomeByName;
    const above = height - this.sea;
    if (above < 0) return B.ocean.id;
    if (above <= r.beachMaxAboveSea && temp > r.coldMaxTemp) return B.beach.id;
    if (above >= r.mountainMinAboveSea && mountain > 8) return B.mountains.id;
    if (temp > r.desertMinTemp && humid < r.desertMaxHumid) return B.desert.id;
    if (temp < r.coldMaxTemp) return humid > r.taigaMinHumid ? B.taiga.id : B.tundra.id;
    if (humid > r.birchMinHumid && temp < 0.2) return B.birch_forest.id;
    if (humid > r.forestMinHumid) return B.forest.id;
    return B.plains.id;
  }

  /** Surface height of a column (y of the top terrain block before carving). */
  heightAt(x, z) { return this.sampleColumn(x, z, { }).height; }

  /** Biome definition at a column. */
  biomeAt(x, z) { return this.biomes[this.sampleColumn(x, z, { }).biome]; }

  /** Raw cave density at a grid point; negative means carved. */
  _caveDensity(x, y, z) {
    const c = this.cfg.caves;
    const n1 = this.nCave1.noise3(x / c.tunnelScaleXZ, y / c.tunnelScaleY, z / c.tunnelScaleXZ);
    const n2 = this.nCave2.noise3(x / c.tunnelScaleXZ, y / c.tunnelScaleY, z / c.tunnelScaleXZ);
    let d = n1 * n1 + n2 * n2 - c.tunnelRadius * c.tunnelRadius;
    if (y < c.cavernMaxY) {
      const n3 = this.nCave3.noise3(x / c.cavernScaleXZ, y / c.cavernScaleY, z / c.cavernScaleXZ);
      const fade = clamp((c.cavernMaxY - y) / 10, 0, 1);
      d = Math.min(d, (c.cavernThreshold - n3 * fade) * 0.1);
    }
    return d;
  }

  /**
   * Interpolated cave test for a single voxel. Matches the bulk path used by
   * {@link generate} exactly, because both interpolate the same grid samples
   * with the same arithmetic.
   */
  caveAt(x, y, z) {
    const c = this.cfg.caves;
    const gx = c.gridXZ, gy = c.gridY;
    const x0 = Math.floor(x / gx) * gx, y0 = Math.floor(y / gy) * gy, z0 = Math.floor(z / gx) * gx;
    const tx = (x - x0) / gx, ty = (y - y0) / gy, tz = (z - z0) / gx;
    const d000 = this._caveDensity(x0, y0, z0), d100 = this._caveDensity(x0 + gx, y0, z0);
    const d010 = this._caveDensity(x0, y0 + gy, z0), d110 = this._caveDensity(x0 + gx, y0 + gy, z0);
    const d001 = this._caveDensity(x0, y0, z0 + gx), d101 = this._caveDensity(x0 + gx, y0, z0 + gx);
    const d011 = this._caveDensity(x0, y0 + gy, z0 + gx), d111 = this._caveDensity(x0 + gx, y0 + gy, z0 + gx);
    return trilerp(d000, d100, d010, d110, d001, d101, d011, d111, tx, ty, tz) < 0;
  }

  /** Whether a column is carved/flooded such that nothing may be carved near its surface. */
  _carveAllowed(y, height) {
    const c = this.cfg.caves;
    if (y < c.minY) return false;
    if (height < this.sea + 1 && y > height - c.underwaterRoof) return false;
    return true;
  }

  /**
   * Fills a chunk with terrain. Lighting is not computed here.
   * @param {import('./chunk.js').Chunk} chunk
   */
  generate(chunk) {
    const { ids, sea } = this;
    const x0 = chunk.cx * CHUNK_SIZE, z0 = chunk.cz * CHUNK_SIZE;
    const col = {};
    // 1. Column data for the chunk plus margin.
    for (let rz = 0; rz < REGION; rz++) {
      for (let rx = 0; rx < REGION; rx++) {
        const s = this.sampleColumn(x0 + rx - TREE_MARGIN, z0 + rz - TREE_MARGIN, col);
        const i = rz * REGION + rx;
        this._heights[i] = s.height;
        this._biome[i] = s.biome;
        this._temp[i] = s.temp;
        this._humid[i] = s.humid;
        this._mountain[i] = s.mountain;
      }
    }
    // 2. Cave density grid.
    const cc = this.cfg.caves;
    const gxz = cc.gridXZ, gyy = cc.gridY, GX = this._gx, GY = this._gy;
    const grid = this._caveGrid;
    for (let gz = 0; gz < GX; gz++) {
      for (let gx = 0; gx < GX; gx++) {
        for (let gy = 0; gy < GY; gy++) {
          grid[(gz * GX + gx) * GY + gy] = this._caveDensity(x0 + gx * gxz, gy * gyy, z0 + gz * gxz);
        }
      }
    }
    const bedrockChances = this.cfg.bedrock.chances;
    const blocks = chunk.blocks;
    const frozenMax = this.cfg.biomeRules.frozenOceanMaxTemp;
    const floorCfg = this.cfg.oceanFloor;

    // 3. Base terrain, surface layers, caves, water.
    for (let lz = 0; lz < CHUNK_SIZE; lz++) {
      for (let lx = 0; lx < CHUNK_SIZE; lx++) {
        const ri = (lz + TREE_MARGIN) * REGION + lx + TREE_MARGIN;
        const h = this._heights[ri];
        const biome = this.biomes[this._biome[ri]];
        const wx = x0 + lx, wz = z0 + lz;
        chunk.biome[(lz << 4) | lx] = biome.id;
        const colHash = hash3(this.seed, wx, 99, wz);
        const fillerDepth = biome.depth + (colHash & 1);

        let surface = biome.surfaceId, filler = biome.fillerId;
        if (h < sea) {
          const depth = sea - h;
          const patch = this.nPatch.noise2(wx / 14, wz / 14);
          if (depth <= floorCfg.shallowDepth) surface = ids.sand;
          else if (patch > 1 - floorCfg.gravelChance * 2) surface = ids.gravel;
          else if (patch < -1 + floorCfg.clayChance * 2) surface = ids.clay;
          else surface = ids.sand;
          filler = surface === ids.clay ? ids.clay : (surface === ids.gravel ? ids.gravel : ids.sand);
        } else if (biome.stoneAbove !== undefined) {
          if (h >= biome.snowAbove) { surface = ids.snow; filler = ids.stone; }
          else if (h >= biome.stoneAbove) { surface = (colHash % 7 === 0) ? ids.gravel : ids.stone; filler = ids.stone; }
        }

        const gxi = lx / gxz, gzi = lz / gxz;
        const gx0 = Math.floor(gxi), gz0 = Math.floor(gzi);
        const tx = gxi - gx0, tz = gzi - gz0;
        const top = Math.max(h, sea);
        for (let y = 0; y <= top; y++) {
          let id;
          if (y > h) {
            id = ids.water;
            if (y === sea && this._temp[ri] < frozenMax) id = ids.ice;
          } else if (y === h) id = surface;
          else if (y > h - fillerDepth) id = filler;
          else if (biome.deepFillerId >= 0 && y > h - fillerDepth - 3) id = biome.deepFillerId;
          else id = ids.stone;

          if (y <= h && this._carveAllowed(y, h)) {
            const gyi = y / gyy;
            const gy0 = Math.floor(gyi);
            const ty = gyi - gy0;
            const b00 = (gz0 * GX + gx0) * GY + gy0;
            const b10 = (gz0 * GX + gx0 + 1) * GY + gy0;
            const b01 = ((gz0 + 1) * GX + gx0) * GY + gy0;
            const b11 = ((gz0 + 1) * GX + gx0 + 1) * GY + gy0;
            const d = trilerp(grid[b00], grid[b10], grid[b00 + 1], grid[b10 + 1],
              grid[b01], grid[b11], grid[b01 + 1], grid[b11 + 1], tx, ty, tz);
            if (d < 0) id = y <= cc.lavaLevel ? ids.lava : 0;
          }
          if (y < bedrockChances.length && hashFloat(this.seed, wx, y, wz) < bedrockChances[y]) id = ids.bedrock;
          blocks[(y << 8) | (lz << 4) | lx] = id;
        }
      }
    }

    // 4. Ores and underground pockets.
    const rand = mulberry32(hash3(this.seed, chunk.cx, 0x0de5, chunk.cz));
    for (const ore of this.ores) {
      for (let v = 0; v < ore.veins; v++) {
        let x = Math.floor(rand() * 16), z = Math.floor(rand() * 16);
        let y = ore.minY + Math.floor(rand() * (ore.maxY - ore.minY));
        for (let s = 0; s < ore.size; s++) {
          if (x >= 0 && x < 16 && z >= 0 && z < 16 && y > 0 && y < WORLD_HEIGHT) {
            const i = (y << 8) | (z << 4) | x;
            if (blocks[i] === ids.stone) blocks[i] = ore.id;
          }
          const dir = Math.floor(rand() * 6);
          if (dir === 0) x++; else if (dir === 1) x--; else if (dir === 2) z++;
          else if (dir === 3) z--; else if (dir === 4) y++; else y--;
        }
      }
    }

    // 5. Trees (including ones rooted in neighbouring chunks).
    const setClipped = (x, y, z, id, onlyAir) => {
      const lx = x - x0, lz = z - z0;
      if (lx < 0 || lx >= 16 || lz < 0 || lz >= 16 || y < 0 || y >= WORLD_HEIGHT) return;
      const i = (y << 8) | (lz << 4) | lx;
      const cur = blocks[i];
      if (onlyAir ? (cur === 0 || this.blocks.replaceable[cur] && !this.blocks.liquid[cur]) : cur !== ids.bedrock) {
        blocks[i] = id;
        chunk.meta[i] = 0;
      }
    };
    for (let rz = 0; rz < REGION; rz++) {
      for (let rx = 0; rx < REGION; rx++) {
        const wx = x0 + rx - TREE_MARGIN, wz = z0 + rz - TREE_MARGIN;
        const ri = rz * REGION + rx;
        const tree = this._treeAtColumn(wx, wz, this.biomes[this._biome[ri]], this._heights[ri]);
        if (!tree) continue;
        const trand = mulberry32(hash3(this.seed, wx, 0x7ee5, wz));
        this.placeTree(tree, wx, this._heights[ri] + 1, wz, trand, setClipped);
      }
    }

    // 6. Surface plants.
    for (let lz = 0; lz < CHUNK_SIZE; lz++) {
      for (let lx = 0; lx < CHUNK_SIZE; lx++) {
        const ri = (lz + TREE_MARGIN) * REGION + lx + TREE_MARGIN;
        const h = this._heights[ri];
        if (h < sea || h >= WORLD_HEIGHT - 4) continue;
        const biome = this.biomes[this._biome[ri]];
        if (!biome.plants.length) continue;
        const ground = blocks[(h << 8) | (lz << 4) | lx];
        if (blocks[((h + 1) << 8) | (lz << 4) | lx] !== 0) continue;
        let r = hashFloat(this.seed, x0 + lx, 0x91a7, z0 + lz);
        for (const p of biome.plants) {
          if (r < p.chance) {
            if (p.id === ids.cactus) {
              if (ground !== ids.sand) break;
              const height = 1 + (hash3(this.seed, x0 + lx, 5, z0 + lz) % 3);
              for (let k = 1; k <= height; k++) setClipped(x0 + lx, h + k, z0 + lz, p.id, true);
            } else if (ground === ids.grass || ground === biome.surfaceId || (ground === ids.sand && biome.surfaceId === ids.sand)) {
              setClipped(x0 + lx, h + 1, z0 + lz, p.id, true);
            }
            break;
          }
          r -= p.chance;
        }
      }
    }

    // 7. Tints.
    const tint = this.cfg.tint;
    for (let lz = 0; lz < CHUNK_SIZE; lz++) {
      for (let lx = 0; lx < CHUNK_SIZE; lx++) {
        const ri = (lz + TREE_MARGIN) * REGION + lx + TREE_MARGIN;
        const ci = ((lz << 4) | lx) * 3;
        const t = clamp((this._temp[ri] + 1) / 2, 0, 1), w = clamp((this._humid[ri] + 1) / 2, 0, 1);
        const biome = this.biomes[this._biome[ri]];
        const snowy = biome.surfaceId === this.blocks.id('snowy_grass');
        for (let k = 0; k < 3; k++) {
          chunk.grassTint[ci + k] = snowy ? tint.snowyGrass[k] : bilerpColor(tint.grass, t, w, k);
          chunk.foliageTint[ci + k] = bilerpColor(tint.foliage, t, w, k);
        }
      }
    }
    chunk.recountSections();
    chunk.generated = true;
  }

  /**
   * Decides whether a tree is rooted at a column. Deterministic and independent
   * of which chunk asks.
   * @returns {object|null} tree definition
   */
  _treeAtColumn(wx, wz, biome, height) {
    if (!biome.trees.length || height < this.sea) return null;
    const r = hashFloat(this.seed, wx, 0x7ee, wz);
    let acc = 0, chosen = null;
    for (const t of biome.trees) {
      acc += t.density;
      if (r < acc) { chosen = t.def; break; }
    }
    if (!chosen) return null;
    // Keep trees from touching: the root must be the lowest hash in its 3x3 neighbourhood.
    for (let dz = -1; dz <= 1; dz++) {
      for (let dx = -1; dx <= 1; dx++) {
        if ((dx || dz) && hashFloat(this.seed, wx + dx, 0x7ee, wz + dz) <= r) return null;
      }
    }
    if (!biome.surfaceId || !this.treeSoil.has(biome.surfaceId)) return null;
    if (biome.stoneAbove !== undefined && height >= biome.stoneAbove) return null;
    if (this._carveAllowed(height, height) && this.caveAt(wx, height, wz)) return null;
    return chosen;
  }

  /**
   * Places a tree. Used by world generation (chunk-clipped setter) and by sapling growth.
   * @param {object} def tree definition (from worldgen trees)
   * @param {number} x root x (first log block)
   * @param {number} y root y
   * @param {number} z root z
   * @param {() => number} rand seeded random
   * @param {(x:number,y:number,z:number,id:number,onlyAir:boolean)=>void} set
   */
  placeTree(def, x, y, z, rand, set) {
    const height = def.minHeight + Math.floor(rand() * (def.maxHeight - def.minHeight + 1));
    const top = y + height;
    if (top + 1 >= WORLD_HEIGHT) return;
    if (def.shape === 'cone') {
      // Layers narrow towards the top and alternate between radius 1 and 2 below.
      for (let ly = top; ly >= y + 2; ly--) {
        const k = top - ly;
        const r = k < 2 ? 1 : (k % 2 === 0 ? 2 : 1);
        for (let dz = -r; dz <= r; dz++) {
          for (let dx = -r; dx <= r; dx++) {
            if (Math.abs(dx) === r && Math.abs(dz) === r) continue;
            set(x + dx, ly, z + dz, def.leavesId, true);
          }
        }
      }
      set(x, top + 1, z, def.leavesId, true);
    } else {
      for (let ly = top - 3; ly <= top; ly++) {
        const rel = ly - top;
        const r = rel >= -1 ? 1 : 2;
        for (let dz = -r; dz <= r; dz++) {
          for (let dx = -r; dx <= r; dx++) {
            const corner = Math.abs(dx) === r && Math.abs(dz) === r;
            if (corner && (rel === 0 || rand() < 0.5)) continue;
            set(x + dx, ly, z + dz, def.leavesId, true);
          }
        }
      }
    }
    for (let ly = y; ly < top; ly++) set(x, ly, z, def.logId, false);
  }

  /**
   * Finds a dry-land column near the origin for the world spawn.
   * @returns {{x:number, z:number, height:number}}
   */
  findSpawnColumn() {
    const max = this.cfg.spawnSearchRadius;
    const col = {};
    for (let r = 0; r <= max; r += 8) {
      for (let a = 0; a < Math.max(1, r); a += 4) {
        const ang = (a / Math.max(1, r)) * Math.PI * 2;
        const x = Math.round(Math.cos(ang) * r), z = Math.round(Math.sin(ang) * r);
        const s = this.sampleColumn(x, z, col);
        const b = this.biomes[s.biome];
        if (s.height > this.sea + 1 && b.name !== 'mountains' && b.surfaceId !== this.ids.sand) {
          return { x, z, height: s.height };
        }
      }
    }
    return { x: 0, z: 0, height: this.heightAt(0, 0) };
  }
}

function trilerp(d000, d100, d010, d110, d001, d101, d011, d111, tx, ty, tz) {
  const a = lerp(lerp(d000, d100, tx), lerp(d010, d110, tx), ty);
  const b = lerp(lerp(d001, d101, tx), lerp(d011, d111, tx), ty);
  return lerp(a, b, tz);
}

function bilerpColor(c, t, w, k) {
  const dry = lerp(c.coldDry[k], c.hotDry[k], t);
  const wet = lerp(c.coldWet[k], c.hotWet[k], t);
  return Math.round(lerp(dry, wet, w));
}
