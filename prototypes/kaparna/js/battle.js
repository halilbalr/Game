// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Striden: simulering (vägfinning, trupper, försvar, projektiler, drycker, stjärnor, byte) + ritning.
(function () {
  const K = window.K, D = K.DATA, G = K.gfx, A = K.art, P = G.P;
  const SQ2 = Math.SQRT2;
  const NB = [[1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1], [1, 1, SQ2], [1, -1, SQ2], [-1, 1, SQ2], [-1, -1, SQ2]];
  const B_HEIGHT = { brygga: 112, kanon: 26, vatten: 38, utkik: 100, morsare: 24, vaktkur: 46, container: 26, kista: 30, fisklada: 26, ventil: 30, skorsten: 74, kran: 62, livbat: 24, radar: 60, helipad: 6, pool: 10 };

  const rand = Math.random;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const dist = (ax, ay, bx, by) => Math.hypot(ax - bx, ay - by);
  function distRect(px, py, x0, y0, x1, y1) {
    const dx = Math.max(x0 - px, 0, px - x1), dy = Math.max(y0 - py, 0, py - y1);
    return Math.hypot(dx, dy);
  }
  function closestRect(px, py, x0, y0, x1, y1) { return [clamp(px, x0, x1), clamp(py, y0, y1)]; }

  // Minimal binärheap för Dijkstra
  class Heap {
    constructor() { this.a = []; }
    push(d, t) {
      const a = this.a; a.push([d, t]); let i = a.length - 1;
      while (i > 0) { const p = (i - 1) >> 1; if (a[p][0] <= a[i][0]) break; [a[p], a[i]] = [a[i], a[p]]; i = p; }
    }
    pop() {
      const a = this.a, top = a[0], last = a.pop();
      if (a.length) {
        a[0] = last; let i = 0;
        for (;;) {
          const l = i * 2 + 1, r = l + 1; let m = i;
          if (l < a.length && a[l][0] < a[m][0]) m = l;
          if (r < a.length && a[r][0] < a[m][0]) m = r;
          if (m === i) break; [a[m], a[i]] = [a[i], a[m]]; i = m;
        }
      }
      return top;
    }
    get size() { return this.a.length; }
  }

  class Battle {
    constructor(def, save, opts = {}) {
      this.def = def; this.save = save; this.headless = !!opts.headless;
      const sh = (this.sh = K.ship.build(def));
      this.W = sh.W; this.H = sh.H;
      this.buildings = sh.buildings; this.walls = sh.walls;
      this.units = []; this.skiffs = []; this.proj = []; this.fx = []; this.spells = []; this.events = []; this.marks = [];
      this.time = 0; this.elapsed = 0; this.started = false; this.ended = false; this.finishAt = -1;
      this.maxTime = 150; this.version = 0; this.fields = new Map(); this.uid = 1;
      this.inspect = null; this.deployFail = null;

      const replay = !!save.captured[def.id];
      this.replay = replay;
      this.lootTotal = Math.round(def.loot * (replay ? 0.7 : 1));
      this.captureBonus = replay ? 0 : Math.round(def.loot * 0.25);
      let wsum = 0;
      for (const b of this.buildings) wsum += b.def.loot || 0;
      for (const b of this.buildings) {
        b.lootTotal = b.def.loot ? (this.lootTotal * b.def.loot) / wsum : 0;
        b.lootLeft = b.lootTotal;
        b.alive = true; b.cd = rand(); b.target = null; b.flash = 0; b.lastHit = -99; b.recoil = 0; b.atkAnim = 0;
        b.ang = (b.seed % 628) / 100; b.alarm = false; b.spawned = 0; b.spawnT = 0;
        b.cx = b.x + b.w / 2; b.cy = b.y + b.h / 2;
      }
      for (const w of this.walls) w.flash = 0;
      this.loot = 0; this.coinAcc = 0; this.coinStep = Math.max(8, this.lootTotal / 70);
      this.total = this.buildings.length; this.destroyed = 0; this.pct = 0; this.stars = 0; this.bridgeDown = false;

      this.pool = { troops: Object.assign({}, save.army), spells: Object.assign({}, save.spells), hero: 1 };
      this.initialPool = JSON.parse(JSON.stringify(this.pool));
      this.heroUnit = null; this.abilityUsed = false;
      this.selected = this.firstAvailable();
      this.waves = [];
      if (!this.headless) {
        const r = G.rng(def.tier * 77);
        for (let i = -16; i < this.W + 16; i += 2.2) for (let j = -14; j < this.H + 14; j += 2.2) this.waves.push([i + r() * 1.6, j + r() * 1.6, r() * 6.28]);
      }
    }

    firstAvailable() {
      for (const k of Object.keys(D.troops)) if (this.pool.troops[k] > 0) return k;
      if (this.pool.hero) return 'kapten';
      for (const k of Object.keys(D.spells)) if (this.pool.spells[k] > 0) return k;
      return null;
    }
    remaining(key) {
      if (key === 'kapten') return this.pool.hero;
      if (D.spells[key]) return this.pool.spells[key] || 0;
      return this.pool.troops[key] || 0;
    }

    // ---------- rutnät ----------
    passable(t) { const sh = this.sh; return sh.deck[t] === 1 && (sh.occ[t] < 0 || !this.buildings[sh.occ[t]].alive); }
    wallAlive(t) { const i = this.sh.wallAt[t]; return i >= 0 && this.walls[i].alive; }
    walkable(t) { return this.passable(t) && !this.wallAlive(t); }
    walkableAt(x, y) {
      if (x < 0 || y < 0 || x >= this.W || y >= this.H) return false;
      return this.walkable((y | 0) * this.W + (x | 0));
    }

    goalTiles(tg) {
      const W = this.W, H = this.H, out = [];
      const x0 = tg.isWall ? tg.x : tg.x, y0 = tg.y, x1 = tg.isWall ? tg.x + 1 : tg.x + tg.w, y1 = tg.isWall ? tg.y + 1 : tg.y + tg.h;
      for (let y = y0 - 1; y <= y1; y++) for (let x = x0 - 1; x <= x1; x++) {
        if (x >= x0 && x < x1 && y >= y0 && y < y1) continue;
        if (x < 0 || y < 0 || x >= W || y >= H) continue;
        const t = y * W + x;
        if (this.passable(t)) out.push(t);
      }
      return out;
    }

    field(tg) {
      const key = tg.isWall ? 'w' + (tg.y * this.W + tg.x) : 'b' + tg.id;
      const c = this.fields.get(key);
      if (c && c.v === this.version) return c.d;
      const W = this.W, H = this.H, N = W * H;
      const d = new Float32Array(N).fill(Infinity);
      const hp = new Heap();
      for (const g of this.goalTiles(tg)) { d[g] = 0; hp.push(0, g); }
      const pen = D.wallPenalty;
      while (hp.size) {
        const [dd, t] = hp.pop();
        if (dd > d[t]) continue;
        const tx = t % W, ty = (t / W) | 0;
        const enter = this.wallAlive(t) ? pen : 0;
        for (const [ox, oy, len] of NB) {
          const nx = tx + ox, ny = ty + oy;
          if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
          const n = ny * W + nx;
          if (!this.passable(n)) continue;
          if (ox && oy && (!this.walkable(ty * W + nx) || !this.walkable(ny * W + tx))) continue;
          const nd = dd + len + enter;
          if (nd < d[n]) { d[n] = nd; hp.push(nd, n); }
        }
      }
      this.fields.set(key, { v: this.version, d });
      return d;
    }

    nextStep(u, d) {
      const W = this.W, tx = u.x | 0, ty = u.y | 0;
      let best = -1, bv = Infinity;
      const pen = D.wallPenalty;
      for (const [ox, oy, len] of NB) {
        const nx = tx + ox, ny = ty + oy;
        if (nx < 0 || ny < 0 || nx >= W || ny >= this.H) continue;
        const n = ny * W + nx;
        if (!this.passable(n)) continue;
        if (ox && oy && (!this.walkable(ty * W + nx) || !this.walkable(ny * W + tx))) continue;
        const v = d[n] + len + (this.wallAlive(n) ? pen : 0);
        if (v < bv) { bv = v; best = n; }
      }
      return best;
    }

    // ---------- skapa enheter ----------
    level(key) { return (this.save.levels && this.save.levels[key]) || 1; }
    makeUnit(key, side, x, y) {
      let def, mul;
      if (side === 'e') { def = D.guard; mul = this.sh.hpMul; }
      else { def = key === 'kapten' ? D.hero : D.troops[key]; mul = 1 + D.levelScale * (this.level(key) - 1); }
      const dmul = side === 'e' ? this.sh.dmgMul : mul;
      const skins = side === 'e' ? A.GUARD_SKINS : A.SKINS;
      const u = {
        id: this.uid++, isUnit: true, type: key, side, def, x, y, hp: def.hp * mul, maxHp: def.hp * mul, dmg: def.dmg * dmul,
        atkInt: def.atk, range: def.range, speed: def.speed, state: 'deck', target: null, wallTarget: null, cd: 0.2 + rand() * 0.4,
        facing: 1, walk: rand() * 6, moving: false, atkAnim: 0, flash: 0, slow: 0, rage: 0, air: 0, squash: 1, land: 0,
        skin: skins[(rand() * skins.length) | 0], off: [(rand() - 0.5) * 0.5, (rand() - 0.5) * 0.5], scan: rand() * 0.3, skip: new Set(), skipV: 0,
        pend: null, home: null,
      };
      return u;
    }

    // Placera trupp från vattnet (x, y på vattenplanet)
    deploy(key, wx, wy) {
      if (this.ended) return 'ended';
      if (this.remaining(key) <= 0) return 'empty';
      const poly = this.sh.poly;
      if (K.ship.inPoly(poly, wx, wy)) {
        const c = K.ship.closestOnPoly(poly, wx, wy);
        wx = c.x + c.nx * 0.7; wy = c.y + c.ny * 0.7;
      }
      const c = K.ship.closestOnPoly(poly, wx, wy);
      const tx = c.x + c.nx * 0.45, ty = c.y + c.ny * 0.45;
      // närmaste gångbara däcksruta
      let land = null, bd = Infinity;
      for (let y = 0; y < this.H; y++) for (let x = 0; x < this.W; x++) {
        const t = y * this.W + x;
        if (!this.walkable(t)) continue;
        const d = (x + 0.5 - tx) ** 2 + (y + 0.5 - ty) ** 2;
        if (d < bd) { bd = d; land = [x + 0.5, y + 0.5]; }
      }
      if (!land) return 'full';
      if (key === 'kapten') this.pool.hero = 0; else this.pool.troops[key]--;
      const u = this.makeUnit(key, 'p', wx, wy);
      u.state = 'boat';
      if (key === 'kapten') this.heroUnit = u;
      const sk = { x: wx, y: wy, tx, ty, ang: Math.atan2(ty - wy, tx - wx), state: 'go', unit: u, t: 0, seed: rand() * 9, moving: true, land: [land[0] + (rand() - 0.5) * 0.4, land[1] + (rand() - 0.5) * 0.4], color: ['#2f7fd1', '#3aa357', '#e8b021', '#e0392b'][(rand() * 4) | 0] };
      u.x = sk.x; u.y = sk.y;
      this.skiffs.push(sk);
      this.units.push(u);
      this.start();
      this.sound('deploy');
      if (this.remaining(key) <= 0 && this.selected === key) this.selected = this.firstAvailable();
      return 'ok';
    }

    castSpell(key, x, y) {
      if (this.ended || this.remaining(key) <= 0) return 'empty';
      const sd = D.spells[key];
      this.pool.spells[key]--;
      const lv = this.level(key);
      this.spells.push({ type: key, x, y, r: sd.radius, dur: sd.duration, t: 0, tick: 0.45, color: sd.color, lv, hps: sd.hps ? sd.hps * (1 + D.levelScale * (lv - 1)) : 0, dmgMul: sd.dmgMul ? sd.dmgMul + 0.1 * (lv - 1) : 1, spdMul: sd.spdMul || 1 });
      this.start();
      this.sound(key === 'lakning' ? 'heal' : 'drum');
      if (this.remaining(key) <= 0 && this.selected === key) this.selected = this.firstAvailable();
      return 'ok';
    }

    useAbility() {
      const h = this.heroUnit;
      if (!h || h.hp <= 0 || h.state !== 'deck' || this.abilityUsed) return false;
      this.abilityUsed = true;
      const ab = D.hero.ability;
      h.hp = Math.min(h.maxHp, h.hp + h.maxHp * ab.healPct);
      h.rage = ab.rage; h.rageMul = 1.6; h.rageSpd = 1.4; h.yellT = 1.2;
      for (let i = 0; i < ab.summon; i++) {
        const a = (i / ab.summon) * Math.PI * 2;
        let x = h.x + Math.cos(a) * 0.9, y = h.y + Math.sin(a) * 0.9;
        if (!this.walkableAt(x, y)) { x = h.x; y = h.y; }
        const u = this.makeUnit('kampe', 'p', x, y);
        u.squash = 1.4; u.land = 0.25;
        this.units.push(u);
        this.fxAdd('poof', x, y, 10, { size: 10, color: '#ffffff', life: 0.5 });
      }
      this.fxAdd('ring', h.x, h.y, 0, { size: 40, color: '#ffcf3a', life: 0.6 });
      this.sound('roar');
      return true;
    }

    start() { if (!this.started) { this.started = true; this.events.push({ type: 'start' }); } }

    // ---------- skada ----------
    damage(tg, amt) {
      if (tg.isUnit) {
        if (tg.hp <= 0) return;
        tg.hp -= amt; tg.flash = 0.12;
        if (tg.hp <= 0) this.killUnit(tg);
        return;
      }
      if (tg.isWall) {
        if (!tg.alive) return;
        tg.hp -= amt; tg.flash = 0.12;
        if (tg.hp <= 0) {
          tg.alive = false; this.version++;
          for (let i = 0; i < 6; i++) this.fxAdd('debris', tg.x + 0.5, tg.y + 0.5, 10, { vx: (rand() - 0.5) * 4, vy: (rand() - 0.5) * 4, vz: 80 + rand() * 80, color: i % 2 ? '#f2c14e' : '#59616b', size: 4, life: 1 });
          this.fxAdd('dust', tg.x + 0.5, tg.y + 0.5, 8, { size: 12, color: '#d9d2c3', life: 0.7 });
          this.sound('wall');
        }
        return;
      }
      if (!tg.alive) return;
      const real = Math.min(tg.hp, amt);
      tg.hp -= real; tg.flash = 0.12; tg.lastHit = this.time;
      if (tg.lootTotal > 0) {
        const take = Math.min(tg.lootLeft, (tg.lootTotal * real) / tg.maxHp);
        tg.lootLeft -= take; this.addLoot(take, tg);
      }
      if (tg.hp <= 0.001) this.destroyBuilding(tg);
    }

    addLoot(v, b) {
      this.loot += v; this.coinAcc += v;
      while (this.coinAcc >= this.coinStep) {
        this.coinAcc -= this.coinStep;
        this.events.push({ type: 'coin', x: b.cx, y: b.cy, z: (B_HEIGHT[b.type] || 20) * 0.6 });
        this.fxAdd('coin', b.cx + (rand() - 0.5), b.cy + (rand() - 0.5), 20, { vx: (rand() - 0.5) * 2, vy: (rand() - 0.5) * 2, vz: 120 + rand() * 60, life: 0.9, rot: 0, spin: 12 });
        this.sound('coin');
      }
    }

    destroyBuilding(b) {
      b.alive = false; b.hp = 0;
      if (b.lootLeft > 0) { const v = b.lootLeft; b.lootLeft = 0; this.addLoot(v, b); }
      this.destroyed++; this.version++; this.layerVer = (this.layerVer || 0) + 1;
      const big = b.w * b.h;
      for (let i = 0; i < 6 + big * 2; i++) {
        this.fxAdd('debris', b.x + rand() * b.w, b.y + rand() * b.h, 15 + rand() * 20, { vx: (rand() - 0.5) * 5, vy: (rand() - 0.5) * 5, vz: 100 + rand() * 120, color: ['#8d99a6', '#6e6a64', '#c8402e', '#e3e6ea'][(rand() * 4) | 0], size: 4 + rand() * 4, life: 1.2, rot: rand() * 6 });
      }
      for (let i = 0; i < 4 + big; i++) this.fxAdd('dust', b.x + rand() * b.w, b.y + rand() * b.h, 6 + rand() * 20, { size: 14 + rand() * 12, color: '#d9d2c3', life: 1 + rand() * 0.6, vz: 20 });
      this.fxAdd('flash', b.cx, b.cy, 20, { size: 30 + big * 6, life: 0.3 });
      this.events.push({ type: 'shake', amt: b.type === 'brygga' ? 14 : 6 });
      this.sound(b.type === 'brygga' ? 'boom' : 'collapse');
      if (b.type === 'brygga') { this.bridgeDown = true; this.events.push({ type: 'capture' }); }
      this.updateStars();
    }

    updateStars() {
      this.pct = Math.floor((this.destroyed / this.total) * 100);
      const s = (this.pct >= 50 ? 1 : 0) + (this.bridgeDown ? 1 : 0) + (this.pct >= 100 ? 1 : 0);
      while (this.stars < s) { this.stars++; this.events.push({ type: 'star', n: this.stars }); this.sound('star'); }
      if (this.pct >= 100 && this.finishAt < 0) this.finishAt = this.time + 1.6;
    }

    killUnit(u) {
      u.hp = 0; u.state = 'dead';
      this.fxAdd('poof', u.x, u.y, 12, { size: 12, color: '#ffffff', life: 0.5 });
      this.fxAdd('skull', u.x, u.y, 4, { life: 1.6, vz: 0 });
      this.sound(u.side === 'p' ? 'die' : 'ko');
    }

    splash(x, y, r, dmg, side, opts = {}) {
      for (const u of this.units) {
        if (u.hp <= 0 || u.state !== 'deck' || u.side === side) continue;
        if (dist(u.x, u.y, x, y) <= r) { this.damage(u, dmg); if (opts.slow) u.slow = 0.8; }
      }
      if (side === 'p') {
        for (const b of this.buildings) if (b.alive && distRect(x, y, b.x, b.y, b.x + b.w, b.y + b.h) <= r) this.damage(b, dmg * (opts.bMul || 1));
        for (const w of this.walls) if (w.alive && distRect(x, y, w.x, w.y, w.x + 1, w.y + 1) <= r) this.damage(w, dmg * (opts.wMul || 1));
      }
    }

    // ---------- effekter ----------
    fxAdd(type, x, y, z, o = {}) {
      if (this.headless) return;
      if (this.fx.length > 700) return;
      const life = o.life || 0.6;
      this.fx.push({ type, x, y, z, vx: o.vx || 0, vy: o.vy || 0, vz: o.vz || 0, life, max: life, size: o.size || 6, color: o.color, rot: o.rot || 0, spin: o.spin || 0, g: o.g ?? (type === 'debris' || type === 'coin' || type === 'water' ? 380 : 0), alpha: o.alpha, floor: o.floor ?? 0 });
    }
    sound(name) {
      if (this.headless || !K.sfx) return;
      K.sfx.play(name);
      const buzz = { collapse: 16, boom: 28, star: 40, roar: 50, die: 6 }[name];
      if (buzz) K.sfx.buzz(buzz);
    }

    // ---------- uppdatering ----------
    update(dt) {
      let left = Math.min(dt, 0.1);
      while (left > 1e-6) { const s = Math.min(left, 1 / 60); this.step(s); left -= s; }
    }

    step(dt) {
      this.time += dt;
      if (this.started && !this.ended) this.elapsed += dt;
      for (const b of this.buildings) { b.flash = Math.max(0, b.flash - dt); b.recoil = Math.max(0, b.recoil - dt * 4); b.atkAnim = Math.max(0, b.atkAnim - dt); }
      for (const w of this.walls) w.flash = Math.max(0, w.flash - dt);
      if (!this.ended) {
        this.updateSkiffs(dt);
        for (const u of this.units) if (u.hp > 0) { if (u.side === 'p') this.updateUnit(u, dt); else this.updateGuard(u, dt); }
        for (const b of this.buildings) if (b.alive) this.updateDefense(b, dt);
        this.updateProjectiles(dt);
        this.updateSpells(dt);
        this.ambient(dt);
      } else this.updateSkiffs(dt);
      this.units = this.units.filter((u) => u.hp > 0 || u.state !== 'dead');
      this.updateFx(dt);
      if (this.inspect) { this.inspect.t -= dt; if (this.inspect.t <= 0) this.inspect = null; }
      if (this.deployFail) { this.deployFail.t -= dt; if (this.deployFail.t <= 0) this.deployFail = null; }
      if (this.zoneFlash > 0) this.zoneFlash -= dt;
      this.checkEnd();
    }

    ambient(dt) {
      if (this.headless) return;
      for (const b of this.buildings) {
        if (!b.alive) continue;
        const f = b.hp / b.maxHp;
        if (f < 0.55 && rand() < dt * 3) this.fxAdd('smoke', b.cx + (rand() - 0.5) * b.w * 0.6, b.cy + (rand() - 0.5) * b.h * 0.6, (B_HEIGHT[b.type] || 20) * 0.7, { size: 7, color: '#5a5650', vz: 30, life: 1.4, alpha: 0.55 });
        if (f < 0.3 && rand() < dt * 6) this.fxAdd('fire', b.cx + (rand() - 0.5) * b.w * 0.5, b.cy + (rand() - 0.5) * b.h * 0.5, (B_HEIGHT[b.type] || 20) * 0.5, { size: 7, vz: 40, life: 0.6 });
      }
    }

    updateSkiffs(dt) {
      for (const sk of this.skiffs) {
        sk.t += dt;
        const u = sk.unit;
        if (sk.state === 'go') {
          const d = dist(sk.x, sk.y, sk.tx, sk.ty), sp = 8 * dt;
          if (d <= sp) {
            sk.x = sk.tx; sk.y = sk.ty; sk.state = 'wait'; sk.moving = false; sk.t = 0;
            u.state = 'jump'; u.jt = 0; u.j0 = [sk.x, sk.y]; u.j1 = sk.land;
            this.sound('hook');
          } else { sk.x += ((sk.tx - sk.x) / d) * sp; sk.y += ((sk.ty - sk.y) / d) * sp; }
          if (u.state === 'boat') { u.x = sk.x; u.y = sk.y; }
          if (!this.headless && rand() < dt * 20) this.fxAdd('water', sk.x - Math.cos(sk.ang) * 0.7, sk.y - Math.sin(sk.ang) * 0.7, -A.HULL + 2, { size: 2.5, vz: 60, vx: (rand() - 0.5), vy: (rand() - 0.5), life: 0.4, floor: -A.HULL, color: '#ffffff' });
        } else if (sk.state === 'wait') {
          if (sk.t > 1.6) { sk.state = 'leave'; sk.t = 0; sk.moving = true; sk.ang += Math.PI; }
        } else if (sk.state === 'leave') {
          sk.x += Math.cos(sk.ang) * 3 * dt; sk.y += Math.sin(sk.ang) * 3 * dt;
        }
        if (u && u.state === 'jump') {
          u.jt += dt;
          const f = Math.min(1, u.jt / 0.55);
          u.x = u.j0[0] + (u.j1[0] - u.j0[0]) * f; u.y = u.j0[1] + (u.j1[1] - u.j0[1]) * f;
          u.jz = -A.HULL * (1 - f) + Math.sin(f * Math.PI) * 46;
          if (f >= 1) {
            u.state = 'deck'; u.jz = 0; u.squash = 1.35; u.land = 0.22; sk.unit = null;
            this.fxAdd('dust', u.x, u.y, 2, { size: 9, color: '#e8dcc4', life: 0.45 });
          }
        }
      }
      this.skiffs = this.skiffs.filter((s) => !(s.state === 'leave' && s.t > 3));
    }

    pickTarget(u) {
      if (u.skipV !== this.version) { u.skip.clear(); u.skipV = this.version; }
      const pref = u.type === 'kapten' ? 'any' : u.def.target;
      let cands = [];
      if (pref === 'wall') {
        cands = this.walls.filter((w) => w.alive && !u.skip.has('w' + w.x + ',' + w.y));
        if (!cands.length) cands = this.buildings.filter((b) => b.alive && !u.skip.has(b.id));
      } else {
        const all = this.buildings.filter((b) => b.alive && !u.skip.has(b.id));
        if (pref === 'defense') cands = all.filter((b) => b.kind === 'defense');
        else if (pref === 'loot') cands = all.filter((b) => b.lootTotal > 0 && b.lootLeft > 0.5);
        if (!cands.length) cands = all;
      }
      let best = null, bd = Infinity;
      for (const c of cands) {
        const d = c.isWall ? distRect(u.x, u.y, c.x, c.y, c.x + 1, c.y + 1) : distRect(u.x, u.y, c.x, c.y, c.x + c.w, c.y + c.h);
        if (d < bd) { bd = d; best = c; }
      }
      return best;
    }

    moveToward(u, tx, ty, spd, dt) {
      const dx = tx - u.x, dy = ty - u.y, d = Math.hypot(dx, dy);
      if (d < 0.01) { u.moving = false; return; }
      const s = Math.min(d, spd * dt);
      const nx = u.x + (dx / d) * s, ny = u.y + (dy / d) * s;
      if (this.walkableAt(nx, ny)) { u.x = nx; u.y = ny; }
      else if (this.walkableAt(nx, u.y)) u.x = nx;
      else if (this.walkableAt(u.x, ny)) u.y = ny;
      else { u.moving = false; return; }
      u.moving = true;
      u.walk += dt * spd * 7;
      const sdx = G.sdx(dx, dy);
      if (Math.abs(sdx) > 0.05) u.facing = sdx > 0 ? 1 : -1;
    }

    face(u, tx, ty) { const sdx = G.sdx(tx - u.x, ty - u.y); if (Math.abs(sdx) > 0.02) u.facing = sdx > 0 ? 1 : -1; }

    tickTimers(u, dt) {
      u.cd -= dt; u.atkAnim = Math.max(0, u.atkAnim - dt); u.flash = Math.max(0, u.flash - dt);
      u.slow = Math.max(0, u.slow - dt); u.rage = Math.max(0, u.rage - dt); u.yellT = Math.max(0, (u.yellT || 0) - dt);
      if (u.land > 0) { u.land -= dt; u.squash = 1 + Math.max(0, u.land) * 1.5; } else u.squash = 1;
      if (u.pend) {
        u.pend.t -= dt;
        if (u.pend.t <= 0) {
          const p = u.pend; u.pend = null;
          const alive = p.tg.isUnit ? p.tg.hp > 0 : p.tg.alive;
          if (alive) {
            this.damage(p.tg, p.dmg);
            const [hx, hy] = p.tg.isUnit ? [p.tg.x, p.tg.y] : closestRect(u.x, u.y, p.tg.x, p.tg.y, p.tg.x + (p.tg.w || 1), p.tg.y + (p.tg.h || 1));
            for (let i = 0; i < 3; i++) this.fxAdd('spark', hx, hy, 12 + rand() * 8, { vx: (rand() - 0.5) * 6, vy: (rand() - 0.5) * 6, vz: 60 + rand() * 60, life: 0.25 });
            this.sound(u.type === 'bjasse' ? 'thud' : 'hit');
          }
        }
      }
    }

    speedOf(u) {
      let s = u.speed;
      if (u.slow > 0) s *= 0.5;
      if (u.rage > 0) s *= u.rageSpd || 1.4;
      return s;
    }
    dmgOf(u, tg) {
      let d = u.dmg;
      if (u.rage > 0) d *= u.rageMul || 1.6;
      if (u.def.lootMul && tg && tg.lootTotal > 0) d *= u.def.lootMul;
      return d;
    }

    doAttack(u, tg) {
      const tx = tg.isUnit ? tg.x : tg.isWall ? tg.x + 0.5 : tg.cx, ty = tg.isUnit ? tg.y : tg.isWall ? tg.y + 0.5 : tg.cy;
      this.face(u, tx, ty);
      u.moving = false;
      if (u.cd > 0) return;
      u.cd = u.atkInt; u.atkAnim = 0.35;
      if (u.type === 'bombare') { this.explodeBomber(u); return; }
      const dmg = this.dmgOf(u, tg);
      if (u.def.proj) {
        this.proj.push({ kind: 'shot', side: u.side, x: u.x, y: u.y, z: 18, target: tg, dmg, speed: 16, dx: 0, dy: 0, dz: 0 });
        this.sound('shot');
      } else u.pend = { tg, dmg, t: 0.15 };
    }

    explodeBomber(u) {
      const lv = 1 + D.levelScale * (this.level('bombare') - 1);
      const dmg = D.troops.bombare.dmg * lv;
      this.splash(u.x, u.y, D.troops.bombare.splash, dmg, 'p', { wMul: D.troops.bombare.wallMul, bMul: 1 });
      this.fxAdd('flash', u.x, u.y, 14, { size: 46, life: 0.35 });
      for (let i = 0; i < 8; i++) this.fxAdd('smoke', u.x + (rand() - 0.5), u.y + (rand() - 0.5), 10 + rand() * 10, { size: 10, color: '#3b3b44', vz: 40, life: 0.9 });
      this.events.push({ type: 'shake', amt: 7 });
      this.sound('boom');
      u.hp = 0; u.state = 'dead';
    }

    updateUnit(u, dt) {
      if (u.state !== 'deck') return;
      this.tickTimers(u, dt);
      const spd = this.speedOf(u);
      // vakter distraherar (inte bjässar och bombare)
      if (u.type !== 'bjasse' && u.type !== 'bombare') {
        u.scan -= dt;
        if (u.scan <= 0) {
          u.scan = 0.3;
          if (!u.target || !u.target.isUnit) {
            let best = null, bd = 2.4;
            for (const g of this.units) if (g.side === 'e' && g.hp > 0) { const d = dist(g.x, g.y, u.x, u.y); if (d < bd) { bd = d; best = g; } }
            if (best) { u.target = best; u.wallTarget = null; }
          }
        }
      }
      if (u.target && (u.target.isUnit ? u.target.hp <= 0 : !u.target.alive)) { u.target = null; u.wallTarget = null; }
      if (u.wallTarget && !u.wallTarget.alive) u.wallTarget = null;
      if (!u.target) { u.target = this.pickTarget(u); u.wallTarget = null; }
      const tg = u.target;
      if (!tg) { u.moving = false; return; }
      if (tg.isUnit) {
        if (dist(u.x, u.y, tg.x, tg.y) <= u.range + 0.3) this.doAttack(u, tg);
        else this.moveToward(u, tg.x, tg.y, spd, dt);
        return;
      }
      const rx1 = tg.isWall ? tg.x + 1 : tg.x + tg.w, ry1 = tg.isWall ? tg.y + 1 : tg.y + tg.h;
      const dr = distRect(u.x, u.y, tg.x, tg.y, rx1, ry1);
      if (dr <= u.range) { this.doAttack(u, tg); return; }
      if (u.wallTarget) {
        const w = u.wallTarget;
        if (distRect(u.x, u.y, w.x, w.y, w.x + 1, w.y + 1) <= Math.max(u.range, 0.6)) this.doAttack(u, w);
        else this.moveToward(u, w.x + 0.5, w.y + 0.5, spd, dt);
        return;
      }
      const d = this.field(tg);
      const t = (u.y | 0) * this.W + (u.x | 0);
      if (!isFinite(d[t])) { u.skip.add(tg.isWall ? 'w' + tg.x + ',' + tg.y : tg.id); u.target = null; u.moving = false; return; }
      if (d[t] === 0 || dr < 1.3) {
        const [cx, cy] = closestRect(u.x, u.y, tg.x, tg.y, rx1, ry1);
        this.moveToward(u, cx, cy, spd, dt);
        if (!u.moving) { u.skip.add(tg.isWall ? 'w' + tg.x + ',' + tg.y : tg.id); u.target = null; }
        return;
      }
      const n = this.nextStep(u, d);
      if (n < 0) { u.moving = false; return; }
      if (this.wallAlive(n)) {
        u.wallTarget = this.walls[this.sh.wallAt[n]];
        return;
      }
      const nx = (n % this.W) + 0.5 + u.off[0], ny = ((n / this.W) | 0) + 0.5 + u.off[1];
      this.moveToward(u, nx, ny, spd, dt);
      if (!u.moving) this.moveToward(u, (n % this.W) + 0.5, ((n / this.W) | 0) + 0.5, spd, dt);
    }

    updateGuard(g, dt) {
      this.tickTimers(g, dt);
      g.scan -= dt;
      if (g.scan <= 0 || !g.target || g.target.hp <= 0 || g.target.state !== 'deck') {
        g.scan = 0.4;
        let best = null, bd = 9;
        for (const u of this.units) if (u.side === 'p' && u.hp > 0 && u.state === 'deck') { const d = dist(u.x, u.y, g.x, g.y); if (d < bd) { bd = d; best = u; } }
        g.target = best;
      }
      const tg = g.target;
      if (tg) {
        if (dist(g.x, g.y, tg.x, tg.y) <= g.range + 0.25) this.doAttack(g, tg);
        else this.moveToward(g, tg.x, tg.y, this.speedOf(g), dt);
      } else if (g.home && dist(g.x, g.y, g.home[0], g.home[1]) > 0.6) this.moveToward(g, g.home[0], g.home[1], g.speed * 0.5, dt);
      else g.moving = false;
    }

    updateDefense(b, dt) {
      const bd = b.def;
      if (b.type === 'vaktkur') {
        if (b.spawned < bd.guards) {
          if (!b.alarm) {
            for (const u of this.units) if (u.side === 'p' && u.state === 'deck' && u.hp > 0 && dist(u.x, u.y, b.cx, b.cy) < bd.trigger) { b.alarm = true; this.sound('alarm'); break; }
          }
          if (b.alarm) {
            b.spawnT -= dt;
            if (b.spawnT <= 0) {
              b.spawnT = 0.45; b.spawned++;
              let sx = b.cx, sy = b.y + b.h + 0.4;
              if (!this.walkableAt(sx, sy)) {
                const gt = this.goalTiles(b).filter((t) => this.walkable(t));
                if (gt.length) { const t = gt[(rand() * gt.length) | 0]; sx = (t % this.W) + 0.5; sy = ((t / this.W) | 0) + 0.5; }
              }
              const g = this.makeUnit(this.def.guardType || 'vakt', 'e', sx, sy);
              g.home = [sx, sy]; g.squash = 1.3; g.land = 0.2;
              this.units.push(g);
              this.fxAdd('poof', sx, sy, 8, { size: 8, color: '#ffffff', life: 0.4 });
            }
          }
        }
        return;
      }
      if (!bd.range) return;
      b.cd -= dt;
      const tg = b.target;
      const valid = (u) => u && u.hp > 0 && u.side === 'p' && u.state === 'deck' && (() => { const d = dist(u.x, u.y, b.cx, b.cy); return d <= bd.range + b.w / 2 && (!bd.minRange || d >= bd.minRange); })();
      if (!valid(tg)) {
        b.target = null;
        let best = null, bdist = Infinity;
        for (const u of this.units) if (valid(u)) { const d = dist(u.x, u.y, b.cx, b.cy); if (d < bdist) { bdist = d; best = u; } }
        b.target = best;
      }
      const t = b.target;
      if (!t) { b.ang += dt * 0.35; return; }
      const want = Math.atan2(t.y - b.cy, t.x - b.cx);
      let diff = ((want - b.ang + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
      const turn = b.type === 'morsare' ? 20 : 7;
      b.ang += clamp(diff, -turn * dt, turn * dt);
      diff = ((want - b.ang + Math.PI * 3) % (Math.PI * 2)) - Math.PI;
      if (b.cd > 0 || Math.abs(diff) > 0.35) return;
      b.cd = bd.atk;
      b.recoil = 1; b.atkAnim = 0.35;
      const dmg = b.dmg;
      if (b.type === 'kanon') {
        const len = 1.15;
        this.proj.push({ kind: 'ball', side: 'e', x: b.cx + Math.cos(b.ang) * len, y: b.cy + Math.sin(b.ang) * len, z: 22, target: t, dmg, speed: 11, dx: 0, dy: 0, dz: 0 });
        this.fxAdd('flash', b.cx + Math.cos(b.ang) * len, b.cy + Math.sin(b.ang) * len, 22, { size: 18, life: 0.15 });
        this.fxAdd('smoke', b.cx + Math.cos(b.ang) * (len + 0.2), b.cy + Math.sin(b.ang) * (len + 0.2), 22, { size: 8, color: '#e6e6e6', vz: 20, life: 0.7 });
        this.sound('cannon');
      } else if (b.type === 'utkik') {
        this.proj.push({ kind: 'bullet', side: 'e', x: b.cx, y: b.cy, z: 82, target: t, dmg, speed: 20, dx: 0, dy: 0, dz: 0 });
        this.fxAdd('flash', b.cx, b.cy, 84, { size: 10, life: 0.1 });
        this.sound('shot');
      } else if (b.type === 'morsare') {
        this.proj.push({ kind: 'shell', side: 'e', x: b.cx, y: b.cy, z: 30, sx: b.cx, sy: b.cy, tx: t.x, ty: t.y, t: 0, dur: 1.3, dmg, splash: bd.splash, dx: 0, dy: 0, dz: 0 });
        this.fxAdd('smoke', b.cx, b.cy, 32, { size: 12, color: '#e6e6e6', vz: 50, life: 0.9 });
        this.sound('mortar');
      } else if (b.type === 'vatten') {
        this.splash(t.x, t.y, bd.splash, dmg, 'e', { slow: true });
        if (!this.headless) {
          const nz = b._nozzle || [b.cx, b.cy, 38];
          for (let i = 0; i < 3; i++) {
            const f = 0.25 + rand() * 0.2;
            this.fxAdd('water', nz[0], nz[1], nz[2], { vx: (t.x - nz[0]) / f + (rand() - 0.5), vy: (t.y - nz[1]) / f + (rand() - 0.5), vz: 380 * f * 0.5 + (12 - nz[2]) / f, size: 3 + rand() * 2, life: f, g: 380, color: i ? '#bfe9ff' : '#ffffff' });
          }
          this.fxAdd('water', t.x, t.y, 4, { vx: (rand() - 0.5) * 3, vy: (rand() - 0.5) * 3, vz: 100, size: 2.5, life: 0.4 });
          if (rand() < 0.3) this.sound('water');
        }
      }
    }

    updateProjectiles(dt) {
      for (const pr of this.proj) {
        if (pr.kind === 'shell') {
          pr.t += dt;
          const f = Math.min(1, pr.t / pr.dur);
          const ox = pr.x, oy = pr.y, oz = pr.z;
          pr.x = pr.sx + (pr.tx - pr.sx) * f; pr.y = pr.sy + (pr.ty - pr.sy) * f;
          pr.z = 30 * (1 - f) + 170 * 4 * f * (1 - f);
          pr.dx = pr.x - ox; pr.dy = pr.y - oy; pr.dz = pr.z - oz;
          if (f >= 1) {
            pr.done = true;
            this.splash(pr.tx, pr.ty, pr.splash, pr.dmg, 'e');
            this.fxAdd('flash', pr.tx, pr.ty, 8, { size: 40, life: 0.3 });
            this.fxAdd('ring', pr.tx, pr.ty, 0, { size: pr.splash * 40, color: '#ffd9a0', life: 0.45 });
            for (let i = 0; i < 6; i++) this.fxAdd('smoke', pr.tx + (rand() - 0.5) * 1.5, pr.ty + (rand() - 0.5) * 1.5, 8, { size: 11, color: '#4a4640', vz: 30, life: 1 });
            this.marks.push({ x: pr.tx, y: pr.ty, t: 6 });
            this.events.push({ type: 'shake', amt: 5 });
            this.sound('boom');
          }
          continue;
        }
        const tg = pr.target;
        const alive = tg && (tg.isUnit ? tg.hp > 0 : tg.alive);
        if (alive) {
          if (tg.isUnit) { pr.tx = tg.x; pr.ty = tg.y; pr.tz = 14; }
          else if (tg.isWall) { pr.tx = tg.x + 0.5; pr.ty = tg.y + 0.5; pr.tz = 10; }
          else { const [cx, cy] = closestRect(pr.x, pr.y, tg.x + 0.3, tg.y + 0.3, tg.x + tg.w - 0.3, tg.y + tg.h - 0.3); pr.tx = cx; pr.ty = cy; pr.tz = Math.min(30, (B_HEIGHT[tg.type] || 20) * 0.5); }
        }
        if (pr.tx === undefined) { pr.done = true; continue; }
        const dx = pr.tx - pr.x, dy = pr.ty - pr.y, dz = (pr.tz - pr.z) / 32;
        const d = Math.hypot(dx, dy, dz);
        const s = pr.speed * dt;
        if (d <= s) {
          pr.done = true;
          if (alive) {
            this.damage(tg, pr.dmg);
            if (pr.kind === 'ball') { this.fxAdd('flash', pr.tx, pr.ty, pr.tz, { size: 14, life: 0.15 }); this.sound('hit'); }
            else for (let i = 0; i < 2; i++) this.fxAdd('spark', pr.tx, pr.ty, pr.tz, { vx: (rand() - 0.5) * 5, vy: (rand() - 0.5) * 5, vz: 50, life: 0.2 });
          }
        } else {
          pr.dx = (dx / d) * s; pr.dy = (dy / d) * s; pr.dz = (dz / d) * s * 32;
          pr.x += pr.dx; pr.y += pr.dy; pr.z += pr.dz;
          if (pr.kind === 'ball' && rand() < dt * 30) this.fxAdd('smoke', pr.x, pr.y, pr.z, { size: 3, color: '#dddddd', life: 0.3, alpha: 0.5 });
        }
      }
      this.proj = this.proj.filter((p) => !p.done);
      for (const m of this.marks) m.t -= dt;
      this.marks = this.marks.filter((m) => m.t > 0);
    }

    updateSpells(dt) {
      for (const s of this.spells) {
        s.t += dt; s.tick -= dt;
        if (s.t > 0.45 && s.tick <= 0) {
          s.tick = 0.25;
          for (const u of this.units) {
            if (u.side !== 'p' || u.hp <= 0 || u.state !== 'deck') continue;
            if (dist(u.x, u.y, s.x, s.y) > s.r) continue;
            if (s.type === 'lakning') {
              if (u.hp < u.maxHp) { u.hp = Math.min(u.maxHp, u.hp + s.hps * 0.25); if (rand() < 0.5) this.fxAdd('plus', u.x, u.y, 30, { vz: 40, life: 0.7, color: '#d6ff6a' }); }
            } else { u.rage = Math.max(u.rage, 0.35); u.rageMul = s.dmgMul; u.rageSpd = s.spdMul; }
          }
          if (!this.headless) {
            const a = rand() * 6.28, r = rand() * s.r;
            this.fxAdd(s.type === 'lakning' ? 'smoke' : 'note', s.x + Math.cos(a) * r, s.y + Math.sin(a) * r, 6, { size: 6, color: s.type === 'lakning' ? '#fff6c8' : '#ff7be6', vz: 50, life: 1, alpha: 0.6 });
          }
        }
      }
      this.spells = this.spells.filter((s) => s.t < s.dur);
    }

    updateFx(dt) {
      for (const p of this.fx) {
        p.life -= dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
        p.vz -= p.g * dt;
        p.rot += p.spin * dt;
        const floor = p.floor;
        if (p.g && p.z < floor) {
          const onDeck = K.ship.inPoly(this.sh.poly, p.x, p.y);
          if (onDeck || floor < 0) { p.z = floor; p.vz *= -0.35; p.vx *= 0.6; p.vy *= 0.6; }
          else { p.floor = -A.HULL; }
        }
      }
      this.fx = this.fx.filter((p) => p.life > 0);
    }

    checkEnd() {
      if (this.ended || !this.started) return;
      if (this.finishAt > 0 && this.time >= this.finishAt) return this.finish('all');
      if (this.elapsed >= this.maxTime) return this.finish('time');
      let left = this.pool.hero;
      for (const k in this.pool.troops) left += this.pool.troops[k];
      const alive = this.units.some((u) => u.side === 'p' && u.hp > 0);
      if (!left && !alive) {
        if (this.finishAt < 0) this.finishAt = this.time + 1.5;
      } else if (this.pct < 100) this.finishAt = -1;
    }

    finish(reason) {
      if (this.ended) return;
      this.ended = true;
      const loot = Math.round(this.loot) + (this.bridgeDown ? this.captureBonus : 0);
      const used = {};
      for (const k in this.initialPool.troops) used[k] = (this.initialPool.troops[k] || 0) - (this.pool.troops[k] || 0);
      const usedSpells = {};
      for (const k in this.initialPool.spells) usedSpells[k] = (this.initialPool.spells[k] || 0) - (this.pool.spells[k] || 0);
      this.result = {
        reason, stars: this.stars, pct: this.pct, loot, lootRaw: Math.round(this.loot), bonus: this.bridgeDown ? this.captureBonus : 0,
        captured: this.bridgeDown, firstCapture: this.bridgeDown && !this.replay, used, usedSpells, time: this.elapsed,
      };
      this.events.push({ type: 'end', result: this.result });
    }

    surrender() { if (!this.started) { this.ended = true; this.result = null; this.events.push({ type: 'leave' }); return; } this.finish('surrender'); }

    // ---------- ritning ----------
    bob() { return Math.sin(this.time * 1.1) * 2; }

    behindShip(x, y) {
      // ligger punkten bakom skrovet sett från kameran?
      const poly = this.sh.poly, [dx, dy] = G.depthDir();
      for (let k = 0.5; k < 40; k += 0.5) if (K.ship.inPoly(poly, x + k * dx, y + k * dy)) return true;
      return false;
    }

    render(ctx, cam, cw, ch, dpr, t) {
      A.unitScale = G.unitScale;
      try { this.draw(ctx, cam, cw, ch, dpr, t); } finally { A.unitScale = 1; A.spriteScale = 0; }
    }

    draw(ctx, cam, cw, ch, dpr, t) {
      const sh = this.sh;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const g = ctx.createLinearGradient(0, 0, 0, ch);
      g.addColorStop(0, '#0d5f7e'); g.addColorStop(1, '#1590a8');
      ctx.fillStyle = g; ctx.fillRect(0, 0, cw, ch);
      cam.apply(ctx, cw, ch, dpr);
      G.waves(ctx, this.waves, t, -A.HULL);
      const back = [], front = [];
      for (const sk of this.skiffs) {
        if (sk.behind === undefined || sk.moving || sk.view !== G.view) { sk.behind = this.behindShip(sk.x, sk.y); sk.view = G.view; }
        (sk.behind ? back : front).push(sk);
      }
      const drawSkiffs = (list) => {
        for (const sk of list) {
          const alpha = sk.state === 'leave' ? Math.max(0, 1 - sk.t / 3) : 1;
          ctx.globalAlpha = alpha;
          const seat = A.skiff(ctx, sk, t, -A.HULL);
          const u = sk.unit;
          if (u && u.state === 'boat') A.unit(ctx, Object.assign({}, u, { noShadow: true, moving: false }), seat[0], seat[1] + 2, t);
          ctx.globalAlpha = 1;
        }
      };
      drawSkiffs(back);

      const bob = this.bob();
      ctx.save();
      ctx.translate(0, bob);
      A.water(ctx, sh, t);
      const zone = !this.started ? 0.17 + 0.07 * Math.sin(t * 4) : this.zoneFlash > 0 ? 0.26 * Math.min(1, this.zoneFlash) : 0;
      if (zone > 0) {
        ctx.setLineDash([12, 10]); ctx.lineDashOffset = -t * 25;
        ctx.strokeStyle = `rgba(255,255,255,${Math.min(0.9, zone * 3.5)})`; ctx.lineWidth = 2.5; ctx.lineJoin = 'round';
        G.path(ctx, sh.foam.map(([x, y, nx, ny]) => P(x + nx * 1.35, y + ny * 1.35, -A.HULL))); ctx.stroke();
        ctx.setLineDash([]);
      }
      // skrov, däck, skuggor och ruiner ändras sällan: rita dem i ett förrenderat lager
      if (!this.layer) this.layer = new G.Layer();
      if (this.layerView !== G.view) {
        const b = A.shipBounds(sh);
        this.layerBounds = { x0: b.x0 - 10, y0: b.y0 - 28, x1: b.x1 + 10, y1: b.y1 + 10 };
        this.layerView = G.view;
      }
      const drawStatic = (c) => {
        A.hull(c, sh, t);
        A.deck(c, sh, t);
        for (const b of this.buildings) if (!b.alive) A.rubble(c, b, sh, t, true);
        for (const b of this.buildings) if (b.alive) A.buildingShadow(c, b);
      };
      const key = cam.z.toFixed(4) + '|' + dpr + '|' + (this.layerVer || 0) + '|' + G.view;
      if (this.layer.ensure(key, this.layerBounds, cam.z * dpr, drawStatic)) this.layer.blit(ctx);
      else drawStatic(ctx);
      if (zone > 0) {
        // vitt band innanför relingen = här kan man också trycka
        const pts = sh.poly.map(([x, y]) => P(x, y, 0));
        ctx.save(); G.path(ctx, pts); ctx.clip();
        ctx.strokeStyle = `rgba(255,255,255,${zone})`; ctx.lineWidth = 2 * 2.3 * ((G.SX + G.SY) / 2) * 0.9; ctx.lineJoin = 'round';
        G.path(ctx, pts); ctx.stroke();
        ctx.restore();
      }
      if (this.bridgeDown) { const br = this.buildings.find((b) => b.type === 'brygga'); const [X, Y] = P(br.cx, br.cy, 0); A.flag(ctx, X, Y - 58, 'pirate', t, 1.15); }
      for (const m of this.marks) { ctx.globalAlpha = Math.min(1, m.t / 2) * 0.5; G.disc(ctx, m.x, m.y, 0.7, 0, '#2a2420', null); ctx.globalAlpha = 1; }
      for (const s of this.spells) A.spellZone(ctx, s, t);
      if (this.inspect && this.inspect.b.alive && this.inspect.b.def.range) {
        const b = this.inspect.b;
        G.disc(ctx, b.cx, b.cy, b.def.range + b.w / 2, 0, 'rgba(255,255,255,.12)', 'rgba(255,255,255,.75)', 2);
        if (b.def.minRange) G.disc(ctx, b.cx, b.cy, b.def.minRange, 0, null, 'rgba(255,120,120,.75)', 2);
      }
      const items = [];
      for (const b of this.buildings) if (b.alive) items.push([G.depth(b.cx, b.cy), 0, b]);
      for (const w of this.walls) if (w.alive) items.push([G.depth(w.x + 0.5, w.y + 0.5), 1, w]);
      for (const u of this.units) if (u.hp > 0 && (u.state === 'deck' || u.state === 'jump')) items.push([G.depth(u.x, u.y) + (u.state === 'jump' ? 50 : 0), 2, u]);
      items.sort((p, q) => p[0] - q[0]);
      A.spriteScale = cam.z * dpr;
      for (const [, kind, o] of items) {
        if (kind === 0) A.building(ctx, o, sh, t, { pirate: false });
        else if (kind === 1) A.wall(ctx, o, sh, t);
        else {
          const [X, Y] = P(o.x, o.y, o.state === 'jump' ? o.jz : 0);
          if (o.state === 'jump') {
            const sk = this.skiffs.find((s) => s.unit === o);
            if (sk) { const [SX, SY] = P(o.j1[0], o.j1[1], 8); ctx.strokeStyle = '#c9a26b'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.moveTo(SX, SY); ctx.lineTo(X, Y - 20); ctx.stroke(); }
          }
          A.unit(ctx, Object.assign({}, o, { yell: o.yellT > 0, noShadow: o.state === 'jump' }), X, Y, t);
        }
      }
      A.spriteScale = 0;
      for (const pr of this.proj) A.projectile(ctx, pr);
      const low = [];
      for (const p of this.fx) { if (p.z >= -2 || K.ship.inPoly(sh.poly, p.x, p.y)) A.particle(ctx, p); else low.push(p); }
      ctx.restore();
      for (const p of low) A.particle(ctx, p);
      drawSkiffs(front);

      // livsmätare
      ctx.save(); ctx.translate(0, bob);
      for (const b of this.buildings) {
        if (!b.alive || this.time - b.lastHit > 3.5) continue;
        const [X, Y] = P(b.cx, b.cy, (B_HEIGHT[b.type] || 20) * (b.type === 'container' ? b.stack : 1) + 12);
        const f = b.hp / b.maxHp;
        A.hpBar(ctx, X, Y, f, f > 0.5 ? '#7be043' : f > 0.25 ? '#ffc93a' : '#ff5a3a', 34);
      }
      for (const u of this.units) {
        if (u.hp <= 0 || u.state !== 'deck') continue;
        const hero = u.type === 'kapten';
        if (u.hp >= u.maxHp && !hero) continue;
        const s = (A.SPEC[u.type] || A.SPEC.kampe).s * A.unitScale;
        const [X, Y0] = P(u.x, u.y, 0);
        const Y = Y0 - 44 * s - 6;
        A.hpBar(ctx, X, Y, u.hp / u.maxHp, u.side === 'p' ? '#7be043' : '#ff5a3a', hero ? 30 : 18);
        if (hero) A.crown(ctx, X, Y - 3);
      }
      if (this.deployFail) {
        const f = this.deployFail.t / 0.7;
        ctx.globalAlpha = f;
        G.disc(ctx, this.deployFail.x, this.deployFail.y, 0.9 + (1 - f) * 0.6, 0, 'rgba(255,60,60,.25)', '#ff4b3a', 3);
        ctx.globalAlpha = 1;
      }
      ctx.restore();
    }
  }

  K.Battle = Battle;
  K.B_HEIGHT = B_HEIGHT;

  // ---------- huvudlös simulering för balansering ----------
  K.simulate = function (shipId, army, o = {}) {
    const def = D.ships.find((s) => s.id === shipId);
    const save = { army: Object.assign({}, army), spells: Object.assign({}, o.spells || {}), levels: o.levels || {}, captured: {} };
    const bt = new Battle(def, save, { headless: true });
    // utplaceringspunkter längs skrovet (vatten)
    const spots = [];
    const sides = o.sides || 2;
    const cands = [[bt.W * 0.25, -1.5], [bt.W * 0.55, bt.H + 1.5], [-1.5, bt.H / 2], [bt.W * 0.75, -1.5], [bt.W + 1.5, bt.H / 2]];
    for (let i = 0; i < sides; i++) spots.push(cands[i]);
    const order = ['bjasse', 'bombare', 'kampe', 'skytt', 'plundrare'];
    const queue = [];
    let tt = 0;
    for (const k of order) for (let i = 0; i < (army[k] || 0); i++) { queue.push([tt, k, spots[i % spots.length]]); tt += 0.12; }
    if (o.hero !== false) queue.push([1.5, 'kapten', spots[0]]);
    queue.sort((a, b) => a[0] - b[0]);
    let qi = 0;
    const spellQ = [];
    for (const k in save.spells) for (let i = 0; i < save.spells[k]; i++) spellQ.push(k);
    let nextSpell = 7;
    while (!bt.ended && bt.time < 260) {
      while (qi < queue.length && queue[qi][0] <= bt.time) {
        const [, k, s] = queue[qi++];
        bt.deploy(k, s[0] + (Math.random() - 0.5) * 2, s[1] + (Math.random() - 0.5));
      }
      if (bt.heroUnit && !bt.abilityUsed && bt.heroUnit.state === 'deck' && bt.heroUnit.hp < bt.heroUnit.maxHp * 0.5) bt.useAbility();
      if (spellQ.length && bt.time > nextSpell) {
        const alive = bt.units.filter((u) => u.side === 'p' && u.hp > 0 && u.state === 'deck');
        if (alive.length > 2) {
          const cx = alive.reduce((a, u) => a + u.x, 0) / alive.length, cy = alive.reduce((a, u) => a + u.y, 0) / alive.length;
          bt.castSpell(spellQ.shift(), cx, cy);
        }
        nextSpell += 6;
      }
      bt.step(1 / 30);
      bt.events.length = 0;
    }
    return { stars: bt.stars, pct: bt.pct, loot: Math.round(bt.loot), time: Math.round(bt.elapsed), bridge: bt.bridgeDown };
  };
})();
