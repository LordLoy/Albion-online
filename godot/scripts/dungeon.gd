class_name Dungeon
extends RefCounted
## La carte du combat : génération, déplacements (Dijkstra) et ligne de vue.

enum { FLOOR, WALL, RUBBLE, WATER }

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var w: int
var h: int
var tiles := PackedInt32Array()
var deco := PackedFloat32Array()   # valeur aléatoire par case (variantes de tuiles)


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
	return t == FLOOR or t == RUBBLE


func blocks_sight(c: Vector2i) -> bool:
	return get_tile(c) == WALL


## Coût de déplacement : les gravats comptent double.
func cost(c: Vector2i) -> int:
	return 2 if get_tile(c) == RUBBLE else 1


## Distance « grille » façon D&D 5e : une diagonale compte pour 1 case.
static func dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# ---------------------------------------------------------------------------
# Génération : une arène avec murs, piliers, bassins et gravats
# ---------------------------------------------------------------------------
func generate() -> void:
	for attempt in 100:
		_fill_random()
		if _make_connected():
			return
	push_error("Impossible de générer une carte")


func _fill_random() -> void:
	tiles.resize(w * h)
	tiles.fill(FLOOR)
	deco.resize(w * h)
	for i in w * h:
		deco[i] = randf()
	for x in w:
		_put(Vector2i(x, 0), WALL)
		_put(Vector2i(x, h - 1), WALL)
	for y in h:
		_put(Vector2i(0, y), WALL)
		_put(Vector2i(w - 1, y), WALL)
	# Murs en segments
	for s in 5 + randi() % 4:
		var horiz := randf() < 0.5
		var length := 2 + randi() % 4
		var start := Vector2i(4 + randi() % (w - 8), 1 + randi() % (h - 2))
		for i in length:
			_put(start + (Vector2i(i, 0) if horiz else Vector2i(0, i)), WALL)
	# Piliers 2×2
	for p in 2 + randi() % 3:
		var c := Vector2i(4 + randi() % (w - 9), 2 + randi() % (h - 5))
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			_put(c + d, WALL)
	# Bassins d'eau (bloquent le passage mais pas la vue)
	for p in randi() % 3:
		var c := Vector2i(5 + randi() % (w - 10), 2 + randi() % (h - 4))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cc := c + Vector2i(dx, dy)
				if get_tile(cc) == FLOOR and ((dx == 0 and dy == 0) or randf() < 0.6):
					_put(cc, WATER)
	# Gravats (terrain difficile)
	for y in range(1, h - 1):
		for x in range(3, w - 3):
			if get_tile(Vector2i(x, y)) == FLOOR and randf() < 0.09:
				_put(Vector2i(x, y), RUBBLE)
	# Zones de départ dégagées
	for y in range(1, h - 1):
		for x in [1, 2, w - 3, w - 2]:
			_put(Vector2i(x, y), FLOOR)


## Tout ce qui n'est pas atteignable depuis la gauche devient un mur.
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
		if not seen[i] and (tiles[i] == FLOOR or tiles[i] == RUBBLE):
			tiles[i] = WALL
	return true


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
