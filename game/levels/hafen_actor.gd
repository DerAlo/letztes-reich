extends "res://game/levels/overwatch_actor.gd"
## Mission "Kräne": Puppen-Figur wie in "Kaltes Auge", dazu Weber als echte Person (kein Panzerglas):
## Treffer bluten, schaden ihm aber nicht (das Level wertet sie als Warnung/Fehlschlag). Weber gehoert zur
## Gruppe "friendly" (Scharfschuetzen-Bot schiesst nicht durch ihn) und "no_shoot".

func _ready() -> void:
	super._ready()
	if role == "weber":
		add_to_group("friendly")
		add_to_group("no_shoot")

## Puppe (hafen_models.puppet): Zielpunkt relativ zur Figur, wandert mit Boot/Lafette mit.
var aim_local := Vector3.INF

func _physics_process(delta: float) -> void:
	if aim_local != Vector3.INF:
		aim_point = global_transform * aim_local
	super._physics_process(delta)

func take_hit_part(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3, headshot: bool) -> void:
	if role != "weber":
		super.take_hit_part(amount, source, hit_position, hit_normal, headshot)
		return
	if state == State.DEAD or amount <= 0.0:
		return
	VFX.spawn_blood(hit_position, hit_normal)
	_flinch = 1.0
	var from_player: bool = source != null and is_instance_valid(source) and source.is_in_group("player")
	if from_player and level_ref != null and level_ref.has_method("on_weber_hit"):
		level_ref.call("on_weber_hit")
