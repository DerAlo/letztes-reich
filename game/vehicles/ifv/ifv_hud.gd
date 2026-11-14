extends CanvasLayer
## Turmoptik-HUD des Schuetzenpanzers: Fadenkreuz je Waffe, Zoom/Azimut, Munition/Hitze/Nebel,
## Schadensdiagramm (Draufsicht, vier Zonen), Warnungen (Panzerfaust, Kuehlung, Nachladen), Trefferblitz.

var ifv: Node = null
var _draw_ctl: Control
var _vignette: TextureRect
var _font: Font

const C_MAIN := Color(0.55, 1.0, 0.6, 0.9)
const C_DIM := Color(0.55, 1.0, 0.6, 0.45)
const C_WARN := Color(1.0, 0.75, 0.2, 0.95)
const C_RED := Color(1.0, 0.25, 0.2, 0.95)

func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_vignette = TextureRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.texture = _make_vignette()
	add_child(_vignette)
	_draw_ctl = Control.new()
	_draw_ctl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_ctl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_ctl.draw.connect(_on_draw)
	add_child(_draw_ctl)

func _process(_delta: float) -> void:
	visible = ifv != null and is_instance_valid(ifv)
	_draw_ctl.queue_redraw()

func _make_vignette() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0))
	g.set_offset(0, 0.55)
	g.set_color(1, Color(0, 0, 0, 0.82))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.05, 0.5)
	t.width = 256
	t.height = 256
	return t

func _txt(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, w: float = -1.0) -> void:
	_draw_ctl.draw_string(_font, pos, s, align, w, maxi(size, 8), col)

func _on_draw() -> void:
	if ifv == null or not is_instance_valid(ifv):
		return
	var sz := _draw_ctl.size
	if sz.y < 64.0:
		return
	var c := sz * 0.5
	var sc := sz.y / 1080.0
	var weapon: int = ifv.get("weapon")
	var zoom: int = ifv.get("zoom")
	# Trefferblitz
	var hf: float = ifv.get("hit_flash")
	if hf > 0.01:
		_draw_ctl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.9, 0.1, 0.05, 0.28 * hf))
	# Fadenkreuz
	var col := C_MAIN
	if weapon == 0:
		var g := 14.0 * sc
		var l := 70.0 * sc
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
			_draw_ctl.draw_line(c + d * g, c + d * (g + l), col, 2.0 * sc)
		_draw_ctl.draw_line(c + Vector2.UP * g, c + Vector2.UP * (g + l * 0.4), col, 2.0 * sc)
		# Entfernungsmarken (Haltepunkte)
		for i in range(1, 5):
			var y := c.y + g + i * 16.0 * sc
			var hw := (24.0 - i * 4.0) * sc
			_draw_ctl.draw_line(Vector2(c.x - hw, y), Vector2(c.x + hw, y), C_DIM, 1.5 * sc)
			_txt(Vector2(c.x + hw + 4.0 * sc, y + 5.0 * sc), str(i * 4), int(12 * sc), C_DIM)
		_draw_ctl.draw_circle(c, 2.0 * sc, col)
	else:
		_draw_ctl.draw_arc(c, 34.0 * sc, 0.0, TAU, 48, col, 1.5 * sc)
		for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			_draw_ctl.draw_line(c + d * 8.0 * sc, c + d * 26.0 * sc, col, 1.5 * sc)
		_draw_ctl.draw_circle(c, 1.6 * sc, col)
	# Zoom + Azimut + Elevation
	var zooms: Array[float] = [60.0, 26.0, 10.0]
	var mag := 60.0 / zooms[clampi(zoom, 0, 2)]
	_txt(Vector2(c.x - 300.0 * sc, c.y - 300.0 * sc), "VERGR. %.1fx" % mag, int(20 * sc), C_MAIN)
	var hull_yaw: float = ifv.get("hull_yaw")
	var tur_yaw: float = ifv.get("tur_yaw")
	var az := fposmod(rad_to_deg(-tur_yaw), 360.0)
	_txt(Vector2(c.x + 140.0 * sc, c.y - 300.0 * sc), "AZ %03d   EL %+.0f" % [int(az), rad_to_deg(float(ifv.get("tur_pitch")))], int(20 * sc), C_MAIN)
	# Azimut-Band oben
	var band_w := 400.0 * sc
	var by := 60.0 * sc
	_draw_ctl.draw_line(Vector2(c.x - band_w * 0.5, by), Vector2(c.x + band_w * 0.5, by), C_DIM, 1.0)
	for k in range(-20, 21):
		var deg := floorf(az / 5.0) * 5.0 + k * 5.0
		var x := c.x + (deg - az) * 4.0 * sc
		if absf(x - c.x) > band_w * 0.5:
			continue
		var big := int(fposmod(deg, 30.0)) == 0
		_draw_ctl.draw_line(Vector2(x, by), Vector2(x, by - (12.0 if big else 6.0) * sc), C_DIM, 1.0)
		if big:
			_txt(Vector2(x - 20.0 * sc, by - 16.0 * sc), "%03d" % int(fposmod(deg, 360.0)), int(14 * sc), C_DIM, HORIZONTAL_ALIGNMENT_CENTER, 40.0 * sc)
	_draw_ctl.draw_line(Vector2(c.x, by + 2.0), Vector2(c.x, by + 12.0 * sc), C_MAIN, 2.0)

	# ---- Waffenfeld unten rechts
	var px := sz.x - 380.0 * sc
	var py := sz.y - 210.0 * sc
	_draw_ctl.draw_rect(Rect2(px - 14.0 * sc, py - 34.0 * sc, 360.0 * sc, 196.0 * sc), Color(0, 0.05, 0, 0.45))
	var mk_ammo: int = ifv.get("mk_ammo")
	var mk_rel: float = ifv.get("mk_reload_t")
	var c0 := C_MAIN if weapon == 0 else C_DIM
	_txt(Vector2(px, py), ("> " if weapon == 0 else "  ") + "[1] MK 30 mm  SPRENG", int(20 * sc), c0)
	if mk_rel > 0.0:
		var k := 1.0 - mk_rel / 4.0
		_draw_ctl.draw_rect(Rect2(px + 20.0 * sc, py + 10.0 * sc, 300.0 * sc * k, 10.0 * sc), C_WARN)
		_txt(Vector2(px + 20.0 * sc, py + 42.0 * sc), "NACHLADEN", int(18 * sc), C_WARN)
	else:
		for i in 40:
			var x := px + 20.0 * sc + i * 7.5 * sc
			var r := Rect2(x, py + 10.0 * sc, 5.0 * sc, 14.0 * sc)
			if i < mk_ammo:
				_draw_ctl.draw_rect(r, c0)
			else:
				_draw_ctl.draw_rect(r, C_DIM * Color(1, 1, 1, 0.4), false, 1.0)
		_txt(Vector2(px + 20.0 * sc, py + 44.0 * sc), "%d / 40" % mk_ammo, int(16 * sc), c0)
	var heat: float = ifv.get("mg_heat")
	var locked: bool = ifv.get("mg_locked")
	var c1 := C_MAIN if weapon == 1 else C_DIM
	_txt(Vector2(px, py + 78.0 * sc), ("> " if weapon == 1 else "  ") + "[2] KOAX-MG 7,62", int(20 * sc), c1)
	var hcol := C_RED if locked else (C_WARN if heat > 0.7 else c1)
	_draw_ctl.draw_rect(Rect2(px + 20.0 * sc, py + 88.0 * sc, 300.0 * sc, 12.0 * sc), C_DIM * Color(1, 1, 1, 0.5), false, 1.0)
	_draw_ctl.draw_rect(Rect2(px + 20.0 * sc, py + 88.0 * sc, 300.0 * sc * heat, 12.0 * sc), hcol)
	if locked:
		_txt(Vector2(px + 20.0 * sc, py + 120.0 * sc), "KUEHLUNG", int(18 * sc), C_RED)
	var smoke: int = ifv.get("smoke_charges")
	var sc_col := C_MAIN if smoke > 0 else C_RED
	var sm_txt := "[F] NEBEL  "
	for i in 3:
		sm_txt += ("#" if i < smoke else "-") + " "
	if float(ifv.get("smoke_t")) > 0.0:
		sm_txt += " AKTIV"
	_txt(Vector2(px, py + 150.0 * sc), sm_txt, int(18 * sc), sc_col)

	# ---- Schadensdiagramm unten links (Draufsicht, vorn = oben)
	var dx := 150.0 * sc
	var dy := sz.y - 150.0 * sc
	_draw_ctl.draw_rect(Rect2(dx - 120.0 * sc, dy - 120.0 * sc, 240.0 * sc, 250.0 * sc), Color(0, 0.05, 0, 0.45))
	var zd: Array = ifv.get("zone_dmg")
	var hw := 34.0 * sc
	var hl := 70.0 * sc
	var rects := [Rect2(dx - hw, dy - hl, hw * 2.0, 18.0 * sc), Rect2(dx - hw, dy - hl + 18.0 * sc, 14.0 * sc, hl * 2.0 - 36.0 * sc),
		Rect2(dx + hw - 14.0 * sc, dy - hl + 18.0 * sc, 14.0 * sc, hl * 2.0 - 36.0 * sc), Rect2(dx - hw, dy + hl - 18.0 * sc, hw * 2.0, 18.0 * sc)]
	for i in 4:
		var v: float = zd[i]
		var zc := C_MAIN.lerp(C_WARN, clampf(v * 2.0, 0.0, 1.0)).lerp(C_RED, clampf(v * 2.0 - 1.0, 0.0, 1.0))
		_draw_ctl.draw_rect(rects[i], zc * Color(1, 1, 1, 0.75))
	_draw_ctl.draw_rect(Rect2(dx - hw, dy - hl, hw * 2.0, hl * 2.0), C_MAIN, false, 1.5)
	# Turmrichtung relativ zur Wanne
	var rel := tur_yaw - hull_yaw
	var tdir := Vector2(-sin(rel), -cos(rel))
	_draw_ctl.draw_circle(Vector2(dx, dy - 6.0 * sc), 16.0 * sc, C_DIM)
	_draw_ctl.draw_line(Vector2(dx, dy - 6.0 * sc), Vector2(dx, dy - 6.0 * sc) + tdir * 46.0 * sc, C_MAIN, 3.0 * sc)
	var integ: float = ifv.get("integrity")
	var icol := C_MAIN if integ > 50.0 else (C_WARN if integ > 25.0 else C_RED)
	_txt(Vector2(dx - 110.0 * sc, dy + 112.0 * sc), "RABE  %d %%" % int(ceilf(integ)), int(20 * sc), icol)
	var st: String = ifv.get("status_text")
	if st == "":
		st = "FAHRT" if bool(ifv.call("moving")) else "HALT"
	_txt(Vector2(dx - 110.0 * sc, dy - 128.0 * sc), st, int(18 * sc), C_DIM)

	# ---- Zielmarken (Gruppe "ifv_marker", Meta hud_label; Panzerfaust-Schuetzen im Anschlag blinken rot)
	_draw_markers(sz, sc)

	# ---- Warnungen
	var rw: float = ifv.get("rocket_warn")
	if rw > 0.0 and fmod(rw, 0.3) > 0.12:
		_txt(Vector2(c.x - 200.0 * sc, c.y + 170.0 * sc), "PANZERFAUST!", int(40 * sc), C_RED, HORIZONTAL_ALIGNMENT_CENTER, 400.0 * sc)
		var from: Vector3 = ifv.get("rocket_from")
		var pos: Vector3 = (ifv as Node3D).global_position
		var to := from - pos
		var ang := atan2(-to.x, -to.z) - tur_yaw
		var ad := Vector2(-sin(ang), -cos(ang))
		var tip := c + ad * 150.0 * sc
		_draw_ctl.draw_line(c + ad * 100.0 * sc, tip, C_RED, 4.0 * sc)
		var side := Vector2(-ad.y, ad.x)
		_draw_ctl.draw_colored_polygon(PackedVector2Array([tip + ad * 18.0 * sc, tip + side * 12.0 * sc, tip - side * 12.0 * sc]), C_RED)
	if integ <= 25.0 and integ > 0.0 and fmod(Time.get_ticks_msec() / 1000.0, 0.8) > 0.4:
		_txt(Vector2(c.x - 200.0 * sc, c.y + 230.0 * sc), "SCHWERER SCHADEN", int(28 * sc), C_RED, HORIZONTAL_ALIGNMENT_CENTER, 400.0 * sc)
	if bool(ifv.get("dead")):
		_draw_ctl.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.2, 0.0, 0.0, 0.5))
		_txt(Vector2(c.x - 300.0 * sc, c.y - 60.0 * sc), "FAHRZEUG AUSGEFALLEN", int(44 * sc), C_RED, HORIZONTAL_ALIGNMENT_CENTER, 600.0 * sc)

## Sichtlinie Kamera -> Zielpunkt durch Weltgeometrie verdeckt? (Treffer am Ziel selbst zaehlt als frei)
func _occluded(cam: Camera3D, target: Node3D, p: Vector3) -> bool:
	var space := cam.get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, p, 1)
	var ex: Array[RID] = []
	if ifv is CollisionObject3D:
		ex.append((ifv as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		ex.append((target as CollisionObject3D).get_rid())
	q.exclude = ex
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	return (hit["position"] as Vector3).distance_to(p) > 1.5

## Markiert Ziele im Turmbild: Eckwinkel + Bezeichnung + Entfernung, ausserhalb des Bildes ein Randpfeil.
## Meta am Ziel: hud_label (Text), hud_off (Vector3, Zielpunkt ueber dem Ursprung), hud_hp_max (Lebensbalken
## aus `health`), hud_aim (Zeitpunkt in s bis zu dem der Schuetze im Anschlag ist -> rot, blinkend).
func _draw_markers(sz: Vector2, sc: float) -> void:
	var cam: Camera3D = ifv.get("cam")
	if cam == null or not is_instance_valid(cam) or not cam.is_inside_tree():
		return
	var vp_size := cam.get_viewport().get_visible_rect().size
	if vp_size.x < 2.0:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var me := (ifv as Node3D).global_position
	var inset := 70.0 * sc
	for n: Node in get_tree().get_nodes_in_group("ifv_marker"):
		if not (n is Node3D) or not is_instance_valid(n) or n.is_queued_for_deletion() or not n.has_meta("hud_label"):
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		var p: Vector3 = (n as Node3D).global_position + (n.get_meta("hud_off", Vector3(0, 1.2, 0)) as Vector3)
		var dist := me.distance_to(p)
		if dist > 140.0:
			continue
		var aim := float(n.get_meta("hud_aim", 0.0)) > now
		var col := C_WARN
		if aim:
			col = C_RED if fmod(now, 0.25) < 0.15 else Color(1.0, 0.9, 0.85, 0.95)
		var label := "%s  %d m" % [str(n.get_meta("hud_label")), int(dist)]
		if aim:
			label = "FEUERT!  " + label
		var behind := cam.is_position_behind(p)
		var sp := cam.unproject_position(p) / vp_size * sz
		var on := not behind and sp.x > inset and sp.x < sz.x - inset and sp.y > inset and sp.y < sz.y - inset
		if on and not aim and _occluded(cam, n as Node3D, p):
			# Ziel steht hinter einer Hauswand (z.B. Fensterloch schraeg von vorn noch nicht einsehbar):
			# gedimmte Raute statt Zielwinkel, sonst klebt die Marke auf der falschen Fassade.
			var dc := Color(col.r, col.g, col.b, 0.45)
			var q := 9.0 * sc
			var pts := PackedVector2Array([sp + Vector2(0, -q), sp + Vector2(q, 0), sp + Vector2(0, q), sp + Vector2(-q, 0), sp + Vector2(0, -q)])
			_draw_ctl.draw_polyline(pts, dc, 1.5 * sc)
			_txt(sp + Vector2(-150.0 * sc, -q - 22.0 * sc), "%s (verdeckt)  %d m" % [str(n.get_meta("hud_label")), int(dist)], int(14 * sc), dc, HORIZONTAL_ALIGNMENT_CENTER, 300.0 * sc)
		elif on:
			var r := clampf(900.0 / maxf(dist, 1.0), 16.0, 46.0) * sc * (1.25 if aim else 1.0)
			var l := r * 0.45
			var w := (3.0 if aim else 2.0) * sc
			for cx: float in [-1.0, 1.0]:
				for cy: float in [-1.0, 1.0]:
					var corner := sp + Vector2(cx, cy) * r
					_draw_ctl.draw_line(corner, corner - Vector2(cx * l, 0), col, w)
					_draw_ctl.draw_line(corner, corner - Vector2(0, cy * l), col, w)
			_txt(sp + Vector2(-150.0 * sc, -r - 8.0 * sc), label, int((22 if aim else 17) * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 300.0 * sc)
			if n.has_meta("hud_hp_max"):
				var k := clampf(float(n.get("health")) / float(n.get_meta("hud_hp_max")), 0.0, 1.0)
				var br := Rect2(sp + Vector2(-r, r + 6.0 * sc), Vector2(r * 2.0, 7.0 * sc))
				_draw_ctl.draw_rect(br, Color(0, 0, 0, 0.5))
				_draw_ctl.draw_rect(Rect2(br.position, Vector2(br.size.x * k, br.size.y)), col)
				_draw_ctl.draw_rect(br, col, false, 1.0)
		else:
			# Richtung auf dem Bildrand (hinter der Kamera gespiegelt)
			var c := sz * 0.5
			var d := sp - c
			if behind:
				d = -d
			if d.length() < 1.0:
				d = Vector2(0, 1)
			d = d.normalized()
			var half := c - Vector2(inset, inset)
			var t := minf(half.x / maxf(absf(d.x), 0.001), half.y / maxf(absf(d.y), 0.001))
			var tip := c + d * t
			var side := Vector2(-d.y, d.x)
			var a := (22.0 if aim else 15.0) * sc
			_draw_ctl.draw_colored_polygon(PackedVector2Array([tip + d * a, tip + side * a * 0.7, tip - side * a * 0.7]), col)
			var tp := tip - d * 40.0 * sc + Vector2(-150.0 * sc, 6.0 * sc)
			_txt(tp, label, int((20 if aim else 15) * sc), col, HORIZONTAL_ALIGNMENT_CENTER, 300.0 * sc)
