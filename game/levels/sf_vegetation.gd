extends RefCounted
## Modellierte Vegetation von Sketchfab (CC-BY 4.0, LOLIPOP; Nachweise in assets/CREDITS_ASSETS.md):
##  - "Oak trees pack (17var, LODs, seasons, gameready)": Eichen LOD0 (auch fuer den fernen Wald, als
##    MultiMesh-Zellen mit Importer-LODs: oak_grove); Billboard-Kreuze (oak_billboards) nur noch Reserve,
##    aus der Naehe wirkten sie wie Pappaufsteller
##  - "Shrub tiles pack (3 vars, seamless)": Buchsbaum-Heckenblock (TileExample), segmentweise gestreckt
## Ausgeduennt mit tools/prune_gltf.py (nur benutzte Baeume, Texturen 1K / Billboards 512).
## Alle Funktionen liefern false, wenn das Asset fehlt; der Aufrufer baut dann seine prozedurale Version.

const OAK := "res://assets/environment/vegetation/oak/scene.gltf"
const HEDGE := "res://assets/environment/vegetation/hedge/scene.gltf"
## Baumarten -> LOD0-Knoten (Hoehen: medium ~10,4 m, small ~5,6 m, large ~26 m, big ~19,6 m)
const OAKS := {
	"medium_a": "Medium_oak_tree__001", "medium_b": "Medium_oak_tree__002", "small": "Small_oak_tree__001",
	"large_a": "Large_oak_tree_001", "large_b": "Large_oak_tree_002", "big": "Big_oak_tree__001",
}

static var _cache: Dictionary = {}

static func _xf(n: Node, stop: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n != null and n != stop:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

## Teile [[Mesh, Transform3D]] eines Knotens samt AABB; "foot" = Stammfuss (Mittel der tiefsten Rindenpunkte).
static func _load(path: String, node_name: String) -> Dictionary:
	var key := path + "#" + node_name
	if _cache.has(key):
		return _cache[key]
	var out := {}
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps != null:
			var inst := ps.instantiate()
			var base := inst.find_child(node_name, true, false)
			if base != null:
				var parts: Array = []
				var box := AABB()
				var first := true
				var foot := Vector3.INF
				for mi_n in base.find_children("*", "MeshInstance3D", true, false) + ([base] if base is MeshInstance3D else []):
					var mi := mi_n as MeshInstance3D
					if mi.mesh == null:
						continue
					var xf := _xf(mi, null)
					parts.append([mi.mesh, xf])
					var bb: AABB = xf * mi.mesh.get_aabb()
					box = bb if first else box.merge(bb)
					first = false
					for si in mi.mesh.get_surface_count():
						var mat := mi.mesh.surface_get_material(si)
						if mat is BaseMaterial3D:
							var bm := mat as BaseMaterial3D
							if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
								bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
								bm.alpha_scissor_threshold = 0.45
								bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
								if path == OAK:
									# in der Ferne duennen die Alpha-Mips die Kronen aus (licht, grau) -> niedrigere Schwelle
									bm.alpha_scissor_threshold = 0.33
									# Eichenlaub: matter (KHR_materials_specular ~0.02 im Original), sonst glaenzen
									# die Blattkarten gegen den Abendhimmel grau-weiss; etwas Durchscheinen.
									bm.metallic_specular = 0.15
									bm.backlight_enabled = true
									bm.backlight = Color(0.12, 0.16, 0.05)
							bm.cull_mode = BaseMaterial3D.CULL_DISABLED
							if path == HEDGE:
								# Heckenblock: gebackene AO/Metallic-Karte macht die Schattenseite schwarz ->
								# ohne AO, matt, mit Durchscheinen (Gegenlicht am Abend)
								bm.ao_enabled = false
								bm.metallic = 0.0
								bm.metallic_texture = null
								# Optik 3: Textur ist gelbstichig (Mittel 52/72/23) -> im Abendlicht grell gelb.
								# Zum Buchsbaum-Blaugruen hin, ohne Glanzkarte (sonnenseitig kein Spiegeln).
								bm.roughness_texture = null
								bm.roughness = 0.85
								bm.metallic_specular = 0.3
								bm.backlight_enabled = true
								bm.backlight = Color(0.1, 0.17, 0.06)
								bm.albedo_color = Color(0.8, 0.9, 1.3)
						if mat != null and str(mat.resource_name).begins_with("Bark") and foot == Vector3.INF:
							var vs: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
							var lo := INF
							for v in vs:
								lo = minf(lo, (xf * v).y)
							var acc := Vector3.ZERO
							var cnt := 0
							for v in vs:
								var w := xf * v
								if w.y < lo + 0.4:
									acc += w
									cnt += 1
							if cnt > 0:
								foot = acc / cnt
				if not parts.is_empty():
					if foot == Vector3.INF:
						foot = Vector3(box.get_center().x, box.position.y, box.get_center().z)
					foot.y = box.position.y
					out = {"parts": parts, "aabb": box, "foot": foot}
			inst.free()
	_cache[key] = out
	return out

static func available() -> bool:
	return not _load(OAK, OAKS["medium_a"] + "_LOD0").is_empty()

static func _instance(parent: Node3D, d: Dictionary, xf: Transform3D, vis_end: float, nm: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = nm
	holder.transform = xf
	parent.add_child(holder)
	for part: Array in d["parts"]:
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		if vis_end > 0.0:
			mi.visibility_range_end = vis_end
			mi.visibility_range_end_margin = 10.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		holder.add_child(mi)
	return holder

## Eiche mit Stammfuss auf pos; scale_v skaliert die natuerliche Groesse.
static func oak(parent: Node3D, kind: String, pos: Vector3, yaw_deg: float, scale_v: float = 1.0, vis_end: float = 0.0) -> bool:
	var d := _load(OAK, str(OAKS.get(kind, OAKS["medium_a"])) + "_LOD0")
	if d.is_empty():
		return false
	var foot: Vector3 = d["foot"]
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)).scaled(Vector3.ONE * scale_v)
	_instance(parent, d, Transform3D(b, pos - b * foot), vis_end, "Oak")
	return true

## Waldsaum aus echten Eichen-Modellen (LOD0 + vom Importer erzeugte Mesh-LODs) als MultiMesh je
## Zelle/Art/Teil: Zellen erlauben Frustum-Culling und Mesh-LOD je Gebiet (LOD wird je MultiMesh-AABB
## gewaehlt, darum kleine Zellen). items = [[pos, yaw_deg, scale, kind, shadow(bool)], ...].
## Je Baum leichte Schraeglage und ungleichmaessige Skalierung, je Instanz ein Farbton (Laub-Varianz).
static func oak_grove(parent: Node3D, items: Array, cell: float = 22.0, vis_end: float = 0.0, seed_v: int = 1) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var groups: Dictionary = {}
	for it: Array in items:
		var kind := str(it[3])
		var d := _load(OAK, str(OAKS.get(kind, OAKS["medium_a"])) + "_LOD0")
		if d.is_empty():
			return false
		var p: Vector3 = it[0]
		var s: float = it[2]
		var b := Basis(Vector3.UP, deg_to_rad(float(it[1]))).scaled(Vector3(s * rng.randf_range(0.92, 1.08), s * rng.randf_range(0.94, 1.06), s * rng.randf_range(0.92, 1.08)))
		b = Basis(Vector3.RIGHT, rng.randf_range(-0.04, 0.04)) * Basis(Vector3.BACK, rng.randf_range(-0.04, 0.04)) * b
		var foot: Vector3 = d["foot"]
		var xf := Transform3D(b, p - b * foot + Vector3(0, -0.15, 0))
		# Laub: etwas gelber/dunkler/bunter je Baum (Eichen sind nie gleich gruen)
		var tone := rng.randf_range(-1.0, 1.0)
		var bright := rng.randf_range(0.74, 0.98)
		var col := Color(bright * (1.0 + 0.07 * tone), bright, bright * (1.0 - 0.1 * tone))
		var key := "%d_%d_%s_%d" % [floori(p.x / cell), floori(p.z / cell), kind, 1 if bool(it[4]) else 0]
		if not groups.has(key):
			groups[key] = {"d": d, "shadow": bool(it[4]), "kind": kind, "xs": [], "cols": []}
		groups[key]["xs"].append(xf)
		groups[key]["cols"].append(col)
	for key: String in groups:
		var g: Dictionary = groups[key]
		var d: Dictionary = g["d"]
		var xs: Array = g["xs"]
		var cols: Array = g["cols"]
		for part: Array in d["parts"]:
			var mesh: Mesh = part[0]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = xs.size()
			for i in xs.size():
				mm.set_instance_transform(i, (xs[i] as Transform3D) * (part[1] as Transform3D))
				mm.set_instance_color(i, cols[i])
			var mmi := MultiMeshInstance3D.new()
			mmi.name = "OakGrove_" + str(g["kind"])
			mmi.multimesh = mm
			var mat := mesh.surface_get_material(0)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				mmi.material_override = _tinted(mat as BaseMaterial3D)   # nur Laub, Rinde bleibt neutral
			if not bool(g["shadow"]):
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if vis_end > 0.0:
				mmi.visibility_range_end = vis_end
			parent.add_child(mmi)
	return true

## Materialkopie, die die MultiMesh-Instanzfarbe als Albedo-Faktor nimmt (gecacht).
static func _tinted(m: BaseMaterial3D) -> BaseMaterial3D:
	var key := "tint#" + str(m.get_instance_id())
	if not _cache.has(key):
		var t := m.duplicate() as BaseMaterial3D
		t.vertex_color_use_as_albedo = true
		_cache[key] = t
	return _cache[key]

## Ferne Baeume: Billboard-Kreuze (28 Dreiecke) als MultiMesh je Art. items = [[pos, yaw_deg, scale], ...]
static func oak_billboards(parent: Node3D, kind: String, items: Array, vis_begin: float = 0.0, vis_end: float = 900.0) -> bool:
	var d := _load(OAK, str(OAKS.get(kind, OAKS["medium_a"])) + "_Billboard")
	if d.is_empty() or items.is_empty():
		return false
	var foot: Vector3 = d["foot"]
	for part: Array in d["parts"]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part[0]
		mm.instance_count = items.size()
		for i in items.size():
			var it: Array = items[i]
			var b := Basis(Vector3.UP, deg_to_rad(float(it[1]))).scaled(Vector3.ONE * float(it[2]))
			mm.set_instance_transform(i, Transform3D(b, (it[0] as Vector3) - b * foot) * (part[1] as Transform3D))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "OakBillboards_" + kind
		mmi.multimesh = mm
		mmi.visibility_range_begin = vis_begin
		mmi.visibility_range_end = vis_end
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
	return true

## Hecke als Buchsbaum-Bloecke in der Box (Mitte c, Groesse s), laengs der laengeren Achse segmentiert.
static func hedge(parent: Node3D, c: Vector3, s: Vector3, vis_end: float = 160.0) -> bool:
	var d := _load(HEDGE, "TileExample Large")
	if d.is_empty():
		return false
	var box: AABB = d["aabb"]
	var along_x := s.x >= s.z
	var length := s.x if along_x else s.z
	var depth := s.z if along_x else s.x
	var n := maxi(1, roundi(length / 4.0))
	var seg := length / n
	var sc := Vector3(seg / box.size.x * 1.07, s.y / box.size.y * 1.04, depth / box.size.z * 1.12)
	var rot := Basis.IDENTITY if along_x else Basis(Vector3.UP, PI * 0.5)
	var b := rot * Basis.from_scale(sc)
	var ctr := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var ax := Vector3.RIGHT if along_x else Vector3.BACK
	var lo_y := c.y - s.y * 0.5
	for i in n:
		var p := Vector3(c.x, lo_y, c.z) + ax * (-length * 0.5 + seg * (i + 0.5))
		# jedes zweite Segment um 180 Grad gedreht: weniger sichtbare Wiederholung
		var bi := b if i % 2 == 0 else Basis(Vector3.UP, PI) * b
		_instance(parent, d, Transform3D(bi, p - bi * ctr), vis_end, "Hedge")
	return true
