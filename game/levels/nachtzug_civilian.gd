extends StaticBody3D
## Reisender im Nachtzug (Gruppe no_shoot). Faellt bei Treffern nicht um, sondern meldet
## dem Level jeden Spieler-Treffer (1. Warnung, 2. Abbruch – Logik im Level).

@export var pose: String = "seat"     ## "seat" (Bank), "lie" (Bett, laengs x), "cower" (kauert)
@export var coat: Color = Color(0.25, 0.22, 0.2)
@export var legs: Color = Color(0.16, 0.16, 0.2)
@export var hair: Color = Color(0.2, 0.15, 0.1)
@export var skin: Color = Color(0.68, 0.52, 0.42)

var level: Node = null
var hits: int = 0
var _body: Node3D
var _torso: Node3D
var _t: float = 0.0
var _phase: float = 0.0
var _cool: float = 0.0

func _ready() -> void:
	collision_layer = 4 | 16
	collision_mask = 0
	set_meta("no_fit", true)
	set_meta("surface", "flesh")
	add_to_group("damageable")
	add_to_group("civilian")
	add_to_group("no_shoot")
	_phase = randf() * TAU
	_build()

func _m(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(parent: Node3D, s: Vector3, m: Material, p: Vector3, rot: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation_degrees = rot
	parent.add_child(mi)

func _shape(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.position = c
	add_child(cs)

func _hip() -> float:
	match pose:
		"seat":
			return 0.48
		"lie":
			return 0.62
		_:
			return 0.4

func _build() -> void:
	var cm := _m(coat)
	var lm := _m(legs)
	var sk := _m(skin, 0.7)
	var hm := _m(hair, 0.9)
	var shoe := _m(Color(0.06, 0.05, 0.05), 0.4)
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var hy := _hip()
	_torso = Node3D.new()
	_torso.position = Vector3(0, hy, 0)
	_body.add_child(_torso)
	if pose == "lie":
		# liegt auf dem Ruecken, Kopf bei -x, Decke ueber den Beinen
		_body.rotation_degrees = Vector3(0, 0, 0)
		_box(_body, Vector3(0.9, 0.16, 0.42), _m(Color(0.75, 0.72, 0.66), 0.95), Vector3(0.35, hy + 0.02, 0))
		_box(_torso, Vector3(0.55, 0.2, 0.4), cm, Vector3(-0.3, 0.02, 0))
		_box(_torso, Vector3(0.22, 0.19, 0.21), sk, Vector3(-0.7, 0.06, 0))
		_box(_torso, Vector3(0.1, 0.2, 0.22), hm, Vector3(-0.82, 0.06, 0))
		_shape(Vector3(-0.1, hy + 0.05, 0), Vector3(1.6, 0.3, 0.45))
		return
	if pose == "seat":
		for sx: float in [-0.1, 0.1]:
			_box(_body, Vector3(0.15, 0.15, 0.44), lm, Vector3(sx, hy + 0.04, -0.17))
			_box(_body, Vector3(0.13, 0.46, 0.14), lm, Vector3(sx, 0.25, -0.38))
			_box(_body, Vector3(0.12, 0.07, 0.24), shoe, Vector3(sx, 0.035, -0.44))
		_shape(Vector3(0, 0.3, -0.25), Vector3(0.4, 0.6, 0.5))
	else:
		# kauernd: Knie angezogen, Arme ueber dem Kopf
		for sx: float in [-0.11, 0.11]:
			_box(_body, Vector3(0.14, 0.13, 0.46), lm, Vector3(sx, 0.07, 0.12))
			_box(_body, Vector3(0.15, 0.36, 0.16), lm, Vector3(sx, 0.27, -0.06))
		_shape(Vector3(0, 0.22, 0.08), Vector3(0.4, 0.44, 0.6))
	var lean := -8.0 if pose == "seat" else -35.0
	_box(_torso, Vector3(0.44, 0.58, 0.26), cm, Vector3(0, 0.31, 0.02), Vector3(lean, 0, 0))
	if pose == "seat":
		# Haende im Schoss
		for sx: float in [-0.2, 0.2]:
			_box(_torso, Vector3(0.11, 0.42, 0.12), cm, Vector3(sx, 0.3, -0.05), Vector3(-20, 0, 0))
		_box(_torso, Vector3(0.24, 0.08, 0.12), sk, Vector3(0, 0.05, -0.22))
	else:
		for sx: float in [-0.17, 0.17]:
			_box(_torso, Vector3(0.11, 0.42, 0.12), cm, Vector3(sx, 0.72, -0.18), Vector3(-150, 0, sx * -40.0))
	var head_rot := Vector3(10, 0, 0) if pose == "seat" else Vector3(40, 0, 0)
	var head_p := Vector3(0, 0.79, -0.02) if pose == "seat" else Vector3(0, 0.66, -0.25)
	_box(_torso, Vector3(0.19, 0.23, 0.21), sk, head_p, head_rot)
	_box(_torso, Vector3(0.21, 0.09, 0.23), hm, head_p + Vector3(0, 0.11, 0.02), head_rot)
	_shape(Vector3(0, hy + 0.31, 0.02), Vector3(0.46, 0.6, 0.3))
	_shape(Vector3(0, hy + 0.78, 0.0), Vector3(0.24, 0.28, 0.25))

func _process(delta: float) -> void:
	if _torso == null:
		return
	_t += delta
	_cool = maxf(0.0, _cool - delta)
	# Atmen, bei "cower" deutliches Zittern
	var shake := 1.6 if pose == "cower" else 0.35
	_torso.position.y = _hip() + sin(_t * 2.4 + _phase) * 0.005
	_torso.rotation_degrees.z = sin(_t * 15.0 + _phase) * shake

## Stichpunkte fuer die Schusslinien-Pruefung (Bot).
func clearance_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if pose == "lie":
		for x: float in [-0.7, -0.2, 0.3]:
			out.append(to_global(Vector3(x, _hip(), 0)))
		return out
	var hy := _hip()
	for y: float in [hy + 0.78, hy + 0.45, hy + 0.15, 0.3]:
		out.append(to_global(Vector3(0, y, 0)))
	return out

func is_alive() -> bool:
	return true

func take_damage(_amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	VFX.spawn_blood(hit_position, hit_normal)
	if _cool > 0.0:
		return
	_cool = 0.5
	hits += 1
	if level != null and is_instance_valid(level) and level.has_method("on_civilian_hit"):
		level.on_civilian_hit(self)

func reset() -> void:
	hits = 0
	_cool = 0.0
