extends Node
## Testszene (nicht im Export): Hauptmenue durchklicken, Screenshots nach captures/main_menu/ und Ablauf pruefen:
## Fortsetzen -> richtige Mission, Pause -> Hauptmenue, Missionsauswahl -> richtige Mission, Neue Kampagne (Reset).
## Start (Fenster, nicht headless; --no-settings = nichts wird in user:// gespeichert):
##   Godot --path . --resolution 1920x1080 res://game/ui/tools/main_menu_test.tscn -- --no-settings [--shots-only]
## Ergebnis: Zeilen "[menutest] OK ..." / "[menutest] FEHLER ..." und am Ende "[menutest] FERTIG fehler=N".

const OUT := "res://captures/main_menu/"
const UNLOCKED := ["baltic_night", "test_range", "river_crossing", "rail_yard", "berlin", "curfew", "overwatch"]

var _main: Node
var _errors: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var st := get_node_or_null("/root/Settings")
	if st != null:
		st.call("set_value", "game/pause_on_focus", false)
		if not Game.arg("fresh", false):
			st.call("set_value", "game/unlocked", UNLOCKED)
			st.call("set_value", "game/last_level", "overwatch")
	_main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(_main)
	_run()


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("[menutest] shot " + name)


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[menutest] OK " + what)
	else:
		_errors += 1
		print("[menutest] FEHLER " + what)


func _menu() -> Node:
	return _main.get_node_or_null("MainMenu")


func _wait_menu(timeout: float = 20.0) -> Node:
	var t0 := Time.get_ticks_msec()
	while _menu() == null and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame
	return _menu()


func _wait_level(level_name: String, timeout: float = 120.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		var lv: Variant = _main.get("_level")
		if str(_main.get("_level_name")) == level_name and bool(_main.call("can_pause")) \
				and lv is Node and is_instance_valid(lv) and (lv as Node).process_mode == Node.PROCESS_MODE_PAUSABLE:
			return true   # erst nach dem Vorwaermen (vorher steht das Level still)
		await get_tree().process_frame
	return false


func _run() -> void:
	var m := await _wait_menu()
	_check(m != null, "Hauptmenue beim Start ohne --level")
	if m == null:
		_finish()
		return
	await _wait(2.6)
	await _shot("01_main_continue")
	for id in ["new", "missions", "episodes", "settings", "credits", "quit"]:
		(m.get("_buttons")[id] as Button).grab_focus()
		await _wait(0.25)
		await _shot("02_card_" + id)
	m.call("_show_page", "missions")
	await _wait(0.4)
	await _shot("03_missions")
	m.call("_back")
	m.call("_show_page", "episodes")
	await _wait(0.4)
	await _shot("04_episodes")
	m.call("_back")
	m.call("_on_item", "settings")
	await _wait(0.4)
	await _shot("05_settings")
	m.call("_back")
	m.call("_on_item", "new")
	await _wait(0.4)
	await _shot("06_confirm_new")
	m.call("_back")
	m.call("_on_item", "quit")
	await _wait(0.4)
	await _shot("07_confirm_quit")
	m.call("_back")
	await _wait(0.3)
	m.call("_on_item", "credits")
	await _wait(4.0)
	await _shot("08_credits")
	for c in m.get_children():
		if c.has_method("_finish"):
			c.call("_finish")
	await _wait(1.2)
	await _shot("09_after_credits")
	if Game.arg("shots-only", false):
		_finish()
		return

	# Fortsetzen -> overwatch
	m.call("_on_item", "continue")
	_check(await _wait_level("overwatch"), "Fortsetzen startet overwatch (ist: %s)" % _main.get("_level_name"))
	_check(_menu() == null, "Menue nach Start entfernt")
	await _wait(1.0)
	# Pause -> Hauptmenue
	var pm: Node = _main.get_node_or_null("PauseMenu")
	_check(pm != null and (pm.get("_buttons") as Dictionary).has("mainmenu"), "Pausenmenue hat HAUPTMENÜ")
	pm.call("open")
	await _wait(0.5)
	pm.call("_on_item", "mainmenu")
	await _wait(0.4)
	await _shot("10_pause_confirm_mainmenu")
	pm.call("_transition", func() -> void: _main.call("return_to_main_menu"))
	m = await _wait_menu()
	_check(m != null, "Pause -> Hauptmenue")
	_check(not get_tree().paused, "Baum nach Rueckkehr nicht pausiert")
	await _wait(2.0)
	await _shot("11_back_in_menu")
	# Missionsauswahl -> curfew (ueber den echten Knopf)
	m.call("_show_page", "missions")
	await _wait(0.3)
	var target: Button = null
	for b in m.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.get_parent() is VBoxContainer and b.get_parent().get_parent() is ScrollContainer:
			for l in b.find_children("*", "Label", true, false):
				if (l as Label).text == "Ausgangssperre":
					target = b
	_check(target != null, "Missionsknopf »Ausgangssperre« gefunden")
	var locked_shown := false
	for l in m.find_children("*", "Label", true, false):
		if (l as Label).text == "Kräne":
			locked_shown = true
	_check(not locked_shown, "Gesperrte Mission (Kräne) nicht gelistet")
	if target != null:
		target.grab_focus()
		await _wait(0.2)
		target.pressed.emit()
		_check(await _wait_level("curfew"), "Missionsauswahl startet curfew (ist: %s)" % _main.get("_level_name"))
	await _wait(1.0)
	pm.call("open")
	await _wait(0.3)
	pm.call("_transition", func() -> void: _main.call("return_to_main_menu"))
	m = await _wait_menu()
	_check(m != null, "zweites Mal Pause -> Hauptmenue")
	await _wait(1.0)
	_check(str((m.get("_state") as Dictionary).get("continue", "")) == "curfew", "Fortsetzen zeigt jetzt curfew")
	# Neue Kampagne mit Rueckfrage -> Reset + Intro
	m.call("_on_item", "new")
	await _wait(0.3)
	_check(str(m.get("_page")) == "confirm", "Neue Kampagne fragt nach")
	m.call("_launch", "menu_new_campaign", [true])
	await _wait(1.6)
	var st := get_node_or_null("/root/Settings")
	_check(st != null and (st.call("get_value", "game/unlocked", ["x"]) as Array).is_empty() or _main.get("_level_name") == "baltic_night",
		"Neue Kampagne setzt Fortschritt zurueck")
	_check(_main.get_node_or_null("Intro") != null or _main.find_children("*", "", false, false).any(func(n: Node) -> bool: return n.has_signal("finished") and n.name.to_lower().contains("intro")),
		"Intro laeuft nach Neue Kampagne")
	await _wait(2.0)
	await _shot("12_new_campaign_intro")
	_finish()


func _finish() -> void:
	print("[menutest] FERTIG fehler=%d" % _errors)
	get_tree().quit(1 if _errors > 0 else 0)
