extends Node
## Statistik eines Levellaufs (Welle 4, systeme-a). main.gd legt pro Levelstart einen Tracker an (Kind von Main,
## PROCESS_MODE_ALWAYS) und holt beim Levelende stats(). Liest nur vorhandene Events und Level-Variablen –
## kein Level-Skript muss dafuer etwas tun.
##
## Gezaehlt: Einsatzzeit (Spielzeit ohne Pause/Briefing), Schuesse und Treffer des Spielers (wie autopilot.gd),
## Abschuesse und Kopfschuss-Abschuesse (Enemy._last_hit_head), Tode, erlittener Schaden,
## Geisel-Zwischenfaelle (Signale shot_by_player/executed von breach_hostage), Alarme (level.director.alarm_count,
## curfew/kanalisation) sowie optional das Maximum einer Level-Variable (STAR_GOALS "prop", z. B. hafen _weber_hits).

var level: Node = null
var level_name: String = ""
var watch_prop: String = ""

var time: float = 0.0
var shots: int = 0
var hits: int = 0
var kills: int = 0
var headshot_kills: int = 0
var deaths: int = 0
var damage_taken: float = 0.0
var hostage_incidents: int = 0
var alarms: int = -1          ## -1 = Level hat keinen Schleich-Direktor
var prop_max: int = -1        ## -1 = Variable nicht gefunden
var finished: bool = false

var _last_expl_frame: int = -100
var _poll_t: float = 0.0


func setup(lvl: Node, lname: String, goal: Dictionary) -> void:
	level = lvl
	level_name = lname
	watch_prop = str(goal.get("prop", ""))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.weapon_fired.connect(_on_weapon_fired)
	Events.enemy_damaged.connect(_on_enemy_damaged)
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.player_died.connect(func() -> void:
		if not finished:
			deaths += 1)
	Events.player_damaged.connect(func(amount: float, _src: Node) -> void:
		if not finished:
			damage_taken += amount)
	Events.explosion.connect(func(_p: Vector3, _r: float, _s: float) -> void:
		_last_expl_frame = Engine.get_physics_frames())
	get_tree().node_added.connect(_on_node_added)
	# Geiseln, die schon im Baum sind (Level baut im _ready)
	_scan_hostages(level)


func _process(delta: float) -> void:
	if finished or get_tree().paused:
		return
	if level == null or not is_instance_valid(level) or not level.is_inside_tree():
		return
	time += delta
	_poll_t -= delta
	if _poll_t <= 0.0:
		_poll_t = 0.5
		_poll()


## Alarme und Level-Variable mitschreiben (Maximum, falls das Level sie bei einem Neuansatz zuruecksetzt).
func _poll() -> void:
	if level == null or not is_instance_valid(level):
		return
	var dir = level.get("director")
	if dir is Object and is_instance_valid(dir) and "alarm_count" in dir:
		alarms = maxi(alarms, int(dir.get("alarm_count")))
	if watch_prop != "" and watch_prop in level:
		prop_max = maxi(prop_max, int(level.get(watch_prop)))


func _is_enemy_weapon(w: Node) -> bool:
	if w == null or not is_instance_valid(w):
		return false
	return w.is_in_group("enemy") or (w.get_parent() != null and w.get_parent().is_in_group("enemy"))


func _on_weapon_fired(w: Node) -> void:
	if finished or _is_enemy_weapon(w):
		return
	shots += 1


func _on_enemy_damaged(_e: Node, _amount: float) -> void:
	if finished:
		return
	if absi(Engine.get_physics_frames() - _last_expl_frame) > 1:
		hits += 1


func _on_enemy_killed(e: Node) -> void:
	if finished:
		return
	kills += 1
	if e != null and is_instance_valid(e) and "_last_hit_head" in e and bool(e.get("_last_hit_head")):
		headshot_kills += 1


func _on_node_added(n: Node) -> void:
	if finished:
		return
	_hook_hostage(n)


func _scan_hostages(n: Node) -> void:
	if n == null:
		return
	_hook_hostage(n)
	for c in n.get_children():
		_scan_hostages(c)


func _hook_hostage(n: Node) -> void:
	if not n.has_signal("shot_by_player"):
		return
	if not n.is_connected("shot_by_player", _on_hostage_incident):
		n.connect("shot_by_player", _on_hostage_incident)
	if n.has_signal("executed") and not n.is_connected("executed", _on_hostage_incident):
		n.connect("executed", _on_hostage_incident)


func _on_hostage_incident(_h: Node) -> void:
	if not finished:
		hostage_incidents += 1


## Lauf abschliessen und Statistik liefern.
func finish(difficulty: String) -> Dictionary:
	if not finished:
		_poll()
		finished = true
	var acc := float(hits) / float(shots) if shots > 0 else 0.0
	return {
		"level": level_name, "result": "completed", "time": snappedf(time, 0.1), "shots": shots, "hits": hits,
		"accuracy": minf(acc, 1.0), "kills": kills, "headshot_kills": headshot_kills, "deaths": deaths,
		"damage_taken": snappedf(damage_taken, 0.1), "hostage_incidents": hostage_incidents, "alarms": alarms,
		"prop_max": prop_max, "difficulty": difficulty,
	}


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
