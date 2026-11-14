extends Node
## Blut-Effekte (Kind des VFX-Autoloads, Aufruf ueber VFX.spawn_blood).
## - Treffer: schneller, kleiner, gerichteter Spruehstoss: viele winzige gestreckte Tropfen + kurzer
##   roetlicher Nebel, Austrittsseite (entlang der Schussrichtung) kraeftig, Eintrittsseite schwach.
##   Ring-Pool aus MAX_FX Rigs mit je 5 GPUParticles3D (geteilte Materialien), Anzahl pro Treffer ueber
##   amount_ratio. Partikel laufen in Spielzeit -> passt zur Zeitlupe der Geschoss-Kamera.
## - Decals: Spritzer an Wand/Boden hinter dem Ziel (Raycast entlang der Schussrichtung), Tropfflecken
##   am Boden, langsam wachsende Lache unter Toten. Ringpuffer (MAX_DECALS).
## - Mehrere Aufrufe fuer denselben Treffer im selben Frame (Gegner + Waffe melden beide) werden
##   zusammengefasst; Richtung/Staerke vom informativsten Aufruf.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

const MAX_DECALS := 64
const MAX_FX := 12            # Pool-Groesse: gleichzeitig sichtbare Treffer-Effekte
const MERGE_DIST := 0.45
const SPLAT_TEX := ["res://assets/vfx/blood_splat_0.png", "res://assets/vfx/blood_splat_1.png",
	"res://assets/vfx/blood_splat_2.png", "res://assets/vfx/blood_splat_3.png"]
const DRIP_TEX := ["res://assets/vfx/blood_drip_0.png", "res://assets/vfx/blood_drip_1.png"]
const POOL_TEX := "res://assets/vfx/blood_pool.png"
const ORM_TEX := "res://assets/vfx/blood_orm.png"

@export var splat_lifetime: float = 150.0
@export var pool_lifetime: float = 300.0
@export var decals_enabled: bool = true

var _pending: Array[Dictionary] = []
var _flush_queued: bool = false
var _decals: Array[Decal] = []
var _rigs: Array[Node3D] = []   # Ring-Pool der Treffer-Effekte (je 5 GPUParticles3D, geteilte Materialien)
var _rig_next: int = 0
var _built: bool = false

var _drop_mat: ShaderMaterial
var _fine_mat: ShaderMaterial
var _mist_mat: ShaderMaterial
var _mist_entry_mat: ShaderMaterial
var _pm_exit: ParticleProcessMaterial
var _pm_fine: ParticleProcessMaterial
var _pm_entry: ParticleProcessMaterial
var _pm_mist: ParticleProcessMaterial
var _pm_mist_entry: ParticleProcessMaterial
var _quad: QuadMesh

## Statistik (Perf-Check / Tests)
var stat_hits: int = 0
var stat_merged: int = 0

func _ready() -> void:
	if not Events.enemy_killed.is_connected(_on_enemy_killed):
		Events.enemy_killed.connect(_on_enemy_killed)

# --- API ---------------------------------------------------------------------

## pos: Trefferpunkt (Eintritt), normal: Oberflaechennormale am Treffer, dir: Flugrichtung des
## Geschosses (ZERO = unbekannt -> -normal), strength: 1 normal, ~1.6 Kopftreffer, ~1.5 Scharfschuetze.
func spawn(pos: Vector3, normal: Vector3, dir: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	var n := normal.normalized() if normal.length() > 0.01 else Vector3.ZERO
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	for p in _pending:
		if (p["pos"] as Vector3).distance_to(pos) < MERGE_DIST:
			stat_merged += 1
			if d != Vector3.ZERO and (p["dir"] as Vector3) == Vector3.ZERO:
				p["dir"] = d
				p["pos"] = pos
			if (p["normal"] as Vector3) == Vector3.ZERO:
				p["normal"] = n
			p["strength"] = maxf(float(p["strength"]), strength)
			return
	_pending.append({"pos": pos, "normal": n, "dir": d, "strength": strength})
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()

## Alles sofort entfernen (Vorwaermen beendet, Levelwechsel).
func clear() -> void:
	for r: Node3D in _rigs:
		r.visible = false
		for p: GPUParticles3D in r.get_meta("em"):
			p.emitting = false
	for d: Variant in _decals:
		if is_instance_valid(d):
			(d as Node).queue_free()
	_decals.clear()
	_pending.clear()

func live_decals() -> int:
	return _decals.size()

## Anzahl gerade sichtbarer Treffer-Rigs (Pool-Groesse = MAX_FX)
func live_fx() -> int:
	var n := 0
	for r: Node3D in _rigs:
		if r.visible and ((r.get_meta("em") as Array)[0] as GPUParticles3D).emitting:
			n += 1
	return n

## false fuer Ziele ohne Blut: Fahrzeuge, Drohnen, Ziele mit Meta "surface" != flesh.
## Akzeptiert auch Hitboxen (get_enemy()).
static func is_bleeder(n: Node) -> bool:
	if n == null:
		return true
	if n.has_method("get_enemy"):
		var e: Variant = n.call("get_enemy")
		if e is Node:
			n = e as Node
	if n.is_in_group("vehicle"):
		return false
	var surf := str(n.get_meta("surface", "flesh"))
	if surf != "flesh" and surf != "blood":
		return false
	if str(n.get("enemy_type")) == "drone":
		return false
	var sc: Script = n.get_script() as Script
	if sc != null and sc.resource_path.get_file().contains("drone"):
		return false
	return true

# --- Treffer -------------------------------------------------------------------

func _flush() -> void:
	_flush_queued = false
	var list := _pending
	_pending = []
	for p in list:
		_hit(p["pos"], p["normal"], p["dir"], float(p["strength"]))

func _hit(pos: Vector3, normal: Vector3, dir: Vector3, strength: float) -> void:
	_build()
	stat_hits += 1
	if dir == Vector3.ZERO:
		dir = -normal if normal != Vector3.ZERO else _cam_forward()
	if normal == Vector3.ZERO:
		normal = -dir
	var s := clampf(strength, 0.5, 2.5)
	var head := s >= 1.55
	# Rumpftreffer liegen auf der Kollisionskapsel (r = 0.3 m um die Koerperachse), Ruecken/Brust des Modells
	# ~12-17 cm dahinter (gemessen mit _blood_shot.gd): Eintritt einruecken, Austritt ~38 cm hinter dem
	# Kapsel-Treffer. Kopf-Hitbox sitzt eng am Helm: kaum einruecken, Austritt ~20 cm.
	var entry := pos + dir * (0.03 if head else 0.12)
	var exit := pos + dir * (0.2 if head else 0.38)

	# Rig aus dem Ring-Pool (keine Node-Erzeugung pro Treffer); aeltester wird ggf. neu gestartet
	var rig: Node3D = _rigs[_rig_next]
	_rig_next = (_rig_next + 1) % _rigs.size()
	rig.visible = true
	var em: Array = rig.get_meta("em")
	var k := sqrt(s)
	var back := (normal - dir).normalized() if (normal - dir).length() > 0.01 else -dir
	# [Emitter, Anzahl, Ort, Richtung] - Austritt: grobe Tropfen, feiner Spruehnebel, roetliche Wolke
	# entlang der Schussrichtung; Eintritt: kleiner Rueckspritzer + Hauch von Nebel.
	_fire(em[0], 20.0 * s, exit, dir, k)
	_fire(em[1], 60.0 * s, exit, dir, k)
	_fire(em[2], 3.0 + 2.0 * s, exit, dir, k)
	_fire(em[3], 7.0 * s, entry, back, k)
	_fire(em[4], 2.0 + s, entry - dir * 0.02, back, k)
	if decals_enabled:
		_hit_decals(exit, dir, s)

func _fire(p: GPUParticles3D, count: float, at: Vector3, dir: Vector3, k: float) -> void:
	p.amount_ratio = clampf(count / float(p.amount), 0.02, 1.0)
	# Emissionsrichtung = lokales +Z; Skalierung k macht Tropfen groesser/schneller (Kopftreffer)
	p.global_transform = Transform3D(_basis_z(dir) * Basis.from_scale(Vector3.ONE * k), at)
	p.restart()

func _make_rig() -> Node3D:
	var rig := Node3D.new()
	rig.name = "BloodHit"
	add_child(rig)
	var em: Array = []
	# Puffergroessen = Maximum bei Staerke 2.5; pro Treffer ueber amount_ratio skaliert
	for spec: Array in [[_pm_exit, _drop_mat, 50, 0.8], [_pm_fine, _fine_mat, 150, 0.5], [_pm_mist, _mist_mat, 8, 0.75],
			[_pm_entry, _drop_mat, 18, 0.45], [_pm_mist_entry, _mist_entry_mat, 5, 0.55]]:
		var p := VfxLib.make_particles(int(spec[2]), float(spec[3]), spec[0], _quad, spec[1])
		p.randomness = 0.35
		p.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
		p.collision_base_size = 0.01
		rig.add_child(p)
		em.append(p)
	rig.set_meta("em", em)
	rig.visible = false
	return rig

static func _basis_z(z_dir: Vector3) -> Basis:
	var z := z_dir.normalized()
	var up := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := up.cross(z).normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z)

func _cam_forward() -> Vector3:
	var vp := get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp != null else null
	return -cam.global_transform.basis.z if cam != null else Vector3.FORWARD

# --- Decals --------------------------------------------------------------------

func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	var w: World3D = vp.find_world_3d() if vp != null else null
	return w.direct_space_state if w != null else null

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var sp := _space()
	if sp == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)   # nur Welt (Layer 1), keine Figuren
	q.hit_back_faces = false
	return sp.intersect_ray(q)

func _hit_decals(exit: Vector3, dir: Vector3, s: float) -> void:
	# Spritzer hinter dem Ziel: Wand oder Boden innerhalb weniger Meter entlang der Flugrichtung
	var reach := 2.6 + 1.2 * s
	var r := _ray(exit, exit + dir * reach)
	if not r.is_empty():
		var hp: Vector3 = r["position"]
		var hn: Vector3 = r["normal"]
		var dist := exit.distance_to(hp)
		var sz := clampf(0.45 + dist * 0.28, 0.45, 1.25) * sqrt(s)
		var fade := clampf(1.15 - dist / reach * 0.55, 0.45, 1.0)
		_later(dist / 9.0, func() -> void:
			_place(hp, hn, dir, SPLAT_TEX[randi() % SPLAT_TEX.size()], Vector3(sz * 0.8, 0.5, sz), splat_lifetime, fade))
	# Tropfen fallen auf den Boden: 1-3 Flecken unter/hinter dem Ziel
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.05 else Vector3.ZERO
	var drops := 1 + int(randf() * (1.5 + s))
	for i in drops:
		var o := exit + flat * randf_range(0.2, 1.1 * s) + Vector3(randf_range(-0.25, 0.25), 0.0, randf_range(-0.25, 0.25))
		var g := _ray(o + Vector3.UP * 0.3, o + Vector3.DOWN * 2.6)
		if g.is_empty():
			continue
		var gp: Vector3 = g["position"]
		var gn: Vector3 = g["normal"]
		var t := sqrt(2.0 * maxf(o.y - gp.y, 0.05) / 9.8)
		var dsz := randf_range(0.14, 0.3) * sqrt(s)
		_later(t, func() -> void:
			_place(gp, gn, dir, DRIP_TEX[randi() % DRIP_TEX.size()], Vector3(dsz, 0.4, dsz), splat_lifetime, 1.0))

func _later(t: float, cb: Callable) -> void:
	if t < 0.02:
		cb.call()
		return
	get_tree().create_timer(t).timeout.connect(cb)

## Decal aus dem Ringpuffer holen, ausrichten (Texturoben = Flugrichtung auf der Flaeche).
func _place(pos: Vector3, normal: Vector3, travel: Vector3, tex_path: String, size: Vector3, lifetime: float, alpha: float, tint: Color = Color.WHITE) -> Decal:
	var d := _take_decal()
	var y := normal.normalized()
	var t := travel - y * travel.dot(y)
	if t.length() < 0.15:
		t = VfxLib.basis_from_normal(y, randf() * TAU).z    # senkrecht getroffen: beliebige Drehung
	var z := -t.normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	d.global_transform = Transform3D(Basis(x, y, z), pos)
	d.texture_albedo = VfxLib.tex(tex_path)
	d.texture_normal = VfxLib.tex(tex_path.replace(".png", "_n.png"))
	d.texture_orm = VfxLib.tex(ORM_TEX)
	d.size = size
	d.modulate = Color(tint.r, tint.g, tint.b, 0.0)
	var tw := d.create_tween()
	d.set_meta("tw", tw)
	tw.tween_property(d, "modulate:a", alpha, 0.06)
	tw.tween_interval(lifetime)
	tw.tween_property(d, "modulate:a", 0.0, 5.0)
	return d

func _take_decal() -> Decal:
	var d: Decal = null
	while _decals.size() >= MAX_DECALS:
		var old: Variant = _decals.pop_front()
		if is_instance_valid(old):
			d = old as Decal
			break
	if d != null:
		for key in ["tw", "tw_grow"]:
			if not d.has_meta(key):
				continue
			var tw: Variant = d.get_meta(key)
			if tw is Tween and (tw as Tween).is_valid():
				(tw as Tween).kill()
		if d.has_meta("tw_grow"):
			d.remove_meta("tw_grow")
	else:
		d = Decal.new()
		d.cull_mask = 1               # nur Welt; Figuren/Partikel bleiben sauber
		d.upper_fade = 0.15
		d.lower_fade = 0.3
		d.normal_fade = 0.3
		d.albedo_mix = 1.0
		d.distance_fade_enabled = true
		d.distance_fade_begin = 45.0
		d.distance_fade_length = 15.0
		add_child(d)
	_decals.append(d)
	return d

# --- Lache unter Toten -----------------------------------------------------------

func _on_enemy_killed(enemy: Node) -> void:
	if not decals_enabled or not (enemy is Node3D) or bool(enemy.get_meta("no_blood_pool", false)) or not is_bleeder(enemy):
		return
	var eid := enemy.get_instance_id()
	# Koerper erst liegen lassen (Sterbeanimation/Ragdoll), dann Lache unter dem Becken
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		var e := instance_from_id(eid) as Node3D
		if e == null:
			return
		var c := _body_center(e)
		var g := _ray(c + Vector3.UP * 0.6, c + Vector3.DOWN * 2.5)
		if g.is_empty():
			return
		var gp: Vector3 = g["position"]
		var gn: Vector3 = g["normal"]
		if gn.y < 0.6:
			return
		var full := randf_range(1.1, 1.6)
		var d := _place(gp, gn, Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), POOL_TEX, Vector3(0.22, 0.5, 0.22), pool_lifetime, 0.97, Color(0.6, 0.45, 0.42))
		# langsam wachsen (eigener Tween, laeuft parallel zum Ein-/Ausblenden)
		var grow := d.create_tween()
		grow.tween_property(d, "size", Vector3(full, 0.5, full * randf_range(0.75, 1.0)), 24.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		d.set_meta("tw_grow", grow))

func _body_center(e: Node3D) -> Vector3:
	var best: Node3D = null
	for b in e.find_children("*", "PhysicalBone3D", true, false):
		var nm := String(b.name).to_lower()
		if nm.contains("hip") or nm.contains("pelvis") or nm.ends_with("_body") or nm.contains("abdomen"):
			best = b
			break
		if best == null and (nm.contains("spine") or nm.contains("torso")):
			best = b
	if best != null:
		return best.global_position
	# einfacher Ragdoll aus RigidBody3D-Teilen (enemy.gd ohne Soldaten-Rig): Schwerpunkt
	var acc := Vector3.ZERO
	var m := 0.0
	for rb in e.find_children("*", "RigidBody3D", true, false):
		acc += (rb as RigidBody3D).global_position * (rb as RigidBody3D).mass
		m += (rb as RigidBody3D).mass
	if m > 0.0:
		return acc / m
	for sk in e.find_children("*", "Skeleton3D", true, false):
		var skel := sk as Skeleton3D
		for nm in ["Hips", "mixamorig_Hips", "pelvis", "Pelvis", "hips"]:
			var bi := skel.find_bone(nm)
			if bi >= 0:
				return skel.global_transform * skel.get_bone_global_pose(bi).origin
	return e.global_position

# --- Ressourcen (einmal, geteilt) ----------------------------------------------------

func _build() -> void:
	if _built:
		return
	_built = true
	_quad = VfxLib.quad(1.0)
	var drop_tex := VfxLib.tex("res://assets/vfx/blood_drop.png")
	# Farben sind source_color (sRGB): dunkles venoes/arterielles Rot, Nebel heller (feine Troepfchen streuen)
	_drop_mat = VfxLib.shader_mat("blood_drop", {"drop_tex": drop_tex, "blood_color": Color(0.4, 0.018, 0.016),
		"stretch": 6.0, "stretch_end": 2.2, "roughness_v": 0.14})
	_fine_mat = VfxLib.shader_mat("blood_drop", {"drop_tex": drop_tex, "blood_color": Color(0.5, 0.04, 0.035),
		"stretch": 5.0, "stretch_end": 2.0, "roughness_v": 0.3})
	_mist_mat = VfxLib.smoke_mat({"smoke_color": Vector3(0.62, 0.1, 0.09), "smoke_color_end": Vector3(0.58, 0.2, 0.18),
		"density": 1.6, "soft_dist": 0.06, "soft_size_factor": 0.2, "erosion": 0.6, "frame_span": 3.0,
		"self_shadow": 0.12, "near_fade": 0.3, "close_cull": 0.5, "scatter": 0.6, "wrap": 1.0,
		"glow_color": Color(0.62, 0.07, 0.06), "glow": 0.35, "glow_decay": 1.5}, true)   # Eigenleuchten: Rot statt Grau im Gegenlicht

	_mist_entry_mat = _mist_mat.duplicate() as ShaderMaterial
	_mist_entry_mat.set_shader_parameter("density", 1.4)

	# Tropfen (schnell, mit Schwerkraft, verschwinden bei Bodenkontakt) - schmale Striche, keine Kugeln
	_pm_exit = _drop_pm(13.0, 2.5, 8.0, 0.0035, 0.01, 0.8)
	# feiner Spruehnebel aus Kleinsttropfen (stark gebremst, kurzlebig)
	_pm_fine = _drop_pm(20.0, 1.5, 6.5, 0.0015, 0.0045, 5.0)
	_pm_fine.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.9)], [0.45, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0.0)]])
	# Rueckspritzer am Eintritt (schwach, kurz)
	_pm_entry = _drop_pm(30.0, 0.4, 1.6, 0.002, 0.006, 2.0)

	_pm_mist = _mist_pm(24.0, 0.8, 2.8, 0.14, 0.24)
	_pm_mist_entry = _mist_pm(40.0, 0.15, 0.7, 0.12, 0.2)

	for i in MAX_FX:
		_rigs.append(_make_rig())

func _drop_pm(spread: float, v0: float, v1: float, s0: float, s1: float, damp: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.03
	pm.direction = Vector3(0, 0, 1)
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.gravity = Vector3(0, -9.8, 0)
	pm.damping_min = damp * 0.6
	pm.damping_max = damp
	pm.scale_min = s0
	pm.scale_max = s1
	pm.particle_flag_align_y = true
	pm.scale_curve = VfxLib.curve_tex([[0.0, 1.0], [0.7, 0.85], [1.0, 0.3]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 1)], [0.75, Color(1, 1, 1, 0.9)], [1.0, Color(1, 1, 1, 0.0)]])
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	return pm

func _mist_pm(spread: float, v0: float, v1: float, s0: float, s1: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.04
	pm.direction = Vector3(0, 0, 1)
	pm.spread = spread
	pm.initial_velocity_min = v0
	pm.initial_velocity_max = v1
	pm.damping_min = 3.0
	pm.damping_max = 5.0
	pm.gravity = Vector3(0, -0.6, 0)
	VfxLib.smoke_pm(pm, 25.0)
	pm.scale_min = s0
	pm.scale_max = s1
	# schnell aufbluehen, dann langsam verdunsten
	pm.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.6], [0.12, 1.7], [0.5, 2.6], [1.0, 3.3]])
	pm.color_ramp = VfxLib.ramp([[0.0, Color(1, 1, 1, 0.0)], [0.03, Color(1, 1, 1, 0.9)], [0.25, Color(1, 1, 1, 0.6)],
		[0.6, Color(1, 1, 1, 0.22)], [1.0, Color(1, 1, 1, 0.0)]])
	return pm
