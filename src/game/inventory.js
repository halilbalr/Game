/**
 * Slot containers (player inventory, chests, furnaces, crafting grids) and the
 * cursor-based slot interaction rules shared by every inventory screen.
 * A stack is a plain object {id, count, damage} or null.
 */

/** Creates a stack object. */
export function stack(id, count = 1, damage = 0) {
  return { id, count, damage };
}

/** Two stacks can merge when they hold the same item in the same condition. */
export function sameItem(a, b) {
  return !!a && !!b && a.id === b.id && (a.damage ?? 0) === (b.damage ?? 0);
}

export class Inventory {
  /**
   * @param {number} size number of slots
   * @param {{maxStack(id:number):number}} items item registry
   */
  constructor(size, items) {
    this.size = size;
    this.items = items;
    /** @type {({id:number,count:number,damage:number}|null)[]} */
    this.slots = new Array(size).fill(null);
    /** Incremented on every change so UIs know when to redraw. */
    this.version = 0;
  }

  get(i) { return this.slots[i]; }

  set(i, s) {
    this.slots[i] = s && s.count > 0 ? s : null;
    this.version++;
  }

  /**
   * Adds items, merging into existing stacks first, then empty slots.
   * @param {number} id
   * @param {number} count
   * @param {number} [damage]
   * @param {number[]} [order] slot visiting order (default 0..size-1)
   * @returns {number} how many did not fit
   */
  add(id, count, damage = 0, order) {
    const max = this.items.maxStack(id);
    const idx = order ?? [...Array(this.size).keys()];
    let left = count;
    if (max > 1) {
      for (const i of idx) {
        const s = this.slots[i];
        if (left <= 0) break;
        if (s && s.id === id && (s.damage ?? 0) === damage && s.count < max) {
          const n = Math.min(max - s.count, left);
          s.count += n;
          left -= n;
        }
      }
    }
    for (const i of idx) {
      if (left <= 0) break;
      if (!this.slots[i]) {
        const n = Math.min(max, left);
        this.slots[i] = stack(id, n, damage);
        left -= n;
      }
    }
    if (left !== count) this.version++;
    return left;
  }

  /** Total count of an item across all slots. */
  count(id) {
    let n = 0;
    for (const s of this.slots) if (s && s.id === id) n += s.count;
    return n;
  }

  /**
   * Removes up to `count` of an item.
   * @returns {number} how many were removed
   */
  remove(id, count) {
    let left = count;
    for (let i = this.size - 1; i >= 0 && left > 0; i--) {
      const s = this.slots[i];
      if (s && s.id === id) {
        const n = Math.min(s.count, left);
        s.count -= n;
        left -= n;
        if (s.count <= 0) this.slots[i] = null;
      }
    }
    if (left !== count) this.version++;
    return count - left;
  }

  /** Removes `n` items from one slot and returns them as a stack. */
  take(i, n) {
    const s = this.slots[i];
    if (!s) return null;
    const k = Math.min(n, s.count);
    s.count -= k;
    if (s.count <= 0) this.slots[i] = null;
    this.version++;
    return stack(s.id, k, s.damage);
  }

  clear() {
    this.slots.fill(null);
    this.version++;
  }

  /** Serialisable copy. */
  toJSON() {
    return this.slots.map((s) => (s ? [s.id, s.count, s.damage ?? 0] : null));
  }

  /** Restores from {@link toJSON} output, skipping unknown item ids. */
  load(data) {
    this.slots.fill(null);
    if (Array.isArray(data)) {
      data.slice(0, this.size).forEach((e, i) => {
        if (e && this.items.get?.(e[0]) !== undefined) this.slots[i] = stack(e[0], e[1], e[2] ?? 0);
        else if (e && !this.items.get) this.slots[i] = stack(e[0], e[1], e[2] ?? 0);
      });
    }
    this.version++;
  }
}

/**
 * Applies a click on a slot with the item currently held on the cursor.
 * "primary" = tap / left click, "secondary" = long-press / right click.
 * @param {Inventory} inv
 * @param {number} i slot index
 * @param {object|null} cursor stack on the cursor
 * @param {'primary'|'secondary'} button
 * @param {(stack:object)=>boolean} [accepts] slot filter (e.g. furnace fuel)
 * @returns {object|null} new cursor stack
 */
export function clickSlot(inv, i, cursor, button, accepts) {
  const s = inv.get(i);
  const max = cursor ? inv.items.maxStack(cursor.id) : 0;
  if (cursor && accepts && !accepts(cursor)) {
    if (!s) return cursor;
  }
  if (button === 'primary') {
    if (!cursor) {
      if (!s) return null;
      inv.set(i, null);
      return s;
    }
    if (!s) {
      if (accepts && !accepts(cursor)) return cursor;
      inv.set(i, cursor);
      return null;
    }
    if (sameItem(s, cursor) && max > 1) {
      const n = Math.min(max - s.count, cursor.count);
      s.count += n;
      inv.set(i, s);
      const rest = cursor.count - n;
      return rest > 0 ? stack(cursor.id, rest, cursor.damage) : null;
    }
    if (accepts && !accepts(cursor)) return cursor;
    inv.set(i, cursor);
    return s;
  }
  // secondary
  if (!cursor) {
    if (!s) return null;
    const half = Math.ceil(s.count / 2);
    return inv.take(i, half);
  }
  if (accepts && !accepts(cursor)) return cursor;
  if (!s) {
    inv.set(i, stack(cursor.id, 1, cursor.damage));
    return cursor.count > 1 ? stack(cursor.id, cursor.count - 1, cursor.damage) : null;
  }
  if (sameItem(s, cursor) && s.count < max) {
    s.count += 1;
    inv.set(i, s);
    return cursor.count > 1 ? stack(cursor.id, cursor.count - 1, cursor.damage) : null;
  }
  inv.set(i, cursor);
  return s;
}

/**
 * Moves a stack between two inventories ("shift-click"): fills matching stacks
 * then empty slots of the target in the given order.
 * @returns {boolean} whether anything moved
 */
export function quickMove(from, i, to, order) {
  const s = from.get(i);
  if (!s) return false;
  const left = to.add(s.id, s.count, s.damage ?? 0, order);
  if (left === s.count) return false;
  if (left === 0) from.set(i, null);
  else { s.count = left; from.set(i, s); }
  return true;
}
