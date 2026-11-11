extends Node
## Aufklaerungsdrohne (Quadkopter), wiederverwendbares Opt-in-System (zuerst Level "villa", spaeter Lena-Episode).
##
## Das Level erzeugt den Knoten, meldet Ziele an und startet den Flug:
##   var drone := ReconDrone.new(); add_child(drone)
##   drone.director = stealth_director          # optional: Watcher-Liste fuer den Rotorlaerm
##   drone.add_target(enemy, "guard", "Wache")  # Arten: guard, camera, jaeger, weber, person, object
##   drone.start(origin, yaw_deg)               # Spielerfigur wird eingefroren, Kamera wechselt
##   drone.finished.connect(func(reason): ...)  # "manual" | "battery" | "bot" | "menu" | "level"
## Begrenzte Reichweite (Signal) und Akku, umschaltbares Waermebild, Wind (Drift), Rotorlaerm macht Wachen
## misstrauisch (StealthBrain.hear_noise), markierte Ziele bleiben danach im HUD sichtbar (eigene Ebene).
##
## Steuerung im Flug: WASD fliegen, Maus schwenken, Leertaste/Strg(C) steigen/sinken, Shift schnell,
## Linksklick markieren, Rechtsklick Zoom, [T] Waermebild, [V] zurueckholen.
## Bot (--autopilot): autofly(punkte) fliegt die Punkte ab und markiert alles, was die Kamera erfasst.

signal launched
signal finished(reason: String)
signal target_marked(node: Node3D, kind: String)
signal noticed(watcher: Object)        ## eine Wache hat den Rotorlaerm gehoert
signal thermal_toggled(on: bool)

const ThermalShader = preload("res://game/systems/recon_drone_thermal.gdshader")

@export var max_range: float = 160.0          ## horizontale Funkreichweite ab Startpunkt (m)
@export var battery_seconds: float = 150.0    ## Flugzeit bei Normalflug
@export var cruise_speed: float = 9.0
@export var boost_speed: float = 15.0
@export var climb_speed: float = 5.0
@export var min_agl: float = 1.6              ## Mindesthoehe ueber Grund
@export var max_height: float = 55.0          ## max. Hoehe ueber dem Startpunkt
@export var noise_radius: float = 15.0        ## horizontaler Hoerradius der Wachen
@export var noise_agl: float = 17.0           ## darueber ist der Rotor unhoerbar
@export var wind_base: float = 1.8            ## m/s
@export var wind_gust: float = 2.4            ## m/s zusaetzlich in Boeen
@export var thermal_see_through: float = 85.0 ## Waermebild: Ziele bis hier auch hinter Laub/Daechern markierbar
@export var mark_range: float = 130.0
@export var pilot_label: String = "KERNER"
@export var feed_label: String = "AUFKLÄRUNGSDROHNE"

var director: Node
var active: bool = false
var thermal: bool = false
var battery: float = 1.0                      ## 0..1, bleibt zwischen Fluegen erhalten
var origin: Vector3 = Vector3.ZERO
var wind: Vector3 = Vector3.ZERO
var signal_strength: float = 1.0
var noise_level: float = 0.0                  ## 0..1 lautester Watcher (fuer HUD)
var targets: Array[Dictionary] = []           ## {"node", "kind", "label", "marked"}
var hovered: Dictionary = {}
var marks_visible: bool = true
var body: CharacterBody3D
var cam: Camera3D

var _bot: bool = false
var _yaw: float = 0.0
var _pitch: float = -0.35
var _vel: Vector3 = Vector3.ZERO
var _t: float = 0.0
var _rec_t: float = 0.0
var _wind_ang: float = 0.0
var _wind_target: float = 0.0
var _gust: float = 0.0
var _noise_acc: Dictionary = {}               ## watcher -> Zaehler
var _noise_cd: Dictionary = {}                ## watcher -> Sperrzeit
var _heat_t: float = 0.0
var _heat_nodes: Array[MeshInstance3D] = []
var _heat_mat: StandardMaterial3D
var _heat_mat_dev: StandardMaterial3D
var _thermal_env: Environment
var _thermal_attr: CameraAttributesPractical
var _fx_layer: CanvasLayer
var _fx_rect: ColorRect
var _fx_mat: ShaderMaterial
var _hud_layer: CanvasLayer
var _hud: Control
var _marks_layer: CanvasLayer
var _marks: Control
var _font: Font
var _hum: AudioStreamPlayer
var _hidden_layers: Array[CanvasLayer] = []
var _player_cam: Camera3D
var _auto_pts: Array = []
var _auto_i: int = 0
var _auto_dwell: float = 0.0
var _auto_wait: float = 0.0
var _auto_mark_t: float = 0.0
var _fov: float = 70.0
var _flash: Array[Dictionary] = []            ## kurze Einblendungen {"text", "t"}
var _ground_ray_t: float = 0.0
var _agl: float = 10.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	name = "ReconDrone"
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	InputConfig.ensure_actions()
	_rng.seed = 4242
	_font = ThemeDB.fallback_font
	_wind_ang = _rng.randf() * TAU
	_wind_target = _wind_ang
	_build_layers()
	_heat_mat = StandardMaterial3D.new()
	_heat_mat.albedo_color = Color(0, 0, 0)
	_heat_mat.emission_enabled = true
	_heat_mat.emission = Color(1, 1, 1)
	_heat_mat.emission_energy_multiplier = 4.0
	_heat_mat.roughness = 1.0
	_heat_mat_dev = _heat_mat.duplicate() as StandardMaterial3D
	_heat_mat_dev.emission_energy_multiplier = 1.1
	_thermal_env = Environment.new()
	_thermal_env.background_mode = Environment.BG_COLOR
	_thermal_env.background_color = Color(0.02, 0.02, 0.02)
	_thermal_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_thermal_env.ambient_light_color = Color(0.5, 0.5, 0.5)
	_thermal_env.ambient_light_energy = 0.55
	_thermal_env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_thermal_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_thermal_env.tonemap_exposure = 0.42
	_thermal_env.glow_enabled = true
	_thermal_env.glow_intensity = 0.5
	_thermal_env.glow_hdr_threshold = 1.2
	_thermal_attr = CameraAttributesPractical.new()
	_thermal_attr.auto_exposure_enabled = false

func _exit_tree() -> void:
	if active:
		_restore_player()
	_apply_heat(false)

# ------------------------------------------------------------------ Oeffentlich

## Ziel anmelden (Wache, Kamera, Person, Objekt). Markierte Ziele bleiben im HUD sichtbar.
func add_target(node: Node3D, kind: String, label: String = "") -> void:
	if node == null:
		return
	for t: Dictionary in targets:
		if t["node"] == node:
			return
	targets.append({"node": node, "kind": kind, "label": label if label != "" else _kind_label(kind), "marked": false})

func remove_target(node: Node3D) -> void:
	for i in range(targets.size() - 1, -1, -1):
		if targets[i]["node"] == node:
			targets.remove_at(i)

func is_marked(node: Node3D) -> bool:
	for t: Dictionary in targets:
		if t["node"] == node:
			return bool(t["marked"])
	return false

func mark(node: Node3D) -> bool:
	for t: Dictionary in targets:
		if t["node"] == node and not bool(t["marked"]):
			t["marked"] = true
			_sfx("drone_beep", -8.0, 1.25)
			_flash_text("MARKIERT: " + str(t["label"]).to_upper())
			target_marked.emit(node, str(t["kind"]))
			return true
	return false

## Anzahl markierter (und noch gueltiger) Ziele, optional nur einer Art.
func marked_count(kind: String = "") -> int:
	var n := 0
	for t: Dictionary in targets:
		if bool(t["marked"]) and _target_valid(t) and (kind == "" or t["kind"] == kind):
			n += 1
	return n

func target_count(kind: String = "") -> int:
	var n := 0
	for t: Dictionary in targets:
		if _target_valid(t) and (kind == "" or t["kind"] == kind):
			n += 1
	return n

func is_active() -> bool:
	return active

## Drohne am Startpunkt (Hand des Piloten) starten. yaw_deg: 0 = Blick nach -Z.
func start(at: Vector3, yaw_deg: float = 0.0) -> bool:
	if active:
		return false
	if battery < 0.04:
		_sfx("dry_fire", -8.0)
		return false
	origin = at
	_yaw = deg_to_rad(yaw_deg)
	_pitch = -0.3
	_vel = Vector3.ZERO
	_ensure_body()
	body.global_position = at
	body.rotation = Vector3(0, _yaw, 0)
	cam.rotation = Vector3(_pitch, 0, 0)
	var pl := _player()
	if pl != null:
		_player_cam = pl.get_camera()
	body.visible = true
	body.process_mode = Node.PROCESS_MODE_INHERIT
	cam.current = true
	active = true
	_hide_player_layers(true)
	_fx_layer.visible = true
	_hud_layer.visible = true
	_set_thermal_internal(thermal)
	_hum = _loop2d("curfew_drone_hum", -16.0)
	_sfx("gunship_switch", -10.0)
	_rec_t = 0.0
	launched.emit()
	return true

## Flug beenden (Rueckkehr: Verbindung trennt, Pilot hat wieder die eigene Sicht).
func stop(reason: String = "manual") -> void:
	if not active:
		return
	active = false
	_auto_pts.clear()
	_apply_heat(false)
	if _hum != null and is_instance_valid(_hum):
		_hum.queue_free()
	_hum = null
	_fx_layer.visible = false
	_hud_layer.visible = false
	if body != null:
		# nicht DISABLED: der Koerper bliebe sonst beim naechsten Start einen Frame ohne Physik-Space
		body.visible = false
	_restore_player()
	_sfx("gunship_switch", -14.0)
	finished.emit(reason)

func set_thermal(on: bool) -> void:
	if on == thermal:
		return
	thermal = on
	if active:
		_set_thermal_internal(on)
		_sfx("gunship_switch", -12.0)
	thermal_toggled.emit(on)

func toggle_thermal() -> void:
	set_thermal(not thermal)

func set_marks_visible(on: bool) -> void:
	marks_visible = on
	_marks_layer.visible = on

## Bot: Punkte (Vector3, Weltkoordinaten) nacheinander anfliegen, je dwell Sekunden schwenken, alles markieren.
func autofly(points: Array, dwell: float = 1.0) -> void:
	_auto_pts = points.duplicate()
	_auto_i = 0
	_auto_dwell = dwell
	_auto_wait = 0.0

## Weltposition des Drohnenkoerpers (fuer Level-Logik).
func drone_position() -> Vector3:
	return body.global_position if body != null else origin

# ------------------------------------------------------------------ Aufbau

func _ensure_body() -> void:
	if body != null:
		return
	body = CharacterBody3D.new()
	body.name = "DroneBody"
	body.collision_layer = 0
	body.collision_mask = 1
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.top_level = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.35
	cs.shape = sh
	body.add_child(cs)
	# kleiner Rahmen mit vier Rotoren (sichtbar fuer Wachen nah am Boden, nicht fuer die eigene Kamera)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.09)
	dark.roughness = 0.6
	var mesh_root := Node3D.new()
	body.add_child(mesh_root)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.22, 0.08, 0.3)
	var core := MeshInstance3D.new()
	core.mesh = bm
	core.material_override = dark
	core.layers = 1 << 18
	mesh_root.add_child(core)
	for sx: float in [-0.22, 0.22]:
		for sz: float in [-0.22, 0.22]:
			var rm := CylinderMesh.new()
			rm.top_radius = 0.12
			rm.bottom_radius = 0.12
			rm.height = 0.015
			var r := MeshInstance3D.new()
			r.mesh = rm
			r.material_override = dark
			r.position = Vector3(sx, 0.05, sz)
			r.layers = 1 << 18
			mesh_root.add_child(r)
	cam = Camera3D.new()
	cam.name = "DroneCam"
	cam.fov = 70.0
	cam.near = 0.1
	cam.far = 900.0
	cam.cull_mask = 0xFFFFF & ~(1 << 18) & ~(1 << 19)
	cam.position = Vector3(0, -0.12, -0.1)
	body.add_child(cam)
	add_child(body)
	body.visible = false

func _build_layers() -> void:
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = 3
	_fx_layer.name = "DroneFX"
	_fx_layer.visible = false
	add_child(_fx_layer)
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = ThermalShader
	_fx_rect.material = _fx_mat
	_fx_layer.add_child(_fx_rect)
	_marks_layer = CanvasLayer.new()
	_marks_layer.layer = 4
	_marks_layer.name = "DroneMarks"
	add_child(_marks_layer)
	_marks = Control.new()
	_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.draw.connect(_draw_marks)
	_marks_layer.add_child(_marks)
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 7
	_hud_layer.name = "DroneHUD"
	_hud_layer.visible = false
	add_child(_hud_layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	_hud_layer.add_child(_hud)

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if not active or _bot:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel := (event as InputEventMouseMotion).relative
		var sens: float = 0.0022 * float(_setting("controls/sensitivity", 1.0)) * (_fov / 70.0)
		var inv := -1.0 if bool(_setting("controls/invert_y", false)) else 1.0
		_yaw -= rel.x * sens
		_pitch = clampf(_pitch - rel.y * sens * inv, deg_to_rad(-88.0), deg_to_rad(25.0))
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drone_thermal") and not event.is_echo():
		toggle_thermal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drone_toggle") and not event.is_echo():
		get_viewport().set_input_as_handled()
		stop("manual")
	elif event.is_action_pressed("fire"):
		if not hovered.is_empty() and not bool(hovered["marked"]):
			mark(hovered["node"])
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ Ablauf

func _process(delta: float) -> void:
	_t += delta
	for i in range(_flash.size() - 1, -1, -1):
		_flash[i]["t"] = float(_flash[i]["t"]) - delta
		if float(_flash[i]["t"]) <= 0.0:
			_flash.remove_at(i)
	if active:
		_fx_mat.set_shader_parameter("time_s", _t)
		_fx_mat.set_shader_parameter("signal_loss", clampf(1.0 - signal_strength, 0.0, 1.0) * 0.9)
		_hud.queue_redraw()
	if marks_visible:
		_marks.queue_redraw()

func _physics_process(delta: float) -> void:
	_update_wind(delta)
	if not active:
		return
	_rec_t += delta
	_freeze_player()
	var input_move := Vector2.ZERO
	var vert := 0.0
	var boost := false
	var zoom := false
	if _bot:
		var r := _auto_step(delta)
		input_move = r[0]
		vert = r[1]
		boost = true
	else:
		input_move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.is_action_pressed("jump"):
			vert += 1.0
		if Input.is_action_pressed("crouch") or (InputMap.has_action("crouch_hold") and Input.is_action_pressed("crouch_hold")):
			vert -= 1.0
		boost = Input.is_action_pressed("sprint")
		zoom = Input.is_action_pressed("aim")
	_fov = lerpf(_fov, 26.0 if zoom else 70.0, clampf(delta * 8.0, 0.0, 1.0))
	cam.fov = _fov
	# Akku
	var drain := (1.6 if boost else 1.0) / maxf(battery_seconds, 1.0)
	battery = maxf(0.0, battery - drain * delta)
	# Steuerung relativ zur Blickrichtung (nur Gier)
	var b := Basis(Vector3.UP, _yaw)
	var spd := boost_speed if boost else cruise_speed
	var want := b * Vector3(input_move.x, 0.0, input_move.y) * spd
	want.y = vert * climb_speed
	_vel = _vel.lerp(want, clampf(delta * 2.6, 0.0, 1.0))
	var v := _vel + wind * 0.55
	# Reichweite: ausserhalb drueckt die Fernsteuerung zurueck, Signal bricht weg
	var off := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z)
	var dist := off.length()
	signal_strength = 1.0 - smoothstep(max_range * 0.72, max_range, dist)
	if dist > max_range and dist > 0.01:
		var back := Vector3(-off.x, 0.0, -off.y) / dist
		v += back * (dist - max_range + 1.0) * 2.5
		var outward := Vector3(off.x, 0.0, off.y) / dist
		var ov := v.dot(outward)
		if ov > 0.0:
			v -= outward * ov
	# Hoehe ueber Grund
	_ground_ray_t -= delta
	if _ground_ray_t <= 0.0:
		_ground_ray_t = 0.1
		_agl = _measure_agl()
	if _agl < min_agl and v.y < 0.0:
		v.y = maxf(v.y, 0.0) + (min_agl - _agl) * 3.0
	elif _agl < min_agl:
		v.y += (min_agl - _agl) * 3.0
	var top := origin.y + max_height
	if body.global_position.y > top and v.y > 0.0:
		v.y = minf(v.y, (top - body.global_position.y) * 2.0)
	body.velocity = v
	if PhysicsServer3D.body_get_space(body.get_rid()).is_valid():
		body.move_and_slide()
	body.rotation = Vector3(0.0, _yaw, 0.0)
	cam.rotation = Vector3(_pitch, 0.0, 0.0)
	# leichtes Wackeln in Boeen
	cam.rotation.z = sin(_t * 1.7) * 0.008 * (1.0 + _gust)
	if _hum != null and is_instance_valid(_hum):
		_hum.pitch_scale = 0.95 + clampf(v.length() / 15.0, 0.0, 1.0) * 0.25
	_update_noise(delta)
	_update_hover()
	_heat_t -= delta
	if thermal and _heat_t <= 0.0:
		_heat_t = 0.6
		_apply_heat(true)
	if battery <= 0.0:
		_flash_text("AKKU LEER – RÜCKKEHR")
		stop("battery")

func _update_wind(delta: float) -> void:
	# Richtung wandert langsam, Boeen kommen und gehen
	if absf(angle_difference(_wind_ang, _wind_target)) < 0.05:
		_wind_target = _wind_ang + _rng.randf_range(-0.9, 0.9)
	_wind_ang = lerp_angle(_wind_ang, _wind_target, clampf(delta * 0.08, 0.0, 1.0))
	_gust = clampf(_gust + _rng.randf_range(-1.0, 1.0) * delta * 0.9, 0.0, 1.0)
	var spd := wind_base + wind_gust * _gust * _gust
	wind = Vector3(sin(_wind_ang), 0.0, cos(_wind_ang)) * spd

func _measure_agl() -> float:
	var space := body.get_world_3d().direct_space_state
	var p := body.global_position
	var q := PhysicsRayQueryParameters3D.create(p, p + Vector3.DOWN * 200.0, 1)
	q.exclude = [body.get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return 99.0
	return p.y - (hit["position"] as Vector3).y

## Rotorlaerm: Wachen in der Naehe (horizontal und nicht zu hoch) werden misstrauisch.
func _update_noise(delta: float) -> void:
	noise_level = 0.0
	if director == null or not is_instance_valid(director):
		return
	var dp := body.global_position
	for w in director.get("watchers"):
		if not is_instance_valid(w) or not w.has_method("hear_noise"):
			continue
		var e: Node3D = w.get("enemy")
		if e == null or not is_instance_valid(e) or not bool(w.call("is_watcher_alive")):
			continue
		var cd: float = float(_noise_cd.get(w, 0.0))
		if cd > 0.0:
			_noise_cd[w] = cd - delta
		var dh := Vector2(dp.x - e.global_position.x, dp.z - e.global_position.z).length()
		var dv := dp.y - e.global_position.y
		if dh >= noise_radius or dv >= noise_agl:
			_noise_acc[w] = maxf(0.0, float(_noise_acc.get(w, 0.0)) - delta * 0.3)
			continue
		var k := (1.0 - dh / noise_radius) * (1.0 - maxf(dv, 0.0) / noise_agl)
		noise_level = maxf(noise_level, k)
		if cd > 0.0:
			continue
		var acc := float(_noise_acc.get(w, 0.0)) + k * delta * 1.6
		if acc >= 1.0:
			acc = 0.0
			_noise_cd[w] = 6.0
			var ground := Vector3(dp.x, e.global_position.y, dp.z)
			w.call("hear_noise", ground, 1.0e6)
			_flash_text("WACHE HÖRT DEN ROTOR")
			noticed.emit(w)
		_noise_acc[w] = acc

func _target_point(t: Dictionary) -> Vector3:
	var n: Node3D = t["node"]
	var k := str(t["kind"])
	if k in ["guard", "jaeger", "weber", "person"]:
		return n.global_position + Vector3(0, 1.3, 0)
	return n.global_position

func _target_valid(t: Dictionary) -> bool:
	var n: Variant = t["node"]
	if n == null or not is_instance_valid(n) or not (n as Node).is_inside_tree():
		return false
	if (n as Object).has_method("is_alive") and not bool((n as Object).call("is_alive")):
		return false
	if (n as Object).has_method("is_watcher_alive") and not bool((n as Object).call("is_watcher_alive")):
		return false
	return true

func _visible_from_cam(t: Dictionary, dist: float) -> bool:
	if thermal and dist <= thermal_see_through:
		return true
	var tp := _target_point(t)
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, tp, 1)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	return (hit["position"] as Vector3).distance_to(tp) < 1.6

func _update_hover() -> void:
	hovered = {}
	var vs := _hud.get_viewport_rect().size
	var c := vs * 0.5
	var radius := 70.0 * (70.0 / _fov) * 0.55 + 30.0
	var best := radius
	for t: Dictionary in targets:
		if not _target_valid(t):
			continue
		var tp := _target_point(t)
		if cam.is_position_behind(tp):
			continue
		var dist := cam.global_position.distance_to(tp)
		if dist > mark_range:
			continue
		var sp := cam.unproject_position(tp)
		var d := sp.distance_to(c)
		if d < best and _visible_from_cam(t, dist):
			best = d
			hovered = t

## Bot-Steuerung: liefert [Bewegung (Vector2), Steigen (float)] und markiert sichtbare Ziele.
func _auto_step(delta: float) -> Array:
	if _auto_pts.is_empty():
		return [Vector2.ZERO, 0.0]
	_auto_mark_t -= delta
	if _auto_mark_t <= 0.0:
		_auto_mark_t = 0.35
		for t: Dictionary in targets:
			if bool(t["marked"]) or not _target_valid(t):
				continue
			var tp := _target_point(t)
			if cam.is_position_behind(tp):
				continue
			var dist := cam.global_position.distance_to(tp)
			if dist > mark_range:
				continue
			var sp := cam.unproject_position(tp)
			var vs := _hud.get_viewport_rect().size
			if sp.x < vs.x * 0.1 or sp.x > vs.x * 0.9 or sp.y < vs.y * 0.1 or sp.y > vs.y * 0.9:
				continue
			if _visible_from_cam(t, dist):
				mark(t["node"])
				break
	if _auto_i >= _auto_pts.size():
		stop("bot")
		return [Vector2.ZERO, 0.0]
	var goal: Vector3 = _auto_pts[_auto_i]
	var to := goal - body.global_position
	var flat := Vector2(to.x, to.z)
	if flat.length() < 2.5 and absf(to.y) < 2.5:
		_auto_wait += delta
		_yaw += delta * 1.1
		_pitch = lerpf(_pitch, deg_to_rad(-40.0), delta * 2.0)
		if _auto_wait >= _auto_dwell:
			_auto_wait = 0.0
			_auto_i += 1
		return [Vector2.ZERO, 0.0]
	var want_yaw := atan2(-to.x, -to.z)
	_yaw = lerp_angle(_yaw, want_yaw, clampf(delta * 2.5, 0.0, 1.0))
	_pitch = lerpf(_pitch, deg_to_rad(-28.0), delta * 2.0)
	# Bewegung in lokale Eingabe umrechnen (wie beim Spieler)
	var b := Basis(Vector3.UP, _yaw)
	var local := b.inverse() * Vector3(to.x, 0.0, to.z)
	var mv := Vector2(local.x, local.z)
	mv = mv.normalized() * minf(1.0, mv.length() / 4.0)
	return [mv, clampf(to.y / 3.0, -1.0, 1.0)]

# ------------------------------------------------------------------ Waermebild

func _set_thermal_internal(on: bool) -> void:
	_fx_mat.set_shader_parameter("thermal", 1.0 if on else 0.0)
	if cam != null:
		cam.environment = _thermal_env if on else null
		cam.attributes = _thermal_attr if on else null
	_apply_heat(on and active)

## Warme Koerper (Gruppe "enemy", Gruppe "recon_warm", Personen-Ziele) bekommen ein emittierendes Overlay.
func _apply_heat(on: bool) -> void:
	if not on:
		for mi in _heat_nodes:
			if is_instance_valid(mi):
				mi.material_overlay = mi.get_meta("rd_prev_overlay") if mi.has_meta("rd_prev_overlay") else null
				mi.remove_meta("rd_prev_overlay")
		_heat_nodes.clear()
		return
	if not is_inside_tree():
		return
	var warm: Array[Node] = []
	warm.append_array(get_tree().get_nodes_in_group("enemy"))
	warm.append_array(get_tree().get_nodes_in_group("recon_warm"))
	var dev: Array[Node] = []
	for t: Dictionary in targets:
		if not _target_valid(t):
			continue
		if str(t["kind"]) in ["guard", "jaeger", "weber", "person"]:
			warm.append(t["node"])
		elif str(t["kind"]) == "camera":
			dev.append(t["node"])
	for grp: Array in [[warm, _heat_mat], [dev, _heat_mat_dev]]:
		for n: Node in grp[0]:
			if not is_instance_valid(n):
				continue
			if n.has_method("is_alive") and not bool(n.call("is_alive")):
				continue
			for c in n.find_children("*", "MeshInstance3D", true, false):
				var mi := c as MeshInstance3D
				if mi.has_meta("rd_prev_overlay") or not mi.visible:
					continue
				mi.set_meta("rd_prev_overlay", mi.material_overlay)
				mi.material_overlay = grp[1]
				_heat_nodes.append(mi)

# ------------------------------------------------------------------ Spieler

func _player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player

func _freeze_player() -> void:
	var pl := _player()
	if pl == null or pl.dead:
		return
	pl.external_input = true
	var ext: Dictionary = pl.ext
	for k in ["fire", "aim", "sprint", "crouch", "jump", "reload", "grenade", "interact"]:
		ext[k] = false
	ext["move"] = Vector2.ZERO
	ext["look"] = Vector2.ZERO

func _restore_player() -> void:
	_hide_player_layers(false)
	var pl := _player()
	if pl != null:
		var pc := pl.get_camera()
		if pc != null:
			pc.current = true
		if not _bot:
			pl.external_input = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif _player_cam != null and is_instance_valid(_player_cam):
		_player_cam.current = true

func _hide_player_layers(hide: bool) -> void:
	if hide:
		_hidden_layers.clear()
		var pl := _player()
		if pl == null:
			return
		for c in pl.find_children("*", "CanvasLayer", true, false):
			var cl := c as CanvasLayer
			if cl.visible:
				cl.visible = false
				_hidden_layers.append(cl)
	else:
		for cl in _hidden_layers:
			if is_instance_valid(cl):
				cl.visible = true
		_hidden_layers.clear()

# ------------------------------------------------------------------ Klang

func _sfx(sfx_name: String, vol: float = 0.0, pitch: float = 1.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	p.volume_db = vol
	p.pitch_scale = pitch
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _loop2d(sfx_name: String, vol: float) -> AudioStreamPlayer:
	var path := "res://assets/sfx/%s.ogg" % sfx_name
	if not ResourceLoader.exists(path):
		return null
	var st := load(path) as AudioStreamOggVorbis
	if st == null:
		return null
	st = st.duplicate() as AudioStreamOggVorbis
	st.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	p.volume_db = vol
	add_child(p)
	p.play()
	return p

func _setting(key: String, dflt: Variant) -> Variant:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return dflt
	var v: Variant = st.call("get_value", key, dflt)
	return dflt if v == null else v

func _flash_text(text: String) -> void:
	_flash.append({"text": text, "t": 1.8})
	if _flash.size() > 3:
		_flash.remove_at(0)

static func _kind_label(kind: String) -> String:
	match kind:
		"guard":
			return "Wache"
		"camera":
			return "Kamera"
		"jaeger":
			return "Garde-Jäger"
		"weber":
			return "Weber"
		"person":
			return "Person"
	return "Ziel"

static func _kind_color(kind: String) -> Color:
	match kind:
		"guard":
			return Color(1.0, 0.42, 0.2)
		"camera":
			return Color(1.0, 0.86, 0.25)
		"jaeger":
			return Color(0.66, 0.74, 0.95)
		"weber":
			return Color(0.35, 0.95, 0.9)
	return Color(0.9, 0.9, 0.9)

func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
		if ev is InputEventMouseButton:
			var mb := (ev as InputEventMouseButton).button_index
			return "LMT" if mb == MOUSE_BUTTON_LEFT else ("RMT" if mb == MOUSE_BUTTON_RIGHT else "Maus")
	return "?"

# ------------------------------------------------------------------ HUD

func _text(s: String, pos: Vector2, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, ctl: Control = null) -> void:
	var c := ctl if ctl != null else _hud
	var w := _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	c.draw_string(_font, Vector2(x + 1, pos.y + 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, col.a * 0.7))
	c.draw_string(_font, Vector2(x, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw_hud() -> void:
	if not active or cam == null:
		return
	var vs := _hud.size
	var c := vs * 0.5
	var fg := Color(0.85, 1.0, 0.9, 0.92) if not thermal else Color(1.0, 1.0, 1.0, 0.92)
	var warn := Color(1.0, 0.45, 0.25, 0.95)
	# Bildecken
	var m := 40.0
	var l := 46.0
	for corner: Vector2 in [Vector2(m, m), Vector2(vs.x - m, m), Vector2(m, vs.y - m), Vector2(vs.x - m, vs.y - m)]:
		var sx := 1.0 if corner.x < c.x else -1.0
		var sy := 1.0 if corner.y < c.y else -1.0
		_hud.draw_line(corner, corner + Vector2(l * sx, 0), fg, 2.0)
		_hud.draw_line(corner, corner + Vector2(0, l * sy), fg, 2.0)
	# Fadenkreuz (Zoomrahmen)
	var r := 70.0 * (70.0 / _fov) * 0.55 + 30.0
	var g := 10.0
	_hud.draw_line(c + Vector2(-r, 0), c + Vector2(-g, 0), fg, 1.5)
	_hud.draw_line(c + Vector2(g, 0), c + Vector2(r, 0), fg, 1.5)
	_hud.draw_line(c + Vector2(0, -r * 0.6), c + Vector2(0, -g), fg, 1.5)
	_hud.draw_line(c + Vector2(0, g), c + Vector2(0, r * 0.6), fg, 1.5)
	_hud.draw_arc(c, r, -0.4, 0.4, 10, fg, 1.5)
	_hud.draw_arc(c, r, PI - 0.4, PI + 0.4, 10, fg, 1.5)
	# Kopfzeile
	_text("%s · %s" % [feed_label, pilot_label], Vector2(m + 14, m + 30), 18, fg)
	var rec_on := fmod(_t, 1.0) < 0.6
	if rec_on:
		_hud.draw_circle(Vector2(m + 22, m + 52), 6.0, Color(1.0, 0.2, 0.15))
	_text("REC %02d:%02d" % [int(_rec_t) / 60, int(_rec_t) % 60], Vector2(m + 36, m + 58), 16, fg)
	if thermal:
		_text("WÄRMEBILD  WEISS-HEISS", Vector2(m + 14, m + 82), 16, fg)
	# Akku und Signal
	var bx := vs.x - m - 200.0
	_text("AKKU %d %%" % int(round(battery * 100.0)), Vector2(bx, m + 30), 16, warn if battery < 0.25 else fg)
	_bar(Vector2(bx, m + 38), Vector2(186, 9), battery, warn if battery < 0.25 else fg)
	_text("SIGNAL", Vector2(bx, m + 66), 16, warn if signal_strength < 0.45 else fg)
	for i in 5:
		var on := signal_strength > float(i) / 5.0 + 0.05
		var h := 6.0 + i * 4.0
		var rc := Rect2(Vector2(bx + 80 + i * 12, m + 66 - h), Vector2(8, h))
		_hud.draw_rect(rc, fg if on else Color(fg.r, fg.g, fg.b, 0.2))
	var dist := Vector2(body.global_position.x - origin.x, body.global_position.z - origin.z).length()
	_text("DIST %3d m" % int(dist), Vector2(bx, m + 92), 16, fg)
	_text("HÖHE %3d m" % int(_agl), Vector2(bx, m + 114), 16, warn if _agl < noise_agl and noise_level > 0.05 else fg)
	# Kompass oben mittig
	var hdg := fposmod(rad_to_deg(-_yaw) + 0.0, 360.0)
	_text("%03d°" % int(hdg), Vector2(c.x, m + 30), 18, fg, HORIZONTAL_ALIGNMENT_CENTER)
	# Wind (Pfeil relativ zur Blickrichtung)
	var wl := Vector2(wind.x, wind.z)
	var wc := Vector2(m + 60, vs.y - m - 70)
	_hud.draw_arc(wc, 30.0, 0, TAU, 28, Color(fg.r, fg.g, fg.b, 0.4), 1.2)
	if wl.length() > 0.05:
		var rel := wl.rotated(_yaw)    # Welt -> Bild (oben = vorn)
		var dir := Vector2(rel.x, rel.y).normalized()
		var tip := wc + dir * 26.0
		_hud.draw_line(wc - dir * 20.0, tip, fg, 2.5)
		var side := Vector2(-dir.y, dir.x)
		_hud.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 10.0 + side * 6.0, tip - dir * 10.0 - side * 6.0]), fg)
	_text("WIND %.1f m/s" % wl.length(), Vector2(m + 14, vs.y - m - 22), 16, fg)
	# Markierungen
	var total := target_count()
	_text("MARKIERT %d / %d" % [marked_count(), total], Vector2(vs.x - m - 14, vs.y - m - 70), 18, fg, HORIZONTAL_ALIGNMENT_RIGHT)
	# Ziel unter dem Fadenkreuz
	if not hovered.is_empty():
		var tp := _target_point(hovered)
		var sp := cam.unproject_position(tp)
		var kc := _kind_color(str(hovered["kind"]))
		_hud.draw_rect(Rect2(sp - Vector2(18, 18), Vector2(36, 36)), kc, false, 2.0)
		var txt := str(hovered["label"]).to_upper()
		if bool(hovered["marked"]):
			txt += " · MARKIERT"
		else:
			txt += "  [%s] markieren" % _key("fire")
		_text(txt, sp + Vector2(0, -26), 16, kc, HORIZONTAL_ALIGNMENT_CENTER)
		_text("%d m" % int(cam.global_position.distance_to(tp)), sp + Vector2(0, 38), 14, kc, HORIZONTAL_ALIGNMENT_CENTER)
	# Warnungen
	var y := c.y + 120.0
	var blink := fmod(_t, 0.8) < 0.5
	if signal_strength < 0.45 and blink:
		_text("SIGNAL SCHWACH – ZURÜCK", Vector2(c.x, y), 22, warn, HORIZONTAL_ALIGNMENT_CENTER)
		y += 28
	if battery < 0.2 and blink:
		_text("AKKU KRITISCH", Vector2(c.x, y), 22, warn, HORIZONTAL_ALIGNMENT_CENTER)
		y += 28
	if noise_level > 0.15:
		_text("ZU NAH – ROTOR HÖRBAR", Vector2(c.x, y), 20, Color(1.0, 0.75, 0.3, 0.6 + 0.4 * noise_level), HORIZONTAL_ALIGNMENT_CENTER)
		y += 26
	for f: Dictionary in _flash:
		_text(str(f["text"]), Vector2(c.x, y), 20, Color(fg.r, fg.g, fg.b, clampf(float(f["t"]), 0.0, 1.0)), HORIZONTAL_ALIGNMENT_CENTER)
		y += 26
	# Tastenhilfe
	if not _bot:
		var hint := "[WASD] fliegen  [%s/%s] Höhe  [%s] schnell  [%s] markieren  [%s] Zoom  [%s] Wärmebild  [%s] zurück" % [
			_key("jump"), _key("crouch"), _key("sprint"), _key("fire"), _key("aim"), _key("drone_thermal"), _key("drone_toggle")]
		_text(hint, Vector2(c.x, vs.y - m - 16), 15, Color(fg.r, fg.g, fg.b, 0.75), HORIZONTAL_ALIGNMENT_CENTER)

func _bar(pos: Vector2, size: Vector2, f: float, col: Color) -> void:
	_hud.draw_rect(Rect2(pos, size), Color(col.r, col.g, col.b, 0.18))
	_hud.draw_rect(Rect2(pos, Vector2(size.x * clampf(f, 0.0, 1.0), size.y)), col)
	_hud.draw_rect(Rect2(pos, size), col, false, 1.0)

## Dauerhafte Markierungen (auch nach dem Flug, aus Spielersicht): Raute, Art, Entfernung; am Rand geklemmt.
func _draw_marks() -> void:
	var cv := _marks.get_viewport().get_camera_3d()
	if cv == null:
		return
	var vs := _marks.size
	for t: Dictionary in targets:
		if not bool(t["marked"]) or not _target_valid(t):
			continue
		var tp := _target_point(t) + Vector3(0, 0.75 if str(t["kind"]) in ["guard", "jaeger", "weber", "person"] else 0.45, 0)
		var behind := cv.is_position_behind(tp)
		var sp := cv.unproject_position(tp)
		var col := _kind_color(str(t["kind"]))
		var dist := cv.global_position.distance_to(tp)
		var edge := false
		if behind:
			sp = vs - sp
			edge = true
		var pad := 26.0
		if sp.x < pad or sp.x > vs.x - pad or sp.y < pad or sp.y > vs.y - pad:
			edge = true
		sp = Vector2(clampf(sp.x, pad, vs.x - pad), clampf(sp.y, pad, vs.y - pad))
		var s := 7.0 if edge else clampf(220.0 / maxf(dist, 1.0), 6.0, 11.0)
		var a := 0.55 if edge else 0.9
		var pts := PackedVector2Array([sp + Vector2(0, -s), sp + Vector2(s, 0), sp + Vector2(0, s), sp + Vector2(-s, 0), sp + Vector2(0, -s)])
		_marks.draw_polyline(pts, Color(0, 0, 0, 0.5 * a), 3.5)
		_marks.draw_polyline(pts, Color(col.r, col.g, col.b, a), 1.8)
		if str(t["kind"]) == "camera":
			_marks.draw_circle(sp, 2.0, Color(col.r, col.g, col.b, a))
		if not edge and (dist < 45.0 or active):
			_text("%s %dm" % [str(t["label"]), int(dist)], sp + Vector2(0, -s - 6), 13, Color(col.r, col.g, col.b, a * 0.9), HORIZONTAL_ALIGNMENT_CENTER, _marks)
