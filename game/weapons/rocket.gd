class_name Rocket
extends Node3D
## Panzerfaust-Rakete: Projektil mit Rauchspur, Raycast pro Schritt (Maske world|enemy, nie Spieler/Debris),
## Annäherungszünder an Fahrzeugen. Volltreffer: direkter Schaden auf das Ziel + Combat.explode.

const HIT_MASK: int = 1 | 4
const DIRECT_DAMAGE: float = 650.0      # Ziele ohne rocket_hit(); Panzer/Helikopter: rocket_hit() = 1/3 HP (3 Treffer)
const BLAST_RADIUS: float = 6.5
const BLAST_DAMAGE: float = 220.0

var velocity: Vector3 = Vector3.ZERO
var source: Node = null
var _life: float = 0.0
var _trail: GPUParticles3D
var _exploded: bool = false
var _snd: AudioStreamPlayer3D

static var _smoke_mat: StandardMaterial3D
static var _flame_mat: StandardMaterial3D

static func launch(parent: Node, from: Vector3, dir: Vector3, speed: float, src: Node) -> Rocket:
	var r := Rocket.new()
	r.name = "Rocket"
	r.velocity = dir.normalized() * speed
	r.source = src
	parent.add_child(r)
	r.global_position = from
	r._orient()
	return r

func _ready() -> void:
	var model: Node3D = GunModels.build_rocket()
	add_child(model)
	# Triebwerksflamme + Licht
	if _flame_mat == null:
		_flame_mat = StandardMaterial3D.new()
		_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_mat.albedo_color = Color(1.0, 0.75, 0.35)
		_flame_mat.emission_enabled = true
		_flame_mat.emission = Color(1.0, 0.6, 0.2)
		_flame_mat.emission_energy_multiplier = 8.0
	var fl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.05
	sm.height = 0.22
	fl.mesh = sm
	fl.material_override = _flame_mat
	fl.position = Vector3(0, 0, 0.36)
	fl.rotation_degrees = Vector3(90, 0, 0)
	fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fl)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 2.5
	light.omni_range = 6.0
	light.position = Vector3(0, 0, 0.5)
	add_child(light)
	_build_trail()
	_snd = AudioStreamPlayer3D.new()
	_snd.unit_size = 8.0
	add_child(_snd)
	Sfx.play_on(_snd, "rocket_fly", 0.05)

func _build_trail() -> void:
	if _smoke_mat == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1, 1, 1, 1))
		grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.albedo_texture = tex
		_smoke_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_trail = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.1
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.35, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.35))
	sc.add_point(Vector2(1, 2.4))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.6, 0.9))
	ramp.add_point(0.08, Color(0.75, 0.73, 0.7, 0.7))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.6, 0.6, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	_trail.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	q.material = _smoke_mat
	_trail.draw_pass_1 = q
	_trail.amount = 160
	_trail.lifetime = 2.2
	_trail.local_coords = false
	_trail.fixed_fps = 0
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.position = Vector3(0, 0, 0.4)
	_trail.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 120, 120))
	add_child(_trail)
	_trail.emitting = true

func _orient() -> void:
	if velocity.length() > 0.01:
		var up: Vector3 = Vector3.UP if absf(velocity.normalized().y) < 0.98 else Vector3.RIGHT
		look_at(global_position + velocity, up)

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	_life += delta
	velocity.y -= 2.2 * delta
	var from: Vector3 = global_position
	var to: Vector3 = from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK)
	q.collide_with_areas = false
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not res.is_empty():
		_explode(res.position, res.collider as Object, res.normal)
		return
	global_position = to
	_orient()
	# Annäherungszünder (Helikopter-Rumpf ist schwer exakt zu treffen)
	for v in get_tree().get_nodes_in_group("vehicle"):
		var n3: Node3D = v as Node3D
		if n3 == null or (n3.has_method("is_alive") and not n3.is_alive()):
			continue
		var r: float = 3.2 if n3.is_in_group("enemy") else 0.0
		if r > 0.0 and n3.global_position.distance_to(to) < r:
			_explode(to, n3, -velocity.normalized())
			return
	if _life > 6.0:
		_explode(global_position, null, Vector3.UP)

func _explode(pos: Vector3, collider: Object, normal: Vector3) -> void:
	_exploded = true
	var target: Node = _find_damageable(collider)
	if target != null and target != source:
		if target.has_method("rocket_hit"):
			target.call("rocket_hit", source, pos, normal)
		else:
			target.take_damage(DIRECT_DAMAGE, source, pos, normal)
	Combat.explode(pos + normal * 0.2, BLAST_RADIUS, BLAST_DAMAGE, source, 1.6)
	# Rauchspur stehen lassen, Rakete entfernen
	if _trail:
		_trail.emitting = false
		var root: Node = get_parent()
		var gt: Transform3D = _trail.global_transform
		remove_child(_trail)
		root.add_child(_trail)
		_trail.global_transform = gt
		get_tree().create_timer(_trail.lifetime + 0.2).timeout.connect(_trail.queue_free)
	queue_free()

func _find_damageable(n: Object) -> Node:
	var node: Node = n as Node
	var depth: int = 0
	while node and depth < 6:
		# Panzerungs-Collider (vehicle_armor.gd: is_alive() = false) ueberspringen -> das Fahrzeug darueber trifft
		if node.has_method("take_damage") and not node.is_in_group("player") 				and not (node.has_method("is_alive") and not node.call("is_alive") and node is CollisionObject3D and node.get_parent().has_method("take_damage")):
			return node
		node = node.get_parent()
		depth += 1
	return null
