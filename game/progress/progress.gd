extends RefCounted
## Fortschritt pro Level (Welle 4, systeme-a): Sterne, Bestzeit, Schwierigkeit. Eigene Datei user://progress.cfg.
## Nutzung per preload: const Progress = preload("res://game/progress/progress.gd")
##
## Sterne (Bitmaske, ueber alle Laeufe vereinigt – jeder Stern bleibt einzeln erhalten):
##   Bit 0 = Mission abgeschlossen, Bit 1 = Zeit unter Zielzeit, Bit 2 = Herausforderung.
## Ziele kommen aus main.gd STAR_GOALS: {"time": Sekunden, "challenge": Typ, "value": Zahl, "prop": ..., "label": ...}
## Herausforderungs-Typen (alle aus Run-Tracker-Statistik messbar, siehe run_tracker.gd):
##   no_deaths · headshots (Anteil Kopfschuss-Abschuesse >= value) · accuracy (Treffer/Schuesse >= value)
##   undetected (Schleich-Direktor des Levels meldet keinen Alarm) · no_hostage_loss (keine Geisel getroffen/hingerichtet)
##   prop_zero (Level-Variable "prop" war nie > 0, z. B. hafen _weber_hits) · damage (erlittener Schaden <= value)
##
## Speichern: wie Settings – bei Bot-/Tool-Laeufen (--autopilot, --debug-server, --capture, --no-settings) nur im Speicher.
## Mit --progress-file=<pfad> wird stattdessen dorthin geladen/geschrieben (Test des Speicherpfads im Tool-Lauf).

const PATH := "user://progress.cfg"
const STAR_DONE := 1
const STAR_TIME := 2
const STAR_CHALLENGE := 4
const MIN_KILLS_HEADSHOT := 4
const MIN_SHOTS_ACCURACY := 10

static var _cfg: ConfigFile = null
static var _path: String = ""


static func _game_arg(key: String, default = null):
	var tree := Engine.get_main_loop() as SceneTree
	var g: Node = tree.root.get_node_or_null("/root/Game") if tree != null else null
	return g.call("arg", key, default) if g != null else default


static func is_tool_run() -> bool:
	for a in OS.get_cmdline_user_args():
		for flag in ["--autopilot", "--debug-server", "--capture", "--no-settings"]:
			if a.begins_with(flag):
				return true
	return false


## Zieldatei ("" = nur im Speicher).
static func save_path() -> String:
	var custom = _game_arg("progress-file", null)
	if custom != null and not (custom is bool) and str(custom) != "":
		var p := str(custom)
		if p.begins_with("user://") or p.begins_with("res://") or p.is_absolute_path():
			return p
		return ProjectSettings.globalize_path("res://").path_join(p)
	return "" if is_tool_run() else PATH


static func _ensure() -> ConfigFile:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_path = save_path()
		if _path != "" and FileAccess.file_exists(_path):
			_cfg.load(_path)
	return _cfg


static func save() -> bool:
	_ensure()
	if _path == "":
		return false
	var err := _cfg.save(_path)
	if err != OK:
		push_warning("[progress] Speichern fehlgeschlagen (%d): %s" % [err, _path])
		return false
	return true


static func mask(level: String) -> int:
	return int(_ensure().get_value(level, "stars", 0))


static func stars(level: String) -> int:
	return popcount(mask(level))


static func best_time(level: String) -> float:
	return float(_ensure().get_value(level, "best_time", -1.0))


static func get_entry(level: String, key: String, default = null):
	return _ensure().get_value(level, key, default)


static func popcount(m: int) -> int:
	return (m & 1) + ((m >> 1) & 1) + ((m >> 2) & 1)


static func total_stars(levels: Array) -> int:
	var n := 0
	for l in levels:
		n += stars(str(l))
	return n


# ------------------------------------------------------------------ Auswertung

static func clock(t: float) -> String:
	if t < 0.0:
		return "--:--"
	var sec := int(ceil(t - 0.001))
	if sec >= 3600:
		return "%d:%02d:%02d" % [sec / 3600, (sec / 60) % 60, sec % 60]
	return "%02d:%02d" % [sec / 60, sec % 60]


## Kurzer Anzeigetext der Herausforderung.
static func challenge_text(goal: Dictionary) -> String:
	if goal.has("label"):
		return str(goal["label"])
	var v := float(goal.get("value", 0.0))
	match str(goal.get("challenge", "no_deaths")):
		"no_deaths":
			return "Ohne Ausfall"
		"headshots":
			return "Kopfschussquote ab %d %%" % roundi(v * 100.0)
		"accuracy":
			return "Treffergenauigkeit ab %d %%" % roundi(v * 100.0)
		"undetected":
			return "Unentdeckt bleiben (kein Alarm)"
		"no_hostage_loss":
			return "Keine Geisel verletzt"
		"damage":
			return "Höchstens %d Schaden erlitten" % roundi(v)
		"prop_zero":
			return "Herausforderung"
	return "Herausforderung"


static func time_text(goal: Dictionary) -> String:
	return "Unter %s" % clock(float(goal.get("time", 0.0)))


static func challenge_met(goal: Dictionary, s: Dictionary) -> bool:
	var v := float(goal.get("value", 0.0))
	match str(goal.get("challenge", "no_deaths")):
		"no_deaths":
			return int(s.get("deaths", 0)) == 0
		"headshots":
			var k := int(s.get("kills", 0))
			return k >= MIN_KILLS_HEADSHOT and float(s.get("headshot_kills", 0)) / float(k) >= v - 0.0001
		"accuracy":
			var sh := int(s.get("shots", 0))
			return sh >= MIN_SHOTS_ACCURACY and float(s.get("accuracy", 0.0)) >= v - 0.0001
		"undetected":
			return int(s.get("alarms", -1)) == 0
		"no_hostage_loss":
			return int(s.get("hostage_incidents", 0)) == 0
		"damage":
			return float(s.get("damage_taken", 0.0)) <= v
		"prop_zero":
			return int(s.get("prop_max", -1)) == 0
	return false


## Sterne eines Laufs: Array[bool] mit 3 Eintraegen.
static func evaluate(goal: Dictionary, s: Dictionary) -> Array[bool]:
	var done := str(s.get("result", "completed")) == "completed"
	var t := float(s.get("time", 1e9))
	var limit := float(goal.get("time", 0.0))
	return [done, done and limit > 0.0 and t <= limit, done and challenge_met(goal, s)]


## Lauf eintragen. Gibt die Auswertung fuer den Abschluss-Bildschirm zurueck.
static func record(level: String, goal: Dictionary, s: Dictionary) -> Dictionary:
	var cfg := _ensure()
	var ev := evaluate(goal, s)
	var run_mask := (STAR_DONE if ev[0] else 0) | (STAR_TIME if ev[1] else 0) | (STAR_CHALLENGE if ev[2] else 0)
	var prev_mask := mask(level)
	var prev_best := best_time(level)
	var t := float(s.get("time", -1.0))
	var diff := str(s.get("difficulty", "soldier"))
	var new_best := ev[0] and t >= 0.0 and (prev_best < 0.0 or t < prev_best)
	cfg.set_value(level, "stars", prev_mask | run_mask)
	if new_best:
		cfg.set_value(level, "best_time", snappedf(t, 0.1))
		cfg.set_value(level, "best_time_difficulty", diff)
	if ev[0]:
		cfg.set_value(level, "completions", int(cfg.get_value(level, "completions", 0)) + 1)
		var rank := {"recruit": 0, "soldier": 1, "veteran": 2}
		var top := str(cfg.get_value(level, "top_difficulty", ""))
		if top == "" or int(rank.get(diff, 1)) > int(rank.get(top, 1)):
			cfg.set_value(level, "top_difficulty", diff)
	cfg.set_value(level, "last_time", snappedf(t, 0.1))
	cfg.set_value(level, "last_stars", run_mask)
	cfg.set_value(level, "last_difficulty", diff)
	var written := save()
	return {
		"level": level, "stars": ev, "mask": run_mask, "prev_mask": prev_mask, "best_mask": prev_mask | run_mask,
		"new_best": new_best, "prev_best": prev_best, "time_goal": float(goal.get("time", 0.0)),
		"time_text": time_text(goal), "challenge_text": challenge_text(goal), "stats": s,
		"saved": written, "path": _path,
	}
