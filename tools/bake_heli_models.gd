extends SceneTree
## Backt die Hubschrauber-glTFs (Mi-8 "Russian Transport Heli", Mi-28N "Havoc") in saubere Godot-Szenen:
##  - Einheit Meter, Nase -Z, +Y oben, Ursprung auf der Rotorachse, Bodenkontakt bei y = GROUND_Y (wie heli_model.gd)
##  - statische Teile je Material zu einem Mesh zusammengefasst (+ LODs), Skinning (Mi-28N) aufgeloest
##  - MainRotor (lokale Y = Rotorachse, aus den Blattspitzen bestimmt) > Blades > Arm<i> > Blade<i> (+ Hub)
##  - TailRotor (lokale X = Drehachse) > TailBlades > Mesh;  Mi-28N: GunYaw > GunPitch > Gun + Muzzle
## Aufruf: Godot --headless --path D:/project_alo --script res://tools/bake_heli_models.gd
## (nach dem Import der glTFs; erzeugt assets/models/vehicles/<name>/<name>.scn)

const GROUND_Y := -1.94

const MODELS := [
	{"name": "mi8", "src": "res://assets/models/vehicles/mi8/scene.gltf", "dst": "res://assets/models/vehicles/mi8/mi8.scn",
		"length": 18.2, "main": "Rotor_Hub", "tail": "rotor_q", "gun": "", "main_blades": 5, "tail_blades": 3},
	{"name": "mi28n", "src": "res://assets/models/vehicles/mi28n/scene.gltf", "dst": "res://assets/models/vehicles/mi28n/mi28n.scn",
		"length": 17.0, "main": "Bone.002", "tail": "Bone.004", "gun": "Bone.005", "main_blades": 5, "tail_blades": 4},
]

var _frame := 0
var _roots: Array[Node3D] = []

func _init() -> void:
	for cfg: Dictionary in MODELS:
		var ps := load(cfg["src"]) as PackedScene
		var r := ps.instantiate() as Node3D
		root.add_child(r)
		_roots.append(r)
		# Mi-28N: Ruhepose der Knochen != Einsatzpose (Kanone zeigt in der Ruhepose schraeg) -> Animation "ON" bei t = 0
		for ap in r.find_children("*", "AnimationPlayer", true, false):
			var anims := (ap as AnimationPlayer).get_animation_list()
			for an in anims:
				if String(an).ends_with("|ON"):
					(ap as AnimationPlayer).play(an)
					(ap as AnimationPlayer).seek(0.0, true)
					(ap as AnimationPlayer).pause()

func _process(_d: float) -> bool:
	_frame += 1
	if _frame == 3:
		for i in MODELS.size():
			_bake(MODELS[i], _roots[i])
		quit()
	return _frame >= 3

# ------------------------------------------------------------------ Einsammeln

## [{mesh, xf (Rohwelt), cls ("static"/"main"/"tail"/"gun"), pivot (Rohwelt, nur Skin)}]
func _collect(cfg: Dictionary, r: Node3D) -> Array:
	var out: Array = []
	for n in r.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var e := {"mesh": mi.mesh, "xf": mi.global_transform, "cls": "static", "name": String(mi.get_path())}
		var key := String(mi.get_path())
		if mi.skin != null:
			var sk := mi.get_node(mi.skeleton) as Skeleton3D
			var cnt := {}
			var arr := mi.mesh.surface_get_arrays(0)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			for j in bones.size():
				if w[j] > 0.5:
					cnt[bones[j]] = int(cnt.get(bones[j], 0)) + 1
			var bi := -1
			var best := -1
			for k in cnt:
				if int(cnt[k]) > best:
					best = int(cnt[k])
					bi = int(k)
			var bone := mi.skin.get_bind_bone(bi)
			if bone < 0:
				bone = sk.find_bone(mi.skin.get_bind_name(bi))
			e["xf"] = sk.global_transform * sk.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bi)
			e["pivot"] = (sk.global_transform * sk.get_bone_global_pose(bone)).origin
			key = sk.get_bone_name(bone)
		for c: String in ["main", "tail", "gun"]:
			if str(cfg[c]) != "" and key.contains(str(cfg[c])):
				e["cls"] = c
		out.append(e)
	return out

# ------------------------------------------------------------------ Geometrie

## Oberflaeche -> {v, n, t, uv, idx} in Zielraum xf (Skin-Daten, UV2, Farben entfallen)
func _surf(mesh: Mesh, s: int, xf: Transform3D) -> Dictionary:
	var a := mesh.surface_get_arrays(s)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var t: PackedFloat32Array = a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV] if a[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(v.size())
		for i in v.size():
			idx[i] = i
	var nb := xf.basis.inverse().transposed()
	var det := xf.basis.determinant()
	var ov := PackedVector3Array()
	ov.resize(v.size())
	var on := PackedVector3Array()
	on.resize(v.size())
	var ot := PackedFloat32Array()
	ot.resize(v.size() * 4)
	for i in v.size():
		ov[i] = xf * v[i]
		on[i] = (nb * n[i]).normalized() if n.size() == v.size() else Vector3.UP
		if t.size() == v.size() * 4:
			var tv := (xf.basis * Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])).normalized()
			ot[i * 4] = tv.x
			ot[i * 4 + 1] = tv.y
			ot[i * 4 + 2] = tv.z
			ot[i * 4 + 3] = t[i * 4 + 3] * signf(det)
		else:
			ot[i * 4] = 1.0
			ot[i * 4 + 3] = 1.0
	if uv.size() != v.size():
		uv.resize(v.size())
	if det < 0.0:
		for i in range(0, idx.size(), 3):
			var tmp := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = tmp
	return {"v": ov, "n": on, "t": ot, "uv": uv, "idx": idx}

func _append(acc: Dictionary, s: Dictionary) -> void:
	var base: int = (acc["v"] as PackedVector3Array).size()
	acc["v"].append_array(s["v"])
	acc["n"].append_array(s["n"])
	acc["t"].append_array(s["t"])
	acc["uv"].append_array(s["uv"])
	var idx: PackedInt32Array = s["idx"]
	var o: PackedInt32Array = acc["idx"]
	for i in idx:
		o.append(i + base)
	acc["idx"] = o

func _empty() -> Dictionary:
	return {"v": PackedVector3Array(), "n": PackedVector3Array(), "t": PackedFloat32Array(), "uv": PackedVector2Array(), "idx": PackedInt32Array()}

func _arrays(s: Dictionary) -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = s["v"]
	a[Mesh.ARRAY_NORMAL] = s["n"]
	a[Mesh.ARRAY_TANGENT] = s["t"]
	a[Mesh.ARRAY_TEX_UV] = s["uv"]
	a[Mesh.ARRAY_INDEX] = s["idx"]
	return a

## Gruppen (Material -> Oberflaeche) zu einem ArrayMesh mit LODs
func _mesh(groups: Dictionary, lods: bool) -> ArrayMesh:
	var im := ImporterMesh.new()
	for m in groups:
		if (groups[m]["idx"] as PackedInt32Array).is_empty():
			continue
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, _arrays(groups[m]), [], {}, m, (m as Material).resource_name if m != null else "")
	if lods:
		im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()

## Teil-Oberflaeche aus ausgewaehlten Dreiecken (Vertices neu indiziert), optional verschoben
func _subset(s: Dictionary, tris: PackedInt32Array, xf: Transform3D) -> Dictionary:
	var o := _empty()
	var remap := {}
	var idx: PackedInt32Array = s["idx"]
	var oi := PackedInt32Array()
	for tri in tris:
		for k in 3:
			var vi := idx[tri * 3 + k]
			if not remap.has(vi):
				remap[vi] = (o["v"] as PackedVector3Array).size()
				o["v"].append(xf * (s["v"][vi] as Vector3))
				o["n"].append((xf.basis * (s["n"][vi] as Vector3)).normalized())
				var tv := xf.basis * Vector3(s["t"][vi * 4], s["t"][vi * 4 + 1], s["t"][vi * 4 + 2])
				o["t"].append_array(PackedFloat32Array([tv.x, tv.y, tv.z, s["t"][vi * 4 + 3]]))
				o["uv"].append(s["uv"][vi])
			oi.append(remap[vi])
	o["idx"] = oi
	return o

## Rotor in n Blaetter + Nabe zerlegen. s liegt im Rotor-Lokalraum (Achse = lokale Y, Ursprung auf der Achse).
## Rueckgabe: {"hub": PackedInt32Array, "blades": [{tris, angle}], "radius": float}
func _split(s: Dictionary, nb: int) -> Dictionary:
	var v: PackedVector3Array = s["v"]
	var idx: PackedInt32Array = s["idx"]
	var radius := 0.0
	for p in v:
		radius = maxf(radius, Vector2(p.x, p.z).length())
	var tri_n := idx.size() / 3
	var tip_angles: Array[float] = []
	var cent: Array[Vector3] = []
	for t in tri_n:
		var c := (v[idx[t * 3]] + v[idx[t * 3 + 1]] + v[idx[t * 3 + 2]]) / 3.0
		cent.append(c)
		if Vector2(c.x, c.z).length() > radius * 0.6:
			tip_angles.append(atan2(-c.x, -c.z))
	var angles := _clusters(tip_angles, nb)
	var blades: Array = []
	for a in angles:
		blades.append({"tris": PackedInt32Array(), "angle": a})
	var hub := PackedInt32Array()
	for t in tri_n:
		var c := cent[t]
		if Vector2(c.x, c.z).length() < radius * 0.13:
			hub.append(t)
			continue
		var a := atan2(-c.x, -c.z)
		var bi := 0
		var bd := 99.0
		for k in angles.size():
			var d := absf(wrapf(a - angles[k], -PI, PI))
			if d < bd:
				bd = d
				bi = k
		blades[bi]["tris"].append(t)
	return {"hub": hub, "blades": blades, "radius": radius}

## n Winkel-Cluster: an den n groessten Luecken der sortierten Winkel trennen, Kreismittel je Cluster
func _clusters(angles: Array[float], n: int) -> Array[float]:
	angles.sort()
	var m := angles.size()
	var gaps: Array = []
	for i in m:
		var a := angles[i]
		var b := angles[(i + 1) % m] + (TAU if i == m - 1 else 0.0)
		gaps.append([b - a, i])
	gaps.sort_custom(func(x, y): return x[0] > y[0])
	var cuts: Array[int] = []
	for k in n:
		cuts.append(int(gaps[k][1]))
	cuts.sort()
	var out: Array[float] = []
	for k in n:
		var i0 := cuts[k] + 1
		var i1 := cuts[(k + 1) % n] + (m if k == n - 1 else 0)
		var sx := 0.0
		var sy := 0.0
		for i in range(i0, i1 + 1):
			sx += sin(angles[i % m])
			sy += cos(angles[i % m])
		out.append(atan2(sx, sy))
	return out

## Achse + Zentrum eines Rotors aus den Blattspitzen (Zielraum). approx = ungefaehre Achse.
func _fit_axis(s: Dictionary, nb: int, approx: Vector3) -> Dictionary:
	var v: PackedVector3Array = s["v"]
	var c0 := Vector3.ZERO
	for p in v:
		c0 += p
	c0 /= float(v.size())
	var tb := Basis(Quaternion(Vector3.UP, approx.normalized()))
	var loc := s.duplicate()
	var lv := PackedVector3Array()
	for p in v:
		lv.append(tb.inverse() * (p - c0))
	loc["v"] = lv
	var sp := _split(loc, nb)
	var tips: Array[Vector3] = []
	for b in sp["blades"]:
		# Schwerpunkt der aeusseren Dreiecke dieses Blatts
		var acc := Vector3.ZERO
		var cnt := 0
		var idx: PackedInt32Array = s["idx"]
		for t in (b["tris"] as PackedInt32Array):
			var c := (lv[idx[t * 3]] + lv[idx[t * 3 + 1]] + lv[idx[t * 3 + 2]]) / 3.0
			if Vector2(c.x, c.z).length() > float(sp["radius"]) * 0.75:
				acc += c
				cnt += 1
		tips.append(acc / float(maxi(cnt, 1)))
	var center := Vector3.ZERO
	for p in tips:
		center += p
	center /= float(tips.size())
	var normal := Vector3.ZERO
	if tips.size() >= 3:
		for i in tips.size():   # Newell
			var a := tips[i]
			var b := tips[(i + 1) % tips.size()]
			normal += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		normal = normal.normalized()
		if normal.y < 0.0:
			normal = -normal
	else:
		normal = Vector3.UP
	return {"center": c0 + tb * center, "axis": (tb * normal).normalized(), "radius": float(sp["radius"])}

# ------------------------------------------------------------------ Backen

func _bake(cfg: Dictionary, r: Node3D) -> void:
	var entries := _collect(cfg, r)
	# Rohmaß (statische Teile) -> Skalierung
	var raw := AABB()
	var first := true
	for e in entries:
		if e["cls"] != "static":
			continue
		var bb: AABB = (e["xf"] as Transform3D) * (e["mesh"] as Mesh).get_aabb()
		raw = bb if first else raw.merge(bb)
		first = false
	var sc := float(cfg["length"]) / raw.size.z
	var f0 := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * sc), Vector3.ZERO)
	# Oberflaechen im Zwischenraum f0
	var parts := {"static": {}, "main": _empty(), "tail": _empty(), "gun": _empty()}
	var part_mats := {}
	var gun_pivot := Vector3.ZERO
	for e in entries:
		var mesh: Mesh = e["mesh"]
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat != null and not part_mats.has(mat):
				part_mats[mat] = mat.duplicate(true)
			var dm: Material = part_mats.get(mat)
			var sd := _surf(mesh, s, f0 * (e["xf"] as Transform3D))
			if e["cls"] == "static":
				if not parts["static"].has(dm):
					parts["static"][dm] = _empty()
				_append(parts["static"][dm], sd)
			else:
				sd["mat"] = dm
				_append(parts[e["cls"]], sd)
				parts[e["cls"]]["mat"] = dm
		if e["cls"] == "gun":
			gun_pivot = f0 * (e["pivot"] as Vector3)
	print("[bake] %s main verts=%d tail verts=%d gun verts=%d" % [cfg["name"], parts["main"]["v"].size(), parts["tail"]["v"].size(), parts["gun"]["v"].size()])
	var main_fit := _fit_axis(parts["main"], int(cfg["main_blades"]), Vector3.UP)
	var tail_fit := _fit_axis(parts["tail"], int(cfg["tail_blades"]), Vector3.RIGHT)
	var miny := INF
	for m in parts["static"]:
		for p: Vector3 in parts["static"][m]["v"]:
			miny = minf(miny, p.y)
	var c: Vector3 = main_fit["center"]
	var off := Vector3(-c.x, GROUND_Y - miny, -c.z)
	var sh := Transform3D(Basis.IDENTITY, off)

	var out := Node3D.new()
	out.name = String(cfg["name"]).to_upper()
	# Rumpf
	for m in parts["static"]:
		var g: Dictionary = parts["static"][m]
		for i in (g["v"] as PackedVector3Array).size():
			g["v"][i] = sh * (g["v"][i] as Vector3)
	var body := MeshInstance3D.new()
	body.name = "Body"
	body.mesh = _mesh(parts["static"], true)
	out.add_child(body)
	# Hauptrotor
	var axis: Vector3 = main_fit["axis"]
	var rotor := Node3D.new()
	rotor.name = "MainRotor"
	rotor.transform = Transform3D(Basis(Quaternion(Vector3.UP, axis)), sh * (main_fit["center"] as Vector3))
	out.add_child(rotor)
	var to_rotor := rotor.transform.affine_inverse() * sh
	var ms: Dictionary = parts["main"]
	var loc := _subset(ms, _all_tris(ms), to_rotor)
	var sp := _split(loc, int(cfg["main_blades"]))
	var blades := Node3D.new()
	blades.name = "Blades"
	rotor.add_child(blades)
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	hub.mesh = _mesh({ms["mat"]: _subset(loc, sp["hub"], Transform3D.IDENTITY)}, false)
	blades.add_child(hub)
	var bi := 0
	for b in sp["blades"]:
		var arm := Node3D.new()
		arm.name = "Arm%d" % bi
		arm.rotation.y = float(b["angle"])
		blades.add_child(arm)
		var bs := _subset(loc, b["tris"], Transform3D(Basis(Vector3.UP, float(b["angle"])).inverse(), Vector3.ZERO))
		var bb := AABB(bs["v"][0], Vector3.ZERO)
		for p: Vector3 in bs["v"]:
			bb = bb.expand(p)
		var cc := bb.get_center()
		for i in (bs["v"] as PackedVector3Array).size():
			bs["v"][i] = (bs["v"][i] as Vector3) - cc
		var bm := MeshInstance3D.new()
		bm.name = "Blade%d" % bi
		bm.mesh = _mesh({ms["mat"]: bs}, false)
		bm.position = cc
		arm.add_child(bm)
		bi += 1
	# Heckrotor (lokale X = Drehachse)
	var tax: Vector3 = tail_fit["axis"]
	if tax.x < 0.0:
		tax = -tax
	var tail := Node3D.new()
	tail.name = "TailRotor"
	tail.transform = Transform3D(Basis(Quaternion(Vector3.RIGHT, tax)), sh * (tail_fit["center"] as Vector3))
	out.add_child(tail)
	var tail_blades := Node3D.new()
	tail_blades.name = "TailBlades"
	tail.add_child(tail_blades)
	var ts: Dictionary = parts["tail"]
	var tm := MeshInstance3D.new()
	tm.name = "TailMesh"
	tm.mesh = _mesh({ts["mat"]: _subset(ts, _all_tris(ts), tail.transform.affine_inverse() * sh)}, false)
	tail_blades.add_child(tm)
	# Kanone
	var gun_info := ""
	if (parts["gun"]["v"] as PackedVector3Array).size() > 0:
		var gy := Node3D.new()
		gy.name = "GunYaw"
		gy.position = sh * gun_pivot
		out.add_child(gy)
		var gp := Node3D.new()
		gp.name = "GunPitch"
		gy.add_child(gp)
		var gs: Dictionary = parts["gun"]
		var to_pivot := Transform3D(Basis.IDENTITY, -gy.position) * sh
		var gl := _subset(gs, _all_tris(gs), to_pivot)
		var tip := _gun_tip(gl)
		# Rohr in der Einsatzpose schraeg (gierend/geneigt) -> so drehen, dass es entlang -Z zeigt (Zielcode setzt Gier/Nick)
		var align := Basis(Quaternion(tip.normalized(), Vector3.FORWARD))
		gl = _subset(gs, _all_tris(gs), Transform3D(align, Vector3.ZERO) * to_pivot)
		tip = _gun_tip(gl)
		tip.x = 0.0
		var gm := MeshInstance3D.new()
		gm.name = "Gun"
		gm.mesh = _mesh({gs["mat"]: gl}, false)
		gp.add_child(gm)
		var mz := Marker3D.new()
		mz.name = "Muzzle"
		mz.position = tip + Vector3(0, 0, -0.05)
		gp.add_child(mz)
		gun_info = "gun pivot %s muzzle %s" % [gy.position, mz.position]
	out.set_meta("rotor_radius", float(sp["radius"]))
	out.set_meta("tail_radius", float(tail_fit["radius"]))
	out.set_meta("main_blades", int(cfg["main_blades"]))
	out.set_meta("tail_blades", int(cfg["tail_blades"]))
	_own(out, out)
	var ps := PackedScene.new()
	var err := ps.pack(out)
	if err == OK:
		err = ResourceSaver.save(ps, cfg["dst"], ResourceSaver.FLAG_COMPRESS)
	# Statistik fuer die Platzierung von Lichtern/Trefferzonen
	var fin := AABB()
	first = true
	for m in parts["static"]:
		for p: Vector3 in parts["static"][m]["v"]:
			fin = AABB(p, Vector3.ZERO) if first else fin.expand(p)
			first = false
	print("[bake] %s -> %s err=%d scale=%.5f body=%s" % [cfg["name"], cfg["dst"], err, sc, fin])
	print("[bake]   main center=%s axis=%s R=%.2f blades=%s" % [rotor.position, axis, float(sp["radius"]), (sp["blades"] as Array).map(func(b): return "%.0f°/%d" % [rad_to_deg(b["angle"]), (b["tris"] as PackedInt32Array).size()])])
	print("[bake]   tail center=%s axis=%s R=%.2f  %s" % [tail.position, tax, float(tail_fit["radius"]), gun_info])
	_profile(parts["static"])
	out.free()

func _all_tris(s: Dictionary) -> PackedInt32Array:
	var o := PackedInt32Array()
	for t in (s["idx"] as PackedInt32Array).size() / 3:
		o.append(t)
	return o

func _own(n: Node, owner_node: Node) -> void:
	for ch in n.get_children():
		ch.owner = owner_node
		_own(ch, owner_node)

## Rumpfprofil je 1-m-Scheibe (Breite/Hoehe), fuer Trefferzonen und Lichter
func _profile(groups: Dictionary) -> void:
	var sl := {}
	for m in groups:
		for p: Vector3 in groups[m]["v"]:
			var k := int(floor(p.z))
			if not sl.has(k):
				sl[k] = [INF, -INF, INF, -INF]
			var a: Array = sl[k]
			a[0] = minf(a[0], p.x)
			a[1] = maxf(a[1], p.x)
			a[2] = minf(a[2], p.y)
			a[3] = maxf(a[3], p.y)
	var ks := sl.keys()
	ks.sort()
	for k in ks:
		var a: Array = sl[k]
		print("[bake]   z=%3d..%3d  x %.2f..%.2f  y %.2f..%.2f" % [k, k + 1, a[0], a[1], a[2], a[3]])

## Mittelpunkt der vordersten Vertices (Muendung), Pivot-Raum.
func _gun_tip(gl: Dictionary) -> Vector3:
	var minz := INF
	for p: Vector3 in gl["v"]:
		minz = minf(minz, p.z)
	var tip := Vector3.ZERO
	var n := 0
	for p: Vector3 in gl["v"]:
		if p.z < minz + 0.06:
			tip += p
			n += 1
	return tip / float(maxi(n, 1))
