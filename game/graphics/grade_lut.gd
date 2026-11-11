extends RefCounted
## Erzeugt die Farb-LUT fuer den Kino-Look (Teal-Orange wie moderne Militaer-Shooter) per Skript.
## Keine Bilddatei noetig: Graphics ruft GradeLut.make() einmal auf und reicht die 3D-Textur an
## cinema_post.gdshader weiter. Texel i einer Achse speichert die Farbe fuer den Eingangswert i/(n-1)
## (der Shader rechnet die Texelmitten passend um).
##
## Aufbau (im Anzeige-/sRGB-Raum, nach dem Tonemapping):
##   - sanfte S-Kurve (mehr Kontrast in den Mitteltoenen, Schwarz/Weiss bleiben)
##   - Tiefen leicht blaugruen (Teal), Lichter leicht warm (Orange)
##   - Gruentoene etwas entsaettigt/olivfarben, Haut-/Orangetoene leicht kraeftiger
##   - minimale Gesamtentsaettigung

const SIZE := 32

static var _cache: ImageTexture3D


static func make() -> ImageTexture3D:
	if _cache != null:
		return _cache
	var n := SIZE
	var images: Array[Image] = []
	for bz in n:
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for gy in n:
			for rx in n:
				var c := grade(Color(float(rx) / (n - 1), float(gy) / (n - 1), float(bz) / (n - 1)))
				img.set_pixel(rx, gy, Color(c.r, c.g, c.b, 1.0))
		images.append(img)
	var tex := ImageTexture3D.new()
	var err := tex.create(Image.FORMAT_RGBA8, n, n, n, false, images)
	if err != OK:
		push_warning("[graphics] Farb-LUT konnte nicht erzeugt werden (%d)" % err)
		return null
	_cache = tex
	return tex


## Die eigentliche Farbabstimmung fuer einen Eingangswert (0..1 je Kanal).
static func grade(src: Color) -> Color:
	var c := Vector3(src.r, src.g, src.b)
	# S-Kurve, 18 % Anteil
	var sc := Vector3(_smooth(c.x), _smooth(c.y), _smooth(c.z))
	c = c.lerp(sc, 0.18)
	var l := c.dot(Vector3(0.2126, 0.7152, 0.0722))
	# Split-Toning: Tiefen Teal, Lichter warm
	var shadow_w := pow(1.0 - l, 2.2)
	var high_w := pow(l, 1.8)
	c += Vector3(-0.012, 0.010, 0.028) * shadow_w
	c += Vector3(0.030, 0.010, -0.026) * high_w
	# Farbtonabhaengige Saettigung
	var col := Color(clampf(c.x, 0.0, 1.0), clampf(c.y, 0.0, 1.0), clampf(c.z, 0.0, 1.0))
	var h := col.h
	var s := col.s
	var v := col.v
	var green := _hue_bell(h, 0.30, 0.12)      # Gelbgruen..Gruen
	var orange := _hue_bell(h, 0.07, 0.07)     # Haut, Feuer, Ziegel
	s *= 1.0 - 0.22 * green
	s *= 1.0 + 0.10 * orange
	h = lerpf(h, 0.22, 0.25 * green)            # Gruen Richtung Oliv
	s *= 0.95
	col = Color.from_hsv(h, clampf(s, 0.0, 1.0), v)
	return col


static func _smooth(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Glockenfoermige Gewichtung um einen Farbton (zyklisch, 0..1).
static func _hue_bell(h: float, center: float, width: float) -> float:
	var dh := absf(h - center)
	dh = minf(dh, 1.0 - dh)
	return clampf(1.0 - dh / width, 0.0, 1.0)
