class_name JetFlyby
extends Node3D
## Tiefflug eines Kampfjets (Set-Piece). run(from, to, bomb_targets) startet den Ueberflug.
## Nachbrenner, Kondensstreifen an den Fluegelspitzen, Doppler (manuell ueber pitch_scale),
## Ueberschallknall beim Passieren der Kamera, Bomben mit Pfeifen und Explosionskette. Danach queue_free.

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const SOUND_SPEED := 343.0

@export var speed: float = 210.0                  ## m/s
@export var faction: String = "eu"                ## Optik: "eu" (grau) | "ru" (Tarnung)
@export var bomb_damage: float = 140.0
@export var bomb_radius: float = 9.0
@export var boom: bool = true                     ## Ueberschallknall + Kamera-Ruck

var _from: Vector3
var _to: Vector3
var _dir: Vector3
var _len: float = 0.0
var _dist: float = 0.0
var _running: bool = false
var _pending_bombs: int = 0
var _bombs: Array[Vector3] = []
var _boomed: bool = false
var _last_radial: float = 0.0
var _model: Node3D
var _loop: AudioStreamPlayer3D
var _trails: Array[GPUParticles3D] = []
var _flame: MeshInstance3D
var _flame_mat: StandardMaterial3D
var _t: float = 0.0

func _ready() -> void:
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	_build_model()
	visible = false
	set_physics_process(false)

## Startet den Ueberflug. Bomben fallen auf bomb_targets (Abwurf auf Hoehe des naechsten Bahnpunkts).
func run(from: Vector3, to: Vector3, bomb_targets: Array[Vector3] = []) -> void:
	_from = from
	_to = to
	_len = from.distance_to(to)
	_dir = (to - from).normalized() if _len > 0.01 else Vector3.FORWARD
	_dist = 0.0
	_bombs = bomb_targets.duplicate()
	_bombs.sort_custom(func(a: Vector3, b: Vector3) -> bool: return (a - from).dot(_dir) < (b - from).dot(_dir))
	_pending_bombs = _bombs.size()
	_running = true
	_boomed = false
	visible = true
	var up := Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT
	global_transform = Transform3D(Basis.looking_at(_dir, up), from)
	if _loop == null:
		_loop = VF.loop_player(self, "veh_jet_loop", 60.0, 2500.0, 6.0)
	if _loop:
		_loop.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	for tr in _trails:
		tr.emitting = true
	set_physics_process(true)

func _physics_process(delta: float) -> void:
	if not _running:
		return
	_t += delta
	var prev := _dist
	_dist += speed * delta
	var p := _from + _dir * minf(_dist, _len)
	# leichtes Schaukeln und Querneigung fuer Lebendigkeit
	_model.rotation.z = sin(_t * 1.3) * 0.08
	_model.position.y = sin(_t * 2.1) * 0.3
	global_position = p
	# Bomben ausloesen, wenn der Jet ueber den Ziel-Fusspunkt zieht (mit Vorhalt fuer die Fallzeit)
	while not _bombs.is_empty():
		var tgt: Vector3 = _bombs[0]
		var h := maxf(p.y - tgt.y, 5.0)
		var fall := clampf(sqrt(2.0 * h / 9.8), 1.2, 4.5)
		var lead := minf(speed * fall * 0.35, 260.0)  # Bombe behaelt einen Teil der Fluggeschwindigkeit
		var along := (tgt - _from).dot(_dir) - lead
		if _dist >= along:
			_bombs.pop_front()
			_drop_bomb(p, tgt, fall)
		else:
			break
	_update_audio(delta)
	_flame_mat.albedo_color.a = 0.75 + 0.25 * sin(_t * 70.0)
	_flame.scale = Vector3(1, 1.0 + 0.15 * sin(_t * 53.0), 1)
	if prev < _len and _dist >= _len:
		_finish()

func _update_audio(_delta: float) -> void:
	var cam := VF.camera(self)
	if cam == null:
		return
	var to_cam := cam.global_position - global_position
	var d := to_cam.length()
	var radial := (_dir * speed).dot(to_cam / maxf(d, 0.01))  # >0: naehert sich
	if _loop:
		var pitch := SOUND_SPEED / maxf(SOUND_SPEED - radial * 0.55, 60.0)
		_loop.pitch_scale = clampf(pitch, 0.55, 1.9)
	if boom and not _boomed and _last_radial > 0.0 and radial <= 0.0 and d < 600.0:
		_boomed = true
		var vol := lerpf(6.0, -8.0, clampf(d / 600.0, 0.0, 1.0))
		VF.play_2d(self, "veh_jet_boom", vol, d / SOUND_SPEED * 0.5)
		var player := Game.get_player()
		if player and player.has_method("add_trauma"):
			player.call("add_trauma", lerpf(0.55, 0.15, clampf(d / 400.0, 0.0, 1.0)))
	_last_radial = radial

func _drop_bomb(release: Vector3, target: Vector3, fall: float) -> void:
	var bomb := Node3D.new()
	bomb.name = "Bomb"
	var m := VF.mat("bomb_olive", Color(0.22, 0.24, 0.17), 0.6, 0.4)
	VF.mesh_node(bomb, VF.capsule(0.17, 1.6, 12), m, Vector3.ZERO, Vector3(90, 0, 0))
	for i in 4:
		VF.mesh_node(bomb, VF.box(Vector3(0.02, 0.32, 0.3)), m, Vector3(0, 0, 0.75), Vector3(0, 0, 45 + i * 90))
	VF.effects_root(self).add_child(bomb)
	bomb.global_position = release + Vector3.DOWN * 1.2
	var wst := Sfx.get_stream("veh_bomb_whistle")
	if wst:
		var whistle := AudioStreamPlayer3D.new()
		whistle.stream = wst
		whistle.bus = &"SFX"
		whistle.unit_size = 25.0
		whistle.max_distance = 600.0
		whistle.volume_db = 2.0
		bomb.add_child(whistle)
		# Pfeifen endet mit dem Einschlag: Startoffset so waehlen, dass das Ende auf den Aufprall faellt
		whistle.play(maxf(wst.get_length() - fall, 0.0))
	var vel0 := _dir * speed * 0.35
	var tw := bomb.create_tween()
	tw.tween_method(func(t: float) -> void:
		var tt := t * fall
		var lin := release.lerp(target, t)  # Basisbahn, Endpunkt garantiert
		var arc := vel0 * tt * (1.0 - t) * 0.6  # Vorwaertsbogen, endet auf dem Ziel
		var drop := Vector3.UP * (release.y - target.y) * (t - t * t) * 0.9  # zuerst flach, dann steil
		var np := lin + arc + drop
		var v := np - bomb.global_position
		if v.length() > 0.001:
			bomb.look_at(np + v, Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT)
		bomb.global_position = np, 0.0, 1.0, fall)
	tw.tween_callback(func() -> void:
		Combat.explode(target, bomb_radius, bomb_damage, self, 2.6)
		VFX.spawn_dust_cloud(target, 6.0)
		VFX.spawn_scorch(target, Vector3.UP, 7.0, 180.0)
		VF.shake_player(self, target, 0.5, 70.0)
		bomb.queue_free()
		_pending_bombs -= 1
		_try_free())

func _finish() -> void:
	_running = false
	# Modell bleibt sichtbar (Jet ist am Bahnende weit weg), Streifen verwehen noch
	for tr in _trails:
		tr.emitting = false
	if _loop:
		var tw := create_tween()
		tw.tween_property(_loop, "volume_db", -60.0, 1.5)
	set_physics_process(false)
	get_tree().create_timer(3.0, false).timeout.connect(_try_free)

func _try_free() -> void:
	if not _running and _pending_bombs <= 0 and is_inside_tree():
		queue_free()

# ------------------------------------------------------------------ Modell (prozedural, -Z = Flugrichtung)

func _build_model() -> void:
	var body := VF.mat("jet_grey", Color(0.36, 0.39, 0.42), 0.5, 0.45)
	if faction == "ru":
		body = VF.camo_mat("jet_ru", Color(0.38, 0.45, 0.5), Color(0.5, 0.56, 0.6), Color(0.28, 0.33, 0.37), 0.08, 0.5)
	var dark := VF.mat("jet_dark", Color(0.12, 0.12, 0.13), 0.45, 0.7)
	var m := _model
	# Rumpf
	VF.mesh_node(m, VF.cyl(0.62, 0.7, 9.0, 18), body, Vector3(0, 0, 0.5), Vector3(90, 0, 0))
	VF.mesh_node(m, VF.cyl(0.05, 0.62, 3.6, 18), body, Vector3(0, 0, -5.8), Vector3(-90, 0, 0))
	VF.mesh_node(m, VF.cyl(0.62, 0.55, 1.0, 18), dark, Vector3(0, 0, 5.4), Vector3(90, 0, 0))
	# Lufteinlaesse
	for s in [-1.0, 1.0]:
		VF.mesh_node(m, VF.box(Vector3(0.5, 0.75, 4.0)), body, Vector3(0.78 * s, -0.2, -0.2))
		VF.mesh_node(m, VF.box(Vector3(0.42, 0.62, 0.05)), dark, Vector3(0.78 * s, -0.2, -2.2))
	# Cockpit
	VF.mesh_node(m, VF.sphere(0.48, 2.4, 16), VF.glass_mat(Color(0.25, 0.22, 0.12, 0.7)), Vector3(0, 0.55, -3.6), Vector3.ZERO, Vector3(1, 0.8, 2.4))
	# Delta-Fluegel (flaches Prisma) und Canards
	var wing := VF.prism(Vector3(11.0, 6.5, 0.14), 0.5)
	VF.mesh_node(m, wing, body, Vector3(0, -0.1, 1.6), Vector3(-90, 0, 0))
	VF.mesh_node(m, VF.prism(Vector3(3.4, 1.4, 0.08), 0.5), body, Vector3(0, 0.15, -3.0), Vector3(-90, 0, 0))
	# Seitenleitwerk
	VF.mesh_node(m, VF.prism(Vector3(3.2, 3.0, 0.12), 1.0), body, Vector3(0, 1.9, 3.6), Vector3(0, 90, 0))
	# Waffen unter den Fluegeln
	for s in [-1.0, 1.0]:
		VF.mesh_node(m, VF.capsule(0.17, 1.6, 10), VF.mat("bomb_olive", Color(0.22, 0.24, 0.17), 0.6, 0.4), Vector3(2.4 * s, -0.4, 1.4), Vector3(90, 0, 0))
		VF.mesh_node(m, VF.cyl(0.08, 0.08, 2.6, 8), VF.mat("jet_missile", Color(0.8, 0.8, 0.78), 0.4, 0.2), Vector3(5.2 * s, -0.2, 2.2), Vector3(90, 0, 0))
	# Positionslichter
	VF.mesh_node(m, VF.sphere(0.07), VF.mat("nav_red_e", Color.RED, 0.3, 0.0, Color(1, 0.1, 0.05), 6.0), Vector3(-5.4, -0.05, 4.4))
	VF.mesh_node(m, VF.sphere(0.07), VF.mat("nav_green_e", Color.GREEN, 0.3, 0.0, Color(0.1, 1, 0.2), 6.0), Vector3(5.4, -0.05, 4.4))
	# Nachbrenner: Flammenkegel + Schockdiamanten + Licht
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flame_mat.albedo_color = Color(1.0, 0.55, 0.25, 0.9)
	_flame_mat.albedo_texture = _flame_gradient()
	_flame = VF.mesh_node(m, VF.cyl(0.02, 0.5, 4.5, 16), _flame_mat, Vector3(0, 0, 8.1), Vector3(90, 0, 0))
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := _flame_mat.duplicate() as StandardMaterial3D
	core_mat.albedo_color = Color(0.6, 0.75, 1.0, 0.9)
	var core := VF.mesh_node(m, VF.cyl(0.05, 0.38, 2.0, 12), core_mat, Vector3(0, 0, 6.9), Vector3(90, 0, 0))
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = 8.0
	l.omni_range = 30.0
	l.position = Vector3(0, 0, 8.0)
	m.add_child(l)
	# Kondensstreifen an den Fluegelspitzen + Abgasschleier
	_trails.append(_make_trail(Vector3(-5.4, -0.05, 4.4), 0.25, 0.55))
	_trails.append(_make_trail(Vector3(5.4, -0.05, 4.4), 0.25, 0.55))
	_trails.append(_make_trail(Vector3(0, 0, 7.0), 0.8, 0.25))

func _flame_gradient() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 1.0))
	g.add_point(0.6, Color(1, 0.8, 0.6, 0.7))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 1)
	t.fill_to = Vector2(0, 0)
	t.width = 8
	t.height = 64
	return t

func _make_trail(local: Vector3, size: float, alpha: float) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 2.0
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 2.0
	pm.gravity = VfxLib.WIND * 0.3
	pm.scale_min = size
	pm.scale_max = size * 1.4
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.4], [0.2, 1.0], [1.0, 4.0]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(alpha, 0.05, 0.4)
	var mat := VfxLib.smoke_mat({"smoke_color": Color(0.75, 0.77, 0.8), "smoke_color_end": Color(0.6, 0.62, 0.66), "density": 0.75, "glow": 0.0, "soft_dist": 0.5}, true)
	var p := VfxLib.make_particles(260, 2.6, pm, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.emitting = false
	p.local_coords = false
	p.fixed_fps = 0
	p.visibility_aabb = AABB(Vector3(-40, -40, -600), Vector3(80, 80, 1200))
	p.position = local
	_model.add_child(p)
	return p
