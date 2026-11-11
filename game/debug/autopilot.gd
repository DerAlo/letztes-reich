extends Node
## Autopilot-Bot: spielt ein Level automatisch durch und schreibt Telemetrie (telemetry/run_*.json).
## Aktiv mit --autopilot (wird vom DebugServer-Autoload hinzugefuegt). Besitzer: Test-Infra-Agent.
## Args: --skill=novice|average|veteran  --max-time=600 (Sim-Sekunden)  --max-deaths=N  --out=<datei>  --timescale=N

const SKILLS: Dictionary = {
	"novice": {
		"reaction": 0.45, "aim_sigma": 2.6, "turn_speed": 130.0, "inertia": 5.0, "cover": 0.2,
		"fire_cone": 6.0, "fire_range": 25.0, "burst": [0.5, 1.3], "pause": [0.3, 0.8], "fov": 60.0, "grenade": 0.3,
	},
	"average": {
		"reaction": 0.30, "aim_sigma": 1.5, "turn_speed": 220.0, "inertia": 9.0, "cover": 0.5,
		"fire_cone": 4.0, "fire_range": 35.0, "burst": [0.4, 1.0], "pause": [0.2, 0.5], "fov": 80.0, "grenade": 0.6,
	},
	"veteran": {
		"reaction": 0.20, "aim_sigma": 0.6, "turn_speed": 360.0, "inertia": 14.0, "cover": 0.8,
		"fire_cone": 2.5, "fire_range": 45.0, "burst": [0.3, 0.7], "pause": [0.1, 0.3], "fov": 100.0, "grenade": 0.9,
	},
}
const VIEW_RANGE: float = 60.0
const WP_RADIUS: float = 1.8
const STUCK_TIME: float = 5.0
const STUCK_DIST: float = 0.5

var _player: Node3D = null
var _level: Node = null
var _skill: String = "average"
var _prof: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _finished: bool = false
var _sim_time: float = 0.0
var _max_time: float = 600.0
var _max_deaths: int = 1000000
var _real_start_ms: int = 0
var _out_path: String = ""

# Route
var _waypoints: Array[Vector3] = []
var _end_pos: Vector3 = Vector3.ZERO
var _has_end: bool = false
var _wp_idx: int = 0
var _route_done_time: float = -1.0

# Wahrnehmung / Ziel
var _seen: Dictionary = {}  # instance_id -> {first, last}
var _vis: Array[Node3D] = []
var _target: Node3D = null
var _target_since: float = 0.0
var _target_hp0: float = 0.0
var _ignore_until: Dictionary = {}
var _vis_tick: int = 0
var _last_visible_time: float = -100.0
var _aim_cache: Dictionary = {}

# Zielen
var _look_vel: Vector2 = Vector2.ZERO
var _noise: Vector2 = Vector2.ZERO
var _noise_t: float = 0.0
var _fire_on_until: float = 0.0
var _fire_off_until: float = 0.0
var _reload_cd: float = 0.0
var _strafe_dir: float = 1.0
var _strafe_until: float = 0.0

# Deckung
var _cover_mode: bool = false
var _cover_pos: Vector3 = Vector3.ZERO
var _cover_since: float = 0.0
var _cover_decided_for: float = -100.0
var _no_cover_until: float = 0.0
var _force_advance_until: float = 0.0
var _last_progress_t: float = 0.0
var _stall_streak: int = 0
var _stall_wp: int = -1

# Granaten
var _gren_cd_until: float = 10.0
var _gren_state: bool = false
var _gren_point: Vector3 = Vector3.ZERO
var _gren_start: float = 0.0
var _gren_check_t: float = 0.0
var _last_grenades: int = -1

# Stuck
var _stuck_ref_pos: Vector3 = Vector3.ZERO
var _stuck_ref_t: float = 0.0
var _stuck_wanted_time: float = 0.0
var _unstick_until: float = 0.0
var _unstick_dir: float = 1.0
var _stuck_streak: int = 0
var _stuck_streak_wp: int = -1

# Schaden / Telemetrie
var _last_pos: Vector3 = Vector3.ZERO
var _last_damage_t: float = -100.0
var _last_damage_type: String = ""
var _alive: bool = true
var _result: String = ""
var _t_deaths: Array[Dictionary] = []
var _t_damage_taken: Dictionary = {}
var _t_kills: Dictionary = {}
var _t_shots: int = 0
var _t_hits: int = 0
var _t_expl_hits: int = 0
var _t_grenades: int = 0
var _t_grenade_attempts: int = 0
var _t_stuck: Array[Dictionary] = []
var _sections: Array[Dictionary] = []  # {id, start}
var _section_times: Dictionary = {}
var _section_deaths: Dictionary = {}
var _last_expl_frame: int = -100
var _fps_samples: Array[float] = []
var _fps_next_ms: int = 0
var _is_headless: bool = false
var _debug: bool = false


func _ready() -> void:
	_skill = str(Game.arg("skill", "average"))
	if not SKILLS.has(_skill):
		push_warning("Autopilot: unbekannter Skill '%s', nehme average" % _skill)
		_skill = "average"
	_prof = SKILLS[_skill]
	_max_time = float(Game.arg("max-time", 600.0))
	_max_deaths = int(Game.arg("max-deaths", 1000000))
	_out_path = str(Game.arg("out", ""))
	_rng.seed = int(Game.arg("seed", 0)) if Game.arg("seed", null) != null else Time.get_ticks_usec()
	_real_start_ms = Time.get_ticks_msec()
	_is_headless = DisplayServer.get_name() == "headless"
	_debug = Game.arg("ap-debug", false) != false
	_level = _find_level()
	_read_level_info()
	_sections.append({"id": "start", "start": 0.0})
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(_on_player_died)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.enemy_damaged.connect(_on_enemy_damaged)
	Events.explosion.connect(func(_p: Vector3, _r: float, _s: float) -> void: _last_expl_frame = Engine.get_physics_frames())
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.checkpoint_reached.connect(_on_checkpoint)
	Events.level_completed.connect(func() -> void: _finish("completed"))
	print("[autopilot] skill=%s max-time=%.0f waypoints=%d timescale=%.1f" % [_skill, _max_time, _waypoints.size(), Engine.time_scale])


func _find_level() -> Node:
	var root: Node = get_tree().current_scene
	if root == null:
		return null
	if root.has_method("get_level_info"):
		return root
	for c in root.get_children():
		if c.has_method("get_level_info"):
			return c
	return null


func _read_level_info() -> void:
	_waypoints.clear()
	if _level == null:
		return
	var info: Dictionary = _level.get_level_info()
	for w in info.get("waypoints", []):
		if w is Array and (w as Array).size() >= 3:
			_waypoints.append(Vector3(float(w[0]), float(w[1]), float(w[2])))
	var ep: Variant = info.get("end_position", null)
	if ep is Array and (ep as Array).size() >= 3:
		_end_pos = Vector3(float(ep[0]), float(ep[1]), float(ep[2]))
		_has_end = true
	if _waypoints.is_empty() and _has_end:
		_waypoints.append(_end_pos)


# --------------------------------------------------------------------------- Hauptschleife

func _process(_delta: float) -> void:
	if _finished or _is_headless:
		return
	var now: int = Time.get_ticks_msec()
	if now >= _fps_next_ms:
		_fps_next_ms = now + 500
		_fps_samples.append(float(Engine.get_frames_per_second()))


func _physics_process(delta: float) -> void:
	if _finished:
		return
	_sim_time += delta
	if _sim_time >= _max_time:
		_finish("timeout")
		return
	if _player == null or not is_instance_valid(_player):
		_player = Game.get_player() as Node3D
		if _player == null:
			return
	# Level-Hook (Runde 5): Spieler-Modi mit eigenem Bot (z. B. Gunship) steuern sich selbst;
	# der Autopilot zaehlt dann nur Zeit/Telemetrie.
	if _player.has_method("autopilot_self_driven") and bool(_player.call("autopilot_self_driven")):
		_last_pos = _player.global_position
		return
	if _level == null or not is_instance_valid(_level):
		_level = _find_level()
		_read_level_info()
	var ext_v: Variant = _player.get("ext")
	if not (ext_v is Dictionary):
		push_error("Autopilot: Player hat kein ext")
		_finish("error")
		return
	var ext: Dictionary = ext_v
	_player.set("external_input", true)
	var st: Dictionary = _player.get_status()
	_alive = bool(st.get("alive", true))
	if not _alive:
		_set_neutral(ext)
		return
	_last_pos = _player.global_position
	var grenades: int = int(st.get("grenades", 0))
	if _last_grenades >= 0 and grenades < _last_grenades:
		_t_grenades += _last_grenades - grenades
	_last_grenades = grenades

	var cam: Camera3D = _get_cam()
	if cam == null:
		return
	var health: float = float(st.get("health", 100.0))
	var max_health: float = float(st.get("max_health", 100.0))
	var ammo: int = int(st.get("ammo_mag", 30))
	var reloading: bool = bool(st.get("reloading", false))

	_update_perception(cam)
	_pick_target()
	_update_noise(delta)

	# ---- Zustand: Deckung
	var under_fire: bool = _sim_time - _last_damage_t < 2.0
	var can_cover: bool = _sim_time >= _no_cover_until
	if can_cover and _target != null and not _cover_mode and _sim_time - _cover_decided_for > 6.0:
		_cover_decided_for = _sim_time
		if _rng.randf() < float(_prof["cover"]):
			_enter_cover()
	if can_cover and not _cover_mode and health < max_health * 0.45 and (_target != null or under_fire):
		_enter_cover()
	if _cover_mode:
		var recovered: bool = health >= max_health * 0.85
		var in_cover_t: float = _sim_time - _cover_since
		if (_target == null and not under_fire and recovered and in_cover_t > 1.5) or in_cover_t > 20.0 or (_target == null and in_cover_t > 8.0):
			_cover_mode = false
			_no_cover_until = _sim_time + 8.0
	_check_progress()
	if _finished:
		return

	# ---- Bewegung
	var move_world: Vector3 = Vector3.ZERO
	var wants_move: bool = false
	var sprint: bool = false
	var crouch: bool = false
	var target_dist: float = 0.0
	if _target != null:
		target_dist = (_target.global_position - cam.global_position).length()

	if _gren_state:
		pass  # Granatenwurf: stehen bleiben
	elif _cover_mode:
		var to_cover: Vector3 = _cover_pos - _player.global_position
		to_cover.y = 0.0
		if to_cover.length() > 0.9:
			move_world = to_cover.normalized()
			wants_move = true
			sprint = to_cover.length() > 4.0
		else:
			crouch = under_fire or health < max_health * 0.7
	elif _target != null and target_dist < float(_prof["fire_range"]) and _sim_time >= _force_advance_until:
		# stehen und schiessen; Veteranen strafen leicht
		if _prof["cover"] >= 0.8 and target_dist > 8.0 and under_fire:
			if _sim_time > _strafe_until:
				_strafe_until = _sim_time + _rng.randf_range(0.6, 1.4)
				_strafe_dir = -_strafe_dir
			var r: Vector3 = cam.global_transform.basis.x
			r.y = 0.0
			move_world = r.normalized() * _strafe_dir * 0.6
	else:
		var wp: Vector3 = _current_waypoint()
		var to_wp: Vector3 = wp - _player.global_position
		var flat: Vector3 = Vector3(to_wp.x, 0.0, to_wp.z)
		var at_end: bool = _wp_idx >= _waypoints.size()
		if at_end and _route_done_time < 0.0:
			_route_done_time = _sim_time
		if not at_end and flat.length() < WP_RADIUS and absf(to_wp.y) < 3.0:
			_advance_waypoint()
		elif at_end and flat.length() < 0.4:
			pass  # am Ende angekommen, auf level_completed warten
		else:
			move_world = flat.normalized()
			wants_move = true
			sprint = _vis.is_empty() and flat.length() > 6.0 and _skill != "novice"

	# Entstecken
	if _sim_time < _unstick_until:
		var r2: Vector3 = cam.global_transform.basis.x
		r2.y = 0.0
		move_world = (move_world + r2.normalized() * _unstick_dir * 1.2).limit_length(1.0)
		if _rng.randf() < 0.02:
			ext["jump"] = true
		wants_move = true
	_check_stuck(wants_move, delta)
	if _finished:
		return
	if _debug and int(_sim_time * 2.0) != int((_sim_time - delta) * 2.0):
		print("[ap] t=%.1f pos=%s wp=%d wants=%s cover=%s target=%s unstick=%s" % [_sim_time, str(_player.global_position), _wp_idx, str(wants_move), str(_cover_mode), str(_target), str(_sim_time < _unstick_until)])

	# Weltvektor -> lokale Eingabe ueber die Kamera-Ausrichtung
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var mv: Vector2 = Vector2(move_world.dot(right), move_world.dot(fwd)).limit_length(1.0)

	# ---- Zielen
	var aim_point: Vector3 = Vector3.ZERO
	var have_aim: bool = false
	var combat_aim: bool = false
	if _gren_state:
		aim_point = _gren_point
		have_aim = true
		combat_aim = true
	elif _target != null:
		aim_point = _aim_point_of(_target)
		have_aim = true
		combat_aim = true
	elif under_fire and _sim_time - _last_visible_time > 0.3:
		var near: Node3D = _nearest_enemy(35.0)
		if near != null:
			aim_point = _aim_point_of(near)
			have_aim = true
			combat_aim = true
	if not have_aim:
		if wants_move and not _cover_mode and _wp_idx < _waypoints.size() + 1:
			var wp2: Vector3 = _current_waypoint()
			aim_point = Vector3(wp2.x, cam.global_position.y, wp2.z)
		else:
			aim_point = cam.global_position + fwd * 10.0
		have_aim = true
	var angs: Vector2 = _angles_to(cam, aim_point)  # x = yaw rechts+, y = pitch hoch+
	var true_err: float = angs.length()
	var sigma_scale: float = 1.0 + mv.length() * 0.6
	var err: Vector2 = angs
	if combat_aim:
		err += _noise * sigma_scale
	var max_speed: float = float(_prof["turn_speed"]) * (1.0 if combat_aim else 0.6)
	var desired: Vector2 = (err * 8.0).limit_length(max_speed)
	_look_vel = _look_vel.lerp(desired, 1.0 - exp(-float(_prof["inertia"]) * delta))
	ext["look"] = _look_vel

	# ---- Feuern
	var fire: bool = false
	var aim_btn: bool = false
	if _target != null and not _gren_state and not reloading and ammo > 0:
		var cone: float = minf(float(_prof["fire_cone"]), maxf(0.35, 1.3 * rad_to_deg(atan(0.45 / maxf(target_dist, 1.0)))))
		if true_err < cone and target_dist < float(_prof["fire_range"]):
			if _sim_time >= _fire_off_until:
				if _fire_on_until < _sim_time:
					var b: Array = _prof["burst"]
					_fire_on_until = _sim_time + _rng.randf_range(float(b[0]), float(b[1]))
				fire = true
				if _sim_time >= _fire_on_until:
					var p: Array = _prof["pause"]
					_fire_off_until = _sim_time + _rng.randf_range(float(p[0]), float(p[1]))
					_fire_on_until = 0.0
					fire = false
		aim_btn = target_dist > 25.0 and _skill != "novice" and true_err < cone * 2.0

	# ---- Nachladen
	_reload_cd -= delta
	if not reloading and _reload_cd <= 0.0:
		if ammo <= 0 or (ammo < 8 and _target == null):
			ext["reload"] = true
			_reload_cd = 0.8

	# ---- Granaten
	_update_grenade(ext, grenades, true_err, cam)

	if _debug and _target != null and int(_sim_time * 6.0) != int((_sim_time - delta) * 6.0):
		print("[ap] t=%.1f dist=%.1f err=%.2f yaw=%.2f pit=%.2f cone=%s fire=%s vel=%s ammo=%d" % [_sim_time, target_dist, true_err, angs.x, angs.y, str(_prof["fire_cone"]), str(fire), str(_look_vel), ammo])
	ext["move"] = mv
	ext["fire"] = fire
	ext["aim"] = aim_btn
	ext["sprint"] = sprint and mv.y > 0.5 and not fire
	ext["crouch"] = crouch


func _set_neutral(ext: Dictionary) -> void:
	ext["move"] = Vector2.ZERO
	ext["look"] = Vector2.ZERO
	ext["fire"] = false
	ext["aim"] = false
	ext["sprint"] = false
	ext["crouch"] = false
	_look_vel = Vector2.ZERO


# --------------------------------------------------------------------------- Route / Stuck

func _current_waypoint() -> Vector3:
	if _wp_idx < _waypoints.size():
		return _waypoints[_wp_idx]
	if _has_end:
		return _end_pos
	return _last_pos


func _advance_waypoint() -> void:
	_wp_idx += 1
	_last_progress_t = _sim_time
	_stuck_streak = 0
	if _wp_idx >= _waypoints.size() and _route_done_time < 0.0:
		_route_done_time = _sim_time


## Fortschritts-Watchdog: weder Wegpunkt noch Kill seit 45 s (z.B. Deckungs-Pendeln, unerreichbarer Gegner).
func _check_progress() -> void:
	if _sim_time - _last_progress_t < 45.0:
		return
	_last_progress_t = _sim_time
	var ev: Dictionary = {
		"time": snappedf(_sim_time, 0.1), "pos": _arr(_player.global_position),
		"waypoint": _wp_idx, "section": _section_id(), "kind": "stall",
	}
	_t_stuck.append(ev)
	print("[autopilot] STALL (kein Fortschritt) bei %s (wp %d, t=%.1f)" % [str(_player.global_position), _wp_idx, _sim_time])
	if _stall_wp == _wp_idx:
		_stall_streak += 1
	else:
		_stall_wp = _wp_idx
		_stall_streak = 1
	if _stall_streak >= 4:
		_finish("stuck")
		return
	_cover_mode = false
	_no_cover_until = _sim_time + 30.0
	_force_advance_until = _sim_time + 12.0
	_target = null
	if _stall_streak >= 2 and _wp_idx < _waypoints.size():
		_wp_idx += 1


func _check_stuck(wants_move: bool, delta: float) -> void:
	if _route_done_time >= 0.0 and _boss_alive():
		_route_done_time = _sim_time   # Level-Ende wartet auf den Boss: Zeitfenster laeuft erst danach
	if _route_done_time >= 0.0 and _sim_time - _route_done_time > 40.0:
		_finish("stuck")  # Ende nicht erreicht
		return
	if _sim_time - _stuck_ref_t >= STUCK_TIME:
		var moved: float = (_player.global_position - _stuck_ref_pos).length()
		var wanted_frac: float = _stuck_wanted_time / maxf(0.01, _sim_time - _stuck_ref_t)
		if _debug:
			print("[ap] stuckwin moved=%.2f wanted=%.2f" % [moved, wanted_frac])
		if moved < STUCK_DIST and wanted_frac > 0.8:
			var ev: Dictionary = {
				"time": snappedf(_sim_time, 0.1), "pos": _arr(_player.global_position),
				"waypoint": _wp_idx, "section": _section_id(),
			}
			_t_stuck.append(ev)
			print("[autopilot] STUCK bei %s (wp %d, t=%.1f)" % [str(_player.global_position), _wp_idx, _sim_time])
			if _stuck_streak_wp == _wp_idx:
				_stuck_streak += 1
			else:
				_stuck_streak_wp = _wp_idx
				_stuck_streak = 1
			if _stuck_streak >= 4:
				_finish("stuck")
				return
			if _stuck_streak >= 2 and _wp_idx < _waypoints.size():
				_wp_idx += 1  # Wegpunkt ueberspringen
			_unstick_until = _sim_time + 1.5
			_unstick_dir = 1.0 if _rng.randf() < 0.5 else -1.0
		_stuck_ref_pos = _player.global_position
		_stuck_ref_t = _sim_time
		_stuck_wanted_time = 0.0
	elif wants_move:
		_stuck_wanted_time += delta


func _boss_alive() -> bool:
	for b in get_tree().get_nodes_in_group("boss"):
		if b.has_method("is_alive") and bool(b.call("is_alive")) and bool(b.get("boss_engaged")):
			return true
	return false


# --------------------------------------------------------------------------- Wahrnehmung / Ziel

func _get_cam() -> Camera3D:
	if _player != null and _player.has_method("get_camera"):
		var c: Variant = _player.get_camera()
		if c is Camera3D:
			return c
	return get_viewport().get_camera_3d()


func _aim_point_of(e: Node3D) -> Vector3:
	if e.has_method("get_aim_point"):   # gepanzerte Gegner / Juggernaut: Schwachstelle statt Platte
		return e.call("get_aim_point")
	var id: int = e.get_instance_id()
	var shape: Node3D = null
	if _aim_cache.has(id) and is_instance_valid(_aim_cache[id]):
		shape = _aim_cache[id]
	else:
		shape = _find_shape(e)
		_aim_cache[id] = shape
	if shape != null:
		return shape.global_position
	return e.global_position + Vector3(0, 1.2, 0)


func _find_shape(n: Node) -> Node3D:
	for c in n.get_children():
		if c is CollisionShape3D:
			return c
	for c in n.get_children():
		var r: Node3D = _find_shape(c)
		if r != null:
			return r
	return null


func _angles_to(cam: Camera3D, point: Vector3) -> Vector2:
	var local: Vector3 = cam.global_transform.basis.inverse() * (point - cam.global_position)
	var yaw: float = rad_to_deg(atan2(local.x, -local.z))
	var pitch: float = rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length()))
	return Vector2(yaw, pitch)


func _los(from: Vector3, to: Vector3) -> bool:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	return get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty()


func _update_perception(cam: Camera3D) -> void:
	_vis_tick += 1
	if _vis_tick % 3 != 0:
		return
	_vis.clear()
	var fov: float = float(_prof["fov"])
	for e in get_tree().get_nodes_in_group("enemy"):
		var n3: Node3D = e as Node3D
		if n3 == null or (e.has_method("is_alive") and not e.is_alive()):
			continue
		var ap: Vector3 = _aim_point_of(n3)
		var to: Vector3 = ap - cam.global_position
		if to.length() > VIEW_RANGE:
			continue
		var a: Vector2 = _angles_to(cam, ap)
		if absf(a.x) > fov and not (_sim_time - _last_damage_t < 2.0):
			continue
		if not _los(cam.global_position, ap):
			continue
		_vis.append(n3)
		var id: int = n3.get_instance_id()
		if not _seen.has(id) or _sim_time - float(_seen[id]["last"]) > 0.8:
			_seen[id] = {"first": _sim_time, "last": _sim_time}
		else:
			_seen[id]["last"] = _sim_time
	if not _vis.is_empty():
		_last_visible_time = _sim_time


func _pick_target() -> void:
	var react: float = float(_prof["reaction"])
	var best: Node3D = null
	var best_d: float = 1e9
	for e in _vis:
		var id: int = e.get_instance_id()
		if float(_ignore_until.get(id, 0.0)) > _sim_time:
			continue
		if _sim_time - float(_seen[id]["first"]) < react:
			continue
		var d: float = (e.global_position - _player.global_position).length()
		if e == _target:
			d *= 0.7  # Zielstabilitaet
		if d < best_d:
			best_d = d
			best = e
	if best != _target:
		_target = best
		_target_since = _sim_time
		if _target != null:
			_target_hp0 = _hp_of(_target)
	elif _target != null and _sim_time - _target_since > 12.0:
		# Ziel laesst sich nicht besiegen -> kurz ignorieren
		if _hp_of(_target) >= _target_hp0 - 0.1:
			_ignore_until[_target.get_instance_id()] = _sim_time + 10.0
			_target = null
		else:
			_target_since = _sim_time
			_target_hp0 = _hp_of(_target)


func _hp_of(e: Node) -> float:
	if e.has_method("get_status"):
		return float(e.get_status().get("health", 0.0))
	return 0.0


func _nearest_enemy(max_d: float) -> Node3D:
	var best: Node3D = null
	var bd: float = max_d
	for e in get_tree().get_nodes_in_group("enemy"):
		var n3: Node3D = e as Node3D
		if n3 == null or (e.has_method("is_alive") and not e.is_alive()):
			continue
		var d: float = (n3.global_position - _player.global_position).length()
		if d < bd:
			bd = d
			best = n3
	return best


func _update_noise(delta: float) -> void:
	_noise_t -= delta
	if _noise_t <= 0.0:
		_noise_t = _rng.randf_range(0.25, 0.6)
		var s: float = float(_prof["aim_sigma"])
		_noise = Vector2(_rng.randfn(0.0, s), _rng.randfn(0.0, s * 0.7))


func _enter_cover() -> void:
	var best: Vector3 = Vector3.ZERO
	var bd: float = 15.0
	var found: bool = false
	for c in get_tree().get_nodes_in_group("cover_point"):
		var n3: Node3D = c as Node3D
		if n3 == null:
			continue
		var d: float = (n3.global_position - _player.global_position).length()
		if d < bd and d > 0.5:
			bd = d
			best = n3.global_position
			found = true
	if found:
		_cover_mode = true
		_cover_pos = best
		_cover_since = _sim_time


# --------------------------------------------------------------------------- Granaten

func _update_grenade(ext: Dictionary, grenades: int, true_err: float, cam: Camera3D) -> void:
	if _gren_state:
		if true_err < 4.0 or _sim_time - _gren_start > 1.2:
			ext["grenade"] = true
			_t_grenade_attempts += 1
			_gren_state = false
			_gren_cd_until = _sim_time + 10.0
		return
	if grenades <= 0 or _sim_time < _gren_cd_until or _sim_time < _gren_check_t:
		return
	_gren_check_t = _sim_time + 0.5
	var pts: Array[Vector3] = []
	for e in _vis:
		if _sim_time - float(_seen[e.get_instance_id()]["first"]) >= float(_prof["reaction"]):
			pts.append(e.global_position)
	if pts.size() < 3:
		return
	var best_n: int = 0
	var best_c: Vector3 = Vector3.ZERO
	for p in pts:
		var group: Array[Vector3] = []
		for q in pts:
			if p.distance_to(q) < 7.0:
				group.append(q)
		if group.size() > best_n:
			best_n = group.size()
			var c: Vector3 = Vector3.ZERO
			for g in group:
				c += g
			best_c = c / float(group.size())
	if best_n < 3:
		return
	var dist: float = best_c.distance_to(_player.global_position)
	if dist < 9.0 or dist > 28.0:
		return
	if _rng.randf() > float(_prof["grenade"]):
		_gren_cd_until = _sim_time + 4.0
		return
	_gren_state = true
	_gren_start = _sim_time
	_gren_point = best_c + Vector3.UP * (1.0 + dist * 0.18)  # Wurfbogen: etwas ueber das Ziel zielen


# --------------------------------------------------------------------------- Events / Telemetrie

func _type_of(n: Node) -> String:
	if n == null or not is_instance_valid(n):
		return "environment"
	if n.is_in_group("player"):
		return "self"
	if n.has_method("get_status"):
		var st: Variant = n.get_status()
		if st is Dictionary and (st as Dictionary).has("type"):
			return str((st as Dictionary)["type"])
	if n.has_meta("enemy_type"):
		return str(n.get_meta("enemy_type"))
	return String(n.name)


func _section_id() -> String:
	return str(_sections[_sections.size() - 1]["id"])


func _on_player_damaged(amount: float, source: Node) -> void:
	var t: String = _type_of(source)
	_t_damage_taken[t] = snappedf(float(_t_damage_taken.get(t, 0.0)) + amount, 0.1)
	_last_damage_t = _sim_time
	_last_damage_type = t


func _on_player_died() -> void:
	if _finished:
		return
	var cause: String = _last_damage_type if _sim_time - _last_damage_t < 6.0 else "unknown"
	var sec: String = _section_id()
	_t_deaths.append({
		"time": snappedf(_sim_time, 0.1), "pos": _arr(_last_pos), "cause": cause, "section": sec,
	})
	_section_deaths[sec] = int(_section_deaths.get(sec, 0)) + 1
	print("[autopilot] TOT #%d bei %s (%s, t=%.1f)" % [_t_deaths.size(), str(_last_pos), cause, _sim_time])
	_cover_mode = false
	_gren_state = false
	_target = null
	if _t_deaths.size() >= _max_deaths:
		_finish("max_deaths")


func _on_enemy_killed(enemy: Node) -> void:
	_last_progress_t = _sim_time
	var t: String = _type_of(enemy)
	_t_kills[t] = int(_t_kills.get(t, 0)) + 1


func _on_enemy_damaged(_enemy: Node, _amount: float) -> void:
	if _enemy != null and is_instance_valid(_enemy) and _enemy.is_in_group("boss"):
		_last_progress_t = _sim_time   # Bosskampf zaehlt als Fortschritt (viele Treffer bis zum Kill)
	if absi(Engine.get_physics_frames() - _last_expl_frame) <= 1:
		_t_expl_hits += 1
	else:
		_t_hits += 1


func _on_weapon_fired(w: Node) -> void:
	if w != null and is_instance_valid(w):
		if w.is_in_group("enemy") or (w.get_parent() != null and w.get_parent().is_in_group("enemy")):
			return
	_t_shots += 1


func _on_checkpoint(id: String) -> void:
	var cur: Dictionary = _sections[_sections.size() - 1]
	_section_times[cur["id"]] = snappedf(float(_section_times.get(cur["id"], 0.0)) + _sim_time - float(cur["start"]), 0.1)
	_sections.append({"id": id, "start": _sim_time})
	print("[autopilot] Checkpoint %s bei t=%.1f" % [id, _sim_time])


func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


func _finish(result: String) -> void:
	if _finished:
		return
	_finished = true
	_result = result
	var cur: Dictionary = _sections[_sections.size() - 1]
	_section_times[cur["id"]] = snappedf(float(_section_times.get(cur["id"], 0.0)) + _sim_time - float(cur["start"]), 0.1)
	var fps: Variant = null
	if not _fps_samples.is_empty():
		var mn: float = 1e9
		var sm: float = 0.0
		for f in _fps_samples:
			mn = minf(mn, f)
			sm += f
		fps = {"min": snappedf(mn, 0.1), "avg": snappedf(sm / float(_fps_samples.size()), 0.1)}
	var tot_dmg: float = 0.0
	for k in _t_damage_taken:
		tot_dmg += float(_t_damage_taken[k])
	var data: Dictionary = {
		"skill": _skill,
		"result": result,
		"duration_sim": snappedf(_sim_time, 0.1),
		"duration_real": snappedf(float(Time.get_ticks_msec() - _real_start_ms) / 1000.0, 0.1),
		"timescale": Engine.time_scale,
		"level": str(Game.arg("level", "test_range")),
		"deaths": _t_deaths,
		"death_count": _t_deaths.size(),
		"damage_taken_by_type": _t_damage_taken,
		"damage_taken_total": snappedf(tot_dmg, 0.1),
		"kills_by_type": _t_kills,
		"shots": _t_shots,
		"hits": _t_hits,
		"explosion_hits": _t_expl_hits,
		"accuracy": snappedf(minf(1.0, float(_t_hits) / float(maxi(1, _t_shots))), 0.001),
		"grenades_thrown": maxi(_t_grenades, 0),
		"grenade_attempts": _t_grenade_attempts,
		"stuck_events": _t_stuck,
		"section_times": _section_times,
		"section_deaths": _section_deaths,
		"fps": fps,
		"final_position": _arr(_last_pos),
		"waypoint_index": _wp_idx,
		"waypoint_count": _waypoints.size(),
	}
	var path: String = _resolve_out_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Autopilot: kann Telemetrie nicht schreiben: " + path)
	else:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
	print("[autopilot] FERTIG result=%s deaths=%d sim=%.1fs telemetry=%s" % [result, _t_deaths.size(), _sim_time, path])
	get_tree().quit()


func _resolve_out_path() -> String:
	if _out_path != "":
		if _out_path.is_absolute_path():
			return _out_path
		return ProjectSettings.globalize_path("res://").path_join(_out_path)
	var dt: Dictionary = Time.get_datetime_dict_from_system()
	var ts: String = "%04d%02d%02d_%02d%02d%02d" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"]]
	var dir: String = ProjectSettings.globalize_path("res://telemetry")
	var base: String = dir.path_join("run_%s_%s" % [ts, _skill])
	var p: String = base + ".json"
	var n: int = 1
	while FileAccess.file_exists(p):
		p = "%s_%d.json" % [base, n]
		n += 1
	return p
