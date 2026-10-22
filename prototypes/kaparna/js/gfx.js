// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Isometrisk projektion, kamera och ritprimitiver (lådor, cylindrar, linjer) i tecknad stil.
(function () {
  const K = window.K;
  const G = (K.gfx = {});
  const HW = (G.HW = 32), HH = (G.HH = 16);
  G.OUT = '#1d1526';
  G.flash = 0; // 0..1: blanda mot vitt (träffblink)

  // värld (x, y, z) -> iso-pixlar
  G.P = (x, y, z = 0) => [(x - y) * HW, (x + y) * HH - z];
  G.isoToWorld = (X, Y, z = 0) => {
    const u = X / HW, v = (Y + z) / HH;
    return [(u + v) / 2, (v - u) / 2];
  };

  // ---------- färger ----------
  const rgbCache = new Map();
  function rgb(hex) {
    let c = rgbCache.get(hex);
    if (c) return c;
    let h = hex.replace('#', '');
    if (h.length === 3) h = h.split('').map((s) => s + s).join('');
    c = [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
    rgbCache.set(hex, c);
    return c;
  }
  G.rgb = rgb;
  const colCache = new Map();
  // f > 0 ljusare, f < 0 mörkare. Tar hänsyn till G.flash.
  G.col = function (hex, f = 0) {
    if (hex[0] !== '#') return hex;
    const fl = G.flash > 0 ? Math.round(G.flash * 10) / 10 : 0;
    if (f === 0 && fl === 0) return hex;
    let m = colCache.get(hex);
    if (!m) colCache.set(hex, (m = new Map()));
    const key = Math.round(f * 1000) * 100 + fl * 10;
    let s = m.get(key);
    if (s) return s;
    let [r, g, b] = rgb(hex);
    if (f > 0) { r += (255 - r) * f; g += (255 - g) * f; b += (255 - b) * f; }
    else if (f < 0) { r *= 1 + f; g *= 1 + f; b *= 1 + f; }
    if (fl > 0) { const t = fl * 0.85; r += (255 - r) * t; g += (255 - g) * t; b += (255 - b) * t; }
    s = `rgb(${r | 0},${g | 0},${b | 0})`;
    m.set(key, s);
    return s;
  };
  G.rgba = function (hex, a) { const [r, g, b] = rgb(hex); return `rgba(${r},${g},${b},${a})`; };

  // ---------- grundformer ----------
  G.path = function (ctx, pts) {
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1]);
    ctx.closePath();
  };
  G.poly = function (ctx, pts, fill, stroke = G.OUT, lw = 1.6) {
    G.path(ctx, pts);
    if (fill) { ctx.fillStyle = fill; ctx.fill(); }
    if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.lineJoin = 'round'; ctx.stroke(); }
  };

  // Låda med tre synliga sidor. o: {top, left, right, lw, noStroke, topCol}
  G.box = function (ctx, x0, y0, x1, y1, z0, z1, color, o = {}) {
    const P = G.P;
    const A = P(x0, y0, z1), B = P(x1, y0, z1), C = P(x1, y1, z1), D = P(x0, y1, z1);
    const B0 = P(x1, y0, z0), C0 = P(x1, y1, z0), D0 = P(x0, y1, z0);
    const lw = o.lw ?? 1.6, st = o.noStroke ? null : G.OUT;
    G.poly(ctx, [D, C, C0, D0], G.col(o.leftCol || color, o.left ?? -0.3), st, lw);
    G.poly(ctx, [C, B, B0, C0], G.col(o.rightCol || color, o.right ?? -0.12), st, lw);
    G.poly(ctx, [A, B, C, D], G.col(o.topCol || color, o.top ?? 0.08), st, lw);
  };

  // Stående cylinder (iso-ellips)
  G.R2 = Math.SQRT2;
  G.cyl = function (ctx, cx, cy, r, z0, z1, color, o = {}) {
    const [X, Y0] = G.P(cx, cy, z0);
    const Y1 = Y0 - (z1 - z0);
    const rx = r * HW * G.R2, ry = r * HH * G.R2;
    ctx.beginPath();
    ctx.moveTo(X - rx, Y1);
    ctx.lineTo(X - rx, Y0);
    ctx.ellipse(X, Y0, rx, ry, 0, Math.PI, 0, true);
    ctx.lineTo(X + rx, Y1);
    ctx.closePath();
    const gr = ctx.createLinearGradient(X - rx, 0, X + rx, 0);
    gr.addColorStop(0, G.col(color, -0.38));
    gr.addColorStop(0.62, G.col(color, -0.04));
    gr.addColorStop(1, G.col(color, -0.22));
    ctx.fillStyle = gr;
    ctx.fill();
    if (!o.noStroke) { ctx.lineWidth = o.lw ?? 1.6; ctx.strokeStyle = G.OUT; ctx.stroke(); }
    if (!o.noTop) {
      ctx.beginPath();
      ctx.ellipse(X, Y1, rx, ry, 0, 0, Math.PI * 2);
      ctx.fillStyle = G.col(o.topCol || color, o.top ?? 0.12);
      ctx.fill();
      if (!o.noStroke) ctx.stroke();
    }
    return [X, Y1, rx, ry];
  };

  // Platt iso-cirkel på höjd z
  G.disc = function (ctx, cx, cy, r, z, fill, stroke, lw = 1.6) {
    const [X, Y] = G.P(cx, cy, z);
    ctx.beginPath();
    ctx.ellipse(X, Y, r * HW * G.R2, r * HH * G.R2, 0, 0, Math.PI * 2);
    if (fill) { ctx.fillStyle = fill; ctx.fill(); }
    if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.stroke(); }
  };

  // Tjock linje med kontur (rör, kanonpipor, armar)
  G.thick = function (ctx, a, b, color, w, outline = true) {
    ctx.lineCap = 'round';
    if (outline) {
      ctx.strokeStyle = G.OUT; ctx.lineWidth = w + 3;
      ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
    }
    ctx.strokeStyle = color; ctx.lineWidth = w;
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
  };

  G.line = function (ctx, a, b, color, w = 1.5) {
    ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.stroke();
  };

  G.blob = function (ctx, X, Y, rx, ry, fill, stroke = G.OUT, lw = 1.6) {
    ctx.beginPath(); ctx.ellipse(X, Y, rx, ry, 0, 0, Math.PI * 2);
    if (fill) { ctx.fillStyle = fill; ctx.fill(); }
    if (stroke) { ctx.lineWidth = lw; ctx.strokeStyle = stroke; ctx.stroke(); }
  };

  G.shadow = function (ctx, X, Y, rx, ry, a = 0.25) {
    ctx.beginPath(); ctx.ellipse(X, Y, rx, ry, 0, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(10,20,30,${a})`; ctx.fill();
  };

  // Seedad slump (samma resultat varje bildruta)
  G.rng = function (seed) {
    let a = seed >>> 0 || 1;
    return function () {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };

  // Vågkammar, grupperade i fyra genomskinlighetsnivåer så att det blir fyra streck i stället för hundratals
  G.waves = function (ctx, waves, t, z, amp = 1) {
    const buckets = [[], [], [], []];
    for (const w of waves) { const a = 0.5 + 0.5 * Math.sin(t * 1.3 + w[2]); buckets[Math.min(3, (a * 4) | 0)].push(w); }
    ctx.lineWidth = 2; ctx.lineCap = 'round';
    buckets.forEach((list, i) => {
      ctx.strokeStyle = `rgba(255,255,255,${(0.04 + i * 0.065) * amp})`;
      ctx.beginPath();
      for (const [x, y, ph] of list) {
        const [X, Y] = G.P(x + Math.sin(t * 0.4 + ph) * 0.3, y, z);
        ctx.moveTo(X - 9, Y); ctx.quadraticCurveTo(X, Y + 4, X + 9, Y);
      }
      ctx.stroke();
    });
  };

  // Förrenderat lager i världskoordinater (iso-pixlar). Ritas om bara när nyckeln ändras.
  G.Layer = class {
    constructor() { this.cv = document.createElement('canvas'); this.key = null; this.ok = false; }
    ensure(key, b, scale, draw) {
      if (this.key === key) return this.ok;
      this.key = key;
      const w = Math.ceil((b.x1 - b.x0) * scale), h = Math.ceil((b.y1 - b.y0) * scale);
      this.ok = w > 0 && h > 0 && w * h <= 9e6 && w <= 8192 && h <= 8192;
      if (!this.ok) { this.cv.width = this.cv.height = 1; return false; }
      this.cv.width = w; this.cv.height = h; this.b = b; this.s = scale;
      const c = this.cv.getContext('2d');
      c.setTransform(scale, 0, 0, scale, -b.x0 * scale, -b.y0 * scale);
      draw(c);
      return true;
    }
    blit(ctx) { ctx.drawImage(this.cv, this.b.x0, this.b.y0, this.cv.width / this.s, this.cv.height / this.s); }
  };

  // ---------- kamera ----------
  G.Camera = class {
    constructor() { this.x = 0; this.y = 0; this.z = 1; this.shake = 0; this.sx = 0; this.sy = 0; this.min = 0.3; this.max = 2.5; }
    update(dt) {
      if (this.shake > 0) {
        this.shake = Math.max(0, this.shake - dt * 20);
        this.sx = (Math.random() - 0.5) * this.shake; this.sy = (Math.random() - 0.5) * this.shake;
      } else { this.sx = this.sy = 0; }
    }
    apply(ctx, cw, ch, dpr) {
      const z = this.z;
      ctx.setTransform(z * dpr, 0, 0, z * dpr, (cw / 2 - (this.x + this.sx) * z) * dpr, (ch / 2 - (this.y + this.sy) * z) * dpr);
    }
    toIso(sx, sy, cw, ch) { return [(sx - cw / 2) / this.z + this.x, (sy - ch / 2) / this.z + this.y]; }
    toScreen(X, Y, cw, ch) { return [(X - this.x) * this.z + cw / 2, (Y - this.y) * this.z + ch / 2]; }
    zoomAt(f, sx, sy, cw, ch) {
      const before = this.toIso(sx, sy, cw, ch);
      this.z = Math.max(this.min, Math.min(this.max, this.z * f));
      const after = this.toIso(sx, sy, cw, ch);
      this.x += before[0] - after[0]; this.y += before[1] - after[1];
    }
    // Håll kameran inom ett område (iso-pixlar)
    clamp(b) {
      if (!b) return;
      this.x = Math.max(b.x0, Math.min(b.x1, this.x));
      this.y = Math.max(b.y0, Math.min(b.y1, this.y));
    }
  };
})();
