// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Hemmahamnen: kust, piratfäste, läger, smedja, kapade skepp som ger guld.
(function () {
  const K = window.K, G = K.gfx, A = K.art, P = G.P, OUT = G.OUT, D = K.DATA;
  const WL = -12; // vattennivå i hamnen
  const W = (u, v) => [(u + v) / 2, (v - u) / 2];
  const coast = (u) => 20 + 1.6 * Math.sin(u * 0.23) + 0.8 * Math.sin(u * 0.57 + 1);
  const SHIP_SCALE = 0.4;
  // Två planlösningar: bred för liggande skärm, smal för stående mobil (flottan i en kolumn nedåt).
  const LAYOUTS = {
    wide: {
      fort: [0, 11], camp: [-10, 14], forge: [10, 14], light: [21, 16.5],
      palms: [[-17, 16], [-5, 17], [5, 17.5], [16, 12], [-15, 8], [18, 6], [-3, 3], [-22, 13], [24, 9]],
      acacias: [[-21, 7], [8, 6], [-9, 4], [12, 3]],
      rocks: [[-12, 18.5], [3, 18.7], [9, 18.6], [-25, 18]],
      barrels: [[-4, 15.5], [-3.2, 16], [6.5, 15], [-7, 9]],
      jetties: [[-6.5, 19.5, 6], [7.5, 19.3, 6]],
      moored: [[-6.5, 25.5], [7.5, 25.3], [-5.2, 24.4]],
      camels: [[-18, 6], [12, 9]], crew: [-12, 6], walkU: 24,
      slots: [[-15, 31], [0, 30], [15, 31], [-15, 47], [0, 46], [15, 47]],
      waves: [620, 140, 58],
    },
    narrow: {
      fort: [0, 11.5], camp: [-7, 14.5], forge: [7, 14.5], light: [-10.5, 18.2],
      palms: [[-9.5, 9.5], [-3.2, 17.4], [3.6, 18], [10, 10], [-5, 4], [5.5, 4], [10.5, 16.5], [-11.5, 13]],
      acacias: [[-8, 4], [8.5, 6], [0, 3]],
      rocks: [[-6.5, 17], [6.5, 19.6], [9.5, 20]],
      barrels: [[-2.6, 16.3], [-1.8, 16.8], [2.8, 16.4]],
      jetties: [[-3.6, 19.3, 6], [4.2, 19.6, 6]],
      moored: [[-3.6, 25.3], [4.2, 25.6], [-2.4, 24.2]],
      camels: [[-8, 6], [8, 8]], crew: [-8, 4], walkU: 10,
      slots: [[-2.5, 32], [2.5, 47], [-2.5, 62], [2.5, 77], [-2.5, 92], [2.5, 107]],
      waves: [480, 60, 100],
    },
  };

  class Harbor {
    constructor(game, portrait) {
      this.game = game; this.t = 0; this.portrait = !!portrait;
      const L = (this.L = LAYOUTS[portrait ? 'narrow' : 'wide']);
      const pts = [];
      for (let u = -90; u <= 90; u += 1) pts.push(W(u, coast(u)));
      pts.push(W(90, -90), W(-90, -90));
      this.land = pts;
      this.coastPts = pts.slice(0, pts.length - 2);
      const r = G.rng(42);
      this.sandPatches = [];
      for (let i = 0; i < 60; i++) { const u = -70 + r() * 140, v = -30 + r() * 46; this.sandPatches.push([...W(u, v), 0.8 + r() * 2.2, r()]); }
      this.waves = [];
      const [nw, wu, wv] = L.waves;
      for (let i = 0; i < nw; i++) { const u = -wu / 2 + r() * wu, v = 23.5 + r() * wv; this.waves.push([...W(u, v), r() * 6.28]); }
      const B = (uv, w, h, type) => { const [cx, cy] = W(uv[0], uv[1]); return { type, x: cx - w / 2, y: cy - h / 2, w, h, cx, cy }; };
      this.fort = B(L.fort, 4, 4, 'fort');
      this.camp = B(L.camp, 3, 3, 'camp');
      this.forge = B(L.forge, 3, 3, 'forge');
      this.light = B(L.light, 1.4, 1.4, 'light');
      this.deco = [];
      for (const [u, v] of L.palms) this.deco.push({ type: 'palm', ...this.pt(u, v), s: 0.9 + r() * 0.3, ph: r() * 6 });
      for (const [u, v] of L.acacias) this.deco.push({ type: 'acacia', ...this.pt(u, v), s: 0.9 + r() * 0.3, ph: r() * 6 });
      for (const [u, v] of L.rocks) this.deco.push({ type: 'rock', ...this.pt(u, v), s: 0.7 + r() * 0.6, ph: r() * 6 });
      for (const [u, v] of L.barrels) this.deco.push({ type: 'barrel', ...this.pt(u, v), s: 1, ph: r() });
      this.jetties = L.jetties;
      this.moored = [];
      for (const [u, v] of L.moored) this.moored.push({ ...this.pt(u, v), ang: 0.785 + (r() - 0.5) * 0.6, seed: r() * 9, color: ['#2f7fd1', '#3aa357', '#e8b021'][(r() * 3) | 0] });
      this.camels = L.camels.map(([u, v], i) => ({ ...this.pt(u, v), tx: 0, ty: 0, wait: r() * 3, walk: 0, facing: 1, id: i }));
      this.crew = [];
      const types = ['kampe', 'skytt', 'kampe', 'plundrare', 'skytt'];
      for (let i = 0; i < 5; i++) this.crew.push({ type: types[i], ...this.pt(L.crew[0] + i * L.crew[1] * 0.6, 12 + (i % 2) * 3), tx: 0, ty: 0, wait: r() * 2, walk: 0, facing: 1, moving: false, id: i + 3, skin: A.SKINS[i % A.SKINS.length] });
      this.fleet = [];
      this.refreshFleet();
    }
    pt(u, v) { const [x, y] = W(u, v); return { x, y }; }

    refreshFleet() {
      const save = this.game.save;
      this.fleet = [];
      let i = 0;
      for (const def of D.ships) {
        if (!save.captured[def.id]) continue;
        const sh = K.ship.build(def);
        for (const b of sh.buildings) { b.alive = true; b.cx = b.x + b.w / 2; b.cy = b.y + b.h / 2; b.ang = (b.seed % 628) / 100; }
        const [u, v] = this.L.slots[i++ % this.L.slots.length];
        const [cx, cy] = W(u, v);
        this.fleet.push({ def, sh, ox: cx - (def.len * SHIP_SCALE) / 2, oy: cy - (def.beam * SHIP_SCALE) / 2, cx, cy, u, v });
      }
    }

    onLand(x, y) { return K.ship.inPoly(this.land, x, y) && x + y < coast(x - y) - 1.5; }
    blocked(x, y) {
      for (const b of [this.fort, this.camp, this.forge, this.light]) if (x > b.x - 0.3 && x < b.x + b.w + 0.3 && y > b.y - 0.3 && y < b.y + b.h + 0.3) return true;
      return false;
    }
    randomLandPoint(r) {
      for (let k = 0; k < 30; k++) {
        const wu = this.L.walkU, u = -wu + Math.random() * wu * 2, v = 2 + Math.random() * 15;
        const [x, y] = W(u, v);
        if (this.onLand(x, y) && !this.blocked(x, y)) return [x, y];
      }
      return [this.fort.cx + 3, this.fort.cy + 3];
    }

    update(dt) {
      this.t += dt;
      const walkers = [...this.crew.map((c) => [c, 1.4]), ...this.camels.map((c) => [c, 0.6])];
      for (const [c, spd] of walkers) {
        if (c.wait > 0) { c.wait -= dt; c.moving = false; if (c.wait <= 0) { const [x, y] = this.randomLandPoint(); c.tx = x; c.ty = y; } continue; }
        const dx = c.tx - c.x, dy = c.ty - c.y, d = Math.hypot(dx, dy);
        if (d < 0.1) { c.wait = 1.5 + Math.random() * 4; c.moving = false; continue; }
        const nx = c.x + (dx / d) * spd * dt, ny = c.y + (dy / d) * spd * dt;
        if (this.blocked(nx, ny)) { c.wait = 0.5; c.moving = false; continue; }
        c.x = nx; c.y = ny; c.moving = true; c.walk += dt * spd * 7;
        if (Math.abs(dx - dy) > 0.05) c.facing = dx - dy > 0 ? 1 : -1;
      }
    }

    shipGold(f) {
      const save = this.game.save;
      const last = save.fleet[f.def.id] || Date.now();
      return Math.min(f.def.cap, Math.floor((f.def.income * (Date.now() - last)) / 60000));
    }
    bubblePos(f) { return P(f.cx, f.cy, WL + 140 * SHIP_SCALE + 40); }

    bounds() {
      if (this.portrait) {
        const last = this.fleet.length ? this.L.slots[this.fleet.length - 1][1] + 9 : 30;
        return { x0: -11.5 * 32, x1: 11.5 * 32, y0: -40, y1: last * 16 };
      }
      const ys = this.fleet.length > 3 ? 54 : this.fleet.length ? 40 : 30;
      return { x0: -26 * 32, x1: 26 * 32, y0: -2 * 16 - 60, y1: ys * 16 };
    }

    // ---------- ritning ----------
    render(ctx, cam, cw, ch, dpr, t) {
      // statisk terräng ritas i ett skärmstort lager som bara görs om när kameran rör sig
      if (!this.layer) this.layer = document.createElement('canvas');
      const key = [cam.x.toFixed(2), cam.y.toFixed(2), cam.z.toFixed(4), dpr, cw, ch, this.game.save.harborLvl].join('|');
      if (this.layerKey !== key) {
        this.layerKey = key;
        this.layer.width = ctx.canvas.width; this.layer.height = ctx.canvas.height;
        const c = this.layer.getContext('2d');
        c.setTransform(dpr, 0, 0, dpr, 0, 0);
        const g = c.createLinearGradient(0, 0, 0, ch);
        g.addColorStop(0, '#0f6c8a'); g.addColorStop(1, '#0b5873');
        c.fillStyle = g; c.fillRect(0, 0, cw, ch);
        cam.apply(c, cw, ch, dpr);
        this.terrain(c);
      }
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.drawImage(this.layer, 0, 0);
      cam.apply(ctx, cw, ch, dpr);
      G.waves(ctx, this.waves, t, WL, 0.85);
      // skum längs kusten
      ctx.strokeStyle = 'rgba(255,255,255,.75)'; ctx.lineWidth = 4;
      ctx.beginPath();
      this.coastPts.forEach(([x, y], i) => { const o = 0.35 + Math.sin(t * 1.8 + i * 0.7) * 0.18; const [X, Y] = P(x + o, y + o, WL); if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); });
      ctx.stroke();
      for (const [u, v, len] of this.jetties) this.jetty(ctx, u, v, len);
      for (const sk of this.moored) A.skiff(ctx, { ...sk, moving: false }, t, WL);
      this.drawLive(ctx, t);
    }

    terrain(ctx) {
      // grunt vatten nära kusten
      const shallow = this.coastPts.map(([x, y]) => P(x + 1.6, y + 1.6, WL)).concat([P(...W(90, coast(90) - 4), WL), P(...W(-90, coast(-90) - 4), WL)]);
      G.poly(ctx, shallow, '#2bb3c4', null);
      const mid = this.coastPts.map(([x, y]) => P(x + 4.5, y + 4.5, WL)).concat([P(...W(90, 0), WL), P(...W(-90, 0), WL)]);
      ctx.globalAlpha = 0.35; G.poly(ctx, mid, '#1c97b0', null); ctx.globalAlpha = 1;
      // land med kantsida
      for (let i = 0; i < this.coastPts.length - 1; i++) {
        const a = this.coastPts[i], b = this.coastPts[i + 1];
        G.poly(ctx, [P(a[0], a[1], 0), P(b[0], b[1], 0), P(b[0], b[1], WL), P(a[0], a[1], WL)], '#c9a464', null);
      }
      G.poly(ctx, this.land.map(([x, y]) => P(x, y, 0)), '#ecd29b', null);
      ctx.save(); G.path(ctx, this.land.map(([x, y]) => P(x, y, 0))); ctx.clip();
      for (const [x, y, r, k] of this.sandPatches) G.disc(ctx, x, y, r, 0, k > 0.5 ? 'rgba(201,164,100,.35)' : 'rgba(150,160,80,.22)', null);
      // våt sand
      ctx.strokeStyle = 'rgba(176,140,80,.5)'; ctx.lineWidth = 10; ctx.beginPath();
      this.coastPts.forEach(([x, y], i) => { const [X, Y] = P(x - 0.35, y - 0.35, 0); if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); });
      ctx.stroke();
      // stigar
      ctx.strokeStyle = 'rgba(190,150,90,.55)'; ctx.lineWidth = 14; ctx.lineCap = 'round';
      ctx.beginPath();
      for (const b of [this.camp, this.forge]) { const a = P(this.fort.cx, this.fort.cy, 0), e = P(b.cx, b.cy, 0); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]); }
      for (const [u] of this.jetties) { const a = P(this.fort.cx, this.fort.cy, 0), e = P(...W(u, 19), 0); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]); }
      ctx.stroke();
      ctx.restore();
      ctx.strokeStyle = OUT; ctx.lineWidth = 2; ctx.beginPath();
      this.coastPts.forEach(([x, y], i) => { const [X, Y] = P(x, y, WL); if (i) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); });
      ctx.stroke();
    }

    drawLive(ctx, t) {
      const cam = this.game.camHome, dpr = this.game.dpr;
      // föremål på land, djupsorterade
      const items = [];
      for (const b of [this.fort, this.camp, this.forge, this.light]) items.push([b.cx + b.cy, b]);
      for (const d of this.deco) items.push([d.x + d.y, d]);
      for (const c of this.crew) items.push([c.x + c.y, { type: 'crew', c }]);
      for (const c of this.camels) items.push([c.x + c.y, { type: 'camel', c }]);
      items.sort((a, b) => a[0] - b[0]);
      for (const [, o] of items) this.drawItem(ctx, o, t);

      // flottan
      const fl = this.fleet.slice().sort((a, b) => a.cx + a.cy - b.cx - b.cy);
      for (const f of fl) {
        const bob = Math.sin(t * 1.1 + f.u) * 1.5;
        const [OX, OY] = P(f.ox, f.oy, WL + A.HULL * SHIP_SCALE);
        ctx.save();
        ctx.translate(OX, OY + bob);
        ctx.scale(SHIP_SCALE, SHIP_SCALE);
        A.spriteScale = cam.z * dpr * SHIP_SCALE;
        A.shipFull(ctx, f.sh, t + f.u, { pirate: true });
        A.spriteScale = 0;
        ctx.restore();
      }
      for (const f of fl) {
        const gold = this.shipGold(f);
        if (gold < 1) continue;
        const [X, Y] = this.bubblePos(f);
        const by = Y + Math.sin(t * 3 + f.u) * 4;
        G.blob(ctx, X, by, 22, 22, '#ffffff', OUT, 2.5);
        const fr = gold / f.def.cap;
        ctx.beginPath(); ctx.arc(X, by, 18.5, -Math.PI / 2, -Math.PI / 2 + fr * Math.PI * 2); ctx.strokeStyle = fr >= 1 ? '#ff5a3a' : '#7be043'; ctx.lineWidth = 4; ctx.stroke();
        G.blob(ctx, X, by, 11, 11, '#ffcf3a', OUT, 2);
        G.blob(ctx, X, by, 6.5, 6.5, null, '#c98a00', 2);
        ctx.beginPath(); ctx.moveTo(X - 6, by + 30); ctx.lineTo(X, by + 22); ctx.lineTo(X + 6, by + 30); ctx.fillStyle = '#fff'; ctx.fill();
      }
    }

    jetty(ctx, u, v, len) {
      const [x0, y0] = W(u, v - 1.2), [x1, y1] = W(u, v + len);
      // längs (1,1): bredd vinkelrätt i u-led
      const hw = 0.55;
      const corners = (zz) => [P(x0 + hw / 2, y0 - hw / 2, zz), P(x1 + hw / 2, y1 - hw / 2, zz), P(x1 - hw / 2, y1 + hw / 2, zz), P(x0 - hw / 2, y0 + hw / 2, zz)];
      const steps = Math.round(len + 1.2);
      for (let i = 0; i <= steps; i += 1.5) {
        const f = i / steps;
        for (const s of [-1, 1]) { const x = x0 + (x1 - x0) * f + s * hw / 2, y = y0 + (y1 - y0) * f - s * hw / 2; G.line(ctx, P(x, y, -2), P(x, y, WL - 2), '#5a3a20', 3); }
      }
      const top = corners(-2), bot = corners(-6);
      G.poly(ctx, [top[1], top[2], bot[2], bot[1]], G.col('#8a5a2b', -0.3), OUT, 1.4);
      G.poly(ctx, [top[2], top[3], bot[3], bot[2]], G.col('#8a5a2b', -0.15), OUT, 1.4);
      G.poly(ctx, top, '#a8743e', OUT, 1.6);
      ctx.strokeStyle = 'rgba(60,35,15,.45)'; ctx.lineWidth = 1; ctx.beginPath();
      for (let i = 1; i < steps * 2; i++) { const f = i / (steps * 2); const x = x0 + (x1 - x0) * f, y = y0 + (y1 - y0) * f; const a = P(x + hw / 2, y - hw / 2, -2), b = P(x - hw / 2, y + hw / 2, -2); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
      ctx.stroke();
    }

    drawItem(ctx, o, t) {
      switch (o.type) {
        case 'fort': return this.drawFort(ctx, o, t);
        case 'camp': return this.drawCamp(ctx, o, t);
        case 'forge': return this.drawForge(ctx, o, t);
        case 'light': return this.drawLight(ctx, o, t);
        case 'palm': return drawPalm(ctx, o, t);
        case 'acacia': return drawAcacia(ctx, o, t);
        case 'rock': { const [X, Y] = P(o.x, o.y, 0); G.blob(ctx, X, Y - 4 * o.s, 12 * o.s, 7 * o.s, '#9c8f7e', OUT, 1.6); G.blob(ctx, X - 3 * o.s, Y - 7 * o.s, 5 * o.s, 3 * o.s, 'rgba(255,255,255,.25)', null); return; }
        case 'barrel': { G.cyl(ctx, o.x, o.y, 0.22, 0, 16, '#8a5a2b'); const [X, Y] = P(o.x, o.y, 8); ctx.strokeStyle = '#3b2412'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.ellipse(X, Y, 10, 5, 0, 0, Math.PI); ctx.stroke(); return; }
        case 'crew': { const c = o.c; const [X, Y] = P(c.x, c.y, 0); A.unit(ctx, { ...c, type: c.type }, X, Y, t); return; }
        case 'camel': return drawCamel(ctx, o.c, t);
      }
    }

    sel(b) { return this.game.harborSel === b.type; }

    drawFort(ctx, b, t) {
      const x0 = b.x, y0 = b.y, x1 = b.x + b.w, y1 = b.y + b.h, wall = '#f3efe6';
      const lvl = this.game.save.harborLvl;
      G.box(ctx, x0 + 0.3, y0 + 0.3, x1 - 0.3, y1 - 0.3, 0, 34, wall);
      // kreneleringar
      for (let i = 0; i < 5; i++) {
        const f = 0.15 + i * 0.175;
        const xa = x0 + 0.3 + (x1 - x0 - 0.6) * f;
        G.box(ctx, xa, y1 - 0.5, xa + 0.3, y1 - 0.3, 34, 41, wall, { lw: 1.2 });
        const ya = y0 + 0.3 + (y1 - y0 - 0.6) * f;
        G.box(ctx, x1 - 0.5, ya, x1 - 0.3, ya + 0.3, 34, 41, wall, { lw: 1.2 });
      }
      // port med ljusblå dörr
      const cx = (x0 + x1) / 2;
      G.poly(ctx, [P(cx - 0.45, y1 - 0.3, 0), P(cx - 0.45, y1 - 0.3, 16), P(cx - 0.25, y1 - 0.3, 22), P(cx + 0.25, y1 - 0.3, 22), P(cx + 0.45, y1 - 0.3, 16), P(cx + 0.45, y1 - 0.3, 0)], G.col('#4aa3df'), OUT, 1.6);
      G.line(ctx, P(cx, y1 - 0.3, 0), P(cx, y1 - 0.3, 22), OUT, 1.2);
      G.poly(ctx, [P(x1 - 0.3, b.cy - 0.25, 26), P(x1 - 0.3, b.cy + 0.25, 26), P(x1 - 0.3, b.cy + 0.25, 18), P(x1 - 0.3, b.cy - 0.25, 18)], G.col('#2d4a6b'), OUT, 1.2);
      // torn i hörnen
      for (const [x, y] of [[x0 + 0.45, y0 + 0.45], [x1 - 0.45, y0 + 0.45], [x0 + 0.45, y1 - 0.45], [x1 - 0.45, y1 - 0.45]]) {
        const h = 46 + lvl * 3;
        G.cyl(ctx, x, y, 0.5, 0, h, wall);
        G.cyl(ctx, x, y, 0.58, h, h + 7, '#e6dfcf');
        G.disc(ctx, x, y, 0.36, h + 7, '#c9bfa8', null);
      }
      const [FX, FY] = P(x0 + 0.45, y0 + 0.45, 53 + lvl * 3);
      A.flag(ctx, FX, FY - 30, 'pirate', t, 1.3);
      // nivåmärke
      const [LX, LY] = P(x1 - 0.3, b.cy, 30);
      G.blob(ctx, LX + 6, LY - 2, 9, 9, '#ffcf3a', OUT, 2);
      ctx.fillStyle = OUT; ctx.font = '700 11px "Lilita One", system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText(String(lvl), LX + 6, LY - 1);
    }

    drawCamp(ctx, b, t) {
      const cx = b.cx, cy = b.cy;
      // tält
      const base = [[cx - 1.5, cy - 1.2], [cx + 0.4, cy - 1.2], [cx + 0.4, cy + 0.7], [cx - 1.5, cy + 0.7]];
      const apex = P(cx - 0.55, cy - 0.25, 62);
      const pb = base.map(([x, y]) => P(x, y, 0));
      G.poly(ctx, [pb[3], pb[2], apex], '#c8402e');
      G.poly(ctx, [pb[2], pb[1], apex], '#e3e3dc');
      ctx.save(); G.path(ctx, [pb[3], pb[2], apex]); ctx.clip();
      ctx.fillStyle = '#f4f1ea';
      for (let i = 0; i < 5; i++) { const a = P(cx - 1.5 + i * 0.42, cy + 0.7, 0); ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(apex[0], apex[1]); ctx.lineTo(a[0] + 9, a[1] - 4); ctx.closePath(); ctx.fill(); }
      ctx.restore();
      G.poly(ctx, [pb[3], pb[2], apex], null);
      G.poly(ctx, [P(cx - 0.85, cy + 0.7, 0), P(cx - 0.55, cy + 0.7, 22), P(cx - 0.25, cy + 0.7, 0)], '#3b2412', OUT, 1.2);
      // lägereld
      const fx = cx + 0.8, fy = cy + 0.8;
      for (const a of [0.3, 1.9, 3.5]) G.thick(ctx, P(fx - Math.cos(a) * 0.35, fy - Math.sin(a) * 0.35, 2), P(fx + Math.cos(a) * 0.35, fy + Math.sin(a) * 0.35, 4), '#6b4024', 4);
      const [X, Y] = P(fx, fy, 4);
      ctx.globalCompositeOperation = 'lighter';
      for (let i = 0; i < 4; i++) {
        const h = 10 + Math.sin(t * 12 + i * 1.7) * 4;
        G.blob(ctx, X + (i - 1.5) * 3, Y - h / 2, 4, h / 2 + 2, i % 2 ? '#ff8a1c' : '#ffd23f', null);
      }
      ctx.globalCompositeOperation = 'source-over';
      const g = ctx.createRadialGradient(X, Y, 0, X, Y, 40);
      g.addColorStop(0, 'rgba(255,170,60,.35)'); g.addColorStop(1, 'rgba(255,170,60,0)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(X, Y, 40, 0, 7); ctx.fill();
      // skylt
      const [SX, SY] = P(cx + 1.1, cy - 0.9, 0);
      G.line(ctx, [SX, SY], [SX, SY - 26], '#5a3a20', 3);
      G.poly(ctx, [[SX - 16, SY - 34], [SX + 16, SY - 34], [SX + 16, SY - 22], [SX - 16, SY - 22]], '#a8743e', OUT, 1.5);
      ctx.fillStyle = '#fff'; ctx.font = '10px "Lilita One", system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('ARMÉ', SX, SY - 27.5);
    }

    drawForge(ctx, b, t) {
      const cx = b.cx, cy = b.cy;
      G.box(ctx, b.x + 0.4, b.y + 0.4, b.x + b.w - 0.6, b.y + b.h - 0.6, 0, 26, '#d9c8a6');
      G.poly(ctx, [P(b.x + b.w - 0.6, cy - 0.3, 18), P(b.x + b.w - 0.6, cy + 0.3, 18), P(b.x + b.w - 0.6, cy + 0.3, 0), P(b.x + b.w - 0.6, cy - 0.3, 0)], '#3b2412', OUT, 1.3);
      // stråtak
      const r = [P(b.x + 0.15, b.y + 0.15, 26), P(b.x + b.w - 0.35, b.y + 0.15, 26), P(b.x + b.w - 0.35, b.y + b.h - 0.35, 26), P(b.x + 0.15, b.y + b.h - 0.35, 26)];
      const apex = P(cx - 0.1, cy - 0.1, 58);
      G.poly(ctx, [r[3], r[2], apex], G.col('#c49a4a', -0.15));
      G.poly(ctx, [r[2], r[1], apex], G.col('#d8b25e'));
      ctx.strokeStyle = 'rgba(90,60,20,.45)'; ctx.lineWidth = 1; ctx.beginPath();
      for (let i = 1; i < 8; i++) { const f = i / 8; for (const [a, c] of [[r[3], r[2]], [r[2], r[1]]]) { const p = [a[0] + (c[0] - a[0]) * f, a[1] + (c[1] - a[1]) * f]; ctx.moveTo(p[0], p[1]); ctx.lineTo(apex[0], apex[1]); } }
      ctx.stroke();
      // städ och ässja
      const ax = b.x + b.w - 0.1, ay = cy + 0.9;
      G.box(ctx, ax - 0.35, ay - 0.15, ax + 0.1, ay + 0.15, 0, 7, '#3a3f48', { lw: 1.2 });
      G.box(ctx, ax - 0.5, ay - 0.2, ax + 0.25, ay + 0.2, 7, 12, '#4a5058', { lw: 1.2 });
      const [GX, GY] = P(b.x + b.w - 0.6, cy - 0.9, 8);
      const gl = 0.5 + Math.sin(t * 5) * 0.2;
      const g = ctx.createRadialGradient(GX, GY, 0, GX, GY, 26);
      g.addColorStop(0, `rgba(255,140,40,${gl})`); g.addColorStop(1, 'rgba(255,140,40,0)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(GX, GY, 26, 0, 7); ctx.fill();
      for (let i = 0; i < 3; i++) {
        const f = (((t * 0.4 + i / 3) % 1) + 1) % 1;
        const [X, Y] = P(cx - 0.1 - f * 0.5, cy - 0.1 - f * 0.3, 60 + f * 50);
        ctx.globalAlpha = (1 - f) * 0.5; G.blob(ctx, X, Y, 5 + f * 9, 4 + f * 8, '#d6d6d6', null); ctx.globalAlpha = 1;
      }
      const [SX, SY] = P(b.x + 0.2, b.y + b.h + 0.1, 0);
      G.line(ctx, [SX, SY], [SX, SY - 26], '#5a3a20', 3);
      G.poly(ctx, [[SX - 20, SY - 34], [SX + 20, SY - 34], [SX + 20, SY - 22], [SX - 20, SY - 22]], '#a8743e', OUT, 1.5);
      ctx.fillStyle = '#fff'; ctx.font = '10px "Lilita One", system-ui, sans-serif'; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText('SMEDJA', SX, SY - 27.5);
    }

    drawLight(ctx, b, t) {
      const cx = b.cx, cy = b.cy;
      G.cyl(ctx, cx, cy, 0.62, 0, 10, '#9c8f7e');
      const bands = ['#f4f4f4', '#d23b2c', '#f4f4f4', '#d23b2c', '#f4f4f4'];
      bands.forEach((c, i) => G.cyl(ctx, cx, cy, 0.48 - i * 0.03, 10 + i * 18, 28 + i * 18, c));
      const top = 100;
      G.cyl(ctx, cx, cy, 0.5, top, top + 4, '#22252c');
      G.cyl(ctx, cx, cy, 0.34, top + 4, top + 16, '#fff3a0');
      G.cyl(ctx, cx, cy, 0.42, top + 16, top + 20, '#d23b2c');
      const [X, Y] = P(cx, cy, top + 10);
      const a = t * 1.2;
      ctx.globalCompositeOperation = 'lighter';
      const gr = ctx.createRadialGradient(X, Y, 0, X, Y, 160);
      gr.addColorStop(0, 'rgba(255,245,180,.45)'); gr.addColorStop(1, 'rgba(255,245,180,0)');
      ctx.fillStyle = gr;
      ctx.beginPath(); ctx.moveTo(X, Y); ctx.arc(X, Y, 160, a - 0.18, a + 0.18); ctx.closePath(); ctx.fill();
      ctx.globalCompositeOperation = 'source-over';
    }

    // ---------- tryck ----------
    hit(X, Y) {
      for (const f of this.fleet) {
        if (this.shipGold(f) < 1) continue;
        const [BX, BY] = this.bubblePos(f);
        if (Math.hypot(X - BX, Y - BY) < 30) return { type: 'collect', f };
      }
      const box = (b, h) => {
        const pts = [P(b.x, b.y, 0), P(b.x + b.w, b.y, 0), P(b.x + b.w, b.y + b.h, 0), P(b.x, b.y + b.h, 0), P(b.x, b.y, h)];
        const xs = pts.map((p) => p[0]), ys = pts.map((p) => p[1]);
        return X >= Math.min(...xs) && X <= Math.max(...xs) && Y >= Math.min(...ys) && Y <= Math.max(...ys);
      };
      if (box(this.fort, 70)) return { type: 'fort' };
      if (box(this.camp, 50)) return { type: 'camp' };
      if (box(this.forge, 60)) return { type: 'forge' };
      for (const f of this.fleet) {
        const [SX, SY] = P(f.cx, f.cy, WL);
        if (Math.abs(X - SX) < f.def.len * SHIP_SCALE * 22 && Math.abs(Y - SY + 20) < f.def.len * SHIP_SCALE * 12) return { type: 'ship', f };
      }
      return null;
    }
  }

  function drawPalm(ctx, o, t) {
    const [X, Y] = P(o.x, o.y, 0);
    const s = o.s, sway = Math.sin(t * 1.3 + o.ph) * 3 * s;
    G.shadow(ctx, X + 10 * s, Y + 3, 22 * s, 9 * s, 0.16);
    const tx = X + 8 * s + sway, ty = Y - 70 * s;
    ctx.lineCap = 'round';
    ctx.strokeStyle = OUT; ctx.lineWidth = 9 * s;
    ctx.beginPath(); ctx.moveTo(X, Y); ctx.quadraticCurveTo(X - 2 * s, Y - 40 * s, tx, ty); ctx.stroke();
    ctx.strokeStyle = '#8a6440'; ctx.lineWidth = 6 * s; ctx.stroke();
    ctx.strokeStyle = '#6e4f31'; ctx.lineWidth = 1.2;
    for (let i = 1; i < 7; i++) { const f = i / 7; const px = X + (tx - X) * f * f * 0.9 - 2 * s * (1 - f), py = Y + (ty - Y) * f; ctx.beginPath(); ctx.moveTo(px - 3 * s, py); ctx.lineTo(px + 3 * s, py - 1); ctx.stroke(); }
    for (let k = 0; k < 7; k++) {
      const a = (k / 7) * Math.PI * 2 + Math.sin(t + o.ph + k) * 0.06;
      const ex = tx + Math.cos(a) * 30 * s, ey = ty + Math.sin(a) * 12 * s + 10 * s;
      ctx.beginPath(); ctx.moveTo(tx, ty);
      ctx.quadraticCurveTo(tx + Math.cos(a) * 18 * s, ty + Math.sin(a) * 7 * s - 12 * s, ex, ey);
      ctx.quadraticCurveTo(tx + Math.cos(a) * 14 * s, ty + Math.sin(a) * 6 * s - 3 * s, tx, ty);
      ctx.fillStyle = k % 2 ? '#3f9a3a' : '#52b448'; ctx.fill(); ctx.lineWidth = 1.4; ctx.strokeStyle = OUT; ctx.stroke();
    }
    for (const dx of [-3, 3]) G.blob(ctx, tx + dx * s, ty + 4 * s, 3.2 * s, 3.2 * s, '#6b4a22', OUT, 1);
  }

  function drawAcacia(ctx, o, t) {
    const [X, Y] = P(o.x, o.y, 0);
    const s = o.s;
    G.shadow(ctx, X, Y + 2, 30 * s, 12 * s, 0.16);
    ctx.lineCap = 'round';
    for (const [dx, h] of [[-10, 38], [8, 42], [0, 46]]) {
      G.thick(ctx, [X, Y], [X + dx * s, Y - h * s], '#6b4a2e', 4 * s);
    }
    const sway = Math.sin(t * 0.9 + o.ph) * 1.5;
    G.blob(ctx, X + sway, Y - 50 * s, 38 * s, 11 * s, '#4f7a2e', OUT, 1.8);
    G.blob(ctx, X - 6 * s + sway, Y - 55 * s, 26 * s, 8 * s, '#679a3b', null);
    G.blob(ctx, X + 10 * s + sway, Y - 53 * s, 14 * s, 5 * s, '#7cb247', null);
  }

  function drawCamel(ctx, c, t) {
    const [X, Y] = P(c.x, c.y, 0);
    G.shadow(ctx, X, Y, 20, 7, 0.22);
    ctx.save(); ctx.translate(X, Y); ctx.scale(c.facing, 1);
    const w = c.moving ? c.walk : 0;
    const col = '#c99a5b';
    for (const [lx, ph] of [[-9, 0], [-5, Math.PI], [6, Math.PI / 2], [10, Math.PI * 1.5]]) {
      const sw = c.moving ? Math.sin(w + ph) * 3 : 0;
      G.thick(ctx, [lx, -18], [lx + sw, -1], G.col(col, -0.2), 3.2);
    }
    const bob = c.moving ? Math.abs(Math.sin(w)) * 1.5 : 0;
    G.blob(ctx, 0, -23 - bob, 15, 7.5, G.col(col), OUT, 1.6);
    G.blob(ctx, -2, -31 - bob, 7.5, 6.5, G.col(col, 0.05), OUT, 1.6);
    G.thick(ctx, [12, -24 - bob], [19, -38 - bob], G.col(col), 5);
    G.blob(ctx, 22, -39 - bob, 5.5, 3.6, G.col(col), OUT, 1.4);
    G.blob(ctx, 23, -40 - bob, 1, 1, OUT, null);
    G.blob(ctx, -14, -22 - bob, 2, 4, G.col(col, -0.25), OUT, 1);
    ctx.fillStyle = '#c8402e'; ctx.fillRect(-6, -30 - bob, 9, 3);
    ctx.restore();
  }

  K.Harbor = Harbor;
  K.HARBOR_WL = WL;
})();
