class_name Dungeon
extends RefCounted
## La carte du combat : génération, déplacements (Dijkstra) et ligne de vue.

## Types de cases. Les gravats et buissons ralentissent ; l'eau et la lave bloquent le passage mais pas la vue ;
## les murs et les arbres bloquent tout.
enum { FLOOR, WALL, RUBBLE, WATER, TREE, BUSH, LAVA, BRIDGE }

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var w: int
var h: int
var tiles := PackedInt32Array()
var deco := PackedFloat32Array()   # valeur aléatoire par case (variantes de tuiles)
var biome := "crypte"
var torches: Array[Vector2i] = []   # murs avec une torche (crypte)


func _init(width: int, height: int) -> void:
	w = width
	h = height


func idx(c: Vector2i) -> int:
	return c.y * w + c.x


func cell(i: int) -> Vector2i:
	return Vector2i(i % w, i / w)


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func get_tile(c: Vector2i) -> int:
	return tiles[idx(c)] if inside(c) else WALL


func walkable(c: Vector2i) -> bool:
	var t := get_tile(c)
	return t == FLOOR or t == RUBBLE or t == BUSH or t == BRIDGE


func blocks_sight(c: Vector2i) -> bool:
	var t := get_tile(c)
	return t == WALL or t == TREE


## Coût de déplacement : gravats et buissons comptent double.
func cost(c: Vector2i) -> int:
	var t := get_tile(c)
	return 2 if t == RUBBLE or t == BUSH else 1


## La case de bordure du biome (mur ou arbre)
func border_tile() -> int:
	return TREE if biome == "foret" else WALL


## Distance « grille » façon D&D 5e : une diagonale compte pour 1 case.
static func dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# ---------------------------------------------------------------------------
# Génération : une arène différente selon le biome
# ---------------------------------------------------------------------------
func generate(biome_name := "crypte") -> void:
	biome = biome_name
	for attempt in 200:
		_reset()
		match biome:
			"foret":
				_gen_forest()
			"volcan":
				_gen_volcano()
			_:
				_gen_crypt()
		for y in range(1, h - 1):   # zones de départ dégagées
			for x in [1, 2, w - 3, w - 2]:
				_put(Vector2i(x, y), FLOOR)
		if _make_connected():
			_place_torches()
			return
	push_error("Impossible de générer une carte")


func _reset() -> void:
	tiles.resize(w * h)
	tiles.fill(FLOOR)
	deco.resize(w * h)
	for i in w * h:
		deco[i] = randf()
	var b := border_tile()
	for x in w:
		_put(Vector2i(x, 0), b)
		_put(Vector2i(x, h - 1), b)
	for y in h:
		_put(Vector2i(0, y), b)
		_put(Vector2i(w - 1, y), b)


func _rand_inner(margin_x := 4, margin_y := 1) -> Vector2i:
	return Vector2i(margin_x + randi() % (w - 2 * margin_x), margin_y + randi() % (h - 2 * margin_y))


func _scatter(t: int, chance: float) -> void:
	for y in range(1, h - 1):
		for x in range(3, w - 3):
			if get_tile(Vector2i(x, y)) == FLOOR and randf() < chance:
				_put(Vector2i(x, y), t)


## Crypte : murs en segments, piliers, bassins, gravats
func _gen_crypt() -> void:
	for s in 5 + randi() % 4:
		var horiz := randf() < 0.5
		var start := _rand_inner(4, 1)
		for i in 2 + randi() % 4:
			_put(start + (Vector2i(i, 0) if horiz else Vector2i(0, i)), WALL)
	for p in 2 + randi() % 3:
		var c := _rand_inner(4, 2)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			_put(c + d, WALL)
	for p in randi() % 3:
		_blob(_rand_inner(5, 2), WATER, 0.6)
	_scatter(RUBBLE, 0.09)


## Forêt : bosquets d'arbres, buissons, une rivière avec deux ponts
func _gen_forest() -> void:
	for k in 9 + randi() % 5:
		var c := _rand_inner(4, 1)
		for i in 1 + randi() % 4:
			_put(c + Vector2i(randi() % 3 - 1, randi() % 3 - 1), TREE)
	var x := w / 2 + randi() % 5 - 2
	var river: Array[Vector2i] = []
	for y in range(1, h - 1):
		if randf() < 0.35:
			x = clampi(x + (1 if randf() < 0.5 else -1), 5, w - 7)
		for dx in 2:
			_put(Vector2i(x + dx, y), WATER)
			river.append(Vector2i(x + dx, y))
	var bridge_rows := [2 + randi() % (h / 2 - 2), h / 2 + 1 + randi() % (h / 2 - 3)]
	for c in river:
		if c.y in bridge_rows:
			_put(c, BRIDGE)
	_scatter(BUSH, 0.1)


## Volcan : coulées de lave avec passages, mares de lave, cendres, rochers
func _gen_volcano() -> void:
	for stream in 1 + randi() % 2:
		var x := 6 + randi() % (w - 12)
		var gap := 2 + randi() % (h - 5)
		for y in range(1, h - 1):
			if randf() < 0.3:
				x = clampi(x + (1 if randf() < 0.5 else -1), 5, w - 6)
			if y == gap or y == gap + 1:
				continue   # passage de basalte
			_put(Vector2i(x, y), LAVA)
	for p in 1 + randi() % 3:
		_blob(_rand_inner(5, 2), LAVA, 0.55)
	for r in 3 + randi() % 3:
		_put(_rand_inner(4, 1), WALL)
	_scatter(RUBBLE, 0.08)


func _blob(c: Vector2i, t: int, chance: float) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cc := c + Vector2i(dx, dy)
			if get_tile(cc) == FLOOR and ((dx == 0 and dy == 0) or randf() < chance):
				_put(cc, t)


## Tout ce qui n'est pas atteignable depuis la gauche est bouché.
func _make_connected() -> bool:
	var seen := PackedByteArray()
	seen.resize(w * h)
	var stack: Array[Vector2i] = [Vector2i(1, 1)]
	seen[idx(stack[0])] = 1
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		for i in 4:
			var n: Vector2i = c + DIRS[i]
			if walkable(n) and not seen[idx(n)]:
				seen[idx(n)] = 1
				stack.append(n)
	for y in range(1, h - 1):
		if not seen[idx(Vector2i(w - 2, y))]:
			return false
	for i in w * h:
		if not seen[i] and walkable(cell(i)):
			tiles[i] = border_tile()
	return true


func _place_torches() -> void:
	torches.clear()
	if biome != "crypte":
		return
	for i in w * h:
		var c := cell(i)
		if tiles[i] == WALL and walkable(c + Vector2i(0, 1)) and randf() < 0.18:
			torches.append(c)


func _put(c: Vector2i, t: int) -> void:
	if inside(c):
		tiles[idx(c)] = t


# ---------------------------------------------------------------------------
# Ligne de vue : les murs bloquent, l'eau non
# ---------------------------------------------------------------------------
func has_los(a: Vector2i, b: Vector2i) -> bool:
	var steps := dist(a, b) * 6
	for i in range(1, steps):
		var t := float(i) / steps
		var c := Vector2i(floori(a.x + 0.5 + (b.x - a.x) * t), floori(a.y + 0.5 + (b.y - a.y) * t))
		if c == a or c == b:
			continue
		if blocks_sight(c):
			return false
	return true


# ---------------------------------------------------------------------------
# Déplacement : Dijkstra depuis une unité. On traverse les alliés, pas les ennemis.
# Retourne { dist: Array (coût par case, INF si inaccessible), prev: PackedInt32Array, start: int }
# ---------------------------------------------------------------------------
func compute_reach(unit: Unit, units: Array, max_cost := INF) -> Dictionary:
	var n := w * h
	var d := []
	d.resize(n)
	d.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	var blocked := {}
	for o: Unit in units:
		if o.is_alive() and o.side != unit.side:
			blocked[idx(o.pos)] = true
	var start := idx(unit.pos)
	d[start] = 0.0
	while true:
		var best := -1
		var bd := INF
		for i in n:
			if not done[i] and d[i] < bd:
				bd = d[i]
				best = i
		if best < 0 or bd > max_cost:
			break
		done[best] = 1
		var bc := cell(best)
		for dir in DIRS:
			var nc := bc + dir
			if not walkable(nc):
				continue
			# pas de coupe de coin en diagonale
			if dir.x != 0 and dir.y != 0 and (not walkable(bc + Vector2i(dir.x, 0)) or not walkable(bc + Vector2i(0, dir.y))):
				continue
			var ni := idx(nc)
			if blocked.has(ni):
				continue
			var nd := bd + cost(nc)
			if nd < d[ni]:
				d[ni] = nd
				prev[ni] = best
	return {"dist": d, "prev": prev, "start": start}


## Chemin (liste d'index de cases, sans la case de départ) vers la case i.
static func path_to(reach: Dictionary, i: int) -> Array[int]:
	var path: Array[int] = []
	while i != reach.start and i != -1:
		path.append(i)
		i = reach.prev[i]
	if i == -1:
		return []
	path.reverse()
	return path
