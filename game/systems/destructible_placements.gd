extends RefCounted
## Zerstoerbare Deckung in fertigen Leveln (Runde 7, Welle 4, systeme-c) - rein additiv.
## Aufruf als erste Zeile im _bake_nav() des Levels, damit die Objekte als Hindernis ins Navmesh gebacken
## werden (nach dem Zerstoeren bleibt das Navmesh unveraendert -> kein Loch, keine Blockade).
## Debug: --destruct=0 schaltet die Nachruestung ab (A/B-Vergleich in Sims).

const Destructible := preload("res://game/systems/destructible.gd")
const ROUTE_CLEAR := 0.9     ## Mindestabstand Objektrand <-> Bot-Route
const SPAWN_CLEAR := 1.2

## level_name -> [[Art, Position (y = Boden), Gierwinkel, Optionen], ...]
const DATA := {
	"berlin": [
		["sandbag", Vector3(8.0, 0.0, -96.0), 0.0, {}],
		["planks", Vector3(-8.0, 0.0, -98.0), 0.0, {}],
		["glass", Vector3(-12.0, 0.0, -120.0), 90.0, {}],
		["crate", Vector3(-9.0, 0.0, -140.0), 10.0, {}],
		["brick", Vector3(9.0, 0.0, -165.0), 0.0, {}],
		["crate", Vector3(12.0, 0.0, -226.0), -15.0, {}],
		["brick", Vector3(-8.0, 0.0, -248.0), 0.0, {}],
		["sandbag", Vector3(6.0, 0.0, -262.0), 0.0, {}],
	],
	"river_crossing": [
		["planks", Vector3(5.0, 0.0, -40.0), 0.0, {}],
		["crate", Vector3(5.5, 0.0, -230.0), -10.0, {}],
		["glass", Vector3(6.0, 0.0, -10.0), 90.0, {}],
		["sandbag", Vector3(-5.0, 0.0, -240.0), 0.0, {}],
	],
	"spreebogen": [
		["planks", Vector3(-5.6, 0.0, -50.0), 90.0, {}],
		["glass", Vector3(-6.3, 0.0, -95.0), 90.0, {}],
		["crate", Vector3(5.8, 0.0, -112.0), 0.0, {}],
		["brick", Vector3(5.4, 0.0, -128.0), 90.0, {}],
		["sandbag", Vector3(5.4, 0.0, -205.0), 90.0, {}],
		["sandbag", Vector3(-5.4, 0.0, -120.0), 90.0, {}],
		["crate", Vector3(-6.0, 0.0, -252.0), 15.0, {}],
		["planks", Vector3(5.6, 0.0, -318.0), 0.0, {"width": 2.0}],
	],
	"bunker": [
		["crate", Vector3(3.5, 0.0, -8.0), 10.0, {}],
		["planks", Vector3(-9.5, 0.0, -19.0), 0.0, {}],
		["sandbag", Vector3(8.0, 0.0, -19.0), 0.0, {}],
		["glass", Vector3(9.0, 0.0, -31.0), 0.0, {}],
	],
	"funkturm": [
		["sandbag", Vector3(-8.0, 0.0, 74.0), 0.0, {}],
		["planks", Vector3(8.0, 0.0, 84.0), 0.0, {}],
		["crate", Vector3(-9.0, 0.0, 48.0), 15.0, {}],
		["brick", Vector3(9.0, 0.0, 44.0), 0.0, {}],
		["glass", Vector3(-10.0, 0.0, 30.0), 0.0, {}],
		["crate", Vector3(10.0, 0.0, 20.0), -10.0, {}],
		["sandbag", Vector3(-6.0, 0.0, 14.0), 0.0, {}],
		["planks", Vector3(12.0, 0.0, 66.0), 0.0, {}],
	],
}

static func place(level: Node) -> Array[Node]:
	var out: Array[Node] = []
	if str(Game.arg("destruct", "1")) == "0":
		return out
	var lname := str(level.get("level_name"))
	if not DATA.has(lname):
		return out
	var parent: Node = level.get("world")
	if parent == null:
		parent = level
	var route := _route(level)
	var spawns: Array[Vector3] = []
	for n in level.get_tree().get_nodes_in_group("enemy_spawn") if level.is_inside_tree() else []:
		if n is Node3D:
			spawns.append((n as Node3D).global_position)
	for e: Array in DATA[lname]:
		var kind: String = e[0]
		var pos: Vector3 = e[1]
		var opts: Dictionary = e[3]
		var def: Dictionary = Destructible.KINDS[kind]
		var half := float(opts.get("width", def["width"])) * 0.5
		if _too_close(pos, half + ROUTE_CLEAR, route) or _near_point(pos, half + SPAWN_CLEAR, spawns):
			print("[destructible] %s: %s bei %s uebersprungen (Route/Spawn zu nah)" % [lname, kind, pos])
			continue
		out.append(Destructible.spawn(parent, kind, pos, float(e[2]), opts))
	return out

static func _route(level: Node) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	if level.has_method("get_level_info"):
		var info: Dictionary = level.call("get_level_info")
		for w in info.get("waypoints", []):
			if w is Array and (w as Array).size() >= 3:
				pts.append(Vector3(float(w[0]), float(w[1]), float(w[2])))
	return pts

static func _too_close(p: Vector3, r: float, route: Array[Vector3]) -> bool:
	var q := Vector2(p.x, p.z)
	for i in range(route.size() - 1):
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i + 1].x, route[i + 1].z)
		if absf(route[i].y - p.y) > 2.5 and absf(route[i + 1].y - p.y) > 2.5:
			continue
		var ab := b - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if (a + ab * t).distance_to(q) < r:
			return true
	return false

static func _near_point(p: Vector3, r: float, pts: Array[Vector3]) -> bool:
	for s in pts:
		if Vector2(s.x - p.x, s.z - p.z).length() < r and absf(s.y - p.y) < 2.5:
			return true
	return false
