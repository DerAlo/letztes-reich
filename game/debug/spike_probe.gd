extends Node
## Ruckler-Sonde (--spike-log[=ms]): meldet Frames ueber der Schwelle (Echtzeit), mit
## Pipeline-/Shader-Kompilierungen im Frame, Prozess-/Physik-/Render-CPU-Zeit, Objekt-Delta
## und den Knoten, die in diesem Frame neu in den Baum kamen.
## Ausgabe: "[spike] t=.. ms=.. pipe=+N proc=.. phys=.. rcpu=.. obj=+N nodes=N bodies=N added=N: Name(Klasse) x3, ..."
## --spike-quit=S beendet nach S Sekunden Echtzeit (mit Zusammenfassung "[spike] SUMMARY ...").

var _thr_ms: float = 45.0
var _last_us: int = 0
var _added: Dictionary = {}
var _pipe_last: int = 0
var _pipe_start: int = 0
var _obj_last: int = 0
var _t0: int = 0
var _total: int = 0
var _worst: float = 0.0
var _frames: int = 0
var _buckets := {25: 0, 33: 0, 50: 0, 100: 0, 250: 0}
var _quit_s: float = -1.0
var _vp: RID
## Abschnitts-Zeiten (us) des laufenden Frames: andere Skripte melden per SpikeProbe.mark(name, t0_usec).
static var marks: Dictionary = {}
## Frame-Zeitleiste: Physik-Skripte / Physik-Engine (Luecken zwischen Physik-Schritten) / Prozess / Rest (Render)
var _tl_phys_start: int = 0
var _tl_phys_script: int = 0
var _tl_phys_engine: int = 0
var _tl_last_phys_end: int = 0
var _tl_steps: int = 0
var _tl_proc_end: int = 0
var _tl_proc_script: int = 0
var _tl_prev: String = ""

var _proc_t0: int = 0

static func mark(name: String, t0: int) -> void:
	marks[name] = int(marks.get(name, 0)) + (Time.get_ticks_usec() - t0)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	var a = Game.arg("spike-log", true)
	if typeof(a) != TYPE_BOOL:
		_thr_ms = float(a)
	_quit_s = float(Game.arg("spike-quit", -1.0))
	get_tree().node_added.connect(_on_added)
	get_tree().physics_frame.connect(_on_pf)
	_last_us = Time.get_ticks_usec()
	_t0 = _last_us
	_pipe_last = _pipes()
	_pipe_start = _pipe_last
	_obj_last = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	print("[spike] Sonde aktiv, Schwelle %.0f ms" % _thr_ms)
	process_physics_priority = -1000
	var tail := _Tail.new()
	tail.probe = self
	tail.process_priority = 1000
	tail.process_physics_priority = 1000
	tail.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(tail)

class _Tail extends Node:
	var probe: Node
	func _physics_process(_d: float) -> void:
		probe.call("_phys_end")
	func _process(_d: float) -> void:
		probe.call("_proc_end")

var _tl_pf_at: int = 0
var _tl_pre: int = 0   # Physik-Ende (Tail) -> physics_frame-Signal: Timer/Tweens/Deferred, Navigation, Engine-Schritt, Kontakt-Signale
var _tl_aw: int = 0    # physics_frame-Signal -> Physik-Skripte: await-Koroutinen auf physics_frame
var _tl_nav: float = 0.0
var _last_pre_ms: float = 0.0

## --spike-bodies: bei langen Physik-Schritten alle wachen Dynamik-Koerper (RigidBody3D, PhysicalBone3D) auflisten
func _dump_bodies() -> void:
	var out: Array = []
	var n := 0
	for b: Node in get_tree().root.find_children("*", "PhysicsBody3D", true, false):
		if b is RigidBody3D:
			var rb := b as RigidBody3D
			if rb.freeze or rb.sleeping:
				continue
			n += 1
			out.append("%s@%s v=%.1f" % [rb.name, str(rb.global_position.snapped(Vector3.ONE * 0.1)), rb.linear_velocity.length()])
		elif b is PhysicalBone3D:
			var pb := b as PhysicalBone3D
			n += 1
			out.append("%s@%s v=%.1f" % [pb.name, str(pb.global_position.snapped(Vector3.ONE * 0.1)), pb.linear_velocity.length()])
	out.sort_custom(func(a: String, b: String) -> bool: return (0 if not a.begins_with("@") else 1) < (0 if not b.begins_with("@") else 1))
	print("[spike]   bodies awake=%d: %s" % [n, ", ".join(out.slice(0, 40))])

func _on_pf() -> void:
	_tl_pf_at = Time.get_ticks_usec()
	if _tl_last_phys_end > 0:
		_tl_pre += _tl_pf_at - _tl_last_phys_end
	_tl_nav = maxf(_tl_nav, Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0)

func _physics_process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _tl_pf_at > 0:
		_tl_aw += now - _tl_pf_at
		_tl_pf_at = 0
	if _tl_last_phys_end > 0:
		_tl_phys_engine += now - _tl_last_phys_end   # Engine-Schritt (+Flush) des vorigen Physik-Ticks
		_tl_last_phys_end = 0
	_tl_phys_start = now
	_tl_steps += 1

func _phys_end() -> void:
	var now := Time.get_ticks_usec()
	_tl_phys_script += now - _tl_phys_start
	_tl_last_phys_end = now

func _proc_end() -> void:
	_tl_proc_end = Time.get_ticks_usec()
	_tl_proc_script = _tl_proc_end - _proc_t0

func _pipes() -> int:
	var n := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]:
		n += RenderingServer.get_rendering_info(k)
	return n

func _pipe_detail() -> String:
	var names := ["cv", "mesh", "surf", "draw", "spec"]
	var ks := [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION]
	var out: Array = []
	for i in ks.size():
		out.append("%s%d" % [names[i], RenderingServer.get_rendering_info(ks[i])])
	return "/".join(out)

func _on_added(n: Node) -> void:
	var key := String(n.name).rstrip("0123456789@") + "(" + n.get_class() + ")"
	if n.get_script() != null:
		var sp: String = (n.get_script() as Script).resource_path.get_file()
		if sp != "":
			key = String(n.name).rstrip("0123456789@") + "(" + sp + ")"
	_added[key] = int(_added.get(key, 0)) + 1

func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _tl_last_phys_end > 0:
		_tl_phys_engine += now - _tl_last_phys_end
		_tl_last_phys_end = 0
	var ms := float(now - _last_us) / 1000.0
	# Zeitleiste des abgelaufenen Intervalls: Rest = Render/Sync/Eingabe
	var rest := (now - _last_us) - _tl_phys_script - _tl_phys_engine - _tl_proc_script
	var tl := "steps=%d physScr=%.1f physEng=%.1f (pre=%.1f await=%.1f navMax=%.1f) proc=%.1f rest=%.1f" % [_tl_steps, _tl_phys_script / 1000.0, _tl_phys_engine / 1000.0, _tl_pre / 1000.0, _tl_aw / 1000.0, _tl_nav, _tl_proc_script / 1000.0, rest / 1000.0]
	_last_pre_ms = _tl_pre / 1000.0
	_tl_pre = 0
	_tl_aw = 0
	_tl_nav = 0.0
	var mk: Array = []
	for k in marks.keys():
		mk.append("%s=%.1f" % [k, int(marks[k]) / 1000.0])
	marks.clear()
	_tl_steps = 0
	_tl_phys_script = 0
	_tl_phys_engine = 0
	_last_us = now
	var p := _pipes()
	var dp := p - _pipe_last
	_pipe_last = p
	var obj := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var dobj := obj - _obj_last
	_obj_last = obj
	var warm := now - _t0 > 2_000_000
	if warm:
		_frames += 1
	if ms >= _thr_ms and warm and not get_tree().paused:
		_total += 1
		_worst = maxf(_worst, ms)
		for b in _buckets.keys():
			if ms >= float(b):
				_buckets[b] += 1
		var parts: Array = []
		var keys := _added.keys()
		keys.sort_custom(func(x, y): return int(_added[x]) > int(_added[y]))
		for k in keys.slice(0, 8):
			parts.append("%s x%d" % [k, int(_added[k])])
		print("[spike] t=%.1f ms=%.0f pipe=+%d proc=%.1f phys=%.1f rcpu=%.1f gpu=%.1f obj=%+d nodes=%d bodies=%d added=%d: %s" % [
			float(now - _t0) / 1e6, ms, dp,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(_vp),
			RenderingServer.viewport_get_measured_render_time_gpu(_vp),
			dobj, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
			_sum(), ", ".join(parts)])
		print("[spike]   %s | marks: %s" % [tl, " ".join(mk)])
		if Game.arg("spike-bodies", false) and _last_pre_ms > 20.0:
			_dump_bodies()
	_added.clear()
	_tl_proc_script = 0
	_proc_t0 = Time.get_ticks_usec()
	if _quit_s > 0.0 and float(now - _t0) / 1e6 >= _quit_s:
		_summary()
		get_tree().quit()

func _exit_tree() -> void:
	if _quit_s != -2.0:
		_summary()

func _summary() -> void:
	if _quit_s == -2.0:
		return
	var b: Array = []
	for k in _buckets.keys():
		b.append(">=%d:%d" % [k, _buckets[k]])
	print("[spike] SUMMARY frames=%d spikes=%d worst=%.0f %s pipes_total=+%d (%s)" % [_frames, _total, _worst, " ".join(b),
		_pipes() - _pipe_start, _pipe_detail()])
	_quit_s = -2.0

func _sum() -> int:
	var s := 0
	for v in _added.values():
		s += int(v)
	return s
