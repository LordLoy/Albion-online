class_name Board
extends Node2D
## Le plateau : dessine les cases, les jetons, la lumière et les effets, et gère la souris.
##
## Deux couches :
##  - le monde (ce nœud) : tuiles et jetons, assombris par l'ambiance et éclairés par des PointLight2D ;
##  - la surcouche (_overlay, dans un CanvasLayer) : surbrillances, barres de vie, effets, textes —
##    toujours bien lisibles, quelle que soit la lumière.

signal hovered(cell: Vector2i)   ## la souris survole une case (Vector2i(-1, -1) = aucune)

const TILE_PX := 16                     ## taille d'une case dans les images
const FACING := {"loup": -1, "salamandre": -1}  ## sprites qui regardent vers la gauche par défaut
const BOSS_SCALE := {"ogre": 1.5, "liche": 1.4, "dragon": 2.0}

## Ambiance de chaque biome : couleur de la nuit, lumière des héros, particules
const BIOMES := {
	"crypte": {"ambient": Color(0.30, 0.28, 0.38), "hero_light": Color(1.0, 0.85, 0.65), "particles": Color(0.85, 0.8, 0.7, 0.35)},
	"foret": {"ambient": Color(0.40, 0.50, 0.50), "hero_light": Color(0.85, 0.95, 1.0), "particles": Color(0.8, 1.0, 0.4, 0.9)},
	"volcan": {"ambient": Color(0.50, 0.33, 0.33), "hero_light": Color(1.0, 0.8, 0.6), "particles": Color(1.0, 0.55, 0.15, 0.9)},
}

var combat: Combat
var cell := 48                          ## taille d'une case à l'écran (multiple de 16)
var hover := Vector2i(-1, -1)
var sprites := {}                       ## id d'unité -> Sprite2D
var effects: Array = []                 ## projectiles et explosions en cours

var _units_layer := Node2D.new()
var _lights_layer := Node2D.new()
var _hero_lights := {}                  ## id d'héros -> PointLight2D
var _flicker: Array = []                ## lumières qui vacillent : [light, énergie de base, phase]
var _ambient := CanvasModulate.new()
var _overlay_layer := CanvasLayer.new()
var _overlay := Node2D.new()
var _particles := CPUParticles2D.new()
var _light_tex: GradientTexture2D
var _time := 0.0
var _shake := 0.0
var _base_pos := Vector2.ZERO


func _ready() -> void:
	add_child(_ambient)
	add_child(_units_layer)
	add_child(_lights_layer)
	_overlay_layer.layer = 1
	add_child(_overlay_layer)
	_overlay_layer.add_child(_overlay)
	_overlay.draw.connect(_draw_overlay)
	_overlay.add_child(_particles)
	_ambient.visible = false
	# Texture de lumière : un disque blanc qui s'estompe vers les bords
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	_light_tex = GradientTexture2D.new()
	_light_tex.gradient = g
	_light_tex.fill = GradientTexture2D.FILL_RADIAL
	_light_tex.fill_from = Vector2(0.5, 0.5)
	_light_tex.fill_to = Vector2(1.0, 0.5)
	_light_tex.width = 128
	_light_tex.height = 128


func setup(c: Combat) -> void:
	combat = c
	for s in sprites.values():
		s.queue_free()
	sprites.clear()
	effects.clear()
	for u in combat.units:
		_make_sprite(u)
	layout()


func _make_sprite(u: Unit) -> Sprite2D:
	var s := Sprite2D.new()
	var frames := Assets.sprite_frames(u.sprite)   # remplaçable via assets_perso/
	s.texture = frames[0]
	s.set_meta("frames", frames)
	_units_layer.add_child(s)
	sprites[u.id] = s
	return s


## Ajoute le jeton d'une unité apparue en cours de combat
func add_unit(u: Unit) -> void:
	_make_sprite(u)
	snap(u)
	boom(u.pos, 0, Color("#c86bff"))


## Calcule la taille des cases selon la place disponible, centre le plateau et place les lumières.
func layout() -> void:
	if combat == null or combat.dungeon == null:
		return
	var area: Rect2 = get_meta("area", Rect2(Vector2.ZERO, get_viewport_rect().size))
	var raw := mini(int(area.size.x / combat.MAP_W), int(area.size.y / combat.MAP_H))
	cell = maxi(32, raw / TILE_PX * TILE_PX)
	_base_pos = (area.position + (area.size - Vector2(combat.MAP_W, combat.MAP_H) * cell) / 2).floor()
	position = _base_pos
	for u in combat.units:
		snap(u)
	_setup_lighting()
	refresh()


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * cell


## Échelle d'un jeton : son image (quelle que soit sa taille) tient dans une case (plus grand pour les boss)
func _scale_for(u: Unit) -> float:
	var s: Sprite2D = sprites.get(u.id)
	var px := TILE_PX
	if s and s.texture:
		px = maxi(s.texture.get_width(), s.texture.get_height())
	return BOSS_SCALE.get(u.key, 1.0) * cell / px


func _sprite_height(u: Unit) -> float:
	var s: Sprite2D = sprites.get(u.id)
	return s.texture.get_height() if s and s.texture else TILE_PX


func _sprite_pos(u: Unit) -> Vector2:
	var k := _scale_for(u)
	return cell_center(u.pos) - Vector2(0, (k * _sprite_height(u) - cell) / 2.0 + 2)


## Place immédiatement le jeton d'une unité sur sa case.
func snap(u: Unit) -> void:
	var s: Sprite2D = sprites.get(u.id)
	if s == null:
		return
	var k := _scale_for(u)
	s.scale = Vector2(k, k)
	s.position = _sprite_pos(u)


## Met à jour l'apparence des jetons (morts, inconscients…).
func refresh() -> void:
	if combat == null:
		return
	for u in combat.units:
		var s: Sprite2D = sprites.get(u.id)
		if s == null:
			continue
		s.visible = not u.dead
		s.self_modulate.a = 0.45 if u.hp <= 0 else 1.0
		s.rotation = PI / 2 if u.hp <= 0 else 0.0
	for id in _hero_lights:
		var l: PointLight2D = _hero_lights[id]
		l.visible = sprites.has(id) and sprites[id].visible


# ---------------------------------------------------------------------------
# Lumière et ambiance
# ---------------------------------------------------------------------------
func _add_light(at: Vector2, color: Color, energy: float, radius_cells: float, flicker := false) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = _light_tex
	l.color = color
	l.energy = energy
	l.texture_scale = radius_cells * 2.0 * cell / 128.0
	l.position = at
	_lights_layer.add_child(l)
	if flicker:
		_flicker.append([l, energy, randf() * TAU])
	return l


func _setup_lighting() -> void:
	for l in _lights_layer.get_children():
		l.queue_free()
	_hero_lights.clear()
	_flicker.clear()
	var m := combat.dungeon
	var b: Dictionary = BIOMES.get(m.biome, BIOMES.crypte)
	_ambient.color = b.ambient
	_ambient.visible = true
	# Torches de la crypte
	for t in m.torches:
		_add_light(cell_center(t) + Vector2(0, cell * 0.6), Color(1.0, 0.62, 0.3), 1.3, 3.2, true)
	# Lueur de la lave (une lumière toutes les quelques cases de lave)
	var n := 0
	for i in m.w * m.h:
		if m.tiles[i] == Dungeon.LAVA and (i * 7919) % 3 == 0 and n < 24:
			_add_light(cell_center(m.cell(i)), Color(1.0, 0.45, 0.15), 1.0, 2.2, true)
			n += 1
	# Feux follets de la forêt
	if m.biome == "foret":
		for k in 5:
			var c := Vector2i(3 + randi() % (m.w - 6), 1 + randi() % (m.h - 2))
			_add_light(cell_center(c), Color(0.55, 1.0, 0.6), 0.6, 2.5, true)
	# Lumière autour de chaque héros
	for u in combat.heroes:
		var l := _add_light(Vector2.ZERO, b.hero_light, 0.45, 3.5)
		_hero_lights[u.id] = l
	_setup_particles(m.biome, b.particles)


func _setup_particles(biome: String, color: Color) -> void:
	var p := _particles
	var size := Vector2(combat.MAP_W, combat.MAP_H) * cell
	p.emitting = true
	p.amount = 40 if biome != "crypte" else 30
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.position = size / 2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = size / 2
	p.color = color
	p.scale_amount_min = 2.0
	p.scale_amount_max = 3.5
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.3, Color(1, 1, 1, 1))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	p.color_ramp = fade
	match biome:
		"volcan":   # braises qui montent
			p.direction = Vector2(0, -1)
			p.spread = 25
			p.gravity = Vector2(0, -12)
			p.initial_velocity_min = 10
			p.initial_velocity_max = 30
		"foret":    # lucioles qui flottent
			p.direction = Vector2(1, 0)
			p.spread = 180
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 4
			p.initial_velocity_max = 14
		_:          # poussière qui tombe doucement
			p.direction = Vector2(0, 1)
			p.spread = 40
			p.gravity = Vector2(0, 3)
			p.initial_velocity_min = 2
			p.initial_velocity_max = 8


# ---------------------------------------------------------------------------
# Animations appelées par le combat
# ---------------------------------------------------------------------------
func step(u: Unit, speed_factor: float) -> void:
	var s: Sprite2D = sprites.get(u.id)
	var target := _sprite_pos(u)
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
	await bolt(u.pos, c, color, speed_factor)


func bolt(from: Vector2i, to: Vector2i, color: Color, speed_factor: float) -> void:
	if speed_factor <= 0.0:
		return
	var dur := (0.12 + Dungeon.dist(from, to) * 0.035) * speed_factor
	effects.append({"type": "bolt", "from": cell_center(from), "to": cell_center(to), "color": color, "t0": _time, "dur": dur})
	await get_tree().create_timer(dur).timeout


func boom(c: Vector2i, radius: int, color: Color) -> void:
	effects.append({"type": "boom", "at": cell_center(c), "r": (radius + 0.5) * cell, "color": color, "t0": _time, "dur": 0.6})
	_burst(cell_center(c), color, 10 + radius * 10)


func hurt(u: Unit, crit: bool) -> void:
	var s: Sprite2D = sprites.get(u.id)
	if s:
		s.modulate = Color(3, 3, 3)
		create_tween().tween_property(s, "modulate", Color(1, 1, 1), 0.2)
	_burst(cell_center(u.pos), Color("#e6dcb8") if u.key in ["squelette", "liche", "phylactere"] else Color("#c83c3c"), 14 if crit else 7)
	if crit:
		shake(6)


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## Petite gerbe de particules (sang, étincelles…)
func _burst(at: Vector2, color: Color, n: int) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = n
	p.lifetime = 0.6
	p.direction = Vector2(0, -1)
	p.spread = 180
	p.gravity = Vector2(0, 260)
	p.initial_velocity_min = 40
	p.initial_velocity_max = 130
	p.scale_amount_min = 2.5
	p.scale_amount_max = 4.0
	p.color = color
	_overlay.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func floater(c: Vector2i, text: String, color: Color) -> void:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = maxi(15, cell * 2 / 5)
	ls.font_color = color
	ls.outline_size = 6
	ls.outline_color = Color(0, 0, 0, 0.85)
	l.label_settings = ls
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(cell * 4, cell)
	l.position = cell_center(c) - Vector2(cell * 2, cell * 1.1)
	_overlay.add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", l.position.y - cell * 0.7, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 1.1).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


# ---------------------------------------------------------------------------
# Boucle de rendu
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	# Tremblement d'écran
	if _shake > 0.3:
		position = _base_pos + Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_shake *= 0.86
	elif _shake > 0.0:
		_shake = 0.0
		position = _base_pos
	_overlay.position = position
	# Lumières qui vacillent, lumière qui suit les héros, respiration des jetons
	for f in _flicker:
		f[0].energy = f[1] * (0.85 + 0.1 * sin(_time * 7.0 + f[2]) + 0.06 * sin(_time * 17.0 + f[2] * 3.0))
	if combat:
		for u in combat.units:
			var s: Sprite2D = sprites.get(u.id)
			if s == null:
				continue
			s.offset.y = -0.5 + 0.5 * sin(_time * 3.0 + u.id) if u.hp > 0 else 0.0
			var frames: Array = s.get_meta("frames", [])
			if frames.size() > 1:   # animation (images personnelles)
				s.texture = frames[int(_time * 6.0 + u.id) % frames.size()]
			if u.is_object:
				s.self_modulate = Color(1.2 + 0.3 * sin(_time * 4.0), 1.0, 1.3 + 0.3 * sin(_time * 4.0))
			if _hero_lights.has(u.id):
				_hero_lights[u.id].position = s.position
	queue_redraw()
	_overlay.queue_redraw()


func _draw() -> void:
	if combat == null or combat.dungeon == null:
		return
	var m := combat.dungeon
	var frame := int(_time * 2) % 2
	for y in m.h:
		for x in m.w:
			var c := Vector2i(x, y)
			var i := m.idx(c)
			var r := Rect2(Vector2(c) * cell, Vector2(cell, cell))
			var v := m.deco[i]
			for tex in _tile_textures(m, c, m.tiles[i], v, frame):
				draw_texture_rect(Assets.tile(tex), r, false)
			if m.walkable(c) and m.blocks_sight(c - Vector2i(0, 1)):
				draw_rect(Rect2(r.position, Vector2(cell, cell * 0.18)), Color(0, 0, 0, 0.3))
	# Ombres des unités
	for u in combat.units:
		var s: Sprite2D = sprites.get(u.id)
		if u.dead or s == null:
			continue
		var w: float = cell * 0.32 * BOSS_SCALE.get(u.key, 1.0)
		_draw_ellipse_filled(Vector2(s.position.x, cell_center(u.pos).y + cell * 0.36), w, cell * 0.1, Color(0, 0, 0, 0.45))


## Les textures à empiler pour une case, selon le biome
func _tile_textures(m: Dungeon, c: Vector2i, t: int, v: float, frame: int) -> Array:
	var face := not m.blocks_sight(c + Vector2i(0, 1)) and c.y + 1 < m.h
	match m.biome:
		"foret":
			var grass := "grass_%d" % int(v * 4)
			match t:
				Dungeon.TREE: return ["tree"]
				Dungeon.WALL: return [grass, "tree"]
				Dungeon.BUSH: return [grass, "bush"]
				Dungeon.WATER: return ["river_%d" % ((frame + int(v * 2)) % 2)]
				Dungeon.BRIDGE: return ["bridge"]
				Dungeon.RUBBLE: return [grass, "rubble"]
				_: return [grass]
		"volcan":
			var basalt := "basalt_%d" % int(v * 4)
			match t:
				Dungeon.WALL: return ["rock_face_%d" % int(v * 2)] if face else ["rock_top"]
				Dungeon.LAVA: return ["lava_%d" % ((frame + int(v * 2)) % 2)]
				Dungeon.RUBBLE: return [basalt, "ash"]
				Dungeon.WATER: return ["lava_%d" % frame]
				_: return [basalt]
		_:
			var floor_t := "floor_%d" % int(v * 4)
			match t:
				Dungeon.WALL:
					if face:
						var out := ["wall_face_%d" % int(v * 2)]
						if c in m.torches:
							out.append("torch_%d" % (int(_time * 7 + c.x) % 3))
						return out
					return ["wall_top"]
				Dungeon.WATER: return ["water_%d" % ((frame + int(v * 2)) % 2)]
				Dungeon.RUBBLE: return [floor_t, "rubble"]
				_: return [floor_t]


func _draw_ellipse_filled(center: Vector2, rx: float, ry: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, color)


# ---------------------------------------------------------------------------
# Surcouche : dangers, attaques annoncées, surbrillances, barres de vie, effets
# ---------------------------------------------------------------------------
func _cell_rect(c: Vector2i, fill: Color, border := Color.TRANSPARENT) -> void:
	var r := Rect2(Vector2(c) * cell + Vector2(1, 1), Vector2(cell - 2, cell - 2))
	_overlay.draw_rect(r, fill)
	if border.a > 0:
		_overlay.draw_rect(r, border, false, 2.0)


func _draw_overlay() -> void:
	if combat == null or combat.dungeon == null:
		return
	var m := combat.dungeon
	var pulse := 0.5 + 0.5 * sin(_time * 5)
	# Flammes au sol
	for i in combat.hazards:
		var c := m.cell(i)
		var base := Vector2(c) * cell
		_cell_rect(c, Color(1, 0.35, 0.05, 0.25 + 0.1 * sin(_time * 9 + i)))
		for k in 3:
			var x := base.x + cell * (0.25 + 0.25 * k)
			var h := cell * (0.3 + 0.15 * sin(_time * 11 + i + k * 2))
			var y := base.y + cell * 0.85
			_overlay.draw_colored_polygon(PackedVector2Array([Vector2(x - cell * 0.1, y), Vector2(x + cell * 0.1, y), Vector2(x, y - h)]),
				Color(1, 0.6 + 0.2 * k / 3.0, 0.1, 0.85))
	# Attaques annoncées par les boss
	for tg in combat.telegraphs:
		for c in tg.cells:
			_cell_rect(c, Color(1, 0.1, 0.05, 0.22 + pulse * 0.25), Color(1, 0.3, 0.2, 0.9))
	if combat.god_selected:
		_cell_rect(combat.god_selected.pos, Color(0.78, 0.42, 1, 0.35), Color(0.78, 0.42, 1))
	_draw_highlights()
	_draw_bars()
	_draw_effects()


func _draw_highlights() -> void:
	var u := combat.current()
	if not combat.is_player_controlled(u) or combat.busy or combat.over:
		return
	var m := combat.dungeon
	var pulse := 0.5 + 0.5 * sin(_time * 4)
	var ab := combat.ability
	if not ab.is_empty():
		var rng := u.range_of(ab)
		for i in m.w * m.h:
			var c := m.cell(i)
			if m.blocks_sight(c):
				continue
			if combat.is_valid_target(u, ab, c):
				var t := combat.unit_at(c)
				if t:
					var friendly: bool = ab.type in ["heal", "shield", "cleanse"]
					_cell_rect(c, Color(0.35, 0.9, 0.55, 0.25 + pulse * 0.2) if friendly else Color(1, 0.27, 0.23, 0.25 + pulse * 0.2))
				else:
					_cell_rect(c, Color(0.6, 0.43, 0.86, 0.25) if ab.type == "teleport" else Color(1, 0.6, 0.23, 0.14))
			elif Dungeon.dist(u.pos, c) <= rng:
				_cell_rect(c, Color(1, 0.6, 0.23, 0.05))
		var rad := u.radius_of(ab)
		if ab.type in ["aoe", "aoeAttack"] and m.inside(hover) and combat.is_valid_target(u, ab, hover):
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					var c := hover + Vector2i(dx, dy)
					if m.inside(c) and not m.blocks_sight(c):
						_cell_rect(c, Color(1, 0.31, 0.12, 0.35), Color(1, 0.63, 0.31, 0.8))
		return
	if combat.reach.is_empty() or u.moves_left <= 0:
		return
	var d: Array = combat.reach.dist
	for i in d.size():
		if i == combat.reach.start or d[i] > u.moves_left or combat.unit_at(m.cell(i)):
			continue
		_cell_rect(m.cell(i), Color(0.35, 0.65, 1, 0.13) if not combat.hazards.has(i) else Color(1, 0.5, 0.2, 0.25))
	if m.inside(hover):
		var hi := m.idx(hover)
		if hi != combat.reach.start and d[hi] <= u.moves_left and combat.unit_at(hover) == null:
			var pts := PackedVector2Array([cell_center(u.pos)])
			for i in Dungeon.path_to(combat.reach, hi):
				pts.append(cell_center(m.cell(i)))
			_overlay.draw_polyline(pts, Color(0.63, 0.82, 1, 0.95), 3.0)
			_cell_rect(hover, Color(0.27, 0.59, 1, 0.35), Color(0.63, 0.82, 1))
			_overlay.draw_string(ThemeDB.fallback_font, Vector2(hover) * cell + Vector2(cell - 14, 18), str(int(d[hi])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Barres de vie, bouclier, états, anneau du tour actif
func _draw_bars() -> void:
	var active := combat.current()
	for u in combat.units:
		if u.dead:
			continue
		var s: Sprite2D = sprites.get(u.id)
		if s == null:
			continue
		var base := Vector2(s.position.x, cell_center(u.pos).y)
		if u == active and not combat.over:
			_draw_ellipse(base + Vector2(0, cell * 0.38), cell * 0.44, cell * 0.15, Color(1, 0.85, 0.42, 0.6 + 0.4 * sin(_time * 6)))
		var top := s.position.y - s.scale.y * s.texture.get_height() / 2.0 - 4
		var bw := cell * (0.75 if not u.boss else 1.3)
		var bar := Rect2(Vector2(base.x - bw / 2, top - 5), Vector2(bw, 5))
		_overlay.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
		var ratio := float(u.hp) / u.max_hp
		var col := Color("#4cc36b") if ratio > 0.5 else (Color("#e0b030") if ratio > 0.25 else Color("#d94040"))
		if u.side == "monster":
			col = Color("#c86bff") if not u.elite.is_empty() or u.is_object else Color("#d94a4a")
		_overlay.draw_rect(Rect2(bar.position, Vector2(bw * ratio, 5)), col)
		if u.shield > 0:
			_overlay.draw_rect(Rect2(bar.position - Vector2(0, 4), Vector2(bw * minf(1.0, float(u.shield) / u.max_hp), 3)), Color("#9be8ff"))
		var k := 0
		for st in u.status:
			_overlay.draw_rect(Rect2(Vector2(bar.position.x + k * 9, bar.end.y + 2), Vector2(7, 7)), Data.STATUS[st].color)
			k += 1
		if u.boss or not u.elite.is_empty():
			var star := "♛" if u.boss else "★"
			_overlay.draw_string(ThemeDB.fallback_font, Vector2(base.x - 6, top - 8), star, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color("#ff8a65") if u.boss else Color("#c86bff"))


func _draw_effects() -> void:
	var still: Array = []
	for e in effects:
		var t: float = (_time - e.t0) / e.dur
		if t >= 1.0:
			continue
		still.append(e)
		if e.type == "bolt":
			var p: Vector2 = e.from.lerp(e.to, t)
			var tail: Vector2 = e.from.lerp(e.to, maxf(0.0, t - 0.2))
			_overlay.draw_line(tail, p, Color(e.color, 0.6), 4.0)
			_overlay.draw_circle(p, cell * 0.14, Color(e.color, 0.35))
			_overlay.draw_circle(p, cell * 0.08, e.color)
		elif e.type == "boom":
			_overlay.draw_circle(e.at, e.r * (0.3 + 0.7 * t), Color(e.color, (1.0 - t) * 0.6))
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
	if combat == null or combat.dungeon == null:
		return
	if event is InputEventMouseMotion:
		var c := Vector2i(((get_global_mouse_position() - _base_pos) / cell).floor())
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
