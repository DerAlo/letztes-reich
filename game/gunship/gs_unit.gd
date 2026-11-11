extends Node3D
## Leichte Einheit der Gunship-Mission (kein Physik-Koerper): Infanterie, Fahrzeuge, Flak, SAM, Radar,
## Jets, Tanks des Tanklagers und der eigene Trupp (IR-Blinker). Getroffen wird ueber Abstand zur Detonation
## (GSWorld.blast). Die Welt ruft tick() auf; Schuesse sind reine Optik + "Druck" auf den Trupp.

const GSModels := preload("res://game/gunship/gs_models.gd")
const GSMesh := preload("res://game/gunship/gs_mesh.gd")

const HP := {"inf": 60.0, "team": 100.0, "jeep": 120.0, "truck": 160.0, "team_truck": 9999.0, "bowser": 120.0,
	"apc": 450.0, "tank": 900.0, "flak": 140.0, "sam": 260.0, "radar": 200.0, "jet": 220.0, "fuel": 400.0}
## Panzerung: Schadens-Multiplikator je Waffe [25, 40, 105]
const ARMOR := {"inf": [1.0, 1.0, 1.0], "team": [1.0, 1.0, 1.0], "jeep": [0.6, 1.0, 1.0], "truck": [0.45, 1.0, 1.0],
	"bowser": [0.6, 1.0, 1.0], "apc": [0.07, 0.45, 1.0], "tank": [0.03, 0.22, 1.0], "flak": [0.55, 1.0, 1.0],
	"sam": [0.35, 0.8, 1.0], "radar": [0.4, 0.9, 1.0], "jet": [0.5, 1.0, 1.0], "fuel": [0.12, 0.5, 1.0],
	"team_truck": [0.0, 0.0, 0.0]}
## Trefferkugel: [radius, mittelhoehe]
const HITBOX := {"inf": [0.6, 0.9], "team": [0.6, 0.9], "jeep": [2.0, 1.0], "truck": [2.8, 1.4], "team_truck": [2.8, 1.4],
	"bowser": [2.8, 1.4], "apc": [3.2, 1.3], "tank": [3.6, 1.3], "flak": [2.2, 0.8], "sam": [3.6, 1.5],
	"radar": [3.4, 1.6], "jet": [6.0, 1.8], "fuel": [11.5, 6.0]}
const SPEED := {"inf": 3.2, "team": 3.6, "jeep": 13.0, "truck": 10.0, "team_truck": 9.0, "bowser": 7.0,
	"apc": 8.0, "tank": 6.0, "jet": 9.0}

var kind: String = "inf"
var side: String = "reich"          # "reich" | "team"
var callsign: String = ""
var hp: float = 60.0
var max_hp: float = 60.0
var alive: bool = true
var phase: int = 0
var required: bool = true            # zaehlt fuer das Phasenziel
var engage_range: float = 160.0
var hit_r: float = 0.6
var hit_h: float = 0.9
var speed: float = 3.2
var path: PackedVector3Array = PackedVector3Array()
var path_i: int = 0
var state: String = "idle"           # idle | move | engage | panic | ride | dead
var hidden_in: Node3D = null         # Team: sitzt im Fahrzeug
var formation: Vector3 = Vector3.ZERO
var escaped: bool = false
var hold_fire: bool = false          # Team: kein Feuer (z. B. am Mast beschaeftigt)
var flak_active: bool = false
var taxiing: bool = false

var mi: MeshInstance3D
var dish: MeshInstance3D = null
var _frames: Array[ArrayMesh] = []
var _aim_mesh: ArrayMesh = null
var _anim_t: float = 0.0
var _anim_i: int = 0
var _fire_cd: float = 0.0
var _burst: int = 0
var _panic_t: float = 0.0
var _panic_dir: Vector3 = Vector3.ZERO
var _dead_t: float = 0.0
var _heat_add: float = 0.0
var _strobe_ph: float = 0.0
var _yaw: float = 0.0
var _target: Node3D = null
var _retarget: float = 0.0
var _rng := RandomNumberGenerator.new()

func setup(p_kind: String, p_side: String, pos: Vector3, yaw: float, seed_v: int) -> void:
	kind = p_kind
	side = p_side
	_rng.seed = seed_v
	max_hp = float(HP.get(kind, 100.0))
	hp = max_hp
	var hb: Array = HITBOX.get(kind, [1.0, 1.0])
	hit_r = float(hb[0])
	hit_h = float(hb[1])
	speed = float(SPEED.get(kind, 0.0)) * _rng.randf_range(0.9, 1.1)
	position = pos
	_yaw = yaw
	rotation.y = yaw
	_strobe_ph = _rng.randf()
	_fire_cd = _rng.randf_range(0.5, 3.0)
	mi = MeshInstance3D.new()
	mi.material_override = GSMesh.mat("obj")
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	match kind:
		"inf":
			for k: String in ["inf_0", "inf_1", "inf_0", "inf_2"]:
				_frames.append(GSModels.get_mesh(k))
			_aim_mesh = GSModels.get_mesh("inf_aim")
			mi.mesh = _frames[0]
		"team":
			for k: String in ["team_0", "team_1", "team_0", "team_2"]:
				_frames.append(GSModels.get_mesh(k))
			_aim_mesh = GSModels.get_mesh("team_aim")
			mi.mesh = _frames[0]
		_:
			mi.mesh = GSModels.get_mesh(kind)
	if kind == "radar":
		dish = MeshInstance3D.new()
		dish.mesh = GSModels.get_mesh("radar_dish")
		dish.material_override = GSMesh.mat("obj")
		dish.position = Vector3(0, 3.05, 0)
		add_child(dish)
	if kind in ["inf", "team"]:
		scale = Vector3.ONE * _rng.randf_range(0.95, 1.06)
	mi.set_instance_shader_parameter("heat_add", 0.0)
	mi.set_instance_shader_parameter("heat_mul", 1.0)
	if side == "reich":
		add_to_group("gs_enemy")

func get_status() -> Dictionary:
	return {"type": kind, "alive": alive, "health": hp, "side": side}

func is_vehicle() -> bool:
	return kind in ["jeep", "truck", "team_truck", "bowser", "apc", "tank", "jet"]

func is_infantry() -> bool:
	return kind == "inf" or kind == "team"

func hit_center() -> Vector3:
	return global_position + Vector3(0, hit_h, 0)

func set_path(pts: Array, p_speed: float = -1.0) -> void:
	path = PackedVector3Array()
	for p in pts:
		path.append(p as Vector3)
	path_i = 0
	if p_speed > 0.0:
		speed = p_speed
	if not path.is_empty() and alive:
		state = "move"

func at_path_end() -> bool:
	return path_i >= path.size()

# ------------------------------------------------------------------ Schaden

## Gibt den tatsaechlichen Schaden zurueck (nach Panzerung).
func damage(amount: float, weapon: int) -> float:
	if not alive:
		return 0.0
	var arm: Array = ARMOR.get(kind, [1.0, 1.0, 1.0])
	var d := amount * float(arm[clampi(weapon, 0, 2)])
	if d <= 0.0:
		return 0.0
	hp -= d
	_heat_add = maxf(_heat_add, 0.25)
	return d

func suppress(from: Vector3, t: float) -> void:
	if not alive or not is_infantry() or state == "ride":
		return
	_panic_t = maxf(_panic_t, t)
	var away := global_position - from
	away.y = 0.0
	if away.length() < 0.1:
		away = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	_panic_dir = away.normalized().rotated(Vector3.UP, _rng.randf_range(-0.6, 0.6))

func kill(fx, blast_from: Vector3 = Vector3.INF) -> void:
	if not alive:
		return
	alive = false
	state = "dead"
	hp = 0.0
	_dead_t = 0.0
	if dish != null:
		dish.queue_free()
		dish = null
	match kind:
		"inf", "team":
			mi.mesh = GSModels.get_mesh("inf_dead")
			if blast_from != Vector3.INF:
				var away := global_position - blast_from
				away.y = 0.0
				if away.length() < 6.0:
					position += away.normalized() * _rng.randf_range(0.5, 2.5) if away.length() > 0.05 else Vector3.ZERO
			rotation = Vector3(0, _rng.randf() * TAU, 0)
			fx.glow(global_position + Vector3(0, 0.4, 0), 1.0, 1.4, 0.3)
		"jeep", "truck", "bowser":
			mi.mesh = GSModels.get_mesh("wreck_small" if kind == "jeep" else "wreck_big")
			fx.explosion(global_position, 2.0 if kind != "bowser" else 3.0)
			fx.fire(global_position + Vector3(0, 1.0, 0), 1.8 if kind != "bowser" else 3.5, 1.6, _rng.randf_range(60.0, 120.0))
		"apc", "tank":
			mi.mesh = GSModels.get_mesh("wreck_big")
			fx.explosion(global_position, 2.4)
			fx.fire(global_position + Vector3(0, 1.6, 0), 2.2, 1.7, _rng.randf_range(80.0, 160.0))
		"flak":
			mi.mesh = GSModels.get_mesh("wreck_flak")
			fx.explosion(global_position, 1.6)
			fx.fire(global_position + Vector3(0, 0.6, 0), 1.2, 1.5, 40.0)
		"sam", "radar":
			mi.mesh = GSModels.get_mesh("wreck_big")
			fx.explosion(global_position, 2.6)
			fx.fire(global_position + Vector3(0, 1.5, 0), 2.5, 1.7, 140.0)
		"jet":
			mi.mesh = GSModels.get_mesh("wreck_jet")
			fx.explosion(global_position, 3.0)
			fx.fire(global_position + Vector3(0, 1.2, 0), 3.5, 1.8, 200.0)
		"fuel":
			mi.mesh = GSModels.get_mesh("wreck_tank")
			fx.explosion(global_position + Vector3(0, 6, 0), 4.5)
			fx.explosion(global_position, 4.0, true)
			fx.fire(global_position + Vector3(0, 5.0, 0), 9.0, 1.9, -1.0)
	mi.set_instance_shader_parameter("heat_add", 0.0)

# ------------------------------------------------------------------ Ablauf

func tick(delta: float, w) -> void:
	if not alive:
		_dead_t += delta
		var hm := 1.0
		if is_infantry():
			hm = lerpf(1.0, 0.62, clampf(_dead_t / 90.0, 0.0, 1.0))
		elif kind != "fuel":
			hm = lerpf(1.0, 0.72, clampf(_dead_t / 150.0, 0.0, 1.0))
		mi.set_instance_shader_parameter("heat_mul", hm)
		return
	if _heat_add > 0.0:
		_heat_add = maxf(0.0, _heat_add - delta * 0.6)
		mi.set_instance_shader_parameter("heat_add", _heat_add)
	if state == "ride":
		if hidden_in != null and is_instance_valid(hidden_in):
			global_position = hidden_in.global_position
		return
	var moving := false
	if _panic_t > 0.0:
		_panic_t -= delta
		if is_infantry():
			_step(global_position + _panic_dir * 10.0, speed * 1.6, delta)
			moving = true
	elif state == "move" and not at_path_end():
		var tgt: Vector3 = path[path_i]
		if side == "team" and formation != Vector3.ZERO:
			tgt += formation
		var arrive := 1.2 if is_infantry() else 4.0
		var flat := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
		if flat.length() < arrive:
			path_i += 1
			if at_path_end():
				state = "engage"
		else:
			var sp := speed
			if is_vehicle() and path_i == path.size() - 1:
				sp = lerpf(2.0, speed, clampf(flat.length() / 25.0, 0.0, 1.0))
			_step(tgt, sp, delta)
			moving = true
	# Animation
	if is_infantry():
		if moving:
			_anim_t += delta * (speed / 3.2) * (1.6 if _panic_t > 0.0 else 1.0)
			if _anim_t > 0.2:
				_anim_t = 0.0
				_anim_i = (_anim_i + 1) % _frames.size()
				mi.mesh = _frames[_anim_i]
		elif mi.mesh != _aim_mesh and state == "engage":
			mi.mesh = _aim_mesh
		elif state != "engage" and mi.mesh != _frames[0]:
			mi.mesh = _frames[0]
	if dish != null:
		dish.rotation.y += delta * 1.6
	# IR-Blinker des Trupps
	if side == "team":
		var ph := fmod(w.time + _strobe_ph, 1.1)
		if ph < 0.09:
			var top := global_position + Vector3(0, 1.95 if kind == "team" else 3.0, 0)
			w.fx.glow(top, 2.2 if kind == "team" else 2.8, 3.2)
	# Abgas/Waerme
	if is_vehicle() and (moving or kind != "jet" or taxiing):
		var back := global_transform.basis.z
		if kind == "jet":
			if taxiing:
				w.fx.glow(global_position + Vector3(0, 1.9, 0) + back * 8.0, 2.4, 1.6)
		elif moving:
			w.fx.glow(global_position + Vector3(0, 0.9, 0) + back * 3.2, 1.0, 1.0, 0.0, Vector3.ZERO, 0.0, 0.0, 0.5)
	if _panic_t > 0.0 or hold_fire:
		return
	_combat(delta, w, moving)

func _step(tgt: Vector3, sp: float, delta: float) -> void:
	var to := Vector3(tgt.x - global_position.x, 0, tgt.z - global_position.z)
	var d := to.length()
	if d < 0.01:
		return
	var want := atan2(-to.x, -to.z)
	var turn := 6.0 if is_infantry() else (1.4 if kind != "jet" else 0.9)
	_yaw = rotate_toward(_yaw, want, turn * delta)
	rotation.y = _yaw
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var step := minf(sp * delta, d)
	if is_infantry():
		global_position += to.normalized() * step
	else:
		global_position += fwd * step * clampf(fwd.dot(to / d) * 1.2, 0.15, 1.0)

func _combat(delta: float, w, moving: bool) -> void:
	match kind:
		"flak":
			_flak_fire(delta, w)
			return
		"inf", "team", "jeep", "apc", "tank":
			pass
		_:
			return
	_retarget -= delta
	if _retarget <= 0.0 or _target == null or not is_instance_valid(_target) or not bool(_target.get("alive")):
		_retarget = _rng.randf_range(0.8, 1.6)
		_target = w.nearest_hostile(self, engage_range)
	if _target == null:
		return
	if is_infantry() and not moving:
		var to := _target.global_position - global_position
		_yaw = rotate_toward(_yaw, atan2(-to.x, -to.z), 5.0 * delta)
		rotation.y = _yaw
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var muzzle := global_position + Vector3(0, 1.4, 0)
	var dmg := 0.0
	match kind:
		"inf", "team":
			if moving and _rng.randf() < 0.6:
				_fire_cd = 0.4
				return
			if _burst <= 0:
				_burst = _rng.randi_range(2, 5)
			_burst -= 1
			_fire_cd = 0.11 if _burst > 0 else _rng.randf_range(1.2, 2.8)
			muzzle += global_transform.basis * Vector3(0.05, 0.05, -0.9)
			dmg = 9.0 if kind == "team" else 0.0
		"jeep":
			if _burst <= 0:
				_burst = 6
			_burst -= 1
			_fire_cd = 0.09 if _burst > 0 else _rng.randf_range(1.5, 2.5)
			muzzle = global_position + Vector3(0, 2.2, 0.4)
		"apc":
			if _burst <= 0:
				_burst = 5
			_burst -= 1
			_fire_cd = 0.16 if _burst > 0 else _rng.randf_range(1.4, 2.4)
			muzzle = global_position + global_transform.basis * Vector3(-0.2, 2.35, -2.4)
		"tank":
			_fire_cd = _rng.randf_range(5.5, 8.0)
			muzzle = global_position + global_transform.basis * Vector3(0, 2.1, -6.0)
	var tp: Vector3 = (_target as Node3D).global_position + Vector3(0, 1.0, 0)
	var miss := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-1, 1)) * (3.5 if side == "reich" else 1.5)
	var hitp := tp + miss
	var dir := (hitp - muzzle)
	var tracer_len := minf(dir.length(), 22.0 if kind != "tank" else 60.0)
	var t0 := _rng.randf_range(0.0, 0.5)
	var a := muzzle + dir * t0
	var b := a + dir.normalized() * tracer_len
	if (b - muzzle).length() > dir.length():
		b = hitp
	if kind == "tank":
		w.fx.glow(muzzle, 5.0, 2.6, 0.12)
		w.fx.streak(muzzle, hitp, 0.35, 1.8, 0.08)
		w.fx.explosion(hitp - Vector3(0, 1.0, 0), 0.8, false, true)
	else:
		w.fx.glow(muzzle, 0.9 if is_infantry() else 1.4, 2.2)
		w.fx.streak(a, b, 0.12 if is_infantry() else 0.2, 2.0, 0.07, 0.9, dir.normalized() * 300.0)
		if _rng.randf() < 0.25:
			w.fx.glow(hitp - Vector3(0, 1.0, 0), 0.5, 1.4, 0.15)
	if dmg > 0.0 and _rng.randf() < 0.35:
		w.team_hit(_target, dmg)

func _flak_fire(delta: float, w) -> void:
	if not flak_active:
		return
	_fire_cd -= delta
	var ap: Vector3 = w.aircraft_pos
	if _fire_cd > 0.0:
		return
	if _burst <= 0:
		_burst = _rng.randi_range(6, 12)
	_burst -= 1
	_fire_cd = 0.07 if _burst > 0 else _rng.randf_range(2.0, 4.5)
	_heat_add = minf(_heat_add + 0.05, 0.6)
	var muzzle := global_position + Vector3(0, 1.9, 0)
	# Vorhalt grob in Flugrichtung, Streuung gross: die Flak schiesst "in den Himmel"
	var tgt := ap + Vector3(_rng.randf_range(-90, 90), _rng.randf_range(-120, 60), _rng.randf_range(-90, 90))
	var dir := (tgt - muzzle).normalized()
	w.fx.glow(muzzle, 2.2, 2.6)
	var start := muzzle + dir * _rng.randf_range(4.0, 20.0)
	w.fx.streak(start, start + dir * 45.0, 0.35, 2.0, 0.55, 1.0, dir * 520.0)
	w.flak_shot(self)
