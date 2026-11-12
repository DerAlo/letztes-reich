extends RefCounted
## Hubschrauber-Modellslot: laedt ein externes glTF/GLB-Modell und liefert dieselben Animations-Schluessel
## wie heli_model.gd ("blades" = Hauptrotor, "tail_rotor" = Heckrotor). Fehlt die Datei oder schlaegt das
## Laden fehl, wird das prozedurale heli_model (ueber ModelCache) gebaut – das Level laeuft immer.
##
## Einbau:
##   var parts := HeliGltf.build(pivot, "res://assets/vehicles/heli/heli.glb", {"faction": "de"})
##   # _process: (parts["blades"] as Node3D).rotate_y(-delta * 11.0); (parts["tail_rotor"] as Node3D).rotate_x(delta * 23.0)
##
## ANFORDERUNGEN an das Modell (fuer den Asset-Austausch):
##  - Format: .glb (bevorzugt) oder .gltf mit externen Texturen, PBR-Metallic-Roughness. Liegt es unter
##    res://, importiert Godot es (Import-Einstellungen: "Generate LODs" an). Absolute Pfade ausserhalb des
##    Projekts werden zur Laufzeit per GLTFDocument geladen (langsamer, keine LODs).
##  - Einheit Meter, +Y oben, Nase zeigt nach -Z (Godot-Vorwaerts). Abweichungen per opts korrigieren:
##    "scale" (float), "yaw_deg" (float, Drehung um Y), "offset" (Vector3).
##  - Ursprung: Mitte des Rumpfes auf Kufen-/Fahrwerkshoehe (Bodenkontakt bei y = 0).
##  - Hauptrotor: EIN eigener Knoten, dessen Ursprung auf der Rotorachse liegt und dessen lokale Y-Achse die
##    Drehachse ist. Standard-Namen (Gross/Klein egal, erster Treffer, Teilstring): "main_rotor", "mainrotor",
##    "rotor_main", "rotor". Eigene Namen per opts["rotor_names"] (Array[String]).
##  - Heckrotor: eigener Knoten, Ursprung auf der Achse, Drehachse = lokale X-Achse (Querachse). Namen:
##    "tail_rotor", "tailrotor", "rotor_tail", "heckrotor". Eigene per opts["tail_names"]. Dreht er um eine
##    andere Achse: opts["tail_axis"] = Vector3(...) – das Level liest parts["tail_axis"].
##  - Rotorblaetter sollten Kinder des Rotorknotens sein (dann drehen sie mit). Kein eingebautes Rotor-Blur.
##  - Polygonbudget: <= 60k Dreiecke, Texturen <= 2k (der Heli steht im Intro nah an der Kamera).
##  - Lizenz: CC0/CC-BY o. ae., Eintrag in assets/CREDITS_ASSETS.md.
##
## Rueckgabe: { "root": Node3D, "blades": Node3D|null, "tail_rotor": Node3D|null, "tail_axis": Vector3,
##              "source": "gltf"|"procedural", ...weitere Schluessel des prozeduralen Modells }

const HeliModel := preload("res://game/vehicles/models/heli_model.gd")
const ModelCache := preload("res://game/vehicles/models/model_cache.gd")
const HeliReal := preload("res://game/vehicles/models/heli_real.gd")
const Mi8Model := preload("res://game/vehicles/models/mi8_model.gd")
const Mi28Model := preload("res://game/vehicles/models/mi28_model.gd")

const ROTOR_NAMES := ["main_rotor", "mainrotor", "rotor_main", "hauptrotor", "rotor"]
const TAIL_NAMES := ["tail_rotor", "tailrotor", "rotor_tail", "heckrotor", "tail"]

static func build(parent: Node3D, path: String, opts: Dictionary = {}) -> Dictionary:
	var faction: String = str(opts.get("faction", "de"))
	# Vorgebackene Echtmodelle (heli_real.gd): Pfad der .scn oder "mi8"/"mi28n" -> volles Teile-Dictionary
	# inkl. Rotor-Blur, Lichter, Kanone; ModelCache-Klon, prozeduraler Fallback eingebaut.
	var real := ""
	if path == HeliReal.MI8_SCENE or path == "mi8":
		real = "mi8"
	elif path == HeliReal.MI28_SCENE or path == "mi28n":
		real = "mi28n"
	if real != "":
		var holder := Node3D.new()
		holder.name = "HeliReal"
		parent.add_child(holder)
		var rp := ModelCache.build(Mi8Model if real == "mi8" else Mi28Model, holder, faction)
		if not rp.has("root"):
			rp["root"] = holder
		return rp
	var root: Node3D = null
	if path != "":
		root = _load(path)
		if root == null:
			push_warning("HeliGltf: Modell '%s' nicht ladbar – prozeduraler Fallback" % path)
	if root == null:
		var holder := Node3D.new()
		holder.name = "HeliProcedural"
		parent.add_child(holder)
		var out: Dictionary = ModelCache.build(HeliModel, holder, faction)
		out["root"] = holder
		out["tail_axis"] = Vector3.RIGHT
		out["source"] = "procedural"
		return out
	root.name = "HeliModel"
	root.scale = Vector3.ONE * float(opts.get("scale", 1.0))
	root.rotation.y = deg_to_rad(float(opts.get("yaw_deg", 0.0)))
	root.position = opts.get("offset", Vector3.ZERO)
	parent.add_child(root)
	var rn: Array = opts.get("rotor_names", ROTOR_NAMES)
	var tn: Array = opts.get("tail_names", TAIL_NAMES)
	var tail := _find(root, tn, null)
	var rotor := _find(root, rn, tail)
	if rotor == null:
		push_warning("HeliGltf: kein Hauptrotor-Knoten (%s) in '%s'" % [", ".join(rn), path])
	if tail == null:
		push_warning("HeliGltf: kein Heckrotor-Knoten (%s) in '%s'" % [", ".join(tn), path])
	for gi in root.find_children("*", "GeometryInstance3D", true, false):
		(gi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return {"root": root, "blades": rotor, "tail_rotor": tail, "tail_axis": opts.get("tail_axis", Vector3.RIGHT), "source": "gltf"}

static func _load(path: String) -> Node3D:
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		var ps := load(path) as PackedScene
		if ps == null:
			return null
		return ps.instantiate() as Node3D
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		return null
	return doc.generate_scene(st) as Node3D

## Erster Knoten (Breitensuche), dessen Name einen der Kandidaten enthaelt; Kandidaten in Prioritaetsreihenfolge.
## exclude (und seine Kinder) werden uebersprungen (z. B. damit "rotor" nicht den Heckrotor trifft).
static func _find(root: Node, names: Array, exclude: Node) -> Node3D:
	for cand in names:
		var c := str(cand).to_lower()
		var queue: Array[Node] = [root]
		while not queue.is_empty():
			var n: Node = queue.pop_front()
			if exclude != null and (n == exclude or exclude.is_ancestor_of(n)):
				continue
			if n != root and n is Node3D and String(n.name).to_lower().replace(" ", "_").contains(c):
				# "tail" soll nicht den Rumpf-"tail_boom" treffen
				if not String(n.name).to_lower().contains("boom"):
					return n as Node3D
			queue.append_array(n.get_children())
	return null
