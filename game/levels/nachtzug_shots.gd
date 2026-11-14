extends SubViewport
## Debug-Aufnahmen fuer nachtzug (nur mit --shots=<ordner>): feste 960x540 (unabhaengig vom --bg-Fenster),
## faehrt eine Liste fester Kamerapositionen ab (Reisende, Strecke/Baeume) und speichert je Position ein PNG
## nach captures/<ordner>/. Danach wird die Spielkamera alle --shot-every Sekunden gespiegelt.
## --shot-only=<tag,tag> beschraenkt die Liste.

## [tag, Kamera, Ziel, fov]
const PRESETS := [
	["civ1", Vector3(-0.35, 2.3, -6.35), Vector3(-1.2, 1.9, -5.25), 60.0],
	["civ2", Vector3(-0.25, 2.3, -14.2), Vector3(-0.6, 1.9, -15.3), 60.0],
	["civ3", Vector3(0.45, 2.3, -30.3), Vector3(1.25, 1.9, -29.2), 60.0],
	["civ4", Vector3(-0.45, 2.3, -39.1), Vector3(-1.25, 1.9, -40.2), 60.0],
	["sleeper", Vector3(-0.45, 2.3, -145.75), Vector3(-1.0, 1.75, -144.35), 75.0],
	["sleeper2", Vector3(-0.45, 2.3, -152.35), Vector3(-1.0, 1.75, -150.95), 75.0],
	["cower", Vector3(1.35, 2.45, -143.1), Vector3(0.4, 1.55, -145.0), 65.0],
	["trees_r", Vector3(1.0, 6.0, -60.0), Vector3(40.0, 4.0, -95.0), 55.0],
	["trees_l", Vector3(-1.0, 6.0, -60.0), Vector3(-40.0, 4.0, -95.0), 55.0],
	["window", Vector3(0.6, 2.4, -20.0), Vector3(25.0, 3.0, -40.0), 70.0],
	["roof_back", Vector3(0.0, 7.5, -10.0), Vector3(0.0, 2.0, 60.0), 65.0],
	["abteil", Vector3(0.35, 2.35, -8.875), Vector3(-1.5, 1.6, -9.2), 78.0],
	["abteil_gang", Vector3(1.3, 2.6, -0.8), Vector3(0.6, 2.1, -20.0), 70.0],
	["speise", Vector3(0.0, 2.65, -28.6), Vector3(0.0, 1.8, -44.0), 72.0],
	["speise_tisch", Vector3(0.15, 2.25, -35.9), Vector3(1.3, 1.9, -37.3), 60.0],
	["speise_links", Vector3(0.05, 2.3, -28.4), Vector3(-1.3, 1.85, -30.2), 60.0],
	["gepaeck", Vector3(0.6, 2.9, -55.6), Vector3(-0.4, 1.4, -72.0), 72.0],
	["schlaf_gang", Vector3(1.3, 2.6, -138.3), Vector3(0.7, 2.0, -158.0), 70.0],
	["mountains_r", Vector3(0.0, 7.0, -60.0), Vector3(400.0, 40.0, -260.0), 60.0],
	["mountains_l", Vector3(0.0, 7.0, -60.0), Vector3(-400.0, 40.0, -260.0), 60.0],
]

var out_dir: String = ""
var every: float = 2.5
var level: Node = null
var _cam: Camera3D
var _t: float = 0.0
var _next: float = 4.0
var _idx: int = 0
var _list: Array = []
var _caption: Label

func _ready() -> void:
	var only := str(Game.arg("shot-only", "")).split(",", false)
	for p: Array in PRESETS:
		if only.is_empty() or String(p[0]) in only:
			_list.append(p)
	size = Vector2i(960, 540)
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_2X
	_cam = Camera3D.new()
	_cam.near = 0.05
	_cam.far = 4000.0
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
	print("[zug-shots] -> %s (%d Positionen)" % [out_dir, _list.size()])

func _process(delta: float) -> void:
	_t += delta
	if _idx < _list.size():
		var p: Array = _list[_idx]
		_cam.fov = float(p[3])
		_cam.look_at_from_position(p[1], p[2])
		if _t >= _next:
			_next = _t + every
			_idx += 1
			snap(String(p[0]))
		return
	var src := get_tree().root.get_camera_3d()
	if src != null and is_instance_valid(src) and src != _cam:
		_cam.global_transform = src.global_transform
		_cam.fov = src.fov
	if _t >= _next:
		_next = _t + every * 4.0
		snap("play")

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
	img.save_png(out_dir.path_join("%s_%05.1f.png" % [tag.validate_filename(), _t]))
