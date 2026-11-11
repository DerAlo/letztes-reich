extends Node3D
## Kamera-Tour fuer "curfew" (ohne Player, nur fuer Screenshots). Args: --view=<name>, --noenemies, --alarm.
## Beispiel: godot --path . --write-movie x.png --quit-after 150 res://game/levels/_curfew_tour.tscn -- --view=a

var _level: Node3D
var _cam: Camera3D

const VIEWS := {
	"a": [Vector3(5.0, 1.7, 5.5), Vector3(-1.0, 2.5, -40.0)],          # Start hinter dem Bus
	"b": [Vector3(-2.5, 1.6, -42.0), Vector3(2.0, 1.8, -64.0)],       # Kontrollpunkt
	"c": [Vector3(-19.4, 1.7, -46.0), Vector3(-27.0, 1.2, -72.0)],    # Hinterhof
	"d": [Vector3(-3.0, 1.7, -107.0), Vector3(4.0, 5.0, -150.0)],     # Platz
	"e": [Vector3(15.0, 1.7, -111.0), Vector3(36.0, 2.5, -118.0)],    # Lieferzufahrt
	"f": [Vector3(36.0, 1.7, -119.3), Vector3(36.5, 1.4, -128.0)],    # Ladehalle
	"g": [Vector3(35.2, 1.7, -133.2), Vector3(44.0, 1.0, -145.5)],    # Fernmeldestelle
	"h": [Vector3(42.3, -3.3, -163.0), Vector3(41.0, -4.2, -200.0)],  # Tunnel
	"i": [Vector3(10.0, 70.0, 25.0), Vector3(5.0, 0.0, -110.0)],      # Uebersicht
	"j": [Vector3(6.0, 2.0, -28.0), Vector3(-3.0, 2.5, -80.0)],       # Strasse Mitte
	"k": [Vector3(37.0, 1.7, -150.5), Vector3(42.5, -1.5, -157.0)],   # Rueckhalle/Schacht
	"l": [Vector3(-18.0, 3.0, -112.0), Vector3(20.0, 6.0, -150.0)],   # Platz diagonal
	"m": [Vector3(41.0, -3.4, -190.0), Vector3(40.6, -3.6, -200.0)],  # Voss
}

func _ready() -> void:
	_level = (load("res://game/levels/curfew.tscn") as PackedScene).instantiate() as Node3D
	_level.set("spawn_player", false)
	_level.set("spawn_enemies", Game.arg("noenemies", false) == false)
	add_child(_level)
	_cam = Camera3D.new()
	_cam.fov = 75
	_cam.far = 700
	add_child(_cam)
	_cam.make_current()
	var v: Array = VIEWS.get(str(Game.arg("view", "a")), VIEWS["a"])
	_cam.look_at_from_position(v[0], v[1])
	if Game.arg("alarm", false):
		while not _level.call("is_level_ready"):
			await get_tree().physics_frame
		var d: Node = _level.get("director")
		d.call("raise_alarm", Vector3(0, 0, -130), "spotted", true)
