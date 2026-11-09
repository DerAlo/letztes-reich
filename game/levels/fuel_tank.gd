extends StaticBody3D
## Liegender Treibstofftank auf Boecken: damageable, explodiert gross und brennt danach.

const NightProps = preload("res://game/levels/night_props.gd")
const Props = preload("res://game/levels/level_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

signal exploded

@export var max_health: float = 60.0
@export var blast_radius: float = 9.0
@export var blast_damage: float = 170.0
@export var blast_visual: float = 2.6
@export var length: float = 4.2

var health: float
var _alive: bool = true
var _shell: MeshInstance3D

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	collision_layer = 1
	collision_mask = 0
	var m := NightProps.metal(Color(0.32, 0.36, 0.3), 0.55)
	_shell = Geo.cylinder_node(0.95, length, m, Vector3(0, 1.45, 0), Vector3(0, 0, 90), 18)
	add_child(_shell)
	var stripe := Geo.cylinder_node(0.97, 0.3, NightProps.metal(Color(0.7, 0.55, 0.1), 0.3), Vector3(length * 0.25, 1.45, 0), Vector3(0, 0, 90), 18)
	add_child(stripe)
	var b := Geo.batch()
	for x in [-length * 0.32, length * 0.32]:
		b.add(Vector3(x, 0.4, 0), Vector3(0.25, 0.8, 1.7))
	b.add(Vector3(0, 2.45, 0), Vector3(0.5, 0.15, 0.5))
	NightProps.add_batch(self, b, NightProps.metal(Color(0.15, 0.15, 0.14), 0.3))
	Geo.add_box_shape(self, Vector3(0, 1.2, 0), Vector3(length, 2.4, 1.9))

func is_alive() -> bool:
	return _alive

func take_damage(amount: float, _source: Node = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	if not _alive:
		return
	health -= amount
	if hit_position != Vector3.ZERO:
		VFX.spawn_impact(hit_position, hit_normal, "metal")
	if health <= 0.0:
		_alive = false
		# Kettenreaktion leicht verzoegert (vermeidet Rekursion im Combat-Loop)
		get_tree().create_timer(0.08).timeout.connect(_explode)

func _explode() -> void:
	var p := global_position + Vector3(0, 1.4, 0)
	Combat.explode(p, blast_radius, blast_damage, self, blast_visual)
	VFX.spawn_scorch(global_position + Vector3(0, 0.05, 0), Vector3.UP, 6.0)
	_shell.material_override = Geo.flat(Color(0.05, 0.045, 0.04), 0.9, 0.3)
	_shell.scale = Vector3(1.0, 0.85, 0.8)
	_shell.rotation_degrees = Vector3(0, 12, 84)
	Props.fire(get_parent(), global_position + Vector3(0, 1.2, 0), 1.5, true, 1.8, 9.0)
	exploded.emit()
