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
const Pickup := preload("res://game/pickups/pickup.gd")
const SquadOrders := preload("res://game/squad/squad_orders.gd")
const Companion := preload("res://game/squad/companion.gd")
const HELI_SCENE := "res://game/vehicles/helicopter.tscn"

const C_GARDE := [Color(0.42, 0.43, 0.44), Color(0.2, 0.2, 0.22), Color(0.12, 0.12, 0.13)]
const C_LENA := [Color(0.16, 0.18, 0.2), Color(0.25, 0.24, 0.22), Color(0.45, 0.7, 0.95)]
const C_WEBER := [Color(0.1, 0.1, 0.12), Color(0.18, 0.17, 0.16), Color(0.1, 0.1, 0.12)]

const Y := 1.2               ## Wagenboden
const YR := 4.1              ## Dach
const ENTRY_Z := {2: -28.5, 3: -56.0, 6: -140.5}
const ROOF_ENTRY_Z := -81.3
const ROOF_SPOT := Vector3(0, 4.15, -85.0)
const HATCH_Z := -133.0
const HATCH_SPOT := Vector3(0.85, 1.25, -139.5)
const DEBUG_SPOT := {2: Vector3(0.6, 1.25, -24.0), 3: Vector3(0.3, 1.25, -52.5), 4: Vector3(0.1, 1.25, -66.0),
	5: Vector3(0.1, 1.25, -70.0), 6: Vector3(0.85, 1.25, -139.5), 7: Vector3(0.45, 1.25, -159.0)}
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
	env.glow_hdr_threshold = 0.9
	env.glow_intensity = 0.9
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
		["cower", Vector3(1.45, Y, -144.0), -90.0],
		["lie", Vector3(-0.92, Y, -144.35), 0.0], ["lie", Vector3(-0.92, Y, -150.95), 0.0],
	]
	var r := RandomNumberGenerator.new()
	r.seed = build_seed
	var coats := [Color(0.3, 0.22, 0.16), Color(0.2, 0.25, 0.32), Color(0.45, 0.42, 0.36), Color(0.35, 0.12, 0.12), Color(0.18, 0.28, 0.2)]
	var hairs := [Color(0.15, 0.1, 0.07), Color(0.55, 0.45, 0.3), Color(0.6, 0.6, 0.6), Color(0.08, 0.07, 0.06)]
	for i in list.size():
		var d: Array = list[i]
		var c: StaticBody3D = Civ.new()
		c.set("pose", d[0])
		c.set("coat", coats[r.randi() % coats.size()])
		c.set("hair", hairs[r.randi() % hairs.size()])
		c.set("skin", Color(0.68, 0.52, 0.42).lerp(Color(0.45, 0.32, 0.24), r.randf() * 0.6))
		c.set("level", self)
		c.name = "Reisender_%d" % (i + 1)
		world.add_child(c)
		c.position = d[1]
		c.rotation.y = deg_to_rad(float(d[2]))
		civs.append(c)
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
	add_child(e)
	e.global_position = pos + Vector3(0, 0.05, 0)
	e.rotation.y = deg_to_rad(yaw)
	e.set("accuracy_scale", acc)
	e.set("sight_range", 40.0)
	_phase_nodes.append(e)
	return e

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

func _wait_entry(z: float) -> bool:
	return await _until(func() -> bool: return _ppos().z < z, -1.0)

## P1: Abteilwagen.
func _p1() -> bool:
	_checkpoint("cp_w1")
	var es: Array = [_enemy("rifleman", Vector3(0.85, Y, -14.0), 0.35, 180.0),
		_enemy("assault", Vector3(0.5, Y, -20.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(1.0, Y, -24.0), 0.35, 180.0)]
	if not await _sleep(0.8):
		return false
	_say(SD.LENA, "Graue Mäntel im Gang! Sie haben uns erkannt!")
	_alert_all(es)
	_obj("Garde-Jäger im Abteilwagen ausschalten")
	if not await _clear(es, 75.0):
		return false
	_say(SD.LENA, "Wagen eins ist frei. Weiter zum Speisewagen.")
	return true

## P2: Speisewagen.
func _p2() -> bool:
	var es: Array = [_enemy("rifleman", Vector3(0.0, Y, -36.0), 0.4, 180.0),
		_enemy("assault", Vector3(0.3, Y, -42.0), 0.4, 180.0),
		_enemy("officer", Vector3(0.5, Y, -45.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.8, Y, -50.5), 0.4, 180.0)]
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
	_alert_all(es)
	if not await _clear(es, 80.0):
		return false
	_say(SD.KERNER, "Speisewagen sauber. Der Gepäckwagen ist als Nächstes.")
	return true

## P3: Gepaeckwagen.
func _p3() -> bool:
	var es: Array = [_enemy("heavy", Vector3(0.1, Y, -62.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(-0.2, Y, -70.0), 0.4, 180.0),
		_enemy("assault", Vector3(0.5, Y, -76.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(-0.3, Y, -79.5), 0.4, 180.0)]
	train.call("open_door", 1)
	_obj("Gepäckwagen säubern")
	if not await _wait_entry(ENTRY_Z[3]):
		return false
	_checkpoint("cp_w3")
	_top_up_ammo()
	_say(SD.LENA, "Gepäckwagen. Vorsicht, die haben einen Schweren dabei.")
	_alert_all(es)
	if not await _clear(es, 85.0):
		return false
	return true

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
	var ok: bool = await _until(func() -> bool: return not _alive(_heli), 100.0)
	if not ok:
		return false
	if _alive(_heli):
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
	_fade(1.0, 0.35)
	await get_tree().create_timer(0.4, false).timeout
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
	h.set("max_health", 320.0)
	h.set("mg_damage", 4.0)
	h.set("burst_rounds", 10)
	h.set("attack_range", 200.0)
	h.set("searchlight", true)
	h.name = "GardeHeli"
	add_child(h)
	h.global_position = Vector3(70.0, 20.0, -20.0)
	h.set_meta("priority", 40.0)
	h.call("attack", true)
	h.call("hover_at", Vector3(36.0, 15.0, -60.0))
	_phase_nodes.append(h)
	_heli_t = 3.0
	return h

func _tick_heli(delta: float) -> void:
	if _heli == null or not is_instance_valid(_heli) or not _alive(_heli):
		return
	_heli_t -= delta
	if _heli_t <= 0.0:
		_heli_t = 3.0
		_heli.call("hover_at", Vector3(randf_range(28.0, 45.0), randf_range(10.0, 22.0), -68.0 + randf_range(-25.0, 25.0)))

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
	_say(SD.LENA, "Oben ist Fahrtwind ohne Ende. Und achte auf die Tunnel – wer steht, wird abgeräumt.")
	_obj("Garde auf dem Dach ausschalten – bei Tunneln ducken oder hinlegen")
	# Welle 1 + Tunnel 1
	_roof_stage = 1
	_roof_enemies = [_enemy("rifleman", Vector3(0.6, YR, -100.0), 0.35, 180.0),
		_enemy("assault", Vector3(-0.6, YR, -104.0), 0.35, 180.0),
		_enemy("rifleman", Vector3(0.5, YR, -112.0), 0.35, 180.0)]
	var w1: Array = _roof_enemies.duplicate()
	_alert_all(w1)
	train.call("spawn_tunnel_eta", _ppos().z, 16.0)
	if not await _clear(w1, 70.0):
		return false
	if not await _until(_tunnel_passed, 30.0):
		return false
	# Welle 2 + Tunnel 2
	_say(SD.LENA, "Mehr von denen, vorn auf dem nächsten Wagen!")
	_roof_stage = 2
	var w2: Array = [_enemy("rifleman", Vector3(-0.6, YR, -122.0), 0.38, 180.0),
		_enemy("assault", Vector3(0.6, YR, -128.0), 0.38, 180.0),
		_enemy("heavy", Vector3(0.0, YR, -132.0), 0.35, 180.0)]
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
	_say(SD.LENA, "Da vorn ist eine Dachluke. Rein in den Schlafwagen!")
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
	_tunnel_layer.add_child(_tunnel_ui)

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
				_say(SD.LENA, "Tunnel voraus! Runter, sofort!")
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
			if _foot_ok():
				_say(SD.LENA, "Das war knapp.")

# ------------------------------------------------------------------ P6: Schlafwagen

func _p6() -> bool:
	if _ppos().z > HATCH_SPOT.z + 1.0 and _ppos().y < 3.0:
		_teleport(HATCH_SPOT, 0.0)
	_checkpoint("cp_w6")
	var es: Array = [_enemy("rifleman", Vector3(0.6, Y, -151.0), 0.4, 180.0),
		_enemy("assault", Vector3(0.9, Y, -156.0), 0.4, 180.0),
		_enemy("officer", Vector3(0.5, Y, -160.0), 0.4, 180.0),
		_enemy("rifleman", Vector3(0.8, Y, -162.5), 0.4, 180.0)]
	_say(SD.LENA, "Schlafwagen. Hier liegen Leute in den Betten – kein einziger Fehlschuss!")
	_obj("Schlafwagen säubern – Reisende nicht treffen")
	if not await _sleep(1.5):
		return false
	_alert_all(es)
	if not await _clear(es, 85.0):
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
			return {"kind": "walk", "key": "p1", "fight": true,
				"path": _path([Vector2(0.85, -4), Vector2(0.85, -12), Vector2(0.85, -20), Vector2(0.6, -24)])}
		2:
			if not _door(0):
				return {"kind": "walk", "key": "p2w", "fight": true, "path": _path([Vector2(0.6, -24)])}
			return {"kind": "walk", "key": "p2", "fight": true,
				"path": _path([Vector2(0.2, -25.2), Vector2(0.1, -27.5), Vector2(0.0, -34), Vector2(0.0, -40), Vector2(0.0, -45), Vector2(0.6, -48), Vector2(0.3, -53)])}
		3:
			if not _door(1):
				return {"kind": "walk", "key": "p3w", "fight": true, "path": _path([Vector2(0.3, -52.5)])}
			return {"kind": "walk", "key": "p3", "fight": true,
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
	if _bot != null and bot_drives_player():
		_bot.call("tick", delta)
