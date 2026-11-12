extends Node3D
## Debug: Viewmodel mit Armen ohne Level rendern (Ego-, Seiten-, Draufsicht).
## godot --path . res://game/weapons/_arms_debug.tscn -- --w=pistol --out=captures/fp_arms/dbg [--ads=1] [--t=0.5 Nachladen]
var _out: String

func _ready() -> void:
	_out = str(Game.arg("out", "captures/fp_arms/dbg"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://").path_join(_out))
	get_window().size = Vector2i(1200, 800)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.38, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.5)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_cull_mask = 0xFFFFFFFF
	add_child(sun)
	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFFFFF
	cam.near = 0.01
	add_child(cam)
	cam.current = true
	for id in str(Game.arg("w", "pistol")).split(","):
		var w: Weapon = WeaponDefs.instantiate(id)
		add_child(w)
		w.set_active(true)
		if not w._mag_part.is_empty():
			print("MAG c=", w._mag_part.c, " down=", w._mag_part.down)
			for mi: MeshInstance3D in w._collect_meshes(w._mag_part.node):
				print("MAG aabb ", w._rel(mi, w._pivot) * mi.mesh.get_aabb())
		var all := AABB()
		for mi: MeshInstance3D in w._collect_meshes(w._pivot):
			if mi.get_parent() != null and not (mi is GeometryInstance3D and mi.get_parent().name == "Arms"):
				all = all.merge(w._rel(mi, w._pivot) * mi.mesh.get_aabb()) if all.size != Vector3.ZERO else w._rel(mi, w._pivot) * mi.mesh.get_aabb()
		print("GUN aabb ", all)
		if str(Game.arg("probe", "")) != "":
			for mi: MeshInstance3D in w._collect_meshes(w._pivot):
				if mi.get_parent().name != "Skeleton":
					print("PART ", mi.name, " ", w._rel(mi, w._pivot) * mi.mesh.get_aabb())
					if mi.name.begins_with("base") or mi.name.begins_with("slid"):
						_sight_scan(mi, w._rel(mi, w._pivot))
		for ads in [0.0, 1.0]:
			for i in 30:
				w.animate(1.0 / 60.0, {"ads": ads})
			await _views(cam, w, "%s_%s" % [id, "ads" if ads > 0.5 else "hip"], ads)
			if str(Game.arg("probe", "")) != "":
				_probe(w)
			if str(Game.arg("thumb", "")) != "":
				_thumb_fix(w, str_to_var("Vector3(%s)" % Game.arg("thumb", "")))
		var rt: String = str(Game.arg("t", ""))
		if rt != "":
			w.ammo_mag = 0
			w.start_reload()
			for t in rt.split(","):
				while w._reload_t < float(t):
					w.tick(1.0 / 60.0)
					w.animate(1.0 / 60.0, {"ads": 0.0})
				await _views(cam, w, "%s_rl%s" % [id, t], 0.0)
		w.queue_free()
	print("DBG_DONE")
	get_tree().quit()

func _views(cam: Camera3D, w: Weapon, name: String, ads: float) -> void:
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 52.0
	cam.transform = Transform3D.IDENTITY
	await _shot(name + "_fp")
	var pv: Transform3D = w._pivot.transform
	var c: Vector3 = pv * Vector3(0, -0.02, 0.0)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(Game.arg("zoom", "0.32"))
	cam.look_at_from_position(c + pv.basis.x * -1.0, c, pv.basis.y)
	await _shot(name + "_left")
	cam.look_at_from_position(c + pv.basis.x * 1.0, c, pv.basis.y)
	await _shot(name + "_top")
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 40.0
	cam.look_at_from_position(c + pv.basis * Vector3(0.12, -0.03, -0.4), c, Vector3.UP)
	await _shot(name + "_front")

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(600, 400, Image.INTERPOLATE_LANCZOS)
	img.save_png(ProjectSettings.globalize_path("res://").path_join(_out).path_join(name + ".png"))

func _probe(w: Weapon) -> void:
	var a: FpArms = w._arms
	var inv: Transform3D = w._pivot.transform.affine_inverse() * a.global_transform.affine_inverse() * a.sk.global_transform
	for sd: String in ["L", "R"]:
		print("ELBOW ", sd, " ", inv * a.sk.get_bone_global_pose(a._b[sd].fore).origin, " cam ", a.transform * a.sk.transform * a.sk.get_bone_global_pose(a._b[sd].fore).origin)
	for i in a.sk.get_bone_count():
		var n: String = a.sk.get_bone_name(i)
		if n.begins_with("Bone_") or n.begins_with("Hand_") or n.begins_with("BoneTwist_01") or n.begins_with("Forearm_") or n.begins_with("UpArm_"):
			print("BONE ", n, " ", inv * a.sk.get_bone_global_pose(i).origin)

## Daumen-Korrektur berechnen: Stützhand-Daumen (L.020..022_end) auf Ziel (Pivotraum) ausrichten -> Euler (Grad) für support_thumb_rot
func _thumb_fix(w: Weapon, target: Vector3) -> void:
	var a: FpArms = w._arms
	var sk: Skeleton3D = a.sk
	var to_piv: Transform3D = w._pivot.transform.affine_inverse() * a.global_transform.affine_inverse() * sk.global_transform
	var b: int = -1
	var e: int = -1
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).begins_with("Bone_L.020"):
			b = i
		if sk.get_bone_name(i).begins_with("Bone_L.022_end"):
			e = i
	var g: Transform3D = sk.get_bone_global_pose(b)
	var v: Vector3 = sk.get_bone_global_pose(e).origin - g.origin
	var d: Vector3 = to_piv.affine_inverse() * target - g.origin
	var r := Basis(Quaternion(v.normalized(), d.normalized()))
	var pg: Basis = sk.get_bone_global_pose(sk.get_bone_parent(b)).basis
	var loc_old: Basis = sk.get_bone_pose_rotation(b)
	var loc_new: Basis = pg.inverse() * r * g.basis
	var delta: Quaternion = (Basis(loc_old).orthonormalized().inverse() * loc_new.orthonormalized()).get_rotation_quaternion()
	print("THUMBFIX ", delta.get_euler() * (180.0 / PI), " len v=", v.length(), " d=", d.length())

## Höchste Punkte vorn/hinten (Korn/Kimme) eines Meshes im Pivotraum, je 1-cm-z-Scheibe
func _sight_scan(mi: MeshInstance3D, xf: Transform3D) -> void:
	var top: Dictionary = {}
	for si in mi.mesh.get_surface_count():
		var v: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for p: Vector3 in v:
			var q: Vector3 = xf * p
			var k: int = floori(q.z * 200.0)
			if not top.has(k) or q.y > (top[k] as Vector3).y:
				top[k] = q
	var ks: Array = top.keys()
	ks.sort()
	for k: int in ks:
		print("TOP ", mi.name, " ", top[k])
