extends Enemy
## Offizier / Funker: kaempft vorsichtig aus Deckung, koordiniert aber die Gruppe:
## - markiert kurz nach Gefechtsbeginn die Spielerposition (Verbuendete im Umkreis werden alarmiert),
## - befiehlt alle 9–13 s Vorruecken oder Flankieren (1–2 Schuetzen in der Naehe),
## - ruft einmalig Verstaerkung (2 Schuetzen, ausser Sicht hinter ihm), wenn seine Gruppe fast aufgerieben ist –
##   nur wenn er nach dem Funkspruch noch lebt (Offizier zuerst ausschalten lohnt sich),
## - faellt er, zoegern Verbuendete in der Naehe kurz.

const MARK_RADIUS := 40.0
const ORDER_RADIUS := 30.0
const REINF_CHECK_RADIUS := 45.0
const REINF_DELAY := 6.0
const MAX_REINF_PER_LEVEL := 4
const REINF_SCENE := "res://game/enemies/rifleman.tscn"
const NO_ORDERS := ["heavy", "marksman", "officer", "drone"]

var _combat_t: float = 0.0
var _marked: bool = false
var _order_timer: float = 10.0
var _reinf_done: bool = false

func _ready() -> void:
	super._ready()
	_order_timer = rng.randf_range(9.0, 13.0)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if state == State.DEAD or state == State.IDLE or state == State.ALERT:
		return
	if not _target_alive():
		return
	_combat_t += delta
	if not _marked and _combat_t > 1.5 and _has_last_known:
		_marked = true
		_give_mark()
	_order_timer -= delta
	if _order_timer <= 0.0:
		_order_timer = rng.randf_range(9.0, 13.0)
		_give_order()
	if not _reinf_done and _combat_t > 10.0:
		_check_reinforcements()

func _allies(radius: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if n == self or not (n is Enemy):
			continue
		var e := n as Enemy
		if e.is_alive() and e.global_position.distance_to(global_position) <= radius:
			out.append(e)
	return out

func _target_pos() -> Vector3:
	return _player.global_position if _los and _player != null else _last_known

func _give_mark() -> void:
	_bark("order_mark")
	var p := _target_pos()
	for e in _allies(MARK_RADIUS):
		e.receive_order("mark", p)

func _give_order() -> void:
	if not (_los or _has_last_known):
		return
	var cands: Array[Enemy] = []
	for e in _allies(ORDER_RADIUS):
		if e.enemy_type in NO_ORDERS or e.state != State.ATTACK or e._burst_left > 0:
			continue
		cands.append(e)
	if cands.is_empty():
		return
	var kind := "flank" if rng.randf() < 0.5 else "advance"
	if not _bark("order_" + kind):
		return
	cands.shuffle()
	var n := mini(cands.size(), rng.randi_range(1, 2))
	var p := _target_pos()
	var chosen := cands.slice(0, n)
	get_tree().create_timer(rng.randf_range(0.5, 0.9)).timeout.connect(func() -> void:
		for e in chosen:
			if is_instance_valid(e) and e.is_alive():
				e.receive_order(kind, p))

func _check_reinforcements() -> void:
	var near := 1
	for e in _allies(REINF_CHECK_RADIUS):
		if e.enemy_type != "drone":
			near += 1
	if near > 3:
		return
	var root := get_tree().current_scene
	var used: int = int(root.get_meta("officer_reinf", 0)) if root != null else 0
	if used >= MAX_REINF_PER_LEVEL:
		_reinf_done = true
		return
	_reinf_done = true
	_bark("order_reinf", 1.0, true)
	get_tree().create_timer(REINF_DELAY).timeout.connect(_spawn_reinforcements)

func _spawn_reinforcements() -> void:
	if not is_instance_valid(self) or not is_alive() or _player == null or not is_instance_valid(_player):
		return
	var root := get_tree().current_scene
	var used: int = int(root.get_meta("officer_reinf", 0)) if root != null else 0
	var scene := load(REINF_SCENE) as PackedScene
	if scene == null:
		return
	var away := global_position - _player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else -global_transform.basis.z
	var side := away.cross(Vector3.UP)
	var spawned := 0
	var tries := 0
	while spawned < 2 and tries < 14 and used < MAX_REINF_PER_LEVEL:
		tries += 1
		var cand := global_position + away * rng.randf_range(12.0, 18.0) + side * rng.randf_range(-7.0, 7.0)
		cand = _snap_to_nav(cand)
		if absf(cand.y - global_position.y) > 3.0:
			continue
		if not _hidden_from_player(cand):
			continue
		var e := scene.instantiate() as Enemy
		e.set_meta("faction", faction)
		get_parent().add_child(e)
		e.global_position = cand
		e.alert(_target_pos(), false)
		spawned += 1
		used += 1
	if root != null:
		root.set_meta("officer_reinf", used)

func _hidden_from_player(p: Vector3) -> bool:
	var head := _player_head()
	var r := _ray(head, p + Vector3.UP * 1.4, LAYER_WORLD)
	return not r.is_empty()

func _die() -> void:
	var was_alive := state != State.DEAD
	super._die()
	if not was_alive:
		return
	for e in _allies(25.0):
		if e.enemy_type != "drone":
			e.hesitate(rng.randf_range(1.0, 1.8))
