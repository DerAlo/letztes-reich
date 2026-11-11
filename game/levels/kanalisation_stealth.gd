extends "res://game/levels/curfew_stealth.gd"
## Schleich-Direktor fuer "kanalisation": wie curfew, zusaetzlich
## - Taschenlampe an -> Spieler gilt als hell beleuchtet (Lampenkegel verraten ihn),
## - im Wasser -> Waten ist laut (groesserer Geraeuschradius, auch geduckt).

var nightvision: Node            ## game/systems/nightvision.gd (flashlight_on)
var in_water: bool = false

func _init(lvl: Node3D) -> void:
	super(lvl)
	name = "KanalStealth"

func _process(delta: float) -> void:
	super(delta)
	if _player == null or not is_instance_valid(_player):
		return
	if nightvision != null and is_instance_valid(nightvision) and bool(nightvision.get("flashlight_on")):
		player_light = maxf(player_light, 0.8)

func _update_noise() -> void:
	super()
	if not in_water:
		return
	var v: Vector3 = _player.get("velocity")
	var spd := Vector2(v.x, v.z).length()
	if spd < 0.4 or not bool(_player.call("is_alive")):
		return
	if bool(_player.get("is_crouching")):
		noise_radius = maxf(noise_radius, 4.0)
	elif bool(_player.get("_sprinting")):
		noise_radius = maxf(noise_radius, 15.0)
	else:
		noise_radius = maxf(noise_radius, 8.0)
