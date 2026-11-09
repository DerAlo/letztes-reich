extends StaticBody3D
## Portalkran (Gitterkonstruktion, Industriegelb) ueber der Kranbahn. topple() kippt ihn nach fall_dir:
## Kippen per Tween um die vordere Fusslinie, erschlaegt Gegner im Fallbereich, danach liegende
## Truemmer-Kollision als Deckung. Spannweite entlang X, Fuesse auf Kranschienen entlang Z.

const RailProps = preload("res://game/levels/rail_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

signal toppled

@export var span: float = 20.0          ## Abstand der Stuetzen (x)
@export var height: float = 15.0
@export var depth: float = 8.0          ## Abstand der Fuesse je Seite (z)
@export var cantilever: float = 5.0     ## Auskragung links/rechts
@export var fall_dir: Vector3 = Vector3(0, 0, -1)
@export var fall_time: float = 2.4

var _pivot: Node3D
var _alive: bool = true
var _cable: MeshInstance3D
var _load: Node3D

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_build()

func is_standing() -> bool:
	return _alive

func _build() -> void:
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	var fd := fall_dir.normalized()
	_pivot.position = fd * (depth * 0.5)
	add_child(_pivot)
	var geo := Node3D.new()
	geo.position = -fd * (depth * 0.5)
	_pivot.add_child(geo)
	var k := RailProps.kit()
	var yellow := RailProps.paint(Color(0.85, 0.56, 0.1))
	var lattice := k.b("lattice", yellow)
	var heavy := k.b("heavy", yellow)
	var dark := k.b("dark", RailProps.dark_steel())
	var hs := span * 0.5
	var hd := depth * 0.5
	var total := span + cantilever * 2.0
	# Fusstraeger auf den Schienen + Laufwerke
	for sx: float in [-hs, hs]:
		heavy.add(Vector3(sx, 0.9, 0), Vector3(1.0, 1.0, depth + 2.0))
		for sz: float in [-hd - 0.4, hd + 0.4]:
			dark.add(Vector3(sx, 0.45, sz), Vector3(0.9, 0.9, 1.6))
		# Stuetzen (leicht geneigt, oben zusammenlaufend)
		for sz: float in [-hd, hd]:
			var top := Vector3(sx, height - 1.0, sz * 0.35)
			var bot := Vector3(sx, 1.4, sz)
			_beam(heavy, bot, top, Vector2(0.75, 0.75))
		# Querverband zwischen den Stuetzen
		var y := 3.0
		while y < height - 2.0:
			var f := (y - 1.4) / (height - 2.4)
			var w := lerpf(depth, depth * 0.35, f)
			lattice.add(Vector3(sx, y, 0), Vector3(0.22, 0.22, w))
			y += 2.6
		for i in 4:
			var y0 := 1.4 + i * (height - 2.4) / 4.0
			var y1 := 1.4 + (i + 1) * (height - 2.4) / 4.0
			var w0 := lerpf(depth, depth * 0.35, float(i) / 4.0) * 0.5
			var w1 := lerpf(depth, depth * 0.35, float(i + 1) / 4.0) * 0.5
			var s := 1.0 if i % 2 == 0 else -1.0
			_beam(lattice, Vector3(sx, y0, -w0 * s), Vector3(sx, y1, w1 * s), Vector2(0.16, 0.16))
	# Hauptträger: zwei Fachwerktraeger entlang X
	for gz: float in [-1.3, 1.3]:
		var gy0 := height - 1.0
		var gy1 := height + 1.2
		lattice.add(Vector3(0, gy0, gz), Vector3(total, 0.45, 0.45))
		lattice.add(Vector3(0, gy1, gz), Vector3(total, 0.35, 0.35))
		var n := int(total / 2.0)
		for i in n + 1:
			var x := -total * 0.5 + i * total / n
			lattice.add(Vector3(x, (gy0 + gy1) * 0.5, gz), Vector3(0.16, gy1 - gy0, 0.16))
			if i < n:
				var x1 := -total * 0.5 + (i + 1) * total / n
				var a := Vector3(x, gy0, gz) if i % 2 == 0 else Vector3(x, gy1, gz)
				var b := Vector3(x1, gy1, gz) if i % 2 == 0 else Vector3(x1, gy0, gz)
				_beam(lattice, a, b, Vector2(0.12, 0.12))
	for i in int(total / 3.0) + 1:
		var x := -total * 0.5 + i * 3.0
		lattice.add(Vector3(x, height + 1.2, 0), Vector3(0.14, 0.14, 2.6))
		lattice.add(Vector3(x, height - 1.0, 0), Vector3(0.14, 0.14, 2.6))
	# Laufkatze mit Kabine
	var tx := hs * 0.3
	heavy.add(Vector3(tx, height + 1.8, 0), Vector3(3.2, 1.2, 3.4))
	var cab := k.b("cab", RailProps.paint(Color(0.72, 0.7, 0.62)))
	cab.add(Vector3(-hs + 1.0, height - 2.2, 1.9), Vector3(2.0, 2.2, 1.8))
	var gl := k.b("glass", RailProps.glass())
	gl.add(Vector3(-hs + 1.0, height - 2.0, 2.82), Vector3(1.8, 1.2, 0.04))
	# Warnstreifen an den Fuessen
	var stripe := k.b("stripe", RailProps.paint(Color(0.08, 0.07, 0.06)))
	for sx: float in [-hs, hs]:
		for i in 3:
			stripe.add(Vector3(sx, 0.9, -hd - 1.0 + i * 0.01), Vector3(1.02, 1.02, 0.2) * 1.0)
	k.flush(geo)
	# Haken + Seil + haengender Container
	_cable = Geo.box_mesh_node(Vector3(0.05, 6.0, 0.05), Geo.flat(Color(0.1, 0.1, 0.1), 0.4, 0.8), Vector3(tx, height - 2.0, 0))
	geo.add_child(_cable)
	_load = Node3D.new()
	_load.position = Vector3(tx, height - 6.5, 0)
	geo.add_child(_load)
	var cm := RailProps.mat("container_side", Color(0.25, 0.4, 0.6), 0.25, 1.0, 0.0, false)
	_load.add_child(Geo.box_mesh_node(Vector3(6.0, 2.6, 2.44), cm, Vector3(0, -1.4, 0)))
	_load.add_child(Geo.box_mesh_node(Vector3(5.6, 0.2, 2.0), RailProps.dark_steel(), Vector3(0, 0.0, 0)))
	# Kollision (stehend): Fussträger + Stuetzen
	for sx: float in [-hs, hs]:
		Geo.add_box_shape(self, Vector3(sx, 0.7, 0), Vector3(1.2, 1.4, depth + 2.0))
		Geo.add_box_shape(self, Vector3(sx, height * 0.5, 0), Vector3(1.0, height - 2.0, depth * 0.55))
	Geo.add_box_shape(self, Vector3(0, height + 0.1, 0), Vector3(total, 2.4, 3.2))

## Balken zwischen a und b als gedrehte Box.
func _beam(bb: Geo.BoxBatch, a: Vector3, b: Vector3, thick: Vector2) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.01:
		return
	var y := d / len
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	bb.add((a + b) * 0.5, Vector3(thick.x, len, thick.y), Basis(x, y, z))

func topple() -> void:
	if not _alive:
		return
	_alive = false
	var fd := fall_dir.normalized()
	for c in get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	VFX.play_sfx_3d("rail_metal_creak", global_position + Vector3(0, height * 0.5, 0), 6.0, 30.0, 300.0)
	var axis := Vector3.UP.cross(fd).normalized()
	var tw := create_tween()
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(4.0)), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(1.5)), 0.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(84.0)), fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_impact)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(80.0)), 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(_pivot, "basis", Basis(axis, deg_to_rad(84.0)), 0.22).set_ease(Tween.EASE_IN)
	# Last pendelt waehrend des Falls
	var tl := create_tween()
	tl.tween_property(_load, "rotation_degrees", Vector3(0, 0, 25.0), 1.2).set_trans(Tween.TRANS_SINE)
	tl.tween_property(_load, "rotation_degrees", Vector3(0, 0, -40.0), fall_time).set_trans(Tween.TRANS_SINE)

func _impact() -> void:
	var fd := fall_dir.normalized()
	var base := global_position + fd * (depth * 0.5)
	var land := base + fd * height
	land.y = 0.4
	var side := Vector3(1, 0, 0) if absf(fd.z) > 0.5 else Vector3(0, 0, 1)
	var total := span + cantilever * 2.0
	for i in 4:
		VFX.spawn_dust_cloud(land + side * ((float(i) / 3.0 - 0.5) * total), 7.5)
	VFX.spawn_dust_cloud(base + fd * height * 0.5, 6.0)
	VFX.play_sfx_3d("rail_metal_crash", land, 8.0, 40.0, 400.0)
	Events.explosion.emit(land, 6.0, 2.0)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", clampf(0.85 - pl.global_position.distance_to(land) / 70.0, 0.2, 0.75))
	# Gegner im Fallbereich erschlagen
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node3D) or not e.has_method("take_damage"):
			continue
		var p: Vector3 = (e as Node3D).global_position
		var rel := p - base
		var along := rel.dot(fd)
		var across := rel.dot(side)
		if along > -1.0 and along < height + 3.0 and absf(across) < total * 0.5 + 1.0 and p.y < 6.0:
			e.call("take_damage", 500.0, self, p + Vector3(0, 1, 0), Vector3.UP)
	# Liegender Kran: Traeger quer, Stuetzen laengs (niedrige Deckung)
	var yaw := atan2(side.x, side.z)
	_lying_shape(land + Vector3(0, 0.9, 0), Vector3(2.8, 1.8, total), yaw)
	for sx: float in [-span * 0.5, span * 0.5]:
		_lying_shape(base + fd * (height * 0.5) + side * sx + Vector3(0, 0.6, 0), Vector3(1.3, 1.2, height), atan2(fd.x, fd.z))
	toppled.emit()

func _lying_shape(gpos: Vector3, size: Vector3, yaw: float) -> void:
	var c := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	c.shape = bs
	add_child(c)
	c.global_position = gpos
	c.global_basis = Basis(Vector3.UP, yaw)
