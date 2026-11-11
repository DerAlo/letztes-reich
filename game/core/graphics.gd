extends Node
## Grafik-Backend (Autoload "Graphics", siehe CONTRACTS.md "Runde 6", Agent B).
##
## Schnittstelle fuer die UI:
##   get_options() -> Array[Dictionary]   – Optionsliste (key, label, section, type, values/labels, min/max/step,
##                                          default, tooltip, requires_restart)
##   apply_all()                          – alles anwenden (Start, nach Preset-Wechsel)
##   apply_preset("niedrig"|"mittel"|"hoch"|"ultra")
## Reagiert selbst auf Settings.changed fuer graphics/*.
##
## Grundprinzip: Jede Option wirkt RELATIV zu dem, was das Level selbst eingestellt hat.
## Eine Eigenschaft wird erst beim ersten Abweichen vom Original angefasst; der Originalwert wird dann als
## Meta (_gfx_orig) am Objekt gemerkt und beim Zuruecksetzen wiederhergestellt.
## Qualitaetsoptionen schalten nur herunter/herauf, was ein Level benutzt – sie aktivieren nie Effekte, die ein
## Level bewusst aus hat (z. B. Gunship: kein SSAO/SDFGI/Nebel, kein Kino-Look).
##
## Kino-Look (Runde "CoD-Grafik", game/graphics/): Der PostFx-Bildschirmshader der Level wird zur Laufzeit gegen
## game/graphics/cinema_post.gdshader getauscht (gleiche Level-Parameter + Teal-Orange-LUT, CAS-Nachschaerfen,
## optionale Kamera-Bewegungsunschaerfe mit Waffenmaske). Level ohne eigenen PostFx (ausser Linear-Tonemapping
## wie das Gunship) bekommen ein Standard-Overlay. Nachtsicht/Drohne daempfen den Look automatisch (fx_mute).
## Standard ist FSR 2.2 mit 100 % (natives temporales AA) – glaettet Kanten UND Textur-/Specular-Flimmern.
##
## Erfasst werden Level-Objekte generisch ueber get_tree().node_added: WorldEnvironment / Camera3D.environment,
## Light3D, GPU-/CPUParticles3D und der PostFx-Bildschirmshader (game/vfx/post_fx.gd). SubViewports
## (Waffen-Viewmodel) bleiben unangetastet.
##
## Debug-Args (nach "--"):
##   --gfx-preset=<niedrig|mittel|hoch|ultra>   Preset anwenden (ohne Speichern bei Tool-Laeufen)
##   --gfx-set=ssao=aus,sdfgi=aus               Einzelwerte setzen
##   --gfx-off                                   Graphics komplett inaktiv (Vergleichsbasis)
##   --gfx-bench=<sek> [--gfx-shot=<png>] [--gfx-warmup=<sek>]
##        wartet auf die 3D-Kamera, Aufwaermzeit (Standard 6 s), Screenshot, misst dann <sek> lang FPS/GPU-Zeit
##        (VSync aus), gibt "GFX_BENCH ..." aus und beendet das Spiel. --gfx-cycle=<preset> wechselt nach 2 s
##        zur Laufzeit das Preset (Test der Wiederherstellung).

const POST_FX_SHADER := preload("res://game/vfx/shaders/post_fx.gdshader")
const ADJUST_SHADER := preload("res://game/vfx/post/display_adjust.gdshader")
const FPS_OVERLAY_SCRIPT := preload("res://game/ui/fps_overlay.gd")
const CINEMA_SHADER := preload("res://game/graphics/cinema_post.gdshader")
const GradeLut := preload("res://game/graphics/grade_lut.gd")
const PostFxLib := preload("res://game/vfx/post_fx.gd")
## Sondersichten, bei denen der Kino-Look gedaempft wird (Script-Pfade, kein preload -> keine Ladeabhaengigkeit)
const SPECIAL_SCRIPTS: Array[String] = ["res://game/systems/nightvision.gd", "res://game/systems/recon_drone.gd"]
## Post-Shader-Parameter, die aus dem Level-Profil stammen und beim Shader-Tausch erhalten bleiben
const POST_PARAMS: Array[StringName] = [&"aberration", &"vignette", &"vignette_soft", &"grain", &"grain_size",
	&"saturation", &"lift"]

const PRESETS: Array[String] = ["niedrig", "mittel", "hoch", "ultra"]
const P := "graphics/"
const META := &"_gfx_orig"

## Werte, die VfxEnv.apply_render_quality() in den Leveln setzt (= Stand "Hoch").
const LEVEL_DIR_ATLAS := 8192
const LEVEL_FOG_VOLUME := Vector2i(160, 96)
## Volumetrischer Nebel aus: Dichte wandert anteilig in den Distanznebel, damit der Dunst bleibt.
const FOG_FALLBACK_K := 2.5
## ... und der Distanznebel wird mindestens so hell wie das (von Licht/GI aufgehellte) Nebel-Albedo * Faktor.
const FOG_FALLBACK_LIGHT := 0.3

const G_ENV := &"_gfx_env"
const G_LIGHT := &"_gfx_light"
const G_PART := &"_gfx_particles"
const G_POST := &"_gfx_post"
const G_SPECIAL := &"_gfx_special"

var _opts: Array[Dictionary] = []
var _by_key: Dictionary = {}
var _off: bool = false
var _batch: bool = false
var _suppress_preset: bool = false
var _apply_queued: bool = false
var _flush_queued: bool = false
var _late_pending: bool = false
var _new_nodes: Array[Node] = []
var _new_has_env: bool = false
var _rs_last: Dictionary = {}
var _dir_atlas_overridden: bool = false
var _fog_volume_overridden: bool = false
var _adjust_layer: CanvasLayer
var _adjust_mat: ShaderMaterial
var _fps_overlay: CanvasLayer
var _new_geo: Array[GeometryInstance3D] = []
var _aniso_done: Dictionary = {}
# Kino-Look: Bewegungsunschaerfe / Sondersicht
var _mb_cam: Camera3D
var _mb_basis: Basis
var _mb_vec: Vector2 = Vector2.ZERO
var _mute: float = 0.0
var _mask_vp: SubViewport
var _mask_try: int = 0

# Benchmark (--gfx-bench)
var _bench_secs: float = 0.0
var _bench_warmup: float = 6.0
var _bench_state: int = 0
var _bench_t: float = 0.0
var _bench_frames: int = 0
var _bench_gpu: float = 0.0
var _bench_worst: PackedFloat32Array = PackedFloat32Array()
var _bench_last_us: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_options()
	if Game.arg("gfx-off", false):
		_off = true
		print("[graphics] --gfx-off: Grafik-Backend inaktiv")
	else:
		Settings.changed.connect(_on_setting_changed)
		get_tree().node_added.connect(_on_node_added)
		var pre := str(Game.arg("gfx-preset", ""))
		if pre != "":
			if pre in PRESETS:
				apply_preset(pre)
			else:
				push_warning("[graphics] unbekanntes Preset '%s'" % pre)
		_apply_cli_overrides()
		apply_all()
	_bench_secs = float(Game.arg("gfx-bench", 0.0))
	if _bench_secs > 0.0:
		_bench_warmup = float(Game.arg("gfx-warmup", 6.0))
	set_process(not _off or _bench_secs > 0.0)


# =========================================================================== Optionen

func get_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for o in _opts:
		var d: Dictionary = o.duplicate(true)
		d.erase("presets")
		out.append(d)
	return out


func _opt(key: String, label: String, section: String, type: String, default: Variant, tooltip: String,
		extra: Dictionary = {}) -> void:
	var d := {"key": P + key, "label": label, "section": section, "type": type, "default": default,
		"tooltip": tooltip, "requires_restart": false}
	d.merge(extra, true)
	_opts.append(d)
	_by_key[key] = d


func _build_options() -> void:
	_opts.clear()
	_by_key.clear()
	const S0 := "Voreinstellung"
	const S1 := "Anzeige"
	const S2 := "Bildskalierung"
	const S3 := "Kantenglättung"
	const S4 := "Qualität"
	const S5 := "Nachbearbeitung"

	_opt("preset", "Grafik-Voreinstellung", S0, "enum", "hoch",
		"Setzt alle Qualitätswerte auf einmal. Hoch = volle Level-Qualität mit FSR 2.2 als Kantenglättung (Mittelklasse-GPU). Niedrig/Mittel rechnen intern in geringerer Auflösung (FSR 2.2 skaliert hoch), Ultra für starke Grafikkarten. Sobald ein Einzelwert abweicht: „Benutzerdefiniert“.",
		{"values": ["niedrig", "mittel", "hoch", "ultra", "benutzerdefiniert"],
		"labels": ["Niedrig", "Mittel", "Hoch", "Ultra", "Benutzerdefiniert"]})

	# ------------------------------------------------------------ Anzeige
	_opt("window_mode", "Fenstermodus", S1, "enum", "fenster",
		"Fenster, randloses Vollbild (schnelles Alt+Tab) oder exklusives Vollbild (geringste Latenz, VSync-Steuerung durch den Treiber).",
		{"values": ["fenster", "randlos", "vollbild"], "labels": ["Fenster", "Randlos", "Vollbild (exklusiv)"]})
	var res_vals: Array = ["auto"]
	var res_labels: Array = ["Automatisch"]
	var scr := DisplayServer.screen_get_size()
	# Gaengige Aufloesungen aller Seitenverhaeltnisse (16:9, 16:10, 21:9) plus die native Monitoraufloesung,
	# damit z. B. 2560x1600 oder 3440x1440 waehlbar sind (frueher nur 16:9 -> Maximum oft kleiner als der Monitor).
	var cand: Array = ["1280x720", "1280x800", "1600x900", "1680x1050", "1920x1080", "1920x1200",
		"2560x1080", "2560x1440", "2560x1600", "3440x1440", "3840x1600", "3840x2160"]
	var native := ""
	if scr.x > 0 and scr.y > 0:
		native = "%dx%d" % [scr.x, scr.y]
		if not cand.has(native):
			cand.append(native)
	cand.sort_custom(func(a: String, b: String) -> bool:
		var wa := _parse_res(a)
		var wb := _parse_res(b)
		return wa.x * wa.y < wb.x * wb.y if wa.x * wa.y != wb.x * wb.y else wa.x < wb.x)
	for r in cand:
		var wh := _parse_res(r)
		if scr.x <= 0 or (wh.x <= scr.x and wh.y <= scr.y):
			res_vals.append(r)
			res_labels.append(r.replace("x", " × ") + (" (Monitor)" if r == native else ""))
	_opt("resolution", "Auflösung", S1, "enum", "auto",
		"Fenster: Fenstergröße. Vollbild: Godot gibt immer in Monitorauflösung aus – eine kleinere Auflösung senkt hier die interne 3D-Auflösung (wie Renderauflösung). „Automatisch“ = Monitor bzw. Startgröße.",
		{"values": res_vals, "labels": res_labels})
	_opt("vsync", "VSync", S1, "enum", "an",
		"Synchronisiert mit der Bildwiederholrate: verhindert Tearing, kostet etwas Eingabeverzögerung. Adaptiv = nur unterhalb der Bildrate synchronisieren. Mailbox = ohne Tearing, geringe Latenz (falls unterstützt).",
		{"values": ["aus", "an", "adaptiv", "mailbox"], "labels": ["Aus", "An", "Adaptiv", "Mailbox"]})
	_opt("fps_limit", "Bildraten-Limit", S1, "enum", 0,
		"Begrenzt die Bilder pro Sekunde. Spart Strom/Wärme und glättet die Frametimes, wenn die GPU das Limit sicher hält.",
		{"values": [0, 30, 60, 120, 144, 165, 240], "labels": ["Aus", "30", "60", "120", "144", "165", "240"]})
	_opt("fps_overlay", "FPS-Anzeige", S1, "bool", false,
		"Kleines Overlay oben links: FPS, Frametime, schlechteste 1 %, GPU-Zeit und Frametime-Graph.")

	# ------------------------------------------------------------ Bildskalierung
	_opt("upscale_mode", "Hochskalierung", S2, "enum", "fsr2",
		"Wie das 3D-Bild entsteht. AMD FSR 2.2 (Standard): temporal – glättet Kanten und Textur-Flimmern, bei 100 % als natives AA, darunter als Hochskalierer (Qualität 67 %, Ausgewogen 59 %, Leistung 50 %); MSAA/FXAA/SMAA/TAA sind dann aus. FSR 1: räumliches Schärfen, sehr günstig, ohne Glättung. Bilinear: einfach, weich (nutzt MSAA + Bildschirm-Kantenglättung).",
		{"values": ["bilinear", "fsr1", "fsr2"], "labels": ["Bilinear", "AMD FSR 1.0", "AMD FSR 2.2"],
		"presets": {"niedrig": "fsr2", "mittel": "fsr2", "hoch": "fsr2", "ultra": "fsr2"}})
	_opt("render_scale", "Renderauflösung", S2, "enum", 1.0,
		"Anteil der Bildschirmauflösung, in dem die 3D-Welt berechnet wird (HUD bleibt scharf). Größter Leistungshebel: 67 % spart grob die Hälfte der Pixel. Mit FSR 2.2 sieht auch 59–67 % noch gut aus.",
		{"values": [1.0, 0.9, 0.77, 0.67, 0.59, 0.5, 0.33],
		"labels": ["100 % (nativ / FSR 2 Native-AA)", "90 %", "77 % – FSR Ultra-Qualität", "67 % – FSR Qualität", "59 % – FSR Ausgewogen", "50 % – FSR Leistung", "33 % – FSR Ultra-Leistung"],
		"presets": {"niedrig": 0.59, "mittel": 0.67, "hoch": 1.0, "ultra": 1.0}})
	_opt("fsr_sharpness", "Schärfe (FSR)", S2, "float", 0.9,
		"Nachschärfen bei FSR 1/2 (0 = weich, 1 = maximal scharf). Keine Leistungskosten.",
		{"min": 0.0, "max": 1.0, "step": 0.05})

	# ------------------------------------------------------------ Kantenglättung
	_opt("msaa", "MSAA", S3, "enum", "2x",
		"Multisample-Kantenglättung für Geometriekanten. Saubere Kanten ohne Unschärfe, aber teuer: 4x/8x = hohe GPU-Last. Bei FSR 2.2 aus.",
		{"values": ["aus", "2x", "4x", "8x"], "labels": ["Aus", "2x", "4x", "8x"],
		"presets": {"niedrig": "aus", "mittel": "aus", "hoch": "2x", "ultra": "4x"}})
	_opt("screen_aa", "Bildschirm-Kantenglättung", S3, "enum", "taa",
		"Nur ohne FSR 2.2. FXAA: sehr günstig, etwas weich. SMAA: schärfer und gründlicher, geringe Kosten. TAA: glättet auch Textur-/Glanzlicht-Flimmern und Vegetation, kann bei Bewegung leicht schmieren. Bei FSR 2.2 übernimmt FSR das.",
		{"values": ["aus", "fxaa", "smaa", "taa"], "labels": ["Aus", "FXAA", "SMAA", "TAA"],
		"presets": {"niedrig": "fxaa", "mittel": "taa", "hoch": "taa", "ultra": "taa"}})

	# ------------------------------------------------------------ Qualität
	_opt("shadows", "Schattenqualität", S4, "enum", "hoch",
		"Auflösung und Weichzeichnung der Schatten, Schattendistanz der Sonne/des Mondes. Niedrig spart deutlich GPU-Speicher und Zeit, Schatten werden gröber und enden früher.",
		{"values": ["niedrig", "mittel", "hoch", "ultra"], "labels": ["Niedrig", "Mittel", "Hoch", "Ultra"],
		"presets": {"niedrig": "niedrig", "mittel": "mittel", "hoch": "hoch", "ultra": "ultra"}})
	_opt("light_shadows", "Lampenschatten", S4, "bool", true,
		"Schatten von Lampen, Scheinwerfern und Mündungsfeuer. Aus = großer Gewinn in Nachtleveln mit vielen Lichtern, die Stimmung wird aber flacher.",
		{"presets": {"niedrig": true, "mittel": true, "hoch": true, "ultra": true}})
	_opt("ssao", "Umgebungsverdeckung (SSAO)", S4, "enum", "hoch",
		"Kontaktschatten in Ecken und unter Objekten. Mittlere GPU-Last; Ultra rechnet in voller Auflösung.",
		{"values": ["aus", "niedrig", "mittel", "hoch", "ultra"], "labels": ["Aus", "Niedrig", "Mittel", "Hoch", "Ultra"],
		"presets": {"niedrig": "aus", "mittel": "niedrig", "hoch": "hoch", "ultra": "ultra"}})
	_opt("ssil", "Indirektes Licht (SSIL)", S4, "enum", "hoch",
		"Farbiges Streulicht von hellen Flächen in der Nähe (Bildschirmraum). Mittlere bis hohe GPU-Last.",
		{"values": ["aus", "niedrig", "hoch", "ultra"], "labels": ["Aus", "Niedrig", "Hoch", "Ultra"],
		"presets": {"niedrig": "aus", "mittel": "aus", "hoch": "hoch", "ultra": "ultra"}})
	_opt("ssr", "Spiegelungen (SSR)", S4, "enum", "hoch",
		"Spiegelungen auf nassen Straßen, Wasser und Glas (Bildschirmraum). Mittlere GPU-Last.",
		{"values": ["aus", "niedrig", "hoch", "ultra"], "labels": ["Aus", "Niedrig", "Hoch", "Ultra"],
		"presets": {"niedrig": "aus", "mittel": "niedrig", "hoch": "hoch", "ultra": "ultra"}})
	_opt("vol_fog", "Volumetrischer Nebel", S4, "enum", "hoch",
		"Lichtstrahlen im Dunst, Scheinwerferkegel. Niedrig = gröberes Raster. Aus = großer Gewinn; der Dunst wird dann durch normalen Distanznebel ersetzt (ohne Lichtkegel).",
		{"values": ["aus", "niedrig", "mittel", "hoch", "ultra"], "labels": ["Aus", "Niedrig", "Mittel", "Hoch", "Ultra"],
		"presets": {"niedrig": "niedrig", "mittel": "mittel", "hoch": "hoch", "ultra": "ultra"}})
	_opt("sdfgi", "Globale Beleuchtung (SDFGI)", S4, "enum", "hoch",
		"Echtzeit-Lichtreflexion zwischen Wänden und Boden. Hohe GPU-Last. Niedrig rechnet in halber Auflösung mit weniger Strahlen, Aus spart am meisten (Ausleuchtung wird flacher).",
		{"values": ["aus", "niedrig", "hoch", "ultra"], "labels": ["Aus", "Niedrig", "Hoch", "Ultra"],
		"presets": {"niedrig": "aus", "mittel": "niedrig", "hoch": "hoch", "ultra": "ultra"}})
	_opt("glow", "Leuchten (Bloom)", S4, "enum", "hoch",
		"Überstrahlen heller Lichter, Neon, Explosionen. Geringe GPU-Last; Niedrig = einfachere Hochskalierung des Glow.",
		{"values": ["aus", "niedrig", "hoch"], "labels": ["Aus", "Niedrig", "Hoch"],
		"presets": {"niedrig": "niedrig", "mittel": "hoch", "hoch": "hoch", "ultra": "hoch"}})
	_opt("aniso", "Anisotrope Filterung", S4, "enum", 16,
		"Schärfe von Texturen in flachem Blickwinkel (Straßen, Böden) – ohne Flimmern. Kaum Leistungskosten.",
		{"values": [0, 2, 4, 8, 16], "labels": ["Aus", "2x", "4x", "8x", "16x"],
		"presets": {"niedrig": 4, "mittel": 8, "hoch": 16, "ultra": 16}})
	_opt("lod", "Detailstufen (LOD)", S4, "enum", "hoch",
		"Ab welcher Entfernung Modelle durch einfachere Versionen ersetzt werden. Niedrig = früher vereinfachen (spart Geometrie-Last).",
		{"values": ["niedrig", "mittel", "hoch", "ultra"], "labels": ["Niedrig", "Mittel", "Hoch", "Ultra"],
		"presets": {"niedrig": "niedrig", "mittel": "mittel", "hoch": "hoch", "ultra": "ultra"}})
	_opt("particles", "Partikeldichte", S4, "enum", 1.0,
		"Menge an Funken, Rauch, Trümmern, Regen. Weniger = entlastet GPU bei Explosionen und großen Gefechten.",
		{"values": [0.25, 0.5, 0.75, 1.0], "labels": ["25 %", "50 %", "75 %", "100 %"],
		"presets": {"niedrig": 0.5, "mittel": 0.75, "hoch": 1.0, "ultra": 1.0}})

	_opt("light_shafts", "Lichtschäfte / Dunst", S4, "bool", true,
		"Fügt Leveln mit Bildlook, die keinen eigenen volumetrischen Nebel haben, einen hauchdünnen Dunst hinzu: Licht- und Schattenschäfte von Sonne und Lampen. Mittlere GPU-Last (wie Volumetrischer Nebel „Hoch“). Wirkt nur, wenn Volumetrischer Nebel nicht aus ist.",
		{"presets": {"niedrig": false, "mittel": false, "hoch": true, "ultra": true}})

	_opt("real_soldiers", "Realistische Soldaten", S4, "bool", true,
		"Gegner als realistische Menschen (eigene Körper-Varianten, Uniform mit Tarnmuster, Stahlhelm, flüssige Animationen) statt der einfachen Spielfiguren. Aus = ältere, schlichtere Modelle (etwas weniger GPU-Last bei vielen Gegnern). Gilt ab dem nächsten Levelstart.")

	# ------------------------------------------------------------ Nachbearbeitung
	_opt("look", "Bildlook", S5, "enum", "kino",
		"Farbabstimmung wie in modernen Militär-Shootern: Kino = Teal-Orange-Grading (kühle Schatten, warme Lichter, oliv statt knallgrün) und leichte S-Kurve. Dezent = halbe Stärke. Original = Level-Farben unverändert. Keine Leistungskosten.",
		{"values": ["original", "dezent", "kino"], "labels": ["Original", "Dezent", "Kino"]})
	_opt("sharpen", "Nachschärfen (CAS)", S5, "float", 0.35,
		"Kontrastadaptives Nachschärfen des fertigen Bildes – gleicht die Weichheit von TAA/FSR aus, ohne Kanten-Überschwingen. 0 = aus. Sehr geringe Kosten.",
		{"min": 0.0, "max": 1.0, "step": 0.05})
	_opt("motion_blur", "Bewegungsunschärfe", S5, "enum", "aus",
		"Kamera-Bewegungsunschärfe beim schnellen Umsehen (die Waffe bleibt scharf, beim Zielen durchs Zielfernrohr aus). Geringe bis mittlere Kosten nur während der Drehung.",
		{"values": ["aus", "niedrig", "hoch"], "labels": ["Aus", "Niedrig", "Hoch"]})
	_opt("film_grain", "Filmkorn", S5, "float", 1.0,
		"Stärke des Filmkorns relativ zum Level-Look (1 = Original, 0 = aus). Keine Leistungskosten.",
		{"min": 0.0, "max": 2.0, "step": 0.1})
	_opt("aberration", "Chromatische Aberration", S5, "float", 1.0,
		"Farbsäume zum Bildrand hin, relativ zum Level-Look (1 = Original, 0 = aus). Keine Leistungskosten.",
		{"min": 0.0, "max": 3.0, "step": 0.1})
	_opt("vignette", "Vignette", S5, "float", 1.0,
		"Abdunklung der Bildecken, relativ zum Level-Look (1 = Original, 0 = aus). Keine Leistungskosten.",
		{"min": 0.0, "max": 2.0, "step": 0.1})
	_opt("brightness", "Helligkeit", S5, "float", 1.0,
		"Gesamthelligkeit des Bildes (1 = neutral). Wirkt auf alles inklusive HUD.",
		{"min": 0.5, "max": 1.5, "step": 0.05})
	_opt("contrast", "Kontrast", S5, "float", 1.0,
		"Bildkontrast (1 = neutral).",
		{"min": 0.5, "max": 1.5, "step": 0.05})
	_opt("gamma", "Gamma", S5, "float", 1.0,
		"Hebt (größer 1) oder senkt (kleiner 1) die Mitteltöne, ohne Schwarz und Weiß zu verändern. Hilfreich bei dunklen Nachtleveln.",
		{"min": 0.6, "max": 1.6, "step": 0.05})


func _v(name: String) -> Variant:
	var d: Dictionary = _by_key[name]
	var v: Variant = Settings.get_value(P + name, d["default"])
	return d["default"] if v == null else v


func _vs(name: String) -> String:
	return str(_v(name))


func _vf(name: String) -> float:
	return float(_v(name))


func _is_default(name: String) -> bool:
	return _same(_v(name), _by_key[name]["default"])


static func _same(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	return str(a) == str(b)


# =========================================================================== Presets

func apply_preset(preset_name: String) -> void:
	if not preset_name in PRESETS:
		return
	_batch = true
	for o in _opts:
		if o.has("presets"):
			Settings.set_value(str(o["key"]), o["presets"][preset_name])
	_batch = false
	_suppress_preset = true
	Settings.set_value(P + "preset", preset_name)
	_suppress_preset = false
	apply_all()


func current_preset() -> String:
	for pr in PRESETS:
		var ok := true
		for o in _opts:
			if o.has("presets") and not _same(_v(str(o["key"]).substr(P.length())), o["presets"][pr]):
				ok = false
				break
		if ok:
			return pr
	return "benutzerdefiniert"


func _update_preset_label() -> void:
	var cur := current_preset()
	if str(Settings.get_value(P + "preset", "hoch")) != cur:
		_suppress_preset = true
		Settings.set_value(P + "preset", cur)
		_suppress_preset = false


func _apply_cli_overrides() -> void:
	var s := str(Game.arg("gfx-set", ""))
	if s == "":
		return
	for pair in s.split(",", false):
		var kv := pair.split("=", true, 1)
		if kv.size() < 2 or not _by_key.has(kv[0]):
			push_warning("[graphics] --gfx-set: unbekannt '%s'" % pair)
			continue
		var d: Dictionary = _by_key[kv[0]]
		var val: Variant = kv[1]
		match str(d["type"]):
			"bool":
				val = kv[1] in ["1", "true", "an", "on"]
			"float":
				val = float(kv[1])
			"int":
				val = int(kv[1])
			"enum":
				for ev in d["values"]:
					if str(ev) == kv[1] or (kv[1].is_valid_float() and _same(ev, float(kv[1]))):
						val = ev
		Settings.set_value(str(d["key"]), val)


# =========================================================================== Reaktion auf Settings

func _on_setting_changed(key: String, value: Variant) -> void:
	if _batch or not key.begins_with(P):
		return
	var name := key.substr(P.length())
	if name == "preset":
		if not _suppress_preset and value is String and value in PRESETS:
			apply_preset(value)
		return
	match name:
		"window_mode", "resolution":
			_apply_window()
		"vsync":
			_apply_vsync()
		"fps_limit":
			_apply_fps_limit()
	_queue_apply()
	if _by_key.has(name) and _by_key[name].has("presets"):
		_update_preset_label()


func _queue_apply() -> void:
	if not _apply_queued:
		_apply_queued = true
		apply_all.call_deferred()


func apply_all() -> void:
	_apply_queued = false
	if _off:
		return
	_apply_display_stored()
	_apply_viewport()
	_apply_globals()
	for n in get_tree().get_nodes_in_group(G_ENV):
		_apply_env_node(n)
	for n in get_tree().get_nodes_in_group(G_LIGHT):
		_apply_light(n as Light3D)
	for n in get_tree().get_nodes_in_group(G_PART):
		_apply_particles(n)
	for n in get_tree().get_nodes_in_group(G_POST):
		_apply_post(n as CanvasItem)
	_ensure_fallback_post()
	_apply_adjust()
	_apply_fps_overlay()


# =========================================================================== Generischer Hook

func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment or n is Camera3D:
		n.add_to_group(G_ENV)
		_new_has_env = true
	elif n is Light3D:
		n.add_to_group(G_LIGHT)
	elif n is GPUParticles3D or n is CPUParticles3D:
		n.add_to_group(G_PART)
	elif n is GeometryInstance3D:
		_new_geo.append(n as GeometryInstance3D)
		if not _flush_queued:
			_flush_queued = true
			_flush.call_deferred()
		return
	elif n is ColorRect:
		var m := (n as ColorRect).material as ShaderMaterial
		if m == null or (m.shader != POST_FX_SHADER and m.shader != CINEMA_SHADER):
			return
		n.add_to_group(G_POST)
	else:
		var sc := n.get_script() as Script
		if sc != null and sc.resource_path in SPECIAL_SCRIPTS:
			n.add_to_group(G_SPECIAL)
		return
	_new_nodes.append(n)
	if not _flush_queued:
		_flush_queued = true
		_flush.call_deferred()


## Ende des Frames, in dem Level-Knoten hinzukamen: das Level hat seine Werte (inkl. apply_render_quality und
## PostFx.apply) dann schon gesetzt, die Originale sind also die des Levels.
func _flush() -> void:
	_flush_queued = false
	var nodes := _new_nodes
	_new_nodes = []
	var had_env := _new_has_env
	_new_has_env = false
	var geo := _new_geo
	_new_geo = []
	for g in geo:
		if is_instance_valid(g):
			_aniso_geo(g)
	if had_env:
		_apply_viewport()
		_apply_globals()
		if not _late_pending:
			_late_pending = true
			get_tree().create_timer(0.75, true, false, true).timeout.connect(_late_reapply)
	for n in nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		if n.is_in_group(G_ENV):
			_apply_env_node(n)
		elif n.is_in_group(G_LIGHT):
			_apply_light(n as Light3D)
		elif n.is_in_group(G_PART):
			_apply_particles(n)
		elif n.is_in_group(G_POST):
			_apply_post(n as CanvasItem)


## Nachlauf fuer Level, die Umgebung/Viewport-Werte etwas spaeter setzen.
func _late_reapply() -> void:
	_late_pending = false
	_apply_viewport()
	_apply_globals()
	for n in get_tree().get_nodes_in_group(G_ENV):
		_apply_env_node(n)
	_ensure_fallback_post()


# =========================================================================== Override-Helfer

## Setzt obj.prop = value und merkt sich beim ersten Mal den Originalwert. identity=true stellt das Original
## wieder her (oder laesst die Eigenschaft unberuehrt, wenn sie nie ueberschrieben wurde).
func _ov(obj: Object, prop: StringName, value: Variant, identity: bool) -> void:
	var orig: Dictionary = obj.get_meta(META, {})
	if identity:
		if orig.has(prop):
			if obj.get(prop) != orig[prop]:
				obj.set(prop, orig[prop])
			orig.erase(prop)
			if orig.is_empty():
				obj.remove_meta(META)
			else:
				obj.set_meta(META, orig)
		return
	if not orig.has(prop):
		orig[prop] = obj.get(prop)
		obj.set_meta(META, orig)
	if obj.get(prop) != value:
		obj.set(prop, value)


func _orig(obj: Object, prop: StringName) -> Variant:
	var orig: Dictionary = obj.get_meta(META, {})
	return orig[prop] if orig.has(prop) else obj.get(prop)


## Wie _ov, aber "Original" ergibt sich automatisch: entspricht value dem Originalwert, wird wiederhergestellt.
func _ova(obj: Object, prop: StringName, value: Variant) -> void:
	var o: Variant = _orig(obj, prop)
	var same := false
	if (o is float or o is int or o is bool) and (value is float or value is int or value is bool):
		same = is_equal_approx(float(o), float(value))
	else:
		same = o == value
	_ov(obj, prop, value, same)


## Globale RenderingServer-Aufrufe nur bei Aenderung.
func _rs(method: String, args: Array) -> void:
	if _rs_last.get(method) == args:
		return
	_rs_last[method] = args
	RenderingServer.callv(method, args)


static func _ps(key: String, default: Variant) -> Variant:
	return ProjectSettings.get_setting(key, default)


# =========================================================================== Viewport

func _res_factor() -> float:
	var mode := DisplayServer.window_get_mode()
	if mode != DisplayServer.WINDOW_MODE_FULLSCREEN and mode != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		return 1.0
	var r := _vs("resolution")
	if r == "auto":
		return 1.0
	var wh := _parse_res(r)
	var scr := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	if scr.y <= 0:
		return 1.0
	return clampf(float(wh.y) / float(scr.y), 0.25, 1.0)


func _apply_viewport() -> void:
	var vp := get_tree().root
	var up := _vs("upscale_mode")
	var fsr2 := up == "fsr2"
	var scale := clampf(_vf("render_scale") * _res_factor(), 0.25, 1.0)
	var sm := Viewport.SCALING_3D_MODE_BILINEAR
	if up == "fsr1":
		sm = Viewport.SCALING_3D_MODE_FSR
	elif fsr2:
		sm = Viewport.SCALING_3D_MODE_FSR2
	_ova(vp, &"scaling_3d_mode", sm)
	_ova(vp, &"scaling_3d_scale", scale)
	_ova(vp, &"fsr_sharpness", 2.0 * (1.0 - _vf("fsr_sharpness")))
	# Mipmap-Bias: Godot addiert bei scale < 1 selbst log2(scale) (richtig fuer FSR 2, das temporal auf volle
	# Aufloesung rekonstruiert). Bilinear/FSR 1 rekonstruieren nicht – dort wird der Auto-Bias neutralisiert,
	# sonst lesen sie zu feine Mip-Stufen und Boeden flimmern. (Frueher wurde hier log2(scale) ein ZWEITES Mal
	# abgezogen -> doppelt negativer Bias, eine der Flimmer-Ursachen im Preset „Niedrig“.)
	var bias := 0.0
	if not fsr2 and scale < 0.999:
		bias = -log(scale) / log(2.0)
	_ova(vp, &"texture_mipmap_bias", bias)

	var msaa := _vs("msaa")
	var msaa_v: int = {"aus": Viewport.MSAA_DISABLED, "2x": Viewport.MSAA_2X, "4x": Viewport.MSAA_4X,
		"8x": Viewport.MSAA_8X}.get(msaa, Viewport.MSAA_2X)
	_ova(vp, &"msaa_3d", Viewport.MSAA_DISABLED if fsr2 else msaa_v)
	var saa := _vs("screen_aa")
	var saa_v := Viewport.SCREEN_SPACE_AA_DISABLED
	if saa == "fxaa":
		saa_v = Viewport.SCREEN_SPACE_AA_FXAA
	elif saa == "smaa":
		saa_v = Viewport.SCREEN_SPACE_AA_SMAA
	_ova(vp, &"screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED if fsr2 else saa_v)
	_ova(vp, &"use_taa", saa == "taa" and not fsr2)

	var aniso: int = {0: Viewport.ANISOTROPY_DISABLED, 2: Viewport.ANISOTROPY_2X, 4: Viewport.ANISOTROPY_4X,
		8: Viewport.ANISOTROPY_8X, 16: Viewport.ANISOTROPY_16X}.get(int(_v("aniso")), Viewport.ANISOTROPY_16X)
	_ova(vp, &"anisotropic_filtering_level", aniso)
	var lod: float = {"niedrig": 4.0, "mittel": 2.0, "hoch": 1.0, "ultra": 0.5}.get(_vs("lod"), 1.0)
	_ov(vp, &"mesh_lod_threshold", lod, _is_default("lod"))
	var sh := _vs("shadows")
	var pos_atlas: int = {"niedrig": 1024, "mittel": 2048, "hoch": 4096, "ultra": 8192}.get(sh, 4096)
	_ov(vp, &"positional_shadow_atlas_size", pos_atlas, sh == "hoch")


# =========================================================================== Globale Qualitaet

func _apply_globals() -> void:
	# Schatten
	var sh := _vs("shadows")
	if sh == "niedrig" or sh == "mittel":
		RenderingServer.directional_shadow_atlas_set_size(2048 if sh == "niedrig" else 4096, true)
		_dir_atlas_overridden = true
	elif _dir_atlas_overridden:
		RenderingServer.directional_shadow_atlas_set_size(LEVEL_DIR_ATLAS, true)
		_dir_atlas_overridden = false
	var soft_def := int(_ps("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 2))
	var psoft_def := int(_ps("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality", 2))
	var soft: int = {"niedrig": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "mittel": soft_def,
		"hoch": soft_def, "ultra": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}.get(sh, soft_def)
	var psoft: int = {"niedrig": RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, "mittel": psoft_def,
		"hoch": psoft_def, "ultra": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}.get(sh, psoft_def)
	_rs("directional_soft_shadow_filter_set_quality", [soft])
	_rs("positional_soft_shadow_filter_set_quality", [psoft])

	# SSAO
	var ao_q := int(_ps("rendering/environment/ssao/quality", 2))
	var ao_half := bool(_ps("rendering/environment/ssao/half_size", true))
	match _vs("ssao"):
		"niedrig":
			ao_q = RenderingServer.ENV_SSAO_QUALITY_VERY_LOW
			ao_half = true
		"mittel":
			ao_q = RenderingServer.ENV_SSAO_QUALITY_LOW
			ao_half = true
		"ultra":
			ao_q = RenderingServer.ENV_SSAO_QUALITY_HIGH
			ao_half = false
	_rs("environment_set_ssao_quality", [ao_q, ao_half,
		float(_ps("rendering/environment/ssao/adaptive_target", 0.5)),
		int(_ps("rendering/environment/ssao/blur_passes", 2)),
		float(_ps("rendering/environment/ssao/fadeout_from", 50.0)),
		float(_ps("rendering/environment/ssao/fadeout_to", 300.0))])

	# SSIL
	var il_q := int(_ps("rendering/environment/ssil/quality", 2))
	var il_half := bool(_ps("rendering/environment/ssil/half_size", true))
	match _vs("ssil"):
		"niedrig":
			il_q = RenderingServer.ENV_SSIL_QUALITY_VERY_LOW
			il_half = true
		"ultra":
			il_q = RenderingServer.ENV_SSIL_QUALITY_HIGH
			il_half = false
	_rs("environment_set_ssil_quality", [il_q, il_half,
		float(_ps("rendering/environment/ssil/adaptive_target", 0.5)),
		int(_ps("rendering/environment/ssil/blur_passes", 4)),
		float(_ps("rendering/environment/ssil/fadeout_from", 50.0)),
		float(_ps("rendering/environment/ssil/fadeout_to", 300.0))])

	# SSR
	var ssr := _vs("ssr")
	var rough: int = RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_LOW
	if ssr == "niedrig":
		rough = RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED
	elif ssr == "ultra":
		rough = RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_MEDIUM
	_rs("environment_set_ssr_roughness_quality", [rough])
	var ssr_half_def := bool(_ps("rendering/environment/screen_space_reflection/half_size", true))
	_rs("environment_set_ssr_half_size", [false if ssr == "ultra" else ssr_half_def])

	# SDFGI
	var rays := int(_ps("rendering/global_illumination/sdfgi/probe_ray_count", 1))
	var conv := int(_ps("rendering/global_illumination/sdfgi/frames_to_converge", 5))
	var upd := int(_ps("rendering/global_illumination/sdfgi/frames_to_update_lights", 2))
	var gi_half := bool(_ps("rendering/global_illumination/gi/use_half_resolution", false))
	match _vs("sdfgi"):
		"niedrig":
			rays = RenderingServer.ENV_SDFGI_RAY_COUNT_4
			gi_half = true
		"ultra":
			rays = mini(rays + 2, RenderingServer.ENV_SDFGI_RAY_COUNT_128)
			gi_half = false
	_rs("environment_set_sdfgi_ray_count", [rays])
	_rs("environment_set_sdfgi_frames_to_converge", [conv])
	_rs("environment_set_sdfgi_frames_to_update_light", [upd])
	_rs("gi_set_use_half_resolution", [gi_half])

	# Glow
	var bicubic := int(_ps("rendering/environment/glow/upscale_mode", 1)) > 0
	_rs("environment_glow_set_use_bicubic_upscale", [false if _vs("glow") == "niedrig" else bicubic])

	# Volumetrischer Nebel: Rastergroesse (Levels setzen 160x96 ueber apply_render_quality)
	var vf := _vs("vol_fog")
	var vol_sz: Vector2i = {"niedrig": Vector2i(64, 48), "mittel": Vector2i(96, 64),
		"ultra": Vector2i(224, 128)}.get(vf, Vector2i.ZERO)
	if vol_sz != Vector2i.ZERO:
		RenderingServer.environment_set_volumetric_fog_volume_size(vol_sz.x, vol_sz.y)
		_fog_volume_overridden = true
	elif _fog_volume_overridden:
		RenderingServer.environment_set_volumetric_fog_volume_size(LEVEL_FOG_VOLUME.x, LEVEL_FOG_VOLUME.y)
		_fog_volume_overridden = false


# =========================================================================== Level-Objekte

func _apply_env_node(n: Node) -> void:
	var env: Environment = null
	if n is WorldEnvironment:
		env = (n as WorldEnvironment).environment
	elif n is Camera3D:
		env = (n as Camera3D).environment
	if env != null:
		_apply_env(env, n is WorldEnvironment)


func _apply_env(env: Environment, is_world: bool = false) -> void:
	_ov(env, &"ssao_enabled", false, _vs("ssao") != "aus")
	_ov(env, &"ssil_enabled", false, _vs("ssil") != "aus")
	var ssr := _vs("ssr")
	_ov(env, &"ssr_enabled", false, ssr != "aus")
	var steps := int(_orig(env, &"ssr_max_steps"))
	if ssr == "niedrig":
		_ov(env, &"ssr_max_steps", maxi(steps >> 1, 16), false)
	elif ssr == "ultra":
		_ov(env, &"ssr_max_steps", mini(steps * 2, 256), false)
	else:
		_ov(env, &"ssr_max_steps", 0, true)
	_ov(env, &"sdfgi_enabled", false, _vs("sdfgi") != "aus")
	_ov(env, &"glow_enabled", false, _vs("glow") != "aus")

	# Volumetrischer Nebel aus -> Ersatz durch Distanznebel (Atmosphaere bleibt)
	var vf_off := _vs("vol_fog") == "aus"
	var had_vf := bool(_orig(env, &"volumetric_fog_enabled"))
	# Lichtschaefte: Level mit Bildlook, aber ohne eigenen volumetrischen Nebel bekommen einen Hauch Dunst
	var shafts := is_world and not vf_off and not had_vf and bool(_v("light_shafts")) \
		and env.tonemap_mode != Environment.TONE_MAPPER_LINEAR and env.background_mode != Environment.BG_CANVAS
	if vf_off:
		_ov(env, &"volumetric_fog_enabled", false, false)
	else:
		_ov(env, &"volumetric_fog_enabled", true, not shafts)
	var dens := 0.0035
	if bool(_orig(env, &"fog_enabled")):
		dens = clampf(float(_orig(env, &"fog_density")) * 0.6, 0.002, 0.009)
	var shaft_props := {&"volumetric_fog_density": dens, &"volumetric_fog_albedo": Color(0.78, 0.8, 0.84),
		&"volumetric_fog_anisotropy": 0.6, &"volumetric_fog_length": 96.0, &"volumetric_fog_sky_affect": 0.0,
		&"volumetric_fog_gi_inject": 0.4, &"volumetric_fog_ambient_inject": 0.0}
	for k: StringName in shaft_props:
		_ov(env, k, shaft_props[k], not shafts)
	if vf_off and had_vf:
		var base := float(_orig(env, &"fog_density")) if bool(_orig(env, &"fog_enabled")) else 0.0
		_ov(env, &"fog_enabled", true, false)
		_ov(env, &"fog_density", base + env.volumetric_fog_density * FOG_FALLBACK_K, false)
		var oc: Color = _orig(env, &"fog_light_color")
		var lit: Color = env.volumetric_fog_albedo * FOG_FALLBACK_LIGHT + env.volumetric_fog_emission * env.volumetric_fog_emission_energy
		_ov(env, &"fog_light_color", Color(maxf(oc.r, lit.r), maxf(oc.g, lit.g), maxf(oc.b, lit.b)), false)
	else:
		_ov(env, &"fog_enabled", true, true)
		_ov(env, &"fog_density", 0.0, true)
		_ov(env, &"fog_light_color", Color.BLACK, true)


func _apply_light(l: Light3D) -> void:
	if l == null:
		return
	if l is DirectionalLight3D:
		var dl := l as DirectionalLight3D
		var sh := _vs("shadows")
		var dist := float(_orig(dl, &"directional_shadow_max_distance"))
		var f: float = {"niedrig": 0.6, "mittel": 0.8}.get(sh, 1.0)
		_ov(dl, &"directional_shadow_max_distance", dist * f, f == 1.0)
		var mode := int(_orig(dl, &"directional_shadow_mode"))
		var low4 := sh == "niedrig" and mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		_ov(dl, &"directional_shadow_mode", DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS, not low4)
	else:
		_ov(l, &"shadow_enabled", false, bool(_v("light_shadows")))


func _apply_particles(n: Node) -> void:
	var ratio := _vf("particles")
	var orig := int(_orig(n, &"amount"))
	_ov(n, &"amount", maxi(1, roundi(float(orig) * ratio)), is_equal_approx(ratio, 1.0))


func _apply_post(ci: CanvasItem) -> void:
	if ci == null:
		return
	var m := ci.material as ShaderMaterial
	if m == null:
		return
	var look := _vs("look")
	var cinema := look != "original"
	# Shader tauschen (Level-Parameter bleiben erhalten)
	var want: Shader = CINEMA_SHADER if cinema else POST_FX_SHADER
	if m.shader != want:
		var keep := {}
		for k in POST_PARAMS:
			var v: Variant = m.get_shader_parameter(k)
			if v != null:
				keep[k] = v
		m.shader = want
		for k: StringName in keep:
			m.set_shader_parameter(k, keep[k])
	var layer := ci.get_parent() as CanvasLayer
	if layer != null and layer.has_meta(&"_gfx_fallback"):
		layer.visible = cinema
	for pair in [["film_grain", &"shader_parameter/grain"], ["aberration", &"shader_parameter/aberration"],
			["vignette", &"shader_parameter/vignette"]]:
		var o: Variant = _orig(m, pair[1])
		if o == null:
			continue
		_ov(m, pair[1], float(o) * _vf(pair[0]), _is_default(pair[0]))
	if cinema:
		var lut := GradeLut.make()
		m.set_shader_parameter(&"grade_lut", lut)
		m.set_shader_parameter(&"lut_size", float(GradeLut.SIZE))
		m.set_shader_parameter(&"grade_mix", 0.0 if lut == null else (1.0 if look == "kino" else 0.55))
		m.set_shader_parameter(&"sharpen", _vf("sharpen"))


## Level ohne eigenen PostFx (z. B. Rangierbahnhof, Flussuebergang, Overwatch) bekommen ein Standard-Overlay,
## damit der Kino-Look ueberall gleich wirkt. Ausnahmen: Linear-Tonemapping (Gunship-Waermebild), --nopostfx.
func _ensure_fallback_post() -> void:
	if _off or _vs("look") == "original" or Game.arg("nopostfx", false):
		return
	for n in get_tree().get_nodes_in_group(G_POST):
		if is_instance_valid(n) and n.is_inside_tree():
			return
	var we: WorldEnvironment = null
	for n in get_tree().get_nodes_in_group(G_ENV):
		if n is WorldEnvironment and n.is_inside_tree():
			var e := (n as WorldEnvironment).environment
			if e != null and e.tonemap_mode != Environment.TONE_MAPPER_LINEAR and e.background_mode != Environment.BG_CANVAS:
				we = n
				break
	if we == null or get_viewport().get_camera_3d() == null or we.get_parent() == null:
		return
	var p: Dictionary = (PostFxLib.PROFILES["day_war"] as Dictionary).duplicate()
	p["grain"] = 0.028
	var layer := PostFxLib.add_overlay(we.get_parent(), p)
	layer.name = "PostFxGfx"
	layer.set_meta(&"_gfx_fallback", true)


## Kino-Look pro Bild: Kamera-Bewegungsunschaerfe, Waffenmaske, Daempfung bei Nachtsicht/Drohne.
func _tick_cinema(delta: float) -> void:
	var posts := get_tree().get_nodes_in_group(G_POST)
	if posts.is_empty():
		_mb_cam = null
		return
	var special := false
	for n in get_tree().get_nodes_in_group(G_SPECIAL):
		if n.is_inside_tree() and (n.get("nv_on") == true or n.get("active") == true):
			special = true
			break
	_mute = move_toward(_mute, 1.0 if special else 0.0, delta * 3.0)

	var vec := Vector2.ZERO
	var mb := _vs("motion_blur")
	var vp := get_viewport()
	var cam := vp.get_camera_3d()
	if mb != "aus" and cam != null and not get_tree().paused:
		if cam == _mb_cam and cam.fov >= 40.0:
			var p := cam.global_position - _mb_basis.z * 50.0
			if not cam.is_position_behind(p):
				var size := vp.get_visible_rect().size
				if size.x > 1.0 and size.y > 1.0:
					vec = (cam.unproject_position(p) - size * 0.5) / size
					vec *= 0.35 if mb == "niedrig" else 0.7
					# Kameraschnitt/Teleport: keine Unschaerfe
					vec = Vector2.ZERO if vec.length() > 0.1 else vec.limit_length(0.035)
		_mb_cam = cam
		_mb_basis = cam.global_basis
	else:
		_mb_cam = null

	if not is_instance_valid(_mask_vp):
		_mask_vp = null
		_mask_try -= 1
		if _mask_try <= 0:
			_mask_try = 30
			var pl := Game.get_player()
			if pl != null and "weapon_viewport" in pl and pl.get("weapon_viewport") is SubViewport:
				_mask_vp = pl.get("weapon_viewport")
	for n in posts:
		var ci := n as CanvasItem
		if ci == null or not ci.is_visible_in_tree():
			continue
		var m := ci.material as ShaderMaterial
		if m == null or m.shader != CINEMA_SHADER:
			continue
		m.set_shader_parameter(&"blur_vec", vec)
		m.set_shader_parameter(&"fx_mute", _mute)
		if _mask_vp != null:
			m.set_shader_parameter(&"weapon_mask", _mask_vp.get_texture())
			m.set_shader_parameter(&"use_weapon_mask", 1.0)
		else:
			m.set_shader_parameter(&"use_weapon_mask", 0.0)


# =========================================================================== Anisotrope Filterung

## Godot-Materialien filtern standardmaessig nur trilinear (LINEAR_WITH_MIPMAPS) – dann wirkt die
## anisotrope Filterung des Viewports gar nicht und flache Boeden werden matschig/flimmernd. Alle Level-,
## Modell- und Waffenmaterialien mit Texturen werden einmalig auf den anisotropen Filter umgestellt
## (die Staerke regelt die Option "Anisotrope Filterung" am Viewport).
func _aniso_geo(g: GeometryInstance3D) -> void:
	_aniso_mat(g.material_override)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		if mesh != null:
			for i in mini(mesh.get_surface_count(), mi.get_surface_override_material_count()):
				_aniso_mat(mi.get_surface_override_material(i))
	elif g is MultiMeshInstance3D:
		var mm := (g as MultiMeshInstance3D).multimesh
		if mm != null:
			mesh = mm.mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			_aniso_mat(mesh.surface_get_material(i))


func _aniso_mat(m: Material) -> void:
	if m == null:
		return
	var id := m.get_instance_id()
	if _aniso_done.has(id):
		return
	if _aniso_done.size() > 50000:
		_aniso_done.clear()
	_aniso_done[id] = true
	var bm := m as BaseMaterial3D
	if bm == null:
		return
	if bm.texture_filter == BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS \
			and (bm.albedo_texture != null or bm.normal_texture != null):
		bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if bm.next_pass != null:
		_aniso_mat(bm.next_pass)


# =========================================================================== Anzeige-Kalibrierung / Overlay

func _apply_adjust() -> void:
	var neutral := _is_default("brightness") and _is_default("contrast") and _is_default("gamma")
	if neutral:
		if _adjust_layer != null:
			_adjust_layer.visible = false
		return
	if _adjust_layer == null:
		_adjust_layer = CanvasLayer.new()
		_adjust_layer.name = "GfxAdjust"
		_adjust_layer.layer = 126
		var rect := ColorRect.new()
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_adjust_mat = ShaderMaterial.new()
		_adjust_mat.shader = ADJUST_SHADER
		rect.material = _adjust_mat
		_adjust_layer.add_child(rect)
		add_child(_adjust_layer)
	_adjust_layer.visible = true
	_adjust_mat.set_shader_parameter("brightness", _vf("brightness"))
	_adjust_mat.set_shader_parameter("contrast", _vf("contrast"))
	_adjust_mat.set_shader_parameter("gamma", _vf("gamma"))


func _apply_fps_overlay() -> void:
	var on := bool(_v("fps_overlay"))
	if on and _fps_overlay == null:
		_fps_overlay = FPS_OVERLAY_SCRIPT.new()
		_fps_overlay.name = "FpsOverlay"
		add_child(_fps_overlay)
	elif not on and _fps_overlay != null:
		_fps_overlay.queue_free()
		_fps_overlay = null


# =========================================================================== Anzeige (Fenster, VSync, Limit)

## Beim Start nur anwenden, was der Spieler wirklich gespeichert hat (Kommandozeilen-Fenstergroessen der Tools
## und die project.godot-Werte bleiben sonst unangetastet).
func _apply_display_stored() -> void:
	if Settings.has(P + "window_mode") or Settings.has(P + "resolution"):
		_apply_window()
	if Settings.has(P + "vsync"):
		_apply_vsync()
	if Settings.has(P + "fps_limit"):
		_apply_fps_limit()


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


func _apply_window() -> void:
	if _headless():
		return
	var cur := DisplayServer.window_get_mode()
	match _vs("window_mode"):
		"randlos":
			if cur != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"vollbild":
			if cur != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		_:
			if cur == DisplayServer.WINDOW_MODE_FULLSCREEN or cur == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var r := _vs("resolution")
			if r != "auto":
				var wh := _parse_res(r)
				var screen := DisplayServer.window_get_current_screen()
				var usable := DisplayServer.screen_get_usable_rect(screen)
				DisplayServer.window_set_size(wh)
				DisplayServer.window_set_position(usable.position + (usable.size - wh) / 2)
	_apply_viewport()


func _apply_vsync() -> void:
	if _headless():
		return
	var m: int = {"aus": DisplayServer.VSYNC_DISABLED, "an": DisplayServer.VSYNC_ENABLED,
		"adaptiv": DisplayServer.VSYNC_ADAPTIVE, "mailbox": DisplayServer.VSYNC_MAILBOX}.get(_vs("vsync"),
		DisplayServer.VSYNC_ENABLED)
	DisplayServer.window_set_vsync_mode(m as DisplayServer.VSyncMode)


func _apply_fps_limit() -> void:
	Engine.max_fps = int(_v("fps_limit"))


static func _parse_res(r: String) -> Vector2i:
	var p := r.split("x")
	if p.size() != 2:
		return Vector2i(1920, 1080)
	return Vector2i(int(p[0]), int(p[1]))


# =========================================================================== Benchmark (--gfx-bench)

func _process(delta: float) -> void:
	if not _off:
		_tick_cinema(delta)
	if _bench_secs <= 0.0:
		return
	var now := Time.get_ticks_usec()
	var dt := 0.0 if _bench_last_us == 0 else float(now - _bench_last_us) / 1000000.0
	_bench_last_us = now
	var vp := get_viewport()
	match _bench_state:
		0:
			if vp.get_camera_3d() != null:
				_bench_state = 1
				_bench_t = 0.0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				Engine.max_fps = 0
				RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
		1:
			# --gfx-cycle=<preset>: Laufzeit-Wechsel testen (z. B. niedrig -> hoch muss das Original ergeben)
			var cyc := str(Game.arg("gfx-cycle", ""))
			if cyc != "" and _bench_t < 2.0 and _bench_t + dt >= 2.0 and not _off:
				Settings.set_value(P + "preset", cyc)
				print("[graphics] Laufzeit-Wechsel auf ", cyc, " -> ", current_preset())
			_bench_t += dt
			if _bench_t >= _bench_warmup:
				var shot := str(Game.arg("gfx-shot", ""))
				if shot != "":
					var path := shot if shot.is_absolute_path() else ProjectSettings.globalize_path("res://" + shot)
					DirAccess.make_dir_recursive_absolute(path.get_base_dir())
					vp.get_texture().get_image().save_png(path)
					print("[graphics] Screenshot: ", path)
				_bench_state = 2
				_bench_t = 0.0
				_bench_frames = 0
				_bench_gpu = 0.0
				_bench_worst = PackedFloat32Array()
		2:
			_bench_t += dt
			_bench_frames += 1
			_bench_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
			_bench_worst.append(dt * 1000.0)
			if _bench_t >= _bench_secs:
				_bench_worst.sort()
				var p99 := _bench_worst[clampi(int(_bench_worst.size() * 0.99), 0, _bench_worst.size() - 1)]
				print("GFX_BENCH preset=%s level=%s fps=%.1f frame_ms=%.2f p99_ms=%.2f gpu_ms=%.2f size=%s scale=%.2f mode=%d msaa=%d ssaa=%d taa=%s" % [
					current_preset(), str(Game.arg("level", "?")), float(_bench_frames) / _bench_t,
					1000.0 * _bench_t / float(_bench_frames), p99, _bench_gpu / float(_bench_frames),
					str(vp.get_visible_rect().size), vp.scaling_3d_scale, vp.scaling_3d_mode, vp.msaa_3d,
					vp.screen_space_aa, str(vp.use_taa)])
				_bench_secs = 0.0
				get_tree().quit()
