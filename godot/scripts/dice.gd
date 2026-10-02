class_name Dice
## Lancers de dés façon D&D : « 1d20 », « 2d6+3 »…

static var _regex := RegEx.create_from_string("^(\\d+)d(\\d+)([+-]\\d+)?$")


## Dés truqués (mode dieu) : 0 = normal, sinon le d20 donne toujours cette valeur.
static var forced_d20 := 0


static func d20() -> int:
	return forced_d20 if forced_d20 > 0 else randi_range(1, 20)


## Lance une formule « XdY+Z ». Un critique double le nombre de dés.
## Retourne { total, rolls, mod, label }.
static func roll(expr: String, crit := false, bonus := 0) -> Dictionary:
	var m := _regex.search(expr.replace(" ", ""))
	assert(m != null, "Formule de dés invalide : " + expr)
	var n := int(m.get_string(1))
	var faces := int(m.get_string(2))
	var mod := (int(m.get_string(3)) if m.get_string(3) != "" else 0) + bonus
	if crit:
		n *= 2
	var rolls: Array[int] = []
	var total := 0
	for i in n:
		var r := randi_range(1, faces)
		rolls.append(r)
		total += r
	return {"total": maxi(0, total + mod), "rolls": rolls, "mod": mod, "label": "%dd%d" % [n, faces]}


static func fmt_mod(mod: int) -> String:
	if mod > 0:
		return " + %d" % mod
	if mod < 0:
		return " − %d" % -mod
	return ""


## Texte lisible d'un lancer : « 1d10 [7] + 3 »
static func fmt(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for v in r.rolls:
		parts.append(str(v))
	return "%s [%s]%s" % [r.label, ", ".join(parts), fmt_mod(r.mod)]
