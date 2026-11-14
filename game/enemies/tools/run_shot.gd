extends Node3D
## Debug: laufende Figur (echte Pipeline: Actor -> velocity -> SoldierVisual) seitlich auf Fusshoehe filmen
## und Fussgleiten messen. Nicht headless:
##   Godot --audio-driver Dummy --path . res://game/enemies/tools/run_shot.tscn -- --who=lena --speed=3.2 --out=captures/run_feet/x --bg
##   (Bild kommt aus einem SubViewport fester Groesse [--w=1280] [--h=720], das Fenster darf klein sein)
##   [--who=lena|enemy|op] [--speed=3.2] [--strafe=0] (Grad zwischen Lauf- und Blickrichtung) [--view=side|q|front]
##   [--dist=2.4] [--focus_y=0.45] [--shots=12] [--every=3] [--measure_only=1]
## Ausgabe: <out>_sheet.png (Kontaktbogen 4x3) und eine Zeile "run_shot: slide ..." (m/s Fussgeschwindigkeit
## waehrend Bodenkontakt; natuerlich ~0).

const Actor := preload("res://game/levels/overwatch_actor.gd")
const C_LENA := [Color(0.16, 0.18, 0.2), Color(0.25, 0.24, 0.22), Color(0.45, 0.7, 0.95)]
const C_GARDE := [Color(0.42, 0.43, 0.44), Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13)]

var _a: CharacterBody3D
var _cam: Camera3D
var _vp: SubViewport   # feste Bildgroesse (--w/--h), unabhaengig vom Fenster (--bg = kleines Hintergrundfenster)
var _frames := 0
var _shots: Array[Image] = []
var _rec := [[], []]   # je Fuss: [y, pos(xz)] pro Physik-Frame
var _t := 0.0

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.65, 0.65, 0.65)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 40)
	cs.shape = bs
	cs.position.y = -0.5
	floor.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 40)
	mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.36, 0.37, 0.34)
	fm.uv1_scale = Vector3(200, 20, 1)
	fm.albedo_texture = _grid_tex()
	mi.material_override = fm
	floor.add_child(mi)
	add_child(floor)
	var who := _arg("who", "lena")
	_a = Actor.new()
	_a.set("role", "friendly" if who == "lena" else "enemy")
	_a.set("enemy_type", "rifleman")
	var cols: Array = C_LENA if who == "lena" else C_GARDE
	_a.set_meta("faction", "resistance" if who == "lena" else "garde")
	_a.set("color_primary", cols[0])
	_a.set("color_secondary", cols[1])
	_a.set("color_armband", cols[2])
	_a.set("invulnerable", true)
	if who == "op":
		Settings.set_value("graphics/real_soldiers", false)
	add_child(_a)
	_a.global_position = Vector3(-150, 0.05, 0)
	var spd := float(_arg("speed", "3.2"))
	var strafe := deg_to_rad(float(_arg("strafe", "0")))
	_a.call("walk_to", Vector3(150, 0, 0), spd, false)
	if strafe != 0.0:
		# Blickrichtung um strafe gegen die Laufrichtung (+X) gedreht: Zielpunkt weit voraus in dieser Richtung
		_a.set("aiming", true)
		_a.set("_player", _a)
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(_arg("w", "1280")), int(_arg("h", "720")))
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.fov = float(_arg("fov", "30"))
	_cam.current = true

func _grid_tex() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(0.42, 0.43, 0.4))
	for i in 64:
		for k in 2:
			img.set_pixel(i, k, Color(0.25, 0.25, 0.24))
			img.set_pixel(k, i, Color(0.25, 0.25, 0.24))
	return ImageTexture.create_from_image(img)

func _physics_process(delta: float) -> void:
	_t += delta
	var strafe := deg_to_rad(float(_arg("strafe", "0")))
	if strafe != 0.0:
		var p := _a.global_position
		_a.set("aim_point", p + Vector3(cos(strafe), 0, -sin(strafe)) * 30.0 + Vector3.UP * 1.3)
	var sv: SoldierVisual = _a.get("_soldier")
	if sv == null or _t < 1.5:
		return
	var sk := sv.skeleton
	for j in 2:
		var side := "L" if j == 0 else "R"
		var bi := sk.find_bone("Toes." + side)
		var fb := sk.find_bone("Foot." + side)
		var pt := sk.global_transform * sk.get_bone_global_pose(fb).origin
		var pt2 := sk.global_transform * sk.get_bone_global_pose(bi).origin if bi >= 0 else pt
		_rec[j].append([minf(pt.y, pt2.y), Vector2(pt.x, pt.z), Vector2(pt2.x, pt2.z), pt.y, pt2.y])

func _process(_delta: float) -> void:
	_frames += 1
	var sv: SoldierVisual = _a.get("_soldier")
	if sv == null:
		return
	var view := _arg("view", "side")
	var fy := float(_arg("focus_y", "0.45"))
	var dist := float(_arg("dist", "2.6"))
	var dir := Vector3(0, 0.1, 1)
	match view:
		"q":
			dir = Vector3(0.7, 0.25, 1)
		"front":
			dir = Vector3(1, 0.15, 0)
		"low":
			dir = Vector3(0.0, 0.02, 1)
	var c := Vector3(_a.global_position.x, fy, _a.global_position.z)
	_cam.global_position = c + dir.normalized() * dist
	_cam.look_at(c)
	if _t < 2.0:
		return
	if _arg("measure_only", "") == "" and _frames % int(_arg("every", "3")) == 0 and _shots.size() < int(_arg("shots", "12")):
		_shots.append(_vp.get_texture().get_image())
	if _t > 2.0 + float(_arg("dur", "3.0")) and (_shots.size() >= int(_arg("shots", "12")) or _arg("measure_only", "") != ""):
		_finish(sv)

func _finish(sv: SoldierVisual) -> void:
	set_process(false)
	var out := _arg("out", "user://run")
	if not _shots.is_empty():
		var w := _shots[0].get_width() / 2
		var h := _shots[0].get_height() / 2
		var cols := 4
		var rows := int(ceil(_shots.size() / float(cols)))
		var sheet := Image.create(w * cols, h * rows, false, _shots[0].get_format())
		for i in _shots.size():
			var im := _shots[i]
			im.resize(w, h, Image.INTERPOLATE_BILINEAR)
			sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
		sheet.save_png(out + "_sheet.png")
		_shots[0].save_png(out + "_0.png")
	# Fussgleiten: horizontale Fussgeschwindigkeit in Frames mit Bodenkontakt (Fuss < min + 3 cm)
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var res := []
	for j in 2:
		var r: Array = _rec[j]
		var mn := 99.0
		for x in r:
			mn = minf(mn, x[0])
		var vs: Array[float] = []
		var contact := 0
		for i in range(1, r.size()):
			if r[i][0] < mn + 0.03 and r[i - 1][0] < mn + 0.03:
				contact += 1
				# Kontaktpunkt: der niedrigere von Ferse(Knoechel)/Ballen
				var k := 1 if r[i][3] <= r[i][4] else 2
				vs.append((r[i][k] as Vector2).distance_to(r[i - 1][k]) / dt)
		vs.sort()
		var med := vs[vs.size() / 2] if not vs.is_empty() else -1.0
		var avg := 0.0
		for v in vs:
			avg += v
		avg = avg / maxf(vs.size(), 1)
		res.append("%s: min_y=%.3f contact=%d/%d med=%.2f avg=%.2f m/s" % ["L" if j == 0 else "R", mn, contact, r.size(), med, avg])
	var csv := FileAccess.open(out + "_trace.csv", FileAccess.WRITE)
	csv.store_line("i,fLy,tLy,fLx,tLx,fRy,tRy,fRx,tRx")
	for i in mini(_rec[0].size(), _rec[1].size()):
		var a: Array = _rec[0][i]
		var b: Array = _rec[1][i]
		csv.store_line("%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f" % [i, a[3], a[4], a[1].x, a[2].x, b[3], b[4], b[1].x, b[2].x])
	csv.close()
	var sk2 := sv.skeleton
	print("run_shot: rest Foot.L y=%.3f Toes.L y=%.3f skel_y=%.3f" % [sk2.get_bone_global_rest(sk2.find_bone("Foot.L")).origin.y, sk2.get_bone_global_rest(sk2.find_bone("Toes.L")).origin.y, sk2.global_position.y])
	var vel := Vector2(_a.velocity.x, _a.velocity.z).length()
	print("run_shot: who=%s kind=%s/%s v=%.2f loco=%s bp=%s ts=%.2f slide %s" % [_arg("who", "lena"), sv.kind, sv.variant, vel, str(sv.get("_loco")), str(sv.anim_tree.get("parameters/loco/blend_position")), float(sv.anim_tree.get("parameters/loco_ts/scale")) if sv.anim_tree.get("parameters/loco_ts/scale") != null else 1.0, " | ".join(res)])
	get_tree().quit()
