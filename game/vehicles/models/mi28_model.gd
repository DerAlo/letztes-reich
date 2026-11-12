extends RefCounted
## Mi-28N Kampfhubschrauber (glTF "Mi-28N Havoc", Rukh3D, CC-BY-4.0).
## build(pivot, faction) -> Teile-Dictionary wie heli_model.gd (+ root, tail_axis, source, kind, hitboxes, tail_z).
## Faellt auf das prozedurale Modell zurueck, wenn die gebackene Szene fehlt. ModelCache-tauglich.

const HeliReal = preload("res://game/vehicles/models/heli_real.gd")

static func build(pivot: Node3D, faction: String = "ru") -> Dictionary:
	return HeliReal.build(pivot, faction, "mi28n")
