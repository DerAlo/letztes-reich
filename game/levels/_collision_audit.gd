extends Node3D
## Kollisions-Audit: vergleicht die Kollisionsformen aller Deckungs-Props (StaticBody3D auf Layer 1 mit
## sichtbaren Meshes, max. 20 m gross) mit ihrer sichtbaren Geometrie.
## Pro Prop werden Kollision und Optik (Trimesh aus den Mesh-Flaechen) in eine eigene, isolierte Welt
## kopiert und mit ~fast horizontalen Strahlen (Pitch +-25 Grad, wie Schuesse) beschossen:
##   ghost = Strahl trifft die Kollision, aber die Optik erst >12 cm spaeter oder gar nicht
##           ("Kugel bleibt in unsichtbarer Box haengen")
##   leak  = Strahl trifft die Optik, die Kollision aber erst spaeter oder gar nicht (Kugel geht durch)
## Start: godot --headless --path . res://game/levels/_collision_audit.tscn -- --level=test_range [--rays=300] [--top=25]

const TOL := 0.12

var _vp: SubViewport
var _root: Node3D

func _ready() -> void:
	var lname := str(Game.arg("level", "test_range"))
	var rays := int(Game.arg("rays", 300))
	var top := int(Game.arg("top", 25))
	var level := (load("res://game/levels/%s.tscn" % lname) as PackedScene).instantiate()
	level.set("spawn_player", false)
	level.set("spawn_enemies", false)
	level.set("ambient_artillery", false)
	add_child(level)
	var t0 := Time.get_ticks_msec()
	while level.has_method("is_level_ready") and not level.call("is_level_ready") and Time.get_ticks_msec() - t0 < 30000:
		await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(4, 4)
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_root = Node3D.new()
	_vp.add_child(_root)

	var props: Array = []
	for n in level.find_children("*", "StaticBody3D", true, false):
		var b := n as StaticBody3D
		if (b.collision_layer & 1) == 0:
			continue
		var meshes := _meshes_of(b)
		if meshes.is_empty():
			continue
		var shapes := _shapes_of(b)
		if shapes.is_empty():
			continue
		var aabb := _shape_aabb(b, shapes)
		if aabb.size.x > 20.0 or aabb.size.y > 20.0 or aabb.size.z > 20.0:
			continue
		props.append({"body": b, "meshes": meshes, "shapes": shapes, "aabb": aabb})
	print("AUDIT level=%s props=%d" % [lname, props.size()])

	# Kopien in die isolierte Welt, jeweils 60 m versetzt
	var idx := 0
	for p in props:
		var b: StaticBody3D = p.body
		var off := Transform3D(Basis.IDENTITY, Vector3(idx * 60.0, 0, 0))
		var col := StaticBody3D.new()
		col.collision_layer = 1
		col.collision_mask = 0
		col.transform = off
		for s in p.shapes:
			var cs := CollisionShape3D.new()
			cs.shape = (s as CollisionShape3D).shape
			cs.transform = b.global_transform.affine_inverse() * (s as CollisionShape3D).global_transform
			col.add_child(cs)
		_root.add_child(col)
		var vis := StaticBody3D.new()
		vis.collision_layer = 2
		vis.collision_mask = 0
		vis.transform = off
		var faces := PackedVector3Array()
		for mi: MeshInstance3D in p.meshes:
			var xf := b.global_transform.affine_inverse() * mi.global_transform
			var f := mi.mesh.get_faces()
			for v in f:
				faces.append(xf * v)
		var cps := ConcavePolygonShape3D.new()
		cps.backface_collision = true
		cps.set_faces(faces)
		var vcs := CollisionShape3D.new()
		vcs.shape = cps
		vis.add_child(vcs)
		_root.add_child(vis)
		p["col"] = col
		p["vis"] = vis
		p["off"] = off
		idx += 1
	for i in 4:
		await get_tree().physics_frame

	var space := _root.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var results: Array = []
	var tot_hits := 0
	var tot_ghost := 0
	var tot_leak := 0
	for p in props:
		var b: StaticBody3D = p.body
		var local_aabb: AABB = p.aabb  # im Body-Raum
		var off: Transform3D = p.off
		var hits := 0
		var ghost := 0
		var leak := 0
		var vhits := 0
		var ghost_pts: Array = []
		for r in rays:
			var target := local_aabb.position + Vector3(rng.randf(), rng.randf(), rng.randf()) * local_aabb.size
			var yaw := rng.randf() * TAU
			var pitch := deg_to_rad(rng.randf_range(-25.0, 25.0))
			var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
			var from := off * (target - dir * 25.0)
			var to := off * (target + dir * 25.0)
			var qa := PhysicsRayQueryParameters3D.create(from, to, 1)
			var qb := PhysicsRayQueryParameters3D.create(from, to, 2)
			qb.hit_back_faces = true
			var ra := space.intersect_ray(qa)
			var rb := space.intersect_ray(qb)
			var da := INF
			var db := INF
			if not ra.is_empty():
				da = from.distance_to(ra.position)
			if not rb.is_empty():
				db = from.distance_to(rb.position)
			if da < INF:
				hits += 1
				if db > da + TOL:
					ghost += 1
					if ghost_pts.size() < 3:
						ghost_pts.append(off.affine_inverse() * (ra.position as Vector3))
			if db < INF:
				vhits += 1
				if da > db + TOL:
					leak += 1
		tot_hits += hits
		tot_ghost += ghost
		tot_leak += leak
		var gp := 100.0 * ghost / maxf(hits, 1)
		var lp := 100.0 * leak / maxf(vhits, 1)
		results.append({"name": _label(b), "pos": b.global_position, "ghost": gp, "leak": lp, "hits": hits, "pts": ghost_pts})
	results.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a.ghost > c.ghost)
	for i in mini(top, results.size()):
		var r: Dictionary = results[i]
		var pos: Vector3 = r.pos
		print("AUDIT ghost=%5.1f%% leak=%5.1f%% hits=%d  %s @ (%.1f, %.1f, %.1f) z.B. lokal %s" % [r.ghost, r.leak, r.hits, r.name, pos.x, pos.y, pos.z, str(r.pts)])
	print("AUDIT summary level=%s props=%d ghost=%.1f%% leak=%.1f%% (über alle Strahlen)" % [lname, props.size(), 100.0 * tot_ghost / maxf(tot_hits, 1), 100.0 * tot_leak / maxf(tot_hits, 1)])
	get_tree().quit()

func _meshes_of(b: Node) -> Array:
	var out: Array = []
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		# eigene Unter-Bodies (z. B. Rigid-Truemmer) nicht mitzaehlen
		var par := mi.get_parent()
		var nested := false
		while par != null and par != b:
			if par is CollisionObject3D:
				nested = true
				break
			par = par.get_parent()
		if not nested:
			out.append(mi)
	return out

func _shapes_of(b: Node) -> Array:
	var out: Array = []
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null and not (c as CollisionShape3D).disabled:
			out.append(c)
	return out

func _shape_aabb(b: StaticBody3D, shapes: Array) -> AABB:
	var inv := b.global_transform.affine_inverse()
	var res := AABB()
	var first := true
	for s in shapes:
		var cs := s as CollisionShape3D
		var dm := cs.shape.get_debug_mesh()
		var a: AABB = (inv * cs.global_transform) * dm.get_aabb()
		if first:
			res = a
			first = false
		else:
			res = res.merge(a)
	return res.grow(0.05)

func _label(b: Node) -> String:
	var s := str(b.name)
	for mi: MeshInstance3D in _meshes_of(b):
		var rp := mi.mesh.resource_path
		if rp != "":
			return s + " [" + rp.get_file() + "]"
		var own := mi.owner
		if own != null and own.scene_file_path != "":
			return s + " [" + own.scene_file_path.get_file() + "]"
	return s
