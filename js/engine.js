'use strict';

// ---------------------------------------------------------------------------
// Outils de base : hasard, dés, carte, déplacement, ligne de vue
// ---------------------------------------------------------------------------

const TILE = { FLOOR: 0, WALL: 1, RUBBLE: 2, WATER: 3 };
const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

function rand(n) { return Math.floor(Math.random() * n); }
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }
function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) { const j = rand(i + 1); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

// --- Dés --------------------------------------------------------------------
function d20() { return 1 + rand(20); }

function parseDice(expr) {
  const m = /^(\d+)d(\d+)([+-]\d+)?$/.exec(expr.replace(/\s/g, ''));
  if (!m) throw new Error('Formule de dés invalide : ' + expr);
  return { n: +m[1], d: +m[2], mod: m[3] ? +m[3] : 0 };
}

// Lance une formule "XdY+Z". Un critique double le nombre de dés.
function roll(expr, { crit = false, bonus = 0 } = {}) {
  const p = parseDice(expr);
  const n = crit ? p.n * 2 : p.n;
  const rolls = [];
  for (let i = 0; i < n; i++) rolls.push(1 + rand(p.d));
  const mod = p.mod + bonus;
  const total = Math.max(0, rolls.reduce((a, b) => a + b, 0) + mod);
  return { total, rolls, mod, label: `${n}d${p.d}` };
}

function fmtMod(mod) { return mod ? (mod > 0 ? ` + ${mod}` : ` − ${-mod}`) : ''; }
function fmtRoll(r) { return `${r.label} [${r.rolls.join(', ')}]${fmtMod(r.mod)}`; }

// --- Carte -----------------------------------------------------------------
class GameMap {
  constructor(w, h) {
    this.w = w; this.h = h;
    this.t = new Array(w * h).fill(TILE.FLOOR);
    this.deco = Array.from({ length: w * h }, () => Math.random());
  }
  idx(x, y) { return y * this.w + x; }
  inside(x, y) { return x >= 0 && y >= 0 && x < this.w && y < this.h; }
  get(x, y) { return this.inside(x, y) ? this.t[this.idx(x, y)] : TILE.WALL; }
  set(x, y, v) { if (this.inside(x, y)) this.t[this.idx(x, y)] = v; }
  walkable(x, y) { const t = this.get(x, y); return t === TILE.FLOOR || t === TILE.RUBBLE; }
  blocksSight(x, y) { return this.get(x, y) === TILE.WALL; }
  cost(x, y) { return this.get(x, y) === TILE.RUBBLE ? 2 : 1; }
}

// Donjon en salles reliées par des couloirs
function generateDungeon(w, h) {
  for (let attempt = 0; attempt < 200; attempt++) {
    const m = new GameMap(w, h);
    m.t.fill(TILE.WALL);
    const rooms = [];
    for (let tries = 0; tries < 300 && rooms.length < 8; tries++) {
      const rw = 4 + rand(4), rh = 3 + rand(3);
      const x = 1 + rand(w - rw - 2), y = 1 + rand(h - rh - 2);
      const r = { x, y, w: rw, h: rh, cx: x + (rw >> 1), cy: y + (rh >> 1) };
      if (rooms.some(o => x <= o.x + o.w + 1 && x + rw + 1 >= o.x && y <= o.y + o.h + 1 && y + rh + 1 >= o.y)) continue;
      rooms.push(r);
    }
    if (rooms.length < 5) continue;
    rooms.sort((a, b) => a.cx - b.cx);
    for (const r of rooms) for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) m.set(x, y, TILE.FLOOR);

    const carve = (a, b) => {
      const wide = Math.random() < 0.35;
      let x = a.cx, y = a.cy;
      const horizFirst = Math.random() < 0.5;
      const dig = (x, y) => { if (m.get(x, y) === TILE.WALL && x > 0 && y > 0 && x < w - 1 && y < h - 1) m.set(x, y, TILE.FLOOR); };
      const stepX = () => { while (x !== b.cx) { x += Math.sign(b.cx - x); dig(x, y); if (wide) dig(x, y + 1); } };
      const stepY = () => { while (y !== b.cy) { y += Math.sign(b.cy - y); dig(x, y); if (wide) dig(x + 1, y); } };
      if (horizFirst) { stepX(); stepY(); } else { stepY(); stepX(); }
    };
    for (let i = 1; i < rooms.length; i++) carve(rooms[i - 1], rooms[i]);
    for (let k = 0; k < 2; k++) { // boucles
      const a = rooms[rand(rooms.length)], b = rooms[rand(rooms.length)];
      if (a !== b) carve(a, b);
    }

    // Décor dans les grandes salles
    for (const r of rooms.slice(1)) {
      const roll = Math.random();
      if (r.w >= 6 && r.h >= 5 && roll < 0.3) { // piliers
        m.set(r.x + 1, r.y + 1, TILE.WALL); m.set(r.x + r.w - 2, r.y + r.h - 2, TILE.WALL);
      } else if (r.w >= 5 && r.h >= 4 && roll < 0.5) { // bassin
        m.set(r.cx, r.cy, TILE.WATER);
        if (Math.random() < 0.6) m.set(r.cx + 1, r.cy, TILE.WATER);
      }
      for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) {
        if (m.get(x, y) === TILE.FLOOR && Math.random() < 0.08) m.set(x, y, TILE.RUBBLE);
      }
    }

    // Vérifier la connectivité de toutes les salles
    const seen = new Array(w * h).fill(false);
    const stack = [m.idx(rooms[0].cx, rooms[0].cy)];
    if (!m.walkable(rooms[0].cx, rooms[0].cy)) continue;
    seen[stack[0]] = true;
    while (stack.length) {
      const i = stack.pop(), x = i % w, y = (i / w) | 0;
      for (const [dx, dy] of DIRS.slice(0, 4)) {
        const nx = x + dx, ny = y + dy, ni = m.idx(nx, ny);
        if (m.inside(nx, ny) && m.walkable(nx, ny) && !seen[ni]) { seen[ni] = true; stack.push(ni); }
      }
    }
    const roomCells = r => {
      const cells = [];
      for (let y = r.y; y < r.y + r.h; y++) for (let x = r.x; x < r.x + r.w; x++) if (m.walkable(x, y) && seen[m.idx(x, y)]) cells.push([x, y]);
      return cells;
    };
    if (rooms.some(r => roomCells(r).length < 4)) continue;
    for (let i = 0; i < w * h; i++) if (!seen[i] && m.walkable(i % w, (i / w) | 0)) m.t[i] = TILE.WALL;

    // Torches sur les murs dont la case du dessous est du sol
    m.torches = [];
    for (const r of rooms) {
      const n = 1 + rand(2);
      for (let k = 0; k < n; k++) {
        const x = r.x + rand(r.w), y = r.y - 1;
        if (m.get(x, y) === TILE.WALL && m.walkable(x, y + 1) && !m.torches.some(t => t.x === x && t.y === y)) m.torches.push({ x, y });
      }
    }
    m.rooms = rooms.map(r => ({ ...r, cells: roomCells(r) }));
    return m;
  }
  throw new Error('Impossible de générer un donjon');
}

// Champ de vision : cases visibles depuis une liste de points
function computeFOV(map, eyes, radius) {
  const vis = new Uint8Array(map.w * map.h);
  for (const e of eyes) {
    for (let y = Math.max(0, e.y - radius); y <= Math.min(map.h - 1, e.y + radius); y++) {
      for (let x = Math.max(0, e.x - radius); x <= Math.min(map.w - 1, e.x + radius); x++) {
        const i = map.idx(x, y);
        if (vis[i]) continue;
        if ((x - e.x) ** 2 + (y - e.y) ** 2 > radius * radius + 1) continue;
        if (hasLOS(map, e.x, e.y, x, y)) vis[i] = 1;
      }
    }
  }
  return vis;
}

// --- Géométrie --------------------------------------------------------------
// Distance "grille" façon D&D 5e : une diagonale compte pour 1 case.
function dist(ax, ay, bx, by) { return Math.max(Math.abs(ax - bx), Math.abs(ay - by)); }
function distU(a, b) { return dist(a.x, a.y, b.x, b.y); }

function hasLOS(map, ax, ay, bx, by) {
  const steps = Math.max(Math.abs(bx - ax), Math.abs(by - ay)) * 6;
  for (let i = 1; i < steps; i++) {
    const t = i / steps;
    const cx = Math.floor(ax + 0.5 + (bx - ax) * t), cy = Math.floor(ay + 0.5 + (by - ay) * t);
    if ((cx === ax && cy === ay) || (cx === bx && cy === by)) continue;
    if (map.blocksSight(cx, cy)) return false;
  }
  return true;
}

// Dijkstra : coût de déplacement depuis la position d'une unité.
// On peut traverser les alliés mais pas les ennemis.
function computeReach(unit, units, map, maxCost = Infinity, allowed = null) {
  const N = map.w * map.h;
  const d = new Array(N).fill(Infinity), prev = new Array(N).fill(-1), done = new Array(N).fill(false);
  const blocked = new Set();
  for (const o of units) if (!o.dead && o.hp > 0 && o.side !== unit.side) blocked.add(map.idx(o.x, o.y));
  const start = map.idx(unit.x, unit.y);
  d[start] = 0;
  for (;;) {
    let best = -1, bd = Infinity;
    for (let i = 0; i < N; i++) if (!done[i] && d[i] < bd) { bd = d[i]; best = i; }
    if (best < 0 || bd > maxCost) break;
    done[best] = true;
    const bx = best % map.w, by = (best / map.w) | 0;
    for (const [dx, dy] of DIRS) {
      const nx = bx + dx, ny = by + dy;
      if (!map.walkable(nx, ny)) continue;
      if (allowed && !allowed[map.idx(nx, ny)]) continue;
      if (dx && dy && (!map.walkable(bx + dx, by) || !map.walkable(bx, by + dy))) continue; // pas de coupe de coin
      const ni = map.idx(nx, ny);
      if (blocked.has(ni)) continue;
      const nd = bd + map.cost(nx, ny);
      if (nd < d[ni]) { d[ni] = nd; prev[ni] = best; }
    }
  }
  return { dist: d, prev, start };
}

function pathTo(reach, idx) {
  const path = [];
  while (idx !== reach.start && idx !== -1) { path.push(idx); idx = reach.prev[idx]; }
  return idx === -1 ? null : path.reverse();
}
