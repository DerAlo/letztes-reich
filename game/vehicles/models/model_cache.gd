extends RefCounted
## Klon-Cache fuer prozedurale Fahrzeugmodelle (heli_model / tank_model bauen ihre Meshes in GDScript:
## 100-280 ms je Instanz -> Ruckler beim Auftauchen von Hubschrauber/Panzer). Das erste build() je
## Modell+Fraktion baut wie bisher und legt eine Vorlage ab; jedes weitere dupliziert nur die Knoten
## (Meshes/Materialien geteilt). Materialien, die build() im Teile-Dictionary zurueckgibt (zur Laufzeit
## animiert: Rotor-Unschaerfe, Ketten, Laufraeder), bekommt jede Instanz als eigene Kopie.

static var _templates := {}   # "script|faction" -> [Node3D Vorlage, Dictionary kodierte Teile]

static func build(model: Script, parent: Node3D, faction: String) -> Dictionary:
	var key := "%s|%s" % [model.resource_path, faction]
	if not _templates.has(key):
		var n0 := parent.get_child_count()
		var out: Dictionary = model.call("build", parent, faction)
		# automatische Namen (@MeshInstance3D@57) sind nach dem Duplizieren andere -> feste Namen fuer die Pfade
		var stack: Array[Node] = []
		for i in range(n0, parent.get_child_count()):
			stack.append(parent.get_child(i))
		var u := 0
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if String(n.name).begins_with("@"):
				n.name = "mc%d" % u
				u += 1
		var tpl := Node3D.new()
		for i in range(n0, parent.get_child_count()):
			tpl.add_child(parent.get_child(i).duplicate())
		var enc := {}
		for k in out:
			enc[k] = _encode(out[k], parent)
		if _templates.is_empty():
			var ml := Engine.get_main_loop() as SceneTree
			if ml != null:
				ml.root.tree_exiting.connect(clear, CONNECT_ONE_SHOT)
		_templates[key] = [tpl, enc]
		return out
	var tpl: Node3D = _templates[key][0]
	var enc: Dictionary = _templates[key][1]
	var n0 := parent.get_child_count()
	for c in tpl.get_children():
		parent.add_child(c.duplicate())
	var dup := {}
	for k in enc:
		_collect_res(enc[k], dup)
	if not dup.is_empty():
		var stack: Array[Node] = []
		for i in range(n0, parent.get_child_count()):
			stack.append(parent.get_child(i))
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is GeometryInstance3D and dup.has((n as GeometryInstance3D).material_override):
				(n as GeometryInstance3D).material_override = dup[(n as GeometryInstance3D).material_override]
	var out := {}
	for k in enc:
		out[k] = _decode(enc[k], parent, dup)
	return out

## Vorlagen freigeben (Programmende).
static func clear() -> void:
	for e in _templates.values():
		(e[0] as Node).free()
	_templates.clear()

static func _encode(v: Variant, parent: Node) -> Variant:
	if v is Node:
		return parent.get_path_to(v)
	if v is Array:
		var items: Array = []
		for x in v:
			items.append(_encode(x, parent))
		var arr := v as Array
		return {"__arr": items, "t": arr.get_typed_builtin(), "c": arr.get_typed_class_name(), "s": arr.get_typed_script()}
	return v

static func _collect_res(v: Variant, dup: Dictionary) -> void:
	if v is Resource and not dup.has(v):
		dup[v] = (v as Resource).duplicate()
	elif v is Dictionary and (v as Dictionary).has("__arr"):
		for x in v["__arr"]:
			_collect_res(x, dup)

static func _decode(v: Variant, parent: Node, dup: Dictionary) -> Variant:
	if v is NodePath:
		return parent.get_node(v)
	if v is Resource:
		return dup.get(v, v)
	if v is Dictionary and (v as Dictionary).has("__arr"):
		var a := Array([], int(v["t"]), StringName(v["c"]), v["s"])
		for x in v["__arr"]:
			a.append(_decode(x, parent, dup))
		return a
	return v
