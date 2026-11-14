extends RefCounted
## Realistische Zivil-/Story-Figuren in gebackenen Posen (MakeHuman/MPFB2-CC0-Assets, Pipeline
## tools/civilian/prep_civ.py + build_civ.py --poses=..., siehe assets/CREDITS_ASSETS.md).
## Dateien: assets/characters/civilian/civ_<kind>_<set>.glb mit je einem Mesh-Objekt pro Pose:
##   set "stand"  -> Pose "stand" (Ursprung unter dem Becken, Sohlen bei y = 0)
##   set "geisel" -> Posen "bound_seat" (Ursprung Gesaess-Unterkante, Sohlen 0,45 m tiefer) und "kneel"
##                   (Ursprung unter dem Becken, Knie/Fuesse bei y = 0); Haende hinter dem Ruecken
## Modelle schauen im GLB nach +Z; die Helfer drehen sie so, dass die Figur lokal nach -Z blickt
## (wie Cutscene.aim / vip_models). Ersetzt die alten Kastenfiguren (curfew, kanalisation, Geiseln).

const DIR := "res://assets/characters/civilian/civ_%s_%s.glb"
const CIV_IDLE = preload("res://game/characters/civ_idle.gd")

static var _meshes: Dictionary = {}     ## "kind/set/pose" -> Mesh (Materialien abgestimmt)

## Mesh der Pose (gecacht, Materialien abgestimmt) oder null, wenn die Datei fehlt.
static func mesh(kind: String, set_name: String, pose: String) -> Mesh:
	var key := "%s/%s/%s" % [kind, set_name, pose]
	if _meshes.has(key):
		return _meshes[key]
	var path := DIR % [kind, set_name]
	var out: Mesh = null
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var root := ps.instantiate()
			var src := root.find_child(pose, true, false) as MeshInstance3D
			if src != null and src.mesh != null:
				out = src.mesh.duplicate()
				for i in out.get_surface_count():
					var m := out.surface_get_material(i) as BaseMaterial3D
					if m != null:
						out.surface_set_material(i, tune(m.duplicate() as BaseMaterial3D))
				_add_idle(out)
			root.free()
	_meshes[key] = out
	return out

# ------------------------------------------------------------------ Idle-Leben (Vertex-Shader)
## Die Posen sind gebackene, ungeriggte Meshes. Damit die Figuren nicht wie Puppen erstarren, bekommen ihre
## Materialien einen Vertex-Zusatz: Kopf/Hals drehen um den Halsansatz (Blickwechsel), der Brustkorb hebt und
## weitet sich beim Atmen, die Schultern gehen mit. Getrieben je Figur ueber den Instanz-Parameter idle_state
## (game/characters/civ_idle.gd: x Yaw, y Pitch, z Atem -1..1). idle_state = 0 -> exakt die gebackene Pose.
## Eigener Shader mit denselben Werten wie das abgestimmte BaseMaterial3D (tune()); passt ein Material nicht ins
## Schema, bleibt es unveraendert (diese Flaeche dann ohne Idle-Verformung).
const IDLE_DECL := """
uniform vec3 idle_neck = vec3(0.0, 1.5, 0.0);
instance uniform vec4 idle_state = vec4(0.0);
void idle_deform(inout vec3 v, inout vec3 n, inout vec3 tg, inout vec3 bn) {
	vec3 p = v - idle_neck;
	float br = idle_state.z;
	float chest = smoothstep(-0.52, -0.32, p.y) * (1.0 - smoothstep(-0.12, -0.02, p.y));
	float front = clamp(n.z * 0.6 + 0.55, 0.0, 1.0);
	p += n * (0.0035 * br * chest * front);
	p.y += 0.0025 * br * smoothstep(-0.3, -0.06, p.y);
	float hw = smoothstep(-0.01, 0.08, p.y);
	float cy = cos(idle_state.x * hw);
	float sy = sin(idle_state.x * hw);
	float cp = cos(-idle_state.y * hw);
	float sp = sin(-idle_state.y * hw);
	mat3 r = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy))
		* mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cp, sp), vec3(0.0, -sp, cp));
	v = idle_neck + r * p;
	n = r * n;
	tg = r * tg;
	bn = r * bn;
}
"""
static var _idle_shaders: Dictionary = {}   ## Art (opaque/skin/scissor) -> Shader (von allen Figuren geteilt)

## Halsansatz der Pose (Mesh-Raum, Blick +Z): Kopfoberkante (AABB) minus 0,24 m, x/z = Mitte der Kopf-Vertices.
static func neck_point(m: Mesh) -> Vector3:
	var top := m.get_aabb().end.y
	var acc := Vector3.ZERO
	var n := 0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for v in vs:
			if v.y > top - 0.14:
				acc += v
				n += 1
	var c := acc / float(n) if n > 0 else Vector3(0.0, top, 0.0)
	return Vector3(c.x, top - 0.24, c.z)

static func _add_idle(m: Mesh) -> void:
	var neck := neck_point(m)
	for i in m.get_surface_count():
		var bm := m.surface_get_material(i) as BaseMaterial3D
		if bm == null:
			continue
		var sm := idle_material(bm, neck)
		if sm != null:
			m.surface_set_material(i, sm)

## ShaderMaterial mit gleichem Aussehen wie das abgestimmte bm (tune(): Albedo-Textur, Rauheit, Spekular, Haut-SSS,
## Haare Alpha-Scissor + Alpha-to-Coverage, beidseitig) plus Idle-Vertex-Zusatz; null bei unbekannter Konfiguration.
static func idle_material(bm: BaseMaterial3D, neck: Vector3) -> ShaderMaterial:
	if bm.normal_enabled or bm.metallic_texture != null or bm.roughness_texture != null or bm.emission_enabled:
		return null   # die Figuren nutzen nur Albedo-Textur + Werte; alles andere bleibt beim Original
	var kind := "opaque"
	if bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		kind = "scissor"
	elif bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return null
	elif bm.subsurf_scatter_enabled:
		kind = "skin"
	var sh: Shader = _idle_shaders.get(kind)
	if sh == null:
		sh = Shader.new()
		sh.code = _idle_code(kind)
		_idle_shaders[kind] = sh
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.resource_name = bm.resource_name
	sm.set_shader_parameter(&"albedo", bm.albedo_color)
	if bm.albedo_texture != null:
		sm.set_shader_parameter(&"albedo_tex", bm.albedo_texture)
	sm.set_shader_parameter(&"uv_scale", Vector2(bm.uv1_scale.x, bm.uv1_scale.y))
	sm.set_shader_parameter(&"uv_offset", Vector2(bm.uv1_offset.x, bm.uv1_offset.y))
	sm.set_shader_parameter(&"roughness", bm.roughness)
	sm.set_shader_parameter(&"specular", bm.metallic_specular)
	sm.set_shader_parameter(&"metallic", bm.metallic)
	sm.set_shader_parameter(&"sss_strength", bm.subsurf_scatter_strength)
	sm.set_shader_parameter(&"alpha_scissor", bm.alpha_scissor_threshold)
	sm.set_shader_parameter(&"idle_neck", neck)
	return sm

static func _idle_code(kind: String) -> String:
	var modes := "blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx"
	var extra := ""
	if kind == "skin":
		modes += ", sss_mode_skin"
		extra = "\tSSS_STRENGTH = sss_strength;\n"
	elif kind == "scissor":
		modes += ", alpha_to_coverage"
		extra = "\tALPHA = c.a;\n\tALPHA_SCISSOR_THRESHOLD = alpha_scissor;\n\tALPHA_ANTIALIASING_EDGE = 0.3;\n" \
			+ "\tALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_tex, 0));\n"
	return "shader_type spatial;\nrender_mode " + modes + ";\n" + """
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float roughness = 0.8;
uniform float specular = 0.5;
uniform float metallic = 0.0;
uniform float sss_strength = 0.0;
uniform float alpha_scissor = 0.5;
""" + IDLE_DECL + """
void vertex() {
	idle_deform(VERTEX, NORMAL, TANGENT, BINORMAL);
}
void fragment() {
	vec4 c = texture(albedo_tex, UV * uv_scale + uv_offset) * albedo;
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = metallic;
""" + extra + "}\n"

## MeshInstance der Pose (Blick lokal -Z) oder null.
static func instance(kind: String, set_name: String, pose: String, shadows: bool = true) -> MeshInstance3D:
	var m := mesh(kind, set_name, pose)
	if m == null:
		return null
	var mi := MeshInstance3D.new()
	mi.name = "Figure_%s" % kind
	mi.mesh = m
	mi.rotation.y = PI
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 90.0
	mi.visibility_range_end_margin = 6.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	# Idle-Leben (Atmen, Blickwechsel): Treiber als Kind, nur wirksam mit Idle-Materialien
	var drv := CIV_IDLE.new()
	drv.name = "CivIdle"
	drv.mesh_inst = mi
	mi.add_child(drv)
	return mi

## Stehende Figur mit Kollider (Blick nach -Z bei yaw 0). null, wenn das Modell fehlt
## (das Level baut dann seinen alten Ersatz).
static func stand(parent: Node, kind: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var mi := instance(kind, "stand", "stand")
	if mi == null:
		return null
	var root := Node3D.new()
	root.name = "NPC_%s" % kind
	parent.add_child(root)
	root.position = pos
	root.rotation_degrees.y = yaw_deg
	root.add_child(mi)
	var drv := mi.get_node_or_null("CivIdle")
	if drv != null:
		drv.set("sway", true)   # stehend: leichtes Pendeln um die Fuesse
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.26
	cap.height = 1.78
	cs.shape = cap
	cs.position = Vector3(0, 0.89, 0)
	sb.add_child(cs)
	root.add_child(sb)
	return root

## Materialabstimmung wie bei den Nachtzug-Reisenden (Haut mit SSS, Haare Alpha-Scissor).
static func tune(m: BaseMaterial3D) -> BaseMaterial3D:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var n := m.resource_name.to_lower()
	if n.begins_with("skin"):
		m.roughness = 0.58
		m.metallic_specular = 0.35
		m.subsurf_scatter_enabled = true
		m.subsurf_scatter_strength = 0.35
		m.subsurf_scatter_skin_mode = true
	elif n.begins_with("eye"):
		m.roughness = 0.08
		m.metallic_specular = 0.7
	elif n.begins_with("brow") or n.begins_with("lash") or n.begins_with("hair"):
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.45
		m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.75
		m.metallic_specular = 0.25
	elif n.begins_with("suit"):
		m.roughness = 0.92
		m.metallic_specular = 0.2
	elif n.begins_with("shoes"):
		m.roughness = 0.4
		m.metallic_specular = 0.4
	return m
