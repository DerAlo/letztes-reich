class_name Enemy
extends CharacterBody3D
## Gegner-Basisklasse (Rifleman/Heavy/Sturm; Drone, Marksman, Offizier erben davon).
## Zustandsmaschine, Sicht, Deckung, faire Treffsicherheit, prozeduraler Koerper, Ragdoll.
## Schnittstelle laut CONTRACTS.md: take_damage, is_alive, get_status.

enum State { IDLE, ALERT, MOVE_TO_COVER, ATTACK, ADVANCE, FLANK, DEAD }
enum CoverPhase { HIDE, PEEK, FIRE, RETURN }

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_DEBRIS := 8

# Globaler Multiplikator fuer alle Gegner (z.B. vom Lead/Debug-Server setzbar).
static var global_accuracy_scale: float = 1.0
## Schwierigkeitsgrad (Welle 4, game/progress/difficulty.gd): Soldat = 1.0 ueberall -> unveraendert.
const _Difficulty = preload("res://game/progress/difficulty.gd")
## Laub-Sichtlinie: Nadelbaum-Kronen verdecken die Sicht auch fuer Gegner (faire Sicht im Wald).
const FoliageSight = preload("res://game/enemies/foliage_sight.gd")
static var _foliage_log: int = -1
static var _cover_owner: Dictionary = {}
static var _sfx_cache: Dictionary = {}
static var _tracer_mesh: QuadMesh = null
static var _tracer_mat: ShaderMaterial = null

@export_group("Identity")
@export var enemy_type: String = "rifleman"
@export var max_health: float = 60.0
@export var body_scale: float = 1.0
@export var heavy_armor: bool = false
@export var head_damage_multiplier: float = 2.5
@export var debug_log: bool = false

@export_group("Movement")
@export var walk_speed: float = 2.4
@export var run_speed: float = 4.2
@export var strafe_speed: float = 1.3
@export var acceleration: float = 14.0
@export var turn_speed: float = 6.0
@export var gravity: float = 24.0
@export var arrive_distance: float = 0.5

@export_group("Perception")
@export var sight_range: float = 50.0
@export var fov_degrees: float = 150.0
@export var hear_weapon_range: float = 45.0
@export var hear_close_range: float = 6.0
@export var notice_time: float = 0.35
@export var reaction_min: float = 0.45
@export var reaction_max: float = 0.95
@export var alert_neighbor_radius: float = 20.0

@export_group("Tactics")
@export var cover_chance: float = 0.8
@export var cover_search_radius: float = 28.0
@export var cover_min_player_dist: float = 5.0
@export var crouch_in_cover: bool = true
@export var hide_time_min: float = 1.2
@export var hide_time_max: float = 2.8
@export var peek_cycles_min: int = 3
@export var peek_cycles_max: int = 5
@export var flank_chance: float = 0.35
@export var preferred_distance_min: float = 12.0
@export var preferred_distance_max: float = 24.0
@export var advance_segment_time: float = 2.8
@export var open_attack_max_time: float = 12.0
@export var fire_while_moving: bool = false
@export var suppress_without_los: bool = false

@export_group("Weapon")
@export var damage_per_hit: float = 8.0
@export var burst_min: int = 3
@export var burst_max: int = 5
@export var shot_interval: float = 0.16
@export var burst_pause_min: float = 1.1
@export var burst_pause_max: float = 2.4
@export var tracer_speed: float = 160.0
@export var sfx_shot: String = "enemy_rifle"

@export_group("Accuracy")
## Pro-Instanz-Multiplikator (zusaetzlich zu Enemy.global_accuracy_scale).
@export var accuracy_scale: float = 1.0
@export var type_accuracy: float = 1.0
@export var accuracy_near: float = 0.5
@export var accuracy_far: float = 0.07
@export var accuracy_near_dist: float = 6.0
@export var accuracy_far_dist: float = 45.0
@export var warmup_time: float = 1.5
@export var warmup_floor: float = 0.04
@export var moving_player_factor: float = 0.55
@export var crouching_player_factor: float = 0.7
@export var max_hit_chance: float = 0.6
@export var miss_offset_min: float = 0.45
@export var miss_offset_max: float = 1.9

@export_group("Death")
@export var cleanup_time: float = 8.5
@export var fade_start: float = 6.8
@export var death_impulse_speed: float = 3.5
@export var explosion_launch_speed: float = 13.0

@export_group("Visual")
## Geriggtes Soldatenmodell (SoldierVisual) statt Primitiv-Figur; Drohne ignoriert das.
@export var use_soldier_model: bool = true

@export_group("Colors")
@export var color_primary: Color = Color(0.2, 0.23, 0.15)
@export var color_secondary: Color = Color(0.22, 0.23, 0.24)
@export var color_armband: Color = Color(0.75, 0.04, 0.04)
@export var color_skin: Color = Color(0.62, 0.48, 0.4)

## Ordnungsfront: fast schwarze Uniform, stahlgraue Ausruestung, Amber-Armbinde mit Emblem.
const FACTION_REICH_PRIMARY := Color(0.08, 0.085, 0.095)
const FACTION_REICH_SECONDARY := Color(0.26, 0.27, 0.3)
const FACTION_REICH_ARMBAND := Color(1.0, 0.62, 0.13)
var faction: String = "ru"

var health: float = 100.0
var stat_shots: int = 0
var stat_hits: int = 0
var state: State = State.IDLE
var _age: float = 0.0
var _state_time: float = 0.0
var rng := RandomNumberGenerator.new()

# Referenzen
var _player: Node3D = null
var _player_timer: float = 0.0
var _player_vel: Vector3 = Vector3.ZERO
var _last_player_pos: Vector3 = Vector3.ZERO
var _have_last_player_pos: bool = false
var nav: NavigationAgent3D = null
var _body_shape: CollisionShape3D = null
var _head_hitbox: EnemyHitbox = null
var _exclude: Array[RID] = []

# Wahrnehmung
var _los: bool = false
var _los_timer: float = 0.0
var _sight_time: float = 0.0
var _lost_time: float = 99.0
var _notice_acc: float = 0.0
var _last_known: Vector3 = Vector3.ZERO
var _has_last_known: bool = false
var _alert_timer: float = 0.0

# Bewegung
var _desired_velocity: Vector3 = Vector3.ZERO
var _safe_velocity: Vector3 = Vector3.ZERO
var _safe_stamp: int = -100000
var _nav_repath_timer: float = 0.0
var _navmesh_cached: bool = false
var _navmesh_timer: float = 0.0
var _aim_at_target: bool = false
var _use_avoidance: bool = false

# Kampf
var _burst_left: int = 0
var _shot_timer: float = 0.0
var _pause_timer: float = 0.0
var _strafe_dir: float = 0.0
var _strafe_timer: float = 0.0
var _open_bursts: int = 0
var _open_time: float = 0.0
var _in_cover: bool = false
var _cover_node: Node3D = null
var _cover_pos: Vector3 = Vector3.ZERO
var _prev_cover: Node3D = null
var _phase_t: float = 0.0
var _cover_phase: CoverPhase = CoverPhase.HIDE:
	set(v):
		if debug_log and v != _cover_phase:
			print("[%6.2f] %s cover phase %s -> %s" % [_age, name, CoverPhase.keys()[_cover_phase], CoverPhase.keys()[v]])
		_cover_phase = v
		_phase_t = 0.0
var _hide_timer: float = 0.0
var _peek_pos: Vector3 = Vector3.ZERO
var _peek_fail: int = 0
var _cycles_done: int = 0
var _cycles_goal: int = 4
var _flank_target: Vector3 = Vector3.ZERO
var _advance_time: float = 0.0
var _fire_los_lost: float = 0.0
var _grenade_scan: float = 0.0
var _spotting: bool = false

# Koerper / Animation
var _visual: Node3D = null
var _soldier: SoldierVisual = null
var _aim_pivot: Node3D = null
var _leg_l: Node3D = null
var _leg_r: Node3D = null
var _muzzle: Node3D = null
var _flash_light: OmniLight3D = null
var _flash_timer: float = 0.0
var _parts: Array[Dictionary] = []
var _head_part: MeshInstance3D = null
var _walk_phase: float = 0.0
var _stance: float = 0.0
var _stance_target: float = 0.0
var _recoil: float = 0.0
var _flinch: float = 0.0
var _aim_pitch: float = 0.0
var _eye_height: float = 1.62

# Tod
var _death_time: float = -100.0
var _death_pos: Vector3 = Vector3.ZERO
var _last_hit_dir: Vector3 = Vector3.FORWARD
var _last_hit_head: bool = false
var _expl_pos: Vector3 = Vector3.ZERO
var _expl_radius: float = 0.0
var _expl_time: float = -100.0
var _expl_boosted: bool = false
var _ragdoll_bodies: Array[RigidBody3D] = []
## Opt-in Schleich-KI (Level "curfew"): Objekt mit tick_idle(delta)->bool, on_weapon_fired(weapon)->bool,
## on_owner_died(). null = Standardverhalten (alle anderen Level).
var stealth: Object = null

## Spielweite Zaehigkeit: alle Gegner halten 50 % mehr aus (Nutzerwunsch).
const HEALTH_SCALE: float = 1.5

func _ready() -> void:
	rng.randomize()
	max_health *= HEALTH_SCALE
	health = max_health
	add_to_group("enemy")
	add_to_group("damageable")
	collision_layer = LAYER_ENEMY
	collision_mask = LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY | 16   # 16 = move_block (grobe Bewegungsboxen der Props)
	_exclude.append(get_rid())
	_setup_nav()
	_apply_faction()
	if enemy_type != "drone":
		EnemyVoice.assign(self, enemy_type == "officer")
	_build_body()
	_cycles_goal = rng.randi_range(peek_cycles_min, peek_cycles_max)
	if not Events.weapon_fired.is_connected(_on_weapon_fired):
		Events.weapon_fired.connect(_on_weapon_fired)
	if not Events.explosion.is_connected(_on_explosion):
		Events.explosion.connect(_on_explosion)
	_strafe_timer = rng.randf_range(0.5, 2.0)

func _exit_tree() -> void:
	_release_cover()

## Fraktions-Optik (CONTRACTS Runde 3): das Level setzt vor add_child die Meta "faction".
## Nur Farben/Abzeichen, keine Werte. "ru" = Standard, "reich" = Ordnungsfront (fiktiv).
func _apply_faction() -> void:
	faction = str(get_meta("faction", "ru"))
	if faction == "reich":
		color_primary = FACTION_REICH_PRIMARY
		color_secondary = FACTION_REICH_SECONDARY
		color_armband = FACTION_REICH_ARMBAND

# ---------------------------------------------------------------- Schnittstelle

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	take_hit_part(amount, source, hit_position, hit_normal, false)

func take_hit_part(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3, headshot: bool) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	if headshot:
		amount *= head_damage_multiplier
	health -= amount
	Events.enemy_damaged.emit(self, amount)
	if VFX.is_bleeder(self):
		VFX.spawn_blood(hit_position, hit_normal)
	_flinch = 1.0
	_last_hit_head = headshot
	var dir := -hit_normal
	var src_pos := global_position
	if source is Node3D and source != self:
		src_pos = (source as Node3D).global_position
		var sd := global_position - src_pos
		sd.y = 0.0
		if sd.length() > 0.1:
			dir = sd.normalized()
	if dir.length() < 0.01:
		dir = -global_transform.basis.z
	_last_hit_dir = dir.normalized()
	if health <= 0.0:
		_die()
		return
	_bark("hit")
	_on_damaged(source, src_pos)

func is_alive() -> bool:
	return state != State.DEAD

func get_status() -> Dictionary:
	var p := global_position
	return {
		"type": enemy_type,
		"alive": state != State.DEAD,
		"health": maxf(health, 0.0),
		"position": [p.x, p.y, p.z],
		"state": State.keys()[state],
	}

## Alarmiert den Gegner (Schuss gehoert, Verbuendeter ruft, Treffer).
func alert(pos: Vector3, propagate: bool = true) -> void:
	if state == State.DEAD:
		return
	_last_known = pos
	_has_last_known = true
	if state == State.IDLE:
		_set_state(State.ALERT)
		if _spotting:
			_bark("spot")
		_alert_timer = rng.randf_range(reaction_min * 0.5, reaction_max * 0.6) * _Difficulty.enemy_reaction()
		if propagate:
			_alert_neighbors(pos)

# ---------------------------------------------------------------- Hauptschleife

func _physics_process(delta: float) -> void:
	_age += delta
	_state_time += delta
	if state == State.DEAD:
		_tick_dead(delta)
		return
	_update_perception(delta)
	_desired_velocity = Vector3.ZERO
	_use_avoidance = false
	_tick_state(delta)
	_update_facing(delta)
	_apply_motion(delta)
	_animate(delta)

func _tick_state(delta: float) -> void:
	match state:
		State.IDLE: _tick_idle(delta)
		State.ALERT: _tick_alert(delta)
		State.MOVE_TO_COVER: _tick_move_to_cover(delta)
		State.ATTACK: _tick_attack(delta)
		State.ADVANCE: _tick_advance(delta)
		State.FLANK: _tick_flank(delta)

func _tick_dead(_delta: float) -> void:
	pass

func _set_state(s: State) -> void:
	if s == state:
		_state_time = 0.0
		return
	var old := state
	state = s
	_state_time = 0.0
	if debug_log:
		print("[%6.2f] %s(%s) %s -> %s  hp=%.0f" % [_age, name, enemy_type, State.keys()[old], State.keys()[s], health])

# ---------------------------------------------------------------- Wahrnehmung

func _update_perception(delta: float) -> void:
	_player_timer -= delta
	if _player_timer <= 0.0 or (_player != null and not is_instance_valid(_player)):
		_player_timer = 0.5
		_player = Game.get_player() as Node3D
		_have_last_player_pos = false
	if _player == null:
		_los = false
		return
	var ppos := _player.global_position
	if _have_last_player_pos and delta > 0.0:
		var v := (ppos - _last_player_pos) / delta
		_player_vel = _player_vel.lerp(v, clampf(delta * 8.0, 0.0, 1.0))
	_last_player_pos = ppos
	_have_last_player_pos = true
	_grenade_scan -= delta
	if _grenade_scan <= 0.0:
		_grenade_scan = 0.3 + rng.randf() * 0.1
		_scan_grenades()
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = 0.1 + rng.randf() * 0.05
		_los = _compute_los()
	if _los:
		_sight_time += delta
		_lost_time = 0.0
		_last_known = ppos
		_has_last_known = true
	else:
		_lost_time += delta
		if _lost_time > 2.5:
			_sight_time = 0.0

func _target_alive() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.has_method("is_alive") and not _player.call("is_alive"):
		return false
	return true

func _compute_los() -> bool:
	if not _target_alive():
		return false
	var head := _player_head()
	if _eye_pos().distance_to(head) > sight_range:
		return false
	return _clear_to_player(_eye_pos(), head)

func _clear_to_player(from: Vector3, head: Vector3) -> bool:
	var r := _ray(from, head, LAYER_WORLD | LAYER_PLAYER)
	if not r.is_empty():
		var c = r["collider"]
		if not (c is Node and (c as Node).is_in_group("player")):
			return false
	# Laub (Kronen ohne Kollision): sieht der Spieler hier nicht durch, sieht der Gegner auch nicht durch
	return not _foliage_blocked(from, head)

## true, wenn Nadelbaum-Kronen die Strecke from->to verdecken (siehe foliage_sight.gd).
func _foliage_blocked(from: Vector3, to: Vector3) -> bool:
	return FoliageSight.blocks(get_tree(), from, to)

func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, _exclude)
	return get_world_3d().direct_space_state.intersect_ray(q)

func _eye_pos() -> Vector3:
	return global_position + Vector3.UP * (_eye_height * body_scale * lerpf(1.0, 0.7, _stance))

func _player_head() -> Vector3:
	if _player == null:
		return global_position + Vector3.UP * 1.6
	if _player.has_method("get_camera"):
		var cam = _player.call("get_camera")
		if cam is Node3D:
			return (cam as Node3D).global_position
	return _player.global_position + Vector3.UP * 1.6

func _player_chest() -> Vector3:
	var head := _player_head()
	var feet := _player.global_position
	return feet + (head - feet) * 0.68

func _player_crouching() -> bool:
	for prop in ["is_crouching", "crouching", "crouched"]:
		var v = _player.get(prop)
		if v is bool:
			return v
	return (_player_head().y - _player.global_position.y) < 1.3

func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _dist_to_player() -> float:
	if _player == null:
		return 999.0
	return _flat_dist(global_position, _player.global_position)

func _in_view_cone(p: Vector3) -> bool:
	var to := p - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return true
	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().dot(to.normalized()) >= cos(deg_to_rad(fov_degrees * 0.5))

func _on_weapon_fired(weapon: Node) -> void:
	if state == State.DEAD or weapon == null or not is_instance_valid(weapon):
		return
	if weapon.is_in_group("enemy") or weapon.get_parent() is Enemy:
		return
	var pos := Vector3.ZERO
	if weapon is Node3D:
		pos = (weapon as Node3D).global_position
	elif _player != null:
		pos = _player.global_position
	else:
		return
	if stealth != null and stealth.call("on_weapon_fired", weapon):
		return
	if pos.distance_to(global_position) <= hear_weapon_range:
		alert(pos, true)
		if state != State.IDLE:
			_last_known = pos
			_has_last_known = true

func _alert_neighbors(pos: Vector3) -> void:
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not (n is Enemy):
			continue
		var e := n as Enemy
		if e.global_position.distance_to(global_position) <= alert_neighbor_radius:
			e.alert(pos, false)

func _on_damaged(source: Node, src_pos: Vector3) -> void:
	_alert_neighbors(src_pos)
	if state == State.IDLE:
		alert(src_pos, false)
		_alert_timer = rng.randf_range(0.15, 0.35)
		return
	_last_known = src_pos
	_has_last_known = true
	# aus der Deckung hervorgekommen und getroffen: eher zurueckziehen
	if state == State.ATTACK and _in_cover and (_cover_phase == CoverPhase.PEEK or _cover_phase == CoverPhase.FIRE):
		if rng.randf() < 0.6:
			_burst_left = 0
			_cover_phase = CoverPhase.RETURN
	elif state == State.ALERT:
		_alert_timer = minf(_alert_timer, 0.3)

# ---------------------------------------------------------------- Zustaende

func _tick_idle(delta: float) -> void:
	if stealth != null and stealth.call("tick_idle", delta):
		return
	_aim_at_target = false
	_stance_target = 0.0
	if not _target_alive():
		return
	var d := _dist_to_player()
	var seen := _los and d <= sight_range and (_in_view_cone(_player.global_position) or d <= hear_close_range)
	if seen:
		_notice_acc += delta
		if _notice_acc >= notice_time * _Difficulty.enemy_reaction():
			_notice_acc = 0.0
			_spotting = true
			alert(_player.global_position, true)
			_spotting = false
	else:
		_notice_acc = maxf(_notice_acc - delta, 0.0)

func _tick_alert(delta: float) -> void:
	_stance_target = 0.0
	_aim_at_target = _has_last_known
	if not _target_alive():
		if _state_time > 3.0:
			_set_state(State.IDLE)
		return
	_alert_timer -= delta
	if _alert_timer > 0.0:
		return
	_decide_engage()

func _decide_engage() -> void:
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_sight_time = 0.0  # Aufwaermzeit beginnt mit dem Gefecht, nicht mit dem ersten Erspaehen
	var d := _dist_to_player()
	if rng.randf() < cover_chance and _try_take_cover():
		return
	if d > preferred_distance_max:
		_enter_advance()
	else:
		_enter_attack_open()

func _try_take_cover() -> bool:
	var cover := _find_cover()
	if cover.is_empty():
		return false
	_release_cover()
	_cover_node = cover.get("node")
	_cover_pos = cover["pos"]
	if _cover_node != null:
		_cover_owner[_cover_node.get_instance_id()] = self
	_in_cover = false
	_set_state(State.MOVE_TO_COVER)
	_bark("cover")
	return true

func _tick_move_to_cover(delta: float) -> void:
	_stance_target = 0.0
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_aim_at_target = _los
	var arrived := _move_to(_cover_pos, run_speed, delta)
	if arrived or _state_time > 12.0:
		_in_cover = arrived and _cover_node != null
		_cycles_done = 0
		_cycles_goal = rng.randi_range(peek_cycles_min, peek_cycles_max)
		_peek_fail = 0
		_cover_phase = CoverPhase.HIDE
		_hide_timer = rng.randf_range(0.5, 1.1)
		_burst_left = 0
		_pause_timer = 0.0
		_open_time = 0.0
		_open_bursts = 0
		_set_state(State.ATTACK)

func _tick_attack(delta: float) -> void:
	if not _target_alive():
		_burst_left = 0
		_stance_target = 0.0
		_aim_at_target = false
		if _state_time > 4.0:
			_set_state(State.IDLE)
		return
	_aim_at_target = true
	if _in_cover:
		_tick_cover_attack(delta)
	else:
		_tick_open_attack(delta)

func _tick_open_attack(delta: float) -> void:
	_stance_target = 0.0
	_open_time += delta
	var d := _dist_to_player()
	# Strafe leicht
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = rng.randf_range(1.2, 3.0)
		_strafe_dir = [-1.0, 0.0, 1.0][rng.randi() % 3]
	if _strafe_dir != 0.0 and _burst_left <= 0:
		var to := _player.global_position - global_position
		to.y = 0.0
		var side := to.normalized().cross(Vector3.UP)
		_desired_velocity = side * _strafe_dir * strafe_speed
	# Feuer
	if _tick_firing(delta):
		pass
	elif _pause_timer > 0.0:
		_pause_timer -= delta
	elif _los or (suppress_without_los and _has_last_known):
		_start_burst()
	# Entscheidungen
	if _lost_time > 3.5 and _state_time > 1.0:
		_bark("lost")
		_set_state(State.FLANK if rng.randf() < 0.5 else State.ADVANCE)
		_on_enter_move_state()
		return
	if _burst_left <= 0 and _pause_timer > 0.0:
		if d > preferred_distance_max + 4.0 and _open_bursts >= 2:
			_enter_advance()
		elif _open_time > open_attack_max_time:
			if rng.randf() < cover_chance and _try_take_cover():
				return
			if rng.randf() < flank_chance:
				_enter_flank()
			else:
				_open_time = 0.0

func _tick_cover_attack(delta: float) -> void:
	_phase_t += delta
	match _cover_phase:
		CoverPhase.HIDE:
			_stance_target = 1.0 if crouch_in_cover else 0.0
			_hide_timer -= delta
			if _hide_timer <= 0.0:
				if _choose_peek():
					_cover_phase = CoverPhase.PEEK
					_stance_target = 0.0
				else:
					_peek_fail += 1
					_hide_timer = rng.randf_range(0.6, 1.2)
					if _peek_fail >= 3:
						_in_cover = false
						if rng.randf() < 0.5:
							_enter_flank()
						else:
							_enter_advance()
		CoverPhase.PEEK:
			_stance_target = 0.0
			var to_peek := _peek_pos - global_position
			to_peek.y = 0.0
			if to_peek.length() > 0.12:
				_desired_velocity = to_peek.normalized() * minf(strafe_speed * 2.2, to_peek.length() * 8.0)
			if to_peek.length() <= 0.2 and _phase_t > 0.3:
				if _los:
					_start_burst()
					_cover_phase = CoverPhase.FIRE
					_fire_los_lost = 0.0
				elif _phase_t > 1.3:
					_cover_phase = CoverPhase.RETURN
			elif _phase_t > 2.5:
				_cover_phase = CoverPhase.RETURN
		CoverPhase.FIRE:
			_stance_target = 0.0
			if not _los:
				_fire_los_lost += delta
			else:
				_fire_los_lost = 0.0
			var still := _tick_firing(delta)
			if not still or _fire_los_lost > 1.0:
				_burst_left = 0
				_cover_phase = CoverPhase.RETURN
		CoverPhase.RETURN:
			_stance_target = 0.0
			var to_c := _cover_pos - global_position
			to_c.y = 0.0
			if to_c.length() > 0.15:
				_desired_velocity = to_c.normalized() * minf(strafe_speed * 2.5, to_c.length() * 8.0)
			else:
				_cycles_done += 1
				_cover_phase = CoverPhase.HIDE
				_hide_timer = rng.randf_range(hide_time_min, hide_time_max)
				if _cycles_done >= _cycles_goal:
					_release_cover()
					_in_cover = false
					if rng.randf() < flank_chance:
						_enter_flank()
					elif not _try_take_cover():
						_enter_attack_open()

func _choose_peek() -> bool:
	var head := _player_head()
	var to := head - _cover_pos
	to.y = 0.0
	if to.length() < 0.5:
		return false
	var right := to.normalized().cross(Vector3.UP).normalized()
	var offsets: Array[Vector3] = [Vector3.ZERO, right * 1.0, -right * 1.0, right * 1.8, -right * 1.8]
	if rng.randf() < 0.5:
		offsets = [right * 1.0, -right * 1.0, Vector3.ZERO, -right * 1.8, right * 1.8]
	var stand_eye := Vector3.UP * (_eye_height * body_scale)
	for off in offsets:
		var p := _cover_pos + off
		if _clear_to_player(p + stand_eye, head):
			# Weg zum Peek-Punkt muss frei sein (Hoehe Huefte)
			if off != Vector3.ZERO:
				var wall := _ray(_cover_pos + Vector3.UP * 0.9, p + Vector3.UP * 0.9, LAYER_WORLD)
				if not wall.is_empty():
					continue
			_peek_pos = p
			return true
	return false

func _tick_advance(delta: float) -> void:
	_stance_target = 0.0
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_aim_at_target = true
	_advance_time += delta
	var target := _player.global_position if _los or not _has_last_known else _last_known
	var d := _dist_to_player()
	var done := d <= rng_pref_distance()
	if not done:
		_move_to(target, walk_speed if fire_while_moving else run_speed, delta)
	if fire_while_moving:
		if not _tick_firing(delta):
			if _pause_timer > 0.0:
				_pause_timer -= delta
			elif _los or (suppress_without_los and _has_last_known):
				_start_burst()
	if done or (not fire_while_moving and _advance_time > advance_segment_time):
		_enter_attack_open()

var _pref_dist: float = -1.0

func rng_pref_distance() -> float:
	if _pref_dist < 0.0:
		_pref_dist = rng.randf_range(preferred_distance_min, preferred_distance_max)
	return _pref_dist

func _enter_advance() -> void:
	_advance_time = 0.0
	_pref_dist = -1.0
	_burst_left = 0
	_in_cover = false
	_release_cover()
	_set_state(State.ADVANCE)
	_bark("advance")

func _on_enter_move_state() -> void:
	if state == State.FLANK:
		_pick_flank_target()
	elif state == State.ADVANCE:
		_advance_time = 0.0
		_pref_dist = -1.0

func _enter_flank() -> void:
	_burst_left = 0
	_in_cover = false
	_release_cover()
	_set_state(State.FLANK)
	_pick_flank_target()
	_bark("flank")

func _pick_flank_target() -> void:
	if _player == null:
		_flank_target = global_position
		return
	var ppos := _player.global_position
	var from_p := global_position - ppos
	from_p.y = 0.0
	if from_p.length() < 0.1:
		from_p = Vector3.FORWARD
	var side := from_p.normalized().cross(Vector3.UP) * (1.0 if rng.randf() < 0.5 else -1.0)
	var r := clampf(from_p.length() * 0.8, preferred_distance_min, preferred_distance_max)
	# Kandidaten: gewuenschte Seite, Gegenseite, dann kuerzer/frontaler. Genommen wird der erste Punkt,
	# von dem aus der Spieler nicht hinter Laub steckt (kein Ausweichen ins Dickicht).
	var head := _player_head()
	var stand_eye := Vector3.UP * (_eye_height * body_scale)
	var first := Vector3.INF
	for k in 4:
		var sd := side if k % 2 == 0 else -side
		var rr := r if k < 2 else maxf(r * 0.65, preferred_distance_min * 0.75)
		var cand := ppos + sd * rr * 0.9 + from_p.normalized() * rr * (0.3 if k < 2 else 0.6)
		cand.y = global_position.y
		var snapped := _snap_to_nav(cand)
		if first == Vector3.INF:
			first = snapped
		if not _foliage_blocked(snapped + stand_eye, head):
			_flank_target = snapped
			return
	_flank_target = first

func _tick_flank(delta: float) -> void:
	_stance_target = 0.0
	if not _target_alive():
		_set_state(State.IDLE)
		return
	_aim_at_target = _los
	var arrived := _move_to(_flank_target, run_speed, delta)
	if arrived or _state_time > 10.0 or (_los and _state_time > 3.0 and _dist_to_player() < preferred_distance_max):
		_enter_attack_open()

func _enter_attack_open() -> void:
	_in_cover = false
	_burst_left = 0
	_open_time = 0.0
	_open_bursts = 0
	_pause_timer = rng.randf_range(0.2, 0.8)
	_set_state(State.ATTACK)

# ---------------------------------------------------------------- Deckung

func _find_cover() -> Dictionary:
	if _player == null:
		return {}
	var head := _player_head()
	var ppos := _player.global_position
	var my_d_player := _flat_dist(global_position, ppos)
	var crouch_eye := Vector3.UP * (_eye_height * body_scale * 0.7)
	var stand_eye := Vector3.UP * (_eye_height * body_scale)
	var best: Node3D = null
	var best_score := INF
	for c in get_tree().get_nodes_in_group("cover_point"):
		if not (c is Node3D) or c == _prev_cover:
			continue
		var cp := (c as Node3D).global_position
		var d_me := _flat_dist(cp, global_position)
		if d_me > cover_search_radius:
			continue
		var d_pl := _flat_dist(cp, ppos)
		if d_pl < cover_min_player_dist:
			continue
		var owner_e = _cover_owner.get(c.get_instance_id())
		if owner_e != null and owner_e != self and is_instance_valid(owner_e) and owner_e.state != State.DEAD:
			continue
		if _ray(cp + crouch_eye, head, LAYER_WORLD).is_empty():
			continue  # frei einsehbar
		if _foliage_blocked(cp + stand_eye, head):
			continue  # im Dickicht: von dort sieht man den Spieler nicht (und er einen selbst nicht)
		var score := d_me + absf(d_pl - (preferred_distance_min + preferred_distance_max) * 0.5) * 0.6 + rng.randf() * 4.0
		if d_pl > my_d_player + 6.0:
			score += 12.0  # hinter dem Spieler
		if score < best_score:
			best_score = score
			best = c as Node3D
	if best != null:
		return {"node": best, "pos": best.global_position}
	# Fallback: Zufallspunkt in mittlerer Distanz auf dem Navmesh
	if get_tree().get_nodes_in_group("cover_point").is_empty():
		var pt := _find_open_point()
		if pt != Vector3.INF:
			return {"node": null, "pos": pt}
	return {}

func _find_open_point() -> Vector3:
	if _player == null:
		return Vector3.INF
	var ppos := _player.global_position
	var best := Vector3.INF
	var best_d := INF
	for i in 6:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(preferred_distance_min, preferred_distance_max)
		var cand := ppos + Vector3(cos(ang), 0.0, sin(ang)) * r
		cand.y = global_position.y
		if _navmesh_ready():
			var on_nav := _snap_to_nav(cand)
			if _flat_dist(on_nav, cand) > 3.0:
				continue
			cand = on_nav
		if _foliage_blocked(cand + Vector3.UP * (_eye_height * body_scale), _player_head()):
			continue
		var d := _flat_dist(cand, global_position)
		if d < best_d:
			best_d = d
			best = cand
	return best

## Zerstoerbare Deckung (systeme-c): Deckungspunkt/-objekt ist weg -> neue Deckung suchen oder offen kaempfen.
func on_cover_lost(cover: Node) -> void:
	if state == State.DEAD:
		return
	if cover == null or _cover_node != cover:
		# Objekt selbst gemeldet (Gegner direkt dahinter): nur ohne eigene, intakte Deckung und in der Naehe
		var own_ok := _cover_node != null and is_instance_valid(_cover_node) and _cover_node.get_parent() != cover
		if own_ok or not (cover is Node3D) or _flat_dist(global_position, (cover as Node3D).global_position) > 3.5:
			return
	_release_cover()
	_in_cover = false
	if state == State.MOVE_TO_COVER or state == State.ATTACK:
		if not _try_take_cover():
			_enter_attack_open()

func _release_cover() -> void:
	if _cover_node != null and is_instance_valid(_cover_node):
		var id := _cover_node.get_instance_id()
		if _cover_owner.get(id) == self:
			_cover_owner.erase(id)
		_prev_cover = _cover_node
	_cover_node = null

# ---------------------------------------------------------------- Schiessen

func _start_burst() -> void:
	_burst_left = rng.randi_range(burst_min, burst_max)
	_shot_timer = rng.randf_range(0.12, 0.3)
	_open_bursts += 1

## Verarbeitet eine laufende Salve. Gibt true zurueck, solange die Salve laeuft.
func _tick_firing(delta: float) -> bool:
	if _burst_left <= 0:
		return false
	var can_shoot := _los or (suppress_without_los and _has_last_known)
	if not can_shoot:
		_burst_left = 0
		_pause_timer = rng.randf_range(burst_pause_min, burst_pause_max)
		return false
	_shot_timer -= delta
	if _shot_timer <= 0.0:
		_fire_shot()
		_burst_left -= 1
		_shot_timer = shot_interval
		if _burst_left <= 0:
			_pause_timer = rng.randf_range(burst_pause_min, burst_pause_max)
			return false
	return true

func hit_chance() -> float:
	if _player == null:
		return 0.0
	var d := _flat_dist(global_position, _player.global_position)
	var t := clampf((d - accuracy_near_dist) / maxf(accuracy_far_dist - accuracy_near_dist, 0.1), 0.0, 1.0)
	var p := lerpf(accuracy_near, accuracy_far, t)
	var spd := Vector2(_player_vel.x, _player_vel.z).length()
	p *= lerpf(1.0, moving_player_factor, clampf(spd / 5.0, 0.0, 1.0))
	if _player_crouching():
		p *= crouching_player_factor
	var w := clampf(_sight_time / maxf(warmup_time, 0.01), 0.0, 1.0)
	p *= lerpf(warmup_floor, 1.0, w * w)
	p *= accuracy_scale * global_accuracy_scale * type_accuracy * _Difficulty.enemy_accuracy()
	return clampf(p, 0.0, max_hit_chance)

func _fire_shot() -> void:
	if _muzzle == null or _player == null:
		return
	var from := _muzzle.global_position
	var aim := _player_chest() if _los else (_last_known + Vector3.UP * 1.0)
	var hit := _los and rng.randf() < hit_chance()
	if _foliage_log < 0:
		_foliage_log = 1 if Game.arg("foliagelog", false) else 0
	if _foliage_log == 1:
		_log_foliage_shot(hit)
	_recoil = 1.0
	_flash_timer = 0.05
	stat_shots += 1
	_play_sfx(sfx_shot)
	if hit:
		stat_hits += 1
		var point := aim + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.12, 0.12))
		_spawn_tracer(from, point)
		if _player.has_method("take_damage"):
			_player.call("take_damage", damage_per_hit, self, point, (from - point).normalized())
		return
	# Fehlschuss: knapp vorbei, sichtbar
	var dir := (aim - from).normalized()
	var perp := dir.cross(Vector3.UP)
	if perp.length() < 0.01:
		perp = Vector3.RIGHT
	perp = perp.normalized()
	var perp2 := dir.cross(perp).normalized()
	var ang := rng.randf() * TAU
	var off := (perp * cos(ang) + perp2 * sin(ang)) * rng.randf_range(miss_offset_min, miss_offset_max)
	var miss_dir := (aim + off - from).normalized()
	var far := from + miss_dir * 90.0
	var r := _ray(from, far, LAYER_WORLD)
	if r.is_empty():
		_spawn_tracer(from, from + miss_dir * 60.0)
		VFX.play_whiz_along(from, from + miss_dir * 60.0)
	else:
		var hp: Vector3 = r["position"]
		_spawn_tracer(from, hp)
		var col: Object = r.get("collider")
		if col != null and col.has_method("take_bullet"):   # zerstoerbare Deckung (systeme-c)
			col.call("take_bullet", damage_per_hit, self, hp, r["normal"], miss_dir)
		else:
			VFX.spawn_impact(hp, r["normal"], "concrete")
		VFX.play_whiz_along(from, hp)

## Messausgabe (--foliagelog): Laubtiefe Auge->Spielerkopf je Schuss, unabhaengig davon, ob die Laub-Sicht aktiv ist.
func _log_foliage_shot(hit: bool) -> void:
	var eye := _eye_pos()
	var head := _player_head()
	var dep := FoliageSight.depth(get_tree(), eye, head)
	var dist := eye.distance_to(head)
	var hidden := dep > 0.0 and dep > FoliageSight.limit_for(dist)
	var forest := FoliageSight.nearest_tree(get_tree(), global_position, 4.0) < 3.0
	print("[foliage] shot type=%s pos=%.1f,%.1f dist=%.1f depth=%.2f hidden=%d forest=%d los=%d hit=%d dmg=%.1f" % [
		enemy_type, global_position.x, global_position.z, dist, dep, int(hidden), int(forest), int(_los), int(hit),
		damage_per_hit if hit else 0.0])

func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.6 or not is_inside_tree():
		return
	if _tracer_mesh == null:
		# Leuchtstreifen statt Box (opake Box wirkte nicht wie eine Leuchtspur)
		_tracer_mesh = QuadMesh.new()
		_tracer_mat = ShaderMaterial.new()
		_tracer_mat.shader = load("res://game/vfx/shaders/tracer.gdshader")
		_tracer_mat.set_shader_parameter("length_m", 1.6)
		_tracer_mat.set_shader_parameter("width_m", 0.014)
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 3.0
	_effects_root().add_child(mi)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up), from)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to, length / tracer_speed)
	tw.tween_callback(mi.queue_free)

func _effects_root() -> Node:
	var cs := get_tree().current_scene
	return cs if cs != null else get_tree().root

# ---------------------------------------------------------------- Bewegung

func _setup_nav() -> void:
	nav = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if nav == null:
		nav = NavigationAgent3D.new()
		nav.name = "NavigationAgent3D"
		add_child(nav)
	nav.path_desired_distance = 0.6
	nav.target_desired_distance = 0.6
	nav.radius = 0.4 * body_scale
	nav.height = 1.8 * body_scale
	nav.avoidance_enabled = true
	nav.max_speed = run_speed * 1.2
	nav.path_max_distance = 3.0
	nav.velocity_computed.connect(_on_velocity_computed)

func _on_velocity_computed(v: Vector3) -> void:
	_safe_velocity = v
	_safe_stamp = Time.get_ticks_msec()

func _navmesh_ready() -> bool:
	_navmesh_timer -= get_physics_process_delta_time()
	if _navmesh_timer <= 0.0:
		_navmesh_timer = 0.5
		var map := nav.get_navigation_map() if nav != null else RID()
		_navmesh_cached = map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty() \
			and NavigationServer3D.map_get_iteration_id(map) > 0
	return _navmesh_cached

func _snap_to_nav(p: Vector3) -> Vector3:
	if _navmesh_ready():
		return NavigationServer3D.map_get_closest_point(nav.get_navigation_map(), p)
	return p

## Setzt die Wunschgeschwindigkeit Richtung Ziel. Gibt true zurueck, wenn angekommen.
func _move_to(target: Vector3, speed: float, delta: float) -> bool:
	var to_t := target - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	if dist < arrive_distance:
		return true
	var dir := to_t / dist
	if _navmesh_ready():
		_nav_repath_timer -= delta
		if _nav_repath_timer <= 0.0 or nav.target_position.distance_to(target) > 1.0:
			nav.target_position = target
			_nav_repath_timer = 0.4
		var nxt := nav.get_next_path_position()
		var d2 := nxt - global_position
		d2.y = 0.0
		if d2.length() > 0.05 and not nav.is_navigation_finished():
			dir = d2.normalized()
	_desired_velocity = dir * speed
	_use_avoidance = true
	return false

func _apply_motion(delta: float) -> void:
	var want := _desired_velocity
	if nav != null and nav.avoidance_enabled and _navmesh_ready():
		nav.velocity = want
		if _use_avoidance and Time.get_ticks_msec() - _safe_stamp < 250:
			want = _safe_velocity
			want.y = 0.0
	velocity.x = move_toward(velocity.x, want.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, want.z, acceleration * delta)
	if is_on_floor():
		velocity.y = -0.5
	else:
		velocity.y -= gravity * delta
	move_and_slide()

func _update_facing(delta: float) -> void:
	var face := Vector3.ZERO
	if _aim_at_target and _player != null and (_los or _has_last_known):
		face = (_player.global_position if _los else _last_known) - global_position
	elif Vector2(velocity.x, velocity.z).length() > 0.4:
		face = velocity
	elif _has_last_known and state == State.ALERT:
		face = _last_known - global_position
	face.y = 0.0
	if face.length() < 0.05:
		return
	var yaw := atan2(-face.x, -face.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(turn_speed * delta, 0.0, 1.0))

# ---------------------------------------------------------------- Koerper

func _mat(c: Color, rough: float = 0.85, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m

func _mesh_node(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size * body_scale
	return b

func _register_part(mi: MeshInstance3D, shape: Shape3D, mass: float) -> void:
	_parts.append({"node": mi, "shape": shape, "mass": mass})

func _box_shape(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size * body_scale
	return s

func _build_body() -> void:
	var s := body_scale
	var olive := _mat(color_primary)
	var grey := _mat(color_secondary, 0.7)
	var skin := _mat(color_skin, 0.7)
	var red := _mat(color_armband, 0.6, color_armband, 0.6)
	var dark := _mat(Color(0.08, 0.08, 0.09), 0.5)

	# Kollision
	_body_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3 * s
	cap.height = 1.45 * s
	_body_shape.shape = cap
	_body_shape.position.y = 0.725 * s
	add_child(_body_shape)

	# Kopf-Hitbox
	_head_hitbox = EnemyHitbox.new()
	_head_hitbox.enemy = self
	_head_hitbox.is_head = true
	_head_hitbox.set_meta("headshot", true)
	_head_hitbox.collision_layer = LAYER_ENEMY
	_head_hitbox.collision_mask = 0
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.17 * s
	hs.shape = sph
	_head_hitbox.add_child(hs)
	_head_hitbox.position = Vector3(0.0, 1.64 * s, 0.0)
	add_child(_head_hitbox)
	add_collision_exception_with(_head_hitbox)
	_exclude.append(_head_hitbox.get_rid())

	if use_soldier_model and ResourceLoader.exists(SoldierVisual.RIG_PATH):
		_soldier = SoldierVisual.new()
		add_child(_soldier)
		_soldier.setup(self)
		_visual = _soldier
		_muzzle = _soldier.muzzle
		_flash_light = _soldier.flash_light
		# Kopf-Hitbox folgt dem Kopfknochen (Weltradius bleibt 0.17 * body_scale)
		sph.radius = 0.17 * s / _soldier.vis_scale
		_head_hitbox.reparent(_soldier.head_attach, false)
		_head_hitbox.position = _soldier.head_hit_offset
		return

	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)

	# Beine
	_leg_l = Node3D.new()
	_leg_l.position = Vector3(-0.12 * s, 0.78 * s, 0.0)
	_visual.add_child(_leg_l)
	_leg_r = Node3D.new()
	_leg_r.position = Vector3(0.12 * s, 0.78 * s, 0.0)
	_visual.add_child(_leg_r)
	var leg_size := Vector3(0.17, 0.76, 0.21)
	for leg in [_leg_l, _leg_r]:
		var lm := _mesh_node(leg, _box(leg_size), olive, Vector3(0.0, -0.38 * s, 0.0))
		_register_part(lm, _box_shape(leg_size), 8.0 * s * s * s)
		_mesh_node(lm, _box(Vector3(0.19, 0.12, 0.3)), dark, Vector3(0.0, -0.33 * s, -0.04 * s))

	# Torso
	var torso_mesh := CapsuleMesh.new()
	torso_mesh.radius = 0.25 * s
	torso_mesh.height = 0.78 * s
	var torso := _mesh_node(_visual, torso_mesh, olive, Vector3(0.0, 1.12 * s, 0.0))
	var torso_shape := CapsuleShape3D.new()
	torso_shape.radius = 0.25 * s
	torso_shape.height = 0.78 * s
	_register_part(torso, torso_shape, 24.0 * s * s * s)
	_mesh_node(torso, _box(Vector3(0.46, 0.34, 0.3)), grey, Vector3(0.0, 0.1 * s, -0.02 * s))  # Weste
	if heavy_armor:
		_mesh_node(torso, _box(Vector3(0.62, 0.22, 0.38)), grey, Vector3(0.0, 0.3 * s, 0.0))  # Schulterplatten
		_mesh_node(torso, _box(Vector3(0.5, 0.45, 0.08)), grey, Vector3(0.0, 0.05 * s, -0.2 * s))  # Brustplatte
		_mesh_node(torso, _box(Vector3(0.36, 0.5, 0.16)), grey, Vector3(0.0, 0.0, 0.28 * s))  # Rucksack

	# Kopf + Helm
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15 * s
	head_mesh.height = 0.3 * s
	var head := _mesh_node(_visual, head_mesh, skin, Vector3(0.0, 1.64 * s, 0.0))
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.15 * s
	_register_part(head, head_shape, 4.0 * s * s * s)
	_head_part = head
	var helm_mesh := SphereMesh.new()
	helm_mesh.radius = 0.175 * s
	helm_mesh.height = 0.3 * s
	var helm := _mesh_node(head, helm_mesh, olive, Vector3(0.0, 0.04 * s, 0.0))
	helm.scale = Vector3(1.0, 0.85, 1.0)
	if heavy_armor:
		_mesh_node(head, _box(Vector3(0.3, 0.1, 0.06)), dark, Vector3(0.0, 0.0, -0.15 * s))  # Visier

	# Zielpivot mit Armen und Waffe
	_aim_pivot = Node3D.new()
	_aim_pivot.position = Vector3(0.0, 1.35 * s, 0.0)
	_visual.add_child(_aim_pivot)
	var arm_r_size := Vector3(0.11, 0.11, 0.44)
	var arm_r := _mesh_node(_aim_pivot, _box(arm_r_size), olive, Vector3(0.2 * s, -0.08 * s, -0.2 * s))
	_register_part(arm_r, _box_shape(arm_r_size), 3.0 * s * s * s)
	var arm_l := _mesh_node(_aim_pivot, _box(arm_r_size), olive, Vector3(-0.17 * s, -0.1 * s, -0.3 * s))
	_register_part(arm_l, _box_shape(arm_r_size), 3.0 * s * s * s)
	_mesh_node(arm_l, _box(Vector3(0.14, 0.14, 0.1)), red, Vector3(0.0, 0.0, 0.08 * s))  # Armbinde (Fraktionsfarbe)
	var gun_len := 0.72 if not heavy_armor else 0.95
	var gun_size := Vector3(0.07, 0.11, gun_len)
	var gun := _mesh_node(_aim_pivot, _box(gun_size), dark, Vector3(0.03 * s, -0.06 * s, -0.5 * s))
	_register_part(gun, _box_shape(gun_size), 3.0 * s * s * s)
	_mesh_node(gun, _box(Vector3(0.03, 0.03, 0.4)), dark, Vector3(0.0, 0.01 * s, -(gun_len * 0.5 + 0.18) * s))  # Lauf
	_mesh_node(gun, _box(Vector3(0.06, 0.14, 0.22)), olive, Vector3(0.0, -0.03 * s, (gun_len * 0.5 + 0.08) * s))  # Schaft
	if heavy_armor:
		_mesh_node(gun, _box(Vector3(0.16, 0.16, 0.16)), grey, Vector3(0.0, -0.14 * s, 0.05 * s))  # Munitionstrommel
	else:
		_mesh_node(gun, _box(Vector3(0.05, 0.16, 0.07)), dark, Vector3(0.0, -0.12 * s, -0.05 * s))  # Magazin
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.03 * s, -0.05 * s, -(0.5 + gun_len * 0.5 + 0.38) * s)
	_aim_pivot.add_child(_muzzle)
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.75, 0.35)
	_flash_light.omni_range = 5.0
	_flash_light.light_energy = 0.0
	_flash_light.shadow_enabled = false
	_muzzle.add_child(_flash_light)

# ---------------------------------------------------------------- Animation

func _animate(delta: float) -> void:
	_stance = move_toward(_stance, _stance_target, delta * 4.5)
	if _soldier != null:
		if _body_shape != null:
			var scap := _body_shape.shape as CapsuleShape3D
			scap.height = 1.45 * body_scale * lerpf(1.0, 0.7, _stance)
			_body_shape.position.y = scap.height * 0.5
		_flinch = move_toward(_flinch, 0.0, delta * 5.0)
		_recoil = move_toward(_recoil, 0.0, delta * 9.0)
		if _flash_timer > 0.0:
			# kurzes, abklingendes Flackern statt konstantem Leuchten
			_flash_light.light_energy = 3.2 * pow(clampf(_flash_timer / 0.05, 0.0, 1.0), 2.0)
			_flash_timer -= delta
		else:
			_flash_light.light_energy = 0.0
		_soldier.tick(delta)
		return
	var squash := lerpf(1.0, 0.7, _stance)
	_visual.scale = Vector3(1.0, squash, 1.0)
	if _body_shape != null:
		var cap := _body_shape.shape as CapsuleShape3D
		cap.height = 1.45 * body_scale * squash
		_body_shape.position.y = cap.height * 0.5
	if _head_hitbox != null:
		_head_hitbox.position.y = 1.64 * body_scale * squash

	var spd := Vector2(velocity.x, velocity.z).length()
	_walk_phase += spd * delta * 2.4
	var amp := clampf(spd / 3.0, 0.0, 1.0)
	_leg_l.rotation.x = sin(_walk_phase) * 0.7 * amp
	_leg_r.rotation.x = -sin(_walk_phase) * 0.7 * amp
	_visual.position.y = absf(sin(_walk_phase)) * 0.05 * amp * body_scale

	_flinch = move_toward(_flinch, 0.0, delta * 5.0)
	_recoil = move_toward(_recoil, 0.0, delta * 9.0)
	# Zielen: Pitch zum Ziel
	var target_pitch := 0.0
	if _aim_at_target and _player != null and (_los or _has_last_known):
		var tp := _player_chest() if _los else _last_known
		var from := _aim_pivot.global_position
		var dv := tp - from
		var flat := Vector2(dv.x, dv.z).length()
		target_pitch = clampf(atan2(dv.y, maxf(flat, 0.1)), -0.9, 0.9)
	_aim_pitch = lerpf(_aim_pitch, target_pitch, clampf(delta * 10.0, 0.0, 1.0))
	_aim_pivot.rotation.x = _aim_pitch + _recoil * 0.07
	_aim_pivot.position.z = _recoil * 0.07 * body_scale
	_visual.rotation.x = -_flinch * 0.22
	_visual.rotation.z = sin(_age * 40.0) * _flinch * 0.05
	# Muendungsfeuer
	if _flash_timer > 0.0:
		# kurzes, abklingendes Flackern statt konstantem Leuchten
		_flash_light.light_energy = 3.2 * pow(clampf(_flash_timer / 0.05, 0.0, 1.0), 2.0)
		_flash_timer -= delta
	else:
		_flash_light.light_energy = 0.0

# ---------------------------------------------------------------- Tod

func _on_explosion(pos: Vector3, radius: float, _strength: float) -> void:
	if state == State.DEAD:
		if not _expl_boosted and _age - _death_time < 0.3 and _death_pos.distance_to(pos) <= radius * 1.15 + 0.5:
			_expl_boosted = true
			if _soldier != null:
				_soldier.boost_explosion(pos, radius)
				return
			for rb in _ragdoll_bodies:
				if is_instance_valid(rb):
					rb.apply_central_impulse(_launch_vector(rb.global_position, pos, radius) * rb.mass)
					rb.angular_velocity = _rand_spin(10.0)
		return
	if global_position.distance_to(pos) <= radius * 1.15 + 0.5:
		_expl_pos = pos
		_expl_radius = radius
		_expl_time = _age

func _launch_vector(from: Vector3, expl: Vector3, radius: float) -> Vector3:
	var d := from - expl
	var dist := d.length()
	var dir := d.normalized() if dist > 0.05 else Vector3.UP
	dir.y = maxf(dir.y, 0.0) + 0.55
	var falloff := clampf(1.0 - dist / maxf(radius * 1.2, 0.1), 0.35, 1.0)
	return dir.normalized() * explosion_launch_speed * falloff * rng.randf_range(0.8, 1.25)

func _rand_spin(mag: float) -> Vector3:
	return Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * mag

func _die() -> void:
	if state == State.DEAD:
		return
	_set_state(State.DEAD)
	_death_time = _age
	_death_pos = global_position
	remove_from_group("enemy")
	remove_from_group("damageable")
	collision_layer = 0
	collision_mask = 0
	if _head_hitbox != null:
		_head_hitbox.collision_layer = 0
	_release_cover()
	_burst_left = 0
	Events.enemy_killed.emit(self)
	if stealth != null:
		stealth.call("on_owner_died")   # lautlos: kein Todesschrei, keine Kameraden-Meldung
	else:
		_bark("death")
		_notify_ally_death()
	_on_death()

func _on_death() -> void:
	var explosive := _age - _expl_time < 0.3
	_spawn_ragdoll(explosive)
	if explosive:
		_expl_boosted = true
	get_tree().create_timer(cleanup_time).timeout.connect(queue_free)

func _spawn_ragdoll(explosive: bool) -> void:
	if _soldier != null:
		_soldier.die(explosive)
		return
	_visual.scale = Vector3.ONE
	_visual.rotation = Vector3.ZERO
	_visual.position = Vector3.ZERO
	_aim_pivot.position.z = 0.0
	var impulse_dir := _last_hit_dir
	impulse_dir.y = 0.4
	impulse_dir = impulse_dir.normalized()
	for part in _parts:
		var mi: MeshInstance3D = part["node"]
		var gt := mi.global_transform
		var rb := RigidBody3D.new()
		rb.collision_layer = LAYER_DEBRIS
		rb.collision_mask = LAYER_WORLD
		rb.mass = part["mass"]
		rb.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.8
		pm.bounce = 0.15
		rb.physics_material_override = pm
		add_child(rb)
		rb.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
		var cs := CollisionShape3D.new()
		cs.shape = part["shape"]
		rb.add_child(cs)
		mi.reparent(rb, false)
		mi.transform = Transform3D.IDENTITY
		_ragdoll_bodies.append(rb)
		var v: Vector3
		if explosive:
			v = _launch_vector(rb.global_position, _expl_pos, _expl_radius)
			rb.angular_velocity = _rand_spin(10.0)
		else:
			var boost := 1.4 if _last_hit_head and mi == _head_part else 1.0
			v = impulse_dir * death_impulse_speed * boost * rng.randf_range(0.7, 1.3)
			rb.angular_velocity = _rand_spin(3.0)
		rb.linear_velocity = v
	_visual.visible = false
	# Ausblenden
	var tw := create_tween()
	tw.set_parallel(true)
	var fade_dur := maxf(cleanup_time - fade_start - 0.3, 0.2)
	for part in _parts:
		var node: MeshInstance3D = part["node"]
		tw.tween_property(node, "transparency", 1.0, fade_dur).set_delay(fade_start)
		for ch in node.get_children():  # Weste, Helm, Armbinde ...
			if ch is GeometryInstance3D:
				tw.tween_property(ch, "transparency", 1.0, fade_dur).set_delay(fade_start)

# ---------------------------------------------------------------- Stimme / Befehle

## Zuruf ueber EnemyVoice (Drohnen haben keine Stimme).
func _bark(situation: String, chance_mul: float = 1.0, force: bool = false) -> bool:
	if not has_meta("voice"):
		return false
	return EnemyVoice.bark(self, situation, chance_mul, force)

func _scan_grenades() -> void:
	if state == State.IDLE:
		return
	for g in get_tree().get_nodes_in_group("grenade"):
		if not (g is Node3D) or g.has_meta("barked"):
			continue
		if (g as Node3D).global_position.distance_to(global_position) < 8.0:
			if _bark("grenade"):
				g.set_meta("barked", true)
			return

## Ein Kamerad in der Naehe meldet den Verlust (etwas verzoegert, nicht immer).
func _notify_ally_death() -> void:
	var best: Enemy = null
	var best_d := 26.0
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not (n is Enemy) or not n.has_meta("voice"):
			continue
		var d := (n as Enemy).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = n
	if best == null:
		return
	best.on_ally_died(self)
	var who := best
	get_tree().create_timer(rng.randf_range(0.6, 1.3)).timeout.connect(func() -> void:
		if is_instance_valid(who) and who.is_alive():
			who._bark("mandown"))

## Hook: ein Verbuendeter in der Naehe ist gefallen.
func on_ally_died(_ally: Enemy) -> void:
	pass

## Befehl eines Offiziers. kind: "advance" | "flank" | "mark". Gibt true zurueck, wenn befolgt.
func receive_order(kind: String, pos: Vector3) -> bool:
	if state == State.DEAD or enemy_type == "drone":
		return false
	_last_known = pos
	_has_last_known = true
	if state == State.IDLE:
		alert(pos, false)
		return kind == "mark"
	if kind == "mark":
		return true
	if state != State.ATTACK or _burst_left > 0:
		return false
	if kind == "advance":
		_enter_advance()
	else:
		_enter_flank()
	return true

## Kurzes Zoegern (z. B. Offizier gefallen): Salve abbrechen, Pause verlaengern.
func hesitate(seconds: float) -> void:
	if state == State.DEAD:
		return
	_burst_left = 0
	_pause_timer = maxf(_pause_timer, 0.0) + seconds
	_alert_timer += seconds * 0.5

# ---------------------------------------------------------------- Sound

func _play_sfx(sfx_name: String, at: Vector3 = Vector3.INF) -> void:
	if sfx_name == "" or not is_inside_tree():
		return
	var stream: AudioStream = null
	if _sfx_cache.has(sfx_name):
		stream = _sfx_cache[sfx_name]
	else:
		for ext in ["ogg", "wav"]:
			var path := "res://assets/sfx/%s.%s" % [sfx_name, ext]
			if ResourceLoader.exists(path):
				stream = load(path) as AudioStream
				break
		_sfx_cache[sfx_name] = stream
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.unit_size = 12.0
	p.max_distance = 250.0 if sfx_name.begins_with("enemy_rifle") or sfx_name.begins_with("enemy_mg") else 120.0
	_effects_root().add_child(p)
	p.global_position = global_position + Vector3.UP if at == Vector3.INF else at
	p.finished.connect(p.queue_free)
	p.play()
