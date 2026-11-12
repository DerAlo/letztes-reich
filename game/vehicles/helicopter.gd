class_name Helicopter
extends CharacterBody3D
## Kampfhubschrauber (Gegner). Gruppen enemy, damageable, vehicle.
## API: fly_path(points, speed, loop), hover_at(p), attack(enable), take_damage/is_alive/get_status.
## Tod: rauchende Trudelspirale, Absturz, grosse Explosion, brennendes Wrack. Signal destroyed (beim Abschuss),
## zusaetzlich crashed (beim Aufschlag).

signal destroyed
signal crashed

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const ModelCache = preload("res://game/vehicles/models/model_cache.gd")
const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const HeliModel = preload("res://game/vehicles/models/heli_model.gd")
const Mi8Model = preload("res://game/vehicles/models/mi8_model.gd")
const Mi28Model = preload("res://game/vehicles/models/mi28_model.gd")
const HeliReal = preload("res://game/vehicles/models/heli_real.gd")
const FIRE_SCENE := "res://game/vfx/fire.tscn"

enum Mode { IDLE, PATH, HOVER, DYING, WRECK }

@export_group("Werte")
@export var max_health: float = 600.0
@export var faction: String = "ru"                  ## Optik: "ru", "eu" oder "reich" (auch per set_meta("faction"))
@export_group("Flug")
@export var accel: float = 7.0                      ## m/s^2
@export var turn_rate_deg: float = 55.0
@export var hover_bob: float = 0.35
@export_group("Bordkanone")
@export var mg_damage: float = 8.0                  ## pro Treffer am Spieler
@export var burst_rounds: int = 16
@export var fire_rate: float = 12.0                 ## Schuss/s
@export var burst_pause_min: float = 2.6
@export var burst_pause_max: float = 4.2
@export var warn_time: float = 0.8                  ## Kanone schwenkt + Anlaufgeraeusch vor der Salve
@export var attack_range: float = 160.0
@export_group("Optik")
@export var searchlight: bool = false               ## Suchscheinwerfer (Nacht)
@export var downwash: bool = true
## Modell: "auto" (oder "") = automatisch (Fraktion "eu" -> Mi-8-Transporter, sonst Mi-28N), "mi8", "mi28n",
## "procedural" (altes Blockmodell). Auch per set_meta("model_kind").
@export_enum("auto", "mi8", "mi28n", "procedural") var model_kind: String = "auto"

var health: float = 600.0
var mode: Mode = Mode.IDLE

var _path: Array[Vector3] = []
var _path_i: int = 0
var _speed: float = 18.0
var _loop: bool = false
var _hover_point: Vector3 = Vector3.ZERO
var _vel: Vector3 = Vector3.ZERO
var _prev_vel: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _t: float = 0.0
var _attack: bool = false
var _burst_cd: float = 2.0
var _burst_left: int = 0
var _shot_cd: float = 0.0
var _warn: float = 0.0
var _strafe_a: Vector3 = Vector3.ZERO
var _strafe_b: Vector3 = Vector3.ZERO
var _burst_total: int = 1
var _rotor_angle: float = 0.0
var _rotor_speed: float = 1.0                       ## 0..1
var _spin_rate: float = 0.0
var _dying_time: float = 0.0
var _ground_tick: float = 0.0
var _ground_hit: Dictionary = {}

var _pivot: Node3D
var _parts: Dictionary = {}
var _rotor_snd: AudioStreamPlayer3D
var _turbine_snd: AudioStreamPlayer3D
var _dust: GPUParticles3D
var _spray: GPUParticles3D
var _spot: SpotLight3D
var _smoke_trail: Node3D
var _hit_flash: float = 0.0
var nav_lights: bool = true

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	add_to_group("damageable")
	add_to_group("vehicle")
	collision_layer = VF.LAYER_ENEMY
	collision_mask = 0
	_yaw = rotation.y
	_hover_point = global_position
	if has_meta("faction"):
		faction = str(get_meta("faction"))
	if has_meta("model_kind"):
		model_kind = str(get_meta("model_kind"))
	_build()
	_build_audio()

func _build() -> void:
	# Kollision (am Rumpf, nicht am Neige-Pivot) — erstes Shape = Zielpunkt fuer den Bot
	_pivot = Node3D.new()
	_pivot.name = "Model"
	add_child(_pivot)
	_parts = ModelCache.build(model_script(faction, model_kind), _pivot, faction)   # Klon statt Neubau (100-280 ms)
	var boxes: Array = _parts.get("hitboxes", [])
	if boxes.is_empty():
		_add_shape(Vector3(0, 0.1, -0.6), Vector3(2.2, 2.4, 6.6))
		_add_shape(Vector3(0, 0.6, 6.0), Vector3(1.2, 1.4, 6.0))
		_add_shape(Vector3(0, 0.25, -0.3), Vector3(6.4, 0.6, 1.6))
	else:
		for hb: AABB in boxes:
			_add_shape(hb.get_center(), hb.size)
	VF.merge_static(_pivot, _parts.values())
	if downwash:
		_build_downwash()
	if searchlight:
		set_searchlight(true)

## Modellskript fuer Fraktion/Modellwahl (auch fuer Level, die Modelle selbst bauen).
static func model_script(fac: String, kind: String = "") -> Script:
	if kind == "" or kind == "auto":
		kind = "mi8" if fac == "eu" else "mi28n"
	match kind:
		"mi8":
			return Mi8Model if HeliReal.available("mi8") else HeliModel
		"mi28n":
			return Mi28Model if HeliReal.available("mi28n") else HeliModel
	return HeliModel

func _add_shape(pos: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)

func _build_audio() -> void:
	_rotor_snd = VF.loop_player(self, "veh_heli_rotor", 30.0, 700.0, 2.0)
	_turbine_snd = VF.loop_player(self, "veh_heli_turbine", 10.0, 220.0, -6.0)

# ------------------------------------------------------------------ API

## Fliegt die Punkte ab (Weltkoordinaten). Ohne loop schwebt er am letzten Punkt.
func fly_path(points: Array[Vector3], speed: float = 18.0, loop: bool = false) -> void:
	if not _alive_mode():
		return
	_path = points.duplicate()
	_path_i = 0
	_speed = maxf(speed, 1.0)
	_loop = loop
	if _path.is_empty():
		hover_at(global_position)
		return
	mode = Mode.PATH

## Fliegt zu p und schwebt dort (mit leichtem Pendeln). Bei aktivem Angriff richtet er die Nase auf den Spieler.
func hover_at(p: Vector3) -> void:
	if not _alive_mode():
		return
	_hover_point = p
	mode = Mode.HOVER

## MG-Salven auf den Spieler an/aus.
func attack(enable: bool) -> void:
	_attack = enable
	if enable:
		_burst_cd = minf(_burst_cd, randf_range(1.0, 2.0))

## Suchscheinwerfer an/aus (zusaetzlich zur API).
func set_searchlight(on: bool) -> void:
	if on and _spot == null:
		_spot = SpotLight3D.new()
		_spot.light_color = Color(0.95, 0.97, 1.0)
		_spot.light_energy = 16.0
		_spot.spot_range = 90.0
		_spot.spot_angle = 9.0
		_spot.spot_attenuation = 0.6
		_spot.light_volumetric_fog_energy = 4.0
		_spot.shadow_enabled = true
		_spot.rotation_degrees = Vector3(-60, 0, 0)
		var mount: Node3D = _parts.get("searchlight_mount", _pivot)
		mount.add_child(_spot)
	if _spot:
		_spot.visible = on

## Panzerfaust-Volltreffer: ein Drittel der Lebenspunkte (3 Treffer). Die Druckwelle derselben Rakete zaehlt nicht extra.
const ROCKET_HITS: int = 3
var _rocket_frame: int = -1

func rocket_hit(source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not _alive_mode():
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

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if not _alive_mode() or amount <= 0.0:
		return
	if _rocket_frame == Engine.get_physics_frames() and bool(Combat.get("explosion_active")):
		return
	if not _in_rocket and amount < 500.0 and not _heavy_source(source):
		if randf() < 0.35 and not bool(Combat.get("explosion_active")):
			VFX.spawn_impact(hit_position, hit_normal, "metal")   # Kugel prallt ab
		return
	health -= amount
	_hit_flash = 1.0
	Events.enemy_damaged.emit(self, amount)
	if randf() < 0.35:
		VFX.spawn_impact(hit_position, hit_normal, "metal")
	if health <= 0.0:
		_die(source)
	elif health < max_health * 0.5 and _smoke_trail == null:
		_start_smoke(false)

func is_alive() -> bool:
	return _alive_mode()

func get_status() -> Dictionary:
	var p := global_position
	return {
		"type": "helicopter",
		"alive": _alive_mode(),
		"health": maxf(health, 0.0),
		"position": [p.x, p.y, p.z],
		"state": Mode.keys()[mode],
	}

## Trefferpunkte fuer Combat.explode (Rumpfmitte, Nase, Heck).
func get_damage_points() -> Array[Vector3]:
	var b := global_transform.basis
	var tz: float = _parts.get("tail_z", 9.5)
	return [global_position, global_position + b * Vector3(0, 0, -3.0), global_position + b * Vector3(0, 0.5, tz * 0.55)]

func _alive_mode() -> bool:
	return mode != Mode.DYING and mode != Mode.WRECK

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	match mode:
		Mode.PATH, Mode.HOVER, Mode.IDLE:
			_fly(delta)
			if _attack:
				_tick_attack(delta)
			else:
				_aim_gun(Vector3.INF, delta)
		Mode.DYING:
			_tick_dying(delta)
		Mode.WRECK:
			pass

func _process(delta: float) -> void:
	_animate_rotors(delta)
	_update_downwash(delta)
	_update_audio()
	_blink_lights()

func _fly(delta: float) -> void:
	var pos := global_position
	var desired := Vector3.ZERO
	match mode:
		Mode.PATH:
			var target := _path[_path_i]
			var to := target - pos
			var last := _path_i == _path.size() - 1 and not _loop
			if to.length() < maxf(4.0, _speed * 0.35) and not last:
				_path_i += 1
				if _path_i >= _path.size():
					_path_i = 0
				target = _path[_path_i]
				to = target - pos
			if last:
				desired = to.normalized() * minf(_speed, to.length() * 0.6)
				if to.length() < 1.5:
					hover_at(target)
			else:
				desired = to.normalized() * _speed
		Mode.HOVER:
			var bob := Vector3(sin(_t * 0.7) * 1.2, sin(_t * 1.1) * hover_bob * 2.0, cos(_t * 0.53) * 1.0)
			var to := _hover_point + bob - pos
			desired = to * 0.8
			desired = desired.limit_length(_speed)
		_:
			desired = Vector3.ZERO
	_prev_vel = _vel
	_vel = _vel.move_toward(desired, accel * delta)
	global_position = pos + _vel * delta

	# Gierwinkel: im Angriff/Schwebeflug zum Spieler, sonst in Flugrichtung
	var face_dir := Vector3.ZERO
	var pl := _player()
	var hspeed := Vector2(_vel.x, _vel.z).length()
	if _attack and pl != null and (mode == Mode.HOVER or hspeed < 9.0):
		face_dir = pl.global_position - pos
	elif hspeed > 1.5:
		face_dir = _vel
	if face_dir.length() > 0.1:
		var want := atan2(-face_dir.x, -face_dir.z)
		var diff := wrapf(want - _yaw, -PI, PI)
		var step := deg_to_rad(turn_rate_deg) * delta
		_yaw += clampf(diff, -step, step)
	rotation = Vector3(0, _yaw, 0)

	# Neigung des Modells: Nase runter bei Vorwaertsfahrt/Beschleunigung, Rollen in Kurven
	var acc := (_vel - _prev_vel) / maxf(delta, 0.001)
	var inv := Basis(Vector3.UP, _yaw).inverse()
	var lv := inv * _vel
	var la := inv * acc
	var pitch := clampf(lv.z * 0.012 + la.z * 0.03, -0.3, 0.3)
	var roll := clampf(-lv.x * 0.015 - la.x * 0.045, -0.45, 0.45)
	_pivot.rotation.x = lerpf(_pivot.rotation.x, pitch, 1.0 - exp(-delta * 3.0))
	_pivot.rotation.z = lerpf(_pivot.rotation.z, roll, 1.0 - exp(-delta * 3.0))
	_pivot.position.y = sin(_t * 2.1) * 0.06

# ------------------------------------------------------------------ Angriff

func _tick_attack(delta: float) -> void:
	var pl := _player()
	if pl == null or (pl.has_method("is_alive") and not pl.call("is_alive")):
		_aim_gun(Vector3.INF, delta)
		return
	var target := pl.global_position + Vector3.UP * 1.0
	var muzzle: Marker3D = _parts["muzzle"]
	var dist := muzzle.global_position.distance_to(target)
	if _burst_left > 0:
		_shot_cd -= delta
		var k := 1.0 - float(_burst_left) / float(_burst_total)
		var aim := _strafe_a.lerp(_strafe_b, k)
		_aim_gun(aim, delta, 8.0)
		while _shot_cd <= 0.0 and _burst_left > 0:
			_shot_cd += 1.0 / fire_rate
			_fire_round(aim)
			_burst_left -= 1
			k = 1.0 - float(_burst_left) / float(_burst_total)
			aim = _strafe_a.lerp(_strafe_b, k)
		if _burst_left == 0:
			_burst_cd = randf_range(burst_pause_min, burst_pause_max)
		return
	_aim_gun(target, delta, 3.0)
	_burst_cd -= delta
	if _burst_cd <= warn_time and _warn <= 0.0 and _burst_cd > 0.0:
		_warn = warn_time
		VF.play_at(self, "veh_heli_gun_spin", muzzle.global_position, 0.0, 20.0, 250.0)
	_warn -= delta
	if _burst_cd > 0.0:
		return
	if dist > attack_range or not _has_los(muzzle.global_position, target):
		_burst_cd = 0.8
		return
	_start_burst(pl)

## Feuerstoss "laeuft" ueber den Boden: beginnt einige Meter vor dem Spieler (zum Heli hin), endet knapp hinter ihm.
## Wer sich bewegt, weicht aus; wer stehen bleibt, wird von einem Teil der Salve getroffen.
func _start_burst(pl: Node3D) -> void:
	var p := pl.global_position
	var from := global_position
	var flat := p - from
	flat.y = 0.0
	var dir := flat.normalized() if flat.length() > 0.5 else Vector3.FORWARD
	var side := dir.cross(Vector3.UP).normalized() * randf_range(-1.5, 1.5)
	_strafe_a = p - dir * randf_range(7.0, 10.0) + side + Vector3.UP * 0.2
	_strafe_b = p + dir * randf_range(2.5, 4.0) - side * 0.5 + Vector3.UP * 0.8
	_burst_total = burst_rounds
	_burst_left = burst_rounds
	_shot_cd = 0.0

func _fire_round(aim: Vector3) -> void:
	var muzzle: Marker3D = _parts["muzzle"]
	var from := muzzle.global_position
	var jitter := Vector3(randf_range(-0.6, 0.6), randf_range(-0.2, 0.3), randf_range(-0.6, 0.6))
	var dir := (aim + jitter - from).normalized()
	var to := from + dir * (from.distance_to(aim) + 40.0)
	var hit := VF.ray(self, from, to, VF.LAYER_WORLD | VF.LAYER_PLAYER, [get_rid()])
	var end := to
	VF.show_flash(_parts["flash"], 0.04)
	VF.play_at(self, "veh_heli_gun", from, 2.0, 25.0, 450.0, randf_range(0.95, 1.05))
	if hit.is_empty():
		VF.tracer(self, from, end, 320.0, "red", 1.3)
		VFX.play_whiz_along(from, end, 4.0)
		return
	end = hit["position"]
	VF.tracer(self, from, end, 320.0, "red", 1.3)
	var col: Object = hit.get("collider")
	if col is Node and (col as Node).is_in_group("player"):
		(col as Node).call("take_damage", mg_damage, self, end, hit["normal"])
	else:
		var surface := "concrete"
		if col is Node:
			surface = str((col as Node).get_meta("surface", "concrete"))
		VFX.spawn_impact(end, hit["normal"], surface)
		VFX.play_whiz_along(from, end, 3.0)
		# Grosse Kaliber: Staubfontaene alle paar Schuss
		if randf() < 0.3:
			VFX.spawn_dust_cloud(end, 0.8)

func _aim_gun(target: Vector3, delta: float, rate: float = 3.0) -> void:
	var gy: Node3D = _parts.get("gun_yaw")
	var gp: Node3D = _parts.get("gun_pitch")
	if gy == null:
		return
	var want_yaw := 0.0
	var want_pitch := -0.15
	if target != Vector3.INF:
		var lp := _pivot.global_transform.affine_inverse() * target - gy.position
		want_yaw = clampf(atan2(-lp.x, -lp.z), -1.9, 1.9)
		want_pitch = clampf(atan2(lp.y, Vector2(lp.x, lp.z).length()), -1.3, 0.25)
	var k := 1.0 - exp(-delta * rate)
	gy.rotation.y = lerp_angle(gy.rotation.y, want_yaw, k)
	gp.rotation.x = lerp_angle(gp.rotation.x, want_pitch, k)

func _has_los(from: Vector3, to: Vector3) -> bool:
	return VF.ray(self, from, to, VF.LAYER_WORLD, [get_rid()]).is_empty()

func _player() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D

# ------------------------------------------------------------------ Tod

func _die(_source: Node) -> void:
	mode = Mode.DYING
	_attack = false
	_burst_left = 0
	remove_from_group("enemy")
	remove_from_group("damageable")
	Events.enemy_killed.emit(self)
	destroyed.emit()
	VFX.spawn_explosion(global_position + global_transform.basis * Vector3(0, 1.2, 1.5), 1.3)
	_start_smoke(true)
	_spin_rate = 0.0
	_dying_time = 0.0
	if _vel.length() < 6.0:
		_vel += -global_transform.basis.z * 6.0

func _start_smoke(burning: bool) -> void:
	if _smoke_trail != null:
		if burning:
			_smoke_trail.queue_free()
		else:
			return
	if not ResourceLoader.exists(FIRE_SCENE):
		return
	var f := (load(FIRE_SCENE) as PackedScene).instantiate() as Node3D
	f.set("size", 0.9 if burning else 0.45)
	f.set("smoke_height", 1.6)
	f.set("flame_amount", 14 if burning else 2)
	f.set("light_enabled", burning)
	f.set("embers_enabled", burning)
	_pivot.add_child(f)
	f.position = Vector3(0, 1.3, 2.0)
	_smoke_trail = f

func _tick_dying(delta: float) -> void:
	_dying_time += delta
	_spin_rate = minf(_spin_rate + delta * 2.6, 6.5)
	_yaw += _spin_rate * delta
	rotation = Vector3(0, _yaw, 0)
	_vel.y -= 7.5 * delta
	_vel.x = lerpf(_vel.x, 0.0, delta * 0.3)
	_vel.z = lerpf(_vel.z, 0.0, delta * 0.3)
	# Spiralbahn
	var side := global_transform.basis.x * 3.5
	var motion := (_vel + side) * delta
	_pivot.rotation.z = lerpf(_pivot.rotation.z, 0.35, delta)
	_pivot.rotation.x = lerpf(_pivot.rotation.x, 0.25, delta)
	var from := global_position
	var hit := VF.ray(self, from, from + motion + Vector3.DOWN * 1.8, VF.LAYER_WORLD, [get_rid()])
	if not hit.is_empty() or _dying_time > 12.0:
		var p: Vector3 = hit["position"] if not hit.is_empty() else from
		_crash(p, hit.get("normal", Vector3.UP))
		return
	global_position = from + motion
	if randf() < delta * 1.2:
		VFX.spawn_explosion(global_position + Vector3(randf_range(-1, 1), 1.0, randf_range(0, 3)), 0.6)

func _crash(p: Vector3, n: Vector3) -> void:
	mode = Mode.WRECK
	global_position = p + Vector3.UP * 1.0
	_vel = Vector3.ZERO
	_rotor_speed = 0.0
	Combat.explode(p + Vector3.UP * 1.2, 9.0, 140.0, self, 3.0)
	VFX.spawn_dust_cloud(p, 6.0)
	VFX.spawn_scorch(p, n, 9.0, 120.0)
	VF.shake_player(self, p, 0.6, 50.0)
	VF.play_at(self, "veh_heli_crash", p, 6.0, 35.0, 600.0)
	# Wrack: auf die Seite gelegt, verkohlt, Rotorblaetter abgerissen
	_pivot.rotation = Vector3(deg_to_rad(randf_range(-8, 8)), 0, deg_to_rad(randf_range(55, 80)) * (1.0 if randf() < 0.5 else -1.0))
	_pivot.position = Vector3(0, -0.2, 0)
	_fling_blades()
	VF.char_all(_pivot)
	for k in ["nav_l", "nav_r", "strobe"]:
		var b: Node3D = _parts.get(k)
		if b:
			b.visible = false
	if _spot:
		_spot.visible = false
	if _smoke_trail:
		_smoke_trail.queue_free()
		_smoke_trail = null
	_spawn_wreck_fire(p)
	collision_layer = VF.LAYER_WORLD
	if _dust:
		_dust.emitting = false
	if _spray:
		_spray.emitting = false
	if _rotor_snd:
		_rotor_snd.stop()
	if _turbine_snd:
		_turbine_snd.stop()
	crashed.emit()

func _spawn_wreck_fire(p: Vector3) -> void:
	if not ResourceLoader.exists(FIRE_SCENE):
		return
	var scene := load(FIRE_SCENE) as PackedScene
	var root := VF.effects_root(self)
	var main := scene.instantiate() as Node3D
	main.set("size", 2.2)
	main.set("smoke_height", 2.6)
	main.set("light_energy", 9.0)
	main.set("light_range", 16.0)
	root.add_child(main)
	main.global_position = p + Vector3.UP * 0.6
	var tail := scene.instantiate() as Node3D
	tail.set("size", 0.9)
	tail.set("smoke_enabled", true)
	tail.set("light_enabled", false)
	root.add_child(tail)
	tail.global_position = global_position + global_transform.basis * Vector3(0, 0, float(_parts.get("tail_z", 9.5)) * 0.63) + Vector3.DOWN * 0.6
	# Nachexplosionen (Munition)
	for i in 3:
		get_tree().create_timer(1.2 + i * randf_range(0.9, 1.8), false).timeout.connect(func() -> void:
			if is_inside_tree():
				VFX.spawn_explosion(p + Vector3(randf_range(-2.5, 2.5), 0.8, randf_range(-2.5, 2.5)), randf_range(0.5, 0.9)))

func _fling_blades() -> void:
	var blades: Node3D = _parts.get("blades")
	var disc: Node3D = _parts.get("disc")
	if disc:
		disc.visible = false
	if blades == null:
		return
	var root := VF.effects_root(self)
	for arm in blades.get_children():
		for mi in (arm as Node3D).get_children():
			if not (mi is MeshInstance3D):
				continue
			var rb := RigidBody3D.new()
			rb.collision_layer = VF.LAYER_DEBRIS
			rb.collision_mask = VF.LAYER_WORLD | VF.LAYER_DEBRIS
			rb.mass = 60.0
			var gt := (mi as MeshInstance3D).global_transform
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = (mi as MeshInstance3D).mesh.get_aabb().size
			cs.shape = bs
			rb.add_child(cs)
			root.add_child(rb)
			rb.global_transform = gt
			(mi as Node3D).reparent(rb, true)
			var out := (gt.origin - global_position)
			out.y = 0.0
			rb.linear_velocity = out.normalized() * randf_range(8.0, 16.0) + Vector3.UP * randf_range(4.0, 9.0)
			rb.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-12, 12), randf_range(-3, 3))
			_settle_later(rb, 10.0)
			break
	blades.visible = false

func _settle_later(rb: RigidBody3D, t: float) -> void:
	get_tree().create_timer(t, false).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.freeze = true)

# ------------------------------------------------------------------ Optik/Sound

func _animate_rotors(delta: float) -> void:
	if mode == Mode.WRECK:
		_rotor_speed = 0.0
	elif mode == Mode.DYING:
		_rotor_speed = lerpf(_rotor_speed, 0.75, delta * 0.5)
	var blades: Node3D = _parts.get("blades")
	if blades == null:
		return
	# Sichtbare Blattdrehung bewusst langsamer als real (kein Stroboskop-Effekt), Scheibe liefert das Tempo
	_rotor_angle += delta * 11.0 * _rotor_speed
	blades.rotation.y = -_rotor_angle
	var disc_mat: ShaderMaterial = _parts.get("disc_mat")
	if disc_mat:
		disc_mat.set_shader_parameter("spin", _rotor_angle * 2.7)
		disc_mat.set_shader_parameter("opacity", 0.34 * _rotor_speed)
	var tr: Node3D = _parts.get("tail_rotor")
	if tr:
		tr.rotation.x += delta * 23.0 * _rotor_speed
	var tdm: ShaderMaterial = _parts.get("tail_disc_mat")
	if tdm:
		tdm.set_shader_parameter("spin", -_rotor_angle * 5.0)
		tdm.set_shader_parameter("opacity", 0.28 * _rotor_speed)
	for b: MeshInstance3D in _parts.get("blade_meshes", []):
		b.transparency = 0.55 * _rotor_speed

func _blink_lights() -> void:
	var on := fmod(_t, 1.2) < 0.08 and nav_lights
	var s: Node3D = _parts.get("strobe")
	if s and mode != Mode.WRECK:
		s.visible = on

## Positionslichter + Blitzer an/aus (z. B. verdeckter Flug "Lichter aus").
func set_nav_lights(on: bool) -> void:
	nav_lights = on
	for k in ["nav_l", "nav_r", "strobe"]:
		var b: Node3D = _parts.get(k)
		if b:
			b.visible = on

func _update_audio() -> void:
	if _rotor_snd:
		var spd := _vel.length()
		_rotor_snd.pitch_scale = lerpf(0.82, 1.0, _rotor_speed) + spd * 0.002 + (0.15 if mode == Mode.DYING else 0.0)
	if _turbine_snd:
		_turbine_snd.pitch_scale = 1.0 + (0.35 if mode == Mode.DYING else 0.0)

# ------------------------------------------------------------------ Rotor-Abwind

func _build_downwash() -> void:
	_dust = _make_wash(Color(0.36, 0.32, 0.27), Color(0.45, 0.42, 0.38), 64, 2.6)
	_spray = _make_wash(Color(0.75, 0.8, 0.85), Color(0.85, 0.88, 0.9), 90, 1.6)

func _make_wash(c0: Color, c1: Color, amount: int, life: float) -> GPUParticles3D:
	var pm := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 30.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 2.5
	pm.emission_ring_inner_radius = 0.5
	pm.emission_ring_height = 0.2
	pm.direction = Vector3.UP
	pm.spread = 10.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.5
	pm.radial_velocity_min = 7.0
	pm.radial_velocity_max = 14.0
	pm.gravity = Vector3(0, 0.6, 0)
	pm.damping_min = 2.0
	pm.damping_max = 3.5
	pm.scale_min = 1.6
	pm.scale_max = 2.8
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.4], [0.3, 1.0], [1.0, 2.0]])
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.55, 0.1, 0.4)
	var mat := VfxLib.smoke_mat({"smoke_color": c0, "smoke_color_end": c1, "density": 1.1, "glow": 0.0, "soft_dist": 0.8, "erosion": 0.3, "frame_span": 4.0}, true)
	var p := VfxLib.make_particles(amount, life, pm, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.3
	p.emitting = false
	p.top_level = true
	p.visibility_aabb = AABB(Vector3(-25, -3, -25), Vector3(50, 12, 50))
	add_child(p)
	return p

func _update_downwash(delta: float) -> void:
	if _dust == null or mode == Mode.WRECK:
		return
	_ground_tick -= delta
	if _ground_tick <= 0.0:
		_ground_tick = 0.12
		var from := global_position
		_ground_hit = VF.ray(self, from, from + Vector3.DOWN * 28.0, VF.LAYER_WORLD, [get_rid()])
	if _ground_hit.is_empty():
		_dust.emitting = false
		_spray.emitting = false
		return
	var gp: Vector3 = _ground_hit["position"]
	var h := global_position.y - gp.y
	var strength := clampf(1.0 - (h - 6.0) / 20.0, 0.0, 1.0) * _rotor_speed
	var col: Object = _ground_hit.get("collider")
	var water := col is Node and str((col as Node).get_meta("surface", "")) == "water"
	var active := _spray if water else _dust
	var other := _dust if water else _spray
	other.emitting = false
	active.emitting = strength > 0.05
	active.amount_ratio = strength
	active.global_position = gp + Vector3.UP * 0.3
