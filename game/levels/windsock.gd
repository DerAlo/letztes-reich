extends Node3D
## Windsack (gemeinsam fuer "Kräne"/hafen_wind.gd und "Kaltes Auge"/overwatch_wind.gd).
## Aufbau wie an Haefen/Flugplaetzen: verzinkter Rohrmast mit Fussplatte und Abspannseilen (mount "pole")
## oder Ausleger an einem vorhandenen Mast (mount "bracket"), oben Drehlager, daran ein starres
## Buegelgestell (Ring + Hinterbuegel + Laengsstreben) und der konische Stoffschlauch (rot/weiss, 5 Baender).
## Form, Fuellung, Durchhang und Flattern rechnet windsock.gdshader; hier nur Gestell und Ausrichtung.
## Benutzung: Windsock.new(), opts setzen (siehe setup()), add_child, dann jedes Frame set_wind(weltvektor).
## Volle Streckung bei 15 kn (7,7 m/s) wie beim ICAO-Windsack: je Band etwa 3 kn.

const SHADER := preload("res://game/vfx/shaders/windsock.gdshader")
const FULL_SPEED := 7.7

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}
static var _steel: StandardMaterial3D
static var _galv: StandardMaterial3D
static var _wire: StandardMaterial3D

var sock_len: float = 2.4
var mouth_r: float = 0.25
var tail_r: float = 0.11
var mount: String = "pole"           ## "pole" = freistehender Mast, "bracket" = Ausleger
var pole_h: float = 6.0
var guys: bool = true
var arm: Vector3 = Vector3(1.0, 0.0, 0.0)   ## Ausleger: Versatz vom Ursprung zum Drehlager (horizontal)
var stub_h: float = 0.9                     ## Ausleger: Rohrstueck vom Arm hoch zum Drehlager
var glow: float = 0.0
var top_light: bool = false

var _pivot: Node3D
var _sock: MeshInstance3D
var _yaw: float = 0.0
var _yaw_v: float = 0.0
var _fill: float = 0.4
var _have_wind: bool = false

## opts: len, mouth_r, tail_r, mount, pole_h, guys, arm, stub_h, glow, top_light
func setup(opts: Dictionary) -> void:
	sock_len = float(opts.get("len", sock_len))
	mouth_r = float(opts.get("mouth_r", sock_len * 0.104))
	tail_r = float(opts.get("tail_r", mouth_r * 0.45))
	mount = str(opts.get("mount", mount))
	pole_h = float(opts.get("pole_h", pole_h))
	guys = bool(opts.get("guys", mount == "pole" and pole_h > 4.0))
	arm = opts.get("arm", arm)
	stub_h = float(opts.get("stub_h", stub_h))
	glow = float(opts.get("glow", glow))
	top_light = bool(opts.get("top_light", top_light))

func _ready() -> void:
	_make_shared()
	var top := _build_mount()
	_pivot = Node3D.new()
	_pivot.name = "Swivel"
	_pivot.position = top
	add_child(_pivot)
	_build_frame()
	_sock = MeshInstance3D.new()
	_sock.name = "Sock"
	_sock.mesh = _sock_mesh()
	_sock.material_override = _sock_mat()
	# Gestellachse liegt mouth_r ueber dem Drehlager; Ring etwas vor dem Lager (Sack haengt frei vom Mast)
	_sock.position = Vector3(0.0, mouth_r + 0.03, -sock_len * 0.04)
	_sock.extra_cull_margin = sock_len
	_sock.custom_aabb = AABB(Vector3(-sock_len, -sock_len - mouth_r, -mouth_r), Vector3(sock_len * 2.0, sock_len + mouth_r * 2.0, sock_len + mouth_r * 2.0))
	_pivot.add_child(_sock)
	_sock.set_instance_shader_parameter(&"phase", randf() * TAU)
	_sock.set_instance_shader_parameter(&"fill", _fill)

## Windvektor in Weltkoordinaten (m/s, Richtung = wohin er blaest).
func set_wind(w: Vector3, delta: float) -> void:
	var flat := Vector3(w.x, 0.0, w.z)
	var spd := flat.length()
	var goal_fill := clampf(spd / FULL_SPEED, 0.0, 1.0)
	if spd > 0.05:
		var goal := atan2(flat.x, flat.z)
		var rel_goal := goal - (global_rotation.y if is_inside_tree() else rotation.y)
		if not _have_wind:
			_yaw = rel_goal
			_fill = goal_fill
			_have_wind = true
		# Drehlager mit Traegheit und leichter Daempfung (pendelt bei Boeen kurz nach)
		var err := wrapf(rel_goal - _yaw, -PI, PI)
		_yaw_v += err * (6.0 + 6.0 * goal_fill) * delta
		_yaw_v *= exp(-delta * 3.2)
		_yaw += _yaw_v * delta
	_fill = move_toward(_fill, goal_fill, delta * (0.6 if goal_fill > _fill else 0.35))
	if _pivot != null:
		_pivot.rotation = Vector3(0.0, _yaw, 0.0)
	if _sock != null:
		_sock.set_instance_shader_parameter(&"fill", _fill)

# ------------------------------------------------------------------ Aufbau

static func _make_shared() -> void:
	if _steel != null:
		return
	_steel = StandardMaterial3D.new()
	_steel.albedo_color = Color(0.62, 0.63, 0.62)
	_steel.metallic = 0.85
	_steel.roughness = 0.42
	_galv = StandardMaterial3D.new()
	_galv.albedo_color = Color(0.55, 0.57, 0.58)
	_galv.metallic = 0.9
	_galv.roughness = 0.55
	_wire = StandardMaterial3D.new()
	_wire.albedo_color = Color(0.3, 0.31, 0.32)
	_wire.metallic = 0.8
	_wire.roughness = 0.5

func _sock_mat() -> ShaderMaterial:
	var key := "%.3f|%.3f|%.3f|%.3f" % [sock_len, mouth_r, tail_r, glow]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("sock_len", sock_len)
	m.set_shader_parameter("r0", mouth_r)
	m.set_shader_parameter("r1", tail_r)
	m.set_shader_parameter("frame_frac", 0.2)
	m.set_shader_parameter("glow", glow)
	_mats[key] = m
	return m

## Roh-Schlauch: UV.x = Umfang, UV.y = Laenge; Position nur fuer Vorschau/AABB (Shader formt neu).
func _sock_mesh() -> ArrayMesh:
	var key := "%.3f|%.3f|%.3f" % [sock_len, mouth_r, tail_r]
	if _meshes.has(key):
		return _meshes[key]
	const NU := 18
	const NV := 30
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in NV + 1:
		var v := float(j) / float(NV)
		var r := lerpf(mouth_r, tail_r, v)
		for i in NU + 1:
			var u := float(i) / float(NU)
			var th := u * TAU
			st.set_uv(Vector2(u, v))
			st.set_normal(Vector3(cos(th), sin(th), 0.0))
			st.add_vertex(Vector3(cos(th) * r, sin(th) * r, v * sock_len))
	for j in NV:
		for i in NU:
			var a := j * (NU + 1) + i
			var b := a + NU + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	var mesh := st.commit()
	_meshes[key] = mesh
	return mesh

func _cyl(parent: Node3D, r_top: float, r_bot: float, h: float, mat: Material, pos: Vector3, basis: Basis = Basis.IDENTITY, segs: int = 10) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r_top
	cm.bottom_radius = r_bot
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.transform = Transform3D(basis, pos)
	parent.add_child(mi)
	return mi

## Stab von a nach b (Rohr/Seil).
func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material, segs: int = 6) -> MeshInstance3D:
	var d := b - a
	var l := d.length()
	if l < 0.001:
		return null
	var y := d / l
	var x := y.cross(Vector3.FORWARD) if absf(y.dot(Vector3.FORWARD)) < 0.95 else y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	var mi := _cyl(parent, r, r, l, mat, (a + b) * 0.5, Basis(x, y, z), segs)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if r < 0.02 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func _ring(parent: Node3D, center: Vector3, r: float, tube: float, mat: Material) -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = r - tube
	tm.outer_radius = r + tube
	tm.rings = 28
	tm.ring_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.material_override = mat
	mi.position = center
	mi.rotation_degrees = Vector3(90.0, 0.0, 0.0)     # Ringebene senkrecht zur Sackachse (+Z)
	parent.add_child(mi)

## Mast bzw. Ausleger; gibt die Position des Drehlagers (lokal) zurueck.
func _build_mount() -> Vector3:
	if mount == "bracket":
		var a0 := Vector3.ZERO
		var a1 := Vector3(arm.x, 0.0, arm.z)
		# Schelle am Mast, Ausleger (Vierkant als Rohr), Stuetzstrebe, Rohrstueck nach oben
		_cyl(self, 0.09, 0.09, 0.22, _galv, a0, Basis.IDENTITY, 10)
		_rod(self, a0, a1, 0.035, _galv, 8)
		_rod(self, a0 + Vector3(0.0, -0.55, 0.0), a1 * 0.7, 0.022, _galv, 6)
		_rod(self, a1 + Vector3(0.0, -0.05, 0.0), a1 + Vector3(0.0, stub_h, 0.0), 0.03, _galv, 8)
		return a1 + Vector3(0.0, stub_h, 0.0)
	# Freistehender Mast: Fussplatte, konisches Rohr, Lager
	_cyl(self, 0.16, 0.16, 0.03, _galv, Vector3(0.0, 0.015, 0.0), Basis.IDENTITY, 12)
	_cyl(self, 0.034, 0.05, pole_h, _galv, Vector3(0.0, pole_h * 0.5, 0.0), Basis.IDENTITY, 10)
	if guys:
		# Drei Abspannseile auf 2/3 Hoehe, Erdanker als kleine Betonsockel
		var hk := pole_h * 0.68
		var rad := maxf(pole_h * 0.42, 1.2)
		var anchor_m := StandardMaterial3D.new()
		anchor_m.albedo_color = Color(0.45, 0.45, 0.43)
		anchor_m.roughness = 0.9
		_cyl(self, 0.055, 0.055, 0.08, _galv, Vector3(0.0, hk, 0.0), Basis.IDENTITY, 10)
		for k in 3:
			var ang := TAU * float(k) / 3.0 + 0.4
			var g := Vector3(cos(ang) * rad, 0.0, sin(ang) * rad)
			_rod(self, Vector3(0.0, hk, 0.0), g + Vector3(0.0, 0.12, 0.0), 0.005, _wire, 4)
			_cyl(self, 0.012, 0.012, 0.22, _galv, g + Vector3(0.0, 0.15, 0.0), Basis.IDENTITY, 6)
			var anc := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.3, 0.1, 0.3)
			anc.mesh = bm
			anc.material_override = anchor_m
			anc.position = g + Vector3(0.0, 0.05, 0.0)
			add_child(anc)
	return Vector3(0.0, pole_h, 0.0)

## Drehlager + Buegelgestell (dreht mit dem Wind).
func _build_frame() -> void:
	var p := _pivot
	# Lagergehaeuse am Mastkopf (steht still) und Drehteil
	_cyl(self, 0.05, 0.05, 0.12, _steel, _pivot.position + Vector3(0.0, -0.04, 0.0), Basis.IDENTITY, 10)
	var cy := mouth_r + 0.03
	var z0 := -sock_len * 0.04
	var z1 := z0 + sock_len * 0.2
	var r_back := lerpf(mouth_r, tail_r, 0.2)
	# Ringe: vorne (Einlauf) und hinterer Buegel
	_ring(p, Vector3(0.0, cy, z0), mouth_r + 0.008, 0.012, _steel)
	_ring(p, Vector3(0.0, cy, z1), r_back + 0.006, 0.009, _steel)
	# Laengsstreben oben/seitlich, Gabel hinunter zum Drehlager
	for ang in [PI * 0.5, 0.0, PI, PI * 1.25, PI * 1.75]:
		var o0 := Vector3(cos(ang) * mouth_r, sin(ang) * mouth_r + cy, z0)
		var o1 := Vector3(cos(ang) * r_back, sin(ang) * r_back + cy, z1)
		_rod(p, o0, o1, 0.008, _steel, 5)
	_rod(p, Vector3(0.0, 0.02, 0.0), Vector3(0.0, cy - mouth_r, z0), 0.014, _steel, 6)
	_rod(p, Vector3(0.0, 0.02, 0.0), Vector3(0.0, cy - r_back, z1), 0.012, _steel, 6)
	_cyl(p, 0.035, 0.035, 0.06, _steel, Vector3(0.0, 0.03, 0.0), Basis.IDENTITY, 8)
	if top_light:
		# Hindernisfeuer auf dem Mastkopf (rot, ohne eigene Lichtquelle)
		var red := StandardMaterial3D.new()
		red.albedo_color = Color(0.9, 0.1, 0.05)
		red.emission_enabled = true
		red.emission = Color(1.0, 0.1, 0.04)
		red.emission_energy_multiplier = 5.0
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.1
		s.mesh = sm
		s.material_override = red
		s.position = _pivot.position + Vector3(0.0, -0.18, 0.0)
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
