class_name Combat
extends Node
## Les règles du combat : tours, initiative, capacités, dégâts et IA des monstres.
##
## Toutes les actions passent par perform(action), un simple Dictionary :
##   {"type": "move", "to": Vector2i}
##   {"type": "ability", "index": int, "target": Vector2i}
##   {"type": "end_turn"}
## Pour le multijoueur, il suffira d'envoyer ces dictionnaires sur le réseau.

signal log_added(bbcode: String)   ## une ligne pour le journal des dés
signal changed                      ## l'état a changé : rafraîchir l'interface
signal ended(win: bool)             ## fin du niveau

const MAP_W := 18
const MAP_H := 12

var dungeon: Dungeon
var units: Array[Unit] = []
var heroes: Array[Unit] = []
var order: Array[Unit] = []
var turn_idx := 0
var round_num := 1
var level_idx := 0
var busy := false          ## animation ou tour de monstre en cours
var over := false
var ability: Dictionary = {}   ## capacité en cours de ciblage
var reach: Dictionary = {}     ## zone de déplacement du héros actif
var autoplay := false      ## les héros jouent tout seuls (mode démo / tests)
var speed_factor := 1.0    ## accélère les animations (0 = instantané)

var board: Node            ## le plateau (animations)


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
	return units.filter(func(o: Unit): return not o.dead and o.side == u.side)


func wait(seconds: float) -> void:
	if speed_factor <= 0.0:
		return
	await get_tree().create_timer(seconds * speed_factor).timeout


# ---------------------------------------------------------------------------
# Déroulement
# ---------------------------------------------------------------------------
func start_level(party: Array[Unit], index: int) -> void:
	heroes = party
	level_idx = index
	over = false
	busy = false
	ability = {}
	var lvl: Dictionary = Data.LEVELS[index]
	dungeon = Dungeon.new(MAP_W, MAP_H)
	dungeon.generate()
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
		heroes[i].pos = cells[i]
		heroes[i].cooldowns = {}
		units.append(heroes[i])

	# Monstres à droite
	var mcells: Array[Vector2i] = []
	for y in range(1, MAP_H - 1):
		for x in range(MAP_W - 4, MAP_W - 1):
			if dungeon.walkable(Vector2i(x, y)):
				mcells.append(Vector2i(x, y))
	mcells.shuffle()
	var totals := {}
	var counts := {}
	for k in lvl.monsters:
		totals[k] = totals.get(k, 0) + 1
	for i in lvl.monsters.size():
		var k: String = lvl.monsters[i]
		counts[k] = counts.get(k, 0) + 1
		var m := Unit.make_monster(k, counts[k] if totals[k] > 1 else 0, level_idx * 2)
		m.pos = mcells[i]
		units.append(m)

	log_added.emit("[font_size=17][color=#e3b95f][b]Niveau %d — %s[/b][/color][/font_size]\n%d ennemis vous attendent dans l'ombre…" %
		[index + 1, lvl.name, lvl.monsters.size()])
	if board:
		board.setup(self)
	_roll_initiative()
	round_num = 1
	turn_idx = 0
	_begin_turn()


func _roll_initiative() -> void:
	var lines := "[b]Jets d'initiative[/b]"
	for u in units:
		var r := Dice.d20()
		u.init = r + u.dex + randf() * 0.01
		lines += "\n  %s : %s" % [u.name, roll_chip(r, u.dex)]
	order.assign(units)
	order.sort_custom(func(a: Unit, b: Unit): return a.init > b.init)
	log_added.emit(lines)


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
	u.moves_left = u.speed
	u.action_used = false
	u.bonus_used = false
	for k in u.cooldowns:
		u.cooldowns[k] = maxi(0, u.cooldowns[k] - 1)
	ability = {}
	if u.side == "hero" and not autoplay:
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
		log_added.emit("[center][color=#e3b95f]— Round %d —[/color][/center]" % round_num)
	_begin_turn()


func _refresh_reach() -> void:
	var u := current()
	reach = dungeon.compute_reach(u, units, u.moves_left) if u and u.side == "hero" else {}


## Retourne true si le combat est terminé
func _check_end() -> bool:
	if over:
		return true
	var monsters_left := units.any(func(u: Unit): return u.side == "monster" and u.is_alive())
	var heroes_left := heroes.any(func(u: Unit): return u.is_alive())
	if monsters_left and heroes_left:
		return false
	over = true
	busy = true
	changed.emit()
	await wait(0.9)
	ended.emit(not monsters_left)
	return true


# ---------------------------------------------------------------------------
# Actions (point d'entrée unique)
# ---------------------------------------------------------------------------
func perform(action: Dictionary) -> void:
	var u := current()
	if busy or over or u == null:
		return
	match action.type:
		"move":
			var i := dungeon.idx(action.to)
			if reach.is_empty() or not dungeon.inside(action.to):
				return
			if unit_at(action.to) == null and reach.dist[i] <= u.moves_left and i != reach.start:
				busy = true
				await _move_along(u, Dungeon.path_to(reach, i))
				busy = false
				_refresh_reach()
				changed.emit()
		"ability":
			var ab: Dictionary = u.abilities[action.index]
			if ability_ready(u, ab) and (not needs_target(ab) or is_valid_target(u, ab, action.target)):
				await use_ability(u, ab, action.get("target", u.pos))
		"end_turn":
			_end_turn()


## Clic sur une case (appelé par le plateau)
func click_cell(c: Vector2i) -> void:
	var u := current()
	if busy or over or u == null or u.side != "hero":
		return
	if not ability.is_empty():
		if is_valid_target(u, ability, c):
			await perform({"type": "ability", "index": u.abilities.find(ability), "target": c})
		elif c == u.pos:
			ability = {}
			changed.emit()
		return
	await perform({"type": "move", "to": c})


## Bouton de capacité (appelé par l'interface)
func select_ability(index: int) -> void:
	var u := current()
	if busy or over or u == null or u.side != "hero" or index >= u.abilities.size():
		return
	var ab: Dictionary = u.abilities[index]
	if not ability_ready(u, ab):
		return
	if ability == ab:
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
	if not busy and not over and u and u.side == "hero":
		perform({"type": "end_turn"})


# ---------------------------------------------------------------------------
# Règles des capacités
# ---------------------------------------------------------------------------
func ability_ready(u: Unit, ab: Dictionary) -> bool:
	if u.cooldowns.get(ab.id, 0) > 0:
		return false
	return not u.bonus_used if ab.get("bonus", false) else not u.action_used


static func needs_target(ab: Dictionary) -> bool:
	return not (ab.type in ["whirlwind", "selfheal", "massheal", "dash"])


func in_range(u: Unit, c: Vector2i, r: int) -> bool:
	return Dungeon.dist(u.pos, c) <= r and (r <= 1 or dungeon.has_los(u.pos, c))


func is_valid_target(u: Unit, ab: Dictionary, c: Vector2i) -> bool:
	if not dungeon.inside(c) or not in_range(u, c, ab.get("range", 0)):
		return false
	var t := unit_at(c)
	match ab.type:
		"attack", "autohit", "save":
			return t != null and t.is_alive() and t.side != u.side
		"heal":
			return t != null and t.side == u.side and t.hp < t.max_hp
		"aoe", "aoeAttack":
			return dungeon.get_tile(c) != Dungeon.WALL
		"teleport":
			return dungeon.walkable(c) and t == null
	return false


func units_in_radius(c: Vector2i, r: int) -> Array:
	return units.filter(func(o: Unit): return not o.dead and Dungeon.dist(o.pos, c) <= r)


func use_ability(u: Unit, ab: Dictionary, c: Vector2i) -> void:
	busy = true
	ability = {}
	if ab.get("cd", 0) > 0:
		u.cooldowns[ab.id] = ab.cd
	if ab.get("bonus", false):
		u.bonus_used = true
	else:
		u.action_used = true
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
			_deal_damage(t, r.total)
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
				_deal_damage(t, r.total)
		"aoe":
			await _shoot(u, c, color)
			if board:
				board.boom(c, ab.radius, color)
			var r := Dice.roll(ab.dmg, false, u.dmg_bonus())
			var txt := "[b]%s[/b] !\nDégâts : %s = [b]%d[/b] (DD %d)" % [ab.name, Dice.fmt(r), r.total, ab.dc]
			var hits := []
			for v in units_in_radius(c, ab.radius):
				if not v.is_alive():
					continue
				var s := Dice.d20()
				var ok: bool = s + v.dex >= ab.dc
				var dmg: int = (r.total / 2 if ab.get("half", false) else 0) if ok else r.total
				txt += "\n   %s : %s %s → %s" % [v.name, roll_chip(s, v.dex), "moitié" if ok else "plein", _dmg(dmg)]
				hits.append([v, dmg])
			if hits.is_empty():
				txt += "\n[i]Personne dans la zone.[/i]"
			_log(u, txt)
			for hdmg in hits:
				_deal_damage(hdmg[0], hdmg[1])
		"aoeAttack":
			await _shoot(u, c, color)
			if board:
				board.boom(c, ab.radius, color)
			var victims := units_in_radius(c, ab.radius).filter(func(v: Unit): return v.is_alive() and v.side != u.side)
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
		"heal":
			if t != u:
				await _shoot(u, c, color)
			var r := Dice.roll(ab.heal, false, u.dmg_bonus())
			_log(u, "[b]%s[/b] → %s\nSoins : %s = %s" % [ab.name, t.name, Dice.fmt(r), _heal(r.total)])
			_heal_unit(t, r.total)
		"selfheal":
			var r := Dice.roll(ab.heal, false, u.dmg_bonus())
			_log(u, "[b]%s[/b]\nSoins : %s = %s" % [ab.name, Dice.fmt(r), _heal(r.total)])
			_heal_unit(u, r.total)
		"massheal":
			if board:
				board.boom(u.pos, ab.radius, Color("#7dffa8"))
			var r := Dice.roll(ab.heal, false, u.dmg_bonus())
			var targets := allies_of(u).filter(func(a: Unit): return Dungeon.dist(a.pos, u.pos) <= ab.radius)
			_log(u, "[b]%s[/b]\nSoins : %s = %s pour %s" % [ab.name, Dice.fmt(r), _heal(r.total),
				", ".join(targets.map(func(a: Unit): return a.name))])
			for a in targets:
				_heal_unit(a, r.total)
		"teleport":
			if board:
				board.boom(u.pos, 0, Color("#6a4c9c"))
			u.pos = c
			if board:
				board.snap(u)
				board.boom(c, 0, Color("#6a4c9c"))
			_log(u, "[b]%s[/b]\nDisparaît dans les ombres et réapparaît plus loin." % ab.name)
		"dash":
			u.moves_left += u.speed
			_log(u, "[b]%s[/b]\n+%d cases de déplacement." % [ab.name, u.speed])

	await wait(0.25)
	changed.emit()
	if await _check_end():
		return
	if u.side == "hero" and not autoplay:
		busy = false
		_refresh_reach()
		changed.emit()


func _resolve_attack(u: Unit, t: Unit, ab: Dictionary) -> void:
	var nat := Dice.d20()
	var bonus: int = ab.get("hit", 0) + u.hit_bonus()
	var crit := nat == 20
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
		var s := Dice.roll("2d6", crit)
		dmg += s.total
		txt += "\nAttaque sournoise : %s = %s" % [Dice.fmt(s), _dmg(s.total)]
	_log(u, txt)
	_deal_damage(t, dmg, crit)


func _deal_damage(t: Unit, amount: int, crit := false) -> void:
	t.hp = maxi(0, t.hp - amount)
	_floater(t, ("CRIT -%d" if crit else "-%d") % amount, Color("#ffd23f") if crit else Color("#ff5b5b"))
	if board:
		board.hurt(t, crit)
	if t.hp == 0:
		if t.side == "monster":
			t.dead = true
			log_added.emit("[color=#e05050]☠ %s est vaincu ![/color]" % t.name)
		else:
			log_added.emit("[color=#e0b030]%s tombe inconscient ! Un soin peut le relever.[/color]" % t.name)
	changed.emit()


func _heal_unit(t: Unit, amount: int) -> void:
	var was_down := t.hp == 0
	t.hp = mini(t.max_hp, t.hp + amount)
	_floater(t, "+%d" % amount, Color("#5fe08d"))
	if was_down and t.hp > 0:
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
# IA (monstres, et héros en mode démo)
# ---------------------------------------------------------------------------
func _main_attack(u: Unit) -> Dictionary:
	return u.attack if u.side == "monster" else u.abilities[0]


func _ai_turn(u: Unit) -> void:
	await wait(0.35)
	if enemies_of(u).is_empty():
		return
	# Soigneur : aide un allié blessé si possible
	var heal_ab: Dictionary = u.heal_ab
	if u.side == "hero":
		for ab in u.abilities:
			if ab.type == "heal" and ability_ready(u, ab):
				heal_ab = ab
	if not heal_ab.is_empty() and u.cooldowns.get("heal", 0) == 0:
		var hurt := allies_of(u).filter(func(o: Unit): return o.hp < o.max_hp * 0.5)
		hurt.sort_custom(func(a: Unit, b: Unit): return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
		if not hurt.is_empty() and in_range(u, hurt[0].pos, heal_ab.range):
			if u.side == "monster":
				u.cooldowns["heal"] = 2
			await use_ability(u, heal_ab, hurt[0].pos)
			if over or u.side == "monster":
				return
	var ab := _main_attack(u)
	if ab.get("range", 1) > 1:
		await _ranged_turn(u, ab)
	else:
		await _melee_turn(u, ab)


## Meilleure case atteignable (hors case actuelle) selon une fonction de score
func _best_cell(u: Unit, r: Dictionary, score: Callable) -> int:
	var best := -1
	var bs := -INF
	for i in r.dist.size():
		if r.dist[i] > u.moves_left:
			continue
		var o := unit_at(dungeon.cell(i))
		if o != null and o != u:
			continue
		var s: float = score.call(dungeon.cell(i))
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
	for i in full.dist.size():
		if full.dist[i] == INF:
			continue
		var c := dungeon.cell(i)
		var o := unit_at(c)
		if o != null and o != u:
			continue
		for e in enemies_of(u):
			if Dungeon.dist(c, e.pos) > 1:
				continue
			var cost: float = full.dist[i] + float(e.hp) / e.max_hp * 1.5 + (e.ac - 12) * 0.15
			if cost < goal_cost:
				goal_cost = cost
				goal = i
				target = e
	if goal < 0:
		await _approach(u)
		return
	if goal != full.start:
		await _advance(u, full, goal)
	var adj := enemies_of(u).filter(func(e: Unit): return Dungeon.dist(u.pos, e.pos) <= 1)
	adj.sort_custom(func(a: Unit, b: Unit): return a.hp < b.hp)
	var tgt: Unit = target if target in adj else (adj[0] if not adj.is_empty() else null)
	if tgt and ability_ready(u, ab):
		await use_ability(u, ab, tgt.pos)


func _ranged_turn(u: Unit, ab: Dictionary) -> void:
	var r := dungeon.compute_reach(u, units, u.moves_left)
	var foes := enemies_of(u)
	var can_shoot := func(c: Vector2i) -> Array:
		return foes.filter(func(e: Unit): return Dungeon.dist(c, e.pos) <= ab.range and dungeon.has_los(c, e.pos))
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
	var foes := enemies_of(u)
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
