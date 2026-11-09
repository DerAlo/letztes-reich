class_name WeaponDefs
extends RefCounted
## Waffen-Katalog: id -> Szene, Anzeigename, Munitionssorte, Slot.
## Slot 0 = Primärwaffe (wird per [E] getauscht), 1 = Pistole, 2 = Panzerfaust.

const DEFS: Dictionary = {
	"g36c": {"scene": "res://game/weapons/g36c.tscn", "name": "G36C", "ammo": "556", "slot": 0, "mag": 30},
	"ak74m": {"scene": "res://game/weapons/ak74m.tscn", "name": "AK-74M", "ammo": "545", "slot": 0, "mag": 30},
	"pistol": {"scene": "res://game/weapons/pistol.tscn", "name": "P228", "ammo": "9mm", "slot": 1, "mag": 12},
	"pzf3": {"scene": "res://game/weapons/panzerfaust.tscn", "name": "Panzerfaust 3", "ammo": "pzf", "slot": 2, "mag": 1},
}

const AMMO_NAMES: Dictionary = {"556": "5,56 mm", "545": "5,45 mm", "9mm": "9 mm", "pzf": "Panzerfaust-Rakete"}

static func has(id: String) -> bool:
	return DEFS.has(id)

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func display_name(id: String) -> String:
	return str(get_def(id).get("name", id.to_upper()))

static func ammo_of(id: String) -> String:
	return str(get_def(id).get("ammo", ""))

static func instantiate(id: String) -> Weapon:
	var d: Dictionary = get_def(id)
	if d.is_empty():
		return null
	var ps := load(str(d.scene)) as PackedScene
	return ps.instantiate() as Weapon if ps else null
