extends Node
## Le chef d'orchestre : écran de départ, enchaînement des niveaux, fin de partie.
##
## Options de lancement (utiles pour tester sans jouer) :
##   godot -- --autoplay   : les héros jouent tout seuls
##   godot -- --fast       : animations instantanées
##   godot -- --start      : passe l'écran de départ (groupe par défaut)
##   godot -- --shot=capture.png  : enregistre une capture d'écran après 4 secondes puis quitte

var combat := Combat.new()
var board := Board.new()
var hud := Hud.new()
var screen_layer := CanvasLayer.new()
var heroes: Array[Unit] = []
var autoplay := false
var fast := false


func _ready() -> void:
	RenderingServer.set_default_clear_color(Hud.COL_BG)
	var args := OS.get_cmdline_user_args()
	autoplay = "--autoplay" in args
	fast = "--fast" in args

	add_child(combat)
	add_child(board)
	var ui_layer := CanvasLayer.new()
	add_child(ui_layer)
	ui_layer.add_child(hud)
	screen_layer.layer = 2
	add_child(screen_layer)

	combat.board = board
	combat.autoplay = autoplay
	combat.speed_factor = 0.0 if fast else 1.0
	hud.combat = combat
	combat.log_added.connect(hud.add_log)
	combat.changed.connect(_on_changed)
	combat.ended.connect(_on_level_ended)
	hud.ability_pressed.connect(func(i): combat.select_ability(i))
	hud.end_turn_pressed.connect(func(): combat.end_hero_turn())
	board.hovered.connect(func(c): hud.show_tooltip(combat.unit_at(c) if combat.dungeon and combat.dungeon.inside(c) else null))
	get_viewport().size_changed.connect(_relayout)

	if autoplay or "--start" in args:
		_start(["guerrier", "mage", "rodeur", "clerc"])
	else:
		_show_start_screen()
	for a in args:
		if a.begins_with("--shot="):
			_screenshot(a.trim_prefix("--shot="))


func _screenshot(path: String) -> void:
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(path)
	print("Capture enregistrée : ", path)
	get_tree().quit()


func _relayout() -> void:
	board.set_meta("area", hud.board_area())
	board.layout()


func _on_changed() -> void:
	board.refresh()
	hud.update_all()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed) or screen_layer.get_child_count() > 0:
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
func _start(keys: Array) -> void:
	heroes.clear()
	for k in keys:
		heroes.append(Unit.make_hero(k))
	hud.clear_log()
	_start_level(0)


func _start_level(index: int) -> void:
	board.set_meta("area", hud.board_area())
	combat.start_level(heroes, index)


func _on_level_ended(win: bool) -> void:
	if autoplay:
		print("RESULTAT niveau %d : %s (round %d)" % [combat.level_idx + 1, "victoire" if win else "défaite", combat.round_num])
	if not win:
		_show_end(false)
	elif combat.level_idx >= Data.LEVELS.size() - 1:
		_show_end(true)
	else:
		_show_level_up()


func _next_level() -> void:
	for h in heroes:
		h.level += 1
		h.max_hp += Data.CLASSES[h.key].hp_lvl
		h.hp = h.max_hp
	_start_level(combat.level_idx + 1)


# ---------------------------------------------------------------------------
# Écrans
# ---------------------------------------------------------------------------
func _clear_screen() -> void:
	for c in screen_layer.get_children():
		c.queue_free()


## Fond assombri + fenêtre centrée ; retourne le conteneur où ajouter le contenu
func _dialog(title: String, width := 600) -> VBoxContainer:
	_clear_screen()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL, Hud.COL_BORDER, 12, 24))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(Hud.label(title, 28, Hud.COL_GOLD))
	return col


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 46)
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", Color("#1a1408"))
	b.add_theme_color_override("font_hover_color", Color("#1a1408"))
	b.add_theme_color_override("font_disabled_color", Color("#1a1408", 0.5))
	b.add_theme_stylebox_override("normal", Hud.style(Hud.COL_GOLD, Color.TRANSPARENT, 8, 10))
	b.add_theme_stylebox_override("hover", Hud.style(Hud.COL_GOLD.lightened(0.15), Color.TRANSPARENT, 8, 10))
	b.add_theme_stylebox_override("disabled", Hud.style(Hud.COL_GOLD.darkened(0.5), Color.TRANSPARENT, 8, 10))
	b.pressed.connect(cb)
	return b


func _show_start_screen() -> void:
	var col := _dialog("Donjon Tactique", 1150)
	var intro := Hud.label("Compose ton groupe (jusqu'à 4 héros) et descends dans les 5 niveaux du donjon.", 15, Hud.COL_MUTED)
	col.add_child(intro)
	var chosen := {"guerrier": true, "mage": true, "rodeur": true, "clerc": true}
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	col.add_child(grid)
	var cards := {}
	var count := Hud.label("", 15)
	var start := _button("Commencer l'aventure", func(): pass)
	var refresh := func():
		for k in cards:
			cards[k].add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL2, Hud.COL_HERO if chosen.has(k) else Hud.COL_BORDER, 10, 12))
		count.text = "%d/4 héros" % chosen.size()
		start.disabled = chosen.is_empty()
	for k in Data.CLASSES:
		var c: Dictionary = Data.CLASSES[k]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(205, 0)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		var img := hud._sprite_rect(k, 72)
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(img)
		var title := Hud.label(c.name, 18)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(title)
		var stats := Hud.label("PV %d · CA %d · Vitesse %d" % [c.hp, c.ac, c.speed], 13, Hud.COL_MUTED)
		stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(stats)
		var desc := Hud.label(c.desc, 13)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 180
		v.add_child(desc)
		var abs := PackedStringArray()
		for ab in c.abilities:
			if ab.type != "dash":
				abs.append("• " + ab.name)
		v.add_child(Hud.label("\n".join(abs), 12, Hud.COL_MUTED))
		for child in v.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if chosen.has(k):
					chosen.erase(k)
				elif chosen.size() < 4:
					chosen[k] = true
				refresh.call())
		cards[k] = card
		grid.add_child(card)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 16)
	row.add_child(count)
	start.custom_minimum_size.x = 260
	start.pressed.connect(func():
		var keys := []
		for k in Data.CLASSES:
			if chosen.has(k):
				keys.append(k)
		_clear_screen()
		_start(keys))
	row.add_child(start)
	col.add_child(row)
	refresh.call()


func _show_level_up() -> void:
	var lvl: Dictionary = Data.LEVELS[combat.level_idx]
	var col := _dialog("Victoire !")
	col.add_child(Hud.label("%s est nettoyé en %d rounds." % [lvl.name, combat.round_num]))
	col.add_child(Hud.label("Vos héros se reposent et gagnent un niveau :"))
	for h in heroes:
		col.add_child(Hud.label("  %s : niveau %d → %d, PV max %d → %d" % [h.name, h.level, h.level + 1, h.max_hp,
			h.max_hp + Data.CLASSES[h.key].hp_lvl], 15, Hud.COL_HERO))
	var note := Hud.label("Chaque niveau : +PV, +1 aux dégâts et aux soins, +1 au toucher tous les 2 niveaux.", 13, Hud.COL_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(note)
	col.add_child(_button("Descendre plus profond", func():
		_clear_screen()
		_next_level()))
	if autoplay:
		_clear_screen()
		_next_level()


func _show_end(win: bool) -> void:
	var col := _dialog("Le donjon est purifié !" if win else "Défaite…")
	var txt := "L'Ogre est tombé. Vos héros ressortent couverts de gloire (et de poussière)." if win else \
		"Votre groupe a péri au niveau %d : %s." % [combat.level_idx + 1, Data.LEVELS[combat.level_idx].name]
	var l := Hud.label(txt)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(l)
	col.add_child(_button("Nouvelle partie", func(): _show_start_screen()))
	if autoplay:
		print("FIN DE PARTIE : %s" % ("victoire" if win else "défaite"))
		get_tree().quit()
