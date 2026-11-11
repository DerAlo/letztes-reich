extends Node
## Klang an Bord der "Waechter": Einzelklaenge aus einem kleinen Player-Pool, Schleifen (Triebwerke, Gatling)
## mit weichem Ein-/Ausblenden. Dateien: res://assets/sfx/gunship_<name>.ogg

const POOL := 14

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}     # name -> {"p": player, "on": bool, "db": float}
var _queued: Array = []         # [zeit, name, db]
var _t: float = 0.0

func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		add_child(p)
		_pool.append(p)

func _stream(n: String, looped: bool = false) -> AudioStream:
	var key := n + ("#l" if looped else "")
	if _streams.has(key):
		return _streams[key]
	var path := "res://assets/sfx/gunship_%s.ogg" % n
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if looped and s is AudioStreamOggVorbis:
			s = s.duplicate()
			(s as AudioStreamOggVorbis).loop = true
	_streams[key] = s
	return s

func play(n: String, db: float = 0.0, delay: float = 0.0) -> void:
	if delay > 0.0:
		_queued.append([_t + delay, n, db])
		return
	var s := _stream(n)
	if s == null:
		return
	var best: AudioStreamPlayer = null
	for p in _pool:
		if not p.playing:
			best = p
			break
	if best == null:
		best = _pool[0]
		_pool.push_back(_pool.pop_front())
	best.stream = s
	best.volume_db = db
	best.pitch_scale = randf_range(0.96, 1.04)
	best.play()

func loop(n: String, on: bool, db: float = 0.0) -> void:
	if not _loops.has(n):
		if not on:
			return
		var s := _stream(n, true)
		if s == null:
			return
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		p.stream = s
		p.volume_db = -40.0
		add_child(p)
		_loops[n] = {"p": p, "on": false, "db": db}
	var L: Dictionary = _loops[n]
	L["db"] = db
	if on and not bool(L["on"]):
		var p2: AudioStreamPlayer = L["p"]
		if not p2.playing:
			p2.volume_db = db - 12.0
			p2.play()
	L["on"] = on

func stop_all() -> void:
	for p in _pool:
		p.stop()
	for k in _loops:
		(_loops[k]["p"] as AudioStreamPlayer).stop()
		_loops[k]["on"] = false
	_queued.clear()

func _process(delta: float) -> void:
	_t += delta
	var i := 0
	while i < _queued.size():
		var q: Array = _queued[i]
		if _t >= float(q[0]):
			_queued.remove_at(i)
			play(q[1], q[2])
			continue
		i += 1
	for k in _loops:
		var L: Dictionary = _loops[k]
		var p: AudioStreamPlayer = L["p"]
		if bool(L["on"]):
			p.volume_db = move_toward(p.volume_db, float(L["db"]), delta * 60.0)
		elif p.playing:
			p.volume_db = move_toward(p.volume_db, -50.0, delta * 90.0)
			if p.volume_db <= -49.0:
				p.stop()
