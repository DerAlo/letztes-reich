extends AnimatableBody3D
## Spielbarer Schuetzenpanzer "Rabe" (Mission spreebogen). Voss faehrt einen festen Pfad, Kerner sitzt am Turm.
## Waffen: 30-mm-Maschinenkanone (Sprenggranaten, Magazin 40, Nachladen), Koax-MG (Ueberhitzung),
## Nebelwurfanlage (3 Salven, laedt nach). Turmoptik mit drei Zoomstufen, Schadensanzeige je Seite.
## Ersetzt waehrend der Fahrt den Player: Gruppe "player", get_camera(), take_damage(), get_status(),
## autopilot_self_driven() (Bot: ifv_bot.gd unter --autopilot).
##
## Steuerung: Maus = Turm richten, LMB = Feuer, RMB/Mausrad = Zoom, 1/2/Q = Waffe, R = Nachladen,
## F/Leertaste = Nebel, ESC = Pause.

signal ifv_destroyed
signal hit_taken(amount: float, zone: int)

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const Model := preload("res://game/vehicles/ifv/ifv_model.gd")
const HudScript := preload("res://game/vehicles/ifv/ifv_hud.gd")
const BotScript := preload("res://game/vehicles/ifv/ifv_bot.gd")

const ZOOMS: Array[float] = [60.0, 26.0, 10.0]
const YAW_RATE := 1.9            ## rad/s Turmschwenk
const PITCH_RATE := 1.2
const PITCH_MIN := -0.16
const PITCH_MAX := 0.95

const MK_MAG := 40
const MK_INTERVAL := 0.21
const MK_RELOAD := 4.0
const MK_SPEED := 850.0
const MK_RADIUS := 3.3
const MK_DAMAGE := 62.0
const MK_DIRECT := 45.0
const MK_SPREAD := 0.12          ## Grad

const MG_INTERVAL := 0.075
const MG_DAMAGE := 21.0
const MG_HEAT := 0.028
const MG_COOL := 0.3
const MG_UNLOCK := 0.35
const MG_SPREAD := 0.35

const SMOKE_CHARGES := 3
const SMOKE_RECHARGE := 28.0
const SMOKE_TIME := 15.0

const ZONE_NAMES := ["FRONT", "LINKS", "RECHTS", "HECK"]
const HIT_MASK := 1 | 4

var path: Array[Vector3] = []
var _cum: Array[float] = []
var path_s: float = 0.0
var target_s: float = 0.0
var speed: float = 0.0
var max_speed: float = 5.5
var hull_yaw: float = 0.0

var aim_yaw: float = 0.0          ## gewuenschte Richtung (Welt, stabilisiert)
var aim_pitch: float = 0.0
var tur_yaw: float = 0.0          ## tatsaechliche Turmrichtung (Welt)
var tur_pitch: float = 0.0

var weapon: int = 0               ## 0 = Kanone, 1 = Koax-MG
var mk_ammo: int = MK_MAG
var mk_reload_t: float = 0.0
var mk_cd: float = 0.0
var mg_heat: float = 0.0
var mg_locked: bool = false
var mg_cd: float = 0.0
var _mg_count: int = 0
var smoke_charges: int = SMOKE_CHARGES
var smoke_recharge_t: float = 0.0
var smoke_t: float = 0.0
var smoke_clouds: Array[Vector3] = []

var integrity: float = 100.0
var zone_dmg: Array[float] = [0.0, 0.0, 0.0, 0.0]
var dead: bool = false
var invulnerable: bool = false
var input_enabled: bool = true
var weapons_free: bool = true
var fire_held: bool = false
var zoom: int = 0
var bot_active: bool = false
var is_crouching: bool = false
var hit_flash: float = 0.0
var rocket_warn: float = 0.0
var rocket_from: Vector3 = Vector3.ZERO
var extra_targets: Array[Node3D] = []   ## Ziele ausserhalb der Gruppe "enemy" (Panzer, Sperre) fuer Bot/HUD
var status_text: String = ""

var parts: Dictionary = {}
var cam: Camera3D
var hud: CanvasLayer
var bot: Node
var _model: Node3D
var _trauma: float = 0.0
var _t: float = 0.0
var _recoil: float = 0.0
var _noise := FastNoiseLite.new()
var _engine: AudioStreamPlayer3D
var _tracks: AudioStreamPlayer3D
var _turret_snd: AudioStreamPlayer3D
var _exhaust: GPUParticles3D
var _last_speed: float = 0.0
var _small_snd_cd: float = 0.0

func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = VF.LAYER_PLAYER
	collision_mask = 0
	sync_to_physics = false
	set_meta("surface", "metal")
	_model = Node3D.new()
	_model.name = "Model"
	add_child(_model)
	parts = Model.build(_model)
	for s: Array in Model.shapes():
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s[1]
		cs.shape = bs
		cs.position = s[0]
		add_child(cs)
	cam = Camera3D.new()
	cam.name = "Optic"
	cam.near = 0.08
	cam.far = 1500.0
	cam.fov = ZOOMS[0]
	(parts["cam_pivot"] as Node3D).add_child(cam)
	cam.make_current()
	_noise.frequency = 0.6
	_noise.seed = 31
	_engine = VF.loop_player(self, "veh_tank_engine", 10.0, 200.0, -10.0)
	_tracks = VF.loop_player(self, "veh_tank_tracks", 10.0, 200.0, -40.0)
	_turret_snd = VF.loop_player(self, "veh_tank_turret", 6.0, 60.0, -60.0)
	_build_exhaust()
	bot_active = bool(Game.arg("autopilot", false))
	if not bot_active and not bool(Game.arg("capture", false)):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud = HudScript.new()
	hud.name = "IfvHud"
	hud.set("ifv", self)
	add_child(hud)
	if bot_active:
		bot = BotScript.new()
		bot.name = "IfvBot"
		bot.set("ifv", self)
		add_child(bot)

# ------------------------------------------------------------------ Schnittstelle

func autopilot_self_driven() -> bool:
	return bot_active

func get_camera() -> Camera3D:
	return cam

func is_alive() -> bool:
	return not dead

func get_status() -> Dictionary:
	return {"type": "ifv", "alive": not dead, "health": integrity, "max_health": 100.0,
		"ammo_mag": mk_ammo if weapon == 0 else int((1.0 - mg_heat) * 100.0), "reloading": mk_reload_t > 0.0,
		"grenades": smoke_charges, "weapon": "MK 30mm" if weapon == 0 else "Koax-MG"}

func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)

## Pfad setzen (Weltpunkte, y = Boden). Position springt an den Anfang.
func set_path(points: Array[Vector3]) -> void:
	path = points.duplicate()
	_cum.clear()
	var acc := 0.0
	for i in path.size():
		if i > 0:
			acc += path[i - 1].distance_to(path[i])
		_cum.append(acc)
	reset_to(0.0)

func path_length() -> float:
	return _cum[_cum.size() - 1] if not _cum.is_empty() else 0.0

## Pfadlaenge bis zur ersten Stelle mit dieser z-Koordinate (Pfad laeuft nach -Z).
func s_for_z(z: float) -> float:
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		if (a.z - z) * (b.z - z) <= 0.0 and absf(b.z - a.z) > 0.001:
			var k := (z - a.z) / (b.z - a.z)
			return _cum[i - 1] + a.distance_to(b) * k
	return path_length()

func drive_to_z(z: float, spd: float = 5.5) -> void:
	target_s = clampf(s_for_z(z), 0.0, path_length())
	max_speed = spd

func arrived() -> bool:
	return absf(target_s - path_s) < 0.35 and speed < 0.3

func moving() -> bool:
	return speed > 0.3

func reset_to(s: float) -> void:
	path_s = clampf(s, 0.0, path_length())
	target_s = path_s
	speed = 0.0
	var d := _dir_at(path_s + 2.0)
	hull_yaw = atan2(-d.x, -d.z)
	tur_yaw = hull_yaw
	aim_yaw = hull_yaw
	tur_pitch = 0.0
	aim_pitch = 0.0
	global_transform = Transform3D(Basis(Vector3.UP, hull_yaw), _pos_at(path_s))

func repair(to_min: float) -> void:
	integrity = maxf(integrity, to_min)
	for i in 4:
		zone_dmg[i] = minf(zone_dmg[i], (100.0 - integrity) / 100.0 + 0.1)

func refit() -> void:
	integrity = 100.0
	dead = false
	for i in 4:
		zone_dmg[i] = 0.0
	mk_ammo = MK_MAG
	mk_reload_t = 0.0
	mg_heat = 0.0
	mg_locked = false
	smoke_charges = SMOKE_CHARGES
	smoke_t = 0.0
	smoke_clouds.clear()

func smoke_active() -> bool:
	return smoke_t > 0.0

## Ist pos in einer der aktiven Nebelwolken (oder liegt die Linie from->pos darin)?
func in_smoke(pos: Vector3) -> bool:
	if smoke_t <= 0.0:
		return false
	for c in smoke_clouds:
		if Vector2(c.x - pos.x, c.z - pos.z).length() < 9.0:
			return true
	return smoke_t > 2.0 and pos.distance_to(global_position) < 12.0

## Warnung vor einer anfliegenden Panzerfaust (fuer HUD und Bot).
func warn_rocket(from: Vector3) -> void:
	rocket_warn = 2.2
	rocket_from = from

func select_weapon(i: int) -> void:
	if i == weapon:
		return
	weapon = clampi(i, 0, 1)
	VF.play_2d(self, "gunship_switch", -12.0)

func set_zoom(z: int) -> void:
	z = clampi(z, 0, ZOOMS.size() - 1)
	if z == zoom:
		return
	zoom = z
	VF.play_2d(self, "gunship_zoom", -10.0)

func manual_reload() -> void:
	if mk_reload_t <= 0.0 and mk_ammo < MK_MAG:
		_start_reload()

func zone_of(world_pos: Vector3) -> int:
	var l := global_transform.affine_inverse() * world_pos
	if absf(l.z) > absf(l.x) * 1.7:
		return 0 if l.z < 0.0 else 3
	return 1 if l.x < 0.0 else 2

# ------------------------------------------------------------------ Schaden

func take_damage(amount: float, source: Node, hit_position: Vector3, _hit_normal: Vector3) -> void:
	if dead or amount <= 0.0 or source == self:
		return
	var mult := 0.03
	if bool(Combat.get("explosion_active")):
		mult = 0.4
	elif source != null and is_instance_valid(source) and source.is_in_group("vehicle"):
		mult = 0.16
	if smoke_t > 0.0 and not bool(Combat.get("explosion_active")):
		mult *= 0.5
	apply_damage(amount * mult, hit_position, source)

## Panzerfaust-Treffer (ifv_rocket.gd).
func rocket_hit_ifv(dmg: float, pos: Vector3, source: Node) -> void:
	apply_damage(dmg, pos, source)
	add_trauma(0.7)
	VF.play_2d(self, "impact_metal_3", 2.0)
	VF.play_2d(self, "gunship_hit", -2.0)

func apply_damage(d: float, pos: Vector3, source: Node = null) -> void:
	if dead or d <= 0.0:
		return
	var z := zone_of(pos)
	zone_dmg[z] = minf(1.0, zone_dmg[z] + d / 30.0)
	if invulnerable:
		d = minf(d, maxf(integrity - 5.0, 0.0))
	integrity = maxf(0.0, integrity - d)
	hit_flash = minf(1.0, hit_flash + clampf(d / 8.0, 0.08, 1.0))
	add_trauma(clampf(d / 25.0, 0.02, 0.5))
	if d >= 1.0 or _small_snd_cd <= 0.0:
		_small_snd_cd = 0.25
		VF.play_2d(self, ["impact_metal", "impact_metal_2", "impact_metal_3"][randi() % 3], -14.0 + minf(d, 12.0), 0.0, &"SFX", randf_range(0.9, 1.1))
	hit_taken.emit(d, z)
	Events.player_damaged.emit(d, source)
	if integrity <= 0.0:
		dead = true
		fire_held = false
		ifv_destroyed.emit()

## Combat.explode: Trefferpunkte rund um Wanne und Turm.
func get_damage_points() -> Array[Vector3]:
	var b := global_transform
	return [b * Vector3(0, 1.3, 0), b * Vector3(0, 1.2, -3.2), b * Vector3(0, 1.2, 3.3),
		b * Vector3(-1.7, 1.1, 0), b * Vector3(1.7, 1.1, 0), b * Vector3(0, 2.4, -0.3)]

func get_collision_rids() -> Array[RID]:
	return [get_rid()]

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if bot_active or not input_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel := (event as InputEventMouseMotion).relative
		var sens := 0.0022 * (cam.fov / ZOOMS[0])
		var st := get_node_or_null("/root/Settings")
		if st != null:
			var f: Variant = st.call("get_value", "controls/sensitivity", 1.0)
			sens *= clampf(float(f) if f != null else 1.0, 0.05, 10.0)
			if bool(st.call("get_value", "controls/invert_y", false)):
				rel.y = -rel.y
		aim_yaw -= rel.x * sens
		aim_pitch = clampf(aim_pitch - rel.y * sens, PITCH_MIN, PITCH_MAX)
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
				if mb.pressed:
					set_zoom((zoom + 1) % ZOOMS.size())
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					set_zoom(zoom + 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					set_zoom(zoom - 1)
	elif event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).physical_keycode:
			KEY_1: select_weapon(0)
			KEY_2: select_weapon(1)
			KEY_Q, KEY_TAB: select_weapon(1 - weapon)
			KEY_R: manual_reload()
			KEY_F, KEY_SPACE: launch_smoke()

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	_small_snd_cd -= delta
	if not bot_active and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		fire_held = false
	_drive(delta)
	_aim(delta)
	_weapons(delta)
	_effects(delta)

func _drive(delta: float) -> void:
	if path.size() < 2:
		return
	var rest := target_s - path_s
	var want := clampf(rest * 0.7, 0.0, max_speed) if not dead else 0.0
	var acc := 1.8 if want > speed else 3.5
	speed = move_toward(speed, want, acc * delta)
	path_s = minf(path_s + speed * delta, maxf(target_s, path_s))
	var d := _dir_at(path_s + 3.0)
	var want_yaw := atan2(-d.x, -d.z)
	var prev_yaw := hull_yaw
	hull_yaw = lerp_angle(hull_yaw, want_yaw, clampf(delta * 1.6, 0.0, 1.0))
	global_transform = Transform3D(Basis(Vector3.UP, hull_yaw), _pos_at(path_s))
	# Wanne nickt beim Anfahren/Bremsen, leichtes Rattern
	var dv := (speed - _last_speed) / maxf(delta, 0.001)
	_last_speed = speed
	_model.rotation.x = lerpf(_model.rotation.x, clampf(dv * 0.012, -0.05, 0.05), clampf(delta * 4.0, 0.0, 1.0))
	_model.position.y = sin(_t * 23.0) * 0.006 * minf(speed, 4.0) + _noise.get_noise_1d(_t * 40.0) * 0.008 * minf(speed, 4.0)
	_model.rotation.z = (hull_yaw - prev_yaw) / maxf(delta, 0.001) * -0.02
	var roll := speed * delta / 0.34
	for k in ["wheels_l", "wheels_r"]:
		for w: Node3D in parts.get(k, []):
			w.rotation.x -= roll
	if _engine:
		_engine.pitch_scale = 0.8 + speed * 0.07
		_engine.volume_db = -11.0 + minf(speed, 5.0) * 1.2
	if _tracks:
		_tracks.volume_db = lerpf(-40.0, -6.0, clampf(speed / 3.0, 0.0, 1.0))
		_tracks.pitch_scale = 0.8 + speed * 0.06

func _aim(delta: float) -> void:
	var dy := wrapf(aim_yaw - tur_yaw, -PI, PI)
	var step := YAW_RATE * delta
	tur_yaw += clampf(dy, -step, step)
	tur_pitch = move_toward(tur_pitch, aim_pitch, PITCH_RATE * delta)
	(parts["turret"] as Node3D).rotation.y = wrapf(tur_yaw - hull_yaw, -PI, PI)
	(parts["mantlet"] as Node3D).rotation.x = tur_pitch
	(parts["cam_pivot"] as Node3D).rotation.x = tur_pitch
	if _turret_snd:
		var sw := absf(clampf(dy, -step, step)) / maxf(step, 0.0001)
		_turret_snd.volume_db = lerpf(-60.0, -14.0, clampf(sw * 1.5, 0.0, 1.0))
	cam.fov = lerpf(cam.fov, ZOOMS[zoom], clampf(delta * 10.0, 0.0, 1.0))
	# Kamera-Shake (Rueckstoss, Treffer)
	_trauma = maxf(0.0, _trauma - delta * 1.4)
	var sh := _trauma * _trauma
	cam.h_offset = _noise.get_noise_2d(_t * 50.0, 0.0) * 0.06 * sh
	cam.v_offset = _noise.get_noise_2d(0.0, _t * 50.0) * 0.06 * sh
	cam.rotation.z = _noise.get_noise_2d(_t * 30.0, 7.0) * 0.03 * sh

func _weapons(delta: float) -> void:
	mk_cd -= delta
	mg_cd -= delta
	if mk_reload_t > 0.0:
		mk_reload_t -= delta
		if mk_reload_t <= 0.0:
			mk_ammo = MK_MAG
			VF.play_2d(self, "gunship_reload_done", -6.0)
	mg_heat = maxf(0.0, mg_heat - MG_COOL * delta * (1.6 if mg_locked else 1.0))
	if mg_locked and mg_heat <= MG_UNLOCK:
		mg_locked = false
	if smoke_charges < SMOKE_CHARGES:
		smoke_recharge_t -= delta
		if smoke_recharge_t <= 0.0:
			smoke_charges += 1
			smoke_recharge_t = SMOKE_RECHARGE
	if smoke_t > 0.0:
		smoke_t -= delta
		if smoke_t <= 0.0:
			smoke_clouds.clear()
	rocket_warn = maxf(0.0, rocket_warn - delta)
	hit_flash = maxf(0.0, hit_flash - delta * 1.6)
	_recoil = move_toward(_recoil, 0.0, delta * 6.0)
	(parts["barrel"] as Node3D).position.z = 0.16 * _recoil
	if dead or not weapons_free or not fire_held:
		return
	if weapon == 0:
		if mk_cd <= 0.0 and mk_reload_t <= 0.0 and mk_ammo > 0:
			_fire_mk()
	else:
		if mg_cd <= 0.0 and not mg_locked:
			_fire_mg()

func _effects(_delta: float) -> void:
	if _exhaust:
		_exhaust.amount_ratio = clampf(0.3 + speed * 0.15, 0.2, 1.0)

# ------------------------------------------------------------------ Waffen

func _aim_ray(spread_deg: float, max_range: float) -> Dictionary:
	var origin := cam.global_position
	var b := cam.global_basis
	var dir := -b.z
	if spread_deg > 0.0:
		var r := tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a := randf() * TAU
		dir = (dir + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, HIT_MASK, [get_rid()])
	q.collide_with_areas = true
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {"position": origin + dir * max_range, "normal": -dir, "collider": null, "dir": dir, "hit": false}
	res["dir"] = dir
	res["hit"] = true
	return res

func _fire_mk() -> void:
	mk_ammo -= 1
	mk_cd = MK_INTERVAL
	var r := _aim_ray(MK_SPREAD, 900.0)
	var impact: Vector3 = r["position"]
	var muzzle := (parts["muzzle"] as Node3D).global_position
	VF.tracer(self, muzzle, impact, MK_SPEED, "orange", 1.7)
	VF.show_flash(parts["flash"], 0.05)
	VF.play_2d(self, "gunship_gun40", -3.0, 0.0, &"SFX", randf_range(0.96, 1.04))
	VFX.spawn_dust_cloud(muzzle + Vector3(0, -1.0, 0), 0.8)
	_recoil = 1.0
	add_trauma(0.16)
	Events.weapon_fired.emit(self)
	var flight := muzzle.distance_to(impact) / MK_SPEED
	var col: Object = r["collider"]
	var nrm: Vector3 = r["normal"]
	var hit: bool = r["hit"]
	get_tree().create_timer(flight, false).timeout.connect(func() -> void:
		if is_instance_valid(self) and is_inside_tree():
			_shell_impact(impact, nrm, col if is_instance_valid(col) else null, hit))
	if mk_ammo <= 0:
		_start_reload()

func _shell_impact(pos: Vector3, nrm: Vector3, col: Object, hit: bool) -> void:
	if not hit:
		return
	var target := _find_damageable(col)
	if target != null and target.is_in_group("enemy") and target.has_method("is_alive") and bool(target.call("is_alive")):
		if target.has_method("set_shot_dir"):
			target.call("set_shot_dir", -nrm)
		target.call("take_damage", MK_DIRECT, self, pos, nrm)
	Combat.explode(pos + nrm * 0.3, MK_RADIUS, MK_DAMAGE, self, 0.55)
	VF.play_at(self, "gunship_impact40", pos, 2.0, 18.0, 400.0, randf_range(0.9, 1.1))

func _fire_mg() -> void:
	mg_cd = MG_INTERVAL
	mg_heat = minf(1.0, mg_heat + MG_HEAT)
	if mg_heat >= 1.0:
		mg_locked = true
		VF.play_2d(self, "dry_fire", -6.0)
	_mg_count += 1
	var r := _aim_ray(MG_SPREAD, 600.0)
	var end: Vector3 = r["position"]
	var coax := (parts["coax_muzzle"] as Node3D).global_position
	if _mg_count % 3 == 0:
		VF.tracer(self, coax, end, 520.0, "red", 0.8)
	VF.show_flash(parts["coax_flash"], 0.03)
	if _mg_count % 2 == 0:
		VF.play_2d(self, "enemy_mg", -8.0, 0.0, &"SFX", randf_range(0.95, 1.05))
	add_trauma(0.03)
	Events.weapon_fired.emit(self)
	if not bool(r["hit"]):
		return
	var pos: Vector3 = r["position"]
	var nrm: Vector3 = r["normal"]
	var target := _find_damageable(r["collider"])
	if target == null:
		var surface := "concrete"
		var c: Object = r["collider"]
		if c is Node:
			surface = str((c as Node).get_meta("surface", "concrete"))
		VFX.spawn_impact(pos, nrm, surface)
		return
	var armor: Node = target
	if not armor.has_method("armor_deflected") and armor.has_method("get_enemy"):
		armor = target.call("get_enemy") as Node
	if armor != null and armor.has_method("set_shot_dir"):
		armor.call("set_shot_dir", r["dir"])
	target.call("take_damage", MG_DAMAGE, self, pos, nrm)
	if not target.is_in_group("enemy"):
		VFX.spawn_impact(pos, nrm, "metal")

func _find_damageable(n: Object) -> Node:
	var node := n as Node
	var depth := 0
	while node != null and depth < 6:
		if node == self:
			return null
		if node.has_method("take_damage"):
			if node.has_method("is_alive") and not bool(node.call("is_alive")) and node is CollisionObject3D \
					and node.get_parent() != null and node.get_parent().has_method("take_damage"):
				node = node.get_parent()
				depth += 1
				continue
			return node
		node = node.get_parent()
		depth += 1
	return null

func _start_reload() -> void:
	mk_reload_t = MK_RELOAD
	VF.play_2d(self, "gunship_reload", -6.0)

## Nebelwurfanlage: sechs Becher, Wolkenwand 20-30 m in Turmrichtung.
func launch_smoke() -> void:
	if dead or smoke_charges <= 0:
		return
	if smoke_charges == SMOKE_CHARGES:
		smoke_recharge_t = SMOKE_RECHARGE
	smoke_charges -= 1
	smoke_t = SMOKE_TIME
	smoke_clouds.clear()
	VF.play_2d(self, "gunship_flare", -2.0)
	VF.play_2d(self, "rail_flare_launch", -4.0, 0.08)
	var fwd := Vector3(-sin(tur_yaw), 0.0, -cos(tur_yaw))
	var right := Vector3(fwd.z * -1.0, 0.0, fwd.x)
	var base := global_position
	var root := VF.effects_root(self)
	for i in 6:
		var k := (float(i) - 2.5) / 2.5
		var land := base + fwd * (18.0 + absf(k) * -4.0 + randf_range(-1.5, 1.5)) + right * (k * 14.0)
		land.y = 0.4
		smoke_clouds.append(land)
		var tubes: Array = parts.get("smoke_tubes", [])
		var from: Vector3 = (tubes[i % tubes.size()] as Node3D).global_position if not tubes.is_empty() else base + Vector3.UP * 2.6
		var g := MeshInstance3D.new()
		g.mesh = VF.cyl(0.05, 0.05, 0.2, 6)
		g.material_override = VF.mat("ifv_dark", Color(0.055, 0.055, 0.05), 0.85, 0.25)
		root.add_child(g)
		g.global_position = from
		var tw := g.create_tween()
		var mid := from.lerp(land, 0.5) + Vector3.UP * 6.0
		tw.tween_method(func(t: float) -> void:
			if is_instance_valid(g):
				g.global_position = from.lerp(mid, t).lerp(mid.lerp(land, t), t), 0.0, 1.0, 0.7 + i * 0.03)
		tw.tween_callback(func() -> void:
			_smoke_cloud(root, land)
			g.queue_free())

func _smoke_cloud(root: Node, pos: Vector3) -> void:
	VF.play_at(self, "grenade_bounce", pos, -4.0, 10.0, 120.0, 0.6)
	VFX.spawn_dust_cloud(pos, 6.0)
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(13.0, 7.0, 13.0)
	var fm := FogMaterial.new()
	fm.density = 0.0
	fm.albedo = Color(0.82, 0.82, 0.8)
	fm.height_falloff = 0.1
	fm.edge_fade = 0.6
	fv.material = fm
	root.add_child(fv)
	fv.global_position = pos + Vector3.UP * 2.2
	var tw := fv.create_tween()
	tw.tween_property(fm, "density", 1.4, 1.2)
	tw.tween_interval(SMOKE_TIME - 5.0)
	tw.tween_property(fm, "density", 0.0, 3.5)
	tw.tween_callback(fv.queue_free)
	# Nachquellender Rauch (sichtbar auch ohne Volumennebel)
	for i in 3:
		get_tree().create_timer(2.5 + i * 3.5, false).timeout.connect(func() -> void:
			if is_inside_tree():
				VFX.spawn_dust_cloud(pos + Vector3(randf_range(-2, 2), 0.5, randf_range(-2, 2)), 7.0))

# ------------------------------------------------------------------ Pfad

func _pos_at(s: float) -> Vector3:
	if path.is_empty():
		return global_position
	if s <= 0.0:
		return path[0]
	for i in range(1, path.size()):
		if s <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var k := (s - _cum[i - 1]) / maxf(seg, 0.001)
			return path[i - 1].lerp(path[i], k)
	return path[path.size() - 1]

func _dir_at(s: float) -> Vector3:
	var a := _pos_at(s - 1.5)
	var b := _pos_at(s + 1.5)
	var d := b - a
	d.y = 0.0
	if d.length() < 0.01:
		if path.size() >= 2:
			d = path[path.size() - 1] - path[path.size() - 2]
			d.y = 0.0
		if d.length() < 0.01:
			return Vector3.FORWARD
	return d.normalized()

func _build_exhaust() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.6, 1.0, 0.3)
	pm.spread = 25.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.15, 0.15, 0.15, 0.45))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = m
	_exhaust = GPUParticles3D.new()
	_exhaust.process_material = pm
	_exhaust.draw_pass_1 = q
	_exhaust.amount = 40
	_exhaust.lifetime = 1.8
	_exhaust.local_coords = false
	_exhaust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_exhaust.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 20, 40))
	(parts["exhaust"] as Node3D).add_child(_exhaust)
	_exhaust.emitting = true

## Nach dem Abschuss: Modell als statisches Wrack in die Welt uebergeben (Kollision Layer 1), Rest freigeben.
func make_wreck(parent: Node3D) -> StaticBody3D:
	var w := StaticBody3D.new()
	w.name = "RabeWrack"
	w.collision_layer = 1
	w.collision_mask = 0
	w.set_meta("surface", "metal")
	parent.add_child(w)
	w.global_transform = global_transform
	for s: Array in Model.shapes():
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s[1]
		cs.shape = bs
		cs.position = s[0]
		w.add_child(cs)
	var gt := _model.global_transform
	remove_child(_model)
	w.add_child(_model)
	_model.global_transform = gt
	if _exhaust:
		_exhaust.emitting = false
	VF.char_all(_model)
	return w
