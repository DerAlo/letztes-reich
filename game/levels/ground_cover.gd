extends RefCounted
## Einbinden: const GroundCover = preload("res://game/levels/ground_cover.gd")
## Bodenbewuchs (Gras, Unkraut, Bluemchen, Steine, Reisig) als zellweise MultiMeshes.
## - Jede glTF-Teilgeometrie (Poly Haven: _a.._e) ist eine Variante, Fuss auf y=0, Mitte im Ursprung.
## - Materialien: Kopie des importierten StandardMaterial3D, Alpha-Scissor statt Blend, beidseitig,
##   Distanz-Fade per Pixel-Dither (umgekehrt: nah sichtbar, ab fade_end weg), kein Schattenwurf.
## - Zellen (Standard 18 m) mit visibility_range_end -> ferne Zellen werden gar nicht erst gezeichnet.
## Aufruf: GroundCover.scatter(parent, "grass02", xforms, {"fade": Vector2(30, 45)})
## xforms: Array[Transform3D] (Position + Drehung + Skala); die Hoehe der Variante ist auf 1 m normiert,
## wenn opts.height gesetzt ist (dann Skala = Wunschhoehe in Metern).

const DIRS := {
	"grass01": "res://assets/environment/rail/models/grass_medium_01/grass_medium_01.gltf",
	"shrub02": "res://assets/environment/rail/models/shrub_02/shrub_02.gltf",
	"grass02": "res://assets/environment/vegetation/models/grass_medium_02/grass_medium_02.gltf",
	"dandelion": "res://assets/environment/vegetation/models/dandelion_01/dandelion_01.gltf",
	"weed": "res://assets/environment/vegetation/models/weed_plant_02/weed_plant_02.gltf",
	"nettle": "res://assets/environment/vegetation/models/nettle_plant/nettle_plant.gltf",
	"rocks": "res://assets/environment/vegetation/models/rock_moss_set_02/rock_moss_set_02.gltf",
	"branches": "res://assets/environment/vegetation/models/dry_branches_medium_01/dry_branches_medium_01.gltf",
}

static var _variants := {}   # key|tint|fade -> Array[{mesh, xf, h}]

## A/B-Vergleich (Bildrate): mit "--no-veg" in den Nutzer-Argumenten bleibt der Bodenbewuchs leer.
static func disabled() -> bool:
	return "--no-veg" in OS.get_cmdline_user_args()

## Varianten eines Modells (optional nur Teile, deren Name 'only' enthaelt, und max. 'max_tris' Dreiecke).
static func variants(key: String, opts: Dictionary = {}) -> Array:
	var fade: Vector2 = opts.get("fade", Vector2(30, 45))
	var tint: Color = opts.get("tint", Color(1, 1, 1))
	var only: String = str(opts.get("only", ""))
	var max_tris: int = int(opts.get("max_tris", 6000))
	var ck := "%s|%s|%s|%s|%d" % [key, tint.to_html(), str(fade), only, max_tris]
	if _variants.has(ck):
		return _variants[ck]
	var out: Array = []
	var path: String = DIRS.get(key, key)
	var ps: PackedScene = load(path) if ResourceLoader.exists(path) else null
	if ps == null:
		push_warning("GroundCover: Modell fehlt: " + path)
		_variants[ck] = out
		return out
	var inst := ps.instantiate()
	var parts: Array = []
	_collect(inst, Transform3D.IDENTITY, parts, true)
	inst.free()
	var mats := {}
	for p in parts:
		var mesh: Mesh = p["mesh"]
		if only != "" and str(p["name"]).find(only) < 0:
			continue
		if _tris(mesh) > max_tris:
			continue
		var b: Basis = (p["xf"] as Transform3D).basis
		var bb: AABB = Transform3D(b, Vector3.ZERO) * mesh.get_aabb()
		if bb.size.y <= 0.001:
			continue
		var c := bb.get_center()
		var xf := Transform3D(b, Vector3(-c.x, -bb.position.y, -c.z))
		var m2: Mesh = mesh.duplicate()
		for s in m2.get_surface_count():
			var src: Material = mesh.surface_get_material(s)
			if not mats.has(src):
				mats[src] = _material(src, fade, tint)
			m2.surface_set_material(s, mats[src])
		out.append({"mesh": m2, "xf": xf, "h": bb.size.y, "name": str(p["name"])})
	_variants[ck] = out
	return out

static func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var idx = arr[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n

static func _collect(n: Node, xf: Transform3D, out: Array, is_root: bool) -> void:
	var t := xf
	if n is Node3D and not is_root:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": t, "name": str(n.name)})
	for c in n.get_children():
		_collect(c, t, out, false)

static func _material(src: Material, fade: Vector2, tint: Color) -> Material:
	var m: StandardMaterial3D
	if src is StandardMaterial3D:
		m = (src as StandardMaterial3D).duplicate()
	else:
		m = StandardMaterial3D.new()
	var alpha := m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if alpha else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.alpha_scissor_threshold = 0.45
	m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = m.albedo_color * tint
	if alpha:
		# Blattwerk: etwas Durchlicht, damit Gegenlicht-Halme nicht schwarz absaufen
		m.backlight_enabled = true
		m.backlight = Color(0.18, 0.2, 0.12) * tint
	# umgekehrter Fade: bis fade.x voll, ab fade.y unsichtbar (Dither, bleibt im Opaque-Pass)
	m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
	m.distance_fade_min_distance = fade.y
	m.distance_fade_max_distance = fade.x
	return m

## Streut ein Modell. xforms: Array von Transform3D; Variante je Instanz per rng (oder Index).
## opts: fade (Vector2), cell (float), mult (Grundskala: Poly-Haven-Pflanzen sind real zu klein, Gras ~x2.5,
##       Brennnessel ~x4.5), height (alternativ: Wunschhoehe je Variante normieren),
##       tint (Color), only, max_tris, seed (int), shadows (bool, Standard aus).
static func scatter(parent: Node3D, key: String, xforms: Array, opts: Dictionary = {}) -> Node3D:
	var vars := variants(key, opts)
	var root := Node3D.new()
	root.name = "GC_" + key
	parent.add_child(root)
	if disabled() or vars.is_empty() or xforms.is_empty():
		return root
	var fade: Vector2 = opts.get("fade", Vector2(30, 45))
	var cell: float = float(opts.get("cell", 18.0))
	var want_h: float = float(opts.get("height", 0.0))
	var mult: float = float(opts.get("mult", 1.0))
	var shadows: bool = bool(opts.get("shadows", false))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(opts.get("seed", 4711))
	# Zellen x Varianten -> Transformliste
	var buckets := {}
	for xf: Transform3D in xforms:
		var vi := rng.randi() % vars.size()
		var v: Dictionary = vars[vi]
		var t: Transform3D = xf
		if want_h > 0.0:
			t = t.scaled_local(Vector3.ONE * (want_h / float(v["h"])))
		elif mult != 1.0:
			t = t.scaled_local(Vector3.ONE * mult)
		t = t * (v["xf"] as Transform3D)
		var ck := Vector3i(floori(xf.origin.x / cell), vi, floori(xf.origin.z / cell))
		if not buckets.has(ck):
			buckets[ck] = []
		buckets[ck].append(t)
	var reach := fade.y + cell * 0.75
	for ck: Vector3i in buckets:
		var list: Array = buckets[ck]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = vars[ck.y]["mesh"]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = reach
		mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		root.add_child(mmi)
	return root

## Hilfsfunktion: zufaellige Transforms in einem Rechteck, Filter-Callable(pos)->bool, Skala s.x..s.y.
## tilt = max. Neigung in Grad.
static func points(rng: RandomNumberGenerator, n: int, x0: float, x1: float, z0: float, z1: float,
		s: Vector2, ok: Callable = Callable(), y: float = 0.0, tilt: float = 6.0) -> Array:
	var out: Array = []
	for i in n:
		var p := Vector3(rng.randf_range(x0, x1), y, rng.randf_range(z0, z1))
		var yaw := rng.randf() * TAU
		var sc := rng.randf_range(s.x, s.y)
		var tx := deg_to_rad(rng.randf_range(-tilt, tilt))
		var tz := deg_to_rad(rng.randf_range(-tilt, tilt))
		if ok.is_valid() and not ok.call(p):
			continue
		var b := Basis.from_euler(Vector3(tx, yaw, tz)).scaled(Vector3.ONE * sc)
		out.append(Transform3D(b, p))
	return out
