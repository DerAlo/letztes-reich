extends Node3D
## Platzhalter fuer einen gestaffelt gespawnten Wellen-Gegner (Level._spawn_wave).
## Steht fuer ein paar Frames in Gruppe "enemy", damit synchrone Wave-Done-Pruefungen
## (Gruppe leer / alle tot) nicht zu frueh feuern. Wird beim echten Spawn ersetzt;
## queue_free/destroy vorher bricht den Spawn ab.

func _ready() -> void:
	add_to_group("enemy")

func is_alive() -> bool:
	return not is_queued_for_deletion()

func destroy() -> void:
	remove_from_group("enemy")
	queue_free()
