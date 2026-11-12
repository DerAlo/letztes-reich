class_name InputConfig
extends RefCounted
## Tastenbelegung: Standardwerte merken, gespeicherte Belegung (Settings "input/<aktion>") anwenden,
## Umbelegen mit Konfliktsuche, Tastennamen im aktuellen Tastaturlayout.
##
## Ablauf: Game._setup_input() baut die Standard-InputMap. Danach (deferred, wenn Settings da ist)
## ruft Game InputConfig.apply_saved() auf: fehlende Spieler-Aktionen (weapon_3, crouch_hold – sonst erst
## im Player angelegt) werden identisch ergaenzt, die Standardbelegung wird gemerkt, gespeicherte Belegungen
## ueberschreiben sie. Ohne gespeicherte Werte (immer bei Bots/Tools) bleibt die InputMap exakt wie bisher.
##
## Speicherformat pro Aktion: Array[String] mit genau SLOTS Eintraegen (Primaer, Sekundaer):
##   "pk:<physical_keycode>"  Taste (physisch, layoutunabhaengig)
##   "k:<keycode>"            Taste (logisch, z. B. Hinlegen auf "Z" bei QWERTZ)
##   "mb:<button_index>"      Maustaste / Mausrad
##   ""                       leer
## "pause" ist fest auf ESC und nicht umbelegbar.

const SLOTS := 2
const PREFIX := "input/"

## [aktion, Anzeigename, Gruppe] – Reihenfolge = Anzeige im Menue
const ACTIONS: Array = [
	["move_forward", "Vorwärts", "Bewegung"],
	["move_back", "Rückwärts", "Bewegung"],
	["move_left", "Links", "Bewegung"],
	["move_right", "Rechts", "Bewegung"],
	["sprint", "Sprinten", "Bewegung"],
	["jump", "Springen / Klettern", "Bewegung"],
	["crouch", "Ducken (Sprint: Rutschen)", "Bewegung"],
	["crouch_hold", "Ducken (Halten)", "Bewegung"],
	["prone", "Hinlegen", "Bewegung"],
	["fire", "Feuern", "Kampf"],
	["aim", "Zielen", "Kampf"],
	["reload", "Nachladen", "Kampf"],
	["grenade", "Granate werfen", "Kampf"],
	["interact", "Benutzen / Aufheben", "Kampf"],
	["weapon_1", "Primärwaffe", "Waffen"],
	["weapon_2", "Pistole", "Waffen"],
	["weapon_3", "Dritte Waffe", "Waffen"],
	["weapon_last", "Letzte Waffe", "Waffen"],
	["weapon_next", "Nächste Waffe", "Waffen"],
	["weapon_prev", "Vorige Waffe", "Waffen"],
	["nightvision", "Nachtsichtgerät", "Ausrüstung"],
	["flashlight", "Taschenlampe", "Ausrüstung"],
	["binoculars", "Fernglas (Artilleriebeobachter)", "Ausrüstung"],
	["spotter_far", "Korrektur: weiter", "Ausrüstung"],
	["spotter_near", "Korrektur: kürzer", "Ausrüstung"],
	["spotter_left", "Korrektur: links", "Ausrüstung"],
	["spotter_right", "Korrektur: rechts", "Ausrüstung"],
	["spotter_effect", "Mörser: Wirkungsfeuer", "Ausrüstung"],
	["drone_toggle", "Drohne starten / zurückholen", "Ausrüstung"],
	["drone_thermal", "Drohne: Wärmebild", "Ausrüstung"],
	["squad_order", "Befehl: Feuer / Dort hin (halten: Halt)", "Begleiter"],
	["squad_hold", "Halt / Folgen", "Begleiter"],
]

## Aktionen, die Game._setup_input nicht anlegt, der Player aber (identische Standardwerte wie player.gd).
const EXTRA_KEYS := {"weapon_3": KEY_3, "crouch_hold": KEY_CTRL, "nightvision": KEY_N, "flashlight": KEY_L,
	"binoculars": KEY_B, "spotter_far": KEY_UP, "spotter_near": KEY_DOWN, "spotter_left": KEY_LEFT, "spotter_right": KEY_RIGHT, "spotter_effect": KEY_F,
	"drone_toggle": KEY_V, "drone_thermal": KEY_T,
	"squad_order": KEY_X, "squad_hold": KEY_H}   # Squad-Befehle light (game/squad/), nur mit Level-Opt-in wirksam

static var _defaults: Dictionary = {}   # aktion -> Array[InputEvent]
static var _applied: bool = false


## Einmal beim Start (nach Game._setup_input, sobald das Autoload Settings existiert).
static func apply_saved() -> void:
	if _applied:
		return
	_applied = true
	ensure_actions()
	_capture_defaults()
	var settings := _settings()
	if settings == null:
		return
	for a in ACTIONS:
		var action: String = a[0]
		if settings.call("has", PREFIX + action):
			var arr = settings.call("get_value", PREFIX + action, [])
			if arr is Array:
				_set_events(action, _parse_list(arr))


static func ensure_actions() -> void:
	for action in EXTRA_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = EXTRA_KEYS[action]
			InputMap.action_add_event(action, ev)
	for a in ACTIONS:
		if not InputMap.has_action(a[0]):
			InputMap.add_action(a[0])


static func _capture_defaults() -> void:
	if not _defaults.is_empty():
		return
	for a in ACTIONS:
		var list: Array = []
		for ev in InputMap.action_get_events(a[0]):
			list.append(ev.duplicate())
		_defaults[a[0]] = list


static func _settings() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	if ml == null:
		return null
	return ml.root.get_node_or_null("Settings")


# ------------------------------------------------------------------ Lesen / Schreiben

## Belegung eines Slots (null = leer).
static func get_binding(action: String, slot: int) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	var evs := _bindable_events(action)
	return evs[slot] if slot < evs.size() else null


## Nur Tastatur-/Mausereignisse (Gamepad o. ae. bleibt unangetastet).
static func _bindable_events(action: String) -> Array:
	var out: Array = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			out.append(ev)
	return out


static func get_slots(action: String) -> Array:
	var out: Array = []
	for i in SLOTS:
		out.append(get_binding(action, i))
	return out


## Setzt einen Slot (ev = null leert ihn) und speichert die Aktion.
static func set_binding(action: String, slot: int, ev: InputEvent) -> void:
	var slots := get_slots(action)
	slots[slot] = _clean(ev)
	_set_events(action, slots)
	_save(action)


## Weist ev an (action, slot) zu. Liegt ev schon auf einer anderen Stelle, wird getauscht:
## die andere Stelle erhaelt die bisherige Belegung dieses Slots. Rueckgabe: [aktion, slot] des Tauschpartners oder [].
static func assign(action: String, slot: int, ev: InputEvent) -> Array:
	var conflict := find_conflict(ev, action, slot)
	var old := get_binding(action, slot)
	if not conflict.is_empty():
		var other_action: String = conflict[0]
		var other_slot: int = conflict[1]
		if other_action == action:
			# gleiche Aktion, anderer Slot: Slots tauschen
			var s := get_slots(action)
			s[other_slot] = old
			s[slot] = _clean(ev)
			_set_events(action, s)
			_save(action)
			return conflict
		set_binding(other_action, other_slot, old)
	set_binding(action, slot, ev)
	return conflict


## Erste andere Stelle (aktion, slot), die dasselbe Ereignis belegt.
static func find_conflict(ev: InputEvent, except_action: String = "", except_slot: int = -1) -> Array:
	if ev == null:
		return []
	for a in ACTIONS:
		var action: String = a[0]
		for i in SLOTS:
			if action == except_action and i == except_slot:
				continue
			var other := get_binding(action, i)
			if other != null and events_equal(ev, other):
				return [action, i]
	return []


## Alle Stellen mit Doppelbelegung: Dictionary "aktion:slot" -> true
static func all_conflicts() -> Dictionary:
	var out := {}
	for a in ACTIONS:
		for i in SLOTS:
			var ev := get_binding(a[0], i)
			if ev != null and not find_conflict(ev, a[0], i).is_empty():
				out["%s:%d" % [a[0], i]] = true
	return out


static func reset_all() -> void:
	var settings := _settings()
	if settings != null:
		settings.call("reset_section", "input")
	for action in _defaults:
		_set_events(action, (_defaults[action] as Array).duplicate())


static func is_default(action: String) -> bool:
	var d: Array = _defaults.get(action, [])
	var cur := _bindable_events(action)
	if d.size() != cur.size():
		return false
	for i in d.size():
		if not events_equal(d[i], cur[i]):
			return false
	return true


static func action_label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action


# ------------------------------------------------------------------ intern

static func _set_events(action: String, evs: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	# nicht umbelegbare Ereignisse (z. B. Gamepad) behalten
	var keep: Array = []
	for ev in InputMap.action_get_events(action):
		if not (ev is InputEventKey or ev is InputEventMouseButton):
			keep.append(ev)
	InputMap.action_erase_events(action)
	for ev in evs:
		if ev != null:
			InputMap.action_add_event(action, ev)
	for ev in keep:
		InputMap.action_add_event(action, ev)


static func _save(action: String) -> void:
	var settings := _settings()
	if settings == null:
		return
	var arr: Array = []
	for ev in get_slots(action):
		arr.append(event_to_string(ev))
	settings.call("set_value", PREFIX + action, arr)


## Reines Ereignis ohne Modifikatoren/Druckzustand.
static func _clean(ev: InputEvent) -> InputEvent:
	if ev == null:
		return null
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var n := InputEventKey.new()
		if k.physical_keycode != KEY_NONE:
			n.physical_keycode = k.physical_keycode
		else:
			n.keycode = k.keycode
		return n
	if ev is InputEventMouseButton:
		var m := InputEventMouseButton.new()
		m.button_index = (ev as InputEventMouseButton).button_index
		return m
	return null


static func event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var k := ev as InputEventKey
		if k.physical_keycode != KEY_NONE:
			return "pk:%d" % k.physical_keycode
		return "k:%d" % k.keycode
	if ev is InputEventMouseButton:
		return "mb:%d" % (ev as InputEventMouseButton).button_index
	return ""


static func string_to_event(s: String) -> InputEvent:
	var p := s.split(":")
	if p.size() != 2 or not p[1].is_valid_int():
		return null
	var v := int(p[1])
	match p[0]:
		"pk":
			var e := InputEventKey.new()
			e.physical_keycode = v as Key
			return e
		"k":
			var e2 := InputEventKey.new()
			e2.keycode = v as Key
			return e2
		"mb":
			var m := InputEventMouseButton.new()
			m.button_index = v as MouseButton
			return m
	return null


static func _parse_list(arr: Array) -> Array:
	var out: Array = []
	for s in arr:
		out.append(string_to_event(str(s)))
	while out.size() < SLOTS:
		out.append(null)
	return out


## Logische Taste eines Tastenereignisses im aktuellen Layout.
static func _logical_key(k: InputEventKey) -> int:
	if k.physical_keycode != KEY_NONE:
		var l := DisplayServer.keyboard_get_keycode_from_physical(k.physical_keycode)
		return int(l) if l != KEY_NONE else int(k.physical_keycode)
	return int(k.keycode)


static func events_equal(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		if ka.physical_keycode != KEY_NONE and kb.physical_keycode != KEY_NONE:
			return ka.physical_keycode == kb.physical_keycode
		return _logical_key(ka) == _logical_key(kb)
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false


const MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Linke Maustaste", MOUSE_BUTTON_RIGHT: "Rechte Maustaste",
	MOUSE_BUTTON_MIDDLE: "Mittlere Maustaste", MOUSE_BUTTON_WHEEL_UP: "Mausrad hoch",
	MOUSE_BUTTON_WHEEL_DOWN: "Mausrad runter", MOUSE_BUTTON_WHEEL_LEFT: "Mausrad links",
	MOUSE_BUTTON_WHEEL_RIGHT: "Mausrad rechts", MOUSE_BUTTON_XBUTTON1: "Maustaste 4",
	MOUSE_BUTTON_XBUTTON2: "Maustaste 5",
}
const KEY_NAMES := {
	KEY_SPACE: "Leertaste", KEY_SHIFT: "Umschalt", KEY_CTRL: "Strg", KEY_ALT: "Alt", KEY_TAB: "Tab",
	KEY_ENTER: "Eingabe", KEY_KP_ENTER: "Num-Eingabe", KEY_BACKSPACE: "Rücktaste", KEY_CAPSLOCK: "Feststell",
	KEY_UP: "Pfeil hoch", KEY_DOWN: "Pfeil runter", KEY_LEFT: "Pfeil links", KEY_RIGHT: "Pfeil rechts",
	KEY_DELETE: "Entf", KEY_INSERT: "Einfg", KEY_HOME: "Pos1", KEY_END: "Ende", KEY_PAGEUP: "Bild hoch",
	KEY_PAGEDOWN: "Bild runter", KEY_ESCAPE: "Esc", KEY_META: "Win",
}


## Anzeigename im aktuellen Tastaturlayout ("" = leer).
static func event_label(ev: InputEvent) -> String:
	if ev == null:
		return ""
	if ev is InputEventMouseButton:
		var bi: int = (ev as InputEventMouseButton).button_index
		return MOUSE_NAMES.get(bi, "Maustaste %d" % bi)
	if ev is InputEventKey:
		var k := ev as InputEventKey
		var key: int = int(k.keycode)
		if k.physical_keycode != KEY_NONE:
			var lab := DisplayServer.keyboard_get_label_from_physical(k.physical_keycode)
			key = int(lab) if lab != KEY_NONE else int(k.physical_keycode)
		if KEY_NAMES.has(key):
			return KEY_NAMES[key]
		var s := OS.get_keycode_string(key as Key)
		return s if s != "" else "Taste %d" % key
	return ev.as_text()
