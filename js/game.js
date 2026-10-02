'use strict';

// ---------------------------------------------------------------------------
// Combat tactique
// ---------------------------------------------------------------------------
const MAP_W = 24, MAP_H = 16;
const SIGHT = 7;

const G = {
  map: null,
  units: [],
  order: [],          // ordre d'initiative
  turnIdx: 0,
  round: 1,
  busy: false,        // animation / tour des monstres en cours
  ability: null,      // capacité en cours de ciblage
  reach: null,        // zone de déplacement du héros actif
  hover: null,        // case survolée
  vis: null,          // cases visibles actuellement
  explored: null,     // cases déjà explorées
  floaters: [], effects: [], particles: [],
  shake: 0,
  over: false,
  kills: [],
  onEnd: null,        // callback(résultat) fourni par run.js
};
let nextId = 1;

const current = () => G.order[G.turnIdx];
const alive = u => !u.dead && u.hp > 0;
const unitAt = (x, y) => G.units.find(u => !u.dead && u.x === x && u.y === y);
const enemiesOf = u => G.units.filter(o => alive(o) && o.side !== u.side);
const alliesOf = u => G.units.filter(o => !o.dead && o.side === u.side);
const heroesAlive = () => G.units.filter(u => u.side === 'hero' && alive(u));
const isVisible = (x, y) => !!(G.vis && G.vis[G.map.idx(x, y)]);

// Statistiques dérivées (objets, talents, traits d'élite)
const mod = (u, k) => (u.mods && u.mods[k]) || 0;
const hitB = u => mod(u, 'hit') + (u.hitMod || 0);
const dmgB = u => mod(u, 'dmg') + (u.dmgMod || 0);
const healB = u => mod(u, 'heal');
const critMin = u => 20 - mod(u, 'crit');
const rangeOf = (u, ab) => (ab.range > 1 && !ab.consumable ? ab.range + mod(u, 'range') : ab.range || 0);
const radiusOf = (u, ab) => (ab.radius || 0) + (!ab.consumable && (ab.type === 'aoe' || ab.type === 'aoeAttack') ? mod(u, 'radius') : 0);
const cdOf = (u, ab) => (ab.cd ? Math.max(1, ab.cd - mod(u, 'cdr')) : 0);

// ---------------------------------------------------------------------------
// Création des monstres
// ---------------------------------------------------------------------------
function makeMonster(key, elite = null) {
  const m = MONSTERS[key];
  const u = {
    id: nextId++, side: 'monster', kind: key, name: m.name, icon: m.icon, sprite: m.sprite, color: m.color,
    maxHp: m.hp, hp: m.hp, ac: m.ac, speed: m.speed, dex: m.dex, boss: !!m.boss,
    attack: m.attack, healAb: m.heal, summon: m.summon, xp: m.xp, gold: m.gold,
    cooldowns: {}, status: {}, mods: {}, hitMod: 0, dmgMod: 0, x: 0, y: 0, rx: 0, ry: 0, face: -1, flash: 0,
    awake: false, group: 0,
  };
  if (typeof RUN !== 'undefined' && RUN.act > 0 && !m.boss) { // monstres plus coriaces dans les actes suivants
    u.maxHp = u.hp = Math.round(m.hp * (1 + 0.25 * RUN.act));
    u.hitMod += RUN.act; u.dmgMod += RUN.act;
  }
  if (elite) {
    u.elite = elite;
    u.name = `${m.name} ${elite.name.toLowerCase()}`;
    u.maxHp = Math.round(u.maxHp * 1.6); u.hp = u.maxHp;
    u.hitMod += 1; u.dmgMod += 1;
    elite.apply(u);
    u.xp *= 3; u.gold *= 3;
  }
  return u;
}

// ---------------------------------------------------------------------------
// Déroulement du combat
// ---------------------------------------------------------------------------
// encounter = { title, monsters: [clés], elite: index|null, awake: bool }
function startCombat(heroes, encounter, onEnd) {
  G.map = generateDungeon(MAP_W, MAP_H);
  G.units = [];
  G.floaters = []; G.effects = []; G.particles = [];
  G.ability = null; G.reach = null; G.over = false; G.busy = false;
  G.kills = [];
  G.onEnd = onEnd;
  G.explored = new Uint8Array(MAP_W * MAP_H);
  document.getElementById('log').innerHTML = '';

  const rooms = G.map.rooms;
  // Héros dans la première salle
  const startCells = shuffle([...rooms[0].cells]).sort((a, b) =>
    dist(a[0], a[1], rooms[0].cx, rooms[0].cy) - dist(b[0], b[1], rooms[0].cx, rooms[0].cy));
  heroes.forEach((h, i) => {
    const [x, y] = startCells[i];
    Object.assign(h, { x, y, rx: x, ry: y, cooldowns: {}, status: {}, dead: false, face: 1, flash: 0 });
    G.units.push(h);
  });

  // Salle la plus éloignée pour le boss / l'élite
  const reachStart = computeReach(heroes[0], [], G.map);
  const far = rooms.slice(1).sort((a, b) =>
    reachStart.dist[G.map.idx(b.cx, b.cy)] - reachStart.dist[G.map.idx(a.cx, a.cy)]);
  const others = encounter.awake ? [rooms[1]] : far.slice(1);
  const usedCells = new Set();
  const place = (m, room) => {
    const free = room.cells.filter(([x, y]) => !usedCells.has(x + ',' + y));
    const [x, y] = free.length ? free[rand(free.length)] : room.cells[0];
    usedCells.add(x + ',' + y);
    m.x = m.rx = x; m.y = m.ry = y;
    m.group = rooms.indexOf(room);
  };
  encounter.monsters.forEach((k, i) => {
    const isLeader = encounter.elite === i || MONSTERS[k].boss;
    const m = makeMonster(k, encounter.elite === i ? ELITE_TRAITS[rand(ELITE_TRAITS.length)] : null);
    m.awake = !!encounter.awake;
    let room;
    if (encounter.awake) room = rooms[1];
    else if (isLeader || encounter.boss) room = far[0];
    else room = others.length ? others[i % others.length] : far[0];
    place(m, room);
    G.units.push(m);
  });

  logSystem(`<div class="lvl-title">${encounter.title}</div>Vos héros s'avancent dans l'obscurité…`);
  updateFOV();
  resizeBoard();
  rollInitiative();
  G.round = 1;
  G.turnIdx = 0;
  beginTurn();
}

function rollInitiative() {
  const lines = [];
  for (const u of G.units) {
    const r = d20(), b = u.dex + mod(u, 'init');
    u.init = r + b + Math.random() * 0.01;
    if (u.side === 'hero') lines.push(`<div class="init-line"><span>${u.icon} ${u.name}</span>${rollChip(r, b)}</div>`);
  }
  G.order = [...G.units].sort((a, b) => b.init - a.init);
  logSystem(`<b>Jets d'initiative</b>${lines.join('')}`);
}

function updateFOV() {
  G.vis = computeFOV(G.map, heroesAlive(), SIGHT);
  for (let i = 0; i < G.vis.length; i++) if (G.vis[i]) G.explored[i] = 1;
  // Réveil des monstres qui voient un héros
  for (const m of G.units) {
    if (m.side !== 'monster' || m.dead || m.awake) continue;
    if (isVisible(m.x, m.y)) wakeGroup(m);
  }
}

function wakeGroup(m) {
  const group = G.units.filter(o => o.side === 'monster' && !o.dead && !o.awake && o.group === m.group);
  if (!group.length) return;
  for (const o of group) { o.awake = true; addFloater(o, '!', '#ffd23f'); }
  logSystem(`❗ ${group.map(o => `<b>${o.name}</b>`).join(', ')} ${group.length > 1 ? 'vous ont repérés' : 'vous a repérés'} !`);
}

async function beginTurn() {
  if (G.over) return;
  const u = current();
  if (!u || u.dead) return endTurn();
  if (u.side === 'monster' && !u.awake) return endTurn();
  if (u.hp <= 0) {
    logSystem(`💤 <b>${u.name}</b> est inconscient et passe son tour.`);
    return endTurn();
  }
  u.movesLeft = u.speed;
  u.actionUsed = false;
  u.bonusUsed = false;
  for (const k in u.cooldowns) if (u.cooldowns[k] > 0) u.cooldowns[k]--;
  G.ability = null;
  updateTracker();

  // États et régénération
  const skip = tickStatus(u);
  updateTracker();
  if (checkEnd()) return;
  if (u.hp <= 0 || u.dead) return endTurn();
  if (skip) { await sleep(500); return endTurn(); }
  if (u.status.slow) u.movesLeft = Math.ceil(u.speed / 2);

  if (u.side === 'hero') {
    G.busy = false;
    refreshReach();
    updateActionBar();
  } else {
    G.busy = true;
    G.reach = null;
    updateActionBar();
    await monsterTurn(u);
    if (!G.over) endTurn();
  }
}

// Applique les effets de début de tour. Retourne true si l'unité perd son tour.
function tickStatus(u) {
  const st = u.status;
  if (mod(u, 'regen') && u.hp > 0 && u.hp < u.maxHp) healUnit(u, mod(u, 'regen'), true);
  if (st.poison) { log(u, `🟢 Le poison fait effet : <b class="dmg">3</b> dégâts.`); dealDamage(u, 3); }
  if (st.burn && alive(u)) {
    const r = roll('1d6');
    log(u, `🔥 Brûlure : ${fmtRoll(r)} = <b class="dmg">${r.total}</b> dégâts.`);
    dealDamage(u, r.total);
  }
  let skip = false;
  if (st.stun && alive(u)) { skip = true; log(u, '💫 Étourdi, il perd son tour !'); addFloater(u, '💫', '#ffe066'); }
  for (const k of Object.keys(st)) { st[k]--; if (st[k] <= 0) delete st[k]; }
  return skip;
}

function applyStatus(t, onHit) {
  if (!onHit || !alive(t) || Math.random() > (onHit.chance ?? 1)) return '';
  t.status[onHit.status] = Math.max(t.status[onHit.status] || 0, onHit.turns + (onHit.status === 'slow' ? 1 : 0));
  const s = STATUS[onHit.status];
  addFloater(t, s.icon, s.color);
  return `<br>${s.icon} ${t.name} est <b>${s.name.toLowerCase()}</b> !`;
}

function endTurn() {
  if (G.over) return;
  G.ability = null;
  G.reach = null;
  G.turnIdx++;
  if (G.turnIdx >= G.order.length) {
    G.order = G.order.filter(u => !u.dead);
    G.turnIdx = 0;
    G.round++;
    if (G.units.some(u => u.side === 'monster' && u.awake && alive(u))) logSystem(`<div class="round-sep">— Round ${G.round} —</div>`);
  }
  updateTopbar();
  beginTurn();
}

function refreshReach() {
  const u = current();
  G.reach = u && u.side === 'hero' ? computeReach(u, G.units, G.map, u.movesLeft, G.explored) : null;
}

// Retourne true si le combat est terminé
function checkEnd() {
  if (G.over) return true;
  const win = !G.units.some(u => u.side === 'monster' && alive(u));
  const lose = !heroesAlive().length;
  if (!win && !lose) return false;
  G.over = true;
  G.busy = true;
  updateActionBar();
  setTimeout(() => {
    for (const h of G.units.filter(u => u.side === 'hero')) {
      h.status = {};
      if (win && h.hp <= 0) h.hp = 1;
    }
    G.onEnd && G.onEnd(win ? 'win' : 'lose');
  }, 1100);
  return true;
}

// ---------------------------------------------------------------------------
// Déplacement
// ---------------------------------------------------------------------------
function tween(u, tx, ty, ms) {
  const fx = u.rx, fy = u.ry, t0 = performance.now();
  if (tx !== fx) u.face = tx > fx ? 1 : -1;
  return new Promise(res => {
    function step(now) {
      const t = Math.min(1, (now - t0) / ms);
      const e = t * (2 - t);
      u.rx = fx + (tx - fx) * e; u.ry = fy + (ty - fy) * e;
      if (t < 1) requestAnimationFrame(step); else res();
    }
    requestAnimationFrame(step);
  });
}

async function moveAlong(u, path) {
  for (const i of path) {
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    u.movesLeft -= G.map.cost(x, y);
    const hidden = u.side === 'monster' && !isVisible(x, y) && !isVisible(u.x, u.y);
    if (hidden) { u.rx = x; u.ry = y; } else await tween(u, x, y, 130);
    u.x = x; u.y = y;
    if (u.side === 'hero') {
      updateFOV();
      // S'arrêter si un nouvel ennemi vient d'être repéré
      if (G.units.some(m => m.side === 'monster' && m.awake && !m.seenOnce && isVisible(m.x, m.y))) {
        G.units.forEach(m => { if (m.side === 'monster' && m.awake && isVisible(m.x, m.y)) m.seenOnce = true; });
        break;
      }
    }
  }
  if (u.side === 'hero') G.units.forEach(m => { if (m.side === 'monster' && m.awake && isVisible(m.x, m.y)) m.seenOnce = true; });
  updateTracker();
}

// ---------------------------------------------------------------------------
// Capacités (y compris potions) d'un héros
// ---------------------------------------------------------------------------
function heroAbilities(u) {
  const list = [...u.abilities];
  const counts = {};
  for (const k of RUN.potions) counts[k] = (counts[k] || 0) + 1;
  for (const k of Object.keys(POTIONS)) {
    if (!counts[k]) continue;
    list.push({ ...POTIONS[k], consumable: true, potionKey: k, count: counts[k], cd: 0 });
  }
  return list;
}

function abilityReady(u, ab) {
  if ((u.cooldowns[ab.id] || 0) > 0) return false;
  return ab.bonus ? !u.bonusUsed : !u.actionUsed;
}

function needsTarget(ab) {
  return !['whirlwind', 'selfheal', 'massheal', 'dash', 'cleanse'].includes(ab.type);
}

function inRange(u, x, y, range) {
  return dist(u.x, u.y, x, y) <= range && (range <= 1 || hasLOS(G.map, u.x, u.y, x, y));
}

function isValidTarget(u, ab, x, y) {
  if (!inRange(u, x, y, rangeOf(u, ab))) return false;
  if (u.side === 'hero' && !isVisible(x, y)) return false;
  const t = unitAt(x, y);
  switch (ab.type) {
    case 'attack': case 'autohit': case 'save':
      return !!t && alive(t) && t.side !== u.side;
    case 'heal':
      return !!t && t.side === u.side && (t.hp < t.maxHp || t.status.poison || t.status.burn);
    case 'aoe': case 'aoeAttack':
      return G.map.get(x, y) !== TILE.WALL;
    case 'teleport':
      return G.map.walkable(x, y) && !t;
  }
  return false;
}

function unitsInRadius(x, y, r) {
  return G.units.filter(o => !o.dead && dist(o.x, o.y, x, y) <= r);
}

// ---------------------------------------------------------------------------
// Résolution des capacités
// ---------------------------------------------------------------------------
async function useAbility(u, ab, x, y) {
  G.busy = true;
  G.ability = null;
  const cd = cdOf(u, ab);
  if (cd) u.cooldowns[ab.id] = cd;
  if (ab.bonus) u.bonusUsed = true; else u.actionUsed = true;
  if (ab.consumable) removePotion(ab.potionKey);
  updateActionBar();

  const t = x !== undefined ? unitAt(x, y) : null;
  if (t && t !== u && t.x !== u.x) u.face = t.x > u.x ? 1 : -1;
  switch (ab.type) {
    case 'attack':
      await shoot(u, t, ab);
      resolveAttack(u, t, ab);
      break;
    case 'autohit': {
      await shoot(u, t, ab);
      const r = roll(ab.dmg, { bonus: dmgB(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Touche automatiquement.<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`);
      dealDamage(t, r.total, false, u);
      break;
    }
    case 'save': {
      await shoot(u, t, ab);
      const s = d20(), ok = s + t.dex >= ab.dc;
      const r = roll(ab.dmg, { bonus: dmgB(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Sauvegarde Dex : ${rollChip(s, t.dex)} vs DD ${ab.dc} — ${ok ? '<span class="miss">Réussie</span>' : '<span class="hit">Ratée</span>'}` +
        (ok ? '' : `<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`));
      if (ok) addFloater(t, 'Résiste', '#cfd6e0'); else dealDamage(t, r.total, false, u);
      break;
    }
    case 'aoe': {
      const rad = radiusOf(u, ab);
      await shoot(u, { x, y }, ab);
      addEffect({ type: 'boom', x, y, r: rad, color: ab.fx || '#ff5a1a', dur: 600 });
      burst(x, y, ab.fx || '#ff7a2a', 30, 1 + rad);
      G.shake = 8;
      const r = roll(ab.dmg, { bonus: ab.consumable ? 0 : dmgB(u) });
      const lines = [];
      const victims = unitsInRadius(x, y, rad).filter(alive);
      for (const v of victims) {
        const s = d20(), ok = s + v.dex >= ab.dc;
        const dmg = ok ? (ab.half ? Math.floor(r.total / 2) : 0) : r.total;
        lines.push({ v, dmg, ok, text: `${v.icon} ${v.name} : ${rollChip(s, v.dex)} ${ok ? '✔ moitié' : '✘'} → <b class="dmg">${dmg}</b>` });
      }
      let extra = '';
      for (const l of lines) { dealDamage(l.v, l.dmg, false, u); if (!l.ok) extra += applyStatus(l.v, ab.onHit); }
      log(u, `<b>${ab.name}</b> !<br>Dégâts : ${fmtRoll(r)} = <b>${r.total}</b> (DD ${ab.dc})` +
        (lines.length ? lines.map(l => `<div class="sub">${l.text}</div>`).join('') : '<br><i>Personne dans la zone.</i>') + extra);
      break;
    }
    case 'aoeAttack': {
      const rad = radiusOf(u, ab);
      await shoot(u, { x, y }, ab);
      addEffect({ type: 'boom', x, y, r: rad, color: ab.fx || '#d9c38a', dur: 500 });
      const victims = unitsInRadius(x, y, rad).filter(v => alive(v) && v.side !== u.side);
      if (!victims.length) log(u, `<b>${ab.name}</b><br><i>Aucun ennemi dans la zone.</i>`);
      for (const v of victims) resolveAttack(u, v, ab);
      break;
    }
    case 'whirlwind': {
      addEffect({ type: 'boom', x: u.x, y: u.y, r: 1, color: '#e0e0e0', dur: 450 });
      const victims = enemiesOf(u).filter(v => distU(u, v) <= 1);
      if (!victims.length) log(u, `<b>${ab.name}</b><br><i>…mais aucun ennemi n'est au contact.</i>`);
      for (const v of victims) resolveAttack(u, v, ab);
      break;
    }
    case 'heal': {
      if (t !== u) await shoot(u, t, ab);
      const r = roll(ab.heal, { bonus: healB(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b>`);
      delete t.status.poison; delete t.status.burn;
      healUnit(t, r.total);
      break;
    }
    case 'selfheal': {
      const r = roll(ab.heal, { bonus: ab.consumable ? 0 : healB(u) });
      log(u, `<b>${ab.name}</b><br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b>`);
      healUnit(u, r.total);
      break;
    }
    case 'cleanse': {
      const r = roll(ab.heal);
      delete u.status.poison; delete u.status.burn; delete u.status.slow;
      log(u, `<b>${ab.name}</b><br>Les maux sont purgés. Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b>`);
      healUnit(u, r.total);
      break;
    }
    case 'massheal': {
      addEffect({ type: 'boom', x: u.x, y: u.y, r: ab.radius, color: '#7dffa8', dur: 700 });
      const r = roll(ab.heal, { bonus: healB(u) });
      const targets = alliesOf(u).filter(a => distU(a, u) <= ab.radius);
      log(u, `<b>${ab.name}</b><br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b> pour ${targets.map(a => a.name).join(', ')}`);
      for (const a of targets) healUnit(a, r.total);
      break;
    }
    case 'teleport': {
      burst(u.x, u.y, '#6a4c9c', 14, 0.6);
      u.x = u.rx = x; u.y = u.ry = y;
      burst(x, y, '#6a4c9c', 14, 0.6);
      log(u, `<b>${ab.name}</b><br>Disparaît dans les ombres et réapparaît plus loin.`);
      updateFOV();
      break;
    }
    case 'dash': {
      const n = ab.amount || u.speed;
      u.movesLeft += n;
      log(u, `<b>${ab.name}</b><br>+${n} cases de déplacement.`);
      break;
    }
  }
  await sleep(250);
  updateTracker();
  if (checkEnd()) return;
  if (u.side === 'hero') { G.busy = false; refreshReach(); updateActionBar(); }
}

function resolveAttack(u, t, ab) {
  const nat = d20(), bonus = (ab.hit || 0) + hitB(u), total = nat + bonus;
  const crit = nat >= critMin(u), fumble = nat === 1;
  const hit = crit || (!fumble && total >= t.ac);
  let html = `<b>${ab.name}</b> → ${t.name}<br>${rollChip(nat, bonus)} vs CA ${t.ac} — ` +
    (hit ? (crit ? '<span class="crit">CRITIQUE !</span>' : '<span class="hit">Touché</span>') : (fumble ? '<span class="miss">Échec critique</span>' : '<span class="miss">Raté</span>'));
  if (!hit) {
    log(u, html);
    addFloater(t, 'Raté', '#9aa3b2');
    if (t.side === 'monster' && !t.awake) wakeGroup(t);
    return;
  }
  const r = roll(ab.dmg, { crit, bonus: dmgB(u) });
  let dmg = r.total;
  html += `<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`;
  if (ab.sneak && G.units.some(o => o !== u && o.side === u.side && alive(o) && distU(o, t) <= 1)) {
    const s = roll(`${2 + Math.floor((u.level - 1) / 2) + mod(u, 'sneak')}d6`, { crit });
    dmg += s.total;
    html += `<br>Attaque sournoise : ${fmtRoll(s)} = <b class="dmg">${s.total}</b>`;
  }
  html += applyStatus(t, ab.onHit);
  log(u, html);
  dealDamage(t, dmg, crit, u);
  // Épines
  if (distU(u, t) <= 1 && mod(t, 'thorns') && alive(u)) {
    log(t, `🌵 Épines : <b class="dmg">${mod(t, 'thorns')}</b> dégâts renvoyés à ${u.name}.`);
    dealDamage(u, mod(t, 'thorns'));
  }
}

function dealDamage(t, amount, crit = false, source = null) {
  if (amount <= 0) return;
  t.hp = Math.max(0, t.hp - amount);
  t.flash = performance.now();
  addFloater(t, (crit ? '💥 ' : '-') + amount, crit ? '#ffd23f' : '#ff5b5b');
  burst(t.x, t.y, t.kind === 'squelette' || t.kind === 'liche' ? '#e6dcb8' : '#c83c3c', crit ? 16 : 8, 0.4);
  if (crit) G.shake = Math.max(G.shake, 6);
  if (t.side === 'monster' && !t.awake) wakeGroup(t);
  if (source && mod(source, 'lifesteal') && alive(source) && source !== t) {
    const h = Math.max(1, Math.floor(amount * mod(source, 'lifesteal')));
    healUnit(source, h, true);
  }
  if (t.hp === 0) {
    if (t.side === 'monster') {
      t.dead = true;
      G.kills.push(t);
      burst(t.x, t.y, '#888', 20, 0.6);
      logSystem(`☠️ <b>${t.name}</b> est vaincu !`);
    } else {
      t.status = {};
      logSystem(`💤 <b>${t.name}</b> tombe inconscient ! Un soin peut le relever.`);
      updateFOV();
    }
  }
}

function healUnit(t, amount, quiet = false) {
  const wasDown = t.hp === 0;
  const before = t.hp;
  t.hp = Math.min(t.maxHp, t.hp + amount);
  if (t.hp === before) return;
  addFloater(t, '+' + (t.hp - before), '#5fe08d');
  if (!quiet) burst(t.x, t.y, '#5fe08d', 10, 0.4, -1);
  if (wasDown && t.hp > 0) { logSystem(`✨ <b>${t.name}</b> reprend connaissance !`); updateFOV(); }
}

// ---------------------------------------------------------------------------
// Effets visuels
// ---------------------------------------------------------------------------
function addFloater(u, text, color) {
  if (u.side === 'monster' && !isVisible(u.x, u.y)) return;
  G.floaters.push({ x: u.x, y: u.y, text, color, t0: performance.now() });
}
function addEffect(e) { G.effects.push({ ...e, t0: performance.now() }); }

function burst(x, y, color, n, spread, gravity = 1) {
  if (!isVisible(x, y)) return;
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, s = (0.5 + Math.random()) * spread * 0.06;
    G.particles.push({
      x: x + 0.5, y: y + 0.5, vx: Math.cos(a) * s, vy: Math.sin(a) * s - (gravity < 0 ? 0.03 : 0.02),
      g: gravity * 0.002, life: 500 + Math.random() * 400, t0: performance.now(), color,
    });
  }
}

async function shoot(u, target, ab) {
  if (!target) return;
  const d = dist(u.x, u.y, target.x, target.y);
  const seen = isVisible(u.x, u.y) || isVisible(target.x, target.y);
  if (!seen) return;
  if (d <= 1) { // corps à corps : petite poussée vers la cible
    const fx = u.rx, fy = u.ry;
    await tween(u, fx + (target.x - fx) * 0.35, fy + (target.y - fy) * 0.35, 90);
    await tween(u, fx, fy, 110);
    return;
  }
  const dur = 120 + d * 35;
  addEffect({ type: 'bolt', fx: u.x, fy: u.y, tx: target.x, ty: target.y, color: ab.fx || '#fff', dur });
  await sleep(dur);
}

// ---------------------------------------------------------------------------
// IA des monstres
// ---------------------------------------------------------------------------
async function monsterTurn(m) {
  const visible = isVisible(m.x, m.y);
  await sleep(visible ? 300 : 40);
  if (!heroesAlive().length) return;

  // Liche : invoque un squelette régulièrement
  if (m.summon) {
    m.summonTimer = (m.summonTimer || 0) + 1;
    if (m.summonTimer >= m.summon.every) {
      m.summonTimer = 0;
      const free = DIRS.map(([dx, dy]) => [m.x + dx, m.y + dy]).filter(([x, y]) => G.map.walkable(x, y) && !unitAt(x, y));
      if (free.length) {
        const [x, y] = free[rand(free.length)];
        const s = makeMonster(m.summon.kind);
        Object.assign(s, { x, y, rx: x, ry: y, awake: true, group: m.group, init: m.init - 0.001 });
        G.units.push(s);
        G.order.splice(G.turnIdx + 1, 0, s);
        burst(x, y, '#b07dff', 20, 0.7);
        log(m, `🪦 <b>Relève-toi !</b> Un squelette surgit du sol.`);
        updateTracker();
        await sleep(400);
      }
    }
  }

  // Chaman : soigne un allié blessé si possible
  if (m.healAb && !m.cooldowns.heal) {
    const hurt = G.units.filter(o => alive(o) && o.side === 'monster' && o.awake && o.hp < o.maxHp * 0.5)
      .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0];
    if (hurt) {
      if (!inRange(m, hurt.x, hurt.y, m.healAb.range)) {
        const reach = computeReach(m, G.units, G.map, m.movesLeft);
        const cell = bestCell(m, reach, (x, y) => dist(x, y, hurt.x, hurt.y) <= m.healAb.range && hasLOS(G.map, x, y, hurt.x, hurt.y) ? 10 - reach.dist[G.map.idx(x, y)] * 0.1 : -Infinity);
        if (cell) await moveAlong(m, pathTo(reach, cell));
      }
      if (inRange(m, hurt.x, hurt.y, m.healAb.range)) {
        m.cooldowns.heal = 3;
        await useAbility(m, { ...m.healAb, cd: 0 }, hurt.x, hurt.y);
        return;
      }
    }
  }

  const ab = m.attack;
  if (ab.range > 1) return rangedTurn(m, ab);
  return meleeTurn(m, ab);
}

// Choisit la meilleure case atteignable (hors case actuelle) selon un score
function bestCell(m, reach, score) {
  let best = null, bs = -Infinity;
  for (let i = 0; i < reach.dist.length; i++) {
    if (reach.dist[i] > m.movesLeft) continue;
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    const o = unitAt(x, y);
    if (o && o !== m) continue;
    const s = score(x, y);
    if (s > bs) { bs = s; best = i; }
  }
  return best === null || best === reach.start ? null : best;
}

async function advance(m, full, goal) {
  const path = pathTo(full, goal);
  if (!path) return;
  let stop = -1;
  for (let k = 0; k < path.length; k++) {
    const i = path[k];
    if (full.dist[i] > m.movesLeft) break;
    if (!unitAt(i % G.map.w, (i / G.map.w) | 0)) stop = k;
  }
  if (stop >= 0) await moveAlong(m, path.slice(0, stop + 1));
}

async function meleeTurn(m, ab) {
  const full = computeReach(m, G.units, G.map);
  const heroes = heroesAlive();
  let goal = -1, goalCost = Infinity, target = null;
  for (let i = 0; i < full.dist.length; i++) {
    if (full.dist[i] === Infinity) continue;
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    const o = unitAt(x, y);
    if (o && o !== m) continue;
    for (const h of heroes) {
      if (dist(x, y, h.x, h.y) > 1) continue;
      const c = full.dist[i] + h.hp / h.maxHp * 1.5 + (h.ac - 12) * 0.15;
      if (c < goalCost) { goalCost = c; goal = i; target = h; }
    }
  }
  if (goal < 0) return approach(m);
  if (goal !== full.start) await advance(m, full, goal);
  const adj = heroesAlive().filter(h => distU(m, h) <= 1).sort((a, b) => a.hp - b.hp);
  const tgt = adj.includes(target) ? target : adj[0];
  if (tgt) await useAbility(m, ab, tgt.x, tgt.y);
}

async function rangedTurn(m, ab) {
  const reach = computeReach(m, G.units, G.map, m.movesLeft);
  const heroes = heroesAlive();
  const canShootFrom = (x, y) => heroes.filter(h => dist(x, y, h.x, h.y) <= ab.range && hasLOS(G.map, x, y, h.x, h.y));
  const score = (x, y) => {
    const targets = canShootFrom(x, y);
    const nearest = Math.min(...heroes.map(h => dist(x, y, h.x, h.y)));
    const cost = reach.dist[G.map.idx(x, y)];
    return (targets.length ? 100 : 0) + Math.min(nearest, 5) * 3 - cost * 0.4;
  };
  const here = score(m.x, m.y);
  const cell = bestCell(m, reach, score);
  if (cell !== null) {
    const cx = cell % G.map.w, cy = (cell / G.map.w) | 0;
    if (score(cx, cy) > here) await moveAlong(m, pathTo(reach, cell));
  }
  const targets = canShootFrom(m.x, m.y).sort((a, b) => a.hp - b.hp);
  if (targets.length) { await useAbility(m, ab, targets[0].x, targets[0].y); return; }
  if (m.movesLeft > 0) await approach(m);
}

async function approach(m) {
  const full = computeReach(m, G.units, G.map);
  const near = heroesAlive().sort((a, b) => distU(m, a) - distU(m, b))[0];
  if (!near) return;
  let goal = -1, gc = Infinity;
  for (let i = 0; i < full.dist.length; i++) {
    if (full.dist[i] === Infinity) continue;
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    const c = full.dist[i] + dist(x, y, near.x, near.y) * 2;
    if (c < gc) { gc = c; goal = i; }
  }
  if (goal < 0 || goal === full.start) return;
  await advance(m, full, goal);
}

// ---------------------------------------------------------------------------
// Interaction joueur
// ---------------------------------------------------------------------------
async function onCellClick(x, y) {
  const u = current();
  if (G.busy || G.over || !u || u.side !== 'hero') return;

  if (G.ability) {
    if (isValidTarget(u, G.ability, x, y)) await useAbility(u, G.ability, x, y);
    else if (x === u.x && y === u.y) { G.ability = null; updateActionBar(); }
    return;
  }

  if (G.reach) {
    const i = G.map.idx(x, y);
    if (!unitAt(x, y) && G.reach.dist[i] <= u.movesLeft && i !== G.reach.start) {
      G.busy = true;
      await moveAlong(u, pathTo(G.reach, i));
      G.busy = false;
      refreshReach();
      updateActionBar();
    }
  }
}

async function selectAbility(idx) {
  const u = current();
  if (G.busy || G.over || !u || u.side !== 'hero') return;
  const ab = heroAbilities(u)[idx];
  if (!ab || !abilityReady(u, ab)) return;
  if (G.ability && G.ability.id === ab.id) { G.ability = null; updateActionBar(); return; }
  if (!needsTarget(ab)) { await useAbility(u, ab); return; }
  G.ability = ab;
  updateActionBar();
}

function cancelTargeting() {
  if (G.ability) { G.ability = null; updateActionBar(); }
}

function heroEndTurn() {
  const u = current();
  if (G.busy || G.over || !u || u.side !== 'hero') return;
  endTurn();
}
