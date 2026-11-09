extends Node3D
## Eine "Nachrichten-Aufnahme" fuer die Montage am Anfang des Intros (Spielgrafik, Nacht, Schnee).
## shot: 0 = Panzerkolonne, 1 = Grenzposten, 2 = EU-Kolonne mit Hubschraubern, 3 = Raketenstarts.
## Der Director (intro.gd) baut alle Aufnahmen vorab, schaltet sie sichtbar und ruft tick(t) mit der
## lokalen Zeit seit Schnittbeginn.

const Geo = preload("res://game/levels/level_geo.gd")
const NightProps = preload("res://game/levels/night_props.gd")
const NightFx = preload("res://game/levels/night_fx.gd")
const IProps = preload("res://game/intro/intro_props.gd")

var shot: int = 0
var env: Environment
var cam: Camera3D
var rng := RandomNumberGenerator.new()

var _fx: Node3D
var _movers: Array[Dictionary] = []     ## {node, from, vel}
var _missiles: Array[Dictionary] = []   ## {node, start, dir, t0, launched}
var _real: Array[Node3D] = []           ## echte Fahrzeuge (werden erst bei Aktivierung gestartet)
var _flag: Node3D
var _active: bool = false

func _ready() -> void:
	rng.seed = 900 + shot
	env = _make_env()
	_build_common()
	match shot:
		0: _build_column()
		1: _build_border()
		2: _build_eu()
		3: _build_missiles()
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED

## Aufnahme sichtbar machen und Fahrzeuge starten.
func activate() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_INHERIT
	_active = true
	cam.environment = env
	cam.make_current()
	for v in _real:
		_start_real(v)
	tick(0.0)

func tick(t: float) -> void:
	for m in _movers:
		var n: Node3D = m["node"]
		n.position = (m["from"] as Vector3) + (m["vel"] as Vector3) * t
	match shot:
		0: _cam_column(t)
		1: _cam_border(t)
		2: _cam_eu(t)
		3: _tick_missiles(t)
	if _flag != null:
		_flag.rotation.y = sin(t * 2.3) * 0.25
		_flag.rotation.x = sin(t * 5.1) * 0.05

# --------------------------------------------------------------------------- Gemeinsam

func _make_env() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.015, 0.02, 0.04)
	sm.sky_horizon_color = Color(0.06, 0.07, 0.1)
	sm.ground_bottom_color = Color(0.01, 0.012, 0.018)
	sm.ground_horizon_color = Color(0.06, 0.07, 0.1)
	sm.sun_angle_max = 1.0
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.27, 0.4)
	e.ambient_light_energy = 0.3
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.15
	e.ssao_enabled = true
	e.glow_enabled = true
	e.glow_intensity = 0.9
	e.glow_bloom = 0.08
	e.glow_hdr_threshold = 0.9
	e.fog_enabled = true
	e.fog_light_color = Color(0.08, 0.09, 0.12)
	e.fog_density = 0.006 if shot != 3 else 0.0022
	e.fog_sky_affect = 0.85
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.02 if shot != 3 else 0.01
	e.volumetric_fog_albedo = Color(0.78, 0.82, 0.9)
	e.volumetric_fog_emission = Color(0.006, 0.008, 0.014)
	e.volumetric_fog_anisotropy = 0.4
	e.volumetric_fog_length = 90.0
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.1
	e.adjustment_saturation = 0.85
	return e

func _build_common() -> void:
	# Boden mit Kollision (fuer echte Fahrzeuge, die per Raycast am Boden kleben)
	var body := Geo.static_body()
	var size := Vector3(1200, 2, 1200)
	body.add_child(Geo.box_mesh_node(size, NightProps.ground_mat(), Vector3(0, -1, 0)))
	Geo.add_box_shape(body, Vector3(0, -1, 0), size)
	add_child(body)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.65, 1.0)
	moon.light_energy = 0.25
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 120.0
	moon.transform = Transform3D(Basis.looking_at(Vector3(-0.3, -0.6, -0.7).normalized(), Vector3.UP), Vector3.ZERO)
	add_child(moon)
	cam = Camera3D.new()
	cam.far = 1500.0
	add_child(cam)
	_fx = NightFx.new()
	_fx.set("snow_amount", 6000)
	_fx.set("flares_enabled", false)
	_fx.set("tracers_enabled", shot == 1)
	_fx.set("artillery_enabled", false)
	add_child(_fx)

func _road(a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var mid := (a + b) * 0.5
	var mi := Geo.box_mesh_node(Vector3(w, 0.1, d.length()), NightProps.snowy(NightProps.ENV_TEX + "gravel", Color(0.32, 0.31, 0.3), 0.4, 0.3), mid + Vector3(0, 0.02, 0))
	mi.rotation.y = atan2(d.x, d.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## Waldstreifen links/rechts einer Achse. axis_x: Strasse laeuft entlang X (sonst Z).
func _forest_band(axis_x: bool, from: float, to: float, near: float, far: float, count: int) -> void:
	var trees: Array = []
	for i in count:
		var along := rng.randf_range(from, to)
		var off := rng.randf_range(near, far) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p := Vector3(along, 0, off) if axis_x else Vector3(off, 0, along)
		trees.append([p, rng.randf_range(0.8, 1.25)])
	NightProps.forest(self, trees, rng, false)

func _mover(n: Node3D, from: Vector3, vel: Vector3) -> void:
	n.position = from
	add_child(n)
	_movers.append({"node": n, "from": from, "vel": vel})

## Echtes Fahrzeug oder Silhouette. kind: "tank" | "heli". Bewegung als gerade Fahrt from + vel*t.
func _vehicle(kind: String, faction: String, from: Vector3, vel: Vector3, tint: Color) -> void:
	var yaw := atan2(-vel.x, -vel.z)   # Front = -Z
	var path := IProps.TANK_SCENE if kind == "tank" else IProps.HELI_SCENE
	var real := IProps.try_vehicle(path)
	if real != null:
		real.set("faction", faction)
		real.rotation.y = yaw
		real.position = from
		real.set_meta("intro_vel", vel)
		add_child(real)
		if kind == "tank":
			IProps.headlight(real, Vector3(0, 1.3, -3.9), 7.0, 36.0)
			IProps.lamp_pair(real, -3.7, 1.2, 1.1)
		_real.append(real)
		return
	var sil := IProps.tank(tint) if kind == "tank" else IProps.heli(tint)
	sil.rotation.y = yaw
	_mover(sil, from, vel)

func _start_real(v: Node3D) -> void:
	var vel: Vector3 = v.get_meta("intro_vel", Vector3.ZERO)
	var speed := vel.length()
	if speed < 0.01:
		return
	var target: Vector3 = v.global_position + vel * 60.0
	var pts: Array[Vector3] = [target]
	if v.has_method("drive_path"):
		v.call("drive_path", pts, speed)
		v.set("_speed", speed)
	elif v.has_method("fly_path"):
		v.call("fly_path", pts, speed, false)
		v.set("_vel", vel)

# --------------------------------------------------------------------------- 0: Panzerkolonne

func _build_column() -> void:
	_road(Vector3(0, 0, -400), Vector3(0, 0, 60), 7.0)
	_forest_band(false, -400.0, 60.0, 11.0, 40.0, 260)
	for i in 6:
		var z := -48.0 - i * 17.0
		_vehicle("tank", "ru", Vector3(-0.8 if i % 2 == 0 else 0.9, 0, z), Vector3(0, 0, 6.5), Color(0.27, 0.29, 0.24))
	# ferne Lichter weiterer Fahrzeuge
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.9, 0.7)
		l.light_energy = 1.2
		l.omni_range = 8.0
		l.position = Vector3(rng.randf_range(-2, 2), 1.2, -170.0 - i * 22.0)
		add_child(l)
		IProps.lamp_pair(self, l.position.z, 1.1, 1.1)
	cam.fov = 26.0

func _cam_column(t: float) -> void:
	var lead_z := -48.0 + 6.5 * t
	var p := Vector3(8.5 - t * 0.15, 1.7 + sin(t * 1.7) * 0.03, 22.0)
	cam.position = p
	cam.look_at(Vector3(0, 1.6, lerpf(lead_z - 14.0, lead_z - 4.0, 0.5)), Vector3.UP)
	cam.rotate_object_local(Vector3.FORWARD, sin(t * 1.1) * 0.006)

# --------------------------------------------------------------------------- 1: Grenzposten

func _build_border() -> void:
	_road(Vector3(-1.5, 0, -300), Vector3(-1.5, 0, 80), 6.5)
	var d := IProps.border_post(self, rng)
	_flag = d["flag"]
	NightProps.ifv(self, Vector3(4.5, 0, 6.0), 160.0, [])
	_forest_band(false, -300.0, 80.0, 30.0, 70.0, 180)
	_fx.call("add_searchlight", Vector3(9.0, 6.2, 3.0), 200.0, -10.0, 35.0, 0.25, 50.0)
	# Jenseits der Grenze: Scheinwerferkette des Aufmarsches
	for i in 7:
		var x := -40.0 + i * 13.0 + rng.randf_range(-3, 3)
		var tk := IProps.tank(Color(0.25, 0.27, 0.22), true)
		tk.position = Vector3(x, 0, -95.0 - rng.randf_range(0, 25))
		tk.rotation.y = PI + rng.randf_range(-0.3, 0.3)
		add_child(tk)
	cam.fov = 38.0

func _cam_border(t: float) -> void:
	var a := Vector3(13.0, 2.4, 16.0)
	var b := Vector3(9.0, 2.0, 10.5)
	var k := smoothstep(0.0, 6.5, t)
	cam.position = a.lerp(b, k) + Vector3(sin(t * 1.3) * 0.04, sin(t * 2.1) * 0.03, 0)
	cam.look_at(Vector3(-2.5, 1.8, -6.0), Vector3.UP)

# --------------------------------------------------------------------------- 2: EU-Kolonne

func _build_eu() -> void:
	_road(Vector3(-300, 0, 0), Vector3(300, 0, 0), 7.0)
	_forest_band(true, -300.0, 300.0, 14.0, 50.0, 260)
	var grey := Color(0.42, 0.44, 0.42)
	for i in 6:
		var tr := IProps.truck(grey)
		tr.rotation.y = -PI * 0.5   # Front nach +X
		_mover(tr, Vector3(-30.0 - i * 14.0, 0, -1.6), Vector3(8.0, 0, 0))
	for i in 2:
		_vehicle("heli", "eu", Vector3(-70.0 - i * 26.0, 24.0 + i * 4.0, -8.0 - i * 10.0), Vector3(16.0, 0, 0), Color(0.3, 0.33, 0.32))
	cam.fov = 34.0

func _cam_eu(t: float) -> void:
	cam.position = Vector3(-6.0 + t * 1.2, 1.4, 11.0)
	var lead_x := -30.0 + 8.0 * t
	cam.look_at(Vector3(lead_x - 12.0 + t * 1.5, 2.5 + t * 0.9, -2.0), Vector3.UP)

# --------------------------------------------------------------------------- 3: Raketenstarts

func _build_missiles() -> void:
	_forest_band(false, -260.0, -200.0, 0.0, 200.0, 300)
	var delays: Array[float] = [0.5, 1.5, 2.3, 3.4, 4.3]
	for i in delays.size():
		var m := IProps.missile()
		m.visible = false
		m.scale = Vector3.ONE * 2.2
		add_child(m)
		var start := Vector3(-95.0 + i * 45.0 + rng.randf_range(-10, 10), -2.0, -235.0 - rng.randf_range(0, 40))
		var dir := Vector3(rng.randf_range(0.05, 0.22), 1.0, rng.randf_range(-0.1, 0.05)).normalized()
		_missiles.append({"node": m, "start": start, "dir": dir, "t0": delays[i]})
	cam.fov = 34.0

func _tick_missiles(t: float) -> void:
	cam.fov = lerpf(34.0, 27.0, smoothstep(0.0, 6.5, t))
	cam.position = Vector3(sin(t * 0.9) * 0.05, 3.0 + sin(t * 1.4) * 0.03, 0)
	cam.look_at(Vector3(-8, 38.0 + t * 7.0, -240), Vector3.UP)
	for m in _missiles:
		var n: Node3D = m["node"]
		var lt: float = t - float(m["t0"])
		if lt < 0.0:
			continue
		n.visible = true
		var dir: Vector3 = m["dir"]
		var s := 0.5 * 14.0 * lt * lt + 8.0 * lt
		n.position = (m["start"] as Vector3) + dir * s
		n.basis = Basis(Quaternion(Vector3.UP, dir))
