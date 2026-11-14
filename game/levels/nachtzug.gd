extends "res://game/levels/level.gd"
## Teil 3, Mission 11 "Nachtzug": Nachtzug Innsbruck–Wien der Alpen-Donau-Bahn, 16. Juni 2030, 22:40.
## Kerner und Lena kaempfen sich Waggon fuer Waggon nach vorn zu Weber (Schlafwagen, Abteil neun).
## Falks Garde-Jaeger (graue Maentel) sind an Bord, dazwischen Reisende (Gruppe no_shoot:
## 1. Treffer Warnung, 2. Treffer Abbruch). Der Zug steht im Ursprung, die Landschaft scrollt (nachtzug_world).
##
## Phasen:
##   1  Abteilwagen W1: Garde im Gang
##   2  Speisewagen W2 (Durchsage Falk, Reisende an den Tischen)
##   3  Gepaeckwagen W3 (Schwerer)
##   4  Garde-Hubschrauber: MG an der Ladetuer (rail_ride, fest, ohne Fahrt)
##   5  Dach W4/W5: zwei Wellen, zwei Tunnel (ducken/hinlegen, sonst Tod), Oberleitung
##   6  Schlafwagen W6: Garde zwischen Reisenden in den Betten
##   7  Finale: Weber koppelt die vorderen Wagen ab, Hinweis Traunsee
## Debug: --phase=N (Einstieg), --autopilot (eigener Bot: nachtzug_bot).

const SD := preload("res://game/story/story_data.gd")
const VF := preload("res://game/vehicles/vehicle_fx.gd")
const World := preload("res://game/levels/nachtzug_world.gd")
const Actor := preload("res://game/levels/hafen_actor.gd")
const RailRide := preload("res://game/systems/rail_ride.gd")
const Bot := preload("res://game/levels/nachtzug_bot.gd")
const Civ := preload("res://game/levels/nachtzug_civilian.gd")
const ShotsScript := preload("res://game/levels/nachtzug_shots.gd")
const Pickup := preload("res://game/pickups/pickup.gd")
const SquadOrders := preload("res://game/squad/squad_orders.gd")
const Companion := preload("res://game/squad/companion.gd")
const HELI_SCENE := "res://game/vehicles/helicopter.tscn"
## Schwierigkeit (Nutzer 13.11.2026: "viel zu einfach"): Garde-Gegner halten mehr aus und treffen besser.
const GARDE_HP: float = 1.7
const GARDE_ACC: float = 1.35
## Hubschrauber P4: Teiler fuer Tuer-MG-Schaden (vorher Heli-Default 15) und Schwachstellen-Faktor.
const HELI_MG_TOUGHNESS: float = 5.0
const HELI_WEAK_MULT: float = 3.0
## Feinschliff 14.11.2026: Phase dauerte ~90 s (78 s Dauerfeuer auf 3200 HP) und war zaeh. Jetzt 2000 HP,
## Funkhinweis auf die Schwachstellen, Ausweichanflug bei jeder Schadensstufe (dreht ab, schweigt kurz,
## kommt im Angriffsanflug tief zurueck) und eine Nachlauf-Leiste fuer sichtbare Trefferwirkung.
const HELI_HP: float = 2000.0
const HELI_HINT_T: float = 6.0       ## s nach Erscheinen: Lena weist auf Kanzel/Rotorkopf hin
const HELI_EVADE_T: float = 3.4      ## s Abdrehen nach einer neuen Schadensstufe (keine Salven)
## Zielpunkt fuer den Autopilot-Schuetzen nach dem Funkhinweis (lokal, Nase -z): vordere Kanzelkante,
## Streuung verteilt die Treffer auf Kanzel und Rumpfnase - wie ein Spieler, der dem Hinweis folgt.
const HELI_AIM_LOCAL := Vector3(0.0, 0.55, -2.9)

const C_GARDE := [Color(0.42, 0.43, 0.44), Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13)]
const C_LENA := [Color(0.16, 0.18, 0.2), Color(0.25, 0.24, 0.22), Color(0.45, 0.7, 0.95)]
const C_WEBER := [Color(0.1, 0.1, 0.12), Color(0.18, 0.17, 0.16), Color(0.1, 0.1, 0.12)]

const Y := 1.2               ## Wagenboden
const YR := 4.1              ## Dach
const ROOF_Z_MIN := -135.0   ## vorderstes Dach mit Gelaender (W5, Quergelaender bei -135.9)
const P6_Z_MIN := -162.6     ## Schlafwagen W6: nicht in die Stirnwand (-163.45) spawnen
const FALL_Y := -3.0         ## darunter gilt ein Gegner als durch die Welt gefallen
const ENTRY_Z := {2: -28.5, 3: -56.0, 6: -140.5}
const ROOF_ENTRY_Z := -81.3
const ROOF_SPOT := Vector3(0, 4.15, -85.0)
const HATCH_Z := -133.0
const HATCH_SPOT := Vector3(0.85, 1.25, -139.5)
const DEBUG_SPOT := {2: Vector3(0.6, 1.25, -24.0), 3: Vector3(0.3, 1.25, -52.5), 4: Vector3(0.1, 1.25, -66.0),
	5: Vector3(0.1, 1.25, -70.0), 6: Vector3(0.85, 1.25, -139.5), 7: Vector3(0.45, 1.25, -159.0)}
## P3: Wiedereinstieg nach Welle 1 (links hinter der hohen Kiste bei z -63, ~18 m vor der Stirntuer),
## Vorwarnzeit und Abstand zwischen den Verstaerkungen, die durch die Stirntuer kommen.
const P3_MID_SPOT := Vector3(-1.1, 1.25, -61.7)
## Abteilwagen W1: Tuermitten der 8 Abteile (nachtzug_world._furnish_abteil: zr - 2 - 2.75 k - 1.375)
const P1_DOORS_Z: Array[float] = [-3.375, -6.125, -8.875, -11.625, -14.375, -17.125, -19.875, -22.625]
## Bot-Deckung im Gepaeckwagen: direkt hinter den hohen Kisten (z -63 links, -71.5 links, -74 rechts)
const P3_COVER: Array[Vector3] = [Vector3(-1.1, 1.2, -61.7), Vector3(-1.1, 1.2, -70.1), Vector3(1.1, 1.2, -72.6)]
const P3_W2_WARN := 2.5
const P3_W2_STAGGER := 0.7
const RIDE_PATH: Array[Vector3] = [Vector3(1.3, 1.2, -68.0), Vector3(3.3, 1.2, -68.0)]

var phase: int = 0
var train: Node3D = null
var env_ref: Environment = null
var moon_ref: DirectionalLight3D = null
var sky_ref: ProceduralSkyMaterial = null

var _time: float = 0.0
var _phase_t: float = 0.0
var _failed: String = ""
var _radio_end: float = 0.0
var _fail_count: int = 0
var _done: bool = false
var _knapp_said: bool = false
var _p3_w1_done: bool = false      ## Gepaeckwagen: Welle 1 erledigt (Zwischen-Checkpoint cp_w3b)
var _heli_hp_keep: float = -1.0    ## Heli-HP beim letzten Fehlschlag in P4 (Schaden bleibt nach Neustart)
var _phase_nodes: Array[Node] = []
var _bot: RefCounted = null
var _bot_on: bool = false
var _ready_ok: bool = false
var _fade_rect: ColorRect = null

var lena: Node3D = null
var weber: Node3D = null
var ride: Node3D = null
var _foot: Node3D = null
var _foot_layer: int = 2
var _heli: Node3D = null
var _heli_t: float = 0.0
var _heli_ui: CanvasLayer = null    ## Bossleiste Hubschrauber (P4)
var _heli_bar: ProgressBar = null
var _heli_hint: Label = null
var _heli_log_t: float = 0.0
var _heli_t0: float = 0.0
var _heli_ghost: ProgressBar = null  ## Nachlauf-Leiste (helles Stueck = gerade verursachter Schaden)
var _heli_hinted: bool = false
var _heli_ghost_hold: float = 0.0
var _heli_frac_last: float = 1.0
var _heli_stage_seen: int = 0
var _heli_evade: float = 0.0
var _heli_evades: int = 0
var civs: Array[Node3D] = []
var _civ_hits: int = 0
var _civ_cd: float = 0.0
var _lena_hits: int = 0
var _lena_cd: float = 0.0
var _weber_hits: int = 0
var _crumbs: Array[Vector3] = []
var _lena_fire_cd: float = 2.0
var _lena_tp_cd: float = 0.0
var _roof_stage: int = 0          ## 0 innen, 1 Welle 1, 2 Welle 2, 3 Luke frei
var _roof_enemies: Array = []
var _tunnel_ui: Label = null
var _tunnel_layer: CanvasLayer = null
var _hatch_open: bool = false
var _weber_hits_total: int = 0
var _squad: Node = null            ## Squad-Befehle light (game/squad/)
var _lena_c: RefCounted = null     ## Lenas Befehls-Zustand (companion.gd); ohne Befehl folgt sie wie bisher

func _init() -> void:
	level_name = "nachtzug"
	spawn_player = true
	spawn_enemies = false
	default_faction = "reich"
	ambient_artillery = false
	end_z = -170.0
	fog_density = 0.003
	build_seed = 1606
	_wave_count = 7

func get_level_info() -> Dictionary:
	return {"name": level_name, "title": "Nachtzug", "waves": 7, "end_position": [0.4, 1.2, -162.0], "waypoints": []}

func is_level_ready() -> bool:
	return _ready_done

# ================================================================== Aufbau

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.004, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.008, 0.012, 0.03)
	sm.sky_horizon_color = Color(0.06, 0.07, 0.1)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.05, 0.055, 0.07)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.27, 0.38)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.2
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.065, 0.09)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.7
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.82, 0.83, 0.86)
	env.volumetric_fog_emission = Color(0.004, 0.004, 0.007)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 90.0
	env.volumetric_fog_gi_inject = 0.3
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	# Glow-Werte werden von PostFx ueberschrieben -> endgueltig unten nach PostFx.apply
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.9
	env.glow_bloom = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.9
	env.adjustment_contrast = 1.1
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.58, 0.66, 1.0)
	moon.light_energy = 0.2
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.4
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	var dir := Vector3(0.45, -0.55, -0.6).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	env_ref = env
	moon_ref = moon
	sky_ref = sm
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")
	# nach dem Profil (das Glow 0.8 / Schwelle 1.0 setzt): Deckenlampen im Waggon nicht ueberstrahlen
	env.glow_hdr_threshold = 1.5
	env.glow_intensity = 0.5
	env.glow_bloom = 0.0

func _build_ground() -> void:
	train = World.new()
	add_child(train)
	train.set("env", env_ref)
	train.set("moon", moon_ref)
	train.set("sky_mat", sky_ref)
	train.call("build", self, world, build_seed)

func _build_street() -> void:
	pass

func _build_props() -> void:
	# Reisende (vor dem Navmesh-Bake, damit die Agenten um sie herum planen)
	var list := [
		["seat", Vector3(-1.2, Y, -5.25), 0.0], ["seat", Vector3(-0.6, Y, -15.3), 180.0],
		["seat", Vector3(1.25, Y, -29.2), 0.0], ["seat", Vector3(-1.25, Y, -40.2), 180.0],
		# Kauernder an der Abteiltuer (Tuer z -144,65..-145,35), Gesicht zum Gang; kriecht bei Kampfbeginn ins Abteil
		["cower", Vector3(0.3, Y, -145.0), 90.0],
		["lie", Vector3(-0.92, Y, -144.35), 0.0], ["lie", Vector3(-0.92, Y, -150.95), 0.0],
		# Speisewagen W2: weitere Gaeste an den hinteren Tischen (Fensterplaetze x = +-1,45, Gang frei).
		# Nur hinter dem Einstieg-Bereich (z > -34): weiter vorn blockieren sie die Schusslinien des Bots
		# (Abstand 0,75 m) im Gefecht. Tische bei z = -30,1 - 2,3 k, Baenke bei +-0,9 (Blick -z = 0 Grad).
		["seat", Vector3(-1.45, Y, -29.2), 0.0], ["seat", Vector3(-1.45, Y, -31.0), 180.0],
		["seat", Vector3(1.45, Y, -31.0), 180.0], ["seat", Vector3(-1.45, Y, -31.5), 0.0],
		["seat", Vector3(1.45, Y, -33.3), 180.0],
	]
	var r := RandomNumberGenerator.new()
	r.seed = build_seed
	var coats := [Color(0.3, 0.22, 0.16), Color(0.2, 0.25, 0.32), Color(0.45, 0.42, 0.36), Color(0.35, 0.12, 0.12), Color(0.18, 0.28, 0.2)]
	var hairs := [Color(0.15, 0.1, 0.07), Color(0.55, 0.45, 0.3), Color(0.6, 0.6, 0.6), Color(0.08, 0.07, 0.06)]
	# MakeHuman-Zivilfiguren (assets/characters/civilian), Reihenfolge wie list
	var variants := ["mantel", "frau", "jacke", "frau2", "alt", "frau", "mantel",
		"frau2", "alt", "frau", "jacke", "frau2"]
	# Gehautete Nachtzug-Figuren (tools/civilian/build_civ_nz.py) mit Idle-Schleife je Pose; fehlt eine
	# Datei, greift die alte statische Figur oben.
	var nz := [["tweed", "seat_cross"], ["dame", "seat"], ["pulli", "seat_table"], ["blazer", "seat_table"],
		["hemd", "cower"], ["schlaf_m", ""], ["schlaf_f", ""], ["alt", "seat_lean"], ["bluse", "seat_table"],
		["jacke", "seat_cross"], ["anzug", "seat_table"], ["kostuem", "seat"]]
	for i in list.size():
		var d: Array = list[i]
		var c: StaticBody3D = Civ.new()
		c.set("pose", d[0])
		c.set("variant", variants[i])
		if ResourceLoader.exists("res://assets/characters/civilian/civ_nz_%s.glb" % nz[i][0]):
			c.set("variant", "nz_" + str(nz[i][0]))
			c.set("anim", nz[i][1])
		if d[0] == "cower":
			c.set("cover_to", Vector3(-0.95, Y, -145.55))
		c.set("coat", coats[r.randi() % coats.size()])
		c.set("hair", hairs[r.randi() % hairs.size()])
		c.set("skin", Color(0.68, 0.52, 0.42).lerp(Color(0.45, 0.32, 0.24), r.randf() * 0.6))
		c.set("level", self)
		c.name = "Reisender_%d" % (i + 1)
		world.add_child(c)
		c.position = d[1]
		c.rotation.y = deg_to_rad(float(d[2]))
		civs.append(c)
	# Aufhellung fuer den Kauernden im Schlafwagengang (sonst nur Silhouette gegen das Fenster)
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.84, 0.66)
	fill.light_energy = 0.45
	fill.omni_range = 2.4
	fill.position = Vector3(0.6, Y + 1.5, -144.6)
	world.add_child(fill)
	Pickup.place_ammo_crate(world, Vector3(-1.2, Y, -69.4), 90.0)
	Pickup.place_ammo_crate(world, Vector3(1.4, Y, -138.3), 0.0)

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0.85, 1.25, -3.0), "player_spawn")
	ps.name = "PlayerSpawn"

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	pass

func _bake_nav() -> void:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 45.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.geometry_collision_mask = 1 | 16
	nm.filter_baking_aabb = AABB(Vector3(-2.2, 0.9, -170.0), Vector3(4.4, 5.0, 172.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)

func _ready() -> void:
	await super._ready()
	if not is_inside_tree():
		return
	_foot = player
	if player != null:
		_foot_layer = (player as CollisionObject3D).collision_layer
		if player.has_method("set_view"):
			player.call("set_view", 0.0, -4.0)
	Events.player_respawned.connect(_on_player_respawned)
	Events.player_died.connect(_on_player_died)
	_bot_on = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	if _bot_on and player != null:
		_bot = Bot.new()
		_bot.call("setup", self, player)
	_make_tunnel_ui()
	_squad = SquadOrders.new()
	add_child(_squad)
	_ready_ok = true
	var shots := str(Game.arg("shots", ""))
	if shots != "" and shots != "true":
		var sv: SubViewport = ShotsScript.new()
		sv.set("out_dir", ProjectSettings.globalize_path("res://captures").path_join(shots))
		sv.set("every", float(Game.arg("shot-every", 2.5)))
		sv.set("level", self)
		add_child(sv)
	_run()

# ================================================================== Ablauf-Helfer

func _say(speaker: String, text: String, dur: float = 0.0, opts: Dictionary = {}) -> void:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if opts.is_empty() or ui == null or not ui.has_method("say"):
		Events.story_radio.emit(speaker, text, dur)
	else:
		ui.call("say", speaker, text, dur, opts)
	var d := dur if dur > 0.0 else clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)
	_radio_end = maxf(_radio_end, _time) + d + 0.65

## Restzeit der Funk-Warteschlange (echte Audiolaengen aus StoryUI, sonst Schaetzung).
func _radio_busy() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return maxf(0.0, _radio_end - _time)

func _radio_wait(max_wait: float = 12.0) -> bool:
	return await _until(func() -> bool: return _radio_busy() <= 0.05, max_wait)

func _obj(text: String) -> void:
	Events.story_objective.emit(text)

func _sleep(t: float) -> bool:
	var end := _time + t
	while _time < end:
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
	return true

func _until(cond: Callable, timeout: float = -1.0) -> bool:
	var end := _time + timeout
	while not bool(cond.call()):
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
		if timeout > 0.0 and _time >= end:
			return true
	return true

func _fail(reason: String) -> void:
	if _failed == "" and phase >= 1 and phase <= 6 and not _done:
		_failed = reason

func _alive(n: Variant) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if (n as Object).has_method("is_alive"):
		return bool((n as Object).call("is_alive"))
	return not bool((n as Object).get("dead"))

func _all_dead(nodes: Array) -> bool:
	for n in nodes:
		if _alive(n):
			return false
	return true

func _kill(nv: Variant) -> void:
	if not _alive(nv):
		return
	var n := nv as Node
	var n3 := n as Node3D
	var src: Node = player if player != null and is_instance_valid(player) else self
	if n.has_method("destroy"):
		n.call("destroy")
	elif n.has_method("take_damage"):
		var prev := bool(Combat.get("explosion_active"))
		Combat.set("explosion_active", true)
		n.call("take_damage", 99999.0, src, n3.global_position + Vector3.UP, Vector3.UP)
		Combat.set("explosion_active", prev)

func _clear_phase_nodes() -> void:
	for n in _phase_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_phase_nodes.clear()
	_roof_enemies.clear()
	_heli = null

## Wartet, bis alle Pflichtziele tot sind. Nach timeout raeumt Lena die Reste ab (kein Haenger).
func _clear(req: Array, timeout: float = 80.0) -> bool:
	var ok: bool = await _until(func() -> bool: return _all_dead(req), timeout)
	if not ok:
		return false
	if not _all_dead(req):
		var names: Array[String] = []
		for n in req:
			if _alive(n):
				names.append("%s@%s" % [str((n as Node).name), str((n as Node3D).global_position.snapped(Vector3.ONE * 0.1))])
		print("[nachtzug] Phase %d: Zeitlimit, Lena hilft (%s)" % [phase, ", ".join(names) + " Spieler@" + str(_ppos().snapped(Vector3.ONE * 0.1))])
		_say(SD.LENA, "Ich hab sie im Visier. Bleib unten!")
		await _sleep(2.0)
		if _failed != "":
			return false
		for n in req:
			if _alive(n):
				if lena != null and is_instance_valid(lena):
					lena.call("puppet_fire", (n as Node3D).global_position + Vector3.UP * 1.2, 0.1)
				_kill(n)
	return true

func _enemy(etype: String, pos: Vector3, acc: float = 0.4, yaw: float = 0.0) -> Node3D:
	var path := ENEMY_PATH % etype
	if not ResourceLoader.exists(path):
		path = ENEMY_PATH % "rifleman"
	var e := (load(path) as PackedScene).instantiate() as Node3D
	e.set_meta("faction", "garde")
	e.set("color_primary", C_GARDE[0])
	e.set("color_secondary", C_GARDE[1])
	e.set("color_armband", C_GARDE[2])
	e.name = "Garde_%s_%d" % [etype, get_child_count()]
	e.set("max_health", float(e.get("max_health")) * GARDE_HP)   # vor add_child: _ready skaliert weiter
	add_child(e)
	e.global_position = pos + Vector3(0, 0.05, 0)
	e.set_meta("spawn_pos", e.global_position)
	e.rotation.y = deg_to_rad(yaw)
	e.set("accuracy_scale", acc * GARDE_ACC)
	e.set("sight_range", 40.0)
	_phase_nodes.append(e)
	return e

## Spawnpunkt mindestens min_d vor dem Spieler (Fahrtrichtung -Z), nicht weiter vorn als z_min.
func _ahead(pos: Vector3, min_d: float, z_min: float) -> Vector3:
	var p := pos
	p.z = maxf(minf(p.z, _ppos().z - min_d), z_min)
	return p

## Dach-Spawn wie _ahead, aber nur auf dem begehbaren Dach W4/W5 (Gelaender bis z -135.9). Was
## darueber hinaus laege (frueher bis -160 = Dach W6 ohne Gelaender -> Absturz ins Leere), wird in
## einen 3-m-Streifen vor dem Quergelaender gestaffelt, damit niemand am selben Punkt steht.
func _roof_ahead(pos: Vector3, min_d: float) -> Vector3:
	var p := pos
	p.z = minf(p.z, _ppos().z - min_d)
	if p.z < ROOF_Z_MIN:
		p.z = ROOF_Z_MIN + fposmod(ROOF_Z_MIN - p.z, 3.0)
	return p

## Wie _ahead; wird z_min erreicht, staffeln (nach der Soll-Position) statt alle auf einen Punkt.
func _ahead_spread(pos: Vector3, min_d: float, z_min: float, band: float) -> Vector3:
	var p := pos
	p.z = minf(p.z, _ppos().z - min_d)
	if p.z < z_min:
		p.z = z_min + fposmod(z_min - pos.z, band)
	return p

## Sicherheitsnetz: Phasen-Gegner, die unter den Zug fallen (unter dem Zug gibt es keinen Boden),
## an ihren Spawnpunkt zuruecksetzen statt endlos zu fallen.
func _tick_fallen() -> void:
	for n in _phase_nodes:
		if not _alive(n) or not (n is CharacterBody3D):
			continue
		var e := n as CharacterBody3D
		if e.global_position.y > FALL_Y:
			continue
		var home: Vector3 = e.get_meta("spawn_pos", Vector3(0.0, Y, -20.0))
		print("[nachtzug] WARNUNG: %s gefallen bei %s -> zurueck nach %s" % [e.name, e.global_position.snapped(Vector3.ONE * 0.1), home])
		e.global_position = home + Vector3.UP * 0.1
		e.velocity = Vector3.ZERO

func _alert_all(nodes: Array) -> void:
	var at := _ppos()
	for n in nodes:
		if _alive(n) and (n as Object).has_method("alert"):
			n.call("alert", at, false)

func _make_actor(role: String, etype: String, pos: Vector3, cols: Array, yaw: float, props: Dictionary = {}, parent: Node = null) -> Node3D:
	var a: CharacterBody3D = Actor.new()
	a.set("role", role)
	a.set("enemy_type", etype)
	a.set("level_ref", self)
	a.set_meta("faction", "resistance")
	a.set("color_primary", cols[0])
	a.set("color_secondary", cols[1])
	a.set("color_armband", cols[2])
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	for k: String in props:
		a.set(k, props[k])
	a.name = "%s_%s_%d" % [role, etype, get_child_count()]
	(parent if parent != null else self).add_child(a)
	a.global_position = pos + Vector3(0, 0.05, 0)
	a.rotation.y = deg_to_rad(yaw)
	return a

func _fade(to: float, t: float) -> void:
	if _fade_rect == null:
		var cl := CanvasLayer.new()
		cl.layer = 40
		add_child(cl)
		_fade_rect = ColorRect.new()
		_fade_rect.color = Color(0, 0, 0, 0)
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		cl.add_child(_fade_rect)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", to, t)

func _ppos() -> Vector3:
	var p := _foot if _foot != null and is_instance_valid(_foot) else player
	return (p as Node3D).global_position if p != null and is_instance_valid(p) else Vector3(0, Y, 0)

func _foot_ok() -> bool:
	return _foot != null and is_instance_valid(_foot) and bool(_foot.call("is_alive"))

func _teleport(p: Vector3, yaw: float = 0.0) -> void:
	if _foot == null or not is_instance_valid(_foot):
		return
	_foot.global_position = p
	if _foot is CharacterBody3D:
		(_foot as CharacterBody3D).velocity = Vector3.ZERO
	_foot.call("set_view", yaw, -4.0)
	_crumbs.clear()
	_lena_to_player()

func _top_up_ammo() -> void:
	if not _foot_ok():
		return
	var ws: Variant = _foot.get("weapons")
	if ws is Array:
		for w in ws:
			if w != null and is_instance_valid(w) and int(w.get("slot")) == 0:
				w.call("add_reserve", 90)

# ================================================================== Lena

func _spawn_lena(pos: Vector3) -> void:
	lena = _make_actor("friendly", "rifleman", pos, C_LENA, 0.0, {"invulnerable": true})
	lena.name = "Lena"
	_lena_c = Companion.new()
	_lena_c.set("actor", lena)
	_lena_c.set("move_speed", 2.8)
	_lena_c.set("move_timeout", 8.0)
	_lena_c.set("fire_range", 30.0)
	_lena_c.set("fire_interval", Vector2(0.7, 1.2))
	_lena_c.set("hit_chance", 0.45)
	_lena_c.set("damage", 8.0)
	_lena_c.set("move_filter", _sq_move_filter)
	_lena_c.set("available_cb", func() -> bool: return ride == null and not _done and phase >= 1 and phase <= 6 and _foot_ok())
	if _squad != null:
		_squad.set("companion", _lena_c)

## Squad-Befehl "Dort hin": im Wagen auf den Gang, auf dem Dach mittig, gleiche Ebene wie Kerner,
## hoechstens 12 m vor/hinter ihm und mit freiem Weg (geschlossene Tueren, Waende).
func _sq_move_filter(pos: Vector3) -> Variant:
	if lena == null or not is_instance_valid(lena):
		return null
	var p := _ppos()
	var inside := p.y < 3.0
	if inside != (pos.y < 3.0) or absf(pos.z - p.z) > 12.0:
		return null
	pos.x = clampf(pos.x, -0.2, 1.3) if inside else clampf(pos.x, -0.8, 0.8)
	var from := lena.global_position + Vector3.UP * 1.0
	if not VF.ray(self, from, Vector3(pos.x, from.y, pos.z), 1, [lena.get_rid()]).is_empty():
		return null
	return pos

func _lena_to_player() -> void:
	if lena == null or not is_instance_valid(lena):
		return
	if _lena_c != null:
		_lena_c.call("reset")
	var p := _ppos()
	var back := Vector3(0, 0, 2.2)
	var spot := p + back
	# im Wagen am Gang bleiben, auf dem Dach mittig
	if p.y < 3.0:
		spot.x = clampf(spot.x, -0.2, 1.3)
	lena.global_position = spot + Vector3(0, 0.05, 0)
	lena.call("walk_to", spot, 1.0, false)

func _tick_lena(delta: float) -> void:
	if lena == null or not is_instance_valid(lena) or ride != null:
		return
	var p := _ppos()
	if _crumbs.is_empty() or _crumbs[-1].distance_to(p) > 0.5:
		_crumbs.append(p)
		if _crumbs.size() > 40:
			_crumbs.pop_front()
	var lp := lena.global_position
	var dist := lp.distance_to(p)
	_lena_tp_cd = maxf(0.0, _lena_tp_cd - delta)
	# Squad-Befehle: Halten/Dort hin ersetzt das Folgen; zu weit weg oder andere Ebene -> sie schliesst wieder auf
	if _lena_c != null:
		_lena_c.call("tick", delta)
		if not bool(_lena_c.call("is_following")) and (dist > 24.0 or absf(lp.y - p.y) > 2.0):
			_lena_c.call("order_follow")
			if _squad != null:
				_squad.call("say", "auto_follow")
	var following: bool = _lena_c == null or bool(_lena_c.call("is_following"))
	if following and (dist > 10.0 or absf(lp.y - p.y) > 2.0) and _lena_tp_cd <= 0.0:
		_lena_tp_cd = 1.5
		_lena_to_player()
		return
	# Brotkrumen: Punkt ca. 3 m hinter dem Spieler
	if following and dist > 3.2:
		var tgt := _crumbs[0]
		for c in _crumbs:
			if c.distance_to(p) > 3.0:
				tgt = c
		lena.call("walk_to", tgt, 3.4 if dist > 5.0 else 2.4, false)
	# Tunnel: Lena geht in die Hocke
	var danger := false
	if train != null and lp.y > 3.0:
		danger = float(train.call("tunnel_eta", lp.z)) < 6.0 or not (train.call("tunnel_at", lp.z) as Dictionary).is_empty()
	lena.set("crouch", danger)
	_tick_lena_fire(delta)

func _tick_lena_fire(delta: float) -> void:
	if _lena_c != null and bool(_lena_c.call("has_target")):
		return   # Squad-Befehl "Feuer auf Ziel": companion.gd schiesst
	_lena_fire_cd -= delta
	if _lena_fire_cd > 0.0:
		return
	_lena_fire_cd = randf_range(1.1, 2.0)
	var from: Vector3 = lena.call("muzzle_pos")
	var best: Node3D = null
	var bd := 26.0
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node3D) or (n as Node).is_in_group("vehicle") or not _alive(n):
			continue
		var tp := (n as Node3D).global_position + Vector3.UP * 1.2
		var d := from.distance_to(tp)
		if d >= bd:
			continue
		var hit := VF.ray(self, from, tp, 1 | 4, [lena.get_rid()])
		if not hit.is_empty() and hit.get("collider") != n:
			continue
		bd = d
		best = n
	if best == null:
		return
	var aim := best.global_position + Vector3.UP * 1.2
	lena.call("puppet_fire", aim, 0.35)
	if randf() < 0.3:
		best.call("take_damage", 6.0, lena, aim, (from - aim).normalized())

# ================================================================== Hauptablauf

func _run() -> void:
	await get_tree().process_frame
	var start := clampi(int(Game.arg("phase", 1)), 1, 7)
	if start > 1:
		for i in range(0, mini(start - 2, 3)):
			train.call("open_door", i, false)
		_teleport(DEBUG_SPOT[start])
		_checkpoint("cp_start")
	_spawn_lena(_ppos() + Vector3(0, 0, 2.2))
	if start == 1:
		_checkpoint("cp_start")
		await _intro()
	phase = start
	while phase <= 6 and is_inside_tree():
		_failed = ""
		_phase_t = 0.0
		await _radio_wait(8.0)
		var ok: bool = await _phase(phase)
		if not is_inside_tree():
			return
		print("[nachtzug] Phase %d %s nach %.1f s (gesamt %.1f s)" % [phase, "geschafft" if ok and _failed == "" else "FEHLER " + _failed, _phase_t, _time])
		if ok and _failed == "":
			phase += 1
		else:
			await _retry()
	if is_inside_tree():
		phase = 7
		await _finale()

func _phase(p: int) -> bool:
	match p:
		1: return await _p1()
		2: return await _p2()
		3: return await _p3()
		4: return await _p4()
		5: return await _p5()
		6: return await _p6()
	return true

func _intro() -> void:
	_say(SD.LENA, "Wir sind drin. Weber reist als ‚Herr Brenner‘, Schlafwagen, Abteil neun. Sieben Wagen bis vorn.")
	_say(SD.KERNER, "Und Falks Leute?")
	_say(SD.LENA, "Graue Mäntel, mindestens zwei pro Wagen. Und überall Reisende. Pass auf, wohin du schießt.")
	_obj("Zum Schlafwagen vorarbeiten – keine Reisenden treffen")
	await _radio_wait(14.0)

func _retry() -> void:
	_fail_count += 1
	var reason := _failed
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	if ride != null and is_instance_valid(ride):
		# Fairness: der Heli startet nach dem Neustart nicht wieder mit vollen HELI_HP (Schaden bleibt)
		if _alive(_heli):
			_heli_hp_keep = float(_heli.get("health"))
			print("[nachtzug] P4 Neustart: Heli behaelt %.0f HP" % _heli_hp_keep)
		_say(SD.LENA, "Die Tür ist zerschossen, weg da!" if reason != "menu" else "Zurück. Wir versuchen es noch mal, sauber diesmal.")
		Events.player_died.emit()
		ride.set("input_enabled", false)
		ride.set("fire_held", false)
		await get_tree().create_timer(2.5 if reason != "menu" else 0.6, false).timeout
		_clear_phase_nodes()
		ride.call("clear_events")
		ride.call("refit")
		ride.call("reset_to", 0.0)
		ride.set("invulnerable", _fail_count >= 2)
		ride.set("input_enabled", true)
		await get_tree().create_timer(0.8, false).timeout
		return
	if reason != "zivil":
		_say(SD.LENA, "Zurück. Wir versuchen es noch mal, sauber diesmal.")
	await get_tree().create_timer(0.6, false).timeout
	_fade(1.0, 0.4)
	var t_end := _time + 6.0
	await get_tree().create_timer(1.6 if reason != "menu" else 0.4, false).timeout
	while is_inside_tree() and _foot != null and is_instance_valid(_foot) and not bool(_foot.call("is_alive")) and _time < t_end:
		await get_tree().process_frame
	_clear_phase_nodes()
	if train != null:
		train.call("clear_tunnels")
	for c in civs:
		if is_instance_valid(c):
			c.call("reset")
	_civ_hits = 0
	_lena_hits = 0
	_weber_hits = 0
	_roof_stage = 0
	_hatch_open = false
	if _foot != null and is_instance_valid(_foot):
		_foot.call("respawn")
	_crumbs.clear()
	_lena_to_player()
	if train != null:
		train.set("wind_level", 1.0 if _ppos().y > 3.0 else 0.0)
	await get_tree().create_timer(0.5, false).timeout
	_fade(0.0, 0.6)
	await get_tree().create_timer(0.6, false).timeout

## Reisende zwischen z0 und z1 gehen in Deckung (ducken sich / kriechen ins Abteil); reset() hebt es auf.
func _civs_cover(z0: float, z1: float) -> void:
	for c in civs:
		if is_instance_valid(c) and c.has_method("take_cover"):
			var z: float = (c as Node3D).position.z
			if z <= z0 and z >= z1:
				c.call("take_cover")

func _wait_entry(z: float) -> bool:
	return await _until(func() -> bool: return _ppos().z < z, -1.0)

## P1: Abteilwagen.
func _p1() -> bool:
	_checkpoint("cp_w1")
	var es: Array = [_enemy("rifleman", Vector3(0.85, Y, -14.0), 0.35, 180.0),
		_enemy("assault", Vector3(0.5, Y, -20.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(1.0, Y, -24.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(0.8, Y, -17.0), 0.35, 180.0),
		_enemy("assault", Vector3(-0.6, Y, -21.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(0.9, Y, -19.0), 0.35, 180.0),
		_enemy("assault", Vector3(-0.4, Y, -22.5), 0.35, 180.0)]
	if not await _sleep(0.8):
		return false
	_say(SD.LENA, "Graue Mäntel im Gang! Sie haben uns erkannt!")
	_civs_cover(-1.0, -25.0)
	_alert_all(es)
	_obj("Garde-Jäger im Abteilwagen ausschalten")
	if not await _clear(es, 110.0):
		return false
	_say(SD.LENA, "Wagen eins ist frei. Weiter zum Speisewagen.")
	return true

## P2: Speisewagen.
func _p2() -> bool:
	var es: Array = [_enemy("rifleman", Vector3(0.0, Y, -36.0), 0.4, 180.0),
		_enemy("assault", Vector3(0.3, Y, -42.0), 0.4, 180.0),
		_enemy("officer", Vector3(0.5, Y, -45.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.8, Y, -50.5), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.0, Y, -33.0), 0.4, 180.0),
		_enemy("assault", Vector3(0.8, Y, -48.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(-0.5, Y, -35.5), 0.4, 180.0),
		_enemy("assault", Vector3(-0.3, Y, -38.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(-0.6, Y, -44.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.2, Y, -47.0), 0.4, 180.0)]
	VF.play_2d(self, "nachtzug_chime", -4.0)
	if not await _sleep(1.6):
		return false
	_say(SD.FALK, "Werte Fahrgäste, hier spricht Oberst Falk. Bleiben Sie in Ihren Abteilen. Es befinden sich zwei bewaffnete Terroristen im Zug.")
	if not await _radio_wait(9.0):
		return false
	train.call("open_door", 0)
	_obj("Speisewagen säubern – Reisende an den Tischen nicht treffen")
	if not await _wait_entry(ENTRY_Z[2]):
		return false
	_checkpoint("cp_w2")
	_top_up_ammo()
	_say(SD.LENA, "Speisewagen. Die verschanzen sich hinter den Tischen.")
	_civs_cover(-26.0, -52.0)
	_alert_all(es)
	if not await _clear(es, 120.0):
		return false
	_say(SD.KERNER, "Speisewagen sauber. Der Gepäckwagen ist als Nächstes.")
	return true

## P3: Gepaeckwagen.
func _p3() -> bool:
	# Balance 13.11.2026: Vorher standen alle 10 (Schwerer auf 6 m, Sturmgewehr auf 5 m hinter der Tuer)
	# gleichzeitig im 3-m-Gang und waren alarmiert, sobald man die Schwelle uebertrat -> Bot tot nach 6-20 s.
	# Jetzt zwei Wellen: Welle 1 (5) hinter den Kisten ab 9 m, der Schwere im hinteren Drittel; Welle 2 (5)
	# kommt als Verstaerkung durch die Stirntuer vorn (immer >= 9 m vor dem Spieler), sobald Welle 1 bis auf
	# einen Mann gefallen ist. Gleiche Gegnerzahl, kein Spawn im Ruecken.
	# Fairness 14.11.2026 (nach GARDE_HP/ACC): Welle 2 kommt mit Vorwarnung (Funk, Auftrag, Tuergeraeusch)
	# und gestaffelt durch die Tuer statt als fertiger Pulk aus dem Nichts; nach Welle 1 gibt es einen
	# Zwischen-Checkpoint (cp_w3b) hinter der ersten Kiste - wer in Welle 2 faellt, spielt nur Welle 2 neu.
	train.call("open_door", 1)
	if _p3_w1_done:
		_obj("Gepäckwagen säubern")
		return await _p3_wave2([])
	var es: Array = [_enemy("assault", Vector3(-0.3, Y, -65.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.7, Y, -66.5), 0.4, 180.0),
		_enemy("rifleman", Vector3(-0.4, Y, -69.0), 0.4, 180.0),
		_enemy("heavy", Vector3(0.1, Y, -73.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.3, Y, -76.0), 0.4, 180.0)]
	_obj("Gepäckwagen säubern")
	if not await _wait_entry(ENTRY_Z[3]):
		return false
	_checkpoint("cp_w3")
	_top_up_ammo()
	_say(SD.LENA, "Gepäckwagen. Vorsicht, die haben einen Schweren dabei.")
	_alert_all(es)
	if not await _until(func() -> bool: return _alive_count(es) <= 1, 70.0):
		return false
	_p3_w1_done = true
	_checkpoint("cp_w3b")
	# Wiedereinstieg nicht mitten im Gang (wo man gerade stand), sondern in Deckung hinter der Kiste
	if _foot != null and is_instance_valid(_foot):
		_foot.set("_checkpoint_pos", P3_MID_SPOT)
		_foot.set("_checkpoint_yaw", 0.0)
	return await _p3_wave2(es)

## P3 Welle 2: Vorwarnung, dann einer nach dem anderen durch die Stirntuer (W3 vorn, -80.95).
func _p3_wave2(es: Array) -> bool:
	_say(SD.LENA, "Mehr von denen, vorn auf dem nächsten Wagen!")
	_obj("Verstärkung an der Stirntür – in Deckung gehen")
	VF.play_at(self, "nachtzug_door", Vector3(0.0, Y + 1.0, -80.9), -2.0, 8.0, 60.0)
	if not await _sleep(P3_W2_WARN):
		return false
	var w2_pos: Array[Vector3] = [Vector3(0.2, Y, -78.0), Vector3(-0.3, Y, -79.5), Vector3(0.5, Y, -79.9),
		Vector3(-0.2, Y, -78.8), Vector3(0.1, Y, -79.2)]
	var w2_type: Array[String] = ["assault", "rifleman", "rifleman", "assault", "rifleman"]
	var w2: Array = []
	for i in w2_pos.size():
		var p := w2_pos[i]
		p.z = minf(p.z, _ppos().z - 9.0)
		p.z = maxf(p.z, -80.0)   # Stirnwand W3 bei -80.95
		var e := _enemy(w2_type[i], p, 0.4, 180.0)
		w2.append(e)
		_alert_all([e])
		if i == 0:
			print("[nachtzug] Phase 3: Welle 2 (5) vorn, Spieler bei z %.1f" % _ppos().z)
		if i < w2_pos.size() - 1 and not await _sleep(P3_W2_STAGGER):
			return false
	_obj("Gepäckwagen säubern")
	es.append_array(w2)
	if not await _clear(es, 90.0):
		return false
	return true

func _alive_count(nodes: Array) -> int:
	var c := 0
	for n in nodes:
		if _alive(n):
			c += 1
	return c

# ------------------------------------------------------------------ P4: Hubschrauber, MG an der Ladetuer

func _p4() -> bool:
	if ride == null:
		_say(SD.LENA, "Hörst du das? Rotoren. Die Garde hat einen Hubschrauber.")
		_say(SD.LENA, "Ich mach die Ladetür auf. Da hängt ein MG an der Halterung – nimm es!")
		train.call("open_door", 4)
		train.set("auto_tunnels", false)
		train.call("clear_tunnels")
		if not await _radio_wait(9.0):
			return false
		_fade(1.0, 0.35)
		await get_tree().create_timer(0.4, false).timeout
		_start_ride()
		_fade(0.0, 0.5)
	_obj("Garde-Hubschrauber mit dem Tür-MG abschießen")
	_heli = _spawn_heli()
	_say(SD.FALK, "Kerner, Sie fahren nicht bis Wien. Das garantiere ich Ihnen.")
	var ok: bool = await _until(func() -> bool: return not _alive(_heli), 300.0)
	if not ok:
		return false
	if _alive(_heli):
		print("[nachtzug] Heli-Zeitlimit-Fallback (Panzerfaust) bei %.0f HP" % float(_heli.get("health")))
		_say(SD.LENA, "Ich hab noch die Panzerfaust! Deckung!")
		await _sleep(2.0)
		if _failed != "":
			return false
		if lena != null and is_instance_valid(lena) and _heli != null and is_instance_valid(_heli):
			VF.tracer(self, lena.call("muzzle_pos"), _heli.global_position, 120.0, "orange", 2.0)
		_kill(_heli)
	if _heli != null and is_instance_valid(_heli):
		train.call("add_scroller", _heli)
	_say(SD.KERNER, "Hubschrauber ist unten.")
	if not await _sleep(2.5):
		return false
	print("[nachtzug] Heli abgeschossen nach %.1f s" % (_time - _heli_t0))
	_fade(1.0, 0.35)
	await get_tree().create_timer(0.4, false).timeout
	_free_heli_ui()
	_end_ride()
	_checkpoint("cp_w4")
	_top_up_ammo()
	_fade(0.0, 0.5)
	return true

func _start_ride() -> void:
	if _foot != null and is_instance_valid(_foot):
		_foot.remove_from_group("player")
		_foot.remove_from_group("damageable")
		(_foot as CollisionObject3D).collision_layer = 0
		_foot.process_mode = Node.PROCESS_MODE_DISABLED
		_set_foot_visual(false)
		_foot.global_position = Vector3(0.1, 1.25, -66.0)
	ride = RailRide.new()
	ride.name = "TuerMG"
	ride.call("configure", {"vehicle_name": "Tür-MG", "cruise_speed": 0.0, "accel": 1.0, "decel": 1.0,
		"mount_offset": Vector3(0, 1.25, 0), "eye_offset": Vector3(0, 0.3, 0.5),
		"yaw_limit_deg": 56.0, "pitch_min_deg": -12.0, "pitch_max_deg": 40.0,
		"rock_roll_deg": 0.6, "rock_pitch_deg": 0.4, "bob_amp": 0.02, "cam_stabilize": 0.7,
		"max_integrity": 100.0, "weapon": {"name": "MG5"}})
	ride.set("invulnerable", _fail_count >= 2)
	add_child(ride)
	ride.call("add_hull_box", Vector3(0, 1.2, 0), Vector3(0.8, 1.6, 0.8))
	ride.call("set_path", RIDE_PATH)
	ride.connect("destroyed", func() -> void: _fail("tuer"))
	ride.call("reset_to", 0.0)
	player = ride
	if _lena_c != null:
		_lena_c.call("reset")
	if lena != null and is_instance_valid(lena):
		lena.global_position = Vector3(-0.3, Y + 0.05, -66.5)
		lena.call("walk_to", Vector3(-0.3, Y, -66.5), 1.0, false)
		lena.set("crouch", true)

func _end_ride() -> void:
	if ride != null and is_instance_valid(ride):
		ride.queue_free()
	ride = null
	if _foot != null and is_instance_valid(_foot):
		_foot.process_mode = Node.PROCESS_MODE_INHERIT
		_foot.add_to_group("player")
		_foot.add_to_group("damageable")
		(_foot as CollisionObject3D).collision_layer = _foot_layer
		_set_foot_visual(true)
		var cam: Variant = _foot.call("get_camera")
		if cam is Camera3D:
			(cam as Camera3D).make_current()
		_teleport(Vector3(0.1, 1.25, -70.0), 0.0)
	player = _foot
	if lena != null and is_instance_valid(lena):
		lena.set("crouch", false)

func _set_foot_visual(on: bool) -> void:
	for nm: String in ["HUD", "WeaponLayer"]:
		var n := _foot.get_node_or_null(nm)
		if n != null and "visible" in n:
			n.set("visible", on)

func _spawn_heli() -> Node3D:
	var h := (load(HELI_SCENE) as PackedScene).instantiate() as Node3D
	h.set_meta("faction", "reich")
	h.set("max_health", HELI_HP)
	# Balance: 22/5 = 4.4 je Rumpftreffer, Kanzel/Rotorkopf x3 (13.2). 3200 HP brauchten ~730 Rumpftreffer
	# (~78 s Dauerfeuer, zaeh). 1800 HP: reiner Rumpfbeschuss ~410 Treffer, gezielt auf die Schwachstellen
	# deutlich weniger; mit Abdreh-Pausen ~35-45 s Gefecht.
	h.set("mg_toughness", HELI_MG_TOUGHNESS)
	h.set("weak_spot_mult", HELI_WEAK_MULT)
	h.set("damage_stages", true)
	h.set("mg_damage", 4.0)
	h.set("burst_rounds", 10)
	h.set("attack_range", 200.0)
	h.set("searchlight", false)   # eigener, auf den Zug nachgefuehrter Scheinwerfer: _dress_heli
	h.name = "GardeHeli"
	add_child(h)
	h.global_position = Vector3(70.0, 20.0, -20.0)
	if _heli_hp_keep > 0.0:
		h.set("health", minf(_heli_hp_keep, float(h.get("max_health"))))
		if h.has_method("_update_damage_stage"):
			h.call("_update_damage_stage")
	_heli_stage_seen = int(h.get("damage_stage"))
	_heli_hinted = false
	_heli_evade = 0.0
	_heli_evades = 0
	_dress_heli(h)
	h.set_meta("priority", 40.0)
	h.call("attack", true)
	h.call("hover_at", Vector3(36.0, 15.0, -60.0))
	_phase_nodes.append(h)
	_heli_t = 3.0
	_heli_t0 = _time
	_heli_log_t = 10.0
	_make_heli_ui()
	return h

## Bossleiste oben: Name, Lebensbalken, Hinweis auf die Schwachstellen; blinkt bei Schwachstellen-Treffern.
func _make_heli_ui() -> void:
	_free_heli_ui()
	_heli_ui = CanvasLayer.new()
	_heli_ui.layer = 20
	add_child(_heli_ui)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.position = Vector2(-300, 26)
	box.size = Vector2(600, 70)
	box.add_theme_constant_override("separation", 4)
	# in 1080p-Pixeln unter skalierter Wurzel (kleine Fenster, z. B. 960x540)
	var hroot := UIStyle.HudRoot.new()
	_heli_ui.add_child(hroot)
	hroot.add_child(box)
	var title := Label.new()
	title.text = "GARDE-KAMPFHUBSCHRAUBER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.95, 0.9, 0.82))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 5)
	box.add_child(title)
	# Zwei Leisten uebereinander: hinten die helle Nachlauf-Leiste (folgt verzoegert), vorn der echte Wert.
	# Das helle Stueck dazwischen zeigt jede Salve als sichtbaren Abzug.
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(600, 16)
	box.add_child(stack)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	bg.border_color = Color(0.0, 0.0, 0.0, 0.9)
	bg.set_border_width_all(2)
	var gf := StyleBoxFlat.new()
	gf.bg_color = Color(1.0, 0.88, 0.7, 0.9)
	_heli_ghost = ProgressBar.new()
	_heli_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heli_ghost.show_percentage = false
	_heli_ghost.max_value = 1.0
	_heli_ghost.value = 1.0
	_heli_ghost.add_theme_stylebox_override("background", bg)
	_heli_ghost.add_theme_stylebox_override("fill", gf)
	stack.add_child(_heli_ghost)
	_heli_bar = ProgressBar.new()
	_heli_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	_heli_bar.show_percentage = false
	_heli_bar.max_value = 1.0
	_heli_bar.value = 1.0
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.78, 0.16, 0.1)
	_heli_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
	_heli_bar.add_theme_stylebox_override("fill", fg)
	stack.add_child(_heli_bar)
	if _heli != null and is_instance_valid(_heli):
		var f0 := clampf(float(_heli.get("health")) / maxf(float(_heli.get("max_health")), 1.0), 0.0, 1.0)
		_heli_bar.value = f0
		_heli_ghost.value = f0
		_heli_frac_last = f0
	_heli_hint = Label.new()
	_heli_hint.text = "Schwachstellen: Cockpit und Rotorkopf"
	_heli_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heli_hint.add_theme_font_size_override("font_size", 16)
	_heli_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_heli_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_heli_hint.add_theme_constant_override("outline_size", 4)
	box.add_child(_heli_hint)

func _free_heli_ui() -> void:
	if _heli_ui != null and is_instance_valid(_heli_ui):
		_heli_ui.queue_free()
	_heli_ui = null
	_heli_bar = null
	_heli_ghost = null
	_heli_hint = null

func _update_heli_ui() -> void:
	if _heli_bar == null or not is_instance_valid(_heli_bar):
		return
	if _heli == null or not is_instance_valid(_heli):
		_free_heli_ui()
		return
	var mh := maxf(float(_heli.get("max_health")), 1.0)
	var frac := clampf(float(_heli.get("health")) / mh, 0.0, 1.0)
	_heli_bar.value = lerpf(_heli_bar.value, frac, 0.35)
	if _heli_ghost != null:
		# Nachlauf: kurz stehen lassen, dann mit ~0,3/s nachziehen
		var dt := get_process_delta_time()
		if frac < _heli_frac_last - 0.0001:
			_heli_ghost_hold = 0.4
		_heli_frac_last = frac
		_heli_ghost_hold -= dt
		var gap := _heli_ghost.value - frac
		if gap < 0.0:
			_heli_ghost.value = frac
		elif _heli_ghost_hold <= 0.0:
			_heli_ghost.value = maxf(frac, _heli_ghost.value - dt * (0.25 if gap < 0.1 else 0.5))
	var weak_age := Time.get_ticks_msec() - int(_heli.get("last_weak_hit_ms"))
	if weak_age < 450:
		_heli_hint.text = "VOLLTREFFER – %s" % ("COCKPIT" if str(_heli.get("last_weak_part")) == "cockpit" else "ROTORKOPF")
		_heli_hint.add_theme_color_override("font_color", Color(1.0, 0.8, 0.25))
		(_heli_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(1.0, 0.55, 0.15)
	else:
		_heli_hint.text = "Dreht ab – kommt gleich im Tiefflug zurück" if _heli_evade > 0.0 else "Schwachstellen: Cockpit und Rotorkopf"
		_heli_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		(_heli_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = Color(0.78, 0.16, 0.1)
	if not _alive(_heli):
		_heli_bar.value = 0.0
		_heli_hint.text = "ABGESCHOSSEN"

func _tick_heli(delta: float) -> void:
	_update_heli_ui()
	_tick_heli_lights(delta)
	if _heli == null or not is_instance_valid(_heli) or not _alive(_heli):
		return
	_heli_log_t -= delta
	if _heli_log_t <= 0.0:
		_heli_log_t = 10.0
		print("[nachtzug] Heli %.0f/%.0f HP, Stufe %d, Treffer Rumpf %d / Schwachstelle %d, %.0f s" % [float(_heli.get("health")), float(_heli.get("max_health")), int(_heli.get("damage_stage")), int(_heli.get("hits_body")), int(_heli.get("hits_weak")), _time - _heli_t0])
	var age := _time - _heli_t0
	# Funkhinweis auf die Schwachstellen (sofern der Spieler sie nicht schon gefunden hat)
	if not _heli_hinted and age > HELI_HINT_T:
		_heli_hinted = true
		if int(_heli.get("hits_weak")) < 8:
			_say(SD.LENA, "Der Rumpf ist gepanzert! Halt auf die Kanzel oder den Rotorkopf!")
	if _heli_hinted and ride != null and bool(ride.get("bot_active")):
		_heli.set_meta("aim_offset", _heli.global_basis * HELI_AIM_LOCAL)
	# Ausweichanflug: jede neue Schadensstufe -> abdrehen, kurz keine Salven, dann tiefer Angriffsanflug
	var st := int(_heli.get("damage_stage"))
	if st > _heli_stage_seen:
		_heli_stage_seen = st
		_heli_evades += 1
		_heli_evade = HELI_EVADE_T
		_heli.call("attack", false)
		_heli.set("_speed", 27.0)
		_heli.set("accel", 11.0)
		var side := -1.0 if _heli_evades % 2 == 1 else 1.0
		_heli.call("hover_at", Vector3(randf_range(60.0, 72.0), randf_range(24.0, 30.0), -68.0 + side * randf_range(28.0, 38.0)))
		print("[nachtzug] Heli dreht ab (Stufe %d) bei %.0f s" % [st, age])
		if _heli_evades == 1:
			_say(SD.LENA, "Er dreht ab – weiter, weiter!")
	if _heli_evade > 0.0:
		_heli_evade -= delta
		if _heli_evade <= 0.0:
			# Angriffsanflug: tief und nah, Salven sofort wieder frei
			_heli.set("_speed", 22.0)
			_heli.set("accel", 9.0)
			_heli.call("attack", true)
			_heli.call("hover_at", Vector3(randf_range(24.0, 30.0), randf_range(9.0, 13.0), -68.0 + randf_range(-12.0, 12.0)))
			_heli_t = 3.5
		return
	_heli_t -= delta
	if _heli_t <= 0.0:
		_heli_t = 3.0
		_heli.set("_speed", 18.0)
		_heli.set("accel", 7.0)
		_heli.call("hover_at", Vector3(randf_range(28.0, 45.0), randf_range(10.0, 22.0), -68.0 + randf_range(-25.0, 25.0)))

# ------------------------------------------------------------------ P4: Heli-Beleuchtung (nur dieses Level)
## Nachts war der Heli nur eine dunkle Silhouette vor dem Sternenhimmel. Hier bekommt er echte Befeuerung:
## Positionslichter (rot backbord / gruen steuerbord), weisser Doppelblitz am Heck, rote Anti-Kollisions-
## Rundumleuchten (oben am Rotormast, unten am Bauch), schwaches gruenes Cockpitglimmen (NVG-Beleuchtung),
## einen auf den Zug gerichteten Suchscheinwerfer mit sichtbarem Lichtkegel und ein Muendungsfeuer der
## Kinnkanone, das die Kanzel kurz anleuchtet. Alles als Kind-Nodes am Modell-Pivot (neigt sich mit);
## helicopter.gd bleibt unveraendert. Leuchtpunkte sind Billboards mit fester Bildschirmgroesse, damit
## sie auf 30-50 m nicht unter einen Pixel schrumpfen.

const HL_RED := Color(1.0, 0.08, 0.04)
const HL_GREEN := Color(0.15, 1.0, 0.3)
const HL_WHITE := Color(1.0, 0.97, 0.92)
const HL_COCKPIT := Color(0.35, 1.0, 0.55)
const HL_BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 beam_color : source_color = vec4(0.75, 0.8, 0.95, 1.0);
uniform float strength = 0.12;
varying float along;
void vertex() {
	along = clamp(0.5 - VERTEX.y, 0.0, 1.0);
}
void fragment() {
	float fall = pow(1.0 - along, 1.4) * smoothstep(0.0, 0.04, along);
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.6);
	ALBEDO = beam_color.rgb * strength * fall * edge;
}
"""

var _hl: Dictionary = {}           ## Leucht-Nodes des aktuellen Helis (P4)
var _hl_t: float = 0.0
var _hl_burst: int = 0
var _hl_flash: float = 0.0
var _hl_sweep: float = 0.0
static var _hl_tex: Texture2D = null

static func _hl_glow_tex() -> Texture2D:
	if _hl_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.18, Color(1, 1, 1, 0.85))
		g.add_point(0.45, Color(1, 1, 1, 0.22))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_hl_tex = t
	return _hl_tex

## Leuchtpunkt: Billboard, additiv, feste Bildschirmgroesse (size ~ Winkel in rad), dazu optional ein Punktlicht.
func _hl_glow(parent: Node3D, pos: Vector3, c: Color, size: float, light_energy: float = 0.0, light_range: float = 2.5) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.fixed_size = true
	m.disable_fog = true
	m.albedo_texture = _hl_glow_tex()
	m.albedo_color = Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 1.0)
	m.render_priority = 2
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var mi := MeshInstance3D.new()
	mi.name = "Glow"
	mi.mesh = q
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if light_energy > 0.0:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.light_color = c
		l.omni_range = light_range
		l.light_energy = light_energy
		l.shadow_enabled = false
		l.set_meta("energy", light_energy)
		root.add_child(l)
	root.set_meta("color", m.albedo_color)
	return root

## Helligkeit eines Leuchtpunkts (0..1+): Billboard-Alpha und Lichtenergie.
func _hl_set(n: Variant, k: float) -> void:
	if not (n is Node3D) or not is_instance_valid(n):
		return
	var root := n as Node3D
	root.visible = k > 0.01
	if not root.visible:
		return
	var mi := root.get_node_or_null("Glow") as MeshInstance3D
	if mi != null:
		var c: Color = root.get_meta("color")
		(mi.material_override as StandardMaterial3D).albedo_color = Color(c.r * k, c.g * k, c.b * k, 1.0)
	var l := root.get_node_or_null("Light") as OmniLight3D
	if l != null:
		l.light_energy = float(l.get_meta("energy")) * k

func _hl_part_pos(parts: Dictionary, key: String, fallback: Vector3) -> Vector3:
	var v: Variant = parts.get(key)
	if v is Node3D and is_instance_valid(v):
		return (v as Node3D).position
	if v is Vector3:
		return v
	return fallback

func _dress_heli(h: Node3D) -> void:
	_hl.clear()
	var pivot := h.get_node_or_null("Model") as Node3D
	if pivot == null:
		pivot = h
	var parts: Variant = h.get("_parts")
	var pd: Dictionary = parts if parts is Dictionary else {}
	# Positionslichter an den Stummelfluegeln (die Modell-Birnchen mit 7 cm Radius sind auf 40 m unsichtbar)
	_hl["nav_l"] = _hl_glow(pivot, _hl_part_pos(pd, "nav_l", Vector3(-3.38, -0.1, 1.0)), HL_RED, 0.022, 1.2, 3.0)
	_hl["nav_r"] = _hl_glow(pivot, _hl_part_pos(pd, "nav_r", Vector3(3.44, -0.1, 1.0)), HL_GREEN, 0.022, 1.2, 3.0)
	# Weisser Heckblitz
	var tail := _hl_part_pos(pd, "strobe", Vector3(-0.45, 1.75, 11.2))
	_hl["strobe"] = _hl_glow(pivot, tail + Vector3(0, 0.15, 0.2), HL_WHITE, 0.05, 1.2, 4.0)
	# Rote Anti-Kollisionsleuchten: oben hinter dem Rotormast (leuchtet den Rotorkopf an) und unter dem Rumpf
	_hl["beacon_top"] = _hl_glow(pivot, Vector3(0.0, 1.45, 0.9), HL_RED, 0.035, 1.4, 3.0)
	_hl["beacon_low"] = _hl_glow(pivot, Vector3(0.0, -1.05, 0.6), HL_RED, 0.03, 1.0, 3.0)
	# Cockpit: gruenes Instrumentenglimmen in beiden Kanzeln (Tandem), schwach
	_hl["cockpit_f"] = _hl_glow(pivot, Vector3(0.0, 0.35, -4.6), HL_COCKPIT, 0.016, 0.9, 1.8)
	_hl["cockpit_r"] = _hl_glow(pivot, Vector3(0.0, 0.85, -3.4), HL_COCKPIT, 0.014, 0.7, 1.6)
	# Muendungsfeuer der Kinnkanone (zusaetzlich zum eingebauten Blitz): grosser Leuchtpunkt + Licht auf die Kanzel
	var mz: Variant = pd.get("muzzle")
	var mz_parent: Node3D = mz if mz is Node3D else pivot
	_hl["muzzle"] = _hl_glow(mz_parent, Vector3(0, 0, -0.3) if mz is Node3D else Vector3(0, -1.0, -5.0), Color(1.0, 0.62, 0.25), 0.06, 3.0, 5.0)
	_hl_set(_hl["muzzle"], 0.0)
	# Suchscheinwerfer: Lampe, Spot (mit Volumen-Nebel) und sichtbarer Lichtkegel, folgt dem Zug
	var mount: Variant = pd.get("searchlight_mount")
	var sl_parent: Node3D = mount if mount is Node3D else pivot
	var aim := Node3D.new()
	aim.name = "SuchscheinwerferZiel"
	sl_parent.add_child(aim)
	if not (mount is Node3D):
		aim.position = Vector3(0.05, -0.95, -3.6)
	_hl["aim"] = aim
	var spot := SpotLight3D.new()
	spot.light_color = Color(0.92, 0.95, 1.0)
	spot.light_energy = 7.0
	spot.spot_range = 80.0
	spot.spot_angle = 6.5
	spot.spot_attenuation = 0.5
	spot.light_volumetric_fog_energy = 1.0
	spot.shadow_enabled = true
	aim.add_child(spot)
	_hl["spot"] = spot
	_hl["lamp"] = _hl_glow(aim, Vector3(0, 0, -0.15), HL_WHITE, 0.022, 0.0)
	var beam := Node3D.new()
	beam.name = "Lichtkegel"
	aim.add_child(beam)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.006
	cyl.bottom_radius = tan(deg_to_rad(6.0))
	cyl.height = 1.0
	cyl.radial_segments = 20
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var sh := Shader.new()
	sh.code = HL_BEAM_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var cone := MeshInstance3D.new()
	cone.mesh = cyl
	cone.material_override = sm
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cone.rotation_degrees = Vector3(90, 0, 0)   # Spitze (+Y) an der Lampe, Kegel laeuft nach -Z
	cone.position = Vector3(0, 0, -0.5)
	beam.add_child(cone)
	_hl["beam"] = beam
	_hl_t = randf() * 2.0
	_hl_burst = int(h.get("_burst_left"))
	_hl_flash = 0.0
	_hl_sweep = 0.0

func _tick_heli_lights(delta: float) -> void:
	if _hl.is_empty():
		return
	if _heli == null or not is_instance_valid(_heli):
		_hl.clear()
		return
	var alive := _alive(_heli)
	if not alive:
		# Abschuss: Bordnetz faellt aus, alles dunkel (Brand/Explosion leuchten selbst)
		for k: String in _hl:
			var n: Variant = _hl[k]
			if n is Node3D and is_instance_valid(n) and k != "aim":
				(n as Node3D).visible = false
		_hl.clear()
		return
	_hl_t += delta
	# Positionslichter dauerhaft, leichtes Flackern durch Vibration
	_hl_set(_hl.get("nav_l"), 1.0)
	_hl_set(_hl.get("nav_r"), 1.0)
	# Heckblitz: Doppelblitz alle 1,3 s
	var sp := fmod(_hl_t, 1.3)
	_hl_set(_hl.get("strobe"), 1.6 if (sp < 0.05 or (sp > 0.16 and sp < 0.21)) else 0.0)
	# Rundumleuchten: rotierender Reflektor -> weiches Pulsieren ~1,1 Hz, unten versetzt
	_hl_set(_hl.get("beacon_top"), 0.12 + 1.2 * pow(maxf(0.0, sin(_hl_t * TAU * 1.1)), 6.0))
	_hl_set(_hl.get("beacon_low"), 0.1 + 1.1 * pow(maxf(0.0, sin(_hl_t * TAU * 1.1 + PI)), 6.0))
	_hl_set(_hl.get("cockpit_f"), 0.85 + 0.1 * sin(_hl_t * 7.0))
	_hl_set(_hl.get("cockpit_r"), 0.8)
	# Muendungsfeuer: jede abgegebene Patrone (Salvenzaehler sinkt) zuendet kurz den Leuchtpunkt
	var bl := int(_heli.get("_burst_left"))
	if bl < _hl_burst:
		_hl_flash = 0.06
	_hl_burst = bl
	_hl_flash -= delta
	_hl_set(_hl.get("muzzle"), randf_range(0.8, 1.3) if _hl_flash > 0.0 else 0.0)
	# Suchscheinwerfer: sucht die Ladetuer ab (langsames Schwenken um den Spieler), Kegel endet am Zug
	var aim: Variant = _hl.get("aim")
	if aim is Node3D and is_instance_valid(aim):
		var a := aim as Node3D
		var pl := player as Node3D
		var tgt := Vector3(2.5, 1.0, -68.0)
		if pl != null and is_instance_valid(pl):
			tgt = pl.global_position + Vector3(1.6, -2.4, 0.0)   # Wagenflanke unter der Tuer, nicht ins Gesicht
		_hl_sweep += delta
		tgt += Vector3(0.0, sin(_hl_sweep * 0.9) * 0.8, sin(_hl_sweep * 0.55) * 5.0)
		var from := a.global_position
		if from.distance_to(tgt) > 2.0:
			var want := Transform3D.IDENTITY.looking_at(tgt - from, Vector3.UP)
			var cur := Basis(a.global_basis.get_rotation_quaternion())
			var k := 1.0 - exp(-maxf(delta, 0.016) * 4.0)
			a.global_basis = Basis(cur.get_rotation_quaternion().slerp(want.basis.get_rotation_quaternion(), k))
			var beam: Variant = _hl.get("beam")
			if beam is Node3D and is_instance_valid(beam):
				var blen := clampf(from.distance_to(tgt), 5.0, 90.0)
				(beam as Node3D).scale = Vector3.ONE * blen

# ------------------------------------------------------------------ P5: Dach

func _on_roof() -> bool:
	return _ppos().y > 3.4

func _p5() -> bool:
	train.set("auto_tunnels", false)
	_roof_stage = 0
	if not _on_roof():
		train.call("open_door", 2)
		_say(SD.LENA, "Wagen vier und fünf sind Postwagen ohne Durchgang. Wir müssen übers Dach.")
		_obj("Über das Dach nach vorn")
		if not await _wait_entry(ROOF_ENTRY_Z):
			return false
		_fade(1.0, 0.25)
		await get_tree().create_timer(0.3, false).timeout
		if _failed != "":
			return false
		_teleport(ROOF_SPOT, 0.0)
		_fade(0.0, 0.5)
	_checkpoint("cp_dach")
	_top_up_ammo()
	train.set("wind_level", 1.0)
	_say(SD.LENA, "Oben ist Fahrtwind ohne Ende. Und achte auf die Tunnel – wer steht, wird abgeräumt.", 0.0,
		{"priority": 1, "cut": true})
	_obj("Garde auf dem Dach ausschalten – bei Tunneln ducken oder hinlegen")
	# Welle 1 + Tunnel 1
	_roof_stage = 1
	_roof_enemies = [_enemy("rifleman", Vector3(0.6, YR, -100.0), 0.35, 180.0),
		_enemy("assault", Vector3(-0.6, YR, -104.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(0.5, YR, -112.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(-1.0, YR, -108.0), 0.35, 180.0),
		_enemy("assault", Vector3(0.9, YR, -102.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(-0.3, YR, -110.0), 0.35, 180.0)]
	var w1: Array = _roof_enemies.duplicate()
	_alert_all(w1)
	train.call("spawn_tunnel_eta", _ppos().z, 16.0)
	if not await _clear(w1, 70.0):
		return false
	if not await _until(_tunnel_passed, 30.0):
		return false
	# Welle 2 + Tunnel 2
	_say(SD.LENA, "Mehr von denen, vorn auf dem nächsten Wagen!", 0.0, {"priority": 1, "max_age": 4.0})
	_roof_stage = 2
	# Welle 2 nie direkt vor dem Spieler: ganze Welle nach vorn schieben, falls er schon weit vorn steht
	var w2_off: float = minf(0.0, (_ppos().z - 14.0) - (-122.0))
	var w2: Array = [_enemy("rifleman", _roof_ahead(Vector3(-0.6, YR, -122.0 + w2_off), 14.0), 0.38, 180.0),
		_enemy("assault", _roof_ahead(Vector3(0.6, YR, -128.0 + w2_off), 14.0), 0.38, 180.0),
		_enemy("heavy", _roof_ahead(Vector3(0.0, YR, -132.0 + w2_off), 14.0), 0.35, 180.0),
		_enemy("rifleman", _roof_ahead(Vector3(1.0, YR, -125.0 + w2_off), 14.0), 0.38, 180.0),
		_enemy("rifleman", _roof_ahead(Vector3(-1.0, YR, -135.0 + w2_off), 14.0), 0.38, 180.0),
		_enemy("assault", _roof_ahead(Vector3(0.3, YR, -130.0 + w2_off), 14.0), 0.38, 180.0),
		_enemy("rifleman", _roof_ahead(Vector3(-0.5, YR, -138.0 + w2_off), 14.0), 0.38, 180.0)]
	_roof_enemies.append_array(w2)
	_alert_all(w2)
	train.call("spawn_tunnel_eta", _ppos().z, 18.0)
	if not await _clear(w2, 75.0):
		return false
	if not await _until(_tunnel_passed, 30.0):
		return false
	# Luke in den Schlafwagen
	_roof_stage = 3
	_hatch_open = true
	_say(SD.LENA, "Da vorn ist eine Dachluke. Rein in den Schlafwagen!", 0.0, {"priority": 1, "cut": true})
	_obj("Durch die Dachluke in den Schlafwagen")
	if not await _wait_entry(HATCH_Z):
		return false
	_fade(1.0, 0.25)
	await get_tree().create_timer(0.3, false).timeout
	if _failed != "":
		return false
	_teleport(HATCH_SPOT, 0.0)
	train.set("wind_level", 0.0)
	_roof_stage = 0
	_hatch_open = false
	_checkpoint("cp_w6")
	_top_up_ammo()
	_fade(0.0, 0.5)
	return true

func _tunnel_passed() -> bool:
	var z := _ppos().z
	return float(train.call("tunnel_eta", z)) == INF and (train.call("tunnel_at", z) as Dictionary).is_empty()

func _make_tunnel_ui() -> void:
	_tunnel_layer = CanvasLayer.new()
	_tunnel_layer.layer = 20
	add_child(_tunnel_layer)
	_tunnel_ui = Label.new()
	_tunnel_ui.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tunnel_ui.position = Vector2(-260, 120)
	_tunnel_ui.size = Vector2(520, 60)
	_tunnel_ui.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tunnel_ui.add_theme_font_size_override("font_size", 30)
	_tunnel_ui.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	_tunnel_ui.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_tunnel_ui.add_theme_constant_override("outline_size", 6)
	_tunnel_ui.visible = false
	var troot := UIStyle.HudRoot.new()   # 1080p-Pixel, skaliert mit dem Fenster
	_tunnel_layer.add_child(troot)
	troot.add_child(_tunnel_ui)

## Tunnelregel: Warnung, Countdown; im Tunnel stirbt, wer auf dem Dach steht.
func _tick_tunnels() -> void:
	if train == null:
		return
	var show := false
	if ride == null and _foot_ok() and _on_roof():
		var z := _ppos().z
		var eta: float = train.call("tunnel_eta", z)
		var cur: Dictionary = train.call("tunnel_at", z)
		var nt: Dictionary = train.call("next_tunnel", z)
		if eta < 6.0 and not nt.is_empty():
			show = true
			_tunnel_ui.text = "TUNNEL  %.1f s  –  DUCKEN ODER HINLEGEN" % eta
			if not bool(nt.get("warned", false)):
				nt["warned"] = true
				_say(SD.LENA, "Tunnel voraus! Runter, sofort!", 0.0, {"priority": 2, "cut": true, "max_age": 2.0})
		if not cur.is_empty():
			show = true
			_tunnel_ui.text = "TUNNEL – UNTEN BLEIBEN"
			if not bool(cur.get("entered", false)):
				print("[nachtzug] Tunnel erreicht, Haltung %d" % int(_foot.get("stance")))
			cur["entered"] = true
			var standing := int(_foot.get("stance")) == 0 and not bool(_foot.get("is_crouching"))
			if standing and not bool(cur.get("killed", false)):
				cur["killed"] = true
				print("[nachtzug] Tunnel: Spieler stand auf dem Dach")
				_foot.call("take_damage", 99999.0, self, _ppos() + Vector3.UP * 1.7, Vector3.BACK)
	_tunnel_ui.visible = show
	# Garde auf dem Dach
	for e in _roof_enemies:
		if not _alive(e):
			continue
		var en := e as Node3D
		if en.global_position.y < 3.4:
			continue
		if (train.call("tunnel_at", en.global_position.z) as Dictionary).is_empty():
			continue
		if float(en.get("_stance")) < 0.5:
			_kill(en)
	# Nach jedem Tunnel ein kurzer Kommentar
	for t: Dictionary in (train.get("tunnels") as Array):
		if bool(t.get("entered", false)) and not bool(t.get("commented", false)) and float(t["z"]) - float(t["len"]) > _ppos().z + 2.0:
			t["commented"] = true
			if _foot_ok() and not _knapp_said and _radio_busy() <= 0.3:
				_knapp_said = true
				_say(SD.LENA, "Das war knapp.", 0.0, {"max_age": 1.5, "key": "knapp"})

# ------------------------------------------------------------------ P6: Schlafwagen

func _p6() -> bool:
	if _ppos().z > HATCH_SPOT.z + 1.0 and _ppos().y < 3.0:
		_teleport(HATCH_SPOT, 0.0)
	_checkpoint("cp_w6")
	# Spawns >= 16 m vor der Luke (HATCH_SPOT z -139.5), im hinteren Gangende; die Abteile liegen
	# nicht auf dem Navmesh. Frueher stand der erste Gegner 11 m vor dem Spieler im Blickfeld.
	var es: Array = [_enemy("rifleman", _ahead_spread(Vector3(0.6, Y, -156.0), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("assault", _ahead_spread(Vector3(0.9, Y, -157.8), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("officer", _ahead_spread(Vector3(0.5, Y, -159.6), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("rifleman", _ahead_spread(Vector3(0.8, Y, -161.4), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("rifleman", _ahead_spread(Vector3(0.4, Y, -162.6), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("heavy", _ahead_spread(Vector3(0.7, Y, -162.2), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0),
		_enemy("assault", _ahead_spread(Vector3(0.3, Y, -158.6), 16.0, P6_Z_MIN, 2.5), 0.4, 180.0)]
	_say(SD.LENA, "Schlafwagen. Hier liegen Leute in den Betten – kein einziger Fehlschuss!")
	_obj("Schlafwagen säubern – Reisende nicht treffen")
	_civs_cover(-138.0, -170.0)
	if not await _sleep(1.5):
		return false
	_alert_all(es)
	if not await _clear(es, 125.0):
		return false
	return true

# ------------------------------------------------------------------ Finale

func _finale() -> void:
	_done = true
	_obj("Weber stellen – Abteil neun")
	_say(SD.LENA, "Abteil neun ist leer! Er ist nach vorn, zur Lok!")
	var front: Node3D = train.get("front")
	var spot: Vector3 = train.get("weber_spot")
	weber = _make_actor("weber", "officer", spot, C_WEBER, 180.0, {"unarmed": true, "frozen": true}, front)
	weber.name = "Weber"
	train.call("open_door", 3)
	await _until(func() -> bool: return _ppos().z < -161.0, 20.0)
	if _failed != "" or not is_inside_tree():
		return
	# Zwischensequenz (game/cutscene): Weber an der Kupplung, Abkuppeln von außen gesehen.
	# Autopilot/--skip-cutscenes: sofort übersprungen (Abkuppeln passiert trotzdem).
	if not Cutscene.instant_skip():
		await _radio_wait(4.0)     # Lenas "Abteil neun"-Zeile ausklingen lassen
	var skipped: bool = await _decouple_cutscene()
	if not is_inside_tree():
		return
	if skipped:
		await _sleep(1.0)
		await _radio_wait(8.0)
	_say(SD.KERNER, "Verdammt. Wir rollen aus.")
	await _radio_wait(8.0)
	_say(SD.LENA, "Moment. In seinem Abteil – ein Gepäckschein. Zustellung an ‚Villa Seeblick, Altmünster am Traunsee‘.")
	_say(SD.KERNER, "Traunsee. Dann holen wir ihn dort.")
	_obj("Weber ist entkommen – Spur zum Traunsee")
	await _radio_wait(18.0)
	await _sleep(1.5)
	_on_level_end()

## Weber an der Kupplung: Gegenschuss durch den Übergang, dann Außenkamera am Wagenende, die dem abfahrenden
## Zugteil nachschaut. Zeilen und Ablauf wie zuvor (Lenas Zeile ist essential = kommt auch beim Überspringen).
func _decouple_cutscene() -> bool:
	var pl := player as Player
	var head := Vector3(0, 1.62, 0)
	var floor_y: float = 1.2
	var gap_z: float = -164.2
	var cs := Cutscene.new()
	# 1) Blick durch den Übergang auf Weber, leichter Push-in
	cs.shot(null, Vector3(0.25, floor_y + 1.62, -162.6), 3.5, {"look": weber, "look_offset": head, "fov": 42.0,
		"shake": 0.35, "dof": true, "async": true})
	cs._say(SD.WEBER, "Kerner. Sie geben nicht auf, was? Ich auch nicht.")
	# 2) Gegenschuss: Weber im Vordergrund, Kerner im Wagen dahinter
	if pl != null:
		cs.cut(Vector3(-0.7, floor_y + 1.75, -167.4), {"look": pl.get_camera(), "fov": 38.0})
	cs._say(SD.WEBER, "Grüßen Sie Voss. Und sagen Sie ihm, er soll nicht nach mir suchen.")
	# 3) Außen an der Kupplung: der vordere Zugteil zieht davon, Kamera schaut Weber nach
	cs.call_step(func() -> void: train.call("decouple"), true)
	cs.cut(Vector3(2.7, floor_y + 1.3, gap_z + 3.0), {"look": weber, "look_offset": head, "fov": 46.0,
		"shake": 0.6, "dof": false})
	cs._say(SD.LENA, "Er kuppelt ab! Der vordere Zugteil fährt weg!", {"async": true, "essential": true})
	cs.shot(null, Vector3(3.1, floor_y + 2.2, gap_z + 7.0), 4.2, {"fov": 34.0, "trans": Tween.TRANS_QUAD,
		"ease": Tween.EASE_OUT})
	# 4) zurück in Kerners Blick nach vorn
	if pl != null:
		cs.shot(null, pl.get_camera(), 1.0, {"free": true, "fov": pl.get_camera().fov, "shake": 0.0})
	return await cs.play(self)

# ================================================================== Treffer / Rueckmeldungen

func on_civilian_hit(_who: Node) -> void:
	if _failed != "" or _civ_cd > 0.0:
		return
	_civ_cd = 0.6
	_civ_hits += 1
	print("[nachtzug] Reisender getroffen (%d)" % _civ_hits)
	if _civ_hits == 1:
		_say(SD.LENA, "Nicht auf die Reisenden! Noch einmal, und wir brechen ab!")
	elif not _done:
		get_tree().call_group(&"story_ui", &"interrupt")
		_say(SD.LENA, "Ein Unbeteiligter ist getroffen. Abbruch!")
		_fail("zivil")

func on_weber_hit() -> void:
	_weber_hits_total += 1
	if _weber_hits_total == 1 or _weber_hits_total % 4 == 0:
		_say(SD.LENA, "Nicht schießen! Wir brauchen ihn lebend!")

func on_friendly_hit(who: Node) -> void:
	if who != lena or _lena_cd > 0.0:
		return
	_lena_cd = 3.0
	_lena_hits += 1
	_say(SD.LENA, "Kerner! Das war ich!")

func on_friendly_died(_who: Node) -> void:
	pass

func on_enemy_wounded(_who: Node) -> void:
	pass

func _on_player_died() -> void:
	if ride != null:
		return
	if phase >= 1 and phase <= 6 and not _done:
		_fail("tot")

func _on_player_respawned() -> void:
	_crumbs.clear()
	_lena_to_player()

## Pausenmenue: "Checkpoint laden".
func menu_reload_checkpoint() -> void:
	if phase >= 1 and phase <= 6 and not _done:
		_fail("menu")
		return
	if _foot != null and is_instance_valid(_foot) and ride == null:
		_foot.call("respawn")

# ================================================================== Bot

func bot_drives_player() -> bool:
	return _bot_on and _ready_ok and ride == null

## Autopilot-Hook: waehrend der Tuer-MG-Fahrt schiesst rail_ride_bot; der Fuss-Autopilot pausiert.
func autopilot_paused() -> bool:
	return _bot_on and ride != null

func _door(i: int) -> bool:
	return bool(train.call("is_door_open", i))

func _path(pts: Array, y: float = Y) -> Array:
	var out: Array = []
	for p: Vector2 in pts:
		out.append(Vector3(p.x, y, p.y))
	return out

## Aufgabe fuer nachtzug_bot: {kind, path, key, fight, prone}
func bot_task() -> Dictionary:
	var pz := _ppos().z
	match phase:
		1:
			return {"kind": "walk", "key": "p1", "fight": true, "search_doors": P1_DOORS_Z, "search_x": 0.6,
				"path": _path([Vector2(0.85, -4), Vector2(0.85, -12), Vector2(0.85, -20), Vector2(0.6, -24)])}
		2:
			if not _door(0):
				return {"kind": "walk", "key": "p2w", "fight": true, "path": _path([Vector2(0.6, -24)])}
			return {"kind": "walk", "key": "p2", "fight": true,
				"path": _path([Vector2(0.2, -25.2), Vector2(0.1, -27.5), Vector2(0.0, -34), Vector2(0.0, -40), Vector2(0.0, -45), Vector2(0.6, -48), Vector2(0.3, -53)])}
		3:
			if not _door(1):
				return {"kind": "walk", "key": "p3w", "fight": true, "path": _path([Vector2(0.3, -52.5)])}
			return {"kind": "walk", "key": "p3", "fight": true, "crouch_fight": true, "cover": P3_COVER,
				"path": _path([Vector2(0.1, -54.5), Vector2(0.1, -56), Vector2(0.1, -62), Vector2(0.1, -66), Vector2(0.1, -72), Vector2(0.1, -79.5)])}
		5:
			if not _on_roof():
				if not _door(2):
					return {"kind": "walk", "key": "p5w", "fight": true, "path": _path([Vector2(0.1, -75)])}
				return {"kind": "walk", "key": "p5in", "fight": true,
					"path": _path([Vector2(0.1, -75), Vector2(0.1, -80), Vector2(0.0, -81.8)])}
			var prone := _roof_danger(pz)
			match _roof_stage:
				1:
					return {"kind": "walk", "key": "r1", "fight": true, "prone": prone, "path": _path([Vector2(0, -88), Vector2(0, -92)], YR)}
				2:
					return {"kind": "walk", "key": "r2", "fight": true, "prone": prone, "path": _path([Vector2(0, -96), Vector2(0, -104), Vector2(0, -112)], YR)}
				3:
					return {"kind": "walk", "key": "r3", "fight": true, "prone": prone, "path": _path([Vector2(0, -116), Vector2(0, -124), Vector2(0, -133.6)], YR)}
			return {"kind": "walk", "key": "r0", "fight": true, "prone": prone, "path": _path([Vector2(0, -86)], YR)}
		6:
			return {"kind": "walk", "key": "p6", "fight": true,
				"path": _path([Vector2(0.45, -141), Vector2(0.45, -146), Vector2(0.45, -151), Vector2(0.45, -156), Vector2(0.45, -159)])}
		7:
			return {"kind": "walk", "key": "p7", "fight": false, "path": _path([Vector2(0.45, -160), Vector2(0.4, -162.6)])}
	return {"kind": "wait"}

func _roof_danger(z: float) -> bool:
	if train == null:
		return false
	return float(train.call("tunnel_eta", z)) < 4.5 or not (train.call("tunnel_at", z) as Dictionary).is_empty()

# ================================================================== Takt

func _process(delta: float) -> void:
	_time += delta
	_phase_t += delta

func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	_civ_cd = maxf(0.0, _civ_cd - delta)
	_lena_cd = maxf(0.0, _lena_cd - delta)
	_tick_lena(delta)
	_tick_heli(delta)
	_tick_tunnels()
	_tick_fallen()
	if _bot != null and bot_drives_player():
		_bot.call("tick", delta)
