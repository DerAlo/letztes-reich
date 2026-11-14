class_name DropManager
extends Node
## Waffen-/Munitions-Drops gefallener Gegner und Munitionskisten an Checkpoints.
## Nutzt nur vorhandene Signale (Events.enemy_killed, Events.checkpoint_reached); enemy.gd bleibt unverändert.
## Die physikalisch fallende Gegnerwaffe ("DroppedWeapon", soldier_visual.gd) wird nach dem Liegenbleiben
## ausgeblendet und durch ein Pickup an derselben Stelle ersetzt.

const MAX_DROPS: int = 14
const DROP_LIFETIME: float = 90.0
const SETTLE_TIME: float = 1.4
const AMMO_CHANCE: float = 0.35

var player: Player = null
var _drops: Array = []
var _crate_ids: Dictionary = {}

func _ready() -> void:
	# Waffenmodelle (AK-74M/G36 + Rotpunkt) beim Levelstart laden: kein Ruckler beim ersten Drop
	GunModels.preload_all()
	Events.enemy_killed.connect(_on_enemy_killed)
	Events.checkpoint_reached.connect(_on_checkpoint)

func _world() -> Node:
	var root: Node = get_tree().current_scene
	if root == null and player:
		root = player.get_parent()
	return root

## Drop-Tabelle: ru -> AK-74M, reich -> G36, Drohnen/Fahrzeuge -> nichts.
static func weapon_for(faction: String, etype: String) -> String:
	if etype == "drone" or etype == "":
		return ""
	return "g36c" if faction == "reich" else "ak74m"

func _on_enemy_killed(enemy: Node) -> void:
	if not (enemy is Node3D) or not is_instance_valid(enemy):
		return
	var etype: String = str(enemy.get("enemy_type")) if "enemy_type" in enemy else ""
	var faction: String = str(enemy.get("faction")) if "faction" in enemy else str(enemy.get_meta("faction", "ru"))
	var wid: String = weapon_for(faction, etype)
	if wid == "":
		return
	var death_pos: Vector3 = (enemy as Node3D).global_position
	var wr: WeakRef = weakref(enemy)
	get_tree().create_timer(SETTLE_TIME).timeout.connect(func() -> void: _spawn_drop(wr, death_pos, wid))

func _spawn_drop(wr: WeakRef, death_pos: Vector3, wid: String) -> void:
	var root: Node = _world()
	if root == null:
		return
	var pos: Vector3 = death_pos
	var yaw: float = randf() * 360.0
	var enemy: Node = wr.get_ref() as Node
	if enemy != null:
		var dw: Node3D = enemy.find_child("DroppedWeapon", true, false) as Node3D
		if dw != null:
			pos = dw.global_position
			yaw = rad_to_deg(dw.global_rotation.y)
			# Physik-Waffe ausblenden (nicht freigeben: gehört dem Gegner-Visual)
			dw.visible = false
			if dw is RigidBody3D:
				(dw as RigidBody3D).freeze = true
	# Munitionsstand der liegenden Waffe: ein angebrochenes Magazin + etwas Reserve
	var mag: int = randi_range(8, 24)
	var reserve: int = randi_range(0, 30)
	var p: Pickup = Pickup.spawn_weapon(root, pos, wid, mag, reserve, yaw, DROP_LIFETIME)
	_track(p)
	if randf() < AMMO_CHANCE:
		var ammo_types: Array[String] = ["556", "545", "9mm"]
		var t: String = WeaponDefs.ammo_of(wid)
		# Häufig Munition für die eigene Primärwaffe, damit sie nicht ausgeht
		if player and player.weapons.size() > 0 and randf() < 0.6:
			t = player.weapons[0].ammo_type
		elif randf() < 0.3:
			t = ammo_types[randi() % ammo_types.size()]
		var off := Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))
		var amt: int = 12 if t == "9mm" else 30
		_track(Pickup.spawn_ammo(root, pos + off, t, amt, DROP_LIFETIME))

func _track(p: Pickup) -> void:
	_drops.append(p)
	var i: int = 0
	while i < _drops.size():
		if not is_instance_valid(_drops[i]):
			_drops.remove_at(i)
		else:
			i += 1
	while _drops.size() > MAX_DROPS:
		var old: Variant = _drops.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()

## Checkpoint: Munitionskiste neben dem Spieler (einmal pro Checkpoint-ID).
func _on_checkpoint(id: String) -> void:
	if player == null or _crate_ids.has(id):
		return
	_crate_ids[id] = true
	var root: Node = _world()
	if root == null:
		return
	var b: Basis = player.global_basis
	# Nicht in eine Wand stellen und nicht über eine Dachkante hinaus (sonst schwebt die Kiste in der Luft,
	# weil Pickup._snap unter ihr keinen Boden findet): Kandidaten der Reihe nach prüfen.
	var space := player.get_world_3d().direct_space_state
	var eye: Vector3 = player.global_position + Vector3.UP * 0.5
	var pos: Vector3 = player.global_position + b * Vector3(0.0, 0.0, 1.2)
	for off: Vector3 in [Vector3(1.4, 0.0, -0.6), Vector3(-1.4, 0.0, -0.6), Vector3(0.0, 0.0, 1.2),
			Vector3(1.0, 0.0, 0.4), Vector3(-1.0, 0.0, 0.4), Vector3(0.7, 0.0, 0.0), Vector3(-0.7, 0.0, 0.0)]:
		var c: Vector3 = player.global_position + b * off
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, c + Vector3.UP * 0.5, 1)).is_empty():
			continue
		var down := PhysicsRayQueryParameters3D.create(c + Vector3.UP * 0.8, c + Vector3.DOWN * 1.0, 1)
		if space.intersect_ray(down).is_empty():
			continue
		pos = c
		break
	Pickup.spawn_crate(root, pos, player.rotation_degrees.y + 90.0, false)
