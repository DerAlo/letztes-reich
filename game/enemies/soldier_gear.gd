extends RefCounted
## Realismus-Upgrade fuer das SWAT-Soldatenmodell:
## - prepare_mesh(): schreibt Ruhepose-Position/-Normale (Skelettraum, Meter) in CUSTOM0/CUSTOM1, damit
##   soldier_cloth.gdshader Tarnmuster/Stoffstruktur triplanar und OHNE "Schwimmen" bei Animation aufbringt.
## - Ausruestung (Helmbezug/NVG-Halter, Magazintaschen, Funkgeraet, Trinkrucksack, Handschuhe) wird in
##   soldier_visual.gd ueber build_* angehaengt (MeshKit, je Knochen ein Mesh = ein Draw Call).

const MK = preload("res://game/vehicles/models/mesh_kit.gd")
const CLOTH_SHADER := "res://game/enemies/soldier_cloth.gdshader"
const LINEN_N := "res://assets/characters/textures/rough_linen/normal.jpg"
const LINEN_ARM := "res://assets/characters/textures/rough_linen/arm.jpg"
const CAMO_TEX := {
	"ru": "res://assets/characters/textures/camo_ru_digital.png",
	"reich": "res://assets/characters/textures/camo_reich_urban.png",
}

static var _mesh_cache: Dictionary = {}
static var _mat_cache: Dictionary = {}

## Ersetzt mi.mesh durch eine (gecachte) Kopie mit Ruhepose-Daten in CUSTOM0 (Position) und CUSTOM1 (Normale).
static func prepare_mesh(mi: MeshInstance3D, sk: Skeleton3D) -> void:
	var src := mi.mesh as ArrayMesh
	if src == null or mi.skin == null:
		return
	var key := "%s|%s" % [src.resource_path if src.resource_path != "" else str(src.get_instance_id()), mi.name]
	if _mesh_cache.has(key):
		mi.mesh = _mesh_cache[key]
		return
	var skin := mi.skin
	var bind_xf: Array[Transform3D] = []
	for b in skin.get_bind_count():
		var bi := skin.get_bind_bone(b)
		if bi < 0:
			bi = sk.find_bone(skin.get_bind_name(b))
		var rest := sk.get_bone_global_rest(bi) if bi >= 0 else Transform3D.IDENTITY
		bind_xf.append(rest * skin.get_bind_pose(b))
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var a := src.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
		var per := bones.size() / maxi(v.size(), 1)
		var c0 := PackedFloat32Array()
		var c1 := PackedFloat32Array()
		c0.resize(v.size() * 4)
		c1.resize(v.size() * 4)
		for i in v.size():
			var p := Vector3.ZERO
			var nn := Vector3.ZERO
			var wsum := 0.0
			for j in per:
				var w := weights[i * per + j]
				if w <= 0.0:
					continue
				var t := bind_xf[bones[i * per + j]]
				p += (t * v[i]) * w
				nn += (t.basis * n[i]) * w
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
		var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		if per == 8:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [], {}, flags)
		out.surface_set_material(s, src.surface_get_material(s))
		out.surface_set_name(s, src.surface_get_name(s))
	_mesh_cache[key] = out
	mi.mesh = out

## Stoff-/Ausruestungsmaterial (ShaderMaterial, gecacht).
## mode 0 = Tarnstoff, 1 = Ausruestung (Cordura, einfarbig), 2 = Haut/Gesicht (nur leichtes Rauschen).
static func cloth_mat(faction: String, mode: int, base: Color, tint_key: String = "") -> ShaderMaterial:
	var key := "%s|%d|%s|%s" % [faction, mode, base.to_html(), tint_key]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(CLOTH_SHADER) as Shader
	var camo_path: String = CAMO_TEX.get(faction, CAMO_TEX["ru"])
	if ResourceLoader.exists(camo_path):
		m.set_shader_parameter("camo_tex", load(camo_path))
	if ResourceLoader.exists(LINEN_N):
		m.set_shader_parameter("weave_normal", load(LINEN_N))
		m.set_shader_parameter("weave_arm", load(LINEN_ARM))
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("base_col", base)
	match mode:
		0:
			m.set_shader_parameter("rough", 0.88)
			m.set_shader_parameter("weave_strength", 0.55)
		1:
			m.set_shader_parameter("rough", 0.78 if faction != "reich" else 0.55)
			m.set_shader_parameter("metal", 0.0 if faction != "reich" else 0.25)
			m.set_shader_parameter("weave_strength", 0.7)
		_:
			m.set_shader_parameter("rough", 0.55)
			m.set_shader_parameter("weave_strength", 0.08)
	_mat_cache[key] = m
	return m

## Material fuer starre Anbauteile (MeshKit, Vertex-Farbe = Albedo; Stoffstruktur triplanar im Objektraum).
static func gear_mat(key: String) -> StandardMaterial3D:
	if _mat_cache.has("gear_" + key):
		return _mat_cache["gear_" + key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.82
	if ResourceLoader.exists(LINEN_N):
		m.normal_enabled = true
		m.normal_texture = load(LINEN_N)
		m.normal_scale = 0.8
		m.ao_enabled = true
		m.ao_texture = load(LINEN_ARM)
		m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
		m.ao_light_affect = 0.4
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(9, 9, 9)
		m.uv1_triplanar_sharpness = 2.0
	if key.begins_with("reich"):
		m.roughness = 0.6
	_mat_cache["gear_" + key] = m
	return m

## Einfarbiges Ausruestungsmaterial fuer Primitive ohne Vertex-Farben (z. B. Platten des Schweren).
static func flat_gear(c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var key := "flat_%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := gear_mat(key).duplicate() as StandardMaterial3D
	m.vertex_color_use_as_albedo = false
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_mat_cache[key] = m
	return m

## Farbsatz der Ausruestung je Fraktion: [Cordura, dunkel/Gurtband, Metall/Kunststoff, Akzent].
static func gear_colors(faction: String) -> Array[Color]:
	if faction == "reich":
		return [Color(0.095, 0.1, 0.105), Color(0.04, 0.042, 0.045), Color(0.2, 0.205, 0.21), Color(1.0, 0.6, 0.12)]
	return [Color(0.2, 0.22, 0.14), Color(0.075, 0.08, 0.06), Color(0.12, 0.12, 0.11), Color(0.32, 0.29, 0.2)]

# ------------------------------------------------------------------ Anbauteile
# Jede Baugruppe haengt an einem Knochen, ihr Rahmen ist aber an der RUHEPOSE ausgerichtet
# (Ursprung = REST_ORIGIN[gruppe] im Skelettraum, Achsen = Skelettachsen: +Y oben, +Z vorne).

const REST_ORIGIN := {
	"chest": ["Chest", Vector3(0.004, 1.3, 0.09)],
	"hips": ["Abdomen", Vector3(0.01, 0.985, 0.055)],
	"head": ["Head", Vector3(0.004, 1.556, 0.089)],
}

## Brust: drei Gewehr-Magazintaschen, Admin-Tasche, Schulterpolster, Funkgeraet mit Antenne, Trinkrucksack.
static func build_chest(k: MK, faction: String, heavy: bool) -> void:
	var c := gear_colors(faction)
	var fz := 0.128 if heavy else 0.1    # Vorderseite Weste/Platte auf Taschenhoehe
	var bz := -0.15 if heavy else -0.118 # Rueckseite
	for i in 3:
		var x := -0.072 + 0.072 * float(i)
		k.color = c[0]
		k.cbox(Vector3(x, -0.085, fz + 0.022), Vector3(0.064, 0.115, 0.05), 0.012, Vector3(-8, 0, 0))
		k.color = c[1]
		k.cbox(Vector3(x, -0.03, fz + 0.027), Vector3(0.068, 0.022, 0.056), 0.006, Vector3(-8, 0, 0))   # Klappe
		k.color = c[2]
		k.cbox(Vector3(x, -0.055, fz + 0.051), Vector3(0.018, 0.03, 0.006), 0.002, Vector3(-8, 0, 0))   # Zuglasche
	k.color = c[0]
	k.cbox(Vector3(-0.065, 0.045, fz + 0.012), Vector3(0.09, 0.075, 0.03), 0.008, Vector3(-10, 0, 0))   # Admin-Tasche
	k.color = c[1]
	k.cbox(Vector3(0.075, 0.06, fz + 0.006), Vector3(0.028, 0.045, 0.02), 0.006, Vector3(-10, 0, 0))   # Sprechtaste (PTT)
	# Schulterpolster
	k.color = c[0]
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.105, 0.15, -0.005), Vector3(0.075, 0.03, 0.22), 0.012)
	# Funkgeraet links hinten mit Antenne
	k.color = c[2]
	k.cbox(Vector3(-0.11, 0.0, bz - 0.028), Vector3(0.065, 0.15, 0.045), 0.01)
	k.color = c[1]
	k.cbox(Vector3(-0.11, -0.01, bz - 0.03), Vector3(0.075, 0.06, 0.05), 0.006)
	k.cyl(Vector3(-0.125, 0.07, bz - 0.04), Vector3(-0.15, 0.45, bz - 0.07), 0.004, 5)
	k.color = c[2]
	k.cyl(Vector3(-0.095, 0.07, bz - 0.03), Vector3(-0.095, 0.095, bz - 0.03), 0.008, 6)
	if not heavy:
		# Trinkrucksack
		k.color = c[0]
		k.cbox(Vector3(0.03, -0.07, bz - 0.04), Vector3(0.16, 0.24, 0.06), 0.025)
		k.color = c[1]
		k.cbox(Vector3(0.03, 0.0, bz - 0.073), Vector3(0.12, 0.012, 0.012), 0.003)
		k.cbox(Vector3(0.03, -0.1, bz - 0.073), Vector3(0.12, 0.012, 0.012), 0.003)
	if faction == "reich":
		# Amber-Erkennungsstreifen auf den Schulterpolstern
		k.color = c[3]
		for sx: float in [-1.0, 1.0]:
			k.cbox(Vector3(sx * 0.105, 0.167, 0.02), Vector3(0.077, 0.004, 0.05), 0.001)

## Huefte: Koppel mit Taschen (Granate, Verbandspaeckchen, Abwurfsack) und Schnalle.
static func build_hips(k: MK, faction: String) -> void:
	var c := gear_colors(faction)
	k.color = c[1]
	var ring := MK.superellipse(0.165, 0.135, 2.6, 20)
	var rings: Array[PackedVector3Array] = []
	for y: float in [-0.022, 0.022]:
		var r := PackedVector3Array()
		for p in ring:
			r.append(Vector3(p.x, y, p.y))
		rings.append(r)
	k.loft(rings, false, false, true)
	k.color = c[0]
	k.cbox(Vector3(0.15, -0.035, 0.06), Vector3(0.045, 0.085, 0.065), 0.012)
	k.cbox(Vector3(-0.15, -0.04, 0.04), Vector3(0.045, 0.095, 0.075), 0.014)
	k.cbox(Vector3(0.08, -0.04, -0.13), Vector3(0.085, 0.08, 0.045), 0.012)
	k.color = c[2]
	k.cbox(Vector3(0.0, 0.0, 0.138), Vector3(0.05, 0.034, 0.012), 0.004)

## Helm: NVG-Halterung (Shroud), Akkupack hinten, ARC-Seitenschienen, Gummiband des Helmbezugs.
static func build_head(k: MK, faction: String) -> void:
	var c := gear_colors(faction)
	k.color = c[2]
	k.cbox(Vector3(0, 0.205, 0.142), Vector3(0.05, 0.045, 0.02), 0.008, Vector3(-30, 0, 0))   # NVG-Shroud
	k.color = c[1]
	k.cbox(Vector3(0, 0.18, 0.158), Vector3(0.03, 0.03, 0.03), 0.006, Vector3(-30, 0, 0))
	k.color = c[0]
	k.cbox(Vector3(0, 0.215, -0.11), Vector3(0.07, 0.05, 0.03), 0.01, Vector3(30, 0, 0))   # Akkupack
	k.color = c[1]
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.116, 0.16, 0.02), Vector3(0.012, 0.022, 0.13), 0.004)   # ARC-Schienen
	var ring := MK.superellipse(0.118, 0.132, 2.2, 20)
	var rings: Array[PackedVector3Array] = []
	for y: float in [0.192, 0.204]:
		var r := PackedVector3Array()
		for p in ring:
			r.append(Vector3(p.x, y, p.y + 0.02))
		rings.append(r)
	k.loft(rings, false, false, true)
	if faction == "reich":
		k.color = c[3]
		k.cbox(Vector3(0, 0.258, 0.0), Vector3(0.012, 0.008, 0.15), 0.002)   # Amber-Kennstreifen

# ------------------------------------------------------------------ Rollen-Ausruestung (Gegnertypen)

## Sturmsoldat, Kopf: Gesichtsschutz (untere Gesichtshaelfte) + Schutzbrille auf dem Helm.
static func build_assault_head(k: MK, faction: String) -> void:
	var c := gear_colors(faction)
	k.color = c[1]
	k.cbox(Vector3(0, 0.03, 0.13), Vector3(0.14, 0.08, 0.05), 0.022, Vector3(-6, 0, 0))   # Maske
	k.color = c[2]
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.032, 0.025, 0.158), Vector3(0.026, 0.034, 0.012), 0.004)       # Filter
	k.color = Color(0.06, 0.065, 0.07)
	k.cbox(Vector3(0, 0.2, 0.135), Vector3(0.15, 0.04, 0.035), 0.012, Vector3(-25, 0, 0))   # Brille auf dem Helm
	k.color = c[3] if faction == "reich" else Color(0.5, 0.42, 0.18)
	k.cbox(Vector3(0, 0.2, 0.154), Vector3(0.12, 0.022, 0.004), 0.002, Vector3(-25, 0, 0))  # Glas

## Sturmsoldat, Brust: Patronen-Bandolier quer ueber die Weste.
static func build_assault_chest(k: MK, faction: String) -> void:
	var c := gear_colors(faction)
	var a := Vector3(0.13, 0.16, 0.06)
	var b := Vector3(-0.13, -0.2, 0.17)
	var dir := b - a
	var ang := rad_to_deg(atan2(dir.y, dir.x))
	k.color = c[1].lerp(Color(0.25, 0.17, 0.09), 0.5)
	k.cbox((a + b) * 0.5, Vector3(dir.length(), 0.045, 0.012), 0.004, Vector3(0, 0, ang))
	for i in 9:
		var t := 0.12 + 0.76 * float(i) / 8.0
		var p := a.lerp(b, t) + Vector3(0, 0, 0.012)
		k.color = Color(0.55, 0.42, 0.16) if faction == "ru" else Color(0.42, 0.4, 0.36)
		k.cbox(p, Vector3(0.018, 0.04, 0.02), 0.004, Vector3(0, 0, ang + 90.0))

static func _ghillie_cols(faction: String) -> Array[Color]:
	if faction == "reich":
		return [Color(0.1, 0.104, 0.11), Color(0.05, 0.05, 0.055), Color(0.16, 0.16, 0.155), Color(0.03, 0.03, 0.035)]
	return [Color(0.15, 0.14, 0.075), Color(0.1, 0.12, 0.06), Color(0.19, 0.15, 0.09), Color(0.08, 0.09, 0.05)]

## Ghillie-Haube des Scharfschuetzen: Stoffkuppel ueber dem Helm + herabhaengende Streifen.
static func build_ghillie(k: MK, faction: String) -> void:
	var cols := _ghillie_cols(faction)
	k.color = cols[0]
	var prof := PackedVector2Array()
	for i in 9:
		var a := deg_to_rad(lerpf(-8.0, 90.0, float(i) / 8.0))
		prof.append(Vector2(0.125 * sin(a), maxf(0.163 * cos(a), 0.0)))
	k.lathe(Vector3(0, 0.15, -0.005), Vector3.UP, prof, 14)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in 64:
		var yaw := rng.randf() * TAU
		if absf(wrapf(yaw, -PI, PI)) < 0.55 and i % 3 != 0:   # Gesicht weitgehend frei
			yaw += PI * 0.5
		var up := rng.randf_range(0.0, 1.0)
		var r := lerpf(0.15, 0.06, up * up)
		var y := 0.1 + up * 0.17
		var ln := rng.randf_range(0.07, 0.17) * (1.4 if cos(yaw) < 0.0 else 1.0)
		var p := Vector3(sin(yaw) * r, y - ln * 0.4, cos(yaw) * r)
		k.color = cols[rng.randi() % cols.size()]
		k.cbox(p, Vector3(0.022, ln, 0.006), 0.002, Vector3(rng.randf_range(-18, 18), rad_to_deg(yaw), rng.randf_range(-15, 15)))

## Ghillie-Umhang auf Schultern/Ruecken.
static func build_ghillie_back(k: MK, faction: String) -> void:
	var cols := _ghillie_cols(faction)
	var rng := RandomNumberGenerator.new()
	rng.seed = 815
	for i in 36:
		var x := rng.randf_range(-0.17, 0.17)
		var ln := rng.randf_range(0.12, 0.26)
		var z := rng.randf_range(-0.2, -0.13) if i % 4 != 0 else rng.randf_range(-0.05, 0.05)
		var y := 0.17 - ln * 0.45 + rng.randf_range(-0.02, 0.02)
		if i % 4 == 0:
			y = 0.19
			ln = 0.05
		k.color = cols[rng.randi() % cols.size()]
		k.cbox(Vector3(x, y, z), Vector3(0.03, ln, 0.008), 0.002, Vector3(rng.randf_range(-10, 10), rng.randf_range(-25, 25), rng.randf_range(-12, 12)))

## Offizier: eigener Kopf (Haut), Schirmmuetze, Sonnenbrille (Swat_Head ist ausgeblendet).
static func build_officer_head(k: MK, faction: String, skin: Color) -> void:
	var c := gear_colors(faction)
	k.color = skin * Color(0.62, 0.56, 0.52)
	var prof := PackedVector2Array()
	for i in 11:
		var a := deg_to_rad(lerpf(-90.0, 90.0, float(i) / 10.0))
		prof.append(Vector2(0.118 * sin(a), 0.092 * cos(a)))
	k.lathe(Vector3(0, 0.1, 0.025), Vector3.UP, prof, 16)                      # Schaedel
	k.cyl(Vector3(0, -0.06, 0.0), Vector3(0, 0.02, 0.015), 0.058, 10)          # Hals
	k.cbox(Vector3(0, 0.025, 0.07), Vector3(0.1, 0.06, 0.06), 0.025)           # Kiefer
	k.cbox(Vector3(0, 0.085, 0.12), Vector3(0.022, 0.04, 0.025), 0.008, Vector3(15, 0, 0))   # Nase
	for sx: float in [-1.0, 1.0]:
		k.cbox(Vector3(sx * 0.093, 0.09, 0.02), Vector3(0.015, 0.045, 0.03), 0.006)          # Ohren
	k.color = Color(0.03, 0.03, 0.035)
	k.cbox(Vector3(0, 0.112, 0.111), Vector3(0.135, 0.032, 0.012), 0.006)       # Sonnenbrille
	k.color = Color(0.15, 0.14, 0.12)
	k.cbox(Vector3(0, 0.126, 0.113), Vector3(0.14, 0.006, 0.01), 0.002)
	var cap := Color(0.22, 0.25, 0.15) if faction == "ru" else Color(0.06, 0.062, 0.068)
	var band := Color(0.55, 0.06, 0.05) if faction == "ru" else c[3]
	k.color = band
	k.cyl(Vector3(0, 0.145, 0.025), Vector3(0, 0.178, 0.025), 0.1, 16)        # Muetzenband
	k.color = cap
	k.lathe(Vector3(0, 0.178, 0.03), Vector3.UP, PackedVector2Array([
		Vector2(0, 0), Vector2(0, 0.1), Vector2(0.035, 0.128), Vector2(0.05, 0.13), Vector2(0.056, 0.11), Vector2(0.057, 0)]), 18)
	k.color = Color(0.04, 0.04, 0.045)
	k.cbox(Vector3(0, 0.152, 0.13), Vector3(0.16, 0.012, 0.075), 0.005, Vector3(-14, 0, 0))   # Schirm
	k.color = Color(0.75, 0.62, 0.25) if faction == "ru" else c[3]
	k.cbox(Vector3(0, 0.19, 0.128), Vector3(0.03, 0.03, 0.01), 0.004)         # Kokarde

## Offizier, Ruecken: Funkgeraet-Rucksack mit langer Peitschenantenne; Kartentasche vorne.
static func build_officer_chest(k: MK, faction: String) -> void:
	var c := gear_colors(faction)
	var bz := -0.118
	k.color = c[2]
	k.cbox(Vector3(0.0, -0.04, bz - 0.075), Vector3(0.21, 0.27, 0.09), 0.02)   # Funkgeraet
	k.color = c[1]
	k.cbox(Vector3(0.0, 0.03, bz - 0.123), Vector3(0.17, 0.08, 0.012), 0.004)
	k.color = Color(0.1, 0.1, 0.1)
	k.cyl(Vector3(0.07, 0.09, bz - 0.09), Vector3(0.07, 0.13, bz - 0.09), 0.014, 8)   # Antennenfuss
	k.cyl(Vector3(0.07, 0.13, bz - 0.09), Vector3(0.1, 0.95, bz - 0.17), 0.0045, 5)   # Peitschenantenne
	k.color = c[3] if faction == "reich" else Color(0.7, 0.1, 0.08)
	k.cyl(Vector3(0.1, 0.95, bz - 0.17), Vector3(0.101, 0.98, bz - 0.172), 0.008, 6)  # Spitze (Wimpel)
	k.color = c[2]
	k.cyl(Vector3(-0.06, 0.09, bz - 0.09), Vector3(-0.07, 0.11, bz - 0.09), 0.01, 6)
	k.color = c[0].lerp(Color(0.25, 0.18, 0.1), 0.4)
	k.cbox(Vector3(0.11, -0.2, 0.12), Vector3(0.07, 0.1, 0.035), 0.01, Vector3(0, 0, -6))  # Kartentasche
