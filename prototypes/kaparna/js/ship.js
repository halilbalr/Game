// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Skeppsgeometri: skrovform, däcksrutor och placering av byggnader/barrikader.
(function () {
  const K = window.K;
  const S = (K.ship = {});

  // Skrovet som polygon i rutkoordinater (x längs skeppet, akter vid x=0, för vid x=len).
  S.hull = function (def) {
    const L = def.len, B = def.beam, bw = def.bow, r = 0.7;
    const pts = [];
    for (let i = 0; i <= 4; i++) {
      const a = Math.PI + (Math.PI / 2) * (i / 4);
      pts.push([r + Math.cos(a) * r, r + Math.sin(a) * r]);
    }
    const sx = L - bw, cx = L - bw * 0.3;
    const bez = (t) => (1 - t) * (1 - t) * sx + 2 * (1 - t) * t * cx + t * t * L;
    for (let i = 0; i <= 12; i++) { const t = i / 12; pts.push([bez(t), t * t * (B / 2)]); }
    for (let i = 11; i >= 0; i--) { const t = i / 12; pts.push([bez(t), B - t * t * (B / 2)]); }
    for (let i = 0; i <= 4; i++) {
      const a = Math.PI / 2 + (Math.PI / 2) * (i / 4);
      pts.push([r + Math.cos(a) * r, B - r + Math.sin(a) * r]);
    }
    return pts;
  };

  S.inPoly = function (pts, x, y) {
    let inside = false;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const xi = pts[i][0], yi = pts[i][1], xj = pts[j][0], yj = pts[j][1];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  };

  // Närmaste punkt på polygonens kant
  S.closestOnPoly = function (pts, x, y) {
    let best = null, bd = Infinity;
    for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
      const ax = pts[j][0], ay = pts[j][1], bx = pts[i][0], by = pts[i][1];
      const dx = bx - ax, dy = by - ay;
      const l2 = dx * dx + dy * dy || 1;
      let t = ((x - ax) * dx + (y - ay) * dy) / l2;
      t = Math.max(0, Math.min(1, t));
      const px = ax + dx * t, py = ay + dy * t;
      const d = (px - x) * (px - x) + (py - y) * (py - y);
      if (d < bd) { bd = d; best = { x: px, y: py, nx: dy, ny: -dx, d: Math.sqrt(d) }; }
    }
    // normalera normalen så att den pekar utåt
    const n = Math.hypot(best.nx, best.ny) || 1;
    best.nx /= n; best.ny /= n;
    if (S.inPoly(pts, best.x + best.nx * 0.05, best.y + best.ny * 0.05)) { best.nx *= -1; best.ny *= -1; }
    return best;
  };

  // Bygg upp hela skeppet: rutnät, byggnader och barrikader
  S.build = function (def) {
    const D = K.DATA;
    const W = def.len, H = def.beam;
    const poly = S.hull(def);
    const deck = new Uint8Array(W * H);
    const m = 0.38;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const cx = x + 0.5, cy = y + 0.5;
      deck[y * W + x] = S.inPoly(poly, cx, cy) && S.inPoly(poly, cx - m, cy - m) && S.inPoly(poly, cx + m, cy - m) &&
        S.inPoly(poly, cx - m, cy + m) && S.inPoly(poly, cx + m, cy + m) ? 1 : 0;
    }
    const occ = new Int16Array(W * H).fill(-1);
    const wallAt = new Int16Array(W * H).fill(-1);
    const problems = [];
    const tier = def.tier;
    const hpMul = 1 + D.tierScale.hp * (tier - 1);
    const dmgMul = 1 + D.tierScale.dmg * (tier - 1);

    const buildings = [];
    def.layout.forEach((e, i) => {
      const type = e[0], bd = D.buildings[type], opt = e[3] || {};
      if (!bd) { problems.push('okänd byggnad ' + type); return; }
      const w = opt.rot ? bd.h : bd.w, h = opt.rot ? bd.w : bd.h;
      const b = {
        id: i, type, def: bd, kind: bd.kind, x: e[1], y: e[2], w, h,
        maxHp: Math.round(bd.hp * hpMul), dmg: (bd.dmg || 0) * dmgMul,
        color: opt.color || null, stack: opt.stack || 1, seed: (i * 9301 + 49297) % 233280,
      };
      b.hp = b.maxHp;
      for (let yy = b.y; yy < b.y + h; yy++) for (let xx = b.x; xx < b.x + w; xx++) {
        if (xx < 0 || yy < 0 || xx >= W || yy >= H || !deck[yy * W + xx]) { problems.push(`${def.id}: ${type} @${b.x},${b.y} utanför däck (${xx},${yy})`); continue; }
        if (occ[yy * W + xx] >= 0) problems.push(`${def.id}: ${type} @${b.x},${b.y} krockar med ${buildings[occ[yy * W + xx]].type}`);
        occ[yy * W + xx] = buildings.length;
      }
      buildings.push(b);
    });

    const walls = [];
    (def.walls || []).forEach((s) => {
      for (let k = 0; k < s[2]; k++) {
        const x = s[0] + (s[3] === 'h' ? k : 0), y = s[1] + (s[3] === 'v' ? k : 0);
        const t = y * W + x;
        if (x < 0 || y < 0 || x >= W || y >= H || !deck[t]) { problems.push(`${def.id}: barrikad @${x},${y} utanför däck`); continue; }
        if (occ[t] >= 0) { problems.push(`${def.id}: barrikad @${x},${y} på ${buildings[occ[t]].type}`); continue; }
        if (wallAt[t] >= 0) continue;
        wallAt[t] = walls.length;
        walls.push({ x, y, maxHp: Math.round(D.wallHp * hpMul), hp: Math.round(D.wallHp * hpMul), alive: true, isWall: true, kind: 'wall' });
      }
    });

    return { def, W, H, poly, deck, occ, wallAt, buildings, walls, problems, hpMul, dmgMul };
  };

  // ASCII-karta för felsökning
  S.CHAR = { brygga: 'B', kanon: 'C', vatten: 'W', utkik: 'U', morsare: 'M', vaktkur: 'G', container: 'N', kista: '$', fisklada: 'F', ventil: 'V', skorsten: 'S', kran: 'K', livbat: 'L', radar: 'A', helipad: 'H', pool: 'P' };
  S.ascii = function (sh) {
    const rows = [];
    for (let y = 0; y < sh.H; y++) {
      let r = '';
      for (let x = 0; x < sh.W; x++) {
        const t = y * sh.W + x;
        if (!sh.deck[t]) r += ' ';
        else if (sh.wallAt[t] >= 0) r += '#';
        else if (sh.occ[t] >= 0) r += S.CHAR[sh.buildings[sh.occ[t]].type] || '?';
        else r += '.';
      }
      rows.push(r);
    }
    return rows.join('\n');
  };
})();
