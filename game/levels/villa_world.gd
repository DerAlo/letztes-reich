extends RefCounted
## Level 12 "Das Haus am See" (villa): statische Welt der Villa am Traunsee in der Abenddaemmerung
## (18.06.2030, 20:15). Umgebung (HDRI-Himmel, tiefe Sonne ueber dem See im Nordwesten), Hang mit
## Startplatz, Wiese, Grundstuecksmauer, Bootshaus, Garten mit Hecken, Terrasse, Vorplatz mit Brunnen,
## Villa (Halle, Salon, Bibliothek), See, Steg, Wasserflugzeug, Bundesstrasse mit Garde-Transportern,
## Berge, Baeume, Lichter und Levelgrenzen. Alle Funktionen statisch; build() liefert Bezugspunkte.
##
## Koordinaten: y = 0 Boden, -Z = Norden (See). Villa x -12..12, z -32..-14. See noerdlich z < -44
## und westlich x < -32. Hang (Start) im Sueden, Plateau y = 5 bei z 70..102.

const VfxEnv = preload("res://game/vfx/vfx_env.gd")
const Geo = preload("res://game/levels/level_geo.gd")
const Props = preload("res://game/levels/level_props.gd")
const BP = preload("res://game/levels/berlin_props.gd")
const K = preload("res://game/levels/overwatch_world_kit.gd")
const RP = preload("res://game/levels/river_props.gd")
const NP = preload("res://game/levels/night_props.gd")

const HDRI := "res://assets/environment/rail/hdri/industrial_sunset_02_puresky_2k.hdr"
const SUN_AZ := 228.0          ## 180 = aus -Z (Norden); > 180 nach Westen: Sonnenuntergang ueber dem See
const SUN_EL := 3.5

const FLOOR_Y := 0.1           ## Fussboden der Villa
const STOREY := 3.6            ## Erdgeschosshoehe (Decke)
const EAVE := 7.2              ## Traufhoehe
const DOOR_H := 2.5
const WALL_T := 0.35
const WATER_Y := -0.35

# ------------------------------------------------------------------ Umgebung

static func setup_environment(lv: Node3D) -> Dictionary:
	var env := VfxEnv.make_environment(0.006, 1.0)
	if ResourceLoader.exists(HDRI):
		var mat := env.sky.sky_material as PanoramaSkyMaterial
		mat.panorama = load(HDRI)
		mat.energy_multiplier = 0.55
	env.sky_rotation = Vector3(0.0, deg_to_rad(VfxEnv.SKY_YAW_OFFSET_DEG + (SUN_AZ - 200.0)), 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_color = Color(0.42, 0.46, 0.6)
	env.ambient_light_energy = 0.75
	env.tonemap_exposure = 0.9
	# Daemmerung: kuehler Dunst ueber dem Wasser, warme Streuung zur Sonne
	env.fog_light_color = Color(0.5, 0.52, 0.64)
	env.fog_light_energy = 0.7
	env.fog_density = 0.0006
	env.fog_sun_scatter = 0.22
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.35
	env.fog_height = 2.0
	env.fog_height_density = 0.004
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(0.8, 0.82, 0.9)
	env.volumetric_fog_emission = Color(0.012, 0.014, 0.024)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 160.0
	env.volumetric_fog_sky_affect = 0.3
	env.volumetric_fog_ambient_inject = 0.35
	env.glow_intensity = 0.5
	env.glow_bloom = 0.06
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	lv.add_child(we)
	# Tiefe, rotgoldene Sonne knapp ueber den Bergen im Nordwesten
	var sun := VfxEnv.make_sun()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.56, 0.32)
	sun.light_energy = 1.9
	sun.light_volumetric_fog_energy = 1.4
	sun.directional_shadow_max_distance = 160.0
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	lv.add_child(sun)
	# Kuehles Blau aus dem Osten (Daemmerungshimmel)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.5, 0.58, 0.82)
	fill.light_energy = 0.4
	fill.light_indirect_energy = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.5, -0.5, 0.4).normalized(), Vector3.UP), Vector3.ZERO)
	lv.add_child(fill)
	VfxEnv.apply_render_quality(lv.get_viewport())
	return {"sun": sun, "env": env}

## Materialtabelle fuer den Builder.
static func materials() -> Dictionary:
	var m := BP.materials()
	m["grass"] = K.grass()
	m["gravel"] = K.gravel(Color(0.72, 0.68, 0.62))
	m["stone"] = K.stones(Color(0.62, 0.6, 0.57))
	m["quay"] = K.concrete(Color(0.5, 0.5, 0.48))
	m["plaster"] = Geo.flat(Color(0.86, 0.82, 0.72), 0.9)
	m["plaster_dark"] = Geo.flat(Color(0.6, 0.57, 0.5), 0.9)
	m["roof"] = Geo.flat(Color(0.16, 0.15, 0.15), 0.75, 0.1)
	m["timber"] = Geo.flat(Color(0.28, 0.2, 0.14), 0.8)
	m["timber_dark"] = Geo.flat(Color(0.16, 0.12, 0.09), 0.85)
	m["planks"] = Geo.flat(Color(0.36, 0.28, 0.2), 0.85)
	m["parquet"] = Geo.flat(Color(0.32, 0.2, 0.12), 0.45)
	m["rug"] = Geo.flat(Color(0.32, 0.08, 0.07), 0.95)
	m["hedge"] = Geo.flat(Color(0.09, 0.16, 0.07), 0.95)
	m["leaves"] = Geo.flat(Color(0.12, 0.2, 0.08), 0.95)
	m["bark"] = Geo.flat(Color(0.2, 0.15, 0.11), 0.95)
	m["sofa"] = Geo.flat(Color(0.2, 0.22, 0.28), 0.9)
	m["leather"] = Geo.flat(Color(0.22, 0.11, 0.06), 0.55)
	m["books"] = Geo.flat(Color(0.3, 0.14, 0.1), 0.85)
	m["books2"] = Geo.flat(Color(0.12, 0.18, 0.22), 0.85)
	m["books3"] = Geo.flat(Color(0.32, 0.27, 0.15), 0.85)
	m["iron"] = Geo.flat(Color(0.05, 0.05, 0.055), 0.5, 0.7)
	m["brass"] = Geo.flat(Color(0.7, 0.55, 0.25), 0.35, 0.85)
	m["white_paint"] = Geo.flat(Color(0.85, 0.85, 0.83), 0.5)
	m["red_paint"] = Geo.flat(Color(0.55, 0.07, 0.06), 0.45)
	m["mountain"] = Geo.flat(Color(0.2, 0.22, 0.27), 1.0)
	m["mountain_far"] = Geo.flat(Color(0.28, 0.31, 0.38), 1.0)
	m["snow"] = Geo.flat(Color(0.75, 0.77, 0.82), 0.9)
	m["lamp_glow"] = Geo.flat(Color(0.1, 0.08, 0.05), 0.6, 0.0, Color(1.0, 0.72, 0.42), 5.0)
	m["shore_light"] = Geo.flat(Color(0.1, 0.08, 0.05), 0.6, 0.0, Color(1.0, 0.75, 0.45), 9.0)
	m["fire_glow"] = Geo.flat(Color(0.1, 0.03, 0.0), 0.6, 0.0, Color(1.0, 0.45, 0.12), 6.0)
	m["paper"] = Geo.flat(Color(0.82, 0.8, 0.72), 0.9)
	m["folder"] = Geo.flat(Color(0.55, 0.42, 0.18), 0.8)
	return m

# ------------------------------------------------------------------ Aufbau

static func build(lv: Node3D, world: Node3D, mats: Dictionary, covers: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pts: Dictionary = {}
	var bd := BP.Builder.new(mats)
	var body := Geo.static_body()
	body.name = "VillaStatic"
	_terrain(bd, body)
	_estate_walls(bd, body)
	_boathouse(bd, body)
	_garden(bd, body)
	_forecourt(bd, body, world, covers)
	_villa(bd, body)
	_interior(bd, body)
	_jetty(bd, body)
	_road(bd, world, covers)
	bd.build(world)
	world.add_child(body)
	_water(lv)
	_mountains(lv, mats)
	_trees(lv, world, rng)
	_lights(lv, mats, pts)
	_boundaries(lv)
	pts["back_door"] = _back_door(lv, mats)
	var plane := _seaplane(lv, mats)
	pts["plane"] = plane["root"]
	pts["prop"] = plane["prop"]
	pts["akte"] = _akte(lv, mats)
	# Nebelbaenke ueber dem Wasser
	Props.fog_volume(lv, Vector3(-40.0, 0.4, -90.0), Vector3(120.0, 2.0, 60.0), 0.035, Color(0.78, 0.8, 0.88))
	Props.fog_volume(lv, Vector3(-75.0, 0.4, 10.0), Vector3(60.0, 2.0, 140.0), 0.03, Color(0.78, 0.8, 0.88))
	return pts

## Box mit Kollision.
static func _sb(bd: BP.Builder, body: StaticBody3D, key: String, c: Vector3, s: Vector3, yaw_deg: float = 0.0) -> void:
	bd.box(key, c, s, Basis(Vector3.UP, deg_to_rad(yaw_deg)))
	Geo.add_box_shape(body, c, s, Vector3(0, yaw_deg, 0))

## Box aus zwei Ecken, mit Kollision.
static func _mm(bd: BP.Builder, body: StaticBody3D, key: String, a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	_sb(bd, body, key, (lo + hi) * 0.5, hi - lo)

## Nur Optik (zwei Ecken).
static func _vis(bd: BP.Builder, key: String, a: Vector3, b: Vector3) -> void:
	var lo := Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z))
	var hi := Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z))
	bd.box(key, (lo + hi) * 0.5, hi - lo)

## Wand entlang X bei z, von xa bis xb, mit Tueroeffnungen gaps = [[x0, x1], ...] (Sturz ab DOOR_H).
static func _wall_x(bd: BP.Builder, body: StaticBody3D, key: String, z: float, xa: float, xb: float, y0: float, h: float, gaps: Array, t: float = WALL_T) -> void:
	var x := xa
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for g: Array in sorted_gaps:
		if float(g[0]) > x:
			_mm(bd, body, key, Vector3(x, y0, z - t * 0.5), Vector3(float(g[0]), y0 + h, z + t * 0.5))
		_mm(bd, body, key, Vector3(float(g[0]), y0 + DOOR_H, z - t * 0.5), Vector3(float(g[1]), y0 + h, z + t * 0.5))
		x = float(g[1])
	if xb > x:
		_mm(bd, body, key, Vector3(x, y0, z - t * 0.5), Vector3(xb, y0 + h, z + t * 0.5))

## Wand entlang Z bei x, von za bis zb (za < zb), Oeffnungen gaps = [[z0, z1], ...].
static func _wall_z(bd: BP.Builder, body: StaticBody3D, key: String, x: float, za: float, zb: float, y0: float, h: float, gaps: Array, t: float = WALL_T) -> void:
	var z := za
	var sorted_gaps := gaps.duplicate()
	sorted_gaps.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for g: Array in sorted_gaps:
		if float(g[0]) > z:
			_mm(bd, body, key, Vector3(x - t * 0.5, y0, z), Vector3(x + t * 0.5, y0 + h, float(g[0])))
		_mm(bd, body, key, Vector3(x - t * 0.5, y0 + DOOR_H, float(g[0])), Vector3(x + t * 0.5, y0 + h, float(g[1])))
		z = float(g[1])
	if zb > z:
		_mm(bd, body, key, Vector3(x - t * 0.5, y0, z), Vector3(x + t * 0.5, y0 + h, zb))

## Satteldach ueber einem Rechteck (First entlang X). Nur Optik.
static func _gable_x(bd: BP.Builder, key: String, xa: float, xb: float, za: float, zb: float, y: float, rise: float) -> void:
	var half := (zb - za) * 0.5
	var slope := sqrt(half * half + rise * rise)
	var ang := atan2(rise, half)
	var zc := (za + zb) * 0.5
	for side: float in [-1.0, 1.0]:
		var basis := Basis(Vector3(1, 0, 0), ang * side)
		var c := Vector3((xa + xb) * 0.5, y + rise * 0.5, zc + side * half * 0.5)
		bd.box(key, c, Vector3(xb - xa + 0.8, 0.18, slope + 0.5), basis)

## Satteldach mit First entlang Z.
static func _gable_z(bd: BP.Builder, key: String, xa: float, xb: float, za: float, zb: float, y: float, rise: float) -> void:
	var half := (xb - xa) * 0.5
	var slope := sqrt(half * half + rise * rise)
	var ang := atan2(rise, half)
	var xc := (xa + xb) * 0.5
	for side: float in [-1.0, 1.0]:
		var basis := Basis(Vector3(0, 0, 1), -ang * side)
		var c := Vector3(xc + side * half * 0.5, y + rise * 0.5, (za + zb) * 0.5)
		bd.box(key, c, Vector3(slope + 0.5, 0.18, zb - za + 0.8), basis)

# ------------------------------------------------------------------ Gelaende

static func _terrain(bd: BP.Builder, body: StaticBody3D) -> void:
	# Hauptflaeche (Ufer, Grundstueck, Wiese) und Land oestlich bis hinter die Strasse
	_mm(bd, body, "grass", Vector3(-32.0, -3.0, -44.0), Vector3(110.0, 0.0, 160.0))
	# Kaimauer (See im Norden und Westen) mit niedriger Kante
	_mm(bd, body, "quay", Vector3(-32.6, -3.0, -44.6), Vector3(-7.2, 0.12, -44.0))
	_mm(bd, body, "quay", Vector3(-4.8, -3.0, -44.6), Vector3(110.0, 0.12, -44.0))
	_mm(bd, body, "quay", Vector3(-32.6, -3.0, -44.6), Vector3(-32.0, 0.12, 22.0))
	_mm(bd, body, "quay", Vector3(-32.6, -3.0, 34.0), Vector3(-32.0, 0.12, 160.0))
	# Seegrund
	_mm(bd, body, "mountain", Vector3(-160.0, -5.0, -200.0), Vector3(110.0, -3.0, -44.6))
	_mm(bd, body, "mountain", Vector3(-160.0, -5.0, -44.6), Vector3(-32.6, -3.0, 160.0))
	# Hang: Plateau (Startplatz) und Boeschung hinunter zur Wiese
	_mm(bd, body, "grass", Vector3(-20.0, -1.0, 70.0), Vector3(30.0, 5.0, 104.0))
	var top := Vector3(5.0, 5.0, 70.0)
	var bottom := Vector3(5.0, 0.0, 48.0)
	var d := (bottom - top).normalized()
	var up := Vector3(1, 0, 0).cross(d).normalized()
	if up.y < 0.0:
		up = -up
	var basis := Basis(Vector3(1, 0, 0), up, Vector3(1, 0, 0).cross(up))
	var size := Vector3(50.0, 2.0, top.distance_to(bottom) + 0.6)
	var c := (top + bottom) * 0.5 - up * 1.0
	bd.box("grass", c, size, basis)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = Transform3D(basis, c)
	body.add_child(cs)
	# Pfad ueber den Hang (Optik) und Ausguck-Felsen
	for i in 6:
		var rp := Vector3(-14.0 + i * 7.5, 5.0, 100.0 + (i % 2) * 1.5)
		bd.box("stone", rp + Vector3(0, 0.4, 0), Vector3(2.4, 1.2, 1.8), Basis(Vector3.UP, i * 0.7))
	_sb(bd, body, "stone", Vector3(-6.0, 5.5, 76.0), Vector3(2.6, 1.0, 1.6), 20.0)
	_sb(bd, body, "stone", Vector3(9.0, 5.45, 77.0), Vector3(2.0, 0.9, 1.4), -15.0)
	# Feldweg von der Strasse auf den Hang (Optik)
	_vis(bd, "gravel", Vector3(30.0, 5.0, 88.0), Vector3(38.0, 5.02, 91.0))

# ------------------------------------------------------------------ Grundstuecksmauer

static func _estate_walls(bd: BP.Builder, body: StaticBody3D) -> void:
	# Suedmauer mit Toreinfahrt (x 10..18), Ostmauer bis zum Ufer
	_mm(bd, body, "stone", Vector3(-23.0, 0.0, 29.75), Vector3(9.6, 2.5, 30.25))
	_mm(bd, body, "stone", Vector3(18.4, 0.0, 29.75), Vector3(34.25, 2.5, 30.25))
	_mm(bd, body, "stone", Vector3(33.75, 0.0, -44.0), Vector3(34.25, 2.5, 30.25))
	# Mauerabdeckung
	_vis(bd, "quay", Vector3(-23.0, 2.5, 29.65), Vector3(9.6, 2.62, 30.35))
	_vis(bd, "quay", Vector3(18.4, 2.5, 29.65), Vector3(34.35, 2.62, 30.35))
	_vis(bd, "quay", Vector3(33.65, 2.5, -44.0), Vector3(34.35, 2.62, 30.35))
	# Torpfeiler und offene Torfluegel
	for px: float in [9.6, 18.4]:
		_sb(bd, body, "stone", Vector3(px, 1.6, 30.0), Vector3(0.9, 3.2, 0.9))
		bd.box("quay", Vector3(px, 3.28, 30.0), Vector3(1.05, 0.16, 1.05))
	for side: float in [-1.0, 1.0]:
		var hinge := Vector3(14.0 + side * 3.95, 0.0, 30.0)
		var leaf_c := hinge + Vector3(0.0, 1.2, -1.9)
		for k in 9:
			bd.box("iron", leaf_c + Vector3(0.0, 0.0, -1.7 + k * 0.42), Vector3(0.04, 2.2, 0.04))
		bd.box("iron", leaf_c + Vector3(0.0, 1.05, 0.0), Vector3(0.06, 0.06, 3.7))
		bd.box("iron", leaf_c + Vector3(0.0, -0.9, 0.0), Vector3(0.06, 0.06, 3.7))
		Geo.add_box_shape(body, leaf_c, Vector3(0.1, 2.4, 3.7))
	# Messingschild am Tor
	bd.box("brass", Vector3(9.6, 1.9, 30.47), Vector3(0.5, 0.3, 0.03))

# ------------------------------------------------------------------ Bootshaus

static func _boathouse(bd: BP.Builder, body: StaticBody3D) -> void:
	var xa := -32.0
	var xb := -23.0
	var za := 22.0
	var zb := 34.0
	var h := 3.2
	var t := 0.25
	# Wandscheiben (Holz), Tueren Nord/Sued bei x -27.5 (Breite 2.4)
	_wall_x(bd, body, "timber", za, xa, xb, 0.0, h, [[-28.7, -26.3]], t)
	_wall_x(bd, body, "timber", zb, xa, xb, 0.0, h, [[-28.7, -26.3]], t)
	_wall_z(bd, body, "timber", xa, za, zb, 0.0, h, [], t)
	_wall_z(bd, body, "timber", xb, za, zb, 0.0, h, [], t)
	# Bretterboden, Dach
	_vis(bd, "planks", Vector3(xa, 0.0, za), Vector3(xb, 0.05, zb))
	_gable_z(bd, "roof", xa - 0.3, xb + 0.3, za - 0.4, zb + 0.4, h, 2.0)
	# Giebeldreiecke (gestuft angedeutet)
	for zz: float in [za, zb]:
		for k in 4:
			var w := 9.0 * (1.0 - float(k) / 4.0)
			bd.box("timber_dark", Vector3((xa + xb) * 0.5, h + 0.25 + k * 0.5, zz), Vector3(w, 0.5, 0.2))
	# Seetor (geschlossen) an der Westwand
	bd.box("timber_dark", Vector3(xa - 0.15, 1.3, 28.0), Vector3(0.1, 2.6, 4.6))
	# Motorboot auf dem Slipwagen
	_sb(bd, body, "iron", Vector3(-30.4, 0.3, 28.0), Vector3(1.4, 0.6, 5.2))
	bd.box("white_paint", Vector3(-30.4, 0.95, 28.0), Vector3(1.9, 0.7, 6.0))
	bd.box("timber", Vector3(-30.4, 1.32, 28.6), Vector3(1.7, 0.06, 3.6))
	bd.box("dark", Vector3(-30.4, 1.55, 27.0), Vector3(1.6, 0.45, 0.06))
	Geo.add_box_shape(body, Vector3(-30.4, 0.95, 28.0), Vector3(1.9, 0.7, 6.0))
	# Werkbank, Kanister, Taurollen (Deckung)
	_sb(bd, body, "timber_dark", Vector3(-23.6, 0.45, 26.0), Vector3(0.7, 0.9, 2.6))
	_sb(bd, body, "red_paint", Vector3(-24.0, 0.25, 31.6), Vector3(0.5, 0.5, 0.35))
	_sb(bd, body, "timber_dark", Vector3(-25.0, 0.4, 32.8), Vector3(1.6, 0.8, 1.0))
	# Steg vor dem Bootshaus (kleiner Bootssteg am Westufer, nur Optik)
	_vis(bd, "planks", Vector3(-38.0, 0.0, 26.0), Vector3(-32.0, 0.18, 30.0))

# ------------------------------------------------------------------ Garten, Terrasse

static func _garden(bd: BP.Builder, body: StaticBody3D) -> void:
	# Hecken (Sichtschutz, nicht ueberkletterbar hoch)
	_sb(bd, body, "hedge", Vector3(-16.5, 0.85, 12.0), Vector3(7.0, 1.7, 0.9))
	_sb(bd, body, "hedge", Vector3(-29.0, 0.85, 0.0), Vector3(4.0, 1.7, 0.9))
	_sb(bd, body, "hedge", Vector3(-15.75, 0.85, -4.0), Vector3(6.5, 1.7, 0.9))
	_sb(bd, body, "hedge", Vector3(-27.0, 0.85, -14.0), Vector3(6.0, 1.7, 0.9))
	_sb(bd, body, "hedge", Vector3(-8.0, 0.75, 20.0), Vector3(0.9, 1.5, 8.0))
	# Gartenweg (Kies) vom Bootshaus zur Terrasse
	for p: Array in [[Vector3(-28.5, 0.0, 21.5), Vector3(-26.5, 0.02, 14.0)], [Vector3(-26.5, 0.0, 14.0), Vector3(-22.5, 0.02, -10.0)],
			[Vector3(-22.5, 0.0, -10.0), Vector3(-18.0, 0.02, -14.0)]]:
		_vis(bd, "gravel", p[0], p[1])
	# Gartenbank, Steinfigur, Pavillon-Pfosten
	_sb(bd, body, "timber", Vector3(-30.6, 0.25, 8.0), Vector3(0.6, 0.5, 1.8))
	_sb(bd, body, "stone", Vector3(-14.0, 0.6, 4.0), Vector3(0.8, 1.2, 0.8))
	bd.ball("stone", Vector3(-14.0, 1.55, 4.0), Vector3(0.6, 0.7, 0.6))
	for q: Vector3 in [Vector3(-31.0, 0.0, -24.0), Vector3(-27.0, 0.0, -24.0), Vector3(-31.0, 0.0, -20.0), Vector3(-27.0, 0.0, -20.0)]:
		_sb(bd, body, "white_paint", q + Vector3(0, 1.3, 0), Vector3(0.18, 2.6, 0.18))
	_gable_x(bd, "roof", -31.3, -26.7, -24.3, -19.7, 2.6, 1.0)
	# Terrasse (Natursteinplatten) mit Balustrade West/Nord
	_mm(bd, body, "stone", Vector3(-20.0, 0.0, -30.0), Vector3(-12.0, 0.12, -14.0))
	_mm(bd, body, "white_paint", Vector3(-20.2, 0.12, -30.0), Vector3(-19.8, 1.0, -19.5))
	_mm(bd, body, "white_paint", Vector3(-20.0, 0.12, -30.2), Vector3(-12.2, 1.0, -29.8))
	# Tisch und Stuehle
	_sb(bd, body, "iron", Vector3(-17.0, 0.5, -21.0), Vector3(1.2, 0.08, 1.2))
	bd.box("iron", Vector3(-17.0, 0.25, -21.0), Vector3(0.08, 0.5, 0.08))
	for o: Vector3 in [Vector3(-0.9, 0, 0), Vector3(0.9, 0, 0), Vector3(0, 0, 0.9)]:
		_sb(bd, body, "iron", Vector3(-17.0, 0.25, -21.0) + o, Vector3(0.45, 0.5, 0.45))
	# Bootsanleger-Pfad hinter der Villa zum Steg
	_vis(bd, "stone", Vector3(-7.0, 0.0, -44.0), Vector3(-5.0, 0.03, -36.0))
	_vis(bd, "stone", Vector3(-7.0, 0.0, -37.5), Vector3(11.0, 0.03, -35.5))
	_vis(bd, "stone", Vector3(9.0, 0.0, -36.0), Vector3(11.0, 0.03, -32.0))

# ------------------------------------------------------------------ Vorplatz

static func _forecourt(bd: BP.Builder, body: StaticBody3D, world: Node3D, covers: Array) -> void:
	# Kiesauffahrt vom Tor zum Rondell und zur Haustuer
	_vis(bd, "gravel", Vector3(10.5, 0.0, -2.0), Vector3(17.5, 0.02, 30.0))
	_vis(bd, "gravel", Vector3(2.0, 0.0, -13.0), Vector3(26.0, 0.02, 7.0))
	# Brunnen
	bd.cyl("stone", Vector3(14.0, 0.3, 0.0), 2.5, 2.6, 0.6, 20)
	bd.cyl("dark", Vector3(14.0, 0.58, 0.0), 2.25, 2.25, 0.06, 20)
	bd.cyl("stone", Vector3(14.0, 1.0, 0.0), 0.35, 0.5, 1.4, 10)
	bd.cyl("stone", Vector3(14.0, 1.75, 0.0), 0.9, 0.6, 0.2, 14)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.55
	cyl.height = 0.6
	cs.shape = cyl
	cs.position = Vector3(14.0, 0.3, 0.0)
	body.add_child(cs)
	# Sicherheitsdienst-Wagen und Limousine (Deckung)
	Props.vehicle(world, Vector3(24.0, 0.0, 8.0), 0.0, "van", Color(0.07, 0.08, 0.11), false, false, covers)
	Props.vehicle(world, Vector3(22.5, 0.0, -6.0), 90.0, "truck", Color(0.1, 0.1, 0.11), false, false, covers)
	# Pflanzkuebel an der Auffahrt
	for z: float in [24.0, 16.0, 8.0]:
		_sb(bd, body, "stone", Vector3(9.6, 0.4, z), Vector3(0.9, 0.8, 0.9))
		bd.ball("hedge", Vector3(9.6, 1.1, z), Vector3(1.0, 0.9, 1.0))
	# Hecke vor der Ostmauer
	_sb(bd, body, "hedge", Vector3(32.0, 0.9, -10.0), Vector3(1.2, 1.8, 30.0))

# ------------------------------------------------------------------ Villa

static func _villa(bd: BP.Builder, body: StaticBody3D) -> void:
	var xa := -12.0
	var xb := 12.0
	var za := -32.0
	var zb := -14.0
	# Sockel und Boden
	_mm(bd, body, "stone", Vector3(xa - 0.4, 0.0, za - 0.4), Vector3(xb + 0.4, FLOOR_Y, zb + 0.4))
	_vis(bd, "parquet", Vector3(xa + 0.2, FLOOR_Y, za + 0.2), Vector3(xb - 0.2, FLOOR_Y + 0.01, zb - 0.2))
	# Aussenwaende bis zur Traufe (Tueren: vorne x 6, Terrasse z -22.8, hinten x 10)
	_wall_x(bd, body, "plaster", zb, xa, xb, FLOOR_Y, EAVE - FLOOR_Y, [[4.8, 7.2]])
	_wall_x(bd, body, "plaster", za, xa, xb, FLOOR_Y, EAVE - FLOOR_Y, [[9.3, 10.7]])
	_wall_z(bd, body, "plaster", xa, za, zb, FLOOR_Y, EAVE - FLOOR_Y, [[-24.0, -21.6]])
	_wall_z(bd, body, "plaster", xb, za, zb, FLOOR_Y, EAVE - FLOOR_Y, [])
	# Geschossdecke und Dachboden
	_mm(bd, body, "plaster_dark", Vector3(xa, STOREY, za), Vector3(xb, STOREY + 0.25, zb))
	_mm(bd, body, "plaster_dark", Vector3(xa - 0.3, EAVE, za - 0.3), Vector3(xb + 0.3, EAVE + 0.2, zb + 0.3))
	_gable_x(bd, "roof", xa - 0.8, xb + 0.8, za - 0.8, zb + 0.8, EAVE + 0.2, 3.6)
	# Walmenden angedeutet (gestufte Giebelfuellung)
	for xx: float in [xa - 0.1, xb + 0.1]:
		for k in 6:
			var w := 18.4 * (1.0 - float(k) / 6.0)
			bd.box("plaster", Vector3(xx, EAVE + 0.5 + k * 0.6, (za + zb) * 0.5), Vector3(0.2, 0.6, w))
	# Gesimse
	for y: float in [STOREY + 0.1, EAVE - 0.15]:
		bd.box("white_paint", Vector3(0.0, y, zb + 0.22), Vector3(24.6, 0.18, 0.12))
		bd.box("white_paint", Vector3(0.0, y, za - 0.22), Vector3(24.6, 0.18, 0.12))
		bd.box("white_paint", Vector3(xa - 0.22, y, (za + zb) * 0.5), Vector3(0.12, 0.18, 18.6))
		bd.box("white_paint", Vector3(xb + 0.22, y, (za + zb) * 0.5), Vector3(0.12, 0.18, 18.6))
	# Schornsteine
	bd.box("plaster_dark", Vector3(0.4, EAVE + 3.4, -27.0), Vector3(0.9, 3.2, 0.9))
	bd.box("plaster_dark", Vector3(-6.0, EAVE + 3.0, -20.0), Vector3(0.9, 2.6, 0.9))
	# Vordach mit Saeulen ueber der Haustuer
	for sx: float in [4.4, 7.6]:
		_sb(bd, body, "white_paint", Vector3(sx, 1.5, -11.6), Vector3(0.35, 3.0, 0.35))
	bd.box("white_paint", Vector3(6.0, 3.1, -12.8), Vector3(4.2, 0.25, 2.8))
	_mm(bd, body, "stone", Vector3(4.0, 0.0, -13.8), Vector3(8.0, 0.06, -11.0))
	# Fenster: warm erleuchtet, mit Rahmen (Erdgeschoss und Obergeschoss)
	var fronts: Array = [
		# [richtung, fester wert, von, bis, auslassen]
		["z", zb + 0.2, xa, xb, [6.0]],
		["z", za - 0.2, xa, xb, [10.0]],
		["x", xa - 0.2, za, zb, [-22.8]],
		["x", xb + 0.2, za, zb, []],
	]
	for f: Array in fronts:
		var dir: String = f[0]
		var fixed: float = f[1]
		var a: float = f[2]
		var b: float = f[3]
		var skip: Array = f[4]
		var n := int((b - a) / 3.0)
		for i in n:
			var u := a + 1.5 + i * 3.0
			var skip_this := false
			for s: float in skip:
				if absf(u - s) < 1.6:
					skip_this = true
			for floor_i in 2:
				if floor_i == 0 and skip_this:
					continue
				var y := 1.8 if floor_i == 0 else 5.3
				var c := Vector3(u, y, fixed) if dir == "z" else Vector3(fixed, y, u)
				var s_glass := Vector3(1.1, 1.6, 0.06) if dir == "z" else Vector3(0.06, 1.6, 1.1)
				var s_frame := Vector3(1.35, 1.85, 0.05) if dir == "z" else Vector3(0.05, 1.85, 1.35)
				var lit := (i + floor_i * 3) % 4 != 1
				bd.box("white_paint", c, s_frame)
				var push := Vector3(0, 0, 0.02 * signf(fixed)) if dir == "z" else Vector3(0.02 * signf(fixed), 0, 0)
				bd.box("win_warm" if lit else "glass", c + push, s_glass)
				# Fensterlaeden
				var off := Vector3(0.85, 0, 0) if dir == "z" else Vector3(0, 0, 0.85)
				var s_sh := Vector3(0.5, 1.8, 0.05) if dir == "z" else Vector3(0.05, 1.8, 0.5)
				bd.box("timber_dark", c + off, s_sh)
				bd.box("timber_dark", c - off, s_sh)

static func _interior(bd: BP.Builder, body: StaticBody3D) -> void:
	var y0 := FLOOR_Y
	var h := STOREY - FLOOR_Y
	# Trennwand Salon | Halle+Bibliothek (Durchgang bei z -18), Wand Halle | Bibliothek (Durchgang x 6)
	_wall_z(bd, body, "plaster", 0.0, -32.0, -14.0, y0, h, [[-18.8, -17.2]], 0.25)
	_wall_x(bd, body, "plaster", -22.0, 0.0, 12.0, y0, h, [[5.1, 6.9]], 0.25)
	# Teppiche
	_vis(bd, "rug", Vector3(3.5, y0, -20.5), Vector3(8.5, y0 + 0.02, -15.5))
	_vis(bd, "rug", Vector3(-9.0, y0, -27.0), Vector3(-3.0, y0 + 0.02, -19.0))
	_vis(bd, "rug", Vector3(3.0, y0, -30.5), Vector3(9.0, y0 + 0.02, -24.5))
	# Halle: Konsole, Garderobe, Treppe (verstellt, Absperrung) an der Ostwand
	_sb(bd, body, "timber_dark", Vector3(1.0, y0 + 0.45, -15.0), Vector3(1.4, 0.9, 0.5))
	for k in 8:
		_sb(bd, body, "timber", Vector3(11.0, y0 + 0.11 + k * 0.22, -20.6 + k * 0.32), Vector3(1.6, 0.22, 0.32 + (7 - k) * 0.0))
	_sb(bd, body, "timber_dark", Vector3(11.0, y0 + 1.05, -17.9), Vector3(1.8, 2.1, 0.6))
	_sb(bd, body, "timber_dark", Vector3(10.1, y0 + 0.5, -18.4), Vector3(0.08, 1.0, 4.4))
	# Salon: Sofas, Fluegel, Kamin, Couchtisch
	_sb(bd, body, "sofa", Vector3(-8.5, y0 + 0.4, -23.0), Vector3(0.9, 0.8, 2.6))
	_sb(bd, body, "sofa", Vector3(-4.0, y0 + 0.4, -23.0), Vector3(0.9, 0.8, 2.6))
	_sb(bd, body, "timber_dark", Vector3(-6.25, y0 + 0.22, -23.0), Vector3(1.6, 0.44, 1.0))
	_sb(bd, body, "black", Vector3(-8.5, y0 + 0.5, -29.6), Vector3(2.0, 1.0, 1.6))
	bd.box("black", Vector3(-8.5, y0 + 1.25, -30.3), Vector3(2.0, 0.6, 0.08), Basis(Vector3(1, 0, 0), -0.35))
	_sb(bd, body, "marble", Vector3(-11.6, y0 + 0.7, -19.0), Vector3(0.5, 1.4, 2.0))
	bd.box("fire_glow", Vector3(-11.45, y0 + 0.4, -19.0), Vector3(0.1, 0.5, 1.1))
	_sb(bd, body, "timber_dark", Vector3(-1.0, y0 + 0.9, -30.8), Vector3(1.2, 1.8, 0.5))
	# Bibliothek: Regale (Ostwand, Rueckwand bis zur Hintertuer), Schreibtisch, Kamin, Sessel
	_sb(bd, body, "timber_dark", Vector3(11.55, y0 + 1.6, -27.0), Vector3(0.6, 3.2, 9.4))
	_sb(bd, body, "timber_dark", Vector3(4.2, y0 + 1.6, -31.55), Vector3(7.8, 3.2, 0.6))
	var book_keys: Array[String] = ["books", "books2", "books3"]
	for row in 5:
		var yy := y0 + 0.45 + row * 0.6
		for seg in 6:
			bd.box(book_keys[(row + seg) % 3], Vector3(11.2, yy, -31.0 + seg * 1.55 + 0.75), Vector3(0.12, 0.42, 1.4))
		for seg in 5:
			bd.box(book_keys[(row + seg + 1) % 3], Vector3(0.9 + seg * 1.55 + 0.6, yy, -31.2), Vector3(1.4, 0.42, 0.12))
	_sb(bd, body, "leather", Vector3(6.0, y0 + 0.39, -29.0), Vector3(1.8, 0.78, 0.9))
	bd.box("timber_dark", Vector3(6.0, y0 + 0.8, -29.0), Vector3(1.9, 0.05, 1.0))
	_sb(bd, body, "leather", Vector3(6.0, y0 + 0.5, -30.0), Vector3(0.6, 1.0, 0.6))
	bd.box("brass", Vector3(6.6, y0 + 1.05, -29.2), Vector3(0.12, 0.45, 0.12))
	bd.box("lamp_glow", Vector3(6.6, y0 + 1.32, -29.2), Vector3(0.32, 0.16, 0.32))
	_sb(bd, body, "marble", Vector3(0.45, y0 + 0.7, -27.0), Vector3(0.5, 1.4, 2.0))
	bd.box("fire_glow", Vector3(0.6, y0 + 0.4, -27.0), Vector3(0.1, 0.5, 1.1))
	_sb(bd, body, "leather", Vector3(2.0, y0 + 0.4, -25.2), Vector3(0.9, 0.8, 0.9))
	_sb(bd, body, "leather", Vector3(2.0, y0 + 0.4, -28.8), Vector3(0.9, 0.8, 0.9))
	# Globus und Leselampe
	bd.ball("folder", Vector3(9.5, y0 + 1.0, -24.0), Vector3(0.55, 0.55, 0.55))
	_sb(bd, body, "timber_dark", Vector3(9.5, y0 + 0.35, -24.0), Vector3(0.4, 0.7, 0.4))
	# Bilder an den Waenden (Halle, Salon)
	bd.box("folder", Vector3(0.18, 2.2, -16.0), Vector3(0.05, 1.0, 1.4))
	bd.box("books2", Vector3(-0.18, 2.2, -26.0), Vector3(0.05, 1.2, 1.8))
	bd.box("books3", Vector3(-11.8, 2.2, -27.0), Vector3(0.05, 1.0, 1.6))
	# Kronleuchter
	bd.box("brass", Vector3(6.0, STOREY - 0.6, -18.0), Vector3(0.05, 1.0, 0.05))
	bd.ball("lamp_glow", Vector3(6.0, STOREY - 1.15, -18.0), Vector3(0.7, 0.35, 0.7))
	bd.ball("lamp_glow", Vector3(-6.0, STOREY - 1.0, -23.0), Vector3(0.6, 0.3, 0.6))

# ------------------------------------------------------------------ See, Steg

static func _jetty(bd: BP.Builder, body: StaticBody3D) -> void:
	_mm(bd, body, "planks", Vector3(-7.0, 0.0, -72.0), Vector3(-5.0, 0.2, -44.0))
	for k in 8:
		var z := -46.0 - k * 3.8
		for sx: float in [-7.05, -4.95]:
			bd.cyl("timber_dark", Vector3(sx, -1.2, z), 0.12, 0.12, 3.0, 8)
	# Querstueck am Ende (Anleger)
	_mm(bd, body, "planks", Vector3(-7.0, 0.0, -72.0), Vector3(-2.5, 0.2, -69.5))
	for z: float in [-60.0, -70.5]:
		_sb(bd, body, "iron", Vector3(-5.1, 0.42, z), Vector3(0.22, 0.45, 0.22))
	# Ruderboot am Steg (Optik)
	bd.box("timber", Vector3(-8.6, -0.15, -52.0), Vector3(1.3, 0.5, 4.0))

static func _water(lv: Node3D) -> void:
	var base := RP.water_mat([])
	var m := base.duplicate() as ShaderMaterial
	m.set_shader_parameter("flow", Vector2(0.12, 0.05))
	m.set_shader_parameter("wave_height", 0.05)
	m.set_shader_parameter("wave_scale", 0.06)
	m.set_shader_parameter("rain_ripples", 0.0)
	m.set_shader_parameter("shore_z_a", -9000.0)
	m.set_shader_parameter("shore_z_b", -9001.0)
	m.set_shader_parameter("deep_color", Vector3(0.03, 0.045, 0.06))
	m.set_shader_parameter("shallow_color", Vector3(0.06, 0.075, 0.085))
	var pm := PlaneMesh.new()
	pm.size = Vector2(900.0, 900.0)
	pm.subdivide_width = 90
	pm.subdivide_depth = 90
	var mi := MeshInstance3D.new()
	mi.name = "Traunsee"
	mi.mesh = pm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(-40.0, WATER_Y, -180.0)
	lv.add_child(mi)

# ------------------------------------------------------------------ Strasse, Garde

static func _road(bd: BP.Builder, world: Node3D, covers: Array) -> void:
	bd.box("asphalt", Vector3(45.0, 0.01, 50.0), Vector3(8.0, 0.04, 220.0))
	for k in 22:
		bd.box("white_paint", Vector3(45.0, 0.035, -55.0 + k * 10.0), Vector3(0.12, 0.01, 4.0))
	# Leitpfosten
	for k in 18:
		bd.box("white_paint", Vector3(40.6, 0.5, -40.0 + k * 10.0), Vector3(0.1, 1.0, 0.1))
	# Garde-Transporter (grau) am Strassenrand
	Props.vehicle(world, Vector3(45.5, 0.0, 20.0), 0.0, "van", Color(0.34, 0.35, 0.36), false, false, covers)
	Props.vehicle(world, Vector3(45.5, 0.0, 30.0), 0.0, "van", Color(0.34, 0.35, 0.36), false, false, covers)

static func _mountains(lv: Node3D, mats: Dictionary) -> void:
	# Low-Poly-Kegel jenseits des Sees (Norden, Nordosten, Westen) mit Schneekuppen
	var peaks: Array = [
		[Vector3(-420.0, -5.0, -620.0), 330.0, 380.0, "mountain_far"],
		[Vector3(-120.0, -5.0, -700.0), 380.0, 460.0, "mountain_far"],
		[Vector3(260.0, -5.0, -560.0), 300.0, 420.0, "mountain_far"],
		[Vector3(170.0, -5.0, -330.0), 150.0, 330.0, "mountain"],
		[Vector3(-380.0, -5.0, -180.0), 220.0, 240.0, "mountain"],
		[Vector3(-420.0, -5.0, 160.0), 260.0, 200.0, "mountain"],
		[Vector3(40.0, -5.0, -420.0), 160.0, 190.0, "mountain"],
	]
	for p: Array in peaks:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = float(p[1])
		cm.height = float(p[2])
		cm.radial_segments = 7
		cm.rings = 2
		var mi := Geo.mesh_node(cm, mats[str(p[3])], (p[0] as Vector3) + Vector3(0, float(p[2]) * 0.5, 0), false)
		mi.rotation.y = randf() * TAU
		lv.add_child(mi)
		var cap := CylinderMesh.new()
		cap.top_radius = 0.0
		cap.bottom_radius = float(p[1]) * 0.22
		cap.height = float(p[2]) * 0.22
		cap.radial_segments = 7
		cap.rings = 1
		var ci := Geo.mesh_node(cap, mats["snow"], (p[0] as Vector3) + Vector3(0, float(p[2]) * 0.89 + 0.5, 0), false)
		ci.rotation.y = mi.rotation.y
		lv.add_child(ci)
	# Lichter am anderen Ufer
	var srng := RandomNumberGenerator.new()
	srng.seed = 1806
	for i in 40:
		var a := srng.randf_range(-2.4, -0.4)
		var r := srng.randf_range(380.0, 520.0)
		var p := Vector3(cos(a) * r - 60.0, srng.randf_range(0.5, 6.0), sin(a) * r * 0.75 - 60.0)
		lv.add_child(Geo.box_mesh_node(Vector3(0.8, 0.6, 0.8), mats["shore_light"], p))

static func _trees(lv: Node3D, world: Node3D, rng: RandomNumberGenerator) -> void:
	var trees_in: Array = []
	var trees_out: Array = []
	# Hang: Fichten rechts und links des Startplatzes, hinten dicht
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := (-24.0 - rng.randf() * 7.0) if side < 0.0 else (31.0 + rng.randf() * 5.0)
		trees_in.append([Vector3(x, 0.0, rng.randf_range(36.0, 100.0)), rng.randf_range(0.75, 1.05)])
	for i in 40:
		trees_out.append([Vector3(rng.randf_range(-30.0, 36.0), 5.0, rng.randf_range(106.0, 140.0)), rng.randf_range(0.8, 1.15)])
	# Jenseits der Strasse, Ostufer
	for i in 50:
		trees_out.append([Vector3(rng.randf_range(52.0, 105.0), 0.0, rng.randf_range(-40.0, 150.0)), rng.randf_range(0.8, 1.2)])
	# Im Grundstueck einzelne Fichten an der Ostmauer
	for z: float in [-36.0, -26.0, 20.0, 25.0]:
		trees_in.append([Vector3(31.5, 0.0, z), rng.randf_range(0.8, 0.95)])
	NP.forest(lv, trees_in + trees_out, rng)
	NP.trunk_colliders(world, trees_in)
	# Laubbaeume im Garten (Ball-Kronen), ohne Kollision der Krone
	var bd := BP.Builder.new({"bark": Geo.flat(Color(0.2, 0.15, 0.11), 0.95), "leaves": Geo.flat(Color(0.12, 0.2, 0.08), 0.95)})
	var tb := Geo.static_body()
	for p: Vector3 in [Vector3(-30.0, 0.0, 16.0), Vector3(-21.0, 0.0, 19.0), Vector3(-30.5, 0.0, -7.0), Vector3(-9.0, 0.0, -6.0), Vector3(-25.0, 0.0, -33.0)]:
		bd.cyl("bark", p + Vector3(0, 1.8, 0), 0.18, 0.26, 3.6, 8)
		bd.ball("leaves", p + Vector3(0, 4.6, 0), Vector3(4.2, 3.6, 4.2))
		bd.ball("leaves", p + Vector3(0.8, 5.6, 0.4), Vector3(2.8, 2.4, 2.8))
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.3
		cy.height = 3.6
		cs.shape = cy
		cs.position = p + Vector3(0, 1.8, 0)
		tb.add_child(cs)
	bd.build(lv)
	world.add_child(tb)

# ------------------------------------------------------------------ Licht

static func _omni(lv: Node3D, pos: Vector3, c: Color, energy: float, rng_: float, shadows: bool = false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = c
	l.light_energy = energy
	l.omni_range = rng_
	l.light_volumetric_fog_energy = 0.5
	l.shadow_enabled = shadows
	l.position = pos
	lv.add_child(l)
	return l

static func _lights(lv: Node3D, mats: Dictionary, pts: Dictionary) -> void:
	var warm := Color(1.0, 0.72, 0.45)
	# Innenraeume
	pts["light_hall"] = _omni(lv, Vector3(6.0, 2.6, -18.0), warm, 2.2, 9.0, true)
	pts["light_salon"] = _omni(lv, Vector3(-6.0, 2.6, -23.0), warm, 1.8, 10.0)
	pts["light_library"] = _omni(lv, Vector3(6.0, 2.7, -27.0), warm, 1.5, 8.0, true)
	_omni(lv, Vector3(6.6, 1.5, -29.2), Color(1.0, 0.66, 0.38), 0.9, 3.5)
	_omni(lv, Vector3(0.9, 0.6, -27.0), Color(1.0, 0.45, 0.15), 1.2, 4.0)
	_omni(lv, Vector3(-11.0, 0.6, -19.0), Color(1.0, 0.45, 0.15), 1.0, 4.0)
	# Aussen: Torpfeiler, Haustuer, Terrasse, Bootshaus, Steg
	var lamp_pts: Array = [
		[Vector3(9.6, 3.6, 30.0), 1.6, 8.0], [Vector3(18.4, 3.6, 30.0), 1.6, 8.0],
		[Vector3(6.0, 2.85, -12.4), 1.8, 8.0], [Vector3(-12.6, 2.8, -22.8), 1.2, 7.0],
		[Vector3(-27.5, 2.9, 34.5), 0.9, 5.0], [Vector3(-5.1, 1.6, -70.5), 1.3, 7.0],
		[Vector3(10.0, 2.8, -32.6), 1.0, 6.0],
	]
	for lp: Array in lamp_pts:
		var p: Vector3 = lp[0]
		lv.add_child(Geo.box_mesh_node(Vector3(0.22, 0.3, 0.22), mats["lamp_glow"], p))
		_omni(lv, p + Vector3(0, -0.3, 0), warm, float(lp[1]), float(lp[2]))
	lv.add_child(Geo.box_mesh_node(Vector3(0.08, 1.4, 0.08), mats["iron"], Vector3(-5.1, 0.9, -70.5)))
	# Fenster-Abstrahlung nach draussen (schwach, ohne Schatten)
	for p: Vector3 in [Vector3(-6.0, 1.8, -12.6), Vector3(9.5, 1.8, -12.6), Vector3(-13.4, 1.8, -27.0), Vector3(13.4, 1.8, -23.0)]:
		_omni(lv, p, warm, 0.5, 5.0)

## Hintertuer der Bibliothek (Fluegel an Scharnier, gehoert NICHT zur Navmesh-Quelle).
static func _back_door(lv: Node3D, mats: Dictionary) -> Node3D:
	var hinge := Node3D.new()
	hinge.name = "BackDoor"
	hinge.position = Vector3(9.3, FLOOR_Y, -32.0)
	lv.add_child(hinge)
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.set_meta("no_fit", true)
	hinge.add_child(b)
	b.add_child(Geo.box_mesh_node(Vector3(1.4, 2.45, 0.08), mats["timber_dark"], Vector3(0.7, 1.225, 0.0)))
	b.add_child(Geo.box_mesh_node(Vector3(0.06, 0.06, 0.14), mats["brass"], Vector3(1.25, 1.05, 0.0)))
	Geo.add_box_shape(b, Vector3(0.7, 1.225, 0.0), Vector3(1.4, 2.45, 0.12))
	return hinge

## Halbe Akte Nordlicht auf dem Schreibtisch (erst nach Webers Abgang sichtbar).
static func _akte(lv: Node3D, mats: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = "AkteNordlicht"
	n.position = Vector3(5.7, FLOOR_Y + 0.83, -28.9)
	lv.add_child(n)
	n.add_child(Geo.box_mesh_node(Vector3(0.34, 0.05, 0.46), mats["folder"], Vector3.ZERO, Vector3(0, 12, 0)))
	n.add_child(Geo.box_mesh_node(Vector3(0.3, 0.02, 0.42), mats["paper"], Vector3(0.02, 0.035, 0.0), Vector3(0, 8, 0)))
	n.visible = false
	return n

## Wasserflugzeug (Hochdecker auf Schwimmern), Nase nach -Z. Liefert {"root", "prop"}.
static func _seaplane(lv: Node3D, mats: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "Wasserflugzeug"
	root.position = Vector3(-1.5, WATER_Y, -66.0)
	lv.add_child(root)
	var white: Material = mats["white_paint"]
	var red: Material = mats["red_paint"]
	var dark: Material = mats["dark"]
	for sx: float in [-1.25, 1.25]:
		root.add_child(Geo.box_mesh_node(Vector3(0.55, 0.45, 5.6), white, Vector3(sx, 0.15, -0.3)))
		root.add_child(Geo.box_mesh_node(Vector3(0.5, 0.3, 0.8), white, Vector3(sx, 0.25, -3.3), Vector3(-20, 0, 0)))
		root.add_child(Geo.box_mesh_node(Vector3(0.08, 1.3, 0.08), dark, Vector3(sx * 0.7, 0.95, -1.4), Vector3(0, 0, sx * 18.0)))
		root.add_child(Geo.box_mesh_node(Vector3(0.08, 1.3, 0.08), dark, Vector3(sx * 0.7, 0.95, 0.6), Vector3(0, 0, sx * 18.0)))
	root.add_child(Geo.box_mesh_node(Vector3(1.25, 1.4, 4.2), white, Vector3(0, 2.0, -0.8)))
	root.add_child(Geo.box_mesh_node(Vector3(1.27, 0.2, 4.22), red, Vector3(0, 1.75, -0.8)))
	root.add_child(Geo.box_mesh_node(Vector3(1.1, 0.5, 0.9), mats["glass"], Vector3(0, 2.45, -2.2)))
	root.add_child(Geo.box_mesh_node(Vector3(0.7, 0.8, 3.6), white, Vector3(0, 2.25, 3.0)))
	root.add_child(Geo.box_mesh_node(Vector3(0.08, 1.3, 1.2), red, Vector3(0, 3.1, 4.4)))
	root.add_child(Geo.box_mesh_node(Vector3(3.2, 0.06, 0.9), white, Vector3(0, 2.4, 4.4)))
	root.add_child(Geo.box_mesh_node(Vector3(12.0, 0.18, 1.6), white, Vector3(0, 2.85, -1.2)))
	root.add_child(Geo.box_mesh_node(Vector3(0.6, 0.19, 1.62), red, Vector3(5.7, 2.851, -1.2)))
	root.add_child(Geo.box_mesh_node(Vector3(0.6, 0.19, 1.62), red, Vector3(-5.7, 2.851, -1.2)))
	root.add_child(Geo.box_mesh_node(Vector3(0.9, 0.9, 0.5), dark, Vector3(0, 2.0, -3.1)))
	var prop := Node3D.new()
	prop.position = Vector3(0, 2.0, -3.4)
	root.add_child(prop)
	prop.add_child(Geo.box_mesh_node(Vector3(2.1, 0.16, 0.05), dark, Vector3.ZERO))
	prop.add_child(Geo.box_mesh_node(Vector3(0.18, 0.18, 0.16), mats["brass"], Vector3.ZERO))
	# Positionslichter
	root.add_child(Geo.box_mesh_node(Vector3(0.12, 0.12, 0.12), Geo.flat(Color(0.2, 0, 0), 0.5, 0.0, Color(1, 0.1, 0.05), 6.0), Vector3(-6.0, 2.85, -1.2)))
	root.add_child(Geo.box_mesh_node(Vector3(0.12, 0.12, 0.12), Geo.flat(Color(0, 0.2, 0), 0.5, 0.0, Color(0.1, 1, 0.2), 6.0), Vector3(6.0, 2.85, -1.2)))
	return {"root": root, "prop": prop}

# ------------------------------------------------------------------ Grenzen

static func _boundaries(lv: Node3D) -> void:
	# Ufer West und Nord (Luecke fuer den Steg), Strasse Ost, hinter dem Hang Sued
	lv.call("_invisible_wall", Vector3(-32.4, 3.0, 29.0), Vector3(0.4, 8.0, 146.0))
	lv.call("_invisible_wall", Vector3(36.8, 3.0, 29.0), Vector3(0.4, 8.0, 146.0))
	lv.call("_invisible_wall", Vector3(2.5, 6.0, 102.6), Vector3(70.0, 12.0, 0.4))
	lv.call("_invisible_wall", Vector3(-19.85, 3.0, -44.35), Vector3(25.3, 8.0, 0.3))
	lv.call("_invisible_wall", Vector3(16.25, 3.0, -44.35), Vector3(41.5, 8.0, 0.3))
	# Steg: seitlich und am Ende
	lv.call("_invisible_wall", Vector3(-7.15, 3.0, -58.0), Vector3(0.3, 8.0, 28.0))
	lv.call("_invisible_wall", Vector3(-4.85, 3.0, -56.75), Vector3(0.3, 8.0, 25.5))
	lv.call("_invisible_wall", Vector3(-4.75, 3.0, -72.2), Vector3(5.0, 8.0, 0.3))
	lv.call("_invisible_wall", Vector3(-2.35, 3.0, -70.75), Vector3(0.3, 8.0, 3.2))
	# Plateau-Kanten (kein Absturz vom Hang)
	lv.call("_invisible_wall", Vector3(-20.2, 6.5, 86.0), Vector3(0.3, 3.0, 32.0))
	lv.call("_invisible_wall", Vector3(30.2, 6.5, 86.0), Vector3(0.3, 3.0, 32.0))
	# Ueber den Mauern (kein Ueberklettern): Suedmauer, Ostmauer, Bootshaus-Dach
	lv.call("_invisible_wall", Vector3(-6.7, 5.0, 30.0), Vector3(32.6, 5.0, 0.6))
	lv.call("_invisible_wall", Vector3(26.3, 5.0, 30.0), Vector3(15.8, 5.0, 0.6))
	lv.call("_invisible_wall", Vector3(34.0, 5.0, -7.0), Vector3(0.6, 5.0, 74.0))
	lv.call("_invisible_wall", Vector3(-27.5, 5.5, 28.0), Vector3(9.6, 5.0, 12.4))
