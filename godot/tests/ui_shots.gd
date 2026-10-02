extends Node
## Captures des écrans hors combat (pour vérifier l'interface) :
## xvfb-run godot --path godot res://tests/ui_shots.tscn -- --out=/chemin/dossier

func _ready() -> void:
	var out := "user://"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=") + "/"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main.new_run(["guerrier", "mage", "rodeur", "clerc"])
	main.run.gold = 150
	var shots := {
		"shop": func(): main.screens.show_shop(main.screens.make_shop_stock()),
		"talent": func(): main.screens.show_talent(main.run.heroes[1], func(): pass),
		"item": func(): main.screens.show_item_assign("mithril", func(): pass),
		"rewards": func(): main.screens.show_rewards({"gold": 42, "xp": 30, "potion": "feu", "items": ["croc", "trefle", "ecailles"]}, "elite"),
		"event": func(): main.screens.show_event(),
	}
	for k in shots:
		shots[k].call()
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "ui_" + k + ".png")
		print("Capture : ", k)
	get_tree().quit()
