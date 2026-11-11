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
