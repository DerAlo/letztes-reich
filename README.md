# Letztes Reich

![Kriegsstraße – G36C im Feuergefecht, Raketeneinschlag in der Fassade](docs/screenshots/00_hero_war_street_rocket.jpg)

Singleplayer-Korridorshooter in Godot 4.7. Fiktive Geschichte, Europa 2030 – 17 Missionen in vier Teilen, mit Intro, Briefings und Abspann.

| | |
|---|---|
| ![Speisewagen](docs/screenshots/v05_nachtzug_speisewagen.jpg) | ![Reisender](docs/screenshots/v05_nachtzug_reisender.jpg) |
| **Nachtzug** – Speisewagen mit Reisenden, die sich beim ersten Schuss ducken | **Abteil** – neue, animierte Zivilfiguren statt starrer Puppen |
| ![Hubbrücke](docs/screenshots/v05_hafen_hubbruecke.jpg) | ![Regierungsviertel](docs/screenshots/v05_ep_lena_regierungsviertel.jpg) |
| **Hubbrücke** – Schützen oben auf der Brücke, das Zollboot wartet davor | **Lenas Nacht** – Dächer des Regierungsviertels im Regen, Kerner im Zielfernrohr |
| ![Fernmeldestelle](docs/screenshots/v05_curfew_fernmeldestelle.jpg) | ![Nachtsicht](docs/screenshots/v05_kanalisation_nachtsicht.jpg) |
| **Ausgangssperre** – Webers Funkprotokolle aus der Fernmeldestelle ziehen | **Unter der Spree** – Versorgungskeller des Kanzleramts im Nachtsichtgerät |
| ![Hauptmenü](docs/screenshots/v04_hauptmenue.jpg) | ![Absetzen mit der Mi-8](docs/screenshots/v04_alpenpass_mi8_absetzen.jpg) |
| **Hauptmenü** – Fortsetzen, Missionsauswahl, Episoden und Einstellungen direkt beim Spielstart | **Weißes Rauschen** – Absetzen am Grenzpass, die Mi-8 hebt im Schneesturm der Rotoren ab |
| ![Kessel](docs/screenshots/v04_alpenpass_kessel.jpg) | ![Lawine](docs/screenshots/v04_alpenpass_lawine.jpg) |
| **Der Kessel** – bei klarer Sicht durch das Hochtal zur Zollhütte | **Lawine** – Mörserfeuer auf die Wechte, die Pulverwolke rollt die Rinne hinab |
| ![Bootsjagd](docs/screenshots/v04_hafen_bootsjagd_mg5.jpg) | ![Aurelia](docs/screenshots/v04_hafen_aurelia.jpg) |
| **Kräne** – nächtliche Bootsjagd im Rostocker Hafen, MG5 gegen die Garde-Boote | **Die Aurelia** – Weber entkommt über die Gangway des Frachters |
| ![Juggernaut](docs/screenshots/v04_juggernaut.jpg) | |
| **Juggernaut** – Altyn-Helm, Plattenträger und MG5 | |
| ![Holovisier](docs/screenshots/01_holo_sight_officer.jpg) | ![Panzerfaust an der Brücke](docs/screenshots/02_river_bridge_panzerfaust.jpg) |
| **Häuserkampf** – Offizier und Sturmsoldat im Holovisier der G36C | **Die Brücke** – Panzerfaust 3 gegen den Kampfhubschrauber, im Regen |
| ![Scharfschützen-Laser](docs/screenshots/03_baltic_night_marksman_laser.jpg) | ![Letzter Zug](docs/screenshots/04_rail_yard_evening.jpg) |
| **Nacht an der Grenze** – der rote Laser des Scharfschützen im verschneiten Baltikum | **Letzter Zug** – Güterbahnhof Pskow im Abendlicht |
| ![Waffen aufnehmen](docs/screenshots/05_weapon_pickup_panzerfaust.jpg) | ![Anschlag](docs/screenshots/07_berlin_stage_attack.jpg) |
| **Nachschub** – Panzerfaust-Kiste und fallengelassene Waffen: [E] aufnehmen | **Der Anschlag** – in Berlin fliegt die Bühne mitten in der Friedensrede in die Luft |
| ![Stahlwerk](docs/screenshots/v03_overwatch_stahlwerk_panorama.jpg) | ![Zielfernrohr](docs/screenshots/v03_overwatch_zielfernrohr_windsack.jpg) |
| **Kaltes Auge** – Scharfschützen-Mission im Stahlwerk Hennigsdorf | **Wind lesen** – Windsack, Geschossfall und Kugel-Kamera |
| ![Wärmebild](docs/screenshots/v03_gunship_waermebild_25mm.jpg) | ![Fliegerhorst](docs/screenshots/v03_gunship_uebersicht_flugplatz.jpg) |
| **Wächter** – Feuerunterstützung aus dem Gunship, Wärmebild der 25 mm | **Fliegerhorst Lindenau** – drei Geschütze, Täuschkörper gegen Raketen |

## ▶ Spielen

1. **[Neueste Version herunterladen](https://github.com/DerAlo/letztes-reich/releases/latest)** – `LetztesReich-v0.5-win64.zip`
2. Entpacken, `LetztesReich.exe` doppelklicken. Keine Installation nötig.
3. Falls Windows warnt („Der Computer wurde durch Windows geschützt“): **Weitere Informationen → Trotzdem ausführen** (die Datei ist nicht signiert).

**Voraussetzungen:** Windows 10/11 64-Bit, Vulkan-fähige Grafikkarte (etwa GTX 1060 / RX 580 oder besser).

## Steuerung

| Taste | Aktion |
|---|---|
| W A S D / Maus | Bewegen / Umsehen |
| Linksklick / Rechtsklick | Schießen / Zielen |
| Shift | Sprinten |
| Leertaste | Springen, an Kanten hochklettern |
| C / Strg (halten) / Z | Ducken umschalten / geduckt bleiben / Hinlegen umschalten |
| Shift + C | Rutschen (endet geduckt; Springen oder Sprinten richtet auf) |
| R / G | Nachladen / Granate |
| E | Waffe aufnehmen (tauscht die Primärwaffe), Munitionskiste benutzen |
| 1 / 2 / 3, Mausrad, Q | Primärwaffe / Pistole / Panzerfaust, Waffe wechseln, letzte Waffe |
| F | Lautlos ausschalten, Tür eintreten (je nach Mission) |
| Esc | Pause: Missionen, Episoden, Einstellungen (Intro: Leertaste/Esc überspringt) |

**Gunship:** 1 / 2 / 3 oder Q / Tab Geschütz wählen · F / Leertaste Täuschkörper · T Wärmebild umschalten

## Entwicklung

Projekt in Godot 4.7.2 öffnen (`project.godot`). Export: Preset „Windows“ (eine .exe mit eingebettetem PCK).

Alle Figuren, Organisationen und Symbole sind frei erfunden. Freie Assets und Lizenzen: [assets/CREDITS.md](assets/CREDITS.md).
