class_name Pickup
extends Node3D
## Aufhebbare Objekte. Der Player prüft die Gruppe "pickup" (Reichweite RANGE):
##  - WEAPON: liegende Waffe. [E] nimmt sie (Primärwaffe wird getauscht, alte fällt zu Boden).
##    Gleiche Waffe bereits im Inventar -> Munition wird automatisch übernommen.
##  - AMMO: Munition einer Sorte, wird beim Drüberlaufen automatisch eingesammelt (passende Waffe nötig).
##  - CRATE: Munitionskiste, [E] füllt alle Waffen auf Startreserve auf (wiederverwendbar, Abklingzeit).
##  - PZF_CRATE: Panzerfaust-Kiste, [E] gibt Panzerfaust bzw. füllt Raketen auf (Abklingzeit).

enum Kind { WEAPON, AMMO, CRATE, PZF_CRATE }

const RANGE: float = 1.6
const FLOOR_MASK: int = 1

var kind: int = Kind.WEAPON
var weapon_id: String = "g36c"
var ammo_mag: int = 0
var ammo_reserve: int = 0
var ammo_type: String = "556"
var amount: int = 0
var lifetime: float = -1.0
var cooldown_time: float = 15.0
var snap_to_floor: bool = true

var _cd: float = 0.0
var _age: float = 0.0
var _label: Label3D
var _labels: Array[Label3D] = []
var _visual: Node3D

static var _crate_mats: Dictionary = {}

# ----------------------------------------------------------------- Fabriken

static func spawn_weapon(parent: Node, pos: Vector3, id: String, mag: int, reserve: int, yaw_deg: float = 0.0, life: float = -1.0) -> Pickup:
	var p := Pickup.new()
	p.kind = Kind.WEAPON
	p.weapon_id = id
	p.ammo_mag = mag
	p.ammo_reserve = reserve
	p.ammo_type = WeaponDefs.ammo_of(id)
	p.lifetime = life
	p.name = "Pickup_%s" % id
	parent.add_child(p)
	p.global_position = pos
	p.rotation_degrees.y = yaw_deg
	p._after_spawn()
	return p

static func spawn_ammo(parent: Node, pos: Vector3, type: String, count: int, life: float = -1.0) -> Pickup:
	var p := Pickup.new()
	p.kind = Kind.AMMO
	p.ammo_type = type
	p.amount = count
	p.lifetime = life
	p.name = "Pickup_ammo_%s" % type
	parent.add_child(p)
	p.global_position = pos
	p.rotation_degrees.y = randf() * 360.0
	p._after_spawn()
	return p

static func spawn_crate(parent: Node, pos: Vector3, yaw_deg: float = 0.0, pzf: bool = false) -> Pickup:
	var p := Pickup.new()
	p.kind = Kind.PZF_CRATE if pzf else Kind.CRATE
	p.cooldown_time = 12.0 if pzf else 15.0
	p.name = "PzfCrate" if pzf else "AmmoCrate"
	parent.add_child(p)
	p.global_position = pos
	p.rotation_degrees.y = yaw_deg
	p._after_spawn()
	return p

## Level-Helfer: liegende Panzerfaust (1 geladen + 2 Reserve) und daneben eine Panzerfaust-Kiste.
## Deferred, damit die Level-Geometrie für das Boden-Snapping schon existiert.
static func place_pzf_set(parent: Node, pos: Vector3, yaw_deg: float = 0.0) -> void:
	var cb := func() -> void:
		var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
		spawn_weapon(parent, pos, "pzf3", 1, 2, yaw_deg)
		spawn_crate(parent, pos + b * Vector3(0.0, 0.0, 1.3), yaw_deg, true)
	cb.call_deferred()

## Level-Helfer: Munitionskiste (deferred).
static func place_ammo_crate(parent: Node, pos: Vector3, yaw_deg: float = 0.0) -> void:
	(func() -> void: spawn_crate(parent, pos, yaw_deg, false)).call_deferred()

# ----------------------------------------------------------------- Aufbau

func _ready() -> void:
	add_to_group("pickup")

func _after_spawn() -> void:
	if snap_to_floor:
		_snap()
	_build_visual()

func _snap() -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 0.8
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3.DOWN * 6.0, FLOOR_MASK)
	var res: Dictionary = space.intersect_ray(q)
	if not res.is_empty():
		global_position = res.position

func _build_visual() -> void:
	match kind:
		Kind.WEAPON:
			_visual = GunModels.build_world(weapon_id)
			add_child(_visual)
			# auf der Seite liegend
			_visual.rotation_degrees = Vector3(0, 0, 90)
			_visual.position = Vector3(0, 0.03 if weapon_id != "pzf3" else 0.06, 0)
		Kind.AMMO:
			_visual = _build_ammo_box()
			add_child(_visual)
		Kind.CRATE, Kind.PZF_CRATE:
			_visual = _build_crate(kind == Kind.PZF_CRATE)
			add_child(_visual)
	_set_shadows(_visual)

func _set_shadows(n: Node) -> void:
	if n is GeometryInstance3D and not n is Label3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_set_shadows(c)

static func _cmat(key: String) -> StandardMaterial3D:
	if _crate_mats.is_empty():
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color(0.25, 0.27, 0.16)
		wood.roughness = 0.85
		_crate_mats["olive"] = wood
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.14, 0.15, 0.1)
		dark.roughness = 0.8
		_crate_mats["dark"] = dark
		var metal := StandardMaterial3D.new()
		metal.albedo_color = Color(0.2, 0.2, 0.2)
		metal.metallic = 0.8
		metal.roughness = 0.45
		_crate_mats["metal"] = metal
		var yel := StandardMaterial3D.new()
		yel.albedo_color = Color(0.8, 0.65, 0.12)
		yel.roughness = 0.6
		_crate_mats["yellow"] = yel
	return _crate_mats[key]

static func _box_mi(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi

func _build_ammo_box() -> Node3D:
	var n := Node3D.new()
	if ammo_type == "pzf":
		var r := GunModels.build_rocket()
		r.rotation_degrees = Vector3(0, 0, 90)
		r.position = Vector3(0, 0.06, 0)
		n.add_child(r)
		return n
	# Munitionskasten (Blech, oliv) mit Klappgriff, Kennstreifen und Kaliber-Aufdruck
	var can := GunModels.build_ammo_can()
	n.add_child(can)
	GunModels._set_vis_range(can, 45.0)
	return n

## Munitionskiste (oliv lackierte Holzbretter, Leisten, Metallecken, Spannverschluesse, Seilgriffe).
## Beschriftung zwischen den Leisten, gross genug, dass nichts abgeschnitten wird.
func _build_crate(pzf: bool) -> Node3D:
	var n := Node3D.new()
	var crate := GunModels.build_crate(pzf)
	n.add_child(crate)
	var size: Vector3 = crate.get_meta("size")
	var body_h: float = crate.get_meta("body_h")
	if pzf:
		# Zwei Panzerfaeuste obenauf
		for i in 2:
			var l := GunModels.build_pzf()
			l.scale = Vector3.ONE * 0.85
			l.rotation_degrees = Vector3(0, 90, 0)
			l.position = Vector3(0.05, size.y + 0.04, -0.1 + 0.2 * i)
			n.add_child(l)
	var face_z: float = size.z * 0.5 - 0.006 + 0.0015
	for side: float in [1.0, -1.0]:
		var holder := Node3D.new()
		holder.rotation_degrees = Vector3(0, 0.0 if side > 0.0 else 180.0, 0)
		n.add_child(holder)
		var lb := _stencil("PANZERFAUST" if pzf else "MUNITION", 64, 0.0014)
		lb.position = Vector3(0, body_h * 0.6, face_z)
		holder.add_child(lb)
		var sub := _stencil("PZF 3 - DM 22 - 2 STK - LOS 07/31" if pzf else "5,56 x 45 - DM 11 - 840 SCHUSS", 40, 0.00075)
		sub.position = Vector3(0, body_h * 0.6 - 0.07, face_z)
		holder.add_child(sub)
		_labels.append(lb)
		_labels.append(sub)
		if side > 0.0:
			_label = lb
	return n

static func _stencil(text: String, fs: int, px: float) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = fs
	lb.pixel_size = px
	lb.modulate = Color(0.95, 0.9, 0.7)
	lb.outline_size = 0
	lb.shaded = true
	lb.double_sided = false
	lb.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	lb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return lb

# ----------------------------------------------------------------- Logik

func _process(delta: float) -> void:
	_age += delta
	if _cd > 0.0:
		_cd = maxf(0.0, _cd - delta)
		for lb: Label3D in _labels:
			lb.modulate = Color(0.6, 0.6, 0.55) if _cd > 0.0 else Color(0.95, 0.9, 0.7)
	if lifetime > 0.0 and _age > lifetime:
		queue_free()

func in_range(p: Node3D) -> bool:
	var d: Vector3 = p.global_position - global_position
	return absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < RANGE

## Automatisches Einsammeln (nur Munition). true = Pickup verbraucht.
func auto_collect(p: Player) -> bool:
	match kind:
		Kind.AMMO:
			var w: Weapon = p.weapon_for_ammo(ammo_type)
			if w == null or w.ammo_reserve >= w.reserve_max:
				return false
			var before: int = w.ammo_reserve
			w.add_reserve(amount)
			amount -= w.ammo_reserve - before
			p.on_ammo_collected(w.ammo_reserve - before, ammo_type)
			if amount <= 0:
				queue_free()
				return true
		Kind.WEAPON:
			var w2: Weapon = p.get_weapon(weapon_id)
			if w2 == null or w2.ammo_reserve >= w2.reserve_max:
				return false
			var total: int = ammo_mag + ammo_reserve
			if total <= 0:
				return false
			var before2: int = w2.ammo_reserve
			w2.add_reserve(total)
			var got: int = w2.ammo_reserve - before2
			p.on_ammo_collected(got, ammo_type)
			# Rest bleibt in der liegenden Waffe
			var rest: int = total - got
			ammo_mag = mini(rest, ammo_mag)
			ammo_reserve = rest - ammo_mag
			if rest <= 0:
				queue_free()
				return true
	return false

## Text für den HUD-Hinweis ("" = keine Interaktion möglich).
func interact_text(p: Player) -> String:
	match kind:
		Kind.WEAPON:
			if p.get_weapon(weapon_id) != null:
				return ""
			return "[E] %s aufnehmen" % WeaponDefs.display_name(weapon_id)
		Kind.CRATE:
			if _cd > 0.0 or not p.needs_ammo():
				return ""
			return "[E] Munition auffüllen"
		Kind.PZF_CRATE:
			if _cd > 0.0:
				return ""
			var l: Weapon = p.get_weapon("pzf3")
			if l == null:
				return "[E] Panzerfaust aufnehmen"
			if l.ammo_mag + l.ammo_reserve < l.mag_size + l.reserve_start:
				return "[E] Raketen auffüllen"
	return ""

func interact(p: Player) -> void:
	match kind:
		Kind.WEAPON:
			var old: Dictionary = p.give_weapon(weapon_id, ammo_mag, ammo_reserve)
			if not old.is_empty():
				Pickup.spawn_weapon(get_parent(), global_position, str(old.id), int(old.mag), int(old.reserve),
					rotation_degrees.y + 40.0, 120.0)
			queue_free()
		Kind.CRATE:
			p.refill_from_crate()
			_cd = cooldown_time
		Kind.PZF_CRATE:
			var l: Weapon = p.get_weapon("pzf3")
			if l == null:
				p.give_weapon("pzf3", 1, 2)
			else:
				l.ammo_reserve = maxi(l.ammo_reserve, l.reserve_start + l.mag_size - l.ammo_mag)
				l.ammo_reserve = mini(l.ammo_reserve, l.reserve_max)
				p.play_sfx("ammo_pickup", 0.05)
			_cd = cooldown_time
