class_name SoldierVisual
extends Node3D
## Sichtbarer Soldat (Rifleman/Heavy): geriggtes Modell + AnimationTree + Oberkoerper-IK +
## Waffe an der rechten Hand + Ragdoll (PhysicalBoneSimulator3D) beim Tod.
## Wird von Enemy._build_body() erzeugt; liest Zustand direkt aus dem Enemy (keine KI-Logik hier).
## Rig/Animationen: assets/characters/soldier/soldier_rig.scn (gebacken mit tools/bake_soldier.gd).

const RIG_PATH := "res://assets/characters/soldier/soldier_rig.scn"
const RIFLE_PATH := "res://assets/characters/weapons/rifle_ar_west.glb"
const MG_PATH := "res://assets/characters/weapons/rifle_ar_quaternius.glb"
## Fraktion "reich" (fiktive Ordnungsfront): Armbinde mit erfundenem Emblem (gebrochener Ring + Klinge)
const REICH_ARMBAND_TEX := "res://assets/characters/faction/reich_armband.png"
const REICH_EMBLEM_TEX := "res://assets/environment/berlin/emblem.png"
const SG = preload("res://game/enemies/soldier_gear.gd")
const MAX_RAGDOLLS := 10
const RELOAD_TIME := 2.3

const LOCO_POINTS := [
	["idle", Vector2(0, 0)], ["walk", Vector2(0, 2.4)], ["run_fwd", Vector2(0, 4.2)],
	["run_back", Vector2(0, -2.6)], ["run_left", Vector2(-2.6, 0)], ["run_right", Vector2(2.6, 0)],
]
const HIT_BONES := ["Hips", "Abdomen", "Torso", "Chest", "Neck", "Head"]
## Ragdoll: [Knochen, End-Knochen (Laenge), Radius, Masse, Gelenk ("root"/"cone"/"hinge"), swing, twist]
const RAGDOLL := [
	["Body", "Abdomen", 0.15, 12.0, "root", 0.0, 0.0],
	["Torso", "Neck", 0.16, 16.0, "cone", 25.0, 15.0],
	["Head", "", 0.12, 4.5, "cone", 35.0, 25.0],
	["UpperArm.L", "LowerArm.L", 0.055, 2.5, "cone", 75.0, 25.0],
	["UpperArm.R", "LowerArm.R", 0.055, 2.5, "cone", 75.0, 25.0],
	["LowerArm.L", "Wrist.L", 0.045, 1.8, "hinge", 0.0, 135.0],
	["LowerArm.R", "Wrist.R", 0.045, 1.8, "hinge", 0.0, 135.0],
	["UpperLeg.L", "LowerLeg.L", 0.085, 8.0, "cone", 55.0, 15.0],
	["UpperLeg.R", "LowerLeg.R", 0.085, 8.0, "cone", 55.0, 15.0],
	["LowerLeg.L", "Foot.L", 0.065, 4.0, "hinge", 0.0, 130.0],
	["LowerLeg.R", "Foot.R", 0.065, 4.0, "hinge", 0.0, 130.0],
]

static var _tree_root: AnimationNodeBlendTree = null
static var _mat_cache: Dictionary = {}
static var _weapon_cache: Dictionary = {}
static var active_ragdolls: int = 0

var enemy: Enemy = null
var heavy: bool = false
var vis_scale: float = 1.0
var rig: Node3D = null
var skeleton: Skeleton3D = null
var anim_tree: AnimationTree = null
var ik: SoldierIK = null
var weapon: Node3D = null
var muzzle: Node3D = null
var flash_light: OmniLight3D = null
var head_attach: BoneAttachment3D = null
var sim: PhysicalBoneSimulator3D = null
var bones: Array[PhysicalBone3D] = []

var _flash_mesh: MeshInstance3D = null
var _weapon_attach: BoneAttachment3D = null
var _loco := Vector2.ZERO
var _last_flinch: float = 0.0
var _aim_w: float = 0.0
var _reload_left: float = -1.0
var _shots_at_reload: int = 0
var _mag_size: int = 30
var _dead: bool = false
var _death_t: float = 0.0
var _ragdoll_at: float = -1.0
var _ragdoll_on: bool = false
var _pending_impulse: bool = false
var _explosive: bool = false
var _counted: bool = false
var _meshes: Array[GeometryInstance3D] = []
var _weapon_body: RigidBody3D = null

func setup(e: Enemy) -> void:
	enemy = e
	heavy = e.heavy_armor
	vis_scale = 1.1 if heavy else 1.0
	_mag_size = 100 if heavy else 30
	name = "Visual"
	rig = (load(RIG_PATH) as PackedScene).instantiate() as Node3D
	add_child(rig)
	rig.rotation.y = PI  # Modell blickt nach +Z, Gegner nach -Z
	rig.scale = Vector3.ONE * vis_scale
	skeleton = rig.get_node("Skeleton3D") as Skeleton3D
	_apply_materials()
	_build_gear()
	_build_weapon()
	_build_tree()
	ik = SoldierIK.new()
	ik.name = "SoldierIK"
	skeleton.add_child(ik)
	_config_ik()
	head_attach = _attach("Head")

# ---------------------------------------------------------------- Aufbau

func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = "BA_" + bone.replace(".", "_")
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba

func _apply_materials() -> void:
	var reich := enemy.faction == "reich"
	var key := "%s|%s|%s|%s" % [enemy.enemy_type, enemy.color_primary.to_html(), enemy.color_secondary.to_html(), enemy.faction]
	if not _mat_cache.has(key):
		var m := {}
		var fat := enemy.color_primary.lerp(enemy.color_secondary, 0.35) * 1.35
		var gear := enemy.color_secondary * 0.55
		m["Swat"] = _std(Color(fat.r, fat.g, fat.b), 0.9)
		m["Swat_Black"] = _std(Color(gear.r, gear.g, gear.b), 0.75)
		m["Visor"] = _std(Color(0.05, 0.06, 0.07), 0.15, 0.6)
		m["armband"] = _std(enemy.color_armband, 0.6)
		(m["armband"] as StandardMaterial3D).emission_enabled = true
		(m["armband"] as StandardMaterial3D).emission = enemy.color_armband
		(m["armband"] as StandardMaterial3D).emission_energy_multiplier = 0.35
		m["plate"] = _std(enemy.color_secondary * 0.8, 0.55, 0.25)
		m["dark"] = _std(Color(0.07, 0.07, 0.08), 0.5, 0.3)
		if reich:
			_reich_materials(m)
		if SG.CAMO_TEX.has(enemy.faction):
			# Realistischer Stoff: Tarnmuster (Ruhepose-triplanar) + Gewebe-Normalen, Ausruestung als Cordura
			var gc := SG.gear_colors(enemy.faction)
			m["Swat"] = SG.cloth_mat(enemy.faction, 0, Color.WHITE)
			m["Swat_Black"] = SG.cloth_mat(enemy.faction, 1, gc[0].lerp(gc[1], 0.55 if heavy else 0.35), "heavy" if heavy else "")
			m["Skin"] = SG.cloth_mat(enemy.faction, 1, gc[0].lerp(gc[1], 0.15) * 1.1, "carrier")   # Plattentraeger/Hemd
			m["plate"] = SG.flat_gear(gc[0].lerp(gc[2], 0.5), 0.6 if not reich else 0.45, 0.0 if not reich else 0.3)
			m["dark"] = SG.flat_gear(gc[1], 0.8)
		_mat_cache[key] = m
	var mats: Dictionary = _mat_cache[key]
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			SG.prepare_mesh(mi, skeleton)
			_meshes.append(mi)
			for s in mi.mesh.get_surface_count():
				var sm := mi.mesh.surface_get_material(s)
				if sm != null and mats.has(sm.resource_name):
					mi.set_surface_override_material(s, mats[sm.resource_name])
	set_meta("mats", mats)

## Ordnungsfront: stahlgrauer Helm/Ausruestung (leicht metallisch), Armbinde Amber mit Emblem-Textur,
## kleines leuchtendes Brustabzeichen (damit die dunklen Uniformen nachts lesbar bleiben).
func _reich_materials(m: Dictionary) -> void:
	m["Swat_Black"] = _std(Color(0.2, 0.21, 0.23), 0.45, 0.4)
	var band := _std(Color.WHITE, 0.55)
	if ResourceLoader.exists(REICH_ARMBAND_TEX):
		var tex: Texture2D = load(REICH_ARMBAND_TEX)
		band.albedo_texture = tex
		band.emission_enabled = true
		band.emission_texture = tex
		band.emission = Color.WHITE
		band.emission_energy_multiplier = 0.45
		band.uv1_scale = Vector3(1.0, 2.0, 1.0)   # CylinderMesh: Mantel liegt in v 0..0.5
	else:
		band.albedo_color = enemy.color_armband
	m["armband"] = band
	var patch := StandardMaterial3D.new()
	patch.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	patch.alpha_scissor_threshold = 0.4
	patch.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(REICH_EMBLEM_TEX):
		var et: Texture2D = load(REICH_EMBLEM_TEX)
		patch.albedo_texture = et
		patch.emission_enabled = true
		patch.emission_texture = et
		patch.emission_energy_multiplier = 1.2
	else:
		patch.albedo_color = enemy.color_armband
	m["patch"] = patch

func _std(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	_meshes.append(mi)
	return mi

func _boxm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b

func _cyl(r_top: float, r_bot: float, h: float, seg: int = 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

func _build_gear() -> void:
	var mats: Dictionary = get_meta("mats")
	# Fraktions-Armbinden (ru: nur Farbe; reich: fiktives Emblem der Ordnungsfront)
	for side in ["L", "R"]:
		var ba := _attach("UpperArm." + side)
		_part(ba, _cyl(0.066, 0.064, 0.075), mats["armband"], Vector3(0, 0.13, 0))
	if mats.has("patch"):
		var q := QuadMesh.new()
		q.size = Vector2(0.075, 0.075)
		var cp := _attach("Chest")
		var pm := _part(cp, q, mats["patch"], Vector3(0.07, -0.02, 0.142 if heavy else 0.122), Vector3(-0.1, 0, 0))
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_build_kit()
	if not heavy:
		return
	var plate: Material = mats["plate"]
	var dark: Material = mats["dark"]
	var ch := _attach("Chest")
	_part(ch, _boxm(Vector3(0.29, 0.27, 0.045)), plate, Vector3(0, -0.05, 0.115), Vector3(-0.1, 0, 0))   # Brustplatte
	_part(ch, _boxm(Vector3(0.25, 0.08, 0.035)), dark, Vector3(0, -0.17, 0.13), Vector3(-0.1, 0, 0))     # Magazintaschen
	_part(ch, _boxm(Vector3(0.29, 0.29, 0.045)), plate, Vector3(0, -0.04, -0.1))                          # Rueckenplatte
	_part(ch, _boxm(Vector3(0.24, 0.26, 0.11)), dark, Vector3(0, -0.07, -0.175))                         # Munitionsrucksack
	_part(ch, _cyl(0.1, 0.125, 0.06, 14), plate, Vector3(0, 0.12, 0.01), Vector3(-0.12, 0, 0))           # Kragen
	for side in ["L", "R"]:
		var sh := _attach("UpperArm." + side)
		var sm := SphereMesh.new()
		sm.radius = 0.075
		sm.height = 0.15
		sm.radial_segments = 12
		sm.rings = 6
		_part(sh, sm, plate, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.1))                    # Schulterpanzer
	var hd := _attach("Head")
	_part(hd, _boxm(Vector3(0.16, 0.11, 0.018)), mats["Visor"], Vector3(0, 0.02, 0.115), Vector3(0.25, 0, 0))  # Gesichtsschild

## Zusatz-Ausruestung (soldier_gear.gd): je Baugruppe ein Mesh an einem ruhepose-ausgerichteten Rahmen.
func _build_kit() -> void:
	var gm := SG.gear_mat(enemy.faction)
	for grp: String in SG.REST_ORIGIN:
		var spec: Array = SG.REST_ORIGIN[grp]
		var bi := skeleton.find_bone(spec[0])
		if bi < 0:
			continue
		var ba := _attach(spec[0])
		var frame := Node3D.new()
		frame.name = "Kit_" + grp
		frame.transform = skeleton.get_bone_global_rest(bi).affine_inverse() * Transform3D(Basis.IDENTITY, spec[1])
		ba.add_child(frame)
		var k := SG.MK.new()
		match grp:
			"chest":
				SG.build_chest(k, enemy.faction, heavy)
			"hips":
				SG.build_hips(k, enemy.faction)
			"head":
				SG.build_head(k, enemy.faction)
		var mi := k.emit(frame, gm, "Kit")
		_meshes.append(mi)

## Waffe: Modell normalisiert (Lauf -Z, oben +Y, Ursprung oben am Pistolengriff).
func _weapon_model() -> Dictionary:
	var key := "mg" if heavy else "rifle"
	if _weapon_cache.has(key):
		return _weapon_cache[key]
	var d := {}
	var src := (load(MG_PATH if heavy else RIFLE_PATH) as PackedScene).instantiate()
	var mi: MeshInstance3D = null
	var xf := Transform3D.IDENTITY
	var stack: Array = [[src, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var nd: Node = it[0]
		var t: Transform3D = it[1]
		if nd is Node3D:
			t = t * (nd as Node3D).transform
		if nd is MeshInstance3D:
			mi = nd
			xf = t
			break
		for c in nd.get_children():
			stack.append([c, t])
	d["mesh"] = mi.mesh
	if heavy:
		# Quaternius-Gewehr: Lauf entlang +X, Laenge 5.17 Einheiten -> 0.9 m
		var s := 0.9 / 5.17
		var norm := Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * s), Vector3.ZERO)
		var grip := norm * Vector3(-0.2, 0.32, 0.0)
		d["xf"] = Transform3D(Basis(), -grip) * norm * xf
		d["muzzle"] = norm * Vector3(3.62, 0.66, 0.0) - grip
		d["stock"] = 1.56 * s + grip.z
	else:
		# West-Gewehr: bereits Meter, Lauf -Z, 0.70 m (Arme des Low-Poly-Modells sind kurz)
		var s := 1.0
		var grip := Vector3(0, -0.045, 0.09) * s
		d["xf"] = Transform3D(Basis().scaled(Vector3.ONE * s), -grip) * xf
		d["muzzle"] = Vector3(0, 0.016, -0.345) * s - grip
		d["stock"] = 0.355 * s - grip.z
	src.free()
	_weapon_cache[key] = d
	return d

func _build_weapon() -> void:
	var wm := _weapon_model()
	var mats: Dictionary = get_meta("mats")
	weapon = Node3D.new()
	weapon.name = "Weapon"
	var model := MeshInstance3D.new()
	model.mesh = wm["mesh"]
	model.transform = wm["xf"]
	weapon.add_child(model)
	_meshes.append(model)
	if heavy:
		var dark: Material = mats["dark"]
		var plate: Material = mats["plate"]
		_part(weapon, _boxm(Vector3(0.06, 0.09, 0.11)), plate, Vector3(-0.055, -0.07, -0.09))                 # Munitionskasten
		_part(weapon, _boxm(Vector3(0.025, 0.02, 0.09)), dark, Vector3(-0.03, 0.0, -0.09), Vector3(0, 0, 0.6)) # Gurt
		_part(weapon, _cyl(0.026, 0.026, 0.42, 10), dark, Vector3(0, 0.115, -0.47), Vector3(PI * 0.5, 0, 0))  # Laufmantel
		for sx in [-1.0, 1.0]:
			_part(weapon, _cyl(0.008, 0.008, 0.3, 6), dark, Vector3(sx * 0.03, 0.07, -0.5), Vector3(PI * 0.5 + 0.12, 0, sx * 0.08))  # Zweibein
	muzzle = Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = wm["muzzle"]
	weapon.add_child(muzzle)
	flash_light = OmniLight3D.new()
	flash_light.light_color = Color(1.0, 0.75, 0.35)
	flash_light.omni_range = 5.0
	flash_light.light_energy = 0.0
	flash_light.shadow_enabled = false
	muzzle.add_child(flash_light)
	_flash_mesh = MeshInstance3D.new()
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.albedo_color = Color(1.0, 0.7, 0.3, 0.9)
	fm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.3)
	q.center_offset = Vector3(0, 0.15, 0)
	_flash_mesh.mesh = q
	_flash_mesh.material_override = fm
	_flash_mesh.rotation = Vector3(-PI * 0.5, 0, 0)
	_flash_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.visible = false
	muzzle.add_child(_flash_mesh)
	var q2 := MeshInstance3D.new()
	q2.mesh = q
	q2.material_override = fm
	q2.rotation = Vector3(0, PI * 0.5, 0)
	q2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash_mesh.add_child(q2)
	_weapon_attach = _attach("Wrist.R")
	_weapon_attach.add_child(weapon)

func _config_ik() -> void:
	var wm := _weapon_model()
	ik.stock_length = wm["stock"]
	if heavy:
		ik.grip_r = Transform3D(SoldierIK.hand_basis(Vector3(-0.15, 0.3, -1.0), Vector3(1.0, 0.15, 0.05)), Vector3(0.025, -0.075, 0.085))
		ik.grip_l = Transform3D(SoldierIK.hand_basis(Vector3(0.3, 0.5, -0.8), Vector3(-0.6, -0.8, 0.0)), Vector3(-0.045, 0.0, -0.24))
	else:
		ik.grip_r = Transform3D(SoldierIK.hand_basis(Vector3(-0.15, 0.3, -1.0), Vector3(1.0, 0.15, 0.05)), Vector3(0.025, -0.075, 0.085))
		ik.grip_l = Transform3D(SoldierIK.hand_basis(Vector3(0.3, 0.5, -0.8), Vector3(-0.6, -0.8, 0.0)), Vector3(-0.04, -0.05, -0.2))
	weapon.transform = ik.grip_r.affine_inverse()

func _build_tree() -> void:
	if _tree_root == null:
		_tree_root = _make_tree_root()
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	rig.add_child(anim_tree)
	anim_tree.anim_player = NodePath("../AnimationPlayer")
	anim_tree.tree_root = _tree_root
	anim_tree.active = true
	anim_tree.set("parameters/life/transition_request", "alive")

static func _anim(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a

static func _make_tree_root() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-5, -5)
	loco.max_space = Vector2(5, 5)
	for p in LOCO_POINTS:
		loco.add_blend_point(_anim(p[0]), p[1], -1, StringName(p[0]))
	bt.add_node("loco", loco, Vector2(0, 0))
	var cr := AnimationNodeBlendSpace1D.new()
	cr.min_space = 0.0
	cr.max_space = 4.0
	cr.add_blend_point(_anim("crouch_idle"), 0.0, -1, &"crouch_idle")
	cr.add_blend_point(_anim("crouch_walk"), 1.6, -1, &"crouch_walk")
	bt.add_node("crouch", cr, Vector2(0, 200))
	bt.add_node("crouch_mix", AnimationNodeBlend2.new(), Vector2(250, 100))
	var hs := AnimationNodeTransition.new()
	for h in ["hit_1", "hit_2", "hit_3"]:
		hs.add_input(h)
	bt.add_node("hit_sel", hs, Vector2(250, 300))
	for h in ["hit_1", "hit_2", "hit_3"]:
		bt.add_node("a_" + h, _anim(h), Vector2(0, 350))
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.06
	hit.fadeout_time = 0.22
	hit.filter_enabled = true
	for b in HIT_BONES:
		hit.set_filter_path(NodePath("Skeleton3D:" + b), true)
	bt.add_node("hit", hit, Vector2(500, 150))
	var life := AnimationNodeTransition.new()
	life.xfade_time = 0.12
	for l in ["alive", "death_1", "death_2"]:
		life.add_input(l)
	bt.add_node("life", life, Vector2(750, 150))
	bt.add_node("a_death_1", _anim("death_1"), Vector2(500, 350))
	bt.add_node("a_death_2", _anim("death_2"), Vector2(500, 450))
	bt.connect_node("crouch_mix", 0, "loco")
	bt.connect_node("crouch_mix", 1, "crouch")
	for i in 3:
		bt.connect_node("hit_sel", i, "a_hit_%d" % (i + 1))
	bt.connect_node("hit", 0, "crouch_mix")
	bt.connect_node("hit", 1, "hit_sel")
	bt.connect_node("life", 0, "hit")
	bt.connect_node("life", 1, "a_death_1")
	bt.connect_node("life", 2, "a_death_2")
	bt.connect_node("output", 0, "life")
	return bt

# ---------------------------------------------------------------- Laufzeit

## Pro Physik-Frame vom Enemy aufgerufen (nur lebend).
func tick(delta: float) -> void:
	var e := enemy
	var lv := e.global_transform.basis.inverse() * e.velocity
	var target_loco := Vector2(lv.x, -lv.z) / maxf(e.body_scale, 0.01)
	_loco = _loco.lerp(target_loco, clampf(delta * 8.0, 0.0, 1.0))
	anim_tree.set("parameters/loco/blend_position", _loco)
	anim_tree.set("parameters/crouch/blend_position", _loco.length())
	anim_tree.set("parameters/crouch_mix/blend_amount", e._stance)
	if e._flinch > _last_flinch + 0.3:
		anim_tree.set("parameters/hit_sel/transition_request", "hit_%d" % e.rng.randi_range(1, 3))
		anim_tree.set("parameters/hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_last_flinch = e._flinch
	# Zielen
	var aiming := e._aim_at_target and e._player != null and is_instance_valid(e._player) and (e._los or e._has_last_known)
	var yaw := 0.0
	var pitch := 0.0
	if aiming:
		var tp := e._player_chest() if e._los else e._last_known
		var sk_inv := skeleton.global_transform.affine_inverse()
		var local := sk_inv * tp
		var from := skeleton.get_bone_global_pose(ik._b.get("Chest", 0)).origin if ik._ok else Vector3(0, 1.35, 0)
		var d := local - from
		yaw = clampf(atan2(d.x, d.z), -1.1, 1.1)
		pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.1, 1.1)
	var want_aim := 1.0 if aiming or e._burst_left > 0 else 0.0
	if _reload_left > 0.0:
		want_aim = 0.6
	_aim_w = move_toward(_aim_w, want_aim, delta * 3.5)
	var k := clampf(delta * 9.0, 0.0, 1.0)
	ik.aim_yaw = lerpf(ik.aim_yaw, yaw, k)
	ik.aim_pitch = lerpf(ik.aim_pitch, pitch, k)
	ik.aim_weight = smoothstep(0.0, 1.0, _aim_w)
	ik.recoil = e._recoil
	# Nachladen (rein optisch): nach einem Magazin, wenn gerade nicht geschossen wird
	if _reload_left > 0.0:
		_reload_left -= delta
		if e._burst_left > 0 and _reload_left < RELOAD_TIME * 0.7:
			_reload_left = -1.0
		ik.reload_t = 1.0 - _reload_left / RELOAD_TIME if _reload_left > 0.0 else -1.0
		if _reload_left <= 0.0:
			_shots_at_reload = e.stat_shots
	elif e._burst_left == 0 and e.stat_shots - _shots_at_reload >= _mag_size:
		start_reload()
	else:
		ik.reload_t = -1.0
	# Muendungsfeuer
	var flash := e._flash_timer > 0.0
	_flash_mesh.visible = flash
	if flash:
		_flash_mesh.rotation.y = e.rng.randf() * TAU
		_flash_mesh.scale = Vector3.ONE * e.rng.randf_range(0.7, 1.2)

func start_reload() -> void:
	_reload_left = RELOAD_TIME
	_shots_at_reload = enemy.stat_shots

# ---------------------------------------------------------------- Tod / Ragdoll

func die(explosive: bool) -> void:
	if _dead:
		return
	_dead = true
	_explosive = explosive
	_flash_mesh.visible = false
	flash_light.light_energy = 0.0
	var can_ragdoll := active_ragdolls < MAX_RAGDOLLS
	if can_ragdoll:
		active_ragdolls += 1
		_counted = true
	_drop_weapon()
	if can_ragdoll and (explosive or enemy._last_hit_head):
		_start_ragdoll()
	else:
		anim_tree.set("parameters/life/transition_request", "death_%d" % enemy.rng.randi_range(1, 2))
		ik.active = false
		_ragdoll_at = 0.3 if can_ragdoll else -1.0
	set_physics_process(true)
	# Ausblenden
	var tw := create_tween()
	tw.set_parallel(true)
	var fade_dur := maxf(enemy.cleanup_time - enemy.fade_start - 0.3, 0.2)
	for m in _meshes:
		if is_instance_valid(m):
			tw.tween_property(m, "transparency", 1.0, fade_dur).set_delay(enemy.fade_start)

func _exit_tree() -> void:
	if _counted:
		active_ragdolls = maxi(active_ragdolls - 1, 0)
		_counted = false

func _physics_process(delta: float) -> void:
	if not _dead:
		set_physics_process(false)
		return
	_death_t += delta
	if _ragdoll_at > 0.0 and _death_t >= _ragdoll_at and not _ragdoll_on:
		_start_ragdoll()
	if _pending_impulse:
		_pending_impulse = false
		_apply_death_impulse()
	if _ragdoll_on and _death_t > 5.0:
		for pb in bones:
			pb.linear_damp = 3.0
			pb.angular_damp = 6.0
		set_physics_process(false)

func _start_ragdoll() -> void:
	if _ragdoll_on:
		return
	_ragdoll_on = true
	if not _counted:
		return
	ik.active = false
	anim_tree.active = false
	sim = PhysicalBoneSimulator3D.new()
	sim.name = "Ragdoll"
	skeleton.add_child(sim)
	var sk_g := skeleton.global_transform
	for r in RAGDOLL:
		var bi := skeleton.find_bone(r[0])
		if bi < 0:
			continue
		var g_rest := skeleton.get_bone_global_rest(bi)
		var end_local := Vector3(0, 0.2, 0)
		if r[1] != "":
			var ei := skeleton.find_bone(r[1])
			end_local = g_rest.affine_inverse() * skeleton.get_bone_global_rest(ei).origin
			if r[0].begins_with("LowerArm"):
				end_local *= 1.3
		var length := end_local.length()
		var dir := end_local / maxf(length, 0.001)
		var pb := PhysicalBone3D.new()
		pb.name = "PB_" + String(r[0]).replace(".", "_")
		pb.bone_name = r[0]
		pb.collision_layer = Enemy.LAYER_DEBRIS
		pb.collision_mask = Enemy.LAYER_WORLD
		pb.mass = r[3]
		pb.friction = 0.9
		pb.bounce = 0.05
		pb.linear_damp = 0.05
		pb.angular_damp = 0.9
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = r[2]
		cap.height = maxf(length + r[2] * 0.6, r[2] * 2.0 + 0.01)
		cs.shape = cap
		cs.transform = Transform3D(Basis(Quaternion(Vector3.UP, dir)), end_local * 0.5)
		pb.add_child(cs)
		match String(r[4]):
			"cone":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
				pb.joint_rotation = Basis(Quaternion(Vector3.RIGHT, dir)).get_euler()
				pb.set("joint_constraints/swing_span", r[5])
				pb.set("joint_constraints/twist_span", r[6])
			"hinge":
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
				var n := _rest_bend_axis(r[0], r[1])
				var z := (g_rest.basis.inverse() * n).normalized()
				var x := dir.cross(z).normalized()
				pb.joint_rotation = Basis(x, z.cross(x), z).get_euler()
				pb.set("joint_constraints/angular_limit_enabled", true)
				pb.set("joint_constraints/angular_limit_lower", -r[6])
				pb.set("joint_constraints/angular_limit_upper", 3.0)
			_:
				pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		sim.add_child(pb)
		pb.global_transform = sk_g * skeleton.get_bone_global_pose(bi)
		bones.append(pb)
	sim.physical_bones_start_simulation()
	_pending_impulse = true

## Beuge-Achse eines Gelenks aus der Ruhepose (Elternknochen -> Knochen -> End-Knochen).
func _rest_bend_axis(bone: String, end_bone: String) -> Vector3:
	var bi := skeleton.find_bone(bone)
	var pi := skeleton.get_bone_parent(bi)
	var a := skeleton.get_bone_global_rest(pi).origin
	var b := skeleton.get_bone_global_rest(bi).origin
	var c := skeleton.get_bone_global_rest(skeleton.find_bone(end_bone)).origin
	var n := (b - a).cross(c - b)
	return n.normalized() if n.length_squared() > 1e-10 else Vector3.RIGHT

func _apply_death_impulse() -> void:
	var e := enemy
	var base := e.velocity * 0.8
	var dir := e._last_hit_dir
	dir.y = 0.35
	dir = dir.normalized()
	for pb in bones:
		var v: Vector3
		if _explosive:
			v = e._launch_vector(pb.global_position, e._expl_pos, e._expl_radius)
			pb.apply_impulse(e._rand_spin(0.6) * pb.mass, e._rand_spin(0.1))
		else:
			var f := 1.0
			if pb.bone_name == &"Head":
				f = 2.2 if e._last_hit_head else 1.2
			elif pb.bone_name == &"Torso":
				f = 1.3
			elif String(pb.bone_name).begins_with("Lower"):
				f = 0.5
			v = base + dir * e.death_impulse_speed * f * e.rng.randf_range(0.8, 1.2)
		pb.apply_central_impulse(v * pb.mass)

## Nachtraeglicher Schub, wenn eine Explosion den frischen Ragdoll trifft.
func boost_explosion(pos: Vector3, radius: float) -> void:
	if not _ragdoll_on:
		_explosive = true
		enemy._expl_pos = pos
		enemy._expl_radius = radius
		_start_ragdoll()
		return
	for pb in bones:
		pb.apply_central_impulse(enemy._launch_vector(pb.global_position, pos, radius) * pb.mass)
	if is_instance_valid(_weapon_body):
		_weapon_body.apply_central_impulse(enemy._launch_vector(_weapon_body.global_position, pos, radius) * _weapon_body.mass)

func _drop_weapon() -> void:
	if weapon == null:
		return
	var gt := weapon.global_transform
	var rb := RigidBody3D.new()
	rb.name = "DroppedWeapon"
	rb.collision_layer = Enemy.LAYER_DEBRIS
	rb.collision_mask = Enemy.LAYER_WORLD
	rb.mass = 6.0 if heavy else 3.5
	rb.continuous_cd = true
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var wm := _weapon_model()
	var len_w: float = absf((wm["muzzle"] as Vector3).z) + float(wm["stock"])
	bs.size = Vector3(0.06, 0.2, len_w) * vis_scale
	cs.shape = bs
	cs.position = Vector3(0, 0, (float(wm["stock"]) - len_w * 0.5)) * vis_scale
	rb.add_child(cs)
	enemy.add_child(rb)
	rb.global_transform = Transform3D(gt.basis.orthonormalized(), gt.origin)
	weapon.reparent(rb, true)
	rb.linear_velocity = enemy.velocity + enemy._last_hit_dir * 1.2 + Vector3.UP * 0.8
	rb.angular_velocity = enemy._rand_spin(3.0)
	_weapon_body = rb
