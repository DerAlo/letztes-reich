extends StaticBody3D
## Strassensperre am Spreebogen (Mittelstueck): Betonbloecke, Sandsaecke, Stacheldraht auf einem Lkw-Wrack.
## Nur Explosionen zaehlen (Maschinenkanone, Panzer). Bei 0: Explosion, Trümmer, Durchfahrt frei.

signal destroyed

const VF := preload("res://game/vehicles/vehicle_fx.gd")

var max_health: float = 240.0
var health: float = 240.0
var dead: bool = false
var size := Vector3(9.0, 2.4, 2.2)
var _visual: Node3D

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("spree_target")
	collision_layer = 1
	collision_mask = 0
	set_meta("surface", "concrete")
	set_meta("aim_offset", Vector3(0, 1.1, 0))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = Vector3(0, size.y / 2.0, 0)
	add_child(cs)
	_visual = Node3D.new()
	add_child(_visual)
	var conc := VF.mat("spree_conc", Color(0.5, 0.49, 0.46), 0.9, 0.0)
	var sand := VF.mat("spree_sand", Color(0.42, 0.37, 0.27), 0.95, 0.0)
	var rust := VF.mat("spree_rust", Color(0.3, 0.17, 0.1), 0.8, 0.4)
	var wire := VF.mat("spree_wire", Color(0.25, 0.25, 0.24), 0.5, 0.8)
	for i in 4:
		var x := -3.4 + i * 2.25
		VF.mesh_node(_visual, VF.box(Vector3(2.0, 1.2, 1.0)), conc, Vector3(x, 0.6, 0.45), Vector3(0, randf_range(-6, 6), 0))
	# Lkw-Pritsche quer (verrostet) mit Sandsaecken
	VF.mesh_node(_visual, VF.box(Vector3(8.4, 0.25, 2.0)), rust, Vector3(0, 1.35, -0.3))
	VF.mesh_node(_visual, VF.box(Vector3(8.4, 0.9, 0.12)), rust, Vector3(0, 1.0, -1.25))
	for i in 9:
		VF.mesh_node(_visual, VF.box(Vector3(0.9, 0.32, 0.55)), sand, Vector3(-3.8 + i * 0.95, 1.65, -0.1 + (i % 2) * 0.1), Vector3(0, randf_range(-12, 12), randf_range(-4, 4)))
	for i in 7:
		VF.mesh_node(_visual, VF.box(Vector3(0.85, 0.3, 0.5)), sand, Vector3(-3.3 + i * 1.1, 1.95, 0.0), Vector3(0, randf_range(-12, 12), 0))
	# Stacheldraht-Rolle oben
	for i in 10:
		VF.mesh_node(_visual, VF.cyl(0.32, 0.32, 0.03, 10), wire, Vector3(-4.0 + i * 0.88, 2.45, 0.1), Vector3(0, 0, 90))

func take_damage(amount: float, source: Node, hit_position: Vector3, _n: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	if not bool(Combat.get("explosion_active")) and amount < 500.0:
		return
	health -= amount
	VFX.spawn_dust_cloud(hit_position, 1.6)
	if health <= 0.0:
		_destroy(source)

func is_alive() -> bool:
	return not dead

func get_damage_points() -> Array[Vector3]:
	var b := global_transform
	return [b * Vector3(-3.0, 1.2, 0.0), b * Vector3(0, 1.2, 0.0), b * Vector3(3.0, 1.2, 0.0), b * Vector3(0, 2.0, 0.6)]

func get_collision_rids() -> Array[RID]:
	return [get_rid()]

func _destroy(_source: Node) -> void:
	dead = true
	remove_from_group("damageable")
	destroyed.emit()
	var p := global_position + Vector3.UP * 1.2
	call_deferred("_finish", p)

func _finish(p: Vector3) -> void:
	Combat.explode(p, 6.0, 120.0, self, 2.0)
	VFX.spawn_explosion(p, 2.2)
	VFX.spawn_dust_cloud(p, 7.0)
	VF.play_at(self, "explosion_3", p, 6.0, 30.0, 600.0)
	# Truemmer: flache, ueberfahrbare Reste, Kollision weg
	for c in get_children():
		if c is CollisionShape3D:
			c.queue_free()
	_visual.queue_free()
	var deb := Node3D.new()
	add_child(deb)
	var conc := VF.mat("spree_conc", Color(0.5, 0.49, 0.46), 0.9, 0.0)
	for i in 8:
		VF.mesh_node(deb, VF.box(Vector3(randf_range(0.5, 1.2), randf_range(0.2, 0.45), randf_range(0.5, 1.0))), conc,
			Vector3(randf_range(-5, 5), 0.15, randf_range(-2.5, 2.5)), Vector3(randf_range(-20, 20), randf_range(0, 180), randf_range(-20, 20)))
	VF.char_all(deb)
