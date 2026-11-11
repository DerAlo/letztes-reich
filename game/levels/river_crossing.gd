extends "res://game/levels/level.gd"
## Level 3 "Die Bruecke" (river_crossing): Welikaja bei Pskow, 22.03.2030, 05:50 – Morgengrauen,
## Gewitter, Starkregen. Die EU-Kampfgruppe nimmt die Strassenbruecke nach Osten.
## Abschnitt 1: Westufer mit Uferstrasse, Schuetzengraeben, ausgebrannten Fahrzeugen (Welle 0).
## Abschnitt 2: Stahlfachwerkbruecke unter Feuer – Kampfhubschrauber (abschiessbar, stuerzt in den Fluss),
##              hinter dem Spieler bricht das erste Brueckenfeld ein (Wellen 1/2).
## Abschnitt 3: Ostufer – Panzer blockiert den Brueckenkopf (Sprengladung), Haeuser, Fabrik (Welle 3).
## Fahrzeuge aus game/vehicles/ werden optional geladen; ohne sie greifen einfache Ersatzloesungen.

const RP = preload("res://game/levels/river_props.gd")
const Bridge = preload("res://game/levels/river_bridge.gd")
const RiverFx = preload("res://game/levels/river_fx.gd")

const HDRI := "res://assets/environment/river/overcast_soil_puresky_2k.hdr"
const HELI_PATH := "res://game/vehicles/helicopter.tscn"
const TANK_PATH := "res://game/vehicles/tank.tscn"
const CHARGE_PATH := "res://game/vehicles/demo_charge.tscn"
const JET_PATH := "res://game/vehicles/jet_flyby.tscn"

const BRIDGE_Z0 := -64.0       ## Westwiderlager (Deckbeginn)
const BRIDGE_Z1 := -188.0      ## Ostwiderlager
const PIER_A := -105.0
const PIER_B := -146.0
const WATER_Y := -9.0
const BANK_DROP := 11.0        ## Boeschung: 11 m Hoehe auf 12 m Laenge
const BANK_RUN := 12.0
const TRENCHES: Array = [-22.0, -44.0]
const TRENCH_HW := 1.1
const TRENCH_DEPTH := 1.3
const TANK_POS := Vector3(1.5, 0.0, -207.0)
const TANK_START := Vector3(1.5, 0.0, -228.0)
const GATE_Z := -232.0

## Bot-Route (x, z). Gerade Linien muessen frei begehbar sein.
const ROUTE: Array = [
	Vector2(0.0, 9.0), Vector2(1.2, -8.0), Vector2(-1.6, -28.0), Vector2(0.4, -48.0), Vector2(0.0, -61.0),
	Vector2(0.0, -76.0), Vector2(0.0, -92.0), Vector2(0.0, -108.0), Vector2(0.0, -126.0), Vector2(0.2, -146.0),
	Vector2(-1.0, -162.0), Vector2(-1.4, -178.0), Vector2(-2.3, -192.0), Vector2(-2.3, -201.0),
	Vector2(-2.3, -207.6), Vector2(-2.3, -218.0), Vector2(-2.0, -229.0), Vector2(-1.0, -244.0),
	Vector2(0.0, -262.0), Vector2(0.0, -280.0), Vector2(0.0, -293.0)]

@export var storm_sky_energy: float = 0.42
@export var storm_fog: float = 0.022

var fx: Node3D
var water_mat: ShaderMaterial
var span1: AnimatableBody3D
var heli: Node3D = null
var tank: Node3D = null
var charge: Node3D = null
var _env: Environment
var _sun: DirectionalLight3D
var _gate: StaticBody3D
var _heli_started: bool = false
var _heli_down: bool = false
var _collapsed: bool = false
var _tank_started: bool = false
var _tank_dead: bool = false
var _sunrise_done: bool = false
var _tank_t0: int = 0

func _init() -> void:
	level_name = "river_crossing"
	end_z = -296.0
	build_seed = 2203
	_wave_count = 4
	ambient_artillery = true

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Die Bruecke"
	return info

## Set-Piece fuer Tests/Touren: Brueckenfeld 1 einstuerzen lassen.
func trigger_setpiece() -> void:
	_collapse()

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(storm_fog, 1.0)
	if ResourceLoader.exists(HDRI):
		var sky := Sky.new()
		var sm := PanoramaSkyMaterial.new()
		sm.panorama = load(HDRI)
		sm.energy_multiplier = 1.0
		sky.sky_material = sm
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		env.sky = sky
		env.sky_rotation = Vector3(0, deg_to_rad(200.0), 0)
	env.background_energy_multiplier = storm_sky_energy
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.75
	env.ambient_light_color = Color(0.36, 0.42, 0.52)
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.0
	env.sdfgi_energy = 0.8
	env.ssr_max_steps = 64
	env.ssr_fade_out = 1.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.34, 0.4)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.75
	env.fog_aerial_perspective = 0.35
	env.volumetric_fog_density = storm_fog
	env.volumetric_fog_albedo = Color(0.66, 0.72, 0.8)
	env.volumetric_fog_emission = Color(0.018, 0.022, 0.03)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.3
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_sky_affect = 0.6
	env.glow_hdr_threshold = 1.1
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.78
	env.adjustment_contrast = 1.08
	env.adjustment_brightness = 1.0
	_env = env
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	# Kaltes Daemmerlicht von Nordost durch die Wolkendecke (flach, weich)
	_sun = DirectionalLight3D.new()
	_sun.name = "Dawn"
	_sun.light_color = Color(0.62, 0.7, 0.86)
	_sun.light_energy = 0.75
	_sun.light_indirect_energy = 1.2
	_sun.light_volumetric_fog_energy = 0.7
	_sun.light_angular_distance = 4.0
	_sun.shadow_enabled = true
	_sun.shadow_blur = 2.5
	_sun.shadow_bias = 0.04
	_sun.shadow_normal_bias = 1.2
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.directional_shadow_max_distance = 140.0
	_sun.transform = Transform3D(Basis.looking_at(Vector3(-0.45, -0.42, 0.79).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(_sun)
	VfxEnv.apply_render_quality(get_viewport())

# ------------------------------------------------------------------ Gelaende

func _rect(gb: Geo.BoxBatch, body: StaticBody3D, x0: float, x1: float, z0: float, z1: float, top: float = 0.0, depth: float = 3.0) -> void:
	var c := Vector3((x0 + x1) * 0.5, top - depth * 0.5, (z0 + z1) * 0.5)
	var s := Vector3(absf(x1 - x0), depth, absf(z1 - z0))
	gb.add(c, s)
	Geo.add_box_shape(body, c, s)

## Boeschung: Flaeche faellt von (z_top, y_top) in Richtung dir (z) um BANK_DROP ab. Nur Optik.
func _slope(parent: Node3D, gb: Geo.BoxBatch, x0: float, x1: float, z_top: float, y_top: float, dir: float, drop: float = BANK_DROP, run: float = BANK_RUN) -> void:
	var a := atan2(drop, run)
	var len := sqrt(drop * drop + run * run)
	var mid := Vector3((x0 + x1) * 0.5, y_top - drop * 0.5, z_top + dir * run * 0.5)
	# Kippung: Oberflaeche zeigt zum Fluss (dir)
	var basis := Basis(Vector3.RIGHT, a * dir)
	var n := basis * Vector3.UP
	gb.add(mid - n * 0.5, Vector3(absf(x1 - x0), 1.0, len + 1.0), basis)

func _build_ground() -> void:
	var body := Geo.static_body()
	var gb := Geo.batch()
	var W := 70.0
	# Westufer, mit Aussparungen fuer die Graeben (|x| 5.5..18)
	var zs: Array = [22.0]
	for t: float in TRENCHES:
		zs.append(t + TRENCH_HW)
		zs.append(t - TRENCH_HW)
	zs.append(BRIDGE_Z0)
	for i in range(0, zs.size(), 2):
		_rect(gb, body, -W, W, zs[i + 1], zs[i])
	for t: float in TRENCHES:
		for seg: Array in [[-W, -18.0], [-5.5, 5.5], [18.0, W]]:
			_rect(gb, body, seg[0], seg[1], t - TRENCH_HW, t + TRENCH_HW)
		for seg: Array in [[-18.0, -5.5], [5.5, 18.0]]:
			_rect(gb, body, seg[0], seg[1], t - TRENCH_HW, t + TRENCH_HW, -TRENCH_DEPTH, 1.5)
	# Ostufer
	_rect(gb, body, -W, W, -340.0, BRIDGE_Z1)
	world.add_child(body)
	var gm := RP.mud()
	var mi := RP.add_batch(body, gb, gm)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Weites Land bis zum Horizont (nur Optik)
	var far := Geo.batch()
	far.add(Vector3(0, -0.16, 300.0), Vector3(1400, 0.2, 640))
	far.add(Vector3(-W - 300.0, -0.16, -100.0), Vector3(600, 0.2, 80))
	far.add(Vector3(W + 300.0, -0.16, -100.0), Vector3(600, 0.2, 80))
	far.add(Vector3(0, -0.16, BRIDGE_Z1 - 360.0), Vector3(1400, 0.2, 720))
	var fm := RP.add_batch(self, far, RP.grass())
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Uferboeschungen (unter der Bruecke flacher und tiefer, damit das Widerlager sichtbar bleibt)
	var bank := Geo.batch()
	var bx := 9.4
	for side: Array in [[-700.0, -bx], [bx, 700.0]]:
		_slope(self, bank, side[0], side[1], BRIDGE_Z0, 0.0, -1.0)
		_slope(self, bank, side[0], side[1], BRIDGE_Z1, 0.0, 1.0)
	_slope(self, bank, -bx, bx, BRIDGE_Z0 - 1.0, -3.6, -1.0, BANK_DROP - 3.6, 8.0)
	_slope(self, bank, -bx, bx, BRIDGE_Z1 + 1.0, -3.6, 1.0, BANK_DROP - 3.6, 8.0)
	var bmi := RP.add_batch(self, bank, RP.mud())
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Ufersteine an der Wasserlinie
	var stones := Geo.batch()
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 5
	for k in 260:
		var west := k % 2 == 0
		var x := srng.randf_range(-160.0, 160.0)
		if absf(x) < 8.0:
			continue
		var zl := BRIDGE_Z0 - BANK_RUN * (-WATER_Y / BANK_DROP) if west else BRIDGE_Z1 + BANK_RUN * (-WATER_Y / BANK_DROP)
		var z := zl + srng.randf_range(-1.5, 2.5) * (1.0 if west else -1.0)
		var s := srng.randf_range(0.5, 1.8)
		stones.add_ball(Vector3(x, WATER_Y + srng.randf_range(-0.2, 0.3), z), Vector3(s * 1.3, s * 0.7, s), Basis(Vector3.UP, srng.randf() * TAU))
	RP.add_batch(self, stones, RP.rocks())
	_build_river()
	_build_bounds()

func _build_river() -> void:
	var pm := PlaneMesh.new()
	var zc := (BRIDGE_Z0 + BRIDGE_Z1) * 0.5
	var depth := (BRIDGE_Z0 - BRIDGE_Z1) + 40.0
	pm.size = Vector2(1400.0, depth)
	pm.subdivide_width = 280
	pm.subdivide_depth = 48
	var piers: Array = [
		Vector4(-5.5, WATER_Y, PIER_A, 1.7), Vector4(5.5, WATER_Y, PIER_A, 1.7), Vector4(0.0, WATER_Y, PIER_A, 1.9),
		Vector4(-5.5, WATER_Y, PIER_B, 1.7), Vector4(5.5, WATER_Y, PIER_B, 1.7), Vector4(0.0, WATER_Y, PIER_B, 1.9)]
	water_mat = RP.water_mat(piers)
	water_mat.set_shader_parameter("shore_z_a", BRIDGE_Z0 - BANK_RUN * (-WATER_Y / BANK_DROP))
	water_mat.set_shader_parameter("shore_z_b", BRIDGE_Z1 + BANK_RUN * (-WATER_Y / BANK_DROP))
	var water := MeshInstance3D.new()
	water.name = "River"
	water.mesh = pm
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.position = Vector3(0, WATER_Y, zc)
	add_child(water)
	# Wasser-Kollider (Layer Welt) mit Oberflaechen-Meta, nicht im Navmesh (haengt am Level-Root)
	var wb := StaticBody3D.new()
	wb.name = "WaterBody"
	wb.collision_layer = 1
	wb.collision_mask = 0
	wb.set_meta("surface", "water")
	Geo.add_box_shape(wb, Vector3(0, WATER_Y - 0.5, zc), Vector3(1400.0, 1.0, depth))
	add_child(wb)
	# Wer ins Wasser faellt, ertrinkt (Sicherheitsnetz)
	var kill := Area3D.new()
	kill.name = "RiverKill"
	kill.collision_layer = 0
	kill.collision_mask = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400.0, 2.0, depth - 24.0)
	cs.shape = bs
	kill.add_child(cs)
	kill.position = Vector3(0, WATER_Y + 0.6, zc)
	kill.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player") and b.has_method("take_damage"):
			b.call("take_damage", 9999.0, null, b.global_position, Vector3.UP))
	add_child(kill)
	# Flussbett-Dunkel unter dem Wasser (verhindert Durchblick bei flachen Winkeln)
	var bed := Geo.box_mesh_node(Vector3(1400.0, 0.5, depth), Geo.flat(Color(0.02, 0.025, 0.02), 1.0), Vector3(0, Bridge.BED_Y, zc))
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)

func _build_bounds() -> void:
	# Westufer
	for sx: float in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 20.0, 6.0, -20.0), Vector3(1.0, 14.0, 90.0))
		_invisible_wall(Vector3(sx * 13.2, 6.0, BRIDGE_Z0 - 0.4), Vector3(13.6, 14.0, 1.0))
		# Ostufer: Gasse zwischen den Haeusern
		_invisible_wall(Vector3(sx * 11.6, 6.0, -246.0), Vector3(1.0, 14.0, 118.0))
		_invisible_wall(Vector3(sx * 9.2, 6.0, BRIDGE_Z1 + 0.4), Vector3(5.6, 14.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, 16.0), Vector3(42.0, 14.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, end_z - 6.0), Vector3(26.0, 14.0, 1.0))

# ------------------------------------------------------------------ Strassen, Bruecke, Haeuser

func _build_street() -> void:
	# Fahrbahn (Optik ueber dem Boden, Kollision liefert der Boden)
	var road := Geo.batch()
	road.add(Vector3(0, 0.012, (22.0 + BRIDGE_Z0) * 0.5), Vector3(11.0, 0.03, 22.0 - BRIDGE_Z0))
	road.add(Vector3(0, 0.012, (BRIDGE_Z1 - 300.0) * 0.5), Vector3(11.0, 0.03, BRIDGE_Z1 + 300.0 + 0.0))
	var rm := RP.add_batch(world, road, RP.road(), false)
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Mittellinie (ausgeblichen, unterbrochen)
	var lines := Geo.batch()
	var z := 20.0
	while z > -300.0:
		if z > BRIDGE_Z0 + 2.0 or z < BRIDGE_Z1 - 2.0 or (z < BRIDGE_Z0 and z > BRIDGE_Z1):
			lines.add(Vector3(0, 0.03 if (z > BRIDGE_Z0 or z < BRIDGE_Z1) else 0.006, z), Vector3(0.14, 0.01, 3.0))
		z -= 7.0
	var lm := RP.add_batch(world, lines, RP.flat_wet(Color(0.55, 0.53, 0.45), 0.3), false)
	lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Bordsteine an den Uferstrassen
	var curbs := Geo.batch()
	for sx: float in [-1.0, 1.0]:
		curbs.add(Vector3(sx * 5.6, 0.07, (22.0 + BRIDGE_Z0) * 0.5), Vector3(0.22, 0.14, 22.0 - BRIDGE_Z0))
		curbs.add(Vector3(sx * 5.6, 0.07, (BRIDGE_Z1 - 300.0) * 0.5), Vector3(0.22, 0.14, -(BRIDGE_Z1 + 300.0) * -1.0))
	RP.add_batch(world, curbs, RP.concrete(Color(0.55, 0.55, 0.53)), false)
	_build_bridge()
	_build_houses()

func _build_bridge() -> void:
	var brng := RandomNumberGenerator.new()
	brng.seed = build_seed + 11
	# Feld 1: beweglich (Einsturz), Drehpunkt am Westwiderlager
	span1 = AnimatableBody3D.new()
	span1.name = "Span1"
	span1.sync_to_physics = false
	span1.collision_layer = 1
	span1.collision_mask = 0
	span1.position = Vector3(0, 0, BRIDGE_Z0)
	world.add_child(span1)
	Bridge.build_span(span1, span1, 0.0, PIER_A - BRIDGE_Z0, brng, true)
	# Felder 2 und 3: fest
	var fixed := Geo.static_body()
	fixed.name = "Spans23"
	world.add_child(fixed)
	Bridge.build_span(fixed, fixed, PIER_A, PIER_B, brng, true)
	Bridge.build_span(fixed, fixed, PIER_B, BRIDGE_Z1, brng, false)
	Bridge.pier(world, PIER_A)
	Bridge.pier(world, PIER_B)
	Bridge.abutment(world, BRIDGE_Z0, 1.0)
	Bridge.abutment(world, BRIDGE_Z1, -1.0)
	# Schild am Brueckenkopf
	var sign_b := Geo.batch()
	sign_b.add(Vector3(-7.4, 1.2, BRIDGE_Z0 + 3.0), Vector3(0.08, 2.4, 0.08))
	sign_b.add(Vector3(-7.4, 2.4, BRIDGE_Z0 + 3.0), Vector3(0.05, 0.6, 1.6))
	RP.add_batch(world, sign_b, RP.steel(Color(0.3, 0.32, 0.3)))
	var lbl := Label3D.new()
	lbl.text = "р. ВЕЛИКАЯ"
	lbl.font_size = 64
	lbl.pixel_size = 0.004
	lbl.modulate = Color(0.85, 0.85, 0.82)
	lbl.position = Vector3(-7.36, 2.4, BRIDGE_Z0 + 3.0)
	lbl.rotation_degrees.y = 90.0
	lbl.shaded = true
	world.add_child(lbl)

## Ausgebrannte/verlassene Fahrzeuge und Sperren auf der Bruecke. Feld 1-Objekte haengen am Feld.
func _build_bridge_props() -> void:
	var dark := Color(0.2, 0.22, 0.2)
	# Feld 1 (lokal, Ursprung bei z = BRIDGE_Z0)
	Props.vehicle(span1, Vector3(-3.3, 0.0, -18.0), 168.0, "car", Color(0.4, 0.1, 0.08), true, false, [])
	Props.vehicle(span1, Vector3(3.6, 0.0, -31.0), 8.0, "van", Color(0.7, 0.7, 0.68), false, false, [])
	RP.model(span1, "concrete_road_barrier", Vector3(3.2, 0.0, -8.0), 84.0, 1.0, Vector3(0.64, 0.83, 1.55))
	# Feld 2
	Props.vehicle(world, Vector3(-3.5, 0.0, -113.0), -24.0, "car", Color(0.18, 0.25, 0.35), true, false, covers)
	Props.vehicle(world, Vector3(3.1, 0.0, -125.0), 6.0, "bus", Color(0.75, 0.55, 0.15), true, false, covers)
	Props.fire(world, Vector3(3.1, 1.6, -121.0), 1.1, true, 2.2, 5.0)
	RP.model(world, "wooden_military_crate", Vector3(-4.2, 0.0, -136.0), 12.0, 1.0, Vector3(1.24, 0.46, 0.52), covers)
	# Feld 3: russisches MG-Nest und Sperren
	RP.sandbag_wall(world, Vector3(4.1, 0.0, -168.0), 0.0, 3.0, 3, rng, covers)
	RP.sandbag_wall(world, Vector3(5.2, 0.0, -170.0), 90.0, 3.0, 3, rng, covers)
	Props.hedgehog(world, Vector3(-4.2, 0.0, -156.0), 20.0, covers)
	Props.vehicle(world, Vector3(-4.7, 0.0, -179.0), 12.0, "car", dark, true, true, covers)
	RP.model(world, "concrete_road_barrier", Vector3(2.4, 0.0, -184.0), 4.0, 1.0, Vector3(1.55, 0.83, 0.64), covers)
	# Laternen auf dem Gehweg (Natrium, einige noch an)
	var lz: Array = [-74.0, -96.0, -116.0, -138.0, -158.0, -180.0]
	for i in lz.size():
		var z: float = lz[i]
		var sx := -1.0 if i % 2 == 0 else 1.0
		var lit := i in [1, 2, 4]
		if z > PIER_A:
			Props.lamp(span1, Vector3(sx * 5.85, 0.18, z - BRIDGE_Z0), -90.0 * sx, lit, 0.0)
		else:
			Props.lamp(world, Vector3(sx * 5.85, 0.18, z), -90.0 * sx, lit, 3.0 if i == 5 else 0.0)

func _build_houses() -> void:
	var hrng := RandomNumberGenerator.new()
	hrng.seed = build_seed + 21
	# Westufer: Plattenbauten und Ziegelhaeuser an der Uferstrasse
	RP.building(world, Vector3(-30.0, 0, 4.0), 90.0, Vector3(24.0, 5.0, 12.0), hrng, {"tint": Color(0.72, 0.7, 0.64), "lit": 0.06, "burnt": 0.06})
	RP.building(world, Vector3(30.0, 0, -6.0), -90.0, Vector3(20.0, 4.0, 12.0), hrng, {"tint": Color(0.66, 0.62, 0.56), "damage": 0.5, "burnt": 0.1})
	RP.building(world, Vector3(-28.0, 0, -32.0), 90.0, Vector3(16.0, 3.0, 11.0), hrng, {"brick": true, "tint": Color(0.75, 0.62, 0.55), "damage": 0.6, "burnt": 0.15})
	RP.building(world, Vector3(29.0, 0, -38.0), -90.0, Vector3(14.0, 2.0, 10.0), hrng, {"brick": true, "tint": Color(0.7, 0.6, 0.55), "shop": true, "lit": 0.0})
	# Ostufer: Haeuserzeilen links/rechts der Strasse bis zur Fabrik
	RP.building(world, Vector3(-18.0, 0, -214.0), 90.0, Vector3(16.0, 3.0, 11.0), hrng, {"brick": true, "tint": Color(0.8, 0.68, 0.6), "damage": 0.45, "burnt": 0.2})
	RP.building(world, Vector3(18.5, 0, -218.0), -90.0, Vector3(20.0, 4.0, 12.0), hrng, {"tint": Color(0.62, 0.64, 0.6), "lit": 0.05, "burnt": 0.12})
	RP.building(world, Vector3(-18.5, 0, -243.0), 90.0, Vector3(22.0, 5.0, 12.0), hrng, {"tint": Color(0.7, 0.66, 0.6), "shop": true, "lit": 0.1, "burnt": 0.08})
	RP.building(world, Vector3(18.0, 0, -248.0), -90.0, Vector3(18.0, 3.0, 11.0), hrng, {"brick": true, "tint": Color(0.72, 0.58, 0.52), "damage": 0.4, "burnt": 0.15})
	RP.building(world, Vector3(-18.0, 0, -271.0), 90.0, Vector3(18.0, 4.0, 11.0), hrng, {"tint": Color(0.6, 0.6, 0.62), "lit": 0.04, "burnt": 0.1, "damage": 0.3})
	# Fabrik am Ende (Fabrikkante quer zur Strasse) + Nebenhalle
	RP.factory(world, Vector3(0.0, 0, -318.0), 0.0, Vector3(64.0, 13.0, 30.0), hrng)
	RP.factory(world, Vector3(21.0, 0, -276.0), -90.0, Vector3(26.0, 9.0, 16.0), hrng)
	RP.chimney(world, Vector3(-22.0, 0, -326.0), 46.0)

func _build_props() -> void:
	var prng := RandomNumberGenerator.new()
	prng.seed = build_seed + 41
	# Westufer: ausgebrannte Fahrzeuge
	Props.vehicle(world, Vector3(3.4, 0.0, -11.0), 14.0, "car", Color(0.3, 0.32, 0.35), true, false, covers)
	Props.vehicle(world, Vector3(-4.5, 0.0, -36.0), -8.0, "truck", Color(0.3, 0.33, 0.25), true, false, covers)
	Props.vehicle(world, Vector3(-11.0, 0.0, 2.0), 75.0, "car", Color(0.55, 0.12, 0.1), true, false, covers)
	Props.vehicle(world, Vector3(11.5, 0.0, -14.0), 100.0, "van", Color(0.75, 0.75, 0.72), false, false, covers)
	Props.tank_wreck(world, Vector3(12.0, 0.0, -54.0), 160.0, covers)
	Props.fire(world, Vector3(-4.5, 1.8, -37.5), 1.3, true, 2.5, 6.0)
	Props.fire(world, Vector3(12.0, 2.0, -53.0), 1.0, true, 2.0, 5.0)
	# Graeben mit Wellblech und Sandsaecken
	for t: float in TRENCHES:
		RP.trench_dressing(world, Vector3(-18.0, 0, t), Vector3(-5.8, 0, t), TRENCH_HW * 2.0, TRENCH_DEPTH, prng, covers)
		RP.trench_dressing(world, Vector3(5.8, 0, t), Vector3(18.0, 0, t), TRENCH_HW * 2.0, TRENCH_DEPTH, prng, covers)
	# Betonsperren-Schikane vor der Bruecke
	RP.model(world, "concrete_road_barrier", Vector3(-3.3, 0.0, -54.0), 2.0, 1.0, Vector3(1.55, 0.83, 0.64), covers)
	RP.model(world, "concrete_road_barrier", Vector3(-4.8, 0.0, -54.3), -4.0, 1.0, Vector3(1.55, 0.83, 0.64), covers)
	RP.model(world, "concrete_road_barrier", Vector3(3.5, 0.0, -58.0), 3.0, 1.0, Vector3(1.55, 0.83, 0.64), covers)
	RP.model(world, "concrete_road_barrier", Vector3(4.9, 0.0, -57.8), -2.0, 1.0, Vector3(1.55, 0.83, 0.64), covers)
	# Kleinkram am Strassenrand
	var small: Array = [
		["Barrel_01", Vector3(-6.4, 0, -5.0), Vector3(0.56, 0.88, 0.56)], ["Barrel_01", Vector3(-6.9, 0, -5.6), Vector3(0.56, 0.88, 0.56)],
		["wooden_military_crate", Vector3(6.6, 0, -26.0), Vector3(1.24, 0.46, 0.52)], ["wooden_military_crate", Vector3(6.8, 0.46, -26.1), Vector3.ZERO],
		["metal_jerrycan_green", Vector3(6.2, 0, -27.0), Vector3.ZERO], ["trashbag", Vector3(-6.3, 0, -16.0), Vector3.ZERO],
		["trashbag", Vector3(-6.7, 0, -16.5), Vector3.ZERO], ["utility_box_01", Vector3(-6.4, 0, -40.0), Vector3(0.52, 1.12, 0.43)],
		["cement_bag", Vector3(4.4, 0, -46.0), Vector3.ZERO], ["dead_tree_trunk", Vector3(9.0, 0, 6.0), Vector3.ZERO],
		["Barrel_01", Vector3(-6.4, 0, -214.0), Vector3(0.56, 0.88, 0.56)], ["wooden_military_crate", Vector3(6.4, 0, -236.0), Vector3(1.24, 0.46, 0.52)],
		["metal_jerrycan_green", Vector3(-6.0, 0, -236.0), Vector3.ZERO], ["utility_box_01", Vector3(6.6, 0, -258.0), Vector3(0.52, 1.12, 0.43)],
		["trashbag", Vector3(-6.4, 0, -264.0), Vector3.ZERO], ["Barrel_01", Vector3(7.0, 0, -284.0), Vector3(0.56, 0.88, 0.56)],
	]
	for s: Array in small:
		RP.model(world, s[0], s[1], prng.randf_range(0.0, 360.0), 1.0, s[2])
	for i in 6:
		var p := Vector3(prng.randf_range(-9.0, -6.5) if i % 2 == 0 else prng.randf_range(6.5, 9.0), 0.3, prng.randf_range(-50.0, 0.0))
		var t := RP.model(self, "old_tyre", p, prng.randf_range(0, 360))
		if t != null:
			t.rotation_degrees.x = 90.0
			t.position.y = 0.09
	# Felsbrocken auf den Boeschungen
	for x: float in [-26.0, 24.0, -60.0, 52.0]:
		RP.model(self, "rock_moss_set_01", Vector3(x, -6.0, BRIDGE_Z0 - 6.5), prng.randf_range(0, 360), 1.4)
		RP.model(self, "rock_moss_set_01", Vector3(x + 7.0, -6.0, BRIDGE_Z1 + 6.5), prng.randf_range(0, 360), 1.4)
	# Laternen Uferstrasse
	for z: float in [6.0, -18.0, -42.0]:
		Props.lamp(world, Vector3(-6.2, 0, z), 90.0, z == -18.0)
		Props.lamp(world, Vector3(6.2, 0, z - 12.0), -90.0, false, 4.0)
	for z: float in [-200.0, -224.0, -250.0, -276.0]:
		Props.lamp(world, Vector3(-6.3 if z != -224.0 else 6.3, 0, z), 90.0 if z != -224.0 else -90.0, z in [-224.0, -276.0])
	_build_bridge_props()
	_build_east_bank(prng)

func _build_east_bank(prng: RandomNumberGenerator) -> void:
	# Russische Stellungen am Brueckenkopf
	RP.sandbag_wall(world, Vector3(-7.0, 0, -197.0), 0.0, 5.0, 3, prng, covers)
	RP.sandbag_wall(world, Vector3(7.5, 0, -199.0), 0.0, 4.0, 3, prng, covers)
	Props.hedgehog(world, Vector3(9.5, 0, -193.5), 10.0, covers)
	Props.hedgehog(world, Vector3(-9.8, 0, -193.0), -15.0, covers)
	# Sperrlinie neben dem Panzer (Gasse links bei x -4.0 .. -0.25)
	Props.vehicle(world, Vector3(-8.0, 0, -207.5), 92.0, "truck", Color(0.25, 0.28, 0.22), true, false, covers)
	RP.model(world, "concrete_road_barrier", Vector3(-4.6, 0, -210.5), 80.0, 1.0, Vector3(0.64, 0.83, 1.55))
	Props.vehicle(world, Vector3(6.9, 0, -207.0), 88.0, "van", Color(0.3, 0.33, 0.27), true, false, covers)
	Props.hedgehog(world, Vector3(10.4, 0, -210.0), 30.0, covers)
	Props.fire(world, Vector3(-8.0, 1.8, -207.5), 1.2, true, 2.4, 6.0)
	# Strassengefecht-Deckungen weiter hinten
	RP.sandbag_wall(world, Vector3(6.6, 0, -252.0), 0.0, 2.6, 2, prng, covers)
	RP.sandbag_wall(world, Vector3(-5.5, 0, -266.0), 0.0, 3.0, 2, prng, covers)
	Props.vehicle(world, Vector3(4.6, 0, -240.0), -170.0, "car", Color(0.5, 0.5, 0.52), true, false, covers)
	Props.vehicle(world, Vector3(-4.5, 0, -282.0), 15.0, "van", Color(0.2, 0.25, 0.3), true, true, covers, 0.0)
	Props.rubble(world, Vector3(-9.0, 0, -228.0), 2.4, 1.2, prng, true, covers)
	Props.rubble(world, Vector3(9.0, 0, -262.0), 2.0, 1.0, prng, true, covers)
	Props.fire(world, Vector3(-4.5, 1.0, -282.0), 1.0, true, 1.8, 5.0)

# ------------------------------------------------------------------ Marker / Trigger / Story

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.0, 0.05, 10.0), "player_spawn")
	ps.name = "PlayerSpawn"
	# Gegner: [typ, welle, x, y, z]
	var spawns: Array = [
		["rifleman", 0, -8.0, 0.05, -49.0], ["rifleman", 0, 8.5, 0.05, -50.5], ["rifleman", 0, 11.0, 0.05, -30.0],
		["rifleman", 0, -3.0, 0.05, -60.0], ["marksman", 0, 2.6, 0.05, -70.0],
		["rifleman", 1, -3.4, 0.05, -131.0], ["rifleman", 1, 3.6, 0.05, -140.0], ["drone", 1, 0.0, 7.0, -125.0],
		["assault", 2, 3.4, 0.05, -171.0], ["rifleman", 2, -3.0, 0.05, -184.0], ["rifleman", 2, 7.0, 0.05, -201.0],
		["rifleman", 2, -7.0, 0.05, -199.0], ["heavy", 2, 0.5, 0.05, -197.0],
		["rifleman", 3, -7.0, 0.05, -250.0], ["rifleman", 3, 7.5, 0.05, -256.0], ["officer", 3, -4.0, 0.05, -270.0],
		["heavy", 3, 3.0, 0.05, -280.0], ["drone", 3, 0.0, 8.0, -262.0], ["rifleman", 3, 8.0, 0.05, -289.0],
		["armored", 2, -4.5, 0.05, -192.0], ["armored", 3, 4.5, 0.05, -265.0],   # gepanzerte Soldaten
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, Vector3(s[2], s[3], s[4]), "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for c in covers:
		var v: Vector3 = c
		if absf(v.x) > 18.0 or v.z > 10.0:
			continue
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	for i in ROUTE.size():
		var r: Vector2 = ROUTE[i]
		var w := Geo.marker(m, Vector3(r.x, 0.05, r.y), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	var full := Vector3(60, 8, 1.5)
	_trigger("TriggerTrench", Vector3(0, 3, -24.0), full, func() -> void:
		_radio(StoryData.LENA, "Kontakt am Brueckenkopf! Die halten die Auffahrt – Deckung hinter den Wracks!", 4.5))
	_trigger("Checkpoint1", Vector3(0, 3, -60.0), full, func() -> void:
		_checkpoint("cp_westbank")
		_radio(StoryData.WEBER, "Gut so. Jetzt rueber – bleibt nicht auf dem Stahl stehen!", 4.0))
	_trigger("TriggerWave1", Vector3(0, 3, -68.0), full, func() -> void: _spawn_wave(1))
	_trigger("TriggerHeli", Vector3(0, 3, -82.0), full, _start_heli)
	_trigger("Checkpoint2", Vector3(0, 3, -112.0), full, func() -> void: _checkpoint("cp_bridge"))
	_trigger("TriggerCollapse", Vector3(0, 3, -124.0), full, _collapse)
	_trigger("TriggerWave2", Vector3(0, 3, -129.0), full, func() -> void: _spawn_wave(2))
	_trigger("TriggerTank", Vector3(0, 3, -150.0), full, func() -> void: _start_tank.call_deferred())
	_trigger("TriggerWave3", Vector3(0, 3, -216.0), full, func() -> void: _spawn_wave(3))
	_trigger("Checkpoint3", Vector3(0, 3, -236.0), full, func() -> void: _checkpoint("cp_eastbank"))
	_trigger("TriggerSunrise", Vector3(0, 3, -268.0), full, _sunrise)
	var area := _trigger("LevelEnd", Vector3(0.0, 2.0, -294.0), Vector3(14, 4, 3), _on_level_end, false)
	area.add_to_group("level_end")
	# Weiche Sperre hinter dem Panzer (faellt mit dem Panzer); nicht im Navmesh
	_gate = Geo.static_body(Vector3(0, 4.0, GATE_Z))
	_gate.name = "TankGate"
	# Panzerfaust gegen Helikopter (vor TriggerHeli) und Panzer (am Checkpoint Brücke) + Munitionskiste
	Pickup.place_pzf_set(self, Vector3(4.5, 0.0, -63.0), 90.0)
	Pickup.place_pzf_set(self, Vector3(-3.6, 0.0, -110.0), -90.0)
	Pickup.place_ammo_crate(self, Vector3(-4.5, 0.0, -58.0), 90.0)
	Geo.add_box_shape(_gate, Vector3.ZERO, Vector3(24.0, 8.0, 1.0))
	add_child(_gate)

func _radio(speaker: String, text: String, duration: float) -> void:
	Events.story_radio.emit(speaker, text, duration)

func _objective(text: String) -> void:
	Events.story_objective.emit(text)

func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t, false).timeout.connect(f)

func _intro() -> void:
	_objective("Ueberquere die Bruecke")
	_radio(StoryData.WEBER, "Kerner, hier Weber. Die Bruecke muss bis Sonnenaufgang stehen – und in unserer Hand sein. Pioniere folgen euch.", 6.5)
	_later(7.5, func() -> void:
		_radio(StoryData.LENA, "Graeben links und rechts der Strasse. Bleib auf dem Asphalt, Jonas.", 4.5))

# ------------------------------------------------------------------ Hubschrauber

func _start_heli() -> void:
	if _heli_started:
		return
	_heli_started = true
	var pl := _player_pos()
	var hover := Vector3(-16.0, 11.0, minf(pl.z, -84.0) - 12.0)
	_radio(StoryData.LENA, "Hubschrauber! Elf Uhr!", 3.0)
	_objective("Schiess den Kampfhubschrauber ab")
	_later(3.2, func() -> void:
		if not _heli_down:
			_radio(StoryData.WEBER, "Hol ihn runter, Kerner, sonst kommt keiner ueber diese Bruecke!", 4.0))
	if ResourceLoader.exists(HELI_PATH):
		var scene := load(HELI_PATH) as PackedScene
		if scene != null:
			heli = scene.instantiate() as Node3D
			heli.set("mg_damage", 3.0)
			heli.set("burst_rounds", 10)
			heli.set("max_health", 360.0)
			heli.set("faction", "ru")
			heli.set("attack_range", 120.0)
			add_child(heli)
			heli.global_position = Vector3(-150.0, 34.0, hover.z - 70.0)
			var path: Array[Vector3] = [Vector3(-70.0, 22.0, hover.z - 30.0), hover]
			heli.call("fly_path", path, 30.0, false)
			_later(4.5, func() -> void:
				if is_instance_valid(heli) and heli.has_method("attack"):
					heli.call("attack", true))
			if heli.has_signal("destroyed"):
				heli.connect("destroyed", _on_heli_down)
			if heli.has_signal("crashed"):
				heli.connect("crashed", _on_heli_crash)
	if heli == null:
		_fake_heli_pass(hover)
	# Rueckfallebene: Lena holt ihn mit der Fliegerfaust runter
	_later(38.0, _heli_fallback)
	(func() -> void: _trigger("TriggerHeliFallback", Vector3(0, 3, -152.0), Vector3(60, 8, 1.5), _heli_fallback)).call_deferred()

func _heli_fallback() -> void:
	if _heli_down or heli == null or not is_instance_valid(heli):
		return
	if heli.has_method("is_alive") and not heli.call("is_alive"):
		return
	_radio(StoryData.LENA, "Halt ihn beschaeftigt – Fliegerfaust ist raus!", 3.0)
	var from := _player_pos() + Vector3(4.0, 1.5, 6.0)
	var to := heli.global_position
	var rocket := Geo.box_mesh_node(Vector3(0.15, 0.15, 0.9), Geo.flat(Color(0.2, 0.2, 0.2), 0.5, 0.0, Color(1.0, 0.7, 0.3), 6.0), from)
	add_child(rocket)
	rocket.look_at(to, Vector3.UP)
	VFX.play_sfx_3d("grenade_throw", from, 2.0, 10.0, 100.0)
	var tw := rocket.create_tween()
	tw.tween_property(rocket, "global_position", to, from.distance_to(to) / 60.0)
	tw.tween_callback(func() -> void:
		rocket.queue_free()
		if is_instance_valid(heli) and heli.has_method("take_damage"):
			heli.call("take_damage", 99999.0, null, heli.global_position, Vector3.UP))

func _on_heli_down() -> void:
	if _heli_down:
		return
	_heli_down = true
	print("[river] Hubschrauber abgeschossen")
	_radio(StoryData.LENA, "Er geht runter! Direkt in den Fluss!", 3.5)
	_objective("Ueberquere die Bruecke")

func _on_heli_crash() -> void:
	if not is_instance_valid(heli):
		return
	var p := heli.global_position
	if fx != null and p.y < WATER_Y + 4.0:
		fx.call("splash", Vector3(p.x, WATER_Y, p.z), 3.6)
		_foam(Vector3(p.x, WATER_Y, p.z), 16.0, 10.0)
		# Wrack versinkt langsam
		var tw := heli.create_tween()
		tw.tween_interval(1.5)
		tw.tween_property(heli, "global_position:y", WATER_Y - 6.0, 9.0).set_ease(Tween.EASE_IN)
		tw.tween_callback(heli.queue_free)
	elif absf(p.x) < 9.0:
		# Wrack auf der Fahrbahn: nicht als Hindernis stehen lassen (Weg muss frei bleiben)
		(heli as CollisionObject3D).collision_layer = 0

## Ersatz ohne Hubschrauber-Szene: dunkle Silhouette rast tief ueber den Fluss, MG-Einschlaege im Wasser.
func _fake_heli_pass(hover: Vector3) -> void:
	var h := Node3D.new()
	var bm := Geo.batch()
	bm.add(Vector3.ZERO, Vector3(1.8, 1.8, 6.0))
	bm.add(Vector3(0, 0.3, 5.5), Vector3(0.5, 0.6, 6.0))
	bm.add(Vector3(0, 1.3, 0), Vector3(14.0, 0.06, 0.4))
	bm.add(Vector3(0, 1.3, 0), Vector3(0.4, 0.06, 14.0))
	RP.add_batch(h, bm, Geo.flat(Color(0.08, 0.09, 0.08), 0.6, 0.3))
	add_child(h)
	var a := Vector3(-160.0, 20.0, hover.z - 20.0)
	var b := Vector3(160.0, 26.0, hover.z + 10.0)
	h.global_position = a
	h.look_at_from_position(a, b, Vector3.UP)
	var tw := h.create_tween()
	tw.tween_property(h, "global_position", b, 7.0)
	tw.tween_callback(h.queue_free)
	_heli_down = true
	for k in 8:
		_later(2.0 + k * 0.25, func() -> void:
			if fx != null:
				fx.call("splash", Vector3(randf_range(-30.0, -12.0), WATER_Y, hover.z + randf_range(-6.0, 6.0)), 0.4, k == 0))
	_later(8.0, func() -> void: _radio(StoryData.LENA, "Er dreht ab – weiter, weiter!", 3.0))

# ------------------------------------------------------------------ Brueckeneinsturz

func _collapse() -> void:
	if _collapsed or span1 == null:
		return
	_collapsed = true
	_setpiece_done = true
	setpiece_triggered.emit()
	# Kein Weg zurueck: Sperre sofort (nicht im Navmesh)
	var wall := Geo.static_body(Vector3(0, 4.0, PIER_A - 1.2))
	Geo.add_box_shape(wall, Vector3.ZERO, Vector3(14.0, 8.0, 1.0))
	add_child(wall)
	Events.story_cinematic.emit(true)
	_later(4.6, func() -> void: Events.story_cinematic.emit(false))
	var mid := Vector3(0, 0, (BRIDGE_Z0 + PIER_A) * 0.5)
	VFX.audio.call("play_3d", "river_creak", mid, 8.0, 40.0, 400.0)
	_shake(0.25)
	if fx != null:
		fx.call("strike", true)
	_radio(StoryData.LENA, "Die Bruecke! Lauf, Jonas, lauf!", 3.0)
	var tw := span1.create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	# Phase 1: Aechzen und Wackeln
	for k in 4:
		var amp := 0.006 + k * 0.004
		tw.tween_property(span1, "rotation", Vector3(-amp, 0, amp * 0.6), 0.2)
		tw.tween_property(span1, "rotation", Vector3(amp * 0.4, 0, -amp * 0.5), 0.2)
	# Phase 2: Ostende bricht vom Pfeiler, stuerzt in den Fluss
	tw.tween_callback(func() -> void:
		VFX.audio.call("play_3d", "river_collapse", mid, 10.0, 60.0, 600.0)
		_shake(0.6)
		_debris(Vector3(0, -0.5, PIER_A + 1.0), 14)
		VFX.spawn_dust_cloud(Vector3(0, 0.0, PIER_A + 2.0), 6.0))
	tw.tween_property(span1, "rotation", Vector3(-0.27, 0, 0.03), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		var sp := Vector3(0, WATER_Y, PIER_A + 2.0)
		if fx != null:
			fx.call("splash", sp, 4.0)
		_foam(sp, 22.0, 14.0)
		_shake(0.4))
	tw.tween_interval(0.5)
	# Phase 3: Westauflager reisst ab, Feld sackt ab und bleibt als Wrack im Wasser liegen
	tw.tween_callback(func() -> void:
		VFX.audio.call("play_3d", "river_collapse", mid + Vector3(0, 0, 15), 6.0, 50.0, 500.0, 0.85)
		VFX.spawn_dust_cloud(Vector3(0, 0.0, BRIDGE_Z0 - 2.0), 5.0))
	tw.set_parallel(true)
	tw.tween_property(span1, "position:y", -10.2, 1.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(span1, "rotation", Vector3(-0.1, 0, 0.05), 1.3)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void:
		var sp := Vector3(0, WATER_Y, BRIDGE_Z0 - 14.0)
		if fx != null:
			fx.call("splash", sp, 3.4)
			fx.call("splash", Vector3(4.0, WATER_Y, BRIDGE_Z0 - 28.0), 2.6, false)
		_shake(0.3)
		_later(2.0, func() -> void:
			_radio(StoryData.WEBER, "Das erste Feld ist weg. Kein Weg zurueck, Kerner – nur nach vorn.", 4.5)))

func _shake(amount: float) -> void:
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", amount)

## Laesst die Gischt im Wasser-Shader an einer Stelle aufschaeumen und langsam abklingen.
func _foam(p: Vector3, radius: float, fade: float) -> void:
	if water_mat == null:
		return
	water_mat.set_shader_parameter("foam_boost_pos", p)
	water_mat.set_shader_parameter("foam_boost_radius", radius)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: water_mat.set_shader_parameter("foam_boost", v), 1.0, 0.0, fade)

func _debris(at: Vector3, n: int) -> void:
	var m := RP.steel(Color(0.45, 0.5, 0.45))
	for i in n:
		var rb := RigidBody3D.new()
		rb.collision_layer = 8
		rb.collision_mask = 1
		var s := Vector3(randf_range(0.3, 1.2), randf_range(0.2, 0.6), randf_range(0.4, 2.2))
		rb.mass = s.x * s.y * s.z * 300.0
		Geo.add_box_shape(rb, Vector3.ZERO, s)
		rb.add_child(Geo.box_mesh_node(s, m if i % 2 == 0 else VFX.debris_material(), Vector3.ZERO))
		if not VFX.add_debris(rb):
			return
		rb.global_position = at + Vector3(randf_range(-6.0, 6.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
		rb.linear_velocity = Vector3(randf_range(-3, 3), randf_range(-2, 4), randf_range(-1, 3))
		rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
		VFX.schedule_free(rb, 8.0)

# ------------------------------------------------------------------ Panzer

func _start_tank() -> void:
	if _tank_started:
		return
	_tank_started = true
	_tank_t0 = Time.get_ticks_msec()
	_radio(StoryData.LENA, "Panzer am Brueckenkopf!", 2.5)
	_objective("Zerstoere den Panzer")
	_later(2.8, func() -> void:
		_radio(StoryData.WEBER, "Sprengladung an die Wanne, Kerner! Links an ihm vorbei, er sieht dich schlecht!", 4.5))
	var scene: PackedScene = load(TANK_PATH) as PackedScene if ResourceLoader.exists(TANK_PATH) else null
	if scene != null:
		tank = scene.instantiate() as Node3D
		tank.set("faction", "ru")
		tank.set("shell_damage", 30.0)
		tank.set("shell_radius", 4.0)
		tank.set("miss_min", 5.5)
		tank.set("miss_max", 9.0)
		tank.set("fire_interval", 7.5)
		tank.set("aim_time", 2.0)
	else:
		tank = RP.FallbackTank.new()
	tank.name = "Tank"
	add_child(tank)
	tank.global_position = TANK_START
	tank.rotation.y = PI
	if tank.has_method("drive_path"):
		var path: Array[Vector3] = [TANK_POS]
		tank.call("drive_path", path, 3.5)
	else:
		var tw := tank.create_tween()
		tw.tween_property(tank, "global_position", TANK_POS, 6.0).set_ease(Tween.EASE_OUT)
	if tank.has_method("set_target"):
		tank.call("set_target", get_tree().get_first_node_in_group("player"))
	tank.connect("destroyed", _on_tank_destroyed)
	# Sprengladung seitlich an der Wanne (zur Gasse hin)
	var cscene: PackedScene = load(CHARGE_PATH) as PackedScene if ResourceLoader.exists(CHARGE_PATH) else null
	if cscene != null:
		charge = cscene.instantiate() as Node3D
		charge.set("blast_radius", 5.0)
		charge.set("blast_damage", 120.0)
	else:
		charge = RP.FallbackCharge.new()
	charge.set("target", tank)
	tank.add_child(charge)
	charge.position = Vector3(1.8, 0.9, 0.5)
	# Rueckfall: Artillerie erledigt den Panzer, falls es zu lange dauert
	_later(55.0, func() -> void:
		if not _tank_dead and is_instance_valid(tank):
			_radio(StoryData.WEBER, "Artillerie liegt auf dem Panzer – Kopf runter!", 3.0)
			_later(2.0, func() -> void:
				if not _tank_dead and is_instance_valid(tank) and tank.has_method("destroy"):
					VFX.spawn_explosion(tank.global_position + Vector3(0, 2, 0), 3.0)
					tank.call("destroy")))

func _on_tank_destroyed() -> void:
	if _tank_dead:
		return
	_tank_dead = true
	print("[river] Panzer zerstoert nach %.1fs" % ((Time.get_ticks_msec() - _tank_t0) / 1000.0 * Engine.time_scale))
	if is_instance_valid(_gate):
		_gate.queue_free()
	_shake(0.5)
	_later(1.5, func() -> void:
		_radio(StoryData.WEBER, "Panzer ist erledigt! Brueckenkopf sichern – bis zur Fabrik!", 4.0)
		_objective("Sichere den Brueckenkopf bis zur Fabrik"))
	_later(2.5, func() -> void: _spawn_wave(3))
	_later(4.0, _jet_run)

func _jet_run() -> void:
	if not ResourceLoader.exists(JET_PATH):
		return
	var scene := load(JET_PATH) as PackedScene
	if scene == null:
		return
	var jet := scene.instantiate() as Node3D
	jet.set("faction", "eu")
	add_child(jet)
	var targets: Array[Vector3] = [Vector3(-48.0, 0.0, -236.0), Vector3(-58.0, 0.0, -262.0), Vector3(46.0, 0.0, -300.0)]
	jet.call("run", Vector3(-30.0, 70.0, 400.0), Vector3(30.0, 60.0, -900.0), targets)
	_later(1.5, func() -> void: _radio(StoryData.LENA, "Unsere Jets! Endlich!", 2.5))

# ------------------------------------------------------------------ Sonnenaufgang

func _sunrise() -> void:
	if _sunrise_done:
		return
	_sunrise_done = true
	_radio(StoryData.WEBER, "Die Sonne geht auf ... und die Bruecke steht. Gute Arbeit, Kerner.", 5.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_sun, "light_color", Color(1.0, 0.72, 0.5), 8.0)
	tw.tween_property(_sun, "light_energy", 1.5, 8.0)
	tw.tween_property(_env, "background_energy_multiplier", storm_sky_energy * 1.6, 8.0)
	if fx != null:
		fx.set("sky_energy_base", storm_sky_energy * 1.6)
		var w: Node = fx.get("weather")
		if w != null:
			tw.tween_property(w, "rain_strength", 0.45, 8.0)

# ------------------------------------------------------------------ Kulisse

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	var srng := RandomNumberGenerator.new()
	srng.seed = build_seed + 31
	var bb := Geo.batch()
	# Pskow am Ostufer: Wohnbloecke im Dunst, Westufer: niedrige Bebauung
	for i in 60:
		var east := i % 3 != 0
		var x := srng.randf_range(-320.0, 320.0)
		if absf(x) < 40.0:
			x += signf(x + 0.01) * 40.0
		var z := srng.randf_range(-260.0, -520.0) if east else srng.randf_range(40.0, 240.0)
		var h := srng.randf_range(10.0, 42.0) if east else srng.randf_range(6.0, 20.0)
		bb.add(Vector3(x, h * 0.5, z), Vector3(srng.randf_range(14.0, 40.0), h, srng.randf_range(10.0, 18.0)))
	# Uferbebauung links/rechts entlang des Flusses
	for i in 24:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var x := sx * srng.randf_range(70.0, 300.0)
		var z := BRIDGE_Z1 - srng.randf_range(20.0, 80.0) if i % 4 < 2 else BRIDGE_Z0 + srng.randf_range(20.0, 80.0)
		var h := srng.randf_range(8.0, 30.0)
		bb.add(Vector3(x, h * 0.5, z), Vector3(srng.randf_range(12.0, 30.0), h, srng.randf_range(10.0, 16.0)))
	var mi := Geo.mesh_node(bb.build(), RP.concrete(Color(0.3, 0.3, 0.31)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Kreml-Silhouette (Dreifaltigkeitskathedrale) im Nordosten
	var k := Node3D.new()
	k.position = Vector3(170.0, 0, -470.0)
	add_child(k)
	var wm := RP.plaster(Color(0.75, 0.74, 0.7))
	var dm := RP.wet("", Color(0.6, 0.55, 0.4), 1.0, {"base_metallic": 0.9, "base_roughness": 0.35})
	k.add_child(Geo.box_mesh_node(Vector3(30, 26, 30), wm, Vector3(0, 13, 0)))
	k.add_child(Geo.cylinder_node(5.0, 12.0, wm, Vector3(0, 32, 0), Vector3.ZERO, 16))
	var dome := SphereMesh.new()
	dome.radius = 5.6
	dome.height = 11.0
	k.add_child(Geo.mesh_node(dome, dm, Vector3(0, 40, 0)))
	k.add_child(Geo.box_mesh_node(Vector3(0.4, 6, 0.4), dm, Vector3(0, 48, 0)))
	k.add_child(Geo.box_mesh_node(Vector3(2.4, 0.3, 0.3), dm, Vector3(0, 49, 0)))
	for c: Vector3 in [Vector3(-10, 0, -10), Vector3(10, 0, -10), Vector3(-10, 0, 10), Vector3(10, 0, 10)]:
		k.add_child(Geo.cylinder_node(2.5, 7.0, wm, c + Vector3(0, 29, 0), Vector3.ZERO, 12))
		var d2 := SphereMesh.new()
		d2.radius = 2.8
		d2.height = 5.5
		k.add_child(Geo.mesh_node(d2, dm, c + Vector3(0, 34, 0)))
	# Festungsmauer davor
	k.add_child(Geo.box_mesh_node(Vector3(160, 9, 4), wm, Vector3(-40, 4.5, 40)))

func _build_atmosphere() -> void:
	fx = RiverFx.new()
	fx.name = "RiverFx"
	fx.set("env", _env)
	fx.set("sky_energy_base", storm_sky_energy)
	fx.set("river_z0", BRIDGE_Z0 - 8.0)
	fx.set("river_z1", BRIDGE_Z1 + 8.0)
	fx.set("water_y", WATER_Y)
	add_child(fx)
	# Rauchsaeulen ueber der Stadt
	for c: Vector3 in [Vector3(-70, 0, -300), Vector3(90, 0, -360), Vector3(-130, 0, 60), Vector3(60, 0, 90), Vector3(-40, 0, -420)]:
		Props.fire(self, c, 3.0, false, 4.0)
	# Brand im Fenster
	Props.fire(world, Vector3(-11.6, 4.6, -216.0), 0.9, true, 1.2, 6.0)
	# Dunst ueber dem Wasser und in den Gassen
	Props.fog_volume(self, Vector3(0, WATER_Y + 2.0, (BRIDGE_Z0 + BRIDGE_Z1) * 0.5), Vector3(260, 7, 110), 0.045, Color(0.7, 0.74, 0.8))
	for z: float in [-30.0, -230.0, -275.0]:
		Props.fog_volume(self, Vector3(0, 1.5, z), Vector3(26, 5, 30), 0.03, Color(0.55, 0.58, 0.62))
	_later(1.5, _intro)

# ------------------------------------------------------------------ Navigation / Artillerie

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
	nm.geometry_collision_mask = 1 | 16   # world + move_block (= alles, woran Player/Gegner haengen)
	nm.filter_baking_aabb = AABB(Vector3(-22.0, -2.0, end_z - 8.0), Vector3(44.0, 14.0, 26.0 - end_z + 8.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

func _start_artillery() -> void:
	if fx != null:
		fx.set("artillery_enabled", true)

func _player_pos() -> Vector3:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	return pl.global_position if pl != null else Vector3(0, 0, -80)
