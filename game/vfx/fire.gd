extends Node3D
## Dauerhaftes Feuer: Flammen, Glut, Rauchsaeule und flackerndes Licht. Skalierbar ueber `size`.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

@export var size: float = 1.0
@export var smoke_enabled: bool = true
@export var embers_enabled: bool = true
@export var light_enabled: bool = true
@export var light_energy: float = 6.0
@export var light_range: float = 12.0
@export var light_color: Color = Color(1.0, 0.5, 0.18)
@export var smoke_height: float = 1.0      ## Multiplikator fuer die Steiggeschwindigkeit des Rauchs
@export var smoke_amount: int = 40          ## Basis; wird mit smoke_height hochskaliert
@export var flame_amount: int = 16
## Deckkraft der Rauchpartikel (Shader-Dichte). Weniger, dafuer dichtere Partikel = weniger Overdraw.
@export var smoke_density: float = 1.6
## false: Rauch empfaengt keine Schatten (smoke_billboard_fast, ~15 % guenstiger pro Pixel) –
## fuer Nacht-/Nahfeuer, wo Schatten auf dem Rauch ohnehin nicht zu sehen sind.
@export var smoke_shadows: bool = true
## > 0: Feuer erlischt nach dieser Zeit (Flammen/Licht blenden aus, Rauch glimmt kurz nach)
@export var burn_time: float = 0.0

var _flames: GPUParticles3D
var _smoke: GPUParticles3D
var _smoke_mat: ShaderMaterial
var _fog_mat: FogMaterial
var _embers: GPUParticles3D
var _light: OmniLight3D
var _noise := FastNoiseLite.new()
var _t: float = randf() * 100.0
var _intensity: float = 1.0
var _dying: bool = false
var _crackle: AudioStreamPlayer3D

func _ready() -> void:
	add_to_group("vfx_fire")
	_noise.frequency = 1.0
	_noise.seed = randi()
	_build()
	_build_crackle()
	if burn_time > 0.0:
		get_tree().create_timer(burn_time).timeout.connect(extinguish)

func _build() -> void:
	var quad := VfxLib.quad(1.0)
	var s := size
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35 * s
	pm.direction = Vector3.UP
	pm.spread = 14.0
	pm.initial_velocity_min = 0.8 * s
	pm.initial_velocity_max = 2.0 * s
	pm.gravity = Vector3(0, 1.0 * s, 0)
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -25.0
	pm.angular_velocity_max = 25.0
	pm.scale_min = 0.9 * s
	pm.scale_max = 1.5 * s
	pm.scale_curve = VfxLib.curve_tex([[0.0, 0.7], [0.25, 1.0], [1.0, 0.25]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.0)], [0.12, Color(1, 1, 1, 1)], [0.7, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0.0)]])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 1.6
	_flames = VfxLib.make_particles(flame_amount, 1.0, pm, quad, VfxLib.fire_mat({"intensity": 1.8, "tex_scale": 0.6, "rise": 1.2, "core_heat": 1.5}))
	_flames.one_shot = false
	_flames.explosiveness = 0.0
	_flames.randomness = 0.3
	_flames.emitting = flame_amount > 0   # 0 = nur Rauch (z. B. Heli-Schadensstufe 1)
	_flames.visible = flame_amount > 0
	_flames.visibility_aabb = AABB(Vector3(-6, -1, -6) * s, Vector3(12, 14, 12) * s)
	add_child(_flames)

	if smoke_enabled:
		_smoke = _build_smoke(s)
		add_child(_smoke)
		_smoke_mat.set_shader_parameter("glow_origin_y", global_position.y + 0.2 * s)
		if smoke_height >= 2.5:
			_build_smoke_fog(s)

	if embers_enabled:
		var ep := ParticleProcessMaterial.new()
		ep.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		ep.emission_sphere_radius = 0.3 * s
		ep.direction = Vector3.UP
		ep.spread = 35.0
		ep.initial_velocity_min = 1.0 * s
		ep.initial_velocity_max = 3.2 * s
		ep.gravity = Vector3(0.4, 0.3, 0.0)
		ep.scale_min = 0.5
		ep.scale_max = 1.0
		ep.turbulence_enabled = true
		ep.turbulence_noise_strength = 1.5
		ep.turbulence_noise_scale = 1.2
		ep.color_ramp = VfxLib.ramp([[0.0, Color(1.0, 0.7, 0.3, 1)], [0.5, Color(1.0, 0.35, 0.06, 0.9)], [1.0, Color(0.5, 0.08, 0.0, 0.0)]])
		var em := BoxMesh.new()
		em.size = Vector3(0.025, 0.025, 0.025)
		_embers = VfxLib.make_particles(8, 2.4, ep, em, VfxLib.shader_mat("spark", {"intensity": 4.0}))
		_embers.one_shot = false
		_embers.explosiveness = 0.0
		_embers.randomness = 0.5
		_embers.emitting = true
		_embers.visibility_aabb = AABB(Vector3(-8, -1, -8) * s, Vector3(16, 18, 16) * s)
		add_child(_embers)

	if light_enabled:
		_light = OmniLight3D.new()
		_light.light_color = light_color
		_light.omni_range = light_range * s
		_light.omni_attenuation = 1.6
		_light.light_energy = light_energy
		_light.light_volumetric_fog_energy = 1.0
		_light.shadow_enabled = false
		_light.position = Vector3(0, 0.8 * s, 0)
		add_child(_light)

## Rauchsaeule: viele, transparente, weiche Partikel, die mit der Zeit wachsen, aufhellen und
## mit dem Wind driften. Unten von der Glut angestrahlt (glow_height).
func _build_smoke(s: float) -> GPUParticles3D:
	var h := smoke_height
	var big := clampf(0.4 + 0.75 * h, 1.0, 3.0)          # hohe Saeulen: mehr Partikel, laenger
	var life := 6.5 * (0.75 + 0.3 * h)
	var sp := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 9.0)
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 0.35 * s
	sp.direction = Vector3.UP
	sp.spread = 12.0
	sp.initial_velocity_min = 1.3 * s * sqrt(h)
	sp.initial_velocity_max = 2.4 * s * sqrt(h)
	# Auftrieb + Wind (seitliche Drift waechst mit der Hoehe)
	sp.gravity = Vector3(0, 0.18 * s, 0) + VfxLib.WIND * (0.35 + 0.12 * h) * sqrt(s)
	sp.damping_min = 0.05
	sp.damping_max = 0.15
	sp.scale_min = 2.0 * s
	sp.scale_max = 3.3 * s
	sp.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.4], [0.2, 0.8], [1.0, 1.6 + 0.45 * h]])
	sp.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.16, 0.6)
	sp.turbulence_enabled = true
	sp.turbulence_noise_strength = 0.35
	sp.turbulence_noise_scale = 2.4 * s
	sp.turbulence_noise_speed = Vector3(0.0, 0.25, 0.0)
	sp.turbulence_influence_min = 0.03
	sp.turbulence_influence_max = 0.08
	_smoke_mat = VfxLib.smoke_mat({
		"smoke_color": Color(0.045, 0.042, 0.04),
		"smoke_color_end": Color(0.15, 0.147, 0.144),
		"color_shift": 1.4,
		"density": smoke_density,
		"erosion": 0.2,
		"frame_span": 7.0,
		"soft_dist": 0.8 * s,
		"glow": 0.45,
		"glow_height": 0.6 * s,
		"glow_color": Color(1.0, 0.4, 0.12),
	}, not smoke_shadows)
	# fx2: viele, sehr transparente Partikel (Alpha ~0.05-0.25), die sich weich ueberlagern
	var p := VfxLib.make_particles(int(smoke_amount * big * 2.4), life, sp, VfxLib.quad(1.0), _smoke_mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.25
	p.emitting = true
	p.preprocess = life
	p.position = Vector3(0, 0.25 * s, 0)
	p.visibility_aabb = AABB(Vector3(-20, -2, -20) * s, Vector3(40, 30 * h, 40) * s)
	p.name = "Smoke"
	return p

func _process(delta: float) -> void:
	if _light == null:
		return
	_t += delta
	var n := _noise.get_noise_2d(_t * 6.0, 0.0) * 0.5 + 0.5
	var n2 := _noise.get_noise_2d(_t * 17.0, 7.0) * 0.5 + 0.5
	_light.light_energy = light_energy * _intensity * (0.55 + n * 0.55 + n2 * 0.25)
	_light.position = Vector3(sin(_t * 3.1) * 0.12, 0.8 * size + n2 * 0.15, cos(_t * 2.3) * 0.12) * 1.0

## Knister-Loop (3D, Bus SFX). Zufaelliger Startpunkt, damit mehrere Feuer nicht synchron knistern.
func _build_crackle() -> void:
	var st := load("res://assets/sfx/fire_crackle.ogg") as AudioStreamOggVorbis if ResourceLoader.exists("res://assets/sfx/fire_crackle.ogg") else null
	if st == null:
		return
	st.loop = true
	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = st
	_crackle.bus = &"SFX"
	_crackle.unit_size = 2.5 + size * 2.0
	_crackle.max_distance = 18.0 + size * 14.0
	_crackle.volume_db = linear_to_db(clampf(0.45 + size * 0.3, 0.3, 1.4))
	_crackle.pitch_scale = clampf(1.15 - size * 0.12, 0.8, 1.1) * randf_range(0.95, 1.05)
	_crackle.position = Vector3(0, 0.6 * size, 0)
	_crackle.autoplay = false
	add_child(_crackle)
	_crackle.play(randf() * 18.0)

func _exit_tree() -> void:
	if _crackle:
		_crackle.stop()
		_crackle.stream = null

## Feuer langsam loeschen: Flammen und Licht blenden aus, Rauch laeuft aus.
## Hohe Rauchsaeulen: zusaetzlich ein weiches, dunkles Fog-Volumen um den unteren/mittleren Teil der
## Saeule (fuellt die Luecken zwischen den Partikeln mit volumetrischem Dunst; wirkt nur in Leveln mit
## volumetrischem Nebel, sonst ohne Kosten). Leicht in Windrichtung versetzt.
func _build_smoke_fog(s: float) -> void:
	var h := smoke_height
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3(3.2 * s, 2.6 * h * s, 3.2 * s)
	_fog_mat = FogMaterial.new()
	_fog_mat.density = 0.35
	_fog_mat.albedo = Color(0.12, 0.115, 0.11)
	_fog_mat.height_falloff = 0.15
	_fog_mat.edge_fade = 0.9
	fv.material = _fog_mat
	var wd := Vector3(VfxLib.WIND.x, 0.0, VfxLib.WIND.z)
	fv.position = Vector3(0, 1.3 * h * s, 0) + wd * (0.25 * h * s)
	fv.name = "SmokeFog"
	add_child(fv)

func extinguish(fade_time: float = 6.0) -> void:
	if _dying:
		return
	_dying = true
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_intensity", 0.0, fade_time)
	if _smoke_mat:
		tw.tween_property(_smoke_mat, "shader_parameter/glow", 0.0, fade_time * 0.6)
	if _fog_mat:
		tw.tween_property(_fog_mat, "density", 0.0, fade_time * 1.5)
	if _crackle:
		tw.tween_property(_crackle, "volume_db", -60.0, fade_time)
	tw.tween_callback(func() -> void:
		if _flames: _flames.emitting = false
		if _embers: _embers.emitting = false).set_delay(fade_time * 0.5)
	tw.tween_callback(func() -> void:
		if _smoke: _smoke.emitting = false).set_delay(fade_time)
	tw.chain().tween_interval(8.0)
	tw.chain().tween_callback(queue_free)
