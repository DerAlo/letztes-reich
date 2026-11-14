extends Weapon
## Zielfernrohr-Gewehr (G28-Stil, "overwatch"): eigenes Modell mit Zielfernrohr, echte Geschosse mit
## Ballistik (Schwerkraft + quadratischer Luftwiderstand relativ zur Luft -> Wind-Abdrift), verstellbarer
## Nullpunkt (Bild auf/ab bzw. Alt+Mausrad, 100..600 m), zwei Zoomstufen (Mausrad im Anschlag),
## Zielfernrohr-Overlay mit Absehen (Duplex + Strichplatte + BDC-Marken mit Wind-Punkten), Wind- und
## Entfernungsanzeige, Atemleiste, Schwanken + Atem anhalten (Shift im Anschlag, begrenzt), Geschossspur
## entlang der simulierten Bahn ("Trace"), satte Treffer-Rueckmeldung und Geschoss-Kamera (ab BULLET_CAM_MIN
## vorhergesagter Einschlagentfernung immer, mit echtem 7,62-mm-Geschossmodell, Drall und Luftverwirbelung).
## Ein Ballistik-Modell fuer alles: Flug (_physics_process), Haltemarken (drop_mil/drift_mil),
## Geschoss-Kamera (_predict_impact_dist), Zielhilfe und Bot-Loeser (solve_aim) nutzen ballistic_step().
## Wind liefert das Level ueber sniper_wind() -> Vector3 (m/s, Weltkoordinaten), sonst windstill.
## Alles bleibt in dieser Datei: weapon.gd/player.gd werden nicht veraendert.
## Ziele in der Gruppe "friendly" bekommen take_damage (das Ziel meldet den Eigenbeschuss selbst),
## aber weder Hitmarker noch Treffer-Bestaetigung.

## Spielgefuehl statt Realismus (Nutzerwunsch): langsameres Geschoss, staerkere Schwerkraft und verstaerkter Wind,
## damit Fall, Flugzeit und Abdrift schon auf 150-250 m deutlich sichtbar sind.
const GRAVITY := Vector3(0.0, -8.0, 0.0)   # halbiert (Nutzerwunsch: Fall war zu krass)
const WIND_GAIN := 2.5
const MODEL_SCRIPT := "res://game/weapons/g28_model.gd"
const OVERLAY_LAYER := 3            # ueber dem Viewmodel (1), unter dem HUD (5)
## Quadratischer Luftwiderstand a = -k*|v-w|*(v-w) (1/m); Wind wirkt mit WIND_GAIN verstaerkt.
## 380 m/s, g=8: Fall etwa halb so stark wie vorher (g=16); Haltemarken werden aus GRAVITY berechnet.
const DRAG_K := 0.0009
const SIM_STEP := 0.005             # s, feste RK2-Teilschritte (Flug und Vorhersage identisch)
const ZERO_STEPS: Array[float] = [100.0, 150.0, 200.0, 250.0, 300.0, 400.0, 500.0, 600.0]
const TAB_STEP := 25.0              # m, Tabellen fuer Haltemarken
const TAB_MAX := 1000.0
const TRAIL_TAIL := 110.0           # m sichtbarer Schweif hinter dem Geschoss
const TRAIL_FADE := 0.6             # s Ausblenden nach dem Einschlag
const TRAIL_PX := 10.0              # Bildschirmbreite der Spur (px), unabhaengig von Entfernung/Zoom
## Geschoss-Kamera: ab dieser vorhergesagten Einschlagentfernung (m) bei jedem Schuss, darunter nie.
const BULLET_CAM_MIN := 180.0
const CAM_FLIGHT_REAL := 3.2        # s Echtzeit fuer den Flug; die Zeitlupe richtet sich nach der Flugzeit
const CAM_SCALE_MIN := 0.1
const CAM_SCALE_MAX := 0.38
const CAM_HOLD_HIT := 1.1           # s Echtzeit nach dem Einschlag (Treffer ansehen)
const CAM_HOLD_MISS := 0.25
const CAM_MAX_REAL := 9.0           # s Sicherheitsgrenze
const CAM_BACK := 0.2               # m hinter dem Geschoss
const CAM_SIDE := 0.1
const CAM_UP := 0.05
const CAM_AIM := 0.12               # m Blickpunkt vor dem Geschoss (Geschoss im Profil, Ziel noch im Bild)
## 7,62 x 51 Matchgeschoss (175 gr, Boattail): 31,2 mm lang, 7,82 mm Kaliber; fuer die Kamera leicht vergroessert.
const BULLET_LEN := 0.0312
const BULLET_R := 0.00391
const BULLET_VIS_SCALE := 2.0
const BULLET_SPIN := 9.0            # rad/s Echtzeit: sichtbarer Drall in der Zeitlupe
const WAKE_LEN := 0.5

const WAKE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.012;
void fragment() {
	// Nachlauf hinter dem Geschoss: verwirbelte Luft, Hintergrund flimmernd versetzt, kaum eingefaerbt.
	// UV.y = 0 am Geschossboden, 1 am Ende des Nachlaufs.
	float along = clamp(UV.y, 0.0, 1.0);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float swirl = sin(UV.x * 37.7 + TIME * 24.0 - along * 30.0) * cos(UV.x * 18.8 - TIME * 15.0 + along * 11.0);
	float k = facing * (1.0 - along) * (1.0 - along);
	vec2 off = vec2(swirl, -0.7 * swirl) * strength * k;
	vec3 bg = textureLod(screen_tex, SCREEN_UV + off, 0.0).rgb;
	ALBEDO = bg * (1.0 + 0.05 * k);
	ALPHA = clamp(k * 1.5, 0.0, 1.0);
}
"""

static var _bullet_mesh_res: ArrayMesh = null
static var _bullet_mat_res: StandardMaterial3D = null
static var _wake_mat_res: ShaderMaterial = null

const TRAIL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.008;
uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.22, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.45, 0.05, 1.0);
void fragment() {
	// Luftverwirbelung: Hintergrund flimmernd versetzt + leichte Aufhellung im Kern
	float across = UV.y * 2.0 - 1.0;
	float core = clamp(1.0 - across * across, 0.0, 1.0);
	vec2 wob = vec2(sin(UV.x * 9.0 - TIME * 38.0 + across * 3.0), cos(UV.x * 7.0 + TIME * 31.0));
	vec3 bg = textureLod(screen_tex, SCREEN_UV + wob * strength * core, 0.0).rgb;
	float a = COLOR.a;
	// Leuchtender orangefarbener Kern (auch vor hellem Himmel/Kuehlturm sichtbar), Rand bleibt Luftflimmern
	float hot = core * core * core;
	ALBEDO = mix(bg, tint.rgb, 0.6 * core * a) + hot_color.rgb * hot * a * 1.6;
	ALPHA = clamp(a * (0.35 + 0.65 * core), 0.0, 1.0);
}
"""

@export_group("Zielfernrohr")
@export var muzzle_velocity: float = 380.0
@export var zero_range: float = 100.0
@export var zoom_fovs: PackedFloat32Array = PackedFloat32Array([12.5, 6.0])
@export var zoom_labels: PackedStringArray = PackedStringArray(["6×", "12×"])
@export var breath_max: float = 4.5            # s Atem anhalten
@export var breath_recover: float = 0.55       # s Atem pro s zurueck
@export var sway_stand: float = 0.34           # Grad
@export var sway_crouch: float = 0.2
@export var sway_prone: float = 0.1
@export var bullet_cam: bool = true

var zoom_index: int = 0
var breath: float = 4.5
var holding_breath: bool = false
var scoped_amount: float = 0.0                 # 0..1 Overlay sichtbar

var _projectiles: Array = []                   # {pos, vel, t, dist, origin, wind, hist, trail, vis_off}
var _fading: Array = []                        # beendete Geschosse, deren Spur noch ausblendet
var _trail_mat: ShaderMaterial
var _zero_angle: float = 0.0                   # rad, Laufueberhoehung fuer zero_range
var _drop_tab: PackedFloat32Array = PackedFloat32Array()    # mil unter der Visierlinie je TAB_STEP
var _drift_tab: PackedFloat32Array = PackedFloat32Array()   # mil Abdrift je 1 m/s Querwind je TAB_STEP
var _tof_tab: PackedFloat32Array = PackedFloat32Array()     # s Flugzeit je TAB_STEP
var _zero_flash: float = 0.0                   # s Hervorhebung nach Nullpunkt-Verstellung
var _level_ref: Node = null
var _overlay_layer: CanvasLayer
var _mask: ColorRect
var _mask_mat: ShaderMaterial
var _reticle: Control
var _sway_t: float = 0.0
var _sway_off: Vector2 = Vector2.ZERO          # Grad (x = yaw, y = pitch)
var _need_release: bool = false              # Atem automatisch beendet -> erst Taste loslassen
var _exhausted: float = 0.0                    # s Zittern nach leerer Lunge
var _heart_t: float = 0.0
var _range_m: float = -1.0
var _range_timer: float = 0.0
var _model_node: Node3D
var _cam_node: Camera3D = null
var _cam_proj: Dictionary = {}
var _cam_hold: float = 0.0
var _cam_prev_scale: float = 1.0
var _cam_cooldown: float = 0.0
var _bullet_vis: Node3D = null                 # Geschossmodell + Nachlauf (nur in der Geschoss-Kamera)
var _bullet_mi: MeshInstance3D = null
var _bullet_spin: float = 0.0
var _cam_real_t: float = 0.0                   # s Echtzeit seit Start der Geschoss-Kamera
var _cam_hold_t: float = 0.0                   # s Echtzeit seit dem Einschlag
var _cam_count: int = 0
var _cam_shot_i: int = 0
var _noise := FastNoiseLite.new()
## Treffpunkt-Vorhersage beim Luftanhalten (Nutzerwunsch: weniger Frust): gleiche Ballistik wie der Flug
var pred_valid: bool = false
var pred_pos: Vector3 = Vector3.ZERO
var pred_enemy: bool = false
var _pred_timer: float = 0.0

func _ready() -> void:
	breath = breath_max
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.35
	_noise.seed = 4711
	super._ready()
	ads_fov = zoom_fovs[0]
	_rebuild_ballistics()
	_build_overlay()

func _exit_tree() -> void:
	_end_bullet_cam()
	for p in _projectiles + _fading:
		var tr: Node = (p as Dictionary).get("trail")
		if is_instance_valid(tr):
			tr.queue_free()
	_projectiles.clear()
	_fading.clear()

# ---------------------------------------------------------------- Modell

func _build_model() -> void:
	_get_mats()
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	_pivot.add_child(muzzle)
	var model: Node3D = null
	if ResourceLoader.exists(MODEL_SCRIPT):
		var scr: Script = load(MODEL_SCRIPT) as Script
		if scr != null:
			model = scr.call("build") as Node3D
	if model == null:
		model = GunModels.build_g36c()
	model.name = "Model"
	_pivot.add_child(model)
	_model_node = model
	var xf := Transform3D(Basis.from_euler(model_rot_deg * (PI / 180.0)).scaled(Vector3.ONE * model_scale), model_offset)
	model.transform = xf
	_apply_view_layer(model, null)
	if model.has_meta("muzzle"):
		muzzle_pos = xf * (model.get_meta("muzzle") as Vector3)
	if model.has_meta("eject") and eject_pos == Vector3.ZERO:
		eject_pos = xf * (model.get_meta("eject") as Vector3)
	if model.has_meta("scope_eye"):
		# Zielfernrohr-Achse auf die Kamera-Achse, Augenabstand ads_eye_dist
		var se: Vector3 = xf * (model.get_meta("scope_eye") as Vector3)
		ads_pos = Vector3(-se.x, -se.y, -ads_eye_dist - se.z)
		_sight_r = se
		_sight_f = se + Vector3(0, 0, -0.3)
	_mag_part = _make_part(model.find_child("Magazine", true, false) as Node3D, Vector3(0.0, -1.0, -0.15))
	_bolt_part = _make_part(model.find_child("Charging_Handle", true, false) as Node3D, Vector3.BACK)
	muzzle.position = muzzle_pos

# ---------------------------------------------------------------- Zoom / Eingabe

## Mausrad im Anschlag: Zoomstufe wechseln (dir > 0 = naeher).
func scope_wheel(dir: int) -> void:
	set_zoom(zoom_index + (1 if dir > 0 else -1))

func set_zoom(idx: int) -> void:
	var n: int = clampi(idx, 0, zoom_fovs.size() - 1)
	if n == zoom_index:
		return
	zoom_index = n
	ads_fov = zoom_fovs[n]
	_play("overwatch_scope_zoom", 0.03)

func is_scoped() -> bool:
	return scoped_amount > 0.5

## Hoehenverstellung: Nullpunkt eine Stufe weiter (dir > 0) bzw. zurueck (ZERO_STEPS).
func adjust_zero(dir: int) -> void:
	var idx: int = 0
	var best: float = INF
	for i in ZERO_STEPS.size():
		var dd: float = absf(ZERO_STEPS[i] - zero_range)
		if dd < best:
			best = dd
			idx = i
	set_zero(ZERO_STEPS[clampi(idx + (1 if dir > 0 else -1), 0, ZERO_STEPS.size() - 1)])

func set_zero(r: float) -> void:
	r = clampf(r, ZERO_STEPS[0], ZERO_STEPS[ZERO_STEPS.size() - 1])
	if is_equal_approx(r, zero_range):
		return
	zero_range = r
	_rebuild_ballistics()
	_zero_flash = 1.6
	_play("overwatch_scope_zoom", 0.06)

func _player_ads() -> float:
	if owner_player == null:
		return 0.0
	return float(owner_player.get("_ads"))

func _unhandled_input(event: InputEvent) -> void:
	if owner_player == null or not visible or owner_player.external_input:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	# Hoehenverstellung (auch ohne Anschlag): Bild auf / Bild ab
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var kc: Key = (event as InputEventKey).physical_keycode
		if kc == KEY_PAGEUP or kc == KEY_PAGEDOWN:
			adjust_zero(1 if kc == KEY_PAGEUP else -1)
			get_viewport().set_input_as_handled()
			return
	if _player_ads() < 0.5:
		return
	# Alt + Mausrad im Anschlag: Nullpunkt statt Zoom
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).alt_pressed:
		var ab: int = (event as InputEventMouseButton).button_index
		if ab == MOUSE_BUTTON_WHEEL_UP or ab == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_zero(1 if ab == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion:
		# Feinere Maus im Zielfernrohr (relativ zum Sichtfeld); der Player liest _mouse_accum im _process.
		var k: float = clampf(owner_player.camera.fov / 52.0, 0.06, 1.0)
		var acc: Vector2 = owner_player.get("_mouse_accum")
		owner_player.set("_mouse_accum", acc + (event as InputEventMouseMotion).relative * k)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var bi: int = (event as InputEventMouseButton).button_index
		if bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_DOWN:
			scope_wheel(1 if bi == MOUSE_BUTTON_WHEEL_UP else -1)
			get_viewport().set_input_as_handled()

func set_active(on: bool) -> void:
	super.set_active(on)
	if not on:
		_end_bullet_cam()
		_set_breath(false)
		scoped_amount = 0.0
		if _overlay_layer:
			_overlay_layer.visible = false

# ---------------------------------------------------------------- Logik

func tick(delta: float) -> void:
	super.tick(delta)
	_cam_cooldown = maxf(0.0, _cam_cooldown - delta)
	_zero_flash = maxf(0.0, _zero_flash - delta)
	var ads: float = _player_ads() if visible else 0.0
	var key_held: bool = owner_player != null and bool(owner_player.get("_in_sprint"))
	if not key_held:
		_need_release = false   # Taste losgelassen -> Atem anhalten wieder moeglich
	var want_hold: bool = ads > 0.85 and key_held and not _need_release and breath > 0.5
	if want_hold != holding_breath:
		_set_breath(want_hold)
	if holding_breath:
		breath -= delta
		_heart_t -= delta
		if _heart_t <= 0.0:
			_heart_t = 0.95
			_play("overwatch_heartbeat", 0.02)
		if breath <= 0.0:
			breath = 0.0
			_need_release = true   # Luft alle: sauber zurueck in den Normalmodus, neu anhalten erst nach Loslassen
			_set_breath(false)
	else:
		_exhausted = maxf(0.0, _exhausted - delta)
		breath = minf(breath_max, breath + breath_recover * delta * (0.5 if _exhausted > 0.0 else 1.0))
	# Treffpunkt-Vorhersage: nur bei angehaltenem Atem im Zielfernrohr, ~20x pro Sekunde
	if holding_breath and scoped_amount > 0.5 and owner_player != null:
		_pred_timer -= delta
		if _pred_timer <= 0.0:
			_pred_timer = 0.05
			_update_prediction(owner_player.camera)
	else:
		pred_valid = false
		_pred_timer = 0.0
	# Entfernungsmesser (Mitte des Absehens), 8x pro Sekunde
	_range_timer -= delta
	if _range_timer <= 0.0 and scoped_amount > 0.1 and owner_player != null:
		_range_timer = 0.12
		var cam: Camera3D = owner_player.camera
		var from: Vector3 = cam.global_position
		var q := PhysicsRayQueryParameters3D.create(from, from - cam.global_basis.z * 1200.0, 1 | 4, [owner_player.get_rid()])
		var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		_range_m = from.distance_to(r.position) if not r.is_empty() else -1.0

func _set_breath(on: bool) -> void:
	if on == holding_breath:
		return
	holding_breath = on
	if on:
		_heart_t = 0.5
		_play("overwatch_breath_in", 0.04)
	elif scoped_amount > 0.3:
		_play("overwatch_breath_out", 0.04)

## Schwanken (Grad) aus Haltung, Bewegung, Atem.
func _update_sway(delta: float, s: Dictionary, ads: float) -> void:
	var crouch: float = float(s.get("crouch", 0.0))
	var prone: float = float(s.get("prone", 0.0))
	var amp: float = lerpf(lerpf(sway_stand, sway_crouch, crouch), sway_prone, prone)
	var vl: Vector3 = s.get("vel_local", Vector3.ZERO)
	amp *= 1.0 + clampf(Vector2(vl.x, vl.z).length() / 2.5, 0.0, 1.0) * 2.2
	var speed: float = 1.0
	if holding_breath:
		amp *= 0.1
		speed = 0.5
	elif _exhausted > 0.0:
		amp *= 2.0
		speed = 2.4
	_sway_t += delta * speed
	var t: float = _sway_t
	# Liegende Acht + Rauschen
	var target := Vector2(sin(t * 0.9) * 0.8 + _noise.get_noise_2d(t, 3.0) * 0.6,
			sin(t * 1.8 + 0.4) * 0.45 + _noise.get_noise_2d(t, 77.0) * 0.6) * amp
	if _exhausted > 0.0:
		target += Vector2(_noise.get_noise_2d(t * 9.0, 11.0), _noise.get_noise_2d(t * 9.0, 41.0)) * 0.12
	var k: float = smoothstep(0.55, 1.0, ads)
	_sway_off = _sway_off.lerp(target * k, 1.0 - exp(-6.0 * delta))

func animate(delta: float, s: Dictionary) -> void:
	super.animate(delta, s)
	var ads: float = float(s.get("ads", 0.0))
	_update_sway(delta, s, ads)
	if owner_player != null and visible:
		# Der Player setzt die Kopfrotation jeden Frame neu (vor animate) -> hier nur addieren.
		owner_player.head.rotation_degrees += Vector3(_sway_off.y, _sway_off.x, 0.0)
	var target_scope: float = smoothstep(0.82, 0.97, ads) if visible and _cam_node == null else 0.0
	scoped_amount = target_scope
	# Waehrend der Killcam kein Gewehr im Bild (sonst "fliegt" es ueber der Kugelkamera mit)
	var show_model: bool = scoped_amount < 0.6 and _cam_node == null
	if _model_node:
		_model_node.visible = show_model
	if _muzzle_fx:
		_muzzle_fx.visible = show_model
	# Im Zielfernrohr keine Arme/Stützhand im Bild
	if _arms:
		_arms.visible = show_model
	_update_overlay()

# ---------------------------------------------------------------- Schuss

func _shoot(cam: Camera3D, spread_deg: float) -> void:
	var origin: Vector3 = cam.global_position
	var b: Basis = cam.global_basis
	var dir: Vector3 = -b.z
	if spread_deg > 0.0:
		var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a: float = randf() * TAU
		dir = (dir + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	# Nullpunkt: Lauf um _zero_angle ueberhoeht (aus derselben Ballistik berechnet), damit das Geschoss
	# auf zero_range die Visierlinie kreuzt. Ursprung = Kamera = Visierlinie des Zielfernrohrs.
	dir = launch_dir(dir, b.y)
	var vel0: Vector3 = dir * muzzle_velocity
	var wind: Vector3 = wind_vector()
	# Spur-Ursprung: im Zielfernrohr exakt auf der Visierlinie; aus der Huefte an der sichtbaren
	# Muendung beginnend und auf den ersten Metern in die echte Bahn uebergehend.
	var vis_off := Vector3.ZERO
	if scoped_amount < 0.5:
		vis_off = _tracer_start(cam) - origin
	var hist := PackedVector3Array([origin])
	var p := {"pos": origin, "vel": vel0, "t": 0.0, "dist": 0.0, "origin": origin, "wind": wind,
		"hist": hist, "trail": _make_trail(), "vis_off": vis_off, "fade": 0.0}
	_projectiles.append(p)
	# Geschoss-Kamera bei jedem weiten Schuss (vorhergesagter Einschlag >= BULLET_CAM_MIN), nie bei nahen.
	# Autopilot nur mit --bulletcam (Test/Screenshots).
	if bullet_cam and _cam_node == null and not Game.arg("nobulletcam", false) \
			and (not Game.arg("autopilot", false) or Game.arg("bulletcam", false)):
		var hit_d: float = _predict_impact_dist(origin, vel0, wind)
		if hit_d >= BULLET_CAM_MIN:
			_start_bullet_cam(p, time_of_flight(hit_d))

func _physics_process(delta: float) -> void:
	if _projectiles.is_empty():
		_tick_bullet_cam_hold(delta)
		return
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	for i in range(_projectiles.size() - 1, -1, -1):
		var p: Dictionary = _projectiles[i]
		var pos: Vector3 = p.pos
		var vel: Vector3 = p.vel
		var st: Array = ballistic_step(pos, vel, p.wind, delta)
		var npos: Vector3 = st[0]
		var q := PhysicsRayQueryParameters3D.create(pos, npos, HIT_MASK, exclude)
		q.collide_with_areas = true
		var res: Dictionary = space.intersect_ray(q)
		p.t = float(p.t) + delta
		var hist: PackedVector3Array = p.hist
		if not res.is_empty():
			p.pos = res.position
			hist.append(res.position)
			p.hist = hist
			_impact(res, vel.normalized(), (res.position as Vector3).distance_to(p.origin))
			_finish_projectile(p, true)
			_projectiles.remove_at(i)
			continue
		p.vel = st[1]
		p.pos = npos
		p.dist = float(p.dist) + pos.distance_to(npos)
		hist.append(npos)
		p.hist = hist
		if float(p.dist) > max_range or float(p.t) > 3.0:
			_finish_projectile(p, false)
			_projectiles.remove_at(i)
	_tick_bullet_cam_hold(delta)

func _finish_projectile(p: Dictionary, hit: bool) -> void:
	p["fade"] = TRAIL_FADE
	_fading.append(p)
	if _cam_node != null and is_same(_cam_proj, p):
		_cam_hold = CAM_HOLD_HIT if hit else CAM_HOLD_MISS
		_cam_hold_t = 0.0
		if is_instance_valid(_bullet_vis):
			_bullet_vis.visible = false
		if hit:
			_place_hold_cam(p.pos, (p.vel as Vector3).normalized())

## Nach dem Einschlag: Kamera einige Meter zurueck und seitlich versetzt, Blick auf den Einschlag (nicht in der Wand).
func _place_hold_cam(at: Vector3, d: Vector3) -> void:
	if not is_instance_valid(_cam_node):
		return
	var side: Vector3 = d.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var want: Vector3 = at - d * 3.4 + side * 1.1 + Vector3.UP * 0.6
	var from: Vector3 = at - d * 0.4
	var ex: Array[RID] = []
	if owner_player:
		ex.append(owner_player.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, want, 1, ex)
	var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if not r.is_empty():
		want = (r.position as Vector3).lerp(from, 0.25)
	_cam_node.global_position = want
	if want.distance_to(at) > 0.2:
		_cam_node.look_at(at, Vector3.UP)

# ---------------------------------------------------------------- Ballistik

static func _accel(v: Vector3, wind: Vector3) -> Vector3:
	var r: Vector3 = v - wind * WIND_GAIN
	return GRAVITY - r * (DRAG_K * r.length())

## Ein Flugabschnitt dt (RK2-Mittelpunkt, Teilschritte <= SIM_STEP) -> [pos, vel].
## Einzige Bewegungsgleichung fuer Flug, Vorhersage, Tabellen und Loeser.
static func ballistic_step(pos: Vector3, vel: Vector3, wind: Vector3, dt: float) -> Array:
	var n: int = maxi(1, ceili(dt / SIM_STEP - 0.001))
	var h: float = dt / float(n)
	for _i in n:
		var vm: Vector3 = vel + _accel(vel, wind) * (h * 0.5)
		pos += vm * h
		vel += _accel(vm, wind) * h
	return [pos, vel]

## Abschussrichtung aus der Visierrichtung: um _zero_angle in Richtung "oben" der Kamera gekippt.
func launch_dir(sight_dir: Vector3, up: Vector3 = Vector3.ZERO) -> Vector3:
	var d: Vector3 = sight_dir.normalized()
	if up == Vector3.ZERO:
		var right: Vector3 = d.cross(Vector3.UP)
		right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
		up = right.cross(d).normalized()
	return (d + up * tan(_zero_angle)).normalized()

## Waagerechter Schuss in der Ebene (x = Entfernung, y = Hoehe, z = quer): Tabellen fuer Fall, Abdrift
## (1 m/s Querwind) und Flugzeit, plus Nullpunkt-Winkel per Iteration.
func _rebuild_ballistics() -> void:
	var ang: float = 0.0
	for _it in 6:
		var y: float = _flat_shot(ang, Vector3.ZERO, zero_range).y
		ang -= y / zero_range
	_zero_angle = ang
	var n: int = int(TAB_MAX / TAB_STEP) + 1
	_drop_tab.resize(n)
	_drift_tab.resize(n)
	_tof_tab.resize(n)
	_drop_tab[0] = 0.0
	_drift_tab[0] = 0.0
	_tof_tab[0] = 0.0
	# ein Durchlauf mit 1 m/s Querwind (+z): Fall aendert sich dadurch vernachlaessigbar (< 0,1 %)
	var pos := Vector3.ZERO
	var vel := Vector3(cos(ang), sin(ang), 0.0) * muzzle_velocity
	var w := Vector3(0.0, 0.0, 1.0)
	var t: float = 0.0
	var k: int = 1
	while k < n and t < 6.0:
		var st: Array = ballistic_step(pos, vel, w, SIM_STEP)
		var np: Vector3 = st[0]
		while k < n and np.x >= float(k) * TAB_STEP:
			var x: float = float(k) * TAB_STEP
			var f: float = (x - pos.x) / maxf(np.x - pos.x, 1e-6)
			var ip: Vector3 = pos.lerp(np, f)
			_drop_tab[k] = -ip.y / x * 1000.0
			_drift_tab[k] = ip.z / x * 1000.0
			_tof_tab[k] = t + f * SIM_STEP
			k += 1
		pos = np
		vel = st[1]
		t += SIM_STEP
	for j in range(k, n):
		_drop_tab[j] = _drop_tab[k - 1]
		_drift_tab[j] = _drift_tab[k - 1]
		_tof_tab[j] = _tof_tab[k - 1]

## Hoehe/Querablage beim Erreichen der Entfernung x (waagerechte Visierlinie, Abschusswinkel ang).
func _flat_shot(ang: float, wind: Vector3, x: float) -> Vector3:
	var pos := Vector3.ZERO
	var vel := Vector3(cos(ang), sin(ang), 0.0) * muzzle_velocity
	var t: float = 0.0
	while t < 6.0:
		var st: Array = ballistic_step(pos, vel, wind, SIM_STEP)
		var np: Vector3 = st[0]
		if np.x >= x:
			return pos.lerp(np, (x - pos.x) / maxf(np.x - pos.x, 1e-6))
		pos = np
		vel = st[1]
		t += SIM_STEP
	return pos

func _tab(tab: PackedFloat32Array, d: float) -> float:
	if tab.is_empty():
		return 0.0
	var f: float = clampf(d / TAB_STEP, 0.0, float(tab.size() - 1))
	var i: int = mini(int(f), tab.size() - 2)
	return lerpf(tab[i], tab[i + 1], f - float(i))

## Fall (Milliradiant unter der Visierlinie, negativ = ueber) auf Entfernung d beim aktuellen Nullpunkt.
func drop_mil(d: float) -> float:
	return _tab(_drop_tab, d)

## Abdrift (mil in Windrichtung) je 1 m/s Querwind auf Entfernung d.
func drift_mil(d: float) -> float:
	return _tab(_drift_tab, d)

## Flugzeit (s) bis zur Entfernung d.
func time_of_flight(d: float) -> float:
	return _tab(_tof_tab, d)

## Aktueller Wind (m/s, Welt) vom Level (sniper_wind()), sonst windstill.
func wind_vector() -> Vector3:
	if _level_ref == null or not is_instance_valid(_level_ref):
		_level_ref = get_tree().get_first_node_in_group("level") if is_inside_tree() else null
	if _level_ref != null and _level_ref.has_method("sniper_wind"):
		var w: Variant = _level_ref.call("sniper_wind")
		if w is Vector3:
			return w as Vector3
	return Vector3.ZERO

## Haltepunkt fuer die Visierlinie: Kamera bei from soll das (mit tvel bewegte) Ziel target treffen.
## Simuliert mit derselben Ballistik (Nullpunkt, Luftwiderstand, aktueller Wind) und korrigiert iterativ.
func solve_aim(from: Vector3, target: Vector3, tvel: Vector3 = Vector3.ZERO) -> Vector3:
	var wind: Vector3 = wind_vector()
	var aim: Vector3 = target
	var fut: Vector3 = target
	for _it in 5:
		var sight: Vector3 = aim - from
		if sight.length() < 1.0:
			return target
		var vel: Vector3 = launch_dir(sight) * muzzle_velocity
		var r: Dictionary = _fly_to_plane(from, vel, wind, fut)
		if r.is_empty():
			return aim
		fut = target + tvel * float(r.t)
		var miss: Vector3 = (r.pos as Vector3) - fut
		aim -= miss
	return aim

## Flug bis zur Ebene senkrecht zur Linie from->goal durch goal -> {pos, t} (leer, wenn nie erreicht).
func _fly_to_plane(from: Vector3, vel: Vector3, wind: Vector3, goal: Vector3) -> Dictionary:
	var nrm: Vector3 = (goal - from).normalized()
	var dist: float = from.distance_to(goal)
	var pos: Vector3 = from
	var t: float = 0.0
	var dt: float = 0.01
	while t < 3.0:
		var st: Array = ballistic_step(pos, vel, wind, dt)
		var np: Vector3 = st[0]
		var a: float = (pos - from).dot(nrm)
		var b2: float = (np - from).dot(nrm)
		if b2 >= dist:
			var f: float = (dist - a) / maxf(b2 - a, 1e-6)
			return {"pos": pos.lerp(np, f), "t": t + f * dt}
		pos = np
		vel = st[1]
		t += dt
	return {}

## Sichtbarer Haltepunkt (mil: x > 0 = rechts halten, y > 0 = hoeher halten) fuer Entfernung d und Wind.
func hold_mil(d: float, cam_basis: Basis) -> Vector2:
	var w: Vector3 = wind_vector()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 1e-6 else Vector3.RIGHT
	var cross: float = w.dot(right)                 # > 0: Wind blaest nach rechts -> Geschoss driftet rechts
	return Vector2(-cross * drift_mil(d), drop_mil(d))

func _impact(res: Dictionary, dir: Vector3, dist: float) -> void:
	var target: Node = _find_damageable(res.collider)
	var pos: Vector3 = res.position
	var normal: Vector3 = res.normal
	var owner_node: Node = target
	if target != null and target.has_method("get_enemy"):
		var e: Variant = target.call("get_enemy")
		if e is Node:
			owner_node = e as Node
	# Level-Puppen (Verbuendete, Weber): Ziel meldet den Treffer selbst, kein Hitmarker
	if owner_node != null and (owner_node.is_in_group("friendly") or owner_node.get("role") != null):
		target.take_damage(damage, owner_player, pos, normal)
		_later_sfx("overwatch_impact_flesh" if owner_node.is_in_group("friendly") else "overwatch_impact_metal", dist / 343.0)
		return
	var is_enemy: bool = _is_enemy(target)
	_apply_hit(res, dir)
	var delay: float = dist / 343.0
	if is_enemy and not VFX.is_bleeder(target):
		_later_sfx("overwatch_impact_metal", delay)
		VFX.spawn_impact(pos, normal, "metal")
	elif is_enemy:
		_spawn_mist(pos, normal, dir, res.collider is Node and bool((res.collider as Node).get_meta("headshot", false)))
		_later_sfx("overwatch_impact_flesh", delay)
	elif target == null:
		var surface: String = str((res.collider as Node).get_meta("surface", "concrete")) if res.collider is Node else "concrete"
		if surface == "metal":
			_later_sfx("overwatch_impact_metal", delay)
		# Deutliches Feedback auch auf grosse Distanz: Staubwolke waechst mit der Entfernung (kein Leuchtpunkt mehr,
		# Nutzerwunsch; die Leuchtspur zeigt die Bahn)
		VFX.spawn_dust_cloud(pos + normal * 0.2, clampf(dist / 110.0, 0.6, 2.2))
		VFX.spawn_impact(pos, normal, surface)

func _is_enemy(t: Node) -> bool:
	if t == null:
		return false
	if t.is_in_group("enemy"):
		return true
	if t.has_method("get_enemy"):
		var e: Variant = t.call("get_enemy")
		return e is Node and (e as Node).is_in_group("enemy")
	return false

func _later_sfx(sfx: String, delay: float) -> void:
	if delay < 0.05:
		_play(sfx, 0.05)
		return
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_play(sfx, 0.05))

## Blut beim Treffer (game/vfx/blood_fx.gd): gerichteter Spruehstoss + Nebel, Spritzer an der Wand dahinter.
## Hochgeschwindigkeitsgeschoss -> kraeftiger als Sturmgewehr; Kopftreffer am staerksten. Sieht auch in der
## Zeitlupe der Geschoss-Kamera gut aus (Partikel/Timer laufen in Spielzeit).
func _spawn_mist(pos: Vector3, normal: Vector3, dir: Vector3 = Vector3.ZERO, head: bool = false) -> void:
	VFX.spawn_blood(pos, normal, dir, 2.1 if head else 1.5)

# ---------------------------------------------------------------- Geschossspur

## Spur = Band entlang der Positionshistorie der Simulation (ImmediateMesh, jeden Frame zur Kamera gedreht).
func _make_trail() -> MeshInstance3D:
	if _trail_mat == null:
		var sh := Shader.new()
		sh.code = TRAIL_SHADER
		_trail_mat = ShaderMaterial.new()
		_trail_mat.shader = sh
	var mi := MeshInstance3D.new()
	mi.name = "BulletTrace"
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _trail_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16.0
	mi.top_level = true
	_world_root().add_child(mi)
	mi.global_transform = Transform3D.IDENTITY
	return mi

func _process(delta: float) -> void:
	# Geschosskopf zwischen zwei Physikschritten fortschreiben (ruhige Spur bei hoher Bildrate; in der Zeitlupe
	# ist ein Physikschritt entsprechend kuerzer)
	var frac: float = Engine.get_physics_interpolation_fraction() * Engine.time_scale / float(maxi(Engine.physics_ticks_per_second, 1))
	if _cam_node != null:
		_process_bullet_cam(delta, frac)
	if _fading.is_empty() and _projectiles.is_empty():
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return
	for p in _projectiles:
		_draw_trail(p, cam, (p.vel as Vector3) * frac, 1.0)
	for i in range(_fading.size() - 1, -1, -1):
		var f: Dictionary = _fading[i]
		f["fade"] = float(f["fade"]) - delta / maxf(Engine.time_scale, 0.05)
		var k: float = clampf(float(f["fade"]) / TRAIL_FADE, 0.0, 1.0)
		if k <= 0.0:
			var tr: Node = f.get("trail")
			if is_instance_valid(tr):
				tr.queue_free()
			_fading.remove_at(i)
			continue
		_draw_trail(f, cam, Vector3.ZERO, k * k)

func _draw_trail(p: Dictionary, cam: Camera3D, head_ext: Vector3, alpha: float) -> void:
	var tr: MeshInstance3D = p.get("trail")
	if not is_instance_valid(tr):
		return
	var im: ImmediateMesh = tr.mesh as ImmediateMesh
	im.clear_surfaces()
	# In der Geschoss-Kamera zeigt das Geschossmodell den Flug; die Spur waere von hinten nur ein Fleck
	if _cam_node != null and is_same(p, _cam_proj):
		return
	var hist: PackedVector3Array = p.hist
	if hist.size() < 2:
		return
	var origin: Vector3 = p.origin
	var vis_off: Vector3 = p.vis_off
	# Punkte vom Kopf rueckwaerts bis TRAIL_TAIL (Abstand s hinter dem Kopf)
	var pts := PackedVector3Array()
	var ss := PackedFloat32Array()
	var head: Vector3 = hist[hist.size() - 1] + head_ext
	pts.append(head)
	ss.append(0.0)
	var s: float = 0.0
	var prev: Vector3 = head
	for i in range(hist.size() - 2, -1, -1):
		var q: Vector3 = hist[i]
		var seg: float = prev.distance_to(q)
		if s + seg > TRAIL_TAIL:
			q = prev.lerp(q, (TRAIL_TAIL - s) / maxf(seg, 1e-4))
			seg = TRAIL_TAIL - s
		s += seg
		pts.append(q)
		ss.append(s)
		prev = q
		if s >= TRAIL_TAIL:
			break
	var cpos: Vector3 = cam.global_position
	var vp_h: float = maxf(cam.get_viewport().get_visible_rect().size.y, 1.0)
	var px_m: float = 2.0 * tan(deg_to_rad(maxf(cam.fov, 0.5) * 0.5)) / vp_h * TRAIL_PX
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	for i in pts.size():
		var wp: Vector3 = pts[i]
		var from_o: float = wp.distance_to(origin)
		if vis_off != Vector3.ZERO:
			wp += vis_off * clampf(1.0 - from_o / 25.0, 0.0, 1.0)
		# Richtung entlang der Bahn
		var a: Vector3 = pts[maxi(i - 1, 0)]
		var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var along: Vector3 = (a - b)
		if along.length_squared() < 1e-8:
			continue
		along = along.normalized()
		var to_cam: Vector3 = cpos - wp
		var dcam: float = to_cam.length()
		var side: Vector3 = along.cross(to_cam / maxf(dcam, 1e-4))
		if side.length_squared() < 1e-6:
			side = cam.global_basis.x
		side = side.normalized()
		var w: float = clampf(dcam * px_m, 0.004, 0.6) * 0.5
		# Kopf hell, Schweif blendet aus; die ersten Meter an der Muendung ebenfalls weich
		var tail_k: float = pow(clampf(1.0 - float(ss[i]) / TRAIL_TAIL, 0.0, 1.0), 1.3)
		var near_k: float = smoothstep(1.5, 5.0, from_o)
		var al: float = tail_k * near_k * alpha
		var u: float = (from_o) * 0.2
		verts.append(wp - side * w)
		verts.append(wp + side * w)
		cols.append(Color(1, 1, 1, al))
		cols.append(Color(1, 1, 1, al))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
	if verts.size() < 4:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for j in verts.size():
		im.surface_set_color(cols[j])
		im.surface_set_uv(uvs[j])
		im.surface_add_vertex(verts[j])
	im.surface_end()

# ---------------------------------------------------------------- Geschoss-Kamera

## Fuer Level-Platzierung: kommt ein korrekt gehaltener Schuss von from bis target durch (Geschossbahn mit Fall,
## Wind und Nullpunkt, nicht nur die Sichtlinie)?
func ballistic_clear(from: Vector3, target: Vector3) -> bool:
	var aim: Vector3 = solve_aim(from, target)
	var vel: Vector3 = launch_dir(aim - from) * muzzle_velocity
	var d: float = _predict_impact_dist(from, vel, wind_vector())
	return d < 0.0 or d >= from.distance_to(target) - 1.0

## Vorhergesagte Einschlagentfernung (m) mit derselben Ballistik wie der Flug; -1 = kein Einschlag in Reichweite.
func _predict_impact_dist(origin: Vector3, vel: Vector3, wind: Vector3) -> float:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	var pos := origin
	var v := vel
	var dt := 0.02
	for _i in 160:
		var st: Array = ballistic_step(pos, v, wind, dt)
		var npos: Vector3 = st[0]
		var q := PhysicsRayQueryParameters3D.create(pos, npos, HIT_MASK, exclude)
		q.collide_with_areas = true
		var res: Dictionary = space.intersect_ray(q)
		if not res.is_empty():
			return origin.distance_to(res.position)
		if origin.distance_to(npos) > max_range:
			break
		v = st[1]
		pos = npos
	return -1.0

func _start_bullet_cam(p: Dictionary, tof: float) -> void:
	_cam_node = Camera3D.new()
	_cam_node.name = "BulletCam"
	_cam_node.fov = 38.0
	_cam_node.near = 0.01
	_cam_node.far = 2000.0
	_world_root().add_child(_cam_node)
	_bullet_vis = _make_bullet_vis()
	_cam_proj = p
	_cam_hold = -1.0
	_cam_hold_t = 0.0
	_cam_real_t = 0.0
	_cam_shot_i = 0
	_cam_count += 1
	_bullet_spin = randf() * TAU
	_place_bullet_cam(p.pos, (p.vel as Vector3).normalized(), 0.0)
	_cam_node.make_current()
	_cam_prev_scale = Engine.time_scale
	# Zeitlupe nach Flugzeit: nahe und weite Schuesse dauern in Echtzeit etwa gleich lang
	Engine.time_scale = clampf(tof / CAM_FLIGHT_REAL, CAM_SCALE_MIN, CAM_SCALE_MAX)
	if _overlay_layer:
		_overlay_layer.visible = false
	# Kein cancel_aim mehr: die Kamera kommt jetzt bei jedem weiten Schuss, danach geht es im Zielfernrohr
	# weiter (Treffer kontrollieren, naechstes Ziel)

## Kamera seitlich hinter dem Geschoss, leicht mitdrehend; Geschossmodell mit Drall an der Kopfposition.
func _place_bullet_cam(head: Vector3, dir: Vector3, real_dt: float) -> void:
	if _cam_node == null:
		return
	var side: Vector3 = dir.cross(Vector3.UP)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var up: Vector3 = side.cross(dir).normalized()
	# langsame Fahrt um die Flugachse (von rechts oben nach rechts)
	var orbit: float = 0.55 - 0.22 * minf(_cam_real_t, 3.0)
	var off: Vector3 = (side * CAM_SIDE + up * CAM_UP).rotated(dir, orbit)
	_cam_node.global_position = head - dir * CAM_BACK + off
	_cam_node.look_at(head + dir * CAM_AIM, up)
	if is_instance_valid(_bullet_vis):
		_bullet_vis.global_position = head
		_bullet_vis.look_at(head + dir, up)
		_bullet_spin = fposmod(_bullet_spin + BULLET_SPIN * real_dt, TAU)
		if _bullet_mi != null:
			_bullet_mi.rotation.z = _bullet_spin

func _process_bullet_cam(delta: float, frac: float) -> void:
	var real_dt: float = delta / maxf(Engine.time_scale, 0.01)
	_cam_real_t += real_dt
	if _cam_hold < 0.0 and not _cam_proj.is_empty():
		var vel: Vector3 = _cam_proj.vel
		_place_bullet_cam((_cam_proj.pos as Vector3) + vel * frac, vel.normalized(), real_dt)
	elif _cam_hold >= 0.0 and is_instance_valid(_cam_node) and not _cam_proj.is_empty():
		# nach dem Einschlag langsam zurueckziehen: Treffer bleibt im Bild
		_cam_hold_t += real_dt
		_cam_node.global_position -= _cam_node.global_transform.basis.z * -0.35 * real_dt
	_capture_bullet_cam()

## Test: --bulletcam-shots=<Ordner> speichert je Geschoss-Kamera (die ersten 4) drei Bilder.
func _capture_bullet_cam() -> void:
	var out: String = str(Game.arg("bulletcam-shots", ""))
	if out == "" or _cam_count > 4 or _cam_shot_i >= 3:
		return
	var due: bool = false
	if _cam_shot_i == 0 and _cam_real_t >= 0.35:
		due = true
	elif _cam_shot_i == 1 and (_cam_real_t >= 1.4 or _cam_hold >= 0.0):
		due = true
	elif _cam_shot_i == 2 and _cam_hold >= 0.0 and _cam_hold_t >= 0.3:
		due = true
	if not due:
		return
	DirAccess.make_dir_recursive_absolute(out)
	var path: String = out.path_join("bulletcam_%d_%d.png" % [_cam_count, _cam_shot_i])
	get_viewport().get_texture().get_image().save_png(path)
	print("[g28] Geschoss-Kamera Bild: ", path)
	_cam_shot_i += 1

func _tick_bullet_cam_hold(delta: float) -> void:
	if _cam_node == null:
		return
	if _cam_real_t > CAM_MAX_REAL:
		_end_bullet_cam()
		return
	if _cam_hold < 0.0:
		return
	# delta laeuft in Zeitlupe: Echtzeit-Haltezeit
	_cam_hold -= delta / maxf(Engine.time_scale, 0.01)
	if _cam_hold <= 0.0:
		_end_bullet_cam()

func _end_bullet_cam() -> void:
	if is_instance_valid(_bullet_vis):
		_bullet_vis.queue_free()
	_bullet_vis = null
	_bullet_mi = null
	if _cam_node == null:
		return
	Engine.time_scale = _cam_prev_scale
	if is_instance_valid(_cam_node):
		_cam_node.queue_free()
	_cam_node = null
	_cam_proj = {}
	if owner_player != null and is_instance_valid(owner_player):
		owner_player.camera.make_current()

# ---------------------------------------------------------------- Geschossmodell

func _make_bullet_vis() -> Node3D:
	var root := Node3D.new()
	root.name = "BulletCamProjectile"
	root.top_level = true
	_world_root().add_child(root)
	var mi := MeshInstance3D.new()
	mi.mesh = _bullet_mesh()
	mi.material_override = _bullet_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3.ONE * BULLET_VIS_SCALE
	root.add_child(mi)
	_bullet_mi = mi
	# Kleines Streiflicht seitlich ueber dem Geschoss (Kameraseite): der Tombakmantel glaenzt auch nachts
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.93, 0.84)
	lamp.light_energy = 1.4
	lamp.omni_range = 0.4
	lamp.omni_attenuation = 1.2
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.07, 0.06, -0.03)
	root.add_child(lamp)
	# Nachlauf: duenner Kegel hinter dem Boden, nur Luftflimmern (Bildschirm-Verzerrung)
	if _wake_mat_res == null:
		var sh := Shader.new()
		sh.code = WAKE_SHADER
		_wake_mat_res = ShaderMaterial.new()
		_wake_mat_res.shader = sh
	var cm := CylinderMesh.new()
	cm.top_radius = BULLET_R * 0.8 * BULLET_VIS_SCALE
	cm.bottom_radius = 0.03
	cm.height = WAKE_LEN
	cm.radial_segments = 18
	cm.rings = 6
	cm.cap_top = false
	cm.cap_bottom = false
	var wake := MeshInstance3D.new()
	wake.name = "Wake"
	wake.mesh = cm
	wake.material_override = _wake_mat_res
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Zylinderachse +Y -> -Z: schmales oberes Ende am Geschossboden, Kegel oeffnet nach hinten (+Z)
	wake.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	wake.position = Vector3(0.0, 0.0, BULLET_LEN * 0.42 * BULLET_VIS_SCALE + WAKE_LEN * 0.5)
	root.add_child(wake)
	return root

## Drehkoerper aus dem Profil eines 7,62-mm-Matchgeschosses (Boattail, Fuehrungsteil, Tangentenogive mit
## kleiner Meplat). Spitze nach -Z, Ursprung im Schwerpunkt (42 % der Laenge vom Boden), Masse in Metern.
static func _bullet_mesh() -> ArrayMesh:
	if _bullet_mesh_res != null:
		return _bullet_mesh_res
	var l: float = BULLET_LEN * 1000.0
	var rb: float = BULLET_R * 1000.0
	var prof := PackedVector2Array()     # (z ab Boden, r) in mm
	prof.append(Vector2(0.0, 3.05))
	prof.append(Vector2(0.35, 3.22))
	prof.append(Vector2(3.6, rb))
	prof.append(Vector2(14.0, rb))
	var og: float = l - 14.0
	var big_r: float = (rb * rb + og * og) / (2.0 * rb)
	for i in range(1, 14):
		var x: float = og * float(i) / 14.0
		prof.append(Vector2(14.0 + x, maxf(sqrt(maxf(big_r * big_r - x * x, 0.0)) - (big_r - rb), 0.5)))
	prof.append(Vector2(l - 0.08, 0.48))
	prof.append(Vector2(l, 0.0))
	var n: int = prof.size()
	var nrm := PackedVector2Array()      # (axial, radial)
	for i in n:
		var t: Vector2 = (prof[mini(i + 1, n - 1)] - prof[maxi(i - 1, 0)]).normalized()
		nrm.append(Vector2(-t.y, t.x))
	var zc: float = l * 0.42
	var segs: int = 32
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in n - 1:
		for s in segs:
			var a0: float = TAU * float(s) / float(segs)
			var a1: float = TAU * float(s + 1) / float(segs)
			var q: Array = [[i, a0, s], [i + 1, a0, s], [i + 1, a1, s + 1], [i, a0, s], [i + 1, a1, s + 1], [i, a1, s + 1]]
			for e: Array in q:
				var p: Vector2 = prof[int(e[0])]
				var nn: Vector2 = nrm[int(e[0])]
				var ang: float = float(e[1])
				st.set_normal(Vector3(cos(ang) * nn.y, sin(ang) * nn.y, -nn.x).normalized())
				st.set_uv(Vector2(float(e[2]) / float(segs), p.x / l))
				st.add_vertex(Vector3(cos(ang) * p.y, sin(ang) * p.y, -(p.x - zc)) * 0.001)
	# Boden (flach, Normale nach hinten)
	var r0: float = prof[0].y
	for s in segs:
		var a0: float = TAU * float(s) / float(segs)
		var a1: float = TAU * float(s + 1) / float(segs)
		for e: Vector3 in [Vector3(0, 0, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0), Vector3(cos(a0) * r0, sin(a0) * r0, 0)]:
			st.set_normal(Vector3.BACK)
			st.set_uv(Vector2(0.5 + e.x / (2.0 * r0) * 0.1, 0.985))   # Boden: dunkler Bereich der Textur
			st.add_vertex(Vector3(e.x, e.y, zc) * 0.001)
	_bullet_mesh_res = st.commit()
	return _bullet_mesh_res

## Tombakmantel (Kupfer-Zink, kupferrot-messingfarben) mit vier Feldeindruecken im Rechtsdrall auf dem
## Fuehrungsteil, feinen Ziehriefen und leicht angelaufener Spitze.
static func _bullet_material() -> StandardMaterial3D:
	if _bullet_mat_res != null:
		return _bullet_mat_res
	var w: int = 128
	var h: int = 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var base := Color(0.8, 0.5, 0.33)
	var bear0: float = 3.8 / 31.2
	var bear1: float = 13.8 / 31.2
	for y in h:
		var v: float = (float(y) + 0.5) / float(h)
		for x in w:
			var u: float = (float(x) + 0.5) / float(w)
			var c: Color = base * (0.95 + 0.05 * sin(u * TAU * 23.0 + v * 9.0))
			if v > bear0 and v < bear1:
				var ph: float = fposmod(u * 4.0 + v * 0.35, 1.0)
				if ph < 0.15:
					c = c * 0.7
				elif ph < 0.19:
					c = c.lightened(0.18)
			if v > 0.93:
				c = c.darkened(0.25 * (v - 0.93) / 0.07)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.metallic = 0.7
	m.metallic_specular = 0.6
	m.roughness = 0.32
	m.emission_enabled = true
	m.emission = Color(0.3, 0.15, 0.07)
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_bullet_mat_res = m
	return m

# ---------------------------------------------------------------- Overlay

const MASK_SHADER := """
shader_type canvas_item;
uniform vec2 size = vec2(1920.0, 1080.0);
uniform vec2 offset = vec2(0.0);
uniform float radius = 480.0;
uniform float amount = 1.0;
void fragment() {
	vec2 p = UV * size - size * 0.5;
	float d = length(p);
	float ds = length(p - offset);
	// harte Tubus-Kante (leicht weich), innen dunkler Rand + Schatten bei Verkantung
	float outside = smoothstep(radius - 3.0, radius + 1.5, d);
	float rim = smoothstep(radius * 0.78, radius, ds) * 0.75;
	float edge = smoothstep(radius * 0.93, radius, d);
	float a = max(outside, max(rim * 0.7, edge * 0.9));
	vec3 col = mix(vec3(0.03, 0.025, 0.02), vec3(0.0), outside);
	COLOR = vec4(col, a * amount);
}
"""

## Simuliert den Schuss, der jetzt fallen wuerde (ohne Streuung), bis zum ersten Treffer.
func _update_prediction(cam: Camera3D) -> void:
	pred_valid = false
	pred_enemy = false
	var b: Basis = cam.global_basis
	var pos: Vector3 = cam.global_position
	var v: Vector3 = launch_dir(-b.z, b.y) * muzzle_velocity
	var wind: Vector3 = wind_vector()
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	var dt := 0.02
	for _i in 175:
		var st: Array = ballistic_step(pos, v, wind, dt)
		var npos: Vector3 = st[0]
		var q := PhysicsRayQueryParameters3D.create(pos, npos, HIT_MASK, exclude)
		q.collide_with_areas = true
		var res: Dictionary = space.intersect_ray(q)
		if not res.is_empty():
			pred_valid = true
			pred_pos = res.position
			var t: Node = _find_damageable(res.collider)
			pred_enemy = _is_enemy(t) and (not t.has_method("is_alive") or bool(t.call("is_alive")))
			return
		v = st[1]
		pos = npos

func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "ScopeOverlay"
	_overlay_layer.layer = OVERLAY_LAYER
	_overlay_layer.visible = false
	add_child(_overlay_layer)
	_mask = ColorRect.new()
	_mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK_SHADER
	_mask_mat = ShaderMaterial.new()
	_mask_mat.shader = sh
	_mask.material = _mask_mat
	_overlay_layer.add_child(_mask)
	_reticle = ScopeReticle.new()
	_reticle.set("rifle", self)
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_layer.add_child(_reticle)

func _update_overlay() -> void:
	if _overlay_layer == null:
		return
	var on: bool = scoped_amount > 0.01
	_overlay_layer.visible = on
	if not on:
		return
	var size: Vector2 = _mask.get_viewport_rect().size
	var radius: float = size.y * 0.47
	_mask_mat.set_shader_parameter("size", size)
	_mask_mat.set_shader_parameter("radius", radius)
	var px_per_deg: float = size.y * 0.5 / tan(deg_to_rad(maxf(owner_player.camera.fov, 1.0) * 0.5)) * PI / 180.0 if owner_player else 50.0
	# Schatten folgt dem Schwanken (Auge nicht exakt hinter der Achse)
	_mask_mat.set_shader_parameter("offset", Vector2(_sway_off.x, -_sway_off.y) * px_per_deg * 0.35 * radius / 400.0)
	_mask_mat.set_shader_parameter("amount", clampf(scoped_amount * 1.6, 0.0, 1.0))
	_reticle.modulate.a = clampf((scoped_amount - 0.3) / 0.7, 0.0, 1.0)
	_reticle.queue_redraw()

func range_m() -> float:
	return _range_m

## Zielhilfe (Einstellung "game/sniper_assist"): 0 = realistisch, 1 = korrigierter Haltepunkt im Absehen.
func assist_on() -> bool:
	return int(Settings.get_value("game/sniper_assist", 0)) == 1

func zero_flash() -> float:
	return _zero_flash

class ScopeReticle extends Control:
	var rifle: Node = null
	var _font: Font

	func _ready() -> void:
		_font = ThemeDB.fallback_font

	func _draw() -> void:
		if rifle == null or rifle.get("owner_player") == null:
			return
		var size: Vector2 = get_viewport_rect().size
		var c: Vector2 = size * 0.5
		var r: float = size.y * 0.47
		var cam: Camera3D = (rifle.get("owner_player") as Node).get("camera")
		var fov: float = maxf(cam.fov, 0.5)
		var px_per_mil: float = (size.y * 0.5) / tan(deg_to_rad(fov * 0.5)) * 0.001
		var ink := Color(0.02, 0.02, 0.02, 0.95)
		var thin: float = maxf(1.2, size.y / 700.0)
		var thick: float = maxf(4.0, size.y / 150.0)
		# Duplex: dicke Pfosten aussen, duenne Linien innen
		var inner: float = r * 0.42
		draw_line(c + Vector2(-r, 0), c + Vector2(-inner, 0), ink, thick)
		draw_line(c + Vector2(inner, 0), c + Vector2(r, 0), ink, thick)
		draw_line(c + Vector2(0, inner), c + Vector2(0, r), ink, thick)
		draw_line(c + Vector2(0, -r), c + Vector2(0, -inner), ink, thick)
		draw_line(c + Vector2(-inner, 0), c + Vector2(inner, 0), ink, thin, true)
		draw_line(c + Vector2(0, -inner), c + Vector2(0, inner), ink, thin, true)
		# Strichplatte: Milliradiant-Striche (bei kleiner Teilung jeder zweite)
		var step: int = 1 if px_per_mil >= 6.0 else 2
		var m: int = step
		while float(m) * px_per_mil < inner - 2.0:
			var o: float = float(m) * px_per_mil
			var big: bool = m % 5 == 0
			var hl: float = (6.0 if big else 3.5) * thin
			draw_line(c + Vector2(o, -hl), c + Vector2(o, hl), ink, thin, true)
			draw_line(c + Vector2(-o, -hl), c + Vector2(-o, hl), ink, thin, true)
			draw_line(c + Vector2(-hl, -o), c + Vector2(hl, -o), ink, thin, true)
			m += step
		# BDC-Marken unter der Mitte (aus derselben Ballistik wie der Flug, relativ zum eingestellten Nullpunkt),
		# je Marke Wind-Punkte im Abstand von 1 mil links/rechts zum Vorhalten gegen den Wind
		var zr: float = float(rifle.get("zero_range"))
		var dot_r: float = maxf(1.3, thin * 1.1)
		for d in [200, 300, 400, 500, 600]:
			if float(d) < zr + 40.0:
				continue
			var y: float = float(rifle.call("drop_mil", float(d))) * px_per_mil
			if y < 4.0 or y > inner:
				continue
			var w: float = maxf(10.0, (14.0 - float(d) / 60.0) * thin * 1.4)
			draw_line(c + Vector2(-w, y), c + Vector2(w, y), ink, thin * 1.3, true)
			draw_string(_font, c + Vector2(w + 4.0, y + 4.0), str(d / 100), HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(11.0, size.y / 60.0)), ink)
			for k in range(1, 4):
				var ox: float = float(k) * px_per_mil
				if ox < w + 3.0 and k < 3:
					continue
				draw_circle(c + Vector2(ox, y), dot_r, ink)
				draw_circle(c + Vector2(-ox, y), dot_r, ink)
		var fs: int = int(maxf(13.0, size.y / 42.0))
		var txt_col := Color(0.85, 0.9, 0.82, 0.92)
		var rng: float = float(rifle.call("range_m"))
		# Zielhilfe: korrigierter Haltepunkt (Fall + Wind) fuer die gemessene Entfernung
		if bool(rifle.call("assist_on")) and rng > 20.0:
			var hv: Vector2 = rifle.call("hold_mil", rng, cam.global_basis)
			var hp: Vector2 = c + Vector2(-hv.x, hv.y) * px_per_mil    # Ziel an diese Marke legen
			if hp.distance_to(c) < inner:
				var hr: float = maxf(5.0, size.y / 150.0)
				var hc := Color(1.0, 0.55, 0.1, 0.95)
				draw_arc(hp, hr, 0.0, TAU, 20, hc, thin * 1.4, true)
				draw_circle(hp, maxf(1.2, thin), hc)
				var ht: String = "HALTE  %.1f %s  %.1f %s mil" % [absf(hv.y), "HOCH" if hv.y >= 0.0 else "TIEF", absf(hv.x), "LINKS" if hv.x < 0.0 else "RECHTS"]
				draw_string(_font, c + Vector2(r * 0.18, r * 0.72), ht, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), hc)
		# Treffpunkt-Vorhersage (nur bei angehaltenem Atem): orangene Raute, rot + "TREFFER" auf einem Gegner
		if bool(rifle.get("pred_valid")):
			var wp: Vector3 = rifle.get("pred_pos")
			if not cam.is_position_behind(wp):
				var sp: Vector2 = cam.unproject_position(wp)
				if sp.distance_to(c) < r * 0.95:
					var on_enemy: bool = bool(rifle.get("pred_enemy"))
					var pc := Color(1.0, 0.18, 0.1, 1.0) if on_enemy else Color(1.0, 0.6, 0.12, 0.95)
					var ds: float = maxf(7.0, size.y / 110.0)
					var pts := PackedVector2Array([sp + Vector2(0, -ds), sp + Vector2(ds, 0), sp + Vector2(0, ds), sp + Vector2(-ds, 0), sp + Vector2(0, -ds)])
					draw_polyline(pts, Color(0, 0, 0, 0.6), thin * 3.2, true)
					draw_polyline(pts, pc, thin * 1.8, true)
					draw_circle(sp, maxf(1.5, thin * 1.2), pc)
					if on_enemy:
						draw_string(_font, sp + Vector2(ds + 5.0, -ds - 2.0), "TREFFER", HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(12.0, size.y / 70.0)), pc)
		# Leuchtpunkt
		draw_circle(c, maxf(1.6, size.y / 460.0), Color(0.95, 0.12, 0.08, 0.95))
		# Entfernung, Vergroesserung, Nullpunkt, Wind, Atem
		var rtxt: String = "ENTF  ---  m" if rng < 0.0 else "ENTF  %d m" % int(round(rng))
		draw_string(_font, c + Vector2(r * 0.18, r * 0.82), rtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
		var labels: PackedStringArray = rifle.get("zoom_labels")
		var zi: int = int(rifle.get("zoom_index"))
		var ztxt: String = labels[zi] if zi < labels.size() else ""
		draw_string(_font, c + Vector2(-r * 0.5, r * 0.82), ztxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, txt_col)
		var zf: float = float(rifle.call("zero_flash"))
		var zcol: Color = txt_col.lerp(Color(1.0, 0.75, 0.3, 1.0), clampf(zf, 0.0, 1.0))
		draw_string(_font, c + Vector2(-r * 0.62, -r * 0.74), "NULL  %d m" % int(round(zr)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.9), zcol)
		_draw_wind(c + Vector2(r * 0.36, -r * 0.76), fs, txt_col, cam, thin)
		var br: float = float(rifle.get("breath")) / maxf(float(rifle.get("breath_max")), 0.01)
		var hold: bool = bool(rifle.get("holding_breath"))
		var arc_c: Vector2 = c + Vector2(0, 0)
		var arc_r: float = r * 0.9
		var a0: float = PI * 0.5 + 0.55
		var a1: float = PI * 0.5 + 0.95
		draw_arc(arc_c, arc_r, a0, a1, 24, Color(0.4, 0.42, 0.4, 0.45), thick * 0.8, true)
		var bcol := Color(0.75, 0.88, 0.95, 0.95) if hold else Color(0.7, 0.75, 0.7, 0.7)
		if br < 0.25:
			bcol = Color(0.95, 0.35, 0.25, 0.9)
		if br > 0.01:
			draw_arc(arc_c, arc_r, a1 - (a1 - a0) * br, a1, 24, bcol, thick * 0.8, true)
		draw_string(_font, arc_c + Vector2(cos(a1), sin(a1)) * arc_r + Vector2(-fs * 3.4, fs * 0.2), "ATEM", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), txt_col)

	# Windanzeige: Kreis mit Pfeil (wohin der Wind blaest, relativ zur Blickrichtung: oben = vorn),
	# dazu Staerke und Uhrzeit, AUS der der Wind kommt (12 Uhr = von vorn, 3 Uhr = von rechts)
	func _draw_wind(pos: Vector2, fs: int, col: Color, cam: Camera3D, thin: float) -> void:
		var wv: Vector3 = rifle.call("wind_vector")
		var fwd := -cam.global_basis.z
		fwd.y = 0.0
		if fwd.length() < 0.01:
			fwd = Vector3.FORWARD
		fwd = fwd.normalized()
		var right := Vector3(-fwd.z, 0.0, fwd.x)
		var flat := Vector3(wv.x, 0.0, wv.z)
		var spd: float = flat.length()
		var rad: float = maxf(14.0, fs * 1.15)
		var cc: Vector2 = pos + Vector2(rad, -rad * 0.35)
		draw_arc(cc, rad, 0.0, TAU, 28, Color(col, 0.55), thin, true)
		draw_line(cc + Vector2(0, -rad - 4.0), cc + Vector2(0, -rad + 3.0), col, thin * 1.4, true)
		var clock: int = 12
		if spd > 0.15:
			var sv := Vector2(flat.dot(right), -flat.dot(fwd)).normalized()
			var tip: Vector2 = cc + sv * rad * 0.8
			var tail: Vector2 = cc - sv * rad * 0.8
			draw_line(tail, tip, col, thin * 1.6, true)
			var side := Vector2(-sv.y, sv.x)
			draw_colored_polygon(PackedVector2Array([tip, tip - sv * rad * 0.42 + side * rad * 0.26, tip - sv * rad * 0.42 - side * rad * 0.26]), col)
			var from_r: float = -flat.dot(right)
			var from_f: float = -flat.dot(fwd)
			var ang: float = atan2(from_r, from_f)
			clock = int(round(fposmod(ang, TAU) / (TAU / 12.0))) % 12
			if clock == 0:
				clock = 12
		var txt: String = "WIND  %.1f m/s" % spd
		if spd > 0.15:
			txt += "  %d Uhr" % clock
		draw_string(_font, cc + Vector2(rad + 8.0, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.9), col)
