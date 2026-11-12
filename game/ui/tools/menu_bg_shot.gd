extends Node3D
## Werkzeug: Hintergrundbilder fuers Hauptmenue aus einem Level rendern (ohne Spieler/Gegner/Overlays).
## Start: godot --path . --resolution 1920x1080 res://game/ui/tools/menu_bg_shot.tscn -- --level=funkturm
##        --out=captures/main_menu/bg/funkturm [--cams=px,py,pz,tx,ty,tz;...] [--fov=60] [--settle=3]
## Ohne --cams: Ansichten rund um player_spawn und level_end (zum Suchen guter Blickwinkel).

var _cam: Camera3D

func _ready() -> void:
	var lname := str(Game.arg("level", "berlin"))
	var out := str(Game.arg("out", "captures/main_menu/bg/" + lname))
	var settle := float(Game.arg("settle", 3.0))
	var lvl := (load("res://game/levels/%s.tscn" % lname) as PackedScene).instantiate()
	lvl.set("spawn_player", false)
	lvl.set("spawn_enemies", false)
	lvl.set("ambient_artillery", false)
	add_child(lvl)
	_cam = Camera3D.new()
	_cam.fov = float(Game.arg("fov", 62.0))
	_cam.far = 1500
	add_child(_cam)
	_cam.make_current()
	var t0 := Time.get_ticks_msec()
	while lvl.has_method("is_level_ready") and not lvl.call("is_level_ready") and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	_hide_overlays(get_tree().root)
	for p in get_tree().get_nodes_in_group("player"):   # Spielerfahrzeug (Kamera + HUD) entfernen
		p.queue_free()
	var views := {}
	var cams := str(Game.arg("cams", ""))
	if cams != "":
		var parts := cams.split(";")
		for i in parts.size():
			var f := parts[i].split(",")
			if f.size() == 6:
				views["c%d" % i] = [Vector3(float(f[0]), float(f[1]), float(f[2])), Vector3(float(f[3]), float(f[4]), float(f[5]))]
	else:
		var sp := get_tree().get_first_node_in_group("player_spawn") as Node3D
		var en := get_tree().get_first_node_in_group("level_end") as Node3D
		var a := sp.global_position if sp != null else Vector3.ZERO
		var b := en.global_position if en != null else a + Vector3(0, 0, -100)
		var d := (b - a)
		d.y = 0
		d = d.normalized() if d.length() > 1.0 else Vector3.FORWARD
		views["s_fwd"] = [a + Vector3(0, 1.7, 0), a + d * 60.0 + Vector3(0, 3, 0)]
		views["s_high"] = [a + Vector3(0, 12, 0) - d * 10.0, a + d * 80.0]
		views["m_fwd"] = [a.lerp(b, 0.5) + Vector3(0, 1.7, 0), b + Vector3(0, 4, 0)]
		views["e_back"] = [b + Vector3(0, 2.0, 0), a.lerp(b, 0.6) + Vector3(0, 4, 0)]
		views["e_fwd"] = [b + Vector3(0, 1.7, 0) - d * 25.0, b + d * 40.0 + Vector3(0, 6, 0)]
		print("BGSHOT spawn=%s end=%s" % [a, b])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	for k in views:
		var v: Array = views[k]
		_cam.look_at_from_position(v[0], v[1])
		await get_tree().create_timer(settle).timeout
		_hide_overlays(get_tree().root)
		_cam.make_current()   # Level-eigene Kameras (z. B. Panzer in spreebogen) uebernehmen sonst
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://%s_%s.png" % [out, k])
		img.save_png(path)
		print("BGSHOT view=%s cam=%s shot=%s" % [k, str(v), path])
	get_tree().quit()


func _process(_d: float) -> void:
	if _cam != null:
		_hide_overlays(get_tree().root)
		for p in get_tree().get_nodes_in_group("player"):
			if not p.is_queued_for_deletion():
				p.queue_free()
		if not _cam.current:
			_cam.make_current()


## FPS-Overlay, HUD u. ae. (CanvasLayer) ausblenden.
func _hide_overlays(n: Node) -> void:
	for c in n.get_children():
		if c is CanvasLayer:
			(c as CanvasLayer).visible = false
		_hide_overlays(c)
