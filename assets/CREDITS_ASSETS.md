# Asset-Quellen (Realismus-Pass: Waffen, Wracks, Baeume)

Nur CC0-Assets (CC0 1.0 Public Domain). Downloads wurden in einem separaten Verzeichnis entpackt;
es wurden keine Skripte aus Downloads ausgefuehrt. Ergaenzt `assets/CREDITS.md`.

| Datei(en) | Quelle | Autor | Lizenz | Groesse |
|---|---|---|---|---|
| `assets/weapons/service_pistol/service_pistol.glb` + `service_pistol_service_pistol_{diff,nor_gl,arm}_2k.jpg` | https://polyhaven.com/a/service_pistol | Mateusz Sadek | CC0 | ca. 17 MB (Variante "a", Holzgriff; in Blender auf Teile base_gun/slider/magazine/hammer/trigger reduziert) |
| `assets/environment/trees/spruce_atlas_albedo.png`, `spruce_atlas_normal.png` (Rindenhaelfte) | https://polyhaven.com/a/pine_bark (Rinde) | Poly Haven | CC0 | zusammen ca. 7,4 MB |

## Selbst erzeugt (CC0)

| Datei | Erzeugung |
|---|---|
| `assets/environment/trees/spruce_atlas_*.png` (Zweighaelfte) | prozedural, `tools/gen_spruce_atlas.py` |
| `assets/environment/trees/spruce_impostor.png` | aus dem eigenen Fichten-Mesh (`NightProps.spruce_mesh`) in Blender gerendert |
| `assets/environment/trees/spruce.gdshader` | eigener Shader (Alpha-Laubkarten, Wind, Schnee) |
| `game/vehicles/models/tank_wreck_model.gd` | prozedurales Panzerwrack (vorhandenes TankModel + Material `rusty_metal_02`) |
| `game/vehicles/models/car_model.gd` | prozedurale Pkw/Transporter/Bus/Lkw (Profil-Extrusion), nutzt vorhandene Materialien |
| `assets/vfx/muzzle_flash_front.png`, `assets/vfx/muzzle_flash_side.png` | Muendungsfeuer-Atlanten (Front-Stern 2x2, Seitenflamme 4x1), prozedural mit numpy/scipy, `assets/vfx/gen_muzzle_flash.py` |
| `game/vfx/shaders/muzzle_flash.gdshader`, `game/vfx/shaders/muzzle_spark.gdshader` | eigene Shader (additives Muendungsfeuer mit Erosion, Funken-Striche) |

## Requisiten-Pass (Poly Haven, CC0)

Neu heruntergeladen (1k-Texturen), zusammen ca. 8,3 MB:

| Datei(en) | Quelle | Autor | Lizenz | Groesse |
|---|---|---|---|---|
| `assets/environment/props/textures/hessian_230/{diffuse,normal,arm}.jpg` (Sandsack-Jute) | https://polyhaven.com/a/hessian_230 | colormass, Rico Cilliers | CC0 | ca. 3,2 MB |
| `assets/environment/props/models/tree_stump_01/` (glTF + 1k-Texturen) | https://polyhaven.com/a/tree_stump_01 | Rob Tuytel | CC0 | ca. 3,9 MB |
| `assets/environment/props/models/Lantern_01/` (glTF + 1k-Texturen, Sturmlaterne) | https://polyhaven.com/a/Lantern_01 | Rajil Jose Macatangay | CC0 | ca. 1,4 MB |

Wiederverwendet (bereits im Projekt, siehe `assets/CREDITS.md`), jetzt zusaetzlich ueber `game/levels/ph_props.gd`:
`rail/models/wooden_military_crate`, `rail/models/ammo_box`, `river/models/rock_moss_set_01`,
`river/models/dead_tree_trunk`, `street/models/street_lamp_01`, `street/models/concrete_road_barrier`.

Selbst erzeugt (CC0): Sandsack-Mesh (prozedural, `PH.sandbag_mesh()`), `assets/environment/snowy_uv.gdshader`
(UV-Material mit Schneeauflage fuer Poly-Haven-Modelle).

## Realistische VIP-Figur: General von Riedhammer (MakeHuman / MPFB2, CC0)

`assets/characters/vip/riedhammer.glb` (geriggt, MPFB-"game_engine"-Skelett, ca. 41k Dreiecke inkl. Muetze,
Texturen max. 2k; Godot extrahiert die eingebetteten Texturen beim Import als `riedhammer_*.jpg/png`).
Zusammen ca. 5,1 MB. Gebaut mit `tools/vip/prep_tex.py` + `tools/vip/build_ried.py`
(Blender 4.2 + MPFB 2.0.18; das MPFB-Addon selbst ist GPLv3-Code und wird **nicht** mitgeliefert).

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Basismesh, Ziel-Morphs (Alter/Gewicht/Gesicht), Skelett "game_engine" | MakeHuman System Assets, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | MakeHuman-Team | CC0 |
| Haut `middleage_caucasian_male`, Augen `low-poly` (lightblue), Brauen `eyebrow001`, Wimpern `eyelashes01`, Haar `short02` | ebenda | MakeHuman-Team | CC0 |
| Anzug `male_elegantsuit01` (Textur auf Feldgrau umgefaerbt, Krawatte eingefaerbt, Hose in die Stiefel eingezogen) | ebenda | MakeHuman-Team | CC0 |
| Stiefel `culturalibre_hero_boots_2` (Textur schwarz umgefaerbt) | Asset-Pack shoes01, https://files.makehumancommunity.org/asset_packs/shoes01/shoes01_cc0.zip | culturalibre | CC0 |

Lizenznachweis: https://static.makehumancommunity.org/about/license.html ("All core assets are shared under
Creative Commons, CC0"); die `.mhclo`/`.mhmat`-Koepfe und `packs/*.json` der Pakete nennen jeweils "CC0".
Hinweis: im Paket shoes01 ist `culturalibre_heroine_boots_4` CC-BY - **nicht** verwenden.

Selbst erzeugt (CC0, prozedural in `build_ried.py`): Schirmmuetze (Band, Krone, Schirm, Paspeln, Kinnkordel,
**erfundenes** Emblem aus gebrochenem Ring + Klinge, rote Kokarde), Kragenspiegel, Schulterstuecke,
Ordensspange (Fantasiefarben), Koppel mit Rahmenschnalle. Keine realen historischen Hoheitszeichen.

## VIP-Figuren v4: Riedhammer (ueberarbeitet), Weber (zivil + Uniform), Falk, Graumantel (MakeHuman / MPFB2, CC0)

Neue Pipeline: `tools/vip/prep_vip.py <tex_dir> <kind>` + `blender -b --python tools/vip/build_vip.py -- <tex_dir> <out.glb> --kind=<kind>`
(kind: riedhammer | weber | weber_uniform | falk | graumantel). Ergebnis in `assets/characters/vip/<kind>.glb`
(+ von Godot extrahierte `<kind>_*.jpg/png`), je < 40k Dreiecke; Ordner gesamt ca. 28 MB (GLBs ca. 17 MB).
`build_ried.py`/`prep_tex.py` sind die alte Einzelversion und bleiben nur als Referenz.

Zusaetzlich zu den oben genannten Riedhammer-Bestandteilen verwendet:

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Haut `old_caucasian_male` (mit `middleage_caucasian_male` verblendet), Ziel-Morph `head/head-age-incr`, Haar `short01`, Kleidung `male_casualsuit05` (Falk/Graumantel, umgefaerbt) | MakeHuman System Assets (Link s. o.) | MakeHuman-Team | CC0 |
| Anzug `toigo_male_suit_tie_and_jacket` (Weber zivil, anthrazit umgefaerbt) | Asset-Pack suits01, https://files.makehumancommunity.org/asset_packs/suits01/suits01_cc0.zip | MargaretToigo | CC0 |
| Stiefel `toigo_ankle_boots_male` (Weber zivil) | Asset-Pack shoes01 (Link s. o.) | MargaretToigo | CC0 |
| Tarnmuster Falk: `assets/characters/textures/camo_reich_urban.png` | eigenes Projekt-Asset | - | CC0 |

Selbst erzeugt (CC0, prozedural in `build_vip.py`): geschlossener Stehkragen mit Kragenspiegeln und Knopfleiste,
Brille (Weber), Barett (Falk), Feldmuetze (Graumantel), Schirmmuetzen-Varianten mit Silber-/Goldpaspel,
Armbinde, Koppel, Schulterstuecke. Kein Bart (kein CC0-Bart-Asset verfuegbar). Keine realen Hoheitszeichen.

## Operator-Gegner (Sketchfab Standard License) - `assets/characters/soldier_op/`

Modell "S.W.A.T. Operator - Remastered" von Mateusz Wolinski (jeandiz),
https://sketchfab.com/3d-models/swat-operator-remastered-732d2eec5a0c456bafedd08af35134c3 - Sketchfab Standard License
(Nutzung in Projekten erlaubt, keine Weitergabe als eigenstaendiges Asset). Bake: `game/enemies/tools/bake_soldier_op.gd`
-> `soldier_op.scn` (KSVR-Meshes entfernt, Texturen 2048 px, LODs, Skelett mit SWAT-kompatiblen Knochennamen,
Animationen aus Quaternius UAL/SWAT retargetet). Laufzeit: `soldier_visual.gd` (Art "op"), `soldier_op.gdshader`,
`soldier_op_hood.gdshader`. Verwendet fuer gepanzerte Typen (armored/juggernaut) und als Fallback ohne `graphics/real_soldiers`.
Fraktionsfarben/Armbinden/Abzeichen sind erfunden; keine realen Hoheitszeichen.

## Realistische Gegner-Soldaten (MakeHuman / MPFB2, CC0) - `assets/characters/soldier_mh/`

Pipeline: `python tools/soldier/prep_soldier.py <tex_dir> <helmet_dir>` + `blender -b --python tools/soldier/build_soldier.py -- ...`
(3 Koerpervarianten a/b/c -> `soldier_mh/src/soldier_*.glb`, .gdignore), dann Godot-Bake
`game/enemies/tools/bake_soldier_mh.gd` -> `soldier_mh_{a,b,c}.scn` (Skelett mit SWAT-kompatiblen Knochennamen,
Animationen, LOD-Kette). Laufzeit: `game/enemies/soldier_visual.gd`, `soldier_mh_gear.gd`, `soldier_mh_cloth.gdshader`.
Einstellung `graphics/real_soldiers` (aus = alte SWAT-Optik; fehlt die .scn, wird automatisch SWAT verwendet).
MPFB selbst (GPLv3) wird **nicht** mitgeliefert, nur damit erzeugte CC0-Daten.

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Basismesh, Ziel-Morphs (Statur/Gesicht/Alter), Skelett "game_engine" | MakeHuman System Assets (Link s. o.) | MakeHuman-Team | CC0 |
| Haeute `young_caucasian_male`, `young_caucasian_male2`, `middleage_caucasian_male` (verblendet, gealtert), Augen `low-poly` (brown), Brauen `eyebrow001`, Wimpern `eyelashes01` (nur Textur), Haar `short02` | ebenda | MakeHuman-Team | CC0 |
| Uniform `male_casualsuit01` (nur als Graustufen-Detailkarte genutzt, Farbe/Tarnung zur Laufzeit) | ebenda | MakeHuman-Team | CC0 |
| Stiefel `culturalibre_hero_boots_2` | Asset-Pack shoes01 (Link s. o.) | culturalibre | CC0 |
| Helm `mrgreaterthan_m1_helmet` (Graustufen-Detail + Normalmap neu erzeugt) | Asset-Pack hats02, https://files.makehumancommunity.org/asset_packs/hats02/hats02_cc0.zip | MrGreaterThan | CC0 |
| Animationen (Idle/Walk/Jog/Crouch u. a.) | Quaternius Universal Animation Library (s. assets/CREDITS.md, `anim_src/ual_standard.glb`) | Quaternius | CC0 |
| Animationen (Zielen/Schiessen/Deckung/Tod) | Quaternius SWAT-Clips (bereits im Projekt, s. assets/CREDITS.md) | Quaternius | CC0 |
| Tarnmuster `camo_ru_digital.png`, `camo_reich_urban.png` | eigene Projekt-Assets | - | CC0 |

Hinweis: `culturalibre_heroine_boots_4` (CC-BY) wird **nicht** verwendet.
Selbst erzeugt (CC0, prozedural in `soldier_mh_gear.gd` / `soldier_gear.gd`): Plattentraeger, Magazin-/Granatentaschen,
Koppel, Funkgeraet, Brille, Halstuch, Strickmuetze, Ghillie-Netz, Feldmuetze, Armbinden, Abzeichen.
Alle Abzeichen/Embleme sind **erfunden**; keine realen Hoheitszeichen.

### Nachtrag: Ausruestungs-Realismus-Pass (Gegner-Soldaten)

Geprueft, aber **nicht** verwendbar: Poly Haven (keine Westen/Helme), MakeHuman-Community-Packs mit Westen/Helmen/Muetzen
(z. B. equipment03, hats04: CC-BY, nicht CC0), Quaternius/Kenney (nur Low-Poly-Stil), ambientCG (nur Materialien).
Daher keine neuen externen Assets. Alles Folgende ist selbst erzeugt (CC0):
- Ausruestung komplett prozedural neu in `game/enemies/soldier_mh_gear.gd` (gepolsterte Platten mit Rundkanten,
  Taschen mit Klappen, Kummerbund, High-Cut-/Vollschalenhelm mit Kantenschutz, Schirmmuetze, Ghillie-Haube aus Jute-Bueschen)
  plus Shader `game/enemies/soldier_mh_gear.gdshader` (MOLLE-Gurtreihen, Gewebe, Naehte/Einfassung, Lack, Strick, Jute).
- Der M1-Helm (`mrgreaterthan_m1_helmet`, s. o.) wird zur Laufzeit nicht mehr angezeigt (Datei bleibt fuer den Bake).
- Haut-Shader `game/enemies/soldier_mh_skin.gdshader` (waermerer Hautton, Haaransatz, Halstuch auf der Haut).
- Armbinden werden im Uniform-Shader (`soldier_mh_cloth.gdshader`) auf den Aermel projiziert.
- Wiederverwendet: Gewebe-Struktur `assets/characters/textures/rough_linen/diffuse.jpg` (Poly Haven "Rough Linen", CC0, s. assets/CREDITS.md).

### Nachtrag: Waffenmodelle (Runde waffen_neu)

Externe Modelle, CC BY 4.0 (http://creativecommons.org/licenses/by/4.0/), Namensnennung erforderlich:
- `assets/weapons/ak74m/`: AK-74M, Waffenmodell von creationwasteland (Sketchfab), aus dem Paket
  "FPS AK-74m animations" von Cransh (ccransh), https://sketchfab.com/3d-models/fps-ak-74m-animations-94be8385c402474cacd39bc096c6ca14
  (nur Waffe, Arme entfernt, Skin statisch gebacken, skaliert auf 0,943 m, Texturen 2048 px).
- `assets/weapons/g36/`: "HK G36" von r4m, https://sketchfab.com/3d-models/hk-g36-2cf3be6a834c425bbc2a416e85b52042
  (skaliert auf 0,999 m, Teile getrennt, Texturen 2048 px).
- Rotpunktvisier auf dem G36: eigene Arbeit, prozedural (CC0).
- `assets/models/weapons/mbus/`: Klapp-Notvisier (Kimme/Korn) auf dem G36: "Magpul MBUS Sights GEN3" von xylvnking,
  https://sketchfab.com/3d-models/magpul-mbus-sights-gen3-a27302dcf26644d3a4be3d30fbde318e
  (Sketchfab Standard-Lizenz, keine Namensnennung erforderlich; in Kimme/Korn zusammengefasst, echter Massstab,
  Texturen auf 2048 px, Rauheit fuer mattes Polymer angehoben).
- Das alte AK-47-Modell (Lamoot, CC0) wird nicht mehr verwendet.

### Nachtrag: Maschinengewehre und Juggernaut-Ausruestung

CC BY 4.0 (http://creativecommons.org/licenses/by/4.0/), Namensnennung erforderlich:
- `assets/models/weapons/m2/`: "M2 Browning" von Charlie Tinley (@Tnkii),
  https://sketchfab.com/3d-models/m2-browning-7b83ca60e6c9451f9f23d2d0bc0e4710
  (in Koerper/Lauf/Dreibein getrennt, skaliert auf ca. 1,65 m, Texturen max. 2048 px). Schwere Stellungen/MG-Nester.
- `assets/models/weapons/mg5/`: "low-poly HK MG5" von D_U (@DU1701),
  https://sketchfab.com/3d-models/low-poly-hk-mg5-ca249a577a5744b8bc7e16ff063a6e5e
  (skaliert auf ca. 1,2 m, Texturen max. 2048 px; `mg5_world.glb` = schwarz umgefaerbte Ein-Mesh-Fassung fuer Gegner,
  Munitionskasten samt Gurt 3,5 cm naeher an die Waffe gesetzt). MG-Schuetzen, Juggernaut, Bord-MG.

Sketchfab Standard-Lizenz (Free Standard, keine Namensnennung erforderlich; trotzdem genannt):
- `assets/models/gear/altyn/`: "Altyn helmet" von Kenza9 (@atynnikov31),
  https://sketchfab.com/3d-models/altyn-helmet-57e1db31f2e34530ae072baa1fd1b9f6 (Juggernaut-Helm, Visier mit eigenem Shader).
- `assets/models/gear/gasmask/`: "Gas mask and helmet" von TwilightFox (@twilightfox),
  https://sketchfab.com/3d-models/gas-mask-and-helmet-e4edaaa99eca46c7868a77ef390bed6f (nur Maske + Filter genutzt).
- `assets/models/gear/plate_carrier/`: "Free - Armor Plate Carrier - Gameready Metahuman" von Karnaval (@amadions),
  https://sketchfab.com/3d-models/free-armor-plate-carrier-gameready-metahuman-39d3b162b14444d487eb39186268e7a7
  (Juggernaut-Plattentraeger, auf den Anzug skaliert).

### Nachtrag: Erste-Person-Arme

Externes Modell, CC BY 4.0 (http://creativecommons.org/licenses/by/4.0/), Namensnennung erforderlich:
- `assets/characters/fp_arms/`: Arme (Aermel + Handschuhe) mit Rig aus dem Paket "FPS AK-74m animations"
  von Cransh (ccransh), https://sketchfab.com/3d-models/fps-ak-74m-animations-94be8385c402474cacd39bc096c6ca14
  (nur Arme, Pose aus "AK_Idle" eingefroren, in den Kameraraum gebacken, Texturen 2048 px; Lizenztext in LICENSE.txt).
  Zur Laufzeit per IK an die Waffe gestellt (game/weapons/fp_arms.gd).

### Nachtrag: Hochgebirge "Weisses Rauschen" (Alpenpass-Overhaul)
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich:
- `assets/environment/textures/snow_field_aerial/`: "Snow Field Aerial" (https://polyhaven.com/a/snow_field_aerial) – grossflaechige Verwehungen im Gelaende-Shader
- `assets/environment/textures/rock_face_03/`: "Rock Face 03" (https://polyhaven.com/a/rock_face_03) – Fels an steilen Haengen
- `assets/environment/props/models/boulder_01/`: "Boulder 01" (https://polyhaven.com/a/boulder_01) – Felsbrocken als Deckung im Kessel

### Nachtrag: Mission "Kraene" (Hafen) – Schiffe, Boote, Kraene, Container

Externe Modelle von Sketchfab, eingebunden ueber die Modell-Slots in `assets/models/hafen/` (game/levels/hafen_models.gd);
Lizenztext je Ordner in license.txt. Kollision bleibt im Code (Boxen).
CC BY 4.0 (http://creativecommons.org/licenses/by/4.0/), Namensnennung erforderlich:
- `assets/models/hafen/zollboot/`: "Patrol Speed Boat" von bartolt, https://sketchfab.com/3d-models/patrol-speed-boat-0177025d02f44def9b252a36d5fd70f8
  (Spielerboot; skaliert, verbreitert, Materialien neu eingefaerbt: Marineblau/Grau).
- `assets/models/hafen/weber_boat/`: "Yatch I (second edition)" von dannzjs, https://sketchfab.com/3d-models/yatch-i-second-edition-b826e1c52d604c599b893967bed8a254
  (Webers Fluchtboot, auf 9 m skaliert).
- `assets/models/hafen/freighter_aurelia/`: "Cargo ship" von hungry_drifter, https://sketchfab.com/3d-models/cargo-ship-b7c97df584824ca682d26daabf401f87
  (Frachter "Aurelia"; Name als Label, Fallreep und Matrosen prozedural ergaenzt).
- `assets/models/hafen/port_crane/`: "Port crane \"Sokol\"" von Vitaliy Kovalchuk (Domender), https://sketchfab.com/3d-models/port-crane-sokol-4964eaa7634e47c9bac4c2a74fa91c20
  (Wippdrehkrane am Westkai, Originalanimation hin und zurueck, Hindernisfeuer ergaenzt).
- `assets/models/hafen/container/`: "Classic Shipping Container (Free/Gameready)" von Sebastian Webster, https://sketchfab.com/3d-models/classic-shipping-container-freegameready-772f4be391a245f699c54e6cf157c58d
  (20-ft-Container als MultiMesh mit Farbvarianten je Instanz).
Sketchfab Standard-Lizenz (https://sketchfab.com/licenses), keine Namensnennung erforderlich:
- `assets/models/hafen/garde_boat/`: "JM 16 (ZOLFAQAR) SPEEDBOAT" von Haikyousha, https://sketchfab.com/3d-models/jm-16-zolfaqar-speedboat-37450859926a4c6280d8c45396f3896a
  (Garde-Schnellboot; Rumpfschriftzug unkenntlich gemacht, Bug-DShK dient als Spiel-MG).

### Nachtrag: Hubschrauber Mi-8 / Mi-28N

CC-BY 4.0 (https://creativecommons.org/licenses/by/4.0/), Hubschrauber (skaliert, gedreht, Rotoren getrennt, Texturen auf 2048 px):
- `assets/models/vehicles/mi8/`: "Russian Transport Heli" von Mateusz Wolinski (https://sketchfab.com/jeandiz), https://sketchfab.com/3d-models/russian-transport-heli-ab981d28f7124a489cd1b1992b2e467b
  (Mi-8-Transporter, Brandts Hubschrauber; gebacken nach mi8.scn durch tools/bake_heli_models.gd).
- `assets/models/vehicles/mi28n/`: "Mi-28N Havoc" von Rukh3D (https://sketchfab.com/rukh3d), https://sketchfab.com/3d-models/mi-28n-havoc-3e80c95bbadf46abbafba9d9a08afc68
  (gegnerischer Kampfhubschrauber/Garde; gebacken nach mi28n.scn durch tools/bake_heli_models.gd).
