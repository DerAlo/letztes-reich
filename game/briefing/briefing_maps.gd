extends RefCounted
## Briefing-Karten (Welle 4, systeme-b): pro Level eine stilisierte taktische Karte.
## Koordinaten normiert 0..1 (x nach rechts, y nach unten; Norden = oben). Der Spieler kommt meist von unten.
## Level ohne Eintrag bekommen das alte Text-Briefing (main.gd::_run_briefing).
##
## "terrain": statische Kartengrundlage, immer sichtbar.
##   {"k": "field"|"forest"|"water"|"block"|"zone", "r": [x, y, w, h]}  oder  "p": [x0, y0, x1, y1, ...] (Polygon)
##   {"k": "road"|"rail"|"path"|"tunnel"|"contour"|"border"|"fence", "p": [...]}  (Linienzug)
##   {"k": "label", "c": [x, y], "s": "TEXT"}   (Ortsname, klein, gedimmt)
## "cues": erscheinen im Takt des Lageberichts. "at" = Satzindex (0 = erster Satz), Nachkommastellen = Anteil des
##   Satzes (1.5 = Mitte von Satz 1). Saetze trennt BriefingMaps.sentence_starts() wie der Sprechtext.
##   {"t": "mark", "k": "friend"|"enemy"|"objective"|"hvt"|"neutral"|"charge"|"hostage", "c": [x, y], "s": "Beschriftung"}
##   {"t": "arrow", "k": "route"|"friend"|"enemy"|"hvt", "p": [...], "s": "..."}   (waechst animiert, Pfeilspitze)
##   {"t": "zone", "k": "friend"|"enemy"|"objective"|"neutral"|"weather", "c": [x, y], "r": radius, "s": "..."}
##   {"t": "line", "k": ..., "p": [...], "s": "..."}   (gestrichelte Linie ohne Spitze, z. B. Sicherungslinie)
## Optional: "ref" (Kartenkopf), "grid" (Planquadrat-Kennung).

const MAPS := {
	"baltic_night": {
		"ref": "Grenzraum Lettland–Russland · 1:25 000", "grid": "35V MC 41",
		"terrain": [
			{"k": "field", "r": [0.02, 0.62, 0.96, 0.36]},
			{"k": "forest", "p": [0.0, 0.40, 0.18, 0.37, 0.38, 0.42, 0.62, 0.38, 0.82, 0.43, 1.0, 0.39, 1.0, 0.60, 0.74, 0.62, 0.5, 0.58, 0.24, 0.63, 0.0, 0.60]},
			{"k": "block", "r": [0.40, 0.20, 0.06, 0.05]}, {"k": "block", "r": [0.54, 0.21, 0.07, 0.04]},
			{"k": "block", "r": [0.42, 0.28, 0.05, 0.05]}, {"k": "block", "r": [0.55, 0.28, 0.05, 0.06]},
			{"k": "block", "r": [0.70, 0.24, 0.08, 0.07]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.62, 0.48, 0.42, 0.50, 0.24, 0.52, 0.0]},
			{"k": "road", "p": [0.30, 0.25, 0.70, 0.27, 0.95, 0.22]},
			{"k": "rail", "p": [0.0, 0.11, 1.0, 0.09]},
			{"k": "border", "p": [0.0, 0.03, 0.35, 0.05, 0.7, 0.02, 1.0, 0.04]},
			{"k": "label", "c": [0.12, 0.80], "s": "FELD"}, {"k": "label", "c": [0.80, 0.50], "s": "WALD"},
			{"k": "label", "c": [0.30, 0.31], "s": "DORF"}, {"k": "label", "c": [0.74, 0.33], "s": "TANKLAGER"},
			{"k": "label", "c": [0.62, 0.17], "s": "WASSERTURM"}, {"k": "label", "c": [0.08, 0.075], "s": "BAHNLINIE"},
			{"k": "label", "c": [0.80, 0.015], "s": "GRENZE"},
		],
		"cues": [
			{"at": 0.1, "t": "arrow", "k": "enemy", "p": [0.80, 0.0, 0.78, 0.12, 0.70, 0.30], "s": "RU-Verbände"},
			{"at": 0.4, "t": "arrow", "k": "enemy", "p": [0.22, 0.0, 0.26, 0.14, 0.36, 0.30]},
			{"at": 0.7, "t": "zone", "k": "enemy", "c": [0.50, 0.50], "r": 0.09, "s": "Stellungen Waldrand"},
			{"at": 1.1, "t": "line", "k": "friend", "p": [0.04, 0.82, 0.5, 0.80, 0.96, 0.83], "s": "Linie halten"},
			{"at": 1.4, "t": "mark", "k": "friend", "c": [0.50, 0.92], "s": "Zug Kerner"},
			{"at": 2.1, "t": "arrow", "k": "route", "p": [0.50, 0.90, 0.50, 0.64, 0.48, 0.44, 0.50, 0.26, 0.52, 0.13], "s": "Vorstoß"},
			{"at": 2.4, "t": "mark", "k": "enemy", "c": [0.43, 0.56], "s": "Sandsäcke"},
			{"at": 2.5, "t": "mark", "k": "enemy", "c": [0.58, 0.55]},
			{"at": 2.8, "t": "mark", "k": "objective", "c": [0.52, 0.10], "s": "Bahnübergang"},
		],
	},
	"test_range": {
		"ref": "Daugavpils, Innenstadt · 1:5 000", "grid": "35V NC 07",
		"terrain": [
			{"k": "block", "r": [0.26, 0.62, 0.18, 0.30]}, {"k": "block", "r": [0.56, 0.60, 0.18, 0.32]},
			{"k": "block", "r": [0.24, 0.10, 0.20, 0.28]}, {"k": "block", "r": [0.56, 0.10, 0.20, 0.28]},
			{"k": "block", "r": [0.04, 0.50, 0.16, 0.42]}, {"k": "block", "r": [0.80, 0.52, 0.16, 0.40]},
			{"k": "block", "r": [0.04, 0.06, 0.16, 0.34]}, {"k": "block", "r": [0.80, 0.06, 0.16, 0.36]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.0]},
			{"k": "road", "p": [0.0, 0.46, 1.0, 0.46]},
			{"k": "label", "c": [0.52, 0.80], "s": "HAUPTSTRASSE"}, {"k": "label", "c": [0.80, 0.445], "s": "KREUZUNG"},
			{"k": "label", "c": [0.52, 0.04], "s": "TOR"}, {"k": "label", "c": [0.06, 0.97], "s": "DAUGAVPILS"},
		],
		"cues": [
			{"at": 0.2, "t": "zone", "k": "neutral", "c": [0.50, 0.46], "r": 0.30, "s": "umkämpft seit 03:15"},
			{"at": 1.1, "t": "mark", "k": "enemy", "c": [0.46, 0.72], "s": "Infanterie"},
			{"at": 1.2, "t": "mark", "k": "enemy", "c": [0.55, 0.64]},
			{"at": 1.3, "t": "mark", "k": "enemy", "c": [0.45, 0.56]},
			{"at": 1.7, "t": "mark", "k": "enemy", "c": [0.50, 0.40], "s": "MG-Nest"},
			{"at": 1.8, "t": "zone", "k": "enemy", "c": [0.50, 0.40], "r": 0.06},
			{"at": 2.1, "t": "mark", "k": "friend", "c": [0.50, 0.94], "s": "KG Nord"},
			{"at": 2.4, "t": "arrow", "k": "route", "p": [0.50, 0.91, 0.47, 0.70, 0.52, 0.50, 0.50, 0.12], "s": "Haus für Haus"},
			{"at": 2.8, "t": "mark", "k": "objective", "c": [0.50, 0.08], "s": "Tor"},
		],
	},
	"river_crossing": {
		"ref": "Welikaja bei Pskow · 1:10 000", "grid": "36V UE 22",
		"terrain": [
			{"k": "water", "p": [0.0, 0.40, 0.3, 0.43, 0.6, 0.41, 1.0, 0.44, 1.0, 0.59, 0.6, 0.57, 0.3, 0.60, 0.0, 0.58]},
			{"k": "field", "r": [0.0, 0.62, 1.0, 0.38]},
			{"k": "block", "r": [0.62, 0.08, 0.22, 0.14]}, {"k": "block", "r": [0.30, 0.12, 0.08, 0.08]},
			{"k": "block", "r": [0.40, 0.22, 0.06, 0.06]}, {"k": "block", "r": [0.22, 0.24, 0.07, 0.06]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.62]}, {"k": "road", "p": [0.50, 0.38, 0.52, 0.0]},
			{"k": "road", "p": [0.0, 0.66, 1.0, 0.67]},
			{"k": "path", "p": [0.10, 0.76, 0.40, 0.74]}, {"k": "path", "p": [0.60, 0.75, 0.90, 0.77]},
			{"k": "label", "c": [0.06, 0.52], "s": "WELIKAJA"}, {"k": "label", "c": [0.06, 0.90], "s": "WESTUFER"},
			{"k": "label", "c": [0.06, 0.34], "s": "OSTUFER"}, {"k": "label", "c": [0.66, 0.06], "s": "FABRIK"},
			{"k": "label", "c": [0.70, 0.71], "s": "SCHÜTZENGRÄBEN"}, {"k": "label", "c": [0.86, 0.02], "s": "PSKOW →"},
		],
		"cues": [
			{"at": 0.1, "t": "arrow", "k": "enemy", "p": [0.44, 0.78, 0.47, 0.55, 0.46, 0.25], "s": "Rückzug"},
			{"at": 0.6, "t": "mark", "k": "objective", "c": [0.51, 0.50], "s": "Brücke"},
			{"at": 0.8, "t": "mark", "k": "charge", "c": [0.56, 0.47], "s": "Sprengung?"},
			{"at": 1.1, "t": "arrow", "k": "friend", "p": [0.18, 0.98, 0.28, 0.80]},
			{"at": 1.2, "t": "arrow", "k": "friend", "p": [0.82, 0.98, 0.72, 0.80], "s": "Vormarsch"},
			{"at": 2.0, "t": "mark", "k": "friend", "c": [0.50, 0.93], "s": "KG Nord"},
			{"at": 2.2, "t": "arrow", "k": "route", "p": [0.50, 0.90, 0.50, 0.66, 0.51, 0.40, 0.52, 0.20]},
			{"at": 2.5, "t": "zone", "k": "enemy", "c": [0.52, 0.29], "r": 0.10, "s": "Brückenkopf"},
			{"at": 2.7, "t": "mark", "k": "enemy", "c": [0.56, 0.32], "s": "Panzer"},
		],
	},
	"rail_yard": {
		"ref": "Güterbahnhof Pskow · 1:5 000", "grid": "36V UE 31",
		"terrain": [
			{"k": "rail", "p": [0.30, 1.0, 0.30, 0.0]}, {"k": "rail", "p": [0.38, 1.0, 0.38, 0.0]},
			{"k": "rail", "p": [0.62, 1.0, 0.62, 0.0]}, {"k": "rail", "p": [0.70, 1.0, 0.70, 0.30, 0.95, 0.10]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.0]},
			{"k": "block", "r": [0.78, 0.62, 0.12, 0.10]}, {"k": "block", "r": [0.08, 0.55, 0.14, 0.30]},
			{"k": "block", "r": [0.06, 0.06, 0.20, 0.18]}, {"k": "block", "r": [0.74, 0.08, 0.18, 0.10]},
			{"k": "block", "r": [0.35, 0.36, 0.06, 0.28]},
			{"k": "label", "c": [0.79, 0.75], "s": "STELLWERK"}, {"k": "label", "c": [0.08, 0.88], "s": "LADERAMPEN"},
			{"k": "label", "c": [0.07, 0.27], "s": "LAGERHALLEN"}, {"k": "label", "c": [0.52, 0.20], "s": "KRANBAHN"},
			{"k": "label", "c": [0.06, 0.97], "s": "PSKOW"},
		],
		"cues": [
			{"at": 0.2, "t": "zone", "k": "neutral", "c": [0.50, 0.50], "r": 0.34, "s": "Pskow"},
			{"at": 1.1, "t": "mark", "k": "objective", "c": [0.38, 0.50], "s": "Zug: Gefangene, Munition"},
			{"at": 1.6, "t": "arrow", "k": "enemy", "p": [0.40, 0.36, 0.70, 0.28, 0.98, 0.08], "s": "Abfahrt Ost"},
			{"at": 2.1, "t": "mark", "k": "friend", "c": [0.50, 0.94], "s": "KG Nord"},
			{"at": 2.3, "t": "mark", "k": "enemy", "c": [0.76, 0.66], "s": "Stellwerk"},
			{"at": 2.4, "t": "mark", "k": "enemy", "c": [0.46, 0.30]},
			{"at": 2.5, "t": "arrow", "k": "route", "p": [0.50, 0.90, 0.48, 0.62, 0.52, 0.30, 0.50, 0.14]},
			{"at": 2.8, "t": "zone", "k": "objective", "c": [0.50, 0.12], "r": 0.08, "s": "Bahnhof halten"},
		],
	},
	"berlin": {
		"ref": "Berlin, Regierungsviertel · 1:5 000", "grid": "33U UU 89",
		"terrain": [
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.08]},
			{"k": "road", "p": [0.0, 0.30, 1.0, 0.30]},
			{"k": "block", "r": [0.10, 0.04, 0.30, 0.20]}, {"k": "block", "r": [0.60, 0.04, 0.32, 0.20]},
			{"k": "block", "r": [0.10, 0.38, 0.28, 0.20]}, {"k": "block", "r": [0.62, 0.38, 0.28, 0.20]},
			{"k": "block", "r": [0.06, 0.66, 0.28, 0.28]}, {"k": "block", "r": [0.66, 0.66, 0.28, 0.28]},
			{"k": "water", "p": [0.0, 0.0, 1.0, 0.0, 1.0, 0.025, 0.0, 0.03]},
			{"k": "label", "c": [0.52, 0.62], "s": "BOULEVARD"}, {"k": "label", "c": [0.62, 0.02], "s": "SENDEZENTRUM"},
			{"k": "label", "c": [0.12, 0.02], "s": "MINISTERIEN"}, {"k": "label", "c": [0.40, 0.27], "s": "PLATZ"},
		],
		"cues": [
			{"at": 0.3, "t": "zone", "k": "friend", "c": [0.50, 0.80], "r": 0.14, "s": "Waffenstillstand"},
			{"at": 1.2, "t": "zone", "k": "neutral", "c": [0.50, 0.70], "r": 0.10, "s": "Siegesfeier"},
			{"at": 1.6, "t": "mark", "k": "neutral", "c": [0.50, 0.86], "s": "Bühne"},
			{"at": 1.8, "t": "mark", "k": "friend", "c": [0.42, 0.82], "s": "Ehrenformation KG Nord"},
			{"at": 2.3, "t": "mark", "k": "friend", "c": [0.58, 0.82], "s": "Hptm. Weber"},
		],
	},
	"curfew": {
		"ref": "Berlin-Mitte, Sperrgebiet · 1:2 500", "grid": "33U UU 90",
		"terrain": [
			{"k": "block", "r": [0.06, 0.70, 0.36, 0.26]}, {"k": "block", "r": [0.58, 0.70, 0.36, 0.26]},
			{"k": "block", "r": [0.06, 0.36, 0.16, 0.26]}, {"k": "block", "r": [0.34, 0.42, 0.10, 0.20]},
			{"k": "block", "r": [0.54, 0.06, 0.30, 0.18]}, {"k": "block", "r": [0.10, 0.06, 0.30, 0.18]},
			{"k": "zone", "r": [0.40, 0.28, 0.40, 0.08]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.28]}, {"k": "path", "p": [0.46, 0.68, 0.28, 0.66, 0.27, 0.40, 0.42, 0.36]},
			{"k": "tunnel", "p": [0.84, 0.15, 0.92, 0.10, 1.0, 0.10]},
			{"k": "label", "c": [0.52, 0.86], "s": "STRASSE"}, {"k": "label", "c": [0.22, 0.64], "s": "HINTERHÖFE"},
			{"k": "label", "c": [0.56, 0.33], "s": "PLATZ"}, {"k": "label", "c": [0.56, 0.04], "s": "MINISTERIUMSANBAU"},
			{"k": "label", "c": [0.86, 0.06], "s": "U-BAHN"},
		],
		"cues": [
			{"at": 0.2, "t": "zone", "k": "enemy", "c": [0.50, 0.50], "r": 0.42, "s": "Ausgangssperre"},
			{"at": 0.6, "t": "mark", "k": "enemy", "c": [0.50, 0.70], "s": "Kontrollpunkt"},
			{"at": 0.7, "t": "mark", "k": "enemy", "c": [0.30, 0.55], "s": "Streife"},
			{"at": 0.8, "t": "mark", "k": "enemy", "c": [0.66, 0.32], "s": "Drohne"},
			{"at": 1.3, "t": "mark", "k": "objective", "c": [0.70, 0.16], "s": "Fernmeldestelle"},
			{"at": 2.1, "t": "arrow", "k": "route", "p": [0.50, 0.96, 0.49, 0.74, 0.30, 0.66, 0.29, 0.42, 0.56, 0.35, 0.68, 0.22], "s": "ungesehen"},
			{"at": 2.6, "t": "arrow", "k": "route", "p": [0.72, 0.16, 0.86, 0.12, 0.94, 0.10]},
			{"at": 2.8, "t": "mark", "k": "friend", "c": [0.95, 0.12], "s": "Voss"},
		],
	},
	"overwatch": {
		"ref": "Stahlwerk Hennigsdorf · 1:5 000", "grid": "33U UU 77",
		"terrain": [
			{"k": "block", "r": [0.44, 0.24, 0.14, 0.24]}, {"k": "block", "r": [0.64, 0.30, 0.22, 0.14]},
			{"k": "block", "r": [0.08, 0.44, 0.18, 0.12]}, {"k": "block", "r": [0.32, 0.50, 0.06, 0.08]},
			{"k": "zone", "p": [0.12, 0.18, 0.20, 0.12, 0.28, 0.18, 0.28, 0.30, 0.12, 0.30]},
			{"k": "road", "p": [0.0, 0.74, 0.4, 0.73, 0.7, 0.75, 1.0, 0.72]},
			{"k": "rail", "p": [0.38, 0.54, 0.46, 0.40]},
			{"k": "fence", "p": [0.04, 0.08, 0.96, 0.08, 0.96, 0.66, 0.04, 0.66, 0.04, 0.08]},
			{"k": "label", "c": [0.13, 0.11], "s": "KÜHLTURM"}, {"k": "label", "c": [0.45, 0.21], "s": "HOCHOFEN"},
			{"k": "label", "c": [0.24, 0.60], "s": "ÜBERGABETURM"}, {"k": "label", "c": [0.04, 0.78], "s": "WERKSSTRASSE"},
			{"k": "label", "c": [0.40, 0.47], "s": "BANDBRÜCKE"},
		],
		"cues": [
			{"at": 0.1, "t": "arrow", "k": "enemy", "p": [0.0, 0.73, 0.40, 0.73, 0.98, 0.73], "s": "Konvoi nach Norden"},
			{"at": 0.7, "t": "mark", "k": "hvt", "c": [0.18, 0.73], "s": "Brandt (Gefangener)"},
			{"at": 1.2, "t": "zone", "k": "weather", "c": [0.50, 0.42], "r": 0.30, "s": "Morgennebel"},
			{"at": 2.1, "t": "mark", "k": "friend", "c": [0.56, 0.80], "s": "Voss’ Trupp"},
			{"at": 2.2, "t": "mark", "k": "friend", "c": [0.64, 0.81]},
			{"at": 2.4, "t": "zone", "k": "objective", "c": [0.60, 0.74], "r": 0.07, "s": "Hinterhalt"},
			{"at": 2.6, "t": "mark", "k": "friend", "c": [0.35, 0.54], "s": "Kerner"},
			{"at": 2.75, "t": "line", "k": "route", "p": [0.35, 0.54, 0.60, 0.74]},
			{"at": 2.85, "t": "mark", "k": "enemy", "c": [0.20, 0.24], "s": "Posten"},
			{"at": 2.9, "t": "mark", "k": "enemy", "c": [0.70, 0.40]},
		],
	},
	"gunship": {
		"ref": "Fliegerhorst Lindenau · Wärmebild-Lage", "grid": "33U UT 54",
		"terrain": [
			{"k": "field", "r": [0.0, 0.0, 1.0, 1.0]},
			{"k": "road", "p": [0.08, 0.82, 0.92, 0.36]},
			{"k": "block", "r": [0.30, 0.28, 0.14, 0.10]}, {"k": "block", "r": [0.48, 0.24, 0.10, 0.08]},
			{"k": "block", "r": [0.66, 0.56, 0.12, 0.10]}, {"k": "block", "r": [0.78, 0.14, 0.04, 0.04]},
			{"k": "fence", "p": [0.10, 0.12, 0.90, 0.08, 0.94, 0.80, 0.14, 0.92, 0.10, 0.12]},
			{"k": "label", "c": [0.30, 0.25], "s": "HANGAR"}, {"k": "label", "c": [0.48, 0.21], "s": "TOWER"},
			{"k": "label", "c": [0.66, 0.68], "s": "TANKLAGER"}, {"k": "label", "c": [0.76, 0.12], "s": "SENDEMAST"},
			{"k": "label", "c": [0.40, 0.62], "s": "PISTE"}, {"k": "label", "c": [0.12, 0.10], "s": "ZAUN"},
		],
		"cues": [
			{"at": 0.2, "t": "zone", "k": "friend", "c": [0.52, 0.48], "r": 0.44, "s": "Kreisbahn „Wächter“"},
			{"at": 0.5, "t": "mark", "k": "friend", "c": [0.52, 0.04], "s": "Wächter"},
			{"at": 1.1, "t": "arrow", "k": "friend", "p": [0.14, 1.0, 0.20, 0.86, 0.34, 0.66], "s": "Lena / Voss"},
			{"at": 1.5, "t": "mark", "k": "objective", "c": [0.60, 0.46], "s": "Jets"},
			{"at": 1.6, "t": "mark", "k": "objective", "c": [0.72, 0.61], "s": "Tanklager"},
			{"at": 1.8, "t": "mark", "k": "objective", "c": [0.80, 0.16], "s": "Sendemast"},
			{"at": 2.1, "t": "mark", "k": "enemy", "c": [0.38, 0.42], "s": "Flak"},
			{"at": 2.2, "t": "mark", "k": "enemy", "c": [0.72, 0.30], "s": "SAM"},
			{"at": 2.6, "t": "mark", "k": "friend", "c": [0.26, 0.76], "s": "IR-Blinker"},
		],
	},
	"hafen": {
		"ref": "Überseehafen Rostock · 1:5 000", "grid": "33U UV 12",
		"terrain": [
			{"k": "water", "p": [0.0, 0.0, 1.0, 0.0, 1.0, 0.16, 0.86, 0.18, 0.86, 0.30, 1.0, 0.30, 1.0, 0.36, 0.0, 0.10]},
			{"k": "block", "r": [0.36, 0.40, 0.08, 0.04]}, {"k": "block", "r": [0.46, 0.40, 0.08, 0.04]},
			{"k": "block", "r": [0.36, 0.48, 0.08, 0.04]}, {"k": "block", "r": [0.46, 0.48, 0.08, 0.04]},
			{"k": "block", "r": [0.36, 0.56, 0.08, 0.04]}, {"k": "block", "r": [0.46, 0.56, 0.08, 0.04]},
			{"k": "block", "r": [0.58, 0.40, 0.08, 0.04]}, {"k": "block", "r": [0.58, 0.48, 0.08, 0.04]},
			{"k": "block", "r": [0.58, 0.56, 0.08, 0.04]}, {"k": "block", "r": [0.68, 0.44, 0.08, 0.04]},
			{"k": "block", "r": [0.68, 0.52, 0.08, 0.04]}, {"k": "block", "r": [0.10, 0.80, 0.10, 0.08]},
			{"k": "rail", "p": [0.24, 0.30, 0.24, 0.92]}, {"k": "rail", "p": [0.32, 0.30, 0.32, 0.92]},
			{"k": "road", "p": [0.0, 0.70, 1.0, 0.70]}, {"k": "road", "p": [0.56, 1.0, 0.56, 0.38]},
			{"k": "label", "c": [0.04, 0.04], "s": "HAFENBECKEN"}, {"k": "label", "c": [0.40, 0.36], "s": "CONTAINERLAGER"},
			{"k": "label", "c": [0.18, 0.28], "s": "PORTALKRAN"}, {"k": "label", "c": [0.82, 0.14], "s": "LIEGEPLATZ 7"},
			{"k": "label", "c": [0.10, 0.78], "s": "WACHE"},
		],
		"cues": [
			{"at": 1.3, "t": "mark", "k": "hvt", "c": [0.62, 0.62], "s": "Weber · Akte Nordlicht"},
			{"at": 2.4, "t": "mark", "k": "objective", "c": [0.90, 0.24], "s": "Liegeplatz 7"},
			{"at": 4.1, "t": "arrow", "k": "friend", "p": [0.0, 0.98, 0.12, 0.90, 0.20, 0.84], "s": "Brandt"},
			{"at": 5.1, "t": "mark", "k": "friend", "c": [0.28, 0.50], "s": "Kerner (Kran)"},
			{"at": 5.5, "t": "arrow", "k": "friend", "p": [0.40, 0.96, 0.45, 0.72, 0.56, 0.62, 0.66, 0.46, 0.82, 0.30], "s": "Lena"},
			{"at": 6.2, "t": "arrow", "k": "neutral", "p": [0.96, 0.06, 0.82, 0.06], "s": "Seewind, böig"},
			{"at": 7.3, "t": "mark", "k": "enemy", "c": [0.52, 0.53], "s": "Garde-Jäger"},
			{"at": 7.4, "t": "mark", "k": "enemy", "c": [0.72, 0.49]},
			{"at": 7.5, "t": "mark", "k": "enemy", "c": [0.12, 0.83], "s": "Hafenwache"},
			{"at": 8.2, "t": "zone", "k": "objective", "c": [0.86, 0.28], "r": 0.08, "s": "Weber lebend"},
		],
	},
	"alpenpass": {
		"ref": "Grenzpass bei Mittenwald · 1:25 000", "grid": "32T PT 48",
		"terrain": [
			{"k": "contour", "p": [0.0, 0.62, 0.2, 0.55, 0.35, 0.62, 0.55, 0.58, 0.75, 0.66, 1.0, 0.60]},
			{"k": "contour", "p": [0.0, 0.42, 0.15, 0.36, 0.30, 0.44, 0.50, 0.40, 0.72, 0.46, 1.0, 0.40]},
			{"k": "contour", "p": [0.0, 0.24, 0.2, 0.18, 0.40, 0.24, 0.60, 0.18, 0.80, 0.22, 1.0, 0.16]},
			{"k": "contour", "p": [0.32, 0.56, 0.42, 0.48, 0.56, 0.50, 0.62, 0.56, 0.50, 0.62, 0.38, 0.62, 0.32, 0.56]},
			{"k": "road", "p": [0.50, 1.0, 0.44, 0.86, 0.58, 0.76, 0.46, 0.64, 0.56, 0.50, 0.62, 0.36, 0.72, 0.24, 0.80, 0.10]},
			{"k": "path", "p": [0.80, 0.10, 0.92, 0.04]},
			{"k": "border", "p": [0.0, 0.06, 0.4, 0.09, 0.7, 0.05, 1.0, 0.08]},
			{"k": "block", "r": [0.78, 0.08, 0.06, 0.04]},
			{"k": "label", "c": [0.40, 0.535], "s": "KESSEL"}, {"k": "label", "c": [0.08, 0.20], "s": "GRAT"},
			{"k": "label", "c": [0.64, 0.38], "s": "SATTEL"}, {"k": "label", "c": [0.76, 0.14], "s": "BERGSTATION"},
			{"k": "label", "c": [0.82, 0.02], "s": "ÖSTERREICH"}, {"k": "label", "c": [0.52, 0.94], "s": "PASSSTRASSE"},
		],
		"cues": [
			{"at": 1.2, "t": "arrow", "k": "hvt", "p": [0.50, 0.96, 0.52, 0.70, 0.60, 0.40, 0.80, 0.12, 0.86, 0.02], "s": "Weber → Österreich"},
			{"at": 2.1, "t": "zone", "k": "weather", "c": [0.50, 0.46], "r": 0.46, "s": "Schneesturm"},
			{"at": 3.1, "t": "mark", "k": "friend", "c": [0.24, 0.32], "s": "Absetzpunkt"},
			{"at": 3.5, "t": "mark", "k": "friend", "c": [0.08, 0.13], "s": "Mörserzug"},
			{"at": 3.8, "t": "line", "k": "friend", "p": [0.08, 0.13, 0.30, 0.20, 0.44, 0.50]},
			{"at": 4.1, "t": "mark", "k": "enemy", "c": [0.47, 0.64], "s": "Nachhut"},
			{"at": 4.2, "t": "mark", "k": "enemy", "c": [0.57, 0.48]},
			{"at": 4.6, "t": "mark", "k": "enemy", "c": [0.36, 0.22], "s": "Garde-Jäger"},
			{"at": 5.1, "t": "mark", "k": "objective", "c": [0.81, 0.10], "s": "Weber lebend"},
		],
	},
	# Welle 5: Bonus-Episode Lena (dieselbe Karte wie curfew, aus Lenas Sicht)
	"ep_lena": {
		"ref": "Berlin-Mitte, Sperrgebiet · Dächer · 1:2 500", "grid": "33U UU 90",
		"terrain": [
			{"k": "block", "r": [0.20, 0.78, 0.18, 0.17]}, {"k": "block", "r": [0.60, 0.78, 0.30, 0.17]},
			{"k": "block", "r": [0.12, 0.26, 0.14, 0.14]}, {"k": "block", "r": [0.80, 0.28, 0.14, 0.20]},
			{"k": "block", "r": [0.56, 0.08, 0.26, 0.12]},
			{"k": "zone", "r": [0.38, 0.26, 0.28, 0.16]},
			{"k": "road", "p": [0.52, 1.0, 0.51, 0.62, 0.50, 0.44, 0.88, 0.44]},
			{"k": "path", "p": [0.86, 0.44, 0.86, 0.36, 0.93, 0.29]},
			{"k": "tunnel", "p": [0.93, 0.27, 0.92, 0.12, 0.92, 0.02]},
			{"k": "label", "c": [0.21, 0.76], "s": "WOHNBLOCK"}, {"k": "label", "c": [0.53, 0.62], "s": "KONTROLLPUNKT"},
			{"k": "label", "c": [0.44, 0.30], "s": "PLATZ"}, {"k": "label", "c": [0.12, 0.24], "s": "REGIERUNGSBAU"},
			{"k": "label", "c": [0.57, 0.06], "s": "MINISTERIUM"}, {"k": "label", "c": [0.80, 0.26], "s": "ANBAU"},
		],
		"cues": [
			{"at": 0.3, "t": "zone", "k": "enemy", "c": [0.52, 0.55], "r": 0.40, "s": "Ausgangssperre"},
			{"at": 1.3, "t": "mark", "k": "friend", "c": [0.37, 0.89], "s": "Lena · G28"},
			{"at": 2.2, "t": "mark", "k": "friend", "c": [0.55, 0.94], "s": "Kerner"},
			{"at": 2.6, "t": "mark", "k": "objective", "c": [0.93, 0.29], "s": "Fernmeldestelle"},
			{"at": 3.2, "t": "arrow", "k": "route", "p": [0.55, 0.94, 0.52, 0.67, 0.51, 0.47, 0.61, 0.42, 0.86, 0.42, 0.93, 0.30], "s": "Kerner"},
			{"at": 3.6, "t": "mark", "k": "enemy", "c": [0.52, 0.70], "s": "Streifen"},
			{"at": 4.1, "t": "arrow", "k": "friend", "p": [0.37, 0.88, 0.45, 0.50, 0.68, 0.19], "s": "Stellungswechsel"},
			{"at": 4.5, "t": "mark", "k": "enemy", "c": [0.76, 0.39], "s": "Suchscheinwerfer"},
			{"at": 4.8, "t": "mark", "k": "enemy", "c": [0.22, 0.33], "s": "Gegenscharfschütze"},
			{"at": 5.3, "t": "zone", "k": "enemy", "c": [0.86, 0.40], "r": 0.05, "s": "Lieferzufahrt"},
			{"at": 6.3, "t": "mark", "k": "friend", "c": [0.92, 0.07], "s": "Voss"},
		],
	},
	"nachtzug": {
		"ref": "Strecke Innsbruck–Wien · Zugskizze", "grid": "EN 466",
		"terrain": [
			{"k": "rail", "p": [0.04, 0.38, 0.28, 0.28, 0.52, 0.32, 0.76, 0.20, 0.96, 0.12]},
			{"k": "tunnel", "p": [0.34, 0.29, 0.42, 0.30]}, {"k": "tunnel", "p": [0.62, 0.26, 0.70, 0.23]},
			{"k": "label", "c": [0.02, 0.42], "s": "INNSBRUCK"}, {"k": "label", "c": [0.48, 0.36], "s": "SALZBURG"},
			{"k": "label", "c": [0.70, 0.17], "s": "LINZ"}, {"k": "label", "c": [0.90, 0.07], "s": "WIEN"},
			{"k": "label", "c": [0.35, 0.25], "s": "TUNNEL"},
			{"k": "block", "r": [0.06, 0.62, 0.11, 0.10]}, {"k": "block", "r": [0.18, 0.62, 0.11, 0.10]},
			{"k": "block", "r": [0.30, 0.62, 0.11, 0.10]}, {"k": "block", "r": [0.42, 0.62, 0.11, 0.10]},
			{"k": "block", "r": [0.54, 0.62, 0.11, 0.10]}, {"k": "block", "r": [0.66, 0.62, 0.11, 0.10]},
			{"k": "block", "r": [0.80, 0.63, 0.12, 0.09]},
			{"k": "rail", "p": [0.02, 0.73, 0.98, 0.73]},
			{"k": "label", "c": [0.06, 0.60], "s": "SITZWAGEN"}, {"k": "label", "c": [0.42, 0.60], "s": "SPEISEWAGEN"},
			{"k": "label", "c": [0.66, 0.60], "s": "SCHLAFWAGEN"}, {"k": "label", "c": [0.82, 0.60], "s": "LOK"},
		],
		"cues": [
			{"at": 1.2, "t": "mark", "k": "hvt", "c": [0.22, 0.28], "s": "am Pass entkommen"},
			{"at": 2.3, "t": "mark", "k": "objective", "c": [0.72, 0.67], "s": "Abteil 9"},
			{"at": 2.6, "t": "mark", "k": "hvt", "c": [0.72, 0.56], "s": "Weber"},
			{"at": 3.1, "t": "mark", "k": "friend", "c": [0.04, 0.38], "s": "Zustieg"},
			{"at": 3.3, "t": "mark", "k": "friend", "c": [0.10, 0.67], "s": "Kerner / Lena"},
			{"at": 4.1, "t": "mark", "k": "enemy", "c": [0.36, 0.67], "s": "Garde-Jäger"},
			{"at": 4.2, "t": "mark", "k": "enemy", "c": [0.58, 0.66]},
			{"at": 5.2, "t": "mark", "k": "neutral", "c": [0.23, 0.68], "s": "Reisende"},
			{"at": 5.3, "t": "mark", "k": "neutral", "c": [0.47, 0.68]},
			{"at": 6.1, "t": "arrow", "k": "route", "p": [0.10, 0.80, 0.50, 0.80, 0.74, 0.80], "s": "Waggon für Waggon"},
			{"at": 6.5, "t": "arrow", "k": "route", "p": [0.30, 0.58, 0.45, 0.54, 0.60, 0.58], "s": "Dach"},
		],
	},
	"villa": {
		"ref": "Traunsee, Westufer · 1:2 500", "grid": "33U UP 61",
		"terrain": [
			{"k": "water", "p": [0.80, 0.0, 1.0, 0.0, 1.0, 1.0, 0.74, 1.0, 0.78, 0.60, 0.76, 0.30]},
			{"k": "forest", "p": [0.0, 0.0, 0.26, 0.0, 0.22, 0.30, 0.30, 0.50, 0.0, 0.56]},
			{"k": "forest", "r": [0.0, 0.84, 0.74, 0.16]},
			{"k": "field", "r": [0.36, 0.30, 0.38, 0.48]},
			{"k": "block", "r": [0.52, 0.38, 0.14, 0.14]}, {"k": "block", "r": [0.72, 0.58, 0.06, 0.06]},
			{"k": "road", "p": [0.40, 0.0, 0.46, 0.22, 0.56, 0.36]},
			{"k": "path", "p": [0.78, 0.62, 0.90, 0.60]},
			{"k": "contour", "p": [0.04, 0.20, 0.14, 0.26, 0.16, 0.40, 0.08, 0.48]},
			{"k": "label", "c": [0.04, 0.12], "s": "HANG"}, {"k": "label", "c": [0.52, 0.355], "s": "VILLA"},
			{"k": "label", "c": [0.64, 0.66], "s": "BOOTSHAUS"}, {"k": "label", "c": [0.84, 0.64], "s": "STEG"},
			{"k": "label", "c": [0.40, 0.02], "s": "EINFAHRT"}, {"k": "label", "c": [0.86, 0.04], "s": "TRAUNSEE"},
			{"k": "label", "c": [0.42, 0.74], "s": "GARTEN"},
		],
		"cues": [
			{"at": 1.3, "t": "arrow", "k": "hvt", "p": [0.98, 0.98, 0.90, 0.70, 0.66, 0.46], "s": "Spur aus Rostock"},
			{"at": 2.1, "t": "mark", "k": "objective", "c": [0.59, 0.45], "s": "Villa"},
			{"at": 2.4, "t": "mark", "k": "neutral", "c": [0.75, 0.61], "s": "Bootshaus"},
			{"at": 2.6, "t": "mark", "k": "enemy", "c": [0.90, 0.56], "s": "Wasserflugzeug"},
			{"at": 2.8, "t": "mark", "k": "enemy", "c": [0.48, 0.30], "s": "Wachdienst / Kameras"},
			{"at": 2.9, "t": "mark", "k": "enemy", "c": [0.68, 0.52]},
			{"at": 3.2, "t": "mark", "k": "hvt", "c": [0.60, 0.42], "s": "Weber"},
			{"at": 4.1, "t": "mark", "k": "friend", "c": [0.12, 0.34], "s": "Kerner (Drohne)"},
			{"at": 4.5, "t": "arrow", "k": "route", "p": [0.14, 0.38, 0.32, 0.80, 0.70, 0.70, 0.62, 0.53], "s": "leise"},
			{"at": 4.8, "t": "arrow", "k": "enemy", "p": [0.14, 0.32, 0.32, 0.12, 0.46, 0.22, 0.55, 0.36], "s": "laut: Einfahrt"},
			{"at": 5.2, "t": "zone", "k": "friend", "c": [0.40, 0.93], "r": 0.10, "s": "Brandt (Heli)"},
		],
	},
	"spreebogen": {
		"ref": "Berlin-Moabit · 1:10 000", "grid": "33U UU 88",
		"terrain": [
			{"k": "water", "p": [0.0, 0.08, 0.4, 0.12, 0.7, 0.06, 1.0, 0.10, 1.0, 0.18, 0.7, 0.14, 0.4, 0.20, 0.0, 0.16]},
			{"k": "block", "r": [0.04, 0.26, 0.16, 0.16]}, {"k": "block", "r": [0.26, 0.26, 0.18, 0.16]},
			{"k": "block", "r": [0.64, 0.26, 0.30, 0.16]}, {"k": "block", "r": [0.04, 0.50, 0.12, 0.18]},
			{"k": "block", "r": [0.34, 0.62, 0.12, 0.14]}, {"k": "block", "r": [0.60, 0.50, 0.14, 0.18]},
			{"k": "block", "r": [0.78, 0.50, 0.16, 0.18]}, {"k": "block", "r": [0.32, 0.82, 0.30, 0.14]},
			{"k": "road", "p": [0.22, 1.0, 0.24, 0.72, 0.50, 0.58, 0.54, 0.24, 0.58, 0.04]},
			{"k": "road", "p": [0.0, 0.46, 1.0, 0.46]},
			{"k": "label", "c": [0.04, 0.04], "s": "SPREE"}, {"k": "label", "c": [0.60, 0.21], "s": "MOLTKEBRÜCKE"},
			{"k": "label", "c": [0.04, 0.97], "s": "MOABIT"}, {"k": "label", "c": [0.66, 0.02], "s": "REGIERUNGSVIERTEL"},
			{"k": "label", "c": [0.70, 0.445], "s": "UFERPLATZ"},
		],
		"cues": [
			{"at": 1.2, "t": "zone", "k": "friend", "c": [0.80, -0.05], "r": 0.30, "s": "Belagerungsring"},
			{"at": 3.1, "t": "mark", "k": "friend", "c": [0.22, 0.93], "s": "SPz „Rabe“"},
			{"at": 3.4, "t": "arrow", "k": "route", "p": [0.22, 0.90, 0.24, 0.72, 0.50, 0.58, 0.53, 0.30], "s": "Durchbruch"},
			{"at": 3.7, "t": "mark", "k": "objective", "c": [0.56, 0.14], "s": "Moltkebrücke"},
			{"at": 4.1, "t": "mark", "k": "enemy", "c": [0.30, 0.68], "s": "Panzerfaust"},
			{"at": 4.2, "t": "mark", "k": "enemy", "c": [0.46, 0.55]},
			{"at": 4.5, "t": "arrow", "k": "enemy", "p": [0.98, 0.46, 0.62, 0.46], "s": "Garde"},
			{"at": 4.7, "t": "arrow", "k": "enemy", "p": [0.0, 0.46, 0.34, 0.48]},
			{"at": 5.1, "t": "zone", "k": "objective", "c": [0.56, 0.14], "r": 0.07, "s": "bis Sonnenaufgang"},
		],
	},
	"funkturm": {
		"ref": "Messegelände Charlottenburg · 1:5 000", "grid": "33U UU 85",
		"terrain": [
			{"k": "block", "r": [0.06, 0.62, 0.26, 0.32]}, {"k": "block", "r": [0.68, 0.62, 0.26, 0.32]},
			{"k": "block", "r": [0.06, 0.16, 0.22, 0.30]}, {"k": "block", "r": [0.74, 0.12, 0.20, 0.28]},
			{"k": "zone", "r": [0.36, 0.52, 0.28, 0.20]},
			{"k": "road", "p": [0.50, 1.0, 0.50, 0.72]}, {"k": "road", "p": [0.0, 0.08, 1.0, 0.06]},
			{"k": "label", "c": [0.08, 0.60], "s": "MESSEHALLEN"}, {"k": "label", "c": [0.38, 0.73], "s": "PLAZA"},
			{"k": "label", "c": [0.56, 0.30], "s": "FUNKTURM 60 m"}, {"k": "label", "c": [0.38, 0.03], "s": "MESSEDAMM"},
		],
		"cues": [
			{"at": 1.4, "t": "mark", "k": "hvt", "c": [0.50, 0.38], "s": "Riedhammer auf Sendung"},
			{"at": 2.1, "t": "zone", "k": "enemy", "c": [0.50, 0.50], "r": 0.30, "s": "Garde"},
			{"at": 3.05, "t": "mark", "k": "friend", "c": [0.50, 0.95], "s": "Kerner"},
			{"at": 3.15, "t": "arrow", "k": "route", "p": [0.50, 0.92, 0.50, 0.62, 0.50, 0.44], "s": "Plaza"},
			{"at": 3.4, "t": "mark", "k": "objective", "c": [0.50, 0.40], "s": "Sendepult"},
			{"at": 3.8, "t": "mark", "k": "friend", "c": [0.42, 0.42], "s": "Lena"},
			{"at": 4.1, "t": "arrow", "k": "route", "p": [0.52, 0.40, 0.64, 0.42, 0.66, 0.70], "s": "Fassadenlift"},
			{"at": 4.5, "t": "arrow", "k": "enemy", "p": [1.0, 0.80, 0.80, 0.70, 0.68, 0.68], "s": "Falk riegelt ab"},
		],
	},
	"kanalisation": {
		"ref": "Kanalnetz Tiergarten · Leitungsplan", "grid": "33U UU 89-K",
		"terrain": [
			{"k": "block", "r": [0.34, 0.06, 0.28, 0.18]}, {"k": "block", "r": [0.78, 0.08, 0.18, 0.18]},
			{"k": "forest", "r": [0.0, 0.70, 0.22, 0.30]},
			{"k": "tunnel", "p": [0.08, 0.86, 0.30, 0.70, 0.60, 0.56, 0.86, 0.30, 0.88, 0.22]},
			{"k": "tunnel", "p": [0.44, 0.62, 0.40, 0.40, 0.62, 0.36]},
			{"k": "water", "p": [0.50, 0.66, 0.60, 0.62, 0.66, 0.70, 0.56, 0.74]},
			{"k": "label", "c": [0.36, 0.04], "s": "REICHSTAG (OBEN)"}, {"k": "label", "c": [0.78, 0.06], "s": "KANZLERAMT"},
			{"k": "label", "c": [0.02, 0.68], "s": "TIERGARTEN"}, {"k": "label", "c": [0.30, 0.62], "s": "SAMMLER"},
			{"k": "label", "c": [0.56, 0.77], "s": "BECKEN"},
		],
		"cues": [
			{"at": 1.2, "t": "zone", "k": "friend", "c": [0.10, 0.02], "r": 0.16, "s": "Divisionen"},
			{"at": 1.6, "t": "zone", "k": "enemy", "c": [0.87, 0.17], "r": 0.10, "s": "Riedhammer"},
			{"at": 2.1, "t": "mark", "k": "friend", "c": [0.08, 0.88], "s": "Voss · Versorgungsgang"},
			{"at": 2.5, "t": "arrow", "k": "route", "p": [0.10, 0.85, 0.30, 0.71, 0.60, 0.57, 0.86, 0.30], "s": "Sammler"},
			{"at": 3.3, "t": "mark", "k": "enemy", "c": [0.34, 0.66], "s": "Gardestreife"},
			{"at": 3.5, "t": "mark", "k": "enemy", "c": [0.66, 0.50]},
			{"at": 4.1, "t": "mark", "k": "charge", "c": [0.48, 0.61], "s": "Ladungen"},
			{"at": 4.2, "t": "mark", "k": "charge", "c": [0.74, 0.44]},
			{"at": 4.6, "t": "mark", "k": "enemy", "c": [0.96, 0.40], "s": "Falk (Funk)"},
			{"at": 5.5, "t": "mark", "k": "objective", "c": [0.88, 0.22], "s": "Leiter → Keller"},
		],
	},
	"kanzleramt": {
		"ref": "Kanzleramt · Grundriss EG / 2. OG", "grid": "33U UU 89-A",
		"terrain": [
			{"k": "block", "p": [0.20, 0.10, 0.80, 0.10, 0.80, 0.90, 0.20, 0.90]},
			{"k": "zone", "r": [0.36, 0.60, 0.28, 0.26]},
			{"k": "zone", "r": [0.22, 0.40, 0.24, 0.16]}, {"k": "zone", "r": [0.54, 0.40, 0.24, 0.16]},
			{"k": "zone", "r": [0.22, 0.14, 0.18, 0.20]}, {"k": "zone", "r": [0.56, 0.12, 0.22, 0.20]},
			{"k": "tunnel", "p": [0.50, 1.0, 0.50, 0.86]}, {"k": "tunnel", "p": [0.80, 0.20, 0.98, 0.20]},
			{"k": "label", "c": [0.38, 0.84], "s": "LOBBY"}, {"k": "label", "c": [0.23, 0.38], "s": "KABINETTSSAAL"},
			{"k": "label", "c": [0.55, 0.38], "s": "OSTBÜRO"}, {"k": "label", "c": [0.23, 0.12], "s": "WESTBÜRO"},
			{"k": "label", "c": [0.57, 0.10], "s": "SAAL UNTERM DACH"}, {"k": "label", "c": [0.84, 0.17], "s": "BUNKERGANG"},
		],
		"cues": [
			{"at": 1.3, "t": "zone", "k": "friend", "c": [0.50, 0.50], "r": 0.50, "s": "Ring der Divisionen"},
			{"at": 2.2, "t": "mark", "k": "hostage", "c": [0.34, 0.49], "s": "Geiseln"},
			{"at": 2.3, "t": "mark", "k": "hostage", "c": [0.31, 0.25]},
			{"at": 2.6, "t": "mark", "k": "hostage", "c": [0.67, 0.22], "s": "Hartmann"},
			{"at": 3.1, "t": "arrow", "k": "route", "p": [0.50, 0.99, 0.50, 0.76], "s": "Tunnel"},
			{"at": 3.6, "t": "mark", "k": "charge", "c": [0.42, 0.68], "s": "Säulen"},
			{"at": 3.7, "t": "mark", "k": "charge", "c": [0.58, 0.68]},
			{"at": 4.1, "t": "arrow", "k": "route", "p": [0.50, 0.74, 0.40, 0.56, 0.62, 0.50, 0.36, 0.30, 0.70, 0.30, 0.67, 0.24], "s": "Raum für Raum"},
			{"at": 4.5, "t": "mark", "k": "enemy", "c": [0.72, 0.46], "s": "Garde"},
		],
	},
	"bunker": {
		"ref": "Regierungsbunker · Schnitt / Grundriss", "grid": "33U UU 89-B",
		"terrain": [
			{"k": "water", "r": [0.0, 0.0, 1.0, 0.12]},
			{"k": "tunnel", "p": [0.02, 0.90, 0.30, 0.86]},
			{"k": "zone", "r": [0.30, 0.78, 0.08, 0.12]},
			{"k": "block", "r": [0.38, 0.64, 0.20, 0.24]}, {"k": "block", "r": [0.40, 0.42, 0.24, 0.16]},
			{"k": "block", "r": [0.64, 0.26, 0.16, 0.16]}, {"k": "block", "r": [0.80, 0.14, 0.16, 0.16]},
			{"k": "tunnel", "p": [0.58, 0.64, 0.56, 0.58]}, {"k": "tunnel", "p": [0.64, 0.50, 0.68, 0.42]},
			{"k": "label", "c": [0.04, 0.04], "s": "SPREE"}, {"k": "label", "c": [0.02, 0.94], "s": "VERSORGUNGSRÖHRE"},
			{"k": "label", "c": [0.29, 0.75], "s": "SCHLEUSE"}, {"k": "label", "c": [0.40, 0.90], "s": "TECHNIKEBENE"},
			{"k": "label", "c": [0.40, 0.395], "s": "SCHLAFSÄLE"}, {"k": "label", "c": [0.62, 0.44], "s": "LAGEZENTRUM"},
			{"k": "label", "c": [0.78, 0.32], "s": "KONTROLLRAUM"},
		],
		"cues": [
			{"at": 1.2, "t": "mark", "k": "hvt", "c": [0.88, 0.22], "s": "Riedhammer"},
			{"at": 1.5, "t": "mark", "k": "enemy", "c": [0.72, 0.34], "s": "Falks Garde"},
			{"at": 1.8, "t": "line", "k": "enemy", "p": [0.88, 0.22, 0.92, 0.10, 0.70, 0.02], "s": "Zündleitung"},
			{"at": 2.3, "t": "mark", "k": "enemy", "c": [0.94, 0.12], "s": "Panzertür"},
			{"at": 3.3, "t": "arrow", "k": "route", "p": [0.02, 0.88, 0.30, 0.84], "s": "Röhre (geflutet)"},
			{"at": 4.2, "t": "mark", "k": "friend", "c": [0.12, 0.96], "s": "Lena · Haustechnik"},
			{"at": 4.6, "t": "mark", "k": "objective", "c": [0.34, 0.84], "s": "Schleuse"},
			{"at": 5.1, "t": "arrow", "k": "route", "p": [0.36, 0.82, 0.48, 0.76, 0.56, 0.60, 0.52, 0.50, 0.66, 0.46, 0.72, 0.34, 0.86, 0.24]},
			{"at": 6.2, "t": "zone", "k": "objective", "c": [0.88, 0.22], "r": 0.08, "s": "General stellen"},
		],
	},
}


static func has_map(level: String) -> bool:
	return MAPS.has(level)


static func get_map(level: String) -> Dictionary:
	return MAPS.get(level, {})


## Satzanfaenge (Zeichenindex) wie der Lagebericht gelesen wird: Trennung nach . ! ? gefolgt von Leerzeichen,
## aber nicht nach reinen Zahlen ("24. Juni").
static func sentence_starts(text: String) -> PackedInt32Array:
	var out := PackedInt32Array([0])
	var n := text.length()
	var i := 0
	while i < n - 1:
		var c := text[i]
		if (c == "." or c == "!" or c == "?") and text[i + 1] == " ":
			var j := i - 1
			while j >= 0 and text[j] != " ":
				j -= 1
			var word := text.substr(j + 1, i - j - 1)
			if not word.is_valid_int():
				var k := i + 1
				while k < n and text[k] == " ":
					k += 1
				if k < n:
					out.append(k)
		i += 1
	return out


## Zeichenindex, an dem ein Hinweis mit "at" (Satz.Anteil) erscheint.
static func cue_char(starts: PackedInt32Array, text_len: int, at: float) -> int:
	var si := clampi(int(floor(at)), 0, starts.size() - 1)
	var s0 := starts[si]
	var s1 := starts[si + 1] if si + 1 < starts.size() else text_len
	return s0 + int(float(s1 - s0) * clampf(at - float(si), 0.0, 0.99))
