extends StaticBody3D
## Hoelzerner Wasserturm (Set-Piece): damageable. Nach genug Treffern (oder Explosion des
## Tanks daneben) knicken die Beine, der Turm kippt um die Grundkante Richtung fall_dir und
## erschlaegt Gegner im Fallbereich. Aufbau prozedural.

const NightProps = preload("res://game/levels/night_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

signal toppled

@export var max_health: float = 140.0
@export var height: float = 9.0          ## Hoehe der Plattform
@export var fall_dir: Vector3 = Vector3(1, 0, 0)
@export var fall_time: float = 2.4

var health: float
var _alive: bool = true
var _pivot: Node3D
var _visual: Node3D

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	collision_layer = 1
	collision_mask = 0
	_build()

func is_alive() -> bool:
	return _alive

func take_damage(amount: float, _source: Node = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	if not _alive:
		return
	health -= amount
	if hit_position != Vector3.ZERO and has_node("/root/VFX"):
		VFX.spawn_impact(hit_position, hit_normal, "wood")
	if health <= 0.0:
		topple()

func _build() -> void:
	var wood := NightProps.planks(Color(0.42, 0.34, 0.26), 0.35)
	var dark := NightProps.planks(Color(0.26, 0.21, 0.17), 0.3)
	var roof := NightProps.metal(Color(0.25, 0.25, 0.24), 0.7)
	# Kipp-Pivot an der Grundkante in Fallrichtung
	var fd := fall_dir.normalized()
	_pivot = Node3D.new()
	_pivot.position = fd * 1.6
	add_child(_pivot)
	_visual = Node3D.new()
	_visual.position = -fd * 1.6
	_pivot.add_child(_visual)
	var legs := Geo.batch()
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var top := Vector3(sx * 1.25, height, sz * 1.25)
			var bot := Vector3(sx * 1.6, 0, sz * 1.6)
			var mid := (top + bot) / 2.0
			var dir := (top - bot)
			legs.add(mid, Vector3(0.28, dir.length(), 0.28), Basis(Vector3(0, 0, 1), -atan2(dir.x, dir.y)) * Basis(Vector3(1, 0, 0), atan2(dir.z, dir.y)))
	# Querstreben
	for lv: float in [2.6, 5.4, 8.0]:
		var hw := 1.6 - (lv / height) * 0.35
		for side in 4:
			var rot := Basis(Vector3.UP, side * PI / 2.0)
			legs.add(rot * Vector3(0, lv, hw), Vector3(hw * 2.0, 0.14, 0.12), rot)
			legs.add(rot * Vector3(0, lv + 1.3, hw), Vector3(0.12, hw * 2.9, 0.1), rot * Basis(Vector3(0, 0, 1), deg_to_rad(52.0)))
	NightProps.add_batch(_visual, legs, dark)
	# Plattform, Tank (Holzfass) mit Reifen, Spitzdach, Leiter
	var tank := Geo.batch()
	tank.add(Vector3(0, height + 0.12, 0), Vector3(3.4, 0.24, 3.4))
	NightProps.add_batch(_visual, tank, dark)
	var barrel := Geo.cylinder_node(1.55, 3.0, wood, Vector3(0, height + 1.75, 0), Vector3.ZERO, 16)
	_visual.add_child(barrel)
	var hoop_m := NightProps.metal(Color(0.18, 0.18, 0.17), 0.2)
	for hy: float in [0.6, 1.5, 2.4]:
		_visual.add_child(Geo.cylinder_node(1.58, 0.08, hoop_m, Vector3(0, height + 0.25 + hy, 0), Vector3.ZERO, 16))
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 1.85
	cm.height = 1.4
	cm.radial_segments = 16
	cone.mesh = cm
	cone.material_override = roof
	cone.position = Vector3(0, height + 3.95, 0)
	_visual.add_child(cone)
	var ladder := Geo.batch()
	for sx: float in [-0.25, 0.25]:
		ladder.add(Vector3(sx, height / 2.0, -1.75), Vector3(0.06, height, 0.06), Basis(Vector3(1, 0, 0), 0.04))
	for k in int(height / 0.4):
		ladder.add(Vector3(0, 0.3 + k * 0.4, -1.75 + 0.002 * k), Vector3(0.5, 0.05, 0.05))
	NightProps.add_batch(_visual, ladder, dark)
	# Kollision: Beine unten (Deckung) + Tank oben (Treffer). Alles im Visual, kippt mit.
	var shapes := Node3D.new()
	_visual.add_child(shapes)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_add_shape(Vector3(sx * 1.45, height / 2.0, sz * 1.45), Vector3(0.4, height, 0.4))
	_add_shape(Vector3(0, height + 1.8, 0), Vector3(3.2, 3.4, 3.2))

func _add_shape(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	add_child(cs)

func topple() -> void:
	if not _alive:
		return
	_alive = false
	var fd := fall_dir.normalized()
	var top := global_position + Vector3(0, height + 1.5, 0)
	if has_node("/root/Combat"):
		Combat.explode(global_position + Vector3(0, 1.0, 0) + fd * 0.5, 4.0, 60.0, self, 1.6)
	VFX.spawn_dust_cloud(global_position + Vector3(0, height, 0), 4.0)
	# Kollision sofort weg (Kipp-Kollision waere instabil); Trümmer-Kollision am Ende
	for c in get_children():
		if c is CollisionShape3D:
			c.set_deferred("disabled", true)
	var axis := Vector3.UP.cross(fd).normalized()
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(8.0)) * _pivot.basis, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(88.0)), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact.bind(top, fd))
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(84.0)), 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(88.0)), 0.25).set_ease(Tween.EASE_IN)

func _impact(top: Vector3, fd: Vector3) -> void:
	var land := global_position + fd * (height + 2.0)
	land.y = 0.3
	VFX.spawn_dust_cloud(land, 7.0)
	VFX.spawn_dust_cloud(global_position + fd * (height * 0.5), 5.0)
	Events.explosion.emit(land, 4.0, 1.5)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", clampf(0.7 - pl.global_position.distance_to(land) / 60.0, 0.15, 0.6))
	# Gegner im Fallbereich erschlagen (Streifen von Fuss bis Spitze)
	var a := global_position
	var b := global_position + fd * (height + 4.0)
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("take_damage"):
			continue
		var p: Vector3 = (e as Node3D).global_position
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		if Vector2(p.x - q.x, p.z - q.z).length() < 2.6 and p.y < 4.0:
			e.call("take_damage", 400.0, self, p + Vector3(0, 1, 0), Vector3.UP)
	# Liegender Turm als niedrige Truemmer-Kollision (Deckung)
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.6, 1.6, 2.6)
	c.shape = bs
	add_child(c)
	c.global_position = global_position + fd * (height + 2.0) + Vector3(0, 0.8, 0)
	var c2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(height, 0.9, 2.2)
	c2.shape = bs2
	add_child(c2)
	c2.global_position = global_position + fd * (height * 0.5) + Vector3(0, 0.45, 0)
	c2.global_basis = Basis(Vector3.UP, atan2(-fd.z, fd.x))
	toppled.emit()
