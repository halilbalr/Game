/**
 * Unified input for touch screens and keyboard/mouse.
 *
 * Touch layout (mobile "split controls" with a crosshair):
 *   - left half: floating joystick (pushing it to the rim sprints)
 *   - right half: drag to look, tap to use/place/attack, hold to break
 *   - buttons: jump (double-tap to fly in creative), sneak toggle, and
 *     fly up/down while flying
 *
 * Desktop: WASD, mouse look (pointer lock), left = break/attack,
 * right = use/place, Space, Shift, Ctrl (sprint), E, Q, 1-9, wheel, Esc.
 */

export class Controls {
  /**
   * @param {object} opts
   * @param {HTMLElement} opts.layer element receiving touch input (covers the screen)
   * @param {HTMLCanvasElement} opts.canvas game canvas (pointer lock target)
   * @param {object} opts.settings live settings object (sensitivity, invertY, ...)
   * @param {object} opts.cfg "controls" section of data/ui.json
   */
  constructor({ layer, canvas, settings, cfg }) {
    this.layer = layer;
    this.canvas = canvas;
    this.settings = settings;
    this.cfg = cfg;
    this.enabled = false;
    this.keys = new Set();
    this.lookDX = 0;
    this.lookDY = 0;
    this.joy = { id: null, x0: 0, y0: 0, x: 0, y: 0 };
    this.look = new Map();
    this.state = { forward: 0, strafe: 0, jump: false, sneak: false, sprint: false, breakHeld: false };
    this.pressed = new Set();
    this.sneakToggle = false;
    this.touchJump = false;
    this.mouseBreak = false;
    this.mouseUse = false;
    this.wheel = 0;
    this.touchMode = settings.touchControls === 'on' || (settings.touchControls !== 'off'
      && (navigator.maxTouchPoints > 0 || 'ontouchstart' in window));
    this._buildTouchUI();
    this._bind();
  }

  _el(tag, cls, parent, text) {
    const e = document.createElement(tag);
    e.className = cls;
    if (text) e.textContent = text;
    parent.appendChild(e);
    return e;
  }

  _buildTouchUI() {
    const L = this.layer;
    this.joyBase = this._el('div', 'joy-base', L);
    this.joyKnob = this._el('div', 'joy-knob', this.joyBase);
    this.btnJump = this._el('div', 'tbtn tbtn-jump', L);
    this.btnJump.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 5l7 8h-4v6H9v-6H5z"/></svg>';
    this.btnSneak = this._el('div', 'tbtn tbtn-sneak', L);
    this.btnSneak.innerHTML = '<svg viewBox="0 0 24 24"><circle cx="12" cy="7" r="3"/><path d="M8 21l2-7-3-2 3-3h4l3 3-3 2 2 7z"/></svg>';
    this.btnDown = this._el('div', 'tbtn tbtn-down', L);
    this.btnDown.innerHTML = '<svg viewBox="0 0 24 24"><path d="M12 19l-7-8h4V5h6v6h4z"/></svg>';
    this.layer.classList.toggle('touch-on', this.touchMode);
  }

  _bind() {
    const L = this.layer;
    const opt = { passive: false };
    L.addEventListener('touchstart', (e) => this._touchStart(e), opt);
    L.addEventListener('touchmove', (e) => this._touchMove(e), opt);
    L.addEventListener('touchend', (e) => this._touchEnd(e), opt);
    L.addEventListener('touchcancel', (e) => this._touchEnd(e), opt);

    const hold = (btn, on, off) => {
      btn.addEventListener('touchstart', (e) => { e.preventDefault(); e.stopPropagation(); btn.classList.add('down'); on(); }, opt);
      const up = (e) => { e.preventDefault(); e.stopPropagation(); btn.classList.remove('down'); off?.(); };
      btn.addEventListener('touchend', up, opt);
      btn.addEventListener('touchcancel', up, opt);
    };
    hold(this.btnJump, () => { this.touchJump = true; }, () => { this.touchJump = false; });
    hold(this.btnDown, () => { this.touchDown = true; }, () => { this.touchDown = false; });
    hold(this.btnSneak, () => {
      this.sneakToggle = !this.sneakToggle;
      this.btnSneak.classList.toggle('active', this.sneakToggle);
    });

    window.addEventListener('keydown', (e) => this._key(e, true));
    window.addEventListener('keyup', (e) => this._key(e, false));
    window.addEventListener('blur', () => { this.keys.clear(); this.mouseBreak = false; this.mouseUse = false; });
    this.canvas.addEventListener('mousedown', (e) => {
      if (!this.enabled || this.touchMode) return;
      if (document.pointerLockElement !== this.canvas) {
        this.requestPointerLock();
        return;
      }
      if (e.button === 0) { this.mouseBreak = true; this.pressed.add('attack'); }
      if (e.button === 2) { this.mouseUse = true; this.pressed.add('use'); }
      if (e.button === 1) this.pressed.add('pick');
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouseBreak = false;
      if (e.button === 2) this.mouseUse = false;
    });
    window.addEventListener('mousemove', (e) => {
      if (this.enabled && document.pointerLockElement === this.canvas) {
        this.lookDX += e.movementX * this.cfg.mouseScale;
        this.lookDY += e.movementY * this.cfg.mouseScale;
      }
    });
    this.canvas.addEventListener('contextmenu', (e) => e.preventDefault());
    window.addEventListener('wheel', (e) => { if (this.enabled) this.wheel += Math.sign(e.deltaY); }, { passive: true });
    document.addEventListener('pointerlockchange', () => {
      if (this.enabled && !this.touchMode && document.pointerLockElement !== this.canvas) this.pressed.add('pause');
    });
  }

  requestPointerLock() {
    if (this.touchMode) return;
    try {
      const p = this.canvas.requestPointerLock?.();
      if (p && p.catch) p.catch(() => {});
    } catch { /* not supported */ }
  }

  exitPointerLock() {
    if (document.pointerLockElement) document.exitPointerLock();
  }

  /** Enables gameplay input (false while menus are open). */
  setEnabled(on) {
    this.enabled = on;
    this.layer.classList.toggle('active', on && this.touchMode);
    if (!on) {
      this.joy.id = null;
      this.joyBase.classList.remove('show');
      this.look.clear();
      this.mouseBreak = false;
      this.mouseUse = false;
      this.touchJump = false;
      this.touchDown = false;
      this.keys.clear();
    }
  }

  setFlying(flying) {
    this.layer.classList.toggle('flying', flying);
  }

  _key(e, down) {
    const code = e.code;
    if (down && !e.repeat) {
      if (code === 'KeyE') this.pressed.add('inventory');
      if (code === 'Escape') this.pressed.add('pause');
      if (code === 'KeyQ') this.pressed.add('drop');
      if (code === 'F3') { this.pressed.add('debug'); e.preventDefault(); }
      if (code === 'F1') { this.pressed.add('hideHud'); e.preventDefault(); }
      if (code === 'KeyW') {
        const now = performance.now();
        if (now - (this._lastW ?? 0) < 300) this.pressed.add('sprintTap');
        this._lastW = now;
      }
      if (/^Digit[1-9]$/.test(code)) this.pressed.add(`slot${Number(code.slice(5)) - 1}`);
    }
    if (!this.enabled) return;
    if (down) this.keys.add(code); else this.keys.delete(code);
    if (['Space', 'ArrowUp', 'ArrowDown', 'Tab'].includes(code)) e.preventDefault();
  }

  _isOnButton(t) {
    const el = document.elementFromPoint(t.clientX, t.clientY);
    return el && el.closest('.tbtn, .hud-hotbar, .hud-btn');
  }

  _touchStart(e) {
    if (!this.enabled) return;
    e.preventDefault();
    const w = window.innerWidth;
    for (const t of e.changedTouches) {
      if (this._isOnButton(t)) continue;
      if (t.clientX < w * this.cfg.joystickZone && this.joy.id === null) {
        this.joy.id = t.identifier;
        this.joy.x0 = t.clientX; this.joy.y0 = t.clientY;
        this.joy.x = t.clientX; this.joy.y = t.clientY;
        this.joyBase.style.left = `${t.clientX}px`;
        this.joyBase.style.top = `${t.clientY}px`;
        this.joyBase.classList.add('show');
        this.joyKnob.style.transform = 'translate(-50%, -50%)';
      } else {
        this.look.set(t.identifier, { x: t.clientX, y: t.clientY, sx: t.clientX, sy: t.clientY, t0: performance.now(), moved: 0, holding: false });
      }
    }
  }

  _touchMove(e) {
    if (!this.enabled) return;
    e.preventDefault();
    for (const t of e.changedTouches) {
      if (t.identifier === this.joy.id) {
        this.joy.x = t.clientX; this.joy.y = t.clientY;
        const r = this.cfg.joystickRadius;
        let dx = this.joy.x - this.joy.x0, dy = this.joy.y - this.joy.y0;
        const len = Math.hypot(dx, dy);
        if (len > r) { dx = (dx / len) * r; dy = (dy / len) * r; }
        this.joyKnob.style.transform = `translate(calc(-50% + ${dx}px), calc(-50% + ${dy}px))`;
        continue;
      }
      const l = this.look.get(t.identifier);
      if (!l) continue;
      const dx = t.clientX - l.x, dy = t.clientY - l.y;
      l.x = t.clientX; l.y = t.clientY;
      l.moved = Math.max(l.moved, Math.hypot(t.clientX - l.sx, t.clientY - l.sy));
      this.lookDX += dx * this.cfg.touchScale;
      this.lookDY += dy * this.cfg.touchScale;
    }
  }

  _touchEnd(e) {
    for (const t of e.changedTouches) {
      if (t.identifier === this.joy.id) {
        this.joy.id = null;
        this.joyBase.classList.remove('show');
        continue;
      }
      const l = this.look.get(t.identifier);
      if (!l) continue;
      this.look.delete(t.identifier);
      const dt = performance.now() - l.t0;
      if (!l.holding && dt < this.cfg.tapMaxMs && l.moved < this.cfg.tapMaxMove) this.pressed.add('tap');
    }
  }

  /** True when the given one-shot action was triggered since the last frame. */
  took(action) {
    if (this.pressed.has(action)) { this.pressed.delete(action); return true; }
    return false;
  }

  /**
   * Samples continuous input for this frame.
   * @param {number} holdMs hold duration that turns a touch into "break"
   */
  sample(holdMs) {
    const k = this.keys;
    const s = this.state;
    let f = 0, st = 0;
    if (k.has('KeyW') || k.has('ArrowUp')) f += 1;
    if (k.has('KeyS') || k.has('ArrowDown')) f -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) st += 1;
    if (k.has('KeyA') || k.has('ArrowLeft')) st -= 1;
    let sprint = k.has('ControlLeft') || k.has('ControlRight') || this._sprintLatch;
    if (this.joy.id !== null) {
      const r = this.cfg.joystickRadius;
      let dx = (this.joy.x - this.joy.x0) / r, dy = (this.joy.y - this.joy.y0) / r;
      const len = Math.hypot(dx, dy);
      if (len > 1) { dx /= len; dy /= len; }
      const dead = this.cfg.joystickDeadzone;
      if (len > dead) { f = -dy; st = dx; }
      if (-dy > this.cfg.sprintThreshold) sprint = true;
    }
    if (this.took('sprintTap')) this._sprintLatch = true;
    if (f <= 0) this._sprintLatch = false;
    s.forward = f; s.strafe = st;
    s.jump = k.has('Space') || this.touchJump;
    s.sneak = k.has('ShiftLeft') || k.has('ShiftRight') || this.sneakToggle || this.touchDown;
    s.sprint = sprint;
    let breakHeld = this.mouseBreak;
    const now = performance.now();
    for (const l of this.look.values()) {
      if (!l.holding && now - l.t0 >= holdMs && l.moved < this.cfg.holdMaxMove) l.holding = true;
      if (l.holding) breakHeld = true;
    }
    s.breakHeld = breakHeld;
    s.useHeld = this.mouseUse;
    const dx = this.lookDX, dy = this.lookDY;
    this.lookDX = 0; this.lookDY = 0;
    const sens = this.settings.sensitivity;
    s.lookX = dx * sens;
    s.lookY = dy * sens * (this.settings.invertY ? -1 : 1);
    s.wheel = this.wheel; this.wheel = 0;
    return s;
  }
}
