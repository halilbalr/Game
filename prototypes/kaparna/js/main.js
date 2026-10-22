// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Spelets huvudloop: sparning, scener (titel / hamn / strid), inmatning och kamera.
(function () {
  const K = window.K, D = K.DATA, G = K.gfx, A = K.art, UI = K.ui;
  const $ = (id) => document.getElementById(id);
  const SAVE_KEY = 'kaparna-save-v1';

  function defaultSave() {
    const levels = {};
    for (const k of [...Object.keys(D.troops), 'kapten', ...Object.keys(D.spells)]) levels[k] = 1;
    return { v: 1, gold: D.start.gold, harborLvl: 1, levels, army: Object.assign({}, D.start.army), spells: {}, captured: {}, stars: {}, fleet: {}, tut: {}, muted: false };
  }
  function loadSave() {
    const s = defaultSave();
    try {
      const raw = localStorage.getItem(SAVE_KEY);
      if (raw) {
        const o = JSON.parse(raw);
        if (o && o.v === 1) {
          for (const k of Object.keys(s)) if (o[k] !== undefined) s[k] = typeof s[k] === 'object' && !Array.isArray(s[k]) ? Object.assign(s[k], o[k]) : o[k];
        }
      }
    } catch (e) { /* ingen lagring – spela ändå */ }
    s.harborLvl = Math.max(1, Math.min(D.harbor.length, s.harborLvl | 0 || 1));
    return s;
  }

  const Game = {
    scene: 'title', t: 0, coins: [], lootShown: 0, harborSel: null,
    init() {
      this.cv = $('cv'); this.ctx = this.cv.getContext('2d');
      this.save = loadSave();
      K.sfx.muted = !!this.save.muted;
      this.camHome = new G.Camera(); this.camBattle = new G.Camera();
      this.cw = innerWidth; this.ch = innerHeight;
      this.harbor = new K.Harbor(this, this.isPortrait());
      this.resize();
      addEventListener('resize', () => this.resize());
      addEventListener('orientationchange', () => setTimeout(() => this.resize(), 250));
      if (window.visualViewport) visualViewport.addEventListener('resize', () => this.resize());
      this.bindInput();
      this.bindUI();
      UI.updateHome(this, true);
      this.last = performance.now();
      requestAnimationFrame((ts) => this.loop(ts));
    },
    persist() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.save)); } catch (e) { /* ignorera */ } },

    applyDpr() {
      this.dpr = Math.min(this.maxDpr || 2, devicePixelRatio || 1);
      this.cv.width = Math.round(this.cw * this.dpr); this.cv.height = Math.round(this.ch * this.dpr);
    },
    isPortrait() { return this.ch > this.cw * 1.05; },
    // stående mobil -> skeppet står upp ('tall'); liggande skärm -> klassisk diagonal vy ('iso')
    battleView() { return this.isPortrait() ? 'tall' : 'iso'; },
    resize() {
      const w = innerWidth, h = innerHeight;
      if (this._sized && w === this.cw && h === this.ch) return;
      this._sized = true;
      this.cw = w; this.ch = h;
      this.applyDpr();
      const portrait = this.isPortrait();
      if (this.harbor && this.harbor.portrait !== portrait) { this.harbor = new K.Harbor(this, portrait); }
      this.fitHome();
      if (this.battle) { this.bView = this.battleView(); this.fitBattle(); }
    },
    // b = område som ska synas från början, clampB = hur långt man får panorera
    fit(cam, b, padTop, padBottom, maxZ = 1.6, clampB = null) {
      const bw = b.x1 - b.x0, bh = b.y1 - b.y0;
      const aw = Math.max(100, this.cw - 20), ah = Math.max(100, this.ch - padTop - padBottom);
      const z = Math.max(0.22, Math.min(maxZ, Math.min(aw / bw, ah / bh)));
      cam.z = z; cam.min = z * 0.8; cam.max = Math.max(2, z * 2.8);
      cam.x = (b.x0 + b.x1) / 2; cam.y = (b.y0 + b.y1) / 2 + (padBottom - padTop) / 2 / z;
      cam.bounds = clampB || b;
      cam.clamp(cam.bounds);
    },
    fitHome() {
      G.setView('iso');
      const b = this.harbor.bounds();
      if (this.harbor.portrait) {
        // stående: fyll bredden, börja högst upp, panorera nedåt till flottan
        const z = Math.max(0.3, Math.min(1.1, (this.cw - 12) / (b.x1 - b.x0)));
        const cam = this.camHome;
        cam.z = z; cam.min = z * 0.85; cam.max = Math.max(2, z * 3);
        cam.x = (b.x0 + b.x1) / 2;
        cam.y = b.y0 + (this.ch / 2 - 56) / z;
        // få skepp: centrera i höjdled i stället för att lämna tomt hav längst ner
        const free = this.ch - 60 - 150;
        if ((b.y1 - b.y0) * z < free) cam.y = (b.y0 + b.y1) / 2 + (150 - 60) / 2 / z;
        cam.bounds = { x0: b.x0, x1: b.x1, y0: cam.y, y1: Math.max(cam.y, b.y1 - (this.ch / 2 - 150) / z) };
        cam.clamp(cam.bounds);
      } else this.fit(this.camHome, b, 24, 50, 1.25);
    },
    fitBattle() {
      G.setView(this.bView);
      const tall = this.bView === 'tall';
      const bd = A.shipBounds(this.battle.sh, tall ? 1.7 : 1.1);
      const short = this.ch < 520;
      const top = bd.y0 - 120 * G.ZK;
      this.fit(this.camBattle, { x0: bd.x0, x1: bd.x1, y0: top, y1: bd.y1 }, tall ? 74 : short ? 40 : 70, tall ? 118 : short ? 88 : 125, tall ? 1.4 : 1.5);
    },
    get cam() { return this.scene === 'battle' ? this.camBattle : this.camHome; },

    // ---------- scener ----------
    play() {
      K.sfx.init(); K.sfx.setMuted(this.save.muted); K.sfx.startMusic(); K.sfx.play('click');
      // på telefon: försök gå till helskärm (fungerar på Android; iPhone och inbäddade vyer säger nej, det gör inget)
      const standalone = matchMedia('(display-mode: standalone), (display-mode: fullscreen)').matches || navigator.standalone;
      const el = document.documentElement;
      if (!standalone && matchMedia('(pointer: coarse)').matches && el.requestFullscreen && !document.fullscreenElement) {
        try { el.requestFullscreen({ navigationUI: 'hide' }).catch(() => {}); } catch (e) { /* ignorera */ }
      }
      $('title').hidden = true;
      this.goHome();
    },
    goHome() {
      this.scene = 'home';
      this.battle = null;
      $('hud-battle').hidden = true; $('result').hidden = true; $('hud-home').hidden = false;
      this.harbor.refreshFleet();
      this.fitHome();
      UI.updateHome(this, true);
      this.homeHints();
    },
    homeHints() {
      const s = this.save, tut = s.tut;
      if (!tut.firstBattle) UI.hint('Tryck på ANFALL! för att välja ett skepp att kapa.');
      else if (UI.captured(s) && !tut.collected) UI.hint('Ditt kapade skepp tjänar guld. Tryck på guldbubblan ovanför skeppet!', true);
      else if (UI.armyUsed(s) === 0) UI.hint('Armén är tom! Rekrytera pirater i Armélägret innan nästa anfall.');
      else UI.hint(null);
    },
    tryAttack(def) {
      const used = UI.armyUsed(this.save) + UI.spellUsed(this.save);
      if (used === 0) {
        UI.confirm('Tom armé', 'Du har inga trupper – bara Kaptenen följer med. Vill du anfalla ändå?', 'Anfall', () => this.startBattle(def));
        return;
      }
      this.startBattle(def);
    },
    startBattle(def) {
      UI.closePanel(); UI.hint(null);
      this.battle = new K.Battle(def, this.save);
      this.bView = this.battleView();
      this.scene = 'battle';
      this.lootShown = 0; this.coins = [];
      $('hud-home').hidden = true; $('hud-battle').hidden = false; $('result').hidden = true;
      this.fitBattle();
      UI.buildBattleCards(this);
      UI.updateBattle(this, true);
      $('b-banner').textContent = this.save.tut.firstBattle ? 'Välj en pirat och tryck på vattnet runt skeppet' : 'Välj en pirat nedan och tryck på vattnet runt skeppet. Håll inne för att skicka flera!';
      this.save.tut.firstBattle = 1; this.persist();
      K.sfx.play('alarm');
    },
    endBattle(res) {
      const s = this.save, bt = this.battle, def = bt.def;
      if (res) {
        s.gold += res.loot;
        for (const k in res.used) s.army[k] = Math.max(0, (s.army[k] || 0) - res.used[k]);
        for (const k in res.usedSpells) s.spells[k] = Math.max(0, (s.spells[k] || 0) - res.usedSpells[k]);
        if (res.stars > (s.stars[def.id] || 0)) s.stars[def.id] = res.stars;
        if (res.firstCapture) { s.captured[def.id] = true; s.fleet[def.id] = Date.now(); }
        this.persist();
      }
      setTimeout(() => { if (this.battle === bt) UI.showResult(this, res, def); }, 1100);
    },

    // ---------- ekonomi ----------
    armyAction(act, key) {
      const s = this.save;
      if (act === 'add') {
        const d = D.troops[key];
        if (UI.armyUsed(s) + d.space > UI.armyCap(s)) { UI.toast('Armélägret är fullt!'); K.sfx.play('error'); return; }
        if (s.gold < d.cost) { UI.toast('Inte tillräckligt med guld'); K.sfx.play('error'); return; }
        s.gold -= d.cost; s.army[key] = (s.army[key] || 0) + 1; K.sfx.play('train');
      } else if (act === 'rm') {
        if (!s.army[key]) return;
        s.army[key]--; s.gold += D.troops[key].cost; K.sfx.play('click');
      } else if (act === 'sadd') {
        const d = D.spells[key];
        if (UI.spellUsed(s) + d.space > UI.spellCap(s)) { UI.toast('Inga fler dryckesplatser'); K.sfx.play('error'); return; }
        if (s.gold < d.cost) { UI.toast('Inte tillräckligt med guld'); K.sfx.play('error'); return; }
        s.gold -= d.cost; s.spells[key] = (s.spells[key] || 0) + 1; K.sfx.play('heal');
      } else if (act === 'srm') {
        if (!s.spells[key]) return;
        s.spells[key]--; s.gold += D.spells[key].cost; K.sfx.play('click');
      }
      this.persist(); UI.refreshPanel(); UI.updateHome(this); this.homeHints();
    },
    upgrade(key) {
      const s = this.save, lv = s.levels[key] || 1;
      if (lv >= UI.levelCap(s)) return;
      const cost = UI.upCost(key, lv + 1);
      if (s.gold < cost) { UI.toast('Inte tillräckligt med guld'); K.sfx.play('error'); return; }
      s.gold -= cost; s.levels[key] = lv + 1;
      K.sfx.play('upgrade'); UI.toast(`${UI.defOf(key).name} är nu nivå ${lv + 1}!`);
      this.persist(); UI.refreshPanel(); UI.updateHome(this);
    },
    upgradeHarbor() {
      const s = this.save, next = D.harbor[s.harborLvl];
      if (!next || UI.captured(s) < s.harborLvl) return;
      if (s.gold < next.cost) { UI.toast('Inte tillräckligt med guld'); K.sfx.play('error'); return; }
      s.gold -= next.cost; s.harborLvl++;
      K.sfx.play('upgrade'); UI.toast(`Piratfästet är nu nivå ${s.harborLvl}!`);
      this.persist(); UI.refreshPanel(); UI.updateHome(this);
    },
    collect(f) {
      const s = this.save, gold = this.harbor.shipGold(f);
      if (gold < 1) return;
      s.gold += gold; s.fleet[f.def.id] = Date.now(); s.tut.collected = 1;
      const [X, Y] = this.harbor.bubblePos(f);
      const [sx, sy] = this.camHome.toScreen(X, Y, this.cw, this.ch);
      this.spawnCoins(Math.min(14, 3 + Math.round(gold / 40)), sx, sy, $('gold-pill'), () => UI.updateHome(this));
      K.sfx.play('coin');
      UI.toast(`+${UI.fmt(gold)} guld från ${f.def.name.toLowerCase()}`);
      this.persist(); this.homeHints();
    },

    // ---------- flygande mynt (skärmkoordinater) ----------
    spawnCoins(n, sx, sy, el, onArrive) {
      const r = el.getBoundingClientRect();
      const tx = r.left + 14, ty = r.top + r.height / 2;
      for (let i = 0; i < n; i++) {
        this.coins.push({ x0: sx + (Math.random() - 0.5) * 30, y0: sy + (Math.random() - 0.5) * 20, x1: tx, y1: ty, cx: (sx + tx) / 2 + (Math.random() - 0.5) * 160, cy: Math.min(sy, ty) - 60 - Math.random() * 80, t: -i * 0.05, dur: 0.55 + Math.random() * 0.25, el, cb: i === n - 1 ? onArrive : null, rot: Math.random() * 6 });
      }
    },
    drawCoins(dt) {
      if (!this.coins.length) return;
      const ctx = this.ctx;
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
      for (const c of this.coins) {
        c.t += dt; c.rot += dt * 12;
        if (c.t < 0) continue;
        const f = Math.min(1, c.t / c.dur), e = f * f * (3 - 2 * f);
        const x = (1 - e) * (1 - e) * c.x0 + 2 * (1 - e) * e * c.cx + e * e * c.x1;
        const y = (1 - e) * (1 - e) * c.y0 + 2 * (1 - e) * e * c.cy + e * e * c.y1;
        const s = 1.2 - e * 0.4, sx = Math.abs(Math.cos(c.rot)) * 7 + 1.5;
        G.blob(ctx, x, y, sx * s, 8 * s, '#ffcf3a', G.OUT, 2);
        if (f >= 1) { c.done = true; UI.bump(c.el.id); if (c.cb) c.cb(); }
      }
      this.coins = this.coins.filter((c) => !c.done);
    },

    // ---------- loop ----------
    loop(ts) {
      const raw = Math.max(0, (ts - this.last) / 1000);
      const dt = Math.min(0.05, raw);
      this.last = ts; this.t += dt;
      // sänk upplösningen om enheten inte orkar (~35 fps eller sämre i två sekunder)
      if (raw < 0.25 && !document.hidden) {
        this.ftAvg = (this.ftAvg || 0.016) * 0.97 + raw * 0.03;
        this.slowT = this.ftAvg > 0.029 ? (this.slowT || 0) + raw : 0;
        if (this.slowT > 2 && this.dpr > 1) { this.maxDpr = Math.max(1, this.dpr - 0.5); this.slowT = 0; this.ftAvg = 0.016; this.applyDpr(); }
      }
      try { this.frame(dt); } catch (e) { console.error(e); if (this.ctx.reset) this.ctx.reset(); }
      requestAnimationFrame((t2) => this.loop(t2));
    },
    frame(dt) {
      const { ctx, cw, ch, dpr } = this;
      if (this.scene === 'battle' && this.battle) {
        const bt = this.battle;
        G.setView(this.bView);
        this.holdDeploy();
        bt.update(dt);
        this.battleEvents();
        this.camBattle.update(dt);
        bt.render(ctx, this.camBattle, cw, ch, dpr, this.t);
        this.lootShown += (bt.loot - this.lootShown) * Math.min(1, dt * 6);
        if (Math.abs(bt.loot - this.lootShown) < 1) this.lootShown = bt.loot;
        UI.updateBattle(this);
      } else {
        G.setView('iso');
        this.harbor.update(dt);
        this.camHome.update(dt);
        this.harbor.render(ctx, this.camHome, cw, ch, dpr, this.t);
        if (this.scene === 'home' && (this._hudT = (this._hudT || 0) + dt) > 1) { this._hudT = 0; UI.updateHome(this); }
      }
      this.drawCoins(dt);
    },

    battleEvents() {
      const bt = this.battle;
      for (const ev of bt.events) {
        switch (ev.type) {
          case 'start':
            $('b-banner').textContent = 'Ta kommandobryggan för att kapa skeppet!';
            setTimeout(() => { if (this.battle === bt) $('b-banner').textContent = ''; }, 3500);
            break;
          case 'star': UI.starOn(ev.n); break;
          case 'capture':
            UI.bigMsg('SKEPPET KAPAT!<small>Kommandobryggan är er!</small>');
            K.sfx.play('capture'); K.sfx.lastBuzz = 0; K.sfx.buzz([40, 60, 90]);
            break;
          case 'shake': this.camBattle.shake = Math.max(this.camBattle.shake, ev.amt); break;
          case 'coin': {
            const [X, Y] = G.P(ev.x, ev.y, ev.z);
            const [sx, sy] = this.camBattle.toScreen(X, Y + bt.bob(), this.cw, this.ch);
            this.spawnCoins(1, sx, sy, $('loot-pill'));
            break;
          }
          case 'end': this.endBattle(ev.result); break;
          case 'leave': this.goHome(); break;
        }
      }
      bt.events.length = 0;
    },

    // ---------- inmatning ----------
    bindInput() {
      const cv = this.cv, ptrs = new Map();
      let drag = null, pinch = null;
      this._ptrs = ptrs;
      const clampCam = (cam) => cam.clamp(cam.bounds);
      cv.addEventListener('pointerdown', (e) => {
        if (this.scene === 'title') return;
        K.sfx.init();
        try { cv.setPointerCapture(e.pointerId); } catch (er) { /* */ }
        ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
        const cam = this.cam;
        if (ptrs.size === 1) drag = { sx: e.clientX, sy: e.clientY, x: e.clientX, y: e.clientY, cx: cam.x, cy: cam.y, moved: false, held: false, t0: performance.now(), last: 0, slop: e.pointerType === 'touch' ? 14 : 8 };
        else if (ptrs.size === 2) {
          if (drag) drag.moved = true;
          const [a, b] = [...ptrs.values()];
          const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2;
          pinch = { d: Math.hypot(a.x - b.x, a.y - b.y) || 1, z: cam.z, iso: cam.toIso(mx, my, this.cw, this.ch) };
        }
      });
      cv.addEventListener('pointermove', (e) => {
        if (!ptrs.has(e.pointerId)) return;
        ptrs.set(e.pointerId, { x: e.clientX, y: e.clientY });
        const cam = this.cam;
        if (ptrs.size >= 2 && pinch) {
          const [a, b] = [...ptrs.values()];
          const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, d = Math.hypot(a.x - b.x, a.y - b.y) || 1;
          cam.z = Math.max(cam.min, Math.min(cam.max, (pinch.z * d) / pinch.d));
          cam.x = pinch.iso[0] - (mx - this.cw / 2) / cam.z; cam.y = pinch.iso[1] - (my - this.ch / 2) / cam.z;
          clampCam(cam);
        } else if (drag) {
          drag.x = e.clientX; drag.y = e.clientY;
          const dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
          if (!drag.moved && !drag.held && Math.hypot(dx, dy) > (drag.slop || 10)) drag.moved = true;
          if (drag.moved && !drag.held) { cam.x = drag.cx - dx / cam.z; cam.y = drag.cy - dy / cam.z; clampCam(cam); }
        }
      });
      const up = (e) => {
        if (!ptrs.has(e.pointerId)) return;
        ptrs.delete(e.pointerId);
        if (ptrs.size < 2) pinch = null;
        if (ptrs.size === 0) {
          if (drag && !drag.moved && !drag.held && e.type === 'pointerup') this.tap(e.clientX, e.clientY);
          drag = null;
        } else if (drag) { const [p] = [...ptrs.values()]; const cam = this.cam; drag = { sx: p.x, sy: p.y, x: p.x, y: p.y, cx: cam.x, cy: cam.y, moved: true, held: false, t0: 0 }; }
      };
      cv.addEventListener('pointerup', up);
      cv.addEventListener('contextmenu', (e) => e.preventDefault());
      cv.addEventListener('pointercancel', up);
      cv.addEventListener('wheel', (e) => {
        e.preventDefault();
        if (this.scene === 'title') return;
        const cam = this.cam;
        cam.zoomAt(e.deltaY < 0 ? 1.1 : 1 / 1.1, e.clientX, e.clientY, this.cw, this.ch);
        clampCam(cam);
      }, { passive: false });
      this._drag = () => drag;
    },

    holdDeploy() {
      const drag = this._drag && this._drag();
      const bt = this.battle;
      if (!drag || drag.moved || this._ptrs.size !== 1 || !bt || bt.ended) return;
      const sel = bt.selected;
      if (!sel || D.spells[sel]) return;
      // fortsätt bara med samma trupp som hållningen började med
      if (drag.key && drag.key !== sel) return;
      const now = performance.now();
      if (now - drag.t0 < 260) return;
      if (now - drag.last < 110) return;
      drag.last = now; drag.key = sel;
      const r = this.deployAt(drag.x, drag.y, true);
      if (r === 'ok' || drag.held) drag.held = true;
      if (r !== 'ok') drag.held = true;
    },

    tap(sx, sy) {
      if (this.scene === 'battle') { this.deployAt(sx, sy, false); return; }
      if (this.scene !== 'home') return;
      const [X, Y] = this.camHome.toIso(sx, sy, this.cw, this.ch);
      const hit = this.harbor.hit(X, Y);
      if (!hit) return;
      K.sfx.play('click');
      if (hit.type === 'collect') this.collect(hit.f);
      else if (hit.type === 'fort' || hit.type === 'forge') UI.openForge(this);
      else if (hit.type === 'camp') UI.openArmy(this);
      else if (hit.type === 'ship') UI.toast(`${hit.f.def.name}: +${hit.f.def.income} guld/min (max ${UI.fmt(hit.f.def.cap)})`);
    },

    deployAt(sx, sy, quiet) {
      const bt = this.battle;
      if (!bt || bt.ended) return 'ended';
      G.setView(this.bView);
      const sel = bt.selected;
      if (!sel) { if (!quiet) UI.toast('Du har inga trupper kvar'); return 'none'; }
      const [X, Y0] = this.camBattle.toIso(sx, sy, this.cw, this.ch);
      const Y = Y0 - bt.bob();
      const [dx, dy] = G.isoToWorld(X, Y, 0);
      if (D.spells[sel]) {
        const r = bt.castSpell(sel, dx, dy);
        if (r !== 'ok' && !quiet) { K.sfx.play('error'); }
        else if (r === 'ok') K.sfx.buzz(20);
        return r;
      }
      // på mobilen räcker det att trycka nära relingen: skiffen kommer till närmaste sida
      const RAIL = 2.4;
      if (K.ship.inPoly(bt.sh.poly, dx, dy)) {
        const c = K.ship.closestOnPoly(bt.sh.poly, dx, dy);
        if (c.d <= RAIL) {
          const r = bt.deploy(sel, c.x + c.nx * 2.2, c.y + c.ny * 2.2);
          return this.afterDeploy(r, sel, quiet);
        }
      }
      if (K.ship.inPoly(bt.sh.poly, dx, dy)) {
        const tx = dx | 0, ty = dy | 0;
        const oi = tx >= 0 && ty >= 0 && tx < bt.W && ty < bt.H ? bt.sh.occ[ty * bt.W + tx] : -1;
        if (!quiet) {
          if (oi >= 0 && bt.buildings[oi].alive) {
            const b = bt.buildings[oi];
            bt.inspect = { b, t: 2.5 };
            UI.toast(`${b.def.name} – ${Math.ceil(b.hp)} liv${b.def.range ? ` · räckvidd ${b.def.range}` : ''}${b.lootLeft > 1 ? ` · ${UI.fmt(b.lootLeft)} guld` : ''}`);
          } else UI.toast('Tryck i vattnet eller nära relingen!');
          bt.deployFail = { x: dx, y: dy, t: 0.7 };
          bt.zoneFlash = 1.6;
          K.sfx.play('error');
        }
        return 'deck';
      }
      const [wx, wy] = G.isoToWorld(X, Y, -A.HULL);
      return this.afterDeploy(bt.deploy(sel, wx, wy), sel, quiet);
    },
    afterDeploy(r, sel, quiet) {
      if (r === 'empty' && !quiet) { UI.toast('Slut på den truppen – välj en annan'); K.sfx.play('error'); }
      if (r === 'ok') { K.sfx.buzz(8); if (sel === 'kapten') UI.toast('Kaptenen är på väg!'); }
      return r;
    },

    bindUI() {
      $('btn-play').onclick = () => this.play();
      $('btn-attack').onclick = () => { K.sfx.play('click'); UI.hint(null); UI.openMap(this); };
      $('btn-army').onclick = () => { K.sfx.play('click'); UI.openArmy(this); };
      $('btn-forge').onclick = () => { K.sfx.play('click'); UI.openForge(this); };
      $('btn-sound').onclick = () => { this.save.muted = !this.save.muted; K.sfx.init(); K.sfx.setMuted(this.save.muted); this.persist(); UI.updateHome(this, true); };
      $('panel-close').onclick = () => { K.sfx.play('click'); UI.closePanel(); this.homeHints(); };
      $('panel').addEventListener('pointerdown', (e) => { if (e.target === $('panel')) { UI.closePanel(); this.homeHints(); } });
      $('b-end').onclick = () => {
        const bt = this.battle; if (!bt || bt.ended) return;
        K.sfx.play('click');
        if (!bt.started) { bt.surrender(); return; }
        UI.confirm('Avsluta striden?', 'Du behåller bytet du redan tagit. Trupper som inte satts ut går tillbaka till armén.', 'Avsluta', () => { if (this.battle === bt && !bt.ended) bt.surrender(); });
      };
      $('b-ability').onclick = () => { if (this.battle && this.battle.useAbility()) UI.bigMsg('STRIDSROP!', 1400); };
      $('res-home').onclick = () => { K.sfx.play('click'); this.goHome(); };
      addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { if (!$('confirm').hidden) $('confirm').hidden = true; else if (UI.panelOpen()) { UI.closePanel(); this.homeHints(); } }
      });
    },
  };

  // Offline-stöd när spelet ligger på en riktig webbadress (inte som lokal fil eller inbäddat)
  try {
    if ('serviceWorker' in navigator && (location.protocol === 'https:' || location.hostname === 'localhost') && window.self === window.top && document.querySelector('link[rel="manifest"]')) {
      addEventListener('load', () => navigator.serviceWorker.register('sw.js').catch(() => {}));
    }
  } catch (e) { /* inbäddad vy */ }

  K.game = Game;
  window.KAPARNA = { game: Game, simulate: K.simulate, reset() { try { localStorage.removeItem(SAVE_KEY); } catch (e) { /* */ } location.reload(); } };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', () => Game.init());
  else Game.init();
})();
