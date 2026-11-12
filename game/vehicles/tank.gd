class_name Tank
extends Node3D
## Kampfpanzer (Set-Piece-Gegner). Gruppen damageable, vehicle (NICHT enemy).
## Kugeln machen keinen Schaden (Panzerung faengt sie ab), nur Explosionen (Combat.explode) und destroy().
## API: drive_path(points, speed), set_target(node_or_null), destroy(). Signal destroyed.
## Kanone: alle ~fire_interval s; 1,5 s vorher richtet sich der Turm sichtbar aus (Laser-Entfernungsmesser,
## Servo-Geraeusch), dann Muendungsfeuer und Einschlag in der Naehe des Ziels (nicht direkt toedlich).

signal destroyed

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const ModelCache = preload("res://game/vehicles/models/model_cache.gd")
const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const TankModel = preload("res://game/vehicles/models/tank_model.gd")
const ArmorScript = preload("res://game/vehicles/vehicle_armor.gd")
const FIRE_SCENE := "res://game/vfx/fire.tscn"

@export_group("Werte")
@export var max_health: float = 300.0             ## nur Explosionsschaden zaehlt (ca. 3 nahe Granaten)
@export var faction: String = "ru"                ## Optik: "ru" | "reich" | "eu"
@export_group("Fahrt")
@export var accel: float = 1.6
@export var turn_rate_deg: float = 22.0
@export_group("Kanone")
@export var fire_interval: float = 6.0
@export var aim_time: float = 1.5
@export var turret_speed_deg: float = 32.0
@export var shell_damage: float = 55.0
@export var shell_radius: float = 5.0
@export var miss_min: float = 3.5                 ## Einschlag mindestens so weit vom Ziel entfernt (m)
@export var miss_max: float = 7.0
@export var max_range: float = 170.0

var health: float = 300.0
var dead: bool = false

var _path: Array[Vector3] = []
var _path_i: int = 0
var _max_speed: float = 4.0
var _speed: float = 0.0
var _yaw_rate: float = 0.0
var _target: Node3D = null
var _fire_t: float = 0.0
var _aiming: bool = false
var _aim_point: Vector3 = Vector3.ZERO
var _track_l: float = 0.0
var _track_r: float = 0.0
var _recoil: float = 0.0
var _rock: float = 0.0
var _rock_v: float = 0.0
var _t: float = 0.0
var _smoking: bool = false

var _parts: Dictionary = {}
var _armor: AnimatableBody3D
var _turret_shape: CollisionShape3D
var _engine_snd: AudioStreamPlayer3D
var _track_snd: AudioStreamPlayer3D
var _servo_snd: AudioStreamPlayer3D
var _exhaust: GPUParticles3D
var _laser: MeshInstance3D
var _laser_mat: StandardMaterial3D
var _model_root: Node3D

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	add_to_group("vehicle")
	_fire_t = randf_range(0.0, 2.0)
	if has_meta("faction"):
		faction = str(get_meta("faction"))
	_build()
	_build_audio()

func _build() -> void:
	_model_root = Node3D.new()
	_model_root.name = "Model"
	add_child(_model_root)
	_parts = ModelCache.build(TankModel, _model_root, faction)   # Klon statt Neubau (~270 ms)
	var keep: Array = _parts.values()
	for key in ["barrel", "mantlet", "turret", "hull"]:
		VF.merge_static(_parts[key], keep)
	for w: Node3D in _parts["wheels_l"] + _parts["wheels_r"]:
		VF.merge_static(w, keep)
	_armor = AnimatableBody3D.new()
	_armor.set_script(ArmorScript)
	_armor.name = "Armor"
	_armor.collision_layer = VF.LAYER_WORLD
	_armor.collision_mask = 0
	_armor.sync_to_physics = false   # true: Collider blieb am Ursprung haengen (Raketen flogen durch)
	_armor.set_meta("surface", "metal")
	add_child(_armor)
	_add_shape(Vector3(0, 0.95, 0.1), Vector3(3.5, 1.5, 7.0))
	_turret_shape = _add_shape(Vector3(0, 2.05, 0.1), Vector3(2.7, 0.85, 3.4))
	# Laser-Entfernungsmesser (Warnung vor dem Schuss)
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.albedo_color = Color(1.0, 0.1, 0.05, 0.5)
	_laser = MeshInstance3D.new()
	_laser.mesh = VF.cyl(0.012, 0.012, 1.0, 6)
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.visible = false
	_laser.top_level = true
	add_child(_laser)
	_build_exhaust()

func _add_shape(pos: Vector3, size: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	_armor.add_child(cs)
	return cs

func _build_audio() -> void:
	_engine_snd = VF.loop_player(self, "veh_tank_engine", 14.0, 260.0, 0.0)
	_track_snd = VF.loop_player(self, "veh_tank_tracks", 10.0, 160.0, -60.0)
	_servo_snd = VF.loop_player(self, "veh_tank_turret", 6.0, 70.0, -60.0)

func _build_exhaust() -> void:
	var pm := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 20.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.1
	pm.direction = Vector3(-1, 0.4, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 0.5, 0) + VfxLib.WIND * 0.5
	pm.damping_min = 0.8
	pm.damping_max = 1.4
	pm.scale_min = 0.5
	pm.scale_max = 0.9
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.3], [0.3, 1.0], [1.0, 2.6]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.5, 0.1, 0.3)
	var mat := VfxLib.smoke_mat({"smoke_color": Color(0.08, 0.08, 0.08), "smoke_color_end": Color(0.22, 0.22, 0.22), "density": 0.9, "glow": 0.0, "soft_dist": 0.5}, true)
	_exhaust = VfxLib.make_particles(24, 2.5, pm, VfxLib.quad(1.0), mat)
	_exhaust.one_shot = false
	_exhaust.explosiveness = 0.0
	_exhaust.emitting = true
	_exhaust.position = _parts.get("exhaust", Vector3(-1.85, 1.3, 2.4))
	(_parts["hull"] as Node3D).add_child(_exhaust)

# ------------------------------------------------------------------ API

## Faehrt die Punkte ab (Weltkoordinaten; y wird vom Boden bestimmt) und haelt am Ende.
func drive_path(points: Array[Vector3], speed: float = 4.0) -> void:
	if dead:
		return
	_path = points.duplicate()
	_path_i = 0
	_max_speed = maxf(speed, 0.5)

## Ziel fuer den Turm (Node3D) oder null (Turm geradeaus, kein Feuer).
func set_target(node_or_null: Node) -> void:
	_target = node_or_null as Node3D
	if _target == null:
		_aiming = false
		_laser.visible = false

func destroy() -> void:
	if dead:
		return
	dead = true
	health = 0.0
	_aiming = false
	_laser.visible = false
	destroyed.emit()
	remove_from_group("damageable")
	call_deferred("_do_destroy")

## Panzerfaust-Volltreffer: genau ein Drittel der Lebenspunkte (3 Treffer). Die Druckwelle derselben Rakete
## zaehlt danach nicht noch einmal (sonst reichen 2).
const ROCKET_HITS: int = 3
var _rocket_frame: int = -1

func rocket_hit(source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if dead:
		return
	_in_rocket = true
	take_damage(max_health / float(ROCKET_HITS) + 0.5, source, hit_position, hit_normal)
	_in_rocket = false
	_rocket_frame = Engine.get_physics_frames()

## Schaden zaehlt nur von der Panzerfaust (rocket_hit), von Bordwaffen (Schuetzenpanzer, Tuer-/Boots-MG)
## und von Skript-Ereignissen (>= 500). Handwaffen, Granaten und Faesser richten nichts aus.
var _in_rocket: bool = false

static func _heavy_source(src: Node) -> bool:
	return src != null and is_instance_valid(src) and (src.is_in_group("rail_ride") or src.has_method("rocket_hit_ifv"))

func take_damage(amount: float, source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	if _rocket_frame == Engine.get_physics_frames() and bool(Combat.get("explosion_active")):
		return
	# Bordwaffen nur mit Sprengwirkung (Maschinenkanone), MG-Kugeln prallen auch dort ab.
	if not _in_rocket and amount < 500.0 and not (_heavy_source(source) and bool(Combat.get("explosion_active"))):
		return
	health -= amount
	_rock_v += 1.5
	if health <= 0.0:
		destroy()
	elif health < max_health * 0.5 and not _smoking:
		_smoking = true
		_attach_fire(Vector3(0.6, 1.6, 2.2), 0.5, false)

func is_alive() -> bool:
	return not dead

func get_status() -> Dictionary:
	var p := global_position
	return {"type": "tank", "alive": not dead, "health": maxf(health, 0.0), "position": [p.x, p.y, p.z],
		"state": "dead" if dead else ("aiming" if _aiming else ("driving" if _speed > 0.2 else "idle"))}

## Trefferpunkte fuer Combat.explode (Wanne vorne/hinten/Seiten, Turm).
func get_damage_points() -> Array[Vector3]:
	var b := global_transform.basis
	var o := global_position
	return [o + b * Vector3(0, 1.0, 0), o + b * Vector3(0, 2.1, 0.2), o + b * Vector3(0, 1.0, -3.2),
		o + b * Vector3(0, 1.0, 3.2), o + b * Vector3(-1.8, 1.0, 0), o + b * Vector3(1.8, 1.0, 0)]

func get_collision_rids() -> Array[RID]:
	var out: Array[RID] = []
	if _armor != null:
		out.append(_armor.get_rid())
	return out

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	if dead:
		return
	_drive(delta)
	_turret(delta)
	_animate(delta)

func _drive(delta: float) -> void:
	var want_speed := 0.0
	var want_yaw_rate := 0.0
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if _path_i < _path.size():
		var tgt := _path[_path_i]
		var to := tgt - global_position
		to.y = 0.0
		var last := _path_i == _path.size() - 1
		if to.length() < (1.2 if last else 3.0):
			_path_i += 1
		else:
			var ang := fwd.signed_angle_to(to.normalized(), Vector3.UP)
			want_yaw_rate = clampf(ang * 1.5, -1.0, 1.0) * deg_to_rad(turn_rate_deg)
			var align := clampf(1.0 - absf(ang) / deg_to_rad(50.0), 0.0, 1.0)
			want_speed = _max_speed * align
			if last:
				want_speed = minf(want_speed, to.length() * 0.6 + 0.3)
	_speed = move_toward(_speed, want_speed, accel * delta)
	_yaw_rate = move_toward(_yaw_rate, want_yaw_rate, deg_to_rad(40.0) * delta)
	rotate_y(_yaw_rate * delta)
	var pos := global_position + (-global_transform.basis.z) * _speed * delta
	# Boden folgen: Hoehe und Neigung aus drei Strahlen
	var b := global_transform.basis
	var ex: Array[RID] = get_collision_rids()
	var pf := _ground(pos + b * Vector3(0, 0, -2.6), ex)
	var pl := _ground(pos + b * Vector3(-1.4, 0, 2.4), ex)
	var pr := _ground(pos + b * Vector3(1.4, 0, 2.4), ex)
	var n := (pr - pf).cross(pl - pf).normalized()
	if n.y < 0.0:
		n = -n
	if n.length() < 0.5 or n.y < 0.5:
		n = Vector3.UP
	var mid := (pf + (pl + pr) * 0.5) * 0.5
	pos.y = lerpf(global_position.y, mid.y, 1.0 - exp(-delta * 8.0))
	var cur_up := global_transform.basis.y
	var up := cur_up.slerp(n, 1.0 - exp(-delta * 5.0)).normalized()
	var f := (-global_transform.basis.z)
	f = (f - up * f.dot(up)).normalized()
	global_transform = Transform3D(Basis.looking_at(f, up), pos)
	# Kettengeschwindigkeit je Seite
	var half := 1.45
	_track_l += (_speed - _yaw_rate * half) * delta
	_track_r += (_speed + _yaw_rate * half) * delta

func _ground(p: Vector3, ex: Array[RID]) -> Vector3:
	var hit := VF.ray(self, p + Vector3.UP * 3.0, p + Vector3.DOWN * 8.0, VF.LAYER_WORLD, ex)
	if hit.is_empty():
		return Vector3(p.x, global_position.y, p.z)
	return hit["position"]

func _turret(delta: float) -> void:
	var turret: Node3D = _parts["turret"]
	var mantlet: Node3D = _parts["mantlet"]
	var muzzle: Marker3D = _parts["muzzle"]
	var has_target := _target != null and is_instance_valid(_target) and _target.is_inside_tree()
	if has_target and _target.has_method("is_alive") and not _target.call("is_alive"):
		has_target = false
	var aim := Vector3.INF
	if has_target:
		_fire_t += delta
		var tp := _target.global_position + Vector3.UP * 1.0
		if not _aiming and _fire_t >= fire_interval - aim_time:
			if global_position.distance_to(tp) <= max_range:
				_begin_aim(tp)
			else:
				_fire_t = 0.0
		if _aiming:
			aim = _aim_point
			if _fire_t >= fire_interval:
				_fire()
		else:
			# lockere Verfolgung mit Versatz (wirkt suchend), erst beim Ausrichten exakt
			aim = tp + Vector3(sin(_t * 0.6) * 4.0, 0.0, cos(_t * 0.45) * 4.0)
	var want_yaw := 0.0
	var want_pitch := 0.0
	if aim != Vector3.INF:
		var lt := turret.global_transform.affine_inverse() * aim
		var cur_yaw := turret.rotation.y
		want_yaw = cur_yaw + atan2(-lt.x, -lt.z)
		var lm := (turret.global_transform * Transform3D(Basis.IDENTITY, mantlet.position)).affine_inverse() * aim
		want_pitch = clampf(atan2(lm.y, Vector2(lm.x, lm.z).length()), deg_to_rad(-6.0), deg_to_rad(18.0))
	var step := deg_to_rad(turret_speed_deg) * delta
	var dy := wrapf(want_yaw - turret.rotation.y, -PI, PI)
	turret.rotation.y += clampf(dy, -step, step)
	mantlet.rotation.x = move_toward(mantlet.rotation.x, want_pitch, step * 0.6)
	if _servo_snd:
		var moving := absf(dy) > 0.02
		_servo_snd.volume_db = lerpf(_servo_snd.volume_db, -4.0 if moving else -60.0, 1.0 - exp(-delta * 10.0))
	if _laser.visible:
		var from := muzzle.global_position
		var to := _aim_point
		var hit := VF.ray(self, from, from + (to - from).normalized() * 200.0, VF.LAYER_WORLD | VF.LAYER_PLAYER, get_collision_rids())
		if not hit.is_empty():
			to = hit["position"]
		var d := from.distance_to(to)
		var dir := (to - from) / maxf(d, 0.01)
		var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
		var bas := Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, PI * 0.5)
		_laser.global_transform = Transform3D(bas * Basis.from_scale(Vector3(1, d, 1)), from + dir * d * 0.5)
		_laser_mat.albedo_color.a = 0.25 + 0.25 * sin(_t * 30.0)

## Waehlt den Einschlagpunkt: einige Meter neben dem Ziel, bevorzugt zwischen Panzer und Ziel.
func _begin_aim(tp: Vector3) -> void:
	_aiming = true
	var ground := tp + Vector3.DOWN * 1.0
	var to_tank := global_position - ground
	to_tank.y = 0.0
	var base_ang := atan2(to_tank.x, to_tank.z)
	var ang := base_ang + randf_range(-1.3, 1.3)
	var r := randf_range(miss_min, miss_max)
	var p := ground + Vector3(sin(ang), 0.0, cos(ang)) * r
	var hit := VF.ray(self, p + Vector3.UP * 4.0, p + Vector3.DOWN * 6.0, VF.LAYER_WORLD, get_collision_rids())
	_aim_point = (hit["position"] as Vector3) + Vector3.UP * 0.3 if not hit.is_empty() else p
	_laser.visible = true
	VF.play_at(self, "veh_tank_warn", (_parts["turret"] as Node3D).global_position, -2.0, 10.0, 90.0)

func _fire() -> void:
	_aiming = false
	_fire_t = 0.0
	_laser.visible = false
	var muzzle: Marker3D = _parts["muzzle"]
	var from := muzzle.global_position
	var dir := (_aim_point - from).normalized()
	var to := _aim_point + dir * 3.0
	var hit := VF.ray(self, from, to, VF.LAYER_WORLD | VF.LAYER_PLAYER, get_collision_rids())
	var impact := to if hit.is_empty() else (hit["position"] as Vector3)
	# Muendung: Feuer, Rauchring, Staub am Boden, Ruecklauf, Wanne kippt
	VF.show_flash(_parts["flash"], 0.08)
	VFX.spawn_dust_cloud(from + (-muzzle.global_transform.basis.z) * 1.5, 2.2)
	VFX.spawn_dust_cloud(global_position + (-global_transform.basis.z) * 4.0, 3.5)
	_recoil = 1.0
	_rock_v -= 2.5
	VF.play_at(self, "veh_tank_cannon", from, 6.0, 40.0, 900.0)
	VF.shake_player(self, from, 0.35, 40.0)
	VF.tracer(self, from, impact, 420.0, "orange", 3.0)
	var flight := from.distance_to(impact) / 420.0
	get_tree().create_timer(flight, false).timeout.connect(func() -> void:
		Combat.explode(impact, shell_radius, shell_damage, self, 1.8)
		VFX.spawn_dust_cloud(impact, 4.0))

func _animate(delta: float) -> void:
	var tm_l: ShaderMaterial = _parts.get("track_mat_l")
	var tm_r: ShaderMaterial = _parts.get("track_mat_r")
	if tm_l:
		tm_l.set_shader_parameter("scroll", _track_l)
		tm_r.set_shader_parameter("scroll", _track_r)
	var wm_l: ShaderMaterial = _parts.get("wheel_mat_l")
	if wm_l:
		wm_l.set_shader_parameter("spin", _track_l)
		(_parts["wheel_mat_r"] as ShaderMaterial).set_shader_parameter("spin", _track_r)
	for w: Node3D in _parts.get("wheels_l", []):
		w.rotation.x = -_track_l / 0.32
	for w: Node3D in _parts.get("wheels_r", []):
		w.rotation.x = -_track_r / 0.32
	# Ruecklauf des Rohrs + Wippen der Wanne (gedaempfte Feder)
	_recoil = move_toward(_recoil, 0.0, delta * 1.6)
	(_parts["barrel"] as Node3D).position.z = 0.45 * ease(_recoil, 0.4)
	_rock_v += (-_rock * 30.0 - _rock_v * 4.0) * delta
	_rock += _rock_v * delta
	_model_root.rotation.x = _rock * 0.04 + (_speed - _max_speed * 0.5) * 0.0
	var ant: Node3D = _parts.get("antenna")
	if ant:
		ant.rotation.x = deg_to_rad(-6.0) - _rock * 0.15 + sin(_t * 3.0) * 0.02 * _speed
	var spd := absf(_speed) + absf(_yaw_rate) * 2.0
	if _engine_snd:
		_engine_snd.pitch_scale = 0.85 + spd * 0.06
		_engine_snd.volume_db = -2.0 + minf(spd, 4.0) * 1.0
	if _track_snd:
		_track_snd.volume_db = lerpf(-40.0, 0.0, clampf(spd / 3.0, 0.0, 1.0))
		_track_snd.pitch_scale = 0.8 + spd * 0.06
	if _exhaust:
		_exhaust.amount_ratio = clampf(0.4 + absf(_speed - move_toward(_speed, _max_speed, 0.1)) + spd * 0.12, 0.3, 1.0)

# ------------------------------------------------------------------ Zerstoerung

func _do_destroy() -> void:
	var b := global_transform.basis
	var center := global_position + b * Vector3(0, 1.4, 0)
	Combat.explode(center, 7.0, 90.0, self, 2.6)
	VF.play_at(self, "veh_tank_explode", center, 8.0, 50.0, 900.0)
	VF.shake_player(self, center, 0.8, 60.0)
	VFX.spawn_scorch(global_position, Vector3.UP, 10.0, 180.0)
	if _engine_snd:
		_engine_snd.stop()
	if _track_snd:
		_track_snd.stop()
	if _servo_snd:
		_servo_snd.stop()
	if _exhaust:
		_exhaust.emitting = false
	_launch_turret()
	VF.char_all(_model_root)
	# Stichflamme aus dem Turmring, danach Dauerbrand mit Rauchsaeule
	_attach_fire(Vector3(0, 1.6, 0.2), 2.0, true)
	_attach_fire(Vector3(-0.8, 1.5, 2.4), 1.0, false)
	_flame_jet(global_position + b * Vector3(0, 1.6, 0.25))
	for i in 3:
		get_tree().create_timer(2.0 + i * randf_range(1.2, 2.2), false).timeout.connect(func() -> void:
			if is_inside_tree():
				VFX.spawn_explosion(global_position + global_transform.basis * Vector3(randf_range(-1, 1), 1.6, randf_range(-2, 2)), randf_range(0.6, 1.0)))

func _attach_fire(local: Vector3, size: float, big_smoke: bool) -> void:
	if not ResourceLoader.exists(FIRE_SCENE):
		return
	var f := (load(FIRE_SCENE) as PackedScene).instantiate() as Node3D
	f.set("size", size)
	f.set("smoke_height", 3.2 if big_smoke else 1.2)
	f.set("light_energy", 10.0 if big_smoke else 3.0)
	f.set("light_range", 18.0 if big_smoke else 8.0)
	if not big_smoke and size < 0.8:
		f.set("flame_amount", 3)
		f.set("light_enabled", false)
	_model_root.add_child(f)
	f.position = local

## Kurze, sehr hohe Stichflamme (Munitionsbrand) aus dem Turmring.
func _flame_jet(p: Vector3) -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.6
	pm.direction = Vector3.UP
	pm.spread = 8.0
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -2.0, 0)
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.scale_min = 1.6
	pm.scale_max = 2.8
	pm.scale_curve = VfxLib.curve_tex([[0.0, 0.5], [0.3, 1.0], [1.0, 1.6]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.0)], [0.1, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]])
	var jet := VfxLib.make_particles(60, 1.1, pm, VfxLib.quad(1.0), VfxLib.fire_mat({"intensity": 2.6, "tex_scale": 0.5, "rise": 1.4, "core_heat": 2.0}))
	jet.one_shot = false
	jet.explosiveness = 0.0
	jet.emitting = true
	jet.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 30, 16))
	VF.effects_root(self).add_child(jet)
	jet.global_position = p
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 30.0
	l.omni_range = 30.0
	l.position = Vector3(0, 4, 0)
	jet.add_child(l)
	var tw := jet.create_tween()
	tw.tween_interval(2.2)
	tw.tween_callback(func() -> void: jet.emitting = false)
	tw.parallel().tween_property(l, "light_energy", 0.0, 1.5).set_delay(1.0)
	tw.tween_interval(1.5)
	tw.tween_callback(jet.queue_free)

func _launch_turret() -> void:
	var turret: Node3D = _parts["turret"]
	if _turret_shape:
		_turret_shape.set_deferred("disabled", true)
	var rb := RigidBody3D.new()
	rb.name = "TankTurretDebris"
	rb.mass = 2500.0
	rb.collision_layer = VF.LAYER_DEBRIS | VF.LAYER_WORLD
	rb.collision_mask = VF.LAYER_WORLD | VF.LAYER_DEBRIS
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 0.9, 3.2)
	cs.shape = bs
	cs.position = Vector3(0, 0.45, 0.1)
	rb.add_child(cs)
	var root := VF.effects_root(self)
	var gt := turret.global_transform
	root.add_child(rb)
	rb.global_transform = gt
	turret.reparent(rb, true)
	var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	rb.linear_velocity = Vector3.UP * randf_range(13.0, 17.0) + side * randf_range(1.5, 3.5)
	rb.angular_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(-3.0, 3.0), randf_range(-2.5, 2.5))
	var landed := [false]
	var t0 := Time.get_ticks_msec()
	rb.body_entered.connect(func(_b: Node) -> void:
		if landed[0] or Time.get_ticks_msec() - t0 < 600:
			return
		landed[0] = true
		VFX.spawn_dust_cloud(rb.global_position, 4.0)
		VF.play_at(rb, "veh_metal_crash", rb.global_position, 4.0, 25.0, 300.0)
		VF.shake_player(rb, rb.global_position, 0.3, 30.0))
	get_tree().create_timer(14.0, false).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.freeze = true)
