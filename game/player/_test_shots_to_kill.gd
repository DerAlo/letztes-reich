extends Node3D
## Automatischer Test: Schüsse bis zum Kill mit den ECHTEN Gegner-Szenen.
## Start (headless):
##   Godot_v4.7.2-stable_win64_console.exe --headless --path D:\project_alo res://game/player/_test_shots_to_kill.tscn
## Zielt per Kamera-Raycast exakt auf die Mitte der Kopf-Hitbox bzw. des Torsos und zählt Treffer,
## bis der Gegner tot ist. Ruft Weapon._shoot() direkt auf (ohne Streuung = Schuss aus der Bildmitte).

const ENEMIES: Dictionary = {
	"rifleman": "res://game/enemies/rifleman.tscn",
	"heavy": "res://game/enemies/heavy.tscn",
}
const WEAPONS: Dictionary = {
	"rifle": "res://game/weapons/rifle.tscn",
	"pistol": "res://game/weapons/pistol.tscn",
}

var _cam: Camera3D

func _ready() -> void:
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.current = true
	await get_tree().physics_frame
	var lines: PackedStringArray = []
	var fails: int = 0
	for wname: String in WEAPONS:
		var weapon: Weapon = (load(WEAPONS[wname]) as PackedScene).instantiate() as Weapon
		add_child(weapon)
		for ename: String in ENEMIES:
			for zone: String in ["head", "torso"]:
				var r: Array = await _shots_to_kill(weapon, ENEMIES[ename], zone)
				var line := "STK %-6s %-8s %-5s shots=%d  dmg/hit=%.1f  hp=%.0f" % [wname, ename, zone, r[0], r[1], r[2]]
				lines.append(line)
				print(line)
				if r[0] <= 0:
					fails += 1
		weapon.queue_free()
	print("STK_DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)

## Rückgabe: [Schüsse, Schaden pro Treffer, Start-HP]; Schüsse = -1, wenn nicht getroffen/getötet.
func _shots_to_kill(weapon: Weapon, scene_path: String, zone: String) -> Array:
	var enemy: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	add_child(enemy)
	enemy.global_position = Vector3(0, 0, -12)
	enemy.set_physics_process(false)    # keine KI/Bewegung im Test
	enemy.set_process(false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s: float = float(enemy.get("body_scale"))
	var target: Vector3
	if zone == "head":
		target = (enemy.get("_head_hitbox") as Node3D).global_position
	else:
		target = enemy.global_position + Vector3.UP * 1.05 * s
	_cam.global_position = Vector3(target.x, target.y, 0.0)
	_cam.look_at(target, Vector3.UP)
	await get_tree().physics_frame
	var hp0: float = float(enemy.get("health"))
	var shots: int = 0
	var first_dmg: float = 0.0
	while enemy.call("is_alive") and shots < 30:
		var before: float = float(enemy.get("health"))
		weapon._shoot(_cam, 0.0)
		shots += 1
		if shots == 1:
			first_dmg = before - float(enemy.get("health"))
			if first_dmg <= 0.0:
				enemy.queue_free()
				return [-1, 0.0, hp0]
		await get_tree().physics_frame
	var ok: bool = not enemy.call("is_alive")
	enemy.queue_free()
	await get_tree().physics_frame
	return [shots if ok else -1, first_dmg, hp0]
