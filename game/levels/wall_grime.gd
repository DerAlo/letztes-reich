extends RefCounted
## Gebrauchsspuren als Decals an Innenwaenden (Bunker, Kanzleramt): Schmutzkante ueber dem Boden, Schrammen,
## Feuchteflecken, Rost-/Sickerfahnen von der Decke, Risse. Texturen: assets/environment/villa/decals und
## assets/environment/decals (eigene, CC0). Eigene Zufallsfolge je Level -> Spielablauf unberuehrt.
##
## Stil (style): "bunker" = feucht, verschmutzt; "office" = gepflegt, aber belagert (Schrammen, Schmutzkante,
## selten Wasserflecken).

const DIRS := ["res://assets/environment/villa/decals/", "res://assets/environment/decals/"]
const MAX_DECALS := 420


## Wandstueck a..b (y ignoriert), Boden y0, Decke y1; beide Wandseiten (Wandstaerke 2 * half_t).
static func wall(parent: Node3D, a: Vector3, b: Vector3, y0: float, y1: float, rng: RandomNumberGenerator,
		style: String = "bunker", half_t: float = 0.15) -> void:
	a.y = 0.0
	b.y = 0.0
	var ln := a.distance_to(b)
	var hgt := y1 - y0
	var n_now := int(parent.get_meta("wall_grime_n", 0))
	if ln < 1.0 or hgt < 2.0 or hgt > 6.0 or n_now > MAX_DECALS:
		return
	var office := style == "office"
	var dir := (b - a) / ln
	for s: float in [-1.0, 1.0]:
		var n := Vector3(-dir.z, 0.0, dir.x) * s
		var off := n * half_t
		var k := maxi(1, int(ln / (5.0 if office else 3.5)))
		for i in k:
			var u := (float(i) + rng.randf_range(0.25, 0.75)) / float(k)
			var p := a.lerp(b, u) + off
			# Schmutzkante (Stiefel, Wischwasser)
			if not office or rng.randf() < 0.6:
				var sh_h := rng.randf_range(0.3, 0.5) if office else rng.randf_range(0.4, 0.75)
				_decal(parent, p + Vector3(0, y0 + sh_h * 0.5 - 0.02, 0), n, minf(ln / float(k), rng.randf_range(1.8, 3.0)),
						sh_h, 1, "floor_grime.png", rng.randf_range(0.35, 0.55) if office else rng.randf_range(0.6, 0.9))
			if rng.randf() < 0.45:
				_decal(parent, p + Vector3(rng.randf_range(-0.5, 0.5), y0 + rng.randf_range(0.6, 1.1), 0), n, 1.1, 0.55, 0,
						"scuffs.png", rng.randf_range(0.4, 0.75), rng.randf_range(-0.15, 0.15))
			var wet := rng.randf()
			if wet < (0.1 if office else 0.3):
				# Feuchtefleck / Kalkausbluehung unter der Decke
				var ws := rng.randf_range(0.8, 1.6)
				var wh := ws * rng.randf_range(1.0, 1.5)
				_decal(parent, p + Vector3(rng.randf_range(-0.6, 0.6), y1 - wh * 0.45, 0), n, ws, wh, 1,
						"damp_stain.png", rng.randf_range(0.5, 0.8), rng.randf_range(-0.25, 0.25))
			elif not office and wet < 0.52:
				# Rostfahne / Sickerwasser von der Decke (rust_streak.png: Bildoberkante = Austritt, Laufspuren nach unten)
				var sh := minf(hgt * 0.75, rng.randf_range(1.1, 2.2))
				_decal(parent, p + Vector3(rng.randf_range(-0.6, 0.6), y1 - sh * 0.5, 0), n, rng.randf_range(0.45, 0.9), sh, 1,
						"rust_streak.png", rng.randf_range(0.55, 0.85))
			if rng.randf() < (0.06 if office else 0.12):
				_decal(parent, p + Vector3(rng.randf_range(-0.6, 0.6), y0 + rng.randf_range(0.9, hgt - 0.6), 0), n, 1.0, 1.0, 1,
						"crack.png", 0.5, rng.randf() * TAU, Color(0.5, 0.5, 0.5))


static func _decal(parent: Node3D, pos: Vector3, n: Vector3, w: float, h: float, dir_i: int, tex: String, alpha: float,
		roll: float = 0.0, tint: Color = Color.WHITE) -> void:
	var t := load(DIRS[dir_i] + tex) as Texture2D
	if t == null:
		return
	var d := Decal.new()
	d.texture_albedo = t
	d.modulate = Color(tint.r, tint.g, tint.b, alpha)
	d.size = Vector3(w, 0.3, h)
	d.normal_fade = 0.4
	d.upper_fade = 0.15
	d.lower_fade = 0.15
	d.distance_fade_enabled = true
	d.distance_fade_begin = 22.0
	d.distance_fade_length = 6.0
	var y := n.normalized()
	var x := Vector3.UP.cross(y).normalized()
	d.transform = Transform3D(Basis(x, y, x.cross(y).normalized()).rotated(y, roll), pos)
	parent.add_child(d)
	parent.set_meta("wall_grime_n", int(parent.get_meta("wall_grime_n", 0)) + 1)
