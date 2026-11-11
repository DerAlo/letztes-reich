extends RefCounted
## Statische Effekt-Helfer fuer RailRide (per preload einbinden): Pintle-MG-Modell, Wassertreffer,
## Bug-Gischt und Kielwasser fuer Boote, kleine Wasserfontaenen.

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const VfxLib := preload("res://game/vfx/vfx_lib.gd")

static var _hit_pm: ParticleProcessMaterial
static var _hit_mat: Material
static var _big_pm: ParticleProcessMaterial
static var _spray_mat: Material

## Einfaches MG auf Schwenklafette (Fuss am mount_yaw, Waffe am mount_pitch).
static func build_pintle_mg(mount_yaw: Node3D, mount_pitch: Node3D) -> void:
	var steel := VF.mat("rr_gun_steel", Color(0.13, 0.135, 0.14), 0.45, 0.8)
	var dark := VF.mat("rr_gun_dark", Color(0.06, 0.06, 0.065), 0.6, 0.5)
	VF.mesh_node(mount_yaw, VF.cyl(0.05, 0.07, 0.9), steel, Vector3(0, -0.5, 0))
	VF.mesh_node(mount_yaw, VF.box(Vector3(0.18, 0.12, 0.25)), steel, Vector3(0, -0.06, 0))
	# Gehaeuse, Lauf mit Mantel, Kolben, Patronenkasten, Griffe
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.11, 0.13, 0.62)), dark, Vector3(0, 0.04, -0.12))
	VF.mesh_node(mount_pitch, VF.cyl(0.03, 0.03, 0.62), steel, Vector3(0, 0.05, -0.72), Vector3(90, 0, 0))
	VF.mesh_node(mount_pitch, VF.cyl(0.045, 0.045, 0.38), dark, Vector3(0, 0.05, -0.58), Vector3(90, 0, 0))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.07, 0.11, 0.26)), dark, Vector3(0, 0.0, 0.3))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.12, 0.14, 0.2)), VF.mat("rr_ammo", Color(0.2, 0.24, 0.16), 0.7, 0.2), Vector3(-0.13, -0.02, -0.08))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.03, 0.12, 0.03)), dark, Vector3(-0.09, -0.08, 0.22))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.03, 0.12, 0.03)), dark, Vector3(0.09, -0.08, 0.22))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.2, 0.025, 0.025)), dark, Vector3(0, -0.14, 0.22))
	# Visier (vorn Korn, hinten Kimme)
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.012, 0.05, 0.012)), dark, Vector3(0, 0.12, -0.95))
	VF.mesh_node(mount_pitch, VF.box(Vector3(0.05, 0.04, 0.012)), dark, Vector3(0, 0.13, 0.12))

static func _ensure() -> void:
	if _hit_pm != null:
		return
	_hit_pm = ParticleProcessMaterial.new()
	_hit_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_hit_pm.emission_sphere_radius = 0.15
	_hit_pm.direction = Vector3.UP
	_hit_pm.spread = 12.0
	_hit_pm.initial_velocity_min = 3.5
	_hit_pm.initial_velocity_max = 7.0
	_hit_pm.gravity = Vector3(0, -12.0, 0)
	_hit_pm.scale_min = 0.25
	_hit_pm.scale_max = 0.6
	_hit_pm.scale_curve = VfxLib.curve_tex([[0.0, 0.5], [0.3, 1.0], [1.0, 1.5]])
	_hit_pm.color = Color(0.8, 0.85, 0.9)
	_hit_pm.color_ramp = VfxLib.smoke_alpha_ramp(0.8, 0.05, 0.3)
	VfxLib.smoke_pm(_hit_pm, 20.0)
	_hit_mat = VfxLib.smoke_mat({"density": 1.4}, true)
	_big_pm = _hit_pm.duplicate() as ParticleProcessMaterial
	_big_pm.emission_sphere_radius = 0.8
	_big_pm.initial_velocity_min = 7.0
	_big_pm.initial_velocity_max = 15.0
	_big_pm.scale_min = 1.0
	_big_pm.scale_max = 2.4
	_spray_mat = VfxLib.smoke_mat({"density": 1.2}, true)

## Kleine Wasserfontaene (Geschosseinschlag).
static func water_hit(n: Node, pos: Vector3) -> void:
	if not n.is_inside_tree():
		return
	_ensure()
	var p := VfxLib.make_particles(6, 0.9, _hit_pm, VfxLib.quad(1.0), _hit_mat)
	p.one_shot = true
	p.explosiveness = 0.9
	VF.effects_root(n).add_child(p)
	p.global_position = pos
	p.emitting = true
	n.get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)

## Grosse Fontaene (Bootstreffer, versenktes Boot, Hubschrauberabsturz).
static func big_splash(n: Node, pos: Vector3, size: float = 1.0) -> void:
	if not n.is_inside_tree():
		return
	_ensure()
	var p := VfxLib.make_particles(int(26 * size), 2.2, _big_pm, VfxLib.quad(1.0), _hit_mat)
	p.one_shot = true
	p.explosiveness = 0.85
	p.scale = Vector3.ONE * size
	p.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 50, 40))
	VF.effects_root(n).add_child(p)
	p.global_position = pos
	p.emitting = true
	n.get_tree().create_timer(3.0, false).timeout.connect(p.queue_free)
	VF.play_at(n, "river_splash", pos, 2.0 + size * 2.0, 14.0 * size, 300.0, randf_range(0.85, 1.05))

## Dauer-Gischt fuer ein Boot: zwei Bugwellen-Emitter + Heck-Kielwasser. Rueckgabe: Liste der Emitter,
## Staerke per set_spray(list, 0..1) steuern. bow/stern: lokale Positionen am (nicht schaukelnden) Rumpf.
static func make_boat_spray(parent: Node3D, bow: Vector3, stern: Vector3, beam: float = 1.2) -> Array[GPUParticles3D]:
	_ensure()
	var out: Array[GPUParticles3D] = []
	for side in [-1.0, 1.0]:
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.15, 0.1, 0.6)
		pm.direction = Vector3(side * 1.0, 0.9, 0.35).normalized()
		pm.spread = 18.0
		pm.initial_velocity_min = 3.0
		pm.initial_velocity_max = 6.5
		pm.gravity = Vector3(0, -9.0, 0)
		pm.damping_min = 0.4
		pm.damping_max = 1.0
		pm.scale_min = 0.5
		pm.scale_max = 1.3
		pm.scale_curve = VfxLib.curve_tex([[0.0, 0.4], [0.4, 1.0], [1.0, 1.8]])
		pm.color = Color(0.78, 0.83, 0.88)
		pm.color_ramp = VfxLib.smoke_alpha_ramp(0.7, 0.08, 0.3)
		VfxLib.smoke_pm(pm, 15.0)
		var p := VfxLib.make_particles(48, 1.1, pm, VfxLib.quad(1.0), _spray_mat)
		p.one_shot = false
		p.explosiveness = 0.0
		p.local_coords = false
		p.position = bow + Vector3(side * beam * 0.55, 0.0, 0.0)
		p.visibility_aabb = AABB(Vector3(-15, -4, -15), Vector3(30, 14, 30))
		parent.add_child(p)
		p.emitting = true
		out.append(p)
	var wm := ParticleProcessMaterial.new()
	wm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	wm.emission_box_extents = Vector3(beam * 0.5, 0.05, 0.3)
	wm.direction = Vector3(0, 0.6, 1.0).normalized()
	wm.spread = 25.0
	wm.initial_velocity_min = 1.5
	wm.initial_velocity_max = 4.0
	wm.gravity = Vector3(0, -3.0, 0)
	wm.damping_min = 0.8
	wm.damping_max = 1.6
	wm.scale_min = 1.0
	wm.scale_max = 2.4
	wm.scale_curve = VfxLib.curve_tex([[0.0, 0.5], [1.0, 2.2]])
	wm.color = Color(0.85, 0.88, 0.92)
	wm.color_ramp = VfxLib.smoke_alpha_ramp(0.55, 0.05, 0.35)
	VfxLib.smoke_pm(wm, 8.0)
	var w := VfxLib.make_particles(70, 2.6, wm, VfxLib.quad(1.0), _spray_mat)
	w.one_shot = false
	w.explosiveness = 0.0
	w.local_coords = false
	w.position = stern
	w.visibility_aabb = AABB(Vector3(-20, -4, -30), Vector3(40, 12, 60))
	parent.add_child(w)
	w.emitting = true
	out.append(w)
	return out

static func set_spray(list: Array[GPUParticles3D], strength: float) -> void:
	for p in list:
		if not is_instance_valid(p):
			continue
		p.emitting = strength > 0.05
		p.amount_ratio = clampf(strength, 0.0, 1.0)
		p.speed_scale = lerpf(0.6, 1.2, clampf(strength, 0.0, 1.0))
