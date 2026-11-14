extends CanvasLayer
## HUD der RailRide-Bordwaffe: Fadenkreuz (offen, mit Streukreis), Hitzebalken + Ueberhitzungswarnung,
## Zustandsbalken des Fahrzeugs, Tempo, Treffer-/Abschussmarker, Trefferrichtung, Hinweistext.

var ride: Node = null
var _ctl: Control
var _vig: TextureRect
var _font: Font

const C_MAIN := Color(0.95, 0.95, 0.9, 0.88)
const C_DIM := Color(0.95, 0.95, 0.9, 0.4)
const C_WARN := Color(1.0, 0.72, 0.2, 0.95)
const C_RED := Color(1.0, 0.25, 0.2, 0.95)

func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_vig = TextureRect.new()
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_offset(0, 0.5)
	g.set_color(1, Color(0.6, 0.0, 0.0, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	_vig.texture = t
	_vig.modulate.a = 0.0
	add_child(_vig)
	_ctl = Control.new()
	_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ctl.draw.connect(_on_draw)
	add_child(_ctl)

func _process(_delta: float) -> void:
	var ok := ride != null and is_instance_valid(ride)
	visible = ok
	if not ok:
		return
	var low := 1.0 - float(ride.get("integrity")) / maxf(float(ride.get("max_integrity")), 1.0)
	_vig.modulate.a = clampf(float(ride.get("hit_flash")) * 0.7 + maxf(low - 0.55, 0.0) * 1.2, 0.0, 0.9)
	_ctl.queue_redraw()

func _txt(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	_ctl.draw_string(_font, pos, s, align, w, maxi(size, 8), col)

func _on_draw() -> void:
	if ride == null or not is_instance_valid(ride):
		return
	var sz := _ctl.size
	if sz.y < 64.0:
		return
	var c := sz * 0.5
	var sc := sz.y / 1080.0
	var heat: float = ride.get("heat")
	var locked: bool = ride.get("locked")
	var col := C_RED if locked else (C_WARN if heat > 0.75 else C_MAIN)
	# Fadenkreuz: vier Striche + Punkt, Luecke waechst mit Hitze (Streuung)
	var gap := (10.0 + heat * 10.0) * sc
	var ln := 14.0 * sc
	var w := maxf(2.0 * sc, 1.0)
	for d: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		_ctl.draw_line(c + d * gap, c + d * (gap + ln), col, w)
	_ctl.draw_circle(c, maxf(1.6 * sc, 1.0), col)
	# Treffer-/Abschussmarker
	var hm: float = ride.get("hitmarker_t")
	var km: float = ride.get("kill_t")
	if hm > 0.0 or km > 0.0:
		var hc := C_RED if km > 0.0 else Color(1, 1, 1, 0.9)
		var r0 := 8.0 * sc
		var r1 := (16.0 if km > 0.0 else 13.0) * sc
		for d: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var dn := d.normalized()
			_ctl.draw_line(c + dn * r0, c + dn * r1, hc, w)
	# Trefferrichtung (roter Bogen am Rand des Fadenkreuzes)
	var ht: float = ride.get("hit_dir_t")
	if ht > 0.0:
		var a: float = ride.get("hit_dir")
		var rr := 120.0 * sc
		var ang := -PI * 0.5 - a
		_ctl.draw_arc(c, rr, ang - 0.28, ang + 0.28, 12, Color(1, 0.2, 0.15, clampf(ht, 0.0, 1.0) * 0.85), 5.0 * sc)
	# Unten links: Fahrzeug-Zustand + Tempo
	var bx := 48.0 * sc
	var by := sz.y - 120.0 * sc
	var bw := 300.0 * sc
	var bh := 14.0 * sc
	var integ := float(ride.get("integrity")) / maxf(float(ride.get("max_integrity")), 1.0)
	_txt(Vector2(bx, by - 8.0 * sc), str(ride.get("vehicle_name")).to_upper(), int(22 * sc), C_DIM)
	_ctl.draw_rect(Rect2(bx, by, bw, bh), Color(0, 0, 0, 0.45))
	var icol := C_MAIN if integ > 0.5 else (C_WARN if integ > 0.25 else C_RED)
	_ctl.draw_rect(Rect2(bx, by, bw * integ, bh), icol)
	_ctl.draw_rect(Rect2(bx, by, bw, bh), C_DIM, false, maxf(sc, 1.0))
	# Tempo nur bei fahrenden Bordwaffen; stationaere Waffen (Tuer-MG, MG-Stellung: cruise_speed 0) ohne km/h
	var kmh := float(ride.get("speed")) * 3.6
	if float(ride.get("cruise_speed")) > 0.01 or kmh >= 1.0:
		_txt(Vector2(bx, by + bh + 30.0 * sc), "%d km/h" % roundi(kmh), int(26 * sc), C_MAIN)
	# Unten rechts: Waffe + Hitze
	var rx := sz.x - 48.0 * sc - bw
	var wd: Dictionary = ride.get("weapon")
	_txt(Vector2(rx, by - 8.0 * sc), str(wd.get("name", "MG")).to_upper(), int(22 * sc), C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	_ctl.draw_rect(Rect2(rx, by, bw, bh), Color(0, 0, 0, 0.45))
	_ctl.draw_rect(Rect2(rx, by, bw * heat, bh), col)
	_ctl.draw_rect(Rect2(rx, by, bw, bh), C_DIM, false, maxf(sc, 1.0))
	var lockx := rx + bw * float(wd.get("unlock_at", 0.35))
	_ctl.draw_line(Vector2(lockx, by - 3.0 * sc), Vector2(lockx, by + bh + 3.0 * sc), C_DIM, maxf(sc, 1.0))
	if locked:
		var blink := 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.012)
		_txt(Vector2(rx, by + bh + 30.0 * sc), "LAUF UEBERHITZT", int(24 * sc), Color(C_RED, blink), HORIZONTAL_ALIGNMENT_RIGHT, bw)
	elif heat > 0.75:
		_txt(Vector2(rx, by + bh + 30.0 * sc), "HITZE", int(22 * sc), C_WARN, HORIZONTAL_ALIGNMENT_RIGHT, bw)
	if bool(ride.get("zoomed")):
		_txt(Vector2(c.x - 100.0 * sc, c.y + 70.0 * sc), "ZOOM", int(18 * sc), C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 200.0 * sc)
	var hint: String = ride.get("hud_hint")
	if hint != "":
		_txt(Vector2(0, sz.y - 40.0 * sc), hint, int(22 * sc), C_MAIN, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if bool(ride.get("dead")):
		_txt(Vector2(0, c.y - 120.0 * sc), str(ride.get("vehicle_name")).to_upper() + " AUSGEFALLEN", int(40 * sc), C_RED, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
