extends SceneTree
## Offline-Bake der realistischen Gegner-Soldaten (headless):
##   godot --headless --path . -s res://game/enemies/tools/bake_soldier_mh.gd
## - Modelle: assets/characters/soldier_mh/src/soldier_<v>.glb (MakeHuman/MPFB2, CC0; gebaut mit
##   tools/soldier/build_soldier.py, Knochen bereits auf die SWAT-Namen umbenannt, Texturen NICHT eingebettet).
## - Texturen: assets/characters/soldier_mh/tex/ (gemeinsam fuer alle Varianten, nur die Haut je Variante).
## - LODs werden hier mit ImporterMesh.generate_lods erzeugt (GLBs liegen in einem .gdignore-Ordner).
## - Animationen: Welt-Delta-Retarget aus der Quaternius Universal Animation Library (CC0) und den
##   Quaternius-SWAT-Clips (CC0) auf das MPFB-"game_engine"-Skelett. Arme/Beine werden vorher auf die
##   Ruhepose der Quelle ausgerichtet (A-Pose -> T-Pose). Huefthoehe wird skaliert, Schleifen
##   werden "in place" gemacht und die Fuesse optional auf den Boden gezwungen (kein Schweben/Einsinken).
## Ergebnis: assets/characters/soldier_mh/soldier_mh_<v>.scn (SoldierRig/Skeleton3D/Body+Helmet, AnimationPlayer),
## Meta "loco_speed": natuerliche Laufgeschwindigkeit der Fortbewegungs-Clips (m/s) fuer den Blend-Space.

const FPS := 30.0
## Stiefel sind steif: Zehen-Beugung der Quelle (UAL bis ~55 Grad) nur gedaempft uebernehmen, sonst knickt der
## Stiefel-Vorderteil weg und der Schuh wirkt ploetzlich riesig/lang ("Clownschuhe").
const TOE_FLEX := 0.4
const SRC := "res://assets/characters/soldier_mh/src/soldier_%s.glb"
const TEX := "res://assets/characters/soldier_mh/tex/"
const OUT := "res://assets/characters/soldier_mh/soldier_mh_%s.scn"
const SWAT := "res://assets/characters/soldier/swat.glb"
const UAL := "res://assets/characters/anim_src/ual_standard.glb"
const VARIANTS := ["a", "b", "c"]

## Zielknochen -> UAL-Quellknochen
const UAL_MAP := {
	"Hips": "DEF-hips", "Abdomen": "DEF-spine.001", "Torso": "DEF-spine.002",
	"Chest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head",
	"Shoulder.L": "DEF-shoulder.L", "UpperArm.L": "DEF-upper_arm.L", "LowerArm.L": "DEF-forearm.L", "Wrist.L": "DEF-hand.L",
	"Shoulder.R": "DEF-shoulder.R", "UpperArm.R": "DEF-upper_arm.R", "LowerArm.R": "DEF-forearm.R", "Wrist.R": "DEF-hand.R",
	"UpperLeg.L": "DEF-thigh.L", "LowerLeg.L": "DEF-shin.L", "Foot.L": "DEF-foot.L", "Toes.L": "DEF-toe.L",
	"UpperLeg.R": "DEF-thigh.R", "LowerLeg.R": "DEF-shin.R", "Foot.R": "DEF-foot.R", "Toes.R": "DEF-toe.R",
}
## Zielknochen -> SWAT-Quellknochen (gleiche Namen; Becken = "Hips")
const SWAT_MAP := {
	"Hips": "Hips", "Abdomen": "Abdomen", "Torso": "Torso", "Chest": "Chest", "Neck": "Neck", "Head": "Head",
	"Shoulder.L": "Shoulder.L", "UpperArm.L": "UpperArm.L", "LowerArm.L": "LowerArm.L", "Wrist.L": "Wrist.L",
	"Shoulder.R": "Shoulder.R", "UpperArm.R": "UpperArm.R", "LowerArm.R": "LowerArm.R", "Wrist.R": "Wrist.R",
	"UpperLeg.L": "UpperLeg.L", "LowerLeg.L": "LowerLeg.L", "Foot.L": "Foot.L",
	"UpperLeg.R": "UpperLeg.R", "LowerLeg.R": "LowerLeg.R", "Foot.R": "Foot.R",
}
## Knochen, deren Richtung vor dem Retarget an die Ruhepose der Quelle angeglichen wird
const ALIGN := ["UpperArm.L", "LowerArm.L", "Wrist.L", "UpperArm.R", "LowerArm.R", "Wrist.R",
	"UpperLeg.L", "LowerLeg.L", "UpperLeg.R", "LowerLeg.R"]
const SWAT_REPARENT := {"Foot.L": "LowerLeg.L", "Foot.R": "LowerLeg.R"}

## [Name, Quelle, Clip, Loop, Boden ("lock" = Fuss immer am Boden, "clamp" = nie darunter, "" = frei)]
## [Name, Quelle, Clip, Loop, Boden ("lock" = Fuss immer am Boden, "clamp" = nie darunter, "" = frei),
##  Ziel-Geschwindigkeit m/s (0 = Clip-Tempo bleibt; sonst wird die Zeit so skaliert, dass das Standbein
##  bei dieser Geschwindigkeit nicht rutscht)]
const ANIMS := [
	["idle", "ual", "Idle_Loop", true, "lock", 0.0],
	["walk", "ual", "Walk_Loop", true, "lock", 1.4],
	["run_fwd", "swat", "CharacterArmature|Run", true, "clamp", 2.4],
	["sprint", "ual", "Jog_Fwd_Loop", true, "clamp", 4.2],
	["run_back", "swat", "CharacterArmature|Run_Back", true, "clamp", 0.0],
	["run_left", "swat", "CharacterArmature|Run_Left", true, "clamp", 0.0],
	["run_right", "swat", "CharacterArmature|Run_Right", true, "clamp", 0.0],
	["crouch_idle", "ual", "Crouch_Idle_Loop", true, "lock", 0.0],
	["crouch_walk", "ual", "Crouch_Fwd_Loop", true, "lock", 0.9],
	["hit_1", "ual", "Hit_Chest", false, "", 0.0],
	["hit_2", "ual", "Hit_Head", false, "", 0.0],
	["hit_3", "swat", "CharacterArmature|HitRecieve", false, "", 0.0],
	["death_1", "ual", "Death01", false, "", 0.0],
	["death_2", "swat", "CharacterArmature|Death", false, "", 0.0],
]

func _gltf(path: String, st: GLTFState = null) -> Node:
	var doc := GLTFDocument.new()
	if st == null:
		st = GLTFState.new()
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

func _chain_xf(from: Node, to: Node) -> Transform3D:
	var A := Transform3D.IDENTITY
	var nd: Node = from
	while nd != to and nd != null:
		if nd is Node3D:
			A = (nd as Node3D).transform * A
		nd = nd.get_parent()
	return A

## Quelle (UAL oder SWAT): Skelett, Player, globale Ruhepose im gemeinsamen Raum (Meter, +Z vorn)
class Src:
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var A: Transform3D
	var parents: PackedInt32Array
	var order: PackedInt32Array
	var rest: Array[Transform3D]
	var map: Dictionary
	var hips: int

func _make_src(scene: Node, map: Dictionary, hips_name: String) -> Src:
	var s := Src.new()
	s.sk = _find(scene, "Skeleton3D")
	s.ap = _find(scene, "AnimationPlayer")
	s.A = _chain_xf(s.sk.get_parent(), scene)
	for i in s.sk.get_bone_count():
		s.parents.append(s.sk.get_bone_parent(i))
	s.order = _order(s.parents)
	s.rest = _src_globals(s, null, 0.0)
	s.map = map
	s.hips = s.sk.find_bone(hips_name)
	return s

func _src_globals(s: Src, anim: Animation, t: float) -> Array[Transform3D]:
	var g := _globals(_sample_local(s.sk, anim, t), s.parents, s.order)
	if s.A != Transform3D.IDENTITY:
		for i in g.size():
			g[i] = _ortho(s.A * g[i])
	return g

var _mat_shared := {}

func _tex(n: String) -> Texture2D:
	return load(TEX + n) as Texture2D

## Grundmaterialien (Laufzeit ersetzt Uniform/Helm/Stiefel durch Fraktionsmaterialien, soldier_visual.gd).
func _material(name: String, v: String) -> Material:
	var key := name if not name.begins_with("Skin") else "Skin_" + v
	if _mat_shared.has(key):
		return _mat_shared[key]
	var m := StandardMaterial3D.new()
	m.resource_name = name.get_slice("_", 0) if name.begins_with("Skin") else name
	match m.resource_name:
		"Skin":
			m.albedo_texture = _tex("skin_%s.jpg" % v)
			m.roughness = 0.58
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.35
			m.subsurf_scatter_skin_mode = true
		"Eye":
			m.albedo_texture = _tex("eye.jpg")
			m.roughness = 0.12
			m.metallic_specular = 0.7
		"Brow", "Hair":
			m.albedo_texture = _tex("brow.png" if m.resource_name == "Brow" else "hair.png")
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.45
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.8
		"Uniform":
			m.albedo_color = Color(0.36, 0.38, 0.3)
			m.albedo_texture = _tex("suit.jpg")
			m.normal_enabled = true
			m.normal_texture = _tex("suit_n.jpg")
			m.roughness = 0.9
		"Boots":
			m.albedo_texture = _tex("boots.jpg")
			m.roughness = 0.45
		"Helmet":
			m.albedo_color = Color(0.5, 0.52, 0.42)
			m.albedo_texture = _tex("helmet.jpg")
			m.normal_enabled = true
			m.normal_texture = _tex("helmet_n.jpg")
			m.roughness = 0.75
		_:
			push_warning("unbekanntes Material " + name)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_shared[key] = m
	return m

func _init() -> void:
	var ual := _gltf(UAL)
	var swat := _gltf(SWAT)
	root.add_child(ual)
	root.add_child(swat)
	var srcs := {"ual": _make_src(ual, UAL_MAP, "DEF-hips"), "swat": _make_src(swat, SWAT_MAP, "Hips")}
	for v in VARIANTS:
		_bake(v, srcs)
	quit()

## Ruhepose-Position/-Normale (Skelettraum des neuen Rigs, m) in CUSTOM0/CUSTOM1 schreiben
## (wie soldier_gear.prepare_mesh, aber VOR der LOD-Erzeugung, damit die LODs erhalten bleiben).
## soldier_mh_cloth.gdshader legt damit Tarnmuster triplanar in der Ruhepose auf (kein "Schwimmen").
func _add_rest_custom(im: ImporterMesh, skin0: Skin, sk0: Skeleton3D, A: Transform3D, g0rest: Array[Transform3D]) -> void:
	var bx: Array[Transform3D] = []
	for j in skin0.get_bind_count():
		var bn := String(skin0.get_bind_name(j))
		var b := sk0.find_bone(bn) if bn != "" else skin0.get_bind_bone(j)
		bx.append(A * g0rest[b] * skin0.get_bind_pose(j))
	var surfs := []
	for s in im.get_surface_count():
		surfs.append([im.get_surface_primitive_type(s), im.get_surface_arrays(s), im.get_surface_material(s),
			im.get_surface_name(s), im.get_surface_format(s)])
	im.clear()
	for sd in surfs:
		var a: Array = sd[1]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(vs.size(), 1)
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		c0.resize(vs.size() * 4)
		c1.resize(vs.size() * 4)
		for i in vs.size():
			var p := Vector3.ZERO
			var nn := Vector3.ZERO
			var wsum := 0.0
			for j in per:
				var w := ws[i * per + j]
				if w <= 0.0:
					continue
				var t := bx[bones[i * per + j]]
				p += (t * vs[i]) * w
				nn += (t.basis * ns[i]) * w
				wsum += w
			if wsum > 0.0:
				p /= wsum
			nn = nn.normalized()
			c0[i * 4] = p.x
			c0[i * 4 + 1] = p.y
			c0[i * 4 + 2] = p.z
			c1[i * 4] = nn.x
			c1[i * 4 + 1] = nn.y
			c1[i * 4 + 2] = nn.z
		a[Mesh.ARRAY_CUSTOM0] = c0
		a[Mesh.ARRAY_CUSTOM1] = c1
		var fl: int = int(sd[4]) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		fl |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		im.add_surface(sd[0], a, [], {}, sd[2], sd[3], fl)

func _bake(v: String, srcs: Dictionary) -> void:
	var st := GLTFState.new()
	var scene := _gltf(SRC % v, st)
	root.add_child(scene)
	var sk0: Skeleton3D = _find(scene, "Skeleton3D")
	var A := _chain_xf(sk0.get_parent(), scene)
	var n := sk0.get_bone_count()
	var parents := PackedInt32Array()
	for i in n:
		parents.append(sk0.get_bone_parent(i))
	var order := _order(parents)
	var g0rest := _globals(_sample_local(sk0, null, 0.0), parents, order)
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

	# --- Meshes: LODs aus den ImporterMeshes, Materialien mit gemeinsamen Texturen, Skins neu gebunden ---
	var lod_mesh := {}
	var skin_of := {}
	for c in sk0.get_children():
		if c is MeshInstance3D:
			skin_of[(c as MeshInstance3D).mesh.resource_name] = (c as MeshInstance3D).skin
	for gm: GLTFMesh in st.get_meshes():
		var im: ImporterMesh = gm.mesh
		if skin_of.has(im.get_name()):
			_add_rest_custom(im, skin_of[im.get_name()], sk0, A, g0rest)
		var bones_xf := []
		im.generate_lods(25.0, 60.0, bones_xf)
		lod_mesh[im.get_name()] = im
		# Dreiecke je LOD-Stufe (Summe ueber alle Flaechen)
		var per := {}
		for s in im.get_surface_count():
			per[0] = int(per.get(0, 0)) + im.get_surface_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			for l in im.get_surface_lod_count(s):
				per[l + 1] = int(per.get(l + 1, 0)) + im.get_surface_lod_indices(s, l).size() / 3
		print("[%s] LOD-Dreiecke %s: %s" % [v, im.get_name(), per])
	var tris := {}
	for c in sk0.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi0 := c as MeshInstance3D
		var src_mesh: Mesh = mi0.mesh
		var am: ArrayMesh = null
		if lod_mesh.has(src_mesh.resource_name):
			am = (lod_mesh[src_mesh.resource_name] as ImporterMesh).get_mesh()
		else:
			push_warning("keine LODs fuer " + src_mesh.resource_name)
			am = src_mesh as ArrayMesh
		for s in am.get_surface_count():
			var mn := am.surface_get_material(s).resource_name if am.surface_get_material(s) else ""
			am.surface_set_material(s, _material(mn, v))
		am.resource_name = mi0.name
		var mi := MeshInstance3D.new()
		mi.name = mi0.name
		mi.mesh = am
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
		var t := 0
		for s in am.get_surface_count():
			t += am.surface_get_array_index_len(s) / 3 if am.surface_get_array_index_len(s) > 0 else am.surface_get_array_len(s) / 3
		tris[mi.name] = t
	print("[%s] Dreiecke LOD0: %s" % [v, tris])

	# --- Retarget-Vorbereitung je Quelle ---
	var hips := sk0.find_bone("Hips")
	var foot := [sk0.find_bone("Foot.L"), sk0.find_bone("Foot.R")]
	var toes := [sk0.find_bone("Toes.L"), sk0.find_bone("Toes.R")]
	var prep := {}
	for key in srcs:
		var s: Src = srcs[key]
		var idx := {}
		for i in n:
			var nm := sk0.get_bone_name(i)
			if s.map.has(nm):
				var si := s.sk.find_bone(s.map[nm])
				if si >= 0:
					idx[i] = si
				else:
					push_warning("%s: Quellknochen fehlt %s" % [key, s.map[nm]])
		var tp: Array[Transform3D] = []
		tp.resize(n)
		for i in order:
			var t: Transform3D = lrest[i] if parents[i] < 0 else tp[parents[i]] * lrest[i]
			if sk0.get_bone_name(i) in ALIGN and idx.has(i):
				var d_t := t.basis.y.normalized()
				var d_s := s.rest[idx[i]].basis.y.normalized()
				t.basis = Basis(Quaternion(d_t, d_s)) * t.basis
			tp[i] = t
		var k := nrest[hips].origin.y / s.rest[s.hips].origin.y
		print("[%s] %s: Huefte Ziel %.3f Quelle %.3f k=%.3f" % [v, key, nrest[hips].origin.y, s.rest[s.hips].origin.y, k])
		prep[key] = {"idx": idx, "tp": tp, "k": k}

	var lib := AnimationLibrary.new()
	var speeds := {}
	var ground := [nrest[foot[0]].origin.y, nrest[foot[1]].origin.y,
		nrest[toes[0]].origin.y if toes[0] >= 0 else 0.0, nrest[toes[1]].origin.y if toes[1] >= 0 else 0.0]
	for spec in ANIMS:
		var s: Src = srcs[spec[1]]
		var pr: Dictionary = prep[spec[1]]
		var idx: Dictionary = pr["idx"]
		var tp: Array[Transform3D] = pr["tp"]
		var k: float = pr["k"]
		if not s.ap.has_animation(spec[2]):
			push_error("missing anim " + str(spec[2]))
			continue
		var sa := s.ap.get_animation(spec[2])
		var a := Animation.new()
		a.length = sa.length
		a.loop_mode = Animation.LOOP_LINEAR if spec[3] else Animation.LOOP_NONE
		var rt := {}
		for i in n:
			if parents[i] < 0:
				continue
			rt[i] = a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(rt[i], NodePath("Skeleton3D:" + sk0.get_bone_name(i)))
		var pt := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(pt, NodePath("Skeleton3D:Hips"))
		var frames := maxi(1, int(round(sa.length * FPS)))
		var drift := Vector3.ZERO
		if spec[3]:
			var s0 := _src_globals(s, sa, 0.0)[s.hips].origin
			var s1 := _src_globals(s, sa, sa.length)[s.hips].origin
			drift = Vector3(s1.x - s0.x, 0, s1.z - s0.z)
			if drift.length() > 0.05:
				speeds[spec[0]] = drift.length() * k / sa.length
		var gmode: String = spec[4]
		var low := 99.0
		var high := -99.0
		var rec := [[], []]   # je Fuss: [Bodenabstand, z] pro Frame
		for f in frames + 1:
			var t := minf(f / FPS, sa.length)
			var sg := _src_globals(s, sa, t)
			var g: Array[Transform3D] = []
			g.resize(n)
			for i in order:
				var tt: Transform3D = lrest[i] if parents[i] < 0 else g[parents[i]] * lrest[i]
				if idx.has(i):
					var si: int = idx[i]
					tt.basis = (sg[si].basis.orthonormalized() * s.rest[si].basis.orthonormalized().inverse() * tp[i].basis).orthonormalized()
					if i == toes[0] or i == toes[1]:
						var pb: Basis = g[parents[i]].basis
						var lq := Quaternion((pb.inverse() * tt.basis).orthonormalized())
						tt.basis = pb * Basis(Quaternion(lrest[i].basis.orthonormalized()).slerp(lq, TOE_FLEX))
					if i == hips:
						var d := sg[si].origin - s.rest[si].origin - drift * (t / sa.length)
						tt.origin = tp[i].origin + d * k
				g[i] = tt
			# Bodenkontakt: niedrigster Fuss (Knoechel oder Zehen) relativ zur Ruhepose
			var clear := 99.0
			var fc := [99.0, 99.0]
			for j in 2:
				fc[j] = g[foot[j]].origin.y - ground[j]
				if toes[j] >= 0:
					fc[j] = minf(fc[j], g[toes[j]].origin.y - ground[2 + j])
				clear = minf(clear, fc[j])
			for j in 2:
				rec[j].append([fc[j], g[foot[j]].origin.z])
			var off := 0.0
			if gmode == "lock" or (gmode == "clamp" and clear < 0.0):
				off = -clear
			if off != 0.0:
				for i in n:
					if parents[i] >= 0:
						g[i].origin.y += off
			low = minf(low, clear + off)
			high = maxf(high, clear + off)
			for i in rt:
				var l: Transform3D = g[parents[i]].affine_inverse() * g[i]
				a.rotation_track_insert_key(rt[i], t, l.basis.orthonormalized().get_rotation_quaternion())
				if i == hips:
					a.position_track_insert_key(pt, t, l.origin)
		# Standbein gleitet im Clip nach hinten -> natuerliche Geschwindigkeit (Median ueber Standphasen)
		if spec[3] and not speeds.has(spec[0]):
			var vs: Array[float] = []
			for j in 2:
				var mn := 99.0
				for r in rec[j]:
					mn = minf(mn, r[0])
				for fi in range(1, rec[j].size()):
					if rec[j][fi][0] < mn + 0.02 and rec[j][fi - 1][0] < mn + 0.02:
						vs.append(-(rec[j][fi][1] - rec[j][fi - 1][1]) * FPS)
			if vs.size() > 2:
				vs.sort()
				speeds[spec[0]] = vs[vs.size() / 2]
		var natural: float = speeds.get(spec[0], 0.0)
		if spec[5] > 0.0 and natural > 0.1:
			var fac: float = natural / spec[5]
			for tr in a.get_track_count():
				# Keys neu aufbauen statt track_set_key_time: das sortiert beim Strecken (fac > 1) um und hat die
				# Keys verwuerfelt (Zeiten > Clip-Laenge, Beine springen pro Frame bis 110 Grad -> "Clownschuhe" im Lauf)
				var nk := a.track_get_key_count(tr)
				var kt: Array[float] = []
				var kv: Array = []
				for kk in nk:
					kt.append(a.track_get_key_time(tr, kk) * fac)
					kv.append(a.track_get_key_value(tr, kk))
				for kk in range(nk - 1, -1, -1):
					a.track_remove_key(tr, kk)
				for kk in nk:
					a.track_insert_key(tr, kt[kk], kv[kk])
			a.length *= fac
			speeds[spec[0]] = spec[5]
			print("[%s] %s: Tempo x%.2f (natuerlich %.2f m/s -> %.2f m/s)" % [v, spec[0], 1.0 / fac, natural, spec[5]])
		lib.add_animation(spec[0], a)
		print("[%s] %-12s <- %-28s len=%.2f speed=%.2f foot_clear=[%.3f..%.3f]" % [v, spec[0], spec[2], sa.length, speeds.get(spec[0], 0.0), low, high])

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	rig.add_child(ap)
	ap.owner = rig
	rig.set_meta("loco_speed", speeds)
	rig.set_meta("kind", "mh")
	var ps := PackedScene.new()
	ps.pack(rig)
	var err := ResourceSaver.save(ps, OUT % v, ResourceSaver.FLAG_COMPRESS)
	print("[%s] gespeichert %s err=%d" % [v, OUT % v, err])
	for nm in ["Root", "Hips", "Abdomen", "Chest", "Neck", "Head", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R", "Wrist.L", "UpperLeg.L", "Foot.L"]:
		var b := sk0.find_bone(nm)
		if b >= 0:
			print("  rest %-11s pos=%s y=%s z=%s" % [nm, nrest[b].origin, nrest[b].basis.y, nrest[b].basis.z])
	scene.queue_free()
