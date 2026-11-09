extends Node3D
## Performance-Test fuer Rauch/VFX im echten Level (ohne Player/Gegner, mit Artillerie).
## Fliegt mehrere Kamerapositionen ab und druckt FPS + Draw Calls. Ausloesen von Explosionen alle 2 s.
## Start (Fenster): godot --path . res://game/vfx/_vfx_perf.tscn -- [--seconds=6]

const VIEWS := [
	[Vector3(0.5, 1.7, 6.0), Vector3(0, 2.5, -60.0)],
	[Vector3(-2.0, 1.7, -35.0), Vector3(1.0, 3.0, -100.0)],
	[Vector3(3.0, 1.7, -50.0), Vector3(-10.0, 7.0, -72.0)],
	[Vector3(4.0, 2.0, -62.0), Vector3(6.2, 3.0, -73.0)],
	[Vector3(0.0, 1.7, -130.0), Vector3(0.0, 3.0, -190.0)],
	[Vector3(0.0, 40.0, 20.0), Vector3(0.0, 0.0, -80.0)],
]

var _cam: Camera3D

func _ready() -> void:
	var level := (load("res://game/levels/test_range.tscn") as PackedScene).instantiate()
	level.set("spawn_player", false)
	level.set("spawn_enemies", false)
	add_child(level)
	_cam = Camera3D.new()
	_cam.fov = 70
	_cam.far = 700
	add_child(_cam)
	_cam.make_current()
	_run()

func _run() -> void:
	var secs := float(Game.arg("seconds", 6.0))
	await get_tree().create_timer(3.0).timeout
	var all: Array[float] = []
	var only := int(Game.arg("view", -1))
	var upto := int(Game.arg("upto", 99))
	if Game.arg("nosmoke", false):
		_hide_smoke(self)
	for i in VIEWS.size():
		if (only >= 0 and i != only) or i > upto:
			continue
		var v: Array = VIEWS[i]
		_cam.look_at_from_position(v[0], v[1])
		await get_tree().create_timer(1.0).timeout
		var f0 := Engine.get_frames_drawn()
		var t0 := Time.get_ticks_usec()
		var worst := 0.0
		var last := t0
		var dc := 0
		var n := 0
		while Time.get_ticks_usec() - t0 < int(secs * 1e6):
			if n % 120 == 60 and not Game.arg("noexpl", false):
				var fwd := -_cam.global_transform.basis.z
				VFX.spawn_explosion(_cam.global_position + fwd * 25.0 + Vector3(0, -1.5, 0), 1.6)
			await get_tree().process_frame
			if n % 30 == 0 and Game.arg("nosmoke", false):
				_hide_smoke(get_tree().root)
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			dc = maxi(dc, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			n += 1
		var fps := (Engine.get_frames_drawn() - f0) / ((Time.get_ticks_usec() - t0) / 1e6)
		all.append(fps)
		if Game.arg("shot", false):
			get_viewport().get_texture().get_image().save_png("res://captures/perf_view_%d.png" % i)
		var sfx_b := AudioServer.get_bus_index("SFX")
		var amb_b := AudioServer.get_bus_index("Ambient")
		print("AUDIO buses=%d sfx_peak=%.1f dB amb_peak=%.1f dB" % [AudioServer.bus_count, AudioServer.get_bus_peak_volume_left_db(sfx_b, 0) if sfx_b >= 0 else -999.0, AudioServer.get_bus_peak_volume_left_db(amb_b, 0) if amb_b >= 0 else -999.0])
		print("PERF view=%d avg_fps=%.1f worst_frame_ms=%.1f max_draw_calls=%d" % [i, fps, worst, dc])
	var mn := all.min() as float
	var avg := 0.0
	for f in all:
		avg += f
	print("PERF summary avg=%.1f min_view=%.1f" % [avg / all.size(), mn])
	get_tree().quit()

func _hide_smoke(n: Node) -> void:
	if n is GPUParticles3D:
		var m := (n as GPUParticles3D).material_override
		if m is ShaderMaterial and str((m as ShaderMaterial).shader.resource_path).contains("smoke"):
			(n as GPUParticles3D).visible = false
	for c in n.get_children():
		_hide_smoke(c)
