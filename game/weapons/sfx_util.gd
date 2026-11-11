class_name Sfx
extends RefCounted
## SFX-Lader: liefert null, wenn res://assets/sfx/<name>.ogg|.wav fehlt (dann bleibt alles stumm).
## Varianten: <name>_2, <name>_3, ... werden automatisch gefunden und zufällig gewählt.

const MAX_VARIANTS: int = 8

static var _cache: Dictionary = {}   # name -> Array[AudioStream]

static func _load_one(base: String) -> AudioStream:
	for ext in ["ogg", "wav"]:
		var path := "res://assets/sfx/%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			return load(path) as AudioStream
	return null

static func get_variants(sfx_name: String) -> Array:
	if sfx_name == "":
		return []
	if _cache.has(sfx_name):
		return _cache[sfx_name]
	var list: Array = []
	var first := _load_one(sfx_name)
	if first:
		list.append(first)
	for i in range(2, MAX_VARIANTS + 1):
		var v := _load_one("%s_%d" % [sfx_name, i])
		if v == null:
			break
		list.append(v)
	_cache[sfx_name] = list
	return list

## Zufällige Variante (oder null).
static func get_stream(sfx_name: String) -> AudioStream:
	var list := get_variants(sfx_name)
	if list.is_empty():
		return null
	return list[randi() % list.size()]

## Spielt einen Sound auf dem gegebenen Player (falls Datei vorhanden).
## pitch_jitter: +- Tonhöhe; vol_jitter_db: +- Lautstärke in dB.
static func play_on(player: AudioStreamPlayer3D, sfx_name: String, pitch_jitter: float = 0.0,
		vol_jitter_db: float = 0.0, vol_offset_db: float = 0.0) -> void:
	var s := get_stream(sfx_name)
	if s == null or player == null:
		return
	player.stream = s
	player.bus = &"SFX"
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = vol_offset_db + randf_range(-vol_jitter_db, vol_jitter_db)
	player.play()
