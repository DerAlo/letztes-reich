extends Node
## Treiber fuer realistische VIP-Modelle (geriggtes GLB): uebertraegt die Drehung der Gelenk-Nodes
## (arms/legs/head aus VipModels-API) auf die Knochen des Skeleton3D. Die Nodes sitzen exakt auf den
## Gelenkpunkten der Knochen, daher dreht sich alles, was Level-Skripte an einen Arm-Node haengen
## (Koffer, Granate ...), um denselben Punkt wie der Arm des Modells.
## Cutscenes bleiben unveraendert: sie drehen weiterhin nur rotation.x der Nodes.

var skel: Skeleton3D
## Je Eintrag: {"bone": int, "node": Node3D, "s": Basis (Root->Skelett), "g": Basis (globale Ruhelage),
##              "p": Basis (globale Ruhelage des Elternknochens, invertiert)}
var links: Array[Dictionary] = []
var _last: Array[Basis] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last.resize(links.size())
	_apply(true)

func _process(_dt: float) -> void:
	_apply(false)

func _apply(force: bool) -> void:
	if skel == null or not is_instance_valid(skel):
		return
	for i in links.size():
		var l: Dictionary = links[i]
		var n := l["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var b := n.basis
		if not force and b.is_equal_approx(_last[i]):
			continue
		_last[i] = b
		var s: Basis = l["s"]
		var rs := s.inverse() * b.orthonormalized() * s          # Drehung im Skelettraum
		_pose(int(l["bone"]), rs, l["g"], l["p"])

func _pose(bone: int, rs: Basis, g: Basis, p_inv: Basis) -> void:
	var local := p_inv * (rs * g)
	skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
