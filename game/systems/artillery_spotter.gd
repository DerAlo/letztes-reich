extends Node
## Artillerie-Beobachter (opt-in, wiederverwendbar): Fernglas mit Entfernungsmesser und Marschrichtung,
## Ziel markieren -> Feuerauftrag an einen (unsichtbaren) Moerserzug, Salven mit Flugzeit und Streuung,
## Korrekturen ("weiter 50", "links 20") oder Neu-Markieren, begrenzte Salven, Nachladezeit.
##
## Einbau (Level):
##   var sp = preload("res://game/systems/artillery_spotter.gd").new()
##   sp.visibility_check = func(p: Vector3) -> bool: return wx.is_window_open()
##   add_child(sp); sp.enabled = true
## Funk/Story macht das Level ueber die Signale (das System spricht selbst nicht).
##
## Bedienung: [binoculars] (B) Fernglas an/aus, im Fernglas: LMB = Ziel markieren bzw. offene Korrektur
## senden, RMB = Zoomstufe, Pfeiltasten = Korrektur (10 m, mit Shift 50 m). rmb_raises = true: RMB-Halten
## hebt das Fernglas (reine Beobachter-Abschnitte).
##
## Einschiessen (adjust_mode = true): Markieren/Korrektur loest EINEN Einschiess-Schuss aus (kleine
## Streuung, kostet keine Salve); der Einschlag bleibt als Marker im Fernglas stehen (plus Rauchsaeule),
## dazu ein "Geist" fuer die vorgemerkte Korrektur. [spotter_effect] (F) = Wirkungsfeuer mit
## effect_rounds Granaten (elliptische Streuung laengs der Schussrichtung) auf den aktuellen Zielpunkt.
##
## Bot/Level-API: raise(an), is_up(), mark_from_camera(), mark_point(p), add_correction(weiter, rechts),
## send_correction(), fire_for_effect(), refill(n), state(), busy(), is_effect(), last_impacts(),
## aim_point(), target_point(), ot_basis(p), has_target().

signal binoculars_changed(up: bool)
signal mission_requested(target: Vector3, distance: float)
signal mission_refused(reason: String)            ## sicht | laden | leer | unterwegs | gesperrt | kein_ziel | aus
signal danger_close(target: Vector3, who: String) ## erste Anforderung zu nah: zweite binnen confirm_time bestaetigt
signal correction_sent(forward: float, right: float)
signal salvo_fired(aim: Vector3, flight_time: float, rounds: int)
signal shell_impact(pos: Vector3, index: int)
signal salvo_complete(impacts: Array)
signal battery_ready
signal effect_requested(target: Vector3)          ## Wirkungsfeuer angefordert
signal impact_unseen(pos: Vector3)                ## Einschlag lag ausserhalb der Sicht (kein Marker)

# --- Einstellungen
@export var enabled: bool = false:
	set(v):
		enabled = v
		if not v and _up:
			raise(false)
@export var salvos_left: int = 8
@export var rounds_per_salvo: int = 3
@export var reload_time: float = 9.0             ## s nach dem letzten Einschlag
@export var prep_time: float = 2.5               ## s vom Funkspruch bis zum Abschuss
@export var flight_base: float = 6.0             ## s Flugzeit + Entfernung/flight_speed
@export var flight_speed: float = 260.0
@export var round_interval: float = 0.7
@export var dispersion: float = 6.0              ## m (Kreisstreuung pro Granate)
@export var bias_initial: float = 32.0           ## m Ablage des ersten Schusses auf ein neues Ziel
@export var bias_keep_on_remark: float = 1.0     ## Restablage nach Neu-Markieren in Zielnaehe (1 = korrigieren!)
@export var adjust_mode: bool = true             ## Einschiessen mit Einzelschuss + Wirkungsfeuer [F]
@export var adjust_dispersion: float = 3.0       ## m Streuung des Einschiess-Schusses
@export var adjust_reload: float = 3.0           ## s Pause nach einem Einschiess-Schuss
@export var effect_rounds: int = 4
@export var range_spread: float = 1.7            ## Ellipse: Laengsstreuung = dispersion * range_spread
@export var deflection_spread: float = 0.7       ## ... Querstreuung = dispersion * deflection_spread
@export var smoke_time: float = 22.0             ## s, die eine Rauchsaeule am Einschlag steht
@export var marker_time: float = 60.0            ## s, die ein Einschlagmarker im Fernglas bleibt
@export var remark_radius: float = 60.0
@export var max_range: float = 1200.0
@export var min_range: float = 35.0
@export var blast_radius: float = 9.0
@export var blast_damage: float = 240.0
@export var danger_radius: float = 40.0
@export var confirm_time: float = 6.0
@export var zoom_fovs: PackedFloat32Array = PackedFloat32Array([18.0, 8.0])
@export var rmb_raises: bool = false
@export var north: Vector3 = Vector3(0, 0, 1)    ## Weltrichtung "Nord" fuer die Marschrichtung
@export var battery_dir: Vector3 = Vector3(0, 0, 1)  ## woher die Granaten kommen (Klang)
@export var ground_mask: int = 1

## Callable(p: Vector3) -> bool: darf jetzt markiert werden (Sichtfenster)? Leer = immer.
var visibility_check: Callable
## [{ "node": Node3D, "radius": float, "name": String }] – Gefahr nahe (Warnung + Bestaetigung)
var protected: Array = []
## [{ "node": Node3D or "pos": Vector3, "radius": float, "name": String }] – Feuer wird verweigert
var no_fire: Array = []
## Schadensquelle fuer Combat.explode (Default: der Spieler – Kills zaehlen fuer ihn)
var damage_source: Node = null

var _up: bool = false
var _zoom_i: int = 0
var _fov_cur: float = 76.0
var _sens_base: float = -1.0
var _sens_set: float = -1.0
var _state: String = "ready"      ## ready | prep | flight | reload | empty
var _state_t: float = 0.0
var _target := Vector3.ZERO
var _has_target: bool = false
var _aim := Vector3.ZERO
var _bias := Vector3.ZERO
var _corr := Vector2.ZERO          ## x = weiter(+)/kuerzer(-), y = rechts(+)/links(-)
var _confirm_until: float = -1.0
var _confirm_point := Vector3.ZERO
var _impacts: Array = []
var _pending: Array = []           ## [{ "t": float, "pos": Vector3, "whistle": bool }]
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _range_txt: String = "---"
var _range_m: float = -1.0
var _look_point := Vector3.ZERO
var _look_ok: bool = false
var _rmb_held: bool = false
var _effect: bool = false          ## laufender Auftrag ist Wirkungsfeuer
var _marks: Array = []             ## [{ "pos": Vector3, "t": float, "effect": bool }]
var _smoke_mat: StandardMaterial3D

var _hud: CanvasLayer
var _mask: ColorRect
var _overlay: Control
var _lbl_top: Label
var _lbl_bot: Label
var _lbl_small: Label
var _lbl_msg: Label
var _msg_t: float = 0.0

const MASK_SHADER := """
shader_type canvas_item;
uniform float aspect = 1.777;
void fragment() {
	vec2 p = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float r = 0.36;
	float d1 = length(p - vec2(-0.2, 0.0));
	float d2 = length(p - vec2(0.2, 0.0));
	float d = min(d1, d2);
	float a = smoothstep(r - 0.02, r + 0.004, d);
	float vig = smoothstep(r * 0.55, r, d) * 0.35;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a + vig, 0.0, 1.0));
}
"""

func _ready() -> void:
	process_priority = 100   # nach dem Player (der setzt camera.fov in _process)
	_rng.seed = int(Game.arg("seed", 2030)) if Game.arg("seed", null) != null else 2030
	InputConfig.ensure_actions()
	_build_hud()
	Events.player_respawned.connect(_on_respawn)
	Events.player_died.connect(func() -> void: raise(false))

func _exit_tree() -> void:
	if _up:
		raise(false)

# ------------------------------------------------------------------ Oeffentlich

func is_up() -> bool:
	return _up

func state() -> String:
	return _state

func busy() -> bool:
	return _state != "ready"

func state_time_left() -> float:
	return maxf(_state_t, 0.0)

func last_impacts() -> Array:
	return _impacts

func target_point() -> Vector3:
	return _target

func aim_point() -> Vector3:
	return _aim

func pending_correction() -> Vector2:
	return _corr

func has_target() -> bool:
	return _has_target

func is_effect() -> bool:
	return _effect

## Einschlagmarker (Fernglas) – Level kann sie z. B. beim Zielwechsel loeschen.
func clear_marks() -> void:
	_marks.clear()

func refill(n: int) -> void:
	salvos_left += n
	if _state == "empty":
		_set_state("ready", 0.0)
		battery_ready.emit()

## Beobachter-Achsen zum Punkt p: [vorwaerts (weg vom Beobachter), rechts], beide horizontal.
func ot_basis(p: Vector3) -> Array:
	var pl := _player()
	var o: Vector3 = pl.global_position if pl != null else Vector3.ZERO
	var f := p - o
	f.y = 0.0
	if f.length() < 0.1:
		f = Vector3(0, 0, -1)
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	return [f, r]

func raise(up: bool) -> void:
	if up == _up:
		return
	var pl := _player()
	if up and (not enabled or pl == null or not bool(pl.call("is_alive"))):
		return
	_up = up
	if pl != null:
		var wr: Node3D = pl.get("weapon_root")
		if wr != null:
			wr.visible = not up
		if up:
			_sens_base = float(pl.get("_opt_sens"))
			_sens_set = _sens_base
			_fov_cur = float(pl.get_camera().fov)
		elif _sens_base > 0.0:
			pl.set("_opt_sens", _sens_base)
			_sens_base = -1.0
	_hud.visible = true
	_mask.visible = up
	_overlay.visible = up
	_lbl_top.visible = up
	_lbl_bot.visible = up
	_sfx2d("overwatch_scope_zoom", -8.0)
	binoculars_changed.emit(up)

## Markiert den Punkt unter dem Fadenkreuz (Raycast) und fordert Feuer an.
func mark_from_camera() -> bool:
	_update_look()
	if not _look_ok:
		_refuse("kein_ziel")
		return false
	return mark_point(_look_point)

## Markiert einen Weltpunkt (Bot/Level). Sichtpruefung gilt trotzdem.
func mark_point(p: Vector3) -> bool:
	if not enabled:
		_refuse("aus")
		return false
	if visibility_check.is_valid() and not bool(visibility_check.call(p)):
		_refuse("sicht")
		return false
	if not _can_fire():
		return false
	var pl := _player()
	var d: float = pl.global_position.distance_to(p) if pl != null else 0.0
	if d > max_range or d < min_range:
		_refuse("kein_ziel")
		return false
	var nf := _in_zone(p, no_fire, 0.0)
	if nf != "":
		_refuse("gesperrt")
		return false
	var near := _danger_check(p)
	if near != "" and not (_t < _confirm_until and _confirm_point.distance_to(p) < 25.0):
		_confirm_until = _t + confirm_time
		_confirm_point = p
		danger_close.emit(p, near)
		_msg("GEFAHR NAHE (%s) – erneut markieren zum Bestätigen" % near, 3.0)
		return false
	_confirm_until = -1.0
	# Ablage der Feuerstellung: neues Ziel -> neue Ablage; Nachmarkieren in Zielnaehe -> Ablage schrumpft
	if _has_target and _target.distance_to(p) < remark_radius:
		_bias *= bias_keep_on_remark
	else:
		var vis := 1.0
		var ang := _rng.randf() * TAU
		_bias = Vector3(cos(ang), 0.0, sin(ang)) * bias_initial * _rng.randf_range(0.65, 1.0) * vis
	if _has_target and _target.distance_to(p) >= remark_radius:
		_marks.clear()
	_target = p
	_has_target = true
	_corr = Vector2.ZERO
	_effect = false
	_start_mission(d)
	return true

## Korrektur vormerken (m): forward > 0 = "weiter", right > 0 = "rechts".
func add_correction(forward: float, right: float) -> void:
	_corr += Vector2(forward, right)
	_corr = _corr.clamp(Vector2(-400, -400), Vector2(400, 400))

func clear_correction() -> void:
	_corr = Vector2.ZERO

## Vorgemerkte Korrektur auf das letzte Ziel anwenden und die naechste Salve anfordern.
func send_correction() -> bool:
	if not enabled:
		_refuse("aus")
		return false
	if not _has_target:
		_refuse("kein_ziel")
		return false
	if _corr == Vector2.ZERO:
		return false
	if not _can_fire():
		return false
	var b := ot_basis(_target)
	var nt: Vector3 = _target + (b[0] as Vector3) * _corr.x + (b[1] as Vector3) * _corr.y
	nt = _ground(nt)
	if _in_zone(nt, no_fire, 0.0) != "":
		_refuse("gesperrt")
		return false
	var near := _danger_check(nt)
	if near != "" and not (_t < _confirm_until and _confirm_point.distance_to(nt) < 25.0):
		_confirm_until = _t + confirm_time
		_confirm_point = nt
		danger_close.emit(nt, near)
		_msg("GEFAHR NAHE (%s) – erneut senden zum Bestätigen" % near, 3.0)
		return false
	_confirm_until = -1.0
	var c := _corr
	_target = nt
	_corr = Vector2.ZERO
	_effect = false
	correction_sent.emit(c.x, c.y)
	var pl := _player()
	_start_mission(pl.global_position.distance_to(nt) if pl != null else 200.0, false)
	return true

## Wirkungsfeuer auf den aktuellen Zielpunkt (vorgemerkte Korrektur wird mit uebernommen).
func fire_for_effect() -> bool:
	if not enabled:
		_refuse("aus")
		return false
	if not _has_target:
		_refuse("kein_ziel")
		return false
	if not _can_fire():
		return false
	if salvos_left <= 0:
		_refuse("leer")
		return false
	var nt := _target
	if _corr != Vector2.ZERO:
		var b := ot_basis(_target)
		nt = _ground(_target + (b[0] as Vector3) * _corr.x + (b[1] as Vector3) * _corr.y)
	if _in_zone(nt, no_fire, 0.0) != "":
		_refuse("gesperrt")
		return false
	var near := _danger_check(nt)
	if near != "" and not (_t < _confirm_until and _confirm_point.distance_to(nt) < 25.0):
		_confirm_until = _t + confirm_time
		_confirm_point = nt
		danger_close.emit(nt, near)
		_msg("GEFAHR NAHE (%s) – erneut [%s] zum Bestätigen" % [near, _key_name("spotter_effect", "F")], 3.0)
		return false
	_confirm_until = -1.0
	if _corr != Vector2.ZERO:
		var c := _corr
		_corr = Vector2.ZERO
		correction_sent.emit(c.x, c.y)
	_target = nt
	_effect = true
	effect_requested.emit(nt)
	var pl := _player()
	_start_mission(pl.global_position.distance_to(nt) if pl != null else 200.0, false)
	return true

## Korrekturtext wie im Funk: "weiter 50, links 20".
static func correction_text(c: Vector2) -> String:
	var parts: Array[String] = []
	if c.x != 0.0:
		parts.append("%s %d" % ["weiter" if c.x > 0.0 else "kürzer", int(absf(c.x))])
	if c.y != 0.0:
		parts.append("%s %d" % ["rechts" if c.y > 0.0 else "links", int(absf(c.y))])
	return ", ".join(parts) if not parts.is_empty() else "keine"

## Marschrichtung (Grad, 0 = north) vom Beobachter zum Punkt.
func bearing_to(p: Vector3) -> float:
	var pl := _player()
	var o: Vector3 = pl.global_position if pl != null else Vector3.ZERO
	return _bearing(p - o)

# ------------------------------------------------------------------ Ablauf

func _can_fire() -> bool:
	match _state:
		"ready":
			return true
		"empty":
			# Einschiessen geht auch ohne Wirkungssalven (nur Wirkungsfeuer ist begrenzt)
			if adjust_mode:
				return true
			_refuse("leer")
			return false
		"reload":
			_refuse("laden")
		_:
			_refuse("unterwegs")
	return false

func _start_mission(dist: float, announce: bool = true) -> void:
	if announce:
		mission_requested.emit(_target, dist)
	_set_state("prep", prep_time)
	_aim = _target + _bias
	_impacts.clear()

func _fire_salvo() -> void:
	var single := adjust_mode and not _effect
	var n := 1 if single else (effect_rounds if adjust_mode else rounds_per_salvo)
	if not single:
		salvos_left -= 1
	var pl := _player()
	var d: float = pl.global_position.distance_to(_aim) if pl != null else 300.0
	var ft := flight_base + d / flight_speed
	salvo_fired.emit(_aim, ft, n)
	_sfx2d("overwatch_mortar_launch", -6.0)
	# Streuung: Ellipse laengs der Schussrichtung (Batterie -> Ziel), Gauss-artig (Mittel aus 2 Zufallswerten)
	var fwd := -Vector3(battery_dir.x, 0.0, battery_dir.z)
	if fwd.length() < 0.01:
		fwd = Vector3(0, 0, -1)
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var disp := adjust_dispersion if single else dispersion
	for i in n:
		var a := (_rng.randf() + _rng.randf() - 1.0) * 1.6
		var b := (_rng.randf() + _rng.randf() - 1.0) * 1.6
		var p := _aim + fwd * a * disp * (range_spread if not single else 1.0) + side * b * disp * (deflection_spread if not single else 1.0)
		_pending.append({"t": _t + ft + i * round_interval + _rng.randf_range(-0.15, 0.15), "pos": p, "whistle": false, "i": i})
	_set_state("flight", ft + n * round_interval + 0.5)

func _impact(p: Vector3, i: int) -> void:
	var g := _ground(p)
	var src: Node = damage_source if damage_source != null and is_instance_valid(damage_source) else _player()
	Combat.explode(g + Vector3(0, 0.4, 0), blast_radius, blast_damage, src, 1.7)
	if VFX.has_method("spawn_dust_cloud"):
		VFX.spawn_dust_cloud(g, 6.0)
	_impacts.append(g)
	# Nur beobachtete Einschlaege landen als Marker im Fernglas (im Sturm sieht man auf Entfernung nichts)
	var seen := not visibility_check.is_valid() or bool(visibility_check.call(g))
	if seen:
		_marks.append({"pos": g, "t": _t, "effect": _effect})
		if _marks.size() > 12:
			_marks.pop_front()
	else:
		impact_unseen.emit(g)
		_msg("EINSCHLAG NICHT BEOBACHTET – KEINE SICHT", 2.5)
	_smoke_column(g)
	shell_impact.emit(g, i)
	var pl := _player()
	if pl != null and pl.has_method("add_trauma"):
		var dd: float = pl.global_position.distance_to(g)
		if dd < 120.0:
			pl.call("add_trauma", clampf(0.5 - dd / 240.0, 0.05, 0.5))

func _set_state(s: String, t: float) -> void:
	_state = s
	_state_t = t

func _process(delta: float) -> void:
	_t += delta
	_msg_t -= delta
	_tick_state(delta)
	_tick_shells()
	var pl := _player()
	if pl == null:
		return
	if _up:
		if not bool(pl.call("is_alive")) or not enabled:
			raise(false)
		else:
			_apply_view(pl, delta)
	if rmb_raises and enabled and not bool(pl.get("external_input")):
		var held := Input.is_action_pressed("aim") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if held != _rmb_held:
			_rmb_held = held
			raise(held)
	_update_hud()

func _tick_state(delta: float) -> void:
	if _state == "ready" or _state == "empty":
		return
	_state_t -= delta
	if _state_t > 0.0:
		return
	match _state:
		"prep":
			_fire_salvo()
		"flight":
			var was_effect := _effect or not adjust_mode
			_effect = false
			salvo_complete.emit(_impacts.duplicate())
			if salvos_left <= 0 and not adjust_mode:
				_set_state("empty", 0.0)
			else:
				_set_state("reload", reload_time if was_effect else adjust_reload)
		"reload":
			_set_state("ready" if (salvos_left > 0 or adjust_mode) else "empty", 0.0)
			battery_ready.emit()

func _tick_shells() -> void:
	var i := 0
	while i < _pending.size():
		var s: Dictionary = _pending[i]
		var tt: float = s["t"]
		if not bool(s["whistle"]) and _t >= tt - 2.2:
			s["whistle"] = true
			_sfx3d("overwatch_mortar_whistle", _ground(s["pos"]) + Vector3(0, 12, 0), 2.0)
		if _t >= tt:
			_pending.remove_at(i)
			_impact(s["pos"], int(s["i"]))
			continue
		i += 1

func _apply_view(pl: Node, delta: float) -> void:
	var cam: Camera3D = pl.get_camera()
	var want: float = zoom_fovs[clampi(_zoom_i, 0, zoom_fovs.size() - 1)] if zoom_fovs.size() > 0 else 18.0
	_fov_cur = lerpf(_fov_cur, want, 1.0 - exp(-12.0 * delta))
	cam.fov = _fov_cur
	var wr: Node3D = pl.get("weapon_root")
	if wr != null:
		wr.visible = false
	var w: Node = pl.get("weapon")
	if w != null:
		w.set("_cooldown", maxf(float(w.get("_cooldown")), 0.25))
	# Maus-Empfindlichkeit an den Zoom koppeln (Einstellungen koennen sich zwischendurch aendern)
	var cur := float(pl.get("_opt_sens"))
	if absf(cur - _sens_set) > 0.0001:
		_sens_base = cur
	_sens_set = _sens_base * clampf(_fov_cur / 70.0, 0.08, 1.0)
	pl.set("_opt_sens", _sens_set)
	_update_look()

func _update_look() -> void:
	_look_ok = false
	_range_m = -1.0
	var pl := _player()
	if pl == null or not pl.is_inside_tree():
		return
	var cam: Camera3D = pl.get_camera()
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * max_range
	var q := PhysicsRayQueryParameters3D.create(from, to, ground_mask)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return
	_look_point = hit["position"]
	_range_m = from.distance_to(_look_point)
	_look_ok = _range_m >= min_range

func _on_respawn() -> void:
	raise(false)
	_corr = Vector2.ZERO
	_confirm_until = -1.0

## Dunkle Rauchsaeule am Einschlag (im Schnee gut zu sehen, steht smoke_time Sekunden).
func _smoke_column(g: Vector3) -> void:
	if not is_inside_tree():
		return
	var host := get_tree().current_scene if get_tree().current_scene != null else self
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 6.0
	p.preprocess = 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 30, 30))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(1.2, 0.6, 0.4)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.scale_min = 2.0
	pm.scale_max = 4.5
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	var st := CurveTexture.new()
	st.curve = sc
	pm.scale_curve = st
	var gr := Gradient.new()
	gr.set_color(0, Color(0.16, 0.15, 0.14, 0.75))
	gr.set_color(1, Color(0.4, 0.4, 0.42, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = gr
	pm.color_ramp = gt
	p.process_material = pm
	if _smoke_mat == null:
		_smoke_mat = StandardMaterial3D.new()
		_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_smoke_mat.vertex_color_use_as_albedo = true
		_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in 32:
			for x in 32:
				var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.5)))
		_smoke_mat.albedo_texture = ImageTexture.create_from_image(img)
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	q.material = _smoke_mat
	p.draw_pass_1 = q
	host.add_child(p)
	p.global_position = g + Vector3(0, 0.5, 0)
	p.emitting = true
	var tw := p.create_tween()
	tw.tween_interval(maxf(smoke_time - 6.0, 1.0))
	tw.tween_callback(func() -> void: p.emitting = false)
	tw.tween_interval(6.5)
	tw.tween_callback(p.queue_free)

# ------------------------------------------------------------------ Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var pl := _player()
	if pl == null or bool(pl.get("external_input")):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if InputMap.has_action("binoculars") and event.is_action_pressed("binoculars") and not event.is_echo():
		raise(not _up)
		get_viewport().set_input_as_handled()
		return
	if not _up:
		return
	if event.is_action_pressed("fire") and not event.is_echo():
		if _corr != Vector2.ZERO:
			send_correction()
		else:
			mark_from_camera()
		return
	if adjust_mode and InputMap.has_action("spotter_effect") and event.is_action_pressed("spotter_effect") and not event.is_echo():
		fire_for_effect()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("aim") and not event.is_echo() and not rmb_raises:
		_zoom_i = (_zoom_i + 1) % maxi(zoom_fovs.size(), 1)
		_sfx2d("overwatch_scope_zoom", -10.0)
		return
	var step := 50.0 if Input.is_key_pressed(KEY_SHIFT) else 10.0
	for pair: Array in [["spotter_far", Vector2(step, 0)], ["spotter_near", Vector2(-step, 0)], ["spotter_left", Vector2(0, -step)], ["spotter_right", Vector2(0, step)]]:
		if InputMap.has_action(pair[0]) and event.is_action_pressed(pair[0]):
			var v: Vector2 = pair[1]
			add_correction(v.x, v.y)
			get_viewport().set_input_as_handled()
			return

# ------------------------------------------------------------------ Hilfen

func _player() -> Node3D:
	if not is_inside_tree():
		return null
	return get_tree().get_first_node_in_group("player") as Node3D

func _bearing(v: Vector3) -> float:
	var n := Vector2(north.x, north.z).normalized()
	var d := Vector2(v.x, v.z)
	if d.length() < 0.001:
		return 0.0
	d = d.normalized()
	# Uhrzeigersinn von Nord (von oben gesehen, rechts = Ost)
	var ang := atan2(n.x * d.y - n.y * d.x, n.dot(d))
	var deg := rad_to_deg(-ang)
	return fposmod(deg, 360.0)

func _ground(p: Vector3) -> Vector3:
	if not is_inside_tree():
		return p
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 120, 0), p - Vector3(0, 200, 0), ground_mask)
	var hit := space.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else p

func _zone_pos(z: Dictionary) -> Variant:
	if z.has("node"):
		var n: Variant = z["node"]
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
			return (n as Node3D).global_position
		return null
	return z.get("pos", null)

func _in_zone(p: Vector3, zones: Array, extra: float) -> String:
	for z: Dictionary in zones:
		var zp: Variant = _zone_pos(z)
		if zp == null:
			continue
		var d := Vector2(p.x - (zp as Vector3).x, p.z - (zp as Vector3).z).length()
		if d < float(z.get("radius", 30.0)) + extra:
			return str(z.get("name", "Zone"))
	return ""

func _danger_check(p: Vector3) -> String:
	var pl := _player()
	if pl != null:
		var d := Vector2(p.x - pl.global_position.x, p.z - pl.global_position.z).length()
		if d < danger_radius + _bias.length() * 0.5:
			return "eigene Position"
	return _in_zone(p, protected, dispersion)

func _refuse(reason: String) -> void:
	mission_refused.emit(reason)
	match reason:
		"sicht":
			_msg("KEINE SICHT – auf ein Sichtfenster warten", 2.0)
		"laden":
			_msg("MÖRSER LADEN – noch %d s" % ceili(_state_t), 2.0)
		"leer":
			_msg("KEINE SALVEN MEHR", 2.0)
		"unterwegs":
			_msg("SALVE UNTERWEGS", 1.5)
		"gesperrt":
			_msg("FEUER VERWEIGERT – Sperrzone", 2.5)
		"kein_ziel":
			_msg("KEIN ZIEL IM ENTFERNUNGSMESSER", 1.5)

func _msg(t: String, dur: float) -> void:
	if _lbl_msg != null:
		_lbl_msg.text = t
	_msg_t = dur

func _sfx2d(nm: String, vol: float) -> void:
	var st := Sfx.get_stream(nm)
	if st == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = vol
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func _sfx3d(nm: String, pos: Vector3, vol: float) -> void:
	var st := Sfx.get_stream(nm)
	if st == null or not is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = vol
	p.unit_size = 30.0
	p.max_distance = 900.0
	var host := get_tree().current_scene if get_tree().current_scene != null else self
	host.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)

func _key_name(action: String, fallback: String) -> String:
	if not InputMap.has_action(action):
		return fallback
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return fallback

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 6
	add_child(_hud)
	_mask = ColorRect.new()
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_mask.material = sm
	_mask.visible = false
	_hud.add_child(_mask)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_reticle)
	_overlay.visible = false
	_hud.add_child(_overlay)
	_lbl_top = _make_label(Vector2(0.5, 0.27), 22, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_bot = _make_label(Vector2(0.5, 0.87), 18, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_small = _make_label(Vector2(0.5, 0.93), 15, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_msg = _make_label(Vector2(0.5, 0.34), 20, HORIZONTAL_ALIGNMENT_CENTER)
	_lbl_msg.modulate = Color(1.0, 0.75, 0.35)
	_lbl_top.visible = false
	_lbl_bot.visible = false

func _make_label(anchor: Vector2, size: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = anchor.y
	l.anchor_bottom = anchor.y
	l.offset_top = -size
	l.offset_bottom = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.modulate = Color(0.85, 1.0, 0.8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(l)
	return l

func _state_text() -> String:
	match _state:
		"ready":
			return "BEREIT"
		"prep":
			return "WIRKUNG – FEUERAUFTRAG…" if _effect else ("EINSCHIESSEN…" if adjust_mode else "FEUERAUFTRAG…")
		"flight":
			return "WIRKUNG UNTERWEGS" if _effect else ("SCHUSS UNTERWEGS" if adjust_mode else "SALVE UNTERWEGS")
		"reload":
			return "LADEN %d s" % ceili(_state_t)
		"empty":
			return "LEER"
	return _state

func _update_hud() -> void:
	if _hud == null:
		return
	var vp := _hud.get_viewport()
	if vp != null and _mask.visible:
		var sz := vp.get_visible_rect().size
		(_mask.material as ShaderMaterial).set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	_lbl_msg.visible = _msg_t > 0.0
	if not enabled:
		_lbl_small.visible = false
		return
	_lbl_small.visible = true
	var key := _key_name("binoculars", "B")
	if not _up:
		_lbl_small.text = "[%s] Fernglas   ·   Mörser: %s   ·   %s %d" % [key, _state_text(), "Wirkungssalven" if adjust_mode else "Salven", maxi(salvos_left, 0)]
		return
	var pl := _player()
	var brg := 0.0
	if pl != null:
		var cam: Camera3D = pl.get_camera()
		brg = _bearing(-cam.global_transform.basis.z)
	var vis_ok := true
	if _look_ok and visibility_check.is_valid():
		vis_ok = bool(visibility_check.call(_look_point))
	var rng_txt := ("%d m" % roundi(_range_m)) if (_look_ok and vis_ok) else "---"
	_lbl_top.text = "ENTF %s     RICHTUNG %03d°  (%04d ‰)" % [rng_txt, roundi(brg) % 360, roundi(brg / 360.0 * 6400.0) % 6400]
	var line := "MÖRSER %s   ·   %s %d" % [_state_text(), "WIRKUNGSSALVEN" if adjust_mode else "SALVEN", maxi(salvos_left, 0)]
	if not vis_ok:
		line += "   ·   KEINE SICHT"
	var fk := _key_name("spotter_effect", "F")
	if _corr != Vector2.ZERO:
		line += "\nKORREKTUR: %s  –  [LMB] Einschießen  ·  [%s] Wirkung" % [correction_text(_corr), fk] if adjust_mode else "\nKORREKTUR: %s  –  [LMB] senden" % correction_text(_corr)
	elif adjust_mode and _has_target and not _marks.is_empty() and _state == "ready":
		line += "\nEinschlag beobachten · [Pfeile] korrigieren · liegt er am Ziel: [%s] WIRKUNG" % fk
	elif adjust_mode and not _has_target:
		line += "\nZiel ins Fadenkreuz · [LMB] Einschießen"
	_lbl_bot.text = line
	if adjust_mode:
		_lbl_small.text = "[LMB] Einschießen   [Pfeile] Korrektur 10 m (Shift 50)   [%s] Wirkung   [RMB] Zoom   [%s] absetzen" % [fk, key]
	else:
		_lbl_small.text = "[LMB] Ziel markieren   [RMB] Zoom   [Pfeile] Korrektur (Shift: 50 m)   [%s] absetzen" % key
	_overlay.queue_redraw()

func _draw_reticle() -> void:
	var sz := _overlay.size
	var c := sz * 0.5
	var col := Color(0.1, 0.1, 0.1, 0.85)
	var col2 := Color(0.85, 1.0, 0.8, 0.8)
	# Strichplatte: Kreuz mit Teilstrichen (je 10 ‰ bei der aktuellen Brennweite)
	var px_per_mil := sz.y / deg_to_rad(maxf(_fov_cur, 1.0)) / 1000.0
	_overlay.draw_line(c - Vector2(sz.y * 0.3, 0), c + Vector2(sz.y * 0.3, 0), col, 1.5)
	_overlay.draw_line(c - Vector2(0, sz.y * 0.05), c + Vector2(0, sz.y * 0.25), col, 1.5)
	for i in range(-10, 11):
		if i == 0:
			continue
		var x := i * 10.0 * px_per_mil
		if absf(x) > sz.y * 0.3:
			continue
		var h := 8.0 if i % 5 == 0 else 4.0
		_overlay.draw_line(c + Vector2(x, -h), c + Vector2(x, h), col, 1.2)
	for i in range(1, 6):
		var y := i * 10.0 * px_per_mil
		if y > sz.y * 0.25:
			break
		_overlay.draw_line(c + Vector2(-5, y), c + Vector2(5, y), col, 1.2)
	_overlay.draw_arc(c, 3.0, 0.0, TAU, 12, col2, 1.0)
	if _state == "flight" or _state == "prep":
		_overlay.draw_arc(c, 14.0, 0.0, TAU * clampf(1.0 - _state_t / 12.0, 0.05, 1.0), 24, Color(1.0, 0.7, 0.3, 0.9), 2.0)
	_draw_marks()

## Einschlagmarker, markierter Zielpunkt und "Geist" der vorgemerkten Korrektur (projiziert).
func _draw_marks() -> void:
	var pl := _player()
	if pl == null:
		return
	var cam: Camera3D = pl.get_camera()
	if cam == null:
		return
	var vp_sz := _overlay.get_viewport_rect().size
	var scale_v := _overlay.size / vp_sz if vp_sz.x > 0.0 else Vector2.ONE
	var font := ThemeDB.fallback_font
	var last: Variant = null
	var i := 0
	while i < _marks.size():
		var m: Dictionary = _marks[i]
		if _t - float(m["t"]) > marker_time:
			_marks.remove_at(i)
			continue
		i += 1
		var wp: Vector3 = m["pos"]
		last = wp
		if cam.is_position_behind(wp):
			continue
		var sp := cam.unproject_position(wp) * scale_v
		var fresh := clampf(1.0 - (_t - float(m["t"])) / marker_time, 0.25, 1.0)
		var col := Color(1.0, 0.45, 0.2, 0.95 * fresh) if bool(m["effect"]) else Color(1.0, 0.85, 0.3, 0.95 * fresh)
		_overlay.draw_line(sp + Vector2(-7, -7), sp + Vector2(7, 7), col, 2.0)
		_overlay.draw_line(sp + Vector2(-7, 7), sp + Vector2(7, -7), col, 2.0)
	if _has_target and not cam.is_position_behind(_target):
		var tp := cam.unproject_position(_target) * scale_v
		var tc := Color(0.6, 1.0, 0.7, 0.8)
		var pts := PackedVector2Array([tp + Vector2(0, -9), tp + Vector2(9, 0), tp + Vector2(0, 9), tp + Vector2(-9, 0), tp + Vector2(0, -9)])
		_overlay.draw_polyline(pts, tc, 1.5)
		if font != null:
			_overlay.draw_string(font, tp + Vector2(12, -10), "ZIELPUNKT", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)
	if _corr != Vector2.ZERO and last != null:
		var b := ot_basis(_target)
		var gp: Vector3 = (last as Vector3) + (b[0] as Vector3) * _corr.x + (b[1] as Vector3) * _corr.y
		if not cam.is_position_behind(gp) and not cam.is_position_behind(last as Vector3):
			var gs := cam.unproject_position(gp) * scale_v
			var ls := cam.unproject_position(last as Vector3) * scale_v
			var gc := Color(0.55, 0.9, 1.0, 0.9)
			_overlay.draw_dashed_line(ls, gs, gc, 1.5, 6.0)
			_overlay.draw_arc(gs, 10.0, 0.0, TAU, 20, gc, 2.0)
			if font != null:
				_overlay.draw_string(font, gs + Vector2(13, 4), correction_text(_corr), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, gc)
