/**
 * Crafting recipes (shaped and shapeless) from data/recipes.json, including the
 * generated tool recipes, plus helpers for the touch-friendly recipe book.
 */

export class CraftingSystem {
  /**
   * @param {object} data parsed recipes.json
   * @param {import('../world/registry.js').ItemRegistry} items
   */
  constructor(data, items) {
    this.items = items;
    this.tags = {};
    for (const [tag, names] of Object.entries(data.tags)) this.tags[tag] = new Set(names.map((n) => this._id(n)));
    const raw = [...data.recipes];
    for (const [mat, ingredient] of Object.entries(data.toolIngredients)) {
      for (const [tool, pattern] of Object.entries(data.toolPatterns)) {
        raw.push({ type: 'shaped', pattern, key: { X: ingredient, '#': 'stick' }, result: { item: `${mat}_${tool}`, count: 1 } });
      }
    }
    this.recipes = raw.map((r, index) => this._compile(r, index));
  }

  _id(name) {
    const id = this.items.id(name);
    if (id < 0) throw new Error(`recipe references unknown item "${name}"`);
    return id;
  }

  _matcher(key) {
    if (key.startsWith('#')) {
      const set = this.tags[key];
      if (!set) throw new Error(`unknown tag ${key}`);
      return set;
    }
    return new Set([this._id(key)]);
  }

  _compile(r, index) {
    const result = { id: this._id(r.result.item), count: r.result.count ?? 1 };
    if (r.type === 'shapeless') {
      const ingredients = r.ingredients.map((k) => this._matcher(k));
      return { index, type: 'shapeless', ingredients, result, size: ingredients.length <= 4 ? 2 : 3 };
    }
    const rows = r.pattern;
    const height = rows.length, width = Math.max(...rows.map((s) => s.length));
    const cells = [];
    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const ch = rows[y][x] ?? ' ';
        cells.push(ch === ' ' ? null : this._matcher(r.key[ch]));
      }
    }
    return { index, type: 'shaped', width, height, cells, result, size: Math.max(width, height) };
  }

  /**
   * Finds the recipe matching a crafting grid.
   * @param {number[]} grid item ids (0 = empty), row-major
   * @param {number} gridSize 2 or 3
   * @returns {{recipe:object, result:{id:number,count:number}}|null}
   */
  match(grid, gridSize) {
    let minX = gridSize, minY = gridSize, maxX = -1, maxY = -1;
    const present = [];
    for (let y = 0; y < gridSize; y++) {
      for (let x = 0; x < gridSize; x++) {
        const id = grid[y * gridSize + x];
        if (id) {
          present.push(id);
          minX = Math.min(minX, x); minY = Math.min(minY, y);
          maxX = Math.max(maxX, x); maxY = Math.max(maxY, y);
        }
      }
    }
    if (!present.length) return null;
    const w = maxX - minX + 1, h = maxY - minY + 1;
    for (const r of this.recipes) {
      if (r.type === 'shaped') {
        if (r.width !== w || r.height !== h) continue;
        for (const mirror of [false, true]) {
          let ok = true;
          for (let y = 0; y < h && ok; y++) {
            for (let x = 0; x < w && ok; x++) {
              const id = grid[(minY + y) * gridSize + (minX + x)];
              const cell = r.cells[y * w + (mirror ? w - 1 - x : x)];
              if (cell === null ? id !== 0 : !cell.has(id)) ok = false;
            }
          }
          if (ok) return { recipe: r, result: r.result };
        }
      } else if (this._shapelessMatches(r, present)) {
        return { recipe: r, result: r.result };
      }
    }
    return null;
  }

  _shapelessMatches(r, present) {
    if (r.ingredients.length !== present.length) return false;
    const used = new Array(present.length).fill(false);
    for (const ing of r.ingredients) {
      let found = false;
      for (let i = 0; i < present.length; i++) {
        if (!used[i] && ing.has(present[i])) { used[i] = true; found = true; break; }
      }
      if (!found) return false;
    }
    return true;
  }

  /** Ingredient requirements of a recipe as [{options:Set<id>, count}]. */
  requirements(r) {
    const list = r.type === 'shaped' ? r.cells.filter(Boolean) : r.ingredients;
    const reqs = [];
    for (const set of list) {
      const existing = reqs.find((q) => q.options === set);
      if (existing) existing.count++;
      else reqs.push({ options: set, count: 1 });
    }
    return reqs;
  }

  /**
   * Picks concrete items from an inventory for a recipe, or null if it cannot be made.
   * @param {object} r compiled recipe
   * @param {import('./inventory.js').Inventory} inv
   * @returns {Map<number, number>|null} item id -> count to consume
   */
  plan(r, inv) {
    const avail = new Map();
    for (const s of inv.slots) if (s && !(s.damage > 0)) avail.set(s.id, (avail.get(s.id) ?? 0) + s.count);
    const take = new Map();
    for (const req of this.requirements(r)) {
      let need = req.count;
      for (const id of req.options) {
        const have = (avail.get(id) ?? 0) - (take.get(id) ?? 0);
        if (have <= 0) continue;
        const n = Math.min(have, need);
        take.set(id, (take.get(id) ?? 0) + n);
        need -= n;
        if (need === 0) break;
      }
      if (need > 0) return null;
    }
    return take;
  }

  /**
   * Recipes the inventory can currently make, for the recipe book.
   * @param {import('./inventory.js').Inventory} inv
   * @param {number} gridSize 2 (inventory) or 3 (crafting table)
   */
  craftable(inv, gridSize) {
    const out = [];
    const seen = new Set();
    for (const r of this.recipes) {
      if (r.size > gridSize) continue;
      if (this.plan(r, inv)) {
        const key = `${r.result.id}`;
        if (seen.has(key)) continue;
        seen.add(key);
        out.push(r);
      }
    }
    return out;
  }

  /**
   * Crafts one batch from inventory contents (recipe book path).
   * @returns {boolean} success
   */
  craftFromInventory(r, inv) {
    const plan = this.plan(r, inv);
    if (!plan) return false;
    for (const [id, n] of plan) inv.remove(id, n);
    const left = inv.add(r.result.id, r.result.count);
    return left === 0 ? true : { overflow: left };
  }
}
