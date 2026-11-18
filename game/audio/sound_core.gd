class_name SoundCore
extends Node
## Zentrales Klang-System (Sound-Overhaul v0.6). Wird von world_audio.gd (Kind von VFX) angelegt und lebt
## damit ueber alle Level. Andere Skripte rufen es nur ueber `if SoundCore.I: SoundCore.I.xxx(...)` auf –
## fehlt es, bleibt das alte Verhalten bestehen.
## - Raum-Sonde an der Kamera (drinnen/draussen, Raumgroesse) -> Hall auf dem SFX-Bus + Wahl der Schuss-Fahne.
## - Spieler-Schuss: Hall-Fahne (draussen/drinnen) zusaetzlich zum Nahknall.
## - Gegner-Schuss: Nah-Knall mit Varianz, Schall-Laufzeit, Luftdaempfung, Verdeckung und Fern-Schicht.
## - Einschlaege nach Material (Meta "surface", sonst Namen/Material-/Texturpfade, sonst Level-Vorgabe).
## - Schritte nach Untergrund fuer Spieler und Gegner, Ausruestungsrascheln beim Sprinten/Landen.
## - Explosionen: Nah-/Truemmer-/Fernschicht, Taubheit (Tiefpass + Tinnitus) bei nahen Explosionen.
## - Herzschlag bei wenig Leben, Level-Ambience (Aussen-Bett + Raumton, nach Innen/Aussen ueberblendet), UI-Klicks.

static var I: SoundCore = null

const SPEED_OF_SOUND := 343.0
const LAYER_WORLD := 1

## Level -> [Bodenart (Gelaende), Standard-Material, Aussen-Bett, Bett-dB, Innen-Raumton, Raumton-dB]
const LEVELS := {
	"baltic_night": ["dirt", "concrete", "ambience/forest_night", -8.0, "ambience/room_tone", -10.0],
	"test_range": ["dirt", "concrete", "ambience/wind_strong", -14.0, "ambience/room_tone", -10.0],
	"river_crossing": ["dirt", "concrete", "ambience/forest_night", -10.0, "ambience/room_tone", -10.0],
	"rail_yard": ["dirt", "concrete", "ambience/city_night", -8.0, "ambience/hall_tone", -8.0],
	"berlin": ["concrete", "concrete", "ambience/city_night", -10.0, "ambience/hall_tone", -8.0],
	"curfew": ["concrete", "concrete", "ambience/city_night", -8.0, "ambience/room_tone", -9.0],
	"ep_lena": ["concrete", "concrete", "ambience/city_night", -7.0, "ambience/room_tone", -9.0],   # Curfew-Daecher
	"overwatch": ["dirt", "concrete", "ambience/wind_strong", -14.0, "ambience/machine_hum", -8.0],
	"gunship": ["dirt", "concrete", "", 0.0, "", 0.0],
	"hafen": ["concrete", "concrete", "ambience/city_night", -12.0, "ambience/machine_hum", -9.0],
	"alpenpass": ["snow", "concrete", "ambience/wind_strong", -8.0, "ambience/room_tone", -10.0],
	"nachtzug": ["dirt", "metal", "", 0.0, "", 0.0],
	"villa": ["grass", "concrete", "ambience/forest_night", -12.0, "ambience/room_tone", -9.0],
	"spreebogen": ["concrete", "concrete", "ambience/city_night", -8.0, "ambience/hall_tone", -8.0],
	"funkturm": ["concrete", "concrete", "ambience/wind_strong", -10.0, "ambience/machine_hum", -9.0],
	"kanalisation": ["concrete", "concrete", "ambience/cave", -8.0, "ambience/drain", -7.0],
	"kanzleramt": ["concrete", "concrete", "ambience/city_night", -10.0, "ambience/hall_tone", -7.0],
	"bunker": ["concrete", "concrete", "ambience/cave", -10.0, "ambience/machine_hum", -8.0],
}

## Innenboden je Level (Schritte drinnen, wenn nur der Aussen-Standard erkannt wurde).
const INDOOR_FLOOR := {"villa": "wood", "baltic_night": "wood", "alpenpass": "wood", "river_crossing": "wood", "nachtzug": "carpet"}
## Level, deren Sammel-Collider pauschal ein Material tragen, innen aber anders klingen (Nachtzug: TrainCol = metal,
## drinnen Gangteppich/Abteilboden) -> Schritte drinnen immer INDOOR_FLOOR.
const INDOOR_FORCE := {"nachtzug": true}
## Benannte Collider je Level ohne Material-Hinweis (Runde 2, aus --soundlog).
const NAME_SURFACE := {
	"overwatch": {"P1Tower": "metal", "P1Stairs": "metal", "Gantry": "metal", "P2Deck": "metal", "P2Stairs": "metal"},
	"river_crossing": {"Span1": "concrete", "Spans23": "concrete"},   # Betonfahrbahn der Stahlbruecke
}

## Schluesselwoerter in Knotennamen / Material- / Texturpfaden -> Untergrund (erste Uebereinstimmung gewinnt).
const KEYWORDS := [
	["water", "water"], ["wasser", "water"], ["puddle", "water"],
	["glass", "glass"], ["window", "glass"], ["fenster", "glass"],
	["snow", "snow"], ["schnee", "snow"], ["alpine", "snow"],
	["carpet", "carpet"], ["teppich", "carpet"],
	["grass", "grass"], ["lawn", "grass"], ["leaf", "grass"], ["leafy", "grass"], ["vegetation", "grass"], ["rasen", "grass"], ["moss", "grass"],
	["mud", "mud"], ["schlamm", "mud"],
	["wood", "wood"], ["plank", "wood"], ["parquet", "wood"], ["timber", "wood"], ["holz", "wood"], ["crate", "wood"], ["pallet", "wood"], ["bark", "wood"],
	["metal", "metal"], ["rust", "metal"], ["steel", "metal"], ["container", "metal"], ["blech", "metal"], ["wagon", "metal"], ["vehicle", "metal"], ["car_", "metal"],
	["dirt", "dirt"], ["soil", "dirt"], ["ground", "dirt"], ["terrain", "dirt"], ["gravel", "dirt"], ["river", "dirt"], ["sand", "dirt"], ["forest", "dirt"], ["rock", "concrete"],
	["concrete", "concrete"], ["brick", "concrete"], ["asphalt", "concrete"], ["plaster", "concrete"], ["stone", "concrete"], ["tile", "concrete"], ["facade", "concrete"], ["beton", "concrete"],
]

## Untergrund -> Einschlag-Satz
const IMPACT_OF := {"concrete": "concrete", "stone": "concrete", "brick": "concrete", "metal": "metal", "wood": "wood",
	"dirt": "dirt", "grass": "dirt", "snow": "dirt", "mud": "dirt", "sand": "dirt", "carpet": "wood",
	"glass": "glass", "flesh": "flesh", "blood": "flesh", "water": "water"}
## Untergrund -> Schritt-Satz
const STEP_OF := {"concrete": "concrete", "stone": "concrete", "brick": "concrete", "metal": "metal", "wood": "wood",
	"dirt": "dirt", "grass": "grass", "snow": "snow", "mud": "mud", "sand": "dirt", "carpet": "carpet",
	"glass": "concrete", "water": "water", "flesh": "dirt"}

var enabled := true
var indoor := 0.0             ## 0 draussen .. 1 drinnen (geglaettet)
var room := 0.5               ## 0 eng .. 1 grosse Halle (geglaettet)

var _level := ""
var _ground := "dirt"
var _default := "concrete"
var _surf_cache := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _flat: Array[AudioStreamPlayer] = []
var _flat_i := 0
var _ui: Array[AudioStreamPlayer] = []
var _ui_i := 0
var _ui_last := 0
var _amb_out: AudioStreamPlayer
var _amb_in: AudioStreamPlayer
var _amb_out_db := -80.0
var _amb_in_db := -80.0
var _amb_fade := 0.0
var _tinnitus: AudioStreamPlayer
var _reverb: AudioEffectReverb
var _deaf_sfx: AudioEffectLowPassFilter
var _deaf_amb: AudioEffectLowPassFilter
var _deaf_tw: Tween
var _probe_t := 0.0
var _level_t := 0.0
var _impact_budget := 0.0
var _last_shot_ms := 0
var _heart_t := 0.0
var _steps := {}              ## Gegner-ID -> [letzte Position, Strecke]
var _step_list: Array = []
var _step_scan := 0.0
var _probe_dirs: Array[Vector3] = []
var _sphere := SphereShape3D.new()
var _stats := {}             ## --soundlog: Zaehler je Ereignis/Material
var _log := false

func _ready() -> void:
	I = self
	_log = bool(Game.arg("soundlog", false))
	for i in 24:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.attenuation_filter_db = -24.0
		_pool.append(p)
		add_child(p)
	for i in 6:
		var f := AudioStreamPlayer.new()
		f.bus = &"SFX"
		_flat.append(f)
		add_child(f)
	for i in 3:
		var u := AudioStreamPlayer.new()
		u.bus = &"Master"
		u.process_mode = Node.PROCESS_MODE_ALWAYS
		_ui.append(u)
		add_child(u)
	_amb_out = _mk_amb()
	_amb_in = _mk_amb()
	_tinnitus = AudioStreamPlayer.new()
	_tinnitus.bus = &"Master"
	add_child(_tinnitus)
	for i in 8:
		var a := TAU * float(i) / 8.0
		_probe_dirs.append(Vector3(cos(a), 0.0, sin(a)))
	_sphere.radius = 0.08
	_setup_bus_fx()
	var tree := get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)

func _mk_amb() -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.bus = &"Ambient"
	a.volume_db = -80.0
	add_child(a)
	return a

func _setup_bus_fx() -> void:
	var sfx := AudioServer.get_bus_index(&"SFX")
	if sfx >= 0:
		_reverb = AudioEffectReverb.new()
		_reverb.dry = 1.0
		_reverb.wet = 0.03
		_reverb.room_size = 0.3
		_reverb.damping = 0.6
		_reverb.hipass = 0.25
		_reverb.predelay_msec = 20.0
		AudioServer.add_bus_effect(sfx, _reverb)
		_deaf_sfx = AudioEffectLowPassFilter.new()
		_deaf_sfx.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(sfx, _deaf_sfx)
		AudioServer.set_bus_effect_enabled(sfx, AudioServer.get_bus_effect_count(sfx) - 1, false)
	var amb := AudioServer.get_bus_index(&"Ambient")
	if amb >= 0:
		_deaf_amb = AudioEffectLowPassFilter.new()
		_deaf_amb.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(amb, _deaf_amb)
		AudioServer.set_bus_effect_enabled(amb, AudioServer.get_bus_effect_count(amb) - 1, false)

func _set_fx_enabled(bus: StringName, fx: AudioEffect, on: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or fx == null:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) == fx:
			AudioServer.set_bus_effect_enabled(idx, i, on)
			return

func _remove_fx(bus: StringName, fx: AudioEffect) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or fx == null:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) == fx:
			AudioServer.remove_bus_effect(idx, i)
			return

func _exit_tree() -> void:
	if I == self:
		I = null
	if _log:
		print("[soundcore] ", _stats)
	_remove_fx(&"SFX", _reverb)
	_remove_fx(&"SFX", _deaf_sfx)
	_remove_fx(&"Ambient", _deaf_amb)
	for p in _pool:
		p.stop()
		p.stream = null
	for f in _flat + _ui + [_amb_out, _amb_in, _tinnitus]:
		(f as AudioStreamPlayer).stop()
		(f as AudioStreamPlayer).stream = null

# ------------------------------------------------------------------ Hilfen

func _cam() -> Camera3D:
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null

func _listener() -> Vector3:
	var c := _cam()
	return c.global_position if c != null else Vector3.INF

func _space() -> PhysicsDirectSpaceState3D:
	var vp := get_viewport()
	if vp == null or vp.world_3d == null:
		return null
	return vp.world_3d.direct_space_state

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var sp := _space()
	if sp == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return sp.intersect_ray(q)

## 3D-One-Shot (zufaellige Variante ueber Sfx).
func play3d(sfx_name: String, pos: Vector3, vol_db: float = 0.0, unit: float = 8.0, max_d: float = 80.0,
		pitch: float = 1.0, cutoff: float = 20500.0) -> AudioStreamPlayer3D:
	if not enabled or not is_inside_tree():
		return null
	_count(sfx_name)
	var s := Sfx.get_stream(sfx_name)
	if s == null:
		return null
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stop()
	p.stream = s
	p.global_position = pos
	p.volume_db = vol_db
	p.unit_size = unit
	p.max_distance = max_d
	p.pitch_scale = pitch
	p.attenuation_filter_cutoff_hz = cutoff
	p.play()
	return p

## Nicht-raeumlicher One-Shot (Spieler-eigene Geraeusche).
func play_flat(sfx_name: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not enabled:
		return
	_count(sfx_name)
	var s := Sfx.get_stream(sfx_name)
	if s == null:
		return
	var f := _flat[_flat_i]
	_flat_i = (_flat_i + 1) % _flat.size()
	f.stop()
	f.stream = s
	f.volume_db = vol_db
	f.pitch_scale = pitch
	f.play()

func _count(key: String) -> void:
	if _log:
		_stats[key] = int(_stats.get(key, 0)) + 1
		if not key.begins_with("probe") and Sfx.get_variants(key).is_empty():
			_stats["FEHLT " + key] = int(_stats.get("FEHLT " + key, 0)) + 1

func _later(delay: float, cb: Callable) -> void:
	if delay < 0.015:
		cb.call()
	else:
		get_tree().create_timer(delay, false).timeout.connect(cb)

# ------------------------------------------------------------------ Untergrund

func _norm_surface(s: String) -> String:
	s = s.to_lower()
	return s if STEP_OF.has(s) or IMPACT_OF.has(s) else _default

## Untergrund eines Colliders (gecacht).
func surface_of(col: Object) -> String:
	var s := _surface_raw(col)
	return _default if s == "?" else s

func _surface_raw(col: Object) -> String:
	if col == null or not is_instance_valid(col):
		return "?"
	var id := col.get_instance_id()
	if _surf_cache.has(id):
		return _surf_cache[id]
	var s := _classify(col)
	if _log:
		_stats["cls %s <- %s" % [s, str((col as Node).get_path()).right(60) if col is Node else "?"]] = 1
	if _surf_cache.size() > 4000:
		_surf_cache.clear()
	_surf_cache[id] = s
	return s

func _classify(col: Object) -> String:
	var n := col as Node
	if n == null:
		return _default
	var k := n
	for i in 5:
		if k == null:
			break
		if k.has_meta("surface"):
			return _norm_surface(str(k.get_meta("surface")))
		k = k.get_parent()
	if n is CollisionObject3D:
		var co := n as CollisionObject3D
		for o in co.get_shape_owners():
			if co.shape_owner_get_shape_count(o) > 0 and co.shape_owner_get_shape(o, 0) is HeightMapShape3D:
				return _ground
	var named: Dictionary = NAME_SURFACE.get(_level, {})
	if named.has(str(n.name)):
		return named[str(n.name)]
	var text := ""
	k = n
	var sc := get_tree().current_scene if is_inside_tree() else null
	for i in 4:
		# Level-Wurzel (z. B. "RiverCrossing") und Szene nicht mitlesen: der Levelname ist kein Material
		if k == null or k == sc or (sc != null and k.get_parent() == sc):
			break
		text += " " + str(k.name)
		k = k.get_parent()
	text += _mat_text(n)
	# Nur eindeutige Nachbarn auswerten: grosse Sammel-Collider (ganze Level-Geometrie) haben viele Meshes,
	# deren Materialien nichts ueber die getroffene Stelle sagen -> dann Level-Standard.
	var par := n.get_parent()
	if par != null:
		if par is GeometryInstance3D:
			text += _mat_text(par)
		var sib := _geo_children(par, n)
		if sib.size() <= 2:
			for c in sib:
				text += _mat_text(c)
	var own := _geo_children(n, null)
	if own.size() <= 3:
		for c in own:
			text += _mat_text(c)
	text = text.to_lower()
	for kw in KEYWORDS:
		if text.contains(kw[0]):
			if _log:
				_stats["kw " + str(kw[0])] = int(_stats.get("kw " + str(kw[0]), 0)) + 1
			return kw[1]
	return "?"   # nicht erkannt -> Aufrufer entscheidet (Level-Standard / Boden)

func _geo_children(n: Node, skip: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c != skip and c is GeometryInstance3D:
			out.append(c)
			if out.size() > 6:
				break
	return out

func _mat_text(n: Node) -> String:
	var t := ""
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			t += " " + mi.mesh.resource_path + " " + mi.mesh.resource_name
			for i in mini(mi.mesh.get_surface_count(), 3):
				t += _mat_path(mi.get_active_material(i))
		t += _mat_path(mi.material_override)
	elif n is CSGShape3D:
		t += _mat_path(n.get("material") as Material)
		t += _mat_path((n as CSGShape3D).material_override)
	elif n is GeometryInstance3D:
		t += _mat_path((n as GeometryInstance3D).material_override)
	return t

func _mat_path(m: Material) -> String:
	if m == null:
		return ""
	var t := " " + m.resource_path + " " + m.resource_name
	if m is BaseMaterial3D:
		var tex := (m as BaseMaterial3D).albedo_texture
		if tex != null:
			t += " " + tex.resource_path
	elif m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		if sh != null:
			t += " " + sh.resource_path
	return t

## Untergrund an einem Punkt (kleine Kugel-Abfrage).
func surface_at(pos: Vector3) -> String:
	var sp := _space()
	if sp == null:
		return _default
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _sphere
	q.transform = Transform3D(Basis(), pos)
	q.collision_mask = LAYER_WORLD
	var res := sp.intersect_shape(q, 1)
	if res.is_empty():
		return _ground
	return surface_of(res[0].get("collider"))

func surface_below(pos: Vector3) -> String:
	var r := _ray(pos + Vector3.UP * 0.3, pos + Vector3.DOWN * 1.6)
	if r.is_empty():
		return _ground
	var s := _surface_raw(r.get("collider"))
	if indoor > 0.6 and INDOOR_FORCE.has(_level) and s != "water" and s != "flesh":
		return INDOOR_FLOOR.get(_level, s)
	if s != "?":
		return s
	# Unbekannter (meist Sammel-)Collider: draussen = Level-Boden, drinnen = Innenboden des Levels.
	return INDOOR_FLOOR.get(_level, _default) if indoor > 0.6 else _ground

# ------------------------------------------------------------------ Einschlaege

## Ersetzt world_audio.impact: Material-Satz + Querschlaeger. "concrete" ist der Aufrufer-Standard,
## daher wird dann am Punkt nachgesehen.
func impact(pos: Vector3, surface: String) -> void:
	if not enabled or _impact_budget > 10.0:
		return
	_impact_budget += 1.0
	var s := surface.to_lower()
	if s == "" or s == "concrete":
		s = surface_at(pos)
	var set_name: String = IMPACT_OF.get(s, "concrete")
	var d := 0.0
	var lp := _listener()
	if lp != Vector3.INF:
		d = lp.distance_to(pos)
	var cutoff := clampf(20000.0 * exp(-d / 45.0), 1500.0, 20500.0)
	play3d("impacts/" + set_name, pos, -2.0, 5.0, 60.0, randf_range(0.92, 1.08), cutoff)
	var chance := 0.22 if set_name == "metal" else (0.08 if set_name == "concrete" else 0.0)
	if randf() < chance:
		play3d("ricochet", pos, -5.0, 6.0, 70.0, randf_range(0.9, 1.12))

# ------------------------------------------------------------------ Schuesse

## Spieler-Schuss (weapon.gd): Hall-Fahne passend zur Umgebung.
func player_shot(w: Node) -> void:
	if not enabled or w == null:
		return
	var now := Time.get_ticks_msec()
	var auto := now - _last_shot_ms < 160
	_last_shot_ms = now
	var supp := bool(w.get("suppressed"))
	var launcher := w.has_method("is_launcher") and bool(w.call("is_launcher"))
	var kind := str(w.get("model_kind"))
	var vol := -3.0 if auto else 0.0
	if supp:
		vol -= 16.0
	elif kind == "pistol":
		vol -= 3.0
	if launcher:
		vol += 3.0
	var tail := "weapons/tail_in" if indoor > 0.5 else "weapons/tail_out"
	play_flat(tail, vol + (1.0 if indoor > 0.5 else 0.0), randf_range(0.95, 1.05))
	if launcher:
		# Rueckstrahl: Gasstrahl nach hinten, rauschender Abklang (drinnen lauter/kuerzer wirkend)
		play_flat("weapons/pzf_backblast", -3.0 + (2.0 if indoor > 0.5 else 0.0), randf_range(0.95, 1.04))

## Gegner-Schuss: true = behandelt (Aufrufer spielt dann nichts mehr).
func npc_shot(sfx_name: String, pos: Vector3) -> bool:
	if not enabled or not is_inside_tree():
		return false
	if Sfx.get_variants(sfx_name).is_empty():
		return false
	var lp := _listener()
	var d := 0.0 if lp == Vector3.INF else lp.distance_to(pos)
	var far_mix := smoothstep(15.0, 80.0, d)
	var occl := false
	if lp != Vector3.INF and d > 3.0 and d < 160.0:
		occl = not _ray(lp, pos).is_empty()
	var cutoff := clampf(20000.0 * exp(-d / 70.0), 2200.0, 20500.0)
	var vol := linear_to_db(maxf(1.0 - far_mix * 0.8, 0.05)) + randf_range(-1.2, 1.2)
	if occl:
		cutoff = minf(cutoff, 1400.0)
		vol -= 6.0
	var mg := sfx_name.begins_with("enemy_mg")
	var pitch := randf_range(0.96, 1.04)
	var delay := d / SPEED_OF_SOUND if d > 15.0 else 0.0
	_later(delay, func() -> void:
		play3d(sfx_name, pos, vol, 12.0, 250.0, pitch, cutoff)
		if far_mix > 0.05:
			play3d("weapons/far_rifle", pos, linear_to_db(far_mix) + (2.0 if mg else 0.0) - (4.0 if occl else 0.0),
				60.0, 900.0, randf_range(0.94, 1.05), clampf(16000.0 * exp(-d / 220.0), 1200.0, 20500.0))
		if d < 60.0 and randf() < (0.45 if indoor > 0.5 else 0.25):
			play3d("weapons/tail_in" if indoor > 0.5 else "weapons/tail_out", pos, -10.0 - d * 0.1, 20.0, 300.0, randf_range(0.95, 1.05), cutoff))
	return true

# ------------------------------------------------------------------ Explosionen

## Ersetzt world_audio.explosion.
func explosion(pos: Vector3, scale: float = 1.0) -> void:
	if not enabled:
		return
	var lp := _listener()
	var d := 0.0 if lp == Vector3.INF else lp.distance_to(pos)
	var s := clampf(scale, 0.3, 3.0)
	var cutoff := clampf(20000.0 * exp(-d / 52.0), 650.0, 20500.0)
	var pitch := randf_range(0.93, 1.05) * lerpf(1.06, 0.84, clampf((s - 0.5) / 2.5, 0.0, 1.0)) * lerpf(1.0, 0.92, clampf(d / 250.0, 0.0, 1.0))
	var vol := linear_to_db(clampf(0.55 + s * 0.35, 0.3, 1.6))
	var far_mix := smoothstep(40.0, 220.0, d)
	var delay := d / SPEED_OF_SOUND
	_later(delay, func() -> void:
		if far_mix < 0.97:
			play3d("explosion", pos, vol + linear_to_db(maxf(1.0 - far_mix, 0.03)), 18.0 * s, 900.0, pitch, cutoff)
		if far_mix > 0.05:
			play3d("explosions/far", pos, vol + linear_to_db(far_mix) - 1.0, 80.0 * s, 2500.0, randf_range(0.9, 1.05), 20500.0)
		if d < 70.0:
			_later(randf_range(0.18, 0.35), func() -> void:
				play3d("explosions/debris", pos, -3.0 + (s - 1.0) * 3.0, 8.0 * s, 90.0, randf_range(0.9, 1.1), cutoff)))
	var reach := 12.0 * s
	if d < reach:
		deafen(1.0 - d / reach)

## Taubheit nach naher Explosion: Tiefpass auf SFX/Ambient, der sich oeffnet, dazu Tinnitus.
func deafen(k: float) -> void:
	k = clampf(k, 0.0, 1.0)
	if k < 0.05 or _deaf_sfx == null:
		return
	var dur := 1.2 + 3.0 * k
	var start := lerpf(2600.0, 380.0, k)
	if _deaf_tw != null and _deaf_tw.is_valid():
		_deaf_tw.kill()
		start = minf(start, _deaf_sfx.cutoff_hz)
	_set_fx_enabled(&"SFX", _deaf_sfx, true)
	_set_fx_enabled(&"Ambient", _deaf_amb, true)
	_deaf_sfx.cutoff_hz = start
	if _deaf_amb:
		_deaf_amb.cutoff_hz = start
	_deaf_tw = create_tween()
	_deaf_tw.tween_method(_set_deaf_cutoff, start, 20000.0, dur).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_deaf_tw.tween_callback(func() -> void:
		_set_fx_enabled(&"SFX", _deaf_sfx, false)
		_set_fx_enabled(&"Ambient", _deaf_amb, false))
	var st := Sfx.get_stream("foley/tinnitus")
	if st != null:
		_tinnitus.stream = st
		_tinnitus.volume_db = linear_to_db(0.2 + 0.8 * k) - 4.0
		_tinnitus.pitch_scale = randf_range(0.97, 1.03)
		_tinnitus.play()

func _set_deaf_cutoff(v: float) -> void:
	if _deaf_sfx:
		_deaf_sfx.cutoff_hz = v
	if _deaf_amb:
		_deaf_amb.cutoff_hz = v

# ------------------------------------------------------------------ Schritte

## Spieler-Schritt (player.gd). true = behandelt.
func player_step(pl: Node3D) -> bool:
	if not enabled or pl == null:
		return false
	var surf: String = STEP_OF.get(surface_below(pl.global_position), "concrete")
	var sprint := bool(pl.get("_sprinting"))
	var stance := int(pl.get("stance")) if pl.get("stance") != null else 0
	var vol := 0.0
	if sprint:
		vol += 2.0
	elif stance == 1:
		vol -= 6.0
	play_flat("footsteps/" + surf, vol + randf_range(-1.5, 1.0), randf_range(0.94, 1.06))
	if sprint and randf() < 0.6:
		play_flat("foley/gear", randf_range(-3.0, 0.0), randf_range(0.92, 1.08))
	return true

## Landung (player.gd). fall_speed positiv in m/s. true = behandelt.
func player_land(pl: Node3D, fall_speed: float) -> bool:
	if not enabled or pl == null:
		return false
	var surf: String = STEP_OF.get(surface_below(pl.global_position), "concrete")
	var k := clampf((fall_speed - 3.0) / 7.0, 0.0, 1.0)
	play_flat("foley/land", lerpf(-6.0, 1.0, k), randf_range(0.95, 1.05))
	play_flat("footsteps/" + surf, lerpf(0.0, 3.0, k), randf_range(0.85, 0.95))
	play_flat("foley/gear", lerpf(-4.0, 0.0, k), randf_range(0.9, 1.05))
	return true

func _enemy_steps(delta: float) -> void:
	var lp := _listener()
	if lp == Vector3.INF:
		return
	_step_scan -= delta
	if _step_scan <= 0.0:
		_step_scan = 0.3
		var cand: Array = []
		for e in get_tree().get_nodes_in_group("enemy"):
			if not (e is CharacterBody3D) or e is Drone or not (e as Node).is_inside_tree():
				continue
			if str((e as Node).scene_file_path).contains("juggernaut"):
				continue
			if e.has_method("is_alive") and not bool(e.call("is_alive")):
				continue
			var dd := lp.distance_squared_to((e as Node3D).global_position)
			if dd < 900.0:
				cand.append([dd, e])
		cand.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		_step_list.clear()
		for i in mini(cand.size(), 8):
			_step_list.append(cand[i][1])
	var keep := {}
	for e in _step_list:
		if not is_instance_valid(e):
			continue
		var cb := e as CharacterBody3D
		var id := cb.get_instance_id()
		keep[id] = true
		var p := cb.global_position
		if not _steps.has(id):
			_steps[id] = [p, 0.0]
			continue
		var st: Array = _steps[id]
		var dv: Vector3 = p - st[0]
		dv.y = 0.0
		st[0] = p
		var spd := dv.length() / maxf(delta, 0.001)
		if not cb.is_on_floor() or spd < 0.5 or spd > 12.0:
			continue
		st[1] = float(st[1]) + dv.length()
		var stride := 2.0 if spd > 4.0 else 1.5
		if float(st[1]) >= stride:
			st[1] = 0.0
			var surf: String = STEP_OF.get(surface_below(p), "concrete")
			var vol := lerpf(-4.0, 1.0, clampf((spd - 1.5) / 4.0, 0.0, 1.0))
			play3d("footsteps/" + surf, p, vol, 3.0, 32.0, randf_range(0.9, 1.08))
	for id in _steps.keys():
		if not keep.has(id):
			_steps.erase(id)

# ------------------------------------------------------------------ Ambience / Umgebung

func _process(delta: float) -> void:
	_impact_budget = maxf(_impact_budget - delta * 12.0, 0.0)
	_level_t -= delta
	if _level_t <= 0.0:
		_level_t = 1.0
		_check_level()
	_heartbeat(delta)
	# Raumton/Bett nach drinnen/draussen ueberblenden
	if _amb_out.playing:
		_amb_out.volume_db = _amb_out_db + linear_to_db(maxf(1.0 - indoor * 0.85, 0.02)) + _fade_db()
	if _amb_in.playing:
		_amb_in.volume_db = _amb_in_db + linear_to_db(maxf(indoor, 0.02)) + _fade_db()
	_amb_fade = minf(_amb_fade + delta / 3.0, 1.0)

func _fade_db() -> float:
	return linear_to_db(maxf(_amb_fade, 0.001))

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = 0.25
		_probe()
	_enemy_steps(delta)
	_veh_tick(delta)

# ------------------------------------------------------------------ Skript-Fahrzeuge (Lkw/Wagen ohne eigenen Klang)
## Bewegte Kulissen-Fahrzeuge (overwatch-Konvoi, funkturm-Lkw) bekommen automatisch einen Dieselmotor;
## Drehzahl und Lautstaerke folgen der gemessenen Geschwindigkeit, nach Stillstand Leerlauf, dann aus.
const VEH_PREFIXES := ["Truck_", "FalkTruck", "WeberCar"]
var _vehs: Array = []

func _veh_maybe(n: Node) -> void:
	if not (n is Node3D) or n.get_class() != "Node3D":
		return
	var nm := str(n.name)
	for pre in VEH_PREFIXES:
		if nm.begins_with(pre):
			_veh_attach.call_deferred(n)
			return

func _veh_attach(n: Node3D) -> void:
	if not is_instance_valid(n) or not n.is_inside_tree() or n.has_meta("_sc_veh"):
		return
	var st := Sfx.get_stream("veh_truck_engine")
	if st == null:
		return
	n.set_meta("_sc_veh", true)
	st = st.duplicate()
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	var car := str(n.name).begins_with("WeberCar")
	var p := AudioStreamPlayer3D.new()
	p.name = "SC_Engine"
	p.stream = st
	p.bus = &"SFX"
	p.unit_size = 6.0 if car else 10.0
	p.max_distance = 140.0 if car else 200.0
	p.attenuation_filter_cutoff_hz = 7000.0
	p.volume_db = -80.0
	p.position = Vector3(0.0, 1.0, 0.0)
	n.add_child(p)
	_vehs.append({"n": n, "p": p, "last": n.global_position, "spd": 0.0, "still": 0.0, "car": car})

func _veh_tick(delta: float) -> void:
	if _vehs.is_empty() or delta <= 0.0:
		return
	for i in range(_vehs.size() - 1, -1, -1):
		var v: Dictionary = _vehs[i]
		var n: Node3D = v["n"] as Node3D if is_instance_valid(v["n"]) else null
		var p: AudioStreamPlayer3D = v["p"] as AudioStreamPlayer3D if is_instance_valid(v["p"]) else null
		if n == null or p == null or not n.is_inside_tree():
			_vehs.remove_at(i)
			continue
		var pos := n.global_position
		var raw := pos.distance_to(v["last"]) / delta
		v["last"] = pos
		var spd: float = lerpf(float(v["spd"]), minf(raw, 40.0), clampf(delta * 3.0, 0.0, 1.0))
		v["spd"] = spd
		# Wrack (Konvoi-Lkw nach der IED: gekippt) -> Motor tot
		if absf(n.rotation.x) > 0.03 or absf(n.rotation.z) > 0.03:
			p.stop()
			_vehs.remove_at(i)
			continue
		v["still"] = float(v["still"]) + delta if spd < 0.4 else 0.0
		var k := clampf(spd / 12.0, 0.0, 1.0)
		var car: bool = v["car"]
		var vol := lerpf(-9.0, -1.0, k) - (5.0 if car else 0.0)
		if float(v["still"]) > 8.0:
			vol += -60.0 * clampf((float(v["still"]) - 8.0) / 2.0, 0.0, 1.0)
		if vol < -55.0:
			if p.playing:
				p.stop()
			continue
		if not p.playing:
			p.play(randf() * 6.0)
		p.volume_db = lerpf(p.volume_db, vol, clampf(delta * 4.0, 0.0, 1.0)) if p.volume_db > -70.0 else vol - 12.0
		p.pitch_scale = (1.18 if car else 0.9) + k * 0.35

## Raum-Sonde: Decke ueber der Kamera + 8 waagerechte Strahlen -> drinnen/draussen und Raumgroesse.
func _probe() -> void:
	var lp := _listener()
	if lp == Vector3.INF:
		return
	var up := not _ray(lp, lp + Vector3.UP * 25.0).is_empty()
	var hits := 0
	var sum := 0.0
	for dir in _probe_dirs:
		var r := _ray(lp, lp + dir * 30.0)
		if r.is_empty():
			sum += 30.0
		else:
			hits += 1
			sum += lp.distance_to(r["position"])
	var enclosed := float(hits) / 8.0
	var target_in := 0.0
	if up:
		target_in = clampf((enclosed - 0.25) / 0.5, 0.0, 1.0)
	var target_room := clampf((sum / 8.0 - 3.0) / 22.0, 0.0, 1.0)
	indoor = lerpf(indoor, target_in, 0.35)
	if _log:
		_count("probe_in" if indoor > 0.5 else "probe_out")
	room = lerpf(room, target_room, 0.3)
	if _reverb != null:
		_reverb.wet = lerpf(0.035, 0.1 + 0.14 * room, indoor)
		_reverb.room_size = lerpf(0.25, 0.35 + 0.5 * room, indoor)
		_reverb.damping = lerpf(0.75, 0.45, indoor)
		_reverb.predelay_msec = lerpf(45.0, 8.0 + 30.0 * room, indoor)

func _check_level() -> void:
	var sc := get_tree().current_scene
	var lvl := ""
	if sc != null:
		var v: Variant = sc.get("_level_name")
		if v != null:
			lvl = str(v)
	var in_game := get_tree().get_first_node_in_group("player") != null
	if not in_game:
		lvl = ""
	if lvl == _level:
		return
	_level = lvl
	_surf_cache.clear()
	_steps.clear()
	_step_list.clear()
	var cfg: Array = LEVELS.get(lvl, ["dirt", "concrete", "", 0.0, "", 0.0])
	_ground = cfg[0]
	_default = cfg[1]
	_set_bed(_amb_out, cfg[2])
	_set_bed(_amb_in, cfg[4])
	_amb_out_db = cfg[3]
	_amb_in_db = cfg[5]
	_amb_fade = 0.0

func _set_bed(a: AudioStreamPlayer, sfx_name: String) -> void:
	a.stop()
	a.volume_db = -80.0
	if sfx_name == "":
		a.stream = null
		return
	var s := Sfx.get_stream(sfx_name)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	a.stream = s
	if s != null:
		a.play(randf() * 8.0)

## Herzschlag bei < 35 % Leben (schneller und lauter, je weniger Leben).
func _heartbeat(delta: float) -> void:
	_heart_t -= delta
	if _heart_t > 0.0:
		return
	_heart_t = 0.5
	var pl := get_tree().get_first_node_in_group("player")
	if pl == null:
		return
	var hp: Variant = pl.get("health")
	var mx: Variant = pl.get("max_health")
	if hp == null or mx == null or float(mx) <= 0.0:
		return
	var r := float(hp) / float(mx)
	if r <= 0.0 or r >= 0.35 or bool(pl.get("dead")):
		return
	var k := 1.0 - r / 0.35
	play_flat("foley/heartbeat", lerpf(-8.0, 0.0, k), randf_range(0.98, 1.02))
	_heart_t = lerpf(0.95, 0.55, k)

# ------------------------------------------------------------------ UI

func _on_node_added(n: Node) -> void:
	_veh_maybe(n)
	if n is BaseButton:
		var b := n as BaseButton
		if b.has_meta("_sc_ui"):
			return
		b.set_meta("_sc_ui", true)
		b.pressed.connect(_ui_press)
		b.mouse_entered.connect(_ui_hover.bind(b))

func _ui_play(sfx_name: String, vol: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _ui_last < 45:
		return
	_ui_last = now
	var s := Sfx.get_stream(sfx_name)
	if s == null:
		return
	var u := _ui[_ui_i]
	_ui_i = (_ui_i + 1) % _ui.size()
	u.stream = s
	u.volume_db = vol
	u.pitch_scale = randf_range(0.97, 1.03)
	u.play()

func _ui_press() -> void:
	_ui_play("ui/click", -4.0)

## Hover entschaerft (Runde 2): nur wenn der Zeiger kurz auf dem Knopf verweilt (kein Ton beim Darueberwischen),
## hoechstens alle 0.22 s, derselbe Knopf nicht erneut binnen 1.2 s, und leiser.
var _hover_last_ms := 0
var _hover_last_btn := 0
var _hover_last_btn_ms := 0

func _ui_hover(b: BaseButton) -> void:
	if not is_instance_valid(b) or not is_inside_tree():
		return
	get_tree().create_timer(0.09, true).timeout.connect(_ui_hover_dwell.bind(b))

func _ui_hover_dwell(b: BaseButton) -> void:
	if not is_instance_valid(b) or b.disabled or not b.is_visible_in_tree() or not b.is_hovered():
		return
	var now := Time.get_ticks_msec()
	if now - _hover_last_ms < 220:
		return
	var id := b.get_instance_id()
	if id == _hover_last_btn and now - _hover_last_btn_ms < 1200:
		return
	_hover_last_ms = now
	_hover_last_btn = id
	_hover_last_btn_ms = now
	_ui_play("ui/hover", -13.0)
