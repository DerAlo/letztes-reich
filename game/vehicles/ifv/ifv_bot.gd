extends Node
## Autopilot-Richtschuetze fuer den Schuetzenpanzer (nur unter --autopilot). Waehlt sichtbare Ziele
## (Panzerfaust-Nester > Panzer/Hubschrauber/Sperre > Infanterie), richtet mit Skill-Streuung und
## Reaktionszeit, Kanone gegen Fahrzeuge/Nester/Gruppen, Koax-MG gegen Infanterie, Nebel bei Panzerfaust-Warnung.

var ifv: Node3D = null
var _target: Node3D = null
var _retarget: float = 0.0
var _react: float = 0.0
var _err := Vector2.ZERO
var _err_t: float = 0.0
var _skill: String = "average"
var _aim_err_deg: float = 0.4
var _react_time: float = 0.6
var _scan_t: float = 0.0
var _smoke_cd: float = 0.0
var _log_t: float = 0.0

func _ready() -> void:
	_skill = str(Game.arg("skill", "average"))
	match _skill:
		"novice":
			_aim_err_deg = 1.1
			_react_time = 1.2
		"veteran":
			_aim_err_deg = 0.2
			_react_time = 0.35
		_:
			_aim_err_deg = 0.45
			_react_time = 0.65

func _physics_process(delta: float) -> void:
	if ifv == null or not is_instance_valid(ifv) or bool(ifv.get("dead")):
		return
	_smoke_cd -= delta
	_retarget -= delta
	_err_t -= delta
	if _err_t <= 0.0:
		_err_t = randf_range(0.4, 0.9)
		_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * deg_to_rad(_aim_err_deg)
	# Nebel bei Panzerfaust-Warnung (nicht immer: Novize reagiert seltener)
	if float(ifv.get("rocket_warn")) > 1.6 and _smoke_cd <= 0.0 and int(ifv.get("smoke_charges")) > 0 and not bool(ifv.call("smoke_active")):
		_smoke_cd = 6.0
		if randf() < (0.45 if _skill == "novice" else 0.8):
			ifv.call("launch_smoke")
	if _target == null or not is_instance_valid(_target) or not _alive(_target) or _retarget <= 0.0:
		var nt := _pick()
		if nt != _target:
			_react = _react_time
		_target = nt
		_retarget = 0.6
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 15.0
		print("[ifv-bot] Ziel=%s Zustand=%.0f Munition=%d Hitze=%.2f" % [str(_target.name) if _target else "-", float(ifv.get("integrity")), int(ifv.get("mk_ammo")), float(ifv.get("mg_heat"))])
	if _target == null:
		ifv.set("fire_held", false)
		# Turm nach vorn
		ifv.set("aim_yaw", lerp_angle(float(ifv.get("aim_yaw")), float(ifv.get("hull_yaw")), delta * 0.8))
		ifv.set("aim_pitch", lerpf(float(ifv.get("aim_pitch")), 0.04, delta))
		if int(ifv.get("mk_ammo")) < 20 and float(ifv.get("mk_reload_t")) <= 0.0:
			ifv.call("manual_reload")
		return
	var cam: Camera3D = ifv.call("get_camera")
	var tp := _aim_point(_target)
	var d := tp - cam.global_position
	var yaw := atan2(-d.x, -d.z) + _err.x
	var pitch := atan2(d.y, Vector2(d.x, d.z).length()) + _err.y
	ifv.set("aim_yaw", yaw)
	ifv.set("aim_pitch", clampf(pitch, -0.16, 0.95))
	# Waffe waehlen
	var want := 0 if _wants_cannon(_target) else 1
	if want == 1 and bool(ifv.get("mg_locked")):
		want = 0
	if want == 0 and float(ifv.get("mk_reload_t")) > 0.0 and not _target.is_in_group("vehicle") and not bool(ifv.get("mg_locked")):
		want = 1
	if int(ifv.get("weapon")) != want:
		ifv.call("select_weapon", want)
	_react -= delta
	# Feuern, wenn Turm ausgerichtet
	var tur_yaw: float = ifv.get("tur_yaw")
	var tur_pitch: float = ifv.get("tur_pitch")
	var aligned := absf(wrapf(tur_yaw - yaw, -PI, PI)) < 0.03 and absf(tur_pitch - clampf(pitch, -0.16, 0.95)) < 0.03
	var fire := aligned and _react <= 0.0
	# MG in Feuerstoessen (Hitze schonen)
	if fire and want == 1 and float(ifv.get("mg_heat")) > 0.8:
		fire = false
	ifv.set("fire_held", fire)

func _alive(n: Node) -> bool:
	if n.has_method("is_alive"):
		return bool(n.call("is_alive"))
	return not bool(n.get("dead"))

func _aim_point(n: Node3D) -> Vector3:
	if n.has_meta("aim_offset"):
		return n.global_position + (n.get_meta("aim_offset") as Vector3)
	if n.is_in_group("vehicle"):
		return n.global_position + Vector3.UP * (0.0 if n.is_in_group("enemy") else 1.3)
	if n is CharacterBody3D:
		return n.global_position + Vector3.UP * 1.25
	return n.global_position + Vector3.UP * 0.8

func _wants_cannon(n: Node) -> bool:
	return n.is_in_group("vehicle") or n.has_meta("rpg") or n.is_in_group("spree_target") or not n.is_in_group("enemy")

func _visible(n: Node3D) -> bool:
	var cam: Camera3D = ifv.call("get_camera")
	var from := cam.global_position
	var to := _aim_point(n)
	if from.distance_to(to) > 220.0:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [ifv.get_rid()])
	var res := ifv.get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return true
	var c := res["collider"] as Node
	var k := 0
	while c != null and k < 5:
		if c == n:
			return true
		c = c.get_parent()
		k += 1
	return (res["position"] as Vector3).distance_to(to) < 1.2

func _pick() -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	var cands: Array = get_tree().get_nodes_in_group("enemy")
	for e in ifv.get("extra_targets"):
		if is_instance_valid(e):
			cands.append(e)
	var pos := ifv.global_position
	for c: Node in cands:
		var n := c as Node3D
		if n == null or not is_instance_valid(n) or not _alive(n):
			continue
		var dist := pos.distance_to(n.global_position)
		if dist > 200.0:
			continue
		var score := -dist
		if n.has_meta("rpg"):
			score += 120.0
		elif n.is_in_group("vehicle"):
			score += 90.0
		elif n.is_in_group("spree_target"):
			score += 30.0
		if n == _target:
			score += 15.0
		if score <= best_score:
			continue
		if not _visible(n):
			continue
		best = n
		best_score = score
	return best
