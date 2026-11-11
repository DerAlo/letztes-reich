extends RefCounted
## Ausruestungswahl (Welle 4, systeme-b): Tabelle, Freischaltung, Speicherung, Anwenden auf den Spieler.
## Default = heutige Standardausruestung (G36C + Splittergranaten) -> wer nur bestaetigt, spielt unveraendert.
## Gespeichert pro Level in Settings "loadout/<level>" = {"primary": id, "grenade": id}.
## Nie unter --autopilot/Tools (dort gilt immer der Default); Debug: --loadout=<primaer>[,<granate>] erzwingt eine Wahl.

const Progress = preload("res://game/progress/progress.gd")

const DEFAULT := {"primary": "g36c", "grenade": "frag"}
const PRIMARIES: Array[String] = ["g36c", "ak74m", "g28"]
const GRENADES: Array[String] = ["frag", "flash"]
const GRENADE_NAMES := {"frag": "Splittergranate", "flash": "Blendgranate"}
const GRENADE_DESC := {
	"frag": "Splitterwirkung, Radius 7 m. Zünder 2,5 s.",
	"flash": "Kein Schaden. Gegner mit Sichtlinie im Umkreis von 10 m zögern rund 3 s. Zünder 1,6 s.",
}
const PRIMARY_DESC := {
	"g36c": "Sturmgewehr 5,56 mm, Rotpunkt. Ausgewogen, schnell im Anschlag.",
	"ak74m": "Beutewaffe 5,45 mm, Rotpunkt. Mehr Rückstoß, Munition beim Feind reichlich.",
	"g28": "Präzisionsgewehr 7,62 mm, Zielfernrohr. Halbautomatisch, tödlich auf Distanz, träge im Nahkampf.",
}
## Freischaltung: verfuegbar, sobald das genannte Level abgeschlossen ist ("" = immer).
const UNLOCK := {"g36c": "", "ak74m": "river_crossing", "g28": "overwatch", "frag": "", "flash": "curfew"}

## Level mit fester Ausruestung (Level setzt Waffen selbst bzw. eigener Spielmodus) -> nur gesperrte Anzeige.
const FIXED := {
	"curfew": "Schleicheinsatz: G36C und Pistole SD werden gestellt.",
	"overwatch": "Scharfschützeneinsatz: G28 wird gestellt.",
	"gunship": "Bordschütze im Luftnahunterstützer – keine Handwaffen.",
	"hafen": "Scharfschützeneinsatz: G28 wird gestellt.",
	"spreebogen": "Schützenpanzer „Rabe“ – Bordwaffe.",
	"kanalisation": "Nachtsicht und Pistole SD werden gestellt.",
	"ep_lena": "Scharfschützeneinsatz: G28 wird gestellt.",   # Welle 5: Bonus-Episode Lena
}
## Freie Level mit Hinweis (Level ersetzt nur die Seitenwaffe).
const NOTES := {
	"villa": "Seitenwaffe: Pistole SD wird gestellt.",
}


static func is_fixed(level: String) -> bool:
	return FIXED.has(level)


static func _settings() -> Node:
	var ml := Engine.get_main_loop() as SceneTree
	return ml.root.get_node_or_null("Settings") if ml != null else null


static func _game_arg(key: String, default = null):
	var ml := Engine.get_main_loop() as SceneTree
	var g: Node = ml.root.get_node_or_null("Game") if ml != null else null
	return g.call("arg", key, default) if g != null else default


## Wahl erlaubt? (kein Bot/Tool, keine feste Ausruestung)
static func choice_allowed(level: String) -> bool:
	if is_fixed(level) or Progress.is_tool_run():
		return false
	for a in ["autopilot", "debug-server", "capture", "no-loadout", "start-paused"]:
		if _game_arg(a, false):
			return false
	return true


static func is_unlocked(id: String, levels: Array, unlocked: Array) -> bool:
	var from: String = UNLOCK.get(id, "")
	if from == "":
		return true
	if Progress.stars(from) > 0:
		return true
	var fi := levels.find(from)
	if fi < 0:
		return false
	for l in unlocked:
		if levels.find(l) > fi:
			return true
	return false


static func unlock_text(id: String, titles: Dictionary) -> String:
	var from: String = UNLOCK.get(id, "")
	var t: Array = titles.get(from, [from])
	return "Gesperrt – frei nach „%s“" % str(t[0])


static func load_choice(level: String) -> Dictionary:
	var out := DEFAULT.duplicate()
	var st := _settings()
	if st != null:
		var raw = st.call("get_value", "loadout/" + level, {})
		if raw is Dictionary:
			if PRIMARIES.has(str(raw.get("primary", ""))):
				out["primary"] = str(raw["primary"])
			if GRENADES.has(str(raw.get("grenade", ""))):
				out["grenade"] = str(raw["grenade"])
	return out


static func save_choice(level: String, choice: Dictionary) -> void:
	var st := _settings()
	if st != null:
		st.call("set_value", "loadout/" + level, {"primary": str(choice.get("primary", DEFAULT["primary"])),
				"grenade": str(choice.get("grenade", DEFAULT["grenade"]))})


## Wahl, die beim Levelstart gilt. Default unter Bots/Tools; --loadout=... erzwingt (Debug/Screenshots).
static func effective_choice(level: String, levels: Array, unlocked: Array) -> Dictionary:
	var forced := str(_game_arg("loadout", ""))
	if forced != "" and forced != "true":
		var parts := forced.split(",")
		var c := DEFAULT.duplicate()
		if PRIMARIES.has(parts[0]):
			c["primary"] = parts[0]
		if parts.size() > 1 and GRENADES.has(parts[1]):
			c["grenade"] = parts[1]
		return c if not is_fixed(level) else DEFAULT.duplicate()
	if not choice_allowed(level):
		return DEFAULT.duplicate()
	var c2 := load_choice(level)
	if not is_unlocked(c2["primary"], levels, unlocked):
		c2["primary"] = DEFAULT["primary"]
	if not is_unlocked(c2["grenade"], levels, unlocked):
		c2["grenade"] = DEFAULT["grenade"]
	return c2


## Wendet die Wahl auf den Spieler an. Default -> nichts anfassen (exakt wie bisher).
static func apply(player: Node, choice: Dictionary) -> void:
	if player == null or not is_instance_valid(player):
		return
	var prim := str(choice.get("primary", DEFAULT["primary"]))
	var gren := str(choice.get("grenade", DEFAULT["grenade"]))
	if prim != DEFAULT["primary"]:
		_swap_primary(player, prim)
	if gren == "flash" and "grenade_scene" in player:
		player.set("grenade_scene", load("res://game/loadout/flash_grenade.tscn"))
	print("[loadout] %s + %s" % [prim, gren])


static func _swap_primary(pl: Node, id: String) -> void:
	var weapons: Array = pl.get("weapons")
	if weapons.is_empty():
		return
	var old: Weapon = weapons[0]
	if old == null or old.weapon_id == id:
		return
	var w: Weapon = WeaponDefs.instantiate(id)
	if w == null:
		return
	if w.slot != 0:
		w.free()
		return
	(pl.get("weapon_root") as Node).add_child(w)
	w.setup(pl as Player)
	w.fired.connect(Callable(pl, "_on_weapon_fired"))
	w.hit_confirmed.connect(Callable(pl, "_on_hit_confirmed"))
	w.set_active(false)
	var was_active: bool = pl.get("weapon") == old
	old.cancel_reload()
	old.set_active(false)
	weapons[0] = w
	old.queue_free()
	if was_active:
		pl.set("weapon", w)
		pl.set("weapon_index", 0)
		w.set_active(true)
