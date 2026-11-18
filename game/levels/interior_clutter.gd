extends RefCounted
## Innenraum-Kram (nur Optik, keine Kollision): Kartons, Kisten, Muelleimer, Muellsaecke, Stuehle, Kanister,
## Werkzeugkiste, Ordner, Wanduhr, Sicherungskasten, Kabelstraenge. Modelle: Poly Haven (CC0),
## assets/environment/interior/models (tools/fetch_clutter_assets.py).
##
## Platzierung automatisch per Raycast, nachdem der Level gebaut ist (2 Physik-Frames): Zufallspunkte in einer
## Region -> Boden darunter, Decke darueber (= Innenraum), Wand in <= 1.2 m, Wand durchgehend (keine Tuer/Nische),
## vor dem Gegenstand 2 m frei (keine engen Gaenge), Huelle + Vorraum ohne Koerper/Areas (keine Moebel,
## Tueren, Trigger, Spawns). Eigener Zufallsgenerator -> Spielablauf unberuehrt. Fehlt ein Modell, entfaellt es.
##
## Aufruf: InteriorClutter.scatter(level, AABB(...), anzahl, "bunker"|"office"|"house"|"villa"|"tech"|"sewer", seed)

const DIR := "res://assets/environment/interior/models/"

## art -> [Modell, Teilnamen-Praefix ("" = alle), ausgeschlossenes Praefix, Montage, Wandhoehe]
const ITEMS := {
	"box": ["cardboard_box_01", "", "", "floor", 0.0],
	"crate": ["plastic_crate_02", "", "", "floor", 0.0],
	"bin": ["metal_trash_can", "metal_trash_can", "metal_trash_can_rust", "floor", 0.0],
	"bin_rust": ["metal_trash_can", "metal_trash_can_rust", "", "floor", 0.0],
	"bag": ["trashbag", "", "", "floor", 0.0],
	"chair": ["plastic_monobloc_chair_01", "", "", "floor", 0.0],
	"stool": ["metal_stool_01", "", "", "floor", 0.0],
	"armchair": ["modern_arm_chair_01", "", "", "floor", 0.0],
	"can": ["metal_jerrycan_green", "", "", "floor", 0.0],
	"can_p": ["plastic_jerrycan", "", "", "floor", 0.0],
	"toolbox": ["metal_toolbox", "", "", "floor", 0.0],
	"clock": ["wall_clock", "", "", "wall", 2.15],
	"powerbox": ["power_box_01", "", "", "wall", 1.45],
	"cables": ["modular_electric_cables", "", "", "cables", 0.0],
}

## Gewichte je Stil
const STYLES := {
	"bunker": {"box": 3, "crate": 3, "bin_rust": 2, "bag": 2, "stool": 2, "can": 3, "toolbox": 2, "powerbox": 2, "cables": 4},
	"office": {"box": 6, "bin": 3, "bag": 2, "chair": 2, "armchair": 1, "crate": 1, "clock": 2, "cables": 1},
	"house": {"box": 4, "bin": 1, "bag": 1, "chair": 1, "can_p": 1, "toolbox": 1, "clock": 1},
	"tech": {"box": 3, "crate": 3, "bin": 2, "stool": 2, "can": 1, "toolbox": 3, "powerbox": 3, "cables": 5, "clock": 1},
	"villa": {"box": 5, "clock": 1, "can_p": 1},
	"sewer": {"crate": 3, "bin_rust": 3, "bag": 4, "can": 2, "can_p": 2, "toolbox": 1, "powerbox": 1, "cables": 2},
}

const MIN_SPACING := 1.6
const VIS_END := 35.0

static var _parts: Dictionary = {}


static func _model_parts(kind: String) -> Array:
	if _parts.has(kind):
		return _parts[kind]
	var it: Array = ITEMS[kind]
	var m: String = it[0]
	var out: Array = []
	var path := DIR + m + "/" + m + ".gltf"
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
				var mi := n as MeshInstance3D
				var nm := str(mi.name)
				if mi.mesh == null:
					continue
				if str(it[1]) != "" and not nm.begins_with(str(it[1])):
					continue
				if str(it[2]) != "" and nm.begins_with(str(it[2])):
					continue
				var xf := Transform3D.IDENTITY
				var p: Node = mi
				while p != null and p != inst:
					if p is Node3D:
						xf = (p as Node3D).transform * xf
					p = p.get_parent()
				out.append({"mesh": mi.mesh, "xf": xf, "name": nm})
			inst.free()
	# auf Bodenmitte normieren (Teilsaetze wie der einzelne Muelleimer liegen im Modell seitlich versetzt)
	if not out.is_empty():
		var bb := _bounds(out)
		var off := Vector3(-bb.get_center().x, -bb.position.y, -bb.get_center().z)
		for d: Dictionary in out:
			d["xf"] = Transform3D(Basis.IDENTITY, off) * (d["xf"] as Transform3D)
	_parts[kind] = out
	return out


static func _bounds(parts: Array) -> AABB:
	var box := AABB()
	var first := true
	for d: Dictionary in parts:
		var b: AABB = (d["xf"] as Transform3D) * (d["mesh"] as Mesh).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _spawn(parent: Node3D, parts: Array, xf: Transform3D, shadows: bool, nm: String = "item") -> void:
	var root := Node3D.new()
	root.name = nm
	root.set_meta("wall_n", xf.basis.z)
	root.transform = xf
	for d: Dictionary in parts:
		var mi := MeshInstance3D.new()
		mi.mesh = d["mesh"]
		mi.transform = d["xf"]
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VIS_END
		mi.visibility_range_end_margin = 4.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		root.add_child(mi)
	parent.add_child(root)


static func _ray(ss: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.collide_with_areas = false
	return ss.intersect_ray(q)


## Ist die (gedrehte) Box frei von Koerpern und Areas?
static func _free(ss: PhysicsDirectSpaceState3D, xf: Transform3D, size: Vector3) -> bool:
	var sh := BoxShape3D.new()
	sh.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = xf
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return ss.intersect_shape(q, 1).is_empty()


## Verteilt `count` Gegenstaende in region (Weltkoordinaten). Laeuft verzoegert (Physik muss stehen).
## low_walls: Raeume mit Fensterbaendern (Bruestung ~1 m) -> Wand nur bis 0.8 m pruefen.
static func scatter(level: Node3D, region: AABB, count: int, style: String, seed_v: int, low_walls: bool = false) -> void:
	if not level.is_inside_tree() or OS.get_cmdline_user_args().has("--no-clutter"):
		return
	var tree := level.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	if not is_instance_valid(level) or not level.is_inside_tree():
		return
	var ss := level.get_world_3d().direct_space_state
	# Navigationsnetz (Bots) als Begehbarkeits-Pruefung: nur Wandstuecke an begehbaren Flaechen, keine Hohlraeume
	var map := level.get_world_3d().navigation_map
	for i in 120:
		if NavigationServer3D.map_get_iteration_id(map) > 0 and not NavigationServer3D.map_get_regions(map).is_empty():
			break
		await tree.physics_frame
	if not is_instance_valid(level) or not level.is_inside_tree():
		return
	var use_nav := not NavigationServer3D.map_get_regions(map).is_empty()
	var auto := region.size == Vector3.ZERO
	if auto:
		region = _level_bounds(level)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var weights: Dictionary = STYLES.get(style, STYLES["bunker"])
	var kinds: Array = []
	for k: String in weights:
		if not _model_parts(k).is_empty():
			for i in int(weights[k]):
				kinds.append(k)
	if kinds.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "InteriorClutter_" + style
	level.add_child(holder)
	var placed: Array[Vector3] = []
	var n := 0
	var tries := count * 200
	while n < count and tries > 0:
		tries -= 1
		var kind: String = kinds[rng.randi() % kinds.size()]
		var start := Vector3(rng.randf_range(region.position.x, region.end.x), rng.randf_range(region.position.y + 0.5, region.end.y),
				rng.randf_range(region.position.z, region.end.z))
		if auto and use_nav and rng.randf() < 0.8:
			# meist auf dem Navigationsnetz starten (Innenraeume in grossen Aussenleveln sonst kaum getroffen);
			# Punkt in Richtung eines zufaelligen Nachbarn versetzt, damit Wandnaehe vorkommt
			var np := NavigationServer3D.map_get_random_point(map, 1, true)
			if not region.has_point(np):
				continue
			start = np + Vector3(rng.randf_range(-1.2, 1.2), 1.0, rng.randf_range(-1.2, 1.2))
		var spot := _find_spot(ss, start, rng, low_walls)
		if spot.is_empty():
			continue
		var fp: Vector3 = spot["floor"]
		if use_nav and auto:
			var probe := fp + (spot["n"] as Vector3) * 0.7
			if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) > 0.6:
				continue
		var too_close := false
		for q: Vector3 in placed:
			if q.distance_to(fp) < MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		if _place(holder, ss, kind, spot, rng):
			placed.append(fp)
			n += 1
	print("[clutter] %s: %d Gegenstaende" % [style, n])


## Huelle aller Kollisionskoerper des Levels (Gelaende > 300 m ausgenommen).
static func _level_bounds(level: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n: Node in level.find_children("*", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs.shape == null or not (cs.get_parent() is StaticBody3D):
			continue
		var r := cs.shape.get_debug_mesh().get_aabb()
		var b: AABB = cs.global_transform * r
		if b.size.x > 300.0 or b.size.z > 300.0:
			continue
		box = b if first else box.merge(b)
		first = false
	return box


## Bodenpunkt an einer Innenwand: {floor, n (Wandnormale, horizontal), wall (Wandpunkt auf Bodenhoehe), ceil}
static func _find_spot(ss: PhysicsDirectSpaceState3D, start: Vector3, rng: RandomNumberGenerator, low_walls: bool = false) -> Dictionary:
	var fl := _ray(ss, start, start + Vector3.DOWN * 4.5)
	if fl.is_empty() or (fl["normal"] as Vector3).y < 0.9:
		return {}
	var fp: Vector3 = fl["position"]
	var cl := _ray(ss, fp + Vector3.UP * 0.2, fp + Vector3.UP * 5.5)
	if cl.is_empty():
		return {}
	var ceil_h: float = (cl["position"] as Vector3).y - fp.y
	if ceil_h < 2.2:
		return {}
	var best := {}
	var best_d := 99.0
	var a0 := rng.randf() * TAU
	for i in 8:
		var a := a0 + TAU * i / 8.0
		var d := Vector3(cos(a), 0, sin(a))
		var o := fp + Vector3.UP * 0.4
		var h := _ray(ss, o, o + d * 1.2)
		if h.is_empty():
			continue
		var nn: Vector3 = h["normal"]
		if absf(nn.y) > 0.2:
			continue
		var dist := o.distance_to(h["position"])
		if dist < best_d:
			best_d = dist
			nn.y = 0.0
			best = {"n": nn.normalized(), "wall": (h["position"] as Vector3) - Vector3.UP * 0.4}
	if best.is_empty():
		return {}
	var n: Vector3 = best["n"]
	var wall: Vector3 = best["wall"]
	# echte Wand: auch auf 1.6 m und 2.0 m Hoehe an derselben Stelle
	for hh: float in ([0.8] if low_walls else [1.6, 2.0]):
		if hh > ceil_h - 0.15:
			continue
		var o := wall + n * 0.5 + Vector3.UP * hh
		var h := _ray(ss, o, o - n * 0.7)
		if h.is_empty() or absf(o.distance_to(h["position"]) - 0.5) > 0.08:
			return {}
	# Raum davor: 2.2 m frei (keine Gaenge zuparken)
	var o2 := wall + n * 0.1 + Vector3.UP * 0.5
	if not _ray(ss, o2, o2 + n * 2.3).is_empty():
		return {}
	return {"floor": wall, "n": n, "ceil": ceil_h}


static func _place(holder: Node3D, ss: PhysicsDirectSpaceState3D, kind: String, spot: Dictionary, rng: RandomNumberGenerator) -> bool:
	var it: Array = ITEMS[kind]
	var parts := _model_parts(kind)
	var bb := _bounds(parts)
	var n: Vector3 = spot["n"]
	var wall: Vector3 = spot["floor"]
	var t := Vector3.UP.cross(n).normalized()          # entlang der Wand
	var mount: String = it[3]
	if mount == "cables":
		return _cables(holder, ss, parts, wall, n, t, float(spot["ceil"]), rng)
	# Modell-Front (+Z) zeigt in den Raum; Breite/Tiefe nach Drehung
	var yaw := atan2(n.x, n.z)
	var w := bb.size.x
	var dep := bb.size.z
	var basis := Basis(Vector3.UP, yaw)
	if mount == "wall":
		var wy: float = it[4]
		if wy + bb.size.y * 0.5 > float(spot["ceil"]) - 0.1:
			return false
		var pos := wall + n * 0.005 + Vector3.UP * (wy - bb.size.y * 0.5)
		# Wandteil (Uhr, Kasten): Rueckseite (Modell -Z) an die Wand
		pos += n * (-bb.position.z)
		if not _wall_flat(ss, wall, n, t, w, wy):
			return false
		_spawn(holder, parts, Transform3D(basis, pos), false, kind)
		return true
	# Bodenteil: leicht verdreht, mit Abstand zur Wand
	var jit := rng.randf_range(-0.35, 0.35) if kind in ["box", "crate", "bag", "can", "can_p", "toolbox", "bin", "bin_rust"] else rng.randf_range(-0.12, 0.12)
	if kind in ["chair", "armchair", "stool"]:
		jit += rng.randf_range(-0.5, 0.5)
	basis = Basis(Vector3.UP, yaw + jit)
	var reach := maxf(w, dep) * 0.5
	var pos := wall + n * (reach + 0.04) + t * rng.randf_range(-0.3, 0.3)
	pos.y = wall.y
	var cxf := Transform3D(Basis(Vector3.UP, yaw), pos + Vector3.UP * (bb.size.y * 0.5 + 0.06) + n * 0.03)
	if not _free(ss, cxf, Vector3(maxf(w, dep) + 0.15, bb.size.y, maxf(w, dep) + 0.06)):
		return false
	# Zugang davor frei (Moebel, Tueren, Trigger)
	var fxf := Transform3D(Basis(Vector3.UP, yaw), pos + n * (reach + 0.45) + Vector3.UP * 0.9)
	if not _free(ss, fxf, Vector3(maxf(w, dep) + 0.4, 1.6, 0.8)):
		return false
	_spawn(holder, parts, Transform3D(basis, pos), kind in ["armchair", "chair"], kind)
	# Stapel: Kartons/Kisten, obendrauf Ordner/zweiter Karton
	if kind == "box" or kind == "crate":
		var top := pos + Vector3.UP * bb.size.y
		var r := rng.randf()
		if r < 0.55:
			_spawn(holder, parts, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.4, 0.4)), top + t * rng.randf_range(-0.05, 0.05)), false)
			if r < 0.2 and kind == "box":
				_spawn(holder, parts, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.6, 0.6)), top + Vector3.UP * bb.size.y), false)
		elif kind == "box":
			# zweiter Karton daneben auf dem Boden
			var side := t * (w + 0.06) * (1.0 if rng.randf() < 0.5 else -1.0)
			var pxf := Transform3D(Basis(Vector3.UP, yaw), pos + side + Vector3.UP * (bb.size.y * 0.5 + 0.06))
			if _free(ss, pxf, Vector3(w, bb.size.y, dep)):
				_spawn(holder, parts, Transform3D(Basis(Vector3.UP, yaw + rng.randf_range(-0.5, 0.5)), pos + side), false)
	return true


## Wand auf Hoehe wy ueber die Breite w durchgehend eben (keine Tuer, kein Fenster).
static func _wall_flat(ss: PhysicsDirectSpaceState3D, wall: Vector3, n: Vector3, t: Vector3, w: float, wy: float) -> bool:
	for s: float in [-0.5, 0.0, 0.5]:
		var o := wall + n * 0.4 + t * (w * s) + Vector3.UP * wy
		var h := _ray(ss, o, o - n * 0.6)
		if h.is_empty() or absf(o.distance_to(h["position"]) - 0.4) > 0.06:
			return false
	var fxf := Transform3D(Basis.IDENTITY, wall + n * 0.35 + Vector3.UP * wy)
	return _free(ss, fxf, Vector3(0.5, 0.5, 0.5))


## Senkrechter Kabelstrang (Aufputz) vom Boden bis unter die Decke, mit Abzweigdose und Steckdose.
static func _cables(holder: Node3D, ss: PhysicsDirectSpaceState3D, parts: Array, wall: Vector3, n: Vector3, t: Vector3,
		ceil_h: float, rng: RandomNumberGenerator) -> bool:
	var by_name := {}
	for d: Dictionary in parts:
		by_name[d["name"]] = d
	if not by_name.has("cable_straight_long") or not by_name.has("cable_box_4way"):
		return false
	# senkrecht durchgehende Wand
	for hy: float in [0.4, 1.2, 2.0]:
		if hy > ceil_h - 0.1:
			break
		var o := wall + n * 0.3 + Vector3.UP * hy
		var h := _ray(ss, o, o - n * 0.5)
		if h.is_empty() or absf(o.distance_to(h["position"]) - 0.3) > 0.05:
			return false
	if not _free(ss, Transform3D(Basis.IDENTITY, wall + n * 0.3 + Vector3.UP * 1.2), Vector3(0.3, 1.6, 0.3)):
		return false
	# Teile liegen im Modell nebeneinander; einzeln auf ihren eigenen Ursprung zuruecksetzen.
	# Kabel: Laenge entlang Modell +Y, Tiefe entlang Modell Z -> Modell +Z zeigt in den Raum.
	var yaw := atan2(n.x, n.z)
	var basis := Basis(Vector3.UP, yaw)
	var base := wall + n * 0.02 + t * rng.randf_range(-0.3, 0.3)
	var top := ceil_h - 0.05
	var y := 0.3
	var box_y := rng.randf_range(1.1, 1.5)
	var placed_box := false
	while y < top - 0.05:
		if not placed_box and y + 0.6 > box_y:
			_part(holder, by_name["cable_box_4way"], basis, base + Vector3.UP * box_y)
			placed_box = true
		var seg: Dictionary = by_name["cable_straight_long"]
		_part(holder, seg, basis, base + Vector3.UP * y)
		y += 0.6
	if by_name.has("cable_plug_4x"):
		_part(holder, by_name["cable_plug_4x"], basis, base + Vector3.UP * 0.12)
	return true


static func _part(holder: Node3D, d: Dictionary, basis: Basis, pos: Vector3) -> void:
	var mesh: Mesh = d["mesh"]
	var ab := mesh.get_aabb()
	# eigenen Fuss (Unterkante, Rueckseite) an pos
	var local := (d["xf"] as Transform3D).basis
	var off := -(local * Vector3(ab.get_center().x, ab.position.y, ab.position.z))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(basis * local, pos + basis * off)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIS_END
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	holder.add_child(mi)
