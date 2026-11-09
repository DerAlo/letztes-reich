extends SceneTree
## Erzeugt prozedurale VFX-Texturen (CC0, selbst generiert).
## Aufruf: godot --headless --path . --script res://assets/vfx/gen_textures.gd

func _init() -> void:
	_gen_noise_tile()
	_gen_burn_mark()
	_gen_bullet_hole()
	_find_sun()
	quit()

func _fbm(seed_: int, freq: float, type: int = FastNoiseLite.TYPE_SIMPLEX_SMOOTH, octaves: int = 5) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_
	n.noise_type = type
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	n.fractal_gain = 0.5
	if type == FastNoiseLite.TYPE_CELLULAR:
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	var img := n.get_seamless_image(512, 512, false, false, 0.2, true)
	img.convert(Image.FORMAT_RF)
	return img

func _gen_noise_tile() -> void:
	var a := _fbm(11, 0.012)
	var b := _fbm(23, 0.02, FastNoiseLite.TYPE_CELLULAR, 4)
	var c := _fbm(37, 0.03, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 4)
	var out := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	for y in 512:
		for x in 512:
			var r := clampf(a.get_pixel(x, y).r, 0, 1)
			var g := clampf(1.0 - b.get_pixel(x, y).r, 0, 1)
			var bl := clampf(c.get_pixel(x, y).r, 0, 1)
			out.set_pixel(x, y, Color(r, g, bl, 1.0))
	out.save_png("res://assets/vfx/noise_tile.png")
	print("noise_tile.png ok")

func _gen_burn_mark() -> void:
	var size := 512
	var fn := FastNoiseLite.new()
	fn.seed = 5
	fn.frequency = 0.9
	fn.fractal_octaves = 4
	var fine := FastNoiseLite.new()
	fine.seed = 9
	fine.frequency = 0.03
	fine.fractal_octaves = 4
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(x, y) / size - Vector2(0.5, 0.5)) * 2.0
			var d := p.length()
			var ang := atan2(p.y, p.x)
			var rays := fn.get_noise_2d(cos(ang) * 1.6, sin(ang) * 1.6) * 0.5 + 0.5
			var edge := 0.42 + rays * 0.5
			var core := smoothstep(edge, edge * 0.35, d)
			var grain := fine.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf(core * (0.55 + grain * 0.6), 0, 1)
			var c := Color(0.03, 0.025, 0.02) * (0.6 + grain * 0.8)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, a * 0.95))
	out.save_png("res://assets/vfx/burn_mark.png")
	print("burn_mark.png ok")

func _gen_bullet_hole() -> void:
	var size := 128
	var fn := FastNoiseLite.new()
	fn.seed = 3
	fn.frequency = 0.08
	var out := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var p := (Vector2(x, y) / size - Vector2(0.5, 0.5)) * 2.0
			var d := p.length()
			var n := fn.get_noise_2d(x, y) * 0.5 + 0.5
			var hole := smoothstep(0.22, 0.1, d)
			var chip := smoothstep(0.85 * (0.6 + n * 0.5), 0.2, d) * 0.55
			var a := clampf(maxf(hole, chip), 0, 1)
			var c := Color(0.02, 0.02, 0.02).lerp(Color(0.12, 0.1, 0.09), 1.0 - hole)
			out.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	out.save_png("res://assets/vfx/bullet_hole.png")
	print("bullet_hole.png ok")

func _find_sun() -> void:
	var img := Image.new()
	var err := img.load("res://assets/hdri/kloppenheim_01_puresky_2k.hdr")
	if err != OK:
		print("hdr load failed ", err)
		return
	var best := 0.0
	var bp := Vector2i.ZERO
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var c := img.get_pixel(x, y)
			var l := c.r + c.g + c.b
			if l > best:
				best = l
				bp = Vector2i(x, y)
	print("HDRI size ", img.get_size(), " brightest at ", bp, " value ", best, " uv ", Vector2(bp) / Vector2(img.get_size()))
