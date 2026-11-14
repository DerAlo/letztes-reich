extends "res://game/levels/level.gd"
## Level 4 "Letzter Zug" (rail_yard): Gueterbahnhof Pskow, 02.04.2030, 19:20 -- goldene Stunde.
## Abschnitt 1 (z 0..-90): Gleisvorfeld, Gueterwagen als Deckung, Stellwerk rechts, Laderampen links.
## Abschnitt 2 (z -90..-190): Munitionszug auf Gleis x=-11. Set-Piece A: Kettenexplosion.
## Abschnitt 3 (z -190..-270): Lagerhallen und Kranbahn. Set-Piece B: Jets bomben, Portalkran faellt.
## Finale: Gegner ergeben sich/fliehen, Waffenstillstand per Funk, Leuchtkugeln, Levelende.

const RailProps = preload("res://game/levels/rail_props.gd")
const FarCity = preload("res://game/levels/far_city.gd")
const RailFx = preload("res://game/levels/rail_fx.gd")
const RailTrain = preload("res://game/levels/rail_train.gd")
const RailCrane = preload("res://game/levels/rail_crane.gd")
const LeafTrees = preload("res://game/levels/leaf_trees.gd")
const GroundCover = preload("res://game/levels/ground_cover.gd")

const JET_SCENE := "res://game/vehicles/jet_flyby.tscn"
const HDRI := "res://assets/environment/rail/hdri/industrial_sunset_02_puresky_2k.hdr"
const SUN_AZ := 200.0
const SUN_EL := 7.0
const TRAIN_X := -11.0
const TRAIN_FRONT := -94.0
const CRANE_POS := Vector3(18.0, 0.0, -235.0)

## Bot-Route (x, z). Gerade Linien sind frei begehbar (Ladestrasse x -3..3).
const ROUTE: Array = [
	Vector2(1.5, 5.0), Vector2(1.5, -15.0), Vector2(2.0, -35.0), Vector2(1.5, -55.0), Vector2(1.5, -75.0),
	Vector2(1.0, -95.0), Vector2(1.0, -115.0), Vector2(1.5, -135.0), Vector2(1.0, -155.0), Vector2(0.0, -175.0),
	Vector2(-1.0, -190.0), Vector2(-2.0, -205.0), Vector2(-2.0, -220.0), Vector2(-2.0, -235.0),
	Vector2(-2.0, -248.0), Vector2(-1.0, -260.0), Vector2(0.0, -267.0)]

var fx: Node3D
var train: Node3D
var crane: StaticBody3D
var _sun: DirectionalLight3D
var _a_done: bool = false
var _b_started: bool = false
var _b_time: float = -1.0
var _ending: bool = false
var _fleeing: Array[Dictionary] = []    ## {e, mode, target, t}
var _t: float = 0.0
const JUGGERNAUT_SCENE := "res://game/enemies/juggernaut.tscn"   ## auch fuers Vorwaermen (main.gd)
var _fps_log: bool = Game.arg("rail-fps", null) != null   ## --rail-fps: FPS-Protokoll fuer Messungen
var _fps_acc: float = 0.0
var _debug_god: bool = false             ## nur bei --rail-start (Aufnahmen): Spieler unverwundbar

func _init() -> void:
	level_name = "rail_yard"
	end_z = -270.0
	build_seed = 2004
	_wave_count = 4
	fog_density = 0.0028

# ------------------------------------------------------------------ Oeffentlich

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Letzter Zug"
	return info

## Set-Piece A: Rakete auf den markierten Kesselwagen (auch fuer Tests/Touren).
func trigger_setpiece() -> void:
	if _setpiece_done:
		return
	_setpiece_done = true
	setpiece_triggered.emit()
	_run_setpiece_a()

## Set-Piece B: Luftschlag + Kran (fuer Tests/Touren).
func trigger_airstrike() -> void:
	_run_setpiece_b()

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(fog_density, 1.0)
	if ResourceLoader.exists(HDRI):
		var mat := env.sky.sky_material as PanoramaSkyMaterial
		mat.panorama = load(HDRI)
		mat.energy_multiplier = 1.05
	env.sky_rotation = Vector3(0.0, deg_to_rad(VfxEnv.SKY_YAW_OFFSET_DEG), 0.0)
	env.ambient_light_energy = 1.1
	env.tonemap_exposure = 0.78
	env.tonemap_white = 8.0
	env.fog_light_color = Color(0.7, 0.55, 0.42)
	env.fog_light_energy = 0.75
	env.fog_density = 0.0011
	env.fog_sun_scatter = 0.05
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.85, 0.74, 0.6)
	env.volumetric_fog_emission = Color(0.012, 0.008, 0.005)
	# Geringe Vorwaertsstreuung + kuerzere Froxel-Tiefe: bei 0.3/160 m leckte die tiefe Gegenlicht-Sonne
	# als roter Fleck durch Hallenwaende und Wagen (grobe Froxel ueber der Schattenkante)
	env.volumetric_fog_anisotropy = 0.12
	env.volumetric_fog_length = 100.0
	env.volumetric_fog_sky_affect = 0.2
	# Glow nur fuer echte Lichtquellen (Feuer, Muendungsfeuer), nicht fuer den Dunst
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 2.2
	env.adjustment_saturation = 0.95
	env.adjustment_contrast = 1.16
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	# Belichtungsanpassung wie Auge/Kamera: im Freien wie bisher (Belichtung ~0.78), vor Schattenseiten von
	# Wagen und in den Hallen bis ~3,5x heller (vorher fast schwarze Bilder beim Blick auf Wagenwaende)
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = true
	ca.auto_exposure_scale = 0.15
	ca.auto_exposure_min_sensitivity = 35.0
	ca.auto_exposure_max_sensitivity = 125.0
	ca.auto_exposure_speed = 0.9
	we.camera_attributes = ca
	add_child(we)
	# Tiefstehende Sonne voraus (Gegenlicht), lange Schatten
	_sun = VfxEnv.make_sun()
	_sun.light_color = Color(1.0, 0.6, 0.34)
	_sun.light_energy = 2.9
	_sun.light_volumetric_fog_energy = 0.3
	# Harte Schatten: PCSS-Weichschatten liess die 7-Grad-Sonne als orange Pfuetze/Streifen durch duenne Hallenwaende lecken.
	_sun.light_angular_distance = 0.0
	_sun.directional_shadow_max_distance = 180.0
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	_sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	add_child(_sun)
	# Fuelllicht von hinten (Himmel im Osten): Gegner bleiben im Gegenlicht erkennbar
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.62, 0.68, 0.85)
	fill.light_energy = 0.42
	fill.light_indirect_energy = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.transform = Transform3D(Basis.looking_at(Vector3(0.25, -0.45, -1.0).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(fill)
	VfxEnv.apply_render_quality(get_viewport())

# ------------------------------------------------------------------ Boden

func _build_ground() -> void:
	var body := Geo.static_body()
	var gmat := RailProps.matte("gravel_road", Color(0.72, 0.66, 0.6), 0.22)
	var c := Vector3(0, -1.0, -140.0)
	var s := Vector3(140.0, 2.0, 340.0)
	body.add_child(Geo.box_mesh_node(s, gmat, c))
	Geo.add_box_shape(body, c, s)
	world.add_child(body)
	# Ladestrasse (Beton) in der Mitte
	var road := Geo.box_mesh_node(Vector3(7.0, 0.05, 300.0), RailProps.mat("damaged_concrete_floor_02", Color(0.78, 0.74, 0.7), 0.3), Vector3(0, 0.025, -130.0))
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	var far := Geo.box_mesh_node(Vector3(1200.0, 0.2, 1200.0), RailProps.matte("gravel_road", Color(0.5, 0.45, 0.4), 0.1), Vector3(0, -0.15, -300.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	for sx: float in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 30.0, 6.0, -135.0), Vector3(1.0, 14.0, 320.0))
	_invisible_wall(Vector3(0, 6.0, 14.0), Vector3(62.0, 14.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, -290.0), Vector3(62.0, 14.0, 1.0))

# ------------------------------------------------------------------ Gleisfeld

func _build_street() -> void:
	var k := RailProps.kit()
	var cat_body := Geo.static_body()
	# Gleise: [x, z0, z1]
	var tracks: Array = [[-21.0, -50.0, -185.0], [-16.0, 20.0, -185.0], [-11.0, 20.0, -200.0], [-6.0, 20.0, -200.0],
		[7.0, 20.0, -205.0], [12.0, 20.0, -205.0], [17.0, 20.0, -150.0]]
	for t: Array in tracks:
		RailProps.track(k, t[0], t[1], t[2], rng)
	# Kranbahn-Schienen
	for cx: float in [CRANE_POS.x - 10.0, CRANE_POS.x + 10.0]:
		RailProps.track(k, cx, -205.0, -268.0, rng)
	for t: Array in tracks:
		if float(t[2]) > -240.0 and absf(float(t[0])) > 8.0:   # nahe der Route keine Prellboecke (Bot-Hindernis)
			RailProps.buffer_stop(world, t[0], float(t[2]) + 1.0, 1.0, covers)
	# Oberleitung ueber dem linken Gleisfeld + rechts
	var z := 10.0
	while z > -185.0:
		RailProps.catenary_portal(k, cat_body, -24.0, -3.8, z)
		RailProps.catenary_portal(k, cat_body, 4.6, 19.5, z - 6.0)
		z -= 42.0
	RailProps.catenary_wires(k, [-16.0, -11.0, -6.0], 10.0, -178.0)
	RailProps.catenary_wires(k, [7.0, 12.0, 17.0], 4.0, -172.0)
	# Flutlichtmasten
	for p: Vector3 in [Vector3(-26.0, 0, -20.0), Vector3(25.0, 0, -100.0), Vector3(-26.0, 0, -150.0), Vector3(4.2, 0, -190.0)]:
		RailProps.flood_mast(k, cat_body, p)
	k.flush(world)
	world.add_child(cat_body)
	_build_static_wagons()
	# Laderampen links
	RailProps.loading_ramp(world, Vector3(-21.5, 0, -28.0), Vector3(5.0, 1.25, 34.0), covers)
	# Stellwerk rechts (Front nach -X)
	RailProps.signal_box(world, Vector3(24.0, 0, -60.0), covers)

func _build_static_wagons() -> void:
	var wr := RandomNumberGenerator.new()
	wr.seed = 77
	var rust := Color(0.42, 0.2, 0.13)
	var brown := Color(0.36, 0.24, 0.17)
	var green := Color(0.22, 0.28, 0.2)
	var grey := Color(0.3, 0.29, 0.27)
	var tank := Color(0.14, 0.14, 0.13)
	var blue := Color(0.2, 0.28, 0.36)
	# [kind, x, z, color, extra]
	var list: Array = [
		# Abschnitt 1
		["boxcar", -6.0, -24.0, rust, 0.0], ["gondola", -6.0, -60.0, grey, null],
		["flat", 7.0, -16.0, blue, "container"], ["tank", 7.0, -46.0, tank, false], ["boxcar", 7.0, -80.0, brown, 1.6],
		["boxcar", -16.0, -8.0, brown, 0.0], ["boxcar", -16.0, -22.1, rust, 0.0], ["gondola", -16.0, -36.0, grey, null], ["tank", -16.0, -72.0, tank, false],
		["gondola", 12.0, -32.0, grey, null], ["boxcar", 12.0, -64.0, green, 0.0], ["flat", 12.0, -96.0, grey, "crates"],
		["flat", 17.0, -12.0, grey, "crates"], ["boxcar", 17.0, -26.0, rust, 0.8], ["tank", 17.0, -118.0, tank, false],
		["gondola", -11.0, -30.0, grey, null], ["boxcar", -11.0, -58.0, brown, 0.0],
		# Abschnitt 2 (rechts vom Zug)
		["tank", 7.0, -112.0, tank, false], ["boxcar", 7.0, -142.0, rust, 1.2], ["flat", 7.0, -172.0, grey, "container"],
		["boxcar", 12.0, -128.0, brown, 0.0], ["gondola", 12.0, -160.0, grey, null], ["boxcar", 12.0, -190.0, green, 0.0],
		["boxcar", -21.0, -64.0, rust, 0.0],
	]
	for w: Array in list:
		RailProps.static_wagon(world, w[0], Vector3(w[1], 0, w[2]), 0.0, wr, w[3], covers, w[4])

# ------------------------------------------------------------------ Requisiten

func _build_props() -> void:
	var pr := RandomNumberGenerator.new()
	pr.seed = 515
	# Kistenstapel / Munitionskisten (Deckung neben der Ladestrasse)
	for p: Vector3 in [Vector3(-3.6, 0, -12.0), Vector3(4.2, 0, -30.0), Vector3(-3.8, 0, -47.0), Vector3(4.4, 0, -66.0),
			Vector3(-3.6, 0, -86.0), Vector3(4.3, 0, -104.0), Vector3(4.2, 0, -157.0), Vector3(-4.0, 0, -168.0),
			Vector3(-4.5, 0, -212.0), Vector3(3.6, 0, -224.0)]:
		var yaw := pr.randf_range(-20, 20)
		# rechte Seite: laengs gedreht und naeher an Gleis 7 -> keine Tasche zwischen Kisten und Wagen
		if p.x > 0.0 and p.z > -200.0:
			yaw = 90.0 + yaw * 0.3
			p.x = 5.05
		RailProps.crate_stack(world, p, yaw, pr, covers)
	# Kisten auf der Laderampe
	for i in 5:
		RailProps.crate_stack(world, Vector3(-21.5 + pr.randf_range(-1.2, 1.2), 1.25, -16.0 - i * 6.0), pr.randf_range(0, 180), pr, [])
	# Fasser, Kanister, Reifen (ohne Kollision, Optik)
	for i in 26:
		var x := pr.randf_range(3.6, 5.2) * (1.0 if i % 2 == 0 else -1.0)
		var zz := pr.randf_range(-5.0, -260.0)
		var names: Array = ["barrel_03", "metal_jerrycan_green", "old_tyre", "ammo_box"]
		var nm: String = names[pr.randi() % names.size()]
		RailProps.place(world, nm, Vector3(x, 0.0, zz), pr.randf_range(0, 360), 1.0)
	# Barrieren entlang der Strasse
	RailProps.barrier_row(world, Vector3(4.0, 0, -36.5), Vector3(5.8, 0, -40.0), covers)
	RailProps.barrier_row(world, Vector3(-4.0, 0, -118.0), Vector3(-5.0, 0, -123.0), covers)
	RailProps.barrier_row(world, Vector3(4.0, 0, -180.0), Vector3(4.5, 0, -186.0), covers)
	# LKW-Wracks
	Props.vehicle(world, Vector3(-25.5, 0, -52.0), 6.0, "truck", Color(0.3, 0.33, 0.24), true, false, covers)
	Props.vehicle(world, Vector3(22.0, 0, -86.0), 172.0, "truck", Color(0.3, 0.33, 0.24), false, false, covers)
	Props.vehicle(world, Vector3(-10.5, 0, -194.0), 70.0, "van", Color(0.5, 0.5, 0.48), true, false, covers)
	# Gras, Buesche zwischen den Gleisen (MultiMesh)
	var grass: Array = []
	var shrubs: Array = []
	for i in 900:
		var gx := pr.randf_range(-29.0, 29.0)
		var gz := pr.randf_range(10.0, -280.0)
		if absf(gx) < 3.6:
			continue
		var on_track := false
		for tx: float in [-21.0, -16.0, -11.0, -6.0, 7.0, 12.0, 17.0]:
			if absf(gx - tx) < 1.6:
				on_track = true
		if on_track and pr.randf() < 0.75:
			continue
		var sc := pr.randf_range(0.7, 1.4)
		grass.append(Transform3D(Basis(Vector3.UP, pr.randf() * TAU).scaled(Vector3(sc, sc * pr.randf_range(0.8, 1.3), sc)), Vector3(gx, 0.0, gz)))
		if i % 9 == 0:
			var ss := pr.randf_range(0.6, 1.2)
			shrubs.append(Transform3D(Basis(Vector3.UP, pr.randf() * TAU).scaled(Vector3.ONE * ss), Vector3(gx, 0.0, gz)))
	# Gras jetzt als zellweise MultiMeshes mit Distanz-Fade (GroundCover), Buesche wie bisher
	GroundCover.scatter(self, "grass01", grass, {"fade": Vector2(38, 55), "max_tris": 2600, "seed": 11, "mult": 2.2})
	RailProps.scatter(self, "shrub_02", shrubs, true)
	_build_ground_cover()

## Bodenbewuchs (Vegetationspass): Unkraut im Schotter neben den Schienen, Grasflecken und
## Brennnesseln an den Raendern, vereinzelt Loewenzahn, kleine Steine. Eigener Zufallsstrom.
func _build_ground_cover() -> void:
	var gr := RandomNumberGenerator.new()
	gr.seed = 9093
	var patch := FastNoiseLite.new()
	patch.seed = 77
	patch.frequency = 0.09
	var gc := Node3D.new()
	gc.name = "GroundCover"
	add_child(gc)
	var rails: Array = [-21.0, -16.0, -11.0, -6.0, 7.0, 12.0, 17.0]
	var track_d := func(x: float) -> float:
		var best := INF
		for tx: float in rails:
			best = minf(best, absf(x - tx))
		return best
	# Unkraut/Gras im Schotter: zwischen den Gleisen und am Schwellenende, nicht auf der Ladestrasse
	var ballast := func(q: Vector3) -> bool:
		if absf(q.x) < 3.8:
			return false
		var d: float = track_d.call(q.x)
		if d < 0.9:
			return false   # zwischen den Schienen kaum Bewuchs
		return patch.get_noise_2d(q.x, q.z) > 0.0
	# dichte Grundschicht: schlanke, duenne Halmbueschel (wenig Dreiecke), kurze Sichtweite
	var g1 := GroundCover.points(gr, 30000, -29.5, 29.5, -285.0, 12.0, Vector2(0.7, 1.3), ballast)
	GroundCover.scatter(gc, "grass01", g1, {"only": "tall", "mult": 2.4, "fade": Vector2(22, 32), "seed": 17})
	var g2 := GroundCover.points(gr, 7000, -29.5, 29.5, -285.0, 12.0, Vector2(0.7, 1.35), ballast)
	GroundCover.scatter(gc, "grass02", g2, {"mult": 2.2, "fade": Vector2(30, 44), "seed": 12})
	var w := GroundCover.points(gr, 1800, -29.5, 29.5, -285.0, 12.0, Vector2(0.7, 1.25), ballast)
	GroundCover.scatter(gc, "weed", w, {"mult": 2.0, "fade": Vector2(26, 38), "seed": 13})
	# Raender (Zaun/Mauer x ~ +-24..30): Brennnesseln und hoeheres Gras
	var edge := func(q: Vector3) -> bool:
		return absf(q.x) > 23.5 and patch.get_noise_2d(q.x * 0.7, q.z * 0.7) > -0.25
	var ne := GroundCover.points(gr, 900, -29.8, 29.8, -285.0, 12.0, Vector2(0.75, 1.3), edge)
	GroundCover.scatter(gc, "nettle", ne, {"mult": 4.5, "fade": Vector2(30, 45), "seed": 14, "max_tris": 8500})
	var dl := GroundCover.points(gr, 260, -29.5, 29.5, -285.0, 12.0, Vector2(0.8, 1.2), ballast)
	GroundCover.scatter(gc, "dandelion", dl, {"mult": 1.8, "fade": Vector2(22, 32), "seed": 15, "max_tris": 4000})
	# kleine bemooste Steine im Schotter
	var st := GroundCover.points(gr, 160, -29.5, 29.5, -285.0, 12.0, Vector2(0.12, 0.28), ballast, -0.03, 15.0)
	GroundCover.scatter(gc, "rocks", st, {"fade": Vector2(28, 40), "seed": 16, "max_tris": 9000})

# ------------------------------------------------------------------ Marker, Trigger

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(1.5, 0.05, 8.0), "player_spawn")
	ps.name = "PlayerSpawn"
	# Gegner: [typ, welle, x, y, z]
	var spawns: Array = [
		# Welle 0: Gleisvorfeld + Stellwerk
		["rifleman", 0, -3.5, 0.05, -44.0], ["rifleman", 0, 9.5, 0.05, -40.0], ["rifleman", 0, -8.5, 0.05, -52.0],
		["rifleman", 0, 4.5, 0.05, -62.0], ["marksman", 0, 22.5, 4.5, -60.0], ["rifleman", 0, -13.5, 0.05, -66.0],
		["rifleman", 0, 11.0, 0.05, -50.0], ["rifleman", 0, -4.0, 0.05, -68.0], ["rifleman", 0, -13.0, 0.05, -50.0],
		# Welle 1: am Munitionszug
		["rifleman", 1, -7.5, 0.05, -128.0], ["rifleman", 1, -7.8, 0.05, -140.0], ["assault", 1, 4.8, 0.05, -110.0],
		["rifleman", 1, 9.5, 0.05, -126.0], ["rifleman", 1, 4.5, 0.05, -138.0], ["drone", 1, 0.0, 7.0, -125.0],
		["rifleman", 1, 13.0, 0.05, -116.0], ["assault", 1, -2.0, 0.05, -119.0], ["rifleman", 1, 13.0, 0.05, -137.0],
		# Welle 2: Zugende / Hallenvorfeld
		["rifleman", 2, 4.5, 0.05, -172.0], ["officer", 2, -5.0, 0.05, -182.0], ["rifleman", 2, 9.5, 0.05, -180.0],
		["heavy", 2, -1.0, 0.05, -198.0], ["rifleman", 2, -9.5, 0.05, -205.0],
		["rifleman", 2, -14.0, 0.05, -183.0], ["rifleman", 2, 13.0, 0.05, -168.0], ["rifleman", 2, 13.0, 0.05, -201.0],
		# Welle 3: letzte Stellung unter dem Kran
		["rifleman", 3, -8.0, 0.05, -250.0], ["rifleman", 3, 5.5, 0.05, -253.0], ["assault", 3, 2.5, 0.05, -244.0],
		["rifleman", 3, -11.0, 0.05, -240.0], ["heavy", 3, 9.0, 0.05, -246.0], ["rifleman", 3, 13.0, 0.05, -238.0],
		["drone", 3, -4.0, 8.0, -236.0], ["drone", 3, 6.0, 9.0, -242.0],
		["rifleman", 3, -14.0, 0.05, -244.0], ["rifleman", 3, 12.0, 0.05, -252.0],
		# gepanzerte Soldaten
		["armored", 1, 2.0, 0.05, -132.0], ["armored", 2, 6.0, 0.05, -190.0], ["armored", 3, -4.0, 0.05, -247.0],
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, Vector3(s[2], s[3], s[4]), "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for c in covers:
		var v: Vector3 = c
		if absf(v.x) > 28.0 or v.z > 0.0 or v.z < -285.0:
			continue
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	for i in ROUTE.size():
		var r: Vector2 = ROUTE[i]
		var w := Geo.marker(m, Vector3(r.x, 0.05, r.y), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	var strip := Vector3(60, 6, 1.5)
	_trigger("TriggerTwist", Vector3(0, 3, -40.0), strip, _radio_twist)
	_trigger("TriggerWave1", Vector3(0, 3, -75.0), strip, func() -> void:
		_spawn_wave(1)
		_radio_opt("Hauptmann Weber", "Kontakt am Zug! Die Lok steht unter Dampf – die wollen raus.", 4.0, {"priority": 1, "max_age": 3.0}))
	_trigger("TriggerBriefTank", Vector3(0, 3, -98.0), strip, _radio_tank)
	_trigger("TriggerSetpieceA", Vector3(0, 3, -118.0), strip, trigger_setpiece)
	_trigger("TriggerWave2", Vector3(0, 3, -150.0), strip, func() -> void: _spawn_wave(2))
	_trigger("TriggerWave3", Vector3(0, 3, -194.0), strip, func() -> void:
		_spawn_wave(3)
		_objective("Letzte Stellung ausschalten")
		_radio_opt("Lena Aksoy", "Letzte Stellung unter dem Kran. MG und Panzerabwehr.", 4.0, {"max_age": 3.0}))
	_trigger("TriggerSetpieceB", Vector3(0, 3, -205.0), strip, _run_setpiece_b)
	_trigger("TriggerEnding", Vector3(0, 3, -254.0), strip, _start_ending)
	_trigger("Checkpoint1", Vector3(0, 3, -85.0), strip, func() -> void: _checkpoint("cp_train"))
	_trigger("Checkpoint2", Vector3(0, 3, -185.0), strip, func() -> void: _checkpoint("cp_halls"))
	var area := _trigger("LevelEnd", Vector3(0.0, 2.0, -267.0), Vector3(16, 4, 3), _start_ending, false)
	area.add_to_group("level_end")

# ------------------------------------------------------------------ Set-Piece-Geometrie

func _build_set_piece_geometry() -> void:
	train = RailTrain.new()
	train.name = "AmmoTrain"
	add_child(train)
	train.call("build", world, TRAIN_X, TRAIN_FRONT)
	train.connect("detonated", _on_train_detonated)
	# Portalkran ueber der Kranbahn
	crane = RailCrane.new()
	crane.name = "GantryCrane"
	crane.position = CRANE_POS
	world.add_child(crane)
	crane.connect("toppled", func() -> void: _b_time = _t)
	Events.explosion.connect(_on_explosion)
	# Lagerhallen links + rechts hinten
	var wr := RandomNumberGenerator.new()
	wr.seed = 909
	RailProps.warehouse(world, Vector3(-24.0, 0, -228.0), Vector3(12.0, 9.0, 44.0), 1.0, [[-10.0, 6.0], [9.0, 6.0]], wr)
	RailProps.warehouse(world, Vector3(25.0, 0, -186.0), Vector3(10.0, 8.0, 24.0), -1.0, [[0.0, 6.0]], wr)
	# Container unter und neben dem Kran
	var cm1 := RailProps.mat("container_side", Color(0.6, 0.28, 0.18), 0.25, 1.0, 0.0)
	var cm2 := RailProps.mat("container_side", Color(0.25, 0.4, 0.55), 0.25, 1.0, 0.0)
	var cm3 := RailProps.mat("container_side", Color(0.35, 0.42, 0.28), 0.25, 1.0, 0.0)
	var mats: Array = [cm1, cm2, cm3]
	var cont: Array = [[12.0, -226.0, 0, 0.0], [12.0, -226.0, 1, 0.0], [16.5, -224.0, 0, 90.0], [22.0, -232.0, 0, 0.0],
		[22.0, -232.0, 1, 4.0], [25.0, -244.0, 0, 0.0], [14.0, -258.0, 0, 90.0], [-14.0, -262.0, 0, 90.0], [-9.0, -213.0, 0, 0.0]]
	for i in cont.size():
		var c: Array = cont[i]
		var b := Geo.static_body(Vector3(c[0], int(c[2]) * 2.6, c[1]), c[3])
		var sz := Vector3(2.44, 2.6, 6.06)
		b.add_child(Geo.box_mesh_node(sz, mats[i % 3], Vector3(0, 1.3, 0)))
		Geo.add_box_shape(b, Vector3(0, 1.3, 0), sz)
		world.add_child(b)
		if int(c[2]) == 0:
			covers.append(Vector3(c[0] - 2.2, 0, c[1]))
			covers.append(Vector3(c[0], 0, c[1] + 4.0))
	# Letzte Stellung: Sandsaecke + Barrieren (Luecke bei x -3..+1 fuer die Route)
	RailProps.sandbag_arc(world, Vector3(-8.0, 0, -250.0), 2.6, -60.0, 60.0, rng, covers)
	RailProps.sandbag_arc(world, Vector3(6.0, 0, -253.0), 2.6, -60.0, 60.0, rng, covers)
	RailProps.sandbag_arc(world, Vector3(11.5, 0, -240.0), 2.2, -70.0, 50.0, rng, covers)
	RailProps.barrier_row(world, Vector3(-14.0, 0, -243.5), Vector3(-5.0, 0, -243.5), covers)
	RailProps.barrier_row(world, Vector3(2.0, 0, -247.0), Vector3(8.5, 0, -247.0), covers)
	for i in 4:
		RailProps.crate_stack(world, Vector3(-11.0 + i * 1.8, 0, -255.5), 0.0, rng, [])

# ------------------------------------------------------------------ Skyline

func _build_skyline() -> void:
	var sky := Node3D.new()
	sky.name = "Skyline"
	add_child(sky)
	var fb := FarCity.Builder.new()
	var sr := RandomNumberGenerator.new()
	sr.seed = 66
	# Plattenbauten, Werkhallen und alte Backsteinhaeuser am Horizont (voraus); RNG-Folge wie frueher
	for i in 22:
		var x := sr.randf_range(-260.0, 260.0)
		var z := sr.randf_range(-430.0, -560.0)
		var h := sr.randf_range(14.0, 42.0)
		var w := sr.randf_range(18.0, 60.0)
		var d := sr.randf_range(12.0, 18.0)
		var c := Vector3(x, 0.0, z)
		var sv := fposmod(float(i) * 0.6180339, 1.0)
		if h > 27.0:
			fb.block(c, Vector3(w, 2.8 * roundf(h / 2.8), d), "platte", "panel", Color(0.86, 0.84, 0.8), {"seed": sv, "damage": 0.2, "lit": 1.0})
		elif w > 38.0:
			fb.block(c, Vector3(w, minf(h, 18.0), d + 10.0), "hall", "factory" if i % 2 == 0 else "brick_old", Color(0.86, 0.8, 0.74), {"seed": sv, "damage": 0.3, "lit": 0.4, "roof_col": Color(0.24, 0.22, 0.21)})
		elif i % 3 == 0:
			fb.block(c, Vector3(w, 3.7 * roundf(h / 3.7), d), "office", "concrete_old", Color(0.84, 0.82, 0.78), {"seed": sv, "damage": 0.25, "lit": 1.0})
		else:
			fb.block(c, Vector3(w, 4.4 + 3.6 * roundf((h - 4.4) / 3.6), d), "altbau", "brick" if i % 2 == 0 else "plaster_old", Color(0.86, 0.78, 0.7), {"seed": sv, "damage": 0.35, "lit": 1.0, "roof_col": Color(0.3, 0.22, 0.18)})
	# Kraftwerksschlote: Beton, rot-weiss geringelt, verrusster Kopf, Kesselhaus am Fuss
	for p: Vector2 in [Vector2(-140.0, -480.0), Vector2(-120.0, -500.0), Vector2(170.0, -460.0)]:
		var base := Vector3(p.x, 0.0, p.y)
		var sv2 := fposmod(p.x * 0.013, 1.0)
		fb.tube("concrete_old", base, 3.6, 2.3, 90.0, Color(0.82, 0.8, 0.76), sv2, 16)
		for bnd in 4:
			var t0 := 0.5 + float(bnd) * 0.12
			var rr := lerpf(3.6, 2.3, t0) + 0.06
			fb.tube("concrete_old", base + Vector3.UP * (90.0 * t0), rr, rr - 0.1, 5.5, Color(0.62, 0.16, 0.12) if bnd % 2 == 0 else Color(0.9, 0.88, 0.84), sv2, 16)
		fb.tube("concrete_old", base + Vector3.UP * 84.0, 2.45, 2.35, 6.4, Color(0.18, 0.16, 0.15), sv2, 16, Color(0.04, 0.04, 0.04))
	fb.block(Vector3(-130.0, 0.0, -470.0), Vector3(46.0, 24.0, 22.0), "hall", "brick_old", Color(0.8, 0.72, 0.66), {"seed": 0.77, "lit": 0.6, "roof_col": Color(0.22, 0.2, 0.2)})
	# Pskower Kreml: Kalksteinmauer mit Holzdach, Rundtuerme mit Zeltdach, Dreifaltigkeitskathedrale
	var kx := 60.0
	var kz := -620.0
	var lime := Color(0.86, 0.84, 0.78)
	var shingle := Color(0.32, 0.24, 0.17)
	fb.block(Vector3(kx, 0.0, kz), Vector3(160.0, 13.0, 8.0), "plain", "plaster_old", lime, {"seed": 0.31, "roof": "gable", "roof_col": shingle, "roof_h": 2.6, "cornice": false})
	for t: float in [-70.0, -20.0, 40.0, 80.0]:
		var tb := Vector3(kx + t, 0.0, kz)
		fb.tube("plaster_old", tb, 6.6, 6.0, 22.0, lime, 0.4 + t * 0.001, 20)
		fb.tube("plaster_old", tb + Vector3.UP * 22.0, 7.4, 0.25, 11.0, shingle, 0.5, 20)
	var cc := Vector3(kx + 10.0, 0.0, kz - 20.0)
	fb.block(cc, Vector3(28.0, 30.0, 26.0), "plain", "plaster", Color(0.94, 0.92, 0.88), {"seed": 0.12, "roof_col": Color(0.3, 0.36, 0.32), "parapet": 0.0, "bits": false, "cornice": true})
	fb.block(cc + Vector3(0, 30.0, 0), Vector3(20.0, 6.0, 18.0), "plain", "plaster", Color(0.94, 0.92, 0.88), {"seed": 0.13, "roof_col": Color(0.3, 0.36, 0.32), "parapet": 0.0, "bits": false})
	for q: Vector3 in [Vector3(0, 36.0, 0), Vector3(-8.0, 36.0, 8.0), Vector3(8.0, 36.0, 8.0), Vector3(-8.0, 36.0, -8.0), Vector3(8.0, 36.0, -8.0)]:
		var main := q.x == 0.0
		fb.tube("plaster", cc + q, 4.0 if main else 2.6, 3.8 if main else 2.5, 26.0 if main else 9.0, Color(0.94, 0.92, 0.88), 0.2, 16)
	FarCity.build(fb, sky, false, {"lit_ratio": 0.05, "sky_tint": Color(0.86, 0.62, 0.46), "reflect_amt": 0.3, "emission_energy": 1.6})
	var dome_mat := StandardMaterial3D.new()
	dome_mat.albedo_color = Color(0.83, 0.62, 0.3)
	dome_mat.metallic = 0.9
	dome_mat.roughness = 0.28
	for d: Vector3 in [Vector3(kx + 10.0, 62.0, kz - 20.0), Vector3(kx + 2.0, 45.0, kz - 12.0), Vector3(kx + 18.0, 45.0, kz - 12.0),
			Vector3(kx + 2.0, 45.0, kz - 28.0), Vector3(kx + 18.0, 45.0, kz - 28.0)]:
		var big := d.y > 60.0
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 5.0 if big else 3.2
		sm.height = sm.radius * 2.3
		sm.radial_segments = 24
		sm.rings = 12
		mi.mesh = sm
		mi.material_override = dome_mat
		mi.position = d + Vector3.UP * sm.radius * 0.7
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.add_child(mi)
		# Zwiebelspitze + Kreuz
		var tip := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.05
		cm.bottom_radius = sm.radius * 0.45
		cm.height = sm.radius * 1.1
		cm.radial_segments = 12
		tip.mesh = cm
		tip.material_override = dome_mat
		tip.position = mi.position + Vector3.UP * (sm.height * 0.5 + cm.height * 0.4)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.add_child(tip)
		var cr := Geo.box_mesh_node(Vector3(0.25, sm.radius * 0.9, 0.25), dome_mat, tip.position + Vector3.UP * (cm.height * 0.5 + sm.radius * 0.4))
		cr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.add_child(cr)
		var cb := Geo.box_mesh_node(Vector3(sm.radius * 0.5, 0.2, 0.2), dome_mat, cr.position + Vector3.UP * sm.radius * 0.18)
		cb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky.add_child(cb)
	# Baumreihen links/rechts (hinter den Grenzen)
	# (belaubte Laubbaeume aus leaf_trees.gd statt Kugelkronen; Stammkollision wie bisher keine)
	var trees: Array = []
	for side: float in [-1.0, 1.0]:
		var z := 30.0
		while z > -360.0:
			var x := side * sr.randf_range(48.0, 75.0)
			trees.append([Vector3(x, 0.0, z), sr.randf_range(0.72, 1.15)])
			z -= sr.randf_range(6.0, 11.0)
	LeafTrees.plant(sky, trees, sr, {"autumn": 0.3, "shadows": true})

# ------------------------------------------------------------------ Atmosphaere

func _build_atmosphere() -> void:
	if str(Game.arg("shots", "")) != "":   # Debug-Aufnahmen mit festen Kameras (villa_shots.gd)
		add_child(load("res://game/levels/tools/villa_shots.gd").new())
	fx = RailFx.new()
	fx.name = "RailFx"
	add_child(fx)
	if train != null:
		train.set("fx", fx)
	# warmer Bodendunst (Gegenlicht-Streuung) ueber dem Gleisfeld
	for i in 6:
		Props.fog_volume(self, Vector3(rng.randf_range(-18.0, 18.0), 1.0, -30.0 - i * 42.0), Vector3(30.0, 3.0, 40.0), 0.004, Color(0.9, 0.78, 0.64))
	# entfernte Brandsaeulen (Front Richtung Stadt), ohne Licht
	Props.fire(self, Vector3(-90.0, 0.0, -360.0), 3.0, false, 3.5)
	Props.fire(self, Vector3(130.0, 0.0, -420.0), 3.5, false, 3.8)
	# ein brennender Wagen im Vorfeld (Stimmung, ein Licht)
	Props.fire(self, Vector3(-16.0, 1.4, -72.0), 1.2, true, 1.2, 4.0)
	# VFX-Pool vorwaermen (keine Ruckler bei der Kettenexplosion)
	var guard := 0
	while VFX.get("_expl_all").size() < VFX.MAX_EXPLOSIONS and guard < 8:
		VFX.call("_make_explosion")
		guard += 1
	get_tree().create_timer(1.5).timeout.connect(_radio_intro)
	# Debug/Aufnahme: --rail-start=a|b|end setzt den Spieler vor das jeweilige Set-Piece
	var start := str(Game.arg("rail-start", ""))
	if start != "":
		get_tree().create_timer(0.6).timeout.connect(func() -> void: _debug_start(start))

func _debug_start(which: String) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	var pos := {"a": Vector3(1.5, 0.1, -80.0), "b": Vector3(-2.0, 0.1, -198.0), "end": Vector3(-2.0, 0.1, -232.0)}
	pl.global_position = pos.get(which, pl.global_position)
	print("[rail_yard] debug start " + which)
	_debug_god = true
	if which == "a":
		_spawn_wave(1)
		_later(1.0, trigger_setpiece)
	elif which == "b":
		_later(0.8, _run_setpiece_b)
	elif which == "end":
		_b_started = true
		_later(0.5, _start_ending)

# ------------------------------------------------------------------ Navigation

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16   # world + move_block (= alles, woran Player/Gegner haengen)
	nm.filter_baking_aabb = AABB(Vector3(-30.0, -2.0, -290.0), Vector3(60.0, 16.0, 304.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

func _start_artillery() -> void:
	pass   # kein Sperrfeuer: der Krieg endet heute

# ------------------------------------------------------------------ Story

func _radio(speaker: String, text: String, dur: float) -> void:
	Events.story_radio.emit(speaker, text, dur)

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key, siehe story_ui.gd say()).
## Zeilen im selben Frame bilden ein Gespraech: jede kommt direkt nach ihrer Vorgaengerin.
func _radio_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

## Restdauer laufender + wartender Funkzeilen.
func _radio_busy() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return 0.0

## f ausfuehren, sobald der Funk frei ist (hoechstens max_wait s warten).
func _when_radio_free(f: Callable, max_wait: float = 6.0) -> void:
	if _radio_busy() <= 0.3 or max_wait <= 0.0:
		f.call()
		return
	_later(0.25, _when_radio_free.bind(f, max_wait - 0.25))

var _last_objective: String = ""

func _objective(text: String) -> void:
	# leeres Ziel nur senden, wenn eins angezeigt wird (StoryUI startet sonst einen leeren Tween)
	if text == _last_objective:
		return
	_last_objective = text
	Events.story_objective.emit(text)

func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)

func _radio_intro() -> void:
	_radio("Hauptmann Weber", "Güterbahnhof Pskow. Da hinten steht ihr Munitionszug. Der fährt heute nirgendwo mehr hin.", 5.0)
	_objective("Güterbahnhof durchqueren – Munitionszug stoppen")
	_radio("Lena Aksoy", "Stellwerk rechts, obere Etage. Da oben sitzt einer.", 3.5)   # Gespraech: direkt nach Weber

func _radio_twist() -> void:
	_radio("Lena Aksoy", "Kanal zwei, nur wir, Jonas. Weber funkt seit Tagen verschlüsselt mit Berlin. Nachts.", 5.0)
	_radio("Hauptmann Weber", "Funkdisziplin, Aksoy. Augen nach vorn.", 3.0)   # Antwort direkt nach Lena

func _radio_tank() -> void:
	if _a_done:
		return
	_radio("Hauptmann Weber", "Kesselwagen mit roter Binde – Treibladungen. Ein Treffer und der ganze Zug geht hoch.", 5.0)
	_radio_opt("Lena Aksoy", "Die Gefangenenwagen haben sie mittags abgehängt. Der Zug ist leer – nur Munition.", 5.0,
		{"valid": func() -> bool: return not _a_done})

## Set-Piece A: Lena schiesst von hinten auf den markierten Kesselwagen.
func _run_setpiece_a() -> void:
	if _a_done or train == null:
		return
	Events.story_cinematic.emit(true)
	_radio_opt("Hauptmann Weber", "Aksoy! Panzerfaust auf die rote Binde!", 2.5, {"priority": 2, "cut": true})
	_later(5.5, func() -> void: Events.story_cinematic.emit(false))
	await get_tree().create_timer(1.6).timeout
	if _a_done:
		return
	_radio_opt("Lena Aksoy", "Rakete raus!", 1.5, {"priority": 2, "no_chain": true})
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var from := Vector3(-3.0, 1.7, -100.0)
	if pl != null:
		from = pl.global_position + Vector3(-2.5, 1.6, 7.0)
	var to: Vector3 = train.call("get_marked_position")
	if fx != null:
		fx.call("rocket", from, to, 0.85, func() -> void: train.call("detonate"))
	else:
		train.call("detonate")

func _on_train_detonated(_pos: Vector3) -> void:
	if _fps_log:
		print("[rail_fps] t=%.1f KETTENEXPLOSION" % _t)
	if _a_done:
		return
	_a_done = true
	_setpiece_done = true
	_later(2.6, func() -> void:
		_radio_opt("Lena Aksoy", "Heilige ... das ganze Gleis brennt!", 2.5, {"priority": 1, "max_age": 3.0})
		_radio_opt("Hauptmann Weber", "Weiter! Lagerhallen und Kranbahn, bevor die sich neu sortieren.", 4.0, {"priority": 1}))
	_later(6.0, func() -> void: _objective("Lagerhallen und Kranbahn sichern"))

## Set-Piece B: Jets bomben die letzte Stellung, der Portalkran faellt.
func _run_setpiece_b() -> void:
	if _b_started:
		return
	_b_started = true
	_spawn_wave(3)
	_radio_opt("Hauptmann Weber", "Adler-Staffel im Anflug. Köpfe runter!", 3.0, {"priority": 2})
	_later(10.0, _spawn_juggernaut)
	await get_tree().create_timer(1.8).timeout
	var targets: Array[Vector3] = [Vector3(-9.0, 0, -252.0), Vector3(4.0, 0, -248.0), Vector3(12.0, 0, -240.0),
		Vector3(20.0, 0, -237.0), Vector3(-12.0, 0, -240.0)]
	var from := Vector3(6.0, 55.0, 160.0)
	var to := Vector3(6.0, 60.0, -900.0)
	var ok := false
	if ResourceLoader.exists(JET_SCENE):
		var ps := load(JET_SCENE) as PackedScene
		if ps != null:
			var jet := ps.instantiate() as Node3D
			if jet != null and jet.has_method("run"):
				add_child(jet)
				jet.call("run", from, to, targets)
				ok = true
				# Rottenflieger etwas versetzt
				var jet2 := ps.instantiate() as Node3D
				add_child(jet2)
				jet2.set("boom", false)
				var t2: Array[Vector3] = []
				jet2.call("run", from + Vector3(22.0, 6.0, 30.0), to + Vector3(22.0, 6.0, 0.0), t2)
	if not ok and fx != null:
		fx.call("fallback_jets", from + Vector3(0, 0, -200.0), to, targets)
	# Ersatz, falls keine Bombe nahe genug am Kran einschlaegt
	_later(8.0, _topple_crane)

## Vom Ladebildschirm (main.gd _warmup) aufgerufen: Effekte der Zug-Detonation einmal vorab bauen.
## Ohne das kompilierte die erste Detonation Feuerball-/Funken-Shader und das Verkohlt-Material
## (+14 Pipelines, 120 ms Ruckler).
func warmup_fx(holder: Node3D, at: Vector3, fwd: Vector3) -> void:
	if fx != null:
		fx.call("fireball", at + fwd * 8.0, 1.0)
		fx.call("spark_burst", at + fwd * 6.0, 8)
	if train != null:
		var ch = train.get("_charred")
		if ch is Material:
			var mi := MeshInstance3D.new()
			mi.mesh = BoxMesh.new()
			mi.material_override = ch
			holder.add_child(mi)
			mi.global_position = at + fwd * 4.0

func _on_explosion(pos: Vector3, _radius: float, _strength: float) -> void:
	if not _b_started or crane == null:
		return
	var d := Vector2(pos.x - CRANE_POS.x, pos.z - CRANE_POS.z).length()
	if d < 14.0:
		_later(0.25, _topple_crane)

func _topple_crane() -> void:
	if crane == null or not crane.call("is_standing"):
		return
	crane.call("topple")
	_radio_opt("Lena Aksoy", "Der Kran! Der ganze Kran kommt runter!", 2.5, {"priority": 2, "max_age": 2.5})

# ------------------------------------------------------------------ Finale

func _physics_process(delta: float) -> void:
	_t += delta
	if _fps_log:
		_fps_acc += delta
		if _fps_acc >= 0.5:
			_fps_acc = 0.0
			var vp := get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(vp, true)
			print("[rail_fps] t=%.1f fps=%d proc=%.1f phys=%.1f gpu=%.1f rcpu=%.1f prim=%d draws=%d" % [_t, Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				RenderingServer.viewport_get_measured_render_time_gpu(vp), RenderingServer.viewport_get_measured_render_time_cpu(vp),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if _debug_god:
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null and "health" in pl:
			pl.set("health", 100.0)
	if not _ending and _b_started and _waves_spawned.has(3) and _b_time >= 0.0 and _t - _b_time > 6.0:
		var alive := 0
		for e in get_tree().get_nodes_in_group("enemy"):
			if e.has_method("is_alive") and e.call("is_alive"):
				alive += 1
		if alive <= 1:
			_start_ending()
	_update_fleeing(delta)

func _start_ending() -> void:
	if _ending:
		return
	# Juggernaut-Finale: nach dem Luftangriff kommt er aus der Halle; das Ende wartet, bis er liegt
	if _b_started and _jugg == null:
		_spawn_juggernaut()
		return
	if _jugg != null and is_instance_valid(_jugg) and bool(_jugg.call("is_alive")):
		return
	_ending = true
	_objective("")
	var i := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is CharacterBody3D) or not e.has_method("is_alive") or not e.call("is_alive"):
			continue
		var en := e as CharacterBody3D
		en.remove_from_group("enemy")
		en.set_physics_process(false)
		en.set("_aim_at_target", false)
		en.set("_los", false)
		if en.get("nav") == null:
			# Drohnen drehen ab und steigen
			var tw := en.create_tween()
			tw.tween_property(en, "global_position", en.global_position + Vector3(rng.randf_range(-20, 20), 40.0, -60.0), 6.0)
			tw.tween_callback(en.queue_free)
			continue
		var mode := "kneel" if i % 2 == 0 else "flee"
		if mode == "kneel":
			en.set("_stance_target", 1.0)
		_fleeing.append({"e": en, "mode": mode, "target": Vector3(en.global_position.x * 0.5, 0, -300.0), "t": 0.0})
		i += 1
	# Gespraech im selben Frame: jede Zeile direkt nach der vorigen; Levelende erst, wenn der Funk frei ist
	_radio_opt("Lena Aksoy", "Sie werfen die Waffen weg ... die rennen!", 3.5, {"priority": 2, "cut": true})
	_radio_opt("Hauptmann Weber", "An alle Einheiten: Moskau hat den Waffenstillstand unterzeichnet. Es ist vorbei.", 6.5, {"priority": 2})
	_radio_opt("Lena Aksoy", "Vorbei. Hörst du, Jonas? Es ist vorbei.", 4.0, {"priority": 2})
	_later(6.0, _launch_flares)
	_later(14.0, _when_radio_free.bind(_on_level_end, 10.0))

const JUGG_POS := Vector3(0.0, 0.05, -264.0)
var _jugg: Node3D = null

func _spawn_juggernaut() -> void:
	if _jugg != null or _ending or not spawn_enemies:
		return
	var ps := load(JUGGERNAUT_SCENE) as PackedScene
	if ps == null:
		return
	_jugg = ps.instantiate() as Node3D
	_jugg.set_meta("faction", default_faction)
	add_child(_jugg)
	_jugg.global_position = JUGG_POS
	_jugg.rotation.y = 0.0
	_objective("Juggernaut ausschalten")
	_radio_opt("Lena Aksoy", "Da kommt was Großes aus der Halle – ein Juggernaut! Aufs Visier zielen!", 4.5, {"priority": 1})
	_radio_opt("Hauptmann Weber", "Der Tornister auf dem Rücken ist seine Schwachstelle!", 3.5,
		{"priority": 1, "valid": func() -> bool: return _jugg != null and is_instance_valid(_jugg)})
	var p := Game.get_player() as Node3D
	if p != null and _jugg.has_method("alert"):
		_jugg.call("alert", p.global_position)

func _launch_flares() -> void:
	if fx == null:
		return
	var cols: Array[Color] = [Color(0.3, 1.0, 0.35), Color(1.0, 0.25, 0.15), Color(1.0, 0.95, 0.85), Color(0.3, 1.0, 0.35), Color(1.0, 0.95, 0.85)]
	var spots: Array[Vector3] = [Vector3(-6.0, 0.5, -230.0), Vector3(14.0, 0.5, -210.0), Vector3(-18.0, 0.5, -150.0), Vector3(20.0, 0.5, -120.0), Vector3(0.0, 0.5, -280.0)]
	for j in cols.size():
		_later(0.6 + j * 0.9, func() -> void: fx.call("signal_flare", spots[j], cols[j], rng.randf_range(45.0, 65.0)))

func _update_fleeing(delta: float) -> void:
	for i in range(_fleeing.size() - 1, -1, -1):
		var f: Dictionary = _fleeing[i]
		var en: CharacterBody3D = f["e"]
		if not is_instance_valid(en):
			_fleeing.remove_at(i)
			continue
		if not en.call("is_alive"):
			en.set_physics_process(true)
			_fleeing.remove_at(i)
			continue
		f["t"] = float(f["t"]) + delta
		if f["mode"] == "flee":
			en.call("_move_to", f["target"], float(en.get("run_speed")), delta)
			if en.global_position.z < -282.0 or float(f["t"]) > 25.0:
				en.queue_free()
				_fleeing.remove_at(i)
				continue
		else:
			en.set("_desired_velocity", Vector3.ZERO)
		en.call("_update_facing", delta)
		en.call("_apply_motion", delta)
		en.call("_animate", delta)
