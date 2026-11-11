extends Node3D
## Breach-Tuer (wiederverwendbar, Runde 7). Wird in eine Wandoeffnung gesetzt (Ursprung = Boden, Mitte der
## Oeffnung). Lokal -Z zeigt in den Raum, +Z ist die Spielerseite.
##
## Bedienung (nur in Reichweite auf der Spielerseite):
##   [E] halten  -> Sprengladung anbringen; Zuender piept fuse_time s, dann fliegt das Tuerblatt in den Raum
##                  (Gegner nahe der Tuer sind kurz benommen)
##   [F]         -> Tuer eintreten (sofort, ohne Betaeubung)
##   [B]         -> Blendgranate mitwerfen an/aus (wird beim Breach in den Raum geworfen)
## Bot/Skript: bot_plant(flash), bot_kick(flash). Die Tuer meldet breached(kind, flash, pos).
## Kein class_name (keine globale Klasse noetig): preload("res://game/systems/breach_door.gd").

signal planted
signal breached(kind: String, flash: bool)

const VF = preload("res://game/vehicles/vehicle_fx.gd")

@export var width: float = 1.6
@export var height: float = 2.45
@export var hold_time: float = 1.2
@export var fuse_time: float = 2.4
@export var reach: float = 2.3
@export var flash_available: bool = true

enum DoorState { CLOSED, ARMED, OPEN }
var state: DoorState = DoorState.CLOSED
var locked: bool = false                 ## true: keine Bedienung (z. B. Raum gesperrt)
var flash_armed: bool = false
var bot_mode: bool = false

var _leaf: StaticBody3D
var _leaf_mats: Dictionary = {}
var _label: Label3D
var _charge: Node3D
var _led_mat: StandardMaterial3D
var _led_light: OmniLight3D
var _hold: float = 0.0
var _fuse: float = 0.0
var _beep_t: float = 0.0
var _t: float = 0.0
var _bot_hold: bool = false
var _debris: Array[Node] = []

func _ready() -> void:
	bot_mode = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	_ensure_actions()
	_build_frame()
	_build_leaf()
	_build_charge()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 24
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.92, 0.6)
	_label.position = Vector3(0, 1.55, 0.35)
	_label.visible = false
	add_child(_label)

static func _ensure_actions() -> void:
	for pair: Array in [["breach_kick", KEY_F], ["breach_flash", KEY_B]]:
		var a: String = pair[0]
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = pair[1]
			InputMap.action_add_event(a, ev)

# ------------------------------------------------------------------ Aufbau

func _mat(key: String, c: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	if not _leaf_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_leaf_mats[key] = m
	return _leaf_mats[key]

func _build_frame() -> void:
	var fm := _mat("frame", Color(0.16, 0.15, 0.13), 0.5, 0.4)
	var w2 := width * 0.5
	add_child(_box(Vector3(0.12, height + 0.12, 0.34), fm, Vector3(-w2 - 0.06, (height + 0.12) * 0.5, 0)))
	add_child(_box(Vector3(0.12, height + 0.12, 0.34), fm, Vector3(w2 + 0.06, (height + 0.12) * 0.5, 0)))
	add_child(_box(Vector3(width + 0.24, 0.12, 0.34), fm, Vector3(0, height + 0.06, 0)))
	# Markierung "Breach-Punkt": gelbes Klebeband-Dreieck neben der Tuer (Spielerseite)
	var tape := StandardMaterial3D.new()
	tape.albedo_color = Color(0.9, 0.7, 0.08)
	tape.emission_enabled = true
	tape.emission = Color(0.9, 0.6, 0.05)
	tape.emission_energy_multiplier = 0.35
	add_child(_box(Vector3(0.22, 0.04, 0.01), tape, Vector3(w2 + 0.32, 1.35, 0.18)))
	add_child(_box(Vector3(0.04, 0.22, 0.01), tape, Vector3(w2 + 0.32, 1.35, 0.18)))

func _box(s: Vector3, m: Material, p: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = s
	mi.mesh = bm
	mi.material_override = m
	mi.position = p
	mi.rotation_degrees = rot
	return mi

func _build_leaf() -> void:
	if _leaf != null and is_instance_valid(_leaf):
		_leaf.queue_free()
	_leaf = StaticBody3D.new()
	_leaf.name = "Leaf"
	_leaf.collision_layer = 1
	_leaf.collision_mask = 0
	_leaf.set_meta("surface", "wood")
	_leaf.set_meta("no_fit", true)
	var wood := _mat("wood", Color(0.3, 0.2, 0.12), 0.6)
	var dark := _mat("wood_dark", Color(0.18, 0.11, 0.07), 0.6)
	var brass := _mat("brass", Color(0.75, 0.6, 0.3), 0.3, 0.9)
	var lw := width - 0.06
	var lh := height - 0.04
	# Scharnier links (-x): Blatt als Kind eines Pivots, damit Eintreten aufschwingt
	_leaf.position = Vector3(-width * 0.5 + 0.03, 0, 0)
	_leaf.add_child(_box(Vector3(lw, lh, 0.07), wood, Vector3(lw * 0.5, lh * 0.5, 0)))
	for y: float in [0.6, 1.75]:
		_leaf.add_child(_box(Vector3(lw - 0.3, 0.7, 0.012), dark, Vector3(lw * 0.5, y, 0.04)))
		_leaf.add_child(_box(Vector3(lw - 0.3, 0.7, 0.012), dark, Vector3(lw * 0.5, y, -0.04)))
	_leaf.add_child(_box(Vector3(0.14, 0.04, 0.06), brass, Vector3(lw - 0.14, 1.05, 0.06)))
	_leaf.add_child(_box(Vector3(0.14, 0.04, 0.06), brass, Vector3(lw - 0.14, 1.05, -0.06)))
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(lw, lh, 0.1)
	cs.shape = bs
	cs.position = Vector3(lw * 0.5, lh * 0.5, 0)
	_leaf.add_child(cs)
	add_child(_leaf)

func _build_charge() -> void:
	_charge = Node3D.new()
	_charge.visible = false
	_charge.position = Vector3(width * 0.25, 1.1, 0.07)
	add_child(_charge)
	var block := _mat("c4", Color(0.52, 0.5, 0.4), 0.85)
	var tape := _mat("c4_tape", Color(0.12, 0.12, 0.11), 0.5)
	_charge.add_child(_box(Vector3(0.1, 0.5, 0.06), block, Vector3.ZERO))
	_charge.add_child(_box(Vector3(0.11, 0.04, 0.065), tape, Vector3(0, 0.12, 0)))
	_charge.add_child(_box(Vector3(0.11, 0.04, 0.065), tape, Vector3(0, -0.12, 0)))
	# Detonationsschnur quer ueber das Schloss
	_charge.add_child(_box(Vector3(0.6, 0.015, 0.015), _mat("cord", Color(0.8, 0.75, 0.1), 0.6), Vector3(0.15, -0.05, 0.03)))
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.3, 0.0, 0.0)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.05, 0.02)
	_led_mat.emission_energy_multiplier = 0.0
	_charge.add_child(_box(Vector3(0.03, 0.03, 0.02), _led_mat, Vector3(0, 0.2, 0.04)))
	_led_light = OmniLight3D.new()
	_led_light.light_color = Color(1.0, 0.1, 0.05)
	_led_light.light_energy = 0.0
	_led_light.omni_range = 2.2
	_led_light.position = Vector3(0, 0.2, 0.25)
	_charge.add_child(_led_light)

# ------------------------------------------------------------------ Ablauf

func _player() -> Node3D:
	return Game.get_player() as Node3D

## Spieler auf der Aussenseite in Reichweite?
func player_in_reach() -> bool:
	var p := _player()
	if p == null or not p.is_inside_tree():
		return false
	var local := to_local(p.global_position)
	return local.z > -0.2 and local.z < reach + 0.6 and absf(local.x) < reach and absf(local.y) < 1.5

## Punkt vor der Tuer (Spielerseite), dist m vor der Oeffnung, side m seitlich.
func outside_point(dist: float, side: float = 0.0) -> Vector3:
	return to_global(Vector3(side, 0.0, dist))

func inside_point(dist: float, side: float = 0.0) -> Vector3:
	return to_global(Vector3(side, 0.0, -dist))

func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		DoorState.CLOSED:
			_tick_closed(delta)
		DoorState.ARMED:
			_tick_fuse(delta)
		_:
			pass

func _tick_closed(delta: float) -> void:
	var near := not locked and player_in_reach()
	if bot_mode:
		_label.visible = false
		if _bot_hold and near:
			_hold += delta
			if _hold >= hold_time:
				_bot_hold = false
				_plant()
		return
	_label.visible = near
	if not near:
		_hold = 0.0
		return
	if flash_available and Input.is_action_just_pressed("breach_flash"):
		flash_armed = not flash_armed
	if Input.is_action_just_pressed("breach_kick"):
		kick()
		return
	if Input.is_action_pressed("interact"):
		_hold += delta
		if _hold >= hold_time:
			_plant()
			return
	else:
		_hold = 0.0
	_label.text = _prompt()

func _prompt() -> String:
	var t := ""
	if _hold > 0.0:
		var bars := int(clampf(_hold / hold_time, 0.0, 1.0) * 10.0)
		t = "Ladung anbringen  [" + "|".repeat(bars) + ".".repeat(10 - bars) + "]"
	else:
		t = "[E halten] Sprengladung    [F] Eintreten"
	if flash_available:
		t += "\n[B] Blendgranate: " + ("JA" if flash_armed else "nein")
	return t

## Bot: Ladung anbringen (haelt E simuliert, Spieler muss in Reichweite sein).
func bot_plant(flash: bool) -> void:
	if state != DoorState.CLOSED or locked:
		return
	flash_armed = flash and flash_available
	_bot_hold = true

func bot_kick(flash: bool) -> void:
	if state != DoorState.CLOSED or locked:
		return
	flash_armed = flash and flash_available
	kick()

func _plant() -> void:
	if state != DoorState.CLOSED:
		return
	state = DoorState.ARMED
	_fuse = 0.0
	_beep_t = 0.0
	_hold = 0.0
	_label.visible = false
	_charge.visible = true
	VF.play_at(self, "veh_charge_plant", _charge.global_position, -2.0, 4.0, 40.0)
	planted.emit()

func _tick_fuse(delta: float) -> void:
	_fuse += delta
	var k := clampf(_fuse / fuse_time, 0.0, 1.0)
	var interval := lerpf(0.45, 0.07, k * k)
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = interval
		VF.play_at(self, "veh_charge_beep", _charge.global_position, 0.0, 5.0, 60.0, 1.0 + k * 0.3)
		_led_mat.emission_energy_multiplier = 8.0
		_led_light.light_energy = 1.6
	else:
		_led_mat.emission_energy_multiplier = move_toward(_led_mat.emission_energy_multiplier, 0.0, delta * 60.0)
		_led_light.light_energy = move_toward(_led_light.light_energy, 0.0, delta * 12.0)
	if _fuse >= fuse_time:
		_detonate()

func _detonate() -> void:
	state = DoorState.OPEN
	_charge.visible = false
	_led_light.light_energy = 0.0
	var pos := to_global(Vector3(0, 1.1, -0.3))
	# Geringe Reichweite: trifft nur, wer direkt an der Tuer steht (Quelle = Tuer, nie Geiseln-Fehlschlag)
	Combat.explode(pos, 2.4, 45.0, self, 0.7)
	VFX.spawn_dust_cloud(pos, 2.5)
	_fling_leaf()
	_throw_flash()
	breached.emit("charge", flash_armed)

## Tuer eintreten (sofort).
func kick() -> void:
	if state != DoorState.CLOSED or locked:
		return
	state = DoorState.OPEN
	_label.visible = false
	VF.play_at(self, "overwatch_door_slam", to_global(Vector3(0, 1.2, 0)), 4.0, 6.0, 60.0, 0.85)
	for c in _leaf.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property(_leaf, "rotation_degrees:y", 100.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_leaf, "rotation_degrees:y", 92.0, 0.25)
	_throw_flash()
	breached.emit("kick", flash_armed)

func _fling_leaf() -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 8
	rb.collision_mask = 1 | 8
	rb.mass = 30.0
	var xf := _leaf.global_transform
	for c in _leaf.get_children():
		_leaf.remove_child(c)
		rb.add_child(c)
	_leaf.queue_free()
	_leaf = null
	get_parent().add_child(rb)
	rb.global_transform = xf
	var into := -global_basis.z
	rb.linear_velocity = into * 9.0 + Vector3.UP * 1.5
	rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-2, 2), randf_range(-4, 4))
	_debris.append(rb)
	get_tree().create_timer(8.0, false).timeout.connect(func() -> void:
		if is_instance_valid(rb):
			rb.freeze = true)
	VF.play_at(self, "rail_metal_crash", global_position + Vector3.UP, 0.0, 8.0, 80.0, 1.3)

func _throw_flash() -> void:
	if not flash_armed:
		return
	var pos := to_global(Vector3(0.0, 1.0, -2.5))
	get_tree().create_timer(0.25, false).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.97, 0.9)
		l.light_energy = 40.0
		l.omni_range = 14.0
		l.shadow_enabled = false
		get_parent().add_child(l)
		l.global_position = pos
		var tw := l.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.5)
		tw.tween_callback(l.queue_free)
		VF.play_at(self, "explosion_2", pos, -6.0, 6.0, 80.0, 1.9)
		# Spieler nah an der Blendgranate: kurzer Weissblitz (Kameraschuetteln)
		var p := _player()
		if p != null and p.has_method("add_trauma") and p.global_position.distance_to(pos) < 4.0:
			p.call("add_trauma", 0.35))

## Zuruecksetzen (Raum-Neustart): Tuer zu, Ladung weg.
func reset() -> void:
	for d in _debris:
		if is_instance_valid(d):
			d.queue_free()
	_debris.clear()
	_build_leaf()
	state = DoorState.CLOSED
	_charge.visible = false
	_led_light.light_energy = 0.0
	_hold = 0.0
	_fuse = 0.0
	_bot_hold = false
	flash_armed = false

func is_open() -> bool:
	return state == DoorState.OPEN
