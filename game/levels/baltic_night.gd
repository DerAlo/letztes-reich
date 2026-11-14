extends "res://game/levels/level.gd"
## Level "Nacht an der Grenze" (baltic_night): Waldrand und baltisches Grenzdorf, Nacht im Schneesturm.
## Abschnitt 1: eigener Graben, offenes Feld mit Draht (Welle 0).
## Abschnitt 2: Kiefernwald, dann Dorfgasse (Wellen 1/2, Set-Piece Artilleriesperrfeuer auf Haeuserzeile).
## Abschnitt 3: Dorfplatz mit brennender Scheune, Wasserturm-Set-Piece (Welle 3), Ende am Bahnuebergang.

const NightProps = preload("res://game/levels/night_props.gd")
const PH = preload("res://game/levels/ph_props.gd")
const GroundCover = preload("res://game/levels/ground_cover.gd")
const NightFx = preload("res://game/levels/night_fx.gd")
const WaterTower = preload("res://game/levels/water_tower.gd")
const FuelTank = preload("res://game/levels/fuel_tank.gd")

const TRENCH_Z := 1.1          ## halbe Grabenbreite (Graben liegt bei z -1.1..1.1)
const TRENCH_FLOOR := -0.85
const TRENCH_X := 26.0
const RAMPS: Array = [[2.0, 4.4], [-16.0, -13.6]]   ## x-Bereiche der Ausstiegsrampen
const RAMP_END_Z := -5.0

## Bot-Route (x, z); y wird aus dem Gelaende abgeleitet. Gerade Linien muessen frei begehbar sein.
const ROUTE: Array = [
	Vector2(2.5, 0.4), Vector2(3.2, -0.4), Vector2(3.2, -6.5), Vector2(2.0, -20.0), Vector2(0.5, -35.0),
	Vector2(1.0, -50.0), Vector2(0.0, -66.0), Vector2(-1.0, -80.0), Vector2(1.0, -95.0), Vector2(0.0, -108.0),
	Vector2(0.0, -120.0), Vector2(0.0, -135.0), Vector2(0.0, -150.0), Vector2(0.0, -165.0), Vector2(2.0, -180.0),
	Vector2(3.0, -195.0), Vector2(2.0, -210.0), Vector2(0.5, -222.0), Vector2(0.5, -230.0)]

@export var moon_energy: float = 0.22
@export var night_fog: float = 0.016

var fx: Node3D
var tower: StaticBody3D
var fuel: StaticBody3D
var _doomed: Array = []        ## zerlegbare Haeuser fuer das Sperrfeuer
var _tower_done: bool = false
var _trees_play: Array = []

func _init() -> void:
	level_name = "baltic_night"
	end_z = -232.0
	build_seed = 2030
	_wave_count = 4

# ------------------------------------------------------------------ Oeffentlich

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Nacht an der Grenze"
	return info

## Set-Piece 1: Artilleriesperrfeuer auf die linke Haeuserzeile.
func trigger_setpiece() -> void:
	if _setpiece_done:
		return
	_setpiece_done = true
	setpiece_triggered.emit()
	_run_barrage()

## Set-Piece 2: Wasserturm kippen (fuer Tests/Touren; im Spiel durch Beschuss).
func trigger_tower() -> void:
	if tower != null and tower.has_method("topple"):
		tower.call("topple")

# ------------------------------------------------------------------ Umgebung

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(night_fog, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Himmel leicht angehoben (Wolkendecke reflektiert Restlicht), damit Silhouetten lesbar bleiben
	sm.sky_top_color = Color(0.022, 0.03, 0.052)
	sm.sky_horizon_color = Color(0.07, 0.08, 0.11)
	sm.ground_bottom_color = Color(0.01, 0.012, 0.018)
	sm.ground_horizon_color = Color(0.045, 0.055, 0.08)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.sky_rotation = Vector3.ZERO
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.25, 0.38)
	env.ambient_light_energy = 0.22
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.05
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	env.ssil_intensity = 1.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.08, 0.11)
	env.fog_light_energy = 1.0
	env.fog_density = 0.008
	env.fog_sky_affect = 0.9
	env.fog_aerial_perspective = 0.2
	env.volumetric_fog_density = night_fog
	env.volumetric_fog_albedo = Color(0.78, 0.82, 0.9)
	env.volumetric_fog_emission = Color(0.006, 0.008, 0.014)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 110.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.15
	env.volumetric_fog_sky_affect = 0.7
	env.glow_hdr_threshold = 1.4   # vorher 1.0/0.7: beleuchteter Schnee bloomte als Ganzes mit
	env.glow_intensity = 0.4
	env.glow_bloom = 0.04
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.06
	env.adjustment_color_correction = null
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = moon_energy
	moon.light_indirect_energy = 0.6
	moon.light_volumetric_fog_energy = 0.8
	moon.light_angular_distance = 2.5
	moon.shadow_enabled = true
	moon.shadow_blur = 2.5
	moon.shadow_bias = 0.05
	moon.shadow_normal_bias = 1.4
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon.directional_shadow_max_distance = 120.0
	var dir := Vector3(-0.3, -0.57, -0.76).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_snow")

# ------------------------------------------------------------------ Boden und Graben

func _ground_rect(gb: Geo.BoxBatch, body: StaticBody3D, x0: float, x1: float, z0: float, z1: float, top: float = 0.0, depth: float = 3.0) -> void:
	var c := Vector3((x0 + x1) / 2.0, top - depth / 2.0, (z0 + z1) / 2.0)
	var s := Vector3(absf(x1 - x0), depth, absf(z1 - z0))
	gb.add(c, s)
	Geo.add_box_shape(body, c, s)

func _build_ground() -> void:
	var gmat := NightProps.ground_mat()
	var body := Geo.static_body()
	var gb := Geo.batch()
	var W := 70.0
	# hinter dem Graben
	_ground_rect(gb, body, -W, W, TRENCH_Z, 40.0)
	# links/rechts neben dem Graben
	_ground_rect(gb, body, -W, -TRENCH_X, -TRENCH_Z, TRENCH_Z)
	_ground_rect(gb, body, TRENCH_X, W, -TRENCH_Z, TRENCH_Z)
	# Streifen vor dem Graben mit Aussparungen fuer die Rampen
	var xs: Array = [-W]
	for r in RAMPS:
		xs.append(r[0])
		xs.append(r[1])
	xs.append(W)
	xs.sort()
	for i in range(0, xs.size(), 2):
		_ground_rect(gb, body, xs[i], xs[i + 1], RAMP_END_Z, -TRENCH_Z)
	# Feld bis hinter das Levelende
	_ground_rect(gb, body, -W, W, end_z - 70.0, RAMP_END_Z)
	# Grabensohle
	_ground_rect(gb, body, -TRENCH_X, TRENCH_X, -TRENCH_Z, TRENCH_Z, TRENCH_FLOOR, 2.0)
	# Rampen
	var rise := -TRENCH_FLOOR
	var run_abs := absf(-TRENCH_Z - RAMP_END_Z)
	var ang := atan2(rise, run_abs)
	var n := Vector3(0, cos(ang), sin(ang))
	for r in RAMPS:
		var mid := Vector3((r[0] + r[1]) / 2.0, TRENCH_FLOOR / 2.0, (-TRENCH_Z + RAMP_END_Z) / 2.0)
		var c: Vector3 = mid - n * 0.2
		var size := Vector3(r[1] - r[0], 0.4, sqrt(rise * rise + run_abs * run_abs) + 0.1)
		gb.add(c, size, Basis(Vector3.RIGHT, ang))
		Geo.add_box_shape(body, c, size, Vector3(rad_to_deg(ang), 0, 0))
	world.add_child(body)
	var mi := NightProps.add_batch(body, gb, gmat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Weiter Boden bis zum Horizont (nur Optik)
	var far := Geo.box_mesh_node(Vector3(900.0, 0.2, 900.0), gmat, Vector3(0, -0.13, -200.0))
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
	_build_trench()
	_build_drifts()
	# Aussengrenzen
	for sx: float in [-1.0, 1.0]:
		_invisible_wall(Vector3(sx * 30.0, 6.0, -110.0), Vector3(1.0, 14.0, 300.0))
	_invisible_wall(Vector3(0, 6.0, 14.0), Vector3(62.0, 14.0, 1.0))
	_invisible_wall(Vector3(0, 6.0, end_z - 6.0), Vector3(62.0, 14.0, 1.0))

func _build_trench() -> void:
	var t := Node3D.new()
	t.name = "Trench"
	world.add_child(t)
	var planks := Geo.batch()
	var posts := Geo.batch()
	var h := -TRENCH_FLOOR + 0.05
	# Rueckwand komplett
	NightProps.revetment(planks, posts, Vector3(-TRENCH_X, TRENCH_FLOOR, TRENCH_Z), Vector3(TRENCH_X, TRENCH_FLOOR, TRENCH_Z), h, Vector3(0, 0, -1), rng)
	# Vorderwand mit Rampenluecken
	var segs: Array = [-TRENCH_X]
	for r in RAMPS:
		segs.append(r[0])
		segs.append(r[1])
	segs.append(TRENCH_X)
	segs.sort()
	for i in range(0, segs.size(), 2):
		NightProps.revetment(planks, posts, Vector3(segs[i], TRENCH_FLOOR, -TRENCH_Z), Vector3(segs[i + 1], TRENCH_FLOOR, -TRENCH_Z), h, Vector3(0, 0, 1), rng)
	# Grabenenden
	for sx: float in [-1.0, 1.0]:
		NightProps.revetment(planks, posts, Vector3(sx * TRENCH_X, TRENCH_FLOOR, -TRENCH_Z), Vector3(sx * TRENCH_X, TRENCH_FLOOR, TRENCH_Z), h, Vector3(-sx, 0, 0), rng)
	NightProps.add_batch(t, planks, NightProps.planks(Color(0.45, 0.38, 0.3), 0.35))
	NightProps.add_batch(t, posts, NightProps.planks(Color(0.32, 0.26, 0.2), 0.4))
	# Lattenrost auf der Sohle
	var duck := Geo.batch()
	var x := -TRENCH_X + 0.5
	while x < TRENCH_X - 0.5:
		duck.add(Vector3(x, TRENCH_FLOOR + 0.04, 0), Vector3(0.12, 0.05, 0.9))
		x += 0.28
	duck.add(Vector3(0, TRENCH_FLOOR + 0.02, 0.32), Vector3(TRENCH_X * 2.0, 0.04, 0.08))
	duck.add(Vector3(0, TRENCH_FLOOR + 0.02, -0.32), Vector3(TRENCH_X * 2.0, 0.04, 0.08))
	NightProps.add_batch(t, duck, NightProps.planks(Color(0.38, 0.32, 0.26), 0.5))
	# Brustwehr: niedrige Sandsaecke vor dem Graben (Luecken an den Rampen)
	for i in range(0, segs.size(), 2):
		var a: float = segs[i] + 0.6
		var b: float = segs[i + 1] - 0.6
		if b - a < 1.0:
			continue
		NightProps.sandbags(t, Vector3((a + b) / 2.0, 0, -TRENCH_Z - 0.55), 90.0, b - a, 2, rng, [], true)
	NightProps.sandbags(t, Vector3(0, 0, TRENCH_Z + 0.6), 90.0, TRENCH_X * 2.0 - 1.0, 2, rng, [], false)
	# Unterstand-Eingang, Kisten, Laternen
	NightProps.crates(t, Vector3(-6.0, TRENCH_FLOOR, 0.55), 0.0, rng, [])
	NightProps.crates(t, Vector3(11.0, TRENCH_FLOOR, 0.6), 0.0, rng, [])
	var dug := Geo.batch()
	dug.add(Vector3(-9.5, TRENCH_FLOOR + 1.0, 1.25), Vector3(1.4, 0.12, 0.3))
	dug.add(Vector3(-9.5, TRENCH_FLOOR + 0.5, 1.15), Vector3(1.1, 1.0, 0.06))
	NightProps.add_batch(t, dug, NightProps.planks(Color(0.2, 0.17, 0.14), 0.2))
	for lx: float in [-12.0, 0.5, 8.5, 19.0]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.62, 0.3)
		l.light_energy = 0.9
		l.omni_range = 5.5
		l.light_volumetric_fog_energy = 0.6
		l.position = Vector3(lx, TRENCH_FLOOR + 1.1, 0.95)
		t.add_child(l)
		# Sturmlaterne (Poly Haven "Lantern_01", 1,3-fach = 38 cm) am Haken, Flamme als kleiner Leuchtkoerper
		PH.place(t, "lantern_01", PH.xform(l.position + Vector3(0, -0.2, 0), rng.randf_range(0.0, 360.0), Vector3.ONE * 1.3), -1.0, {"shadows": false})
		t.add_child(Geo.box_mesh_node(Vector3(0.025, 0.05, 0.025), NightProps.glow(Color(1.0, 0.6, 0.25), 8.0), l.position + Vector3(0, -0.075, 0)))

func _build_drifts() -> void:
	var gb := Geo.batch()
	for i in 140:
		var p := Vector3(rng.randf_range(-45.0, 45.0), 0, rng.randf_range(end_z - 30.0, 30.0))
		if _near_route(p, 3.5) or absf(p.z) < 3.0 or (p.z < -112.0 and p.z > -215.0 and absf(p.x) < 24.0):
			continue
		var s := Vector3(rng.randf_range(2.0, 6.0), rng.randf_range(0.5, 1.2), rng.randf_range(1.5, 3.5))
		NightProps.drift(gb, p - Vector3(0, s.y * 0.3, 0), s, rng.randf() * TAU)
	var mi := NightProps.add_batch(self, gb, NightProps.ground_mat())
	if mi != null:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Abstand eines Punktes zur Bot-Route (xz).
func _route_dist(p: Vector3) -> float:
	var best := INF
	for i in range(1, ROUTE.size()):
		var a: Vector2 = ROUTE[i - 1]
		var b: Vector2 = ROUTE[i]
		var q := Vector2(p.x, p.z)
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		best = minf(best, q.distance_to(a + ab * t))
	return best

func _near_route(p: Vector3, d: float) -> bool:
	return _route_dist(p) < d

# ------------------------------------------------------------------ Dorf

func _build_street() -> void:
	var v := Node3D.new()
	v.name = "Village"
	world.add_child(v)
	var cols: Array = [Color(0.42, 0.22, 0.16), Color(0.5, 0.42, 0.26), Color(0.3, 0.36, 0.3), Color(0.4, 0.37, 0.32), Color(0.28, 0.3, 0.38), Color(0.46, 0.3, 0.2)]
	var depth := 7.0
	# Linke Zeile (Front nach +x): statisch, 3 zerlegbar, statisch
	var left_z: Array = [-118.0, -130.0, -142.0, -154.0, -166.0]
	var left_ext: Array[Vector2] = []
	var right_ext: Array[Vector2] = []
	for i in left_z.size():
		var z: float = left_z[i]
		var size := Vector3(rng.randf_range(7.0, 8.5), rng.randf_range(2.9, 3.4), depth)
		var pos := Vector3(-5.0 - depth / 2.0, 0, z)
		var c: Color = cols[i % cols.size()]
		if i >= 1 and i <= 3:
			var h := NightProps.house_pieces(v, pos, 90.0, size, c, rng, {"lit": 0.35})
			_doomed.append(h)
		else:
			NightProps.house(v, pos, 90.0, size, c, rng, {"lit": 0.2})
		covers.append(Vector3(-4.3, 0, z + size.x / 2.0 + 0.8))
		left_ext.append(Vector2(z + size.x / 2.0, z - size.x / 2.0))
	# Rechte Zeile (Front nach -x)
	var right_z: Array = [-121.0, -134.0, -147.0, -160.0]
	for i in right_z.size():
		var z: float = right_z[i]
		var size := Vector3(rng.randf_range(7.0, 9.0), rng.randf_range(2.9, 3.5), depth)
		NightProps.house(v, Vector3(5.0 + depth / 2.0, 0, z), -90.0, size, cols[(i + 3) % cols.size()], rng, {"lit": 0.2})
		covers.append(Vector3(4.3, 0, z + size.x / 2.0 + 0.8))
		covers.append(Vector3(4.3, 0, z - size.x / 2.0 - 0.8))
		right_ext.append(Vector2(z + size.x / 2.0, z - size.x / 2.0))
	# Gassen zwischen den Haeusern mit Lattenzaun schliessen (haelt Spieler/Bots in der Strasse)
	for pair: Array in [[left_ext, -9.0], [right_ext, 9.5]]:
		var ext: Array[Vector2] = pair[0]
		for i in range(1, ext.size()):
			NightProps.fence(v, Vector3(pair[1], 0, ext[i - 1].y), Vector3(pair[1], 0, ext[i].x), rng, true, 0.0)
	# Hinterhaeuser (Tiefe, Silhouette) ohne Gassenbedeutung
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := -115.0 - i * 9.0 - rng.randf_range(0, 4)
		NightProps.house(v, Vector3(side * rng.randf_range(19.0, 24.0), 0, z), side * -90.0 + rng.randf_range(-15, 15), Vector3(rng.randf_range(6.5, 8.5), 3.0, 6.5), cols[i % cols.size()], rng, {"lit": 0.1})
	# Haus am Platz (links hinter dem Wasserturm) und am Bahnuebergang
	NightProps.house(v, Vector3(-21.0, 0, -182.0), 90.0, Vector3(9.0, 3.4, 7.0), cols[2], rng, {"lit": 0.3})
	NightProps.house(v, Vector3(-20.0, 0, -205.0), 70.0, Vector3(8.0, 3.0, 7.0), cols[4], rng, {"lit": 0.0})
	# Gartenzaeune in den Gassen (Optik) und hinten (Kollision)
	for z: float in [-124.0, -136.0, -148.0, -160.0]:
		NightProps.fence(v, Vector3(-13.0, 0, z), Vector3(-26.0, 0, z), rng, false, 0.25)
	for z: float in [-127.5, -140.5, -153.5]:
		NightProps.fence(v, Vector3(13.5, 0, z), Vector3(26.0, 0, z), rng, false, 0.25)
	# Scheune (brennend, Dach teilweise eingestuerzt)
	var barn := NightProps.house_pieces(v, Vector3(17.0, 0, -195.0), -90.0, Vector3(18.0, 4.6, 12.0), Color(0.4, 0.17, 0.12), rng, {"lit": 0.0, "door": true})
	var pcs: Array = barn["pieces"]
	for i in pcs.size():
		var p: RigidBody3D = pcs[i]
		# Dachplatten auf der Platzseite fehlen (eingestuerzt) -> Innenfeuer sichtbar
		if p.global_position.y > 5.0 and p.global_position.x < 16.0 and rng.randf() < 0.85:
			p.queue_free()
	covers.append(Vector3(9.5, 0, -184.0))
	covers.append(Vector3(9.5, 0, -206.0))

# ------------------------------------------------------------------ Requisiten

func _build_props() -> void:
	var p := Node3D.new()
	p.name = "Props"
	world.add_child(p)
	# --- Feld: Stacheldraht (Luecken auf der Route) ---
	for seg in [[-26.0, -4.0], [6.5, 26.0]]:
		NightProps.wire(p, Vector3(seg[0], 0, -14.0), Vector3(seg[1], 0, -14.0))
	for seg in [[-26.0, -14.0], [-9.0, -3.5], [5.0, 14.0], [19.0, 26.0]]:
		NightProps.wire(p, Vector3(seg[0], 0, -30.0 + rng.randf_range(-0.6, 0.6)), Vector3(seg[1], 0, -30.0 + rng.randf_range(-0.6, 0.6)))
	for seg in [[-22.0, -8.0], [8.0, 22.0]]:
		NightProps.wire(p, Vector3(seg[0], 0, -44.0), Vector3(seg[1], 0, -44.5))
	NightProps.knife_rest(p, Vector3(-2.5, 0, -15.5), 80.0, covers)
	NightProps.knife_rest(p, Vector3(10.5, 0, -31.5), 95.0, covers)
	NightProps.knife_rest(p, Vector3(-11.5, 0, -32.0), 85.0, covers)
	NightProps.knife_rest(p, Vector3(4.8, 0, -45.5), 70.0, covers)
	# Liegengebliebener Schuetzenpanzer (eigene Kraefte), Heck zum Graben
	NightProps.ifv(p, Vector3(-7.5, 0, -36.0), 160.0, covers)
	Props.tank_wreck(p, Vector3(15.0, 0, -57.0), 200.0, covers, true)
	# Feindliche Schuetzenloecher (Sandsack-Boegen) fuer Welle 0
	NightProps.sandbags(p, Vector3(-6.0, 0, -52.0), 75.0, 3.4, 4, rng, covers)
	NightProps.sandbags(p, Vector3(8.0, 0, -55.0), 100.0, 3.6, 4, rng, covers)
	NightProps.sandbags(p, Vector3(-13.0, 0, -48.0), 90.0, 3.2, 4, rng, covers)
	NightProps.sandbags(p, Vector3(12.5, 0, -42.0), 90.0, 3.0, 4, rng, covers)
	NightProps.sandbags(p, Vector3(-4.0, 0, -61.0), 90.0, 3.0, 4, rng, covers)
	NightProps.sandbags(p, Vector3(7.0, 0, -24.0), 90.0, 2.8, 3, rng, covers)
	NightProps.crates(p, Vector3(-3.5, 0, -22.0), 15.0, rng, covers)
	for c: Vector3 in [Vector3(1.0, 0, -18.0), Vector3(-6.0, 0, -26.0), Vector3(8.0, 0, -36.0), Vector3(-2.0, 0, -42.0), Vector3(12.0, 0, -22.0), Vector3(-15.0, 0, -58.0), Vector3(3.0, 0, -58.0)]:
		Props.crater(p, c, rng.randf_range(2.0, 3.4), rng)
	# Strommasten (links am Feldrand, durchs Dorf, einer umgeknickt)
	var line: Array = []
	var z := 30.0
	while z > end_z - 40.0:
		line.append(Vector3(-22.0 + rng.randf_range(-0.8, 0.8), 0, z))
		z -= 32.0
	NightProps.power_line(p, line, rng, AABB(Vector3(-30, -1, end_z - 10), Vector3(60, 12, 260)))
	var pole2: Array = [Vector3(24.0, 0, 20.0), Vector3(23.0, 0, -12.0), Vector3(24.5, 0, -44.0)]
	NightProps.power_line(p, pole2, rng, AABB(Vector3(-30, -1, end_z - 10), Vector3(60, 12, 260)))
	# Gefaellter Mast am Feldrand rechts (liegt)
	Geo.solid_box(p, Vector3(22.0, 0.2, -60.0), Vector3(0.28, 0.28, 8.5), NightProps.planks(Color(0.3, 0.25, 0.2), 0.5), 25.0, true)
	# --- Wald: umgestuerzte Staemme und Felsen als Deckung ---
	# Umgestuerzte Staemme (Poly Haven "dead_tree_trunk", auf ~0,72 m Dicke skaliert) mit Wurzelstubben
	# am feldseitigen Ende (Poly Haven "tree_stump_01"); Kollision/Deckung wie bisher
	for lg in [[Vector3(-7.5, 0.35, -76.0), 70.0, 6.0], [Vector3(7.5, 0.35, -86.0), 110.0, 5.0], [Vector3(-7.5, 0.35, -99.0), 95.0, 5.5], [Vector3(7.0, 0.35, -104.0), 60.0, 4.5], [Vector3(-11.0, 0.35, -90.0), 20.0, 6.0]]:
		var b := Geo.static_body(lg[0], lg[1])
		var len_s: float = float(lg[2]) / 3.05
		PH.place(b, "dead_tree_trunk", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(len_s, 2.55, 2.55)), Vector3(0.08, -0.27, 0)), 0.5)
		Geo.add_box_shape(b, Vector3.ZERO, Vector3(0.75, 0.75, lg[2]))
		p.add_child(b)
		var bs := Basis(Vector3.UP, deg_to_rad(lg[1]))
		var base: Vector3 = (lg[0] as Vector3) * Vector3(1, 0, 1)
		covers.append(base + bs * Vector3(1.1, 0, 0))
		covers.append(base + bs * Vector3(-1.1, 0, 0))
		var e1 := base + bs * Vector3(0, 0, float(lg[2]) * 0.5 + 0.55)
		var e2 := base - bs * Vector3(0, 0, float(lg[2]) * 0.5 + 0.55)
		var se := e1 if absf(e1.x) > absf(e2.x) else e2
		if absf(se.x) > 9.0:
			var yaw_s := rng.randf_range(0.0, 360.0)
			_stump(p, "tree_stump_01", se, yaw_s, rng.randf_range(0.8, 1.0))
	# Felsbrocken (Poly Haven "rock_moss_set_01", Einzelsteine, verschneit); Kollision/Deckung wie bisher
	var rocks: Array = [["rock03", 0.95, 0.41], ["rock04", 0.75, 0.66], ["rock06", 0.8, 0.53], ["rock02", 0.72, 0.47]]
	var ri := 0
	for rp: Vector3 in [Vector3(6.0, 0, -73.0), Vector3(-5.5, 0, -92.0), Vector3(9.0, 0, -97.0), Vector3(-9.0, 0, -82.0)]:
		var rb := Geo.static_body(rp)
		var rk: Array = rocks[ri % rocks.size()]
		ri += 1
		var rs: float = rk[1]
		PH.place(rb, "rock_moss_set_01", PH.xform(Vector3(0, float(rk[2]) * rs - 0.12, 0), rng.randf_range(0.0, 360.0), Vector3.ONE * rs), 0.42, {"only": rk[0], "center": true})
		Geo.add_box_shape(rb, Vector3(0, 0.55, 0), Vector3(1.8, 1.1, 1.8))
		p.add_child(rb)
		covers.append(rp + Vector3(0, 0, 1.4))
		covers.append(rp + Vector3(0, 0, -1.4))
	# Felsen am Wegrand fuer Welle 1: Schuetzen stehen am Waldrand (Laub-Sicht frei, Silhouette vor dem
	# Kronendunkel), Deckung zum Weg hin. Feste Drehung, damit der rng-Strom der uebrigen Requisiten gleich bleibt.
	for er: Array in [[Vector3(-2.75, 0, -80.8), "rock04", 0.7, 0.66, 35.0], [Vector3(2.05, 0, -87.3), "rock06", 0.7, 0.53, 200.0], [Vector3(-2.35, 0, -89.8), "rock02", 0.65, 0.47, 300.0], [Vector3(2.35, 0, -100.8), "rock03", 0.8, 0.41, 120.0]]:
		var rp: Vector3 = er[0]
		var rb := Geo.static_body(rp)
		var rs: float = er[2]
		PH.place(rb, "rock_moss_set_01", PH.xform(Vector3(0, float(er[3]) * rs - 0.12, 0), float(er[4]), Vector3.ONE * rs), 0.42, {"only": er[1], "center": true})
		Geo.add_box_shape(rb, Vector3(0, 0.5, 0), Vector3(1.3, 1.0, 1.3))
		p.add_child(rb)
		covers.append(rp + Vector3(0, 0, -1.2))
	# --- Dorfgasse ---
	NightProps.cart(p, Vector3(-3.4, 0, -127.0), 4.0, false, covers)
	NightProps.crates(p, Vector3(3.9, 0, -140.0), 90.0, rng, covers)
	NightProps.sandbags(p, Vector3(-3.5, 0, -158.0), 90.0, 2.4, 4, rng, covers)
	Props.vehicle(p, Vector3(3.7, 0, -116.0), 3.0, "car", Color(0.3, 0.32, 0.36), true, false, covers)
	# --- Dorfplatz ---
	NightProps.cart(p, Vector3(-6.8, 0, -186.5), 70.0, true, covers)
	NightProps.hay(p, Vector3(9.0, 0, -188.5), rng, covers)
	NightProps.hay(p, Vector3(-3.5, 0, -205.0), rng, covers)
	NightProps.crates(p, Vector3(7.5, 0, -203.0), 80.0, rng, covers)
	NightProps.sandbags(p, Vector3(-8.0, 0, -199.0), 90.0, 3.2, 4, rng, covers)
	NightProps.sandbags(p, Vector3(9.0, 0, -213.0), 90.0, 3.2, 4, rng, covers)
	NightProps.sandbags(p, Vector3(-6.0, 0, -214.0), 90.0, 3.0, 4, rng, covers)
	# Brunnen
	var well := Geo.static_body(Vector3(-5.0, 0, -176.0))
	well.add_child(Geo.cylinder_node(0.9, 0.9, NightProps.concrete(Color(0.45, 0.44, 0.42), 0.6), Vector3(0, 0.45, 0), Vector3.ZERO, 14))
	Geo.add_box_shape(well, Vector3(0, 0.45, 0), Vector3(1.7, 0.9, 1.7))
	p.add_child(well)
	covers.append(Vector3(-5.0, 0, -174.3))
	_build_rail(p)
	# Explosive Faesser (wiederverwendet)
	for bxz: Vector2 in [Vector2(7.0, -21.0), Vector2(-6.5, -50.0), Vector2(4.5, -84.0), Vector2(6.8, -125.0), Vector2(-3.0, -147.0), Vector2(-12.0, -184.5), Vector2(12.5, -180.0), Vector2(-4.5, -218.0)]:
		_barrel(bxz.x, bxz.y)

const OLD_ROCK := "res://assets/textures/concrete_wall_008"

func _build_rail(p: Node3D) -> void:
	var rz := -226.0
	var ties := Geo.batch()
	var rails := Geo.batch()
	var x := -70.0
	while x < 70.0:
		ties.add(Vector3(x, 0.05, rz), Vector3(0.24, 0.12, 2.6))
		x += 0.7
	for dz: float in [-0.72, 0.72]:
		rails.add(Vector3(0, 0.17, rz + dz), Vector3(140.0, 0.12, 0.07))
	# Schotterbett
	var bal := Geo.batch()
	bal.add(Vector3(0, -0.05, rz), Vector3(140.0, 0.2, 3.6))
	NightProps.add_batch(p, bal, NightProps.snowy(NightProps.ENV_TEX + "gravel", Color(0.4, 0.38, 0.36), 0.6, 0.5))
	NightProps.add_batch(p, ties, NightProps.planks(Color(0.25, 0.2, 0.16), 0.5))
	NightProps.add_batch(p, rails, Geo.flat(Color(0.3, 0.3, 0.32), 0.35, 0.9))
	# Gueterwagen links und rechts der Strasse
	var wm := NightProps.planks(Color(0.38, 0.2, 0.14), 0.35)
	var roofm := NightProps.metal(Color(0.3, 0.3, 0.3), 0.7)
	var dark := Geo.flat(Color(0.05, 0.05, 0.05), 0.8, 0.4)
	for wx: float in [-25.0, -12.0, 15.5, 28.5]:
		var b := Geo.static_body(Vector3(wx, 0, rz))
		var wb := Geo.batch()
		wb.add(Vector3(0, 2.3, 0), Vector3(12.0, 2.6, 2.9))
		NightProps.add_batch(b, wb, wm)
		var rb := Geo.batch()
		rb.add(Vector3(0, 3.7, 0), Vector3(12.2, 0.2, 3.1))
		NightProps.add_batch(b, rb, roofm)
		var ub := Geo.batch()
		ub.add(Vector3(0, 0.9, 0), Vector3(11.0, 0.3, 2.2))
		for sx: float in [-4.0, 4.0]:
			for dz: float in [-0.72, 0.72]:
				ub.add(Vector3(sx, 0.55, dz), Vector3(1.6, 0.5, 0.2))
		NightProps.add_batch(b, ub, dark)
		b.add_child(Geo.box_mesh_node(Vector3(2.0, 2.2, 0.05), dark, Vector3(0, 2.2, 1.47)))
		Geo.add_box_shape(b, Vector3(0, 1.8, 0), Vector3(12.0, 3.6, 2.9))
		p.add_child(b)
		covers.append(Vector3(wx, 0, rz + 2.4))
	# Schranke (offen) + Warnkreuz mit rotem Blinklicht
	var post := Geo.static_body(Vector3(-4.5, 0, rz + 2.6))
	post.add_child(Geo.box_mesh_node(Vector3(0.2, 1.2, 0.2), NightProps.metal(Color(0.5, 0.5, 0.5), 0.3), Vector3(0, 0.6, 0)))
	post.add_child(Geo.box_mesh_node(Vector3(0.1, 0.1, 5.0), NightProps.unshaded(Color(0.8, 0.1, 0.08), 0.6), Vector3(0, 3.2, 0.3), Vector3(-80, 0, 0)))
	post.add_child(Geo.box_mesh_node(Vector3(0.12, 3.2, 0.12), NightProps.metal(Color(0.6, 0.6, 0.6), 0.3), Vector3(-1.0, 1.6, 0)))
	var lamp := Geo.box_mesh_node(Vector3(0.3, 0.3, 0.1), NightProps.glow(Color(1.0, 0.08, 0.04), 12.0), Vector3(-1.0, 2.9, 0.1))
	post.add_child(lamp)
	var red := OmniLight3D.new()
	red.light_color = Color(1.0, 0.1, 0.05)
	red.light_energy = 1.5
	red.omni_range = 9.0
	red.position = Vector3(-1.0, 2.9, 0.5)
	post.add_child(red)
	Geo.add_box_shape(post, Vector3(0, 0.6, 0), Vector3(0.3, 1.2, 0.3))
	p.add_child(post)
	var tw := red.create_tween().set_loops()
	tw.tween_property(red, "light_energy", 0.0, 0.5)
	tw.tween_property(red, "light_energy", 1.5, 0.05)
	tw.tween_interval(0.45)
	# Bahnwaerterhaeuschen
	NightProps.house(p, Vector3(14.0, 0, -219.0), 180.0, Vector3(4.5, 2.6, 3.5), Color(0.5, 0.45, 0.3), rng, {"lit": 1.0, "door": false})

# ------------------------------------------------------------------ Marker, Wellen, Trigger

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(2.5, TRENCH_FLOOR + 0.1, 0.3), "player_spawn")
	ps.name = "PlayerSpawn"
	# Gegner: [typ, welle, x, y, z]  (34 gesamt)
	var spawns: Array = [
		["rifleman", 0, -6.0, 0.05, -53.6], ["rifleman", 0, 8.3, 0.05, -56.7], ["rifleman", 0, -13.0, 0.05, -49.6],
		["rifleman", 0, 14.0, 0.05, -43.3], ["rifleman", 0, -4.0, 0.05, -62.6], ["rifleman", 0, 14.3, 0.05, -61.2],
		["rifleman", 0, -11.0, 0.05, -46.0], ["assault", 0, 7.0, 0.05, -52.0], ["rifleman", 0, -5.0, 0.05, -58.0],
		["rifleman", 1, -2.9, 0.05, -82.0], ["rifleman", 1, 2.2, 0.05, -88.5], ["rifleman", 1, -2.5, 0.05, -91.0],
		["assault", 1, 2.5, 0.05, -102.0], ["drone", 1, 0.0, 6.0, -100.0],
		["rifleman", 1, -8.0, 0.05, -84.0], ["rifleman", 1, 7.0, 0.05, -96.0], ["marksman", 1, -8.0, 0.05, -102.0],
		["rifleman", 2, 3.6, 0.05, -142.0], ["rifleman", 2, -3.5, 0.05, -160.0], ["rifleman", 2, 6.5, 0.05, -153.5],
		["marksman", 2, -6.5, 0.05, -172.0], ["heavy", 2, 1.0, 0.05, -167.0],
		["rifleman", 2, 4.0, 0.05, -150.0], ["assault", 2, -5.0, 0.05, -147.0], ["rifleman", 2, 7.0, 0.05, -165.0],
		["assault", 3, -6.0, 0.05, -192.0], ["officer", 3, -8.0, 0.05, -201.0], ["rifleman", 3, 9.0, 0.05, -215.0],
		["heavy", 3, 5.0, 0.05, -214.0], ["drone", 3, -5.0, 7.0, -195.0], ["drone", 3, 6.0, 8.0, -205.0],
		["rifleman", 3, 10.0, 0.05, -203.0], ["rifleman", 3, -8.0, 0.05, -212.0], ["assault", 3, -11.0, 0.05, -197.0],
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, Vector3(s[2], s[3], s[4]), "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for c in covers:
		var v: Vector3 = c
		if absf(v.x) > 28.0 or v.z > 0.0:
			continue
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	for i in ROUTE.size():
		var r: Vector2 = ROUTE[i]
		var y := TRENCH_FLOOR + 0.05 if absf(r.y) <= TRENCH_Z else 0.05
		var w := Geo.marker(m, Vector3(r.x, y, r.y), "bot_waypoint")
		w.name = "Waypoint%02d" % i
		w.set_meta("order", i)
	# Wellen
	_trigger("TriggerWave1", Vector3(0, 3, -62.0), Vector3(60, 6, 1.5), func() -> void: _spawn_wave(1))
	_trigger("TriggerWave2", Vector3(0, 3, -112.0), Vector3(60, 6, 1.5), func() -> void: _spawn_wave(2))
	_trigger("TriggerWave3", Vector3(0, 3, -170.0), Vector3(60, 6, 1.5), func() -> void: _spawn_wave(3))
	# Set-Piece Sperrfeuer
	_trigger("TriggerBarrage", Vector3(0, 3, -126.0), Vector3(60, 6, 1.5), trigger_setpiece)
	# Checkpoints
	_trigger("Checkpoint1", Vector3(0, 3, -66.0), Vector3(60, 6, 1.5), func() -> void: _checkpoint("cp_forest"))
	_trigger("Checkpoint2", Vector3(0, 3, -168.0), Vector3(60, 6, 1.5), func() -> void: _checkpoint("cp_square"))
	# Levelende hinter dem Bahnuebergang
	var area := _trigger("LevelEnd", Vector3(0.5, 2.0, -230.0), Vector3(12, 4, 3), _on_level_end, false)
	area.add_to_group("level_end")

# ------------------------------------------------------------------ Set-Pieces

func _build_set_piece_geometry() -> void:
	tower = WaterTower.new()
	tower.name = "WaterTower"
	tower.set("max_health", 100.0)
	tower.position = Vector3(-14.0, 0, -191.0)
	world.add_child(tower)
	covers.append(Vector3(-11.6, 0, -191.0))
	fuel = FuelTank.new()
	fuel.name = "FuelTank"
	fuel.position = Vector3(-11.0, 0, -187.5)
	fuel.rotation_degrees.y = 60.0
	world.add_child(fuel)
	# Tank-Explosion knickt die Turmbeine
	fuel.connect("exploded", func() -> void:
		get_tree().create_timer(0.5).timeout.connect(trigger_tower))
	covers.append(Vector3(-10.0, 0, -183.5))

func _run_barrage() -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	# Vorwarnung: zwei Einschlaege weit hinter der Haeuserzeile
	if fx != null:
		fx.call("artillery_strike", Vector3(-28.0, 0, -122.0), 3.0, 0.15)
	await get_tree().create_timer(0.9).timeout
	if fx != null:
		fx.call("artillery_strike", Vector3(-24.0, 0, -160.0), 3.2, 0.15)
	await get_tree().create_timer(0.8).timeout
	for i in _doomed.size():
		var h: Dictionary = _doomed[i]
		_shell_hit(h, pl)
		await get_tree().create_timer(0.45).timeout
		if fx != null:
			fx.call("artillery_strike", (h["center"] as Vector3) + Vector3(-4.0, -2.0, rng.randf_range(-2, 2)), 2.6, 0.2)
		await get_tree().create_timer(0.75).timeout

func _shell_hit(h: Dictionary, pl: Node3D) -> void:
	var c: Vector3 = h["center"]
	VFX.spawn_explosion(c + Vector3(0, 0.5, 0), 3.6)
	VFX.spawn_dust_cloud(c, 7.0)
	Events.explosion.emit(c, 6.0, 2.5)
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", 0.35)
	if fx != null:
		fx.call("artillery_strike", c + Vector3(0, 1.0, 0), 0.01, 0.0)
	var shape: CollisionShape3D = h["shape"]
	shape.set_deferred("disabled", true)
	for p in h["pieces"]:
		var rb: RigidBody3D = p
		if not is_instance_valid(rb):
			continue
		rb.freeze = false
		rb.collision_layer = 8
		rb.collision_mask = 1 | 8
		var d := (rb.global_position - c)
		d.y = 0.0
		var dir := (d.normalized() * 0.6 + Vector3(-0.8, 0.9, 0) + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0, 0.6), rng.randf_range(-0.4, 0.4))).normalized()
		rb.apply_central_impulse(dir * rb.mass * rng.randf_range(4.0, 9.0))
		rb.apply_torque_impulse(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rb.mass * 2.0)
		DebrisSettle.solidify_when_settled(rb, 3.0, 12.0)
	# Truemmerhaufen + Brand im Grundriss
	var base: Vector3 = (h["body"] as Node3D).global_position
	Props.rubble(world, base + Vector3(-0.5, 0, 0), 3.2, 1.3, rng, false)
	Props.fire(world, base + Vector3(rng.randf_range(-1.5, 0.5), 0.6, rng.randf_range(-2, 2)), 1.6, true, 1.6, 7.0)
	Props.crater(world, base + Vector3(1.5, 0, 0), 3.0, rng)

# ------------------------------------------------------------------ Kulisse

func _build_skyline() -> void:
	var trees_play: Array = []
	var trees_near: Array = []
	var trees_far: Array = []
	var placed: Array[Vector2] = []
	var trng := RandomNumberGenerator.new()
	trng.seed = build_seed + 7
	# Wald im Spielbereich (z -64..-110)
	for i in 900:
		var p := Vector3(trng.randf_range(-29.0, 29.0), 0, trng.randf_range(-110.0, -63.0))
		if _route_dist(p) < 4.2 or not _free(placed, p, 2.8):
			continue
		# Freiflaechen um Deckungen (Staemme/Felsen) nicht zuwachsen
		placed.append(Vector2(p.x, p.z))
		trees_play.append([p, trng.randf_range(0.85, 1.25)])
	# Waldraender links/rechts der ganzen Strecke, hinter dem Graben, hinter dem Bahnuebergang
	for i in 4200:
		var p := Vector3(trng.randf_range(-95.0, 95.0), 0, trng.randf_range(-320.0, 60.0))
		var ax := absf(p.x)
		var ok := false
		if ax > 31.0:
			ok = true
		elif p.z > 16.0:
			ok = true
		elif p.z < end_z - 8.0:
			ok = true
		elif ax > 26.0 and p.z < -60.0:
			ok = true
		if not ok:
			continue
		if p.z < -112.0 and p.z > -215.0 and ax < 34.0:
			continue   # Dorf und Platz frei
		if not _free(placed, p, 3.3):
			continue
		placed.append(Vector2(p.x, p.z))
		var near := ax < 45.0 and p.z > end_z - 30.0
		(trees_near if near else trees_far).append([p, trng.randf_range(0.8, 1.35)])
	var f := Node3D.new()
	f.name = "Forest"
	add_child(f)
	NightProps.forest(f, trees_play, trng, true)
	NightProps.forest(f, trees_near, trng, true)
	NightProps.forest(f, trees_far, trng, false)
	NightProps.trunk_colliders(world, trees_play)
	_trees_play = trees_play
	# Junge Kiefern / Unterholz (nur Optik)
	var young: Array = []
	for i in 260:
		var p := Vector3(trng.randf_range(-29.0, 29.0), 0, trng.randf_range(-110.0, -60.0))
		if _route_dist(p) < 3.0:
			continue
		young.append([p, trng.randf_range(0.18, 0.35)])
	NightProps.forest(f, young, trng, false)
	_build_ground_cover(placed)
	# Ferne Brandherde am Horizont (Glut im Nebel)
	for c: Vector3 in [Vector3(-75, 0, -60), Vector3(85, 0, -140), Vector3(-90, 0, -210), Vector3(60, 0, -290), Vector3(-40, 0, -300)]:
		Props.fire(self, c, 3.2, false, 3.5)
		var gl := OmniLight3D.new()
		gl.light_color = Color(1.0, 0.42, 0.14)
		gl.light_energy = 6.0
		gl.omni_range = 45.0
		gl.light_volumetric_fog_energy = 3.0
		gl.position = c + Vector3(0, 6, 0)
		add_child(gl)

## Baumstumpf (Poly Haven, verschneit) mit Zylinder-Kollision um den Wurzelkern.
func _stump(parent: Node3D, mname: String, pos: Vector3, yaw: float, s: float) -> void:
	var b := Geo.static_body(pos * Vector3(1, 0, 1))
	PH.place(b, mname, PH.xform(Vector3(0, -0.06, 0), yaw, Vector3.ONE * s), 0.38)
	var cs := CollisionShape3D.new()
	var cy := CylinderShape3D.new()
	cy.radius = 0.5 * s
	cy.height = 0.9
	cs.shape = cy
	cs.position = Vector3(0, 0.2, 0)
	b.add_child(cs)
	parent.add_child(b)

## Bodenbewuchs im Schnee: trockene Grasbueschel und Unkraut, die durch die Schneedecke ragen,
## Reisig und weitere Stuempfe im Wald. Eigener Zufallsstrom (der Level-rng bleibt unveraendert).
func _build_ground_cover(placed: Array[Vector2]) -> void:
	var gr := RandomNumberGenerator.new()
	gr.seed = build_seed + 31
	var patch := FastNoiseLite.new()
	patch.seed = build_seed + 5
	patch.frequency = 0.07
	var gc := Node3D.new()
	gc.name = "GroundCover"
	add_child(gc)
	var ok := func(q: Vector3) -> bool:
		if q.z > RAMP_END_Z - 0.6 and q.z < TRENCH_Z + 0.6 and absf(q.x) < TRENCH_X + 0.6:
			return false   # Graben/Rampen
		if q.z < -112.0 and q.z > -215.0 and absf(q.x) < 34.0:
			return false   # Dorf/Platz
		if _route_dist(q) < 0.9:
			return false   # ausgetretener Pfad
		return patch.get_noise_2d(q.x, q.z) > -0.15
	# Strohige, bereifte Toene (Nacht, Schnee): Gras entsaettigt, Unkraut braun
	var straw := Color(1.05, 0.88, 0.62)
	var halms := GroundCover.points(gr, 16000, -40.0, 40.0, end_z - 20.0, 26.0, Vector2(0.7, 1.3), ok)
	GroundCover.scatter(gc, "grass01", halms, {"only": "tall", "mult": 2.4, "tint": straw, "fade": Vector2(20, 30), "seed": 6})
	var grass := GroundCover.points(gr, 5200, -40.0, 40.0, end_z - 20.0, 26.0, Vector2(0.75, 1.3), ok)
	GroundCover.scatter(gc, "grass02", grass, {"mult": 2.2, "tint": straw, "fade": Vector2(26, 40), "seed": 3})
	var weeds := GroundCover.points(gr, 900, -40.0, 40.0, end_z - 20.0, 26.0, Vector2(0.7, 1.2), ok)
	GroundCover.scatter(gc, "weed", weeds, {"mult": 2.0, "tint": Color(0.85, 0.7, 0.5), "fade": Vector2(24, 36), "seed": 4})
	# Reisig und Bruchholz auf dem Waldboden (Spielbereich), nicht auf dem Pfad
	var wood_ok := func(q: Vector3) -> bool:
		return _route_dist(q) > 1.6
	var br := GroundCover.points(gr, 260, -29.0, 29.0, -110.0, -62.0, Vector2(0.9, 1.5), wood_ok, 0.0, 8.0)
	GroundCover.scatter(gc, "branches", br, {"tint": Color(0.82, 0.82, 0.86), "fade": Vector2(26, 38), "seed": 5})
	# weitere Stuempfe (Kollision) im Spielwald; Abstand zu Pfad, Baeumen und Deckungen
	var n := 0
	for i in 160:
		if n >= 14:
			break
		var q := Vector3(gr.randf_range(-27.0, 27.0), 0, gr.randf_range(-108.0, -64.0))
		if _route_dist(q) < 3.2 or not _free(placed, q, 1.9):
			continue
		placed.append(Vector2(q.x, q.z))
		_stump(world, "tree_stump_02" if n % 3 == 0 else "tree_stump_01", q, gr.randf_range(0.0, 360.0), gr.randf_range(0.7, 0.95))
		n += 1

func _free(placed: Array[Vector2], p: Vector3, d: float) -> bool:
	var q := Vector2(p.x, p.z)
	var d2 := d * d
	for o in placed:
		if o.distance_squared_to(q) < d2:
			return false
	return true

func _build_atmosphere() -> void:
	fx = NightFx.new()
	fx.name = "NightFx"
	fx.set("end_z", end_z)
	fx.set("artillery_enabled", false)
	add_child(fx)
	# Suchscheinwerfer: zwei eigene hinter dem Graben, einer feindlich am Bahnuebergang
	_searchlight_tower(Vector3(-18.0, 0, 9.0))
	_searchlight_tower(Vector3(18.0, 0, 9.0))
	# Startfeld: Lichtkegel als schmaler Strahl statt Glow-Blob (Volumen-Streuung 5 -> 1.4, Linse 40 -> 14).
	# Im groben Froxel-Nebel verschmierte der 3.6-Grad-Strahl sonst zu einer halbbildgrossen weissen Wolke.
	for sp: Array in [[Vector3(-18.0, 5.6, 9.0), 8.0, -4.5, 22.0, 0.22], [Vector3(18.0, 5.6, 9.0), -6.0, -4.0, 24.0, 0.17]]:
		var sl: SpotLight3D = fx.call("add_searchlight", sp[0], sp[1], sp[2], sp[3], sp[4], 34.0)
		if sl != null:
			sl.light_volumetric_fog_energy = 1.4
			for c in sl.get_children():
				var mi := c as MeshInstance3D
				if mi != null and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).emission_enabled:
					(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 14.0
	_searchlight_tower(Vector3(-16.0, 0, -232.0))
	var dsl: SpotLight3D = fx.call("add_searchlight", Vector3(-16.0, 5.6, -232.0), 172.0, -12.0, 30.0, 0.15, 28.0)
	# Blendung am Dorfplatz daempfen: weniger Volumen-Streulicht und schwaechere Linse
	if dsl != null:
		dsl.light_volumetric_fog_energy = 1.8
		for c in dsl.get_children():
			var mi := c as MeshInstance3D
			if mi != null and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).emission_enabled:
				(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 12.0
	# Brennende Scheune: mehrere Feuer, zwei flackernde Lichter mit Schatten
	for fp: Vector3 in [Vector3(14.0, 0.6, -190.0), Vector3(16.0, 0.6, -198.0), Vector3(12.5, 3.2, -201.0), Vector3(19.0, 4.8, -193.0), Vector3(13.0, 4.5, -188.0)]:
		Props.fire(world, fp, 1.9 if fp.y < 1.0 else 1.4, false, 2.4)
	fx.call("add_fire_light", Vector3(8.0, 2.6, -193.0), 9.0, 28.0, true)
	fx.call("add_fire_light", Vector3(15.0, 3.0, -199.0), 7.0, 20.0, true)
	# Brennendes Haus rechts in der Gasse (Fenster), Glut im Panzerwrack
	Props.fire(world, Vector3(6.0, 1.7, -147.0), 0.9, true, 1.3, 5.0)
	Props.fire(world, Vector3(15.0, 1.4, -57.0), 1.1, true, 1.6, 4.0)
	# Bodennebel ueber dem Feld und im Wald
	for z: float in [-25.0, -55.0, -85.0, -140.0, -195.0]:
		Props.fog_volume(self, Vector3(0, 1.0, z), Vector3(70, 3.0, 30), 0.03, Color(0.7, 0.75, 0.85))

func _searchlight_tower(base: Vector3) -> void:
	var b := Geo.static_body(base)
	var bb := Geo.batch()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			bb.add(Vector3(sx * 0.9, 2.6, sz * 0.9), Vector3(0.18, 5.2, 0.18), Basis(Vector3(sz, 0, -sx).normalized(), 0.06))
	bb.add(Vector3(0, 5.15, 0), Vector3(2.2, 0.14, 2.2))
	for y: float in [1.6, 3.4]:
		bb.add(Vector3(0, y, 0.95), Vector3(2.0, 0.1, 0.1))
		bb.add(Vector3(0, y, -0.95), Vector3(2.0, 0.1, 0.1))
	NightProps.add_batch(b, bb, NightProps.planks(Color(0.3, 0.26, 0.22), 0.4))
	Geo.add_box_shape(b, Vector3(0, 2.6, 0), Vector3(2.0, 5.2, 2.0))
	world.add_child(b)

# ------------------------------------------------------------------ Navigation / Artillerie

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
	nm.filter_baking_aabb = AABB(Vector3(-30.0, -2.0, end_z - 8.0), Vector3(60.0, 16.0, 22.0 - end_z + 8.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

func _start_artillery() -> void:
	if fx != null:
		fx.set("artillery_enabled", true)
