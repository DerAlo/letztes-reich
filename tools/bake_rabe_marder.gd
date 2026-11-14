extends SceneTree
## Backt "Marder 1A3 | High-Quality model" (Scout, Sketchfab, CC-BY 4.0) zum Schuetzenpanzer "Rabe":
##  - Einheit Meter (Laenge 6,79 m), vorne = -Z, +Y oben, Ursprung = Bodenmitte (Kettenaufstandsflaeche y = 0)
##  - alle Vertices in Fahrzeugkoordinaten; bewegliche Teile haengen unter Pivot-Knoten, deren Mesh-Kind um
##    -Pivot versetzt ist (vehicle_paint.gdshader rechnet Tarnung/Schmutz im Objektraum -> durchgehend)
##  - Vertex-Farbe = Materialkanal fuer vehicle_paint (r Lack, g Gummi, a Helligkeit); Glas als eigene Oberflaeche
##  - LODs je Mesh (ImporterMesh.generate_lods)
## Hierarchie: Rabe > Hull > {HullMesh, Tracks, Wheel_L_<i>/Wheel_R_<i> > Mesh, RearRamp > Mesh, Antenna_<i> > Mesh,
##   Turret > {TurretMesh, Mantlet > {MountMesh, Barrel > BarrelMesh}, MgMount > MgMesh}}
## Metadaten am Wurzelknoten: muzzle, coax_muzzle (Fahrzeugkoordinaten), wheel_radius.
## Aufruf (nach dem Import des glb): Godot --headless --path D:/project_alo --script res://tools/bake_rabe_marder.gd

const SRC := "res://assets/vehicles/marder/marder_1a3_hq.glb"
const DST := "res://assets/vehicles/marder/rabe_marder.scn"
const LENGTH := 6.79                      # Marder 1A3, Laenge ueber alles (Wanne)
# Pivots/Muendungen in Fahrzeugkoordinaten vor dem Bodenversatz (aus der Vertex-Analyse des glb)
const TURRET_PIVOT := Vector3(0.072, 2.0, 0.0)
const MOUNT_PIVOT := Vector3(0.066, 2.534, 0.42)
const MUZZLE := Vector3(0.066, 2.534, -1.53)
const MG_PIVOT := Vector3(-0.801, 2.519, 0.5)
const COAX := Vector3(-0.801, 2.519, -0.18)

# Klassen ueber den glb-Knotennamen (Punkte ersetzt Godot durch "_")
const TURRET_PREFIX := ["bone_turret", "ex_armor_turret", "gun_barrel_01", "bone_rocket", "rocket_atgm", "hatch_04"]
const MOUNT_NAMES := ["gun_mask", "gun_mask_002"]
const MG_NAMES := ["mg", "gun_mask_001"]

var _frame := 0
var _r: Node3D

func _init() -> void:
	var ps := load(SRC) as PackedScene
	_r = ps.instantiate() as Node3D
	root.add_child(_r)

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 2:
		_bake()
		quit()
	return _frame >= 2

# ------------------------------------------------------------------ Hilfen

func _norm(s: String) -> String:
	return s.replace(".", "_")

func _cls(n: String) -> String:
	if n == "gun_barrel":
		return "barrel"
	if n in MOUNT_NAMES:
		return "mount"
	if n in MG_NAMES:
		return "mg"
	for p: String in TURRET_PREFIX:
		if n.begins_with(p):
			return "turret"
	if n.begins_with("track_"):
		return "track"
	if n.begins_with("wheel_"):
		return "wheel"
	if n == "hatch_09":
		return "ramp"
	if n.begins_with("antenna_"):
		return "antenna"
	return "hull"

## Materialkanal (Vertex-Farbe) je glb-Material; "" = Glas (eigene Oberflaeche)
func _chan(mat_name: String, n: String) -> Variant:
	if mat_name.contains("glass"):
		return mat_name
	if mat_name.contains("track"):
		return Color(0, 0.55, 0, 0.75)
	if mat_name.contains("mg_42"):
		return Color(0, 0, 0, 0.32)
	if mat_name.contains("net_"):
		return Color(0, 0, 0, 0.22)
	if n.begins_with("antenna_"):
		return Color(0, 0, 0, 0.3)
	if mat_name.contains("body_add"):
		return Color(1, 0, 0, 0.88)
	if mat_name.contains("milan_rocket_c"):
		return Color(1, 0, 0, 0.93)
	return Color(1, 0, 0, 1)

func _empty() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "idx": PackedInt32Array()}

## Gruppe: {Oberflaechenname -> Puffer}
func _add(group: Dictionary, surf: String, v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray, idx: PackedInt32Array) -> void:
	if not group.has(surf):
		group[surf] = _empty()
	var acc: Dictionary = group[surf]
	var base: int = (acc["v"] as PackedVector3Array).size()
	acc["v"].append_array(v)
	acc["n"].append_array(n)
	acc["c"].append_array(c)
	var o: PackedInt32Array = acc["idx"]
	for i in idx:
		o.append(i + base)
	acc["idx"] = o

func _mesh(group: Dictionary, offset: Vector3) -> ArrayMesh:
	var im := ImporterMesh.new()
	var names := group.keys()
	names.sort()
	names.erase("paint")
	names.push_front("paint")
	for s: String in names:
		if not group.has(s):
			continue
		var g: Dictionary = group[s]
		if (g["idx"] as PackedInt32Array).is_empty():
			continue
		var v: PackedVector3Array = g["v"]
		var vv := PackedVector3Array()
		vv.resize(v.size())
		for i in v.size():
			vv[i] = v[i] - offset
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = vv
		a[Mesh.ARRAY_NORMAL] = g["n"]
		a[Mesh.ARRAY_COLOR] = g["c"]
		a[Mesh.ARRAY_INDEX] = g["idx"]
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, null, s)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

func _mi(parent: Node3D, node_name: String, group: Dictionary, pivot_world: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _mesh(group, Vector3.ZERO)
	parent.add_child(mi)
	mi.position = -pivot_world
	return mi

func _pivot(parent: Node3D, node_name: String, world: Vector3, parent_world: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = node_name
	parent.add_child(p)
	p.position = world - parent_world
	return p

func _own(n: Node, owner_node: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner_node
		_own(ch, owner_node)

# ------------------------------------------------------------------ Backen

func _bake() -> void:
	# 1) Rohgeometrie einsammeln und in Fahrzeugkoordinaten bringen
	var raw: Array = []   # [{name, cls, mat, v, n, idx}]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var tris := 0
	for nd in _r.find_children("*", "MeshInstance3D", true, false):
		var mi := nd as MeshInstance3D
		var pname := _norm(String(mi.get_parent().name))
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var mat := mi.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat != null else String(mi.name)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				for i in v.size():
					idx.append(i)
			var ov := PackedVector3Array()
			ov.resize(v.size())
			var on := PackedVector3Array()
			on.resize(v.size())
			for i in v.size():
				var p := xf * v[i]
				ov[i] = p
				lo = lo.min(p)
				hi = hi.max(p)
				on[i] = (xf.basis.inverse().transposed() * n[i]).normalized() if n.size() == v.size() else Vector3.UP
			if xf.basis.determinant() < 0.0:
				for i in range(0, idx.size(), 3):
					var t := idx[i + 1]
					idx[i + 1] = idx[i + 2]
					idx[i + 2] = t
			tris += idx.size() / 3
			raw.append({"name": pname, "cls": _cls(pname), "mat": mname, "v": ov, "n": on, "idx": idx})
	print("[bake] %d Teile, %d Dreiecke, Roh-AABB %s .. %s" % [raw.size(), tris, lo, hi])
	# Laengsachse = groesste horizontale Ausdehnung; glb: vorne = +Z (Rohraum) -> 180 Grad um Y
	var sc := LENGTH / (hi.z - lo.z)
	var fix := Basis(Vector3.UP, PI).scaled(Vector3(sc, sc, sc))
	var ctr := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.z + hi.z) * 0.5)
	# Bodenkontakt: Unterkante der Ketten
	var ground := INF
	for e: Dictionary in raw:
		if e["cls"] == "track":
			for p: Vector3 in e["v"]:
				ground = minf(ground, p.y)
	var shift := Vector3(0, -ground * sc, 0)
	var fin_lo := Vector3(INF, INF, INF)
	var fin_hi := -fin_lo
	for e: Dictionary in raw:
		var v: PackedVector3Array = e["v"]
		var n: PackedVector3Array = e["n"]
		for i in v.size():
			v[i] = fix * (v[i] - ctr) + shift
			n[i] = (Basis(Vector3.UP, PI) * n[i]).normalized()
			fin_lo = fin_lo.min(v[i])
			fin_hi = fin_hi.max(v[i])
		e["v"] = v
		e["n"] = n
	print("[bake] Massstab %.5f, Fahrzeug-AABB %s .. %s (Groesse %s)" % [sc, fin_lo, fin_hi, fin_hi - fin_lo])
	# Pivots in die Endkoordinaten (Bodenversatz der Analyse = 0,0205 m)
	var dy := Vector3(0, shift.y - 0.0205, 0)
	var tp := TURRET_PIVOT + Vector3(0, 0.0205, 0) + dy
	var mp := MOUNT_PIVOT + Vector3(0, 0.0205, 0) + dy
	var gp := MG_PIVOT + Vector3(0, 0.0205, 0) + dy
	var muzzle := MUZZLE + Vector3(0, 0.0205, 0) + dy
	var coax := COAX + Vector3(0, 0.0205, 0) + dy

	# 2) Gruppen bilden
	var groups := {"hull": {}, "track": {}, "turret": {}, "mount": {}, "barrel": {}, "mg": {}, "ramp": {}}
	var wheels: Array = []    # [{name, group, center, r}]
	var antennas: Array = []
	for e: Dictionary in raw:
		var v: PackedVector3Array = e["v"]
		var ch: Variant = _chan(e["mat"], e["name"])
		var surf := "paint"
		var col := Color(1, 0, 0, 1)
		if ch is String:
			surf = "glass_lamp" if (ch as String).contains("headlight") else "glass"
		else:
			col = ch
		var c := PackedColorArray()
		c.resize(v.size())
		c.fill(col)
		var cls: String = e["cls"]
		if cls == "wheel":
			var a := AABB(v[0], Vector3.ZERO)
			for p in v:
				a = a.expand(p)
			var center := a.get_center()
			var rr := a.size.y * 0.5
			var nm: String = e["name"]
			var tire := nm.contains("top") or (not nm.contains("drive") and not nm.contains("back"))
			if tire:
				for i in v.size():
					var d := Vector2(v[i].y - center.y, v[i].z - center.z).length()
					if d > rr - minf(0.065, rr * 0.22):
						c[i] = Color(0, 1, 0, 0.95)
					elif d < rr * 0.18:
						c[i] = Color(0, 0, 0, 0.5)
			var g := {}
			_add(g, surf, v, e["n"], c, e["idx"])
			wheels.append({"name": nm, "group": g, "center": center, "r": rr})
			continue
		if cls == "antenna":
			var g2 := {}
			_add(g2, surf, v, e["n"], c, e["idx"])
			var base := v[0]
			for p in v:
				if p.y < base.y:
					base = p
			antennas.append({"group": g2, "base": base})
			continue
		_add(groups[cls], surf, v, e["n"], c, e["idx"])

	# 3) Szene aufbauen
	var out := Node3D.new()
	out.name = "Rabe"
	var hull := _pivot(out, "Hull", Vector3.ZERO, Vector3.ZERO)
	_mi(hull, "HullMesh", groups["hull"], Vector3.ZERO)
	var tr := _mi(hull, "Tracks", groups["track"], Vector3.ZERO)
	tr.position = Vector3.ZERO
	wheels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
	var road_r := 0.0
	for w: Dictionary in wheels:
		var nm: String = w["name"]
		var side := "L" if nm.begins_with("wheel_l") else "R"
		var wn := _pivot(hull, "Wheel_%s_%s" % [side, nm.trim_prefix("wheel_l_").trim_prefix("wheel_r_")], w["center"], Vector3.ZERO)
		_mi(wn, "Mesh", w["group"], w["center"])
		if not nm.contains("top") and not nm.contains("drive") and not nm.contains("back"):
			road_r = maxf(road_r, float(w["r"]))
	# Heckklappe: Scharnier an der Unterkante hinten
	var ra := AABB()
	var first := true
	for s in groups["ramp"]:
		for p: Vector3 in groups["ramp"][s]["v"]:
			ra = AABB(p, Vector3.ZERO) if first else ra.expand(p)
			first = false
	var hinge := Vector3(0.0, ra.position.y + 0.04, ra.end.z - 0.06)
	var ramp := _pivot(hull, "RearRamp", hinge, Vector3.ZERO)
	_mi(ramp, "Mesh", groups["ramp"], hinge)
	for i in antennas.size():
		var an := _pivot(hull, "Antenna_%d" % i, antennas[i]["base"], Vector3.ZERO)
		_mi(an, "Mesh", antennas[i]["group"], antennas[i]["base"])
	var tur := _pivot(hull, "Turret", tp, Vector3.ZERO)
	_mi(tur, "TurretMesh", groups["turret"], tp)
	var mant := _pivot(tur, "Mantlet", mp, tp)
	_mi(mant, "MountMesh", groups["mount"], mp)
	var bar := _pivot(mant, "Barrel", mp, mp)
	_mi(bar, "BarrelMesh", groups["barrel"], mp)
	var mg := _pivot(tur, "MgMount", gp, tp)
	_mi(mg, "MgMesh", groups["mg"], gp)
	out.set_meta("muzzle", muzzle)
	out.set_meta("coax_muzzle", coax)
	out.set_meta("wheel_radius", road_r)
	out.set_meta("size", fin_hi - fin_lo)
	_own(out, out)
	var ps := PackedScene.new()
	var err := ps.pack(out)
	if err == OK:
		err = ResourceSaver.save(ps, DST, ResourceSaver.FLAG_COMPRESS)
	print("[bake] -> %s err=%d turret=%s mount=%s mg=%s muzzle=%s coax=%s hinge=%s road_r=%.3f wheels=%d antennas=%d" % [
		DST, err, tp, mp, gp, muzzle, coax, hinge, road_r, wheels.size(), antennas.size()])
	for k in groups:
		var cnt := 0
		for s in groups[k]:
			cnt += (groups[k][s]["idx"] as PackedInt32Array).size() / 3
		print("[bake]   %s: %d Dreiecke, Oberflaechen %s" % [k, cnt, groups[k].keys()])
	out.free()
