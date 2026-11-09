extends SceneTree
## Offline-Bake des Soldaten-Rigs (headless):
##   godot --headless --path . -s res://game/enemies/tools/bake_soldier.gd
## - Modell: Quaternius SWAT (CC0). Armature-Transform (Rot -90X, Scale 100) wird ins Skelett
##   gebacken (Meter-Einheiten, keine skalierten Nodes -> PhysicalBones funktionieren),
##   Foot.L/R (im Original IK-Knochen unter Root) werden an die Schienbeine gehaengt.
## - Animationen: eigene SWAT-Clips + per Welt-Delta-Retarget aus der Quaternius Universal
##   Animation Library (CC0). Ergebnis: assets/characters/soldier/soldier_rig.scn mit
##   AnimationPlayer und kanonischen Clip-Namen (idle, walk, run_fwd, ... siehe ANIMS).
## Mixamo-Tausch: Mixamo-GLB nach assets/characters/mixamo/ legen, Quelle in ANIMS auf
## "mixamo" + MIXAMO_MAP umstellen (mixamorig:*-Knochen). Clip-Namen bleiben gleich,
## der Laufzeitcode (soldier_visual.gd) bleibt unveraendert.

const FPS := 30.0
const SWAT := "res://assets/characters/soldier/swat.glb"
const UAL := "res://assets/characters/anim_src/ual_standard.glb"
const OUT := "res://assets/characters/soldier/soldier_rig.scn"

## Ziel-Knochen (SWAT) -> Quellknochen
const UAL_MAP := {
	"Body": "DEF-hips", "Hips": "DEF-hips", "Abdomen": "DEF-spine.001", "Torso": "DEF-spine.002",
	"Chest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head",
	"Shoulder.L": "DEF-shoulder.L", "UpperArm.L": "DEF-upper_arm.L", "LowerArm.L": "DEF-forearm.L", "Wrist.L": "DEF-hand.L",
	"Shoulder.R": "DEF-shoulder.R", "UpperArm.R": "DEF-upper_arm.R", "LowerArm.R": "DEF-forearm.R", "Wrist.R": "DEF-hand.R",
	"UpperLeg.L": "DEF-thigh.L", "LowerLeg.L": "DEF-shin.L", "Foot.L": "DEF-foot.L",
	"UpperLeg.R": "DEF-thigh.R", "LowerLeg.R": "DEF-shin.R", "Foot.R": "DEF-foot.R",
}
## Fuer spaeteren Mixamo-Import (gleiche Methode, T-Pose-Quelle).
const MIXAMO_MAP := {
	"Body": "mixamorig:Hips", "Hips": "mixamorig:Hips", "Abdomen": "mixamorig:Spine", "Torso": "mixamorig:Spine1",
	"Chest": "mixamorig:Spine2", "Neck": "mixamorig:Neck", "Head": "mixamorig:Head",
	"Shoulder.L": "mixamorig:LeftShoulder", "UpperArm.L": "mixamorig:LeftArm", "LowerArm.L": "mixamorig:LeftForeArm", "Wrist.L": "mixamorig:LeftHand",
	"Shoulder.R": "mixamorig:RightShoulder", "UpperArm.R": "mixamorig:RightArm", "LowerArm.R": "mixamorig:RightForeArm", "Wrist.R": "mixamorig:RightHand",
	"UpperLeg.L": "mixamorig:LeftUpLeg", "LowerLeg.L": "mixamorig:LeftLeg", "Foot.L": "mixamorig:LeftFoot",
	"UpperLeg.R": "mixamorig:RightUpLeg", "LowerLeg.R": "mixamorig:RightLeg", "Foot.R": "mixamorig:RightFoot",
}
## Knochen, deren Richtung fuer die T-Pose-Angleichung an die Quelle gedreht wird.
const ALIGN := ["UpperArm.L", "LowerArm.L", "Wrist.L", "UpperArm.R", "LowerArm.R", "Wrist.R",
	"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]
const REPARENT := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}

## [Name, Quelle ("swat"/"ual"), Quell-Clip, Loop, InPlace]
const ANIMS := [
	["idle", "swat", "CharacterArmature|Idle", true, false],
	["idle_gun", "swat", "CharacterArmature|Idle_Gun", true, false],
	["walk", "swat", "CharacterArmature|Walk", true, false],
	["run_fwd", "swat", "CharacterArmature|Run", true, false],
	["run_back", "swat", "CharacterArmature|Run_Back", true, false],
	["run_left", "swat", "CharacterArmature|Run_Left", true, false],
	["run_right", "swat", "CharacterArmature|Run_Right", true, false],
	["hit_1", "swat", "CharacterArmature|HitRecieve", false, false],
	["hit_2", "swat", "CharacterArmature|HitRecieve_2", false, false],
	["death_1", "swat", "CharacterArmature|Death", false, false],
	["crouch_idle", "ual", "Crouch_Idle_Loop", true, true],
	["crouch_walk", "ual", "Crouch_Fwd_Loop", true, true],
	["death_2", "ual", "Death01", false, false],
	["hit_3", "ual", "Hit_Chest", false, false],
	["walk_ual", "ual", "Walk_Loop", true, true],
]

func _gltf(path: String) -> Node:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		push_error("load fail " + path)
		return null
	return doc.generate_scene(st)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var s := _find(c, cls)
		if s:
			return s
	return null

func _ortho(t: Transform3D) -> Transform3D:
	return Transform3D(t.basis.orthonormalized(), t.origin)

## Lokale Posen aller Knochen eines Skeletts zum Zeitpunkt t.
func _sample_local(sk: Skeleton3D, anim: Animation, t: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_rest(i))
	if anim == null:
		return out
	for tr in anim.get_track_count():
		var p := String(anim.track_get_path(tr).get_concatenated_subnames())
		var b := sk.find_bone(p)
		if b < 0:
			continue
		var cur: Transform3D = out[b]
		match anim.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				cur.origin = anim.position_track_interpolate(tr, t)
			Animation.TYPE_ROTATION_3D:
				var sc := cur.basis.get_scale()
				cur.basis = Basis(anim.rotation_track_interpolate(tr, t)) * Basis.from_scale(sc)
			Animation.TYPE_SCALE_3D:
				cur.basis = Basis(cur.basis.get_rotation_quaternion()) * Basis.from_scale(anim.scale_track_interpolate(tr, t))
		out[b] = cur
	return out

func _order(parents: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var done := {}
	while out.size() < parents.size():
		for i in parents.size():
			if done.has(i):
				continue
			if parents[i] < 0 or done.has(parents[i]):
				out.append(i)
				done[i] = true
	return out

func _globals(local: Array[Transform3D], parents: PackedInt32Array, order: PackedInt32Array) -> Array[Transform3D]:
	var g: Array[Transform3D] = []
	g.resize(local.size())
	for i in order:
		g[i] = local[i] if parents[i] < 0 else g[parents[i]] * local[i]
	return g

func _init() -> void:
	var swat := _gltf(SWAT)
	var ual := _gltf(UAL)
	root.add_child(swat)
	root.add_child(ual)
	var sk0: Skeleton3D = _find(swat, "Skeleton3D")
	var ap0: AnimationPlayer = _find(swat, "AnimationPlayer")
	var arm := sk0.get_parent() as Node3D
	var A := Transform3D.IDENTITY
	var nd: Node = arm
	while nd != swat:
		A = (nd as Node3D).transform * A
		nd = nd.get_parent()
	var sks: Skeleton3D = _find(ual, "Skeleton3D")
	var aps: AnimationPlayer = _find(ual, "AnimationPlayer")
	var n := sk0.get_bone_count()

	# --- neues Skelett ---
	var parents0 := PackedInt32Array()
	var parents := PackedInt32Array()
	for i in n:
		parents0.append(sk0.get_bone_parent(i))
		var nm := sk0.get_bone_name(i)
		parents.append(sk0.find_bone(REPARENT[nm]) if REPARENT.has(nm) else sk0.get_bone_parent(i))
	var order0 := _order(parents0)
	var order := _order(parents)
	var g0rest := _globals(_sample_local(sk0, null, 0.0), parents0, order0)
	var nrest: Array[Transform3D] = []
	for i in n:
		nrest.append(_ortho(A * g0rest[i]))
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in n:
		sk.add_bone(sk0.get_bone_name(i))
	for i in n:
		sk.set_bone_parent(i, parents[i])
	var lrest: Array[Transform3D] = []
	for i in n:
		var l: Transform3D = nrest[i] if parents[i] < 0 else nrest[parents[i]].affine_inverse() * nrest[i]
		lrest.append(l)
		sk.set_bone_rest(i, l)
		sk.set_bone_pose(i, l)
	var rig := Node3D.new()
	rig.name = "SoldierRig"
	rig.add_child(sk)
	sk.owner = rig

	# --- Meshes + Skins ---
	for c in sk0.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi0 := c as MeshInstance3D
		var mi := MeshInstance3D.new()
		mi.name = mi0.name
		mi.mesh = mi0.mesh
		for s in mi0.get_surface_override_material_count():
			if mi0.get_surface_override_material(s):
				mi.set_surface_override_material(s, mi0.get_surface_override_material(s))
		var skin0: Skin = mi0.skin
		var skin := Skin.new()
		for j in skin0.get_bind_count():
			var bn := String(skin0.get_bind_name(j))
			var b := sk0.find_bone(bn) if bn != "" else skin0.get_bind_bone(j)
			var bp: Transform3D = nrest[b].affine_inverse() * A * g0rest[b] * skin0.get_bind_pose(j)
			skin.add_named_bind(sk0.get_bone_name(b), bp)
		mi.skin = skin
		sk.add_child(mi)
		mi.owner = rig
		mi.skeleton = NodePath("..")

	# --- Retarget-Vorbereitung (T-Pose des Ziels an Quelle angeglichen) ---
	var ns := sks.get_bone_count()
	var sparents := PackedInt32Array()
	for i in ns:
		sparents.append(sks.get_bone_parent(i))
	var sorder := _order(sparents)
	var srest := _globals(_sample_local(sks, null, 0.0), sparents, sorder)
	var src_idx := {}
	for i in n:
		var nm := sk0.get_bone_name(i)
		if UAL_MAP.has(nm):
			src_idx[i] = sks.find_bone(UAL_MAP[nm])
	var tp: Array[Transform3D] = []
	tp.resize(n)
	for i in order:
		var t: Transform3D = lrest[i] if parents[i] < 0 else tp[parents[i]] * lrest[i]
		if sk0.get_bone_name(i) in ALIGN:
			var d_t := t.basis.y.normalized()
			var d_s := srest[src_idx[i]].basis.y.normalized()
			t.basis = Basis(Quaternion(d_t, d_s)) * t.basis
		tp[i] = t
	var body := sk0.find_bone("Body")
	var hips := sk0.find_bone("Hips")
	var ships := sks.find_bone("DEF-hips")
	var k := nrest[hips].origin.y / srest[ships].origin.y
	print("hip height target=%.3f source=%.3f k=%.3f" % [nrest[hips].origin.y, srest[ships].origin.y, k])

	# --- Animationen backen ---
	var lib := AnimationLibrary.new()
	var foot_l := sk0.find_bone("Foot.L")
	var foot_r := sk0.find_bone("Foot.R")
	var pos_bones := [body, foot_l, foot_r]
	var skip := [sk0.find_bone("Root"), sk0.find_bone("PT.L"), sk0.find_bone("PT.R")]
	for spec in ANIMS:
		var is_ual: bool = spec[1] == "ual"
		var src_ap: AnimationPlayer = aps if is_ual else ap0
		if not src_ap.has_animation(spec[2]):
			push_error("missing anim " + str(spec[2]))
			continue
		var sa := src_ap.get_animation(spec[2])
		var a := Animation.new()
		a.length = sa.length
		a.loop_mode = Animation.LOOP_LINEAR if spec[3] else Animation.LOOP_NONE
		var rt := {}
		var pt := {}
		for i in n:
			if i in skip:
				continue
			var path := NodePath("Skeleton3D:" + sk0.get_bone_name(i))
			rt[i] = a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(rt[i], path)
			if i in pos_bones and (not is_ual or i == body):
				pt[i] = a.add_track(Animation.TYPE_POSITION_3D)
				a.track_set_path(pt[i], path)
		var frames := maxi(1, int(round(sa.length * FPS)))
		var drift := Vector3.ZERO
		if is_ual and spec[4]:
			var s0 := _globals(_sample_local(sks, sa, 0.0), sparents, sorder)[ships].origin
			var s1 := _globals(_sample_local(sks, sa, sa.length), sparents, sorder)[ships].origin
			drift = Vector3(s1.x - s0.x, 0, s1.z - s0.z)
		var min_foot := 99.0
		var max_foot := -99.0
		for f in frames + 1:
			var t := minf(f / FPS, sa.length)
			var g: Array[Transform3D] = []
			if not is_ual:
				var g0 := _globals(_sample_local(sk0, sa, t), parents0, order0)
				for i in n:
					g.append(_ortho(A * g0[i]))
			else:
				var sg := _globals(_sample_local(sks, sa, t), sparents, sorder)
				g.resize(n)
				for i in order:
					var tt: Transform3D = lrest[i] if parents[i] < 0 else g[parents[i]] * lrest[i]
					if src_idx.has(i):
						var si: int = src_idx[i]
						tt.basis = (sg[si].basis.orthonormalized() * srest[si].basis.orthonormalized().inverse() * tp[i].basis).orthonormalized()
						if i == body:
							var d := sg[si].origin - srest[si].origin - drift * (t / sa.length)
							tt.origin = tp[i].origin + d * k
					g[i] = tt
			min_foot = minf(min_foot, minf(g[foot_l].origin.y, g[foot_r].origin.y))
			max_foot = maxf(max_foot, minf(g[foot_l].origin.y, g[foot_r].origin.y))
			for i in rt:
				var l: Transform3D = g[i] if parents[i] < 0 else g[parents[i]].affine_inverse() * g[i]
				a.rotation_track_insert_key(rt[i], t, l.basis.orthonormalized().get_rotation_quaternion())
				if pt.has(i):
					a.position_track_insert_key(pt[i], t, l.origin)
		lib.add_animation(spec[0], a)
		print("baked %-12s from %-28s len=%.2f frames=%d lower_foot_y=[%.3f..%.3f]" % [spec[0], spec[2], sa.length, frames, min_foot, max_foot])

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	rig.add_child(ap)
	ap.owner = rig
	var ps := PackedScene.new()
	ps.pack(rig)
	var err := ResourceSaver.save(ps, OUT)
	print("saved ", OUT, " err=", err)
	for nm in ["Root", "Body", "Hips", "Chest", "Neck", "Head", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R", "Wrist.L", "UpperLeg.L", "LowerLeg.L", "Foot.L"]:
		var b := sk0.find_bone(nm)
		print("  rest %-11s pos=%s y=%s z=%s" % [nm, nrest[b].origin, nrest[b].basis.y, nrest[b].basis.z])
	quit()
