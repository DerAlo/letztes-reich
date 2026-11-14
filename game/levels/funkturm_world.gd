extends RefCounted
## Level 10 "Stimme der Ordnung" (funkturm): statische Geometrie.
## Turm im Ursprung, Messegelaende auf +Z. Betonkern (Innentreppe, 12 Laeufe bis zur Plattform auf 18 m),
## darueber Stahlgitter mit Aussenwendel (12 Laeufe bis 60 m), oben Sendesaal mit Terrasse, Antennenmast
## und Fassadenlift an der Ostseite (+X). Alles Begehbare liegt unter lv.world (Navmesh), der Lift nicht.

const Geo = preload("res://game/levels/level_geo.gd")
const Props = preload("res://game/levels/level_props.gd")
const City = preload("res://game/levels/funkturm_city.gd")
const FacadeKit = preload("res://game/levels/facade_kit.gd")
const FT_TEX := "res://assets/environment/funkturm/textures/"
const VEH_TEX := "res://assets/vehicles/textures/"

const CORE := 5.3          # Kern aussen
const CORE_IN := 5.0       # Kern innen
const SHAFT := 2.0         # Aufzugsschacht (massiv)
const DECK1 := 18.0        # Plattform ueber dem Kern
const TOP := 60.0          # Sendeplattform
const IN_C := 3.5          # Mittellinie Innentreppe
const IN_STEP := 1.5
const EX_C := 6.65         # Mittellinie Aussenwendel
const EX_IN := 5.4
const EX_OUT := 7.9
const EX_STEP := 3.5
const TOP_HALF := 11.0
const LIFT_X := 12.25
const LIFT_HALF := 1.25
const TRUCK_POS := Vector3(26.0, 0.0, 30.0)
const CONSOLE := Vector3(0.0, 60.0, -5.0)
const HOLD_SPOT := Vector3(0.0, 60.0, -3.4)
const PZF_POS := Vector3(-6.0, 60.0, -1.0)
const HELI_SPOT := Vector3(-8.6, 60.0, 8.8)

const _SIGNS: Array = [Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1), Vector2(-1, 1)]

static func corner_in(k: int) -> Vector3:
	var s: Vector2 = _SIGNS[k % 4]
	return Vector3(s.x * IN_C, IN_STEP * k, s.y * IN_C)

static func corner_ex(k: int) -> Vector3:
	var s: Vector2 = _SIGNS[k % 4]
	return Vector3(s.x * EX_C, DECK1 + EX_STEP * k, s.y * EX_C)

## Komplette Bot-Route vom Messe-Eingang bis ans Sendepult.
static func route_messe() -> Array:
	return [Vector3(0, 0, 104), Vector3(-3, 0, 92), Vector3(-2, 0, 78), Vector3(3, 0, 64), Vector3(4, 0, 50),
		Vector3(3, 0, 38), Vector3(3.5, 0, 24), Vector3(3.5, 0, 12), Vector3(3.5, 0, 7.5)]

static func route_core() -> Array:
	var r: Array = [Vector3(3.5, 0, 6.2), Vector3(3.5, 0, 3.5)]
	for k in range(1, 13):
		r.append(corner_in(k))
	return r

static func route_spiral() -> Array:
	var r: Array = [Vector3(5.2, DECK1, 5.2), corner_ex(0)]
	for k in range(1, 13):
		r.append(corner_ex(k))
	return r

static func route_top() -> Array:
	return [Vector3(6.65, TOP, 3.6), Vector3(0, TOP, 3.6), Vector3(0, TOP, 1.0), HOLD_SPOT]

# ================================================================== Helfer

static func _body(lv: Node3D, layer: int = 1) -> StaticBody3D:
	var b := Geo.static_body()
	b.collision_layer = layer
	b.set_meta("no_fit", true)
	(lv.get("world") as Node3D).add_child(b)
	return b

static func _shape(b: CollisionObject3D, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.transform = Transform3D(rot, c)
	b.add_child(cs)
	return cs

## Box mit Kollision (b) und Optik (bb, darf null sein).
static func _box(b: CollisionObject3D, bb: Geo.BoxBatch, c: Vector3, s: Vector3, rot: Basis = Basis.IDENTITY) -> void:
	if b != null:
		_shape(b, c, s, rot)
	if bb != null:
		bb.add(c, s, rot)

## Box aus Min/Max-Ecken.
static func _aabb(b: CollisionObject3D, bb: Geo.BoxBatch, lo: Vector3, hi: Vector3) -> void:
	_box(b, bb, (lo + hi) * 0.5, hi - lo)

## Rampe: a/e sind Punkte auf der Mittellinie der Oberseite.
static func _ramp(b: CollisionObject3D, bb: Geo.BoxBatch, a: Vector3, e: Vector3, width: float) -> void:
	var d := e - a
	var z := d.normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x).normalized()
	var basis := Basis(x, y, z)
	var c := (a + e) * 0.5 - y * 0.15
	_box(b, bb, c, Vector3(width, 0.3, d.length() + 0.12), basis)

## Unsichtbare Bewegungssperre (Layer 16): Kugeln/Sicht gehen durch.
static func _block(lv: Node3D, lo: Vector3, hi: Vector3) -> void:
	var b := _body(lv, 16)
	_aabb(b, null, lo, hi)

static func _emit(c: Color, e: float) -> StandardMaterial3D:
	return Geo.flat(c, 0.6, 0.0, c, e)

## PBR-Material (diffuse/normal/arm, triplanar in Weltkoordinaten) aus einem beliebigen Texturordner.
static var _pbr_cache: Dictionary = {}
static func _pbr(dir: String, tint: Color, scale: float, rough_mul: float = 1.0, metallic: float = 0.0, normal_scale: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, metallic, normal_scale]
	if _pbr_cache.has(key):
		return _pbr_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(dir + "/normal.jpg")
	m.normal_scale = normal_scale
	var arm: Texture2D = load(dir + "/arm.jpg")
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = arm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_pbr_cache[key] = m
	return m

static func _add_mesh(parent: Node, bb: Geo.BoxBatch, m: Material, shadows: bool = true) -> MeshInstance3D:
	var mesh := bb.build()
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, m, Vector3.ZERO, shadows)
	parent.add_child(mi)
	return mi

static func _omni(parent: Node, pos: Vector3, col: Color, energy: float, rng_m: float, shadow: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = shadow
	parent.add_child(l)
	return l

# ================================================================== Boden + Messe

static func ground(lv: Node3D) -> void:
	var w: Node3D = lv.get("world")
	var asphalt := Geo.mat("asphalt_02", Color(0.5, 0.5, 0.53), 0.18, 1.0)
	var paving := Geo.mat("concrete_wall_008", Color(0.42, 0.41, 0.4), 0.25, 1.0)
	var dirt := Geo.mat("concrete_wall_008", Color(0.16, 0.15, 0.14), 0.08, 1.0)
	var g := _body(lv)
	_shape(g, Vector3(0, -1.0, 35.0), Vector3(124.0, 2.0, 196.0))
	var far := Geo.box_mesh_node(Vector3(1400.0, 0.2, 1400.0), dirt, Vector3(0, -0.14, 0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lv.add_child(far)
	w.add_child(Geo.box_mesh_node(Vector3(124.0, 0.2, 196.0), asphalt, Vector3(0, -0.1, 35.0)))
	# Plattenweg vom Messeeingang zum Turmfuss
	var pv := Geo.box_mesh_node(Vector3(14.0, 0.04, 100.0), paving, Vector3(0, 0.01, 62.0))
	pv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(pv)
	# Grenzen
	_block(lv, Vector3(-62, 0, -63), Vector3(-60, 14, 133))
	_block(lv, Vector3(60, 0, -63), Vector3(62, 14, 133))
	_block(lv, Vector3(-62, 0, -63), Vector3(62, 14, -61))
	_block(lv, Vector3(-62, 0, 124), Vector3(62, 14, 126))

static func messe(lv: Node3D) -> Dictionary:
	var w: Node3D = lv.get("world")
	var covers: Array = lv.get("covers")
	var rng: RandomNumberGenerator = lv.get("rng")
	var out: Dictionary = {}
	# Messehallen links/rechts (Stahlbeton, lange Fensterbaender)
	# Hallenwaende: Betonfertigteile (Poly Haven concrete_panels) mit durchlaufendem Fensterband (Shader, einzelne
	# Scheiben unterschiedlich hell/dunkel statt einer leuchtenden Flaeche), Lisenen, Attika und Vordach.
	var hall_m := City.hall_mat(Color(0.62, 0.6, 0.57), 6.4, 8.6, 0.31, 0.34)
	var entry_m := City.hall_mat(Color(0.55, 0.54, 0.52), 4.7, 6.3, 0.77, 0.4)
	var fin_m := FacadeKit.facade_mat("concrete", Color(0.58, 0.57, 0.55), {"grime_amount": 0.7, "streaks": 0.6})
	var cap_m := Geo.flat(Color(0.11, 0.11, 0.12), 0.45, 0.6)
	var roof_m := Geo.mat("rusty_metal_02", Color(0.32, 0.3, 0.3), 0.15, 1.0, 0.4)
	var hb := Geo.batch()
	var eb := Geo.batch()
	var fb := Geo.batch()
	var capb := Geo.batch()
	var rb := Geo.batch()
	var hall := _body(lv)
	for sx in [-1.0, 1.0]:
		_aabb(hall, hb, Vector3(minf(sx * 22.0, sx * 46.0), 0, 40.0), Vector3(maxf(sx * 22.0, sx * 46.0), 13.0, 116.0))
		rb.add(Vector3(sx * 34.0, 13.4, 78.0), Vector3(25.0, 0.8, 77.0))
		# Lisenen (vorgesetzte Betonpfeiler) an der Plazaseite und an der Stirnseite zum Turm
		for i in 11:
			fb.add(Vector3(sx * 21.8, 6.5, 42.0 + i * 7.2), Vector3(0.45, 13.0, 0.7))
		for i in 4:
			fb.add(Vector3(sx * (24.0 + i * 7.0), 6.5, 39.8), Vector3(0.7, 13.0, 0.45))
		# Attika: Blechkante rundum ueber der Dachkante
		capb.add(Vector3(sx * 21.9, 13.55, 78.0), Vector3(0.35, 1.1, 76.4))
		capb.add(Vector3(sx * 46.1, 13.55, 78.0), Vector3(0.35, 1.1, 76.4))
		capb.add(Vector3(sx * 34.0, 13.55, 39.9), Vector3(24.5, 1.1, 0.35))
		capb.add(Vector3(sx * 34.0, 13.55, 116.1), Vector3(24.5, 1.1, 0.35))
		# Vordach zur Plaza
		rb.add(Vector3(sx * 20.5, 5.2, 78.0), Vector3(3.2, 0.25, 70.0))
		capb.add(Vector3(sx * 18.92, 5.2, 78.0), Vector3(0.06, 0.4, 70.0))
		for i in 8:
			fb.add(Vector3(sx * 19.2, 2.6, 46.0 + i * 9.5), Vector3(0.35, 5.2, 0.35))
	# Eingangsbau hinten (Spawn), Kopfbau am Turm
	_aabb(hall, eb, Vector3(-22, 0, 118.0), Vector3(22, 9.0, 124.0))
	capb.add(Vector3(0, 9.45, 117.9), Vector3(44.4, 0.9, 0.3))
	for i in 7:
		fb.add(Vector3(-18.0 + i * 6.0, 4.5, 117.8), Vector3(0.6, 9.0, 0.4))
	_add_mesh(w, hb, hall_m)
	_add_mesh(w, eb, entry_m)
	_add_mesh(w, fb, fin_m)
	_add_mesh(w, capb, cap_m)
	_add_mesh(w, rb, roof_m)
	# Fahnenmasten der Ordnungsfront (stilisierte Flaggen: Grau mit Querbalken, keine realen Symbole)
	var pole_m := Geo.flat(Color(0.5, 0.5, 0.52), 0.4, 0.8)
	var flag_m := Geo.flat(Color(0.22, 0.24, 0.27), 0.9)
	var bar_m := Geo.flat(Color(0.75, 0.62, 0.2), 0.7)
	for i in 6:
		var z := 52.0 + i * 11.0
		for sx in [-1.0, 1.0]:
			w.add_child(Geo.cylinder_node(0.07, 9.0, pole_m, Vector3(sx * 15.5, 4.5, z)))
			w.add_child(Geo.box_mesh_node(Vector3(0.04, 2.6, 1.6), flag_m, Vector3(sx * 15.5, 7.6, z + 0.82)))
			w.add_child(Geo.box_mesh_node(Vector3(0.05, 0.35, 1.6), bar_m, Vector3(sx * 15.5, 7.6, z + 0.82)))
	# Deckung auf der Plaza: Sandsackstellungen, Lkw, Jersey-Barrieren
	Props.sandbags(w, Vector3(-4.0, 0, 86.0), 0.0, 4.0, rng, covers)
	Props.sandbags(w, Vector3(6.0, 0, 80.0), 10.0, 3.5, rng, covers)
	Props.sandbags(w, Vector3(-6.0, 0, 70.0), -8.0, 4.0, rng, covers)
	Props.sandbags(w, Vector3(8.0, 0, 60.0), 0.0, 4.0, rng, covers)
	Props.sandbags(w, Vector3(-3.0, 0, 30.0), 0.0, 5.0, rng, covers)
	Props.sandbags(w, Vector3(9.0, 0, 22.0), 90.0, 4.0, rng, covers)
	Props.vehicle(w, Vector3(-10.0, 0, 95.0), 15.0, "truck", Color(0.2, 0.23, 0.22), false, false, covers)
	Props.vehicle(w, Vector3(11.0, 0, 70.0), -170.0, "truck", Color(0.2, 0.23, 0.22), false, false, covers)
	Props.vehicle(w, Vector3(-11.0, 0, 44.0), 80.0, "van", Color(0.15, 0.16, 0.18), false, false, covers)
	Props.vehicle(w, Vector3(-9.0, 0, 18.0), 100.0, "truck", Color(0.2, 0.23, 0.22), true, false, covers)
	for p in [Vector3(-1.0, 0, 98.0), Vector3(3.0, 0, 90.0), Vector3(0.0, 0, 74.0), Vector3(-8.0, 0, 56.0), Vector3(1.0, 0, 46.0), Vector3(7.0, 0, 34.0), Vector3(-7.0, 0, 26.0)]:
		Props.jersey(w, p, rng.randf_range(-20.0, 20.0), covers)
	for p in [Vector3(-14.0, 0, 34.0), Vector3(15.0, 0, 40.0), Vector3(-15.0, 0, 10.0)]:
		Props.hedgehog(w, p, rng.randf_range(0.0, 90.0), covers)
	# Lampen am Plattenweg
	for i in 5:
		var z := 100.0 - i * 18.0
		Props.lamp(w, Vector3(-8.0, 0, z), 90.0, i % 2 == 0, 0.0, true)
		Props.lamp(w, Vector3(8.0, 0, z - 9.0), -90.0, i != 3, 0.0, true)
	# Suchscheinwerfer-Tuerme (drehen sich, siehe funkturm.gd)
	var spots: Array = []
	var tower_m := _pbr(VEH_TEX + "rusty_painted_metal", Color(0.4, 0.41, 0.42), 0.6, 1.0, 0.4)
	for p in [Vector3(-16.0, 0, 64.0), Vector3(16.0, 0, 88.0), Vector3(-15.0, 0, 22.0), Vector3(15.0, 0, 16.0)]:
		var tb := Geo.batch()
		var tp: Vector3 = p
		for c in [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)]:
			tb.add(tp + Vector3(c.x, 3.5, c.y), Vector3(0.18, 7.0, 0.18))
		tb.add(tp + Vector3(0, 7.05, 0), Vector3(2.2, 0.15, 2.2))
		var tbody := _body(lv)
		_shape(tbody, tp + Vector3(0, 3.5, 0), Vector3(1.8, 7.0, 1.8))
		_add_mesh(w, tb, tower_m)
		var pivot := Node3D.new()
		pivot.position = tp + Vector3(0, 7.7, 0)
		lv.add_child(pivot)
		var head := Geo.cylinder_node(0.45, 0.7, tower_m, Vector3(0, 0, -0.1), Vector3(90, 0, 0))
		pivot.add_child(head)
		var lens := Geo.cylinder_node(0.4, 0.04, _emit(Color(0.9, 0.95, 1.0), 3.0), Vector3(0, 0, -0.46), Vector3(90, 0, 0))
		pivot.add_child(lens)
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.9, 0.94, 1.0)
		sl.light_energy = 14.0
		sl.spot_range = 70.0
		sl.spot_angle = 8.0
		sl.spot_attenuation = 0.7
		sl.light_volumetric_fog_energy = 1.6
		sl.shadow_enabled = false
		sl.position = Vector3(0, 0, -0.5)
		pivot.add_child(sl)
		pivot.rotation_degrees = Vector3(-22.0, rng.randf_range(0, 360), 0)
		spots.append(pivot)
	out["spots"] = spots
	# Lenas Lkw (Exfil) an der Ostseite
	var truck := Props.vehicle(w, TRUCK_POS + Vector3(2.5, 0, 0), 180.0, "truck", Color(0.25, 0.27, 0.22), false, false, covers)
	out["truck"] = truck
	_omni(lv, TRUCK_POS + Vector3(2.5, 1.2, -3.0), Color(1.0, 0.8, 0.5), 1.4, 7.0)
	return out

# ================================================================== Turm

static func tower(lv: Node3D) -> Dictionary:
	var w: Node3D = lv.get("world")
	var out: Dictionary = {}
	# Sichtbeton mit Schmutzfahnen und Russ (Fassaden-Shader), verzinkter/lackierter Stahl mit Rostfahnen,
	# rostige Gitterroste (Poly Haven metal_grate_rusty), Gelaender und Mast in verwittertem Signalrot.
	var concrete := FacadeKit.facade_mat("concrete_old", Color(0.6, 0.59, 0.57),
		{"grime_amount": 0.85, "streaks": 0.8, "soot": 0.25, "wetness": 0.25})
	var steel := _pbr(VEH_TEX + "rusty_painted_metal", Color(0.78, 0.78, 0.8), 0.5, 1.0, 0.35, 1.2)
	var grate := _pbr(FT_TEX + "metal_grate_rusty", Color(0.75, 0.72, 0.7), 0.7, 1.0, 0.5, 1.4)
	var red_steel := _pbr(VEH_TEX + "rusty_painted_metal", Color(0.78, 0.26, 0.2), 0.8, 0.9, 0.3, 1.0)
	var cb := Geo.batch()       # Beton
	# Treppenhaus (Kern, Podeste, Laeufe): ruhiger Sichtbeton ohne Schmutzfahnen (Poly Haven concrete_wall_008,
	# CC0). Die Fahnen des Fassaden-Shaders wirkten unter dem Notlicht wie senkrechte Holzbretter.
	var ib := Geo.batch()
	var stair_m := Geo.mat("concrete_wall_008", Color(0.6, 0.59, 0.57), 0.22, 1.0)
	var sb := Geo.batch()       # Stahlgitter
	var gb := Geo.batch()       # Gitterroste
	var rail := Geo.batch()     # Gelaender (rot)
	var core := _body(lv)
	# ---------------------------------------------------------- Kern
	var h := DECK1 - 0.3
	_aabb(core, ib, Vector3(-CORE, 0, -CORE), Vector3(CORE, h, -CORE_IN))          # -Z
	_aabb(core, ib, Vector3(-CORE, 0, -CORE_IN), Vector3(-CORE_IN, h, CORE_IN))    # -X
	_aabb(core, ib, Vector3(CORE_IN, 0, -CORE_IN), Vector3(CORE, h, CORE_IN))      # +X
	_aabb(core, ib, Vector3(-CORE, 0, CORE_IN), Vector3(2.4, h, CORE))             # +Z links der Tuer
	_aabb(core, ib, Vector3(4.6, 0, CORE_IN), Vector3(CORE, h, CORE))              # +Z rechts
	_aabb(core, ib, Vector3(2.4, 2.4, CORE_IN), Vector3(4.6, h, CORE))             # Sturz
	_aabb(core, ib, Vector3(-SHAFT, 0, -SHAFT), Vector3(SHAFT, h, SHAFT))          # Aufzugsschacht
	# Tuerrahmen + Schild "Aufzug ausser Betrieb"
	sb.add(Vector3(2.35, 1.2, CORE + 0.05), Vector3(0.12, 2.4, 0.12))
	sb.add(Vector3(4.65, 1.2, CORE + 0.05), Vector3(0.12, 2.4, 0.12))
	sb.add(Vector3(3.5, 2.45, CORE + 0.05), Vector3(2.4, 0.12, 0.12))
	var sign := Label3D.new()
	sign.text = "AUFZUG AUSSER BETRIEB\nTREPPE BENUTZEN"
	sign.font_size = 36
	sign.pixel_size = 0.004
	sign.modulate = Color(0.95, 0.85, 0.6)
	sign.position = Vector3(1.0, 1.6, SHAFT + 0.02)
	lv.add_child(sign)
	# Innentreppe: Podeste + Laeufe
	for k in range(1, 12):
		var c := corner_in(k)
		_box(core, ib, c + Vector3(0, -0.15, 0), Vector3(3.0, 0.3, 3.0))
	for k in range(0, 12):
		var c0 := corner_in(k)
		var c1 := corner_in(k + 1)
		var dir := Vector3(c1.x - c0.x, 0, c1.z - c0.z).normalized()
		var a := Vector3(c0.x, c0.y, c0.z) + dir * 1.5
		var e := Vector3(c1.x, c1.y, c1.z) - dir * 1.5
		_ramp(core, ib, a, e, 3.0)
		# Trittkanten (nur Optik)
		for s in 6:
			var t := (s + 0.5) / 6.0
			var p := a.lerp(e, t)
			rail.add(p + Vector3(0, 0.02, 0), Vector3(3.0 if absf(dir.z) > 0.5 else 0.06, 0.04, 0.06 if absf(dir.z) > 0.5 else 3.0))
	# Notbeleuchtung im Treppenhaus: kuehles, schwaches Notlicht + neutrales Grundlicht je Podest
	for k in [1, 4, 7, 10]:
		var c := corner_in(k)
		_omni(lv, c + Vector3(0, 2.2, 0), Color(0.78, 0.86, 1.0), 0.5, 6.5)
		gb.add(c + Vector3(signf(c.x) * 1.4, 2.2, 0), Vector3(0.1, 0.12, 0.3))
	for k in range(1, 12):
		_omni(lv, corner_in(k) + Vector3(0, 1.6, 0), Color(0.95, 0.93, 0.88), 0.3, 5.0)
	# ---------------------------------------------------------- Plattform 18 m (mit Treppenaustritt)
	var deck := _body(lv)
	var y0 := DECK1 - 0.3
	_aabb(deck, cb, Vector3(-EX_OUT, y0, -EX_OUT), Vector3(-5.0, DECK1, EX_OUT))   # A
	_aabb(deck, cb, Vector3(2.0, y0, -EX_OUT), Vector3(EX_OUT, DECK1, EX_OUT))     # B
	_aabb(deck, cb, Vector3(-5.0, y0, -EX_OUT), Vector3(2.0, DECK1, -2.0))         # C
	_aabb(deck, cb, Vector3(-2.0, y0, -2.0), Vector3(2.0, DECK1, 2.0))             # D
	_aabb(deck, cb, Vector3(-5.0, y0, 5.0), Vector3(2.0, DECK1, EX_OUT))           # E
	# Gelaender um den Treppenaustritt (Bewegungssperre + Optik)
	for seg in [[Vector3(-5.0, 0, -2.0), Vector3(-5.0, 0, 5.0)], [Vector3(-5.0, 0, -2.0), Vector3(-2.0, 0, -2.0)],
			[Vector3(-2.0, 0, -2.0), Vector3(-2.0, 0, 2.0)], [Vector3(-2.0, 0, 2.0), Vector3(2.0, 0, 2.0)], [Vector3(-5.0, 0, 5.0), Vector3(2.0, 0, 5.0)]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var lo := Vector3(minf(p0.x, p1.x) - 0.05, DECK1, minf(p0.z, p1.z) - 0.05)
		var hi := Vector3(maxf(p0.x, p1.x) + 0.05, DECK1 + 1.3, maxf(p0.z, p1.z) + 0.05)
		_block(lv, lo, hi)
		rail.add((p0 + p1) * 0.5 + Vector3(0, DECK1 + 1.05, 0), Vector3(absf(p1.x - p0.x) + 0.06, 0.06, absf(p1.z - p0.z) + 0.06))
		rail.add((p0 + p1) * 0.5 + Vector3(0, DECK1 + 0.55, 0), Vector3(absf(p1.x - p0.x) + 0.04, 0.04, absf(p1.z - p0.z) + 0.04))
	# ---------------------------------------------------------- Stahlgitter + Aussenwendel
	var spiral := _body(lv)
	for k in range(1, 12):
		var c := corner_ex(k)
		_box(spiral, gb, c + Vector3(0, -0.15, 0), Vector3(2.5, 0.3, 2.5))
	for k in range(0, 12):
		var c0 := corner_ex(k)
		var c1 := corner_ex(k + 1)
		var dir := Vector3(c1.x - c0.x, 0, c1.z - c0.z).normalized()
		var a := c0 + dir * 1.25
		var e := c1 - dir * 1.25
		_ramp(spiral, gb, a, e, 2.5)
	# Beine, Ringtraeger und Diagonalen (aussen bei +-8.15, innen bei +-5.15; keine Traeger quer ueber den Steg)
	for r in [8.15, 5.15]:
		for s in _SIGNS:
			var sv: Vector2 = s
			sb.add(Vector3(sv.x * r, (DECK1 + TOP) * 0.5, sv.y * r), Vector3(0.5, TOP - DECK1, 0.5))
	for i in 13:
		var y := DECK1 + i * EX_STEP
		for r in [8.15, 5.15]:
			sb.add(Vector3(0, y, r), Vector3(2.0 * r, 0.22, 0.22))
			sb.add(Vector3(0, y, -r), Vector3(2.0 * r, 0.22, 0.22))
			sb.add(Vector3(r, y, 0), Vector3(0.22, 0.22, 2.0 * r))
			sb.add(Vector3(-r, y, 0), Vector3(0.22, 0.22, 2.0 * r))
	var span := 16.3
	var diag := Vector2(span, EX_STEP).length()
	var ang := atan2(EX_STEP, span)
	for i in 12:
		var yc := DECK1 + (i + 0.5) * EX_STEP
		for f in 4:
			var yaw := f * PI * 0.5
			var nrm := Vector3(sin(yaw), 0, cos(yaw))
			var center := nrm * 8.15 + Vector3(0, yc, 0)
			for sgn in [-1.0, 1.0]:
				var basis := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), ang * sgn)
				sb.add(center, Vector3(diag, 0.14, 0.14), basis)
	# Handlauf aussen an den Laeufen
	for k in range(0, 12):
		var c0 := corner_ex(k)
		var c1 := corner_ex(k + 1)
		var a := c0 + Vector3(c0.x, 0, c0.z).normalized() * 0.0
		var dirv := (c1 - c0)
		var out_n := Vector3(signf(c0.x + c1.x), 0, signf(c0.z + c1.z))
		if absf(dirv.x) > 0.1:
			out_n = Vector3(0, 0, signf(c0.z))
		else:
			out_n = Vector3(signf(c0.x), 0, 0)
		var p0 := a + out_n * 1.2 + Vector3(0, 1.0, 0)
		var p1 := c1 + out_n * 1.2 + Vector3(0, 1.0, 0)
		var d := p1 - p0
		var z := d.normalized()
		var x := Vector3.UP.cross(z).normalized()
		var y := z.cross(x).normalized()
		rail.add((p0 + p1) * 0.5, Vector3(0.06, 0.06, d.length()), Basis(x, y, z))
	# Bewegungssperren: aussen +-8.0 (18..59.6), innen +-5.35 (20.2..59.6)
	var yt := TOP - 0.4
	_block(lv, Vector3(-8.1, DECK1, -8.1), Vector3(8.1, yt, -8.0))
	_block(lv, Vector3(-8.1, DECK1, 8.0), Vector3(8.1, yt, 8.1))
	_block(lv, Vector3(-8.1, DECK1, -8.0), Vector3(-8.0, yt, 8.0))
	_block(lv, Vector3(8.0, DECK1, -8.0), Vector3(8.1, yt, 8.0))
	var yi := DECK1 + 2.2
	_block(lv, Vector3(-5.4, yi, -5.4), Vector3(5.4, yt, -5.3))
	_block(lv, Vector3(-5.4, yi, 5.3), Vector3(5.4, yt, 5.4))
	_block(lv, Vector3(-5.4, yi, -5.3), Vector3(-5.3, yt, 5.3))
	_block(lv, Vector3(5.3, yi, -5.3), Vector3(5.4, yt, 5.3))
	# Positionslampen am Gitter
	for i in [3, 6, 9]:
		var c := corner_ex(i)
		_omni(lv, c + Vector3(0, 2.4, 0), Color(1.0, 0.7, 0.4), 0.9, 6.0)
	# ---------------------------------------------------------- Sendeplattform 60 m
	var top := _body(lv)
	var t0 := TOP - 0.3
	var hT := TOP_HALF
	_aabb(top, cb, Vector3(-hT, t0, -hT), Vector3(hT, TOP, EX_IN))
	_aabb(top, cb, Vector3(-hT, t0, EX_OUT), Vector3(hT, TOP, hT))
	_aabb(top, cb, Vector3(-hT, t0, EX_IN), Vector3(-EX_IN, TOP, EX_OUT))
	_aabb(top, cb, Vector3(EX_IN, t0, EX_IN), Vector3(hT, TOP, EX_OUT))
	# Unterzug (Optik) – nur innerhalb des inneren Gitterrings: frueher 16.6 m breit, er hing dann 1.8 m ueber
	# dem letzten Wendellauf und sah aus wie eine Betonwand vor dem Treppenaustritt.
	cb.add(Vector3(0, TOP - 1.0, 0), Vector3(10.2, 1.4, 10.2))
	# Lochraender
	_block(lv, Vector3(-EX_IN, TOP, EX_IN - 0.08), Vector3(EX_IN, TOP + 1.3, EX_IN))
	_block(lv, Vector3(-EX_IN, TOP, EX_OUT), Vector3(EX_IN, TOP + 1.3, EX_OUT + 0.08))
	_block(lv, Vector3(-EX_IN - 0.08, TOP, EX_IN), Vector3(-EX_IN, TOP + 1.3, EX_OUT))
	rail.add(Vector3(0, TOP + 1.05, EX_IN - 0.04), Vector3(2.0 * EX_IN, 0.06, 0.06))
	rail.add(Vector3(0, TOP + 1.05, EX_OUT + 0.04), Vector3(2.0 * EX_IN, 0.06, 0.06))
	rail.add(Vector3(-EX_IN - 0.04, TOP + 1.05, (EX_IN + EX_OUT) * 0.5), Vector3(0.06, 0.06, EX_OUT - EX_IN))
	# Aussengelaender (Luecke fuer das Lifttor bei x=+11, z -1.25..1.25)
	var rh := TOP + 1.3
	_block(lv, Vector3(-hT - 0.1, TOP, -hT - 0.1), Vector3(hT + 0.1, rh, -hT))
	_block(lv, Vector3(-hT - 0.1, TOP, hT), Vector3(hT + 0.1, rh, hT + 0.1))
	_block(lv, Vector3(-hT - 0.1, TOP, -hT), Vector3(-hT, rh, hT))
	_block(lv, Vector3(hT, TOP, -hT), Vector3(hT + 0.1, rh, -LIFT_HALF))
	_block(lv, Vector3(hT, TOP, LIFT_HALF), Vector3(hT + 0.1, rh, hT))
	for side in 4:
		var yaw := side * PI * 0.5
		var nrm := Vector3(sin(yaw), 0, cos(yaw))
		var tang := Vector3(cos(yaw), 0, -sin(yaw))
		# Ostseite (side 1): Gelaender-Optik mit Luecke fuer das Lifttor, sonst sieht der Zugang zugesperrt aus
		var gap := LIFT_HALF if side == 1 else 0.0
		for hh in [1.05, 0.55]:
			if gap > 0.0:
				var seg_len := hT - gap
				for sgn in [-1.0, 1.0]:
					rail.add(nrm * (hT - 0.05) + tang * (sgn * (gap + seg_len * 0.5)) + Vector3(0, TOP + hh, 0),
						Vector3(0.06, 0.06, 0.06) + tang.abs() * seg_len)
			else:
				rail.add(nrm * (hT - 0.05) + Vector3(0, TOP + hh, 0), (Vector3(0.06, 0.06, 0.06) + tang.abs() * 2.0 * hT))
		for i in 12:
			var tpos := -hT + (i + 0.5) * (2.0 * hT / 12.0)
			if gap > 0.0 and absf(tpos) < gap + 0.1:
				continue
			rail.add(nrm * (hT - 0.05) + tang * tpos + Vector3(0, TOP + 0.55, 0), Vector3(0.06, 1.1, 0.06))
	# Lifttor-Rahmen: zwei gelbe Pfosten + Warnstreifen am Boden markieren den Durchgang zum Fassadenlift
	var gate_frame := Geo.batch()
	for sz in [-LIFT_HALF - 0.06, LIFT_HALF + 0.06]:
		gate_frame.add(Vector3(hT - 0.05, TOP + 1.2, sz), Vector3(0.12, 2.4, 0.12))
	gate_frame.add(Vector3(hT - 0.05, TOP + 2.45, 0), Vector3(0.12, 0.12, 2.0 * LIFT_HALF + 0.24))
	gate_frame.add(Vector3(hT - 0.6, TOP + 0.01, 0), Vector3(1.1, 0.02, 2.0 * LIFT_HALF))
	_add_mesh(lv, gate_frame, Geo.flat(Color(0.85, 0.65, 0.1), 0.6, 0.5), false)
	# Sendesaal: Raum x -8..8, z -9..2; Bruestung 0..1 m, Fensterband 1..2.6 m, Sturz 2.6..4.2 m
	var room := _body(lv)
	var rmat := FacadeKit.facade_mat("concrete", Color(0.66, 0.64, 0.6), {"grime_amount": 0.6, "streaks": 0.5})
	var rbx := Geo.batch()
	var wall_t := 0.25
	var walls: Array = [
		[Vector3(-8.0, 0, -9.0), Vector3(8.0, 0, -9.0 + wall_t)],
		[Vector3(-8.0, 0, -9.0), Vector3(-8.0 + wall_t, 0, 2.0)],
		[Vector3(8.0 - wall_t, 0, -9.0), Vector3(8.0, 0, 2.0)],
	]
	for wl in walls:
		var lo: Vector3 = wl[0]
		var hi: Vector3 = wl[1]
		_aabb(room, rbx, Vector3(lo.x, TOP, lo.z), Vector3(hi.x, TOP + 1.0, hi.z))
		_aabb(room, rbx, Vector3(lo.x, TOP + 2.6, lo.z), Vector3(hi.x, TOP + 4.2, hi.z))
	# Front (+Z) mit Tuer x -1.5..1.5
	_aabb(room, rbx, Vector3(-8.0, TOP, 2.0 - wall_t), Vector3(-1.5, TOP + 1.0, 2.0))
	_aabb(room, rbx, Vector3(1.5, TOP, 2.0 - wall_t), Vector3(8.0, TOP + 1.0, 2.0))
	_aabb(room, rbx, Vector3(-8.0, TOP + 2.6, 2.0 - wall_t), Vector3(8.0, TOP + 4.2, 2.0))
	# Fensterpfosten (nur Optik, schmal)
	for i in 9:
		var x := -8.0 + i * 2.0
		sb.add(Vector3(x, TOP + 1.8, 1.88), Vector3(0.08, 1.6, 0.08))
		sb.add(Vector3(x, TOP + 1.8, -8.88), Vector3(0.08, 1.6, 0.08))
	for i in 6:
		var z := -9.0 + i * 2.2
		sb.add(Vector3(-7.88, TOP + 1.8, z), Vector3(0.08, 1.6, 0.08))
		sb.add(Vector3(7.88, TOP + 1.8, z), Vector3(0.08, 1.6, 0.08))
	# Dach
	_aabb(room, rbx, Vector3(-8.2, TOP + 4.2, -9.2), Vector3(8.2, TOP + 4.45, 2.2))
	# Sendepult + Racks
	var desk_m := Geo.flat(Color(0.2, 0.21, 0.22), 0.5, 0.4)
	var db := Geo.batch()
	_box(room, db, CONSOLE + Vector3(0, 0.5, 0), Vector3(4.2, 1.0, 1.2))
	db.add(CONSOLE + Vector3(0, 1.3, -0.45), Vector3(4.2, 0.7, 0.18), Basis(Vector3.RIGHT, deg_to_rad(-15)))
	for i in 6:
		var x := -6.0 + i * 2.4
		_box(room, db, Vector3(x, TOP + 1.0, -8.3), Vector3(1.2, 2.0, 0.9))
	_add_mesh(w, db, desk_m)
	var scr := Geo.batch()
	for i in 3:
		scr.add(CONSOLE + Vector3(-1.3 + i * 1.3, 1.36, -0.33), Vector3(1.0, 0.5, 0.02), Basis(Vector3.RIGHT, deg_to_rad(-15)))
	var scr_m := _emit(Color(1.0, 0.62, 0.18), 2.2)
	_add_mesh(w, scr, scr_m, false)
	out["screen_mat"] = scr_m
	var led := Geo.batch()
	for i in 6:
		var x := -6.0 + i * 2.4
		for j in 7:
			led.add(Vector3(x - 0.4 + (j % 4) * 0.25, TOP + 0.5 + j * 0.2, -7.84), Vector3(0.05, 0.03, 0.02))
	_add_mesh(w, led, _emit(Color(0.3, 1.0, 0.4), 3.0), false)
	_omni(lv, CONSOLE + Vector3(0, 2.0, 1.0), Color(1.0, 0.7, 0.4), 1.6, 9.0, true)
	_omni(lv, Vector3(-5.0, TOP + 3.6, -4.0), Color(0.75, 0.85, 1.0), 0.6, 8.0)
	_omni(lv, Vector3(5.0, TOP + 3.6, -4.0), Color(0.75, 0.85, 1.0), 0.6, 8.0)
	# Leuchtschild "AUF SENDUNG"
	var onair := Label3D.new()
	onair.text = "AUF SENDUNG"
	onair.font_size = 64
	onair.pixel_size = 0.006
	onair.modulate = Color(1.0, 0.2, 0.15)
	onair.outline_size = 0
	onair.position = Vector3(0, TOP + 2.95, -8.72)
	lv.add_child(onair)
	out["onair"] = onair
	_add_mesh(w, rbx, rmat)
	# Antennenmast
	var mast := Geo.batch()
	mast.add(Vector3(0, TOP + 4.45 + 15.0, -3.5), Vector3(1.1, 30.0, 1.1))
	mast.add(Vector3(0, TOP + 4.45 + 33.0, -3.5), Vector3(0.45, 6.0, 0.45))
	for i in 5:
		var y := TOP + 8.0 + i * 5.5
		mast.add(Vector3(0, y, -3.5), Vector3(3.6 - i * 0.5, 0.15, 0.15))
		mast.add(Vector3(0, y, -3.5), Vector3(0.15, 0.15, 3.6 - i * 0.5))
	_add_mesh(w, mast, red_steel)
	var blink: Array = []
	var red_m := _emit(Color(1.0, 0.08, 0.05), 6.0)
	for y in [TOP + 18.0, TOP + 30.0, TOP + 36.4]:
		var bulb := Geo.box_mesh_node(Vector3(0.3, 0.3, 0.3), red_m, Vector3(0, y, -3.5))
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lv.add_child(bulb)
		var bl := _omni(lv, Vector3(0, y, -3.5), Color(1.0, 0.1, 0.05), 2.0, 14.0)
		blink.append(bulb)
		blink.append(bl)
	out["blink"] = blink
	_add_mesh(w, cb, concrete)
	_add_mesh(w, ib, stair_m)
	_add_mesh(w, sb, steel)
	_add_mesh(w, gb, grate)
	_add_mesh(w, rail, red_steel)
	# Liftschacht an der Ostseite (Optik: zwei Fuehrungsschienen)
	var lr := Geo.batch()
	for z in [-1.45, 1.45]:
		lr.add(Vector3(LIFT_X + 1.4, 30.6, z), Vector3(0.18, 61.2, 0.18))
	for i in 18:
		lr.add(Vector3(LIFT_X + 1.4, 1.0 + i * 3.5, 0), Vector3(0.12, 0.12, 3.0))
	lr.add(Vector3(LIFT_X, 61.4, 0), Vector3(3.2, 0.25, 0.3))
	_add_mesh(lv, lr, steel)
	return out

# ================================================================== Fassadenlift

static func lift(lv: Node3D) -> Dictionary:
	var b := AnimatableBody3D.new()
	b.name = "FacadeLift"
	b.collision_layer = 1
	b.collision_mask = 0
	b.sync_to_physics = true
	b.set_meta("no_fit", true)
	b.position = Vector3(LIFT_X, TOP, 0)
	lv.add_child(b)
	var hl := LIFT_HALF
	var m := Geo.mat("rusty_metal_02", Color(0.55, 0.5, 0.42), 0.4, 1.0, 0.6)
	var cage := Geo.batch()
	_box(b, cage, Vector3(0, -0.1, 0), Vector3(2.5, 0.2, 2.5))
	_box(b, cage, Vector3(hl + 0.05, 1.3, 0), Vector3(0.1, 2.6, 2.5))       # +X
	_box(b, cage, Vector3(0, 1.3, -hl - 0.05), Vector3(2.5, 2.6, 0.1))      # -Z
	cage.add(Vector3(0, 2.6, 0), Vector3(2.6, 0.1, 2.6))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		cage.add(Vector3(c.x * hl, 1.3, c.y * hl), Vector3(0.1, 2.6, 0.1))
	var mi := Geo.mesh_node(cage.build(), m)
	b.add_child(mi)
	# Tore (Gitter, nur Rahmen-Optik)
	var gate_m := Geo.flat(Color(0.75, 0.6, 0.12), 0.6, 0.5)
	var deck_gate := _shape(b, Vector3(-hl - 0.05, 0.75, 0), Vector3(0.1, 1.5, 2.5))
	var exit_gate := _shape(b, Vector3(0, 0.75, hl + 0.05), Vector3(2.5, 1.5, 0.1))
	var dg := Geo.box_mesh_node(Vector3(0.06, 1.5, 2.4), gate_m, Vector3(-hl - 0.05, 0.75, 0))
	var eg := Geo.box_mesh_node(Vector3(2.4, 1.5, 0.06), gate_m, Vector3(0, 0.75, hl + 0.05))
	dg.transparency = 0.55
	eg.transparency = 0.55
	b.add_child(dg)
	b.add_child(eg)
	var lamp := _omni(b, Vector3(0, 2.4, 0), Color(1.0, 0.75, 0.35), 1.2, 5.0)
	var beacon := Geo.box_mesh_node(Vector3(0.25, 0.15, 0.25), _emit(Color(1.0, 0.55, 0.05), 5.0), Vector3(hl, 2.75, hl))
	b.add_child(beacon)
	return {"body": b, "deck_gate": deck_gate, "exit_gate": exit_gate, "deck_gate_mesh": dg, "exit_gate_mesh": eg, "lamp": lamp}

# ================================================================== Horizont: Berlin bei Nacht

static func horizon(lv: Node3D) -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = 24062030
	# Stadt: Altbauzeilen, Plattenbauten und Hochhaeuser mit Fassadentextur und Fensterraster (funkturm_city.gd)
	var city: Dictionary = City.build(lv, 24062030, 340, 105.0, 520.0, Rect2(-66.0, -66.0, 132.0, 206.0))
	# Flugwarnlichter (rot, schwach) auf den hohen Haeusern
	var beacons: PackedVector3Array = city.get("beacons", PackedVector3Array())
	if beacons.size() > 0:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.5, 0.5)
		var bmat := _emit(Color(1.0, 0.1, 0.05), 2.2)
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.material = bmat
		lv.add_child(_multimesh(bm, beacons))
	# Strassenlicht-Ketten (Natriumdampf) zwischen den Haeusern: kleine Leuchtkoerper, keine Bloom-Kloetze
	var lights := PackedVector3Array()
	for i in 40:
		var a := srng.randf() * TAU
		var r0 := srng.randf_range(80.0, 200.0)
		var dirv := Vector3(sin(a), 0, cos(a))
		for j in 14:
			lights.append(dirv * (r0 + j * 18.0) + Vector3(0, 7.5, 0) + Vector3(cos(a), 0, -sin(a)) * srng.randf_range(-2.0, 2.0))
	var qm := BoxMesh.new()
	qm.size = Vector3(0.7, 0.25, 0.7)
	var lm := _emit(Color(1.0, 0.6, 0.26), 2.2)
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.material = lm
	lv.add_child(_multimesh(qm, lights))
	# Rauchsaeulen ueber der Stadt (Brandherde)
	for p in [Vector3(-260, 0, -180), Vector3(310, 0, -60), Vector3(-120, 0, 380), Vector3(400, 0, 260), Vector3(80, 0, -420)]:
		Props.fire(lv, p, 4.0, true, 9.0, 40.0)

static func _multimesh(mesh: Mesh, pts: PackedVector3Array) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = pts.size()
	for i in pts.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pts[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi

static func atmosphere(lv: Node3D) -> void:
	var w: Node3D = lv.get("world")
	# Brand auf der Plaza (umgekippte Tonne / Wrack) und Bodennebel
	Props.fire(w, Vector3(-9.0, 0.3, 18.0), 1.2, true, 2.0, 6.0)
	Props.fire(w, Vector3(13.0, 0.0, 52.0), 0.8, true, 1.5, 5.0)
	for z in [90.0, 55.0, 15.0]:
		Props.fog_volume(lv, Vector3(0, 1.5, z), Vector3(46, 5, 34), 0.014, Color(0.3, 0.31, 0.34))
