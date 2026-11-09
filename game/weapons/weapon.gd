class_name Weapon
extends Node3D
## Hitscan-Waffe: Ballistik, Streuung, Rückstoß, Nachladen, Viewmodel (HD-Modell oder Primitive),
## Mündungsfeuer und Tracer. Wird vom Player gesteuert (tick/try_fire/animate).
## Viewmodel-Animation ist rein prozedural: Feder-Dämpfer für Sway/Rückstoß/Impulse,
## Schritt-Bob aus der Schrittphase des Players, Atmen, Nachlade-Zeitleiste mit Teile-Animation.

signal fired(weapon: Weapon)
signal reload_started(weapon: Weapon)
signal reload_finished(weapon: Weapon)
## Treffer auf etwas Schadensfähiges (für Hitmarker)
signal hit_confirmed(killed: bool, headshot: bool)

const VIEW_LAYER_BIT: int = 1 << 19   # Render-Layer 20: nur die Waffen-Kamera sieht das
const HIT_MASK: int = 1 | 2 | 4        # world + player + enemy
const DEBRIS_LAYER: int = 8            # Physik-Layer 4: debris (kollidiert nur mit world)
const MAX_DEBRIS: int = 16

@export_group("Identity")
@export var weapon_id: String = "rifle"
@export var display_name: String = "STURMGEWEHR"
@export_enum("rifle", "pistol", "g36c", "ak", "launcher") var model_kind: String = "rifle"
## Munitionssorte ("556", "545", "9mm", "pzf") – Pickups mit gleicher Sorte füllen diese Waffe auf.
@export var ammo_type: String = "556"
## Slot: 0 Primärwaffe (tauschbar), 1 Pistole, 2 Panzerfaust
@export_range(0, 2) var slot: int = 0
@export var sfx_fire: String = "rifle_fire"
## Fallback, falls die Phasen-Sounds (<sfx_prefix>_mag_out/_mag_in/_bolt|_slide) fehlen
@export var sfx_reload: String = "rifle_reload"
@export var sfx_dry: String = "dry_fire"
## Präfix der Nachlade-Phasen-Sounds ("weapon" -> weapon_mag_out, weapon_mag_in, weapon_bolt)
@export var sfx_prefix: String = "weapon"

@export_group("Ballistics")
@export var rpm: float = 650.0
@export var full_auto: bool = true
@export var mag_size: int = 30
@export var reserve_start: int = 210
@export var reserve_max: int = 300
@export var damage: float = 34.0
## Kopftreffer-Multiplikator für Ziele OHNE eigene Kopf-Logik (z.B. Dummies).
@export var headshot_mult: float = 2.0
## Effektiver Waffen-Multiplikator, wenn das Ziel selbst schon einen Kopf-Multiplikator anwendet
## (EnemyHitbox -> Enemy.take_hit_part multipliziert mit head_damage_multiplier: Rifleman 2.5, Heavy 1.5).
## Sonst würde doppelt multipliziert (2.0 x 2.5). Rifle 34 x 1.4 = 47.6 an die Hitbox:
## Rifleman 47.6 x 2.5 = 119 >= 60 -> 1 Kopftreffer; Heavy 47.6 x 1.5 = 71.4 -> 3 Kopftreffer (170 HP).
@export var headshot_mult_hitbox: float = 1.4
@export var max_range: float = 300.0
## Taktisches Nachladen (Restpatrone im Lauf)
@export var reload_time: float = 1.9
## Leeres Magazin: zusätzlich Ladehebel / Schlittenfang
@export var reload_time_empty: float = 2.3

@export_group("Spread (Grad)")
@export var spread_hip: float = 1.0
@export var spread_ads: float = 0.04
@export var spread_move: float = 0.8       # Zuschlag bei voller Geschwindigkeit
@export var spread_air: float = 2.0
@export var spread_per_shot: float = 0.07  # Bloom pro Schuss
@export var spread_bloom_max: float = 0.9
@export var spread_recover: float = 10.0    # Grad/s
@export var crouch_spread_mult: float = 0.7
@export var prone_spread_mult: float = 0.45
## Bloom-Anteil im ADS (kurze Salven bleiben präzise, Dauerfeuer blüht leicht auf)
@export var ads_bloom_mult: float = 0.4
## Erster Schuss im vollen ADS exakt (0 Streuung), wenn stehend/langsam und Bloom abgeklungen
@export var first_shot_exact: bool = true
@export var first_shot_max_move: float = 0.42   # move_ratio (ADS-Gehen ~0.37)

@export_group("Recoil")
## x = yaw (Grad, + = rechts), y = pitch (Grad, + = hoch); letzter Eintrag wiederholt sich mit Zufall
@export var recoil_pattern: PackedVector2Array = PackedVector2Array([
	Vector2(0, 0.303), Vector2(0.0275, 0.33), Vector2(-0.055, 0.33), Vector2(0.0825, 0.303),
	Vector2(0.138, 0.275), Vector2(-0.0275, 0.275), Vector2(-0.165, 0.248), Vector2(-0.138, 0.248),
	Vector2(0.055, 0.22), Vector2(0.193, 0.22), Vector2(0.11, 0.193), Vector2(-0.11, 0.193)])
@export var recoil_random: float = 0.03
@export var ads_recoil_mult: float = 0.45
@export var recoil_reset_time: float = 0.35
@export var viewkick: float = 0.035        # Rückwärtsversatz des Viewmodels pro Schuss (m)
## Hochschlagen des Viewmodels pro Schuss (Grad)
@export var viewkick_rot: float = 3.2
@export var shot_trauma: float = 0.07

@export_group("Handling")
@export var ads_fov: float = 55.0
@export var ads_speed: float = 10.0
@export var move_speed_mult: float = 1.0
@export var hip_pos: Vector3 = Vector3(0.2, -0.2, -0.55)
@export var ads_pos: Vector3 = Vector3(0.0, -0.088, -0.40)
@export var sprint_pos: Vector3 = Vector3(0.12, -0.26, -0.4)
@export var sprint_rot: Vector3 = Vector3(-12.0, 38.0, -14.0)
## Wegstecken / Ziehen beim Waffenwechsel (s)
## Sprint-zu-Feuer: so lange nach Sprint-Ende kann noch nicht geschossen werden (s)
@export var sprint_to_fire: float = 0.17
@export var holster_time: float = 0.2
@export var draw_time: float = 0.32

@export_group("Model / Optik")
## HD-Modell (leer = Primitiv-Modell). Gewehr: Pivot-Koordinaten unverändert (Meter, Lauf nach -Z).
@export_file("*.fbx", "*.glb", "*.gltf") var model_path: String = ""
## Nur für Modelle, die nicht in Pivot-Koordinaten vorliegen (Pistole): Lage/Drehung/Skalierung
@export var model_offset: Vector3 = Vector3.ZERO
@export var model_rot_deg: Vector3 = Vector3.ZERO
@export var model_scale: float = 1.0
@export var has_red_dot: bool = false
## Red-Dot-Montagepunkt (Oberkante Schiene, Pivot-Koordinaten)
@export var optic_mount: Vector3 = Vector3(0.0, 0.06, -0.03)
## Abstand Auge -> Glas im ADS. ads_pos wird daraus automatisch berechnet (Glas exakt auf der Sichtachse).
@export var ads_eye_dist: float = 0.15
@export var muzzle_pos: Vector3 = Vector3(0.0, 0.012, -0.80)
## Auswurffenster (Pivot-Raum); ZERO = keine Hülsen
@export var eject_pos: Vector3 = Vector3.ZERO
@export var shell_len: float = 0.045

var ammo_mag: int = 0
var ammo_reserve: int = 0
var reloading: bool = false
var last_recoil: Vector2 = Vector2.ZERO    # Rückstoß des letzten Schusses (für Player)

var owner_player: Player = null
var muzzle: Node3D
var _pivot: Node3D
var _flash_light: OmniLight3D
var _flash_mesh: MeshInstance3D
var _flash_particles: GPUParticles3D
var _flash_t: float = 0.0
var _cooldown: float = 0.0
var _shot_index: int = 0
var _since_shot: float = 10.0
var _bloom: float = 0.0
var _dry_clicked: bool = false
var _optic_lens: MeshInstance3D = null

# --- Nachladen (Zeitleiste in Sekunden, siehe _timeline())
var _reload_t: float = 0.0
var _reload_total: float = 2.0
var _reload_empty: bool = false
var _reload_scale: float = 1.0
var _ammo_in: bool = false                 # Munition bereits gutgeschrieben (Magazin sitzt)
var _events_done: Dictionary = {}
var _phase_sfx: bool = true                # Phasen-Sounds vorhanden?

# --- Bewegliche Teile (im Pivot-Raum animiert)
var _mag_part: Dictionary = {}             # node, prel_inv, rest, c, down
var _bolt_part: Dictionary = {}            # Ladehebel (Gewehr) bzw. Schlitten (Pistole)
var _slide_t: float = 1.0                  # Schlitten-Rücklauf nach Schuss (0..1 = läuft)
var _slide_locked: bool = false            # Pistole leer: Schlitten bleibt hinten

# --- Viewmodel-Zustand
var _base_pos: Vector3 = Vector3.ZERO
var _base_rot: Vector3 = Vector3.ZERO
var _sway := Spring3.new()                 # Positions-Sway (Blick-Trägheit)
var _sway_r := Spring3.new()               # Rotations-Sway
var _imp := Spring3.new()                  # Impulse: Landung, Klaps, Ziehen (Position)
var _imp_r := Spring3.new()
var _rc := Spring3.new()                   # Rückstoß (Position)
var _rc_r := Spring3.new()                 # Rückstoß (Rotation)
var _time: float = 0.0
var _initialized: bool = false

## Kritisch/unterkritisch gedämpfte Feder (semi-implizites Euler, vom Aufrufer mit Substeps).
class Spring3:
	var x: Vector3 = Vector3.ZERO
	var v: Vector3 = Vector3.ZERO
	func step(target: Vector3, k: float, zeta: float, dt: float) -> void:
		var c: float = 2.0 * zeta * sqrt(k)
		v += ((target - x) * k - v * c) * dt
		x += v * dt
	func reset() -> void:
		x = Vector3.ZERO
		v = Vector3.ZERO

static var _tracer_mat: StandardMaterial3D
static var _flash_mat: StandardMaterial3D
static var _metal_mat: StandardMaterial3D
static var _poly_mat: StandardMaterial3D
static var _cloth_mat: StandardMaterial3D
static var _debris: Array = []
static var _shell_mat: StandardMaterial3D

const MAX_SHELLS: int = 10
var _shells: Array = []                    # [{node, vel, angv, t, sound}]
var _wall_amt: float = 0.0

func _ready() -> void:
	ammo_mag = mag_size
	ammo_reserve = reserve_start
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	add_child(_pivot)
	_pivot.position = hip_pos
	_base_pos = hip_pos
	_build_model()
	_build_muzzle_flash()
	_phase_sfx = not Sfx.get_variants(sfx_prefix + "_mag_in").is_empty()
	set_active(false)

func setup(p: Player) -> void:
	owner_player = p

func set_active(on: bool) -> void:
	visible = on
	if not on:
		cancel_reload()
		_flash_t = 0.0
		_flash_light.visible = false
		_flash_mesh.visible = false
	else:
		# Beim Ziehen leichter Schwung von unten (Feder schwingt nach)
		_imp_r.v += Vector3(-60.0, 25.0, 40.0)

# ---------------------------------------------------------------- Logik

func tick(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_since_shot += delta
	if _since_shot > recoil_reset_time:
		_shot_index = 0
	_bloom = maxf(0.0, _bloom - spread_recover * delta)
	if _slide_t < 1.0:
		_slide_t = minf(1.0, _slide_t + delta / 0.075)
	if reloading:
		var before: float = _reload_t
		_reload_t += delta
		_reload_events(before, _reload_t)
		if _reload_t >= _reload_total:
			_finish_reload()
	if _flash_t > 0.0:
		_flash_t -= delta
		if _flash_t <= 0.0:
			_flash_light.visible = false
			_flash_mesh.visible = false
	_tick_shells(delta)

func is_launcher() -> bool:
	return model_kind == "launcher"

func is_long() -> bool:
	return model_kind != "pistol"

func reload_progress() -> float:
	return clampf(_reload_t / _reload_total, 0.0, 1.0) if reloading else 0.0

func can_reload() -> bool:
	return not reloading and ammo_mag < mag_size and ammo_reserve > 0

func start_reload() -> bool:
	if not can_reload():
		return false
	reloading = true
	_reload_t = 0.0
	_ammo_in = false
	_events_done.clear()
	_reload_empty = ammo_mag <= 0
	var tl: Dictionary = _timeline()
	if _reload_empty:
		_reload_total = reload_time_empty
		_reload_scale = reload_time_empty / float(tl.end_e)
	else:
		_reload_total = reload_time
		_reload_scale = reload_time / float(tl.end_t)
	if not _phase_sfx:
		_play(sfx_reload)
	reload_started.emit(self)
	return true

func cancel_reload() -> void:
	reloading = false
	_reload_t = 0.0
	_events_done.clear()
	_apply_parts_rest()

func _finish_reload() -> void:
	_credit_ammo()
	reloading = false
	_reload_t = 0.0
	_slide_locked = false
	_events_done.clear()
	_apply_parts_rest()
	reload_finished.emit(self)

func _credit_ammo() -> void:
	if _ammo_in:
		return
	_ammo_in = true
	var need: int = mag_size - ammo_mag
	var take: int = mini(need, ammo_reserve)
	ammo_mag += take
	ammo_reserve -= take

## Phasen der Nachlade-Zeitleiste (Sekunden, vor Skalierung auf reload_time / reload_time_empty).
## rel: Magazin entriegelt, out: Magazin aus dem Schacht, new0: neues Magazin taucht auf,
## ins0..ins1: einführen, slap: Klaps, bolt0..bolt2: Ladehebel ziehen / Schlittenfang lösen.
func _timeline() -> Dictionary:
	if model_kind == "pistol":
		return {"rel": 0.10, "out": 0.22, "new0": 0.40, "ins0": 0.78, "ins1": 0.90, "slap": 0.93,
			"bolt0": 1.08, "bolt1": 1.14, "bolt2": 1.18, "end_t": 1.45, "end_e": 1.75}
	if model_kind == "launcher":
		# Neuer Gefechtskopf wird von vorn in das Rohr gesteckt
		return {"rel": 0.05, "out": 0.08, "new0": 0.45, "ins0": 1.25, "ins1": 1.6, "slap": 1.65,
			"bolt0": 1.85, "bolt1": 1.95, "bolt2": 2.05, "end_t": 2.5, "end_e": 2.5}
	return {"rel": 0.12, "out": 0.30, "new0": 0.50, "ins0": 0.98, "ins1": 1.16, "slap": 1.20,
		"bolt0": 1.40, "bolt1": 1.56, "bolt2": 1.66, "end_t": 1.9, "end_e": 2.4}

func _tl(key: String) -> float:
	return float(_timeline()[key]) * _reload_scale

## Löst die Ereignisse zwischen zwei Zeitpunkten genau einmal aus.
func _reload_events(t0: float, t1: float) -> void:
	var evs: Array = [["mag_out", _tl("rel")], ["drop", _tl("out")], ["mag_in", _tl("ins1") - 0.04],
		["seat", _tl("ins1")], ["slap", _tl("slap")]]
	if _reload_empty:
		evs.append(["bolt_pull", _tl("bolt0")])
		evs.append(["bolt", _tl("bolt2")])
	for e: Array in evs:
		var key: String = e[0]
		var at: float = e[1]
		if _events_done.has(key) or t1 < at:
			continue
		_events_done[key] = true
		match key:
			"mag_out":
				_play_phase("_mag_out")
			"drop":
				# Leer: Magazin fällt zu Boden. Taktisch: Magazin wird verstaut (keine Trümmer).
				if _reload_empty and not is_launcher():
					_spawn_mag_debris()
			"mag_in":
				_play_phase("_mag_in")
			"seat":
				_credit_ammo()
			"slap":
				_imp.v += Vector3(0.0, 0.25, 0.08)
				_imp_r.v += Vector3(70.0, 0.0, -25.0)
			"bolt_pull":
				if model_kind != "pistol" and not is_launcher():
					_imp_r.v += Vector3(0.0, -30.0, 20.0)
			"bolt":
				_slide_locked = false
				_play_phase("_slide" if model_kind == "pistol" else "_bolt")
				_imp.v += Vector3(0.0, 0.0, 0.18)
				_imp_r.v += Vector3(40.0, 0.0, 0.0)

func _play_phase(suffix: String) -> void:
	if _phase_sfx:
		_play(sfx_prefix + suffix, 0.04)

func add_reserve(amount: int) -> void:
	ammo_reserve = mini(reserve_max, ammo_reserve + amount)

func refill() -> void:
	ammo_mag = mag_size
	ammo_reserve = maxi(ammo_reserve, reserve_start)
	cancel_reload()
	_slide_locked = false
	_slide_t = 1.0

func time_since_shot() -> float:
	return _since_shot

func fire_interval() -> float:
	return 60.0 / rpm

func ready_to_fire() -> bool:
	return _cooldown <= 0.0 and not reloading

## Aktuelle Streuung in Grad (auch für das Fadenkreuz).
func current_spread(ads: float, move_ratio: float, crouching: bool, airborne: bool, prone: bool = false) -> float:
	if first_shot_exact and ads >= 0.95 and not airborne and move_ratio <= first_shot_max_move \
			and _bloom <= 0.001 and _shot_index == 0:
		return 0.0
	var s: float = lerpf(spread_hip, spread_ads, ads)
	s += spread_move * move_ratio * (1.0 - 0.6 * ads)
	if airborne:
		s += spread_air
	if prone:
		s *= prone_spread_mult
	elif crouching:
		s *= crouch_spread_mult
	return s + _bloom * lerpf(1.0, ads_bloom_mult, ads)

func notify_dry() -> void:
	if not _dry_clicked:
		_dry_clicked = true
		_play(sfx_dry)

func reset_trigger() -> void:
	_dry_clicked = false

## Schuss abgeben. Gibt true zurück, wenn tatsächlich gefeuert wurde.
func try_fire(cam: Camera3D, ads: float, move_ratio: float, crouching: bool, airborne: bool,
		prone: bool = false) -> bool:
	if not ready_to_fire() or ammo_mag <= 0:
		return false
	ammo_mag -= 1
	_cooldown += fire_interval()
	if _cooldown > fire_interval():   # nach Pause nicht aufstauen
		_cooldown = fire_interval()
	var spread: float = current_spread(ads, move_ratio, crouching, airborne, prone)
	_bloom = minf(spread_bloom_max, _bloom + spread_per_shot)
	# Rückstoß-Muster
	var idx: int = mini(_shot_index, recoil_pattern.size() - 1)
	var rec: Vector2 = recoil_pattern[idx] if recoil_pattern.size() > 0 else Vector2(0, 0.5)
	if _shot_index >= recoil_pattern.size():
		rec.x = randf_range(-0.3, 0.3)
	rec += Vector2(randf_range(-recoil_random, recoil_random), randf_range(-recoil_random, recoil_random))
	rec *= lerpf(1.0, ads_recoil_mult, ads)
	last_recoil = rec
	_shot_index += 1
	_since_shot = 0.0
	_kick_viewmodel(ads)
	_slide_t = 0.0
	if ammo_mag <= 0 and model_kind == "pistol":
		_slide_locked = true
	_shoot(cam, spread)
	_eject_shell()
	_muzzle_flash()
	_play(sfx_fire, 0.035, 1.2)
	fired.emit(self)
	return true

## Rückstoß-Impuls auf die Viewmodel-Federn (im ADS deutlich gedämpft, Optik bleibt nahe der Achse).
func _kick_viewmodel(ads: float) -> void:
	var a: float = clampf(ads, 0.0, 1.0)
	var pm: float = lerpf(1.0, 0.55, a)
	var rm: float = lerpf(1.0, 0.28, a)
	var omega: float = sqrt(300.0)
	# Peak-Auslenkung ~ v0/omega * 0.6 -> v0 = Ziel * omega / 0.6
	var vz: float = viewkick * omega / 0.6 * pm
	var vr: float = viewkick_rot * omega / 0.6 * rm
	_rc.v += Vector3(randf_range(-0.08, 0.08) * vz, 0.12 * vz, vz)
	_rc_r.v += Vector3(vr, randf_range(-0.35, 0.35) * vr, randf_range(-0.6, 0.6) * vr)

func _shoot(cam: Camera3D, spread_deg: float) -> void:
	var origin: Vector3 = cam.global_position
	var b: Basis = cam.global_basis
	var dir: Vector3 = -b.z
	if spread_deg > 0.0:
		var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a: float = randf() * TAU
		dir = (dir + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, HIT_MASK, exclude)
	q.collide_with_areas = true
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = origin + dir * max_range
	if not res.is_empty():
		end = res.position
		_apply_hit(res, dir)
	_spawn_tracer(cam, end)

func _apply_hit(res: Dictionary, dir: Vector3) -> void:
	var collider: Object = res.collider
	var pos: Vector3 = res.position
	var normal: Vector3 = res.normal
	var headshot: bool = false
	if collider is Node:
		var cn: Node = collider as Node
		headshot = bool(cn.get_meta("headshot", false))
		if not headshot and cn.get_parent():
			headshot = bool(cn.get_parent().get_meta("headshot", false)) and not cn.get_parent().has_method("take_damage")
	var target: Node = _find_damageable(collider)
	if target == null:
		var surface: String = "concrete"
		if collider is Node:
			surface = str((collider as Node).get_meta("surface", "concrete"))
		VFX.spawn_impact(pos, normal, surface)
		return
	var is_enemy: bool = target.is_in_group("enemy")
	var was_alive: bool = target.is_alive()
	var dmg: float = damage
	if headshot:
		# Ziele mit eigener Kopf-Logik (EnemyHitbox -> take_hit_part) bekommen den kleineren
		# effektiven Multiplikator, damit nicht doppelt multipliziert wird (siehe headshot_mult_hitbox).
		dmg *= headshot_mult_hitbox if _target_scales_headshots(target) else headshot_mult
	target.take_damage(dmg, owner_player, pos, normal)
	var killed: bool = was_alive and not target.is_alive()
	if is_enemy:
		VFX.spawn_blood(pos, normal)
	else:
		VFX.spawn_impact(pos, normal, "metal")
	if was_alive:
		hit_confirmed.emit(killed, headshot)

func _target_scales_headshots(target: Node) -> bool:
	if target.has_method("take_hit_part"):
		return true
	if target.has_method("get_enemy"):
		var e: Variant = target.call("get_enemy")
		return e is Node and (e as Node).has_method("take_hit_part")
	return false

## Läuft vom Collider nach oben, bis ein Knoten mit take_damage gefunden wird.
func _find_damageable(n: Object) -> Node:
	var node: Node = n as Node
	var depth: int = 0
	while node and depth < 6:
		if node.has_method("take_damage") and node != owner_player:
			return node
		node = node.get_parent()
		depth += 1
	return null

# ---------------------------------------------------------------- Effekte

func _play(sfx: String, jitter: float = 0.0, vol_jitter_db: float = 0.0) -> void:
	if owner_player:
		owner_player.play_sfx(sfx, jitter, vol_jitter_db)

func _muzzle_flash() -> void:
	_flash_t = 0.045
	_flash_light.visible = true
	_flash_mesh.visible = true
	_flash_mesh.rotation.z = randf() * TAU
	var s: float = randf_range(0.8, 1.3)
	_flash_mesh.scale = Vector3(s, s, s)
	_flash_particles.restart()
	_flash_particles.emitting = true

func _spawn_tracer(cam: Camera3D, end: Vector3) -> void:
	var start: Vector3 = _tracer_start(cam)
	var vec: Vector3 = end - start
	var dist: float = vec.length()
	if dist < 1.0:
		return
	if _tracer_mat == null:
		_tracer_mat = StandardMaterial3D.new()
		_tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_tracer_mat.albedo_color = Color(1.0, 0.82, 0.45)
		_tracer_mat.emission_enabled = true
		_tracer_mat.emission = Color(1.0, 0.7, 0.3)
		_tracer_mat.emission_energy_multiplier = 4.0
		_tracer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var seg_len: float = minf(dist * 0.8, 4.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, seg_len)
	bm.material = _tracer_mat
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root: Node = _world_root()
	root.add_child(mi)
	var dir: Vector3 = vec / dist
	mi.global_position = start
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	mi.look_at(start + dir, up)
	# Mitte des Meshes fliegt von start nach end
	var speed: float = 260.0
	var travel: float = maxf(dist - seg_len * 0.5, 0.01)
	var tw := mi.create_tween()
	tw.tween_method(func(d: float) -> void:
		if is_instance_valid(mi):
			mi.global_position = start + dir * d, seg_len * 0.5, travel, travel / speed)
	tw.tween_callback(mi.queue_free)

func _world_root() -> Node:
	var root: Node = get_tree().current_scene
	if root == null:
		root = owner_player.get_parent() if owner_player else get_tree().root
	return root

## Sichtbare Mündung (Waffen-Kamera) in die Hauptkamera übertragen, damit der Tracer dort startet.
func _tracer_start(cam: Camera3D) -> Vector3:
	var fallback: Vector3 = cam.global_position + (-cam.global_basis.z) * 0.8 + cam.global_basis.x * 0.12 - cam.global_basis.y * 0.1
	if owner_player == null or not owner_player.weapon_cam.is_inside_tree():
		return fallback
	var wc: Camera3D = owner_player.weapon_cam
	if wc.is_position_behind(muzzle.global_position):
		return fallback
	var wsize: Vector2 = wc.get_viewport().get_visible_rect().size
	var msize: Vector2 = cam.get_viewport().get_visible_rect().size
	if wsize.x < 1.0 or wsize.y < 1.0:
		return fallback
	var sp: Vector2 = wc.unproject_position(muzzle.global_position) / wsize * msize
	return cam.project_position(sp, 1.2)

## Leeres Magazin als Physik-Trümmer fallen lassen (bleibt liegen). Erst auf dem Waffen-Layer,
## nach kurzer Zeit (außer Sicht unter der Kamera) auf den Welt-Layer umgeschaltet.
func _spawn_mag_debris() -> void:
	if _mag_part.is_empty() or not is_inside_tree() or not visible:
		return
	var src: Node3D = _mag_part.node
	var gt: Transform3D = src.global_transform
	var body := RigidBody3D.new()
	body.name = "MagDebris"
	body.collision_layer = DEBRIS_LAYER
	body.collision_mask = 1
	body.mass = 0.45
	body.continuous_cd = true
	body.contact_monitor = true
	body.max_contacts_reported = 2
	var root: Node = _world_root()
	root.add_child(body)
	body.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
	var inv: Transform3D = body.global_transform.affine_inverse()
	var aabb := AABB()
	var first: bool = true
	var meshes: Array[MeshInstance3D] = []
	for mi: MeshInstance3D in _collect_meshes(src):
		var dup := MeshInstance3D.new()
		dup.mesh = mi.mesh
		dup.material_override = mi.material_override
		dup.transform = inv * mi.global_transform
		dup.layers = VIEW_LAYER_BIT
		dup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		body.add_child(dup)
		meshes.append(dup)
		var bb: AABB = dup.transform * mi.mesh.get_aabb()
		aabb = bb if first else aabb.merge(bb)
		first = false
	if first:
		body.queue_free()
		return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3(0.01, 0.01, 0.01))
	cs.shape = box
	cs.position = aabb.get_center()
	body.add_child(cs)
	var down: Vector3 = (_pivot.global_basis * Vector3(_mag_part.down)).normalized()
	var pv: Vector3 = owner_player.velocity if owner_player else Vector3.ZERO
	body.linear_velocity = pv + down * 1.2 + Vector3(0.0, -0.4, 0.0)
	body.angular_velocity = _pivot.global_basis * Vector3(randf_range(-4.0, 4.0), randf_range(-2.0, 2.0), randf_range(3.0, 7.0))
	var snd := AudioStreamPlayer3D.new()
	body.add_child(snd)
	var hit_once: Array = [false]
	body.body_entered.connect(func(_b: Node) -> void:
		if not hit_once[0] and is_instance_valid(snd):
			hit_once[0] = true
			Sfx.play_on(snd, "weapon_mag_drop", 0.08, 1.5))
	get_tree().create_timer(0.3).timeout.connect(func() -> void:
		for m: MeshInstance3D in meshes:
			if is_instance_valid(m):
				m.layers = 1)
	_debris.append(body)
	while _debris.size() > MAX_DEBRIS:
		var old: Variant = _debris.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

func _collect_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n as MeshInstance3D)
	for c in n.get_children():
		out.append_array(_collect_meshes(c))
	return out

## Messinghülse aus dem Auswurffenster: fliegt nach rechts-oben-hinten, dreht sich, fällt.
## Liegt im Weltraum (nur Waffen-Kamera), wird manuell integriert und nach ~0.7 s entfernt.
func _eject_shell() -> void:
	if eject_pos == Vector3.ZERO or not is_inside_tree() or not visible:
		return
	if _shell_mat == null:
		_shell_mat = StandardMaterial3D.new()
		_shell_mat.albedo_color = Color(0.8, 0.58, 0.26)
		_shell_mat.metallic = 1.0
		_shell_mat.roughness = 0.28
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	var r: float = 0.0042 if is_long() else 0.0048
	cm.top_radius = r * 0.78
	cm.bottom_radius = r
	cm.height = shell_len
	cm.radial_segments = 8
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = _shell_mat
	mi.layers = VIEW_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(mi)
	var gb: Basis = _pivot.global_basis.orthonormalized()
	# Zylinder liegt quer zur Laufachse (Hülse zeigt nach rechts)
	mi.global_transform = Transform3D(gb * Basis.from_euler(Vector3(0, 0, PI * 0.5)), _pivot.global_transform * eject_pos)
	var pv: Vector3 = owner_player.velocity if owner_player else Vector3.ZERO
	var v_local := Vector3(randf_range(1.4, 2.1), randf_range(0.9, 1.5), randf_range(0.1, 0.5))
	var vel: Vector3 = pv + gb * v_local
	var angv: Vector3 = gb * Vector3(randf_range(-18.0, 18.0), randf_range(-8.0, 8.0), randf_range(14.0, 26.0))
	_shells.append({"node": mi, "vel": vel, "angv": angv, "t": 0.0, "snd": false})
	while _shells.size() > MAX_SHELLS:
		var old: Dictionary = _shells.pop_front()
		if is_instance_valid(old.node):
			(old.node as Node).queue_free()

func _tick_shells(delta: float) -> void:
	var i: int = 0
	while i < _shells.size():
		var s: Dictionary = _shells[i]
		var n: Node3D = s.node as Node3D
		if not is_instance_valid(n):
			_shells.remove_at(i)
			continue
		s.t = float(s.t) + delta
		var v: Vector3 = s.vel
		v.y -= 9.8 * delta
		s.vel = v
		n.global_position += v * delta
		var av: Vector3 = s.angv
		if av.length() > 0.001:
			n.global_basis = Basis(av.normalized(), av.length() * delta) * n.global_basis
		if not bool(s.snd) and float(s.t) > 0.42:
			s.snd = true
			if randf() < 0.6:
				_play("shell_drop", 0.12, 3.0)
		if float(s.t) > 0.7:
			n.queue_free()
			_shells.remove_at(i)
			continue
		i += 1

# ---------------------------------------------------------------- Viewmodel-Animation

## Viewmodel pro Frame animieren. s (alle optional):
## look_rate: Vector2 Grad/s (x rechts+, y hoch+), vel_local: Vector3 Geschwindigkeit in Kamera-Koordinaten,
## ads 0..1, sprint 0..1, bob_phase (rad, ein Schritt = PI), bob_amt 0..~1.5, holster 0..1,
## crouch 0..1, prone 0..1, slide 0..1, mantle 0..1, airborne bool.
func animate(delta: float, s: Dictionary) -> void:
	var lr: Vector2 = Vector2(s.get("look_rate", Vector2.ZERO)).clampf(-300.0, 300.0)
	var vl: Vector3 = s.get("vel_local", Vector3.ZERO)
	var ads_raw: float = clampf(float(s.get("ads", 0.0)), 0.0, 1.0)
	var ads: float = ads_raw * ads_raw * (3.0 - 2.0 * ads_raw)      # Ease in/out
	var sprint: float = float(s.get("sprint", 0.0))
	var phase: float = float(s.get("bob_phase", 0.0))
	var bob_amt: float = float(s.get("bob_amt", 0.0))
	var holster: float = float(s.get("holster", 0.0))
	var crouch: float = float(s.get("crouch", 0.0))
	var prone: float = float(s.get("prone", 0.0))
	var slide: float = float(s.get("slide", 0.0))
	var mantle: float = float(s.get("mantle", 0.0))
	var airborne: bool = bool(s.get("airborne", false))
	# Wand vor der Mündung: Waffe zurückziehen und hochkippen (geglättet)
	_wall_amt = lerpf(_wall_amt, clampf(float(s.get("wall", 0.0)), 0.0, 1.0), 1.0 - exp(-12.0 * delta))
	_time += delta
	var hip: float = 1.0 - ads

	# --- Basis-Pose (geglättet)
	var pos: Vector3 = hip_pos.lerp(ads_pos, ads)
	var rot: Vector3 = Vector3.ZERO
	var arc: float = sin(ads * PI)                                   # kleiner Bogen beim Anlegen
	pos.y -= arc * 0.012
	rot.z -= arc * 4.0
	pos = pos.lerp(sprint_pos, sprint)
	rot = rot.lerp(sprint_rot, sprint)
	# Haltung: geduckt leicht gekantet, liegend flacher und mittiger, Slide stark gekantet
	rot.z += (-5.0 * crouch - 9.0 * prone) * hip
	pos += Vector3(-0.012 * crouch - 0.03 * prone, 0.006 * crouch + 0.012 * prone, 0.02 * prone) * hip
	rot.z += 16.0 * slide * hip
	pos += Vector3(-0.02, -0.015, 0.0) * slide * hip
	# Mantle: Waffe weggedreht, die "Hände" sind beschäftigt
	pos += Vector3(0.03, -0.14, 0.04) * mantle
	rot += Vector3(-28.0, 10.0, 22.0) * mantle
	# Wand: Mündung hoch, Waffe an den Körper gezogen
	var wall_k: float = _wall_amt * (1.0 - mantle)
	pos += Vector3(-0.02, -0.035, 0.11 if is_long() else 0.06) * wall_k
	rot += Vector3(38.0 if is_long() else 30.0, 12.0, 14.0) * wall_k
	# Nachladen
	if reloading:
		var rp: Array = _reload_pose(_reload_t)
		pos += rp[0]
		rot += rp[1]
	var k: float = 1.0 - exp(-16.0 * delta)
	if not _initialized:
		k = 1.0
		_initialized = true
	_base_pos = _base_pos.lerp(pos, k)
	_base_rot = _base_rot.lerp(rot, k)

	# --- Federn (Substeps für Stabilität)
	var sway_m: float = lerpf(1.0, 0.25, ads)
	var sway_t := Vector3(-lr.x * 0.00018, -lr.y * 0.00018, 0.0) * sway_m
	sway_t += Vector3(-vl.x * 0.004, 0.0, vl.z * 0.002) * sway_m                 # Strafe / vor-zurück
	if airborne:
		sway_t.y += clampf(-vl.y * 0.006, -0.03, 0.03) * sway_m                  # Fallen: Waffe schwebt hoch
	var sway_rt := Vector3(-lr.y * 0.014, lr.x * 0.016, lr.x * 0.012 - vl.x * 0.7) * sway_m
	sway_rt = sway_rt.clamp(Vector3(-7, -7, -7), Vector3(7, 7, 7))
	var steps: int = clampi(ceili(delta / 0.008), 1, 8)
	var dt: float = delta / float(steps)
	for i in steps:
		_sway.step(sway_t, 90.0, 0.7, dt)
		_sway_r.step(sway_rt, 90.0, 0.7, dt)
		_imp.step(Vector3.ZERO, 180.0, 0.55, dt)
		_imp_r.step(Vector3.ZERO, 180.0, 0.55, dt)
		_rc.step(Vector3.ZERO, 300.0, 0.45, dt)
		_rc_r.step(Vector3.ZERO, 300.0, 0.45, dt)

	# --- Schritt-Bob (ein Schritt = PI; tiefster Punkt beim Auftreten)
	# Haltungsabhängig: geduckt ruhiger, liegend seitliches Robben statt Auf-Ab
	var stance_m: float = 1.0 - 0.35 * crouch * (1.0 - prone)
	var bm: float = bob_amt * lerpf(1.0, 0.18, ads) * stance_m
	var sn: float = sin(phase)
	var dip: float = 1.0 - absf(sn)
	var bpos := Vector3(sn * 0.007, -dip * 0.009, 0.0)
	var brot := Vector3(-dip * 0.8, sn * 0.6, sn * 1.4)
	if prone > 0.01:
		var crawl := Vector3(sn * 0.016, -dip * 0.003, -absf(sn) * 0.012)
		var crawl_r := Vector3(-dip * 0.4, sn * 2.6, sn * 4.5)
		bpos = bpos.lerp(crawl, prone)
		brot = brot.lerp(crawl_r, prone)
	if sprint > 0.01:
		bpos += Vector3(sn * 0.016, -dip * 0.014, 0.0) * sprint
		brot += Vector3(-dip * 2.0, sn * 3.0, sn * 4.0) * sprint
	# --- Atmen im Stand
	var idle: float = clampf(1.0 - bob_amt * 2.0, 0.0, 1.0) * (1.0 - sprint)
	var br: float = lerpf(1.0, 0.45, ads) * (0.5 if prone > 0.5 else 1.0)
	var breath_p := Vector3(sin(_time * 0.8) * 0.0008, sin(_time * 1.6) * 0.0012, 0.0) * idle * br
	var breath_r := Vector3(sin(_time * 1.6 + 0.6) * 0.22, sin(_time * 0.8) * 0.18, 0.0) * idle * br

	# --- Wegstecken / Ziehen (nicht geglättet, Kurve kommt vom Player)
	var hp := Vector3(0.02, -0.30, 0.06) * holster
	var hr := Vector3(-55.0, 12.0, 18.0) * holster

	_pivot.position = _base_pos + bpos * bm + breath_p + _sway.x + _imp.x + _rc.x + hp
	_pivot.rotation_degrees = _base_rot + brot * bm + breath_r + _sway_r.x + _imp_r.x + _rc_r.x + hr
	_animate_parts()

## Landung: Waffe federt nach unten (strength 0..1).
func land_impulse(strength: float) -> void:
	var st: float = clampf(strength, 0.0, 1.5)
	_imp.v += Vector3(0.0, -0.45, 0.05) * st
	_imp_r.v += Vector3(-45.0, 0.0, randf_range(-15.0, 15.0)) * st

## Allgemeiner Impuls (z.B. Slide-Start, Mantle).
func add_impulse(pos_vel: Vector3, rot_vel_deg: Vector3) -> void:
	_imp.v += pos_vel
	_imp_r.v += rot_vel_deg

## Zusätzliche Pose während des Nachladens -> [pos, rot_deg]
func _reload_pose(t: float) -> Array:
	var end: float = _reload_total
	var a: float = smoothstep(0.0, _tl("rel") + 0.12, t) * (1.0 - smoothstep(end - 0.32, end, t))
	var p := Vector3.ZERO
	var r := Vector3.ZERO
	if model_kind == "pistol":
		# Mündung hoch, nach rechts gekippt -> Magazinschacht zur Stützhand
		p = Vector3(-0.05, 0.035, 0.04) * a
		r = Vector3(14.0, 12.0, 26.0) * a
	elif is_launcher():
		# Rohr von der Schulter nehmen, Mündung nach vorn-unten: Gefechtskopf von vorn einsetzen
		p = Vector3(-0.08, -0.06, 0.06) * a
		r = Vector3(-14.0, 28.0, -10.0) * a
	else:
		# Waffe zur Mitte, nach links eingedreht -> Magazinschacht sichtbar
		p = Vector3(-0.06, 0.085, 0.01) * a
		r = Vector3(16.0, 14.0, -34.0) * a
	# Einführen: kurzer Druck nach oben
	var ins: float = smoothstep(_tl("ins0"), _tl("ins1"), t) * (1.0 - smoothstep(_tl("ins1"), _tl("ins1") + 0.12, t))
	p.y += 0.008 * ins
	# Leer: Ladehebel / Schlittenfang
	if _reload_empty:
		var b: float = smoothstep(_tl("slap") + 0.05, _tl("bolt0"), t) * (1.0 - smoothstep(_tl("bolt2") + 0.05, _tl("bolt2") + 0.3, t))
		if model_kind == "pistol":
			r += Vector3(6.0, -8.0, -10.0) * b
		else:
			p += Vector3(0.02, 0.01, 0.0) * b
			r += Vector3(4.0, 14.0, -12.0) * b
	return [p, r]

## Magazin / Ladehebel / Schlitten im Pivot-Raum bewegen.
func _animate_parts() -> void:
	if not _mag_part.is_empty():
		var node: Node3D = _mag_part.node
		var off := Vector3.ZERO
		var rot := Vector3.ZERO
		node.visible = true
		if is_launcher():
			# Gefechtskopf: nach dem Schuss weg, beim Nachladen von vorn eingeschoben
			if reloading:
				var t3: float = _reload_t
				var n0: float = _tl("new0")
				var i0: float = _tl("ins0")
				var i1: float = _tl("ins1")
				if t3 < n0:
					node.visible = false
				elif t3 < i0:
					var k3: float = smoothstep(n0, i0, t3)
					off = Vector3(0.06, -0.12, -0.35) * (1.0 - k3) + Vector3(0, 0, -0.14) * k3
					rot = Vector3(-15.0, 20.0, 0.0) * (1.0 - k3)
				elif t3 < i1:
					off = Vector3(0, 0, -0.14) * (1.0 - smoothstep(i0, i1, t3))
			elif ammo_mag <= 0:
				node.visible = false
			_set_part(_mag_part, off, rot)
		elif reloading:
			var t: float = _reload_t
			var down: Vector3 = _mag_part.down
			var out_d: float = 0.05 if model_kind == "pistol" else 0.06
			var rel: float = _tl("rel")
			var out: float = _tl("out")
			var new0: float = _tl("new0")
			var ins0: float = _tl("ins0")
			var ins1: float = _tl("ins1")
			if t < rel:
				pass
			elif t < out:
				var q: float = (t - rel) / maxf(out - rel, 0.001)
				off = down * out_d * q * q
			elif t < new0:
				node.visible = false
			elif t < ins0:
				var kk: float = smoothstep(new0, ins0, t)
				var side: float = 1.0 if model_kind == "pistol" else -1.0
				off = down * lerpf(0.22, 0.03, kk) + Vector3(0.05 * side, 0.0, 0.03) * (1.0 - kk)
				rot = Vector3(20.0, 0.0, -18.0 * side) * (1.0 - kk)
			elif t < ins1:
				off = down * 0.03 * (1.0 - smoothstep(ins0, ins1, t))
		_set_part(_mag_part, off, rot)
	if not _bolt_part.is_empty():
		var back: float = 0.0
		if model_kind == "pistol":
			var travel: float = 0.022
			if _slide_locked:
				back = travel
			elif _slide_t < 1.0:
				if _slide_t < 0.35:
					back = travel * (_slide_t / 0.35)
				else:
					back = travel * (1.0 - (_slide_t - 0.35) / 0.65)
		elif reloading and _reload_empty:
			var b0: float = _tl("bolt0")
			var b1: float = _tl("bolt1")
			var b2: float = _tl("bolt2")
			var t2: float = _reload_t
			if t2 >= b0 and t2 < b1:
				back = 0.065 * smoothstep(b0, b1, t2)
			elif t2 >= b1 and t2 < b2:
				back = 0.065
			elif t2 >= b2:
				back = 0.065 * (1.0 - clampf((t2 - b2) / 0.04, 0.0, 1.0))
		_set_part(_bolt_part, Vector3(0.0, 0.0, back), Vector3.ZERO)

func _apply_parts_rest() -> void:
	if not _mag_part.is_empty():
		(_mag_part.node as Node3D).visible = true
		_set_part(_mag_part, Vector3.ZERO, Vector3.ZERO)
	if not _bolt_part.is_empty() and not _slide_locked:
		_set_part(_bolt_part, Vector3.ZERO, Vector3.ZERO)

## Teil um seine Mitte c drehen und versetzen (Pivot-Raum) und in den Eltern-Raum zurückrechnen.
func _set_part(part: Dictionary, off: Vector3, rot_deg: Vector3) -> void:
	var c: Vector3 = part.c
	var m := Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), Vector3.ZERO)
	var full: Transform3D = Transform3D(Basis(), c + off) * m * Transform3D(Basis(), -c) * Transform3D(part.rest)
	(part.node as Node3D).transform = Transform3D(part.prel_inv) * full

## Transform von n relativ zu anc (ohne globalen Baum).
func _rel(n: Node, anc: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != anc:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _make_part(node: Node3D, down: Vector3) -> Dictionary:
	if node == null:
		return {}
	var rest: Transform3D = _rel(node, _pivot)
	var prel: Transform3D = _rel(node.get_parent(), _pivot)
	var c: Vector3 = rest.origin
	var bb: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in _collect_meshes(node):
		var b2: AABB = _rel(mi, _pivot) * mi.mesh.get_aabb()
		bb = b2 if first else bb.merge(b2)
		first = false
	if not first:
		c = bb.get_center()
	return {"node": node, "rest": rest, "prel_inv": prel.affine_inverse(), "c": c, "down": down.normalized()}

# ---------------------------------------------------------------- Modell aus Primitiven

func _get_mats() -> void:
	if _metal_mat == null:
		_metal_mat = StandardMaterial3D.new()
		_metal_mat.albedo_color = Color(0.17, 0.17, 0.18)
		_metal_mat.metallic = 0.5
		_metal_mat.roughness = 0.42
		_poly_mat = StandardMaterial3D.new()
		_poly_mat.albedo_color = Color(0.1, 0.1, 0.105)
		_poly_mat.metallic = 0.1
		_poly_mat.roughness = 0.75
		_cloth_mat = StandardMaterial3D.new()
		_cloth_mat.albedo_color = Color(0.2, 0.23, 0.15)
		_cloth_mat.roughness = 0.95

func _box(size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	_finish_part(mi, pos, rot_deg)
	return mi

## Zylinder entlang -Z (Lauf) mit Radius r und Länge seg_len
func _tube(r: float, seg_len: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = seg_len
	m.radial_segments = 12
	m.rings = 1
	mi.mesh = m
	mi.material_override = mat
	_finish_part(mi, pos, Vector3(90.0, 0.0, 0.0))
	return mi

func _finish_part(mi: MeshInstance3D, pos: Vector3, rot_deg: Vector3) -> void:
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = VIEW_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(mi)

func _build_model() -> void:
	_get_mats()
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	_pivot.add_child(muzzle)
	match model_kind:
		"pistol":
			_build_pistol()
		"g36c", "ak", "launcher":
			_build_procedural()
		_:
			_build_rifle()

## G36C / Panzerfaust (prozedural, GunModels) bzw. AK-74M (CC0-Modell, eigene Materialien).
## Mündung, Auswurf und Optik-Montage kommen aus den Metas des Modells (G36C/PzF).
func _build_procedural() -> void:
	var model: Node3D = null
	match model_kind:
		"g36c":
			model = GunModels.build_g36c()
		"ak":
			model = GunModels.build_ak()
		"launcher":
			model = GunModels.build_pzf()
	if model == null:
		_build_rifle_primitive()
		return
	model.name = "Model"
	_pivot.add_child(model)
	var xf := Transform3D(Basis.from_euler(model_rot_deg * (PI / 180.0)).scaled(Vector3.ONE * model_scale), model_offset)
	model.transform = xf
	_apply_view_layer(model, null)
	if model.has_meta("muzzle"):
		muzzle_pos = xf * (model.get_meta("muzzle") as Vector3)
	if model.has_meta("eject") and eject_pos == Vector3.ZERO:
		eject_pos = xf * (model.get_meta("eject") as Vector3)
	if model.has_meta("optic_mount") and has_red_dot:
		optic_mount = xf * (model.get_meta("optic_mount") as Vector3)
	var mag_down := Vector3(0.0, -1.0, -0.2)
	if is_launcher():
		mag_down = Vector3(0.0, -0.3, -1.0)
	_mag_part = _make_part(model.find_child("Magazine", true, false) as Node3D, mag_down)
	_bolt_part = _make_part(model.find_child("Charging_Handle", true, false) as Node3D, Vector3.BACK)
	if is_launcher() and model.has_meta("sight"):
		# Zielen durch das Klappvisier: Visier-Achse auf die Kamera-Achse
		var sp: Vector3 = xf * (model.get_meta("sight") as Vector3)
		ads_pos = Vector3(-sp.x, -sp.y, -ads_eye_dist - sp.z)
	muzzle.position = muzzle_pos
	if has_red_dot:
		_build_red_dot()

const MODEL_TEX_DIR: String = "res://assets/weapons/m4a1/"
const RED_DOT_SHADER: Shader = preload("res://game/weapons/red_dot.gdshader")

static var _gun_mat: StandardMaterial3D
static var _optic_mat: StandardMaterial3D
static var _lens_mat: ShaderMaterial
static var _pistol_mats: Dictionary = {}

func _load_model() -> Node3D:
	if model_path == "" or not ResourceLoader.exists(model_path):
		return null
	var ps: PackedScene = load(model_path) as PackedScene
	if ps == null:
		return null
	var model: Node3D = ps.instantiate() as Node3D
	model.name = "Model"
	# Mitgelieferte Animationen nicht abspielen (wir animieren selbst)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).autoplay = ""
	_pivot.add_child(model)
	model.transform = Transform3D(Basis.from_euler(model_rot_deg * (PI / 180.0)).scaled(Vector3.ONE * model_scale), model_offset)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	return model

func _build_rifle() -> void:
	var model: Node3D = _load_model()
	if model == null:
		_build_rifle_primitive()
	else:
		if _gun_mat == null:
			_gun_mat = StandardMaterial3D.new()
			_gun_mat.albedo_texture = load(MODEL_TEX_DIR + "albedo.png")
			_gun_mat.normal_enabled = true
			_gun_mat.normal_texture = load(MODEL_TEX_DIR + "normal.png")
			_gun_mat.roughness_texture = load(MODEL_TEX_DIR + "roughness.png")
			_gun_mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			_gun_mat.roughness = 1.0
			_gun_mat.metallic_texture = load(MODEL_TEX_DIR + "metallic.png")
			_gun_mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			_gun_mat.metallic = 1.0
			_gun_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_apply_view_layer(model, _gun_mat)
		_mag_part = _make_part(model.find_child("Magazine", true, false) as Node3D, Vector3(0.0, -1.0, -0.12))
		_bolt_part = _make_part(model.find_child("Charging_Handle", true, false) as Node3D, Vector3.BACK)
		# Klappkimme ausblenden: freie Sicht durch das Reflexvisier
		var rear: Node3D = model.find_child("Sight", true, false) as Node3D
		if rear and has_red_dot:
			rear.visible = false
	muzzle.position = muzzle_pos
	if has_red_dot:
		_build_red_dot()

## Alle Meshes nur für die Waffen-Kamera, ohne Schattenwurf.
func _apply_view_layer(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		var gi: GeometryInstance3D = n as GeometryInstance3D
		gi.layers = VIEW_LAYER_BIT
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mat and gi is MeshInstance3D:
			gi.material_override = mat
	for c in n.get_children():
		_apply_view_layer(c, mat)

func _optic_part(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = VIEW_LAYER_BIT
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _optic_box(parent: Node3D, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _optic_part(parent, b, pos, rot_deg, _optic_mat)

## Offenes Reflexvisier (Holosun/RMR-Stil): Basis mit Riser, Emitter hinten, dünner Rahmen,
## klares, leicht getöntes Glas; Leuchtpunkt per Shader im Unendlichen.
func _build_red_dot() -> void:
	if _optic_mat == null:
		_optic_mat = StandardMaterial3D.new()          # eloxiertes Alu, matt
		_optic_mat.albedo_color = Color(0.045, 0.047, 0.05)
		_optic_mat.metallic = 0.65
		_optic_mat.roughness = 0.42
		_optic_mat.clearcoat_enabled = true
		_optic_mat.clearcoat = 0.25
		_optic_mat.clearcoat_roughness = 0.4
		_lens_mat = ShaderMaterial.new()
		_lens_mat.shader = RED_DOT_SHADER
	var o := Node3D.new()
	o.name = "RedDot"
	o.position = optic_mount
	_pivot.add_child(o)
	var gw: float = 0.034          # Glasbreite
	var gh: float = 0.026          # Glashöhe
	var gy: float = 0.036          # Glasmitte über Schienenoberkante
	var gz: float = -0.012         # Glas vorn
	var fr: float = 0.0025         # Rahmenstärke
	var lm: ShaderMaterial = _lens_mat.duplicate() as ShaderMaterial   # pro Waffe (Ring nur G36C)
	if model_kind == "g36c":
		# Holografisches Visier (EOTech-Stil, prozedural): Haube mit Fenster, Batteriefach vorn
		var holo: Node3D = GunModels.build_holo()
		o.add_child(holo)
		_apply_view_layer(holo, null)
		lm.set_shader_parameter("ring_radius_deg", 0.55)
	else:
		_build_reflex_body(o, gw, gh, gy, gz, fr)
	# Glas (leicht nach hinten geneigt)
	var q := QuadMesh.new()
	q.size = Vector2(gw, gh)
	_optic_lens = _optic_part(o, q, Vector3(0, gy, gz), Vector3(-3.0, 0, 0), lm)
	_optic_lens.sorting_offset = 1.0
	# Punkt-Achse im Glas-Objektraum = Waffenachse (-Z des Pivots)
	lm.set_shader_parameter("axis_local", _optic_lens.basis.inverse() * Vector3(0, 0, -1))
	lm.set_shader_parameter("half_size", Vector2(gw, gh) * 0.5)
	# Zielpunkt: Glasmitte exakt auf die Kameraachse legen
	var lens_c: Vector3 = optic_mount + Vector3(0, gy, gz)
	ads_pos = Vector3(-lens_c.x, -lens_c.y, -ads_eye_dist - lens_c.z)

## Offenes Reflexvisier-Gehäuse (AK / Gewehr).
func _build_reflex_body(o: Node3D, gw: float, gh: float, gy: float, gz: float, fr: float) -> void:
	# Klemmfuß + Riser
	_optic_box(o, Vector3(0.032, 0.008, 0.052), Vector3(0, 0.004, 0.0))
	_optic_box(o, Vector3(0.026, 0.014, 0.046), Vector3(0, 0.015, 0.0))
	var knob := CylinderMesh.new()
	knob.top_radius = 0.006
	knob.bottom_radius = 0.006
	knob.height = 0.007
	_optic_part(o, knob, Vector3(0.019, 0.004, 0.006), Vector3(0, 0, 90), _optic_mat)   # Klemmschraube
	# Emitter-Gehäuse hinten (Batterie seitlich)
	# (so tief, dass es beim Zielen nicht ins Glas ragt)
	_optic_box(o, Vector3(0.03, 0.008, 0.016), Vector3(0, 0.017, 0.017))
	var batt := CylinderMesh.new()
	batt.top_radius = 0.0075
	batt.bottom_radius = 0.0075
	batt.height = 0.004
	_optic_part(o, batt, Vector3(0.0145, 0.019, 0.010), Vector3(0, 0, 90), _optic_mat)
	# Dünner Rahmen ums Glas (Pfosten, Oberleiste, Unterkante = Riser)
	var y_bot: float = gy - gh * 0.5
	var y_top: float = gy + gh * 0.5
	_optic_box(o, Vector3(gw + fr * 2.0, 0.003, 0.008), Vector3(0, y_bot - 0.0015, gz + 0.001))
	for sx: float in [-1.0, 1.0]:
		_optic_box(o, Vector3(fr, gh + 0.004, 0.006), Vector3(sx * (gw + fr) * 0.5, gy + 0.001, gz + 0.001), Vector3(-4, 0, 0))
	_optic_box(o, Vector3(gw + fr * 2.0, fr, 0.007), Vector3(0, y_top + fr * 0.5 + 0.001, gz), Vector3(-4, 0, 0))

func _build_rifle_primitive() -> void:
	_box(Vector3(0.056, 0.088, 0.32), Vector3(0, 0, -0.05), _metal_mat)             # Gehäuse
	_box(Vector3(0.05, 0.06, 0.30), Vector3(0, 0.0, -0.36), _poly_mat)              # Handschutz
	_tube(0.011, 0.26, Vector3(0, 0.012, -0.64), _metal_mat)                        # Lauf
	_tube(0.017, 0.06, Vector3(0, 0.012, -0.76), _metal_mat)                        # Mündungsfeuerdämpfer
	_box(Vector3(0.008, 0.045, 0.01), Vector3(0, 0.05, -0.70), _metal_mat)          # Korn
	_box(Vector3(0.034, 0.018, 0.2), Vector3(0, 0.053, -0.04), _metal_mat)          # Schiene
	_box(Vector3(0.026, 0.026, 0.012), Vector3(0, 0.07, 0.04), _metal_mat)          # Kimme
	_box(Vector3(0.046, 0.085, 0.24), Vector3(0, -0.012, 0.23), _poly_mat, Vector3(-4, 0, 0))  # Schaft
	_box(Vector3(0.05, 0.1, 0.02), Vector3(0, -0.018, 0.355), _poly_mat, Vector3(-4, 0, 0))    # Schaftkappe
	var mag: MeshInstance3D = _box(Vector3(0.04, 0.17, 0.075), Vector3(0, -0.14, -0.07), _metal_mat, Vector3(-9, 0, 0))  # Magazin
	_box(Vector3(0.04, 0.105, 0.05), Vector3(0, -0.1, 0.085), _poly_mat, Vector3(16, 0, 0))    # Griff
	_mag_part = _make_part(mag, Vector3(0.0, -1.0, -0.15))
	muzzle.position = Vector3(0, 0.012, -0.80)

## Pistole: HD-Modell (Sig P228, separater Schlitten/Magazin) oder Primitive als Fallback.
func _build_pistol() -> void:
	var model: Node3D = _load_model()
	if model == null:
		_build_pistol_primitive()
		return
	_apply_view_layer(model, null)
	_apply_pistol_mats(model)
	var mag: Node3D = model.find_child("magazine", true, false) as Node3D
	# Magazin gleitet entlang der Griffachse (unten-hinten)
	_mag_part = _make_part(mag, Vector3(0.0, -0.966, 0.259))
	_bolt_part = _make_part(model.find_child("slider", true, false) as Node3D, Vector3.BACK)
	muzzle.position = muzzle_pos

## Eigene PBR-Materialien (brüniert/Polymer) mit leichter triplanarer Rauheits-Variation.
func _apply_pistol_mats(n: Node) -> void:
	if _pistol_mats.is_empty():
		var noise := FastNoiseLite.new()
		noise.frequency = 0.08
		noise.fractal_octaves = 3
		var nt := NoiseTexture2D.new()
		nt.noise = noise
		nt.width = 256
		nt.height = 256
		nt.seamless = true
		var defs: Dictionary = {
			"slide": [Color(0.075, 0.076, 0.08), 0.85, 0.36],
			"frame": [Color(0.05, 0.05, 0.053), 0.55, 0.5],
			"mag": [Color(0.09, 0.09, 0.095), 0.8, 0.42],
			"part": [Color(0.13, 0.13, 0.135), 0.95, 0.3],
		}
		for key: String in defs:
			var d: Array = defs[key]
			var m := StandardMaterial3D.new()
			m.albedo_color = d[0]
			m.metallic = d[1]
			m.roughness = float(d[2]) * 1.6
			m.roughness_texture = nt
			m.uv1_triplanar = true
			m.uv1_scale = Vector3(3.0, 3.0, 3.0)
			m.clearcoat_enabled = key == "slide"
			m.clearcoat = 0.2
			_pistol_mats[key] = m
	if n is MeshInstance3D:
		var nm: String = n.name.to_lower()
		var key2: String = "part"
		if nm.begins_with("slide"):
			key2 = "slide"
		elif nm.begins_with("base"):
			key2 = "frame"
		elif nm.begins_with("magazine"):
			key2 = "mag"
		(n as MeshInstance3D).material_override = _pistol_mats[key2]
	for c in n.get_children():
		_apply_pistol_mats(c)

func _build_pistol_primitive() -> void:
	var slide: MeshInstance3D = _box(Vector3(0.03, 0.04, 0.2), Vector3(0, 0.025, -0.1), _metal_mat)   # Schlitten
	_box(Vector3(0.028, 0.03, 0.17), Vector3(0, -0.008, -0.085), _poly_mat)         # Rahmen
	_tube(0.008, 0.03, Vector3(0, 0.025, -0.205), _metal_mat)                       # Laufspitze
	_box(Vector3(0.03, 0.115, 0.05), Vector3(0, -0.07, -0.005), _poly_mat, Vector3(12, 0, 0))   # Griff
	_box(Vector3(0.01, 0.02, 0.06), Vector3(0, -0.035, -0.07), _poly_mat)           # Abzugsbügel
	_bolt_part = _make_part(slide, Vector3.BACK)
	muzzle.position = Vector3(0, 0.025, -0.222)

func _build_muzzle_flash() -> void:
	# Warmes Licht (beleuchtet auch die Welt)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.72, 0.4)
	_flash_light.light_energy = 3.0
	_flash_light.omni_range = 9.0
	_flash_light.shadow_enabled = false
	_flash_light.position = Vector3(0, 0, -0.1)
	_flash_light.visible = false
	muzzle.add_child(_flash_light)
	# Emissives Quad (Billboard, radialer Verlauf)
	if _flash_mat == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 0.95, 0.75, 1.0))
		grad.add_point(0.35, Color(1.0, 0.6, 0.2, 0.8))
		grad.set_color(grad.get_point_count() - 1, Color(1.0, 0.3, 0.05, 0.0))
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(0.5, 0.0)
		tex.width = 64
		tex.height = 64
		_flash_mat = StandardMaterial3D.new()
		_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mat.albedo_texture = tex
		_flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_flash_mat.billboard_keep_scale = true
		_flash_mat.no_depth_test = true
	_flash_mesh = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.16, 0.16) if model_kind == "pistol" else (Vector2(0.6, 0.6) if is_launcher() else Vector2(0.28, 0.28))
	_flash_mesh.mesh = q
	_flash_mesh.material_override = _flash_mat
	_flash_mesh.layers = VIEW_LAYER_BIT
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.position = Vector3(0, 0, -0.04)
	_flash_mesh.visible = false
	muzzle.add_child(_flash_mesh)
	# Funken
	_flash_particles = GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 28.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	_flash_particles.process_material = pm
	var spark := SphereMesh.new()
	spark.radius = 0.006
	spark.height = 0.012
	spark.radial_segments = 6
	spark.rings = 3
	spark.material = _tracer_spark_mat()
	_flash_particles.draw_pass_1 = spark
	_flash_particles.amount = 8
	_flash_particles.lifetime = 0.14
	_flash_particles.one_shot = true
	_flash_particles.explosiveness = 1.0
	_flash_particles.emitting = false
	_flash_particles.local_coords = false
	_flash_particles.layers = VIEW_LAYER_BIT
	_flash_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	muzzle.add_child(_flash_particles)

func _tracer_spark_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.8, 0.4)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.7, 0.3)
	m.emission_energy_multiplier = 4.0
	return m
