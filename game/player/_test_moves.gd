extends Node
## Test/Screenshots für Slide, Hinlegen, Mantle, Nachladen, Waffenwechsel.
## godot --path . res://game/player/_test_moves.tscn -- --level=test_range --out=captures/moves
## Gibt "MOVES_DONE fails=N" aus.

var _level: Node
var player: Player
var _fails: int = 0
var _out: String = "user://moves"

func _ready() -> void:
	var lv: String = str(Game.arg("level", "test_range"))
	_out = str(Game.arg("out", "user://moves"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out) if _out.begins_with("res://") or _out.begins_with("user://") else _out)
	_level = (load("res://game/levels/%s.tscn" % lv) as PackedScene).instantiate()
	if "spawn_enemies" in _level:
		_level.set("spawn_enemies", false)
	if "ambient_artillery" in _level:
		_level.set("ambient_artillery", false)
	add_child(_level)
	await _wait(0.5)
	player = Game.get_player() as Player
	if player == null:
		print("MOVES_DONE fails=1 (kein Player)")
		get_tree().quit()
		return
	player.external_input = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if lv == "baltic_night":
		await _mantle_test()
	else:
		await _range_test()
	print("MOVES_DONE fails=%d" % _fails)
	get_tree().quit()

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var p: String = _out.path_join(name + ".png")
	img.save_png(p)

func _check(name: String, ok: bool, info: String = "") -> void:
	print("[%s] %s %s" % ["OK" if ok else "FAIL", name, info])
	if not ok:
		_fails += 1

func _reset_ext() -> void:
	for k in ["fire", "aim", "sprint", "crouch", "jump", "reload", "grenade", "prone"]:
		player.ext[k] = false
	player.ext.move = Vector2.ZERO
	player.ext.look = Vector2.ZERO

var _start: Vector3
var _start_yaw: float

func _home() -> void:
	player.global_position = _start
	player.velocity = Vector3.ZERO
	player.set_view(_start_yaw, -2.0)
	await _wait(0.3)

func _range_test() -> void:
	_start = player.global_position
	_start_yaw = player.yaw
	player.set_view(player.yaw, -2.0)
	await _wait(0.6)
	await _shot("hip")
	player.ext.aim = true
	await _wait(0.7)
	await _shot("ads")
	player.ext.aim = false
	# Feuern + Kreuz-Spreizung beim Laufen
	var s0: float = float(player.get_hud_info().spread_deg)
	player.ext.move = Vector2(0, 1)
	await _wait(0.6)
	var s1: float = float(player.get_hud_info().spread_deg)
	player.ext.sprint = true
	await _wait(0.5)
	var s2: float = float(player.get_hud_info().spread_deg)
	_reset_ext()
	await _wait(0.5)
	_check("spread grows walk/sprint", s1 > s0 and s2 > s1, "%.2f %.2f %.2f" % [s0, s1, s2])
	await _shot("walk_spread")
	# Nachladen (taktisch) in Phasen
	player.ext.fire = true
	await _wait(0.4)
	player.ext.fire = false
	await _wait(0.4)
	player.ext.reload = true
	var tl: Array = [0.22, 0.45, 0.9, 1.2]
	var t_prev: float = 0.0
	for i in tl.size():
		await _wait(float(tl[i]) - t_prev)
		t_prev = float(tl[i])
		await _shot("reload_%d" % i)
	await _wait(1.0)
	_check("reload done", player.weapon.ammo_mag == player.weapon.mag_size and not player.weapon.reloading)
	# Leer -> Auto-Reload mit Ladehebel
	player.ext.fire = true
	await _wait(3.2)
	player.ext.fire = false
	for i in 3:
		await _wait(0.5)
		await _shot("reload_empty_%d" % i)
	await _wait(1.5)
	_check("empty reload done", player.weapon.ammo_mag == player.weapon.mag_size)
	player.ext.move = Vector2(0, -1)
	await _wait(0.5)
	player.ext.move = Vector2.ZERO
	player.set_view(player.yaw, -45.0)
	await _wait(0.6)
	for b in Weapon._debris:
		if is_instance_valid(b):
			var rb := b as RigidBody3D
			var cs: CollisionShape3D = rb.find_children("*", "CollisionShape3D", false, false)[0]
			print("debris at ", rb.global_position, " size ", (cs.shape as BoxShape3D).size, " player ", player.global_position)
	await _shot("mags_on_floor")
	player.set_view(player.yaw, -2.0)
	var debris: int = get_tree().get_nodes_in_group("weapon_debris").size()
	print("debris mags: ", debris)
	# Pistole
	player.ext.weapon = 2
	await _wait(0.12)
	await _shot("switch_mid")
	await _wait(0.5)
	_check("pistol active", player.get_status().weapon == "pistol")
	await _shot("pistol_hip")
	player.ext.aim = true
	await _wait(0.6)
	await _shot("pistol_ads")
	player.ext.aim = false
	player.ext.fire = true
	for i in 14:
		await _wait(0.12)
		player.ext.fire = not player.ext.fire
	player.ext.fire = false
	await _wait(0.9)
	await _shot("pistol_reload")
	await _wait(1.5)
	player.ext.weapon = 1
	await _wait(0.7)
	_check("rifle back", player.get_status().weapon == "rifle")
	# Slide
	await _home()
	player.ext.move = Vector2(0, 1)
	player.ext.sprint = true
	await _wait(1.0)
	var p0: Vector3 = player.global_position
	player.ext.crouch = true
	await _wait(0.05)
	_check("slide started", player.get_status().sliding)
	await _wait(0.25)
	await _shot("slide")
	var t: float = 0.3
	while player.get_status().sliding and t < 2.0:
		await _wait(0.05)
		t += 0.05
	var d: float = p0.distance_to(player.global_position)
	_check("slide 0.8-1.0s", t >= 0.6 and t <= 1.1, "t=%.2f d=%.2f" % [t, d])
	_check("slide ends crouched", player.get_status().stance == "crouch")
	_reset_ext()
	await _wait(0.6)
	# Slide + Sprung bricht ab
	await _home()
	player.ext.move = Vector2(0, 1)
	player.ext.sprint = true
	await _wait(0.8)
	player.ext.crouch = true
	await _wait(0.2)
	player.ext.jump = true
	await _wait(0.05)
	print("jump test: ", player.get_status(), " vy=", player.velocity.y)
	_check("jump cancels slide", not player.get_status().sliding and player.velocity.y > 0.5)
	_reset_ext()
	await _wait(1.0)
	# Hinlegen
	await _home()
	player.ext.prone = true
	await _wait(1.2)
	var st: Dictionary = player.get_status()
	_check("prone", st.prone and absf(player.head.position.y - 0.35) < 0.06, "head=%.2f" % player.head.position.y)
	_check("prone counts as crouching for AI", player.is_crouching)
	await _shot("prone")
	var pp: Vector3 = player.global_position
	player.ext.move = Vector2(0, 1)
	await _wait(1.0)
	var crawl: float = pp.distance_to(player.global_position)
	_check("crawl slow", crawl > 0.4 and crawl < 1.3, "d=%.2f" % crawl)
	player.ext.move = Vector2.ZERO
	var spr: float = float(player.get_hud_info().spread_deg)
	print("prone spread ", spr)
	player.ext.prone = false
	await _wait(1.3)
	_check("stand up", player.get_status().stance == "stand" and player.head.position.y > 1.5)

func _mantle_test() -> void:
	# Spawn liegt im Graben (Sohle -0.85). Blick nach vorn (-Z), Sprung -> Mantle.
	player.global_position = Vector3(8.0, -0.8, 0.3)
	player.set_view(0.0, -8.0)
	await _wait(0.8)
	var y0: float = player.global_position.y
	print("start y=%.2f" % y0)
	await _shot("trench_before")
	player.ext.move = Vector2(0, 1)
	player.ext.jump = true
	var m_seen: bool = false
	var shot_done: bool = false
	for i in 90:
		await get_tree().physics_frame
		if player.get_status().mantling:
			m_seen = true
			if not shot_done and i > 8:
				shot_done = true
				await _shot("mantle_mid")
	await _wait(0.2)
	player.ext.move = Vector2.ZERO
	await _wait(0.4)
	await _shot("mantle_after")
	var p: Vector3 = player.global_position
	_check("mantle triggered", m_seen)
	_check("out of trench", p.y > -0.2 and p.z < -1.1, "pos=%s" % p)
	# Zurück, über die Rückwand (Sandsäcke) heraus
	player.global_position = Vector3(5.0, -0.8, 0.0)
	player.set_view(180.0, -8.0)
	await _wait(0.6)
	player.ext.move = Vector2(0, 1)
	player.ext.jump = true
	await _wait(1.2)
	player.ext.move = Vector2.ZERO
	await _wait(0.3)
	p = player.global_position
	_check("out of trench (back)", p.y > -0.2 and p.z > 1.1, "pos=%s" % p)
