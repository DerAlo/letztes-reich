extends "res://game/levels/curfew.gd"
## Bonus-Episode "Lena – Über den Dächern" (Welle 5, game/episodes/episodes.gd).
## Dieselbe Nacht wie "Ausgangssperre": Spielerin ist Lena mit der G28 auf den Dächern, Kerner (Puppe,
## overwatch_actor.gd) schleicht unten die Curfew-Route ab. Er wartet an Haltepunkten (HOLDS), bis Lena den
## Abschnitt freigeschossen hat (Gates), und kämpft selbst, wenn er entdeckt wird (kein Sofort-Fail).
## Stirbt Kerner, geht es am letzten Haltepunkt weiter. Kulisse = curfew.gd (unverändert, nur geerbt).
##
## Ablauf (Haltepunkt -> Gate):
##   0 Straße       – Streife mit Taschenlampe            (Dach A, Wohnblock links)
##   1 Kontrollpunkt– Offizier + Posten kurz hintereinander (Zeugen-Logik: 3,2 s)
##   2 Straße Süd   – Streife mit Taschenlampe
##   3 Platz        – Lena zieht aufs Ministerium um (Dach B); Platzstreife + Suchscheinwerfer (abschießbar)
##   4 Zufahrt      – Gegenscharfschütze auf dem Regierungsbau; danach Drohne: Wachen in der Gasse markieren,
##                    Kerner schaltet sie leise aus
##   5 Terminal     – 22 s Übertragung; späte Streife über den Platz darf das Tor nicht erreichen
##   6 Notausgang   – Kerner taucht ab, Voss meldet sich, Lenas Monolog
##
## Bot (--autopilot): overwatch_bot.gd über bot_task(); Drohne fliegt per autofly. --phase=N startet an Haltepunkt N.

const SD = preload("res://game/story/story_data.gd")
const Actor = preload("res://game/levels/overwatch_actor.gd")
const OwBot = preload("res://game/levels/overwatch_bot.gd")
const ReconDrone = preload("res://game/systems/recon_drone.gd")
const LampScript = preload("res://game/levels/ep_lena_lamp.gd")

const FR_PRIMARY := Color(0.27, 0.29, 0.34)
const FR_SECONDARY := Color(0.33, 0.27, 0.19)
const FR_ARMBAND := Color(0.3, 0.68, 1.0)

## Dach A: Wohnblock links (Kollision x -30..-12, Oberkante 22). Dach B: Aufzugshaus auf dem Ministerium.
const PERCH_A := Vector3(-12.9, 22.1, -17.0)
const PERCH_B := Vector3(18.0, 30.1, -164.6)
const SPOTS_A: Array[Vector3] = [Vector3(-12.5, 22.0, -17.0), Vector3(-12.5, 22.0, -13.0), Vector3(-12.5, 22.0, -21.0), Vector3(-12.5, 22.0, -24.0)]
const SPOTS_B: Array[Vector3] = [Vector3(18.0, 30.0, -163.7), Vector3(15.7, 30.0, -163.7), Vector3(20.3, 30.0, -163.7), Vector3(15.7, 30.0, -166.5)]
## Dachmitte je Stellung: Bot-Ziel wird von hier aus 0,6 m über den Spot hinaus geschoben (Bot hält 0,7 m vorher an).
const ROOF_C: Array[Vector3] = [Vector3(-14.2, 22.0, -18.0), Vector3(18.0, 30.0, -166.0)]

const HOLDS: Array[Vector3] = [
	Vector3(4.6, 0.0, -6.0), Vector3(0.5, 0.0, -44.0), Vector3(-1.0, 0.0, -76.0),
	Vector3(-1.5, 0.0, -103.0), Vector3(11.0, 0.0, -114.6), Vector3(43.0, 0.0, -143.0),
]
## Weg von Haltepunkt i zu i+1 (Segmente 0..3); Segment 4 = Gasse (nach den Takedowns), danach Notausgang.
const SEG_PATHS: Array = [
	[Vector3(2.0, 0, -20.0), Vector3(1.0, 0, -40.0), Vector3(0.5, 0, -44.0)],
	[Vector3(0.0, 0, -56.0), Vector3(0.0, 0, -60.0), Vector3(0.0, 0, -66.0), Vector3(-1.0, 0, -76.0)],
	[Vector3(-1.5, 0, -95.0), Vector3(-1.5, 0, -103.0)],
	[Vector3(0.0, 0, -108.0), Vector3(8.0, 0, -114.5), Vector3(11.0, 0, -114.6)],
]
const LANE_ROUTE: Array[Vector3] = [
	Vector3(30.0, 0, -115.0), Vector3(36.0, 0, -115.5), Vector3(36.0, 0, -117.5), Vector3(36.0, 0, -120.0),
	Vector3(36.0, 0, -124.0), Vector3(36.0, 0, -127.0), Vector3(36.0, 0, -129.2), Vector3(39.0, 0, -130.2),
	Vector3(39.0, 0, -131.6), Vector3(39.0, 0, -133.5), Vector3(41.0, 0, -138.0), Vector3(43.0, 0, -143.0),
]
const EXIT_ROUTE: Array[Vector3] = [
	Vector3(42.0, 0, -146.6), Vector3(42.0, 0, -148.2), Vector3(42.5, 0, -149.4), Vector3(42.5, -0.5, -151.0),
	Vector3(42.5, -2.5, -155.0), Vector3(42.5, -4.9, -159.8), Vector3(42.5, -4.9, -162.5), Vector3(41.5, -4.9, -175.0),
	Vector3(41.5, -4.9, -188.0),
]
const LAMP_POS := Vector3(26.0, 16.2, -121.0)
const CSNIPER_POS := Vector3(-28.0, 24.0, -134.0)
const DOOR_POINT := Vector3(36.0, 1.2, -116.5)
const K_SPEED := 2.4
const K_HP := 100.0
const DL_TIME := 22.0
const SNIPER_DMG := 45.0
const DRONE_TOUR: Array = [Vector3(14.0, 12.0, -114.0), Vector3(24.0, 8.0, -114.5), Vector3(34.0, 8.0, -114.5)]

## Ziel-Stellvertreter für den Bot: Suchscheinwerfer-Kopf (lebt, solange die Lampe lebt).
class LampProxy extends Node3D:
	var lamp_ref: Node = null
	func is_alive() -> bool:
		return lamp_ref != null and is_instance_valid(lamp_ref) and bool(lamp_ref.call("is_alive"))

var ep_bot: RefCounted = null
var drone: Node
var lamp: StaticBody3D
var kerner: CharacterBody3D
var _ready_ok: bool = false
var _phase_arg: int = 0
var _perch: int = 0
var _seg: int = 0
var _cp_seg: int = 0
var _guards: Array = []              ## {d, a, ri, wait, moving, state, sus, t, flash, pos, dead, said, fire_t, scan, body, stuck}
var _combat: bool = false
var _resume_t: float = -1.0
var _fail: bool = false
var _ending: bool = false
var _relocating: bool = false
var _said: Dictionary = {}
var _ff_cool: float = 0.0

var _k_hp: float = K_HP
var _k_mode: String = "hold"         ## hold / move / takedown / download / exit / done
var _k_path: Array = []
var _k_pi: int = 0
var _k_stuck_t: float = 0.0
var _k_stuck_ref: Vector3 = Vector3.ZERO
var _k_stuck_check: float = 0.0
var _k_shoot_t: float = 2.0
var _k_td_queue: Array = []
var _k_td: Dictionary = {}
var _k_label: Label3D
var _k_hud: Label

var _lamp_pivot: Node3D
var _lamp_head: Node3D
var _lamp_light: SpotLight3D
var _lamp_proxy: Node3D
var _lamp_phase: float = 0.0
var _lamp_seen: float = 0.0

var _csniper: Dictionary = {}
var _glint_tex: Texture2D

var _dl_t: float = -1.0
var _dl_done: bool = false
var _late_sent: bool = false

var _drone_cd: float = 0.0
var _drone_t: float = 0.0
var _drone_flights: int = 0
var _bot_drone_wait: float = 1.5

var _fade: ColorRect
var _bt_target: Node3D = null
var _bt_spot: Vector3 = Vector3.ZERO
var _bt_aim_h: float = -1.0
var _bt_until: float = 0.0
var _los_cache: Dictionary = {}

func _init() -> void:
	level_name = "ep_lena"
	end_z = -199.0
	build_seed = 2030
	_wave_count = 1
	default_faction = "reich"
	ambient_artillery = false

func _ready() -> void:
	_phase_arg = clampi(int(str(Game.arg("phase", "0"))), 0, 6)
	_perch = 1 if _phase_arg >= 3 else 0
	await super()
	if not is_inside_tree():
		return
	_glint_tex = _make_glint_tex()
	_build_kerner()
	_build_overlay()
	var pl := _player()
	if _bot and pl != null:
		ep_bot = OwBot.new()
		ep_bot.call("setup", self, pl)
	_ready_ok = true
	if _phase_arg > 0:
		_apply_phase(_phase_arg)
	else:
		_intro()
	if pl != null:
		_aim_view(pl, kerner.global_position + Vector3.UP * 0.8)

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Lena – Über den Dächern"
	return info

# ------------------------------------------------------------------ Aufbau

func _setup_environment() -> void:
	super()
	# Weitere Sicht für das Zielfernrohr: Nebel halbieren (Optik bleibt curfew)
	for n in find_children("*", "WorldEnvironment", true, false):
		var env := (n as WorldEnvironment).environment
		if env != null:
			env.fog_density *= 0.5
			if env.volumetric_fog_enabled:
				env.volumetric_fog_density *= 0.5

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, PERCH_B if _perch == 1 else PERCH_A, "player_spawn")
	ps.name = "PlayerSpawn"
	ps.rotation_degrees.y = 180.0 if _perch == 1 else -122.0
	director = Stealth.new(self)
	add_child(director)
	_build_lamp()
	drone = ReconDrone.new()
	drone.set("pilot_label", "LENA")
	drone.set("director", director)
	add_child(drone)
	drone.connect("launched", _on_drone_launched)
	drone.connect("finished", _on_drone_finished)
	drone.connect("target_marked", _on_target_marked)
	_loop_3d("amb_siren", Vector3(-80.0, 20.0, -150.0), -22.0, 30.0, 400.0)

## Aufzugshaus auf dem Ministeriumsdach (Dach B) und unsichtbare Dachgrenzen für beide Stellungen.
func _build_set_piece_geometry() -> void:
	var body := StaticBody3D.new()
	body.name = "Aufzugshaus"
	body.set_meta("no_fit", true)
	body.set_meta("surface", "concrete")
	add_child(body)
	var mc: Material = mats.get("concrete", Geo.flat(Color(0.32, 0.31, 0.3)))
	var mm: Material = mats.get("metal", Geo.flat(Color(0.2, 0.2, 0.22), 0.5, 0.6))
	var parts: Array = [
		[Vector3(18.0, 28.0, -166.0), Vector3(6.0, 4.0, 6.0), mc],
		[Vector3(18.0, 30.15, -163.15), Vector3(6.0, 0.3, 0.3), mc],    # Kante zum Platz (niedrig: steiler Schuss nach unten)
		[Vector3(15.15, 30.25, -166.0), Vector3(0.3, 0.5, 6.0), mc],    # Brüstung zum Regierungsbau
		[Vector3(20.2, 30.35, -168.0), Vector3(1.2, 0.7, 1.4), mm],     # Lüfter
	]
	for p: Array in parts:
		body.add_child(Geo.box_mesh_node(p[1], p[2], p[0]))
		Geo.add_box_shape(body, p[0], p[1])
	body.add_child(Geo.box_mesh_node(Vector3(1.1, 2.1, 0.08), mm, Vector3(18.0, 27.05, -169.04)))   # Tür
	body.add_child(Geo.box_mesh_node(Vector3(0.06, 3.0, 0.06), mm, Vector3(20.6, 31.5, -168.6)))    # Antenne
	# Dach A: Rand, Mansarde und Dachgrenzen
	_invisible_wall(Vector3(-11.9, 23.5, -18.0), Vector3(0.2, 3.0, 13.4))
	_invisible_wall(Vector3(-16.5, 23.5, -18.0), Vector3(0.2, 3.0, 13.4))
	_invisible_wall(Vector3(-14.2, 23.5, -11.5), Vector3(4.8, 3.0, 0.2))
	_invisible_wall(Vector3(-14.2, 23.5, -24.5), Vector3(4.8, 3.0, 0.2))
	# Dach B
	_invisible_wall(Vector3(14.9, 32.0, -166.0), Vector3(0.2, 4.0, 6.6))
	_invisible_wall(Vector3(21.1, 32.0, -166.0), Vector3(0.2, 4.0, 6.6))
	_invisible_wall(Vector3(18.0, 32.0, -162.9), Vector3(6.6, 4.0, 0.2))
	_invisible_wall(Vector3(18.0, 32.0, -169.1), Vector3(6.6, 4.0, 0.2))

## Suchscheinwerfer auf dem Anbau (Optik wie curfew_searchlight.gd), Kopf abschießbar (ep_lena_lamp.gd).
func _build_lamp() -> void:
	lamp = LampScript.new() as StaticBody3D
	lamp.name = "Suchscheinwerfer"
	lamp.position = LAMP_POS
	lamp.set_meta("no_fit", true)
	lamp.set_meta("surface", "metal")
	add_child(lamp)
	var dark := Geo.flat(Color(0.06, 0.065, 0.07), 0.5, 0.6)
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.35
	bm.bottom_radius = 0.45
	bm.height = 0.5
	base.mesh = bm
	base.material_override = dark
	base.position.y = 0.25
	lamp.add_child(base)
	_lamp_pivot = Node3D.new()
	_lamp_pivot.position.y = 0.95
	lamp.add_child(_lamp_pivot)
	_lamp_pivot.add_child(Geo.box_mesh_node(Vector3(1.05, 0.7, 0.12), dark, Vector3(0, -0.15, 0)))
	_lamp_head = Node3D.new()
	_lamp_head.name = "Head"
	_lamp_pivot.add_child(_lamp_head)
	var drum := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.42
	dm.bottom_radius = 0.36
	dm.height = 0.9
	dm.radial_segments = 20
	drum.mesh = dm
	drum.material_override = dark
	drum.rotation_degrees.x = 90.0
	_lamp_head.add_child(drum)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.38
	lm.bottom_radius = 0.38
	lm.height = 0.02
	lens.mesh = lm
	lens.material_override = SearchlightScript.BP_unshaded(Color(6.0, 5.6, 4.8))
	lens.rotation_degrees.x = 90.0
	lens.position.z = -0.46
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_head.add_child(lens)
	_lamp_light = SpotLight3D.new()
	_lamp_light.light_color = Color(0.92, 0.95, 1.0)
	_lamp_light.light_energy = 26.0
	_lamp_light.spot_range = 36.0
	_lamp_light.spot_angle = 9.0
	_lamp_light.spot_angle_attenuation = 0.6
	_lamp_light.spot_attenuation = 0.4
	_lamp_light.shadow_enabled = true
	_lamp_light.light_volumetric_fog_energy = 1.4
	_lamp_light.position.z = -0.5
	_lamp_light.set_meta("no_stealth", true)   # Erfassung prüft das Level selbst
	_lamp_head.add_child(_lamp_light)
	var beam := SearchlightScript.beam_mesh(30.0, 0.35, tan(deg_to_rad(9.0)) * 30.0, 0.05, Color(0.85, 0.9, 1.0))
	_lamp_head.add_child(beam)
	lamp.set("light", _lamp_light)
	lamp.set("beam", beam)
	lamp.set("glass", lens)
	Geo.add_box_shape(lamp, Vector3(0, 0.95, 0), Vector3(1.3, 1.3, 1.3))
	lamp.connect("destroyed", _on_lamp_destroyed)
	_lamp_pivot.rotation.y = deg_to_rad(40.0)
	_lamp_head.rotation.x = deg_to_rad(-44.0)
	var px := LampProxy.new()
	px.name = "LampProxy"
	px.lamp_ref = lamp
	px.position = LAMP_POS + Vector3(0, 0.95 - 1.3, 0)
	add_child(px)
	_lamp_proxy = px

func _build_kerner() -> void:
	kerner = _make_actor("friendly", "rifleman", HOLDS[0], FR_PRIMARY, FR_SECONDARY, FR_ARMBAND, 0.0)
	kerner.name = "Kerner"
	kerner.set("invulnerable", true)
	kerner.set("crouch", true)
	_k_label = Label3D.new()
	_k_label.text = "KERNER"
	_k_label.font_size = 30
	_k_label.outline_size = 8
	_k_label.pixel_size = 0.0009
	_k_label.fixed_size = true
	_k_label.no_depth_test = true
	_k_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_k_label.modulate = Color(0.55, 0.82, 1.0, 0.9)
	_k_label.position = Vector3(0, 2.2, 0)
	kerner.add_child(_k_label)

func _build_overlay() -> void:
	var cl := CanvasLayer.new()
	cl.name = "EpLenaOverlay"
	cl.layer = 6
	add_child(cl)
	_k_hud = Label.new()
	_k_hud.position = Vector2(28, 96)
	_k_hud.add_theme_font_size_override("font_size", 20)
	_k_hud.add_theme_color_override("font_color", Color(0.62, 0.85, 1.0))
	_k_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_k_hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(_k_hud)
	var fl := CanvasLayer.new()
	fl.name = "EpLenaFade"
	fl.layer = 60
	add_child(fl)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_fade.visible = false
	fl.add_child(_fade)

func _make_actor(role: String, etype: String, pos: Vector3, prim: Color, sec: Color, band: Color, yaw: float) -> CharacterBody3D:
	var a: CharacterBody3D = Actor.new()
	a.set("role", role)
	a.set("enemy_type", etype)
	a.set("level_ref", self)
	if role == "enemy":
		a.set_meta("faction", "reich")
	else:
		a.set_meta("faction", "resistance")
		a.set("color_primary", prim)
		a.set("color_secondary", sec)
		a.set("color_armband", band)
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	a.name = "%s_%s_%d" % [role, etype, get_child_count()]
	add_child(a)
	a.global_position = Vector3(pos.x, maxf(pos.y, 0.0) + 0.05 if pos.y > -0.5 else pos.y + 0.05, pos.z)
	a.rotation.y = deg_to_rad(yaw)
	return a

# ------------------------------------------------------------------ Wachen

func _guard_defs() -> Array:
	return [
		{"key": "street", "type": "rifleman", "flash": true, "gate": 0, "block": true, "route": [_wp(7.0, -22.0, 3.0, 0.0), _wp(7.0, -36.0, 3.0, 180.0)]},
		{"key": "officer", "type": "officer", "flash": false, "gate": 1, "block": true, "route": [_wp(6.2, -64.2, 0.0, 180.0)]},
		{"key": "post", "type": "rifleman", "flash": false, "gate": 1, "block": true, "route": [_wp(-2.0, -60.2, 3.0, 180.0), _wp(2.6, -60.4, 3.0, 160.0)]},
		{"key": "south", "type": "rifleman", "flash": true, "gate": 2, "block": true, "route": [_wp(-4.5, -92.0, 3.0, 0.0), _wp(4.5, -101.0, 3.0, 180.0)]},
		{"key": "plaza", "type": "rifleman", "flash": true, "gate": 3, "block": true,
			"route": [_wp(-10.0, -125.0, 2.0, 90.0), _wp(10.0, -125.0, 2.0, -90.0), _wp(10.0, -146.0, 2.0, -90.0), _wp(-10.0, -146.0, 2.0, 90.0)]},
		{"key": "plaza_w", "type": "rifleman", "flash": true, "gate": 3, "block": false, "route": [_wp(-19.5, -117.0, 3.0, 180.0), _wp(-19.5, -155.0, 3.0, 0.0)]},
		{"key": "portal_n", "type": "rifleman", "flash": false, "gate": 3, "block": false, "route": [_wp(22.4, -137.6, 0.0, 90.0)]},
		{"key": "portal_s", "type": "rifleman", "flash": false, "gate": 3, "block": false, "route": [_wp(22.4, -142.4, 0.0, 90.0)]},
		{"key": "lane", "type": "rifleman", "flash": false, "gate": 4, "block": true, "lane": true, "route": [_wp(26.5, -115.2, 5.0, 180.0), _wp(42.5, -115.2, 3.5, -90.0)]},
		{"key": "door", "type": "rifleman", "flash": false, "gate": 4, "block": true, "lane": true, "route": [_wp(39.5, -116.4, 0.0, -90.0)]},
	]

## Eigene Wachen (Puppen, vom Level gesteuert) statt der curfew-Schleich-KI.
func _spawn_wave(index: int) -> void:
	if _waves_spawned.has(index) or not spawn_enemies or index != 0:
		return
	_waves_spawned[index] = true
	wave_started.emit(index)
	for d: Dictionary in _guard_defs():
		if int(d["gate"]) >= _phase_arg:
			_add_guard(d)

func _add_guard(d: Dictionary) -> Dictionary:
	var route: Array = d["route"]
	var r0: Dictionary = route[0]
	var p0: Vector3 = r0["p"]
	var a := _make_actor("enemy", str(d["type"]), Vector3(p0.x, 0.0, p0.z), Color.BLACK, Color.BLACK, Color.BLACK, 0.0)
	var y: float = r0["yaw"]
	a.rotation.y = 0.0 if is_nan(y) else y
	var fl: SpotLight3D = null
	if bool(d.get("flash", false)):
		fl = SpotLight3D.new()
		fl.light_color = Color(1.0, 0.95, 0.82)
		fl.light_energy = 3.0
		fl.spot_range = 16.0
		fl.spot_angle = 18.0
		fl.light_volumetric_fog_energy = 1.2
		fl.shadow_enabled = false
		fl.set_meta("no_stealth", true)
		fl.position = Vector3(0.22, 1.3, -0.35)
		fl.rotation_degrees.x = -10.0
		a.add_child(fl)
	var g := {"d": d, "a": a, "ri": 0, "wait": float(r0["wait"]), "moving": false, "state": "patrol", "sus": 0.0,
		"t": 0.0, "flash": fl, "pos": a.global_position, "dead": false, "said": false,
		"fire_t": rng.randf_range(0.6, 1.4), "scan": rng.randf() * 0.2, "body": Vector3.ZERO, "stuck": 0.0, "ref": a.global_position}
	_guards.append(g)
	if drone != null:
		drone.call("add_target", a, "guard", "Scharfschütze" if str(d["type"]) == "marksman" else "Wache")
	return g

func _tick_guards(delta: float) -> void:
	for g: Dictionary in _guards:
		var a := _node(g["a"])
		if bool(g["dead"]):
			continue
		if not _alive(a):
			g["dead"] = true
			g["state"] = "dead"
			_on_guard_down(g)
			continue
		g["pos"] = a.global_position
		match str(g["state"]):
			"patrol":
				_guard_patrol(g, a, delta)
				_guard_watch(g, a, delta)
			"curious":
				a.set("has_goal", false)
				_face(a, kerner.global_position, delta)
				_guard_watch(g, a, delta)
				if float(g["sus"]) < 0.06:
					g["state"] = "patrol"
					g["wait"] = 1.0
					g["moving"] = false
			"witness":
				a.set("has_goal", false)
				_face(a, g["body"], delta)
				g["t"] = float(g["t"]) - delta
				if float(g["t"]) <= 0.0:
					_witness_act(g, a)
			"search":
				_guard_search(g, a, delta)
				_guard_watch(g, a, delta)
			"hostile":
				_guard_hostile(g, a, delta)
			"frozen":
				a.set("has_goal", false)
				a.set("aiming", false)
				a.rotation.y = lerp_angle(a.rotation.y, deg_to_rad(-90.0), clampf(delta * 4.0, 0.0, 1.0))
			"late":
				_guard_late(g, a, delta)
			"door":
				_guard_door(g, a, delta)
	# Kampf vorbei?
	if _combat and _count_state("hostile") == 0:
		_combat = false
		_resume_t = 2.5
		if director != null:
			director.call("end_alarm")
		if not _fail:
			_say(SD.LENA, "Das war der Letzte. Atme, Jonas. Dann weiter.")

func _guard_patrol(g: Dictionary, a: Node3D, delta: float) -> void:
	var route: Array = g["d"]["route"]
	var wp: Dictionary = route[int(g["ri"])]
	if bool(g["moving"]):
		if bool(a.get("has_goal")):
			_guard_unstick(g, a, wp["p"], delta)
			return
		g["moving"] = false
		g["wait"] = float(wp["wait"])
		return
	var y: float = wp["yaw"]
	if not is_nan(y):
		a.rotation.y = lerp_angle(a.rotation.y, y, clampf(delta * 3.0, 0.0, 1.0))
	if route.size() <= 1:
		return
	g["wait"] = float(g["wait"]) - delta
	if float(g["wait"]) > 0.0:
		return
	g["ri"] = (int(g["ri"]) + 1) % route.size()
	var nxt: Dictionary = route[int(g["ri"])]
	a.call("walk_to", nxt["p"], 1.3, true)
	g["moving"] = true
	g["stuck"] = 0.0
	g["ref"] = a.global_position

## Festhängen: nach 5 s ohne Fortschritt ans Ziel setzen (Testhilfe, wie die Bots).
func _guard_unstick(g: Dictionary, a: Node3D, goal: Vector3, delta: float) -> void:
	g["stuck"] = float(g["stuck"]) + delta
	if float(g["stuck"]) < 5.0:
		return
	g["stuck"] = 0.0
	if a.global_position.distance_to(g["ref"]) < 0.5:
		a.global_position = Vector3(goal.x, a.global_position.y, goal.z)
	g["ref"] = a.global_position

## Wahrnehmung: Sichtkegel 55°, Reichweite nach Licht/Haltung, Taschenlampe +10 m; Verdacht steigt bis 1.0.
func _guard_watch(g: Dictionary, a: Node3D, delta: float) -> void:
	g["scan"] = float(g["scan"]) - delta
	if float(g["scan"]) > 0.0:
		return
	g["scan"] = 0.2
	var rate := _guard_detect(g, a)
	if rate > 0.0:
		g["sus"] = minf(1.0, float(g["sus"]) + rate * 0.2)
	else:
		g["sus"] = maxf(0.0, float(g["sus"]) - 0.25 * 0.2)
	var s: float = g["sus"]
	if s >= 1.0:
		_start_combat("spotted")
	elif s > 0.3 and str(g["state"]) == "patrol":
		g["state"] = "curious"
		a.set("has_goal", false)
		g["moving"] = false
		if not bool(g["said"]):
			g["said"] = true
			_say(SD.LENA, "Einer schaut zu dir rüber. Nicht bewegen, Jonas.")

func _guard_detect(g: Dictionary, a: Node3D) -> float:
	if _k_hidden() or kerner == null:
		return 0.0
	var kp := kerner.global_position
	var gp := a.global_position
	var to := kp - gp
	to.y = 0.0
	var d := to.length()
	if d > 40.0 or d < 0.1:
		return 0.0
	var fwd := -a.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		return 0.0
	var ang := rad_to_deg(fwd.normalized().angle_to(to / d))
	if ang > 55.0:
		return 0.0
	var crouch := bool(kerner.get("crouch"))
	var still := Vector2(kerner.velocity.x, kerner.velocity.z).length() < 0.3
	var chest := kp + Vector3.UP * (0.7 if crouch else 1.2)
	var lit: float = float(director.call("light_at", chest)) if director != null else 0.0
	var reach := 5.0 + 20.0 * lit
	if crouch:
		reach *= 0.45 if still else 0.75
	if g["flash"] != null and ang < 18.0:
		reach += 5.0 if (crouch and still) else 10.0
	if d > reach:
		return 0.0
	if not _ray_clear(gp + Vector3.UP * 1.6, chest):
		return 0.0
	return 0.5 + 1.5 * (1.0 - d / reach)

## Tote Wache: wer es sieht (20 m, 75°, Sicht), meldet nach 3,2 s – Kampf oder Suche.
func _on_guard_down(g: Dictionary) -> void:
	var bp: Vector3 = g["pos"]
	var any := false
	for o: Dictionary in _guards:
		if o == g or bool(o["dead"]) or not (str(o["state"]) in ["patrol", "curious", "search"]):
			continue
		var a := _node(o["a"])
		if not _alive(a):
			continue
		var to := bp - a.global_position
		to.y = 0.0
		var d := to.length()
		if d > 20.0 or d < 0.1:
			continue
		var fwd := -a.global_transform.basis.z
		fwd.y = 0.0
		if rad_to_deg(fwd.normalized().angle_to(to / d)) > 75.0:
			continue
		if not _ray_clear(a.global_position + Vector3.UP * 1.6, bp + Vector3.UP * 0.5):
			continue
		o["state"] = "witness"
		o["t"] = 3.2
		o["body"] = bp
		a.set("has_goal", false)
		o["moving"] = false
		any = true
	if any:
		_say(SD.LENA, "Der andere hat ihn fallen sehen – schnell!")

func _witness_act(g: Dictionary, a: Node3D) -> void:
	var kd := a.global_position.distance_to(kerner.global_position)
	if kd < 25.0 and not _k_hidden():
		_start_combat("body")
		return
	g["state"] = "search"
	g["t"] = -1.0
	a.call("walk_to", g["body"], 2.2, true)
	g["stuck"] = 0.0
	g["ref"] = a.global_position
	if director != null:
		director.call("raise_alarm", g["body"], "body", false)
	_say(SD.ORDNUNG, "Mann am Boden! Alle Posten: Sperrgebiet absuchen!")

func _guard_search(g: Dictionary, a: Node3D, delta: float) -> void:
	if float(g["t"]) < 0.0:
		if bool(a.get("has_goal")):
			_guard_unstick(g, a, g["body"], delta)
			return
		g["t"] = 12.0
		return
	_face(a, g["body"], delta)
	g["t"] = float(g["t"]) - delta
	if float(g["t"]) <= 0.0:
		g["state"] = "patrol"
		g["ri"] = 0
		var r0: Dictionary = (g["d"]["route"] as Array)[0]
		a.call("walk_to", r0["p"], 1.3, true)
		g["moving"] = true
		g["sus"] = 0.0
		if _count_state("search") == 0 and not _combat and director != null:
			director.call("end_alarm")

func _guard_hostile(g: Dictionary, a: Node3D, delta: float) -> void:
	var kp := kerner.global_position
	var chest := kp + Vector3.UP * (0.8 if bool(kerner.get("crouch")) else 1.2)
	var d := a.global_position.distance_to(kp)
	var see := d < 30.0 and _ray_clear(a.global_position + Vector3.UP * 1.5, chest)
	if not see:
		a.set("aiming", false)
		g["t"] = float(g["t"]) - delta
		if not bool(a.get("has_goal")) or float(g["t"]) <= 0.0:
			g["t"] = 2.0
			a.call("walk_to", kp, 2.6, true)
		return
	a.set("has_goal", false)
	a.set("aiming", true)
	a.set("aim_point", chest)
	g["fire_t"] = float(g["fire_t"]) - delta
	if float(g["fire_t"]) <= 0.0:
		g["fire_t"] = rng.randf_range(1.1, 1.8)
		a.call("puppet_fire", chest, 0.6)
		_k_damage(7.0 * (0.6 if bool(kerner.get("crouch")) else 1.0))

## Späte Streife: läuft über den Platz zur Anlieferung; am Tor schießt sie auf Kerner im Anbau.
func _guard_late(g: Dictionary, a: Node3D, delta: float) -> void:
	var route: Array = g["d"]["route"]
	if a.global_position.x >= 21.0:
		g["state"] = "door"
		a.set("has_goal", false)
		g["fire_t"] = 0.8
		if not _said.has("late_door"):
			_said["late_door"] = true
			_say(SD.KERNER, "Sie sind am Tor! Lena!")
		return
	var wp: Vector3 = (route[int(g["ri"])] as Dictionary)["p"]
	if not bool(a.get("has_goal")):
		if Vector2(a.global_position.x - wp.x, a.global_position.z - wp.z).length() < 1.0 and int(g["ri"]) < route.size() - 1:
			g["ri"] = int(g["ri"]) + 1
			wp = (route[int(g["ri"])] as Dictionary)["p"]
		a.call("walk_to", wp, 1.6, true)
		g["stuck"] = 0.0
		g["ref"] = a.global_position
	else:
		_guard_unstick(g, a, wp, delta)

func _guard_door(g: Dictionary, a: Node3D, delta: float) -> void:
	a.set("has_goal", false)
	a.set("aiming", true)
	a.set("aim_point", DOOR_POINT)
	g["fire_t"] = float(g["fire_t"]) - delta
	if float(g["fire_t"]) <= 0.0:
		g["fire_t"] = 1.5
		a.call("puppet_fire", DOOR_POINT, 0.8)
		if _k_mode in ["download", "hold"] and _seg == 5:
			_k_damage(7.0)

func _start_combat(reason: String) -> void:
	if _fail or _ending or kerner == null:
		return
	var kp := kerner.global_position
	var picked := 0
	var cands: Array = []
	for g: Dictionary in _guards:
		if bool(g["dead"]) or str(g["state"]) in ["frozen", "late", "door", "hostile", "dead"]:
			continue
		var a := _node(g["a"])
		if not _alive(a):
			continue
		var d := a.global_position.distance_to(kp)
		cands.append([d, g])
		if d < 45.0:
			_make_hostile(g, a)
			picked += 1
	if picked == 0 and _count_state("hostile") == 0 and not cands.is_empty():
		# Niemand in der Nähe: die zwei nächsten Wachen rücken an
		cands.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		for i in mini(2, cands.size()):
			var g2: Dictionary = cands[i][1]
			_make_hostile(g2, _node(g2["a"]))
	if _count_state("hostile") == 0:
		return
	kerner.set("has_goal", false)
	kerner.set("crouch", true)
	if not _combat:
		_combat = true
		_k_shoot_t = 2.0
		if director != null:
			director.call("raise_alarm", kp, reason, true)
		match reason:
			"searchlight":
				_say(SD.ORDNUNG, "Scheinwerfer hat ihn! Alarm, Alarm!")
			_:
				_say(SD.ORDNUNG, "Eindringling gesichtet! Alarm!")
		_later(1.6, func() -> void:
			if _combat and not _fail:
				_say(SD.KERNER, "Kontakt! Sie haben mich – Lena, ich brauch dich!"))

func _make_hostile(g: Dictionary, a: Node3D) -> void:
	if a == null:
		return
	g["state"] = "hostile"
	g["fire_t"] = rng.randf_range(0.8, 1.6)
	g["t"] = 0.0
	g["moving"] = false
	a.set("has_goal", false)

func _count_state(st: String) -> int:
	var n := 0
	for g: Dictionary in _guards:
		if not bool(g["dead"]) and str(g["state"]) == st and _alive(_node(g["a"])):
			n += 1
	return n

func _face(a: Node3D, p: Vector3, delta: float) -> void:
	var to := p - a.global_position
	to.y = 0.0
	if to.length() < 0.05:
		return
	a.rotation.y = lerp_angle(a.rotation.y, atan2(-to.x, -to.z), clampf(delta * 4.0, 0.0, 1.0))

# ------------------------------------------------------------------ Kerner

func _k_hidden() -> bool:
	return _fail or _k_mode in ["download", "exit", "done"]

func _tick_kerner(delta: float) -> void:
	if kerner == null or _fail or _ending:
		return
	if _resume_t > 0.0:
		_resume_t -= delta
	var paused := _combat or _resume_t > 0.0 or _count_state("curious") > 0 or _count_state("witness") > 0
	if _combat:
		_kerner_fight(delta)
	match _k_mode:
		"hold":
			kerner.set("crouch", true)
			if not paused and _gate_ok(_seg):
				_gate_open(_seg)
		"move", "exit":
			if paused and _k_mode == "move":
				kerner.set("has_goal", false)
				kerner.set("crouch", true)
				return
			_follow_path(delta)
		"takedown":
			if paused:
				kerner.set("has_goal", false)
				return
			_tick_takedown(delta)
		"download":
			_dl_t += delta
			if _dl_t >= 4.0 and not _late_sent:
				_send_late()
			if _dl_t >= DL_TIME and not _dl_done:
				_dl_done = true
				_say(SD.KERNER, "Hab sie. Alles drauf.")
				if _count_late() > 0:
					_later(2.2, func() -> void:
						if _count_late() > 0:
							_say(SD.LENA, "Warte, Jonas. Draußen sind noch zwei."))
			if _dl_done and _gate_ok(5):
				_gate_open(5)

func _kerner_fight(delta: float) -> void:
	_k_shoot_t -= delta
	if _k_shoot_t > 0.0:
		return
	_k_shoot_t = rng.randf_range(3.0, 4.5)
	var kp := kerner.global_position
	var best: Node3D = null
	var bd := 30.0
	for g: Dictionary in _guards:
		if bool(g["dead"]) or str(g["state"]) != "hostile":
			continue
		var a := _node(g["a"])
		if not _alive(a):
			continue
		var d := a.global_position.distance_to(kp)
		if d < bd and _ray_clear(kp + Vector3.UP * 1.0, a.global_position + Vector3.UP * 1.3):
			bd = d
			best = a
	if best == null:
		return
	var tp := best.global_position + Vector3.UP * 1.3
	kerner.call("puppet_fire", tp, 0.1)
	best.call("take_damage", 100.0, kerner, tp, Vector3.UP)

func _follow_path(delta: float) -> void:
	if _k_pi >= _k_path.size():
		kerner.set("has_goal", false)
		_on_path_done()
		return
	var tgt: Vector3 = _k_path[_k_pi]
	var kp := kerner.global_position
	var flat := Vector2(tgt.x - kp.x, tgt.z - kp.z).length()
	if flat < 0.75 and absf(tgt.y - kp.y) < 1.6:
		_k_pi += 1
		_k_stuck_t = 0.0
		return
	kerner.set("crouch", _k_mode == "move")
	var goal: Vector3 = kerner.get("goal")
	if not bool(kerner.get("has_goal")) or goal.distance_to(tgt) > 0.1:
		kerner.call("walk_to", tgt, K_SPEED if _k_mode == "move" else 3.2, true)
	_k_unstick(tgt, delta)

func _k_unstick(tgt: Vector3, delta: float) -> void:
	_k_stuck_check -= delta
	if _k_stuck_check > 0.0:
		return
	_k_stuck_check = 1.0
	var kp := kerner.global_position
	if kp.distance_to(_k_stuck_ref) < 0.3:
		_k_stuck_t += 1.0
	else:
		_k_stuck_t = 0.0
	_k_stuck_ref = kp
	if _k_stuck_t >= 4.0:
		print("[ep_lena] Kerner haengt bei %s -> %s" % [str(kp), str(tgt)])
		kerner.global_position = tgt + Vector3(0, 0.05, 0)
		_k_stuck_t = 0.0

func _start_path(path: Array, mode: String) -> void:
	_k_path = path.duplicate()
	_k_pi = 0
	_k_mode = mode
	_k_stuck_t = 0.0
	_k_stuck_ref = kerner.global_position

func _on_path_done() -> void:
	if _k_mode == "exit":
		_k_mode = "done"
		_finish_episode()
		return
	_seg += 1
	_arrive(_seg)

## Gate i: Bedingungen, damit Kerner Haltepunkt i verlassen darf.
func _gate_ok(i: int) -> bool:
	if _relocating:
		return false
	for g: Dictionary in _guards:
		if bool(g["dead"]):
			continue
		var st := str(g["state"])
		if st in ["curious", "hostile", "witness"]:
			return false
		var d: Dictionary = g["d"]
		if int(d["gate"]) != i or not bool(d.get("block", false)):
			continue
		if not _alive(_node(g["a"])):
			continue
		if bool(d.get("lane", false)) and drone != null and bool(drone.call("is_marked", g["a"])):
			continue
		return false
	match i:
		3:
			return _perch == 1 and lamp != null and bool(lamp.get("dead"))
		4:
			return not _csniper.is_empty() and not _alive(_node(_csniper["a"]))
		5:
			return _dl_done and _late_sent and _count_late() == 0
	return true

func _gate_open(i: int) -> void:
	match i:
		0:
			_say(SD.LENA, "Streife liegt. Geh, Jonas – an der rechten Hauswand entlang.")
			_later(2.6, func() -> void: _say(SD.KERNER, "Unterwegs."))
		1:
			_say(SD.LENA, "Kontrollpunkt ist frei. Durch die Schranke, Jonas, und nicht stehen bleiben.")
		2:
			_say(SD.LENA, "Weg ist frei. Bis zum Platz – dort muss ich umziehen.")
		3:
			_say(SD.LENA, "Platz ist sauber. Rüber zur Lieferzufahrt, Jonas – an der Hausecke warten.")
		4:
			_say(SD.KERNER, "Verstanden. Ich nehm sie mir leise.")
		5:
			_say(SD.LENA, "Raus jetzt. Notausgang, runter in den Schacht – Voss wartet unten.")
	_obj("Decke Kerner auf seinem Weg")
	if i <= 3:
		_start_path(SEG_PATHS[i], "move")
	elif i == 4:
		_k_td_queue.clear()
		for g: Dictionary in _guards:
			if bool(g["dead"]) or not bool(g["d"].get("lane", false)):
				continue
			var a := _node(g["a"])
			if not _alive(a):
				continue
			g["state"] = "frozen"
			a.set("has_goal", false)
			_k_td_queue.append(g)
		_k_td_queue.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return (x["pos"] as Vector3).x < (y["pos"] as Vector3).x)
		_k_td = {}
		_k_mode = "takedown"
		_k_stuck_t = 0.0
		_k_stuck_ref = kerner.global_position
	else:
		_start_path(EXIT_ROUTE, "exit")
		_obj("")

func _arrive(s: int) -> void:
	_k_mode = "hold"
	kerner.set("has_goal", false)
	kerner.set("crouch", true)
	_cp_seg = s
	if s != 3:
		_checkpoint("ep_cp%d" % s)
	match s:
		1:
			_say(SD.LENA, "Stopp. Kontrollpunkt vor dir – ein Offizier am Häuschen, ein Posten an der Schranke. Ich nehme beide, kurz hintereinander.")
		2:
			_say(SD.LENA, "Halt. Einer kommt dir entgegen, Taschenlampe. Duck dich in den Hauseingang.")
		3:
			_relocate()
		4:
			_spawn_csniper()
			_say(SD.KERNER, "Lena, Blitzen auf dem Regierungsbau! Da drüben liegt einer!")
			_later(3.4, func() -> void: _say(SD.LENA, "Gesehen. Gegenscharfschütze, Dachkante. Wenn er blitzt, geh ich runter."))
		5:
			_start_download()
	_obj(_objective_for(s))

func _objective_for(s: int) -> String:
	match s:
		0:
			return "Decke Kerner: Schalte die Streife auf der Straße aus"
		1:
			return "Kontrollpunkt: Offizier und Posten kurz hintereinander ausschalten"
		2:
			return "Schalte die Streife mit der Taschenlampe aus"
		3:
			return "Schalte die Platzstreife und den Suchscheinwerfer auf dem Anbau aus"
		4:
			if _csniper.is_empty() or _alive(_node(_csniper.get("a"))):
				return "Gegenscharfschütze auf dem Regierungsbau – bei Blitzen hinlegen [%s]" % _key("prone")
			return "Drohne [%s]: Wachen in der Lieferzufahrt markieren – [%s] Wärmebild" % [_key("drone_toggle"), _key("drone_thermal")]
		5:
			return "Halte Kerner den Rücken frei, bis die Übertragung durch ist"
	return ""

func _tick_takedown(delta: float) -> void:
	if _k_td.is_empty() or not _alive(_node(_k_td["a"])):
		_k_td = {}
		while not _k_td_queue.is_empty():
			var nx: Dictionary = _k_td_queue.pop_front()
			if _alive(_node(nx["a"])):
				_k_td = nx
				break
		if _k_td.is_empty():
			_say(SD.KERNER, "Gasse sauber. Ich geh rein.")
			_start_path(LANE_ROUTE, "move")
			_seg = 4
			return
	var a := _node(_k_td["a"])
	var p := a.global_position + Vector3(-1.0, 0.0, 0.0)
	var kp := kerner.global_position
	kerner.set("crouch", true)
	if Vector2(a.global_position.x - kp.x, a.global_position.z - kp.z).length() < 1.5:
		kerner.set("has_goal", false)
		var hp := a.global_position + Vector3.UP * 1.3
		a.call("take_damage", 500.0, kerner, hp, Vector3.UP)
		VFX.play_sfx_3d("curfew_takedown", hp, -4.0, 8.0, 40.0)
		_k_td["state"] = "dead"
		_k_td = {}
		if not _k_td_queue.is_empty():
			_say(SD.KERNER, "Einer weniger.")
		return
	var goal: Vector3 = kerner.get("goal")
	if not bool(kerner.get("has_goal")) or goal.distance_to(p) > 0.3:
		kerner.call("walk_to", p, 2.2, true)
	_k_unstick(p, delta)

func _k_damage(n: float) -> void:
	if _fail or _ending:
		return
	_k_hp -= n
	if _k_hp <= 0.0:
		_kerner_down()

func _kerner_down() -> void:
	_fail = true
	_k_hp = 0.0
	kerner.set("has_goal", false)
	kerner.set("aiming", false)
	kerner.set("frozen", true)
	_say(SD.LENA, "Jonas! – Nein. Nicht so. Nicht heute Nacht.")
	_later(2.4, func() -> void:
		var pl := _player()
		if pl != null:
			pl.respawn())

# ------------------------------------------------------------------ Abschnitte

func _intro() -> void:
	_obj(_objective_for(0))
	_later(1.0, func() -> void: _say(SD.LENA, "Jonas, ich bin auf dem Dach gegenüber. Ab hier gilt Ausgangssperre – wer sich bewegt, wird erschossen."))
	_later(6.0, func() -> void: _say(SD.KERNER, "Dann sollte mich besser keiner sehen."))
	_later(9.0, func() -> void: _say(SD.LENA, "Bleib unten, bis ich die Straße frei habe. Ich hab dich im Glas."))

## Umzug aufs Ministerium (Abblende), danach Checkpoint auf Dach B.
func _relocate() -> void:
	if _perch == 1:
		_checkpoint("ep_cp3")
		return
	_relocating = true
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "scene")
	_say(SD.LENA, "Von hier seh ich den Platz nicht. Ich wechsle aufs Ministerium – zwei Minuten, Jonas. Rühr dich nicht.")
	_later(3.6, func() -> void: _say(SD.KERNER, "Ich warte. Beeil dich."))
	_fade.visible = true
	_fade.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(_fade, "modulate:a", 1.0, 0.8)
	tw.tween_callback(_relocate_jump)
	tw.tween_interval(1.4)
	tw.tween_property(_fade, "modulate:a", 0.0, 0.9)
	tw.tween_callback(_relocate_done)

func _relocate_jump() -> void:
	_perch = 1
	var pl := _player()
	if pl != null:
		pl.global_position = PERCH_B + Vector3(0, 0.05, 0)
		pl.velocity = Vector3.ZERO
		_aim_view(pl, Vector3(4.0, 1.0, -132.0))
	_checkpoint("ep_cp3")

func _relocate_done() -> void:
	_fade.visible = false
	_relocating = false
	_say(SD.LENA, "Bin oben. Aufzugshaus, Ministeriumsdach. Ich seh den ganzen Platz.")
	_later(4.0, func() -> void:
		if lamp != null and not bool(lamp.get("dead")):
			_say(SD.LENA, "Der Scheinwerfer auf dem Anbau streicht über den Platz. Ein Schuss ins Glas, und er ist blind."))

func _on_lamp_destroyed() -> void:
	_lamp_seen = 0.0
	_say(SD.ORDNUNG, "Anbau B an Zentrale: Scheinwerfer ausgefallen. Vermutlich der Regen.")
	_later(3.4, func() -> void: _say(SD.LENA, "Der Regen hat heute Nacht gute Augen."))

func _start_download() -> void:
	_k_mode = "download"
	_dl_t = 0.0
	_dl_done = false
	_late_sent = false
	kerner.set("has_goal", false)
	_say(SD.LENA, "Ab jetzt bist du für mich unsichtbar, Jonas. Ich halte dir den Rücken frei.")
	_later(3.0, func() -> void: _say(SD.KERNER, "Terminal gefunden. Übertragung läuft – zweiundzwanzig Sekunden."))

func _send_late() -> void:
	_late_sent = true
	if not spawn_enemies:
		return
	for i in 2:
		var d := {"key": "late%d" % i, "type": "rifleman", "flash": true, "gate": 5, "block": false, "late": true,
			"route": [_wp(-19.5 + i * 1.4, -152.0 + i * 1.2, 0.0), _wp(6.0 + i * 1.2, -118.0 - i * 0.6, 0.0), _wp(22.0, -115.2 - i * 0.8, 0.0)]}
		var g := _add_guard(d)
		g["state"] = "late"
		g["ri"] = 1
	_say(SD.ORDNUNG, "Zentrale an Streife Platz: Zwei Mann zur Anlieferung B, Sichtkontrolle.")
	_later(3.6, func() -> void: _say(SD.LENA, "Zwei kommen über den Platz, Richtung Anlieferung. Die erreichen das Tor nicht."))

func _count_late() -> int:
	var n := 0
	for g: Dictionary in _guards:
		if bool(g["d"].get("late", false)) and not bool(g["dead"]) and _alive(_node(g["a"])):
			n += 1
	return n

func _finish_episode() -> void:
	if _ending:
		return
	_ending = true
	_finished = true
	_obj("")
	_say(SD.VOSS, "Kerner. Konrad Voss. Willkommen im Untergrund – Lena hat nicht übertrieben.")
	_later(4.5, func() -> void: _say(SD.LENA, "Er ist unten. Funk aus, Gewehr runter."))
	_later(9.0, func() -> void: _say(SD.LENA, "Jonas weiß nicht, dass ich Höhenangst habe. Seit ich denken kann."))
	_later(14.0, func() -> void: _say(SD.LENA, "Mein Vater war Schornsteinfeger in Mitte. Er hat gesagt: Man lernt nicht, keine Angst zu haben – man lernt nur, wohin man schaut."))
	_later(21.5, func() -> void: _say(SD.LENA, "Heute Nacht hab ich nur durchs Glas geschaut. Auf Jonas. Hat funktioniert, Papa."))
	_later(27.0, _on_level_end)

## --phase=N: Kerner an Haltepunkt N, frühere Wachen fehlen (siehe _spawn_wave), Dach B ab 3.
func _apply_phase(n: int) -> void:
	_seg = mini(n, 5)
	_cp_seg = _seg
	kerner.global_position = HOLDS[_seg] + Vector3(0, 0.05, 0)
	if n >= 4 and lamp != null:
		lamp.set("dead", true)
		for nd: Node3D in [_lamp_light, lamp.get("beam") as Node3D, lamp.get("glass") as Node3D]:
			if nd != null:
				nd.visible = false
	if n == 4:
		_spawn_csniper()
	if n == 5:
		_start_download()
	elif n >= 6:
		_dl_done = true
		_late_sent = true
		_start_path(EXIT_ROUTE, "exit")
	else:
		_k_mode = "hold" if n != 5 else "download"
	_obj(_objective_for(_seg))

func _reset_to_cp(cp: int) -> void:
	_fail = false
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "respawn")
	_combat = false
	_resume_t = -1.0
	var keep: Array = []
	var again: Array = []
	for g: Dictionary in _guards:
		var d: Dictionary = g["d"]
		var a := _node(g["a"])
		if bool(d.get("late", false)) or int(d["gate"]) >= cp:
			if a != null:
				if drone != null:
					drone.call("remove_target", a)
				a.queue_free()
			if not bool(d.get("late", false)):
				again.append(d)
			continue
		if not bool(g["dead"]) and _alive(a):
			var r0: Dictionary = (d["route"] as Array)[0]
			var p0: Vector3 = r0["p"]
			a.global_position = Vector3(p0.x, 0.05, p0.z)
			var y: float = r0["yaw"]
			a.rotation.y = 0.0 if is_nan(y) else y
			a.set("has_goal", false)
			a.set("aiming", false)
			g["state"] = "patrol"
			g["sus"] = 0.0
			g["ri"] = 0
			g["moving"] = false
			g["wait"] = float(r0["wait"])
		keep.append(g)
	_guards = keep
	for d: Dictionary in again:
		_add_guard(d)
	_dl_t = -1.0
	_dl_done = false
	_late_sent = false
	_said.erase("late_door")
	var s := mini(cp, 5)
	kerner.set("frozen", false)
	kerner.set("has_goal", false)
	kerner.set("aiming", false)
	kerner.set("crouch", true)
	kerner.velocity = Vector3.ZERO
	kerner.global_position = HOLDS[s] + Vector3(0, 0.05, 0)
	_k_hp = K_HP
	_seg = s
	_k_mode = "hold"
	_k_path = []
	_k_td = {}
	_k_td_queue.clear()
	_free_csniper()
	if s == 4:
		_spawn_csniper()
	if s <= 3 and lamp != null:
		lamp.call("restore")
		_lamp_seen = 0.0
	if s == 5:
		_start_download()
	if director != null:
		director.call("reset_all")
	_bt_target = null
	_los_cache.clear()
	_obj(_objective_for(s))

func _on_player_respawned() -> void:
	if not _ready_ok or _ending:
		return
	_reset_to_cp(_cp_seg)

func _equip_suppressed() -> void:
	var pl := _player()
	if pl == null:
		return
	pl.give_weapon("g28", 10, 90)
	if pl.weapon_index != 0:
		pl._do_switch(0)

func _build_exit_gate() -> void:
	pass

# ------------------------------------------------------------------ Suchscheinwerfer

func _tick_lamp(delta: float) -> void:
	if lamp == null or bool(lamp.get("dead")):
		return
	_lamp_phase += delta * 0.07
	var k := 0.5 - 0.5 * cos(_lamp_phase * TAU)
	_lamp_pivot.rotation.y = deg_to_rad(lerpf(40.0, 150.0, k))
	if _k_hidden() or _combat or kerner == null:
		_lamp_seen = 0.0
		return
	var lp := _lamp_light.global_position
	var fwd := -_lamp_light.global_transform.basis.z
	if fwd.y > -0.05:
		return
	var gp := lp + fwd * (lp.y / -fwd.y)
	var kp := kerner.global_position
	var ex: Array[RID] = [lamp.get_rid()]
	if Vector2(kp.x - gp.x, kp.z - gp.z).length() < 4.5 and _ray_clear(lp, kp + Vector3.UP * 0.8, ex):
		_lamp_seen += delta
		if _lamp_seen >= 0.5:
			_lamp_seen = 0.0
			_start_combat("searchlight")
	else:
		_lamp_seen = maxf(0.0, _lamp_seen - delta)

# ------------------------------------------------------------------ Gegenscharfschütze (wie overwatch.gd)

func _spawn_csniper() -> void:
	_free_csniper()
	var a := _make_actor("enemy", "marksman", CSNIPER_POS, Color.BLACK, Color.BLACK, Color.BLACK, -55.0)
	a.global_position = CSNIPER_POS + Vector3(0, 0.05, 0)
	a.set("gravity", 0.0)
	a.set("max_health", 55.0)
	a.set("tracer_speed", 800.0)
	a.set("sfx_shot", "")
	a.set("crouch", true)
	var g := MeshInstance3D.new()
	g.name = "Glint"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	g.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _glint_tex
	m.albedo_color = Color(1.0, 0.95, 0.8, 0.0)
	m.render_priority = 8
	g.material_override = m
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.visible = false
	add_child(g)
	_csniper = {"a": a, "stage": "hide", "t": 3.5, "shots": 0, "glint": g, "glow": 0.0, "down": false}
	if drone != null:
		drone.call("add_target", a, "guard", "Scharfschütze")

func _free_csniper() -> void:
	if _csniper.is_empty():
		return
	var a := _node(_csniper["a"])
	if a != null:
		if drone != null:
			drone.call("remove_target", a)
		a.queue_free()
	var g: Node = _csniper["glint"]
	if g != null and is_instance_valid(g):
		g.queue_free()
	_csniper = {}

func _make_glint_tex() -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx: float = (float(x) - 31.5) / 31.5
			var dy: float = (float(y) - 31.5) / 31.5
			var r: float = sqrt(dx * dx + dy * dy)
			var core: float = exp(-r * r * 30.0)
			var halo: float = exp(-r * r * 5.0) * 0.35
			var star: float = exp(-absf(dy) * 40.0) * exp(-absf(dx) * 2.2) + exp(-absf(dx) * 40.0) * exp(-absf(dy) * 3.5) * 0.6
			img.set_pixel(x, y, Color(1.0, 0.96, 0.85, clampf(core + halo + star, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

func _tick_csniper(delta: float) -> void:
	if _csniper.is_empty():
		return
	var s := _csniper
	var a := _node(s["a"])
	var g: MeshInstance3D = s["glint"]
	if not _alive(a):
		g.visible = false
		if not bool(s["down"]):
			s["down"] = true
			_on_csniper_down()
		return
	var active := _seg == 4 and _k_mode == "hold" and not _relocating and not (drone != null and bool(drone.get("active")))
	if not active:
		a.set("aiming", false)
		s["glow"] = 0.0
		s["stage"] = "hide"
		s["t"] = maxf(float(s["t"]), 1.5)
		return
	s["t"] = float(s["t"]) - delta
	match str(s["stage"]):
		"hide":
			a.set("crouch", false)
			a.set("aiming", false)
			s["glow"] = maxf(0.0, float(s["glow"]) - delta * 3.0)
			if float(s["t"]) <= 0.0:
				s["stage"] = "aim"
				s["t"] = 2.6
				a.set("aiming", true)
				if player != null:
					VFX.play_sfx_3d("overwatch_glint", player.global_position + Vector3(0, 1.5, -4.0), -12.0, 8.0, 40.0)
		"aim":
			a.set("aim_point", _cam_pos())
			s["glow"] = minf(1.0, float(s["glow"]) + delta * 2.5)
			if float(s["t"]) <= 0.0:
				_sniper_shot(s)
				s["stage"] = "hide"
				s["t"] = rng.randf_range(2.4, 3.2)

func _sniper_shot(s: Dictionary) -> void:
	var a := _node(s["a"])
	if a == null or player == null or not bool(player.call("is_alive")):
		return
	var from: Vector3 = a.call("scope_pos")
	var cam := _cam_pos()
	var shots: int = int(s["shots"])
	s["shots"] = shots + 1
	a.call("puppet_fire", cam, 0.0)
	var dist: float = from.distance_to(cam)
	var dir := (from - cam).normalized()
	_later(dist / 343.0, func() -> void:
		if player != null:
			VFX.play_sfx_3d("overwatch_dmr_fire", player.global_position + dir * 25.0 + Vector3.UP * 2.0, -4.0, 14.0, 80.0))
	var tof: float = dist / 800.0
	var ex: Array[RID] = [a.get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, cam, 1, ex)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if shots == 0:
		var miss := cam + Vector3(rng.randf_range(-1.2, 1.2), -0.9, 0.0) + (cam - from).normalized() * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(from, miss + (miss - from).normalized() * 6.0, 1, ex)
		var r2: Dictionary = get_world_3d().direct_space_state.intersect_ray(q2)
		_later(tof, func() -> void:
			VFX.play_whiz_along(from, cam + (cam - from).normalized() * 4.0, 4.0)
			if not r2.is_empty():
				VFX.spawn_impact(r2.position, r2.normal, "concrete"))
		_say(SD.LENA, "Er hat mich! Runter – die Brüstung deckt nur liegend.")
		return
	if hit.is_empty():
		_later(tof, func() -> void:
			if player != null and bool(player.call("is_alive")):
				player.call("take_damage", SNIPER_DMG, a if is_instance_valid(a) else null, cam, (cam - from).normalized()))
	else:
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		_later(tof, func() -> void: VFX.spawn_impact(hp, hn, "concrete"))

func _update_glints() -> void:
	if _csniper.is_empty():
		return
	var a := _node(_csniper["a"])
	var g: MeshInstance3D = _csniper["glint"]
	if g == null or not is_instance_valid(g):
		return
	if not _alive(a):
		g.visible = false
		return
	var glow: float = float(_csniper["glow"])
	g.visible = glow > 0.01
	if not g.visible:
		return
	var fov: float = 70.0
	if player != null:
		var cam: Camera3D = player.call("get_camera")
		if cam != null:
			fov = cam.fov
	var sp: Vector3 = a.call("scope_pos")
	g.global_position = sp
	var flick: float = 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 7.0)
	var gd: float = _cam_pos().distance_to(sp)
	g.scale = Vector3.ONE * (0.035 * gd * tan(deg_to_rad(fov * 0.5))) * (0.6 + 0.4 * glow)
	(g.material_override as StandardMaterial3D).albedo_color.a = glow * flick

func _on_csniper_down() -> void:
	_say(SD.LENA, "Gegenscharfschütze erledigt.")
	_later(2.4, func() -> void:
		if _seg == 4 and _k_mode == "hold" and not _lane_marked():
			_say(SD.KERNER, "Die Gasse seh ich nicht ein. Schick die Drohne, Lena."))
	if _seg == 4:
		_obj(_objective_for(4))

func _lane_marked() -> bool:
	for g: Dictionary in _guards:
		if bool(g["dead"]) or not bool(g["d"].get("lane", false)):
			continue
		var a := _node(g["a"])
		if _alive(a) and not (drone != null and bool(drone.call("is_marked", a))):
			return false
	return true

# ------------------------------------------------------------------ Drohne

func _tick_drone(pl: Player, delta: float) -> void:
	if drone == null:
		return
	var flying := bool(drone.get("active"))
	if flying:
		_drone_t += delta
		if _bot and _drone_t > 40.0:
			drone.call("stop", "bot")
		return
	if _bot:
		_bot_drone_wait -= delta
		if _seg == 4 and _k_mode == "hold" and not _csniper.is_empty() and not _alive(_node(_csniper["a"])) \
				and not _lane_marked() and _drone_cd <= 0.0 and _bot_drone_wait <= 0.0:
			if _drone_flights >= 3:
				# Testhilfe: nach drei erfolglosen Flügen direkt markieren
				for g: Dictionary in _guards:
					if bool(g["d"].get("lane", false)) and _alive(_node(g["a"])):
						drone.call("mark", g["a"])
				return
			_launch_drone(pl)
		return
	if _drone_cd <= 0.0 and not _relocating and not _ending and bool(pl.is_alive()) \
			and InputMap.has_action("drone_toggle") and Input.is_action_just_pressed("drone_toggle"):
		_launch_drone(pl)

func _launch_drone(pl: Player) -> void:
	var fwd := -pl.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var at := pl.global_position + Vector3(0.0, 1.5, 0.0) + fwd * 0.8
	if _bot:
		drone.call("set_thermal", true)
	var ok: bool = drone.call("start", at, rad_to_deg(atan2(-fwd.x, -fwd.z)))
	if not ok:
		_bot_drone_wait = 3.0
		return
	_drone_t = 0.0
	if _bot:
		drone.call("autofly", DRONE_TOUR, 1.5)

func _on_drone_launched() -> void:
	_obj("Drohne: Wachen markieren – [%s] Wärmebild, [%s] zurück" % [_key("drone_thermal"), _key("drone_toggle")])

func _on_drone_finished(_reason: String) -> void:
	_drone_cd = 0.6
	_drone_flights += 1
	_bot_drone_wait = 2.0
	_obj(_objective_for(_seg) if _k_mode == "hold" else "Decke Kerner auf seinem Weg")

func _on_target_marked(node: Node3D, _kind: String) -> void:
	for g: Dictionary in _guards:
		if g["a"] != node or not bool(g["d"].get("lane", false)):
			continue
		if str(g["d"]["key"]) == "lane":
			_say(SD.LENA, "Markiert. Einer in der Gasse – er läuft auf und ab.")
		else:
			_say(SD.LENA, "Zweiter am Rolltor. Steht still und schaut zur Straße.")
		if _lane_marked() and not _said.has("lane_both"):
			_said["lane_both"] = true
			_later(3.2, func() -> void: _say(SD.LENA, "Beide markiert, Jonas. Ich sag dir, wann sie wegsehen."))

func menu_reload_checkpoint() -> void:
	if drone != null and bool(drone.get("active")):
		drone.call("stop", "menu")
	var pl := _player()
	if pl != null:
		pl.respawn()

# ------------------------------------------------------------------ Ablauf

func _physics_process(delta: float) -> void:
	_t += delta
	var pl := _player()
	if pl == null or not _ready_done or not _ready_ok:
		return
	_ff_cool = maxf(0.0, _ff_cool - delta)
	_drone_cd = maxf(0.0, _drone_cd - delta)
	_tick_drone(pl, delta)
	_tick_lamp(delta)
	_tick_guards(delta)
	_tick_csniper(delta)
	_tick_kerner(delta)
	_update_k_hud()
	if ep_bot != null and not _relocating and not _ending and not (drone != null and bool(drone.get("active"))):
		ep_bot.call("tick", delta)

func _process(delta: float) -> void:
	super._process(delta)
	_update_glints()

func _update_k_hud() -> void:
	if _k_hud == null:
		return
	var n := int(ceil(clampf(_k_hp / K_HP, 0.0, 1.0) * 10.0))
	var bar := "■".repeat(n) + "□".repeat(10 - n)
	var st := ""
	if _fail:
		st = "AUSGEFALLEN"
	elif _combat:
		st = "KONTAKT"
	else:
		match _k_mode:
			"hold":
				st = "wartet"
			"move", "takedown":
				st = "unterwegs"
			"download":
				st = "Übertragung %d s" % maxi(0, int(ceil(DL_TIME - _dl_t))) if not _dl_done else "Übertragung fertig"
			"exit", "done":
				st = "taucht ab"
	_k_hud.text = "KERNER  %s  %s" % [bar, st]

func bot_drives_player() -> bool:
	return _bot

func sniper_wind() -> Vector3:
	return Vector3.ZERO

## Bot-Aufgabe: Ziele nach Vorrang (Angreifer, Zeugen, Neugierige, späte Streife, Gate-Ziele), Stellung mit Sicht.
func bot_task() -> Dictionary:
	var face := (kerner.global_position if kerner != null else Vector3.ZERO) + Vector3.UP
	var spots: Array[Vector3] = SPOTS_B if _perch == 1 else SPOTS_A
	if _bt_target != null and is_instance_valid(_bt_target) and bool(_bt_target.call("is_alive")) and _t < _bt_until:
		return {"kind": "snipe", "pos": _push(_bt_spot), "targets": [_bt_target], "face": face, "aim_h": _bt_aim_h}
	_bt_target = null
	for entry: Array in _bot_targets():
		var t: Node3D = entry[0]
		var ah: float = entry[1]
		var si := _spot_for(t, ah, spots)
		if si < 0:
			continue
		_bt_target = t
		_bt_spot = spots[si]
		_bt_aim_h = ah
		_bt_until = _t + rng.randf_range(0.5, 1.5)
		return {"kind": "snipe", "pos": _push(_bt_spot), "targets": [t], "face": face, "aim_h": ah}
	var home := _bt_spot if spots.has(_bt_spot) else spots[0]
	var hide := not _csniper.is_empty() and _alive(_node(_csniper["a"])) and str(_csniper["stage"]) == "aim"
	return {"kind": "snipe", "pos": _push(home), "targets": [], "face": face, "hide": hide}

func _push(spot: Vector3) -> Vector3:
	var c: Vector3 = ROOF_C[_perch]
	var d := Vector3(spot.x - c.x, 0.0, spot.z - c.z)
	return spot + d.normalized() * 0.6 if d.length() > 0.1 else spot

func _bot_targets() -> Array:
	var out: Array = []
	for st: String in ["hostile", "door", "witness", "curious", "late"]:
		for g: Dictionary in _guards:
			if not bool(g["dead"]) and str(g["state"]) == st and _alive(_node(g["a"])):
				out.append([g["a"], -1.0])
	if _k_mode == "hold" or _k_mode == "download":
		for g: Dictionary in _guards:
			var d: Dictionary = g["d"]
			if bool(g["dead"]) or int(d["gate"]) != _seg or not bool(d.get("block", false)) or not _alive(_node(g["a"])):
				continue
			if bool(d.get("lane", false)):
				continue   # Gasse: Drohne markiert, Kerner erledigt das
			out.append([g["a"], -1.0])
		if _seg == 3 and _perch == 1 and _alive(_lamp_proxy):
			out.append([_lamp_proxy, 1.3])
		if _seg == 4 and not _csniper.is_empty() and _alive(_node(_csniper["a"])):
			out.append([_csniper["a"], -1.0])
	return out

## Erste Stellung mit freier Sicht (Ray Layer 1, Treffer innerhalb 1 m am Ziel zählt als frei), 1 s gecacht.
func _spot_for(t: Node3D, aim_h: float, spots: Array[Vector3]) -> int:
	var key := t.get_instance_id()
	var c: Variant = _los_cache.get(key)
	if c is Array and _t < float((c as Array)[1]):
		return int((c as Array)[0])
	var tp := t.global_position + Vector3.UP * (aim_h if aim_h > 0.0 else 1.2)
	var order: Array[int] = []
	var cur := spots.find(_bt_spot)
	if cur >= 0:
		order.append(cur)
	for i in spots.size():
		if i != cur:
			order.append(i)
	var res := -1
	var ex: Array[RID] = []
	if player != null:
		ex.append((player as CollisionObject3D).get_rid())
	for i in order:
		var from := spots[i] + Vector3.UP * 1.6
		var q := PhysicsRayQueryParameters3D.create(from, tp, 1, ex)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(tp) < 1.0:
			res = i
			break
	_los_cache[key] = [res, _t + 1.0]
	return res

# ------------------------------------------------------------------ Rückmeldungen der Puppen

func on_friendly_hit(who: Node) -> void:
	if who != kerner or _ff_cool > 0.0 or _fail:
		return
	_ff_cool = 1.5
	_k_damage(35.0)
	if not _fail:
		_say(SD.KERNER, "Lena! Das war ich! Ich bin getroffen!")

func on_friendly_died(_who: Node) -> void:
	pass

## Angeschossene Wache in Kerners Nähe: Feuergefecht.
func on_enemy_wounded(who: Node) -> void:
	if kerner == null or not (who is Node3D):
		return
	if (who as Node3D).global_position.distance_to(kerner.global_position) < 30.0 and not _k_hidden():
		_start_combat("shot")

# ------------------------------------------------------------------ Helfer

func _alive(n: Variant) -> bool:
	return n != null and is_instance_valid(n) and n is Node and (n as Node).is_inside_tree() and bool((n as Node).call("is_alive"))

func _node(v: Variant) -> Node3D:
	if v == null or not is_instance_valid(v) or not (v is Node3D):
		return null
	return v as Node3D

func _ray_clear(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _cam_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var cam: Camera3D = player.call("get_camera")
	return cam.global_position if cam != null else player.global_position + Vector3.UP * 1.6

func _aim_view(pl: Node3D, at: Vector3) -> void:
	var cam: Camera3D = pl.call("get_camera")
	var from := cam.global_position if cam != null else pl.global_position + Vector3.UP * 1.6
	var dv := at - from
	pl.call("set_view", rad_to_deg(atan2(-dv.x, -dv.z)), rad_to_deg(atan2(dv.y, Vector2(dv.x, dv.z).length())))

func _key(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			return OS.get_keycode_string(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return "?"
