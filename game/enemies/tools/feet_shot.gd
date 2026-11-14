extends Node3D
## Debug-Bildserie der Gegnerfuesse beim Laufen (nicht headless), Diagnose "Clownschuhe":
## Godot --path . --resolution 1600x900 res://game/enemies/tools/feet_shot.tscn -- --out=captures/clown_feet/x
##   [--only=0..4] (0-2 MH a/b/c, 3 Armored/OP, 4 Juggernaut) [--loco=0,4.2 | --sweep=1] [--view=side|q|front]
##   [--dist=1.6] [--focus_y=0.2] [--shots=12] [--every=4] [--ts=0.5] [--lod=1.0] [--stance=0] [--aim=1]

const SCENES := ["res://game/enemies/rifleman.tscn", "res://game/enemies/rifleman.tscn", "res://game/enemies/rifleman.tscn",
	"res://game/enemies/armored.tscn", "res://game/enemies/juggernaut.tscn"]
const VARIANTS := ["a", "b", "c", "", ""]
## Sweep: Fortbewegung im Zeitverlauf (Geschwindigkeit im Skelettraum, m/s)
const SWEEP := [Vector2(0, 0), Vector2(0, 1.4), Vector2(0, 2.4), Vector2(0, 4.2), Vector2(0, 5.5), Vector2(0, 2.0),
	Vector2(2.6, 0), Vector2(-2.6, 0), Vector2(0, -2.6), Vector2(1.8, 3.0)]

var _soldiers: Array = []
var _frames := 0
var _shot := 0
var _t := 0.0
var _cam: Camera3D

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	Engine.time_scale = float(_arg("ts", "0.5"))
	if _arg("real", "") != "":   # nur zusammen mit --no-settings (sonst wird settings.cfg geschrieben)
		Settings.set_value("graphics/real_soldiers", _arg("real", "1") == "1")
	get_viewport().mesh_lod_threshold = float(_arg("lod", "1.0"))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.6, 0.6)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.36, 0.33)
	floor.material_override = fm
	add_child(floor)
	var only := int(_arg("only", "-1"))
	for i in SCENES.size():
		if only >= 0 and i != only:
			continue
		SoldierVisual.force_variant = VARIANTS[i]
		var en: Enemy = (load(SCENES[i]) as PackedScene).instantiate()
		en.name = "Feet%d" % i
		add_child(en)
		SoldierVisual.force_variant = ""
		en.global_position = Vector3((i - 2) * 1.1 if only < 0 else 0.0, 0, 0)
		en.rotation.y = PI
		en.set_physics_process(false)
		_soldiers.append(en)
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.fov = float(_arg("fov", "35"))
	var fy := float(_arg("focus_y", "0.25" if only >= 0 else "0.6"))
	var dist := float(_arg("dist", "1.6" if only >= 0 else "6.5"))
	var dir := Vector3(0, 0.25, 1)
	match _arg("view", "q"):
		"side":
			dir = Vector3(1, 0.15, 0)
		"q":
			dir = Vector3(0.8, 0.3, 1)
		"back":
			dir = Vector3(0.3, 0.3, -1)
	_cam.position = Vector3(0, fy, 0) + dir.normalized() * dist
	_cam.look_at(Vector3(0, fy, 0))
	_cam.current = true

var _foot := {}   # Soldat -> [Seite] -> Liste [Ruhepos, Knochen, Gewichte]
var _worst := {}

## Fuss-Vertices (Ruhepose y < 0.16) je Seite sammeln
func _collect(sv: SoldierVisual) -> Array:
	var sk := sv.skeleton
	var sets := [[], []]
	for mi in sk.get_children():
		if not (mi is MeshInstance3D) or (mi as MeshInstance3D).skin == null:
			continue
		var skin := (mi as MeshInstance3D).skin
		var bb := []
		for j in skin.get_bind_count():
			bb.append(sk.find_bone(String(skin.get_bind_name(j))))
		var am := (mi as MeshInstance3D).mesh as ArrayMesh
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bs.is_empty():
				continue
			var per := bs.size() / vs.size()
			for i in vs.size():
				var p := Vector3.ZERO
				var bl := []
				var wl := []
				for k in per:
					var w := ws[i * per + k]
					if w > 0.0:
						var b: int = bb[bs[i * per + k]]
						p += (sk.get_bone_global_rest(b) * skin.get_bind_pose(bs[i * per + k]) * vs[i]) * w
						bl.append(b)
						wl.append(w)
				if p.y < 0.16 and absf(p.x) > 0.02:
					sets[0 if p.x > 0.0 else 1].append([p, bl, wl])
	return sets

func _extent(sk: Skeleton3D, set: Array, fb: int) -> Vector3:
	var inv := sk.get_bone_global_pose(fb).affine_inverse()
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := -mn
	for e in set:
		var p := Vector3.ZERO
		for k in (e[1] as Array).size():
			var b: int = e[1][k]
			p += (sk.get_bone_global_pose(b) * sk.get_bone_global_rest(b).affine_inverse() * (e[0] as Vector3)) * float(e[2][k])
		p = inv * p
		mn = mn.min(p)
		mx = mx.max(p)
	return mx - mn

func _measure(en: Enemy, lo: Vector2) -> void:
	var sv: SoldierVisual = en._soldier
	var sk := sv.skeleton
	if not _foot.has(en):
		var sets := _collect(sv)
		var fb := [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
		var rest := []
		for j in 2:
			var inv := sk.get_bone_global_rest(fb[j]).affine_inverse()
			var mn := Vector3(1e9, 1e9, 1e9)
			var mx := -mn
			for e in sets[j]:
				var q: Vector3 = inv * (e[0] as Vector3)
				mn = mn.min(q)
				mx = mx.max(q)
			rest.append(mx - mn)
		_foot[en] = [sets, fb, rest]
		_worst[en] = [0.0, Vector2.ZERO, 0, Vector3.ZERO]
		return
	var d: Array = _foot[en]
	for j in 2:
		var ex := _extent(sk, d[0][j], d[1][j])
		var r: Vector3 = d[2][j]
		var q := maxf(maxf(ex.x / r.x, ex.y / r.y), ex.z / r.z)
		if q > _worst[en][0]:
			_worst[en] = [q, lo, j, ex / r]

func _loco() -> Vector2:
	if _arg("measure", "") != "":
		# Zufaellige Blend-Positionen (alle 0.4 s neu), Uebergaenge gelerpt
		var seg := int(_t / 0.4)
		var r1 := RandomNumberGenerator.new()
		r1.seed = seg
		var a := Vector2(r1.randf_range(-3.5, 3.5), r1.randf_range(-3.0, 5.5))
		r1.seed = seg + 1
		var b := Vector2(r1.randf_range(-3.5, 3.5), r1.randf_range(-3.0, 5.5))
		return a.lerp(b, clampf(fmod(_t, 0.4) / 0.2, 0.0, 1.0))
	if _arg("sweep", "") != "":
		var seg := 1.2   # Spielsekunden pro Abschnitt
		var k := _t / seg
		var i := int(k) % SWEEP.size()
		var j := (i + 1) % SWEEP.size()
		var f := clampf((k - floor(k)) * 2.0, 0.0, 1.0)   # erste Haelfte Uebergang, dann halten
		return (SWEEP[i] as Vector2).lerp(SWEEP[j], f)
	var l := _arg("loco", "0,2.4").split(",")
	return Vector2(float(l[0]), float(l[1]))

func _process(delta: float) -> void:
	_frames += 1
	_t += delta
	var lo := _loco()
	for en in _soldiers:
		var sv: SoldierVisual = en._soldier
		if sv == null:
			continue
		sv.set_loco(lo, float(_arg("stance", "0")))
		sv.ik.aim_weight = float(_arg("aim", "1"))
		if _frames == 2 and _arg("notoes", "") != "":
			var ap: AnimationPlayer = sv.find_children("*", "AnimationPlayer", true, false)[0]
			for an in ap.get_animation_list():
				var a := ap.get_animation(an)
				for ti in range(a.get_track_count() - 1, -1, -1):
					if String(a.track_get_path(ti)).contains(":Toes."):
						a.remove_track(ti)
		if _frames == 2 and _arg("lodbias", "") != "":
			for gi in sv.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).lod_bias = float(_arg("lodbias", "1"))
	if _arg("measure", "") != "":
		for en in _soldiers:
			_measure(en, lo)
		if _t > float(_arg("measure", "20")):
			for en in _soldiers:
				var w: Array = _worst[en]
				print("%s (%s/%s): max Fuss-Ausdehnung x%.2f bei loco=%s Seite %d rel=%s" % [en.name, (en._soldier as SoldierVisual).kind, (en._soldier as SoldierVisual).variant, w[0], w[1], w[2], w[3]])
			get_tree().quit()
		return
	var start := int(_arg("start", "30"))
	if _frames >= start and (_frames - start) % int(_arg("every", "4")) == 0:
		var img := get_viewport().get_texture().get_image()
		var out := _arg("out", "user://feet")
		img.save_png("%s_%03d.png" % [out, _shot])
		_shot += 1
		if _shot >= int(_arg("shots", "12")):
			print("feet_shot: %d Bilder -> %s_*.png" % [_shot, out])
			get_tree().quit()
