extends "res://game/enemies/enemy.gd"
## Level 7 "Kaltes Auge": Puppen-Figur ohne eigene KI (vom Level gesteuert: Ziel, Tempo, Haltung, Zielpunkt).
## role "friendly": Widerstandskaempfer (Gruppe "friendly", hellblaue Armbinde) -- Spielertreffer meldet das Level.
## role "weber":    Weber hinter der Panzertuer -- unverwundbar, Treffer meldet das Level ("Panzerglas").
## role "enemy":    Ordnungsfront-Posten/-Schuetzen: normale Treffer/Tod (enemy_killed), aber keine eigene KI.
## Wahrnehmung/Zustaende der Basisklasse bleiben aus; Bewegung/Animation/Schuesse der Basisklasse werden genutzt.

var role: String = "friendly"
var invulnerable: bool = false
var level_ref: Node = null
var unarmed: bool = false

# --- Steuerung durch das Level
var goal: Vector3 = Vector3.ZERO
var has_goal: bool = false
var goal_speed: float = 1.4
var use_nav: bool = true
var aiming: bool = false
var aim_point: Vector3 = Vector3.ZERO
var crouch: bool = false
var hold_aim: float = 0.0          # s Anschlag halten (Waffe oben ohne Schuss)
var frozen: bool = false           # komplett still (z. B. im Fahrzeug)

func _ready() -> void:
	super._ready()
	if role != "enemy":
		remove_from_group("enemy")
		remove_from_group("damageable")
	if role == "friendly":
		add_to_group("friendly")
	if has_meta("voice"):
		remove_meta("voice")   # keine Gegner-Barks
	if unarmed and _soldier != null:
		var w := _soldier.find_child("Weapon", true, false)
		if w is Node3D:
			(w as Node3D).visible = false

func _physics_process(delta: float) -> void:
	_age += delta
	_state_time += delta
	if state == State.DEAD:
		_tick_dead(delta)
		return
	if frozen:
		return
	if _player == null or not is_instance_valid(_player):
		_player = Game.get_player() as Node3D
	_desired_velocity = Vector3.ZERO
	_use_avoidance = false
	if has_goal:
		var to_t := goal - global_position
		to_t.y = 0.0
		if to_t.length() < arrive_distance:
			has_goal = false
		elif use_nav:
			_move_to(goal, goal_speed, delta)
		else:
			_desired_velocity = to_t.normalized() * goal_speed
	_stance_target = 1.0 if crouch else 0.0
	hold_aim = maxf(0.0, hold_aim - delta)
	var aim_now: bool = (aiming or hold_aim > 0.0) and _player != null
	_aim_at_target = aim_now
	_los = false
	_has_last_known = aim_now
	if aim_now:
		_last_known = aim_point
	_update_facing(delta)
	_apply_motion(delta)
	_animate(delta)

## Laeuft zu p (Bodenpunkte ueber das Navmesh, Hochbauten direkt).
func walk_to(p: Vector3, speed: float, nav_ok: bool = true) -> void:
	goal = p
	has_goal = true
	goal_speed = speed
	use_nav = nav_ok

func arrived() -> bool:
	return not has_goal

## Kosmetischer Schuss auf einen Punkt: Muendungsfeuer, Knall, Leuchtspur (kein Schaden).
func puppet_fire(target: Vector3, spread: float = 0.6) -> void:
	if state == State.DEAD or _muzzle == null or unarmed:
		return
	aim_point = target
	hold_aim = maxf(hold_aim, 1.2)
	_burst_left = 1
	_recoil = 1.0
	_flash_timer = 0.05
	stat_shots += 1
	_play_sfx(sfx_shot)
	var to := target + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.5, spread), rng.randf_range(-spread, spread))
	_spawn_tracer(_muzzle.global_position, to)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(self):
			_burst_left = 0)

func muzzle_pos() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position + Vector3.UP * 1.4

func scope_pos() -> Vector3:
	if _soldier != null and _soldier.scope_tip != null and is_instance_valid(_soldier.scope_tip):
		return _soldier.scope_tip.global_position
	return muzzle_pos()

func _on_weapon_fired(_weapon: Node) -> void:
	pass

func _bark(_situation: String, _chance_mul: float = 1.0, _force: bool = false) -> bool:
	return false

func take_hit_part(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3, headshot: bool) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	if role == "enemy":
		super.take_hit_part(amount, source, hit_position, hit_normal, headshot)
		if state != State.DEAD and level_ref != null and level_ref.has_method("on_enemy_wounded"):
			level_ref.call("on_enemy_wounded", self)
		return
	var from_player: bool = source != null and is_instance_valid(source) and source.is_in_group("player")
	if role == "weber":
		VFX.spawn_impact(hit_position, hit_normal, "metal")
		if from_player and level_ref != null and level_ref.has_method("on_weber_hit"):
			level_ref.call("on_weber_hit")
		return
	if from_player and level_ref != null and level_ref.has_method("on_friendly_hit"):
		level_ref.call("on_friendly_hit", self)
	VFX.spawn_blood(hit_position, hit_normal)
	_flinch = 1.0
	if source is Node3D and source != self:
		var sd := global_position - (source as Node3D).global_position
		sd.y = 0.0
		if sd.length() > 0.1:
			_last_hit_dir = sd.normalized()
	if invulnerable:
		return
	if headshot:
		amount *= head_damage_multiplier
	health -= amount
	if health <= 0.0:
		_die()

func _die() -> void:
	if state == State.DEAD:
		return
	if role == "enemy":
		super._die()
		return
	_set_state(State.DEAD)
	_death_time = _age
	_death_pos = global_position
	remove_from_group("friendly")
	collision_layer = 0
	collision_mask = 0
	if _head_hitbox != null:
		_head_hitbox.collision_layer = 0
	_burst_left = 0
	if level_ref != null and level_ref.has_method("on_friendly_died"):
		level_ref.call("on_friendly_died", self)
	_on_death()
