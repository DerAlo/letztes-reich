class_name PropCollision
extends RefCounted
## Enge Kollision fuer Deckungs-Props (Autos, Wracks, Barrieren, Sandsaecke, Kisten, Truemmer ...).
##
## Problem: Props hatten EINE grosse Box auf Layer 1 (world). Hitscan (Kamera-Ray, Maske world+player+enemy)
## blieb dadurch in unsichtbaren Box-Ecken haengen (ueber der Motorhaube, zwischen Panzersperren-Streben,
## an abgerundeten Kanten ...).
##
## Loesung (laeuft einmal direkt NACH dem Navmesh-Bake in level.gd _ready):
##  - Layer 1 (world)      : passgenaue konvexe Huellen aus der sichtbaren Geometrie (eine Huelle pro
##                           zusammenhaengendem Mesh-Teil; bei vielen Teilen raeumlich gruppiert).
##                           -> Kugeln, Sichtlinien, Explosions-LOS, Truemmer, Granaten.
##  - Layer 5 (move_block) : die alten, vereinfachten Boxen auf einem Kind-StaticBody "MoveBlock".
##                           -> nur Bewegung (Player/Gegner, sobald deren collision_mask Bit 5 enthaelt).
##  Das Navmesh wurde vorher mit den alten Boxen gebacken und bleibt dadurch exakt gleich.
##
## Props werden automatisch erkannt: StaticBody3D auf Layer 1 mit eigenen sichtbaren Meshes, nur
## primitiven Formen (Box/Zylinder/Kugel/Kapsel), max. 20 m gross. Bewusste Sperren (Kollision deutlich
## hoeher/breiter als die Optik, z. B. Levelgrenzen), Bodies mit eigenem Skript und Bodies mit Meta "no_fit"
## bleiben unveraendert.

const LAYER_WORLD := 1
const LAYER_MOVE_BLOCK := 16          # Layer 5
const MAX_EXTENT := 20.0              # groessere Bodies (Gebaeude, Boden) nicht anfassen
const MAX_SHAPES := 64                # mehr Teile -> raeumlich gruppieren
const TRIMESH_VERTS := 150            # zusammenhaengende Teile mit mehr Eckpunkten (importierte Modelle) -> Trimesh
const PROTRUDE_TOL := 0.15           # Teil gilt als "in der alten Box", wenn Punkte hoechstens so weit draussen liegen
const PROTRUDE_FAR := 0.5            # ... und nur, wenn es seitlich so weit ueber die alten Boxen hinausragt
const GROUND_SPAN := 7.0             # Optik in X UND Z breiter -> Boden-/Rampenplatte, nicht fitten
const BLOCKER_MARGIN := 0.6           # Kollision ueberragt Optik um mehr -> bewusste Sperre, nicht anfassen
const MIN_PART := 0.05                # kleinere Teile (Schrauben, Kabel) ignorieren
const BIG_MESH_VERTS := 2500          # Surfaces mit mehr Vertices -> direkt Trimesh (Ladezeit)
const HOLLOW_RATIO := 0.05           # Teilvolumen < 5 % der Bounding-Box -> hohl/ringfoermig -> Trimesh
const FLAT := 0.015                   # flache Teile (Decals, Planen) bekommen eine Mindestdicke

const DEBUG_FIT := Color(1.0, 0.45, 0.05, 0.55)    # --debug-collisions: enge Formen orange
const DEBUG_MOVE := Color(0.6, 0.6, 0.6, 0.06)    # alte Bewegungsboxen kaum sichtbar

static var _comp_cache: Dictionary = {}   # Mesh-Instanz-ID -> Array[PackedVector3Array] (Huellpunkte, Mesh-lokal)
static var stats := {"fitted": 0, "skipped_blocker": 0, "dropped_protrude": 0, "shapes": 0, "ms": 0}
static var reasons := {}

static func _no(r: String) -> bool:
	reasons[r] = int(reasons.get(r, 0)) + 1
	return false

## Alle passenden Props unterhalb von root umbauen. Gibt die Anzahl umgebauter Bodies zurueck.
static func fit_tree(root: Node) -> int:
	if Game.arg("no-propfit", false):   # Vorher/Nachher-Vergleich
		return 0
	var t0 := Time.get_ticks_msec()
	_comp_cache.clear()   # Instanz-IDs freigegebener Meshes koennen wiederverwendet werden
	stats = {"fitted": 0, "skipped_blocker": 0, "dropped_protrude": 0, "shapes": 0, "ms": 0}
	reasons.clear()
	var n := 0
	for c in root.find_children("*", "StaticBody3D", true, false):
		if fit_body(c as StaticBody3D):
			n += 1
	stats.ms = Time.get_ticks_msec() - t0
	if Game.arg("navdebug", false) or Game.arg("fitdebug", false):
		print("PROPFIT fitted=%d skipped_blocker=%d shapes=%d ms=%d %s" % [stats.fitted, stats.skipped_blocker, stats.shapes, stats.ms, str(reasons)])
	return n

static func fit_body(b: StaticBody3D) -> bool:
	if b == null or (b.collision_layer & LAYER_WORLD) == 0 or b.has_meta("no_fit") or b.has_meta("prop_fitted"):
		return false
	if b.get_parent() is StaticBody3D and b.name == "MoveBlock":
		return false
	# Bodies mit eigenem Skript (Wasserturm, Kran, Fass ...) schalten ihre Shapes selbst ab -> nicht anfassen
	if b.get_script() != null:
		return _no("scripted")
	var shapes: Array[CollisionShape3D] = []
	for c in b.get_children():
		if c is CollisionShape3D:
			var cs := c as CollisionShape3D
			if cs.shape == null or cs.disabled:
				continue
			if not (cs.shape is BoxShape3D or cs.shape is CylinderShape3D or cs.shape is SphereShape3D or cs.shape is CapsuleShape3D):
				return _no("shape_type")
			shapes.append(cs)
	if shapes.is_empty():
		return _no("no_shapes")
	var meshes := _visual_meshes(b)
	if meshes.is_empty():
		return _no("no_meshes")
	var inv := b.global_transform.affine_inverse()
	var shape_box := AABB()
	for i in shapes.size():
		var a := (inv * shapes[i].global_transform) * shapes[i].shape.get_debug_mesh().get_aabb()
		shape_box = a if i == 0 else shape_box.merge(a)
	if shape_box.size.x > MAX_EXTENT or shape_box.size.y > MAX_EXTENT or shape_box.size.z > MAX_EXTENT:
		return _no("too_big")

	# Huellpunkte / Trimeshes aller sichtbaren Teile im Body-Raum
	var parts: Array[PackedVector3Array] = []
	var trimeshes: Array = []   # [Shape, Transform im Body-Raum]
	var vis_box := AABB()
	var first := true
	for mi in meshes:
		var xf := inv * mi.global_transform
		for comp_v: Variant in _components(mi.mesh):
			if comp_v is Dictionary:
				# Trimesh: Shape einmal pro Mesh (Mesh-Raum) bauen und per Transform wiederverwenden
				var d := comp_v as Dictionary
				var src: PackedVector3Array = d.faces
				var fa: AABB = xf * _aabb(src)
				var sc := xf.basis.get_scale()
				if xf.basis.is_conformal() and absf(sc.x - sc.y) < 0.001 and absf(sc.x - sc.z) < 0.001:
					if not d.has("shape"):
						var shp := ConcavePolygonShape3D.new()
						shp.backface_collision = true
						shp.set_faces(src)
						d["shape"] = shp
					trimeshes.append([d.shape, xf])
				else:
					var f := PackedVector3Array()
					f.resize(src.size())
					for k in src.size():
						f[k] = xf * src[k]
					var shp2 := ConcavePolygonShape3D.new()
					shp2.backface_collision = true
					shp2.set_faces(f)
					trimeshes.append([shp2, Transform3D.IDENTITY])
				vis_box = fa if first else vis_box.merge(fa)
				first = false
				continue
			var comp: PackedVector3Array = comp_v
			var pts := PackedVector3Array()
			pts.resize(comp.size())
			for k in comp.size():
				pts[k] = xf * comp[k]
			var pa := _aabb(pts)
			if pa.get_longest_axis_size() < MIN_PART:
				continue
			parts.append(pts)
			vis_box = pa if first else vis_box.merge(pa)
			first = false
	if parts.is_empty() and trimeshes.is_empty():
		return _no("no_parts")
	# Boden-/Ufer-/Rampenplatten (in beiden Richtungen breit oder tief im Boden): keine Deckung, Huellen wuerden Mulden fuellen
	if (vis_box.size.x > GROUND_SPAN and vis_box.size.z > GROUND_SPAN) or vis_box.position.y < -1.0:
		return _no("ground_like")
	# Bewusste Sperre? (Kollision viel hoeher/breiter als alles Sichtbare)
	var sb_end := shape_box.end
	var vb_end := vis_box.end
	if sb_end.y > vb_end.y + BLOCKER_MARGIN or shape_box.position.x < vis_box.position.x - BLOCKER_MARGIN \
			or sb_end.x > vb_end.x + BLOCKER_MARGIN or shape_box.position.z < vis_box.position.z - BLOCKER_MARGIN \
			or sb_end.z > vb_end.z + BLOCKER_MARGIN:
		stats.skipped_blocker += 1
		if Game.arg("fitdebug", false): print("PROPFIT blocker %s @ %s shape=%s vis=%s" % [b.name, str(b.global_position), str(shape_box), str(vis_box)])
		return false

	# Teile, die ueberwiegend ausserhalb der alten Boxen liegen (Kanonenrohr, Spiegel, Antennen), bekommen wie
	# bisher keine Kollision: sonst blockieren sie Wege, die Navmesh/Autopilot/Level-Design als frei kennen.
	var olds: Array = []   # [Transform Body->Shape, AABB im Shape-Raum]
	for cs in shapes:
		olds.append([(inv * cs.global_transform).affine_inverse(), cs.shape.get_debug_mesh().get_aabb().grow(PROTRUDE_TOL)])
	var kept: Array[PackedVector3Array] = []
	for pts in parts:
		var inside := 0
		for p in pts:
			for o: Array in olds:
				if (o[1] as AABB).has_point((o[0] as Transform3D) * p):
					inside += 1
					break
		var pa := _aabb(pts)
		var lateral := pa.position.x < shape_box.position.x - PROTRUDE_FAR or pa.end.x > shape_box.end.x + PROTRUDE_FAR 				or pa.position.z < shape_box.position.z - PROTRUDE_FAR or pa.end.z > shape_box.end.z + PROTRUDE_FAR
		if inside * 4 >= pts.size() * 3 or not lateral:
			kept.append(pts)
		else:
			stats.dropped_protrude += 1
	parts = kept
	if parts.is_empty() and trimeshes.is_empty():
		return _no("all_protrude")
	var groups := _group(parts)
	# alte Boxen -> MoveBlock (nur Bewegung)
	var mb := StaticBody3D.new()
	mb.name = "MoveBlock"
	mb.collision_layer = LAYER_MOVE_BLOCK
	mb.collision_mask = 0
	for cs in shapes:
		b.remove_child(cs)
		cs.debug_color = DEBUG_MOVE   # nur fuer --debug-collisions
		cs.debug_fill = false
		mb.add_child(cs)
	b.add_child(mb)
	for g: PackedVector3Array in groups:
		var cps := ConvexPolygonShape3D.new()
		cps.points = g
		var cs := CollisionShape3D.new()
		cs.shape = cps
		cs.name = "FitHull"
		cs.debug_color = DEBUG_FIT
		b.add_child(cs)
		stats.shapes += 1
	for tm: Array in trimeshes:
		var cs := CollisionShape3D.new()
		cs.shape = tm[0]
		cs.transform = tm[1]
		cs.name = "FitMesh"
		cs.debug_color = DEBUG_FIT
		b.add_child(cs)
		stats.shapes += 1
	b.set_meta("prop_fitted", true)
	stats.fitted += 1
	return true

# ------------------------------------------------------------------ intern

static func _visual_meshes(b: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.visible:
			continue
		var par := mi.get_parent()
		var nested := false
		while par != null and par != b:
			if par is CollisionObject3D or (par is Node3D and not (par as Node3D).visible):
				nested = true
				break
			par = par.get_parent()
		if not nested:
			out.append(mi)
	return out

static func _aabb(pts: PackedVector3Array) -> AABB:
	var a := AABB(pts[0], Vector3.ZERO)
	for p in pts:
		a = a.expand(p)
	return a

## Zusammenhaengende Teile eines Meshes (gemeinsame Eckpunkte), je als konvexe Huellpunkte (Mesh-lokal).
static func _components(mesh: Mesh) -> Array:
	var key := mesh.get_instance_id()
	if _comp_cache.has(key):
		return _comp_cache[key]
	var out: Array = []
	for s in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		if verts.is_empty():
			continue
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if verts.size() > BIG_MESH_VERTS:
			# detailreiches Modell: Komponentenanalyse waere teuer und meist ohnehin ein Teil -> direkt Trimesh
			var bf := PackedVector3Array()
			if idx.size() > 0:
				bf.resize(idx.size())
				for t in idx.size():
					bf[t] = verts[idx[t]]
			else:
				bf = verts
			out.append({"faces": bf})
			continue
		# gleiche Positionen zusammenfassen (1 mm)
		var pos_id := {}
		var vid := PackedInt32Array()
		vid.resize(verts.size())
		var uniq := PackedVector3Array()
		for i in verts.size():
			var v := verts[i]
			var k := Vector3i(roundi(v.x * 1000.0), roundi(v.y * 1000.0), roundi(v.z * 1000.0))
			var id: int = pos_id.get(k, -1)
			if id < 0:
				id = uniq.size()
				pos_id[k] = id
				uniq.append(v)
			vid[i] = id
		var parent := PackedInt32Array()
		parent.resize(uniq.size())
		for i in uniq.size():
			parent[i] = i
		var tri_count := (idx.size() if idx.size() > 0 else verts.size()) / 3
		for t in tri_count:
			var a := vid[idx[t * 3] if idx.size() > 0 else t * 3]
			for j in [1, 2]:
				var c := vid[idx[t * 3 + j] if idx.size() > 0 else t * 3 + j]
				var ra := _find(parent, a)
				var rc := _find(parent, c)
				if ra != rc:
					parent[rc] = ra
		var groups := {}
		for i in uniq.size():
			var r := _find(parent, i)
			if not groups.has(r):
				groups[r] = []
			(groups[r] as Array).append(uniq[i])
		# ein grosses, zusammenhaengendes (meist konkaves) Teil (importiertes Modell) -> exaktes Trimesh
		var big := false
		for r in groups:
			if (groups[r] as Array).size() >= TRIMESH_VERTS:
				big = true
				break
		if big:
			var faces := PackedVector3Array()
			var ntri := (idx.size() if idx.size() > 0 else verts.size()) / 3
			faces.resize(ntri * 3)
			for t in ntri * 3:
				faces[t] = verts[idx[t] if idx.size() > 0 else t]
			out.append({"faces": faces})
			continue
		# Volumen je Teil (Divergenzsatz) -> hohle/ringfoermige Teile (Stacheldraht-Rollen, Rahmen) sind
		# als konvexe Huelle viel zu voll: diese Teile bekommen ein exaktes Trimesh.
		var vol := {}
		var tri_faces := {}
		for t in tri_count:
			var i0: int = idx[t * 3] if idx.size() > 0 else t * 3
			var i1: int = idx[t * 3 + 1] if idx.size() > 0 else t * 3 + 1
			var i2: int = idx[t * 3 + 2] if idx.size() > 0 else t * 3 + 2
			var r := _find(parent, vid[i0])
			vol[r] = float(vol.get(r, 0.0)) + verts[i0].dot(verts[i1].cross(verts[i2])) / 6.0
			if not tri_faces.has(r):
				tri_faces[r] = []
			(tri_faces[r] as Array).append_array([verts[i0], verts[i1], verts[i2]])
		var hollow := PackedVector3Array()
		for r in groups:
			var pts := PackedVector3Array(groups[r])
			if pts.size() < 4:
				continue
			var ab := _aabb(pts)
			var box_vol := maxf(ab.size.x, FLAT) * maxf(ab.size.y, FLAT) * maxf(ab.size.z, FLAT)
			if absf(float(vol.get(r, 0.0))) < HOLLOW_RATIO * box_vol and ab.get_longest_axis_size() > 0.3:
				hollow.append_array(PackedVector3Array(tri_faces.get(r, [])))
				continue
			out.append(_hull(pts))
		if not hollow.is_empty():
			out.append({"faces": hollow})
	_comp_cache[key] = out
	return out

static func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i

## Konvexe Huelle (nur die Huell-Eckpunkte), flache Teile bekommen Mindestdicke.
static func _hull(pts: PackedVector3Array) -> PackedVector3Array:
	var a := _aabb(pts)
	var src := pts
	# flach? -> in der duennen Achse auf Mindestdicke aufdicken (sonst entartete Huelle)
	var sz := a.size
	var thin := -1
	if sz.x < FLAT: thin = 0
	elif sz.y < FLAT: thin = 1
	elif sz.z < FLAT: thin = 2
	if thin >= 0:
		src = PackedVector3Array()
		var off := Vector3.ZERO
		off[thin] = FLAT * 0.5
		for p in pts:
			src.append(p + off)
			src.append(p - off)
	if src.size() <= 24:
		return src
	var tri := src.duplicate()
	while tri.size() % 3 != 0:
		tri.append(tri[tri.size() - 1])
	var am := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = tri
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var cs := am.create_convex_shape(true, tri.size() > 600)
	if cs == null or cs.points.size() < 4:
		return src
	return cs.points

## Teile raeumlich gruppieren, bis hoechstens MAX_SHAPES Huellen entstehen.
static func _group(parts: Array[PackedVector3Array]) -> Array:
	if parts.size() <= MAX_SHAPES:
		return parts
	var cell := 0.4
	while true:
		var buckets := {}
		for p in parts:
			var c := _aabb(p).get_center()
			var k := Vector3i(floori(c.x / cell), floori(c.y / cell), floori(c.z / cell))
			if not buckets.has(k):
				buckets[k] = []
			(buckets[k] as Array).append(p)
		if buckets.size() <= MAX_SHAPES or cell > 8.0:
			var out: Array = []
			for k in buckets:
				var all := PackedVector3Array()
				for p: PackedVector3Array in buckets[k]:
					all.append_array(p)
				out.append(_hull(all))
			return out
		cell *= 1.5
	return parts
