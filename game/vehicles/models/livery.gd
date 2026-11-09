extends RefCounted
## Lackierungen der Fahrzeuge je Fraktion (Material = vehicle_paint.gdshader, gecacht).
## "ru": russisches Dreifarb-Gruen/Schwarz/Sand; "eu": NATO-Oliv; "reich" (Ordnungsfront): Stahlgrau/Schwarz + Amber-Akzent.

const PAINT_SHADER := "res://game/vehicles/shaders/vehicle_paint.gdshader"
const NOISE_TEX := "res://assets/vehicles/textures/vehicle_noise.png"
const RUST_DIR := "res://assets/vehicles/textures/green_metal_rust/"
const DECAL_NUMBERS := "res://assets/vehicles/textures/tac_numbers.png"
const EMBLEM_TEX := "res://assets/environment/berlin/emblem.png"

const AMBER := Color(1.0, 0.6, 0.12)

static var _cache: Dictionary = {}

## Farben der Fraktion: [Grundton, dunkel, hell, Akzent, Tarn-Schwellen].
static func colors(faction: String) -> Array:
	match faction:
		"reich":
			return [Color(0.33, 0.34, 0.35), Color(0.05, 0.052, 0.055), Color(0.2, 0.205, 0.21), AMBER, Vector2(0.3, 0.8)]
		"eu":
			return [Color(0.24, 0.26, 0.2), Color(0.08, 0.08, 0.065), Color(0.33, 0.29, 0.21), Color(0.75, 0.75, 0.7), Vector2(0.34, 0.72)]
		_:
			return [Color(0.28, 0.3, 0.19), Color(0.085, 0.09, 0.065), Color(0.42, 0.38, 0.26), Color(0.82, 0.82, 0.78), Vector2(0.33, 0.7)]

## Lackmaterial (geteilt). kind: "tank" | "heli" (Heli: groessere Flecken, weniger Rost/Schmutz).
static func paint(kind: String, faction: String) -> ShaderMaterial:
	var key := kind + "_" + faction
	if _cache.has(key):
		return _cache[key]
	var c := colors(faction)
	var m := ShaderMaterial.new()
	m.shader = load(PAINT_SHADER) as Shader
	m.set_shader_parameter("noise_tex", load(NOISE_TEX))
	m.set_shader_parameter("rust_albedo", load(RUST_DIR + "diffuse.jpg"))
	m.set_shader_parameter("rust_normal", load(RUST_DIR + "normal.jpg"))
	m.set_shader_parameter("rust_arm", load(RUST_DIR + "arm.jpg"))
	m.set_shader_parameter("camo_a", c[0])
	m.set_shader_parameter("camo_b", c[1])
	m.set_shader_parameter("camo_c", c[2])
	m.set_shader_parameter("accent_col", c[3])
	m.set_shader_parameter("camo_split", c[4])
	if kind == "heli":
		m.set_shader_parameter("camo_scale", 0.075)
		m.set_shader_parameter("rust_amount", 0.12)
		m.set_shader_parameter("chip_amount", 0.25)
		m.set_shader_parameter("dirt_amount", 0.25)
		m.set_shader_parameter("dirt_height", 0.6)
		m.set_shader_parameter("dust_amount", 0.12)
		m.set_shader_parameter("normal_strength", 0.35)
		m.set_shader_parameter("paint_rough", 0.55)
		m.set_shader_parameter("detail_scale", 0.4)
	elif kind == "tank_wheel":
		m.set_shader_parameter("dirt_height", 1.0)
		m.set_shader_parameter("dirt_amount", 1.0)
	if faction == "reich":
		m.set_shader_parameter("rust_amount", 0.3 if kind != "heli" else 0.06)
		m.set_shader_parameter("paint_rough", 0.5 if kind != "heli" else 0.45)
		m.set_shader_parameter("paint_metal", 0.15)
	_cache[key] = m
	return m

## Abziehbild (Alpha-Scissor). region = UV-Ausschnitt (offset.xy, scale.zw).
static func decal_mat(tex_path: String, region: Vector4 = Vector4(0, 0, 1, 1), tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "decal_%s_%s_%s" % [tex_path, region, tint]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(tex_path)
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.uv1_offset = Vector3(region.x, region.y, 0)
	m.uv1_scale = Vector3(region.z, region.w, 1)
	m.roughness = 0.75
	m.cull_mode = BaseMaterial3D.CULL_BACK
	_cache[key] = m
	return m

## Abziehbild-Quad (Blickrichtung = normal) anhaengen.
static func decal(parent: Node3D, m: Material, pos: Vector3, normal: Vector3, size: Vector2) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	mi.position = pos
	var n := normal.normalized()
	var up := Vector3.UP if absf(n.y) < 0.95 else Vector3.FORWARD
	# QuadMesh zeigt nach +Z -> Basis so drehen, dass +Z = normal
	mi.basis = Basis.looking_at(-n, up)
	return mi
