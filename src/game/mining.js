/**
 * Block breaking rules: break time from hardness and tool, harvestability,
 * and drops.
 */

/**
 * Whether the held tool may harvest (get drops from) a block.
 * @param {object} def block definition
 * @param {object|undefined} item held item definition
 */
export function canHarvest(def, item) {
  if (!def.requiresTool) return true;
  const tool = item?.tool;
  return !!tool && tool.type === def.tool && tool.tier >= def.tier;
}

/**
 * Seconds needed to break a block.
 * @param {object} def block definition
 * @param {object|undefined} item held item definition
 * @param {{onGround?:boolean, inWater?:boolean, waterFactor?:number, airFactor?:number}} ctx
 * @returns {number} seconds; 0 = instant, Infinity = unbreakable
 */
export function breakSeconds(def, item, ctx = {}) {
  const h = def.hardness;
  if (h < 0) return Infinity;
  if (h === 0) return 0;
  let speed = 1;
  const tool = item?.tool;
  if (tool && def.tool && tool.type === def.tool) speed = tool.speed;
  if (tool && tool.type === 'sword' && def.name.endsWith('leaves')) speed = 1.5;
  if (ctx.inWater) speed *= ctx.waterFactor ?? 0.2;
  if (ctx.onGround === false) speed *= ctx.airFactor ?? 0.2;
  const damage = speed / h / (canHarvest(def, item) ? 30 : 100);
  if (damage >= 1) return 0;
  return Math.ceil(1 / damage) / 20;
}

/**
 * Items dropped when a block is broken.
 * @param {object} def block definition
 * @param {number} meta block metadata
 * @param {object|undefined} item held item definition
 * @param {() => number} rand
 * @param {import('../world/registry.js').ItemRegistry} items
 * @returns {{id:number, count:number}[]}
 */
export function dropsFor(def, meta, item, rand, items) {
  if (!canHarvest(def, item)) return [];
  let table = def.drops ?? [{ item: def.name }];
  if (def.ripeDrops && meta >= (def.maxStage ?? 7)) table = def.ripeDrops;
  const out = [];
  for (const d of table) {
    if (d.chance !== undefined && rand() >= d.chance) continue;
    const [lo, hi] = d.count ?? [1, 1];
    const n = lo + Math.floor(rand() * (hi - lo + 1));
    if (n > 0) out.push({ id: items.id(d.item), count: n });
  }
  return out;
}

/** Durability cost of an action for a tool. */
export function toolWear(item, action) {
  const tool = item?.tool;
  if (!tool) return 0;
  if (action === 'attack') return tool.type === 'sword' ? 1 : 2;
  return tool.type === 'sword' ? 2 : 1;
}
