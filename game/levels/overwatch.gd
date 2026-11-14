extends "res://game/levels/level.gd"
## Level 7 "Kaltes Auge" (overwatch): Stahlwerk Hennigsdorf, 06.06.2030, 05:20 -- Morgendaemmerung im Nebel.
## Scharfschuetzen-Mission mit dem G28 (marksman_rifle.gd). Geometrie/Umgebung: overwatch_world.gd.
## Ablauf (phase):
##   climb    -> Aufstieg zum Uebergabeturm (Stellung 1)
##   sentries -> Lena markiert sechs Posten nacheinander, lautlos ausschalten
##   convoy   -> Konvoi rollt an, Sprengsatz am Fuehrungs-Lkw
##   ambush   -> Feuergefecht an der Strasse, eigene Leute (hellblaue Binden) decken
##   csniper  -> Gegenscharfschuetze auf dem Kuehlturm (Glint)
##   mortar   -> Moerser decken Stellung 1 ein -> ueber die Bandbruecke zur Ofenbuehne
##   p2       -> Schuetze auf dem Schornstein
##   weber    -> Weber hinter der Panzertuer, entkommt (gescriptet, unverwundbar)
##   brandt   -> Brandt wird befreit
##   extract  -> runter vom Turm, durch die Eingreiftruppe zum Transporter
## Figuren an der Strasse sind Puppen (overwatch_actor.gd) ohne eigene KI; nur die Eingreiftruppe am Ende
## nutzt die normale Gegner-KI. Unter --autopilot faehrt overwatch_bot.gd den Spieler.

const World = preload("res://game/levels/overwatch_world.gd")
const Convoy = preload("res://game/levels/overwatch_convoy.gd")
const Actor = preload("res://game/levels/overwatch_actor.gd")
const Bot = preload("res://game/levels/overwatch_bot.gd")
const Wind = preload("res://game/levels/overwatch_wind.gd")
const SD = preload("res://game/story/story_data.gd")
const VfxLib = preload("res://game/vfx/vfx_lib.gd")

const FR_PRIMARY := Color(0.27, 0.29, 0.34)      # Arbeitsjacke, verwaschenes Blaugrau
const FR_SECONDARY := Color(0.33, 0.27, 0.19)    # braune Hose/Weste
const FR_ARMBAND := Color(0.3, 0.68, 1.0)        # hellblaue Binde
const BRANDT_PRIMARY := Color(0.36, 0.38, 0.4)   # Haeftlingsjacke grau
const BRANDT_SECONDARY := Color(0.22, 0.24, 0.27)

const CRUISE := 9.0
const SNIPER_DMG := 45.0

var _sun: DirectionalLight3D
var _env: Environment
var points: Dictionary = {}

var phase: String = "climb"
var _pt: float = 0.0                 # Zeit in der Phase
var _t: float = 0.0                  # Gesamtzeit
var _bot: RefCounted = null
var _bot_on: bool = false
var _sun_x0: float = 0.0
var _fog0: float = 0.0
var _ready_ok: bool = false
var _wind: Node3D = null              # Wind fuer Ballistik + Windsaecke (overwatch_wind.gd)

# Posten (Phase 1)
var _sentries: Array = []            # {a: Actor, p0, p1, leg, wait, desc, startle}
var _mark: Node3D = null             # aktuell markierter Posten
var _mark_t: float = 0.0
var _mark_wait: float = 0.0
var _mark_i: int = 0
var _marker: MeshInstance3D
var _miss_check: float = -1.0
var _miss_lines: int = 0

# Konvoi / Hinterhalt
var _vehicles: Array = []            # {node, x, z, stop, speed, trav, kind}
var _ied_done: bool = false
var _car: Dictionary = {}
var _car_state: String = "drive"
var _car_t: float = 0.0
var _amb: Array = []                 # {a, cover, t, up, shots, shot_t}
var _friends: Array = []             # {a, cover, t, up, shot_t}
var _voss: Node3D = null
var _lena: Node3D = null
var _brandt: Node3D = null
var _weber: Node3D = null
var _fkill_t: float = 10.0
var _ff_count: int = 0
var _ff_cool: float = 0.0
var _weber_hits: int = 0

# Scharfschuetzen
var _snipers: Dictionary = {}        # key -> {a, stage, t, shots, glint, spot}
var _glint_tex: Texture2D

# Moerser
var _mortar_t: float = 3.0
var _mortar_n: int = 0
var _mortar_grace: float = 16.0

# Abzug
var _qrf_spawned: bool = false

# ================================================================== Aufbau

func _init() -> void:
	level_name = "overwatch"
	end_z = -95.0
	build_seed = 2030
	_wave_count = 1
	fog_density = 0.012
	ambient_artillery = false
	default_faction = "reich"

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Kaltes Auge"
	return info

func _setup_environment() -> void:
	var r: Dictionary = World.setup_environment(self)
	_sun = r.get("sun")
	_env = r.get("env")

func _build_ground() -> void:
	pass

func _build_street() -> void:
	points = World.build(self, world, covers, rng)

func _build_props() -> void:
	pass

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, _p("player_spawn", Vector3(3, 0.1, 30)), "player_spawn")
	ps.name = "PlayerSpawn"
	var area := _trigger("LevelEnd", _p("van", Vector3(-30, 0, -92)) + Vector3(0, 1.5, 0), Vector3(6, 3, 6), _try_end, false)
	area.add_to_group("level_end")

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
	# Nur die Bodenebene zwischen Werk und Strasse (Puppen/Eingreiftruppe), nicht die Hochbauten
	nm.filter_baking_aabb = AABB(Vector3(-80.0, -1.0, -165.0), Vector3(200.0, 7.0, 200.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)

func _ready() -> void:
	await super._ready()
	if player != null:
		player.call("give_weapon", "g28", 10, 60)
	if _sun != null:
		_sun_x0 = _sun.rotation_degrees.x
	if _env != null:
		_fog0 = _env.fog_density
	_wind = Wind.new()
	_wind.name = "Wind"
	add_child(_wind)
	_build_marker_mesh()
	_glint_tex = _make_glint_tex()
	_spawn_sentries()
	_spawn_friendlies()
	Events.weapon_fired.connect(_on_player_fired)
	Events.player_respawned.connect(_on_player_respawned)
	_bot_on = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	if _bot_on and player != null:
		_bot = Bot.new()
		_bot.call("setup", self, player)
	_ready_ok = true
	var start_ph: String = str(Game.arg("ow-start", ""))
	if start_ph != "":
		_skip_to(start_ph)
		_wind.call("snap")
	else:
		_intro()
	# Debug/Aufnahmen: --ow-cam=x,y,z,yaw,pitch setzt den Spieler fest an eine Kameraposition
	var cam_arg: String = str(Game.arg("ow-cam", ""))
	if cam_arg != "" and player != null:
		var v: PackedStringArray = cam_arg.split(",")
		if v.size() >= 5:
			player.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			player.call("set_view", float(v[3]), float(v[4]))
			player.set("external_input", true)
			if str(Game.arg("ow-scope", "")) in ["", "false", "0"]:
				player.set_physics_process(false)
	# --ow-scope: Zielfernrohr dauerhaft im Anschlag (Aufnahmen)
	if str(Game.arg("ow-scope", "")) not in ["", "false", "0"] and player != null:
		player.set("external_input", true)
		var e: Dictionary = player.get("ext")
		e["aim"] = true
		if str(Game.arg("ow-scope", "")) == "2":
			_later(1.0, func() -> void:
				var w: Node = player.get("weapon")
				if w != null and w.has_method("set_zoom"):
					w.call("set_zoom", 1))

# ================================================================== Hilfen

func _p(key: String, def: Vector3) -> Vector3:
	var v: Variant = points.get(key, def)
	return v as Vector3 if v is Vector3 else def

func _arr(key: String, def: Array) -> Array:
	var v: Variant = points.get(key, def)
	if v is Array and not (v as Array).is_empty():
		return v as Array
	if v is PackedVector3Array and (v as PackedVector3Array).size() > 0:
		return Array(v as PackedVector3Array)
	return def

func _radio(speaker: String, text: String, dur: float) -> void:
	Events.story_radio.emit(speaker, text, dur)

## Funkzeile mit StoryUI-Optionen (max_age/valid/priority/cut/key, siehe story_ui.gd say()).
## Zeilen im selben Frame bilden ein Gespraech: jede kommt direkt nach ihrer Vorgaengerin.
func _radio_opt(speaker: String, text: String, dur: float, opts: Dictionary) -> void:
	get_tree().call_group(&"story_ui", &"say", speaker, text, dur, opts)

## Restdauer laufender + wartender Funkzeilen.
func _radio_busy() -> float:
	var ui := get_tree().get_first_node_in_group(&"story_ui")
	if ui != null and ui.has_method("busy_left"):
		return float(ui.call("busy_left"))
	return 0.0

## f ausfuehren, sobald der Funk frei ist (hoechstens max_wait s warten).
func _when_radio_free(f: Callable, max_wait: float = 6.0) -> void:
	if _radio_busy() <= 0.3 or max_wait <= 0.0:
		f.call()
		return
	_later(0.25, _when_radio_free.bind(f, max_wait - 0.25))

## Phasenwechsel nach t s, aber erst wenn der Funk frei ist (sonst haengt die Ansage der neuen Phase hinterher).
func _later_phase(t: float, ph: String, f: Callable) -> void:
	_later(t, func() -> void:
		if phase == ph:
			_when_radio_free(func() -> void:
				if phase == ph:
					f.call(), 8.0))

var _last_objective: String = ""

func _objective(text: String) -> void:
	if text == _last_objective:
		return
	_last_objective = text
	Events.story_objective.emit(text)

func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)

## Funk nur, solange die Phase noch stimmt (verhindert veraltete Zeilen nach Spruengen).
## Nach t s, sobald der Funk frei ist (hoechstens 6 s warten) – keine Staus hinter Gefechtsrufen.
func _later_say(t: float, ph: String, speaker: String, text: String, dur: float) -> void:
	_later(t, _say_free.bind(ph, speaker, text, dur, 6.0))

func _say_free(ph: String, speaker: String, text: String, dur: float, wait: float) -> void:
	if phase != ph:
		return
	if _radio_busy() <= 0.3 or wait <= 0.0:
		_radio_opt(speaker, text, dur, {"max_age": 6.0, "valid": func() -> bool: return phase == ph})
		return
	_later(0.25, _say_free.bind(ph, speaker, text, dur, wait - 0.25))

func _set_phase(p: String) -> void:
	phase = p
	_pt = 0.0
	if _wind != null:
		_wind.call("set_phase", p)
	print("[overwatch] Phase -> %s (t=%.1f)" % [p, _t])

## Wind fuer das Scharfschuetzengewehr (m/s, Welt; Richtung, in die er blaest).
func sniper_wind() -> Vector3:
	if _wind == null:
		return Vector3.ZERO
	return _wind.call("current")

func _cam_pos() -> Vector3:
	if player == null:
		return Vector3.ZERO
	var cam: Camera3D = player.call("get_camera")
	return cam.global_position if cam != null else player.global_position + Vector3.UP * 1.6

func _alive(n: Variant) -> bool:
	return n != null and is_instance_valid(n) and n is Node and bool((n as Node).call("is_alive"))

## Gueltiger Knoten oder null (Leichen werden nach einigen Sekunden freigegeben).
func _node(v: Variant) -> Node3D:
	if v == null or not is_instance_valid(v) or not (v is Node3D):
		return null
	return v as Node3D

func _ray_clear(from: Vector3, to: Vector3, exclude: Array[RID] = []) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, exclude)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _visible_from_cam(n: Node3D, h: float = 1.2) -> bool:
	if player == null:
		return false
	var ex: Array[RID] = [player.get_rid()]
	return _ray_clear(_cam_pos(), n.global_position + Vector3.UP * h, ex)

func _make_actor(role: String, etype: String, pos: Vector3, prim: Color, sec: Color, band: Color, yaw: float) -> Node3D:
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
	a.global_position = pos + Vector3(0, 0.05, 0)
	a.rotation.y = deg_to_rad(yaw)
	return a

# ================================================================== Einstieg

func _intro() -> void:
	_set_phase("climb")
	_radio(SD.VOSS, "Kerner, hier Voss. Der Konvoi ist zwanzig Minuten raus. Rauf auf den Übergabeturm, bevor der Nebel sich hebt.", 6.0)
	_objective("Steig auf den Übergabeturm – Stellung beziehen")
	_later_say(7.5, "climb", SD.LENA, "Ich lieg am Bahndamm, Jonas. Unsere Leute tragen hellblaue Binden – präg sie dir ein.", 5.5)

func _skip_to(ph: String) -> void:
	# Debug: direkt in eine Phase springen (Aufnahmen/Tests)
	var p1 := _p("p1_snipe", Vector3(0, 22, 8.6))
	var p2 := _p("p2_snipe", Vector3(-42, 22, 2.8))
	var order: Array = ["climb", "sentries", "convoy", "ambush", "csniper", "mortar", "p2", "weber", "brandt", "extract"]
	var idx: int = order.find(ph)
	if idx < 0:
		_intro()
		return
	if idx >= 1 and player != null:
		player.global_position = p1 + Vector3(0, 0.2, 1.2)
		player.call("set_view", 0.0, -6.0)
		_checkpoint("cp_p1")
	if idx >= 2:
		for s in _sentries:
			var a: Node3D = _node(s["a"])
			if _alive(a):
				a.queue_free()
		_sentries.clear()
	if idx >= 3:
		_spawn_convoy(true)
	if idx == 3:
		_enter_ambush()
		return
	if idx >= 4:
		for e in _amb:
			var a2: Node3D = _node(e["a"])
			if _alive(a2):
				a2.queue_free()
		_amb.clear()
	if idx >= 6 and player != null:
		player.global_position = p2 + Vector3(0, 0.2, 1.2)
		player.call("set_view", 0.0, -6.0)
		_checkpoint("cp_p2")
	match ph:
		"sentries":
			_enter_sentries()
		"convoy":
			_enter_convoy()
		"csniper":
			_enter_csniper()
		"mortar":
			_enter_mortar()
		"p2":
			_enter_p2()
		"weber":
			_enter_weber()
		"brandt":
			_enter_brandt()
		"extract":
			_enter_extract()

# ================================================================== Ablauf

func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	_t += delta
	_pt += delta
	_ff_cool = maxf(0.0, _ff_cool - delta)
	_tick_vehicles(delta)
	_tick_sentries(delta)
	_tick_friendlies(delta)
	_tick_ambush(delta)
	_tick_snipers(delta)
	_check_sniper_deaths()
	match phase:
		"climb":
			_tick_climb()
		"sentries":
			_tick_phase_sentries(delta)
		"convoy":
			pass
		"ambush":
			_tick_phase_ambush(delta)
		"mortar":
			_tick_mortar(delta)
		"weber":
			_tick_weber(delta)
		"brandt":
			if _pt > 13.0:
				_enter_extract()
		"extract":
			_tick_extract()
	if _bot != null and bot_drives_player():
		_bot.call("tick", delta)

## Zielfernrohr: Der Kuehlturm steht knapp neben der tiefen Sonne. Bei 4-8 Grad Sichtfeld fuellte deren
## Vorwaertsstreuung (Volumennebel, Sun-Scatter) das ganze Glas weiss. Echte Optik hat Sonnenblende/Verguetung:
## bei kleinem FOV Streulicht der Sonne daempfen, Belichtung leicht senken.
var _scope_base: Vector3 = Vector3(-1.0, 0.0, 0.0)   # sun vol-energy, fog_sun_scatter, exposure
var _scope_sky: Vector2 = Vector2.ZERO               # fog_sky_affect, volumetric_fog_sky_affect
func _scope_light() -> void:
	if _sun == null or _env == null:
		return
	if _scope_base.x < 0.0:
		_scope_base = Vector3(_sun.light_volumetric_fog_energy, _env.fog_sun_scatter, _env.tonemap_exposure)
		_scope_sky = Vector2(_env.fog_sky_affect, _env.volumetric_fog_sky_affect)
	var cam := get_viewport().get_camera_3d()
	var k := 0.0
	if cam != null:
		k = clampf((40.0 - cam.fov) / 25.0, 0.0, 1.0)   # 40 Grad -> 0, <=15 Grad -> 1
	_sun.light_volumetric_fog_energy = _scope_base.x * lerpf(1.0, 0.3, k)
	_env.fog_sun_scatter = _scope_base.y * lerpf(1.0, 0.25, k)
	_env.tonemap_exposure = _scope_base.z * lerpf(1.0, 0.74, k)
	# Himmel hinter dem Turm: weniger Dunstschleier -> Wolkenzeichnung statt beiger Flaeche
	_env.fog_sky_affect = _scope_sky.x * lerpf(1.0, 0.35, k)
	_env.volumetric_fog_sky_affect = _scope_sky.y * lerpf(1.0, 0.35, k)

func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	# Morgendaemmerung: Sonne steigt langsam, Nebel duennt aus
	if _sun != null:
		_sun.rotation_degrees.x = _sun_x0 - minf(_t / 520.0, 1.0) * 7.0
	if _env != null and _fog0 > 0.0:
		_env.fog_density = _fog0 * lerpf(1.0, 0.72, minf(_t / 520.0, 1.0))
	_scope_light()
	_update_marker()
	_update_glints()

# ---------------------------------------------------------------- Phase 1: Aufstieg

func _tick_climb() -> void:
	if player == null:
		return
	var p1 := _p("p1_snipe", Vector3(0, 22, 8.6))
	var pp := player.global_position
	if pp.y > p1.y - 1.5 and Vector2(pp.x - p1.x, pp.z - p1.z).length() < 7.0:
		_checkpoint("cp_p1")
		_enter_sentries()

func _enter_sentries() -> void:
	_set_phase("sentries")
	_objective("Schalte die Posten aus (Rechtsklick: Zielfernrohr · Mausrad: Zoom · Shift: Atem anhalten · Bild↑/↓: Nullpunkt)")
	_radio(SD.LENA, "Ich seh dich oben. Ich markiere dir die Posten – einer nach dem anderen. Leise, Jonas.", 5.0)
	_later_say(6.0, "sentries", SD.LENA, "Siehst du den Windsack am Geländer? Leichter Wind von rechts – auf diese Entfernung kaum eine Handbreit.", 5.0)
	_mark_wait = 4.0
	_mark = null

# ---------------------------------------------------------------- Posten

func _spawn_sentries() -> void:
	var defs: Array = [
		{"a": _p("yard_a", Vector3(-8, 0, -45)), "b": _p("yard_b", Vector3(12, 0, -50)),
			"desc": "Erster Posten: Werkhof vor der Gießhalle. Er raucht. Lass dir Zeit."},
		{"a": _p("catwalk", Vector3(-20, 8, -70)), "b": _p("catwalk", Vector3(-20, 8, -70)) + Vector3(9, 0, 0),
			"desc": "Laufsteg an der Sinteranlage, acht Meter hoch. Der hat die ganze Straße im Blick."},
		{"a": _p("shed_roof", Vector3(60, 4.5, -80)), "b": _p("shed_roof", Vector3(60, 4.5, -80)) + Vector3(-7, 0, 0),
			"desc": "Dach der Lokhalle, rechts. Fernglas. Der darf uns nicht sehen."},
		{"a": _p("gap_a", Vector3(5, 0, -104)), "b": _p("gap_b", Vector3(25, 0, -104)),
			"desc": "Am Gleis, in der Lücke zwischen den Waggons. Läuft er weiter, stolpert er über unsere Leute."},
		{"a": _p("road_a", Vector3(-40, 0, -136)), "b": _p("road_b", Vector3(-10, 0, -136)),
			"desc": "Straßenposten links, am Schlagbaum. Lange Strecke – halt etwas höher."},
		{"a": _p("south_a", Vector3(35, 0, -150)), "b": _p("south_b", Vector3(55, 0, -150)),
			"desc": "Der Letzte. Jenseits der Straße, vor dem Schlackenberg. Danach ist die Straße blind."},
	]
	for d in defs:
		var a0: Vector3 = d["a"]
		var b0: Vector3 = d["b"]
		var a := _make_actor("enemy", "rifleman", a0, Color.BLACK, Color.BLACK, Color.BLACK, 90.0)
		a.set("walk_speed", 1.1)
		if a0.y > 1.0:
			a.set("gravity", 0.0)
		_sentries.append({"a": a, "p0": a0, "p1": b0, "leg": 1, "wait": rng.randf_range(0.0, 3.0),
			"desc": d["desc"], "startle": 0.0, "elev": a0.y > 1.0})

func _tick_sentries(delta: float) -> void:
	for s in _sentries:
		var a: Node3D = _node(s["a"])
		if not _alive(a):
			continue
		var st: float = float(s["startle"])
		if st > 0.0:
			s["startle"] = st - delta
			a.set("crouch", true)
			a.set("has_goal", false)
			continue
		a.set("crouch", false)
		var w: float = float(s["wait"])
		if w > 0.0:
			s["wait"] = w - delta
			continue
		var tgt: Vector3 = s["p1"] if int(s["leg"]) == 1 else s["p0"]
		if bool(a.call("arrived")) or not bool(a.get("has_goal")):
			var flat := Vector2(tgt.x - a.global_position.x, tgt.z - a.global_position.z)
			if flat.length() < 0.8:
				s["leg"] = 1 - int(s["leg"])
				s["wait"] = rng.randf_range(3.0, 6.0)
				continue
			a.call("walk_to", tgt, 1.1, not bool(s["elev"]))

func _tick_phase_sentries(delta: float) -> void:
	if _mark != null and not _alive(_mark):
		_mark = null
		_mark_i += 1
		var left := _sentries_alive()
		if left == 0:
			_radio_opt(SD.LENA, "Das war der Letzte. Die Straße ist blind. Gute Arbeit, Jonas.", 4.0, {"priority": 1, "cut": true})
			_later_phase(1.5, "sentries_done", _enter_convoy)
			_set_phase("sentries_done")
			return
		var acks: Array = ["Der liegt. Keiner hat's gehört.", "Sauber.", "Treffer. Weiter.", "Gut. Der Nächste.", "Der ist weg."]
		_radio_opt(SD.LENA, str(acks[_mark_i % acks.size()]), 2.5, {"max_age": 1.5, "key": "ow_ack"})
		_mark_wait = 3.0
	if _mark == null:
		_mark_wait -= delta
		# naechsten Posten erst ansagen, wenn der Funk frei ist (hoechstens 6 s Aufschub)
		if _mark_wait <= 0.0 and (_radio_busy() <= 0.3 or _mark_wait < -6.0):
			_mark_next()
	else:
		_mark_t += delta
		if _mark_t > 55.0:
			# Ausweichpfad: Voss' Leute uebernehmen den Posten leise
			_radio(SD.VOSS, "Den nehmen wir. Messer.", 2.5)
			_mark.call("take_damage", 999.0, null, _mark.global_position + Vector3.UP, Vector3.UP)
	# Miss-Erkennung
	if _miss_check > 0.0:
		_miss_check -= delta
		if _miss_check <= 0.0 and _mark != null and _alive(_mark):
			for s in _sentries:
				if s["a"] == _mark:
					s["startle"] = 4.5
			if _miss_lines < 3:
				_miss_lines += 1
				var lines: Array = ["Daneben. Er ist unruhig – warte, bis er sich beruhigt.", "Vorbei. Atme aus, dann Shift.", "Knapp. Er sucht – bleib ruhig."]
				var mk: Node3D = _mark
				_radio_opt(SD.LENA, str(lines[(_miss_lines - 1) % lines.size()]), 3.0,
					{"max_age": 2.0, "key": "ow_miss", "valid": func() -> bool: return _mark == mk and _alive(mk)})
	if _pt > 260.0:
		_radio(SD.VOSS, "Keine Zeit mehr. Den Rest übernehmen wir – der Konvoi ist da.", 4.0)
		_kill_remaining_sentries()
		_enter_convoy()

func _sentries_alive() -> int:
	var n := 0
	for s in _sentries:
		if _alive(s["a"]):
			n += 1
	return n

func _mark_next() -> void:
	for s in _sentries:
		var a: Node3D = _node(s["a"])
		if _alive(a):
			_mark = a
			_mark_t = 0.0
			# Zielbeschreibung erledigt sich, sobald der Posten liegt (bricht dann ab)
			_radio_opt(SD.LENA, str(s["desc"]), 4.5,
				{"priority": 1, "drop_live": true, "valid": func() -> bool: return _alive(a)})
			return

func _kill_remaining_sentries() -> void:
	for s in _sentries:
		var a: Node3D = _node(s["a"])
		if _alive(a):
			a.call("take_damage", 999.0, null, a.global_position + Vector3.UP, Vector3.UP)
	_mark = null

func _on_player_fired(_w: Node) -> void:
	if phase == "sentries" and _mark != null:
		_miss_check = 0.7

# ---------------------------------------------------------------- Markierung (roter Winkel)

func _build_marker_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Winkel nach unten (zwei Balken), Mittelpunkt 0
	var pts: Array = [
		[Vector3(-1.0, 1.0, 0), Vector3(-0.62, 1.0, 0), Vector3(0.0, 0.0, 0)],
		[Vector3(-1.0, 1.0, 0), Vector3(0.0, 0.0, 0), Vector3(0.0, -0.45, 0)],
		[Vector3(1.0, 1.0, 0), Vector3(0.0, 0.0, 0), Vector3(0.62, 1.0, 0)],
		[Vector3(1.0, 1.0, 0), Vector3(0.0, -0.45, 0), Vector3(0.0, 0.0, 0)],
	]
	for tri in pts:
		for v in tri:
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.18, 0.12, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 10
	_marker = MeshInstance3D.new()
	_marker.name = "TargetMarker"
	_marker.mesh = mesh
	_marker.material_override = mat
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)

func _update_marker() -> void:
	if _marker == null:
		return
	if phase != "sentries" or _mark == null or not _alive(_mark):
		_marker.visible = false
		return
	_marker.visible = true
	_marker.global_position = _mark.global_position + Vector3.UP * 2.35
	# Feste Bildschirmgroesse (ca. 2 % der Bildhoehe), unabhaengig von Entfernung und Zoom
	var fov: float = 70.0
	var dist: float = 10.0
	if player != null:
		var cam: Camera3D = player.call("get_camera")
		if cam != null:
			fov = cam.fov
			dist = cam.global_position.distance_to(_marker.global_position)
	var s: float = 0.022 * dist * tan(deg_to_rad(fov * 0.5))
	_marker.scale = Vector3.ONE * s
	var pulse: float = 0.7 + 0.3 * sin(_t * 5.0)
	(_marker.material_override as StandardMaterial3D).albedo_color.a = pulse

# ---------------------------------------------------------------- Verbuendete

func _spawn_friendlies() -> void:
	var covs: Array = _arr("friendly_cover", [
		Vector3(-18, 0, -124.5), Vector3(-10, 0, -124.5), Vector3(-2, 0, -124.5), Vector3(6, 0, -124.5),
		Vector3(14, 0, -124.5), Vector3(22, 0, -124.5), Vector3(30, 0, -124.5), Vector3(38, 0, -124.5)])
	var n: int = mini(covs.size(), 8)
	for i in n:
		var c: Vector3 = covs[i]
		var a := _make_actor("friendly", "rifleman", c, FR_PRIMARY.lerp(Color(0.3, 0.26, 0.2), float(i % 3) * 0.3),
			FR_SECONDARY.lerp(Color(0.2, 0.22, 0.24), float(i % 2) * 0.5), FR_ARMBAND, 180.0)
		a.set("max_health", 100.0)
		a.set("health", 100.0)
		a.set("crouch", true)
		a.set("aim_point", c + Vector3(0, 1.0, -20.0))
		if i == 2:
			_voss = a
			a.set("invulnerable", true)
		elif i == 5:
			_lena = a
			a.set("invulnerable", true)
		_friends.append({"a": a, "cover": c, "t": rng.randf_range(1.0, 4.0), "up": false, "shot_t": 0.0})

func _tick_friendlies(delta: float) -> void:
	var fight: bool = phase == "ambush"
	for f in _friends:
		var a: Node3D = _node(f["a"])
		if not _alive(a):
			continue
		if not fight:
			if f["up"]:
				f["up"] = false
				a.set("crouch", true)
				a.set("aiming", false)
			continue
		f["t"] = float(f["t"]) - delta
		if f["up"]:
			f["shot_t"] = float(f["shot_t"]) - delta
			if float(f["shot_t"]) <= 0.0:
				f["shot_t"] = rng.randf_range(0.25, 0.7)
				var tgt: Node3D = _random_alive(_amb)
				if tgt != null:
					a.call("puppet_fire", tgt.global_position + Vector3.UP * 1.2, 1.2)
			if float(f["t"]) <= 0.0:
				f["up"] = false
				f["t"] = rng.randf_range(2.0, 4.0)
				a.set("crouch", true)
				a.set("aiming", false)
		elif float(f["t"]) <= 0.0:
			f["up"] = true
			f["t"] = rng.randf_range(1.8, 3.2)
			a.set("crouch", false)
			a.set("aiming", true)
			var tgt2: Node3D = _random_alive(_amb)
			if tgt2 != null:
				a.set("aim_point", tgt2.global_position + Vector3.UP * 1.2)

func _random_alive(list: Array) -> Node3D:
	var alive: Array = []
	for e in list:
		var a: Node3D = _node(e["a"])
		if _alive(a):
			alive.append(a)
	if alive.is_empty():
		return null
	return alive[rng.randi() % alive.size()]

func on_friendly_hit(_who: Node) -> void:
	if _ff_cool > 0.0:
		return
	_ff_cool = 1.0
	_ff_count += 1
	if _ff_count == 1:
		_radio(SD.VOSS, "Kerner! Das sind unsere Leute – hellblaue Binden! Noch einmal und wir brechen ab.", 4.5)
	else:
		_friendly_fire_fail()

func on_friendly_died(who: Node) -> void:
	# Nur Spieler-Treffer koennen Verbuendete toeten (Gegner-Puppen schiessen kosmetisch)
	if who == _voss or who == _lena:
		return
	_friendly_fire_fail()

func _friendly_fire_fail() -> void:
	_ff_count = 0
	_radio(SD.VOSS, "Feuer einstellen! Kerner, du hast einen von uns getroffen. Abbruch!", 4.0)
	_later(2.0, func() -> void:
		if player != null and bool(player.call("is_alive")):
			player.call("take_damage", 9999.0, null, Vector3.ZERO, Vector3.UP))

func on_weber_hit() -> void:
	_weber_hits += 1
	if _weber_hits == 1:
		_radio(SD.LENA, "Panzerglas, Jonas! Die Tür ist gepanzert – spar dir die Munition.", 3.5)
		_later(3.8, func() -> void: _radio(SD.WEBER, "Netter Versuch, Kerner.", 2.5))

func on_enemy_wounded(_who: Node) -> void:
	pass

# ---------------------------------------------------------------- Konvoi

func _enter_convoy() -> void:
	_set_phase("convoy")
	_kill_remaining_sentries()
	_objective("Deck den Hinterhalt – triff keine eigenen Leute")
	_radio(SD.LENA, "Motoren. Der Konvoi kommt – drei Lkw und ein schwarzer Wagen.", 4.0)
	_radio_opt(SD.VOSS, "Alle runter. Wir warten auf die Ladung. Kerner, du nimmst, wer aussteigt.", 5.0,
		{"valid": func() -> bool: return phase == "convoy"})
	_later_say(11.0, "convoy", SD.ORDNUNG, "Kolonne Nord an Leitstelle: Passieren Werkstraße Hennigsdorf, keine Vorkommnisse.", 6.0)
	_spawn_convoy(false)

func _spawn_convoy(at_stop: bool) -> void:
	if not _vehicles.is_empty():
		return
	var ied := _p("ied", Vector3(-5, 0, -140))
	var rz: float = float(points.get("road_z", ied.z))
	var lane_z: float = rz - 2.0
	var kinds: Array = ["gun", "prisoner", "troop"]
	var gaps: Array = [0.0, 22.0, 44.0]
	var stops: Array = [ied.x, ied.x + 15.0, ied.x + 31.0]
	var start_x: float = ied.x + 230.0
	for i in kinds.size():
		var v: Node3D = Convoy.build_truck(str(kinds[i]))
		v.name = "Truck_%s" % kinds[i]
		add_child(v)
		var x0: float = (float(stops[i]) if at_stop else start_x + float(gaps[i]))
		v.global_position = Vector3(x0, 0.0, lane_z)
		v.rotation.y = deg_to_rad(90.0)
		_vehicles.append({"node": v, "x": x0, "z": lane_z, "stop": float(stops[i]), "speed": 0.0 if at_stop else CRUISE,
			"trav": 0.0, "kind": kinds[i]})
	var car: Node3D = Convoy.build_car()
	car.name = "WeberCar"
	add_child(car)
	var ws := _p("weber_stop", Vector3(75, 0, -142))
	var cx: float = ws.x if at_stop else start_x + 95.0
	car.global_position = Vector3(cx, 0.0, lane_z)
	car.rotation.y = deg_to_rad(90.0)
	_car = {"node": car, "x": cx, "z": lane_z, "stop": ws.x, "speed": 0.0 if at_stop else CRUISE, "trav": 0.0, "kind": "car"}
	_vehicles.append(_car)
	if at_stop:
		_ied_done = true
		_wreck(_vehicles[0]["node"] as Node3D, false)

func _tick_vehicles(delta: float) -> void:
	if _vehicles.is_empty():
		return
	var ied := _p("ied", Vector3(-5, 0, -140))
	for v in _vehicles:
		var node: Node3D = v["node"]
		if not is_instance_valid(node):
			continue
		if v == _car and _car_state != "drive":
			continue
		var sp: float = float(v["speed"])
		if _ied_done:
			var dist: float = float(v["x"]) - float(v["stop"])
			sp = minf(sp, sqrt(maxf(0.0, 2.0 * 6.5 * dist)))
			if dist <= 0.05:
				sp = 0.0
		v["speed"] = sp
		if sp <= 0.0:
			continue
		v["x"] = float(v["x"]) - sp * delta
		v["trav"] = float(v["trav"]) + sp * delta
		node.global_position.x = float(v["x"])
		Convoy.set_spin(node, float(v["trav"]))
		if not _ied_done and v == _vehicles[0] and float(v["x"]) <= ied.x + 0.3:
			_detonate_ied()
	_tick_car(delta)

func _detonate_ied() -> void:
	_ied_done = true
	var lead: Dictionary = _vehicles[0]
	lead["speed"] = 0.0
	lead["stop"] = float(lead["x"])
	var node: Node3D = lead["node"]
	VFX.spawn_explosion(node.global_position + Vector3(0, 0.8, 0), 2.4)
	_wreck(node, true)
	_enter_ambush()

func _wreck(node: Node3D, anim: bool) -> void:
	var tilt := Vector3(deg_to_rad(4.0), deg_to_rad(90.0 + 9.0), deg_to_rad(7.0))
	if anim:
		var tw := node.create_tween()
		tw.tween_property(node, "rotation", tilt, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		node.rotation = tilt
	Props.fire(self, node.global_position + Vector3(0, 1.4, -0.5), 2.2, true, 1.3, 5.0)
	# Scheinwerfer der Wrack-Kabine aus
	for c in node.find_children("*", "SpotLight3D", true, false):
		(c as SpotLight3D).visible = false

# ---------------------------------------------------------------- Hinterhalt

func _enter_ambush() -> void:
	_set_phase("ambush")
	_objective("Schalte die Konvoi-Wachen aus – schütze die Leute mit den hellblauen Binden")
	_radio_opt(SD.VOSS, "Jetzt! Feuer frei!", 2.0, {"priority": 2, "cut": true})
	_radio_opt(SD.LENA, "Sie steigen aus – hinter den Lkw! Jonas, nimm sie runter!", 3.5,
		{"priority": 2, "max_age": 2.0, "valid": func() -> bool: return phase == "ambush"})
	_later_say(9.0, "ambush", SD.ORDNUNG, "Kontakt! Kontakt Werkstraße! Hinterhalt von Norden!", 4.6)
	var covs: Array = _arr("enemy_cover", [
		Vector3(-14, 0, -147), Vector3(-6, 0, -149), Vector3(3, 0, -147), Vector3(9, 0, -150),
		Vector3(16, 0, -147), Vector3(22, 0, -149), Vector3(29, 0, -147), Vector3(36, 0, -150)])
	covs = _cover_in_gaps(covs)
	var n: int = mini(covs.size(), 12)
	for i in n:
		var v: Dictionary = _vehicles[1 + (i % 2)]
		var src := Vector3(float(v["x"]) + rng.randf_range(-3.0, 3.0), 0.0, float(v["z"]) - 2.2)
		var a := _make_actor("enemy", "rifleman", src, Color.BLACK, Color.BLACK, Color.BLACK, 0.0)
		a.set("max_health", 60.0)
		a.call("walk_to", covs[i], 4.0, true)
		_amb.append({"a": a, "cover": covs[i], "t": rng.randf_range(1.5, 3.0), "up": false, "shot_t": 0.0, "burst": 0})
	_fkill_t = 9.0

## Ein Lkw (3,2 m hoch) verdeckt aus 22 m Hoehe und 150 m Entfernung gut 20 m Boden dahinter.
## Deckungspunkte direkt hinter den stehenden Lkw waeren fuer den Spieler unsichtbar -> in die Luecken schieben.
func _cover_in_gaps(covs: Array) -> Array:
	var blocked: Array = []
	for v in _vehicles:
		if v == _car:
			continue
		blocked.append(float(v["stop"]))
	var out: Array = []
	for c in covs:
		var p: Vector3 = c
		for k in 6:
			var hit := false
			for bx in blocked:
				if absf(p.x - float(bx)) < 6.0:
					hit = true
					p.x = float(bx) + (6.8 if p.x >= float(bx) else -6.8)
			if not hit:
				break
		out.append(p)
	return out

func _tick_ambush(delta: float) -> void:
	if _amb.is_empty():
		return
	for e in _amb:
		var a: Node3D = _node(e["a"])
		if not _alive(a):
			continue
		if bool(a.get("has_goal")):
			continue     # laeuft noch in Deckung
		e["t"] = float(e["t"]) - delta
		if e["up"]:
			e["shot_t"] = float(e["shot_t"]) - delta
			if float(e["shot_t"]) <= 0.0:
				var b: int = int(e["burst"])
				if b > 0:
					e["burst"] = b - 1
					e["shot_t"] = 0.14
				else:
					e["burst"] = rng.randi_range(2, 4)
					e["shot_t"] = rng.randf_range(0.6, 1.1)
				var tgt: Node3D = _random_alive(_friends)
				if tgt != null:
					a.call("puppet_fire", tgt.global_position + Vector3.UP * 0.9, 1.6)
			if float(e["t"]) <= 0.0:
				e["up"] = false
				e["t"] = rng.randf_range(2.0, 3.5)
				a.set("crouch", true)
				a.set("aiming", false)
		elif float(e["t"]) <= 0.0:
			e["up"] = true
			e["t"] = rng.randf_range(2.6, 4.0)
			a.set("crouch", false)
			a.set("aiming", true)
			var tgt2: Node3D = _random_alive(_friends)
			if tgt2 != null:
				a.set("aim_point", tgt2.global_position + Vector3.UP * 1.0)
		else:
			a.set("crouch", true)

func _tick_phase_ambush(delta: float) -> void:
	# Gescriptete Treffer der Verbuendeten (haelt das Gefecht in Bewegung)
	_fkill_t -= delta
	if _fkill_t <= 0.0:
		_fkill_t = rng.randf_range(9.0, 13.0)
		var victim: Node3D = null
		for e in _amb:
			if _alive(e["a"]) and bool(e["up"]):
				victim = e["a"]
				break
		if victim == null:
			victim = _random_alive(_amb)
		if victim != null:
			var shooter: Node3D = _random_alive(_friends)
			if shooter != null:
				shooter.set("crouch", false)
				shooter.call("puppet_fire", victim.global_position + Vector3.UP * 1.2, 0.05)
			victim.call("take_damage", 999.0, null, victim.global_position + Vector3.UP * 1.2, Vector3.UP)
	var alive := 0
	for e in _amb:
		if _alive(e["a"]):
			alive += 1
	if alive == 0 or _pt > 120.0:
		if alive > 0:
			_radio(SD.VOSS, "Wir machen den Rest. Kerner, Augen nach oben!", 3.0)
			for e in _amb:
				var a: Node3D = _node(e["a"])
				if _alive(a):
					a.call("take_damage", 999.0, null, a.global_position + Vector3.UP, Vector3.UP)
		else:
			_radio(SD.VOSS, "Straße ist sauber! Ich hol Brandt aus dem Lkw.", 3.5)
		_set_phase("ambush_done")
		if _voss != null and _alive(_voss):
			var pv: Dictionary = _vehicles[1]
			_voss.call("walk_to", Vector3(float(pv["x"]) + 4.6, 0.0, float(pv["z"]) + 2.4), 3.0, true)
		_later_phase(4.0, "ambush_done", _enter_csniper)

# ---------------------------------------------------------------- Gegenscharfschuetzen

func _spawn_sniper(key: String, pos: Vector3) -> Node3D:
	var a := _make_actor("enemy", "marksman", pos, Color.BLACK, Color.BLACK, Color.BLACK, 0.0)
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
	add_child(g)
	_snipers[key] = {"a": a, "stage": "hide", "t": 3.5, "shots": 0, "glint": g, "glow": 0.0}
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
		var a: Node3D = _node(s["a"])
		var g: MeshInstance3D = s["glint"]
		if not _alive(a):
			g.visible = false
			continue
		var active: bool = (key == "a" and phase in ["csniper", "mortar"]) or (key == "b" and phase == "p2")
		if not active:
			a.set("aiming", false)
			a.set("crouch", true)
			s["glow"] = 0.0
			continue
		s["t"] = float(s["t"]) - delta
		var stage: String = s["stage"]
		var aim_at := _cam_pos()
		match stage:
			"hide":
				# Bleibt stehen (nur Gewehr abgesetzt): geduckt verschwand er hinter dem Gelaender und war unerreichbar.
				a.set("crouch", false)
				a.set("aiming", false)
				s["glow"] = maxf(0.0, float(s["glow"]) - delta * 3.0)
				if float(s["t"]) <= 0.0:
					s["stage"] = "aim"
					s["t"] = 2.6
					a.set("crouch", false)
					a.set("aiming", true)
					if player != null:
						VFX.play_sfx_3d("overwatch_glint", player.global_position + Vector3(0, 1.5, -4.0), -12.0, 8.0, 40.0)
			"aim":
				a.set("aim_point", aim_at)
				s["glow"] = minf(1.0, float(s["glow"]) + delta * 2.5)
				if float(s["t"]) <= 0.0:
					_sniper_shot(key, s)
					s["stage"] = "hide"
					s["t"] = rng.randf_range(2.4, 3.2)
					if key == "a" and int(s["shots"]) == 1 and phase == "csniper":
						_sniper_relocate(s, a)
			"move":
				# Stellungswechsel am Kuehlturmrand (geduckt, kein Blitzen): Duell statt Ein-Schuss-Ziel
				a.set("aiming", false)
				s["glow"] = maxf(0.0, float(s["glow"]) - delta * 3.0)
				if float(s["t"]) <= 0.0:
					a.set("crouch", false)
					s["stage"] = "hide"
					s["t"] = 1.2

## Gegenscharfschuetze "a" wechselt nach dem Warnschuss die Stellung (ca. 20 Grad den Ringsteg entlang,
## bleibt zur Spielerseite): der Spieler muss das naechste Blitzen abwarten, Lenas Hinweise (Hinlegen, Wind)
## haben Zeit zu laufen. Turmmitte wie overwatch_world_far.gd (CT).
func _sniper_relocate(s: Dictionary, a: Node3D) -> void:
	var ct := Vector3(-120.0, 0.0, -230.0)
	var off := a.global_position - ct
	var r := Vector2(off.x, off.z).length()
	var ang := atan2(off.z, off.x) - 0.35
	var dest := Vector3(ct.x + cos(ang) * r, a.global_position.y, ct.z + sin(ang) * r)
	s["stage"] = "move"
	s["t"] = 5.0
	a.set("crouch", true)
	a.set("aiming", false)
	var tw := create_tween()
	tw.tween_property(a, "global_position", dest, 4.6).set_trans(Tween.TRANS_SINE)
	_objective("Er wechselt die Stellung am Kühlturmrand – auf das nächste Blitzen warten")

func _sniper_shot(key: String, s: Dictionary) -> void:
	var a: Node3D = _node(s["a"])
	if player == null or not bool(player.call("is_alive")):
		return
	var from: Vector3 = a.call("scope_pos")
	var cam := _cam_pos()
	var shots: int = int(s["shots"])
	s["shots"] = shots + 1
	a.call("puppet_fire", cam, 0.0)
	var dist: float = from.distance_to(cam)
	# Knall verzoegert (Schallgeschwindigkeit), aus Richtung des Schuetzen
	var dir := (from - cam).normalized()
	_later(dist / 343.0, func() -> void:
		if player != null:
			VFX.play_sfx_3d("overwatch_dmr_fire", player.global_position + dir * 25.0 + Vector3.UP * 2.0, -4.0, 14.0, 80.0))
	var tof: float = dist / 800.0
	var ex: Array[RID] = []
	ex.append(a.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, cam, 1, ex)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	if shots == 0:
		# Erster Schuss: knapp daneben (Warnung)
		var miss := cam + Vector3(rng.randf_range(-1.2, 1.2), -0.9, 0.0) + (cam - from).normalized() * 0.5
		var q2 := PhysicsRayQueryParameters3D.create(from, miss + (miss - from).normalized() * 6.0, 1, ex)
		var r2: Dictionary = get_world_3d().direct_space_state.intersect_ray(q2)
		_later(tof, func() -> void:
			VFX.play_whiz_along(from, cam + (cam - from).normalized() * 4.0, 4.0)
			if not r2.is_empty():
				VFX.spawn_impact(r2.position, r2.normal, str((r2.collider as Node).get_meta("surface", "concrete")) if r2.collider is Node else "concrete"))
		if key == "a":
			_radio_opt(SD.LENA, "Scharfschütze! Kühlturm, oben am Rand – achte auf das Blitzen!", 4.0,
				{"priority": 1, "drop_live": true, "valid": func() -> bool: return phase == "csniper"})
			_later_say(5.0, "csniper", SD.LENA, "Wenn es blitzt, leg dich hin (Z) – die Brüstung deckt dich nur liegend.", 4.5)
			_later_say(10.5, "csniper", SD.LENA, "Kühlturm, rund zweihundertfünfzig Meter. Wind frisch von rechts – halt höher und eine Kopfbreite rechts.", 5.0)
		return
	if hit.is_empty():
		_later(tof, func() -> void:
			if player != null and bool(player.call("is_alive")):
				player.call("take_damage", SNIPER_DMG, a if is_instance_valid(a) else null, cam, (cam - from).normalized()))
	else:
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		var surf: String = str((hit.collider as Node).get_meta("surface", "concrete")) if hit.collider is Node else "concrete"
		_later(tof, func() -> void:
			VFX.spawn_impact(hp, hn, surf)
			if player != null and hp.distance_to(player.global_position) < 6.0:
				VFX.play_sfx_3d("overwatch_impact_metal" if surf == "metal" else "overwatch_impact_flesh", hp, -6.0, 6.0, 40.0))

func _update_glints() -> void:
	var fov: float = 70.0
	if player != null:
		var cam: Camera3D = player.call("get_camera")
		if cam != null:
			fov = cam.fov
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		var a: Node3D = _node(s["a"])
		var g: MeshInstance3D = s["glint"]
		if not _alive(a):
			g.visible = false
			continue
		var glow: float = float(s["glow"])
		g.visible = glow > 0.01
		if not g.visible:
			continue
		var sp: Vector3 = a.call("scope_pos")
		g.global_position = sp
		var flick: float = 0.75 + 0.25 * sin(_t * 23.0) * sin(_t * 7.0)
		var gd: float = _cam_pos().distance_to(sp)
		g.scale = Vector3.ONE * (0.035 * gd * tan(deg_to_rad(fov * 0.5))) * (0.6 + 0.4 * glow)
		(g.material_override as StandardMaterial3D).albedo_color.a = glow * flick

func _enter_csniper() -> void:
	_set_phase("csniper")
	_spawn_sniper("a", _p("sniper_a", Vector3(-112, 68, -212)))
	_objective("Gegenscharfschütze! Achte auf das Blitzen – Kühlturm")
	_radio(SD.LENA, "Jonas, irgendwas blitzt da drüben… links, Richtung Kühlturm.", 3.5)

func on_sniper_dead(key: String) -> void:
	if key == "a" and phase == "csniper":
		_set_phase("csniper_done")
		_radio_opt(SD.LENA, "Kühlturm ist sauber.", 2.5, {"priority": 1, "cut": true})
		_later_phase(1.0, "csniper_done", _enter_mortar)
	elif key == "b" and phase == "p2":
		_set_phase("p2_done")
		_radio_opt(SD.LENA, "Schornstein ist frei. Danke, Jonas.", 2.5, {"priority": 1, "cut": true})
		_later_phase(1.5, "p2_done", _enter_weber)

func _check_sniper_deaths() -> void:
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		if not bool(s.get("dead_told", false)) and not _alive(s["a"]):
			s["dead_told"] = true
			on_sniper_dead(key)

# ---------------------------------------------------------------- Moerser

func _enter_mortar() -> void:
	_set_phase("mortar")
	_mortar_t = 2.5
	_mortar_n = 0
	_mortar_grace = 16.0
	_radio_opt(SD.VOSS, "Mörser! Die haben dich angepeilt, Kerner!", 3.0, {"priority": 2, "cut": true})
	_radio_opt(SD.LENA, "Raus da, Jonas – über die Bandbrücke zur Ofenbühne!", 3.5,
		{"priority": 2, "valid": func() -> bool: return phase == "mortar"})
	_objective("Über die Bandbrücke zur Ofenbühne – zweite Stellung")

func _tick_mortar(delta: float) -> void:
	_mortar_grace -= delta
	_mortar_t -= delta
	if _mortar_t <= 0.0:
		_mortar_t = 3.5
		_fire_mortar()
	if player != null:
		var p2 := _p("p2_snipe", Vector3(-42, 22, 2.8))
		var pp := player.global_position
		if pp.y > p2.y - 1.5 and Vector2(pp.x - p2.x, pp.z - p2.z).length() < 6.0:
			_checkpoint("cp_p2")
			_enter_p2()

func _fire_mortar() -> void:
	var p1 := _p("p1_snipe", Vector3(0, 22, 8.6))
	var tgt: Vector3
	if _mortar_grace > 0.0:
		# Einschiessen: Einschlaege wandern auf den Turm zu
		var k: float = clampf(float(_mortar_n) / 4.0, 0.0, 1.0)
		tgt = Vector3(8, 0, -30).lerp(Vector3(6, 0, 20), k) + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-5, 5))
	else:
		var pp := player.global_position if player != null else p1
		var on_p1: bool = pp.x > -5.5 and pp.y > p1.y - 2.0
		if on_p1:
			tgt = Vector3(pp.x, p1.y, pp.z) + Vector3(rng.randf_range(-3.5, 3.5), 0, rng.randf_range(-3.5, 3.5))
		else:
			tgt = p1 + Vector3(rng.randf_range(-4.0, 4.0), 0, rng.randf_range(0.0, 7.0))
		# Auf die Bodenflaeche der Buehne setzen
		var q := PhysicsRayQueryParameters3D.create(tgt + Vector3.UP * 6.0, tgt + Vector3.DOWN * 30.0, 1)
		var r: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
		if not r.is_empty():
			tgt = r.position
	if _mortar_grace <= 0.0 or _mortar_n > 0:
		pass
	_mortar_n += 1
	if player != null:
		VFX.play_sfx_3d("overwatch_mortar_launch", player.global_position + Vector3(25, 4, -60).normalized() * 40.0, -10.0, 20.0, 120.0)
	var land := tgt
	_later(1.6, func() -> void:
		VFX.play_sfx_3d("overwatch_mortar_whistle", land + Vector3.UP * 8.0, 0.0, 25.0, 200.0))
	_later(3.0, func() -> void:
		if phase != "mortar" and phase != "p2":
			return
		VFX.spawn_explosion(land, 1.3)
		if player != null and bool(player.call("is_alive")):
			var d: float = player.global_position.distance_to(land)
			if d < 7.0:
				player.call("take_damage", 70.0 * (1.0 - d / 7.0) + 10.0, null, land, Vector3.UP))

# ---------------------------------------------------------------- Stellung 2

func _enter_p2() -> void:
	_set_phase("p2")
	_spawn_sniper("b", _p("sniper_b", Vector3(100, 30, -210.5)))
	_radio_opt(SD.LENA, "Gut, du bist drüben. Zweiter Schütze – auf dem Schornstein rechts vom Hochofen!", 4.5, {"priority": 1, "cut": true})
	_radio_opt(SD.VOSS, "Mörserstellung ist unser. Kerner, halt uns den Schornstein vom Hals.", 4.0,
		{"priority": 1, "drop_live": true, "valid": func() -> bool: return phase == "p2"})
	_later_say(10.0, "p2", SD.LENA, "Der Wind hat gedreht, Jonas – jetzt von links. Schau auf den Dampf am Schornstein.", 4.5)
	_objective("Schalte den Schützen auf dem Schornstein aus")

# ---------------------------------------------------------------- Weber

func _enter_weber() -> void:
	_set_phase("weber")
	_objective("Der schwarze Wagen – hintere Tür")
	_radio(SD.LENA, "Bewegung am schwarzen Wagen. Hintere Tür, Jonas.", 3.0)
	if _car.is_empty():
		_spawn_convoy(true)

func _car_local(local: Vector3) -> Vector3:
	var car: Node3D = _car["node"]
	return car.global_transform * local

func _tick_weber(_delta: float) -> void:
	if _car.is_empty():
		return
	var car: Node3D = _car["node"]
	var pivot: Node3D = car.get_meta("door_pivot") as Node3D
	if _pt > 0.8 and _car_state == "drive" and _weber == null:
		_car_state = "door"
		if pivot != null:
			var tw := pivot.create_tween()
			tw.tween_property(pivot, "rotation:y", deg_to_rad(-70.0), 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_weber = _make_actor("weber", "officer", _car_local(Vector3(-1.25, 0, 1.35)), Color(0.12, 0.12, 0.13), Color(0.1, 0.1, 0.11), Color(0.75, 0.04, 0.04), 0.0)
		_weber.set("invulnerable", true)
		_weber.set("gravity", 0.0)
		_weber.global_position.y = car.global_position.y + 0.05
	if _weber != null and is_instance_valid(_weber) and player != null:
		_weber.set("aiming", true)
		_weber.set("aim_point", _cam_pos())
	if _pt > 2.2 and not bool(_car.get("l1", false)):
		_car["l1"] = true
		_radio(SD.WEBER, "Kerner. Ich hätte wissen müssen, dass Voss dich schickt.", 4.5)
	if _pt > 7.5 and not bool(_car.get("l2", false)):
		_car["l2"] = true
		_radio(SD.WEBER, "Du schießt auf Glas, Junge. Wie in Berlin – du siehst nur, was ich dich sehen lasse.", 5.5)
	if _pt > 13.5 and not bool(_car.get("smoke", false)):
		_car["smoke"] = true
		_radio(SD.LENA, "Er wirft Rauch!", 2.0)
		_smoke_screen(_car_local(Vector3(-3.0, 0.3, 0.0)))
	if _pt > 15.5 and _car_state == "door":
		_car_state = "turn"
		_car_t = 0.0
		if _weber != null and is_instance_valid(_weber):
			_weber.queue_free()
		_weber = null
		if pivot != null:
			var tw2 := pivot.create_tween()
			tw2.tween_property(pivot, "rotation:y", 0.0, 0.35)
		VFX.play_sfx_3d("overwatch_door_slam", car.global_position, 0.0, 12.0, 300.0)
	if _pt > 22.0 and not bool(_car.get("l3", false)):
		_car["l3"] = true
		_radio(SD.VOSS, "Lass ihn. Wir sind wegen Brandt hier.", 3.0)
	if _pt > 25.0:
		_enter_brandt()

func _tick_car(delta: float) -> void:
	if _car.is_empty() or _car_state == "drive" or _car_state == "door":
		return
	var car: Node3D = _car["node"]
	if not is_instance_valid(car):
		return
	_car_t += delta
	var cx: float = float(_car["x"])
	var cz: float = float(_car["z"])
	if _car_state == "turn":
		# Wende ueber die Gegenfahrbahn (Halbkreis nach Norden)
		var th: float = clampf(_car_t / 3.2, 0.0, 1.0)
		th = th * th * (3.0 - 2.0 * th) * PI
		var pos := Vector3(cx - sin(th) * 3.2, 0.0, cz + 2.0 - cos(th) * 2.0)
		var d := Vector3(-cos(th) * 3.2, 0.0, sin(th) * 2.0)
		car.global_position = pos
		car.rotation.y = atan2(-d.x, -d.z)
		Convoy.set_spin(car, _car_t * 4.0)
		if _car_t >= 3.2:
			_car_state = "flee"
			_car_t = 0.0
			_car["fx"] = pos.x
			_car["fz"] = pos.z
	elif _car_state == "flee":
		var sp: float = minf(18.0, 3.0 + _car_t * 6.0)
		_car["fx"] = float(_car["fx"]) + sp * delta
		car.global_position = Vector3(float(_car["fx"]), 0.0, float(_car["fz"]))
		car.rotation.y = deg_to_rad(-90.0)
		_car["trav"] = float(_car["trav"]) + sp * delta
		Convoy.set_spin(car, float(_car["trav"]))
		if float(_car["fx"]) > cx + 260.0:
			car.visible = false
			_car_state = "gone"

func _smoke_screen(pos: Vector3) -> void:
	var sp := VfxLib.smoke_pm(ParticleProcessMaterial.new(), 8.0)
	sp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sp.emission_sphere_radius = 1.2
	sp.direction = Vector3(0, 0.4, 1)
	sp.spread = 70.0
	sp.initial_velocity_min = 1.5
	sp.initial_velocity_max = 4.0
	sp.gravity = Vector3(0, 0.25, 0) + VfxLib.WIND * 0.8
	sp.damping_min = 0.6
	sp.damping_max = 1.2
	sp.scale_min = 3.0
	sp.scale_max = 5.0
	sp.scale_curve = VfxLib.smooth_curve_tex([[0.0, 0.3], [0.15, 0.85], [1.0, 2.2]])
	sp.color_ramp = VfxLib.smoke_alpha_ramp(1.0, 0.05, 0.6)
	var mat := VfxLib.smoke_mat({
		"smoke_color": Color(0.78, 0.8, 0.82),
		"smoke_color_end": Color(0.62, 0.64, 0.66),
		"density": 1.6,
		"erosion": 0.25,
		"soft_dist": 2.0,
	})
	var p := VfxLib.make_particles(70, 16.0, sp, VfxLib.quad(1.0), mat)
	p.one_shot = false
	p.explosiveness = 0.15
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-30, -3, -30), Vector3(60, 40, 60))
	p.name = "WeberSmoke"
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_later(9.0, func() -> void:
		if is_instance_valid(p):
			p.emitting = false)
	_later(30.0, func() -> void:
		if is_instance_valid(p):
			p.queue_free())

# ---------------------------------------------------------------- Brandt / Abzug

func _enter_brandt() -> void:
	_set_phase("brandt")
	_objective("Brandt ist frei")
	var pv: Dictionary = _vehicles[1] if _vehicles.size() > 1 else {"x": 10.0, "z": -142.0}
	var rear := Vector3(float(pv["x"]) + 4.6, 0.0, float(pv["z"]))
	_brandt = _make_actor("friendly", "officer", rear, BRANDT_PRIMARY, BRANDT_SECONDARY, FR_ARMBAND, 0.0)
	_brandt.set("unarmed", true)
	_brandt.set("invulnerable", true)
	var van := _p("van", Vector3(-30, 0, -92))
	_brandt.call("walk_to", van + Vector3(2.5, 0, -1.5), 1.6, true)
	if _voss != null and _alive(_voss):
		_voss.set("crouch", false)
		_voss.set("aiming", false)
		_voss.call("walk_to", van + Vector3(3.5, 0, 0.5), 1.7, true)
	# Gespraech im selben Frame: jede Zeile direkt nach der vorigen
	_radio(SD.VOSS, "Brandt ist raus. Er lebt.", 3.0)
	_radio(SD.BRANDT, "Kerner? … Guter Schuss.", 3.0)
	_radio(SD.VOSS, "Schnelle Eingreiftruppe aus Velten, fünf Minuten. Alle zum Transporter am Gleis!", 4.5)

func _enter_extract() -> void:
	_set_phase("extract")
	_objective("Runter vom Turm – zum Transporter am Gleis")
	for f in _friends:
		var a: Node3D = _node(f["a"])
		if _alive(a) and a != _voss:
			a.set("crouch", false)
			a.set("aiming", false)
			var van := _p("van", Vector3(-30, 0, -92))
			a.call("walk_to", van + Vector3(rng.randf_range(-4.0, 6.0), 0, rng.randf_range(-3.0, 3.0)), 2.6, true)

func _tick_extract() -> void:
	if player == null:
		return
	var sd: Array = _arr("stair_down", [])
	var bottom: Vector3 = sd[sd.size() - 1] if not sd.is_empty() else Vector3(-44, 0, 26)
	var pp := player.global_position
	if not _qrf_spawned and pp.y < bottom.y + 3.0 and pp.distance_to(bottom) < 14.0:
		_qrf_spawned = true
		_checkpoint("cp_ground")
		_spawn_qrf()

func _spawn_qrf() -> void:
	_radio(SD.LENA, "Eingreiftruppe im Werk! Vor dir, zwischen den Hallen – kämpf dich durch!", 4.0)
	var path: Array = _arr("extract_path", [Vector3(-44, 0, 26), Vector3(-40, 0, -20), Vector3(-34, 0, -60), Vector3(-30, 0, -92)])
	var spots: Array = _arr("qrf", [])
	if spots.is_empty():
		var n: int = path.size()
		for i in 4:
			var k: float = 0.35 + 0.17 * float(i)
			var idx: int = clampi(int(k * float(n - 1)), 0, n - 1)
			var pp: Vector3 = path[idx]
			spots.append(pp + Vector3(rng.randf_range(-7.0, 7.0), 0, rng.randf_range(-6.0, -2.0)))
	var scene := load(ENEMY_PATH % "rifleman") as PackedScene
	for p in spots:
		var e := scene.instantiate() as Node3D
		e.set_meta("faction", "reich")
		e.set("accuracy_scale", 0.7)
		add_child(e)
		e.global_position = (p as Vector3) + Vector3(0, 0.1, 0)
		e.rotation.y = 0.0
		if e.has_method("alert") and player != null:
			e.call("alert", player.global_position)

func _try_end() -> void:
	if phase == "extract":
		_set_phase("done")
		_radio(SD.VOSS, "Alle drin? Los, los!", 2.5)
		_on_level_end()

# ---------------------------------------------------------------- Respawn

func _on_player_respawned() -> void:
	_ff_count = 0
	if phase == "mortar":
		_mortar_grace = 12.0
		_mortar_t = 3.0
	for key in _snipers.keys():
		var s: Dictionary = _snipers[key]
		s["stage"] = "hide"
		s["t"] = 4.0
		s["glow"] = 0.0
	if player != null and phase in ["sentries", "convoy", "ambush", "csniper", "mortar", "p2"]:
		player.call("give_weapon", "g28", 10, 60)

# ================================================================== Autopilot-Bot

func bot_drives_player() -> bool:
	return _bot_on and _ready_ok and str(Game.arg("ow-cam", "")) == ""

func bot_task() -> Dictionary:
	var p1 := _p("p1_snipe", Vector3(0, 22, 8.6))
	var p2 := _p("p2_snipe", Vector3(-42, 22, 2.8))
	var road := Vector3(10, 1, float(points.get("road_z", -140.0)))
	var on_p2: bool = player != null and player.global_position.x < -30.0 and player.global_position.y > 18.0
	match phase:
		"climb":
			var path: Array = _arr("stair_up", []).duplicate()
			path.append(p1)
			return {"kind": "walk", "path": path, "key": "climb"}
		"sentries", "sentries_done":
			var tg: Array = []
			if _mark != null and _alive(_mark) and _visible_from_cam(_mark):
				tg.append(_mark)
			return {"kind": "snipe", "pos": p1, "targets": tg, "face": _mark.global_position if _mark != null and is_instance_valid(_mark) else road}
		"convoy":
			return {"kind": "snipe", "pos": p1, "targets": [], "face": road}
		"ambush", "ambush_done":
			var tl: Array = []
			for e in _amb:
				var a: Node3D = _node(e["a"])
				if _alive(a) and not bool(a.get("has_goal")) and _visible_from_cam(a, 1.0 if bool(e["up"]) else 0.7):
					if bool(e["up"]):
						tl.push_front(a)
					else:
						tl.append(a)
			return {"kind": "snipe", "pos": p1, "targets": tl, "face": road}
		"csniper", "csniper_done":
			return _bot_sniper_task("a", p1)
		"mortar":
			if on_p2:
				return {"kind": "snipe", "pos": p2, "targets": [], "face": road}
			var gp: Array = _arr("gantry_path", [p1 + Vector3(-3.5, 0, 1.5), Vector3(-5.5, 22, 10.1), Vector3(-36.5, 22, 10.1), p2])
			var path2: Array = gp.duplicate()
			if (path2[path2.size() - 1] as Vector3).distance_to(p2) > 1.0:
				path2.append(p2)
			return {"kind": "walk", "path": path2, "key": "gantry", "sprint": true}
		"p2", "p2_done":
			return _bot_sniper_task("b", p2)
		"weber", "brandt":
			var face := road
			if not _car.is_empty() and is_instance_valid(_car["node"]):
				face = (_car["node"] as Node3D).global_position + Vector3.UP
			return {"kind": "snipe", "pos": p2, "targets": [], "face": face}
		"extract", "done":
			var sd: Array = _arr("stair_down", []).duplicate()
			var ep: Array = _arr("extract_path", [Vector3(-44, 0, 26), Vector3(-40, 0, -20), Vector3(-34, 0, -60)])
			var full: Array = []
			if player != null and player.global_position.y > 3.0:
				full.append_array(sd)
			full.append_array(ep)
			full.append(_p("van", Vector3(-30, 0, -92)))
			return {"kind": "walk", "path": full, "key": "extract_%s" % ("top" if full.size() > ep.size() + 1 else "ground"),
				"fight": true, "fight_range": 70.0, "sprint": true}
	return {"kind": "wait"}

func _bot_sniper_task(key: String, pos: Vector3) -> Dictionary:
	var tg: Array = []
	var face := pos + Vector3(0, 0, -50)
	if _snipers.has(key):
		var s: Dictionary = _snipers[key]
		var a: Node3D = _node(s["a"])
		if _alive(a):
			face = a.global_position + Vector3.UP
			face = a.global_position + Vector3.UP * 1.5
			# Erst nach dem Warnschuss zielen (Duell: Blitzen, Warnschuss, Stellungswechsel, zweites Blitzen)
			if str(s["stage"]) == "aim" and int(s["shots"]) > 0 and _visible_from_cam(a, 1.5):
				tg.append(a)
	return {"kind": "snipe", "pos": pos, "targets": tg, "face": face, "preaim": true, "aim_h": 1.5}
