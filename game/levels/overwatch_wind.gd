extends Node3D
## Level 7 "Kaltes Auge": Wind fuer die Ballistik des Scharfschuetzengewehrs und dessen sichtbare Hinweise.
## Grundwind je Abschnitt (Richtung, in die er blaest + Staerke), weich ueberblendet; darueber langsame Boeen
## (Staerke/Richtung) aus Rauschen. current() liefert den Weltvektor in m/s (Level.sniper_wind()).
## Sichtbar: Windsaecke an beiden Stellungen und an der Strasse, Dampf/Rauch der Schlote driftet mit,
## dazu flache Dunstschwaden ueber der Strasse.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

## Abschnitt -> [Richtung (wohin), Staerke m/s]. Staerken so, dass auf 250 m etwa 1 - 1,5 mil Abdrift entstehen.
const PROFILES := {
	"sentries": [Vector3(-1.0, 0.0, 0.15), 3.0],
	"convoy": [Vector3(-1.0, 0.0, 0.3), 3.8],
	"csniper": [Vector3(-0.85, 0.0, 0.5), 4.5],
	"p2": [Vector3(0.83, 0.0, 0.55), 5.0],
}
const BLEND_T := 6.0          # Zeitkonstante beim Wechsel des Grundwinds (s)
const GUST_AMP := 0.3         # +-30 % Staerke
const GUST_DIR := 0.24        # ~ +-14 Grad
const SOCK_SEGS := 5
const SOCK_FULL := 7.5        # ab dieser Staerke steht der Sack waagerecht

var _base: Vector3 = Vector3(-1.0, 0.0, 0.15).normalized() * 3.0
var _goal: Vector3 = _base
var _cur: Vector3 = _base
var _t: float = 0.0
var _noise := FastNoiseLite.new()
var _socks: Array = []        # {pivot: Node3D, segs: Array[Node3D], phase: float}
var _steam: Array = []        # {pm: ParticleProcessMaterial, gy: float, drift: float}
var _steam_t: float = 0.0
var _wisps: GPUParticles3D = null
var _wisp_pm: ParticleProcessMaterial = null

func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.seed = 7117
	_noise.frequency = 1.0
	var at: Array = [
		[Vector3(4.0, 22.0, 7.9), 3.4],         # P1, Gelaender am Uebergabeturm
		[Vector3(-36.4, 22.0, 2.4), 3.4],       # P2
		[Vector3(-26.0, 0.0, -131.5), 6.0],     # Strasse, vor der eigenen Deckung
		[Vector3(46.0, 0.0, -131.5), 6.0],      # Strasse rechts (Linie zum Schornstein)
		[Vector3(-66.0, 0.0, -133.0), 6.0],     # Strasse links (Linie zum Kuehlturm)
	]
	for e in at:
		_build_sock(e[0] as Vector3, float(e[1]))
	_build_wisps()
	# Dampf/Rauch erst nach dem Aufbau der Welt einsammeln
	_later_collect.call_deferred()

func _later_collect() -> void:
	var root: Node = get_parent()
	if root == null:
		return
	_collect_steam(root)

## Grundwind fuer eine Spielphase setzen (unbekannte Phasen behalten den Wind).
func set_phase(ph: String) -> void:
	var key: String = ""
	match ph:
		"climb", "sentries", "sentries_done":
			key = "sentries"
		"convoy", "ambush", "ambush_done":
			key = "convoy"
		"csniper", "csniper_done", "mortar":
			key = "csniper"
		"p2", "p2_done", "weber", "brandt", "extract", "done":
			key = "p2"
	if key == "":
		return
	var prof: Array = PROFILES[key]
	_goal = (prof[0] as Vector3).normalized() * float(prof[1])

## Sofort auf den Grundwind springen (Debug-Sprung in eine Phase).
func snap() -> void:
	_base = _goal
	_update_cur()

func current() -> Vector3:
	return _cur

func _update_cur() -> void:
	var g1: float = _noise.get_noise_2d(_t * 0.05, 3.0)
	var g2: float = _noise.get_noise_2d(_t * 0.6, 17.0)
	var gd: float = _noise.get_noise_2d(_t * 0.04, 41.0)
	var k: float = maxf(0.2, 1.0 + GUST_AMP * g1 + 0.06 * g2)
	_cur = _base.rotated(Vector3.UP, GUST_DIR * gd) * k

func _process(delta: float) -> void:
	_t += delta
	_base = _base.lerp(_goal, 1.0 - exp(-delta / BLEND_T))
	_update_cur()
	_update_socks()
	_steam_t -= delta
	if _steam_t <= 0.0:
		_steam_t = 0.25
		_update_steam()

# ---------------------------------------------------------------- Windsack

func _build_sock(base: Vector3, pole_h: float) -> void:
	var holder := Node3D.new()
	holder.name = "Windsock"
	add_child(holder)
	holder.position = base
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.32, 0.33, 0.34)
	pole_mat.metallic = 0.6
	pole_mat.roughness = 0.5
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.05
	pm.height = pole_h
	pm.radial_segments = 8
	pole.mesh = pm
	pole.material_override = pole_mat
	pole.position = Vector3(0.0, pole_h * 0.5, 0.0)
	holder.add_child(pole)
	# Drehgelenk oben; der Sack haengt in +Z dieses Gelenks
	var pivot := Node3D.new()
	pivot.position = Vector3(0.0, pole_h, 0.0)
	holder.add_child(pivot)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.2
	tm.outer_radius = 0.24
	ring.mesh = tm
	ring.material_override = pole_mat
	ring.rotation_degrees = Vector3(90, 0, 0)
	pivot.add_child(ring)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.36, 0.06)
	orange.emission_enabled = true
	orange.emission = Color(0.55, 0.16, 0.02)
	orange.emission_energy_multiplier = 0.5     # nachts noch erkennbar
	orange.cull_mode = BaseMaterial3D.CULL_DISABLED
	orange.roughness = 0.85
	var white := orange.duplicate() as StandardMaterial3D
	white.albedo_color = Color(0.92, 0.92, 0.9)
	white.emission = Color(0.4, 0.4, 0.4)
	var segs: Array = []
	var parent: Node3D = pivot
	var seg_len: float = 0.34
	for i in SOCK_SEGS:
		var joint := Node3D.new()
		joint.position = Vector3(0.0, 0.0, 0.0 if i == 0 else seg_len)
		parent.add_child(joint)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r0: float = lerpf(0.22, 0.1, float(i) / float(SOCK_SEGS))
		var r1: float = lerpf(0.22, 0.1, float(i + 1) / float(SOCK_SEGS))
		cm.top_radius = r0
		cm.bottom_radius = r1
		cm.height = seg_len
		cm.radial_segments = 10
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		mi.material_override = orange if i % 2 == 0 else white
		mi.rotation_degrees = Vector3(90, 0, 0)    # Zylinderachse entlang +Z
		mi.position = Vector3(0.0, 0.0, seg_len * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		joint.add_child(mi)
		segs.append(joint)
		parent = joint
	_socks.append({"pivot": pivot, "segs": segs, "phase": randf() * TAU})

func _update_socks() -> void:
	var flat := Vector3(_cur.x, 0.0, _cur.z)
	var spd: float = flat.length()
	var yaw: float = atan2(flat.x, flat.z) if spd > 0.05 else 0.0
	var lift: float = clampf(spd / SOCK_FULL, 0.0, 1.0)
	var droop: float = lerpf(deg_to_rad(80.0), deg_to_rad(2.0), sqrt(lift))
	for s in _socks:
		var pivot: Node3D = s["pivot"]
		var ph: float = float(s["phase"])
		var flutter: float = sin(_t * (6.0 + spd * 1.6) + ph) * (0.05 + 0.1 * lift)
		pivot.rotation = Vector3(droop * 0.6, yaw + flutter * 0.4, 0.0)
		var segs: Array = s["segs"]
		for i in segs.size():
			var j: Node3D = segs[i]
			if i == 0:
				continue
			var w: float = sin(_t * (7.0 + spd * 2.0) + ph + float(i) * 1.1) * (0.06 + 0.08 * lift) * float(i) / float(segs.size())
			j.rotation = Vector3(droop * 0.4 / float(segs.size() - 1), w, 0.0)

# ---------------------------------------------------------------- Dampf, Dunst

func _collect_steam(n: Node) -> void:
	for c in n.get_children():
		if c is GPUParticles3D and str(c.name).begins_with("Steam") and (c as GPUParticles3D).process_material is ParticleProcessMaterial:
			var pm: ParticleProcessMaterial = (c as GPUParticles3D).process_material
			var drift: float = pm.gravity.x / VfxLib.WIND.x if absf(VfxLib.WIND.x) > 0.001 else 1.0
			_steam.append({"pm": pm, "gy": pm.gravity.y, "drift": maxf(drift, 0.0)})
		if c.get_child_count() > 0:
			_collect_steam(c)

func _update_steam() -> void:
	var ks: float = VfxLib.WIND.length() / 4.0
	for s in _steam:
		var pm: ParticleProcessMaterial = s["pm"]
		if pm == null:
			continue
		pm.gravity = Vector3(0.0, float(s["gy"]), 0.0) + _cur * (ks * float(s["drift"]))
	if _wisp_pm != null:
		_wisp_pm.direction = Vector3(_cur.x, 0.0, _cur.z).normalized() if _cur.length() > 0.1 else Vector3.RIGHT
		_wisp_pm.initial_velocity_min = _cur.length() * 0.7
		_wisp_pm.initial_velocity_max = _cur.length() * 1.0

## Flache Dunstschwaden ueber der Strasse, die mit dem Wind ziehen (Hinweis fuer Richtung und Staerke).
func _build_wisps() -> void:
	var pm := ParticleProcessMaterial.new()
	VfxLib.smoke_pm(pm, 2.0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(90.0, 0.6, 9.0)
	pm.direction = Vector3(-1, 0, 0)
	pm.spread = 6.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3.ZERO
	pm.damping_min = 0.0
	pm.damping_max = 0.0
	pm.scale_min = 5.0
	pm.scale_max = 9.0
	pm.color_ramp = VfxLib.smoke_alpha_ramp(0.1, 0.25, 0.5)
	var mat := VfxLib.smoke_mat({
		"smoke_color": Color(0.78, 0.8, 0.84),
		"smoke_color_end": Color(0.74, 0.77, 0.82),
		"density": 0.6,
		"erosion": 0.55,
		"soft_dist": 3.0,
		"near_fade": 4.0,
	}, true)
	var p := VfxLib.make_particles(28, 16.0, pm, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.0
	p.randomness = 0.6
	p.preprocess = 16.0
	p.visibility_aabb = AABB(Vector3(-160, -4, -40), Vector3(320, 14, 80))
	p.name = "WindWisps"
	p.position = Vector3(0.0, 1.0, -136.0)
	add_child(p)
	p.emitting = true
	_wisps = p
	_wisp_pm = pm
