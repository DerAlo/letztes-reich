extends Node
## TCP-Fernsteuerung (127.0.0.1:9123). Nur aktiv mit User-Arg --debug-server. Besitzer: Test-Infra-Agent.
## Protokoll: pro Zeile ein JSON-Objekt {"cmd": "...", ...}, pro Zeile eine Antwort {"ok": true/false, ...}.
## Startet ausserdem (unabhaengig vom Server) den Autopilot (--autopilot) und setzt --timescale=N.

const PORT: int = 9123
const AUTOPILOT_SCRIPT: String = "res://game/debug/autopilot.gd"
const MAX_LOG: int = 400

class Conn extends RefCounted:
	var peer: StreamPeerTCP
	var buf: String = ""
	var queue: Array[String] = []
	var busy: bool = false

signal _step_finished

var _server: TCPServer = null
var _conns: Array[Conn] = []
var _enabled: bool = false
var _pause_mode: bool = false
var _step_active: bool = false
var _step_left: float = 0.0  # verbleibende Sim-Sekunden
var _game_time: float = 0.0
var _base_ticks: int = 60
var _quit_pending: bool = false
var _autopilot: Node = null
var _autopilot_wanted: bool = false
var _last_checkpoint: String = ""
var _level_completed: bool = false
var _last_expl_time: float = -100.0

# Event-Sammler (wird von "events" geleert)
var _log: Array[Dictionary] = []
var _stats: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 100000  # laeuft nach allen anderen Nodes im Tick
	_reset_stats()
	_base_ticks = Engine.physics_ticks_per_second
	var ts: float = float(Game.arg("timescale", 1.0))
	if ts != 1.0:
		_set_timescale(ts)
	_autopilot_wanted = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_enabled = str(Game.arg("debug-server", "")) not in ["", "false", "0"]
	if _enabled:
		_server = TCPServer.new()
		var err: int = _server.listen(PORT, "127.0.0.1")
		if err != OK:
			push_error("DebugServer: listen auf Port %d fehlgeschlagen (%d)" % [PORT, err])
			_enabled = false
		else:
			print("[DebugServer] lauscht auf 127.0.0.1:%d" % PORT)
		_connect_events()
		if Game.arg("start-paused", false) != false:
			_pause_mode = true
			get_tree().paused = true
	if not _enabled and not _autopilot_wanted:
		set_process(false)
		set_physics_process(false)


# --------------------------------------------------------------------------- Loop

func _process(_delta: float) -> void:
	if _autopilot_wanted and _autopilot == null:
		_try_start_autopilot()
	if not _enabled:
		return
	if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	while _server.is_connection_available():
		var c: Conn = Conn.new()
		c.peer = _server.take_connection()
		c.peer.set_no_delay(true)
		_conns.append(c)
	for c in _conns.duplicate():
		c.peer.poll()
		if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			if not c.busy:
				_conns.erase(c)
			continue
		var avail: int = c.peer.get_available_bytes()
		if avail > 0:
			var r: Array = c.peer.get_data(avail)
			if r[0] == OK:
				c.buf += (r[1] as PackedByteArray).get_string_from_utf8()
				while c.buf.contains("\n"):
					var idx: int = c.buf.find("\n")
					var line: String = c.buf.substr(0, idx).strip_edges()
					c.buf = c.buf.substr(idx + 1)
					if line != "":
						c.queue.append(line)
		if not c.busy and not c.queue.is_empty():
			_pump(c)


func _physics_process(delta: float) -> void:
	# delta ist bereits mit Engine.time_scale skaliert (Sim-Sekunden pro Tick)
	if not get_tree().paused:
		_game_time += delta
	if _step_active:
		_step_left -= delta
		if _step_left <= delta * 0.5:
			_step_active = false
			if _pause_mode:
				get_tree().paused = true
			_step_finished.emit()


func _exit_tree() -> void:
	if _server != null:
		_server.stop()


func _pump(c: Conn) -> void:
	c.busy = true
	while not c.queue.is_empty():
		var line: String = c.queue.pop_front()
		var resp: Dictionary = await _execute(line)
		_send(c, resp)
		if _quit_pending:
			get_tree().quit()
			return
	c.busy = false


func _send(c: Conn, resp: Dictionary) -> void:
	if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	c.peer.put_data((JSON.stringify(resp) + "\n").to_utf8_buffer())


func _err(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


# --------------------------------------------------------------------------- Befehle

func _execute(line: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(line)
	if not (parsed is Dictionary):
		return _err("ungueltiges JSON (Objekt erwartet)")
	var d: Dictionary = parsed
	var cmd: String = str(d.get("cmd", ""))
	match cmd:
		"ping":
			return {"ok": true, "pong": true}
		"status":
			return _cmd_status()
		"input":
			var e: String = _apply_input(d)
			return _err(e) if e != "" else {"ok": true}
		"hold":
			var e2: String = _apply_input(d)
			if e2 != "":
				return _err(e2)
			var dur: float = clampf(float(d.get("duration", 0.5)), 0.0, 600.0)
			if _step_active:
				return _err("step laeuft bereits")
			await _run_ticks(dur)
			_neutral_input()
			var s: Dictionary = _cmd_status()
			s["held"] = dur
			return s
		"look_at":
			var p: Node = Game.get_player()
			if p == null or not p.has_method("look_at_point"):
				return _err("kein Player")
			p.look_at_point(Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0))))
			return {"ok": true}
		"set_view":
			var p2: Node = Game.get_player()
			if p2 == null or not p2.has_method("set_view"):
				return _err("kein Player")
			p2.set_view(float(d.get("yaw", 0.0)), float(d.get("pitch", 0.0)))
			return {"ok": true}
		"step":
			if _step_active:
				return _err("step laeuft bereits")
			var secs: float = clampf(float(d.get("seconds", 0.5)), 0.0, 600.0)
			await _run_ticks(secs)
			var s2: Dictionary = _cmd_status()
			s2["stepped"] = secs
			return s2
		"pause":
			_pause_mode = true
			get_tree().paused = true
			return {"ok": true, "paused": true}
		"resume":
			_pause_mode = false
			get_tree().paused = false
			return {"ok": true, "paused": false}
		"screenshot":
			return await _cmd_screenshot(d)
		"enemies":
			return _cmd_enemies()
		"level_info":
			var lv: Node = _find_level()
			if lv == null:
				return _err("kein Level")
			return {"ok": true, "info": lv.get_level_info()}
		"timescale":
			_set_timescale(float(d.get("value", 1.0)))
			return {"ok": true, "timescale": Engine.time_scale}
		"spawn":
			return _cmd_spawn(d)
		"explode":
			var pos := Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
			Combat.explode(pos, float(d.get("radius", 6.0)))
			return {"ok": true}
		"teleport":
			var p3: Node3D = Game.get_player() as Node3D
			if p3 == null:
				return _err("kein Player")
			p3.global_position = Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
			if "velocity" in p3:
				p3.set("velocity", Vector3.ZERO)
			return {"ok": true}
		"events":
			return _cmd_events()
		"quit":
			_quit_pending = true
			return {"ok": true, "quit": true}
		_:
			return _err("unbekannter Befehl: '%s'" % cmd)


func _run_ticks(seconds: float) -> void:
	_step_left = maxf(seconds, 1.0 / float(_base_ticks))
	_step_active = true
	if _pause_mode:
		get_tree().paused = false
	await _step_finished


func _set_timescale(v: float) -> void:
	# Godot skaliert auch das Physics-Delta mit time_scale (delta = time_scale/ticks). Fuer stabile Physik
	# (dt = 1/60 Sim-Sekunden) werden bei Zeitraffer die Physics-Ticks mit hochgesetzt.
	v = clampf(v, 0.05, 64.0)
	Engine.time_scale = v
	Engine.physics_ticks_per_second = roundi(float(_base_ticks) * maxf(1.0, v))
	Engine.max_physics_steps_per_frame = maxi(8, ceili(8.0 * maxf(1.0, v)))


func _cmd_status() -> Dictionary:
	var p: Node = Game.get_player()
	var pst: Variant = null
	if p != null and p.has_method("get_status"):
		pst = p.get_status()
	var lv: Node = _find_level()
	return {
		"ok": true,
		"paused": get_tree().paused,
		"time": snappedf(_game_time, 0.01),
		"timescale": Engine.time_scale,
		"player": pst,
		"enemies_alive": _alive_enemy_count(),
		"level": lv.name if lv != null else null,
		"checkpoint": _last_checkpoint,
		"level_completed": _level_completed,
	}


func _alive_enemy_count() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not e.has_method("is_alive") or e.is_alive():
			n += 1
	return n


func _apply_input(d: Dictionary) -> String:
	var p: Node = Game.get_player()
	if p == null:
		return "kein Player"
	var ext_v: Variant = p.get("ext")
	if not (ext_v is Dictionary):
		return "Player hat kein 'ext'"
	var ext: Dictionary = ext_v
	p.set("external_input", true)
	for k in d:
		var key: String = str(k)
		match key:
			"move", "look":
				var a: Variant = d[k]
				if a is Array and (a as Array).size() >= 2:
					var v := Vector2(float(a[0]), float(a[1]))
					ext[key] = v.limit_length(1.0) if key == "move" else v
			"fire", "aim", "sprint", "crouch", "jump", "reload", "grenade", "prone", "interact":
				ext[key] = bool(d[k])
			"weapon":
				ext[key] = int(d[k])
	return ""


func _neutral_input() -> void:
	var p: Node = Game.get_player()
	if p == null:
		return
	var ext_v: Variant = p.get("ext")
	if ext_v is Dictionary:
		var ext: Dictionary = ext_v
		ext["move"] = Vector2.ZERO
		ext["look"] = Vector2.ZERO
		for k in ["fire", "aim", "sprint", "crouch"]:
			ext[k] = false


func _cmd_screenshot(d: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return _err("headless: kein Rendering, Screenshot nicht moeglich")
	var path: String = str(d.get("path", "captures/shot.png"))
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		path = ProjectSettings.globalize_path("res://").path_join(path)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		return _err("Viewport-Bild leer")
	var w: int = int(d.get("width", 0))
	if w > 0 and w < img.get_width():
		var h: int = int(round(float(img.get_height()) * float(w) / float(img.get_width())))
		img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err: int = img.save_png(path)
	if err != OK:
		return _err("save_png fehlgeschlagen (%d)" % err)
	return {"ok": true, "path": path, "size": [img.get_width(), img.get_height()]}


func _camera() -> Camera3D:
	var p: Node = Game.get_player()
	if p != null and p.has_method("get_camera"):
		var c: Variant = p.get_camera()
		if c is Camera3D:
			return c
	return get_viewport().get_camera_3d()


func _cmd_enemies() -> Dictionary:
	var cam: Camera3D = _camera()
	var out: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		var n3: Node3D = e as Node3D
		if n3 == null:
			continue
		if e.has_method("is_alive") and not e.is_alive():
			continue
		var st: Dictionary = {}
		if e.has_method("get_status"):
			st = e.get_status()
		var info: Dictionary = {
			"type": st.get("type", e.name), "health": st.get("health", null),
			"state": st.get("state", null), "pos": _v3(n3.global_position),
		}
		if cam != null:
			var to: Vector3 = n3.global_position + Vector3(0, 1.0, 0) - cam.global_position
			var local: Vector3 = cam.global_transform.basis.inverse() * to
			info["dist"] = snappedf(to.length(), 0.1)
			info["bearing"] = snappedf(rad_to_deg(atan2(local.x, -local.z)), 0.1)  # + = rechts
			info["elev"] = snappedf(rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length())), 0.1)
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, n3.global_position + Vector3(0, 1.0, 0), 1)
			info["visible"] = get_viewport().world_3d.direct_space_state.intersect_ray(q).is_empty()
		out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("dist", 1e9)) < float(b.get("dist", 1e9)))
	return {"ok": true, "enemies": out}


func _cmd_spawn(d: Dictionary) -> Dictionary:
	var t: String = str(d.get("type", "rifleman"))
	var path: String = "res://game/enemies/%s.tscn" % t
	if not ResourceLoader.exists(path):
		return _err("Szene fehlt: " + path)
	var scn: PackedScene = load(path)
	var inst: Node = scn.instantiate()
	var parent: Node = _find_level()
	if parent == null:
		parent = get_tree().current_scene
	if parent == null:
		inst.queue_free()
		return _err("kein Level")
	parent.add_child(inst)
	var n3: Node3D = inst as Node3D
	if n3 != null:
		n3.global_position = Vector3(float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0)))
	return {"ok": true, "spawned": t}


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


func _v3(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


# --------------------------------------------------------------------------- Events

func _reset_stats() -> void:
	_stats = {"shots": 0, "hits": 0, "damage_dealt": 0.0, "kills": {}, "damage_taken": {}}


func _connect_events() -> void:
	Events.player_damaged.connect(_on_player_damaged)
	Events.player_died.connect(func() -> void: _push({"e": "player_died", "pos": _player_pos()}))
	Events.player_respawned.connect(func() -> void: _push({"e": "player_respawned"}))
	Events.enemy_damaged.connect(_on_enemy_damaged)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.explosion.connect(func(pos: Vector3, radius: float, strength: float) -> void:
		_last_expl_time = _game_time
		_push({"e": "explosion", "pos": _v3(pos), "radius": snappedf(radius, 0.1), "strength": snappedf(strength, 0.1)}))
	Events.weapon_fired.connect(func(w: Node) -> void:
		if w != null and is_instance_valid(w) and (w.is_in_group("enemy") or (w.get_parent() != null and w.get_parent().is_in_group("enemy"))):
			return
		_stats["shots"] = int(_stats["shots"]) + 1)
	Events.checkpoint_reached.connect(func(id: String) -> void:
		_last_checkpoint = id
		_push({"e": "checkpoint", "id": id}))
	Events.level_completed.connect(func() -> void:
		_level_completed = true
		_push({"e": "level_completed"}))


func _push(ev: Dictionary) -> void:
	ev["t"] = snappedf(_game_time, 0.01)
	_log.append(ev)
	if _log.size() > MAX_LOG:
		_log.pop_front()


func _player_pos() -> Variant:
	var p: Node3D = Game.get_player() as Node3D
	return _v3(p.global_position) if p != null else null


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


func _on_player_damaged(amount: float, source: Node) -> void:
	var t: String = _type_of(source)
	var dt: Dictionary = _stats["damage_taken"]
	dt[t] = snappedf(float(dt.get(t, 0.0)) + amount, 0.1)


func _on_enemy_damaged(_enemy: Node, amount: float) -> void:
	if absf(_game_time - _last_expl_time) <= 0.05:
		return  # Explosionsschaden nicht als Treffer zaehlen
	_stats["hits"] = int(_stats["hits"]) + 1
	_stats["damage_dealt"] = snappedf(float(_stats["damage_dealt"]) + amount, 0.1)


func _on_enemy_killed(enemy: Node) -> void:
	var t: String = _type_of(enemy)
	var k: Dictionary = _stats["kills"]
	k[t] = int(k.get(t, 0)) + 1
	var pos: Variant = null
	if enemy is Node3D:
		pos = _v3((enemy as Node3D).global_position)
	_push({"e": "kill", "type": t, "pos": pos})


func _cmd_events() -> Dictionary:
	var out: Dictionary = {"ok": true, "events": _log.duplicate(), "summary": _stats.duplicate(true)}
	_log.clear()
	_reset_stats()
	return out


# --------------------------------------------------------------------------- Autopilot

func _try_start_autopilot() -> void:
	if Game.get_player() == null or _find_level() == null:
		return
	if not ResourceLoader.exists(AUTOPILOT_SCRIPT):
		push_error("Autopilot-Script fehlt")
		_autopilot_wanted = false
		return
	var scr: GDScript = load(AUTOPILOT_SCRIPT)
	_autopilot = scr.new()
	_autopilot.name = "Autopilot"
	_autopilot.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_autopilot)
	print("[DebugServer] Autopilot gestartet")
