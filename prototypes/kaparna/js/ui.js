// PROTOTYPE - NOT FOR PRODUCTION
// Question: Är det roligt att kapa skepp med Clash-liknande anfall?
// Date: 2026-10-22
//
// DOM-gränssnitt: HUD, sjökort, armé, smedja, stridskort, resultat, tips.
(function () {
  const K = window.K, D = K.DATA, A = K.art;
  const $ = (id) => document.getElementById(id);
  const UI = (K.ui = {});
  const COIN = '<svg class="ci" width="18" height="18" style="vertical-align:-3px"><use href="#i-coin"/></svg>';
  const LOCK = '<svg><use href="#i-lock"/></svg>';
  const STAR = '<svg><use href="#i-star"/></svg>';
  const fmt = (n) => Math.floor(n).toLocaleString('sv-SE');
  UI.fmt = fmt;

  // ---------- hjälpare för spelregler ----------
  UI.captured = (s) => D.ships.filter((d) => s.captured[d.id]).length;
  UI.armyCap = (s) => D.harbor[s.harborLvl - 1].army;
  UI.spellCap = (s) => D.harbor[s.harborLvl - 1].spells;
  UI.armyUsed = (s) => Object.keys(D.troops).reduce((a, k) => a + (s.army[k] || 0) * D.troops[k].space, 0);
  UI.spellUsed = (s) => Object.keys(D.spells).reduce((a, k) => a + (s.spells[k] || 0) * D.spells[k].space, 0);
  UI.levelCap = (s) => Math.min(D.maxLevel, s.harborLvl + 1);
  UI.unlocked = (s, key) => {
    const def = D.troops[key] || D.spells[key];
    return !def || UI.captured(s) >= (def.unlock || 0);
  };
  UI.defOf = (key) => (key === 'kapten' ? D.hero : D.troops[key] || D.spells[key]);
  UI.upCost = (key, lvl) => Math.round(D.upgradeCost[lvl] * (UI.defOf(key).upgradeMul || 1));
  UI.lvMul = (lvl) => 1 + D.levelScale * (lvl - 1);

  // ---------- små meddelanden ----------
  let toastT = 0;
  UI.toast = function (msg, ms = 1700) {
    const el = $('toast');
    el.textContent = msg; el.classList.add('show');
    clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove('show'), ms);
  };
  let bigT = 0;
  UI.bigMsg = function (html, ms = 2400) {
    const el = $('big-msg');
    el.innerHTML = html; el.hidden = false; el.classList.remove('show'); void el.offsetWidth; el.classList.add('show');
    clearTimeout(bigT); bigT = setTimeout(() => { el.hidden = true; el.classList.remove('show'); }, ms);
  };
  UI.hint = function (text, top) {
    const el = $('hint');
    if (!text) { el.hidden = true; return; }
    el.textContent = text; el.classList.toggle('top', !!top); el.hidden = false;
  };

  // ---------- paneler ----------
  let panelBuild = null;
  UI.showPanel = function (title, build) {
    $('panel-title').textContent = title;
    panelBuild = build;
    build($('panel-body'));
    $('panel').hidden = false;
  };
  UI.refreshPanel = function () { if (!$('panel').hidden && panelBuild) { const b = $('panel-body'), st = b.scrollTop; panelBuild(b); b.scrollTop = st; } };
  UI.closePanel = function () { $('panel').hidden = true; panelBuild = null; };
  UI.panelOpen = () => !$('panel').hidden;

  UI.confirm = function (title, text, yesLabel, onYes) {
    $('confirm-title').textContent = title;
    $('confirm-text').textContent = text;
    $('confirm-yes').textContent = yesLabel;
    $('confirm').hidden = false;
    $('confirm-yes').onclick = () => { $('confirm').hidden = true; onYes(); };
    $('confirm-no').onclick = () => { $('confirm').hidden = true; };
  };

  function portrait(cv, key) { A.portrait(cv, key); }

  // ---------- sjökort ----------
  const PLURAL = { kanon: ['kanon', 'kanoner'], vatten: ['vattenkanon', 'vattenkanoner'], utkik: ['utkikstorn', 'utkikstorn'], morsare: ['mörsare', 'mörsare'], vaktkur: ['vaktkur', 'vaktkurer'] };
  function defenseSummary(def) {
    const c = {};
    for (const e of def.layout) if (PLURAL[e[0]]) c[e[0]] = (c[e[0]] || 0) + 1;
    const parts = Object.keys(PLURAL).filter((k) => c[k]).map((k) => `${c[k]} ${PLURAL[k][c[k] > 1 ? 1 : 0]}`);
    const walls = (def.walls || []).reduce((a, w) => a + w[2], 0);
    if (walls) parts.push('barrikader');
    return parts.join(', ');
  }

  UI.renderMap = function (g, body) {
    const s = g.save;
    const used = UI.armyUsed(s), cap = UI.armyCap(s);
    const troopTxt = Object.keys(D.troops).filter((k) => s.army[k] > 0).map((k) => `${s.army[k]} ${D.troops[k].name.toLowerCase()}`).join(' · ') || 'Inga trupper';
    let html = `<div class="army-strip"><div><div class="sec-title">Din armé: ${used}/${cap} platser</div><div class="sub">${troopTxt} · Kaptenen följer alltid med</div></div><button class="btn btn-blue ol" data-act="army">Ändra armé</button></div>`;
    D.ships.forEach((d, i) => {
      const open = i === 0 || s.captured[D.ships[i - 1].id];
      const cap2 = s.captured[d.id];
      const stars = s.stars[d.id] || 0;
      const loot = Math.round(d.loot * (cap2 ? 0.7 : 1)) + (cap2 ? 0 : Math.round(d.loot * 0.25));
      html += `<div class="ship-card ${open ? '' : 'locked'}">
        <canvas width="380" height="240" data-ship="${i}"></canvas>
        <div class="info">
          <h3>${d.name} <span class="tier">Nivå ${d.tier}</span>${cap2 ? '<span class="tag-cap">Kapad</span>' : ''}</h3>
          <p class="story">${d.story}</p>
          <div class="facts"><span>Försvar: <b>${defenseSummary(d)}</b></span><span>Byte: <b>≈ ${fmt(loot)}</b> ${COIN}</span><span>Inkomst när kapad: <b>+${d.income}/min</b></span></div>
          <div class="act"><div class="mstars">${[1, 2, 3].map((n) => STAR.replace('<svg>', `<svg class="${stars >= n ? 'on' : ''}">`)).join('')}</div>
          ${open ? `<button class="btn btn-orange ol" data-act="attack" data-i="${i}">${cap2 ? 'Plundra igen' : 'ANFALL!'}</button>` : `<span class="lockmsg">${LOCK} Kapa ${D.ships[i - 1].name.toLowerCase()} först</span>`}</div>
        </div></div>`;
    });
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-ship]').forEach((cv) => { const d = D.ships[+cv.dataset.ship]; A.shipThumb(cv, d, !!s.captured[d.id]); });
    body.onclick = (e) => {
      const b = e.target.closest('[data-act]'); if (!b) return;
      K.sfx.play('click');
      if (b.dataset.act === 'army') UI.openArmy(g);
      if (b.dataset.act === 'attack') g.tryAttack(D.ships[+b.dataset.i]);
    };
  };
  UI.openMap = (g) => UI.showPanel('Sjökort – välj ditt byte', (b) => UI.renderMap(g, b));

  // ---------- armé ----------
  function statLine(key, lvl) {
    const d = UI.defOf(key), m = UI.lvMul(lvl);
    if (D.spells[key]) {
      if (key === 'lakning') return `<span>Läker <b>${Math.round(d.hps * m)}/s</b></span><span>Tid <b>${d.duration} s</b></span>`;
      return `<span>Skada <b>+${Math.round((d.dmgMul + 0.1 * (lvl - 1) - 1) * 100)} %</b></span><span>Fart <b>+${Math.round((d.spdMul - 1) * 100)} %</b></span>`;
    }
    const dps = key === 'bombare' ? d.dmg * m : (d.dmg * m) / d.atk;
    return `<span>Liv <b>${Math.round(d.hp * m)}</b></span><span>${key === 'bombare' ? 'Sprängskada' : 'Skada/s'} <b>${Math.round(dps)}</b></span>${d.space ? `<span>Plats <b>${d.space}</b></span>` : ''}`;
  }

  UI.renderArmy = function (g, body) {
    const s = g.save;
    const used = UI.armyUsed(s), cap = UI.armyCap(s), sUsed = UI.spellUsed(s), sCap = UI.spellCap(s);
    let html = `<div class="cap"><div class="cap-row"><span>Trupper</span><span>${used} / ${cap}</span></div><div class="bar ${used >= cap ? 'full' : ''}"><i style="width:${(used / cap) * 100}%"></i></div></div>`;
    html += `<p class="sub">Trupper du sätter ut i en strid är förbrukade efteråt. De du inte använder stannar kvar. Avträning ger tillbaka hela kostnaden.</p>`;
    html += '<div class="grid">';
    for (const key of Object.keys(D.troops)) {
      const d = D.troops[key], un = UI.unlocked(s, key), lv = s.levels[key] || 1, n = s.army[key] || 0;
      html += `<div class="ucard ${un ? '' : 'locked'}"><canvas width="200" height="160" data-p="${key}"></canvas>
        ${un ? `<span class="have ol">x${n}</span>` : ''}<span class="lvpip ol">Nv ${lv}</span>
        <h3>${d.name}</h3><span class="role">${d.role}</span><p class="desc">${d.desc}</p><div class="stats">${statLine(key, lv)}</div>
        ${un ? `<div class="row-btns"><button class="btn btn-red ol" data-act="rm" data-k="${key}" ${n ? '' : 'disabled'} aria-label="Ta bort ${d.name}">−</button><button class="btn btn-green ol" data-act="add" data-k="${key}" ${s.gold >= d.cost && used + d.space <= cap ? '' : 'disabled'}><span class="cost">+ ${d.cost} ${COIN}</span></button></div>`
          : `<span class="lockmsg">${LOCK} Lås upp: kapa ${d.unlock} skepp</span>`}
      </div>`;
    }
    const h = D.hero, hl = s.levels.kapten || 1;
    html += `<div class="ucard"><canvas width="200" height="160" data-p="kapten"></canvas><span class="lvpip ol">Nv ${hl}</span><h3>${h.name}</h3><span class="role">${h.role} · gratis</span><p class="desc">${h.desc}</p><div class="stats">${statLine('kapten', hl)}</div></div>`;
    html += '</div>';
    html += `<div class="cap"><div class="cap-row"><span>Drycker</span><span>${sUsed} / ${sCap}</span></div><div class="bar ${sUsed >= sCap ? 'full' : ''}"><i style="width:${(sUsed / sCap) * 100}%"></i></div></div><div class="grid">`;
    for (const key of Object.keys(D.spells)) {
      const d = D.spells[key], un = UI.unlocked(s, key), lv = s.levels[key] || 1, n = s.spells[key] || 0;
      html += `<div class="ucard ${un ? '' : 'locked'}"><canvas width="200" height="160" data-p="${key}"></canvas>
        ${un ? `<span class="have ol">x${n}</span>` : ''}<span class="lvpip ol">Nv ${lv}</span>
        <h3>${d.name}</h3><span class="role">${d.role}</span><p class="desc">${d.desc}</p><div class="stats">${statLine(key, lv)}</div>
        ${un ? `<div class="row-btns"><button class="btn btn-red ol" data-act="srm" data-k="${key}" ${n ? '' : 'disabled'} aria-label="Ta bort ${d.name}">−</button><button class="btn btn-green ol" data-act="sadd" data-k="${key}" ${s.gold >= d.cost && sUsed + d.space <= sCap ? '' : 'disabled'}><span class="cost">+ ${d.cost} ${COIN}</span></button></div>`
          : `<span class="lockmsg">${LOCK} Lås upp: kapa ${d.unlock} skepp</span>`}
      </div>`;
    }
    html += '</div>';
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-p]').forEach((cv) => portrait(cv, cv.dataset.p));
    body.onclick = (e) => {
      const b = e.target.closest('[data-act]'); if (!b || b.disabled) return;
      g.armyAction(b.dataset.act, b.dataset.k);
    };
  };
  UI.openArmy = (g) => UI.showPanel('Armélägret', (b) => UI.renderArmy(g, b));

  // ---------- smedja ----------
  UI.renderForge = function (g, body) {
    const s = g.save, L = s.harborLvl, caps = UI.captured(s);
    let html = '';
    const next = D.harbor[L];
    html += `<div class="ucard" style="grid-template-columns: 1fr; text-align:left"><h3>Piratfästet – nivå ${L}</h3>`;
    if (next) {
      const req = caps >= L;
      html += `<p class="desc">Nästa nivå: armé <b>${D.harbor[L - 1].army} → ${next.army}</b> platser, drycker <b>${D.harbor[L - 1].spells} → ${next.spells}</b>, och trupper kan uppgraderas till nivå <b>${Math.min(D.maxLevel, L + 2)}</b>.</p>`;
      html += req ? `<div class="row-btns" style="justify-content:flex-start"><button class="btn btn-green ol" data-act="harbor" ${s.gold >= next.cost ? '' : 'disabled'}><span class="cost">Bygg ut ${fmt(next.cost)} ${COIN}</span></button></div>`
        : `<span class="lockmsg">${LOCK} Kräver ${L} kapade skepp (du har ${caps})</span>`;
    } else html += '<p class="desc">Fästet är fullt utbyggt. Respekt!</p>';
    html += '</div><div class="sec-title">Uppgradera besättningen</div><div class="grid">';
    const keys = [...Object.keys(D.troops), 'kapten', ...Object.keys(D.spells)];
    for (const key of keys) {
      const d = UI.defOf(key), un = UI.unlocked(s, key), lv = s.levels[key] || 1;
      const max = lv >= D.maxLevel, capL = lv >= UI.levelCap(s);
      const cost = max ? 0 : UI.upCost(key, lv + 1);
      html += `<div class="ucard ${un ? '' : 'locked'}"><canvas width="200" height="160" data-p="${key}"></canvas><span class="lvpip ol">Nv ${lv}</span>
        <h3>${d.name}</h3><div class="stats">${statLine(key, lv)}</div>`;
      if (!un) html += `<span class="lockmsg">${LOCK} Lås upp: kapa ${d.unlock} skepp</span>`;
      else if (max) html += '<span class="sub">Max nivå</span>';
      else {
        html += `<div class="stats" style="color:#3aa357">Nivå ${lv + 1}: ${statLine(key, lv + 1)}</div>`;
        html += capL ? `<span class="lockmsg">${LOCK} Kräver Piratfästet nivå ${lv}</span>`
          : `<div class="row-btns"><button class="btn btn-orange ol" data-act="up" data-k="${key}" ${s.gold >= cost ? '' : 'disabled'}><span class="cost">${fmt(cost)} ${COIN}</span></button></div>`;
      }
      html += '</div>';
    }
    html += '</div>';
    body.innerHTML = html;
    body.querySelectorAll('canvas[data-p]').forEach((cv) => portrait(cv, cv.dataset.p));
    body.onclick = (e) => {
      const b = e.target.closest('[data-act]'); if (!b || b.disabled) return;
      if (b.dataset.act === 'harbor') g.upgradeHarbor();
      if (b.dataset.act === 'up') g.upgrade(b.dataset.k);
    };
  };
  UI.openForge = (g) => UI.showPanel('Smedjan', (b) => UI.renderForge(g, b));

  // ---------- hemma-HUD ----------
  let shownGold = -1;
  UI.updateHome = function (g, force) {
    const s = g.save;
    if (force || shownGold !== s.gold) { $('gold').textContent = fmt(s.gold); shownGold = s.gold; }
    $('rep').textContent = Object.values(s.stars).reduce((a, b) => a + b, 0);
    $('army-mini').textContent = `Armé ${UI.armyUsed(s)}/${UI.armyCap(s)}`;
    const use = $('btn-sound').querySelector('use');
    use.setAttribute('href', s.muted ? '#i-mute' : '#i-sound');
  };
  UI.bump = function (id) { const el = $(id); el.classList.remove('bump'); void el.offsetWidth; el.classList.add('bump'); };

  // ---------- strids-HUD ----------
  UI.buildBattleCards = function (g) {
    const bt = g.battle, wrap = $('b-cards');
    const keys = [...Object.keys(D.troops).filter((k) => bt.pool.troops[k] > 0), 'kapten', ...Object.keys(D.spells).filter((k) => bt.pool.spells[k] > 0)];
    wrap.innerHTML = keys.map((k) => {
      const d = UI.defOf(k), cls = D.spells[k] ? 'spell' : k === 'kapten' ? 'hero' : '';
      return `<button class="card ${cls}" data-k="${k}"><canvas width="144" height="140"></canvas><span class="cnt ol"></span><span class="lvl ol">${g.save.levels[k] || 1}</span><span class="nm ol">${d.name}</span></button>`;
    }).join('');
    wrap.querySelectorAll('.card').forEach((c) => portrait(c.querySelector('canvas'), c.dataset.k));
    wrap.onclick = (e) => {
      const c = e.target.closest('.card'); if (!c) return;
      const k = c.dataset.k;
      if (bt.remaining(k) <= 0) { K.sfx.play('error'); return; }
      bt.selected = k; K.sfx.play('click');
      UI.updateBattle(g, true);
    };
    const ab = $('b-ability');
    portrait(ab.querySelector('canvas'), 'kapten');
    $('b-ship').textContent = bt.def.name;
    $('b-loot-max').textContent = '/ ' + fmt(bt.lootTotal);
    $('b-stars').querySelectorAll('svg').forEach((sv) => sv.classList.remove('on'));
    UI._bstate = {};
  };

  UI.updateBattle = function (g, force) {
    const bt = g.battle, st = UI._bstate || (UI._bstate = {});
    const set = (k, v, fn) => { if (force || st[k] !== v) { st[k] = v; fn(v); } };
    $('b-cards').querySelectorAll('.card').forEach((c) => {
      const k = c.dataset.k, n = bt.remaining(k);
      set('n' + k, n, (v) => { c.querySelector('.cnt').textContent = k === 'kapten' ? (v ? '1' : '0') : 'x' + v; c.classList.toggle('empty', v <= 0); });
      set('s' + k, bt.selected === k, (v) => c.classList.toggle('sel', v));
    });
    const left = bt.started ? Math.max(0, bt.maxTime - bt.elapsed) : bt.maxTime;
    const txt = `${Math.floor(left / 60)}:${String(Math.floor(left % 60)).padStart(2, '0')}`;
    set('timer', txt, (v) => { $('b-timer').textContent = v; $('b-timer').classList.toggle('low', left < 30 && bt.started); });
    set('pct', bt.pct, (v) => { $('b-pct').textContent = v + ' %'; });
    set('loot', Math.floor(g.lootShown), (v) => { $('b-loot').textContent = fmt(v); });
    set('started', bt.started, (v) => { $('b-end').textContent = v ? 'Avsluta' : 'Tillbaka'; });
    const h = bt.heroUnit;
    set('ab', !!(h && h.hp > 0 && h.state === 'deck' && !bt.abilityUsed && !bt.ended), (v) => { $('b-ability').hidden = !v; });
  };

  UI.starOn = function (n) {
    const sv = $('b-stars').querySelectorAll('svg')[n - 1];
    if (sv) sv.classList.add('on');
  };

  // ---------- resultat ----------
  UI.showResult = function (g, res, def) {
    const win = res.stars > 0;
    $('res-title').textContent = win ? 'SEGER! · GUUL!' : 'NEDERLAG';
    $('res-title').classList.toggle('lose', !win);
    const stars = $('res-stars').querySelectorAll('svg');
    stars.forEach((sv, i) => { sv.classList.remove('on'); sv.style.animationDelay = (0.35 + i * 0.4) + 's'; if (i < res.stars) setTimeout(() => { sv.classList.add('on'); K.sfx.play('star'); }, 350 + i * 400); });
    $('res-pct').textContent = `${res.pct} % förstört`;
    const lootEl = $('res-loot');
    lootEl.textContent = '0';
    const t0 = performance.now(), dur = 1100;
    const tick = (now) => { const f = Math.min(1, (now - t0) / dur); lootEl.textContent = '+' + fmt(res.loot * (1 - Math.pow(1 - f, 3))); if (f < 1) requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
    const cap = $('res-capture');
    if (res.firstCapture) {
      cap.hidden = false;
      cap.innerHTML = `<b>SKEPPET ÄR KAPAT!</b><canvas width="440" height="260"></canvas><span>${def.name} har anslutit sig till din flotta och ger <b style="font-size:inherit">+${def.income} guld/min</b>. Kaparbonus: +${fmt(res.bonus)} guld.</span>`;
      A.shipThumb(cap.querySelector('canvas'), def, true);
    } else if (res.captured) {
      cap.hidden = false;
      cap.innerHTML = `<span>Bryggan intogs igen! Skeppet finns redan i din flotta.</span>`;
    } else if (!win) {
      cap.hidden = false;
      cap.innerHTML = `<span>Tips: förstör hälften av skeppet eller ta kommandobryggan för att vinna. Bombare spränger barrikader och Bjässar tål mycket stryk.</span>`;
    } else cap.hidden = true;
    const used = Object.keys(res.used).filter((k) => res.used[k] > 0).map((k) => `${res.used[k]} ${D.troops[k].name.toLowerCase()}`);
    const usedS = Object.keys(res.usedSpells).filter((k) => res.usedSpells[k] > 0).map((k) => `${res.usedSpells[k]} ${D.spells[k].name.toLowerCase()}`);
    $('res-used').textContent = used.length || usedS.length ? 'Förbrukat: ' + used.concat(usedS).join(', ') : '';
    $('result').hidden = false;
    K.sfx.play(win ? 'win' : 'lose');
  };
})();
