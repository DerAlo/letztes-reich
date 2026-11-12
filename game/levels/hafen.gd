extends "res://game/levels/level.gd"
## Mission "Kräne" (Teil 3 "Jagd auf Weber", Mission 1): Überseehafen Rostock, 12. Juni 2030, Nacht, Regen.
## Teil A: Kerner liegt mit der G28 auf dem Portalkran (150-350 m, böiger Seewind) und deckt Lena, die unten
##   durch die Containergasse geht. Hafenwache, Garde-Jäger (graue Mäntel), Scharfschütze am Lichtmast.
##   Weber taucht kurz auf und darf nicht getroffen werden (1. Treffer Warnung, 2. Abbruch).
## Teil B: Weber flieht per Boot. Kerner am MG des Zollboots (RailRide, game/systems/rail_ride*), Lena fährt,
##   Brandt fliegt darüber. Becken -> Hubbrücke -> Warnow-Mündung -> Frachter "Aurelia" (Hinweis Alpen).
## Debug: --phase=1..7 (1-3 Teil A, 4-6 Boot, 7 Finale). Autopilot: overwatch_bot (A) bzw. rail_ride_bot (B).

const SD := preload("res://game/story/story_data.gd")
const VF := preload("res://game/vehicles/vehicle_fx.gd")
const FX := preload("res://game/systems/rail_ride_fx.gd")
const World := preload("res://game/levels/hafen_world.gd")
const Wind := preload("res://game/levels/hafen_wind.gd")
const Actor := preload("res://game/levels/hafen_actor.gd")
const Boat := preload("res://game/levels/hafen_boat.gd")
const RailRide := preload("res://game/systems/rail_ride.gd")
const Bot := preload("res://game/levels/overwatch_bot.gd")
const SquadOrders := preload("res://game/squad/squad_orders.gd")
const Companion := preload("res://game/squad/companion.gd")
const Markers := preload("res://game/levels/hafen_markers.gd")
const Models := preload("res://game/levels/hafen_models.gd")
const HELI_SCENE := "res://game/vehicles/helicopter.tscn"

const SNIPER_DMG := 45.0
const LENA_SPEED := 3.2
const LENA_PHASE_START: Array[Vector3] = [Vector3(2, 0, -20), Vector3(2, 0, -72), Vector3(2, 0, -140)]
const AISLE_FACE := Vector3(2.0, 1.0, -150.0)
const BOAT_PATH: Array[Vector3] = [
	Vector3(55, -2, -180), Vector3(62, -2, -260), Vector3(78, -2, -340), Vector3(95, -2, -430),
	Vector3(88, -2, -520), Vector3(90, -2, -590), Vector3(92, -2, -660), Vector3(85, -2, -760),
	Vector3(95, -2, -860), Vector3(130, -2, -940), Vector3(210, -2, -1000), Vector3(320, -2, -1030),
	Vector3(430, -2, -1040), Vector3(505, -2, -1045)]

# Farben (frei erfunden, keine realen Abzeichen)
const C_GARDE := [Color(0.42, 0.43, 0.44), Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13)]
const C_WACHE := [Color(0.1, 0.14, 0.25), Color(0.16, 0.17, 0.2), Color(0.85, 0.72, 0.1)]
const C_LENA := [Color(0.16, 0.18, 0.2), Color(0.25, 0.24, 0.22), Color(0.45, 0.7, 0.95)]
const C_WEBER := [Color(0.1, 0.1, 0.12), Color(0.18, 0.17, 0.16), Color(0.1, 0.1, 0.12)]

var phase: int = 0
var _time: float = 0.0
var _phase_t: float = 0.0
var _failed: String = ""
var _radio_end: float = 0.0
var _fail_count: int = 0
var _done: bool = false
var _phase_nodes: Array[Node] = []
var _shooters: Array = []            ## {a, cd, mode: "lena"/"ride"}
var _snipers: Dictionary = {}
var _glint_tex: Texture2D
var _wind: Node3D
var _weather: Node
var _freighter: Node3D
var _model_refs: Array = []   ## Boots-Modelle (PackedScene) bleiben ab dem Vorwaermen geladen
var _bot: RefCounted = null
var _bot_on: bool = false
var _ready_ok: bool = false
var _targets: Array = []             ## Ziele fuer den Scharfschuetzen-Bot (Teil A)
var lena: Node3D = null
var ride: Node3D = null
var _ride_spray: Array[GPUParticles3D] = []
var _weber_boat: Node3D = null
var _brandt: Node3D = null
var _brandt_t: float = 0.0
var _heli: Node3D = null
var _heli_t: float = 0.0
var _weber_hits: int = 0
var _lena_hits: int = 0
var _lena_hit_cd: float = 0.0
var _wb_hits: int = 0
var _weber_gone: bool = false
var _fade_rect: ColorRect = null
var _s_b1: float = 0.0
var _s_bridge: float = 0.0
var _s_mouth: float = 0.0
var _squad: Node = null            ## Squad-Befehle light (game/squad/), nur Teil A
var _lena_c: RefCounted = null     ## Lenas Befehls-Zustand; ohne Befehl laeuft sie ihre Route wie bisher
var _markers: CanvasLayer = null   ## HUD-Zielmarker (rot = Pflichtziel, blau = nicht schiessen)
var _gk_said: float = 0.0

func _init() -> void:
	level_name = "hafen"
	spawn_player = true
	spawn_enemies = false
	default_faction = "reich"
	ambient_artillery = false
	end_z = -1045.0
	fog_density = 0.0016
	build_seed = 1206
	_wave_count = 7

func get_level_info() -> Dictionary:
	return {"name": level_name, "title": "Kräne", "waves": 7, "end_position": [505.0, -2.0, -1045.0], "waypoints": []}

func is_level_ready() -> bool:
	return _ready_done

# ================================================================== Aufbau

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.012, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.03, 0.05, 0.1)
	sm.sky_horizon_color = Color(0.24, 0.17, 0.13)
	sm.ground_bottom_color = Color(0.01, 0.01, 0.015)
	sm.ground_horizon_color = Color(0.2, 0.15, 0.12)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.31, 0.46)
	env.ambient_light_energy = 1.15
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.6
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	# Sicht: Scharfschuetzen-Karte (Ziele 150-400 m). Frueher Tiefennebel 0.0035 + volumetrisch 0.008 mit
	# hellem Albedo -> die von Kran-Flutlicht/Mastlampen angestrahlte Nebelwand direkt vor der Kamera
	# ueberstrahlte alles (Sicht ~20-30 m). Jetzt: klare Luft im Nahbereich, Dunst erst in der Ferne
	# (300 m ~76 % Durchsicht, Stadtkulisse ab 900 m deutlich verhangen), duenner Lichtdunst nur um Lampen.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.055, 0.06, 0.075)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0009
	env.fog_sky_affect = 0.6
	env.fog_aerial_perspective = 0.2
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0016
	env.volumetric_fog_albedo = Color(0.55, 0.56, 0.6)
	env.volumetric_fog_emission = Color(0.0015, 0.0015, 0.002)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.12
	env.volumetric_fog_ambient_inject = 0.04
	env.volumetric_fog_sky_affect = 0.0
	# Grafikstufe "Volumetrischer Nebel: Aus": Ersatz-Distanznebel nur leicht anheben (graphics.gd)
	env.set_meta(&"gfx_fog_fallback_k", 0.8)
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.9
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	we.camera_attributes = VfxEnv.make_camera_attributes()
	add_child(we)
	var moon := DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.55
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.25
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 120.0
	var dir := Vector3(0.35, -0.6, -0.7).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")

func _build_ground() -> void:
	_wind = Wind.new()
	_wind.name = "Wind"
	add_child(_wind)

func _build_street() -> void:
	var out: Dictionary = World.build(self, world, _wind, rng)
	_freighter = out.get("freighter")

func _build_props() -> void:
	pass

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, World.KERNER_SPOT + Vector3(0, 0.1, 0), "player_spawn")
	ps.name = "PlayerSpawn"

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	pass

func _build_atmosphere() -> void:
	var w := Weather.new()
	w.name = "Weather"
	w.rain_strength = 0.38
	w.lightning = true
	w.lightning_interval = Vector2(45.0, 90.0)
	w.flash_energy = 1.4
	w.rain_volume_db = -8.0
	add_child(w)
	var rm: Variant = w.get("_rain_mat")
	if rm is ShaderMaterial:
		(rm as ShaderMaterial).set_shader_parameter("brightness", 0.24)   # feine, dezente Schlieren statt Vorhang
	_weather = w
	_wind.set("weather", w)
	var amb := AudioStreamPlayer.new()
	amb.name = "AmbHarbour"
	var st: Variant = load("res://assets/sfx/hafen_amb_harbour.ogg") if ResourceLoader.exists("res://assets/sfx/hafen_amb_harbour.ogg") else null
	if st is AudioStream:
		amb.stream = st
		amb.volume_db = -10.0
		amb.bus = &"SFX"
		amb.autoplay = true
		if st is AudioStreamOggVorbis:
			(st as AudioStreamOggVorbis).loop = true
		add_child(amb)

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
	nm.filter_baking_aabb = AABB(Vector3(-12.0, -1.0, -260.0), Vector3(24.0, 5.0, 250.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)

func _ready() -> void:
	await super._ready()
	if not is_inside_tree():
		return
	_glint_tex = _make_glint_tex()
	if player != null:
		player.call("give_weapon", "g28", 10, 60)
		if player.has_method("set_view"):
			player.call("set_view", 0.0, -6.0)
	Events.player_respawned.connect(_on_player_respawned)
	_bot_on = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	if _bot_on and player != null:
		_bot = Bot.new()
		_bot.call("setup", self, player)
	_markers = Markers.new()
	_markers.name = "HafenMarkers"
	add_child(_markers)
	_spawn_brandt()
	_setup_squad()
	_ready_ok = true
	_run()

# ================================================================== Ablauf-Helfer

func _say(speaker: String, text: String, dur: float = 0.0) -> void:
	Events.story_radio.emit(speaker, text, dur)
	var d := dur if dur > 0.0 else clampf(1.6 + 0.055 * text.length(), 2.5, 8.0)
	_radio_end = maxf(_radio_end, _time) + d + 0.65

func _radio_wait(max_wait: float = 12.0) -> bool:
	return await _sleep(clampf(_radio_end - _time, 0.0, max_wait))

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
	_shooters.clear()
	for key in _snipers.keys():
		var g: Node = _snipers[key]["glint"]
		if is_instance_valid(g):
			g.queue_free()
	_snipers.clear()
	_targets.clear()
	_heli = null
	if _markers != null:
		_markers.call("clear")
	if ride != null and is_instance_valid(ride):
		ride.set("hud_hint", "")
	_mark_persistent()

## Wartet, bis alle Pflichtziele tot sind. Brandt loest nichts mehr selbst: gestaffelte Hinweise (Funk mit
## Richtung/Entfernung, Marker blinken), kurz vor fail_t eine Warnung, danach Abbruch und Neustart der Phase.
func _clear(req: Array, fail_t: float = 150.0) -> bool:
	var t0 := _time
	var step := 0
	var marks: Array[float] = [fail_t * 0.17, fail_t * 0.37, fail_t - 30.0]
	while not _all_dead(req):
		await get_tree().process_frame
		if _failed != "" or not is_inside_tree():
			return false
		var el := _time - t0
		if step < marks.size() and el >= marks[step]:
			_hint(req, step)
			step += 1
		if el >= fail_t:
			var names: Array[String] = []
			for n in req:
				if _alive(n):
					names.append(str((n as Node).name))
			print("[hafen] Phase %d: Zeitlimit, Abbruch (%s)" % [phase, ", ".join(names)])
			if phase <= 3:
				_say(SD.LENA, "Ich bin hier festgenagelt, Jonas. So kommen wir nicht durch!")
			else:
				_say(SD.LENA, "Er ist weg! Wir haben ihn verloren!")
			_fail("zeit")
			return false
	return true

## Hinweis-Stufe 0: Funkspruch zum naechsten lebenden Ziel; 1: Marker-Hinweis (Boot: Zeitdruck); 2: letzte Warnung.
func _hint(req: Array, step: int) -> void:
	var left: Array = req.filter(func(n: Variant) -> bool: return _alive(n))
	if left.is_empty():
		return
	if _markers != null:
		_markers.call("pulse", 6.0)
	match step:
		0:
			var co: Variant = (left[0] as Node).get_meta("callout", null)
			if co is Array:
				_say(str(co[0]), str(co[1]))
		1:
			if phase >= 4:
				_say(SD.LENA, "Er zieht davon, Kerner! Mach den Weg frei, sonst ist er weg!")
			else:
				_say(SD.BRANDT, "Folg den roten Markierungen, Kerner. Die zeigen dir, wer noch steht.")
			var co2: Variant = (left[0] as Node).get_meta("callout", null)
			if co2 is Array and phase <= 3:
				_say(str(co2[0]), str(co2[1]))
		2:
			if phase >= 4:
				_say(SD.LENA, "Noch eine halbe Minute, dann ist Weber außer Sicht!")
			else:
				_say(SD.LENA, "Jonas, ich kann hier nicht ewig liegen. Noch eine halbe Minute, dann brechen wir ab!")

## HUD-Marker setzen; callout = [Sprecher, Text] fuer die Hinweis-Stufen.
func _mark(n: Node3D, label: String, col: Color = Markers.C_RED, off: Vector3 = Vector3(0, 1.9, 0), callout: Array = []) -> void:
	if n == null:
		return
	if not callout.is_empty():
		n.set_meta("callout", callout)
	if _markers != null:
		_markers.call("add", n, label, col, off)

## Marker, die ueber Phasen-Neustarts bestehen bleiben (Lena, Webers Boot).
func _mark_persistent() -> void:
	if lena != null and is_instance_valid(lena):
		_mark(lena, "LENA", Markers.C_BLUE, Vector3(0, 1.95, 0))
	if _weber_boat != null and is_instance_valid(_weber_boat):
		_mark(_weber_boat, "WEBER – NICHT SCHIESSEN", Markers.C_BLUE)

func _make_actor(role: String, etype: String, pos: Vector3, cols: Array, yaw: float, props: Dictionary = {}) -> Node3D:
	var a: CharacterBody3D = Actor.new()
	a.set("role", role)
	a.set("enemy_type", etype)
	a.set("level_ref", self)
	a.set_meta("faction", "garde" if role == "enemy" else "resistance")
	a.set("color_primary", cols[0])
	a.set("color_secondary", cols[1])
	a.set("color_armband", cols[2])
	a.set("max_health", 60.0)
	a.set("damage_per_hit", 0.0)
	for k: String in props:
		a.set(k, props[k])
	a.name = "%s_%s_%d" % [role, etype, get_child_count()]
	add_child(a)
	a.global_position = pos + Vector3(0, 0.05, 0)
	a.rotation.y = deg_to_rad(yaw)
	return a

func _enemy(etype: String, pos: Vector3, cols: Array, yaw: float, mode: String = "lena", props: Dictionary = {}) -> Node3D:
	var a := _make_actor("enemy", etype, pos, cols, yaw, props)
	_phase_nodes.append(a)
	_shooters.append({"a": a, "cd": randf_range(1.0, 2.5), "mode": mode})
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

## Lena laeuft eine Wegpunktliste ab (geradeaus, ohne Navmesh) und geht am Ende in die Hocke.
func _lena_route(pts: Array, speed: float = LENA_SPEED) -> bool:
	if lena == null or not is_instance_valid(lena):
		return true
	if not await _lena_orders_wait():
		return false
	lena.set("crouch", false)
	for p: Vector3 in pts:
		if not await _lena_leg(p, speed, 30.0, true):
			return false
	if lena != null and is_instance_valid(lena):
		lena.set("crouch", true)
	return true

## Ein Routenabschnitt. Ohne Squad-Befehl exakt wie bisher (walk_to, warten bis angekommen, Notnagel).
## Mit Befehl (Halt/Dort hin) wartet die Route, bis Kerner "Folgen" gibt (oder das Halten ausläuft);
## Lena kehrt dann zu ihrem Ausgangspunkt zurück und läuft den Abschnitt weiter.
func _lena_leg(p: Vector3, speed: float, timeout: float, snap: bool) -> bool:
	while true:
		if not await _lena_orders_wait():
			return false
		if lena == null or not is_instance_valid(lena):
			return true
		lena.call("walk_to", p, speed, false)
		var ok: bool = await _until(func() -> bool: return lena == null or not is_instance_valid(lena) or bool(lena.call("arrived")) or not _lena_free(), timeout)
		if not ok:
			return false
		if lena == null or not is_instance_valid(lena):
			return true
		if not _lena_free():
			continue
		if snap and not bool(lena.call("arrived")):
			lena.global_position = p + Vector3(0, 0.05, 0)   # Notnagel: haengt fest
		return true
	return true

func _lena_free() -> bool:
	return _lena_c == null or bool(_lena_c.call("is_following"))

## Wartet, solange Lena einen Squad-Befehl ausführt (sofort fertig ohne Befehl).
func _lena_orders_wait() -> bool:
	if _lena_free():
		return true
	var ok: bool = await _until(func() -> bool: return lena == null or not is_instance_valid(lena) or _lena_free(), -1.0)
	if ok and lena != null and is_instance_valid(lena):
		lena.set("crouch", false)
	return ok

# ------------------------------------------------------------------ Squad-Befehle light (Teil A)

func _setup_squad() -> void:
	_squad = SquadOrders.new()
	add_child(_squad)
	var l: Dictionary = _squad.get("lines")
	l["follow"] = ["Okay, ich geh weiter.", "Verstanden, zurück auf meine Route.", "Weiter geht's."]
	l["hold"] = ["Ich warte hier, bis du was sagst.", "Verstanden, ich bleib in Deckung.", "Halte Position."]
	l["auto_follow"] = ["Ich kann hier nicht ewig hocken, Jonas. Ich geh weiter.", "Lange warten geht nicht. Ich lauf weiter."]

func _sq_move_filter(pos: Vector3) -> Variant:
	if lena == null or not is_instance_valid(lena):
		return null
	var map := get_world_3d().navigation_map
	var sp := NavigationServer3D.map_get_closest_point(map, pos)
	if Vector2(sp.x - pos.x, sp.z - pos.z).length() > 1.5 or absf(sp.y - pos.y) > 1.5:
		return null
	return sp

func _lena_pos() -> Vector3:
	return lena.global_position if lena != null and is_instance_valid(lena) else Vector3(2, 0, -100)

# ================================================================== Hauptablauf

func _run() -> void:
	await get_tree().process_frame
	var start := clampi(int(Game.arg("phase", 1)), 1, 7)
	if start <= 3:
		_spawn_lena(LENA_PHASE_START[start - 1])
		if start == 1:
			await _intro()
	else:
		_start_boat(start)
	phase = start
	while phase <= 6 and is_inside_tree():
		_failed = ""
		_phase_t = 0.0
		await _radio_wait(8.0)
		if phase == 4 and ride == null:
			await _transition()
		var ok: bool = await _phase(phase)
		if not is_inside_tree():
			return
		print("[hafen] Phase %d %s nach %.1f s (gesamt %.1f s)" % [phase, "geschafft" if ok and _failed == "" else "FEHLER " + _failed, _phase_t, _time])
		if ok and _failed == "":
			_checkpoint("cp_phase%d" % phase)
			phase += 1
		elif phase <= 3:
			await _retry_foot()
		else:
			await _retry_boat()
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
	_say(SD.BRANDT, "Hier Brandt. Ich kreise über der Warnow, Lichter aus. Offiziell ist das ein Werkstattflug.")
	_say(SD.KERNER, "Stellung auf dem Portalkran. Ich hab die ganze Hauptgasse im Glas.")
	_say(SD.LENA, "Ich geh unten durch die Gasse. Weber soll heute Nacht an Liegeplatz sieben ablegen, mit der Akte Nordlicht.")
	_say(SD.BRANDT, "Seewind aus Westsüd, böig. Die Wimpel an den Lichtmasten zeigen dir, wohin er drückt.")
	_obj("Lena durch das Containerlager decken")
	await _radio_wait(14.0)

func _retry_foot() -> void:
	_fail_count += 1
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	_say(SD.BRANDT, "Abbruch! Lena, zurück in die letzte Deckung. Wir setzen neu an.")
	await get_tree().create_timer(2.5, false).timeout
	_clear_phase_nodes()
	_weber_hits = 0
	_lena_hits = 0
	_weber_gone = false
	if lena == null or not is_instance_valid(lena):
		_spawn_lena(LENA_PHASE_START[phase - 1])
	else:
		if _lena_c != null:
			_lena_c.call("reset")
		lena.global_position = LENA_PHASE_START[phase - 1] + Vector3(0, 0.05, 0)
		lena.call("walk_to", LENA_PHASE_START[phase - 1], 1.0, false)
		lena.set("crouch", true)
	if player != null and is_instance_valid(player) and bool(player.call("is_alive")):
		if player.global_position.distance_to(World.KERNER_SPOT) > 3.0:
			player.global_position = World.KERNER_SPOT + Vector3(0, 0.1, 0)
	await get_tree().create_timer(1.0, false).timeout

func _retry_boat() -> void:
	_fail_count += 1
	get_tree().call_group(&"story_ui", &"interrupt")
	_radio_end = _time
	var timeout := _failed == "zeit"
	if not timeout:
		_say(SD.LENA, "Wir laufen voll! Brandt, zieh uns raus!")
		Events.player_died.emit()
	ride.set("input_enabled", false)
	ride.set("fire_held", false)
	await get_tree().create_timer(2.5, false).timeout
	_clear_phase_nodes()
	ride.call("clear_events")
	ride.call("refit")
	ride.call("reset_to", _phase_s(phase))
	# Nach mehreren Fehlschlaegen: Boot faellt nicht mehr ganz aus
	ride.set("invulnerable", _fail_count >= 3)
	ride.set("input_enabled", true)
	_wb_hits = 0
	if _weber_boat != null and is_instance_valid(_weber_boat):
		_weber_boat.set("offset_s", 110.0)
	if timeout:
		_say(SD.BRANDT, "Zurück auf Position, wir setzen neu an. Diesmal schneller, Kerner.")
	else:
		_say(SD.BRANDT, "Neues Boot, gleicher Kurs. Ich bleib über euch.")
	await get_tree().create_timer(1.0, false).timeout

# ------------------------------------------------------------------ Teil A: Overwatch vom Kran

func _spawn_lena(pos: Vector3) -> void:
	lena = _make_actor("friendly", "rifleman", pos, C_LENA, 180.0, {"invulnerable": true})
	lena.name = "Lena"
	lena.set("crouch", true)
	_lena_c = Companion.new()
	_lena_c.set("actor", lena)
	_lena_c.set("move_speed", LENA_SPEED)
	_lena_c.set("use_nav", true)
	_lena_c.set("crouch_on_hold", true)
	_lena_c.set("resume_anchor", true)
	_lena_c.set("hold_timeout", 45.0)
	_lena_c.set("move_timeout", 15.0)
	_lena_c.set("max_move_dist", 16.0)
	_lena_c.set("fire_range", 80.0)
	_lena_c.set("fire_interval", Vector2(1.0, 1.6))
	_lena_c.set("hit_chance", 0.35)
	_lena_c.set("damage", 12.0)
	_lena_c.set("move_filter", _sq_move_filter)
	_lena_c.set("available_cb", func() -> bool: return ride == null and phase >= 1 and phase <= 3 and _failed == "" and not _done)
	if _squad != null:
		_squad.set("companion", _lena_c)
	_mark_persistent()

## A1: Hafenwache am Wachhaeuschen.
func _p1() -> bool:
	if not await _lena_route([Vector3(2, 0, -56)]):
		return false
	lena.set("crouch", false)
	lena.call("walk_to", Vector3(2, 0, -72), LENA_SPEED, false)
	var g1 := _enemy("rifleman", World.HUT + Vector3(1.0, 0, -5.0), C_WACHE, 10.0)
	var g2 := _enemy("rifleman", World.HUT + Vector3(-1.0, 0, -6.5), C_WACHE, 10.0)
	g1.name = "Hafenwache_1"
	g2.name = "Hafenwache_2"
	g1.call("walk_to", Vector3(5, 0, -104), 2.6, false)
	g2.call("walk_to", Vector3(0, 0, -106), 2.6, false)
	_targets = [g1, g2]
	var c1 := [SD.LENA, "Zwei Wachen am Häuschen rechts der Gasse, dreißig Meter vor mir. Von dir aus geradeaus, hundertsiebzig Meter."]
	_mark(g1, "HAFENWACHE", Markers.C_RED, Vector3(0, 1.9, 0), c1)
	_mark(g2, "HAFENWACHE", Markers.C_RED, Vector3(0, 1.9, 0), c1)
	_say(SD.LENA, "Zwei Hafenwachen am Wachhäuschen. Die haben mich gesehen!")
	_say(SD.KERNER, "Ich hab sie. Bleib unten.")
	_obj("Die zwei Hafenwachen ausschalten – Hauptgasse geradeaus, ~170 m (rot markiert)")
	if not await _lena_leg(Vector3(2, 0, -72), LENA_SPEED, 15.0, false):
		return false
	lena.set("crouch", true)
	var ok: bool = await _clear([g1, g2], 150.0)
	if not ok:
		return false
	_say(SD.LENA, "Danke. Weiter zur nächsten Querreihe.")
	return true

## A2: Garde-Jaeger an den Betonsperren + Scharfschuetze am Lichtmast.
func _p2() -> bool:
	if not await _lena_route([Vector3(2, 0, -118)]):
		return false
	lena.set("crouch", false)
	lena.call("walk_to", Vector3(2, 0, -140), LENA_SPEED, false)
	var dests: Array[Vector3] = [Vector3(-1, 0, -159.6), Vector3(5, 0, -163.6), Vector3(1, 0, -169.6)]
	var garde: Array = []
	for i in 3:
		var e := _enemy("rifleman" if i != 1 else "assault", Vector3(-20.0 - i * 2.0, 0, -170.0 - i * 1.2), C_GARDE, 0.0)
		e.name = "GardeJaeger_%d" % (i + 1)
		e.call("walk_to", dests[i], 3.4, false)
		garde.append(e)
	_targets = garde.duplicate()
	for e in garde:
		_mark(e, "GARDE-JÄGER", Markers.C_RED, Vector3(0, 1.9, 0), [SD.LENA, "Die Jäger liegen hinter den Betonsperren, direkt vor mir. Von dir aus geradeaus, gut zweihundert Meter."])
	_say(SD.LENA, "Graue Mäntel an den Betonsperren. Das ist keine Hafenwache, Jonas. Das sind Garde-Jäger.")
	_obj("Die drei Garde-Jäger an den Betonsperren ausschalten (geradeaus, ~220 m)")
	if not await _lena_leg(Vector3(2, 0, -140), LENA_SPEED, 15.0, false):
		return false
	lena.set("crouch", true)
	if not await _sleep(5.0):
		return false
	var m := _spawn_sniper("m", World.MARKSMAN)
	m.name = "GardeScharfschuetze"
	_targets.push_front(m)
	_mark(m, "SCHARFSCHÜTZE", Markers.C_RED, Vector3(0, 1.5, 0), [SD.BRANDT, "Der Scharfschütze liegt auf der Plattform am Lichtmast links der Gasse, gleich hinter den Betonsperren. Zweihundertvierzig Meter."])
	_say(SD.FALK, "Kerner. Sie suchen Weber, ich suche Weber. Bleiben Sie mir aus dem Weg.")
	_say(SD.BRANDT, "Scharfschütze! Lichtmast links der Gasse, direkt hinter den Betonsperren, oben auf der Plattform. Zweihundertvierzig Meter, leicht links von dir.")
	_say(SD.LENA, "Wenn es da oben blitzt, zielt er auf dich. Erst ihn, dann die Jäger!")
	_obj("Scharfschützen auf dem Lichtmast (links, ~240 m, beleuchtete Plattform) und die Garde-Jäger ausschalten")
	var req: Array = garde.duplicate()
	req.append(m)
	var ok: bool = await _clear(req, 150.0)
	if not ok:
		return false
	_say(SD.LENA, "Sperre ist frei. Ich geh außen um die Blöcke.")
	return true

## A3: Weber quert mit Begleitschutz die Querreihe 235 zum Liegeplatz 7.
func _p3() -> bool:
	_weber_gone = false
	if not await _lena_route([Vector3(2, 0, -150), Vector3(7.3, 0, -158), Vector3(7.3, 0, -172), Vector3(2, 0, -180), Vector3(2, 0, -195)]):
		return false
	var esc: Array = []
	var corners: Array[Vector3] = [Vector3(-5, 0, -229), Vector3(9, 0, -229), Vector3(4, 0, -243)]
	for i in 3:
		var e := _enemy("rifleman" if i != 2 else "assault", Vector3(-27.0 - i * 1.5, 0, -233.5 - i * 1.4), C_GARDE, -90.0)
		e.name = "Begleitschutz_%d" % (i + 1)
		e.call("walk_to", corners[i], 4.0, false)
		esc.append(e)
	var w := _make_actor("weber", "officer", Vector3(-25, 0, -235), C_WEBER, -90.0, {"unarmed": true})
	w.name = "Weber"
	_phase_nodes.append(w)
	_targets = esc.duplicate()
	for e in esc:
		_mark(e, "BEGLEITSCHUTZ", Markers.C_RED, Vector3(0, 1.9, 0), [SD.LENA, "Die Begleiter laufen mit Weber quer durch Reihe zweihundertfünfunddreißig, Richtung Kai. Knapp dreihundert Meter von dir."])
	_mark(w, "WEBER – NICHT SCHIESSEN", Markers.C_BLUE)
	_say(SD.LENA, "Da! Querreihe zweihundertfünfunddreißig, von Westen. Das ist Weber!")
	_say(SD.KERNER, "Ich seh ihn. Dunkler Mantel, Aktenkoffer. Die Akte Nordlicht.")
	_say(SD.BRANDT, "Nicht auf Weber schießen! Wir brauchen ihn lebend, und die Akte auch.")
	_say(SD.LENA, "Drei Begleiter um ihn, knapp dreihundert Meter. Leg die Begleiter um, bevor er am Kai ist!")
	_obj("Webers drei Begleiter ausschalten (Querreihe 235, ~300 m) – Weber (blau) nicht treffen")
	_weber_run(w)
	var ok: bool = await _clear(esc, 150.0)
	if not ok:
		return false
	if not await _until(func() -> bool: return _weber_gone, 25.0):
		return false
	_say(SD.BRANDT, "Runter zum Wasser, beide. Am Zollsteg liegt ein Schnellboot. Ich bleib über euch.")
	return true

func _weber_run(w: Node3D) -> void:
	await get_tree().create_timer(2.5, false).timeout
	if not is_instance_valid(w):
		return
	w.call("walk_to", Vector3(2, 0, -235), 3.6, false)
	while is_instance_valid(w) and not bool(w.call("arrived")):
		await get_tree().process_frame
	if not is_instance_valid(w):
		return
	w.call("walk_to", Vector3(39, 0, -236), 3.6, false)
	while is_instance_valid(w) and not bool(w.call("arrived")):
		await get_tree().process_frame
	if not is_instance_valid(w):
		return
	_say(SD.LENA, "Er springt in ein Boot! Liegeplatz sieben!")
	var b := _make_boat("weber", World.BERTH7 + Vector3(2.5, 0, 0), null)
	b.set("free_target", Vector3(62, -2, -320))
	b.set("free_speed", 9.0)
	_mark(b, "WEBER", Markers.C_BLUE)
	w.queue_free()
	_weber_gone = true

func on_weber_hit() -> void:
	if phase != 3 or _failed != "" or _done:
		return
	_weber_hits += 1
	if _weber_hits == 1:
		_say(SD.BRANDT, "Treffer auf Weber! Feuer einstellen, verdammt. Den brauchen wir lebend!")
	else:
		_say(SD.BRANDT, "Weber ist getroffen. Das war's, Abbruch!")
		_fail("weber")

func on_friendly_hit(who: Node) -> void:
	if who != lena or _failed != "" or _done or _lena_hit_cd > 0.0:
		return
	_lena_hit_cd = 0.6
	_lena_hits += 1
	if _lena_hits == 1:
		_say(SD.LENA, "Jonas! Das war ich! Schau durchs Glas, bevor du abdrückst!")
	else:
		_say(SD.LENA, "Ich bin getroffen! Abbruch!")
		_fail("lena")

func on_friendly_died(_who: Node) -> void:
	pass

func on_enemy_wounded(_who: Node) -> void:
	pass

func _on_player_respawned() -> void:
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		s["stage"] = "hide"
		s["t"] = 4.0
		s["glow"] = 0.0
	if player != null and is_instance_valid(player) and phase <= 3 and player.has_method("give_weapon"):
		player.call("give_weapon", "g28", 10, 60)

# --- Scharfschuetzen-Bot (Teil A)

func bot_drives_player() -> bool:
	return _bot_on and _ready_ok and phase <= 3 and ride == null

func bot_task() -> Dictionary:
	var t: Array = []
	for n in _targets:
		if _alive(n):
			t.append(n)
	return {"kind": "snipe", "pos": World.KERNER_SPOT, "targets": t, "face": AISLE_FACE, "preaim": true}

func sniper_wind() -> Vector3:
	if _wind == null:
		return Vector3.ZERO
	return _wind.call("current")

func _cam_pos() -> Vector3:
	if player == null or not is_instance_valid(player):
		return Vector3.ZERO
	var cam: Camera3D = player.call("get_camera")
	return cam.global_position if cam != null else player.global_position + Vector3.UP * 1.6

# --- Gegenscharfschuetze (Glint/Schuss-Zyklus wie in "Kaltes Auge")

func _spawn_sniper(key: String, pos: Vector3) -> Node3D:
	var a := _make_actor("enemy", "marksman", pos, C_GARDE, 0.0, {"gravity": 0.0})
	_phase_nodes.append(a)
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
	add_child(g)
	_snipers[key] = {"a": a, "stage": "hide", "t": 7.0, "shots": 0, "glint": g, "glow": 0.0}
	return a

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
			var v: float = clampf(core + halo + star, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 0.96, 0.85, v))
	return ImageTexture.create_from_image(img)

func _tick_snipers(delta: float) -> void:
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		var a: Node3D = s["a"] if is_instance_valid(s["a"]) else null
		var g: MeshInstance3D = s["glint"]
		if a == null or not _alive(a) or phase != 2:
			g.visible = false
			continue
		s["t"] = float(s["t"]) - delta
		match str(s["stage"]):
			"hide":
				a.set("crouch", true)
				a.set("aiming", false)
				s["glow"] = maxf(0.0, float(s["glow"]) - delta * 3.0)
				if float(s["t"]) <= 0.0:
					s["stage"] = "aim"
					s["t"] = 3.0
					a.set("crouch", false)
					a.set("aiming", true)
					if player != null and is_instance_valid(player):
						VFX.play_sfx_3d("overwatch_glint", player.global_position + Vector3(0, 1.5, -4.0), -12.0, 8.0, 40.0)
			"aim":
				a.set("aim_point", _cam_pos())
				s["glow"] = minf(1.0, float(s["glow"]) + delta * 2.5)
				if float(s["t"]) <= 0.0:
					_sniper_shot(s)
					s["stage"] = "hide"
					s["t"] = rng.randf_range(2.6, 3.4)

func _sniper_shot(s: Dictionary) -> void:
	var a: Node3D = s["a"]
	if player == null or not is_instance_valid(player) or not bool(player.call("is_alive")):
		return
	var from: Vector3 = a.call("scope_pos")
	var cam := _cam_pos()
	var shots: int = int(s["shots"])
	s["shots"] = shots + 1
	a.call("puppet_fire", cam, 0.0)
	var dist: float = from.distance_to(cam)
	var dir := (from - cam).normalized()
	get_tree().create_timer(dist / 343.0).timeout.connect(func() -> void:
		if player != null and is_instance_valid(player):
			VFX.play_sfx_3d("overwatch_dmr_fire", player.global_position + dir * 25.0 + Vector3.UP * 2.0, -4.0, 14.0, 80.0))
	var tof: float = dist / 800.0
	var ex: Array[RID] = [a.get_rid()]
	if shots == 0:
		var miss := cam + Vector3(rng.randf_range(-1.2, 1.2), -0.9, 0.0) + (cam - from).normalized() * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(from, miss + (miss - from).normalized() * 6.0, 1, ex)
		var r2: Dictionary = get_world_3d().direct_space_state.intersect_ray(q2)
		get_tree().create_timer(tof).timeout.connect(func() -> void:
			VFX.play_whiz_along(from, cam + (cam - from).normalized() * 4.0, 4.0)
			if not r2.is_empty():
				VFX.spawn_impact(r2.position, r2.normal, str((r2.collider as Node).get_meta("surface", "metal")) if r2.collider is Node else "metal"))
		_say(SD.LENA, "Der Schuss kam vom Lichtmast! Wenn es dort oben blitzt, geh in Deckung!")
		return
	var q := PhysicsRayQueryParameters3D.create(from, cam, 1, ex)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		get_tree().create_timer(tof).timeout.connect(func() -> void:
			if player != null and is_instance_valid(player) and bool(player.call("is_alive")) and phase == 2:
				player.call("take_damage", SNIPER_DMG, a if is_instance_valid(a) else null, cam, (cam - from).normalized()))
	else:
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		get_tree().create_timer(tof).timeout.connect(func() -> void:
			VFX.spawn_impact(hp, hn, "metal"))

func _update_glints() -> void:
	var fov: float = 70.0
	if player != null and is_instance_valid(player):
		var cam: Camera3D = player.call("get_camera")
		if cam != null:
			fov = cam.fov
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		var g: MeshInstance3D = s["glint"]
		var a: Node3D = s["a"] if is_instance_valid(s["a"]) else null
		if a == null or not _alive(a):
			g.visible = false
			continue
		var glow: float = float(s["glow"])
		g.visible = glow > 0.01
		if not g.visible:
			continue
		var sp: Vector3 = a.call("scope_pos")
		g.global_position = sp
		var flick: float = 0.75 + 0.25 * sin(_time * 23.0) * sin(_time * 7.0)
		var gd: float = _cam_pos().distance_to(sp)
		g.scale = Vector3.ONE * (0.035 * gd * tan(deg_to_rad(fov * 0.5))) * (0.6 + 0.4 * glow)
		(g.material_override as StandardMaterial3D).albedo_color.a = glow * flick

# --- Kosmetisches Feuer der Gegner (auf Lena) bzw. echtes Streufeuer aufs Boot

func _tick_shooters(delta: float) -> void:
	for s: Dictionary in _shooters:
		var a: Node3D = s["a"] if is_instance_valid(s["a"]) else null
		if a == null or not _alive(a):
			continue
		var tgt: Vector3
		if str(s["mode"]) == "lena":
			if lena == null or not is_instance_valid(lena):
				continue
			tgt = lena.global_position + Vector3.UP * 1.0
		else:
			if ride == null or not is_instance_valid(ride) or not bool(ride.call("is_alive")):
				continue
			tgt = ride.global_position + Vector3.UP * 1.4
		if not bool(a.call("arrived")):
			continue
		a.set("aiming", true)
		a.set("aim_point", tgt)
		s["cd"] = float(s["cd"]) - delta
		if float(s["cd"]) > 0.0:
			continue
		s["cd"] = rng.randf_range(1.6, 2.8)
		var mz: Vector3 = a.call("muzzle_pos")
		if mz.distance_to(tgt) > 260.0:
			continue
		a.call("puppet_fire", tgt, 1.6)
		if str(s["mode"]) == "ride" and rng.randf() < 0.3:
			var ex: Array[RID] = [a.get_rid(), ride.get_rid()]
			var q := PhysicsRayQueryParameters3D.create(mz, tgt, 1, ex)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				ride.call("take_damage", 12.0, a, tgt, (mz - tgt).normalized())

# ------------------------------------------------------------------ Uebergang: Boot

func _transition() -> void:
	_fade(1.0, 1.2)
	await get_tree().create_timer(1.3, false).timeout
	_start_boat(4)
	_fade(0.0, 1.5)
	_say(SD.LENA, "Ich fahre. Kerner, nimm das MG am Bug.")
	_say(SD.BRANDT, "Weber hält auf die Warnow zu. Die Garde hat Boote im Becken, Falk will ihn auch.")
	_say(SD.WEBER, "Kerner? Ihr seid hartnäckig. Aber Nordlicht ist größer als ihr alle.")
	await _radio_wait(6.0)

func _start_boat(start: int) -> void:
	_clear_phase_nodes()
	if lena != null and is_instance_valid(lena):
		lena.queue_free()
	lena = null
	_lena_c = null
	if _squad != null:
		_squad.set("companion", null)
	if player != null and is_instance_valid(player) and player != ride:
		player.remove_from_group("player")
		player.remove_from_group("damageable")
		player.queue_free()
	player = null
	ride = RailRide.new()
	ride.name = "Zollboot"
	ride.call("configure", {"vehicle_name": "Zollboot", "cruise_speed": 22.0, "accel": 6.0, "decel": 6.0,
		"mount_offset": Vector3(0, 1.75, -2.3), "eye_offset": Vector3(0, 0.42, 0.85),
		"rock_roll_deg": 1.2, "rock_pitch_deg": 0.7, "bob_amp": 0.07, "cam_stabilize": 0.65,
		"max_integrity": 160.0, "engine_sfx": "hafen_boat_engine", "water_sfx": "hafen_water_hull",
		"weapon": {"name": "MG5"}})
	ride.set("invulnerable", _fail_count >= 3)
	add_child(ride)
	ride.call("add_hull_box", Vector3(0, 0.6, 0.3), Vector3(2.9, 1.6, 9.0))
	_build_boat_model(ride.get("model"))
	_ride_spray = FX.make_boat_spray(ride, Vector3(0, 0.15, -3.8), Vector3(0, 0.15, 3.9), 1.5)
	ride.call("set_path", BOAT_PATH)
	ride.connect("destroyed", func() -> void: _fail("boot"))
	_s_b1 = float(ride.call("s_nearest", Vector3(95, -2, -430)))
	_s_bridge = float(ride.call("s_nearest", Vector3(90, -2, World.BRIDGE_Z)))
	_s_mouth = float(ride.call("s_nearest", Vector3(210, -2, -1000)))
	ride.call("reset_to", _phase_s(start))
	player = ride
	_weber_boat = _make_boat("weber", Vector3.ZERO, ride, false)
	_weber_boat.set("offset_s", 110.0)
	_weber_boat.set("target_offset", 110.0)
	_weber_boat.set("approach_rate", 1.5)
	_weber_boat.set("lateral", 0.0)
	_weber_boat.set("weave_amp", 3.0)
	(ride.get("avoid_nodes") as Array).append(_weber_boat)
	_mark_persistent()
	_checkpoint("cp_boot")
	if _brandt != null and is_instance_valid(_brandt):
		_brandt.call("hover_at", ride.global_position + Vector3(-30, 35, 30))

## Halt-Bedingung fuer RailRide: haelt, bis die Phase release_stop() ruft (ein leeres Callable gibt sofort frei).
func _hold() -> bool:
	return false

## Gibt den aktuellen Halt frei und verwirft noch nicht erreichte Halte (sind die Ziele schon vor dem Halt
## erledigt, darf das Boot dort nicht mehr stehen bleiben).
func _drop_stops() -> void:
	ride.call("release_stop")
	for st: Dictionary in (ride.get("_stops") as Array):
		st["state"] = 2

func _phase_s(p: int) -> float:
	match p:
		5: return _s_b1
		6: return _s_bridge + 30.0
		7: return _s_mouth
	return 0.0

## Steuerstand im Zollboot-Modell (RIB, Mittelkonsole): Lena steht hinter der Konsole, Deckhoehe (Modell-Lokal).
const ZOLL_HELM := Vector3(0.0, 0.42, 1.75)

func _build_boat_model(root: Node3D) -> void:
	if Models.attach(root, "zollboot", 9.0) != null:
		_helm_figure(root, ZOLL_HELM)
		var nav_r0 := VF.mat("hf_nav_r", Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0.1, 0.1), 4.0)
		var nav_g0 := VF.mat("hf_nav_g", Color(0.1, 1, 0.2), 0.4, 0.0, Color(0.1, 1, 0.2), 4.0)
		VF.mesh_node(root, VF.box(Vector3(0.08, 0.08, 0.08)), nav_r0, Vector3(-1.05, 1.05, -2.6))
		VF.mesh_node(root, VF.box(Vector3(0.08, 0.08, 0.08)), nav_g0, Vector3(1.05, 1.05, -2.6))
		return
	var hull := VF.mat("hf_zoll_hull", Color(0.1, 0.16, 0.3), 0.5, 0.2)
	var stripe := VF.mat("hf_zoll_stripe", Color(0.85, 0.85, 0.82), 0.5, 0.1)
	var dark := VF.mat("hf_zoll_dark", Color(0.08, 0.08, 0.09), 0.7, 0.3)
	var fig := VF.mat("hf_lena", Color(0.16, 0.18, 0.2), 0.85, 0.0)
	VF.mesh_node(root, VF.box(Vector3(2.8, 1.0, 7.0)), hull, Vector3(0, 0.3, 0.5))
	VF.mesh_node(root, VF.prism(Vector3(2.8, 2.6, 1.0), 0.5), hull, Vector3(0, 0.3, -4.3), Vector3(-90, 0, 0))
	VF.mesh_node(root, VF.box(Vector3(2.84, 0.16, 7.0)), stripe, Vector3(0, 0.55, 0.5))
	VF.mesh_node(root, VF.box(Vector3(2.6, 0.12, 7.6)), dark, Vector3(0, 0.84, 0.2))
	VF.mesh_node(root, VF.box(Vector3(1.3, 1.0, 0.8)), dark, Vector3(0, 1.35, 0.9))
	VF.mesh_node(root, VF.box(Vector3(1.3, 0.5, 0.05)), VF.glass_mat(), Vector3(0, 2.05, 0.52), Vector3(-20, 0, 0))
	VF.mesh_node(root, VF.capsule(0.27, 1.6), fig, Vector3(0.2, 1.7, 1.6))
	VF.mesh_node(root, VF.sphere(0.15), VF.mat("hf_lena_hair", Color(0.08, 0.06, 0.05), 0.8, 0.0), Vector3(0.2, 2.55, 1.6))
	var nav_r := VF.mat("hf_nav_r", Color(1, 0.1, 0.1), 0.4, 0.0, Color(1, 0.1, 0.1), 4.0)
	var nav_g := VF.mat("hf_nav_g", Color(0.1, 1, 0.2), 0.4, 0.0, Color(0.1, 1, 0.2), 4.0)
	VF.mesh_node(root, VF.box(Vector3(0.1, 0.1, 0.1)), nav_r, Vector3(-1.35, 1.0, -2.6))
	VF.mesh_node(root, VF.box(Vector3(0.1, 0.1, 0.1)), nav_g, Vector3(1.35, 1.0, -2.6))

## Lena am Steuer: echte Figur (Gegner-Visual-Pipeline, Lena-Farben), ohne Waffe, Arme vorn am Rad
## (Anschlag-Pose auf einen Punkt knapp vor/unter der Konsole); feet = Fusspunkt auf Deck (Modell-Lokal).
func _helm_figure(root: Node3D, feet: Vector3) -> void:
	Models.puppet(root, "resistance", C_LENA, feet, 0.0,
		{"aim": true, "unarmed": true, "name": "LenaHelm", "aim_local": Vector3(0, 0.2, -6.0)})

## Vom Ladebildschirm (main.gd _warmup) aufgerufen: die Boots-Modelle der Teil-B-Phasen einmal vorab bauen und
## sichtbar rendern (Laden + Shader-Kompilierung beim ersten Boot sonst als Ruckler mitten in der Fahrt).
func warmup_fx(holder: Node3D, at: Vector3, fwd: Vector3) -> void:
	var i := 0
	for slot: String in ["zollboot", "garde_boat", "weber_boat"]:
		var p := Models.path_for(slot)
		if p == "":
			continue
		_model_refs.append(load(p))
		var m := Models.build(slot, 9.0)
		if m == null:
			continue
		holder.add_child(m)
		m.global_position = at + fwd * (14.0 + i * 6.0) + Vector3(0, 0.5, 0)
		i += 1
	# Puppen-Figuren (Garde-Schuetze, Lena am Steuer, Matrosen): Rig + Fraktions-Shader vorab
	for f: Array in [["garde", C_GARDE], ["resistance", C_LENA]]:
		var pp := Models.puppet(holder, str(f[0]), f[1], Vector3.ZERO, 0.0, {"unarmed": true, "name": "WarmPuppe"})
		pp.global_position = at + fwd * (10.0 + i * 2.0)
		i += 1

func _make_boat(role: String, pos: Vector3, rd: Node3D, phase_node: bool = true) -> Node3D:
	var b: AnimatableBody3D = Boat.new()
	b.set("role", role)
	b.set("ride", rd)
	b.set("level_ref", self)
	b.name = "Boot_%s_%d" % [role, get_child_count()]
	if rd != null:
		var s: float = float(rd.get("path_s")) + 120.0
		pos = rd.call("pos_at", s)
	b.position = pos
	add_child(b)
	if phase_node:
		_phase_nodes.append(b)
	return b

func _garde_boat(offset: float, target: float, lateral: float) -> Node3D:
	var b := _make_boat("garde", Vector3.ZERO, ride)
	b.set("offset_s", offset)
	b.set("target_offset", target)
	b.set("lateral", lateral)
	b.set("hit_chance", 0.1)
	_mark(b, "GARDE-BOOT · MG-SCHÜTZE", Markers.C_RED, Vector3(0, 2.6, 0), [SD.LENA, "Garde-Boot %s von uns! Halt auf den Mann am Bug-MG!" % ("rechts" if lateral > 0.0 else "links")])
	b.connect("gunner_killed", func() -> void:
		if _time >= _gk_said:
			_gk_said = _time + 18.0
			_say(SD.LENA, "MG-Schütze ist weg, das Boot dreht ab!"))
	return b

func on_weber_boat_hit() -> void:
	if phase < 4 or _failed != "" or _done:
		return
	_wb_hits += 1
	if _wb_hits == 6:
		_say(SD.BRANDT, "Nicht auf Webers Boot! Wir brauchen ihn und die Akte, nicht ein Wrack.")
	elif _wb_hits >= 30:
		_say(SD.BRANDT, "Ihr versenkt ihn! Abbruch!")
		_fail("weber")

# ------------------------------------------------------------------ Teil B: Verfolgung

## B1: Hafenbecken – zwei Garde-Boote (eins ueberholt von hinten) und Schuetzen am Ostkai.
func _p4() -> bool:
	_obj("Weber (blau) folgen – Garde-Boote stoppen: MG-Schützen am Bug treffen")
	ride.set("hud_hint", "ROT: Garde-Boote (MG-Schütze am Bug = Schwachstelle) + Schützen am Ostkai   ·   BLAU: Weber – nicht schießen")
	var req: Array = []
	req.append(_garde_boat(130.0, 40.0, -11.0))
	_say(SD.LENA, "Garde-Boot vorn links! Halt auf den Mann am Bug-MG, dann ist das Boot erledigt.")
	if not await _sleep(4.0):
		return false
	var ov := _garde_boat(-55.0, 30.0, 10.0)
	ov.set("approach_rate", 7.5)
	req.append(ov)
	_say(SD.LENA, "Von hinten rechts, der überholt uns! Kopf runter!")
	var kai := [SD.BRANDT, "Drei Schützen auf dem Ostkai, rechts von euch zwischen den Kränen. Rund fünfzig Meter."]
	for z in [-350.0, -385.0, -420.0]:
		var e := _enemy("rifleman", Vector3(142.5, 0, z), C_GARDE, 90.0, "ride")
		_mark(e, "KAI-SCHÜTZE", Markers.C_RED, Vector3(0, 1.9, 0), kai)
		req.append(e)
	var s_kai := float(ride.call("s_nearest", Vector3(84, -2, -385)))
	ride.call("add_stop", s_kai, "b1", _hold, -1.0)
	if not await _until(func() -> bool: return float(ride.get("path_s")) >= s_kai - 1.0 or _all_dead(req), 60.0):
		return false
	if not _all_dead(req):
		_say(SD.LENA, "Ich muss hier halten, bis der Kai frei ist. Mach schnell, Weber zieht davon!")
	var ok: bool = await _clear(req, 100.0)
	_drop_stops()
	if not ok:
		return false
	_say(SD.LENA, "Becken ist frei. Weiter zur Hubbrücke!")
	return true

## B2: Hubbruecke – Schuetzen auf dem Deck, ein Boot.
func _p5() -> bool:
	var stop_s := _s_bridge - 45.0
	ride.call("add_stop", stop_s, "bridge", _hold, -1.0)
	var req: Array = []
	var bc := [SD.BRANDT, "Vier Mann oben am Geländer der Hubbrücke, geradeaus und hoch, unter den Lampen. Rund fünfzig Meter."]
	for x in [70.0, 85.0, 100.0, 115.0]:
		var e := _enemy("rifleman", Vector3(x, World.BRIDGE_DECK_Y, World.BRIDGE_Z + 6.2), C_GARDE, 0.0, "ride", {"gravity": 0.0})
		_mark(e, "BRÜCKENSCHÜTZE", Markers.C_RED, Vector3(0, 1.9, 0), bc)
		req.append(e)
		# Arbeitslicht ueber jedem Schuetzen: auf dem dunklen Deck sonst kaum zu sehen
		var sl := SpotLight3D.new()
		sl.light_color = Color(1.0, 0.8, 0.55)
		sl.light_energy = 7.0
		sl.spot_range = 14.0
		sl.spot_angle = 38.0
		sl.shadow_enabled = false
		sl.light_volumetric_fog_energy = 0.5
		sl.position = Vector3(x, World.BRIDGE_DECK_Y + 7.0, World.BRIDGE_Z + 5.0)
		sl.rotation_degrees = Vector3(-90, 0, 0)
		add_child(sl)
		_phase_nodes.append(sl)
	ride.set("hud_hint", "ROT: Schützen oben auf der Hubbrücke (geradeaus, hoch)   ·   BLAU: Weber – nicht schießen")
	_say(SD.BRANDT, "Schützen auf der Hubbrücke! Lena, halt davor an, sonst schießen sie euch von oben in den Kahn.")
	_say(SD.BRANDT, "Vier Mann oben am Brückengeländer, geradeaus und hoch, unter den Lampen. Die musst du von unten rausholen.")
	_obj("Die vier Schützen oben auf der Hubbrücke ausschalten (geradeaus, hoch)")
	if not await _until(func() -> bool: return float(ride.get("path_s")) >= stop_s - 60.0, 40.0):
		return false
	req.append(_garde_boat(-60.0, 25.0, 10.0))
	_say(SD.FALK, "Weber gehört der Garde, Kerner. Drehen Sie um, solange Sie noch ein Boot haben.")
	if not await _until(func() -> bool: return bool(ride.call("is_stopped")) or _all_dead(req), 30.0):
		return false
	var ok: bool = await _clear(req, 100.0)
	_drop_stops()
	if not ok:
		return false
	_say(SD.LENA, "Brücke ist frei. Festhalten!")
	return true

## B3: Warnow-Muendung – Garde-Hubschrauber und zwei Boote.
func _p6() -> bool:
	ride.call("add_stop", _s_mouth, "mouth", _hold, -1.0)
	if not await _until(func() -> bool: return float(ride.get("path_s")) >= _s_mouth - 220.0, 50.0):
		return false
	var req: Array = []
	_heli = _spawn_heli()
	req.append(_heli)
	_mark(_heli, "GARDE-HUBSCHRAUBER", Markers.C_RED, Vector3(0, 2.5, 0), [SD.BRANDT, "Der Garde-Hubschrauber steht rechts vor euch, tief über dem Wasser. Bleib mit dem MG drauf, bis er raucht."])
	req.append(_garde_boat(150.0, 40.0, -12.0))
	req.append(_garde_boat(190.0, 60.0, 11.0))
	ride.set("hud_hint", "ROT: Garde-Hubschrauber (rechts vorn) + zwei Boote   ·   Brandt ist unbewaffnet – das musst du erledigen")
	_say(SD.BRANDT, "Hubschrauber aus Richtung Warnemünde, Garde-Kennung! Der ist schwerer bewaffnet als ich.")
	_say(SD.LENA, "Boote an beiden Seiten! Kerner, erst den Vogel!")
	_say(SD.BRANDT, "Gegen den kann ich nichts ausrichten, Kerner. Den musst du runterholen.")
	_obj("Den Garde-Hubschrauber (rechts vorn) und die zwei Boote ausschalten")
	if not await _until(func() -> bool: return bool(ride.call("is_stopped")) or _all_dead(req), 40.0):
		return false
	var ok: bool = await _clear(req, 110.0)
	_drop_stops()
	if not ok:
		return false
	_say(SD.KERNER, "Hubschrauber ist unten. Wo ist Weber?")
	return true

func _spawn_heli() -> Node3D:
	var h := (load(HELI_SCENE) as PackedScene).instantiate() as Node3D
	h.set_meta("faction", "reich")
	h.set("max_health", 350.0)
	h.set("mg_damage", 5.0)
	h.set("burst_rounds", 12)
	h.set("attack_range", 220.0)
	h.set("searchlight", true)
	h.name = "GardeHeli"
	add_child(h)
	var s: float = float(ride.get("path_s")) + 260.0
	h.global_position = (ride.call("pos_at", s) as Vector3) + Vector3(0, 45, 0)
	h.set_meta("priority", 40.0)
	h.call("attack", true)
	_phase_nodes.append(h)
	_heli_t = 0.0
	return h

func _spawn_brandt() -> void:
	if not ResourceLoader.exists(HELI_SCENE):
		return
	var h := (load(HELI_SCENE) as PackedScene).instantiate() as Node3D
	h.set_meta("faction", "eu")
	h.set("max_health", 1000000.0)
	h.set("downwash", false)
	h.name = "Brandt"
	add_child(h)
	h.remove_from_group("enemy")
	h.remove_from_group("damageable")
	h.remove_from_group("vehicle")
	(h as CollisionObject3D).collision_layer = 0
	h.global_position = Vector3(140, 70, -60)
	var pts: Array[Vector3] = []
	for i in 10:
		var a := TAU * float(i) / 10.0
		pts.append(Vector3(80.0 + cos(a) * 150.0, 70.0, -90.0 + sin(a) * 150.0))
	h.call("fly_path", pts, 16.0, true)
	# "Lichter aus": keine Positionslichter/Blitzer (die roten Punkte am Himmel waren Brandts Navigationslichter)
	if h.has_method("set_nav_lights"):
		h.call("set_nav_lights", false)
	_brandt = h

# ------------------------------------------------------------------ Finale

func _finale() -> void:
	_done = true
	if ride != null:
		ride.call("release_stop")
		ride.call("set_speed", 12.0)
	_obj("Webers Boot (blau) zur Aurelia folgen – NICHT schießen")
	if ride != null:
		ride.set("hud_hint", "NICHT SCHIESSEN – Weber flieht an Bord der Aurelia")
	if _markers != null:
		_markers.call("clear")
	_mark_persistent()
	if _freighter != null and is_instance_valid(_freighter):
		_mark(_freighter, "FRACHTER AURELIA", Markers.C_WHITE, Vector3(-55.0, 26.0, 0.0))
	_say(SD.LENA, "Er hält auf den Frachter zu! Die Aurelia!")
	_say(SD.LENA, "Feuer einstellen, Kerner. An der Gangway stehen Matrosen, und Weber brauchen wir lebend.")
	if _weber_boat != null and is_instance_valid(_weber_boat):
		_weber_boat.set("free_target", World.FREIGHTER_BOARD)
		_weber_boat.set("free_speed", 14.0)
	await _until(func() -> bool: return _weber_boat == null or not is_instance_valid(_weber_boat) or (_weber_boat.global_position - World.FREIGHTER_BOARD).length() < 4.0, 30.0)
	_say(SD.KERNER, "Er ist an der Gangway. Ich hab keinen Schuss, ohne ihn umzubringen.")
	VF.play_2d(self, "hafen_horn", -3.0)
	await _sleep(2.0)
	_say(SD.WEBER, "Sagen Sie Voss, er soll mich in den Bergen suchen. Wenn er sich traut.")
	_say(SD.BRANDT, "Die Aurelia hat Ausfahrt Richtung Süden angemeldet. Weiterreise über Land, in die Alpen.")
	_say(SD.LENA, "Dann gehen wir nach Süden. Bis auf den Alpenpass, wenn es sein muss.")
	_obj("Weber ist entkommen – Spur nach Süden")
	if ride != null:
		ride.set("hud_hint", "")
	if _markers != null:
		_markers.call("clear")
	await _radio_wait(26.0)
	await _sleep(1.5)
	_on_level_end()

## Pausenmenue: "Checkpoint laden".
func menu_reload_checkpoint() -> void:
	if phase <= 3:
		var pl := get_tree().get_first_node_in_group("player")
		if pl != null and pl.has_method("respawn"):
			pl.call("respawn")
		return
	if phase >= 4 and phase <= 6:
		_fail("menu")

# ------------------------------------------------------------------ Takt

func _process(delta: float) -> void:
	_time += delta
	_phase_t += delta
	_update_glints()
	if ride != null and is_instance_valid(ride):
		FX.set_spray(_ride_spray, clampf(float(ride.get("speed")) / 14.0, 0.1, 1.0))

func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	_lena_hit_cd = maxf(0.0, _lena_hit_cd - delta)
	if _lena_c != null:
		_lena_c.call("tick", delta)
	_tick_snipers(delta)
	_tick_shooters(delta)
	if ride != null and is_instance_valid(ride):
		_brandt_t -= delta
		if _brandt_t <= 0.0 and _brandt != null and is_instance_valid(_brandt):
			_brandt_t = 1.5
			var d: Vector3 = ride.call("dir_at", float(ride.get("path_s")))
			var right := d.cross(Vector3.UP).normalized()
			_brandt.call("hover_at", ride.global_position - d * 35.0 - right * 30.0 + Vector3(0, 38, 0))
		if _heli != null and is_instance_valid(_heli) and _alive(_heli):
			_heli_t -= delta
			if _heli_t <= 0.0:
				_heli_t = 2.0
				var d2: Vector3 = ride.call("dir_at", float(ride.get("path_s")))
				var r2 := d2.cross(Vector3.UP).normalized()
				_heli.call("hover_at", ride.global_position + r2 * 40.0 + d2 * 30.0 + Vector3(0, 25, 0))
	if _bot != null and bot_drives_player():
		_bot.call("tick", delta)
