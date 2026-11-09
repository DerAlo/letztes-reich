extends SceneTree
## Erzeugt das Rauch-Flipbook (8x8 Frames a 128 px, selbst generiert, CC0).
## Aufruf: godot --headless --path . --script res://assets/vfx/gen_smoke.gd
##
## Aufbau pro Frame: weiche Rauchwolke aus mehrschichtigem, domain-gewarptem fBm-Noise mit
## radialer Maske. Benachbarte Frames sind Schnitte durch dasselbe 3D-Noise mit kleinem z-Versatz,
## d. h. Frame k und k+1 sind sich aehnlich: der Shader blendet waehrend der Lebenszeit von einem
## zufaelligen Start-Frame ueber einige Folge-Frames und der Rauch "quillt" dadurch weich.
## Kanaele: R,G = Normale (x,y, Bildraum, y nach unten), B = geglaettete Dichte (Dicke), A = Dichte.

const CELL := 128
const GRID := 8
const DZ := 7.0          # z-Versatz pro Frame (Noise-Einheiten = Pixel)

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var img := Image.create(CELL * GRID, CELL * GRID, false, Image.FORMAT_RGBA8)
	var detail := FastNoiseLite.new()
	detail.seed = 1337
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail.frequency = 1.0 / 46.0
	detail.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail.fractal_octaves = 6
	detail.fractal_gain = 0.52
	detail.fractal_lacunarity = 2.0
	detail.domain_warp_enabled = true
	detail.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	detail.domain_warp_amplitude = 20.0
	detail.domain_warp_frequency = 1.0 / 70.0
	detail.domain_warp_fractal_type = FastNoiseLite.DOMAIN_WARP_FRACTAL_PROGRESSIVE
	detail.domain_warp_fractal_octaves = 3
	var wx := FastNoiseLite.new()
	wx.seed = 77
	wx.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wx.frequency = 1.0 / 110.0
	wx.fractal_octaves = 2
	var wy := wx.duplicate() as FastNoiseLite
	wy.seed = 91

	for f in GRID * GRID:
		var z := f * DZ
		var dens := PackedFloat32Array()
		dens.resize(CELL * CELL)
		for y in CELL:
			for x in CELL:
				var u := (x + 0.5) / CELL * 2.0 - 1.0
				var v := (y + 0.5) / CELL * 2.0 - 1.0
				# Grob-Form: radial, mit niederfrequentem Warp (keine Kreisscheibe)
				var px := float(x)
				var py := float(y)
				var ox := wx.get_noise_3d(px, py, z) * 0.38
				var oy := wy.get_noise_3d(px, py, z) * 0.38
				var r := Vector2(u + ox, v + oy).length()
				var base := 1.0 - smoothstep(0.15, 0.95, r)
				var n := detail.get_noise_3d(px, py, z) * 0.5 + 0.5   # ~0..1
				var d := base * (0.15 + n * 1.25) - 0.1
				d = clampf(d / 0.95, 0.0, 1.0)
				d = d * d * (3.0 - 2.0 * d)
				# harte Garantie: Rand der Zelle ist leer (kein Bluten in Nachbar-Frames)
				var edge := maxf(absf(u), absf(v))
				d *= 1.0 - smoothstep(0.82, 0.97, edge)
				dens[y * CELL + x] = d
		var smooth := _blur(dens, 4)
		var cx := (f % GRID) * CELL
		var cy := (f / GRID) * CELL
		for y in CELL:
			for x in CELL:
				# Normale aus Gradient einer "Kuppel" (geglaettete Dichte)
				var hl := smooth[y * CELL + maxi(x - 2, 0)]
				var hr := smooth[y * CELL + mini(x + 2, CELL - 1)]
				var hu := smooth[maxi(y - 2, 0) * CELL + x]
				var hd := smooth[mini(y + 2, CELL - 1) * CELL + x]
				var nrm := Vector3((hl - hr) * 5.0, (hu - hd) * 5.0, 1.0).normalized()
				var d := dens[y * CELL + x]
				img.set_pixel(cx + x, cy + y, Color(nrm.x * 0.5 + 0.5, nrm.y * 0.5 + 0.5, smooth[y * CELL + x], d))
	img.save_png("res://assets/vfx/smoke_flipbook.png")
	print("smoke_flipbook.png ok (%d ms)" % (Time.get_ticks_msec() - t0))
	quit()

## Box-Blur (zwei Durchgaenge, separabel) innerhalb einer Zelle.
func _blur(src: PackedFloat32Array, rad: int) -> PackedFloat32Array:
	var a := src
	for pass_i in 2:
		var tmp := PackedFloat32Array()
		tmp.resize(CELL * CELL)
		for y in CELL:
			for x in CELL:
				var s := 0.0
				for k in range(-rad, rad + 1):
					s += a[y * CELL + clampi(x + k, 0, CELL - 1)]
				tmp[y * CELL + x] = s / (rad * 2 + 1)
		var out := PackedFloat32Array()
		out.resize(CELL * CELL)
		for y in CELL:
			for x in CELL:
				var s := 0.0
				for k in range(-rad, rad + 1):
					s += tmp[clampi(y + k, 0, CELL - 1) * CELL + x]
				out[y * CELL + x] = s / (rad * 2 + 1)
		a = out
	return a
