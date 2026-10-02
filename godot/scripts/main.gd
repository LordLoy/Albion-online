extends Node
## Le chef d'orchestre : enchaîne l'écran de départ, la carte de parcours, les combats et les autres salles.
##
## Options de lancement (utiles pour tester sans jouer) :
##   godot -- --autoplay   : les héros jouent tout seuls et tous les choix sont automatiques
##   godot -- --fast       : animations instantanées
##   godot -- --start      : passe l'écran de départ (groupe par défaut)
##   godot -- --act=2      : commence directement à l'acte 2 (1, 2 ou 3)
##   godot -- --boss       : va directement au boss de l'acte
##   godot -- --god        : ouvre le panneau du mode dieu au démarrage
##   godot -- --shot=capture.png  : enregistre une capture d'écran après 4 secondes puis quitte

var combat := Combat.new()
var board := Board.new()
var hud := Hud.new()
var god_panel := GodPanel.new()
var screens := Screens.new()
var run: RunState
var autoplay := false
var current_kind := ""      ## type de la salle en cours ("combat", "elite", "boss"…)


func _ready() -> void:
	RenderingServer.set_default_clear_color(Hud.COL_BG)
	var args := OS.get_cmdline_user_args()
	autoplay = "--autoplay" in args

	add_child(combat)
	add_child(board)
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	ui_layer.add_child(hud)
	god_panel.main = self
	god_panel.combat = combat
	god_panel.visible = false
	god_panel.position = Vector2(12, Hud.TOP_H + 12)
	ui_layer.add_child(god_panel)
	screens.main = self
	screens.auto = autoplay
	add_child(screens)

	combat.board = board
	combat.autoplay = autoplay
	combat.speed_factor = 0.0 if "--fast" in args else 1.0
	hud.combat = combat
	combat.log_added.connect(hud.add_log)
	combat.changed.connect(_on_changed)
	combat.ended.connect(_on_fight_ended)
	hud.ability_pressed.connect(func(i): combat.select_ability(i))
	hud.end_turn_pressed.connect(func(): combat.end_hero_turn())
	board.hovered.connect(func(c): hud.show_tooltip(combat.unit_at(c) if combat.dungeon and combat.dungeon.inside(c) else null))
	get_viewport().size_changed.connect(_relayout)

	if autoplay or "--start" in args:
		new_run(["guerrier", "mage", "rodeur", "clerc"])
		for a in args:
			if a.begins_with("--act="):
				for i in clampi(int(a.trim_prefix("--act=")) - 1, 0, 2):
					run.next_act()
		if "--boss" in args:
			run.pos = run.nodes.filter(func(n): return n.row == Data.ACTS[run.act].rows - 1)[0].id
			enter_node("boss")
		elif not autoplay:
			show_map()
	else:
		screens.show_start()
	god_panel.visible = "--god" in args
	if god_panel.visible:
		_relayout.call_deferred()
	for a in args:
		if a.begins_with("--shot="):
			_screenshot(a.trim_prefix("--shot="))


func _screenshot(path: String) -> void:
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("Capture enregistrée : ", path)
	get_tree().quit()


## Zone du plateau : on laisse la place au panneau du mode dieu s'il est ouvert
func _board_area() -> Rect2:
	var area := hud.board_area()
	if god_panel.visible:
		var w: float = god_panel.size.x + 12
		area = Rect2(area.position + Vector2(w, 0), area.size - Vector2(w, 0))
	return area


func _relayout() -> void:
	board.set_meta("area", _board_area())
	board.layout()


func _on_changed() -> void:
	board.refresh()
	hud.update_all()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_F1 and run != null:
		god_panel.visible = not god_panel.visible
		_relayout()
		return
	if screens.is_open():
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			combat.end_hero_turn()
		KEY_ESCAPE:
			combat.cancel_targeting()
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_9:
				combat.select_ability(event.keycode - KEY_1)


# ---------------------------------------------------------------------------
# Déroulement de la partie
# ---------------------------------------------------------------------------
func new_run(keys: Array) -> void:
	run = RunState.new(keys)
	screens.run = run
	hud.run = run
	god_panel.refresh()
	screens.show_act_intro()


func show_map() -> void:
	if autoplay:
		print("Carte : acte %d, salle %d, %d or, niveau %d" % [run.act + 1, run.row + 2, run.gold, run.level])
	screens.show_map()


func enter_node(id: String) -> void:
	var n := run.enter(id)
	current_kind = n.type
	match n.type:
		"combat", "elite", "boss":
			launch_fight(run.build_encounter(n.type), n.type)
		"event":
			screens.show_event()
		"shop":
			screens.show_shop(screens.make_shop_stock())
		"treasure":
			screens.show_treasure()
		"camp":
			screens.show_camp()


func launch_fight(enc: Dictionary, kind: String) -> void:
	current_kind = kind
	screens.clear()
	hud.clear_log()
	board.set_meta("area", _board_area())
	combat.start_combat(run.heroes, enc, run.act, run.potions)


func _on_fight_ended(win: bool) -> void:
	if autoplay:
		print("  %s : %s (round %d)" % [combat.encounter.title, "victoire" if win else "défaite", combat.round_num])
	if not win:
		screens.show_game_over(false)
		if autoplay:
			print("FIN DE PARTIE : défaite à l'acte %d" % (run.act + 1))
			get_tree().quit()
		return
	screens.show_rewards(run.rewards_for(combat.kills, current_kind), current_kind)


## Après une salle : objets à attribuer, montées de niveau, puis carte (ou acte suivant)
func after_node() -> void:
	if not run.queue.is_empty():
		var step: Dictionary = run.queue.pop_front()
		if step.type == "item":
			screens.show_item_assign(step.item, after_node)
		else:
			screens.show_talent(step.hero, after_node)
		return
	if run.pos == "boss":
		if run.act >= Data.ACTS.size() - 1:
			screens.show_game_over(true)
			if autoplay:
				print("FIN DE PARTIE : victoire ! Niveau %d, %d monstres vaincus" % [run.level, run.stats.kills])
				get_tree().quit()
			return
		run.next_act()
		screens.show_act_intro()
		return
	show_map()


## Mode dieu : aller directement à un acte (et éventuellement à son boss)
func god_goto(act_index: int, boss: bool) -> void:
	if combat.busy and not combat.over:
		return
	while run.act < act_index:
		run.next_act()
	if run.act > act_index:
		run.act = act_index - 1
		run.next_act()
	if boss:
		run.pos = run.nodes.filter(func(n): return n.row == Data.ACTS[run.act].rows - 1)[0].id
		enter_node("boss")
	else:
		show_map()
