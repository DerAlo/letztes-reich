extends Node3D
## Debug-Render fuer Blut-Effekte (blood_fx.gd): echter Gegner vor einer Wand, Treffer wie von weapon.gd.
## Rendert in einen SubViewport fester Groesse (Fenster bleibt klein, --bg) und speichert PNGs.
## godot --path . res://game/vfx/_blood_shot.tscn -- --bg --out=captures/blood [--perf=1]

const W := 1280
const H := 720

var _vp: SubViewport
var _cam: Camera3D
var _out := "captures/blood"
var _enemy: Node3D
var _shooter := Vector3(0.3, 1.45, 9.0)

func _arg(n: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + n + "="):
			return a.substr(n.length() + 3)
	return d

func _ready() -> void:
	_out = _arg("out", _out)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + _out))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.38, 0.47, 0.6)
	sm.sky_horizon_color = Color(0.68, 0.7, 0.72)
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.5, 0), Vector3(40, 1, 40), "asphalt_02", 0.25)          # Boden
	_box(Vector3(0, 2.0, -2.6), Vector3(12, 4, 0.5), "concrete_wall_008", 0.4) # Wand hinter dem Ziel

	_enemy = (load("res://game/enemies/rifleman.tscn") as PackedScene).instantiate()
	add_child(_enemy)
	_enemy.global_position = Vector3(0, 0, 0)
	_enemy.rotation.y = 0.0
	_enemy.set_physics_process(false)

	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)
	_cam.current = true
	_cam.fov = 40.0
	if _arg("perf", "0") == "1":
		_run_perf.call_deferred()
	else:
		_run.call_deferred()

func _box(pos: Vector3, size: Vector3, tex: String, uv: float) -> void:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s/diffuse.jpg" % tex)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s/normal.jpg" % tex)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv
	m.roughness = 0.9
	mi.material_override = m
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	add_child(sb)
	sb.global_position = pos

func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)

func _wait_real(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < sec:
		await get_tree().process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://%s/%s.png" % [_out, name])
	_vp.get_texture().get_image().save_png(path)
	print("BLOODSHOT ", path)

## Schuss wie weapon.gd: Strahl vom Schuetzen auf einen Zielpunkt, Treffer an Hitbox/Koerper.
func _shoot(target: Vector3, dmg: float) -> void:
	var dir := (target - _shooter).normalized()
	var sp := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_shooter, _shooter + dir * 30.0, 0xFFFFFFFF)
	var r := sp.intersect_ray(q)
	if r.is_empty():
		print("BLOODSHOT miss")
		return
	var col: Node = r["collider"]
	var head := bool(col.get_meta("headshot", false))
	var t: Node = col
	while t != null and not t.has_method("take_damage"):
		t = t.get_parent()
	print("BLOODSHOT hit ", col.name, " head=", head, " target=", t.name if t else "none")
	if t != null:
		if head and t.has_method("take_hit_part"):
			t.call("take_hit_part", dmg, null, r["position"], r["normal"], true)
		else:
			t.call("take_damage", dmg, null, r["position"], r["normal"])
	VFX.spawn_blood(r["position"], r["normal"], dir, 1.6 if head else 1.0)

func _run() -> void:
	await _wait_real(1.5)
	# 1) Rumpftreffer in Zeitlupe (wie Geschoss-Kamera), Seitenansicht
	_look(Vector3(2.7, 1.4, -0.2), Vector3(0, 1.3, -0.6))
	await _wait_real(0.3)
	Engine.time_scale = 0.2
	_shoot(Vector3(0.0, 1.3, 0.0), 10.0)
	await _wait_real(0.12)
	await _snap("hit_spray_slowmo_a")
	await _wait_real(0.35)
	await _snap("hit_spray_slowmo_b")
	await _wait_real(0.6)
	await _snap("hit_spray_slowmo_c")
	Engine.time_scale = 1.0
	# 2) Schuetzensicht
	_look(_shooter + Vector3(0.2, 0.0, -5.0), Vector3(0, 1.3, 0))
	await _wait_real(1.0)
	_shoot(Vector3(0.12, 1.15, 0.0), 10.0)
	await _wait_real(0.06)
	await _snap("hit_spray_shooter_view")
	await _wait_real(0.12)
	await _snap("hit_spray_shooter_view_b")
	await _wait_real(1.5)
	# 2b) Entfernung ~25 m (soll dezent bleiben), Schuss leicht von der Seite
	_look(Vector3(6.0, 1.6, 24.0), Vector3(0, 1.3, 0))
	await _wait_real(0.5)
	_shoot(Vector3(-0.08, 1.25, 0.0), 10.0)
	await _wait_real(0.05)
	await _snap("hit_spray_far")
	await _wait_real(1.5)
	# 3) Kopftreffer (staerker), Seitenansicht in Zeitlupe
	_look(Vector3(-2.2, 1.7, 1.0), Vector3(0, 1.6, -0.4))
	await _wait_real(0.3)
	Engine.time_scale = 0.25
	_shoot(Vector3(0.0, 1.66, 0.0), 300.0)
	await _wait_real(0.18)
	await _snap("headshot_spray_slowmo")
	Engine.time_scale = 1.0
	await _wait_real(1.5)
	# 4) Wand hinter dem Ziel
	_look(Vector3(1.6, 1.5, 0.6), Vector3(0, 1.2, -2.35))
	await _wait_real(0.3)
	await _snap("wall_decal")
	# 5) Lache unter dem Toten (Zeit raffen)
	Engine.time_scale = 6.0
	await _wait_real(5.0)
	Engine.time_scale = 1.0
	_look(Vector3(1.8, 1.6, 1.8), Vector3(0, 0.0, -0.3))
	await _wait_real(0.3)
	await _snap("body_pool")
	print("BLOODSHOT decals=", VFX.blood.call("live_decals"), " fx=", VFX.blood.call("live_fx"),
		" hits=", VFX.blood.get("stat_hits"), " merged=", VFX.blood.get("stat_merged"))
	get_tree().quit()

## Last-Test: 3 s Grundlast, dann 5 s lang 12 Treffer/s an zufaelligen Punkten (inkl. Wand-Decals).
func _run_perf() -> void:
	_enemy.queue_free()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_look(Vector3(0, 1.6, 4.0), Vector3(0, 1.2, 0))
	await _wait_real(2.0)
	var base := await _measure(3.0, false)
	var load := await _measure(5.0, true)
	print("BLOODPERF base_ms=%.2f load_ms=%.2f fx=%d decals=%d" % [base, load, VFX.blood.call("live_fx"), VFX.blood.call("live_decals")])
	get_tree().quit()

func _measure(sec: float, spawn: bool) -> float:
	var t0 := Time.get_ticks_usec()
	var frames := 0
	var acc := 0.0
	while (Time.get_ticks_usec() - t0) / 1000000.0 < sec:
		var f0 := Time.get_ticks_usec()
		if spawn and frames % 5 == 0:
			var p := Vector3(randf_range(-1.5, 1.5), randf_range(0.8, 1.8), randf_range(-0.5, 0.5))
			VFX.spawn_blood(p, Vector3.BACK, Vector3(randf_range(-0.2, 0.2), randf_range(-0.1, 0.05), -1.0), 1.0 + randf())
		await get_tree().process_frame
		acc += (Time.get_ticks_usec() - f0) / 1000.0
		frames += 1
	return acc / maxf(frames, 1)
