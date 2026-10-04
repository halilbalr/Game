/**
 * Furnace behaviour: fuel burning and item cooking, ticked at 20 Hz.
 * A furnace state is {input, fuel, output, burnTime, burnTotal, cookTime}.
 */
import { stack } from './inventory.js';

export class FurnaceLogic {
  /**
   * @param {object} data parsed smelting.json
   * @param {import('../world/registry.js').ItemRegistry} items
   */
  constructor(data, items) {
    this.items = items;
    this.cookTicks = data.cookTicks;
    this.outputs = new Map();
    for (const r of data.recipes) {
      const input = items.id(r.input), output = items.id(r.output);
      if (input < 0 || output < 0) throw new Error(`smelting recipe ${r.input} -> ${r.output} references unknown item`);
      this.outputs.set(input, output);
    }
  }

  /** New empty furnace state. */
  createState() {
    return { input: null, fuel: null, output: null, burnTime: 0, burnTotal: 0, cookTime: 0 };
  }

  /** Smelting result for an item id, or -1. */
  outputFor(id) { return this.outputs.get(id) ?? -1; }

  /** Burn duration in ticks for an item id (0 = not fuel). */
  fuelValue(id) { return this.items.get(id)?.fuel ?? 0; }

  _canSmelt(s) {
    if (!s.input) return false;
    const out = this.outputFor(s.input.id);
    if (out < 0) return false;
    if (!s.output) return true;
    return s.output.id === out && s.output.count < this.items.maxStack(out);
  }

  /**
   * Advances one tick.
   * @returns {{changed:boolean, lit:boolean}}
   */
  tick(s) {
    let changed = false;
    const wasLit = s.burnTime > 0;
    if (s.burnTime > 0) s.burnTime--;
    const can = this._canSmelt(s);
    if (s.burnTime === 0 && can && s.fuel) {
      const v = this.fuelValue(s.fuel.id);
      if (v > 0) {
        s.burnTime = s.burnTotal = v;
        const remainder = this.items.get(s.fuel.id)?.fuelRemainder;
        s.fuel.count--;
        if (s.fuel.count <= 0) s.fuel = remainder ? stack(this.items.id(remainder), 1) : null;
        changed = true;
      }
    }
    if (s.burnTime > 0 && can) {
      s.cookTime++;
      if (s.cookTime >= this.cookTicks) {
        s.cookTime = 0;
        const out = this.outputFor(s.input.id);
        if (s.output) s.output.count++;
        else s.output = stack(out, 1);
        s.input.count--;
        if (s.input.count <= 0) s.input = null;
        changed = true;
      }
    } else if (s.cookTime > 0) {
      s.cookTime = Math.max(0, s.cookTime - 2);
    }
    const lit = s.burnTime > 0;
    return { changed: changed || lit !== wasLit, lit };
  }
}
