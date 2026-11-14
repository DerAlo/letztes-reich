extends Node3D
## Mission "Nachtzug": der Zug (statisch entlang -z bei x = 0) und die vorbeiziehende Nachtlandschaft.
## Der Zug steht still, die Welt scrollt mit `speed` nach +z: Boden-Shader (Felder, Schotter, Schwellen),
## Oberleitungsmasten, Landschafts-Chunks (Nadelwald, Dörfer, ferne Lichter) und Ereignisse
## (Tunnel, Brücke, Bahnübergang, Bahnhof). Kollision des Zugs: ein StaticBody "TrainCol" unter der
## NavigationRegion (Meta no_fit), Türen als eigene Körper (geschlossen ins Navmesh gebacken).
##
## Waggons (Heck -> Front): W1 Abteilwagen, W2 Speisewagen, W3 Gepäckwagen, W4/W5 (nur Hülle, begehbares
## Dach), W6 Schlafwagen, dann W7 + Lok als Knoten `front` (ohne Kollision, wird im Finale abgekoppelt).

const VF := preload("res://game/vehicles/vehicle_fx.gd")
const Geo := preload("res://game/levels/level_geo.gd")
const NP := preload("res://game/levels/night_props.gd")
const TrackTrees := preload("res://game/levels/track_trees.gd")
const Int := preload("res://game/levels/nachtzug_interior.gd")
const Deco := preload("res://game/levels/nachtzug_table_deco.gd")
const FKit := preload("res://game/levels/facade_kit.gd")
const MOUNTAIN_SHADER := preload("res://assets/environment/train/mountains_night.gdshader")

const PITCH := 27.5
const CAR_LEN := 26.0
const FLOOR := 1.2
const CEIL := 3.7
const ROOF := 4.1
const HW := 1.8          ## halbe Aussenbreite
const IW := 1.7          ## halbe Innenbreite
const DOOR_HW := 0.7
const DOOR_H := 2.15
const WIRE_Y := 6.6
const TRACK2_X := -4.4
const CRUISE := 33.0
const WIN_LO := 0.9      ## Fensterband ueber dem Wagenboden
const WIN_HI := 1.85
const MAST_N := 14
const MAST_GAP := 60.0
const MAST_FRONT := 200.0          ## Masten zwischen +200 und -640
const CHUNK_N := 8
const CHUNK_LEN := 100.0
const CHUNK_FRONT := 200.0         ## Chunks zwischen +200 und -600
const EVENT_SPAWN_Z := -700.0
const TUNNEL_TOP := 5.6            ## Scheitel der Tunnelroehre ueber der Schiene
const CARGO_Z := -68.0
const CARGO_HW := 1.6
const CARGO_TOP := 3.5
const STATIONS := ["JENBACH", "BISCHOFSHOFEN", "VÖCKLABRUCK", "AMSTETTEN", "ST. PÖLTEN"]

static func car_rear(i: int) -> float:
	return -float(i) * PITCH

static func car_front(i: int) -> float:
	return car_rear(i) - CAR_LEN

var level: Node = null
var env: Environment = null
var moon: DirectionalLight3D = null
var sky_mat: ProceduralSkyMaterial = null

var speed: float = CRUISE
var target_speed: float = CRUISE
var accel: float = 1.85
var scroll: float = 0.0
var wind_level: float = 0.0        ## 0 innen, 1 auf dem Dach (vom Level gesetzt)
var tunnel_factor: float = 0.0     ## Kamera im Tunnel (geglaettet)
var auto_events: bool = true
var auto_tunnels: bool = true
var flicker_boost: float = 0.0

var col: StaticBody3D                      ## Zug-Kollision (unter world)
var doors: Array[StaticBody3D] = []        ## 0..2: Front W1..W3, 3: Front W6, 4: Seitentuer W3
var door_open_off: Array[Vector3] = []
var front: Node3D                          ## W7 + Lok (ohne Kollision)
var weber_spot: Vector3 = Vector3(0, FLOOR, car_rear(6) - 1.0)
var tunnels: Array[Dictionary] = []        ## {node, z, len, killed, entered}
var events: Array[Dictionary] = []         ## {node, len, kind}
var scrollers: Array[Node3D] = []          ## Fremdknoten, die mit der Landschaft zurueckfallen (Wrack)

var _mats: Dictionary = {}
var _ground_mat: ShaderMaterial
var _masts: Array[Node3D] = []
var _chunks: Array[Node3D] = []
var _lights: Array[Dictionary] = []        ## {l, e}
var _clack_acc: float = 0.0
var _event_t: float = 14.0
var _station_i: int = 0
var _rail_snd: AudioStreamPlayer
var _wind_snd: AudioStreamPlayer
var _spark_light: OmniLight3D
var _spark_fx: GPUParticles3D
var _spark_t: float = 1.0
var _spark_on: float = 0.0
var _rng := RandomNumberGenerator.new()
var _cam_in_tunnel: bool = false
var _dot_mesh: Mesh
var _crossing_lights: Array[Dictionary] = []
var _t: float = 0.0
var decoupled: bool = false

# ================================================================== Aufbau

func build(lv: Node, region: Node3D, seed_v: int) -> void:
	level = lv
	_rng.seed = seed_v
	name = "Nachtzug"
	_make_mats()
	col = StaticBody3D.new()
	col.name = "TrainCol"
	col.collision_layer = 1
	col.collision_mask = 0
	col.set_meta("no_fit", true)
	col.set_meta("surface", "metal")
	region.add_child(col)
	var rails := StaticBody3D.new()       # Dach-Gelaender (unsichtbar, nur Bewegung)
	rails.name = "RoofRails"
	rails.collision_layer = 16
	rails.collision_mask = 0
	rails.set_meta("no_fit", true)
	region.add_child(rails)
	for i in 6:
		_build_car(i, rails)
	for i in 6:
		_build_gangway(i)
	# Kupplung W6/W7: W7 hat keine Kollision -> unsichtbare Sperre auf Layer 16
	var bar := StaticBody3D.new()
	bar.name = "CouplingBarrier"
	bar.collision_layer = 16
	bar.collision_mask = 0
	bar.set_meta("no_fit", true)
	region.add_child(bar)
	Geo.add_box_shape(bar, Vector3(0, 2.5, car_rear(6) + 0.05), Vector3(3.6, 5.0, 0.2))
	_build_doors(region)
	_build_front()
	_build_track()
	_build_masts()
	_build_sky()
	_build_chunks()
	_build_ground_collider()
	_build_audio()

func _make_mats() -> void:
	_mats["body"] = Geo.flat(Color(0.07, 0.11, 0.24), 0.45, 0.35)
	_mats["stripe"] = Geo.flat(Color(0.78, 0.7, 0.5), 0.5, 0.1)
	_mats["roof"] = Geo.flat(Color(0.2, 0.21, 0.22), 0.55, 0.6)
	_mats["under"] = Geo.flat(Color(0.05, 0.05, 0.05), 0.8, 0.4)
	_mats["lining"] = Geo.flat(Color(0.6, 0.53, 0.42), 0.7)
	_mats["wood"] = Geo.flat(Color(0.32, 0.18, 0.09), 0.55)
	_mats["floor"] = Geo.flat(Color(0.2, 0.08, 0.07), 0.95)
	_mats["ceil"] = Geo.flat(Color(0.72, 0.71, 0.67), 0.8)
	_mats["lamp"] = Geo.flat(Color(1.0, 0.85, 0.6), 0.5, 0.0, Color(1.0, 0.82, 0.55), 1.0)
	_mats["seat"] = Geo.flat(Color(0.11, 0.17, 0.32), 0.9)
	_mats["cloth"] = Geo.flat(Color(0.85, 0.84, 0.8), 0.9)
	_mats["crate"] = Geo.flat(Color(0.38, 0.28, 0.16), 0.85)
	_mats["case"] = Geo.flat(Color(0.18, 0.2, 0.22), 0.5, 0.6)
	_mats["steel"] = Geo.flat(Color(0.3, 0.3, 0.32), 0.4, 0.8)
	_mats["rail"] = Geo.flat(Color(0.5, 0.5, 0.52), 0.3, 0.9)
	_mats["glass"] = VF.glass_mat(Color(0.1, 0.12, 0.15, 0.2))
	_mats["lit"] = Geo.flat(Color(0.9, 0.75, 0.45), 0.6, 0.0, Color(1.0, 0.78, 0.45), 1.6)
	_mats["bellow"] = Geo.flat(Color(0.08, 0.08, 0.09), 0.95)
	_mats["loco"] = Geo.flat(Color(0.45, 0.07, 0.06), 0.45, 0.35)
	_mats["head"] = Geo.flat(Color(1, 1, 0.95), 0.3, 0.0, Color(1, 0.97, 0.85), 5.0)
	_mats["rock"] = Geo.flat(Color(0.1, 0.1, 0.11), 0.95)
	_mats["concrete"] = Geo.mat("concrete_wall_008", Color(0.42, 0.42, 0.44), 0.25)
	_mats["tree"] = Geo.flat(Color(0.035, 0.06, 0.045), 0.95)
	_mats["house"] = Geo.flat(Color(0.5, 0.48, 0.44), 0.9)
	_mats["tile"] = Geo.flat(Color(0.22, 0.1, 0.08), 0.85)
	_mats["win"] = Geo.flat(Color(1.0, 0.8, 0.45), 0.6, 0.0, Color(1.0, 0.75, 0.4), 3.0)
	_mats["dot"] = Geo.flat(Color(1.0, 0.82, 0.55), 0.6, 0.0, Color(1.0, 0.8, 0.5), 6.0)
	_mats["water"] = Geo.flat(Color(0.02, 0.03, 0.05), 0.05, 0.6)
	_mats["asphalt"] = Geo.mat("asphalt_02", Color(0.4, 0.4, 0.42), 0.3)
	_mats["red"] = Geo.flat(Color(1, 0.1, 0.05), 0.5, 0.0, Color(1, 0.1, 0.05), 6.0)
	_mats["note"] = Geo.flat(Color(0.92, 0.9, 0.82), 0.9)
	# Innenraum: PBR-Furnier, Paneele, Teppich, Polster (nachtzug_interior.gd)
	_mats.merge(Int.mats(), true)
	_mats["lining"] = _mats["veneer"]
	_mats["upper"] = _mats["panel"]
	_mats["ceil"] = Int.pbr("res://assets/environment/villa/beige_wall_001", Color(0.86, 0.85, 0.8), 0.8, 0.6, 0.0, 0.25)
	_mats["floor"] = _mats["carpet"]
	_mats["seat"] = _mats["moquette"]
	_mats["wood"] = _mats["veneer_dark"]
	_mats["cloth"] = _mats["linen"]
	_mats["crate"] = _mats["planks"]

func _m(k: String) -> Material:
	return _mats[k]

func _mesh(b: Geo.BoxBatch, mat: String, parent: Node3D = null, shadows: bool = true) -> MeshInstance3D:
	var mesh := b.build()
	if mesh == null:
		return null
	var mi := Geo.mesh_node(mesh, _m(mat), Vector3.ZERO, shadows)
	(parent if parent != null else self).add_child(mi)
	return mi

func _col(body: CollisionObject3D, c: Vector3, s: Vector3) -> void:
	Geo.add_box_shape(body, c, s)

func _light(parent: Node3D, pos: Vector3, color: Color, energy: float, rng_m: float, flicker: bool = true) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng_m
	l.omni_attenuation = 1.4
	# Innenlampen streuen kaum in den Volumennebel (sonst milchiger Schleier im Waggon)
	l.light_volumetric_fog_energy = 0.08
	l.shadow_enabled = false
	l.position = pos
	parent.add_child(l)
	if flicker:
		_lights.append({"l": l, "e": energy})
	return l

## Fensterliste [z_mitte, breite] je Waggontyp und Seite.
func _windows(kind: String, i: int, side: int) -> Array:
	var zr := car_rear(i)
	var out: Array = []
	match kind:
		"abteil":
			for k in 8:
				out.append([zr - 2.0 - 2.75 * (k + 0.5), 1.7])
		"schlaf":
			for k in 9:
				out.append([zr - 2.0 - 2.2 * (k + 0.5), 1.3 if side < 0 else 1.5])
		"speise":
			for k in 6:
				out.append([zr - 2.6 - 2.3 * k, 1.5])
			if side > 0:
				out.append([zr - 17.5, 1.2])
		"gepaeck":
			for zc: float in [zr - 4.0, zr - 22.0]:
				out.append([zc, 0.9])
			if side < 0:
				out.append([zr - 13.0, 0.9])
		_:
			for k in 9:
				out.append([zr - 2.6 - 2.6 * k, 1.5])
	return out

## Wandstreifen x = const zwischen y0..y1 und z za (hinten) .. zb (vorn); cut: Ladetuer-Ausschnitt aussparen.
func _skin(b: Geo.BoxBatch, x: float, y0: float, y1: float, za: float, zb: float, cut: bool) -> void:
	var c0 := CARGO_Z + CARGO_HW
	var c1 := CARGO_Z - CARGO_HW
	if not cut or za <= c1 or zb >= c0 or y1 <= FLOOR or y0 >= CARGO_TOP:
		b.add(Vector3(x, (y0 + y1) * 0.5, (za + zb) * 0.5), Vector3(0.04, y1 - y0, za - zb))
		return
	if za > c0:
		b.add(Vector3(x, (y0 + y1) * 0.5, (za + c0) * 0.5), Vector3(0.04, y1 - y0, za - c0))
	if zb < c1:
		b.add(Vector3(x, (y0 + y1) * 0.5, (c1 + zb) * 0.5), Vector3(0.04, y1 - y0, c1 - zb))
	var z0 := minf(za, c0)
	var z1 := maxf(zb, c1)
	if y1 > CARGO_TOP:
		var ya := maxf(y0, CARGO_TOP)
		b.add(Vector3(x, (ya + y1) * 0.5, (z0 + z1) * 0.5), Vector3(0.04, y1 - ya, z0 - z1))
	if y0 < FLOOR:
		var yb := minf(y1, FLOOR)
		b.add(Vector3(x, (y0 + yb) * 0.5, (z0 + z1) * 0.5), Vector3(0.04, yb - y0, z0 - z1))

func _build_car(i: int, rails: StaticBody3D) -> void:
	var kinds := ["abteil", "speise", "gepaeck", "hull", "hull", "schlaf"]
	var kind: String = kinds[i]
	var zr := car_rear(i)
	var zf := car_front(i)
	var zm := (zr + zf) * 0.5
	var interior := kind != "hull"
	var body := Geo.batch()
	var stripe := Geo.batch()
	var roof := Geo.batch()
	var under := Geo.batch()
	var glass := Geo.batch()
	var lining := Geo.batch()
	var upper := Geo.batch()
	var y_lo := FLOOR + WIN_LO
	var y_hi := FLOOR + WIN_HI
	# --- Aussenhaut mit Fensterband (W3 +x: Ausschnitt fuer die Ladetuer)
	var cargo_door := kind == "gepaeck"
	for side: int in [-1, 1]:
		var cut := cargo_door and side > 0
		var x := float(side) * (HW - 0.02)
		var xi := float(side) * (IW - 0.02)
		_skin(body, x, 0.75, y_lo, zr, zf, cut)
		_skin(body, x, y_hi, CEIL, zr, zf, cut)
		stripe.add(Vector3(float(side) * (HW + 0.005), y_hi + 0.12, zm), Vector3(0.02, 0.04, CAR_LEN))
		if not cut:
			stripe.add(Vector3(float(side) * (HW + 0.005), y_lo - 0.08, zm), Vector3(0.02, 0.07, CAR_LEN))
		if interior:
			_skin(lining, xi, FLOOR, y_lo, zr, zf, cut)
			_skin(upper, xi, y_hi, CEIL, zr, zf, cut)
		var wins := _windows(kind, i, side)
		wins.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		var cur := zr
		for w: Array in wins:
			var wz: float = w[0]
			var hw: float = float(w[1]) * 0.5
			var a := wz + hw
			if cur - a > 0.01:
				_skin(body, x, y_lo, y_hi, cur, a, cut)
				if interior:
					_skin(lining, xi, y_lo, y_hi, cur, a, cut)
			glass.add(Vector3(x, (y_lo + y_hi) * 0.5, wz), Vector3(0.02 if interior else 0.03, y_hi - y_lo, hw * 2.0))
			if interior:
				_window_trim(kind, side, wz, hw * 2.0, xi)
			cur = wz - hw
		if cur - zf > 0.01:
			_skin(body, x, y_lo, y_hi, cur, zf, cut)
			if interior:
				_skin(lining, xi, y_lo, y_hi, cur, zf, cut)
	# --- Stirnwaende (mit Tuerloch oder geschlossen)
	var rear_open := i in [1, 2]                 # W2/W3 Heck offen (Tuer sitzt vorn am Vorgaenger)
	var front_open := i in [0, 1, 2, 5]          # Tueren W1, W2, W3, W6 (Koerper extra)
	for end: Array in [[zr - 0.05, rear_open], [zf + 0.05, front_open]]:
		var ez: float = end[0]
		var open: bool = end[1]
		if open:
			for side: int in [-1, 1]:
				var cx := float(side) * (DOOR_HW + HW) * 0.5
				body.add(Vector3(cx, (0.75 + CEIL) * 0.5, ez), Vector3(HW - DOOR_HW, CEIL - 0.75, 0.1))
				_col(col, Vector3(cx, (FLOOR + CEIL) * 0.5, ez), Vector3(HW - DOOR_HW, CEIL - FLOOR, 0.12))
			var top := FLOOR + DOOR_H
			body.add(Vector3(0, (top + CEIL) * 0.5, ez), Vector3(DOOR_HW * 2.0, CEIL - top, 0.1))
			body.add(Vector3(0, (0.75 + FLOOR) * 0.5, ez), Vector3(DOOR_HW * 2.0, FLOOR - 0.75, 0.1))
			_col(col, Vector3(0, (top + CEIL) * 0.5, ez), Vector3(DOOR_HW * 2.0, CEIL - top, 0.12))
		else:
			body.add(Vector3(0, (0.75 + CEIL) * 0.5, ez), Vector3(HW * 2.0, CEIL - 0.75, 0.1))
			_col(col, Vector3(0, (FLOOR + CEIL) * 0.5, ez), Vector3(HW * 2.0, CEIL - FLOOR, 0.12))
			if interior or i == 3:
				# verriegelte Tuer (Optik)
				var dz := ez + (0.06 if ez > zm else -0.06)
				lining.add(Vector3(0, FLOOR + DOOR_H * 0.5, dz), Vector3(DOOR_HW * 2.0 - 0.1, DOOR_H, 0.03))
	# --- Dach, Boden, Unterbau
	roof.add(Vector3(0, CEIL + 0.12, zm), Vector3(HW * 2.0, 0.25, CAR_LEN))
	roof.add(Vector3(0, ROOF - 0.08, zm), Vector3(HW * 2.0 - 0.3, 0.16, CAR_LEN - 0.3))
	_col(col, Vector3(0, CEIL + 0.2, zm), Vector3(HW * 2.0, 0.4, CAR_LEN))
	under.add(Vector3(0, FLOOR - 0.18, zm), Vector3(HW * 2.0 - 0.1, 0.34, CAR_LEN))
	under.add(Vector3(0, 0.72, zm), Vector3(3.0, 0.22, CAR_LEN - 2.0))
	for bz: float in [zr - 3.6, zf + 3.6]:
		under.add(Vector3(0, 0.55, bz), Vector3(2.3, 0.45, 3.0))
		for ax: float in [-1.25, 1.25]:
			for wx: float in [-0.72, 0.72]:
				var wc := Vector3(wx, 0.46, bz + ax)
				under.add(wc, Vector3(0.12, 0.88, 0.37))
				under.add(wc, Vector3(0.12, 0.37, 0.88))
				under.add(wc, Vector3(0.12, 0.66, 0.66), Basis(Vector3.RIGHT, PI * 0.25))
	# Unterboden zwischen den Drehgestellen (Kaesten)
	for k in 3:
		under.add(Vector3(0, 0.62, zm + 4.0 - 4.0 * k), Vector3(2.2, 0.4, 2.2))
	if interior:
		_col(col, Vector3(0, FLOOR - 0.15, zm), Vector3(HW * 2.0, 0.3, CAR_LEN))
		var fl := Geo.batch()
		fl.add(Vector3(0, FLOOR + 0.01, zm), Vector3(IW * 2.0, 0.02, CAR_LEN - 0.2))
		_mesh(fl, "planks" if kind == "gepaeck" else "floor")
		var cl := Geo.batch()
		cl.add(Vector3(0, CEIL - 0.03, zm), Vector3(IW * 2.0, 0.04, CAR_LEN - 0.2))
		_mesh(cl, "ceil", null, false)
	# Seitenwaende: Kollision (W3 mit Tuerloch)
	for side: int in [-1, 1]:
		var x := float(side) * (HW - 0.05)
		if cargo_door and side > 0:
			_col(col, Vector3(x, (FLOOR + CEIL) * 0.5, (zr + (-66.4)) * 0.5), Vector3(0.12, CEIL - FLOOR, zr + 66.4))
			_col(col, Vector3(x, (FLOOR + CEIL) * 0.5, (-69.6 + zf) * 0.5), Vector3(0.12, CEIL - FLOOR, -69.6 - zf))
			_col(col, Vector3(x, (3.5 + CEIL) * 0.5, -68.0), Vector3(0.12, CEIL - 3.5, 3.2))
		else:
			_col(col, Vector3(x, (FLOOR + CEIL) * 0.5, zm), Vector3(0.12, CEIL - FLOOR, CAR_LEN))
	_mesh(body, "body")
	_mesh(stripe, "stripe", null, false)
	_mesh(roof, "roof")
	_mesh(under, "under")
	_mesh(glass, "glass" if interior else "lit", null, false)
	if interior:
		_mesh(lining, "cargo_wall" if kind == "gepaeck" else "lining")
		_mesh(upper, "cargo_wall" if kind == "gepaeck" else "upper")
		_flush()
		# Deckenlampen + Licht
		var lamps := Geo.batch()
		for k in 4:
			var lz := zr - 3.25 - 6.5 * k
			lamps.add(Vector3(0.0 if kind in ["speise", "gepaeck"] else 0.8, CEIL - 0.06, lz), Vector3(0.22, 0.03, 2.2))
		_mesh(lamps, "lamp", null, false)
		for k in 3:
			_light(self, Vector3(0.3, CEIL - 0.35, zr - 4.3 - 8.7 * k), Color(1.0, 0.82, 0.58), 1.1, 7.5)
		# Kein Talnebel im geschlossenen Waggon: negative Dichte hebt den globalen Volumennebel
		# (0.004) im Innenraum auf -> kein milchiger Schleier um die Deckenlampen.
		var fv := FogVolume.new()
		fv.name = "InnenKeinNebel"
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		fv.size = Vector3(IW * 2.0, CEIL - FLOOR, CAR_LEN - 0.4)
		var fm := FogMaterial.new()
		fm.density = -0.004
		fm.albedo = Color(1, 1, 1)
		fv.material = fm
		fv.position = Vector3(0.0, (FLOOR + CEIL) * 0.5, zr - CAR_LEN * 0.5)
		add_child(fv)
	else:
		_mesh(lining, "lining")
		# Hohle Waggons: Dach begehbar, unsichtbares Gelaender, Klimakaesten als Deckung
		for side: int in [-1, 1]:
			_col(rails, Vector3(float(side) * 1.6, ROOF + 0.6, zm), Vector3(0.1, 1.2, CAR_LEN + 1.5))
		var ac := Geo.batch()
		var acs: Array = [[0.95, zr - 7.5], [-0.95, zr - 16.5]]
		for a: Array in acs:
			var c := Vector3(float(a[0]), ROOF + 0.28, float(a[1]))
			ac.add(c, Vector3(0.85, 0.56, 1.6))
			ac.add(c + Vector3(0, 0.29, 0), Vector3(0.6, 0.03, 1.2))
			_col(col, c, Vector3(0.85, 0.56, 1.6))
		_mesh(ac, "steel")
	match kind:
		"abteil": _furnish_abteil(i)
		"speise": _furnish_speise(i)
		"gepaeck": _furnish_gepaeck(i)
		"schlaf": _furnish_schlaf(i)
	if i == 3:
		_col(rails, Vector3(0, ROOF + 0.6, zr - 0.15), Vector3(3.3, 1.2, 0.1))
		# Leiter an der Stirn (Optik): vom Uebergang W3/W4 aufs Dach
		var lad := Geo.batch()
		for sx: float in [-0.25, 0.25]:
			lad.add(Vector3(sx, (FLOOR + ROOF + 0.4) * 0.5, zr + 0.12), Vector3(0.05, ROOF + 0.4 - FLOOR, 0.05))
		for k in 9:
			lad.add(Vector3(0, FLOOR + 0.35 + 0.35 * k, zr + 0.12), Vector3(0.5, 0.04, 0.04))
		_mesh(lad, "steel")
	if i == 4:
		_col(rails, Vector3(0, ROOF + 0.6, zf + 0.1), Vector3(3.3, 1.2, 0.1))
		# Dachluke vorn auf W5
		var h := Geo.batch()
		h.add(Vector3(0, ROOF + 0.03, -134.75), Vector3(1.0, 0.06, 1.2))
		h.add(Vector3(0, ROOF + 0.09, -134.2), Vector3(0.4, 0.05, 0.05))
		_mesh(h, "steel")

func _build_gangway(i: int) -> void:
	# Uebergang zwischen Waggon i und i+1
	var z0 := car_front(i)
	var z1 := car_rear(i + 1)
	var zm := (z0 + z1) * 0.5
	var len := z0 - z1 + 0.3
	var b := Geo.batch()
	b.add(Vector3(0, FLOOR - 0.1, zm), Vector3(1.5, 0.2, len))
	if i != 3:
		_col(col, Vector3(0, FLOOR - 0.1, zm), Vector3(1.6, 0.2, len))
	var bel := Geo.batch()
	for side: int in [-1, 1]:
		bel.add(Vector3(float(side) * 0.8, (FLOOR + CEIL - 0.2) * 0.5, zm), Vector3(0.08, CEIL - 0.2 - FLOOR, len))
		_col(col, Vector3(float(side) * 0.8, (FLOOR + CEIL) * 0.5, zm), Vector3(0.1, CEIL - FLOOR, len))
		for k in 4:
			bel.add(Vector3(float(side) * 0.83, (FLOOR + CEIL - 0.2) * 0.5, z0 - 0.3 - 0.3 * k), Vector3(0.06, CEIL - 0.2 - FLOOR, 0.05))
	bel.add(Vector3(0, CEIL - 0.1, zm), Vector3(1.66, 0.1, len))
	_col(col, Vector3(0, CEIL - 0.05, zm), Vector3(1.7, 0.1, len))
	_mesh(bel, "bellow")
	_mesh(b, "steel")
	if i == 3:
		# Dachbruecke W4/W5
		var br := Geo.batch()
		br.add(Vector3(0, ROOF - 0.05, zm), Vector3(2.6, 0.1, len + 0.4))
		_col(col, Vector3(0, ROOF - 0.05, zm), Vector3(3.2, 0.1, len + 0.4))
		_mesh(br, "steel")
	if i == 2:
		# Uebergang W3/W4: Schutz gegen Absturz zwischen die Waggons
		_col(col, Vector3(0, FLOOR - 0.1, zm), Vector3(1.6, 0.2, len))

func _cover(p: Vector3) -> void:
	Geo.marker(self, p, "cover_point")

## Optik-Batches je Waggon (Interior-Materialien): {mat: Geo.BoxBatch} und {mat: Int.RBatch}
var _ib: Dictionary = {}
var _ir: Dictionary = {}

func _b(mat: String) -> Geo.BoxBatch:
	if not _ib.has(mat):
		_ib[mat] = Geo.batch()
	return _ib[mat]

func _r(mat: String) -> Int.RBatch:
	if not _ir.has(mat):
		_ir[mat] = Int.RBatch.new()
	return _ir[mat]

## Schreibt die gesammelten Optik-Batches als Meshes (ein Draw-Call je Material).
func _flush(parent: Node3D = null) -> void:
	var p := parent if parent != null else self
	for k: String in _ib:
		_mesh(_ib[k], k, p, k not in ["shade", "bulb", "lamp", "chrome", "linen_thin"])
	for k: String in _ir:
		var mi := Int.put(p, (_ir[k] as Int.RBatch).build(), _m(k), k not in ["shade", "bulb", "curtain", "chrome"])
		if mi != null and k == "curtain":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ib.clear()
	_ir.clear()

## Fensterrahmen innen: Brett (Kirsche), Alurahmen, Vorhaenge links/rechts, Hinweisschild.
func _window_trim(kind: String, side: int, wz: float, ww: float, xi: float) -> void:
	var y_lo := FLOOR + WIN_LO
	var y_hi := FLOOR + WIN_HI
	var inward := -float(side)
	var hw := ww * 0.5
	if kind == "gepaeck":
		_r("alu").add(Vector3(xi + inward * 0.02, y_lo - 0.02, wz), Vector3(0.05, 0.04, ww + 0.06), 0.01)
		_r("alu").add(Vector3(xi + inward * 0.02, y_hi + 0.02, wz), Vector3(0.05, 0.04, ww + 0.06), 0.01)
		return
	# Fensterbrett (Kirsche), leicht vorstehend
	_r("cherry").add(Vector3(xi + inward * 0.05, y_lo - 0.015, wz), Vector3(0.11, 0.03, ww + 0.1), 0.012)
	# Alurahmen ringsum (Gummi-Dichtung als dunkle Fuge)
	for sy: float in [y_lo + 0.02, y_hi - 0.02]:
		_r("alu").add(Vector3(xi + inward * 0.015, sy, wz), Vector3(0.04, 0.05, ww), 0.012)
	for sz: float in [wz + hw - 0.025, wz - hw + 0.025]:
		_r("alu").add(Vector3(xi + inward * 0.015, (y_lo + y_hi) * 0.5, sz), Vector3(0.04, WIN_HI - WIN_LO, 0.05), 0.012)
	_b("rubber").add(Vector3(xi + inward * 0.004, (y_lo + y_hi) * 0.5, wz), Vector3(0.006, WIN_HI - WIN_LO - 0.06, ww - 0.07))
	# Querteilung oben (Klappfenster) bei breiten Fenstern
	if ww > 1.2:
		_r("alu").add(Vector3(xi + inward * 0.015, y_hi - 0.28, wz), Vector3(0.035, 0.035, ww - 0.06), 0.01)
	# Vorhaenge: zwei geraffte Bahnen an den Fensterkanten, oben Schiene (nicht hinter den Etagenbetten)
	if kind == "schlaf" and side < 0:
		return
	var xc := xi + inward * 0.07
	var cw := clampf(ww * 0.17, 0.18, 0.3)
	_r("curtain").curtain(xc, inward, y_lo - 0.1, y_hi + 0.1, wz + hw + 0.06, wz + hw - cw, 3.0, 0.045)
	_r("curtain").curtain(xc, inward, y_lo - 0.1, y_hi + 0.1, wz - hw + cw, wz - hw - 0.06, 3.0, 0.045)
	_r("chrome").add(Vector3(xc + inward * 0.02, y_hi + 0.12, wz), Vector3(0.018, 0.018, ww + 0.2), 0.008, Basis.IDENTITY, 2)

## Ausstattung, die jeder Personenwagen bekommt: Sockelleisten, Gardinenschiene, Deckenleuchten-Rahmen,
## Notbremse + Fahrplan an den Stirnwaenden, Schmutz-Decals.
func _furnish_common(i: int, kind: String) -> void:
	var zr := car_rear(i)
	var zf := car_front(i)
	var zm := (zr + zf) * 0.5
	if kind == "gepaeck":
		for side: int in [-1, 1]:
			_b("veneer_dark").add(Vector3(float(side) * (IW - 0.05), FLOOR + 0.1, zm), Vector3(0.04, 0.2, CAR_LEN - 0.4))
		Int.decal(self, "scuffs.png", Vector3(0.0, FLOOR, zm + 6.0), Vector3(1.6, 0.3, 3.0), Basis(Vector3.UP, 1.3), 0.6, Color(0.3, 0.25, 0.2))
		Int.decal(self, "smudge.png", Vector3(0.3, FLOOR, zm - 7.0), Vector3(1.4, 0.3, 1.2), Basis(Vector3.UP, 0.4), 0.55, Color(0.25, 0.2, 0.16))
		return
	# Sockelleisten (dunkles Furnier) + Handlauf-Leiste unter den Fenstern
	for side: int in [-1, 1]:
		_b("veneer_dark").add(Vector3(float(side) * (IW - 0.035), FLOOR + 0.06, zm), Vector3(0.03, 0.12, CAR_LEN - 0.3))
		_r("cherry").add(Vector3(float(side) * (IW - 0.03), FLOOR + WIN_HI + 0.2, zm), Vector3(0.04, 0.05, CAR_LEN - 0.3), 0.012)
	# Deckenleuchten: Alurahmen um die Leuchtstreifen
	for k in 4:
		var lz := zr - 3.25 - 6.5 * k
		var lx := 0.0 if kind in ["speise"] else 0.8
		_r("alu").add(Vector3(lx, CEIL - 0.05, lz), Vector3(0.32, 0.04, 2.3), 0.015)
	# Stirnwaende: Notbremse (Schild + Griff) und Fahrplan im Rahmen
	for e: Array in [[zr - 0.11, -1.0], [zf + 0.11, 1.0]]:
		var ez: float = e[0]
		var nz: float = e[1]
		var n := Vector3(0, 0, nz)
		Int.wall_sign(self, "notbremse.png", Vector3(1.2, FLOOR + 1.85, ez), Vector2(0.32, 0.16), n)
		_r("alu").add(Vector3(1.2, FLOOR + 1.62, ez + nz * 0.03), Vector3(0.2, 0.12, 0.05), 0.015)
		_r("red").add(Vector3(1.2, FLOOR + 1.58, ez + nz * 0.07), Vector3(0.14, 0.035, 0.035), 0.015)
		Int.wall_sign(self, "fahrplan.png", Vector3(-1.15, FLOOR + 1.45, ez), Vector2(0.36, 0.495), n)
		_r("alu").add(Vector3(-1.15, FLOOR + 1.45, ez - nz * 0.004), Vector3(0.4, 0.535, 0.012), 0.006)
		Int.wall_sign(self, "rauchverbot.png", Vector3(1.2, FLOOR + 2.35, ez), Vector2(0.14, 0.14), n)
	# Schmutz: Laufspur im Gang, Wasserfleck an der Decke, Handabdruecke an den Tueren
	var gx := 0.85 if kind in ["abteil", "schlaf"] else 0.0
	for k in 3:
		var dz := zr - 4.0 - 8.5 * k + _rng.randf_range(-1.5, 1.5)
		Int.decal(self, "scuffs.png" if k % 2 == 0 else "smudge.png", Vector3(gx, FLOOR, dz), Vector3(0.9, 0.3, 2.2),
			Basis(Vector3.UP, PI * 0.5 + _rng.randf_range(-0.2, 0.2)), 0.45, Color(0.35, 0.28, 0.22))
	Int.decal(self, "water_stain.png", Vector3(_rng.randf_range(-0.6, 0.6), CEIL, zm + _rng.randf_range(-8.0, 8.0)),
		Vector3(1.1, 0.3, 1.1), Basis(Vector3.RIGHT, PI), 0.35, Color(0.6, 0.5, 0.35))
	for ez: float in [zr - 0.1, zf + 0.1]:
		var down := Vector3(0, 0, -1.0 if ez > zm else 1.0)
		Int.decal(self, "handmarks.png", Vector3(0.75, FLOOR + 1.2, ez), Vector3(0.35, 0.3, 0.6),
			Basis(Vector3.RIGHT, -PI * 0.5 * down.z), 0.3, Color(0.4, 0.34, 0.28))
	# Reiseaufkleber an einem Fensterrahmen (Gangseite)
	Int.wall_sign(self, "aufkleber.png", Vector3(IW - 0.025, FLOOR + 0.75, zr - 9.3), Vector2(0.09, 0.09), Vector3.LEFT)

## Polsterbank (3 Plaetze) quer im Abteil: Sitz bei (x_c, sz), back_dir = Richtung der Rueckenlehne (+-1 in z).
func _bench(x_c: float, width: float, sz: float, back_dir: float, places: int, seat_d: float = 0.5) -> void:
	var pw := width / places
	_b("veneer_dark").add(Vector3(x_c, FLOOR + 0.13, sz + back_dir * 0.02), Vector3(width - 0.02, 0.26, seat_d - 0.06))
	_b("black").add(Vector3(x_c, FLOOR + 0.03, sz - back_dir * 0.05), Vector3(width - 0.1, 0.06, seat_d - 0.2))
	var tilt := Basis(Vector3.RIGHT, back_dir * 0.13)
	for p in places:
		var px := x_c - width * 0.5 + pw * (p + 0.5)
		# Sitzkissen (Oberkante 0,46 m wie die Kollision), vorn leicht abgerundet
		_r("moquette").add(Vector3(px, FLOOR + 0.365, sz), Vector3(pw - 0.012, 0.19, seat_d), 0.07, Basis.IDENTITY, 3)
		# Rueckenkissen, nach hinten geneigt
		var bc := Vector3(px, FLOOR + 0.8, sz + back_dir * (seat_d * 0.5 - 0.07))
		_r("moquette").add(bc, Vector3(pw - 0.02, 0.66, 0.13), 0.06, tilt, 3)
		# Kopfschoner (weisses Tuch)
		var hc := bc + tilt * Vector3(0, 0.2, -back_dir * 0.068)
		_r("linen").add(hc, Vector3(pw - 0.14, 0.2, 0.012), 0.004, tilt, 1)
	# Armlehnen an beiden Enden
	for ex: float in [x_c - width * 0.5 + 0.03, x_c + width * 0.5 - 0.03]:
		_r("moquette").add(Vector3(ex, FLOOR + 0.56, sz + back_dir * 0.03), Vector3(0.06, 0.2, seat_d - 0.08), 0.025)

## Gepaeckablage aus Chromrohr an einer Wand (Wand bei wz, Ablage ragt in Richtung dir).
func _rack(x0: float, x1: float, y: float, wz: float, dir: float, depth: float = 0.38) -> void:
	var xc := (x0 + x1) * 0.5
	var w := absf(x1 - x0)
	for k in 5:
		var z := wz + dir * (0.05 + (depth - 0.05) * float(k) / 4.0)
		_r("chrome").add(Vector3(xc, y + (0.025 if k == 4 else 0.0), z), Vector3(w, 0.022, 0.022), 0.01, Basis.IDENTITY, 2)
	for bx: float in [x0 + 0.08, xc, x1 - 0.08]:
		_r("alu").add(Vector3(bx, y - 0.02, wz + dir * depth * 0.5), Vector3(0.025, 0.04, depth), 0.01, Basis.IDENTITY, 2)
		_r("alu").add(Vector3(bx, y - 0.14, wz + dir * 0.04), Vector3(0.025, 0.26, 0.03), 0.01, Basis.IDENTITY, 2)

## Leselampe an der Wand (Messingarm + Schirm), Wand bei wz, Lampe zeigt in Richtung dir.
func _reading_lamp(x: float, y: float, wz: float, dir: float) -> void:
	_r("brass").add(Vector3(x, y, wz + dir * 0.02), Vector3(0.07, 0.1, 0.03), 0.01)
	_r("brass").add(Vector3(x, y + 0.02, wz + dir * 0.08), Vector3(0.02, 0.02, 0.11), 0.008, Basis.IDENTITY, 2)
	# Messinghaube mit Opalglas nach unten (frueher leuchtender Lampenkoerper -> weisse Kugel hinter Koepfen)
	_r("brass").add(Vector3(x, y - 0.01, wz + dir * 0.15), Vector3(0.085, 0.065, 0.085), 0.034)
	_r("bulb").add(Vector3(x, y - 0.043, wz + dir * 0.15), Vector3(0.056, 0.006, 0.056), 0.026)

func _furnish_abteil(i: int) -> void:
	var zr := car_rear(i)
	var wall := Geo.batch()
	var x_wall := -0.1
	_furnish_common(i, "abteil")
	for k in 8:
		var z0 := zr - 2.0 - 2.75 * k
		var z1 := z0 - 2.75
		var zc := (z0 + z1) * 0.5
		# Gangwand mit Tueroeffnung (0.8 m)
		for seg: Array in [[z0, zc + 0.4], [zc - 0.4, z1]]:
			var a: float = seg[0]
			var b: float = seg[1]
			wall.add(Vector3(x_wall, (FLOOR + CEIL) * 0.5, (a + b) * 0.5), Vector3(0.08, CEIL - FLOOR, a - b))
			_col(col, Vector3(x_wall, (FLOOR + CEIL) * 0.5, (a + b) * 0.5), Vector3(0.08, CEIL - FLOOR, a - b))
		wall.add(Vector3(x_wall, CEIL - 0.25, zc), Vector3(0.08, 0.5, 0.8))
		_col(col, Vector3(x_wall, CEIL - 0.25, zc), Vector3(0.08, 0.5, 0.8))
		# Trennwand
		for zz: float in ([z0, z1] if k == 7 else [z0]):
			wall.add(Vector3((-IW + x_wall) * 0.5, (FLOOR + CEIL) * 0.5, zz), Vector3(IW + x_wall, CEIL - FLOOR, 0.08))
			_col(col, Vector3((-IW + x_wall) * 0.5, (FLOOR + CEIL) * 0.5, zz), Vector3(IW + x_wall, CEIL - FLOOR, 0.08))
		# Sitzbaenke gegenueber (Kollision unveraendert, Optik: Polster)
		for dz: float in [-0.45, 0.45]:
			var sz := (z0 if dz < 0.0 else z1) + dz
			var c := Vector3(-0.92, FLOOR + 0.23, sz)
			_col(col, c, Vector3(1.5, 0.46, 0.5))
			var bdir := 1.0 if dz < 0.0 else -1.0
			_bench(-0.92, 1.5, sz, bdir, 3)
			var wz := z0 if dz < 0.0 else z1
			var wdir := -bdir
			_rack(-1.66, -0.18, FLOOR + 1.95, wz + wdir * 0.04, wdir)
			_reading_lamp(-1.5, FLOOR + 1.42, wz + wdir * 0.04, wdir)
			_reading_lamp(-0.35, FLOOR + 1.42, wz + wdir * 0.04, wdir)
			Int.picture(self, "painting_alps.jpg" if (k + int(dz > 0.0)) % 2 == 0 else "painting_lake.jpg",
				Vector3(-0.92, FLOOR + 1.48, wz + wdir * 0.04), Vector2(0.56, 0.34), Vector3(0, 0, wdir), _m("veneer_dark"))
			# Koffer auf mancher Ablage
			if (k * 2 + int(dz > 0.0)) % 3 == 0:
				_r("case" if k % 2 == 0 else "case2").add(Vector3(-1.05 + 0.2 * float(k % 3), FLOOR + 2.1, wz + wdir * 0.22), Vector3(0.62, 0.22, 0.34), 0.03)
		# Klapptisch am Fenster: Kirschholz mit Alukante, Konsole
		_r("cherry").add(Vector3(-1.49, FLOOR + 0.72, zc), Vector3(0.36, 0.035, 0.5), 0.012)
		_r("alu").add(Vector3(-1.31, FLOOR + 0.72, zc), Vector3(0.012, 0.04, 0.5), 0.005, Basis.IDENTITY, 1)
		_r("alu").add(Vector3(-1.6, FLOOR + 0.6, zc), Vector3(0.03, 0.2, 0.06), 0.008, Basis(Vector3.BACK, -0.6), 2)
		Int.wall_sign(self, "rauchverbot.png", Vector3(-1.66, FLOOR + 0.82, zc + 0.6), Vector2(0.08, 0.08), Vector3.RIGHT)
		Int.wall_sign(self, "hinweis.png", Vector3(-1.66, FLOOR + 0.8, zc - 0.55), Vector2(0.24, 0.06), Vector3.RIGHT)
		# Licht der Leselampen (eines je Abteil, ohne Flackern)
		_light(self, Vector3(-1.0, FLOOR + 1.45, zc), Color(1.0, 0.8, 0.55), 0.32, 2.8, false)
		# Abteiltuer: Glasschiebetuer offen geparkt (Gangseite, vor der Wand), Rahmen ums Loch, Nummer
		var dx := x_wall + 0.06
		for dzz: float in [0.42, -0.42]:
			_r("alu").add(Vector3(x_wall, FLOOR + 1.05, zc + dzz), Vector3(0.12, 2.1, 0.04), 0.01, Basis.IDENTITY, 2)
		_r("alu").add(Vector3(x_wall, FLOOR + 2.12, zc), Vector3(0.12, 0.04, 0.88), 0.01, Basis.IDENTITY, 2)
		for fz: float in [zc + 0.42, zc + 1.18]:
			_r("alu").add(Vector3(dx, FLOOR + 1.05, fz), Vector3(0.03, 2.08, 0.05), 0.01, Basis.IDENTITY, 2)
		for fy: float in [FLOOR + 0.05, FLOOR + 2.07, FLOOR + 0.85]:
			_r("alu").add(Vector3(dx, fy, zc + 0.8), Vector3(0.03, 0.06, 0.8), 0.01, Basis.IDENTITY, 2)
		_b("glass").add(Vector3(dx, FLOOR + 1.46, zc + 0.8), Vector3(0.012, 1.18, 0.72))
		var num := Label3D.new()
		num.text = str(11 + k)
		num.font_size = 48
		num.pixel_size = 0.0016
		num.modulate = Color(0.9, 0.85, 0.7)
		num.outline_size = 0
		num.position = Vector3(x_wall + 0.045, FLOOR + 2.3, zc)
		num.rotation.y = PI * 0.5
		add_child(num)
		_r("brass").add(Vector3(x_wall + 0.042, FLOOR + 2.3, zc), Vector3(0.006, 0.09, 0.12), 0.003, Basis.IDENTITY, 1)
	# Gang: Handlauf vor den Fenstern, Klappsitze
	_r("chrome").add(Vector3(IW - 0.08, FLOOR + 1.02, zr - 13.0), Vector3(0.025, 0.025, CAR_LEN - 4.5), 0.012, Basis.IDENTITY, 2)
	for k in 6:
		var hz := zr - 3.0 - 4.0 * k
		_r("alu").add(Vector3(IW - 0.045, FLOOR + 1.02, hz), Vector3(0.07, 0.02, 0.02), 0.008, Basis.IDENTITY, 1)
	for k in 3:
		var kz := zr - 5.4 - 8.25 * k
		_r("moquette").add(Vector3(IW - 0.12, FLOOR + 0.62, kz), Vector3(0.06, 0.36, 0.4), 0.025)
		_r("alu").add(Vector3(IW - 0.06, FLOOR + 0.55, kz), Vector3(0.05, 0.3, 0.06), 0.01)
	_mesh(wall, "lining")
	_flush()
	for z: float in [zr - 1.0, zr - 25.0]:
		_cover(Vector3(0.9, FLOOR, z))

func _furnish_speise(i: int) -> void:
	var zr := car_rear(i)
	var zf := car_front(i)
	_furnish_common(i, "speise")
	var deco := Deco.new(_mats, 4711 + i)   # eigener Seed: Zufallsfolge des Wagens bleibt unveraendert
	for k in 6:
		var z := zr - 2.6 - 2.3 * k
		for sx: float in [-1.2, 1.2]:
			var s := signf(sx)
			# Tisch: Saeule (Alu), Platte (Kirsche), Tischdecke mit Ueberhang zur Gangseite
			_r("alu").add(Vector3(sx, FLOOR + 0.37, z), Vector3(0.09, 0.74, 0.09), 0.03)
			_r("alu").add(Vector3(sx, FLOOR + 0.02, z), Vector3(0.4, 0.03, 0.4), 0.012)
			_r("cherry").add(Vector3(sx, FLOOR + 0.735, z), Vector3(0.78, 0.04, 0.88), 0.014)
			_col(col, Vector3(sx, FLOOR + 0.39, z), Vector3(0.75, 0.78, 0.86))
			_r("linen").add(Vector3(sx, FLOOR + 0.762, z), Vector3(0.8, 0.012, 0.9), 0.005, Basis.IDENTITY, 1)
			_r("linen").add(Vector3(sx - s * 0.404, FLOOR + 0.66, z), Vector3(0.01, 0.2, 0.9), 0.004, Basis(Vector3.BACK, s * 0.05), 1)
			for ez: float in [z + 0.453, z - 0.453]:
				_r("linen").add(Vector3(sx, FLOOR + 0.69, ez), Vector3(0.8, 0.14, 0.01), 0.004, Basis.IDENTITY, 1)
			# Tischlampe, Gedeck, Glaeser, Flasche: echte Modelle/Drehkoerper (nachtzug_table_deco.gd)
			deco.add(sx, z, FLOOR)
			_r("veneer_dark").add(Vector3(sx + s * 0.12, FLOOR + 0.84, z), Vector3(0.012, 0.14, 0.1), 0.004, Basis(Vector3.BACK, s * 0.15), 1)
			# Sitzbaenke (2 Plaetze) quer, Polster
			for dz: float in [-0.9, 0.9]:
				_bench(sx * 1.04, 0.9, z + dz, signf(dz), 2, 0.45)
				_col(col, Vector3(sx * 1.04, FLOOR + 0.55, z + dz * 1.06), Vector3(0.9, 1.1, 0.5))
			if k % 2 == 1:
				_cover(Vector3(sx * 0.55, FLOOR, z))
		_light(self, Vector3(0.0, FLOOR + 1.2, z), Color(1.0, 0.78, 0.5), 0.3, 3.2, false)
	# Kueche vorn links, Gang rechts
	var kz := zf + 6.5
	var wall := Geo.batch()
	wall.add(Vector3((-IW - 0.3) * 0.5, (FLOOR + CEIL) * 0.5, kz), Vector3(IW - 0.3, CEIL - FLOOR, 0.08))
	_col(col, Vector3((-IW - 0.3) * 0.5, (FLOOR + CEIL) * 0.5, kz), Vector3(IW - 0.3, CEIL - FLOOR, 0.08))
	wall.add(Vector3(-0.3, (FLOOR + CEIL) * 0.5, (kz + zf) * 0.5), Vector3(0.08, CEIL - FLOOR, kz - zf))
	_col(col, Vector3(-0.3, (FLOOR + CEIL) * 0.5, (kz + zf) * 0.5), Vector3(0.08, CEIL - FLOOR, kz - zf))
	# Theke vor der Kueche (Deckung): Furnierfront, Kirschplatte, Fussleiste, Flaschen
	_col(col, Vector3(-0.9, FLOOR + 0.55, kz + 0.45), Vector3(1.4, 1.1, 0.5))
	_b("veneer_dark").add(Vector3(-0.9, FLOOR + 0.52, kz + 0.45), Vector3(1.38, 1.04, 0.48))
	_r("cherry").add(Vector3(-0.9, FLOOR + 1.075, kz + 0.47), Vector3(1.44, 0.05, 0.56), 0.015)
	_b("black").add(Vector3(-0.9, FLOOR + 0.05, kz + 0.7), Vector3(1.38, 0.1, 0.02))
	_r("brass").add(Vector3(-0.9, FLOOR + 0.25, kz + 0.75), Vector3(1.3, 0.025, 0.025), 0.01, Basis.IDENTITY, 2)
	for b in 5:
		_r("glass_bottle").add(Vector3(-1.45 + 0.2 * b, FLOOR + 1.85, kz + 0.07), Vector3(0.07, 0.26, 0.07), 0.03)
	_r("cherry").add(Vector3(-0.95, FLOOR + 1.71, kz + 0.1), Vector3(1.3, 0.03, 0.16), 0.01)
	Int.wall_sign(self, "fahrplan.png", Vector3(-0.3 + 0.045, FLOOR + 1.5, kz - 2.5), Vector2(0.36, 0.495), Vector3.RIGHT)
	_cover(Vector3(-0.9, FLOOR, kz + 1.2))
	deco.flush(self)
	_mesh(wall, "lining")
	_flush()

const CRATES := [
	[-1.15, -58.0, 1.0, 1.0, 1.4], [1.15, -60.5, 1.0, 0.9, 1.8], [-1.2, -63.0, 0.9, 1.5, 1.2],
	[-0.95, -67.5, 0.9, 0.8, 0.9], [-1.1, -71.5, 1.1, 1.3, 1.6], [1.1, -74.0, 1.0, 1.1, 1.4],
	[-1.0, -77.0, 1.2, 0.75, 1.0], [1.2, -78.6, 0.8, 1.6, 0.8],
]

func _furnish_gepaeck(i: int) -> void:
	_furnish_common(i, "gepaeck")
	var cr := Geo.batch()
	var cs := Int.RBatch.new()
	for k in CRATES.size():
		var c: Array = CRATES[k]
		var p := Vector3(float(c[0]), FLOOR + float(c[3]) * 0.5, float(c[1]))
		var s := Vector3(float(c[2]), float(c[3]), float(c[4]))
		if k % 3 != 1:
			cr.add(p, s)
			# Kistenkanten (Latten) und Spanngurt
			for sy: float in [-1.0, 1.0]:
				_b("veneer_dark").add(p + Vector3(0, sy * (s.y * 0.5 - 0.04), 0), s + Vector3(0.02, -s.y + 0.08, 0.02))
			_b("black").add(p + Vector3(0, 0, 0), Vector3(s.x + 0.012, s.y + 0.012, 0.05))
		else:
			cs.add(p, s, 0.05)
			_r("alu").add(p + Vector3(0, s.y * 0.5 + 0.02, 0), Vector3(0.3, 0.04, 0.05), 0.015)
		_col(col, p, s)
		_cover(Vector3(float(c[0]) * 0.3, FLOOR, float(c[1]) + 1.2))
	# Gepaecknetze/Regale an den Waenden (Optik)
	for z: float in [-56.5, -65.0, -80.0]:
		_r("alu").add(Vector3(-1.62, FLOOR + 1.9, z), Vector3(0.15, 0.04, 1.8), 0.01)
		for k in 3:
			_r("alu").add(Vector3(-1.64, FLOOR + 1.75, z - 0.8 + 0.8 * k), Vector3(0.03, 0.3, 0.03), 0.008, Basis.IDENTITY, 2)
	_mesh(cr, "crate")
	Int.put(self, cs.build(), _m("case"))
	_flush()

func _furnish_schlaf(i: int) -> void:
	var zr := car_rear(i)
	var wall := Geo.batch()
	var x_wall := -0.1
	_furnish_common(i, "schlaf")
	for k in 9:
		var z0 := zr - 2.0 - 2.2 * k
		var z1 := z0 - 2.2
		var zc := (z0 + z1) * 0.5
		for seg: Array in [[z0, zc + 0.35], [zc - 0.35, z1]]:
			var a: float = seg[0]
			var b: float = seg[1]
			wall.add(Vector3(x_wall, (FLOOR + CEIL) * 0.5, (a + b) * 0.5), Vector3(0.08, CEIL - FLOOR, a - b))
			_col(col, Vector3(x_wall, (FLOOR + CEIL) * 0.5, (a + b) * 0.5), Vector3(0.08, CEIL - FLOOR, a - b))
		wall.add(Vector3(x_wall, CEIL - 0.3, zc), Vector3(0.08, 0.6, 0.7))
		_col(col, Vector3(x_wall, CEIL - 0.3, zc), Vector3(0.08, 0.6, 0.7))
		for zz: float in ([z0, z1] if k == 8 else [z0]):
			wall.add(Vector3((-IW + x_wall) * 0.5, (FLOOR + CEIL) * 0.5, zz), Vector3(IW + x_wall, CEIL - FLOOR, 0.08))
			_col(col, Vector3((-IW + x_wall) * 0.5, (FLOOR + CEIL) * 0.5, zz), Vector3(IW + x_wall, CEIL - FLOOR, 0.08))
		# Unteres Bett (Kollision) + oberes Bett (Optik), quer zur Fahrtrichtung an der Rueckwand
		var bz := z0 - 0.45
		_col(col, Vector3(-0.92, FLOOR + 0.25, bz), Vector3(1.55, 0.5, 0.75))
		for by: float in [0.0, 1.17]:
			var y0 := FLOOR + by
			if by == 0.0:
				_b("veneer_dark").add(Vector3(-0.92, y0 + 0.18, bz), Vector3(1.55, 0.36, 0.75))
			else:
				_r("veneer_dark").add(Vector3(-0.92, y0 + 0.32, bz), Vector3(1.55, 0.08, 0.75), 0.015)
			# Matratze, Laken, Kissen, Wolldecke
			_r("mattress").add(Vector3(-0.92, y0 + 0.44, bz), Vector3(1.5, 0.15, 0.72), 0.05)
			_r("linen").add(Vector3(-0.92, y0 + 0.52, bz), Vector3(1.48, 0.02, 0.7), 0.008, Basis.IDENTITY, 2)
			_r("linen").add(Vector3(-1.44, y0 + 0.57, bz), Vector3(0.36, 0.09, 0.5), 0.04)
			if by > 0.0 or k not in [2, 5]:
				_r("blanket").add(Vector3(-0.32, y0 + 0.56, bz), Vector3(0.3, 0.07, 0.66), 0.03)
		# Absturzsicherung oben, Leiter, Leselampe, Ablage am Fenster
		_r("chrome").add(Vector3(-0.92, FLOOR + 1.85, bz - 0.36), Vector3(1.4, 0.025, 0.025), 0.012, Basis.IDENTITY, 2)
		for lx: float in [-0.32, -0.12]:
			_r("chrome").add(Vector3(lx, FLOOR + 0.95, bz - 0.5), Vector3(0.025, 1.9, 0.025), 0.012, Basis(Vector3.RIGHT, 0.12), 2)
		for r in 4:
			_r("chrome").add(Vector3(-0.22, FLOOR + 0.6 + 0.35 * r, bz - 0.47 - 0.04 * r), Vector3(0.22, 0.02, 0.02), 0.008, Basis.IDENTITY, 1)
		_reading_lamp(-1.55, FLOOR + 1.2, z0 - 0.04, -1.0)
		_reading_lamp(-1.55, FLOOR + 2.25, z0 - 0.04, -1.0)
		_r("cherry").add(Vector3(-1.52, FLOOR + 0.78, z1 + 0.45), Vector3(0.3, 0.03, 0.6), 0.01)
		_rack(-1.66, -0.2, FLOOR + 2.55, z1 + 0.04, 1.0, 0.32)
		Int.wall_sign(self, "hinweis.png", Vector3(-1.66, FLOOR + 0.75, z1 + 0.95), Vector2(0.24, 0.06), Vector3.RIGHT)
		_light(self, Vector3(-1.1, FLOOR + 1.3, zc), Color(1.0, 0.78, 0.52), 0.25, 2.6, false)
		# Abteilnummer ueber der Tuer
		var num := Label3D.new()
		num.text = str(1 + k)
		num.font_size = 48
		num.pixel_size = 0.0016
		num.modulate = Color(0.9, 0.85, 0.7)
		num.position = Vector3(x_wall + 0.045, FLOOR + 2.3, zc)
		num.rotation.y = PI * 0.5
		add_child(num)
		_r("brass").add(Vector3(x_wall + 0.042, FLOOR + 2.3, zc), Vector3(0.006, 0.09, 0.09), 0.003, Basis.IDENTITY, 1)
		for dzz: float in [0.37, -0.37]:
			_r("alu").add(Vector3(x_wall, FLOOR + 1.0, zc + dzz), Vector3(0.12, 2.0, 0.04), 0.01, Basis.IDENTITY, 2)
	# Webers Abteil (vorderstes, Nr. 9): offener Koffer, Notiz, Leselampe
	var wz := zr - 2.0 - 2.2 * 8.5
	var suit := Geo.batch()
	suit.add(Vector3(-1.1, FLOOR + 0.62, wz - 0.45), Vector3(0.6, 0.18, 0.42))
	suit.add(Vector3(-1.1, FLOOR + 0.9, wz - 0.67), Vector3(0.6, 0.42, 0.05), Basis(Vector3.RIGHT, -0.4))
	_mesh(suit, "case")
	var note := Geo.batch()
	note.add(Vector3(-0.6, FLOOR + 0.57, wz - 0.3), Vector3(0.21, 0.01, 0.29), Basis(Vector3.UP, 0.3))
	note.add(Vector3(-0.85, FLOOR + 0.57, wz - 0.2), Vector3(0.15, 0.01, 0.08), Basis(Vector3.UP, -0.5))
	_mesh(note, "note", null, false)
	_light(self, Vector3(-1.2, FLOOR + 1.3, wz), Color(1.0, 0.8, 0.5), 0.6, 3.0)
	# Gang: Handlauf, Klappsitz
	_r("chrome").add(Vector3(IW - 0.08, FLOOR + 1.02, zr - 13.0), Vector3(0.025, 0.025, CAR_LEN - 4.5), 0.012, Basis.IDENTITY, 2)
	_mesh(wall, "lining")
	_flush()
	_cover(Vector3(0.9, FLOOR, zr - 1.0))

func _make_door(region: Node3D, pos: Vector3, size: Vector3, open_off: Vector3, mat: String) -> StaticBody3D:
	var d := StaticBody3D.new()
	d.collision_layer = 1
	d.collision_mask = 0
	d.set_meta("no_fit", true)
	d.set_meta("surface", "metal")
	region.add_child(d)
	d.position = pos
	Geo.add_box_shape(d, Vector3.ZERO, size)
	var b := Geo.batch()
	b.add(Vector3.ZERO, size)
	b.add(Vector3(0, size.y * 0.18, 0), Vector3(size.x * 0.6, size.y * 0.35, size.z + 0.01))
	var mi := Geo.mesh_node(b.build(), _m(mat))
	d.add_child(mi)
	var win := Geo.batch()
	win.add(Vector3(0, size.y * 0.18, 0), Vector3(size.x * 0.55, size.y * 0.3, size.z + 0.02))
	d.add_child(Geo.mesh_node(win.build(), _m("glass"), Vector3.ZERO, false))
	doors.append(d)
	door_open_off.append(open_off)
	return d

func _build_doors(region: Node3D) -> void:
	var sz := Vector3(DOOR_HW * 2.0, DOOR_H, 0.08)
	for i: int in [0, 1, 2, 5]:
		var z := car_front(i) + 0.12
		_make_door(region, Vector3(0, FLOOR + DOOR_H * 0.5, z), sz, Vector3(1.15, 0, 0), "steel")
	# Seitentuer Gepaeckwagen (+x), rollt nach hinten
	_make_door(region, Vector3(HW - 0.08, (FLOOR + 3.5) * 0.5, -68.0), Vector3(0.08, 3.5 - FLOOR, 3.2), Vector3(0, 0, 3.1), "body")

func open_door(idx: int, snd: bool = true) -> void:
	if idx < 0 or idx >= doors.size():
		return
	var d := doors[idx]
	if not is_instance_valid(d) or d.has_meta("open"):
		return
	d.set_meta("open", true)
	d.set_meta("closed_pos", d.position)
	d.collision_layer = 0
	var tw := d.create_tween()
	tw.tween_property(d, "position", d.position + door_open_off[idx], 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if snd:
		VF.play_at(self, "nachtzug_door", d.global_position, -2.0, 8.0, 60.0)

func is_door_open(idx: int) -> bool:
	return idx >= 0 and idx < doors.size() and doors[idx].has_meta("open")

## Vorderer Zugteil: W7 (Huelle) + Lok mit Stromabnehmer und Funken.
func _build_front() -> void:
	front = Node3D.new()
	front.name = "Front"
	add_child(front)
	var zr := car_rear(6)
	var zf := car_front(6)
	var zm := (zr + zf) * 0.5
	var body := Geo.batch()
	var lit := Geo.batch()
	var roof := Geo.batch()
	var under := Geo.batch()
	for side: int in [-1, 1]:
		var x := float(side) * (HW - 0.02)
		body.add(Vector3(x, (0.75 + FLOOR + WIN_LO) * 0.5, zm), Vector3(0.04, FLOOR + WIN_LO - 0.75, CAR_LEN))
		body.add(Vector3(x, (FLOOR + WIN_HI + CEIL) * 0.5, zm), Vector3(0.04, CEIL - FLOOR - WIN_HI, CAR_LEN))
		lit.add(Vector3(x, FLOOR + (WIN_LO + WIN_HI) * 0.5, zm), Vector3(0.03, WIN_HI - WIN_LO, CAR_LEN))
	# Heckstirn W7 mit offener Tuer (dahinter beleuchteter Vorraum)
	for side: int in [-1, 1]:
		body.add(Vector3(float(side) * (DOOR_HW + HW) * 0.5, (0.75 + CEIL) * 0.5, zr - 0.05), Vector3(HW - DOOR_HW, CEIL - 0.75, 0.1))
	body.add(Vector3(0, (FLOOR + DOOR_H + CEIL) * 0.5, zr - 0.05), Vector3(DOOR_HW * 2.0, CEIL - FLOOR - DOOR_H, 0.1))
	body.add(Vector3(0, (0.75 + FLOOR) * 0.5, zr - 0.05), Vector3(DOOR_HW * 2.0, FLOOR - 0.75, 0.1))
	var vest := Geo.batch()
	vest.add(Vector3(0, FLOOR + 0.01, zr - 1.5), Vector3(3.2, 0.02, 3.0))
	vest.add(Vector3(0, (FLOOR + CEIL) * 0.5, zr - 3.0), Vector3(3.2, CEIL - FLOOR, 0.05))
	vest.add(Vector3(-1.65, (FLOOR + CEIL) * 0.5, zr - 1.5), Vector3(0.05, CEIL - FLOOR, 3.0))
	vest.add(Vector3(1.65, (FLOOR + CEIL) * 0.5, zr - 1.5), Vector3(0.05, CEIL - FLOOR, 3.0))
	vest.add(Vector3(0, CEIL - 0.02, zr - 1.5), Vector3(3.2, 0.04, 3.0))
	_mesh(vest, "lining", front)
	_light(front, Vector3(0, CEIL - 0.4, zr - 1.5), Color(1.0, 0.85, 0.65), 1.4, 5.0)
	body.add(Vector3(0, (0.75 + CEIL) * 0.5, zf + 0.05), Vector3(HW * 2.0, CEIL - 0.75, 0.1))
	roof.add(Vector3(0, CEIL + 0.12, zm), Vector3(HW * 2.0, 0.25, CAR_LEN))
	roof.add(Vector3(0, ROOF - 0.08, zm), Vector3(HW * 2.0 - 0.3, 0.16, CAR_LEN - 0.3))
	under.add(Vector3(0, FLOOR - 0.18, zm), Vector3(HW * 2.0 - 0.1, 0.34, CAR_LEN))
	for bz: float in [zr - 3.6, zf + 3.6]:
		under.add(Vector3(0, 0.55, bz), Vector3(2.3, 0.45, 3.0))
	# Gangway-Stueck an W7 (faellt mit ab)
	under.add(Vector3(0, FLOOR - 0.1, zr + 0.5), Vector3(1.5, 0.2, 1.0))
	# Lok
	var lr := zf - 1.5
	var lf := lr - 20.0
	var lm := (lr + lf) * 0.5
	var loco := Geo.batch()
	loco.add(Vector3(0, 2.45, lm + 1.0), Vector3(3.0, 3.1, 18.0))
	loco.add(Vector3(0, 2.0, lf + 1.0), Vector3(3.0, 2.2, 2.0))
	loco.add(Vector3(0, 3.3, lf + 1.4), Vector3(2.9, 1.4, 1.6), Basis(Vector3.RIGHT, -0.5))
	var ls := Geo.batch()
	for side: int in [-1, 1]:
		ls.add(Vector3(float(side) * 1.51, 2.0, lm), Vector3(0.02, 0.12, 20.0))
	ls.add(Vector3(0, 1.5, lf - 0.01), Vector3(3.0, 0.12, 0.02))
	var head := Geo.batch()
	for sx: float in [-1.0, 1.0]:
		head.add(Vector3(sx, 1.55, lf - 0.02), Vector3(0.35, 0.22, 0.04))
	head.add(Vector3(0, 3.7, lf + 0.9), Vector3(0.3, 0.18, 0.04))
	under.add(Vector3(0, 0.6, lm), Vector3(2.6, 0.6, 19.0))
	roof.add(Vector3(0, 4.05, lm + 2.0), Vector3(2.2, 0.15, 12.0))
	# Stromabnehmer (Pantograf) Richtung Fahrdraht
	var pz := lm - 3.0
	var pan := Geo.batch()
	pan.add(Vector3(0, 4.2, pz), Vector3(1.2, 0.1, 1.2))
	var a0 := Vector3(0, 4.25, pz + 0.6)
	var a1 := Vector3(0, 5.4, pz - 0.6)
	var a2 := Vector3(0, WIRE_Y - 0.06, pz)
	for seg: Array in [[a0, a1], [a1, a2]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var d := p1 - p0
		var bas := Basis(Vector3.RIGHT, -atan2(d.z, d.y))
		pan.add((p0 + p1) * 0.5, Vector3(0.06, d.length(), 0.06), bas)
	pan.add(Vector3(0, WIRE_Y - 0.04, pz), Vector3(1.6, 0.05, 0.12))
	_mesh(body, "body", front)
	_mesh(lit, "lit", front, false)
	_mesh(roof, "roof", front)
	_mesh(under, "under", front)
	_mesh(loco, "loco", front)
	_mesh(ls, "stripe", front, false)
	_mesh(head, "head", front, false)
	_mesh(pan, "steel", front)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1, 0.96, 0.85)
	spot.light_energy = 6.0
	spot.spot_range = 120.0
	spot.spot_angle = 22.0
	spot.shadow_enabled = false
	spot.position = Vector3(0, 1.8, lf - 0.2)
	front.add_child(spot)
	spot.rotation = Vector3(deg_to_rad(-6.0), 0, 0)
	# Funken am Fahrdraht
	_spark_light = OmniLight3D.new()
	_spark_light.light_color = Color(0.6, 0.75, 1.0)
	_spark_light.light_energy = 0.0
	_spark_light.omni_range = 26.0
	_spark_light.shadow_enabled = false
	_spark_light.position = Vector3(0, WIRE_Y - 0.1, pz)
	front.add_child(_spark_light)
	_spark_fx = _make_sparks()
	_spark_fx.position = Vector3(0, WIRE_Y - 0.05, pz)
	front.add_child(_spark_fx)
	weber_spot = Vector3(0, FLOOR, zr - 0.9)

func _make_sparks() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 40
	p.lifetime = 0.6
	p.explosiveness = 0.85
	p.one_shot = true
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -0.2, 1)
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -12, 18)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	var q := BoxMesh.new()
	q.size = Vector3(0.03, 0.03, 0.12)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.8, 0.9, 1.0)
	m.emission_enabled = true
	m.emission = Color(0.7, 0.85, 1.0)
	m.emission_energy_multiplier = 8.0
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-10, -10, -2), Vector3(20, 20, 30))
	return p

# ------------------------------------------------------------------ Gleis, Masten, Boden

func _build_track() -> void:
	var gs := Shader.new()
	gs.code = GROUND_SHADER
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = gs
	var pm := PlaneMesh.new()
	pm.size = Vector2(1400, 1400)
	var g := MeshInstance3D.new()
	g.name = "Ground"
	g.mesh = pm
	g.material_override = _ground_mat
	g.position = Vector3(0, -0.15, -200)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	var r := Geo.batch()
	for cx: float in [0.0, TRACK2_X]:
		for rx: float in [-0.72, 0.72]:
			r.add(Vector3(cx + rx, -0.07, -200), Vector3(0.07, 0.15, 1400))
	_mesh(r, "rail", null, false)
	var w := Geo.batch()
	for cx: float in [0.0, TRACK2_X]:
		w.add(Vector3(cx, WIRE_Y, -200), Vector3(0.025, 0.025, 1400))
		w.add(Vector3(cx, WIRE_Y + 0.9, -200), Vector3(0.03, 0.03, 1400))
	_mesh(w, "steel", null, false)

func _build_masts() -> void:
	var b := Geo.batch()
	b.add(Vector3(3.3, 3.75, 0), Vector3(0.22, 7.8, 0.22))
	b.add(Vector3(1.55, 7.45, 0), Vector3(3.6, 0.1, 0.1))
	b.add(Vector3(1.4, 7.1, 0), Vector3(3.2, 0.06, 0.06), Basis(Vector3.BACK, 0.2))
	b.add(Vector3(0, WIRE_Y + 0.45, 0), Vector3(0.03, 0.9, 0.03))
	b.add(Vector3(-7.6, 3.75, 0), Vector3(0.22, 7.8, 0.22))
	b.add(Vector3(-5.85, 7.45, 0), Vector3(3.6, 0.1, 0.1))
	b.add(Vector3(TRACK2_X, WIRE_Y + 0.45, 0), Vector3(0.03, 0.9, 0.03))
	b.add(Vector3(3.3, 0.2, 0), Vector3(0.6, 0.4, 0.6))
	b.add(Vector3(-7.6, 0.2, 0), Vector3(0.6, 0.4, 0.6))
	var mesh := b.build()
	for k in MAST_N:
		var mi := Geo.mesh_node(mesh, _m("steel"), Vector3(0, 0, MAST_FRONT - MAST_GAP * k), false)
		add_child(mi)
		_masts.append(mi)

func _build_ground_collider() -> void:
	# Boden fuer Wrackteile (Hubschrauber-Absturz); liegt NICHT unter der Nav-Region
	var gb := StaticBody3D.new()
	gb.name = "GroundCol"
	gb.collision_layer = 1
	gb.collision_mask = 0
	gb.set_meta("no_fit", true)
	gb.set_meta("surface", "dirt")
	add_child(gb)
	Geo.add_box_shape(gb, Vector3(60, -0.4, -100), Vector3(100, 0.5, 600))
	Geo.add_box_shape(gb, Vector3(-60, -0.4, -100), Vector3(100, 0.5, 600))

func _build_sky() -> void:
	# Ferne Hoehenzuege (statisch, unendliche Parallaxe), Mond, Sterne
	_build_mountains()
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var dir := Vector3(0.35, -0.6, -0.7).normalized()
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.92, 0.94, 1.0)
	mm.set("disable_fog", true)
	var sm := SphereMesh.new()
	sm.radius = 9.0
	sm.height = 18.0
	var moon_mi := MeshInstance3D.new()
	moon_mi.mesh = sm
	moon_mi.material_override = mm
	moon_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon_mi.position = Vector3(0, 0, -100) - dir * 460.0
	add_child(moon_mi)
	var st := MultiMesh.new()
	st.transform_format = MultiMesh.TRANSFORM_3D
	var dm := SphereMesh.new()
	dm.radius = 0.9
	dm.height = 1.8
	dm.radial_segments = 4
	dm.rings = 2
	var smat := mm.duplicate() as StandardMaterial3D
	smat.albedo_color = Color(0.8, 0.85, 1.0)
	dm.material = smat
	st.mesh = dm
	st.instance_count = 320
	for k in 320:
		var a := r.randf_range(0, TAU)
		var el := asin(r.randf_range(0.12, 0.98))
		var p := Vector3(cos(a) * cos(el), sin(el), sin(a) * cos(el)) * 470.0 + Vector3(0, 0, -100)
		st.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * r.randf_range(0.5, 1.4)), p))
	var smi := MultiMeshInstance3D.new()
	smi.multimesh = st
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)

## Hoehenzuege links und rechts der Strecke: zwei Hoehenfeld-Streifen (|x| 380..2300 m) mit dem
## Berg-Shader der Villa (Wald, Fels, Schnee, Dunst), auf Nacht abgestimmt.
func _mountain_h(nr: FastNoiseLite, nh: FastNoiseLite, x: float, z: float) -> float:
	var ax := absf(x)
	var ridge := clampf(nr.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var hills := nh.get_noise_2d(x, z) * 0.5 + 0.5
	var foot := smoothstep(380.0, 620.0, ax) * (20.0 + 90.0 * hills)
	var mt := smoothstep(520.0, 1500.0, ax) * (80.0 + 760.0 * pow(ridge, 1.6))
	if x > 0.0:
		# rechte Seite: Grat weiter weg und niedriger -> ferne Silhouette statt Wand ueber dem Dorf
		mt = smoothstep(800.0, 1900.0, ax) * (60.0 + 520.0 * pow(ridge, 1.6))
	return -3.0 + foot + mt

func _build_mountains() -> void:
	var nr := FastNoiseLite.new()
	nr.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nr.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	nr.fractal_octaves = 4
	nr.frequency = 0.0008
	nr.seed = 1717
	var nh := FastNoiseLite.new()
	nh.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nh.fractal_octaves = 3
	nh.frequency = 0.004
	nh.seed = 2323
	var m := ShaderMaterial.new()
	m.shader = MOUNTAIN_SHADER
	m.set_shader_parameter("rock_albedo", load("res://assets/environment/textures/rock_face_03/diffuse.jpg"))
	m.set_shader_parameter("noise_tex", FKit.noise_tex())
	m.set_shader_parameter("treeline", 420.0)
	m.set_shader_parameter("snowline", 640.0)
	m.set_shader_parameter("forest_color", Color(0.035, 0.05, 0.035))
	m.set_shader_parameter("meadow_color", Color(0.08, 0.1, 0.06))
	m.set_shader_parameter("rock_tint", Color(0.42, 0.42, 0.45))
	m.set_shader_parameter("snow_color", Color(0.62, 0.68, 0.82))
	m.set_shader_parameter("haze_color", Color(0.1, 0.11, 0.15))
	m.set_shader_parameter("haze_k", 0.0011)
	m.set_shader_parameter("haze_energy", 1.0)
	var nx := 56
	var nz := 150
	var z0 := -2600.0
	var z1 := 2000.0
	for side: int in [-1, 1]:
		var grid: Array = []
		for i in nx + 1:
			var ax := 380.0 * pow(2300.0 / 380.0, float(i) / nx)
			var row := PackedVector3Array()
			row.resize(nz + 1)
			for j in nz + 1:
				var z := lerpf(z0, z1, float(j) / nz)
				var x := float(side) * ax
				row[j] = Vector3(x, _mountain_h(nr, nh, x, z), z)
			grid.append(row)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in nx + 1:
			var row: PackedVector3Array = grid[i]
			var prev: PackedVector3Array = grid[maxi(i - 1, 0)]
			var nxt: PackedVector3Array = grid[mini(i + 1, nx)]
			for j in nz + 1:
				var tx := nxt[j] - prev[j]
				var tz := row[mini(j + 1, nz)] - row[maxi(j - 1, 0)]
				var n := tz.cross(tx).normalized()
				if n.y < 0.0:
					n = -n
				st.set_normal(n)
				st.add_vertex(row[j])
		var w := nz + 1
		for i in nx:
			for j in nz:
				var a := i * w + j
				var b := a + 1
				var c := a + w + 1
				var d := a + w
				var pa: Vector3 = (grid[i] as PackedVector3Array)[j]
				var pb: Vector3 = (grid[i] as PackedVector3Array)[j + 1]
				var pc: Vector3 = (grid[i + 1] as PackedVector3Array)[j + 1]
				# Wicklung: im Uhrzeigersinn von oben gesehen (Godot-Vorderseite)
				if (pb - pa).cross(pc - pa).y > 0.0:
					st.add_index(a); st.add_index(c); st.add_index(b)
					st.add_index(a); st.add_index(d); st.add_index(c)
				else:
					st.add_index(a); st.add_index(b); st.add_index(c)
					st.add_index(a); st.add_index(c); st.add_index(d)
		var mi := MeshInstance3D.new()
		mi.name = "Berge_%s" % ("L" if side < 0 else "R")
		mi.mesh = st.commit()
		if side > 0:
			# Rechts liegt das Dorf: dessen Licht hellt den Bodennebel grau auf -> Hangfuss in den
			# Dunst ueberblenden, sonst haengt der dunkle Grat wie eine Hoehlendecke ueber dem Nebel.
			var mr := m.duplicate() as ShaderMaterial
			mr.set_shader_parameter("valley_color", Color(0.15, 0.165, 0.19))
			mr.set_shader_parameter("valley_lo", 30.0)
			mr.set_shader_parameter("valley_hi", 230.0)
			mr.set_shader_parameter("valley_strength", 0.9)
			mi.material_override = mr
		else:
			mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

# ------------------------------------------------------------------ Landschafts-Chunks

func _build_chunks() -> void:
	var dm := SphereMesh.new()
	dm.radius = 0.5
	dm.height = 1.0
	dm.radial_segments = 4
	dm.rings = 2
	dm.material = _m("dot")
	_dot_mesh = dm
	for k in CHUNK_N:
		var c := Node3D.new()
		c.name = "Chunk%d" % k
		add_child(c)
		c.position = Vector3(0, 0, CHUNK_FRONT - CHUNK_LEN * k)
		_fill_chunk(c)
		_chunks.append(c)

func _fill_chunk(c: Node3D) -> void:
	for ch in c.get_children():
		ch.queue_free()
	var r := _rng
	# Mischwald (Fichten + kahle Laubbaeume, track_trees.gd): Guertel beidseitig, dichter weiter draussen.
	# Zufallsfolge von _rng unveraendert (Ereignisse/Doerfer bleiben gleich).
	var trees: Array = []
	var forest_l := r.randf() < 0.65
	var forest_r := r.randf() < 0.55
	for side: int in [-1, 1]:
		var dense := forest_l if side < 0 else forest_r
		var n := r.randi_range(60, 110) if dense else r.randi_range(6, 18)
		for k in n:
			var x := float(side) * r.randf_range(14.0 if side > 0 else 18.0, 260.0)
			if dense and r.randf() < 0.6:
				x = float(side) * r.randf_range(14.0 if side > 0 else 18.0, 70.0)
			var s := r.randf_range(0.7, 1.6)
			var ts := s * 0.72
			var b := Basis(Vector3.UP, float(k) * 2.39).scaled(Vector3(ts, ts * r.randf_range(0.9, 1.3), ts))
			trees.append([Vector3(x, -0.2, -r.randf_range(0.0, CHUNK_LEN)), b, k + (0 if side < 0 else 1000)])
	# Unterholz nah am Gleis: junge Fichten und kahle Straeucher (statt Kugelbuesche)
	var shrubs: Array = []
	var bn := r.randi_range(4, 14)
	for k in bn:
		var side := -1.0 if r.randf() < 0.5 else 1.0
		var x := side * r.randf_range(7.0 if side > 0.0 else 11.0, 22.0)
		var s := r.randf_range(0.6, 1.4)
		shrubs.append([Vector3(x, 0.2, -r.randf_range(0, CHUNK_LEN)), s, k])
	TrackTrees.plant(c, trees, shrubs, CHUNK_LEN)
	# Dorf mit beleuchteten Fenstern
	if r.randf() < 0.35:
		_village(c, (-1.0 if r.randf() < 0.5 else 1.0) * r.randf_range(45.0, 180.0), -r.randf_range(20.0, 80.0), r)
	# Ferne Lichtpunkte (Doerfer an den Haengen)
	var dmm := MultiMesh.new()
	dmm.transform_format = MultiMesh.TRANSFORM_3D
	dmm.mesh = _dot_mesh
	var dn := r.randi_range(0, 3) * 6
	dmm.instance_count = dn
	var cx := (-1.0 if r.randf() < 0.5 else 1.0) * r.randf_range(260.0, 400.0)
	var cz := -r.randf_range(0, CHUNK_LEN)
	var cy := r.randf_range(0.0, 35.0)
	for k in dn:
		var p := Vector3(cx + r.randf_range(-35, 35), cy + r.randf_range(-6, 6) + 1.0, cz + r.randf_range(-40, 40))
		dmm.set_instance_transform(k, Transform3D(Basis().scaled(Vector3.ONE * r.randf_range(0.8, 1.6)), p))
	if dn > 0:
		var dmi := MultiMeshInstance3D.new()
		dmi.multimesh = dmm
		dmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c.add_child(dmi)

func _village(c: Node3D, vx: float, vz: float, r: RandomNumberGenerator) -> void:
	var walls := Geo.batch()
	var roofs := Geo.batch()
	var wins := Geo.batch()
	var n := r.randi_range(5, 12)
	for k in n:
		var p := Vector3(vx + r.randf_range(-35, 35), 0, vz + r.randf_range(-30, 30))
		if absf(p.x) < 14.0:
			p.x = signf(p.x) * 14.0
		var w := r.randf_range(7.0, 11.0)
		var d := r.randf_range(8.0, 12.0)
		var h := r.randf_range(4.5, 7.5)
		var yaw := r.randf_range(-0.3, 0.3) + (0.0 if r.randf() < 0.5 else PI * 0.5)
		var bas := Basis(Vector3.UP, yaw)
		walls.add(p + Vector3(0, h * 0.5, 0), Vector3(w, h, d), bas)
		var rl := sqrt(w * w * 0.25 + 9.0)
		for s: int in [-1, 1]:
			var rb := bas * Basis(Vector3.BACK, float(s) * -0.75)
			roofs.add(p + bas * Vector3(float(s) * w * 0.25, h + 1.2, 0), Vector3(rl, 0.3, d + 0.6), rb)
		# Fenster zur Bahn hin (einige erleuchtet)
		var face := -signf(p.x)
		for fx in 3:
			for fy in 2:
				if r.randf() < 0.45:
					var lp := Vector3(face * (w * 0.5 + 0.02), 1.4 + fy * 2.3, (fx - 1) * d * 0.28)
					wins.add(p + bas * lp, Vector3(0.05, 1.0, 0.9), bas)
	if r.randf() < 0.3:
		var tp := Vector3(vx, 0, vz)
		walls.add(tp + Vector3(0, 9, 0), Vector3(4, 18, 4))
		roofs.add(tp + Vector3(0, 21, 0), Vector3(3.0, 6, 3.0), Basis(Vector3.UP, PI * 0.25))
		wins.add(tp + Vector3(-signf(vx) * 2.02, 14, 0), Vector3(0.05, 1.4, 1.4))
	_mesh(walls, "house", c, false)
	_mesh(roofs, "tile", c, false)
	_mesh(wins, "win", c, false)

# ------------------------------------------------------------------ Ereignisse

## Tunnel, dessen Einfahrt (bei Tempo jetzt) nach `t_arrive` s die Bahnmeter `ref_z` erreicht.
func spawn_tunnel_eta(ref_z: float, t_arrive: float, length: float = 230.0) -> Dictionary:
	return spawn_tunnel(ref_z - maxf(speed, 1.0) * t_arrive, length)

func spawn_tunnel(z_entry: float, length: float) -> Dictionary:
	var n := Node3D.new()
	n.name = "Tunnel"
	add_child(n)
	n.position = Vector3(0, 0, z_entry)
	var conc := Geo.batch()
	var rock := Geo.batch()
	var lamps := Geo.batch()
	# Roehre: Waende + Gewoelbe (Halbkreis r 2.6 ueber y 3.0)
	var rad := 2.6
	var spring := TUNNEL_TOP - rad
	conc.add(Vector3(-rad - 0.2, spring * 0.5, -length * 0.5), Vector3(0.4, spring, length))
	conc.add(Vector3(rad + 0.2, spring * 0.5, -length * 0.5), Vector3(0.4, spring, length))
	for k in 6:
		var a0 := PI * float(k) / 6.0
		var a1 := PI * float(k + 1) / 6.0
		var p0 := Vector3(cos(a0) * (rad + 0.2), spring + sin(a0) * (rad + 0.2), 0)
		var p1 := Vector3(cos(a1) * (rad + 0.2), spring + sin(a1) * (rad + 0.2), 0)
		var mid := (p0 + p1) * 0.5
		var seg := (p1 - p0).length()
		conc.add(Vector3(mid.x, mid.y, -length * 0.5), Vector3(seg + 0.1, 0.4, length), Basis(Vector3.BACK, (a0 + a1) * 0.5 + PI * 0.5))
	# Portale (Einfahrt und Ausfahrt) und Berg
	for pz: float in [0.0, -length]:
		conc.add(Vector3(-17.0, 6.0, pz), Vector3(29.0, 12.0, 1.6))
		conc.add(Vector3(17.0, 6.0, pz), Vector3(29.0, 12.0, 1.6))
		conc.add(Vector3(0, TUNNEL_TOP + 3.3, pz), Vector3(5.2, 6.6, 1.6))
		conc.add(Vector3(0, TUNNEL_TOP + 0.4, pz + (0.9 if pz == 0.0 else -0.9)), Vector3(6.6, 0.8, 0.4))
	var mr := _rng
	var nb := int(length / 40.0) + 3
	for k in nb:
		var z := -length * float(k) / float(nb - 1)
		var h := mr.randf_range(45.0, 110.0)
		var w := mr.randf_range(140.0, 260.0)
		rock.add(Vector3(mr.randf_range(-40, 40), h * 0.42, z), Vector3(w, h, mr.randf_range(60.0, 110.0)), Basis(Vector3.UP, mr.randf_range(-0.3, 0.3)) * Basis(Vector3.BACK, mr.randf_range(-0.15, 0.15)))
	# Lampen im Tunnel
	var nl := int(length / 25.0)
	for k in nl:
		lamps.add(Vector3(rad - 0.05, 2.2, -12.0 - 25.0 * k), Vector3(0.1, 0.25, 0.6))
	_mesh(conc, "concrete", n)
	_mesh(rock, "rock", n, false)
	var lm := Geo.batch()
	lm.add(Vector3.ZERO, Vector3(0.01, 0.01, 0.01))
	var lamp_mat := Geo.flat(Color(1.0, 0.6, 0.25), 0.5, 0.0, Color(1.0, 0.55, 0.2), 5.0)
	var lmesh := lamps.build()
	if lmesh != null:
		n.add_child(Geo.mesh_node(lmesh, lamp_mat, Vector3.ZERO, false))
	for k in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.22)
		l.light_energy = 1.4
		l.omni_range = 9.0
		l.shadow_enabled = false
		l.position = Vector3(rad - 0.4, 2.4, -length * (0.15 + 0.23 * k))
		n.add_child(l)
	var t := {"node": n, "z": z_entry, "len": length, "killed": false, "entered": false, "warned": false}
	tunnels.append(t)
	events.append({"node": n, "len": length, "kind": "tunnel"})
	return t

func spawn_event(kind: String, z: float) -> void:
	match kind:
		"bridge": _ev_bridge(z)
		"crossing": _ev_crossing(z)
		"station": _ev_station(z)
		"tunnel": spawn_tunnel(z, _rng.randf_range(180.0, 300.0))

func _ev_bridge(z: float) -> void:
	var n := Node3D.new()
	n.name = "Bridge"
	add_child(n)
	n.position = Vector3(0, 0, z)
	var length := 70.0
	var water := Geo.batch()
	water.add(Vector3(0, -0.1, -length * 0.5), Vector3(900, 0.05, 44))
	_mesh(water, "water", n, false)
	var bank := Geo.batch()
	for bz: float in [-length * 0.5 + 23.0, -length * 0.5 - 23.0]:
		bank.add(Vector3(0, 0.1, bz), Vector3(900, 0.6, 3.0))
	_mesh(bank, "rock", n, false)
	var st := Geo.batch()
	for cx: float in [0.0, TRACK2_X]:
		for side: int in [-1, 1]:
			var x := cx + float(side) * 2.25
			if cx != 0.0 and side > 0:
				continue
			st.add(Vector3(x, 0.3, -length * 0.5), Vector3(0.3, 0.4, length))
			st.add(Vector3(x, 5.6, -length * 0.5), Vector3(0.3, 0.3, length))
			var nseg := int(length / 5.0)
			for k in nseg + 1:
				var zz := -5.0 * k
				st.add(Vector3(x, 2.95, zz), Vector3(0.2, 5.3, 0.2))
				if k < nseg:
					st.add(Vector3(x, 2.95, zz - 2.5), Vector3(0.12, 0.12, 7.4), Basis(Vector3.RIGHT, (0.82 if k % 2 == 0 else -0.82)))
		for k in int(length / 10.0) + 1:
			st.add(Vector3(cx - 1.1, 5.7, -10.0 * k), Vector3(5.0, 0.2, 0.2))
	# Pfeiler im Wasser
	for pz: float in [-length * 0.33, -length * 0.66]:
		st.add(Vector3(-2.2, -0.5, pz), Vector3(9.0, 1.0, 2.5))
	_mesh(st, "steel", n)
	events.append({"node": n, "len": length, "kind": "bridge"})

func _ev_crossing(z: float) -> void:
	var n := Node3D.new()
	n.name = "Crossing"
	add_child(n)
	n.position = Vector3(0, 0, z)
	var road := Geo.batch()
	road.add(Vector3(0, -0.11, 0), Vector3(600, 0.05, 6.0))
	_mesh(road, "asphalt", n, false)
	var poles := Geo.batch()
	var reds := Geo.batch()
	var entry := {"node": n, "lights": [], "bell": false, "z": z}
	for side: Array in [[4.5, -4.0], [-9.0, 4.0]]:
		var x: float = side[0]
		var zz: float = side[1]
		poles.add(Vector3(x, 1.5, zz), Vector3(0.15, 3.0, 0.15))
		poles.add(Vector3(x - signf(x) * 3.0, 1.0, zz), Vector3(6.0, 0.12, 0.12))
		poles.add(Vector3(x, 2.6, zz), Vector3(1.0, 0.1, 0.1))
		for dx: float in [-0.35, 0.35]:
			reds.add(Vector3(x + dx, 2.6, zz), Vector3(0.22, 0.22, 0.12))
		var l := OmniLight3D.new()
		l.light_color = Color(1, 0.12, 0.05)
		l.light_energy = 2.0
		l.omni_range = 9.0
		l.position = Vector3(x, 2.7, zz)
		n.add_child(l)
		(entry["lights"] as Array).append(l)
	_mesh(poles, "stripe", n, false)
	var rm := _mesh(reds, "red", n, false)
	entry["red_mesh"] = rm
	# wartendes Auto mit Scheinwerfern
	var car := Geo.batch()
	car.add(Vector3(16, 0.75, 1.5), Vector3(4.2, 0.9, 1.8))
	car.add(Vector3(16.3, 1.45, 1.5), Vector3(2.2, 0.6, 1.6))
	_mesh(car, "case", n)
	var hl := Geo.batch()
	for dz: float in [0.95, 2.05]:
		hl.add(Vector3(13.88, 0.8, dz), Vector3(0.05, 0.18, 0.3))
	_mesh(hl, "head", n, false)
	var sp := SpotLight3D.new()
	sp.light_color = Color(1, 0.95, 0.8)
	sp.light_energy = 4.0
	sp.spot_range = 30.0
	sp.spot_angle = 30.0
	sp.position = Vector3(13.7, 0.9, 1.5)
	n.add_child(sp)
	sp.rotation = Vector3(0, deg_to_rad(90), 0)
	_crossing_lights.append(entry)
	events.append({"node": n, "len": 10.0, "kind": "crossing"})

func _ev_station(z: float) -> void:
	var n := Node3D.new()
	n.name = "Station"
	add_child(n)
	n.position = Vector3(0, 0, z)
	var length := 180.0
	var plat := Geo.batch()
	plat.add(Vector3(5.2, 0.27, -length * 0.5), Vector3(4.2, 0.55, length))
	plat.add(Vector3(3.15, 0.56, -length * 0.5), Vector3(0.15, 0.02, length))
	_mesh(plat, "concrete", n)
	var canopy := Geo.batch()
	var lamps := Geo.batch()
	for k in 10:
		var zz := -9.0 - 18.0 * k
		canopy.add(Vector3(6.3, 2.3, zz), Vector3(0.15, 3.6, 0.15))
		lamps.add(Vector3(4.6, 3.6, zz), Vector3(0.6, 0.06, 0.2))
	canopy.add(Vector3(5.4, 4.15, -length * 0.5), Vector3(3.4, 0.15, length - 10.0))
	_mesh(canopy, "steel", n)
	_mesh(lamps, "lamp", n, false)
	for k in 4:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.88, 0.7)
		l.light_energy = 2.0
		l.omni_range = 16.0
		l.position = Vector3(4.6, 3.4, -20.0 - 46.0 * k)
		n.add_child(l)
	var bld := Geo.batch()
	bld.add(Vector3(14.0, 3.5, -length * 0.45), Vector3(9.0, 7.0, 34.0))
	_mesh(bld, "house", n)
	var bw := Geo.batch()
	for k in 6:
		bw.add(Vector3(9.47, 2.2 + 2.8 * (k % 2), -length * 0.45 + 12.0 - 8.0 * (k / 2)), Vector3(0.05, 1.4, 2.0))
	_mesh(bw, "win", n, false)
	for k in 2:
		var lab := Label3D.new()
		lab.text = STATIONS[_station_i % STATIONS.size()]
		lab.font_size = 110
		lab.pixel_size = 0.01
		lab.outline_size = 10
		lab.modulate = Color(0.95, 0.95, 0.92)
		lab.outline_modulate = Color(0.05, 0.12, 0.3)
		lab.position = Vector3(6.25, 3.1, -40.0 - 90.0 * k)
		lab.rotation = Vector3(0, deg_to_rad(-90), 0)
		lab.double_sided = true
		n.add_child(lab)
	_station_i += 1
	events.append({"node": n, "len": length, "kind": "station"})

## Laufender Tunnel an Bahnmeter z (Einfahrt erreicht, Ausfahrt noch nicht passiert) oder {}.
func tunnel_at(z: float) -> Dictionary:
	for t: Dictionary in tunnels:
		var ze: float = t["z"]
		if ze >= z - 0.8 and ze - float(t["len"]) < z:
			return t
	return {}

## Sekunden, bis die naechste Tunneleinfahrt Bahnmeter z erreicht (INF ohne Tunnel).
func tunnel_eta(z: float) -> float:
	var best := INF
	for t: Dictionary in tunnels:
		var ze: float = t["z"]
		if ze < z - 0.8:
			best = minf(best, (z - 0.8 - ze) / maxf(speed, 0.5))
	return best

func next_tunnel(z: float) -> Dictionary:
	var best: Dictionary = {}
	var bz := -INF
	for t: Dictionary in tunnels:
		var ze: float = t["z"]
		if ze < z - 0.8 and ze > bz:
			bz = ze
			best = t
	return best

## Weber koppelt ab: hinterer Zugteil bremst, Front faehrt davon.
func decouple() -> void:
	if decoupled:
		return
	decoupled = true
	auto_events = false
	auto_tunnels = false
	target_speed = 0.0
	accel = 2.1
	VF.play_2d(self, "nachtzug_coupling", 0.0)
	VF.play_2d(self, "nachtzug_brake", -4.0, 0.6)
	if level != null and level.get("player") != null and level.player.has_method("add_trauma"):
		level.player.add_trauma(0.6)

func add_scroller(n: Node3D) -> void:
	if n != null and not scrollers.has(n):
		scrollers.append(n)

func clear_tunnels() -> void:
	for t: Dictionary in tunnels:
		var n: Node = t["node"]
		if is_instance_valid(n):
			n.queue_free()
	var keep: Array[Dictionary] = []
	for e: Dictionary in events:
		if str(e["kind"]) != "tunnel":
			keep.append(e)
	events = keep
	tunnels.clear()

func _any_event_near(z0: float, z1: float) -> bool:
	for e: Dictionary in events:
		if not is_instance_valid(e["node"]):
			continue
		var n := e["node"] as Node3D
		var a := n.position.z
		var b := a - float(e["len"])
		if a > z1 - 60.0 and b < z0 + 60.0:
			return true
	return false

# ------------------------------------------------------------------ Klang

func _build_audio() -> void:
	_rail_snd = _loop2d("nachtzug_rail_loop", -9.0)
	_wind_snd = _loop2d("nachtzug_wind_roof", -40.0)

func _loop2d(sfx: String, db: float) -> AudioStreamPlayer:
	var path := "res://assets/sfx/%s.ogg" % sfx
	if not ResourceLoader.exists(path):
		return null
	var st := (load(path) as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	st.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.bus = &"SFX"
	p.volume_db = db
	add_child(p)
	p.play(_rng.randf() * 3.0)
	return p

# ------------------------------------------------------------------ Takt

func _process(delta: float) -> void:
	_t += delta
	speed = move_toward(speed, target_speed, accel * delta)
	if decoupled and front != null:
		# Vorderer Zugteil faehrt mit Reisegeschwindigkeit weiter, wir bremsen
		front.position.z -= (CRUISE - speed) * delta
		if front.position.z < -900.0:
			front.visible = false
	var dz := speed * delta
	scroll += dz
	if _ground_mat != null:
		_ground_mat.set_shader_parameter("scroll", fmod(scroll, 14300.0))
		_ground_mat.set_shader_parameter("blur", clampf(speed / 14.0, 0.0, 0.93))
	for m in _masts:
		m.position.z += dz
		if m.position.z > MAST_FRONT:
			m.position.z -= MAST_GAP * MAST_N
		m.visible = tunnel_at(m.position.z).is_empty()
	for c in _chunks:
		c.position.z += dz
		if c.position.z - CHUNK_LEN > CHUNK_FRONT:
			c.position.z -= CHUNK_LEN * CHUNK_N
			_fill_chunk(c)
	var keep: Array[Dictionary] = []
	for e: Dictionary in events:
		if not is_instance_valid(e["node"]):
			continue
		var n := e["node"] as Node3D
		n.position.z += dz
		if n.position.z - float(e["len"]) > 260.0:
			n.queue_free()
			continue
		keep.append(e)
	events = keep
	var tk: Array[Dictionary] = []
	for t: Dictionary in tunnels:
		t["z"] = float(t["z"]) + dz
		if is_instance_valid(t["node"]):
			tk.append(t)
	tunnels = tk
	var sk: Array[Node3D] = []
	for s in scrollers:
		if is_instance_valid(s):
			s.global_position.z += dz
			if s.global_position.z < 600.0:
				sk.append(s)
	scrollers = sk
	_tick_crossings()
	_tick_auto_events(delta)
	_tick_clack(dz)
	_tick_tunnel_env(delta)
	_tick_lights(delta)
	_tick_sparks(delta)
	_tick_audio(delta)

func _tick_auto_events(delta: float) -> void:
	if not auto_events or speed < 5.0:
		return
	_event_t -= delta
	if _event_t > 0.0:
		return
	_event_t = _rng.randf_range(18.0, 34.0)
	if _any_event_near(EVENT_SPAWN_Z, EVENT_SPAWN_Z - 300.0):
		_event_t = 4.0
		return
	var kinds := ["bridge", "crossing", "station", "crossing", "bridge"]
	if auto_tunnels:
		kinds.append("tunnel")
	spawn_event(kinds[_rng.randi() % kinds.size()], EVENT_SPAWN_Z)

func _tick_crossings() -> void:
	var cam := get_viewport().get_camera_3d()
	var keep: Array[Dictionary] = []
	for e: Dictionary in _crossing_lights:
		var nv: Variant = e["node"]
		if not is_instance_valid(nv):
			continue
		var n := nv as Node3D
		keep.append(e)
		var on := fmod(_t, 1.0) < 0.5
		var ls: Array = e["lights"]
		for k in ls.size():
			if is_instance_valid(ls[k]):
				(ls[k] as OmniLight3D).visible = on
		var rmv: Variant = e.get("red_mesh")
		if rmv != null and is_instance_valid(rmv):
			(rmv as MeshInstance3D).visible = on
		if not bool(e["bell"]) and cam != null and absf(n.global_position.z - cam.global_position.z) < 70.0:
			e["bell"] = true
			VF.play_2d(self, "nachtzug_crossing_bell", -6.0 + wind_level * 3.0)
	_crossing_lights = keep

func _tick_clack(dz: float) -> void:
	_clack_acc += dz
	if _clack_acc < 25.0:
		return
	_clack_acc = fmod(_clack_acc, 25.0)
	var pitch := clampf(0.8 + speed / 120.0, 0.8, 1.15) * _rng.randf_range(0.96, 1.04)
	VF.play_2d(self, "nachtzug_clack", -11.0 - wind_level * 3.0 + (3.0 if tunnel_factor > 0.5 else 0.0), 0.0, &"SFX", pitch)
	var pl := get_tree().get_first_node_in_group("player")
	if pl != null and pl.has_method("add_trauma"):
		pl.call("add_trauma", (0.05 + wind_level * 0.03) * clampf(speed / CRUISE, 0.0, 1.0))

func _tick_tunnel_env(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var inside := false
	if cam != null:
		inside = not tunnel_at(cam.global_position.z).is_empty() and absf(cam.global_position.x) < 3.0
	if inside and not _cam_in_tunnel:
		VF.play_2d(self, "nachtzug_tunnel_whoosh", -4.0 + wind_level * 3.0)
		flicker_boost = 1.0
	_cam_in_tunnel = inside
	tunnel_factor = move_toward(tunnel_factor, 1.0 if inside else 0.0, delta * 3.0)
	if env != null:
		env.ambient_light_energy = lerpf(0.5, 0.12, tunnel_factor)
	if moon != null:
		moon.light_energy = lerpf(0.14, 0.0, tunnel_factor)
	if sky_mat != null:
		sky_mat.sky_energy_multiplier = lerpf(1.0, 0.05, tunnel_factor)

func _tick_lights(delta: float) -> void:
	flicker_boost = maxf(0.0, flicker_boost - delta * 0.6)
	var p := 0.004 + flicker_boost * 0.12 + tunnel_factor * 0.03
	for d: Dictionary in _lights:
		if not is_instance_valid(d["l"]):
			continue
		var l := d["l"] as OmniLight3D
		var base: float = d["e"]
		if _rng.randf() < p:
			l.light_energy = base * _rng.randf_range(0.05, 0.5)
		else:
			l.light_energy = move_toward(l.light_energy, base, delta * base * 6.0)

func _tick_sparks(delta: float) -> void:
	if _spark_light == null:
		return
	_spark_t -= delta
	_spark_on = maxf(0.0, _spark_on - delta)
	if _spark_t <= 0.0 and speed > 4.0:
		_spark_t = _rng.randf_range(1.2, 5.0)
		_spark_on = _rng.randf_range(0.08, 0.3)
		_spark_fx.restart()
		_spark_fx.emitting = true
		if _rng.randf() < 0.5:
			VF.play_at(self, "nachtzug_spark", _spark_light.global_position, 2.0, 25.0, 300.0, _rng.randf_range(0.85, 1.15))
	_spark_light.light_energy = (_rng.randf_range(3.0, 9.0) if _spark_on > 0.0 else 0.0)

func _tick_audio(_delta: float) -> void:
	var sp := clampf(speed / CRUISE, 0.0, 1.0)
	if _rail_snd != null:
		_rail_snd.volume_db = linear_to_db(maxf(sp, 0.001)) - 9.0 + wind_level * 2.0 + tunnel_factor * 4.0
		_rail_snd.pitch_scale = clampf(0.7 + 0.3 * sp, 0.5, 1.0)
	if _wind_snd != null:
		_wind_snd.volume_db = linear_to_db(maxf(wind_level * sp, 0.001)) - 3.0

# ------------------------------------------------------------------ Boden-Shader

const GROUND_SHADER := """
shader_type spatial;
uniform float scroll = 0.0;
uniform float blur = 0.0;
varying vec3 wp;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vn(vec2 p, float per) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h21(mod(i, per));
	float b = h21(mod(i + vec2(1.0, 0.0), per));
	float c = h21(mod(i + vec2(0.0, 1.0), per));
	float d = h21(mod(i + vec2(1.0, 1.0), per));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = vec2(wp.x, wp.z - scroll);
	vec2 cell = floor(p / 130.0);
	vec2 cm = mod(cell, 110.0);
	float h = h21(cm + 0.37);
	vec3 col = vec3(0.1, 0.12, 0.07);
	if (h > 0.25) col = vec3(0.13, 0.11, 0.07);
	if (h > 0.5) col = vec3(0.07, 0.09, 0.06);
	if (h > 0.75) col = vec3(0.12, 0.125, 0.1);
	float dirsel = step(0.5, h21(cm + 1.7));
	float fu = sin((dirsel > 0.5 ? p.x : p.y) * 6.2832 / 1.3);
	col *= 0.9 + 0.1 * fu * (1.0 - blur * 0.7);
	float n = vn(p / 13.0, 1100.0) * 0.6 + vn(p / 2.6, 5500.0) * 0.4;
	col *= 0.7 + 0.6 * n;
	vec2 fp = fract(p / 130.0);
	float edge = min(min(fp.x, 1.0 - fp.x), min(fp.y, 1.0 - fp.y)) * 130.0;
	col *= mix(0.55, 1.0, smoothstep(0.5, 2.5, edge));
	float dx0 = abs(wp.x);
	float dx1 = abs(wp.x + 4.4);
	float dmin = min(dx0, dx1);
	float bn = vn(vec2(p.x * 5.0, p.y * 5.0 / (1.0 + blur * 25.0)), 71500.0);
	vec3 ballast = vec3(0.17, 0.16, 0.15) * (0.6 + 0.7 * bn);
	float s = fract(p.y / 0.65);
	float sleeper = (1.0 - step(0.38, s)) * (1.0 - step(1.3, dmin));
	vec3 track = mix(ballast, vec3(0.09, 0.075, 0.06), sleeper * (1.0 - blur * 0.85));
	col = mix(col, track, 1.0 - smoothstep(2.3, 3.0, dmin));
	ALBEDO = col;
	ROUGHNESS = 0.95;
}
"""
