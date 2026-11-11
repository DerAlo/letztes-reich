extends RefCounted
## Bonus-Episoden (Welle 5): dieselbe Geschichte aus anderen Augen. Reine Daten + Helfer, keine Szene.
## main.gd laedt Episoden wie Level (res://game/levels/<id>.tscn), aber ohne Kampagnenfortschritt:
## kein _mark_unlocked, keine Folgemission; Sterne laufen ueber game/progress/ unter der Episoden-ID.
## Neue Episode: Eintrag in LIST (id, Titel, Ort/Zeit, Szene, Freischaltung, Sternziel), Level unter
## game/levels/<id>.gd/.tscn, optional Briefing (StoryData.BRIEFINGS[id]) und Karte (BriefingMaps.MAPS[id]).

const Progress = preload("res://game/progress/progress.gd")

## unlock_after: Kampagnenmission, die erreicht (game/unlocked) oder mit Sternen abgeschlossen sein muss.
## scene "": Platzhalter ("In Vorbereitung"), im Menue gesperrt.
const LIST: Array[Dictionary] = [
	{"id": "ep_lena", "title": "Lena – Über den Dächern", "sub": "Dieselbe Nacht wie „Ausgangssperre“, durch Lenas Zielfernrohr.",
		"place": "Berlin-Mitte, Dach des Ministeriums", "date": "3. Juni 2030, 01:35",
		"scene": "res://game/levels/ep_lena.tscn", "unlock_after": "curfew",
		"goal": {"time": 330, "challenge": "undetected"}},
	{"id": "ep_brandt", "title": "Brandt", "sub": "In Vorbereitung.", "place": "", "date": "",
		"scene": "", "unlock_after": "", "goal": {}},
	{"id": "ep_voss", "title": "Voss", "sub": "In Vorbereitung.", "place": "", "date": "",
		"scene": "", "unlock_after": "", "goal": {}},
	{"id": "ep_ueberlaeufer", "title": "Der Überläufer", "sub": "In Vorbereitung.", "place": "", "date": "",
		"scene": "", "unlock_after": "", "goal": {}},
]


static func find(id: String) -> Dictionary:
	for e: Dictionary in LIST:
		if str(e["id"]) == id:
			return e
	return {}


static func is_episode(id: String) -> bool:
	return not find(id).is_empty()


## Szene vorhanden (kein Platzhalter)?
static func available(id: String) -> bool:
	var e := find(id)
	var sc: String = str(e.get("scene", ""))
	return sc != "" and ResourceLoader.exists(sc)


## Freigeschaltet: Bedingungsmission erreicht (Settings "game/unlocked") oder schon mit Sternen abgeschlossen.
## unlocked_list: Inhalt von "game/unlocked" (main.gd reicht ihn durch, damit dieses Skript ohne Autoloads testbar bleibt).
static func is_unlocked(id: String, unlocked_list: Array) -> bool:
	var e := find(id)
	if e.is_empty() or not available(id):
		return false
	var after: String = str(e.get("unlock_after", ""))
	if after == "":
		return true
	return after in unlocked_list or Progress.stars(after) > 0


## Titelzeile wie main.TITLES: [Titel, Ort, Datum/Uhrzeit].
static func title_of(id: String) -> Array:
	var e := find(id)
	if e.is_empty():
		return [id, "", ""]
	return [str(e["title"]), str(e.get("place", "")), str(e.get("date", ""))]


static func goal_of(id: String) -> Dictionary:
	return find(id).get("goal", {})


## Menue-Liste mit Sperrstatus und Sternen.
static func menu_list(unlocked_list: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in LIST:
		var id: String = str(e["id"])
		var ok := available(id)
		out.append({"id": id, "title": str(e["title"]), "sub": str(e.get("sub", "")), "place": str(e.get("place", "")),
			"date": str(e.get("date", "")), "available": ok, "unlocked": is_unlocked(id, unlocked_list),
			"unlock_after": str(e.get("unlock_after", "")),
			"stars": Progress.stars(id) if ok else 0, "star_mask": Progress.mask(id) if ok else 0,
			"best_time": Progress.best_time(id) if ok else -1.0, "goal": e.get("goal", {})})
	return out
