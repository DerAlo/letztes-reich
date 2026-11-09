extends RefCounted
## Fassaden-Generator: Haeuserzeilen aus Pfeilern, Bruestungen, Stuerzen und Geschossplatten,
## mit Kriegsschaeden (ausgeschossene Fenster, fehlende Felder, zackige Oberkanten).
## Ausserdem die vorgeschnittene Fassade (RigidBody-Bloecke) fuer den Einsturz.
## Optik ueber facade_kit.gd: eingelassene Fenster mit Laibung, Rahmen, Sprossen, Bank und
## Interior-Mapping-Glas, Fensterfaschen/Stuerze, Fallrohre, Rinnen, Dachaufbauten, Einschuss-
## und Russ-Decals. Kollision unveraendert (eine Box pro Feld).

const Geo = preload("res://game/levels/level_geo.gd")
const FK = preload("res://game/levels/facade_kit.gd")

const FRONT_X := 10.0      ## Abstand der Fassadenflucht von der Strassenachse
const FLOOR_H := 3.5
const WALL_T := 0.7
const WIN_W := 1.7
const REVEAL := 0.22       ## Laibungstiefe bis zur Glasebene

## Wandmaterial; die Variante haengt deterministisch von brick/tint ab, damit Einsturzbloecke
## dasselbe Material wie ihr Haus bekommen.
static func wall_variant(brick: bool, tint: Color) -> String:
	var hsh := absi(hash(tint.to_html()))
	if brick:
		return ["brick_red", "brick_old", "plaster_broken"][hsh % 3]
	return ["plaster", "concrete", "plaster_broken", "concrete_old"][hsh % 4]

static func wall_mat(brick: bool, tint: Color, soot: float = 0.0) -> ShaderMaterial:
	var v := wall_variant(brick, tint)
	var t := tint
	if v == "brick_red":
		t = tint.lerp(Color(0.9, 0.85, 0.82), 0.5)
	return FK.facade_mat(v, t, {"grime_amount": 0.6, "grime_height": 2.0, "soot": soot, "streaks": 0.45})

static func trim_mat() -> ShaderMaterial:
	return FK.facade_mat("concrete_old", Color(0.66, 0.64, 0.6), {"grime_amount": 0.45, "streaks": 0.5, "variation": 0.12})

static func mass_mat() -> StandardMaterial3D:
	return Geo.mat("concrete_wall_008", Color(0.16, 0.15, 0.14), 0.3, 1.0)

static func glow_mat() -> StandardMaterial3D:
	return Geo.flat(Color(0.06, 0.04, 0.03), 0.9, 0.0, Color(1.0, 0.52, 0.2), 2.4)

## Materialien der Detail-Teile (Schluessel in FK.Parts).
static func part_mats() -> Dictionary:
	return {
		"frame_dark": FK.frame_mat(Color(0.07, 0.065, 0.06)),
		"frame_white": FK.frame_mat(Color(0.55, 0.54, 0.5)),
		"frame_brown": FK.frame_mat(Color(0.16, 0.1, 0.06)),
		"sill": Geo.flat(Color(0.3, 0.3, 0.3), 0.5, 0.5),
		"metal": FK.metal_mat(),
		"zinc": Geo.flat(Color(0.34, 0.35, 0.36), 0.45, 0.7),
		"trim": trim_mat(),
		"brick": FK.facade_mat("brick_old", Color(0.75, 0.62, 0.55), {"grime_amount": 0.0, "soot": 0.25}),
		"wood": Geo.mat("weathered_planks", Color(0.55, 0.5, 0.45), 0.6, 1.0) if ResourceLoader.exists("res://assets/textures/weathered_planks/diffuse.jpg") else Geo.flat(Color(0.25, 0.2, 0.15), 0.9),
		"shutter": Geo.mat("rusty_metal_02", Color(0.46, 0.47, 0.46), 1.6, 0.85, 0.5),
	}

## Ein Wandfeld (eine Achse x Ein Geschoss). c = absolute Feldmitte, off wird von allen
## Positionen abgezogen (fuer Bloecke, deren Mesh um den Ursprung liegt).
## mode: 0 Fenster, 1 ausgeschossen (kein Sturz/Bruestung), 2 Wand fehlt, 3 geschlossen
## kit (optional): {"parts": FK.Parts, "wins": FK.WindowBatch, "frame": String, "style": String,
##   "surround": int (0 nichts, 1 Sturz, 2 Fasche), "light": float, "warm": float, "seed": float, "shop": int}
static func cell(wall: Geo.BoxBatch, trim: Geo.BoxBatch, side: int, c: Vector3, off: Vector3, wb: float, ground: bool, mode: int, deco: int = 0, kit: Dictionary = {}) -> void:
	var cx := c.x - off.x
	var cy := c.y - off.y
	var cz := c.z - off.z
	var n := Vector3(-side, 0.0, 0.0)
	var outer_x := cx - side * WALL_T / 2.0
	var has_kit := kit.has("parts")
	var parts: FK.Parts = kit.get("parts")
	var wins: FK.WindowBatch = kit.get("wins")
	var seed_v: float = kit.get("seed", 0.0)
	# Geschossplatte oben (leicht auskragend) und Sockel
	trim.add(Vector3(cx + side * 0.1, cy + FLOOR_H / 2.0 - 0.15, cz), Vector3(WALL_T + 0.2, 0.3, wb + 0.02))
	if ground:
		trim.add(Vector3(cx + side * 0.06, cy - FLOOR_H / 2.0 + 0.3, cz), Vector3(WALL_T + 0.12, 0.6, wb + 0.02))
	if mode == 2:
		if has_kit:
			# Fehlende Wand: Blick in den zerstoerten Raum
			FK.hole(wins, Vector3(outer_x, cy - 0.15, cz), n, wb - 0.1, FLOOR_H - 0.32, 0.05, seed_v)
		return
	if mode == 0 and not ground and deco > 0:
		if has_kit:
			FK.balcony(parts, Vector3(outer_x, cy, cz), n, cy - FLOOR_H / 2.0 + 0.83, WIN_W + 0.6, {"slab": "trim", "rail": "metal"}, seed_v > 0.6)
		else:
			# Balkon: Platte + Gelaender
			trim.add(Vector3(cx + side * (WALL_T / 2.0 + 0.5), cy - FLOOR_H / 2.0 + 0.9, cz), Vector3(1.0, 0.14, WIN_W + 0.6))
			trim.add(Vector3(cx + side * (WALL_T / 2.0 + 0.97), cy - FLOOR_H / 2.0 + 1.4, cz), Vector3(0.06, 0.07, WIN_W + 0.6))
			for k in 5:
				trim.add(Vector3(cx + side * (WALL_T / 2.0 + 0.97), cy - FLOOR_H / 2.0 + 1.15, cz - (WIN_W + 0.5) / 2.0 + k * (WIN_W + 0.5) / 4.0), Vector3(0.05, 0.5, 0.05))
	if mode == 3:
		wall.add(Vector3(cx, cy - 0.15, cz), Vector3(WALL_T, FLOOR_H - 0.3, wb))
		return
	var ww := WIN_W
	var sill := 0.5 if ground else 0.95
	var wh := 2.5 if ground else 1.9
	var pier := (wb - ww) / 2.0
	wall.add(Vector3(cx, cy - 0.15, cz - (ww + pier) / 2.0), Vector3(WALL_T, FLOOR_H - 0.3, pier))
	wall.add(Vector3(cx, cy - 0.15, cz + (ww + pier) / 2.0), Vector3(WALL_T, FLOOR_H - 0.3, pier))
	var y0 := cy - FLOOR_H / 2.0
	if mode == 0:
		wall.add(Vector3(cx, y0 + sill / 2.0, cz), Vector3(WALL_T, sill, ww))
		var top := sill + wh
		var lh := FLOOR_H - 0.3 - top
		if lh > 0.05:
			wall.add(Vector3(cx, y0 + top + lh / 2.0, cz), Vector3(WALL_T, lh, ww))
		if has_kit:
			var o := Vector3(outer_x, y0 + sill + wh / 2.0, cz)
			var R := FK.basis_for(n)
			var shop: int = kit.get("shop", 0)
			if ground and shop == 2:
				# Mit Brettern vernagelt
				FK.hole(wins, o, n, ww, wh, REVEAL + 0.1, seed_v)
				for k in 5:
					var yy := o.y - wh * 0.4 + k * wh * 0.2 + sin(seed_v * 40.0 + k) * 0.08
					parts.box("wood", Vector3(outer_x, yy, cz) + n * 0.03, Vector3(ww + 0.3, 0.22, 0.04), R * Basis(Vector3(0, 0, 1), sin(seed_v * 17.0 + k * 2.3) * 0.12))
			elif ground and shop == 3:
				# Rollladen halb oder ganz unten
				var down := 0.45 + fposmod(seed_v * 7.3, 0.55)
				FK.window(parts, wins, o, n, ww, wh, REVEAL, kit.get("frame", "frame_dark"), "sill", "shop", 0.0, 1.0, seed_v, false, false)
				var sh := wh * down
				parts.box("shutter", Vector3(outer_x, o.y + wh / 2.0 - sh / 2.0, cz) - n * 0.06, Vector3(ww, sh, 0.05), R)
				parts.box("shutter", Vector3(outer_x, o.y + wh / 2.0 + 0.15, cz) + n * 0.02, Vector3(ww + 0.1, 0.3, 0.2), R)
			else:
				var style: String = "shop" if ground else String(kit.get("style", "cross"))
				FK.window(parts, wins, o, n, ww, wh, REVEAL, kit.get("frame", "frame_dark"), "sill", style, kit.get("light", 0.0), kit.get("warm", 1.0), seed_v, bool(kit.get("broken", false)), not ground)
			var surround: int = kit.get("surround", 0)
			if not ground and surround == 1:
				parts.box("trim", Vector3(outer_x, o.y + wh / 2.0 + 0.11, cz) + n * 0.03, Vector3(ww + 0.3, 0.22, 0.06), R)
			elif not ground and surround == 2:
				parts.box("trim", Vector3(outer_x, o.y + wh / 2.0 + 0.07, cz) + n * 0.02, Vector3(ww + 0.28, 0.14, 0.04), R)
				parts.box("trim", Vector3(outer_x, o.y, cz + ww / 2.0 + 0.07) + n * 0.02, Vector3(0.14, wh, 0.04), R)
				parts.box("trim", Vector3(outer_x, o.y, cz - ww / 2.0 - 0.07) + n * 0.02, Vector3(0.14, wh, 0.04), R)
	elif mode == 1 and has_kit:
		FK.hole(wins, Vector3(outer_x, cy - 0.15, cz), n, ww, FLOOR_H - 0.3, 0.3, seed_v)

static func _add_mesh(parent: Node3D, b: Geo.BoxBatch, m: Material) -> void:
	var mesh := b.build()
	if mesh == null:
		return
	parent.add_child(Geo.mesh_node(mesh, m))

## Haeuserblock. side: -1 links, +1 rechts. z_near > z_far. Rueckgabe: Infos je Feld.
## opts: brick(bool), tint(Color), damage(0..1), collapse_bays(Vector2i: erstes, letztes Feld),
##       lit(float Anteil leuchtender Fenster)
static func build(parent: Node3D, side: int, z_near: float, z_far: float, floors: int, depth: float, opts: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var length := z_near - z_far
	var bays := maxi(1, roundi(length / 3.6))
	var wb := length / bays
	var damage: float = opts.get("damage", 0.4)
	var brick: bool = opts.get("brick", true)
	var tint: Color = opts.get("tint", Color(0.85, 0.75, 0.7))
	var collapse: Vector2i = opts.get("collapse_bays", Vector2i(-1, -2))
	var lit: float = opts.get("lit", 0.05)
	var wall := Geo.batch()
	var trim := Geo.batch()
	var mass := Geo.batch()
	var body := Geo.static_body()
	var info := {"bays": bays, "wb": wb, "floors": [], "zc": []}
	# Eigener Zufallsgenerator fuer die Optik, damit die Gameplay-Folge von rng unveraendert bleibt
	var vr := RandomNumberGenerator.new()
	vr.seed = hash(Vector3(side, z_near, z_far))
	var n := Vector3(-side, 0.0, 0.0)
	var parts := FK.Parts.new()
	var wins := FK.WindowBatch.new()
	var frame: String = ["frame_dark", "frame_white", "frame_brown", "frame_dark"][vr.randi() % 4]
	var style: String = ["cross", "t", "single", "cross"][vr.randi() % 4]
	var surround := vr.randi() % 3
	var shop_mode := vr.randi() % 4
	var decal_list: Array = []   # [pos, kind, size]
	for i in bays:
		var zc := z_near - (i + 0.5) * wb
		var nf := floors
		if rng.randf() < damage:
			nf = maxi(1, floors - rng.randi_range(1, 2))
		var is_collapse := i >= collapse.x and i <= collapse.y
		if is_collapse:
			nf = floors
		(info["floors"] as Array).append(nf)
		(info["zc"] as Array).append(zc)
		var h := nf * FLOOR_H
		var dx := depth - WALL_T
		mass.add(Vector3(side * (FRONT_X + WALL_T + dx / 2.0), h / 2.0, zc), Vector3(dx, h, wb))
		if is_collapse:
			# Erdgeschoss voll, darueber nur der Innenkern (die Fassade liegt als Bloecke davor)
			Geo.add_box_shape(body, Vector3(side * (FRONT_X + depth / 2.0), FLOOR_H / 2.0, zc), Vector3(depth, FLOOR_H, wb))
			Geo.add_box_shape(body, Vector3(side * (FRONT_X + WALL_T + dx / 2.0), FLOOR_H + (h - FLOOR_H) / 2.0, zc), Vector3(dx, h - FLOOR_H, wb))
		else:
			Geo.add_box_shape(body, Vector3(side * (FRONT_X + depth / 2.0), h / 2.0, zc), Vector3(depth, h, wb))
		for f in nf:
			if is_collapse and f >= 1:
				continue
			var c := Vector3(side * (FRONT_X + WALL_T / 2.0), f * FLOOR_H + FLOOR_H / 2.0, zc)
			var mode := 0
			var r := rng.randf()
			if r < damage * 0.14:
				mode = 2
			elif r < damage * 0.55:
				mode = 1
			elif r > 0.94:
				mode = 3
			var deco := 1 if rng.randf() < 0.09 else 0
			var light := 0.0
			if mode == 0 and f > 0 and rng.randf() < lit:
				light = vr.randf_range(0.55, 1.0)
			var shop := 0
			if f == 0:
				shop = shop_mode if vr.randf() < 0.6 else 0
			var kit := {"parts": parts, "wins": wins, "frame": frame, "style": style, "surround": surround,
				"light": light, "warm": 1.0 if vr.randf() < 0.7 else 0.15, "seed": vr.randf(),
				"broken": mode == 0 and vr.randf() < damage * 0.45, "shop": shop}
			cell(wall, trim, side, c, Vector3.ZERO, wb, f == 0, mode, deco, kit)
			var outer := Vector3(side * FRONT_X, c.y, zc)
			if mode == 1 or mode == 2:
				if vr.randf() < 0.55:
					decal_list.append([outer + Vector3(0, FLOOR_H / 2.0 - 0.3, 0), "soot", WIN_W * vr.randf_range(1.4, 2.0)])
			if vr.randf() < damage * 0.55:
				var pz := zc + (wb - WIN_W) * 0.25 * (1.0 if vr.randf() < 0.5 else -1.0) * 2.0
				decal_list.append([Vector3(outer.x, c.y + vr.randf_range(-1.0, 1.0), pz), "bullets", vr.randf_range(0.9, 1.6)])
		# Oberkante: zackig bei Schaden, sonst Kranzgesims
		var top_y := nf * FLOOR_H
		if nf < floors or rng.randf() < damage * 0.4:
			for k in rng.randi_range(1, 3):
				var tw := rng.randf_range(0.5, 1.3)
				var th := rng.randf_range(0.4, 2.2)
				var tz := zc + rng.randf_range(-wb / 2.0 + tw / 2.0, wb / 2.0 - tw / 2.0)
				wall.add(Vector3(side * (FRONT_X + WALL_T / 2.0), top_y + th / 2.0 - 0.15, tz), Vector3(WALL_T * rng.randf_range(0.5, 1.0), th, tw))
			# Abbruchkante: Russ an der Bruchkante
			if vr.randf() < 0.6:
				decal_list.append([Vector3(side * FRONT_X, top_y - 0.8, zc), "soot_wide", wb * 1.1])
		else:
			trim.add(Vector3(side * (FRONT_X + WALL_T / 2.0 - 0.08), top_y + 0.1, zc), Vector3(WALL_T + 0.5, 0.35, wb + 0.02))
			FK.gutter(parts, Vector3(side * FRONT_X, 0, zc + wb / 2.0), Vector3(side * FRONT_X, 0, zc - wb / 2.0), n, top_y - 0.14, "zinc")
			if not is_collapse and vr.randf() < 0.55:
				FK.roof(parts, Vector3(side * (FRONT_X + depth / 2.0), top_y, zc), n, wb, depth - 1.0, vr, {"cap": "zinc", "chimney": "brick", "metal": "metal"})
		# Fallrohr an jeder dritten Feldgrenze (bis zur niedrigeren Nachbarhoehe)
		if i % 3 == 1 and nf == floors and not is_collapse:
			FK.downpipe(parts, Vector3(side * FRONT_X, 0, zc + wb / 2.0), n, 0.05, top_y - 0.2, "zinc")
	var soot := clampf(damage - 0.45, 0.0, 0.4) * 0.6
	_add_mesh(body, wall, wall_mat(brick, tint, soot))
	_add_mesh(body, trim, trim_mat())
	_add_mesh(body, mass, mass_mat())
	parts.build(body, part_mats(), [], {"wood": 90.0, "metal": 110.0})
	var gl := wins.build_node(FK.window_mat("day"))
	if gl != null:
		body.add_child(gl)
	for d: Array in decal_list:
		var p: Vector3 = d[0]
		match String(d[1]):
			"soot":
				FK.soot_above(body, p, n, d[2], 2.4)
			"soot_wide":
				FK.decal(body, p, n, Vector2(d[2], 2.2), "soot.png", {"roll": 180.0, "depth": 1.0, "fade": 70.0})
			"bullets":
				FK.bullet_holes(body, p, n, d[2], vr)
	parent.add_child(body)
	return info

## Ein Fassadenblock als RigidBody (eingefroren). c = Feldmitte absolut.
static func make_block(side: int, c: Vector3, wb: float, brick: bool, tint: Color, rng: RandomNumberGenerator) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1 | 8
	rb.mass = 420.0
	rb.can_sleep = true
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	rb.position = c
	var wall := Geo.batch()
	var trim := Geo.batch()
	var mode := 0 if rng.randf() < 0.75 else 1
	var parts := FK.Parts.new()
	var wins := FK.WindowBatch.new()
	var kit := {"parts": parts, "wins": wins, "frame": "frame_dark", "style": "cross", "surround": 1, "seed": fposmod(c.y * 0.37 + c.z * 0.11, 1.0)}
	cell(wall, trim, side, c, c, wb, false, mode, 0, kit)
	_add_mesh(rb, wall, wall_mat(brick, tint))
	_add_mesh(rb, trim, trim_mat())
	parts.build(rb, part_mats())
	var gl := wins.build_node(FK.window_mat("day"))
	if gl != null:
		rb.add_child(gl)
	Geo.add_box_shape(rb, Vector3(side * 0.05, 0.0, 0.0), Vector3(WALL_T, FLOOR_H, wb - 0.04))
	return rb
