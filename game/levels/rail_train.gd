extends Node3D
## Munitionszug fuer "Letzter Zug": Lok + Wagen auf einem Gleis entlang -Z.
## Ein markierter Kesselwagen ist beschiessbar (Gruppe "damageable"); ein Treffer -- oder detonate()
## vom Level -- startet die Kettenexplosion: Wagen werden zu RigidBodies (Layer debris), fliegen
## hoch und kippen um, danach Feuerwand und riesige Rauchsaeule (ueber das fx-Objekt des Levels).

const RailProps = preload("res://game/levels/rail_props.gd")
const Geo = preload("res://game/levels/level_geo.gd")

signal detonated(pos: Vector3)
signal chain_finished

## Beschiessbarer Huellkoerper des markierten Kesselwagens.
class MarkedBlocker extends StaticBody3D:
	signal hit_dead
	var health: float = 70.0
	var _alive: bool = true
	func _ready() -> void:
		add_to_group("damageable")
	func is_alive() -> bool:
		return _alive
	func take_damage(amount: float, _source: Node = null, hit_position: Vector3 = Vector3.ZERO, hit_normal: Vector3 = Vector3.ZERO) -> void:
		if not _alive:
			return
		health -= amount
		if hit_position != Vector3.ZERO:
			VFX.spawn_impact(hit_position, hit_normal, "metal")
		if health <= 0.0:
			_alive = false
			# leicht verzoegert: keine Rekursion im Combat-Loop
			get_tree().create_timer(0.08).timeout.connect(func() -> void: hit_dead.emit())

## [kind, extra, color]
@export var layout: Array = [
	["loco", true, Color(0.2, 0.32, 0.22)],
	["tank", false, Color(0.16, 0.16, 0.15)],
	["tank", true, Color(0.2, 0.2, 0.19)],
	["boxcar", 1.4, Color(0.42, 0.2, 0.13)],
	["tank", false, Color(0.15, 0.15, 0.14)],
	["boxcar", 0.0, Color(0.36, 0.22, 0.15)],
	["flat", "crates", Color(0.3, 0.28, 0.24)],
]
@export var gap: float = 0.15
@export var chain_step: float = 0.62

var fx: Node = null                    ## rail_fx.gd des Levels (optional)
var wagons: Array[Dictionary] = []     ## {rb, blocker, size, center, kind, marked}
var marked_index: int = -1
var _done: bool = false
var _rng := RandomNumberGenerator.new()
var _charred: StandardMaterial3D

## Baut den Zug. world = NavigationRegion3D (Blocker werden ins Navmesh gebacken).
## Erster Eintrag steht bei z_front (Lok vorne), weitere Wagen folgen nach -Z.
func build(world: Node3D, x: float, z_front: float) -> void:
	_rng.seed = 3003
	_charred = RailProps.mat("rust_coarse_01", Color(0.09, 0.075, 0.065), 0.6, 1.0, 0.0, false)
	var z := z_front
	for i in layout.size():
		var e: Array = layout[i]
		var kind: String = e[0]
		var rb := RigidBody3D.new()
		rb.name = "Wagon%d_%s" % [i, kind]
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.mass = 2500.0
		rb.can_sleep = true
		var vis := Node3D.new()
		vis.name = "Visual"
		rb.add_child(vis)
		var size: Vector3 = RailProps.build_wagon(vis, kind, _rng, e[2], e[1])
		var center := Vector3(x, 0, z - size.z * 0.5)
		rb.position = center
		# Lok: Fuehrerstand zeigt nach -Z (vorne) -> 180 Grad, damit der Zug "abfahrbereit" wirkt
		if kind == "loco":
			rb.rotation_degrees.y = 180.0
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(size.x, size.y - 0.4, size.z - 1.0)
		cs.shape = bs
		cs.position = Vector3(0, size.y * 0.5 + 0.2, 0)
		rb.add_child(cs)
		add_child(rb)
		var marked := kind == "tank" and bool(e[1])
		var blocker: StaticBody3D
		if marked:
			var mb := MarkedBlocker.new()
			mb.collision_layer = 1
			mb.collision_mask = 0
			mb.hit_dead.connect(detonate)
			blocker = mb
			marked_index = i
		else:
			blocker = Geo.static_body()
		blocker.name = "Blocker%d" % i
		blocker.position = center
		Geo.add_box_shape(blocker, Vector3(0, size.y * 0.5, 0), size)
		world.add_child(blocker)
		wagons.append({"rb": rb, "blocker": blocker, "size": size, "center": center, "kind": kind, "marked": marked})
		z -= size.z + gap

func get_marked_position() -> Vector3:
	if marked_index < 0:
		return Vector3.ZERO
	var w: Dictionary = wagons[marked_index]
	return (w["center"] as Vector3) + Vector3(0, 2.7, 0)

func is_done() -> bool:
	return _done

## Startet die Kettenexplosion (einmalig).
func detonate() -> void:
	if _done:
		return
	_done = true
	var origin := marked_index if marked_index >= 0 else 0
	detonated.emit(get_marked_position())
	_chain(origin)

func _chain(origin: int) -> void:
	var order: Array = []          # [index, delay]
	var maxd := 0
	for i in wagons.size():
		var d := absi(i - origin)
		maxd = maxi(maxd, d)
		order.append([i, d * chain_step + (0.0 if d == 0 else _rng.randf_range(-0.08, 0.12))])
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	var t := 0.0
	for o: Array in order:
		var wait := float(o[1]) - t
		if wait > 0.0:
			await get_tree().create_timer(wait).timeout
		t = float(o[1])
		_blow(int(o[0]), int(o[0]) == origin)
	# Nachbrennen: kleine Munitions-Detonationen (Pool hat sich bis dahin erholt)
	await get_tree().create_timer(6.5).timeout
	chain_finished.emit()
	for k in 9:
		await get_tree().create_timer(_rng.randf_range(1.2, 2.6)).timeout
		var w: Dictionary = wagons[_rng.randi() % wagons.size()]
		var p: Vector3 = (w["center"] as Vector3) + Vector3(_rng.randf_range(-2.5, 1.5), _rng.randf_range(0.5, 2.5), _rng.randf_range(-5.0, 5.0))
		VFX.spawn_explosion(p, _rng.randf_range(0.6, 1.1))
		if fx != null and fx.has_method("spark_burst"):
			fx.call("spark_burst", p)

func _blow(i: int, primary: bool) -> void:
	var w: Dictionary = wagons[i]
	var rb: RigidBody3D = w["rb"]
	var size: Vector3 = w["size"]
	var c: Vector3 = w["center"]
	var kind: String = w["kind"]
	var blocker: StaticBody3D = w["blocker"]
	for ch in blocker.get_children():
		if ch is CollisionShape3D:
			(ch as CollisionShape3D).set_deferred("disabled", true)
	var core := c + Vector3(0, 2.2, 0)
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	# Explosion (Pool: 6 gleichzeitige) -- Lok und Flachwagen nur Druckwelle + Feuer
	var big := primary or kind == "tank" or kind == "boxcar"
	if big:
		var vis := 5.2 if primary else (3.8 if kind == "tank" else 3.3)
		Combat.explode(core, 8.5 if primary else 7.0, 220.0 if primary else 160.0, self, vis)
		if fx != null and fx.has_method("fireball"):
			fx.call("fireball", core + Vector3(0, 1.5, 0), 2.2 if primary else 1.5)
	else:
		Events.explosion.emit(core, 5.0, 1.0)
		if fx != null and fx.has_method("fireball"):
			fx.call("fireball", core, 1.1)
	if pl != null and pl.has_method("add_trauma"):
		var d := pl.global_position.distance_to(core)
		pl.call("add_trauma", clampf((1.1 if primary else 0.7) - d / 55.0, 0.12, 0.85))
	# Wagen losreissen
	rb.freeze = false
	rb.collision_layer = 8
	rb.collision_mask = 1 | 8
	rb.continuous_cd = false
	rb.linear_damp = 0.05
	rb.angular_damp = 0.3
	var up := _rng.randf_range(9.0, 15.0) if primary else _rng.randf_range(4.5, 10.5)
	if kind == "loco":
		up = 3.2
	var side := -_rng.randf_range(2.5, 6.5) if kind != "loco" else -2.2
	var v := Vector3(side, up, _rng.randf_range(-2.5, 2.5))
	rb.apply_central_impulse(v * rb.mass)
	var spin := Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(-0.8, 0.8), _rng.randf_range(0.9, 2.4))
	if kind == "loco":
		spin = Vector3(0, 0.1, 1.1)
	rb.angular_velocity = spin
	# Nach dem Ausrollen einfrieren: halb im Boden steckende Wagen blieben sonst dauerhaft wach (Jolt drueckt sie
	# Schritt fuer Schritt heraus), ueber den Rand geflogene fielen endlos.
	get_tree().create_timer(14.0, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(rb):
			return
		if rb.global_position.y < -4.0:
			rb.visible = false
		rb.set_deferred("freeze", true))
	# verkohlen
	_char(rb)
	# Feuer + Rauch an der alten Position
	if fx != null and fx.has_method("wagon_burn"):
		fx.call("wagon_burn", c, kind, primary, i)
	VFX.spawn_scorch(Vector3(c.x, 0.05, c.z), Vector3.UP, 9.0)

func _char(n: Node) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			if mi.material_override != null and mi.material_override is StandardMaterial3D and (mi.material_override as StandardMaterial3D).emission_enabled:
				continue
			mi.material_override = _charred
		_char(ch)
