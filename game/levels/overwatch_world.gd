extends RefCounted
## Level 7 "Kaltes Auge" (overwatch): statische Welt des Stahlwerks Hennigsdorf im Morgennebel
## (06.06.2030, 05:20). Umgebung (HDRI-Himmel, tiefe warme Sonne vorne links, kuehles Fuelllicht,
## Volumetric Fog), Boden, Grenzen, Bodennebel, Ambiente-Ton und Aufruf der Bau-Module.
## Wird vom Level-Skript per preload eingebunden; alle Funktionen statisch.

const VfxEnv = preload("res://game/vfx/vfx_env.gd")
const Geo = preload("res://game/levels/level_geo.gd")
const Props = preload("res://game/levels/level_props.gd")
const RailProps = preload("res://game/levels/rail_props.gd")
const K = preload("res://game/levels/overwatch_world_kit.gd")
const Towers = preload("res://game/levels/overwatch_world_towers.gd")
const Furnace = preload("res://game/levels/overwatch_world_furnace.gd")
const Yard = preload("res://game/levels/overwatch_world_yard.gd")
const Far = preload("res://game/levels/overwatch_world_far.gd")

const HDRI := "res://assets/environment/rail/hdri/industrial_sunset_02_puresky_2k.hdr"
const SUN_AZ := 222.0          ## 180 = aus -Z; > 180 = nach links (-X), links vom Kuehlturm
const SUN_EL := 5.0

# ------------------------------------------------------------------ Umgebung

static func setup_environment(lv: Node3D) -> Dictionary:
	var env := VfxEnv.make_environment(0.006, 1.0)
	if ResourceLoader.exists(HDRI):
		var mat := env.sky.sky_material as PanoramaSkyMaterial
		mat.panorama = load(HDRI)
		mat.energy_multiplier = 0.8
	env.sky_rotation = Vector3(0.0, deg_to_rad(VfxEnv.SKY_YAW_OFFSET_DEG + (SUN_AZ - 200.0)), 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.6
	env.ambient_light_color = Color(0.5, 0.56, 0.66)
	env.ambient_light_energy = 1.1
	env.tonemap_exposure = 0.92
	# Tiefennebel: kuehler Dunst, Hoehennebel staut sich am Boden, warme Streuung zur Sonne
	env.fog_light_color = Color(0.6, 0.64, 0.72)
	env.fog_light_energy = 0.85
	env.fog_density = 0.00042
	env.fog_sun_scatter = 0.16
	env.fog_aerial_perspective = 0.3
	env.fog_sky_affect = 0.4
	env.fog_height = 8.0
	env.fog_height_density = 0.0032
	# Volumetrischer Nebel (Lichtschaechte, Gegenlicht)
	env.volumetric_fog_density = 0.0006
	env.volumetric_fog_albedo = Color(0.84, 0.86, 0.9)
	env.volumetric_fog_emission = Color(0.02, 0.024, 0.032)
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 220.0
	env.volumetric_fog_sky_affect = 0.35
	env.volumetric_fog_ambient_inject = 0.45
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	lv.add_child(we)
	# Tiefe, warme Sonne vorne links (knapp ueber dem Dunst)
	var sun := VfxEnv.make_sun()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.62, 0.38)
	sun.light_energy = 2.4
	sun.light_volumetric_fog_energy = 1.3
	sun.directional_shadow_max_distance = 200.0
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	lv.add_child(sun)
	# Kuehles blaugraues Fuelllicht (Himmel im Osten / von hinten oben)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.56, 0.63, 0.8)
	fill.light_energy = 0.45
	fill.light_indirect_energy = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.3, -0.55, -0.8).normalized(), Vector3.UP), Vector3.ZERO)
	lv.add_child(fill)
	VfxEnv.apply_render_quality(lv.get_viewport())
	return {"sun": sun, "env": env}

# ------------------------------------------------------------------ Aufbau

static func build(lv: Node3D, world: Node3D, covers: Array, rng: RandomNumberGenerator) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var pts: Dictionary = {}
	_ground(lv, world, rng)
	Towers.build(world, covers, rng, pts)
	Furnace.build(world, covers, rng, pts)
	Yard.build(world, covers, rng, pts)
	Far.build(world, covers, rng, pts)
	_boundaries(world)
	_mist(lv)
	_audio(lv)
	pts["extract_path"] = [
		Vector3(-44.65, 0.0, 27.6), Vector3(-44.65, 0.0, 30.5), Vector3(-30.0, 0.0, 30.5),
		Vector3(-30.0, 0.0, -20.0), Vector3(-30.0, 0.0, -60.0), Vector3(-30.0, 0.0, -89.0), Vector3(-30.0, 0.0, -92.0),
	]
	# Laufweg P1 -> Bandbruecke -> P2 (fuer den Bot), weicht den Kisten auf P2 aus
	var gp: Array = [Vector3(-2.0, 22.0, 10.1)]
	gp.append_array(pts["gantry"])
	gp.append_array([Vector3(-43.0, 22.0, 10.1), Vector3(-43.0, 22.0, 4.0), pts["p2_snipe"]])
	pts["gantry_path"] = gp
	# Patrouillen der Posten (je zwei Wegpunkte, frei begehbar, von P1 aus einsehbar)
	pts["yard_a"] = Vector3(-8.0, 0.0, -44.0)
	pts["yard_b"] = Vector3(8.0, 0.0, -52.0)
	pts["gap_a"] = Vector3(2.0, 0.0, -108.0)
	pts["gap_b"] = Vector3(30.0, 0.0, -108.0)
	pts["road_a"] = Vector3(-42.0, 0.0, -135.6)
	pts["road_b"] = Vector3(-12.0, 0.0, -135.6)
	pts["south_a"] = Vector3(32.0, 0.0, -151.4)
	pts["south_b"] = Vector3(56.0, 0.0, -151.4)
	# Eingreiftruppe: Deckungsplaetze beiderseits des Rueckwegs (x = -30)
	pts["qrf"] = [Vector3(-24.0, 0.0, -16.0), Vector3(-37.0, 0.0, -38.0), Vector3(-23.0, 0.0, -54.0), Vector3(-36.0, 0.0, -63.0)]
	print("[overwatch_world] build %d ms" % (Time.get_ticks_msec() - t0))
	return pts

static func _ground(lv: Node3D, world: Node3D, rng: RandomNumberGenerator) -> void:
	var body := Geo.static_body()
	body.name = "Ground"
	body.set_meta("no_fit", true)
	Geo.add_box_shape(body, Vector3(-20.0, -1.0, -90.0), Vector3(700.0, 2.0, 700.0))
	world.add_child(body)
	var k := RailProps.kit()
	# Weite Ebene (Schotter/Matsch), Hofflaeche (Beton), Spawn-Hof
	k.b("far", K.matte(K.pbr(K.RAIL_TEX + "gravel_road", Color(0.46, 0.43, 0.4), 0.08))).add(Vector3(0, -0.06, -150.0), Vector3(1000.0, 0.1, 1000.0))
	k.b("yard", K.gravel(Color(0.56, 0.53, 0.5))).add(Vector3(10.0, -0.02, -60.0), Vector3(240.0, 0.04, 150.0))
	k.b("pad", K.concrete_floor(Color(0.62, 0.6, 0.57))).add(Vector3(-2.0, -0.005, 28.0), Vector3(44.0, 0.01, 30.0))
	k.b("pad", K.concrete_floor(Color(0.6, 0.58, 0.55))).add(Vector3(-30.0, -0.005, -40.0), Vector3(10.0, 0.01, 140.0))
	k.b("mud", K.mud(Color(0.42, 0.38, 0.34))).add(Vector3(-60.0, -0.004, -10.0), Vector3(40.0, 0.01, 50.0))
	k.b("grass", K.grass()).add(Vector3(10.0, -0.01, -132.5), Vector3(400.0, 0.01, 7.0))
	k.b("grass", K.grass()).add(Vector3(10.0, -0.01, -150.5), Vector3(400.0, 0.01, 5.0))
	# Fahrspuren / Schotterwege im Hof
	for p: Array in [[Vector3(20.0, -0.003, -20.0), Vector3(8.0, 0.01, 90.0), 12.0], [Vector3(-10.0, -0.003, -90.0), Vector3(120.0, 0.01, 7.0), 0.0]]:
		k.b("track", K.gravel(Color(0.48, 0.45, 0.42))).add(p[0], p[1], K.yaw_b(float(p[2])))
	var n := Node3D.new()
	n.name = "GroundVisual"
	lv.add_child(n)
	K.flush(k, n, false, 0.0)
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Unsichtbare Bewegungs-Sperren am Spielfeldrand (Layer 16, wie level.gd _invisible_wall).
static func _boundaries(world: Node3D) -> void:
	var walls: Array = [
		[Vector3(-100.0, 10.0, -80.0), Vector3(1.0, 30.0, 260.0)],
		[Vector3(130.0, 10.0, -80.0), Vector3(1.0, 30.0, 260.0)],
		[Vector3(15.0, 10.0, 46.0), Vector3(232.0, 30.0, 1.0)],
		[Vector3(15.0, 10.0, -206.0), Vector3(232.0, 30.0, 1.0)],
	]
	for w: Array in walls:
		var b := Geo.static_body(w[0])
		b.name = "Boundary"
		b.collision_layer = 16
		b.set_meta("no_fit", true)
		Geo.add_box_shape(b, Vector3.ZERO, w[1])
		world.add_child(b)

## Bodennebel (Ellipsoid-FogVolumes) im Hof, ueber der Strasse und am Kuehlturm.
static func _mist(lv: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Mist"
	lv.add_child(root)
	var cool := Color(0.82, 0.85, 0.9)
	Props.fog_volume(root, Vector3(10.0, 0.0, -55.0), Vector3(220.0, 7.0, 130.0), 0.0022, cool)
	Props.fog_volume(root, Vector3(-60.0, 0.0, 10.0), Vector3(90.0, 9.0, 60.0), 0.008, cool)
	Props.fog_volume(root, Vector3(20.0, 0.0, -150.0), Vector3(420.0, 5.0, 46.0), 0.0014, cool)
	Props.fog_volume(root, Vector3(-120.0, 2.0, -230.0), Vector3(120.0, 14.0, 120.0), 0.005, cool)
	Props.fog_volume(root, Vector3(100.0, 2.0, -200.0), Vector3(160.0, 12.0, 90.0), 0.003, cool)
	Props.fog_volume(root, Vector3(0.0, 0.0, 30.0), Vector3(80.0, 4.0, 40.0), 0.005, cool)

static func _audio(lv: Node3D) -> void:
	_loop(lv, "res://assets/sfx/overwatch_amb_works.ogg", Vector3(-30.0, 12.0, -40.0), -6.0, 60.0)
	_loop(lv, "res://assets/sfx/overwatch_steam_loop.ogg", Vector3(-56.0, 40.0, 10.0), -4.0, 30.0)
	_loop(lv, "res://assets/sfx/overwatch_steam_loop.ogg", Vector3(-62.0, 20.0, -9.0), -10.0, 14.0)

static func _loop(lv: Node3D, path: String, pos: Vector3, db: float, unit: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var p := AudioStreamPlayer3D.new()
	p.name = "Amb"
	var stream := load(path) as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = db
	p.unit_size = unit
	p.max_distance = 400.0
	p.bus = "SFX"
	p.position = pos
	p.autoplay = true
	lv.add_child(p)
