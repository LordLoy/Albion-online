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
var is_object := false     # phylactère : ne bouge pas, n'attaque pas
var elite: Dictionary = {} # trait d'élite éventuel
var mechanics: Array = []  # mécaniques de boss
var immune: Array = []     # états auxquels l'unité résiste

var abilities: Array = []  # capacités utilisables (héros : classe + pouvoirs appris)
var attack: Dictionary = {} # monstre : son attaque
var heal_ab: Dictionary = {} # monstre : soin éventuel
var cooldowns := {}
var status := {}           # état -> tours restants
var shield := 0            # PV temporaires (absorbent les dégâts)
var mods := {}             # bonus cumulés (objets, talents, traits)
var pos := Vector2i.ZERO
var init := 0.0
var dead := false
var memory := {}           # compteurs utilisés par les boss

# Héros uniquement
var items := {}            # emplacement -> clé d'objet
var talents: Array = []    # ids de talents passifs
var powers: Array = []     # ids de pouvoirs appris

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
	u.dex = c.dex
	u.recalc()
	u.hp = u.max_hp
	return u


## Crée un monstre. act : 0, 1, 2 (les actes suivants le renforcent).
static func make_monster(monster_key: String, act := 0, elite_trait := {}) -> Unit:
	var m: Dictionary = Data.MONSTERS[monster_key]
	var u := Unit.new()
	u.side = "monster"
	u.key = monster_key
	u.sprite = m.get("sprite", monster_key)
	u.name = m.name
	u.boss = m.get("boss", false)
	u.is_object = m.get("object", false)
	u.mechanics = m.get("mechanics", [])
	u.immune = m.get("immune", [])
	u.max_hp = m.hp
	u.ac = m.ac
	u.speed = m.speed
	u.dex = m.dex
	if act > 0 and not u.boss and not u.is_object:
		u.max_hp = roundi(m.hp * (1.0 + 0.25 * act))
		u.mods = {"hit": act, "dmg": act}
	u.attack = m.attack
	u.heal_ab = m.get("heal", {})
	if not elite_trait.is_empty():
		u.elite = elite_trait
		u.name = "%s %s" % [m.name, elite_trait.name.to_lower()]
		u.max_hp = roundi(u.max_hp * 1.6 * elite_trait.mods.get("hp_mult", 1.0))
		u.ac += elite_trait.mods.get("ac", 0)
		u.speed += elite_trait.mods.get("speed", 0)
		u.mods["hit"] = u.mods.get("hit", 0) + 1 + elite_trait.mods.get("hit", 0)
		u.mods["dmg"] = u.mods.get("dmg", 0) + 1 + elite_trait.mods.get("dmg", 0)
		if elite_trait.mods.has("lifesteal"):
			u.mods["lifesteal"] = elite_trait.mods.lifesteal
	u.hp = u.max_hp
	# Capacités utilisables quand un humain contrôle le monstre (mode dieu / futur mode MJ)
	if not u.attack.is_empty():
		u.abilities.append(u.attack)
	if not u.heal_ab.is_empty():
		u.abilities.append(u.heal_ab)
	return u


func _init() -> void:
	id = _next_id
	_next_id += 1


func is_alive() -> bool:
	return not dead and hp > 0


func mod(k: String) -> float:
	var v = mods.get(k, 0)
	return v if (v is float or v is int) else 0.0


## Recalcule les statistiques d'un héros (niveau + objets + talents) et ses capacités.
func recalc() -> void:
	var c: Dictionary = Data.CLASSES[key]
	var total := {}
	var sources: Array = []
	for slot in items:
		sources.append(Data.ITEMS[items[slot]].mods)
	for tid in talents:
		for t in Data.TALENTS:
			if t.id == tid:
				sources.append(t.mods)
	for m in sources:
		for k in m:
			if k == "resist":
				total[k] = total.get(k, []) + m[k]
			else:
				total[k] = total.get(k, 0) + m[k]
	mods = total
	var old_max := max_hp
	max_hp = c.hp + (level - 1) * c.hp_lvl + int(mod("hp"))
	if old_max > 0 and max_hp > old_max:
		hp += max_hp - old_max
	hp = mini(hp, max_hp)
	ac = c.ac + int(mod("ac"))
	speed = c.speed + int(mod("speed"))
	immune = mods.get("resist", [])
	abilities = c.abilities.duplicate()
	for p in c.powers:
		if p.id in powers:
			abilities.insert(abilities.size() - 1, p)   # avant « Foncer »


# --- Bonus utilisés par les règles -----------------------------------------
func hit_bonus() -> int:
	return int(mod("hit")) + ((level - 1) / 3 if side == "hero" else 0)


func dmg_bonus() -> int:
	return int(mod("dmg")) + (3 if status.has("force") else 0)


func heal_bonus() -> int:
	return int(mod("heal"))


func crit_min() -> int:
	return 20 - int(mod("crit"))


func range_of(ab: Dictionary) -> int:
	var r: int = ab.get("range", 0)
	return r + int(mod("range")) if r > 1 and not ab.get("consumable", false) else r


func radius_of(ab: Dictionary) -> int:
	var r: int = ab.get("radius", 0)
	if ab.type in ["aoe", "aoeAttack"] and not ab.get("consumable", false):
		r += int(mod("radius"))
	return r


func cooldown_of(ab: Dictionary) -> int:
	var cd: int = ab.get("cd", 0)
	return maxi(1, cd - int(mod("cdr"))) if cd > 0 else 0
