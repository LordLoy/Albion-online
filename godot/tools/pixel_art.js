'use strict';
// ---------------------------------------------------------------------------
// Dessins pixel art supplémentaires pour la version Godot.
// Chargé dans un navigateur APRÈS js/sprites.js (même palette, mêmes outils).
// Chaque caractère = un pixel, '.' = transparent. 'C' = couleur variable (potions).
// ---------------------------------------------------------------------------

const EXTRA_SPRITES = {
  diablotin: [
    '................',
    '................',
    '...kk......kk...',
    '...kYk....kYk...',
    '....kYkkkkYk....',
    '...krrrrrrrrk...',
    '.kkkryrrrryrkkk.',
    'kRRkrrrkkrrrkRRk',
    'kRRRkrwrrwrkRRRk',
    '.kRRkkrrrrkkRRk.',
    '..kk.krrrrk.kk..',
    '.....kRrrRk.....',
    '.....krkkrk..k..',
    '.....krk.krkkrk.',
    '.....kkk.kkk.k..',
    '................',
  ],
  elementaire: [
    '.......k........',
    '......kyk...k...',
    '......kyyk.kyk..',
    '.k...kyooyk.kyk.',
    'kyk.kyooooyk.ok.',
    'kyokyooooooykok.',
    '.koyooxooxooyok.',
    '.kooooxooxoooRk.',
    '.kRoooooooooRRk.',
    '..kRoooyyoooRk..',
    '..kRRooyyooRRk..',
    '...kRRooooRRk...',
    '....kRRooRRk....',
    '.....kRRRRk.....',
    '....kRkRRkRk....',
    '.....k.kk.k.....',
  ],
  cultiste: [
    '................',
    '......kkkk......',
    '.....kRRRRk.....',
    '....kRRRRRRk....',
    '....kRyxxyRk....',
    '....kRxxxxRk....',
    '.....kRRRRk.....',
    '...kkRRRRRRkk...',
    '..kRRRkpPkRRRk..',
    '..kRRkpppkkRRk..',
    '..kRRskPkksRRk..',
    '..kRRRRRRRRRRk..',
    '...kRRRRRRRRk...',
    '...kRYRRRRYRk...',
    '...kRRRRRRRRk...',
    '....kkkkkkkk....',
  ],
  salamandre: [
    '................',
    '................',
    '................',
    '................',
    '................',
    '..kkkk..........',
    '.koooyk.........',
    'kooxoooykkkk....',
    'kwkooooooooook..',
    '.kkkoRoRoRooook.',
    '...kRooooooRRook',
    '...kok.kok.kok..',
    '...kk..kk..kk...',
    '................',
    '................',
    '................',
  ],
  dragon: [
    '.k............k.',
    'kRk..k....k..kRk',
    'kRRk.kYkkYk.kRRk',
    'kRrRkkrrrrkkRrRk',
    'kRrrkryrryrkrrRk',
    'kRrrkrrrrrrkrrRk',
    '.kRrkkrRRrkkrRk.',
    '..kRkrwrrwrkRk..',
    '...kkrrrrrrkk...',
    '...krryyyyrrk...',
    '..krrryyyyrrrk..',
    '..krRryyyyrRrk..',
    '..krrRyyyyRrrk.k',
    '...kRrrrrrrRkkRk',
    '...kRk.kk.kRk.k.',
    '...kkk....kkk...',
  ],
  phylactere: [
    '................',
    '.......kk.......',
    '......kpPk......',
    '.....kpwpPk.....',
    '.....kppPPk.....',
    '....kpwppPPk....',
    '....kppppPPk....',
    '....kpppPPPk....',
    '.....kppPPk.....',
    '.....kpPPPk.....',
    '......kPPk......',
    '.....kkkkkk.....',
    '....kgGGGGgk....',
    '...kgGGGGGGgk...',
    '...kGGGGGGGGk...',
    '....kkkkkkkk....',
  ],
};

const ICONS = {
  arme: [
    '................',
    '...........kwgk.',
    '..........kwgk..',
    '.........kwgk...',
    '........kwgk....',
    '.......kwgk.....',
    '......kwgk......',
    '..kk.kwgk.......',
    '...kykgk........',
    '....kyk.........',
    '...knkyk........',
    '..knk..kk.......',
    '.kNk............',
    'kkk.............',
    '................',
    '................',
  ],
  armure: [
    '................',
    '................',
    '...kkk....kkk...',
    '..kgggkkkkgggk..',
    '..kgwgggggggGk..',
    '..kggggGGgggGk..',
    '...kgggGGgggk...',
    '...kggggggggk...',
    '...kgGggggGgk...',
    '...kggggggggk...',
    '...kGggggggGk...',
    '....kkkkkkkk....',
    '................',
    '................',
    '................',
    '................',
  ],
  accessoire: [
    '................',
    '...kk......kk...',
    '....kk....kk....',
    '.....kk..kk.....',
    '......kkkk......',
    '.....kyyyyk.....',
    '....kyrrrryk....',
    '....kyrwrryk....',
    '....kyrrrryk....',
    '.....kyyyyk.....',
    '......kkkk......',
    '................',
    '................',
    '................',
    '................',
    '................',
  ],
  potion: [
    '................',
    '................',
    '......kkkk......',
    '......knnk......',
    '......kwwk......',
    '.....kwwwwk.....',
    '....kwCCCCwk....',
    '...kCCwCCCCCk...',
    '...kCwCCCCCCk...',
    '...kCCCCCCCCk...',
    '...kCCCCCCCCk...',
    '....kCCCCCCk....',
    '.....kkkkkk.....',
    '................',
    '................',
    '................',
  ],
  pouvoir: [
    '................',
    '................',
    '................',
    '...kkkkkkkkkk...',
    '..kllllllllllk..',
    '...klLLLLLlLk...',
    '...kllllllllk...',
    '...klLLLLlllk...',
    '...kllllllllk...',
    '...klLLLLLLlk...',
    '..kllllllllllk..',
    '...kkkkkkkkkk...',
    '................',
    '................',
    '................',
    '................',
  ],
};

const POTION_COLORS = { soin: 'r', feu: 'o', vitesse: 'b', antidote: 'e', force: 'p' };

function paintRows(rows, map = {}) {
  const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
  rows.forEach((row, y) => {
    for (let x = 0; x < PX; x++) {
      let ch = row[x];
      if (!ch || ch === '.') continue;
      if (map[ch]) ch = map[ch];
      ctx.fillStyle = PALETTE[ch] || '#ff00ff';
      ctx.fillRect(x, y, 1, 1);
    }
  });
  return c;
}

// --- Tuiles des biomes --------------------------------------------------------
function noiseTile(base, seed, spots, extra) {
  const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(seed);
  ctx.fillStyle = base; ctx.fillRect(0, 0, PX, PX);
  for (let i = 0; i < spots.n; i++) {
    ctx.fillStyle = spots.colors[(rnd() * spots.colors.length) | 0];
    ctx.fillRect((rnd() * PX) | 0, (rnd() * PX) | 0, spots.w || 1, spots.h || 1);
  }
  if (extra) extra(ctx, rnd);
  return c;
}

function buildBiomeTiles() {
  const T = {};
  // ---- Forêt ----
  for (let v = 0; v < 4; v++) {
    T['grass_' + v] = noiseTile('#3e6b34', 101 + v * 7, { n: 40, colors: ['#4c7d3e', '#335a2b', '#5a8c44', '#2f5228'], h: 2 }, (ctx, rnd) => {
      if (v === 3) { // fleurs
        for (const [x, y, col] of [[3, 4, '#f0d060'], [11, 9, '#e87090'], [7, 13, '#f0f0f0']]) { ctx.fillStyle = col; ctx.fillRect(x, y, 1, 1); }
      }
    });
  }
  T.tree = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    ctx.drawImage(T.grass_0, 0, 0);
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.fillRect(3, 12, 11, 3);
    ctx.fillStyle = '#4a3020'; ctx.fillRect(7, 10, 3, 5);
    const blobs = [[8, 6, 6, '#1f4a22'], [5, 7, 4, '#245226'], [11, 7, 4, '#245226'], [8, 4, 4, '#2d6630'], [6, 4, 2, '#3f8040'], [10, 5, 2, '#3f8040']];
    for (const [x, y, r, col] of blobs) { ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill(); }
    ctx.fillStyle = '#5aa050'; ctx.fillRect(6, 2, 2, 1); ctx.fillRect(9, 3, 1, 1);
    return c;
  })();
  T.bush = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    for (const [x, y, r, col] of [[5, 10, 3, '#2a5a2a'], [10, 11, 3, '#2a5a2a'], [8, 8, 3, '#346e32'], [7, 7, 1, '#4f9a48']]) {
      ctx.fillStyle = col; ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
    }
    ctx.fillStyle = '#c03040'; ctx.fillRect(5, 9, 1, 1); ctx.fillRect(10, 10, 1, 1);
    return c;
  })();
  T.bridge = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    ctx.drawImage(TILES.water[0], 0, 0);
    for (let y = 0; y < PX; y += 4) {
      ctx.fillStyle = '#7a5530'; ctx.fillRect(1, y, 14, 3);
      ctx.fillStyle = '#9a7040'; ctx.fillRect(1, y, 14, 1);
      ctx.fillStyle = '#3a2410'; ctx.fillRect(1, y + 3, 14, 1);
    }
    ctx.fillStyle = '#4a3018'; ctx.fillRect(0, 0, 1, PX); ctx.fillRect(15, 0, 1, PX);
    return c;
  })();
  T.river = [0, 1].map(f => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    ctx.fillStyle = '#1d4a52'; ctx.fillRect(0, 0, PX, PX);
    ctx.fillStyle = '#2a6670';
    for (const [x, y] of [[2, 3], [9, 7], [4, 11], [12, 13]]) ctx.fillRect((x + f * 3) % 14, y, 3, 1);
    ctx.fillStyle = '#7fc8c0'; ctx.fillRect((6 + f * 4) % 14, 5, 2, 1);
    return c;
  });

  // ---- Volcan ----
  for (let v = 0; v < 4; v++) {
    T['basalt_' + v] = noiseTile('#352d31', 201 + v * 11, { n: 26, colors: ['#2a2327', '#40373b', '#2e272b'] }, (ctx, rnd) => {
      ctx.fillStyle = '#231d20';
      for (let i = 0; i < PX; i++) { ctx.fillRect(i, 0, 1, 1); ctx.fillRect(0, i, 1, 1); }
      if (v >= 2) { // fissure rougeoyante
        let x = 3 + ((rnd() * 8) | 0), y = 2;
        for (let i = 0; i < 10; i++) { ctx.fillStyle = i % 3 ? '#8a2a10' : '#d05010'; ctx.fillRect(x, y, 1, 1); x += rnd() < 0.5 ? 1 : -1; y += 1; x = Math.max(1, Math.min(14, x)); }
      }
    });
  }
  T.rock_top = noiseTile('#1a1416', 301, { n: 16, colors: ['#241c1f', '#120e10'], w: 2 });
  T.rock_face = [0, 1].map(v => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(311 + v);
    ctx.fillStyle = '#2a2023'; ctx.fillRect(0, 0, PX, PX);
    for (let x = 0; x < PX; x += 4) { // colonnes de basalte
      ctx.fillStyle = shadeHex('#4a3a3e', 0.8 + rnd() * 0.4); ctx.fillRect(x, (rnd() * 3) | 0, 3, PX);
      ctx.fillStyle = 'rgba(255,255,255,0.08)'; ctx.fillRect(x, 0, 1, PX);
    }
    ctx.fillStyle = 'rgba(0,0,0,0.4)'; ctx.fillRect(0, PX - 2, PX, 2);
    return c;
  });
  T.ash = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(333);
    for (let i = 0; i < 30; i++) { ctx.fillStyle = rnd() < 0.5 ? '#6a6266' : '#857c80'; ctx.fillRect((rnd() * 14 + 1) | 0, (rnd() * 14 + 1) | 0, 2, 1); }
    ctx.fillStyle = '#e06020'; ctx.fillRect(6, 8, 1, 1);
    return c;
  })();
  T.lava = [0, 1].map(f => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(401 + f);
    ctx.fillStyle = '#c03810'; ctx.fillRect(0, 0, PX, PX);
    for (let i = 0; i < 14; i++) { ctx.fillStyle = rnd() < 0.5 ? '#e86018' : '#a02808'; ctx.fillRect((rnd() * 14) | 0, (rnd() * 15) | 0, 3, 2); }
    ctx.fillStyle = '#ffc040';
    for (const [x, y] of [[3, 4], [10, 9], [6, 13]]) ctx.fillRect((x + f * 2) % 15, y, 2, 1);
    ctx.fillStyle = '#fff0a0'; ctx.fillRect((8 + f * 3) % 15, 6, 1, 1);
    return c;
  });
  return T;
}
