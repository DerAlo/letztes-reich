class_name SoldierVisual
extends Node3D
## Sichtbarer Soldat (Rifleman/Heavy): geriggtes Modell + AnimationTree + Oberkoerper-IK +
## Waffe an der rechten Hand + Ragdoll (PhysicalBoneSimulator3D) beim Tod.
## Wird von Enemy._build_body() erzeugt; liest Zustand direkt aus dem Enemy (keine KI-Logik hier).
## Rig/Animationen: assets/characters/soldier/soldier_rig.scn (gebacken mit tools/bake_soldier.gd).

const RIG_PATH := "res://assets/characters/soldier/soldier_rig.scn"
## Realistische Soldaten (MakeHuman/MPFB-CC0-Koerper, M1-Helm, Quaternius-UAL-Animationen), drei Koerper-
## Varianten; gebacken mit game/enemies/tools/bake_soldier_mh.gd. Fallback auf das SWAT-Modell, wenn die
## Grafik-Option "Realistische Soldaten" aus ist oder die Dateien fehlen (gepanzerte Typen bleiben SWAT).
const MH_RIG_PATH := "res://assets/characters/soldier_mh/soldier_mh_%s.scn"
## Operator ("S.W.A.T. Operator - Remastered", jeandiz, Sketchfab Standard License; Mixamo-Skelett auf die
## kanonischen Knochennamen gebacken mit game/enemies/tools/bake_soldier_op.gd): ersetzt das alte SWAT-Modell
## ueberall (gepanzerte Typen, Fallback ohne "Realistische Soldaten"). SWAT bleibt nur, falls die Datei fehlt.
const AK = preload("res://game/enemies/armor_kit.gd")
const OP_RIG_PATH := "res://assets/characters/soldier_op/soldier_op.scn"
const OP_TEX := "res://assets/characters/soldier_op/tex/"
const OP_SHADER := "res://game/enemies/soldier_op.gdshader"
const OP_HOOD_SHADER := "res://game/enemies/soldier_op_hood.gdshader"
## Kopf-Hitbox des Operators relativ zum Kopfknochen: Mitte von Helm + Gesicht (Ruhepose 0.0/1.665/0.05)
const OP_HEAD_HIT := Vector3(-0.004, 0.1, 0.006)
## Ordnungsfront-Brustabzeichen auf der Weste (Ruhepose, Skelettraum)
const OP_PATCH_POS := Vector3(0.08, 1.36, 0.16)
## Haende am Gewehr (Waffenrahmen: Lauf -Z, oben +Y, Ursprung oben am Pistolengriff). Die Finger sind im
## Modell schon um die Vector-Griffe gelegt (Ruhepose) -> Handrichtungen aus der Ruhepose (Bake-Meta grip_r),
## keine zusaetzliche Fingerkruemmung.
const OP_GRIP_R_FINGERS := Vector3(0.01, 0.01, -1.0)
const OP_GRIP_R_BACK := Vector3(1.0, -0.056, 0.01)
const MH_VARIANTS := ["a", "b", "c"]
const MH_TEX := "res://assets/characters/soldier_mh/tex/"
const MH_SHADER := "res://game/enemies/soldier_mh_cloth.gdshader"
const MH_SKIN_SHADER := "res://game/enemies/soldier_mh_skin.gdshader"
const MHG = preload("res://game/enemies/soldier_mh_gear.gd")
const RIFLE_PATH := "res://assets/characters/weapons/rifle_ar_west.glb"
const MG_PATH := "res://assets/characters/weapons/rifle_ar_quaternius.glb"
## Fraktion "reich" (fiktive Ordnungsfront): Armbinde mit erfundenem Emblem (gebrochener Ring + Klinge)
const REICH_ARMBAND_TEX := "res://assets/characters/faction/reich_armband.png"
const REICH_EMBLEM_TEX := "res://assets/environment/berlin/emblem.png"
const SG = preload("res://game/enemies/soldier_gear.gd")
const MuzzleFx = preload("res://game/graphics/muzzle_fx.gd")
const MAX_RAGDOLLS := 10
const RELOAD_TIME := 2.3

const LOCO_POINTS := [
	["idle", Vector2(0, 0)], ["walk", Vector2(0, 2.4)], ["run_fwd", Vector2(0, 4.2)],
	["run_back", Vector2(0, -2.6)], ["run_left", Vector2(-2.6, 0)], ["run_right", Vector2(2.6, 0)],
]
## Sync-Fortbewegung (MH/Operator, Bake-Meta "loco", tools/loco_sync.gd): alle Lauf-Schleifen haben dieselbe
## Laenge und Phase (links setzt bei t=0 auf); Dreiecke fest vorgegeben, Idle getrennt per Blend2.
const SYNC_LOCO := ["walk", "run_fwd", "sprint", "run_back", "run_left", "run_right"]
const SYNC_TRIS := [[0, 1, 5], [0, 1, 4], [1, 2, 5], [1, 2, 4], [0, 5, 3], [0, 4, 3]]
const SYNC_IN := [0, 5, 3, 4]    # Innenrand (langsamstes Tempo je Richtung): walk, right, back, left
const SYNC_OUT := [2, 5, 3, 4]   # Aussenrand (schnellstes Tempo je Richtung): sprint, right, back, left
const SYNC_MID := [1, 5, 3, 4]   # Aussenrand ohne Sprint (schraeg: Sprint nicht mit Seitlauf mischen)
## Mit gebackenen Schraeglaeufen (Bake-Spalte Richtungs-Warp, 45 und 70 Grad): 18 Punkte, Indizes 6..13 =
## run_fl, run_fr, sprint_fl, sprint_fr, run_l70, run_r70, sprint_l70, sprint_r70. Schraeg mischen dann nur noch
## Clips derselben Quelle (UAL-Lauf/-Sprint); erst ab 70 Grad kommt der SWAT-Seitlauf dazu.
const SYNC_LOCO_X := ["walk", "run_fwd", "sprint", "run_back", "run_left", "run_right", "run_fl", "run_fr",
	"sprint_fl", "sprint_fr", "run_l70", "run_r70", "sprint_l70", "sprint_r70", "run_bl", "run_br", "run_bl70", "run_br70"]
## Rueckwaerts-schraeg (14..17): run_bl/run_br 135 Grad, run_bl70/run_br70 110 Grad (gedrehter Rueckwaertslauf)
const SYNC_TRIS_X := [[0, 1, 7], [1, 9, 7], [1, 2, 9], [0, 7, 11], [7, 9, 13], [7, 13, 11], [0, 11, 5], [11, 13, 5],
	[0, 5, 17], [0, 17, 15], [0, 15, 3],
	[0, 1, 6], [1, 8, 6], [1, 2, 8], [0, 6, 10], [6, 8, 12], [6, 12, 10], [0, 10, 4], [10, 12, 4],
	[0, 4, 16], [0, 16, 14], [0, 14, 3]]
## Aussenrand: sprint, sprint_fr, sprint_r70, right, run_br70, run_br, back, run_bl, run_bl70, left, sprint_l70, sprint_fl
const SYNC_OUT_X := [2, 9, 13, 5, 17, 15, 3, 14, 16, 4, 12, 8]
const LEAN_MAX := 0.13           # rad Oberkoerper-Vorlage im vollen Lauf (zusaetzlich zur Clip-Haltung)
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

static var _trees: Dictionary = {}    # kind -> AnimationNodeBlendTree
static var _mat_cache: Dictionary = {}
static var _reich_patch: StandardMaterial3D = null
static var _weapon_cache: Dictionary = {}
static var active_ragdolls: int = 0
## Vorwaermen (main.gd): erzwingt die MH-Variante, damit jede Variante (eigenes Rig + Texturen) einmal geladen wird.
static var force_variant: String = ""

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

var _muzzle_fx: Node3D = null   # Muendungsfeuer (game/graphics/muzzle_fx.gd)
var _flash_prev: float = 0.0
var _weapon_attach: BoneAttachment3D = null
var _loco := Vector2.ZERO
## Sync-Fortbewegung: je SYNC_LOCO-Punkt Mischposition (natuerliche Geschwindigkeit) und Sync-Geschwindigkeit
## (m/s bei TimeScale 1); leer = altes SWAT-Blendspace
var _sp: Array[Vector2] = []
var _ss: Array[Vector2] = []
var _crouch_ss: float = 1.0
var _snap_t := -1.0   # _snap_dir: gewaehlter Winkel (rad) im Band Seitlauf..Rueckwaerts-schraeg, -1 = ausserhalb
var _snap_s := -1.0   # _snap_dir: zeitlich geglaetteter Winkel
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
var role: String = "rifleman"
var scope_tip: Node3D = null      ## Marksman: Objektiv (Glint-Position)
var kind: String = "swat"         ## "swat" (altes Modell), "op" (Operator) oder "mh" (realistisch)
## Operator: Kopf im Shader ausblenden (gepanzerte Typen tragen einen geschlossenen Helm, armor_kit.gd)
var hide_head: bool = false
var variant: String = ""
## Kopf-Hitbox relativ zum Kopfknochen (enemy.gd)
var head_hit_offset := Vector3(0.0, 0.1, 0.03)
var _mh_f: float = 1.0            ## Hoehenfaktor der MH-Variante gegenueber Variante a

## Waffenlaenge (z-Skalierung des Gewehrmodells) und Magazin je Gegnertyp
const ROLE_WEAPON_Z := {"assault": 0.74, "marksman": 1.3, "officer": 0.86}
const ROLE_MAG := {"assault": 40, "marksman": 8, "officer": 30}

func setup(e: Enemy) -> void:
	enemy = e
	heavy = e.heavy_armor
	vis_scale = 1.1 if heavy else 1.0
	role = e.enemy_type
	_mag_size = 100 if heavy else int(ROLE_MAG.get(role, 30))
	name = "Visual"
	var path := RIG_PATH
	# --op=0 (Debug): altes SWAT-Modell erzwingen (Vergleichsmessungen)
	if ResourceLoader.exists(OP_RIG_PATH) and str(Game.arg("op", "1")) != "0":
		path = OP_RIG_PATH
		kind = "op"
		hide_head = e is ArmoredEnemy
	if use_mh(e):
		variant = MH_VARIANTS[absi(hash("%s|%s|%s" % [e.name, e.enemy_type, e.global_position.snapped(Vector3.ONE * 0.5)])) % MH_VARIANTS.size()]
		if force_variant != "":
			variant = force_variant
		if ResourceLoader.exists(MH_RIG_PATH % variant):
			path = MH_RIG_PATH % variant
			kind = "mh"
	rig = (load(path) as PackedScene).instantiate() as Node3D
	add_child(rig)
	rig.rotation.y = PI  # Modell blickt nach +Z, Gegner nach -Z
	rig.scale = Vector3.ONE * vis_scale
	skeleton = rig.get_node("Skeleton3D") as Skeleton3D
	if kind == "mh":
		_mh_f = skeleton.get_bone_global_rest(skeleton.find_bone("Hips")).origin.y / MHG.REF_HIPS_Y
		head_hit_offset = Vector3(0.0, 0.04, 0.012)
	elif kind == "op":
		head_hit_offset = OP_HEAD_HIT
	_apply_materials()
	if role == "officer":
		var sh := skeleton.get_node_or_null("Swat_Head") as Node3D
		if sh != null:
			sh.visible = false
	if kind == "mh":
		# M1-Helm aus dem Bake ersetzt: prozeduraler Helm/Muetze in soldier_mh_gear.gd (Kopf-Baugruppe)
		var hm := skeleton.get_node_or_null("Helmet") as Node3D
		if hm != null:
			hm.visible = false
	_build_gear()
	_build_weapon()
	_build_tree()
	ik = SoldierIK.new()
	ik.name = "SoldierIK"
	skeleton.add_child(ik)
	_config_ik()
	head_attach = _attach("Head")

## Realistisches Modell verwenden? (Grafik-Option, nicht fuer gepanzerte Typen, Dateien vorhanden)
static func use_mh(e: Enemy) -> bool:
	if e is ArmoredEnemy:
		return false
	if not bool(Settings.get_value("graphics/real_soldiers", true)):
		return false
	return ResourceLoader.exists(MH_RIG_PATH % MH_VARIANTS[0])

# ---------------------------------------------------------------- Aufbau

func _attach(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.name = "BA_" + bone.replace(".", "_")
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba

func _apply_materials() -> void:
	var reich := enemy.faction == "reich"
	var key := "%s|%s|%s|%s|%s|%s" % [enemy.enemy_type, enemy.color_primary.to_html(), enemy.color_secondary.to_html(), enemy.faction, kind, variant if kind == "mh" else ("hood" if hide_head else "")]
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
		if kind == "mh":
			_mh_materials(m)
		elif kind == "op":
			_op_materials(m)
		_mat_cache[key] = m
	var mats: Dictionary = _mat_cache[key]
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			if kind == "swat":
				SG.prepare_mesh(mi, skeleton)   # MH-Meshes haben die Ruhepose-Daten schon (Bake, mit LODs)
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
	# Ein gemeinsames Abzeichen-Material fuer alle Typen/Varianten: je neuer Instanz kompilierte Godot den
	# Shader neu (Berlin-Wellen: ~85 ms je neuem Typ/Varianten-Schluessel beim ersten Gegner)
	if _reich_patch == null:
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
		_reich_patch = patch
	m["patch"] = _reich_patch

## Original-Material (Bake) einer Oberflaeche des MH-Modells, per Name
func _mh_bake_mat(nm: String) -> Material:
	for c in skeleton.get_children():
		if c is MeshInstance3D:
			var mesh := (c as MeshInstance3D).mesh
			for s in mesh.get_surface_count():
				var sm := mesh.surface_get_material(s)
				if sm != null and sm.resource_name == nm:
					return sm
	return null

## Operator: Original-Texturen (2048) + Fraktionsfarbe/Tarnmuster/Armbinde ueber soldier_op.gdshader
## (helligkeitserhaltend: Stoff/Weste sind im Original neutralgrau). Gepanzerte Typen: Kopf ausgeblendet.
func _op_materials(m: Dictionary) -> void:
	var sh := load(OP_HOOD_SHADER if hide_head else OP_SHADER) as Shader
	var camo_path: String = SG.CAMO_TEX.get(enemy.faction, "")
	var camo: Texture2D = load(camo_path) if camo_path != "" and ResourceLoader.exists(camo_path) else null
	var top := enemy.color_primary.lerp(enemy.color_secondary, 0.25) * 0.95
	var trou := enemy.color_primary.lerp(enemy.color_secondary, 0.5) * 0.85
	if enemy.faction == "garde":
		top *= 0.78
		trou *= 0.78
	var u := ShaderMaterial.new()
	u.shader = sh
	u.set_shader_parameter("albedo_tex", load(OP_TEX + "body_albedo.jpg"))
	u.set_shader_parameter("normal_tex", load(OP_TEX + "body_normal.jpg"))
	u.set_shader_parameter("orm_tex", load(OP_TEX + "body_orm.jpg"))
	u.set_shader_parameter("mode", 0)
	u.set_shader_parameter("ref_lum", 0.0269)   # linear (Shader rechnet linear; sRGB-Mittel 0.177)
	u.set_shader_parameter("col_top", Color(top.r, top.g, top.b))
	u.set_shader_parameter("col_trou", Color(trou.r, trou.g, trou.b))
	if camo != null:
		u.set_shader_parameter("camo_tex", camo)
		u.set_shader_parameter("use_camo", true)
		u.set_shader_parameter("camo_mul", Color(0.85, 0.85, 0.85) if enemy.faction == "reich" else Color(1, 1, 1))
	for side in ["L", "R"]:
		var wr := skeleton.get_bone_global_rest(skeleton.find_bone("Wrist." + side)).origin
		var mf := skeleton.get_bone_global_rest(skeleton.find_bone("Middle1." + side)).origin
		u.set_shader_parameter("hand_" + side.to_lower(), wr.lerp(mf, 0.5))
		u.set_shader_parameter("arm_a_" + side.to_lower(), skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm." + side)).origin)
		u.set_shader_parameter("arm_b_" + side.to_lower(), skeleton.get_bone_global_rest(skeleton.find_bone("LowerArm." + side)).origin)
	u.set_shader_parameter("arm_on", true)
	u.set_shader_parameter("arm_col", Color(enemy.color_armband.r, enemy.color_armband.g, enemy.color_armband.b))
	if enemy.faction == "reich" and ResourceLoader.exists(REICH_ARMBAND_TEX):
		u.set_shader_parameter("arm_tex", load(REICH_ARMBAND_TEX))
		u.set_shader_parameter("arm_use_tex", true)
		u.set_shader_parameter("arm_col", Color.WHITE)
	if hide_head:
		# Kopf/Helm des Modells innerhalb des Panzerhelms ausblenden (Helm-Ellipsoid aus armor_kit A_HC/A_HR
		# ueber AK.op_fix, leicht verkleinert -> keine Luecke zwischen Ausblendung und Panzerhelm)
		var hf := AK.op_fix("Head")
		var hr := AK.A_HR * hf.basis.get_scale() * 0.97
		u.set_shader_parameter("hide_c", hf * AK.A_HC)
		u.set_shader_parameter("hide_r", hr)
	m["OpBody"] = u
	var g := ShaderMaterial.new()
	g.shader = sh
	g.set_shader_parameter("albedo_tex", load(OP_TEX + "gear_albedo.jpg"))
	g.set_shader_parameter("normal_tex", load(OP_TEX + "gear_normal.jpg"))
	g.set_shader_parameter("orm_tex", load(OP_TEX + "gear_orm.jpg"))
	g.set_shader_parameter("emission_tex", load(OP_TEX + "gear_emissive.jpg"))
	g.set_shader_parameter("mode", 1)
	g.set_shader_parameter("ref_lum", 0.0187)   # linear (sRGB 0.146)
	var gc := MHG.colors(enemy.faction)
	if enemy.faction == "reich":
		g.set_shader_parameter("col_top", Color(0.2, 0.21, 0.23))   # stahlgrau wie Helm/Ausruestung der SWAT-Variante
		g.set_shader_parameter("metal_mul", 1.3)
	elif camo != null:
		g.set_shader_parameter("camo_tex", camo)
		g.set_shader_parameter("use_camo", true)
		g.set_shader_parameter("camo_mul", Color(0.86, 0.86, 0.84))
		g.set_shader_parameter("camo_scale", 2.5)
	else:
		var hc := gc[0].lerp(enemy.color_secondary, 0.5) if enemy.faction != "garde_winter" else enemy.color_primary * 1.1
		g.set_shader_parameter("col_top", Color(hc.r, hc.g, hc.b))
		g.set_shader_parameter("tint_amount", 0.85)
	if hide_head:
		g.set_shader_parameter("hide_c", u.get_shader_parameter("hide_c"))
		g.set_shader_parameter("hide_r", u.get_shader_parameter("hide_r"))
	m["OpGear"] = g

## MH-Modell: Uniform/Helm ueber soldier_mh_cloth.gdshader (Tarnmuster ru/reich, sonst Fraktionsfarben).
func _mh_materials(m: Dictionary) -> void:
	# SWAT: "Skin" = Plattentraeger-Stoff; MH: echte Haut -> Haut-Shader (waermer, Sturm mit Halstuch)
	var base_skin := _mh_bake_mat("Skin") as BaseMaterial3D
	var sk := ShaderMaterial.new()
	sk.shader = load(MH_SKIN_SHADER)
	if base_skin:
		sk.set_shader_parameter("albedo_tex", base_skin.albedo_texture)
		sk.set_shader_parameter("skin_rough", base_skin.roughness)
	sk.set_shader_parameter("head_off", skeleton.get_bone_global_rest(skeleton.find_bone("Head")).origin - MHG.REF_HEAD)
	if role == "assault":
		var gcol := MHG.gaiter_color(enemy.faction)
		sk.set_shader_parameter("gaiter_on", true)
		sk.set_shader_parameter("gaiter_col", Color(gcol.r, gcol.g, gcol.b))
	m["Skin"] = sk
	# Haar-Karten: matter (wirkten wie glaenzende Kappe), dunkler Haaransatz darunter kommt aus dem Haut-Shader
	var base_hair := _mh_bake_mat("Hair") as BaseMaterial3D
	if base_hair:
		var hm := base_hair.duplicate() as BaseMaterial3D
		hm.roughness = 1.0
		hm.metallic_specular = 0.12
		hm.albedo_color = Color(0.8, 0.78, 0.76)
		m["Hair"] = hm
	var sh := load(MH_SHADER) as Shader
	var camo_path: String = SG.CAMO_TEX.get(enemy.faction, "")
	var camo: Texture2D = load(camo_path) if camo_path != "" and ResourceLoader.exists(camo_path) else null
	var top := enemy.color_primary.lerp(enemy.color_secondary, 0.25) * 0.95
	var trou := enemy.color_primary.lerp(enemy.color_secondary, 0.5) * 0.85
	if enemy.faction == "garde":
		top *= 0.78   # Stadtgrau statt Hellgrau (Stoff wirkt mit Detailkarte sonst fast weiss)
		trou *= 0.78
	var u := ShaderMaterial.new()
	u.shader = sh
	u.set_shader_parameter("detail_tex", load(MH_TEX + "suit.jpg"))
	u.set_shader_parameter("normal_tex", load(MH_TEX + "suit_n.jpg"))
	u.set_shader_parameter("mode", 0)
	u.set_shader_parameter("col_top", Color(top.r, top.g, top.b))
	u.set_shader_parameter("col_trou", Color(trou.r, trou.g, trou.b))
	if camo != null:
		u.set_shader_parameter("camo_tex", camo)
		u.set_shader_parameter("use_camo", true)
		u.set_shader_parameter("camo_mul", Color(0.85, 0.85, 0.85) if enemy.faction == "reich" else Color(1, 1, 1))
	if enemy.faction == "garde_winter":
		u.set_shader_parameter("dirt_amount", 0.15)
	# Armbinde eng am Oberarm (Ruhepose: Schulter- und Ellbogengelenk je Seite)
	u.set_shader_parameter("arm_on", true)
	u.set_shader_parameter("arm_col", Color(enemy.color_armband.r, enemy.color_armband.g, enemy.color_armband.b))
	for side in ["L", "R"]:
		var a0 := skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm." + side)).origin
		var a1 := skeleton.get_bone_global_rest(skeleton.find_bone("LowerArm." + side)).origin
		u.set_shader_parameter("arm_a_" + side.to_lower(), a0)
		u.set_shader_parameter("arm_b_" + side.to_lower(), a1)
	if enemy.faction == "reich" and ResourceLoader.exists(REICH_ARMBAND_TEX):
		u.set_shader_parameter("arm_tex", load(REICH_ARMBAND_TEX))
		u.set_shader_parameter("arm_use_tex", true)
		u.set_shader_parameter("arm_col", Color.WHITE)
	m["Uniform"] = u
	var h := ShaderMaterial.new()
	h.shader = sh
	h.set_shader_parameter("detail_tex", load(MH_TEX + "helmet.jpg"))
	h.set_shader_parameter("normal_tex", load(MH_TEX + "helmet_n.jpg"))
	h.set_shader_parameter("mode", 1)
	h.set_shader_parameter("dirt_amount", 0.0)
	h.set_shader_parameter("normal_depth", 0.8)
	var gc := MHG.colors(enemy.faction)
	if enemy.faction == "reich":
		# Ordnungsfront: stahlgrau lackiert, leicht metallisch
		h.set_shader_parameter("col_top", Color(0.3, 0.31, 0.33))
		h.set_shader_parameter("shade_strength", 0.5)
		h.set_shader_parameter("rough", 0.5)
		h.set_shader_parameter("metal", 0.3)
	elif camo != null:
		# ru: Helmbezug im Tarnmuster
		h.set_shader_parameter("camo_tex", camo)
		h.set_shader_parameter("use_camo", true)
		h.set_shader_parameter("camo_mul", Color(0.9, 0.9, 0.9))
		h.set_shader_parameter("camo_scale", 3.0)
		h.set_shader_parameter("shade_strength", 0.6)
	else:
		var hc := gc[0].lerp(enemy.color_secondary, 0.5) if enemy.faction != "garde_winter" else enemy.color_primary * 1.1
		h.set_shader_parameter("col_top", Color(hc.r, hc.g, hc.b))
		h.set_shader_parameter("rough", 0.7)
	m["Helmet"] = h

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
	if kind == "mh":
		_build_gear_mh(mats)
		return
	if kind == "op":
		_build_gear_op(mats)
		return
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

## MH-Modell: Armbinden am Oberarm, Brustabzeichen (reich), Plattentraeger/Koppel/Kopfausruestung
## (soldier_mh_gear.gd) an ruhepose-ausgerichteten Rahmen; Hoehe je Variante skaliert.
func _build_gear_mh(mats: Dictionary) -> void:
	# Armbinden: im Uniform-Shader auf den Aermel projiziert (soldier_mh_cloth.gdshader, _mh_materials)
	var gm := MHG.gear_mat(enemy.faction)
	for grp: String in MHG.GROUP_BONE:
		var bone: String = MHG.GROUP_BONE[grp]
		var bi := skeleton.find_bone(bone)
		var gmesh := MHG.mesh(enemy.faction, role, heavy, grp)
		if gmesh == null:
			continue
		var ba := _attach(bone)
		var frame := Node3D.new()
		frame.name = "Kit_" + grp
		var place := Transform3D(Basis.from_scale(Vector3(1.0, _mh_f, 1.0)), Vector3.ZERO)
		if grp == "head":
			# Kopfgroesse ist bei allen Varianten gleich -> nur verschieben (Kopfknoten-Differenz), nicht strecken
			place = Transform3D(Basis.IDENTITY, skeleton.get_bone_global_rest(bi).origin - MHG.REF_HEAD)
		frame.transform = skeleton.get_bone_global_rest(bi).affine_inverse() * place
		ba.add_child(frame)
		var mi := MeshInstance3D.new()
		mi.name = "Kit"
		mi.mesh = gmesh
		mi.material_override = gm
		frame.add_child(mi)
		_meshes.append(mi)
		if grp == "chest" and mats.has("patch") and enemy.faction != "resistance":
			var q := QuadMesh.new()
			q.size = Vector2(0.06, 0.06)
			var y := 1.37
			var z := MHG._front_z(y, heavy) + (0.045 if heavy else 0.035) * 0.5 + 0.0045
			var pm := _part(frame, q, mats["patch"], Vector3(0.075, y, z), Vector3(deg_to_rad(MHG.FRONT_TILT), 0, 0))
			pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Operator: Weste/Helm/Taschen sind Teil des Modells; Armbinden im Shader (_op_materials). Hier nur das
## leuchtende Brustabzeichen der Ordnungsfront (Weste vorn links, Ruhepose) und unter dem Panzerhelm
## (hide_head) die Wimpern aus.
func _build_gear_op(mats: Dictionary) -> void:
	if hide_head:
		var el := skeleton.get_node_or_null("Eyelashes") as Node3D
		if el != null:
			el.visible = false
	if mats.has("patch") and not hide_head:
		var ci := skeleton.find_bone("Chest")
		var ba := _attach("Chest")
		var frame := Node3D.new()
		frame.name = "Kit_patch"
		frame.transform = skeleton.get_bone_global_rest(ci).affine_inverse()
		ba.add_child(frame)
		var q := QuadMesh.new()
		q.size = Vector2(0.06, 0.06)
		var pm := _part(frame, q, mats["patch"], OP_PATCH_POS, Vector3(deg_to_rad(-12.0), 0, 0))
		pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
				if role == "assault":
					SG.build_assault_chest(k, enemy.faction)
				elif role == "officer":
					SG.build_officer_chest(k, enemy.faction)
				elif role == "marksman":
					SG.build_ghillie_back(k, enemy.faction)
			"hips":
				SG.build_hips(k, enemy.faction)
			"head":
				if role == "officer":
					SG.build_officer_head(k, enemy.faction, enemy.color_skin)
				elif role == "marksman":
					SG.build_ghillie(k, enemy.faction)
				else:
					SG.build_head(k, enemy.faction)
					if role == "assault":
						SG.build_assault_head(k, enemy.faction)
		var mi := k.emit(frame, gm, "Kit")
		_meshes.append(mi)

## Waffe: Modell normalisiert (Lauf -Z, oben +Y, Ursprung oben am Pistolengriff).
func _weapon_model() -> Dictionary:
	# Schuetze/Offizier: AK-74M bzw. G36 (reich) wie Spieler und Drops (GunModels, ein Mesh mit LODs)
	if not heavy and (role == "rifleman" or role == "officer"):
		var nk: String = "nw_g36" if enemy.faction == "reich" else "nw_ak"
		if not _weapon_cache.has(nk):
			_weapon_cache[nk] = _new_rifle(enemy.faction)
		if not (_weapon_cache[nk] as Dictionary).is_empty():
			return _weapon_cache[nk]
	var zs: float = 1.0 if heavy else float(ROLE_WEAPON_Z.get(role, 1.0))
	var key := "mg" if heavy else "rifle_%.2f" % zs
	if _weapon_cache.has(key):
		return _weapon_cache[key]
	if heavy:
		# MG-Schuetze/Juggernaut: HK MG5 (GunModels); fehlt das Modell -> Kasten-MG unten (Rueckfall)
		var mg := _new_mg()
		if not mg.is_empty():
			_weapon_cache[key] = mg
			return mg
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
		d["proc"] = true
	else:
		# West-Gewehr: bereits Meter, Lauf -Z, 0.70 m (Arme des Low-Poly-Modells sind kurz)
		var s := 1.0
		var grip := Vector3(0, -0.045, 0.09) * s
		var zsc := Transform3D(Basis.from_scale(Vector3(1, 1, zs)), Vector3.ZERO)
		d["xf"] = zsc * Transform3D(Basis().scaled(Vector3.ONE * s), -grip) * xf
		d["muzzle"] = zsc * (Vector3(0, 0.016, -0.345) * s - grip)
		d["stock"] = (0.355 * s - grip.z) * zs
	src.free()
	_weapon_cache[key] = d
	return d

## AK-74M / G36 auf den Griff-Ursprung verschoben; hand_l = Ziel der linken Hand (unter dem Handschutz).
static func _new_rifle(faction: String) -> Dictionary:
	var r := GunModels.soldier_rifle(faction)
	if r.is_empty():
		return {}
	var m: Dictionary = r["meta"]
	# Bezugspunkt etwas hoeher/vorn, damit die rechte Hand (grip_r) den Pistolengriff umfasst statt darunter zu haengen
	var grip: Vector3 = (m["grip"] as Vector3) + Vector3(0.0, 0.05, -0.03)
	# Linke Hand: Reichweite des Arms ist begrenzt -> hinteres Handschutz-Ende, unter dem Gehaeuse
	var hl: Vector3 = (m["hand_l"] as Vector3) - grip
	return {"mesh": r["mesh"], "xf": Transform3D(Basis(), -grip) * (r["xf"] as Transform3D),
		"muzzle": (m["muzzle"] as Vector3) - grip, "stock": float(m["stock_end"]) - grip.z - STOCK_INSET,
		"hand_l": Vector3(-0.04, hl.y - 0.06, maxf(hl.z, -0.24))}

## HK MG5 wie _new_rifle auf den Griff-Ursprung; linke Hand unter dem Gehaeuse hinter dem Gurtkasten.
static func _new_mg() -> Dictionary:
	var r := GunModels.soldier_mg()
	if r.is_empty():
		return {}
	var m: Dictionary = r["meta"]
	var grip: Vector3 = (m["grip"] as Vector3) + Vector3(0.0, 0.05, -0.03)
	var hl: Vector3 = (m["hand_l"] as Vector3) - grip
	return {"mesh": r["mesh"], "xf": Transform3D(Basis(), -grip) * (r["xf"] as Transform3D),
		"muzzle": (m["muzzle"] as Vector3) - grip, "stock": float(m["stock_end"]) - grip.z - STOCK_INSET,
		"hand_l": Vector3(-0.045, hl.y - 0.03, maxf(hl.z, -0.26))}

## Kolbenkappe sitzt in der Schulter (nicht vor der Weste): die Tasche (shoulder_pocket) liegt auf der
## Westenfront, die Schaftkappe wird um so viel weiter nach hinten an das Schultergelenk gezogen.
const STOCK_INSET: float = 0.14

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
	if heavy and wm.get("proc", false):
		# Rueckfall-MG (Low-Poly-Gewehr): Kasten-Anbauteile machen es zum MG
		var dark: Material = mats["dark"]
		var plate: Material = mats["plate"]
		_part(weapon, _boxm(Vector3(0.06, 0.09, 0.11)), plate, Vector3(-0.055, -0.07, -0.09))                 # Munitionskasten
		_part(weapon, _boxm(Vector3(0.025, 0.02, 0.09)), dark, Vector3(-0.03, 0.0, -0.09), Vector3(0, 0, 0.6)) # Gurt
		_part(weapon, _cyl(0.026, 0.026, 0.42, 10), dark, Vector3(0, 0.115, -0.47), Vector3(PI * 0.5, 0, 0))  # Laufmantel
		for sx in [-1.0, 1.0]:
			_part(weapon, _cyl(0.008, 0.008, 0.3, 6), dark, Vector3(sx * 0.03, 0.07, -0.5), Vector3(PI * 0.5 + 0.12, 0, sx * 0.08))  # Zweibein
	elif not heavy:
		_build_role_weapon(wm)
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
	# Muendungsfeuer: dieselben prozeduralen Flash-Sprites/Funken wie die Spielerwaffe (Welt-Layer,
	# mit Tiefentest), etwas groesser fuer die Lesbarkeit auf Distanz
	_muzzle_fx = MuzzleFx.new()
	_muzzle_fx.name = "MuzzleFx"
	muzzle.add_child(_muzzle_fx)
	_muzzle_fx.call("setup", false, false, 1, 1.35, false)
	_weapon_attach = _attach("Wrist.R")
	_weapon_attach.add_child(weapon)

## Anbauteile je Gegnertyp (Waffe: Lauf -Z, oben +Y, Ursprung am Pistolengriff).
func _build_role_weapon(wm: Dictionary) -> void:
	var gc := SG.gear_colors(enemy.faction)
	var blk := SG.flat_gear(Color(0.05, 0.05, 0.055), 0.45, 0.5)
	var mz: Vector3 = wm["muzzle"]
	match role:
		"assault":
			var drum := SG.flat_gear(gc[2] * 0.8, 0.5, 0.35)
			_part(weapon, _cyl(0.062, 0.062, 0.05, 16), drum, Vector3(0, -0.075, -0.075), Vector3(0, 0, PI * 0.5))   # Trommelmagazin
			_part(weapon, _cyl(0.02, 0.02, 0.06, 8), blk, Vector3(0, -0.03, -0.31), Vector3.ZERO)                    # Vordergriff
			_part(weapon, _cyl(0.02, 0.022, 0.07, 10), blk, mz + Vector3(0, 0, 0.03), Vector3(PI * 0.5, 0, 0))       # Kompensator
		"marksman":
			_part(weapon, _cyl(0.021, 0.021, 0.2, 12), blk, Vector3(0, 0.115, -0.08), Vector3(PI * 0.5, 0, 0))       # Zielfernrohr
			_part(weapon, _cyl(0.029, 0.022, 0.05, 12), blk, Vector3(0, 0.115, -0.2), Vector3(PI * 0.5, 0, 0))       # Objektiv
			_part(weapon, _cyl(0.024, 0.02, 0.04, 12), blk, Vector3(0, 0.115, 0.04), Vector3(PI * 0.5, 0, 0))        # Okular
			for zz in [-0.13, -0.03]:
				_part(weapon, _boxm(Vector3(0.018, 0.04, 0.018)), blk, Vector3(0, 0.085, zz))                         # Montage
			_part(weapon, _cyl(0.014, 0.014, 0.12, 10), blk, mz + Vector3(0, 0, 0.055), Vector3(PI * 0.5, 0, 0))     # Schalldaempfer
			for sx in [-1.0, 1.0]:
				_part(weapon, _cyl(0.006, 0.006, 0.22, 6), blk, Vector3(sx * 0.02, -0.02, mz.z + 0.18), Vector3(PI * 0.5 - 0.15, 0, sx * 0.06))  # Zweibein (angeklappt)
			scope_tip = Node3D.new()
			scope_tip.name = "ScopeTip"
			scope_tip.position = Vector3(0, 0.115, -0.228)
			weapon.add_child(scope_tip)
		"officer":
			pass

func _config_ik() -> void:
	var wm := _weapon_model()
	ik.stock_length = wm["stock"]
	if heavy:
		ik.grip_r = Transform3D(SoldierIK.hand_basis(Vector3(-0.15, 0.3, -1.0), Vector3(1.0, 0.15, 0.05)), Vector3(0.025, -0.075, 0.085))
		ik.grip_l = Transform3D(SoldierIK.hand_basis(Vector3(0.3, 0.5, -0.8), Vector3(-0.6, -0.8, 0.0)), wm.get("hand_l", Vector3(-0.045, 0.0, -0.24)))
	else:
		ik.grip_r = Transform3D(SoldierIK.hand_basis(Vector3(-0.15, 0.3, -1.0), Vector3(1.0, 0.15, 0.05)), Vector3(0.025, -0.075, 0.085))
		var zs: float = float(ROLE_WEAPON_Z.get(role, 1.0))
		ik.grip_l = Transform3D(SoldierIK.hand_basis(Vector3(0.3, 0.5, -0.8), Vector3(-0.6, -0.8, 0.0)), wm.get("hand_l", Vector3(-0.04, -0.05, -0.2 * minf(zs, 1.15))))
	if kind == "op":
		ik.grip_r = Transform3D(SoldierIK.hand_basis(OP_GRIP_R_FINGERS, OP_GRIP_R_BACK), ik.grip_r.origin)
		ik.curl_r = Vector3.ZERO
		ik.curl_r_index = Vector3.ZERO
		ik.curl_l = Vector3.ZERO
		ik.curl_thumb = Vector3.ZERO
		var oci := skeleton.find_bone("Chest")
		var oua := skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm.R")).origin
		ik.shoulder_pocket = skeleton.get_bone_global_rest(oci).affine_inverse() * Vector3(oua.x * 0.7, oua.y - 0.01, 0.08)
	if kind == "mh":
		# Kolben in der rechten Schultertasche (auf dem Plattentraeger), aus der Ruhepose der Variante
		var ci := skeleton.find_bone("Chest")
		var ua := skeleton.get_bone_global_rest(skeleton.find_bone("UpperArm.R")).origin
		var pocket := Vector3(ua.x * 0.68, ua.y - 0.01 * _mh_f, 0.17)
		ik.shoulder_pocket = skeleton.get_bone_global_rest(ci).affine_inverse() * pocket
	weapon.transform = ik.grip_r.affine_inverse()

func _build_tree() -> void:
	var meta: Dictionary = rig.get_meta("loco", {}) if kind == "mh" or kind == "op" else {}
	if meta.has("sprint"):
		var cyc := float(meta.get("cycle", 0.8))
		for n in (SYNC_LOCO_X if meta.has("run_br70") else SYNC_LOCO):
			var d: Dictionary = meta[n]
			var v: Vector2 = d["vel"]
			var p := Vector2(-v.x, v.y)   # Rig-Raum (+Z vorn, +X links) -> Mischraum (x rechts, y vorn)
			_ss.append(p.normalized() * float(d["stride"]) / cyc)
			if n == "walk":
				p = p.normalized() * maxf(p.length(), 1.5)   # Gehen deckt zuegiges Gehen ab (Kadenz per TimeScale)
			_sp.append(p)
		_crouch_ss = maxf(float(meta.get("crouch_walk", {}).get("stride", 1.3)) / cyc, 0.1)
	var key := kind + ":" + variant if not _sp.is_empty() else kind
	if not _trees.has(key):
		_trees[key] = _make_tree_root(_sp)
	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	rig.add_child(anim_tree)
	anim_tree.anim_player = NodePath("../AnimationPlayer")
	anim_tree.tree_root = _trees[key]
	anim_tree.active = true
	anim_tree.set("parameters/life/transition_request", "alive")

static func _anim(n: String) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a

## sp leer = SWAT-Rig (LOCO_POINTS, Auto-Dreiecke); sonst Sync-Fortbewegung: Mischpunkte sp (SYNC_LOCO),
## feste Dreiecke, sync=true (alle Schleifen laufen phasengleich weiter) und TimeScale-Knoten, ueber die
## set_loco() die Kadenz an die echte Geschwindigkeit koppelt (kein Fussgleiten, kein Strecken einzelner Clips).
static func _make_tree_root(sp: Array[Vector2] = []) -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace2D.new()
	loco.min_space = Vector2(-6, -6)
	loco.max_space = Vector2(6, 6)
	if sp.is_empty():
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
		bt.connect_node("crouch_mix", 0, "loco")
		bt.connect_node("crouch_mix", 1, "crouch")
	else:
		loco.auto_triangles = false
		loco.sync = true
		var names: Array = SYNC_LOCO_X if sp.size() == SYNC_LOCO_X.size() else SYNC_LOCO
		for i in names.size():
			loco.add_blend_point(_anim(names[i]), sp[i], -1, StringName(names[i]))
		for t in (SYNC_TRIS_X if sp.size() == SYNC_LOCO_X.size() else SYNC_TRIS):
			loco.add_triangle(t[0], t[1], t[2])
		bt.add_node("loco", loco, Vector2(0, 0))
		bt.add_node("loco_ts", AnimationNodeTimeScale.new(), Vector2(150, 0))
		bt.add_node("a_idle", _anim("idle"), Vector2(150, -100))
		bt.add_node("move", AnimationNodeBlend2.new(), Vector2(300, 0))
		bt.add_node("a_crouch_idle", _anim("crouch_idle"), Vector2(0, 150))
		bt.add_node("a_crouch_walk", _anim("crouch_walk"), Vector2(0, 250))
		bt.add_node("crouch_ts", AnimationNodeTimeScale.new(), Vector2(150, 250))
		bt.add_node("crouch_move", AnimationNodeBlend2.new(), Vector2(300, 200))
		bt.add_node("crouch_mix", AnimationNodeBlend2.new(), Vector2(450, 100))
		bt.connect_node("loco_ts", 0, "loco")
		bt.connect_node("move", 0, "a_idle")
		bt.connect_node("move", 1, "loco_ts")
		bt.connect_node("crouch_ts", 0, "a_crouch_walk")
		bt.connect_node("crouch_move", 0, "a_crouch_idle")
		bt.connect_node("crouch_move", 1, "crouch_ts")
		bt.connect_node("crouch_mix", 0, "move")
		bt.connect_node("crouch_mix", 1, "crouch_move")
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
	var target_loco := Vector2(lv.x, -lv.z) / maxf(vis_scale, 0.01)   # Schrittlaenge skaliert mit dem sichtbaren Rig, nicht mit der Kollision (body_scale)
	_loco = _loco.lerp(target_loco, clampf(delta * 8.0, 0.0, 1.0))
	set_loco(_loco, e._stance)
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
	if flash:
		# RNG-Verbrauch wie bisher beibehalten (deterministische Gegner-Zufallsfolge)
		e.rng.randf()
		e.rng.randf_range(0.7, 1.2)
		if e._flash_timer > _flash_prev:
			_muzzle_fx.call("fire")
	_flash_prev = e._flash_timer

## Fortbewegung setzen (v: Rig-skalierte Geschwindigkeit, x rechts / y vorn; stance 0 stehend .. 1 geduckt).
## Auch fuer Debug-Werkzeuge (feet_shot/pose_shot/run_shot).
func set_loco(v: Vector2, stance: float) -> void:
	_loco = v
	var spd := v.length()
	if ik != null:
		ik.lean = LEAN_MAX * smoothstep(1.8, 5.5, spd) * (1.0 - stance) * (1.0 - 0.5 * ik.aim_weight)
	if _sp.is_empty():
		anim_tree.set("parameters/loco/blend_position", v)
		anim_tree.set("parameters/crouch/blend_position", spd)
		anim_tree.set("parameters/crouch_mix/blend_amount", stance)
		return
	var ts := 1.0
	var yaw_fix := 0.0
	if spd > 0.01:
		var d := _snap_dir(v / spd)
		# Richtungs-Warp zur Laufzeit: weicht die Clip-Richtung (Fang-Baender um den Seitlauf, bis ~12 Grad) von der
		# echten Laufrichtung ab, das Modell um den Rest drehen -> Fuesse laufen exakt mit, statt quer zu rutschen
		# (Oberkoerper/Waffe zielen per IK im Skelett-Raum und gleichen das aus)
		yaw_fix = wrapf(atan2(v.x, v.y) - atan2(d.x, d.y), -PI, PI)
		# Aussenrand: mit Schraeglaeufen bis Schraeg-Sprint; ohne (alte Rigs) Sprint nur nahe geradeaus
		var r_in := _ray_hull(d, SYNC_IN)
		var r_hi := _ray_hull(d, SYNC_OUT_X) if _sp.size() == SYNC_LOCO_X.size() 			else lerpf(_ray_hull(d, SYNC_MID), _ray_hull(d, SYNC_OUT), smoothstep(0.82, 0.97, d.y))
		if d.y < 0.0 and _sp.size() == SYNC_LOCO_X.size():
			# rueckwaerts/rueckwaerts-schraeg nie mit dem (Vorwaerts-)Gehen mischen: auf dem Aussenrand bleiben,
			# langsameres Tempo nur ueber die Kadenz (TimeScale) -> Standbein bleibt verriegelt
			r_in = maxf(r_hi, r_in)
		var p := d * clampf(spd, r_in, maxf(r_hi, r_in))
		ts = clampf(spd / maxf(_sync_speed(p), 0.1), 0.25, 2.0)
		anim_tree.set("parameters/loco/blend_position", p)
	var move := smoothstep(0.05, 0.6, spd)
	rig.rotation.y = PI - yaw_fix * move * (1.0 - stance)
	anim_tree.set("parameters/loco_ts/scale", ts)
	anim_tree.set("parameters/move/blend_amount", move)
	anim_tree.set("parameters/crouch_ts/scale", clampf(spd / _crouch_ss, 0.25, 2.0))
	anim_tree.set("parameters/crouch_move/blend_amount", move)
	anim_tree.set("parameters/crouch_mix/blend_amount", stance)

## SWAT-Seitlauf (Kreuzschritt) und die UAL-/Rueckwaerts-Laeufe passen beim Mischen nicht zusammen (Fuesse
## rutschen bis 3 m/s). Darum zwischen dem Seitlauf (90 Grad) und den gedrehten 70-Grad-Laeufen davor/dahinter nur
## in einem schmalen Winkelband ueberblenden (Phase ist synchron, der Wechsel bleibt sauber).
func _snap_dir(d: Vector2) -> Vector2:
	if _sp.size() != SYNC_LOCO_X.size() or is_zero_approx(d.x):
		return d
	var r := d.x > 0.0
	var a := atan2(absf(d.x), d.y)   # 0 = vorn, PI = hinten
	var side := _ang(_sp[5 if r else 4])
	var f70 := _ang(_sp[11 if r else 10])
	var b70 := _ang(_sp[17 if r else 16])
	if a > f70 and a < side:
		a = lerpf(f70, side, smoothstep(0.35, 0.65, (a - f70) / (side - f70)))
	elif a > side and a < b70:
		# hinter dem Seitlauf: gar nicht ueber den Winkel mischen, sondern den naeheren Clip waehlen (mit
		# Hysterese) und ueber die Zeit ueberblenden (Restfehler <= 12 Grad, statt Kreuzschritt-Gemisch)
		var near := side if a - side < b70 - a else b70
		if _snap_t >= 0.0 and absf(a - _snap_t) < absf(a - near) + 0.06 and (_snap_t == side or _snap_t == b70):
			near = _snap_t
		_snap_t = near
		_snap_s = near if _snap_s < 0.0 else lerpf(_snap_s, near, 0.15)
		a = _snap_s
		return Vector2(sin(a) * (1.0 if r else -1.0), cos(a))
	_snap_t = -1.0
	_snap_s = -1.0
	return Vector2(sin(a) * (1.0 if r else -1.0), cos(a))

static func _ang(p: Vector2) -> float:
	return atan2(absf(p.x), p.y)

## Abstand vom Ursprung bis zum Rand des Vierecks hull (Indizes in _sp) in Richtung d.
func _ray_hull(d: Vector2, hull: Array) -> float:
	var best := 0.0
	for i in hull.size():
		var a: Vector2 = _sp[hull[i]]
		var b: Vector2 = _sp[hull[(i + 1) % hull.size()]]
		var e := b - a
		var den := d.cross(e)
		if absf(den) < 1e-6:
			continue
		var t := a.cross(e) / den
		var u := a.cross(d) / den
		if t > 0.0 and u >= -1e-4 and u <= 1.0 + 1e-4:
			best = maxf(best, t)
	return best

## Geschwindigkeit des gemischten Laufzyklus bei TimeScale 1 an Mischposition p (baryzentrisch wie BlendSpace2D).
func _sync_speed(p: Vector2) -> float:
	for t in (SYNC_TRIS_X if _sp.size() == SYNC_LOCO_X.size() else SYNC_TRIS):
		var a := _sp[t[0]]
		var b := _sp[t[1]]
		var c := _sp[t[2]]
		var den := (b - a).cross(c - a)
		if absf(den) < 1e-6:
			continue
		var wb := (p - a).cross(c - a) / den
		var wc := (b - a).cross(p - a) / den
		var wa := 1.0 - wb - wc
		if wa >= -1e-3 and wb >= -1e-3 and wc >= -1e-3:
			# Laufschleifen (alles ausser Gehen, Index 0) sind gedrehte Varianten derselben Bewegung: beim Mischen
			# dreht sich die Laufrichtung, die Schrittlaenge bleibt -> Betraege mischen statt Vektoren (sonst ist die
			# Sync-Geschwindigkeit zwischen zwei Punkten bis 8 % zu klein = Kadenz zu hoch = Fuesse rutschen)
			var w := [wa, wb, wc]
			var walk := Vector2.ZERO
			var run := Vector2.ZERO
			var mag := 0.0
			for q in 3:
				if t[q] == 0:
					walk += _ss[0] * w[q]
				else:
					run += _ss[t[q]] * w[q]
					mag += _ss[t[q]].length() * w[q]
			return (walk + run.normalized() * mag).length() if run.length() > 1e-4 else walk.length()
	return _ss[1].length()

func start_reload() -> void:
	_reload_left = RELOAD_TIME
	_shots_at_reload = enemy.stat_shots
	enemy._bark("reload")

# ---------------------------------------------------------------- Tod / Ragdoll

func die(explosive: bool) -> void:
	if _dead:
		return
	_dead = true
	_explosive = explosive
	_muzzle_fx.call("stop")
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
		if bi < 0 and r[4] == "root":
			bi = skeleton.find_bone("Hips")   # MH-Rig: kein "Body"-Knochen
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
		pb.bone_name = skeleton.get_bone_name(bi)
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
	if kind == "op" and bone.begins_with("LowerLeg"):
		return Vector3.RIGHT   # Operator-Ruhepose: rechtes Bein fast gestreckt -> Kreuzprodukt unzuverlaessig
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
