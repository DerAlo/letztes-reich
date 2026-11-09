extends Node3D
## Nahaufnahmen fuer Rauch-Vorher/Nachher: laedt _vfx_showcase (liest dieselben User-Args) und
## speichert Screenshots zu festen Zeiten. Start:
## godot --path . --resolution 1920x1080 res://game/vfx/_smoke_shot.tscn -- --fires --cam=a --times=4,8 --out=captures/fx2/smoke_pre_fires
## Optional --burst=N: zusaetzlich N aufeinanderfolgende Frames je Zeitpunkt (Flimmer-Test).

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	add_child((load("res://game/vfx/_vfx_showcase.tscn") as PackedScene).instantiate())
	var out := str(Game.arg("out", "captures/fx2/smoke"))
	var times := str(Game.arg("times", "2")).split(",")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	var t0 := Time.get_ticks_msec()
	for ts in times:
		var t := float(ts)
		var f0 := Engine.get_frames_drawn()
		var m0 := Time.get_ticks_usec()
		while (Time.get_ticks_msec() - t0) / 1000.0 < t:
			await get_tree().process_frame
		var fps := float(Engine.get_frames_drawn() - f0) / maxf((Time.get_ticks_usec() - m0) / 1000000.0, 0.001)
		await RenderingServer.frame_post_draw
		var path := ProjectSettings.globalize_path("res://%s_t%s.png" % [out, ts])
		get_viewport().get_texture().get_image().save_png(path)
		print("SMOKESHOT t=%s fps=%.1f %s" % [ts, fps, path])
		# --burst=N: N direkt aufeinanderfolgende Frames (Flimmer-Test), erst im Speicher, dann speichern
		var burst := int(Game.arg("burst", 0))
		if burst > 0:
			var imgs: Array[Image] = []
			for i in burst:
				await RenderingServer.frame_post_draw
				imgs.append(get_viewport().get_texture().get_image())
			for i in imgs.size():
				imgs[i].save_png(ProjectSettings.globalize_path("res://%s_t%s_b%02d.png" % [out, ts, i]))
	get_tree().quit()
