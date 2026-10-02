class_name Assets
## Chargement des images avec remplacement personnel.
##
## Pour chaque sprite ou tuile, le jeu cherche dans cet ordre :
##   1. res://assets_perso/sprites/<nom>/        → un dossier d'images = une animation (jouée en boucle)
##   2. res://assets_perso/sprites/<nom>.png     → une seule image
##   3. res://assets/sprites/<nom>.png           → l'image d'origine du jeu
## (même principe pour les tuiles : assets_perso/tiles/<nom>.png)
##
## Les images personnelles peuvent avoir n'importe quelle taille : les marges transparentes
## sont rognées automatiquement et le plateau les met à l'échelle d'une case.
## Le dossier assets_perso/ est ignoré par Git : il reste sur ton ordinateur.

const PERSO := "res://assets_perso/"

static var _frames_cache := {}
static var _tile_cache := {}


## Toutes les images (animation) d'un sprite, déjà rognées.
static func sprite_frames(key: String) -> Array:
	if _frames_cache.has(key):
		return _frames_cache[key]
	var frames: Array = []
	var dir := PERSO + "sprites/" + key
	if DirAccess.dir_exists_absolute(dir):
		var files: Array = []
		for f in DirAccess.get_files_at(dir):
			f = f.trim_suffix(".import")
			if f.get_extension().to_lower() == "png" and not (f in files):
				files.append(f)
		files.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
		for f in files:
			var t := _load(dir + "/" + f)
			if t:
				frames.append(t)
	if frames.is_empty():
		var t := _load(PERSO + "sprites/" + key + ".png")
		if t:
			frames.append(t)
	if frames.is_empty():
		frames.append(load("res://assets/sprites/%s.png" % key))
	else:
		frames = _crop_all(frames)
	_frames_cache[key] = frames
	return frames


## La première image d'un sprite (portraits, listes…)
static func sprite(key: String) -> Texture2D:
	return sprite_frames(key)[0]


## Une tuile (sol, mur…), éventuellement remplacée
static func tile(tile_name: String) -> Texture2D:
	if not _tile_cache.has(tile_name):
		var t := _load(PERSO + "tiles/" + tile_name + ".png")
		_tile_cache[tile_name] = t if t else load("res://assets/tiles/%s.png" % tile_name)
	return _tile_cache[tile_name]


## Charge une image : importée par Godot si possible, sinon directement depuis le fichier.
static func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img:
			return ImageTexture.create_from_image(img)
	return null


## Rogne les marges transparentes communes à toutes les images d'une animation
## (même cadre pour toutes, pour que le personnage ne « saute » pas).
static func _crop_all(frames: Array) -> Array:
	var used := Rect2i()
	for t in frames:
		var r: Rect2i = t.get_image().get_used_rect()
		if r.size == Vector2i.ZERO:
			continue
		used = r if used.size == Vector2i.ZERO else used.merge(r)
	if used.size == Vector2i.ZERO:
		return frames
	var out: Array = []
	for t in frames:
		var a := AtlasTexture.new()
		a.atlas = t
		a.region = Rect2(used)
		out.append(a)
	return out
