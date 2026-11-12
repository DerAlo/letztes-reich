extends RefCounted
## Sammelt alle Ressourcen (Meshes, Materialien, Shader, Texturen, Animationen, Szenen ...), die ein Knoten-
## Teilbaum referenziert. main.gd haelt sie waehrend des Levels fest: Ohne Referenz wirft Godot sie nach dem
## Vorwaermen wieder aus dem Cache, und der erste echte Gegner laedt Rig/Texturen erneut von der Platte
## (river_crossing: 240-480 ms Ruckler beim Wellen-Spawn).

static func collect(root: Node, out: Dictionary) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		_scan(n, out)
		stack.append_array(n.get_children(true))

static func _scan(o: Object, out: Dictionary) -> void:
	for p in o.get_property_list():
		var t: int = p["type"]
		if t != TYPE_OBJECT and t != TYPE_ARRAY and t != TYPE_DICTIONARY:
			continue
		if int(p["usage"]) & (PROPERTY_USAGE_STORAGE | PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		_add(o.get(p["name"]), out)

static func _add(v: Variant, out: Dictionary) -> void:
	if v is Resource:
		var r := v as Resource
		if out.has(r) or r is Script:
			return
		out[r] = true
		_scan(r, out)
		if r is Mesh:
			for i in (r as Mesh).get_surface_count():
				_add((r as Mesh).surface_get_material(i), out)
	elif v is Array:
		for x in v:
			if x is Resource or x is Array or x is Dictionary:
				_add(x, out)
	elif v is Dictionary:
		for x in (v as Dictionary).values():
			if x is Resource or x is Array or x is Dictionary:
				_add(x, out)
