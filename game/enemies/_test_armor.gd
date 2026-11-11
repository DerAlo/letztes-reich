extends Node3D
## Headless-Schadenstest fuer gepanzerte Gegner: Gewehr (34) aus 10 m auf Brust / Kopf / Ruecken / Beine,
## dazu Rakete und Granate. Druckt Schuesse-bis-Tod-Tabelle fuer rifleman / armored / juggernaut.
## Start: godot --headless res://game/enemies/_test_armor.tscn

const RIFLE := 34.0
const HEAD_MULT := 1.4   # wie _test_armor_shot (Gewehr-Kopftreffer-Bonus der Waffe)
const TYPES := ["rifleman", "armored", "juggernaut"]
const SCEN := ["chest", "head", "back", "legs", "rocket", "grenade"]

var _queue: Array = []
var _cur: Node3D = null
var _cur_t := ""
var _cur_s := ""
var _shots := 0
var _wait := 0
var _zones: Dictionary = {}
var _results: Dictionary = {}

func _ready() -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	sb.add_child(cs)
	add_child(sb)
	for t in TYPES:
		for s in SCEN:
			_queue.append([t, s])

func _spawn(t: String) -> Node3D:
	var en: Node3D = (load("res://game/enemies/%s.tscn" % t) as PackedScene).instantiate()
	en.set_meta("faction", "reich")
	add_child(en)
	en.global_position = Vector3.ZERO
	en.rotation.y = PI
	en.set_physics_process(false)
	return en

func _physics_process(_d: float) -> void:
	if _cur == null:
		if _queue.is_empty():
			_report()
			set_physics_process(false)
			get_tree().quit()
			return
		var q: Array = _queue.pop_front()
		_cur_t = q[0]
		_cur_s = q[1]
		_cur = _spawn(_cur_t)
		_shots = 0
		_zones = {}
		_wait = 3
		return
	if _wait > 0:
		_wait -= 1
		return
	var alive: bool = _cur.call("is_alive")
	if not alive or _shots >= 300:
		_finish(alive)
		return
	match _cur_s:
		"rocket":
			var hp0: float = _cur.get("health")
			if _cur.has_method("rocket_hit"):
				_cur.call("rocket_hit", null, _cur.global_position + Vector3(0, 1.2, 0.4), Vector3(0, 0, 1))
			else:
				_cur.call("take_damage", 650.0, null, _cur.global_position + Vector3(0, 1.2, 0.4), Vector3(0, 0, 1))
			_results[_cur_t + ":rocket"] = "%.0f (%.0f%% HP)" % [hp0 - float(_cur.get("health")), (hp0 - float(_cur.get("health"))) / float(_cur.get("max_health")) * 100.0]
			_finish(true, true)
		"grenade":
			var hp1: float = _cur.get("health")
			Combat.explosion_active = true
			_cur.call("take_damage", 150.0, null, _cur.global_position + Vector3(0, 0.5, 2.0), Vector3(0, 0, 1))
			Combat.explosion_active = false
			_results[_cur_t + ":grenade"] = "%.0f (%.0f%% HP)" % [hp1 - float(_cur.get("health")), (hp1 - float(_cur.get("health"))) / float(_cur.get("max_health")) * 100.0]
			_finish(true, true)
		_:
			_shoot()

func _shoot() -> void:
	var bsc: float = _cur.get("body_scale")
	var vs := 1.1 if bool(_cur.get("heavy_armor")) else 1.0
	var p := _cur.global_position
	var from := p + Vector3(0, 1.4, 10.0)
	var tgt := p + Vector3(0.03, 1.25 * vs, 0)
	match _cur_s:
		"head":
			tgt = p + Vector3(0.0, 1.66 * maxf(bsc, vs), 0.0)
			for hb in _cur.find_children("*", "CollisionObject3D", true, false):
				if bool(hb.get_meta("headshot", false)):
					tgt = (hb as Node3D).global_position
					for csn in hb.get_children():
						if csn is CollisionShape3D:
							tgt = (csn as Node3D).global_position
		"back":
			from = p + Vector3(0, 1.4, -10.0)
			tgt = p + Vector3(0.0, 1.2 * vs, 0)
		"legs":
			tgt = p + Vector3(0.11, 0.55, 0)
	_shots += 1
	var d := (tgt - from).normalized()
	var q := PhysicsRayQueryParameters3D.create(from, from + d * 30.0, 4)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	if r.is_empty():
		_zones["MISS"] = int(_zones.get("MISS", 0)) + 1
		return
	var c: Node = r.collider
	while c != null and not c.has_method("take_damage"):
		c = c.get_parent()
	if c == null:
		return
	var tn: Node = c
	if c.has_method("get_enemy"):
		tn = c.call("get_enemy")
	if tn.has_method("set_shot_dir"):
		tn.call("set_shot_dir", d)
	var head: bool = bool(r.collider.get_meta("headshot", false))
	var hp0: float = tn.get("health")
	c.call("take_damage", RIFLE * (HEAD_MULT if head else 1.0), null, r.position, r.normal)
	var z := str(tn.get("last_zone")) if tn.get("last_zone") != null else ("head" if head else "body")
	var key := "%s %.1f" % [z, hp0 - float(tn.get("health"))]
	_zones[key] = int(_zones.get(key, 0)) + 1

func _finish(alive: bool, special: bool = false) -> void:
	if not special:
		var zs: Array = []
		for k in _zones:
			zs.append("%sx%d" % [k, _zones[k]])
		_results[_cur_t + ":" + _cur_s] = ("%d shots" % _shots if not alive else ">%d (alive)" % _shots) + "  [" + ", ".join(zs) + "]"
	_cur.queue_free()
	_cur = null

func _report() -> void:
	print("\n=== ARMOR DAMAGE TEST (rifle %.0f, head x%.1f) ===" % [RIFLE, HEAD_MULT])
	for t in TYPES:
		print("-- %s" % t)
		for s in SCEN:
			print("   %-8s %s" % [s, _results.get(t + ":" + s, "?")])
	print("=== END ===")
