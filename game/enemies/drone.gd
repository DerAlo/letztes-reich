class_name Drone
extends Enemy
## Kamikaze-Quadrocopter. Fliegt frei (ohne Navmesh), schwebt wackelnd an, piept/blinkt rot,
## stuerzt sich dann auf den Spieler und sprengt sich per Combat.explode.
## Abgeschossen: trudelt kurz, explodiert dann kleiner.

@export_group("Drone")
@export var fly_speed: float = 6.5
@export var hover_distance: float = 10.0
@export var hover_height: float = 1.4
@export var hover_time_min: float = 2.2
@export var hover_time_max: float = 3.2
@export var dive_speed: float = 11.0
@export var dive_turn_rate: float = 2.6
@export var dive_timeout: float = 7.0
@export var wobble_amount: float = 0.7
@export var avoid_distance: float = 3.0
@export var explode_radius: float = 4.0
@export var explode_damage: float = 45.0
@export var explode_visual_scale: float = 0.6
@export var death_explode_radius: float = 2.5
@export var death_explode_damage: float = 12.0
@export var death_explode_visual_scale: float = 0.4
@export var tumble_time_min: float = 0.45
@export var tumble_time_max: float = 0.85

var _hover_t: float = 0.0
var _hover_goal: float = 2.5
var _blink_t: float = 0.0
var _blink_on: bool = false
var _wobble_phase: float = 0.0
var _rotors: Array[Node3D] = []
var _eye_mat: StandardMaterial3D = null
var _eye_light: OmniLight3D = null
var _tumble_t: float = 0.0
var _tumble_vel: Vector3 = Vector3.ZERO
var _tumble_spin: Vector3 = Vector3.ZERO
var _detonated: bool = false
var _dive_dir: Vector3 = Vector3.FORWARD
var _dive_speed: float = 0.0

func _ready() -> void:
	enemy_type = "drone"
	super._ready()
	collision_mask = LAYER_WORLD | LAYER_PLAYER | 16   # 16 = move_block
	_wobble_phase = rng.randf() * TAU
	_hover_goal = rng.randf_range(hover_time_min, hover_time_max)

func _setup_nav() -> void:
	nav = null

func _eye_pos() -> Vector3:
	return global_position

func _player_crouching() -> bool:
	return false

# ---------------------------------------------------------------- Zustaende

func _tick_state(delta: float) -> void:
	_wobble_phase += delta
	match state:
		State.IDLE:
			_tick_idle(delta)
			_desired_velocity = _wobble(0.5)
			_blink(delta, 1.4)
		State.ALERT:
			_tick_alert_drone(delta)
		State.ADVANCE:
			_tick_approach(delta)
		State.ATTACK:
			_tick_dive(delta)

func _tick_alert_drone(delta: float) -> void:
	_aim_at_target = true
	_desired_velocity = _wobble(0.5)
	_blink(delta, 0.8)
	_alert_timer -= delta
	if _alert_timer <= 0.0:
		if _target_alive():
			_hover_t = 0.0
			_hover_goal = rng.randf_range(hover_time_min, hover_time_max)
			_set_state(State.ADVANCE)
		elif _state_time > 3.0:
			_set_state(State.IDLE)

func _hover_point() -> Vector3:
	var ppos := _player.global_position
	var away := global_position - ppos
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3.BACK
	var p := ppos + away.normalized() * hover_distance
	p.y = _player_head().y + hover_height
	return p

func _tick_approach(delta: float) -> void:
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_aim_at_target = true
	var target := _hover_point()
	var to := target - global_position
	var near := to.length() < 2.0 or _flat_dist(global_position, _player.global_position) <= hover_distance * 1.15
	if near:
		_hover_t += delta
		_desired_velocity = _wobble(1.0) + to.limit_length(1.0) * 0.3
	else:
		var dir := _steer(to.normalized(), delta)
		_desired_velocity = dir * fly_speed + _wobble(0.6)
	var urgency := clampf(_hover_t / maxf(_hover_goal, 0.1), 0.0, 1.0)
	_blink(delta, lerpf(0.7, 0.12, urgency))
	if _hover_t >= _hover_goal:
		_dive_dir = (_player_chest() - global_position).normalized()
		_dive_speed = maxf(velocity.length(), 2.0)
		_set_state(State.ATTACK)
		_play_sfx("drone_dive")

func _tick_dive(delta: float) -> void:
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_aim_at_target = true
	_blink(delta, 0.08)
	var target := _player_chest()
	var to := target - global_position
	var dist := to.length()
	var want := to / maxf(dist, 0.01)
	# begrenzte Wendegeschwindigkeit: der Spieler kann ausweichen
	var ang := _dive_dir.angle_to(want)
	var max_ang := dive_turn_rate * delta
	if ang <= max_ang:
		_dive_dir = want
	else:
		var axis := _dive_dir.cross(want)
		if axis.length() < 0.001:
			axis = Vector3.UP
		_dive_dir = _dive_dir.rotated(axis.normalized(), max_ang).normalized()
	var dir := _dive_dir
	if dist > 3.5:
		dir = _steer(_dive_dir, delta, 0.8, 0.45)
	_dive_speed = move_toward(_dive_speed, dive_speed, 28.0 * delta)
	velocity = dir * _dive_speed
	if dist < 1.3 or _state_time > dive_timeout:
		_detonate(explode_radius, explode_damage, explode_visual_scale)

func _wobble(mult: float) -> Vector3:
	var t := _wobble_phase
	return Vector3(sin(t * 2.3), cos(t * 3.1) * 0.7, cos(t * 1.9)) * wobble_amount * mult

## Einfache Hindernisvermeidung per Raycasts (vorne, links, rechts, unten).
func _steer(dir: Vector3, _delta: float, strength: float = 1.0, floor_clear: float = 1.1) -> Vector3:
	var pos := global_position
	var out := dir
	var fwd_hit := _ray(pos, pos + dir * avoid_distance, LAYER_WORLD)
	if not fwd_hit.is_empty():
		var n: Vector3 = fwd_hit["normal"]
		var closeness := 1.0 - pos.distance_to(fwd_hit["position"]) / avoid_distance
		out += (n + Vector3.UP * 0.6) * (1.5 + closeness * 2.0) * strength
	var side := dir.cross(Vector3.UP).normalized()
	for s in [-1.0, 1.0]:
		var sd: Vector3 = (dir + side * s * 0.7).normalized()
		var h := _ray(pos, pos + sd * avoid_distance * 0.8, LAYER_WORLD)
		if not h.is_empty():
			out -= side * s * (1.0 - pos.distance_to(h["position"]) / (avoid_distance * 0.8)) * 1.2 * strength
	var down := _ray(pos, pos + Vector3.DOWN * floor_clear, LAYER_WORLD)
	if not down.is_empty():
		out += Vector3.UP * 1.5
	return out.normalized() if out.length() > 0.01 else dir

func _blink(delta: float, interval: float) -> void:
	_blink_t += delta
	if _blink_t >= interval:
		_blink_t = 0.0
		_blink_on = not _blink_on
		if _blink_on and state != State.IDLE:
			_play_sfx("drone_beep")
	var on := _blink_on
	if _eye_mat != null:
		_eye_mat.emission_energy_multiplier = 6.0 if on else 0.6
	if _eye_light != null:
		_eye_light.light_energy = 1.6 if on else 0.0

# ---------------------------------------------------------------- Bewegung

func _apply_motion(delta: float) -> void:
	if state != State.ATTACK:
		velocity = velocity.lerp(_desired_velocity, clampf(4.0 * delta, 0.0, 1.0))
	move_and_slide()
	if state == State.ATTACK and get_slide_collision_count() > 0 and _state_time > 0.3:
		_detonate(explode_radius, explode_damage, explode_visual_scale)

func _update_facing(delta: float) -> void:
	var face := Vector3.ZERO
	if _player != null and is_instance_valid(_player) and state != State.IDLE:
		face = _player.global_position - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.5:
		face = velocity
	face.y = 0.0
	if face.length() < 0.05:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), clampf(5.0 * delta, 0.0, 1.0))

# ---------------------------------------------------------------- Koerper

func _build_body() -> void:
	var dark := _mat(Color(0.1, 0.105, 0.11), 0.45)
	var shell := _mat(color_primary.lerp(Color(0.25, 0.26, 0.27), 0.5), 0.6)
	var metal := _mat(Color(0.3, 0.3, 0.32), 0.35)
	metal.metallic = 0.7
	var red := _mat(color_armband, 0.6, color_armband, 0.6)
	var glass := _mat(Color(0.02, 0.02, 0.03), 0.08)
	glass.metallic = 0.6
	var charge_mat := _mat(Color(0.32, 0.3, 0.2), 0.9)
	var tape := _mat(Color(0.08, 0.08, 0.08), 0.6)
	var blur := StandardMaterial3D.new()
	blur.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blur.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blur.albedo_color = Color(0.12, 0.12, 0.13, 0.28)
	blur.cull_mode = BaseMaterial3D.CULL_DISABLED
	_eye_mat = _mat(Color(0.5, 0.0, 0.0), 0.4, Color(1.0, 0.05, 0.03), 0.6)

	_body_shape = CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.38
	_body_shape.shape = sph
	add_child(_body_shape)

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	# Rumpf: flacher Kern + gewoelbte Haube + Akku
	var core := _mesh_node(_visual, _box(Vector3(0.2, 0.07, 0.3)), dark, Vector3.ZERO)
	_register_part(core, _box_shape(Vector3(0.2, 0.07, 0.3)), 2.0)
	var hood_mesh := SphereMesh.new()
	hood_mesh.radius = 0.13
	hood_mesh.height = 0.26
	hood_mesh.radial_segments = 16
	hood_mesh.rings = 8
	var hood := _mesh_node(core, hood_mesh, shell, Vector3(0.0, 0.03, -0.01))
	hood.scale = Vector3(0.95, 0.42, 1.3)
	_mesh_node(core, _box(Vector3(0.11, 0.045, 0.16)), dark, Vector3(0.0, 0.075, 0.04))      # Akku
	_mesh_node(core, _box(Vector3(0.035, 0.012, 0.3)), red, Vector3(0.0, 0.088, -0.01))      # Fraktionsstreifen
	_mesh_node(core, _box(Vector3(0.05, 0.03, 0.02)), metal, Vector3(0.0, 0.02, 0.16))       # Antennenfuss
	var ant := _mesh_node(core, _cyl_mesh(0.004, 0.004, 0.16), dark, Vector3(0.0, 0.1, 0.16))
	ant.rotation.x = -0.35
	# Kamerakuppel vorne unten mit roter Status-LED (blinkt)
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.055
	dome_mesh.height = 0.11
	_mesh_node(core, _cyl_mesh(0.03, 0.03, 0.03), metal, Vector3(0.0, -0.045, -0.12))         # Gimbal
	var dome := _mesh_node(core, dome_mesh, glass, Vector3(0.0, -0.075, -0.13))
	_mesh_node(dome, _cyl_mesh(0.022, 0.026, 0.02), metal, Vector3(0.0, 0.0, -0.048), Vector3(PI * 0.5, 0.0, 0.0))  # Objektiv
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.014
	eye_mesh.height = 0.028
	var eye := _mesh_node(dome, eye_mesh, _eye_mat, Vector3(0.0, 0.0, -0.058))
	_mesh_node(core, eye_mesh, _eye_mat, Vector3(0.0, 0.02, -0.158))                         # LED Nase
	_eye_light = OmniLight3D.new()
	_eye_light.light_color = Color(1.0, 0.1, 0.05)
	_eye_light.omni_range = 4.0
	_eye_light.light_energy = 0.0
	_eye_light.shadow_enabled = false
	eye.add_child(_eye_light)
	# Sprengladung unten: zwei Rohre, Klebeband, Zuender mit LED
	for sx in [-0.035, 0.035]:
		_mesh_node(core, _cyl_mesh(0.032, 0.032, 0.2), charge_mat, Vector3(sx, -0.075, 0.03), Vector3(PI * 0.5, 0.0, 0.0))
	for z in [-0.03, 0.09]:
		_mesh_node(core, _box(Vector3(0.14, 0.07, 0.022)), tape, Vector3(0.0, -0.075, z))
	_mesh_node(core, _box(Vector3(0.05, 0.03, 0.04)), dark, Vector3(0.0, -0.118, 0.03))      # Zuender
	_mesh_node(core, eye_mesh, _eye_mat, Vector3(0.0, -0.135, 0.03))
	var wire := _mesh_node(core, _cyl_mesh(0.004, 0.004, 0.09), red, Vector3(0.03, -0.11, -0.02))
	wire.rotation = Vector3(0.9, 0.0, 0.4)
	# Kufen
	for sx in [-1.0, 1.0]:
		var leg := _mesh_node(core, _cyl_mesh(0.006, 0.006, 0.12), dark, Vector3(sx * 0.1, -0.08, 0.0))
		leg.rotation.z = sx * 0.35
		_mesh_node(core, _cyl_mesh(0.007, 0.007, 0.26), dark, Vector3(sx * 0.125, -0.135, 0.0), Vector3(PI * 0.5, 0.0, 0.0))
	# Arme, Motoren, Rotoren (Blaetter drehen sich, Bewegungsunschaerfe-Scheibe)
	var blade_mesh := _box(Vector3(0.3, 0.004, 0.028))
	var disc_mesh := _cyl_mesh(0.165, 0.165, 0.003)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var tip := Vector3(sx * 0.25, 0.02, sz * 0.25)
			var arm := _mesh_node(core, _cyl_mesh(0.014, 0.018, 0.3), dark, tip * 0.5)
			arm.transform = Transform3D(Basis(Quaternion(Vector3.UP, Vector3(sx, 0.08, sz).normalized())), tip * 0.5)
			_register_part(arm, _box_shape(Vector3(0.04, 0.3, 0.04)), 0.5)
			_mesh_node(core, _cyl_mesh(0.032, 0.036, 0.05), metal, tip + Vector3(0.0, 0.02, 0.0))   # Motor
			_mesh_node(core, _cyl_mesh(0.012, 0.012, 0.02), dark, tip + Vector3(0.0, 0.055, 0.0))   # Nabe
			var nav := _mat(Color(0.1, 0.4, 0.1) if sz > 0.0 else Color(0.5, 0.05, 0.05), 0.5, Color(0.2, 1.0, 0.3) if sz > 0.0 else Color(1.0, 0.1, 0.05), 1.5)
			_mesh_node(core, _box(Vector3(0.015, 0.012, 0.015)), nav, tip + Vector3(sx * 0.03, -0.01, sz * 0.03))
			var rotor := Node3D.new()
			rotor.position = tip + Vector3(0.0, 0.06, 0.0)
			core.add_child(rotor)
			_mesh_node(rotor, blade_mesh, dark, Vector3.ZERO, Vector3(0.0, 0.0, 0.06))
			var disc := _mesh_node(core, disc_mesh, blur, tip + Vector3(0.0, 0.062, 0.0))
			disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rotor.rotation.y = rng.randf() * TAU
			_rotors.append(rotor)
	_muzzle = Node3D.new()
	core.add_child(_muzzle)

func _cyl_mesh(r_top: float, r_bot: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = 10
	c.rings = 1
	return c

func _animate(delta: float) -> void:
	for i in _rotors.size():
		_rotors[i].rotation.y += delta * (38.0 if i % 2 == 0 else -38.0)
	var local_v := global_transform.basis.inverse() * velocity
	_visual.rotation.x = lerpf(_visual.rotation.x, clampf(-local_v.z * 0.04, -0.4, 0.4), clampf(6.0 * delta, 0.0, 1.0))
	_visual.rotation.z = lerpf(_visual.rotation.z, clampf(-local_v.x * 0.04, -0.4, 0.4) + sin(_wobble_phase * 5.0) * 0.04, clampf(6.0 * delta, 0.0, 1.0))
	_flinch = move_toward(_flinch, 0.0, delta * 5.0)
	_visual.position.y = sin(_wobble_phase * 7.0) * 0.015 + _flinch * 0.08

# ---------------------------------------------------------------- Tod

func _on_damaged(source: Node, src_pos: Vector3) -> void:
	super._on_damaged(source, src_pos)
	if state == State.IDLE or state == State.ALERT:
		_hover_t = 0.0

func _on_death() -> void:
	# Trudeln: zufaellige Drehung, faellt mit Resttempo
	_tumble_t = rng.randf_range(tumble_time_min, tumble_time_max)
	_tumble_vel = velocity * 0.5 + _last_hit_dir * 2.0
	_tumble_spin = _rand_spin(9.0)
	collision_mask = LAYER_WORLD
	collision_layer = 0
	_play_sfx("drone_hit")

func _tick_dead(delta: float) -> void:
	if _detonated:
		return
	_tumble_t -= delta
	_tumble_vel.y -= gravity * delta
	velocity = _tumble_vel
	move_and_slide()
	_visual.rotation += _tumble_spin * delta
	for r in _rotors:
		r.rotation.y += delta * 10.0
	_blink_t += delta
	if _tumble_t <= 0.0 or get_slide_collision_count() > 0:
		_detonate(death_explode_radius, death_explode_damage, death_explode_visual_scale)

## Sprengt die Drohne. Funktioniert aus jedem Zustand; emittiert enemy_killed falls noch nicht geschehen.
func _detonate(radius: float, damage: float, vis_scale: float) -> void:
	if _detonated:
		return
	_detonated = true
	var pos := global_position
	if state != State.DEAD:
		_set_state(State.DEAD)
		_death_time = _age
		_death_pos = pos
		remove_from_group("enemy")
		remove_from_group("damageable")
		collision_layer = 0
		collision_mask = 0
		Events.enemy_killed.emit(self)
	Combat.explode(pos, radius, damage, self, vis_scale)
	_play_sfx("drone_explode")
	_spawn_debris()
	_visual.visible = false
	set_physics_process(false)
	get_tree().create_timer(cleanup_time).timeout.connect(queue_free)

func _spawn_debris() -> void:
	var dark := _mat(Color(0.12, 0.13, 0.13), 0.5)
	var tw := create_tween()
	tw.set_parallel(true)
	for i in 6:
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER_DEBRIS
		rb.collision_mask = LAYER_WORLD
		rb.mass = 0.4
		add_child(rb)
		rb.global_position = global_position + _rand_spin(0.15)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.12, 0.04, 0.1)
		cs.shape = shape
		rb.add_child(cs)
		var mi := _mesh_node(rb, _box(Vector3(0.12, 0.04, 0.1)), dark, Vector3.ZERO)
		rb.linear_velocity = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.5, 1.5), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(4.0, 9.0)
		rb.angular_velocity = _rand_spin(12.0)
		tw.tween_property(mi, "transparency", 1.0, 1.0).set_delay(maxf(cleanup_time - 2.5, 1.0))
