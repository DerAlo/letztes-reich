extends SceneTree
## Debug: gibt Ruhepose-Infos der Skelette aus. Aufruf:
## godot --headless --path . -s res://game/enemies/tools/inspect_rigs.gd

func _load(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(path), st)
	if err != OK:
		push_error("load fail %s" % path)
		return null
	return doc.generate_scene(st)

func _find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skel(c)
		if s:
			return s
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var s := _find_ap(c)
		if s:
			return s
	return null

func _init() -> void:
	for p in ["res://assets/characters/soldier/swat.glb", "res://assets/characters/anim_src/ual_standard.glb"]:
		var sc := _load(p)
		root.add_child(sc)
		var sk := _find_skel(sc)
		print("== ", p, " skel path=", sc.get_path_to(sk), " bones=", sk.get_bone_count(), " skel global xform=", sk.global_transform)
		var tree := ""
		_print_tree(sc, 0)
		for i in sk.get_bone_count():
			var g := sk.get_bone_global_rest(i)
			var nm := sk.get_bone_name(i)
			if nm.contains("1.") or nm.contains("2.") or nm.contains("3.") or nm.contains("4.") or nm.contains("f_") or nm.contains("thumb"):
				continue
			print("  %-18s par=%-14s pos=(%.3f,%.3f,%.3f) y=(%.2f,%.2f,%.2f) z=(%.2f,%.2f,%.2f)" % [nm, sk.get_bone_name(sk.get_bone_parent(i)) if sk.get_bone_parent(i) >= 0 else "-", g.origin.x, g.origin.y, g.origin.z, g.basis.y.x, g.basis.y.y, g.basis.y.z, g.basis.z.x, g.basis.z.y, g.basis.z.z])
		var ap := _find_ap(sc)
		if ap:
			for a in ap.get_animation_list():
				var an := ap.get_animation(a)
				print("  anim %-28s len=%.2f loop=%d tracks=%d" % [a, an.length, an.loop_mode, an.get_track_count()])
			var an0 := ap.get_animation(ap.get_animation_list()[0])
			for t in mini(4, an0.get_track_count()):
				print("   track ", an0.track_get_path(t), " type ", an0.track_get_type(t))
	quit()

func _print_tree(n: Node, d: int) -> void:
	if d > 4:
		return
	print("  ".repeat(d + 1), n.name, " <", n.get_class(), "> ", (n as Node3D).transform if n is Node3D and d < 3 else "")
	for c in n.get_children():
		if c is Skeleton3D:
			print("  ".repeat(d + 2), c.name, " <Skeleton3D> children:", c.get_child_count(), " ", (c as Node3D).transform)
			for m in c.get_children():
				print("  ".repeat(d + 3), m.name, " <", m.get_class(), ">")
		else:
			_print_tree(c, d + 1)
