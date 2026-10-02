'use strict';

// ---------------------------------------------------------------------------
// Rendu : un canvas "pixel art" basse résolution (tuiles, sprites)
// + un canvas haute résolution par-dessus (lumière, surbrillances, textes)
// ---------------------------------------------------------------------------
const R = { px: null, pctx: null, fx: null, fctx: null, light: null, lctx: null, cell: 48, dpr: 1 };
const FACING = { loup: -1 }; // sens par défaut des sprites (1 = vers la droite)

function initRender() {
  buildSprites();
  R.px = document.getElementById('board');
  R.pctx = R.px.getContext('2d');
  R.fx = document.getElementById('fx');
  R.fctx = R.fx.getContext('2d');
  R.light = makeCanvas(1, 1);
  R.lctx = R.light.getContext('2d');
  window.addEventListener('resize', resizeBoard);
  requestAnimationFrame(draw);
}

function resizeBoard() {
  if (!G.map) return;
  const wrap = document.getElementById('board-wrap');
  const w = wrap.clientWidth - 16, h = wrap.clientHeight - 16;
  const cell = Math.max(16, Math.floor(Math.min(w / G.map.w, h / G.map.h)));
  R.cell = cell;
  R.dpr = window.devicePixelRatio || 1;
  R.px.width = G.map.w * PX; R.px.height = G.map.h * PX;
  R.fx.width = G.map.w * cell * R.dpr; R.fx.height = G.map.h * cell * R.dpr;
  for (const c of [R.px, R.fx]) { c.style.width = G.map.w * cell + 'px'; c.style.height = G.map.h * cell + 'px'; }
  document.getElementById('board-stack').style.width = G.map.w * cell + 'px';
  document.getElementById('board-stack').style.height = G.map.h * cell + 'px';
  R.light.width = G.map.w; R.light.height = G.map.h;
}

function draw(now) {
  requestAnimationFrame(draw);
  if (!G.map || !G.explored) return;
  const stack = document.getElementById('board-stack');
  if (G.shake > 0.2) {
    stack.style.transform = `translate(${(Math.random() - 0.5) * G.shake}px,${(Math.random() - 0.5) * G.shake}px)`;
    G.shake *= 0.88;
  } else if (G.shake) { G.shake = 0; stack.style.transform = ''; }

  drawPixels(now);
  const ctx = R.fctx;
  ctx.setTransform(R.dpr, 0, 0, R.dpr, 0, 0);
  ctx.clearRect(0, 0, G.map.w * R.cell, G.map.h * R.cell);
  drawLighting(ctx, now);
  drawHighlights(ctx, now);
  drawUnitOverlays(ctx, now);
  drawEffects(ctx, now);
  drawParticles(ctx, now);
  drawFloaters(ctx, now);
}

// --- Couche pixel art --------------------------------------------------------
function drawPixels(now) {
  const ctx = R.pctx, m = G.map;
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = '#000';
  ctx.fillRect(0, 0, R.px.width, R.px.height);
  const wf = Math.floor(now / 500) % 2;
  for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) {
    const i = m.idx(x, y);
    if (!G.explored[i]) continue;
    const t = m.t[i], px = x * PX, py = y * PX;
    if (t === TILE.WALL) {
      const below = m.get(x, y + 1);
      ctx.drawImage(below !== TILE.WALL && y + 1 < m.h ? TILES.wallFace[(m.deco[i] * 2) | 0] : TILES.wallTop, px, py);
      continue;
    }
    ctx.drawImage(TILES.floor[(m.deco[i] * 4) | 0], px, py);
    if (t === TILE.RUBBLE) ctx.drawImage(TILES.rubble, px, py);
    if (t === TILE.WATER) ctx.drawImage(TILES.water[(wf + ((m.deco[i] * 2) | 0)) % 2], px, py);
    // ombre portée sous un mur
    if (m.get(x, y - 1) === TILE.WALL) { ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(px, py, PX, 3); }
  }
  for (const t of m.torches) {
    if (!G.explored[m.idx(t.x, t.y)]) continue;
    ctx.drawImage(TILES.torch[Math.floor(now / 140 + t.x) % 3], t.x * PX, t.y * PX);
  }

  // Unités (triées par profondeur)
  const list = G.units.filter(u => !u.dead && (u.side === 'hero' || isVisible(u.x, u.y))).sort((a, b) => a.ry - b.ry);
  for (const u of list) {
    const spr = SPR[u.sprite];
    if (!spr) continue;
    const size = u.boss ? 24 : PX;
    const bob = u.hp > 0 ? Math.round(Math.sin(now / 260 + u.id * 1.7) * 0.6) : 0;
    const cx = Math.round(u.rx * PX + PX / 2), by = Math.round(u.ry * PX + PX);
    // ombre
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.fillRect(cx - size * 0.3, by - 2, size * 0.6, 2);
    ctx.fillStyle = u.side === 'hero' ? 'rgba(95,211,141,0.55)' : (u.elite ? 'rgba(200,90,255,0.7)' : 'rgba(224,80,80,0.55)');
    ctx.fillRect(cx - size * 0.3 + 1, by - 1, size * 0.6 - 2, 1);

    ctx.save();
    ctx.translate(cx, by - size + bob);
    const flip = (u.face || 1) !== (FACING[u.sprite] || 1);
    if (flip) { ctx.scale(-1, 1); }
    const ox = -size / 2;
    if (u.hp <= 0) {
      ctx.globalAlpha = 0.45; // héros inconscient : écrasé au sol
      ctx.drawImage(spr.img, ox, size / 2, size, size / 2);
    } else {
      ctx.drawImage(spr.img, ox, 0, size, size);
      const f = now - (u.flash || 0);
      if (f < 160) { ctx.globalAlpha = 1 - f / 160; ctx.drawImage(spr.white, ox, 0, size, size); }
    }
    ctx.restore();
  }
}

// --- Lumière et brouillard ----------------------------------------------------
function drawLighting(ctx, now) {
  const m = G.map, c = R.cell, l = R.lctx;
  const img = l.createImageData(m.w, m.h);
  const heroes = heroesAlive();
  const torches = m.torches;
  for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) {
    const i = m.idx(x, y);
    let a;
    if (!G.explored[i]) a = 1;
    else if (!G.vis[i]) a = 0.68;
    else {
      let d = Infinity;
      for (const h of heroes) d = Math.min(d, Math.hypot(h.x - x, h.y - y));
      a = Math.min(1, Math.max(0, (d - 2) / (SIGHT - 2))) * 0.5;
      for (const t of torches) {
        const td = Math.hypot(t.x - x, t.y + 1 - y);
        if (td < 3.5) a -= (3.5 - td) * 0.09;
      }
      a = Math.max(0, a);
    }
    img.data[i * 4 + 3] = Math.round(a * 255);
  }
  l.putImageData(img, 0, 0);
  ctx.save();
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(R.light, 0, 0, m.w * c, m.h * c);
  // Halo chaud des torches
  ctx.globalCompositeOperation = 'lighter';
  for (const t of torches) {
    if (!G.vis[m.idx(t.x, t.y)] && !G.vis[m.idx(t.x, t.y + 1)]) continue;
    const fl = 0.85 + Math.sin(now / 90 + t.x * 3) * 0.08 + Math.sin(now / 37 + t.y) * 0.05;
    const gx = (t.x + 0.5) * c, gy = (t.y + 0.6) * c, r = c * 3 * fl;
    const g = ctx.createRadialGradient(gx, gy, 0, gx, gy, r);
    g.addColorStop(0, 'rgba(255,150,60,0.22)');
    g.addColorStop(1, 'rgba(255,120,40,0)');
    ctx.fillStyle = g;
    ctx.fillRect(gx - r, gy - r, r * 2, r * 2);
  }
  ctx.restore();
}

// --- Surbrillances ----------------------------------------------------------
function cellRect(ctx, c, x, y, fill, stroke) {
  ctx.fillStyle = fill;
  ctx.fillRect(x * c + 1, y * c + 1, c - 2, c - 2);
  if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = 1.5; ctx.strokeRect(x * c + 1.5, y * c + 1.5, c - 3, c - 3); }
}

function drawHighlights(ctx, now) {
  const u = current(), m = G.map, c = R.cell;
  if (!u || u.side !== 'hero' || G.busy || G.over) return;
  const pulse = 0.5 + 0.5 * Math.sin(now / 250);

  if (G.ability) {
    const ab = G.ability, range = rangeOf(u, ab), rad = radiusOf(u, ab);
    for (let y = 0; y < m.h; y++) for (let x = 0; x < m.w; x++) {
      if (m.get(x, y) === TILE.WALL || !G.explored[m.idx(x, y)]) continue;
      if (isValidTarget(u, ab, x, y)) {
        const t = unitAt(x, y);
        if (t) cellRect(ctx, c, x, y, ab.type === 'heal' ? `rgba(90,230,140,${0.25 + pulse * 0.2})` : `rgba(255,70,60,${0.25 + pulse * 0.2})`);
        else cellRect(ctx, c, x, y, ab.type === 'teleport' ? 'rgba(150,110,220,0.25)' : 'rgba(255,150,60,0.14)');
      } else if (dist(u.x, u.y, x, y) <= range && isVisible(x, y)) {
        cellRect(ctx, c, x, y, 'rgba(255,150,60,0.06)');
      }
    }
    if (G.hover && (ab.type === 'aoe' || ab.type === 'aoeAttack') && isValidTarget(u, ab, G.hover.x, G.hover.y)) {
      for (let dy = -rad; dy <= rad; dy++) for (let dx = -rad; dx <= rad; dx++) {
        const x = G.hover.x + dx, y = G.hover.y + dy;
        if (m.inside(x, y) && m.get(x, y) !== TILE.WALL) cellRect(ctx, c, x, y, 'rgba(255,80,30,0.35)', 'rgba(255,160,80,0.8)');
      }
    }
    return;
  }

  if (G.reach && u.movesLeft > 0) {
    for (let i = 0; i < G.reach.dist.length; i++) {
      if (i === G.reach.start || G.reach.dist[i] > u.movesLeft) continue;
      const x = i % m.w, y = (i / m.w) | 0;
      if (unitAt(x, y)) continue;
      cellRect(ctx, c, x, y, 'rgba(70,150,255,0.16)');
    }
    if (G.hover) {
      const hi = m.idx(G.hover.x, G.hover.y);
      if (hi !== G.reach.start && G.reach.dist[hi] <= u.movesLeft && !unitAt(G.hover.x, G.hover.y)) {
        const path = pathTo(G.reach, hi);
        ctx.strokeStyle = 'rgba(160,210,255,0.95)'; ctx.lineWidth = 3; ctx.setLineDash([6, 5]);
        ctx.beginPath();
        ctx.moveTo((u.x + 0.5) * c, (u.y + 0.5) * c);
        for (const i of path) ctx.lineTo((i % m.w + 0.5) * c, (((i / m.w) | 0) + 0.5) * c);
        ctx.stroke(); ctx.setLineDash([]);
        cellRect(ctx, c, G.hover.x, G.hover.y, 'rgba(70,150,255,0.35)', 'rgba(160,210,255,1)');
        ctx.fillStyle = '#fff'; ctx.font = `bold ${Math.floor(c * 0.3)}px sans-serif`;
        ctx.textAlign = 'right'; ctx.textBaseline = 'top';
        ctx.fillText(G.reach.dist[hi], (G.hover.x + 1) * c - 4, G.hover.y * c + 3);
      }
    }
  }
}

// --- Barres de vie, états, unité active ---------------------------------------
function drawUnitOverlays(ctx, now) {
  const c = R.cell, active = current();
  for (const u of G.units) {
    if (u.dead || (u.side === 'monster' && !isVisible(u.x, u.y))) continue;
    const cx = (u.rx + 0.5) * c, top = u.ry * c - (u.boss ? c * 0.5 : 0);
    if (u === active && !G.over) {
      ctx.strokeStyle = '#ffd86b'; ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]); ctx.lineDashOffset = -now / 40;
      ctx.beginPath(); ctx.ellipse(cx, (u.ry + 0.95) * c, c * 0.42, c * 0.16, 0, 0, Math.PI * 2); ctx.stroke();
      ctx.setLineDash([]);
    }
    if (u.side === 'monster' && !u.awake) {
      ctx.font = `bold ${Math.floor(c * 0.3)}px sans-serif`; ctx.textAlign = 'center';
      ctx.fillStyle = '#cfd6ff';
      ctx.fillText('z', cx + c * 0.3, top + c * 0.1 - Math.abs(Math.sin(now / 600)) * 6);
    }
    // Barre de vie
    const bw = c * 0.75, bh = Math.max(3, c * 0.08), bx = cx - bw / 2, by = top + 1;
    ctx.fillStyle = 'rgba(0,0,0,0.8)'; ctx.fillRect(bx - 1, by - 1, bw + 2, bh + 2);
    const ratio = u.hp / u.maxHp;
    ctx.fillStyle = u.side === 'hero' ? (ratio > 0.5 ? '#4cc36b' : ratio > 0.25 ? '#e0b030' : '#d94040') : (u.elite ? '#c86bff' : '#d94a4a');
    ctx.fillRect(bx, by, bw * ratio, bh);
    // États
    const st = Object.keys(u.status || {});
    if (st.length) {
      ctx.font = `${Math.floor(c * 0.26)}px sans-serif`; ctx.textAlign = 'left'; ctx.textBaseline = 'top';
      st.forEach((k, i) => ctx.fillText(STATUS[k].icon, bx + i * c * 0.27, by + bh + 2));
    }
    if (u.elite || u.boss) {
      ctx.font = `${Math.floor(c * 0.28)}px sans-serif`; ctx.textAlign = 'center'; ctx.textBaseline = 'bottom';
      ctx.fillText(u.boss ? '👑' : '⭐', cx, by - 1);
    }
  }
}

// --- Effets -----------------------------------------------------------------
function drawEffects(ctx, now) {
  const c = R.cell;
  G.effects = G.effects.filter(e => now - e.t0 < e.dur);
  for (const e of G.effects) {
    const t = (now - e.t0) / e.dur;
    if (e.type === 'bolt') {
      const p = k => [(e.fx + (e.tx - e.fx) * k + 0.5) * c, (e.fy + (e.ty - e.fy) * k + 0.5) * c];
      const [x, y] = p(t), [tx, ty] = p(Math.max(0, t - 0.18));
      ctx.strokeStyle = e.color; ctx.lineWidth = 3; ctx.globalAlpha = 0.6;
      ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(x, y); ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = e.color; ctx.shadowColor = e.color; ctx.shadowBlur = 14;
      ctx.beginPath(); ctx.arc(x, y, c * 0.1, 0, Math.PI * 2); ctx.fill();
      ctx.shadowBlur = 0;
      if (Math.random() < 0.5) G.particles.push({ x: x / c, y: y / c, vx: 0, vy: 0, g: 0, life: 250, t0: now, color: e.color });
    } else if (e.type === 'boom') {
      const maxR = (e.r + 0.5) * c;
      ctx.globalAlpha = (1 - t) * 0.8;
      ctx.fillStyle = e.color;
      ctx.beginPath(); ctx.arc((e.x + 0.5) * c, (e.y + 0.5) * c, maxR * (0.3 + 0.7 * t), 0, Math.PI * 2); ctx.fill();
      ctx.globalAlpha = 1;
    }
  }
}

function drawParticles(ctx, now) {
  const c = R.cell, s = Math.max(2, c / 16 * 1.5);
  G.particles = G.particles.filter(p => now - p.t0 < p.life);
  for (const p of G.particles) {
    p.x += p.vx; p.y += p.vy; p.vy += p.g;
    ctx.globalAlpha = 1 - (now - p.t0) / p.life;
    ctx.fillStyle = p.color;
    ctx.fillRect(Math.round(p.x * c - s / 2), Math.round(p.y * c - s / 2), s, s);
  }
  ctx.globalAlpha = 1;
}

function drawFloaters(ctx, now) {
  const c = R.cell;
  G.floaters = G.floaters.filter(f => now - f.t0 < 1200);
  for (const f of G.floaters) {
    const t = (now - f.t0) / 1200;
    ctx.globalAlpha = 1 - t * t;
    ctx.font = `bold ${Math.floor(c * 0.4)}px "Pixelify Sans", sans-serif`;
    ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
    const x = (f.x + 0.5) * c, y = (f.y + 0.1) * c - t * c * 0.7;
    ctx.lineWidth = 4; ctx.strokeStyle = 'rgba(0,0,0,0.85)';
    ctx.strokeText(f.text, x, y);
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, x, y);
    ctx.globalAlpha = 1;
  }
}

function cellFromEvent(ev) {
  const rect = R.fx.getBoundingClientRect();
  const x = Math.floor((ev.clientX - rect.left) / R.cell), y = Math.floor((ev.clientY - rect.top) / R.cell);
  return G.map && G.map.inside(x, y) ? { x, y } : null;
}
