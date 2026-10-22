// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// Tecknade figurer (pirater, vakter), skiffar, flaggor, effekter och porträtt.
(function () {
  const K = window.K, G = K.gfx, P = G.P, OUT = G.OUT;
  const A = (K.art = {});

  A.SKINS = ['#6b3f22', '#7a4a2a', '#8b5a35', '#9a6640', '#5c361d', '#83502c'];
  A.GUARD_SKINS = ['#f1c7a1', '#d9a47a', '#b97a4c', '#7a4a2a', '#e8b48a', '#a8683c'];

  const SPEC = (A.SPEC = {
    kampe: { s: 1, shirt: '#7cc6ff', stripe: '#ffffff', pants: '#33304a', head: 'bandana', hat: '#e0392b', dots: true, weapon: 'sabel' },
    skytt: { s: 1, shirt: '#f4efe2', vest: '#2f9e6b', pants: '#4a3b2a', head: 'turban', hat: '#f6f1e4', weapon: 'musket' },
    bombare: { s: 0.92, shirt: '#4a4a58', pants: '#26242e', head: 'bandana', hat: '#ff8a1c', chubby: true, weapon: 'bomb' },
    bjasse: { s: 1.45, shirt: '#8a6440', vest: '#4a3424', pants: '#2e2a3a', head: 'bald', beard: '#1d1512', big: true, weapon: 'ankare' },
    plundrare: { s: 0.95, shirt: '#ffd23f', pants: '#3d2f52', head: 'bandana', hat: '#8a4fd1', thin: true, sack: true, weapon: 'dolk' },
    kapten: { s: 1.28, shirt: '#c0262d', coat: true, pants: '#20202a', head: 'tricorn', beard: '#1d1512', weapon: 'sabel', gold: true },
    vakt: { s: 1, shirt: '#2c5aa0', pants: '#1e2a40', head: 'cap', hat: '#1e2a40', weapon: 'batong' },
    matros: { s: 1, shirt: '#f3f5f8', collar: '#2c5aa0', pants: '#2c5aa0', head: 'sailor', hat: '#ffffff', weapon: 'batong' },
  });

  const lerp = (a, b, t) => a + (b - a) * t;

  function rr(ctx, x, y, w, h, r) {
    ctx.beginPath();
    if (ctx.roundRect) ctx.roundRect(x, y, w, h, r);
    else ctx.rect(x, y, w, h);
  }
  A.rr = rr;

  function leg(ctx, x, lift, col) {
    rr(ctx, x - 2.3, -9.5 - lift, 4.6, 8.8, 2);
    ctx.fillStyle = G.col(col); ctx.fill(); ctx.lineWidth = 1.4; ctx.strokeStyle = OUT; ctx.stroke();
    G.blob(ctx, x + 1, -1.2 - lift, 3.2, 1.9, G.col('#2a1d14'), OUT, 1.2);
  }

  function weapon(ctx, kind, sp, ap) {
    ctx.lineJoin = 'round';
    if (kind === 'sabel') {
      const L = 15;
      ctx.beginPath();
      ctx.moveTo(1.5, -1.6); ctx.quadraticCurveTo(L * 0.6, -2.8, L, -5); ctx.lineTo(L - 1, -1.6);
      ctx.quadraticCurveTo(L * 0.6, 1.4, 1.5, 1.5); ctx.closePath();
      ctx.fillStyle = G.col('#e9f1f7'); ctx.fill(); ctx.lineWidth = 1.3; ctx.strokeStyle = OUT; ctx.stroke();
      ctx.beginPath(); ctx.moveTo(3, -0.4); ctx.quadraticCurveTo(L * 0.6, -1.4, L - 1.5, -3.6);
      ctx.strokeStyle = 'rgba(255,255,255,.9)'; ctx.lineWidth = 0.9; ctx.stroke();
      rr(ctx, 0, -3.2, 1.9, 6.4, 0.8); ctx.fillStyle = G.col(sp.gold ? '#ffcf3a' : '#d9a441'); ctx.fill(); ctx.lineWidth = 1.1; ctx.strokeStyle = OUT; ctx.stroke();
      rr(ctx, -4, -1.2, 4.2, 2.4, 1); ctx.fillStyle = G.col('#5a3416'); ctx.fill(); ctx.stroke();
    } else if (kind === 'dolk') {
      ctx.beginPath(); ctx.moveTo(1.5, -1.3); ctx.lineTo(9, 0); ctx.lineTo(1.5, 1.3); ctx.closePath();
      ctx.fillStyle = G.col('#dfe8ef'); ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = OUT; ctx.stroke();
      rr(ctx, -2.5, -1.1, 4, 2.2, 1); ctx.fillStyle = G.col('#5a3416'); ctx.fill(); ctx.stroke();
    } else if (kind === 'batong') {
      rr(ctx, -2, -1.3, 13, 2.6, 1.2); ctx.fillStyle = G.col('#22252c'); ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = OUT; ctx.stroke();
    } else if (kind === 'ankare') {
      G.thick(ctx, [0, 0], [17, 0], G.col('#8d99a6'), 3.4);
      G.thick(ctx, [2.5, -4.5], [2.5, 4.5], G.col('#8d99a6'), 2.6);
      ctx.beginPath(); ctx.arc(-1.8, 0, 2.3, 0, Math.PI * 2); ctx.lineWidth = 2.2; ctx.strokeStyle = G.col('#8d99a6'); ctx.stroke();
      ctx.beginPath(); ctx.arc(12.5, 0, 6, -1.35, 1.35); ctx.lineWidth = 6.2; ctx.strokeStyle = OUT; ctx.stroke();
      ctx.lineWidth = 3.4; ctx.strokeStyle = G.col('#8d99a6'); ctx.stroke();
      for (const s of [-1, 1]) {
        const ax = 12.5 + Math.cos(1.35 * s) * 6, ay = Math.sin(1.35 * s) * 6;
        G.poly(ctx, [[ax - 1.5, ay], [ax - 4, ay + 2.6 * s], [ax + 1.8, ay + 0.6 * s]], G.col('#a9b4bf'), OUT, 1.2);
      }
    }
  }

  // Ritar en figur med fötterna i (X, Y) (iso-pixlar). u: {type, facing, walk, moving, atkAnim, skin, flash, air, squash, rage, slow, scale}
  A.unit = function (ctx, u, X, Y, t) {
    const sp = SPEC[u.type] || SPEC.kampe;
    const s = sp.s * (u.scale || 1);
    if (!u.noShadow) G.shadow(ctx, X, Y, 9 * s, 4.2 * s, 0.28);
    if (u.rage > 0) {
      const g = ctx.createRadialGradient(X, Y, 0, X, Y, 16 * s);
      g.addColorStop(0, 'rgba(255,80,220,.55)'); g.addColorStop(1, 'rgba(255,80,220,0)');
      ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(X, Y, 16 * s, 8 * s, 0, 0, Math.PI * 2); ctx.fill();
    }
    ctx.save();
    ctx.translate(X, Y - (u.air || 0));
    const sq = u.squash || 1;
    ctx.scale((u.facing || 1) * s * sq, s / sq);
    G.flash = u.flash > 0 ? Math.min(1, u.flash * 7) : 0;
    body(ctx, sp, u, t);
    G.flash = 0;
    ctx.restore();
  };

  function body(ctx, sp, u, t) {
    const moving = u.moving, w = u.walk || 0;
    const bob = moving ? -Math.abs(Math.sin(w)) * 2.2 : Math.sin(t * 3 + (u.id || 0)) * 0.5;
    const l1 = moving ? Math.sin(w) * 3.2 : 0;
    const lift1 = moving ? Math.max(0, Math.cos(w)) * 1.8 : 0;
    const lift2 = moving ? Math.max(0, -Math.cos(w)) * 1.8 : 0;
    const bw = sp.big ? 9.5 : sp.chubby ? 8.6 : sp.thin ? 6.4 : 7.5;
    const skin = u.skin || '#7a4a2a';
    const ap = u.atkAnim > 0 ? 1 - u.atkAnim / 0.35 : -1;
    const by = -15 + bob;

    leg(ctx, -2.6 - l1 * 0.6, lift2, sp.pants);
    leg(ctx, 2.6 + l1 * 0.6, lift1, sp.pants);

    if (sp.sack) {
      G.blob(ctx, -7, by - 1, 6, 6.8, G.col('#9a6b3c'));
      G.blob(ctx, -7, by - 7.5, 2.2, 1.4, G.col('#7a4f28'), OUT, 1);
      G.blob(ctx, -8.5, by + 1, 1.6, 1.6, G.col('#ffd23f'), OUT, 0.8);
    }
    // bakre arm
    if (sp.weapon !== 'bomb') G.blob(ctx, -bw + 0.6, by + 3, 2.7, 2.7, G.col(skin), OUT, 1.3);

    if (sp.coat) G.poly(ctx, [[-bw - 0.5, by - 2], [bw + 0.5, by - 2], [bw + 2.5, by + 11], [-bw - 2.5, by + 11]], G.col(sp.shirt, -0.12), OUT, 1.4);
    G.blob(ctx, 0, by, bw, 7.4, G.col(sp.shirt), OUT, 1.5);
    if (sp.stripe || sp.vest) {
      ctx.save();
      ctx.beginPath(); ctx.ellipse(0, by, bw - 0.6, 6.8, 0, 0, Math.PI * 2); ctx.clip();
      if (sp.stripe) { ctx.fillStyle = G.col(sp.stripe); for (let i = 0; i < 4; i++) ctx.fillRect(-bw, by - 6.5 + i * 3.8, 2 * bw, 1.7); }
      if (sp.vest) { ctx.fillStyle = G.col(sp.vest); ctx.fillRect(-bw, by - 8, bw * 0.95, 16); ctx.fillRect(bw * 0.38, by - 8, bw, 16); }
      ctx.restore();
    }
    if (sp.coat) {
      G.blob(ctx, 3, by - 2.5, 1.2, 1.2, G.col('#ffcf3a'), OUT, 0.8);
      G.blob(ctx, 3, by + 1.5, 1.2, 1.2, G.col('#ffcf3a'), OUT, 0.8);
      ctx.strokeStyle = G.col('#ffcf3a'); ctx.lineWidth = 1.2;
      ctx.beginPath(); ctx.moveTo(-bw - 2.2, by + 10.5); ctx.lineTo(bw + 2.2, by + 10.5); ctx.stroke();
    }
    if (sp.collar) G.poly(ctx, [[-4, by - 6.8], [5, by - 6.8], [0.5, by - 2]], G.col(sp.collar), OUT, 1.1);
    ctx.fillStyle = G.col('#3b2412'); ctx.fillRect(-bw + 0.9, by + 2.6, 2 * bw - 1.8, 2.4);
    ctx.fillStyle = G.col('#f2c14e'); ctx.fillRect(0.6, by + 2.3, 3, 3);

    // huvud
    const hr = sp.big ? 7.8 : 8.6, hx = 1.6, hy = by - 11.2;
    if (sp.weapon === 'bomb') for (const sx of [-1, 1]) G.thick(ctx, [sx * (bw - 2.5), by - 4], [1.5 + sx * 8.5, hy - hr - 4], G.col(skin), 4);
    if (sp.head === 'bandana') {
      const fl = Math.sin(t * 9 + (u.id || 0)) * 1.5;
      G.poly(ctx, [[hx - hr + 1.5, hy - 4], [hx - hr - 6, hy - 6 + fl], [hx - hr - 4.5, hy - 1.5 + fl], [hx - hr + 1.5, hy - 1.8]], G.col(sp.hat), OUT, 1.2);
    }
    if (sp.head === 'tricorn') {
      ctx.beginPath(); ctx.moveTo(hx - 3, hy - 11); ctx.quadraticCurveTo(hx - 12, hy - 22, hx - 18, hy - 14);
      ctx.quadraticCurveTo(hx - 10, hy - 15, hx - 1, hy - 9); ctx.closePath();
      ctx.fillStyle = G.col('#ffffff'); ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = OUT; ctx.stroke();
    }
    if (sp.head === 'turban') G.poly(ctx, [[hx - hr + 1, hy - 3], [hx - hr - 4, hy + 4], [hx - hr + 2, hy + 1]], G.col(sp.hat, -0.06), OUT, 1.1);

    G.blob(ctx, hx, hy, hr, hr, G.col(skin), OUT, 1.6);
    G.blob(ctx, hx - 3.6, hy + 0.6, 1.8, 2.3, G.col(skin, -0.14), OUT, 1.1);
    if (sp.gold) G.blob(ctx, hx - 3.4, hy + 3.4, 1, 1, G.col('#ffcf3a'), OUT, 0.6);

    if (sp.beard) {
      ctx.beginPath(); ctx.ellipse(hx + 2.4, hy + 5, 6, 4.2, 0, 0, Math.PI);
      ctx.lineTo(hx - 3.6, hy + 2.5); ctx.closePath();
      ctx.fillStyle = G.col(sp.beard); ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = OUT; ctx.stroke();
    }
    // ansikte
    G.blob(ctx, hx + 8.3, hy + 0.9, 1.7, 1.4, G.col(skin, -0.1), OUT, 1);
    for (const ex of [hx + 2.7, hx + 6.2]) {
      G.blob(ctx, ex, hy - 0.4, 1.9, 2.4, '#ffffff', OUT, 1);
      G.blob(ctx, ex + 0.75, hy - 0.2, 1.1, 1.3, '#16121c', null);
    }
    ctx.strokeStyle = OUT; ctx.lineWidth = 1.8; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(hx + 0.9, hy - 3.8); ctx.lineTo(hx + 4.1, hy - 2.6);
    ctx.moveTo(hx + 5.0, hy - 2.7); ctx.lineTo(hx + 8.1, hy - 3.9); ctx.stroke();
    if (ap >= 0 || u.yell) {
      G.blob(ctx, hx + 5, hy + 4.2, 2.2, 1.9, '#5a1414', OUT, 1);
      ctx.fillStyle = '#fff'; ctx.fillRect(hx + 3.6, hy + 2.6, 2.8, 0.9);
    } else {
      ctx.beginPath(); ctx.moveTo(hx + 3.2, hy + 3.5); ctx.quadraticCurveTo(hx + 5.2, hy + 5.4, hx + 7.4, hy + 3.2);
      ctx.lineWidth = 1.3; ctx.stroke();
    }

    // huvudbonad
    if (sp.head === 'bandana') {
      ctx.beginPath(); ctx.arc(hx, hy, hr + 0.7, Math.PI, Math.PI * 2);
      ctx.quadraticCurveTo(hx, hy - 3.4, hx - hr - 0.7, hy); ctx.closePath();
      ctx.fillStyle = G.col(sp.hat); ctx.fill(); ctx.lineWidth = 1.5; ctx.strokeStyle = OUT; ctx.stroke();
      if (sp.dots) { ctx.fillStyle = 'rgba(255,255,255,.85)'; for (const [dx, dy] of [[-3, -5.5], [2, -6.6], [5.6, -4.2]]) { ctx.beginPath(); ctx.arc(hx + dx, hy + dy, 1, 0, 7); ctx.fill(); } }
    } else if (sp.head === 'turban') {
      ctx.beginPath(); ctx.ellipse(hx - 0.3, hy - 5, hr + 1.8, 5.8, 0, 0, Math.PI * 2);
      ctx.fillStyle = G.col(sp.hat); ctx.fill(); ctx.lineWidth = 1.5; ctx.strokeStyle = OUT; ctx.stroke();
      ctx.strokeStyle = G.col(sp.hat, -0.25); ctx.lineWidth = 1.1;
      ctx.beginPath(); ctx.ellipse(hx - 0.3, hy - 4, hr + 0.6, 3.2, -0.15, 0.2, Math.PI - 0.2); ctx.stroke();
      ctx.beginPath(); ctx.ellipse(hx - 0.3, hy - 7, hr - 1, 2.6, 0.15, 0.3, Math.PI - 0.3); ctx.stroke();
    } else if (sp.head === 'bald') {
      G.blob(ctx, hx + 2, hy - 5, 2.6, 1.6, 'rgba(255,255,255,.35)', null);
    } else if (sp.head === 'tricorn') {
      G.blob(ctx, hx, hy - 6.3, hr + 5, 3.6, G.col('#1f1a24'), OUT, 1.5);
      ctx.beginPath(); ctx.arc(hx, hy - 6.5, hr * 0.82, Math.PI, Math.PI * 2); ctx.closePath();
      ctx.fillStyle = G.col('#1f1a24'); ctx.fill(); ctx.stroke();
      ctx.beginPath(); ctx.ellipse(hx, hy - 6.3, hr + 4, 2.6, 0, 0.1, Math.PI - 0.1);
      ctx.strokeStyle = G.col('#ffcf3a'); ctx.lineWidth = 1.3; ctx.stroke();
      G.blob(ctx, hx + 2, hy - 10.2, 1.8, 1.6, '#f4f4f4', OUT, 0.8);
    } else if (sp.head === 'cap') {
      ctx.beginPath(); ctx.arc(hx, hy - 1, hr + 0.4, Math.PI, Math.PI * 2); ctx.closePath();
      ctx.fillStyle = G.col(sp.hat); ctx.fill(); ctx.lineWidth = 1.5; ctx.strokeStyle = OUT; ctx.stroke();
      G.blob(ctx, hx + hr * 0.7, hy - 1.4, 6, 1.8, G.col(sp.hat, -0.3), OUT, 1.2);
      G.blob(ctx, hx + 1, hy - 5.5, 1.4, 1.4, G.col('#ffcf3a'), OUT, 0.8);
    } else if (sp.head === 'sailor') {
      G.blob(ctx, hx, hy - 6.8, hr + 1, 3, G.col(sp.hat), OUT, 1.4);
      ctx.strokeStyle = G.col('#2c5aa0'); ctx.lineWidth = 1.4;
      ctx.beginPath(); ctx.ellipse(hx, hy - 6, hr, 1.6, 0, 0.15, Math.PI - 0.15); ctx.stroke();
    }

    // främre arm + vapen
    if (sp.weapon === 'bomb') {
      const bxp = 1.5, byp = hy - hr - 8.5;
      G.blob(ctx, bxp, byp, 7.5, 7.2, G.col('#2a2a33'), OUT, 1.6);
      G.blob(ctx, bxp - 2.4, byp - 2.6, 2.2, 1.6, 'rgba(255,255,255,.45)', null);
      ctx.beginPath(); ctx.moveTo(bxp + 3, byp - 6); ctx.quadraticCurveTo(bxp + 6, byp - 11, bxp + 9, byp - 10);
      ctx.strokeStyle = G.col('#c9a26b'); ctx.lineWidth = 1.6; ctx.stroke();
      const f = 2 + Math.sin(t * 40) * 1.2;
      G.blob(ctx, bxp + 9, byp - 10, f + 1, f + 1, '#ffd23f', null);
      G.blob(ctx, bxp + 9, byp - 10, f * 0.5, f * 0.5, '#ffffff', null);
      for (const sx of [-1, 1]) G.blob(ctx, bxp + sx * 8.5, byp + 4.5, 2.7, 2.7, G.col(skin), OUT, 1.2);
      return;
    }
    const shx = 2.5, shy = by - 4;
    let ang;
    if (sp.weapon === 'musket') ang = 0.4;
    else {
      ang = 1.05 + (moving ? Math.sin(w) * 0.25 : 0);
      if (ap >= 0) ang = ap < 0.4 ? lerp(1.05, -2.0, ap / 0.4) : lerp(-2.0, 1.3, Math.min(1, (ap - 0.4) / 0.25));
    }
    const al = 7.5;
    const hxp = shx + Math.cos(ang) * al, hyp = shy + Math.sin(ang) * al;
    G.thick(ctx, [shx, shy], [hxp, hyp], G.col(skin), 4.2);
    ctx.save();
    if (sp.weapon === 'musket') {
      const rec = ap >= 0 && ap < 0.3 ? (1 - ap / 0.3) : 0;
      ctx.translate(hxp - 2 - rec * 2, hyp);
      ctx.rotate(-0.12 - rec * 0.25);
      G.poly(ctx, [[-10, -0.6], [2, -2.2], [2, 2], [-10, 3.6]], G.col('#7a4a24'), OUT, 1.2);
      rr(ctx, 2, -2.4, 17, 2.6, 1); ctx.fillStyle = G.col('#4a5560'); ctx.fill(); ctx.lineWidth = 1.2; ctx.strokeStyle = OUT; ctx.stroke();
      if (rec > 0.3) {
        ctx.fillStyle = '#fff3a0';
        ctx.beginPath(); ctx.moveTo(19, -1); ctx.lineTo(26, -4); ctx.lineTo(23, -1); ctx.lineTo(27, 2); ctx.lineTo(19, 0.5); ctx.closePath(); ctx.fill();
      }
      G.blob(ctx, 6, 1.2, 2.5, 2.5, G.col(skin), OUT, 1.2);
    } else {
      ctx.translate(hxp, hyp);
      ctx.rotate(ang - 0.5);
      weapon(ctx, sp.weapon, sp, ap);
    }
    ctx.restore();
    G.blob(ctx, hxp, hyp, 2.7, 2.7, G.col(skin), OUT, 1.3);
    if (u.slow > 0) {
      ctx.fillStyle = 'rgba(120,200,255,.9)';
      for (let i = 0; i < 3; i++) {
        const a = t * 4 + i * 2.1;
        ctx.beginPath(); ctx.arc(hx + Math.cos(a) * 10, hy - 6 + Math.sin(a * 1.3) * 3, 1.4, 0, 7); ctx.fill();
      }
    }
  }

  // Livsmätare
  A.hpBar = function (ctx, X, Y, frac, color, w = 26) {
    const h = 5;
    rr(ctx, X - w / 2 - 1.5, Y - 1.5, w + 3, h + 3, 3);
    ctx.fillStyle = 'rgba(20,14,28,.85)'; ctx.fill();
    if (frac > 0) {
      rr(ctx, X - w / 2, Y, Math.max(2, w * frac), h, 2);
      ctx.fillStyle = color; ctx.fill();
      ctx.fillStyle = 'rgba(255,255,255,.35)'; ctx.fillRect(X - w / 2 + 1, Y + 0.6, Math.max(0, w * frac - 2), 1.4);
    }
  };

  A.crown = function (ctx, X, Y) {
    G.poly(ctx, [[X - 6, Y], [X - 6, Y - 6], [X - 3, Y - 3], [X, Y - 8], [X + 3, Y - 3], [X + 6, Y - 6], [X + 6, Y]], '#ffcf3a', OUT, 1.2);
  };

  // ---------- flaggor ----------
  A.flag = function (ctx, X, Y, colors, t, size = 1) {
    const w = 22 * size, h = 14 * size;
    G.thick(ctx, [X, Y + 2], [X, Y + 34 * size], '#d9dde2', 2.2 * size);
    G.blob(ctx, X, Y, 2.2 * size, 2.2 * size, '#ffcf3a', OUT, 1);
    const pts = [];
    const N = 7;
    for (let i = 0; i <= N; i++) { const f = i / N; pts.push([X + f * w, Y + 2 + Math.sin(t * 6 - f * 4) * 2.4 * f * size]); }
    const top = pts, bot = pts.map(([x, y]) => [x, y + h]).reverse();
    G.path(ctx, top.concat(bot));
    ctx.save(); ctx.clip();
    if (colors === 'pirate') {
      ctx.fillStyle = '#16121c'; ctx.fillRect(X - 2, Y - 6, w + 4, h + 14);
      const cx = X + w * 0.5, cy = Y + 2 + h * 0.5 + Math.sin(t * 6 - 2) * 1.2 * size;
      ctx.strokeStyle = '#f4f4f4'; ctx.lineWidth = 1.6 * size; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(cx - 6 * size, cy + 5 * size); ctx.lineTo(cx + 6 * size, cy - 1 * size);
      ctx.moveTo(cx + 6 * size, cy + 5 * size); ctx.lineTo(cx - 6 * size, cy - 1 * size); ctx.stroke();
      G.blob(ctx, cx, cy - 1 * size, 4 * size, 3.6 * size, '#f4f4f4', null);
      ctx.fillStyle = '#16121c';
      ctx.beginPath(); ctx.arc(cx - 1.5 * size, cy - 1.2 * size, 1 * size, 0, 7); ctx.arc(cx + 1.5 * size, cy - 1.2 * size, 1 * size, 0, 7); ctx.fill();
    } else {
      ctx.fillStyle = colors[0]; ctx.fillRect(X - 2, Y - 6, w + 4, h + 14);
      ctx.fillStyle = colors[1]; ctx.fillRect(X - 2, Y + 2 + h * 0.5 - 1, w + 4, h);
      G.blob(ctx, X + w * 0.32, Y + 2 + h * 0.5, 3 * size, 3 * size, colors[1], null);
    }
    ctx.restore();
    G.path(ctx, top.concat(bot)); ctx.lineWidth = 1.3; ctx.strokeStyle = OUT; ctx.stroke();
  };

  // ---------- skiff ----------
  A.skiff = function (ctx, sk, t, water) {
    const z = water + 2 + Math.sin(t * 3 + sk.seed) * 1.2;
    const c = Math.cos(sk.ang), s = Math.sin(sk.ang);
    const loc = [[0.85, 0], [0.35, 0.3], [-0.6, 0.3], [-0.72, 0.15], [-0.72, -0.15], [-0.6, -0.3], [0.35, -0.3]];
    const wp = (lx, ly, zz) => P(sk.x + lx * c - ly * s, sk.y + lx * s + ly * c, zz);
    if (sk.moving) {
      ctx.fillStyle = 'rgba(255,255,255,.45)';
      G.path(ctx, [wp(-0.6, 0.32, water), wp(-1.8, 0.75, water), wp(-1.8, -0.75, water), wp(-0.6, -0.32, water)]); ctx.fill();
    }
    G.poly(ctx, loc.map(([x, y]) => wp(x * 1.05, y * 1.15, water)), 'rgba(255,255,255,.35)', null);
    G.poly(ctx, loc.map(([x, y]) => wp(x, y, z - 5)), G.col(sk.color || '#2f7fd1', -0.25), OUT, 1.4);
    G.poly(ctx, loc.map(([x, y]) => wp(x, y, z)), G.col('#f4f6f8'), OUT, 1.5);
    G.poly(ctx, loc.map(([x, y]) => wp(x * 0.82, y * 0.7, z)), G.col('#c9d3dc'), null);
    const m0 = wp(-0.72, 0, z), m1 = wp(-0.95, 0, z + 9);
    G.thick(ctx, m0, m1, '#2a2d34', 5);
    G.blob(ctx, m1[0], m1[1], 3.4, 3, '#2a2d34', OUT, 1.2);
    return wp(0.05, 0, z);
  };

  // ---------- partiklar ----------
  A.particle = function (ctx, p) {
    const [X, Y] = P(p.x, p.y, p.z);
    const f = p.life / p.max; // 1 -> 0
    switch (p.type) {
      case 'smoke': case 'dust': case 'poof': {
        const r = p.size * (1.6 - f * 0.6);
        ctx.globalAlpha = Math.min(1, f * 1.4) * (p.alpha || 0.8);
        G.blob(ctx, X, Y, r, r * 0.92, p.color, null);
        ctx.globalAlpha = 1; break;
      }
      case 'fire': {
        ctx.globalCompositeOperation = 'lighter';
        const r = p.size * (0.4 + f * 0.8);
        ctx.globalAlpha = f;
        G.blob(ctx, X, Y, r, r * 1.2, f > 0.5 ? '#ffd23f' : '#ff6a1c', null);
        ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; break;
      }
      case 'flash': {
        ctx.globalCompositeOperation = 'lighter';
        ctx.globalAlpha = f;
        const g = ctx.createRadialGradient(X, Y, 0, X, Y, p.size);
        g.addColorStop(0, 'rgba(255,250,200,1)'); g.addColorStop(0.4, 'rgba(255,190,60,.8)'); g.addColorStop(1, 'rgba(255,120,0,0)');
        ctx.fillStyle = g; ctx.beginPath(); ctx.arc(X, Y, p.size, 0, 7); ctx.fill();
        ctx.globalAlpha = 1; ctx.globalCompositeOperation = 'source-over'; break;
      }
      case 'spark': {
        ctx.strokeStyle = p.color || '#ffd23f'; ctx.lineWidth = 2; ctx.globalAlpha = f;
        const [X2, Y2] = P(p.x - p.vx * 0.04, p.y - p.vy * 0.04, p.z - p.vz * 0.04);
        ctx.beginPath(); ctx.moveTo(X, Y); ctx.lineTo(X2, Y2); ctx.stroke(); ctx.globalAlpha = 1; break;
      }
      case 'debris': {
        ctx.globalAlpha = Math.min(1, f * 3);
        ctx.save(); ctx.translate(X, Y); ctx.rotate(p.rot || 0);
        ctx.fillStyle = p.color; ctx.strokeStyle = OUT; ctx.lineWidth = 1;
        ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.7); ctx.strokeRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.7);
        ctx.restore(); ctx.globalAlpha = 1; break;
      }
      case 'water': {
        ctx.globalAlpha = Math.min(1, f * 2);
        G.blob(ctx, X, Y, p.size, p.size, p.color || '#bfe9ff', null);
        ctx.globalAlpha = 1; break;
      }
      case 'ring': {
        const r = p.size * (1 - f) + 2;
        ctx.globalAlpha = f; ctx.strokeStyle = p.color || '#fff'; ctx.lineWidth = 3 * f + 1;
        ctx.beginPath(); ctx.ellipse(X, Y, r * G.R2 * 1.0, r * G.R2 * 0.5, 0, 0, 7); ctx.stroke(); ctx.globalAlpha = 1; break;
      }
      case 'coin': {
        ctx.globalAlpha = Math.min(1, f * 3);
        const sx = Math.abs(Math.cos(p.rot || 0)) * 4 + 0.6;
        G.blob(ctx, X, Y, sx, 4.4, '#ffcf3a', OUT, 1.2);
        ctx.globalAlpha = 1; break;
      }
      case 'skull': {
        ctx.globalAlpha = Math.min(1, f * 2);
        G.blob(ctx, X, Y - 6, 5, 4.6, '#f4f1ea', OUT, 1.2);
        ctx.fillStyle = '#1d1526';
        ctx.beginPath(); ctx.arc(X - 1.8, Y - 6.5, 1.2, 0, 7); ctx.arc(X + 1.8, Y - 6.5, 1.2, 0, 7); ctx.fill();
        ctx.fillRect(X - 2.2, Y - 2.6, 4.4, 2);
        ctx.globalAlpha = 1; break;
      }
      case 'plus': {
        ctx.globalAlpha = f; ctx.fillStyle = p.color || '#b6ff5a';
        ctx.fillRect(X - 1.2, Y - 4, 2.4, 8); ctx.fillRect(X - 4, Y - 1.2, 8, 2.4); ctx.globalAlpha = 1; break;
      }
      case 'note': {
        ctx.globalAlpha = f; ctx.fillStyle = p.color || '#ff4fd8';
        G.blob(ctx, X, Y, 2.6, 2, p.color, null); ctx.fillRect(X + 1.6, Y - 9, 1.4, 9); ctx.globalAlpha = 1; break;
      }
    }
  };

  // ---------- projektiler ----------
  A.projectile = function (ctx, pr) {
    const [X, Y] = P(pr.x, pr.y, pr.z);
    if (pr.kind === 'shell') {
      const [SX, SY] = P(pr.x, pr.y, 0);
      G.shadow(ctx, SX, SY, 6, 3, 0.25);
      G.blob(ctx, X, Y, 6, 6, '#2a2d34', OUT, 1.5);
      G.blob(ctx, X - 2, Y - 2, 1.8, 1.4, 'rgba(255,255,255,.5)', null);
    } else if (pr.kind === 'ball') {
      G.blob(ctx, X, Y, 4.6, 4.6, '#2a2d34', OUT, 1.3);
      G.blob(ctx, X - 1.4, Y - 1.4, 1.3, 1, 'rgba(255,255,255,.55)', null);
    } else {
      const [X2, Y2] = P(pr.x - pr.dx * 0.5, pr.y - pr.dy * 0.5, pr.z - pr.dz * 0.5);
      ctx.strokeStyle = pr.side === 'p' ? '#fff3a0' : '#ffd0a0'; ctx.lineWidth = 2.4; ctx.lineCap = 'round';
      ctx.beginPath(); ctx.moveTo(X, Y); ctx.lineTo(X2, Y2); ctx.stroke();
    }
  };

  // ---------- drycker: tekanna och trumma ----------
  A.kettle = function (ctx, X, Y, s = 1) {
    ctx.save(); ctx.translate(X, Y); ctx.scale(s, s);
    ctx.beginPath(); ctx.moveTo(8, -6); ctx.quadraticCurveTo(16, -8, 19, -16); ctx.lineTo(21, -15); ctx.quadraticCurveTo(18, -4, 9, -1); ctx.closePath();
    ctx.fillStyle = '#e0ad45'; ctx.fill(); ctx.lineWidth = 1.6; ctx.strokeStyle = OUT; ctx.stroke();
    ctx.beginPath(); ctx.arc(-11, -7, 6, Math.PI * 0.5, Math.PI * 1.5); ctx.lineWidth = 5; ctx.strokeStyle = OUT; ctx.stroke(); ctx.lineWidth = 2.6; ctx.strokeStyle = '#b07a22'; ctx.stroke();
    G.blob(ctx, 0, -6, 11, 9, '#e9b84c', OUT, 1.8);
    G.blob(ctx, -4, -10, 3.5, 2.4, 'rgba(255,255,255,.55)', null);
    G.blob(ctx, 0, -14.5, 6.5, 2.2, '#c98f2a', OUT, 1.4);
    G.blob(ctx, 0, -17.5, 2.2, 2, '#e9b84c', OUT, 1.2);
    ctx.strokeStyle = '#3a8f4a'; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(-9, -3); ctx.lineTo(9, -3); ctx.stroke();
    ctx.restore();
  };
  A.drum = function (ctx, X, Y, s = 1) {
    ctx.save(); ctx.translate(X, Y); ctx.scale(s, s);
    ctx.beginPath(); ctx.moveTo(-12, -18); ctx.lineTo(-12, -2); ctx.ellipse(0, -2, 12, 4.5, 0, Math.PI, 0, true); ctx.lineTo(12, -18); ctx.closePath();
    ctx.fillStyle = '#9b4a24'; ctx.fill(); ctx.lineWidth = 1.8; ctx.strokeStyle = OUT; ctx.stroke();
    ctx.strokeStyle = '#f4e6c4'; ctx.lineWidth = 1.5; ctx.beginPath();
    for (let i = 0; i < 6; i++) { const x = -11 + i * 4.4; ctx.moveTo(x, -17); ctx.lineTo(x + 2.2, -4); ctx.lineTo(x + 4.4, -17); }
    ctx.stroke();
    G.blob(ctx, 0, -18, 12, 4.5, '#f2deb0', OUT, 1.8);
    G.thick(ctx, [-14, -30], [-3, -19], '#d9a441', 2.6);
    G.thick(ctx, [14, -30], [3, -19], '#d9a441', 2.6);
    G.blob(ctx, -14, -30, 2.4, 2.4, '#f4f4f4', OUT, 1);
    G.blob(ctx, 14, -30, 2.4, 2.4, '#f4f4f4', OUT, 1);
    ctx.restore();
  };

  // ---------- porträtt för kort och paneler ----------
  const PORTRAIT_BG = {
    kampe: ['#9fd8ff', '#3f88c9'], skytt: ['#a8f0c6', '#2f9e6b'], bombare: ['#ffc58a', '#d9622b'],
    bjasse: ['#e2c19a', '#8a6440'], plundrare: ['#ffe58a', '#8a4fd1'], kapten: ['#ffd36b', '#c0262d'],
    lakning: ['#fff1a8', '#d9a441'], raseri: ['#ffb3ef', '#a42f9a'],
  };
  A.portrait = function (cv, key) {
    const ctx = cv.getContext('2d');
    const w = cv.width, h = cv.height;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const [c0, c1] = PORTRAIT_BG[key] || ['#ddd', '#888'];
    const g = ctx.createRadialGradient(w / 2, h * 0.35, 2, w / 2, h / 2, w * 0.75);
    g.addColorStop(0, c0); g.addColorStop(1, c1);
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
    if (key === 'lakning') { A.kettle(ctx, w / 2 - 2, h * 0.8, w / 48); return; }
    if (key === 'raseri') { A.drum(ctx, w / 2, h * 0.86, w / 46); return; }
    const sp = SPEC[key];
    const k = (h * 0.78) / (44 * sp.s) * (sp.weapon === 'bomb' ? 0.78 : 1);
    ctx.save();
    ctx.translate(w / 2 - 3 * k, h * 1.02);
    ctx.scale(k, k);
    A.unit(ctx, { type: key, facing: 1, skin: key === 'kapten' ? '#6b3f22' : '#7a4a2a', noShadow: true, id: 2 }, 0, 0, 0.3);
    ctx.restore();
  };
})();
