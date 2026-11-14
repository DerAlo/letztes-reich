extends AnimatableBody3D
## Mission "Kräne", Teil B: Gegnerboot (Garde-Schnellboot mit Bug-MG) oder Webers Fluchtboot.
## Faehrt relativ zur RailRide-Bahn des Spielers (gleiche Kurve, Versatz in Bahnmetern + seitlich + Schlaengeln),
## damit es auch bei Halten und Neustarts sauber mitzieht. role "weber": unverwundbar, Gruppe "no_shoot",
## Treffer meldet das Level (on_weber_boat_hit), haelt Vorsprung, faehrt im Finale frei zum Frachter.
##
## Bewegung (gegen das fruehere Zucken): Das Boot folgt seinem Bahn-Sollpunkt ueber eine kritisch gedaempfte
## Feder (Position + Geschwindigkeit), der Kurs kommt aus der geglaetteten Geschwindigkeit mit begrenzter
## Drehrate, Krängung aus der Drehrate. Kein Blick auf einen Vorhaltepunkt mehr (der kippte am Bahnende und
## mit der Schlaengel-Phase im Sekundentakt um).
##
## Schwachstelle: Der MG-Schuetze am Bug hat eine eigene Trefferzone - ein Treffer schaltet ihn aus, das Boot
## dreht steuerlos ab und gilt als erledigt. Wird das Boot beschossen, weicht es seitlich aus.

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const FX := preload("res://game/systems/rail_ride_fx.gd")
const Models := preload("res://game/levels/hafen_models.gd")
const Night := preload("res://game/levels/hafen_night.gd")   ## glow_light(): runde Positionslichter
## Knotenname des Bug-MG im Garde-Modell (JM-16 Zolfaqar: DShK am Bug) und Hoehe Lafette -> Deck
const MG_NODE := "dshk_007"
const MG_STAND := 0.95
## Garde-Uniform (wie C_GARDE in hafen.gd) und Abstand der Figur hinter dem Schuetzen-Anker (Haende an den Griffen)
const GARDE_COLS := [Color(0.42, 0.43, 0.44), Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13)]
const PUPPET_BACK := -0.12

signal gunner_killed

var role: String = "garde"
var ride: Node3D = null
var level_ref: Node = null
var max_health: float = 150.0
var health: float = 150.0
var offset_s: float = 120.0          ## Bahnmeter vor (+) / hinter (-) dem Spieler
var target_offset: float = 45.0      ## naehert sich auf diesen Versatz
var approach_rate: float = 6.0       ## m/s Annaeherung
var lateral: float = 18.0            ## seitlich (+ = rechts)
var lateral_to: float = INF          ## gesetzt: wechselt waehrend der Fahrt auf diese Seite (kreuzt den Kurs)
var lateral_rate: float = 2.2        ## m/s Seitenwechsel
var weave_amp: float = 4.0
var weave_freq: float = 0.07         ## Hz - ruhiges, weites Schlaengeln
var turn_rate_deg: float = 42.0      ## max. Drehrate des Rumpfs
var follow_omega: float = 1.6        ## Federsteifigkeit der Bahnverfolgung (1/s)
var hit_chance: float = 0.12
var round_damage: float = 12.0       ## vor vehicle_damage_scale der RailRide (0.5) -> 6
var burst_rounds: int = 8
var free_target: Vector3 = Vector3.INF   ## gesetzt: faehrt frei dorthin (Finale)
var free_speed: float = 12.0
var dead: bool = false
var gunner_alive: bool = true

var _t: float = 0.0
var _wt: float = 0.0
var _ph: float = 0.0
var _burst_cd: float = 3.0
var _burst_left: int = 0
var _shot_cd: float = 0.0
var _burst_lethal: bool = true       ## false = Sperrfeuer ohne Treffer (Level begrenzt gleichzeitiges Scharffeuer)
var _gun: Node3D
var _gunner: Node3D
var _muzzle: Marker3D
var _flash: Node3D
var _spray: Array[GPUParticles3D] = []
var _engine: AudioStreamPlayer3D
var _motion: Node3D
var _sink_t: float = 0.0
var _pos := Vector3.INF
var _vel := Vector3.ZERO
var _tgt_prev := Vector3.INF
var _tgt_vel := Vector3.ZERO
var _yaw: float = 0.0
var _yaw_rate: float = 0.0
var _bank: float = 0.0
var _pitch: float = 0.0
var _swerve: float = 0.0
var _swerve_goal: float = 0.0
var _swerve_t: float = 0.0
var _swerve_cd: float = 0.0
var _spin: float = 0.0
var velocity := Vector3.ZERO
var _hull_size := Vector3(2.6, 1.8, 7.5)   ## Kollisionsbox Rumpf (Modell: aus der Modellgroesse)
var _gz_center := Vector3(0, 2.15, -1.4)   ## Trefferzone MG-Schuetze (lokal zum Boot)
var _gz_size := Vector3(1.1, 1.3, 1.1)
var _puppet: CharacterBody3D = null
var _hull_y := 0.7                          ## Mitte der Rumpf-Kollisionsbox (lokal y)

func _ready() -> void:
	health = max_health
	sync_to_physics = false
	collision_layer = VF.LAYER_ENEMY
	collision_mask = 0
	set_meta("surface", "metal")
	add_to_group("vehicle")
	if role == "weber":
		add_to_group("no_shoot")
		set_meta("avoid_radius", 5.0)
	else:
		add_to_group("enemy")
		add_to_group("damageable")
	_ph = randf() * TAU
	_wt = randf() * 10.0
	_yaw = rotation.y
	_build()
	if role != "weber":
		set_meta("aim_offset", _gz_center + Vector3(0, -0.15, 0))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = _hull_size
	cs.shape = bs
	cs.position = Vector3(0, _hull_y, 0)
	add_child(cs)
	if role != "weber":
		# Trefferzone MG-Schuetze (ueber der Rumpfkante)
		var gs := CollisionShape3D.new()
		var gb := BoxShape3D.new()
		gb.size = _gz_size
		gs.shape = gb
		gs.position = _gz_center
		add_child(gs)
	_engine = VF.loop_player(self, "hafen_boat_engine", 14.0, 300.0, -4.0)
	_burst_cd = randf_range(2.0, 3.5)

func _build() -> void:
	_motion = Node3D.new()
	add_child(_motion)
	var hull_c := Color(0.22, 0.23, 0.24) if role != "weber" else Color(0.82, 0.82, 0.8)
	var hull := VF.mat("hb_hull_" + role, hull_c, 0.55, 0.2)
	var dark := VF.mat("hb_dark", Color(0.08, 0.08, 0.09), 0.7, 0.3)
	var slot := "weber_boat" if role == "weber" else "garde_boat"
	var mdl := Models.attach(_motion, slot, 8.0)
	var mlen := 8.0
	if mdl != null:
		var mab: AABB = mdl.get_meta("aabb", AABB())
		mlen = clampf(mab.size.z, 6.0, 14.0)
		_hull_size = Vector3(clampf(mab.size.x * 0.9, 2.2, 3.4), 2.0, mlen * 0.92)
		_hull_y = 0.6
	if mdl == null:
		var glass := VF.glass_mat()
		VF.mesh_node(_motion, VF.box(Vector3(2.5, 0.9, 6.0)), hull, Vector3(0, 0.25, 0.4))
		VF.mesh_node(_motion, VF.prism(Vector3(2.5, 2.2, 0.9), 0.5), hull, Vector3(0, 0.25, -3.5), Vector3(-90, 0, 0))
		VF.mesh_node(_motion, VF.box(Vector3(2.3, 0.15, 6.4)), dark, Vector3(0, 0.75, 0.2))
		VF.mesh_node(_motion, VF.box(Vector3(1.6, 0.9, 1.4)), hull, Vector3(0, 1.25, 0.6))
		VF.mesh_node(_motion, VF.box(Vector3(1.5, 0.5, 0.06)), glass, Vector3(0, 1.45, -0.12))
		VF.mesh_node(_motion, VF.box(Vector3(0.7, 0.7, 0.6)), dark, Vector3(0, 0.95, 3.1))
		# Seitenlichter (rot backbord, gruen steuerbord): kleine Kugeln + runder Lichtpunkt statt Leuchtwuerfel
		var nav_r := VF.mat("hb_nav_r", Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0.1, 0.1), 2.5)
		var nav_g := VF.mat("hb_nav_g", Color(0.1, 1, 0.2), 0.4, 0.0, Color(0.1, 1, 0.2), 2.5)
		VF.mesh_node(_motion, VF.sphere(0.06), nav_r, Vector3(-0.85, 1.75, 0.6))
		VF.mesh_node(_motion, VF.sphere(0.06), nav_g, Vector3(0.85, 1.75, 0.6))
		Night.glow_light(_motion, Vector3(-0.85, 1.75, 0.6), Color(1, 0.1, 0.08), 3.0, 0.3)
		Night.glow_light(_motion, Vector3(0.85, 1.75, 0.6), Color(0.1, 1, 0.25), 3.0, 0.3)
	if role != "weber":
		# Bug-MG mit Schuetze (Puppe) - Spielmechanik, bleibt auch bei eingesetztem Modell.
		# Hat das Modell ein eigenes Bug-MG (MG_NODE), wird genau dieses schwenkbar gemacht (Drehpunkt am
		# Lafettenfuss), sonst ein einfaches Kasten-MG gebaut.
		_gun = Node3D.new()
		_gun.position = Vector3(0, 1.2, -1.9)
		_motion.add_child(_gun)
		var mg: Node3D = mdl.find_child(MG_NODE, true, false) as Node3D if mdl != null else null
		var muzzle_pos := Vector3(0, 0.1, -1.2)
		var gunner_pos := Vector3(0, 0, 0.55)
		var stand := 0.75      # Pivot -> Deck (Fuesse des Schuetzen)
		if mg != null:
			var pxf := _motion.global_transform.affine_inverse() * (mg.get_parent() as Node3D).global_transform
			var ga := Models._aabb(mg, pxf)
			var pivot := Vector3(ga.get_center().x, ga.position.y, ga.get_center().z + ga.size.z * 0.15)
			_gun.position = pivot
			var gx := mg.global_transform
			mg.get_parent().remove_child(mg)
			_gun.add_child(mg)
			mg.global_transform = gx
			muzzle_pos = Vector3(0, ga.size.y * 0.55, ga.position.z - pivot.z)
			gunner_pos = Vector3(0, 0, ga.end.z - pivot.z + 0.3)
			stand = MG_STAND
			# Rumpfbox nur bis zur Unterkante der Trefferzone (Bordwand), sonst verdeckt sie den Schuetzen
			var top := pivot.y - stand + 0.55
			_hull_size.y = top + 0.4
			_hull_y = (top - 0.4) * 0.5
		else:
			VF.mesh_node(_gun, VF.box(Vector3(0.12, 0.14, 1.3)), dark, Vector3(0, 0.1, -0.5))
			VF.mesh_node(_gun, VF.box(Vector3(0.6, 0.4, 0.06)), dark, Vector3(0, 0.05, 0.1))
		_gunner = Node3D.new()
		_gunner.position = gunner_pos
		_gun.add_child(_gunner)
		var hip := -stand + 0.85
		if mg != null:
			# Echte Garde-Figur (Gegner-Pipeline) im Anschlag hinter dem DShK, Gewehr weg (Haende am MG)
			_puppet = Models.puppet(_gunner, "garde", GARDE_COLS, Vector3(0, -stand, PUPPET_BACK), 0.0,
				{"aim": true, "unarmed": true, "name": "GardeSchuetze", "aim_local": Vector3(0, 0.35, -3.2)})
		else:
			_primitive_gunner(stand)
		_gz_center = _gun.position + gunner_pos + Vector3(0, hip + 0.35, 0)
		_gz_size = Vector3(1.0, 1.3, 1.0)
		_muzzle = Marker3D.new()
		_muzzle.position = muzzle_pos
		_gun.add_child(_muzzle)
		_flash = VF.make_muzzle_flash(_muzzle, 1.0, 9.0, 12.0)
		# Suchscheinwerfer (Xenon/LED-Bootsscheinwerfer, real 300-500 m Reichweite): vorher 60 m / Energie 4 -
		# auf die ueblichen 80-150 m Gefechtsabstand (Bruecke ~88 m) kam davon nichts an. Enger, heller Kegel mit
		# sichtbarem Strahl im Regen; folgt in _tick_gun dem Ziel (gekoppelt an das Bug-MG).
		var sl := SpotLight3D.new()
		sl.light_color = Color(0.9, 0.95, 1.0)
		sl.light_energy = 8.0
		sl.spot_range = 240.0
		sl.spot_angle = 7.5
		sl.spot_angle_attenuation = 0.8
		sl.spot_attenuation = 0.45
		sl.light_volumetric_fog_energy = 0.6
		sl.shadow_enabled = false
		sl.light_specular = 0.3   # sonst grelle Glitzerpunkte auf dem Wasser
		sl.position = Vector3(0, 1.8, 0.2) if mg == null else _gun.position + Vector3(0, 1.5, 1.6)
		_motion.add_child(sl)
		_gun.set_meta("spot", sl)
		# Schwaches Arbeitslicht am Schuetzen, damit er nachts als Ziel lesbar ist
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.78, 0.5)
		ol.light_energy = 0.9
		ol.omni_range = 3.2
		ol.shadow_enabled = false
		ol.position = Vector3(0, hip + 0.5, 0.4)
		_gunner.add_child(ol)
	elif Models.find(_motion, "weber_boat") == null:
		var fig := VF.mat("hb_weber", Color(0.12, 0.12, 0.14), 0.85, 0.0)
		VF.mesh_node(_motion, VF.capsule(0.28, 1.5), fig, Vector3(0.3, 1.4, 1.6))
		VF.mesh_node(_motion, VF.capsule(0.28, 1.5), fig, Vector3(-0.4, 1.4, 2.3))
	_spray = FX.make_boat_spray(self, Vector3(0, 0.1, -mlen * 0.33), Vector3(0, 0.1, mlen * 0.43), 2.6 * mlen / 8.0)

## Fallback ohne Modell: einfache Kapsel-Figur.
func _primitive_gunner(stand: float) -> void:
	var coat := VF.mat("hb_coat", Color(0.3, 0.31, 0.29), 0.9, 0.0)
	var dk := VF.mat("hb_gunner_dark", Color(0.12, 0.12, 0.12), 0.85, 0.0)
	var hip := -stand + 0.85
	VF.mesh_node(_gunner, VF.capsule(0.13, 0.9), dk, Vector3(-0.13, hip - 0.42, 0.05))
	VF.mesh_node(_gunner, VF.capsule(0.13, 0.9), dk, Vector3(0.13, hip - 0.42, -0.05))
	VF.mesh_node(_gunner, VF.capsule(0.24, 0.75), coat, Vector3(0, hip + 0.3, -0.05), Vector3(-12, 0, 0))
	VF.mesh_node(_gunner, VF.capsule(0.08, 0.6), coat, Vector3(-0.22, hip + 0.4, -0.3), Vector3(-70, 0, 0))
	VF.mesh_node(_gunner, VF.capsule(0.08, 0.6), coat, Vector3(0.22, hip + 0.4, -0.3), Vector3(-70, 0, 0))
	VF.mesh_node(_gunner, VF.sphere(0.12), VF.mat("hb_skin", Color(0.55, 0.43, 0.36), 0.8, 0.0), Vector3(0, hip + 0.8, -0.1))
	VF.mesh_node(_gunner, VF.sphere(0.135), dk, Vector3(0, hip + 0.86, -0.08))

func is_alive() -> bool:
	return not dead

## Fuer HUD-Marker: Garde-Boot -> MG-Schuetze, Weber-Boot -> Kajuete.
func marker_point() -> Vector3:
	if _gunner != null and gunner_alive:
		return _gunner.global_position + Vector3(0, 0.9, 0)
	return global_position + Vector3(0, 2.6, 0)

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	var from_player: bool = source != null and is_instance_valid(source) and source.is_in_group("player")
	if role == "weber":
		VFX.spawn_impact(hit_position, hit_normal, "metal")
		if from_player and level_ref != null and level_ref.has_method("on_weber_boat_hit"):
			level_ref.call("on_weber_boat_hit")
		return
	# Schwachstelle MG-Schuetze
	if gunner_alive and _gunner != null:
		var lp := global_transform.affine_inverse() * hit_position
		var dz := (lp - _gz_center).abs() - _gz_size * 0.5
		if dz.x < 0.15 and dz.y < 0.15 and dz.z < 0.15:
			VFX.spawn_impact(hit_position, hit_normal, "flesh")
			_kill_gunner()
			return
	VFX.spawn_impact(hit_position, hit_normal, "metal")
	if from_player:
		_evade()
	health -= amount
	if health <= 0.0:
		_die(true)

func destroy() -> void:
	if not dead and role != "weber":
		health = 0.0
		_die(true)

func _kill_gunner() -> void:
	gunner_alive = false
	_burst_left = 0
	if _puppet != null and is_instance_valid(_puppet):
		# Echte Figur: Todesanimation, kein Ragdoll (Boot faehrt weiter)
		_puppet.set("aiming", false)
		_puppet.set("frozen", true)
		var sv: Node = _puppet.get("_soldier")
		if sv != null:
			var tree := sv.get("anim_tree") as AnimationTree
			if tree != null:
				tree.set("parameters/life/transition_request", "death_%d" % randi_range(1, 2))
			var ik: Node = sv.get("ik")
			if ik != null:
				ik.set("active", false)
	elif _gunner != null:
		_gunner.rotation_degrees = Vector3(70, 0, 25)
		_gunner.position += Vector3(0.35, -0.45, 0.5)
	gunner_killed.emit()
	_die(false)

func _evade() -> void:
	if _swerve_cd > 0.0:
		return
	_swerve_cd = 2.6
	_swerve_t = 1.8
	var side := 1.0 if randf() < 0.5 else -1.0
	# lieber nach aussen (weg vom Spieler) als quer vor den Bug
	if absf(lateral) > 1.0 and randf() < 0.7:
		side = signf(lateral)
	_swerve_goal = side * randf_range(4.0, 6.5)

func _die(explode: bool) -> void:
	dead = true
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	_burst_left = 0
	Events.enemy_killed.emit(self)
	if explode:
		VFX.spawn_explosion(global_position + Vector3.UP * 1.0, 0.9)
		FX.big_splash(self, global_position, 1.3)
	_spin = deg_to_rad(randf_range(28.0, 40.0)) * (1.0 if randf() < 0.5 else -1.0)
	if _gun != null and _gun.has_meta("spot"):
		(_gun.get_meta("spot") as Node).queue_free()

func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	_t += delta
	_swerve_cd = maxf(0.0, _swerve_cd - delta)
	if role != "weber" and not dead:
		# Bots rechnen global_position + aim_offset (unrotiert) -> Offset mit der Bootsdrehung nachfuehren
		set_meta("aim_offset", global_basis * (_gz_center + Vector3(0, -0.15, 0)))
	if _pos == Vector3.INF:
		_pos = global_position
		_pos.y = -2.0
		_yaw = rotation.y
	if dead:
		_tick_dead(delta)
		return
	var path_yaw := _yaw
	if free_target != Vector3.INF:
		var to := free_target - _pos
		to.y = 0.0
		var d := to.length()
		var want := to.normalized() * minf(free_speed, d * 0.5) if d > 0.5 else Vector3.ZERO
		_vel = _vel.move_toward(want, 5.0 * delta)
		_pos += _vel * delta
		if d > 2.0:
			path_yaw = atan2(-to.x, -to.z)
	elif ride != null and is_instance_valid(ride):
		var rspeed: float = float(ride.get("speed"))
		var stopped: bool = rspeed < 2.0
		if role == "weber":
			# Vorsprung halten: haelt der Spieler an, zieht Weber davon
			# (gedeckelt, damit er in Sichtweite bleibt; faehrt der Spieler wieder, holt er zuegig auf)
			if stopped:
				offset_s = minf(offset_s + 4.0 * delta, maxf(offset_s, 210.0))
			else:
				offset_s = move_toward(offset_s, target_offset, maxf(approach_rate, 4.0) * delta)
		else:
			offset_s = move_toward(offset_s, target_offset, approach_rate * delta * (0.4 if stopped else 1.0))
		var s: float = float(ride.get("path_s")) + offset_s
		var p: Vector3 = ride.call("pos_at", s)
		var dir: Vector3 = ride.call("dir_at", s)
		var right := dir.cross(Vector3.UP).normalized()
		# Schlaengeln: Phase laeuft bei stehender Bahn langsamer, Amplitude kleiner -> kein Seitwaerts-Rutschen
		var calm := clampf(rspeed / 10.0, 0.25, 1.0)
		if lateral_to != INF:
			lateral = move_toward(lateral, lateral_to, lateral_rate * delta)
		_wt += delta * calm
		_swerve_t = maxf(0.0, _swerve_t - delta)
		_swerve = move_toward(_swerve, _swerve_goal if _swerve_t > 0.0 else 0.0, 5.0 * delta)
		var lat := lateral + sin(_wt * TAU * weave_freq + _ph) * weave_amp * calm + _swerve
		var tgt := p + right * lat
		tgt.y = -2.0
		path_yaw = atan2(-dir.x, -dir.z)
		if _tgt_prev == Vector3.INF or _tgt_prev.distance_to(tgt) > 40.0 or _pos.distance_to(tgt) > 80.0:
			# Erstplatzierung / Neustart: hinsetzen statt quer uebers Becken zu rasen
			_pos = tgt
			_vel = dir * rspeed
			_tgt_vel = _vel
			_yaw = path_yaw
			_yaw_rate = 0.0
		else:
			_tgt_vel = _tgt_vel.lerp((tgt - _tgt_prev) / delta, 1.0 - exp(-delta * 5.0))
		_tgt_prev = tgt
		var w := follow_omega
		var acc := (tgt - _pos) * (w * w) + (_tgt_vel - _vel) * (2.0 * w)
		_vel += acc * delta
		_vel.y = 0.0
		_vel = _vel.limit_length(48.0)
		_pos += _vel * delta
	_pos.y = -2.0
	# Kurs: aus der Geschwindigkeit, solange das Boot vorwaerts faehrt; sonst Bahnrichtung. Drehrate begrenzt.
	var hv := Vector2(_vel.x, _vel.z)
	var desired := path_yaw
	if hv.length() > 3.0:
		var vy := atan2(-_vel.x, -_vel.z)
		if absf(wrapf(vy - path_yaw, -PI, PI)) < deg_to_rad(100.0):
			desired = vy
	var max_rate := deg_to_rad(turn_rate_deg)
	var want_rate := clampf(wrapf(desired - _yaw, -PI, PI) * 2.2, -max_rate, max_rate)
	_yaw_rate = lerpf(_yaw_rate, want_rate, 1.0 - exp(-delta * 3.5))
	_yaw = wrapf(_yaw + _yaw_rate * delta, -PI, PI)
	velocity = _vel
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), _pos)
	var spd := _vel.length()
	var sp01 := clampf(spd / 20.0, 0.0, 1.0)
	_bank = lerpf(_bank, clampf(_yaw_rate * spd * 0.014, -0.2, 0.2), 1.0 - exp(-delta * 2.5))
	_pitch = lerpf(_pitch, 0.06 * sp01, 1.0 - exp(-delta * 1.5))
	_motion.rotation = Vector3(_pitch + sin(_t * 1.3 + _ph) * 0.012 * (1.0 + sp01), 0, _bank + sin(_t * 0.9 + _ph) * 0.02)
	_motion.position.y = sin(_t * 1.6 + _ph) * 0.07 + 0.08 * sp01
	FX.set_spray(_spray, clampf(spd / 12.0, 0.15, 1.0))
	if _engine != null:
		_engine.pitch_scale = lerpf(0.8, 1.3, sp01)
	if role != "weber":
		_tick_gun(delta)

func _tick_dead(delta: float) -> void:
	# steuerlos auslaufen, abdrehen, dann sinken
	_sink_t += delta
	_vel = _vel * exp(-delta * 0.7)
	_pos += _vel * delta
	_spin *= exp(-delta * 0.4)
	_yaw += _spin * delta
	var sink := maxf(0.0, _sink_t - 3.0) * 0.5
	global_transform = Transform3D(Basis(Vector3.UP, _yaw), Vector3(_pos.x, -2.0 - sink, _pos.z))
	_motion.rotation = Vector3(minf(_sink_t * 0.06, 0.3), 0, minf(_sink_t * 0.1, 0.45) * signf(_spin))
	FX.set_spray(_spray, clampf(_vel.length() / 12.0, 0.0, 1.0) if _sink_t < 3.0 else 0.0)
	if _engine != null:
		_engine.pitch_scale = maxf(0.4, _engine.pitch_scale - delta * 0.2)
		if _sink_t > 3.0:
			_engine.stop()
	if _sink_t > 9.0:
		queue_free()

## Suchscheinwerfer traege auf das Ziel nachfuehren (leicht hinterher, wie von Hand gefuehrt).
func _aim_spot(tgt: Vector3, delta: float) -> void:
	if dead or not _gun.has_meta("spot"):
		return
	var o: Variant = _gun.get_meta("spot")
	if not is_instance_valid(o) or not (o is SpotLight3D) or (o as Node).is_queued_for_deletion():
		return
	var sl := o as SpotLight3D
	if not sl.is_inside_tree():
		return
	var gp := sl.global_position
	# auf Rumpf/Wasserlinie vor dem Ziel halten, nicht in die Schuetzenkamera: direkt ins Objektiv
	# gerichtet fuellte der Strahl im Regen-Dunst das halbe Bild mit Weiss
	var d := (tgt + Vector3(0, -2.4, 0)) - gp
	if d.length_squared() < 4.0:
		return
	var want := Basis.looking_at(d.normalized(), Vector3.UP)
	var cur := sl.global_basis.orthonormalized()
	sl.global_basis = cur.slerp(want, 1.0 - exp(-delta * 3.0))

func _tick_gun(delta: float) -> void:
	if not gunner_alive or ride == null or not is_instance_valid(ride) or not bool(ride.call("is_alive")):
		return
	var tgt := ride.global_position + Vector3.UP * 1.2
	var lp: Vector3 = (_gun.get_parent() as Node3D).global_transform.affine_inverse() * tgt - _gun.position
	_gun.rotation.y = lerp_angle(_gun.rotation.y, atan2(-lp.x, -lp.z), 1.0 - exp(-delta * 5.0))
	_aim_spot(tgt, delta)
	if _burst_left > 0:
		_shot_cd -= delta
		if _shot_cd <= 0.0:
			_shot_cd = 0.1
			_burst_left -= 1
			_fire(tgt)
		return
	_burst_cd -= delta
	if _burst_cd > 0.0:
		return
	_burst_cd = randf_range(1.8, 3.0)
	var from := _muzzle.global_position
	if from.distance_to(tgt) > 230.0:
		return
	var hit := VF.ray(self, from, tgt, VF.LAYER_WORLD, [get_rid()])
	if not hit.is_empty():
		return
	_burst_left = burst_rounds
	_shot_cd = 0.0
	_burst_lethal = true
	if level_ref != null and level_ref.has_method("boat_fire_slot"):
		_burst_lethal = bool(level_ref.call("boat_fire_slot", self, burst_rounds * 0.1 + 0.2))

func _fire(tgt: Vector3) -> void:
	var from := _muzzle.global_position
	var hit := _burst_lethal and randf() < hit_chance
	var aim := tgt
	if not hit:
		# Fehlschuesse liegen sichtbar knapp daneben (Wasserfontaenen am Bug), nicht weit weg
		aim += Vector3(randf_range(-3.0, 3.0), randf_range(-2.5, 2.0), randf_range(-3.0, 3.0))
	VF.show_flash(_flash, 0.05)
	VF.play_at(self, "hafen_mg", from, -2.0, 16.0, 340.0, randf_range(0.9, 1.0))
	# Leuchtspur endet einige Meter vor dem Ziel: tgt ist die Spielerkamera, sonst
	# landet die Spitze des Leuchtspur-Quaders frontal im Objektiv (rotes Quadrat im Bild).
	var tr_len := from.distance_to(aim)
	var tr_end := from + (aim - from) / maxf(tr_len, 0.01) * maxf(tr_len - 6.0, 1.0)
	VF.tracer(self, from, tr_end, 420.0, "red", 1.3)
	if hit:
		ride.call("take_damage", round_damage, self, aim, (from - aim).normalized())
	else:
		VFX.play_whiz_along(from, aim + (aim - from).normalized() * 10.0, 3.0)
		if aim.y < -0.8 or randf() < 0.6:
			FX.water_hit(self, Vector3(aim.x, -2.0, aim.z))
