class_name EnemyVoice
extends RefCounted
## Gegner-Zurufe ("Barks"): feste Stimme pro Gegner, Wahrscheinlichkeiten, globaler Cooldown,
## max. gleichzeitige Rufe, 3D-positioniert. Dateien: res://assets/voice/barks/<faction>_<voice>_<situation>_<n>.ogg
## (erzeugt mit tools/gen_barks.py). Fehlen die Dateien, fallen hit/death/spot selten auf die alten SFX zurueck.

const DIR := "res://assets/voice/barks/"
const REGULAR_VOICES := {"ru": ["v1", "v2", "v3", "v4", "v5"], "reich": ["v1", "v2", "v3"]}
const OFFICER_VOICE := "off"
const MAX_ACTIVE := 2            ## gleichzeitig hoerbare Rufe
const GLOBAL_GAP := 1.1          ## s zwischen zwei beliebigen Rufen
const URGENT_GAP := 0.35         ## Granate/Befehle duerfen enger folgen
const ENEMY_GAP := 3.5           ## s pro Gegner
const MAX_HEAR_DIST := 65.0
## Situation -> [Wahrscheinlichkeit, Situations-Cooldown s, dringend]
const RULES := {
	"spot": [0.55, 5.0, false],
	"reload": [0.3, 7.0, false],
	"grenade": [0.9, 2.5, true],
	"cover": [0.22, 6.0, false],
	"advance": [0.3, 6.0, false],
	"flank": [0.55, 6.0, false],
	"hit": [0.3, 2.5, false],
	"death": [0.28, 1.5, false],
	"mandown": [0.6, 5.0, false],
	"lost": [0.35, 8.0, false],
	"order_advance": [0.95, 4.0, true],
	"order_flank": [0.95, 4.0, true],
	"order_reinf": [1.0, 4.0, true],
	"order_mark": [0.95, 4.0, true],
}
## Alte, einheitliche Schrei-Sounds nur noch als seltene Variante (bzw. Ersatz, falls keine Barks da sind).
const LEGACY := {"hit": "enemy_hurt", "death": "enemy_death", "spot": "enemy_alert"}
const LEGACY_CHANCE := 0.1

static var _files: Dictionary = {}       # "ru_v1_spot" -> Array[String]
static var _streams: Dictionary = {}
static var _active: Array[AudioStreamPlayer3D] = []
static var _last_any: float = -100.0
static var _last_sit: Dictionary = {}
static var _rr: Dictionary = {}          # Fraktion -> naechster Stimmen-Index (Rundlauf -> Vielfalt in einer Welle)
static var _rng := RandomNumberGenerator.new()
static var _seeded := false

static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

## Feste Stimme fuer einen Gegner (Meta "voice"; vom Level/Test vorbelegbar).
static func assign(e: Node, officer: bool) -> void:
	if not _seeded:
		_seeded = true
		_rng.randomize()
	var fac := str(e.get_meta("faction", "ru"))
	if not REGULAR_VOICES.has(fac):
		fac = "ru"
	if not e.has_meta("voice"):
		if officer:
			e.set_meta("voice", OFFICER_VOICE)
		else:
			var list: Array = REGULAR_VOICES[fac]
			var i: int = _rr.get(fac, _rng.randi() % list.size())
			_rr[fac] = (i + 1 + (_rng.randi() % 2)) % list.size()
			e.set_meta("voice", list[i % list.size()])
	if not e.has_meta("voice_pitch"):
		e.set_meta("voice_pitch", _rng.randf_range(0.97, 1.03))

static func _list(fac: String, voice: String, situation: String) -> Array:
	var key := "%s_%s_%s" % [fac, voice, situation]
	if _files.has(key):
		return _files[key]
	var out: Array = []
	for n in range(1, 10):
		var p := "%s%s_%d.ogg" % [DIR, key, n]
		if not ResourceLoader.exists(p):
			break
		out.append(p)
	_files[key] = out
	return out

static func _stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	return _streams[path]

static func _prune() -> void:
	var keep: Array[AudioStreamPlayer3D] = []
	for p in _active:
		if is_instance_valid(p) and p.playing:
			keep.append(p)
	_active = keep

## Versucht einen Ruf. chance_mul skaliert die Grundwahrscheinlichkeit (0 = nie, >1 = haeufiger).
## Gibt true zurueck, wenn tatsaechlich etwas abgespielt wird.
static func bark(e: Node3D, situation: String, chance_mul: float = 1.0, force: bool = false) -> bool:
	if e == null or not is_instance_valid(e) or not e.is_inside_tree():
		return false
	if not e.has_meta("voice"):
		return false
	var rule: Array = RULES.get(situation, [0.3, 5.0, false])
	var now := _now()
	var urgent: bool = rule[2]
	if not force:
		if _rng.randf() > float(rule[0]) * chance_mul:
			return false
		if now - _last_any < (URGENT_GAP if urgent else GLOBAL_GAP):
			return false
		if now - float(_last_sit.get(situation, -100.0)) < float(rule[1]):
			return false
		if now - float(e.get_meta("voice_last", -100.0)) < ENEMY_GAP and situation != "death":
			return false
	var cam := e.get_viewport().get_camera_3d() if e.get_viewport() != null else null
	if cam != null and cam.global_position.distance_to(e.global_position) > MAX_HEAR_DIST:
		return false
	_prune()
	if _active.size() >= MAX_ACTIVE:
		if not urgent:
			return false
		var oldest: AudioStreamPlayer3D = _active.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	var fac := str(e.get_meta("faction", "ru"))
	var voice := str(e.get_meta("voice"))
	var files := _list(fac, voice, situation)
	if files.is_empty() and voice == OFFICER_VOICE and not situation.begins_with("order_"):
		files = _list(fac, "v1", situation)
	var stream: AudioStream = null
	var legacy := false
	if LEGACY.has(situation) and (files.is_empty() or _rng.randf() < LEGACY_CHANCE):
		var lp := "res://assets/sfx/%s.ogg" % LEGACY[situation]
		if ResourceLoader.exists(lp):
			stream = _stream(lp)
			legacy = true
	if stream == null and not files.is_empty():
		var last_i: int = int(e.get_meta("voice_last_i_" + situation, -1))
		var i := _rng.randi() % files.size()
		if files.size() > 1 and i == last_i:
			i = (i + 1) % files.size()
		e.set_meta("voice_last_i_" + situation, i)
		stream = _stream(files[i])
	if stream == null:
		return false
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = &"SFX"
	p.unit_size = 9.0
	p.max_distance = MAX_HEAR_DIST
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = -3.0 if legacy else 1.5
	p.pitch_scale = float(e.get_meta("voice_pitch", 1.0)) * _rng.randf_range(0.985, 1.015)
	p.position = Vector3.UP * 1.6
	e.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	_active.append(p)
	_last_any = now
	_last_sit[situation] = now
	e.set_meta("voice_last", now)
	return true
