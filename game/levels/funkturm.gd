extends "res://game/levels/level.gd"
## Level 10 "Stimme der Ordnung" (funkturm): Funkturm am Messegelaende Berlin, 24.06.2030, 21:40 -- Nacht.
## Teil 4 (Garde). Vertikale Mission, Geometrie: funkturm_world.gd, Test-Bot: funkturm_bot.gd.
## Ablauf (phase):
##   messe     -> Sturm ueber die Plaza (Garde, Suchscheinwerfer, Gepanzerte)
##   climb     -> Betonkern, Innentreppe bis zur Plattform auf 18 m (Garde-Kanal: Weber gibt Falk Koordinaten)
##   gallery   -> Aussenwendel im Stahlgitter bis 60 m (Wind, Tiefblick, Stadtlichter)
##   top       -> Sendeplattform, Riedhammer spricht auf allen Frequenzen
##   hold      -> [E] am Sendepult halten, waehrend Wellen anrennen
##   broadcast -> Lena geht auf Sendung
##   heli      -> Kampfhubschrauber greift an, Panzerfaust im Sendesaal (3 Treffer)
##   descent   -> Fassadenlift runter, Countdown bis Falks Verstaerkung den Turmfuss abriegelt
##   done
## Debug: --ft-start=<phase> springt in eine Phase, --ft-cam=x,y,z,yaw,pitch setzt eine feste Kamera.

const World = preload("res://game/levels/funkturm_world.gd")
const Bot = preload("res://game/levels/funkturm_bot.gd")
const SD = preload("res://game/story/story_data.gd")

const HELI_PATH := "res://game/vehicles/helicopter.tscn"
const WIND_PATH := "res://assets/sfx/amb_wind.ogg"
const HOLD_TIME := 26.0
const HOLD_RADIUS := 2.3
const DESCENT_TIME := 90.0
const LIFT_SPEED := 4.0
const FALL_LETHAL := 9.5
const HELI_POINTS: Array[Vector3] = [Vector3(-26.0, 67.0, 36.0), Vector3(8.0, 69.0, 42.0), Vector3(-40.0, 65.0, 14.0), Vector3(-14.0, 71.0, 44.0)]

var phase: String = "messe"
var _pt: float = 0.0
var _t: float = 0.0
var _bot: RefCounted = null
var _bot_on: bool = false
var _ready_ok: bool = false
var _cam_fixed: bool = false

var _spots: Array = []
var _blink: Array = []
var _onair: Label3D = null
var _screen_mat: StandardMaterial3D = null
var _lift: Dictionary = {}
var _lift_state: String = "locked"     # locked | open | closing | down | bottom
var _lift_t: float = 0.0
var _vanguard: bool = false
var _trucks: Array = []

var hold_progress: float = 0.0
var _hold_label: Label3D = null
var _hold_obj_step: int = -1
var _hold_active: bool = false

var _heli: Node3D = null
var _heli_i: int = 0
var _heli_t: float = 0.0
var _heli_dead: bool = false

var countdown: float = -1.0
var _cd_step: int = -1
var _timeout_pending: bool = false

var _wind: AudioStreamPlayer = null
var _gust_t: float = 6.0
var _peak_y: float = 0.0
var _was_floor: bool = true
var _done: bool = false

# ================================================================== Aufbau

func _init() -> void:
	level_name = "funkturm"
	end_z = -60.0
	build_seed = 2406
	_wave_count = 10
	fog_density = 0.004
	ambient_artillery = false
	default_faction = "reich"

func get_level_info() -> Dictionary:
	var info := super.get_level_info()
	info["title"] = "Stimme der Ordnung"
	return info

func _setup_environment() -> void:
	var env := VfxEnv.make_environment(0.004, 1.0)
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.005, 0.007, 0.018)
	sm.sky_horizon_color = Color(0.11, 0.07, 0.06)       # Stadtglocke + Braende
	sm.ground_bottom_color = Color(0.01, 0.01, 0.014)
	sm.ground_horizon_color = Color(0.1, 0.065, 0.055)
	sm.sky_energy_multiplier = 1.0
	sm.sun_angle_max = 2.0
	sm.sun_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.24, 0.25, 0.36)
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_exposure = 1.15
	env.ssr_enabled = false
	env.sdfgi_enabled = true
	env.sdfgi_energy = 0.6
	env.ssil_intensity = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.065, 0.075)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0035
	env.fog_sky_affect = 0.75
	env.fog_aerial_perspective = 0.3
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.008
	env.volumetric_fog_albedo = Color(0.82, 0.83, 0.86)
	env.volumetric_fog_emission = Color(0.006, 0.005, 0.007)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.45
	env.volumetric_fog_length = 120.0
	env.volumetric_fog_gi_inject = 0.4
	env.volumetric_fog_ambient_inject = 0.1
	env.volumetric_fog_sky_affect = 0.0
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.95
	env.glow_bloom = 0.06
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
	moon.light_color = Color(0.55, 0.64, 1.0)
	moon.light_energy = 0.14
	moon.light_indirect_energy = 0.5
	moon.light_volumetric_fog_energy = 0.4
	moon.shadow_enabled = true
	moon.shadow_blur = 2.0
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	var dir := Vector3(0.35, -0.6, -0.7).normalized()
	moon.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3.ZERO)
	add_child(moon)
	VfxEnv.apply_render_quality(get_viewport())
	PostFx.apply(self, "night_city")

func _build_ground() -> void:
	World.ground(self)

func _build_street() -> void:
	var t: Dictionary = World.tower(self)
	_blink = t.get("blink", [])
	_onair = t.get("onair", null)
	_screen_mat = t.get("screen_mat", null)
	_lift = World.lift(self)
	_set_gate("deck_gate", true)
	_set_gate("exit_gate", true)

func _build_props() -> void:
	var m: Dictionary = World.messe(self)
	_spots = m.get("spots", [])

func _build_set_piece_geometry() -> void:
	pass

func _build_skyline() -> void:
	World.horizon(self)

func _build_atmosphere() -> void:
	World.atmosphere(self)

func _build_markers() -> void:
	var m := Node3D.new()
	m.name = "Markers"
	add_child(m)
	var ps := Geo.marker(m, Vector3(0, 0.1, 110.0), "player_spawn")
	ps.name = "PlayerSpawn"
	# Gegner: [typ, welle, pos]
	var spawns: Array = [
		["rifleman", 0, Vector3(-3.0, 0.05, 78.0)], ["rifleman", 0, Vector3(6.5, 0.05, 74.0)],
		["rifleman", 0, Vector3(-7.0, 0.05, 66.0)], ["armored", 0, Vector3(2.0, 0.05, 60.0)],
		["assault", 1, Vector3(4.0, 0.05, 26.0)], ["armored", 1, Vector3(-4.0, 0.05, 19.0)],
		["rifleman", 1, Vector3(8.5, 0.05, 30.0)], ["rifleman", 1, Vector3(-6.5, 0.05, 28.0)],
		["officer", 1, Vector3(0.0, 0.05, 15.0)],
		["rifleman", 2, World.corner_in(5) + Vector3(0, 0.05, 0)], ["assault", 2, World.corner_in(9) + Vector3(0, 0.05, 0)],
		["rifleman", 3, Vector3(-6.6, 18.05, -1.0)], ["rifleman", 3, Vector3(0.0, 18.05, -6.6)],
		["armored", 3, Vector3(-6.6, 18.05, 6.6)],
		["rifleman", 4, World.corner_ex(3) + Vector3(0, 0.05, 0)], ["assault", 4, World.corner_ex(5) + Vector3(0, 0.05, 0)],
		["marksman", 4, World.corner_ex(7) + Vector3(0, 0.05, 0)], ["rifleman", 4, World.corner_ex(9) + Vector3(0, 0.05, 0)],
		["rifleman", 5, Vector3(-9.5, 60.05, 9.0)], ["rifleman", 5, Vector3(9.6, 60.05, -6.0)],
		["officer", 5, Vector3(3.0, 60.05, -7.2)], ["armored", 5, Vector3(-4.0, 60.05, -6.5)],
		["rifleman", 6, Vector3(-9.6, 60.05, 4.5)], ["assault", 6, Vector3(9.6, 60.05, 9.0)],
		["rifleman", 7, Vector3(9.6, 60.05, 4.0)], ["rifleman", 7, Vector3(-9.6, 60.05, 9.5)], ["heavy", 7, Vector3(-9.6, 60.05, -4.0)],
		["assault", 8, Vector3(-9.6, 60.05, 6.0)], ["armored", 8, Vector3(9.6, 60.05, 8.0)], ["rifleman", 8, Vector3(9.6, 60.05, -2.0)],
		["rifleman", 9, Vector3(20.0, 0.05, -24.0)], ["rifleman", 9, Vector3(28.0, 0.05, -20.0)], ["assault", 9, Vector3(14.0, 0.05, -30.0)],
	]
	for i in spawns.size():
		var s: Array = spawns[i]
		var mk := Geo.marker(m, s[2] as Vector3, "enemy_spawn")
		mk.name = "EnemySpawn%d_%s" % [i, s[0]]
		mk.set_meta("enemy_type", s[0])
		mk.set_meta("wave", s[1])
	for p in covers:
		var v: Vector3 = p
		Geo.marker(m, Vector3(v.x, 0.0, v.z), "cover_point")
	# Grobe Wegpunkte (nur Info; der Level-Bot faehrt selbst)
	var wps: Array = World.route_messe() + [World.corner_in(12), World.corner_ex(12), World.HOLD_SPOT]
	for i in wps.size():
		var w := Geo.marker(m, wps[i] as Vector3, "bot_waypoint")
		w.set_meta("order", i)
	# Trigger
	_trigger("TrWave1", Vector3(0, 3, 56.0), Vector3(40, 6, 2), func() -> void:
		_checkpoint("cp_plaza")
		_spawn_wave(1)
		_say(SD.FALK, "Garde-Leitstelle an alle: Eindringlinge am Turmfuß. Haltet den Sender.", 5.0))
	_trigger("TrCore", Vector3(3.5, 1.5, 6.0), Vector3(3.0, 3.0, 2.0), _enter_climb)
	_trigger("TrDeckWave", World.corner_in(9) + Vector3(0, 1, 0), Vector3(3.2, 2.0, 3.2), func() -> void: _spawn_wave(3))
	_trigger("TrGallery", Vector3(4.6, DECK_Y + 1.0, 4.6), Vector3(3.2, 2.0, 3.2), _enter_gallery)
	_trigger("TrTopWave", World.corner_ex(9) + Vector3(0, 1, 0), Vector3(2.6, 2.0, 2.6), func() -> void: _spawn_wave(5))
	_trigger("TrTop", World.corner_ex(12) + Vector3(0, 1, 0), Vector3(2.6, 2.0, 2.6), _enter_top)
	# Panzerfaust-Set + Munitionskiste im Sendesaal
	Pickup.place_pzf_set(self, World.PZF_POS, 0.0)
	Pickup.place_ammo_crate(self, Vector3(6.0, 60.0, -1.0), 0.0)
	var area := _trigger("LevelEnd", World.TRUCK_POS + Vector3(0, 2.0, 0), Vector3(6.0, 4.0, 8.0), _on_truck, false)
	area.add_to_group("level_end")

const DECK_Y := 18.0

func _bake_nav() -> void:
	preload("res://game/systems/destructible_placements.gd").place(self)  # zerstoerbare Deckung (systeme-c), vor dem Bake
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
	nm.filter_baking_aabb = AABB(Vector3(-60.0, -1.0, -60.0), Vector3(120.0, 64.0, 184.0))
	world.navigation_mesh = nm
	world.bake_navigation_mesh(false)
	if Game.arg("navdebug", false):
		print("NAV baked: vertices=%d polygons=%d" % [nm.get_vertices().size(), nm.get_polygon_count()])

func _ready() -> void:
	await super._ready()
	if player != null:
		_peak_y = player.global_position.y
	_build_hold_label()
	_build_wind()
	Events.player_respawned.connect(_on_player_respawned)
	_bot_on = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	var cam_arg: String = str(Game.arg("ft-cam", ""))
	if _bot_on and player != null and cam_arg == "":
		_bot = Bot.new()
		_bot.call("setup", self, player)
	_ready_ok = true
	var start_ph: String = str(Game.arg("ft-start", ""))
	if start_ph != "":
		_skip_to(start_ph)
	else:
		_intro()
	if cam_arg != "" and player != null:
		var v: PackedStringArray = cam_arg.split(",")
		if v.size() >= 5:
			_cam_fixed = true
			player.global_position = Vector3(float(v[0]), float(v[1]), float(v[2]))
			player.call("set_view", float(v[3]), float(v[4]))
			player.set("external_input", true)
			player.set_physics_process(false)

# ================================================================== Hilfen

func _say(speaker: String, text: String, dur: float = 0.0) -> void:
	Events.story_radio.emit(speaker, text, dur)

var _last_objective: String = ""

func _objective(text: String) -> void:
	if text == _last_objective:
		return
	_last_objective = text
	Events.story_objective.emit(text)

func _later(t: float, f: Callable) -> void:
	get_tree().create_timer(t).timeout.connect(f)

func _set_phase(p: String) -> void:
	phase = p
	_pt = 0.0
	print("[funkturm] Phase -> %s (t=%.1f)" % [p, _t])

func _alive(n: Variant) -> bool:
	return n is Node and is_instance_valid(n) and (n as Node).has_method("is_alive") and bool((n as Node).call("is_alive"))

func _enemies_alive() -> int:
	var c := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == _heli:
			continue
		if _alive(e):
			c += 1
	return c

func _set_gate(key: String, closed: bool) -> void:
	var cs: CollisionShape3D = _lift.get(key, null)
	if cs != null:
		cs.set_deferred("disabled", not closed)
	var mi: Node3D = _lift.get(key + "_mesh", null)
	if mi != null:
		mi.visible = closed

func _lift_body() -> Node3D:
	return _lift.get("body", null)

func _in_lift(p: Vector3) -> bool:
	var b := _lift_body()
	if b == null:
		return false
	var l := p - b.global_position
	return absf(l.x) < 1.15 and absf(l.z) < 1.15 and l.y > -0.6 and l.y < 2.0

func in_hold_zone() -> bool:
	if player == null:
		return false
	var d := player.global_position - World.HOLD_SPOT
	return Vector2(d.x, d.z).length() < HOLD_RADIUS and absf(d.y) < 1.5

# ================================================================== Ablauf

func _intro() -> void:
	_set_phase("messe")
	if str(Game.arg("ft-cam", "")) == "" and player != null:
		# Zwischensequenz (game/cutscene): Kranfahrt vom Plaza-Rand den Turm hinauf, während Lena spricht.
		# Autopilot/--skip-cutscenes: sofort übersprungen (Zeile entfällt dann).
		var cs := Cutscene.new()
		cs.cut(null, {"look": Vector3(0.0, 14.0, 0.0), "fov": 55.0})
		cs.shot(null, Vector3(5.5, 9.0, 97.0), 7.0, {"look": Vector3(0.0, 58.0, -2.0), "fov": 36.0,
			"path": [Vector3(2.5, 3.5, 104.0)], "shake": 0.2, "async": true})
		cs._say(SD.LENA, "Jonas, das ist er. Der Funkturm. Von da oben spricht Riedhammer heute Nacht zu ganz Berlin.", {"dur": 6.0})
		cs.wait(0.4)
		cs.shot(null, (player as Player).get_camera(), 1.3, {"free": true, "fov": (player as Player).get_camera().fov,
			"shake": 0.0})
		await cs.play(self)
		if not is_inside_tree():
			return
	else:
		_say(SD.LENA, "Jonas, das ist er. Der Funkturm. Von da oben spricht Riedhammer heute Nacht zu ganz Berlin.", 6.0)
	_say(SD.KERNER, "Dann reden wir ihm rein. Ich geh über die Messe, du hältst den Lkw an der Ostseite warm.", 5.5)
	_say(SD.LENA, "Scheinwerfer auf der Plaza, Garde in Stellung, mindestens ein Gepanzerter. Bleib aus den Lichtkegeln.", 6.0)
	_objective("Stürm das Messegelände – zum Turmfuß")

func _enter_climb() -> void:
	if phase != "messe":
		return
	_set_phase("climb")
	_checkpoint("cp_tower")
	_spawn_wave(2)
	_objective("Die Treppe im Betonkern hoch – zur Plattform auf 18 Metern")
	_say(SD.KERNER, "Aufzug ist tot. Ich nehm die Treppe.", 3.0)
	_say(SD.LENA, "Ich hab den Garde-Kanal. Hör mal.", 3.0)
	_say(SD.WEBER, "Falk, Weber hier. Planquadrat Gustav-Sieben, Sammelpunkt der Loyalen an der Heerstraße. Zwei Kompanien, ab Mitternacht.", 7.0)
	_say(SD.FALK, "Notiert. Und Weber – Sie sind ein nützlicher Mann. Noch.", 4.5)
	_say(SD.LENA, "Das war Weber. Vor sechs Tagen ist er uns am Traunsee entwischt – und jetzt gibt er Falk Koordinaten?", 6.5)
	_say(SD.KERNER, "Falk hat Jäger auf ihn gehetzt. Jetzt reden sie miteinander. Später. Erst der Sender.", 5.5)

func _enter_gallery() -> void:
	if phase != "climb" and phase != "messe":
		return
	_set_phase("gallery")
	_checkpoint("cp_gallery")
	_spawn_wave(4)
	_objective("Über die Wartungsstege im Stahlgitter nach oben – 60 Meter")
	_say(SD.LENA, "Du bist draußen am Gitter, ich seh dich vom Lkw aus. Nicht nach unten schauen, Jonas.", 5.0)
	_later(14.0, func() -> void:
		if phase == "gallery":
			_say(SD.RIEDHAMMER, "Bürger Berlins. Die Ordnung kehrt zurück. Wer heute Nacht seine Tür verschlossen hält, hat nichts zu fürchten.", 7.0))
	_later(30.0, func() -> void:
		if phase == "gallery":
			_say(SD.LENA, "Er ist auf allen Frequenzen. Radio, Lautsprecherwagen, sogar die Straßenbahnanzeigen.", 5.0))

func _enter_top() -> void:
	if phase in ["top", "hold", "broadcast", "heli", "descent", "done"]:
		return
	_set_phase("top")
	_checkpoint("cp_top")
	_spawn_wave(5)
	_objective("In den Sendesaal – ans Sendepult")
	_say(SD.RIEDHAMMER, "Die sogenannten Loyalen sind Söldner einer fremden Macht. Meldet sie. Die Garde schützt euch.", 6.5)
	_say(SD.LENA, "Das Pult im Sendesaal. Halt den Schalter, bis ich seine Leitung überschrieben hab.", 5.0)

func _enter_hold() -> void:
	_set_phase("hold")
	_hold_active = true
	_hold_label.visible = true
	_objective("Halte [E] am Sendepult – Riedhammers Sendung unterbrechen (0 %)")
	_say(SD.LENA, "Ich bin drin. Halt durch, das dauert. Die merken das sofort.", 4.5)
	_say(SD.RIEDHAMMER, "Ab Mitternacht gilt das Standrecht. Wer sich der Garde widersetzt –", 5.0)

func _tick_hold(delta: float) -> void:
	var holding := false
	if in_hold_zone():
		if bot_drives_player():
			holding = bool(_bot.call("is_holding")) if _bot != null else true
		elif InputMap.has_action("interact") and Input.is_action_pressed("interact"):
			holding = true
	if holding and player != null and bool(player.call("is_alive")):
		hold_progress = minf(1.0, hold_progress + delta / HOLD_TIME)
	var pct := int(hold_progress * 100.0)
	if _hold_label != null:
		_hold_label.text = "SENDELEITUNG\n%d %%%s" % [pct, "" if holding else "\n[E] HALTEN"]
	if _screen_mat != null:
		var flick := 1.4 + 1.2 * hold_progress + (0.6 * sin(_t * 23.0) if holding else 0.0)
		_screen_mat.emission_energy_multiplier = flick
	var step := pct / 5
	if step != _hold_obj_step:
		_hold_obj_step = step
		_objective("Halte [E] am Sendepult – Riedhammers Sendung unterbrechen (%d %%)" % (step * 5))
	if hold_progress >= 0.1:
		_spawn_wave(6)
	if hold_progress >= 0.45 and not _waves_spawned.has(7):
		_spawn_wave(7)
		_say(SD.LENA, "Halbe Strecke. Von der Terrasse kommen noch mehr!", 3.5)
	if hold_progress >= 0.75 and not _waves_spawned.has(8):
		_spawn_wave(8)
		_say(SD.FALK, "Kappt die Leitung im Sendesaal! Sofort!", 3.5)
	if hold_progress >= 1.0:
		_enter_broadcast()

func _enter_broadcast() -> void:
	_set_phase("broadcast")
	_hold_active = false
	_checkpoint("cp_broadcast")
	if _hold_label != null:
		_hold_label.text = "LEITUNG\nÜBERNOMMEN"
	if _onair != null:
		_onair.modulate = Color(0.3, 1.0, 0.4)
	_objective("Sendung übernommen – Lena spricht")
	_say(SD.KERNER, "Sendung ist tot.", 2.5)
	_say(SD.LENA, "Meine Leitung steht. Ich geh auf Sendung.", 3.5)
	_say(SD.LENA, "Berlin, hier spricht Obergefreite Lena Aksoy. Die Ordnungsfront hat euch belogen. Bleibt in den Häusern, nicht aus Angst – sondern bis wir euch holen. Die Loyalen kommen.", 10.0)

func _enter_heli() -> void:
	_set_phase("heli")
	_objective("Kampfhubschrauber! Panzerfaust im Sendesaal – hol ihn runter (3 Treffer)")
	_say(SD.LENA, "Jonas, Hubschrauber von Westen! Im Sendesaal liegt eine Panzerfaust, Kisten daneben.", 5.0)
	_say(SD.FALK, "Kerner. Ich hab mir gedacht, dass Sie das sind. Schöne Aussicht da oben, nicht? Genießen Sie sie.", 6.5)
	_spawn_heli()

func _spawn_heli() -> void:
	if not ResourceLoader.exists(HELI_PATH):
		push_warning("funkturm: Hubschrauber-Szene fehlt")
		_later(2.0, _enter_descent)
		return
	var ps := load(HELI_PATH) as PackedScene
	var h := ps.instantiate() as Node3D
	h.set("faction", "reich")
	h.set_meta("faction", "reich")
	h.set("searchlight", true)
	h.set("mg_damage", 6.0)
	add_child(h)
	h.global_position = Vector3(-150.0, 72.0, 70.0)
	h.call("hover_at", HELI_POINTS[0])
	h.call("attack", true)
	h.call("set_searchlight", true)
	if h.has_signal("destroyed"):
		h.connect("destroyed", _on_heli_destroyed)
	_heli = h
	_heli_i = 0
	_heli_t = 0.0

func _tick_heli(delta: float) -> void:
	if _heli_dead:
		return
	if _heli == null or not is_instance_valid(_heli):
		_on_heli_destroyed()
		return
	_heli_t += delta
	if _heli_t > 9.0:
		_heli_t = 0.0
		_heli_i = (_heli_i + 1) % HELI_POINTS.size()
		_heli.call("hover_at", HELI_POINTS[_heli_i])
	if _pt > 150.0:
		# Sicherheitsnetz: brennt nach langer Zeit von allein ab (Tests ohne PZF-Treffer)
		_heli.call("take_damage", 9999.0, self, _heli.global_position, Vector3.UP)

func _on_heli_destroyed() -> void:
	if _heli_dead:
		return
	_heli_dead = true
	_say(SD.LENA, "Er ist runter! Er brennt!", 3.0)
	_later(4.0, _enter_descent)

func heli_node() -> Node3D:
	return _heli if _heli != null and is_instance_valid(_heli) and _alive(_heli) else null

func _enter_descent() -> void:
	if phase == "descent" or phase == "done":
		return
	_set_phase("descent")
	_checkpoint("cp_descent")
	countdown = DESCENT_TIME
	_cd_step = -1
	_lift_state = "open"
	_set_gate("deck_gate", false)
	_say(SD.FALK, "Alle Einheiten zum Funkturm. Riegelt den Fuß ab. Niemand kommt da runter.", 5.0)
	_say(SD.LENA, "Fassadenlift an der Ostseite! Neunzig Sekunden, Jonas, dann ist unten zu.", 5.0)

func _tick_descent(delta: float) -> void:
	if _timeout_pending:
		return
	countdown -= delta
	var s := int(ceilf(maxf(countdown, 0.0)))
	if s != _cd_step:
		_cd_step = s
		var where := "Fassadenlift (Ostseite)" if _lift_state in ["open", "closing"] else "zu Lenas Lkw (grünes Licht)"
		_objective("Runter vom Turm – %s: %d s" % [where, s])
	if countdown <= 0.0:
		_timeout_pending = true
		_say(SD.FALK, "Zu spät, Kerner.", 2.5)
		if player != null and bool(player.call("is_alive")):
			player.call("take_damage", 9999.0, self, player.global_position, Vector3.UP)
		return
	if player != null and player.global_position.distance_to(World.TRUCK_POS) < 3.5 and _lift_state == "bottom":
		_on_truck()

func _tick_lift(delta: float) -> void:
	var b := _lift_body()
	if b == null:
		return
	match _lift_state:
		"open":
			if player != null and bool(player.call("is_alive")) and _in_lift(player.global_position):
				_lift_state = "closing"
				_lift_t = 0.0
				_set_gate("deck_gate", true)
				_say(SD.KERNER, "Bin im Lift. Runter!", 2.5)
		"closing":
			_lift_t += delta
			if _lift_t > 0.8:
				_lift_state = "down"
		"down":
			var p := b.global_position
			p.y = maxf(0.0, p.y - LIFT_SPEED * delta)
			b.global_position = p
			# Spieler nicht oben "haengen" lassen (Plattform-Kontakt kann reissen)
			if player != null:
				var lp := player.global_position - p
				if absf(lp.x) < 1.15 and absf(lp.z) < 1.15 and lp.y > 0.9 and lp.y < 6.0:
					player.global_position = Vector3(player.global_position.x, p.y + 0.05, player.global_position.z)
			if p.y < 32.0 and not _vanguard:
				_vanguard = true
				_spawn_wave(9)
				_spawn_trucks()
				_say(SD.LENA, "Falks Vorhut am Fuß, Lkw von Süden! Ich geb dir Deckung!", 4.0)
			if p.y <= 0.0:
				_lift_state = "bottom"
				_set_gate("exit_gate", false)
				_show_truck_beacon()
				_say(SD.LENA, "Unten! Raus und zu mir – Lkw steht vorn links, ich blink dich an!", 3.5)

func _spawn_trucks() -> void:
	for i in 2:
		var root := Node3D.new()
		root.name = "FalkTruck%d" % i
		add_child(root)
		var body := Props.vehicle(root, Vector3.ZERO, 0.0, "truck", Color(0.16, 0.17, 0.17), false, false, [])
		body.collision_layer = 0
		for sx in [-0.7, 0.7]:
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.92, 0.75)
			sl.light_energy = 6.0
			sl.spot_range = 40.0
			sl.spot_angle = 24.0
			sl.position = Vector3(sx, 1.0, 2.4)
			sl.rotation_degrees = Vector3(-6, 180, 0)
			root.add_child(sl)
		var x := 18.0 + i * 9.0
		root.global_position = Vector3(x, 0.0, -140.0 - i * 20.0)
		var tw := create_tween()
		tw.tween_property(root, "global_position", Vector3(x, 0.0, -34.0 - i * 6.0), 9.0 + i * 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_trucks.append(root)

## Lenas Lkw unten eindeutig machen: gruene Lichtsaeule, blinkende Warnlichter und Schild "LENA" (durch Waende sichtbar).
var _beacon: Node3D = null

func _show_truck_beacon() -> void:
	if _beacon != null:
		_beacon.visible = true
		return
	_beacon = Node3D.new()
	_beacon.name = "TruckBeacon"
	add_child(_beacon)
	_beacon.global_position = World.TRUCK_POS + Vector3(2.5, 0.0, 0.0)
	var col_m := StandardMaterial3D.new()
	col_m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	col_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	col_m.albedo_color = Color(0.3, 1.0, 0.45, 0.22)
	col_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var column := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.35
	cm.height = 30.0
	column.mesh = cm
	column.material_override = col_m
	column.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	column.position = Vector3(0, 15.0 + 3.2, 0)
	_beacon.add_child(column)
	var lbl := Label3D.new()
	lbl.text = "▼ LENA"
	lbl.font_size = 48
	lbl.pixel_size = 0.004
	lbl.fixed_size = true
	lbl.no_depth_test = true
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.45, 1.0, 0.55)
	lbl.outline_size = 8
	lbl.position = Vector3(0, 4.2, 0)
	_beacon.add_child(lbl)
	var blink: Array[OmniLight3D] = []
	for sx in [-1.0, 1.0]:
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.6, 0.1)
		ol.light_energy = 3.0
		ol.omni_range = 9.0
		ol.position = Vector3(sx * 1.1, 1.0, 3.6)
		_beacon.add_child(ol)
		blink.append(ol)
	var tw := create_tween().set_loops()
	tw.tween_callback(func() -> void:
		for l in blink:
			l.visible = true)
	tw.tween_interval(0.45)
	tw.tween_callback(func() -> void:
		for l in blink:
			l.visible = false)
	tw.tween_interval(0.45)

func _on_truck() -> void:
	if phase != "descent" or _lift_state != "bottom" or _done:
		return
	if player == null or not bool(player.call("is_alive")):
		return
	_done = true
	_set_phase("done")
	_objective("Entkommen")
	_say(SD.LENA, "Drin! Halt dich fest!", 2.5)
	_say(SD.KERNER, "Fahr. Und Lena – gute Sendung.", 3.0)
	_on_level_end()

func _on_player_respawned() -> void:
	if player != null:
		_peak_y = player.global_position.y
	if phase == "descent":
		# Zurueck auf der Plattform: Lift wieder oben, Uhr neu
		_timeout_pending = false
		countdown = DESCENT_TIME
		_cd_step = -1
		var b := _lift_body()
		if b != null:
			b.global_position = Vector3(World.LIFT_X, World.TOP, 0)
		_lift_state = "open"
		_set_gate("deck_gate", false)
		_set_gate("exit_gate", true)
		if _beacon != null:
			_beacon.visible = false
		_say(SD.LENA, "Noch mal, Jonas. Der Lift ist wieder oben.", 3.0)

# ================================================================== Physik/Optik

func _physics_process(delta: float) -> void:
	if not _ready_ok:
		return
	_t += delta
	_pt += delta
	match phase:
		"top":
			if in_hold_zone() and player != null and bool(player.call("is_alive")):
				_enter_hold()
		"hold":
			_tick_hold(delta)
		"broadcast":
			if _pt > 15.0:
				_enter_heli()
		"heli":
			_tick_heli(delta)
		"descent":
			_tick_descent(delta)
	_tick_lift(delta)
	_tick_fall()
	if _bot != null and bot_drives_player():
		_bot.call("tick", delta)

func _tick_fall() -> void:
	if player == null or _cam_fixed or not bool(player.call("is_alive")):
		return
	var y := player.global_position.y
	if y < -6.0:
		player.call("take_damage", 9999.0, self, player.global_position, Vector3.UP)
		return
	if _lift_state in ["closing", "down"] and _in_lift(player.global_position):
		_peak_y = y
		return
	var on_floor: bool = (player as CharacterBody3D).is_on_floor() if player is CharacterBody3D else true
	if on_floor:
		if _peak_y - y > FALL_LETHAL:
			print("[funkturm] Absturz %.1f m" % (_peak_y - y))
			player.call("take_damage", 9999.0, self, player.global_position, Vector3.UP)
		_peak_y = y
	else:
		_peak_y = maxf(_peak_y, y)

func _process(delta: float) -> void:
	if not _ready_ok:
		return
	# Suchscheinwerfer schwenken
	for i in _spots.size():
		var sp: Node3D = _spots[i]
		if is_instance_valid(sp):
			sp.rotation.y += delta * (0.35 + 0.08 * i) * (1.0 if i % 2 == 0 else -1.0)
			sp.rotation.x = deg_to_rad(-20.0 - 7.0 * sin(_t * 0.4 + i))
	# Positionslichter am Mast blinken
	var on := fmod(_t, 1.6) < 0.5
	for n in _blink:
		if is_instance_valid(n):
			(n as Node3D).visible = on
	if _onair != null and phase in ["top", "gallery", "climb", "messe"]:
		_onair.visible = fmod(_t, 1.2) < 0.85
	elif _onair != null:
		_onair.visible = true
	_tick_wind(delta)

func _build_hold_label() -> void:
	_hold_label = Label3D.new()
	_hold_label.text = "SENDELEITUNG\n0 %"
	_hold_label.font_size = 54
	_hold_label.pixel_size = 0.005
	_hold_label.modulate = Color(1.0, 0.75, 0.3)
	_hold_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hold_label.no_depth_test = true
	_hold_label.position = World.CONSOLE + Vector3(0, 2.2, 0)
	_hold_label.visible = false
	add_child(_hold_label)

func _build_wind() -> void:
	if not ResourceLoader.exists(WIND_PATH):
		return
	var st := load(WIND_PATH) as AudioStream
	if st == null:
		return
	if st is AudioStreamOggVorbis:
		st = st.duplicate()
		(st as AudioStreamOggVorbis).loop = true
	_wind = AudioStreamPlayer.new()
	_wind.stream = st
	_wind.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	_wind.volume_db = -30.0
	add_child(_wind)
	_wind.play()

func _tick_wind(delta: float) -> void:
	if player == null:
		return
	var y := player.global_position.y
	var k := clampf(y / 60.0, 0.0, 1.0)
	if _wind != null:
		var target := lerpf(-30.0, -6.0, k)
		_wind.volume_db = lerpf(_wind.volume_db, target, clampf(delta * 1.5, 0.0, 1.0))
		_wind.pitch_scale = lerpf(0.9, 1.08, k)
	if y > 30.0 and not _cam_fixed:
		_gust_t -= delta
		if _gust_t <= 0.0:
			_gust_t = rng.randf_range(6.0, 12.0)
			if bool(player.call("is_alive")):
				player.call("add_trauma", 0.06 + 0.06 * k)
			if _wind != null:
				_wind.volume_db = minf(_wind.volume_db + 4.0, 0.0)

# ================================================================== Debug-Spruenge

func _skip_to(ph: String) -> void:
	var order: Array = ["messe", "climb", "gallery", "top", "hold", "heli", "descent"]
	var idx: int = order.find(ph)
	if idx <= 0 or player == null:
		_intro()
		return
	var pos := Vector3(3.5, 0.1, 7.5)
	match ph:
		"climb":
			pos = Vector3(3.5, 0.1, 7.5)
		"gallery":
			pos = World.corner_in(12) + Vector3(0, 0.1, 0)
		"top", "hold":
			pos = World.corner_ex(12) + Vector3(0, 0.1, 0)
		"heli", "descent":
			pos = World.HOLD_SPOT + Vector3(0, 0.1, 2.0)
	player.global_position = pos
	_peak_y = pos.y
	if idx >= 1:
		_waves_spawned[0] = true
		_waves_spawned[1] = true
		for e in get_tree().get_nodes_in_group("enemy"):
			if e is Node3D and (e as Node3D).global_position.z > 40.0:
				e.queue_free()
	match ph:
		"climb":
			_enter_climb()
		"gallery":
			_waves_spawned[2] = true
			_waves_spawned[3] = true
			_set_phase("climb")
			_enter_gallery()
		"top":
			for i in range(2, 5):
				_waves_spawned[i] = true
			_set_phase("gallery")
			_enter_top()
		"hold":
			for i in range(2, 6):
				_waves_spawned[i] = true
			_set_phase("top")
			_checkpoint("cp_top")
		"heli":
			for i in range(2, 9):
				_waves_spawned[i] = true
			hold_progress = 1.0
			_checkpoint("cp_broadcast")
			if _onair != null:
				_onair.modulate = Color(0.3, 1.0, 0.4)
			_enter_heli()
		"descent":
			for i in range(2, 9):
				_waves_spawned[i] = true
			hold_progress = 1.0
			_heli_dead = true
			_enter_descent()

# ================================================================== Autopilot

func bot_drives_player() -> bool:
	return _bot_on and _ready_ok and not _cam_fixed

func bot_task() -> Dictionary:
	match phase:
		"messe", "climb":
			var path: Array = World.route_messe() + World.route_core() + World.route_spiral() + World.route_top()
			return {"kind": "walk", "path": path, "key": "ascent", "fight": true}
		"gallery":
			var path2: Array = World.route_spiral() + World.route_top()
			return {"kind": "walk", "path": path2, "key": "gallery", "fight": true}
		"top":
			return {"kind": "walk", "path": [World.corner_ex(12)] + World.route_top(), "key": "top", "fight": true}
		"hold":
			return {"kind": "hold", "pos": World.HOLD_SPOT, "face": Vector3(0, 61.0, 6.0)}
		"broadcast":
			return {"kind": "hold", "pos": World.HOLD_SPOT, "face": Vector3(0, 61.0, 6.0)}
		"heli":
			return {"kind": "heli", "heli": heli_node(), "pzf": World.PZF_POS, "crate": World.PZF_POS + Vector3(0, 0, 1.3), "spot": World.HELI_SPOT}
		"descent":
			if _lift_state == "bottom":
				var b := _lift_body()
				var lp: Vector3 = b.global_position if b != null else Vector3(World.LIFT_X, 0, 0)
				return {"kind": "walk", "path": [lp + Vector3(0, 0, 0.6), lp + Vector3(0, 0, 3.0), Vector3(20.0, 0, 20.0), World.TRUCK_POS], "key": "exfil", "fight": false, "sprint": true}
			if _lift_state in ["closing", "down"]:
				return {"kind": "ride"}
			return {"kind": "walk", "path": [Vector3(0, 60, 1.0), Vector3(0, 60, 3.4), Vector3(9.6, 60, 3.4), Vector3(9.8, 60, 0.0), Vector3(World.LIFT_X, 60, 0.0)], "key": "tolift", "fight": false, "sprint": true}
	return {"kind": "wait"}
