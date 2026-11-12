extends Node3D
## Spieler-Modus "Feuerleitstand" der Gunship "Waechter" (fiktiver A400M-Umbau).
## Kreisflug um ein Zentrum (Phasen verschieben es), bodenstabilisierter Zielpunkt (Maus), drei Waffen mit echter
## Flugzeit, Waermebild-Polaritaet, Zoomstufen, Taeuschkoerper gegen SAM. Steht in Gruppe "player"
## (Autopilot/DebugServer finden ihn); unter --autopilot steuert der eingebaute Bot (autopilot_self_driven()).

signal aircraft_down
signal fired(weapon: int)

const ORBIT_R := 620.0
const ORBIT_H := 760.0
const ORBIT_PERIOD := 105.0
const AIM_RADIUS := 560.0
const ZOOMS := [44.0, 15.0, 5.5]
const ZOOM_NAMES := ["WFOV", "MFOV", "NFOV"]
const SAFE := [8.0, 14.0, 32.0]
const GSUnit := preload("res://game/gunship/gs_unit.gd")   # Gefahrenabstand zu eigenen Leuten je Waffe (m)

var ext: Dictionary = {}
var external_input: bool = false
var world = null
var fx = null
var audio = null
var post_mat: ShaderMaterial = null

var cam: Camera3D
var orbit_center := Vector3(-100, 0, 100)
var orbit_target := Vector3(-100, 0, 100)
var orbit_angle: float = 2.2
var aircraft_pos := Vector3.ZERO
var aim := Vector3(-120, 0, 150)       # bodenstabilisierter Zielpunkt
var aim_hit := Vector3.ZERO            # Treffpunkt des Fadenkreuz-Strahls (inkl. Drift)
var slant_range: float = 0.0
var zoom: int = 1
var sel: int = 1
var black_hot: bool = false
var integrity: float = 100.0
var flare_cd: float = 0.0
var flares_left: int = 24
var flare_flash: float = 0.0
var missile: Dictionary = {}           # aktive Rakete
var missile_warn: bool = false
var hit_glitch: float = 0.0
var input_enabled: bool = true
var weapons_free: bool = true
var danger_close: bool = false
var bot_active: bool = false
var weapons: Array[Dictionary] = []

var _shells: Array[Dictionary] = []
var _slew_to: Vector3 = Vector3.INF
var _slew_left: float = 0.0
var _slew_speed: float = 0.0
var _jit := Vector2.ZERO
var _jit_v := Vector2.ZERO
var _fire_held: bool = false
var _noise := FastNoiseLite.new()
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _down_sent: bool = false
# Bot
var _skill: String = "average"
var _bot_target: GSUnit = null
var _bot_retarget: float = 0.0
var _bot_err := Vector3.ZERO
var _bot_err_t: float = 0.0
var _bot_vel: Dictionary = {}          # unit -> [pos, vel]
var _bot_missile_seen: float = -1.0
var _bot_wait: float = 0.0
var _gun_snd_cd: float = 0.0

func _init() -> void:
	weapons = [
		{"name": "25 MM", "long": "GAU-25", "rate": 0.075, "mag": 200, "ammo": 200, "reload": 3.5, "rt": 0.0, "cd": 0.0,
			"speed": 1050.0, "radius": 3.4, "dmg": 50.0, "disp": 1.9, "size": 0.4},
		{"name": "40 MM", "long": "L/70 BOFORS", "rate": 0.48, "mag": 8, "ammo": 8, "reload": 3.0, "rt": 0.0, "cd": 0.0,
			"speed": 880.0, "radius": 7.5, "dmg": 175.0, "disp": 1.3, "size": 1.0},
		{"name": "105 MM", "long": "M102 HAUBITZE", "rate": 0.0, "mag": 1, "ammo": 1, "reload": 5.0, "rt": 0.0, "cd": 0.0,
			"speed": 500.0, "radius": 17.0, "dmg": 720.0, "disp": 2.0, "size": 2.2},
	]

func _ready() -> void:
	add_to_group("player")
	_rng.seed = 4711
	_noise.frequency = 0.35
	_noise.seed = 9
	cam = Camera3D.new()
	cam.name = "SensorCam"
	cam.near = 2.0
	cam.far = 9000.0
	cam.fov = ZOOMS[zoom]
	add_child(cam)
	cam.make_current()
	bot_active = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_skill = str(Game.arg("skill", "average"))
	if not bot_active and not bool(Game.arg("capture", false)):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_orbit(0.0)

# ------------------------------------------------------------------ Schnittstelle (Autopilot/DebugServer)

func autopilot_self_driven() -> bool:
	return bot_active

func get_camera() -> Camera3D:
	return cam

func get_status() -> Dictionary:
	var w: Dictionary = weapons[sel]
	return {"type": "gunship", "alive": integrity > 0.0, "health": integrity, "max_health": 100.0,
		"ammo_mag": int(w["ammo"]), "reloading": float(w["rt"]) > 0.0, "grenades": 0, "weapon": str(w["name"])}

func set_orbit_center(c: Vector3, slew_aim: Vector3 = Vector3.INF, slew_time: float = 3.0) -> void:
	orbit_target = Vector3(c.x, 0.0, c.z)
	if slew_aim != Vector3.INF:
		slew_aim_to(slew_aim, slew_time)

func slew_aim_to(p: Vector3, t: float = 2.5) -> void:
	_slew_to = Vector3(p.x, 0.0, p.z)
	_slew_speed = maxf(aim.distance_to(_slew_to) / maxf(t, 0.2), 40.0)
	_slew_left = t + 0.5

func repair(to_min: float) -> void:
	integrity = maxf(integrity, to_min)
	_down_sent = false

func launch_missile(from: Vector3) -> void:
	missile = {"pos": from + Vector3(0, 4, 0), "vel": Vector3(0, 60, 0), "t": 0.0, "deflected": false, "decoy": Vector3.ZERO}
	missile_warn = true
	if audio != null:
		audio.play("launch", -4.0)
		audio.loop("warn", true, -8.0)

func refill_all() -> void:
	for w in weapons:
		w["ammo"] = w["mag"]
		w["rt"] = 0.0

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if bot_active or external_input or not input_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_move_aim((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and mb.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
			return
		match mb.button_index:
			MOUSE_BUTTON_RIGHT:
				_set_zoom((zoom + 1) % ZOOMS.size())
			MOUSE_BUTTON_WHEEL_UP:
				_set_zoom(mini(zoom + 1, ZOOMS.size() - 1))
			MOUSE_BUTTON_WHEEL_DOWN:
				_set_zoom(maxi(zoom - 1, 0))
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		match k:
			KEY_1: _select(0)
			KEY_2: _select(1)
			KEY_3: _select(2)
			KEY_Q, KEY_TAB: _select((sel + 1) % 3)
			KEY_F, KEY_SPACE: deploy_flares()
			KEY_T, KEY_N: toggle_polarity()
			KEY_R: _manual_reload()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _select(i: int) -> void:
	if i == sel:
		return
	sel = i
	if audio != null:
		audio.play("switch", -10.0)

func _set_zoom(z: int) -> void:
	if z == zoom:
		return
	zoom = z
	if audio != null:
		audio.play("zoom", -14.0)

func toggle_polarity() -> void:
	black_hot = not black_hot
	if post_mat != null:
		post_mat.set_shader_parameter("black_hot", 1.0 if black_hot else 0.0)
	if audio != null:
		audio.play("switch", -12.0)

func _manual_reload() -> void:
	var w: Dictionary = weapons[sel]
	if int(w["ammo"]) < int(w["mag"]) and float(w["rt"]) <= 0.0:
		w["rt"] = float(w["reload"])
		w["ammo"] = 0

func _move_aim(rel: Vector2) -> void:
	var vh := get_viewport().get_visible_rect().size.y
	var mpp := 2.0 * slant_range * tan(deg_to_rad(cam.fov) * 0.5) / maxf(vh, 1.0)
	var cb := cam.global_transform.basis
	var right := Vector3(cb.x.x, 0, cb.x.z).normalized()
	var up := Vector3(cb.y.x, 0, cb.y.z).normalized()
	var dep := maxf(0.3, asin(clampf(cb.z.y, -1.0, 1.0)))
	var sens := 0.9
	# Optionen (Settings, Runde 6): Mausempfindlichkeit und Y-Invertierung; Standard = bisheriges Verhalten
	var st := get_node_or_null("/root/Settings")
	if st != null:
		var f = st.call("get_value", "controls/sensitivity", 1.0)
		sens *= clampf(float(f) if f != null else 1.0, 0.05, 10.0)
		if bool(st.call("get_value", "controls/invert_y", false)):
			rel.y = -rel.y
	aim += right * rel.x * mpp * sens - up * rel.y * mpp * sens / sin(dep)
	_slew_to = Vector3.INF

func deploy_flares() -> void:
	if flare_cd > 0.0 or flares_left <= 0:
		return
	flare_cd = 4.0
	flares_left -= 1
	flare_flash = 1.0
	if audio != null:
		audio.play("flare", -3.0)
	# Taeuschkoerper: gleissende Punkte, die vor der Optik nach unten/hinten wegfallen
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	for i in 14:
		var p := cam.global_position + fwd * _rng.randf_range(60.0, 220.0) + right * _rng.randf_range(-40.0, 40.0) + Vector3(0, _rng.randf_range(-10.0, 20.0), 0)
		var v := Vector3(_rng.randf_range(-15, 15), _rng.randf_range(-10, 5), _rng.randf_range(-15, 15)) - fwd * 25.0
		fx.glow(p, _rng.randf_range(4.0, 8.0), 3.2, _rng.randf_range(1.4, 2.6), v, 0.0, 9.0)
	if not missile.is_empty() and not bool(missile["deflected"]):
		missile["deflected"] = true
		missile["decoy"] = aircraft_pos + Vector3(_rng.randf_range(-80, 80), -140.0, _rng.randf_range(-80, 80))

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	_update_orbit(delta)
	if world != null:
		world.aircraft_pos = aircraft_pos
	if bot_active and input_enabled:
		_bot(delta)
	elif not external_input and input_enabled:
		_fire_held = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	elif not input_enabled:
		_fire_held = false
	_update_weapons(delta)
	_update_shells(delta)
	_update_missile(delta)
	_update_cam(delta)
	if world != null and world.flak_hits > 0.0:
		var fh: float = world.flak_hits
		world.flak_hits = 0.0
		integrity -= fh
		if fh > 0.0 and _rng.randf() < 0.03:
			hit_glitch = maxf(hit_glitch, 0.25)
	flare_cd = maxf(0.0, flare_cd - delta)
	flare_flash = maxf(0.0, flare_flash - delta * 1.5)
	hit_glitch = maxf(0.0, hit_glitch - delta * 0.9)
	if integrity <= 0.0 and not _down_sent:
		integrity = 0.0
		_down_sent = true
		aircraft_down.emit()

func _update_orbit(delta: float) -> void:
	orbit_center = orbit_center.move_toward(orbit_target, 28.0 * delta)
	orbit_angle += TAU / ORBIT_PERIOD * delta
	aircraft_pos = orbit_center + Vector3(cos(orbit_angle) * ORBIT_R, ORBIT_H, sin(orbit_angle) * ORBIT_R)
	position = aircraft_pos
	if _slew_to != Vector3.INF:
		aim = aim.move_toward(_slew_to, _slew_speed * delta)
		_slew_left -= delta
		if aim.distance_to(_slew_to) < 0.5 or _slew_left <= 0.0:
			_slew_to = Vector3.INF
	var off := aim - orbit_center
	off.y = 0.0
	if off.length() > AIM_RADIUS:
		aim = orbit_center + off.normalized() * AIM_RADIUS
	aim.y = 0.0

func _update_cam(delta: float) -> void:
	cam.fov = lerpf(cam.fov, ZOOMS[zoom], minf(1.0, delta * 9.0))
	cam.global_transform = Transform3D(Basis(), aircraft_pos)
	cam.look_at(aim, Vector3.UP)
	# Optik-Drift (Kreisel/Turbulenz) proportional zum Bildwinkel + Rueckstoss-Zittern
	var fr := deg_to_rad(cam.fov)
	var dx := _noise.get_noise_2d(_t * 0.6, 0.0) * fr * 0.006 + _jit.x
	var dy := _noise.get_noise_2d(0.0, _t * 0.6 + 40.0) * fr * 0.006 + _jit.y
	cam.rotate_object_local(Vector3.UP, dx)
	cam.rotate_object_local(Vector3.RIGHT, dy)
	_jit_v = _jit_v.lerp(Vector2.ZERO, minf(1.0, delta * 10.0))
	_jit += _jit_v * delta
	_jit = _jit.lerp(Vector2.ZERO, minf(1.0, delta * 6.0))
	if fx != null:
		fx.cam = cam
	# Zielstrahl
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	aim_hit = _raycast(from, dir)
	slant_range = from.distance_to(aim_hit)
	danger_close = false
	if world != null:
		for u in world.team_alive():
			if (u as Node3D).global_position.distance_to(aim_hit) < float(SAFE[sel]) * 1.4:
				danger_close = true
				break
	if post_mat != null:
		post_mat.set_shader_parameter("glitch", clampf(hit_glitch, 0.0, 1.0))
		post_mat.set_shader_parameter("jitter", Vector2(_jit.x, _jit.y) * 0.0)

func _raycast(from: Vector3, dir: Vector3) -> Vector3:
	var best := INF
	var hit := Vector3.ZERO
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 6000.0, 1)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		hit = r["position"]
		best = from.distance_to(hit)
	elif dir.y < -0.01:
		var t := -from.y / dir.y
		hit = from + dir * t
		best = t
	else:
		hit = from + dir * 3000.0
	if world != null:
		for u in world.units:
			var un: GSUnit = u
			if not un.alive or un.state == "ride":
				continue
			var c: Vector3 = un.hit_center()
			var rr: float = un.hit_r * (0.75 if un.is_infantry() else 0.8)
			var oc := from - c
			var b := oc.dot(dir)
			var cc := oc.dot(oc) - rr * rr
			var disc := b * b - cc
			if disc < 0.0:
				continue
			var t2 := -b - sqrt(disc)
			if t2 > 0.0 and t2 < best:
				best = t2
				hit = from + dir * t2
	return hit

func _update_weapons(delta: float) -> void:
	for i in weapons.size():
		var w: Dictionary = weapons[i]
		w["cd"] = maxf(0.0, float(w["cd"]) - delta)
		if float(w["rt"]) > 0.0:
			w["rt"] = float(w["rt"]) - delta
			if float(w["rt"]) <= 0.0:
				w["rt"] = 0.0
				w["ammo"] = w["mag"]
				if audio != null and i == sel:
					audio.play("reload_done", -8.0 if i < 2 else -4.0)
	_gun_snd_cd -= delta
	if not _fire_held or not weapons_free:
		if audio != null:
			audio.loop("gatling", false)
		return
	var w2: Dictionary = weapons[sel]
	if float(w2["rt"]) > 0.0 or int(w2["ammo"]) <= 0 or float(w2["cd"]) > 0.0:
		if audio != null and sel == 0:
			audio.loop("gatling", false)
		return
	_fire(sel)
	if sel == 2:
		_fire_held = false

func _fire(i: int) -> void:
	var w: Dictionary = weapons[i]
	w["ammo"] = int(w["ammo"]) - 1
	w["cd"] = float(w["rate"])
	if int(w["ammo"]) <= 0:
		w["rt"] = float(w["reload"])
		if audio != null:
			audio.play("reload", -10.0 if i < 2 else -6.0)
	var dir := -cam.global_transform.basis.z
	var hit := _raycast(cam.global_position, dir)
	var disp := float(w["disp"])
	var ang := _rng.randf() * TAU
	var rad := disp * sqrt(-2.0 * log(maxf(_rng.randf(), 0.0001))) * 0.6
	hit += Vector3(cos(ang) * rad, 0, sin(ang) * rad)
	var gun := aircraft_pos + Vector3(0, -3, 0)
	var dist := gun.distance_to(hit)
	var tt := dist / float(w["speed"])
	_shells.append({"from": gun, "to": hit, "t": 0.0, "T": tt, "w": i})
	match i:
		0:
			_jit_v += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.004
			if audio != null:
				audio.loop("gatling", true, -2.0)
		1:
			_jit_v += Vector2(_rng.randf_range(-1, 1), 1.0) * 0.012
			if audio != null:
				audio.play("gun40", -2.0)
		2:
			_jit_v += Vector2(_rng.randf_range(-0.5, 0.5), 1.0) * 0.045
			hit_glitch = maxf(hit_glitch, 0.12)
			if audio != null:
				audio.play("gun105", 0.0)
	Events.weapon_fired.emit(self)
	fired.emit(i)

func _update_shells(delta: float) -> void:
	var i := 0
	while i < _shells.size():
		var s: Dictionary = _shells[i]
		s["t"] = float(s["t"]) + delta
		var k := float(s["t"]) / float(s["T"])
		var w := int(s["w"])
		if k >= 1.0:
			_shells.remove_at(i)
			_impact(w, s["to"])
			continue
		if k > 0.3 and fx != null:
			var a: Vector3 = (s["from"] as Vector3).lerp(s["to"], k)
			match w:
				0:
					var b: Vector3 = (s["from"] as Vector3).lerp(s["to"], maxf(0.0, k - 0.018))
					fx.streak(b, a, 0.17, 1.5, 0.0, 0.65)
				1:
					fx.glow(a, 1.6, 1.8)
				2:
					fx.glow(a, 2.4, 2.0)
		i += 1

func _impact(w: int, p: Vector3) -> void:
	var wd: Dictionary = weapons[w]
	if fx != null:
		fx.explosion(p, float(wd["size"]), w == 2)
	if world != null:
		world.blast(p, float(wd["radius"]), float(wd["dmg"]), w, true)
	Events.explosion.emit(p, float(wd["radius"]), float(wd["dmg"]) / 700.0)
	if audio != null and w > 0:
		audio.play("impact105" if w == 2 else "impact40", -10.0 if w == 2 else -18.0, slant_range / 343.0 * 0.35)
	if w == 2:
		_jit_v += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 0.004

func _update_missile(delta: float) -> void:
	if missile.is_empty():
		return
	missile["t"] = float(missile["t"]) + delta
	var pos: Vector3 = missile["pos"]
	var tgt: Vector3 = missile["decoy"] if bool(missile["deflected"]) else aircraft_pos
	var vel: Vector3 = missile["vel"]
	var spd := minf(60.0 + float(missile["t"]) * 90.0, 190.0)
	vel = vel.lerp((tgt - pos).normalized() * spd, minf(1.0, delta * 2.5))
	pos += vel * delta
	missile["pos"] = pos
	missile["vel"] = vel
	if fx != null:
		fx.glow(pos, 3.5, 3.2)
		fx.glow(pos - vel.normalized() * 2.0, 2.0, 0.9, 3.2, Vector3(0.6, 0.6, 0.2), 1.5, 0.0, 0.5)
	var d := pos.distance_to(tgt)
	if d < 16.0 or float(missile["t"]) > 20.0:
		var defl := bool(missile["deflected"])
		missile = {}
		missile_warn = false
		if audio != null:
			audio.loop("warn", false)
		if defl:
			if fx != null:
				fx.glow(pos, 30.0, 3.0, 0.25, Vector3.ZERO, 60.0)
			if audio != null:
				audio.play("impact40", -16.0)
		else:
			integrity -= 42.0
			hit_glitch = 1.0
			_jit_v += Vector2(0.06, 0.04)
			if audio != null:
				audio.play("hit", 0.0)
			Events.player_damaged.emit(42.0, null)

# ------------------------------------------------------------------ Bot (unter --autopilot)

func _bot(delta: float) -> void:
	var prof := _bot_profile()
	# Taeuschkoerper nach Reaktionszeit
	if not missile.is_empty() and not bool(missile["deflected"]):
		if _bot_missile_seen < 0.0:
			_bot_missile_seen = _t
		if _t - _bot_missile_seen > float(prof["react"]):
			deploy_flares()
	else:
		_bot_missile_seen = -1.0
	_fire_held = false
	if world == null:
		return
	# Geschwindigkeiten schaetzen
	_bot_retarget -= delta
	if _bot_retarget <= 0.0 or _bot_target == null or not is_instance_valid(_bot_target) or not bool(_bot_target.get("alive")):
		_bot_retarget = 0.5
		var nt := _bot_pick()
		if nt != _bot_target:
			_bot_target = nt
			_bot_wait = float(prof["react"]) * 0.5
	_bot_track(delta)
	if _bot_target != null:
		_slew_to = Vector3.INF
	if _bot_target == null:
		var fc: Vector3 = world.team_center() if not world.team_alive().is_empty() else orbit_center
		aim = aim.move_toward(fc, float(prof["slew"]) * 0.5 * delta)
		zoom = 1
		return
	_bot_wait -= delta
	var u := _bot_target
	var wsel := _bot_weapon(u)
	if wsel < 0:
		_bot_target = null
		return
	sel = wsel
	var w: Dictionary = weapons[sel]
	var tof := (aircraft_pos.distance_to(u.global_position)) / float(w["speed"])
	var vel: Vector3 = (_bot_vel.get(u, [u.global_position, Vector3.ZERO]) as Array)[1]
	_bot_err_t -= delta
	if _bot_err_t <= 0.0:
		_bot_err_t = _rng.randf_range(1.0, 2.0)
		var e := float(prof["err"])
		_bot_err = Vector3(_rng.randf_range(-e, e), 0, _rng.randf_range(-e, e))
	var want: Vector3 = u.global_position + vel * tof * float(prof["lead"]) + _bot_err
	want.y = 0.0
	var dist := aim.distance_to(want)
	aim = aim.move_toward(want, (float(prof["slew"]) + dist * 2.0) * delta)
	zoom = 1 if dist < 60.0 else 0
	if u.kind == "inf" and dist < 20.0 and _skill != "novice":
		zoom = 2 if sel == 0 else 1
	# Feuer, wenn nah genug und sicher
	var tol := maxf(float(w["radius"]) * 0.55, 2.0)
	if dist < tol and _bot_wait <= 0.0 and _bot_safe(want, sel):
		_fire_held = true

func _bot_profile() -> Dictionary:
	match _skill:
		"novice":
			return {"react": 2.6, "err": 3.4, "slew": 140.0, "lead": 0.75}
		"veteran":
			return {"react": 0.8, "err": 1.0, "slew": 320.0, "lead": 1.0}
	return {"react": 1.4, "err": 2.0, "slew": 220.0, "lead": 0.92}

func _bot_track(delta: float) -> void:
	if delta <= 0.0:
		return
	var seen := {}
	for u in world.units:
		var un: GSUnit = u
		if not un.alive or un.side != "reich":
			continue
		var p := un.global_position
		if _bot_vel.has(un):
			var a: Array = _bot_vel[un]
			var v := (p - (a[0] as Vector3)) / delta
			a[1] = (a[1] as Vector3).lerp(v, 0.15)
			a[0] = p
		else:
			_bot_vel[un] = [p, Vector3.ZERO]
		seen[un] = true
	for k in _bot_vel.keys():
		if not seen.has(k):
			_bot_vel.erase(k)

func _bot_pick() -> GSUnit:
	var best: GSUnit = null
	var bs := -1.0
	var tc: Vector3 = world.team_center()
	var has_team: bool = not world.team_alive().is_empty()
	for u in world.units:
		var un: GSUnit = u
		if not un.alive or un.side != "reich":
			continue
		var off := un.global_position - orbit_center
		off.y = 0.0
		if off.length() > AIM_RADIUS - 5.0:
			continue
		var pr := 3.0
		match un.kind:
			"sam": pr = 9.0
			"flak": pr = 8.0 if un.flak_active else 4.0
			"jet": pr = 11.0 if un.taxiing else 5.0
			"tank", "apc": pr = 7.5
			"jeep", "truck", "bowser": pr = 6.0
			"radar", "fuel": pr = 5.0
			"inf": pr = 4.0
		if un.state == "move" and un.is_vehicle():
			pr += 2.5
		if has_team and un.global_position.distance_to(tc) < 120.0:
			pr += 2.0
		if not un.required:
			pr -= 2.5
		var d := aim.distance_to(un.global_position)
		var sc := pr / (1.0 + d / 160.0)
		if sc > bs and _bot_weapon(un) >= 0:
			bs = sc
			best = un
	return best

func _bot_weapon(u: GSUnit) -> int:
	var order: Array = [1, 0, 2]
	match u.kind:
		"inf":
			var n := 0
			for o in world.units:
				var on: GSUnit = o
				if on.alive and on.side == "reich" and on.is_infantry() and on.global_position.distance_to(u.global_position) < 9.0:
					n += 1
			order = [1, 0, 2] if n >= 3 else [0, 1, 2]
		"tank", "apc":
			order = [2, 1]
		"sam", "radar", "fuel":
			order = [2, 1, 0]
		"flak", "jeep", "truck", "bowser", "jet":
			order = [1, 2, 0]
	for wi in order:
		var w: Dictionary = weapons[wi]
		if float(w["rt"]) > 0.0 and not (wi == 2 and float(w["rt"]) < 1.5):
			continue
		if _bot_safe(u.global_position, wi):
			return wi
	return -1

func _bot_safe(p: Vector3, wi: int) -> bool:
	for t in world.team_alive():
		if (t as Node3D).global_position.distance_to(p) < float(SAFE[wi]):
			return false
	return true
