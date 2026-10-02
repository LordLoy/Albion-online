'use strict';

// ---------------------------------------------------------------------------
// Pixel art : sprites 16×16 dessinés à la main + tuiles générées
// Chaque caractère = un pixel, '.' = transparent.
// ---------------------------------------------------------------------------
const PX = 16; // taille d'une case en pixels "art"

const PALETTE = {
  k: '#1a1214', x: '#000000', w: '#f0ece0', g: '#a8a8b0', G: '#5c5c6a',
  s: '#e8b796', S: '#b67f62', r: '#c83c3c', R: '#7c2020', b: '#4a7ad8', B: '#2a3f80',
  p: '#8a5ad0', P: '#4e2c80', y: '#f0c040', Y: '#a07820', n: '#8a5a30', N: '#553418',
  e: '#6ab446', E: '#2f6a26', o: '#f08030', c: '#9fe0f0', l: '#e6dcb8', L: '#a89c78', h: '#5a3a24',
};

const SPRITE_DATA = {
  guerrier: [
    '................',
    '.....kkkkkk.....',
    '....kgwgggGk....',
    '....kggggggk....',
    '....kGkkkkGk....',
    '....kGskskGk....',
    '.....kssssk..kk.',
    '..kkkkGrrGkk.kwk',
    '.kbbbkgrrggkkwk.',
    '.kbyykgrrgGkkwk.',
    '.kbyykGrrGkkyyk.',
    '.kbbbkkRRkk.kk..',
    '..kkk.kGGk......',
    '......kGkGk.....',
    '.....kNk.kNk....',
    '.....kkk.kkk....',
  ],
  mage: [
    '........k.......',
    '.......kpk......',
    '......kppPk.....',
    '.....kpppPk..kk.',
    '....kppppppk.kck',
    '...kkyyyyyykkkck',
    '....kssssssk.knk',
    '....kskssksk.knk',
    '....kwsssswk.knk',
    '...kpkwwwwkpkknk',
    '..kppPkwwkPppsnk',
    '..kpppPPPPpppknk',
    '...kpppppppPk.nk',
    '...kPpppppPPk.nk',
    '....kkPkkPkk..kk',
    '.....kk..kk.....',
  ],
  rodeur: [
    '................',
    '......kkkk......',
    '.....kEeeek.....',
    '....kEeeeeek....',
    '....kEskskEk....',
    '....kEssssEk....',
    '.k...kEssEk.....',
    'kNk.kEeeeeEknNk.',
    'kNksskeeeekknNk.',
    'kNk.kEeeeeEknNk.',
    'kNk.knnnnnnk.k..',
    '.k..kEeeeeEk....',
    '....kEekkeEk....',
    '.....kNk.kNk....',
    '.....kNk.kNk....',
    '.....kkk.kkk....',
  ],
  clerc: [
    '................',
    '......kkkk......',
    '.....khhhhk.....',
    '....khsssshk....',
    '....kskssksk....',
    '....kssSSssk....',
    '.....kssssk..yy.',
    '...kkwwyywwkkyyk',
    '..kwwwyyyywwkn..',
    '..kwwwwyywwwsn..',
    '..kwwkwyywkwkn..',
    '...kwwwyywwwk...',
    '...kwwwwwwwwk...',
    '...kYwwwwwwYk...',
    '....kkkkkkkk....',
    '....kNk..kNk....',
  ],
  voleur: [
    '................',
    '......kkkk......',
    '.....kGGGGk.....',
    '....kGGGGGGk....',
    '....kGksskGk....',
    '....kGxxxxGk....',
    '.....kGGGGk.....',
    '..kkkGGGGGGkkk..',
    '.kgkGGnGGnGGkgk.',
    '.kgkGGGnnGGGkgk.',
    '.kwksGGGGGGskwk.',
    '..k.kGGGGGGk.k..',
    '....kGGkkGGk....',
    '.....kGk.kGk....',
    '.....kNk.kNk....',
    '.....kkk.kkk....',
  ],
  gobelin: [
    '................',
    '................',
    '.....kkkkkk.....',
    '.kk.keeeeeek.kk.',
    '.kekeyeeeyeekek.',
    '..kkeeEEEeekk...',
    '....keewweek....',
    '.....kkkkkk.....',
    '....knnNNnnk.kg.',
    '...keknnnnkekgk.',
    '...kkkNNNNkkekk.',
    '.....knnnnk.....',
    '.....keekeek....',
    '.....kek.kek....',
    '.....kkk.kkk....',
    '................',
  ],
  archer: [
    '................',
    '................',
    '.....kkkkkk.....',
    '.kk.kNNNNNNk.kk.',
    '.kekeyeeeyeekek.',
    '..kkeeEEEeekk...',
    '....keewweek....',
    '.....kkkkkk..k..',
    '....kEEEEEEk.kNk',
    '...keEEEEEEekNwk',
    '...kkkNNNNkkkNwk',
    '.....kEEEEk..kNk',
    '.....keekeek..k.',
    '.....kek.kek....',
    '.....kkk.kkk....',
    '................',
  ],
  squelette: [
    '................',
    '......kkkk......',
    '.....kllllk.....',
    '....kllllllk....',
    '....kxxllxxk....',
    '....kllLLllk....',
    '.....klklkk.....',
    '......kkkk...kg.',
    '....kkLlLlkk.kg.',
    '...klkLlLlkklkg.',
    '...kk.kLlLk.kkn.',
    '......klLlk.....',
    '.....kLkkLk.....',
    '.....kl..lk.....',
    '.....kl..lk.....',
    '....kkk..kkk....',
  ],
  loup: [
    '................',
    '................',
    '................',
    '..k.k...........',
    '.kgkgk..........',
    '.kgggGk.........',
    'kggyggGkkkkkkk..',
    'xggggGgggggggGk.',
    '.kwwkGggggggGGGk',
    '..kkkGggggggGGk.',
    '....kGgGGGGgGk.k',
    '....kgk.kk.kgkgk',
    '....kgk....kgk..',
    '....kGk....kGk..',
    '....kkk....kkk..',
    '................',
  ],
  chaman: [
    '....r....r......',
    '....rk..kr......',
    '.....kkkkkk.....',
    '.kk.keeeeeek.kk.',
    '.kekeceeeceekek.',
    '..kkeeEEEeekk...',
    '....kbbbbbbk..y.',
    '...kbbyybbbbkkyk',
    '...kbbbyybbbk.n.',
    '...kbbbbbbbbken.',
    '...kBbbbbbbBk.n.',
    '....kBbbbbBk..n.',
    '....kBBkkBBk..n.',
    '.....kek.kek..n.',
    '.....kkk.kkk..n.',
    '................',
  ],
  orc: [
    '................',
    '.....kkkkkk.....',
    '....kEEEEEEk....',
    '...kEEEEEEEEk...',
    '...kErrEErrEk...',
    '...kEEEEEEEEk...',
    '...kEwEkkEwEk.k.',
    '..kkkEEEEEEkkkgk',
    '.kEkNNNNNNNNkggk',
    '.kEkNnnnnnnNkngk',
    '.kEkNnnnnnnNEn..',
    '.kkkknnnnnnkkn..',
    '....kNNkkNNk.n..',
    '....kEEk.kEEk...',
    '....kNNk.kNNk...',
    '....kkkk.kkkk...',
  ],
  araignee: [
    '................',
    '................',
    '................',
    '..k..........k..',
    '.k.k..kkkk..k.k.',
    'k...kkPPPPkk...k',
    'k..kPPpPPpPPk..k',
    '.k.kPpPPPPpPk.k.',
    '..kkPPPPPPPPkk..',
    '.k.kkPrPPrPkk.k.',
    'k..kPrPPPPrPk..k',
    'k...kPwPPwPk...k',
    '.k...kkkkkk...k.',
    '..k..........k..',
    '................',
    '................',
  ],
  spectre: [
    '................',
    '......kkkk......',
    '.....kccwck.....',
    '....kcccccck....',
    '....kcxccxck....',
    '....kcxccxck....',
    '....kccxxcck....',
    '...kcccccccck...',
    '..kcbccccccbck..',
    '.kcbkccccccckbck',
    '.kbk.kcccccck.kk',
    '.....kcbccbck...',
    '.....kbcbcbck...',
    '......kbkbkbk...',
    '.......k.k.k....',
    '................',
  ],
  mimique: [
    '................',
    '................',
    '................',
    '..kkkkkkkkkkkk..',
    '.knnnnnyynnnnnk.',
    '.kNNNNNyyNNNNNk.',
    '.kyyyyyyyyyyyyk.',
    '.kwkwkwkwkwkwkk.',
    '.kRRRRrrrrRRRRk.',
    '.kRRrRRxxRRrRRk.',
    '.kwkwkwkwkwkwkk.',
    '.kyyyyyyyyyyyyk.',
    '.knnnnnnnnnnnnk.',
    '.kNNNNNNNNNNNNk.',
    '..kkkkkkkkkkkk..',
    '................',
  ],
  ogre: [
    '.....kkkkkk.....',
    '....kssssssk....',
    '...kssssssssk...',
    '...ksrkssrksk...',
    '...kssssSsssk...',
    '...ksSwSSwSsk...',
    '..kkkssssssskkk.',
    '.kssknnnnnnkssk.',
    'ksssknnnnnnksssk',
    'kssknnnNNnnnkssk',
    'ksskNnnnnnnNksNk',
    '.kk.knnnnnnk.kNk',
    '....kNNNNNNk.kNk',
    '....kssk.kssk.kk',
    '....kssk.kssk...',
    '...kkkkk.kkkkk..',
  ],
  liche: [
    '....y.y.y.......',
    '....yyyyy...kk..',
    '...kllllllk.kek.',
    '...klxxlxxlk.kek',
    '...kllLLLllk..n.',
    '....klklklk...n.',
    '...kPPkkkPPk..n.',
    '..kPpPPpPPpPk.n.',
    '.kPpPPpePPpPPkn.',
    '.kPkPPpppPPkPln.',
    '.kk.kPpppPPk..n.',
    '....kPpppPPk..n.',
    '...kPPpppPPPk.n.',
    '...kPpPpPpPPk.n.',
    '..kPPPPPPPPPPkn.',
    '..kkkkkkkkkkkk..',
  ],
};

const SPR = {};   // nom -> { img, white }
const TILES = {}; // textures de tuiles

function makeCanvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  return c;
}

function buildSprites() {
  for (const [name, rows] of Object.entries(SPRITE_DATA)) {
    const img = makeCanvas(PX, PX), white = makeCanvas(PX, PX);
    const a = img.getContext('2d'), b = white.getContext('2d');
    rows.forEach((row, y) => {
      for (let x = 0; x < PX; x++) {
        const ch = row[x];
        if (!ch || ch === '.') continue;
        a.fillStyle = PALETTE[ch] || '#ff00ff';
        a.fillRect(x, y, 1, 1);
        b.fillStyle = '#ffffff';
        b.fillRect(x, y, 1, 1);
      }
    });
    SPR[name] = { img, white };
  }
  buildTiles();
}

// --- Tuiles générées --------------------------------------------------------
function seeded(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

function shadeHex(hex, f) {
  const n = parseInt(hex.slice(1), 16);
  const c = v => Math.max(0, Math.min(255, Math.round(v * f)));
  return `rgb(${c(n >> 16)},${c((n >> 8) & 255)},${c(n & 255)})`;
}

function buildTiles() {
  TILES.floor = [];
  for (let v = 0; v < 4; v++) {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(17 + v * 31);
    ctx.fillStyle = '#4a443e'; ctx.fillRect(0, 0, PX, PX);
    // dalles 8×8 décalées
    for (let by = 0; by < 2; by++) for (let bx = 0; bx < 2; bx++) {
      ctx.fillStyle = shadeHex('#4a443e', 0.9 + rnd() * 0.25);
      ctx.fillRect(bx * 8 + 1, by * 8 + 1, 7, 7);
      ctx.fillStyle = 'rgba(255,255,255,0.06)';
      ctx.fillRect(bx * 8 + 1, by * 8 + 1, 7, 1);
    }
    ctx.fillStyle = '#2e2a26';
    for (let i = 0; i < PX; i++) { ctx.fillRect(i, 0, 1, 1); ctx.fillRect(0, i, 1, 1); ctx.fillRect(i, 8, 1, 1); ctx.fillRect(8, i, 1, 1); }
    // grain
    for (let i = 0; i < 10; i++) {
      ctx.fillStyle = rnd() < 0.5 ? 'rgba(0,0,0,0.18)' : 'rgba(255,255,255,0.07)';
      ctx.fillRect((rnd() * PX) | 0, (rnd() * PX) | 0, 1, 1);
    }
    if (v === 3) { // fissure
      ctx.fillStyle = '#2a2622';
      let x = 3, y = 3;
      for (let i = 0; i < 9; i++) { ctx.fillRect(x, y, 1, 1); x += rnd() < 0.6 ? 1 : 0; y += 1; }
    }
    TILES.floor.push(c);
  }

  // Dessus de mur
  TILES.wallTop = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(99);
    ctx.fillStyle = '#211d1a'; ctx.fillRect(0, 0, PX, PX);
    for (let i = 0; i < 14; i++) { ctx.fillStyle = 'rgba(255,255,255,0.04)'; ctx.fillRect((rnd() * PX) | 0, (rnd() * PX) | 0, 2, 1); }
    return c;
  })();

  // Façade de mur en briques
  TILES.wallFace = [0, 1].map(v => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(7 + v * 13);
    ctx.fillStyle = '#2b2520'; ctx.fillRect(0, 0, PX, PX);
    for (let row = 0; row < 4; row++) {
      const off = row % 2 ? 4 : 0;
      for (let bx = -1; bx < 3; bx++) {
        const x = bx * 8 + off;
        ctx.fillStyle = shadeHex('#6a5a48', 0.75 + rnd() * 0.35);
        ctx.fillRect(x + 1, row * 4 + 1, 7, 3);
        ctx.fillStyle = 'rgba(255,255,255,0.08)';
        ctx.fillRect(x + 1, row * 4 + 1, 7, 1);
      }
    }
    ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.fillRect(0, PX - 2, PX, 2);
    return c;
  });

  // Gravats (superposés au sol)
  TILES.rubble = (() => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d'), rnd = seeded(55);
    for (let i = 0; i < 6; i++) {
      const x = 2 + ((rnd() * 11) | 0), y = 2 + ((rnd() * 11) | 0), s = 2 + ((rnd() * 2) | 0);
      ctx.fillStyle = '#1e1a16'; ctx.fillRect(x, y + 1, s, s);
      ctx.fillStyle = '#7a6a56'; ctx.fillRect(x, y, s, s);
      ctx.fillStyle = '#9a8a72'; ctx.fillRect(x, y, s - 1, 1);
    }
    return c;
  })();

  // Eau (2 images d'animation)
  TILES.water = [0, 1].map(f => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    ctx.fillStyle = '#1b3d5a'; ctx.fillRect(0, 0, PX, PX);
    ctx.fillStyle = '#24557a'; ctx.fillRect(0, 0, PX, 3);
    ctx.fillStyle = '#5fa8d8';
    for (const [x, y] of [[2, 5], [9, 9], [4, 12], [11, 3]]) ctx.fillRect((x + f * 2) % 14, y, 3, 1);
    return c;
  });

  // Torche murale (3 images)
  TILES.torch = [0, 1, 2].map(f => {
    const c = makeCanvas(PX, PX), ctx = c.getContext('2d');
    ctx.fillStyle = '#3a2a1a'; ctx.fillRect(7, 8, 2, 5);
    ctx.fillStyle = '#5a4a3a'; ctx.fillRect(6, 8, 4, 1);
    const flame = [[7, 7], [8, 7], [7, 6], [8, 6], [7 + (f === 1 ? 1 : 0), 5], [8 - (f === 2 ? 1 : 0), 4]];
    ctx.fillStyle = '#f08030'; flame.forEach(([x, y]) => ctx.fillRect(x, y, 1, 1));
    ctx.fillStyle = '#ffe066'; ctx.fillRect(7 + (f % 2), 6, 1, 1);
    return c;
  });
}
