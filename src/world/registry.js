/**
 * Block and item registries built from data/blocks.json and data/items.json.
 * Hot-path properties are flattened into typed arrays indexed by block id so
 * the mesher, physics and lighting code never touch object properties per voxel.
 */
import { FACE, RENDER, LIQUID } from './constants.js';

const FACE_KEYS = ['top', 'bottom', 'north', 'south', 'west', 'east'];

/** Registry of block types. */
export class BlockRegistry {
  /** @param {{defaults: object, blocks: object[]}} data parsed blocks.json */
  constructor(data) {
    /** @type {object[]} block definitions indexed by id */
    this.defs = [];
    /** @type {Map<string, object>} */
    this.byName = new Map();
    this.solid = new Uint8Array(256);
    this.opaque = new Uint8Array(256);
    this.cullSame = new Uint8Array(256);
    this.translucent = new Uint8Array(256);
    this.filter = new Uint8Array(256);
    this.emission = new Uint8Array(256);
    this.render = new Uint8Array(256);
    this.liquid = new Uint8Array(256);
    this.replaceable = new Uint8Array(256);
    this.gravity = new Uint8Array(256);
    this.orient = new Uint8Array(256);
    /** 1 when the block uses the foliage tint rather than the grass tint. */
    this.foliage = new Uint8Array(256);
    /** Texture names per id and face; resolved to atlas tiles by {@link bindAtlas}. */
    this.faceTexNames = [];
    /** Atlas tile index per (id * 7 + slot); slot 6 is an oriented block's front. Filled by bindAtlas. */
    this.faceTile = new Uint16Array(256 * 7);
    /** Optional per-stage tiles (crops), id -> Uint16Array */
    this.stageTiles = new Map();

    for (const raw of data.blocks) {
      const def = { ...data.defaults, ...raw };
      if (def.id < 0 || def.id > 255) throw new Error(`Block id out of range: ${def.name}`);
      if (this.defs[def.id]) throw new Error(`Duplicate block id ${def.id}`);
      if (this.byName.has(def.name)) throw new Error(`Duplicate block name ${def.name}`);
      def.renderId = RENDER[def.render];
      if (def.renderId === undefined) throw new Error(`Unknown render type ${def.render}`);
      this.defs[def.id] = def;
      this.byName.set(def.name, def);
      const id = def.id;
      this.solid[id] = def.solid ? 1 : 0;
      this.opaque[id] = def.opaque ? 1 : 0;
      this.cullSame[id] = def.cullSame ? 1 : 0;
      this.translucent[id] = def.translucent ? 1 : 0;
      this.filter[id] = def.opaque ? 15 : Math.min(15, def.filter);
      this.emission[id] = def.light;
      this.render[id] = def.renderId;
      this.liquid[id] = def.liquid ? LIQUID[def.liquid] : 0;
      this.replaceable[id] = def.replaceable ? 1 : 0;
      this.gravity[id] = def.gravity ? 1 : 0;
      this.orient[id] = def.orient ? 1 : 0;
      this.foliage[id] = def.tint === 'foliage' ? 1 : 0;
      this.faceTexNames[id] = resolveFaceTextures(def.tex, def.orient);
    }
    /** Air is always id 0. */
    this.AIR = 0;
  }

  /** @param {string} name @returns {number} block id, or -1 if unknown */
  id(name) {
    const def = this.byName.get(name);
    return def ? def.id : -1;
  }

  /** @param {number} id @returns {object|undefined} */
  get(id) {
    return this.defs[id];
  }

  /** Every distinct texture name referenced by any block. */
  allTextureNames() {
    const set = new Set();
    for (const names of this.faceTexNames) {
      if (names) for (const n of names) if (n) set.add(n);
    }
    for (const def of this.defs) {
      if (def?.stageTex) for (const n of def.stageTex) set.add(n);
    }
    return [...set];
  }

  /**
   * Resolves texture names to atlas tile indices.
   * @param {(name: string) => number} tileOf
   */
  bindAtlas(tileOf) {
    for (let id = 0; id < this.faceTexNames.length; id++) {
      const names = this.faceTexNames[id];
      if (!names) continue;
      for (let f = 0; f < 7; f++) this.faceTile[id * 7 + f] = names[f] ? tileOf(names[f]) : 0;
      const def = this.defs[id];
      if (def.stageTex) this.stageTiles.set(id, Uint16Array.from(def.stageTex.map(tileOf)));
    }
  }

  /**
   * Atlas tile for a face, taking orientation (front face) and growth stage into account.
   * @param {number} id block id
   * @param {number} face FACE index
   * @param {number} meta block metadata (facing for oriented blocks, stage for crops)
   */
  tileFor(id, face, meta) {
    if (this.orient[id] && face >= 2 && face === (meta & 7) && this.faceTexNames[id][6]) {
      return this.faceTile[id * 7 + 6];
    }
    const stages = this.stageTiles.get(id);
    if (stages) return stages[Math.min(stages.length - 1, meta)];
    return this.faceTile[id * 7 + face];
  }
}

/**
 * Normalises the many accepted "tex" shapes to [top, bottom, north, south, west, east, front].
 * @param {string|object|undefined} tex
 */
function resolveFaceTextures(tex, oriented) {
  if (!tex) return [null, null, null, null, null, null, null];
  if (typeof tex === 'string') return [tex, tex, tex, tex, tex, tex, null];
  const side = tex.side ?? tex.all ?? tex.top;
  const out = FACE_KEYS.map((k) => tex[k] ?? (k === 'top' || k === 'bottom' ? (tex.all ?? side) : side));
  if (tex.front && !oriented) {
    // Non-oriented blocks with a "front" (crafting table) show it on north and south.
    out[FACE.NORTH] = tex.front;
    out[FACE.SOUTH] = tex.front;
    out.push(null);
  } else {
    out.push(tex.front ?? null);
  }
  return out;
}

/** Registry of everything that can sit in an inventory slot (blocks and items). */
export class ItemRegistry {
  /**
   * @param {object} itemData parsed items.json
   * @param {BlockRegistry} blocks
   */
  constructor(itemData, blocks) {
    this.blocks = blocks;
    /** @type {Map<number, object>} */
    this.byId = new Map();
    /** @type {Map<string, object>} */
    this.byName = new Map();
    this.fistDamage = itemData.fistDamage ?? 1;
    this.materials = itemData.toolMaterials;

    for (const def of blocks.defs) {
      if (!def || def.id === 0) continue;
      this._add({
        id: def.id, name: def.name, label: def.label, stack: def.stack ?? 64,
        isBlock: true, blockId: def.id, fuel: def.fuel ?? 0, creative: def.creative,
        category: def.category,
      });
    }
    for (const raw of itemData.items) {
      this._add({ stack: 64, isBlock: false, fuel: 0, creative: true, category: raw.food ? 'food' : 'materials', ...raw });
    }
    let nextId = itemData.toolIdStart;
    for (const matName of itemData.materialOrder) {
      const mat = itemData.toolMaterials[matName];
      for (const typeName of itemData.toolOrder) {
        const type = itemData.toolTypes[typeName];
        this._add({
          id: nextId++,
          name: `${matName}_${typeName}`,
          label: {
            sv: `${mat.label.sv}${type.label.sv}`,
            en: `${mat.label.en} ${type.label.en}`,
          },
          stack: 1,
          isBlock: false,
          sprite: `tool_${typeName}`,
          palette: mat.palette,
          fuel: mat.fuel ?? 0,
          creative: true,
          category: 'tools',
          tool: {
            type: typeName, material: matName, tier: mat.tier, speed: mat.speed,
            durability: mat.durability, attack: type.attack + mat.damageBonus,
          },
        });
      }
    }
    // Patch the Swedish compound names: "Trähacka", "Stenyxa", "Diamantsvärd".
    for (const item of this.byId.values()) {
      if (item.tool) item.label.sv = item.label.sv.charAt(0).toUpperCase() + item.label.sv.slice(1);
    }
  }

  _add(item) {
    if (this.byId.has(item.id)) throw new Error(`Duplicate item id ${item.id}`);
    if (this.byName.has(item.name)) throw new Error(`Duplicate item name ${item.name}`);
    this.byId.set(item.id, item);
    this.byName.set(item.name, item);
  }

  /** @param {number} id */
  get(id) { return this.byId.get(id); }

  /** @param {string} name @returns {number} item id or -1 */
  id(name) {
    const item = this.byName.get(name);
    return item ? item.id : -1;
  }

  /** Max stack size for an item id. */
  maxStack(id) { return this.byId.get(id)?.stack ?? 64; }

  /** Localised display name. */
  label(id, lang) {
    const item = this.byId.get(id);
    if (!item) return '?';
    return item.label?.[lang] ?? item.label?.en ?? item.name;
  }

  /** Items shown in the creative inventory, in registry order. */
  creativeItems() {
    return [...this.byId.values()].filter((i) => i.creative !== false);
  }
}

/**
 * Builds both registries from parsed JSON.
 * @param {object} blocksJson
 * @param {object} itemsJson
 */
export function createRegistries(blocksJson, itemsJson) {
  const blocks = new BlockRegistry(blocksJson);
  const items = new ItemRegistry(itemsJson, blocks);
  return { blocks, items };
}

export { FACE };
