extends RefCounted
## Story-Figuren (VIP-Puppen) mit Gesicht und Uniform: General von Riedhammer, Oberst Falk, Weber
## (zivil oder in Uniform) und Graumantel-Jaeger. Ersetzt die alten Box-Figuren der Level-Skripte.
##
## Schnittstelle wie die bisherigen `_figure()`-Puppen der Level (bunker/villa/kanzleramt):
##   build(parent, kind, pos, yaw_deg, opts) -> {"root", "arms", "legs", "head", "cap", "kind"}
##   - root: Node3D, Blickrichtung lokal -Z (wie Cutscene.aim), Fuesse auf y = 0
##   - arms: [links (-x), rechts (+x)], Pivot an der Schulter (+-0.31, 1.58, 0), Arm haengt nach -Y,
##           Hand bei y ~ -0.62 .. -0.78 (Posen: rotation.x, z. B. PI * 0.92 = Haende hoch)
##   - hands: [links, rechts], Kind des jeweiligen Arm-Nodes am Griffpunkt der Hand (Requisiten hier
##           anhaengen: sie folgen jeder Armpose und sitzen auch beim geriggten GLB-Modell in der Hand)
##   - legs: [links, rechts], Pivot an der Huefte (+-0.12, 0.9, 0), Fuss bei y = -0.9 (Gehen: rotation.x)
##   - head: Node3D am Halsansatz (0, 1.56, 0); cap: Kopfbedeckung (Kind von head, darf ausgeblendet
##           werden – darunter ist der Kopf vollstaendig modelliert, z. B. Riedhammers Glatze)
## Kein Collider, keine Hitbox (die alten Puppen hatten auch keine) – Verhalten bleibt beim Level.
##
## Aufbau: prozedural mit MeshKit (abgerundete Lofts, Ellipsoide, Kapseln), je Gelenk und Material ein
## Mesh. Stoffe: Vertex-Farbe + Poly-Haven-Leinen-Normalmap (triplanar im Objektraum, schwimmt nicht),
## Falks Kampfanzug mit dem Reich-Tarnmuster (soldier_cloth.gdshader), Ausruestung als Cordura.

const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const SG = preload("res://game/enemies/soldier_gear.gd")
const LINEN_N := "res://assets/characters/textures/rough_linen/normal.jpg"
const LINEN_ARM := "res://assets/characters/textures/rough_linen/arm.jpg"

const ARM_PIVOT := Vector3(0.31, 1.58, 0.0)
const LEG_PIVOT := Vector3(0.12, 0.9, 0.0)
const NECK := Vector3(0.0, 1.56, 0.0)
## Griffpunkt der Hand relativ zum Arm-Node (prozedurale Figur; Requisiten haengen an fig["hands"])
const HAND := Vector3(0.0, -0.74, -0.045)
## Schaedelmitte im Kopfraum (Kopf-Node sitzt am Halsansatz) -> Augenhoehe ~1.735 m
const SKULL := Vector3(0.0, 0.165, 0.0)

const GOLD := Color(0.86, 0.66, 0.26)
const SILVER := Color(0.78, 0.8, 0.82)
const GENERAL_RED := Color(0.62, 0.07, 0.06)
const AMBER := Color(1.0, 0.6, 0.12)

static var _mats: Dictionary = {}

## Erscheinungsbild je Figur (Schluessel siehe _style()).
static func styles() -> PackedStringArray:
	return PackedStringArray(["riedhammer", "falk", "weber", "weber_uniform", "graumantel"])

static func build(parent: Node, kind: String, pos: Vector3, yaw_deg: float, opts: Dictionary = {}) -> Dictionary:
	var fig := make(kind, opts)
	var root := fig["root"] as Node3D
	parent.add_child(root)
	root.position = pos
	root.rotation.y = deg_to_rad(yaw_deg)
	return fig

## Wie build(), aber ohne Einhaengen (root ist noch keinem Baum zugeordnet).
static func make(kind: String, opts: Dictionary = {}) -> Dictionary:
	if REAL_MODELS.has(kind) and not bool(opts.get("procedural", false)):
		var real := _make_real(kind, opts)
		if not real.is_empty():
			return real
	var st := _style(kind)
	for k: Variant in opts:
		st[k] = opts[k]
	var root := Node3D.new()
	root.name = str(st.get("name", kind.capitalize()))
	root.set_meta("vip", kind)
	var b := Kit.new()
	_torso(b, st)
	_head(b, st)
	_headgear(b, st)
	for s: float in [-1.0, 1.0]:
		_arm(b, st, s)
		_leg(b, st, s)
	# Gelenk-Nodes
	var head := Node3D.new()
	head.name = "Head"
	head.position = NECK
	root.add_child(head)
	var cap := Node3D.new()
	cap.name = "Cap"
	head.add_child(cap)
	var arms: Array[Node3D] = []
	var legs: Array[Node3D] = []
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var leg := Node3D.new()
		leg.name = "LegL" if i == 0 else "LegR"
		leg.position = Vector3(LEG_PIVOT.x * s, LEG_PIVOT.y, 0.0)
		root.add_child(leg)
		legs.append(leg)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var arm := Node3D.new()
		arm.name = "ArmL" if i == 0 else "ArmR"
		arm.position = Vector3(ARM_PIVOT.x * s, ARM_PIVOT.y, 0.0)
		root.add_child(arm)
		arms.append(arm)
	var hands := _add_hands(arms, [HAND, HAND])
	var nodes := {"root": root, "head": head, "cap": cap, "arm_l": arms[0], "arm_r": arms[1],
		"leg_l": legs[0], "leg_r": legs[1]}
	for part: String in b.kits:
		var target := nodes[part] as Node3D
		var per: Dictionary = b.kits[part]
		for mk: String in per:
			var kit := per[mk] as MK
			if kit.verts.is_empty():
				continue
			var mi := kit.emit(target, _mat(mk), "%s_%s" % [part, mk])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return {"root": root, "arms": arms, "hands": hands, "legs": legs, "head": head, "cap": cap, "kind": kind}

## Hand-Nodes (Griffpunkte, lokal zum Arm-Node) anlegen.
static func _add_hands(arms: Array[Node3D], local: Array) -> Array[Node3D]:
	var hands: Array[Node3D] = []
	for i in 2:
		var h := Node3D.new()
		h.name = "HandL" if i == 0 else "HandR"
		h.position = local[i]
		arms[i].add_child(h)
		hands.append(h)
	return hands

# ------------------------------------------------------------------ Realistische Modelle (GLB)
## Geriggte Figuren aus MakeHuman/MPFB2-CC0-Assets (Pipeline: tools/vip/prep_vip.py + build_vip.py --kind=..., siehe
## assets/CREDITS_ASSETS.md). Fehlt das GLB, wird die prozedurale Figur gebaut (opts.procedural = true
## erzwingt sie). Gelenk-Nodes sitzen auf den echten Knochen-Gelenkpunkten (Schulter ~1.44 m statt
## ARM_PIVOT), Hand ~0.5-0.6 m unter dem Arm-Node; Posen per rotation.x wie gehabt (VipRig treibt die Knochen).
const REAL_MODELS := {
	"riedhammer": "res://assets/characters/vip/riedhammer.glb",
	"weber": "res://assets/characters/vip/weber.glb",
	"weber_uniform": "res://assets/characters/vip/weber_uniform.glb",
	"falk": "res://assets/characters/vip/falk.glb",
	"graumantel": "res://assets/characters/vip/graumantel.glb",
}
## Knochen des MPFB-"game_engine"-Rigs je Gelenk-Node (links = -x im Root-Raum = Modell-links)
const RIG_BONES := {"arm_l": "upperarm_l", "arm_r": "upperarm_r", "leg_l": "thigh_l", "leg_r": "thigh_r",
	"head": "head"}
const VIP_RIG = preload("res://game/characters/vip_rig.gd")

static func _make_real(kind: String, opts: Dictionary) -> Dictionary:
	var path: String = REAL_MODELS[kind]
	if not ResourceLoader.exists(path):
		return {}
	var ps := load(path) as PackedScene
	if ps == null:
		return {}
	var root := Node3D.new()
	root.name = str(opts.get("name", kind.capitalize()))
	root.set_meta("vip", kind)
	# glTF blickt nach +Z, die API erwartet -Z
	var holder := Node3D.new()
	holder.name = "Model"
	holder.rotation.y = PI
	root.add_child(holder)
	var model := ps.instantiate() as Node3D
	holder.add_child(model)
	var skel: Skeleton3D = null
	for n: Node in model.find_children("*", "Skeleton3D", true, false):
		skel = n as Skeleton3D
		break
	if skel == null:
		root.free()
		return {}
	var s_xf := _rel_xform(skel, root)
	var cap_mesh: MeshInstance3D = null
	var mats := {}   # je Figur (kein statischer Cache: der hielte Ressourcen bis Programmende)
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_real_materials(mi, mats)
		if String(mi.name).begins_with("Cap"):
			cap_mesh = mi
	# Gelenk-Nodes auf die Knochen-Ursprünge
	var nodes := {}
	for key: String in RIG_BONES:
		var bi := skel.find_bone(RIG_BONES[key])
		var n := Node3D.new()
		n.name = {"arm_l": "ArmL", "arm_r": "ArmR", "leg_l": "LegL", "leg_r": "LegR", "head": "Head"}[key]
		n.position = (s_xf * skel.get_bone_global_rest(bi)).origin if bi >= 0 else Vector3.ZERO
		root.add_child(n)
		nodes[key] = n
	var head := nodes["head"] as Node3D
	var cap := Node3D.new()
	cap.name = "Cap"
	head.add_child(cap)
	if cap_mesh != null:
		var xf := _rel_xform(cap_mesh, root)
		cap_mesh.owner = null
		cap_mesh.get_parent().remove_child(cap_mesh)
		cap.add_child(cap_mesh)
		cap_mesh.transform = Transform3D(Basis.IDENTITY, -head.position) * xf
	# Treiber
	var drv := VIP_RIG.new()
	drv.name = "VipRig"
	drv.skel = skel
	for key: String in RIG_BONES:
		var bi := skel.find_bone(RIG_BONES[key])
		if bi < 0:
			continue
		var par := skel.get_bone_parent(bi)
		var pg := skel.get_bone_global_rest(par).basis if par >= 0 else Basis.IDENTITY
		drv.links.append({"bone": bi, "node": nodes[key], "s": s_xf.basis.orthonormalized(),
			"g": skel.get_bone_global_rest(bi).basis, "p": pg.inverse(), "key": key})
	# Prozeduraler Geh-/Laufzyklus (VipRig misst das Tempo des Roots): Knie, Fuesse, Unterarme, Ruecken
	drv.root = root
	drv.holder = holder
	drv.s_basis = s_xf.basis.orthonormalized()
	# + Idle-Leben (VipRig.IDLE_BONES: Becken, Ruecken, Hals, Schluesselbeine)
	var extra_bones: Array = ["calf_l", "calf_r", "foot_l", "foot_r", "lowerarm_l", "lowerarm_r", "spine_01"]
	for bn: String in VIP_RIG.IDLE_BONES:
		if not extra_bones.has(bn):
			extra_bones.append(bn)
	for bn: String in extra_bones:
		var bi := skel.find_bone(bn)
		if bi < 0:
			continue
		var par := skel.get_bone_parent(bi)
		var pg := skel.get_bone_global_rest(par).basis if par >= 0 else Basis.IDENTITY
		drv.extra[bn] = {"bone": bi, "g": skel.get_bone_global_rest(bi).basis, "p": pg.inverse()}
	root.add_child(drv)
	var arms: Array[Node3D] = [nodes["arm_l"], nodes["arm_r"]]
	var legs: Array[Node3D] = [nodes["leg_l"], nodes["leg_r"]]
	# Griffpunkt: Handflaechenmitte (zwischen Handgelenk und Mittelfinger-Grundgelenk), etwas zur
	# Handinnenseite (Richtung Koerpermitte) versetzt
	var grip := []
	for i in 2:
		var side := "l" if i == 0 else "r"
		var hb := skel.find_bone("hand_" + side)
		var p := arms[i].position + HAND
		if hb >= 0:
			p = (s_xf * skel.get_bone_global_rest(hb)).origin
			# Faustmitte: Schwerpunkt der gekruemmten Mittelfingerglieder und der Daumenspitze
			var acc := Vector3.ZERO
			var n := 0
			for bn in ["middle_01_", "middle_02_", "middle_03_", "thumb_03_"]:
				var bi := skel.find_bone(bn + side)
				if bi >= 0:
					acc += (s_xf * skel.get_bone_global_rest(bi)).origin
					n += 1
			if n == 4:
				p = acc / 4.0
		grip.append(p - arms[i].position)
	var hands := _bone_hands(skel, s_xf, arms, grip)
	return {"root": root, "arms": arms, "hands": hands, "legs": legs, "head": head, "cap": cap, "kind": kind,
		"skeleton": skel}

## Hand-Nodes des geriggten Modells: Kind eines BoneAttachment3D am Handknochen (hand_l/hand_r), damit
## Requisiten (Granate, Koffer, Pistole) der tatsaechlichen Hand folgen – Oberarm-Pose, Unterarm-/
## Armschwung des Geh-Zyklus und Root-Drehung. In der Ruhelage liegt der Node exakt wie der alte
## Arm-Kind-Node (Griffpunkt, achsparallel zum Root), Requisiten-Offsets der Level bleiben gueltig.
## Fehlt der Knochen, faellt es auf den Arm-Kind-Node zurueck.
static func _bone_hands(skel: Skeleton3D, s_xf: Transform3D, arms: Array[Node3D], grip: Array) -> Array[Node3D]:
	var hands: Array[Node3D] = []
	for i in 2:
		var side := "l" if i == 0 else "r"
		var hb := skel.find_bone("hand_" + side)
		var h := Node3D.new()
		h.name = "HandL" if i == 0 else "HandR"
		if hb < 0:
			h.position = grip[i]
			arms[i].add_child(h)
			hands.append(h)
			continue
		var ba := BoneAttachment3D.new()
		ba.name = "BA_Hand_" + side.to_upper()
		ba.bone_name = "hand_" + side
		ba.bone_idx = hb
		skel.add_child(ba)
		ba.add_child(h)
		# Root-Raum-Ziel (Griffpunkt, Root-Achsen) -> Skelettraum -> lokal zum Handknochen (Ruhelage)
		var want := Transform3D(Basis.IDENTITY, arms[i].position + (grip[i] as Vector3))
		h.transform = skel.get_bone_global_rest(hb).affine_inverse() * s_xf.affine_inverse() * want
		hands.append(h)
	return hands

## Transform von n relativ zu root (ohne Szenenbaum)
static func _rel_xform(n: Node, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c := n
	while c != null and c != root:
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf

## Importierte glTF-Materialien fuer Godot nachschaerfen (einmal je Material und Figur).
static func _real_materials(mi: MeshInstance3D, cache: Dictionary) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as BaseMaterial3D
		if src == null:
			continue
		var key := String(src.resource_name)
		if not cache.has(key):
			cache[key] = _tune_real(src.duplicate() as BaseMaterial3D, key)
		mi.set_surface_override_material(i, cache[key])

static func _tune_real(m: BaseMaterial3D, key: String) -> BaseMaterial3D:
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	match key:
		"skin":
			m.roughness = 0.58
			m.metallic_specular = 0.35
			m.subsurf_scatter_enabled = true
			m.subsurf_scatter_strength = 0.35
			m.subsurf_scatter_skin_mode = true
		"eye":
			m.roughness = 0.08
			m.metallic_specular = 0.7
		"brow", "lash", "hair":
			# Scissor + Alpha-to-Coverage: keine Dither-Schatten auf dem Gesicht (Alpha-Hash wirft Rauschen)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.alpha_scissor_threshold = 0.45
			m.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.roughness = 0.75
			m.metallic_specular = 0.25
		"suit", "suit_collar":
			m.roughness = 0.92
			m.metallic_specular = 0.2
		"silver":
			m.roughness = 0.35
			m.metallic = 0.85
		"glasses":
			m.roughness = 0.3
			m.metallic = 0.7
		"armband":
			# Amber-Armbinde leuchtet wie bei den prozeduralen Figuren (Fraktionsmarker)
			m.emission_enabled = true
			m.emission = AMBER
			m.emission_energy_multiplier = 0.6
			m.roughness = 0.6
		"cap_cloth":
			m.roughness = 0.95
			m.metallic_specular = 0.2
			if m is StandardMaterial3D:
				_weave(m as StandardMaterial3D, 30.0, 0.5)
		"boots", "visor":
			m.roughness = 0.28
			m.metallic_specular = 0.6
			m.clearcoat_enabled = true
			m.clearcoat = 0.5
			m.clearcoat_roughness = 0.25
		"gold":
			m.roughness = 0.42
			m.metallic = 0.85
		"tab_red", "cap_band":
			m.roughness = 0.9
			m.metallic_specular = 0.25
	if key == "visor" or key == "tab_red" or key.begins_with("ribbon"):
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

# ------------------------------------------------------------------ Figuren-Steckbriefe

static func _style(kind: String) -> Dictionary:
	# Grundwerte (neutraler Offizier)
	var st := {
		"name": kind.capitalize(), "skin": Color(0.86, 0.68, 0.57), "eyes": Color(0.36, 0.38, 0.36),
		"build": 1.0, "hair": "short", "hair_col": Color(0.22, 0.17, 0.13), "beard": "none",
		"beard_col": Color(0.22, 0.15, 0.1), "brow_col": Color(0.2, 0.15, 0.11), "brow_w": 0.0062,
		"glasses": false, "scar": false, "smirk": false,
		"top": "tunic", "top_col": Color(0.3, 0.32, 0.28), "trouser_col": Color(0.24, 0.25, 0.23),
		"stripes": false, "breeches": false, "boots": "tall", "tabs": Color(0, 0, 0, 0),
		"boards": "", "medals": false, "aiguillette": false, "belt": Color(0.2, 0.12, 0.07), "holster": false,
		"cap": "schirm", "cap_col": Color(0.3, 0.32, 0.28), "cap_band": Color(0.12, 0.13, 0.12), "trim": SILVER,
		"armband": false, "gloves": Color(0, 0, 0, 0), "cuffs": false,
	}
	match kind:
		"riedhammer":
			# General Riedhammer: Mitte 30, glatt rasierter Kopf, kurzer dichter Vollbart (dunkelbraun mit
			# Rotstich), blaue Augen, helle Haut, kraeftige Brauen, schmales Gesicht mit markanten Wangen/Kinn,
			# abstehende Ohren, schlank-athletisch; leicht spoettisches Laecheln. Paradeuniform eines Generals.
			st.merge({"name": "Riedhammer", "skin": Color(0.74, 0.52, 0.4), "eyes": Color(0.26, 0.5, 0.78),
				"build": 0.95, "hair": "bald", "beard": "full", "beard_col": Color(0.3, 0.165, 0.09),
				"brow_col": Color(0.24, 0.14, 0.08), "brow_w": 0.0042, "smirk": true, "ears_out": 34.0,
				"sculpt": true, "gloves": Color(0.045, 0.04, 0.04), "slim_legs": true,
				"face_narrow": 0.94, "top_col": Color(0.25, 0.28, 0.25), "trouser_col": Color(0.17, 0.18, 0.17),
				"stripes": true, "breeches": true, "boots": "tall", "tabs": GENERAL_RED, "boards": "gold",
				"medals": true, "aiguillette": true, "holster": true, "cap": "schirm",
				"cap_col": Color(0.25, 0.28, 0.25), "cap_band": Color(0.08, 0.1, 0.08), "trim": GOLD,
				"cap_piping": GOLD, "cuffs": true}, true)
		"falk":
			# Oberst Falk (Garde): Kampfanzug im Reich-Tarnmuster, Plattentraeger, Funkgeraet, schwarzes Barett,
			# kurzgeschorenes Haar, Bartschatten, Narbe ueber linke Braue/Wange, graue Augen, Handschuhe.
			st.merge({"name": "Falk", "skin": Color(0.8, 0.62, 0.5), "eyes": Color(0.5, 0.55, 0.58),
				"build": 1.08, "hair": "buzz", "hair_col": Color(0.16, 0.14, 0.12), "beard": "stubble",
				"beard_col": Color(0.3, 0.26, 0.22), "brow_col": Color(0.14, 0.12, 0.1), "brow_w": 0.0068,
				"scar": true, "top": "combat", "boots": "combat", "cap": "beret",
				"cap_col": Color(0.06, 0.06, 0.065), "trim": SILVER, "armband": true,
				"gloves": Color(0.06, 0.06, 0.065), "belt": Color(0.07, 0.07, 0.075)}, true)
		"weber":
			# Weber zivil: dunkler Mantel ueber Anzug, Hemd und Krawatte, Brille, graumeliertes Seitenscheitelhaar.
			st.merge({"name": "Weber", "skin": Color(0.84, 0.67, 0.57), "eyes": Color(0.4, 0.38, 0.3),
				"build": 0.98, "hair": "parted", "hair_col": Color(0.36, 0.33, 0.3), "brow_col": Color(0.28, 0.25, 0.22),
				"glasses": true, "top": "coat", "top_col": Color(0.17, 0.17, 0.18), "trouser_col": Color(0.13, 0.13, 0.14),
				"boots": "shoes", "cap": "none", "belt": Color(0.17, 0.17, 0.18)}, true)
		"weber_uniform":
			# Hauptmann Weber im Prolog: Feldgrau, silberne Schulterstuecke, Schirmmuetze, Amber-Armbinde.
			st.merge({"name": "Weber", "skin": Color(0.84, 0.67, 0.57), "eyes": Color(0.4, 0.38, 0.3),
				"hair": "parted", "hair_col": Color(0.36, 0.33, 0.3), "glasses": true,
				"top_col": Color(0.24, 0.26, 0.23), "boards": "silver", "armband": true, "holster": true,
				"cap_col": Color(0.24, 0.26, 0.23)}, true)
		"graumantel":
			# Garde-Jaeger im grauen Wintermantel mit Feldmuetze und Armbinde.
			st.merge({"name": "Graumantel", "top": "coat", "top_col": Color(0.36, 0.37, 0.37),
				"trouser_col": Color(0.2, 0.21, 0.2), "boots": "combat", "cap": "feld",
				"cap_col": Color(0.33, 0.34, 0.34), "armband": true, "belt": Color(0.1, 0.1, 0.1),
				"gloves": Color(0.1, 0.1, 0.1)}, true)
	return st

# ------------------------------------------------------------------ Materialien

static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	match key:
		"camo":
			m = SG.cloth_mat("reich", 0, Color.WHITE)
		"gear":
			m = SG.gear_mat("reich_vip")
		_:
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.85
			match key:
				"cloth", "wool":
					_weave(s, 10.0 if key == "cloth" else 14.0, 0.75 if key == "cloth" else 1.0)
					s.roughness = 0.9
				"hair":
					_weave(s, 34.0, 1.4)
					s.roughness = 0.95
				"skin":
					s.roughness = 0.52
					s.subsurf_scatter_enabled = true
					s.subsurf_scatter_strength = 0.25
					s.rim_enabled = true
					s.rim = 0.12
					s.rim_tint = 0.6
				"leather":
					s.roughness = 0.55
					s.metallic_specular = 0.3
				"boot":
					s.roughness = 0.16
					s.clearcoat_enabled = true
					s.clearcoat = 0.6
					s.clearcoat_roughness = 0.15
				"metal":
					s.metallic = 0.9
					s.roughness = 0.28
				"eye":
					s.roughness = 0.06
					s.metallic_specular = 0.8
				"glow":
					s.roughness = 0.6
					s.emission_enabled = true
					s.emission = AMBER
					s.emission_energy_multiplier = 0.35
				"glass":
					s.vertex_color_use_as_albedo = false
					s.albedo_color = Color(0.75, 0.82, 0.88, 0.14)
					s.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					s.roughness = 0.03
					s.metallic_specular = 1.0
			m = s
	_mats[key] = m
	return m

static func _weave(s: StandardMaterial3D, scale: float, strength: float) -> void:
	if not ResourceLoader.exists(LINEN_N):
		return
	s.normal_enabled = true
	s.normal_texture = load(LINEN_N)
	s.normal_scale = strength
	s.uv1_triplanar = true
	s.uv1_scale = Vector3(scale, scale, scale)
	s.uv1_triplanar_sharpness = 2.0
	if ResourceLoader.exists(LINEN_ARM):
		s.ao_enabled = true
		s.ao_texture = load(LINEN_ARM)
		s.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		s.ao_light_affect = 0.3

# ------------------------------------------------------------------ Bau-Puffer

## Sammelt je Gelenk ("root", "head", "cap", "arm_l", ...) und Material einen MeshKit-Puffer.
class Kit:
	var kits: Dictionary = {}
	func k(part: String, mat: String, col: Color) -> MK:
		if not kits.has(part):
			kits[part] = {}
		var per: Dictionary = kits[part]
		if not per.has(mat):
			per[mat] = MK.new()
		var kit := per[mat] as MK
		kit.color = col
		return kit

## Ellipsoid (oder Ausschnitt): Mitte c, Halbachsen r, Drehung rot (Grad). th = Polarwinkel ab +Y,
## ph = Azimut ab +X Richtung +Z (Vorderseite -Z liegt bei ph = -PI/2).
static func _ell(k: MK, c: Vector3, r: Vector3, rot: Vector3 = Vector3.ZERO, seg: int = 14, rings: int = 9,
		th0: float = 0.0, th1: float = PI, ph0: float = -PI, ph1: float = PI) -> void:
	var bas := Basis.from_euler(rot * (PI / 180.0))
	var pts: Array[PackedVector3Array] = []
	var nrm: Array[PackedVector3Array] = []
	for i in rings + 1:
		var th := lerpf(th0, th1, float(i) / float(rings))
		var rp := PackedVector3Array()
		var rn := PackedVector3Array()
		for j in seg + 1:
			var ph := lerpf(ph0, ph1, float(j) / float(seg))
			var u := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			var p := Vector3(u.x * r.x, u.y * r.y, u.z * r.z)
			var n := Vector3(u.x / r.x, u.y / r.y, u.z / r.z).normalized()
			rp.append(c + bas * p)
			rn.append(bas * n)
		pts.append(rp)
		nrm.append(rn)
	for i in rings:
		for j in seg:
			k.quad_n(pts[i][j], pts[i][j + 1], pts[i + 1][j + 1], pts[i + 1][j],
				nrm[i][j], nrm[i][j + 1], nrm[i + 1][j + 1], nrm[i + 1][j])

## Kapsel mit unterschiedlichen Radien (Gliedmassen): a -> b.
static func _limb(k: MK, a: Vector3, b: Vector3, ra: float, rb: float, seg: int = 12) -> void:
	var l := a.distance_to(b)
	var prof := PackedVector2Array()
	for t: float in [1.0, 0.92, 0.7, 0.38]:
		prof.append(Vector2(-t * ra, sqrt(1.0 - t * t) * ra))
	prof.append(Vector2(0.0, ra))
	prof.append(Vector2(l, rb))
	for t: float in [0.38, 0.7, 0.92, 1.0]:
		prof.append(Vector2(l + t * rb, sqrt(1.0 - t * t) * rb))
	prof[0] = Vector2(-ra, 0.0)
	prof[prof.size() - 1] = Vector2(l + rb, 0.0)
	k.lathe(a, b - a, prof, seg, true)

## Duenne Schnur entlang Punkten.
static func _cord(k: MK, pts: Array[Vector3], r: float) -> void:
	for i in pts.size() - 1:
		k.cyl(pts[i], pts[i + 1], r, 6)

## Ring (Ellipse) auf Hoehe y, Mitte (dx, dz).
static func _ring(y: float, rx: float, rz: float, dz: float, n: int = 24, e: float = 2.4, dx: float = 0.0) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in MK.superellipse(rx, rz, e, n):
		out.append(Vector3(q.x + dx, y, q.y + dz))
	return out

## Loft aus Ringen [y, rx, rz, dz] (weich).
static func _loft(k: MK, spec: Array, n: int = 24, e: float = 2.4, caps: bool = true, dx: float = 0.0) -> void:
	var rings: Array[PackedVector3Array] = []
	for r: Array in spec:
		rings.append(_ring(float(r[0]), float(r[1]), float(r[2]), float(r[3]), n, e, dx))
	k.loft(rings, caps, caps, true)

## Rumpfprofil an Hoehe y interpoliert -> [rx, rz, dz].
static func _at(spec: Array, y: float) -> Array:
	for i in spec.size() - 1:
		var a: Array = spec[i]
		var b: Array = spec[i + 1]
		if y >= float(a[0]) and y <= float(b[0]):
			var t := (y - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.0001)
			return [lerpf(a[1], b[1], t), lerpf(a[2], b[2], t), lerpf(a[3], b[3], t)]
	var l: Array = spec[0] if y < float(spec[0][0]) else spec[spec.size() - 1]
	return [l[1], l[2], l[3]]

## Punkt auf der Rumpfvorderseite bei (x, y) plus Abstand `off` nach aussen; .w = Gier (Grad) der Flaeche.
static func _front(spec: Array, x: float, y: float, off: float = 0.0) -> Vector4:
	var r := _at(spec, y)
	var rx: float = r[0]
	var rz: float = r[1]
	var q := clampf(x / rx, -0.97, 0.97)
	var z: float = float(r[2]) - rz * pow(1.0 - pow(absf(q), 2.4), 1.0 / 2.4) - off
	var yaw := -rad_to_deg(atan2(q * rz, rx)) * 0.9
	return Vector4(x, y, z, yaw)

# ------------------------------------------------------------------ Rumpf

static func _torso_spec(st: Dictionary) -> Array:
	var w: float = st["build"]
	var top: String = st["top"]
	var t := 0.012 if top == "coat" else (0.008 if top == "combat" else 0.0)
	var spec: Array = [
		[0.76, 0.172 * w + t, 0.116 + t, 0.0],
		[0.9, 0.178 * w + t, 0.118 + t, 0.0],
		[1.02, 0.156 * w + t, 0.104 + t, -0.004],
		[1.16, 0.172 * w + t, 0.114 + t, -0.01],
		[1.3, 0.19 * w + t, 0.124 + t, -0.016],
		[1.42, 0.205 * w + t, 0.116 + t, -0.006],
		[1.5, 0.198 * w + t, 0.096 + t, 0.004],
		[1.545, 0.15 * w + t, 0.075 + t * 0.5, 0.008],
		[1.575, 0.07, 0.056, 0.008],
	]
	return spec

static func _torso(b: Kit, st: Dictionary) -> void:
	var top: String = st["top"]
	var tc: Color = st["top_col"]
	var spec := _torso_spec(st)
	var body_mat := "camo" if top == "combat" else "wool"
	_loft(b.k("root", body_mat, tc), spec, 26)
	match top:
		"tunic":
			_tunic(b, st, spec)
		"coat":
			_coat(b, st, spec)
		"combat":
			_combat(b, st, spec)

## Waffenrock: Stehkragen mit Kragenspiegeln, Schulterstuecke, Knopfleiste, Brusttaschen, Ordensspange,
## Bruststern, Fangschnur, Koppel mit Pistolentasche, Rockschoss.
static func _tunic(b: Kit, st: Dictionary, spec: Array) -> void:
	var tc: Color = st["top_col"]
	var trim: Color = st["trim"]
	var dark := tc.darkened(0.25)
	var cl := b.k("root", "wool", tc)
	# Rockschoss (bis knapp unter die Huefte)
	_loft(cl, [[1.0, 0.168 * float(st["build"]), 0.113, -0.004], [0.88, 0.185 * float(st["build"]), 0.124, -0.002],
		[0.75, 0.194 * float(st["build"]), 0.134, 0.0]], 26, 2.4, false)
	# Stehkragen
	_loft(cl, [[1.535, 0.078, 0.07, 0.006], [1.6, 0.07, 0.064, 0.006], [1.606, 0.066, 0.06, 0.006]], 20, 2.2, false)
	# Knopfleiste (Kante) und Knoepfe
	var placket := b.k("root", "wool", dark)
	for y: float in [1.06, 1.18, 1.3, 1.42]:
		var f := _front(spec, 0.0, y, 0.0)
		placket.cbox(Vector3(0.0, y, f.z - 0.002), Vector3(0.012, 0.12, 0.004), 0.002)
	var met := b.k("root", "metal", trim)
	for y: float in [1.06, 1.14, 1.22, 1.3, 1.38, 1.46]:
		var f := _front(spec, 0.0, y, 0.004)
		_ell(met, Vector3(0.0, y, f.z), Vector3(0.0085, 0.0085, 0.005), Vector3.ZERO, 8, 4)
	# Brust- und Schosstaschen
	for s: float in [-1.0, 1.0]:
		var f := _front(spec, s * 0.09, 1.3, 0.003)
		var pk := b.k("root", "wool", tc.lightened(0.03))
		pk.cbox(Vector3(f.x, 1.3, f.z), Vector3(0.085, 0.1, 0.01), 0.004, Vector3(0, f.w, 0))
		pk.color = dark
		var f2 := _front(spec, s * 0.09, 1.355, 0.008)
		pk.cbox(Vector3(f2.x, 1.355, f2.z), Vector3(0.09, 0.03, 0.01), 0.004, Vector3(0, f2.w, 0))
		_ell(met, Vector3(f2.x, 1.35, f2.z - 0.007), Vector3(0.006, 0.006, 0.004), Vector3.ZERO, 6, 3)
		var hs := [[1.0, 0.168, 0.113, -0.004], [0.88, 0.185, 0.124, -0.002], [0.75, 0.194, 0.134, 0.0]]
		var f3 := _front(hs, s * 0.1, 0.9, 0.006)
		pk.color = tc.lightened(0.03)
		pk.cbox(Vector3(f3.x, 0.86, f3.z), Vector3(0.1, 0.11, 0.01), 0.004, Vector3(0, f3.w, 0))
		pk.color = dark
		pk.cbox(Vector3(f3.x, 0.915, f3.z - 0.004), Vector3(0.105, 0.032, 0.01), 0.004, Vector3(0, f3.w, 0))
	# Kragenspiegel (General: rot mit goldener Stickerei)
	var tab: Color = st["tabs"]
	for s: float in [-1.0, 1.0]:
		var ang := deg_to_rad(40.0)
		var p := Vector3(s * 0.074 * sin(ang), 1.57, 0.006 - 0.068 * cos(ang) - 0.004)
		if tab.a > 0.0:
			b.k("root", "wool", tab).cbox(p, Vector3(0.04, 0.045, 0.006), 0.003, Vector3(0, -s * 40.0, 0))
			var g := b.k("root", "metal", trim)
			g.cbox(p + Vector3(0, 0.0, -0.004), Vector3(0.026, 0.008, 0.003), 0.001, Vector3(0, -s * 40.0, 25.0 * s))
			g.cbox(p + Vector3(0, -0.01, -0.004), Vector3(0.026, 0.008, 0.003), 0.001, Vector3(0, -s * 40.0, 25.0 * s))
		else:
			b.k("root", "wool", dark).cbox(p, Vector3(0.036, 0.04, 0.005), 0.003, Vector3(0, -s * 40.0, 0))
	# Schulterstuecke (geflochten, auf roter/dunkler Unterlage)
	var boards: String = st["boards"]
	if boards != "":
		var bc := GOLD if boards == "gold" else SILVER
		for s: float in [-1.0, 1.0]:
			var c := Vector3(s * 0.175, 1.538, 0.0)
			var rot := Vector3(0, 0, -s * 15.0)
			b.k("root", "wool", GENERAL_RED if boards == "gold" else dark).cbox(c, Vector3(0.13, 0.012, 0.062), 0.004, rot)
			var g := b.k("root", "metal", bc)
			var basis := Basis.from_euler(rot * (PI / 180.0))
			for zz: float in [-0.017, 0.0, 0.017]:
				var a := c + basis * Vector3(-0.058, 0.009, zz)
				var e := c + basis * Vector3(0.058, 0.009, zz)
				g.cyl(a, e, 0.0065, 6)
			g.color = SILVER if boards == "gold" else GOLD
			for xx: float in [-0.02, 0.02]:
				_ell(g, c + basis * Vector3(xx, 0.017, 0.0), Vector3(0.008, 0.004, 0.008), rot, 8, 3)
	# Ordensspange (Bandschnallen, links) und Bruststern
	if bool(st["medals"]):
		var cols: Array[Color] = [Color(0.75, 0.12, 0.1), Color(0.95, 0.85, 0.3), Color(0.1, 0.12, 0.13),
			Color(0.2, 0.35, 0.65), Color(0.85, 0.85, 0.85), Color(0.3, 0.5, 0.25), Color(0.6, 0.1, 0.35), Color(0.9, 0.55, 0.15)]
		var ci := 0
		for row in 3:
			var y := 1.392 + float(row) * 0.0135
			var n := 4 - (1 if row == 2 else 0)
			for j in n:
				var x := -0.09 + (float(j) - float(n - 1) * 0.5) * 0.0225
				var f := _front(spec, x, y, 0.004)
				var rb := b.k("root", "cloth", cols[ci % cols.size()])
				rb.cbox(Vector3(x, y, f.z), Vector3(0.021, 0.012, 0.006), 0.0015, Vector3(0, f.w, 0))
				ci += 1
		var fs := _front(spec, -0.09, 1.235, 0.006)
		var star := b.k("root", "metal", SILVER)
		for a: float in [0.0, 45.0]:
			star.cbox(Vector3(fs.x, fs.y, fs.z), Vector3(0.042, 0.042, 0.005), 0.003, Vector3(0, fs.w, a))
		star.color = GOLD
		_ell(star, Vector3(fs.x, fs.y, fs.z - 0.004), Vector3(0.012, 0.012, 0.004), Vector3(0, fs.w, 0), 10, 4)
		star.color = GENERAL_RED
		_ell(star, Vector3(fs.x, fs.y, fs.z - 0.0065), Vector3(0.006, 0.006, 0.002), Vector3(0, fs.w, 0), 8, 3)
	# Fangschnur (rechte Schulter -> zweiter Knopf)
	if bool(st["aiguillette"]):
		var g := b.k("root", "metal", trim)
		for off: float in [0.0, 0.03]:
			var pts: Array[Vector3] = []
			for i in 9:
				var t := float(i) / 8.0
				var x := lerpf(0.2, 0.012, t)
				var y := lerpf(1.505, 1.385, t) - sin(t * PI) * (0.07 + off)
				var f := _front(spec, x, y, 0.008)
				pts.append(Vector3(x, y, f.z))
			_cord(g, pts, 0.0042)
		_ell(g, Vector3(0.012, 1.385, _front(spec, 0.012, 1.385, 0.01).z), Vector3(0.007, 0.012, 0.006), Vector3.ZERO, 6, 4)
	_belt(b, st, spec)

## Koppel mit Schloss (+ Pistolentasche links).
static func _belt(b: Kit, st: Dictionary, spec: Array) -> void:
	var bc: Color = st["belt"]
	var w: float = st["build"]
	var top: String = st["top"]
	var t := 0.012 if top == "coat" else (0.008 if top == "combat" else 0.0)
	var lk := b.k("root", "leather", bc)
	_loft(lk, [[0.975, 0.168 * w + t, 0.114 + t, -0.004], [1.025, 0.164 * w + t, 0.112 + t, -0.005]], 26, 2.4, false)
	var f := _front(spec, 0.0, 1.0, 0.014)
	var met := b.k("root", "metal", st["trim"] if top == "tunic" else Color(0.55, 0.56, 0.58))
	met.cbox(Vector3(0.0, 1.0, f.z), Vector3(0.05, 0.042, 0.008), 0.004)
	if top == "tunic":
		# Schulterriemen (rechte Schulter -> linke Huefte, unter dem Schulterstueck): ein durchgehendes
		# Band, vorn und hinten auf der Rockoberflaeche aufliegend
		var path: Array[Vector2] = [Vector2(0.152, 1.534), Vector2(0.142, 1.5)]
		for i in 10:
			var tt := float(i + 1) / 10.0
			path.append(Vector2(lerpf(0.142, -0.13, tt), lerpf(1.5, 1.0, tt)))
		lk.color = bc.lightened(0.04)
		_strap(lk, spec, path, 0.024, false)
		_strap(lk, spec, path, 0.024, true)
	if bool(st["holster"]):
		var hp := _front(_skirt_spec(st), -0.15, 0.93, 0.02)
		lk.color = bc.darkened(0.1)
		lk.cbox(Vector3(hp.x, 0.92, hp.z), Vector3(0.05, 0.12, 0.09), 0.014, Vector3(0, hp.w - 20.0, 0))
		lk.color = bc.darkened(0.25)
		lk.cbox(Vector3(hp.x, 0.975, hp.z - 0.004), Vector3(0.056, 0.03, 0.094), 0.008, Vector3(0, hp.w - 20.0, 0))
		met.color = Color(0.55, 0.56, 0.58)
		_ell(met, Vector3(hp.x - 0.004, 0.97, hp.z - 0.049), Vector3(0.006, 0.006, 0.003), Vector3.ZERO, 6, 3)

## Punkt auf der Rumpfrueckseite (Gegenstueck zu _front).
static func _back(spec: Array, x: float, y: float, off: float = 0.0) -> Vector3:
	var r := _at(spec, y)
	var q := clampf(x / float(r[0]), -0.985, 0.985)
	return Vector3(x, y, float(r[2]) + float(r[1]) * pow(1.0 - pow(absf(q), 2.4), 1.0 / 2.4) + off)

static func _surf_pt(spec: Array, x: float, y: float, off: float, back: bool) -> Vector3:
	if back:
		return _back(spec, x, y, off)
	var f := _front(spec, x, y, off)
	return Vector3(f.x, f.y, f.z)

## Flaches Lederband entlang eines (x, y)-Pfades auf der Rumpfflaeche, mit Kanten bis in den Stoff.
static func _strap(k: MK, spec: Array, path: Array[Vector2], wid: float, back: bool) -> void:
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	var top_i: Array[Vector3] = []
	var bot_i: Array[Vector3] = []
	for i in path.size():
		var tng := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var pv := Vector2(-tng.y, tng.x) * wid * 0.5
		var a := path[i] + pv
		var e := path[i] - pv
		top.append(_surf_pt(spec, a.x, a.y, 0.0032, back))
		bot.append(_surf_pt(spec, e.x, e.y, 0.0032, back))
		top_i.append(_surf_pt(spec, a.x, a.y, -0.003, back))
		bot_i.append(_surf_pt(spec, e.x, e.y, -0.003, back))
	for i in path.size() - 1:
		var n0 := (bot[i] - top[i]).cross(top[i + 1] - top[i]).normalized()
		var r := _at(spec, top[i].y)
		var out := Vector3(top[i].x / float(r[0]), 0.0, (top[i].z - float(r[2])) / float(r[1]))
		if n0.dot(out) < 0.0:
			n0 = -n0
		k.quad_n(top[i], top[i + 1], bot[i + 1], bot[i], n0, n0, n0, n0)
		var sn := ((top[i] - bot[i]).normalized() + n0).normalized()
		k.quad_n(top[i], top[i + 1], top_i[i + 1], top_i[i], sn, sn, sn, sn)
		sn = ((bot[i] - top[i]).normalized() + n0).normalized()
		k.quad_n(bot[i], bot[i + 1], bot_i[i + 1], bot_i[i], sn, sn, sn, sn)

static func _skirt_spec(st: Dictionary) -> Array:
	var w: float = st["build"]
	return [[0.75, 0.194 * w, 0.134, 0.0], [0.88, 0.185 * w, 0.124, -0.002], [1.0, 0.168 * w, 0.113, -0.004]]

## Mantel (Weber/Graumantel): Revers, Hemdkragen mit Krawatte (zivil), zweireihige Knoepfe, Guertel,
## hochgestellter Kragen, Schulterklappen. Der Schoss haengt an den Beinen (siehe _leg).
static func _coat(b: Kit, st: Dictionary, spec: Array) -> void:
	var tc: Color = st["top_col"]
	var dark := tc.darkened(0.3)
	var civil: bool = st["cap"] == "none"
	var cl := b.k("root", "wool", tc)
	# Rock bis zur Huefte (unterhalb an den Beinen weiter)
	_loft(cl, [[1.0, 0.172 * float(st["build"]) + 0.012, 0.118, -0.004], [0.82, 0.192 * float(st["build"]) + 0.014, 0.134, 0.0]], 26, 2.4, false)
	# Kragen (hochgestellt beim Graumantel, umgelegt bei Weber)
	if civil:
		_loft(cl, [[1.52, 0.09, 0.08, 0.012], [1.585, 0.078, 0.07, 0.014], [1.6, 0.07, 0.064, 0.016]], 20, 2.2, false)
		# Hemdkragen + Krawatte im V-Ausschnitt
		var sh := b.k("root", "cloth", Color(0.9, 0.9, 0.88))
		var f := _front(spec, 0.0, 1.5, 0.002)
		sh.cbox(Vector3(0.0, 1.48, f.z + 0.004), Vector3(0.07, 0.14, 0.008), 0.003)
		for s: float in [-1.0, 1.0]:
			sh.cbox(Vector3(s * 0.022, 1.548, f.z - 0.002), Vector3(0.035, 0.022, 0.006), 0.002, Vector3(0, 0, s * 35.0))
		var tie := b.k("root", "cloth", Color(0.36, 0.08, 0.09))
		tie.cbox(Vector3(0.0, 1.535, f.z - 0.004), Vector3(0.018, 0.016, 0.008), 0.003)
		tie.cbox(Vector3(0.0, 1.47, f.z - 0.003), Vector3(0.026, 0.11, 0.005), 0.002)
	else:
		_loft(cl, [[1.53, 0.088, 0.08, 0.008], [1.64, 0.092, 0.084, 0.01]], 20, 2.2, false)
	# Revers (V-foermig)
	for s: float in [-1.0, 1.0]:
		var pts: Array[Vector3] = []
		for i in 6:
			var t := float(i) / 5.0
			var x := s * lerpf(0.06, 0.03 if civil else 0.0, t)
			var y := lerpf(1.53, 1.28 if civil else 1.36, t)
			pts.append(Vector3(x, y, _front(spec, x, y, 0.006).z))
		for i in pts.size() - 1:
			var a := pts[i]
			var e := pts[i + 1]
			var mid := (a + e) * 0.5
			var d := e - a
			b.k("root", "wool", dark if civil else tc.darkened(0.12)).cbox(mid + Vector3(s * 0.025, 0, 0),
				Vector3(0.06 - float(i) * 0.008, d.length() + 0.006, 0.008), 0.003, Vector3(0, _front(spec, mid.x, mid.y).w, rad_to_deg(atan2(d.x, -d.y))))
	# Knoepfe (zweireihig)
	var bm := b.k("root", "leather", tc.darkened(0.6))
	for y: float in [1.1, 1.2, 1.3]:
		for s: float in [-1.0, 1.0]:
			var f := _front(spec, s * 0.06, y, 0.006)
			_ell(bm, Vector3(f.x, y, f.z), Vector3(0.011, 0.011, 0.005), Vector3.ZERO, 8, 4)
	# Schulterklappen
	for s: float in [-1.0, 1.0]:
		b.k("root", "wool", dark).cbox(Vector3(s * 0.17, 1.54, 0.0), Vector3(0.12, 0.01, 0.045), 0.004, Vector3(0, 0, -s * 15.0))
	_belt(b, st, spec)

## Kampfanzug (Falk): Plattentraeger mit Magazintaschen, Funkgeraet + Antenne, Kummerbund, Rangabzeichen.
static func _combat(b: Kit, st: Dictionary, spec: Array) -> void:
	var gc := SG.gear_colors("reich")
	var g := b.k("root", "gear", gc[0])
	# Kragen des Kampfhemds
	_loft(b.k("root", "camo", Color.WHITE), [[1.53, 0.085, 0.075, 0.008], [1.6, 0.075, 0.068, 0.01]], 20, 2.2, false)
	# Plattentraeger (vorn/hinten etwas flacher, Kummerbund rundherum)
	_loft(g, [[1.06, 0.2, 0.135, -0.008], [1.2, 0.205, 0.142, -0.014], [1.38, 0.212, 0.142, -0.012], [1.44, 0.19, 0.12, -0.004]], 24, 3.2)
	for s: float in [-1.0, 1.0]:
		g.cbox(Vector3(s * 0.12, 1.5, -0.01), Vector3(0.07, 0.04, 0.27), 0.012, Vector3(0, 0, -s * 14.0))
	# Magazintaschen
	var fz := _front(spec, 0.0, 1.16, 0.035).z
	for i in 3:
		var x := -0.075 + 0.075 * float(i)
		g.color = gc[0]
		g.cbox(Vector3(x, 1.15, fz - 0.02), Vector3(0.068, 0.13, 0.05), 0.012)
		g.color = gc[1]
		g.cbox(Vector3(x, 1.215, fz - 0.024), Vector3(0.072, 0.025, 0.056), 0.006)
	# Admin-Tasche mit Rangabzeichen (Oberst: drei Sterne auf Amber-Patch)
	g.color = gc[0]
	g.cbox(Vector3(0.0, 1.31, fz - 0.012), Vector3(0.14, 0.08, 0.03), 0.01)
	b.k("root", "glow", AMBER).cbox(Vector3(0.0, 1.31, fz - 0.03), Vector3(0.07, 0.04, 0.004), 0.002)
	var met := b.k("root", "metal", SILVER)
	for x: float in [-0.02, 0.0, 0.02]:
		for a: float in [0.0, 45.0]:
			met.cbox(Vector3(x, 1.31, fz - 0.034), Vector3(0.011, 0.011, 0.003), 0.001, Vector3(0, 0, a))
	# Funkgeraet an der linken Schulter (Sprechgarnitur) + Rucken-Funkgeraet mit Antenne
	g.color = gc[2]
	g.cbox(Vector3(-0.105, 1.43, fz + 0.01), Vector3(0.05, 0.075, 0.03), 0.008, Vector3(-10, 0, 0))
	g.color = gc[1]
	g.cyl(Vector3(-0.105, 1.47, fz + 0.01), Vector3(-0.06, 1.56, -0.03), 0.006, 6)
	g.color = gc[2]
	g.cbox(Vector3(-0.1, 1.24, 0.17), Vector3(0.09, 0.2, 0.06), 0.012)
	g.color = gc[1]
	g.cyl(Vector3(-0.12, 1.34, 0.18), Vector3(-0.16, 1.82, 0.22), 0.004, 5)
	g.cyl(Vector3(-0.08, 1.34, 0.17), Vector3(-0.08, 1.37, 0.17), 0.009, 8)
	# Trinkblase / Ruecken
	g.color = gc[0]
	g.cbox(Vector3(0.06, 1.22, 0.165), Vector3(0.14, 0.24, 0.05), 0.02)
	_belt(b, st, spec)

# ------------------------------------------------------------------ Kopf

static func _head(b: Kit, st: Dictionary) -> void:
	if bool(st.get("sculpt", false)):
		_head_sculpt(b, st)
		return
	var skin: Color = st["skin"]
	var nw: float = st.get("face_narrow", 1.0)
	var c := SKULL
	var sk := b.k("head", "skin", skin)
	# Hals
	_limb(sk, Vector3(0, -0.05, 0.01), Vector3(0, 0.1, -0.004), 0.052, 0.05, 14)
	# Schaedel, Kiefer, Kinn
	_ell(sk, c + Vector3(0, 0.0, 0.005), Vector3(0.083 * nw, 0.108, 0.098), Vector3.ZERO, 22, 14)
	_ell(sk, c + Vector3(0, -0.062, -0.028), Vector3(0.064 * nw, 0.05, 0.07), Vector3.ZERO, 18, 10)
	for s: float in [-1.0, 1.0]:
		_ell(sk, c + Vector3(s * 0.054 * nw, -0.062, -0.004), Vector3(0.022, 0.032, 0.034), Vector3.ZERO, 10, 6)   # Kieferwinkel
		_ell(sk, c + Vector3(s * 0.047 * nw, -0.008, -0.068), Vector3(0.024, 0.016, 0.022), Vector3.ZERO, 10, 6)  # Wangenknochen
	_ell(sk, c + Vector3(0, -0.097, -0.078), Vector3(0.027, 0.022, 0.022), Vector3.ZERO, 10, 6)                    # Kinn
	_ell(sk, c + Vector3(0, 0.031, -0.084), Vector3(0.066 * nw, 0.016, 0.021), Vector3.ZERO, 14, 6)                 # Brauenwulst
	# Nase
	sk.color = skin.lerp(Color(0.85, 0.5, 0.45), 0.08)
	_ell(sk, c + Vector3(0, 0.0, -0.096), Vector3(0.011, 0.03, 0.013), Vector3(-12, 0, 0), 10, 6)
	_ell(sk, c + Vector3(0, -0.026, -0.11), Vector3(0.0145, 0.0135, 0.0155), Vector3.ZERO, 10, 6)
	for s: float in [-1.0, 1.0]:
		_ell(sk, c + Vector3(s * 0.0135, -0.03, -0.101), Vector3(0.011, 0.0085, 0.01), Vector3.ZERO, 8, 5)
	sk.color = skin.darkened(0.55)
	for s: float in [-1.0, 1.0]:
		_ell(sk, c + Vector3(s * 0.008, -0.037, -0.106), Vector3(0.004, 0.002, 0.004), Vector3.ZERO, 6, 3)  # Nasenloecher
	# Ohren (abstehend: um die Hochachse nach vorn-aussen gedreht)
	var ear_out: float = st.get("ears_out", 18.0)
	for s: float in [-1.0, 1.0]:
		sk.color = skin.lerp(Color(0.9, 0.5, 0.45), 0.12)
		var ec := c + Vector3(s * (0.084 * nw + 0.006), -0.008, 0.014)
		_ell(sk, ec, Vector3(0.0105, 0.033, 0.021), Vector3(0, s * ear_out, 0), 10, 7)
		sk.color = skin.darkened(0.35)
		_ell(sk, ec + Vector3(s * 0.006, -0.002, -0.003), Vector3(0.005, 0.019, 0.011), Vector3(0, s * ear_out, 0), 8, 5)
	# Augen: Lider, Augapfel, Iris, Pupille
	for s: float in [-1.0, 1.0]:
		var ep := c + Vector3(s * 0.032 * nw, 0.01, 0.0)
		var ey := b.k("head", "eye", Color(0.93, 0.92, 0.88))
		_ell(ey, ep + Vector3(0, 0, -0.08), Vector3(0.0125, 0.0125, 0.0125), Vector3.ZERO, 12, 8)
		ey.color = st["eyes"]
		_ell(ey, ep + Vector3(0, -0.0005, -0.0915), Vector3(0.0066, 0.0066, 0.0022), Vector3.ZERO, 12, 4)
		ey.color = Color(0.03, 0.03, 0.03)
		_ell(ey, ep + Vector3(0, -0.0005, -0.0935), Vector3(0.003, 0.003, 0.0008), Vector3.ZERO, 8, 3)
		sk.color = skin.darkened(0.05)
		_ell(sk, ep + Vector3(0, 0.0072, -0.0825), Vector3(0.0165, 0.0072, 0.0125), Vector3(8, 0, 0), 10, 5)     # Oberlid
		_ell(sk, ep + Vector3(0, -0.009, -0.081), Vector3(0.0155, 0.004, 0.0115), Vector3.ZERO, 10, 4)          # Unterlid
	# Augenbrauen (kraeftig, aussen leicht abfallend)
	var bw: float = st["brow_w"]
	var hb := b.k("head", "hair", st["brow_col"])
	for s: float in [-1.0, 1.0]:
		var tilt := -s * 9.0
		if bool(st["smirk"]) and s > 0.0:
			tilt = -s * 3.0   # rechte Braue spoettisch leicht gehoben
		_ell(hb, c + Vector3(s * 0.034 * nw, 0.031 + (0.003 if bool(st["smirk"]) and s > 0.0 else 0.0), -0.1),
			Vector3(0.024, bw, 0.0085), Vector3(0, -s * 12.0, tilt), 10, 4)
	# Mund (leicht spoettisches Laecheln: rechter Mundwinkel hoeher)
	var lip := b.k("head", "skin", skin.lerp(Color(0.72, 0.38, 0.36), 0.45))
	var tilt_m := 5.0 if bool(st["smirk"]) else 0.0
	_ell(lip, c + Vector3(0, -0.05, -0.104), Vector3(0.021, 0.0052, 0.0085), Vector3(0, 0, tilt_m), 10, 4)
	_ell(lip, c + Vector3(0, -0.06, -0.101), Vector3(0.0185, 0.0065, 0.009), Vector3(0, 0, tilt_m * 0.6), 10, 4)
	lip.color = skin.darkened(0.6)
	_ell(lip, c + Vector3(0, -0.055, -0.107), Vector3(0.02, 0.0013, 0.0025), Vector3(0, 0, tilt_m), 8, 2)
	if bool(st["smirk"]):
		lip.color = skin
		_ell(lip, c + Vector3(0.022, -0.049, -0.096), Vector3(0.0075, 0.005, 0.0065), Vector3.ZERO, 8, 4)    # gehobener Mundwinkel
		lip.color = skin.darkened(0.2)
		_ell(lip, c + Vector3(0.03, -0.045, -0.091), Vector3(0.0025, 0.012, 0.004), Vector3(0, 0, 25), 6, 3)  # Laechelfalte
	# Narbe (Falk): ueber die linke Braue auf die Wange
	if bool(st["scar"]):
		var sc := b.k("head", "skin", skin.lerp(Color(0.95, 0.75, 0.72), 0.55))
		_ell(sc, c + Vector3(-0.05, 0.005, -0.09), Vector3(0.0028, 0.042, 0.004), Vector3(-15, 0, -18), 6, 8)
		sc.color = skin.lerp(Color(0.7, 0.3, 0.28), 0.4)
		_ell(sc, c + Vector3(-0.05, 0.005, -0.0915), Vector3(0.001, 0.036, 0.0025), Vector3(-15, 0, -18), 4, 6)
	_hair(b, st)

# ------------------------------------------------------------------ Kopf-Skulptur (ein glattes Mesh)
# Statt vieler sich schneidender Ellipsoide (harte Kanten, "Knetfigur") wird der Kopf als EIN Netz
# gebaut: von einem Punkt im Schaedel aus wird je Richtung die Austrittsdistanz aus allen Gesichts-
# Ellipsoiden bestimmt und weich vereinigt (Soft-Max). Vertex-Farben schminken Augenhoehlen, Wangen,
# Nase, Lippen und den Rasurschatten; der Vollbart ist eine duenne Schale ueber derselben Flaeche.

const SC_NT := 84    # Ringe (Polarwinkel)
const SC_NP := 136   # Segmente (Azimut)
const SC_K := 170.0  # Weichheit der Vereinigung (1/m; ln2/K = maximale Aufdickung)
const SC_O := Vector3(0.0, -0.02, -0.012)   # Strahlursprung relativ zur Schaedelmitte

static var _sculpt_cache: Dictionary = {}

static func _se(c: Vector3, r: Vector3, rot: Vector3 = Vector3.ZERO) -> Array:
	return [c, r, Basis.from_euler(rot * (PI / 180.0)).transposed()]

## Austrittsdistanz des Strahls o + t*d aus einem Ellipsoid (-1 = kein Treffer).
static func _ray_ell(o: Vector3, d: Vector3, e: Array) -> float:
	var bi: Basis = e[2]
	var r: Vector3 = e[1]
	var p := (bi * (o - (e[0] as Vector3))) / r
	var q := (bi * d) / r
	var a := q.dot(q)
	var bb := p.dot(q)
	var disc := bb * bb - a * (p.dot(p) - 1.0)
	if disc <= 0.0:
		return -1.0
	return (-bb + sqrt(disc)) / a

## Weich vereinigte Oberflaechendistanz aller Teile entlang d.
static func _ray_union(parts: Array, o: Vector3, d: Vector3) -> float:
	var ts := PackedFloat32Array()
	var m := 0.0
	for e: Array in parts:
		var t := _ray_ell(o, d, e)
		if t > 0.0:
			ts.append(t)
			m = maxf(m, t)
	var sum := 0.0
	for t in ts:
		sum += exp(SC_K * (t - m))
	return m + log(maxf(sum, 1.0)) / SC_K

## Gesichts-Ellipsoide (relativ zur Schaedelmitte).
static func _face_parts(st: Dictionary) -> Array:
	var nw: float = st.get("face_narrow", 1.0)
	var tilt := 4.0 if bool(st["smirk"]) else 0.0
	var parts: Array = [
		_se(Vector3(0, 0.0, 0.005), Vector3(0.083 * nw, 0.108, 0.098)),            # Schaedel
		_se(Vector3(0, -0.07, -0.03), Vector3(0.058 * nw, 0.046, 0.062)),           # Unterkiefer
		_se(Vector3(0, -0.1, -0.07), Vector3(0.024, 0.018, 0.02)),                 # Kinn
		_se(Vector3(0, 0.031, -0.081), Vector3(0.064 * nw, 0.014, 0.022)),         # Brauenwulst
		_se(Vector3(0, 0.047, -0.063), Vector3(0.058 * nw, 0.028, 0.025)),         # Stirn
		_se(Vector3(0, 0.0, -0.093), Vector3(0.0095, 0.029, 0.013), Vector3(-14, 0, 0)),   # Nasenruecken
		_se(Vector3(0, -0.025, -0.107), Vector3(0.0125, 0.012, 0.014)),            # Nasenspitze
		_se(Vector3(0, -0.049, -0.094), Vector3(0.02, 0.0056, 0.009), Vector3(0, 0, tilt)),      # Oberlippe
		_se(Vector3(0, -0.06, -0.0915), Vector3(0.0175, 0.0066, 0.009), Vector3(0, 0, tilt * 0.6)),  # Unterlippe
		_se(Vector3(0, -0.045, -0.086), Vector3(0.026, 0.016, 0.012)),             # Oberlippen-Wulst
	]
	for s: float in [-1.0, 1.0]:
		parts.append(_se(Vector3(s * 0.052 * nw, -0.064, -0.006), Vector3(0.022, 0.03, 0.034)))   # Kieferwinkel
		parts.append(_se(Vector3(s * 0.046 * nw, -0.01, -0.066), Vector3(0.024, 0.015, 0.022), Vector3(0, s * 25.0, 0)))  # Jochbein
		parts.append(_se(Vector3(s * 0.012, -0.029, -0.098), Vector3(0.01, 0.0075, 0.009)))  # Nasenfluegel
		parts.append(_se(Vector3(s * 0.031 * nw, -0.035, -0.072), Vector3(0.022, 0.022, 0.019)))  # Wange
	return parts

## Dichteverteilte Winkel: mehr Ringe/Segmente um `ctr` (Gesicht), n+1 Werte von lo bis hi.
static func _warp(n: int, lo: float, hi: float, ctr: float, wid: float, boost: float) -> PackedFloat32Array:
	var steps := 600
	var cum := PackedFloat32Array([0.0])
	for i in steps:
		var x := lerpf(lo, hi, (float(i) + 0.5) / float(steps))
		var dx := absf(x - ctr)
		dx = minf(dx, absf(dx - TAU))
		cum.append(cum[i] + 1.0 + boost * exp(-pow(dx / wid, 2.0)))
	var tot := cum[steps]
	var out := PackedFloat32Array()
	var k := 0
	for i in n + 1:
		var target := tot * float(i) / float(n)
		while k < steps - 1 and cum[k + 1] < target:
			k += 1
		var f := (target - cum[k]) / maxf(cum[k + 1] - cum[k], 1e-6)
		out.append(lerpf(lo, hi, (float(k) + clampf(f, 0.0, 1.0)) / float(steps)))
	return out

static func _sc_dir(th: float, ph: float) -> Vector3:
	return Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))

## Kopfoberflaeche als Gitter (gecacht je Gesichtsform): Punkte + Normalen relativ zur Schaedelmitte.
static func _sculpt_grid(st: Dictionary) -> Dictionary:
	var key := "%.3f_%s" % [float(st.get("face_narrow", 1.0)), str(st["smirk"])]
	if _sculpt_cache.has(key):
		return _sculpt_cache[key]
	var parts := _face_parts(st)
	var ths := _warp(SC_NT, 0.02, PI - 0.02, 1.85, 0.7, 2.0)
	var phs := _warp(SC_NP, -PI, PI, -PI * 0.5, 1.1, 2.2)
	var w := SC_NP + 1
	var pts := PackedVector3Array()
	pts.resize((SC_NT + 1) * w)
	for i in SC_NT + 1:
		for j in w:
			var d := _sc_dir(ths[i], phs[j % SC_NP])
			pts[i * w + j] = SC_O + d * _ray_union(parts, SC_O, d)
	var nrm := PackedVector3Array()
	nrm.resize(pts.size())
	for i in SC_NT + 1:
		for j in w:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, SC_NT)
			var j0 := (j - 1 + SC_NP) % SC_NP
			var j1 := (j + 1) % SC_NP
			var n := (pts[i1 * w + j] - pts[i0 * w + j]).cross(pts[i * w + j1] - pts[i * w + j0])
			var radial := (pts[i * w + j] - SC_O).normalized()
			if n.length_squared() < 1e-12:
				n = radial
			n = n.normalized()
			if n.dot(radial) < 0.0:
				n = -n
			nrm[i * w + j] = n
	var g := {"p": pts, "n": nrm, "parts": parts}
	_sculpt_cache[key] = g
	return g

## Oberflaechenpunkt der Skulptur in Richtung eines Zielpunkts (relativ zur Schaedelmitte).
static func _surf(parts: Array, target: Vector3) -> Vector3:
	var d := (target - SC_O).normalized()
	return SC_O + d * _ray_union(parts, SC_O, d)

static func _hash3(p: Vector3) -> float:
	var h := sin(p.dot(Vector3(127.1, 311.7, 74.7)) * 1000.0) * 43758.5453
	return h - floorf(h)

static func _blob(p: Vector3, c: Vector3, r: Vector3) -> float:
	var q := (p - c) / r
	return exp(-q.dot(q))

## Bartdichte 0..1 an p (relativ zur Schaedelmitte): kurz gestutzter Vollbart mit Schnurrbart,
## Wangenlinie schraeg von den Koteletten zum Mundwinkel, Mund frei, Halslinie unter dem Kiefer.
static func _beard_d(p: Vector3) -> float:
	var a := atan2(absf(p.x), -p.z)   # 0 = vorn, PI/2 = seitlich
	var y_top := -0.035 + 0.048 * smoothstep(0.22, 1.5, a)
	var d := smoothstep(y_top + 0.002, y_top - 0.01, p.y)
	# hinten: Koteletten enden vor dem Ohr, unter dem Kiefer laeuft der Bart weiter nach hinten
	var a_max := lerpf(1.56, 1.85, smoothstep(-0.02, -0.08, p.y))
	d *= smoothstep(a_max + 0.04, a_max - 0.05, a)
	# Mund frei
	var e := pow(p.x / 0.0235, 2.0) + pow((p.y + 0.0595) / 0.0102, 2.0)
	if a < 0.9:
		d *= smoothstep(0.85, 1.45, e)
	# nicht auf der Hinterkopf-Unterseite
	d *= smoothstep(0.045, 0.02, p.z) if p.y > -0.1 else 1.0
	return clampf(d, 0.0, 1.0)

static func _skin_col(p: Vector3, st: Dictionary, bd: float) -> Color:
	var skin: Color = st["skin"]
	var nw: float = st.get("face_narrow", 1.0)
	var c := skin
	var shade := Color(skin.r * 0.72, skin.g * 0.6, skin.b * 0.58)
	var warm := skin.lerp(Color(0.86, 0.42, 0.36), 0.55)
	for s: float in [-1.0, 1.0]:
		c = c.lerp(shade, 0.42 * _blob(p, Vector3(s * 0.032 * nw, 0.014, -0.082), Vector3(0.024, 0.016, 0.03)))  # Augenhoehle
		c = c.lerp(warm, 0.22 * _blob(p, Vector3(s * 0.048 * nw, -0.024, -0.072), Vector3(0.022, 0.02, 0.03)))   # Wangen
		c = c.lerp(shade, 0.25 * _blob(p, Vector3(s * 0.021, -0.028, -0.098), Vector3(0.006, 0.012, 0.012)))     # Nasenfluegel-Falte
		c = c.lerp(shade, 0.3 * _blob(p, Vector3(s * 0.011, -0.006, -0.088), Vector3(0.006, 0.02, 0.01)))        # Nasenflanke
	c = c.lerp(warm, 0.35 * _blob(p, Vector3(0, -0.025, -0.118), Vector3(0.014, 0.012, 0.012)))                   # Nasenspitze
	c = c.lerp(shade, 0.18 * _blob(p, Vector3(0, 0.03, -0.1), Vector3(0.06, 0.008, 0.02)) * clampf(-p.y * 50.0 + 1.5, 0.0, 1.0))
	# Lippen
	var lip := skin.lerp(Color(0.7, 0.33, 0.32), 0.6)
	var lw := maxf(_blob(p, Vector3(0, -0.05, -0.1), Vector3(0.019, 0.0055, 0.014)),
		_blob(p, Vector3(0, -0.0605, -0.098), Vector3(0.017, 0.0068, 0.014)))
	c = c.lerp(lip, clampf(lw * 1.6, 0.0, 0.85))
	# Rasurschatten (Glatze seitlich/hinten) und Bartgrund
	if st["hair"] == "bald":
		var side := smoothstep(-0.02, 0.06, p.z + absf(p.x) * 0.6) * smoothstep(0.075, 0.035, p.y) * smoothstep(-0.06, -0.02, p.y)
		c = c.lerp(skin.darkened(0.12).lerp(Color(0.45, 0.42, 0.42), 0.15), 0.6 * side)
	if bd > 0.0:
		c = c.lerp(Color(st["beard_col"]), 0.55 * bd)
	return c

static func _tri_c(k: MK, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-16:
		return
	k.color = ca
	k._v(a, na)
	if n.dot(na + nb + nc) > 0.0:
		k.color = cc
		k._v(c, nc)
		k.color = cb
		k._v(b, nb)
	else:
		k.color = cb
		k._v(b, nb)
		k.color = cc
		k._v(c, nc)

## Gitter ausgeben; `use` (optional) waehlt Vierecke, bei denen mindestens eine Ecke gesetzt ist.
static func _emit_grid(k: MK, pts: PackedVector3Array, nrm: PackedVector3Array, cols: PackedColorArray,
		off: Vector3, use: PackedByteArray = PackedByteArray()) -> void:
	var w := SC_NP + 1
	for i in SC_NT:
		for j in SC_NP:
			var ia := i * w + j
			var ib := ia + 1
			var ic := ia + w + 1
			var id := ia + w
			if not use.is_empty() and use[ia] + use[ib] + use[ic] + use[id] == 0:
				continue
			_tri_c(k, pts[ia] + off, pts[ib] + off, pts[ic] + off, nrm[ia], nrm[ib], nrm[ic], cols[ia], cols[ib], cols[ic])
			_tri_c(k, pts[ia] + off, pts[ic] + off, pts[id] + off, nrm[ia], nrm[ic], nrm[id], cols[ia], cols[ic], cols[id])

static func _head_sculpt(b: Kit, st: Dictionary) -> void:
	var skin: Color = st["skin"]
	var nw: float = st.get("face_narrow", 1.0)
	var c := SKULL
	var g := _sculpt_grid(st)
	var pts: PackedVector3Array = g["p"]
	var nrm: PackedVector3Array = g["n"]
	var parts: Array = g["parts"]
	var full_beard: bool = st["beard"] == "full"
	var bds := PackedFloat32Array()
	bds.resize(pts.size())
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for i in pts.size():
		var bd := _beard_d(pts[i]) if full_beard else 0.0
		bds[i] = bd
		cols[i] = _skin_col(pts[i], st, bd)
	var sk := b.k("head", "skin", skin)
	_emit_grid(sk, pts, nrm, cols, c)
	# Hals
	sk.color = skin.darkened(0.04)
	_limb(sk, Vector3(0, -0.06, 0.012), Vector3(0, 0.1, -0.004), 0.05, 0.048, 16)
	# Kurzer Vollbart: Schale ueber der Haut, Rand taucht weich unter die Haut ab
	if full_beard:
		var bc: Color = st["beard_col"]
		var bp := PackedVector3Array()
		bp.resize(pts.size())
		var bcol := PackedColorArray()
		bcol.resize(pts.size())
		var use := PackedByteArray()
		use.resize(pts.size())
		for i in pts.size():
			var p := pts[i]
			var bd := bds[i]
			var chin := _blob(p, Vector3(0, -0.105, -0.07), Vector3(0.035, 0.03, 0.04))
			var tk := 0.0034 + 0.0008 * chin
			bp[i] = p + nrm[i] * lerpf(-0.003, tk, smoothstep(0.05, 0.75, bd))
			var n := _hash3(p)
			var col := bc.lerp(Color(0.42, 0.2, 0.1), 0.35 * smoothstep(-0.02, -0.07, p.y) * (1.0 - chin))   # rotbraune Wangen
			col = col.darkened(0.18 * smoothstep(-0.09, -0.12, p.y))   # dunkler unter dem Kinn
			col = col.lerp(col.lightened(0.2), n * 0.35).darkened((1.0 - n) * 0.08)
			bcol[i] = col.lerp(skin.lerp(bc, 0.6), 1.0 - smoothstep(0.1, 0.65, bd))
			use[i] = 1 if bd > 0.02 else 0
		_emit_grid(b.k("head", "hair", bc), bp, nrm, bcol, c, use)
	# Ohren (abstehend)
	var ear_out: float = st.get("ears_out", 18.0)
	for s: float in [-1.0, 1.0]:
		var ec := c + Vector3(s * (0.084 * nw + 0.004), -0.006, 0.016)
		sk.color = skin.lerp(Color(0.85, 0.45, 0.4), 0.2)
		_ell(sk, ec, Vector3(0.0095, 0.032, 0.02), Vector3(0, s * ear_out, 0), 12, 8)
		_ell(sk, ec + Vector3(s * 0.002, 0.012, 0.004), Vector3(0.008, 0.016, 0.015), Vector3(0, s * ear_out, s * 10.0), 8, 6)
		sk.color = skin.lerp(Color(0.85, 0.45, 0.4), 0.3).darkened(0.25)
		_ell(sk, ec + Vector3(s * 0.006, -0.002, -0.002), Vector3(0.005, 0.018, 0.011), Vector3(0, s * ear_out, 0), 8, 5)
		sk.color = skin.lerp(Color(0.85, 0.45, 0.4), 0.15)
		_ell(sk, ec + Vector3(-s * 0.002, -0.006, -0.018), Vector3(0.006, 0.012, 0.007), Vector3.ZERO, 8, 5)  # Tragus-Ansatz
	# Augen: Augapfel, Iris, Pupille, Lider (in die Haut eingebettet)
	for s: float in [-1.0, 1.0]:
		var ep := c + Vector3(s * 0.032 * nw, 0.01, 0.0)
		var ey := b.k("head", "eye", Color(0.86, 0.83, 0.78))
		_ell(ey, ep + Vector3(0, 0, -0.078), Vector3(0.0125, 0.0125, 0.0125), Vector3.ZERO, 12, 8)
		ey.color = st["eyes"]
		_ell(ey, ep + Vector3(0, -0.0008, -0.0895), Vector3(0.0062, 0.0062, 0.0022), Vector3.ZERO, 12, 4)
		ey.color = Color(0.03, 0.03, 0.03)
		_ell(ey, ep + Vector3(0, -0.0008, -0.0915), Vector3(0.0028, 0.0028, 0.0008), Vector3.ZERO, 8, 3)
		sk.color = skin.lerp(Color(skin.r * 0.72, skin.g * 0.6, skin.b * 0.58), 0.35)
		_ell(sk, ep + Vector3(0, 0.0068, -0.0805), Vector3(0.0158, 0.0078, 0.0128), Vector3(14, 0, 0), 12, 6)   # Oberlid
		sk.color = skin.lerp(Color(skin.r * 0.72, skin.g * 0.6, skin.b * 0.58), 0.25)
		_ell(sk, ep + Vector3(0, -0.0092, -0.0795), Vector3(0.0148, 0.0042, 0.0118), Vector3(-6, 0, 0), 12, 4)  # Unterlid
		# Lidfalte
		_cord(b.k("head", "skin", skin.darkened(0.3)), [ep + Vector3(-0.013, 0.0125, -0.086), ep + Vector3(0, 0.0152, -0.0915),
			ep + Vector3(0.013, 0.0125, -0.086)] as Array[Vector3], 0.0009)
	# Augenbrauen: auf der Flaeche aufliegend, kraeftig, aussen leicht abfallend
	var bw: float = st["brow_w"]
	var hb := b.k("head", "hair", st["brow_col"])
	for s: float in [-1.0, 1.0]:
		var lift := 0.003 if bool(st["smirk"]) and s > 0.0 else 0.0
		for q in 5:
			var t := float(q) / 4.0
			var x := s * lerpf(0.014, 0.05, t) * nw
			var y := 0.03 + lift + sin(t * PI) * 0.0035 - t * (0.006 if lift == 0.0 else 0.003)
			var sp := _surf(parts, Vector3(x, y, -0.1))
			_ell(hb, c + sp + Vector3(0, 0, 0.0015), Vector3(0.0075, bw * lerpf(1.1, 0.75, t), 0.0045),
				Vector3(0, -s * lerpf(5.0, 35.0, t), 0), 8, 4)
	# Nasenloecher
	sk.color = skin.darkened(0.6)
	for s: float in [-1.0, 1.0]:
		var np := _surf(parts, Vector3(s * 0.0075, -0.037, -0.1))
		_ell(sk, c + np + Vector3(0, 0.0015, 0.0), Vector3(0.0038, 0.0018, 0.0045), Vector3(0, -s * 20.0, 0), 6, 3)
	# Mundspalte (spoettisch: rechter Mundwinkel leicht gehoben)
	var ml: Array[Vector3] = []
	for q in 9:
		var x := lerpf(-0.021, 0.022, float(q) / 8.0)
		var y := -0.0553 + (pow(maxf(x, 0.0) / 0.022, 2.0) * 0.0045 if bool(st["smirk"]) else 0.0) + absf(x) * 0.02
		ml.append(c + _surf(parts, Vector3(x, y, -0.1)) + Vector3(0, 0, 0.0004))
	_cord(b.k("head", "skin", skin.lerp(Color(0.3, 0.12, 0.1), 0.75)), ml, 0.0011)

static func _hair(b: Kit, st: Dictionary) -> void:
	if bool(st.get("sculpt", false)):
		return   # Glatze/Bart stecken in der Skulptur
	var c := SKULL
	var nw: float = st.get("face_narrow", 1.0)
	var hc: Color = st["hair_col"]
	match str(st["hair"]):
		"buzz", "short":
			var hr := b.k("head", "hair", hc)
			var g := 0.003 if st["hair"] == "buzz" else 0.007
			var rr := Vector3(0.083 * nw + g, 0.108 + g, 0.098 + g)
			_ell(hr, c + Vector3(0, 0, 0.005), rr, Vector3.ZERO, 22, 6, 0.0, 0.36 * PI)
			# Seiten und Hinterkopf (vorne frei fuer die Stirn)
			_ell(hr, c + Vector3(0, 0, 0.005), rr, Vector3.ZERO, 16, 6, 0.36 * PI, 0.62 * PI, -0.12 * PI, 1.12 * PI)
		"parted":
			var hr := b.k("head", "hair", hc)
			var rr := Vector3(0.083 * nw + 0.011, 0.108 + 0.014, 0.098 + 0.01)
			_ell(hr, c + Vector3(0, 0.002, 0.004), rr, Vector3(0, 0, 0), 22, 7, 0.0, 0.38 * PI)
			_ell(hr, c + Vector3(0, 0.0, 0.006), rr - Vector3(0.003, 0.003, 0.0), Vector3.ZERO, 16, 6, 0.36 * PI, 0.6 * PI, -0.14 * PI, 1.14 * PI)
			hr.color = hc.lightened(0.25)
			_ell(hr, c + Vector3(-0.035, 0.105, -0.01), Vector3(0.004, 0.006, 0.08), Vector3(0, 0, 18), 4, 6)   # Scheitel
			hr.color = hc
			_ell(hr, c + Vector3(0.018, 0.088, -0.07), Vector3(0.06, 0.025, 0.035), Vector3(0, 0, -8), 12, 6)   # Tolle
		_:
			# Glatze: nur ein Hauch Rasurschatten am Hinterkopf
			var hr := b.k("head", "skin", Color(st["skin"]).darkened(0.08))
			_ell(hr, c + Vector3(0, -0.004, 0.006), Vector3(0.083 * nw + 0.0006, 0.1086, 0.0986), Vector3.ZERO, 16, 5, 0.42 * PI, 0.66 * PI, -0.05 * PI, 1.05 * PI)
	# Bart
	var bc: Color = st["beard_col"]
	match str(st["beard"]):
		"full":
			var bd := b.k("head", "hair", bc)
			# dichter kurzer Vollbart: Kiefer, Wangen, Kinn; Schnurrbart geht in den Bart ueber
			# Seiten ab Wangenlinie, Mitte erst unter der Unterlippe (Mund bleibt frei)
			var br := Vector3(0.076 * nw, 0.066, 0.082)
			var bctr := c + Vector3(0, -0.06, -0.022)
			_ell(bd, bctr, br, Vector3.ZERO, 8, 8, 0.4 * PI, PI, -1.12 * PI, -0.62 * PI)
			_ell(bd, bctr, br, Vector3.ZERO, 8, 8, 0.4 * PI, PI, -0.38 * PI, 0.12 * PI)
			_ell(bd, bctr, br, Vector3.ZERO, 5, 6, 0.55 * PI, PI, -0.62 * PI, -0.38 * PI)
			_ell(bd, c + Vector3(0, -0.102, -0.074), Vector3(0.032, 0.029, 0.028), Vector3.ZERO, 12, 6)
			for s: float in [-1.0, 1.0]:
				_ell(bd, c + Vector3(s * 0.074 * nw, -0.012, 0.004), Vector3(0.014, 0.042, 0.03), Vector3.ZERO, 8, 6)   # Koteletten
				_ell(bd, c + Vector3(s * 0.058 * nw, -0.05, -0.048), Vector3(0.026, 0.04, 0.04), Vector3.ZERO, 10, 6)  # Wange
				_ell(bd, c + Vector3(s * 0.024, -0.052, -0.101), Vector3(0.008, 0.016, 0.008), Vector3(0, 0, s * 12.0), 6, 5)   # Mundwinkel
			_ell(bd, c + Vector3(0, -0.041, -0.106), Vector3(0.03, 0.0085, 0.0095), Vector3.ZERO, 12, 5)            # Schnurrbart
			bd.color = bc.lightened(0.12)
			_ell(bd, c + Vector3(0, -0.075, -0.098), Vector3(0.016, 0.012, 0.01), Vector3.ZERO, 8, 4)               # unter der Lippe
		"stubble":
			var bd := b.k("head", "skin", Color(st["skin"]).lerp(bc, 0.45))
			_ell(bd, c + Vector3(0, -0.062, -0.028), Vector3(0.0652 * nw, 0.0512, 0.0712), Vector3.ZERO, 18, 6, 0.45 * PI, PI, -1.1 * PI, 0.1 * PI)
			_ell(bd, c + Vector3(0, -0.097, -0.078), Vector3(0.0282, 0.0232, 0.0232), Vector3.ZERO, 10, 5)
			_ell(bd, c + Vector3(0, -0.04, -0.103), Vector3(0.024, 0.006, 0.006), Vector3.ZERO, 8, 3)
	# Brille
	if bool(st["glasses"]):
		var fr := b.k("head", "metal", Color(0.25, 0.24, 0.22))
		for s: float in [-1.0, 1.0]:
			var ctr := c + Vector3(s * 0.032 * nw, 0.008, -0.104)
			var pts: Array[Vector3] = []
			for i in 13:
				var a := TAU * float(i) / 12.0
				pts.append(ctr + Vector3(cos(a) * 0.021, sin(a) * 0.0155, 0.0))
			_cord(fr, pts, 0.0016)
			_cord(fr, [ctr + Vector3(s * 0.021, 0.004, 0.0), c + Vector3(s * (0.084 * nw + 0.004), 0.01, -0.02),
				c + Vector3(s * (0.086 * nw + 0.002), 0.0, 0.03)] as Array[Vector3], 0.0014)
			_ell(b.k("head", "glass", Color.WHITE), ctr + Vector3(0, 0, 0.001), Vector3(0.0205, 0.015, 0.002), Vector3.ZERO, 12, 4)
		_cord(fr, [c + Vector3(-0.011, 0.012, -0.106), c + Vector3(0, 0.016, -0.108), c + Vector3(0.011, 0.012, -0.106)] as Array[Vector3], 0.0016)

# ------------------------------------------------------------------ Kopfbedeckung

## Vorderkante der Muetzenkrone (z) auf Hoehe h ueber der Schaedelmitte bei Querversatz x.
static func _crown_z(h: float, x: float, flare: float) -> float:
	var prof: Array = [[0.078, 0.093, 0.105, 0.002], [0.1, 0.106 + flare * 0.6, 0.12 + flare * 0.6, -0.006],
		[0.113, 0.094 + flare, 0.107 + flare, -0.012]]
	var r := _at(prof, h)
	var q := clampf(x / float(r[0]), -0.97, 0.97)
	return float(r[2]) - float(r[1]) * pow(1.0 - pow(absf(q), 2.2), 1.0 / 2.2)

static func _headgear(b: Kit, st: Dictionary) -> void:
	var c := SKULL
	var cc: Color = st["cap_col"]
	var trim: Color = st["trim"]
	match str(st["cap"]):
		"schirm", "feld":
			var feld: bool = st["cap"] == "feld"
			var flare := 0.016 if feld else 0.03
			var band := b.k("cap", "wool", st["cap_band"] if not feld else cc.darkened(0.15))
			_loft(band, [[c.y + 0.032, 0.088, 0.1, 0.004], [c.y + 0.078, 0.091, 0.103, 0.002]], 26, 2.2, false)
			var cr := b.k("cap", "wool", cc)
			_loft(cr, [[c.y + 0.078, 0.093, 0.105, 0.002], [c.y + 0.1, 0.106 + flare * 0.6, 0.12 + flare * 0.6, -0.006],
				[c.y + 0.113, 0.094 + flare, 0.107 + flare, -0.012], [c.y + 0.121, 0.09 + flare, 0.103 + flare, -0.012],
				[c.y + 0.127, 0.05, 0.06, -0.01], [c.y + 0.129, 0.004, 0.004, -0.01]], 26, 2.2, false)
			# Paspel (General: Gold)
			if st.has("cap_piping"):
				var pp := b.k("cap", "metal", st["cap_piping"])
				_loft(pp, [[c.y + 0.111, 0.096 + flare, 0.109 + flare, -0.012], [c.y + 0.116, 0.096 + flare, 0.109 + flare, -0.012]], 26, 2.2, false)
				_loft(pp, [[c.y + 0.076, 0.093, 0.105, 0.002], [c.y + 0.081, 0.093, 0.105, 0.002]], 26, 2.2, false)
			# Schirm (schwarz lackiert, vorn abfallend)
			var vz := b.k("cap", "boot", Color(0.04, 0.04, 0.045))
			var vlen := 0.045 if feld else 0.062
			_ell(vz, c + Vector3(0, 0.036, -0.086), Vector3(0.084, 0.0045, vlen), Vector3(-20, 0, 0), 18, 4, 0.0, PI, -PI, 0.0)
			# Kordel und Knoepfe
			var g := b.k("cap", "metal", trim)
			if not feld:
				for yy: float in [0.04, 0.05]:
					var pts: Array[Vector3] = []
					for i in 11:
						var a := lerpf(-0.75, 0.75, float(i) / 10.0) * 0.5 * PI
						pts.append(Vector3(sin(a) * 0.093, c.y + yy, 0.004 - cos(a) * 0.106))
					_cord(g, pts, 0.0034)
				for s: float in [-1.0, 1.0]:
					var a := s * 0.375 * PI
					_ell(g, Vector3(sin(a) * 0.094, c.y + 0.045, 0.004 - cos(a) * 0.107), Vector3(0.006, 0.006, 0.006), Vector3.ZERO, 6, 4)
			# Kokarde (Amber/schwarz) und Emblem der Ordnungsfront (gebrochener Ring mit Klinge, fiktiv)
			var fz := 0.004 - 0.104 - 0.003
			var ck := b.k("cap", "metal", Color(0.08, 0.08, 0.08))
			_ell(ck, Vector3(0, c.y + 0.065, fz), Vector3(0.011, 0.011, 0.004), Vector3.ZERO, 10, 4)
			_ell(b.k("cap", "glow", AMBER), Vector3(0, c.y + 0.065, fz - 0.003), Vector3(0.006, 0.006, 0.002), Vector3.ZERO, 8, 3)
			# Emblem liegt auf der schraeg nach vorn gezogenen Kronenfront (z je Punkt aus dem Kronenprofil)
			var ring: Array[Vector3] = []
			for i in 10:
				var a := deg_to_rad(40.0 + 30.0 * float(i))
				var x := cos(a) * 0.015
				var h := 0.094 + sin(a) * 0.011
				ring.append(Vector3(x, c.y + h, _crown_z(h, x, flare) - 0.003))
			_cord(g, ring, 0.0024)
			var blade: Array[Vector3] = []
			for h: float in [0.08, 0.094, 0.108]:
				var x := 0.004 - (h - 0.094) * 0.35
				blade.append(Vector3(x, c.y + h, _crown_z(h, x, flare) - 0.004))
			_cord(g, blade, 0.0026)
			if not feld:
				for s: float in [-1.0, 1.0]:
					var wing: Array[Vector3] = []
					for q: Vector2 in [Vector2(0.02, 0.09), Vector2(0.034, 0.096), Vector2(0.046, 0.104)]:
						wing.append(Vector3(s * q.x, c.y + q.y, _crown_z(q.y, q.x, flare) - 0.003))
					_cord(g, wing, 0.0021)   # Schwingen
		"beret":
			var be := b.k("cap", "wool", cc)
			_loft(b.k("cap", "leather", Color(0.05, 0.05, 0.05)), [[c.y + 0.045, 0.088, 0.101, 0.004], [c.y + 0.062, 0.088, 0.101, 0.004]], 24, 2.2, false)
			_ell(be, c + Vector3(0.012, 0.082, 0.01), Vector3(0.106, 0.04, 0.114), Vector3(0, 0, -11), 22, 8)
			var g := b.k("cap", "metal", trim)
			var bz := c + Vector3(-0.04, 0.072, -0.098)
			_ell(g, bz, Vector3(0.013, 0.016, 0.004), Vector3(0, 22, 0), 10, 4)
			g.color = trim.darkened(0.4)
			g.cbox(bz + Vector3(0.0, 0.0, -0.004), Vector3(0.004, 0.022, 0.003), 0.001, Vector3(0, 22, -20))

# ------------------------------------------------------------------ Arme / Beine

static func _arm(b: Kit, st: Dictionary, s: float) -> void:
	var part := "arm_l" if s < 0.0 else "arm_r"
	var top: String = st["top"]
	var tc: Color = st["top_col"]
	var mat := "camo" if top == "combat" else "wool"
	var sl := b.k(part, mat, tc)
	var w: float = st["build"]
	var r := 1.0 + (0.12 if top == "coat" else (0.08 if top == "combat" else 0.0))
	# Schultergelenk sitzt innen/unter dem Pivot (Pivot bleibt fuer die Cutscene-Posen bei +-0.31/1.58);
	# der Arm haengt leicht schraeg nach aussen, die Hand landet wieder nahe x = 0 (Requisiten in der Hand).
	var j := Vector3(-s * 0.074, -0.098, 0.006)
	var el := Vector3(-s * 0.05, -0.37, 0.018)
	var wr := Vector3(-s * 0.03, -0.598, -0.016)
	# flacher Deltamuskel, laeuft schraeg in die Schulterlinie des Rocks
	_ell(sl, j + Vector3(-s * 0.004, 0.008, 0.0), Vector3(0.052 * w * r, 0.046, 0.056 * r), Vector3(0, 0, -s * 22.0), 16, 10)
	_limb(sl, j, el, 0.048 * w * r, 0.04 * r, 16)
	_limb(sl, el, wr + Vector3(0, 0.01, 0), 0.04 * r, 0.034 * r, 16)
	# Aermelaufschlag
	if top == "coat" or bool(st["cuffs"]):
		var cf := b.k(part, mat, tc.darkened(0.14))
		_loft(cf, [[wr.y + 0.006, 0.0375 * r, 0.0375 * r, wr.z + 0.001], [wr.y + 0.012, 0.039 * r, 0.039 * r, wr.z + 0.001],
			[wr.y + 0.052, 0.0405 * r, 0.0405 * r, wr.z - 0.002], [wr.y + 0.058, 0.039 * r, 0.039 * r, wr.z - 0.002]], 18, 2.0, false, wr.x)
		if top == "tunic":
			for yy: float in [0.02, 0.04]:
				_ell(b.k(part, "metal", st["trim"]), Vector3(wr.x + s * 0.038, wr.y + yy, wr.z + 0.012), Vector3(0.004, 0.005, 0.005), Vector3.ZERO, 6, 3)
	elif top == "combat":
		# Aermeltasche + Ellbogenschoner
		var gc := SG.gear_colors("reich")
		b.k(part, "gear", gc[0]).cbox(Vector3(j.x + s * 0.048, -0.17, -0.0), Vector3(0.02, 0.09, 0.075), 0.006)
		_ell(b.k(part, "gear", gc[1]), el + Vector3(0, 0, 0.03), Vector3(0.042, 0.05, 0.03), Vector3.ZERO, 10, 6)
	# Armbinde (Amber, links)
	if bool(st["armband"]) and s < 0.0:
		var ax := lerpf(j.x, el.x, 0.3)
		_loft(b.k(part, "glow", AMBER), [[-0.2, 0.05 * r, 0.05 * r, 0.009], [-0.15, 0.0525 * r, 0.0525 * r, 0.008]], 16, 2.0, false, ax)
	# Hand (Handschuh, falls gesetzt) – modelliert um das alte Handgelenk, verschoben und leicht verkleinert
	var gl: Color = st["gloves"]
	var hk := b.k(part, "leather" if gl.a > 0.0 else "skin", gl if gl.a > 0.0 else Color(st["skin"]).darkened(0.03))
	var wrist := Vector3(0, -0.595, -0.024)
	var hs := 0.9
	var old_xf := hk.xf
	hk.xf = Transform3D(Basis.from_scale(Vector3.ONE * hs), wr - wrist * hs)
	_limb(hk, Vector3(0, -0.57, -0.022), wrist, 0.033, 0.03, 10)
	_ell(hk, Vector3(-s * 0.003, -0.64, -0.03), Vector3(0.019, 0.047, 0.04), Vector3(4, 0, 0), 12, 7)
	var fl := [0.068, 0.078, 0.074, 0.062]
	for i in 4:
		var z := -0.062 + 0.018 * float(i)
		var a := Vector3(-s * 0.002, -0.678, z)
		var mid := a + Vector3(-s * 0.004, -float(fl[i]) * 0.55, -0.004)
		var tip := mid + Vector3(-s * 0.014, -float(fl[i]) * 0.4, -0.008)
		_limb(hk, a, mid, 0.0092, 0.0085, 8)
		_limb(hk, mid, tip, 0.0085, 0.0075, 8)
	_limb(hk, Vector3(-s * 0.012, -0.615, -0.062), Vector3(-s * 0.024, -0.665, -0.078), 0.012, 0.0095, 8)
	if gl.a <= 0.0:
		var nail := b.k(part, "skin", Color(st["skin"]).lightened(0.15))
		nail.xf = hk.xf
		for i in 4:
			var z := -0.062 + 0.018 * float(i)
			var tip := Vector3(-s * 0.02, -0.678 - float(fl[i]) * 0.95, z - 0.012)
			_ell(nail, tip + Vector3(0, 0.004, -0.003), Vector3(0.006, 0.006, 0.003), Vector3.ZERO, 6, 3)
		nail.xf = old_xf
	else:
		# Handschuh-Stulpe ueber dem Aermelsaum
		_loft(hk, [[-0.565, 0.034, 0.036, -0.022], [-0.595, 0.031, 0.033, -0.024]], 14, 2.0, false)
	hk.xf = old_xf

static func _leg(b: Kit, st: Dictionary, s: float) -> void:
	var part := "leg_l" if s < 0.0 else "leg_r"
	var top: String = st["top"]
	var tcol: Color = st["trouser_col"]
	var mat := "camo" if top == "combat" else "wool"
	var tr := b.k(part, mat, tcol)
	var boots: String = st["boots"]
	# Oberschenkel / Knie / Unterschenkel
	_limb(tr, Vector3(0, 0.03, 0.0), Vector3(0, -0.43, -0.006), 0.088, 0.062, 14)
	if bool(st["breeches"]):
		# Stiefelhose: seitlich ausgestellte Reithose
		var slim := bool(st.get("slim_legs", false))
		var bx := 0.012 if slim else 0.018
		var br := Vector3(0.088, 0.17, 0.086) if slim else Vector3(0.098, 0.17, 0.092)
		_ell(tr, Vector3(s * bx, -0.17, 0.004), br, Vector3(0, 0, s * 4.0), 16, 10)
		if bool(st["stripes"]):
			# doppelte Generals-Lampassen in Rot (aussen)
			var lp := b.k(part, "wool", GENERAL_RED)
			_ell(lp, Vector3(s * bx, -0.17, 0.004), br + Vector3(0.002, 0.002, 0.002), Vector3(0, 0, s * 4.0), 12, 10,
				0.12 * PI, 0.9 * PI, (0.0 if s > 0.0 else PI) - 0.13, (0.0 if s > 0.0 else PI) + 0.13)
			lp.color = tcol
			_ell(lp, Vector3(s * bx, -0.17, 0.004), br + Vector3(0.0028, 0.0028, 0.0028), Vector3(0, 0, s * 4.0), 4, 10,
				0.12 * PI, 0.9 * PI, (0.0 if s > 0.0 else PI) - 0.02, (0.0 if s > 0.0 else PI) + 0.02)
	else:
		_limb(tr, Vector3(0, -0.43, -0.006), Vector3(0, -0.8, 0.0), 0.062, 0.054, 14)
		if bool(st["stripes"]):
			b.k(part, "wool", GENERAL_RED).cbox(Vector3(s * 0.082, -0.3, 0.0), Vector3(0.006, 0.5, 0.03), 0.002)
	# Mantelschoss an den Beinen (schwingt mit, kein Durchstechen)
	if top == "coat":
		var cc: Color = st["top_col"]
		var lo := -0.5 if st["cap"] == "none" else -0.58
		_loft(b.k(part, "wool", cc), [[-0.06, 0.12, 0.145, 0.0], [lo, 0.13, 0.16, 0.005], [lo - 0.012, 0.126, 0.156, 0.005]], 20, 2.4, false, -s * 0.004)
		_loft(b.k(part, "wool", cc.darkened(0.15)), [[lo - 0.012, 0.126, 0.156, 0.005], [lo - 0.014, 0.1, 0.13, 0.005]], 20, 2.4, false, -s * 0.004)
	# Knieschoner + Beinholster (Falk)
	if top == "combat":
		var gc := SG.gear_colors("reich")
		var g := b.k(part, "gear", gc[1])
		_ell(g, Vector3(0, -0.45, -0.058), Vector3(0.05, 0.06, 0.024), Vector3.ZERO, 12, 6)
		g.color = gc[0]
		g.cbox(Vector3(s * 0.07, -0.13, -0.025), Vector3(0.022, 0.08, 0.08), 0.006)   # Beintasche
		if s > 0.0:
			g.color = gc[1]
			g.cbox(Vector3(0.088, -0.2, -0.01), Vector3(0.04, 0.17, 0.085), 0.012)   # Pistolenholster rechts
			g.cbox(Vector3(0.08, -0.12, -0.01), Vector3(0.05, 0.022, 0.1), 0.006)
	# Schuhwerk
	var bk := b.k(part, "boot", Color(0.035, 0.033, 0.032))
	match boots:
		"tall":
			_limb(bk, Vector3(0, -0.38, -0.003), Vector3(0, -0.84, 0.002), 0.066, 0.05, 16)
			_loft(bk, [[-0.395, 0.068, 0.068, -0.004], [-0.37, 0.07, 0.07, -0.004]], 16, 2.0, false)
		"combat":
			bk.color = Color(0.07, 0.065, 0.06)
			_limb(bk, Vector3(0, -0.68, 0.0), Vector3(0, -0.84, 0.0), 0.058, 0.054, 14)
		_:
			_limb(bk, Vector3(0, -0.8, 0.0), Vector3(0, -0.85, 0.0), 0.05, 0.048, 12)
	_ell(bk, Vector3(0, -0.855, -0.06), Vector3(0.048, 0.042, 0.122), Vector3.ZERO, 14, 7)
	var sole := Color(0.06, 0.05, 0.045) if boots != "combat" else Color(0.05, 0.05, 0.05)
	var so := b.k(part, "leather", sole)
	so.cbox(Vector3(0, -0.886, -0.065), Vector3(0.098, 0.026, 0.26), 0.008)
	so.cbox(Vector3(0, -0.878, 0.035), Vector3(0.08, 0.044, 0.07), 0.008)
	if boots == "combat":
		# Schnuerung
		var ls := b.k(part, "leather", Color(0.12, 0.11, 0.1))
		for i in 5:
			ls.cbox(Vector3(0, -0.7 - float(i) * 0.03, -0.055), Vector3(0.05, 0.006, 0.006), 0.002)
