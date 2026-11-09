extends RefCounted
## Gemeinsame Umgebung (Himmel aus HDRI, SDFGI, Volumetric Fog, Glow, Tonemap, Farbkorrektur)
## fuer Level und Showcase. Statische Helfer, per preload() einbinden.

const HDRI_PATH := "res://assets/hdri/kloppenheim_01_puresky_2k.hdr"

## Richtung, aus der das Sonnenlicht KOMMT (zeigt zur Sonne), normalisiert.
const SUN_AZIMUTH_DEG := 200.0   # 180 = aus -Z (Ende der Strasse), leicht links davon
const SUN_ELEVATION_DEG := 9.0

static func sun_to_dir() -> Vector3:
	var az := deg_to_rad(SUN_AZIMUTH_DEG)
	var el := deg_to_rad(SUN_ELEVATION_DEG)
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()

static func make_environment(fog_density: float = 0.005, sky_energy: float = 1.0) -> Environment:
	var env := Environment.new()
	# Himmel
	var sky := Sky.new()
	var mat := PanoramaSkyMaterial.new()
	mat.panorama = load(HDRI_PATH)
	mat.energy_multiplier = sky_energy
	sky.sky_material = mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0.0, deg_to_rad(SKY_YAW_OFFSET_DEG), 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Tonemap: AgX, etwas Kontrast
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 0.8
	env.tonemap_white = 6.0

	# Globale Beleuchtung und Screenspace
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.4
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_energy = 1.0
	env.sdfgi_read_sky_light = true
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssil_enabled = true
	env.ssil_radius = 4.0
	env.ssil_intensity = 1.0
	env.ssr_enabled = true
	env.ssr_max_steps = 96
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

	# Nebel: Tiefennebel fuer Dunst, Volumetric Fog fuer Lichtstreuung
	env.fog_enabled = true
	env.fog_light_color = Color(0.46, 0.5, 0.58)
	env.fog_light_energy = 0.8
	env.fog_density = 0.0012
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.35
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = fog_density
	env.volumetric_fog_albedo = Color(0.5, 0.54, 0.62)
	env.volumetric_fog_emission = Color(0.03, 0.035, 0.045)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_ambient_inject = 0.3
	env.volumetric_fog_sky_affect = 0.3
	env.volumetric_fog_temporal_reprojection_enabled = true

	# Glow
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.5
	env.glow_strength = 1.0
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.3
	env.glow_hdr_scale = 1.2
	env.glow_hdr_luminance_cap = 24.0
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 0.8)
	env.set_glow_level(5, 0.5)
	env.set_glow_level(6, 0.3)

	# Farbkorrektur: entsaettigt, kalte Schatten, warme Lichter
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 0.82
	env.adjustment_color_correction = _grade_ramp()
	return env

const SKY_YAW_OFFSET_DEG := -123.8

static func _grade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 0.75, 1.0])
	g.colors = PackedColorArray([
		Color(0.0, 0.012, 0.03),
		Color(0.32, 0.345, 0.38),
		Color(0.77, 0.755, 0.72),
		Color(1.0, 0.97, 0.9)])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t

static func make_camera_attributes() -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = false
	return ca

static func make_sun() -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.66, 0.42)
	sun.light_energy = 2.6
	sun.light_indirect_energy = 1.0
	sun.light_volumetric_fog_energy = 1.6
	sun.light_angular_distance = 0.9
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 160.0
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.5
	var look := -sun_to_dir()
	sun.transform = Transform3D(Basis.looking_at(look, Vector3.UP), Vector3.ZERO)
	return sun

## Qualitaetsregler, die nicht ueber project.godot laufen.
static func apply_render_quality(vp: Viewport) -> void:
	RenderingServer.environment_set_volumetric_fog_volume_size(160, 96)
	RenderingServer.environment_set_volumetric_fog_filter_active(true)
	vp.positional_shadow_atlas_size = 4096
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
