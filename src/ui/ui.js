/**
 * DOM user interface: menus, HUD and screen management. Gameplay screens that
 * move items around (inventory, crafting, furnace, chest) live in
 * inventoryScreens.js.
 */
import { InventoryScreens } from './inventoryScreens.js';
import { seedFromString } from '../core/random.js';

/** Small helper to build DOM trees. */
export function h(tag, props = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(props ?? {})) {
    if (k === 'class') el.className = v;
    else if (k === 'style' && typeof v === 'object') Object.assign(el.style, v);
    else if (k.startsWith('on')) el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (v !== undefined && v !== null && v !== false) el.setAttribute(k, v === true ? '' : v);
  }
  for (const c of children.flat()) {
    if (c === null || c === undefined || c === false) continue;
    el.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
  }
  return el;
}

/** Pixel-art HUD icons (hearts, food, bubbles) as data URLs. */
function hudIcon(rows, palette) {
  const c = document.createElement('canvas');
  c.width = rows[0].length; c.height = rows.length;
  const ctx = c.getContext('2d');
  rows.forEach((r, y) => [...r].forEach((ch, x) => {
    if (ch === '.') return;
    ctx.fillStyle = palette[ch];
    ctx.fillRect(x, y, 1, 1);
  }));
  return c.toDataURL();
}

const HEART = ['.kk.kk.', 'krrkrrk', 'krwrrrk', 'krrrrrk', '.krrrk.', '..krk..', '...k...'];
const HEART_HALF = ['.kk.kk.', 'krrkeek', 'krwreek', 'krreeek', '.krrek.', '..kek..', '...k...'];
const HEART_EMPTY = ['.kk.kk.', 'keekeek', 'keeeeek', 'keeeeek', '.keeek.', '..kek..', '...k...'];
const FOOD = ['....kk.', '...kbbk', '..kbbwk', '.kbbbk.', 'kmmkk..', 'kwk....', '.k.....'];
const FOOD_HALF = ['....kk.', '...keek', '..keeek', '.kbbek.', 'kmmkk..', 'kwk....', '.k.....'];
const FOOD_EMPTY = ['....kk.', '...keek', '..keeek', '.keeek.', 'keekk..', 'kek....', '.k.....'];
const BUBBLE = ['..kkk..', '.kbbbk.', 'kbwbbbk', 'kbbbbbk', 'kbbbbbk', '.kbbbk.', '..kkk..'];

export class UI {
  /**
   * @param {object} deps
   * @param {HTMLElement} deps.root container for screens
   * @param {HTMLElement} deps.hud HUD container
   * @param {import('./i18n.js').I18n} deps.i18n
   * @param {import('./icons.js').IconRenderer} deps.icons
   * @param {object} deps.app application controller (startWorld, quitToTitle, ...)
   * @param {object} deps.data parsed data files
   * @param {object} deps.settings
   * @param {object} deps.sound
   * @param {object} deps.registries
   * @param {object} deps.crafting
   * @param {object} deps.furnaceLogic
   */
  constructor(deps) {
    Object.assign(this, deps);
    this.items = deps.registries.items;
    this.blocks = deps.registries.blocks;
    this.screen = null;
    this.screenName = null;
    this.game = null;
    this.icons16 = {
      heart: hudIcon(HEART, { k: '#1a0000', r: '#e01e1e', w: '#ff9a9a' }),
      heartHalf: hudIcon(HEART_HALF, { k: '#1a0000', r: '#e01e1e', w: '#ff9a9a', e: '#3a2020' }),
      heartEmpty: hudIcon(HEART_EMPTY, { k: '#1a0000', e: '#3a2020' }),
      food: hudIcon(FOOD, { k: '#1a0e00', b: '#b8682a', w: '#ffffff', m: '#e8d8c0' }),
      foodHalf: hudIcon(FOOD_HALF, { k: '#1a0e00', b: '#b8682a', w: '#ffffff', m: '#e8d8c0', e: '#3a2a1a' }),
      foodEmpty: hudIcon(FOOD_EMPTY, { k: '#1a0e00', e: '#3a2a1a' }),
      bubble: hudIcon(BUBBLE, { k: '#0a1a40', b: '#3a8af0', w: '#ffffff' }),
    };
    this.inv = new InventoryScreens(this);
    this._buildHud();
    this._toastTimer = 0;
    this._nameTimer = 0;
  }

  t(key, params) { return this.i18n.t(key, params); }

  click() { this.sound?.play('click'); }

  /* ------------------------------------------------------------ screens */

  /** Replaces the current full-screen menu (null closes it). */
  show(name, el) {
    if (this.screen) this.screen.remove();
    this.screen = el;
    this.screenName = el ? name : null;
    if (el) this.root.appendChild(el);
    this.root.classList.toggle('open', !!el);
    this.app.onScreenChanged?.(this.screenName);
  }

  get blocking() { return this.screenName !== null; }

  button(label, onClick, cls = '') {
    return h('button', { class: `mc-btn ${cls}`, onclick: (e) => { e.preventDefault(); this.click(); onClick(e); } }, label);
  }

  panel(title, ...children) {
    return h('div', { class: 'menu' }, h('div', { class: 'menu-inner' }, title ? h('h2', { class: 'menu-title' }, title) : null, ...children));
  }

  showTitle() {
    const splashes = this.data.ui.splashes[this.i18n.lang] ?? this.data.ui.splashes.en;
    const splash = splashes[Math.floor(Math.random() * splashes.length)];
    const el = h('div', { class: 'menu title-screen' },
      h('div', { class: 'menu-inner' },
        h('div', { class: 'logo-wrap' },
          h('h1', { class: 'logo' }, 'BLOCKHEIM'),
          h('div', { class: 'splash' }, splash)),
        h('p', { class: 'subtitle' }, this.t('title.subtitle')),
        this.button(this.t('title.play'), () => this.showWorlds(), 'wide'),
        this.button(this.t('title.settings'), () => this.showSettings(() => this.showTitle()), 'wide'),
        h('div', { class: 'version' }, this.t('title.version'))));
    this.show('title', el);
  }

  async showWorlds() {
    const worlds = await this.app.storage.listWorlds();
    let selected = worlds[0]?.id ?? null;
    const list = h('div', { class: 'world-list' });
    const render = () => {
      list.innerHTML = '';
      if (!worlds.length) list.appendChild(h('p', { class: 'muted' }, this.t('worlds.none')));
      for (const w of worlds) {
        const date = new Date(w.lastPlayed ?? w.created).toLocaleString(this.i18n.lang === 'sv' ? 'sv-SE' : 'en-GB');
        list.appendChild(h('div', {
          class: `world-row${w.id === selected ? ' selected' : ''}`,
          onclick: () => { selected = w.id; render(); },
          ondblclick: () => this.app.startWorld(w),
        },
        h('div', { class: 'world-name' }, w.name),
        h('div', { class: 'world-info' }, `${this.t(`mode.${w.mode}`)} · ${this.t(`difficulty.${w.difficulty}`)} · ${this.t('worlds.lastPlayed', { date })}`)));
      }
    };
    render();
    // Two-step delete: the first tap arms the button, the second confirms.
    let armed = false;
    const deleteBtn = this.button(this.t('worlds.delete'), async () => {
      const w = worlds.find((x) => x.id === selected);
      if (!w) return;
      if (!armed) {
        armed = true;
        deleteBtn.classList.add('armed');
        deleteBtn.textContent = this.t('worlds.confirmDelete', { name: w.name });
        return;
      }
      await this.app.storage.deleteWorld(w.id);
      this.showWorlds();
    });
    const el = this.panel(this.t('worlds.title'),
      this.app.storage.volatile ? h('p', { class: 'warn' }, this.t('worlds.volatile')) : null,
      list,
      h('div', { class: 'row' },
        this.button(this.t('worlds.play'), () => { const w = worlds.find((x) => x.id === selected); if (w) this.app.startWorld(w); }),
        this.button(this.t('worlds.create'), () => this.showCreate())),
      h('div', { class: 'row' },
        deleteBtn,
        this.button(this.t('worlds.back'), () => this.showTitle())));
    this.show('worlds', el);
  }

  showCreate() {
    const state = { mode: 'survival', difficulty: 'normal' };
    const name = h('input', { class: 'mc-input', value: this.t('create.defaultName'), maxlength: 32 });
    const seed = h('input', { class: 'mc-input', placeholder: this.t('create.seed'), maxlength: 32 });
    const modeBtn = this.button('', () => { state.mode = state.mode === 'survival' ? 'creative' : 'survival'; sync(); }, 'wide');
    const modeDesc = h('p', { class: 'muted small' });
    const diffs = ['peaceful', 'easy', 'normal', 'hard'];
    const diffBtn = this.button('', () => { state.difficulty = diffs[(diffs.indexOf(state.difficulty) + 1) % diffs.length]; sync(); }, 'wide');
    const sync = () => {
      modeBtn.textContent = `${this.t('create.mode')}: ${this.t(`mode.${state.mode}`)}`;
      modeDesc.textContent = this.t(`mode.${state.mode}.desc`);
      diffBtn.textContent = `${this.t('create.difficulty')}: ${this.t(`difficulty.${state.difficulty}`)}`;
    };
    sync();
    const el = this.panel(this.t('create.title'),
      h('label', { class: 'field' }, h('span', {}, this.t('create.name')), name),
      h('label', { class: 'field' }, h('span', {}, this.t('create.seed')), seed),
      modeBtn, modeDesc, diffBtn,
      h('div', { class: 'row' },
        this.button(this.t('create.create'), () => {
          const seedText = seed.value.trim() || String(Math.floor(Math.random() * 2 ** 31));
          const meta = {
            id: `w${Date.now().toString(36)}${Math.floor(Math.random() * 1e6).toString(36)}`,
            name: name.value.trim() || this.t('create.defaultName'),
            seedText, seed: seedFromString(seedText),
            mode: state.mode, difficulty: state.difficulty,
            created: Date.now(), lastPlayed: Date.now(),
          };
          this.app.startWorld(meta);
        }),
        this.button(this.t('create.cancel'), () => this.showWorlds())));
    this.show('create', el);
  }

  showLoading(textKey) {
    this.loadingBar = h('div', { class: 'progress-fill' });
    const el = h('div', { class: 'menu loading' }, h('div', { class: 'menu-inner' },
      h('h2', { class: 'menu-title' }, this.t(textKey)),
      h('div', { class: 'progress' }, this.loadingBar)));
    this.show('loading', el);
  }

  setLoading(f) { if (this.loadingBar) this.loadingBar.style.width = `${Math.round(f * 100)}%`; }

  showPause() {
    const el = this.panel(this.t('pause.title'),
      this.button(this.t('pause.resume'), () => this.app.resume(), 'wide'),
      this.button(this.t('pause.settings'), () => this.showSettings(() => this.showPause()), 'wide'),
      this.button(this.t('pause.saveQuit'), () => this.app.quitToTitle(), 'wide'));
    el.classList.add('translucent');
    this.show('pause', el);
  }

  showSettings(back) {
    const s = this.settings;
    const rc = this.data.game.render;
    const slider = (labelKey, min, max, step, get, set, fmt = (v) => v) => {
      const label = h('span', {});
      const input = h('input', { type: 'range', min, max, step, value: get(), class: 'mc-range' });
      const upd = () => { label.textContent = this.t(labelKey, { n: fmt(Number(input.value)) }); };
      input.addEventListener('input', () => { set(Number(input.value)); upd(); this.app.onSettingsChanged(); });
      upd();
      return h('label', { class: 'slider' }, label, input);
    };
    const toggle = (labelKey, key, values = [true, false]) => {
      const btn = this.button('', () => {
        s[key] = values[(values.indexOf(s[key]) + 1) % values.length];
        upd();
        this.app.onSettingsChanged();
      }, 'wide');
      const upd = () => {
        const v = s[key];
        const word = v === true ? this.t('settings.on') : v === false ? this.t('settings.off') : this.t(`settings.${v}`);
        btn.textContent = `${this.t(labelKey)}: ${word}`;
      };
      upd();
      return btn;
    };
    const langBtn = this.button('', () => {
      const langs = Object.keys(this.data.strings);
      s.language = langs[(langs.indexOf(this.i18n.lang) + 1) % langs.length];
      this.i18n.setLanguage(s.language);
      this.app.onSettingsChanged();
      this.showSettings(back);
    }, 'wide');
    langBtn.textContent = `${this.t('settings.language')}: ${this.i18n.lang === 'sv' ? 'Svenska' : 'English'}`;
    const el = this.panel(this.t('settings.title'),
      h('div', { class: 'settings-grid' },
        slider('settings.renderDistance', rc.minRenderDistance, rc.maxRenderDistance, 1, () => s.renderDistance, (v) => { s.renderDistance = v; }),
        slider('settings.fov', 50, 110, 1, () => s.fov, (v) => { s.fov = v; }),
        slider('settings.sensitivity', 20, 300, 5, () => Math.round(s.sensitivity * 100), (v) => { s.sensitivity = v / 100; }),
        slider('settings.resolution', 50, 100, 5, () => Math.round(s.resolution * 100), (v) => { s.resolution = v / 100; }),
        slider('settings.volume', 0, 100, 5, () => Math.round(s.volume * 100), (v) => { s.volume = v / 100; }),
        slider('settings.music', 0, 100, 5, () => Math.round(s.music * 100), (v) => { s.music = v / 100; }),
        toggle('settings.autoJump', 'autoJump'),
        toggle('settings.clouds', 'clouds'),
        toggle('settings.showFps', 'showFps'),
        toggle('settings.invertY', 'invertY'),
        toggle('settings.touchControls', 'touchControls', ['auto', 'on', 'off']),
        langBtn),
      this.button(this.t('settings.done'), () => { this.app.saveSettings(); back(); }, 'wide'));
    if (this.game) el.classList.add('translucent');
    this.show('settings', el);
  }

  showDeath(cause) {
    const key = `death.cause.${cause}`;
    const text = this.t(key) === key ? this.t('death.cause.mob') : this.t(key);
    const el = h('div', { class: 'menu death' }, h('div', { class: 'menu-inner' },
      h('h1', { class: 'death-title' }, this.t('death.title')),
      h('p', {}, text),
      this.button(this.t('death.respawn'), () => this.app.respawn(), 'wide'),
      this.button(this.t('death.title.menu'), () => this.app.quitToTitle(), 'wide')));
    this.show('death', el);
  }

  /** Opens an in-game container screen. */
  openScreen(kind, ctx) {
    this.inv.open(kind, ctx);
  }

  closeContainerAt(x, y, z) {
    if (this.inv.ctx && this.inv.ctx.x === x && this.inv.ctx.y === y && this.inv.ctx.z === z) this.inv.close();
  }

  /* ------------------------------------------------------------ HUD */

  _buildHud() {
    const hud = this.hud;
    hud.innerHTML = '';
    this.crosshair = h('div', { class: 'crosshair' });
    this.debug = h('pre', { class: 'debug' });
    this.toastEl = h('div', { class: 'toast' });
    this.itemName = h('div', { class: 'item-name' });
    this.pauseBtn = h('div', { class: 'hud-btn hud-pause', onclick: () => { this.click(); this.app.pause(); } }, h('span', {}), h('span', {}));
    this.hearts = h('div', { class: 'bar hearts' });
    this.food = h('div', { class: 'bar food' });
    this.air = h('div', { class: 'bar air' });
    this.hotbar = h('div', { class: 'hud-hotbar' });
    this.slots = [];
    for (let i = 0; i < 9; i++) {
      const slot = h('div', { class: 'slot' }, h('img', { class: 'icon', alt: '', draggable: 'false' }), h('span', { class: 'count' }), h('div', { class: 'dura' }, h('div', {})));
      let pressTimer = null;
      const start = (e) => {
        e.preventDefault();
        e.stopPropagation();
        this.game?.select(i);
        pressTimer = setTimeout(() => { pressTimer = null; this.game?.dropHeld(true); }, 700);
      };
      const end = (e) => { e.preventDefault(); e.stopPropagation(); if (pressTimer) clearTimeout(pressTimer); pressTimer = null; };
      slot.addEventListener('touchstart', start, { passive: false });
      slot.addEventListener('touchend', end, { passive: false });
      slot.addEventListener('mousedown', (e) => { e.stopPropagation(); this.game?.select(i); });
      this.slots.push(slot);
      this.hotbar.appendChild(slot);
    }
    this.invBtn = h('div', { class: 'slot inv-btn' }, h('span', {}, '•••'));
    const openInv = (e) => { e.preventDefault(); e.stopPropagation(); this.click(); this.inv.open('inventory'); };
    this.invBtn.addEventListener('touchstart', openInv, { passive: false });
    this.invBtn.addEventListener('mousedown', openInv);
    this.hotbar.appendChild(this.invBtn);
    this.overlayWater = h('div', { class: 'overlay water' });
    this.overlayHurt = h('div', { class: 'overlay hurt' });
    this.overlaySleep = h('div', { class: 'overlay sleep' });
    this.bars = h('div', { class: 'bars' }, h('div', { class: 'bar-left' }, this.hearts), h('div', { class: 'bar-right' }, this.air, this.food));
    hud.append(this.overlayWater, this.overlayHurt, this.crosshair, this.debug, this.pauseBtn, this.toastEl, this.itemName,
      h('div', { class: 'hud-bottom' }, this.bars, this.hotbar), this.overlaySleep);
    this._heartImgs = []; this._foodImgs = []; this._airImgs = [];
    for (let i = 0; i < 10; i++) {
      this._heartImgs.push(this.hearts.appendChild(h('img', { alt: '' })));
      this._foodImgs.push(this.food.appendChild(h('img', { alt: '' })));
      this._airImgs.push(this.air.appendChild(h('img', { alt: '', src: this.icons16.bubble })));
    }
    this._hudCache = {};
  }

  /** Shows a short message above the hotbar. */
  toast(text, seconds = 2.5) {
    this.toastEl.textContent = text;
    this.toastEl.classList.add('show');
    this._toastTimer = seconds;
  }

  sleepFade(seconds) {
    this.overlaySleep.style.transition = `opacity ${seconds / 2}s`;
    this.overlaySleep.classList.add('show');
    setTimeout(() => this.overlaySleep.classList.remove('show'), seconds * 500);
  }

  /** Per-frame HUD refresh (only touches the DOM when values change). */
  updateHud(game, dt, fps) {
    const c = this._hudCache;
    this.hud.classList.toggle('creative', game.creative);
    this.hud.classList.toggle('hidden', !!game.hideHud);
    // Hotbar
    const v = game.inventory.version;
    if (c.invVersion !== v || c.selected !== game.selected) {
      c.invVersion = v;
      if (c.selected !== game.selected) this._showItemName(game);
      c.selected = game.selected;
      for (let i = 0; i < 9; i++) this._renderSlot(this.slots[i], game.inventory.get(i), i === game.selected);
      this.inv.refresh();
    }
    // Bars
    const s = game.survival;
    const hp = Math.ceil(s.health), food = Math.ceil(s.food);
    if (c.hp !== hp || c.flash !== (s.hurtFlash > 0)) {
      c.hp = hp; c.flash = s.hurtFlash > 0;
      this._heartImgs.forEach((img, i) => {
        const v2 = hp - i * 2;
        img.src = v2 >= 2 ? this.icons16.heart : v2 === 1 ? this.icons16.heartHalf : this.icons16.heartEmpty;
      });
      this.hearts.classList.toggle('flash', c.flash);
    }
    if (c.food !== food) {
      c.food = food;
      this._foodImgs.forEach((img, i) => {
        const v2 = food - (9 - i) * 2;
        img.src = v2 >= 2 ? this.icons16.food : v2 === 1 ? this.icons16.foodHalf : this.icons16.foodEmpty;
      });
    }
    const bubbles = game.player.eyeIn === 'water' || s.air < s.cfg.maxAirTicks ? Math.max(0, Math.ceil((s.air / s.cfg.maxAirTicks) * 10)) : -1;
    if (c.air !== bubbles) {
      c.air = bubbles;
      this.air.style.visibility = bubbles >= 0 ? 'visible' : 'hidden';
      this._airImgs.forEach((img, i) => { img.style.visibility = (9 - i) < bubbles ? 'visible' : 'hidden'; });
    }
    this.overlayWater.classList.toggle('show', game.player.eyeIn === 'water');
    this.overlayHurt.style.opacity = String(Math.min(0.5, s.hurtFlash * 0.5));
    // Messages
    if (this._toastTimer > 0) { this._toastTimer -= dt; if (this._toastTimer <= 0) this.toastEl.classList.remove('show'); }
    if (this._nameTimer > 0) { this._nameTimer -= dt; if (this._nameTimer <= 0) this.itemName.classList.remove('show'); }
    // Debug
    if (this.settings.showFps) {
      const p = game.player;
      const biome = game.generator.biomeAt(Math.floor(p.x), Math.floor(p.z));
      const st = game.view?.renderer.stats ?? {};
      const text = `${fps} fps · ${st.calls ?? 0} draws · ${game.world.chunks.size} chunks\n`
        + `XYZ ${p.x.toFixed(1)} ${p.y.toFixed(1)} ${p.z.toFixed(1)}\n`
        + `${biome.label[this.i18n.lang] ?? biome.name} · ${this.t('msg.day', { n: game.day })} ${String(Math.floor(game.timeOfDay * 24 + 6) % 24).padStart(2, '0')}:00\n`
        + `${game.entities.list.length} entities`;
      if (text !== c.debug) { c.debug = text; this.debug.textContent = text; }
      this.debug.style.display = 'block';
    } else this.debug.style.display = 'none';
  }

  _showItemName(game) {
    const s = game.inventory.get(game.selected);
    if (!s) { this.itemName.classList.remove('show'); return; }
    this.itemName.textContent = this.items.label(s.id, this.i18n.lang);
    this.itemName.classList.add('show');
    this._nameTimer = 2;
  }

  /** Fills a slot element with an item stack. */
  _renderSlot(el, s, selected) {
    el.classList.toggle('selected', !!selected);
    const img = el.querySelector('.icon');
    const count = el.querySelector('.count');
    const dura = el.querySelector('.dura');
    if (!s) {
      img.style.visibility = 'hidden';
      count.textContent = '';
      dura.style.display = 'none';
      el.title = '';
      return;
    }
    const url = this.icons.url(s.id);
    if (img.getAttribute('src') !== url) img.src = url;
    img.style.visibility = 'visible';
    count.textContent = s.count > 1 ? String(s.count) : '';
    const item = this.items.get(s.id);
    if (item?.tool && s.damage > 0) {
      const f = 1 - s.damage / item.tool.durability;
      dura.style.display = 'block';
      const bar = dura.firstChild;
      bar.style.width = `${Math.max(0, f) * 100}%`;
      bar.style.background = `hsl(${Math.round(f * 120)}, 90%, 45%)`;
    } else dura.style.display = 'none';
    el.title = this.items.label(s.id, this.i18n.lang);
  }
}
