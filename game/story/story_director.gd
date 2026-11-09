extends Node
class_name StoryDirector
## Spielt Funksprueche/Ziele aus StoryData.SCRIPTS fuer ein Level ab: Start, z-Schwellen des Spielers, Checkpoints.
## Wird von main.gd als Kind des Levels angelegt (stirbt mit dem Level). Hat bewusst KEIN get_level_info().

var level_name: String = ""
var _entries: Array = []
var _done: Dictionary = {}
var _poll: float = 0.0

func setup(p_level: String, start_delay: float) -> void:
	level_name = p_level
	_entries = StoryData.SCRIPTS.get(p_level, [])
	if _entries.is_empty():
		set_process(false)
		return
	Events.checkpoint_reached.connect(_on_checkpoint)
	get_tree().create_timer(start_delay, false).timeout.connect(_fire_at.bind("start"))

func _process(delta: float) -> void:
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.2
	var pl := Game.get_player() as Node3D
	if pl == null:
		return
	var z := pl.global_position.z
	for i in _entries.size():
		var at: String = _entries[i]["at"]
		if at.begins_with("z:") and not _done.has(i) and z < float(at.substr(2)):
			_fire(i)

func _on_checkpoint(id: String) -> void:
	_fire_at("cp:" + id)

func _fire_at(at: String) -> void:
	for i in _entries.size():
		if _entries[i]["at"] == at and not _done.has(i):
			_fire(i)

func _fire(i: int) -> void:
	_done[i] = true
	var e: Dictionary = _entries[i]
	if e.has("objective"):
		Events.story_objective.emit(str(e["objective"]))
	for l in e.get("lines", []):
		Events.story_radio.emit(str(l[0]), str(l[1]), 0.0)
