extends Node
## Globaler Spielzustand, Input-Map, Kommandozeilen-Args.

var args: Dictionary = {}  # User-Args nach "--": --key=value oder --flag -> true

func _enter_tree() -> void:
	_parse_args()
	_setup_input()
	process_mode = Node.PROCESS_MODE_ALWAYS

## Nach allen Autoloads (Settings existiert dann): gespeicherte Tastenbelegung und Audio-Optionen anwenden.
## Ohne gespeicherte Werte (Bots/Tools laden nie) aendert sich nichts.
const AUDIO_PREFS_PATH := "res://game/ui/audio_prefs.gd"

func _ready() -> void:
	_apply_user_config.call_deferred()
	_start_max_time_watchdog()

## Werkzeug-Notbremse (--max-time=N): beendet Godot spaetestens nach echter Laufzeit, unabhaengig von
## Pause, Respawn-Schleifen, Time-Scale oder ob --autopilot laeuft. Ohne Autopilot: N echte Sekunden.
## Mit Autopilot zaehlt dieser weiter Sim-Sekunden; die Notbremse greift dann erst bei 2*N + 120 s echt
## und laesst den Autopilot noch sauber mit result=timeout_real abschliessen (Telemetrie/Review).
func _start_max_time_watchdog() -> void:
	var mt := float(arg("max-time", 0.0))
	if mt <= 0.0:
		return
	var ap := str(arg("autopilot", "")) not in ["", "false", "0"]
	var limit := (mt * 2.0 + 120.0) if ap else mt
	var t := get_tree().create_timer(limit, true, false, true)   # process_always, echte Zeit
	t.timeout.connect(_on_max_time_watchdog.bind(limit))

func _on_max_time_watchdog(limit: float) -> void:
	print("[game] --max-time Notbremse: %.0f s echte Laufzeit erreicht, beende" % limit)
	var ap := get_node_or_null("/root/DebugServer/Autopilot")
	if ap != null and ap.has_method("_finish") and not bool(ap.get("_finished")):
		ap.call("_finish", "timeout_real")
	else:
		var rv := get_node_or_null("/root/DebugServer/Review")
		if rv != null and rv.has_method("finish"):
			rv.call("finish", "timeout_real")
	get_tree().quit()

func _apply_user_config() -> void:
	InputConfig.apply_saved()
	if ResourceLoader.exists(AUDIO_PREFS_PATH) and get_node_or_null("AudioPrefs") == null:
		var ap: Node = (load(AUDIO_PREFS_PATH) as GDScript).new()
		ap.name = "AudioPrefs"
		add_child(ap)

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else true

func arg(key: String, default = null):
	return args.get(key, default)

func get_player() -> Node:
	return get_tree().get_first_node_in_group("player")

func _setup_input() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_C, "reload": KEY_R,
		"grenade": KEY_G, "interact": KEY_E, "pause": KEY_ESCAPE,
		"prone": KEY_Z, "weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_last": KEY_Q,
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[action]
		InputMap.action_add_event(action, ev)
	# Hinlegen zusätzlich auf der logischen Z-Taste (QWERTZ: Z liegt physisch auf Y)
	var prone_logical := InputEventKey.new()
	prone_logical.keycode = KEY_Z
	InputMap.action_add_event("prone", prone_logical)
	var mouse := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT,
		"weapon_next": MOUSE_BUTTON_WHEEL_DOWN, "weapon_prev": MOUSE_BUTTON_WHEEL_UP}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)
