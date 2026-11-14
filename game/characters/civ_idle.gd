extends Node
## Idle-Leben der gebackenen Zivil-/Geiselfiguren (civ_figure.gd): treibt den Vertex-Zusatz der Idle-Materialien
## ueber den Instanz-Parameter idle_state (x Kopf-Yaw, y Kopf-Pitch, z Atem -1..1) -> Atmen (Brustkorb/Schultern)
## und Blickwechsel (Kopf dreht sich, ab und zu zum nahen Spieler). Stehende Figuren (sway) pendeln zusaetzlich
## minimal um die Fuesse. Je Figur zufaellige Frequenzen/Phasen.
## Nur in Kamera-Naehe (RANGE); aus bei Pause, gekippter Figur (Sturz), totem Traeger (Vorfahre mit is_alive()
## -> false, z. B. breach_hostage) oder Meta "no_idle" am Mesh. Ausgeschaltet = exakt die gebackene Pose.

const RANGE := 25.0

var mesh_inst: GeometryInstance3D = null
var sway: bool = false          ## stehend: Pendeln um den Mesh-Ursprung (Sohlen)
var enabled: bool = true

var _w := 0.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _br_f := 0.25
var _br_ph := 0.0
var _sw_ph := 0.0
var _sw_f := 0.1
var _look := Vector2.ZERO
var _look_v := Vector2.ZERO
var _look_tgt := Vector2.ZERO
var _look_hold := 0.0
var _carrier: Node = null       ## Vorfahre mit is_alive()
var _rot0 := Vector3.ZERO
var _active := false
var _has_mat := false

func _ready() -> void:
	_rng.randomize()
	_br_f = _rng.randf_range(0.21, 0.3)
	_br_ph = _rng.randf() * TAU
	_sw_f = _rng.randf_range(0.06, 0.11)
	_sw_ph = _rng.randf() * TAU
	_look_hold = _rng.randf_range(0.5, 3.0)
	if mesh_inst == null:
		mesh_inst = get_parent() as GeometryInstance3D
	var n := get_parent()
	for i in 5:
		if n == null:
			break
		if n.has_method("is_alive"):
			_carrier = n
			break
		n = n.get_parent()
	if mesh_inst != null:
		_rot0 = mesh_inst.rotation
		# ohne Idle-Materialien (Umwandlung fehlgeschlagen) kein Instanz-Parameter, nur das Pendeln
		var mi := mesh_inst as MeshInstance3D
		_has_mat = false
		if mi != null and mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_material(i) is ShaderMaterial:
					_has_mat = true
					break

func _want() -> float:
	if not enabled or mesh_inst == null or not is_instance_valid(mesh_inst) or mesh_inst.has_meta("no_idle"):
		return 0.0
	if not mesh_inst.is_visible_in_tree():
		return 0.0
	if _carrier != null and is_instance_valid(_carrier) and not bool(_carrier.call("is_alive")):
		return 0.0
	if mesh_inst.global_basis.y.normalized().dot(Vector3.UP) < 0.8:
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_squared_to(mesh_inst.global_position) > RANGE * RANGE:
		return 0.0
	return 1.0

func _process(dt: float) -> void:
	if dt <= 0.0 or mesh_inst == null or not is_instance_valid(mesh_inst):
		return
	var want := _want()
	if want <= 0.0 and _w <= 0.0:
		if _active:
			_active = false
			if _has_mat:
				mesh_inst.set_instance_shader_parameter(&"idle_state", Vector4.ZERO)
			if sway:
				mesh_inst.rotation = _rot0
		return
	if not _active:
		_active = true
		if sway:
			_rot0 = mesh_inst.rotation
	_w = move_toward(_w, want, dt * 1.5)
	_t += dt
	var ph := fmod(_t * _br_f * TAU + _br_ph, TAU)
	var br := sin(ph + 0.35 * sin(ph)) * _w
	_tick_look(dt)
	var nod := 0.01 * sin(_t * 0.47 + _br_ph)
	if _has_mat:
		mesh_inst.set_instance_shader_parameter(&"idle_state",
			Vector4(_look.x * _w, (_look.y + nod) * _w, br, 0.0))
	if sway:
		# Haltungspendeln (~0,3 Grad), seitlich etwas staerker als vor/zurueck
		var sx := sin(_t * _sw_f * TAU + _sw_ph) * 0.6 + sin(_t * 0.031 * TAU + _br_ph) * 0.4
		var sz := sin(_t * _sw_f * 1.37 * TAU + _sw_ph * 1.7)
		mesh_inst.rotation = _rot0 + Vector3(0.0035 * sz, 0.0, 0.0055 * sx) * _w

## Blickwechsel wie VipRig: halten, neues Ziel (geradeaus / seitlich / zum nahen Spieler), gedaempfte Feder.
func _tick_look(dt: float) -> void:
	_look_hold -= dt
	if _look_hold <= 0.0:
		_look_hold = _rng.randf_range(1.5, 5.0)
		var r := _rng.randf()
		if r < 0.35 and _player_target():
			pass
		elif r < 0.65:
			_look_tgt = Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.06, 0.04))
		else:
			var sgn := -1.0 if _rng.randf() < 0.5 else 1.0
			_look_tgt = Vector2(sgn * _rng.randf_range(0.2, 0.45), _rng.randf_range(-0.08, 0.05))
	var k := 22.0
	_look_v += ((_look_tgt - _look) * k - _look_v * 2.0 * sqrt(k)) * dt
	_look += _look_v * dt

## Ziel = Richtung zum Spieler (Mesh-Raum, Blick +Z; Yaw + = Richtung Mesh +X), nur nah und grob voraus.
func _player_target() -> bool:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	if pl == null:
		return false
	var head := mesh_inst.global_transform * (mesh_inst.get_aabb().get_center() + Vector3(0.0, mesh_inst.get_aabb().size.y * 0.4, 0.0))
	var d := pl.global_position + Vector3(0.0, 1.5, 0.0) - head
	if d.length() > 9.0:
		return false
	var l := mesh_inst.global_basis.inverse() * d
	var yaw := atan2(l.x, l.z)
	if absf(yaw) > 1.0:
		return false
	_look_tgt = Vector2(clampf(yaw, -0.5, 0.5), clampf(atan2(l.y, Vector2(l.x, l.z).length()), -0.25, 0.2))
	return true
