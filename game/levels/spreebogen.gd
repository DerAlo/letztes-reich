extends "res://game/levels/level.gd"
## Mission 9 "Spreebogen" (Teil 4): Morgengrauen in Moabit. Kerner sitzt im Turm des Schuetzenpanzers
## "Rabe", Voss faehrt eine feste Route Richtung Moltkebruecke und haelt fuer Feuergefechte an.
## Halt 1: Panzerfaust-Fenster + Strassensperre. Halt 2: Garde-Panzer aus der Seitenstrasse + Fenster.
## Halt 3: Kampfhubschrauber ueber dem Uferplatz. Dann Treffer am Brueckenkopf, Ausstieg, Bruecke zu Fuss
## (gepanzerte Garde + Juggernaut). Oberst Falk meldet sich zum ersten Mal im Funk.
## Debug: --phase=1..5 (5 = direkt zu Fuss).

const SD := preload("res://game/story/story_data.gd")
const VF := preload("res://game/vehicles/vehicle_fx.gd")
const IfvScript := preload("res://game/vehicles/ifv/ifv.gd")
const IfvRocket := preload("res://game/vehicles/ifv/ifv_rocket.gd")
const BarricadeScript := preload("res://game/levels/spreebogen_barricade.gd")
const HDRI := "res://assets/environment/rail/hdri/industrial_sunset_02_puresky_2k.hdr"
const TANK_SCENE := "res://game/vehicles/tank.tscn"
const HELI_SCENE := "res://game/vehicles/helicopter.tscn"

const LANE_X := -1.0
const START_Z := 22.0
const HALT_Z: Array[float] = [22.0, -40.0, -118.0, -195.0, -246.0]
const BRIDGE_Z0 := -258.0
const BRIDGE_Z1 := -352.0
const SUN_AZ := 150.0
const SUN_EL := 4.0

var ifv: IfvScript = null
var phase: int = 0
var _time: float = 0.0
var _phase_t: float = 0.0
var _failed: String = ""
var _radio_end: float = 0.0
var _fail_count: int = 0
var _done: bool = false
var _on_foot: bool = false
var _phase_nodes: Array[Node] = []
var _rpg: Array = []                 ## [{e: Node3D, cd: float}]
var _tank: Node3D = null
var _heli: Node3D = null
var _far_tank: Node3D = null
var _was_smoke: bool = false
var _boss: Node3D = null
var _foot_t: float = 0.0
var _finale_started: bool = false
var _assist_done: bool = false
var _nests: Dictionary = {}          ## id -> [side, zc, floor]

func _init() -> void:
	level_name = "spreebogen"
	spawn_player = false
	spawn_enemies = false
	default_faction = "reich"
	ambient_artillery = true
	end_z = -366.0
	fog_density = 0.012
	build_seed = 2406

func get_level_info() -> Dictionary:
	var wps: Array = []
	for p: Vector3 in [Vector3(3.5, 0, -240), Vector3(3.0, 0, -256), Vector3(-3, 0, -272), Vector3(-3, 0, -288), Vector3(3, 0, -306),
			Vector3(3, 0, -322), Vector3(-2, 0, -338), Vector3(0, 0, -352), Vector3(0, 0, -362)]:
		wps.append([p.x, p.y, p.z])
	return {"name": level_name, "title": "Spreebogen", "waves": 5, "end_position": [0.0, 0.0, end_z], "waypoints": wps}

func is_level_ready() -> bool:
	return _ready_done

func _ready() -> void:
	_nests = {
		"n1": [-1, -50.0, 1], "n2": [1, -54.0, 1],
		"n3": [1, -130.0, 1], "n4": [-1, -128.0, 2],
		"n5": [1, -205.0, 1],
	}
	await super._ready()
	if not is_inside_tree():
		return
	_run()

func _process(delta: float) -> void:
	_time += delta
	_phase_t += delta
	if _on_foot:
		_foot_t += delta
		_foot_tick()

func _physics_process(delta: float) -> void:
	_rpg_tick(delta)

# ================================================================== Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(fog_density, 1.0)
	if ResourceLoader.exists(HDRI):
		var pm := env.sky.sky_material as PanoramaSkyMaterial
		pm.panorama = load(HDRI)
		pm.energy_multiplier = 0.7
	env.sky_rotation = Vector3(0.0, deg_to_rad(VfxEnv.SKY_YAW_OFFSET_DEG), 0.0)
	env.ambient_light_energy = 0.95
	env.tonemap_exposure = 0.9
	env.fog_light_color = Color(0.55, 0.52, 0.58)
	env.fog_light_energy = 0.8
	env.fog_density = 0.0022
	env.fog_sun_scatter = 0.18
	env.fog_aerial_perspective = 0.4
	env.fog_sky_affect = 0.3
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.78, 0.74, 0.76)
	env.volumetric_fog_emission = Color(0.03, 0.02, 0.02)
	env.volumetric_fog_anisotropy = 0.5
	env.volumetric_fog_length = 150.0
	env.volumetric_fog_sky_affect = 0.25
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	# Morgensonne knapp ueber dem Horizont, voraus rechts (Gegenlicht an der Bruecke)
	var sun := VfxEnv.make_sun()
	sun.light_color = Color(1.0, 0.6, 0.4)
	sun.light_energy = 2.1
	sun.light_volumetric_fog_energy = 1.0
	sun.directional_shadow_max_distance = 170.0
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_EL)
	var to_sun := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	sun.transform = Transform3D(Basis.looking_at(-to_sun, Vector3.UP), Vector3.ZERO)
	add_child(sun)
	# Kuehles Daemmerungslicht von hinten (Westhimmel noch blau)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.55, 0.62, 0.85)
	fill.light_energy = 0.45
	fill.light_indirect_energy = 0.0
	fill.light_volumetric_fog_energy = 0.0
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.transform = Transform3D(Basis.looking_at(Vector3(-0.2, -0.5, -1.0).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(fill)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "day_war")

# ================================================================== Boden, Ufer, Bruecke

func _build_ground() -> void:
	var asphalt := Geo.mat("asphalt_02", Color(0.55, 0.55, 0.58), 0.2, 1.0)
	var walk := Geo.mat("concrete_wall_008", Color(0.5, 0.49, 0.47), 0.35, 1.0)
	var dirt := Geo.mat("concrete_wall_008", Color(0.26, 0.24, 0.23), 0.12, 1.0)
	var quay := Geo.mat("concrete_wall_008", Color(0.42, 0.4, 0.38), 0.25, 1.0)
	# Kollision Strasse + Uferplatz (bis Kaimauer) und anderes Ufer
	var g := Geo.static_body(Vector3(0, -1.0, (40.0 + BRIDGE_Z0) / 2.0))
	Geo.add_box_shape(g, Vector3.ZERO, Vector3(80.0, 2.0, 40.0 - BRIDGE_Z0))
	world.add_child(g)
	var g2 := Geo.static_body(Vector3(0, -1.0, (BRIDGE_Z1 - 420.0) / 2.0))
	Geo.add_box_shape(g2, Vector3.ZERO, Vector3(80.0, 2.0, 420.0 + BRIDGE_Z1))
	world.add_child(g2)
	# Ferner Boden (Optik) diesseits und jenseits des Flusses
	var far := Geo.box_mesh_node(Vector3(900.0, 0.2, 520.0), dirt, Vector3(0, -0.12, BRIDGE_Z0 + 260.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	var far2 := Geo.box_mesh_node(Vector3(900.0, 0.2, 400.0), dirt, Vector3(0, -0.12, BRIDGE_Z1 - 200.0))
	far2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far2)
	# Fahrbahn (Alt-Moabit) und Uferplatz
	world.add_child(Geo.box_mesh_node(Vector3(14.0, 0.2, 251.0), asphalt, Vector3(0, -0.1, 40.0 - 125.5)))
	world.add_child(Geo.box_mesh_node(Vector3(56.0, 0.2, 47.0), quay, Vector3(0, -0.1, -211.0 - 23.5)))
	world.add_child(Geo.box_mesh_node(Vector3(56.0, 0.2, 60.0), quay, Vector3(0, -0.1, BRIDGE_Z1 - 30.0)))
	world.add_child(Geo.box_mesh_node(Vector3(14.0, 0.21, 60.0), asphalt, Vector3(0, -0.09, BRIDGE_Z1 - 30.0)))
	for sx in [-1.0, 1.0]:
		var w := Geo.static_body(Vector3(sx * 8.5, 0.07, 40.0 - 125.5))
		w.add_child(Geo.box_mesh_node(Vector3(3.0, 0.14, 251.0), walk, Vector3.ZERO))
		Geo.add_box_shape(w, Vector3.ZERO, Vector3(3.0, 0.14, 251.0))
		world.add_child(w)
	# Spree: Wasser + Kaimauern
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.07, 0.09, 0.1)
	water_mat.roughness = 0.08
	water_mat.metallic = 0.4
	var water := Geo.box_mesh_node(Vector3(900.0, 0.1, BRIDGE_Z0 - BRIDGE_Z1), water_mat, Vector3(0, -2.8, (BRIDGE_Z0 + BRIDGE_Z1) / 2.0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	for z in [BRIDGE_Z0, BRIDGE_Z1]:
		var zf: float = z
		var dz := -0.6 if zf == BRIDGE_Z0 else 0.6
		add_child(Geo.box_mesh_node(Vector3(900.0, 3.0, 1.2), quay, Vector3(0, -1.5, zf + dz)))
		# Gelaender an der Kante + Laufsperre (ausser auf der Bruecke)
		for sx in [-1.0, 1.0]:
			_invisible_wall(Vector3(sx * 24.0, 4.0, zf + dz * 0.5), Vector3(33.0, 8.0, 1.0))
			for k in 10:
				var x: float = sx * (8.5 + k * 2.0)
				world.add_child(Geo.box_mesh_node(Vector3(0.08, 1.0, 0.08), Geo.flat(Color(0.12, 0.12, 0.12), 0.6, 0.6), Vector3(x, 0.5, zf + dz * 0.3)))
			world.add_child(Geo.box_mesh_node(Vector3(20.0, 0.08, 0.08), Geo.flat(Color(0.12, 0.12, 0.12), 0.6, 0.6), Vector3(sx * 17.5, 1.0, zf + dz * 0.3)))
	# Moltkebruecke: Sandsteindeck, Bruestungen, Pfeiler
	var stone := Geo.mat("concrete_wall_008", Color(0.62, 0.55, 0.47), 0.3, 1.0)
	var blen := BRIDGE_Z0 - BRIDGE_Z1
	var bc := (BRIDGE_Z0 + BRIDGE_Z1) / 2.0
	var deck := Geo.static_body(Vector3(0, -0.45, bc))
	deck.add_child(Geo.box_mesh_node(Vector3(16.0, 0.9, blen + 1.0), stone, Vector3.ZERO))
	Geo.add_box_shape(deck, Vector3.ZERO, Vector3(16.0, 0.9, blen + 1.0))
	world.add_child(deck)
	world.add_child(Geo.box_mesh_node(Vector3(12.0, 0.05, blen), asphalt, Vector3(0, 0.02, bc)))
	for sx in [-1.0, 1.0]:
		var par := Geo.static_body(Vector3(sx * 7.6, 0.55, bc))
		par.add_child(Geo.box_mesh_node(Vector3(0.7, 1.1, blen), stone, Vector3.ZERO))
		Geo.add_box_shape(par, Vector3.ZERO, Vector3(0.7, 1.1, blen))
		world.add_child(par)
		_invisible_wall(Vector3(sx * 7.9, 4.0, bc), Vector3(0.6, 8.0, blen))
		# Bruestungspfosten mit Laternen
		for k in 5:
			var z := BRIDGE_Z0 - 8.0 - k * 19.0
			world.add_child(Geo.box_mesh_node(Vector3(1.1, 1.6, 1.1), stone, Vector3(sx * 7.6, 0.8, z)))
			Props.lamp(world, Vector3(sx * 7.6, 1.6, z), 90.0 * sx, false, 6.0 if k == 2 else 0.0)
	for k in 3:
		var z := BRIDGE_Z0 - 23.5 - k * 23.5
		add_child(Geo.box_mesh_node(Vector3(14.0, 3.5, 5.0), stone, Vector3(0, -2.6, z)))
	# Aussengrenzen
	for sx in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 26.0, 6.0, -100.0), Vector3(1.0, 12.0, 280.0))
		_invisible_wall(Vector3(sx * 26.0, 6.0, -375.0), Vector3(1.0, 12.0, 50.0))
	_invisible_wall(Vector3(0, 6.0, 36.0), Vector3(60.0, 12.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, -392.0), Vector3(60.0, 12.0, 1.0))
	# Zu Fuss nicht zurueck in die Strasse
	_invisible_wall(Vector3(0, 6.0, -214.0), Vector3(60.0, 12.0, 1.0))

# ================================================================== Haeuser + Panzerfaust-Nester

func _build_street() -> void:
	var tints: Array[Color] = [Color(0.82, 0.72, 0.62), Color(0.76, 0.72, 0.66), Color(0.68, 0.6, 0.56), Color(0.74, 0.64, 0.56), Color(0.62, 0.6, 0.58)]
	# [side, z_near, z_far, floors, brick, damage, depth]
	var specs: Array = [
		[-1, 34.0, -4.0, 5, true, 0.3, 12.0], [-1, -4.0, -46.0, 4, false, 0.45, 12.0],
		[-1, -54.0, -90.0, 5, true, 0.35, 12.0], [-1, -90.0, -124.0, 4, false, 0.5, 12.0],
		[-1, -132.0, -138.0, 4, true, 0.4, 10.0],
		[-1, -154.0, -180.0, 4, true, 0.5, 12.0], [-1, -180.0, -215.0, 5, false, 0.4, 12.0],
		[1, 34.0, 0.0, 4, false, 0.35, 12.0], [1, 0.0, -50.0, 5, true, 0.4, 12.0],
		[1, -58.0, -96.0, 4, false, 0.5, 12.0], [1, -96.0, -126.0, 4, true, 0.4, 12.0],
		[1, -134.0, -170.0, 5, false, 0.45, 12.0], [1, -170.0, -201.0, 4, true, 0.5, 12.0],
		[1, -209.0, -215.0, 4, false, 0.4, 10.0],
	]
	var brs := RandomNumberGenerator.new()
	brs.seed = build_seed + 7
	for s: Array in specs:
		var opts := {"brick": s[4], "tint": tints[brs.randi() % tints.size()], "damage": s[5], "lit": 0.05}
		var info := Buildings.build(world, s[0], s[1], s[2], s[3], s[6], opts, brs)
		var fl: Array = info["floors"]
		var zc: Array = info["zc"]
		for k in fl.size():
			if int(fl[k]) < int(s[3]) and brs.randf() < 0.7:
				Props.rubble(world, Vector3(float(s[0]) * 8.7, 0.0, float(zc[k])), brs.randf_range(1.2, 2.2), brs.randf_range(0.4, 0.8), brs, false)
	for id: String in _nests:
		var n: Array = _nests[id]
		_build_nest(int(n[0]), float(n[1]), int(n[2]), tints[brs.randi() % tints.size()])
	# Seitenstrasse links (Panzer kommt von dort): Ende mit Mauer und Schutt
	Props.wall(world, Vector3(-40.0, 0, -146.0), 90.0, 16.0, 4.0, 1.0, rng)
	Props.rubble(world, Vector3(-18.0, 0, -140.5), 1.8, 0.8, rng, false)
	# Ecke Uferplatz: niedrige Mauerreste
	Props.wall(world, Vector3(-17.0, 0, -224.0), 0.0, 10.0, 1.4, 0.6, rng, covers)
	Props.wall(world, Vector3(18.0, 0, -228.0), 0.0, 8.0, 1.2, 0.6, rng, covers)

## Hohles Eckhaus mit Fensterloch: Panzerfaust-Trupp steht direkt dahinter.
func _build_nest(side: int, zc: float, fl: int, tint: Color) -> void:
	var wm := Buildings.wall_mat(true, tint, 0.5)
	var dark := Geo.flat(Color(0.12, 0.11, 0.1))
	var sx := float(side)
	var x0 := sx * 10.35
	var h := 11.2
	var fy := fl * Buildings.FLOOR_H
	var sill := fy + 0.45
	var top := fy + 2.6
	var hw := 1.6
	Geo.solid_box(world, Vector3(x0, sill / 2.0, zc), Vector3(0.7, sill, 8.0), wm)
	Geo.solid_box(world, Vector3(x0, (top + h) / 2.0, zc), Vector3(0.7, h - top, 8.0), wm)
	for dz in [-1.0, 1.0]:
		var w := 4.0 - hw
		Geo.solid_box(world, Vector3(x0, (sill + top) / 2.0, zc + dz * (hw + w / 2.0)), Vector3(0.7, top - sill, w), wm)
		Geo.solid_box(world, Vector3(sx * 14.2, h / 2.0, zc + dz * 3.85), Vector3(7.7, h, 0.3), wm)
	Geo.solid_box(world, Vector3(sx * 17.9, h / 2.0, zc), Vector3(0.4, h, 8.0), wm)
	for k in [1, 2, 3]:
		var y: float = k * Buildings.FLOOR_H
		Geo.solid_box(world, Vector3(sx * 14.2, y - 0.15, zc), Vector3(7.4, 0.3, 7.4), dark)
	# Brandspuren um das Fenster + Glut drinnen
	world.add_child(Geo.box_mesh_node(Vector3(0.05, 2.6, 4.6), Geo.flat(Color(0.05, 0.045, 0.04), 0.95), Vector3(sx * 9.98, (sill + top) / 2.0 + 0.3, zc)))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.25)
	l.light_energy = 1.4
	l.omni_range = 6.0
	l.shadow_enabled = false
	l.position = Vector3(sx * 15.5, fy + 1.4, zc + 1.5)
	world.add_child(l)
	Props.rubble(world, Vector3(sx * 8.9, 0.0, zc), 1.5, 0.6, rng, false)

# ================================================================== Requisiten

func _build_props() -> void:
	var cr := RandomNumberGenerator.new()
	cr.seed = build_seed + 3
	# Start: eigene Kolonne hinter dem Rabe (ausgebrannter Bus quer als Strassenabschluss)
	Props.vehicle(world, Vector3(0, 0, 33.0), 90.0, "bus", Color(0.3, 0.32, 0.28), true, false, covers)
	# Brennende Fahrzeuge am Rand (Fahrspur x -3..1 bleibt frei)
	var wrecks: Array = [
		[5.2, 8.0, 12.0, "car", true], [-5.6, -14.0, 170.0, "van", true], [5.0, -30.0, -8.0, "car", true],
		[-5.4, -82.0, 4.0, "car", false], [5.4, -104.0, 182.0, "truck", true], [-5.8, -168.0, 10.0, "car", true],
		[5.6, -182.0, -6.0, "van", false], [-12.0, -236.0, 40.0, "car", true], [14.0, -246.0, 120.0, "truck", true],
	]
	for wv: Array in wrecks:
		var p := Vector3(wv[0], 0, wv[1])
		Props.vehicle(world, p, wv[2], wv[3], Color(0.25, 0.27, 0.25), wv[4], false, covers)
		if wv[4] and cr.randf() < 0.8:
			Props.fire(world, p + Vector3(0, 1.0, 0), 1.0, true, 2.5, 5.0)
	Props.tank_wreck(world, Vector3(6.0, 0, -160.0), 160.0, covers)
	# Halt 1: Sperre + Schuetzen dahinter
	for sx in [-1.0, 1.0]:
		Props.jersey(world, Vector3(sx * 6.3, 0, -62.0), 0.0, covers)
		Props.sandbags(world, Vector3(sx * 5.5, 0, -66.0), 0.0, 3.0, cr, covers)
	Props.hedgehog(world, Vector3(-3.5, 0, -71.0), 20.0, covers)
	Props.hedgehog(world, Vector3(3.0, 0, -72.5), -30.0, covers)
	# Halt 2: Sandsaecke vor der Seitenstrasse
	Props.sandbags(world, Vector3(-6.0, 0, -142.0), 0.0, 3.0, cr, covers)
	Props.sandbags(world, Vector3(6.0, 0, -148.0), 0.0, 3.0, cr, covers)
	# Uferplatz
	Props.sandbags(world, Vector3(-6.0, 0, -232.0), 0.0, 3.0, cr, covers)
	Props.sandbags(world, Vector3(6.5, 0, -238.0), 0.0, 3.0, cr, covers)
	for z in [-34.0, -112.0, -188.0]:
		Props.crater(world, Vector3(cr.randf_range(2.0, 4.0), 0, z), 2.2, cr)
	for i in 14:
		var z := 20.0 - i * 16.0
		var sx := -1.0 if i % 2 == 0 else 1.0
		Props.lamp(world, Vector3(sx * 7.4, 0, z), 90.0 * sx, false, cr.randf_range(0.0, 12.0) if i % 3 == 0 else 0.0)
	# Bruecke: Sperren und Wracks als Deckung
	Props.vehicle(world, Vector3(-4.2, 0, -270.0), 25.0, "car", Color(0.2, 0.2, 0.2), true, false, covers)
	Props.jersey(world, Vector3(3.5, 0, -280.0), 10.0, covers)
	Props.jersey(world, Vector3(-3.0, 0, -292.0), -8.0, covers)
	Props.vehicle(world, Vector3(4.0, 0, -302.0), -20.0, "van", Color(0.22, 0.22, 0.2), true, false, covers)
	Props.sandbags(world, Vector3(-3.5, 0, -314.0), 0.0, 3.0, cr, covers)
	Props.jersey(world, Vector3(3.0, 0, -326.0), 0.0, covers)
	Props.vehicle(world, Vector3(-3.8, 0, -334.0), 170.0, "truck", Color(0.2, 0.22, 0.2), true, false, covers)
	Props.sandbags(world, Vector3(0.0, 0, -344.0), 0.0, 4.0, cr, covers)
	Props.fire(world, Vector3(-4.2, 1.0, -270.0), 1.1, true, 2.5, 5.0)
	Props.fire(world, Vector3(4.0, 1.4, -302.0), 1.2, true, 3.0, 5.0)
	# Anderes Ufer: Stellungen vor dem Regierungsviertel
	Props.sandbags(world, Vector3(-7.0, 0, -360.0), 0.0, 4.0, cr, covers)
	Props.sandbags(world, Vector3(7.0, 0, -362.0), 0.0, 4.0, cr, covers)
	Props.hedgehog(world, Vector3(-12.0, 0, -368.0), 15.0, covers)
	Props.hedgehog(world, Vector3(13.0, 0, -370.0), -20.0, covers)

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(3.5, 0.1, -237.0), "player_spawn")
	ps.name = "PlayerSpawn"
	for p in covers:
		var v: Vector3 = p
		if absf(v.x) > 9.0 and absf(v.x) < 12.0:
			continue
		if v.z > -214.0:
			continue
		Geo.marker(m, Vector3(clampf(v.x, -7.0, 7.0) if v.z < BRIDGE_Z0 and v.z > BRIDGE_Z1 else v.x, 0.0, v.z), "cover_point")
	var end := Geo.marker(self, Vector3(0, 0, end_z))
	end.name = "LevelEnd"
	end.add_to_group("level_end")

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 31
	var bb := Geo.batch()
	for i in 40:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -srng.randf_range(-30.0, 240.0)
		var x := side * srng.randf_range(34.0, 110.0)
		var h := srng.randf_range(14.0, 34.0)
		bb.add(Vector3(x, h / 2.0, z), Vector3(srng.randf_range(10.0, 26.0), h, srng.randf_range(10.0, 24.0)))
	# Regierungsviertel jenseits der Spree: lange flache Riegel
	for i in 9:
		var w := srng.randf_range(30.0, 70.0)
		var h := srng.randf_range(16.0, 28.0)
		bb.add(Vector3(srng.randf_range(-140.0, 140.0), h / 2.0, -420.0 - srng.randf_range(0.0, 160.0)), Vector3(w, h, 22.0))
	var mi := Geo.mesh_node(bb.build(), Geo.mat("concrete_wall_008", Color(0.24, 0.24, 0.26), 0.08, 1.0))
	add_child(mi)
	# Kuppel-Silhouette (Reichstag) im Dunst, rechts voraus
	var sil := Geo.flat(Color(0.2, 0.2, 0.23), 0.9)
	add_child(Geo.box_mesh_node(Vector3(90.0, 24.0, 60.0), sil, Vector3(70.0, 12.0, -470.0)))
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 14.0
	sm.height = 18.0
	dome.mesh = sm
	dome.material_override = sil
	dome.position = Vector3(70.0, 26.0, -470.0)
	add_child(dome)

func _build_atmosphere() -> void:
	# Rauchsaeulen ueber Moabit und am anderen Ufer
	for c: Vector3 in [Vector3(-48, 0, -30), Vector3(55, 0, -80), Vector3(-60, 0, -140), Vector3(42, 0, -190), Vector3(-35, 0, -300), Vector3(60, 0, -430), Vector3(-80, 0, -460)]:
		Props.fire(self, c, 2.6, false, 4.0)
	Props.fire(world, Vector3(11.3, 5.0, -24.0), 0.9, true, 1.2, 6.0)
	Props.fire(world, Vector3(-11.3, 8.5, -100.0), 0.9, true, 1.2, 6.0)
	Props.fire(world, Vector3(11.3, 4.5, -160.0), 1.0, true, 1.5, 6.0)
	# Morgendunst ueber dem Fluss, Rauch in der Strasse
	for z in [-10.0, -70.0, -140.0, -200.0]:
		Props.fog_volume(self, Vector3(0, 1.5, z), Vector3(30, 6, 40), 0.03, Color(0.6, 0.58, 0.6))
	Props.fog_volume(self, Vector3(0, -0.5, -305.0), Vector3(120, 5, 100), 0.04, Color(0.7, 0.7, 0.74))

func _bake_nav() -> void:
	preload("res://game/systems/destructible_placements.gd").place(self)  # zerstoerbare Deckung (systeme-c), vor dem Bake
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-30.0, -1.0, -395.0), Vector3(60.0, 17.0, 435.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)

# ================================================================== Ablauf-Helfer

func _say(speaker: String, text: String, dur: float = 0.0) -> void:
	Events.story_radio.emit(speaker, text, dur)
	var d := dur if dur > 0.0 else clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)
	_radio_end = maxf(_radio_end, _time) + d + 0.65

func _radio_wait(max_wait: float = 12.0) -> bool:
	return await _sleep(clampf(_radio_end - _time, 0.0, max_wait))

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

func _sleep(t: float) -> bool:
	var end := _time + t
	while _time < end:
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
	return true

func _until(cond: Callable, timeout: float = -1.0) -> bool:
	var end := _time + timeout
	while not bool(cond.call()):
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
		if timeout > 0.0 and _time >= end:
			return true
	return true

func _fail(reason: String) -> void:
	if _failed == "" and phase > 0 and phase < 4 and not _done:
		_failed = reason

func _alive(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n.has_method("is_alive"):
		return bool(n.call("is_alive"))
	return not bool(n.get("dead"))

func _all_dead(nodes: Array) -> bool:
	for n in nodes:
		if _alive(n):
			return false
	return true

func _enemy(kind: String, pos: Vector3, yaw: float = PI, props: Dictionary = {}) -> Node3D:
	var e := (load(ENEMY_PATH % kind) as PackedScene).instantiate() as Node3D
	e.set_meta("faction", "reich")
	for k: String in props:
		e.set(k, props[k])
	add_child(e)
	e.global_position = pos
	e.rotation.y = yaw
	_phase_nodes.append(e)
	return e

## Panzerfaust-Schuetze im Fensterloch des Nests id.
func _nest_enemy(id: String) -> Node3D:
	var n: Array = _nests[id]
	var sx := float(n[0])
	var y := int(n[2]) * Buildings.FLOOR_H + 0.05
	var e := _enemy("rifleman", Vector3(sx * 11.15, y, float(n[1])), PI / 2.0 * sx,
		{"walk_speed": 0.0, "run_speed": 0.0, "strafe_speed": 0.0, "cover_chance": 0.0, "flank_chance": 0.0,
		"crouch_in_cover": false, "sight_range": 120.0, "fov_degrees": 360.0, "max_health": 70.0, "damage_per_hit": 6.0})
	e.set_meta("rpg", true)
	e.name = "Panzerfaust_" + id
	_rpg.append({"e": e, "cd": randf_range(4.0, 7.0)})
	return e

func _barricade(pos: Vector3) -> Node3D:
	var b: StaticBody3D = BarricadeScript.new()
	b.name = "Sperre"
	world.add_child(b)
	b.global_position = pos
	_phase_nodes.append(b)
	if ifv != null:
		ifv.extra_targets.append(b)
	return b

func _kill(nv: Variant) -> void:
	if not _alive(nv):
		return
	var n := nv as Node
	var n3 := n as Node3D
	var src: Node = ifv if ifv != null and is_instance_valid(ifv) else self
	if n.has_method("destroy"):
		n.call("destroy")
	elif n.has_method("take_damage"):
		var prev := bool(Combat.get("explosion_active"))
		Combat.set("explosion_active", true)
		n.call("take_damage", 99999.0, src, n3.global_position + Vector3.UP, Vector3.UP)
		Combat.set("explosion_active", prev)

func _clear_phase_nodes() -> void:
	for n in _phase_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_phase_nodes.clear()
	_rpg.clear()
	_tank = null
	_heli = null
	for r in get_tree().get_nodes_in_group("spree_rocket"):
		r.queue_free()
	if ifv != null:
		ifv.extra_targets.clear()

## Wartet, bis alle Pflichtziele tot sind. Nach timeout hilft Lenas Trupp (kein Haenger).
func _clear(req: Array, timeout: float = 90.0) -> bool:
	var ok: bool = await _until(func() -> bool: return _all_dead(req), timeout)
	if not ok:
		return false
	if not _all_dead(req):
		var names: Array[String] = []
		for n in req:
			if _alive(n):
				names.append(str((n as Node).name))
		print("[spreebogen] Phase %d: Zeitlimit, Lenas Trupp hilft (%s)" % [phase, ", ".join(names)])
		_say(SD.LENA, "Mein Trupp nimmt das Haus. Feuer halten!")
		await _sleep(3.0)
		if _failed != "":
			return false
		for n in req:
			_kill(n)
	return true

## Rest-Infanterie der Phase raeumen (Lenas Trupp folgt dem Rabe).
func _mop_up(wait: float = 10.0) -> void:
	var rest: Array = []
	for n in _phase_nodes:
		if is_instance_valid(n) and n.is_in_group("enemy") and _alive(n):
			rest.append(n)
	if rest.is_empty():
		return
	await _until(func() -> bool: return _all_dead(rest), wait)
	for n in rest:
		_kill(n)

# ================================================================== Panzerfaust-Logik

func _rpg_tick(delta: float) -> void:
	if ifv == null or not is_instance_valid(ifv) or ifv.dead:
		return
	var smoke := ifv.smoke_active()
	if smoke != _was_smoke:
		_was_smoke = smoke
		if _tank != null and is_instance_valid(_tank) and _alive(_tank):
			_tank.call("set_target", null if smoke else ifv)
		if _heli != null and is_instance_valid(_heli) and _alive(_heli):
			_heli.call("attack", not smoke)
	var space := get_world_3d().direct_space_state
	for r: Dictionary in _rpg:
		var ev: Variant = r["e"]
		if not _alive(ev):
			continue
		var e := ev as Node3D
		r["cd"] = float(r["cd"]) - delta
		if float(r["cd"]) > 0.0:
			continue
		var head := e.global_position + Vector3.UP * 1.5
		var tgt := ifv.global_position + Vector3.UP * 1.6
		if head.distance_to(tgt) > 80.0 or ifv.moving() and head.distance_to(tgt) > 45.0:
			r["cd"] = 1.0
			continue
		var ex: Array[RID] = []
		if e is CollisionObject3D:
			ex.append((e as CollisionObject3D).get_rid())
		var q := PhysicsRayQueryParameters3D.create(head, tgt, 1, ex)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and (hit["position"] as Vector3).distance_to(tgt) > 3.0:
			r["cd"] = 1.0
			continue
		r["cd"] = randf_range(9.0, 13.0) + 2.0 * float(_fail_count)
		ifv.warn_rocket(head)
		get_tree().create_timer(1.0, false).timeout.connect(_launch_rpg.bind(e))

func _launch_rpg(ev: Variant) -> void:
	if not _alive(ev) or ifv == null or not is_instance_valid(ifv) or ifv.dead:
		return
	var e := ev as Node3D
	var head := e.global_position + Vector3.UP * 1.5
	var tgt := ifv.global_position + Vector3.UP * 1.4
	var dir := (tgt - head).normalized()
	if ifv.smoke_active():
		# Im Nebel blind: deutlich daneben
		tgt += dir.cross(Vector3.UP).normalized() * (6.0 if randf() < 0.5 else -6.0) + Vector3.UP * 2.5
	var from := head + dir * 1.4
	VF.play_at(self, "rocket_launch", from, 2.0, 14.0, 300.0)
	IfvRocket.fire(self, from, tgt, 62.0, e, 9.0)

# ================================================================== Ablauf

func _run() -> void:
	await get_tree().process_frame
	var start := clampi(int(Game.arg("phase", 1)), 1, 5)
	if start >= 5:
		phase = 5
		_start_foot(true)
		return
	_spawn_ifv()
	ifv.reset_to(ifv.s_for_z(HALT_Z[start - 1]))
	if start == 1:
		await _intro()
	phase = start
	while phase <= 3 and is_inside_tree():
		_failed = ""
		_phase_t = 0.0
		await _radio_wait(8.0)
		var ok: bool = await _phase(phase)
		if not is_inside_tree():
			return
		print("[spreebogen] Phase %d %s nach %.1f s (gesamt %.1f s, Rabe %.0f %%)" % [phase, "geschafft" if ok and _failed == "" else "FEHLER " + _failed, _phase_t, _time, ifv.integrity])
		if ok and _failed == "":
			_checkpoint("cp_halt%d" % phase)
			phase += 1
		else:
			await _retry()
	if is_inside_tree():
		phase = 4
		await _p4_dismount()

func _spawn_ifv() -> void:
	ifv = IfvScript.new()
	ifv.name = "Rabe"
	add_child(ifv)
	var pts: Array[Vector3] = [Vector3(LANE_X, 0, START_Z), Vector3(LANE_X, 0, HALT_Z[4] - 2.0)]
	ifv.set_path(pts)
	ifv.ifv_destroyed.connect(func() -> void: _fail("ifv"))
	player = ifv

func _phase(p: int) -> bool:
	match p:
		1: return await _p1()
		2: return await _p2()
		3: return await _p3()
	return true

func _intro() -> void:
	ifv.input_enabled = true
	_say(SD.LENA, "Rabe an alle: Abmarsch. Voss fährt, Kerner sitzt am Turm. Ziel Moltkebrücke.")
	_say(SD.VOSS, "Kaum seid ihr vom Traunsee zurück, schon fahr ich euch wieder durch Berlin.")
	_say(SD.KERNER, "Weber ist uns entwischt. Dann eben Riedhammer zuerst.")
	_say(SD.LENA, "Zwei Wochen nach der Ausstrahlung hält die Garde noch immer den Spreebogen. Wir sind die Spitze, hinter uns kommen drei Bataillone.")
	_say(SD.LENA, "Kanone gegen Fenster und Fahrzeuge, Koax gegen Infanterie. Nebel nur, wenn eine Panzerfaust kommt.")
	_obj("Mit dem Rabe zur Moltkebrücke durchbrechen")
	await _radio_wait(16.0)

func _retry() -> void:
	_fail_count += 1
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	_say(SD.VOSS, "Wir brennen! Zurücksetzen, sofort!")
	Events.player_died.emit()
	ifv.input_enabled = false
	ifv.fire_held = false
	await get_tree().create_timer(2.5, false).timeout
	_clear_phase_nodes()
	ifv.refit()
	ifv.reset_to(ifv.s_for_z(HALT_Z[phase - 1]))
	# Nach mehreren Fehlschlaegen: Panzerung haelt (Rabe faellt nicht mehr ganz aus)
	ifv.invulnerable = _fail_count >= 3
	ifv.input_enabled = true
	_say(SD.LENA, "Noch einmal. Gleiche Straße, gleiche Fenster.")
	await get_tree().create_timer(1.0, false).timeout

func _after_clear() -> void:
	ifv.repair(60.0)
	ifv.smoke_charges = maxi(ifv.smoke_charges, 2)

# --- Halt 1: Sperre und Fenster

func _p1() -> bool:
	var n1 := _nest_enemy("n1")
	var n2 := _nest_enemy("n2")
	var bar := _barricade(Vector3(0, 0, -62.0))
	_enemy("rifleman", Vector3(-5.0, 0.05, -67.5))
	_enemy("rifleman", Vector3(5.5, 0.05, -67.5))
	_enemy("assault", Vector3(1.0, 0.05, -70.0))
	ifv.drive_to_z(HALT_Z[1])
	await _sleep(3.0)
	_say(SD.VOSS, "Sperre voraus! Ich halte an.")
	if not await _until(func() -> bool: return ifv.arrived(), 30.0):
		return false
	_say(SD.LENA, "Fenster links und rechts, Panzerfaust-Trupps! Erst die Fenster, dann die Sperre.")
	_obj("Panzerfaust-Fenster und Straßensperre ausschalten")
	var warned := [false]
	var hit_said := [false]
	var on_hit := func(d: float, _z: int) -> void:
		if d >= 5.0 and not hit_said[0]:
			hit_said[0] = true
			_say(SD.VOSS, "Treffer am Bug! Wir halten noch.")
	ifv.hit_taken.connect(on_hit)
	var req: Array = [n1, n2, bar]
	var watch := func() -> bool:
		if not warned[0] and ifv.rocket_warn > 0.0:
			warned[0] = true
			_say(SD.LENA, "Panzerfaust! Nebel, Kerner!")
		return _all_dead(req)
	var ok: bool = await _until(watch, 90.0)
	if ifv.hit_taken.is_connected(on_hit):
		ifv.hit_taken.disconnect(on_hit)
	if not ok:
		return false
	if not await _clear(req, 1.0):
		return false
	await _mop_up(8.0)
	if _failed != "":
		return false
	_say(SD.VOSS, "Sperre ist weg. Ich fahre durch.")
	_after_clear()
	return true

# --- Halt 2: Garde-Panzer aus der Seitenstrasse

func _p2() -> bool:
	_enemy("rifleman", Vector3(-8.5, 0.2, -92.0))
	_enemy("rifleman", Vector3(8.6, 0.2, -97.0))
	_enemy("rifleman", Vector3(-8.2, 0.2, -101.0))
	var n3 := _nest_enemy("n3")
	var n4 := _nest_enemy("n4")
	_enemy("rifleman", Vector3(-5.5, 0.05, -143.5))
	_enemy("rifleman", Vector3(6.0, 0.05, -149.5))
	_enemy("heavy", Vector3(4.0, 0.05, -152.0))
	ifv.drive_to_z(HALT_Z[2])
	await _sleep(5.0)
	_say(SD.VOSS, "Kettengeräusche in der Seitenstraße links. Das ist kein Lkw.")
	if not await _until(func() -> bool: return ifv.arrived(), 30.0):
		return false
	_tank = _spawn_tank(Vector3(-36.0, 0, -146.0), 260.0)
	var tpath: Array[Vector3] = [Vector3(-24.0, 0, -146.0), Vector3(-13.0, 0, -146.5)]
	_tank.call("drive_path", tpath, 3.2)
	_say(SD.LENA, "Garde-Panzer! Der schluckt mehrere Treffer. Bleib mit der Kanone drauf!")
	_obj("Garde-Panzer und Panzerfaust-Fenster ausschalten")
	get_tree().create_timer(4.0, false).timeout.connect(func() -> void:
		if _tank != null and is_instance_valid(_tank) and _alive(_tank) and ifv != null and is_instance_valid(ifv):
			_tank.call("set_target", ifv))
	await _sleep(6.0)
	_say(SD.FALK, "Kerner. Wir hatten noch nicht das Vergnügen. Nicht direkt.")
	_say(SD.FALK, "Ich beobachte Sie seit der Ausstrahlung. Rostock, die Alpen, der Traunsee. Beeindruckend, für einen Unteroffizier.")
	_say(SD.FALK, "Oberst Falk. Garde. Merken Sie sich den Namen.")
	_say(SD.LENA, "Ignorier ihn. Panzer zuerst!")
	var req: Array = [n3, n4, _tank]
	var said := [false]
	var watch := func() -> bool:
		if not said[0] and not _alive(req[2]):
			said[0] = true
			_say(SD.VOSS, "Panzer brennt!")
		return _all_dead(req)
	var ok: bool = await _until(watch, 90.0)
	if not ok:
		return false
	if not await _clear(req, 1.0):
		return false
	await _mop_up(10.0)
	if _failed != "":
		return false
	_after_clear()
	return true

func _spawn_tank(pos: Vector3, hp: float) -> Node3D:
	var t := (load(TANK_SCENE) as PackedScene).instantiate() as Node3D
	t.set("faction", "reich")
	t.set("max_health", hp)
	t.set("fire_interval", 7.0)
	t.set("aim_time", 1.8)
	t.set("miss_min", 2.0)
	t.set("miss_max", 4.5)
	t.set("shell_damage", 45.0)
	t.name = "GardePanzer"
	add_child(t)
	t.global_position = pos
	t.rotation.y = -PI / 2.0
	_phase_nodes.append(t)
	if ifv != null:
		ifv.extra_targets.append(t)
	return t

# --- Halt 3: Hubschrauber ueber dem Uferplatz

func _p3() -> bool:
	var n5 := _nest_enemy("n5")
	_enemy("rifleman", Vector3(-6.0, 0.05, -233.5))
	_enemy("rifleman", Vector3(6.5, 0.05, -239.5))
	_enemy("assault", Vector3(0.0, 0.05, -244.0))
	_enemy("heavy", Vector3(-4.0, 0.05, -249.0))
	ifv.drive_to_z(HALT_Z[3])
	await _sleep(4.0)
	if not await _until(func() -> bool: return ifv.arrived(), 30.0):
		return false
	_heli = (load(HELI_SCENE) as PackedScene).instantiate() as Node3D
	_heli.set("faction", "reich")
	_heli.set_meta("faction", "reich")
	_heli.set("max_health", 420.0)
	_heli.set("mg_damage", 6.0)
	_heli.name = "GardeHubschrauber"
	add_child(_heli)
	_heli.global_position = Vector3(60.0, 34.0, -280.0)
	_phase_nodes.append(_heli)
	ifv.extra_targets.append(_heli)
	var hp: Array[Vector3] = [Vector3(-18.0, 26.0, -232.0), Vector3(16.0, 28.0, -252.0), Vector3(22.0, 30.0, -218.0), Vector3(-22.0, 27.0, -220.0)]
	_heli.call("fly_path", hp, 13.0, true)
	_say(SD.LENA, "Hubschrauber über dem Ufer! Hoch mit dem Rohr!")
	_obj("Hubschrauber und letztes Fenster ausschalten")
	await _sleep(3.0)
	if _heli != null and is_instance_valid(_heli) and _alive(_heli):
		_heli.call("attack", true)
	_say(SD.FALK, "Sie fahren genau dorthin, wo ich Sie haben will, Kerner.")
	var req: Array = [n5, _heli]
	var said := [false]
	var watch := func() -> bool:
		if not said[0] and not _alive(req[1]):
			said[0] = true
			_say(SD.VOSS, "Der Vogel ist unten!")
		return _all_dead(req)
	var ok: bool = await _until(watch, 90.0)
	if not ok:
		return false
	if not await _clear(req, 1.0):
		return false
	await _mop_up(8.0)
	if _failed != "":
		return false
	_after_clear()
	return true

# --- Brueckenkopf: Treffer, Ausstieg

func _p4_dismount() -> void:
	_rpg.clear()
	ifv.extra_targets.clear()
	_far_tank = _spawn_tank(Vector3(8.0, 0, -380.0), 300.0)
	_far_tank.rotation.y = PI
	_far_tank.call("set_target", null)
	ifv.extra_targets.erase(_far_tank)
	_say(SD.VOSS, "Moltkebrücke voraus. Sieht leer aus. Zu leer.")
	ifv.drive_to_z(HALT_Z[4], 4.5)
	await _until(func() -> bool: return ifv.global_position.z < HALT_Z[4] + 6.0 or ifv.arrived(), 25.0)
	if not is_inside_tree():
		return
	# Treffer aus dem Hinterhalt am anderen Ufer (inszeniert, kein Neustart)
	var muzzle := _far_tank.global_position + Vector3(0, 2.3, 4.0)
	var hitp := ifv.global_position + Vector3(0.6, 1.4, -3.0)
	VF.tracer(self, muzzle, hitp, 900.0, "orange", 3.0)
	VF.play_at(self, "veh_tank_cannon", muzzle, 6.0, 40.0, 900.0)
	await get_tree().create_timer(0.16, false).timeout
	VFX.spawn_explosion(hitp, 2.6)
	VF.play_at(self, "veh_tank_explode", hitp, 4.0, 30.0, 600.0)
	ifv.invulnerable = false
	ifv.apply_damage(999.0, hitp, _far_tank)
	ifv.add_trauma(1.0)
	Events.story_cinematic.emit(true)
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	_say(SD.VOSS, "Treffer im Motorraum! Wir brennen! Alle raus!")
	await get_tree().create_timer(3.0, false).timeout
	if not is_inside_tree():
		return
	_wreck_ifv()
	await get_tree().process_frame
	_start_foot(false)
	await get_tree().create_timer(1.5, false).timeout
	Events.story_cinematic.emit(false)
	_say(SD.LENA, "Kerner! Kerner, melde dich!")
	_say(SD.KERNER, "Ich lebe. Der Rabe nicht.")
	_say(SD.FALK, "Aussteigen, Kerner. So ist es ehrlicher.")
	_say(SD.LENA, "Panzer am anderen Ufer. Runter vom Präsentierteller, in die Deckung auf der Brücke!")

func _wreck_ifv() -> void:
	if ifv == null or not is_instance_valid(ifv):
		return
	var w := ifv.make_wreck(world)
	var c := ifv.get_camera()
	if c != null and is_instance_valid(c):
		c.current = false
		c.queue_free()
	Props.fire(world, w.global_position + Vector3(0, 2.2, 1.5), 1.8, true, 4.0, 7.0)
	Props.fire(world, w.global_position + Vector3(0.5, 1.2, -2.5), 1.0, true, 2.5, 4.0)
	VFX.spawn_dust_cloud(w.global_position + Vector3.UP, 6.0)
	ifv.remove_from_group("player")
	ifv.remove_from_group("damageable")
	ifv.queue_free()
	ifv = null
	player = null

# ================================================================== Zu Fuss: Bruecke nehmen

func _start_foot(debug_start: bool) -> void:
	_on_foot = true
	phase = 5
	_foot_t = 0.0
	if debug_start:
		_far_tank = _spawn_tank(Vector3(8.0, 0, -380.0), 300.0)
		_far_tank.rotation.y = PI
		_far_tank.call("set_target", null)
	_spawn_player()
	if player != null and player.has_method("set_view"):
		player.call("set_view", 0.0, 0.0)
	_checkpoint("cp_dismount")
	_obj("Die Moltkebrücke zu Fuß nehmen")
	Pickup.place_pzf_set(self, Vector3(6.5, 0.0, -236.0), 90.0)
	Pickup.place_ammo_crate(self, Vector3(-5.0, 0.0, -240.0), 90.0)
	# Bruecke: Garde-Infanterie, gepanzerter Trupp, Juggernaut vor dem anderen Ufer
	_enemy("rifleman", Vector3(-3.0, 0.05, -276.0))
	_enemy("rifleman", Vector3(4.0, 0.05, -284.0))
	_enemy("assault", Vector3(-2.5, 0.05, -296.0))
	_enemy("rifleman", Vector3(4.5, 0.05, -306.0))
	_enemy("heavy", Vector3(-3.5, 0.05, -317.0))
	_enemy("armored", Vector3(2.5, 0.05, -328.0))
	_enemy("marksman", Vector3(-7.0, 0.05, -361.0))
	_enemy("rifleman", Vector3(7.0, 0.05, -363.0))
	_trigger("SpreeBoss", Vector3(0, 3, -300.0), Vector3(16, 6, 2), _spawn_boss)
	_trigger("SpreeCheckpoint", Vector3(0, 3, -312.0), Vector3(16, 6, 2), func() -> void: _checkpoint("cp_bridge_mid"))
	# Voss erledigt den Panzer mit der letzten Panzerfaust
	get_tree().create_timer(16.0, false).timeout.connect(_voss_rocket)

func _voss_rocket() -> void:
	if _far_tank == null or not is_instance_valid(_far_tank) or not _alive(_far_tank):
		return
	_say(SD.VOSS, "Ich hab noch eine Panzerfaust aus dem Rabe. Kopf runter!")
	await get_tree().create_timer(2.5, false).timeout
	if not is_instance_valid(_far_tank) or not _alive(_far_tank):
		return
	var from := Vector3(-4.0, 1.6, -244.0)
	var dir := (_far_tank.global_position + Vector3(0, 1.4, 0) - from).normalized()
	Rocket.launch(self, from, dir, 90.0, null)
	await get_tree().create_timer(2.0, false).timeout
	if is_instance_valid(_far_tank) and _alive(_far_tank):
		_far_tank.call("destroy")
	_say(SD.VOSS, "Panzer ist erledigt. Für dich, Rabe.")

func _spawn_boss() -> void:
	if _boss != null:
		return
	_boss = _enemy("juggernaut", Vector3(0.0, 0.05, -346.0))
	_say(SD.LENA, "Schwere Panzerung auf der Brücke! Das ist ein Juggernaut. Panzerfaust, Kerner!")

func _foot_tick() -> void:
	if _finale_started:
		return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return
	# Notnagel gegen Haenger: nach langer Zeit greift Lenas Trupp ein
	if _foot_t > 260.0 and not _assist_done and _boss != null and _alive(_boss):
		_assist_done = true
		_say(SD.LENA, "Wir sind bei dir! Alles auf den Koloss!")
		_kill(_boss)
	if _boss == null and pl.global_position.z < -300.0:
		_spawn_boss()
	var boss_dead := _boss != null and not _alive(_boss)
	if boss_dead and pl.global_position.z < -356.0:
		_finale_started = true
		_finale()

func _finale() -> void:
	_done = true
	for e in get_tree().get_nodes_in_group("enemy"):
		if _alive(e) and (e as Node3D).global_position.distance_to(Vector3(0, 0, end_z)) < 60.0:
			_kill(e)
	_say(SD.LENA, "Brücke gehalten. Die Bataillone rücken nach. Kerner, wir stehen am Spreebogen.")
	_say(SD.FALK, "Ein Brückenkopf. Wie rührend. Wir sehen uns, Kerner.")
	_say(SD.VOSS, "Der Rabe hat uns bis hierher gebracht. Den Rest holen wir uns zu Fuß.")
	await _sleep(9.0)
	_on_level_end()

## Pausenmenue: "Checkpoint laden".
func menu_reload_checkpoint() -> void:
	if _on_foot:
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("respawn"):
			pl.call("respawn")
		return
	if phase >= 1 and phase <= 3:
		_fail("menu")
