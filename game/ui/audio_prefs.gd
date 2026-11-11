extends Node
## Audio-Optionen: Lautstaerke pro Bus (Settings "audio/<bus>", linear 0..1, Standard 1.0) und
## Daempfung waehrend der Pause (Tiefpass + leiser auf Effekten/Umgebung).
## Wird von Game nach dem Start als Kind "AudioPrefs" angelegt. Die Grundlautstaerke aus
## default_bus_layout.tres (z. B. Ambient -3 dB) bleibt der Bezug: Regler 100 % = Layout-Wert.

## Settings-Schluessel -> Busname
const BUSES := {"audio/master": "Master", "audio/music": "Music", "audio/sfx": "SFX",
	"audio/voice": "Voice", "audio/ambient": "Ambient"}
const PAUSE_BUSES := ["SFX", "Ambient", "Music"]
const PAUSE_DB := -9.0
const PAUSE_CUTOFF := 900.0

var _base_db: Dictionary = {}       # Bus -> Layout-Lautstaerke
var _duck: float = 0.0              # 0..1 Pausen-Daempfung
var _duck_target: float = 0.0
var _filters: Dictionary = {}       # Bus -> AudioEffectLowPassFilter (erst bei der ersten Pause angelegt)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in BUSES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx >= 0:
			_base_db[BUSES[key]] = AudioServer.get_bus_volume_db(idx)
	var settings := get_node_or_null("/root/Settings")
	if settings != null:
		settings.connect("changed", _on_setting)
	_apply_all()
	set_process(false)


static func has_bus(bus: String) -> bool:
	return AudioServer.get_bus_index(bus) >= 0


## Regler (0..1) -> dB: Amplitude ~ v^2 (wahrnehmungsnah: 50 % ~ -12 dB, 10 % ~ -40 dB), 0 = stumm.
static func slider_to_db(v: float) -> float:
	if v <= 0.001:
		return -80.0
	return linear_to_db(v * v)


func _on_setting(key: String, _value) -> void:
	if BUSES.has(key):
		_apply_all()


func _apply_all() -> void:
	var settings := get_node_or_null("/root/Settings")
	for key in BUSES:
		var bus: String = BUSES[key]
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var v := 1.0
		if settings != null:
			var raw = settings.call("get_value", key, 1.0)
			v = clampf(float(raw) if raw != null else 1.0, 0.0, 1.0)
		var db: float = float(_base_db.get(bus, 0.0)) + slider_to_db(v)
		if bus in PAUSE_BUSES:
			db += PAUSE_DB * _duck
		AudioServer.set_bus_volume_db(idx, db)
		AudioServer.set_bus_mute(idx, v <= 0.001)


## Pausenmenue: Effekte/Umgebung dumpf und leiser (sanft ueberblendet).
func set_paused(on: bool) -> void:
	_duck_target = 1.0 if on else 0.0
	if on:
		_ensure_filters()
	set_process(true)


func _ensure_filters() -> void:
	for bus in PAUSE_BUSES:
		if _filters.has(bus):
			continue
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var f := AudioEffectLowPassFilter.new()
		f.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(idx, f)
		AudioServer.set_bus_effect_enabled(idx, AudioServer.get_bus_effect_count(idx) - 1, false)
		_filters[bus] = f


func _process(delta: float) -> void:
	_duck = move_toward(_duck, _duck_target, delta * 4.0)
	for bus in _filters:
		var idx := AudioServer.get_bus_index(bus)
		if idx < 0:
			continue
		var f: AudioEffectLowPassFilter = _filters[bus]
		f.cutoff_hz = lerpf(20000.0, PAUSE_CUTOFF, sqrt(_duck))
		for i in AudioServer.get_bus_effect_count(idx):
			if AudioServer.get_bus_effect(idx, i) == f:
				AudioServer.set_bus_effect_enabled(idx, i, _duck > 0.001)
	_apply_all()
	if is_equal_approx(_duck, _duck_target):
		set_process(false)
