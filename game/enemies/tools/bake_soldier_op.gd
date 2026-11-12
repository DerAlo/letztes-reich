extends SceneTree
## Offline-Bake des Gegner-Modells "Operator" (headless):
##   godot --headless --path . -s res://game/enemies/tools/bake_soldier_op.gd [-- --src=<entpackter Sketchfab-Ordner>]
## Modell: "S.W.A.T. Operator - Remastered" von Mateusz Wolinski (jeandiz), Sketchfab Standard License,
##   https://sketchfab.com/3d-models/swat-operator-remastered-732d2eec5a0c456bafedd08af35134c3
## - Mit --src=... werden scene.gltf/.bin (ohne Bildverweise) nach assets/characters/soldier_op/src/ (.gdignore)
##   kopiert und die 4k-Texturen auf 2048 verkleinert nach assets/characters/soldier_op/tex/ geschrieben
##   (danach einmal "--headless --import" laufen lassen, dann den Bake ohne --src).
## - Die Kriss-Vector-Teile (*_KSVR) fliegen raus; ihre Lage in der Ruhepose liefert aber die Griff-Rahmen
##   der Haende (Meta "grip_r"/"grip_l", Hand relativ zur Waffe) fuer die Oberkoerper-IK.
## - Mixamo-Skelett -> kanonische SWAT-Namen (Laufzeit-Code: IK, Ragdoll, Hitboxen, Ausruestung unveraendert).
##   Mixamo hat kein Spine2: "Torso" wird als unbelasteter Zwischenknochen (auf Spine1) eingefuegt.
##   Ruhe-Achsen werden vereinheitlicht (Arme: X = Ellbogenachse, Hand: Y = Finger / Z = Handruecken,
##   Finger: X = Beugeachse, Rumpf/Kopf: Y laengs / Z vorn) -- Skins werden darauf neu gebunden.
## - Animationen wie bake_soldier_mh.gd (Welt-Delta-Retarget aus UAL/Quaternius-SWAT), aber die Ruhepose
##   des Modells ist eine Anschlag-Haltung: Huefte, Brust, Arme, Haende, Beine und Fuesse werden vorher
##   mit ZWEI Richtungen (Knochen + Querachse) auf die Ruhepose der Quelle gebracht (kein Verdrehen).
## Ergebnis: assets/characters/soldier_op/soldier_op.scn (SoldierRig/Skeleton3D/Body+HeadGear+Eyelashes, AnimationPlayer)

const FPS := 30.0
## Stiefel sind steif: Zehen-Beugung der Quelle (UAL bis ~55 Grad) nur gedaempft uebernehmen, sonst knickt der
## Stiefel-Vorderteil weg und der Schuh wirkt ploetzlich riesig/lang ("Clownschuhe").
const TOE_FLEX := 0.3
const OPD := "res://assets/characters/soldier_op/"
const SRC := OPD + "src/scene.gltf"
const TEX := OPD + "tex/"
const OUT := OPD + "soldier_op.scn"
const SWAT := "res://assets/characters/soldier/swat.glb"
const UAL := "res://assets/characters/anim_src/ual_standard.glb"
const TEX_SIZE := 2048

## Texturen: Quelle (Sketchfab-Name) -> [Ziel, Groesse, jpg-Qualitaet (0 = png)]
const TEX_FILES := {
	"Body.001_baseColor.png": ["body_albedo.jpg", TEX_SIZE, 0.93],
	"Body.001_normal.png": ["body_normal.jpg", TEX_SIZE, 0.95],
	"Body.001_metallicRoughness.png": ["body_orm.jpg", TEX_SIZE, 0.9],
	"HeadGear.001_baseColor.png": ["gear_albedo.jpg", TEX_SIZE, 0.93],
	"HeadGear.001_normal.png": ["gear_normal.jpg", TEX_SIZE, 0.95],
	"HeadGear.001_metallicRoughness.png": ["gear_orm.jpg", TEX_SIZE, 0.9],
	"HeadGear.001_emissive.png": ["gear_emissive.jpg", 1024, 0.9],
	"Eyelashes.001_baseColor.png": ["lashes.png", 512, 0.0],
}

## Mixamo (ohne "mixamorig:" und Index-Suffix) -> kanonischer Name
const OP_MAP := {
	"_rootJoint": "Root", "Hips": "Hips", "Spine": "Abdomen", "Spine1": "Chest", "Neck": "Neck", "Head": "Head",
	"HeadTop_End": "HeadTop",
	"LeftShoulder": "Shoulder.L", "LeftArm": "UpperArm.L", "LeftForeArm": "LowerArm.L", "LeftHand": "Wrist.L",
	"RightShoulder": "Shoulder.R", "RightArm": "UpperArm.R", "RightForeArm": "LowerArm.R", "RightHand": "Wrist.R",
	"LeftUpLeg": "UpperLeg.L", "LeftLeg": "LowerLeg.L", "LeftFoot": "Foot.L", "LeftToeBase": "Toes.L", "LeftToe_End": "ToesEnd.L",
	"RightUpLeg": "UpperLeg.R", "RightLeg": "LowerLeg.R", "RightFoot": "Foot.R", "RightToeBase": "Toes.R", "RightToe_End": "ToesEnd.R",
}
const FINGERS := ["Thumb", "Index", "Middle", "Ring", "Pinky"]

## Zielknochen -> UAL-Quellknochen
const UAL_MAP := {
	"Hips": "DEF-hips", "Abdomen": "DEF-spine.001", "Torso": "DEF-spine.002",
	"Chest": "DEF-spine.003", "Neck": "DEF-neck", "Head": "DEF-head",
	"Shoulder.L": "DEF-shoulder.L", "UpperArm.L": "DEF-upper_arm.L", "LowerArm.L": "DEF-forearm.L", "Wrist.L": "DEF-hand.L",
	"Shoulder.R": "DEF-shoulder.R", "UpperArm.R": "DEF-upper_arm.R", "LowerArm.R": "DEF-forearm.R", "Wrist.R": "DEF-hand.R",
	"UpperLeg.L": "DEF-thigh.L", "LowerLeg.L": "DEF-shin.L", "Foot.L": "DEF-foot.L", "Toes.L": "DEF-toe.L",
	"UpperLeg.R": "DEF-thigh.R", "LowerLeg.R": "DEF-shin.R", "Foot.R": "DEF-foot.R", "Toes.R": "DEF-toe.R",
}
const SWAT_MAP := {
	"Hips": "Hips", "Abdomen": "Abdomen", "Torso": "Torso", "Chest": "Chest", "Neck": "Neck", "Head": "Head",
	"Shoulder.L": "Shoulder.L", "UpperArm.L": "UpperArm.L", "LowerArm.L": "LowerArm.L", "Wrist.L": "Wrist.L",
	"Shoulder.R": "Shoulder.R", "UpperArm.R": "UpperArm.R", "LowerArm.R": "LowerArm.R", "Wrist.R": "Wrist.R",
	"UpperLeg.L": "UpperLeg.L", "LowerLeg.L": "LowerLeg.L", "Foot.L": "Foot.L",
	"UpperLeg.R": "UpperLeg.R", "LowerLeg.R": "LowerLeg.R", "Foot.R": "Foot.R",
}
## Nur fuer die Hand-Querachse (Zeigefinger - kleiner Finger) und Handrichtung (Mittelfinger)
const UAL_FINGER := {"Index1": "DEF-f_index.01", "Middle1": "DEF-f_middle.01", "Pinky1": "DEF-f_pinky.01"}
const SWAT_FINGER := {"Index1": "Index1", "Middle1": "Middle1", "Pinky1": "Pinky1"}

## Ausrichtung auf die Quell-Ruhepose: Knochen -> [Kind (Richtung), Querachse]
const ALIGN := [
	["Hips", "Abdomen", "hips"],
	["Chest", "Neck", "shoulders"],
	["UpperArm.L", "LowerArm.L", "elbow"], ["LowerArm.L", "Wrist.L", "elbow"], ["Wrist.L", "Middle1.L", "hand"],
	["UpperArm.R", "LowerArm.R", "elbow"], ["LowerArm.R", "Wrist.R", "elbow"], ["Wrist.R", "Middle1.R", "hand"],
	["UpperLeg.L", "LowerLeg.L", "leg"], ["LowerLeg.L", "Foot.L", "leg"], ["Foot.L", "Toes.L", "side"],
	["UpperLeg.R", "LowerLeg.R", "leg"], ["LowerLeg.R", "Foot.R", "leg"], ["Foot.R", "Toes.R", "side"],
]

## [Name, Quelle, Clip, Loop, Boden, Ziel-Geschwindigkeit] (siehe bake_soldier_mh.gd)
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

const FWD := Vector3(0, 0, 1)

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

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

class Src:
	var sk: Skeleton3D
	var ap: AnimationPlayer
	var A: Transform3D
	var parents: PackedInt32Array
	var order: PackedInt32Array
	var rest: Array[Transform3D]
	var map: Dictionary
	var fingers: Dictionary
	var hips: int

func _make_src(scene: Node, map: Dictionary, fingers: Dictionary, hips_name: String) -> Src:
	var s := Src.new()
	s.sk = _find(scene, "Skeleton3D")
	s.ap = _find(scene, "AnimationPlayer")
	s.A = _chain_xf(s.sk.get_parent(), scene)
	for i in s.sk.get_bone_count():
		s.parents.append(s.sk.get_bone_parent(i))
	s.order = _order(s.parents)
	s.rest = _src_globals(s, null, 0.0)
	s.map = map
	s.fingers = fingers
	s.hips = s.sk.find_bone(hips_name)
	return s

func _src_globals(s: Src, anim: Animation, t: float) -> Array[Transform3D]:
	var g := _globals(_sample_local(s.sk, anim, t), s.parents, s.order)
	if s.A != Transform3D.IDENTITY:
		for i in g.size():
			g[i] = _ortho(s.A * g[i])
	return g

## Ruhe-Position eines kanonischen Knochens in der Quelle (Finger "Index1.L" ueber die Finger-Tabelle)
func _src_pos(s: Src, canon: String) -> Variant:
	var nm := ""
	if s.map.has(canon):
		nm = s.map[canon]
	else:
		var base := canon.get_slice(".", 0)
		if s.fingers.has(base):
			nm = "%s.%s" % [s.fingers[base], canon.get_slice(".", 1)]
	if nm == "":
		return null
	var b := s.sk.find_bone(nm)
	return s.rest[b].origin if b >= 0 else null

# ------------------------------------------------------------------ Vorbereitung (--src)

func _prepare(src_dir: String) -> void:
	var dst := ProjectSettings.globalize_path(OPD)
	DirAccess.make_dir_recursive_absolute(dst + "src")
	DirAccess.make_dir_recursive_absolute(dst + "tex")
	var gi := FileAccess.open(dst + "src/.gdignore", FileAccess.WRITE)
	gi.close()
	# glTF ohne Bildverweise (Texturen kommen getrennt, verkleinert, aus tex/)
	var js: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(src_dir.path_join("scene.gltf")))
	for k in ["images", "textures", "samplers"]:
		js.erase(k)
	for m: Dictionary in js.get("materials", []):
		var pbr: Dictionary = m.get("pbrMetallicRoughness", {})
		pbr.erase("baseColorTexture")
		pbr.erase("metallicRoughnessTexture")
		for k in ["normalTexture", "occlusionTexture", "emissiveTexture"]:
			m.erase(k)
	var f := FileAccess.open(dst + "src/scene.gltf", FileAccess.WRITE)
	f.store_string(JSON.stringify(js, "\t"))
	f.close()
	DirAccess.copy_absolute(src_dir.path_join("scene.bin"), dst + "src/scene.bin")
	DirAccess.copy_absolute(src_dir.path_join("license.txt"), dst + "LICENSE.txt")
	for n: String in TEX_FILES:
		var spec: Array = TEX_FILES[n]
		var im := Image.load_from_file(src_dir.path_join("textures").path_join(n))
		if im == null:
			push_error("Textur fehlt " + n)
			continue
		var png: bool = float(spec[2]) <= 0.0
		im.convert(Image.FORMAT_RGBA8 if png else Image.FORMAT_RGB8)
		im.resize(int(spec[1]), int(spec[1]), Image.INTERPOLATE_LANCZOS)
		var out: String = dst + "tex/" + String(spec[0])
		var err := im.save_png(out) if png else im.save_jpg(out, float(spec[2]))
		print("tex %s -> %s (%d) err=%d" % [n, spec[0], spec[1], err])

# ------------------------------------------------------------------ Materialien (Fallback; Laufzeit: soldier_op.gdshader)

func _tex(n: String) -> Texture2D:
	return load(TEX + n) as Texture2D

func _material(name: String) -> Material:
	var m := StandardMaterial3D.new()
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if name.begins_with("Body"):
		m.resource_name = "OpBody"
		m.albedo_texture = _tex("body_albedo.jpg")
		m.albedo_color = Color(0.615, 0.615, 0.615)
		m.normal_enabled = true
		m.normal_texture = _tex("body_normal.jpg")
		m.roughness_texture = _tex("body_orm.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = _tex("body_orm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
	elif name.begins_with("HeadGear"):
		m.resource_name = "OpGear"
		m.albedo_texture = _tex("gear_albedo.jpg")
		m.normal_enabled = true
		m.normal_texture = _tex("gear_normal.jpg")
		m.roughness_texture = _tex("gear_orm.jpg")
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = _tex("gear_orm.jpg")
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		m.metallic = 1.0
		m.emission_enabled = true
		m.emission_texture = _tex("gear_emissive.jpg")
		m.emission_energy_multiplier = 2.0
	else:
		m.resource_name = "OpLashes"
		m.albedo_texture = _tex("lashes.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.8
	return m

## wie bake_soldier_mh.gd: Ruhepose-Position/-Normale in CUSTOM0/CUSTOM1 (vor der LOD-Erzeugung)
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

## Ruhepose-Punkte eines Meshes (Skelettraum) samt dominantem Knochen (kanonischer Name)
func _rest_points(mi: MeshInstance3D, sk0: Skeleton3D, A: Transform3D, g0rest: Array[Transform3D], canon_of: Dictionary) -> Array:
	var skin0 := mi.skin
	var bx: Array[Transform3D] = []
	var bname: Array[String] = []
	for j in skin0.get_bind_count():
		var bn := String(skin0.get_bind_name(j))
		var b := sk0.find_bone(bn) if bn != "" else skin0.get_bind_bone(j)
		bx.append(A * g0rest[b] * skin0.get_bind_pose(j))
		bname.append(String(canon_of.get(b, sk0.get_bone_name(b))))
	var out := []
	var am := mi.mesh as ArrayMesh
	for s in am.get_surface_count():
		var a := am.surface_get_arrays(s)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var ws: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		if bones.is_empty():
			for v in vs:
				out.append([A * v, ""])
			continue
		var per := bones.size() / maxi(vs.size(), 1)
		for i in vs.size():
			var p := Vector3.ZERO
			var wsum := 0.0
			var best := -1.0
			var bb := ""
			for j in per:
				var w := ws[i * per + j]
				if w <= 0.0:
					continue
				p += (bx[bones[i * per + j]] * vs[i]) * w
				wsum += w
				if w > best:
					best = w
					bb = bname[bones[i * per + j]]
			out.append([p / maxf(wsum, 1e-6), bb])
	return out

# ------------------------------------------------------------------ Skelett

static func _canon_name(raw: String) -> String:
	var re := RegEx.create_from_string("^mixamorig[:_]")
	var s := re.sub(raw, "")
	s = RegEx.create_from_string("_\\d+$").sub(s, "")
	if OP_MAP.has(s):
		return OP_MAP[s]
	for side in [["Left", "L"], ["Right", "R"]]:
		if s.begins_with(side[0] + "Hand"):
			var rest := s.substr((side[0] + "Hand").length())
			for f in FINGERS:
				if rest.begins_with(f) and rest.length() == f.length() + 1:
					return "%s%s.%s" % [f, rest.substr(f.length()), side[1]]
	return s

## Basis mit Y = y und einer zweiten Achse (X oder Z) aus ref (orthogonalisiert)
static func _frame(y: Vector3, ref: Vector3, ref_is_x: bool) -> Basis:
	var yy := y.normalized()
	var r := (ref - yy * yy.dot(ref))
	if r.length_squared() < 1e-8:
		r = Vector3(1, 0, 0) - yy * yy.x
	r = r.normalized()
	if ref_is_x:
		return Basis(r, yy, r.cross(yy))
	return Basis(yy.cross(r), yy, r)

static func _frame2(d: Vector3, l: Vector3) -> Basis:
	return _frame(d, l, true)

## Querachse fuer die Ausrichtung (gleiche Formel fuer Ziel und Quelle)
static func _lat(kind: String, side: String, P: Callable, dir: Vector3) -> Variant:
	match kind:
		"hips":
			var a: Variant = P.call("UpperLeg.L")
			var b: Variant = P.call("UpperLeg.R")
			return (a - b) if a != null and b != null else Vector3(1, 0, 0)
		"shoulders":
			var a: Variant = P.call("UpperArm.L")
			var b: Variant = P.call("UpperArm.R")
			return (a - b) if a != null and b != null else Vector3(1, 0, 0)
		"elbow", "hand":
			if kind == "hand":
				var ix: Variant = P.call("Index1." + side)
				var pk: Variant = P.call("Pinky1." + side)
				if ix != null and pk != null:
					return ix - pk
			var u0: Variant = P.call("UpperArm." + side)
			var u1: Variant = P.call("LowerArm." + side)
			var u2: Variant = P.call("Wrist." + side)
			if u0 == null or u1 == null or u2 == null:
				return null
			var up: Vector3 = (u1 - u0).normalized()
			var fo: Vector3 = (u2 - u1).normalized()
			var c := up.cross(fo)
			if c.length() > 0.17:   # > ~10 Grad gebeugt
				return c
			return up.cross(FWD)    # gestreckt: Beugung nach vorn angenommen
		"leg":
			return dir.cross(FWD)
		"side":
			return Vector3(1, 0, 0)
	return null

func _init() -> void:
	var src_dir := _arg("src", "")
	if src_dir != "":
		_prepare(src_dir)
		quit()
		return
	var ual := _gltf(UAL)
	var swat := _gltf(SWAT)
	root.add_child(ual)
	root.add_child(swat)
	var srcs := {"ual": _make_src(ual, UAL_MAP, UAL_FINGER, "DEF-hips"), "swat": _make_src(swat, SWAT_MAP, SWAT_FINGER, "Hips")}
	_bake(srcs)
	quit()

func _bake(srcs: Dictionary) -> void:
	var st := GLTFState.new()
	var scene := _gltf(SRC, st)
	root.add_child(scene)
	var sk0: Skeleton3D = _find(scene, "Skeleton3D")
	var A := _chain_xf(sk0.get_parent(), scene)
	var n0 := sk0.get_bone_count()
	var par0 := PackedInt32Array()
	for i in n0:
		par0.append(sk0.get_bone_parent(i))
	var g0rest := _globals(_sample_local(sk0, null, 0.0), par0, _order(par0))
	# --- neues Skelett: kanonische Namen, "Torso" zwischen Abdomen und Chest, Tiefensuche-Reihenfolge ---
	var canon_of := {}
	for i in n0:
		canon_of[i] = _canon_name(sk0.get_bone_name(i))
	var names: Array[String] = []
	var src_of: Array[int] = []     # alter Index (-1 = eingefuegter Torso)
	var parents := PackedInt32Array()
	var stack: Array = []
	for i in n0:
		if par0[i] < 0:
			stack.append([i, -1])
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var oi: int = it[0]
		var np: int = it[1]
		if canon_of[oi] == "Chest":
			names.append("Torso")
			src_of.append(-1)
			parents.append(np)
			np = names.size() - 1
		names.append(canon_of[oi])
		src_of.append(oi)
		parents.append(np)
		var me := names.size() - 1
		for c in range(n0 - 1, -1, -1):
			if par0[c] == oi:
				stack.append([c, me])
	var n := names.size()
	var order := _order(parents)
	var ni := {}
	for i in n:
		ni[names[i]] = i
	var P := {}
	for i in n:
		P[names[i]] = (A * g0rest[src_of[i]]).origin if src_of[i] >= 0 else (A * g0rest[src_of[ni["Chest"]]]).origin
	var Pf := func(nm: String) -> Variant: return P.get(nm, null)
	# kanonische Ruhe-Achsen
	var nrest: Array[Transform3D] = []
	nrest.resize(n)
	var elbow := {}
	for side in ["L", "R"]:
		elbow[side] = _lat("elbow", side, Pf, Vector3.ZERO)
	for i in order:
		var nm := names[i]
		var side := nm.get_slice(".", 1) if nm.contains(".") else ""
		var base := nm.get_slice(".", 0)
		var b := Basis.IDENTITY
		var child := ""
		match base:
			"Hips": child = "Abdomen"
			"Abdomen": child = "Chest"
			"Torso", "Chest": child = "Neck"
			"Neck": child = "Head"
			"Head": child = "HeadTop"
			"Shoulder": child = "UpperArm." + side
			"UpperArm": child = "LowerArm." + side
			"LowerArm": child = "Wrist." + side
			"Wrist": child = "Middle1." + side
			"UpperLeg": child = "LowerLeg." + side
			"LowerLeg": child = "Foot." + side
			"Foot": child = "Toes." + side
			"Toes": child = "ToesEnd." + side
		for f in FINGERS:
			if base.begins_with(f) and base.length() == f.length() + 1:
				child = "%s%d.%s" % [f, int(base.substr(f.length())) + 1, side]
		if child != "" and P.has(child) and P[child].distance_to(P[nm]) > 1e-4:
			var d: Vector3 = P[child] - P[nm]
			match base:
				"UpperArm", "LowerArm":
					b = _frame(d, elbow[side], true)
				"Wrist":
					var ix: Vector3 = P["Index1." + side] - P["Pinky1." + side]
					var s := 1.0 if side == "R" else -1.0
					b = _frame(d, d.cross(ix) * s, false)
				"Foot", "Toes":
					b = _frame(d, Vector3(1, 0, 0), true)
				_:
					var is_finger := false
					for f in FINGERS:
						if base.begins_with(f):
							is_finger = true
					if is_finger:
						b = _frame(d, nrest[ni["Wrist." + side]].basis.x, true)
					else:
						b = _frame(d, FWD, false)
		elif parents[i] >= 0:
			b = nrest[parents[i]].basis
		nrest[i] = Transform3D(b, P[nm])
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for i in n:
		sk.add_bone(names[i])
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

	# --- Kriss Vector (nur Ruhepose-Analyse): Laufachse, Griff-Rahmen der Haende ---
	var gun_pts: Array = []
	var gear_head: Array = []
	for c in scene.find_children("*", "MeshInstance3D", true, false):
		var mn := String((c as MeshInstance3D).mesh.resource_name)
		if mn.contains("KSVR"):
			var xf := _chain_xf(c, scene)
			var am0 := (c as MeshInstance3D).mesh
			for s in am0.get_surface_count():
				for v: Vector3 in am0.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					gun_pts.append(xf * v)
	for c in sk0.get_children():
		if c is MeshInstance3D:
			var mn := String((c as MeshInstance3D).mesh.resource_name)
			if mn.contains("HeadGear") or mn.contains("Body"):
				for p in _rest_points(c, sk0, A, g0rest, canon_of):
					if p[1] == "Head" or p[1] == "HeadTop" or p[1] == "Neck":
						gear_head.append(p)
	_analyse_gun(rig, gun_pts, nrest, ni)
	_analyse_head(rig, gear_head, nrest, ni)

	# --- Meshes (ohne KSVR): LODs, Materialien, Skins neu gebunden ---
	var lod_mesh := {}
	var skin_of := {}
	for c in sk0.get_children():
		if c is MeshInstance3D:
			skin_of[(c as MeshInstance3D).mesh.resource_name] = (c as MeshInstance3D).skin
	for gm: GLTFMesh in st.get_meshes():
		var im: ImporterMesh = gm.mesh
		if im.get_name().contains("KSVR"):
			continue
		if skin_of.has(im.get_name()):
			_add_rest_custom(im, skin_of[im.get_name()], sk0, A, g0rest)
		im.generate_lods(25.0, 60.0, [])
		lod_mesh[im.get_name()] = im
		var per := {}
		for s in im.get_surface_count():
			per[0] = int(per.get(0, 0)) + im.get_surface_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
			for l in im.get_surface_lod_count(s):
				per[l + 1] = int(per.get(l + 1, 0)) + im.get_surface_lod_indices(s, l).size() / 3
		print("LOD-Dreiecke %s: %s" % [im.get_name(), per])
	var tris := {}
	for c in sk0.get_children():
		if not (c is MeshInstance3D):
			continue
		var mi0 := c as MeshInstance3D
		var src_mesh: Mesh = mi0.mesh
		if String(src_mesh.resource_name).contains("KSVR"):
			continue
		var am: ArrayMesh = (lod_mesh[src_mesh.resource_name] as ImporterMesh).get_mesh()
		var short := "Body" if String(src_mesh.resource_name).contains("Body") else ("HeadGear" if String(src_mesh.resource_name).contains("HeadGear") else "Eyelashes")
		for s in am.get_surface_count():
			am.surface_set_material(s, _material(short))
		am.resource_name = short
		var mi := MeshInstance3D.new()
		mi.name = short
		mi.mesh = am
		var skin0: Skin = mi0.skin
		var skin := Skin.new()
		for j in skin0.get_bind_count():
			var bn := String(skin0.get_bind_name(j))
			var b := sk0.find_bone(bn) if bn != "" else skin0.get_bind_bone(j)
			var nb: int = ni[canon_of[b]]
			var bp: Transform3D = nrest[nb].affine_inverse() * A * g0rest[b] * skin0.get_bind_pose(j)
			skin.add_named_bind(names[nb], bp)
		mi.skin = skin
		sk.add_child(mi)
		mi.owner = rig
		mi.skeleton = NodePath("..")
		var t := 0
		for s in am.get_surface_count():
			t += am.surface_get_array_index_len(s) / 3
		tris[mi.name] = t
	print("Dreiecke LOD0: %s" % [tris])

	# --- Retarget-Vorbereitung je Quelle: Ziel in Quell-Ruhepose (Zwei-Richtungs-Ausrichtung) ---
	var hips: int = ni["Hips"]
	var foot := [ni["Foot.L"], ni["Foot.R"]]
	var toes := [ni["Toes.L"], ni["Toes.R"]]
	var align := {}
	for a in ALIGN:
		align[a[0]] = a
	var leg_t := 0.0
	for side in ["L", "R"]:
		leg_t += P["UpperLeg." + side].distance_to(P["LowerLeg." + side]) + P["LowerLeg." + side].distance_to(P["Foot." + side])
	var prep := {}
	for key in srcs:
		var s: Src = srcs[key]
		var Sf := func(nm: String) -> Variant: return _src_pos(s, nm)
		var idx := {}
		for i in n:
			if s.map.has(names[i]):
				var si := s.sk.find_bone(s.map[names[i]])
				if si >= 0:
					idx[i] = si
				else:
					push_warning("%s: Quellknochen fehlt %s" % [key, s.map[names[i]]])
		var leg_s := 0.0
		for side in ["L", "R"]:
			leg_s += (Sf.call("UpperLeg." + side) as Vector3).distance_to(Sf.call("LowerLeg." + side)) + (Sf.call("LowerLeg." + side) as Vector3).distance_to(Sf.call("Foot." + side))
		var k := leg_t / leg_s
		var tp: Array[Transform3D] = []
		tp.resize(n)
		var Q: Array[Basis] = []
		Q.resize(n)
		for i in order:
			var t: Transform3D = lrest[i] if parents[i] < 0 else tp[parents[i]] * lrest[i]
			var qp: Basis = Basis.IDENTITY if parents[i] < 0 else Q[parents[i]]
			if align.has(names[i]):
				var spec: Array = align[names[i]]
				var side := names[i].get_slice(".", 1) if names[i].contains(".") else ""
				var ps: Variant = Sf.call(names[i])
				var cs: Variant = Sf.call(spec[1])
				if ps != null and cs != null and P.has(spec[1]):
					var ds: Vector3 = cs - ps
					var dt: Vector3 = qp * (P[spec[1]] - P[names[i]])
					var ls: Variant = _lat(spec[2], side, Sf, ds)
					var lt0: Variant = _lat(spec[2], side, Pf, P[spec[1]] - P[names[i]])
					if ls != null and lt0 != null:
						var lt: Vector3 = qp * (lt0 as Vector3)
						var R := _frame2(ds, ls) * _frame2(dt, lt).inverse()
						t.basis = (R * t.basis).orthonormalized()
			tp[i] = t
			Q[i] = (t.basis * nrest[i].basis.inverse()).orthonormalized()
		# Huefte so setzen, dass die (gestreckten) Fuesse der Quell-Ruhepose genau auf dem Boden stehen
		var gnd := [nrest[foot[0]].origin.y, nrest[foot[1]].origin.y, nrest[toes[0]].origin.y, nrest[toes[1]].origin.y]
		var clr := 99.0
		for j in 2:
			clr = minf(clr, minf(tp[foot[j]].origin.y - gnd[j], tp[toes[j]].origin.y - gnd[2 + j]))
		for i in n:
			if parents[i] >= 0:
				tp[i].origin.y -= clr
		print("%s: Bein Ziel %.3f Quelle %.3f k=%.3f, Huefte Ziel(Ruhe) %.3f -> %.3f" % [key, leg_t, leg_s, k, nrest[hips].origin.y, tp[hips].origin.y])
		prep[key] = {"idx": idx, "tp": tp, "k": k}

	var lib := AnimationLibrary.new()
	var speeds := {}
	var ground := [nrest[foot[0]].origin.y, nrest[foot[1]].origin.y, nrest[toes[0]].origin.y, nrest[toes[1]].origin.y]
	print("Boden-Referenz (Ruhe): Knoechel %.3f/%.3f Zehen %.3f/%.3f" % ground)
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
			if parents[i] < 0 or not idx.has(i):
				continue
			rt[i] = a.add_track(Animation.TYPE_ROTATION_3D)
			a.track_set_path(rt[i], NodePath("Skeleton3D:" + names[i]))
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
		var rec := [[], []]
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
			var clear := 99.0
			var fc := [99.0, 99.0]
			for j in 2:
				fc[j] = minf(g[foot[j]].origin.y - ground[j], g[toes[j]].origin.y - ground[2 + j])
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
		if spec[3] and not speeds.has(spec[0]):
			var vs: Array[float] = []
			for tol in [0.02, 0.04, 0.07]:
				if vs.size() > 2:
					break
				vs.clear()
				for j in 2:
					var mn := 99.0
					for r in rec[j]:
						mn = minf(mn, r[0])
					for fi in range(1, rec[j].size()):
						if rec[j][fi][0] < mn + tol and rec[j][fi - 1][0] < mn + tol:
							vs.append(-(rec[j][fi][1] - rec[j][fi - 1][1]) * FPS)
			if vs.size() > 2:
				vs.sort()
				speeds[spec[0]] = vs[vs.size() / 2]
		if OS.get_cmdline_user_args().has("--dump=" + String(spec[0])):
			for fi in rec[0].size():
				print("  f%02d L %.3f z %.3f | R %.3f z %.3f" % [fi, rec[0][fi][0], rec[0][fi][1], rec[1][fi][0], rec[1][fi][1]])
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
			print("%s: Tempo x%.2f (natuerlich %.2f m/s -> %.2f m/s)" % [spec[0], 1.0 / fac, natural, spec[5]])
		lib.add_animation(spec[0], a)
		print("%-12s <- %-28s len=%.2f speed=%.2f foot_clear=[%.3f..%.3f]" % [spec[0], spec[2], sa.length, speeds.get(spec[0], 0.0), low, high])

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	ap.add_animation_library("", lib)
	rig.add_child(ap)
	ap.owner = rig
	rig.set_meta("loco_speed", speeds)
	rig.set_meta("kind", "op")
	var ps := PackedScene.new()
	ps.pack(rig)
	var err := ResourceSaver.save(ps, OUT, ResourceSaver.FLAG_COMPRESS)
	print("gespeichert %s err=%d (%d Knochen)" % [OUT, err, n])
	for nm in ["Root", "Hips", "Abdomen", "Torso", "Chest", "Neck", "Head", "HeadTop", "Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R", "Wrist.L", "UpperLeg.L", "LowerLeg.L", "Foot.L", "Toes.L"]:
		if ni.has(nm):
			var b: Transform3D = nrest[ni[nm]]
			print("  rest %-11s pos=%s x=%s y=%s z=%s" % [nm, b.origin, b.basis.x, b.basis.y, b.basis.z])
	scene.queue_free()

## Waffe in der Ruhepose: Hauptachse der Vector-Punkte = Lauf (nach vorn, +Z), Waffen-Rahmen wie im Spiel
## (Lauf -Z, oben +Y). Gespeichert wird die Lage beider Haende relativ zu diesem Rahmen (Ursprung: Mitte
## der rechten Handflaeche auf die Laufachse projiziert) -> Startwerte fuer grip_r/grip_l.
func _analyse_gun(rig: Node3D, pts: Array, nrest: Array[Transform3D], ni: Dictionary) -> void:
	if pts.size() < 10:
		print("keine Waffe in der Ruhepose gefunden")
		return
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= pts.size()
	# Kovarianz -> Hauptachse (Potenzmethode)
	var cov := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for p: Vector3 in pts:
		var d := p - c
		cov.x += d * d.x
		cov.y += d * d.y
		cov.z += d * d.z
	var ax := Vector3(0, 0, 1)
	for it in 50:
		ax = (cov * ax).normalized()
	if ax.z < 0.0:
		ax = -ax
	var lo := 1e9
	var hi := -1e9
	for p: Vector3 in pts:
		var t := (p - c).dot(ax)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	var wb := Basis.looking_at(ax, Vector3.UP)   # -Z = Lauf
	var hr: Transform3D = nrest[ni["Wrist.R"]]
	var hl: Transform3D = nrest[ni["Wrist.L"]]
	var palm_r := (hr.origin + nrest[ni["Middle1.R"]].origin) * 0.5
	var o := c + ax * (palm_r - c).dot(ax)
	var W := Transform3D(wb, o)
	var gr := W.affine_inverse() * hr
	var gl := W.affine_inverse() * hl
	rig.set_meta("grip_r", gr)
	rig.set_meta("grip_l", gl)
	print("Waffe Ruhepose: Mitte %s Achse %s Laenge %.3f (%.3f..%.3f), Handflaeche R %s" % [c, ax, hi - lo, lo, hi, palm_r])
	print("  grip_r (Waffenraum) = %s" % [gr])
	print("  grip_l (Waffenraum) = %s" % [gl])
	print("  Hand R fingers(W)=%s back(W)=%s | L fingers(W)=%s back(W)=%s" % [gr.basis.y, gr.basis.z, gl.basis.y, gl.basis.z])

## Helm/Kopf: Ausdehnung der Kopf-Vertices (Ruhepose) -> Kopf-Hitbox (Meta "head_box": Mitte relativ zum Kopfknochen, Radien)
func _analyse_head(rig: Node3D, pts: Array, nrest: Array[Transform3D], ni: Dictionary) -> void:
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for p in pts:
		var v: Vector3 = p[0]
		if v.y < 1.45:
			continue
		lo = lo.min(v)
		hi = hi.max(v)
	var hb: Transform3D = nrest[ni["Head"]]
	var cen := (lo + hi) * 0.5
	rig.set_meta("head_box", [hb.affine_inverse() * cen, (hi - lo) * 0.5])
	print("Kopf/Helm Ruhepose: %s .. %s Mitte %s (Kopfknochen %s) -> lokal %s" % [lo, hi, cen, hb.origin, hb.affine_inverse() * cen])
