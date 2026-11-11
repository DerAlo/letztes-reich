extends Node3D
## Ueberwachungskamera fuer "villa": schwenkt zwischen zwei Winkeln, erkennt Kerner im Kegel (Reichweite,
## Sichtlinie, Licht), baut Verdacht auf und loest bei vollem Verdacht Alarm aus (raise_alarm "camera").
## Watcher-Schnittstelle fuer den Schleich-Direktor/HUD (ohne join_combat -> zaehlt wie Drohne/Scheinwerfer).
## Abschiessbar (take_damage ueber den StaticBody darunter). Die Aufklaerungsdrohne kann sie markieren.

const Geo = preload("res://game/levels/level_geo.gd")

const RANGE := 16.0
const HALF_ANGLE := 28.0
const PITCH_DEG := -24.0

var director: Node
var yaw_a: float = 0.0          ## Schwenkgrenzen (Grad, 0 = Blick nach -Z)
var yaw_b: float = 90.0
var sweep_period: float = 9.0
var suspicion: float = 0.0
var health: float = 20.0

var _head: Node3D
var _led: MeshInstance3D
var _led_mat: StandardMaterial3D
var _body: StaticBody3D
var _t: float = 0.0
var _check_t: float = 0.0
var _seen: bool = false
var _track_t: float = 0.0
var _dead: bool = false
var _yaw: float = 0.0
var _sweep: float = 0.0

func _ready() -> void:
	add_to_group("villa_camera")
	_sweep = randf() * TAU
	var dark := Geo.flat(Color(0.12, 0.12, 0.13), 0.5, 0.4)
	var white := Geo.flat(Color(0.82, 0.82, 0.8), 0.45, 0.1)
	# Wandhalter
	add_child(Geo.box_mesh_node(Vector3(0.12, 0.12, 0.12), dark, Vector3.ZERO))
	_head = Node3D.new()
	add_child(_head)
	_head.add_child(Geo.box_mesh_node(Vector3(0.18, 0.16, 0.38), white, Vector3(0, -0.06, -0.12)))
	_head.add_child(Geo.box_mesh_node(Vector3(0.22, 0.03, 0.44), white, Vector3(0, 0.035, -0.1)))
	var lens := Geo.cylinder_node(0.05, 0.04, Geo.flat(Color(0.02, 0.02, 0.03), 0.1, 0.6), Vector3(0, -0.06, -0.32), Vector3(90, 0, 0), 10)
	_head.add_child(lens)
	_led_mat = Geo.flat(Color(0.2, 0.0, 0.0), 0.5, 0.0, Color(1.0, 0.1, 0.05), 3.0)
	_led = Geo.box_mesh_node(Vector3(0.025, 0.025, 0.02), _led_mat, Vector3(0.06, -0.01, -0.315))
	_head.add_child(_led)
	_body = StaticBody3D.new()
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta("no_fit", true)
	Geo.add_box_shape(_body, Vector3(0, -0.04, -0.1), Vector3(0.26, 0.24, 0.5))
	_head.add_child(_body)
	if director != null:
		director.call("register_watcher", self)

func _physics_process(delta: float) -> void:
	_t += delta
	if _dead:
		return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.1
		_seen = _sees(pl)
	if _seen and pl != null:
		# im Bild: Kamera folgt dem Ziel
		var to := pl.global_position - global_position
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), clampf(delta * 3.0, 0.0, 1.0))
		var light := 0.5
		if director != null:
			light = float(director.get("player_light"))
		var k := (0.45 if bool(pl.get("is_crouching")) else 1.0) * (0.45 + 0.75 * light)
		var dist := global_position.distance_to(pl.global_position)
		k *= 1.0 - 0.5 * clampf(dist / RANGE, 0.0, 1.0)
		suspicion = minf(1.0, suspicion + 0.7 * k * delta)
		if suspicion >= 1.0:
			if _track_t <= 0.0:
				_beep()
			_track_t = 5.0
			if director != null and not bool(director.get("alarm")):
				director.call("raise_alarm", pl.global_position, "camera", false)
	else:
		suspicion = maxf(0.0, suspicion - 0.22 * delta)
		_track_t = maxf(0.0, _track_t - delta)
		if _track_t <= 0.0:
			_sweep += delta * TAU / sweep_period
			var f := 0.5 - 0.5 * cos(_sweep)
			var want := deg_to_rad(lerpf(yaw_a, yaw_b, f))
			_yaw = lerp_angle(_yaw, want, clampf(delta * 2.0, 0.0, 1.0))
	_head.rotation = Vector3(deg_to_rad(PITCH_DEG), _yaw, 0.0)
	var on := fmod(_t, 1.0 if suspicion < 0.5 else 0.25) < 0.12
	_led_mat.emission_energy_multiplier = 4.0 if on else 0.3

func _sees(pl: Node3D) -> bool:
	if pl == null or not bool(pl.call("is_alive")):
		return false
	var lp := _head.global_position
	var target := pl.global_position + Vector3.UP * 0.9
	var to := target - lp
	var d := to.length()
	if d > RANGE or d < 0.1:
		return false
	var fwd := -_head.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to / d)) > HALF_ANGLE:
		return false
	var q := PhysicsRayQueryParameters3D.create(lp, target, 1)
	q.exclude = [_body.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["collider"] as Node).is_in_group("player")

func _beep() -> void:
	var s: AudioStream = Sfx.get_stream("drone_beep")
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 5.0
	p.pitch_scale = 1.4
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func take_damage(amount: float, _source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _dead:
		return
	health -= amount
	if health <= 0.0:
		_dead = true
		suspicion = 0.0
		_led.visible = false
		_head.rotation.x = deg_to_rad(-70.0)
		VFX.spawn_impact(global_position, Vector3.UP, "metal")

func is_alive() -> bool:
	return not _dead

# ------------------------------------------------------------------ Watcher-Schnittstelle

func get_suspicion() -> float:
	return suspicion

func get_watch_state() -> int:
	if _dead:
		return -1
	if _track_t > 0.0:
		return 2
	return 1 if suspicion > 0.05 else 0

func get_watch_pos() -> Vector3:
	return global_position + Vector3.UP * 0.3

func is_watcher_alive() -> bool:
	return not _dead

func reset_home() -> void:
	suspicion = 0.0
	_track_t = 0.0
	_seen = false
