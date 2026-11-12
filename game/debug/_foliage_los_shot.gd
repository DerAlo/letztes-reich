extends Node3D
## Debug: Laub-Sichtlinie pruefen. Laedt baltic_night ohne Spieler, stellt je Ansicht einen Schuetzen
## in den Wald, schaut aus Spieler-Augenhoehe auf ihn und schreibt Laubtiefe/Grenze/Ergebnis ins Bild.
## Start: godot --path . --resolution 1600x900 res://game/debug/_foliage_los_shot.tscn -- --out=captures/forest_los/shot

const FoliageSight = preload("res://game/enemies/foliage_sight.gd")
const RIFLEMAN = preload("res://game/enemies/rifleman.tscn")

## [Kamera (Spielerauge), Fuss des Schuetzen]
const VIEWS: Array = [
	[Vector3(0.0, 1.7, -70.0), Vector3(-6.0, 0.05, -78.0)],
	[Vector3(0.0, 1.7, -70.0), Vector3(-3.0, 0.05, -82.0)],
	[Vector3(-1.0, 1.7, -82.0), Vector3(6.5, 0.05, -88.0)],
	[Vector3(-1.0, 1.7, -82.0), Vector3(12.0, 0.05, -90.0)],
	[Vector3(1.0, 1.7, -95.0), Vector3(-6.5, 0.05, -101.0)],
	[Vector3(1.0, 1.7, -95.0), Vector3(7.0, 0.05, -106.0)],
	[Vector3(0.5, 1.7, -40.0), Vector3(-4.0, 0.05, -62.6)],
	[Vector3(0.5, 1.7, -50.0), Vector3(8.0, 0.05, -72.0)],
	[Vector3(0.0, 1.7, -120.0), Vector3(0.5, 0.05, -125.0)],
	# Welle 1 nach Verlegung an den Waldrand (baltic_night.gd)
	[Vector3(0.0, 1.7, -64.0), Vector3(-4.4, 0.05, -80.0)],
	[Vector3(-0.5, 1.7, -74.0), Vector3(3.2, 0.05, -88.5)],
	[Vector3(-0.5, 1.7, -78.0), Vector3(-4.6, 0.05, -93.6)],
	[Vector3(0.6, 1.7, -90.0), Vector3(3.6, 0.05, -103.8)],
]

func _ready() -> void:
	if Game.arg("profile", false):
		_profile()
		get_tree().quit()
		return
	var out := str(Game.arg("out", "captures/forest_los/shot"))
	var lv := (load("res://game/levels/baltic_night.tscn") as PackedScene).instantiate()
	lv.set("spawn_player", false)
	lv.set("spawn_enemies", false)
	lv.set("ambient_artillery", false)
	add_child(lv)
	var cam := Camera3D.new()
	cam.fov = float(Game.arg("fov", 70.0))
	cam.far = 900
	add_child(cam)
	cam.make_current()
	var cl := CanvasLayer.new()
	add_child(cl)
	var lab := Label.new()
	lab.position = Vector2(20, 20)
	lab.add_theme_font_size_override("font_size", 26)
	lab.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	lab.add_theme_color_override("font_outline_color", Color.BLACK)
	lab.add_theme_constant_override("outline_size", 6)
	cl.add_child(lab)
	var t0 := Time.get_ticks_msec()
	while lv.has_method("is_level_ready") and not lv.call("is_level_ready") and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out.get_base_dir()))
	var dummy: Node3D = null
	var views: Array = VIEWS.duplicate()
	var pick: Array = range(VIEWS.size())
	if str(Game.arg("views", "")) != "":
		pick = Array(str(Game.arg("views", "")).split(",")).map(func(x): return int(x))
	# --viewlist="kx,kz,sx,sz;..." : eigene Ansichten (Kamera x/z auf Augenhoehe, Schuetzenfuss x/z)
	if str(Game.arg("viewlist", "")) != "":
		views.clear()
		for e in str(Game.arg("viewlist", "")).split(";"):
			var f := e.split(",")
			views.append([Vector3(float(f[0]), 1.7, float(f[1])), Vector3(float(f[2]), 0.05, float(f[3]))])
		pick = range(views.size())
	# --diff=1 : zusaetzlich Bild ohne Schuetzen, Pixelunterschied = sichtbarer Anteil des Schuetzen
	var diff := str(Game.arg("diff", "0")) == "1"
	for i in pick:
		var v: Array = views[i]
		if dummy != null:
			dummy.queue_free()
			await get_tree().process_frame
		dummy = RIFLEMAN.instantiate()
		add_child(dummy)
		dummy.global_position = v[1]
		dummy.look_at(Vector3(v[0].x, v[1].y, v[0].z), Vector3.UP)
		dummy.set("sight_range", 0.0)
		var eye: Vector3 = v[1] + Vector3.UP * 1.6
		cam.look_at_from_position(v[0], eye)
		var dep := FoliageSight.depth(get_tree(), eye, v[0])
		var dist: float = eye.distance_to(v[0])
		var lim := FoliageSight.limit_for(dist)
		var res := "VERDECKT (Gegner sieht nicht)" if dep > lim else "SICHT FREI"
		lab.text = "Ansicht %d  Abstand %.1f m  Laubtiefe %.2f / Grenze %.2f  ->  %s" % [i, dist, dep, lim, res]
		print("FOLIAGESHOT view=%d dist=%.1f depth=%.2f limit=%.2f blocked=%d" % [i, dist, dep, lim, int(dep > lim)])
		await get_tree().create_timer(float(Game.arg("wait", 2.0))).timeout
		print("FOLIAGESHOT dummy pos=%s children=%d visible=%s" % [str(dummy.global_position), dummy.get_child_count(), str(dummy.is_visible_in_tree())])
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if str(Game.arg("saveshot", "1")) == "1":
			img.save_png(ProjectSettings.globalize_path("res://%s_%d.png" % [out, i]))
		if diff:
			# Schuetzen magenta/unbeleuchtet einfaerben und sichtbare Pixel zaehlen (reine Verdeckung, ohne Licht)
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = Color(1, 0, 1)
			mat.disable_fog = true
			for gi in dummy.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = mat
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img0 := get_viewport().get_texture().get_image()
			if str(Game.arg("savemask", "1")) == "1":
				img0.save_png(ProjectSettings.globalize_path("res://%s_%d_mask.png" % [out, i]))
			var n := 0
			var cy0 := img0.get_height() / 2
			var cx0 := img0.get_width() / 2
			for y in range(maxi(0, cy0 - 260), mini(img0.get_height(), cy0 + 260)):
				for x in range(maxi(0, cx0 - 160), mini(img0.get_width(), cx0 + 160)):
					var c := img0.get_pixel(x, y)
					if c.r - c.g > 0.3 and c.b - c.g > 0.3:
						n += 1
			# Referenz: gleicher Schuetze ohne Wald waere ca. (Pixel je m)^2 * 1.8 m * 0.5 m
			var ppm: float = img0.get_height() / (2.0 * dist * tan(deg_to_rad(cam.fov * 0.5)))
			print("FOLIAGEDIFF view=%d visible_px=%d full_px~%d frac=%.2f" % [i, n, int(ppm * ppm * 0.9), n / maxf(ppm * ppm * 0.9, 1.0)])
	get_tree().quit()

## Kronenprofil der echten Fichten-Meshes: Radius (90%-Quantil der Kartenflaeche) je Hoehenband.
func _profile() -> void:
	const NP = preload("res://game/levels/night_props.gd")
	for v in 3:
		var rng := RandomNumberGenerator.new()
		rng.seed = 811 + v * 37
		var h := 12.0 * (0.9 + 0.1 * v)
		var m: ArrayMesh = NP.spruce_mesh(rng, h)
		var verts: PackedVector3Array = m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var idx_v = m.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = idx_v if idx_v != null else PackedInt32Array()
		var bands: Dictionary = {}
		# Dreiecke flaechig abtasten
		var i := 0
		while i + 2 < (idx.size() if idx.size() > 0 else verts.size()):
			var a := verts[idx[i] if idx.size() > 0 else i]
			var b := verts[idx[i + 1] if idx.size() > 0 else i + 1]
			var c := verts[idx[i + 2] if idx.size() > 0 else i + 2]
			for k in 12:
				var u := randf()
				var w := randf()
				if u + w > 1.0:
					u = 1.0 - u
					w = 1.0 - w
				var p := a + (b - a) * u + (c - a) * w
				var key := int(floor(p.y / 0.5))
				if not bands.has(key):
					bands[key] = []
				bands[key].append(Vector2(p.x, p.z).length())
			i += 3
		var line := "PROFILE h=%.1f:" % h
		for key in range(0, 10):
			if bands.has(key):
				var arr: Array = bands[key]
				arr.sort()
				line += " y%.1f:r50=%.2f,r90=%.2f,n=%d" % [key * 0.5, arr[int(arr.size() * 0.5)], arr[int(arr.size() * 0.9)], arr.size()]
		print(line)
