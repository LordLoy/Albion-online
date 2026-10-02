'use strict';

// ---------------------------------------------------------------------------
// Interface : journal, suivi d'initiative, barre d'actions, écran de départ
// ---------------------------------------------------------------------------
const $ = id => document.getElementById(id);

const spriteURLs = {};
function spriteImg(name, size) {
  if (!spriteURLs[name] && SPR[name]) spriteURLs[name] = SPR[name].img.toDataURL();
  return `<img class="spr" src="${spriteURLs[name] || ''}" width="${size}" height="${size}" alt="">`;
}

function rollChip(nat, bonus) {
  const cls = nat === 20 ? 'nat20' : nat === 1 ? 'nat1' : '';
  return `<span class="roll-chip ${cls}">🎲 ${nat}${fmtMod(bonus)} = <b>${nat + bonus}</b></span>`;
}

function pushLog(html) {
  const el = $('log');
  el.insertAdjacentHTML('beforeend', html);
  while (el.children.length > 150) el.firstChild.remove();
  el.scrollTop = el.scrollHeight;
}

function log(u, body) {
  if (u.side === 'monster' && !isVisible(u.x, u.y)) return;
  pushLog(`<div class="msg ${u.side}">
    <div class="msg-head">${spriteImg(u.sprite, 22)}
      <span class="msg-who">${u.name}</span><span class="msg-time">Round ${G.round}</span></div>
    <div class="msg-body">${body}</div></div>`);
}

function logSystem(body) {
  pushLog(`<div class="msg system"><div class="msg-body">${body}</div></div>`);
}

function updateTopbar() {
  const inRun = RUN.heroes.length > 0;
  $('level-info').textContent = inRun ? `Acte ${RUN.act + 1} — ${ACTS[RUN.act].name} · Salle ${Math.max(1, RUN.row + 1)}/${ACTS[RUN.act].rows + 1}` : '';
  $('round-info').innerHTML = inRun ? `🪙 ${RUN.gold} · ⭐ niv. ${RUN.level}${G.map && $('screen').classList.contains('hidden') ? ` · Round ${G.round}` : ''}` : '';
}

function trackerVisible(u) {
  return !u.dead && (u.side === 'hero' || isVisible(u.x, u.y) || (u.awake && u.seenOnce));
}

function updateTracker() {
  const cur = current();
  $('tracker').innerHTML = G.order.filter(trackerVisible).map(u => {
    const pct = Math.round(u.hp / u.maxHp * 100);
    const st = Object.keys(u.status || {}).map(k => STATUS[k].icon).join('');
    return `<li class="${u === cur ? 'active' : ''} ${u.side} ${u.hp <= 0 ? 'down' : ''} ${u.elite ? 'elite' : ''}" data-id="${u.id}">
      <span class="tk-icon">${spriteImg(u.sprite, 28)}</span>
      <span class="tk-main"><span class="tk-name">${u.name} ${st}${u.side === 'monster' && !u.awake ? ' 💤' : ''}</span>
        <span class="tk-bar"><span style="width:${pct}%"></span></span></span>
      <span class="tk-hp">${u.hp}/${u.maxHp}</span>
      <span class="tk-init">${Math.floor(u.init)}</span></li>`;
  }).join('');
  updateTopbar();
}

function abilityTags(u, ab) {
  const tags = [ab.bonus ? 'Action bonus' : 'Action'];
  const range = rangeOf(u, ab);
  if (range) tags.push(range === 1 ? 'Contact' : `Portée ${range}`);
  if (ab.radius) tags.push(`Zone ${radiusOf(u, ab) * 2 + 1}×${radiusOf(u, ab) * 2 + 1}`);
  if (ab.hit) tags.push(`+${ab.hit + hitB(u)} toucher`);
  if (ab.dmg) tags.push(`${ab.dmg}${!ab.consumable && dmgB(u) ? '+' + dmgB(u) : ''} dégâts`);
  if (ab.heal) tags.push(`${ab.heal}${!ab.consumable && healB(u) ? '+' + healB(u) : ''} soins`);
  if (ab.cd) tags.push(`Recharge ${cdOf(u, ab)}`);
  return tags.join(' · ');
}

function updateActionBar() {
  const u = current();
  const bar = $('actionbar');
  if (!u || G.over) { bar.innerHTML = ''; return; }
  if (u.side !== 'hero') {
    bar.innerHTML = `<div class="ab-wait">${spriteImg(u.sprite, 44)} ${isVisible(u.x, u.y) ? `Tour de <b>${u.name}</b>…` : 'Quelque chose bouge dans l\'ombre…'}</div>`;
    return;
  }
  const abs = heroAbilities(u);
  const btns = abs.map((ab, i) => {
    const cd = u.cooldowns[ab.id] || 0;
    const ready = abilityReady(u, ab);
    return `<button class="ab-btn ${G.ability && G.ability.id === ab.id ? 'selected' : ''} ${ab.bonus ? 'bonus' : ''} ${ab.consumable ? 'potion' : ''}" ${ready ? '' : 'disabled'}
        data-idx="${i}">
      ${i < 9 ? `<span class="ab-key">${i + 1}</span>` : ''}
      <span class="ab-icon">${ab.icon}</span>
      <span class="ab-name">${ab.name}</span>
      ${ab.count ? `<span class="ab-count">×${ab.count}</span>` : ''}
      ${cd ? `<span class="ab-cd">${cd}</span>` : ''}
      <span class="ab-tip"><b>${ab.name}</b><br>${ab.desc}<br><i>${abilityTags(u, ab)}</i></span>
    </button>`;
  }).join('');
  const st = Object.keys(u.status).map(k => `<span class="st" title="${STATUS[k].desc}">${STATUS[k].icon} ${STATUS[k].name}</span>`).join('');
  const nothingLeft = u.actionUsed && u.movesLeft <= 0 && (u.bonusUsed || !abs.some(a => a.bonus && abilityReady(u, a)));
  bar.innerHTML = `
    <div class="ab-hero">
      <span class="ab-portrait">${spriteImg(u.sprite, 48)}</span>
      <div><div class="ab-name-big">${u.name} <small>niv. ${u.level}</small></div>
        <div class="ab-stats">❤️ ${u.hp}/${u.maxHp} · 🛡️ CA ${u.ac} · 👣 ${u.movesLeft}/${u.speed}</div>
        <div class="ab-res"><span class="${u.actionUsed ? 'used' : ''}">● Action</span>
          <span class="${u.bonusUsed ? 'used' : ''}">◆ Bonus</span>${st}</div></div>
    </div>
    <div class="ab-list">${btns}</div>
    <button class="end-btn ${nothingLeft ? 'pulse' : ''}" id="end-btn">Fin du tour <small>(Espace)</small></button>
    ${G.ability ? `<div class="ab-hint">🎯 Choisis une cible pour <b>${G.ability.name}</b> — clic droit / Échap pour annuler</div>` : ''}`;
}

// --- Info-bulle sur les jetons --------------------------------------------
function updateTooltip(ev) {
  const tip = $('tooltip');
  const cell = ev && cellFromEvent(ev);
  const u = cell && unitAt(cell.x, cell.y);
  if (!u || (u.side === 'monster' && !isVisible(u.x, u.y))) { tip.style.display = 'none'; return; }
  const ab = u.side === 'hero' ? u.abilities[0] : u.attack;
  let extra = '';
  const cur = current();
  if (cur && cur.side === 'hero' && u.side === 'monster' && !G.busy) {
    const d = distU(cur, u);
    extra = `<div class="tt-dist">Distance : ${d} case${d > 1 ? 's' : ''}${d > 1 && !hasLOS(G.map, cur.x, cur.y, u.x, u.y) ? ' · <span class="miss">hors de vue</span>' : ''}</div>`;
  }
  const st = Object.keys(u.status).map(k => `${STATUS[k].icon} ${STATUS[k].name} (${u.status[k]})`).join(', ');
  tip.innerHTML = `<b>${u.name}</b>${u.side === 'hero' ? ` <small>niv. ${u.level}</small>` : ''}<br>
    ❤️ ${u.hp}/${u.maxHp} · 🛡️ CA ${u.ac} · 👣 ${u.speed}<br>
    <small>${ab.name} : ${ab.range > 1 ? 'portée ' + ab.range : 'contact'}, ${ab.dmg}</small>
    ${u.elite ? `<div class="tt-elite">⭐ ${u.elite.name} : ${u.elite.desc}</div>` : ''}
    ${u.side === 'monster' && !u.awake ? '<div class="tt-dist">💤 Endormi</div>' : ''}
    ${st ? `<div class="tt-dist">${st}</div>` : ''}${extra}`;
  tip.style.display = 'block';
  const wrap = $('board-wrap').getBoundingClientRect();
  tip.style.left = Math.min(ev.clientX - wrap.left + 16, wrap.width - 270) + 'px';
  tip.style.top = (ev.clientY - wrap.top + 16) + 'px';
}

// --- Écran de départ ---------------------------------------------------------
function buildStartScreen() {
  const chosen = new Set(['guerrier', 'mage', 'rodeur', 'clerc']);
  const grid = $('class-grid');
  grid.innerHTML = Object.entries(CLASSES).map(([k, c]) => `
    <div class="class-card" data-key="${k}" tabindex="0">
      <div class="cc-icon">${spriteImg(k, 64)}</div>
      <div class="cc-name">${c.name}</div>
      <div class="cc-stats">❤️ ${c.hp} · 🛡️ ${c.ac} · 👣 ${c.speed}</div>
      <div class="cc-desc">${c.desc}</div>
      <ul class="cc-abs">${c.abilities.filter(a => a.type !== 'dash' || a.amount).map(a => `<li>${a.icon} ${a.name}</li>`).join('')}</ul>
    </div>`).join('');
  const refresh = () => {
    grid.querySelectorAll('.class-card').forEach(el => el.classList.toggle('chosen', chosen.has(el.dataset.key)));
    $('party-count').textContent = `${chosen.size}/4 héros`;
    $('start-btn').disabled = chosen.size === 0;
  };
  grid.onclick = e => {
    const card = e.target.closest('.class-card');
    if (!card) return;
    const k = card.dataset.key;
    if (chosen.has(k)) chosen.delete(k);
    else if (chosen.size < 4) chosen.add(k);
    refresh();
  };
  $('start-btn').onclick = () => {
    $('start-screen').classList.add('hidden');
    newRun(Object.keys(CLASSES).filter(k => chosen.has(k)));
  };
  let best = null;
  try { best = JSON.parse(localStorage.getItem('donjon-best') || 'null'); } catch (e) { /* ignoré */ }
  $('best-run').textContent = best ? `Meilleure partie : acte ${best.act}, salle ${best.row}${best.win ? ' — victoire !' : ''}` : '';
  refresh();
}

// --- Initialisation --------------------------------------------------------
function initUI() {
  const cv = $('fx');
  cv.addEventListener('mousemove', ev => { G.hover = cellFromEvent(ev); updateTooltip(ev); });
  cv.addEventListener('mouseleave', () => { G.hover = null; updateTooltip(null); });
  cv.addEventListener('click', ev => { const c = cellFromEvent(ev); if (c) onCellClick(c.x, c.y); });
  cv.addEventListener('contextmenu', ev => { ev.preventDefault(); cancelTargeting(); });

  $('actionbar').addEventListener('click', ev => {
    const b = ev.target.closest('.ab-btn');
    if (b && !b.disabled) selectAbility(+b.dataset.idx);
    if (ev.target.closest('#end-btn')) heroEndTurn();
  });

  document.addEventListener('keydown', ev => {
    if (!$('start-screen').classList.contains('hidden') || !$('screen').classList.contains('hidden')) return;
    if (ev.key === 'Escape') { cancelTargeting(); $('help').classList.add('hidden'); }
    else if (ev.key === ' ' || ev.key === 'Enter') { ev.preventDefault(); heroEndTurn(); }
    else if (/^[1-9]$/.test(ev.key)) selectAbility(+ev.key - 1);
  });

  $('help-btn').onclick = () => $('help').classList.toggle('hidden');
  $('help').onclick = e => { if (e.target.id === 'help' || e.target.closest('.close')) $('help').classList.add('hidden'); };

  buildStartScreen();
}

function boot() { initRender(); initUI(); }
if (document.readyState === 'loading') window.addEventListener('DOMContentLoaded', boot); else boot();
