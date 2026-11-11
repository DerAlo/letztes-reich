extends StaticBody3D
## Episode "Lena": abschiessbarer Suchscheinwerfer-Kopf (G28-Treffer -> Glas splittert, Licht aus).
## Das Level setzt light/beam (werden beim Treffer ausgeschaltet) und hoert auf "destroyed".

signal destroyed

var light: Light3D
var beam: Node3D
var glass: MeshInstance3D
var dead: bool = false


func is_alive() -> bool:
	return not dead


func take_damage(_amount: float, _source: Node = null, pos: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> void:
	if dead:
		return
	dead = true
	if light != null and is_instance_valid(light):
		light.visible = false
	if beam != null and is_instance_valid(beam):
		beam.visible = false
	if glass != null and is_instance_valid(glass):
		glass.visible = false
	var p := pos if pos != Vector3.ZERO else global_position
	VFX.spawn_impact(p, normal, "metal")
	VFX.play_sfx_3d("destruct_glass", p, 0.0, 12.0, 120.0)
	destroyed.emit()


## Checkpoint-Neustart vor dem Treffer: wieder an.
func restore() -> void:
	dead = false
	for n: Node3D in [light, beam, glass]:
		if n != null and is_instance_valid(n):
			n.visible = true
