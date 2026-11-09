class_name Launcher
extends Weapon
## Panzerfaust 3 (Slot 3): verschießt eine Rakete (Projektil) statt eines Hitscan-Schusses.
## Gegenwirkmasse nach hinten: Rückstrahl-Staub hinter dem Spieler.

@export var rocket_speed: float = 72.0

func _shoot(cam: Camera3D, spread_deg: float) -> void:
	var b: Basis = cam.global_basis
	var dir: Vector3 = -b.z
	if spread_deg > 0.0:
		var r: float = tan(deg_to_rad(spread_deg)) * sqrt(randf())
		var a: float = randf() * TAU
		dir = (dir + b.x * cos(a) * r + b.y * sin(a) * r).normalized()
	# Start knapp vor der Kamera; Ziel exakt auf der Kameraachse halten
	var from: Vector3 = cam.global_position + dir * 0.9 + b.x * 0.08 - b.y * 0.04
	var exclude: Array[RID] = []
	if owner_player:
		exclude.append(owner_player.get_rid())
	# Wand direkt vor der Nase: an der Kamera starten, damit die Rakete nicht hindurchtunnelt
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, from, 1 | 4, exclude)
	if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		from = cam.global_position + dir * 0.1
	Rocket.launch(_world_root(), from, dir, rocket_speed, owner_player)
	_backblast(cam)

func _backblast(cam: Camera3D) -> void:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 25.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 9.0
	pm.damping_min = 4.0
	pm.damping_max = 7.0
	pm.gravity = Vector3(0, 0.4, 0)
	pm.scale_min = 0.8
	pm.scale_max = 2.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.5, 0.8))
	ramp.add_point(0.1, Color(0.7, 0.68, 0.62, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.58, 0.55, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	p.process_material = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	var qm := QuadMesh.new()
	qm.size = Vector2(0.8, 0.8)
	qm.material = mat
	p.draw_pass_1 = qm
	p.amount = 40
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world_root().add_child(p)
	p.global_transform = Transform3D(cam.global_basis, cam.global_position + cam.global_basis.z * 0.9 + cam.global_basis.x * 0.15)
	p.emitting = true
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
