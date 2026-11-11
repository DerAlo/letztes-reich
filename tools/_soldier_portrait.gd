extends Node3D
## Pruefaufnahmen der Gegner-Soldaten (SoldierVisual) ohne KI.
##   godot --path . res://tools/_soldier_portrait.tscn -- --mode=lineup --faction=ru --types=rifleman,assault --out=DIR
##   ... --mode=anim --faction=reich --type=rifleman --out=DIR   (walk, run, sprint, crouch, aim, fire, die)
##   ... --mode=muzzle --faction=ru --type=rifleman --out=DIR    (Nahaufnahmen Muendungsfeuer)
## Optional: --colors=r,g,b;r,g,b;r,g,b (color_primary/secondary/armband), --real=0 (altes SWAT-Modell),
##   --variant=a|b|c (erzwingt MH-Variante ueber den Namen), --bg=night

const FakePlayer := preload("res://game/enemies/_test_fake_player.gd")

var out_dir := "user://soldier_portrait"
var cam: Camera3D
var fp: CharacterBody3D

func _ready() -> void:
	out_dir = str(Game.arg("out", out_dir))
	DirAccess.make_dir_recursive_absolute(out_dir)
	if str(Game.arg("real", "1")) == "0":
		Settings.set_value("graphics/real_soldiers", false)
	_world()
	await get_tree().physics_frame
	fp = CharacterBody3D.new()
	fp.set_script(FakePlayer)
	add_child(fp)
	fp.global_position = Vector3(0, 0.05, 8)
	var mode := str(Game.arg("mode", "lineup"))
	if mode == "lineup":
		await _lineup()
	elif mode == "anim":
		await _anim()
	elif mode == "muzzle":
		await _muzzle()
	get_tree().quit()

func _world() -> void:
	var night := str(Game.arg("bg", "")) == "night"
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.03, 0.035, 0.05) if night else Color(0.52, 0.58, 0.64)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.7)
	e.ambient_light_energy = 0.12 if night else 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 35, 0)
	sun.light_energy = 0.08 if night else 1.5
	sun.shadow_enabled = true
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -150, 0)
	fill.light_energy = 0.02 if night else 0.35
	add_child(fill)
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	sb.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.32, 0.31, 0.28)
	m.roughness = 0.95
	mi.material_override = m
	sb.add_child(mi)
	sb.position.y = -0.5
	add_child(sb)
	cam = Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.make_current()

func _colors(en: Node) -> void:
	var c := str(Game.arg("colors", ""))
	if c == "":
		return
	var keys := ["color_primary", "color_secondary", "color_armband"]
	var parts := c.split(";")
	for i in mini(parts.size(), 3):
		var v := parts[i].split(",")
		en.set(keys[i], Color(float(v[0]), float(v[1]), float(v[2])))

func _spawn(ty: String, pos: Vector3, fac: String, idx: int) -> Enemy:
	var en: Enemy = load("res://game/enemies/%s.tscn" % ty).instantiate()
	en.set_meta("faction", fac)
	_colors(en)
	var forced := str(Game.arg("variant", ""))
	en.name = "P_%s_%d" % [ty, idx]
	if forced != "":
		# Namen suchen, dessen Hash die gewuenschte Variante waehlt
		for k in 200:
			var nm := "P_%s_%d_%d" % [ty, idx, k]
			var h := absi(hash("%s|%s|%s" % [nm, ty, pos.snapped(Vector3.ONE * 0.5)])) % 3
			if ["a", "b", "c"][h] == forced:
				en.name = nm
				break
	en.position = pos
	add_child(en)
	en.global_position = pos
	en.rotation.y = PI
	en.set_physics_process(false)
	en.set_process(false)
	en.debug_log = false
	return en

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))

func _tick(list: Array, dt: float) -> void:
	for en: Enemy in list:
		if en._soldier != null:
			en._soldier.tick(dt)

func _wait(list: Array, sec: float) -> void:
	var t := 0.0
	while t < sec:
		var dt := get_process_delta_time()
		_tick(list, dt)
		await get_tree().process_frame
		t += dt

func _look(from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)

# ------------------------------------------------------------------ Aufstellung

func _lineup() -> void:
	var types := str(Game.arg("types", "rifleman,assault,marksman,officer,heavy")).split(",")
	var fac := str(Game.arg("faction", "ru"))
	var aim := str(Game.arg("aim", "0")) == "1"
	var list: Array = []
	var n := types.size()
	for i in n:
		var x := (float(i) - (n - 1) * 0.5) * 1.3
		list.append(_spawn(types[i], Vector3(x, 0.05, 0), fac, i))
	for en: Enemy in list:
		en._player = fp
		en._aim_at_target = aim
		en._los = aim
	await _wait(list, 1.2)
	var w := maxf(n * 1.3, 2.6)
	_look(Vector3(0, 1.1, w * 1.35 + 1.0), Vector3(0, 0.95, 0))
	await _wait(list, 0.1)
	await _shot("front")
	_look(Vector3(-w * 0.9, 1.4, w * 1.1), Vector3(0, 0.95, 0))
	await _wait(list, 0.1)
	await _shot("q34")
	_look(Vector3(w * 0.4, 1.3, -w * 1.3 - 1.0), Vector3(0, 0.95, 0))
	await _wait(list, 0.1)
	await _shot("back")
	for i in n:
		var p: Vector3 = (list[i] as Node3D).global_position
		_look(p + Vector3(-0.55, 1.62, 1.1), p + Vector3(0, 1.45, 0))
		await _wait(list, 0.05)
		await _shot("face_%d_%s" % [i, types[i]])
		_look(p + Vector3(1.6, 1.0, 1.5), p + Vector3(0, 0.95, 0))
		await _wait(list, 0.05)
		await _shot("full_%d_%s" % [i, types[i]])

# ------------------------------------------------------------------ Animationen

func _anim() -> void:
	var ty := str(Game.arg("type", "rifleman"))
	var fac := str(Game.arg("faction", "ru"))
	var en := _spawn(ty, Vector3(0, 0.05, 0), fac, 0)
	var list := [en]
	en._player = fp
	await _wait(list, 0.6)
	# Phasen: [Name, Geschwindigkeit (m/s, vorwaerts), Haltung, Zielen, Feuern, Dauer]
	var phases := [
		["idle", 0.0, 0.0, false, false, 1.0],
		["walk", 1.4, 0.0, false, false, 1.6],
		["run", 2.4, 0.0, true, false, 1.6],
		["sprint", 4.2, 0.0, false, false, 1.6],
		["strafe", -1.3, 0.0, true, false, 1.4],
		["crouch", 0.9, 1.0, true, false, 1.6],
		["aim", 0.0, 0.0, true, false, 1.0],
		["fire", 0.0, 0.0, true, true, 1.4],
		["cover_fire", 0.0, 1.0, true, true, 1.2],
	]
	var frame := 0
	for ph in phases:
		var pname: String = ph[0]
		var spd: float = ph[1]
		var stance: float = ph[2]
		en._aim_at_target = ph[3]
		en._los = ph[3]
		en._stance = stance
		var t := 0.0
		var next_shot := 0.0
		var next_pic := 0.35
		var dur: float = ph[5]
		while t < dur:
			var dt := get_process_delta_time()
			var fwd := -en.global_transform.basis.z
			if pname == "strafe":
				en.velocity = en.global_transform.basis.x * spd
			else:
				en.velocity = fwd * spd
			en.global_position += en.velocity * dt
			fp.global_position = en.global_position + fwd * 8.0 + Vector3(0, 0.05, 0)
			if ph[4]:
				en._burst_left = 1
				if t >= next_shot:
					en._flash_timer = 0.06
					en._recoil = 1.0
					en.stat_shots += 1
					next_shot = t + 0.13
			en._flash_timer = maxf(en._flash_timer - dt, 0.0)
			en._recoil = move_toward(en._recoil, 0.0, dt * 6.0)
			_tick(list, dt)
			var p := en.global_position
			_look(p + Vector3(-3.4, 1.15, -0.6), p + Vector3(0, 0.9, 0))
			await get_tree().process_frame
			t += dt
			if t >= next_pic:
				await _shot("%03d_%s" % [frame, pname])
				frame += 1
				next_pic += 0.25
	en._burst_left = 0
	en.velocity = Vector3.ZERO
	en._stance = 0.0
	en._last_hit_head = str(Game.arg("ragdoll", "0")) == "1"
	en._soldier.die(false)
	var t2 := 0.0
	var nxt := 0.15
	while t2 < 2.6:
		var dt := get_process_delta_time()
		_tick(list, dt)
		var p2 := en.global_position
		_look(p2 + Vector3(-5.5, 2.4, -1.0), p2 + Vector3(0, 0.5, 0))
		var hb := en._soldier.skeleton.find_bone("Hips")
		var pbs := ""
		for pb in en._soldier.bones:
			pbs += " %s=%s" % [pb.name, pb.global_position.snapped(Vector3.ONE * 0.01)]
		print("[die] t=%.2f hips=%s ragdoll=%s%s" % [t2, en._soldier.skeleton.global_transform * en._soldier.skeleton.get_bone_global_pose(hb).origin, en._soldier._ragdoll_on, pbs])
		await get_tree().process_frame
		t2 += dt
		if t2 >= nxt:
			await _shot("%03d_die" % frame)
			frame += 1
			nxt += 0.3

# ------------------------------------------------------------------ Muendungsfeuer

func _muzzle() -> void:
	var ty := str(Game.arg("type", "rifleman"))
	var fac := str(Game.arg("faction", "ru"))
	var en := _spawn(ty, Vector3(0, 0.05, 0), fac, 0)
	var list := [en]
	en._player = fp
	fp.global_position = Vector3(1.5, 0.05, 10)  # Ziel leicht seitlich -> Muendung von der Seite sichtbar
	en._aim_at_target = true
	en._los = true
	await _wait(list, 1.2)
	var mzfix := str(Game.arg("mzfix", ""))
	if mzfix != "":
		var fx0: Node3D = en._soldier._muzzle_fx
		for nm in ["_front", "_side"]:
			var g: GeometryInstance3D = fx0.get(nm)
			var mat := (g.material_override as ShaderMaterial).duplicate() as ShaderMaterial
			var sh := Shader.new()
			var code := mat.shader.code
			if mzfix == "add":
				code = code.replace("blend_premul_alpha,", "blend_add,").replace("ALPHA = 0.0;", "")
			elif mzfix == "nodepth":
				code = code.replace("blend_premul_alpha,", "blend_premul_alpha, depth_test_disabled,")
			elif mzfix == "white":
				code = code.replace("ALPHA = 0.0;", "ALBEDO = vec3(5.0, 0.0, 5.0); ALPHA = 1.0;")
			sh.code = code
			mat.shader = sh
			g.material_override = mat
			if mzfix == "std":
				var sm := StandardMaterial3D.new()
				sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				sm.albedo_color = Color(1, 0, 1)
				sm.cull_mode = BaseMaterial3D.CULL_DISABLED
				g.material_override = sm
			print("[mzfix] ", nm, " mesh=", (g as MeshInstance3D).mesh, " aabb=", g.get_aabb(), " xf=", g.transform)
	var views := {
		"side": Vector3(-3.0, 1.4, 1.2),
		"front": Vector3(2.5, 1.5, 6.5),
		"far": Vector3(-5.0, 1.7, 22.0),
	}
	for v: String in views:
		_look(views[v], en.global_position + Vector3(0.1, 1.25, 0.6))
		await _wait(list, 0.3)
		await _shot("muzzle_%s_off" % v)
		en._burst_left = 1
		en._flash_timer = 0.06
		en._recoil = 1.0
		en.stat_shots += 1
		_tick(list, 0.0)
		await get_tree().process_frame
		var fx: Node3D = en._soldier._muzzle_fx
		var fr: Node3D = fx.get("_front")
		print("[muzzle] %s front_vis=%s vis_tree=%s pos=%s flash_t=%.3f basis=%s layers=%d" % [v, fr.visible, fr.is_visible_in_tree(), fr.global_position, fx.get("_flash_t"), fr.global_transform.basis.get_scale(), (fr as VisualInstance3D).layers])
		await _shot("muzzle_%s_on" % v)
		for j in 3:
			# nach dem PNG-Speichern erst ein paar normale Frames (sonst frisst ein langer delta den 2-Frame-Blitz)
			for w in 4:
				await get_tree().process_frame
			fx.call("fire")
			await get_tree().process_frame
			print("[muzzle] %s on%d flash_t=%.3f dt=%.3f" % [v, j, fx.get("_flash_t"), get_process_delta_time()])
			await _shot("muzzle_%s_on%d" % [v, j])
		fx.call("fire")
		fx.set_process(false)
		await get_tree().process_frame
		await get_tree().process_frame
		print("[muzzle] frozen vis=", fr.visible, " cam_mask=", cam.cull_mask, " cur=", get_viewport().get_camera_3d() == cam)
		await _shot("muzzle_%s_frozen" % v)
		fx.set_process(true)
		en._flash_timer = 0.0
		en._burst_left = 0
		await _wait(list, 0.3)
