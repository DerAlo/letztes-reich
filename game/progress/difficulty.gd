extends RefCounted
## Schwierigkeitsgrade (Welle 4, systeme-a): Rekrut / Soldat / Veteran.
## Nur statische Funktionen; Nutzung per preload (kein class_name, damit kein Editor-Scan noetig ist):
##   const Difficulty = preload("res://game/progress/difficulty.gd")
##   Difficulty.damage_taken()  usw.
## Quelle: Arg --difficulty=recruit|soldier|veteran (Vorrang, z. B. Simulationen), sonst Settings "game/difficulty".
## Ohne beides: "soldier". Soldat liefert ueberall exakt 1.0 -> Verhalten wie vor Welle 4.
## Der Wert wird hoechstens einmal pro Frame neu gelesen, damit eine Aenderung im Menue sofort greift.

const KEY := "game/difficulty"
const DEFAULT := "soldier"
const IDS: Array[String] = ["recruit", "soldier", "veteran"]
const NAMES := {"recruit": "Rekrut", "soldier": "Soldat", "veteran": "Veteran"}
const DESCRIPTIONS := {
	"recruit": "Gegner treffen seltener, reagieren langsamer und richten weniger Schaden an. Kerner erholt sich schneller.",
	"soldier": "Ausgewogen – so ist der Einsatz gedacht.",
	"veteran": "Gegner treffen öfter, reagieren schneller und richten mehr Schaden an. Kerner erholt sich langsamer.",
}
## Multiplikatoren. damage = Schaden von Gegnern/Umwelt am Spieler, accuracy = Gegner-Trefferchance,
## reaction = Gegner-Reaktions- und Bemerkzeit (groesser = langsamer), regen_delay/regen_rate = Spieler-Erholung.
const PRESETS := {
	"recruit": {"damage": 0.6, "accuracy": 0.75, "reaction": 1.35, "regen_delay": 0.75, "regen_rate": 1.5},
	"soldier": {"damage": 1.0, "accuracy": 1.0, "reaction": 1.0, "regen_delay": 1.0, "regen_rate": 1.0},
	"veteran": {"damage": 1.35, "accuracy": 1.2, "reaction": 0.75, "regen_delay": 1.3, "regen_rate": 0.8},
}

static var _cur: String = ""
static var _frame: int = -1


static func _root_node(path: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(path)


static func normalize(v) -> String:
	var s := str(v).strip_edges().to_lower()
	match s:
		"rekrut", "easy", "0":
			return "recruit"
		"soldat", "normal", "1":
			return "soldier"
		"hard", "2":
			return "veteran"
	return s if s in IDS else DEFAULT


static func _resolve() -> String:
	var g := _root_node("/root/Game")
	if g != null:
		var a = g.call("arg", "difficulty", null)
		if a != null and not (a is bool):
			return normalize(a)
	var st := _root_node("/root/Settings")
	if st != null:
		return normalize(st.call("get_value", KEY, DEFAULT))
	return DEFAULT


## Aktueller Grad ("recruit" | "soldier" | "veteran").
static func current() -> String:
	var f := Engine.get_process_frames()
	if f != _frame or _cur == "":
		_frame = f
		_cur = _resolve()
	return _cur


static func display_name(id: String = "") -> String:
	return str(NAMES.get(id if id != "" else current(), "Soldat"))


static func set_current(id: String) -> void:
	var st := _root_node("/root/Settings")
	if st != null:
		st.call("set_value", KEY, normalize(id))
	_cur = ""


static func value(name: String) -> float:
	return float((PRESETS.get(current(), PRESETS[DEFAULT]) as Dictionary).get(name, 1.0))


static func damage_taken() -> float:
	return value("damage")


static func enemy_accuracy() -> float:
	return value("accuracy")


static func enemy_reaction() -> float:
	return value("reaction")


static func regen_delay() -> float:
	return value("regen_delay")


static func regen_rate() -> float:
	return value("regen_rate")
