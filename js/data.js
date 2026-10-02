'use strict';

// ---------------------------------------------------------------------------
// Classes jouables
// Types de capacités :
//   attack     : jet d'attaque (d20 + bonus) contre la CA d'un ennemi
//   autohit    : dégâts automatiques sur un ennemi
//   save       : l'ennemi fait un jet de sauvegarde (DD) ou subit les dégâts
//   aoe        : zone (rayon) — jets de sauvegarde, touche AUSSI les alliés
//   aoeAttack  : zone — un jet d'attaque par ennemi présent dans la zone
//   whirlwind  : un jet d'attaque contre chaque ennemi adjacent
//   heal       : soigne un allié (ou soi-même) à portée
//   massheal   : soigne tous les alliés dans un rayon autour du lanceur
//   selfheal   : se soigne soi-même
//   teleport   : se déplace instantanément sur une case visible
//   dash       : ajoute du déplacement pour ce tour
// bonus: true => utilise l'action bonus au lieu de l'action principale.
// cd = nombre de tours avant de pouvoir réutiliser la capacité.
// onHit = état infligé à la cible ({ status, turns, chance }).
// ---------------------------------------------------------------------------

const DASH = {
  id: 'foncer', name: 'Foncer', icon: '🏃', type: 'dash', cd: 0,
  desc: 'Utilise ton action pour gagner un déplacement supplémentaire égal à ta vitesse.',
};

const CLASSES = {
  guerrier: {
    name: 'Guerrier', icon: '🛡️', color: '#b5462f',
    hp: 34, hpLvl: 8, ac: 17, speed: 5, dex: 1,
    desc: 'Robuste et redoutable au corps à corps. Il encaisse les coups en première ligne.',
    abilities: [
      { id: 'epee', name: "Coup d'épée", icon: '⚔️', type: 'attack', range: 1, hit: 5, dmg: '1d10+3', cd: 0,
        desc: 'Attaque au corps à corps.' },
      { id: 'tourbillon', name: 'Tourbillon', icon: '🌀', type: 'whirlwind', range: 1, hit: 5, dmg: '1d8+3', cd: 3,
        desc: 'Attaque tous les ennemis adjacents.' },
      { id: 'bouclier', name: 'Coup de bouclier', icon: '🛡️', type: 'attack', range: 1, hit: 5, dmg: '1d4+2', cd: 3, bonus: true,
        onHit: { status: 'stun', turns: 1, chance: 0.5 },
        desc: 'Action bonus : 50 % de chances d\'étourdir la cible (elle perd son tour).' },
      { id: 'souffle', name: 'Second souffle', icon: '💪', type: 'selfheal', heal: '1d10+4', cd: 4, bonus: true,
        desc: 'Action bonus : récupère des points de vie.' },
      DASH,
    ],
  },
  mage: {
    name: 'Mage', icon: '🔮', color: '#5b48c2',
    hp: 18, hpLvl: 5, ac: 12, speed: 5, dex: 2,
    desc: 'Fragile mais dévastateur à distance. Attention : la boule de feu brûle aussi les alliés !',
    abilities: [
      { id: 'trait', name: 'Trait de feu', icon: '🔥', type: 'attack', range: 8, hit: 6, dmg: '1d10+2', cd: 0, fx: '#ff7a2a',
        desc: 'Attaque magique à distance.' },
      { id: 'projectile', name: 'Projectile magique', icon: '✴️', type: 'autohit', range: 10, dmg: '3d4+3', cd: 2, fx: '#c49bff',
        desc: 'Touche automatiquement la cible.' },
      { id: 'givre', name: 'Rayon de givre', icon: '❄️', type: 'attack', range: 7, hit: 6, dmg: '1d8+1', cd: 2, fx: '#9be8ff',
        onHit: { status: 'slow', turns: 2, chance: 1 }, desc: 'Ralentit la cible (vitesse divisée par 2) pendant 2 tours.' },
      { id: 'boule', name: 'Boule de feu', icon: '☄️', type: 'aoe', range: 8, radius: 1, save: 'dex', dc: 14, half: true,
        dmg: '4d6', cd: 4, fx: '#ff5a1a', onHit: { status: 'burn', turns: 2, chance: 1 },
        desc: 'Explosion 3×3. Sauvegarde Dex DD 14 pour moitié, enflamme ceux qui ratent. Touche aussi les alliés !' },
      DASH,
    ],
  },
  rodeur: {
    name: 'Rôdeur', icon: '🏹', color: '#2f7d4a',
    hp: 26, hpLvl: 6, ac: 15, speed: 6, dex: 3,
    desc: "Archer d'élite, rapide et précis. Il harcèle l'ennemi depuis l'arrière.",
    abilities: [
      { id: 'arc', name: 'Arc long', icon: '🏹', type: 'attack', range: 10, hit: 6, dmg: '1d8+3', cd: 0, fx: '#d9c38a',
        desc: 'Attaque à distance.' },
      { id: 'precis', name: 'Tir précis', icon: '🎯', type: 'attack', range: 12, hit: 9, dmg: '2d8+3', cd: 2, fx: '#ffe28a',
        desc: 'Tir ajusté : +3 au toucher, dégâts doublés.' },
      { id: 'pluie', name: 'Pluie de flèches', icon: '🌧️', type: 'aoeAttack', range: 9, radius: 1, hit: 6, dmg: '1d8+2', cd: 4,
        fx: '#d9c38a', desc: 'Un jet d\'attaque contre chaque ennemi dans une zone 3×3.' },
      { id: 'repli', name: 'Pas de côté', icon: '💨', type: 'dash', amount: 3, cd: 2, bonus: true,
        desc: 'Action bonus : +3 cases de déplacement.' },
      DASH,
    ],
  },
  clerc: {
    name: 'Clerc', icon: '✨', color: '#c9a227',
    hp: 26, hpLvl: 6, ac: 16, speed: 5, dex: 0,
    desc: 'Soigneur divin. Il peut relever les alliés tombés au combat.',
    abilities: [
      { id: 'masse', name: "Masse d'armes", icon: '🔨', type: 'attack', range: 1, hit: 4, dmg: '1d8+2', cd: 0,
        desc: 'Attaque au corps à corps.' },
      { id: 'flamme', name: 'Flamme sacrée', icon: '🕯️', type: 'save', range: 6, save: 'dex', dc: 13, dmg: '2d8', cd: 0,
        fx: '#fff1a8', desc: 'Sauvegarde Dex DD 13 ou subit des dégâts radiants.' },
      { id: 'soin', name: 'Soin', icon: '💚', type: 'heal', range: 5, heal: '2d8+3', cd: 2, bonus: true, fx: '#7dffa8',
        desc: 'Action bonus : soigne un allié (ou toi-même). Relève un allié inconscient. Retire poison et brûlure.' },
      { id: 'priere', name: 'Prière de guérison', icon: '🙏', type: 'massheal', radius: 3, heal: '1d8+3', cd: 5,
        desc: 'Soigne tous les alliés à 3 cases ou moins.' },
      DASH,
    ],
  },
  voleur: {
    name: 'Voleur', icon: '🗡️', color: '#555b66',
    hp: 22, hpLvl: 5, ac: 14, speed: 7, dex: 4,
    desc: 'Très mobile. Attaque sournoise (+2d6) quand un allié est au contact de la cible.',
    abilities: [
      { id: 'dague', name: 'Dague', icon: '🗡️', type: 'attack', range: 1, hit: 6, dmg: '1d6+4', cd: 0, sneak: true,
        desc: 'Corps à corps. Attaque sournoise possible.' },
      { id: 'lancer', name: 'Couteau de lancer', icon: '🔪', type: 'attack', range: 5, hit: 6, dmg: '1d4+4', cd: 0, sneak: true,
        fx: '#cfd6e0', desc: 'Distance courte. Attaque sournoise possible.' },
      { id: 'poison', name: 'Lame empoisonnée', icon: '🧪', type: 'attack', range: 1, hit: 6, dmg: '1d6+2', cd: 3, sneak: true,
        onHit: { status: 'poison', turns: 3, chance: 1 }, desc: 'Empoisonne la cible pendant 3 tours.' },
      { id: 'ombre', name: "Pas de l'ombre", icon: '🌑', type: 'teleport', range: 6, cd: 3, bonus: true,
        desc: 'Action bonus : téléportation sur une case visible à 6 cases.' },
      DASH,
    ],
  },
};

// ---------------------------------------------------------------------------
// États (statuts)
// ---------------------------------------------------------------------------
const STATUS = {
  poison: { name: 'Empoisonné', icon: '🟢', color: '#7ad04a', desc: '3 dégâts au début du tour.' },
  burn: { name: 'En feu', icon: '🔥', color: '#ff7a2a', desc: '1d6 dégâts au début du tour.' },
  slow: { name: 'Ralenti', icon: '🧊', color: '#9be8ff', desc: 'Vitesse divisée par 2.' },
  stun: { name: 'Étourdi', icon: '💫', color: '#ffe066', desc: 'Perd son prochain tour.' },
};

// ---------------------------------------------------------------------------
// Monstres
// cost = poids dans le budget de rencontre, xp/gold = récompenses
// ---------------------------------------------------------------------------
const MONSTERS = {
  gobelin: {
    name: 'Gobelin', icon: '👺', sprite: 'gobelin', color: '#5a7d2a', hp: 9, ac: 13, speed: 6, dex: 2, xp: 3, gold: 3,
    attack: { id: 'cimeterre', name: 'Cimeterre', type: 'attack', range: 1, hit: 4, dmg: '1d6+2' },
  },
  archer: {
    name: 'Archer gobelin', icon: '🎯', sprite: 'archer', color: '#6d8a3a', hp: 8, ac: 12, speed: 6, dex: 2, xp: 3, gold: 3,
    attack: { id: 'arcCourt', name: 'Arc court', type: 'attack', range: 8, hit: 4, dmg: '1d6+2', fx: '#c9b27a' },
  },
  squelette: {
    name: 'Squelette', icon: '💀', sprite: 'squelette', color: '#9a9484', hp: 14, ac: 13, speed: 5, dex: 2, xp: 4, gold: 2,
    attack: { id: 'epeeCourte', name: 'Épée rouillée', type: 'attack', range: 1, hit: 4, dmg: '1d6+2' },
  },
  loup: {
    name: 'Loup', icon: '🐺', sprite: 'loup', color: '#6b6b78', hp: 12, ac: 13, speed: 8, dex: 2, xp: 4, gold: 1,
    attack: { id: 'morsure', name: 'Morsure', type: 'attack', range: 1, hit: 4, dmg: '2d4+2' },
  },
  chaman: {
    name: 'Chaman gobelin', icon: '🪄', sprite: 'chaman', color: '#4a6d8a', hp: 14, ac: 12, speed: 5, dex: 1, xp: 6, gold: 6,
    attack: { id: 'eclair', name: 'Éclair', type: 'attack', range: 7, hit: 5, dmg: '1d10+1', fx: '#8ad0ff' },
    heal: { id: 'soinNoir', name: 'Soin impie', type: 'heal', range: 6, heal: '2d6+2', fx: '#b07dff' },
  },
  orc: {
    name: 'Orc', icon: '👹', sprite: 'orc', color: '#7a3b2e', hp: 19, ac: 13, speed: 5, dex: 1, xp: 7, gold: 6,
    attack: { id: 'hache', name: 'Grande hache', type: 'attack', range: 1, hit: 5, dmg: '1d12+3' },
  },
  araignee: {
    name: 'Araignée géante', icon: '🕷️', sprite: 'araignee', color: '#3a2a3a', hp: 18, ac: 13, speed: 6, dex: 3, xp: 7, gold: 4,
    attack: { id: 'crochets', name: 'Crochets venimeux', type: 'attack', range: 1, hit: 5, dmg: '1d8+2',
      onHit: { status: 'poison', turns: 3, chance: 1 } },
  },
  spectre: {
    name: 'Spectre', icon: '👻', sprite: 'spectre', color: '#5a6a8a', hp: 20, ac: 12, speed: 6, dex: 2, xp: 8, gold: 5,
    attack: { id: 'glacial', name: 'Toucher glacial', type: 'attack', range: 1, hit: 5, dmg: '2d6+1',
      onHit: { status: 'slow', turns: 2, chance: 1 } },
  },
  mimique: {
    name: 'Mimique', icon: '📦', sprite: 'mimique', color: '#8a6a3a', hp: 32, ac: 14, speed: 4, dex: 1, xp: 15, gold: 50,
    attack: { id: 'machoire', name: 'Mâchoire', type: 'attack', range: 1, hit: 6, dmg: '2d8+3' },
  },
  ogre: {
    name: 'Ogre', icon: '🧌', sprite: 'ogre', color: '#8a5a2e', hp: 85, ac: 13, speed: 5, dex: -1, boss: true, xp: 40, gold: 60,
    attack: { id: 'massue', name: 'Massue géante', type: 'attack', range: 1, hit: 7, dmg: '2d8+5',
      onHit: { status: 'stun', turns: 1, chance: 0.3 } },
  },
  liche: {
    name: 'Liche', icon: '☠️', sprite: 'liche', color: '#4a3a6a', hp: 120, ac: 15, speed: 4, dex: 1, boss: true, xp: 60, gold: 100,
    attack: { id: 'rayonMort', name: 'Rayon nécrotique', type: 'attack', range: 8, hit: 7, dmg: '2d8+3', fx: '#b07dff',
      onHit: { status: 'slow', turns: 1, chance: 0.5 } },
    summon: { kind: 'squelette', every: 3 },
  },
};

// Traits des monstres d'élite
const ELITE_TRAITS = [
  { id: 'enrage', name: 'Enragé', desc: '+2 toucher, +3 dégâts', apply: m => { m.hitMod += 2; m.dmgMod += 3; } },
  { id: 'blinde', name: 'Blindé', desc: '+3 CA', apply: m => { m.ac += 3; } },
  { id: 'vampire', name: 'Vampirique', desc: 'Se soigne de la moitié des dégâts infligés', apply: m => { m.mods.lifesteal = 0.5; } },
  { id: 'rapide', name: 'Rapide', desc: '+3 vitesse', apply: m => { m.speed += 3; } },
  { id: 'geant', name: 'Géant', desc: 'PV doublés', apply: m => { m.maxHp *= 2; m.hp = m.maxHp; } },
];

// ---------------------------------------------------------------------------
// Actes du donjon
// ---------------------------------------------------------------------------
const ACTS = [
  {
    name: 'Les Cryptes', rows: 7,
    pool: [['gobelin', 1], ['archer', 1], ['loup', 1.5], ['squelette', 1.5], ['chaman', 2]],
    budget: row => 4.5 + row * 0.75,
    elites: ['orc', 'loup', 'squelette'],
    boss: { name: "L'Ogre des Cryptes", monsters: ['ogre', 'gobelin', 'gobelin', 'archer', 'chaman'] },
  },
  {
    name: 'Les Profondeurs', rows: 7,
    pool: [['orc', 2], ['squelette', 1.5], ['araignee', 2], ['spectre', 2.5], ['chaman', 2], ['archer', 1]],
    budget: row => 8 + row * 0.9,
    elites: ['orc', 'araignee', 'spectre'],
    boss: { name: 'La Liche', monsters: ['liche', 'squelette', 'squelette', 'spectre', 'spectre', 'araignee'] },
  },
];

// Expérience totale nécessaire pour chaque niveau (index = niveau)
const LEVEL_XP = [0, 0, 16, 40, 72, 112, 165, 230, 305, 390];

// ---------------------------------------------------------------------------
// Types de salles sur la carte de parcours
// ---------------------------------------------------------------------------
const NODE_TYPES = {
  combat: { name: 'Combat', icon: '⚔️', desc: 'Une salle gardée par des monstres.' },
  elite: { name: 'Élite', icon: '💀', desc: 'Un monstre redoutable… et un meilleur butin.' },
  event: { name: 'Mystère', icon: '❓', desc: 'Qui sait ce qui vous attend ?' },
  shop: { name: 'Marchand', icon: '💰', desc: 'Dépensez votre or.' },
  treasure: { name: 'Trésor', icon: '💎', desc: 'Un coffre vous attend.' },
  camp: { name: 'Feu de camp', icon: '🔥', desc: 'Se reposer ou s\'entraîner.' },
  boss: { name: 'Boss', icon: '👑', desc: 'Le maître des lieux.' },
};

// ---------------------------------------------------------------------------
// Objets (reliques équipées sur un héros)
// mods possibles : hit, dmg, ac, hp, speed, range, crit, lifesteal, regen, thorns, heal, init, cdr, radius, sneak
// ---------------------------------------------------------------------------
const ITEMS = {
  epee: { name: 'Lame affûtée', icon: '🗡️', rarity: 1, desc: '+2 dégâts', mods: { dmg: 2 } },
  gants: { name: 'Gants de précision', icon: '🧤', rarity: 1, desc: '+1 au toucher', mods: { hit: 1 } },
  bouclier: { name: 'Bouclier renforcé', icon: '🛡️', rarity: 1, desc: '+1 CA', mods: { ac: 1 } },
  amulette: { name: 'Amulette de vitalité', icon: '📿', rarity: 1, desc: '+8 PV max', mods: { hp: 8 } },
  bottes: { name: 'Bottes de célérité', icon: '👢', rarity: 1, desc: '+1 vitesse', mods: { speed: 1 } },
  bague: { name: 'Anneau de régénération', icon: '💍', rarity: 2, desc: 'Récupère 2 PV au début de chaque tour', mods: { regen: 2 } },
  croc: { name: 'Croc de vampire', icon: '🦷', rarity: 2, desc: 'Vol de vie : 20 % des dégâts infligés', mods: { lifesteal: 0.2 } },
  cape: { name: "Cape d'épines", icon: '🌵', rarity: 2, desc: 'Renvoie 3 dégâts aux attaquants au contact', mods: { thorns: 3 } },
  oeil: { name: 'Œil du faucon', icon: '🦅', rarity: 2, desc: '+2 portée aux attaques à distance', mods: { range: 2 } },
  trefle: { name: 'Trèfle à quatre feuilles', icon: '🍀', rarity: 2, desc: 'Coup critique sur 19-20', mods: { crit: 1 } },
  sablier: { name: 'Sablier arcanique', icon: '⏳', rarity: 3, desc: 'Temps de recharge −1 (minimum 1)', mods: { cdr: 1 } },
  mithril: { name: 'Cotte de mithril', icon: '🥋', rarity: 3, desc: '+2 CA, +6 PV max', mods: { ac: 2, hp: 6 } },
  rage: { name: 'Pierre de rage', icon: '🔴', rarity: 3, desc: '+4 dégâts, −1 CA', mods: { dmg: 4, ac: -1 } },
  plume: { name: 'Plume de phénix', icon: '🪶', rarity: 3, desc: '+4 aux soins prodigués, +1 régénération', mods: { heal: 4, regen: 1 } },
};

// Potions (inventaire commun, utilisables en combat)
const POTIONS = {
  soin: { id: 'pot_soin', name: 'Potion de soin', icon: '🧪', type: 'selfheal', heal: '2d8+4', bonus: true, price: 25,
    desc: 'Action bonus : récupère 2d8+4 PV.' },
  feu: { id: 'pot_feu', name: 'Fiole de feu', icon: '🔥', type: 'aoe', range: 5, radius: 1, save: 'dex', dc: 13, half: true,
    dmg: '3d6', price: 30, fx: '#ff7a2a', onHit: { status: 'burn', turns: 2, chance: 1 },
    desc: 'Action : lance une explosion 3×3 (3d6, Dex DD 13 pour moitié).' },
  vitesse: { id: 'pot_vitesse', name: 'Élixir de vitesse', icon: '⚡', type: 'dash', amount: 4, bonus: true, price: 20,
    desc: 'Action bonus : +4 cases de déplacement.' },
  antidote: { id: 'pot_antidote', name: 'Antidote', icon: '🌿', type: 'cleanse', heal: '1d4+2', bonus: true, price: 15,
    desc: 'Action bonus : retire poison, brûlure et ralentissement, +1d4+2 PV.' },
};

// ---------------------------------------------------------------------------
// Talents (choix à chaque montée de niveau)
// ---------------------------------------------------------------------------
const TALENTS = [
  { id: 'robuste', name: 'Robustesse', icon: '❤️', desc: '+8 PV max', mods: { hp: 8 } },
  { id: 'precision', name: 'Précision', icon: '🎯', desc: '+1 au toucher', mods: { hit: 1 } },
  { id: 'brutal', name: 'Brutalité', icon: '💥', desc: '+2 dégâts', mods: { dmg: 2 } },
  { id: 'vigilance', name: 'Vigilance', icon: '🛡️', desc: '+1 CA', mods: { ac: 1 } },
  { id: 'agile', name: 'Agilité', icon: '👣', desc: '+1 vitesse, +3 initiative', mods: { speed: 1, init: 3 } },
  { id: 'vent', name: 'Second vent', icon: '🌬️', desc: 'Récupère 1 PV au début de chaque tour', mods: { regen: 1 } },
  // Talents de classe
  { id: 'fer', cls: 'guerrier', name: 'Peau de fer', icon: '🪨', desc: '+2 CA', mods: { ac: 2 } },
  { id: 'sang', cls: 'guerrier', name: 'Soif de sang', icon: '🩸', desc: 'Vol de vie : 25 %', mods: { lifesteal: 0.25 } },
  { id: 'riposte', cls: 'guerrier', name: 'Riposte', icon: '⚔️', desc: 'Renvoie 4 dégâts aux attaquants au contact', mods: { thorns: 4 } },
  { id: 'pyro', cls: 'mage', name: 'Pyromane', icon: '☄️', desc: 'Rayon des zones +1 (boule de feu 5×5)', mods: { radius: 1 } },
  { id: 'arcane', cls: 'mage', name: 'Arcaniste', icon: '⏳', desc: 'Temps de recharge −1', mods: { cdr: 1 } },
  { id: 'puissance', cls: 'mage', name: 'Puissance occulte', icon: '🔮', desc: '+3 dégâts', mods: { dmg: 3 } },
  { id: 'aigle', cls: 'rodeur', name: "Œil d'aigle", icon: '🦅', desc: '+3 portée', mods: { range: 3 } },
  { id: 'mortel', cls: 'rodeur', name: 'Tir mortel', icon: '💀', desc: 'Coup critique sur 18-20', mods: { crit: 2 } },
  { id: 'chasseur', cls: 'rodeur', name: 'Chasseur', icon: '🐾', desc: '+2 toucher, +1 vitesse', mods: { hit: 2, speed: 1 } },
  { id: 'benediction', cls: 'clerc', name: 'Bénédiction', icon: '✨', desc: '+5 aux soins', mods: { heal: 5 } },
  { id: 'foi', cls: 'clerc', name: 'Bouclier de la foi', icon: '🛡️', desc: '+2 CA, +5 PV max', mods: { ac: 2, hp: 5 } },
  { id: 'zele', cls: 'clerc', name: 'Zèle', icon: '🔨', desc: '+2 toucher, +2 dégâts', mods: { hit: 2, dmg: 2 } },
  { id: 'assassin', cls: 'voleur', name: 'Assassin', icon: '🗡️', desc: 'Attaque sournoise +1d6', mods: { sneak: 1 } },
  { id: 'esquive', cls: 'voleur', name: 'Esquive', icon: '💨', desc: '+2 CA', mods: { ac: 2 } },
  { id: 'opportuniste', cls: 'voleur', name: 'Opportuniste', icon: '🍀', desc: 'Coup critique sur 19-20, +1 vitesse', mods: { crit: 1, speed: 1 } },
];

// ---------------------------------------------------------------------------
// Événements mystères — chaque choix appelle une fonction de run.js
// ---------------------------------------------------------------------------
const EVENTS = [
  {
    title: 'Autel ensanglanté',
    text: 'Un autel couvert de runes pulse d\'une lueur rouge. Une voix murmure : « Offre ton sang, reçois ma puissance. »',
    choices: [
      { label: 'Offrir son sang (−8 PV à chaque héros, gagner un objet rare)', run: () => { damageParty(8); return grantItem(2, 'Le sang coule… et un objet apparaît sur l\'autel.'); } },
      { label: 'Partir', run: () => 'Vous vous éloignez prudemment.' },
    ],
  },
  {
    title: 'Fontaine claire',
    text: 'Une fontaine d\'eau pure jaillit entre les pierres. Elle semble bénie.',
    choices: [
      { label: 'Boire (soigne 50 % des PV de chacun)', run: () => { healPartyPct(0.5); return 'L\'eau fraîche ravive vos forces.'; } },
      { label: 'Remplir des fioles (+2 potions de soin)', run: () => { addPotion('soin'); addPotion('soin'); return 'Vous remplissez deux fioles.'; } },
    ],
  },
  {
    title: 'Coffre suspect',
    text: 'Un coffre richement décoré trône au milieu de la pièce. Trop beau pour être vrai ?',
    choices: [
      { label: 'L\'ouvrir', run: () => {
        if (Math.random() < 0.45) { startMimicFight(); return null; }
        RUN.gold += 60; return 'Le coffre contenait 60 pièces d\'or !';
      } },
      { label: 'Le laisser', run: () => 'Mieux vaut ne pas tenter le diable.' },
    ],
  },
  {
    title: 'Le joueur de dés',
    text: 'Un vieil homme encapuchonné agite des dés en os. « Une partie ? Double ou rien, 30 pièces d\'or. »',
    choices: [
      { label: 'Jouer (30 or)', cond: () => RUN.gold >= 30, run: () => {
        const a = d20(), b = d20();
        if (a > b) { RUN.gold += 30; return `🎲 Vous faites ${a}, il fait ${b}. Vous gagnez 30 or !`; }
        RUN.gold -= 30; return `🎲 Vous faites ${a}, il fait ${b}. Vous perdez 30 or.`;
      } },
      { label: 'Refuser', run: () => '« Dommage… » ricane-t-il.' },
    ],
  },
  {
    title: 'Aventurier blessé',
    text: 'Un aventurier agonise contre un mur. « Prenez… mon équipement… vengez-moi… »',
    choices: [
      { label: 'Prendre son équipement', run: () => grantItem(1, 'Vous récupérez son équipement.') },
      { label: 'Le soigner (−1 potion de soin, +50 or de récompense)', cond: () => RUN.potions.includes('soin'),
        run: () => { removePotion('soin'); RUN.gold += 50; return 'Il survit et vous remercie avec sa bourse : 50 or.'; } },
    ],
  },
  {
    title: 'Bibliothèque oubliée',
    text: 'Des grimoires poussiéreux couvrent les étagères. Leur savoir pourrait vous être utile.',
    choices: [
      { label: 'Étudier (tout le groupe gagne 15 XP)', run: () => { gainXp(15); return 'Vous apprenez des techniques oubliées.'; } },
      { label: 'Fouiller (+1 potion au hasard)', run: () => { const k = randomPotionKey(); addPotion(k); return `Vous trouvez : ${POTIONS[k].icon} ${POTIONS[k].name}.`; } },
    ],
  },
];
