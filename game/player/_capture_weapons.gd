extends Node
## Screenshots der Waffen (Runde weapons3: + Nahaufnahme, Kiste, Drop am Boden): G36C Hüfte/ADS, AK-74M, Panzerfaust, Pickup-Hinweis, Rakete.
## godot --path . res://game/player/_capture_weapons.tscn -- --out=captures/weapons2
## Nicht headless starten (Screenshots brauchen den Renderer). Gibt "CAPTURE_DONE n=N" aus.

var player: Player
var _out: String = "captures/weapons2"
var _n: int = 0

func _ready() -> void:
	_out = str(Game.arg("out", _out))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	get_window().size = Vector2i(1600, 900)
	var lv: Node = (load("res://game/levels/test_range.tscn") as PackedScene).instantiate()
	lv.set("spawn_enemies", false)
	if "ambient_artillery" in lv:
		lv.set("ambient_artillery", false)
	add_child(lv)
	await _wait(0.6)
	player = Game.get_player() as Player
	player.external_input = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var start: Vector3 = player.global_position
	# G36C Hüfte / ADS
	player.set_view(0.0, -2.0)
	await _wait(1.0)
	await _shot("g36c_hip")
	player.ext.aim = true
	await _wait(0.8)
	await _shot("g36c_ads")
	player.ext.aim = false
	await _wait(0.5)
	# Feuern (Mündungsfeuer + Hülse)
	player.ext.fire = true
	await _wait(0.14)
	await _shot("g36c_fire")
	player.ext.fire = false
	await _wait(0.6)
	# Nahaufnahme: Waffen-Kamera seitlich links neben die Waffe (Spieler kurz eingefroren)
	await _closeup("g36c_closeup", Vector3(-0.42, 0.07, -0.02), Vector3(0.12, -0.17, -0.42), 38.0)
	await _closeup("g36c_closeup_r", Vector3(0.62, 0.02, -0.25), Vector3(0.12, -0.19, -0.44), 40.0)
	# Drop am Boden: liegende G36C (leer, wird nicht automatisch eingesammelt) vor dem Spieler
	Pickup.spawn_weapon(lv, start + Vector3(0.0, 0.0, -0.75), "g36c", 0, 0, 25.0, 35.0)
	player.set_view(0.0, -72.0)
	await _wait(0.5)
	await _shot("g36c_drop")
	# Munitionskiste (test_range: (-2.4, 0, 2.5), Front zeigt nach +X)
	player.global_position = Vector3(-0.5, start.y, 2.5)
	player.velocity = Vector3.ZERO
	player.set_view(90.0, -30.0)
	await _wait(0.6)
	await _shot("ammo_crate")
	player.global_position = start
	player.set_view(0.0, -2.0)
	await _wait(0.4)
	# Pickup-Hinweis vor der liegenden AK-74M
	player.global_position = Vector3(1.6, start.y, 0.2)
	player.velocity = Vector3.ZERO
	player.set_view(0.0, -38.0)
	await _wait(0.6)
	await _shot("pickup_hint")
	player.ext.interact = true
	await _wait(1.0)
	player.set_view(0.0, -2.0)
	await _wait(0.6)
	await _shot("ak74m_hip")
	player.ext.aim = true
	await _wait(0.8)
	await _shot("ak74m_ads")
	player.ext.aim = false
	# Panzerfaust-Kiste
	player.global_position = Vector3(5.6, start.y, 2.0)
	player.velocity = Vector3.ZERO
	player.set_view(90.0, -26.0)
	await _wait(0.6)
	await _shot("pzf_crate_hint")
	player.give_weapon("pzf3", 1, 2)
	player.global_position = start
	player.set_view(0.0, -1.0)
	await _wait(1.2)
	await _shot("pzf_hip")
	player.ext.aim = true
	await _wait(0.9)
	await _shot("pzf_ads")
	player.ext.fire = true
	await _wait(0.25)
	await _shot("pzf_rocket")
	player.ext.fire = false
	player.ext.aim = false
	await _wait(0.6)
	await _shot("pzf_reload")
	print("CAPTURE_DONE n=%d" % _n)
	get_tree().quit()

## Waffen-Kamera relativ zur Hauptkamera versetzen (cam_off) und auf look (Kameraraum) richten.
func _closeup(name: String, cam_off: Vector3, look: Vector3, fov: float) -> void:
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var cam: Camera3D = player.camera
	var wc: Camera3D = player.weapon_cam
	var cb: Transform3D = cam.global_transform
	var old_fov: float = wc.fov
	wc.look_at_from_position(cb * cam_off, cb * look, cb.basis.y)
	wc.fov = fov
	await _wait(0.15)
	await _shot(name)
	wc.fov = old_fov
	player.process_mode = Node.PROCESS_MODE_INHERIT
	await _wait(0.1)

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(ProjectSettings.globalize_path("res://").path_join(_out).path_join(name + ".png"))
	_n += 1
	print("shot ", name)
