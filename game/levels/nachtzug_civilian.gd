extends StaticBody3D
## Reisender im Nachtzug (Gruppe no_shoot). Faellt bei Treffern nicht um, sondern meldet
## dem Level jeden Spieler-Treffer (1. Warnung, 2. Abbruch – Logik im Level).
## Optik: MakeHuman-Zivilfigur (assets/characters/civilian/civ_<variant>.glb, Posen per Skelett
## vorgebacken – tools/civilian/build_civ.py); fehlt die Datei, bleibt die alte Kastenfigur.
## Kollisionsformen sind unabhaengig von der Optik (unveraendert).
## Nachtzug-Figuren civ_nz_<kind>.glb (tools/civilian/build_civ_nz.py) sind gehautet und haben je Pose
## eine 8-s-Schleife (Atmen, Blickwechsel): `anim` waehlt sie. take_cover(): Sitzende ducken sich tief
## (Kopf unter Tischhoehe), der Kauernde kriecht ins Abteil (cover_to) - Schusslinien im Gang bleiben frei.

@export var pose: String = "seat"     ## "seat" (Bank), "lie" (Bett, laengs x), "cower" (kauert)
@export var coat: Color = Color(0.25, 0.22, 0.2)
@export var legs: Color = Color(0.16, 0.16, 0.2)
@export var hair: Color = Color(0.2, 0.15, 0.1)
@export var skin: Color = Color(0.68, 0.52, 0.42)
@export var variant: String = ""        ## mantel|jacke|alt|frau|frau2|nz_<kind> (leer = Kastenfigur)
@export var anim: String = ""           ## gehautete Pose: seat|seat_table|seat_lean|seat_cross|cower (leer = statisch)
@export var cover_to: Vector3 = Vector3.ZERO   ## Ziel (Elternraum) beim Deckung-Suchen, nur "cower"; ZERO = bleibt

const CIV_DIR := "res://assets/characters/civilian/civ_%s.glb"
## Abstand Sohle -> Gesaess-Unterkante der Sitzpose je Figur (aus build_civ.py), Sitzflaeche 0,46 m
const SEAT_DROP := {"mantel": 0.461, "jacke": 0.45, "alt": 0.449, "frau": 0.448, "frau2": 0.412}
const SHADOW_DIST := 14.0
static var _meshes: Dictionary = {}     ## "variant/pose" -> Mesh (Materialien abgestimmt)
static var _scenes: Dictionary = {}     ## variant -> PackedScene (gehautet)
static var _mats: Dictionary = {}       ## "variant/surface/name" -> abgestimmtes Material
var _ap: AnimationPlayer = null
var _cover := false
var _home := Vector3.ZERO
var _home_rot := 0.0
var _home_set := false
var _crawl: Tween = null
var _shp: Array[CollisionShape3D] = []
var _real: MeshInstance3D = null
var _base := Vector3.ZERO
var _shadow_t: float = 0.0

var level: Node = null
var hits: int = 0
var _body: Node3D
var _torso: Node3D
var _t: float = 0.0
var _phase: float = 0.0
var _cool: float = 0.0

func _ready() -> void:
	collision_layer = 4 | 16
	collision_mask = 0
	set_meta("no_fit", true)
	set_meta("surface", "flesh")
	add_to_group("damageable")
	add_to_group("civilian")
	add_to_group("no_shoot")
	_phase = randf() * TAU
	_build()

func _m(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(parent: Node3D, s: Vector3, m: Material, p: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation_degrees = rot
	parent.add_child(mi)

func _shape(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.position = c
	add_child(cs)
	_shp.append(cs)

## Gehautete Nachtzug-Figur mit Idle-Schleife; false = nicht vorhanden (statischer Pfad).
func _build_anim() -> bool:
	if anim == "" or variant == "" or pose == "lie":
		return false
	var ps: PackedScene = _scenes.get(variant)
	if ps == null:
		var path := CIV_DIR % variant
		if not ResourceLoader.exists(path):
			return false
		ps = load(path) as PackedScene
		if ps == null:
			return false
		_scenes[variant] = ps
	var inst := ps.instantiate() as Node3D
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null or not ap.has_animation(anim):
		inst.free()
		return false
	_ap = ap
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_torso = Node3D.new()
	_torso.name = "Pose"
	_body.add_child(_torso)
	_torso.add_child(inst)
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		_real = mi
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 70.0
		mi.visibility_range_end_margin = 6.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if src == null:
				continue
			var key := "%s/%d/%s" % [variant, i, src.resource_name]
			var tm: Material = _mats.get(key)
			if tm == null:
				tm = _tune(src.duplicate() as BaseMaterial3D)
				_mats[key] = tm
			mi.set_surface_override_material(i, tm)
	for an: StringName in _ap.get_animation_list():
		var a := _ap.get_animation(an)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
	_ap.speed_scale = randf_range(0.85, 1.1)
	_ap.play(anim)
	_ap.seek(randf() * _ap.current_animation_length, true)
	if pose == "cower":
		# Gesicht nach +Z (zur Abteiltuer), etwas von der Wand weg
		inst.rotation.y = 0.0
		_base = Vector3(0, 0.0, 0.12)
	else:
		# Modell schaut in Blender nach -Y -> glTF +Z; Reisender schaut nach -Z. Ursprung = Gesaess, Sitz 0,46 m
		inst.rotation.y = PI
		_base = Vector3(0, 0.46, 0.05)
	_torso.position = _base
	_anim_shapes()
	return true

## Kollisionsformen der gehauteten Figur je Zustand (Treffer nur dort, wo auch Koerper ist).
func _anim_shapes() -> void:
	for cs in _shp:
		if is_instance_valid(cs):
			cs.queue_free()
	_shp.clear()
	if pose == "cower":
		_shape(Vector3(0, 0.36, 0.14), Vector3(0.5, 0.72, 0.62))
		_shape(Vector3(0, 0.76, 0.2), Vector3(0.3, 0.2, 0.32))
		return
	_shape(Vector3(0, 0.3, -0.25), Vector3(0.4, 0.6, 0.5))
	if _cover:
		# tief vorgebeugt: Ruecken und Kopf ueber den Oberschenkeln, Oberkante ~0,74 m
		_shape(Vector3(0, 0.6, -0.2), Vector3(0.5, 0.28, 0.55))
	else:
		var lean := -0.12 if anim == "seat_table" else 0.0
		_shape(Vector3(0, _hip() + 0.31, 0.02 + lean), Vector3(0.46, 0.6, 0.3))
		_shape(Vector3(0, _hip() + 0.78, lean * 2.0), Vector3(0.24, 0.28, 0.25))

## Kampf beginnt: Sitzende ducken sich, der Kauernde kriecht ins Abteil.
func take_cover() -> void:
	if _cover or _ap == null:
		return
	_cover = true
	if not _home_set:
		_home = position
		_home_rot = rotation.y
		_home_set = true
	if pose == "cower":
		if cover_to != Vector3.ZERO:
			if _crawl != null and _crawl.is_valid():
				_crawl.kill()
			_crawl = create_tween()
			_crawl.tween_property(self, "position", cover_to, 1.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		return
	if _ap.has_animation("duck"):
		_ap.play("duck", randf_range(0.35, 0.6))
	_anim_shapes()

func _uncover() -> void:
	if not _cover:
		return
	_cover = false
	if _crawl != null and _crawl.is_valid():
		_crawl.kill()
	if _home_set:
		position = _home
		rotation.y = _home_rot
	if _ap != null:
		_ap.play(anim, 0.0)
		_ap.seek(randf() * _ap.current_animation_length, true)
	_anim_shapes()

func _hip() -> float:
	match pose:
		"seat":
			return 0.48
		"lie":
			return 0.62
		_:
			return 0.4

## Fotoreale Figur laden; false = nicht vorhanden (Kasten-Fallback).
func _build_real() -> bool:
	if variant == "":
		return false
	var key := "%s/%s" % [variant, pose]
	var mesh: Mesh = _meshes.get(key)
	if mesh == null:
		var path := CIV_DIR % variant
		if not ResourceLoader.exists(path):
			return false
		var ps := load(path) as PackedScene
		if ps == null:
			return false
		var root := ps.instantiate()
		var src := root.find_child(pose, true, false) as MeshInstance3D
		if src != null and src.mesh != null:
			mesh = src.mesh.duplicate()
			for i in mesh.get_surface_count():
				var m := mesh.surface_get_material(i) as BaseMaterial3D
				if m != null:
					mesh.surface_set_material(i, _tune(m.duplicate() as BaseMaterial3D))
			_meshes[key] = mesh
		root.free()
		if mesh == null:
			return false
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	_torso = Node3D.new()
	_torso.name = "Pose"
	_body.add_child(_torso)
	_real = MeshInstance3D.new()
	_real.mesh = mesh
	_real.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_real.visibility_range_end = 70.0
	_real.visibility_range_end_margin = 6.0
	_real.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_torso.add_child(_real)
	var hy := _hip()
	match pose:
		"seat":
			# Modell schaut in Blender nach -Y -> glTF +Z; Reisender schaut nach -Z
			_real.rotation.y = PI
			_base = Vector3(0, clampf(float(SEAT_DROP.get(variant, 0.45)), 0.43, 0.47), 0.05)
		"cower":
			# Gesicht zum Gang (nicht zur Wand): Nur die Optik dreht, die Kollisionsformen bleiben.
			# Etwas von der Wand weg, damit der gekruemmte Ruecken nicht in die Verkleidung ragt.
			_real.rotation.y = 0.0
			_base = Vector3(0, 0.0, 0.12)
		"lie":
			# stehend gebacken (Ruecken bei z=0, vorn +Z, Kopf +Y) -> Rueckenlage, Kopf bei -x
			_real.basis = Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
			_base = Vector3(0.0, 0.56, 0.0)
			# Decke ueber Becken und angezogenen Knien, aus der Koerperform abgeleitet
			var bl := MeshInstance3D.new()
			bl.mesh = _blanket(mesh, _real.basis)
			bl.material_override = _m(Color(0.6, 0.58, 0.53), 0.95)
			(bl.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			bl.position = _base
			bl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(bl)
			_shape(Vector3(-0.1, hy + 0.05, 0), Vector3(1.6, 0.3, 0.45))
	_torso.position = _base
	match pose:
		"seat":
			_shape(Vector3(0, 0.3, -0.25), Vector3(0.4, 0.6, 0.5))
		"cower":
			_shape(Vector3(0, 0.22, 0.08), Vector3(0.4, 0.44, 0.6))
	if pose != "lie":
		_shape(Vector3(0, hy + 0.31, 0.02), Vector3(0.46, 0.6, 0.3))
		_shape(Vector3(0, hy + 0.78, 0.0), Vector3(0.24, 0.28, 0.25))
	return true

static var _blankets: Dictionary = {}

## Decke als Hoehenfeld ueber dem liegenden Koerper (x: Huefte..Fuesse, z: Bettbreite).
static func _blanket(body: Mesh, b: Basis) -> Mesh:
	if _blankets.has(body):
		return _blankets[body]
	const NX := 26
	const NZ := 14
	const X0 := -0.38
	# Fussende: Matratze endet bei x = +0,75 (Bett 1,5 m, Gangwand dahinter) - weiter hinaus ragte die
	# Decke als schwebendes Laken durch die Abteilwand in den Gang.
	const X1 := 0.74
	const ZW := 0.34
	var h := []
	for i in NX:
		var row := PackedFloat32Array()
		row.resize(NZ)
		row.fill(0.0)
		h.append(row)
	for si in body.get_surface_count():
		var arr := body.surface_get_arrays(si)
		for v: Vector3 in arr[Mesh.ARRAY_VERTEX]:
			var p := b * v
			if p.x < X0 or p.x > X1 or absf(p.z) > ZW:
				continue
			var i := clampi(int((p.x - X0) / (X1 - X0) * (NX - 1) + 0.5), 0, NX - 1)
			var j := clampi(int((p.z + ZW) / (2.0 * ZW) * (NZ - 1) + 0.5), 0, NZ - 1)
			h[i][j] = maxf(h[i][j], p.y)
	var raw := h.duplicate(true)
	# Stoff faellt weich: Maximum-Nachbarschaft, dann glaetten; Raender aufs Laken
	for _pass in 3:
		var n := []
		for i in NX:
			var row := PackedFloat32Array()
			row.resize(NZ)
			for j in NZ:
				var mx := 0.0
				var sum := 0.0
				var c := 0
				for di in range(-1, 2):
					for dj in range(-1, 2):
						var ii := clampi(i + di, 0, NX - 1)
						var jj := clampi(j + dj, 0, NZ - 1)
						mx = maxf(mx, h[ii][jj])
						sum += h[ii][jj]
						c += 1
				row[j] = lerpf(mx, sum / c, 0.5) if _pass < 2 else sum / c
			n.append(row)
		h = n
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pt := func(i: int, j: int) -> Vector3:
		var edge := 1.0 if (j == 0 or j == NZ - 1) else 0.0
		var y: float = maxf(h[i][j], raw[i][j]) + 0.03
		if edge > 0.0:
			y = 0.0
		return Vector3(lerpf(X0, X1, float(i) / (NX - 1)), y, lerpf(-ZW, ZW, float(j) / (NZ - 1)))
	for i in NX - 1:
		for j in NZ - 1:
			var a: Vector3 = pt.call(i, j)
			var c1: Vector3 = pt.call(i + 1, j)
			var d: Vector3 = pt.call(i + 1, j + 1)
			var e: Vector3 = pt.call(i, j + 1)
			for q: Vector3 in [a, c1, d, a, d, e]:
				st.set_uv(Vector2(q.x, q.z))
				st.add_vertex(q)
	# Umschlag am Kopfende und eingeschlagenes Fussende (senkrechte Kante bis aufs Laken)
	for i: int in [0, NX - 1]:
		for j in NZ - 1:
			var a: Vector3 = pt.call(i, j)
			var e: Vector3 = pt.call(i, j + 1)
			var a0 := Vector3(a.x, 0.0, a.z)
			var e0 := Vector3(e.x, 0.0, e.z)
			var tri := [a0, a, e, a0, e, e0] if i == 0 else [a0, e, a, a0, e0, e]
			for q: Vector3 in tri:
				st.set_uv(Vector2(q.z, q.y))
				st.add_vertex(q)
	st.generate_normals()
	var m := st.commit()
	_blankets[body] = m
	return m

static func _tune(m: BaseMaterial3D) -> BaseMaterial3D:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var n := m.resource_name.to_lower()
	if n.begins_with("skin"):
		m.roughness = 0.58
		m.metallic_specular = 0.35
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.35
		m.subsurf_scatter_skin_mode = true
	elif n.begins_with("eye"):
		m.roughness = 0.08
		m.metallic_specular = 0.7
	elif n.begins_with("brow") or n.begins_with("lash") or n.begins_with("hair"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.75
		m.metallic_specular = 0.25
	elif n.begins_with("suit"):
		m.roughness = 0.92
		m.metallic_specular = 0.2
	elif n.begins_with("shoes"):
		m.roughness = 0.4
		m.metallic_specular = 0.4
	return m

func _build() -> void:
	if _build_anim():
		return
	if _build_real():
		return
	var cm := _m(coat)
	var lm := _m(legs)
	var sk := _m(skin, 0.7)
	var hm := _m(hair, 0.9)
	var shoe := _m(Color(0.06, 0.05, 0.05), 0.4)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var hy := _hip()
	_torso = Node3D.new()
	_torso.position = Vector3(0, hy, 0)
	_body.add_child(_torso)
	if pose == "lie":
		# liegt auf dem Ruecken, Kopf bei -x, Decke ueber den Beinen
		_body.rotation_degrees = Vector3(0, 0, 0)
		_box(_body, Vector3(0.9, 0.16, 0.42), _m(Color(0.75, 0.72, 0.66), 0.95), Vector3(0.35, hy + 0.02, 0))
		_box(_torso, Vector3(0.55, 0.2, 0.4), cm, Vector3(-0.3, 0.02, 0))
		_box(_torso, Vector3(0.22, 0.19, 0.21), sk, Vector3(-0.7, 0.06, 0))
		_box(_torso, Vector3(0.1, 0.2, 0.22), hm, Vector3(-0.82, 0.06, 0))
		_shape(Vector3(-0.1, hy + 0.05, 0), Vector3(1.6, 0.3, 0.45))
		return
	if pose == "seat":
		for sx: float in [-0.1, 0.1]:
			_box(_body, Vector3(0.15, 0.15, 0.44), lm, Vector3(sx, hy + 0.04, -0.17))
			_box(_body, Vector3(0.13, 0.46, 0.14), lm, Vector3(sx, 0.25, -0.38))
			_box(_body, Vector3(0.12, 0.07, 0.24), shoe, Vector3(sx, 0.035, -0.44))
		_shape(Vector3(0, 0.3, -0.25), Vector3(0.4, 0.6, 0.5))
	else:
		# kauernd: Knie angezogen, Arme ueber dem Kopf
		for sx: float in [-0.11, 0.11]:
			_box(_body, Vector3(0.14, 0.13, 0.46), lm, Vector3(sx, 0.07, 0.12))
			_box(_body, Vector3(0.15, 0.36, 0.16), lm, Vector3(sx, 0.27, -0.06))
		_shape(Vector3(0, 0.22, 0.08), Vector3(0.4, 0.44, 0.6))
	var lean := -8.0 if pose == "seat" else -35.0
	_box(_torso, Vector3(0.44, 0.58, 0.26), cm, Vector3(0, 0.31, 0.02), Vector3(lean, 0, 0))
	if pose == "seat":
		# Haende im Schoss
		for sx: float in [-0.2, 0.2]:
			_box(_torso, Vector3(0.11, 0.42, 0.12), cm, Vector3(sx, 0.3, -0.05), Vector3(-20, 0, 0))
		_box(_torso, Vector3(0.24, 0.08, 0.12), sk, Vector3(0, 0.05, -0.22))
	else:
		for sx: float in [-0.17, 0.17]:
			_box(_torso, Vector3(0.11, 0.42, 0.12), cm, Vector3(sx, 0.72, -0.18), Vector3(-150, 0, sx * -40.0))
	var head_rot := Vector3(10, 0, 0) if pose == "seat" else Vector3(40, 0, 0)
	var head_p := Vector3(0, 0.79, -0.02) if pose == "seat" else Vector3(0, 0.66, -0.25)
	_box(_torso, Vector3(0.19, 0.23, 0.21), sk, head_p, head_rot)
	_box(_torso, Vector3(0.21, 0.09, 0.23), hm, head_p + Vector3(0, 0.11, 0.02), head_rot)
	_shape(Vector3(0, hy + 0.31, 0.02), Vector3(0.46, 0.6, 0.3))
	_shape(Vector3(0, hy + 0.78, 0.0), Vector3(0.24, 0.28, 0.25))

func _exit_tree() -> void:
	# letzte Figur raeumt die statischen Caches (sonst Ressourcen-Leck-Warnung beim Beenden)
	if get_tree().get_nodes_in_group("civilian").size() <= 1:
		_meshes.clear()
		_blankets.clear()
		_scenes.clear()
		_mats.clear()

func _process(delta: float) -> void:
	if _torso == null:
		return
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	# Atmen, bei "cower" deutliches Zittern
	var shake := 1.6 if pose == "cower" else 0.35
	if _ap != null:
		# Atmen/Blick kommen aus der Animation; ferne Figuren pausieren, Schatten nur aus der Naehe
		_shadow_t -= delta
		if _shadow_t <= 0.0:
			_shadow_t = 0.4 + randf() * 0.2
			var cam := get_viewport().get_camera_3d()
			var d := cam.global_position.distance_to(global_position) if cam != null else 0.0
			_real.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if d < SHADOW_DIST else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_ap.active = d < 50.0
		if pose == "cower":
			_torso.rotation_degrees.z = sin(_t * 15.0 + _phase) * 0.5
		return
	if _real != null:
		_torso.position.y = _base.y + sin(_t * 2.4 + _phase) * 0.004
		if pose != "lie":
			_torso.rotation_degrees.z = sin(_t * 15.0 + _phase) * shake * 0.6
		# Schatten nur aus der Naehe
		_shadow_t -= delta
		if _shadow_t <= 0.0:
			_shadow_t = 0.4 + randf() * 0.2
			var cam := get_viewport().get_camera_3d()
			var near := cam != null and cam.global_position.distance_to(global_position) < SHADOW_DIST
			_real.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	_torso.position.y = _hip() + sin(_t * 2.4 + _phase) * 0.005
	_torso.rotation_degrees.z = sin(_t * 15.0 + _phase) * shake

## Stichpunkte fuer die Schusslinien-Pruefung (Bot).
func clearance_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if _ap != null:
		# lokale Punkte entlang des tatsaechlichen Koerpers (Blick -Z bzw. beim Kauernden +Z)
		var lp: Array[Vector3] = []
		if pose == "cower":
			lp = [Vector3(0, 0.78, 0.2), Vector3(0, 0.5, 0.15), Vector3(0, 0.22, 0.12)]
		elif _cover:
			lp = [Vector3(0, 0.68, -0.25), Vector3(0, 0.55, -0.12), Vector3(0, 0.32, -0.25)]
		else:
			var f := -0.18 if anim == "seat_table" else 0.0
			lp = [Vector3(0, 1.26, f), Vector3(0, 0.98, f * 0.6), Vector3(0, 0.66, 0), Vector3(0, 0.3, -0.2)]
		for v in lp:
			out.append(to_global(v))
		return out
	if pose == "lie":
		for x: float in [-0.7, -0.2, 0.3]:
			out.append(to_global(Vector3(x, _hip(), 0)))
		return out
	var hy := _hip()
	for y: float in [hy + 0.78, hy + 0.45, hy + 0.15, 0.3]:
		out.append(to_global(Vector3(0, y, 0)))
	return out

func is_alive() -> bool:
	return true

func take_damage(_amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	VFX.spawn_blood(hit_position, hit_normal)
	if _cool > 0.0:
		return
	_cool = 0.5
	hits += 1
	if level != null and is_instance_valid(level) and level.has_method("on_civilian_hit"):
		level.on_civilian_hit(self)

func reset() -> void:
	hits = 0
	_cool = 0.0
	_uncover()
