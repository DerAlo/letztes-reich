extends AnimatableBody3D
## RailRide – Fahrt mit Bordwaffe auf festem Pfad (wiederverwendbar: Schnellboot, Zugwaggon, Hubschrauber-Tuer).
##
## Das Fahrzeug IST waehrend der Fahrt der Spieler (Gruppen "player" + "damageable", Layer 2) und erfuellt den
## Spieler-Vertrag: get_camera / is_alive / get_status / take_damage / add_trauma / get_damage_points /
## get_collision_rids / autopilot_self_driven. Unter --autopilot schiesst rail_ride_bot.gd selbst.
##
## Benutzung (siehe hafen.gd):
##   var r = RailRide.new()                       # const RailRide = preload("res://game/systems/rail_ride.gd")
##   r.configure({"cruise_speed": 15.0, "mount_offset": Vector3(0, 1.9, -2.4), "rock_roll_deg": 1.4,
##                "weapon": {"name": "MG3", "rpm": 900.0, "damage": 22.0}})
##   add_child(r); level.player = r
##   r.set_path(points)                           # Weltpunkte (Catmull-Rom-geglaettet), Position springt an den Anfang
##   FX: r.model (Node3D) mit eigener Optik fuellen; add_hull_box(center, size) fuer Kollision
##   r.add_trigger(s, "id", callable)             # einmalig, wenn die Fahrt s (Meter) passiert
##   r.add_stop(s, "id", until_callable, max_wait)  # bremst sauber auf s, wartet bis until() oder max_wait
##   r.set_speed(v) / r.release_stop() / r.reset_to(s) / r.refit()
##   Signale: reached_end, destroyed, stop_reached(id), stop_released(id), trigger_passed(id), hit_taken(amount)
##
## Bewegung: leichtes Schaukeln/Wippen (rock_*), Kurvenneigung (bank_factor), Kamera stabilisiert
## (cam_stabilize 0..1) – bewusst dezent, damit niemandem schlecht wird.
## Waffe: Dauerfeuer mit Hitze (statt Munition), Ueberhitzung sperrt bis unlock_at; Treffer per Raycast aus der Kamera.

signal reached_end
signal destroyed
signal stop_reached(id: String)
signal stop_released(id: String)
signal trigger_passed(id: String)
signal hit_taken(amount: float)

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const HudScript := preload("res://game/systems/rail_ride_hud.gd")
const BotScript := preload("res://game/systems/rail_ride_bot.gd")
const FX := preload("res://game/systems/rail_ride_fx.gd")

const HIT_MASK := 1 | 4

const DEFAULT_WEAPON := {
	"name": "MG", "rpm": 850.0, "damage": 22.0, "spread_deg": 0.45, "range": 500.0,
	"heat_per_shot": 0.012, "cool_rate": 0.34, "cool_delay": 0.22, "unlock_at": 0.35,
	"tracer_every": 3, "tracer_color": "orange", "tracer_width": 0.9,
	"sfx": "hafen_mg", "sfx_every": 2, "sfx_db": -5.0, "trauma": 0.02,
	"splash_radius": 0.0, "splash_damage": 0.0,
}

# ------------------------------------------------------------------ Konfiguration
@export_group("Fahrt")
@export var vehicle_name: String = "Boot"
@export var cruise_speed: float = 14.0          ## m/s
@export var accel: float = 3.5                  ## m/s^2
@export var decel: float = 5.0                  ## m/s^2 (auch Bremsweg vor Halten)
@export var height_offset: float = 0.0          ## y auf die Pfadpunkte
@export_group("Haltbarkeit")
@export var max_integrity: float = 100.0
@export var regen_delay: float = 4.5            ## s ohne Treffer, dann Selbstreparatur
@export var regen_rate: float = 4.0             ## Punkte/s
@export var damage_scale: float = 0.3           ## Handfeuerwaffen
@export var vehicle_damage_scale: float = 0.5   ## Treffer von Fahrzeugen (Gruppe "vehicle")
@export var explosion_damage_scale: float = 0.35
@export var invulnerable: bool = false          ## faellt nie ganz aus (Hilfe nach mehreren Fehlschlaegen)
@export_group("Bordwaffe")
@export var mount_offset: Vector3 = Vector3(0, 1.8, -2.0)   ## Drehpunkt der Waffe relativ zum Fahrzeug
@export var eye_offset: Vector3 = Vector3(0, 0.32, 0.75)    ## Kamera relativ zur Waffe (dahinter, darueber)
@export var yaw_limit_deg: float = 150.0        ## Schwenkbereich +/- zur Fahrtrichtung (>= 180: frei)
@export var pitch_min_deg: float = -22.0
@export var pitch_max_deg: float = 38.0
@export var fov: float = 72.0
@export var zoom_fov: float = 44.0
@export var build_default_gun: bool = true      ## einfaches Pintle-MG-Modell erzeugen
@export_group("Bewegungsgefuehl")
@export var rock_roll_deg: float = 1.2
@export var rock_pitch_deg: float = 0.7
@export var bob_amp: float = 0.07
@export var rock_freq: float = 0.32             ## Hz
@export var bank_factor: float = 0.9            ## Grad Neigung je (m/s * rad/s) Kurvenfahrt
@export var cam_stabilize: float = 0.6          ## 0 = Kamera schaukelt voll mit, 1 = ruhig
@export var shake_scale: float = 1.0
@export_group("Klang")
@export var engine_sfx: String = ""             ## Loop, Tonhoehe nach Tempo
@export var engine_db: float = -8.0
@export var water_sfx: String = ""              ## Loop, Lautstaerke nach Tempo

var weapon: Dictionary = DEFAULT_WEAPON.duplicate()

# ------------------------------------------------------------------ Zustand
var model: Node3D                 ## hier haengt das Level seine Optik ein (schaukelt mit)
var motion: Node3D                ## Schaukel-Pivot (model + Waffe)
var mount_yaw: Node3D
var mount_pitch: Node3D
var muzzle: Marker3D
var cam: Camera3D
var hud: CanvasLayer
var bot: Node = null
var bot_active: bool = false
var input_enabled: bool = true

var path_s: float = 0.0
var speed: float = 0.0
var target_speed: float = 0.0
var integrity: float = 100.0
var dead: bool = false
var aim_yaw: float = 0.0          ## rad, relativ zur Fahrtrichtung (+ = links)
var aim_pitch: float = 0.0
var fire_held: bool = false
var zoomed: bool = false
var heat: float = 0.0
var locked: bool = false
var hit_flash: float = 0.0
var hit_dir: float = 0.0          ## rad, Richtung des letzten Treffers relativ zur Kamera (HUD)
var hit_dir_t: float = 0.0
var hitmarker_t: float = 0.0
var kill_t: float = 0.0
var shots: int = 0
var extra_targets: Array[Node3D] = []   ## Ziele ausserhalb der Gruppe "enemy" (fuer Bot/HUD)
var avoid_nodes: Array[Node3D] = []     ## nicht beschiessen (Bot haelt Abstand zur Schusslinie)
var hud_hint: String = ""               ## frei setzbarer Hinweis unten im HUD

var _curve: Curve3D = null
var _len: float = 0.0
var _stops: Array[Dictionary] = []      ## {s, id, until, max_wait, state: 0 wartet / 1 haelt / 2 frei, t}
var _triggers: Array[Dictionary] = []   ## {s, id, f, done}
var _end_sent: bool = false
var _t: float = 0.0
var _trauma: float = 0.0
var _noise := FastNoiseLite.new()
var _fire_cd: float = 0.0
var _since_shot: float = 9.0
var _since_hit: float = 99.0
var _prev_yaw: float = 0.0
var _yaw_rate: float = 0.0
var _bank: float = 0.0
var _flash: Node3D
var _engine: AudioStreamPlayer3D
var _water: AudioStreamPlayer3D
var _small_snd_cd: float = 0.0
var _fov_cur: float = 72.0

func configure(opts: Dictionary) -> void:
	for k: String in opts:
		if k == "weapon":
			var w: Dictionary = opts[k]
			for wk: String in w:
				weapon[wk] = w[wk]
		else:
			set(k, opts[k])

func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	add_to_group("rail_ride")
	collision_layer = VF.LAYER_PLAYER
	collision_mask = 0
	sync_to_physics = false
	set_meta("surface", "metal")
	integrity = max_integrity
	_fov_cur = fov
	motion = Node3D.new()
	motion.name = "Motion"
	add_child(motion)
	model = Node3D.new()
	model.name = "Model"
	motion.add_child(model)
	mount_yaw = Node3D.new()
	mount_yaw.name = "MountYaw"
	mount_yaw.position = mount_offset
	motion.add_child(mount_yaw)
	mount_pitch = Node3D.new()
	mount_pitch.name = "MountPitch"
	mount_yaw.add_child(mount_pitch)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = Vector3(0, 0.05, -1.25)
	mount_pitch.add_child(muzzle)
	if build_default_gun:
		FX.build_pintle_mg(mount_yaw, mount_pitch)
	_flash = VF.make_muzzle_flash(muzzle, 0.8, 5.0, 7.0)
	cam = Camera3D.new()
	cam.name = "GunnerCam"
	cam.near = 0.06
	cam.far = 2500.0
	cam.fov = fov
	add_child(cam)
	cam.top_level = true
	cam.make_current()
	_noise.frequency = 0.7
	_noise.seed = 77
	if engine_sfx != "":
		_engine = VF.loop_player(self, engine_sfx, 14.0, 300.0, engine_db)
	if water_sfx != "":
		_water = VF.loop_player(self, water_sfx, 10.0, 120.0, -12.0)
	bot_active = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	if not bot_active and not bool(Game.arg("capture", false)):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud = HudScript.new()
	hud.name = "RailRideHud"
	hud.set("ride", self)
	add_child(hud)
	if bot_active:
		bot = BotScript.new()
		bot.name = "RailRideBot"
		bot.set("ride", self)
		add_child(bot)

## Kollisionsbox am Rumpf (lokal, nicht schaukelnd). Ohne Box gibt es eine Standard-Box 3x2x8.
func add_hull_box(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	add_child(cs)

# ------------------------------------------------------------------ Spieler-Vertrag

func autopilot_self_driven() -> bool:
	return bot_active

func get_camera() -> Camera3D:
	return cam

func is_alive() -> bool:
	return not dead

func get_status() -> Dictionary:
	return {"type": "rail_ride", "alive": not dead, "health": integrity, "max_health": max_integrity,
		"ammo_mag": int((1.0 - heat) * 100.0), "reloading": locked, "grenades": 0,
		"weapon": str(weapon.get("name", "MG")), "speed": speed, "s": path_s}

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

func get_damage_points() -> Array[Vector3]:
	var b := global_transform
	return [b * Vector3(0, 1.0, 0), b * Vector3(0, 1.0, -3.0), b * Vector3(0, 1.0, 3.0), b * (mount_offset + Vector3(0, 0.3, 0))]

func get_collision_rids() -> Array[RID]:
	return [get_rid()]

# ------------------------------------------------------------------ Pfad

## Weltpunkte; Kurve wird Catmull-Rom-artig geglaettet. Position springt an den Anfang.
func set_path(points: Array[Vector3]) -> void:
	_curve = Curve3D.new()
	_curve.bake_interval = 0.5
	var n := points.size()
	for i in n:
		var p := points[i] + Vector3(0, height_offset, 0)
		var prev := points[maxi(i - 1, 0)]
		var nxt := points[mini(i + 1, n - 1)]
		var tan := (nxt - prev) * 0.22
		if i == 0 or i == n - 1:
			tan = Vector3.ZERO
		_curve.add_point(p, -tan, tan)
	_len = _curve.get_baked_length()
	_end_sent = false
	reset_to(0.0)

func path_length() -> float:
	return _len

func pos_at(s: float) -> Vector3:
	if _curve == null:
		return global_position
	return _curve.sample_baked(clampf(s, 0.0, _len), true)

func dir_at(s: float) -> Vector3:
	if _curve == null:
		return -global_transform.basis.z
	var a := pos_at(s - 1.0)
	var b := pos_at(s + 1.0)
	var d := b - a
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else -global_transform.basis.z

## Bahnmeter, die dem Weltpunkt p am naechsten liegen.
func s_nearest(p: Vector3) -> float:
	if _curve == null:
		return 0.0
	return _curve.get_closest_offset(p)

## Springt auf s (Neustart nach Fehlschlag). Haelte/Trigger hinter s gelten als erledigt.
func reset_to(s: float) -> void:
	path_s = clampf(s, 0.0, _len)
	speed = 0.0
	target_speed = cruise_speed
	_end_sent = path_s >= _len - 0.01 and _len > 0.0
	for st in _stops:
		st["state"] = 2 if float(st["s"]) < path_s - 0.5 else 0
		st["t"] = 0.0
	for tr in _triggers:
		tr["done"] = float(tr["s"]) < path_s - 0.5
	_place(0.0)
	_prev_yaw = rotation.y

func set_speed(v: float) -> void:
	target_speed = maxf(v, 0.0)

func add_trigger(s: float, id: String, f: Callable) -> void:
	_triggers.append({"s": s, "id": id, "f": f, "done": s < path_s - 0.5})

## Halt bei s. until: Callable -> bool (leer = nur max_wait). max_wait <= 0: wartet unbegrenzt auf until.
func add_stop(s: float, id: String, until: Callable = Callable(), max_wait: float = -1.0) -> void:
	_stops.append({"s": s, "id": id, "until": until, "max_wait": max_wait, "state": 0 if s >= path_s - 0.5 else 2, "t": 0.0})
	_stops.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) < float(b["s"]))

func clear_events() -> void:
	_stops.clear()
	_triggers.clear()

## Aktuellen Halt sofort freigeben.
func release_stop() -> void:
	for st in _stops:
		if int(st["state"]) == 1:
			st["state"] = 2
			stop_released.emit(str(st["id"]))

func is_stopped() -> bool:
	for st in _stops:
		if int(st["state"]) == 1:
			return true
	return false

func arrived() -> bool:
	return _len > 0.0 and path_s >= _len - 0.05

# ------------------------------------------------------------------ Schaden

func take_damage(amount: float, source: Node, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if dead or amount <= 0.0 or source == self:
		return
	var mult := damage_scale
	if bool(Combat.get("explosion_active")):
		mult = explosion_damage_scale
	elif source != null and is_instance_valid(source) and source.is_in_group("vehicle"):
		mult = vehicle_damage_scale
	apply_damage(amount * mult, hit_position, source)

func apply_damage(d: float, pos: Vector3, source: Node = null) -> void:
	if dead or d <= 0.0:
		return
	if invulnerable:
		d = minf(d, maxf(integrity - 8.0, 0.0))
	integrity = maxf(0.0, integrity - d)
	_since_hit = 0.0
	hit_flash = minf(1.0, hit_flash + clampf(d / 8.0, 0.1, 1.0))
	add_trauma(clampf(d / 22.0, 0.03, 0.45))
	var to := pos - cam.global_position
	if to.length() > 0.5:
		var lp := cam.global_transform.basis.inverse() * to
		hit_dir = atan2(lp.x, -lp.z)
		hit_dir_t = 1.4
	if _small_snd_cd <= 0.0:
		_small_snd_cd = 0.2
		VF.play_2d(self, ["impact_metal", "impact_metal_2", "impact_metal_3"][randi() % 3], -12.0 + minf(d, 10.0), 0.0, &"SFX", randf_range(0.9, 1.1))
	hit_taken.emit(d)
	Events.player_damaged.emit(d, source)
	if integrity <= 0.0:
		dead = true
		fire_held = false
		destroyed.emit()

## Volle Haltbarkeit, Hitze weg (Neustart).
func refit() -> void:
	dead = false
	integrity = max_integrity
	heat = 0.0
	locked = false
	hit_flash = 0.0
	_trauma = 0.0
	fire_held = false

func repair(amount: float) -> void:
	integrity = minf(max_integrity, integrity + amount)

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if bot_active or not input_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel := (event as InputEventMouseMotion).relative
		var sens := 0.0022 * (_fov_cur / fov)
		var st := get_node_or_null("/root/Settings")
		if st != null:
			var f: Variant = st.call("get_value", "controls/sensitivity", 1.0)
			sens *= clampf(float(f) if f != null else 1.0, 0.05, 10.0)
			if bool(st.call("get_value", "controls/invert_y", false)):
				rel.y = -rel.y
		aim_yaw -= rel.x * sens
		aim_pitch -= rel.y * sens
		_clamp_aim()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and mb.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				fire_held = mb.pressed
			MOUSE_BUTTON_RIGHT:
				zoomed = mb.pressed

func _clamp_aim() -> void:
	if yaw_limit_deg < 180.0:
		var lim := deg_to_rad(yaw_limit_deg)
		aim_yaw = clampf(wrapf(aim_yaw, -PI, PI), -lim, lim)
	else:
		aim_yaw = wrapf(aim_yaw, -PI, PI)
	aim_pitch = clampf(aim_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))

## Richtwinkel fuer einen Weltpunkt (relativ zum Fahrzeug, ohne Schaukeln). Gibt Vector2(yaw, pitch) zurueck.
func aim_angles_for(p: Vector3) -> Vector2:
	var pivot := global_transform * mount_offset
	var lp := global_transform.basis.inverse() * (p - pivot)
	return Vector2(atan2(-lp.x, -lp.z), atan2(lp.y, Vector2(lp.x, lp.z).length()))

func can_aim_at(p: Vector3) -> bool:
	var a := aim_angles_for(p)
	if yaw_limit_deg < 180.0 and absf(a.x) > deg_to_rad(yaw_limit_deg):
		return false
	return a.y >= deg_to_rad(pitch_min_deg) and a.y <= deg_to_rad(pitch_max_deg)

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	_small_snd_cd -= delta
	_since_hit += delta
	if not bot_active and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		fire_held = false
	_drive(delta)
	_place(delta)
	_weapon_tick(delta)
	if not dead and _since_hit > regen_delay and integrity < max_integrity:
		integrity = minf(max_integrity, integrity + regen_rate * delta)
	hit_flash = maxf(0.0, hit_flash - delta * 1.6)
	hit_dir_t = maxf(0.0, hit_dir_t - delta)
	hitmarker_t = maxf(0.0, hitmarker_t - delta)
	kill_t = maxf(0.0, kill_t - delta)

func _drive(delta: float) -> void:
	if _curve == null:
		return
	var want := target_speed
	if dead:
		want = 0.0
	# Haelte: Bremsweg einhalten, am Halt warten
	for st in _stops:
		var state := int(st["state"])
		if state == 2:
			continue
		var ds := float(st["s"]) - path_s
		if state == 1:
			want = 0.0
			st["t"] = float(st["t"]) + delta
			var until: Callable = st["until"]
			var ok := until.is_valid() and bool(until.call())
			var mw := float(st["max_wait"])
			if ok or (mw > 0.0 and float(st["t"]) >= mw) or (not until.is_valid() and mw <= 0.0):
				st["state"] = 2
				stop_released.emit(str(st["id"]))
			break
		if ds <= 0.4:
			st["state"] = 1
			st["t"] = 0.0
			speed = 0.0
			path_s = maxf(path_s, float(st["s"]) - 0.4)
			want = 0.0
			stop_reached.emit(str(st["id"]))
			break
		want = minf(want, sqrt(2.0 * decel * maxf(ds - 0.3, 0.0)))
		break
	# Pfadende
	var rest := _len - path_s
	want = minf(want, sqrt(2.0 * decel * maxf(rest, 0.0)))
	if speed < want:
		speed = minf(want, speed + accel * delta)
	else:
		speed = maxf(want, speed - decel * 1.4 * delta)
	var prev_s := path_s
	path_s = minf(_len, path_s + speed * delta)
	for tr in _triggers:
		if bool(tr["done"]):
			continue
		var ts := float(tr["s"])
		if ts <= path_s and ts >= prev_s - 0.01:
			tr["done"] = true
			trigger_passed.emit(str(tr["id"]))
			var f: Callable = tr["f"]
			if f.is_valid():
				f.call()
	if rest <= 0.05 and not _end_sent:
		_end_sent = true
		reached_end.emit()

func _place(delta: float) -> void:
	if _curve == null:
		return
	var p := pos_at(path_s)
	var d := dir_at(path_s)
	var yaw := atan2(-d.x, -d.z)
	global_transform = Transform3D(Basis(Vector3.UP, yaw), p)
	if delta > 0.0:
		_yaw_rate = lerpf(_yaw_rate, wrapf(yaw - _prev_yaw, -PI, PI) / delta, 1.0 - exp(-delta * 3.0))
	_prev_yaw = yaw
	# Schaukeln: zwei verstimmte Sinus + Rauschen, Kurvenneigung nach aussen
	var w := TAU * rock_freq
	var sp := clampf(speed / maxf(cruise_speed, 1.0), 0.0, 1.5)
	var calm := lerpf(1.0, 0.75, sp)     # in Fahrt etwas ruhiger, dafuer Stampfen
	var roll := deg_to_rad(rock_roll_deg) * calm * (sin(_t * w) * 0.75 + sin(_t * w * 1.73 + 1.1) * 0.25)
	var pitch := deg_to_rad(rock_pitch_deg) * (sin(_t * w * 0.81 + 0.4) * 0.7 + _noise.get_noise_1d(_t * 9.0) * 0.6 * sp)
	pitch += deg_to_rad(1.2) * sp * 0.6      # Bug hebt sich in Fahrt
	_bank = lerpf(_bank, clampf(-_yaw_rate * speed * deg_to_rad(bank_factor), -0.12, 0.12), 1.0 - exp(-delta * 2.0) if delta > 0.0 else 1.0)
	var bob := bob_amp * (sin(_t * w * 1.13) * 0.7 + _noise.get_noise_1d(_t * 6.0 + 50.0) * 0.5 * sp)
	motion.transform = Transform3D(Basis.from_euler(Vector3(pitch, 0.0, roll + _bank)), Vector3(0, bob, 0))

func _process(delta: float) -> void:
	# Waffe + Kamera (pro Frame, weich)
	_clamp_aim()
	mount_yaw.rotation = Vector3(0, aim_yaw, 0)
	mount_pitch.rotation = Vector3(aim_pitch, 0, 0)
	var want_fov := zoom_fov if zoomed else fov
	_fov_cur = lerpf(_fov_cur, want_fov, 1.0 - exp(-delta * 12.0))
	cam.fov = _fov_cur
	var body := global_transform
	var rocked := body * motion.transform
	var calm := Transform3D(body.basis * motion.transform.basis.slerp(Basis.IDENTITY, clampf(cam_stabilize, 0.0, 1.0)), rocked.origin)
	var aim_b := Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, aim_pitch)
	var pivot := rocked * mount_offset
	var cb := calm.basis * aim_b
	var pos := pivot + cb * eye_offset
	# Kamerawackeln (Trauma^2)
	_trauma = maxf(0.0, _trauma - delta * 1.3)
	var sh := _trauma * _trauma * shake_scale
	var nt := _t * 30.0
	var shake := Basis.from_euler(Vector3(_noise.get_noise_2d(nt, 0) * 0.05 * sh, _noise.get_noise_2d(0, nt) * 0.05 * sh, _noise.get_noise_2d(nt, nt) * 0.04 * sh))
	cam.global_transform = Transform3D((cb * shake).orthonormalized(), pos)
	# Klang
	var sp := clampf(speed / maxf(cruise_speed, 1.0), 0.0, 1.4)
	if _engine != null:
		_engine.pitch_scale = lerpf(0.75, 1.25, sp)
		_engine.volume_db = engine_db + lerpf(-6.0, 0.0, sp)
	if _water != null:
		_water.volume_db = lerpf(-30.0, -8.0, sp)

func _weapon_tick(delta: float) -> void:
	_fire_cd -= delta
	_since_shot += delta
	if _since_shot > float(weapon["cool_delay"]):
		heat = maxf(0.0, heat - float(weapon["cool_rate"]) * delta)
	if locked and heat <= float(weapon["unlock_at"]):
		locked = false
	if dead or not input_enabled:
		return
	if fire_held and not locked:
		var interval := 60.0 / maxf(float(weapon["rpm"]), 1.0)
		while _fire_cd <= 0.0 and not locked:
			_fire_cd += interval
			_fire_round()
	elif _fire_cd < 0.0:
		_fire_cd = 0.0

func _fire_round() -> void:
	shots += 1
	_since_shot = 0.0
	heat = minf(1.0, heat + float(weapon["heat_per_shot"]))
	if heat >= 1.0:
		locked = true
		VF.play_2d(self, "dry_fire", -6.0)
	var spread := deg_to_rad(float(weapon["spread_deg"]))
	var from := cam.global_position
	var b := cam.global_transform.basis
	var dir := (-b.z + b.x * randfn(0.0, spread * 0.6) + b.y * randfn(0.0, spread * 0.6)).normalized()
	var rng_m := float(weapon["range"])
	var to := from + dir * rng_m
	var ex: Array[RID] = get_collision_rids()
	var r := VF.ray(self, from, to, HIT_MASK, ex)
	var end := to if r.is_empty() else (r["position"] as Vector3)
	var te := int(weapon["tracer_every"])
	if te > 0 and shots % te == 0:
		VF.tracer(self, muzzle.global_position, end, 520.0, str(weapon["tracer_color"]), float(weapon["tracer_width"]))
	VF.show_flash(_flash, 0.03)
	var se := maxi(int(weapon["sfx_every"]), 1)
	if shots % se == 0:
		VF.play_2d(self, str(weapon["sfx"]), float(weapon["sfx_db"]), 0.0, &"SFX", randf_range(0.95, 1.05))
	add_trauma(float(weapon["trauma"]))
	Events.weapon_fired.emit(self)
	if r.is_empty():
		return
	var pos: Vector3 = r["position"]
	var nrm: Vector3 = r["normal"]
	var target := _find_damageable(r["collider"])
	if float(weapon["splash_radius"]) > 0.0:
		Combat.explode(pos + nrm * 0.2, float(weapon["splash_radius"]), float(weapon["splash_damage"]), self, 0.2)
	if target == null:
		var surface := "concrete"
		var c: Object = r["collider"]
		if c is Node:
			surface = str((c as Node).get_meta("surface", "concrete"))
		if surface == "water":
			FX.water_hit(self, pos)
		else:
			VFX.spawn_impact(pos, nrm, surface)
		return
	var was_alive := not target.has_method("is_alive") or bool(target.call("is_alive"))
	var armor: Node = target
	if not armor.has_method("armor_deflected") and armor.has_method("get_enemy"):
		armor = target.call("get_enemy") as Node
	if armor != null and armor.has_method("set_shot_dir"):
		armor.call("set_shot_dir", dir)
	target.call("take_damage", float(weapon["damage"]), self, pos, nrm)
	if not target.is_in_group("enemy") and not target.has_method("get_enemy"):
		VFX.spawn_impact(pos, nrm, "metal")
	var enemy_like := target.is_in_group("enemy") or (armor != null and armor.is_in_group("enemy"))
	if enemy_like:
		hitmarker_t = 0.12
		var now_alive := not target.has_method("is_alive") or bool(target.call("is_alive"))
		if armor != null and armor != target and armor.has_method("is_alive"):
			now_alive = bool(armor.call("is_alive"))
		if was_alive and not now_alive:
			kill_t = 0.35

func _find_damageable(n: Object) -> Node:
	var node := n as Node
	var depth := 0
	while node != null and depth < 6:
		if node == self:
			return null
		if node.has_method("take_damage"):
			return node
		node = node.get_parent()
		depth += 1
	return null
