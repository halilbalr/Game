/**
 * Flowing water and lava. Liquid metadata: 0 = source, 1..N = flowing level
 * (higher is shallower), 8 = falling column. Updates are scheduled ticks, so a
 * liquid only moves after something next to it changed - static oceans cost
 * nothing.
 */
import { LIQUID, WORLD_HEIGHT } from './constants.js';

const FALLING = 8;
const HORIZONTAL = [[1, 0], [-1, 0], [0, 1], [0, -1]];

export class LiquidSystem {
  /**
   * @param {import('./world.js').World} world
   * @param {import('./registry.js').BlockRegistry} blocks
   * @param {{water: {tickDelay: number, spread: number}, lava: {tickDelay: number, spread: number}, maxUpdatesPerTick: number}} cfg
   */
  constructor(world, blocks, cfg) {
    this.world = world;
    this.blocks = blocks;
    this.cfg = cfg;
    this.ids = {
      water: blocks.id('water'), lava: blocks.id('lava'),
      obsidian: blocks.id('obsidian'), cobblestone: blocks.id('cobblestone'), stone: blocks.id('stone'),
    };
    /** @type {Map<number, Map<string, number[]>>} due tick -> positions */
    this.pending = new Map();
    this.tick = 0;
    world.listeners.push((x, y, z) => this.onBlockChanged(x, y, z));
  }

  _typeCfg(type) { return type === LIQUID.lava ? this.cfg.lava : this.cfg.water; }

  /** Schedules an update for the cell if it holds a liquid. */
  scheduleIfLiquid(x, y, z) {
    if (y < 0 || y >= WORLD_HEIGHT) return;
    const type = this.blocks.liquid[this.world.getBlock(x, y, z)];
    if (type) this.schedule(x, y, z, this._typeCfg(type).tickDelay);
  }

  /** Schedules an update for (x, y, z) after `delay` ticks. */
  schedule(x, y, z, delay) {
    const due = this.tick + delay;
    let bucket = this.pending.get(due);
    if (!bucket) { bucket = new Map(); this.pending.set(due, bucket); }
    const key = `${x},${y},${z}`;
    if (!bucket.has(key)) bucket.set(key, [x, y, z]);
  }

  /** World listener: wakes liquids around any change. */
  onBlockChanged(x, y, z) {
    this.scheduleIfLiquid(x, y, z);
    this.scheduleIfLiquid(x + 1, y, z);
    this.scheduleIfLiquid(x - 1, y, z);
    this.scheduleIfLiquid(x, y + 1, z);
    this.scheduleIfLiquid(x, y - 1, z);
    this.scheduleIfLiquid(x, y, z + 1);
    this.scheduleIfLiquid(x, y, z - 1);
  }

  /** Advances one game tick and processes due updates. */
  update() {
    this.tick++;
    const bucket = this.pending.get(this.tick);
    if (!bucket) return;
    this.pending.delete(this.tick);
    let n = 0;
    for (const [x, y, z] of bucket.values()) {
      if (n++ >= this.cfg.maxUpdatesPerTick) {
        this.schedule(x, y, z, 1);
        continue;
      }
      this._updateCell(x, y, z);
    }
  }

  /** Number of scheduled updates (for tests and debug overlay). */
  get pendingCount() {
    let n = 0;
    for (const b of this.pending.values()) n += b.size;
    return n;
  }

  _level(meta) { return meta === 0 || meta === FALLING ? 0 : meta; }

  _updateCell(x, y, z) {
    const w = this.world, B = this.blocks;
    if (!w.isLoaded(x, z)) return;
    const id = w.getBlock(x, y, z);
    const type = B.liquid[id];
    if (!type) return;
    let meta = w.getMeta(x, y, z);
    const tc = this._typeCfg(type);

    // Lava touching water hardens.
    if (type === LIQUID.lava && this._touchesWater(x, y, z)) {
      w.setBlock(x, y, z, meta === 0 ? this.ids.obsidian : this.ids.cobblestone);
      return;
    }

    if (meta !== 0) {
      let target = -1;
      if (B.liquid[w.getBlock(x, y + 1, z)] === type) {
        target = FALLING;
      } else {
        let min = 99, sources = 0;
        for (const [dx, dz] of HORIZONTAL) {
          const nid = w.getBlock(x + dx, y, z + dz);
          if (B.liquid[nid] !== type) continue;
          const nm = w.getMeta(x + dx, y, z + dz);
          if (nm === 0) sources++;
          min = Math.min(min, this._level(nm));
        }
        const belowId = w.getBlock(x, y - 1, z);
        const belowSupports = B.solid[belowId] || (B.liquid[belowId] === type && w.getMeta(x, y - 1, z) === 0);
        if (type === LIQUID.water && sources >= 2 && belowSupports) target = 0;
        else if (min + 1 <= tc.spread) target = min + 1;
      }
      if (target < 0) {
        w.setBlock(x, y, z, 0);
        return;
      }
      if (target !== meta) {
        w.setBlock(x, y, z, id, target);
        meta = target;
      }
    }

    const canFall = y > 0 && this._canFlowInto(x, y - 1, z, type, FALLING);
    if (canFall) this._flowInto(x, y - 1, z, id, type, FALLING);
    // Flowing liquid pours downwards instead of spreading; sources always spread.
    const belowSame = B.liquid[w.getBlock(x, y - 1, z)] === type;
    if (meta !== 0 && (canFall || belowSame)) return;
    const next = this._level(meta) + 1;
    if (next > tc.spread) return;
    for (const [dx, dz] of HORIZONTAL) {
      if (this._canFlowInto(x + dx, y, z + dz, type, next)) this._flowInto(x + dx, y, z + dz, id, type, next);
    }
  }

  _touchesWater(x, y, z) {
    const w = this.world, L = this.blocks.liquid;
    return L[w.getBlock(x + 1, y, z)] === LIQUID.water || L[w.getBlock(x - 1, y, z)] === LIQUID.water
      || L[w.getBlock(x, y, z + 1)] === LIQUID.water || L[w.getBlock(x, y, z - 1)] === LIQUID.water
      || L[w.getBlock(x, y + 1, z)] === LIQUID.water;
  }

  _canFlowInto(x, y, z, type, level) {
    const w = this.world, B = this.blocks;
    if (!w.isLoaded(x, z)) return false;
    const id = w.getBlock(x, y, z);
    if (id === 0) return true;
    const t = B.liquid[id];
    if (t) {
      if (t !== type) return true;
      const m = w.getMeta(x, y, z);
      if (m === 0 || m === FALLING) return false;
      return level === FALLING || m > level;
    }
    return B.replaceable[id] === 1;
  }

  _flowInto(x, y, z, id, type, level) {
    const w = this.world, B = this.blocks;
    const cur = w.getBlock(x, y, z);
    const curType = B.liquid[cur];
    if (curType && curType !== type) {
      // Water meeting lava, or lava meeting water.
      const curMeta = w.getMeta(x, y, z);
      if (curType === LIQUID.lava) w.setBlock(x, y, z, curMeta === 0 ? this.ids.obsidian : this.ids.cobblestone);
      else w.setBlock(x, y, z, this.ids.stone);
      return;
    }
    w.setBlock(x, y, z, id, level);
  }
}

export { FALLING };
