extends RefCounted
## Bildlook pro Level: stimmt Environment/CameraAttributes eines Levels ab (ACES-Tonemapping,
## dezente Auto-Exposure, SSAO/SSIL/SSR, Volumetric Fog) und legt einen Post-Shader ueber das Bild
## (chromatische Aberration, Vignette, Filmkorn). Aufruf am Ende von _setup_environment():
##     PostFx.apply(self, "day_war")
## Profile: "day_war" (Tag, Rauch/Dunst), "night_city" (Stadt bei Nacht), "night_snow" (Winternacht).
## Abschaltbar mit Kommandozeilen-Argument --nopostfx (nur der Bildschirm-Shader).
## Motion Blur gibt es in Godot 4 nicht nativ; ein eigener Pass waere ohne Velocity-Buffer zu teuer
## bzw. ungenau, daher bewusst weggelassen.

const SHADER := preload("res://game/vfx/shaders/post_fx.gdshader")

const PROFILES := {
	"day_war": {
		"tonemap": "agx", "exposure": 0.8, "white": 6.0, "contrast": 1.12, "saturation": 0.84,
		"ae_scale": 0.15, "ae_min": 90.0, "ae_max": 125.0, "ae_speed": 0.6,
		"ssao": 1.7, "ssao_radius": 1.3, "ssao_power": 1.5, "ssil": 0.9,
		"glow": 0.45, "glow_threshold": 1.25,
		"aberration": 0.0016, "vignette": 0.34, "grain": 0.03, "post_sat": 0.96, "lift": Vector3(0.0, 0.0, 0.0),
	},
	"night_city": {
		"tonemap": "agx", "exposure": 1.45, "white": 6.0, "contrast": 1.06, "saturation": 0.95,
		"ae_scale": 0.16, "ae_min": 90.0, "ae_max": 125.0, "ae_speed": 0.5,
		"ssao": 1.4, "ssao_radius": 1.2, "ssao_power": 1.4, "ssil": 1.1,
		"glow": 0.8, "glow_threshold": 1.0,
		"aberration": 0.0018, "vignette": 0.38, "grain": 0.04, "post_sat": 0.95, "lift": Vector3(0.008, 0.009, 0.015),
	},
	"night_snow": {
		"tonemap": "agx", "exposure": 1.1, "white": 6.0, "contrast": 1.04, "saturation": 0.9,
		"ae_scale": 0.12, "ae_min": 90.0, "ae_max": 125.0, "ae_speed": 0.5,
		"ssao": 1.3, "ssao_radius": 1.2, "ssao_power": 1.3, "ssil": 1.0,
		"glow": -1.0, "glow_threshold": -1.0,
		"aberration": 0.0015, "vignette": 0.3, "grain": 0.038, "post_sat": 0.97, "lift": Vector3(0.006, 0.009, 0.016),
	},
}

## Stimmt das WorldEnvironment unter `level` ab und haengt den Post-Shader an. Gibt den CanvasLayer zurueck.
static func apply(level: Node, profile: String) -> CanvasLayer:
	var p: Dictionary = PROFILES.get(profile, PROFILES["day_war"])
	var we := level.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we != null and we.environment != null:
		tune_environment(we.environment, p)
		we.camera_attributes = make_camera_attributes(p)
	if Game.arg("nopostfx", false):
		return null
	return add_overlay(level, p)

static func tune_environment(env: Environment, p: Dictionary) -> void:
	# Filmisches Tonemapping: AgX (weich, entsaettigt in den Lichtern) oder ACES (kontrastreicher)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX if p.get("tonemap", "aces") == "agx" else Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = p["exposure"]
	env.tonemap_white = p["white"]
	env.ssao_enabled = true
	env.ssao_intensity = p["ssao"]
	env.ssao_radius = p["ssao_radius"]
	env.ssao_power = p["ssao_power"]
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_light_affect = 0.05
	env.ssil_enabled = true
	env.ssil_intensity = p["ssil"]
	env.ssil_radius = 3.0
	env.ssr_enabled = true
	env.ssr_max_steps = maxi(env.ssr_max_steps, 64)
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.2
	env.ssr_depth_tolerance = 0.25
	if float(p["glow"]) >= 0.0:
		env.glow_intensity = p["glow"]
		env.glow_hdr_threshold = p["glow_threshold"]
	env.adjustment_enabled = true
	env.adjustment_contrast = p["contrast"]
	env.adjustment_saturation = p["saturation"]

static func make_camera_attributes(p: Dictionary) -> CameraAttributesPractical:
	var ca := CameraAttributesPractical.new()
	ca.auto_exposure_enabled = float(p["ae_scale"]) > 0.0
	ca.auto_exposure_scale = p["ae_scale"]
	ca.auto_exposure_min_sensitivity = p["ae_min"]
	ca.auto_exposure_max_sensitivity = p["ae_max"]
	ca.auto_exposure_speed = p["ae_speed"]
	return ca

static func add_overlay(level: Node, p: Dictionary) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "PostFx"
	layer.layer = 2   # ueber der Waffe (1), unter dem HUD (5)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("aberration", p["aberration"])
	m.set_shader_parameter("vignette", p["vignette"])
	m.set_shader_parameter("grain", p["grain"])
	m.set_shader_parameter("saturation", p["post_sat"])
	m.set_shader_parameter("lift", p["lift"])
	rect.material = m
	layer.add_child(rect)
	level.add_child(layer)
	return layer
