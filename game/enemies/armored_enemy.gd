class_name ArmoredEnemy
extends Enemy
## Gepanzerter Soldat: Plattentraeger mit Stahlplatten (vorn/hinten), Schulter- und Oberschenkelplatten,
## geschlossener Helm mit Panzerglas-Visier. Treffer werden gegen die SICHTBAREN Panzerteile geprueft
## (Strahl im Skelett-Ruheraum gegen die Platten-Meshes), danach gegen Koerperzonen (Glieder, Seiten).
## Platten haben Haltbarkeit: abprallende Treffer -> Funken + "Ping" + wenig Schaden; ist eine Platte
## durch, faellt sie sichtbar ab und die Stelle nimmt vollen Schaden. Explosionen ignorieren die Platten.
## Alles andere (KI, Stimme, Tod, Schleich-Hooks) kommt unveraendert aus enemy.gd.

const AK = preload("res://game/enemies/armor_kit.gd")
const AHUD = preload("res://game/enemies/armor_hud.gd")
const PLATE_SHADER = preload("res://game/enemies/armor_plate.gdshader")
const VISOR_SHADER = preload("res://game/enemies/armor_visor.gdshader")
const SGEAR = preload("res://game/enemies/soldier_gear.gd")

@export_group("Armor")
@export var armor_kind: String = "armored"
@export var plate_integrity: float = 90.0     ## Brust-/Rueckenplatte: Schaden bis zum Abfallen
@export var plate_pass: float = 0.3           ## Anteil, der bei intakter Platte durchkommt
@export var limb_plate_integrity: float = 45.0
@export var limb_plate_pass: float = 0.4
@export var side_pass: float = 0.6            ## Seiten (Kummerbund, weich): immer
@export var pouch_pass: float = 0.75          ## Magazintaschen unter der Brustplatte
@export var visor_integrity: float = 30.0
@export var visor_pass: float = 0.2
@export var helmet_pass: float = 0.5          ## Helm (Seite/Hinten/Kinn): unzerstoerbar, kein Kopf-Multiplikator
@export var limb_pass: float = 1.0
@export var explosion_mult: float = 1.0
@export var zone_pad: float = 1.0

static var _tm_cache: Dictionary = {}
static var _plate_mats: Dictionary = {}

## id -> {id, bone, bi, frame, mis, plate_mi, mat, tm, hp, max, broken, hits, hit_i, visor}
var _pieces: Dictionary = {}
var _zones: Array = []
var _shot_dir: Vector3 = Vector3.ZERO
var _shot_frame: int = -1
var _deflect_frame: int = -1
var _noblood_frame: int = -1
var last_zone: String = ""
var last_piece: String = ""
var last_dealt: float = 0.0
var stat_deflects: int = 0
var _helmet_c: Vector3 = AK.A_HC
var _helmet_r: float = 0.165
var _fix: Dictionary = {}   # Knochenindex -> Ruheraum(Kit) -> Ruheraum(Rig), siehe AK.op_fix

# ---------------------------------------------------------------- Aufbau

func _build_body() -> void:
	super._build_body()
	if _soldier == null:
		return
	_strip_default_gear()
	_build_armor()
	if armor_kind == "juggernaut":
		_dress_juggernaut()
	_build_zones()
	_fit_head_hitbox()

## Standard-Weste/-Helm-Kit (soldier_gear) entfernen; Hueft-Kit (Gurt, Taschen) bleibt.
func _strip_default_gear() -> void:
	var sk := _soldier.skeleton
	for n: Node in sk.find_children("Kit_*", "Node3D", true, false):
		if n.name == &"Kit_chest" or n.name == &"Kit_head":
			for c in n.get_children():
				if c is GeometryInstance3D:
					_soldier._meshes.erase(c)
			n.queue_free()

func _plate_material() -> ShaderMaterial:
	var key := armor_kind + "|" + faction
	if not _plate_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = PLATE_SHADER
		var reich := faction == "reich"
		m.set_shader_parameter("steel_col", Color(0.5, 0.5, 0.52) if reich else Color(0.47, 0.46, 0.43))
		m.set_shader_parameter("dirt_col", Color(0.12, 0.11, 0.1) if reich else Color(0.2, 0.17, 0.12))
		m.set_shader_parameter("chip_amount", 0.3 if reich else 0.45)
		m.set_shader_parameter("scratch_amount", 0.5)
		m.set_shader_parameter("dirt_amount", 0.35 if reich else 0.55)
		m.set_shader_parameter("paint_rough", 0.5 if reich else 0.7)
		m.set_shader_parameter("paint_metal", 0.3 if reich else 0.08)
		m.set_shader_parameter("noise_scale", 1.0)
		_plate_mats[key] = m
	var d := (_plate_mats[key] as ShaderMaterial).duplicate() as ShaderMaterial
	var h := PackedVector4Array()
	h.resize(8)
	d.set_shader_parameter("hits", h)
	return d

func _visor_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = VISOR_SHADER
	if faction == "reich":
		m.set_shader_parameter("tint", Color(0.04, 0.035, 0.03))
		m.set_shader_parameter("rim_tint", Color(0.55, 0.38, 0.15))
	else:
		m.set_shader_parameter("tint", Color(0.03, 0.045, 0.045))
		m.set_shader_parameter("rim_tint", Color(0.25, 0.34, 0.3))
	m.set_shader_parameter("crack_scale", 1.0 if armor_kind != "juggernaut" else 1.3)
	return m

static func _trimesh(m: Mesh) -> TriangleMesh:
	if not _tm_cache.has(m):
		_tm_cache[m] = m.generate_triangle_mesh()
	return _tm_cache[m]

func _piece_integrity(id: String) -> float:
	if id == "plate_front" or id == "plate_back":
		return plate_integrity
	if id.begins_with("shoulder_") or id.begins_with("thigh_"):
		return limb_plate_integrity
	if id == "visor":
		return visor_integrity
	return INF

func _build_armor() -> void:
	var sk := _soldier.skeleton
	var soft_mat := SGEAR.gear_mat(faction)
	var bas: Dictionary = {}
	for pc: Dictionary in AK.pieces(armor_kind, faction, sk):
		var bone: String = pc["bone"]
		var bi := sk.find_bone(bone)
		if bi < 0:
			continue
		if not bas.has(bone):
			var ba := BoneAttachment3D.new()
			ba.name = "BA_Armor_" + bone.replace(".", "_")
			ba.bone_name = bone
			sk.add_child(ba)
			bas[bone] = ba
		var frame := Node3D.new()
		frame.name = "Armor_" + str(pc["id"])
		frame.transform = sk.get_bone_global_rest(bi).affine_inverse() * _rig_fix(bi)
		(bas[bone] as Node3D).add_child(frame)
		var hits0 := PackedVector4Array()
		hits0.resize(8)
		var rec := {
			"id": pc["id"], "bone": bone, "bi": bi, "frame": frame, "mis": [], "plate_mi": null, "mat": null,
			"tm": null, "hp": _piece_integrity(pc["id"]), "max": _piece_integrity(pc["id"]), "broken": false,
			"hits": hits0, "hit_i": 0, "visor": false,
		}
		var meshes: Dictionary = pc["meshes"]
		for key: String in meshes:
			var mi := MeshInstance3D.new()
			mi.name = key
			mi.mesh = meshes[key]
			match key:
				"soft":
					mi.material_override = soft_mat
				"plate":
					var pm := _plate_material()
					mi.material_override = pm
					rec["mat"] = pm
					rec["plate_mi"] = mi
					rec["tm"] = _trimesh(mi.mesh)
				"visor":
					var vm := _visor_material()
					mi.material_override = vm
					rec["mat"] = vm
					rec["plate_mi"] = mi
					rec["tm"] = _trimesh(mi.mesh)
					rec["visor"] = true
			frame.add_child(mi)
			(rec["mis"] as Array).append(mi)
			_soldier._meshes.append(mi)
		_pieces[pc["id"]] = rec

# ---------------------------------------------------------------- Juggernaut: echte Ausruestung
## Altyn-Helm (Kenza9) + Gasmaske (TwilightFox) + Plattentraeger (Karnaval), Sketchfab, siehe CREDITS_ASSETS.md.
## Die Primitiv-Teile bleiben fuer Treffertest/Abwurf (unsichtbar, layers = 0); die Modelle haengen als
## Kinder daran und folgen so Abwurf und Ausblenden. Fehlt ein GLB, bleibt das Primitiv-Teil sichtbar.
const GEAR_ALTYN := "res://assets/models/gear/altyn/altyn.glb"
const GEAR_MASK := "res://assets/models/gear/gasmask/gasmask.glb"
const GEAR_CARRIER := "res://assets/models/gear/plate_carrier/plate_carrier.glb"
const J_HELM_XF := Transform3D(Basis(Vector3(1.2, 0, 0), Vector3(0, 1.2, 0), Vector3(0, 0, 1.2)), Vector3(0.004, 1.69, 0.08))
const J_MASK_XF := Transform3D(Basis(Vector3(1.1, 0, 0), Vector3(0, 1.1, 0), Vector3(0, 0, 1.1)), Vector3(0.004, 1.66, 0.1))
const J_CARRIER_XF := Transform3D(Basis(Vector3(1.75, 0, 0), Vector3(0, 1.35, 0), Vector3(0, 0, 1.65)), Vector3(0.004, 1.27, 0.08))
static var _gear_cache: Dictionary = {}

## [[mesh, xf (relativ zur Szenenwurzel), name], ...] eines Ausruestungs-GLB; [] wenn es fehlt.
static func _gear_parts(path: String) -> Array:
	if _gear_cache.has(path):
		return _gear_cache[path]
	var out: Array = []
	var ps := GunModels._scene(path)
	if ps != null:
		var tmp := ps.instantiate()
		for mi: Node in tmp.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != tmp:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			out.append([(mi as MeshInstance3D).mesh, xf, str(mi.name)])
		tmp.free()
	_gear_cache[path] = out
	return out

func _gear_mi(parent: MeshInstance3D, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.transform = xf
	parent.add_child(m)
	_soldier._meshes.append(m)
	return m

func _dress_juggernaut() -> void:
	var altyn := _gear_parts(GEAR_ALTYN)
	if not altyn.is_empty() and _pieces.has("helmet") and _pieces.has("visor"):
		var hmi: MeshInstance3D = _pieces["helmet"]["plate_mi"]
		var vrec: Dictionary = _pieces["visor"]
		var vmi: MeshInstance3D = vrec["plate_mi"]
		if hmi != null and vmi != null:
			for part: Array in altyn:
				var xf: Transform3D = J_HELM_XF * (part[1] as Transform3D)
				if str(part[2]) == "zabralo":
					# Visier: Visier-Shader (Risse in dessen Objektraum -> vis_inv in _damage_piece)
					var vm := _gear_mi(vmi, part[0], xf)
					vm.material_override = vrec["mat"]
					vrec["vis_inv"] = xf.affine_inverse()
					vrec["vis_mi"] = vm
				else:
					_gear_mi(hmi, part[0], xf)
			for part: Array in _gear_parts(GEAR_MASK):
				_gear_mi(hmi, part[0], J_MASK_XF * (part[1] as Transform3D))
			_set_layers_safe(hmi, 0)
			_set_layers_safe(vmi, 0)
	var carrier := _gear_parts(GEAR_CARRIER)
	if not carrier.is_empty() and _pieces.has("chest_plate"):
		var cmi: MeshInstance3D = _pieces["chest_plate"]["plate_mi"]
		if cmi != null:
			for part: Array in carrier:
				_gear_mi(cmi, part[0], J_CARRIER_XF * (part[1] as Transform3D))
			_set_layers_safe(cmi, 0)

## Render-Layer einer Geometrie im Baum aendern, ohne Licht-Paarungen zu verwaisen.
## Godot 4.7 (Forward+) loest beim Layerwechsel die Licht-Paare NICHT auf; _instance_unpair prueft
## spaeter cull_mask & NEUE Layer und ueberspringt das Aufloesen, wenn die Maske nicht mehr passt
## (z. B. layers = 0). Das Licht behaelt dann einen Zeiger auf die Geometrie und umgekehrt ->
## "BUG, indexing did not unpair geometries from light" und Absturz (signal 11), sobald eines davon
## freigegeben wird. Kurz aus dem Baum nehmen loest alle Paare mit der ALTEN Maske sauber auf.
static func _set_layers_safe(gi: GeometryInstance3D, mask: int) -> void:
	if gi == null or gi.layers == mask:
		return
	var p := gi.get_parent()
	if p == null or not gi.is_inside_tree():
		gi.layers = mask
		return
	var idx := gi.get_index()
	p.remove_child(gi)
	gi.layers = mask
	p.add_child(gi)
	p.move_child(gi, idx)

## Koerperzonen fuer Treffer, die keine Platte trafen (Ruheraum, je Knochen).
func _build_zones() -> void:
	var sk := _soldier.skeleton
	var p := zone_pad
	_zones.clear()
	_zones.append({"id": "torso", "bone": "Chest", "type": "box", "c": Vector3(0.004, 1.26, 0.085), "h": Vector3(0.2 * p, 0.215, 0.165 * p)})
	_zones.append({"id": "pelvis", "bone": "Hips", "type": "box", "c": Vector3(0.008, 0.94, 0.07), "h": Vector3(0.18 * p, 0.12, 0.13 * p)})
	for s: String in ["L", "R"]:
		_zones.append({"id": "uarm_" + s, "bone": "UpperArm." + s, "type": "cap", "a": AK.bp(sk, "UpperArm." + s), "b": AK.bp(sk, "LowerArm." + s), "r": 0.07 * p})
		_zones.append({"id": "larm_" + s, "bone": "LowerArm." + s, "type": "cap", "a": AK.bp(sk, "LowerArm." + s), "b": AK.bp(sk, "Wrist." + s), "r": 0.055 * p})
		_zones.append({"id": "thigh_" + s, "bone": "UpperLeg." + s, "type": "cap", "a": AK.bp(sk, "UpperLeg." + s), "b": AK.bp(sk, "LowerLeg." + s), "r": 0.095 * p})
		_zones.append({"id": "shin_" + s, "bone": "LowerLeg." + s, "type": "cap", "a": AK.bp(sk, "LowerLeg." + s), "b": AK.bp(sk, "Foot." + s), "r": 0.07 * p})
	for z: Dictionary in _zones:
		z["bi"] = sk.find_bone(z["bone"])

## Kopf-Hitbox auf den Helm legen (Mittelpunkt + Radius des Helms statt des nackten Kopfes).
func _fit_head_hitbox() -> void:
	if _head_hitbox == null or _soldier.head_attach == null:
		return
	var sk := _soldier.skeleton
	var hb := sk.find_bone("Head")
	var hf := _rig_fix(hb)
	_head_hitbox.position = sk.get_bone_global_rest(hb).affine_inverse() * (hf * _helmet_c)
	for c in _head_hitbox.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is SphereShape3D:
			((c as CollisionShape3D).shape as SphereShape3D).radius = _helmet_r * (hf.basis.get_scale().x + hf.basis.get_scale().z) * 0.5   # Ruheraum, skaliert mit dem Rig

# ---------------------------------------------------------------- Treffer-Geometrie

## Optional von der Waffe gesetzt (gleicher Physik-Frame): exakte Schussrichtung.
func set_shot_dir(dir: Vector3) -> void:
	_shot_dir = dir.normalized()
	_shot_frame = Engine.get_physics_frames()

## true, wenn der letzte Treffer in diesem Frame an der Panzerung abgeprallt ist.
func armor_deflected() -> bool:
	return _deflect_frame == Engine.get_physics_frames()

## true, wenn der letzte Treffer in diesem Frame kein Blut erzeugt (Platte oder Anzugpolster).
func armor_blocks_blood() -> bool:
	return _noblood_frame == Engine.get_physics_frames()

func _shot_ray(source: Node, hit_position: Vector3, hit_normal: Vector3) -> Array:
	var d := Vector3.ZERO
	if _shot_frame == Engine.get_physics_frames() and _shot_dir != Vector3.ZERO:
		d = _shot_dir
	elif source is Node3D and source != self:
		var from := (source as Node3D).global_position + Vector3.UP * 1.5
		var cam: Variant = source.get("camera")
		if cam is Node3D:
			from = (cam as Node3D).global_position
		d = hit_position - from
	if d.length() < 0.01:
		d = -hit_normal
	if d.length() < 0.01:
		d = (global_position + Vector3.UP - hit_position)
	d = d.normalized()
	return [hit_position - d * 0.9, d]

func _to_rest(bi: int) -> Transform3D:
	var sk := _soldier.skeleton
	return _rig_fix(bi).affine_inverse() * sk.get_bone_global_rest(bi) * sk.get_bone_global_pose(bi).affine_inverse() * sk.global_transform.affine_inverse()

## Kit-Ruheraum -> Rig-Ruheraum je Knochen (Operator-Rig: AK.op_fix; SWAT: Identitaet)
func _rig_fix(bi: int) -> Transform3D:
	if not _fix.has(bi):
		_fix[bi] = AK.op_fix(_soldier.skeleton.get_bone_name(bi)) if _soldier.kind == "op" else Transform3D.IDENTITY
	return _fix[bi]

## Findet das getroffene Teil. Rueckgabe {piece, zone, p (Ruheraum), t, u (0..1 entlang Glied)}.
func _locate(o: Vector3, d: Vector3, headshot: bool) -> Dictionary:
	var best := {"piece": "", "zone": "", "p": Vector3.ZERO, "t": INF, "u": 0.0}
	var xf_cache: Dictionary = {}
	var head_bi := _soldier.skeleton.find_bone("Head")
	for id: String in _pieces:
		var rec: Dictionary = _pieces[id]
		if rec["tm"] == null:
			continue
		var bi: int = rec["bi"]
		if headshot != (bi == head_bi):
			continue
		if rec["broken"] and not rec["visor"]:
			continue
		if not xf_cache.has(bi):
			xf_cache[bi] = _to_rest(bi)
		var m: Transform3D = xf_cache[bi]
		var ro := m * o
		var rd := m.basis * d
		var sc := rd.length()
		var r: Dictionary = (rec["tm"] as TriangleMesh).intersect_ray(ro, rd / sc)
		if r.is_empty():
			continue
		var t := ((r["position"] as Vector3) - ro).length() / sc
		if t < float(best["t"]):
			best = {"piece": ("face" if rec["broken"] else id), "zone": "", "p": r["position"], "t": t, "u": 0.0}
	if headshot:
		if best["piece"] == "":
			best["piece"] = "helmet"
		return best
	var zbest := {"zone": "", "t": INF, "p": Vector3.ZERO, "u": 0.0}
	var near_z := ""
	var near_d := INF
	for z: Dictionary in _zones:
		var bi: int = z["bi"]
		if bi < 0:
			continue
		if not xf_cache.has(bi):
			xf_cache[bi] = _to_rest(bi)
		var m: Transform3D = xf_cache[bi]
		var ro := m * o
		var rd := m.basis * d
		var sc := rd.length()
		rd /= sc
		var t := -1.0
		var u := 0.0
		var center: Vector3
		if z["type"] == "box":
			center = z["c"]
			t = _ray_box(ro - center, rd, z["h"])
		else:
			var a: Vector3 = z["a"]
			var b: Vector3 = z["b"]
			center = (a + b) * 0.5
			t = _ray_capsule(ro, rd, a, b, z["r"])
			if t >= 0.0:
				var hp := ro + rd * t
				u = clampf((hp - a).dot(b - a) / maxf((b - a).length_squared(), 1e-6), 0.0, 1.0)
		var dl := (center - ro).cross(rd).length()
		if dl < near_d:
			near_d = dl
			near_z = z["id"]
		if t >= 0.0 and t / sc < float(zbest["t"]):
			zbest = {"zone": z["id"], "t": t / sc, "p": ro + rd * t, "u": u}
	if best["piece"] != "" and float(best["t"]) <= float(zbest["t"]) + 0.03:
		return best
	if zbest["zone"] != "":
		return {"piece": "", "zone": zbest["zone"], "p": zbest["p"], "t": zbest["t"], "u": zbest["u"]}
	if best["piece"] != "":
		return best
	return {"piece": "", "zone": near_z, "p": Vector3.ZERO, "t": 0.0, "u": 0.5}

static func _ray_box(o: Vector3, d: Vector3, h: Vector3) -> float:
	var tmin := -INF
	var tmax := INF
	for i in 3:
		if absf(d[i]) < 1e-8:
			if absf(o[i]) > h[i]:
				return -1.0
			continue
		var t1 := (-h[i] - o[i]) / d[i]
		var t2 := (h[i] - o[i]) / d[i]
		tmin = maxf(tmin, minf(t1, t2))
		tmax = minf(tmax, maxf(t1, t2))
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)

## Strahl (d normiert) gegen Kapsel a-b, Radius r. -1 = kein Treffer.
static func _ray_capsule(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3, r: float) -> float:
	var ba := b - a
	var oa := ro - a
	var baba := ba.dot(ba)
	var bard := ba.dot(rd)
	var baoa := ba.dot(oa)
	var rdoa := rd.dot(oa)
	var oaoa := oa.dot(oa)
	var aa := baba - bard * bard
	var bb := baba * rdoa - baoa * bard
	var cc := baba * oaoa - baoa * baoa - r * r * baba
	var h := bb * bb - aa * cc
	if h >= 0.0 and aa > 1e-9:
		var t := (-bb - sqrt(h)) / aa
		var y := baoa + t * bard
		if y > 0.0 and y < baba:
			return t if t >= 0.0 else -1.0
		var oc := oa if y <= 0.0 else ro - b
		bb = rd.dot(oc)
		cc = oc.dot(oc) - r * r
		h = bb * bb - cc
		if h > 0.0:
			var t2 := -bb - sqrt(h)
			return t2 if t2 >= 0.0 else -1.0
	return -1.0

# ---------------------------------------------------------------- Schadensmodell

func _intact(id: String) -> bool:
	return _pieces.has(id) and not bool(_pieces[id]["broken"])

## Ergebnis: {dmg, deflect, blood, head, piece (Integritaet abziehen), zone}
func _resolve(loc: Dictionary, amount: float, headshot: bool) -> Dictionary:
	var piece: String = loc["piece"]
	var zone: String = loc["zone"]
	var r := {"dmg": amount * limb_pass, "deflect": false, "blood": true, "head": false, "piece": "", "zone": zone if zone != "" else piece}
	if headshot:
		if piece == "visor":
			return _plate_hit(r, "visor", amount, visor_pass)
		if piece == "face":
			r["dmg"] = amount * head_damage_multiplier
			r["head"] = true
			return r
		r["dmg"] = amount * helmet_pass
		r["deflect"] = true
		r["blood"] = false
		return r
	if piece != "":
		if piece == "plate_front" or piece == "plate_back":
			return _plate_hit(r, piece, amount, plate_pass)
		if piece.begins_with("shoulder_") or piece.begins_with("thigh_"):
			return _plate_hit(r, piece, amount, limb_plate_pass)
		r["dmg"] = amount * side_pass
		return r
	var p: Vector3 = loc["p"]
	match zone:
		"torso":
			var az := atan2((p.x - 0.004) / 0.2, (p.z - 0.085) / 0.165)
			if p.y >= 1.12 and absf(az) < 0.8:
				if _intact("plate_front"):
					return _plate_hit(r, "plate_front", amount, plate_pass)
				r["dmg"] = amount
			elif p.y >= 1.12 and absf(az) > 2.4:
				if _intact("plate_back"):
					return _plate_hit(r, "plate_back", amount, plate_pass)
				r["dmg"] = amount
			elif p.y < 1.12 and absf(az) < 1.2:
				r["dmg"] = amount * pouch_pass
			else:
				r["dmg"] = amount * side_pass
		"uarm_L", "uarm_R":
			var sid := "shoulder_" + zone.right(1)
			if float(loc["u"]) < 0.45 and _intact(sid):
				return _plate_hit(r, sid, amount, limb_plate_pass)
		"thigh_L", "thigh_R":
			var tid := "thigh_" + zone.right(1)
			if float(loc["u"]) > 0.12 and float(loc["u"]) < 0.6 and _intact(tid) and _thigh_front(zone.right(1), p):
				return _plate_hit(r, tid, amount, limb_plate_pass)
	return r

func _thigh_front(s: String, p: Vector3) -> bool:
	var sk := _soldier.skeleton
	var a := AK.bp(sk, "UpperLeg." + s)
	var b := AK.bp(sk, "LowerLeg." + s)
	var bl := AK.limb_frame(a, b, 1.0 if s == "L" else -1.0)
	var fwd := 1.0 if bl.z.z > 0.0 else -1.0
	var dd := p - a
	var az := atan2(dd.dot(bl.z) * fwd, dd.dot(bl.x))
	return az > -0.35 and az < 1.75

func _plate_hit(r: Dictionary, id: String, amount: float, pass_frac: float) -> Dictionary:
	r["dmg"] = amount * pass_frac
	r["deflect"] = true
	r["blood"] = false
	r["piece"] = id
	r["zone"] = id
	return r

func _resolve_explosion(amount: float) -> Dictionary:
	return {"dmg": amount * explosion_mult, "deflect": false, "blood": true, "head": false, "piece": "", "zone": "explosion"}

# ---------------------------------------------------------------- Schaden

func take_hit_part(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3, headshot: bool) -> void:
	if state == State.DEAD or amount <= 0.0:
		return
	if _soldier == null:
		super.take_hit_part(amount, source, hit_position, hit_normal, headshot)
		return
	_last_src_player = source != null and source.is_in_group("player")
	var res: Dictionary
	var loc := {"piece": "", "zone": "", "p": Vector3.ZERO, "t": 0.0, "u": 0.0}
	if bool(Combat.get("explosion_active")):
		res = _resolve_explosion(amount)
		_explosion_scuff(amount)
	else:
		res = _special_hit(amount, source, hit_position, hit_normal, headshot)
		if res.is_empty():
			var ray := _shot_ray(source, hit_position, hit_normal)
			loc = _locate(ray[0], ray[1], headshot)
			res = _resolve(loc, amount, headshot)
	last_zone = str(res["zone"])
	last_piece = str(res["piece"])
	if res["piece"] != "":
		_damage_piece(str(res["piece"]), amount, loc)
	_apply_result(res, source, hit_position, hit_normal)

## Hook fuer Unterklassen (Juggernaut: Raketen-Volltreffer). Leeres Dictionary = normal weiter.
func _special_hit(_amount: float, _source: Node, _pos: Vector3, _normal: Vector3, _headshot: bool) -> Dictionary:
	return {}

func _apply_result(res: Dictionary, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	var dmg: float = res["dmg"]
	last_dealt = dmg
	health -= dmg
	Events.enemy_damaged.emit(self, dmg)
	if bool(res["blood"]):
		VFX.spawn_blood(hit_position, hit_normal)
	else:
		_noblood_frame = Engine.get_physics_frames()
	if bool(res["deflect"]):
		_deflect_frame = Engine.get_physics_frames()
		stat_deflects += 1
		_deflect_fx(hit_position, hit_normal, source)
	_flinch = 1.0 if not bool(res["deflect"]) else maxf(_flinch, 0.75)
	_last_hit_head = bool(res["head"])
	var dir := -hit_normal
	var src_pos := global_position
	if source is Node3D and source != self:
		src_pos = (source as Node3D).global_position
		var sd := global_position - src_pos
		sd.y = 0.0
		if sd.length() > 0.1:
			dir = sd.normalized()
	if dir.length() < 0.01:
		dir = -global_transform.basis.z
	_last_hit_dir = dir.normalized()
	_after_damage(dmg, res)
	if health <= 0.0:
		_die()
		return
	_bark("hit")
	_on_damaged(source, src_pos)

## Hook (Juggernaut: Taumeln, Boss-Leiste).
func _after_damage(_dmg: float, _res: Dictionary) -> void:
	pass

func _deflect_fx(pos: Vector3, normal: Vector3, source: Node) -> void:
	var n := normal if normal.length() > 0.01 else Vector3.UP
	var fx: Node3D = VFX.call("_get_impact", false)
	if fx != null:
		fx.call("play", "metal", pos, n.normalized(), 1.0)
	_play_sfx("armor_ping_%d" % rng.randi_range(1, 3), pos)
	if _last_src_player:
		var h := AHUD.get_hud(self)
		if h != null:
			h.call("show_deflect")

func _hud_message(text: String, source_is_player: bool = true) -> void:
	if not source_is_player:
		return
	var h := AHUD.get_hud(self)
	if h != null:
		h.call("show_message", text)

## Integritaet abziehen, Einschussmarke setzen, ggf. Platte abwerfen / Visier brechen.
func _damage_piece(id: String, amount: float, loc: Dictionary) -> void:
	if not _pieces.has(id):
		return
	var rec: Dictionary = _pieces[id]
	if rec["broken"]:
		return
	rec["hp"] = float(rec["hp"]) - amount
	var mi: MeshInstance3D = rec["plate_mi"]
	var p: Vector3 = loc.get("p", Vector3.ZERO)
	if rec.has("vis_inv") and p != Vector3.ZERO:
		p = (rec["vis_inv"] as Transform3D) * p   # echtes Visier: Riss im Objektraum des Modells
	var mat: ShaderMaterial = rec["mat"]
	if mat != null and p != Vector3.ZERO:
		if rec["visor"]:
			var crv: Variant = mat.get_shader_parameter("crack")
			var cr: float = 0.0 if crv == null else float(crv)
			if cr <= 0.0:
				mat.set_shader_parameter("crack_pos", p)
				mat.set_shader_parameter("crack", 0.45)
			else:
				mat.set_shader_parameter("crack_pos2", p)
				mat.set_shader_parameter("crack2", 0.6)
				mat.set_shader_parameter("crack", minf(cr + 0.25, 1.0))
		else:
			var hits: PackedVector4Array = rec["hits"]
			var i: int = rec["hit_i"]
			hits[i % 8] = Vector4(p.x, p.y, p.z, 0.028 if armor_kind != "juggernaut" else 0.04)
			rec["hit_i"] = i + 1
			rec["hits"] = hits
			mat.set_shader_parameter("hits", hits)
	if mi != null and float(rec["max"]) < INF:
		mi.set_instance_shader_parameter("damage", clampf(1.0 - float(rec["hp"]) / float(rec["max"]), 0.0, 1.0))
	if float(rec["hp"]) <= 0.0:
		_break_piece(id)

func _break_piece(id: String) -> void:
	var rec: Dictionary = _pieces[id]
	rec["broken"] = true
	var pos: Vector3 = global_position + Vector3.UP * 1.3
	var mi0: MeshInstance3D = rec["plate_mi"]
	if mi0 != null and is_instance_valid(mi0):
		pos = mi0.global_transform * mi0.get_aabb().get_center()
	if rec["visor"]:
		_play_sfx("visor_crack", pos)
		var fx: Node3D = VFX.call("_get_impact", false)
		if fx != null:
			fx.call("play", "metal", pos, -global_transform.basis.z, 1.0)
		var mat: ShaderMaterial = rec["mat"]
		if mi0 != null:
			# Splitter weg, nur ein gesplitterter Rand bleibt kurz sichtbar
			var tw := mi0.create_tween()
			mat.set_shader_parameter("crack", 1.0)
			tw.tween_interval(0.08)
			tw.tween_callback(func() -> void: mi0.visible = false)
		_on_piece_broken(id)
		_hud_message("VISIER GEBROCHEN", _last_src_player)
		return
	_play_sfx("armor_break", pos)
	_detach_piece(rec)
	_on_piece_broken(id)
	if id.begins_with("plate") or id == "chest_plate" or id == "pack":
		_hud_message("PANZERUNG DURCHSCHLAGEN", _last_src_player)

## Hook (Juggernaut: Tornister-Explosion).
func _on_piece_broken(_id: String) -> void:
	pass

var _last_src_player: bool = false

## Platte als Truemmerteil abwerfen (RigidBody, Layer debris), Plattenmeshes wandern mit.
func _detach_piece(rec: Dictionary) -> void:
	var mi0: MeshInstance3D = rec["plate_mi"]
	if mi0 == null or not is_instance_valid(mi0) or not is_inside_tree():
		return
	var aabb := mi0.get_aabb()
	var gt := mi0.global_transform
	var center := gt * aabb.get_center()
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1
	rb.mass = 4.0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sc := gt.basis.get_scale()
	box.size = (aabb.size * sc).max(Vector3.ONE * 0.04)
	cs.shape = box
	rb.add_child(cs)
	if not bool(VFX.call("add_debris", rb)):
		mi0.visible = false
		return
	rb.global_transform = Transform3D(gt.basis.orthonormalized(), center)
	# Box-Achsen = Mesh-Achsen (Rotation), Mesh relativ zum Koerper
	var keep := gt
	_soldier._meshes.erase(mi0)
	for gm: Node in mi0.find_children("*", "MeshInstance3D", true, false):
		_soldier._meshes.erase(gm)   # angehaengte Ausruestungsmodelle (Juggernaut)
	mi0.get_parent().remove_child(mi0)
	rb.add_child(mi0)
	mi0.global_transform = keep
	var out := (center - (global_position + Vector3.UP * 1.1))
	out.y = 0.0
	out = out.normalized() if out.length() > 0.01 else -global_transform.basis.z
	rb.linear_velocity = out * rng.randf_range(1.6, 2.6) + Vector3.UP * rng.randf_range(1.2, 2.2) + _last_hit_dir * 1.2
	rb.angular_velocity = _rand_spin(5.0)
	VFX.call("schedule_free", rb, 12.0)
	rec["plate_mi"] = null

## Explosionen: Lack schwaerzen (optisch), Platten bleiben.
func _explosion_scuff(amount: float) -> void:
	for id: String in _pieces:
		var rec: Dictionary = _pieces[id]
		var mi: MeshInstance3D = rec["plate_mi"]
		if mi != null and is_instance_valid(mi) and not rec["visor"]:
			var cur: float = mi.get_instance_shader_parameter("damage") if mi.get_instance_shader_parameter("damage") != null else 0.0
			mi.set_instance_shader_parameter("damage", clampf(cur + amount / 300.0, 0.0, 1.0))

func get_status() -> Dictionary:
	var s := super.get_status()
	var broken: Array[String] = []
	for id: String in _pieces:
		if _pieces[id]["broken"]:
			broken.append(id)
	s["armor_broken"] = broken
	return s

## Zielpunkt fuer Bots: Kopf, sobald das Visier gebrochen ist, sonst Brust.
func get_aim_point() -> Vector3:
	if _head_hitbox != null and not _intact("visor"):
		return _head_hitbox.global_position
	return global_position + Vector3.UP * 1.25 * body_scale
