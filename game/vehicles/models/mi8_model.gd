extends RefCounted
## Mi-8 Transporthubschrauber (glTF "Russian Transport Heli", Mateusz Wolinski, CC-BY-4.0).
## build(pivot, faction) -> Teile-Dictionary wie heli_model.gd (+ root, tail_axis, source, kind, hitboxes, tail_z).
## Faellt auf das prozedurale Modell zurueck, wenn die gebackene Szene fehlt. ModelCache-tauglich.

const HeliReal = preload("res://game/vehicles/models/heli_real.gd")

static func build(pivot: Node3D, faction: String = "eu") -> Dictionary:
	return HeliReal.build(pivot, faction, "mi8")
