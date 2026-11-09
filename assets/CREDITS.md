# Asset-Quellen und Lizenzen

Alle fremden Assets stammen von Poly Haven und stehen unter **CC0 1.0 (Public Domain)**.
Es wurden nur Bilddateien heruntergeladen (keine Skripte ausgefuehrt).

| Datei(en) | Quelle | Lizenz |
|---|---|---|
| `assets/hdri/kloppenheim_01_puresky_2k.hdr` | https://polyhaven.com/a/kloppenheim_01_puresky (Greg Zaal) | CC0 |
| `assets/textures/asphalt_02/{diffuse,normal,arm}.jpg` | https://polyhaven.com/a/asphalt_02 | CC0 |
| `assets/textures/concrete_wall_008/{diffuse,normal,arm}.jpg` | https://polyhaven.com/a/concrete_wall_008 | CC0 |
| `assets/textures/brick_wall_02/{diffuse,normal,arm}.jpg` | https://polyhaven.com/a/brick_wall_02 | CC0 |
| `assets/textures/rusty_metal_02/{diffuse,normal,arm}.jpg` | https://polyhaven.com/a/rusty_metal_02 | CC0 |

`arm` = Ambient Occlusion (R), Roughness (G), Metallic (B), 1k-Aufloesung als JPG.

## Selbst erzeugt (Public Domain / CC0)

| Datei | Erzeugung |
|---|---|
| `assets/vfx/noise_tile.png` | Prozedural (FastNoiseLite, kachelbar), Skript `assets/vfx/gen_textures.gd` |
| `assets/vfx/burn_mark.png` | Prozedural (Brandfleck-Decal), `gen_textures.gd` |
| `assets/vfx/bullet_hole.png` | Prozedural (Einschussloch-Decal), `gen_textures.gd` |

Alle Shader (`game/vfx/shaders/*.gdshader`), Partikel- und Level-Geometrie entstehen im Code, ohne externe Modelle.

## Spieler & Waffen (Viewmodel, Optik, Sounds)

### Modelle

| Datei | Quelle | Lizenz | Bearbeitung |
|---|---|---|---|
| `assets/weapons/m4a1/m4a1.fbx`, `albedo.png`, `normal.png`, `roughness.png`, `metallic.png` | "M4A1 Assault Rifle" von nisu, https://opengameart.org/content/m4a1-assault-rifle (Datei `m4a1_0.zip`, urspr. 3dmodelscc0.com) | CC0 | Texturen von Palette-PNG nach RGB/Graustufen konvertiert, Import-Einstellungen (VRAM, Mipmaps, Normal-Map); Klappkimme im Spiel ausgeblendet |

Red-Dot-Visier (Geometrie in `game/weapons/weapon.gd`, Shader `game/weapons/red_dot.gdshader`) und ADS-Rand-Shader (`game/ui/hud.gd`) sind selbst erstellt (CC0).

### Sounds (`assets/sfx/`)

| Datei | Quelle | Lizenz | Bearbeitung |
|---|---|---|---|
| rifle_fire.ogg, rifle_fire_2.ogg | https://opengameart.org/content/the-free-firearm-sound-library – The Free Firearm Sound Library (Ben Jaszczak, Brian Nelson, Kevin Heras, Matthew Nanney; hochgeladen von bart), AR-15 D_32P + D_24P | CC0 | Einzelschüsse geschnitten, Nah-/Mittel-Mikro geschichtet, komprimiert, Mono, normalisiert, Fade-out, OGG |
| rifle_fire_3.ogg, rifle_fire_4.ogg | wie oben, AK-47 C_28P + C_31P | CC0 | wie oben |
| pistol_fire.ogg, _2, _3 | wie oben, Walther PPQ X_39P + X_31P | CC0 | geschnitten, geschichtet (_3 nur Nah-Mikro), komprimiert, normalisiert, OGG |
| rifle_reload.ogg | https://opengameart.org/content/gun-reload-sounds – springyspringo (assaultriflereload1.wav) | CC0 | Pause auf ca. 2,0 s verlängert, Mono, normalisiert, OGG |
| pistol_reload.ogg | https://opengameart.org/content/handgun-reload-sound-effect – zer0sol (reload.wav) | CC0 | getrimmt, Mono, normalisiert, OGG |
| footstep.ogg … footstep_5.ogg | https://opengameart.org/content/fantozzis-footsteps-grasssand-stone – Fantozzi (geschnitten von qubodup), Stone L1/L2/L3/R1/R2 | CC0 | getrimmt, Hochpass, normalisiert, OGG |
| land.ogg | Fantozzi Stone R3 (wie oben) + https://opengameart.org/content/50-rpg-sound-effects – Kenney (dropLeather) | CC0 | gemischt, normalisiert, OGG |
| jump.ogg, weapon_switch.ogg, dry_fire.ogg | https://opengameart.org/content/50-rpg-sound-effects – Kenney: clothBelt2; cloth2 + metalLatch; metalClick | CC0 | geschnitten/gemischt, normalisiert, OGG |
| hitmarker.ogg, hitmarker_kill.ogg | https://opengameart.org/content/interface-sounds – Kenney: tick_001, tick_004 | CC0 | getrimmt, Pegel angepasst, OGG |
| headshot.ogg | https://opengameart.org/content/metal-impact-sounds – Brian MacIntosh (bmaczero), bing1.wav | CC0 | Hochpass, gekürzt, Fade-out, normalisiert, OGG |
| grenade_bounce.ogg, _2, _3 | wie oben, clink2/clink3/clink1 | CC0 | getrimmt, normalisiert, OGG |
| player_hurt.ogg, player_hurt_2.ogg | https://opengameart.org/content/pain-sounds-by-emopreben – Lasse Bührmann (Emopreben), "Hurgh", "Urggh" | CC0 | getrimmt, normalisiert, OGG |
| player_death.ogg | wie oben, "Huuurh" + Kenney dropLeather | CC0 | gemischt, normalisiert, OGG |
| grenade_throw.ogg | Kenney metalLatch + https://opengameart.org/content/swishes-sound-pack – artisticdude (swish-9) | CC0 | gemischt, normalisiert, OGG |

## Level „Nacht an der Grenze“ (baltic_night) – Umgebungstexturen

| Datei(en) | Quelle | Lizenz | Bearbeitung |
|---|---|---|---|
| environment/textures/snow_02/* | https://polyhaven.com/a/snow_02 – Poly Haven | CC0 | 1k JPG (diffuse, normal GL, ARM), unverändert |
| environment/textures/pine_bark/* | https://polyhaven.com/a/pine_bark – Poly Haven | CC0 | 1k JPG (diffuse, normal GL, ARM), unverändert |
| environment/textures/weathered_planks/* | https://polyhaven.com/a/weathered_planks – Poly Haven | CC0 | 1k JPG (diffuse, normal GL, ARM), unverändert |
| environment/textures/gravel/* | https://polyhaven.com/a/gravel – Poly Haven | CC0 | 1k JPG (diffuse, normal GL, ARM), unverändert |
| environment/snowy.gdshader | selbst geschrieben | CC0 | Triplanar-Schneeüberblendung |

## Gegner-Modelle und Animationen (characters/)

| Datei(en) | Quelle | Lizenz | Bearbeitung |
|---|---|---|---|
| characters/soldier/swat.glb | https://poly.pizza/m/Btfn3G5Xv4 – Quaternius, "SWAT" | CC0 | unverändert; Materialien zur Laufzeit umgefärbt (dunkelgrau/oliv, rote Armbinde) |
| characters/anim_src/ual_standard.glb (+ UAL_License.txt) | https://opengameart.org/content/universal-animation-library – Quaternius, Universal Animation Library (Standard) | CC0 | Clips auf das SWAT-Rig retargetet, gebacken in characters/soldier/soldier_rig.scn |
| characters/weapons/rifle_ar_west.glb | https://poly.pizza/m/ss1nz3gJnx – Pichuliru, "Assault Rifle West" | CC0 | unverändert, skaliert |
| characters/weapons/rifle_ar_quaternius.glb | https://poly.pizza/m/Bgvuu4CUMV – Quaternius, "Assault Rifle" | CC0 | als MG-Basis skaliert, Anbauteile prozedural |
| characters/soldier/soldier_rig.scn | selbst erstellt (tools/bake_soldier.gd) aus den obigen Dateien | CC0 | – |
| Drohne, Ausrüstung, Panzerung, Ragdoll | prozedural im Code (game/enemies/) | CC0 | – |

## Welt-Sounds & Rauch (VFX-Agent)

Alle Quellen: OpenGameArt.org, Lizenz **CC0 1.0**, ohne Login heruntergeladen (nur Audiodateien/Archive, keine Skripte ausgefuehrt).
Bearbeitung mit eigenem Python/ffmpeg-Skript (geschnitten, gemischt, gefiltert, normalisiert, Mono, OGG Vorbis).
Synthetische Anteile (Druckstoss, Rauschen, Querschlaeger-Ton, Vorbeiflug) sind selbst erzeugt (CC0).

| Datei(en) in `assets/sfx/` | Quelle(n) | Lizenz |
|---|---|---|
| enemy_rifle.ogg | The Free Firearm Sound Library (https://opengameart.org/content/the-free-firearm-sound-library), AK-47 C_36P | CC0 |
| enemy_mg.ogg | wie oben, PPSh P_22P + AK-47 C_34P, geschichtet, tiefer gepitcht | CC0 |
| enemy_hurt.ogg, enemy_death.ogg, enemy_alert.ogg | "Grunts: Male Death and Pain" von thebardofblasphemy, https://opengameart.org/content/grunts-male-death-and-pain | CC0 |
| drone_beep.ogg, drone_dive.ogg | "50 CC0 Sci-Fi SFX" von rubberduck, https://opengameart.org/content/50-cc0-sci-fi-sfx (beep_01, rocket_01) | CC0 |
| drone_hit.ogg | "75 CC0 breaking/falling/hit SFX" von rubberduck, https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx (metal_hit_02) + "Metal Impact Sounds" von Brian MacIntosh, https://opengameart.org/content/metal-impact-sounds (clink1) | CC0 |
| drone_explode.ogg | 50 CC0 Sci-Fi SFX (explosion_02) + "100 CC0 SFX" von rubberduck, https://opengameart.org/content/100-cc0-sfx (explosion) + 75 CC0 breaking/falling (metal_falling_02) | CC0 |
| explosion.ogg, explosion_2..4.ogg | "Dull explosion" von qubodup (https://opengameart.org/content/dull-explosion), "Chunky Explosion" von Joth (https://opengameart.org/content/chunky-explosion), "Explosion" von tinyworlds (https://opengameart.org/content/explosion-0), 100 CC0 SFX (explosion), "Low Rumbling" von musheran (https://opengameart.org/content/low-rumbling), Truemmer aus 75 CC0 breaking/falling; + synthetischer Druckstoss | CC0 |
| impact_concrete.ogg, _2, _3 | 75 CC0 breaking/falling (rock_hit_01, hit_05, hit_08, rock_falling_*) + synthetischer Knack | CC0 |
| impact_metal.ogg, _2, _3 | 75 CC0 breaking/falling (metal_hit_01/03/05) + synthetischer Knack | CC0 |
| ricochet.ogg, ricochet_2.ogg | Metal Impact Sounds (clink1, bing1) + selbst synthetisierter Querschlaeger-Ton | CC0 |
| bullet_whiz.ogg, _2, _3 | komplett selbst synthetisiert (gefiltertes Rauschen mit Doppler-Abfall) | CC0 |
| amb_wind.ogg | "Mild wind background noise" von bashar3a, https://opengameart.org/content/mild-wind-background-noise (Loop per Crossfade) | CC0 |
| amb_battle.ogg | Collage aus The Free Firearm Sound Library (AK-47, PPSh) + Explosion (tinyworlds), Tiefpass + Hall, nahtloser 48-s-Loop | CC0 |
| amb_siren.ogg | "Storm Siren" von tinyworlds, https://opengameart.org/content/storm-siren (30 s, Tiefpass, Fades) | CC0 |
| fire_crackle.ogg | "Fireplace Sound Loop" von pagdev, https://opengameart.org/content/fireplace-sound-loop (20-s-Loop) | CC0 |

| Datei | Erzeugung |
|---|---|
| `assets/vfx/smoke_flipbook.png` | Prozedural (8x8-Flipbook aus domain-gewarptem fBm-Noise), Skript `assets/vfx/gen_smoke.gd` (CC0) |

## Level 4 "Letzter Zug" (rail_yard)

Alle Assets von **Poly Haven** (https://polyhaven.com), Lizenz **CC0 1.0**, unveraendert (2K-Aufloesung), abgelegt unter `assets/environment/rail/`.

| Datei(en) | Poly-Haven-Asset | Lizenz |
|---|---|---|
| `hdri/industrial_sunset_02_puresky_2k.hdr` | https://polyhaven.com/a/industrial_sunset_02_puresky | CC0 |
| `textures/gravel_stones/` | https://polyhaven.com/a/gravel_stones | CC0 |
| `textures/gravel_road/` | https://polyhaven.com/a/gravel_road | CC0 |
| `textures/rusty_corrugated_iron/` | https://polyhaven.com/a/rusty_corrugated_iron | CC0 |
| `textures/rust_coarse_01/` | https://polyhaven.com/a/rust_coarse_01 | CC0 |
| `textures/rusty_painted_metal/` | https://polyhaven.com/a/rusty_painted_metal | CC0 |
| `textures/damaged_concrete_floor_02/` | https://polyhaven.com/a/damaged_concrete_floor_02 | CC0 |
| `textures/factory_wall/` | https://polyhaven.com/a/factory_wall | CC0 |
| `textures/worn_corrugated_iron/` | https://polyhaven.com/a/worn_corrugated_iron | CC0 |
| `textures/container_side/` | https://polyhaven.com/a/container_side | CC0 |
| `models/wooden_military_crate/` | https://polyhaven.com/a/wooden_military_crate | CC0 |
| `models/old_military_crate/` | https://polyhaven.com/a/old_military_crate | CC0 |
| `models/ammo_box/` | https://polyhaven.com/a/ammo_box | CC0 |
| `models/barrel_03/` | https://polyhaven.com/a/barrel_03 | CC0 |
| `models/concrete_road_barrier/` | https://polyhaven.com/a/concrete_road_barrier | CC0 |
| `models/metal_jerrycan_green/` | https://polyhaven.com/a/metal_jerrycan_green | CC0 |
| `models/old_tyre/` | https://polyhaven.com/a/old_tyre | CC0 |
| `models/shrub_02/` | https://polyhaven.com/a/shrub_02 | CC0 |
| `models/grass_medium_01/` | https://polyhaven.com/a/grass_medium_01 | CC0 |
| `models/overhead_crane/` | https://polyhaven.com/a/overhead_crane | CC0 |

| Datei in `assets/sfx/` | Erzeugung | Lizenz |
|---|---|---|
| rail_metal_creak.ogg, rail_metal_crash.ogg, rail_flare_launch.ogg | komplett selbst synthetisiert (Python + ffmpeg; Reibungs-Oszillator, inharmonische Teiltoene, gefiltertes Rauschen) | CC0 |

## Kampagnen-Intro (game/intro/)

| Datei / Inhalt | Quelle | Lizenz |
|---|---|---|
| Funksprüche `assets/sfx/intro_vo2..vo8.wav`, Stimmengewirr `intro_babble.wav` (zerhackt, rückwärts, unverständlich) | Offline erzeugt mit Piper TTS (https://github.com/rhasspy/piper, Release 2023.11.14-2, MIT) und der Stimme `de_DE-thorsten-high` bzw. `de_DE-thorsten_emotional-medium` für das Stimmengewirr (https://huggingface.co/rhasspy/piper-voices, Thorsten Müller, CC0). Funkfilter (Bandpass 300–3400 Hz, Verzerrung, Bitcrush, Rauschen, Klicks) mit `tools/piper/gen_intro_audio.py` | CC0 |
| `assets/sfx/intro_music_a/b.wav`, `intro_sting`, `intro_static`, `intro_radio_bed`, `intro_radio_click`, `intro_signal_lost`, `intro_beep`, `intro_tick`, `intro_advance`, `intro_whoosh` | Komplett selbst synthetisiert (numpy), `tools/piper/gen_intro_audio.py` | CC0 |
| Ländergrenzen und Seen der Lagekarte (`game/intro/map_data.gd`) | Natural Earth 1:50m Admin 0 Countries + Lakes (https://www.naturalearthdata.com), vereinfacht mit `tools/piper/gen_map_data.py` | Public Domain |
| Sender „EU24 Nachrichten“, Logos, Schlagzeilen, Einheitszeichen | Frei erfunden, keine realen Sender, Personen oder Embleme | CC0 |

## Level 5 „Das letzte Reich“ (berlin) und Story-System

| Datei in `assets/environment/berlin/` | Quelle | Lizenz |
|---|---|---|
| `textures/granite_tile/` | https://polyhaven.com/a/granite_tile | CC0 |
| `textures/large_sandstone_blocks/` | https://polyhaven.com/a/large_sandstone_blocks | CC0 |
| `textures/concrete_tile_facade/` | https://polyhaven.com/a/concrete_tile_facade | CC0 |
| `textures/clean_asphalt/` | https://polyhaven.com/a/clean_asphalt | CC0 |
| `textures/metal_plate/` | https://polyhaven.com/a/metal_plate | CC0 |
| `textures/marble_01/` | https://polyhaven.com/a/marble_01 | CC0 |
| `emblem.png`, `emblem_mask.png`, `eu_flag.png`, `assets/characters/faction/reich_armband.png` | Selbst erzeugt (`gen_textures.py`). Das Emblem der fiktiven „Ordnungsfront“ (gebrochener Ring + senkrechte Klinge) ist frei erfunden und hat keinen Bezug zu realen Symbolen | CC0 |

| Datei in `assets/sfx/` | Erzeugung | Lizenz |
|---|---|---|
| `berlin_crowd`, `berlin_speech`, `berlin_firework_launch`, `berlin_firework_burst`, `berlin_screen_buzz`, `berlin_glass`, `berlin_pa_feedback`, `story_radio_on`, `story_radio_off`, `story_type`, `story_drone` | Komplett selbst synthetisiert (`assets/environment/berlin/gen_sfx.py`, numpy + ffmpeg). Die „Rede“ ist unverständliches, synthetisches Gemurmel | CC0 |
| Figuren, Parolen, Funksprüche, Durchsagen | Frei erfunden, keine realen Personen, Parteien oder Organisationen | CC0 |

## Fahrzeuge & Wetter (Runde 3)

| Datei / Ordner | Quelle / Erzeugung | Lizenz |
|---|---|---|
| Modelle Hubschrauber, Panzer, Jet, Sprengladung (`game/vehicles/models/`, `game/vehicles/*.gd`) | Prozedural im Code erzeugt (Primitive Meshes + Shader), keine externen Assets | CC0 |
| `assets/sfx/veh_heli_rotor`, `veh_heli_turbine`, `veh_heli_gun_spin`, `veh_tank_engine`, `veh_tank_tracks`, `veh_tank_turret`, `veh_tank_warn`, `veh_jet_loop`, `veh_jet_boom`, `veh_bomb_whistle`, `veh_charge_beep`, `veh_charge_plant`, `wx_rain`, `wx_thunder`, `wx_thunder_close` | Selbst synthetisiert (`assets/vehicles/gen_sfx_vehicles.py`, numpy/scipy + ffmpeg) | CC0 |
| `assets/sfx/veh_heli_gun`, `veh_heli_crash`, `veh_tank_cannon`, `veh_tank_explode`, `veh_metal_crash` | Synthese, geschichtet mit den vorhandenen Projekt-Sounds `enemy_mg.ogg`, `explosion*.ogg`, `impact_metal*.ogg`. Deren Quellen stehen oben (OpenGameArt CC0: Free Firearm Sound Library, qubodup, Joth, tinyworlds, rubberduck „100 CC0 SFX“, musheran, „75 CC0 breaking/falling“) | CC0 |

## Level 3 „Die Brücke“ (river_crossing)

| Datei in `assets/environment/river/` | Quelle | Lizenz |
|---|---|---|
| `overcast_soil_puresky_2k.hdr` | https://polyhaven.com/a/overcast_soil_puresky | CC0 |
| `textures/road_damaged/` | https://polyhaven.com/a/road_damaged | CC0 |
| `textures/green_metal_rust/` | https://polyhaven.com/a/green_metal_rust | CC0 |
| `textures/rough_concrete/` | https://polyhaven.com/a/rough_concrete | CC0 |
| `textures/brown_mud_02/` | https://polyhaven.com/a/brown_mud_02 | CC0 |
| `textures/factory_brick/` | https://polyhaven.com/a/factory_brick | CC0 |
| `textures/rusty_corrugated_iron/` | https://polyhaven.com/a/rusty_corrugated_iron | CC0 |
| `textures/river_small_rocks/` | https://polyhaven.com/a/river_small_rocks | CC0 |
| `textures/worn_plaster_wall/` | https://polyhaven.com/a/worn_plaster_wall | CC0 |
| `textures/withered_grass/` | https://polyhaven.com/a/withered_grass | CC0 |
| `models/Barrel_01`, `boulder_01`, `cement_bag`, `concrete_road_barrier`, `dead_tree_trunk`, `metal_jerrycan_green`, `old_tyre`, `rock_moss_set_01`, `street_lamp_02`, `trashbag`, `utility_box_01`, `wooden_military_crate` | https://polyhaven.com/a/<Ordnername> (Poly Haven Models) | CC0 |
| `water.gdshader`, `wet.gdshader` | Selbst geschrieben | CC0 |

| Datei in `assets/sfx/` | Quelle / Bearbeitung | Lizenz |
|---|---|---|
| `river_flow` | randommind/snabisch, „Sea and river wave sounds“ (Vistula), https://opengameart.org/content/sea-and-river-wave-sounds – 40-s-Ausschnitt, Crossfade-Loop | CC0 |
| `river_rain` | kresiek-the-furry, „AMB Rain Loop 1“, https://opengameart.org/content/amb-rain-loop-1 – Loop | CC0 |
| `river_rain_metal` | ylmir/snabisch, „Rain (loopable)“, https://opengameart.org/content/rain-loopable – Hochpass, Kammfilter-Echos | CC0 |
| `river_thunder`, `river_thunder_close` | wuxiascrub, „Rain + Long Thunder“, https://opengameart.org/content/rain-long-thunder – Ausschnitte, EQ | CC0 |
| `river_creak` | antumdeluge, „Tree Creaking“, https://opengameart.org/content/tree-creaking + rubberduck „75 CC0 breaking/falling/hit sfx“ (metal_falling_02), tiefer gepitcht | CC0 |
| `river_collapse` | rubberduck, https://opengameart.org/content/75-cc0-breaking-falling-hit-sfx (metal_falling 01/03/05, rock_falling_03) + `river_creak` gemischt | CC0 |
| `river_splash` | rubberduck, https://opengameart.org/content/40-cc0-water-splash-slime-sfx (splash_03, splash_07), tiefer gepitcht | CC0 |
| Funksprüche, Figuren (Weber, Aksoy, Kerner) | Frei erfunden | CC0 |

## Pistole, Nachlade- und Bewegungs-Sounds (Waffengefühl-Update)

| Datei | Quelle / Bearbeitung | Lizenz |
|---|---|---|
| `assets/weapons/pistol/sig_p228.glb` | „Rigged Sig p228“ von PuKkBuMXDD, https://poly.pizza/m/xce5OmcO43 – Materialien im Spiel per Code ersetzt (`weapon.gd`) | CC-BY 3.0 (Namensnennung: PuKkBuMXDD) |
| `assets/sfx/weapon_mag_out`, `weapon_mag_in`, `weapon_bolt` | Ausschnitte aus dem vorhandenen `rifle_reload` (springyspringo, CC0) | CC0 |
| `assets/sfx/pistol_mag_out`, `pistol_mag_in`, `pistol_slide` | Ausschnitte aus dem vorhandenen `pistol_reload` (zer0sol, CC0) | CC0 |
| `assets/sfx/weapon_mag_drop` | Aus dem vorhandenen `grenade_bounce_2` (bmaczero, CC0), höher gepitcht | CC0 |
| `assets/sfx/player_mantle` | Aus dem vorhandenen `jump` (Kenney, CC0) | CC0 |
| `assets/sfx/player_prone` | Mischung aus den vorhandenen `land` + `jump` (Kenney, CC0) | CC0 |
| `assets/sfx/player_slide` | Selbst synthetisiert (gefiltertes Rauschen, ffmpeg) | CC0 |
| Reflexvisier, Red-Dot-Shader, Ersatzmodelle | Selbst erstellt (Code) | CC0 |

## Fahrzeug- und Soldaten-Modelle (Realismus-Update)

| Datei | Quelle / Bearbeitung | Lizenz |
|---|---|---|
| `assets/vehicles/textures/green_metal_rust/` (diffuse, normal, arm) | Poly Haven „Green Metal Rust“, https://polyhaven.com/a/green_metal_rust – Rost, Detail-Normalen und AO im Fahrzeuglack (`vehicle_paint.gdshader`) | CC0 |
| `assets/vehicles/textures/rusty_painted_metal/` | Poly Haven „Rusty Painted Metal“, https://polyhaven.com/a/rusty_painted_metal (Reserve/Alternative) | CC0 |
| `assets/characters/textures/rough_linen/` (normal, arm, diffuse) | Poly Haven „Rough Linen“, https://polyhaven.com/a/rough_linen – Gewebestruktur der Uniformen/Ausrüstung | CC0 |
| `assets/vehicles/textures/vehicle_noise.png`, `tac_numbers.png`, `stripe_amber.png` | Selbst erzeugt (`assets/vehicles/gen_textures.py`) | CC0 |
| `assets/characters/textures/camo_ru_digital.png`, `camo_reich_urban.png` | Selbst erzeugt (`assets/characters/textures/gen_camo.py`), Pixeltarnung im Stil „Tsifra“ bzw. fiktive Ordnungsfront-Stadttarnung | CC0 |
| Panzer (T-72B3/T-90-Stil), Kampfhubschrauber (Mi-28-Stil), Soldaten-Ausrüstung | Selbst modelliert per Code (`game/vehicles/models/*.gd`, `mesh_kit.gd`, `game/enemies/soldier_gear.gd`), Shader `vehicle_paint`, `track_loop`, `soldier_cloth` selbst geschrieben | CC0 |
| Ordnungsfront-Emblem auf Fahrzeugen | Vorhandene `assets/environment/berlin/emblem.png` (frei erfunden) | CC0 |

## Umgebung und Bildlook (Realismus-Pass Gebäude/Straße)

| Datei | Quelle / Bearbeitung | Lizenz |
|---|---|---|
| `assets/environment/facade/textures/painted_plaster_wall/`, `red_brick_03/`, `precast_concrete_wall/`, `rough_plaster_broken/` | Poly Haven, https://polyhaven.com/a/painted_plaster_wall, https://polyhaven.com/a/red_brick_03, https://polyhaven.com/a/precast_concrete_wall, https://polyhaven.com/a/rough_plaster_broken – Triplanar-Fassaden-Shader (`facade.gdshader`) | CC0 |
| `assets/environment/street/textures/worn_asphalt/`, `concrete_pavement/`, `dry_decay_leaves/` | Poly Haven, https://polyhaven.com/a/worn_asphalt, https://polyhaven.com/a/concrete_pavement, https://polyhaven.com/a/dry_decay_leaves – Laub-Decal aus `dry_decay_leaves` freigestellt | CC0 |
| `assets/environment/street/models/` (covered_car, street_lamp_01, fire_hydrant, water_manhole_cover, utility_box_02, power_box_01, exterior_aircon_unit, trashbag, metal_trash_can, cardboard_box_01, rusted_wheel_rim_01, old_tyre, concrete_road_barrier, rollershutter_door, security_light) | Poly Haven Modelle, https://polyhaven.com/models (jeweils https://polyhaven.com/a/<name>), 1k-glTF | CC0 |
| `assets/environment/decals/` (Einschüsse, Ruß, Risse, Flicken, Pfützen, Papier, Gully, Farbe) | Selbst prozedural erzeugt (Python/Pillow) | CC0 |
| `assets/environment/facade/facade.gdshader`, `game/vfx/shaders/post_fx.gdshader`, `window_interior.gdshader` (Interior Mapping) | Selbst geschrieben | CC0 |
