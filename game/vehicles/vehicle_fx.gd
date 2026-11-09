extends RefCounted
## Gemeinsame Helfer fuer Fahrzeuge (statisch, per preload() einbinden).
## Materialien, Leuchtspuren, Muendungsfeuer, Sound-Loops, Boden-Raycasts.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4
const LAYER_DEBRIS := 8

static var _mats: Dictionary = {}
static var _tracer_mesh: Mesh
static var _tracer_mats: Dictionary = {}
static var _flash_tex: Texture2D

# ------------------------------------------------------------------ Materialien

## PBR-Material mit leichtem Detail-Rauschen (Kantenverschleiss ueber Rauheit). Gecacht nach Schluessel.
static func mat(key: String, albedo: Color, rough: float = 0.6, metal: float = 0.3, emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.45
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mats[key] = m
	return m

## Tarnmuster (3 Farben, harte Flecken) als triplanare Albedo, dazu Schmutz ueber Rauheit.
static func camo_mat(key: String, c1: Color, c2: Color, c3: Color, scale: float = 0.35, rough: float = 0.72) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.0065
	n.fractal_octaves = 3
	n.seed = key.hash()
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	g.offsets = PackedFloat32Array([0.0, 0.42, 0.6])
	g.colors = PackedColorArray([c1, c2, c3])
	tex.color_ramp = g
	var rn := FastNoiseLite.new()
	rn.frequency = 0.05
	rn.seed = key.hash() + 7
	var rtex := NoiseTexture2D.new()
	rtex.width = 256
	rtex.height = 256
	rtex.seamless = true
	rtex.noise = rn
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness = rough
	m.roughness_texture = rtex
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.metallic = 0.25
	m.metallic_specular = 0.4
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.uv1_triplanar_sharpness = 2.0
	_mats[key] = m
	return m

## Glas (Cockpit), leicht getoent, spiegelnd.
static func glass_mat(tint: Color = Color(0.12, 0.16, 0.18, 0.55)) -> StandardMaterial3D:
	var key := "glass_%s" % tint.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.6
	m.metallic_specular = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m

## Verkohlt: dunkles Overlay fuer Wracks (material_overlay).
static func charred_overlay() -> StandardMaterial3D:
	if _mats.has("charred"):
		return _mats["charred"]
	var n := FastNoiseLite.new()
	n.frequency = 0.03
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = n
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.018, 0.016, 0.95), Color(0.05, 0.04, 0.035, 0.85), Color(0.12, 0.08, 0.05, 0.7)])
	tex.color_ramp = g
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.6
	_mats["charred"] = m
	return m

static func char_all(root: Node) -> void:
	var ov := charred_overlay()
	for c in root.find_children("*", "GeometryInstance3D", true, false):
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_overlay = ov

## Fasst statische Meshes zu einem Mesh je Material zusammen (weniger Draw Calls).
## Jeder Knoten in `keep` (und alles darunter) bleibt unangetastet (bewegliche Teile, Referenzen).
## Ein Unterknoten, der selbst Kinder in `keep` hat, wird nicht entfernt, nur seine Meshes.
## Ausgelassen: ShaderMaterials (Instanz-Uniforms), transparente Materialien.
static func merge_static(root: Node3D, keep: Array) -> void:
	var keep_set := {}
	for k in keep:
		if k is Node:
			keep_set[k] = true
		elif k is Array:
			for kk in k:
				if kk is Node:
					keep_set[kk] = true
	var groups := {}   # Material -> Array[MeshInstance3D]
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			if keep_set.has(c):
				continue
			stack.append(c)
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				var m := mi.material_override
				if m == null or m is ShaderMaterial or mi.mesh == null:
					continue
				if m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				if not groups.has(m):
					groups[m] = []
				groups[m].append(mi)
	var inv := root.global_transform.affine_inverse() if root.is_inside_tree() else Transform3D.IDENTITY
	for m in groups:
		var list: Array = groups[m]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi: MeshInstance3D in list:
			var xf := _rel_xform(root, mi, inv)
			for s in mi.mesh.get_surface_count():
				st.append_from(mi.mesh, s, xf)
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = st.commit()
		merged.material_override = m
		root.add_child(merged)
		for mi: MeshInstance3D in list:
			mi.get_parent().remove_child(mi)
			mi.free()

static func _rel_xform(root: Node3D, n: Node3D, inv: Transform3D) -> Transform3D:
	if root.is_inside_tree():
		return inv * n.global_transform
	var xf := n.transform
	var p := n.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

# ------------------------------------------------------------------ Mesh-Bausteine

static func mesh_node(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi

static func box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

static func cyl(top: float, bottom: float, h: float, seg: int = 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = seg
	c.rings = 1
	return c

static func sphere(r: float, h: float = -1.0, seg: int = 24) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = seg
	s.rings = maxi(seg / 2, 6)
	return s

static func capsule(r: float, h: float, seg: int = 20) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = seg
	c.rings = 6
	return c

## Prisma (Keil) fuer geneigte Panzerplatten.
static func prism(size: Vector3, left_to_right: float = 0.5) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	p.left_to_right = left_to_right
	return p

# ------------------------------------------------------------------ Effekte

static func effects_root(n: Node) -> Node:
	var cs := n.get_tree().current_scene
	return cs if cs != null else n.get_tree().root

## Leuchtspur von from nach to (dick, gut sichtbar). color: "red" | "green" | "orange".
static func tracer(n: Node, from: Vector3, to: Vector3, speed: float = 260.0, color: String = "red", width: float = 1.0) -> void:
	var length := from.distance_to(to)
	if length < 0.8 or not n.is_inside_tree():
		return
	if _tracer_mesh == null:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.06, 0.06, 3.2)
		_tracer_mesh = bm
	if not _tracer_mats.has(color):
		var c := Color(1.0, 0.25, 0.12)
		if color == "green":
			c = Color(0.35, 1.0, 0.3)
		elif color == "orange":
			c = Color(1.0, 0.62, 0.2)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 9.0
		_tracer_mats[color] = m
	var mi := MeshInstance3D.new()
	mi.mesh = _tracer_mesh
	mi.material_override = _tracer_mats[color]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(width, width, 1.0)
	effects_root(n).add_child(mi)
	var dir := (to - from) / length
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	mi.global_transform = Transform3D(Basis.looking_at(dir, up).scaled(Vector3(width, width, 1.0)), from + dir * 1.6)
	var tw := mi.create_tween()
	tw.tween_property(mi, "global_position", to - dir * 1.6, maxf(length - 3.2, 0.1) / speed)
	tw.tween_callback(mi.queue_free)

## Muendungsfeuer-Knoten (Stern-Quads + Licht). show_flash(node, energy) blitzt ihn kurz auf.
static func make_muzzle_flash(parent: Node3D, size: float = 1.0, light_energy: float = 6.0, light_range: float = 8.0) -> Node3D:
	var root := Node3D.new()
	root.name = "MuzzleFlash"
	parent.add_child(root)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = flash_texture()
	m.albedo_color = Color(1.0, 0.75, 0.4)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_keep_scale = true
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0) * size
	# Laengs-Quads (Kreuz) + ein Front-Billboard
	for r in [0.0, 90.0]:
		var mi := MeshInstance3D.new()
		var ql := QuadMesh.new()
		ql.size = Vector2(0.9, 2.2) * size
		mi.mesh = ql
		mi.material_override = m
		mi.rotation_degrees = Vector3(90, 0, r)
		mi.position = Vector3(0, 0, -0.9 * size)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var bm := m.duplicate() as StandardMaterial3D
	bm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var front := MeshInstance3D.new()
	front.mesh = q
	front.material_override = bm
	front.scale = Vector3.ONE * 1.3
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(front)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.65, 0.3)
	l.omni_range = light_range
	l.light_energy = light_energy
	l.shadow_enabled = false
	l.position = Vector3(0, 0, -0.5 * size)
	l.set_meta("energy", light_energy)
	root.add_child(l)
	root.visible = false
	return root

static func show_flash(flash: Node3D, duration: float = 0.05) -> void:
	if flash == null:
		return
	flash.visible = true
	flash.rotation.z = randf() * TAU
	flash.scale = Vector3.ONE * randf_range(0.8, 1.25)
	var tw := flash.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(func() -> void: flash.visible = false)

## Weiche Stern-Textur fuer Muendungsfeuer (prozedural, gecacht).
static func flash_texture() -> Texture2D:
	if _flash_tex != null:
		return _flash_tex
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5) / float(s) * 2.0 - Vector2.ONE
			var r := p.length()
			var a := atan2(p.y, p.x)
			var star := pow(absf(cos(a * 3.0)), 6.0) * 0.5 + 0.5
			var v := clampf(1.0 - r / (0.35 + 0.65 * star), 0.0, 1.0)
			v = v * v
			var core := clampf(1.0 - r * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, lerpf(0.55, 1.0, core), lerpf(0.2, 0.9, core), v))
	_flash_tex = ImageTexture.create_from_image(img)
	return _flash_tex

# ------------------------------------------------------------------ Sound

## Geloopter 3D-Sound (Datei assets/sfx/<name>.ogg). Gibt null zurueck, wenn die Datei fehlt.
static func loop_player(parent: Node3D, sfx_name: String, unit_size: float = 12.0, max_dist: float = 300.0, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var st := Sfx.get_stream(sfx_name)
	if st == null:
		return null
	st = st.duplicate() as AudioStream
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamWAV:
		(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = &"SFX"
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.volume_db = volume_db
	p.attenuation_filter_cutoff_hz = 9000.0
	parent.add_child(p)
	p.play(randf() * 2.0)
	return p

## One-Shot an Position (eigener Player, damit Reichweite/Lautstaerke frei waehlbar sind).
static func play_at(n: Node, sfx_name: String, pos: Vector3, volume_db: float = 0.0, unit_size: float = 15.0, max_dist: float = 400.0, pitch: float = 1.0, bus: StringName = &"SFX") -> AudioStreamPlayer3D:
	var st := Sfx.get_stream(sfx_name)
	if st == null or not n.is_inside_tree():
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = st
	p.bus = bus
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.volume_db = volume_db
	p.pitch_scale = pitch
	effects_root(n).add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p

## 2D-One-Shot (z. B. Donner, Ueberschallknall), optional verzoegert.
static func play_2d(n: Node, sfx_name: String, volume_db: float = 0.0, delay: float = 0.0, bus: StringName = &"SFX", pitch: float = 1.0) -> void:
	var st := Sfx.get_stream(sfx_name)
	if st == null or not n.is_inside_tree():
		return
	var root := effects_root(n)
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = bus
	p.volume_db = volume_db
	p.pitch_scale = pitch
	root.add_child(p)
	p.finished.connect(p.queue_free)
	if delay > 0.0:
		root.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
			if is_instance_valid(p):
				p.play())
	else:
		p.play()

# ------------------------------------------------------------------ Welt

static func ray(n: Node3D, from: Vector3, to: Vector3, mask: int = LAYER_WORLD, exclude: Array[RID] = []) -> Dictionary:
	if not n.is_inside_tree():
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, exclude)
	return n.get_world_3d().direct_space_state.intersect_ray(q)

static func camera(n: Node) -> Camera3D:
	return n.get_viewport().get_camera_3d() if n.is_inside_tree() else null

## Kamera-Shake beim Spieler nach Distanz (ohne Events.explosion, damit Gegner nicht reagieren).
static func shake_player(n: Node, pos: Vector3, strength: float, radius: float) -> void:
	var pl := n.get_tree().get_first_node_in_group("player") as Node3D
	if pl == null or not pl.has_method("add_trauma"):
		return
	var d := pl.global_position.distance_to(pos)
	if d < radius:
		pl.call("add_trauma", strength * (1.0 - d / radius))
