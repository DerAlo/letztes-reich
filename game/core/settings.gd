extends Node
## Persistente Einstellungen (user://settings.cfg). Gemeinsamer Speicher fuer Steuerung, Audio, Spiel und Grafik.
##
## API (siehe CONTRACTS.md "Runde 6"):
##   Settings.get_value("section/key", default)   – liest; default, wenn nie gesetzt
##   Settings.set_value("section/key", value)     – setzt, emittiert changed, speichert verzoegert
##   Settings.reset_section("graphics")           – loescht alle Schluessel einer Sektion
##   signal changed(key: String, value)
## Schluessel immer "sektion/name" (z. B. "input/invert_y", "graphics/fsr_mode").

signal changed(key: String, value)

const PATH := "user://settings.cfg"

var _cfg := ConfigFile.new()
var _save_timer: Timer


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Bots/Tools (Simulation, Captures) laufen mit Standardwerten und schreiben nichts.
	if not _is_tool_run():
		_cfg.load(PATH)


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
	_save_timer.timeout.connect(save)
	add_child(_save_timer)


func _is_tool_run() -> bool:
	for a in OS.get_cmdline_user_args():
		for flag in ["--autopilot", "--debug-server", "--capture", "--no-settings", "--bg"]:
			if a.begins_with(flag):
				return true
	return false


func _split(key: String) -> PackedStringArray:
	var p := key.split("/", true, 1)
	if p.size() < 2:
		return PackedStringArray(["general", key])
	return p


func get_value(key: String, default = null):
	var p := _split(key)
	return _cfg.get_value(p[0], p[1], default)


func has(key: String) -> bool:
	var p := _split(key)
	return _cfg.has_section_key(p[0], p[1])


func set_value(key: String, value) -> void:
	var p := _split(key)
	if _cfg.has_section_key(p[0], p[1]) and _cfg.get_value(p[0], p[1]) == value:
		return
	_cfg.set_value(p[0], p[1], value)
	changed.emit(key, value)
	if _save_timer and not _is_tool_run():
		_save_timer.start()


func reset_section(section: String) -> void:
	if not _cfg.has_section(section):
		return
	var keys := _cfg.get_section_keys(section)
	_cfg.erase_section(section)
	for k in keys:
		changed.emit(section + "/" + k, null)
	if not _is_tool_run():
		save()


func save() -> void:
	if _is_tool_run():
		return
	_cfg.save(PATH)
