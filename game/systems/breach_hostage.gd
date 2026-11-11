extends StaticBody3D
## Geisel (wiederverwendbar, Runde 7): sitzend ("seat") oder kniend ("kneel"), Haende auf dem Ruecken.
## Ebene 4 (wie Gegner): Spielerschuesse treffen sie. Trifft der SPIELER (Schuss oder eigene Granate),
## meldet sie shot_by_player -> das Level laesst die Mission am Checkpoint neu starten.
## Gruppe "damageable" (Combat.explode): nur Schaden mit Quelle Spieler zaehlt; die Breach-Ladung (Quelle Tuer)
## und Gegnerfeuer werden ignoriert. Gruppe "hostage" (nicht "enemy": Autopilot/HUD zielen nie darauf).

signal shot_by_player(hostage: Node)
signal executed(hostage: Node)

@export var pose: String = "kneel"            ## "kneel" | "seat"
@export var suit: Color = Color(0.13, 0.14, 0.17)
@export var hair: Color = Color(0.14, 0.11, 0.08)
@export var skin: Color = Color(0.62, 0.47, 0.38)
@export var shirt: Color = Color(0.78, 0.78, 0.76)
@export var display_name: String = ""

var alive: bool = true
var _body: Node3D
var _torso: Node3D
var _t: float = 0.0
var _phase: float = 0.0
var _fall_tw: Tween

func _ready() -> void:
	collision_layer = 4 | 16   # Gegner-Ebene (Treffer) + move_block (Spieler laeuft nicht hindurch)
	collision_mask = 0
	set_meta("no_fit", true)
	set_meta("surface", "flesh")
	add_to_group("damageable")
	add_to_group("hostage")
	_phase = randf() * TAU
	_build()

func _m(c: Color, rough: float = 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m

func _box(parent: Node3D, s: Vector3, m: Material, p: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi

func _shape(c: Vector3, s: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	cs.position = c
	add_child(cs)

func _build() -> void:
	var sm := _m(suit)
	var sk := _m(skin, 0.7)
	var hm := _m(hair, 0.9)
	var sh := _m(shirt, 0.7)
	var shoe := _m(Color(0.05, 0.05, 0.05), 0.4)
	var tie := _m(Color(0.75, 0.75, 0.72), 0.9)   # Kabelbinder/Tape
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var hip_y := 0.5 if pose == "seat" else 0.42
	if pose == "seat":
		# Stuhl (Teil der Geisel, faellt nicht mit)
		var chair := _m(Color(0.22, 0.12, 0.08), 0.6)
		_box(self, Vector3(0.48, 0.06, 0.46), chair, Vector3(0, 0.45, 0.02))
		_box(self, Vector3(0.48, 0.6, 0.06), chair, Vector3(0, 0.78, 0.24))
		for sx: float in [-0.21, 0.21]:
			for sz: float in [-0.18, 0.22]:
				_box(self, Vector3(0.04, 0.45, 0.04), chair, Vector3(sx, 0.225, sz))
		# Oberschenkel waagerecht, Unterschenkel senkrecht
		for sx: float in [-0.1, 0.1]:
			_box(_body, Vector3(0.15, 0.15, 0.46), sm, Vector3(sx, hip_y + 0.05, -0.17))
			_box(_body, Vector3(0.13, 0.46, 0.14), sm, Vector3(sx, 0.25, -0.38))
			_box(_body, Vector3(0.12, 0.07, 0.24), shoe, Vector3(sx, 0.035, -0.44))
		_shape(Vector3(0, 0.3, -0.25), Vector3(0.4, 0.6, 0.55))
	else:
		# kniend: Unterschenkel flach nach hinten, Oberschenkel senkrecht
		for sx: float in [-0.11, 0.11]:
			_box(_body, Vector3(0.14, 0.13, 0.46), sm, Vector3(sx, 0.07, 0.12))
			_box(_body, Vector3(0.15, 0.36, 0.16), sm, Vector3(sx, 0.27, -0.06))
			_box(_body, Vector3(0.11, 0.12, 0.08), shoe, Vector3(sx, 0.06, 0.38), Vector3(-70, 0, 0))
		_shape(Vector3(0, 0.22, 0.08), Vector3(0.4, 0.44, 0.6))
	_torso = Node3D.new()
	_torso.position = Vector3(0, hip_y, 0)
	_body.add_child(_torso)
	_box(_torso, Vector3(0.44, 0.58, 0.25), sm, Vector3(0, 0.31, 0.02), Vector3(-6, 0, 0))
	_box(_torso, Vector3(0.14, 0.2, 0.02), sh, Vector3(0, 0.5, -0.115), Vector3(-6, 0, 0))
	# Arme nach hinten, Haende gefesselt
	for sx: float in [-0.25, 0.25]:
		_box(_torso, Vector3(0.12, 0.52, 0.13), sm, Vector3(sx, 0.32, 0.1), Vector3(22, 0, sx * 30.0))
	_box(_torso, Vector3(0.2, 0.09, 0.1), sk, Vector3(0, 0.1, 0.24))
	_box(_torso, Vector3(0.22, 0.03, 0.11), tie, Vector3(0, 0.1, 0.24))
	# Kopf leicht gesenkt
	_box(_torso, Vector3(0.1, 0.08, 0.1), sk, Vector3(0, 0.64, 0.0))
	_box(_torso, Vector3(0.19, 0.23, 0.21), sk, Vector3(0, 0.79, -0.02), Vector3(14, 0, 0))
	_box(_torso, Vector3(0.21, 0.09, 0.23), hm, Vector3(0, 0.9, 0.0), Vector3(14, 0, 0))
	_box(_torso, Vector3(0.21, 0.16, 0.06), hm, Vector3(0, 0.82, 0.09), Vector3(14, 0, 0))
	_shape(Vector3(0, hip_y + 0.31, 0.02), Vector3(0.46, 0.6, 0.3))
	_shape(Vector3(0, hip_y + 0.8, 0.0), Vector3(0.24, 0.28, 0.25))

func _process(delta: float) -> void:
	if not alive or _torso == null:
		return
	_t += delta
	# Atmen + Zittern (Angst)
	_torso.position.y = (0.5 if pose == "seat" else 0.42) + sin(_t * 2.6 + _phase) * 0.006
	_torso.rotation_degrees.z = sin(_t * 17.0 + _phase) * 0.5
	_torso.rotation_degrees.x = sin(_t * 1.3 + _phase) * 1.2

## Kopfposition (Ziel der Bewacher-Waffe).
func head_point() -> Vector3:
	return to_global(Vector3(0, (0.5 if pose == "seat" else 0.42) + 0.8, 0))

## Stichpunkte fuer die Schusslinien-Pruefung (Bot): Kopf, Brust, Bauch, Beine.
func clearance_points() -> Array[Vector3]:
	var hy := 0.5 if pose == "seat" else 0.42
	var out: Array[Vector3] = []
	for y: float in [hy + 0.8, hy + 0.45, hy + 0.15, 0.3]:
		out.append(to_global(Vector3(0, y, 0)))
	return out

func is_alive() -> bool:
	return alive

func take_damage(_amount: float, source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if not alive:
		return
	if source == null or not is_instance_valid(source) or not source.is_in_group("player"):
		return
	_fall(Vector3.ZERO)
	shot_by_player.emit(self)

## Vom Bewacher erschossen (Skript).
func execute(from: Vector3) -> void:
	if not alive:
		return
	_fall(from)
	executed.emit(self)

func _fall(from: Vector3) -> void:
	alive = false
	remove_from_group("damageable")
	var dir := 1.0
	if from != Vector3.ZERO:
		var l := to_local(from)
		dir = -1.0 if l.z > 0.0 else 1.0
	if _fall_tw != null and _fall_tw.is_valid():
		_fall_tw.kill()
	_fall_tw = create_tween()
	_fall_tw.tween_property(_body, "rotation_degrees:x", 80.0 * dir, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fall_tw.parallel().tween_property(_body, "position:y", -0.05, 0.45)

func reset() -> void:
	if _fall_tw != null and _fall_tw.is_valid():
		_fall_tw.kill()
	alive = true
	if not is_in_group("damageable"):
		add_to_group("damageable")
	_body.rotation_degrees = Vector3.ZERO
	_body.position = Vector3.ZERO
