/**
 * Inventory-style screens: player inventory (with 2x2 crafting and a recipe
 * book), crafting table, furnace, chest and the creative item palette.
 *
 * Interaction (touch and mouse):
 *   tap / left click        pick up, place, merge or swap a stack
 *   hold / right click      take half, or place a single item
 *   shift + click (desktop) move the stack to the other side
 */
import { h } from './ui.js';
import { Inventory, clickSlot, quickMove, stack, sameItem } from '../game/inventory.js';

/** Adapter exposing a furnace state as three inventory slots. */
class FurnaceSlots {
  constructor(state, items) {
    this.state = state;
    this.items = items;
    this.keys = ['input', 'fuel', 'output'];
    this.size = 3;
    this.version = 0;
  }
  get(i) { return this.state[this.keys[i]]; }
  set(i, s) { this.state[this.keys[i]] = s && s.count > 0 ? s : null; this.version++; }
  take(i, n) {
    const s = this.get(i);
    if (!s) return null;
    const k = Math.min(n, s.count);
    s.count -= k;
    if (s.count <= 0) this.set(i, null);
    this.version++;
    return stack(s.id, k, s.damage);
  }
  add(id, count, damage = 0) {
    // Used by quick-move: smeltables go to input, fuel to fuel.
    const slot = this.furnace.outputFor(id) >= 0 ? 0 : (this.furnace.fuelValue(id) > 0 ? 1 : -1);
    if (slot < 0) return count;
    const cur = this.get(slot);
    const max = this.items.maxStack(id);
    if (!cur) { const n = Math.min(max, count); this.set(slot, stack(id, n, damage)); return count - n; }
    if (cur.id !== id) return count;
    const n = Math.min(max - cur.count, count);
    cur.count += n;
    this.version++;
    return count - n;
  }
}

export class InventoryScreens {
  /** @param {import('./ui.js').UI} ui */
  constructor(ui) {
    this.ui = ui;
    this.items = ui.items;
    this.cursor = null;
    this.kind = null;
    this.ctx = null;
    this.slotEls = [];
    this.creativeTab = ui.data.ui.creativeTabs[0].id;
    this.cursorEl = h('div', { class: 'cursor-item' }, h('img', { alt: '' }), h('span', { class: 'count' }));
    document.body.appendChild(this.cursorEl);
    window.addEventListener('pointermove', (e) => {
      if (this.kind) this._moveCursor(e.clientX, e.clientY);
    });
  }

  get game() { return this.ui.game; }

  t(k, p) { return this.ui.t(k, p); }

  /**
   * Opens a screen.
   * @param {'inventory'|'crafting'|'furnace'|'chest'} kind
   * @param {object} [ctx] block position and entity for containers
   */
  open(kind, ctx = {}) {
    if (!this.game) return;
    this.kind = kind;
    this.ctx = ctx;
    this.cursor = null;
    this.slotEls = [];
    this.recipeVersion = -1;
    if (kind === 'inventory' && this.game.creative) this.kind = kind = 'creative';
    if (kind === 'inventory') this.grid = new Inventory(4, this.items);
    else if (kind === 'crafting') this.grid = new Inventory(9, this.items);
    else this.grid = null;
    if (kind === 'chest') {
      this.container = new Inventory(ctx.entity.slots.length, this.items);
      this.container.slots = ctx.entity.slots;
    } else if (kind === 'furnace') {
      this.container = new FurnaceSlots(ctx.entity, this.items);
      this.container.furnace = this.game.furnaceLogic;
    } else this.container = null;
    this._build();
    this.ui.show(kind, this.el);
    this.refresh();
  }

  /** Closes the screen, returning held and grid items to the player. */
  close() {
    if (!this.kind) return;
    const g = this.game;
    if (this.cursor) { g.give(this.cursor.id, this.cursor.count, this.cursor.damage ?? 0); this.cursor = null; }
    if (this.grid) for (const s of this.grid.slots) if (s) g.give(s.id, s.count, s.damage ?? 0);
    if (this.ctx?.x !== undefined && this.ctx.entity) g.world.setBlockEntity(this.ctx.x, this.ctx.y, this.ctx.z, this.ctx.entity);
    this.kind = null;
    this.ctx = null;
    this.cursorEl.classList.remove('show');
    this.ui.show(null, null);
    this.ui.app.resume();
  }

  _title() {
    return {
      inventory: this.t('inv.title'), creative: this.t('inv.creative'), crafting: this.t('inv.craftingTable'),
      furnace: this.t('inv.furnace'), chest: this.t('inv.chest'),
    }[this.kind];
  }

  _build() {
    const header = h('div', { class: 'inv-header' },
      h('span', { class: 'inv-title' }, this._title()),
      h('span', { class: 'inv-hint' }, this.t('inv.hint')),
      h('button', { class: 'mc-btn small close-btn', onclick: () => { this.ui.click(); this.close(); } }, '✕'));
    let body;
    switch (this.kind) {
      case 'creative': body = this._creativeBody(); break;
      case 'furnace': body = this._furnaceBody(); break;
      case 'chest': body = h('div', { class: 'inv-section' }, this._grid(this.container, [...Array(this.container.size).keys()], 9)); break;
      default: body = this._craftingBody(this.kind === 'crafting' ? 3 : 2);
    }
    const player = this.kind === 'creative' ? null : h('div', { class: 'inv-section player-inv' },
      this._grid(this.game.inventory, [...Array(27).keys()].map((i) => i + 9), 9),
      h('div', { class: 'hotbar-gap' }),
      this._grid(this.game.inventory, [...Array(9).keys()], 9, true));
    this.el = h('div', { class: `menu inv-screen inv-${this.kind}` },
      h('div', { class: 'inv-panel', onpointerdown: (e) => { if (e.target === e.currentTarget) e.preventDefault(); } },
        header, h('div', { class: 'inv-body' }, body, player)));
    this.refresh();
  }

  /* ---------------------------------------------------------------- slots */

  _slotEl(get, act, opts = {}) {
    const el = h('div', { class: `slot${opts.cls ? ` ${opts.cls}` : ''}` },
      h('img', { class: 'icon', alt: '', draggable: 'false' }), h('span', { class: 'count' }), h('div', { class: 'dura' }, h('div', {})));
    let timer = null, longFired = false;
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    el.addEventListener('pointerdown', (e) => {
      e.preventDefault();
      this._moveCursor(e.clientX, e.clientY);
      if (e.pointerType === 'mouse') {
        if (e.button === 2) act('secondary');
        else if (e.button === 0) act(e.shiftKey ? 'quick' : 'primary');
        return;
      }
      longFired = false;
      timer = setTimeout(() => { timer = null; longFired = true; act('secondary'); }, this.ui.data.ui.inventoryHoldMs);
    });
    const up = (e) => {
      if (e.pointerType === 'mouse') return;
      if (timer) { clearTimeout(timer); timer = null; if (!longFired) act('primary'); }
    };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', () => { if (timer) clearTimeout(timer); timer = null; });
    this.slotEls.push({ el, get, selected: opts.selected });
    return el;
  }

  _grid(inv, indices, cols, isHotbar = false) {
    const wrap = h('div', { class: 'slot-grid', style: { gridTemplateColumns: `repeat(${cols}, var(--slot))` } });
    for (const i of indices) {
      wrap.appendChild(this._slotEl(() => inv.get(i), (button) => this._clickContainer(inv, i, button), {
        selected: isHotbar ? () => this.game.selected === i : null,
      }));
    }
    return wrap;
  }

  _clickContainer(inv, i, button) {
    this.ui.click();
    const g = this.game;
    if (button === 'quick') {
      const other = this.container && inv !== this.container ? this.container : (inv === this.container ? g.inventory : null);
      if (other) quickMove(inv, i, other);
      else if (inv === g.inventory) {
        const order = i < 9 ? [...Array(27).keys()].map((k) => k + 9) : [...Array(9).keys()];
        const s = inv.get(i);
        if (s) {
          const left = inv.add(s.id, s.count, s.damage ?? 0, order);
          if (left === 0) inv.set(i, null); else { s.count = left; inv.set(i, s); }
        }
      }
    } else if (inv instanceof FurnaceSlots && i === 2) {
      this._takeOutput(() => inv.get(2), (n) => inv.take(2, n));
    } else {
      const accepts = inv instanceof FurnaceSlots && i === 1 ? (s) => this.game.furnaceLogic.fuelValue(s.id) > 0 : undefined;
      this.cursor = clickSlot(inv, i, this.cursor, button, accepts);
    }
    if (inv === this.container && this.ctx?.x !== undefined) {
      const c = g.world.getChunk(this.ctx.x >> 4, this.ctx.z >> 4);
      if (c) c.modified = true;
    }
    this.refresh();
  }

  _takeOutput(get, take) {
    const s = get();
    if (!s) return;
    if (!this.cursor) this.cursor = take(s.count);
    else if (sameItem(this.cursor, s)) {
      const room = this.items.maxStack(s.id) - this.cursor.count;
      const got = take(Math.min(room, s.count));
      if (got) this.cursor.count += got.count;
    }
  }

  /* ---------------------------------------------------------------- crafting */

  _craftingBody(size) {
    const gridIdx = [...Array(size * size).keys()];
    this.resultEl = this._slotEl(() => this._craftResult(), (button) => this._clickResult(button), { cls: 'result' });
    this.recipeList = h('div', { class: 'recipe-list' });
    return h('div', { class: 'inv-section craft-row' },
      h('div', { class: 'craft-area' },
        h('div', { class: 'label' }, this.t('inv.crafting')),
        h('div', { class: 'craft-grid-row' },
          this._grid(this.grid, gridIdx, size),
          h('div', { class: 'arrow' }, '➜'),
          this.resultEl)),
      h('div', { class: 'recipes' }, h('div', { class: 'label' }, this.t('inv.recipes')), this.recipeList));
  }

  _gridIds() { return this.grid.slots.map((s) => (s ? s.id : 0)); }

  _craftResult() {
    if (!this.grid) return null;
    const m = this.game.crafting.match(this._gridIds(), Math.sqrt(this.grid.size));
    return m ? stack(m.result.id, m.result.count) : null;
  }

  _clickResult(button) {
    this.ui.click();
    const r = this._craftResult();
    if (!r) return;
    const consume = () => {
      for (let i = 0; i < this.grid.size; i++) if (this.grid.get(i)) this.grid.take(i, 1);
    };
    if (button === 'quick') {
      // Craft as many as possible straight into the inventory.
      let guard = 64;
      while (guard-- > 0) {
        const res = this._craftResult();
        if (!res || res.id !== r.id) break;
        const left = this.game.inventory.add(res.id, res.count);
        consume();
        if (left > 0) { this.game.give(res.id, left); break; }
      }
    } else if (!this.cursor) {
      this.cursor = r;
      consume();
    } else if (sameItem(this.cursor, r) && this.cursor.count + r.count <= this.items.maxStack(r.id)) {
      this.cursor.count += r.count;
      consume();
    }
    this.refresh();
  }

  _renderRecipes() {
    if (!this.recipeList) return;
    const key = `${this.game.inventory.version}`;
    if (this.recipeVersion === key) return;
    this.recipeVersion = key;
    const size = this.kind === 'crafting' ? 3 : 2;
    const list = this.game.crafting.craftable(this.game.inventory, size);
    this.recipeList.innerHTML = '';
    if (!list.length) this.recipeList.appendChild(h('p', { class: 'muted small' }, this.t('inv.noRecipes')));
    for (const r of list) {
      const btn = h('div', { class: 'slot recipe', title: this.items.label(r.result.id, this.ui.i18n.lang) },
        h('img', { class: 'icon', alt: '', src: this.ui.icons.url(r.result.id) }),
        h('span', { class: 'count' }, r.result.count > 1 ? String(r.result.count) : ''));
      btn.addEventListener('pointerdown', (e) => {
        e.preventDefault();
        this.ui.click();
        const res = this.game.crafting.craftFromInventory(r, this.game.inventory);
        if (res && res.overflow) this.game.give(r.result.id, res.overflow);
        this.ui.toast(this.items.label(r.result.id, this.ui.i18n.lang), 1.2);
        this.refresh();
      });
      this.recipeList.appendChild(btn);
    }
  }

  /* ---------------------------------------------------------------- furnace */

  _furnaceBody() {
    this.flame = h('div', { class: 'flame' }, h('div', { class: 'fill' }));
    this.progressArrow = h('div', { class: 'progress-arrow' }, h('div', { class: 'fill' }));
    const c = this.container;
    const slot = (i, cls) => this._slotEl(() => c.get(i), (b) => this._clickContainer(c, i, b), { cls });
    return h('div', { class: 'inv-section furnace-row' },
      h('div', { class: 'furnace-col' }, slot(0), this.flame, slot(1, 'fuel')),
      this.progressArrow,
      slot(2, 'result'));
  }

  /* ---------------------------------------------------------------- creative */

  _creativeBody() {
    const tabs = h('div', { class: 'tabs' });
    const gridWrap = h('div', { class: 'creative-grid' });
    const renderTab = () => {
      tabs.innerHTML = '';
      for (const tab of this.ui.data.ui.creativeTabs) {
        const iconId = this.items.id(tab.icon);
        tabs.appendChild(h('div', {
          class: `tab${tab.id === this.creativeTab ? ' active' : ''}`,
          title: this.t(`tab.${tab.id}`),
          onpointerdown: (e) => { e.preventDefault(); this.ui.click(); this.creativeTab = tab.id; renderTab(); },
        }, h('img', { alt: '', src: this.ui.icons.url(iconId) }), h('span', {}, this.t(`tab.${tab.id}`))));
      }
      const tab = this.ui.data.ui.creativeTabs.find((t) => t.id === this.creativeTab);
      gridWrap.innerHTML = '';
      const list = this.items.creativeItems().filter((i) => tab.categories.includes(i.category ?? 'building'));
      const grid = h('div', { class: 'slot-grid', style: { gridTemplateColumns: 'repeat(9, var(--slot))' } });
      for (const item of list) {
        const el = h('div', { class: 'slot', title: this.items.label(item.id, this.ui.i18n.lang) },
          h('img', { class: 'icon', alt: '', src: this.ui.icons.url(item.id) }));
        el.addEventListener('pointerdown', (e) => {
          e.preventDefault();
          this.ui.click();
          const full = stack(item.id, this.items.maxStack(item.id));
          if (e.pointerType === 'mouse' && this.cursor) { this.cursor = null; }
          else if (e.pointerType === 'mouse') this.cursor = full;
          else this.game.inventory.set(this.game.selected, full);
          this.refresh();
        });
        grid.appendChild(el);
      }
      gridWrap.appendChild(grid);
      this.slotEls = this.slotEls.filter((s) => s.el.isConnected || s.keep);
    };
    renderTab();
    const trash = this._slotEl(() => null, () => { this.ui.click(); this.cursor = null; this.refresh(); }, { cls: 'trash' });
    trash.appendChild(h('span', { class: 'trash-label' }, '🗑'));
    const hotbar = this._grid(this.game.inventory, [...Array(9).keys()], 9, true);
    for (const s of this.slotEls) s.keep = true;
    return h('div', { class: 'inv-section creative' }, tabs, gridWrap, h('div', { class: 'creative-hotbar' }, hotbar, trash));
  }

  /* ---------------------------------------------------------------- refresh */

  _moveCursor(x, y) {
    this.cursorEl.style.left = `${x}px`;
    this.cursorEl.style.top = `${y}px`;
  }

  /** Redraws every visible slot and the cursor. */
  refresh() {
    if (!this.kind) return;
    for (const s of this.slotEls) {
      if (!s.el.isConnected) continue;
      this.ui._renderSlot(s.el, s.get(), s.selected ? s.selected() : false);
    }
    if (this.cursor) {
      this.cursorEl.querySelector('img').src = this.ui.icons.url(this.cursor.id);
      this.cursorEl.querySelector('.count').textContent = this.cursor.count > 1 ? String(this.cursor.count) : '';
      this.cursorEl.classList.add('show');
    } else this.cursorEl.classList.remove('show');
    this._renderRecipes();
  }

  /** Per-frame updates (furnace progress, container changes from ticks). */
  update() {
    if (this.kind === 'furnace') {
      const s = this.ctx.entity;
      const burn = s.burnTotal ? s.burnTime / s.burnTotal : 0;
      this.flame.firstChild.style.height = `${Math.round(burn * 100)}%`;
      this.progressArrow.firstChild.style.width = `${Math.round((s.cookTime / this.game.furnaceLogic.cookTicks) * 100)}%`;
      const sig = `${s.input?.count}|${s.fuel?.count}|${s.output?.count}|${s.input?.id}|${s.output?.id}|${s.fuel?.id}`;
      if (sig !== this._furnaceSig) { this._furnaceSig = sig; this.refresh(); }
    }
  }
}
