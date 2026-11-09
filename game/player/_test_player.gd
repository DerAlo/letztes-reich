extends Node3D
## Automatischer Test des Player-Controllers über die externe Steuerung.

@onready var player: Player = $Player
@onready var dummy: Node = $Dummy

var _explosions: int = 0
var _died: int = 0
var _respawned: int = 0
var _damaged: int = 0
var _fired: int = 0
var _fails: int = 0

func _ready() -> void:
	Events.explosion.connect(func(_p: Vector3, _r: float, _s: float) -> void: _explosions += 1)
	Events.player_died.connect(func() -> void: _died += 1)
	Events.player_respawned.connect(func() -> void: _respawned += 1)
	Events.player_damaged.connect(func(_a: float, _s: Node) -> void: _damaged += 1)
	Events.weapon_fired.connect(func(_w: Node) -> void: _fired += 1)
	var shot: Variant = Game.arg("shot", "")
	if str(shot) != "":
		_shot_mode(str(shot))
	else:
		_run()

func _wait(sec: float) -> void:
	for i in int(sec * 60.0):
		await get_tree().physics_frame

func _check(name: String, ok: bool, info: String = "") -> void:
	print("[%s] %s %s" % ["OK" if ok else "FAIL", name, info])
	if not ok:
		_fails += 1

func _run() -> void:
	await _wait(0.3)
	player.external_input = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var st := player.get_status()
	print("Status start: ", st)
	_check("alive+100hp", st.alive and st.health == 100.0)
	_check("groups", player.is_in_group("player") and player.is_in_group("damageable"))

	# 1. Vorwärts laufen
	player.set_view(0.0, 0.0)
	var p0 := player.global_position
	player.ext.move = Vector2(0, 1)
	await _wait(1.0)
	var moved := p0.distance_to(player.global_position)
	_check("walk forward", moved > 3.0 and player.global_position.z < p0.z - 3.0, "moved=%.2f z=%.2f" % [moved, player.global_position.z])
	player.ext.sprint = true
	var p1 := player.global_position
	await _wait(0.5)
	var sprint_d := p1.distance_to(player.global_position)
	_check("sprint faster", sprint_d > 3.0, "d=%.2f in 0.5s" % sprint_d)
	player.ext.sprint = false
	player.ext.move = Vector2.ZERO
	await _wait(0.6)
	_check("stops", Vector2(player.velocity.x, player.velocity.z).length() < 0.1)
	# Sprung
	player.ext.jump = true
	await _wait(0.2)
	_check("jump", player.global_position.y > 0.2, "y=%.2f" % player.global_position.y)
	await _wait(1.0)
	# Ducken
	player.ext.crouch = true
	await _wait(0.5)
	_check("crouch", player.head.position.y < 1.2, "head_y=%.2f" % player.head.position.y)
	player.ext.crouch = false
	await _wait(0.5)
	_check("stand up", player.head.position.y > 1.5, "head_y=%.2f" % player.head.position.y)

	# 2. Zielen und feuern
	player.global_position = Vector3(0, 0.05, 0)
	await _wait(0.2)
	var body_target: Vector3 = dummy.global_position + Vector3(0, 0.2, 0)
	player.look_at_point(body_target)
	player.ext.aim = true
	await _wait(0.4)
	_check("ads fov", player.camera.fov < 65.0, "fov=%.1f" % player.camera.fov)
	var h0: float = dummy.health
	var ammo0: int = player.weapon.ammo_mag
	player.ext.fire = true
	await get_tree().physics_frame
	player.ext.fire = false
	await _wait(0.3)
	_check("single shot hits body", dummy.health < h0, "dmg=%.1f ammo %d->%d" % [h0 - dummy.health, ammo0, player.weapon.ammo_mag])
	_check("body dmg = weapon.damage", absf((h0 - dummy.health) - player.weapon.damage) < 0.1)
	# Kopfschuss
	player.set_view(player.yaw, player.pitch)
	player.look_at_point(dummy.get_node("Head").global_position)
	var h1: float = dummy.health
	player.ext.fire = true
	await get_tree().physics_frame
	player.ext.fire = false
	await _wait(0.3)
	_check("headshot x2", absf((h1 - dummy.health) - 2.0 * player.weapon.damage) < 0.1, "dmg=%.1f" % (h1 - dummy.health))
	# Dauerfeuer + RPM
	player.ext.aim = false
	player.look_at_point(body_target)
	var fired0 := _fired
	var ammo1: int = player.weapon.ammo_mag
	player.ext.fire = true
	await _wait(1.0)
	player.ext.fire = false
	var shots := _fired - fired0
	_check("rpm ~650 (shots in 1s)", shots >= 9 and shots <= 12, "shots=%d" % shots)
	_check("ammo consumed", player.weapon.ammo_mag == ammo1 - shots, "mag=%d" % player.weapon.ammo_mag)
	_check("dummy killed -> left enemy group", not dummy.is_in_group("enemy") and dummy.health <= 0.0, "hp=%.1f" % dummy.health)
	# Nachladen
	player.ext.reload = true
	await _wait(0.5)
	_check("reloading flag", player.get_status().reloading)
	await _wait(2.0)
	var st2 := player.get_status()
	_check("reload done", not st2.reloading and st2.ammo_mag == 30, str(st2))
	# Magazin leeren -> Auto-Reload
	player.ext.fire = true
	await _wait(3.5)
	player.ext.fire = false
	await _wait(2.5)
	_check("auto reload after empty", player.weapon.ammo_mag > 0, "mag=%d reserve=%d" % [player.weapon.ammo_mag, player.weapon.ammo_reserve])

	# 3. Pistole
	player.ext.weapon = 2
	await _wait(0.6)
	_check("switch pistol", player.get_status().weapon == "pistol")
	dummy.health = 500.0
	var f2 := _fired
	player.ext.fire = true
	await _wait(0.5)
	player.ext.fire = false
	_check("pistol fires", _fired > f2, "shots=%d" % (_fired - f2))
	player.ext.weapon = 1
	await _wait(0.6)
	_check("switch back rifle", player.get_status().weapon == "rifle")

	# 4. Granate
	var g0: int = player.grenades
	player.look_at_point(Vector3(0, 1.0, -18))
	player.ext.grenade = true
	await _wait(0.5)
	var gcount := get_tree().get_nodes_in_group("grenade").size()
	_check("grenade spawned", player.grenades == g0 - 1 and gcount == 1, "grenades=%d nodes=%d" % [player.grenades, gcount])
	var exp0 := _explosions
	await _wait(3.0)
	_check("grenade exploded (Events.explosion)", _explosions > exp0 and get_tree().get_nodes_in_group("grenade").size() == 0)

	# 5. Schaden, Regeneration
	player.global_position = Vector3(0, 0.05, 0)
	var d0 := _damaged
	player.take_damage(40.0, dummy, dummy.global_position, Vector3.ZERO)
	_check("damage", player.health == 60.0 and _damaged == d0 + 1, "hp=%.1f" % player.health)
	await _wait(3.0)
	_check("no regen before 4s", player.health == 60.0, "hp=%.1f" % player.health)
	await _wait(3.0)
	_check("regen after delay", player.health > 60.0, "hp=%.1f" % player.health)
	await _wait(2.0)
	_check("full regen", player.health == 100.0, "hp=%.1f" % player.health)

	# 6. Checkpoint + Tod + Respawn
	player.global_position = Vector3(5, 0.05, -3)
	Events.checkpoint_reached.emit("cp1")
	player.global_position = Vector3(-3, 0.05, 4)
	player.take_damage(500.0, dummy, dummy.global_position, Vector3.ZERO)
	_check("dead", not player.is_alive() and _died == 1)
	await _wait(1.0)
	_check("still dead at 1s", not player.is_alive())
	await _wait(1.3)
	_check("respawned at checkpoint", player.is_alive() and _respawned == 1 and player.global_position.distance_to(Vector3(5, 0.05, -3)) < 0.5, "pos=%s hp=%.0f" % [player.global_position, player.health])

	# 7. Trauma
	player.add_trauma(1.0)
	await _wait(0.1)
	_check("trauma shake", player.trauma > 0.5 and player.camera.rotation_degrees.length() > 0.01, "rot=%s" % player.camera.rotation_degrees)
	Events.explosion.emit(player.global_position + Vector3(3, 0, 0), 7.0, 1.0)
	_check("explosion trauma", player.trauma > 0.5)

	print("== Ergebnis: %s (%d Fehler) ==" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)

## Screenshot-Modus: --shot=<pfad> speichert nach kurzer Zeit das Bild (Sichtprüfung, nur mit Fenster/GPU).
func _shot_mode(path: String) -> void:
	await _wait(0.5)
	player.external_input = true
	player.look_at_point(dummy.global_position + Vector3(0, 0.3, 0))
	await _wait(0.6)
	player.ext.fire = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	player.ext.fire = false
	player.ext.aim = true
	await _wait(0.8)
	get_viewport().get_texture().get_image().save_png(path.replace(".png", "_ads.png"))
	get_tree().quit()
