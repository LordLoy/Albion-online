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

function generateMap(w, h) {
  for (let attempt = 0; attempt < 100; attempt++) {
    const m = new GameMap(w, h);
    for (let x = 0; x < w; x++) { m.set(x, 0, TILE.WALL); m.set(x, h - 1, TILE.WALL); }
    for (let y = 0; y < h; y++) { m.set(0, y, TILE.WALL); m.set(w - 1, y, TILE.WALL); }

    // Murs en segments
    const segs = 5 + rand(4);
    for (let s = 0; s < segs; s++) {
      const horiz = Math.random() < 0.5, len = 2 + rand(4);
      const x0 = 4 + rand(w - 8), y0 = 1 + rand(h - 2);
      for (let i = 0; i < len; i++) m.set(x0 + (horiz ? i : 0), y0 + (horiz ? 0 : i), TILE.WALL);
    }
    // Piliers 2×2
    const pillars = 2 + rand(3);
    for (let p = 0; p < pillars; p++) {
      const x = 4 + rand(w - 9), y = 2 + rand(h - 5);
      m.set(x, y, TILE.WALL); m.set(x + 1, y, TILE.WALL); m.set(x, y + 1, TILE.WALL); m.set(x + 1, y + 1, TILE.WALL);
    }
    // Bassins d'eau (bloquent le passage mais pas la vue)
    const pools = rand(3);
    for (let p = 0; p < pools; p++) {
      const cx = 5 + rand(w - 10), cy = 2 + rand(h - 4);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (m.get(cx + dx, cy + dy) === TILE.FLOOR && (dx === 0 && dy === 0 || Math.random() < 0.6)) m.set(cx + dx, cy + dy, TILE.WATER);
      }
    }
    // Gravats (terrain difficile : coûte 2 cases)
    for (let y = 1; y < h - 1; y++) for (let x = 3; x < w - 3; x++) {
      if (m.get(x, y) === TILE.FLOOR && Math.random() < 0.09) m.set(x, y, TILE.RUBBLE);
    }
    // Zones de départ dégagées
    for (let y = 1; y < h - 1; y++) for (const x of [1, 2, w - 3, w - 2]) m.set(x, y, TILE.FLOOR);

    // Connectivité : tout ce qui n'est pas atteignable depuis la gauche devient un mur
    const seen = new Array(w * h).fill(false);
    const stack = [m.idx(1, 1)]; seen[stack[0]] = true;
    while (stack.length) {
      const i = stack.pop(), x = i % w, y = (i / w) | 0;
      for (const [dx, dy] of DIRS.slice(0, 4)) {
        const nx = x + dx, ny = y + dy, ni = m.idx(nx, ny);
        if (m.walkable(nx, ny) && !seen[ni]) { seen[ni] = true; stack.push(ni); }
      }
    }
    let ok = true;
    for (let y = 1; y < h - 1; y++) if (!seen[m.idx(w - 2, y)]) ok = false;
    if (!ok) continue;
    for (let i = 0; i < w * h; i++) {
      if (!seen[i] && (m.t[i] === TILE.FLOOR || m.t[i] === TILE.RUBBLE)) m.t[i] = TILE.WALL;
    }
    return m;
  }
  throw new Error('Impossible de générer une carte');
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
function computeReach(unit, units, map, maxCost = Infinity) {
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
