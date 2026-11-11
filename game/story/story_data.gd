extends RefCounted
class_name StoryData
## Alle Story-Texte (fiktiv). Briefings fuer die Titelkarten, Funksprueche/Ziele fuer Level ohne eigene Story-Logik.
## Eintrag: {"at": "start" | "z:<wert>" | "cp:<id>", "objective": "...", "lines": [[sprecher, text], ...]}

const WEBER := "Hptm. Weber"
const LENA := "Lena Aksoy"
const KERNER := "Kerner"
const VOSS := "Konrad Voss"            # Teil 2: Anfuehrer des Widerstands (Ex-Bundespolizei)
const BRANDT := "Oberstlt. Brandt"     # Teil 2: Kommandant des Gunships "Waechter" (Luftwaffe, loyal)
const ORDNUNG := "Ordnungsfront-Funk"  # Teil 2: abgehoerter Feindfunk / Lautsprecher
const FALK := "Oberst Falk"            # Teil 3: Kommandeur der Garde, wiederkehrender Gegenspieler (Funk)
const RIEDHAMMER := "General von Riedhammer"
const HARTMANN := "Präsidentin Hartmann"  # Teil 3: Bundestagspraesidentin (fiktiv), Geisel im Kanzleramt

## Lagebericht unter Ort/Zeit (2-4 Saetze, Schreibmaschinen-Effekt).
const BRIEFINGS := {
	"baltic_night": "Russische Verbände haben in der Nacht die lettische Grenze überschritten. Die EU-Kampfgruppe „Nord“ soll die Linie halten, bis Verstärkung eintrifft. Ihr Zug stößt über das Feld vor, nimmt die Stellungen am Waldrand und sichert den Bahnübergang.",
	"test_range": "Daugavpils ist seit vier Stunden umkämpft. Feindliche Infanterie hat sich in der Hauptstraße eingegraben, ein MG-Nest blockiert die Kreuzung. Kampfgruppe „Nord“ nimmt die Straße zurück – Haus für Haus.",
	"river_crossing": "Der Gegner zieht sich hinter die Welikaja zurück und will die letzte intakte Brücke sprengen. Fällt sie, steht der Vormarsch für Wochen. Die Brücke muss genommen werden, bevor es hell wird.",
	"rail_yard": "Pskow steht kurz vor dem Fall. Am Güterbahnhof wartet ein Zug mit Gefangenen und Munition auf die Abfahrt nach Osten. Hält Kampfgruppe „Nord“ den Bahnhof, sind die Waffenstillstandsgespräche nur noch Formsache.",
	"berlin": "Der Krieg ist vorbei. Berlin feiert den Waffenstillstand vor dem Regierungsviertel, die Kampfgruppe „Nord“ steht als Ehrenformation an der Bühne. Hauptmann Weber hat euch persönlich für die Feier eingeteilt.",
	# --- Teil 2 (je Level vom zustaendigen Agenten gefuellt) ---
	"curfew": "Seit dem Putsch gilt in Berlin nächtliche Ausgangssperre – Streifen der Ordnungsfront schießen ohne Warnung. In der Fernmeldestelle des Innenministeriums liegen Hauptmann Webers Funkprotokolle aus der Nacht des Anschlags. Kerner muss ungesehen hinein, die Daten ziehen und durch den alten U-Bahn-Tunnel zu Konrad Voss entkommen.",
	"overwatch": "Die Ordnungsfront verlegt Gefangene aus Spandau nach Norden – unter ihnen Oberstleutnant Brandt. Der Konvoi passiert im Morgennebel das stillgelegte Stahlwerk Hennigsdorf. Voss’ Leute legen sich an der Werksstraße in den Hinterhalt, Kerner deckt sie mit dem Zielfernrohr vom Übergabeturm.",
	"gunship": "Brandt hat die „Wächter“ wieder in die Luft gebracht – ein umgebauter A400M mit drei Geschützen und Wärmebild. Lena und Voss stürmen den Fliegerhorst Lindenau, wo die Ordnungsfront Jets für Angriffe auf aufständische Städte betankt und der Sendemast steht. Kerner sitzt am Feuerleitstand; eigene Leute tragen IR-Blinker.",
	"funkturm": "24. Juni 2030, 21:40. Sechs Tage nachdem Weber am Traunsee entkommen ist, spricht General von Riedhammer heute Nacht vom Funkturm an der Messe zu ganz Berlin. Die Garde hält das Messegelände und den Turm. Kerner stürmt die Plaza, steigt durch Betonkern und Stahlgitter auf 60 Meter, kappt die Sendung und hält das Pult, bis Lena ihre eigene Botschaft auf Sendung gebracht hat. Danach bleibt nur der Fassadenlift – bevor Oberst Falk den Turmfuß abriegelt.",
	"kanalisation": "25. Juni 2030, 01:50. Die loyalen Divisionen stehen noch am Spreebogen, das Kanzleramt ist in Riedhammers Hand. Voss führt Kerner zu einem vergessenen Versorgungsgang im Tiergarten – von dort geht es durch den alten Sammler unter dem Reichstag. Stockdunkel, knietiefes Wasser, Gardestreifen mit Lampen. An den Fundamentpfeilern hängen Ladungen mit Lichtschranken, und auf dem Gardefunk spricht Oberst Falk. Lautlos bleiben, entschärfen oder umgehen – und am Ende die Leiter hoch in den Keller des Kanzleramts.",
	"kanzleramt": "25. Juni 2030, 03:20. Zwei Wochen nach der Ausstrahlung der Protokolle schließen loyale Divisionen den Ring um das Regierungsviertel. Riedhammers Garde hält den Spreebogen und hat im Kanzleramt Abgeordnete als Geiseln genommen – unter ihnen Bundestagspräsidentin Hartmann. Durch Voss’ alten Versorgungstunnel dringt Kerner nachts unter die Lobby vor, wo die Garde die Säulen mit Sprengladungen versehen hat. Raum für Raum – und keine Geisel darf sterben.",
	"spreebogen": "24. Juni 2030, 05:10. Zwei Wochen nach der Ausstrahlung der Protokolle liegt der Belagerungsring um das Regierungsviertel. Kerner und Lena sind gerade erst von der Jagd auf Weber zurück – am Traunsee ist er ihnen entkommen. Jetzt führt der Schützenpanzer „Rabe“ den Durchbruch von Moabit zur Moltkebrücke an: Voss fährt, Lena kommandiert, Kerner sitzt am Turm. In den Fenstern warten Panzerfaust-Trupps, in den Seitenstraßen die Garde. Die Brücke muss bis Sonnenaufgang in unserer Hand sein.",
	"bunker": "25. Juni 2030, 04:40. Riedhammer hat sich hinter der Panzertür des Regierungsbunkers eingemauert, mit Falks letzter Garde und einer Zündleitung zu den Ladungen unter dem Spreebogen. Oben kommt niemand durch. Es bleibt der zweite Zugang: eine alte Versorgungsröhre unter der Spree, halb voll Wasser. Lena hat die Haustechnik und öffnet die Schleusen. Danach geht es durch Technikebene, Schlafsäle und Lagezentrum bis in den Kontrollraum. Diesmal entkommt der General nicht.",
	"villa": "18. Juni 2030, 20:15. Sechs Tage hat Lena gebraucht, um Webers Spur aus dem Rostocker Hafen bis an den Traunsee zu verfolgen. Die Villa am Westufer gehört einem Strohmann des Konsortiums: Bootshaus, Steg, ein Wasserflugzeug startbereit, privater Wachdienst mit Kameras. Weber ist seit Mittag im Haus. Kerner klärt vom Hang mit der Drohne auf und geht dann rein – leise über Bootshaus und Garten oder durch die Einfahrt. Brandt kreist mit dem Hubschrauber südlich über dem Wald. Diesmal will Kerner Antworten, keine Verfolgungsjagd.",
	"hafen": "12. Juni 2030, 23:10. Drei Tage nach der Ausstrahlung ist Hauptmann Weber auf der Flucht, mit der Akte Nordlicht im Gepäck. Ein Hinweis führt in den Überseehafen Rostock, Liegeplatz sieben. Voss bleibt in Berlin. Brandt fliegt euch inoffiziell an die Küste. Kerner liegt mit der G28 auf einem Portalkran, Lena geht unten durch das Containerlager. Es regnet, der Seewind ist böig. Und ihr seid nicht die Einzigen: Falks Garde-Jäger in grauen Mänteln suchen Weber ebenfalls. Weber wird lebend gebraucht, und die Akte mit ihm.",
	"alpenpass": "15. Juni 2030, 06:30. Drei Tage nach Rostock will Weber am Grenzpass bei Mittenwald nach Österreich. Ein Schneesturm liegt über dem Pass. Brandt setzt Kerner und Aksoy oberhalb des Kessels ab, ein Mörserzug loyaler Gebirgsjäger steht hinter dem Grat bereit – wer sieht, kann Feuer anfordern. Webers Nachhut hält die Passstraße, und Falks Garde-Jäger in grauen Wintermänteln sind ebenfalls unterwegs. Weber wird lebend gebraucht.",
	"nachtzug": "16. Juni 2030, 22:40. Weber ist am Pass entkommen. Lena hat ihn auf der Buchungsliste des Nachtzugs Innsbruck–Wien der Alpen-Donau-Bahn gefunden: Schlafwagen, Abteil neun, unter falschem Namen. Kerner und Lena steigen in Innsbruck zu. Falks Garde-Jäger in grauen Mänteln sind ebenfalls an Bord. Im Zug sitzen Reisende, die mit alldem nichts zu tun haben – kein Unbeteiligter darf getroffen werden. Waggon für Waggon nach vorn, notfalls über das Dach. Weber wird lebend gebraucht.",
	"ep_lena": "3. Juni 2030, 01:35 – dieselbe Nacht wie die Ausgangssperre. Lena Aksoy liegt mit der G28 auf dem Dach eines Wohnblocks gegenüber dem Sperrgebiet. Kerner muss unten ungesehen bis zur Fernmeldestelle im Ministeriumsanbau. Er wartet an jeder Hausecke, bis Lena den Weg freigeschossen hat. Am Platz wechselt sie aufs Ministeriumsdach – dort streicht ein Suchscheinwerfer, und auf dem Regierungsbau liegt ein Gegenscharfschütze. Die Lieferzufahrt sieht sie nicht ein, dafür hat sie die Aufklärungsdrohne. Wird Kerner entdeckt, wehrt er sich – fällt er, ist alles verloren."
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
				[LENA, "Schon gehört? Von Riedhammer will nach dem Krieg in Berlin „aufräumen“. Was immer das heißt."],
				[WEBER, "Politik ist nicht unser Job, Aksoy. Funkdisziplin."]]},
		{"at": "cp:cp_section3", "objective": "Erreiche das Tor am Ende der Straße",
			"lines": [[WEBER, "Fast geschafft. Das Tor am Ende, dann gehört die Straße uns."]]},
	],
	"curfew": [
		{"at": "start", "objective": "Schleich dich zur Fernmeldestelle im Ministeriumsanbau",
			"lines": [[LENA, "Jonas, ich bin auf dem Dach gegenüber. Ab hier gilt Ausgangssperre – wer sich bewegt, wird erschossen."],
				[KERNER, "Dann sollte mich besser keiner sehen."],
				[LENA, "Bleib in den Schatten, geh in die Hocke. Die Schalldämpferpistole ist leise, Gewehrfeuer hört das ganze Viertel. Von hinten kannst du sie mit [F] lautlos ausschalten."]]},
		{"at": "z:-30", "lines": [[LENA, "Vorne ist ein Kontrollpunkt mit Flutlicht. Links durch die Höfe ist es dunkler – aber da läuft auch einer Streife."]]},
		{"at": "cp:cp_plaza", "objective": "Erreiche die Lieferzufahrt rechts neben dem Ministerium",
			"lines": [[LENA, "Der Platz. Drohne in der Luft, Scheinwerfer auf dem Anbau. Rechts hinten die Lieferzufahrt – das Rolltor steht halb offen."],
				[ORDNUNG, "Bürger Berlins: Die Ausgangssperre dient Ihrem Schutz. Verstöße werden ohne Vorwarnung geahndet."]]},
		{"at": "cp:cp_annex", "objective": "Finde die Fernmeldestelle und lade Webers Funkprotokolle herunter",
			"lines": [[LENA, "Du bist drin. Vorsicht: Löst du hier drin Alarm aus, löschen sie die Server. Dann ist alles weg."],
				[KERNER, "Verstanden. Kein Lärm."]]},
		{"at": "cp:cp_tunnel", "objective": "Erreiche Konrad Voss",
			"lines": [[VOSS, "Kerner? Hier unten. Folgen Sie dem Licht – die Gleise entlang."]]},
	],
}

## Endsequenz nach Berlin (Teil 1) (Texttafeln, je [text, sekunden]).
const ENDING := [
	["Weber hatte den Funk. Er wusste, wo wir standen. Jeder Schritt, jede Nacht.", 4.5],
	["Die Ordnungsfront hält das Regierungsviertel. Sie nennt es Ordnung.\nWir nennen es, was es ist: ein Putsch.", 5.0],
	["General von Riedhammer spricht auf allen Kanälen. Er verspricht Sicherheit.\nEr hat sie mit Sprengstoff bezahlt.", 5.0],
	["Lena und ich sind noch hier. Und wir sind nicht die Einzigen.", 4.0],
]

## Endsequenz nach "gunship" (Teil 2) – vom Gunship-Agenten gefuellt.
const ENDING_2 := [
	["Um 03:41 lief Webers Funkprotokoll auf jedem Sender zwischen Rügen und Passau.
Seine eigene Stimme. Die Uhrzeiten. Die Befehle zur Bühne.", 5.5],
	["Bis zum Morgen hatten drei Divisionen die Ordnungsfront verlassen.
In Leipzig öffneten Soldaten die Kasernentore. In Hamburg drehten sie die Kanonen um.", 5.5],
	["Riedhammer hat sich mit seiner Garde im Regierungsviertel verschanzt.
Er spricht jetzt nur noch nachts. Seine Stimme ist leiser geworden.", 5.0],
	["Weber war nicht in Lindenau. Niemand weiß, wohin er gegangen ist.
Ich weiß nur: Er hat mehr gewusst, als in den Protokollen steht.", 5.0],
	["Brandt hat die Wächter auf einer Autobahn bei Neuruppin abgestellt.
Lena sagt, wir sind fast am Ende. Ich glaube, wir sind erst am Anfang.", 5.0],
]

## Endsequenz nach "villa" (Teil 3 – Jagd auf Weber) – vom Villa-Agenten gefuellt.
const ENDING_3 := [
	["Das Wasserflugzeug verschwand über dem Höllengebirge nach Nordosten.
Brandt verlor es kurz vor Passau aus dem Radar.", 5.0],
	["Die halbe Akte Nordlicht lag auf meinem Schoß, den ganzen Flug zurück.
Konten, Strohmänner, Überweisungen. Echt, bis zur letzten Seite.", 5.5],
	["Lena fragte, warum die Jäger nicht auf uns geschossen haben, als wir zum Steg liefen.
Ich hatte keine Antwort. Falk wusste, wo wir sind. Vielleicht schon seit Rostock.", 6.0],
	["Und Weber sagte, Riedhammer vertraut seinen Leitungen.
Ich habe mich gefragt, woher er das so genau weiß.", 5.0],
]

## Endsequenz nach "bunker" (Teil 4 – Die Garde) – vom Bunker-Agenten gefuellt (Varianten je nach Entscheidung: siehe CONTRACTS Runde 7).
const ENDING_4 := [
	["Um 05:12 brach die Decke des Kontrollraums ein. Riedhammer hatte sich mit seinem Bunker gesprengt,
auf seinem Posten, wie er es nannte. Oberst Falk war tot. Bis zum Mittag hatte die Garde die Waffen niedergelegt.", 6.0],
	["Präsidentin Hartmann rief den Bundestag zusammen, im Saal mit den zerschossenen Fenstern.
Lena sagt, es ist vorbei. Diesmal glaube ich ihr.", 5.0],
	["Am Abend stand ich am Spreeufer. Die Stadt war still.
Zum ersten Mal seit Wochen hörte ich nur das Wasser.", 6.0],
]

## Variante "arrest": Kerner nimmt Weber fest (Settings "game/weber_choice").
const ENDING_4_ARREST := [
	["Um 05:12 brach die Decke des Kontrollraums ein. Riedhammer hatte sich mit seinem Bunker gesprengt,
auf seinem Posten, wie er es nannte. Oberst Falk war tot. Bis zum Mittag hatte die Garde die Waffen niedergelegt.", 6.0],
	["Weber kam mit mir heraus, Staub auf dem Mantel. Er hielt die Hände nach vorn, ohne dass es jemand verlangte.
Die Akte Nordlicht lag da schon beim Generalbundesanwalt.", 5.5],
	["Im Herbst begann der Prozess. Weber sagte elf Tage lang aus.
Zum ersten Mal fielen die Namen der Geldgeber, Konto für Konto.", 5.5],
	["Einige von ihnen hatten Riedhammer bezahlt, weil sie an ihn glaubten. Die meisten aus anderen Gründen.
Weber hat nie gesagt, auf welcher Seite er selbst stand. Für das Land oder für sich.", 6.0],
	["Präsidentin Hartmann rief den Bundestag zusammen, im Saal mit den zerschossenen Fenstern.
Lena sagt, es ist vorbei. Diesmal glaube ich ihr.", 5.0],
	["Am Abend stand ich am Spreeufer. Die Stadt war still.
Zum ersten Mal seit Wochen hörte ich nur das Wasser.", 6.0],
]

## Variante "release": Kerner laesst Weber gehen – Riedhammer stirbt trotzdem im Bunker.
const ENDING_4_RELEASE := [
	["Um 05:12 brach die Decke des Kontrollraums ein. Riedhammer hatte sich mit seinem Bunker gesprengt,
auf seinem Posten, wie er es nannte. Oberst Falk war tot. Bis zum Mittag hatte die Garde die Waffen niedergelegt.", 6.0],
	["Weber war da schon durch den Notausgang unter der Spree verschwunden. Niemand hielt ihn auf.
In meiner Brusttasche steckte eine einzelne Seite aus der Akte Nordlicht. Er hatte sie mir dagelassen.", 5.5],
	["Riedhammer kam nie vor ein Gericht. Die Männer, die ihn bezahlt hatten, auch nicht.
Noch nicht.", 5.0],
	["Präsidentin Hartmann rief den Bundestag zusammen, im Saal mit den zerschossenen Fenstern.
Lena redet nicht mehr über Weber. Ich schon, manchmal, mit mir selbst.", 5.5],
	["Auf der Seite steht eine Telefonnummer, mit Bleistift. Ich habe sie nie angerufen.
Am Abend stand ich am Spreeufer und hörte zum ersten Mal seit Wochen nur das Wasser.", 6.0],
]

## Akt-Enden fuer main.gd: nach diesem Level Texttafeln, dann Zwischentitel (wenn ein Level folgt) oder "Fortsetzung folgt".
const ACT_ENDINGS := {
	"berlin": {"cards": ENDING, "next_title": "Teil 2 – Ordnungsfront", "next_sub": "Zwei Tage nach dem Putsch",
		"end_sub": "Kampagne „Nord“ – Ende von Teil 1"},
	"gunship": {"cards": ENDING_2, "next_title": "Teil 3 – Jagd auf Weber", "next_sub": "Drei Tage später",
		"end_sub": "Ende von Teil 2"},
	"villa": {"cards": ENDING_3, "next_title": "Teil 4 – Die Garde", "next_sub": "Berlin, sechs Tage später",
		"end_sub": "Ende von Teil 3"},
	"bunker": {"cards": ENDING_4, "end_sub": "Letztes Reich", "end_title": "Ende", "credits": true,
		"variant_key": "game/weber_choice", "variants": {"arrest": ENDING_4_ARREST, "release": ENDING_4_RELEASE}},
}
