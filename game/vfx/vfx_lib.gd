extends RefCounted
## Gemeinsame Helfer fuer Effekte (statisch, ohne class_name; per preload() einbinden).

static var _shaders: Dictionary = {}
static var _cache: Dictionary = {}

static func shader(shader_name: String) -> Shader:
	if not _shaders.has(shader_name):
		_shaders[shader_name] = load("res://game/vfx/shaders/%s.gdshader" % shader_name)
	return _shaders[shader_name]

static func noise_tex() -> Texture2D:
	if not _cache.has("noise"):
		_cache["noise"] = load("res://assets/vfx/noise_tile.png")
	return _cache["noise"]

static func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]

static func shader_mat(shader_name: String, params: Dictionary = {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader(shader_name)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m

static func fire_mat(params: Dictionary = {}) -> ShaderMaterial:
	var m := shader_mat("fire_billboard", params)
	m.set_shader_parameter("noise_tex", noise_tex())
	return m

## Globale Windrichtung (m/s^2 als Partikel-Beschleunigung, wird pro Effekt skaliert).
const WIND := Vector3(0.55, 0.0, 0.22)

static func smoke_flipbook() -> Texture2D:
	if not _cache.has("smoke_fb"):
		_cache["smoke_fb"] = load("res://assets/vfx/smoke_flipbook.png")
	return _cache["smoke_fb"]

## Weicher Rauch/Staub (siehe shaders/smoke_billboard.gdshader). Farben als Color oder Vector3.
## fast = true: ohne Schattenempfang (fuer Explosionen/Einschlaege mit viel Overdraw).
static func smoke_mat(params: Dictionary = {}, fast: bool = false) -> ShaderMaterial:
	var m := shader_mat("smoke_billboard_fast" if fast else "smoke_billboard", params)
	m.set_shader_parameter("flipbook", smoke_flipbook())
	m.set_shader_parameter("detail_tex", smoke_detail())
	return m

## Animierte Detail-Schicht fuer Rauch (RG = Curl-Verzerrung, B = feines Billow-Noise), kachelbar.
static func smoke_detail() -> Texture2D:
	if not _cache.has("smoke_detail"):
		_cache["smoke_detail"] = load("res://assets/vfx/smoke_detail.png")
	return _cache["smoke_detail"]

## Gemeinsame Rauch-Partikel-Einstellungen: langsame Rotation, Zufalls-Frame (anim_offset -> CUSTOM.z).
static func smoke_pm(pm: ParticleProcessMaterial, spin_deg: float = 10.0) -> ParticleProcessMaterial:
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -spin_deg
	pm.angular_velocity_max = spin_deg
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	pm.anim_speed_min = 0.0
	pm.anim_speed_max = 0.0
	return pm

## Weiche Alpha-Kurve fuer Rauch (Ein-/Ausblenden), als Farbverlauf fuer color_ramp.
static func smoke_alpha_ramp(peak: float = 1.0, fade_in: float = 0.12, hold: float = 0.45) -> GradientTexture1D:
	return ramp([[0.0, Color(1, 1, 1, 0.0)], [fade_in * 0.4, Color(1, 1, 1, peak * 0.45)], [fade_in, Color(1, 1, 1, peak)],
		[hold, Color(1, 1, 1, peak * 0.85)], [lerpf(hold, 1.0, 0.55), Color(1, 1, 1, peak * 0.4)], [1.0, Color(1, 1, 1, 0.0)]])

## Glatte Kurve (Tangenten automatisch) aus [[x, y], ...].
static func smooth_curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	c.max_value = 4.0
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
	for i in c.point_count:
		c.set_point_left_mode(i, Curve.TANGENT_FREE)
		c.set_point_right_mode(i, Curve.TANGENT_FREE)
	c.min_value = 0.0
	c.max_value = 4.0
	c.bake()
	var t := CurveTexture.new()
	t.curve = c
	return t

## Kurve aus [[x, y], ...] (linear) als CurveTexture.
static func curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(Vector2(p[0], p[1]))
		c.set_point_left_mode(c.point_count - 1, Curve.TANGENT_LINEAR)
		c.set_point_right_mode(c.point_count - 1, Curve.TANGENT_LINEAR)
	var t := CurveTexture.new()
	t.curve = c
	return t

## Farbverlauf aus [[offset, Color], ...].
static func ramp(stops: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for s in stops:
		offs.append(s[0])
		cols.append(s[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 128
	return t

static func quad(size: float = 1.0) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	return q

static func make_particles(amount: int, lifetime: float, pm: ParticleProcessMaterial, mesh: Mesh, mat: Material) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, amount)   # 0 (z. B. skalierte/abgeschaltete Partikel) -> Engine-ERROR
	p.lifetime = maxf(0.01, lifetime)
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.process_material = pm
	p.draw_pass_1 = mesh
	p.material_override = mat
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	p.fixed_fps = 0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-30, -6, -30), Vector3(60, 70, 60))
	return p

## Basis, deren Y-Achse der Normalen entspricht (fuer Decals).
static func basis_from_normal(n: Vector3, yaw: float = 0.0) -> Basis:
	var y := n.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var b := Basis(x, y, z)
	return b * Basis(Vector3.UP, yaw)
