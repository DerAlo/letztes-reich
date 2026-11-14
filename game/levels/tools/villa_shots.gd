extends Node
## Debug-Aufnahmen fuer "villa" (und jedes andere Level): rendert feste Kameras in einen SubViewport
## fester Groesse (Fenster bleibt klein, --bg) und speichert PNGs.
##   --shots=captures/villa_x               Zielordner (relativ zum Projekt)
##   --shot-cams="name@t:x,y,z>ZIEL;..."    t = Sekunden nach Start; ZIEL = "x,y,z" oder Node-Name
##                                           (find_child, z. B. Weber, Wasserflugzeug). Beginnt die Position
##                                           mit "~", ist sie relativ zum Ziel-Node (Weltachsen).
##   --shot-fov=60  --shot-w=1280 --shot-h=720  --shot-quit=1 (nach der letzten Aufnahme beenden)
##   --shot-main=960x540                     Aufloesung fuer "main"-Aufnahmen (Spielerkamera inkl. HUD)
##   Kamera "main": NAME@t:main>-
## Aufruf: in villa.gd (_ready), wenn --shots gesetzt ist.

var _vp: SubViewport
var _cam: Camera3D
var _jobs: Array[Dictionary] = []
var _t: float = 0.0
var _dir: String = ""
var _busy: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = str(Game.arg("shots", "captures/shots"))
	if not _dir.is_absolute_path():
		_dir = ProjectSettings.globalize_path("res://").path_join(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	# --shot-main=960x540: Hauptfenster (inkl. HUD) in fester Aufloesung rendern, fuer "main"-Aufnahmen
	var ms := str(Game.arg("shot-main", "")).split("x")
	if ms.size() == 2 and ms[0].is_valid_int() and ms[1].is_valid_int():
		var root := get_tree().root
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		root.content_scale_size = Vector2i(int(ms[0]), int(ms[1]))
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(str(Game.arg("shot-w", "1280"))), int(str(Game.arg("shot-h", "720"))))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.world_3d = get_viewport().world_3d
	_vp.positional_shadow_atlas_size = 4096
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = float(str(Game.arg("shot-fov", "60")))
	_cam.near = 0.05
	_cam.far = 1500.0
	_vp.add_child(_cam)
	_cam.current = true
	for spec in str(Game.arg("shot-cams", "")).split(";", false):
		var j := _parse(spec.strip_edges())
		if not j.is_empty():
			_jobs.append(j)
	_jobs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["t"]) < float(b["t"]))
	print("[villa_shots] %d Aufnahmen -> %s" % [_jobs.size(), _dir])

func _parse(spec: String) -> Dictionary:
	var head_body := spec.split(":", true, 1)
	if head_body.size() < 2:
		return {}
	var nt := head_body[0].split("@")
	var pl := head_body[1].split(">")
	if pl.size() < 2:
		return {}
	return {"name": nt[0], "t": float(nt[1]) if nt.size() > 1 else 3.0, "pos": pl[0], "look": pl[1]}

func _vec(s: String) -> Variant:
	var p := s.split(",")
	if p.size() != 3 or not p[0].is_valid_float():
		return null
	return Vector3(float(p[0]), float(p[1]), float(p[2]))

func _node(nm: String) -> Node3D:
	var lv := get_parent()
	return lv.find_child(nm, true, false) as Node3D if lv != null else null

func _process(delta: float) -> void:
	_t += delta
	if _busy or _jobs.is_empty():
		return
	if _t >= float(_jobs[0]["t"]):
		_take(_jobs.pop_front())

func _take(j: Dictionary) -> void:
	_busy = true
	if str(j["pos"]) == "main":
		# Hauptfenster inkl. HUD (Spielerkamera)
		await RenderingServer.frame_post_draw
		var mi := get_viewport().get_texture().get_image()
		var mp := _dir.path_join("%s.png" % str(j["name"]))
		mi.save_png(mp)
		print("[villa_shots] %s (t=%.1f)" % [mp, _t])
		_busy = false
		_maybe_quit()
		return
	var look: Variant = _vec(str(j["look"]))
	var tgt: Node3D = null
	if look == null:
		tgt = _node(str(j["look"]))
		look = (tgt.global_position + Vector3(0, 1.2, 0)) if tgt != null else Vector3.ZERO
	var ps := str(j["pos"])
	var rel := ps.begins_with("~")
	var pos: Variant = _vec(ps.trim_prefix("~"))
	if pos == null:
		pos = Vector3(0, 10, 10)
	if rel:
		pos = (tgt.global_position if tgt != null else (look as Vector3)) + (pos as Vector3)
	_cam.global_position = pos
	if (look as Vector3).distance_to(pos) > 0.01:
		_cam.look_at(look, Vector3.UP)
	for i in 4:
		await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := _dir.path_join("%s.png" % str(j["name"]))
	img.save_png(path)
	print("[villa_shots] %s (t=%.1f)" % [path, _t])
	_busy = false
	_maybe_quit()

func _maybe_quit() -> void:
	if _jobs.is_empty() and str(Game.arg("shot-quit", "")) not in ["", "0", "false"]:
		get_tree().quit()
