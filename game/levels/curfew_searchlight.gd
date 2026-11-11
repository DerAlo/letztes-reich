extends Node3D
## Suchscheinwerfer auf dem Dach (Level "curfew"): schwenkt zwischen zwei Winkeln, erfasst Kerner im
## Lichtkegel (mit Sichtpruefung) und loest nach kurzer Erfassung Alarm aus. Watcher fuer das HUD.

const BEAM_SHADER := preload("res://game/levels/curfew_beam.gdshader")
const Geo = preload("res://game/levels/level_geo.gd")

var director: Node
var yaw_a: float = 0.0
var yaw_b: float = 0.0
var pitch: float = -30.0
var sweep_speed: float = 0.18
var reach: float = 46.0
var cone: float = 9.0

var suspicion: float = 0.0
var _phase: float = 0.0
var _seen: bool = false
var _lock_t: float = 0.0
var _check_t: float = 0.0
var _pivot: Node3D
var light: SpotLight3D

func _ready() -> void:
	_build()
	if director != null:
		director.call("register_watcher", self)

func _build() -> void:
	var dark := Geo.flat(Color(0.06, 0.065, 0.07), 0.5, 0.6)
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.45
	bm.height = 0.5
	base.mesh = bm
	base.material_override = dark
	base.position.y = 0.25
	add_child(base)
	_pivot = Node3D.new()
	_pivot.position.y = 0.95
	add_child(_pivot)
	var yoke := MeshInstance3D.new()
	var ym := BoxMesh.new()
	ym.size = Vector3(1.05, 0.7, 0.12)
	yoke.mesh = ym
	yoke.material_override = dark
	yoke.position = Vector3(0, -0.15, 0)
	_pivot.add_child(yoke)
	var head := Node3D.new()
	head.name = "Head"
	_pivot.add_child(head)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.42
	dm.bottom_radius = 0.36
	dm.height = 0.9
	dm.radial_segments = 20
	drum.mesh = dm
	drum.material_override = dark
	drum.rotation_degrees.x = 90.0
	head.add_child(drum)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.38
	lm.bottom_radius = 0.38
	lm.height = 0.02
	lens.mesh = lm
	lens.material_override = BP_unshaded(Color(6.0, 5.6, 4.8))
	lens.rotation_degrees.x = 90.0
	lens.position.z = -0.46
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.add_child(lens)
	light = SpotLight3D.new()
	light.light_color = Color(0.92, 0.95, 1.0)
	light.light_energy = 26.0
	light.spot_range = reach + 6.0
	light.spot_angle = cone
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 0.4
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 1.4
	light.position.z = -0.5
	head.add_child(light)
	head.add_child(beam_mesh(reach, 0.35, tan(deg_to_rad(cone)) * reach, 0.05, Color(0.85, 0.9, 1.0)))

static func BP_unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m

## Weicher Lichtkegel entlang -Z (Spitze am Ursprung).
static func beam_mesh(length: float, r0: float, r1: float, strength: float, c: Color) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r0
	cm.bottom_radius = r1
	cm.height = length
	cm.radial_segments = 24
	cm.rings = 1
	cm.cap_top = false
	cm.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = BEAM_SHADER
	mat.set_shader_parameter("strength", strength)
	mat.set_shader_parameter("beam_color", c)
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = cm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.rotation_degrees.x = 90.0
	mi.position.z = -length / 2.0
	return mi

func _physics_process(delta: float) -> void:
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	var head := _pivot.get_node("Head") as Node3D
	if _seen and pl != null:
		# Kerner im Licht: Kegel folgt ihm
		var to := pl.global_position + Vector3.UP * 0.9 - head.global_position
		var want_yaw := atan2(-to.x, -to.z)
		var want_pitch := atan2(to.y, Vector2(to.x, to.z).length())
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, want_yaw - global_rotation.y, clampf(delta * 2.2, 0.0, 1.0))
		head.rotation.x = lerpf(head.rotation.x, want_pitch, clampf(delta * 2.2, 0.0, 1.0))
	else:
		_phase += delta * sweep_speed
		var t := 0.5 - 0.5 * cos(_phase * TAU)
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, deg_to_rad(lerpf(yaw_a, yaw_b, t)), clampf(delta * 1.5, 0.0, 1.0))
		head.rotation.x = lerpf(head.rotation.x, deg_to_rad(pitch), clampf(delta * 1.0, 0.0, 1.0))
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = 0.1
		_seen = _sees(pl, head)
	if _seen:
		_lock_t = 3.0
		var k := 0.7 if bool(pl.get("is_crouching")) else 1.0
		suspicion = minf(1.0, suspicion + 1.3 * k * delta)
		if suspicion >= 1.0 and director != null and not bool(director.get("alarm")):
			director.call("raise_alarm", pl.global_position, "searchlight", true)
	else:
		_lock_t = maxf(0.0, _lock_t - delta)
		suspicion = maxf(0.0, suspicion - 0.4 * delta)

func _sees(pl: Node3D, head: Node3D) -> bool:
	if pl == null or not bool(pl.call("is_alive")):
		return false
	var lp := light.global_position
	var target := pl.global_position + Vector3.UP * (0.6 if bool(pl.get("is_crouching")) else 1.0)
	var to := target - lp
	var d := to.length()
	if d > reach or d < 0.5:
		return false
	var fwd := -light.global_transform.basis.z
	if rad_to_deg(fwd.angle_to(to / d)) > cone * 0.85:
		return false
	var q := PhysicsRayQueryParameters3D.create(lp, target, 1)
	return head.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func get_suspicion() -> float:
	return suspicion

func get_watch_state() -> int:
	if _seen and suspicion >= 1.0:
		return 2
	return 1 if suspicion > 0.05 else 0

func get_watch_pos() -> Vector3:
	return global_position + Vector3.UP * 1.6

func is_watcher_alive() -> bool:
	return true
