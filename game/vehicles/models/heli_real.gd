extends RefCounted
## Echte Hubschraubermodelle (glTF, vorgebacken durch tools/bake_heli_models.gd) mit denselben
## Teile-Schluesseln wie heli_model.gd: blades/rotor/disc/disc_mat/tail_rotor/tail_disc_mat/blade_meshes,
## gun_yaw/gun_pitch/muzzle/flash, searchlight_mount, nav_l/nav_r/strobe, exhaust_l/exhaust_r.
## Zusaetzlich: root, tail_axis (lokale Drehachse von tail_rotor), source ("gltf"/"procedural"), kind,
## hitboxes (Array[AABB] im Pivot-Raum), tail_z (Heckende).
## Fehlt die .scn-Datei, baut build() das prozedurale heli_model.gd (gleiche Schluessel).
## Koordinaten wie heli_model: -Z = vorne, Hauptrotorachse bei x = z = 0, Kufen/Raeder bei y = -1.94.
##
## Die Wrapper mi8_model.gd / mi28_model.gd liefern build(pivot, faction) fuer ModelCache.

const VF = preload("res://game/vehicles/vehicle_fx.gd")
const HeliModel = preload("res://game/vehicles/models/heli_model.gd")

const MI8_SCENE := "res://assets/models/vehicles/mi8/mi8.scn"
const MI28_SCENE := "res://assets/models/vehicles/mi28n/mi28n.scn"

## Je Modell: Lichter, Suchscheinwerfer, Abgase, virtuelle Kanone (Mi-8), Trefferzonen (Mitte, Groesse).
const SPEC := {
	"mi8": {
		"scene": MI8_SCENE,
		"nav_l": Vector3(-2.3, -0.55, 1.5), "nav_r": Vector3(2.5, -0.55, 1.5), "strobe": Vector3(0.18, 2.55, 13.3),
		"searchlight": Vector3(0.1, -1.35, -3.6),
		"exhaust_l": Vector3(-0.9, 2.0, 1.6), "exhaust_r": Vector3(1.1, 2.0, 1.6),
		"gun": Vector3(0.1, -1.2, -3.9),   # keine echte Kanone: unsichtbarer Mount (Bordschuetze/Raketen)
		"tail_z": 13.0,
		"hitboxes": [
			[Vector3(0.1, 0.25, -0.55), Vector3(3.3, 4.2, 9.2)],    # Kabine/Cockpit (erstes = Zielpunkt)
			[Vector3(0.15, 0.9, 8.6), Vector3(1.2, 2.2, 9.2)],     # Heckausleger + Seitenleitwerk
			[Vector3(0.1, -0.9, 1.5), Vector3(4.8, 1.6, 1.6)],     # Zusatztanks/Fahrwerk
		],
	},
	"mi28n": {
		"scene": MI28_SCENE,
		"nav_l": Vector3(-3.38, -0.1, 1.0), "nav_r": Vector3(3.44, -0.1, 1.0), "strobe": Vector3(-0.45, 1.75, 11.2),
		"searchlight": Vector3(0.05, -0.95, -3.6),
		"exhaust_l": Vector3(-1.95, 0.6, 4.6), "exhaust_r": Vector3(1.95, 0.6, 4.6),
		"gun": Vector3.ZERO,   # echte Kinnkanone aus dem Modell (GunYaw)
		"tail_z": 11.5,
		"hitboxes": [
			[Vector3(0.05, 0.2, -1.6), Vector3(2.3, 2.8, 7.2)],    # Rumpf/Cockpit (erstes = Zielpunkt)
			[Vector3(0.05, 0.1, 3.4), Vector3(4.0, 2.0, 3.2)],     # Triebwerke
			[Vector3(0.05, 0.0, 8.0), Vector3(1.3, 1.8, 7.2)],     # Heckausleger + Leitwerk
			[Vector3(0.05, 0.3, 1.0), Vector3(6.8, 0.6, 2.2)],     # Stummelfluegel
		],
	},
}

## Lackierung je Modell (Material-Name aus dem glTF -> Albedo-Kopie + matte Werte). Texturen aus
## tools/paint_heli_textures.py: Mi-8 mattes Oliv ohne Aeroflot/CCCP-Kennung, Mi-28N dunkles Anthrazit (Garde).
## Fehlende Eintraege/Dateien -> Originalmaterial.
const TEX8 := "res://assets/models/vehicles/mi8/textures/"
const TEX28 := "res://assets/models/vehicles/mi28n/textures/"
const PAINT := {
	"mi8": {
		"texture1": {"albedo": TEX8 + "texture1_baseColor_mil.png", "metallic": 0.1, "roughness": 0.78},
		"texture2": {"albedo": TEX8 + "texture2_baseColor_mil.png", "metallic": 0.15, "roughness": 0.74},
		"rotor": {"albedo": TEX8 + "rotor_baseColor_mil.png", "metallic": 0.15, "roughness": 0.72},
		"cockpit": {"metallic": 0.1, "roughness": 0.7},
	},
	"mi28n": {
		"Body": {"albedo": TEX28 + "Body_baseColor_garde.png", "metallic": 0.1, "roughness": 0.76},
		"inter": {"metallic": 0.15, "roughness": 0.7},
	},
}

static var _scenes := {}   # Pfad -> PackedScene (bleibt geladen, kein Nachlade-Ruckler)
static var _painted := {}  # Original-Material -> lackierte Kopie (von allen Instanzen geteilt)

static func scene_path(kind: String) -> String:
	return String(SPEC.get(kind, SPEC["mi28n"])["scene"])

static func available(kind: String) -> bool:
	return ResourceLoader.exists(scene_path(kind))

## Laedt die Szenen vorab (Ladebildschirm). Mehrfachaufruf billig.
static func preload_all() -> void:
	for k in SPEC:
		_scene(String(k))

static func _scene(kind: String) -> PackedScene:
	var p := scene_path(kind)
	if _scenes.has(p):
		return _scenes[p]
	var ps: PackedScene = null
	if ResourceLoader.exists(p):
		ps = load(p) as PackedScene
	_scenes[p] = ps
	return ps

static func build(pivot: Node3D, faction: String, kind: String) -> Dictionary:
	var ps := _scene(kind)
	if ps == null:
		push_warning("heli_real: %s fehlt - prozedurales Modell" % scene_path(kind))
		var po: Dictionary = HeliModel.build(pivot, faction)
		po["source"] = "procedural"
		po["kind"] = "procedural"
		po["tail_axis"] = Vector3.RIGHT
		return po
	var spec: Dictionary = SPEC[kind]
	var root := ps.instantiate() as Node3D
	root.scene_file_path = ""   # als normale Knoten behandeln (ModelCache dupliziert alle Kinder)
	root.name = kind.to_upper()
	pivot.add_child(root)
	var out: Dictionary = {"root": root, "source": "gltf", "kind": kind, "tail_axis": Vector3.RIGHT}
	for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_apply_paint(mi as MeshInstance3D, kind)

	# --- Hauptrotor: MainRotor (lokal Y = Achse) > Blades > Hub, Arm<i> > Blade<i>
	var rotor := root.get_node("MainRotor") as Node3D
	var blades := rotor.get_node("Blades") as Node3D
	var blade_list: Array[MeshInstance3D] = []
	for arm in blades.get_children():
		for c in arm.get_children():
			if c is MeshInstance3D:
				blade_list.append(c)
	var radius: float = root.get_meta("rotor_radius", 8.0)
	var disc_mesh := PlaneMesh.new()
	disc_mesh.size = Vector2.ONE * radius * 2.0
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = load("res://game/vehicles/shaders/rotor_blur.gdshader")
	disc_mat.set_shader_parameter("blades", float(root.get_meta("main_blades", 5)))
	var disc := VF.mesh_node(rotor, disc_mesh, disc_mat, Vector3(0, 0.02, 0))
	disc.name = "Disc"
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["rotor"] = rotor
	out["blades"] = blades
	out["blade_meshes"] = blade_list
	out["disc"] = disc
	out["disc_mat"] = disc_mat

	# --- Heckrotor: TailRotor (lokal X = Achse) > TailBlades
	var tail := root.get_node("TailRotor") as Node3D
	var tail_blades := tail.get_node("TailBlades") as Node3D
	var tr: float = root.get_meta("tail_radius", 1.5)
	var tdisc_mesh := PlaneMesh.new()
	tdisc_mesh.size = Vector2.ONE * tr * 2.0
	var tdisc_mat := disc_mat.duplicate() as ShaderMaterial
	tdisc_mat.set_shader_parameter("blades", float(root.get_meta("tail_blades", 4)))
	tdisc_mat.set_shader_parameter("opacity", 0.28)
	var tdisc := VF.mesh_node(tail, tdisc_mesh, tdisc_mat, Vector3.ZERO, Vector3(0, 0, 90))
	tdisc.name = "TailDisc"
	tdisc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	out["tail_rotor"] = tail_blades
	out["tail_disc_mat"] = tdisc_mat

	# --- Kanone (Mi-28N: echtes Modell; Mi-8: unsichtbarer Mount unter der Nase)
	var gy := root.get_node_or_null("GunYaw") as Node3D
	var gp: Node3D
	var muzzle: Marker3D
	if gy != null:
		gp = gy.get_node("GunPitch") as Node3D
		muzzle = gp.get_node("Muzzle") as Marker3D
	else:
		gy = Node3D.new()
		gy.name = "GunYaw"
		gy.position = spec["gun"]
		root.add_child(gy)
		gp = Node3D.new()
		gp.name = "GunPitch"
		gy.add_child(gp)
		muzzle = Marker3D.new()
		muzzle.name = "Muzzle"
		muzzle.position = Vector3(0, 0, -0.6)
		gp.add_child(muzzle)
	out["gun_yaw"] = gy
	out["gun_pitch"] = gp
	out["muzzle"] = muzzle
	out["flash"] = VF.make_muzzle_flash(muzzle, 0.9, 8.0, 10.0)

	var sl := Marker3D.new()
	sl.name = "SearchlightMount"
	sl.position = spec["searchlight"]
	root.add_child(sl)
	out["searchlight_mount"] = sl
	out["exhaust_l"] = spec["exhaust_l"]
	out["exhaust_r"] = spec["exhaust_r"]
	out["nav_l"] = _light_bulb(root, spec["nav_l"], Color(1.0, 0.05, 0.03))
	out["nav_r"] = _light_bulb(root, spec["nav_r"], Color(0.1, 1.0, 0.2))
	out["strobe"] = _light_bulb(root, spec["strobe"], Color(1.0, 0.1, 0.05))
	out["tail_z"] = float(spec["tail_z"])
	out["hitboxes"] = hitboxes(kind)
	return out

## Lackierung als Oberflaechen-Override (ModelCache-Klone uebernehmen die Overrides).
static func _apply_paint(mi: MeshInstance3D, kind: String) -> void:
	var table: Dictionary = PAINT.get(kind, {})
	if table.is_empty() or mi.mesh == null:
		return
	for s in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(s) as StandardMaterial3D
		if src == null or not table.has(src.resource_name):
			continue
		if not _painted.has(src):
			var cfg: Dictionary = table[src.resource_name]
			var m := src.duplicate() as StandardMaterial3D
			if cfg.has("albedo") and ResourceLoader.exists(cfg["albedo"]):
				m.albedo_texture = load(cfg["albedo"]) as Texture2D
			m.metallic = float(cfg.get("metallic", m.metallic))
			m.metallic_texture = null
			m.roughness = float(cfg.get("roughness", m.roughness))
			m.roughness_texture = null
			m.metallic_specular = 0.4
			# texture1: Occlusion-Kanal = Helligkeit der Originaltextur inkl. Aeroflot/CCCP-Schrift -> aus
			m.ao_enabled = false
			m.ao_texture = null
			_painted[src] = m
		mi.set_surface_override_material(s, _painted[src])

## Trefferzonen im Pivot-Raum (Mitte, Groesse). Erstes Element = Zielpunkt des Bots.
static func hitboxes(kind: String) -> Array:
	var out: Array = []
	for hb: Array in SPEC.get(kind, SPEC["mi28n"])["hitboxes"]:
		out.append(AABB(hb[0] - hb[1] * 0.5, hb[1]))
	return out

static func _light_bulb(parent: Node3D, pos: Vector3, c: Color) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 6.0
	var mi := VF.mesh_node(parent, VF.sphere(0.07, -1.0, 8), m, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var l := OmniLight3D.new()
	l.light_color = c
	l.omni_range = 2.2
	l.light_energy = 0.5   # nah am echten Rumpf: schwaecher als beim Blockmodell, sonst gluehen die Flanken
	l.shadow_enabled = false
	mi.add_child(l)
	return mi
