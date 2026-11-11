extends AnimatableBody3D
## Mission "Kräne", Teil B: Gegnerboot (Garde-Schnellboot mit Bug-MG) oder Webers Fluchtboot.
## Faehrt relativ zur RailRide-Bahn des Spielers (gleiche Kurve, Versatz in Bahnmetern + seitlich + Schlaengeln),
## damit es auch bei Halten und Neustarts sauber mitzieht. role "weber": unverwundbar, Gruppe "no_shoot",
## Treffer meldet das Level (on_weber_boat_hit), haelt Vorsprung, faehrt im Finale frei zum Frachter.

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const FX := preload("res://game/systems/rail_ride_fx.gd")

var role: String = "garde"
var ride: Node3D = null
var level_ref: Node = null
var max_health: float = 150.0
var health: float = 150.0
var offset_s: float = 120.0          ## Bahnmeter vor (+) / hinter (-) dem Spieler
var target_offset: float = 45.0      ## naehert sich auf diesen Versatz
var approach_rate: float = 6.0       ## m/s Annaeherung
var lateral: float = 18.0            ## seitlich (+ = rechts)
var weave_amp: float = 6.0
var weave_freq: float = 0.18
var hit_chance: float = 0.22
var round_damage: float = 12.0       ## vor vehicle_damage_scale der RailRide (0.5) -> 6
var burst_rounds: int = 6
var free_target: Vector3 = Vector3.INF   ## gesetzt: faehrt frei dorthin (Finale)
var free_speed: float = 12.0
var dead: bool = false

var _t: float = 0.0
var _ph: float = 0.0
var _burst_cd: float = 3.0
var _burst_left: int = 0
var _shot_cd: float = 0.0
var _gun: Node3D
var _muzzle: Marker3D
var _flash: Node3D
var _spray: Array[GPUParticles3D] = []
var _engine: AudioStreamPlayer3D
var _motion: Node3D
var _sink_t: float = 0.0
var _vel := Vector3.ZERO
var _last_pos := Vector3.ZERO
var velocity := Vector3.ZERO

func _ready() -> void:
	health = max_health
	sync_to_physics = false
	collision_layer = VF.LAYER_ENEMY
	collision_mask = 0
	set_meta("surface", "metal")
	add_to_group("vehicle")
	if role == "weber":
		add_to_group("no_shoot")
		set_meta("avoid_radius", 5.0)
	else:
		add_to_group("enemy")
		add_to_group("damageable")
		set_meta("aim_offset", Vector3(0, 1.0, 0))
	_ph = randf() * TAU
	_build()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 1.8, 7.5)
	cs.shape = bs
	cs.position = Vector3(0, 0.7, 0)
	add_child(cs)
	_engine = VF.loop_player(self, "hafen_boat_engine", 12.0, 260.0, -6.0)
	_burst_cd = randf_range(2.5, 4.5)
	_last_pos = global_position

func _build() -> void:
	_motion = Node3D.new()
	add_child(_motion)
	var hull_c := Color(0.22, 0.23, 0.24) if role != "weber" else Color(0.82, 0.82, 0.8)
	var hull := VF.mat("hb_hull_" + role, hull_c, 0.55, 0.2)
	var dark := VF.mat("hb_dark", Color(0.08, 0.08, 0.09), 0.7, 0.3)
	var glass := VF.glass_mat()
	VF.mesh_node(_motion, VF.box(Vector3(2.5, 0.9, 6.0)), hull, Vector3(0, 0.25, 0.4))
	VF.mesh_node(_motion, VF.prism(Vector3(2.5, 2.2, 0.9), 0.5), hull, Vector3(0, 0.25, -3.5), Vector3(-90, 0, 0))
	VF.mesh_node(_motion, VF.box(Vector3(2.3, 0.15, 6.4)), dark, Vector3(0, 0.75, 0.2))
	VF.mesh_node(_motion, VF.box(Vector3(1.6, 0.9, 1.4)), hull, Vector3(0, 1.25, 0.6))
	VF.mesh_node(_motion, VF.box(Vector3(1.5, 0.5, 0.06)), glass, Vector3(0, 1.45, -0.12))
	VF.mesh_node(_motion, VF.box(Vector3(0.7, 0.7, 0.6)), dark, Vector3(0, 0.95, 3.1))
	var nav_r := VF.mat("hb_nav_r", Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0.1, 0.1), 4.0)
	var nav_g := VF.mat("hb_nav_g", Color(0.1, 1, 0.2), 0.4, 0.0, Color(0.1, 1, 0.2), 4.0)
	VF.mesh_node(_motion, VF.box(Vector3(0.12, 0.12, 0.12)), nav_r, Vector3(-0.85, 1.75, 0.6))
	VF.mesh_node(_motion, VF.box(Vector3(0.12, 0.12, 0.12)), nav_g, Vector3(0.85, 1.75, 0.6))
	if role != "weber":
		# Bug-MG mit Schuetze (Puppe)
		_gun = Node3D.new()
		_gun.position = Vector3(0, 1.2, -1.9)
		_motion.add_child(_gun)
		VF.mesh_node(_gun, VF.box(Vector3(0.12, 0.14, 1.3)), dark, Vector3(0, 0.1, -0.5))
		VF.mesh_node(_gun, VF.box(Vector3(0.6, 0.4, 0.06)), dark, Vector3(0, 0.05, 0.1))
		var coat := VF.mat("hb_coat", Color(0.36, 0.37, 0.38), 0.85, 0.0)
		VF.mesh_node(_gun, VF.capsule(0.28, 1.2), coat, Vector3(0, -0.15, 0.55))
		VF.mesh_node(_gun, VF.sphere(0.16), VF.mat("hb_skin", Color(0.6, 0.47, 0.4), 0.8, 0.0), Vector3(0, 0.55, 0.55))
		_muzzle = Marker3D.new()
		_muzzle.position = Vector3(0, 0.1, -1.2)
		_gun.add_child(_muzzle)
		_flash = VF.make_muzzle_flash(_muzzle, 0.6, 4.0, 6.0)
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.9, 0.95, 1.0)
		sl.light_energy = 4.0
		sl.spot_range = 60.0
		sl.spot_angle = 14.0
		sl.position = Vector3(0, 1.8, 0.2)
		_motion.add_child(sl)
		_gun.set_meta("spot", sl)
	else:
		var fig := VF.mat("hb_weber", Color(0.12, 0.12, 0.14), 0.85, 0.0)
		VF.mesh_node(_motion, VF.capsule(0.28, 1.5), fig, Vector3(0.3, 1.4, 1.6))
		VF.mesh_node(_motion, VF.capsule(0.28, 1.5), fig, Vector3(-0.4, 1.4, 2.3))
	_spray = FX.make_boat_spray(self, Vector3(0, 0.1, -2.6), Vector3(0, 0.1, 3.4), 2.2)

func is_alive() -> bool:
	return not dead

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	VFX.spawn_impact(hit_position, hit_normal, "metal")
	if role == "weber":
		var from_player: bool = source != null and is_instance_valid(source) and source.is_in_group("player")
		if from_player and level_ref != null and level_ref.has_method("on_weber_boat_hit"):
			level_ref.call("on_weber_boat_hit")
		return
	health -= amount
	if health <= 0.0:
		_die()

func destroy() -> void:
	if not dead and role != "weber":
		health = 0.0
		_die()

func _die() -> void:
	dead = true
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	_burst_left = 0
	Events.enemy_killed.emit(self)
	VFX.spawn_explosion(global_position + Vector3.UP * 1.0, 0.9)
	FX.big_splash(self, global_position, 1.3)
	FX.set_spray(_spray, 0.0)
	if _engine != null:
		_engine.stop()
	if _gun != null and _gun.has_meta("spot"):
		(_gun.get_meta("spot") as Node).queue_free()

func _physics_process(delta: float) -> void:
	_t += delta
	if dead:
		_sink_t += delta
		global_position += Vector3(0, -0.6 * delta, 0)
		_motion.rotation = Vector3(minf(_sink_t * 0.12, 0.35), 0, minf(_sink_t * 0.2, 0.5))
		if _sink_t > 6.0:
			queue_free()
		return
	var pos := global_position
	var yaw := rotation.y
	if free_target != Vector3.INF:
		var to := free_target - pos
		to.y = 0.0
		var d := to.length()
		var v := minf(free_speed, d * 0.5)
		if d > 0.5:
			pos += to.normalized() * v * delta
			yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 1.0 - exp(-delta * 2.0))
		pos.y = -2.0
	elif ride != null and is_instance_valid(ride):
		if role == "weber":
			# Vorsprung halten: haelt der Spieler an, zieht Weber davon
			var stopped: bool = float(ride.get("speed")) < 2.0
			offset_s += (5.0 if stopped else 0.0) * delta
			offset_s = move_toward(offset_s, target_offset, approach_rate * delta * (0.0 if stopped else 1.0))
		else:
			offset_s = move_toward(offset_s, target_offset, approach_rate * delta)
		var s: float = float(ride.get("path_s")) + offset_s
		var p: Vector3 = ride.call("pos_at", s)
		var dir: Vector3 = ride.call("dir_at", s)
		var right := dir.cross(Vector3.UP).normalized()
		var lat := lateral + sin(_t * TAU * weave_freq + _ph) * weave_amp
		pos = p + right * lat
		pos.y = -2.0
		var ahead: Vector3 = ride.call("pos_at", s + 6.0) + right * (lateral + sin((_t + 0.4) * TAU * weave_freq + _ph) * weave_amp)
		var hd := ahead - pos
		hd.y = 0.0
		if hd.length() > 0.1:
			yaw = lerp_angle(yaw, atan2(-hd.x, -hd.z), 1.0 - exp(-delta * 4.0))
	velocity = (pos - _last_pos) / maxf(delta, 0.001)
	_last_pos = pos
	global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	var spd := velocity.length()
	_motion.rotation = Vector3(0.05 * clampf(spd / 15.0, 0.0, 1.0) + sin(_t * 1.7 + _ph) * 0.02, 0, sin(_t * 1.3 + _ph) * 0.035)
	_motion.position.y = sin(_t * 2.1 + _ph) * 0.08
	FX.set_spray(_spray, clampf(spd / 14.0, 0.15, 1.0))
	if _engine != null:
		_engine.pitch_scale = lerpf(0.8, 1.2, clampf(spd / 16.0, 0.0, 1.0))
	if role != "weber":
		_tick_gun(delta)

func _tick_gun(delta: float) -> void:
	if ride == null or not is_instance_valid(ride) or not bool(ride.call("is_alive")):
		return
	var tgt := ride.global_position + Vector3.UP * 1.2
	var lp: Vector3 = (_gun.get_parent() as Node3D).global_transform.affine_inverse() * tgt - _gun.position
	_gun.rotation.y = lerp_angle(_gun.rotation.y, atan2(-lp.x, -lp.z), 1.0 - exp(-delta * 5.0))
	if _burst_left > 0:
		_shot_cd -= delta
		if _shot_cd <= 0.0:
			_shot_cd = 0.11
			_burst_left -= 1
			_fire(tgt)
		return
	_burst_cd -= delta
	if _burst_cd > 0.0:
		return
	_burst_cd = randf_range(2.6, 4.2)
	var from := _muzzle.global_position
	if from.distance_to(tgt) > 220.0:
		return
	var hit := VF.ray(self, from, tgt, VF.LAYER_WORLD, [get_rid()])
	if not hit.is_empty():
		return
	_burst_left = burst_rounds
	_shot_cd = 0.0

func _fire(tgt: Vector3) -> void:
	var from := _muzzle.global_position
	var hit := randf() < hit_chance
	var aim := tgt
	if not hit:
		aim += Vector3(randf_range(-4.0, 4.0), randf_range(-1.0, 3.0), randf_range(-4.0, 4.0))
	VF.show_flash(_flash, 0.04)
	VF.play_at(self, "hafen_mg", from, -4.0, 14.0, 320.0, randf_range(0.9, 1.0))
	VF.tracer(self, from, aim, 420.0, "red", 1.0)
	if hit:
		ride.call("take_damage", round_damage, self, aim, (from - aim).normalized())
	else:
		VFX.play_whiz_along(from, aim + (aim - from).normalized() * 10.0, 3.0)
		if aim.y < -1.0 or randf() < 0.5:
			FX.water_hit(self, Vector3(aim.x, -2.0, aim.z))
