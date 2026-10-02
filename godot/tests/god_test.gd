extends Node
## Test automatique du mode dieu.
## Lancer : godot --headless --path godot res://tests/god_test.tscn

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  OK   " if cond else "  ÉCHEC ") + what)
	if not cond:
		fails += 1


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var c: Combat = main.combat
	c.speed_factor = 0.0
	main.new_run(["guerrier", "mage", "rodeur", "clerc"])
	main.enter_node(main.run.available_nodes()[0].id)   # premier combat
	await get_tree().process_frame
	# Attendre que ce soit au tour d'un héros (les outils sont bloqués pendant le tour des monstres)
	for k in 500:
		if not c.busy:
			break
		await get_tree().process_frame

	# Invincibilité
	var h: Unit = c.heroes[0]
	c.set_god_option("invincible", true)
	var before := h.hp
	c._deal_damage(h, 10)
	check(h.hp == before, "héros invincible : aucun dégât")
	c.set_god_option("invincible", false)
	c._deal_damage(h, 3)
	check(h.hp == before - 3, "invincibilité désactivée : dégâts normaux")

	# Dés truqués
	Dice.forced_d20 = 20
	check(Dice.d20() == 20, "dés truqués sur 20")
	Dice.forced_d20 = 0

	# Apparition d'un monstre
	var free := Vector2i(-1, -1)
	for i in c.dungeon.w * c.dungeon.h:
		var cell := c.dungeon.cell(i)
		if c.dungeon.walkable(cell) and c.unit_at(cell) == null:
			free = cell
			break
	var n := c.units.size()
	c.god_tool = "spawn:orc"
	c.click_cell(free)
	check(c.units.size() == n + 1 and c.unit_at(free) != null and c.unit_at(free).key == "orc", "apparition d'un orc")
	check(c.order.has(c.unit_at(free)), "l'orc est dans l'ordre d'initiative")
	check(main.board.sprites.has(c.unit_at(free).id), "l'orc a un jeton sur le plateau")

	# Déplacer un jeton
	var orc := c.unit_at(free)
	var dest := Vector2i(-1, -1)
	for i in c.dungeon.w * c.dungeon.h:
		var cell := c.dungeon.cell(i)
		if c.dungeon.walkable(cell) and c.unit_at(cell) == null and cell != free:
			dest = cell
			break
	c.god_tool = "move"
	c.click_cell(free)
	c.click_cell(dest)
	check(orc.pos == dest, "déplacement libre d'un jeton")

	# Foudroyer / soigner
	c.god_tool = "kill"
	c.click_cell(dest)
	check(orc.dead, "foudroyer un monstre")
	c.god_tool = "heal"
	c.click_cell(h.pos)
	check(h.hp == h.max_hp, "soigner une unité")
	c.god_tool = ""

	# Contrôle des monstres : avancer jusqu'au tour d'un monstre
	c.set_god_option("control_monsters", true)
	for k in 30:
		var u := c.current()
		if u.side == "monster" and u.is_alive():
			break
		c.end_hero_turn()
		await get_tree().process_frame
	var m := c.current()
	check(m.side == "monster" and c.is_player_controlled(m) and not c.busy, "c'est à moi de jouer le monstre (%s)" % m.name)
	check(not m.abilities.is_empty(), "le monstre a des capacités utilisables")

	# Actions illimitées
	c.set_god_option("free_actions", true)
	check(c.ability_ready(m, m.abilities[0]) and m.moves_left >= 99, "actions et déplacement illimités")
	c.set_god_option("free_actions", false)
	c.set_god_option("control_monsters", false)

	# Partie : or, niveau, potions
	var gold: int = main.run.gold
	main.run.gold += 100
	check(main.run.gold == gold + 100, "+100 or")
	var lvl := h.level
	main.run.gain_xp(Data.LEVEL_XP[main.run.level + 1] - main.run.xp)
	check(h.level == lvl + 1 and not main.run.queue.is_empty(), "+1 niveau (et un choix de pouvoir en attente)")
	main.run.queue.clear()

	# Aller directement à l'acte 3
	c.end_hero_turn()
	for k in 200:
		if not c.busy:
			break
		await get_tree().process_frame
	main.god_goto(2, false)
	check(main.run.act == 2 and main.screens.is_open(), "aller directement à l'acte 3 (carte affichée)")
	main.enter_node(main.run.available_nodes()[0].id)
	await get_tree().process_frame
	check(c.dungeon.biome == "volcan", "le combat de l'acte 3 se passe dans le volcan")

	# Tuer tous les monstres -> victoire
	var won := [false]
	c.ended.connect(func(win): won[0] = win)
	for k in 200:
		if not c.busy:
			break
		await get_tree().process_frame
	c.god_kill_all_monsters()
	for k in 10:
		await get_tree().process_frame
	check(won[0], "tuer tous les monstres termine le niveau")

	print("RÉSULTAT : %s" % ("tout est OK" if fails == 0 else "%d échec(s)" % fails))
	get_tree().quit(1 if fails else 0)
