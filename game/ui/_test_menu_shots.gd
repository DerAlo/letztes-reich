extends Node
## Testszene (nicht im Export): Screenshots von Pausenmenue und allen Einstellungsreitern nach captures/menu/.
## Start (Fenstermodus, nicht headless):
##   Godot --path . res://game/ui/_test_menu_shots.tscn -- --level=berlin --no-briefing --no-settings

var _out := "res://captures/menu/"
var _main: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.call("set_value", "game/pause_on_focus", false)
		st.call("set_value", "game/unlocked", ["baltic_night", "test_range", "river_crossing", "rail_yard", "berlin"])
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_run()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(_out + name + ".png"))
	print("[shots] " + name)


func _run() -> void:
	await _wait(2.0)
	# Warten, bis das Level laeuft (erste Frames kompilieren Shader) und die Aufblende vorbei ist
	var pm0: Node = _main.get_node("PauseMenu")
	var t0 := Time.get_ticks_msec()
	while (float(pm0.get("_mission_time")) < float(Game.arg("warmup", 6.0)) 			or (_main.get("_black") as ColorRect).color.a > 0.01) and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	# Fiktiver Auftrag fuer den Kopfbereich, falls das Level noch keinen gesetzt hat
	var pm: Node = _main.get_node("PauseMenu")
	if str(pm.get("_objective")) == "":
		Events.story_objective.emit("Zum Reichstag vorrücken. Funkverbindung zu Lena halten.")
	print("[shots] level=%s paused=%s t=%s black=%s" % [_main.get("_level"), get_tree().paused, pm.get("_mission_time"), (_main.get("_black") as ColorRect).color.a])
	pm.call("open")
	await _wait(0.6)
	await _shot("01_pause")
	pm.call("_on_item", "missions")
	await _wait(0.3)
	await _shot("02_missions")
	pm.call("_back")
	pm.call("_on_item", "quit")
	await _wait(0.3)
	await _shot("03_quit_confirm")
	pm.call("_back")
	pm.call("_on_item", "settings")
	var sm: Node = pm.get("_settings_page")
	var names := ["10_steuerung", "11_tasten", "12_spiel", "13_audio", "14_grafik"]
	for i in names.size():
		sm.call("show_tab", i)
		await _wait(0.35)
		await _shot(names[i])
	# Tasten: Zuweisung laeuft + Konflikt sichtbar
	sm.call("show_tab", 1)
	await _wait(0.2)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_W
	InputConfig.set_binding("jump", 1, ev)
	sm.call("refresh_binds")
	var rows: Array = sm.get("_rows")
	for r in rows:
		if r.get("action") == "reload":
			var b: Button = (r.get("buttons") as Array)[0]
			b.grab_focus()
			sm.call("start_capture", "reload", 0, b)
	await _wait(0.4)
	await _shot("15_tasten_zuweisung")
	await _functional(pm, sm)
	get_tree().quit()


func _esc() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_ESCAPE
	k.keycode = KEY_ESCAPE
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().process_frame
	var u := k.duplicate() as InputEventKey
	u.pressed = false
	Input.parse_input_event(u)
	await get_tree().process_frame
	await get_tree().process_frame


## Ablauf-Test: ESC-Ebenen, Checkpoint, Neustart, Missionswechsel (Ausgabe "[func] ...").
func _functional(pm: Node, sm: Node) -> void:
	await _esc()   # Zuweisung abbrechen
	print("[func] nach ESC 1: capturing=%s open=%s page=%s" % [sm.call("is_capturing"), pm.get("is_open"), pm.get("_page")])
	await _esc()   # Einstellungen -> Hauptseite
	print("[func] nach ESC 2: open=%s page=%s" % [pm.get("is_open"), pm.get("_page")])
	await _esc()   # schliessen
	print("[func] nach ESC 3: open=%s paused=%s" % [pm.get("is_open"), get_tree().paused])
	await _esc()   # oeffnen
	print("[func] nach ESC 4: open=%s paused=%s" % [pm.get("is_open"), get_tree().paused])
	pm.call("_on_item", "checkpoint")
	await _wait(1.5)
	print("[func] Checkpoint: open=%s paused=%s fade=%.2f" % [pm.get("is_open"), get_tree().paused, (pm.get("_fade") as ColorRect).color.a])
	pm.call("open")
	pm.call("_transition", func() -> void: _main.call("restart_level"))
	await _wait(3.0)
	print("[func] Neustart: level=%s paused=%s open=%s briefing=%s" % [_main.get("_level_name"), get_tree().paused, pm.get("is_open"), _main.get("_in_briefing")])
	pm.call("open")
	pm.call("_transition", func() -> void: _main.call("goto_level", "curfew"))
	await _wait(4.0)
	print("[func] Wechsel: level=%s paused=%s unlocked=%s" % [_main.get("_level_name"), get_tree().paused, _main.call("unlocked_levels")])

