extends Node
## Breach-Zeitlupe (wiederverwendbar, Runde 7). Ein Knoten pro Level; start(sekunden) loest ein kurzes
## Zeitlupen-Fenster aus. Die Dauer zaehlt in "Basis-Sekunden" (so wie das Spiel ohne Zeitlupe laeuft).
##
## Regeln:
## - relativ zur Basis-Zeitskala: Sim-Zeitraffer (DebugServer, z. B. 4x) bleibt erhalten -> 4x * Faktor
## - pausen-sicher: PROCESS_MODE_ALWAYS; solange der Baum pausiert ist (Pause-Menue), gilt die Basis-Skala,
##   nach dem Fortsetzen geht die Zeitlupe weiter (Restdauer bleibt)
## - stellt die Basis-Skala sicher zurueck: Ende, stop(), Tod, Respawn, Verlassen des Baums (Levelwechsel,
##   Neustart, Hauptmenue - main.goto_level setzt zusaetzlich selbst 1.0)
## Optik: leichte Blau-Vignette + Herzschlag; Audio laeuft gedehnt (AudioServer.playback_speed_scale).

signal started
signal ended

@export var factor: float = 0.3          ## Zeitskala waehrend der Zeitlupe (relativ zur Basis)
@export var ramp_out: float = 0.35       ## Basis-Sekunden zum Ausblenden am Ende

var active: bool = false
var _base: float = 1.0
var _left: float = 0.0                   ## Restdauer in Basis-Sekunden
var _applied: float = -1.0               ## zuletzt gesetzte Skala (Fremdaenderung erkennen)
var _was_paused: bool = false
var _foreign: float = 0.0
var _layer: CanvasLayer
var _tint: ColorRect
var _beat: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Events.player_died.connect(stop)
	Events.player_respawned.connect(stop)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	add_child(_layer)
	_tint = ColorRect.new()
	_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.25, 0.75, length(d) * 1.25);
	COLOR = vec4(0.55, 0.7, 1.0, (0.05 + v * 0.38) * amount);
}"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_tint.material = sm
	_tint.visible = false
	_layer.add_child(_tint)

func _exit_tree() -> void:
	_restore()

## Zeitlupe fuer `seconds` Basis-Sekunden. Laeuft schon eine, wird nur verlaengert.
func start(seconds: float, f: float = -1.0) -> void:
	if f > 0.0:
		factor = clampf(f, 0.05, 1.0)
	if active:
		_left = maxf(_left, seconds)
		return
	if get_tree() == null or get_tree().paused:
		return
	_base = Engine.time_scale
	active = true
	_left = seconds
	_was_paused = false
	_apply(factor)
	_tint.visible = true
	_play_beat()
	started.emit()

## Sofort beenden und die Basis-Skala wiederherstellen.
func stop() -> void:
	if not active:
		return
	_restore()
	ended.emit()

func remaining() -> float:
	return _left if active else 0.0

func _restore() -> void:
	if active:
		# Nur zuruecksetzen, wenn niemand sonst die Skala inzwischen geaendert hat
		if _applied < 0.0 or is_equal_approx(Engine.time_scale, _applied) or Engine.time_scale < _base:
			Engine.time_scale = _base
		AudioServer.playback_speed_scale = 1.0
	active = false
	_applied = -1.0
	_left = 0.0
	if _tint != null:
		_tint.visible = false
	if _beat != null and is_instance_valid(_beat):
		_beat.queue_free()
	_beat = null

func _apply(f: float) -> void:
	_applied = maxf(_base * f, 0.01)
	Engine.time_scale = _applied
	AudioServer.playback_speed_scale = lerpf(1.0, 0.62, clampf((1.0 - f) / (1.0 - factor + 0.0001), 0.0, 1.0))

func _process(delta: float) -> void:
	if not active:
		return
	var tree := get_tree()
	if tree.paused:
		# Pause-Menue: normale Skala, damit Menue-Tweens/Uebergaenge normal laufen
		if not _was_paused:
			_was_paused = true
			Engine.time_scale = _base
			_applied = _base
			AudioServer.playback_speed_scale = 1.0
		return
	if _was_paused:
		_was_paused = false
	# Fremdaenderung (z. B. Bullet-Cam, DebugServer): nicht dagegen arbeiten. Dauert sie laenger als
	# ~1 s Echtzeit, gilt sie als neue Basis und die Zeitlupe endet ohne Zuruecksetzen.
	if _applied > 0.0 and not is_equal_approx(Engine.time_scale, _applied):
		_foreign += delta / maxf(Engine.time_scale, 0.01)
		if _foreign > 1.0:
			_applied = -1.0
			_base = Engine.time_scale
			_restore()
			ended.emit()
		return
	_foreign = 0.0
	var scale_now := maxf(Engine.time_scale / maxf(_base, 0.0001), 0.01)
	_left -= delta / scale_now
	if _left <= 0.0:
		stop()
		return
	_apply(_cur_factor())
	var sm := _tint.material as ShaderMaterial
	sm.set_shader_parameter("amount", clampf(_left / maxf(ramp_out, 0.01), 0.0, 1.0))

func _cur_factor() -> float:
	if _left < ramp_out:
		return lerpf(1.0, factor, clampf(_left / maxf(ramp_out, 0.01), 0.0, 1.0))
	return factor

func _play_beat() -> void:
	var st := Sfx.get_stream("overwatch_heartbeat")
	if st == null:
		return
	_beat = AudioStreamPlayer.new()
	_beat.stream = st
	_beat.bus = "SFX"
	_beat.volume_db = -4.0
	_beat.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_beat)
	_beat.play()
