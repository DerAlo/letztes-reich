extends SceneTree
# Hilfsskript: misst Ruhepose-Landmarken der MH-Soldaten (Knochen + Rumpfquerschnitte).
func _init() -> void:
	for v in ["a", "b", "c"]:
		var sc := (load("res://assets/characters/soldier_mh/soldier_mh_%s.scn" % v) as PackedScene).instantiate()
		var sk := sc.get_node("Skeleton3D") as Skeleton3D
		var s := "[%s] " % v
		for b in ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R", "UpperLeg.R", "Foot.R"]:
			var t := sk.get_bone_global_rest(sk.find_bone(b))
			s += "%s=%s  " % [b, t.origin.snapped(Vector3.ONE * 0.001)]
		print(s)
		var tb := sk.get_bone_global_rest(sk.find_bone("Head")).basis
		print("  Head basis y=", tb.y.snapped(Vector3.ONE*0.01), " z=", tb.z.snapped(Vector3.ONE*0.01))
		var tc := sk.get_bone_global_rest(sk.find_bone("Chest")).basis
		print("  Chest basis y=", tc.y.snapped(Vector3.ONE*0.01), " z=", tc.z.snapped(Vector3.ONE*0.01))
		var tu := sk.get_bone_global_rest(sk.find_bone("UpperArm.L")).basis
		print("  UpperArm.L basis x=", tu.x.snapped(Vector3.ONE*0.01), " y=", tu.y.snapped(Vector3.ONE*0.01), " z=", tu.z.snapped(Vector3.ONE*0.01), " len=", (sk.get_bone_global_rest(sk.find_bone("LowerArm.L")).origin - sk.get_bone_global_rest(sk.find_bone("UpperArm.L")).origin).length())
		for c in sk.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				print("  mesh ", mi.name, " surfaces=", mi.mesh.get_surface_count(), " aabb=", mi.mesh.get_aabb())
				for si in mi.mesh.get_surface_count():
					var a := mi.mesh.surface_get_arrays(si)
					var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
					var mat := mi.mesh.surface_get_material(si)
					var mn := Vector3.INF; var mx := -Vector3.INF
					for p in vs:
						mn = mn.min(p); mx = mx.max(p)
					print("    surf ", si, " ", mat.resource_name if mat else "-", " n=", vs.size(), " min=", mn.snapped(Vector3.ONE*0.001), " max=", mx.snapped(Vector3.ONE*0.001))
					if mat and mat.resource_name == "Uniform":
						for y in [0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25, 1.3, 1.35, 1.4, 1.45]:
							var fz := -9.0; var bz := 9.0; var wx := 0.0
							for p in vs:
								if absf(p.y - y) < 0.012:
									if absf(p.x) < 0.04:
										fz = maxf(fz, p.z); bz = minf(bz, p.z)
									if absf(p.z) < 0.1 and p.y > 0.0:
										wx = maxf(wx, absf(p.x)) if absf(p.x) < 0.22 else wx
							print("      y=%.2f front=%.3f back=%.3f halfw=%.3f" % [y, fz, bz, wx])
					if mat and (mat.resource_name == "Helmet" or mat.resource_name.begins_with("Skin")):
						pass
		sc.free()
	quit()
