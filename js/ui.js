'use strict';

// ---------------------------------------------------------------------------
// Interface : journal, suivi d'initiative, barre d'actions, écrans
// ---------------------------------------------------------------------------
const $ = id => document.getElementById(id);

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
  pushLog(`<div class="msg ${u.side}">
    <div class="msg-head"><span class="msg-icon" style="background:${u.color}">${u.icon}</span>
      <span class="msg-who">${u.name}</span><span class="msg-time">Round ${G.round}</span></div>
    <div class="msg-body">${body}</div></div>`);
}

function logSystem(body) {
  pushLog(`<div class="msg system"><div class="msg-body">${body}</div></div>`);
}

function updateTopbar() {
  if (!G.map) return;
  $('level-info').textContent = `Niveau ${G.level + 1}/${LEVELS.length} — ${LEVELS[G.level].name}`;
  $('round-info').textContent = `Round ${G.round}`;
}

function updateTracker() {
  const cur = current();
  $('tracker').innerHTML = G.order.filter(u => !u.dead).map(u => {
    const pct = Math.round(u.hp / u.maxHp * 100);
    return `<li class="${u === cur ? 'active' : ''} ${u.side} ${u.hp <= 0 ? 'down' : ''}" data-id="${u.id}">
      <span class="tk-icon" style="background:${u.color}">${u.hp <= 0 ? '💤' : u.icon}</span>
      <span class="tk-main"><span class="tk-name">${u.name}</span>
        <span class="tk-bar"><span style="width:${pct}%"></span></span></span>
      <span class="tk-hp">${u.hp}/${u.maxHp}</span>
      <span class="tk-init">${Math.floor(u.init)}</span></li>`;
  }).join('');
  updateTopbar();
}

function updateActionBar() {
  const u = current();
  const bar = $('actionbar');
  if (!u || G.over) { bar.innerHTML = ''; return; }
  if (u.side !== 'hero') {
    bar.innerHTML = `<div class="ab-wait"><span class="ab-portrait" style="background:${u.color}">${u.icon}</span>
      Tour de <b>${u.name}</b>…</div>`;
    return;
  }
  const btns = u.abilities.map((ab, i) => {
    const cd = u.cooldowns[ab.id] || 0;
    const ready = abilityReady(u, ab);
    const tags = [ab.bonus ? 'Bonus' : 'Action'];
    if (ab.range) tags.push(ab.range === 1 ? 'Contact' : `Portée ${ab.range}`);
    if (ab.hit) tags.push(`+${ab.hit + hitBonus(u)} toucher`);
    if (ab.dmg) tags.push(`${ab.dmg}${dmgBonus(u) ? '+' + dmgBonus(u) : ''} dégâts`);
    if (ab.heal) tags.push(`${ab.heal}${dmgBonus(u) ? '+' + dmgBonus(u) : ''} soins`);
    if (ab.cd) tags.push(`Recharge ${ab.cd}`);
    return `<button class="ab-btn ${G.ability === ab ? 'selected' : ''} ${ab.bonus ? 'bonus' : ''}" ${ready ? '' : 'disabled'}
        onclick="selectAbility(${i})">
      <span class="ab-key">${i + 1}</span>
      <span class="ab-icon">${ab.icon}</span>
      <span class="ab-name">${ab.name}</span>
      ${cd ? `<span class="ab-cd">${cd}</span>` : ''}
      <span class="ab-tip"><b>${ab.name}</b><br>${ab.desc}<br><i>${tags.join(' · ')}</i></span>
    </button>`;
  }).join('');
  const nothingLeft = u.actionUsed && u.movesLeft <= 0 &&
    (u.bonusUsed || !u.abilities.some(a => a.bonus && abilityReady(u, a)));
  bar.innerHTML = `
    <div class="ab-hero">
      <span class="ab-portrait" style="background:${u.color}">${u.icon}</span>
      <div><div class="ab-name-big">${u.name} <small>niv. ${u.level}</small></div>
        <div class="ab-stats">❤️ ${u.hp}/${u.maxHp} · 🛡️ CA ${u.ac} · 👣 ${u.movesLeft}/${u.speed}</div>
        <div class="ab-res"><span class="${u.actionUsed ? 'used' : ''}">● Action</span>
          <span class="${u.bonusUsed ? 'used' : ''}">◆ Bonus</span></div></div>
    </div>
    <div class="ab-list">${btns}</div>
    <button class="end-btn ${nothingLeft ? 'pulse' : ''}" onclick="heroEndTurn()">Fin du tour <small>(Espace)</small></button>
    ${G.ability ? `<div class="ab-hint">🎯 Choisis une cible pour <b>${G.ability.name}</b> — clic droit / Échap pour annuler</div>` : ''}`;
}

// --- Info-bulle sur les jetons --------------------------------------------
function updateTooltip(ev) {
  const tip = $('tooltip');
  const cell = ev && cellFromEvent(ev);
  const u = cell && unitAt(cell.x, cell.y);
  if (!u) { tip.style.display = 'none'; return; }
  const ab = u.side === 'hero' ? u.abilities[0] : u.attack;
  let extra = '';
  const cur = current();
  if (cur && cur.side === 'hero' && u.side === 'monster' && !G.busy) {
    const d = distU(cur, u);
    extra = `<div class="tt-dist">Distance : ${d} case${d > 1 ? 's' : ''}${d > 1 && !hasLOS(G.map, cur.x, cur.y, u.x, u.y) ? ' · <span class="miss">hors de vue</span>' : ''}</div>`;
  }
  tip.innerHTML = `<b>${u.icon} ${u.name}</b>${u.side === 'hero' ? ` <small>niv. ${u.level}</small>` : ''}<br>
    ❤️ ${u.hp}/${u.maxHp} · 🛡️ CA ${u.ac} · 👣 ${u.speed}<br>
    <small>${ab.name} : ${ab.range > 1 ? 'portée ' + ab.range : 'contact'}, ${ab.dmg}</small>${extra}`;
  tip.style.display = 'block';
  const wrap = $('board-wrap').getBoundingClientRect();
  tip.style.left = (ev.clientX - wrap.left + 16) + 'px';
  tip.style.top = (ev.clientY - wrap.top + 16) + 'px';
}

// --- Écrans ----------------------------------------------------------------
function buildStartScreen() {
  const chosen = new Set(['guerrier', 'mage', 'rodeur', 'clerc']);
  const grid = $('class-grid');
  grid.innerHTML = Object.entries(CLASSES).map(([k, c]) => `
    <div class="class-card" data-key="${k}">
      <div class="cc-icon" style="background:${c.color}">${c.icon}</div>
      <div class="cc-name">${c.name}</div>
      <div class="cc-stats">❤️ ${c.hp} · 🛡️ ${c.ac} · 👣 ${c.speed}</div>
      <div class="cc-desc">${c.desc}</div>
      <ul class="cc-abs">${c.abilities.filter(a => a.type !== 'dash').map(a => `<li>${a.icon} ${a.name}</li>`).join('')}</ul>
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
    startGame(Object.keys(CLASSES).filter(k => chosen.has(k)));
  };
  refresh();
}

function showLevelUp() {
  const ov = $('end-screen');
  ov.innerHTML = `<div class="dialog">
    <h2>🏆 Victoire !</h2>
    <p>${LEVELS[G.level].name} est nettoyé en ${G.round} rounds.</p>
    <p>Vos héros se reposent et gagnent un niveau :</p>
    <ul class="lvl-list">${G.heroes.map(h => `<li>${h.icon} <b>${h.name}</b> : niveau ${h.level} → ${h.level + 1},
      PV max ${h.maxHp} → ${h.maxHp + CLASSES[h.cls].hpLvl}</li>`).join('')}</ul>
    <p class="muted">Chaque niveau : +PV, +1 aux dégâts et aux soins, +1 au toucher tous les 2 niveaux. Les PV sont restaurés.</p>
    <button class="primary" id="next-btn">Descendre plus profond ▶</button></div>`;
  ov.classList.remove('hidden');
  $('next-btn').onclick = () => { ov.classList.add('hidden'); nextLevel(); };
}

function showEnd(win) {
  const ov = $('end-screen');
  ov.innerHTML = `<div class="dialog">
    <h2>${win ? '👑 Le donjon est purifié !' : '💀 Défaite…'}</h2>
    <p>${win ? "L'Ogre est tombé. Vos héros ressortent couverts de gloire (et de poussière)." :
      `Votre groupe a péri au niveau ${G.level + 1} : ${LEVELS[G.level].name}.`}</p>
    <button class="primary" id="restart-btn">Nouvelle partie</button></div>`;
  ov.classList.remove('hidden');
  $('restart-btn').onclick = () => {
    ov.classList.add('hidden');
    G.map = null;
    $('start-screen').classList.remove('hidden');
  };
}

// --- Initialisation --------------------------------------------------------
function initUI() {
  const cv = $('board');
  cv.addEventListener('mousemove', ev => { G.hover = cellFromEvent(ev); updateTooltip(ev); });
  cv.addEventListener('mouseleave', () => { G.hover = null; updateTooltip(null); });
  cv.addEventListener('click', ev => { const c = cellFromEvent(ev); if (c) onCellClick(c.x, c.y); });
  cv.addEventListener('contextmenu', ev => { ev.preventDefault(); cancelTargeting(); });

  $('tracker').addEventListener('mouseover', ev => {
    const li = ev.target.closest('li');
    const u = li && G.units.find(x => x.id === +li.dataset.id);
    G.hover = u ? { x: u.x, y: u.y } : G.hover;
  });

  document.addEventListener('keydown', ev => {
    if (!$('start-screen').classList.contains('hidden')) return;
    if (ev.key === 'Escape') { cancelTargeting(); $('help').classList.add('hidden'); }
    else if (ev.key === ' ' || ev.key === 'Enter') { ev.preventDefault(); heroEndTurn(); }
    else if (/^[1-9]$/.test(ev.key)) selectAbility(+ev.key - 1);
  });

  $('help-btn').onclick = () => $('help').classList.toggle('hidden');
  $('help').onclick = e => { if (e.target.id === 'help' || e.target.closest('.close')) $('help').classList.add('hidden'); };

  buildStartScreen();
}

window.addEventListener('DOMContentLoaded', () => {
  initRender();
  initUI();
});
