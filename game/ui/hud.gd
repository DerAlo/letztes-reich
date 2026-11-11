class_name PlayerHUD
extends CanvasLayer
## Schlichtes HUD: Fadenkreuz (wächst mit Streuung), Munition, Granaten, Hitmarker,
## Schadens-Vignette, Richtungsanzeige, Nachlade-Hinweis, Todes-Overlay.
## Wird vom Player per show_hitmarker/show_damage/show_death gesteuert, liest den Rest per get_hud_info().

@export var line_color: Color = Color(1, 1, 1, 0.85)
@export var shadow_color: Color = Color(0, 0, 0, 0.35)
@export var crosshair_len: float = 9.0
@export var crosshair_min_gap: float = 5.0
@export var hit_time: float = 0.18
@export var kill_time: float = 0.5
@export var damage_indicator_time: float = 1.6
@export var vignette_decay: float = 1.4

## ADS: Rand leicht abdunkeln und unscharf (Fokus auf die Optik)
const ADS_SHADER: String = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = (uv - vec2(0.5)) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float r = length(d);
	float e = smoothstep(0.36, 0.95, r) * amount;
	vec3 sharp = textureLod(screen_tex, uv, 0.0).rgb;
	vec3 blur = textureLod(screen_tex, uv, 2.2).rgb;
	vec3 c = mix(sharp, blur, clamp(e * 1.6, 0.0, 1.0));
	c *= 1.0 - e * 0.4;
	COLOR = vec4(c, 1.0);
}
"""

const VIGNETTE_SHADER: String = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.6, 0.0, 0.02, 1.0);
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 0.85)) * 1.55;
	float v = smoothstep(0.38, 1.05, d);
	COLOR = vec4(tint.rgb, v * intensity);
}
"""

var player: Player = null
var _overlay: Control
var _vignette: ColorRect
var _vig_mat: ShaderMaterial
var _ads_rect: ColorRect
var _ads_mat: ShaderMaterial
var _ammo_label: Label
var _reserve_label: Label
var _weapon_label: Label
var _grenade_label: Label
var _reload_label: Label
var _toast_label: Label
var _interact_label: Label
var _death_rect: ColorRect
var _death_label: Label
var _hit_t: float = 0.0
var _hit_kill: bool = false
var _hit_head: bool = false
var _indicators: Array[Dictionary] = []
var _flash: float = 0.0
var _info: Dictionary = {}
var _death_amt: float = 0.0
var _dead: bool = false
var _toast_t: float = 0.0
var _time: float = 0.0
var _gap_s: float = -1.0          # geglättete Fadenkreuz-Lücke (px)
var _slot_box: HBoxContainer
var _slot_labels: Array[Label] = []
var _last_weapon_idx: int = -1
var _pop: float = 0.0

func _ready() -> void:
	layer = 5
	_build()
	player = get_parent() as Player
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Player
	Events.checkpoint_reached.connect(func(_id: String) -> void: toast("CHECKPOINT"))
	_init_options()

# ---------------------------------------------------------------- Optionen (Settings, Runde 6)
# Fadenkreuz-Stil: 0 Standard, 1 Punkt, 2 Kreuz ohne Punkt, 3 Kreis, 4 Aus. Farbe: 0 = line_color (Standard).
const XH_COLORS := [Color(1, 1, 1), Color(0.3, 1.0, 0.35), Color(1.0, 0.92, 0.2), Color(0.25, 0.95, 1.0),
	Color(1.0, 0.25, 0.2), Color(1.0, 0.3, 0.95)]
var _xh_style: int = 0
var _xh_color: int = 0
var _hitmarkers: bool = true

func _init_options() -> void:
	var st := get_node_or_null("/root/Settings")
	if st == null:
		return
	_load_options(st)
	st.connect("changed", func(_k: String, _v) -> void: _load_options(st))

func _load_options(st: Node) -> void:
	if not is_instance_valid(st):
		return
	var v = st.call("get_value", "game/crosshair", 0)
	_xh_style = int(v) if v != null else 0
	v = st.call("get_value", "game/crosshair_color", 0)
	_xh_color = int(v) if v != null else 0
	v = st.call("get_value", "game/hitmarkers", true)
	_hitmarkers = bool(v) if v != null else true

# ---------------------------------------------------------------- Aufbau

func _make_label(size: int, align: HorizontalAlignment, color: Color = Color(1, 1, 1, 0.9)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build() -> void:
	# ADS-Rand (unter allem anderen HUD)
	_ads_rect = ColorRect.new()
	_ads_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ads_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ash := Shader.new()
	ash.code = ADS_SHADER
	_ads_mat = ShaderMaterial.new()
	_ads_mat.shader = ash
	_ads_rect.material = _ads_mat
	_ads_rect.visible = false
	add_child(_ads_rect)
	# Vignette
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = sh
	_vignette.material = _vig_mat
	add_child(_vignette)
	# Zeichenfläche (Fadenkreuz, Hitmarker, Richtungsanzeige, Balken)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_draw)
	add_child(_overlay)
	# Munition unten rechts
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_right = -56
	box.offset_bottom = -44
	box.alignment = BoxContainer.ALIGNMENT_END
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", -4)
	add_child(box)
	_weapon_label = _make_label(16, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.55))
	_ammo_label = _make_label(54, HORIZONTAL_ALIGNMENT_RIGHT)
	_reserve_label = _make_label(22, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.65))
	_grenade_label = _make_label(18, HORIZONTAL_ALIGNMENT_RIGHT, Color(1, 1, 1, 0.8))
	# Waffen-Slots: "1 G36C  2 P1  3 PANZERFAUST 3", aktive Waffe hervorgehoben
	_slot_box = HBoxContainer.new()
	_slot_box.alignment = BoxContainer.ALIGNMENT_END
	_slot_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_box.add_theme_constant_override("separation", 14)
	box.add_child(_slot_box)
	for l in [_weapon_label, _ammo_label, _reserve_label, _grenade_label]:
		box.add_child(l)
	# Nachladen-Hinweis (Mitte, unter dem Fadenkreuz)
	_reload_label = _make_label(22, HORIZONTAL_ALIGNMENT_CENTER, Color(1, 0.95, 0.8, 0.95))
	_reload_label.set_anchors_preset(Control.PRESET_CENTER)
	_reload_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_reload_label.offset_left = -200
	_reload_label.offset_right = 200
	_reload_label.offset_top = 70
	_reload_label.offset_bottom = 100
	add_child(_reload_label)
	# Interaktions-Hinweis ("[E] AK-74M aufnehmen"), unter dem Nachladen-Hinweis
	_interact_label = _make_label(20, HORIZONTAL_ALIGNMENT_CENTER, Color(1.0, 0.92, 0.7, 0.95))
	_interact_label.set_anchors_preset(Control.PRESET_CENTER)
	_interact_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_interact_label.offset_left = -260
	_interact_label.offset_right = 260
	_interact_label.offset_top = 108
	_interact_label.offset_bottom = 136
	add_child(_interact_label)
	# Hinweis oben Mitte
	_toast_label = _make_label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_label.offset_left = -250
	_toast_label.offset_right = 250
	_toast_label.offset_top = 80
	_toast_label.offset_bottom = 120
	_toast_label.modulate.a = 0.0
	add_child(_toast_label)
	# Tod
	_death_rect = ColorRect.new()
	_death_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_rect.color = Color(0.02, 0.0, 0.0, 1.0)
	_death_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_rect.modulate.a = 0.0
	add_child(_death_rect)
	_death_label = _make_label(40, HORIZONTAL_ALIGNMENT_CENTER, Color(0.85, 0.15, 0.12, 1.0))
	_death_label.text = "GEFALLEN"
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_label.offset_left = -250
	_death_label.offset_right = 250
	_death_label.offset_top = -30
	_death_label.offset_bottom = 30
	_death_label.modulate.a = 0.0
	add_child(_death_label)

# ---------------------------------------------------------------- Öffentliche API

func show_hitmarker(kill: bool, headshot: bool = false) -> void:
	if not _hitmarkers:
		return
	_hit_kill = kill
	_hit_head = headshot
	_hit_t = kill_time if (kill or headshot) else hit_time

## angle: 0 = von vorn, + = von rechts (Bogenmaß); NAN = ohne Richtung
func show_damage(angle: float, amount: float) -> void:
	_flash = clampf(_flash + 0.45 + amount / 120.0, 0.0, 1.0)
	if not is_nan(angle):
		_indicators.append({"angle": angle, "t": damage_indicator_time})
		if _indicators.size() > 6:
			_indicators.pop_front()

func show_death() -> void:
	_dead = true

func hide_death() -> void:
	_dead = false
	_indicators.clear()
	_flash = 0.0

func toast(text: String, seconds: float = 2.0) -> void:
	_toast_label.text = text
	_toast_t = seconds

# ---------------------------------------------------------------- Update

func _process(delta: float) -> void:
	_time += delta
	if player == null:
		return
	_info = player.get_hud_info()
	_flash = maxf(0.0, _flash - vignette_decay * delta)
	_hit_t = maxf(0.0, _hit_t - delta)
	for i in range(_indicators.size() - 1, -1, -1):
		_indicators[i]["t"] = float(_indicators[i]["t"]) - delta
		if float(_indicators[i]["t"]) <= 0.0:
			_indicators.remove_at(i)
	# Vignette: Treffer-Blitz + dauerhaft bei niedriger Gesundheit
	var hp_ratio: float = float(_info.health) / maxf(float(_info.max_health), 1.0)
	var low: float = clampf((0.45 - hp_ratio) / 0.45, 0.0, 1.0) * 0.7
	_vig_mat.set_shader_parameter("intensity", clampf(maxf(_flash, low), 0.0, 1.0))
	var ads: float = float(_info.get("ads", 0.0)) if bool(_info.alive) else 0.0
	_ads_rect.visible = ads > 0.02
	_ads_mat.set_shader_parameter("amount", smoothstep(0.3, 1.0, ads))
	# Texte
	var mag: int = int(_info.ammo_mag)
	_ammo_label.text = "%d" % mag
	_ammo_label.add_theme_color_override("font_color", Color(1, 0.4, 0.3, 0.95) if mag == 0 else Color(1, 1, 1, 0.92))
	_reserve_label.text = "/ %d" % int(_info.ammo_reserve)
	_weapon_label.text = str(_info.weapon_name)
	_update_slots(delta)
	var g: int = int(_info.grenades)
	_grenade_label.text = "GRANATEN  " + "● ".repeat(g) + "○ ".repeat(maxi(0, 4 - g))
	# Nachladen-Hinweis
	var mag_size: int = int(_info.mag_size)
	if _info.reloading:
		_reload_label.text = "NACHLADEN"
		_reload_label.modulate.a = 0.9
	elif mag == 0 and int(_info.ammo_reserve) == 0:
		_reload_label.text = "KEINE MUNITION"
		_reload_label.modulate.a = 0.5 + 0.5 * sin(_time * 8.0)
	elif mag_size > 2 and mag <= int(ceil(mag_size * 0.25)) and int(_info.ammo_reserve) > 0:
		_reload_label.text = "NACHLADEN  [R]"
		_reload_label.modulate.a = 0.55 + 0.45 * sin(_time * 7.0)
	else:
		_reload_label.modulate.a = 0.0
	# Interaktion
	var hint: String = str(_info.get("interact_hint", ""))
	_interact_label.text = hint
	_interact_label.visible = hint != "" and bool(_info.alive)
	# Toast + Tod
	_toast_t = maxf(0.0, _toast_t - delta)
	_toast_label.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_death_amt = move_toward(_death_amt, 1.0 if _dead else 0.0, delta * (0.8 if _dead else 3.0))
	_death_rect.modulate.a = _death_amt * 0.85
	_death_label.modulate.a = clampf((_death_amt - 0.3) * 2.0, 0.0, 1.0)
	_overlay.queue_redraw()

# ---------------------------------------------------------------- Zeichnen

func _update_slots(delta: float) -> void:
	var names: Array = _info.get("weapon_names", [])
	var idx: int = int(_info.get("weapon_index", 0))
	while _slot_labels.size() < names.size():
		var l := _make_label(14, HORIZONTAL_ALIGNMENT_RIGHT)
		_slot_box.add_child(l)
		_slot_labels.append(l)
	for i in _slot_labels.size():
		var l: Label = _slot_labels[i]
		l.visible = i < names.size()
		if not l.visible:
			continue
		l.text = "%d  %s" % [i + 1, str(names[i])]
		var active: bool = i == idx
		l.add_theme_color_override("font_color",
				Color(1.0, 0.86, 0.45, 0.95) if active else Color(1, 1, 1, 0.35))
	if idx != _last_weapon_idx:
		if _last_weapon_idx >= 0:
			_pop = 1.0
		_last_weapon_idx = idx
	_pop = maxf(0.0, _pop - delta * 3.5)
	var k: float = 1.0 + 0.25 * _pop * _pop
	_weapon_label.pivot_offset = _weapon_label.size
	_weapon_label.scale = Vector2(k, k)
	_weapon_label.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.55).lerp(Color(1.0, 0.86, 0.45, 1.0), _pop))
	# Fadenkreuz-Lücke glätten (reale Streuung aus weapon.gd)
	var size: Vector2 = _overlay.size
	if size.y > 0.0:
		var px_per_rad: float = (size.y * 0.5) / tan(deg_to_rad(float(_info.fov) * 0.5))
		var target: float = maxf(crosshair_min_gap, tan(deg_to_rad(float(_info.spread_deg))) * px_per_rad)
		_gap_s = target if _gap_s < 0.0 else lerpf(_gap_s, target, 1.0 - exp(-18.0 * delta))

func _line(a: Vector2, b: Vector2, color: Color, w: float = 1.6) -> void:
	_overlay.draw_line(a + Vector2(1, 1), b + Vector2(1, 1), shadow_color, w + 1.0, true)
	_overlay.draw_line(a, b, color, w, true)

func _on_draw() -> void:
	if _info.is_empty():
		return
	var size: Vector2 = _overlay.size
	var c: Vector2 = size * 0.5
	if bool(_info.alive):
		_draw_crosshair(c, size)
		_draw_hitmarker(c)
		_draw_reload_bar(c)
	_draw_indicators(c, size)
	_draw_health(size)

func _draw_crosshair(c: Vector2, size: Vector2) -> void:
	var fov: float = float(_info.fov)
	var spread: float = float(_info.spread_deg)
	var px_per_rad: float = (size.y * 0.5) / tan(deg_to_rad(fov * 0.5))
	var gap: float = maxf(crosshair_min_gap, tan(deg_to_rad(spread)) * px_per_rad)
	if _gap_s > 0.0:
		gap = _gap_s
	var ads: float = float(_info.ads)
	var sprint: float = float(_info.sprint)
	# Beim Zielen ausblenden (Red Dot / Kimme übernimmt)
	var a: float = clampf(1.0 - ads * 1.8, 0.0, 1.0) * (1.0 - 0.6 * sprint)
	if a <= 0.01 or _xh_style == 4:
		return
	var col := Color(line_color.r, line_color.g, line_color.b, line_color.a * a)
	if _xh_color > 0 and _xh_color < XH_COLORS.size():
		var xc: Color = XH_COLORS[_xh_color]
		col = Color(xc.r, xc.g, xc.b, col.a)
	if _xh_style == 1:
		_overlay.draw_rect(Rect2(c - Vector2(2.5, 2.5), Vector2(5, 5)), Color(0, 0, 0, col.a * 0.5))
		_overlay.draw_rect(Rect2(c - Vector2(1.5, 1.5), Vector2(3, 3)), col)
		return
	if _xh_style == 3:
		_overlay.draw_arc(c, gap + 2.0, 0.0, TAU, 48, Color(0, 0, 0, col.a * 0.45), 3.0, true)
		_overlay.draw_arc(c, gap + 2.0, 0.0, TAU, 48, col, 1.5, true)
		_overlay.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(col.r, col.g, col.b, col.a * 0.9))
		return
	var l: float = crosshair_len * (1.0 - 0.3 * ads)
	_line(c + Vector2(gap, 0), c + Vector2(gap + l, 0), col)
	_line(c - Vector2(gap, 0), c - Vector2(gap + l, 0), col)
	_line(c + Vector2(0, gap), c + Vector2(0, gap + l), col)
	_line(c - Vector2(0, gap), c - Vector2(0, gap + l), col)
	if _xh_style != 2:
		_overlay.draw_rect(Rect2(c - Vector2(1, 1), Vector2(2, 2)), Color(col.r, col.g, col.b, col.a * 0.8))

func _draw_hitmarker(c: Vector2) -> void:
	if _hit_t <= 0.0:
		return
	var total: float = kill_time if (_hit_kill or _hit_head) else hit_time
	var k: float = _hit_t / total
	var al: float = minf(1.0, k * 1.6)
	var col: Color = Color(1.0, 0.18, 0.12, al) if _hit_kill else Color(1, 1, 1, al)
	var r0: float = 7.0 + (1.0 - k) * (3.0 if not _hit_kill else 8.0)
	var r1: float = r0 + (9.0 if not _hit_kill else 13.0)
	var w: float = 2.0 if not _hit_kill else 2.8
	if _hit_head:
		# Kopftreffer: rot-orange, größer, dicker, mit kurzem Ring
		col = Color(1.0, 0.1, 0.06, al) if _hit_kill else Color(1.0, 0.45, 0.1, al)
		r0 += 3.0
		r1 += 7.0
		w += 1.0
		_overlay.draw_arc(c, r1 + 4.0 + (1.0 - k) * 10.0, 0.0, TAU, 40, Color(col.r, col.g, col.b, al * 0.7), 1.6, true)
	for d in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var dn: Vector2 = (d as Vector2).normalized()
		_line(c + dn * r0, c + dn * r1, col, w)

func _draw_reload_bar(c: Vector2) -> void:
	if not bool(_info.reloading):
		return
	var w: float = 120.0
	var p: float = float(_info.reload_progress)
	var y: float = c.y + 62.0
	_overlay.draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x + w * 0.5, y), Color(1, 1, 1, 0.2), 2.0)
	_overlay.draw_line(Vector2(c.x - w * 0.5, y), Vector2(c.x - w * 0.5 + w * p, y), Color(1, 1, 1, 0.9), 2.0)

func _draw_indicators(c: Vector2, size: Vector2) -> void:
	var r_in: float = size.y * 0.26
	var r_out: float = size.y * 0.31
	for ind in _indicators:
		var a: float = float(ind.angle)
		var k: float = clampf(float(ind.t) / damage_indicator_time, 0.0, 1.0)
		var col := Color(0.9, 0.08, 0.05, k * 0.85)
		var pts := PackedVector2Array()
		var half: float = 0.32
		var steps: int = 8
		for i in range(steps + 1):
			var aa: float = a - half + 2.0 * half * float(i) / float(steps)
			pts.append(c + Vector2(sin(aa), -cos(aa)) * r_out)
		for i in range(steps, -1, -1):
			var aa: float = a - half * 0.8 + 2.0 * half * 0.8 * float(i) / float(steps)
			pts.append(c + Vector2(sin(aa), -cos(aa)) * r_in)
		_overlay.draw_colored_polygon(pts, col)

func _draw_health(size: Vector2) -> void:
	var hp: float = float(_info.health) / maxf(float(_info.max_health), 1.0)
	if hp >= 0.999 or not bool(_info.alive):
		return
	var x0: float = 56.0
	var y: float = size.y - 44.0
	var w: float = 180.0
	var col := Color(1, 1, 1, 0.7).lerp(Color(1, 0.2, 0.15, 0.9), 1.0 - hp)
	_overlay.draw_line(Vector2(x0, y), Vector2(x0 + w, y), Color(1, 1, 1, 0.15), 3.0)
	_overlay.draw_line(Vector2(x0, y), Vector2(x0 + w * hp, y), col, 3.0)
