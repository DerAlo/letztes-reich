extends Node
## Autopilot-Schuetze fuer RailRide (nur unter --autopilot). Waehlt sichtbare Ziele aus Gruppe "enemy"
## plus ride.extra_targets im Schwenkbereich, schwenkt mit begrenzter Rate, Skill-Streuung und
## Reaktionszeit, schiesst in Feuerstoessen (Hitze schonen) und haelt Feuer, wenn ein Knoten aus
## ride.avoid_nodes oder Gruppe "no_shoot" nahe der Schusslinie ist.

var ride: Node3D = null
var max_range: float = 300.0
var _target: Node3D = null
var _retarget: float = 0.0
var _react: float = 0.0
var _err := Vector2.ZERO
var _err_t: float = 0.0
var _skill: String = "average"
var _err_deg: float = 0.5
var _react_time: float = 0.6
var _slew: float = 2.2
var _burst_hi: float = 0.85
var _burst_lo: float = 0.45
var _cooling: bool = false
var _log_t: float = 0.0

func _ready() -> void:
	_skill = str(Game.arg("skill", "average"))
	match _skill:
		"novice":
			_err_deg = 1.0
			_react_time = 1.1
			_slew = 1.5
			_burst_hi = 0.97
			_burst_lo = 0.3
		"veteran":
			_err_deg = 0.25
			_react_time = 0.35
			_slew = 3.0
			_burst_hi = 0.8
			_burst_lo = 0.5
		_:
			_err_deg = 0.5
			_react_time = 0.65
			_slew = 2.2

func _physics_process(delta: float) -> void:
	if ride == null or not is_instance_valid(ride) or bool(ride.get("dead")):
		if ride != null and is_instance_valid(ride):
			ride.set("fire_held", false)
		return
	_retarget -= delta
	_err_t -= delta
	_react -= delta
	if _err_t <= 0.0:
		_err_t = randf_range(0.35, 0.8)
		_err = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * deg_to_rad(_err_deg)
	if _target == null or not is_instance_valid(_target) or not _alive(_target) or _retarget <= 0.0:
		var nt := _pick()
		if nt != _target:
			_react = _react_time
		_target = nt
		_retarget = 0.5
	_log_t -= delta
	if _log_t <= 0.0:
		_log_t = 15.0
		print("[rail-bot] Ziel=%s Zustand=%.0f Hitze=%.2f s=%.0f v=%.1f" % [str(_target.name) if _target else "-", float(ride.get("integrity")), float(ride.get("heat")), float(ride.get("path_s")), float(ride.get("speed"))])
	var cur := Vector2(float(ride.get("aim_yaw")), float(ride.get("aim_pitch")))
	var want := Vector2(0.0, 0.03)
	if _target != null:
		want = _angles(_aim_point(_target)) + _err
	var dy := wrapf(want.x - cur.x, -PI, PI)
	var dp := want.y - cur.y
	var step := _slew * delta * (1.0 if _target != null else 0.4)
	var nv := Vector2(cur.x + clampf(dy, -step, step), cur.y + clampf(dp, -step, step))
	ride.set("aim_yaw", nv.x)
	ride.set("aim_pitch", nv.y)
	var heat: float = ride.get("heat")
	if heat >= _burst_hi:
		_cooling = true
	elif heat <= _burst_lo:
		_cooling = false
	var fire := _target != null and _react <= 0.0 and absf(dy) < 0.035 and absf(dp) < 0.035 and not _cooling and not bool(ride.get("locked"))
	if fire and _blocked_by_friend():
		fire = false
	ride.set("fire_held", fire)

func _angles(p: Vector3) -> Vector2:
	var cam: Camera3D = ride.call("get_camera")
	var d := p - cam.global_position
	var lp := ride.global_transform.basis.inverse() * d
	return Vector2(atan2(-lp.x, -lp.z), atan2(lp.y, Vector2(lp.x, lp.z).length()))

func _alive(n: Node) -> bool:
	if n.has_method("is_alive"):
		return bool(n.call("is_alive"))
	return not bool(n.get("dead"))

func _aim_point(n: Node3D) -> Vector3:
	if n.has_meta("aim_offset"):
		return n.global_position + (n.get_meta("aim_offset") as Vector3)
	if n.is_in_group("vehicle"):
		return n.global_position + Vector3.UP * 0.6
	if n is CharacterBody3D:
		return n.global_position + Vector3.UP * 1.15
	return n.global_position + Vector3.UP * 0.8

func _visible(n: Node3D) -> bool:
	var cam: Camera3D = ride.call("get_camera")
	var from := cam.global_position
	var to := _aim_point(n)
	if from.distance_to(to) > max_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [ride.get_rid()])
	var res := ride.get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return true
	var c := res["collider"] as Node
	var k := 0
	while c != null and k < 6:
		if c == n:
			return true
		c = c.get_parent()
		k += 1
	return (res["position"] as Vector3).distance_to(to) < 1.2

func _pick() -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	var cands: Array = get_tree().get_nodes_in_group("enemy")
	for e in ride.get("extra_targets"):
		if is_instance_valid(e):
			cands.append(e)
	var pos := ride.global_position
	for c: Node in cands:
		var n := c as Node3D
		if n == null or not is_instance_valid(n) or not n.is_inside_tree() or not _alive(n):
			continue
		var dist := pos.distance_to(n.global_position)
		if dist > max_range:
			continue
		if not bool(ride.call("can_aim_at", _aim_point(n))):
			continue
		var score := -dist
		if n.is_in_group("vehicle"):
			score += 70.0
		if n.has_meta("priority"):
			score += float(n.get_meta("priority"))
		if n == _target:
			score += 25.0
		if score <= best_score:
			continue
		if not _visible(n):
			continue
		best = n
		best_score = score
	return best

func _blocked_by_friend() -> bool:
	var cam: Camera3D = ride.call("get_camera")
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var tgt_d := from.distance_to(_aim_point(_target)) if _target != null else 400.0
	var list: Array = get_tree().get_nodes_in_group("no_shoot")
	for a in ride.get("avoid_nodes"):
		list.append(a)
	for o in list:
		var n := o as Node3D
		if n == null or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var rel := n.global_position + Vector3.UP * 1.0 - from
		var along := rel.dot(dir)
		if along < 0.0 or along > tgt_d + 15.0:
			continue
		var r := float(n.get_meta("avoid_radius", 3.0))
		if (rel - dir * along).length() < r:
			return true
	return false
