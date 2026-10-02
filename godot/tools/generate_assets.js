// Génère les images PNG du dossier assets/ à partir des dessins en texte.
// Utilisation (nécessite Node.js et Playwright) :  node godot/tools/generate_assets.js
// Les PNG sont déjà dans le dépôt : ce script ne sert que si tu modifies les dessins.
const path = require('path');
const fs = require('fs');
const { chromium } = require(process.env.PLAYWRIGHT || 'playwright');

const root = path.join(__dirname, '..');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setContent('<html><body></body></html>');
  await page.addScriptTag({ path: path.join(root, '..', 'js', 'sprites.js') });
  await page.addScriptTag({ path: path.join(__dirname, 'pixel_art.js') });
  const out = await page.evaluate(() => {
    buildSprites();
    const r = {};
    const add = (name, canvas) => { r[name] = canvas.toDataURL(); };
    for (const [k, v] of Object.entries(SPR)) add('sprites/' + k, v.img);
    for (const [k, rows] of Object.entries(EXTRA_SPRITES)) add('sprites/' + k, paintRows(rows));
    for (const [k, rows] of Object.entries(ICONS)) if (k !== 'potion') add('icons/' + k, paintRows(rows));
    for (const [k, col] of Object.entries(POTION_COLORS)) add('icons/potion_' + k, paintRows(ICONS.potion, { C: col }));
    // Crypte
    TILES.floor.forEach((c, i) => add('tiles/floor_' + i, c));
    TILES.wallFace.forEach((c, i) => add('tiles/wall_face_' + i, c));
    TILES.water.forEach((c, i) => add('tiles/water_' + i, c));
    TILES.torch.forEach((c, i) => add('tiles/torch_' + i, c));
    add('tiles/wall_top', TILES.wallTop);
    add('tiles/rubble', TILES.rubble);
    // Forêt et volcan
    const T = buildBiomeTiles();
    for (const [k, v] of Object.entries(T)) {
      if (Array.isArray(v)) v.forEach((c, i) => add(`tiles/${k}_${i}`, c));
      else add('tiles/' + k, v);
    }
    return r;
  });
  for (const [k, v] of Object.entries(out)) {
    const file = path.join(root, 'assets', k + '.png');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, Buffer.from(v.split(',')[1], 'base64'));
  }
  console.log(Object.keys(out).length + ' images générées');
  await browser.close();
})();
