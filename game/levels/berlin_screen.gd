extends StaticBody3D
## Propaganda-Bildschirm der (fiktiven) Ordnungsfront: flackert auf, zeigt Emblem + hohle Parolen,
## wirft Amber-Licht auf die Strasse. Kann zerschossen werden (Funken, Glas, Bild stirbt).

const EMBLEM := "res://assets/environment/berlin/emblem.png"

signal destroyed

@export var size: Vector2 = Vector2(9.0, 5.0)
@export var max_health: float = 45.0
@export var slogans: Array[String] = ["ORDNUNG.", "STÄRKE.", "DAS LETZTE REICH."]
@export var light_energy: float = 5.0

var health: float
var _alive: bool = true
var _on: bool = false
var _mat: ShaderMaterial
var _label: Label3D
var _light: OmniLight3D
var _buzz: AudioStreamPlayer3D
var _slogan_i: int = 0
var _t: float = 0.0

static var _shader: Shader

func _ready() -> void:
	health = max_health
	add_to_group("damageable")
	collision_layer = 1
	collision_mask = 0
	_build()
	set_process(false)

func _build() -> void:
	# Rahmen
	var frame := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x + 0.5, size.y + 0.5, 0.45)
	frame.mesh = bm
	frame.material_override = preload("res://game/levels/level_geo.gd").flat(Color(0.06, 0.06, 0.065), 0.5, 0.6)
	frame.position = Vector3(0, 0, -0.25)
	add_child(frame)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x + 0.5, size.y + 0.5, 0.5)
	cs.shape = bs
	cs.position = Vector3(0, 0, -0.2)
	add_child(cs)
	# Bildflaeche
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	if ResourceLoader.exists(EMBLEM):
		_mat.set_shader_parameter("emblem", load(EMBLEM))
	_mat.set_shader_parameter("aspect", size.x / size.y)
	_mat.set_shader_parameter("power", 0.0)
	var q := QuadMesh.new()
	q.size = size
	var scr := MeshInstance3D.new()
	scr.mesh = q
	scr.material_override = _mat
	scr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(scr)
	# Parole (rechts neben dem Emblem)
	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 128
	_label.outline_size = 0
	_label.pixel_size = size.y * 0.0011
	_label.modulate = Color(2.4, 1.45, 0.4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.width = (size.x * 0.56) / _label.pixel_size
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label.position = Vector3(size.x * 0.19, 0, 0.03)
	_label.shaded = false
	_label.double_sided = false
	_label.visible = false
	add_child(_label)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.6, 0.2)
	_light.light_energy = 0.0
	_light.omni_range = maxf(size.x * 2.6, 16.0)
	_light.omni_attenuation = 1.3
	_light.light_volumetric_fog_energy = 1.2
	_light.position = Vector3(0, 0, 2.5)
	add_child(_light)

## Schaltet den Bildschirm mit Flackern ein.
func power_on(delay: float = 0.0) -> void:
	if not _alive or _on:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	if not _alive:
		return
	_on = true
	if ResourceLoader.exists("res://assets/sfx/berlin_screen_buzz.ogg"):
		var st: AudioStreamOggVorbis = load("res://assets/sfx/berlin_screen_buzz.ogg")
		st.loop = true
		_buzz = AudioStreamPlayer3D.new()
		_buzz.stream = st
		_buzz.bus = "SFX"
		_buzz.volume_db = -14.0
		_buzz.unit_size = 4.0
		_buzz.max_distance = 35.0
		add_child(_buzz)
		_buzz.play()
	var tw := create_tween()
	for k: float in [0.6, 0.0, 0.9, 0.1, 0.0, 1.0, 0.4, 1.0]:
		tw.tween_callback(_set_power.bind(k))
		tw.tween_interval(randf_range(0.05, 0.16))
	tw.tween_callback(func() -> void:
		_label.visible = true
		_label.text = slogans[0]
		set_process(true))

func _set_power(k: float) -> void:
	if not _alive:
		return
	_mat.set_shader_parameter("power", k)
	_light.light_energy = light_energy * k

func _process(delta: float) -> void:
	_t += delta
	if _t >= 2.4:
		_t = 0.0
		_slogan_i = (_slogan_i + 1) % slogans.size()
		_label.text = slogans[_slogan_i]
		_mat.set_shader_parameter("glitch", 1.0)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void: _mat.set_shader_parameter("glitch", v), 1.0, 0.0, 0.35)
	_light.light_energy = light_energy * (0.88 + 0.12 * sin(_t * 31.0) * sin(_t * 7.0))

func is_alive() -> bool:
	return _alive

func take_damage(amount: float, _source: Node = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
	if not _alive:
		return
	health -= amount
	if hit_position != Vector3.ZERO:
		VFX.spawn_impact(hit_position, hit_normal, "metal")
	if _on:
		_mat.set_shader_parameter("glitch", 1.0)
	if health <= 0.0:
		_break()

func _break() -> void:
	_alive = false
	set_process(false)
	_label.visible = false
	_mat.set_shader_parameter("power", 0.0)
	_mat.set_shader_parameter("broken", 1.0)
	if _buzz != null:
		_buzz.stop()
	VFX.play_sfx_3d("berlin_glass", global_position, 2.0, 12.0, 90.0)
	var b := global_transform.basis
	for i in 7:
		var p := global_position + b * Vector3(randf_range(-0.45, 0.45) * size.x, randf_range(-0.45, 0.45) * size.y, 0.1)
		VFX.spawn_impact(p, b.z, "metal")
	# Kurzer Funkenblitz, dann dunkel
	var tw := create_tween()
	tw.tween_property(_light, "light_color", Color(0.7, 0.85, 1.0), 0.01)
	tw.tween_property(_light, "light_energy", light_energy * 2.0, 0.04)
	tw.tween_property(_light, "light_energy", 0.0, 0.5)
	destroyed.emit()

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D emblem : source_color, filter_linear_mipmap, repeat_disable;
uniform float power = 0.0;
uniform float broken = 0.0;
uniform float glitch = 0.0;
uniform float aspect = 1.8;
uniform vec3 tint : source_color = vec3(1.0, 0.6, 0.14);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float band = step(0.975 - glitch * 0.25, hash(vec2(floor(uv.y * 38.0), floor(t * 14.0))));
	uv.x += band * (hash(vec2(floor(t * 20.0), floor(uv.y * 38.0))) - 0.5) * (0.04 + glitch * 0.12);
	// Hintergrund: dunkler Verlauf mit Raster und Scanlines
	vec3 bg = mix(vec3(0.05, 0.03, 0.015), vec3(0.16, 0.07, 0.02), smoothstep(1.0, 0.0, distance(uv, vec2(0.3, 0.5))));
	float scan = 0.82 + 0.18 * sin(uv.y * 520.0 + t * 6.0);
	vec2 px = fract(uv * vec2(aspect * 110.0, 110.0));
	float grid = smoothstep(0.0, 0.18, px.x) * smoothstep(0.0, 0.18, px.y);
	// Emblem im linken Quadrat
	float sq = 0.86 / aspect;
	vec2 euv = vec2((uv.x - 0.04) / sq, (uv.y - 0.07) / 0.86);
	vec4 e = vec4(0.0);
	if (euv.x >= 0.0 && euv.x <= 1.0 && euv.y >= 0.0 && euv.y <= 1.0) {
		e = texture(emblem, euv);
	}
	// Trennbalken
	float bar = step(abs(uv.x - (0.06 + sq)), 0.004) * step(0.15, uv.y) * step(uv.y, 0.85);
	vec3 col = bg + tint * 2.4 * e.a + tint * 1.6 * bar;
	float flick = 0.9 + 0.1 * hash(vec2(floor(t * 24.0), 3.0));
	col *= scan * mix(0.7, 1.0, grid) * flick;
	col += vec3(band * glitch * 0.6);
	col *= power;
	// zerschossen: totes Bild mit Rissen und vereinzelten Pixelstreifen
	if (broken > 0.5) {
		vec2 c = uv - vec2(0.55, 0.45);
		float ang = atan(c.y, c.x);
		float crack = step(0.93, fract(ang * 2.2 + hash(vec2(floor(ang * 9.0), 1.0)))) * step(length(c), 0.6);
		float dead = step(0.992, hash(vec2(floor(uv.x * 160.0), 7.0)));
		col = vec3(0.012) + vec3(0.12) * crack + tint * dead * 0.8 * step(0.5, hash(vec2(floor(t * 8.0), uv.x)));
	}
	ALBEDO = col;
}
"""
