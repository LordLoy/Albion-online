class_name RunState
extends RefCounted
## L'état d'une partie roguelike : groupe, or, potions, XP, acte en cours et carte de parcours.
## Aucune interface ici : uniquement la logique (les écrans sont dans screens.gd).

var heroes: Array[Unit] = []
var act := 0
var row := -1
var nodes: Array = []        ## salles de la carte : {id, row, col, type, next: [ids], visited}
var pos := ""                ## id de la salle actuelle ("" = début de l'acte)
var gold := 40
var potions: Array = ["soin", "soin"]
var xp := 0
var level := 1
var stats := {"kills": 0, "fights": 0, "gold": 0}
var queue: Array = []        ## étapes en attente : {"type": "talent", "hero": Unit} ou {"type": "item", "item": clé}


func _init(class_keys: Array = []) -> void:
	for k in class_keys:
		heroes.append(Unit.make_hero(k))
	if not class_keys.is_empty():
		nodes = generate_map()


# ---------------------------------------------------------------------------
# Carte de parcours (style Slay the Spire)
# ---------------------------------------------------------------------------
func generate_map() -> Array:
	const COLS := 7
	var rows_n: int = Data.ACTS[act].rows
	var rows: Array = []
	for r in rows_n:
		var n := 3 if r == 0 else 2 + randi() % 3
		var cols := range(COLS)
		cols.shuffle()
		cols = cols.slice(0, n)
		cols.sort()
		var row_nodes := []
		for c in cols:
			row_nodes.append({"id": "%d-%d" % [r, c], "row": r, "col": c, "type": _pick_type(r, rows_n), "next": [], "visited": false})
		rows.append(row_nodes)
	for r in rows_n - 1:
		var cur: Array = rows[r]
		var nxt: Array = rows[r + 1]
		for n in cur:
			var sorted := nxt.duplicate()
			sorted.sort_custom(func(a, b): return absi(a.col - n.col) < absi(b.col - n.col))
			n.next.append(sorted[0].id)
			if sorted.size() > 1 and randf() < 0.4 and absi(sorted[1].col - n.col) <= 2:
				n.next.append(sorted[1].id)
		for m in nxt:
			if cur.any(func(n): return m.id in n.next):
				continue
			var near := cur.duplicate()
			near.sort_custom(func(a, b): return absi(a.col - m.col) < absi(b.col - m.col))
			near[0].next.append(m.id)
	var boss := {"id": "boss", "row": rows_n, "col": 3, "type": "boss", "next": [], "visited": false}
	for n in rows[rows_n - 1]:
		n.next.append("boss")
	var all := []
	for r in rows:
		all.append_array(r)
	all.append(boss)
	return all


func _pick_type(r: int, total: int) -> String:
	if r == 0:
		return "combat"
	if r == total - 1:
		return "camp"
	if r == total / 2 and randf() < 0.6:
		return "treasure"
	var table := [["combat", 45], ["event", 22], ["elite", 13 if r >= 2 else 0], ["shop", 10 if r >= 1 else 0],
		["camp", 7 if r >= 2 else 0], ["treasure", 3]]
	var total_w := 0
	for e in table:
		total_w += e[1]
	var t := randf() * total_w
	for e in table:
		t -= e[1]
		if t < 0:
			return e[0]
	return "combat"


func node(id: String) -> Dictionary:
	for n in nodes:
		if n.id == id:
			return n
	return {}


func available_nodes() -> Array:
	if pos == "":
		return nodes.filter(func(n): return n.row == 0)
	return node(pos).next.map(func(id): return node(id))


func enter(id: String) -> Dictionary:
	var n := node(id)
	pos = id
	row = n.row
	n.visited = true
	return n


func next_act() -> void:
	act += 1
	row = -1
	pos = ""
	nodes = generate_map()
	for h in heroes:
		h.hp = h.max_hp


# ---------------------------------------------------------------------------
# Rencontres
# ---------------------------------------------------------------------------
func build_encounter(kind: String) -> Dictionary:
	var a: Dictionary = Data.ACTS[act]
	if kind == "boss":
		var boss_name: String = Data.MONSTERS[a.boss].name
		return {"title": "Acte %d — %s" % [act + 1, boss_name], "monsters": [a.boss] + a.escort, "elite": -1, "boss": true}
	var scale := 0.45 + 0.15 * heroes.size()
	var budget: float = (a.budget_base + maxi(0, row) * a.budget_row) * scale * (0.55 if kind == "elite" else 1.0)
	var monsters: Array = []
	var elite := -1
	if kind == "elite":
		monsters.append(a.elites.pick_random())
		elite = 0
	while true:
		var affordable: Array = a.pool.filter(func(p): return p[1] <= budget)
		var pick: Array = affordable.pick_random() if not affordable.is_empty() else a.pool[0]
		monsters.append(pick[0])
		budget -= pick[1]
		if budget < 1.0 or monsters.size() >= 9:
			break
	var title := "Acte %d — %s" % [act + 1, "Salle d'élite" if kind == "elite" else "Salle %d" % (row + 1)]
	return {"title": title, "monsters": monsters, "elite": elite, "boss": false}


## Récompenses après une victoire. Retourne {gold, xp, potion, items}
func rewards_for(kills: Array, kind: String) -> Dictionary:
	var g := randi() % 8
	var x := 0
	for m in kills:
		var data: Dictionary = Data.MONSTERS[m.key]
		var mult := 3 if not m.elite.is_empty() else 1
		g += data.get("gold", 0) * mult
		x += data.get("xp", 0) * mult
	gold += g
	stats.gold += g
	stats.kills += kills.size()
	stats.fights += 1
	var r := {"gold": g, "xp": x, "potion": "", "items": []}
	if randf() < (0.35 if kind == "combat" else 0.8):
		var k: String = Data.POTIONS.keys().pick_random()
		if add_potion(k):
			r.potion = k
	if kind == "elite":
		r.items = random_items(3, 1, 3)
	elif kind == "boss":
		r.items = random_items(3, 2, 3)
	gain_xp(x)
	return r


# ---------------------------------------------------------------------------
# Objets, potions, XP
# ---------------------------------------------------------------------------
func random_items(n: int, min_rarity := 1, max_rarity := 3) -> Array:
	var keys: Array = Data.ITEMS.keys().filter(func(k): return Data.ITEMS[k].rarity >= min_rarity and Data.ITEMS[k].rarity <= max_rarity)
	keys.shuffle()
	return keys.slice(0, n)


func equip(hero: Unit, item_key: String) -> String:
	var slot: String = Data.ITEMS[item_key].slot
	var old: String = hero.items.get(slot, "")
	hero.items[slot] = item_key
	hero.recalc()
	return old


func add_potion(k: String) -> bool:
	if potions.size() >= Data.MAX_POTIONS:
		return false
	potions.append(k)
	return true


func heal_party_pct(p: float) -> void:
	for h in heroes:
		h.hp = mini(h.max_hp, h.hp + ceili(h.max_hp * p))


func gain_xp(n: int) -> void:
	xp += n
	while level + 1 < Data.LEVEL_XP.size() and xp >= Data.LEVEL_XP[level + 1]:
		level += 1
		for h in heroes:
			h.level = level
			h.recalc()
			h.hp = mini(h.max_hp, h.hp + Data.CLASSES[h.key].hp_lvl)
			queue.append({"type": "talent", "hero": h})


## Trois choix de montée de niveau : pouvoirs de classe non appris et talents passifs.
func talent_options(h: Unit) -> Array:
	var powers: Array = Data.CLASSES[h.key].powers.filter(func(p): return not (p.id in h.powers))
	powers.shuffle()
	var passives: Array = Data.TALENTS.filter(func(t): return (not t.has("cls") or t.cls == h.key) and not (t.has("cls") and t.id in h.talents))
	passives.shuffle()
	var out := []
	if not powers.is_empty():
		out.append({"kind": "power", "data": powers[0]})
	for t in passives:
		if out.size() >= 3:
			break
		out.append({"kind": "talent", "data": t})
	if out.size() < 3 and powers.size() > 1:
		out.append({"kind": "power", "data": powers[1]})
	return out


func learn(h: Unit, option: Dictionary) -> void:
	if option.kind == "power":
		h.powers.append(option.data.id)
	else:
		h.talents.append(option.data.id)
	h.recalc()


# ---------------------------------------------------------------------------
# Événements : applique les effets d'un choix. Retourne le texte du résultat,
# ou "FIGHT:<monstre>" si l'événement déclenche un combat.
# ---------------------------------------------------------------------------
func apply_event(choice: Dictionary) -> String:
	var e: Dictionary = choice.effects
	var msg: String = choice.get("result", "")
	if e.has("mimic") and randf() < e.mimic:
		return "FIGHT:mimique"
	if e.has("damage"):
		for h in heroes:
			if h.hp > 0:
				h.hp = maxi(1, h.hp - e.damage)
	if e.has("heal_pct"):
		heal_party_pct(e.heal_pct)
	if e.has("use_potion"):
		potions.erase(e.use_potion)
	if e.has("gold"):
		gold += e.gold
	if e.has("xp"):
		gain_xp(e.xp)
	for p in e.get("potions", []):
		add_potion(p)
	if e.has("random_potion"):
		var k: String = Data.POTIONS.keys().pick_random()
		add_potion(k)
		msg += " (%s)" % Data.POTIONS[k].name
	if e.has("item"):
		var it: String = random_items(1, e.item, e.item)[0]
		queue.push_front({"type": "item", "item": it})
		msg += "\nVous obtenez : %s." % Data.ITEMS[it].name
	if e.has("gamble"):
		var a := Dice.d20()
		var b := Dice.d20()
		if a > b:
			gold += e.gamble
			msg = "Vous faites %d, il fait %d. Vous gagnez %d or !" % [a, b, e.gamble]
		else:
			gold -= e.gamble
			msg = "Vous faites %d, il fait %d. Vous perdez %d or." % [a, b, e.gamble]
	return msg
