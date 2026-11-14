extends SubViewport
## Debug-Aufnahmen fuer spreebogen (nur mit --shots=<ordner>): rendert die aktuelle Spielkamera in feste
## 960x540 (unabhaengig vom kleinen --bg-Fenster) samt Turm-HUD und speichert alle --shot-every Sekunden
## (Standard 5) sowie auf Zuruf (snap) ein PNG nach captures/<ordner>/.

const IfvHud := preload("res://game/vehicles/ifv/ifv_hud.gd")

var out_dir: String = ""
var every: float = 5.0
var level: Node = null
var _cam: Camera3D
var _t: float = 0.0
var _next: float = 2.0
var _hud: CanvasLayer = null
var _hud_ifv: Node = null
var _caption: Label
var fixed_cam: Array[float] = []
var ifv_cam: Array[float] = []

func _ready() -> void:
	for v in str(Game.arg("shot-cam", "")).split(",", false):
		fixed_cam.append(float(v))
	for v in str(Game.arg("shot-ifv", "")).split(",", false):
		ifv_cam.append(float(v))
	size = Vector2i(960, 540)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_2X
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	_caption = Label.new()
	_caption.position = Vector2(8, 4)
	_caption.add_theme_font_size_override("font_size", 14)
	_caption.add_theme_color_override("font_color", Color(1, 1, 0.6))
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 4)
	cl.add_child(_caption)
	DirAccess.make_dir_recursive_absolute(out_dir)
	print("[spree-shots] -> %s alle %.1f s" % [out_dir, every])

func _process(delta: float) -> void:
	_t += delta
	var src := get_tree().root.get_camera_3d()
	var ifv0: Node3D = level.get("ifv") if level != null else null
	if fixed_cam.size() == 6:
		# --shot-cam=x,y,z,tx,ty,tz : feste Kamera (Weltkoordinaten)
		_cam.fov = 50.0
		_cam.look_at_from_position(Vector3(fixed_cam[0], fixed_cam[1], fixed_cam[2]), Vector3(fixed_cam[3], fixed_cam[4], fixed_cam[5]))
	elif ifv_cam.size() == 3 and ifv0 != null and is_instance_valid(ifv0):
		# --shot-ifv=dx,dy,dz : Aussenansicht des Rabe (Versatz in Fahrzeugkoordinaten)
		_cam.fov = 45.0
		var b := ifv0.global_transform
		_cam.look_at_from_position(b * Vector3(ifv_cam[0], ifv_cam[1], ifv_cam[2]), b * Vector3(0, 1.4, 0))
	elif src != null and is_instance_valid(src):
		_cam.global_transform = src.global_transform
		_cam.fov = src.fov
		_cam.near = src.near
		_cam.far = src.far
		_cam.h_offset = src.h_offset
		_cam.v_offset = src.v_offset
	# Turm-HUD spiegeln, solange der Rabe existiert
	var ifv: Node = level.get("ifv") if level != null else null
	if ifv != _hud_ifv:
		if _hud != null and is_instance_valid(_hud):
			_hud.queue_free()
		_hud = null
		_hud_ifv = ifv
		if ifv != null and is_instance_valid(ifv) and fixed_cam.is_empty() and ifv_cam.is_empty():
			_hud = IfvHud.new()
			_hud.set("ifv", ifv)
			add_child(_hud)
	if _t >= _next:
		_next = _t + every
		snap("t")

func snap(tag: String) -> void:
	if out_dir == "":
		return
	_caption.text = "t=%.1f  phase %s  %s" % [_t, str(level.get("phase")) if level != null else "?", tag]
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := get_texture().get_image()
	if img == null:
		return
	var p := out_dir.path_join("%05.1f_%s.png" % [_t, tag.validate_filename()])
	img.save_png(p)
