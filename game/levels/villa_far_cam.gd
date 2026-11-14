extends Node
## Villa: hebt die Sichtweite der Weltkameras an, damit die Berge jenseits des Traunsees (bis ca. 6 km)
## nicht an der Far-Plane der Spielerkamera (500 m) abgeschnitten werden. Kameras mit kleiner Far-Plane
## (< 100 m, z. B. die Waffenkamera) bleiben unveraendert. Wird von VillaDressing in das Level gehaengt.

const FAR := 7000.0

var _t: float = 0.0

func _ready() -> void:
	get_tree().node_added.connect(_on_added)
	_scan.call_deferred()

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_added):
		get_tree().node_added.disconnect(_on_added)

func _on_added(n: Node) -> void:
	if n is Camera3D:
		_fix.call_deferred(n)

func _fix(c: Camera3D) -> void:
	if is_instance_valid(c) and c.far >= 100.0 and c.far < FAR:
		c.far = FAR

func _scan() -> void:
	for c in get_tree().root.find_children("*", "Camera3D", true, false):
		_fix(c as Camera3D)

func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_fix(cam)
