extends Node
## Welt-Sounds (Kind von VFX). Besitzer: VFX-Agent.
## - Explosionen mit Schall-Laufzeit (Distanz / 343 m/s), Tiefpass ueber Distanz, Daempfung, Fern-Variante.
## - Einschlaege (Beton/Metall), Querschlaeger, Vorbeiflug (play_whiz).
## - Ambient-Bett (Wind + entferntes Gefecht, 2D, Bus "Ambient"), gelegentlich Sirene aus der Ferne.
##   Startet automatisch, sobald Feuer (Gruppe "vfx_fire") im Baum sind, und blendet aus, wenn keine mehr da sind.
## Busse: siehe res://default_bus_layout.tres (Master / SFX / Ambient).

const SPEED_OF_SOUND := 343.0
const POOL_SIZE := 28
const BUS_SFX := &"SFX"
const BUS_AMB := &"Ambient"

const EXPLOSIONS := ["explosion", "explosion_2", "explosion_3", "explosion_4"]
const IMPACT_SETS := {
	"concrete": ["impact_concrete", "impact_concrete_2", "impact_concrete_3"],
	"stone": ["impact_concrete", "impact_concrete_2", "impact_concrete_3"],
	"wood": ["impact_concrete_2", "impact_concrete_3"],
	"metal": ["impact_metal", "impact_metal_2", "impact_metal_3"],
}
const RICOCHETS := ["ricochet", "ricochet_2"]
const WHIZZES := ["bullet_whiz", "bullet_whiz_2", "bullet_whiz_3"]

var enabled := true
var _cache := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _impact_budget := 0.0           # begrenzt Einschlag-Sounds pro Sekunde
var _amb: Array[AudioStreamPlayer] = []
var _amb_on := false
var _amb_check := 0.0
var _siren_t := 0.0
var _siren: AudioStreamPlayer3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = BUS_SFX
		_pool.append(p)
		add_child(p)
	for n in ["amb_wind", "amb_battle"]:
		var a := AudioStreamPlayer.new()
		a.bus = BUS_AMB
		a.stream = _stream(n, true)
		a.volume_db = -80.0
		_amb.append(a)
		add_child(a)
	_siren = AudioStreamPlayer3D.new()
	_siren.bus = BUS_AMB
	_siren.unit_size = 160.0
	_siren.max_distance = 1200.0
	_siren.attenuation_filter_cutoff_hz = 2500.0
	add_child(_siren)
	_siren_t = randf_range(25.0, 50.0)

func _stream(sfx_name: String, loop: bool = false) -> AudioStream:
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var s: AudioStream = null
	var path := "res://assets/sfx/%s.ogg" % sfx_name
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
		if loop and s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
	_cache[sfx_name] = s
	return s

func _listener_pos() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	return cam.global_position if cam != null else Vector3.INF

## Allgemeiner 3D-One-Shot aus dem Pool (Bus SFX).
func play_3d(sfx_name: String, pos: Vector3, volume_db: float = 0.0, unit_size: float = 10.0, max_dist: float = 120.0, pitch: float = 1.0, cutoff_hz: float = 20500.0) -> AudioStreamPlayer3D:
	if not enabled or not is_inside_tree():
		return null
	var s := _stream(sfx_name)
	if s == null:
		return null
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stop()
	p.stream = s
	p.global_position = pos
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = max_dist
	p.pitch_scale = pitch
	p.attenuation_filter_cutoff_hz = cutoff_hz
	p.attenuation_filter_db = -24.0
	p.play()
	return p

# --- Explosionen ---------------------------------------------------------------

## Explosionsknall mit Laufzeit-Verzoegerung und Luftdaempfung (Hoehen gehen mit der Distanz verloren).
func explosion(pos: Vector3, scale: float = 1.0) -> void:
	if not enabled:
		return
	var lp := _listener_pos()
	var d := 0.0 if lp == Vector3.INF else lp.distance_to(pos)
	var sfx: String = EXPLOSIONS[randi() % EXPLOSIONS.size()]
	var s := clampf(scale, 0.3, 3.0)
	# Tiefpass: nah ~20 kHz, 100 m ~3 kHz, 300 m ~700 Hz
	var cutoff := clampf(20000.0 * exp(-d / 52.0), 650.0, 20500.0)
	# groessere Explosionen tiefer, ferne etwas tiefer (wirkt dumpfer)
	var pitch := randf_range(0.93, 1.05) * lerpf(1.06, 0.84, clampf((s - 0.5) / 2.5, 0.0, 1.0)) * lerpf(1.0, 0.9, clampf(d / 250.0, 0.0, 1.0))
	var vol := linear_to_db(clampf(0.55 + s * 0.35, 0.3, 1.6))
	var delay := d / SPEED_OF_SOUND
	if delay < 0.02:
		play_3d(sfx, pos, vol, 18.0 * s, 900.0, pitch, cutoff)
		return
	get_tree().create_timer(delay, false).timeout.connect(func() -> void:
		play_3d(sfx, pos, vol, 18.0 * s, 900.0, pitch, cutoff))

# --- Einschlaege / Querschlaeger / Vorbeiflug ----------------------------------

func impact(pos: Vector3, surface: String) -> void:
	if not enabled or not IMPACT_SETS.has(surface):
		return
	if _impact_budget > 10.0:
		return
	_impact_budget += 1.0
	var names: Array = IMPACT_SETS[surface]
	play_3d(names[randi() % names.size()], pos, -4.0, 4.0, 45.0, randf_range(0.9, 1.12))
	var chance := 0.2 if surface == "metal" else (0.08 if surface == "concrete" or surface == "stone" else 0.0)
	if randf() < chance:
		play_3d(RICOCHETS[randi() % RICOCHETS.size()], pos, -6.0, 6.0, 60.0, randf_range(0.88, 1.15))

## Vorbeiflug-Pfeifen an einer Position (typisch: naechster Punkt der Flugbahn zur Kamera).
func whiz(pos: Vector3) -> void:
	play_3d(WHIZZES[randi() % WHIZZES.size()], pos, -2.0, 2.0, 18.0, randf_range(0.9, 1.15))

## Prueft eine Flugbahn from->to und pfeift, wenn sie naeher als max_dist an der Kamera vorbeigeht.
func whiz_along(from: Vector3, to: Vector3, max_dist: float = 3.5) -> bool:
	var lp := _listener_pos()
	if lp == Vector3.INF:
		return false
	var seg := to - from
	var l2 := seg.length_squared()
	if l2 < 0.01:
		return false
	var t := clampf((lp - from).dot(seg) / l2, 0.0, 1.0)
	if t <= 0.02 or t >= 0.995:
		return false
	var c := from + seg * t
	if c.distance_to(lp) > max_dist:
		return false
	whiz(c)
	return true

# --- Ambient --------------------------------------------------------------------

func _process(delta: float) -> void:
	_impact_budget = maxf(_impact_budget - delta * 12.0, 0.0)
	_amb_check -= delta
	if _amb_check <= 0.0:
		_amb_check = 1.0
		var want := enabled and get_tree().get_nodes_in_group("vfx_fire").size() > 0
		if want != _amb_on:
			set_ambient(want)
	if _amb_on:
		_siren_t -= delta
		if _siren_t <= 0.0:
			_siren_t = randf_range(70.0, 140.0)
			_distant_siren()

## Ambient-Bett ein-/ausblenden (Wind + fernes Gefecht).
func set_ambient(on: bool, fade: float = 3.0) -> void:
	_amb_on = on
	var vols := [-5.0, -4.0]
	for i in _amb.size():
		var a := _amb[i]
		if a.stream == null:
			continue
		if on and not a.playing:
			a.play(randf() * 20.0)
		var tw := a.create_tween()
		tw.tween_property(a, "volume_db", vols[i] if on else -80.0, fade)
		if not on:
			tw.tween_callback(a.stop)

func _distant_siren() -> void:
	var lp := _listener_pos()
	var st := _stream("amb_siren")
	if lp == Vector3.INF or st == null or _siren.playing:
		return
	var ang := randf() * TAU
	_siren.stream = st
	_siren.global_position = lp + Vector3(cos(ang), 0.0, sin(ang)) * 260.0 + Vector3(0, 20, 0)
	_siren.pitch_scale = randf_range(0.96, 1.03)
	_siren.volume_db = 2.0
	_siren.play()

## Beim Beenden alle Wiedergaben stoppen (sonst haelt der AudioServer Playbacks -> Leak-Meldungen).
func _exit_tree() -> void:
	for p in _pool:
		p.stop()
		p.stream = null
	for a in _amb:
		a.stop()
		a.stream = null
	if _siren:
		_siren.stop()
		_siren.stream = null
	_cache.clear()
	# Der Audio-Thread entfernt gestoppte Playbacks erst beim naechsten Mix-Schritt.
	OS.delay_msec(60)
