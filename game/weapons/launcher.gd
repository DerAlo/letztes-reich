class_name Launcher
extends Weapon
## Panzerfaust 3 (Slot 3): verschießt eine Rakete (Projektil) statt eines Hitscan-Schusses.
## Gegenwirkmasse nach hinten: Rückstrahl-Staub hinter dem Spieler.

@export var rocket_speed: float = 72.0

## Zieloptik (ADS): Blick durch das Okular mit Gummi-Augenmuschel. Das Viewmodel verschwindet, stattdessen
## runder Sehkreis mit weichem Muschelrand (dunkle Vignette, wandert beim Schwenken leicht mit) und Strichplatte:
## Zielmarke (Winkel + Pfosten), Vorhaltemarken fuer 10/20/30 km/h quer (aus rocket_speed berechnet, Rakete fliegt
## gerade) und Entfernungsklammern fuer ein 3,5 m breites Fahrzeug auf 100-400 m unter der Zielmarke.
const SIGHT_LAYER := 3                 # ueber dem Viewmodel (1), unter dem HUD (5) – wie das Zielfernrohr der G28
const TARGET_WIDTH_M := 3.5
const SIGHT_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(1920.0, 1080.0);
uniform vec2 offset = vec2(0.0);
uniform float radius = 470.0;
uniform float amount = 1.0;
void fragment() {
	vec2 p = UV * size - size * 0.5;
	float d = length(p);
	float ds = length(p - offset);
	// Sehkreis: weiche Kante (Auge nicht scharf auf die Muschel fokussiert), aussen schwarz
	float outside = smoothstep(radius * 0.965, radius * 1.03, ds);
	// Augenmuschel: dunkler, leicht warmer Gummi-Ring direkt am Rand, nach innen sanfte Abdunklung
	float cup = smoothstep(radius * 0.72, radius * 0.99, ds);
	float inner = smoothstep(radius * 0.25, radius, d) * 0.18;
	float a = max(outside, max(cup * cup * 0.82, inner));
	vec3 col = mix(vec3(0.035, 0.03, 0.026), vec3(0.0), outside);
	COLOR = vec4(col, clamp(a, 0.0, 1.0) * amount);
}
"""

var scoped_amount: float = 0.0
var _sight_layer: CanvasLayer = null
var _sight_mask: ColorRect = null
var _sight_mat: ShaderMaterial = null
var _sight_ret: Control = null
var _sight_off: Vector2 = Vector2.ZERO

func set_active(on: bool) -> void:
	super.set_active(on)
	if not on:
		scoped_amount = 0.0
		_show_model(true)
		if _sight_layer != null:
			_sight_layer.visible = false

func animate(delta: float, s: Dictionary) -> void:
	super.animate(delta, s)
	var ads: float = float(s.get("ads", 0.0))
	scoped_amount = smoothstep(0.8, 0.97, ads) if visible and owner_player != null else 0.0
	_show_model(scoped_amount < 0.6)
	var lr: Variant = s.get("look_rate", Vector2.ZERO)
	var look: Vector2 = lr if lr is Vector2 else Vector2.ZERO
	_sight_off = _sight_off.lerp(look.clamp(Vector2(-3, -3), Vector2(3, 3)), 1.0 - exp(-10.0 * delta))
	_update_sight()

func _show_model(on: bool) -> void:
	var m: Node3D = _pivot.get_node_or_null("Model") as Node3D if _pivot != null else null
	if m != null:
		m.visible = on
	if _arms != null:
		_arms.visible = on
	if _muzzle_fx != null:
		_muzzle_fx.visible = on

func _build_sight() -> void:
	_sight_layer = CanvasLayer.new()
	_sight_layer.name = "PzfSight"
	_sight_layer.layer = SIGHT_LAYER
	add_child(_sight_layer)
	_sight_mask = ColorRect.new()
	_sight_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sight_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SIGHT_SHADER
	_sight_mat = ShaderMaterial.new()
	_sight_mat.shader = sh
	_sight_mask.material = _sight_mat
	_sight_layer.add_child(_sight_mask)
	_sight_ret = Control.new()
	_sight_ret.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sight_ret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sight_ret.draw.connect(_draw_reticle)
	_sight_layer.add_child(_sight_ret)

func _update_sight() -> void:
	var on: bool = scoped_amount > 0.01
	if not on:
		if _sight_layer != null:
			_sight_layer.visible = false
		return
	if _sight_layer == null:
		_build_sight()
	_sight_layer.visible = true
	var size: Vector2 = _sight_mask.get_viewport_rect().size
	# Auge naehert sich der Muschel: Sehkreis waechst beim Anlegen auf volle Groesse
	var r: float = size.y * lerpf(0.3, 0.455, scoped_amount)
	_sight_mat.set_shader_parameter("size", size)
	_sight_mat.set_shader_parameter("radius", r)
	_sight_mat.set_shader_parameter("offset", Vector2(-_sight_off.x, _sight_off.y) * size.y * 0.012)
	_sight_mat.set_shader_parameter("amount", clampf(scoped_amount * 1.6, 0.0, 1.0))
	_sight_ret.modulate.a = clampf((scoped_amount - 0.35) / 0.65, 0.0, 1.0)
	_sight_ret.queue_redraw()

## Strichplatte in Strich (mil) ueber das echte Kamera-FOV -> passt bei jeder Aufloesung und Zoomstufe.
func _draw_reticle() -> void:
	if owner_player == null:
		return
	var size: Vector2 = _sight_ret.get_viewport_rect().size
	var c: Vector2 = size * 0.5
	var r: float = size.y * 0.455
	var fov: float = maxf(owner_player.camera.fov, 1.0)
	var ppm: float = (size.y * 0.5) / tan(deg_to_rad(fov * 0.5)) * 0.001   # Pixel je Strich
	var ink := Color(0.03, 0.03, 0.025, 0.92)
	var thin: float = maxf(1.0, size.y / 900.0)
	var thick: float = maxf(2.0, size.y / 340.0)
	var fs: int = int(maxf(9.0, size.y / 72.0))
	var font: Font = ThemeDB.fallback_font
	# Zielmarke: Querbalken links/rechts mit Luecke, Pfosten von unten bis knapp unter die Mitte, Mittelpunkt
	var gap: float = 9.0 * ppm
	draw_reticle_line(c + Vector2(-r * 0.92, 0), c + Vector2(-r * 0.55, 0), ink, thick)
	draw_reticle_line(c + Vector2(r * 0.55, 0), c + Vector2(r * 0.92, 0), ink, thick)
	draw_reticle_line(c + Vector2(-r * 0.55, 0), c + Vector2(-gap, 0), ink, thin)
	draw_reticle_line(c + Vector2(gap, 0), c + Vector2(r * 0.55, 0), ink, thin)
	draw_reticle_line(c + Vector2(0, r * 0.92), c + Vector2(0, r * 0.62), ink, thick)
	draw_reticle_line(c + Vector2(0, -r * 0.6), c + Vector2(0, -gap * 2.0), ink, thin)
	# Winkel (Chevron) als Haltepunkt
	var ch: float = 4.5 * ppm
	draw_reticle_line(c + Vector2(-ch, ch), c, ink, thin * 1.4)
	draw_reticle_line(c, c + Vector2(ch, ch), ink, thin * 1.4)
	# Vorhaltemarken: Ziel faehrt quer mit v km/h -> Vorhalt = atan(v / rocket_speed)
	for kmh in [10, 20, 30]:
		var x: float = atan((float(kmh) / 3.6) / maxf(rocket_speed, 1.0)) * 1000.0 * ppm
		if x > r * 0.53:
			break
		var hl: float = (5.0 if kmh == 20 else 3.0) * ppm
		for sx: float in [-1.0, 1.0]:
			draw_reticle_line(c + Vector2(sx * x, -hl), c + Vector2(sx * x, hl), ink, thin)
		var t := str(kmh)
		var tw: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_sight_ret.draw_string(font, c + Vector2(x - tw * 0.5, -hl - 3.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
	# Entfernungsklammern: Breite = 3,5 m Fahrzeug auf 100/200/300/400 m, gestaffelt unter der Zielmarke
	var y: float = 16.0 * ppm
	for d in [400, 300, 200, 100]:
		var half: float = TARGET_WIDTH_M / float(d) * 1000.0 * 0.5 * ppm
		if half > r * 0.5:
			continue
		var bh: float = maxf(4.0, 3.0 * ppm)
		var a := c + Vector2(-half, y)
		var b := c + Vector2(half, y)
		draw_reticle_line(a, a + Vector2(0, -bh), ink, thin)
		draw_reticle_line(b, b + Vector2(0, -bh), ink, thin)
		draw_reticle_line(a, a + Vector2(minf(half * 0.35, 6.0 * ppm), 0), ink, thin)
		draw_reticle_line(b, b - Vector2(minf(half * 0.35, 6.0 * ppm), 0), ink, thin)
		_sight_ret.draw_string(font, b + Vector2(4.0, 0.0 + fs * 0.35), str(d / 100), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		y += maxf(9.0 * ppm, fs * 1.3)

func draw_reticle_line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	_sight_ret.draw_line(a, b, col, w, true)

func _shoot(cam: Camera3D, spread_deg: float) -> void:
	var b: Basis = cam.global_basis
	var dir: Vector3 = -b.z
	if spread_deg > 0.0:
		var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a: float = randf() * TAU
		dir = (dir + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	# Start knapp vor der Kamera; Ziel exakt auf der Kameraachse halten
	var from: Vector3 = cam.global_position + dir * 0.9 + b.x * 0.08 - b.y * 0.04
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	# Wand direkt vor der Nase: an der Kamera starten, damit die Rakete nicht hindurchtunnelt
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, from, 1 | 4, exclude)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = cam.global_position + dir * 0.1
	Rocket.launch(_world_root(), from, dir, rocket_speed, owner_player)
	_backblast(cam)

func _backblast(cam: Camera3D) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 25.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.damping_min = 4.0
	pm.damping_max = 7.0
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.8
	pm.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.5, 0.8))
	ramp.add_point(0.1, Color(0.7, 0.68, 0.62, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.58, 0.55, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 0.8)
	qm.material = mat
	p.draw_pass_1 = qm
	p.amount = 40
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(p)
	p.global_transform = Transform3D(cam.global_basis, cam.global_position + cam.global_basis.z * 0.9 + cam.global_basis.x * 0.15)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
