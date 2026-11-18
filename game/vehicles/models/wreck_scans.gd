extends RefCounted
## Modellierte Fahrzeugwracks von Sketchfab (alle CC-BY 4.0, Nachweise in assets/CREDITS_ASSETS.md):
##  - "Burned-out Cars" (Renafox): zwei ausgebrannte Pkw            -> car_a, car_b
##  - "destroyed Bus 01" (o0ozexo0o): ausgebrannter Linienbus        -> bus
##  - "Destroyed car Van" (sehjadm64): ausgebrannter Transporter      -> van
##  - "Burnt Truck" (Digitage, Fotogrammetrie): ausgebrannte Zugmaschine -> truck
## Die glTF-Szenen werden einmal instanziert, die Meshes eines Fahrzeugs samt Knotentransform
## eingesammelt (Cache) und beim Platzieren normiert: Laenge entlang lokal Z, Boden y = 0, Mitte x/z = 0.
## Fehlt ein Asset, liefert place() -1 und der Aufrufer nutzt sein prozedurales Wrack.

const SRC := {
	"car_a": ["res://assets/vehicles/wrecks/burned_cars/scene.gltf", "default001"],
	"car_b": ["res://assets/vehicles/wrecks/burned_cars/scene.gltf", "default002"],
	"bus": ["res://assets/vehicles/wrecks/bus/scene.gltf", ""],
	"van": ["res://assets/vehicles/wrecks/van/scene.gltf", ""],
	"truck": ["res://assets/vehicles/wrecks/truck/scene.gltf", "", false, "", 0.04],
	# intakte Fahrzeuge (CC-BY 4.0): "vw golf 5 gti", "Mercedes Benz Sprinter 2006", "LCT 3000 '95"
	"golf": ["res://assets/vehicles/intact/golf5/scene.gltf", ""],
	"sprinter": ["res://assets/vehicles/intact/sprinter/scene.gltf", ""],
	"lct3000": ["res://assets/vehicles/intact/lct3000/scene.gltf", ""],
}
const VIS_END := 320.0
## Auf dem Dach: Anteil der Hoehe, um den das Wrack einsinkt. Die Scans haben ausgebrannte Dachholme ohne
## tragendes Dachblech; ohne Versenkung steht die Karosserie auf duennen Saeulen und wirkt schwebend.
## So liegt die Guertellinie auf dem Boden (eingedruecktes Dach, Fensterband im Boden verborgen).
const FLIP_SINK := {"car_a": 0.32, "car_b": 0.32, "van": 0.34, "bus": 0.16, "truck": 0.3}

## Versenkung in m fuer ein Wrack der Hoehe h auf dem Dach.
static func flip_sink(key: String, h: float) -> float:
	return h * float(FLIP_SINK.get(key, 0.0))

static var _cache: Dictionary = {}

## SRC-Eintrag: [Pfad, Basisknoten ("" = alles), Basis-Transform ignorieren?, Knotenpraefix ausschliessen,
##   Versenkung in m (Scan-Bodenstueck verschwindet im Boden)]
## Teile [[Mesh, Transform3D]] und gemeinsame AABB im Szenenraum; {} wenn das Asset fehlt.
static func _load(key: String) -> Dictionary:
	if _cache.has(key):
		return _cache[key]
	var out := {}
	var src: Array = SRC.get(key, [])
	if not src.is_empty() and ResourceLoader.exists(src[0]):
		var ps := load(src[0]) as PackedScene
		if ps != null:
			var inst := ps.instantiate() as Node3D
			var base: Node = inst
			if str(src[1]) != "":
				base = inst.find_child(str(src[1]), true, false)
			var stop: Node = inst
			if src.size() > 2 and bool(src[2]) and base != null:
				stop = base
			var skip := str(src[3]) if src.size() > 3 else ""
			if base != null:
				var parts: Array = []
				var box := AABB()
				var first := true
				var stack: Array[Node] = [base]
				while not stack.is_empty():
					var n: Node = stack.pop_back()
					if skip != "" and str(n.name).begins_with(skip):
						continue
					stack.append_array(n.get_children())
					var mi := n as MeshInstance3D
					if mi == null or mi.mesh == null:
						continue
					var xf := Transform3D.IDENTITY
					var p: Node = mi
					while p != null and p != stop:
						if p is Node3D:
							xf = (p as Node3D).transform * xf
						p = p.get_parent()
					parts.append([mi.mesh, xf])
					var bb: AABB = xf * mi.mesh.get_aabb()
					box = bb if first else box.merge(bb)
					first = false
				if not parts.is_empty():
					out = {"parts": parts, "aabb": box}
			inst.free()
	_cache[key] = out
	return out

## Ersetzt unter root das Material mit dem Namen mat_name (z. B. Lack des Lkw-Kastens) durch m.
static func repaint(root: Node, mat_name: String, m: Material) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		for si in mi.mesh.get_surface_count():
			var sm := mi.mesh.surface_get_material(si)
			if sm != null and str(sm.resource_name) == mat_name:
				mi.set_surface_override_material(si, m)

static func available(key: String) -> bool:
	return not _load(key).is_empty()

## Haengt das Wrack unter root: Laenge `length` entlang lokal Z (Breite/Hoehe proportional).
## yaw_deg dreht zusaetzlich um die Hochachse (z. B. 180 = Front tauschen). Rueckgabe: Hoehe, -1 = fehlt.
static func place(root: Node3D, key: String, length: float, yaw_deg: float = 0.0) -> float:
	var d := _load(key)
	if d.is_empty():
		return -1.0
	var box: AABB = d["aabb"]
	var rot := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var long := box.size.z
	if box.size.x > box.size.z:
		rot = rot * Basis(Vector3.UP, PI * 0.5)
		long = box.size.x
	var s := length / maxf(long, 0.001)
	var b := rot.scaled(Vector3(s, s, s))
	var c := box.get_center()
	var off := -(b * Vector3(c.x, box.position.y, c.z))
	var src: Array = SRC[key]
	var sink := float(src[4]) if src.size() > 4 else 0.0
	off.y -= sink
	var holder := Node3D.new()
	holder.name = "WreckScan"
	holder.transform = Transform3D(b, off)
	root.add_child(holder)
	for part: Array in d["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		mi.visibility_range_end = VIS_END
		mi.visibility_range_end_margin = 20.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mi)
	return box.size.y * s - sink
