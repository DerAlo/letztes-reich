extends AnimatableBody3D
## Patrouillendrohne der Ordnungsfront (Level "curfew"): fliegt eine Schleife in ~7 m Hoehe und leuchtet
## mit einem Suchlicht nach unten. Erfasst sie Kerner (Kegel + Sicht), meldet sie ihn: Alarm.
## Abschiessbar (Gruppe "enemy"); der Absturz ist laut, Wachen in der Naehe sehen nach.

const SL = preload("res://game/levels/curfew_searchlight.gd")
const Geo = preload("res://game/levels/level_geo.gd")

var director: Node
var path: Array[Vector3] = []
var speed: float = 3.4
var max_health: float = 45.0
var health: float = 45.0

var suspicion: float = 0.0
var _seen: bool = false
var _i: int = 0
var _check_t: float = 0.0
var _track_t: float = 0.0
var _dead: bool = false
var _fall_v: Vector3 = Vector3.ZERO
var _spin: Vector3 = Vector3.ZERO
var _rotors: Array[Node3D] = []
var _blink: OmniLight3D
var _blink_mesh: MeshInstance3D
var _t: float = 0.0
var light: SpotLight3D
var _beam: MeshInstance3D
var _hum: AudioStreamPlayer3D
var _yaw: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("damageable")
	collision_layer = 4
	collision_mask = 0
	sync_to_physics = false
	_build()
	if director != null:
		director.call("register_watcher", self)
	if not path.is_empty():
		global_position = path[0]

func _build() -> void:
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.3, 0.4, 1.3)
	cs.shape = sh
	add_child(cs)
	var body_m := Geo.flat(Color(0.07, 0.075, 0.08), 0.45, 0.5)
	var arm_m := Geo.flat(Color(0.12, 0.12, 0.13), 0.6, 0.3)
	var rotor_m := Geo.flat(Color(0.02, 0.02, 0.02), 0.5)
	var core := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.46, 0.16, 0.62)
	core.mesh = cm
	core.material_override = body_m
	add_child(core)
	var dome := MeshInstance3D.new()
	var dmm := SphereMesh.new()
	dmm.radius = 0.2
	dmm.height = 0.22
	dome.mesh = dmm
	dome.material_override = body_m
	dome.position = Vector3(0, 0.07, 0.04)
	add_child(dome)
	for k in 4:
		var sx := -1.0 if k % 2 == 0 else 1.0
		var sz := -1.0 if k < 2 else 1.0
		var tip := Vector3(sx * 0.52, 0.02, sz * 0.52)
		var arm := MeshInstance3D.new()
		var am := BoxMesh.new()
		am.size = Vector3(0.06, 0.05, 0.74)
		arm.mesh = am
		arm.material_override = arm_m
		arm.position = tip * 0.5
		arm.rotation.y = atan2(tip.x, tip.z)
		add_child(arm)
		var motor := MeshInstance3D.new()
		var mm := CylinderMesh.new()
		mm.top_radius = 0.05
		mm.bottom_radius = 0.06
		mm.height = 0.1
		motor.mesh = mm
		motor.material_override = arm_m
		motor.position = tip + Vector3(0, 0.04, 0)
		add_child(motor)
		var rotor := Node3D.new()
		rotor.position = tip + Vector3(0, 0.1, 0)
		add_child(rotor)
		var disc := MeshInstance3D.new()
		var rd := CylinderMesh.new()
		rd.top_radius = 0.24
		rd.bottom_radius = 0.24
		rd.height = 0.008
		disc.mesh = rd
		var rdm := StandardMaterial3D.new()
		rdm.albedo_color = Color(0.05, 0.05, 0.05, 0.35)
		rdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material_override = rdm
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rotor.add_child(disc)
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.46, 0.006, 0.035)
		blade.mesh = bm
		blade.material_override = rotor_m
		rotor.add_child(blade)
		_rotors.append(rotor)
	# Kamera-Gondel mit Suchlicht
	var gimbal := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.1
	gm.height = 0.2
	gimbal.mesh = gm
	gimbal.material_override = arm_m
	gimbal.position = Vector3(0, -0.12, -0.2)
	add_child(gimbal)
	light = SpotLight3D.new()
	light.light_color = Color(0.85, 0.92, 1.0)
	light.light_energy = 14.0
	light.spot_range = 16.0
	light.spot_angle = 24.0
	light.spot_angle_attenuation = 0.7
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.6
	light.position = Vector3(0, -0.2, -0.2)
	light.rotation_degrees.x = -78.0
	add_child(light)
	_beam = SL.beam_mesh(9.0, 0.08, tan(deg_to_rad(24.0)) * 9.0, 0.035, Color(0.8, 0.88, 1.0))
	light.add_child(_beam)
	var lens := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	lens.mesh = lm
	lens.material_override = SL.BP_unshaded(Color(5.0, 5.0, 5.5))
	lens.position = Vector3(0, -0.2, -0.2)
	add_child(lens)
	_blink = OmniLight3D.new()
	_blink.light_color = Color(1.0, 0.1, 0.05)
	_blink.light_energy = 0.0
	_blink.omni_range = 3.0
	_blink.position = Vector3(0, -0.05, 0.32)
	_blink.set_meta("no_stealth", true)
	add_child(_blink)
	_blink_mesh = MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.035
	bsm.height = 0.07
	_blink_mesh.mesh = bsm
	_blink_mesh.material_override = SL.BP_unshaded(Color(4.0, 0.2, 0.1))
	_blink_mesh.position = _blink.position
	add_child(_blink_mesh)
	var st := load("res://assets/sfx/curfew_drone_hum.ogg") as AudioStreamOggVorbis
	if st != null:
		st = st.duplicate() as AudioStreamOggVorbis
		st.loop = true
		_hum = AudioStreamPlayer3D.new()
		_hum.stream = st
		_hum.bus = "SFX"
		_hum.volume_db = -4.0
		_hum.unit_size = 5.0
		_hum.max_distance = 45.0
		_hum.autoplay = true
		add_child(_hum)

func _physics_process(delta: float) -> void:
	_t += delta
	for r in _rotors:
		r.rotation.y += delta * (60.0 if not _dead else 8.0)
	if _dead:
		_fall(delta)
		return
	var on := fmod(_t, 1.2) < 0.12
	_blink.light_energy = 1.2 if on else 0.0
	_blink_mesh.visible = on
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var goal: Vector3
	var spd := speed
	if _track_t > 0.0 and pl != null:
		goal = pl.global_position + Vector3(0, 7.0, 2.5)
		spd = 4.5
		_track_t -= delta
	elif not path.is_empty():
		goal = path[_i]
		if global_position.distance_to(goal) < 0.8:
			_i = (_i + 1) % path.size()
	else:
		goal = global_position
	var to := goal - global_position
	var step := to.limit_length(spd * delta)
	global_position += step
	if Vector2(to.x, to.z).length() > 0.3:
		_yaw = lerp_angle(_yaw, atan2(-to.x, -to.z), clampf(delta * 2.0, 0.0, 1.0))
	var tilt := clampf(step.length() / maxf(delta, 0.001) / 8.0, 0.0, 0.25)
	rotation = Vector3(-tilt, _yaw, sin(_t * 1.3) * 0.03)
	position.y += sin(_t * 2.1) * 0.004
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.1
		_seen = _sees(pl)
	if _seen:
		var k := 0.65 if bool(pl.get("is_crouching")) else 1.0
		suspicion = minf(1.0, suspicion + 0.95 * k * delta)
		if suspicion >= 1.0:
			if _track_t <= 0.0:
				_play("drone_beep")
			_track_t = 6.0
			if director != null and not bool(director.get("alarm")):
				director.call("raise_alarm", pl.global_position, "drone", true)
	else:
		suspicion = maxf(0.0, suspicion - 0.3 * delta)

func _sees(pl: Node3D) -> bool:
	if pl == null or not bool(pl.call("is_alive")):
		return false
	var lp := light.global_position
	var target := pl.global_position + Vector3.UP * 0.8
	var to := target - lp
	var d := to.length()
	if d > 17.0:
		return false
	var fwd := -light.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to / d)) > 26.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(lp, target, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _play(n: String) -> void:
	var s: AudioStream = Sfx.get_stream(n)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.unit_size = 6.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

# ------------------------------------------------------------------ Schaden / Absturz

func take_damage(amount: float, _source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _dead:
		return
	health -= amount
	Events.enemy_damaged.emit(self, amount)
	if health <= 0.0:
		_die()

func is_alive() -> bool:
	return not _dead

func get_status() -> Dictionary:
	var p := global_position
	return {"type": "drone", "alive": not _dead, "health": maxf(health, 0.0), "position": [p.x, p.y, p.z], "state": "DEAD" if _dead else "PATROL"}

func _die() -> void:
	_dead = true
	suspicion = 0.0
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	_blink.light_energy = 0.0
	_blink_mesh.visible = false
	light.light_energy = 3.0
	_beam.visible = false
	_fall_v = Vector3(randf_range(-1.0, 1.0), 0.5, randf_range(-1.0, 1.0))
	_spin = Vector3(randf_range(-4, 4), randf_range(-6, 6), randf_range(-4, 4))
	_play("drone_hit")
	if _hum != null:
		_hum.pitch_scale = 0.7
	Events.enemy_killed.emit(self)

func _fall(delta: float) -> void:
	if _fall_v == Vector3.ZERO:
		return
	_fall_v.y -= 14.0 * delta
	var nxt := global_position + _fall_v * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, nxt + Vector3.DOWN * 0.2, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		global_position = (hit["position"] as Vector3) + Vector3.UP * 0.15
		_fall_v = Vector3.ZERO
		rotation = Vector3(0.2, rotation.y, 0.35)
		light.light_energy = 0.0
		_play("drone_explode")
		if _hum != null:
			_hum.queue_free()
			_hum = null
		# Sparks/Rauch
		var sp := OmniLight3D.new()
		sp.light_color = Color(1.0, 0.55, 0.2)
		sp.light_energy = 6.0
		sp.omni_range = 6.0
		sp.set_meta("no_stealth", true)
		add_child(sp)
		var tw := create_tween()
		tw.tween_property(sp, "light_energy", 0.0, 0.6)
		tw.tween_callback(sp.queue_free)
		# Laerm: Wachen in der Naehe sehen nach
		if director != null:
			for w in director.get("watchers"):
				if is_instance_valid(w) and w.has_method("hear_noise"):
					w.call("hear_noise", global_position, 22.0)
		return
	global_position = nxt
	rotation += _spin * delta

func get_suspicion() -> float:
	return suspicion

func get_watch_state() -> int:
	if _dead:
		return -1
	if _track_t > 0.0 and _seen:
		return 2
	return 1 if suspicion > 0.05 else 0

func get_watch_pos() -> Vector3:
	return global_position + Vector3.UP * 0.5

func is_watcher_alive() -> bool:
	return not _dead
