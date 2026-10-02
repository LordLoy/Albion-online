class_name Screens
extends CanvasLayer
## Tous les écrans hors combat : départ, carte de parcours, récompenses, équipement,
## montée de niveau, feu de camp, marchand, trésor, événements, fin de partie.

var main                    ## le chef d'orchestre (main.gd)
var run: RunState
var auto := false           ## mode démo : choisit tout seul (pour les tests)

const RARITY_COLORS := [Color("#3d3745"), Color("#8a8290"), Color("#3a6aa8"), Color("#8a4ab8")]


func _init() -> void:
	layer = 10


func clear() -> void:
	for c in get_children():
		c.queue_free()


func is_open() -> bool:
	return get_child_count() > 0


# ---------------------------------------------------------------------------
# Briques d'interface
# ---------------------------------------------------------------------------
func _backdrop() -> Control:
	clear()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.04, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	return dim


## Fenêtre centrée ; retourne la colonne où ajouter le contenu
func dialog(title: String, width := 640) -> VBoxContainer:
	var dim := _backdrop()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL, Hud.COL_BORDER, 12, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(Hud.label(title, 28, Hud.COL_GOLD))
	return col


func text(t: String, size := 15, color := Hud.COL_TEXT) -> Label:
	var l := Hud.label(t, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 300
	return l


func button(t: String, cb: Callable, primary := true) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_font_size_override("font_size", 16)
	var bg := Hud.COL_GOLD if primary else Hud.COL_PANEL2
	var fg := Color("#1a1408") if primary else Hud.COL_TEXT
	for s in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(s, fg)
	b.add_theme_color_override("font_disabled_color", Color(fg, 0.45))
	b.add_theme_stylebox_override("normal", Hud.style(bg, Color.TRANSPARENT if primary else Hud.COL_BORDER, 8, 10))
	b.add_theme_stylebox_override("hover", Hud.style(bg.lightened(0.15), Hud.COL_GOLD, 8, 10))
	b.add_theme_stylebox_override("pressed", Hud.style(bg.darkened(0.1), Hud.COL_GOLD, 8, 10))
	b.add_theme_stylebox_override("disabled", Hud.style(bg.darkened(0.5), Color.TRANSPARENT, 8, 10))
	b.pressed.connect(cb)
	return b


func icon(path: String, size := 32) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path)
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


func sprite(key: String, size := 48) -> TextureRect:
	return icon("res://assets/sprites/%s.png" % key, size)


func item_icon_path(k: String) -> String:
	return "res://assets/icons/%s.png" % Data.ITEMS[k].slot


## Carte cliquable (objet, talent, potion…) : icône, titre, description, bas de carte optionnel
func card(icon_path: String, title: String, desc: String, border: Color, cb: Callable, footer := "", disabled := false) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(180, 196)
	b.disabled = disabled
	b.add_theme_stylebox_override("normal", Hud.style(Hud.COL_PANEL2, border, 10, 10))
	b.add_theme_stylebox_override("hover", Hud.style(Hud.COL_PANEL2.lightened(0.06), Hud.COL_GOLD, 10, 10))
	b.add_theme_stylebox_override("pressed", Hud.style(Hud.COL_PANEL2, Hud.COL_GOLD, 10, 10))
	b.add_theme_stylebox_override("disabled", Hud.style(Color("#1e1b22"), Hud.COL_BORDER, 10, 10))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -8
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := icon(icon_path, 40)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	for part in [[title, 15, Hud.COL_TEXT], [desc, 12, Hud.COL_MUTED], [footer, 14, Hud.COL_GOLD]]:
		if part[0] == "":
			continue
		var l := Hud.label(part[0], part[1], part[2])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 150
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
	b.pressed.connect(cb)
	return b


func row() -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	return r


func status_bar() -> HBoxContainer:
	var r := row()
	r.add_child(Hud.label("Or : %d" % run.gold, 15, Hud.COL_GOLD))
	var nxt: int = Data.LEVEL_XP[run.level + 1] if run.level + 1 < Data.LEVEL_XP.size() else run.xp
	r.add_child(Hud.label("   Niveau %d (%d/%d XP)   " % [run.level, run.xp, nxt], 15))
	r.add_child(Hud.label("Potions :", 15, Hud.COL_MUTED))
	for p in run.potions:
		var ic := icon("res://assets/icons/potion_%s.png" % p, 24)
		ic.tooltip_text = Data.POTIONS[p].name
		r.add_child(ic)
	return r


## Fiches du groupe (cliquables si pick_cb est fourni)
func party(pick_cb := Callable(), compare_item := "") -> HBoxContainer:
	var r := row()
	for i in run.heroes.size():
		var h: Unit = run.heroes[i]
		var p := PanelContainer.new()
		p.custom_minimum_size.x = 210
		p.add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL2, Hud.COL_BORDER, 8, 8))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(v)
		var top := row()
		top.add_child(sprite(h.sprite, 40))
		var id := VBoxContainer.new()
		id.add_child(Hud.label("%s  niv. %d" % [h.name, h.level], 15))
		var bar := ProgressBar.new()
		bar.max_value = h.max_hp
		bar.value = h.hp
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(120, 6)
		bar.add_theme_stylebox_override("background", Hud.style(Color("#111111"), Color.TRANSPARENT, 2, 0))
		bar.add_theme_stylebox_override("fill", Hud.style(Color("#4cc36b"), Color.TRANSPARENT, 2, 0))
		id.add_child(bar)
		id.add_child(Hud.label("PV %d/%d · CA %d · Vit. %d" % [h.hp, h.max_hp, h.ac, h.speed], 12, Hud.COL_MUTED))
		top.add_child(id)
		v.add_child(top)
		var gear := row()
		for slot in Data.SLOTS:
			var ic := icon("res://assets/icons/%s.png" % slot, 24)
			if h.items.has(slot):
				var it: Dictionary = Data.ITEMS[h.items[slot]]
				ic.tooltip_text = "%s : %s" % [it.name, it.desc]
			else:
				ic.modulate = Color(1, 1, 1, 0.2)
				ic.tooltip_text = "%s : vide" % Data.SLOTS[slot]
			gear.add_child(ic)
		var learned := h.powers.size() + h.talents.size()
		if learned:
			var ic := icon("res://assets/icons/pouvoir.png", 24)
			ic.tooltip_text = _learned_text(h)
			gear.add_child(ic)
		v.add_child(gear)
		if compare_item != "":
			var slot: String = Data.ITEMS[compare_item].slot
			var cur: String = h.items.get(slot, "")
			v.add_child(Hud.label("Remplace : %s" % (Data.ITEMS[cur].name if cur != "" else "rien"), 12, Hud.COL_GOLD))
		if pick_cb.is_valid():
			var b := button("Choisir", pick_cb.bind(i), false)
			v.add_child(b)
		r.add_child(p)
	return r


func _learned_text(h: Unit) -> String:
	var parts := PackedStringArray()
	for p in Data.CLASSES[h.key].powers:
		if p.id in h.powers:
			parts.append("Pouvoir : " + p.name)
	for t in Data.TALENTS:
		if t.id in h.talents:
			parts.append("Talent : %s (%s)" % [t.name, t.desc])
	return "\n".join(parts)


# ---------------------------------------------------------------------------
# Écran de départ
# ---------------------------------------------------------------------------
func show_start() -> void:
	var col := dialog("Donjon Tactique", 1180)
	col.add_child(text("Un roguelike tactique au tour par tour. Compose ton groupe (jusqu'à 4 héros), traverse les 3 actes — "
		+ "les Cryptes, la Forêt maudite et le Cœur du Volcan — et terrasse leurs boss. Si tout le groupe tombe, la partie est perdue.", 14, Hud.COL_MUTED))
	var chosen := {"guerrier": true, "mage": true, "rodeur": true, "clerc": true}
	var grid := row()
	col.add_child(grid)
	var cards := {}
	var count := Hud.label("", 15)
	var start := button("Commencer l'aventure", func(): pass)
	var refresh := func():
		for k in cards:
			cards[k].add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL2, Hud.COL_HERO if chosen.has(k) else Hud.COL_BORDER, 10, 12))
		count.text = "%d/4 héros" % chosen.size()
		start.disabled = chosen.is_empty()
	for k in Data.CLASSES:
		var c: Dictionary = Data.CLASSES[k]
		var cardp := PanelContainer.new()
		cardp.custom_minimum_size = Vector2(212, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 5)
		cardp.add_child(v)
		var img := sprite(k, 72)
		img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(img)
		var t := Hud.label(c.name, 18)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(t)
		var st := Hud.label("PV %d · CA %d · Vitesse %d" % [c.hp, c.ac, c.speed], 13, Hud.COL_MUTED)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(st)
		var d := Hud.label(c.desc, 13)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = 190
		v.add_child(d)
		var abs := PackedStringArray()
		for ab in c.abilities:
			if ab.type != "dash":
				abs.append("• " + ab.name)
		v.add_child(Hud.label("\n".join(abs), 12, Hud.COL_MUTED))
		var pw := PackedStringArray()
		for p in c.powers:
			pw.append("◆ " + p.name)
		v.add_child(Hud.label("Pouvoirs à débloquer :\n" + "\n".join(pw), 12, Color("#c86bff")))
		for child in v.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cardp.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				if chosen.has(k):
					chosen.erase(k)
				elif chosen.size() < 4:
					chosen[k] = true
				refresh.call())
		cards[k] = cardp
		grid.add_child(cardp)
	var bottom := row()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_child(count)
	start.custom_minimum_size.x = 260
	start.pressed.connect(func():
		var keys := []
		for k in Data.CLASSES:
			if chosen.has(k):
				keys.append(k)
		main.new_run(keys))
	bottom.add_child(start)
	col.add_child(bottom)
	refresh.call()


# ---------------------------------------------------------------------------
# Intro d'acte et carte de parcours
# ---------------------------------------------------------------------------
func show_act_intro() -> void:
	var a: Dictionary = Data.ACTS[run.act]
	var col := dialog("Acte %d — %s" % [run.act + 1, a.name])
	col.add_child(text(a.intro, 16))
	if run.act > 0:
		col.add_child(text("Vos héros reprennent leur souffle : tous les PV sont restaurés.", 14, Hud.COL_HERO))
	col.add_child(button("Continuer", func(): main.show_map()))
	if auto:
		main.show_map.call_deferred()


func show_map() -> void:
	var a: Dictionary = Data.ACTS[run.act]
	var dim := _backdrop()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	dim.add_child(margin)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	margin.add_child(h)

	# Colonne de gauche : groupe et inventaire
	var side := PanelContainer.new()
	side.custom_minimum_size.x = 470
	side.add_theme_stylebox_override("panel", Hud.style(Hud.COL_PANEL, Hud.COL_BORDER, 12, 18))
	h.add_child(side)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", 12)
	side.add_child(sc)
	sc.add_child(Hud.label("Acte %d — %s" % [run.act + 1, a.name], 24, Hud.COL_GOLD))
	sc.add_child(status_bar())
	var p := party()
	# Les fiches du groupe en 2 colonnes
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for c in p.get_children():
		p.remove_child(c)
		grid.add_child(c)
	p.queue_free()
	sc.add_child(grid)
	var legend := PackedStringArray()
	for k in Data.NODE_TYPES:
		legend.append("%s = %s" % [Data.NODE_TYPES[k].letter, Data.NODE_TYPES[k].name])
	var lg := text("  ·  ".join(legend), 12, Hud.COL_MUTED)
	sc.add_child(lg)
	sc.add_child(text("Choisis ta prochaine salle sur la carte (les cases dorées).", 13, Hud.COL_MUTED))

	# Carte
	var map_panel := PanelContainer.new()
	map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_panel.add_theme_stylebox_override("panel", Hud.style(Color("#1d1915"), Hud.COL_BORDER, 12, 30))
	h.add_child(map_panel)
	var area := Control.new()
	area.clip_contents = false
	map_panel.add_child(area)
	var avail := run.available_nodes().map(func(n): return n.id)
	var rows_n: int = a.rows + 1
	var place := func(n: Dictionary) -> Vector2:
		var col: int = 3 if n.type == "boss" else n.col
		return Vector2(col / 6.0, 1.0 - float(n.row) / rows_n - 0.04) * area.size
	area.draw.connect(func():
		for n in run.nodes:
			for id in n.next:
				var m := run.node(id)
				var on: bool = n.visited and (m.visited or id in avail)
				area.draw_line(place.call(n), place.call(m), Hud.COL_GOLD if on else Color("#4a4036"), 3.0 if on else 2.0)
	)
	var buttons := []
	for n in run.nodes:
		var t: Dictionary = Data.NODE_TYPES[n.type]
		var b := Button.new()
		var big: bool = n.type == "boss"
		var s := 72 if big else 46
		b.custom_minimum_size = Vector2(s, s)
		b.size = Vector2(s, s)
		b.text = t.letter
		b.tooltip_text = "%s — %s" % [t.name, t.desc]
		b.add_theme_font_size_override("font_size", 26 if big else 18)
		var can: bool = n.id in avail
		var border: Color = Hud.COL_GOLD if can else (t.color.darkened(0.3) if not n.visited else Hud.COL_GOLD.darkened(0.3))
		var bg := Color("#3a3020") if n.visited else Color("#2b2520")
		b.add_theme_color_override("font_color", t.color)
		b.add_theme_color_override("font_disabled_color", Color(t.color, 0.45 if not n.visited else 0.8))
		b.add_theme_stylebox_override("normal", Hud.style(bg, border, s / 2, 0))
		b.add_theme_stylebox_override("hover", Hud.style(bg.lightened(0.1), Hud.COL_GOLD, s / 2, 0))
		b.add_theme_stylebox_override("disabled", Hud.style(bg, border, s / 2, 0))
		b.disabled = not can
		var nid: String = n.id
		b.pressed.connect(func(): main.enter_node(nid))
		area.add_child(b)
		buttons.append([b, n, s])
		if can:
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "modulate", Color(1.3, 1.2, 0.9), 0.6)
			tw.tween_property(b, "modulate", Color.WHITE, 0.6)
	area.resized.connect(func():
		for e in buttons:
			e[0].position = place.call(e[1]) - Vector2(e[2], e[2]) / 2
		area.queue_redraw())
	if auto:
		main.enter_node.call_deferred(avail[0])


# ---------------------------------------------------------------------------
# Récompenses et équipement
# ---------------------------------------------------------------------------
func show_rewards(r: Dictionary, kind: String) -> void:
	var col := dialog("Boss vaincu !" if kind == "boss" else "Victoire !")
	var line := "+%d or   ·   +%d XP" % [r.gold, r.xp]
	if r.potion != "":
		line += "   ·   %s" % Data.POTIONS[r.potion].name
	col.add_child(Hud.label(line, 18, Hud.COL_GOLD))
	if not r.items.is_empty():
		col.add_child(Hud.label("Choisis un objet :", 16))
		var items := row()
		for k in r.items:
			var it: Dictionary = Data.ITEMS[k]
			items.add_child(card(item_icon_path(k), it.name, "%s\n(%s)" % [it.desc, Data.SLOTS[it.slot]], RARITY_COLORS[it.rarity],
				func(): run.queue.push_front({"type": "item", "item": k}); main.after_node()))
		col.add_child(items)
		col.add_child(button("Passer", func(): main.after_node(), false))
		if auto:
			run.queue.push_front({"type": "item", "item": r.items[0]})
			main.after_node.call_deferred()
	else:
		col.add_child(button("Continuer", func(): main.after_node()))
		if auto:
			main.after_node.call_deferred()


func show_item_assign(k: String, then: Callable) -> void:
	var it: Dictionary = Data.ITEMS[k]
	var col := dialog("%s  (%s)" % [it.name, Data.SLOTS[it.slot]], 960)
	col.add_child(text("%s. Quel héros doit le porter ? (il remplace l'objet du même emplacement)" % it.desc))
	col.add_child(party(func(i): run.equip(run.heroes[i], k); then.call(), k))
	col.add_child(button("Laisser l'objet", then, false))
	if auto:
		run.equip(run.heroes[0], k)
		then.call_deferred()


func show_talent(h: Unit, then: Callable) -> void:
	var col := dialog("Niveau %d : %s" % [h.level, h.name], 720)
	var top := row()
	top.add_child(sprite(h.sprite, 56))
	top.add_child(text("PV max %d. Choisis un nouveau pouvoir ou un talent :" % h.max_hp))
	col.add_child(top)
	var opts := run.talent_options(h)
	var cards_row := row()
	for o in opts:
		var d: Dictionary = o.data
		var is_power: bool = o.kind == "power"
		cards_row.add_child(card("res://assets/icons/pouvoir.png" if is_power else "res://assets/icons/accessoire.png",
			d.name, d.desc, Color("#8a4ab8") if is_power else Hud.COL_BORDER,
			func(): run.learn(h, o); then.call(), "Pouvoir actif" if is_power else "Talent passif"))
	col.add_child(cards_row)
	if auto:
		run.learn(h, opts[0])
		then.call_deferred()


# ---------------------------------------------------------------------------
# Salles sans combat
# ---------------------------------------------------------------------------
func show_camp() -> void:
	var col := dialog("Feu de camp", 960)
	col.add_child(text("Les flammes crépitent. Vous pouvez souffler un instant."))
	col.add_child(party())
	col.add_child(button("Se reposer : chaque héros récupère 40 % de ses PV", func(): run.heal_party_pct(0.4); main.after_node()))
	col.add_child(button("S'entraîner : un héros gagne un pouvoir ou un talent", func():
		var c2 := dialog("Qui s'entraîne ?", 960)
		c2.add_child(party(func(i): show_talent(run.heroes[i], func(): main.after_node())))
	, false))
	if auto:
		run.heal_party_pct(0.4)
		main.after_node.call_deferred()


func make_shop_stock() -> Dictionary:
	var items := []
	for k in run.random_items(3):
		items.append({"k": k, "price": 35 + Data.ITEMS[k].rarity * 25 + randi() % 15, "sold": false})
	var pots := []
	var keys: Array = Data.POTIONS.keys()
	keys.shuffle()
	for k in keys.slice(0, 3):
		pots.append({"k": k, "price": Data.POTIONS[k].price, "sold": false})
	return {"items": items, "potions": pots, "heal_used": false}


func show_shop(stock: Dictionary) -> void:
	var heal_price := 30
	var col := dialog("Le marchand", 980)
	col.add_child(text("« Des articles de qualité, pour des aventuriers de qualité ! »", 14, Hud.COL_MUTED))
	col.add_child(status_bar())
	col.add_child(Hud.label("Équipement", 16))
	var r1 := row()
	for s in stock.items:
		var it: Dictionary = Data.ITEMS[s.k]
		r1.add_child(card(item_icon_path(s.k), it.name, "%s\n(%s)" % [it.desc, Data.SLOTS[it.slot]], RARITY_COLORS[it.rarity],
			func():
				run.gold -= s.price
				s.sold = true
				show_item_assign(s.k, func(): show_shop(stock)),
			"Vendu" if s.sold else "%d or" % s.price, s.sold or run.gold < s.price))
	col.add_child(r1)
	col.add_child(Hud.label("Potions (%d/%d)" % [run.potions.size(), Data.MAX_POTIONS], 16))
	var r2 := row()
	for s in stock.potions:
		var p: Dictionary = Data.POTIONS[s.k]
		r2.add_child(card("res://assets/icons/potion_%s.png" % s.k, p.name, p.desc, Hud.COL_BORDER,
			func():
				run.gold -= s.price
				s.sold = true
				run.add_potion(s.k)
				show_shop(stock),
			"Vendu" if s.sold else "%d or" % s.price, s.sold or run.gold < s.price or run.potions.size() >= Data.MAX_POTIONS))
	r2.add_child(card("res://assets/icons/potion_soin.png", "Soins", "Soigne 50 % des PV de chaque héros.", Hud.COL_BORDER,
		func():
			run.gold -= heal_price
			stock.heal_used = true
			run.heal_party_pct(0.5)
			show_shop(stock),
		"Utilisé" if stock.heal_used else "%d or" % heal_price, stock.heal_used or run.gold < heal_price))
	col.add_child(r2)
	col.add_child(button("Partir", func(): main.after_node()))
	if auto:
		main.after_node.call_deferred()


func show_treasure() -> void:
	var items := run.random_items(3, 1, 2)
	var g := 25 + randi() % 25
	run.gold += g
	var col := dialog("Un coffre au trésor !")
	col.add_child(Hud.label("+%d or" % g, 18, Hud.COL_GOLD))
	col.add_child(Hud.label("Choisis un objet :", 16))
	var r := row()
	for k in items:
		var it: Dictionary = Data.ITEMS[k]
		r.add_child(card(item_icon_path(k), it.name, "%s\n(%s)" % [it.desc, Data.SLOTS[it.slot]], RARITY_COLORS[it.rarity],
			func(): run.queue.push_front({"type": "item", "item": k}); main.after_node()))
	col.add_child(r)
	col.add_child(button("Passer", func(): main.after_node(), false))
	if auto:
		main.after_node.call_deferred()


func show_event() -> void:
	var ev: Dictionary = Data.EVENTS.pick_random()
	var col := dialog(ev.title)
	col.add_child(text(ev.text, 16))
	for ch in ev.choices:
		var ok: bool = run.gold >= ch.get("need_gold", 0) and (not ch.has("need_potion") or ch.need_potion in run.potions)
		var b := button(ch.label, func(): _choose_event(ev, ch), false)
		b.disabled = not ok
		col.add_child(b)
	if auto:
		_choose_event.call_deferred(ev, ev.choices[-1])


func _choose_event(ev: Dictionary, ch: Dictionary) -> void:
	var msg := run.apply_event(ch)
	if msg.begins_with("FIGHT:"):
		main.launch_fight({"title": "C'était une Mimique !", "monsters": [msg.trim_prefix("FIGHT:")], "elite": -1, "boss": false}, "elite")
		return
	var col := dialog(ev.title)
	col.add_child(text(msg, 16))
	col.add_child(status_bar())
	col.add_child(button("Continuer", func(): main.after_node()))
	if auto:
		main.after_node.call_deferred()


func show_game_over(win: bool) -> void:
	var col := dialog("Le donjon est purifié !" if win else "Votre groupe a péri…")
	col.add_child(text("Le Dragon rouge s'effondre dans la lave. Les bardes chanteront vos exploits !" if win else
		"Vous êtes tombés à l'acte %d (%s), salle %d." % [run.act + 1, Data.ACTS[run.act].name, run.row + 1], 16))
	col.add_child(Hud.label("Monstres vaincus : %d   ·   Niveau %d   ·   Or ramassé : %d" % [run.stats.kills, run.level, run.stats.gold], 15, Hud.COL_GOLD))
	col.add_child(button("Nouvelle partie", func(): show_start()))
