class_name Grenade
extends RigidBody3D
## Splittergranate: Zünder, dann Combat.explode.

@export var fuse_time: float = 2.5
@export var blast_radius: float = 7.0
@export var blast_damage: float = 150.0

var thrower: Node = null
var _t: float = 0.0
var _exploded: bool = false
@onready var _blink: OmniLight3D = $Blink
@onready var _lamp: MeshInstance3D = $Lamp
@onready var _audio: AudioStreamPlayer3D = $Audio

func _ready() -> void:
	collision_mask |= 16   # Levelgrenzen (move_block) halten Granaten auf
	add_to_group("grenade")
	_t = fuse_time
	contact_monitor = true
	max_contacts_reported = 2
	body_entered.connect(func(_b: Node) -> void: Sfx.play_on(_audio, "grenade_bounce", 0.1))

func setup(who: Node) -> void:
	thrower = who

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_t -= delta
	# Blinken, wird zum Ende schneller
	var rate: float = lerpf(4.0, 22.0, 1.0 - clampf(_t / fuse_time, 0.0, 1.0))
	var on: bool = sin(_t * rate * TAU) > 0.0
	_blink.visible = on
	_lamp.visible = on
	if _t <= 0.0:
		_explode()

func _explode() -> void:
	_exploded = true
	var src: Node = thrower if is_instance_valid(thrower) else null
	Combat.explode(global_position, blast_radius, blast_damage, src)
	queue_free()
