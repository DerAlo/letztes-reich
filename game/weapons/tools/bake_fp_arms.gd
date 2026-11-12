extends SceneTree
## Offline-Bake der Erste-Person-Arme (headless):
##   1) fps_ak-74m_animations.zip (Projektwurzel) entpacken, Bildverweise aus scene.gltf entfernen
##      (Texturen liegen bereits als 2048er JPG in assets/characters/fp_arms/tex/)
##   2) godot --headless --path . -s res://game/weapons/tools/bake_fp_arms.gd -- --src=<.../scene.gltf>
## Modell: "FPS AK-74m animations" von Cransh (https://sketchfab.com/ccransh), CC BY 4.0,
##   https://sketchfab.com/3d-models/fps-ak-74m-animations-94be8385c402474cacd39bc096c6ca14
## Nur die Arme (Ärmel + Handschuhe) samt Skelett; die AK-Meshes fliegen raus (die Waffe kommt aus ak74m.glb).
## Die Pose ist Bild 0 von "AK_Idle" (Griffhaltung der Finger). Das Ergebnis liegt im Kameraraum
## (Meter, -Z vorn, +X rechts, Ursprung = Auge) -> game/weapons/fp_arms.gd stellt Hände per IK an die Waffe.
## Ergebnis: assets/characters/fp_arms/fp_arms.scn (FpArms/Skeleton/Arms)

const OUT := "res://assets/characters/fp_arms/fp_arms.scn"
const TEX := "res://assets/characters/fp_arms/tex/"
## Rig-Einheiten -> Meter: Handgelenk-Knöchel ~0,093 m (Handschuh)
const SCALE := 0.30

func _init() -> void:
	var src: String = ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			src = a.substr(6)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(src, st) != OK:
		push_error("gltf laden fehlgeschlagen: " + src)
		quit(1)
		return
	var root: Node = doc.generate_scene(st)
	var ap: AnimationPlayer = root.find_children("*", "AnimationPlayer", true, false)[0]
	ap.play("Rig|AK_Idle")
	ap.seek(0.0, true)
	ap.advance(0.0)
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var sk_rel: Transform3D = _rel(sk, root)
	# Ursprung = Sketchfab-Kamera (Auge), sonst Head_Cam-Knochen
	var hc: Vector3 = (sk_rel * sk.get_bone_global_pose(sk.find_bone("Head_Cam_014"))).origin
	var cam_node: Node = root.find_child("Camera", true, false)
	if cam_node is Node3D:
		hc = _rel(cam_node, root).origin
	print("eye ", hc)
	var conv := Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * SCALE), Vector3.ZERO) * Transform3D(Basis(), -hc)
	# Pose einfrieren (Animation weg), AK-Meshes entfernen
	var arms_mi: MeshInstance3D = null
	for mi: MeshInstance3D in sk.find_children("*", "MeshInstance3D", false, false):
		if mi.mesh.get_aabb().size.x > 0.3:
			arms_mi = mi
	var poses: Array = []
	for i in sk.get_bone_count():
		poses.append([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i), sk.get_bone_pose_scale(i)])
	ap.stop()
	for c in sk.get_children():
		sk.remove_child(c)
		if c != arms_mi:
			c.free()
	sk.get_parent().remove_child(sk)
	for i in sk.get_bone_count():
		sk.set_bone_pose_position(i, poses[i][0])
		sk.set_bone_pose_rotation(i, poses[i][1])
		sk.set_bone_pose_scale(i, poses[i][2])
	var out := Node3D.new()
	out.name = "FpArms"
	sk.name = "Skeleton"
	sk.transform = conv * sk_rel
	out.add_child(sk)
	sk.owner = out
	arms_mi.name = "Arms"
	sk.add_child(arms_mi)
	arms_mi.owner = out
	arms_mi.transform = Transform3D.IDENTITY
	arms_mi.skeleton = NodePath("..")
	arms_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + "arms_albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load(TEX + "arms_normal.jpg")
	m.roughness_texture = load(TEX + "arms_rough.jpg")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.roughness = 1.0
	m.metallic = 0.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	arms_mi.material_override = m
	# Ellbogen-Polziele (Kameraraum) aus dem Rig
	for side in ["L", "R"]:
		var pi: int = sk.find_bone("IK_PoleTrgt_%s_0%s" % [side, "0" if side == "L" else "57"])
		if pi >= 0:
			out.set_meta("pole_" + side.to_lower(), sk.transform * sk.get_bone_global_pose(pi).origin)
	for b in ["UpArm_L_03", "UpArm_R_09", "Hand_L_016", "Hand_R_037"]:
		print(b, " cam=", sk.transform * sk.get_bone_global_pose(sk.find_bone(b)).origin)
	print("poles ", out.get_meta("pole_l", null), " ", out.get_meta("pole_r", null))
	var ps := PackedScene.new()
	ps.pack(out)
	var err := ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("BAKE_DONE err=", err, " bones=", sk.get_bone_count())
	root.free()
	quit()

func _rel(n: Node, anc: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != anc:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
