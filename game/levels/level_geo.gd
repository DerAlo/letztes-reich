extends RefCounted
## Geometrie-Helfer fuer den Level-Builder: Materialien (PBR, triplanar), Box-Meshes aus
## Teilstuecken, Statik-/Rigid-Bodies. Statische Funktionen, per preload() einbinden.

const TEX_DIR := "res://assets/textures/"

static var _mat_cache: Dictionary = {}

## PBR-Material aus einem Poly-Haven-Ordner (diffuse/normal/arm), triplanar in Weltkoordinaten.
## scale = Kacheln pro Meter.
static func mat(dir: String, tint: Color = Color.WHITE, scale: float = 0.3, rough_mul: float = 1.0, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [dir, tint.to_html(), scale, rough_mul, metallic]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX_DIR + dir + "/diffuse.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX_DIR + dir + "/normal.jpg")
	m.roughness_texture = load(TEX_DIR + dir + "/arm.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = rough_mul
	m.ao_enabled = true
	m.ao_texture = load(TEX_DIR + dir + "/arm.jpg")
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = metallic
	if metallic > 0.0:
		m.metallic_texture = load(TEX_DIR + dir + "/arm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	# Anisotrop + Mipmaps (Texturen werden mit Mipmaps importiert): Boeden in flachem Winkel bleiben scharf
	# und flimmern nicht. Die Staerke regelt Graphics ueber Viewport.anisotropic_filtering_level.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m

static func flat(color: Color, rough: float = 0.85, metallic: float = 0.0, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%s|%s|%s|%s" % [color.to_html(), rough, metallic, emission.to_html(), emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mat_cache[key] = m
	return m

# --- Mesh-Bau -----------------------------------------------------------------

## Sammelt Boxen (Mitte, Groesse, optionale Rotation) zu einem einzigen ArrayMesh.
class BoxBatch:
	var st := SurfaceTool.new()
	var count: int = 0
	var unit := BoxMesh.new()
	var ball := SphereMesh.new()
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		ball.radius = 0.5
		ball.height = 1.0
		ball.radial_segments = 10
		ball.rings = 5
	func add(center: Vector3, size: Vector3, rot: Basis = Basis.IDENTITY) -> void:
		var b := rot.scaled_local(size)
		st.append_from(unit, 0, Transform3D(b, center))
		count += 1
	## Abgerundeter Klumpen (Sandsack u. ae.): Ellipsoid mit Halbachsen size/2.
	func add_ball(center: Vector3, size: Vector3, rot: Basis = Basis.IDENTITY) -> void:
		st.append_from(ball, 0, Transform3D(rot.scaled_local(size), center))
		count += 1
	func build() -> ArrayMesh:
		if count == 0:
			return null
		return st.commit()

static func batch() -> BoxBatch:
	return BoxBatch.new()

static func mesh_node(mesh: Mesh, material: Material, pos: Vector3 = Vector3.ZERO, shadows: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func box_mesh_node(size: Vector3, material: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := mesh_node(bm, material, pos)
	mi.rotation_degrees = rot_deg
	return mi

static func add_box_shape(body: CollisionObject3D, center: Vector3, size: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	cs.rotation_degrees = rot_deg
	body.add_child(cs)
	return cs

## Statischer Koerper auf Layer 1 (world).
static func static_body(pos: Vector3 = Vector3.ZERO, yaw_deg: float = 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	b.collision_mask = 0
	b.position = pos
	b.rotation_degrees.y = yaw_deg
	return b

## Einfache Box mit Mesh + Kollision (optional ohne Kollision).
static func solid_box(parent: Node, pos: Vector3, size: Vector3, material: Material, yaw_deg: float = 0.0, collide: bool = true) -> StaticBody3D:
	var b := static_body(pos, yaw_deg)
	b.add_child(box_mesh_node(size, material, Vector3.ZERO))
	if collide:
		add_box_shape(b, Vector3.ZERO, size)
	parent.add_child(b)
	return b

static func marker(parent: Node, pos: Vector3, group: String = "") -> Marker3D:
	var m := Marker3D.new()
	m.position = pos
	if group != "":
		m.add_to_group(group)
	parent.add_child(m)
	return m

static func cylinder_node(radius: float, height: float, material: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, segments: int = 12) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = segments
	cm.rings = 1
	var mi := mesh_node(cm, material, pos)
	mi.rotation_degrees = rot_deg
	return mi
