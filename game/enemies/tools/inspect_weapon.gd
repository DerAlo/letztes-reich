extends SceneTree
## Debug: gibt AABB/Transforms von Waffenmodellen aus.
func _walk(n: Node, xf: Transform3D, d: int) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	var extra := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var ab := t * mi.mesh.get_aabb()
		extra = " AABB pos=%s size=%s surf=%d" % [ab.position, ab.size, mi.mesh.get_surface_count()]
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			extra += " [%s]" % (m.resource_name if m else "-")
	print("  ".repeat(d), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		_walk(c, t, d + 1)
func _init() -> void:
	for p in ["res://assets/characters/weapons/rifle_ar_quaternius.glb", "res://assets/characters/weapons/rifle_ar_west.glb"]:
		print("== ", p)
		_walk((load(p) as PackedScene).instantiate(), Transform3D.IDENTITY, 0)
	quit()
