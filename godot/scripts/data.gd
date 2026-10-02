extends Node
## Toutes les données du jeu : classes, monstres et niveaux.
## Ce script est chargé automatiquement (autoload) sous le nom « Data ».
## Pour équilibrer le jeu, c'est ici qu'il faut changer les chiffres.
##
## Types de capacités :
##   attack    : jet d'attaque (d20 + bonus) contre la CA d'un ennemi
##   autohit   : dégâts automatiques sur un ennemi
##   save      : l'ennemi fait un jet de sauvegarde (DD) ou subit les dégâts
##   aoe       : zone (rayon) — jets de sauvegarde, touche AUSSI les alliés
##   aoeAttack : zone — un jet d'attaque par ennemi dans la zone
##   whirlwind : un jet d'attaque contre chaque ennemi adjacent
##   heal      : soigne un allié (ou soi-même) à portée
##   massheal  : soigne tous les alliés dans un rayon autour du lanceur
##   selfheal  : se soigne soi-même
##   teleport  : se déplace instantanément sur une case visible
##   dash      : double le déplacement pour ce tour
## "bonus": true => utilise l'action bonus au lieu de l'action principale.
## "cd" = nombre de tours avant de pouvoir réutiliser la capacité.

const DASH := {
	"id": "foncer", "name": "Foncer", "type": "dash", "cd": 0,
	"desc": "Utilise ton action pour gagner un déplacement supplémentaire égal à ta vitesse.",
}

var CLASSES := {
	"guerrier": {
		"name": "Guerrier", "hp": 34, "hp_lvl": 9, "ac": 17, "speed": 5, "dex": 1,
		"desc": "Robuste et redoutable au corps à corps. Il encaisse les coups en première ligne.",
		"abilities": [
			{"id": "epee", "name": "Coup d'épée", "type": "attack", "range": 1, "hit": 5, "dmg": "1d10+3", "cd": 0,
				"desc": "Attaque au corps à corps."},
			{"id": "tourbillon", "name": "Tourbillon", "type": "whirlwind", "range": 1, "hit": 5, "dmg": "1d8+3", "cd": 3,
				"desc": "Attaque tous les ennemis adjacents."},
			{"id": "souffle", "name": "Second souffle", "type": "selfheal", "heal": "1d10+4", "cd": 4, "bonus": true,
				"desc": "Action bonus : récupère des points de vie."},
			DASH,
		],
	},
	"mage": {
		"name": "Mage", "hp": 18, "hp_lvl": 5, "ac": 12, "speed": 5, "dex": 2,
		"desc": "Fragile mais dévastateur à distance. Attention : la boule de feu brûle aussi les alliés !",
		"abilities": [
			{"id": "trait", "name": "Trait de feu", "type": "attack", "range": 8, "hit": 6, "dmg": "1d10+2", "cd": 0,
				"fx": Color("#ff7a2a"), "desc": "Attaque magique à distance."},
			{"id": "projectile", "name": "Projectile magique", "type": "autohit", "range": 10, "dmg": "3d4+3", "cd": 2,
				"fx": Color("#c49bff"), "desc": "Touche automatiquement la cible."},
			{"id": "boule", "name": "Boule de feu", "type": "aoe", "range": 8, "radius": 1, "dc": 14, "half": true,
				"dmg": "4d6", "cd": 4, "fx": Color("#ff5a1a"),
				"desc": "Explosion 3×3. Sauvegarde Dex DD 14 pour moitié. Touche aussi les alliés !"},
			DASH,
		],
	},
	"rodeur": {
		"name": "Rôdeur", "hp": 26, "hp_lvl": 7, "ac": 15, "speed": 6, "dex": 3,
		"desc": "Archer d'élite, rapide et précis. Il harcèle l'ennemi depuis l'arrière.",
		"abilities": [
			{"id": "arc", "name": "Arc long", "type": "attack", "range": 10, "hit": 6, "dmg": "1d8+3", "cd": 0,
				"fx": Color("#d9c38a"), "desc": "Attaque à distance."},
			{"id": "precis", "name": "Tir précis", "type": "attack", "range": 12, "hit": 9, "dmg": "2d8+3", "cd": 2,
				"fx": Color("#ffe28a"), "desc": "Tir ajusté : +3 au toucher, dégâts doublés."},
			{"id": "pluie", "name": "Pluie de flèches", "type": "aoeAttack", "range": 9, "radius": 1, "hit": 6, "dmg": "1d8+2",
				"cd": 4, "fx": Color("#d9c38a"), "desc": "Un jet d'attaque contre chaque ennemi dans une zone 3×3."},
			DASH,
		],
	},
	"clerc": {
		"name": "Clerc", "hp": 26, "hp_lvl": 7, "ac": 16, "speed": 5, "dex": 0,
		"desc": "Soigneur divin. Il peut relever les alliés tombés au combat.",
		"abilities": [
			{"id": "masse", "name": "Masse d'armes", "type": "attack", "range": 1, "hit": 4, "dmg": "1d8+2", "cd": 0,
				"desc": "Attaque au corps à corps."},
			{"id": "flamme", "name": "Flamme sacrée", "type": "save", "range": 6, "dc": 13, "dmg": "2d8", "cd": 0,
				"fx": Color("#fff1a8"), "desc": "Sauvegarde Dex DD 13 ou subit des dégâts radiants."},
			{"id": "soin", "name": "Soin", "type": "heal", "range": 5, "heal": "2d8+3", "cd": 2, "bonus": true,
				"fx": Color("#7dffa8"), "desc": "Action bonus : soigne un allié (ou toi-même). Relève un allié inconscient."},
			{"id": "priere", "name": "Prière de guérison", "type": "massheal", "radius": 3, "heal": "1d8+3", "cd": 5,
				"desc": "Soigne tous les alliés à 3 cases ou moins."},
			DASH,
		],
	},
	"voleur": {
		"name": "Voleur", "hp": 22, "hp_lvl": 6, "ac": 14, "speed": 7, "dex": 4,
		"desc": "Très mobile. Attaque sournoise (+2d6) quand un allié est au contact de la cible.",
		"abilities": [
			{"id": "dague", "name": "Dague", "type": "attack", "range": 1, "hit": 6, "dmg": "1d6+4", "cd": 0, "sneak": true,
				"desc": "Corps à corps. Attaque sournoise possible."},
			{"id": "lancer", "name": "Couteau de lancer", "type": "attack", "range": 5, "hit": 6, "dmg": "1d4+4", "cd": 0,
				"sneak": true, "fx": Color("#cfd6e0"), "desc": "Distance courte. Attaque sournoise possible."},
			{"id": "ombre", "name": "Pas de l'ombre", "type": "teleport", "range": 6, "cd": 3, "bonus": true,
				"desc": "Action bonus : téléportation sur une case visible à 6 cases."},
			DASH,
		],
	},
}

## "sprite" (optionnel) : nom de l'image à utiliser, sinon la clé du monstre.
var MONSTERS := {
	"gobelin": {"name": "Gobelin", "hp": 9, "ac": 13, "speed": 6, "dex": 2,
		"attack": {"id": "cimeterre", "name": "Cimeterre", "type": "attack", "range": 1, "hit": 4, "dmg": "1d6+2"}},
	"archer": {"name": "Archer gobelin", "hp": 8, "ac": 12, "speed": 6, "dex": 2,
		"attack": {"id": "arcCourt", "name": "Arc court", "type": "attack", "range": 8, "hit": 4, "dmg": "1d6+2", "fx": Color("#c9b27a")}},
	"squelette": {"name": "Squelette", "hp": 14, "ac": 13, "speed": 5, "dex": 2,
		"attack": {"id": "epeeCourte", "name": "Épée rouillée", "type": "attack", "range": 1, "hit": 4, "dmg": "1d6+2"}},
	"loup": {"name": "Loup", "hp": 12, "ac": 13, "speed": 8, "dex": 2,
		"attack": {"id": "morsure", "name": "Morsure", "type": "attack", "range": 1, "hit": 4, "dmg": "2d4+2"}},
	"orc": {"name": "Orc", "hp": 17, "ac": 13, "speed": 5, "dex": 1,
		"attack": {"id": "hache", "name": "Grande hache", "type": "attack", "range": 1, "hit": 5, "dmg": "1d12+3"}},
	"chaman": {"name": "Chaman gobelin", "hp": 14, "ac": 12, "speed": 5, "dex": 1,
		"attack": {"id": "eclair", "name": "Éclair", "type": "attack", "range": 7, "hit": 5, "dmg": "1d10+1", "fx": Color("#8ad0ff")},
		"heal": {"id": "soinNoir", "name": "Soin impie", "type": "heal", "range": 6, "heal": "2d6+2", "fx": Color("#b07dff")}},
	"ogre": {"name": "Ogre", "hp": 75, "ac": 12, "speed": 5, "dex": -1, "boss": true,
		"attack": {"id": "massue", "name": "Massue géante", "type": "attack", "range": 1, "hit": 7, "dmg": "2d8+5"}},
}

## Rencontres pour chaque niveau du donjon
var LEVELS := [
	{"name": "L'entrée de la crypte", "monsters": ["gobelin", "gobelin", "gobelin", "archer"]},
	{"name": "Les catacombes", "monsters": ["squelette", "squelette", "loup", "loup", "archer"]},
	{"name": "Le camp des orcs", "monsters": ["orc", "orc", "archer", "archer", "chaman"]},
	{"name": "La fosse aux bêtes", "monsters": ["orc", "orc", "orc", "loup", "loup", "chaman", "squelette"]},
	{"name": "L'antre de l'Ogre", "monsters": ["ogre", "orc", "orc", "gobelin", "archer", "chaman"]},
]
