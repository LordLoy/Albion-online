class_name GodPanel
extends PanelContainer
## Le panneau du mode dieu (F1) : tout ce qu'il faut pour tester le jeu librement.

signal goto_level(index: int)   ## demande au chef d'orchestre de lancer un niveau

var combat: Combat
var _tool_buttons := {}
var _monster_pick: OptionButton
var _info: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", Hud.style(Color(0.1, 0.06, 0.14, 0.94), Color("#c86bff"), 10, 12))
	custom_minimum_size.x = 250
	var th := Theme.new()
	th.default_font_size = 13
	th.set_stylebox("normal", "Button", Hud.style(Color("#2a2033"), Color.TRANSPARENT, 5, 4))
	th.set_stylebox("hover", "Button", Hud.style(Color("#3a2c48"), Color.TRANSPARENT, 5, 4))
	th.set_stylebox("pressed", "Button", Hud.style(Color("#5a3a78"), Color("#c86bff"), 5, 4))
	theme = th
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	add_child(col)

	col.add_child(Hud.label("MODE DIEU  (F1)", 16, Color("#d9a3ff")))

	_section(col, "Règles")
	_toggle(col, "Héros invincibles", "invincible")
	_toggle(col, "Actions illimitées", "free_actions")
	_toggle(col, "Je contrôle les monstres", "control_monsters")

	_section(col, "Dés (d20)")
	var dice := OptionButton.new()
	for t in ["Normaux", "Toujours 20 (critique)", "Toujours 1 (échec)"]:
		dice.add_item(t)
	dice.item_selected.connect(func(i): Dice.forced_d20 = [0, 20, 1][i])
	col.add_child(dice)

	_section(col, "Vitesse des animations")
	var speed := OptionButton.new()
	for t in ["Normale", "Rapide", "Instantanée"]:
		speed.add_item(t)
	speed.item_selected.connect(func(i): combat.speed_factor = [1.0, 0.35, 0.0][i])
	col.add_child(speed)

	_section(col, "Outil (clic sur le plateau)")
	for t in [["", "Aucun"], ["move", "Déplacer un jeton"], ["kill", "Foudroyer une unité"],
			["heal", "Soigner une unité"], ["spawn", "Faire apparaître :"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = t[0] == ""
		b.pressed.connect(_select_tool.bind(t[0]))
		_tool_buttons[t[0]] = b
		col.add_child(b)
	_monster_pick = OptionButton.new()
	for k in Data.MONSTERS:
		_monster_pick.add_item(Data.MONSTERS[k].name)
		_monster_pick.set_item_metadata(_monster_pick.item_count - 1, k)
	_monster_pick.item_selected.connect(func(_i): _select_tool("spawn"))
	col.add_child(_monster_pick)

	_section(col, "Actions")
	col.add_child(_action("Tuer tous les monstres", func(): combat.god_kill_all_monsters()))
	col.add_child(_action("Soigner le groupe", func(): combat.god_heal_party()))
	col.add_child(_action("Groupe +1 niveau", func(): combat.god_level_up()))
	var levels := HBoxContainer.new()
	levels.add_child(Hud.label("Niveau :", 13, Hud.COL_MUTED))
	for i in Data.LEVELS.size():
		var b := Button.new()
		b.text = str(i + 1)
		b.tooltip_text = Data.LEVELS[i].name
		b.pressed.connect(func():
			if not combat.busy:
				goto_level.emit(i))
		levels.add_child(b)
	col.add_child(levels)

	_info = Hud.label("", 12, Hud.COL_MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 220
	col.add_child(_info)
	_select_tool("")


func _section(col: VBoxContainer, title: String) -> void:
	var l := Hud.label(title.to_upper(), 11, Hud.COL_GOLD)
	l.add_theme_constant_override("line_spacing", 0)
	col.add_child(HSeparator.new())
	col.add_child(l)


func _toggle(col: VBoxContainer, text: String, option: String) -> void:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(func(on): combat.set_god_option(option, on))
	col.add_child(c)


func _action(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _select_tool(tool: String) -> void:
	for k in _tool_buttons:
		_tool_buttons[k].set_pressed_no_signal(k == tool)
	combat.god_selected = null
	if tool == "spawn":
		combat.god_tool = "spawn:" + str(_monster_pick.get_selected_metadata())
	else:
		combat.god_tool = tool
	_info.text = {
		"": "Clique sur le plateau pour jouer normalement.",
		"move": "Clique sur un jeton, puis sur une case libre.",
		"kill": "Clique sur une unité pour la foudroyer.",
		"heal": "Clique sur une unité pour la soigner entièrement.",
		"spawn": "Clique sur une case libre pour y faire apparaître le monstre choisi.",
	}[tool]
	if combat and combat.dungeon:
		combat.changed.emit()
