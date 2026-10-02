class_name Unit
extends RefCounted
## Un personnage sur le plateau : héros ou monstre.

static var _next_id := 1

var id: int
var side: String           # "hero" ou "monster"
var key: String            # clé dans Data.CLASSES ou Data.MONSTERS
var sprite: String         # nom de l'image dans assets/sprites/
var name: String
var max_hp: int
var hp: int
var ac: int
var speed: int
var dex: int
var level := 1
var boss := false
var abilities: Array = []  # héros : liste de capacités
var attack: Dictionary = {} # monstre : son attaque
var heal_ab: Dictionary = {} # monstre : soin éventuel (chaman)
var cooldowns := {}
var pos := Vector2i.ZERO
var init := 0.0
var dead := false

# État du tour en cours
var moves_left := 0
var action_used := false
var bonus_used := false


static func make_hero(class_key: String) -> Unit:
	var c: Dictionary = Data.CLASSES[class_key]
	var u := Unit.new()
	u.side = "hero"
	u.key = class_key
	u.sprite = class_key
	u.name = c.name
	u.max_hp = c.hp
	u.hp = c.hp
	u.ac = c.ac
	u.speed = c.speed
	u.dex = c.dex
	u.abilities = c.abilities
	return u


static func make_monster(monster_key: String, number := 0, bonus_hp := 0) -> Unit:
	var m: Dictionary = Data.MONSTERS[monster_key]
	var u := Unit.new()
	u.side = "monster"
	u.key = monster_key
	u.sprite = m.get("sprite", monster_key)
	u.name = m.name + (" %d" % number if number > 0 else "")
	u.max_hp = m.hp + bonus_hp
	u.hp = u.max_hp
	u.ac = m.ac
	u.speed = m.speed
	u.dex = m.dex
	u.boss = m.get("boss", false)
	u.attack = m.attack
	u.heal_ab = m.get("heal", {})
	# Capacités utilisables quand un humain contrôle le monstre (mode dieu / futur mode MJ)
	u.abilities = [u.attack] + ([u.heal_ab] if not u.heal_ab.is_empty() else [])
	return u


func _init() -> void:
	id = _next_id
	_next_id += 1


func is_alive() -> bool:
	return not dead and hp > 0


## Bonus des héros qui montent de niveau
func hit_bonus() -> int:
	return (level - 1) / 2 if side == "hero" else 0


func dmg_bonus() -> int:
	return level - 1 if side == "hero" else 0
