class_name Board
extends Node2D
## Le plateau : dessine les cases, les jetons et les effets, et gère la souris.

signal hovered(cell: Vector2i)   ## la souris survole une case (Vector2i(-1, -1) = aucune)

const TILE_PX := 16                     ## taille d'une case dans les images
const FACING := {"loup": -1}            ## sprites qui regardent vers la gauche par défaut

var combat: Combat
var cell := 48                          ## taille d'une case à l'écran (multiple de 16)
var hover := Vector2i(-1, -1)
var sprites := {}                       ## id d'unité -> Sprite2D
var effects: Array = []                 ## projectiles et explosions en cours

var _tex := {}
var _units_layer := Node2D.new()
var _overlay := Node2D.new()
var _time := 0.0


func _ready() -> void:
	for name in ["floor_0", "floor_1", "floor_2", "floor_3", "wall_top", "wall_face_0", "wall_face_1",
			"rubble", "water_0", "water_1"]:
		_tex[name] = load("res://assets/tiles/%s.png" % name)
	add_child(_units_layer)
	add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)


func setup(c: Combat) -> void:
	combat = c
	for s in sprites.values():
		s.queue_free()
	sprites.clear()
	effects.clear()
	for u in combat.units:
		var s := Sprite2D.new()
		s.texture = load("res://assets/sprites/%s.png" % u.sprite)
		_units_layer.add_child(s)
		sprites[u.id] = s
	layout()


## Calcule la taille des cases selon la place disponible et centre le plateau.
func layout() -> void:
	if combat == null:
		return
	var area: Rect2 = get_meta("area", Rect2(Vector2.ZERO, get_viewport_rect().size))
	var raw := mini(int(area.size.x / combat.MAP_W), int(area.size.y / combat.MAP_H))
	cell = maxi(32, raw / TILE_PX * TILE_PX)
	position = (area.position + (area.size - Vector2(combat.MAP_W, combat.MAP_H) * cell) / 2).floor()
	for u in combat.units:
		snap(u)
	refresh()


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell


## Place immédiatement le jeton d'une unité sur sa case.
func snap(u: Unit) -> void:
	var s: Sprite2D = sprites.get(u.id)
	if s == null:
		return
	var k := (1.4 if u.boss else 1.0) * cell / TILE_PX
	s.scale = Vector2(k, k)
	s.position = cell_center(u.pos) - Vector2(0, (k * TILE_PX - cell) / 2.0 + 2)


## Met à jour l'apparence des jetons (morts, inconscients…).
func refresh() -> void:
	if combat == null:
		return
	for u in combat.units:
		var s: Sprite2D = sprites.get(u.id)
		if s == null:
			continue
		s.visible = not u.dead
		s.modulate.a = 0.45 if u.hp <= 0 else 1.0
		s.rotation = PI / 2 if u.hp <= 0 else 0.0
	queue_redraw()


# ---------------------------------------------------------------------------
# Animations appelées par le combat
# ---------------------------------------------------------------------------
func step(u: Unit, speed_factor: float) -> void:
	var s: Sprite2D = sprites.get(u.id)
	var k := s.scale.x
	var target := cell_center(u.pos) - Vector2(0, (k * TILE_PX - cell) / 2.0 + 2)
	if target.x != s.position.x:
		s.flip_h = (target.x < s.position.x) != (FACING.get(u.sprite, 1) < 0)
	if speed_factor <= 0.0:
		s.position = target
		return
	var tw := create_tween()
	tw.tween_property(s, "position", target, 0.13 * speed_factor).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished


func shoot(u: Unit, c: Vector2i, color: Color, speed_factor: float) -> void:
	var d := Dungeon.dist(u.pos, c)
	if speed_factor <= 0.0 or d == 0:
		return
	var s: Sprite2D = sprites.get(u.id)
	if d <= 1:  # corps à corps : petite poussée vers la cible
		var start := s.position
		var tw := create_tween()
		tw.tween_property(s, "position", start.lerp(cell_center(c), 0.35), 0.09 * speed_factor)
		tw.tween_property(s, "position", start, 0.11 * speed_factor)
		await tw.finished
		return
	var dur := (0.12 + d * 0.035) * speed_factor
	effects.append({"type": "bolt", "from": cell_center(u.pos), "to": cell_center(c), "color": color, "t0": _time, "dur": dur})
	await get_tree().create_timer(dur).timeout


func boom(c: Vector2i, radius: int, color: Color) -> void:
	effects.append({"type": "boom", "at": cell_center(c), "r": (radius + 0.5) * cell, "color": color, "t0": _time, "dur": 0.6})


func hurt(u: Unit, crit: bool) -> void:
	var s: Sprite2D = sprites.get(u.id)
	if s:
		s.modulate = Color(3, 3, 3, s.modulate.a)
		create_tween().tween_property(s, "modulate", Color(1, 1, 1, 1), 0.2)
	if crit:
		var base := position
		var tw := create_tween()
		for i in 6:
			tw.tween_property(self, "position", base + Vector2(randf_range(-6, 6), randf_range(-6, 6)), 0.03)
		tw.tween_property(self, "position", base, 0.03)


func floater(c: Vector2i, text: String, color: Color) -> void:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = maxi(16, cell / 2)
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(cell * 3, cell)
	l.position = cell_center(c) - Vector2(cell * 1.5, cell * 1.1)
	_overlay.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - cell * 0.7, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------------------
# Dessin
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	queue_redraw()
	_overlay.queue_redraw()


func _draw() -> void:
	if combat == null or combat.dungeon == null:
		return
	var m := combat.dungeon
	var water_frame := int(_time * 2) % 2
	for y in m.h:
		for x in m.w:
			var c := Vector2i(x, y)
			var i := m.idx(c)
			var r := Rect2(Vector2(c) * cell, Vector2(cell, cell))
			var t := m.tiles[i]
			if t == Dungeon.WALL:
				var face := m.get_tile(c + Vector2i(0, 1)) != Dungeon.WALL and y + 1 < m.h
				draw_texture_rect(_tex["wall_face_%d" % int(m.deco[i] * 2)] if face else _tex.wall_top, r, false)
				continue
			draw_texture_rect(_tex["floor_%d" % int(m.deco[i] * 4)], r, false)
			if t == Dungeon.RUBBLE:
				draw_texture_rect(_tex.rubble, r, false)
			elif t == Dungeon.WATER:
				draw_texture_rect(_tex["water_%d" % ((water_frame + int(m.deco[i] * 2)) % 2)], r, false)
			if m.get_tile(c - Vector2i(0, 1)) == Dungeon.WALL:
				draw_rect(Rect2(r.position, Vector2(cell, cell * 0.18)), Color(0, 0, 0, 0.3))
	_draw_highlights()


func _cell_rect(c: Vector2i, fill: Color, border := Color.TRANSPARENT) -> void:
	var r := Rect2(Vector2(c) * cell + Vector2(1, 1), Vector2(cell - 2, cell - 2))
	draw_rect(r, fill)
	if border.a > 0:
		draw_rect(r, border, false, 2.0)


func _draw_highlights() -> void:
	var u := combat.current()
	if u == null or u.side != "hero" or combat.busy or combat.over or combat.autoplay:
		return
	var m := combat.dungeon
	var pulse := 0.5 + 0.5 * sin(_time * 4)
	var ab := combat.ability
	if not ab.is_empty():
		for i in m.w * m.h:
			var c := m.cell(i)
			if m.tiles[i] == Dungeon.WALL:
				continue
			if combat.is_valid_target(u, ab, c):
				var t := combat.unit_at(c)
				if t:
					_cell_rect(c, Color(0.35, 0.9, 0.55, 0.25 + pulse * 0.2) if ab.type == "heal" else Color(1, 0.27, 0.23, 0.25 + pulse * 0.2))
				else:
					_cell_rect(c, Color(0.6, 0.43, 0.86, 0.25) if ab.type == "teleport" else Color(1, 0.6, 0.23, 0.14))
			elif Dungeon.dist(u.pos, c) <= ab.get("range", 0):
				_cell_rect(c, Color(1, 0.6, 0.23, 0.05))
		if ab.type in ["aoe", "aoeAttack"] and m.inside(hover) and combat.is_valid_target(u, ab, hover):
			for dy in range(-ab.radius, ab.radius + 1):
				for dx in range(-ab.radius, ab.radius + 1):
					var c := hover + Vector2i(dx, dy)
					if m.inside(c) and m.get_tile(c) != Dungeon.WALL:
						_cell_rect(c, Color(1, 0.31, 0.12, 0.35), Color(1, 0.63, 0.31, 0.8))
		return
	if combat.reach.is_empty() or u.moves_left <= 0:
		return
	var d: Array = combat.reach.dist
	for i in d.size():
		if i == combat.reach.start or d[i] > u.moves_left or combat.unit_at(m.cell(i)):
			continue
		_cell_rect(m.cell(i), Color(0.27, 0.59, 1, 0.17))
	if m.inside(hover):
		var hi := m.idx(hover)
		if hi != combat.reach.start and d[hi] <= u.moves_left and combat.unit_at(hover) == null:
			var pts := PackedVector2Array([cell_center(u.pos)])
			for i in Dungeon.path_to(combat.reach, hi):
				pts.append(cell_center(m.cell(i)))
			draw_polyline(pts, Color(0.63, 0.82, 1, 0.95), 3.0)
			_cell_rect(hover, Color(0.27, 0.59, 1, 0.35), Color(0.63, 0.82, 1))
			draw_string(ThemeDB.fallback_font, Vector2(hover) * cell + Vector2(cell - 14, 18), str(int(d[hi])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Barres de vie, anneau du tour actif, projectiles, explosions (au-dessus des jetons)
func _draw_overlay() -> void:
	if combat == null:
		return
	var active := combat.current()
	for u in combat.units:
		if u.dead:
			continue
		var s: Sprite2D = sprites.get(u.id)
		var base := Vector2(s.position.x, cell_center(u.pos).y)
		if u == active and not combat.over:
			_draw_ellipse(base + Vector2(0, cell * 0.42), cell * 0.42, cell * 0.14, Color(1, 0.85, 0.42, 0.6 + 0.4 * sin(_time * 6)))
		var top := s.position.y - s.scale.y * TILE_PX / 2.0 - 4
		var bw := cell * 0.75
		var bar := Rect2(Vector2(base.x - bw / 2, top - 5), Vector2(bw, 5))
		_overlay.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
		var ratio := float(u.hp) / u.max_hp
		var col := Color("#4cc36b") if ratio > 0.5 else (Color("#e0b030") if ratio > 0.25 else Color("#d94040"))
		if u.side == "monster":
			col = Color("#d94a4a")
		_overlay.draw_rect(Rect2(bar.position, Vector2(bw * ratio, 5)), col)
	# Effets
	var still: Array = []
	for e in effects:
		var t: float = (_time - e.t0) / e.dur
		if t >= 1.0:
			continue
		still.append(e)
		if e.type == "bolt":
			var p: Vector2 = e.from.lerp(e.to, t)
			var tail: Vector2 = e.from.lerp(e.to, maxf(0.0, t - 0.18))
			_overlay.draw_line(tail, p, Color(e.color, 0.6), 3.0)
			_overlay.draw_circle(p, cell * 0.12, e.color)
		elif e.type == "boom":
			_overlay.draw_circle(e.at, e.r * (0.3 + 0.7 * t), Color(e.color, (1.0 - t) * 0.7))
	effects = still


func _draw_ellipse(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	_overlay.draw_polyline(pts, color, 2.0)


# ---------------------------------------------------------------------------
# Souris
# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if combat == null:
		return
	if event is InputEventMouseMotion:
		var c := Vector2i((get_local_mouse_position() / cell).floor())
		if not combat.dungeon.inside(c):
			c = Vector2i(-1, -1)
		if c != hover:
			hover = c
			hovered.emit(c)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT and combat.dungeon.inside(hover):
			combat.click_cell(hover)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			combat.cancel_targeting()
