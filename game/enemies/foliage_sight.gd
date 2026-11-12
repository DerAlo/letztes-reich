extends RefCounted
## Laub-Sichtlinie (faire Sicht im Wald).
## Nadelbaum-Kronen haben keine Kollision (nur Stamm-Zylinder), der Spieler sieht durch die Zweigkarten
## aber kaum hindurch. Damit Gegner nicht "durch Laub" sehen und schiessen, registriert NightProps.forest()
## jede Krone hier (Knoten in Gruppe GROUP, Raster-Zellen als Meta). Die Gegner-Wahrnehmung (enemy.gd)
## summiert entlang der Sichtlinie die Laubtiefe (Sehnen durch Kronen-Kegel) und verwirft die Sicht,
## wenn sie ueber der entfernungsabhaengigen Grenze liegt. Gleiche Linie Auge->Kopf = symmetrische Sicht.
## Abschaltbar per Kommandozeile --foliage-los=0 (Vergleichslaeufe).

const GROUP := "foliage_occluder"
const CELL := 5.0
## Anteil deckender Nadelflaeche je Meter Kronenweg (Zweigkarten sind alpha-getestet, mit Luecken).
const DENSITY := 0.7
## Laubtiefe (m, nach DENSITY), ab der die Sicht abreisst: nah tolerant, auf Distanz (Nacht/Schnee) streng.
const BLOCK_NEAR := 2.2
const BLOCK_FAR := 1.0
const NEAR_D := 8.0
const FAR_D := 40.0

static var _enabled: int = -1

static func enabled() -> bool:
	if _enabled < 0:
		var g = Engine.get_main_loop()
		var v = null
		if g is SceneTree and (g as SceneTree).root.has_node("Game"):
			v = (g as SceneTree).root.get_node("Game").call("arg", "foliage-los", null)
		_enabled = 0 if (v != null and str(v) == "0") else 1
	return _enabled == 1

## Kronen registrieren. trees: Array von [Vector3 fuss, float skalierung] (wie NightProps.forest), tree_h = Meshhoehe bei Skala 1.
static func register(parent: Node, trees: Array, tree_h: float) -> Node:
	if parent == null or trees.is_empty():
		return null
	var cells: Dictionary = {}
	var hmax := 0.0
	for t in trees:
		var p: Vector3 = t[0]
		var h: float = tree_h * float(t[1])
		hmax = maxf(hmax, h)
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		var arr: PackedFloat32Array = cells.get(key, PackedFloat32Array())
		arr.append_array(PackedFloat32Array([p.x, p.y - 0.2, p.z, h]))
		cells[key] = arr
	var n := Node.new()
	n.name = "FoliageOccluder"
	n.set_meta("cells", cells)
	n.set_meta("rmax", radius_at(0.0, hmax) + 0.1)
	n.add_to_group(GROUP)
	parent.add_child(n)
	return n

## Kronenradius in Hoehe y ueber dem Stammfuss (Fichte: breiter, haengender Astschirm bis fast zum Boden).
static func radius_at(y: float, h: float) -> float:
	if y < 0.1 or y > h * 0.95:
		return 0.0
	return 0.24 * h * (1.0 - y / h) + 0.4

## Laubtiefe (m, bereits mit DENSITY gewichtet) entlang der Strecke a->b.
static func depth(tree: SceneTree, a: Vector3, b: Vector3) -> float:
	if tree == null:
		return 0.0
	var nodes := tree.get_nodes_in_group(GROUP)
	if nodes.is_empty():
		return 0.0
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var d2 := b2 - a2
	var len2 := d2.length()
	if len2 < 0.05:
		return 0.0
	var slope := a.distance_to(b) / len2
	var total := 0.0
	for n in nodes:
		if not is_instance_valid(n):
			continue
		var cells: Dictionary = n.get_meta("cells", {})
		var pad: float = n.get_meta("rmax", 4.0)
		var cx0 := floori((minf(a.x, b.x) - pad) / CELL)
		var cx1 := floori((maxf(a.x, b.x) + pad) / CELL)
		var cz0 := floori((minf(a.z, b.z) - pad) / CELL)
		var cz1 := floori((maxf(a.z, b.z) + pad) / CELL)
		var reach := pad + CELL * 0.7072
		for cx in range(cx0, cx1 + 1):
			for cz in range(cz0, cz1 + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key):
					continue
				var cc := Vector2((cx + 0.5) * CELL, (cz + 0.5) * CELL)
				if _seg_dist(cc, a2, b2) > reach:
					continue
				var pf: PackedFloat32Array = cells[key]
				var i := 0
				while i < pf.size():
					total += _chord(a, b, a2, d2, len2, pf[i], pf[i + 1], pf[i + 2], pf[i + 3])
					i += 4
	return total * slope * DENSITY

## Grenze fuer die Laubtiefe bei gegebener Sichtweite.
static func limit_for(dist: float) -> float:
	return lerpf(BLOCK_NEAR, BLOCK_FAR, clampf((dist - NEAR_D) / (FAR_D - NEAR_D), 0.0, 1.0))

## true, wenn Laub die Sicht a->b verdeckt.
static func blocks(tree: SceneTree, a: Vector3, b: Vector3) -> bool:
	if not enabled():
		return false
	var dep := depth(tree, a, b)
	return dep > 0.0 and dep > limit_for(a.distance_to(b))

## Abstand zum naechsten registrierten Stamm (horizontal), INF wenn keiner im Umkreis max_r.
static func nearest_tree(tree: SceneTree, p: Vector3, max_r: float = 6.0) -> float:
	if tree == null:
		return INF
	var best := INF
	for n in tree.get_nodes_in_group(GROUP):
		var cells: Dictionary = n.get_meta("cells", {})
		for cx in range(floori((p.x - max_r) / CELL), floori((p.x + max_r) / CELL) + 1):
			for cz in range(floori((p.z - max_r) / CELL), floori((p.z + max_r) / CELL) + 1):
				var pf: PackedFloat32Array = cells.get(Vector2i(cx, cz), PackedFloat32Array())
				var i := 0
				while i < pf.size():
					best = minf(best, Vector2(pf[i] - p.x, pf[i + 2] - p.z).length())
					i += 4
	return best

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Horizontale Sehnenlaenge der Strecke durch den Kronen-Kegel eines Baums.
static func _chord(a: Vector3, b: Vector3, a2: Vector2, d2: Vector2, len2: float, tx: float, ty: float, tz: float, h: float) -> float:
	var f := a2 - Vector2(tx, tz)
	var dd := d2.dot(d2)
	var tc := clampf(-f.dot(d2) / dd, 0.0, 1.0)
	var y := lerpf(a.y, b.y, tc) - ty
	var r := radius_at(y, h)
	if r <= 0.0:
		return 0.0
	var c := f.dot(f) - r * r
	var bq := 2.0 * f.dot(d2)
	var disc := bq * bq - 4.0 * dd * c
	if disc <= 0.0:
		return 0.0
	var sq := sqrt(disc)
	var t1 := clampf((-bq - sq) / (2.0 * dd), 0.0, 1.0)
	var t2 := clampf((-bq + sq) / (2.0 * dd), 0.0, 1.0)
	return (t2 - t1) * len2
