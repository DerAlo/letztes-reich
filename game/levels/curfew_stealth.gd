extends Node
## Schleich-Direktor fuer "curfew": Licht am Spieler, Geraeuschradius, Leichen, Alarmzustand.
## Watcher (Wachen, Drohne, Suchscheinwerfer) melden sich hier an; das HUD liest sie aus.
## Konkrete Alarmfolgen (Tor zu, Sirene, Verstaerkung, Loeschen) erledigt das Level ueber die Signale.

signal alarm_raised(reason: String, pos: Vector3, first: bool)
signal alarm_ended
signal body_reported(pos: Vector3)

const AMBIENT := 0.05
const LIGHT_K := 0.30
const ALARM_DECAY := 28.0

var level: Node3D
var watchers: Array = []
var bodies: Array = []             ## [{"enemy": Enemy, "pos": Vector3, "found": bool}]
var player_light: float = 0.0      ## 0 = stockdunkel, 1 = voll beleuchtet
var noise_radius: float = 0.0
var alarm: bool = false
var alarm_count: int = 0
var heightened_t: float = 0.0      ## nach Alarm/Leichenfund: Wachen aufmerksamer
var enabled: bool = true

var _lights: Array[Light3D] = []
var _gather_t: float = 0.0
var _light_t: float = 0.0
var _no_los_t: float = 0.0
var _player: Node3D

func _init(lvl: Node3D) -> void:
	level = lvl
	name = "CurfewStealth"

func register_watcher(w: Object) -> void:
	if not watchers.has(w):
		watchers.append(w)

func register_body(e: Node3D) -> void:
	var p := e.global_position
	if "_death_pos" in e:
		p = e.get("_death_pos")
	bodies.append({"enemy": e, "pos": p, "found": false})

func alert_mult() -> float:
	if alarm:
		return 1.4
	return 1.25 if heightened_t > 0.0 else 1.0

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
		if _player == null:
			return
	heightened_t = maxf(0.0, heightened_t - delta)
	_gather_t -= delta
	if _gather_t <= 0.0:
		_gather_t = 3.0
		_gather_lights()
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.15
		var chest := _player.global_position + Vector3.UP * (0.7 if bool(_player.get("is_crouching")) else 1.1)
		var l := light_at(chest)
		player_light = lerpf(player_light, l, 0.6)
	_update_noise()
	if alarm:
		_update_alarm(delta)

func _update_noise() -> void:
	var v: Vector3 = _player.get("velocity")
	var spd := Vector2(v.x, v.z).length()
	if spd < 0.6 or not bool(_player.call("is_alive")):
		noise_radius = 0.0
	elif bool(_player.get("is_crouching")):
		noise_radius = 0.8
	elif bool(_player.get("_sprinting")):
		noise_radius = 10.0
	else:
		noise_radius = 3.5

func _gather_lights() -> void:
	_lights.clear()
	for n in level.find_children("*", "Light3D", true, false):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		if not l.visible or not l.is_visible_in_tree() or l.light_energy < 0.05 or l.has_meta("no_stealth"):
			continue
		_lights.append(l)

## Helligkeit an einem Punkt (0..1): Umgebungslicht plus Omni-/Spotlichter mit Verdeckungstest.
func light_at(p: Vector3) -> float:
	var sum := AMBIENT
	var space := level.get_world_3d().direct_space_state
	for l in _lights:
		if not is_instance_valid(l) or not l.visible or l.light_energy < 0.05:
			continue
		var lp := l.global_position
		var d := lp.distance_to(p)
		var rng := 0.0
		var k := 1.0
		if l is OmniLight3D:
			rng = (l as OmniLight3D).omni_range
		elif l is SpotLight3D:
			var sl := l as SpotLight3D
			rng = sl.spot_range
			if d > 0.05:
				var fwd := -sl.global_transform.basis.z
				var cang := fwd.dot((p - lp) / d)
				var edge := cos(deg_to_rad(sl.spot_angle))
				if cang < edge:
					continue
				k = clampf((cang - edge) / maxf(0.0001, 1.0 - edge) * 3.0, 0.0, 1.0)
		if d >= rng:
			continue
		var f := 1.0 - d / rng
		var c := f * f * l.light_energy * LIGHT_K * k
		if c < 0.02:
			continue
		var q := PhysicsRayQueryParameters3D.create(lp, p, 1)
		if not space.intersect_ray(q).is_empty():
			continue
		sum += c
		if sum >= 1.0:
			return 1.0
	return clampf(sum, 0.0, 1.0)

# ------------------------------------------------------------------ Alarm

## reason: "spotted" | "shot" | "body" | "drone" | "searchlight"
func raise_alarm(pos: Vector3, reason: String, spotted: bool) -> void:
	if not enabled:
		return
	var first := not alarm
	alarm = true
	_no_los_t = 0.0
	heightened_t = 90.0
	if first:
		alarm_count += 1
	for w in watchers:
		if not is_instance_valid(w) or not w.has_method("join_combat"):
			continue
		var e: Node3D = w.get("enemy")
		if e == null or not is_instance_valid(e):
			continue
		var d := e.global_position.distance_to(pos)
		if spotted and d <= 40.0:
			w.call("join_combat", pos)
		elif d <= 60.0:
			w.call("start_search", pos)
	alarm_raised.emit(reason, pos, first)

func report_body(b: Dictionary, finder_pos: Vector3) -> void:
	for x: Dictionary in bodies:
		if x["pos"].distance_to(b["pos"]) < 6.0:
			x["found"] = true
	body_reported.emit(b["pos"])
	raise_alarm(finder_pos, "body", false)

func end_alarm() -> void:
	if not alarm:
		return
	alarm = false
	_no_los_t = 0.0
	for w in watchers:
		if is_instance_valid(w) and w.has_method("stand_down"):
			w.call("stand_down")
	alarm_ended.emit()

func _update_alarm(delta: float) -> void:
	var seen := false
	for n in get_tree().get_nodes_in_group("enemy"):
		var e := n as Enemy
		if e == null or not e.is_alive():
			continue
		if e._los and e.state != Enemy.State.IDLE:
			seen = true
			break
	for w in watchers:
		if is_instance_valid(w) and w.has_method("get_watch_state") and int(w.call("get_watch_state")) == 2 and not w.has_method("join_combat"):
			seen = true   # Drohne/Scheinwerfer haben Kerner im Licht
	_no_los_t = 0.0 if seen else _no_los_t + delta
	if _no_los_t >= ALARM_DECAY:
		end_alarm()

## Alle Wachen zurueck an den Streifenanfang (Neustart nach Loeschung/Tod).
func reset_all() -> void:
	alarm = false
	_no_los_t = 0.0
	heightened_t = 30.0
	for w in watchers:
		if is_instance_valid(w) and w.has_method("reset_home"):
			w.call("reset_home")

## Hoechster Zustand aller Watcher (fuer die Statusanzeige): -1 keiner, 0..2
func top_state() -> int:
	var best := 0
	for w in watchers:
		if is_instance_valid(w) and w.has_method("get_watch_state"):
			best = maxi(best, int(w.call("get_watch_state")))
	return best
