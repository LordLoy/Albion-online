'use strict';

// ---------------------------------------------------------------------------
// État global du jeu
// ---------------------------------------------------------------------------
const MAP_W = 18, MAP_H = 12;

const G = {
  level: 0,           // index dans LEVELS
  map: null,
  units: [],
  heroes: [],
  order: [],          // ordre d'initiative (unités)
  turnIdx: 0,
  round: 1,
  busy: false,        // animation / tour des monstres en cours
  ability: null,      // capacité en cours de ciblage
  reach: null,        // zone de déplacement du héros actif
  hover: null,        // case survolée
  floaters: [],       // textes flottants (dégâts, soins…)
  effects: [],        // projectiles, explosions
  over: false,
};
let nextId = 1;

const current = () => G.order[G.turnIdx];
const alive = u => !u.dead && u.hp > 0;
const unitAt = (x, y) => G.units.find(u => !u.dead && u.x === x && u.y === y);
const enemiesOf = u => G.units.filter(o => alive(o) && o.side !== u.side);
const alliesOf = u => G.units.filter(o => !o.dead && o.side === u.side);
const hitBonus = u => (u.side === 'hero' ? Math.floor((u.level - 1) / 2) : 0);
const dmgBonus = u => (u.side === 'hero' ? u.level - 1 : 0);

// ---------------------------------------------------------------------------
// Création des unités
// ---------------------------------------------------------------------------
function makeHero(key) {
  const c = CLASSES[key];
  return {
    id: nextId++, side: 'hero', cls: key, name: c.name, icon: c.icon, color: c.color,
    level: 1, maxHp: c.hp, hp: c.hp, ac: c.ac, speed: c.speed, dex: c.dex,
    abilities: c.abilities, cooldowns: {}, x: 0, y: 0, rx: 0, ry: 0,
  };
}

function makeMonster(key, n) {
  const m = MONSTERS[key];
  const hp = m.hp + G.level * 2;
  return {
    id: nextId++, side: 'monster', kind: key, name: m.name + (n > 1 ? ' ' + n : ''), icon: m.icon, color: m.color,
    maxHp: hp, hp, ac: m.ac, speed: m.speed, dex: m.dex, boss: !!m.boss,
    attack: m.attack, healAb: m.heal, cooldowns: {}, x: 0, y: 0, rx: 0, ry: 0,
  };
}

// ---------------------------------------------------------------------------
// Déroulement de la partie
// ---------------------------------------------------------------------------
function startGame(classKeys) {
  G.heroes = classKeys.map(makeHero);
  G.level = 0;
  G.over = false;
  document.getElementById('log').innerHTML = '';
  startLevel();
}

function startLevel() {
  const lvl = LEVELS[G.level];
  G.map = generateMap(MAP_W, MAP_H);
  G.units = [];
  G.floaters = []; G.effects = [];
  G.ability = null; G.reach = null;

  // Héros à gauche
  const heroCells = [];
  for (let y = 1; y < MAP_H - 1; y++) for (let x = 1; x <= 2; x++) heroCells.push([x, y]);
  const key = c => Math.abs(c[1] + 0.5 - MAP_H / 2) + Math.random() * 2;
  heroCells.map(c => [key(c), c]).sort((a, b) => a[0] - b[0]).forEach((e, i) => { heroCells[i] = e[1]; });
  G.heroes.forEach((h, i) => {
    h.x = h.rx = heroCells[i][0]; h.y = h.ry = heroCells[i][1];
    h.cooldowns = {};
    G.units.push(h);
  });

  // Monstres à droite
  const monsterCells = [];
  for (let y = 1; y < MAP_H - 1; y++) for (let x = MAP_W - 4; x <= MAP_W - 2; x++) {
    if (G.map.walkable(x, y)) monsterCells.push([x, y]);
  }
  shuffle(monsterCells);
  const counts = {};
  const totals = {};
  lvl.monsters.forEach(k => { totals[k] = (totals[k] || 0) + 1; });
  lvl.monsters.forEach((k, i) => {
    counts[k] = (counts[k] || 0) + 1;
    const m = makeMonster(k, totals[k] > 1 ? counts[k] : 0);
    m.x = m.rx = monsterCells[i][0]; m.y = m.ry = monsterCells[i][1];
    G.units.push(m);
  });

  logSystem(`<div class="lvl-title">Niveau ${G.level + 1} — ${lvl.name}</div>
    ${lvl.monsters.length} ennemis vous attendent dans l'ombre…`);
  updateTopbar();
  resizeBoard();
  rollInitiative();
  G.round = 1;
  G.turnIdx = 0;
  beginTurn();
}

function rollInitiative() {
  const lines = [];
  for (const u of G.units) {
    const r = d20();
    u.init = r + u.dex + Math.random() * 0.01; // départage aléatoire
    lines.push(`<div class="init-line"><span>${u.icon} ${u.name}</span><span class="roll-chip">🎲 ${r}${fmtMod(u.dex)} = <b>${r + u.dex}</b></span></div>`);
  }
  G.order = [...G.units].sort((a, b) => b.init - a.init);
  logSystem(`<b>Jets d'initiative</b>${lines.join('')}`);
}

function beginTurn() {
  if (G.over) return;
  const u = current();
  if (!u || u.dead) return endTurn();
  if (u.hp <= 0) { // héros inconscient
    logSystem(`${u.icon} <b>${u.name}</b> est inconscient et passe son tour.`);
    return endTurn();
  }
  u.movesLeft = u.speed;
  u.actionUsed = false;
  u.bonusUsed = false;
  for (const k in u.cooldowns) if (u.cooldowns[k] > 0) u.cooldowns[k]--;
  G.ability = null;
  updateTracker();

  if (u.side === 'hero') {
    G.busy = false;
    refreshReach();
    updateActionBar();
  } else {
    G.busy = true;
    G.reach = null;
    updateActionBar();
    monsterTurn(u).then(() => { if (!G.over) endTurn(); });
  }
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
    logSystem(`<div class="round-sep">— Round ${G.round} —</div>`);
  }
  updateTopbar();
  beginTurn();
}

function refreshReach() {
  const u = current();
  G.reach = u && u.side === 'hero' ? computeReach(u, G.units, G.map, u.movesLeft) : null;
}

// Retourne true si le combat est terminé
function checkEnd() {
  if (G.over) return true;
  if (!G.units.some(u => u.side === 'monster' && alive(u))) {
    G.over = true;
    G.busy = true;
    setTimeout(levelCleared, 900);
    return true;
  }
  if (!G.heroes.some(alive)) {
    G.over = true;
    G.busy = true;
    setTimeout(() => showEnd(false), 900);
    return true;
  }
  return false;
}

function levelCleared() {
  if (G.level >= LEVELS.length - 1) return showEnd(true);
  showLevelUp();
}

function nextLevel() {
  for (const h of G.heroes) {
    const c = CLASSES[h.cls];
    h.level++;
    h.maxHp += c.hpLvl;
    h.hp = h.maxHp;
  }
  G.level++;
  G.over = false;
  startLevel();
}

// ---------------------------------------------------------------------------
// Déplacement
// ---------------------------------------------------------------------------
function tween(u, tx, ty, ms) {
  const fx = u.rx, fy = u.ry, t0 = performance.now();
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
    await tween(u, x, y, 140);
    u.x = x; u.y = y;
  }
}

// ---------------------------------------------------------------------------
// Ciblage
// ---------------------------------------------------------------------------
function abilityReady(u, ab) {
  if ((u.cooldowns[ab.id] || 0) > 0) return false;
  return ab.bonus ? !u.bonusUsed : !u.actionUsed;
}

function needsTarget(ab) {
  return !['whirlwind', 'selfheal', 'massheal', 'dash'].includes(ab.type);
}

function inRange(u, x, y, range) {
  return dist(u.x, u.y, x, y) <= range && (range <= 1 || hasLOS(G.map, u.x, u.y, x, y));
}

function isValidTarget(u, ab, x, y) {
  if (!inRange(u, x, y, ab.range)) return false;
  const t = unitAt(x, y);
  switch (ab.type) {
    case 'attack': case 'autohit': case 'save':
      return !!t && alive(t) && t.side !== u.side;
    case 'heal':
      return !!t && t.side === u.side && t.hp < t.maxHp;
    case 'aoe': case 'aoeAttack':
      return true;
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
  if (ab.cd) u.cooldowns[ab.id] = ab.cd;
  if (ab.bonus) u.bonusUsed = true; else u.actionUsed = true;
  updateActionBar();

  const t = x !== undefined ? unitAt(x, y) : null;
  switch (ab.type) {
    case 'attack':
      await shoot(u, t, ab);
      resolveAttack(u, t, ab);
      break;
    case 'autohit': {
      await shoot(u, t, ab);
      const r = roll(ab.dmg, { bonus: dmgBonus(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Touche automatiquement.<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`);
      dealDamage(t, r.total);
      break;
    }
    case 'save': {
      await shoot(u, t, ab);
      const s = d20(), tot = s + t.dex, ok = tot >= ab.dc;
      const r = roll(ab.dmg, { bonus: dmgBonus(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Sauvegarde Dex : ${rollChip(s, t.dex)} vs DD ${ab.dc} — ${ok ? '<span class="miss">Réussie</span>' : '<span class="hit">Ratée</span>'}` +
        (ok ? '' : `<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`));
      if (ok) addFloater(t, 'Résiste', '#cfd6e0'); else dealDamage(t, r.total);
      break;
    }
    case 'aoe': {
      await shoot(u, { x, y }, ab);
      addEffect({ type: 'boom', x, y, r: ab.radius, color: ab.fx || '#ff5a1a', dur: 600 });
      const r = roll(ab.dmg, { bonus: dmgBonus(u) });
      const lines = [];
      const victims = unitsInRadius(x, y, ab.radius).filter(alive);
      for (const v of victims) {
        const s = d20(), ok = s + v.dex >= ab.dc;
        const dmg = ok ? (ab.half ? Math.floor(r.total / 2) : 0) : r.total;
        lines.push({ v, dmg, text: `${v.icon} ${v.name} : ${rollChip(s, v.dex)} ${ok ? '✔ moitié' : '✘'} → <b class="dmg">${dmg}</b>` });
      }
      log(u, `<b>${ab.name}</b> !<br>Dégâts : ${fmtRoll(r)} = <b>${r.total}</b> (DD ${ab.dc})` +
        (lines.length ? lines.map(l => `<div class="sub">${l.text}</div>`).join('') : '<br><i>Personne dans la zone.</i>'));
      for (const l of lines) dealDamage(l.v, l.dmg);
      break;
    }
    case 'aoeAttack': {
      await shoot(u, { x, y }, ab);
      addEffect({ type: 'boom', x, y, r: ab.radius, color: ab.fx || '#d9c38a', dur: 500 });
      const victims = unitsInRadius(x, y, ab.radius).filter(v => alive(v) && v.side !== u.side);
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
      const r = roll(ab.heal, { bonus: dmgBonus(u) });
      log(u, `<b>${ab.name}</b> → ${t.name}<br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b>`);
      healUnit(t, r.total);
      break;
    }
    case 'selfheal': {
      const r = roll(ab.heal, { bonus: dmgBonus(u) });
      log(u, `<b>${ab.name}</b><br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b>`);
      healUnit(u, r.total);
      break;
    }
    case 'massheal': {
      addEffect({ type: 'boom', x: u.x, y: u.y, r: ab.radius, color: '#7dffa8', dur: 700 });
      const r = roll(ab.heal, { bonus: dmgBonus(u) });
      const targets = alliesOf(u).filter(a => distU(a, u) <= ab.radius);
      log(u, `<b>${ab.name}</b><br>Soins : ${fmtRoll(r)} = <b class="heal">${r.total}</b> pour ${targets.map(a => a.name).join(', ')}`);
      for (const a of targets) healUnit(a, r.total);
      break;
    }
    case 'teleport': {
      addEffect({ type: 'boom', x: u.x, y: u.y, r: 0, color: '#6a4c9c', dur: 400 });
      u.x = u.rx = x; u.y = u.ry = y;
      addEffect({ type: 'boom', x, y, r: 0, color: '#6a4c9c', dur: 400 });
      log(u, `<b>${ab.name}</b><br>Disparaît dans les ombres et réapparaît plus loin.`);
      break;
    }
    case 'dash':
      u.movesLeft += u.speed;
      log(u, `<b>${ab.name}</b><br>+${u.speed} cases de déplacement.`);
      break;
  }
  await sleep(250);
  updateTracker();
  if (checkEnd()) return;
  if (u.side === 'hero') { G.busy = false; refreshReach(); updateActionBar(); }
}

function resolveAttack(u, t, ab) {
  const nat = d20(), bonus = ab.hit + hitBonus(u), total = nat + bonus;
  const crit = nat === 20, fumble = nat === 1;
  const hit = crit || (!fumble && total >= t.ac);
  let html = `<b>${ab.name}</b> → ${t.name}<br>${rollChip(nat, bonus)} vs CA ${t.ac} — ` +
    (hit ? (crit ? '<span class="crit">CRITIQUE !</span>' : '<span class="hit">Touché</span>') : (fumble ? '<span class="miss">Échec critique</span>' : '<span class="miss">Raté</span>'));
  if (!hit) {
    log(u, html);
    addFloater(t, 'Raté', '#9aa3b2');
    return;
  }
  const r = roll(ab.dmg, { crit, bonus: dmgBonus(u) });
  let dmg = r.total;
  html += `<br>Dégâts : ${fmtRoll(r)} = <b class="dmg">${r.total}</b>`;
  if (ab.sneak && G.units.some(o => o !== u && o.side === u.side && alive(o) && distU(o, t) <= 1)) {
    const s = roll(`${2 + Math.floor((u.level - 1) / 2)}d6`, { crit });
    dmg += s.total;
    html += `<br>Attaque sournoise : ${fmtRoll(s)} = <b class="dmg">${s.total}</b>`;
  }
  log(u, html);
  dealDamage(t, dmg, crit);
}

function dealDamage(t, amount, crit = false) {
  t.hp = Math.max(0, t.hp - amount);
  addFloater(t, (crit ? '💥 ' : '-') + amount, crit ? '#ffd23f' : '#ff5b5b');
  if (t.hp === 0) {
    if (t.side === 'monster') {
      t.dead = true;
      addEffect({ type: 'boom', x: t.x, y: t.y, r: 0, color: '#555', dur: 500 });
      logSystem(`☠️ <b>${t.name}</b> est vaincu !`);
    } else {
      logSystem(`💤 <b>${t.name}</b> tombe inconscient ! Un soin peut le relever.`);
    }
  }
}

function healUnit(t, amount) {
  const wasDown = t.hp === 0;
  t.hp = Math.min(t.maxHp, t.hp + amount);
  addFloater(t, '+' + amount, '#5fe08d');
  if (wasDown && t.hp > 0) logSystem(`✨ <b>${t.name}</b> reprend connaissance !`);
}

// ---------------------------------------------------------------------------
// Effets visuels
// ---------------------------------------------------------------------------
function addFloater(u, text, color) {
  G.floaters.push({ x: u.x, y: u.y, text, color, t0: performance.now() });
}
function addEffect(e) { G.effects.push({ ...e, t0: performance.now() }); }

async function shoot(u, target, ab) {
  if (!target) return;
  const d = dist(u.x, u.y, target.x, target.y);
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
  await sleep(350);
  const heroes = G.heroes.filter(alive);
  if (!heroes.length) return;

  // Chaman : soigne un allié blessé si possible
  if (m.healAb && !m.cooldowns.heal) {
    const hurt = G.units.filter(o => alive(o) && o.side === 'monster' && o.hp < o.maxHp * 0.5)
      .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0];
    if (hurt) {
      if (!inRange(m, hurt.x, hurt.y, m.healAb.range)) {
        const reach = computeReach(m, G.units, G.map, m.movesLeft);
        const cell = bestCell(m, reach, (x, y) => dist(x, y, hurt.x, hurt.y) <= m.healAb.range && hasLOS(G.map, x, y, hurt.x, hurt.y) ? 10 - reach.dist[G.map.idx(x, y)] * 0.1 : -Infinity);
        if (cell) await moveAlong(m, pathTo(reach, cell));
      }
      if (inRange(m, hurt.x, hurt.y, m.healAb.range)) {
        m.cooldowns.heal = 2;
        await useAbility(m, { ...m.healAb, cd: 0 }, hurt.x, hurt.y);
        return;
      }
    }
  }

  const ab = m.attack;
  if (ab.range > 1) return rangedTurn(m, ab);
  return meleeTurn(m, ab);
}

// Choisit la meilleure case atteignable (y compris la case actuelle) selon un score
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

async function meleeTurn(m, ab) {
  const full = computeReach(m, G.units, G.map);
  // Trouver la case adjacente à un héros la moins coûteuse
  let goal = -1, goalCost = Infinity, target = null;
  for (let i = 0; i < full.dist.length; i++) {
    if (full.dist[i] === Infinity) continue;
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    const o = unitAt(x, y);
    if (o && o !== m) continue;
    for (const h of G.heroes) {
      if (!alive(h) || dist(x, y, h.x, h.y) > 1) continue;
      const c = full.dist[i] + h.hp / h.maxHp * 1.5 + (h.ac - 12) * 0.15;
      if (c < goalCost) { goalCost = c; goal = i; target = h; }
    }
  }
  if (goal < 0) { // aucun accès : se rapprocher du héros le plus proche à vol d'oiseau
    const near = G.heroes.filter(alive).sort((a, b) => distU(m, a) - distU(m, b))[0];
    const reach = computeReach(m, G.units, G.map, m.movesLeft);
    const cell = bestCell(m, reach, (x, y) => -dist(x, y, near.x, near.y));
    if (cell !== null) await moveAlong(m, pathTo(reach, cell));
    return;
  }
  if (goal !== full.start) {
    const path = pathTo(full, goal);
    // Avancer le plus loin possible dans la limite du déplacement, sur une case libre
    let stop = -1;
    for (let k = 0; k < path.length; k++) {
      const i = path[k];
      if (full.dist[i] > m.movesLeft) break;
      const o = unitAt(i % G.map.w, (i / G.map.w) | 0);
      if (!o) stop = k;
    }
    if (stop >= 0) await moveAlong(m, path.slice(0, stop + 1));
  }
  // Attaquer le héros adjacent le plus faible
  const adj = G.heroes.filter(h => alive(h) && distU(m, h) <= 1).sort((a, b) => a.hp - b.hp);
  const tgt = adj.includes(target) ? target : adj[0];
  if (tgt) await useAbility(m, ab, tgt.x, tgt.y);
}

async function rangedTurn(m, ab) {
  const reach = computeReach(m, G.units, G.map, m.movesLeft);
  const heroes = G.heroes.filter(alive);
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
  // Toujours personne en vue : approcher
  if (m.movesLeft > 0) await meleeApproach(m);
}

async function meleeApproach(m) {
  const full = computeReach(m, G.units, G.map);
  const near = G.heroes.filter(alive).sort((a, b) => distU(m, a) - distU(m, b))[0];
  if (!near) return;
  let goal = -1, gc = Infinity;
  for (let i = 0; i < full.dist.length; i++) {
    if (full.dist[i] === Infinity) continue;
    const x = i % G.map.w, y = (i / G.map.w) | 0;
    const c = full.dist[i] + dist(x, y, near.x, near.y) * 2;
    if (c < gc) { gc = c; goal = i; }
  }
  if (goal < 0 || goal === full.start) return;
  const path = pathTo(full, goal);
  let stop = -1;
  for (let k = 0; k < path.length; k++) {
    const i = path[k];
    if (full.dist[i] > m.movesLeft) break;
    if (!unitAt(i % G.map.w, (i / G.map.w) | 0)) stop = k;
  }
  if (stop >= 0) await moveAlong(m, path.slice(0, stop + 1));
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

  // Déplacement
  if (G.reach) {
    const i = G.map.idx(x, y);
    const o = unitAt(x, y);
    if (!o && G.reach.dist[i] <= u.movesLeft && i !== G.reach.start) {
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
  const ab = u.abilities[idx];
  if (!ab || !abilityReady(u, ab)) return;
  if (G.ability === ab) { G.ability = null; updateActionBar(); return; }
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
