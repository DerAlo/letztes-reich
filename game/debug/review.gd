extends Node
## Review-Werkzeug (nur mit --review=<ordner>, Ordner relativ zu captures/): spielt ein Level (meist per --autopilot)
## durch und schreibt Material zum Anschauen nach captures/<ordner>/:
##   <t 0000.0>_<phase/auftrag>.png  alle --review-every Sim-Sekunden (Standard 8) + kurz nach jedem Phasen-/Auftragswechsel
##   radio.tsv    jede Funkzeile (StoryUI): Aufruf, Abspielbeginn, Verzug, Dauer, Sprecher, Text, verworfen, ueberlappt_mit
##   events.tsv   Auftrag (Events.story_objective), Level-Phase (Property phase/_phase), Checkpoint, Zwischensequenz, Tod
##   summary.txt  Ergebnis, Tode, Dauer, Shots, Funkzeilen mit Verzug > 3 s, verworfene Zeilen
## Wird vom DebugServer-Autoload angelegt (/root/DebugServer/Review); StoryUI, Autopilot und EnemyVoice melden sich hier.
##
## Bild: 960x540 der Hauptansicht INKLUSIVE HUD/Untertitel. Dafuer rendert das Wurzelfenster unter --review im
## Content-Scale-Modus "viewport" mit fester Basisgroesse 1920x1080 (das HUD wird also exakt wie im normalen Spiel
## gelayoutet, egal wie klein das --bg-Fenster ist) und 3D-Renderskala hoechstens 0.5 (3D intern ~960x540, kaum teurer
## als ein zweiter SubViewport). Das Bild wird aus der Wurzel-Textur gelesen und auf 960x540 verkleinert. Ein
## SubViewport mit gespiegelter Kamera (wie spreebogen_shots.gd / villa_shots.gd) kann die CanvasLayer des Hauptfensters
## nicht mitzeichnen – deshalb dieser Weg.

const SHOT_SIZE := Vector2i(960, 540)
const BASE_SIZE := Vector2i(1920, 1080)
const LAG_WARN := 3.0
const UMLAUTS := {"ä": "ae", "ö": "oe", "ü": "ue", "Ä": "Ae", "Ö": "Oe", "Ü": "Ue", "ß": "ss"}

var _dir: String = ""
var _every: float = 8.0
var _t: float = 0.0
var _running: bool = false
var _next_shot: float = 1.0
var _event_shot_at: float = -1.0
var _shots: int = 0
var _busy: bool = false
var _level: Node = null
var _phase_str: String = ""
var _objective: String = ""
var _deaths: int = 0
var _done: bool = false
var _ev: FileAccess = null
var _lines: Array[Dictionary] = []   # {e, q, play, end, dur, speaker, text, drop, over}
var _cur: Dictionary = {}            # laufende Funkzeile (Record)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_every = maxf(0.5, float(str(Game.arg("review-every", "8"))))
	var rel := str(Game.arg("review", "review"))
	if rel == "true":
		rel = "review"
	_dir = ProjectSettings.globalize_path("res://captures").path_join(rel)
	DirAccess.make_dir_recursive_absolute(_dir)
	_ev = FileAccess.open(_dir.path_join("events.tsv"), FileAccess.WRITE)
	if _ev != null:
		_ev.store_line("zeit\ttext")
	Events.story_objective.connect(_on_objective)
	Events.checkpoint_reached.connect(func(id: String) -> void: _event("checkpoint: " + id))
	Events.story_cinematic.connect(func(a: bool) -> void: _event("zwischensequenz " + ("an" if a else "aus")))
	Events.player_died.connect(func() -> void:
		_deaths += 1
		_event("spieler tot (#%d)" % _deaths))
	Events.player_respawned.connect(func() -> void: _event("spieler respawn"))
	Events.level_completed.connect(func() -> void: _event("level abgeschlossen"))
	var root := get_tree().root
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	# --review-base=WxH: HUD/UI mit anderer Basis layouten (z. B. 960x540 = so wie im kleinen Fenster), Standard 1920x1080
	var base := BASE_SIZE
	var rb := str(Game.arg("review-base", ""))
	if rb.contains("x"):
		var p := rb.split("x")
		base = Vector2i(maxi(320, int(p[0])), maxi(180, int(p[1])))
	root.content_scale_size = base
	print("[review] -> %s  alle %.1f s, Bild %dx%d (Basis %dx%d inkl. HUD)" % [_dir, _every, SHOT_SIZE.x, SHOT_SIZE.y, base.x, base.y])


func _physics_process(delta: float) -> void:
	if _done:
		return
	if not _running:
		_level = _find_level()
		if _level == null or Game.get_player() == null:
			return
		_running = true
		_apply_render_scale()
		_event("start: " + str(_level.name))
	_t += delta
	if _level != null and not is_instance_valid(_level):
		_level = null
	if _level != null:
		var ph: Variant = _level.get("phase")
		if ph == null:
			ph = _level.get("_phase")
		var s := str(ph) if ph != null else ""
		if s != _phase_str:
			_phase_str = s
			_event("phase: " + s)
	if _busy:
		return
	if _t >= _next_shot:
		_next_shot = _t + _every
		_snap()
	elif _event_shot_at >= 0.0 and _t >= _event_shot_at:
		_event_shot_at = -1.0
		_snap()


func _apply_render_scale() -> void:
	# 3D intern nicht groesser als das Zielbild rendern (Fenster ist unter --bg ohnehin klein)
	var root := get_tree().root
	if root.scaling_3d_scale > 0.5:
		root.scaling_3d_scale = 0.5
		if root.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2:
			root.texture_mipmap_bias = 1.0   # Auto-Bias von log2(0.5) neutralisieren (wie Graphics._apply_viewport)


func _find_level() -> Node:
	var cs := get_tree().current_scene
	if cs == null:
		return null
	var lv: Variant = cs.get("_level")
	if lv is Node and is_instance_valid(lv):
		return lv
	if cs.has_method("get_level_info"):
		return cs
	for c in cs.get_children():
		if c.has_method("get_level_info"):
			return c
	return null


# --------------------------------------------------------------------------- Ereignisse

func _event(text: String) -> void:
	if _ev != null:
		_ev.store_line("%.1f\t%s" % [_t, text.replace("\t", " ").replace("\n", " ")])
		_ev.flush()
	if _running and not text.begins_with("zwischensequenz"):
		_event_shot_at = _t + 1.5   # Bild kurz nach dem Wechsel (Auftrag eingeblendet)


func _on_objective(text: String) -> void:
	_objective = text
	_event("auftrag: " + (text if text != "" else "(leer)"))


# --------------------------------------------------------------------------- Bilder

func _label() -> String:
	var parts: Array[String] = []
	if _phase_str != "":
		parts.append("p" + _phase_str)
	if _objective != "":
		parts.append(_objective)
	var s := "_".join(parts)
	for k: String in UMLAUTS:
		s = s.replace(k, str(UMLAUTS[k]))
	var out := ""
	for ch in s:
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or ch == "_"
		out += ch if ok else "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.strip_edges().trim_prefix("-").trim_suffix("-").left(40).trim_suffix("-")
	return out if out != "" else "x"


func _snap() -> void:
	_busy = true
	var fname := "%06.1f_%s.png" % [_t, _label()]
	await RenderingServer.frame_post_draw
	_busy = false
	if _done or not is_inside_tree():
		return
	var img := get_tree().root.get_texture().get_image()
	if img == null or img.is_empty():
		return
	if img.get_size() != SHOT_SIZE:
		img.resize(SHOT_SIZE.x, SHOT_SIZE.y, Image.INTERPOLATE_BILINEAR)
	if img.save_png(_dir.path_join(fname)) == OK:
		_shots += 1


# --------------------------------------------------------------------------- Funk (Aufrufe aus StoryUI)

func _rec(e: Array) -> Dictionary:
	for i in range(_lines.size() - 1, -1, -1):
		if is_same(_lines[i]["e"], e):
			return _lines[i]
	return {}


func radio_queued(e: Array) -> void:
	_lines.append({"e": e, "q": _t, "play": -1.0, "end": -1.0, "dur": float(e[2]), "speaker": str(e[0]),
		"text": str(e[1]), "drop": "", "over": []})


func radio_dropped(e: Array, why: String) -> void:
	var r := _rec(e)
	if not r.is_empty() and r["drop"] == "":
		r["drop"] = why
		r["end"] = _t   # Zeitpunkt des Verwerfens


func radio_play(e: Array, dur: float) -> void:
	var r := _rec(e)
	if r.is_empty():
		radio_queued(e)
		r = _lines[_lines.size() - 1]
	if not _cur.is_empty() and float(_cur["end"]) > _t + 0.05:
		# laeuft noch (z. B. Tween ohne Abbruch) -> echte Ueberlappung
		_cur["over"].append("Funk: " + str(r["text"]).left(40))
		r["over"].append("Funk: " + str(_cur["text"]).left(40))
	r["play"] = _t
	r["dur"] = dur
	r["end"] = _t + dur
	_cur = r


## StoryUI setzt eine unterbrochene Erzaehlzeile fort (Abspielbeginn bleibt der erste Start).
func radio_resume(e: Array, dur: float) -> void:
	var r := _rec(e)
	if r.is_empty():
		return
	r["over"].append("fortgesetzt")
	r["end"] = _t + dur
	_cur = r


func radio_cut(e: Array, why: String) -> void:
	var r := _rec(e)
	if r.is_empty():
		return
	r["end"] = minf(float(r["end"]), _t) if float(r["end"]) >= 0.0 else _t
	r["over"].append("abgebrochen (" + why + ")")
	if is_same(r, _cur):
		_cur = {}


## Gegnerruf (EnemyVoice.bark) waehrend einer Funkzeile
func bark(situation: String) -> void:
	if not _cur.is_empty() and _t <= float(_cur["end"]):
		var tag := "Ruf " + situation
		var ov: Array = _cur["over"]
		if not ov.has(tag):
			ov.append(tag)


# --------------------------------------------------------------------------- Abschluss

## Vom Autopilot vor dem Beenden aufgerufen (ohne Autopilot: _exit_tree mit result "abgebrochen").
func finish(result: String, deaths: int = -1, sim: float = -1.0) -> void:
	if _done:
		return
	_done = true
	if deaths >= 0:
		_deaths = deaths
	var dur := sim if sim >= 0.0 else _t
	_event("ende: " + result)
	if _ev != null:
		_ev.close()
		_ev = null
	var late: Array[String] = []
	var dropped: Array[String] = []
	var f := FileAccess.open(_dir.path_join("radio.tsv"), FileAccess.WRITE)
	if f != null:
		f.store_line("sim_zeit_aufruf\tsim_zeit_abspielbeginn\tverzug_s\tdauer\tsprecher\ttext\tverworfen\tueberlappt_mit")
	for r in _lines:
		var play := float(r["play"])
		var gone := float(r["end"]) if float(r["end"]) >= 0.0 else dur
		var lag := (play - float(r["q"])) if play >= 0.0 else (gone - float(r["q"]))
		var drop := str(r["drop"])
		if drop == "" and play < 0.0:
			drop = "nie gespielt (Ende)"
		var txt := str(r["text"]).replace("\t", " ").replace("\n", " ")
		if f != null:
			f.store_line("%.1f\t%s\t%.1f\t%.1f\t%s\t%s\t%s\t%s" % [float(r["q"]), ("%.1f" % play) if play >= 0.0 else "-",
				lag, float(r["dur"]), str(r["speaker"]), txt, ("ja: " + drop) if drop != "" else "nein",
				"; ".join(PackedStringArray(r["over"]))])
		if play >= 0.0 and lag > LAG_WARN:
			late.append("  t=%6.1f  +%4.1f s  %s: %s" % [float(r["q"]), lag, str(r["speaker"]), txt.left(90)])
		if drop != "":
			dropped.append("  t=%6.1f  nach %4.1f s  %-20s %s: %s" % [float(r["q"]), lag, drop.left(20), str(r["speaker"]), txt.left(90)])
	if f != null:
		f.close()
	var s := FileAccess.open(_dir.path_join("summary.txt"), FileAccess.WRITE)
	if s != null:
		s.store_line("level:    %s" % str(Game.arg("level", "?")))
		s.store_line("result:   %s" % result)
		s.store_line("deaths:   %d" % _deaths)
		s.store_line("dauer:    %.1f s (Sim)" % dur)
		s.store_line("shots:    %d (alle %.1f s + nach Wechseln, 960x540)" % [_shots, _every])
		s.store_line("funk:     %d Zeilen" % _lines.size())
		s.store_line("")
		s.store_line("Funkzeilen mit Verzug > %.0f s: %d" % [LAG_WARN, late.size()])
		for l in late:
			s.store_line(l)
		s.store_line("")
		s.store_line("Verworfene Zeilen: %d" % dropped.size())
		for l in dropped:
			s.store_line(l)
		s.close()
	print("[review] fertig: %d Bilder, %d Funkzeilen (%d verspaetet, %d verworfen) -> %s" % [_shots, _lines.size(), late.size(), dropped.size(), _dir])


func _exit_tree() -> void:
	finish("abgebrochen")
