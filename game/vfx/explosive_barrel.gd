extends RigidBody3D
## Explosives rotes Fass: damageable, 30 HP. Bei Zerstoerung Combat.explode + brennendes Wrack.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const FireScene = preload("res://game/vfx/fire.tscn")

@export var max_health: float = 30.0
@export var blast_radius: float = 7.0
@export var blast_damage: float = 140.0
@export var blast_visual_scale: float = 1.7
@export var chain_delay_min: float = 0.06
@export var chain_delay_max: float = 0.24
@export var wreck_burn_time: float = 70.0

var health: float
var _armed: bool = false
var _exploded: bool = false
var _body_mesh: MeshInstance3D
var _parts: Array[MeshInstance3D] = []

static var _mat_red: StandardMaterial3D
static var _mat_dark: StandardMaterial3D
static var _mat_yellow: StandardMaterial3D
static var _mat_burnt: StandardMaterial3D

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	collision_layer = 1
	collision_mask = 1
	mass = 45.0
	can_sleep = true
	_build_visual()
	set_physics_process(false)

static func _materials() -> void:
	if _mat_red != null:
		return
	var tex := VfxLib.tex("res://assets/textures/rusty_metal_02/diffuse.jpg")
	var nrm := VfxLib.tex("res://assets/textures/rusty_metal_02/normal.jpg")
	var arm := VfxLib.tex("res://assets/textures/rusty_metal_02/arm.jpg")
	_mat_red = _metal(tex, nrm, arm, Color(0.78, 0.06, 0.04), 0.55)
	_mat_dark = _metal(tex, nrm, arm, Color(0.22, 0.04, 0.03), 0.6)
	_mat_yellow = _metal(tex, nrm, arm, Color(0.95, 0.72, 0.1), 0.5)
	_mat_burnt = _metal(tex, nrm, arm, Color(0.07, 0.065, 0.06), 0.8)

static func _metal(tex: Texture2D, nrm: Texture2D, arm: Texture2D, tint: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = nrm
	m.roughness = rough
	m.metallic = 0.45
	m.metallic_specular = 0.6
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(1.6, 1.6, 1.6)
	return m

func _cyl(radius: float, height: float, y: float, mat: Material, segs: int = 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = c
	mi.material_override = mat
	mi.position.y = y
	add_child(mi)
	_parts.append(mi)
	return mi

func _build_visual() -> void:
	_materials()
	_body_mesh = _cyl(0.29, 0.9, 0.0, _mat_red)
	_cyl(0.305, 0.045, -0.3, _mat_dark)
	_cyl(0.305, 0.045, 0.3, _mat_dark)
	_cyl(0.297, 0.14, 0.0, _mat_yellow)
	_cyl(0.255, 0.03, 0.455, _mat_dark)
	if get_node_or_null("CollisionShape3D") == null:
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.3
		sh.height = 0.92
		cs.shape = sh
		add_child(cs)

func is_alive() -> bool:
	return health > 0.0 and not _exploded

func take_damage(amount: float, source: Node, _hit_position: Vector3, _hit_normal: Vector3) -> void:
	if _armed:
		return
	health -= amount
	if health <= 0.0:
		_armed = true
		var d := randf_range(chain_delay_min, chain_delay_max)
		get_tree().create_timer(d).timeout.connect(func() -> void: _detonate(source))

func _detonate(source: Node) -> void:
	if _exploded or not is_inside_tree():
		return
	_exploded = true
	remove_from_group("damageable")
	var pos := global_position + Vector3.UP * 0.45
	Combat.explode(pos, blast_radius, blast_damage, source if source != null else self, blast_visual_scale)
	_become_wreck()

func _become_wreck() -> void:
	for p in _parts:
		p.material_override = _mat_burnt
	# Feuer zeitversetzt aufbauen: Kettenexplosionen erzeugen sonst mehrere
	# Feuer (Partikel + Licht + Rauch) im selben Frame wie die Explosion.
	get_tree().create_timer(randf_range(0.06, 0.3)).timeout.connect(_spawn_wreck_fire)

func _spawn_wreck_fire() -> void:
	if not is_inside_tree():
		return
	var fire: Node3D = FireScene.instantiate()
	fire.set("size", 0.85)
	fire.set("light_energy", 5.0)
	fire.set("light_range", 11.0)
	fire.set("burn_time", wreck_burn_time)
	fire.set("smoke_amount", 12)
	add_child(fire)
	fire.position = Vector3(0, 0.45, 0)
	# Fire soll beim Rollen/Fallen aufrecht bleiben
	fire.top_level = true
	fire.global_position = global_position + Vector3.UP * 0.5
	set_physics_process(true)
	_follow = fire

var _follow: Node3D

func _physics_process(_delta: float) -> void:
	if _follow != null and is_instance_valid(_follow):
		_follow.global_position = global_position + Vector3.UP * 0.45
	elif _exploded:
		set_physics_process(false)
