extends Node3D
## Mission "Kräne": boeiger Seewind fuer die Ballistik (Level.sniper_wind()) und sichtbare Hinweise:
## Windfahnen an den Lichtmasten/am Kran richten sich aus und flattern, Regen treibt mit (Weather.wind).
## Grundwind von Westsued (blaest nach Ostnord), Boeen aus Rauschen: +-35 % Staerke, +-15 Grad Richtung.

const BASE_DIR := Vector3(0.92, 0.0, -0.38)
const BASE_SPEED := 4.2            ## m/s -> auf 250 m gut 1 mil Abdrift
const GUST_AMP := 0.35
const GUST_DIR := 0.26
const FLAG_FULL := 8.0

var weather: Node = null
var _t: float = 0.0
var _noise := FastNoiseLite.new()
var _cur := BASE_DIR.normalized() * BASE_SPEED
var _flags: Array = []             ## {pivot: Node3D, cloth: Node3D, ph: float}

func _ready() -> void:
	_noise.seed = 4711
	_noise.frequency = 0.05

func current() -> Vector3:
	return _cur

func strength() -> float:
	return _cur.length()

func _process(delta: float) -> void:
	_t += delta
	var g := _noise.get_noise_1d(_t * 6.0)
	var d := _noise.get_noise_1d(_t * 4.0 + 300.0)
	var dir := BASE_DIR.normalized().rotated(Vector3.UP, d * GUST_DIR * 2.0)
	_cur = dir * BASE_SPEED * (1.0 + g * GUST_AMP * 2.0)
	if weather != null and is_instance_valid(weather):
		weather.set("wind", _cur * 0.9)
	var yaw := atan2(-_cur.x, -_cur.z)
	var k := clampf(_cur.length() / FLAG_FULL, 0.2, 1.0)
	for f: Dictionary in _flags:
		var pv: Node3D = f["pivot"]
		if not is_instance_valid(pv):
			continue
		var ph: float = f["ph"]
		pv.global_rotation = Vector3(0, yaw + PI * 0.5 + sin(_t * 7.0 + ph) * 0.12 * k, 0)
		var cl: Node3D = f["cloth"]
		cl.rotation = Vector3(0, sin(_t * 11.0 + ph) * 0.25 * k, (1.0 - k) * 1.1)

## Windfahne (Wimpel) an Weltpunkt top. Rot-weiss, gut im Zielfernrohr zu sehen.
func add_flag(parent: Node3D, top: Vector3) -> void:
	var pv := Node3D.new()
	parent.add_child(pv)
	pv.global_position = top
	var cl := Node3D.new()
	pv.add_child(cl)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.2, 0.12)
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.2, 0.12)
	mat.emission_energy_multiplier = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mat2 := mat.duplicate() as StandardMaterial3D
	mat2.albedo_color = Color(0.9, 0.9, 0.88)
	mat2.emission = Color(0.9, 0.9, 0.88)
	for i in 3:
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.55, 0.5 - i * 0.1)
		q.mesh = qm
		q.material_override = mat if i % 2 == 0 else mat2
		q.position = Vector3(0.28 + i * 0.55, -0.3, 0)
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cl.add_child(q)
	_flags.append({"pivot": pv, "cloth": cl, "ph": randf() * 6.0})
