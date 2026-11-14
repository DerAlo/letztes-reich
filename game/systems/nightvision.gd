extends Node
## Nachtsichtgeraet und Taschenlampe als wiederverwendbares System (Opt-in pro Level).
## Ein Level, das es will, erzeugt es selbst:
##     var nv := preload("res://game/systems/nightvision.gd").new()
##     nv.battery_enabled = true
##     add_child(nv)
## Ohne diesen Knoten passiert in keinem Level etwas (Tasten N/L sind dann wirkungslos).
##
## - N (Aktion "nightvision"): Restlichtverstaerker. Gruenes Bild mit Korn und Vignette, Einblenden,
##   IR-Aufheller an der Kamera, Umgebungslicht angehoben. Lampen, die ins Objektiv leuchten
##   (SpotLight3D mit Meta "stealth_light", z. B. Gardisten-Taschenlampen), blenden aus.
## - L (Aktion "flashlight"): Taschenlampe. Hell, aber sichtbar: `flashlight_on` lesen Level/Direktor,
##   um den Spieler als beleuchtet zu werten.
## - Optionale Batterie (`battery_enabled`): leert sich bei Nachtsicht, laedt im Aus-Zustand nach.
## Beides schliesst sich gegenseitig aus. Pause: der Knoten pausiert mit dem Baum (keine Eingaben).

signal toggled(kind: String, on: bool)

const SHADER := preload("res://game/systems/nightvision.gdshader")

@export var battery_enabled: bool = true
@export var battery_seconds: float = 150.0       ## volle Batterie in Sekunden Nachtsicht
@export var recharge_seconds: float = 45.0       ## Leer -> voll im Aus-Zustand
@export var allow_flashlight: bool = true
@export var ambient_boost: float = 0.16          ## zusaetzliches Umgebungslicht bei Nachtsicht (Rest regelt die Roehre)
@export var ir_range: float = 16.0
@export var ir_energy: float = 0.6
@export var fade_time: float = 0.45
## Unter Nachtsicht: Szenen-Glow (Bloom) auf diesen Anteil daempfen, Glow-Schwelle anheben.
## Die Roehre zeichnet Lichtquellen nur mit kleinem Halo (Bright Source Protection).
@export var nv_glow_scale: float = 0.15
@export var nv_glow_threshold: float = 1.6
## Lichtkegel fremder Lampen im Nebel unter Nachtsicht abschwaechen (sonst fuellt der Streukegel das Bild).
@export var nv_lamp_fog_scale: float = 0.3
## Volumetrischen Nebel unter Nachtsicht ausduennen: die Roehre verstaerkt den Streuschleier sonst
## zu einer flachen gruenen Wand, in der Gegner verschwinden.
@export var nv_fog_scale: float = 0.5

var nv_on: bool = false
var flashlight_on: bool = false
var battery: float = 1.0
var glare: float = 0.0

var _fade: float = 0.0
var _power_on: float = 0.0
var _player: Node3D
var _cam: Camera3D
var _env: Environment
var _env_base: Dictionary = {}
var _layer: CanvasLayer
var _mat: ShaderMaterial
var _ir: OmniLight3D
var _torch: SpotLight3D
var _hud: CanvasLayer
var _bar: ProgressBar
var _hud_label: Label
var _hint: Label
var _lamps: Array[SpotLight3D] = []
var _lamp_t: float = 0.0
var _snd: AudioStreamPlayer
var _hint_t: float = 6.0

func _ready() -> void:
	name = "NightVision"
	InputConfig.ensure_actions()
	_build_overlay()
	_build_hud()
	_snd = AudioStreamPlayer.new()
	_snd.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(_snd)

func _exit_tree() -> void:
	_restore_env()

# ------------------------------------------------------------------ Oeffentlich

func set_nightvision(on: bool) -> void:
	if on == nv_on:
		return
	if on and battery_enabled and battery < 0.03:
		_beep("dry_fire", -8.0)
		return
	nv_on = on
	if on:
		if flashlight_on:
			set_flashlight(false)
		_power_on = 1.0
		_capture_env()
	_beep("gunship_switch", -10.0 if on else -14.0)
	toggled.emit("nightvision", on)

func set_flashlight(on: bool) -> void:
	if on == flashlight_on or (on and not allow_flashlight):
		return
	flashlight_on = on
	if on and nv_on:
		set_nightvision(false)
	_ensure_rig()
	if _torch != null:
		_torch.visible = on
	_beep("pistol_slide", -16.0)
	toggled.emit("flashlight", on)

func toggle_nightvision() -> void:
	set_nightvision(not nv_on)

func toggle_flashlight() -> void:
	set_flashlight(not flashlight_on)

## Beim Respawn/Neustart: alles aus, Batterie voll.
func reset() -> void:
	set_flashlight(false)
	set_nightvision(false)
	battery = 1.0

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if InputMap.has_action("nightvision") and event.is_action_pressed("nightvision"):
		toggle_nightvision()
		get_viewport().set_input_as_handled()
	elif InputMap.has_action("flashlight") and event.is_action_pressed("flashlight"):
		toggle_flashlight()
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ Ablauf

func _process(delta: float) -> void:
	_ensure_rig()
	var rd := delta / maxf(Engine.time_scale, 0.05)   # Bildeffekte in Echtzeit (Zeitlupe)
	if _player != null and _player.has_method("is_alive") and not bool(_player.call("is_alive")):
		if flashlight_on:
			set_flashlight(false)
	# Batterie
	if battery_enabled:
		if nv_on:
			battery = maxf(0.0, battery - delta / maxf(battery_seconds, 1.0))
			if battery <= 0.0:
				set_nightvision(false)
		else:
			battery = minf(1.0, battery + delta / maxf(recharge_seconds, 1.0))
	# Einblenden
	var target := 1.0 if nv_on else 0.0
	_fade = move_toward(_fade, target, rd / maxf(fade_time, 0.05))
	_power_on = move_toward(_power_on, 0.0, rd * 3.5)
	_update_glare(delta)
	_apply_env()
	if _ir != null:
		_ir.visible = _fade > 0.02
		_ir.light_energy = ir_energy * _fade
	if _mat != null:
		_layer.visible = _fade > 0.001
		var e := _fade * _fade * (3.0 - 2.0 * _fade)
		_mat.set_shader_parameter("fade", e)
		_mat.set_shader_parameter("glare", glare)
		_mat.set_shader_parameter("power_on", _power_on * 0.6 * e)
		var low := 0.0
		if battery_enabled and battery < 0.15:
			low = (0.15 - battery) / 0.15 * 0.6
		_mat.set_shader_parameter("flicker", low)
	_update_hud(rd)

func _ensure_rig() -> void:
	if _player != null and is_instance_valid(_player) and _cam != null and is_instance_valid(_cam):
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player == null or not _player.has_method("get_camera"):
		return
	_cam = _player.call("get_camera") as Camera3D
	if _cam == null:
		return
	_ir = OmniLight3D.new()
	_ir.name = "NVIlluminator"
	_ir.light_color = Color(0.85, 0.9, 0.85)
	_ir.omni_range = ir_range
	_ir.omni_attenuation = 1.2
	_ir.light_energy = 0.0
	_ir.light_specular = 0.1
	_ir.shadow_enabled = false
	_ir.light_volumetric_fog_energy = 0.0
	_ir.visible = false
	_ir.set_meta("no_stealth", true)
	_ir.position = Vector3(0.0, 0.1, 0.0)
	_cam.add_child(_ir)
	_torch = SpotLight3D.new()
	_torch.name = "Flashlight"
	_torch.light_color = Color(1.0, 0.95, 0.85)
	_torch.light_energy = 3.2
	_torch.spot_range = 26.0
	_torch.spot_angle = 24.0
	_torch.spot_angle_attenuation = 1.4
	_torch.spot_attenuation = 0.8
	_torch.shadow_enabled = true
	_torch.light_volumetric_fog_energy = 1.2
	_torch.set_meta("no_stealth", true)        ## Sichtbarkeit wertet der Direktor ueber flashlight_on
	_torch.position = Vector3(0.18, -0.12, 0.0)
	_torch.visible = flashlight_on
	_cam.add_child(_torch)

# ------------------------------------------------------------------ Umgebung

func _capture_env() -> void:
	if _env != null:
		return
	var lv := get_parent()
	var we: WorldEnvironment = null
	if lv != null:
		we = lv.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we == null:
		var found := get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if not found.is_empty():
			we = found[0] as WorldEnvironment
	if we == null or we.environment == null:
		return
	_env = we.environment
	_env_base = {
		"ambient_light_energy": _env.ambient_light_energy,
		"ambient_light_color": _env.ambient_light_color,
		"ambient_light_source": _env.ambient_light_source,
		"ambient_light_sky_contribution": _env.ambient_light_sky_contribution,
		"glow_intensity": _env.glow_intensity,
		"glow_bloom": _env.glow_bloom,
		"glow_hdr_threshold": _env.glow_hdr_threshold,
		"volumetric_fog_density": _env.volumetric_fog_density,
	}

func _apply_env() -> void:
	if _env == null or _env_base.is_empty():
		return
	var f := _fade
	if f <= 0.001:
		_restore_env()
		return
	var base_e: float = _env_base["ambient_light_energy"]
	var base_c: Color = _env_base["ambient_light_color"]
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_sky_contribution = 0.0
	_env.ambient_light_color = base_c.lerp(Color(0.7, 0.72, 0.7), f)
	_env.ambient_light_energy = base_e + ambient_boost * f
	_env.glow_intensity = lerpf(float(_env_base["glow_intensity"]), float(_env_base["glow_intensity"]) * nv_glow_scale, f)
	_env.glow_bloom = lerpf(float(_env_base["glow_bloom"]), 0.0, f)
	var th0: float = _env_base["glow_hdr_threshold"]
	_env.glow_hdr_threshold = lerpf(th0, maxf(th0, nv_glow_threshold), f)
	var vd0: float = _env_base["volumetric_fog_density"]
	_env.volumetric_fog_density = lerpf(vd0, vd0 * nv_fog_scale, f)

func _restore_env() -> void:
	if _env == null or _env_base.is_empty():
		return
	for k: String in _env_base:
		_env.set(k, _env_base[k])
	_env = null
	_env_base.clear()

# ------------------------------------------------------------------ Blendung

func _update_glare(delta: float) -> void:
	_lamp_t -= delta
	if _lamp_t <= 0.0:
		_lamp_t = 1.0
		_lamps.clear()
		var root := get_parent() if get_parent() != null else get_tree().current_scene
		for n in root.find_children("*", "SpotLight3D", true, false):
			if n.has_meta("stealth_light") or n.has_meta("nv_glare"):
				_lamps.append(n as SpotLight3D)
	# Streukegel fremder Lampen im Nebel: unter Nachtsicht schwaecher (Roehre regelt helle Flaechen ab)
	for l in _lamps:
		if not is_instance_valid(l):
			continue
		if not l.has_meta("_nv_fog0"):
			l.set_meta("_nv_fog0", l.light_volumetric_fog_energy)
		l.light_volumetric_fog_energy = float(l.get_meta("_nv_fog0")) * lerpf(1.0, nv_lamp_fog_scale, _fade)
	var target := 0.0
	if _cam != null and _fade > 0.01:
		var eye := _cam.global_position
		var look := -_cam.global_transform.basis.z
		var space := _cam.get_world_3d().direct_space_state
		for l in _lamps:
			if not is_instance_valid(l) or not l.is_visible_in_tree() or l.light_energy < 0.1:
				continue
			var lp := l.global_position
			var to_eye := eye - lp
			var d := to_eye.length()
			if d < 0.05 or d > l.spot_range * 1.2:
				continue
			var fwd := -l.global_transform.basis.z
			var cang := fwd.dot(to_eye / d)
			var edge := cos(deg_to_rad(minf(l.spot_angle * 1.25, 80.0)))
			if cang < edge:
				continue
			# Nur wenn der Spieler ungefaehr in die Lampe schaut
			var view := look.dot(-to_eye / d)
			if view < 0.35:
				continue
			var q := PhysicsRayQueryParameters3D.create(lp, eye, 1)
			if not space.intersect_ray(q).is_empty():
				continue
			var k := clampf((cang - edge) / maxf(0.0001, 1.0 - edge) * 2.0, 0.0, 1.0)
			var dist_k := 1.0 - d / (l.spot_range * 1.2)
			target += k * dist_k * clampf((view - 0.35) / 0.5, 0.0, 1.0) * 1.4
	target = clampf(target, 0.0, 1.0)
	# schnell rein, langsam raus (Roehre erholt sich)
	var rate := 6.0 if target > glare else 1.2
	glare = move_toward(glare, target, delta * rate)

# ------------------------------------------------------------------ Darstellung

func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "NightVisionFx"
	_layer.layer = 3   # ueber PostFx (2), unter dem HUD (5)
	_layer.visible = false
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	rect.material = _mat
	_layer.add_child(rect)
	add_child(_layer)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.name = "NightVisionHud"
	_hud.layer = 6
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -250.0
	box.offset_right = -36.0
	box.offset_top = -300.0   # ueber der Waffenanzeige des Spieler-HUDs (unten rechts)
	box.offset_bottom = -250.0
	box.add_theme_constant_override("separation", 3)
	_hud_label = Label.new()
	_hud_label.text = "NSG"
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud_label.add_theme_font_size_override("font_size", 15)
	_hud_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.65, 0.85))
	_hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud_label.add_theme_constant_override("outline_size", 4)
	box.add_child(_hud_label)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.custom_minimum_size = Vector2(214, 6)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.45, 1.0, 0.5, 0.85)
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)
	box.add_child(_bar)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.85, 0.88, 0.85, 0.7))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 4)
	box.add_child(_hint)
	# in 1080p-Pixeln unter skalierter Wurzel (ueber der Munitionsanzeige von hud.gd, kleine Fenster z. B. 960x540)
	var root := UIStyle.HudRoot.new()
	_hud.add_child(root)
	root.add_child(box)
	root.keep_min_font(_hud_label, 15)
	root.keep_min_font(_hint, 13)
	add_child(_hud)

func _key_name(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var code := k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
			return OS.get_keycode_string(code)
	return "?"

func _update_hud(rd: float) -> void:
	if _hud == null:
		return
	_hint_t = maxf(0.0, _hint_t - rd)
	_bar.visible = battery_enabled
	_bar.value = battery
	var state := "AN" if nv_on else ("LAMPE" if flashlight_on else "AUS")
	_hud_label.text = "NSG %s%s" % [state, ("  %d%%" % int(round(battery * 100.0))) if battery_enabled else ""]
	var col := Color(0.6, 1.0, 0.65, 0.9)
	if battery_enabled and battery < 0.2:
		col = Color(1.0, 0.45, 0.3, 0.9 if fmod(Time.get_ticks_msec() / 400.0, 2.0) < 1.0 else 0.4)
	elif not nv_on:
		col = Color(0.75, 0.8, 0.75, 0.6)
	_hud_label.add_theme_color_override("font_color", col)
	_hint.visible = _hint_t > 0.0 or (battery_enabled and battery < 0.03)
	var lamp := ("  ·  [%s] Lampe" % _key_name("flashlight")) if allow_flashlight else ""
	_hint.text = "[%s] Nachtsicht%s" % [_key_name("nightvision"), lamp]

func _beep(sfx_name: String, vol: float) -> void:
	if _snd == null:
		return
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return
	_snd.stream = st
	_snd.volume_db = vol
	_snd.play()
