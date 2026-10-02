extends Node
## Vérifie que les mécaniques des 3 boss se déclenchent.
## Lancer : godot --headless --path godot res://tests/boss_test.tscn
## Les héros jouent tout seuls et sont invincibles : on regarde ce que font les boss.

var fails := 0


func check(cond: bool, what: String) -> void:
	print(("  OK   " if cond else "  ÉCHEC ") + what)
	if not cond:
		fails += 1


func all_logs(log: Array) -> String:
	return "\n".join(log)


func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	var c: Combat = main.combat
	c.speed_factor = 0.0
	c.autoplay = true
	main.screens.auto = false   # on s'arrête après chaque combat de boss
	var expected := [
		["Ogre", ["Séisme se prépare", "Séisme", "rage folle"]],
		["Liche", ["squelette", "dernier phylactère"]],
		["Dragon", ["Souffle de feu se prépare", "s'envole"]],
	]
	for act in 3:
		main.new_run(["guerrier", "mage", "rodeur", "clerc"])
		var log := []
		var cb := func(t): log.append(t)
		c.log_added.connect(cb)
		c.god.invincible = true
		main.god_goto(act, true)
		if act == 1:   # la Liche est invulnérable tant qu'un phylactère est debout
			var liche: Unit = c.units.filter(func(u): return u.key == "liche")[0]
			var before := liche.hp
			c._deal_damage(liche, 20)
			check(liche.hp == before and all_logs(log).contains("bouclier nécrotique"), "Liche protégée par ses phylactères")
		for k in 4000:
			if c.over:
				break
			await get_tree().process_frame
		c.log_added.disconnect(cb)
		c.god.invincible = false
		var all := "\n".join(log)
		print("%s : combat terminé en %d rounds (%s) — %s, monstres : %s" % [expected[act][0], c.round_num, "fini" if c.over else "pas fini", c.encounter.get("title", "?"), ", ".join(c.units.filter(func(u): return u.side == "monster").map(func(u): return u.name))])
		check(c.over, "le combat contre %s se termine" % expected[act][0])
		for key in expected[act][1]:
			check(all.contains(key), "%s : « %s »" % [expected[act][0], key])
	print("RÉSULTAT : %s" % ("tout est OK" if fails == 0 else "%d échec(s)" % fails))
	get_tree().quit(1 if fails else 0)
