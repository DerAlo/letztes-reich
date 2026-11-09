extends Node3D
## Deckungstest: Spieler steht direkt hinter einem Wrack, ein Gegner steht sichtbar dahinter.
## Der Spieler zielt knapp ueber das Wrack auf den Gegner und feuert (echte Waffe, Kamera-Hitscan).
## Erwartung: Treffer kommen an (Events.enemy_damaged), statt in einer unsichtbaren Box-Ecke zu haengen.
## Start: godot --path . res://game/levels/_test_cover.tscn [-- --no-propfit]   (headless geht auch)
## Ausgabe: COVERTEST ... / COVERTEST result=PASS|FAIL

# [Level, Prop-Position (ungefaehr), Richtung Spieler->Gegner (XZ), geduckt]
const CASES := [
	["test_range", Vector3(5.2, 0, -62.0), Vector3(0, 0, -1), false],    # Abdeckplanen-Auto (GLTF)
	["test_range", Vector3(-3.0, 0, -112.0), Vector3(0, 0, -1), false],  # ausgebranntes Auto (BoxBatch)
	["test_range", Vector3(5.0, 0, -146.0), Vector3(0, 0, -1), true],    # Sandsackwall
	["test_range", Vector3(2.0, 0, -41.1), Vector3(0, 0, -1), true],     # Panzersperre
]

var _hits := 0
var _shots := 0

func _ready() -> void:
	var shot_dir := str(Game.arg("shots", ""))
	var total_pass := 0
	Events.enemy_damaged.connect(func(_e: Node, _a: float) -> void: _hits += 1)
	Events.weapon_fired.connect(func(_w: Node) -> void: _shots += 1)
	for ci in CASES.size():
		var c: Array = CASES[ci]
		var level := (load("res://game/levels/%s.tscn" % c[0]) as PackedScene).instantiate()
		level.set("spawn_player", true)
		level.set("spawn_enemies", false)
		level.set("ambient_artillery", false)
		add_child(level)
		var t0 := Time.get_ticks_msec()
		while not level.call("is_level_ready") and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().process_frame
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var body := _nearest_prop(level, c[1])
		if player == null or body == null:
			print("COVERTEST case=%d FEHLER player=%s body=%s" % [ci, str(player), str(body)])
			level.queue_free()
			await get_tree().process_frame
			continue
		var box := _visual_aabb(body)
		var dir: Vector3 = (c[2] as Vector3).normalized()
		var center := box.get_center()
		# Spieler 0.7 m vor der Wrackkante (auf der Startseite), Gegner 4 m hinter dem Wrack
		var near_d := absf(dir.dot(box.size)) * 0.5 + 0.7
		var ppos := Vector3(center.x, 0.05, center.z) - dir * near_d
		var epos := Vector3(center.x, 0.05, center.z) + dir * (absf(dir.dot(box.size)) * 0.5 + 4.0)
		player.set("external_input", true)
		player.global_position = ppos
		if "velocity" in player:
			player.set("velocity", Vector3.ZERO)
		var enemy := (load("res://game/enemies/rifleman.tscn") as PackedScene).instantiate() as Node3D
		level.add_child(enemy)
		enemy.global_position = epos
		for i in 20:
			await get_tree().physics_frame
		enemy.global_position = epos   # nicht weglaufen lassen
		var cam: Camera3D = player.call("get_camera")
		var ext: Dictionary = player.get("ext")
		ext["crouch"] = bool(c[3])
		player.call("look_at_point", epos + Vector3(0, 1.4, 0))
		for i in 30:
			await get_tree().physics_frame
		# Schusslinie suchen, die die alte (grobe) Box schneidet, die sichtbare Geometrie aber frei laesst:
		# genau der Fall "Kugel bleibt in unsichtbarer Box haengen".
		var eye := cam.global_position
		var faces := _visual_faces(body)
		var boxes := _old_boxes(body)
		var side := dir.cross(Vector3.UP).normalized()
		var space0 := player.get_world_3d().direct_space_state
		var excl: Array[RID] = [body.get_rid(), (player as CollisionObject3D).get_rid(), (enemy as CollisionObject3D).get_rid()]
		var mbn := body.get_node_or_null("MoveBlock") as CollisionObject3D
		if mbn != null:
			excl.append(mbn.get_rid())
		var aim := Vector3.INF
		var best_cross := 0.0
		var blockers: Array = []
		for si in 33:
			var lat := -4.0 + si * 0.25
			for hi in 9:
				var h := 0.5 + hi * 0.15
				var tgt := epos + side * lat + Vector3(0, h, 0)
				if _ray_hits_faces(eye, tgt, faces):
					continue
				# Linie darf ausser dem Prop nichts anderes treffen (Boden, Nachbar-Props)
				var oq := PhysicsRayQueryParameters3D.create(eye, tgt, 1)
				oq.exclude = excl
				var orr := space0.intersect_ray(oq)
				if not orr.is_empty():
					var bn := orr.collider as Node
					var key := "%s<%s @%s" % [str(bn.name), str(bn.get_parent().name), str((orr.position as Vector3).snapped(Vector3.ONE * 0.1))]
					if blockers.size() < 4 and not blockers.has(key):
						blockers.append(key)
					continue
				var cross := _ray_box_len(eye, tgt, boxes)
				if cross > best_cross:
					best_cross = cross
					aim = tgt
		if aim == Vector3.INF:
			print("COVERTEST case=%d keine passende Schusslinie gefunden (boxes=%d faces=%d auge=%.2f) blocker=%s" % [ci, boxes.size(), faces.size() / 3, eye.y, str(blockers)])
			level.queue_free()
			await get_tree().process_frame
			continue
		var aim_h := aim.y - epos.y
		epos = Vector3(aim.x, epos.y, aim.z)
		enemy.global_position = epos
		player.call("look_at_point", aim)
		await get_tree().physics_frame
		# Sichtlinie: welche Form liegt zuerst zwischen Kamera und Ziel?
		var space := player.get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam.global_position, aim, 1 | 2 | 4)
		q.collide_with_areas = true
		q.exclude = [(player as CollisionObject3D).get_rid()]
		var r := space.intersect_ray(q)
		var first_hit := "nichts"
		if not r.is_empty():
			var cn := r.collider as Node
			first_hit = "%s (%s)" % [str(cn.name), "Gegner" if cn.is_in_group("enemy") or cn.get_parent().is_in_group("enemy") else "Welt"]
		var top_y := box.end.y
		_hits = 0
		_shots = 0
		for i in 50:   # ~0.8 s Dauerfeuer, Ziel jeden Frame nachfuehren
			if is_instance_valid(enemy):
				enemy.global_position = epos
			player.call("look_at_point", aim)
			ext["fire"] = true
			await get_tree().physics_frame
		ext["fire"] = false
		ext["crouch"] = false
		if shot_dir != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://%s_case%d.png" % [shot_dir, ci]))
		var ok := _hits > 0
		if ok:
			total_pass += 1
		print("COVERTEST case=%d prop=%s wrack_oben=%.2f m augen=%.2f m ziel=%.2f m alte_box_im_strahl=%.2f m erster_treffer_im_strahl=%s schuesse=%d treffer=%d -> %s" % [
			ci, str(body.name), top_y, cam.global_position.y, aim_h, best_cross, first_hit, _shots, _hits, "PASS" if ok else "FAIL"])
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	print("COVERTEST result=%s (%d/%d) propfit=%s" % ["PASS" if total_pass == CASES.size() else "FAIL", total_pass, CASES.size(), str(not Game.arg("no-propfit", false))])
	get_tree().quit()

func _visual_faces(b: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := mi.global_transform
		for v in mi.mesh.get_faces():
			out.append(xf * v)
	return out

## Alte, grobe Boxen: bei aktivem PropCollision im Kind "MoveBlock", sonst direkt am Body.
func _old_boxes(b: Node3D) -> Array:
	var holder: Node = b.get_node_or_null("MoveBlock")
	if holder == null:
		holder = b
	var out: Array = []
	for c in holder.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			out.append([(c as CollisionShape3D).global_transform, ((c as CollisionShape3D).shape as BoxShape3D).size])
	return out

func _ray_hits_faces(a: Vector3, b: Vector3, f: PackedVector3Array) -> bool:
	var d := b - a
	for i in range(0, f.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(a, b, f[i], f[i + 1], f[i + 2])
		if hit != null:
			return true
	return false

## Laenge des Strahlstuecks innerhalb der Boxen (Slab-Test im Box-Raum).
func _ray_box_len(a: Vector3, b: Vector3, boxes: Array) -> float:
	var total := 0.0
	for bx: Array in boxes:
		var inv := (bx[0] as Transform3D).affine_inverse()
		var la := inv * a
		var lb := inv * b
		var half: Vector3 = (bx[1] as Vector3) * 0.5
		var d := lb - la
		var t0 := 0.0
		var t1 := 1.0
		var ok := true
		for k in 3:
			if absf(d[k]) < 1e-6:
				if la[k] < -half[k] or la[k] > half[k]:
					ok = false
					break
			else:
				var ta := (-half[k] - la[k]) / d[k]
				var tb := (half[k] - la[k]) / d[k]
				t0 = maxf(t0, minf(ta, tb))
				t1 = minf(t1, maxf(ta, tb))
		if ok and t1 > t0:
			total += (t1 - t0) * d.length()
	return total

func _nearest_prop(level: Node, p: Vector3) -> StaticBody3D:
	var best: StaticBody3D = null
	var bd := 3.0
	for n in level.find_children("*", "StaticBody3D", true, false):
		var b := n as StaticBody3D
		if b.name == "MoveBlock" or (b.collision_layer & 1) == 0:
			continue
		if _visual_aabb(b).size == Vector3.ZERO:
			continue
		var d := Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length()
		if d < bd:
			bd = d
			best = b
	return best

func _visual_aabb(b: Node3D) -> AABB:
	var res := AABB()
	var first := true
	for n in b.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.mesh.get_aabb()
		res = a if first else res.merge(a)
		first = false
	return res
