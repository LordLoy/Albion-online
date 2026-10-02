class_name Hud
extends Control
## L'interface : barre du haut, ordre d'initiative, journal des dés, barre d'actions.
## Tout est construit en code pour rester simple à lire et à modifier.

signal ability_pressed(index: int)
signal end_turn_pressed

const TOP_H := 44
const SIDE_W := 380
const BOTTOM_H := 112

const COL_BG := Color("#17151a")
const COL_PANEL := Color("#221f26")
const COL_PANEL2 := Color("#2b2731")
const COL_BORDER := Color("#3d3745")
const COL_TEXT := Color("#e8e2d6")
const COL_MUTED := Color("#9a92a3")
const COL_GOLD := Color("#e3b95f")
const COL_HERO := Color("#5fd38d")
const COL_MONSTER := Color("#e05050")

var combat: Combat
var level_label: Label
var round_label: Label
var tracker: VBoxContainer
var log_box: RichTextLabel
var action_box: HBoxContainer
var tooltip: PanelContainer
var tooltip_label: RichTextLabel


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_side()
	_build_bottom()
	_build_tooltip()


static func style(bg: Color, border := Color.TRANSPARENT, radius := 6, pad := 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if border.a > 0:
		s.border_color = border
		s.set_border_width_all(2)
	return s


static func label(text: String, size := 15, color := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel(preset: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style(COL_PANEL, Color.TRANSPARENT, 0, 10))
	add_child(p)
	p.set_anchors_and_offsets_preset(preset)
	return p


func _build_top() -> void:
	var p := _panel(Control.PRESET_TOP_WIDE)
	p.offset_bottom = TOP_H
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	p.add_child(row)
	row.add_child(label("Donjon Tactique", 20, COL_GOLD))
	level_label = label("", 15)
	level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(level_label)
	row.add_child(label("F1 : mode dieu", 13, COL_MUTED))
	round_label = label("", 15, COL_GOLD)
	row.add_child(round_label)


func _build_side() -> void:
	var p := _panel(Control.PRESET_RIGHT_WIDE)
	p.offset_left = -SIDE_W
	p.offset_top = TOP_H
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	col.add_child(label("ORDRE D'INITIATIVE", 13, COL_GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 260
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	tracker = VBoxContainer.new()
	tracker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tracker)
	col.add_child(label("JOURNAL DES DÉS", 13, COL_GOLD))
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.selection_enabled = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_theme_font_size_override("normal_font_size", 14)
	log_box.add_theme_font_size_override("bold_font_size", 14)
	log_box.add_theme_stylebox_override("normal", style(Color("#1c1a20"), COL_BORDER, 6, 8))
	col.add_child(log_box)


func _build_bottom() -> void:
	var p := _panel(Control.PRESET_BOTTOM_WIDE)
	p.offset_top = -BOTTOM_H
	p.offset_right = -SIDE_W
	action_box = HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 10)
	p.add_child(action_box)


func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.add_theme_stylebox_override("panel", style(Color(0.08, 0.07, 0.1, 0.95), COL_BORDER, 6, 8))
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	tooltip_label = RichTextLabel.new()
	tooltip_label.bbcode_enabled = true
	tooltip_label.fit_content = true
	tooltip_label.custom_minimum_size.x = 240
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_child(tooltip_label)
	add_child(tooltip)


## Zone libre pour le plateau (entre les barres)
func board_area() -> Rect2:
	var vs := get_viewport_rect().size
	return Rect2(Vector2(12, TOP_H + 12), Vector2(vs.x - SIDE_W - 24, vs.y - TOP_H - BOTTOM_H - 24))


# ---------------------------------------------------------------------------
# Mises à jour
# ---------------------------------------------------------------------------
func add_log(bbcode: String) -> void:
	log_box.append_text(bbcode + "\n\n")


func clear_log() -> void:
	log_box.clear()


func update_all() -> void:
	if combat == null:
		return
	var lvl: Dictionary = Data.LEVELS[combat.level_idx]
	level_label.text = "Niveau %d/%d — %s" % [combat.level_idx + 1, Data.LEVELS.size(), lvl.name]
	round_label.text = "Round %d" % combat.round_num
	_update_tracker()
	_update_actions()


func _sprite_rect(key: String, size: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/sprites/%s.png" % key)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


func _update_tracker() -> void:
	for c in tracker.get_children():
		c.queue_free()
	var cur := combat.current()
	for u in combat.order:
		if u.dead:
			continue
		var row := PanelContainer.new()
		var border := COL_GOLD if u == cur else (COL_HERO if u.side == "hero" else COL_MONSTER).darkened(0.4)
		row.add_theme_stylebox_override("panel", style(Color("#3a3328") if u == cur else COL_PANEL2, border, 6, 4))
		row.modulate.a = 0.5 if u.hp <= 0 else 1.0
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		row.add_child(h)
		h.add_child(_sprite_rect(u.sprite, 28))
		var mid := VBoxContainer.new()
		mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mid.add_theme_constant_override("separation", 2)
		mid.add_child(label(u.name, 14))
		var bar := ProgressBar.new()
		bar.max_value = u.max_hp
		bar.value = u.hp
		bar.show_percentage = false
		bar.custom_minimum_size.y = 5
		bar.add_theme_stylebox_override("background", style(Color("#111111"), Color.TRANSPARENT, 2, 0))
		bar.add_theme_stylebox_override("fill", style(Color("#4cc36b") if u.side == "hero" else Color("#d65050"), Color.TRANSPARENT, 2, 0))
		mid.add_child(bar)
		h.add_child(mid)
		h.add_child(label("%d/%d" % [u.hp, u.max_hp], 13, COL_MUTED))
		h.add_child(label("%2d" % int(u.init), 14, COL_GOLD))
		tracker.add_child(row)


func _update_actions() -> void:
	for c in action_box.get_children():
		c.queue_free()
	var u := combat.current()
	if u == null or combat.over:
		return
	var portrait := PanelContainer.new()
	portrait.add_theme_stylebox_override("panel", style(Color("#15131a"), COL_HERO if u.side == "hero" else COL_MONSTER, 8, 4))
	portrait.add_child(_sprite_rect(u.sprite, 56))
	action_box.add_child(portrait)
	if not combat.is_player_controlled(u):
		action_box.add_child(label("Tour de %s…" % u.name, 18, COL_MUTED))
		return
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 200
	info.add_child(label("%s  niv. %d" % [u.name, u.level], 17))
	info.add_child(label("PV %d/%d · CA %d · Dépl. %d/%d" % [u.hp, u.max_hp, u.ac, u.moves_left, u.speed], 14, COL_MUTED))
	info.add_child(label(("● Action  " if not u.action_used else "○ Action  ") + ("◆ Bonus" if not u.bonus_used else "◇ Bonus"), 13, COL_HERO))
	action_box.add_child(info)
	for i in u.abilities.size():
		var ab: Dictionary = u.abilities[i]
		var b := Button.new()
		var cd: int = u.cooldowns.get(ab.id, 0)
		b.text = "%d. %s%s" % [i + 1, ab.name, "\n(recharge %d)" % cd if cd > 0 else ""]
		b.custom_minimum_size = Vector2(110, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.disabled = not combat.ability_ready(u, ab)
		b.tooltip_text = "%s\n%s\n%s" % [ab.name, ab.get("desc", ""), _ability_tags(u, ab)]
		var selected := combat.ability == ab
		b.add_theme_stylebox_override("normal", style(Color("#3d2a22") if selected else COL_PANEL2, Color("#ff8040") if selected else COL_BORDER, 8, 6))
		b.add_theme_stylebox_override("hover", style(COL_PANEL2, COL_GOLD, 8, 6))
		b.add_theme_stylebox_override("disabled", style(Color("#1e1b22"), COL_BORDER, 8, 6))
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func(): ability_pressed.emit(i))
		action_box.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_box.add_child(spacer)
	var end := Button.new()
	end.text = "Fin du tour\n(Espace)"
	end.custom_minimum_size = Vector2(130, 64)
	end.add_theme_color_override("font_color", COL_GOLD)
	end.add_theme_stylebox_override("normal", style(Color("#3b2f1c"), COL_GOLD, 8, 6))
	end.add_theme_stylebox_override("hover", style(Color("#4d3d22"), COL_GOLD, 8, 6))
	end.pressed.connect(func(): end_turn_pressed.emit())
	action_box.add_child(end)


func _ability_tags(u: Unit, ab: Dictionary) -> String:
	var tags := PackedStringArray(["Action bonus" if ab.get("bonus", false) else "Action"])
	if ab.has("range"):
		tags.append("Contact" if ab.range == 1 else "Portée %d" % ab.range)
	if ab.has("hit"):
		tags.append("+%d toucher" % (ab.hit + u.hit_bonus()))
	if ab.has("dmg"):
		tags.append("%s%s dégâts" % [ab.dmg, ("+%d" % u.dmg_bonus()) if u.dmg_bonus() else ""])
	if ab.has("heal"):
		tags.append("%s%s soins" % [ab.heal, ("+%d" % u.dmg_bonus()) if u.dmg_bonus() else ""])
	if ab.get("cd", 0) > 0:
		tags.append("Recharge %d" % ab.cd)
	return " · ".join(tags)


func show_tooltip(u: Unit) -> void:
	if u == null:
		tooltip.visible = false
		return
	var ab: Dictionary = u.abilities[0] if u.side == "hero" else u.attack
	var txt := "[b]%s[/b]%s\nPV %d/%d · CA %d · Vitesse %d\n[color=#9a92a3]%s : %s, %s[/color]" % [
		u.name, ("  niv. %d" % u.level) if u.side == "hero" else "", u.hp, u.max_hp, u.ac, u.speed,
		ab.name, "contact" if ab.range == 1 else "portée %d" % ab.range, ab.dmg]
	var cur := combat.current()
	if cur and cur.side == "hero" and u.side == "monster":
		var d := Dungeon.dist(cur.pos, u.pos)
		txt += "\nDistance : %d case%s" % [d, "s" if d > 1 else ""]
		if d > 1 and not combat.dungeon.has_los(cur.pos, u.pos):
			txt += " · [color=#9aa3b2]hors de vue[/color]"
	tooltip_label.text = txt
	tooltip.visible = true
	tooltip.reset_size()
	var mp := get_viewport().get_mouse_position()
	tooltip.position = Vector2(minf(mp.x + 18, get_viewport_rect().size.x - SIDE_W - 260), mp.y + 18)
