extends Node
## Squad-Befehle light (Welle 4): Kerner gibt seiner Begleiterin mit einer Taste Befehle.
##
## Steuerung (umbelegbar, Aktionen in InputConfig, Gruppe "Begleiter"):
##   X kurz  ("squad_order"): Kontextbefehl auf das Fadenkreuz.
##             Gegner im Visier -> "Feuer auf Ziel", Boden/Wand -> "Dort hin" (danach haelt sie dort).
##   X halten (>= 0,4 s) oder H ("squad_hold"): Halt <-> Folgen.
## Rueckmeldung: kurze Funkzeile der Begleiterin (Varianten, nie zweimal dieselbe hintereinander, Abklingzeit,
## schweigt, wenn gerade Story-Funk laeuft), Statusfeld unten links und Marker im Raum (squad_hud.gd).
## Beim ersten Mal ein Tutorial-Hinweis (Settings "game/squad_hint_seen").
##
## Opt-in pro Level (ohne diesen Knoten sind X/H wirkungslos):
##     var squad := preload("res://game/squad/squad_orders.gd").new()
##     add_child(squad)
##     squad.companion = mein_begleiter   # z. B. game/squad/companion.gd, oder ein eigenes Objekt mit dem Interface
## Der Autopilot gibt keine Befehle. Programmatisch (Tests, Skripte): issue_attack/issue_move/issue_hold/issue_follow.

const SD := preload("res://game/story/story_data.gd")
const SquadHud := preload("res://game/squad/squad_hud.gd")
const HOLD_TIME := 0.4
const LINE_COOLDOWN := 2.2
const HINT_KEY := "game/squad_hint_seen"

## Begleiter-Objekt (Interface siehe companion.gd). null = keine Befehle moeglich.
var companion: Object = null:
	set(v):
		if companion != null and is_instance_valid(companion) and companion.has_signal("event"):
			if companion.is_connected("event", _on_companion_event):
				companion.disconnect("event", _on_companion_event)
		companion = v
		if companion != null and companion.has_signal("event"):
			companion.connect("event", _on_companion_event)
var companion_name: String = "Lena"
var speaker: String = SD.LENA
var max_range: float = 420.0          ## Reichweite des Ziel-Strahls (Kran-Scharfschuetze: 150-350 m)
var aim_assist_deg: float = 2.5       ## Gegner knapp neben dem Fadenkreuz zaehlen noch als Ziel
var input_enabled: bool = true
var voice_enabled: bool = true
var show_tutorial: bool = true
var tutorial_text: String = ""        ## leer = Standardtext

## Funkzeilen je Anlass (Level duerfen einzelne Listen ersetzen). Sprecher: `speaker` (SD.LENA).
var lines: Dictionary = {
	"attack": ["Feuer auf Ziel!", "Hab ihn. Feuer!", "Ziel erfasst, ich schieße.", "Verstanden, ich nehm ihn unter Feuer."],
	"move": ["Bin unterwegs.", "Verstanden, ich geh rüber.", "Okay, ich wechsel die Position.", "Bewege mich."],
	"hold": ["Ich halte hier.", "Verstanden, ich bleib stehen.", "Halte Position.", "Okay, ich warte hier."],
	"follow": ["Ich bin hinter dir.", "Komme nach.", "Verstanden, ich folge.", "Bin wieder bei dir."],
	"arrived": ["Bin in Position.", "Position erreicht.", "Stehe. Was jetzt?"],
	"target_down": ["Ziel ist down.", "Der steht nicht mehr auf.", "Erledigt."],
	"blocked": ["Da komm ich nicht hin.", "Kein Durchkommen.", "Negativ, da ist kein Weg."],
	"friendly": ["Nicht schießen, das ist kein Feind!", "Negativ, das sind Unbeteiligte."],
	"auto_follow": ["Warte, ich schließ auf.", "Du bist zu weit weg, ich komm nach."],
}

var _hud: CanvasLayer = null
var _press_t: float = -1.0
var _press_done: bool = false
var _last_line_t: float = -100.0
var _last_used: Dictionary = {}       ## anlass -> zuletzt gesprochene Zeile
var _time: float = 0.0
var _key_cache: Dictionary = {}
var _cinematic: bool = false
var _was_active: bool = false
var _snd: AudioStreamPlayer = null
var _bot: bool = false

func _ready() -> void:
	name = "SquadOrders"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	InputConfig.ensure_actions()
	_bot = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_hud = SquadHud.new()
	_hud.set("orders", self)
	add_child(_hud)
	_snd = AudioStreamPlayer.new()
	_snd.bus = &"SFX" if AudioServer.get_bus_index("SFX") >= 0 else &"Master"
	add_child(_snd)
	Events.story_cinematic.connect(func(on: bool) -> void: _cinematic = on)

# ------------------------------------------------------------------ Zustand / Anzeige

func is_active() -> bool:
	return companion != null and is_instance_valid(companion) and bool(companion.call("is_available")) and not _cinematic

func order_label() -> String:
	if companion == null or not is_instance_valid(companion):
		return ""
	var base := ""
	match str(companion.call("current_order")):
		"follow": base = "FOLGT"
		"hold": base = "HÄLT POSITION"
		"move": base = "UNTERWEGS"
		"return": base = "ZURÜCK AUF DIE ROUTE"
	if companion.has_method("attack_target") and companion.call("attack_target") != null:
		base = "FEUER AUF ZIEL · " + base
	return base

func order_short() -> String:
	if companion == null or not is_instance_valid(companion):
		return ""
	match str(companion.call("current_order")):
		"hold": return "HALT"
		"move": return "DORT HIN"
		"return": return "ROUTE"
	return ""

## Anzeigename der Taste; gecacht (Abfrage am DisplayServer nur ca. 1x pro Sekunde, headless gar nicht).
func key_name(action: String) -> String:
	var c: Array = _key_cache.get(action, [])
	if not c.is_empty() and _time - float(c[0]) < 1.0:
		return str(c[1])
	var ev := InputConfig.get_binding(action, 0)
	if ev == null:
		ev = InputConfig.get_binding(action, 1)
	var s := ""
	if DisplayServer.get_name() == "headless":
		if ev is InputEventKey:
			s = OS.get_keycode_string((ev as InputEventKey).physical_keycode if (ev as InputEventKey).keycode == KEY_NONE else (ev as InputEventKey).keycode)
	else:
		s = InputConfig.event_label(ev)
	s = s if s != "" else "—"
	_key_cache[action] = [_time, s]
	return s

# ------------------------------------------------------------------ Eingabe

func _process(delta: float) -> void:
	_time += delta
	var active := is_active()
	if active and not _was_active:
		_maybe_tutorial()
	_was_active = active
	if not active or not input_enabled or _player_dead():
		_press_t = -1.0
		return
	if InputMap.has_action("squad_hold") and Input.is_action_just_pressed("squad_hold"):
		toggle_hold()
	if not InputMap.has_action("squad_order"):
		return
	if Input.is_action_just_pressed("squad_order"):
		_press_t = _time
		_press_done = false
	if _press_t >= 0.0:
		if Input.is_action_pressed("squad_order"):
			if not _press_done and _time - _press_t >= HOLD_TIME:
				_press_done = true
				toggle_hold()
		else:
			if not _press_done:
				issue_context()
			_press_t = -1.0

func _player_dead() -> bool:
	var p := Game.get_player()
	return p != null and p.has_method("is_alive") and not bool(p.call("is_alive"))

# ------------------------------------------------------------------ Befehle (auch programmatisch)

## Kontextbefehl auf das Fadenkreuz: Gegner -> Feuer, Boden -> dort hin.
func issue_context() -> bool:
	if not is_active():
		return false
	var pick := pick_aim()
	match str(pick.get("kind", "")):
		"enemy":
			return issue_attack(pick["node"])
		"friendly":
			_feedback("friendly", "KEIN FEIND")
			return false
		"ground":
			return issue_move(pick["pos"])
	_click(false)
	_flash("KEIN ZIEL")
	return false

func toggle_hold() -> bool:
	if not is_active():
		return false
	if str(companion.call("current_order")) == "follow":
		return issue_hold()
	return issue_follow()

func issue_follow() -> bool:
	return _do("follow", companion.call("order_follow") if is_active() else false)

func issue_hold() -> bool:
	if not is_active():
		return false
	var a: Variant = companion.get("actor")
	var pos: Vector3 = (a as Node3D).global_position if a is Node3D and is_instance_valid(a) else Vector3.INF
	return _do("hold", companion.call("order_hold", pos))

func issue_move(pos: Vector3) -> bool:
	return _do("move", companion.call("order_move", pos) if is_active() else false)

func issue_attack(t: Node3D) -> bool:
	return _do("attack", companion.call("order_attack", t) if is_active() else false)

func _do(kind: String, ok: Variant) -> bool:
	if bool(ok):
		_click(true)
		say(kind)
		return true
	var why := str(companion.get("reject_reason")) if companion != null and is_instance_valid(companion) else "unavailable"
	match why:
		"blocked": _feedback("blocked", "KEIN WEG")
		"friendly": _feedback("friendly", "KEIN FEIND")
		_:
			_click(false)
			_flash("NICHT MÖGLICH")
	return false

# ------------------------------------------------------------------ Zielsuche

## Was liegt unter dem Fadenkreuz? {"kind": "enemy"|"friendly"|"ground"|"", "node", "pos"}
func pick_aim() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.global_position
	var dir := -cam.global_transform.basis.z
	var to := from + dir * max_range
	var ex: Array[RID] = []
	var pl := Game.get_player()
	if pl is CollisionObject3D:
		ex.append((pl as CollisionObject3D).get_rid())
	var a: Variant = companion.get("actor") if companion != null else null
	if a is CollisionObject3D and is_instance_valid(a):
		ex.append((a as CollisionObject3D).get_rid())
	var space := cam.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, ex)
	var hit := space.intersect_ray(q)
	var hit_d := max_range
	if not hit.is_empty():
		var col := hit.get("collider") as Node
		hit_d = from.distance_to(hit["position"])
		var en := _owner_in_group(col, "enemy")
		if en != null and not en.is_in_group("vehicle"):
			return {"kind": "enemy", "node": en, "pos": hit["position"]}
		if _owner_in_group(col, "friendly") != null or _owner_in_group(col, "no_shoot") != null:
			return {"kind": "friendly", "node": col, "pos": hit["position"]}
	# Zielhilfe: Gegner knapp neben dem Fadenkreuz, frei sichtbar, vor dem Treffpunkt
	var best: Node3D = null
	var best_ang := deg_to_rad(aim_assist_deg)
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or (n as Node).is_in_group("vehicle"):
			continue
		if n.has_method("is_alive") and not bool(n.call("is_alive")):
			continue
		var tp := (n as Node3D).global_position + Vector3.UP * 1.1
		var v := tp - from
		var d := v.length()
		if d > hit_d + 1.5 or d < 0.5:
			continue
		var ang := dir.angle_to(v / d)
		if ang >= best_ang:
			continue
		var q2 := PhysicsRayQueryParameters3D.create(from, tp, 1, ex)
		if not space.intersect_ray(q2).is_empty():
			continue
		best_ang = ang
		best = n
	if best != null:
		return {"kind": "enemy", "node": best, "pos": best.global_position}
	if hit.is_empty():
		return {}
	var p: Vector3 = hit["position"]
	var nrm: Vector3 = hit.get("normal", Vector3.UP)
	if nrm.y < 0.6:
		# Wand: etwas davor auf den Boden projizieren
		var base := p + nrm * 0.6
		var q3 := PhysicsRayQueryParameters3D.create(base + Vector3.UP * 0.3, base + Vector3.DOWN * 4.0, 1, ex)
		var down := space.intersect_ray(q3)
		if down.is_empty():
			return {}
		p = down["position"]
	return {"kind": "ground", "pos": p}

static func _owner_in_group(n: Node, group: String) -> Node:
	while n != null:
		if n.is_in_group(group):
			return n
		n = n.get_parent()
	return null

# ------------------------------------------------------------------ Funk / Rueckmeldung

func _on_companion_event(kind: String) -> void:
	say(kind)

## Funkzeile zum Anlass (falls gerade Ruhe ist und die Abklingzeit um ist). Rueckgabe: gesprochen?
func say(kind: String) -> bool:
	if not voice_enabled or not lines.has(kind):
		return false
	if _time - _last_line_t < LINE_COOLDOWN or _story_busy():
		return false
	var pool: Array = lines[kind]
	if pool.is_empty():
		return false
	var choices: Array = pool.filter(func(s: Variant) -> bool: return s != _last_used.get(kind, ""))
	if choices.is_empty():
		choices = pool
	var text: String = choices[randi() % choices.size()]
	_last_used[kind] = text
	_last_line_t = _time
	Events.story_radio.emit(speaker, text, clampf(1.2 + 0.05 * text.length(), 1.8, 3.0))
	return true

## Laeuft gerade Story-Funk (oder steht welcher an)? Dann keine Bestaetigung dazwischen.
func _story_busy() -> bool:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui == null:
		return false
	var q: Variant = ui.get("_queue")
	return bool(ui.get("_showing")) or (q is Array and not (q as Array).is_empty())

func _feedback(kind: String, flash_text: String) -> void:
	_click(false)
	_flash(flash_text)
	say(kind)

func _flash(text: String) -> void:
	if _hud != null:
		_hud.call("flash", text)

func _click(ok: bool) -> void:
	if _snd == null:
		return
	var st := Sfx.get_stream("gunship_switch" if ok else "dry_fire")
	if st == null:
		return
	_snd.stream = st
	_snd.volume_db = -14.0 if ok else -12.0
	_snd.play()

func _maybe_tutorial() -> void:
	if not show_tutorial or _bot or _hud == null:
		return
	var st := get_node_or_null("/root/Settings")
	if st != null and bool(st.call("get_value", HINT_KEY, false)):
		return
	var txt := tutorial_text
	if txt == "":
		txt = "%s hört auf dich:  [%s] aufs Ziel = Feuer · auf den Boden = Dort hin  ·  [%s] (oder %s halten) = Halt / Folgen" % [
			companion_name, key_name("squad_order"), key_name("squad_hold"), key_name("squad_order")]
	_hud.call("show_hint", txt, 11.0)
	if st != null:
		st.call("set_value", HINT_KEY, true)
