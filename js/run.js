'use strict';

// ---------------------------------------------------------------------------
// La partie roguelike : carte de parcours, récompenses, boutique, camp…
// ---------------------------------------------------------------------------
const RUN = {
  heroes: [], act: 0, row: -1, nodes: [], pos: null,
  gold: 0, potions: [], xp: 0, level: 1,
  stats: { kills: 0, fights: 0, gold: 0 },
  queue: [],   // étapes en attente (objets à attribuer, talents à choisir…)
};

const MAX_POTIONS = 6;

// ---------------------------------------------------------------------------
// Héros
// ---------------------------------------------------------------------------
function makeHero(key) {
  const c = CLASSES[key];
  const h = {
    id: nextId++, side: 'hero', cls: key, name: c.name, icon: c.icon, sprite: key, color: c.color,
    level: 1, hp: c.hp, maxHp: 0, ac: c.ac, speed: c.speed, dex: c.dex,
    abilities: c.abilities, items: [], talents: [], mods: {},
    cooldowns: {}, status: {}, x: 0, y: 0, rx: 0, ry: 0, face: 1, flash: 0,
  };
  recalcHero(h);
  h.hp = h.maxHp;
  return h;
}

function recalcHero(h) {
  const c = CLASSES[h.cls];
  const mods = {};
  const add = m => { for (const k in m) mods[k] = (mods[k] || 0) + m[k]; };
  h.items.forEach(k => add(ITEMS[k].mods));
  h.talents.forEach(id => add(TALENTS.find(t => t.id === id).mods));
  h.mods = mods;
  const old = h.maxHp;
  h.maxHp = c.hp + (h.level - 1) * c.hpLvl + (mods.hp || 0);
  if (old) h.hp = Math.max(h.hp > 0 ? 1 : 0, Math.min(h.maxHp, h.hp + Math.max(0, h.maxHp - old)));
  h.ac = c.ac + (mods.ac || 0);
  h.speed = c.speed + (mods.speed || 0);
}

// ---------------------------------------------------------------------------
// Fonctions utilisées par les événements
// ---------------------------------------------------------------------------
function damageParty(n) { RUN.heroes.forEach(h => { if (h.hp > 0) h.hp = Math.max(1, h.hp - n); }); }
function healPartyPct(p) { RUN.heroes.forEach(h => { h.hp = Math.min(h.maxHp, h.hp + Math.ceil(h.maxHp * p)); }); }
function addPotion(k) { if (RUN.potions.length < MAX_POTIONS) { RUN.potions.push(k); return true; } return false; }
function removePotion(k) { const i = RUN.potions.indexOf(k); if (i >= 0) RUN.potions.splice(i, 1); }
function randomPotionKey() { const k = Object.keys(POTIONS); return k[rand(k.length)]; }
function randomItems(n, minRarity = 1, maxRarity = 3) {
  const keys = shuffle(Object.keys(ITEMS).filter(k => ITEMS[k].rarity >= minRarity && ITEMS[k].rarity <= maxRarity));
  return keys.slice(0, n);
}
function grantItem(rarity, msg) {
  const [k] = randomItems(1, rarity, rarity);
  RUN.queue.push({ type: 'assign', item: k });
  return `${msg}<br>Vous obtenez : <b>${ITEMS[k].icon} ${ITEMS[k].name}</b> (${ITEMS[k].desc}).`;
}
function gainXp(n) {
  RUN.xp += n;
  while (RUN.level + 1 < LEVEL_XP.length && RUN.xp >= LEVEL_XP[RUN.level + 1]) {
    RUN.level++;
    for (const h of RUN.heroes) {
      h.level = RUN.level;
      recalcHero(h);
      h.hp = Math.min(h.maxHp, h.hp + CLASSES[h.cls].hpLvl);
      RUN.queue.push({ type: 'talent', hero: h });
    }
  }
}
function startMimicFight() {
  launchFight({ title: '📦 C\'était une Mimique !', monsters: ['mimique'], elite: null, awake: true }, 'elite');
}

// ---------------------------------------------------------------------------
// Nouvelle partie / carte des actes
// ---------------------------------------------------------------------------
function newRun(classKeys) {
  Object.assign(RUN, {
    heroes: classKeys.map(makeHero), act: 0, row: -1, pos: null,
    gold: 40, potions: ['soin', 'soin'], xp: 0, level: 1,
    stats: { kills: 0, fights: 0, gold: 0 }, queue: [],
  });
  RUN.nodes = generateRunMap(ACTS[0]);
  showMap();
}

function generateRunMap(act) {
  const COLS = 7;
  const rows = [];
  for (let r = 0; r < act.rows; r++) {
    const n = r === 0 ? 3 : 2 + rand(3);
    const cols = shuffle([...Array(COLS).keys()]).slice(0, n).sort((a, b) => a - b);
    rows.push(cols.map(c => ({ id: `${r}-${c}`, row: r, col: c, type: pickNodeType(r, act.rows), next: [] })));
  }
  // Liens entre rangées
  for (let r = 0; r < rows.length - 1; r++) {
    const cur = rows[r], nxt = rows[r + 1];
    for (const n of cur) {
      const sorted = [...nxt].sort((a, b) => Math.abs(a.col - n.col) - Math.abs(b.col - n.col));
      n.next.push(sorted[0].id);
      if (sorted[1] && Math.random() < 0.4 && Math.abs(sorted[1].col - n.col) <= 2) n.next.push(sorted[1].id);
    }
    for (const m of nxt) {
      if (cur.some(n => n.next.includes(m.id))) continue;
      const near = [...cur].sort((a, b) => Math.abs(a.col - m.col) - Math.abs(b.col - m.col))[0];
      near.next.push(m.id);
    }
  }
  const boss = { id: 'boss', row: act.rows, col: 3, type: 'boss', next: [] };
  rows[rows.length - 1].forEach(n => n.next.push('boss'));
  return [...rows.flat(), boss];
}

function pickNodeType(r, total) {
  if (r === 0) return 'combat';
  if (r === total - 1) return 'camp';
  if (r === Math.floor(total / 2) && Math.random() < 0.6) return 'treasure';
  const table = [['combat', 45], ['event', 22], ['elite', r >= 2 ? 13 : 0], ['shop', r >= 1 ? 10 : 0], ['camp', r >= 2 ? 7 : 0], ['treasure', 3]];
  let t = Math.random() * table.reduce((a, b) => a + b[1], 0);
  for (const [k, w] of table) { if ((t -= w) < 0) return k; }
  return 'combat';
}

const nodeById = id => RUN.nodes.find(n => n.id === id);
function availableNodes() {
  if (!RUN.pos) return RUN.nodes.filter(n => n.row === 0);
  return nodeById(RUN.pos).next.map(nodeById);
}

function enterNode(id) {
  const node = nodeById(id);
  if (!availableNodes().includes(node)) return;
  RUN.pos = id;
  RUN.row = node.row;
  node.visited = true;
  switch (node.type) {
    case 'combat': launchFight(buildEncounter('combat'), 'combat'); break;
    case 'elite': launchFight(buildEncounter('elite'), 'elite'); break;
    case 'boss': launchFight(buildEncounter('boss'), 'boss'); break;
    case 'event': showEvent(); break;
    case 'shop': showShop(makeShopStock()); break;
    case 'treasure': showTreasure(); break;
    case 'camp': showCamp(); break;
  }
}

// ---------------------------------------------------------------------------
// Combats
// ---------------------------------------------------------------------------
function buildEncounter(type) {
  const act = ACTS[RUN.act];
  if (type === 'boss') return { title: `👑 ${act.boss.name}`, monsters: [...act.boss.monsters], elite: null, boss: true };
  const scale = 0.45 + 0.15 * RUN.heroes.length;
  let budget = act.budget(Math.max(0, RUN.row)) * scale * (type === 'elite' ? 0.55 : 1);
  const monsters = [];
  let elite = null;
  if (type === 'elite') {
    monsters.push(act.elites[rand(act.elites.length)]);
    elite = 0;
  }
  do {
    const affordable = act.pool.filter(([, c]) => c <= budget);
    const [k, c] = affordable.length ? affordable[rand(affordable.length)] : act.pool[0];
    monsters.push(k);
    budget -= c;
  } while (budget >= 1 && monsters.length < 9);
  const title = type === 'elite' ? `💀 Acte ${RUN.act + 1} — Salle d'élite` : `⚔️ Acte ${RUN.act + 1} — Salle ${RUN.row + 1}`;
  return { title, monsters, elite };
}

function launchFight(encounter, kind) {
  hideScreen();
  RUN.stats.fights++;
  updateTopbar();
  startCombat(RUN.heroes, encounter, result => onFightEnd(result, kind));
}

function onFightEnd(result, kind) {
  if (result === 'lose') return showGameOver(false);
  const kills = G.kills;
  RUN.stats.kills += kills.length;
  const gold = kills.reduce((a, m) => a + m.gold, 0) + rand(8);
  const xp = kills.reduce((a, m) => a + m.xp, 0);
  RUN.gold += gold;
  RUN.stats.gold += gold;
  const rewards = { gold, xp, potion: null, items: [] };
  if (Math.random() < (kind === 'combat' ? 0.35 : 0.8)) {
    const k = randomPotionKey();
    if (addPotion(k)) rewards.potion = k;
  }
  if (kind === 'elite') rewards.items = randomItems(3, 1, 3);
  if (kind === 'boss') rewards.items = randomItems(3, 2, 3);
  gainXp(xp);
  showRewards(rewards, kind);
}

function afterNode() {
  // Étapes en attente (objets à attribuer, talents)
  const step = RUN.queue.shift();
  if (step) {
    if (step.type === 'assign') return showAssign(step.item);
    if (step.type === 'talent') return showTalent(step.hero);
  }
  const node = nodeById(RUN.pos);
  if (node && node.type === 'boss') {
    if (RUN.act >= ACTS.length - 1) return showGameOver(true);
    RUN.act++;
    RUN.row = -1;
    RUN.pos = null;
    RUN.nodes = generateRunMap(ACTS[RUN.act]);
    healPartyPct(1);
    return showActIntro();
  }
  showMap();
}

// ---------------------------------------------------------------------------
// Écrans
// ---------------------------------------------------------------------------
function screen(html, actions = {}) {
  const el = document.getElementById('screen');
  el.innerHTML = html;
  el.classList.remove('hidden');
  el.scrollTop = 0;
  el.onclick = e => {
    const b = e.target.closest('[data-act]');
    if (!b || b.disabled || !el.contains(b)) return;
    const fn = actions[b.dataset.act];
    if (fn) fn(b.dataset.arg);
  };
  updateTopbar();
}
function hideScreen() { document.getElementById('screen').classList.add('hidden'); }

function partyHtml(opts = {}) {
  return `<div class="party">${RUN.heroes.map((h, i) => `
    <div class="pcard ${opts.pick ? 'pickable' : ''} ${h.hp <= 0 ? 'down' : ''}" ${opts.pick ? `data-act="${opts.pick}" data-arg="${i}"` : ''}>
      <div class="pc-top">${spriteImg(h.sprite, 40)}
        <div class="pc-id"><b>${h.name}</b> <small>niv. ${h.level}</small>
          <div class="hpbar"><span style="width:${Math.round(h.hp / h.maxHp * 100)}%"></span></div>
          <small>❤️ ${h.hp}/${h.maxHp} · 🛡️ ${h.ac} · 👣 ${h.speed}</small></div></div>
      <div class="pc-gear">${h.items.map(k => `<span class="chip" title="${ITEMS[k].name} : ${ITEMS[k].desc}">${ITEMS[k].icon}</span>`).join('')}
        ${h.talents.map(id => { const t = TALENTS.find(x => x.id === id); return `<span class="chip talent" title="${t.name} : ${t.desc}">${t.icon}</span>`; }).join('')}</div>
    </div>`).join('')}</div>`;
}

function statusBar() {
  const next = LEVEL_XP[RUN.level + 1];
  return `<div class="runbar">
    <span>🪙 <b>${RUN.gold}</b> or</span>
    <span>⭐ Niveau ${RUN.level} <small>(${RUN.xp}${next ? '/' + next : ''} XP)</small></span>
    <span class="pots">${RUN.potions.length ? RUN.potions.map(k => `<span title="${POTIONS[k].name}">${POTIONS[k].icon}</span>`).join('') : '<small class="muted">aucune potion</small>'}</span>
  </div>`;
}

function showActIntro() {
  const act = ACTS[RUN.act];
  screen(`<div class="dialog">
    <h2>Acte ${RUN.act + 1} — ${act.name}</h2>
    <p>Vos héros descendent plus profondément. Ils récupèrent tous leurs PV avant d'affronter ce qui les attend.</p>
    <button class="primary" data-act="go">Continuer ▶</button></div>`, { go: showMap });
}

function showMap() {
  const act = ACTS[RUN.act];
  const avail = availableNodes().map(n => n.id);
  const W = 7, rowsN = act.rows + 1;
  const px = n => (n.type === 'boss' ? 3 : n.col) * 100 / (W - 1);
  const py = n => 100 - (n.row * 100 / rowsN) - 4;
  const lines = RUN.nodes.flatMap(n => n.next.map(id => {
    const m = nodeById(id);
    const on = n.visited && (m.visited || avail.includes(m.id));
    return `<line x1="${px(n)}%" y1="${py(n)}%" x2="${px(m)}%" y2="${py(m)}%" class="${on ? 'on' : ''}"/>`;
  })).join('');
  const nodes = RUN.nodes.map(n => {
    const t = NODE_TYPES[n.type];
    const cls = [n.type, avail.includes(n.id) ? 'avail' : '', n.visited ? 'visited' : '', RUN.pos === n.id ? 'here' : ''].join(' ');
    return `<button class="node ${cls}" style="left:${px(n)}%;top:${py(n)}%" ${avail.includes(n.id) ? `data-act="enter" data-arg="${n.id}"` : 'disabled'}
      title="${t.name} — ${t.desc}"><span>${t.icon}</span></button>`;
  }).join('');
  screen(`<div class="mapscreen">
    <div class="map-side">
      <h2>Acte ${RUN.act + 1} — ${act.name}</h2>
      ${statusBar()}
      ${partyHtml()}
      <div class="legend">${Object.entries(NODE_TYPES).map(([k, t]) => `<span>${t.icon} ${t.name}</span>`).join('')}</div>
    </div>
    <div class="map-wrap"><div class="map-inner">
      <svg class="map-lines" preserveAspectRatio="none">${lines}</svg>${nodes}
    </div><p class="muted map-hint">Choisis la prochaine salle (les cases qui brillent).</p></div>
  </div>`, { enter: enterNode });
}

function showRewards(r, kind) {
  let picked = false;
  const render = () => screen(`<div class="dialog">
    <h2>${kind === 'boss' ? '👑 Boss vaincu !' : '🏆 Victoire !'}</h2>
    <div class="rewards">
      <div class="reward">🪙 +${r.gold} or</div>
      <div class="reward">⭐ +${r.xp} XP</div>
      ${r.potion ? `<div class="reward">${POTIONS[r.potion].icon} ${POTIONS[r.potion].name}</div>` : ''}
    </div>
    ${r.items.length && !picked ? `<h3>Choisis un objet</h3><div class="items">${r.items.map(k => itemCard(k, 'item', k)).join('')}</div>` : ''}
    <button class="${r.items.length && !picked ? 'ghost' : 'primary'}" data-act="go">${r.items.length && !picked ? 'Passer' : 'Continuer ▶'}</button></div>`,
  {
    item: k => { picked = true; RUN.queue.unshift({ type: 'assign', item: k }); afterNode(); },
    go: () => afterNode(),
  });
  render();
}

function itemCard(k, act, arg, extra = '') {
  const it = ITEMS[k];
  return `<button class="item r${it.rarity}" data-act="${act}" data-arg="${arg}">
    <span class="it-icon">${it.icon}</span><b>${it.name}</b><small>${it.desc}</small>${extra}</button>`;
}

function showAssign(k) { showAssignThen(k, afterNode); }

function showTalent(h) {
  const pool = shuffle(TALENTS.filter(t => (!t.cls || t.cls === h.cls) && !(t.cls && h.talents.includes(t.id))));
  // au moins un talent de classe si possible
  const cls = pool.filter(t => t.cls), gen = pool.filter(t => !t.cls);
  const options = shuffle([...(cls.length ? [cls[0]] : []), ...gen.slice(0, 3)]).slice(0, 3);
  screen(`<div class="dialog">
    <h2>⭐ Niveau ${h.level} !</h2>
    <div class="lvl-hero">${spriteImg(h.sprite, 56)}<div><b>${h.name}</b><br><small>PV max ${h.maxHp} (+${CLASSES[h.cls].hpLvl})</small></div></div>
    <p>Choisis un talent :</p>
    <div class="items">${options.map(t => `<button class="item talent-card ${t.cls ? 'r3' : 'r1'}" data-act="pick" data-arg="${t.id}">
      <span class="it-icon">${t.icon}</span><b>${t.name}</b><small>${t.desc}</small>${t.cls ? '<em>Talent de classe</em>' : ''}</button>`).join('')}</div></div>`,
  { pick: id => { h.talents.push(id); recalcHero(h); afterNode(); } });
}

function showCamp() {
  screen(`<div class="dialog wide">
    <h2>🔥 Feu de camp</h2>
    <p>Les flammes crépitent. Vous pouvez souffler un instant.</p>
    ${partyHtml()}
    <div class="choices">
      <button class="choice" data-act="rest"><b>😴 Se reposer</b><small>Chaque héros récupère 40 % de ses PV max (les inconscients se relèvent).</small></button>
      <button class="choice" data-act="train"><b>🏋️ S'entraîner</b><small>Un héros de ton choix gagne un talent supplémentaire.</small></button>
    </div></div>`,
  {
    rest: () => { healPartyPct(0.4); afterNode(); },
    train: () => screen(`<div class="dialog wide"><h2>🏋️ Qui s'entraîne ?</h2>${partyHtml({ pick: 'pick' })}</div>`,
      { pick: i => { RUN.queue.unshift({ type: 'talent', hero: RUN.heroes[+i] }); afterNode(); } }),
  });
}

function makeShopStock() {
  return {
    items: randomItems(3).map(k => ({ k, price: 35 + ITEMS[k].rarity * 25 + rand(15), sold: false })),
    potions: shuffle(Object.keys(POTIONS)).slice(0, 3).map(k => ({ k, price: POTIONS[k].price, sold: false })),
    healUsed: false,
  };
}

function showShop(stock) {
  const healPrice = 30;
  screen(`<div class="dialog wide">
    <h2>💰 Le marchand</h2>
    <p class="muted">« Des articles de qualité, pour des aventuriers de qualité ! »</p>
    ${statusBar()}
    <h3>Objets</h3>
    <div class="items">${stock.items.map((s, i) => s.sold ? '<div class="item sold">Vendu</div>' :
      itemCard(s.k, 'buyItem', i, `<span class="price ${RUN.gold < s.price ? 'cant' : ''}">🪙 ${s.price}</span>`)).join('')}</div>
    <h3>Potions <small class="muted">(${RUN.potions.length}/${MAX_POTIONS})</small></h3>
    <div class="items">${stock.potions.map((s, i) => s.sold ? '<div class="item sold">Vendu</div>' : `
      <button class="item" data-act="buyPot" data-arg="${i}"><span class="it-icon">${POTIONS[s.k].icon}</span><b>${POTIONS[s.k].name}</b>
      <small>${POTIONS[s.k].desc}</small><span class="price ${RUN.gold < s.price ? 'cant' : ''}">🪙 ${s.price}</span></button>`).join('')}
      <button class="item" data-act="heal" ${stock.healUsed ? 'disabled' : ''}><span class="it-icon">⛑️</span><b>Soins</b>
      <small>Soigne 50 % des PV de chaque héros.</small><span class="price ${RUN.gold < healPrice ? 'cant' : ''}">🪙 ${healPrice}</span></button>
    </div>
    <button class="primary" data-act="leave">Partir ▶</button></div>`,
  {
    buyItem: i => {
      const s = stock.items[+i];
      if (RUN.gold < s.price) return;
      RUN.gold -= s.price; s.sold = true;
      showAssignThen(s.k, () => showShop(stock));
    },
    buyPot: i => {
      const s = stock.potions[+i];
      if (RUN.gold < s.price || RUN.potions.length >= MAX_POTIONS) return;
      RUN.gold -= s.price; s.sold = true; addPotion(s.k);
      showShop(stock);
    },
    heal: () => {
      if (RUN.gold < healPrice || stock.healUsed) return;
      RUN.gold -= healPrice; stock.healUsed = true; healPartyPct(0.5);
      showShop(stock);
    },
    leave: afterNode,
  });
}

function showAssignThen(k, then) {
  const it = ITEMS[k];
  screen(`<div class="dialog wide"><h2>${it.icon} ${it.name}</h2><p>${it.desc}. Quel héros doit le porter ?</p>${partyHtml({ pick: 'pick' })}</div>`,
    { pick: i => { const h = RUN.heroes[+i]; h.items.push(k); recalcHero(h); then(); } });
}

function showTreasure() {
  const items = randomItems(3, 1, 2);
  const gold = 25 + rand(25);
  RUN.gold += gold;
  screen(`<div class="dialog">
    <h2>💎 Un coffre au trésor !</h2>
    <div class="rewards"><div class="reward">🪙 +${gold} or</div></div>
    <h3>Choisis un objet</h3>
    <div class="items">${items.map(k => itemCard(k, 'item', k)).join('')}</div>
    <button class="ghost" data-act="go">Passer</button></div>`,
  { item: k => { RUN.queue.unshift({ type: 'assign', item: k }); afterNode(); }, go: afterNode });
}

function showEvent() {
  const ev = EVENTS[rand(EVENTS.length)];
  screen(`<div class="dialog">
    <h2>❓ ${ev.title}</h2>
    <p class="event-text">${ev.text}</p>
    ${partyHtml()}
    <div class="choices">${ev.choices.map((c, i) => `<button class="choice" data-act="choose" data-arg="${i}" ${c.cond && !c.cond() ? 'disabled' : ''}>${c.label}</button>`).join('')}</div>
  </div>`,
  {
    choose: i => {
      const msg = ev.choices[+i].run();
      if (msg === null) return; // l'événement a lancé un combat
      screen(`<div class="dialog"><h2>❓ ${ev.title}</h2><p class="event-text">${msg}</p>${statusBar()}
        <button class="primary" data-act="go">Continuer ▶</button></div>`, { go: afterNode });
    },
  });
}

function showGameOver(win) {
  const score = { act: RUN.act + 1, row: RUN.row + 1, kills: RUN.stats.kills, level: RUN.level, win };
  let best = null;
  try {
    best = JSON.parse(localStorage.getItem('donjon-best') || 'null');
    const better = !best || score.win > best.win || score.act > best.act || (score.act === best.act && score.row > best.row);
    if (better) localStorage.setItem('donjon-best', JSON.stringify(score));
  } catch (e) { /* stockage indisponible */ }
  screen(`<div class="dialog">
    <h2>${win ? '👑 Le donjon est purifié !' : '💀 Votre groupe a péri…'}</h2>
    <p>${win ? 'La Liche est retournée en poussière. Les bardes chanteront vos exploits.' : `Vous êtes tombés à l'acte ${score.act}, salle ${score.row}. Le donjon garde vos os… pour l'instant.`}</p>
    <div class="rewards">
      <div class="reward">☠️ ${RUN.stats.kills} monstres vaincus</div>
      <div class="reward">⭐ Niveau ${RUN.level}</div>
      <div class="reward">🪙 ${RUN.stats.gold} or ramassé</div>
    </div>
    ${best ? `<p class="muted">Meilleure partie : acte ${best.act}, salle ${best.row}${best.win ? ' (victoire)' : ''}.</p>` : ''}
    <button class="primary" data-act="again">Nouvelle partie</button></div>`,
  { again: () => { hideScreen(); G.map = null; document.getElementById('start-screen').classList.remove('hidden'); } });
}
