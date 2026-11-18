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
| `assets/vfx/blood_splat_0..3.png`, `blood_drip_0..1.png`, `blood_pool.png` (+ `*_n.png` Normalmaps), `blood_drop.png`, `blood_orm.png` | Blut-Decals (gerichtete Spritzer, Tropfflecken, Lache) und Partikel-Tropfen, prozedural mit numpy/scipy, `assets/vfx/gen_blood.py` (keine Fremd-Assets) |
| `game/vfx/shaders/blood_drop.gdshader` | eigener Shader (entlang der Flugrichtung gestreckte, glaenzende Bluttropfen mit Gegenlicht-Durchscheinen) |

## Requisiten-Pass (Poly Haven, CC0)

Neu heruntergeladen (1k-Texturen), zusammen ca. 8,3 MB:

| Datei(en) | Quelle | Autor | Lizenz | Groesse |
|---|---|---|---|---|
| `assets/environment/props/textures/hessian_230/{diffuse,normal,arm}.jpg` (Sandsack-Jute) | https://polyhaven.com/a/hessian_230 | colormass, Rico Cilliers | CC0 | ca. 3,2 MB |
| `assets/environment/props/models/tree_stump_01/` (glTF + 1k-Texturen) | https://polyhaven.com/a/tree_stump_01 | Rob Tuytel | CC0 | ca. 3,9 MB |
| `assets/environment/props/models/Lantern_01/` (glTF + 1k-Texturen, Sturmlaterne) | https://polyhaven.com/a/Lantern_01 | Rajil Jose Macatangay | CC0 | ca. 1,4 MB |
| `assets/environment/funkturm/textures/metal_grate_rusty/{diffuse,normal,arm}.jpg` (1k, Gitterroste/Wendeltreppe Funkturm) | https://polyhaven.com/a/metal_grate_rusty | Poly Haven | CC0 | ca. 2,8 MB |
| `assets/environment/funkturm/textures/concrete_panels/{diffuse,normal,arm}.jpg` (1k, Betonfertigteile Messehallen/Plattenbauten Funkturm) | https://polyhaven.com/a/concrete_panels | Poly Haven | CC0 | ca. 1,9 MB |

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

### Nachtrag: Villa am Traunsee (Garten, Fernkulisse, Fassade, Innenraum) - `assets/environment/villa/`

Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich (je Ordner diffuse/normal/arm, auf 1-2K):
- `leafy_grass/`: https://polyhaven.com/a/leafy_grass (Rasen-Grundtextur, im Shader mit Maehstreifen gemischt)
- `gravel_floor_02/`: https://polyhaven.com/a/gravel_floor_02 (Kieswege, Vorplatz, Beet-Erde eingefaerbt)
- `beige_wall_001/`: https://polyhaven.com/a/beige_wall_001 (Aussenputz der Villa)
- `plastered_wall_04/`: https://polyhaven.com/a/plastered_wall_04 (Innenputz)
- `herringbone_parquet/`: https://polyhaven.com/a/herringbone_parquet (Fischgraet-Parkett)
- `grey_roof_tiles/`: https://polyhaven.com/a/grey_roof_tiles (Walmdach)
- `leaves/`: Laubkarten (leaf_cluster.png u. a.), zusammengesetzt aus den Blatt-Texturen von https://polyhaven.com/a/tree_small_02 (CC0)
Wiederverwendet (bereits oben/in assets/CREDITS.md gelistet, Poly Haven CC0): `assets/environment/rock_face_03` (Uferfelsen, Fels der Bergkulisse), `assets/environment/pine_bark` (Rinde der Laubbaeume).
Selbst erzeugt (CC0, prozedural mit numpy/PIL): `decals/` (Handabdruecke, Schmutz, Scheuerspuren, Wasserflecken, Bilderrahmen-Abdruck), `art/` (Gemaelde, Seekarte, topografische Karte).
Eigene Shader (CC0): `lawn.gdshader`, `grass_blades.gdshader`, `foliage.gdshader`, `mountains.gdshader`; Code in `game/levels/villa_dressing.gd`, `game/levels/villa_far_cam.gd`.

### Nachtrag: Schuetzenpanzer "Rabe" (Marder 1A3)
- `assets/vehicles/marder/`: "Marder 1A3 | High-Quality model" von Scout, https://sketchfab.com/3d-models/marder-1a3-high-quality-model-0897f55d01a24fca9577d3d8a8579aac - CC-BY 4.0. Verwendet als IFV "Rabe" (gebacken mit `tools/bake_rabe_marder.gd` zu `rabe_marder.scn`, eigene Materialien/Tarnung).

### Nachtrag: Nachtzug-Reisende und Streckenbaeume (Realismus-Pass) - `assets/characters/civilian/`

Zivilfiguren `civ_<kind>.glb` (kind: mantel | jacke | alt | frau | frau2; je drei vorgebackene Posen "seat"/"cower"/"lie"
ueber das MPFB-"game_engine"-Skelett, je Pose ca. 22-24k Dreiecke, Texturen max. 1k; Godot extrahiert `civ_<kind>_*.jpg/png`;
Ordner gesamt ca. 21 MB). Gebaut mit `tools/civilian/prep_civ.py <tex_dir> <kind>` +
`blender -b --python tools/civilian/build_civ.py -- <tex_dir> <out.glb> --kind=<kind>` (Blender 4.2 + MPFB 2.0.18;
MPFB ist GPLv3-Code und wird **nicht** mitgeliefert). Verwendet in `game/levels/nachtzug_civilian.gd`.

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Basismesh, Morphs, Skelett; Haeute `middleage_caucasian_male`, `young_caucasian_male`, `old_caucasian_male`, `middleage_caucasian_female`, `young_african_female`; Augen `low-poly`, Brauen `eyebrow001`, Wimpern `eyelashes01`; Haare `short01`, `short02`, `short03`, `bob01`, `ponytail01`; Kleidung `male_casualsuit05`, `female_elegantsuit01`, Schuhe `shoes01` (alle umgefaerbt) | MakeHuman System Assets, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | MakeHuman-Team | CC0 |
| Anzuege `toigo_male_double-breasted_suit`, `toigo_male_suit_3`, `toigo_female_suit` (umgefaerbt: Mantelbraun, Graubraun, Bordeaux) | Asset-Pack suits01, https://files.makehumancommunity.org/asset_packs/suits01/suits01_cc0.zip | MargaretToigo | CC0 |
| Stiefeletten `toigo_ankle_boots_male`, `toigo_ankle_boots_female` | Asset-Pack shoes01, https://files.makehumancommunity.org/asset_packs/shoes01/shoes01_cc0.zip | MargaretToigo | CC0 |

Lizenznachweis wie oben (https://static.makehumancommunity.org/about/license.html). Selbst erzeugt (CC0): Posen,
Bettdecke (Hoehenfeld aus der Koerperform, `nachtzug_civilian.gd`).

Streckenbaeume (`game/levels/track_trees.gd`, eigener Code, CC0): Fichten aus den vorhandenen Zweigkarten
(`assets/environment/trees/`, s. o.), kahle Laubbaeume/Straeucher mit Rinde aus dem Fichten-Atlas (Poly Haven `pine_bark`,
CC0) und trockenem Eichenlaub aus `assets/environment/villa/leaves/leaf_cluster.png` (Poly Haven `tree_small_02`, CC0).
Keine neuen Fremd-Assets.

### Nachtrag: Nachtzug-Reisende v2 (gehautet, Idle-Animationen) - `assets/characters/civilian/civ_nz_*.glb`

Ersetzen im Nachtzug die statischen `civ_<kind>.glb` (die bleiben fuer andere Level). Zwoelf Figuren
`civ_nz_<kind>.glb` (tweed | dame | pulli | blazer | hemd | alt | bluse | jacke | anzug | kostuem: gehautet, MPFB-"game_engine"-Skelett,
je ca. 24k Dreiecke, Posen-Schleifen seat/seat_table/seat_lean/seat_cross/duck/cower mit Atmen und Blickwechseln;
schlaf_m | schlaf_f: statische Rueckenlage). Texturen bis 2k mit Kleidungs-Normalmaps; Godot extrahiert `civ_nz_<kind>_*.jpg/png`.
Gebaut mit `python tools/civilian/prep_civ_nz.py <tex_dir> <kind>` +
`blender -b --python tools/civilian/build_civ_nz.py -- <tex_dir> <out.glb> --kind=<kind> [--static=lie]`
(Blender 4.2 + MPFB 2.0.18, MPFB selbst wird **nicht** mitgeliefert). Laufzeit: `game/levels/nachtzug_civilian.gd`.

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Basismesh, Morphs, Skelett; Haeute `middleage_caucasian_male/female`, `young_caucasian_male/male2/female`, `old_caucasian_male/female`, `young_asian_male`, `middleage_asian_female`, `middleage_african_male`, `young_african_female`; Augen `low-poly`, Brauen `eyebrow001`, Wimpern `eyelashes01`; Haare `short01`-`short04`, `bob01`, `bob02`, `ponytail01`, `long01`; Kleidung `male_casualsuit02/03/05/06`, `male_elegantsuit01`, `female_elegantsuit01`, `female_casualsuit01`; Schuhe `shoes01`, `shoes04` (Stoffe umgefaerbt, Logos entfernt) | MakeHuman System Assets, https://files.makehumancommunity.org/asset_packs/makehuman_system_assets/makehuman_system_assets_cc0.zip | MakeHuman-Team | CC0 |
| Anzuege `toigo_male_double-breasted_suit`, `toigo_male_suit_3`, `toigo_female_double-breasted_suit`, `toigo_female_suit_2`, `toigo_female_suit` (umgefaerbt) | Asset-Pack suits01, https://files.makehumancommunity.org/asset_packs/suits01/suits01_cc0.zip | MargaretToigo | CC0 |
| Stiefeletten `toigo_ankle_boots_male`, `toigo_ankle_boots_female` | Asset-Pack shoes01, https://files.makehumancommunity.org/asset_packs/shoes01/shoes01_cc0.zip | MargaretToigo | CC0 |

Selbst erzeugt (CC0): Stoffmuster (Fischgrat, Strick, Melange, Koeper, Jersey - prozedural in `prep_civ_nz.py`), Posen
und Idle-Animationen. Lizenznachweis MakeHuman: https://static.makehumancommunity.org/about/license.html

### Nachtrag: Story-Figuren Curfew/Kanalisation und Kanzleramt-Geiseln (Realismus-Pass) - `assets/characters/civilian/`

Ersetzen die alten Kastenfiguren. Gleiche Pipeline wie oben, neu: `build_civ.py --poses=stand|bound_seat|kneel` und die
Arten voss | kaempfer | praesidentin | abgeordneter. Dateien: `civ_voss_stand.glb`, `civ_kaempfer_stand.glb`,
`civ_jacke_stand.glb` (Pose "stand"; Konrad Voss + zwei Begleiter in `curfew.gd`, Voss in `kanalisation.gd`),
`civ_praesidentin_geisel.glb` (bound_seat/stand), `civ_<abgeordneter|alt|frau|mantel|frau2>_geisel.glb` (bound_seat/kneel;
Geiseln im Kanzleramt ueber `game/systems/breach_hostage.gd`). Je Pose ca. 22-24k Dreiecke. Laufzeit-Helfer:
`game/characters/civ_figure.gd`.

| Bestandteil | Quelle | Autor | Lizenz |
|---|---|---|---|
| Haeute `old_caucasian_male`, `old_caucasian_female`, `young_caucasian_male`, `middleage_caucasian_male` (verblendet); Haare `short04`, `bob01`; Kleidung `male_casualsuit01` (umgefaerbt: Oliv/Dunkel) | MakeHuman System Assets (Link s. o.) | MakeHuman-Team | CC0 |
| Anzuege `toigo_male_double-breasted_suit` (Voss, Anthrazit), `toigo_female_double-breasted_suit` (Praesidentin Hartmann, Bordeaux), `toigo_male_suit_tie_and_jacket` (Abgeordnete, Marine + rote Krawatte) | Asset-Pack suits01 (Link s. o.) | MargaretToigo | CC0 |
| Geiselstuhl: Poly Haven `dining_chair_02` (vorhanden, ueber `FurnitureKit`) | https://polyhaven.com/a/dining_chair_02 | Poly Haven | CC0 |

Selbst erzeugt (CC0): Posen stehend, gefesselt sitzend, kniend (Haende hinter dem Ruecken).

### Nachtrag: Ausgebrannte Fahrzeugwracks (Pkw/Transporter/Lkw/Bus, Panzerwrack) - `assets/vehicles/wrecks/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich (je 1K diffuse/normal/arm):
- `textures/rust_coarse_01/` - https://polyhaven.com/a/rust_coarse_01 (Brandrost der Karosserie)
- `textures/rusty_metal_04/` - https://polyhaven.com/a/rusty_metal_04 (Zunder-/Ascheschicht)
- `textures/burned_ground_01/` - https://polyhaven.com/a/burned_ground_01 (Grundlage des Brandfleck-Decals)

Selbst erzeugt (CC0): Wrackgeometrie `game/vehicles/models/wreck_model.gd` (prozedural: Karosserie mit Fensteroeffnungen,
Saeulen, eingesacktes Dach, Sitzgestelle mit Federn, Felgen, Ladeflaeche), Shader `assets/vehicles/wrecks/burnt_vehicle.gdshader`,
Brandfleck `textures/scorch_decal*.png` (erzeugt mit `tools/gen_wreck_decal.py`).
Panzerwrack: wiederverwendet `assets/vehicles/marder/rabe_marder.scn` ("Marder 1A3 | High-Quality model" von Scout, CC-BY 4.0, s. o.),
ausgebrannt eingefaerbt, Turm verdreht, Heckrampe offen.

### Nachtrag: Nachtzug-Innenraeume - `assets/environment/train/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich (je 1K diffuse/normal/arm):
- `textures/sapele_veneer/` - https://polyhaven.com/a/sapele_veneer (Holzvertaefelung, Bettkaesten, Bilderrahmen)
- `textures/lacquered_cherry_wood/` - https://polyhaven.com/a/lacquered_cherry_wood (Tische, Fensterbretter, Theke)
- `textures/quatrefoil_jacquard_fabric/` - https://polyhaven.com/a/quatrefoil_jacquard_fabric (Sitzpolster/Moquette, Matratzen)
- `textures/velour_velvet/` - https://polyhaven.com/a/velour_velvet (Vorhaenge, Wolldecken)
- `textures/dirty_carpet/` - https://polyhaven.com/a/dirty_carpet (Teppichboden)

Wiederverwendet (bereits oben gelistet, CC0): `villa/beige_wall_001` (Wandpaneele/Decke), `villa/decals` (Kratzer, Flecken,
Handabdruecke), `villa/art` (Bilder in den Abteilen), `characters/textures/rough_linen` (Kopfschoner, Tischdecken, Bettwaesche),
`environment/textures/weathered_planks` (Gepaeckwagen), `rail/textures/rusty_painted_metal` (Gepaeckwagenwaende),
`rock_face_03` + `villa/mountains.gdshader` (Hoehenzuege neben der Strecke).
Selbst erzeugt (CC0): Schilder `signs/notbremse.png`, `fahrplan.png`, `rauchverbot.png`, `aufkleber.png`, `hinweis.png`
(`tools/gen_train_signs.py`, erfundene Bahn "Alpen-Donau-Bahn" und Texte), Innenraum-Geometrie `game/levels/nachtzug_interior.gd`.

### Nachtrag: Innenraum-Moebel - `assets/props/furniture/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich (glTF mit 1K-Texturen),
eingesetzt ueber `game/levels/furniture_kit.gd` (eigener Code, CC0):
- `sofa_03/` - https://polyhaven.com/a/sofa_03 (Polstersofa, Villa-Salon)
- `sofa_02/` - https://polyhaven.com/a/sofa_02 (Leder-Chesterfield, Kanzleramt-Sitzgruppen)
- `gothic_coffee_table/` - https://polyhaven.com/a/gothic_coffee_table (Couchtisch, Villa-Salon)
- `GothicCabinet_01/` - https://polyhaven.com/a/GothicCabinet_01 (Garderobenschrank, Villa-Halle)
- `ClassicConsole_01/` - https://polyhaven.com/a/ClassicConsole_01 (Konsole, Villa-Halle)
- `WoodenTable_01/` - https://polyhaven.com/a/WoodenTable_01 (Schreibtisch, Villa-Bibliothek)
- `GreenChair_01/` - https://polyhaven.com/a/GreenChair_01 (Schreibtischstuhl, Villa-Bibliothek)
- `ArmChair_01/` - https://polyhaven.com/a/ArmChair_01 (Sessel am Kamin, Villa-Bibliothek)
- `dining_chair_02/` - https://polyhaven.com/a/dining_chair_02 (Lederstuehle, Kanzleramt (Kabinettssaal, Saal 2. OG))
- `modern_wooden_cabinet/` - https://polyhaven.com/a/modern_wooden_cabinet (Sideboard, Kabinettssaal)
- `vintage_cabinet_01/` - https://polyhaven.com/a/vintage_cabinet_01 (Vitrinenschrank, Villa-Salon und Kabinettssaal)
- `metal_office_desk/` - https://polyhaven.com/a/metal_office_desk (Stahlschreibtische, Kanzleramt-Bueros/Saal, Bunker-Kontrollraum)
- `wooden_table_02/` - https://polyhaven.com/a/wooden_table_02 (Holztische, Bunker-Unterkunft (einer umgekippt))
- `wooden_bookshelf_worn/` - https://polyhaven.com/a/wooden_bookshelf_worn (Autor Ulan Cabanilla; Buecherregale der Villa-Bibliothek, `FK.bookshelves`)
- `book_encyclopedia_set_01/` - https://polyhaven.com/a/book_encyclopedia_set_01 (Autor John Malcolm; nur Cover-Textur diff/nor_gl 1K: Buchruecken/Deckel der prozeduralen Buch-Quader in den Villa-Regalen)

### Nachtrag: Curfew-Fernmeldestelle/U-Bahn und Hafen-Tonnen - `assets/environment/curfew/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich. Geladen per
`tools/fetch_curfew_assets.py` (1K-Texturen als diffuse/normal/arm.jpg, Modelle als glTF mit 1K-Texturen).
Texturen (`textures/`):
- `long_white_tiles/` - https://polyhaven.com/a/long_white_tiles (Fliesenwaende und gruenes Kachelband im U-Bahn-Tunnel, curfew)
- `concrete_wall_006/` - https://polyhaven.com/a/concrete_wall_006 (Tunneldecke, Gewoelbeansatz, Stirnwaende, curfew)
- `concrete_floor_worn_001/` - https://polyhaven.com/a/concrete_floor_worn_001 (Treppenstufen im Notausgangsschacht, curfew; seit 14.11. auch Zementestrich in Technikebene und Lagezentrum, `game/levels/bunker.gd`)
Modelle (`models/`):
- `vintage_radio_transceiver/` - https://polyhaven.com/a/vintage_radio_transceiver (Funkgeraet auf dem Funkerpult)
- `television_02/` - https://polyhaven.com/a/television_02 (Sichtgeraete in der Fernmeldestelle)
- `retro_multimeter/` - https://polyhaven.com/a/retro_multimeter (Messgeraete auf den Arbeitstischen)
- `desk_lamp_arm_01/` - https://polyhaven.com/a/desk_lamp_arm_01 (Gelenklampe am Funkerpult)
- `metal_stool_01/` - https://polyhaven.com/a/metal_stool_01 (Hocker in der Fernmeldestelle)
- `wall_clock/` - https://polyhaven.com/a/wall_clock (Wanduhr Fernmeldestelle)
- `worn_metal_rack/` - https://polyhaven.com/a/worn_metal_rack (Lagerregale Fernmeldestelle)
- `ocean_buoy/` - https://polyhaven.com/a/ocean_buoy (rote Fahrwassertonnen der Bootsfahrt, hafen_night.gd)

### Nachtrag: Scan-Felgen der ausgebrannten Bus-/Lkw-/Transporter-Wracks - `assets/props/vehicles_wreck/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), Autor John Hutcheson. Geladen per `tools/fetch_wreck_wheels.py`
(glTF mit 1K-Texturen diff/nor_gl/arm). Eingebaut in `game/vehicles/models/wreck_model.gd` (Felgen ohne Reifen, Blendshape verworfen):
- `rusted_wheel_rim_01/` - https://polyhaven.com/a/rusted_wheel_rim_01
- `rusted_wheel_rim_02/` - https://polyhaven.com/a/rusted_wheel_rim_02
Hinweis: Poly Haven/ambientCG bieten keine CC0-Modelle von Bus, Lkw oder Transporter; die Karosserien bleiben prozedural.

### Nachtrag: Bunker-Detailpass (Letztes Gefecht) - `assets/environment/bunker/textures/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich. Per Python ueber die
Poly-Haven-API geladen (1K-Texturen als diffuse/normal/arm.jpg), eingebaut in `game/levels/bunker.gd` (`_make_mats`):
- `linoleum_brown/` - https://polyhaven.com/a/linoleum_brown (Rob Tuytel; Linoleum in Schlafsaal und Kontrollraum, grauoliv getoent)
- `painted_steel/` - https://polyhaven.com/a/blue_metal_plate ("Blue Metal Plate"; diffuse.jpg entsaettigt und auf Mittelgrau normiert,
  normal/arm unveraendert; lackierte Stahlkonsolen, Schraenke, Pulte und Monitorgehaeuse im Bunker)

### Nachtrag: Vegetations- und Bodenpass - `assets/environment/vegetation/models/`
Poly Haven (https://polyhaven.com), Lizenz CC0 (gemeinfrei), keine Namensnennung erforderlich. Geladen per
`tools/fetch_vegetation_assets.py` (glTF mit 1K-Texturen, Lizenz je Asset geprueft), eingebaut ueber `game/levels/ground_cover.gd`
(Bodenbewuchs in rail_yard, river_crossing, baltic_night) und `game/levels/ph_props.gd` (Baumstumpf, baltic_night):
| Datei(en) | Quelle | Autor | Lizenz | Groesse |
|---|---|---|---|---|
| `tree_stump_02/` | https://polyhaven.com/a/tree_stump_02 | Rob Tuytel | CC0 | 4,3 MB |
| `grass_medium_02/` | https://polyhaven.com/a/grass_medium_02 | Rico Cilliers | CC0 | 0,8 MB |
| `dandelion_01/` | https://polyhaven.com/a/dandelion_01 | Rob Tuytel, Rico Cilliers | CC0 | 3,0 MB |
| `weed_plant_02/` | https://polyhaven.com/a/weed_plant_02 | Rob Tuytel, Rico Cilliers | CC0 | 2,0 MB |
| `nettle_plant/` | https://polyhaven.com/a/nettle_plant | Rob Tuytel, Rico Cilliers | CC0 | 2,4 MB |
| `rock_moss_set_02/` | https://polyhaven.com/a/rock_moss_set_02 | Kless Gyzen | CC0 | 1,9 MB |
| `dry_branches_medium_01/` | https://polyhaven.com/a/dry_branches_medium_01 | Rico Cilliers | CC0 | 3,2 MB |
### Nachtrag: Bunker-Materialpass 2 (Papier, Leder, Stahltueren) - `assets/environment/bunker/textures/`
Geladen per `tools/fetch_bunker_assets.py` (1K), eingebaut in `game/levels/bunker.gd` (`_make_mats`, `_build_doors`, `_screen_mat`)
und `game/levels/bunker_screen.gdshader` (Papierstruktur der Lagekarte):
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `brown_leather/` (diffuse/normal/arm.jpg) | https://polyhaven.com/a/brown_leather | Rob Tuytel | CC0 | Aktenkoffer, Leder-Schreibunterlage des Kartentischs (umgetoent) |
| `metal_plate/` (diffuse/normal/arm.jpg) | https://polyhaven.com/a/metal_plate | Rob Tuytel | CC0 | Stahltueren (Innentuer, Panzertuer, Luke, Korridor-Seitentueren) |
| `paper_creased/` (diffuse/normal/rough.jpg) | https://ambientcg.com/view?id=Paper003 | ambientCG | CC0 | Papierstapel, Papierstruktur der Lagekarte |
### Nachtrag: Fernkulissen statt Quader (Spreebogen, Bahnhof/Pskow, Bergstation)
Keine neuen Downloads. Die bereits gelisteten Poly-Haven-Texturen (CC0) werden in diese Kulissen wiederverwendet:
`game/levels/far_city.gd` und `assets/environment/facade/far_facade.gdshader`, aufgerufen aus `spreebogen.gd` (Moabit, Regierungsviertel, Reichstag)
und `rail_yard.gd` (Horizont, Schlote, Kreml). Die Bergstation in `alpenpass.gd` nutzt sie ebenfalls.
Fensterraster, Laibungen, Spiegelung und Glaskuppel (`glass_dome.gdshader`) sind prozedural.
| Kuerzel | Textur | Quelle | Lizenz |
|---|---|---|---|
| brick / plaster / plaster_old / concrete | `facade/textures/red_brick_03`, `painted_plaster_wall`, `rough_plaster_broken`, `precast_concrete_wall` | polyhaven.com (gleichnamige Assets) | CC0 |
| brick_old / concrete_old | `assets/textures/brick_wall_02`, `concrete_wall_008` | polyhaven.com | CC0 |
| sandstone / tile | `berlin/textures/large_sandstone_blocks`, `concrete_tile_facade` | polyhaven.com | CC0 |
| panel | `funkturm/textures/concrete_panels` | polyhaven.com | CC0 |
| factory / corrugated | `rail/textures/factory_wall`, `worn_corrugated_iron` | polyhaven.com | CC0 |

### Nachtrag: Innenraeume Kanzleramt + Bunker-Kontrollraum - `assets/environment/interior/`
Geladen per `tools/fetch_interior_assets.py` (Poly Haven, 1K), eingebaut in `game/levels/kanzleramt.gd` (`_build_dressing`) und `game/levels/bunker.gd` (`_build_control_dressing`):
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `textures/american_walnut_veneer/` | https://polyhaven.com/a/american_walnut_veneer | Jenelle van Heerden | CC0 | Wandvertaefelung Kanzleramt (Saal, Bueros, Halle) |
| `textures/poly_wool_herringbone/` | https://polyhaven.com/a/poly_wool_herringbone | colormass, Rico Cilliers | CC0 | Teppich mit Fischgratmuster (Saal, Bueros) |
| `models/fancy_picture_frame_01/` | https://polyhaven.com/a/fancy_picture_frame_01 | Rob Tuytel, Rico Cilliers | CC0 | Gemaelde Bueros |
| `models/fancy_picture_frame_02/` | https://polyhaven.com/a/fancy_picture_frame_02 | Rob Tuytel, Rico Cilliers | CC0 | Gemaelde Kabinettssaal, Halle |
| `models/hanging_picture_frame_02/` | https://polyhaven.com/a/hanging_picture_frame_02 | James Ray Cock | CC0 | Bilder Ostwand Kabinettssaal |
| `models/Shelf_01/` | https://polyhaven.com/a/Shelf_01 | Gabriel Radić | CC0 | Buecherregale Bueros |
| `models/drawer_cabinet/` | https://polyhaven.com/a/drawer_cabinet | Ulan Cabanilla | CC0 | Aktenschraenke Bueros |
| `models/potted_plant_02/` | https://polyhaven.com/a/potted_plant_02 | Rico Cilliers | CC0 | Topfpflanzen |
| `models/office_notepads/` | https://polyhaven.com/a/office_notepads | Ulan Cabanilla | CC0 | Notizbloecke Kabinettstisch, Schreibtische |
| `models/binder_notebook/` | https://polyhaven.com/a/binder_notebook | DaDrood | CC0 | Aktenordner |
| `models/stationery_supplies/` | https://polyhaven.com/a/stationery_supplies | Mateusz Sadek | CC0 | Schreibtisch-Utensilien |
| `models/marble_bust_01/` | https://polyhaven.com/a/marble_bust_01 | Rico Cilliers | CC0 | Bueste in der Halle |
| `models/fire_alarm/` | https://polyhaven.com/a/fire_alarm | Slinc | CC0 | Brandmelder (Kanzleramt-Flur, Bunker-Kontrollraum) |
| `models/korean_fire_extinguisher_01/` | https://polyhaven.com/a/korean_fire_extinguisher_01 | UM JOORIN | CC0 | Feuerloescher (Kanzleramt, Bunker) |
| `models/steel_frame_shelves_01/` | https://polyhaven.com/a/steel_frame_shelves_01 | James Ray Cock | CC0 | Stahlregal Bunker-Kontrollraum (Skalierung 0.1) |
| `models/industrial_caged_sconce/` | https://polyhaven.com/a/industrial_caged_sconce | Ulan Cabanilla | CC0 | Gitterleuchten Bunker-Kontrollraum |
| `models/metal_toolbox/` | https://polyhaven.com/a/metal_toolbox | Mateusz Sadek | CC0 | Werkzeugkasten Bunker-Kontrollraum |

### Nachtrag: Speisewagen Nachtzug, Laternen Curfew/Kanalisation, Feuerloescher (14.11.)
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/train/models/tea_set_01/` (glTF + 1k-Texturen) | https://polyhaven.com/a/tea_set_01 | Rico Cilliers (Modell), James Ray Cock (Texturen), Jurita Burger (Grafik) | CC0 | Teller, Tassen, Untertassen im Speisewagen (`game/levels/nachtzug_table_deco.gd`) |
| `assets/environment/train/models/wine_bottles_01/` (glTF + 1k-Texturen) | https://polyhaven.com/a/wine_bottles_01 | Rico Cilliers (Modell), Jurita Burger (Grafik) | CC0 | Weinflaschen auf den Speisewagen-Tischen |
| `assets/environment/interior/models/fire_extinguisher_de/` | abgeleitet von https://polyhaven.com/a/korean_fire_extinguisher_01 | UM JOORIN (Original), Texturen deutsch beschriftet | CC0 | Feuerloescher Kanzleramt/Bunker: koreanische Schrift entfernt, Aufdruck "FEUERLÖSCHER", deutsches Etikett und Pruefkarte (`tools/gen_fire_extinguisher_de.py`, PIL; Windows-Schriften Bahnschrift/Ink Free nur gerastert) |

Wiederverwendet: `props/models/Lantern_01` (siehe oben) jetzt auch als Sturmlaterne bei Voss in `curfew.gd` und `kanalisation.gd`
(ersetzt den bernsteinfarbenen Kasten). Weinglaeser, Tischlampen und Besteck im Speisewagen sind prozedurale Drehkoerper.

### Nachtrag: Dachlandschaft ep_lena (14.11.)
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/curfew/textures/bitumen/` (2k diffuse/nor_gl/arm) | https://polyhaven.com/a/bitumen | Rob Tuytel | CC0 | Dachpappe und Flicken der Flachdaecher (`game/levels/ep_lena_roofs.gd`) |
| `assets/environment/curfew/textures/roof_slates_03/` (2k diffuse/nor_gl/arm) | https://polyhaven.com/a/roof_slates_03 | Rob Tuytel | CC0 | Schiefer der Mansarddaecher und Gauben (ep_lena) |
| `assets/environment/curfew/textures/box_profile_metal_sheet/` (1k diffuse/nor_gl/arm) | https://polyhaven.com/a/box_profile_metal_sheet | Amal Kumar | CC0 | Trapezblech von Klimageraeten/Aufbauten (ep_lena) |

Wiederverwendet: `street/models/exterior_aircon_unit` (Poly Haven, CC0, siehe `assets/CREDITS.md`) als Klimageraete auf Regierungsbau/Ministerium in ep_lena.

### Nachtrag: Villa-Steg (14.11.)
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/villa/rough_wood/` (1k diffuse/normal/arm) | https://polyhaven.com/a/rough_wood | Rob Tuytel | CC0 | Bohlen, Pfaehle, Traeger, Ruderboot und Bootshaus-Steg der Villa (`game/levels/villa_jetty.gd`) |

### Nachtrag: Fernsicht ep_lena / Hafen-Hubbruecke (14.11.)
Keine neuen Dateien, nur Wiederverwendung bereits gelisteter Poly-Haven-Texturen (CC0): `river/textures/rough_concrete` (Kaimauer, Brueckenpfeiler, Rampen), `berlin/textures/large_sandstone_blocks` (Kaikante), `rail/textures/rusty_painted_metal` (Brueckentraeger, Hubtuerme, Gelaender, Torzargen), `rail/textures/rusty_corrugated_iron` (Rolltore), `textures/weathered_planks` (Reibepfaehle, Pfeilerfender) in `game/levels/hafen_world.gd`; `far_city.gd` + `far_facade.gdshader` zusaetzlich in `ep_lena.gd` (Skyline) und `hafen_world.gd` (Lagerhallen).

### Nachtrag: Realismus Bunker-Lagezentrum/Technik und Kanzleramt-Saele (14.11.)
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/bunker/textures/concrete_wall_004/` (1k diffuse/normal/arm) | https://polyhaven.com/a/concrete_wall_004 | Dario Barresi, Charlotte Baglioni | CC0 | Schalungsbeton Waende/Decken Lagezentrum, Technikebene, Notausgang (`game/levels/bunker.gd`) |
| `assets/environment/bunker/textures/painted_concrete/` (1k diffuse/normal/arm) | https://polyhaven.com/a/painted_concrete | Dario Barresi, Dimitrios Savva | CC0 | Gruener Sockelanstrich an Waenden und Saeulen (bunker.gd) |
| `assets/environment/bunker/textures/concrete_floor_painted/` (1k diffuse/normal/arm) | https://polyhaven.com/a/concrete_floor_painted | Rob Tuytel | CC0 | Estrich mit Bodenfarbe in Lagezentrum und Technik (bunker.gd) |
| `assets/environment/interior/textures/ceiling_interior/` (1k diffuse/normal/arm) | https://polyhaven.com/a/ceiling_interior | Dimitrios Savva | CC0 | Rauputzdecke (Kassettenfelder), Saal unterm Dach + Kabinettssaal (`game/levels/kanzleramt.gd`) |
| `assets/environment/interior/textures/white_plaster_02/` (1k diffuse/normal/arm) | https://polyhaven.com/a/white_plaster_02 | Rob Tuytel | CC0 | Feiner Wandputz der beiden Saele und Stuckprofil der Kassetten-Unterzuege (kanzleramt.gd) |
| `assets/environment/interior/textures/wooden_panels/` (1k diffuse/normal/arm) | https://polyhaven.com/a/wooden_panels | Dimitrios Savva | CC0 | Holzpaneele an der Nordwand des Saals unterm Dach (kanzleramt.gd) |

Wiederverwendet: `train/textures/velour_velvet` (Poly Haven, CC0, siehe oben) fuer die Samtvorhaenge im Kanzleramt; `far_city.gd` + `far_facade.gdshader` als Stadt hinter den Fensterbaendern (kanzleramt.gd). Download: `tools/fetch_bunker_assets.py`, `tools/fetch_interior_assets.py`.

### Nachtrag: Hafen-Hubbruecke Fachwerk und Molenfeuer (14.11.)
Keine neuen Dateien, nur Wiederverwendung bereits gelisteter Poly-Haven-Texturen (CC0) in `game/levels/hafen_world.gd`: `bunker/textures/painted_steel` (https://polyhaven.com/a/blue_metal_plate, lackierte Vollwandtraeger und genietetes Fachwerk der Hubspanne), `facade/textures/painted_plaster_wall` (https://polyhaven.com/a/painted_plaster_wall, Putz der beiden Leuchttuerme, weiss/rot eingefaerbt), `river/textures/rough_concrete` (Leuchtturmsockel), `rail/textures/rusty_painted_metal` (Galerie, Laterne, Haube).

### Nachtrag: Realismus curfew/kanalisation/ep_lena (14.11.)
| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/realism/textures/brick_gravel/` (1k diffuse/normal/arm) | https://polyhaven.com/a/brick_gravel | Dimitrios Savva | CC0 | Schuttkegel (Hoehenfeld) am Einsturz, `game/levels/debris_kit.gd` / `kanalisation.gd` |
| `assets/environment/realism/textures/concrete_debris/` (1k diffuse/normal/arm) | https://polyhaven.com/a/concrete_debris | Amal Kumar | CC0 | Ziegel, Ziegelbruch und Betonbrocken (MultiMesh), `debris_kit.gd` |
| `assets/environment/realism/textures/square_tiled_wall/` (1k diffuse/normal/arm) | https://polyhaven.com/a/square_tiled_wall | Charlotte Baglioni | CC0 | Fliesensockel im Anbau/Fernmeldestelle, `game/levels/curfew.gd` |
| `assets/environment/realism/models/steel_frame_shelves_02/` (glTF 1k) | https://polyhaven.com/a/steel_frame_shelves_02 | James Ray Cock | CC0 | Regal im Versorgungskeller, `kanalisation.gd` |
| `assets/environment/realism/models/metal_tool_chest/` (glTF 1k) | https://polyhaven.com/a/metal_tool_chest | Yann Kervran, John Hutcheson | CC0 | Werkzeugkiste im Versorgungskeller, `kanalisation.gd` |

Wiederverwendet (bereits gelistet, CC0): `facade/textures/painted_plaster_wall` (Putz Anbau/Keller), `river/models/utility_box_01` (Schaltkaesten), `river/models/Barrel_01`, `river/models/cement_bag` (Keller), `bunker/textures/linoleum_brown`, `bunker/textures/concrete_floor_painted`, `interior/textures/ceiling_interior`, `interior/textures/american_walnut_veneer`, `rusty_metal_02` aus der vorhandenen Geo.mat-Bibliothek (Rohre, Lueftungskanal). Der Lkw in curfew nutzt `game/levels/villa_truck.gd` (eigene Geometrie). Download: `tools/fetch_realism_assets.py`.

## Sounds (Sound-Overhaul v0.6, 17.11.) - `assets/sfx/`

Alle Aufnahmen CC0 1.0 (Freesound, nur CC0 gefiltert; Kenney CC0). Geschnitten, gelayert (teils mit synthetischer Tiefton-Druckwelle), normalisiert, Mono-OGG. Dateinamen ohne `.ogg`; `_N` = Varianten.

| Titel | Autor | Quelle | Lizenz | Dateien |
|---|---|---|---|---|
| AR15 rifle shot | michorvath | https://freesound.org/people/michorvath/sounds/427596/ | CC0 1.0 | rifle_fire, weapons/tail_out |
| AssaultRifle1.wav | SuperPhat | https://freesound.org/people/SuperPhat/sounds/404562/ | CC0 1.0 | rifle_fire_2 |
| M16 Rifle Shots.flac | qubodup | https://freesound.org/people/qubodup/sounds/187677/ | CC0 1.0 | enemy_rifle_4, overwatch_dmr_fire_4, rifle_fire_3, rifle_fire_4 |
| Automatic Assault Rifle.wav | SuperPhat | https://freesound.org/people/SuperPhat/sounds/416417/ | CC0 1.0 | rifle_fire_5 |
| AK47 Shot | LeMudCrab | https://freesound.org/people/LeMudCrab/sounds/163457/ | CC0 1.0 | enemy_mg_3, enemy_rifle_2, weapons/ak_fire |
| AK47 Fire into Street.aif | Franki-01234 | https://freesound.org/people/Franki-01234/sounds/201670/ | CC0 1.0 | enemy_mg_4, enemy_rifle, weapons/ak_fire_2, weapons/ak_fire_3, weapons/tail_out_2 |
| Kalashnikov 1 (indoor) | mahecic | https://freesound.org/people/mahecic/sounds/812210/ | CC0 1.0 | weapons/ak_fire_4, weapons/tail_in |
| AK47 and various other gunshots at indoor shooting range | acidsnowflake | https://freesound.org/people/acidsnowflake/sounds/402791/ | CC0 1.0 | enemy_rifle_3, weapons/ak_fire_5 |
| 9mm pistol shot | michorvath | https://freesound.org/people/michorvath/sounds/427592/ | CC0 1.0 | pistol_fire |
| Pistol Shot | LeMudCrab | https://freesound.org/people/LeMudCrab/sounds/163456/ | CC0 1.0 | pistol_fire_2 |
| 9mm_gunshot.wav | mnslugger20 | https://freesound.org/people/mnslugger20/sounds/244138/ | CC0 1.0 | pistol_fire_3 |
| gun_9mm_15m_in_front_m10.wav | johanwestling | https://freesound.org/people/johanwestling/sounds/377789/ | CC0 1.0 | pistol_fire_4 |
| Pocket Pistol gunshot 2 (Outside of room) | mahecic | https://freesound.org/people/mahecic/sounds/803497/ | CC0 1.0 | pistol_fire_5 |
| S20-30 Pistol shots with silencer.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/675677/ | CC0 1.0 | curfew_pistol_sd, curfew_pistol_sd_2, curfew_pistol_sd_3 |
| Sniper Shot | LeMudCrab | https://freesound.org/people/LeMudCrab/sounds/163460/ | CC0 1.0 | overwatch_dmr_fire |
| Sniper Rifle | SuperPhat | https://freesound.org/people/SuperPhat/sounds/514228/ | CC0 1.0 | overwatch_dmr_fire_2 |
| Sniper Rifle M24 SFX.mp3 | kennysvoice | https://freesound.org/people/kennysvoice/sounds/351777/ | CC0 1.0 | overwatch_dmr_fire_3 |
| LightMachineGun1.wav | SuperPhat | https://freesound.org/people/SuperPhat/sounds/417688/ | CC0 1.0 | enemy_mg |
| Machine Gun 002 - triple shot.ogg | pgi | https://freesound.org/people/pgi/sounds/212606/ | CC0 1.0 | enemy_mg_2 |
| rpg launcher  three shots.wav | klangfabrik | https://freesound.org/people/klangfabrik/sounds/249298/ | CC0 1.0 | rocket_launch |
| Launching Anti-Tank Missiles.flac | qubodup | https://freesound.org/people/qubodup/sounds/184274/ | CC0 1.0 | rocket_launch_2 |
| Rocket Launch | Jarusca | https://freesound.org/people/Jarusca/sounds/521377/ | CC0 1.0 | rocket_launch_3 |
| Forest Impulse Response Gunshot Tail | modusmogulus | https://freesound.org/people/modusmogulus/sounds/734096/ | CC0 1.0 | weapons/tail_out_3 |
| 357 Magnum Revolver Gunshot with Tail | Shark_Anthony | https://freesound.org/people/Shark_Anthony/sounds/683175/ | CC0 1.0 | weapons/tail_out_4 |
| Kalashnikov 2 (indoor) | mahecic | https://freesound.org/people/mahecic/sounds/812211/ | CC0 1.0 | weapons/tail_in_2 |
| AR15 rifle shot from 50 yards away | michorvath | https://freesound.org/people/michorvath/sounds/427597/ | CC0 1.0 | weapons/far_rifle |
| R12-09-Rifle Shots, Natural Reverb.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/486063/ | CC0 1.0 | weapons/far_rifle_2, weapons/far_rifle_3, weapons/far_rifle_4 |
| G35-17-Rifle Cracks.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/438582/ | CC0 1.0 | weapons/far_rifle_5 |
| AR15 M4 Gun Hardware Magazine Movement Sounds | jackthemurray | https://freesound.org/people/jackthemurray/sounds/393732/ | CC0 1.0 | weapon_bolt, weapon_bolt_2, weapon_bolt_3, weapon_mag_in, weapon_mag_in_2, weapon_mag_in_3, weapon_mag_out, weapon_mag_out_2, weapon_mag_out_3 |
| Glock 19 Handgun Pistol Slide Cocking Sounds | jackthemurray | https://freesound.org/people/jackthemurray/sounds/393734/ | CC0 1.0 | pistol_mag_in, pistol_mag_in_2, pistol_mag_in_3, pistol_mag_out, pistol_mag_out_2, pistol_mag_out_3, pistol_slide, pistol_slide_2, pistol_slide_3, pistol_slide_4 |
| GUNRif_M1 GARAND DRY FIRE_MP.wav | MPierluissi | https://freesound.org/people/MPierluissi/sounds/460852/ | CC0 1.0 | dry_fire, dry_fire_2, dry_fire_3 |
| Bouncing Shell Casings (Various Sizes) | GryffDavid | https://freesound.org/people/GryffDavid/sounds/318964/ | CC0 1.0 | shell_drop, shell_drop_2, shell_drop_3, shell_drop_4, shell_drop_5, shell_drop_6 |
| bullets hit EDIT.aif | Woodingp | https://freesound.org/people/Woodingp/sounds/116645/ | CC0 1.0 | impacts/concrete, impacts/concrete_2, impacts/concrete_3, impacts/concrete_4, impacts/concrete_5, impacts/concrete_6, impacts/glass, impacts/glass_2, impacts/glass_3, impacts/glass_4, impacts/metal, impacts/metal_2, impacts/metal_3, impacts/metal_4, impacts/metal_5, impacts/metal_6, impacts/metal_7, impacts/metal_8, impacts/water, impacts/water_2, impacts/water_3, impacts/water_4, impacts/water_5, impacts/wood, impacts/wood_2, impacts/wood_3, impacts/wood_4, impacts/wood_5 |
| bullet impacts | pushkin | https://freesound.org/people/pushkin/sounds/144444/ | CC0 1.0 | impacts/concrete, impacts/concrete_2, impacts/concrete_3, impacts/concrete_4, impacts/concrete_5, impacts/concrete_6, impacts/dirt, impacts/dirt_2, impacts/dirt_3, impacts/dirt_4, impacts/dirt_5 |
| Foley bullet hit metal 02.wav | martian | https://freesound.org/people/martian/sounds/182263/ | CC0 1.0 | impacts/metal, impacts/metal_2, impacts/metal_3, impacts/metal_4, impacts/metal_5, impacts/metal_6, impacts/metal_7 |
| HeavyBulletPing.mp3 | wilhellboy | https://freesound.org/people/wilhellboy/sounds/351371/ | CC0 1.0 | impacts/metal_8 |
| Single Rock hit Dirt.wav | worthahep88 | https://freesound.org/people/worthahep88/sounds/319222/ | CC0 1.0 | impacts/dirt, impacts/dirt_3, impacts/dirt_5 |
| Single Rock hit dirt 2.wav | worthahep88 | https://freesound.org/people/worthahep88/sounds/319229/ | CC0 1.0 | impacts/dirt_2, impacts/dirt_4 |
| Glass Break | unfa | https://freesound.org/people/unfa/sounds/221528/ | CC0 1.0 | impacts/glass_5 |
| VisceralBulletImpacts.wav | u1769092 | https://freesound.org/people/u1769092/sounds/423301/ | CC0 1.0 | impacts/flesh, impacts/flesh_2 |
| ricochet.mp3 | cedarstudios | https://freesound.org/people/cedarstudios/sounds/148840/ | CC0 1.0 | ricochet |
| Ricochet 2.wav | morganpurkis | https://freesound.org/people/morganpurkis/sounds/392975/ | CC0 1.0 | ricochet_2 |
| Whizzby | Daleonfire | https://freesound.org/people/Daleonfire/sounds/505238/ | CC0 1.0 | bullet_whiz, bullet_whiz_3 |
| Real Bullet Flyby Sound | qubodup | https://freesound.org/people/qubodup/sounds/855248/ | CC0 1.0 | bullet_whiz, bullet_whiz_2, bullet_whiz_3, bullet_whiz_4 |
| Fly-by whiz SFX (subsonic) | modusmogulus | https://freesound.org/people/modusmogulus/sounds/789222/ | CC0 1.0 | bullet_whiz_2, bullet_whiz_4 |
| water_splash_10shots.wav | vibe_crc | https://freesound.org/people/vibe_crc/sounds/50623/ | CC0 1.0 | impacts/water, impacts/water_2, impacts/water_3, impacts/water_4, impacts/water_5 |
| Hiking Boot Footsteps on Stone | Fission9 | https://freesound.org/people/Fission9/sounds/521590/ | CC0 1.0 | footsteps/concrete_6, footsteps/concrete_7, footsteps/concrete_8 |
| Footsteps on slush | xkeril | https://freesound.org/people/xkeril/sounds/611278/ | CC0 1.0 | footsteps/snow_6, footsteps/snow_7, footsteps/snow_8 |
| Footsteps_6_Dirt_shoe.wav | monte32 | https://freesound.org/people/monte32/sounds/353799/ | CC0 1.0 | footsteps/dirt, footsteps/dirt_2, footsteps/dirt_3, footsteps/dirt_4, footsteps/dirt_5, footsteps/dirt_6 |
| Footsteps_Mountain_Boots_Mud_Mono.wav | Nox_Sound | https://freesound.org/people/Nox_Sound/sounds/548384/ | CC0 1.0 | footsteps/dirt_7, footsteps/dirt_8, footsteps/mud, footsteps/mud_2, footsteps/mud_3, footsteps/mud_4, footsteps/mud_5, footsteps/mud_6, footsteps/mud_7, footsteps/mud_8 |
| Walking on metal | Sanderboah | https://freesound.org/people/Sanderboah/sounds/696374/ | CC0 1.0 | footsteps/metal, footsteps/metal_2, footsteps/metal_3, footsteps/metal_4, footsteps/metal_5, footsteps/metal_6 |
| Metal Steps | Phil25 | https://freesound.org/people/Phil25/sounds/208101/ | CC0 1.0 | footsteps/metal_7, footsteps/metal_8 |
| puddle footsteps.wav | patchytherat | https://freesound.org/people/patchytherat/sounds/531566/ | CC0 1.0 | footsteps/water, footsteps/water_2, footsteps/water_3, footsteps/water_4, footsteps/water_5 |
| puddlewalk.wav | j1987 | https://freesound.org/people/j1987/sounds/106395/ | CC0 1.0 | footsteps/water_6, footsteps/water_7, footsteps/water_8 |
| foley cloth rustle.wav | martian | https://freesound.org/people/martian/sounds/19291/ | CC0 1.0 | foley/gear, foley/gear_2, foley/gear_3, foley/gear_4 |
| Clothes Rustling 1 | WasabiWielder | https://freesound.org/people/WasabiWielder/sounds/334219/ | CC0 1.0 | foley/gear_5, foley/gear_6 |
| Cloth_1(rustle, fabric, clothes).WAV | o_ciz | https://freesound.org/people/o_ciz/sounds/475440/ | CC0 1.0 | foley/gear_7, foley/gear_8 |
| Jump Landing.wav | Shamewap | https://freesound.org/people/Shamewap/sounds/389678/ | CC0 1.0 | foley/land, foley/land_2, foley/land_3, foley/land_4 |
| BODY FALL - V HVY - DIRT | leonelmail | https://freesound.org/people/leonelmail/sounds/504626/ | CC0 1.0 | foley/land_5 |
| Heart Beating | michorvath | https://freesound.org/people/michorvath/sounds/273150/ | CC0 1.0 | foley/heartbeat, foley/heartbeat_2, foley/heartbeat_3, foley/heartbeat_4 |
| Explosion with debris - authentic. 4kg TNT | sidohzen | https://freesound.org/people/sidohzen/sounds/165808/ | CC0 1.0 | explosion, explosions/debris_2 |
| Explosion and Rubble/Debris | deleted_user_1887925 | https://freesound.org/people/deleted_user_1887925/sounds/132929/ | CC0 1.0 | explosion_2, explosions/debris_4 |
| Explosion004.wav | klangfabrik | https://freesound.org/people/klangfabrik/sounds/220062/ | CC0 1.0 | explosion_3 |
| massive explosion | Hugofski | https://freesound.org/people/Hugofski/sounds/177556/ | CC0 1.0 | explosion_4 |
| Explosion_Debris_Short_Stereo.wav | Nox_Sound | https://freesound.org/people/Nox_Sound/sounds/560510/ | CC0 1.0 | explosions/debris, explosions/debris_3 |
| Muffled Distant Explosion | NenadSimic | https://freesound.org/people/NenadSimic/sounds/149966/ | CC0 1.0 | explosions/far |
| Distant Explosion | Mr_KeybOred | https://freesound.org/people/Mr_KeybOred/sounds/372086/ | CC0 1.0 | explosions/far_2 |
| Explosion Distant  | Johnnyfarmer | https://freesound.org/people/Johnnyfarmer/sounds/209769/ | CC0 1.0 | explosions/far_3 |
| distant explosions | Kostrava | https://freesound.org/people/Kostrava/sounds/320788/ | CC0 1.0 | explosions/far_4 |
| Wind__Artic__Cold.wav | cobratronik | https://freesound.org/people/cobratronik/sounds/117136/ | CC0 1.0 | amb_wind |
| Background shooting 120.wav | deleted_user_1371021 | https://freesound.org/people/deleted_user_1371021/sounds/113360/ | CC0 1.0 | amb_battle |
| 201110 Distant sirens, urban, night, quiet, roof 11pm.flac | TRP | https://freesound.org/people/TRP/sounds/568975/ | CC0 1.0 | amb_siren |
| Strong Wind | florianreichelt | https://freesound.org/people/florianreichelt/sounds/459981/ | CC0 1.0 | ambience/wind_strong |
| Downtown LA, Little Tokyo, late night semi distant traffic.wav | janbezouska | https://freesound.org/people/janbezouska/sounds/330427/ | CC0 1.0 | ambience/city_night |
| Night Woods | widgetstudios | https://freesound.org/people/widgetstudios/sounds/532301/ | CC0 1.0 | ambience/forest_night |
| Water Through Drain (With Reverb).wav | clif_creates | https://freesound.org/people/clif_creates/sounds/381418/ | CC0 1.0 | ambience/drain |
| Ambiance_Atmosphere_Cave_Loop_Stereo.ogg | Nox_Sound | https://freesound.org/people/Nox_Sound/sounds/553080/ | CC0 1.0 | ambience/cave |
| room tone large room church basement heavy deep ventilation or furnace hum.flac | kyles | https://freesound.org/people/kyles/sounds/451924/ | CC0 1.0 | ambience/room_tone |
| room tone, big hall, heavy ventilation hum, extremely sparse people.wav | be_a_hero_not_a_patriot | https://freesound.org/people/be_a_hero_not_a_patriot/sounds/509477/ | CC0 1.0 | ambience/hall_tone |
| 070916 Machine room transformer hum 1.wav | thaighaudio | https://freesound.org/people/thaighaudio/sounds/349688/ | CC0 1.0 | ambience/machine_hum |
| S20-02 Rifle ricochets.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/675955/ | CC0 1.0 | ricochet_3, ricochet_4 |
| UH-1 helicopter.wav | Rmutt | https://freesound.org/people/Rmutt/sounds/156906/ | CC0 1.0 | veh_heli_rotor |
| Riding Train interior recording | gecop | https://freesound.org/people/gecop/sounds/525058/ | CC0 1.0 | nachtzug_rail_loop |
| Kenney Impact Sounds | Kenney (kenney.nl) | https://kenney.nl/assets/impact-sounds | CC0 1.0 | footsteps/carpet, footsteps/carpet_2, footsteps/carpet_3, footsteps/carpet_4, footsteps/carpet_5, footsteps/concrete, footsteps/concrete_2, footsteps/concrete_3, footsteps/concrete_4, footsteps/concrete_5, footsteps/grass, footsteps/grass_2, footsteps/grass_3, footsteps/grass_4, footsteps/grass_5, footsteps/snow, footsteps/snow_2, footsteps/snow_3, footsteps/snow_4, footsteps/snow_5, footsteps/wood, footsteps/wood_2, footsteps/wood_3, footsteps/wood_4, footsteps/wood_5, impacts/concrete, impacts/concrete_2, impacts/concrete_3, impacts/concrete_4, impacts/concrete_5, impacts/concrete_6, impacts/flesh, impacts/flesh_2, impacts/flesh_3, impacts/flesh_4, impacts/flesh_5, impacts/glass, impacts/glass_2, impacts/glass_3, impacts/glass_4, impacts/wood, impacts/wood_2, impacts/wood_3, impacts/wood_4, impacts/wood_5 |
| Kenney Interface Sounds | Kenney (kenney.nl) | https://kenney.nl/assets/interface-sounds | CC0 1.0 | ui/back, ui/click, ui/click_2, ui/click_3, ui/hover, ui/hover_2, ui/toggle, ui/toggle_2 |
| Tinnitus-Ton (numpy) | selbst erzeugt | – | CC0 | foley/tinnitus, foley/tinnitus_2 |

### Nachtrag: Sound-Runde 2 (Fahrzeuge, Panzerfaust, Granate, Gunship, 17.11.)

Alle CC0 1.0 (Freesound). Schleifen nahtlos geschnitten; `gunship_impact105/40` sind gefilterte Fassungen von `explosions/far`/`far_3` (Quellen oben). `veh_tank_turret` = Servo-Abschnitte, 0,55-fach tiefer.

| Titel | Autor | Quelle | Lizenz | Dateien |
|---|---|---|---|---|
| foley cloth rustle.wav | martian | https://freesound.org/people/martian/sounds/19291/ | CC0 1.0 | launcher_mag_out |
| Metal Cup Drop | AlecCorday | https://freesound.org/people/AlecCorday/sounds/181115/ | CC0 1.0 | grenade_bounce_2, grenade_bounce_soft_2 |
| small metal object fall  | nicktermer | https://freesound.org/people/nicktermer/sounds/259553/ | CC0 1.0 | grenade_bounce, grenade_bounce_soft |
| MetalDrop.wav | nickronk123 | https://freesound.org/people/nickronk123/sounds/489767/ | CC0 1.0 | grenade_bounce_3 |
| ThrowGrenadeCloth.ogg | Avreliy | https://freesound.org/people/Avreliy/sounds/611613/ | CC0 1.0 | grenade_throw, grenade_throw_2 |
| Grenade with Pin Handling | loganzsound | https://freesound.org/people/loganzsound/sounds/876008/ | CC0 1.0 | grenade_throw, grenade_throw_2 |
| Excalibur Howitzer Shot | qubodup | https://freesound.org/people/qubodup/sounds/175430/ | CC0 1.0 | gunship_gun105 |
| Artillery Shots.flac | qubodup | https://freesound.org/people/qubodup/sounds/182822/ | CC0 1.0 | gunship_gun105 |
| Cannon Shot | qubodup | https://freesound.org/people/qubodup/sounds/187767/ | CC0 1.0 | gunship_gun40 |
| Airplane inside ambient- cessna 414. condenser .mp3 | Daveshu88 | https://freesound.org/people/Daveshu88/sounds/325845/ | CC0 1.0 | gunship_engine |
| Lockheed Electra turboprop flyover | HootOwl | https://freesound.org/people/HootOwl/sounds/464893/ | CC0 1.0 | gunship_engine |
| Radio Noise.wav | RutgerMuller | https://freesound.org/people/RutgerMuller/sounds/50750/ | CC0 1.0 | gunship_radio |
| Autocannon Three Shot Burst | qubodup | https://freesound.org/people/qubodup/sounds/854186/ | CC0 1.0 | gunship_gatling, gunship_gun40 |
| rpg launcher  three shots.wav | klangfabrik | https://freesound.org/people/klangfabrik/sounds/249298/ | CC0 1.0 | weapons/pzf_backblast, weapons/pzf_backblast_2 |
| Metallic latch release.wav | Crinkem | https://freesound.org/people/Crinkem/sounds/481789/ | CC0 1.0 | launcher_bolt |
| Rocket Launch Boost and Burning (Version A) | TheLittleCrow | https://freesound.org/people/TheLittleCrow/sounds/774245/ | CC0 1.0 | rocket_fly |
| Rocket Launch | qubodup | https://freesound.org/people/qubodup/sounds/840511/ | CC0 1.0 | rocket_fly |
| Mechanical1.wav | BMacZero | https://freesound.org/people/BMacZero/sounds/94120/ | CC0 1.0 | launcher_bolt |
| Clank1.wav | BMacZero | https://freesound.org/people/BMacZero/sounds/94127/ | CC0 1.0 | gunship_gun105, launcher_mag_in |
| LightClunk1.wav | BMacZero | https://freesound.org/people/BMacZero/sounds/94129/ | CC0 1.0 | launcher_mag_out |
| LightClunk2.wav | BMacZero | https://freesound.org/people/BMacZero/sounds/94130/ | CC0 1.0 | launcher_mag_in |
| Thud2.wav | BMacZero | https://freesound.org/people/BMacZero/sounds/96137/ | CC0 1.0 | grenade_bounce, grenade_bounce_2, grenade_bounce_3, grenade_bounce_soft, grenade_bounce_soft_2, launcher_mag_out |
| tracked vehicle.wav | cognito perceptu | https://freesound.org/people/cognito%20perceptu/sounds/121531/ | CC0 1.0 | veh_tank_tracks_2 |
| Servo motor | Burningmonkey | https://freesound.org/people/Burningmonkey/sounds/322021/ | CC0 1.0 | veh_tank_turret |
| Military Vehicle Humming.flac | qubodup | https://freesound.org/people/qubodup/sounds/182793/ | CC0 1.0 | veh_tank_engine |
| t26_moving_01.wav | greatmganga | https://freesound.org/people/greatmganga/sounds/329800/ | CC0 1.0 | veh_tank_tracks |
| Helicopter interior, no rotor | schots | https://freesound.org/people/schots/sounds/265568/ | CC0 1.0 | veh_heli_turbine |
| River boat with outboard engine (at a constant speed) | nomadas | https://freesound.org/people/nomadas/sounds/690161/ | CC0 1.0 | hafen_boat_engine |
| Prop Plane | Mozfoo | https://freesound.org/people/Mozfoo/sounds/440163/ | CC0 1.0 | veh_prop_plane |
| Truck Engine Idle Loops.flac | qubodup | https://freesound.org/people/qubodup/sounds/187564/ | CC0 1.0 | veh_truck_engine |
| Jet Plane Flyby.flac | qubodup | https://freesound.org/people/qubodup/sounds/189446/ | CC0 1.0 | veh_jet_loop |
| intense and very intimate breathing after sport | florianreichelt | https://freesound.org/people/florianreichelt/sounds/434828/ | CC0 1.0 | player/exert_breath_in(_2.._6), player/exert_breath_out(_2.._6) – Sprint-Ausdauer-Keuchen, einzelne Atemzuege geschnitten (HP 110 Hz, Blenden 12/90 ms) |


## Fahrzeugwracks v0.6 (Sketchfab, CC-BY 4.0)

Ausgebrannte Fahrzeuge fuer `LevelProps.vehicle(..., burnt = true)` ueber `game/vehicles/models/wreck_scans.gd`
(Fallback: prozedurales `WreckModel`). Texturen auf 1K (Lkw 2K) verkleinert; beim Lkw wurde das mitgescannte
Bodenstueck (Dreiecke < 0,3 m ueber Grund) aus dem Index-Puffer entfernt.

| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/vehicles/wrecks/burned_cars/` | "Burned-out Cars", https://sketchfab.com/3d-models/burned-out-cars-701066df6b914fd08318524c7ccd96a7 | Renafox (https://sketchfab.com/kryik1023) | CC-BY 4.0 | Pkw-Wracks (2 Varianten, auch auf dem Dach), ca. 11 MB |
| `assets/vehicles/wrecks/bus/` | "destroyed Bus 01", https://sketchfab.com/3d-models/destroyed-bus-01-fdf39ca893a64368af45f82a6b6d68a4 | o0ozexo0o (https://sketchfab.com/dadndan0091) | CC-BY 4.0 | Bus-Wracks, ca. 27 MB |
| `assets/vehicles/wrecks/van/` | "Destroyed car Van", https://sketchfab.com/3d-models/destroyed-car-van-ef5b7d68f03845a1bf810129053de91e | sehjadm64 (https://sketchfab.com/sehjadm64) | CC-BY 4.0 | Transporter-Wracks |
| `assets/vehicles/wrecks/truck/` | "Burnt Truck", https://sketchfab.com/3d-models/burnt-truck-bb538b4a384d4a71a39b4eb49be0039d | Digitage (https://sketchfab.com/digitage) | CC-BY 4.0 | Lkw-Wracks (Fotogrammetrie einer ausgebrannten Zugmaschine) |

## Optik Runde 2 v0.6 (17.11.)

### Innenraum-Kleinkram (Poly Haven, CC0)
Verteilt ueber `game/levels/interior_clutter.gd` (Bunker, Kanzleramt, Funkturm, Curfew, Kanalisation, Villa), 1K-glTF, zusammen ca. 33 MB.

| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/interior/models/cardboard_box_01/` | https://polyhaven.com/a/cardboard_box_01 | Rahul Chaudhary | CC0 | Kartons (Villa: Umzugskartons, Wohnungen, Bunker), 2,2 MB |
| `assets/environment/interior/models/metal_jerrycan_green/` | https://polyhaven.com/a/metal_jerrycan_green | Ulan Cabanilla | CC0 | Kanister Bunker/Kanalisation, 2,6 MB |
| `assets/environment/interior/models/metal_stool_01/` | https://polyhaven.com/a/metal_stool_01 | Ulan Cabanilla | CC0 | Hocker Bunker/Funkturm, 2,3 MB |
| `assets/environment/interior/models/metal_trash_can/` | https://polyhaven.com/a/metal_trash_can | GurJas Studios | CC0 | Muelleimer Buero/Wohnung, 4,9 MB |
| `assets/environment/interior/models/modern_arm_chair_01/` | https://polyhaven.com/a/modern_arm_chair_01 | Vibrant Nordic | CC0 | Sessel Kanzleramt, 2,7 MB |
| `assets/environment/interior/models/modular_electric_cables/` | https://polyhaven.com/a/modular_electric_cables | Kuutti Siitonen | CC0 | Kabelrollen Funkturm/Bunker, 5,9 MB |
| `assets/environment/interior/models/plastic_crate_02/` | https://polyhaven.com/a/plastic_crate_02 | Fabi_G | CC0 | Kunststoffkisten, 1,8 MB |
| `assets/environment/interior/models/plastic_jerrycan/` | https://polyhaven.com/a/plastic_jerrycan | Ulan Cabanilla | CC0 | Kanister (Kunststoff), 2,5 MB |
| `assets/environment/interior/models/plastic_monobloc_chair_01/` | https://polyhaven.com/a/plastic_monobloc_chair_01 | Kuutti Siitonen | CC0 | Gartenstuehle Wohnungen/Kanalisation, 1,9 MB |
| `assets/environment/interior/models/power_box_01/` | https://polyhaven.com/a/power_box_01 | Rico Cilliers (Modell/Textur), Yann Kervran (Rigging) | CC0 | Verteilerkaesten Funkturm/Bunker, 2,7 MB |
| `assets/environment/interior/models/trashbag/` | https://polyhaven.com/a/trashbag | Benny Weimer | CC0 | Muellsaecke Wohnungen/Kanalisation, 1,7 MB |
| `assets/environment/interior/models/wall_clock/` | https://polyhaven.com/a/wall_clock | PierreB3D | CC0 | Wanduhren Buero/Bunker/Villa, 1,6 MB |

### Vegetation Villa und intakte Fahrzeuge (Sketchfab, CC-BY 4.0)
Mit `tools/prune_gltf.py` ausgeduennt (nur benutzte Knoten, Texturen 1K, Billboards 512). Fallback jeweils die
bisherige prozedurale Version (`game/levels/sf_vegetation.gd`, `game/vehicles/models/wreck_scans.gd`).

| Datei(en) | Quelle | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/vegetation/oak/` | "Oak trees pack (17var, LODs, seasons, gameready)", https://sketchfab.com/3d-models/oak-trees-pack-17var-lods-seasons-gameready-a5e4e64f9f1d4089bdcc6170a9333393 | LOLIPOP (https://sketchfab.com/lolipop_1707) | CC-BY 4.0 | Laubbaeume Villa-Garten (LOD0), Eichenwald am Ostufer/Suedhang und Waldrand (LOD-Stufen als MultiMesh), 8,4 MB |
| `assets/environment/vegetation/hedge/` | "Shrub tiles pack (3 vars, seamless)", https://sketchfab.com/3d-models/shrub-tiles-pack-3-vars-seamless-ce2fce219f634f328abc6280b2409613 | LOLIPOP (https://sketchfab.com/lolipop_1707) | CC-BY 4.0 | Buchsbaumhecken Villa (Bloecke segmentweise gestreckt), 6,9 MB |
| `assets/vehicles/intact/golf5/` | "vw golf 5 gti", https://sketchfab.com/3d-models/vw-golf-5-gti-4389c32f54964b5ab01aa8462419b6c1 | giuffridanicolo54 (https://sketchfab.com/giuffridanicolo54) | CC-BY 4.0 | intakte Pkw (`LevelProps.vehicle`, jeder zweite unverbrannte Pkw; Rest bleibt abgedeckt), 10,1 MB |
| `assets/vehicles/intact/sprinter/` | "Mercedes Benz Sprinter 2006", https://sketchfab.com/3d-models/mercedes-benz-sprinter-2006-f69de1315bb049c8946d57f6006acd73 | Max (https://sketchfab.com/Max-5532) | CC-BY 4.0 | intakte Transporter; der Autor bittet auf der Modellseite um eine kurze Nachricht bei Verwendung, 3,6 MB |
| `assets/vehicles/intact/lct3000/` | "LCT 3000 '95 - Low poly model", https://sketchfab.com/3d-models/lct-3000-95-low-poly-model-663a0953c038434a918cb85725c88ffa | Daniel Zhabotinsky (https://sketchfab.com/DanielZhabotinsky) | CC-BY 4.0 | intakte Lkw (Aufbau in Levelfarbe umlackiert), 4,4 MB |

## Optik Runde 3 v0.6 (17.11.)

Poly Haven (https://polyhaven.com), CC0, je 1K-JPG (diffuse/normal/arm), geladen mit `tools/fetch_optik3_assets.py`.

| Pfad | Asset | Autor | Lizenz | Verwendung |
|---|---|---|---|---|
| `assets/environment/textures/old_stone_wall/` | "Old Stone Wall", https://polyhaven.com/a/old_stone_wall | Charlotte Baglioni | CC0 | Villa-Grundstuecksmauern und Torpfeiler (statt Schotter-Textur), 2,6 MB |
| `assets/environment/textures/blue_metal_plate/` | "Blue Metal Plate", https://polyhaven.com/a/blue_metal_plate | Rob Tuytel | CC0 | Hafen-Containerbruecken (STS-Kraene), 1,1 MB |

Wiederverwendete Projekttexturen (bereits oben nachgewiesen): `bunker/textures/painted_steel` (Hafen-Kranhaus, Funkturm-Attika,
Alpenpass-Seilbahnkabine, Kanalisation-Warnlack), `river/textures/brown_mud_02` (Kanalisation Schlammrinnen und Abwasser-Shader),
`river/textures/green_metal_rust` + `textures/weathered_planks` (Kanalisation-Kisten), `assets/textures/rusty_metal_02` (Kanalisation-Regale),
`villa/rough_wood` + `train/textures/quatrefoil_jacquard_fabric` (Villa-Bootshaus, Teppich), `assets/textures/concrete_wall_008` (Spreebogen-Decken).
