extends Node
## Toutes les données du jeu : classes, pouvoirs, monstres, boss, actes, objets, potions, talents, événements.
## Ce script est chargé automatiquement (autoload) sous le nom « Data ».
## Pour équilibrer le jeu ou ajouter du contenu, c'est ici qu'il faut aller.
##
## Types de capacités :
##   attack     : jet d'attaque (d20 + bonus) contre la CA d'un ennemi
##   autohit    : dégâts automatiques sur un ennemi
##   save       : l'ennemi fait un jet de sauvegarde (DD) ou subit les dégâts
##   aoe        : zone (rayon) — jets de sauvegarde, touche AUSSI les alliés
##   aoeAttack  : zone — un jet d'attaque par ennemi dans la zone
##   whirlwind  : un jet d'attaque contre chaque ennemi adjacent
##   chain      : attaque une cible puis rebondit sur les ennemis proches
##   charge     : bondit à côté d'un ennemi puis l'attaque
##   heal       : soigne un allié (ou soi-même) à portée
##   massheal   : soigne tous les alliés dans un rayon autour du lanceur
##   selfheal   : se soigne soi-même
##   shield     : donne un bouclier (PV temporaires) à un allié
##   buff       : donne un état (ex. force) aux alliés dans un rayon
##   cleanse    : retire poison, brûlure et ralentissement
##   teleport   : se déplace instantanément sur une case visible
##   dash       : ajoute du déplacement pour ce tour
## Options : "bonus" (action bonus), "cd" (recharge en tours), "onHit" (état infligé),
##           "sneak" (attaque sournoise), "execute" (dégâts en plus si la cible a moins de la moitié de ses PV).

const DASH := {
	"id": "foncer", "name": "Foncer", "type": "dash", "cd": 0,
	"desc": "Utilise ton action pour gagner un déplacement supplémentaire égal à ta vitesse.",
}

var CLASSES := {
	"guerrier": {
		"name": "Guerrier", "hp": 34, "hp_lvl": 8, "ac": 17, "speed": 5, "dex": 1,
		"desc": "Robuste et redoutable au corps à corps. Il encaisse les coups en première ligne.",
		"abilities": [
			{"id": "epee", "name": "Coup d'épée", "type": "attack", "range": 1, "hit": 5, "dmg": "1d10+3",
				"desc": "Attaque au corps à corps."},
			{"id": "tourbillon", "name": "Tourbillon", "type": "whirlwind", "range": 1, "hit": 5, "dmg": "1d8+3", "cd": 3,
				"desc": "Attaque tous les ennemis adjacents."},
			{"id": "souffle", "name": "Second souffle", "type": "selfheal", "heal": "1d10+4", "cd": 4, "bonus": true,
				"desc": "Action bonus : récupère des points de vie."},
			DASH,
		],
		"powers": [
			{"id": "charge", "name": "Charge", "type": "charge", "range": 5, "hit": 6, "dmg": "2d8+3", "cd": 3,
				"desc": "Bondit à côté d'un ennemi à 5 cases et le frappe violemment."},
			{"id": "cri", "name": "Cri de guerre", "type": "buff", "radius": 3, "status": "force", "turns": 2, "cd": 4, "bonus": true,
				"desc": "Action bonus : les alliés à 3 cases gagnent Force (+3 dégâts) pendant 2 tours."},
			{"id": "bouclier", "name": "Coup de bouclier", "type": "attack", "range": 1, "hit": 5, "dmg": "1d4+2", "cd": 3, "bonus": true,
				"onHit": {"status": "stun", "turns": 1, "chance": 0.5},
				"desc": "Action bonus : 50 % de chances d'étourdir la cible."},
		],
	},
	"mage": {
		"name": "Mage", "hp": 18, "hp_lvl": 5, "ac": 12, "speed": 5, "dex": 2,
		"desc": "Fragile mais dévastateur à distance. Attention : la boule de feu brûle aussi les alliés !",
		"abilities": [
			{"id": "trait", "name": "Trait de feu", "type": "attack", "range": 8, "hit": 6, "dmg": "1d10+2",
				"fx": Color("#ff7a2a"), "desc": "Attaque magique à distance."},
			{"id": "projectile", "name": "Projectile magique", "type": "autohit", "range": 10, "dmg": "3d4+3", "cd": 2,
				"fx": Color("#c49bff"), "desc": "Touche automatiquement la cible."},
			{"id": "boule", "name": "Boule de feu", "type": "aoe", "range": 8, "radius": 1, "dc": 14, "half": true,
				"dmg": "4d6", "cd": 4, "fx": Color("#ff5a1a"), "onHit": {"status": "burn", "turns": 2, "chance": 1.0},
				"desc": "Explosion 3×3. Sauvegarde Dex DD 14 pour moitié. Touche aussi les alliés !"},
			DASH,
		],
		"powers": [
			{"id": "givre", "name": "Rayon de givre", "type": "attack", "range": 7, "hit": 6, "dmg": "1d8+2", "cd": 2,
				"fx": Color("#9be8ff"), "onHit": {"status": "slow", "turns": 2, "chance": 1.0},
				"desc": "Ralentit la cible pendant 2 tours."},
			{"id": "chaine", "name": "Chaîne d'éclairs", "type": "chain", "range": 7, "hit": 6, "dmg": "2d6+2", "bounces": 2, "cd": 3,
				"fx": Color("#8ad0ff"), "desc": "Frappe une cible puis rebondit sur 2 ennemis proches."},
			{"id": "arcane", "name": "Bouclier arcanique", "type": "shield", "range": 0, "amount": 12, "cd": 4, "bonus": true,
				"desc": "Action bonus : un bouclier de 12 PV te protège."},
		],
	},
	"rodeur": {
		"name": "Rôdeur", "hp": 26, "hp_lvl": 6, "ac": 15, "speed": 6, "dex": 3,
		"desc": "Archer d'élite, rapide et précis. Il harcèle l'ennemi depuis l'arrière.",
		"abilities": [
			{"id": "arc", "name": "Arc long", "type": "attack", "range": 10, "hit": 6, "dmg": "1d8+3",
				"fx": Color("#d9c38a"), "desc": "Attaque à distance."},
			{"id": "precis", "name": "Tir précis", "type": "attack", "range": 12, "hit": 9, "dmg": "2d8+3", "cd": 2,
				"fx": Color("#ffe28a"), "desc": "Tir ajusté : +3 au toucher, dégâts doublés."},
			{"id": "pluie", "name": "Pluie de flèches", "type": "aoeAttack", "range": 9, "radius": 1, "hit": 6, "dmg": "1d8+2",
				"cd": 4, "fx": Color("#d9c38a"), "desc": "Un jet d'attaque contre chaque ennemi dans une zone 3×3."},
			DASH,
		],
		"powers": [
			{"id": "paralysant", "name": "Tir paralysant", "type": "attack", "range": 10, "hit": 6, "dmg": "1d6+2", "cd": 3,
				"fx": Color("#c0ff80"), "onHit": {"status": "stun", "turns": 1, "chance": 0.6},
				"desc": "60 % de chances d'étourdir la cible."},
			{"id": "cote", "name": "Pas de côté", "type": "dash", "amount": 3, "cd": 2, "bonus": true,
				"desc": "Action bonus : +3 cases de déplacement."},
			{"id": "explosive", "name": "Flèche explosive", "type": "aoe", "range": 10, "radius": 1, "dc": 13, "half": true,
				"dmg": "3d6", "cd": 4, "fx": Color("#ffb040"), "desc": "Explosion 3×3 (Dex DD 13 pour moitié). Touche aussi les alliés."},
		],
	},
	"clerc": {
		"name": "Clerc", "hp": 26, "hp_lvl": 6, "ac": 16, "speed": 5, "dex": 0,
		"desc": "Soigneur divin. Il peut relever les alliés tombés au combat.",
		"abilities": [
			{"id": "masse", "name": "Masse d'armes", "type": "attack", "range": 1, "hit": 4, "dmg": "1d8+2",
				"desc": "Attaque au corps à corps."},
			{"id": "flamme", "name": "Flamme sacrée", "type": "save", "range": 6, "dc": 13, "dmg": "2d8",
				"fx": Color("#fff1a8"), "desc": "Sauvegarde Dex DD 13 ou subit des dégâts radiants."},
			{"id": "soin", "name": "Soin", "type": "heal", "range": 5, "heal": "2d8+3", "cd": 2, "bonus": true,
				"fx": Color("#7dffa8"), "desc": "Action bonus : soigne un allié (ou toi-même). Relève un allié inconscient."},
			{"id": "priere", "name": "Prière de guérison", "type": "massheal", "radius": 3, "heal": "1d8+3", "cd": 5,
				"desc": "Soigne tous les alliés à 3 cases ou moins."},
			DASH,
		],
		"powers": [
			{"id": "foi", "name": "Bouclier de la foi", "type": "shield", "range": 5, "amount": 10, "cd": 3, "bonus": true,
				"fx": Color("#fff1a8"), "desc": "Action bonus : un allié gagne un bouclier de 10 PV."},
			{"id": "purification", "name": "Purification", "type": "cleanse", "range": 5, "heal": "1d8+2", "cd": 2,
				"desc": "Retire poison, brûlure et ralentissement d'un allié et le soigne un peu."},
			{"id": "chatiment", "name": "Châtiment", "type": "attack", "range": 1, "hit": 5, "dmg": "3d8+2", "cd": 3,
				"desc": "Un coup de masse béni : dégâts radiants massifs."},
		],
	},
	"voleur": {
		"name": "Voleur", "hp": 22, "hp_lvl": 5, "ac": 14, "speed": 7, "dex": 4,
		"desc": "Très mobile. Attaque sournoise (+2d6) quand un allié est au contact de la cible.",
		"abilities": [
			{"id": "dague", "name": "Dague", "type": "attack", "range": 1, "hit": 6, "dmg": "1d6+4", "sneak": true,
				"desc": "Corps à corps. Attaque sournoise possible."},
			{"id": "lancer", "name": "Couteau de lancer", "type": "attack", "range": 5, "hit": 6, "dmg": "1d4+4",
				"sneak": true, "fx": Color("#cfd6e0"), "desc": "Distance courte. Attaque sournoise possible."},
			{"id": "ombre", "name": "Pas de l'ombre", "type": "teleport", "range": 6, "cd": 3, "bonus": true,
				"desc": "Action bonus : téléportation sur une case visible à 6 cases."},
			DASH,
		],
		"powers": [
			{"id": "poison", "name": "Lame empoisonnée", "type": "attack", "range": 1, "hit": 6, "dmg": "1d6+2", "cd": 3, "sneak": true,
				"onHit": {"status": "poison", "turns": 3, "chance": 1.0}, "desc": "Empoisonne la cible pendant 3 tours."},
			{"id": "assassinat", "name": "Assassinat", "type": "attack", "range": 1, "hit": 6, "dmg": "1d6+4", "cd": 4, "execute": "4d6",
				"desc": "+4d6 dégâts si la cible a moins de la moitié de ses PV."},
			{"id": "fumigene", "name": "Bombe fumigène", "type": "aoe", "range": 5, "radius": 1, "dc": 13, "half": false,
				"dmg": "1d4", "cd": 4, "bonus": true, "onHit": {"status": "slow", "turns": 2, "chance": 1.0},
				"desc": "Action bonus : ralentit les ennemis dans une zone 3×3 (Dex DD 13)."},
		],
	},
}

# ---------------------------------------------------------------------------
# États
# ---------------------------------------------------------------------------
var STATUS := {
	"poison": {"name": "Empoisonné", "color": Color("#7ad04a"), "desc": "3 dégâts au début du tour."},
	"burn": {"name": "En feu", "color": Color("#ff7a2a"), "desc": "1d6 dégâts au début du tour."},
	"slow": {"name": "Ralenti", "color": Color("#9be8ff"), "desc": "Vitesse divisée par 2."},
	"stun": {"name": "Étourdi", "color": Color("#ffe066"), "desc": "Perd son prochain tour."},
	"force": {"name": "Force", "color": Color("#ff5050"), "desc": "+3 dégâts."},
}

# ---------------------------------------------------------------------------
# Monstres (stats de base, l'acte les renforce)
# "sprite" (optionnel) : nom de l'image à utiliser, sinon la clé du monstre.
# ---------------------------------------------------------------------------
var MONSTERS := {
	"gobelin": {"name": "Gobelin", "hp": 9, "ac": 13, "speed": 6, "dex": 2, "xp": 3, "gold": 3,
		"attack": {"id": "cimeterre", "name": "Cimeterre", "type": "attack", "range": 1, "hit": 4, "dmg": "1d6+2"}},
	"archer": {"name": "Archer gobelin", "hp": 8, "ac": 12, "speed": 6, "dex": 2, "xp": 3, "gold": 3,
		"attack": {"id": "arcCourt", "name": "Arc court", "type": "attack", "range": 8, "hit": 4, "dmg": "1d6+2", "fx": Color("#c9b27a")}},
	"squelette": {"name": "Squelette", "hp": 14, "ac": 13, "speed": 5, "dex": 2, "xp": 4, "gold": 2,
		"attack": {"id": "epeeCourte", "name": "Épée rouillée", "type": "attack", "range": 1, "hit": 4, "dmg": "1d6+2"}},
	"loup": {"name": "Loup", "hp": 12, "ac": 13, "speed": 8, "dex": 2, "xp": 4, "gold": 1,
		"attack": {"id": "morsure", "name": "Morsure", "type": "attack", "range": 1, "hit": 4, "dmg": "2d4+2"}},
	"orc": {"name": "Orc", "hp": 19, "ac": 13, "speed": 5, "dex": 1, "xp": 7, "gold": 6,
		"attack": {"id": "hache", "name": "Grande hache", "type": "attack", "range": 1, "hit": 5, "dmg": "1d12+3"}},
	"chaman": {"name": "Chaman gobelin", "hp": 14, "ac": 12, "speed": 5, "dex": 1, "xp": 6, "gold": 6,
		"attack": {"id": "eclair", "name": "Éclair", "type": "attack", "range": 7, "hit": 5, "dmg": "1d10+1", "fx": Color("#8ad0ff")},
		"heal": {"id": "soinNoir", "name": "Soin impie", "type": "heal", "range": 6, "heal": "2d6+2", "fx": Color("#b07dff")}},
	"araignee": {"name": "Araignée géante", "hp": 18, "ac": 13, "speed": 6, "dex": 3, "xp": 7, "gold": 4,
		"attack": {"id": "crochets", "name": "Crochets venimeux", "type": "attack", "range": 1, "hit": 5, "dmg": "1d8+2",
			"onHit": {"status": "poison", "turns": 3, "chance": 1.0}}},
	"spectre": {"name": "Spectre", "hp": 20, "ac": 12, "speed": 6, "dex": 2, "xp": 8, "gold": 5,
		"attack": {"id": "glacial", "name": "Toucher glacial", "type": "attack", "range": 1, "hit": 5, "dmg": "2d6+1",
			"onHit": {"status": "slow", "turns": 2, "chance": 1.0}}},
	"diablotin": {"name": "Diablotin", "hp": 12, "ac": 13, "speed": 7, "dex": 3, "xp": 6, "gold": 5,
		"attack": {"id": "flammeche", "name": "Flammèche", "type": "attack", "range": 6, "hit": 5, "dmg": "1d8+2", "fx": Color("#ff7a2a"),
			"onHit": {"status": "burn", "turns": 2, "chance": 0.3}}},
	"elementaire": {"name": "Élémentaire de feu", "hp": 26, "ac": 13, "speed": 5, "dex": 1, "xp": 9, "gold": 6, "immune": ["burn"],
		"attack": {"id": "embrasement", "name": "Embrasement", "type": "attack", "range": 1, "hit": 6, "dmg": "2d6+2",
			"onHit": {"status": "burn", "turns": 2, "chance": 0.5}}},
	"cultiste": {"name": "Cultiste", "hp": 16, "ac": 12, "speed": 5, "dex": 1, "xp": 8, "gold": 8,
		"attack": {"id": "ombre", "name": "Trait d'ombre", "type": "attack", "range": 7, "hit": 5, "dmg": "1d10+2", "fx": Color("#b07dff")},
		"heal": {"id": "rituel", "name": "Rituel de sang", "type": "heal", "range": 6, "heal": "2d6+3", "fx": Color("#e04040")}},
	"salamandre": {"name": "Salamandre", "hp": 22, "ac": 14, "speed": 6, "dex": 2, "xp": 8, "gold": 5, "immune": ["burn"],
		"attack": {"id": "morsureBrulante", "name": "Morsure brûlante", "type": "attack", "range": 1, "hit": 6, "dmg": "1d10+3",
			"onHit": {"status": "burn", "turns": 2, "chance": 0.3}}},
	"mimique": {"name": "Mimique", "hp": 32, "ac": 14, "speed": 4, "dex": 1, "xp": 15, "gold": 50,
		"attack": {"id": "machoire", "name": "Mâchoire", "type": "attack", "range": 1, "hit": 6, "dmg": "2d8+3"}},
	"phylactere": {"name": "Phylactère", "hp": 30, "ac": 10, "speed": 0, "dex": -5, "xp": 5, "gold": 0, "object": true,
		"attack": {}},

	# ---- Boss : leurs mécaniques spéciales sont dans combat.gd (section « Boss ») ----
	"ogre": {"name": "Ogre des Cryptes", "hp": 95, "ac": 13, "speed": 5, "dex": -1, "xp": 40, "gold": 60, "boss": true,
		"mechanics": ["rage", "seisme"],
		"attack": {"id": "massue", "name": "Massue géante", "type": "attack", "range": 1, "hit": 7, "dmg": "2d8+5",
			"onHit": {"status": "stun", "turns": 1, "chance": 0.25}}},
	"liche": {"name": "La Liche", "hp": 115, "ac": 15, "speed": 4, "dex": 1, "xp": 60, "gold": 100, "boss": true,
		"mechanics": ["phylactere", "invocation", "clignement"],
		"attack": {"id": "rayonMort", "name": "Rayon nécrotique", "type": "attack", "range": 8, "hit": 7, "dmg": "2d8+3",
			"fx": Color("#b07dff"), "onHit": {"status": "slow", "turns": 1, "chance": 0.5}}},
	"dragon": {"name": "Le Dragon rouge", "hp": 170, "ac": 16, "speed": 5, "dex": 0, "xp": 100, "gold": 200, "boss": true,
		"immune": ["burn"], "mechanics": ["souffle", "queue", "envol"],
		"attack": {"id": "griffes", "name": "Griffes", "type": "attack", "range": 1, "hit": 8, "dmg": "2d10+4"}},
}

## Description des mécaniques de boss (affichée en début de combat et dans l'info-bulle)
var MECHANICS := {
	"rage": "Rage : sous 50 % de PV, il frappe deux fois par tour.",
	"seisme": "Séisme : tous les 3 tours, il frappe le sol. Les cases marquées en rouge explosent au tour suivant !",
	"phylactere": "Phylactères : invulnérable tant que ses cristaux sont debout. Détruisez-les !",
	"invocation": "Invocation : tous les 3 tours, deux squelettes se relèvent.",
	"clignement": "Clignement : si on la colle, elle se téléporte au loin.",
	"souffle": "Souffle de feu : il prépare une ligne de flammes (cases rouges) qui frappe au tour suivant. Écartez-vous !",
	"queue": "Coup de queue : frappe tous les héros au contact.",
	"envol": "À mi-vie, il s'envole : des élémentaires de feu surgissent et le sol s'embrase.",
}

## Traits des monstres d'élite
var ELITE_TRAITS := [
	{"id": "enrage", "name": "Enragé", "desc": "+2 toucher, +3 dégâts", "mods": {"hit": 2, "dmg": 3}},
	{"id": "blinde", "name": "Blindé", "desc": "+3 CA", "mods": {"ac": 3}},
	{"id": "vampire", "name": "Vampirique", "desc": "Se soigne de la moitié des dégâts infligés", "mods": {"lifesteal": 0.5}},
	{"id": "rapide", "name": "Rapide", "desc": "+3 vitesse", "mods": {"speed": 3}},
	{"id": "geant", "name": "Géant", "desc": "PV doublés", "mods": {"hp_mult": 2.0}},
]

# ---------------------------------------------------------------------------
# Actes : chacun a son biome (carte), ses monstres et son boss
# ---------------------------------------------------------------------------
var ACTS := [
	{"name": "Les Cryptes", "biome": "crypte", "rows": 6,
		"pool": [["gobelin", 1.0], ["archer", 1.0], ["squelette", 1.5], ["loup", 1.5], ["chaman", 2.0]],
		"budget_base": 4.5, "budget_row": 0.6, "elites": ["orc", "squelette", "loup"],
		"boss": "ogre", "escort": ["gobelin", "gobelin", "archer"],
		"intro": "Des couloirs de pierre humides, éclairés par quelques torches. Quelque chose de lourd respire au fond…"},
	{"name": "La Forêt maudite", "biome": "foret", "rows": 6,
		"pool": [["loup", 1.5], ["araignee", 2.0], ["archer", 1.0], ["spectre", 2.5], ["chaman", 2.0]],
		"budget_base": 6.5, "budget_row": 0.7, "elites": ["araignee", "spectre", "loup"],
		"boss": "liche", "escort": ["squelette", "squelette"],
		"intro": "Les arbres murmurent, une brume verdâtre rampe entre les racines. Une magie morte imprègne la forêt."},
	{"name": "Le Cœur du Volcan", "biome": "volcan", "rows": 6,
		"pool": [["diablotin", 1.5], ["salamandre", 2.0], ["cultiste", 2.0], ["elementaire", 2.5], ["orc", 2.0]],
		"budget_base": 8.0, "budget_row": 0.8, "elites": ["elementaire", "salamandre", "orc"],
		"boss": "dragon", "escort": ["diablotin", "diablotin"],
		"intro": "La chaleur est étouffante. Des rivières de lave éclairent la roche noire. Le dragon vous attend."},
]

## Expérience totale nécessaire pour chaque niveau (index = niveau)
const LEVEL_XP := [0, 0, 16, 40, 72, 112, 165, 230, 305, 390, 480, 580]

## Salles de la carte de parcours
var NODE_TYPES := {
	"combat": {"name": "Combat", "letter": "C", "color": Color("#c8b8a0"), "desc": "Une salle gardée par des monstres."},
	"elite": {"name": "Élite", "letter": "E", "color": Color("#c86bff"), "desc": "Un monstre redoutable… et un meilleur butin."},
	"event": {"name": "Mystère", "letter": "?", "color": Color("#8ad0ff"), "desc": "Qui sait ce qui vous attend ?"},
	"shop": {"name": "Marchand", "letter": "$", "color": Color("#e3b95f"), "desc": "Dépensez votre or."},
	"treasure": {"name": "Trésor", "letter": "T", "color": Color("#5fe08d"), "desc": "Un coffre vous attend."},
	"camp": {"name": "Feu de camp", "letter": "F", "color": Color("#ff8a40"), "desc": "Se reposer ou s'entraîner."},
	"boss": {"name": "Boss", "letter": "B", "color": Color("#e05050"), "desc": "Le maître des lieux."},
}

# ---------------------------------------------------------------------------
# Équipement : 3 emplacements par héros (arme, armure, accessoire)
# mods possibles : hit, dmg, ac, hp, speed, range, crit, lifesteal, regen, thorns, heal, cdr, radius, init, resist (liste d'états)
# ---------------------------------------------------------------------------
const SLOTS := {"arme": "Arme", "armure": "Armure", "accessoire": "Accessoire"}

var ITEMS := {
	# Armes
	"lame": {"name": "Lame affûtée", "slot": "arme", "rarity": 1, "desc": "+2 dégâts", "mods": {"dmg": 2}},
	"runique": {"name": "Arme runique", "slot": "arme", "rarity": 2, "desc": "+1 toucher, +2 dégâts", "mods": {"hit": 1, "dmg": 2}},
	"croc": {"name": "Croc de vampire", "slot": "arme", "rarity": 2, "desc": "+1 dégât, vol de vie 20 %", "mods": {"dmg": 1, "lifesteal": 0.2}},
	"bourreau": {"name": "Lame du bourreau", "slot": "arme", "rarity": 2, "desc": "Critique sur 19-20, +1 dégât", "mods": {"crit": 1, "dmg": 1}},
	"faucon": {"name": "Arc du faucon", "slot": "arme", "rarity": 2, "desc": "+2 portée, +1 toucher", "mods": {"range": 2, "hit": 1}},
	"archimage": {"name": "Bâton de l'archimage", "slot": "arme", "rarity": 3, "desc": "+3 dégâts, zones plus grandes", "mods": {"dmg": 3, "radius": 1}},
	"tueuse": {"name": "Tueuse de dragons", "slot": "arme", "rarity": 3, "desc": "+2 toucher, +4 dégâts", "mods": {"hit": 2, "dmg": 4}},
	# Armures
	"cuir": {"name": "Cuir renforcé", "slot": "armure", "rarity": 1, "desc": "+1 CA", "mods": {"ac": 1}},
	"mailles": {"name": "Cotte de mailles", "slot": "armure", "rarity": 2, "desc": "+2 CA", "mods": {"ac": 2}},
	"epines": {"name": "Cape d'épines", "slot": "armure", "rarity": 2, "desc": "+1 CA, renvoie 3 dégâts au contact", "mods": {"ac": 1, "thorns": 3}},
	"robe": {"name": "Robe de régénération", "slot": "armure", "rarity": 2, "desc": "Récupère 2 PV par tour", "mods": {"regen": 2}},
	"mithril": {"name": "Cotte de mithril", "slot": "armure", "rarity": 3, "desc": "+2 CA, +8 PV max", "mods": {"ac": 2, "hp": 8}},
	"ecailles": {"name": "Armure d'écailles de dragon", "slot": "armure", "rarity": 3, "desc": "+3 CA, insensible au feu", "mods": {"ac": 3, "resist": ["burn"]}},
	# Accessoires
	"amulette": {"name": "Amulette de vitalité", "slot": "accessoire", "rarity": 1, "desc": "+8 PV max", "mods": {"hp": 8}},
	"bottes": {"name": "Bottes de célérité", "slot": "accessoire", "rarity": 1, "desc": "+1 vitesse, +3 initiative", "mods": {"speed": 1, "init": 3}},
	"trefle": {"name": "Trèfle à quatre feuilles", "slot": "accessoire", "rarity": 2, "desc": "Critique sur 19-20", "mods": {"crit": 1}},
	"purete": {"name": "Talisman de pureté", "slot": "accessoire", "rarity": 2, "desc": "Insensible au poison et au ralentissement", "mods": {"resist": ["poison", "slow"]}},
	"flamme": {"name": "Pendentif de flamme froide", "slot": "accessoire", "rarity": 2, "desc": "Insensible au feu, +4 PV max", "mods": {"resist": ["burn"], "hp": 4}},
	"sablier": {"name": "Sablier arcanique", "slot": "accessoire", "rarity": 3, "desc": "Temps de recharge −1", "mods": {"cdr": 1}},
	"phenix": {"name": "Plume de phénix", "slot": "accessoire", "rarity": 3, "desc": "+4 aux soins, +1 PV par tour", "mods": {"heal": 4, "regen": 1}},
}

## Potions (inventaire commun du groupe, utilisables en combat)
var POTIONS := {
	"soin": {"id": "pot_soin", "name": "Potion de soin", "type": "selfheal", "heal": "2d8+4", "bonus": true, "price": 25,
		"desc": "Action bonus : récupère 2d8+4 PV."},
	"feu": {"id": "pot_feu", "name": "Fiole de feu", "type": "aoe", "range": 5, "radius": 1, "dc": 13, "half": true,
		"dmg": "3d6", "price": 30, "fx": Color("#ff7a2a"), "onHit": {"status": "burn", "turns": 2, "chance": 1.0},
		"desc": "Action : explosion 3×3 (3d6, Dex DD 13 pour moitié)."},
	"vitesse": {"id": "pot_vitesse", "name": "Élixir de vitesse", "type": "dash", "amount": 4, "bonus": true, "price": 20,
		"desc": "Action bonus : +4 cases de déplacement."},
	"antidote": {"id": "pot_antidote", "name": "Antidote", "type": "cleanse", "range": 0, "heal": "1d4+2", "bonus": true, "price": 15,
		"desc": "Action bonus : retire poison, brûlure et ralentissement, +1d4+2 PV."},
	"force": {"id": "pot_force", "name": "Élixir de force", "type": "buff", "radius": 0, "status": "force", "turns": 3, "bonus": true, "price": 25,
		"desc": "Action bonus : Force (+3 dégâts) pendant 3 tours."},
}
const MAX_POTIONS := 6

# ---------------------------------------------------------------------------
# Talents passifs (choix à la montée de niveau, avec les pouvoirs de classe)
# ---------------------------------------------------------------------------
var TALENTS := [
	{"id": "robuste", "name": "Robustesse", "desc": "+8 PV max", "mods": {"hp": 8}},
	{"id": "precision", "name": "Précision", "desc": "+1 au toucher", "mods": {"hit": 1}},
	{"id": "brutal", "name": "Brutalité", "desc": "+2 dégâts", "mods": {"dmg": 2}},
	{"id": "vigilance", "name": "Vigilance", "desc": "+1 CA", "mods": {"ac": 1}},
	{"id": "agile", "name": "Agilité", "desc": "+1 vitesse, +3 initiative", "mods": {"speed": 1, "init": 3}},
	{"id": "vent", "name": "Second vent", "desc": "Récupère 1 PV au début de chaque tour", "mods": {"regen": 1}},
	{"id": "fer", "cls": "guerrier", "name": "Peau de fer", "desc": "+2 CA", "mods": {"ac": 2}},
	{"id": "sang", "cls": "guerrier", "name": "Soif de sang", "desc": "Vol de vie 25 %", "mods": {"lifesteal": 0.25}},
	{"id": "pyro", "cls": "mage", "name": "Pyromane", "desc": "Zones plus grandes (+1 rayon)", "mods": {"radius": 1}},
	{"id": "arcaniste", "cls": "mage", "name": "Arcaniste", "desc": "Temps de recharge −1", "mods": {"cdr": 1}},
	{"id": "aigle", "cls": "rodeur", "name": "Œil d'aigle", "desc": "+3 portée", "mods": {"range": 3}},
	{"id": "mortel", "cls": "rodeur", "name": "Tir mortel", "desc": "Critique sur 18-20", "mods": {"crit": 2}},
	{"id": "benediction", "cls": "clerc", "name": "Bénédiction", "desc": "+5 aux soins", "mods": {"heal": 5}},
	{"id": "zele", "cls": "clerc", "name": "Zèle", "desc": "+2 toucher, +2 dégâts", "mods": {"hit": 2, "dmg": 2}},
	{"id": "esquive", "cls": "voleur", "name": "Esquive", "desc": "+2 CA", "mods": {"ac": 2}},
	{"id": "opportuniste", "cls": "voleur", "name": "Opportuniste", "desc": "Critique sur 19-20, +1 vitesse", "mods": {"crit": 1, "speed": 1}},
]

# ---------------------------------------------------------------------------
# Événements mystères
# Effets possibles : damage (PV perdus par héros), heal_pct, gold, xp, potions (liste),
# random_potion, item (rareté), fight (monstre), gamble (mise)
# ---------------------------------------------------------------------------
var EVENTS := [
	{"title": "Autel ensanglanté",
		"text": "Un autel couvert de runes pulse d'une lueur rouge. Une voix murmure : « Offre ton sang, reçois ma puissance. »",
		"choices": [
			{"label": "Offrir son sang (−8 PV par héros, objet rare)", "effects": {"damage": 8, "item": 2},
				"result": "Le sang coule… et un objet apparaît sur l'autel."},
			{"label": "Partir", "effects": {}, "result": "Vous vous éloignez prudemment."},
		]},
	{"title": "Fontaine claire",
		"text": "Une fontaine d'eau pure jaillit entre les pierres. Elle semble bénie.",
		"choices": [
			{"label": "Boire (soigne 50 % des PV de chacun)", "effects": {"heal_pct": 0.5}, "result": "L'eau fraîche ravive vos forces."},
			{"label": "Remplir des fioles (+2 potions de soin)", "effects": {"potions": ["soin", "soin"]}, "result": "Vous remplissez deux fioles."},
		]},
	{"title": "Coffre suspect",
		"text": "Un coffre richement décoré trône au milieu de la pièce. Trop beau pour être vrai ?",
		"choices": [
			{"label": "L'ouvrir", "effects": {"mimic": 0.45, "gold": 60}, "result": "Le coffre contenait 60 pièces d'or !"},
			{"label": "Le laisser", "effects": {}, "result": "Mieux vaut ne pas tenter le diable."},
		]},
	{"title": "Le joueur de dés",
		"text": "Un vieil homme encapuchonné agite des dés en os. « Une partie ? Double ou rien, 30 pièces d'or. »",
		"choices": [
			{"label": "Jouer (30 or)", "need_gold": 30, "effects": {"gamble": 30}, "result": ""},
			{"label": "Refuser", "effects": {}, "result": "« Dommage… » ricane-t-il."},
		]},
	{"title": "Aventurier blessé",
		"text": "Un aventurier agonise contre un mur. « Prenez… mon équipement… vengez-moi… »",
		"choices": [
			{"label": "Prendre son équipement", "effects": {"item": 1}, "result": "Vous récupérez son équipement."},
			{"label": "Le soigner (−1 potion de soin, +50 or)", "need_potion": "soin", "effects": {"use_potion": "soin", "gold": 50},
				"result": "Il survit et vous remercie avec sa bourse."},
		]},
	{"title": "Bibliothèque oubliée",
		"text": "Des grimoires poussiéreux couvrent les étagères. Leur savoir pourrait vous être utile.",
		"choices": [
			{"label": "Étudier (+20 XP)", "effects": {"xp": 20}, "result": "Vous apprenez des techniques oubliées."},
			{"label": "Fouiller (+1 potion au hasard)", "effects": {"random_potion": 1}, "result": "Vous trouvez une potion."},
		]},
]
