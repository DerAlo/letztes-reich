extends Pickup
## Funkterminal der Fernmeldestelle (Level "curfew"): [E] startet den Download von Webers Funkprotokollen.
## Der Download laeuft weiter, solange Kerner in der Naehe bleibt (Fortschritt im Schleich-HUD).
## Waehrend eines Alarms ist das Terminal gesperrt.

signal download_started
signal download_finished

const DL_RANGE := 6.5

var duration: float = 15.0
var progress: float = 0.0
var downloading: bool = false
var done: bool = false
var locked: bool = false
var paused: bool = false
var _tick_t: float = 0.0
var _screen_mat: StandardMaterial3D
var _screen_label: Label3D
var _glow: OmniLight3D

func _ready() -> void:
	super()
	snap_to_floor = false
	_build_terminal()

func _build_terminal() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.17, 0.17)
	metal.roughness = 0.55
	metal.metallic = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.04, 0.04, 0.045)
	dark.roughness = 0.5
	# Pult, Gehaeuse, Bildschirm, Tastatur
	_box(Vector3(1.4, 0.06, 0.75), Vector3(0, 0.92, 0), metal)
	_box(Vector3(1.36, 0.88, 0.7), Vector3(0, 0.45, 0.02), dark)
	_box(Vector3(0.9, 0.6, 0.08), Vector3(0, 1.32, 0.22), dark)
	_box(Vector3(0.1, 0.32, 0.1), Vector3(0, 1.04, 0.24), metal)
	_box(Vector3(0.62, 0.025, 0.2), Vector3(0, 0.965, -0.12), dark)
	var scr := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.82, 0.52)
	scr.mesh = q
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.albedo_color = Color(0.0, 0.0, 0.0)
	_screen_mat.emission_enabled = true
	_screen_mat.emission = Color(0.15, 0.85, 0.45)
	_screen_mat.emission_energy_multiplier = 0.7
	scr.material_override = _screen_mat
	scr.position = Vector3(0, 1.32, 0.175)
	scr.rotation_degrees.y = 180.0
	add_child(scr)
	_screen_label = Label3D.new()
	_screen_label.text = "FERNMELDESTELLE 4\nFUNKPROTOKOLLE 05/2030\nZUGRIFF: GESPERRT"
	_screen_label.font_size = 28
	_screen_label.pixel_size = 0.0016
	_screen_label.modulate = Color(0.6, 2.0, 0.9)
	_screen_label.shaded = false
	_screen_label.outline_size = 0
	_screen_label.position = Vector3(0, 1.33, 0.17)
	_screen_label.rotation_degrees.y = 180.0
	add_child(_screen_label)
	_glow = OmniLight3D.new()
	_glow.light_color = Color(0.3, 1.0, 0.55)
	_glow.light_energy = 0.6
	_glow.omni_range = 2.6
	_glow.position = Vector3(0, 1.35, -0.3)
	_glow.set_meta("no_stealth", true)
	add_child(_glow)
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 1.0, 0.75)
	cs.shape = bs
	cs.position = Vector3(0, 0.5, 0)
	sb.add_child(cs)
	add_child(sb)

func _box(size: Vector3, pos: Vector3, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	add_child(mi)

func in_range(p: Node3D) -> bool:
	if done or downloading:
		return false
	var d: Vector3 = p.global_position - global_position
	return absf(d.y) < 1.6 and Vector2(d.x, d.z).length() < 2.2

func auto_collect(_p: Player) -> bool:
	return false

func interact_text(_p: Player) -> String:
	if done or downloading:
		return ""
	if locked:
		return "Terminal gesperrt – Alarm!"
	return "[E] Funkprotokolle herunterladen"

func interact(_p: Player) -> void:
	start()

func start() -> void:
	if locked or downloading or done:
		return
	downloading = true
	_screen_label.text = "FUNKPROTOKOLLE 05/2030\nKOPIERE …"
	download_started.emit()

## Alarm im Datenraum: Protokolle geloescht, alles zurueck.
func wipe() -> void:
	downloading = false
	paused = false
	progress = 0.0
	_screen_label.text = "FUNKPROTOKOLLE 05/2030\n*** GELÖSCHT ***"
	_screen_mat.emission = Color(1.0, 0.2, 0.15)

func reset() -> void:
	downloading = false
	paused = false
	progress = 0.0
	_screen_label.text = "FERNMELDESTELLE 4\nFUNKPROTOKOLLE 05/2030\nZUGRIFF: GESPERRT"
	_screen_mat.emission = Color(0.15, 0.85, 0.45)

func _process(delta: float) -> void:
	super(delta)
	if not downloading or done:
		return
	var pl := get_tree().get_first_node_in_group("player") as Node3D
	paused = pl == null or locked or pl.global_position.distance_to(global_position) > DL_RANGE \
		or not bool(pl.call("is_alive"))
	if paused:
		return
	progress = minf(1.0, progress + delta / duration)
	_tick_t -= delta
	if _tick_t <= 0.0:
		_tick_t = 1.0
		_beep("curfew_download_tick", -8.0)
	var pct := int(progress * 100.0)
	_screen_label.text = "FUNKPROTOKOLLE 05/2030\nKOPIERE … %d %%" % pct
	_screen_mat.emission_energy_multiplier = 0.6 + 0.3 * sin(Time.get_ticks_msec() * 0.02)
	if progress >= 1.0:
		done = true
		downloading = false
		_screen_label.text = "FUNKPROTOKOLLE 05/2030\nÜBERTRAGUNG ABGESCHLOSSEN"
		_beep("curfew_download_done", -2.0)
		download_finished.emit()

func _beep(n: String, vol: float) -> void:
	var s := Sfx.get_stream(n)
	if s == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "SFX"
	p.volume_db = vol
	p.unit_size = 4.0
	p.position = Vector3(0, 1.3, 0)
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
