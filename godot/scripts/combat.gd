class_name Combat
extends Node
## Les règles du combat : tours, initiative, capacités, états, boss et IA des monstres.
##
## Toutes les actions passent par perform(action), un simple Dictionary :
##   {"type": "move", "to": Vector2i}
##   {"type": "ability", "index": int, "target": Vector2i}   (index dans usable_abilities())
##   {"type": "end_turn"}
## Pour le multijoueur, il suffira d'envoyer ces dictionnaires sur le réseau.

signal log_added(bbcode: String)   ## une ligne pour le journal des dés
signal changed                      ## l'état a changé : rafraîchir l'interface
signal ended(win: bool)             ## fin du combat

const MAP_W := 20
const MAP_H := 13

var dungeon: Dungeon
var units: Array[Unit] = []
var heroes: Array[Unit] = []
var order: Array[Unit] = []
var turn_idx := 0
var round_num := 1
var act := 0                ## 0, 1, 2 : renforce les monstres
var encounter := {}         ## description du combat (titre, monstres…)
var potions: Array = []     ## inventaire de potions du groupe (partagé avec la partie)
var kills: Array[Unit] = [] ## monstres vaincus (pour les récompenses)
var telegraphs: Array = []  ## attaques annoncées : {owner, cells, name, dmg, dc, status, fire}
var hazards := {}           ## index de case -> tours de flammes restants
var busy := false           ## animation ou tour de monstre en cours
var over := false
var ability: Dictionary = {}   ## capacité en cours de ciblage
var reach: Dictionary = {}     ## zone de déplacement de l'unité active
var autoplay := false      ## les héros jouent tout seuls (mode démo / tests)
var speed_factor := 1.0    ## accélère les animations (0 = instantané)

var board: Node            ## le plateau (animations)

## Mode dieu (outils de test) — voir la section « Mode dieu » en bas du fichier
var god := {
	"invincible": false,       ## les héros ne prennent aucun dégât
	"free_actions": false,     ## actions, recharges et déplacements illimités
	"control_monsters": false, ## c'est toi qui joues les monstres
}
var god_tool := ""         ## outil à clic : "spawn:<monstre>", "move", "kill", "heal", ou ""
var god_selected: Unit = null


## Vrai si c'est un humain (et non l'IA) qui joue cette unité
func is_player_controlled(u: Unit) -> bool:
	if u == null:
		return false
	if u.side == "hero":
		return not autoplay
	return god.control_monsters


func current() -> Unit:
	return order[turn_idx] if turn_idx < order.size() else null


func unit_at(c: Vector2i) -> Unit:
	for u in units:
		if not u.dead and u.pos == c:
			return u
	return null


func enemies_of(u: Unit) -> Array:
	return units.filter(func(o: Unit): return o.is_alive() and o.side != u.side)


func allies_of(u: Unit) -> Array:
	return units.filter(func(o: Unit): return not o.dead and o.side == u.side and not o.is_object)


func wait(seconds: float) -> void:
	if speed_factor <= 0.0:
		await get_tree().process_frame   # même en mode instantané, on avance d'une image
		return
	await get_tree().create_timer(seconds * speed_factor).timeout


func _free_cells_near(c: Vector2i, max_r := 3) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var cc := c + Vector2i(dx, dy)
				if Dungeon.dist(cc, c) == r and dungeon.walkable(cc) and unit_at(cc) == null:
					out.append(cc)
		if not out.is_empty():
			return out
	return out


# ---------------------------------------------------------------------------
# Mise en place
# ---------------------------------------------------------------------------
## enc = { title, monsters: [clés], elite: index ou -1, boss: bool }
func start_combat(party: Array[Unit], enc: Dictionary, act_index: int, potion_inventory: Array) -> void:
	heroes = party
	encounter = enc
	act = act_index
	potions = potion_inventory
	over = false
	busy = false
	ability = {}
	telegraphs.clear()
	hazards.clear()
	kills.clear()
	dungeon = Dungeon.new(MAP_W, MAP_H)
	dungeon.generate(Data.ACTS[act].biome)
	units.clear()

	# Héros à gauche, au plus près du centre
	var cells: Array[Vector2i] = []
	for y in range(1, MAP_H - 1):
		for x in [1, 2]:
			cells.append(Vector2i(x, y))
	var keys := {}
	for c in cells:
		keys[c] = absf(c.y + 0.5 - MAP_H / 2.0) + randf() * 2
	cells.sort_custom(func(a, b): return keys[a] < keys[b])
	for i in heroes.size():
		var h := heroes[i]
		h.pos = cells[i]
		h.cooldowns = {}
		h.status = {}
		h.shield = 0
		h.dead = false
		units.append(h)

	# Monstres à droite (pour un boss : au plus près du centre)
	var mcells: Array[Vector2i] = []
	for y in range(1, MAP_H - 1):
		for x in range(MAP_W - 5, MAP_W - 1):
			if dungeon.walkable(Vector2i(x, y)):
				mcells.append(Vector2i(x, y))
	mcells.shuffle()
	if enc.get("boss", false):
		var mkeys := {}
		for c in mcells:
			mkeys[c] = absi(c.y - MAP_H / 2) + absi(c.x - (MAP_W - 3)) + randf()
		mcells.sort_custom(func(a, b): return mkeys[a] < mkeys[b])
	for i in enc.monsters.size():
		var k: String = enc.monsters[i]
		var elite_trait: Dictionary = Data.ELITE_TRAITS.pick_random() if enc.get("elite", -1) == i else {}
		var m := Unit.make_monster(k, act, elite_trait)
		m.pos = mcells[i]
		units.append(m)
		if "phylactere" in m.mechanics:
			for corner in [Vector2i(MAP_W - 7, 2), Vector2i(MAP_W - 7, MAP_H - 3)]:
				var free := _free_cells_near(corner, 4)
				if not free.is_empty():
					var p := Unit.make_monster("phylactere", act)
					p.pos = free[0]
					units.append(p)

	log_added.emit("[font_size=17][color=#e3b95f][b]%s[/b][/color][/font_size]" % enc.title)
	for u in units:
		if u.boss:
			var lines := PackedStringArray()
			for mech in u.mechanics:
				lines.append("  • " + Data.MECHANICS[mech])
			log_added.emit("[color=#e05050][b]%s[/b][/color]\n%s" % [u.name, "\n".join(lines)])
		elif not u.elite.is_empty():
			log_added.emit("[color=#c86bff]Élite : %s — %s[/color]" % [u.name, u.elite.desc])
	if board:
		board.setup(self)
	_roll_initiative()
	round_num = 1
	turn_idx = 0
	_begin_turn()


func _roll_initiative() -> void:
	var lines := "[b]Jets d'initiative[/b]"
	order.clear()
	for u in units:
		if u.is_object:
			continue
		var r := Dice.d20()
		var b := u.dex + int(u.mod("init"))
		u.init = r + b + randf() * 0.01
		if u.side == "hero":
			lines += "\n  %s : %s" % [u.name, roll_chip(r, b)]
		order.append(u)
	order.sort_custom(func(a: Unit, b: Unit): return a.init > b.init)
	log_added.emit(lines)


# ---------------------------------------------------------------------------
# Déroulement des tours
# ---------------------------------------------------------------------------
func _begin_turn() -> void:
	if over:
		return
	var u := current()
	if u == null or u.dead:
		_end_turn()
		return
	if u.hp <= 0:
		log_added.emit("[color=#9a92a3]%s est inconscient et passe son tour.[/color]" % u.name)
		_end_turn()
		return
	u.moves_left = 99 if god.free_actions and is_player_controlled(u) else u.speed
	u.action_used = false
	u.bonus_used = false
	for k in u.cooldowns:
		u.cooldowns[k] = maxi(0, u.cooldowns[k] - 1)
	ability = {}
	changed.emit()

	# Effets de début de tour : régénération, états, flammes au sol, attaques annoncées
	var skip := _tick_start(u)
	if await _check_end():
		return
	if not u.is_alive():
		_end_turn()
		return
	if u.status.has("slow"):
		u.moves_left = int(ceil(u.moves_left / 2.0))
	if skip:
		await wait(0.5)
		_end_turn()
		return
	await _resolve_telegraphs(u)
	if await _check_end():
		return

	if is_player_controlled(u):
		busy = false
		_refresh_reach()
		changed.emit()
	else:
		busy = true
		reach = {}
		changed.emit()
		await _ai_turn(u)
		if not over:
			_end_turn()


## Retourne true si l'unité perd son tour (étourdie)
func _tick_start(u: Unit) -> bool:
	if u.mod("regen") > 0 and u.hp < u.max_hp:
		_heal_unit(u, int(u.mod("regen")), true)
	var i := dungeon.idx(u.pos)
	if hazards.has(i):
		var r := Dice.roll("1d6")
		_log(u, "Les flammes au sol le brûlent : %s" % _dmg(r.total))
		_deal_damage(u, r.total)
		_apply_status(u, {"status": "burn", "turns": 1, "chance": 1.0})
	if u.status.has("poison") and u.is_alive():
		_log(u, "Le poison fait effet : %s dégâts." % _dmg(3))
		_deal_damage(u, 3)
	if u.status.has("burn") and u.is_alive():
		var r := Dice.roll("1d6")
		_log(u, "Brûlure : %s = %s dégâts." % [Dice.fmt(r), _dmg(r.total)])
		_deal_damage(u, r.total)
	var skip := false
	if u.status.has("stun") and u.is_alive():
		skip = true
		_log(u, "[color=#ffe066]Étourdi, il perd son tour ![/color]")
		_floater(u, "Étourdi", Color("#ffe066"))
	for k in u.status.keys():
		u.status[k] -= 1
		if u.status[k] <= 0:
			u.status.erase(k)
	return skip


func _end_turn() -> void:
	if over:
		return
	ability = {}
	reach = {}
	turn_idx += 1
	if turn_idx >= order.size():
		order.assign(order.filter(func(u: Unit): return not u.dead))
		turn_idx = 0
		round_num += 1
		for k in hazards.keys():
			hazards[k] -= 1
			if hazards[k] <= 0:
				hazards.erase(k)
		log_added.emit("[center][color=#e3b95f]— Round %d —[/color][/center]" % round_num)
	_begin_turn()


func _refresh_reach() -> void:
	var u := current()
	reach = dungeon.compute_reach(u, units, u.moves_left) if is_player_controlled(u) and not u.is_object else {}


## Retourne true si le combat est terminé
func _check_end() -> bool:
	if over:
		return true
	var monsters_left := units.any(func(u: Unit): return u.side == "monster" and u.is_alive() and not u.is_object)
	var heroes_left := heroes.any(func(u: Unit): return u.is_alive())
	if monsters_left and heroes_left:
		return false
	over = true
	busy = true
	changed.emit()
	await wait(0.9)
	for h in heroes:
		h.status = {}
		h.shield = 0
		if not monsters_left and h.hp <= 0:
			h.hp = 1   # les héros tombés se relèvent à 1 PV après une victoire
	ended.emit(not monsters_left)
	return true


# ---------------------------------------------------------------------------
# Actions (point d'entrée unique)
# ---------------------------------------------------------------------------
## Capacités utilisables par une unité : les siennes + les potions du groupe (héros)
func usable_abilities(u: Unit) -> Array:
	var list := u.abilities.duplicate()
	if u.side == "hero":
		var counts := {}
		for k in potions:
			counts[k] = counts.get(k, 0) + 1
		for k in Data.POTIONS:
			if counts.has(k):
				var p: Dictionary = Data.POTIONS[k].duplicate()
				p["consumable"] = true
				p["potion"] = k
				p["count"] = counts[k]
				list.append(p)
	return list


func perform(action: Dictionary) -> void:
	var u := current()
	if busy or over or u == null:
		return
	match action.type:
		"move":
			if reach.is_empty() or not dungeon.inside(action.to):
				return
			var i := dungeon.idx(action.to)
			if unit_at(action.to) == null and reach.dist[i] <= u.moves_left and i != reach.start:
				busy = true
				await _move_along(u, Dungeon.path_to(reach, i))
				if god.free_actions:
					u.moves_left = 99
				busy = false
				_refresh_reach()
				changed.emit()
		"ability":
			var list := usable_abilities(u)
			if action.index < 0 or action.index >= list.size():
				return
			var ab: Dictionary = list[action.index]
			if ability_ready(u, ab) and (not needs_target(ab) or is_valid_target(u, ab, action.target)):
				await use_ability(u, ab, action.get("target", u.pos))
		"end_turn":
			_end_turn()


## Clic sur une case (appelé par le plateau)
func click_cell(c: Vector2i) -> void:
	if god_tool != "" and not busy and not over:
		_god_click(c)
		return
	var u := current()
	if busy or over or not is_player_controlled(u):
		return
	if not ability.is_empty():
		if is_valid_target(u, ability, c):
			await perform({"type": "ability", "index": _ability_index(u, ability), "target": c})
		elif c == u.pos:
			ability = {}
			changed.emit()
		return
	await perform({"type": "move", "to": c})


func _ability_index(u: Unit, ab: Dictionary) -> int:
	var list := usable_abilities(u)
	for i in list.size():
		if list[i].id == ab.id:
			return i
	return -1


## Bouton de capacité (appelé par l'interface)
func select_ability(index: int) -> void:
	var u := current()
	if busy or over or not is_player_controlled(u):
		return
	var list := usable_abilities(u)
	if index >= list.size():
		return
	var ab: Dictionary = list[index]
	if not ability_ready(u, ab):
		return
	if not ability.is_empty() and ability.id == ab.id:
		ability = {}
	elif not needs_target(ab):
		await perform({"type": "ability", "index": index, "target": u.pos})
		return
	else:
		ability = ab
	changed.emit()


func cancel_targeting() -> void:
	if not ability.is_empty():
		ability = {}
		changed.emit()


func end_hero_turn() -> void:
	var u := current()
	if not busy and not over and is_player_controlled(u):
		perform({"type": "end_turn"})


# ---------------------------------------------------------------------------
# Règles des capacités
# ---------------------------------------------------------------------------
func ability_ready(u: Unit, ab: Dictionary) -> bool:
	if god.free_actions and is_player_controlled(u):
		return true
	if u.cooldowns.get(ab.id, 0) > 0:
		return false
	return not u.bonus_used if ab.get("bonus", false) else not u.action_used


static func needs_target(ab: Dictionary) -> bool:
	if ab.type in ["shield", "cleanse"]:
		return ab.get("range", 0) > 0
	return not (ab.type in ["whirlwind", "selfheal", "massheal", "dash", "buff"])


func in_range(u: Unit, c: Vector2i, r: int) -> bool:
	return Dungeon.dist(u.pos, c) <= r and (r <= 1 or dungeon.has_los(u.pos, c))


func is_valid_target(u: Unit, ab: Dictionary, c: Vector2i) -> bool:
	if not dungeon.inside(c) or not in_range(u, c, u.range_of(ab)):
		return false
	var t := unit_at(c)
	match ab.type:
		"attack", "autohit", "save", "chain":
			return t != null and t.is_alive() and t.side != u.side
		"charge":
			return t != null and t.is_alive() and t.side != u.side and Dungeon.dist(u.pos, c) > 1 and _charge_cell(u, t) != Vector2i(-1, -1)
		"heal":
			return t != null and t.side == u.side and not t.is_object and t.hp < t.max_hp
		"shield", "cleanse":
			return t != null and t.side == u.side and not t.is_object
		"aoe", "aoeAttack":
			return not dungeon.blocks_sight(c)
		"teleport":
			return dungeon.walkable(c) and t == null
	return false


## Case libre au contact de la cible, la plus proche du chargeur
func _charge_cell(u: Unit, t: Unit) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 999
	for d in Dungeon.DIRS:
		var c := t.pos + d
		if dungeon.walkable(c) and (unit_at(c) == null or unit_at(c) == u) and dungeon.has_los(u.pos, c):
			var dd := Dungeon.dist(u.pos, c)
			if dd < bd:
				bd = dd
				best = c
	return best


func units_in_radius(c: Vector2i, r: int) -> Array:
	return units.filter(func(o: Unit): return not o.dead and Dungeon.dist(o.pos, c) <= r)


func use_ability(u: Unit, ab: Dictionary, c: Vector2i) -> void:
	busy = true
	ability = {}
	var cd := u.cooldown_of(ab)
	if cd > 0:
		u.cooldowns[ab.id] = cd
	if ab.get("bonus", false):
		u.bonus_used = true
	else:
		u.action_used = true
	if ab.get("consumable", false):
		potions.erase(ab.potion)
	changed.emit()

	var t := unit_at(c)
	var color: Color = ab.get("fx", Color.WHITE)
	match ab.type:
		"attack":
			await _shoot(u, c, color)
			_resolve_attack(u, t, ab)
		"autohit":
			await _shoot(u, c, color)
			var r := Dice.roll(ab.dmg, false, u.dmg_bonus())
			_log(u, "[b]%s[/b] → %s\nTouche automatiquement.\nDégâts : %s = %s" % [ab.name, t.name, Dice.fmt(r), _dmg(r.total)])
			_deal_damage(t, r.total, false, u)
		"save":
			await _shoot(u, c, color)
			var s := Dice.d20()
			var ok: bool = s + t.dex >= ab.dc
			var r := Dice.roll(ab.dmg, false, u.dmg_bonus())
			var txt := "[b]%s[/b] → %s\nSauvegarde Dex : %s vs DD %d — %s" % [ab.name, t.name, roll_chip(s, t.dex), ab.dc,
				"[color=#9aa3b2]Réussie[/color]" if ok else "[color=#ff8a65]Ratée[/color]"]
			if ok:
				_log(u, txt)
				_floater(t, "Résiste", Color("#cfd6e0"))
			else:
				_log(u, txt + "\nDégâts : %s = %s" % [Dice.fmt(r), _dmg(r.total)])
				_deal_damage(t, r.total, false, u)
		"aoe":
			await _shoot(u, c, color)
			var rad := u.radius_of(ab)
			if board:
				board.boom(c, rad, color)
				board.shake(6)
			var r := Dice.roll(ab.dmg, false, 0 if ab.get("consumable", false) else u.dmg_bonus())
			var txt := "[b]%s[/b] !\nDégâts : %s = [b]%d[/b] (DD %d)" % [ab.name, Dice.fmt(r), r.total, ab.dc]
			var hits := []
			for v in units_in_radius(c, rad):
				if not v.is_alive():
					continue
				var s := Dice.d20()
				var ok: bool = s + v.dex >= ab.dc
				var dmg: int = (r.total / 2 if ab.get("half", false) else 0) if ok else r.total
				txt += "\n   %s : %s %s → %s" % [v.name, roll_chip(s, v.dex), "moitié" if ok else "plein", _dmg(dmg)]
				hits.append([v, dmg, ok])
			if hits.is_empty():
				txt += "\n[i]Personne dans la zone.[/i]"
			_log(u, txt)
			for hit in hits:
				_deal_damage(hit[0], hit[1], false, u)
				if not hit[2]:
					_apply_status(hit[0], ab.get("onHit", {}))
		"aoeAttack":
			await _shoot(u, c, color)
			var rad := u.radius_of(ab)
			if board:
				board.boom(c, rad, color)
			var victims := units_in_radius(c, rad).filter(func(v: Unit): return v.is_alive() and v.side != u.side)
			if victims.is_empty():
				_log(u, "[b]%s[/b]\n[i]Aucun ennemi dans la zone.[/i]" % ab.name)
			for v in victims:
				_resolve_attack(u, v, ab)
		"whirlwind":
			if board:
				board.boom(u.pos, 1, Color("#e0e0e0"))
			var victims := enemies_of(u).filter(func(v: Unit): return Dungeon.dist(u.pos, v.pos) <= 1)
			if victims.is_empty():
				_log(u, "[b]%s[/b]\n[i]…mais aucun ennemi n'est au contact.[/i]" % ab.name)
			for v in victims:
				_resolve_attack(u, v, ab)
		"chain":
			var hit_list: Array = [t]
			await _shoot(u, c, color)
			_resolve_attack(u, t, ab)
			var last := t
			for b in ab.get("bounces", 2):
				var nexts := enemies_of(u).filter(func(e: Unit): return not (e in hit_list) and Dungeon.dist(e.pos, last.pos) <= 3)
				if nexts.is_empty():
					break
				nexts.sort_custom(func(a: Unit, b2: Unit): return Dungeon.dist(a.pos, last.pos) < Dungeon.dist(b2.pos, last.pos))
				var nxt: Unit = nexts[0]
				if board:
					await board.bolt(last.pos, nxt.pos, color, speed_factor)
				_resolve_attack(u, nxt, ab)
				hit_list.append(nxt)
				last = nxt
		"charge":
			var dest := _charge_cell(u, t)
			_log(u, "[b]%s[/b] ! Il fonce sur %s." % [ab.name, t.name])
			u.pos = dest
			if board:
				await board.step(u, speed_factor)
				board.shake(4)
			_resolve_attack(u, t, ab)
		"heal":
			if t != u:
				await _shoot(u, c, color)
			var r := Dice.roll(ab.heal, false, u.heal_bonus())
			_log(u, "[b]%s[/b] → %s\nSoins : %s = %s" % [ab.name, t.name, Dice.fmt(r), _heal(r.total)])
			_heal_unit(t, r.total)
		"selfheal":
			var r := Dice.roll(ab.heal, false, 0 if ab.get("consumable", false) else u.heal_bonus())
			_log(u, "[b]%s[/b]\nSoins : %s = %s" % [ab.name, Dice.fmt(r), _heal(r.total)])
			_heal_unit(u, r.total)
		"massheal":
			if board:
				board.boom(u.pos, ab.radius, Color("#7dffa8"))
			var r := Dice.roll(ab.heal, false, u.heal_bonus())
			var targets := allies_of(u).filter(func(a: Unit): return Dungeon.dist(a.pos, u.pos) <= ab.radius)
			_log(u, "[b]%s[/b]\nSoins : %s = %s pour %s" % [ab.name, Dice.fmt(r), _heal(r.total),
				", ".join(targets.map(func(a: Unit): return a.name))])
			for a in targets:
				_heal_unit(a, r.total)
		"shield":
			var target: Unit = t if t else u
			var amount: int = ab.amount + u.heal_bonus()
			target.shield += amount
			if board:
				board.boom(target.pos, 0, Color("#9be8ff"))
			_log(u, "[b]%s[/b] → %s\nBouclier de [color=#9be8ff][b]%d[/b][/color] PV." % [ab.name, target.name, amount])
			_floater(target, "+%d bouclier" % amount, Color("#9be8ff"))
		"buff":
			var targets := allies_of(u).filter(func(a: Unit): return a.is_alive() and Dungeon.dist(a.pos, u.pos) <= ab.get("radius", 0))
			if board:
				board.boom(u.pos, ab.get("radius", 0), Data.STATUS[ab.status].color)
			_log(u, "[b]%s[/b]\n%s : %s" % [ab.name, Data.STATUS[ab.status].name, ", ".join(targets.map(func(a: Unit): return a.name))])
			for a in targets:
				_apply_status(a, {"status": ab.status, "turns": ab.turns, "chance": 1.0})
		"cleanse":
			var target: Unit = t if t else u
			var r := Dice.roll(ab.heal, false, 0 if ab.get("consumable", false) else u.heal_bonus())
			for k in ["poison", "burn", "slow"]:
				target.status.erase(k)
			_log(u, "[b]%s[/b] → %s\nLes maux sont purgés. Soins : %s = %s" % [ab.name, target.name, Dice.fmt(r), _heal(r.total)])
			_heal_unit(target, r.total)
		"teleport":
			if board:
				board.boom(u.pos, 0, Color("#6a4c9c"))
			u.pos = c
			if board:
				board.snap(u)
				board.boom(c, 0, Color("#6a4c9c"))
			_log(u, "[b]%s[/b]\nDisparaît dans les ombres et réapparaît plus loin." % ab.name)
		"dash":
			var n: int = ab.get("amount", u.speed)
			u.moves_left += n
			_log(u, "[b]%s[/b]\n+%d cases de déplacement." % [ab.name, n])

	await wait(0.25)
	changed.emit()
	if await _check_end():
		return
	if is_player_controlled(u) and current() == u:
		busy = false
		if god.free_actions:
			u.moves_left = 99
		_refresh_reach()
		changed.emit()


func _resolve_attack(u: Unit, t: Unit, ab: Dictionary) -> void:
	if t == null or not t.is_alive():
		return
	var nat := Dice.d20()
	var bonus: int = ab.get("hit", 0) + u.hit_bonus()
	var crit := nat >= u.crit_min()
	var fumble := nat == 1
	var hit := crit or (not fumble and nat + bonus >= t.ac)
	var txt := "[b]%s[/b] → %s\n%s vs CA %d — " % [ab.name, t.name, roll_chip(nat, bonus), t.ac]
	if not hit:
		_log(u, txt + ("[color=#9aa3b2]Échec critique[/color]" if fumble else "[color=#9aa3b2]Raté[/color]"))
		_floater(t, "Raté", Color("#9aa3b2"))
		return
	txt += "[color=#ffd23f][b]CRITIQUE ![/b][/color]" if crit else "[color=#ff8a65]Touché[/color]"
	var r := Dice.roll(ab.dmg, crit, u.dmg_bonus())
	var dmg: int = r.total
	txt += "\nDégâts : %s = %s" % [Dice.fmt(r), _dmg(r.total)]
	if ab.get("sneak", false) and units.any(func(o: Unit): return o != u and o.side == u.side and o.is_alive() and Dungeon.dist(o.pos, t.pos) <= 1):
		var s := Dice.roll("%dd6" % (2 + (u.level - 1) / 3), crit)
		dmg += s.total
		txt += "\nAttaque sournoise : %s = %s" % [Dice.fmt(s), _dmg(s.total)]
	if ab.has("execute") and t.hp < t.max_hp / 2.0:
		var e := Dice.roll(ab.execute, crit)
		dmg += e.total
		txt += "\nExécution : %s = %s" % [Dice.fmt(e), _dmg(e.total)]
	_log(u, txt)
	_deal_damage(t, dmg, crit, u)
	_apply_status(t, ab.get("onHit", {}))
	# Épines
	if Dungeon.dist(u.pos, t.pos) <= 1 and t.mod("thorns") > 0 and u.is_alive() and t != u:
		_log(t, "Épines : %s dégâts renvoyés à %s." % [_dmg(int(t.mod("thorns"))), u.name])
		_deal_damage(u, int(t.mod("thorns")))


func _apply_status(t: Unit, on_hit: Dictionary) -> void:
	if on_hit.is_empty() or not t.is_alive() or t.is_object or randf() > on_hit.get("chance", 1.0):
		return
	var st: String = on_hit.status
	if st in t.immune:
		_floater(t, "Immunisé", Color("#cfd6e0"))
		return
	var turns: int = on_hit.turns + (1 if st in ["slow", "force"] else 0)
	t.status[st] = maxi(t.status.get(st, 0), turns)
	_floater(t, Data.STATUS[st].name, Data.STATUS[st].color)
	changed.emit()


## Vrai si la Liche est encore protégée par ses phylactères
func _protected(t: Unit) -> bool:
	return "phylactere" in t.mechanics and units.any(func(o: Unit): return o.key == "phylactere" and o.is_alive())


func _deal_damage(t: Unit, amount: int, crit := false, source: Unit = null, ignore_protection := false) -> void:
	if amount <= 0 or t.dead:
		return
	if god.invincible and t.side == "hero":
		_floater(t, "Invincible", Color("#ffd23f"))
		return
	if _protected(t) and not ignore_protection:
		_floater(t, "Protégée !", Color("#b07dff"))
		_log(t, "[color=#b07dff]Le bouclier nécrotique absorbe le coup. Détruisez les phylactères ![/color]")
		return
	if t.shield > 0:
		var absorbed := mini(t.shield, amount)
		t.shield -= absorbed
		amount -= absorbed
		_floater(t, "-%d bouclier" % absorbed, Color("#9be8ff"))
		if amount <= 0:
			changed.emit()
			return
	t.hp = maxi(0, t.hp - amount)
	_floater(t, ("CRIT -%d" if crit else "-%d") % amount, Color("#ffd23f") if crit else Color("#ff5b5b"))
	if board:
		board.hurt(t, crit)
	if source and source != t and source.mod("lifesteal") > 0 and source.is_alive():
		_heal_unit(source, maxi(1, int(amount * source.mod("lifesteal"))), true)
	if t.hp == 0:
		if t.side == "monster":
			t.dead = true
			if not t.is_object:
				kills.append(t)
			log_added.emit("[color=#e05050]☠ %s est %s ![/color]" % [t.name, "détruit" if t.is_object else "vaincu"])
			if t.key == "phylactere" and not units.any(func(o: Unit): return o.key == "phylactere" and o.is_alive()):
				log_added.emit("[color=#b07dff][b]Le dernier phylactère vole en éclats : la Liche est vulnérable ![/b][/color]")
		else:
			t.status = {}
			log_added.emit("[color=#e0b030]%s tombe inconscient ! Un soin peut le relever.[/color]" % t.name)
	changed.emit()


func _heal_unit(t: Unit, amount: int, quiet := false) -> void:
	var was_down := t.hp == 0
	var before := t.hp
	t.hp = mini(t.max_hp, t.hp + amount)
	if t.hp > before:
		_floater(t, "+%d" % (t.hp - before), Color("#5fe08d"))
	if was_down and t.hp > 0 and not quiet:
		log_added.emit("[color=#5fe08d]%s reprend connaissance ![/color]" % t.name)
	changed.emit()


# ---------------------------------------------------------------------------
# Déplacements et animations
# ---------------------------------------------------------------------------
func _move_along(u: Unit, path: Array[int]) -> void:
	for i in path:
		var c := dungeon.cell(i)
		u.moves_left -= dungeon.cost(c)
		u.pos = c
		if board:
			await board.step(u, speed_factor)


func _shoot(u: Unit, c: Vector2i, color: Color) -> void:
	if board:
		await board.shoot(u, c, color, speed_factor)


func _floater(t: Unit, text: String, color: Color) -> void:
	if board:
		board.floater(t.pos, text, color)


# ---------------------------------------------------------------------------
# Journal
# ---------------------------------------------------------------------------
func _log(u: Unit, body: String) -> void:
	var col := "#5fd38d" if u.side == "hero" else "#e05050"
	log_added.emit("[color=%s][b]%s[/b][/color]  [color=#8a8290][font_size=12]Round %d[/font_size][/color]\n%s" % [col, u.name, round_num, body])


static func roll_chip(nat: int, bonus: int) -> String:
	var col := "#5fe08d" if nat == 20 else ("#ff6b6b" if nat == 1 else "#e8e2d6")
	return "[bgcolor=#3a3542][color=%s] d20 %d%s = [b]%d[/b] [/color][/bgcolor]" % [col, nat, Dice.fmt_mod(bonus), nat + bonus]


static func _dmg(n: int) -> String:
	return "[color=#ff6b6b][b]%d[/b][/color]" % n


static func _heal(n: int) -> String:
	return "[color=#5fe08d][b]%d[/b][/color]" % n


# ---------------------------------------------------------------------------
# Boss : attaques annoncées (télégraphes) et mécaniques spéciales
# ---------------------------------------------------------------------------
## Prépare une attaque qui frappera au prochain tour de « owner » (les cases s'affichent en rouge)
func _telegraph(owner: Unit, cells: Array, attack_name: String, dmg: String, dc: int, on_hit := {}, fire := false) -> void:
	telegraphs.append({"owner": owner, "cells": cells, "name": attack_name, "dmg": dmg, "dc": dc, "status": on_hit, "fire": fire})
	_log(owner, "[color=#ff6b6b][b]%s se prépare ![/b] Quittez les cases rouges avant son prochain tour ![/color]" % attack_name)
	if board:
		board.shake(3)
	changed.emit()


func _resolve_telegraphs(u: Unit) -> void:
	var mine := telegraphs.filter(func(tg): return tg.owner == u)
	for tg in mine:
		telegraphs.erase(tg)
		if board:
			for c in tg.cells:
				board.boom(c, 0, Color("#ff5a1a"))
			board.shake(10)
		var r := Dice.roll(tg.dmg)
		var txt := "[b]%s[/b] !\nDégâts : %s = [b]%d[/b] (Dex DD %d)" % [tg.name, Dice.fmt(r), r.total, tg.dc]
		var hits := []
		for v in heroes:
			if v.is_alive() and v.pos in tg.cells:
				var s := Dice.d20()
				var ok: bool = s + v.dex >= tg.dc
				var dmg: int = r.total / 2 if ok else r.total
				txt += "\n   %s : %s %s → %s" % [v.name, roll_chip(s, v.dex), "moitié" if ok else "plein", _dmg(dmg)]
				hits.append([v, dmg, ok])
		if hits.is_empty():
			txt += "\n[i]Personne n'est touché.[/i]"
		_log(u, txt)
		for hit in hits:
			_deal_damage(hit[0], hit[1], false, u)
			if not hit[2]:
				_apply_status(hit[0], tg.status)
		if tg.fire:
			for c in tg.cells:
				hazards[dungeon.idx(c)] = 2
		await wait(0.5)
	changed.emit()


## Mécaniques jouées au début du tour du boss. Retourne true si le boss a fini son tour.
func _boss_mechanics(m: Unit) -> bool:
	m.memory["turns"] = m.memory.get("turns", 0) + 1
	var turns: int = m.memory.turns
	# --- Ogre ---
	if "rage" in m.mechanics and not m.memory.get("raged", false) and m.hp < m.max_hp / 2:
		m.memory["raged"] = true
		_log(m, "[color=#ff5050][b]L'Ogre entre dans une rage folle ![/b] Il frappera deux fois par tour.[/color]")
		if board:
			board.shake(8)
	if "seisme" in m.mechanics and turns % 3 == 0:
		var cells := []
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var c := m.pos + Vector2i(dx, dy)
				if dungeon.walkable(c) and c != m.pos:
					cells.append(c)
		_telegraph(m, cells, "Séisme", "3d6+2", 14, {"status": "stun", "turns": 1, "chance": 1.0})
		await wait(0.6)
		return true
	# --- Liche ---
	if "clignement" in m.mechanics and heroes.any(func(h: Unit): return h.is_alive() and Dungeon.dist(h.pos, m.pos) <= 1):
		var best := Vector2i(-1, -1)
		var bs := -1
		for i in dungeon.w * dungeon.h:
			var c := dungeon.cell(i)
			if not dungeon.walkable(c) or unit_at(c):
				continue
			var near := 99
			for h in heroes:
				if h.is_alive():
					near = mini(near, Dungeon.dist(c, h.pos))
			if near > bs and near <= 8:
				bs = near
				best = c
		if best.x >= 0:
			if board:
				board.boom(m.pos, 0, Color("#b07dff"))
			m.pos = best
			if board:
				board.snap(m)
				board.boom(best, 0, Color("#b07dff"))
			_log(m, "[color=#b07dff]Clignement ! La Liche disparaît et réapparaît plus loin.[/color]")
	var skeletons := units.filter(func(o: Unit): return o.key == "squelette" and o.is_alive()).size()
	if "invocation" in m.mechanics and turns % 3 == 0 and skeletons < 4:
		var free := _free_cells_near(m.pos, 3)
		free.shuffle()
		var n := 0
		for c in free.slice(0, mini(2, 4 - skeletons)):
			_spawn("squelette", c, m)
			n += 1
		if n:
			_log(m, "[color=#b07dff]« Relevez-vous ! » %d squelette%s sort%s de terre.[/color]" % [n, "s" if n > 1 else "", "ent" if n > 1 else ""])
			await wait(0.4)
	# --- Dragon ---
	if "envol" in m.mechanics and not m.memory.get("flown", false) and m.hp < m.max_hp / 2:
		m.memory["flown"] = true
		_log(m, "[color=#ff7a2a][b]Le Dragon rugit et s'envole ! Le sol s'embrase.[/b][/color]")
		if board:
			board.shake(12)
		for c in _free_cells_near(m.pos, 3).slice(0, 2):
			_spawn("elementaire", c, m)
		var floor_cells := []
		for i in dungeon.w * dungeon.h:
			if dungeon.walkable(dungeon.cell(i)) and unit_at(dungeon.cell(i)) == null:
				floor_cells.append(i)
		floor_cells.shuffle()
		for i in floor_cells.slice(0, 10):
			hazards[i] = 3
		await wait(0.6)
	if "souffle" in m.mechanics and turns % 3 == 2:
		var cells := _breath_cells(m)
		if not cells.is_empty():
			_telegraph(m, cells, "Souffle de feu", "4d6+4", 15, {"status": "burn", "turns": 2, "chance": 1.0}, true)
			await wait(0.6)
			return true
	if "queue" in m.mechanics:
		var adj := heroes.filter(func(h: Unit): return h.is_alive() and Dungeon.dist(h.pos, m.pos) <= 1)
		if adj.size() >= 2:
			var tail := {"id": "queue", "name": "Coup de queue", "type": "attack", "range": 1, "hit": 7, "dmg": "2d6+4"}
			if board:
				board.boom(m.pos, 1, Color("#c83c3c"))
			for h in adj:
				_resolve_attack(m, h, tail)
			await wait(0.4)
			return true
	return false


## Cône de flammes du dragon dans la direction où il y a le plus de héros
func _breath_cells(m: Unit) -> Array:
	var best: Array = []
	var best_n := 0
	for d in Dungeon.DIRS:
		var cells := []
		var side := Vector2i(-d.y, d.x)
		for k in range(1, 7):
			var center := m.pos + d * k
			var width := 0 if k <= 1 else 1
			for s in range(-width, width + 1):
				var c := center + side * s
				if dungeon.inside(c) and not dungeon.blocks_sight(c) and not (c in cells):
					cells.append(c)
		var n := heroes.filter(func(h: Unit): return h.is_alive() and h.pos in cells).size()
		if n > best_n:
			best_n = n
			best = cells
	return best


func _spawn(key: String, c: Vector2i, near: Unit) -> Unit:
	var s := Unit.make_monster(key, act)
	s.pos = c
	s.init = near.init - 0.001
	units.append(s)
	if not s.is_object:
		order.insert(turn_idx + 1, s)
	if board:
		board.add_unit(s)
	changed.emit()
	return s


# ---------------------------------------------------------------------------
# IA (monstres, et héros en mode démo)
# ---------------------------------------------------------------------------
func _main_attack(u: Unit) -> Dictionary:
	return u.attack if u.side == "monster" else u.abilities[0]


func _ai_turn(u: Unit) -> void:
	await wait(0.3)
	if u.is_object or enemies_of(u).is_empty():
		return
	if u.boss and await _boss_mechanics(u):
		return
	if over:
		return
	# Héros en mode démo : boit une potion de soin si besoin
	if u.side == "hero" and u.hp < u.max_hp * 0.35 and "soin" in potions:
		for ab in usable_abilities(u):
			if ab.get("potion", "") == "soin" and ability_ready(u, ab):
				await use_ability(u, ab, u.pos)
				break
	# Soigneur : aide un allié blessé si possible
	var heal_ab: Dictionary = u.heal_ab
	if u.side == "hero":
		for ab in u.abilities:
			if ab.type == "heal" and ability_ready(u, ab):
				heal_ab = ab
	if not heal_ab.is_empty() and u.cooldowns.get("heal", 0) == 0 and ability_ready(u, heal_ab):
		var hurt := allies_of(u).filter(func(o: Unit): return o.hp < o.max_hp * 0.5)
		hurt.sort_custom(func(a: Unit, b: Unit): return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
		if not hurt.is_empty() and in_range(u, hurt[0].pos, heal_ab.range):
			if u.side == "monster":
				u.cooldowns["heal"] = 2
			await use_ability(u, heal_ab, hurt[0].pos)
			if over or u.side == "monster":
				return
	var ab := _main_attack(u)
	if ab.is_empty():
		return
	if ab.get("range", 1) > 1:
		await _ranged_turn(u, ab)
	else:
		await _melee_turn(u, ab)
	# Rage de l'Ogre : seconde attaque
	if not over and u.memory.get("raged", false):
		var adj := enemies_of(u).filter(func(e: Unit): return Dungeon.dist(u.pos, e.pos) <= 1 and not e.is_object)
		if not adj.is_empty():
			await wait(0.2)
			_resolve_attack(u, adj[0], ab)
			await _check_end()


## Cibles de l'IA : les monstres ignorent les objets, les héros les visent (phylactères)
func _ai_targets(u: Unit) -> Array:
	var foes := enemies_of(u).filter(func(e: Unit): return not e.is_object or u.side == "hero")
	if u.side == "hero" and foes.any(func(e: Unit): return e.is_object):
		foes = foes.filter(func(e: Unit): return e.is_object or not _protected(e))
	return foes


func _best_cell(u: Unit, r: Dictionary, score: Callable) -> int:
	var best := -1
	var bs := -INF
	for i in r.dist.size():
		if r.dist[i] > u.moves_left:
			continue
		var o := unit_at(dungeon.cell(i))
		if o != null and o != u:
			continue
		var s: float = score.call(dungeon.cell(i)) - (5.0 if hazards.has(i) else 0.0)
		if s > bs:
			bs = s
			best = i
	return -1 if best == r.start else best


func _advance(u: Unit, full: Dictionary, goal: int) -> void:
	var path := Dungeon.path_to(full, goal)
	var stop := -1
	for k in path.size():
		if full.dist[path[k]] > u.moves_left:
			break
		if unit_at(dungeon.cell(path[k])) == null:
			stop = k
	if stop >= 0:
		await _move_along(u, path.slice(0, stop + 1))


func _melee_turn(u: Unit, ab: Dictionary) -> void:
	var full := dungeon.compute_reach(u, units)
	var goal := -1
	var goal_cost := INF
	var target: Unit = null
	var foes := _ai_targets(u)
	for i in full.dist.size():
		if full.dist[i] == INF:
			continue
		var c := dungeon.cell(i)
		var o := unit_at(c)
		if o != null and o != u:
			continue
		for e in foes:
			if Dungeon.dist(c, e.pos) > 1:
				continue
			var cost: float = full.dist[i] + float(e.hp) / e.max_hp * 1.5 + (e.ac - 12) * 0.15 + (3.0 if hazards.has(i) else 0.0)
			if cost < goal_cost:
				goal_cost = cost
				goal = i
				target = e
	if goal < 0:
		await _approach(u)
		return
	if goal != full.start:
		await _advance(u, full, goal)
	var adj := foes.filter(func(e: Unit): return e.is_alive() and Dungeon.dist(u.pos, e.pos) <= 1)
	adj.sort_custom(func(a: Unit, b: Unit): return a.hp < b.hp)
	var tgt: Unit = target if target in adj else (adj[0] if not adj.is_empty() else null)
	if tgt and ability_ready(u, ab):
		await use_ability(u, ab, tgt.pos)


func _ranged_turn(u: Unit, ab: Dictionary) -> void:
	var r := dungeon.compute_reach(u, units, u.moves_left)
	var foes := _ai_targets(u)
	var rng := u.range_of(ab)
	var can_shoot := func(c: Vector2i) -> Array:
		return foes.filter(func(e: Unit): return Dungeon.dist(c, e.pos) <= rng and dungeon.has_los(c, e.pos))
	var score := func(c: Vector2i) -> float:
		var nearest := 99
		for e in foes:
			nearest = mini(nearest, Dungeon.dist(c, e.pos))
		return (100.0 if not can_shoot.call(c).is_empty() else 0.0) + mini(nearest, 5) * 3.0 - r.dist[dungeon.idx(c)] * 0.4
	var here: float = score.call(u.pos)
	var cell_i := _best_cell(u, r, score)
	if cell_i >= 0 and score.call(dungeon.cell(cell_i)) > here:
		await _move_along(u, Dungeon.path_to(r, cell_i))
	var targets: Array = can_shoot.call(u.pos)
	targets.sort_custom(func(a: Unit, b: Unit): return a.hp < b.hp)
	if not targets.is_empty() and ability_ready(u, ab):
		await use_ability(u, ab, targets[0].pos)
	elif u.moves_left > 0:
		await _approach(u)


func _approach(u: Unit) -> void:
	var full := dungeon.compute_reach(u, units)
	var foes := _ai_targets(u)
	if foes.is_empty():
		return
	foes.sort_custom(func(a: Unit, b: Unit): return Dungeon.dist(u.pos, a.pos) < Dungeon.dist(u.pos, b.pos))
	var near: Unit = foes[0]
	var goal := -1
	var gc := INF
	for i in full.dist.size():
		if full.dist[i] == INF:
			continue
		var c: float = full.dist[i] + Dungeon.dist(dungeon.cell(i), near.pos) * 2
		if c < gc:
			gc = c
			goal = i
	if goal >= 0 and goal != full.start:
		await _advance(u, full, goal)


# ---------------------------------------------------------------------------
# Mode dieu : outils pour tout tester (panneau ouvert avec F1)
# ---------------------------------------------------------------------------
func set_god_option(option: String, value: bool) -> void:
	god[option] = value
	var u := current()
	if option == "free_actions" and value and u and is_player_controlled(u):
		u.moves_left = 99
	if not busy:
		_refresh_reach()
	changed.emit()


func _god_click(c: Vector2i) -> void:
	var t := unit_at(c)
	match god_tool:
		"kill":
			if t:
				log_added.emit("[color=#c86bff]⚡ Mode dieu : %s est foudroyé.[/color]" % t.name)
				_deal_damage(t, 9999, false, null, true)
				_check_end()
		"heal":
			if t:
				_heal_unit(t, t.max_hp)
		"move":
			if god_selected == null:
				god_selected = t
			elif t == null and dungeon.walkable(c):
				god_selected.pos = c
				if board:
					board.snap(god_selected)
				god_selected = null
				_refresh_reach()
			else:
				god_selected = t
		_:
			if god_tool.begins_with("spawn:") and t == null and dungeon.walkable(c):
				var m := _spawn(god_tool.trim_prefix("spawn:"), c, current() if current() else heroes[0])
				log_added.emit("[color=#c86bff]⚡ Mode dieu : %s apparaît.[/color]" % m.name)
	changed.emit()


func god_kill_all_monsters() -> void:
	if busy or over:
		return
	for u in units:
		if u.side == "monster" and u.is_alive():
			u.hp = 0
			u.dead = true
			if not u.is_object:
				kills.append(u)
	log_added.emit("[color=#c86bff]⚡ Mode dieu : tous les monstres sont foudroyés.[/color]")
	changed.emit()
	_check_end()


func god_heal_party() -> void:
	for h in heroes:
		h.hp = h.max_hp
		h.status = {}
	log_added.emit("[color=#c86bff]⚡ Mode dieu : le groupe est entièrement soigné.[/color]")
	changed.emit()
