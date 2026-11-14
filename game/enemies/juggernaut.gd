extends "res://game/enemies/armored_enemy.gd"
## Juggernaut-Endgegner: Bombenschutzanzug, Rotations-MG mit Anlaufen (faire Vorwarnung), kurze Granatwuerfe.
## Schwachstellen: Visier (bricht, danach volle Kopftreffer) und der Tornister auf dem Ruecken (platzt -> Taumeln).
## Taumelt bei 75/50/25 % HP (Taumeln = Trefferfenster, Schaden x stagger_mult). Rakete = 1/4 HP.
## Boss-Leiste ueber armor_hud.gd; die Statuszeile nennt immer die aktuelle Schwachstelle, und wer nur
## auf die Panzerung schiesst, bekommt nach einigen Abprallern einen Hinweis eingeblendet.

const GRENADE_SCENE: PackedScene = preload("res://game/weapons/grenade.tscn")

@export_group("Juggernaut")
@export var suit_pass: float = 0.2            ## Panzerplatten/Helm: fast alles bleibt haengen
@export var padded_pass: float = 0.3          ## gepolsterter Anzug (Arme/Beine/Seiten)
@export var chest_open_pass: float = 0.4       ## Brust nach abgefallener Brustplatte
@export var pack_mult: float = 1.5             ## Tornister: Schwachstelle
@export var back_open_pass: float = 0.5        ## Ruecken nach geplatztem Tornister
@export var face_mult: float = 2.5             ## Kopftreffer nach gebrochenem Visier
@export var rocket_fraction: float = 0.25
@export var pack_burst_damage: float = 150.0
@export var stagger_mult: float = 1.5          ## Schaden waehrend des Taumelns (klares Trefferfenster)
@export var spinup_time: float = 1.1
@export var grenade_cooldown: float = 9.0
@export var grenade_min_dist: float = 7.0
@export var grenade_max_dist: float = 14.0

var boss_engaged: bool = false
var _stagger_t: float = 0.0
var _stagger_marks: Array[float] = [0.75, 0.5, 0.25]
var _rocket_frame: int = -1
var _last_fire_age: float = -100.0
var _spin: float = 0.0
var _spinning_up: float = 0.0
var _barrels: Node3D = null
var _barrel_glow: StandardMaterial3D = null
var _step_dist: float = 0.0
var _step_i: int = 0
var _grenade_cd: float = 5.0
var _hud_set: bool = false
var _pack_burst_done: bool = false
var _deflect_streak: int = 0                   ## Abpraller des Spielers in Folge (fuer den Schwachstellen-Hinweis)
var _hint_cd: float = 0.0
var _jtracer_mesh: QuadMesh = null
var _jtracer_mat: ShaderMaterial = null

func _ready() -> void:
	armor_kind = "juggernaut"
	_helmet_c = AK.J_HC
	_helmet_r = 0.212
	set_meta("voice_pitch", 0.74)
	super._ready()
	add_to_group("boss")

# ---------------------------------------------------------------- Aufbau

func _strip_default_gear() -> void:
	# Juggernaut: komplettes Standard-Kit + die Primitiv-Teile des MG-Schuetzen weg (Anzug ersetzt alles),
	# nur die Waffe (BA_Wrist_R/Weapon) und die Kopf-Hitbox bleiben.
	var sk := _soldier.skeleton
	for c in sk.get_children():
		if not (c is BoneAttachment3D) or str(c.name).begins_with("BA_Armor_"):
			continue
		for n in c.get_children():
			if n is MeshInstance3D or (n is Node3D and str(n.name).begins_with("Kit_")):
				for m in n.find_children("*", "GeometryInstance3D", true, false):
					_soldier._meshes.erase(m)
				if n is GeometryInstance3D:
					_soldier._meshes.erase(n)
				n.queue_free()
	# Uniform (Tarnstoff) unter dem Anzug in Anzugfarbe: Spalte an Knien/Hueften zeigen kein Tarnmuster
	var mats: Dictionary = _soldier.get_meta("mats", {})
	var suit := StandardMaterial3D.new()
	var sc: Color = AK.colors(faction)["suit"]
	suit.albedo_color = Color(sc.r, sc.g, sc.b) * 0.8
	suit.roughness = 0.92
	for c in sk.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var cur := mi.get_surface_override_material(s)
				if cur != null and (cur == mats.get("Swat") or cur == mats.get("Skin")):
					mi.set_surface_override_material(s, suit)
	_build_barrels()

## Rotations-Laufbuendel vor dem MG (dreht beim Anlaufen/Feuern sichtbar hoch).
func _build_barrels() -> void:
	var w: Node3D = _soldier.weapon
	if w == null or _soldier.muzzle == null:
		return
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.13, 0.13, 0.14)
	steel.metallic = 0.85
	steel.roughness = 0.4
	_barrel_glow = StandardMaterial3D.new()
	_barrel_glow.albedo_color = Color(0.2, 0.18, 0.16)
	_barrel_glow.metallic = 0.7
	_barrel_glow.roughness = 0.35
	_barrel_glow.emission_enabled = true
	_barrel_glow.emission = Color(1.0, 0.35, 0.08)
	_barrel_glow.emission_energy_multiplier = 0.0
	_barrels = Node3D.new()
	_barrels.name = "Barrels"
	_barrels.position = _soldier.muzzle.position + Vector3(0, 0, 0.16)
	w.add_child(_barrels)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0085
	cyl.bottom_radius = 0.0085
	cyl.height = 0.42
	cyl.radial_segments = 8
	cyl.rings = 1
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0095
	tip.bottom_radius = 0.0095
	tip.height = 0.05
	tip.radial_segments = 8
	tip.rings = 1
	for i in 6:
		var a := TAU * float(i) / 6.0
		var off := Vector3(cos(a), sin(a), 0.0) * 0.024
		var b := MeshInstance3D.new()
		b.mesh = cyl
		b.material_override = steel
		b.rotation.x = PI * 0.5
		b.position = off
		_barrels.add_child(b)
		var t := MeshInstance3D.new()
		t.mesh = tip
		t.material_override = _barrel_glow
		t.rotation.x = PI * 0.5
		t.position = off + Vector3(0, 0, -0.19)
		_barrels.add_child(t)
	for z: float in [-0.12, 0.1]:
		var ring := MeshInstance3D.new()
		var rm := CylinderMesh.new()
		rm.top_radius = 0.04
		rm.bottom_radius = 0.04
		rm.height = 0.022
		rm.radial_segments = 14
		ring.mesh = rm
		ring.material_override = steel
		ring.rotation.x = PI * 0.5
		ring.position.z = z
		_barrels.add_child(ring)
	for c in _barrels.get_children():
		_soldier._meshes.append(c as GeometryInstance3D)
	_soldier.muzzle.position.z -= 0.08

func _piece_integrity(id: String) -> float:
	match id:
		"chest_plate": return 400.0
		"pack": return 120.0
		"visor": return 90.0
	return INF

func _build_zones() -> void:
	super._build_zones()
	# Anzug ist dicker als der nackte Koerper: Rumpf-Box groesser + tiefer nach hinten (Tornister)
	for z: Dictionary in _zones:
		if z["id"] == "torso":
			z["c"] = Vector3(0.004, 1.27, 0.05)
			z["h"] = Vector3(0.27, 0.24, 0.26)
		elif z["id"] == "pelvis":
			z["h"] = Vector3(0.23, 0.14, 0.17)

# ---------------------------------------------------------------- Schadensmodell

func _resolve(loc: Dictionary, amount: float, headshot: bool) -> Dictionary:
	var r := _resolve_suit(loc, amount, headshot)
	if _stagger_t > 0.0:
		r["dmg"] = float(r["dmg"]) * stagger_mult
	if _last_src_player:
		if bool(r["deflect"]):
			_deflect_streak += 1
			if _deflect_streak >= 6 and _hint_cd <= 0.0:
				_deflect_streak = 0
				_hint_cd = 10.0
				_hud_message(_weak_hint(), true)
		else:
			_deflect_streak = 0
	return r

## Aktuelle Schwachstelle in Worten (Statuszeile der Boss-Leiste, Hinweis nach Abprallern).
func _weak_hint() -> String:
	if _intact("visor"):
		return "PANZERUNG HÄLT – ZIEL: VISIER" + (" ODER TORNISTER" if _intact("pack") else "")
	if _intact("pack"):
		return "PANZERUNG HÄLT – ZIEL: KOPF ODER TORNISTER"
	return "PANZERUNG HÄLT – ZIEL: KOPF"

func _resolve_suit(loc: Dictionary, amount: float, headshot: bool) -> Dictionary:
	var piece: String = loc["piece"]
	var zone: String = loc["zone"]
	var r := {"dmg": amount * padded_pass, "deflect": false, "blood": false, "head": false, "piece": "", "zone": zone if zone != "" else piece}
	if headshot:
		if piece == "visor":
			return _plate_hit(r, "visor", amount, visor_pass)
		if piece == "face":
			r["dmg"] = amount * face_mult
			r["head"] = true
			r["blood"] = true
			return r
		return _deflect(r, amount * suit_pass)
	match piece:
		"pack":
			r["dmg"] = amount * pack_mult
			r["piece"] = "pack"
			r["zone"] = "pack"
			return r
		"chest_plate":
			return _plate_hit(r, "chest_plate", amount, suit_pass)
		"":
			pass
		_:
			if piece.begins_with("arm_") or piece.begins_with("thigh_") or piece.begins_with("shin_") \
					or piece.begins_with("forearm_") or piece == "groin":
				return _deflect(r, amount * suit_pass)
	if zone == "torso":
		var p: Vector3 = loc["p"]
		var az := atan2(p.x - 0.004, p.z - 0.05)
		if absf(az) > 2.3:
			if _intact("pack"):
				r["dmg"] = amount * pack_mult
				r["piece"] = "pack"
				r["zone"] = "pack"
				return r
			r["dmg"] = amount * back_open_pass
			r["blood"] = true
			return r
		if absf(az) < 0.9 and p.y > 1.12:
			if _intact("chest_plate"):
				return _plate_hit(r, "chest_plate", amount, suit_pass)
			r["dmg"] = amount * chest_open_pass
			r["blood"] = true
			return r
	return r

func _deflect(r: Dictionary, dmg: float) -> Dictionary:
	r["dmg"] = dmg
	r["deflect"] = true
	r["blood"] = false
	return r

func _resolve_explosion(amount: float) -> Dictionary:
	var d := amount * explosion_mult
	if _rocket_frame == Engine.get_physics_frames():
		d = 0.0   # Volltreffer wurde schon als 1/4 HP verbucht
	return {"dmg": d, "deflect": false, "blood": false, "head": false, "piece": "", "zone": "explosion"}

func _special_hit(amount: float, _source: Node, _pos: Vector3, _normal: Vector3, _headshot: bool) -> Dictionary:
	if amount >= 500.0:   # Raketen-Volltreffer (auch ueber die Kopf-Hitbox)
		return _rocket_result()
	return {}

func _rocket_result() -> Dictionary:
	_rocket_frame = Engine.get_physics_frames()
	_stagger(2.2)
	_explosion_scuff(220.0)
	return {"dmg": max_health * rocket_fraction + 0.5, "deflect": false, "blood": false, "head": false, "piece": "", "zone": "rocket"}

## Panzerfaust-Volltreffer: 1/4 der Lebenspunkte, Explosionsschaden im selben Frame entfaellt.
func rocket_hit(source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if state == State.DEAD:
		return
	_last_src_player = source != null and source.is_in_group("player")
	var res := _rocket_result()
	last_zone = "rocket"
	last_piece = ""
	_apply_result(res, source, hit_position, hit_normal)

func _after_damage(dmg: float, _res: Dictionary) -> void:
	if dmg > 0.0 and _hud_set:
		var h := AHUD.get_hud(self)
		if h != null:
			h.call("boss_hit")
	_engage()
	var frac := health / maxf(max_health, 1.0)
	while not _stagger_marks.is_empty() and frac <= _stagger_marks[0] and health > 0.0:
		_stagger_marks.pop_front()
		_stagger(2.2)
		_hud_message("ER TAUMELT – JETZT DRAUF!", _last_src_player)
		_bark("hit", 1.0, true)

func _on_piece_broken(id: String) -> void:
	if id == "pack" and not _pack_burst_done:
		_pack_burst_done = true
		call_deferred("_pack_burst")
	elif id == "chest_plate":
		_stagger(1.2)

func _pack_pos() -> Vector3:
	return global_position + Vector3.UP * 1.3 * _soldier.vis_scale + global_transform.basis.z * 0.3

func _pack_burst() -> void:
	if state == State.DEAD:
		return
	var p := _pack_pos()
	VFX.spawn_explosion(p, 0.7)
	_play_sfx("jugg_pack_burst", p)
	_hud_message("TORNISTER GETROFFEN", _last_src_player)
	_stagger(2.5)
	health -= pack_burst_damage
	Events.enemy_damaged.emit(self, pack_burst_damage)
	_explosion_scuff(160.0)
	if _hud_set:
		var h := AHUD.get_hud(self)
		if h != null:
			h.call("boss_hit")
	if health <= 0.0:
		_die()
		return
	_after_damage(0.0, {})

func _stagger(t: float) -> void:
	_stagger_t = maxf(_stagger_t, t)
	_burst_left = 0
	_spinning_up = 0.0
	_flinch = 1.0

func _engage() -> void:
	if boss_engaged or state == State.DEAD:
		return
	boss_engaged = true
	if not _hud_set:
		var h := AHUD.get_hud(self)
		if h != null:
			var ticks: Array[float] = [0.75, 0.5, 0.25]
			h.call("set_boss", self, "JUGGERNAUT", ticks)
			_hud_set = true

func boss_status() -> String:
	var s: Array[String] = []
	if _stagger_t > 0.0:
		s.append("TAUMELT – SCHADEN x%s" % str(snappedf(stagger_mult, 0.1)))
	if not _intact("visor"):
		s.append("VISIER OFFEN – KOPF")
	else:
		s.append("SCHWACHSTELLE: VISIER")
	if not _intact("pack"):
		s.append("TORNISTER ZERSTÖRT")
	else:
		s.append("TORNISTER (RÜCKEN)")
	return " · ".join(s)

## Bots: immer auf den Kopf (Visier ist die erste Schwachstelle von vorn).
func get_aim_point() -> Vector3:
	if _head_hitbox != null:
		return _head_hitbox.global_position
	return global_position + Vector3.UP * 1.7

# ---------------------------------------------------------------- Verhalten

func _tick_state(delta: float) -> void:
	if state != State.IDLE and state != State.DEAD:
		_engage()
	_grenade_cd -= delta
	_hint_cd -= delta
	if _stagger_t > 0.0:
		_stagger_t -= delta
		_burst_left = 0
		_desired_velocity = Vector3.ZERO
		if fmod(_stagger_t, 0.7) < delta:
			_flinch = 1.0
		return
	if _spinning_up > 0.0:
		_spinning_up -= delta
	super._tick_state(delta)
	_maybe_grenade()

func _maybe_grenade() -> void:
	if _grenade_cd > 0.0 or not _los or _player == null or _burst_left > 0:
		return
	if state != State.ATTACK and state != State.ADVANCE:
		return
	var d := _flat_dist(global_position, _player.global_position)
	if d < grenade_min_dist or d > grenade_max_dist:
		return
	_grenade_cd = grenade_cooldown * rng.randf_range(0.9, 1.3)
	var g: RigidBody3D = GRENADE_SCENE.instantiate()
	g.call("setup", self)
	_effects_root().add_child(g)
	var from := global_position + Vector3.UP * 1.7 + (-global_transform.basis.z) * 0.5
	g.global_position = from
	var tgt := _player.global_position + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(-1.2, 1.2))
	# ballistisch: Flugzeit ~ 0.9-1.2 s
	var tt := clampf(d / 11.0, 0.8, 1.3)
	var g_acc: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var v := (tgt - from) / tt
	v.y = (tgt.y - from.y) / tt + 0.5 * g_acc * tt
	g.linear_velocity = v
	g.angular_velocity = _rand_spin(6.0)
	_bark("grenade", 1.0, true)

func _start_burst() -> void:
	super._start_burst()
	if _age - _last_fire_age > 1.6:
		# Anlaufen: faire Vorwarnung (Ton + gluehende Laeufe), erst danach Feuer
		_shot_timer = spinup_time
		_spinning_up = spinup_time
		_play_sfx("jugg_spinup")

func _fire_shot() -> void:
	super._fire_shot()
	_last_fire_age = _age

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.6 or not is_inside_tree():
		return
	if _jtracer_mesh == null:
		_jtracer_mesh = QuadMesh.new()
		_jtracer_mat = ShaderMaterial.new()
		_jtracer_mat.shader = load("res://game/vfx/shaders/tracer.gdshader")
		_jtracer_mat.set_shader_parameter("length_m", 2.6)
		_jtracer_mat.set_shader_parameter("width_m", 0.022)
		_jtracer_mat.set_shader_parameter("glow_color", Color(1.0, 0.42, 0.1))
		_jtracer_mat.set_shader_parameter("energy", 6.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _jtracer_mesh
	mi.material_override = _jtracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3.0
	_effects_root().add_child(mi)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, length / tracer_speed)
	tw.tween_callback(mi.queue_free)

func _animate(delta: float) -> void:
	super._animate(delta)
	var firing := _burst_left > 0 and _spinning_up <= 0.0
	var want := 1.0 if (firing or _spinning_up > 0.0) else 0.0
	_spin = move_toward(_spin, want, delta * (1.0 / spinup_time if want > 0.0 else 0.45))
	if _barrels != null:
		_barrels.rotate_object_local(Vector3.BACK, _spin * 38.0 * delta)
	if _barrel_glow != null:
		var heat := clampf(_spin * 1.2 - 0.2, 0.0, 1.0)
		_barrel_glow.emission_energy_multiplier = heat * heat * 3.5
	# schwere Schritte
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp > 0.3 and is_on_floor():
		_step_dist += sp * delta
		if _step_dist > 0.95:
			_step_dist = 0.0
			_step_i += 1
			_play_sfx("jugg_step_%d" % (1 + _step_i % 3))

# ---------------------------------------------------------------- Tod

func _on_death() -> void:
	boss_engaged = false
	_play_sfx("jugg_collapse")
	if _intact("pack") and not _pack_burst_done:
		# Tornister geht beim Zusammenbruch hoch (nur Optik, kein Flaechenschaden)
		_pack_burst_done = true
		var p := _pack_pos()
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			VFX.spawn_explosion(p, 0.8)
			VFX.play_sfx_3d("jugg_pack_burst", p, 2.0))
	super._on_death()
