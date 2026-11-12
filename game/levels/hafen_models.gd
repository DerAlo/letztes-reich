extends RefCounted
## Mission "Kräne": Modell-Slots fuer echte Boots-/Schiffsmodelle (z. B. von Sketchfab).
## Liegt unter res://assets/models/hafen/<slot>.glb (oder .gltf/.tscn, auch im Unterordner <slot>/<slot>.gltf)
## eine Datei, wird sie statt des prozeduralen Platzhalters eingehaengt; sonst bleibt alles wie bisher.
## Kollision bleibt immer im Code (Boxen), das Modell ist reine Optik.
##
## Slots und Anforderungen:
##   zollboot          Spielerboot (Zoll-/Polizei-Schnellboot), Ziel-Laenge 9 m
##   garde_boat        Gegner-Schnellboot (RIB/Patrouillenboot, Bug frei fuer MG), 8 m
##   weber_boat        Webers Fluchtboot (helles Motorboot/Kajuetboot), 8 m
##   freighter_aurelia Frachter "Aurelia" (Stueckgut-/Feederschiff), 150 m
##   port_crane        Wippdrehkran (Kai), container (20-ft-Container fuer MultiMesh) – siehe hafen_world.gd
## Konvention: Meter, +Y oben, Bug zeigt nach -Z, Ursprung = Mitte der Wasserlinie (Y=0 auf Wasserlinie).
## Laenge und horizontale Mitte werden automatisch angeglichen (Skalierung auf Ziel-Laenge), die Hoehe nicht.
## Optional: <slot>.json neben dem Modell, Schluessel:
##   "yaw" Grad, "y" Versatz m, "length" m,
##   "draft" m  – Unterkante des Modells liegt draft Meter unter Y=0 (ersetzt die Rohhoehe des Modells),
##   "hide"     – Liste von Knotennamen, die entfernt werden (Bodenplatten, Fremdbewaffnung ...),
##   "materials" – {Knotenname: {"color": [r,g,b], "rough": f, "metal": f}} fuer Modelle ohne Texturen,
##   "rough_min" – Mindest-Rauheit fuer alle Materialien (gegen Plastik-Glanz bei Nacht/Regen),
##   "anim"     – Animationsname, der in Schleife laeuft,
##   "scale"    – feste Skalierung statt Ziel-Laenge, "center_node" – Knoten, dessen Mitte auf den Ursprung kommt,
##   "pingpong" – Animation hin und zurueck statt Schleife,
##   "widen"    – Faktor fuer die Breite (schmale Rumpfmodelle an die Kollisionsbox angleichen).

const DIR := "res://assets/models/hafen/"

static func path_for(slot: String) -> String:
	if Game.arg("no-hafen-models", false):
		return ""   # Vergleichsmessung/Fallback: prozedurale Platzhalter
	for base in [DIR + slot, DIR + slot + "/" + slot]:
		for ext in [".glb", ".gltf", ".tscn", ".scn"]:
			var p: String = base + ext
			if ResourceLoader.exists(p):
				return p
	return ""

## Instanziert das Modell (Skalierung/Ausrichtung aus der Konfiguration) ohne es einzuhaengen.
static func build(slot: String, length: float, extra_yaw_deg: float = 0.0) -> Node3D:
	var p := path_for(slot)
	if p == "":
		return null
	var ps := load(p) as PackedScene
	if ps == null:
		push_warning("[hafen] Modell-Slot %s: %s laesst sich nicht laden" % [slot, p])
		return null
	var n := ps.instantiate() as Node3D
	if n == null:
		return null
	var cfg := _cfg(slot)
	for nm in cfg.get("hide", []):
		var h := n.find_child(str(nm), true, false)
		if h != null:
			h.get_parent().remove_child(h)
			h.free()
	_apply_materials(n, cfg)
	var holder := Node3D.new()
	holder.name = "Model_" + slot
	holder.add_child(n)
	var ab := _aabb(n, Transform3D.IDENTITY)
	var want: float = float(cfg.get("length", length))
	var cur := maxf(ab.size.x, ab.size.z)
	var k := 1.0
	if cfg.has("scale"):
		k = float(cfg["scale"])
	elif want > 0.0 and cur > 0.01:
		k = want / cur
	var sc := Vector3.ONE * k
	if cfg.has("widen"):
		if ab.size.x < ab.size.z:
			sc.x *= float(cfg["widen"])
		else:
			sc.z *= float(cfg["widen"])
	n.scale = sc
	var cab := ab
	if cfg.has("center_node"):
		var cn := n.find_child(str(cfg["center_node"]), true, false)
		if cn != null:
			cab = _aabb(cn, _rel(n, cn.get_parent()))
	var c := cab.get_center() * sc
	var y: float = float(cfg.get("y", 0.0))
	if cfg.has("draft"):
		y += -ab.position.y * k - float(cfg["draft"])
	n.position = Vector3(-c.x, y, -c.z)
	holder.rotation_degrees.y = extra_yaw_deg + float(cfg.get("yaw", 0.0))
	holder.set_meta("model_scale", k)
	holder.set_meta("aabb", _aabb(holder, Transform3D.IDENTITY))
	if cfg.has("anim"):
		var ap := n.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap != null and ap.has_animation(str(cfg["anim"])):
			var an := ap.get_animation(str(cfg["anim"]))
			an.loop_mode = Animation.LOOP_PINGPONG if bool(cfg.get("pingpong", false)) else Animation.LOOP_LINEAR
			ap.play(str(cfg["anim"]))
			ap.seek(randf() * an.length, true)
			ap.speed_scale = randf_range(0.8, 1.1)
	return holder

## Haengt das Modell unter parent ein und liefert den Halter-Knoten, oder null (dann prozedural bauen).
static func attach(parent: Node3D, slot: String, length: float, extra_yaw_deg: float = 0.0) -> Node3D:
	var holder := build(slot, length, extra_yaw_deg)
	if holder == null:
		return null
	parent.add_child(holder)
	print("[hafen] Modell-Slot %s: %s (Skalierung %.3f)" % [slot, path_for(slot), float(holder.get_meta("model_scale", 1.0))])
	return holder

static func find(parent: Node3D, slot: String) -> Node3D:
	return parent.get_node_or_null("Model_" + slot) as Node3D

static func _cfg(slot: String) -> Dictionary:
	for jp in [DIR + slot + ".json", DIR + slot + "/" + slot + ".json"]:
		if FileAccess.file_exists(jp):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
			return v if v is Dictionary else {}
	return {}

## Transform von root bis einschliesslich node (node im Teilbaum von root).
static func _rel(root: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c := node
	while c != null and c != root:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t

static func _apply_materials(n: Node, cfg: Dictionary) -> void:
	var mats: Dictionary = cfg.get("materials", {})
	for nm in mats:
		var mi := n.find_child(str(nm), true, false) as MeshInstance3D
		if mi == null:
			continue
		var d: Dictionary = mats[nm]
		var m := StandardMaterial3D.new()
		var col: Array = d.get("color", [0.5, 0.5, 0.5])
		m.albedo_color = Color(float(col[0]), float(col[1]), float(col[2]))
		m.roughness = float(d.get("rough", 0.7))
		m.metallic = float(d.get("metal", 0.0))
		mi.material_override = m
	if cfg.has("rough_min") or cfg.has("tint") or cfg.has("metal_scale") or cfg.has("normal_scale"):
		_tune(n, cfg, {})

## Material-Feinschliff per Slot-JSON (Duplikate, Originale bleiben): rough_min (Mindest-Rauheit),
## tint {Materialname: [r,g,b]} (Albedo-Multiplikator, z. B. dunklerer Militaeranstrich), metal_scale,
## normal_scale (Normal-Map staerker -> Plattenstoesse/Beulen lesbar statt flach).
static func _tune(n: Node, cfg: Dictionary, done: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.material_override == null:
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null:
					continue
				if not done.has(m):
					var m2 := m.duplicate() as BaseMaterial3D
					m2.roughness = maxf(m2.roughness, float(cfg.get("rough_min", 0.0)))
					m2.metallic *= float(cfg.get("metal_scale", 1.0))
					var tints: Dictionary = cfg.get("tint", {})
					if tints.has(m.resource_name):
						var t: Array = tints[m.resource_name]
						m2.albedo_color *= Color(float(t[0]), float(t[1]), float(t[2]))
					if cfg.has("normal_scale") and m2.normal_enabled:
						m2.normal_scale = float(cfg["normal_scale"])
					done[m] = m2
				mi.set_surface_override_material(s, done[m])
	for ch in n.get_children():
		_tune(ch, cfg, done)

static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var have := false
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is VisualInstance3D and (n as Node3D).visible:
		out = t * (n as VisualInstance3D).get_aabb()
		have = true
	for ch in n.get_children():
		var a := _aabb(ch, t)
		if a.size == Vector3.ZERO:
			continue
		out = out.merge(a) if have else a
		have = true
	return out

## Echte Soldaten-Figur (Gegner-Visual-Pipeline: MH-Rig, Fraktionsstoffe, Animation, IK) als reine Puppe auf
## Booten/Deck: ohne KI, ohne Kollision/Treffer (die Trefferzone bleibt beim Boot), nicht in Gruppen
## enemy/damageable/friendly (Bots zielen/vermeiden sie nicht). opts: etype, unarmed, aim (bool: Anschlag
## halten, aim_point setzt der Aufrufer laufend), frozen. Fuesse = Ursprung, Blick -Z.
static func puppet(parent: Node3D, faction: String, cols: Array, pos: Vector3, yaw_deg: float, opts: Dictionary = {}) -> CharacterBody3D:
	var a: CharacterBody3D = preload("res://game/levels/hafen_actor.gd").new()
	a.set("role", "friendly" if faction == "resistance" else "enemy")
	a.set("enemy_type", str(opts.get("etype", "rifleman")))
	a.set_meta("faction", faction)
	a.set("color_primary", cols[0])
	a.set("color_secondary", cols[1])
	a.set("color_armband", cols[2])
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	a.set("invulnerable", true)
	a.set("unarmed", bool(opts.get("unarmed", false)))
	a.set("gravity", 0.0)
	a.set("turn_speed", 0.0)
	a.set("frozen", not bool(opts.get("aim", false)))
	a.set("aiming", bool(opts.get("aim", false)))
	a.set("aim_local", opts.get("aim_local", Vector3(0, 1.3, -30.0)))
	a.name = str(opts.get("name", "Puppe"))
	parent.add_child(a)
	a.position = pos
	a.rotation.y = deg_to_rad(yaw_deg)
	for g in ["enemy", "damageable", "friendly"]:
		a.remove_from_group(g)
	a.collision_layer = 0
	a.collision_mask = 0
	for c in a.find_children("*", "CollisionObject3D", true, false):
		(c as CollisionObject3D).collision_layer = 0
		(c as CollisionObject3D).collision_mask = 0
	return a
