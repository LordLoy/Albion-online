'use strict';

// ---------------------------------------------------------------------------
// Rendu du plateau (canvas)
// ---------------------------------------------------------------------------
const R = { canvas: null, ctx: null, cell: 48 };

function initRender() {
  R.canvas = document.getElementById('board');
  R.ctx = R.canvas.getContext('2d');
  window.addEventListener('resize', resizeBoard);
  requestAnimationFrame(draw);
}

function resizeBoard() {
  if (!G.map) return;
  const wrap = document.getElementById('board-wrap');
  const w = wrap.clientWidth - 16, h = wrap.clientHeight - 16;
  const cell = Math.max(22, Math.floor(Math.min(w / G.map.w, h / G.map.h)));
  R.cell = cell;
  const dpr = window.devicePixelRatio || 1;
  R.canvas.width = G.map.w * cell * dpr;
  R.canvas.height = G.map.h * cell * dpr;
  R.canvas.style.width = G.map.w * cell + 'px';
  R.canvas.style.height = G.map.h * cell + 'px';
  R.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

function draw(now) {
  requestAnimationFrame(draw);
  if (!G.map) return;
  const ctx = R.ctx, c = R.cell, m = G.map;
  ctx.clearRect(0, 0, m.w * c, m.h * c);

  drawTiles(ctx, c, m, now);
  drawHighlights(ctx, c, m, now);
  drawUnits(ctx, c, now);
  drawEffects(ctx, c, now);
  drawFloaters(ctx, c, now);
}

function drawTiles(ctx, c, m, now) {
  for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) {
    const t = m.get(x, y), r = m.deco[m.idx(x, y)];
    const px = x * c, py = y * c;
    if (t === TILE.WALL) {
      ctx.fillStyle = '#1b1915';
      ctx.fillRect(px, py, c, c);
      // briques si un sol est en dessous (effet de façade)
      if (m.get(x, y + 1) !== TILE.WALL) {
        ctx.fillStyle = '#2c2822';
        ctx.fillRect(px, py + c * 0.55, c, c * 0.45);
        ctx.strokeStyle = '#1b1915'; ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.moveTo(px, py + c * 0.77); ctx.lineTo(px + c, py + c * 0.77);
        ctx.moveTo(px + c * 0.5, py + c * 0.55); ctx.lineTo(px + c * 0.5, py + c * 0.77);
        ctx.moveTo(px + c * 0.25, py + c * 0.77); ctx.lineTo(px + c * 0.25, py + c);
        ctx.moveTo(px + c * 0.75, py + c * 0.77); ctx.lineTo(px + c * 0.75, py + c);
        ctx.stroke();
      }
      continue;
    }
    // sol en dalles
    const shade = 52 + Math.floor(r * 10);
    ctx.fillStyle = `rgb(${shade},${shade - 3},${shade - 8})`;
    ctx.fillRect(px, py, c, c);
    ctx.fillStyle = 'rgba(255,255,255,0.025)';
    ctx.fillRect(px + 2, py + 2, c - 4, c * 0.3);

    if (t === TILE.RUBBLE) {
      ctx.fillStyle = '#6e5a43';
      for (let k = 0; k < 5; k++) {
        const a = (r * 97 + k * 37) % 1, b = (r * 53 + k * 71) % 1;
        ctx.beginPath();
        ctx.arc(px + c * (0.2 + a * 0.6), py + c * (0.2 + b * 0.6), c * (0.06 + ((a + b) % 1) * 0.06), 0, Math.PI * 2);
        ctx.fill();
      }
    } else if (t === TILE.WATER) {
      ctx.fillStyle = '#1d4560';
      ctx.fillRect(px, py, c, c);
      ctx.strokeStyle = 'rgba(160,210,255,0.35)'; ctx.lineWidth = 1.5;
      for (let k = 0; k < 2; k++) {
        const yy = py + c * (0.35 + k * 0.3), off = Math.sin(now / 600 + r * 6 + k) * c * 0.08;
        ctx.beginPath();
        ctx.moveTo(px + c * 0.15 + off, yy);
        ctx.quadraticCurveTo(px + c * 0.5 + off, yy - c * 0.1, px + c * 0.85 + off, yy);
        ctx.stroke();
      }
    }
  }
  // grille
  ctx.strokeStyle = 'rgba(0,0,0,0.35)'; ctx.lineWidth = 1;
  ctx.beginPath();
  for (let x = 0; x <= m.w; x++) { ctx.moveTo(x * c + 0.5, 0); ctx.lineTo(x * c + 0.5, m.h * c); }
  for (let y = 0; y <= m.h; y++) { ctx.moveTo(0, y * c + 0.5); ctx.lineTo(m.w * c, y * c + 0.5); }
  ctx.stroke();
}

function cellRect(ctx, c, x, y, fill, stroke) {
  ctx.fillStyle = fill;
  ctx.fillRect(x * c + 1, y * c + 1, c - 2, c - 2);
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1; ctx.strokeRect(x * c + 1.5, y * c + 1.5, c - 3, c - 3); }
}

function drawHighlights(ctx, c, m, now) {
  const u = current();
  if (!u || u.side !== 'hero' || G.busy || G.over) return;
  const pulse = 0.5 + 0.5 * Math.sin(now / 250);

  if (G.ability) {
    const ab = G.ability;
    // portée
    for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) {
      if (m.get(x, y) === TILE.WALL) continue;
      if (isValidTarget(u, ab, x, y)) {
        const t = unitAt(x, y);
        if (t) cellRect(ctx, c, x, y, ab.type === 'heal' ? `rgba(90,230,140,${0.25 + pulse * 0.2})` : `rgba(255,70,60,${0.25 + pulse * 0.2})`);
        else cellRect(ctx, c, x, y, ab.type === 'teleport' ? 'rgba(150,110,220,0.22)' : 'rgba(255,150,60,0.13)');
      } else if (inRange(u, x, y, ab.range)) {
        cellRect(ctx, c, x, y, 'rgba(255,150,60,0.07)');
      }
    }
    // zone d'effet survolée
    if (G.hover && (ab.type === 'aoe' || ab.type === 'aoeAttack') && isValidTarget(u, ab, G.hover.x, G.hover.y)) {
      for (let dy = -ab.radius; dy <= ab.radius; dy++) for (let dx = -ab.radius; dx <= ab.radius; dx++) {
        const x = G.hover.x + dx, y = G.hover.y + dy;
        if (m.inside(x, y) && m.get(x, y) !== TILE.WALL) cellRect(ctx, c, x, y, 'rgba(255,80,30,0.35)', 'rgba(255,160,80,0.8)');
      }
    }
    return;
  }

  // déplacement
  if (G.reach && u.movesLeft > 0) {
    for (let i = 0; i < G.reach.dist.length; i++) {
      if (i === G.reach.start || G.reach.dist[i] > u.movesLeft) continue;
      const x = i % m.w, y = (i / m.w) | 0;
      if (unitAt(x, y)) continue;
      cellRect(ctx, c, x, y, 'rgba(70,150,255,0.17)');
    }
    // chemin survolé
    if (G.hover) {
      const hi = m.idx(G.hover.x, G.hover.y);
      if (hi !== G.reach.start && G.reach.dist[hi] <= u.movesLeft && !unitAt(G.hover.x, G.hover.y)) {
        const path = pathTo(G.reach, hi);
        ctx.strokeStyle = 'rgba(140,200,255,0.9)'; ctx.lineWidth = 3; ctx.setLineDash([6, 5]);
        ctx.beginPath();
        ctx.moveTo((u.x + 0.5) * c, (u.y + 0.5) * c);
        for (const i of path) ctx.lineTo((i % m.w + 0.5) * c, (((i / m.w) | 0) + 0.5) * c);
        ctx.stroke(); ctx.setLineDash([]);
        cellRect(ctx, c, G.hover.x, G.hover.y, 'rgba(70,150,255,0.35)', 'rgba(140,200,255,1)');
        ctx.fillStyle = '#fff'; ctx.font = `bold ${Math.floor(c * 0.3)}px sans-serif`;
        ctx.textAlign = 'right'; ctx.textBaseline = 'top';
        ctx.fillText(G.reach.dist[hi], (G.hover.x + 1) * c - 4, G.hover.y * c + 3);
      }
    }
  }
}

function drawUnits(ctx, c, now) {
  const active = current();
  const list = G.units.filter(u => !u.dead).sort((a, b) => (a.hp > 0) - (b.hp > 0));
  for (const u of list) {
    const cx = (u.rx + 0.5) * c, cy = (u.ry + 0.5) * c;
    const rad = c * (u.boss ? 0.46 : 0.4);
    const down = u.hp <= 0;

    ctx.save();
    if (down) ctx.globalAlpha = 0.45;

    // ombre
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.beginPath(); ctx.ellipse(cx, cy + rad * 0.85, rad * 0.9, rad * 0.3, 0, 0, Math.PI * 2); ctx.fill();

    // indicateur du tour actif
    if (u === active && !G.over) {
      ctx.strokeStyle = '#ffd86b'; ctx.lineWidth = 3;
      ctx.setLineDash([8, 6]); ctx.lineDashOffset = -now / 40;
      ctx.beginPath(); ctx.arc(cx, cy, rad + 5, 0, Math.PI * 2); ctx.stroke();
      ctx.setLineDash([]);
    }

    // jeton
    const g = ctx.createRadialGradient(cx - rad * 0.3, cy - rad * 0.3, rad * 0.1, cx, cy, rad);
    g.addColorStop(0, lighten(u.color, 40));
    g.addColorStop(1, u.color);
    ctx.fillStyle = g;
    ctx.beginPath(); ctx.arc(cx, cy, rad, 0, Math.PI * 2); ctx.fill();
    ctx.lineWidth = 3;
    ctx.strokeStyle = u.side === 'hero' ? '#5fd38d' : '#e05050';
    ctx.stroke();

    ctx.font = `${Math.floor(rad * 1.05)}px "Segoe UI Emoji","Apple Color Emoji","Noto Color Emoji",sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    ctx.fillText(down ? '💤' : u.icon, cx, cy + 1);

    // barre de vie
    const bw = c * 0.8, bh = Math.max(4, c * 0.09), bx = cx - bw / 2, by = cy + rad + 2;
    ctx.fillStyle = '#111'; ctx.fillRect(bx - 1, by - 1, bw + 2, bh + 2);
    const ratio = u.hp / u.maxHp;
    ctx.fillStyle = ratio > 0.5 ? '#4cc36b' : ratio > 0.25 ? '#e0b030' : '#d94040';
    ctx.fillRect(bx, by, bw * ratio, bh);
    ctx.restore();
  }
}

function drawEffects(ctx, c, now) {
  G.effects = G.effects.filter(e => now - e.t0 < e.dur);
  for (const e of G.effects) {
    const t = (now - e.t0) / e.dur;
    if (e.type === 'bolt') {
      const x = (e.fx + (e.tx - e.fx) * t + 0.5) * c, y = (e.fy + (e.ty - e.fy) * t + 0.5) * c;
      const tx = (e.fx + (e.tx - e.fx) * Math.max(0, t - 0.15) + 0.5) * c, ty = (e.fy + (e.ty - e.fy) * Math.max(0, t - 0.15) + 0.5) * c;
      ctx.strokeStyle = e.color; ctx.lineWidth = 3; ctx.globalAlpha = 0.6;
      ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(x, y); ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = e.color;
      ctx.shadowColor = e.color; ctx.shadowBlur = 12;
      ctx.beginPath(); ctx.arc(x, y, c * 0.1, 0, Math.PI * 2); ctx.fill();
      ctx.shadowBlur = 0;
    } else if (e.type === 'boom') {
      const maxR = (e.r + 0.5) * c;
      ctx.globalAlpha = 1 - t;
      ctx.fillStyle = e.color;
      ctx.beginPath(); ctx.arc((e.x + 0.5) * c, (e.y + 0.5) * c, maxR * (0.3 + 0.7 * t), 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}

function drawFloaters(ctx, c, now) {
  G.floaters = G.floaters.filter(f => now - f.t0 < 1200);
  for (const f of G.floaters) {
    const t = (now - f.t0) / 1200;
    ctx.globalAlpha = 1 - t * t;
    ctx.font = `bold ${Math.floor(c * 0.38)}px sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const x = (f.x + 0.5) * c, y = (f.y + 0.1) * c - t * c * 0.7;
    ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(0,0,0,0.8)';
    ctx.strokeText(f.text, x, y);
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, x, y);
    ctx.globalAlpha = 1;
  }
}

function lighten(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const r = Math.min(255, (n >> 16) + amt), g = Math.min(255, ((n >> 8) & 255) + amt), b = Math.min(255, (n & 255) + amt);
  return `rgb(${r},${g},${b})`;
}

function cellFromEvent(ev) {
  const rect = R.canvas.getBoundingClientRect();
  const x = Math.floor((ev.clientX - rect.left) / R.cell), y = Math.floor((ev.clientY - rect.top) / R.cell);
  return G.map && G.map.inside(x, y) ? { x, y } : null;
}
