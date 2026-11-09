extends RefCounted
class_name StoryData
## Alle Story-Texte (fiktiv). Briefings fuer die Titelkarten, Funksprueche/Ziele fuer Level ohne eigene Story-Logik.
## Eintrag: {"at": "start" | "z:<wert>" | "cp:<id>", "objective": "...", "lines": [[sprecher, text], ...]}

const WEBER := "Hptm. Weber"
const LENA := "Lena Aksoy"
const KERNER := "Kerner"

## Lagebericht unter Ort/Zeit (2-4 Saetze, Schreibmaschinen-Effekt).
const BRIEFINGS := {
	"baltic_night": "Russische Verbände haben in der Nacht die lettische Grenze überschritten. Die EU-Kampfgruppe „Nord“ soll die Linie halten, bis Verstärkung eintrifft. Ihr Zug stößt über das Feld vor, nimmt die Stellungen am Waldrand und sichert den Bahnübergang.",
	"test_range": "Daugavpils ist seit vier Stunden umkämpft. Feindliche Infanterie hat sich in der Hauptstraße eingegraben, ein MG-Nest blockiert die Kreuzung. Kampfgruppe „Nord“ nimmt die Straße zurück – Haus für Haus.",
	"river_crossing": "Der Gegner zieht sich hinter die Welikaja zurück und will die letzte intakte Brücke sprengen. Fällt sie, steht der Vormarsch für Wochen. Die Brücke muss genommen werden, bevor es hell wird.",
	"rail_yard": "Pskow steht kurz vor dem Fall. Am Güterbahnhof wartet ein Zug mit Gefangenen und Munition auf die Abfahrt nach Osten. Hält Kampfgruppe „Nord“ den Bahnhof, sind die Waffenstillstandsgespräche nur noch Formsache.",
	"berlin": "Der Krieg ist vorbei. Berlin feiert den Waffenstillstand vor dem Regierungsviertel, die Kampfgruppe „Nord“ steht als Ehrenformation an der Bühne. Hauptmann Weber hat euch persönlich für die Feier eingeteilt.",
}

const SCRIPTS := {
	"baltic_night": [
		{"at": "start", "objective": "Überquere das Feld und nimm die feindlichen Stellungen",
			"lines": [[WEBER, "Kerner, hier Weber. Euer Zug überquert das Feld. Die Stellungen am Waldrand müssen fallen, bevor es hell wird."],
				[LENA, "Bin direkt hinter dir, Jonas. Kopf unten."]]},
		{"at": "z:-40", "lines": [[LENA, "Bewegung bei den Sandsäcken! Zwölf Uhr!"]]},
		{"at": "cp:cp_forest", "objective": "Kämpf dich durch den Wald ins Dorf",
			"lines": [[WEBER, "Stellung genommen. Weiter durch den Wald – das Dorf dahinter ist besetzt."]]},
		{"at": "z:-123", "lines": [[LENA, "Artillerie! Runter!"]]},
		{"at": "cp:cp_square", "objective": "Sichere den Dorfplatz und erreiche den Bahnübergang",
			"lines": [[WEBER, "Dorfplatz. Achtet auf den Wasserturm – und das Tanklager geht hoch wie eine Bombe."],
				[LENA, "Dann lassen wir es hochgehen. Bei denen."]]},
		{"at": "z:-212", "lines": [[WEBER, "Bahnübergang voraus. Sammelpunkt dahinter. Bringt alle nach Hause."]]},
	],
	"test_range": [
		{"at": "start", "objective": "Nimm die Hauptstraße zurück",
			"lines": [[WEBER, "Kerner, die Hauptstraße. Haus für Haus, bis zum Tor am Ende."],
				[LENA, "Achte auf die Dächer. Die lieben ihre Scharfschützen."]]},
		{"at": "z:-46", "lines": [[LENA, "Rakete im Anflug! Das Haus kommt runter – weg da!"]]},
		{"at": "cp:cp_section2", "objective": "Schalte das MG-Nest an der Kreuzung aus",
			"lines": [[WEBER, "Panzerwrack voraus, dahinter das MG. Nutzt die Deckung."],
				[LENA, "Schon gehört? Von Hagen will nach dem Krieg in Berlin „aufräumen“. Was immer das heißt."],
				[WEBER, "Politik ist nicht unser Job, Aksoy. Funkdisziplin."]]},
		{"at": "cp:cp_section3", "objective": "Erreiche das Tor am Ende der Straße",
			"lines": [[WEBER, "Fast geschafft. Das Tor am Ende, dann gehört die Straße uns."]]},
	],
}

## Endsequenz nach Berlin (Texttafeln, je [text, sekunden]).
const ENDING := [
	["Weber hatte den Funk. Er wusste, wo wir standen. Jeder Schritt, jede Nacht.", 4.5],
	["Die Ordnungsfront hält das Regierungsviertel. Sie nennt es Ordnung.\nWir nennen es, was es ist: ein Putsch.", 5.0],
	["General von Hagen spricht auf allen Kanälen. Er verspricht Sicherheit.\nEr hat sie mit Sprengstoff bezahlt.", 5.0],
	["Lena und ich sind noch hier. Und wir sind nicht die Einzigen.", 4.0],
]
