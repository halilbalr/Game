// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Skrov, däck, byggnader, barrikader, ruiner och dryckszoner.
(function () {
  const K = window.K, G = K.gfx, P = G.P, OUT = G.OUT, A = K.art;
  const HULL = (A.HULL = 34); // skrovhöjd över vattnet (px)

  // Förberäknar kanter, normaler och skumkontur för ett skepp
  function prep(sh) {
    if (sh.edges) return;
    const pts = sh.poly, n = pts.length;
    sh.edges = [];
    const normals = [];
    for (let i = 0; i < n; i++) {
      const a = pts[i], b = pts[(i + 1) % n];
      let nx = b[1] - a[1], ny = -(b[0] - a[0]);
      const l = Math.hypot(nx, ny) || 1; nx /= l; ny /= l;
      const mx = (a[0] + b[0]) / 2, my = (a[1] + b[1]) / 2;
      if (K.ship.inPoly(pts, mx + nx * 0.03, my + ny * 0.03)) { nx = -nx; ny = -ny; }
      normals.push([nx, ny]);
      sh.edges.push({ a, b, nx, ny, len: l, vis: nx + ny > 0.02 });
    }
    sh.foam = pts.map((p, i) => {
      const n0 = normals[(i - 1 + n) % n], n1 = normals[i];
      let nx = n0[0] + n1[0], ny = n0[1] + n1[1];
      const l = Math.hypot(nx, ny) || 1;
      return [p[0], p[1], nx / l, ny / l];
    });
    // reling-stolpar ungefär varje ruta
    sh.posts = [];
    let acc = 0;
    for (const e of sh.edges) {
      let d = 0;
      while (acc + (e.len - d) >= 1) { d += 1 - acc; acc = 0; const f = d / e.len; sh.posts.push([e.a[0] + (e.b[0] - e.a[0]) * f, e.a[1] + (e.b[1] - e.a[1]) * f]); }
      acc += e.len - d;
    }
  }
  A.prepShip = prep;

  A.water = function (ctx, sh, t) {
    prep(sh);
    const z = -HULL;
    const ring = (d, wob) => sh.foam.map(([x, y, nx, ny], i) => P(x + nx * (d + Math.sin(t * 2 + i * 0.9) * wob), y + ny * (d + Math.sin(t * 2 + i * 0.9) * wob), z));
    G.poly(ctx, ring(0.7, 0.12), 'rgba(255,255,255,.14)', null);
    G.poly(ctx, ring(0.32, 0.07), 'rgba(255,255,255,.45)', null);
  };

  A.hull = function (ctx, sh, t) {
    prep(sh);
    const pal = sh.def.pal;
    for (const e of sh.edges) {
      if (!e.vis) continue;
      const f = -0.05 - 0.35 * ((e.ny - e.nx + 1) / 2);
      const a0 = P(e.a[0], e.a[1], 0), b0 = P(e.b[0], e.b[1], 0);
      const a1 = P(e.a[0], e.a[1], -HULL), b1 = P(e.b[0], e.b[1], -HULL);
      const a2 = P(e.a[0], e.a[1], -HULL + 10), b2 = P(e.b[0], e.b[1], -HULL + 10);
      G.poly(ctx, [a0, b0, b1, a1], G.col(pal.hull, f), null);
      G.poly(ctx, [a2, b2, b1, a1], G.col(pal.stripe, f), null);
      G.line(ctx, a2, b2, 'rgba(255,255,255,.7)', 1.6);
      // ljuskant upptill
      G.line(ctx, P(e.a[0], e.a[1], -3), P(e.b[0], e.b[1], -3), G.rgba('#ffffff', 0.18), 2);
      if (e.len > 1.4) {
        const k = Math.floor(e.len / 1.5);
        for (let i = 1; i <= k; i++) {
          const fr = i / (k + 1);
          const [X, Y] = P(e.a[0] + (e.b[0] - e.a[0]) * fr, e.a[1] + (e.b[1] - e.a[1]) * fr, -14);
          G.blob(ctx, X, Y, 2.6, 2.6, '#1d2a36', 'rgba(255,255,255,.35)', 1);
        }
      }
    }
    // konturer
    ctx.strokeStyle = OUT; ctx.lineWidth = 2.2; ctx.lineJoin = 'round';
    for (const e of sh.edges) {
      if (!e.vis) continue;
      const a1 = P(e.a[0], e.a[1], -HULL), b1 = P(e.b[0], e.b[1], -HULL);
      ctx.beginPath(); ctx.moveTo(a1[0], a1[1]); ctx.lineTo(b1[0], b1[1]); ctx.stroke();
    }
    const L = sh.edges.filter((e) => e.vis);
    // vertikala ytterkanter (där synliga sidor börjar/slutar)
    for (let i = 0; i < sh.edges.length; i++) {
      const e = sh.edges[i], nx = sh.edges[(i + 1) % sh.edges.length];
      if (e.vis !== nx.vis) {
        const p = e.b;
        G.line(ctx, P(p[0], p[1], 0), P(p[0], p[1], -HULL), OUT, 2.2);
      }
    }
    return L;
  };

  A.deck = function (ctx, sh, t) {
    prep(sh);
    const pal = sh.def.pal;
    const deckPts = sh.poly.map(([x, y]) => P(x, y, 0));
    G.poly(ctx, deckPts, G.col(pal.deck), null);
    ctx.save();
    G.path(ctx, deckPts); ctx.clip();
    const W = sh.W, H = sh.H;
    ctx.strokeStyle = G.rgba(pal.deckLine, 0.55); ctx.lineWidth = 1;
    ctx.beginPath();
    const step = sh.def.deckType === 'wood' ? 0.5 : 1;
    for (let y = step; y < H; y += step) { const a = P(-1, y, 0), b = P(W + 1, y, 0); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
    if (sh.def.deckType === 'steel') for (let x = 3; x < W; x += 3) { const a = P(x, -1, 0), b = P(x, H + 1, 0); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
    else {
      const r = G.rng(7);
      for (let y = 0; y < H; y += step) for (let x = 0; x < W; x += 2.5 + r() * 2) {
        const a = P(x + r(), y, 0), b = P(x + r(), y + step, 0); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]);
      }
    }
    ctx.stroke();
    for (const d of sh.def.decals || []) {
      const [x, y, w, h] = d;
      G.poly(ctx, [P(x + 0.1, y + 0.1), P(x + w - 0.1, y + 0.1), P(x + w - 0.1, y + h - 0.1), P(x + 0.1, y + h - 0.1)], G.col(pal.deck, -0.18), G.rgba('#000000', 0.3), 1.4);
      ctx.strokeStyle = G.rgba('#000000', 0.15); ctx.beginPath();
      for (let k = 1; k < w * 2; k++) { const a = P(x + k / 2, y + 0.2), b = P(x + k / 2, y + h - 0.2); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); }
      ctx.stroke();
    }
    // mörkare skuggrand innanför relingen
    ctx.strokeStyle = 'rgba(0,0,0,.18)'; ctx.lineWidth = 7; G.path(ctx, deckPts); ctx.stroke();
    ctx.restore();
    G.poly(ctx, deckPts, null, OUT, 2.4);
    // reling
    const rc = G.col(pal.house, -0.05);
    ctx.lineCap = 'round';
    for (const [x, y] of sh.posts) G.line(ctx, P(x, y, 0), P(x, y, 9), G.col(pal.house, -0.25), 1.6);
    ctx.strokeStyle = OUT; ctx.lineWidth = 3.6; G.path(ctx, sh.poly.map(([x, y]) => P(x, y, 9))); ctx.stroke();
    ctx.strokeStyle = rc; ctx.lineWidth = 1.8; ctx.stroke();
  };

  // ---------- byggnader ----------
  const lerp = (a, b, t) => a + (b - a) * t;

  function faceWindowsX(ctx, x, ya, yb, z0, z1, n, glass) {
    for (let i = 0; i < n; i++) {
      const y0 = lerp(ya, yb, i / n) + 0.06, y1 = lerp(ya, yb, (i + 1) / n) - 0.06;
      G.poly(ctx, [P(x, y0, z1), P(x, y1, z1), P(x, y1, z0), P(x, y0, z0)], glass, OUT, 1);
      G.line(ctx, P(x, y0 + 0.08, z1 - 2), P(x, lerp(y0, y1, 0.4), z1 - 2), 'rgba(255,255,255,.55)', 1.2);
    }
  }
  function faceWindowsY(ctx, y, xa, xb, z0, z1, n, glass) {
    for (let i = 0; i < n; i++) {
      const x0 = lerp(xa, xb, i / n) + 0.06, x1 = lerp(xa, xb, (i + 1) / n) - 0.06;
      G.poly(ctx, [P(x0, y, z1), P(x1, y, z1), P(x1, y, z0), P(x0, y, z0)], glass, OUT, 1);
      G.line(ctx, P(x0 + 0.08, y, z1 - 2), P(lerp(x0, x1, 0.4), y, z1 - 2), 'rgba(255,255,255,.45)', 1.2);
    }
  }

  function barrel(ctx, cx, cy, z, ang, len, w, color) {
    const a = P(cx, cy, z), b = P(cx + Math.cos(ang) * len, cy + Math.sin(ang) * len, z + 2);
    G.thick(ctx, a, b, G.col(color), w);
    ctx.strokeStyle = 'rgba(255,255,255,.3)'; ctx.lineWidth = w * 0.25;
    ctx.beginPath(); ctx.moveTo(a[0], a[1] - w * 0.25); ctx.lineTo(b[0], b[1] - w * 0.25); ctx.stroke();
    G.blob(ctx, b[0], b[1], w * 0.62, w * 0.55, G.col(color, -0.35), OUT, 1.4);
    return b;
  }

  const B = {};

  B.brygga = function (ctx, b, sh, t, o) {
    const pal = sh.def.pal;
    const x0 = b.x + 0.15, y0 = b.y + 0.15, x1 = b.x + b.w - 0.15, y1 = b.y + b.h - 0.15;
    G.box(ctx, x0, y0, x1, y1, 0, 44, pal.house);
    const glass = G.col('#2d4a6b');
    faceWindowsX(ctx, x1, y0 + 0.3, y1 - 0.3, 27, 36, 4, glass);
    faceWindowsY(ctx, y1, x0 + 0.3, x1 - 0.3, 27, 36, 4, glass);
    for (let i = 0; i < 3; i++) {
      const [X, Y] = P(x1, lerp(y0 + 0.5, y1 - 0.5, i / 2), 12); G.blob(ctx, X, Y, 2.6, 3, '#2d4a6b', OUT, 1);
      const [X2, Y2] = P(lerp(x0 + 0.5, x1 - 0.5, i / 2), y1, 12); G.blob(ctx, X2, Y2, 2.6, 3, '#2d4a6b', OUT, 1);
    }
    const wx0 = x0 + 0.5, wy0 = y0 + 0.5, wx1 = x1 - 0.7, wy1 = y1 - 0.7;
    G.box(ctx, wx0, wy0, wx1, wy1, 44, 64, pal.house);
    G.poly(ctx, [P(wx1, wy0 + 0.1, 61), P(wx1, wy1 - 0.1, 61), P(wx1, wy1 - 0.1, 51), P(wx1, wy0 + 0.1, 51)], glass, OUT, 1.2);
    G.poly(ctx, [P(wx0 + 0.1, wy1, 61), P(wx1 - 0.1, wy1, 61), P(wx1 - 0.1, wy1, 51), P(wx0 + 0.1, wy1, 51)], glass, OUT, 1.2);
    G.line(ctx, P(wx1, wy0 + 0.3, 59), P(wx1, wy0 + 1, 59), 'rgba(255,255,255,.6)', 1.6);
    G.box(ctx, wx0 - 0.15, wy0 - 0.15, wx1 + 0.2, wy1 + 0.2, 64, 68, pal.accent);
    // mast med radar och flagga
    const mx = (wx0 + wx1) / 2, my = (wy0 + wy1) / 2;
    const m0 = P(mx, my, 68), m1 = P(mx, my, 104);
    G.thick(ctx, m0, m1, '#c9d1d8', 3);
    const ra = t * 2.2 + b.id;
    const r0 = P(mx - Math.cos(ra) * 0.6, my - Math.sin(ra) * 0.6, 96), r1 = P(mx + Math.cos(ra) * 0.6, my + Math.sin(ra) * 0.6, 96);
    G.thick(ctx, r0, r1, '#f4f6f8', 3.2);
    A.flag(ctx, m1[0], m1[1] - 2, o.pirate ? 'pirate' : pal.flag, t + b.id, 1);
  };

  B.kanon = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.box(ctx, b.x + 0.18, b.y + 0.18, b.x + b.w - 0.18, b.y + b.h - 0.18, 0, 6, '#6f7b86');
    G.cyl(ctx, cx, cy, 0.72, 6, 13, '#8c98a3');
    const ang = b.ang || 0, len = 1.15 - (b.recoil || 0) * 0.35;
    const behind = Math.cos(ang) + Math.sin(ang) < 0;
    if (behind) barrel(ctx, cx, cy, 20, ang, len, 8, '#3a424c');
    G.cyl(ctx, cx, cy, 0.48, 13, 25, '#5b6773');
    G.blob(ctx, ...P(cx - 0.12, cy - 0.12, 26), 5, 2.4, 'rgba(255,255,255,.3)', null);
    if (!behind) barrel(ctx, cx, cy, 20, ang, len, 8, '#3a424c');
  };

  B.vatten = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.box(ctx, b.x + 0.22, b.y + 0.22, b.x + b.w - 0.22, b.y + b.h - 0.22, 0, 10, '#d23b2c');
    G.box(ctx, b.x + 0.22, b.y + 0.22, b.x + b.w - 0.22, b.y + b.h - 0.22, 10, 13, '#f4f4f4');
    G.cyl(ctx, b.x + 0.55, b.y + b.h - 0.55, 0.26, 13, 30, '#c9d6df');
    G.cyl(ctx, cx, cy, 0.3, 13, 30, '#e9ecef');
    G.cyl(ctx, cx, cy, 0.36, 30, 37, '#d23b2c');
    const ang = b.ang || 0.6;
    const tip = barrel(ctx, cx, cy, 36, ang, 0.85 - (b.recoil || 0) * 0.1, 6.5, '#d23b2c');
    G.blob(ctx, tip[0], tip[1], 3.4, 3, '#e8b021', OUT, 1.2);
    b._nozzle = [cx + Math.cos(ang) * 0.9, cy + Math.sin(ang) * 0.9, 38];
  };

  B.utkik = function (ctx, b, sh, t) {
    const x0 = b.x + 0.3, y0 = b.y + 0.3, x1 = b.x + b.w - 0.3, y1 = b.y + b.h - 0.3;
    const wood = '#7a5232', top = 58;
    const post = (x, y) => G.box(ctx, x - 0.08, y - 0.08, x + 0.08, y + 0.08, 0, top, wood, { lw: 1.2 });
    post(x0, y0); post(x1, y0); post(x0, y1);
    ctx.strokeStyle = G.col(wood, -0.2); ctx.lineWidth = 2;
    ctx.beginPath();
    for (const [a, c] of [[[x0, y1], [x1, y1]], [[x1, y0], [x1, y1]]]) {
      const p1 = P(a[0], a[1], 8), p2 = P(c[0], c[1], top - 6), p3 = P(a[0], a[1], top - 6), p4 = P(c[0], c[1], 8);
      ctx.moveTo(p1[0], p1[1]); ctx.lineTo(p2[0], p2[1]); ctx.moveTo(p3[0], p3[1]); ctx.lineTo(p4[0], p4[1]);
    }
    ctx.stroke();
    post(x1, y1);
    G.box(ctx, b.x + 0.12, b.y + 0.12, b.x + b.w - 0.12, b.y + b.h - 0.12, top, top + 6, '#9b6a3d');
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    const [GX, GY] = P(cx, cy, top + 6);
    const face = Math.cos(b.ang || 0) - Math.sin(b.ang || 0) >= 0 ? 1 : -1;
    A.unit(ctx, { type: sh.def.guardType || 'vakt', facing: face, scale: 0.78, noShadow: true, atkAnim: b.atkAnim || 0, skin: '#b97a4c', id: b.id }, GX, GY, t);
    for (const [x, y] of [[b.x + 0.15, b.y + 0.15], [b.x + b.w - 0.15, b.y + 0.15], [b.x + 0.15, b.y + b.h - 0.15], [b.x + b.w - 0.15, b.y + b.h - 0.15]])
      G.line(ctx, P(x, y, top + 6), P(x, y, top + 30), '#5a3a20', 2);
    const rB = P(b.x + b.w - 0.05, b.y + 0.05, top + 30), rC = P(b.x + b.w - 0.05, b.y + b.h - 0.05, top + 30), rD = P(b.x + 0.05, b.y + b.h - 0.05, top + 30);
    const apex = P(cx, cy, top + 46);
    G.poly(ctx, [rD, rC, apex], G.col('#c8402e', -0.25));
    G.poly(ctx, [rC, rB, apex], G.col('#c8402e', 0));
  };

  B.morsare = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    const bags = [];
    for (let k = 0; k < 12; k++) { const a = (k / 12) * Math.PI * 2; bags.push([cx + Math.cos(a) * 0.74, cy + Math.sin(a) * 0.74, Math.cos(a) + Math.sin(a)]); }
    bags.sort((p, q) => p[2] - q[2]);
    const drawBags = (front) => {
      for (const [x, y, d] of bags) {
        if ((d > 0) !== front) continue;
        for (const z of [5, 12]) { const [X, Y] = P(x, y, z); G.blob(ctx, X, Y, 9, 5.5, G.col('#d8c08a', z > 6 ? 0.05 : -0.12), OUT, 1.3); }
      }
    };
    drawBags(false);
    G.disc(ctx, cx, cy, 0.5, 4, G.col('#6d6150'), null);
    const ang = b.ang || 0;
    const a = P(cx, cy, 8), e = P(cx + Math.cos(ang) * 0.32, cy + Math.sin(ang) * 0.32, 30 - (b.recoil || 0) * 5);
    G.thick(ctx, a, e, G.col('#3b4148'), 14);
    G.blob(ctx, e[0], e[1], 7.5, 4.2, G.col('#1d2126'), OUT, 1.5);
    drawBags(true);
  };

  B.vaktkur = function (ctx, b, sh, t) {
    const x0 = b.x + 0.2, y0 = b.y + 0.2, x1 = b.x + b.w - 0.2, y1 = b.y + b.h - 0.2;
    const wall = sh.def.guardType === 'matros' ? '#9aa6b1' : '#7f9fc0';
    G.box(ctx, x0, y0, x1, y1, 0, 32, wall);
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    G.poly(ctx, [P(cx - 0.28, y1, 22), P(cx + 0.28, y1, 22), P(cx + 0.28, y1, 0), P(cx - 0.28, y1, 0)], b.alarm ? '#141a22' : G.col('#3b4a5c'), OUT, 1.3);
    G.poly(ctx, [P(x1, cy - 0.32, 26), P(x1, cy + 0.32, 26), P(x1, cy + 0.32, 14), P(x1, cy - 0.32, 14)], G.col('#cfe8ff'), OUT, 1.3);
    G.box(ctx, x0 - 0.12, y0 - 0.12, x1 + 0.12, y1 + 0.12, 32, 38, '#3c5c80');
    const on = b.alarm && Math.sin(t * 14) > 0;
    G.cyl(ctx, cx, cy, 0.17, 38, 47, on ? '#ff3b3b' : '#8a2a2a', { lw: 1.2 });
    if (on) {
      const [X, Y] = P(cx, cy, 44);
      const g = ctx.createRadialGradient(X, Y, 0, X, Y, 26);
      g.addColorStop(0, 'rgba(255,60,60,.6)'); g.addColorStop(1, 'rgba(255,60,60,0)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(X, Y, 26, 0, 7); ctx.fill();
    }
    // sköld-skylt
    const [SX, SY] = P(x1, cy - 0.62, 26);
    G.poly(ctx, [[SX - 4, SY - 5], [SX + 4, SY - 7], [SX + 4, SY], [SX, SY + 4], [SX - 4, SY + 2]], G.col('#f2c14e'), OUT, 1.1);
  };

  B.container = function (ctx, b, sh, t) {
    const col = b.color || '#c8402e';
    const x0 = b.x + 0.08, y0 = b.y + 0.08, x1 = b.x + b.w - 0.08, y1 = b.y + b.h - 0.08;
    for (let s = 0; s < b.stack; s++) {
      const z0 = s * 26, z1 = z0 + 25;
      const base = s === 1 ? shiftHue(col) : col;
      G.box(ctx, x0, y0, x1, y1, z0, z1, base);
      ctx.strokeStyle = G.rgba('#000000', 0.22); ctx.lineWidth = 1;
      ctx.beginPath();
      for (let y = y0 + 0.2; y < y1 - 0.05; y += 0.22) { const a = P(x1, y, z0 + 3), e = P(x1, y, z1 - 3); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]); }
      for (let x = x0 + 0.2; x < x1 - 0.05; x += 0.22) { const a = P(x, y1, z0 + 3), e = P(x, y1, z1 - 3); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]); }
      ctx.stroke();
    }
  };
  function shiftHue(hex) {
    const map = { '#c8402e': '#2f7fd1', '#2f7fd1': '#e8b021', '#3aa357': '#c8402e', '#e8b021': '#3aa357', '#e2632b': '#8a4fd1', '#8a4fd1': '#3aa357' };
    return map[hex] || '#e2632b';
  }

  B.kista = function (ctx, b, sh, t) {
    const x0 = b.x + 0.25, y0 = b.y + 0.25, x1 = b.x + b.w - 0.25, y1 = b.y + b.h - 0.25;
    G.box(ctx, x0, y0, x1, y1, 0, 20, '#8a5a2b');
    ctx.strokeStyle = G.col('#f2c14e'); ctx.lineWidth = 2.6; ctx.lineCap = 'butt';
    ctx.beginPath();
    for (const fx of [0.28, 0.72]) {
      const x = lerp(x0, x1, fx); let a = P(x, y1, 1), e = P(x, y1, 19); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]);
      const y = lerp(y0, y1, fx); a = P(x1, y, 1); e = P(x1, y, 19); ctx.moveTo(a[0], a[1]); ctx.lineTo(e[0], e[1]);
    }
    ctx.stroke();
    G.box(ctx, x0 - 0.04, y0 - 0.04, x1 + 0.04, y1 + 0.04, 20, 27, '#9b6633', { top: 0.12 });
    const lf = b.lootTotal ? Math.max(0, b.lootLeft / b.lootTotal) : 1;
    const cx = (x0 + x1) / 2, cy = (y0 + y1) / 2;
    if (lf > 0.02) {
      const [X, Y] = P(cx, cy, 30);
      const glow = 0.35 + Math.sin(t * 3 + b.id) * 0.12;
      const g = ctx.createRadialGradient(X, Y, 0, X, Y, 30);
      g.addColorStop(0, `rgba(255,220,90,${glow})`); g.addColorStop(1, 'rgba(255,220,90,0)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(X, Y, 30, 0, 7); ctx.fill();
      const r = G.rng(b.seed + 3);
      const n = Math.ceil(9 * lf);
      for (let i = 0; i < n; i++) {
        const px = lerp(x0 + 0.15, x1 - 0.15, r()), py = lerp(y0 + 0.15, y1 - 0.15, r());
        const [CX, CY] = P(px, py, 28 + r() * 5 * lf);
        G.blob(ctx, CX, CY, 4.2, 2.4, G.col('#ffcf3a'), OUT, 1);
      }
    }
    const [LX, LY] = P(cx, y1, 15);
    ctx.fillStyle = G.col('#f2c14e'); ctx.fillRect(LX - 3, LY - 4, 6, 6); ctx.strokeStyle = OUT; ctx.lineWidth = 1; ctx.strokeRect(LX - 3, LY - 4, 6, 6);
  };

  B.fisklada = function (ctx, b, sh, t) {
    const y0 = b.y + 0.12, y1 = b.y + b.h - 0.12;
    const crate = (xa, xb, ya, yb, z0, z1) => {
      G.box(ctx, xa, ya, xb, yb, z0, z1, '#c79a5b');
      G.poly(ctx, [P(xa + 0.08, ya + 0.08, z1), P(xb - 0.08, ya + 0.08, z1), P(xb - 0.08, yb - 0.08, z1), P(xa + 0.08, yb - 0.08, z1)], G.col('#cdeefb'), null);
    };
    crate(b.x + 0.1, b.x + 0.95, y0, y1, 0, 13);
    crate(b.x + 1.05, b.x + b.w - 0.1, y0, y1, 0, 13);
    crate(b.x + 0.55, b.x + 1.5, y0 + 0.05, y1 - 0.05, 13, 25);
    const r = G.rng(b.seed);
    for (let i = 0; i < 3; i++) {
      const [X, Y] = P(b.x + 0.7 + r() * 0.6, b.y + 0.3 + r() * 0.4, 26);
      G.blob(ctx, X, Y - 2, 5, 2.2, G.col('#8fb3c9'), OUT, 1);
      G.poly(ctx, [[X + 4, Y - 2], [X + 8, Y - 5], [X + 8, Y + 1]], G.col('#8fb3c9'), OUT, 1);
    }
  };

  B.ventil = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.box(ctx, b.x + 0.1, b.y + 0.1, b.x + b.w - 0.1, b.y + b.h - 0.1, 0, 4, '#5d6670');
    G.thick(ctx, P(b.x + 0.1, cy - 0.4, 10), P(b.x + b.w - 0.1, cy - 0.4, 10), G.col('#3c8f5a'), 10);
    G.thick(ctx, P(b.x + 0.1, cy + 0.4, 10), P(b.x + b.w - 0.1, cy + 0.4, 10), G.col('#e9ecef'), 10);
    G.cyl(ctx, cx, cy, 0.17, 4, 26, '#e9ecef', { lw: 1.3 });
    const [X, Y] = P(cx, cy, 28);
    ctx.lineWidth = 6; ctx.strokeStyle = OUT; ctx.beginPath(); ctx.ellipse(X, Y, 13, 6.5, 0, 0, 7); ctx.stroke();
    ctx.lineWidth = 3.4; ctx.strokeStyle = G.col('#d23b2c'); ctx.stroke();
    ctx.lineWidth = 1.8; ctx.beginPath(); ctx.moveTo(X - 13, Y); ctx.lineTo(X + 13, Y); ctx.moveTo(X, Y - 6.5); ctx.lineTo(X, Y + 6.5); ctx.stroke();
  };

  B.skorsten = function (ctx, b, sh, t) {
    const pal = sh.def.pal;
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2, r = 0.62;
    G.cyl(ctx, cx, cy, r + 0.12, 0, 6, '#5d6670');
    G.cyl(ctx, cx, cy, r, 6, 46, '#e3e6ea');
    G.cyl(ctx, cx, cy, r, 46, 58, pal.accent);
    G.cyl(ctx, cx, cy, r, 58, 64, '#e3e6ea');
    G.cyl(ctx, cx, cy, r, 64, 72, '#22252c');
    G.disc(ctx, cx, cy, r * 0.7, 72, '#0e0f12', null);
    if (b.hp > 0) {
      for (let i = 0; i < 4; i++) {
        const f = (((t * 0.45 + i / 4 + b.id * 0.13) % 1) + 1) % 1;
        const [X, Y] = P(cx - f * 0.8, cy - f * 0.4, 74 + f * 60);
        ctx.globalAlpha = (1 - f) * 0.55;
        G.blob(ctx, X, Y, 6 + f * 12, 5 + f * 10, '#cfd5db', null);
      }
      ctx.globalAlpha = 1;
    }
  };

  B.kran = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.box(ctx, b.x + 0.3, b.y + 0.3, b.x + b.w - 0.3, b.y + b.h - 0.3, 0, 12, '#e8b021');
    G.box(ctx, cx - 0.2, cy - 0.2, cx + 0.2, cy + 0.2, 12, 56, '#e8b021');
    G.box(ctx, cx - 0.42, cy - 0.42, cx + 0.32, cy + 0.32, 42, 56, '#e8b021');
    G.poly(ctx, [P(cx + 0.32, cy - 0.3, 54), P(cx + 0.32, cy + 0.2, 54), P(cx + 0.32, cy + 0.2, 46), P(cx + 0.32, cy - 0.3, 46)], G.col('#2d4a6b'), OUT, 1);
    const a = P(cx, cy, 54), e = P(cx + 1.7, cy - 1.5, 84);
    G.thick(ctx, a, e, G.col('#e8b021'), 6);
    ctx.strokeStyle = G.col('#a37a12'); ctx.lineWidth = 1.2; ctx.beginPath();
    for (let i = 0; i < 6; i++) { const p0 = [lerp(a[0], e[0], i / 6), lerp(a[1], e[1], i / 6)], p1 = [lerp(a[0], e[0], (i + 0.5) / 6), lerp(a[1], e[1], (i + 0.5) / 6)]; ctx.moveTo(p0[0], p0[1] - 2); ctx.lineTo(p1[0], p1[1] + 2); }
    ctx.stroke();
    const sway = Math.sin(t * 1.6 + b.id) * 3;
    G.line(ctx, e, [e[0] + sway, e[1] + 30], '#22252c', 1.3);
    ctx.beginPath(); ctx.arc(e[0] + sway, e[1] + 33, 3, 0, Math.PI * 1.4); ctx.lineWidth = 2; ctx.strokeStyle = '#22252c'; ctx.stroke();
  };

  B.livbat = function (ctx, b, sh, t) {
    const x0 = b.x + 0.15, y0 = b.y + 0.15, x1 = b.x + b.w - 0.15, y1 = b.y + b.h - 0.15;
    for (const [x, y] of [[x0 + 0.1, y0 + 0.4], [x1 - 0.1, y0 + 0.4]]) G.line(ctx, P(x, y, 0), P(x, y, 24), '#8d99a6', 2.4);
    G.box(ctx, x0 + 0.1, y0 + 0.05, x1 - 0.1, y1 - 0.05, 7, 17, '#f07c1c');
    G.box(ctx, x0 + 0.3, y0 + 0.15, x1 - 0.3, y1 - 0.15, 17, 23, '#f4f4f4');
  };

  B.radar = function (ctx, b, sh, t) {
    const cx = b.x + 0.5, cy = b.y + 0.5;
    G.box(ctx, b.x + 0.2, b.y + 0.2, b.x + 0.8, b.y + 0.8, 0, 8, '#8d99a6');
    G.box(ctx, cx - 0.08, cy - 0.08, cx + 0.08, cy + 0.08, 8, 54, '#c9d1d8', { lw: 1.2 });
    const a = t * 2.8 + b.id;
    G.thick(ctx, P(cx - Math.cos(a) * 0.62, cy - Math.sin(a) * 0.62, 56), P(cx + Math.cos(a) * 0.62, cy + Math.sin(a) * 0.62, 56), '#f4f6f8', 3.4);
    G.blob(ctx, ...P(cx, cy, 60), 3, 3, '#d23b2c', OUT, 1.2);
  };

  B.helipad = function (ctx, b, sh, t) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.box(ctx, b.x + 0.1, b.y + 0.1, b.x + b.w - 0.1, b.y + b.h - 0.1, 0, 4, '#4f6d5a');
    G.disc(ctx, cx, cy, 1.1, 4, null, G.col('#f2c14e'), 3);
    ctx.strokeStyle = G.col('#ffffff'); ctx.lineWidth = 4; ctx.lineCap = 'butt';
    ctx.beginPath();
    for (const [a, e] of [[[cx - 0.35, cy - 0.45], [cx - 0.35, cy + 0.45]], [[cx + 0.35, cy - 0.45], [cx + 0.35, cy + 0.45]], [[cx - 0.35, cy], [cx + 0.35, cy]]]) {
      const p0 = P(a[0], a[1], 4), p1 = P(e[0], e[1], 4); ctx.moveTo(p0[0], p0[1]); ctx.lineTo(p1[0], p1[1]);
    }
    ctx.stroke();
  };

  B.pool = function (ctx, b, sh, t) {
    const x0 = b.x + 0.1, y0 = b.y + 0.1, x1 = b.x + b.w - 0.1, y1 = b.y + b.h - 0.1;
    G.box(ctx, x0, y0, x1, y1, 0, 8, '#f4f7fa');
    const wp = [P(x0 + 0.25, y0 + 0.25, 8), P(x1 - 0.25, y0 + 0.25, 8), P(x1 - 0.25, y1 - 0.25, 8), P(x0 + 0.25, y1 - 0.25, 8)];
    G.poly(ctx, wp, G.col('#3fc6f0'), OUT, 1.2);
    ctx.save(); G.path(ctx, wp); ctx.clip();
    ctx.strokeStyle = 'rgba(255,255,255,.55)'; ctx.lineWidth = 1.5;
    for (let i = 0; i < 4; i++) {
      const y = lerp(y0 + 0.4, y1 - 0.4, i / 3);
      ctx.beginPath();
      for (let k = 0; k <= 10; k++) { const x = lerp(x0, x1, k / 10); const [X, Y] = P(x, y + Math.sin(t * 2 + k + i) * 0.06, 8); if (k) ctx.lineTo(X, Y); else ctx.moveTo(X, Y); }
      ctx.stroke();
    }
    ctx.restore();
    const da = t * 0.6;
    const [DX, DY] = P(lerp(x0 + 0.8, x1 - 0.8, 0.5 + Math.cos(da) * 0.35), lerp(y0 + 0.6, y1 - 0.6, 0.5 + Math.sin(da) * 0.35), 9);
    G.blob(ctx, DX, DY, 5, 3, '#ffd23f', OUT, 1.2);
    G.blob(ctx, DX + 3, DY - 4, 2.6, 2.4, '#ffd23f', OUT, 1.1);
    ctx.fillStyle = '#ff8a1c'; ctx.fillRect(DX + 5, DY - 4.5, 2.4, 1.4);
  };

  // Sprite-cache för byggnader utan animation: ritas en gång per zoomnivå och klistras sedan in.
  // A.spriteScale sätts av den som ritar (kamerans zoom × dpr); 0 = rita direkt.
  A.spriteScale = 0;
  const STATIC = new Set(['container', 'fisklada', 'ventil', 'livbat', 'helipad']);
  const spriteCache = new Map();
  function sprite(key, w, h, hgt, draw) {
    const sc = A.spriteScale;
    const k = key + '|' + sc.toFixed(3);
    let sp = spriteCache.get(k);
    if (!sp) {
      if (spriteCache.size > 400) spriteCache.clear();
      const x0 = -h * G.HW - 12, x1 = w * G.HW + 12, y0 = -hgt - 18, y1 = (w + h) * G.HH + 12;
      const cv = document.createElement('canvas');
      cv.width = Math.max(1, Math.ceil((x1 - x0) * sc)); cv.height = Math.max(1, Math.ceil((y1 - y0) * sc));
      const c = cv.getContext('2d');
      c.setTransform(sc, 0, 0, sc, -x0 * sc, -y0 * sc);
      draw(c);
      sp = { cv, x0, y0, sc };
      spriteCache.set(k, sp);
    }
    return sp;
  }
  function blit(ctx, sp, x, y) {
    const [X, Y] = P(x, y, 0);
    ctx.drawImage(sp.cv, X + sp.x0, Y + sp.y0, sp.cv.width / sp.sc, sp.cv.height / sp.sc);
  }

  A.building = function (ctx, b, sh, t, o = {}) {
    const f = B[b.type];
    if (!f) return;
    if (A.spriteScale > 0 && STATIC.has(b.type) && !(b.flash > 0)) {
      const sp = sprite([b.type, b.w, b.h, b.color, b.stack, b.seed].join(','), b.w, b.h, 26 * b.stack + 10, (c) => {
        f(c, Object.assign({}, b, { x: 0, y: 0, cx: b.w / 2, cy: b.h / 2 }), sh, t, o);
      });
      blit(ctx, sp, b.x, b.y);
      return;
    }
    G.flash = b.flash > 0 ? Math.min(1, b.flash * 7) : 0;
    f(ctx, b, sh, t, o);
    G.flash = 0;
  };

  A.buildingShadow = function (ctx, b) {
    const s = 0.35;
    G.poly(ctx, [P(b.x + 0.1, b.y + 0.1 + s), P(b.x + b.w, b.y + 0.1 + s), P(b.x + b.w, b.y + b.h + s), P(b.x + 0.1, b.y + b.h + s)], 'rgba(10,15,25,.16)', null);
  };

  // ---------- barrikader ----------
  A.wall = function (ctx, w, sh, t) {
    const alive = (xx, yy) => { if (xx < 0 || yy < 0 || xx >= sh.W || yy >= sh.H) return false; const i = sh.wallAt[yy * sh.W + xx]; return i >= 0 && sh.walls[i].alive; };
    const ax = alive(w.x + 1, w.y), ay = alive(w.x, w.y + 1), dmg = w.hp / w.maxHp < 0.5;
    if (A.spriteScale > 0 && !(w.flash > 0)) {
      blit(ctx, sprite(['wall', ax, ay, dmg].join(','), 1, 1, 24, (c) => wallDraw(c, 0, 0, ax, ay, dmg)), w.x, w.y);
      return;
    }
    G.flash = w.flash > 0 ? Math.min(1, w.flash * 7) : 0;
    wallDraw(ctx, w.x, w.y, ax, ay, dmg);
    G.flash = 0;
  };
  function wallDraw(ctx, x, y, ax, ay, dmg) {
    const col = dmg ? '#4a5058' : '#59616b';
    if (ax) G.box(ctx, x + 0.7, y + 0.36, x + 1.3, y + 0.64, 3, 12, '#7b8590', { lw: 1.2 });
    if (ay) G.box(ctx, x + 0.36, y + 0.7, x + 0.64, y + 1.3, 3, 12, '#7b8590', { lw: 1.2 });
    G.box(ctx, x + 0.22, y + 0.22, x + 0.78, y + 0.78, 0, 17, col, { topCol: '#f2c14e', top: 0 });
    const [X, Y] = P(x + 0.5, y + 0.5, 17);
    ctx.fillStyle = G.col('#1d1526');
    ctx.beginPath(); ctx.moveTo(X - 8, Y); ctx.lineTo(X - 4, Y - 2); ctx.lineTo(X + 2, Y + 3); ctx.lineTo(X - 2, Y + 5); ctx.closePath(); ctx.fill();
    ctx.beginPath(); ctx.moveTo(X + 2, Y - 5); ctx.lineTo(X + 6, Y - 3); ctx.lineTo(X + 10, Y + 1); ctx.lineTo(X + 6, Y + 1); ctx.closePath(); ctx.fill();
    // taggtråd
    ctx.strokeStyle = 'rgba(220,226,232,.9)'; ctx.lineWidth = 1;
    for (let i = 0; i < 3; i++) { ctx.beginPath(); ctx.ellipse(X - 6 + i * 6, Y - 4, 4, 3, 0, 0, 7); ctx.stroke(); }
  }

  // ---------- ruiner ----------
  A.rubble = function (ctx, b, sh, t, noFlag) {
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2;
    G.disc(ctx, cx, cy, Math.min(b.w, b.h) * 0.5, 0, 'rgba(20,16,12,.32)', null);
    const r = G.rng(b.seed + 11);
    const cols = { brygga: '#d9dde2', container: b.color || '#c8402e', kista: '#8a5a2b', kanon: '#5b6773', vatten: '#d23b2c', utkik: '#7a5232', morsare: '#d8c08a', vaktkur: '#7f9fc0', skorsten: '#e3e6ea', kran: '#e8b021', livbat: '#f07c1c', pool: '#f4f7fa', helipad: '#4f6d5a', fisklada: '#c79a5b', ventil: '#3c8f5a', radar: '#c9d1d8' };
    const c = cols[b.type] || '#8d99a6';
    const n = 4 + Math.round(b.w * b.h * 0.8);
    const chunks = [];
    for (let i = 0; i < n; i++) chunks.push([b.x + 0.2 + r() * (b.w - 0.4), b.y + 0.2 + r() * (b.h - 0.4), r(), r()]);
    chunks.sort((p, q) => p[0] + p[1] - q[0] - q[1]);
    for (const [x, y, a, s] of chunks) {
      const sz = 0.12 + s * 0.16;
      G.box(ctx, x - sz, y - sz * 0.8, x + sz, y + sz * 0.8, 0, 4 + a * 7, a > 0.55 ? c : '#6e6a64', { lw: 1.1 });
    }
    if (b.type === 'brygga' && !noFlag) {
      const [X, Y] = P(cx, cy, 0);
      A.flag(ctx, X, Y - 58, 'pirate', t, 1.15);
    }
  };

  // ---------- dryckszoner ----------
  A.spellZone = function (ctx, s, t) {
    const [X, Y] = P(s.x, s.y, 0);
    const rx = s.r * G.HW * G.R2, ry = s.r * G.HH * G.R2;
    const life = s.t / s.dur;
    const fade = Math.min(1, (1 - life) * 6, s.t * 6);
    ctx.globalAlpha = 0.28 * fade;
    ctx.fillStyle = s.color;
    ctx.beginPath(); ctx.ellipse(X, Y, rx, ry, 0, 0, 7); ctx.fill();
    ctx.globalAlpha = 0.9 * fade;
    ctx.setLineDash([10, 8]); ctx.lineDashOffset = -t * 30;
    ctx.strokeStyle = s.color; ctx.lineWidth = 3;
    ctx.beginPath(); ctx.ellipse(X, Y, rx, ry, 0, 0, 7); ctx.stroke();
    ctx.setLineDash([]);
    const pulse = (t * 1.6) % 1;
    ctx.globalAlpha = (1 - pulse) * 0.6 * fade;
    ctx.beginPath(); ctx.ellipse(X, Y, rx * pulse, ry * pulse, 0, 0, 7); ctx.stroke();
    ctx.globalAlpha = 1;
    if (s.t < 0.45) {
      const f = s.t / 0.45, z = (1 - f) * 220;
      if (s.type === 'lakning') A.kettle(ctx, X, Y - z, 1.2); else A.drum(ctx, X, Y - z, 1.2);
    }
  };

  // Hela skeppet med byggnader (för hamnen och miniatyrer)
  A.shipFull = function (ctx, sh, t, o = {}) {
    A.water(ctx, sh, t);
    A.hull(ctx, sh, t);
    A.deck(ctx, sh, t);
    const items = [];
    for (const b of sh.buildings) items.push([b.x + b.y + (b.w + b.h) / 2, 0, b]);
    for (const w of sh.walls) items.push([w.x + w.y + 1, 1, w]);
    items.sort((p, q) => p[0] - q[0]);
    for (const it of items) if (it[1] === 1) A.wall(ctx, it[2], sh, t); else A.building(ctx, it[2], sh, t, o);
  };

  A.shipBounds = function (sh) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const [x, y] of sh.poly) for (const z of [0, -HULL]) {
      const [X, Y] = P(x, y, z); x0 = Math.min(x0, X); x1 = Math.max(x1, X); y0 = Math.min(y0, Y); y1 = Math.max(y1, Y);
    }
    return { x0, y0, x1, y1 };
  };

  A.shipThumb = function (cv, def, pirate) {
    const ctx = cv.getContext('2d');
    const sh = K.ship.build(def);
    const bd = A.shipBounds(sh);
    const top = bd.y0 - 110;
    const w = cv.width, h = cv.height;
    const s = Math.min(w / (bd.x1 - bd.x0 + 20), h / (bd.y1 - top + 10));
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    ctx.setTransform(s, 0, 0, s, w / 2 - ((bd.x0 + bd.x1) / 2) * s, h / 2 - ((top + bd.y1) / 2) * s);
    A.shipFull(ctx, sh, 1.2, { pirate });
    ctx.setTransform(1, 0, 0, 1, 0, 0);
  };
})();
