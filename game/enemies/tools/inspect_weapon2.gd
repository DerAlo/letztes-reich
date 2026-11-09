extends SceneTree
## Debug: Knochen der West-Waffe + Vertex-Schwerpunkt Quaternius-Waffe entlang X.
func _init() -> void:
	var sc := (load("res://assets/characters/weapons/rifle_ar_west.glb") as PackedScene).instantiate()
	var rig := sc.get_node("RootNode/Rifle_Assault_West_Rig") as Node3D
	var sk := rig.get_node("Skeleton3D") as Skeleton3D
	print("rig xf ", rig.transform)
	for nm in ["Attach_Muzzle", "Stock", "Magazine", "Trigger", "Attach_Rail_Bottom", "Front Sights", "Rear Sights"]:
		var b := sk.find_bone(nm)
		print(nm, " ", rig.transform * sk.get_bone_global_rest(b).origin)
	var q := (load("res://assets/characters/weapons/rifle_ar_quaternius.glb") as PackedScene).instantiate()
	var mi := q.get_node("RootNode/AssaultRifle2_1") as MeshInstance3D
	print("q xf ", mi.transform, " parent ", (mi.get_parent() as Node3D).transform)
	var arr := mi.mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bins := {}
	for p0 in v:
		var p := mi.transform * p0
		var k := int(floor(p.x * 2.0))
		if not bins.has(k):
			bins[k] = [999.0, -999.0]
		bins[k][0] = minf(bins[k][0], p.y)
		bins[k][1] = maxf(bins[k][1], p.y)
	var ks := bins.keys()
	ks.sort()
	for k in ks:
		print("x=%.1f y[%.2f..%.2f]" % [k * 0.5, bins[k][0], bins[k][1]])
	quit()
