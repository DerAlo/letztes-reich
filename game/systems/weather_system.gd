extends Node3D
## Wetter-System (opt-in, wiederverwendbar). Das Level legt es an:
##   var wx = preload("res://game/systems/weather_system.gd").new()
##   wx.mode = "blizzard"; add_child(wx)
## Modi: "clear", "snow" (leichter Schneefall), "blizzard" (Sturm in Wellen mit Sichtfenstern),
##       "rain" (delegiert an game/vfx/weather.gd – Hook fuer spaeter, Regen/Gewitter).
## Leistung: zwei GPUParticles3D (Weltkoordinaten, folgen der Kamera, Dichte ueber amount_ratio),
## kein Node pro Flocke. Steuert Tiefen- und Volumennebel der WorldEnvironment (stellt beim Entfernen
## alles wieder her), Windgeraeusch auf Bus "Ambient" und einen Tiefpass auf Bus "SFX" (gedaempfter Klang).
##
## Abfragen:  visibility() 0 (Whiteout) .. 1 (klar), visibility_range() in m, is_window_open(),
##            wind() (m/s, Weltvektor), sight_factor() (fuer Gegner-Sichtweite).
## Steuerung: set_mode(m, blend), set_intensity(v, blend), open_window(dauer), close_window(dauer),
##            set_waves(an).  Signale: window_changed(open), mode_changed(mode),
##            wave_warning(kind, sekunden) ("window" | "storm", einmal je Wechsel, warn_time vorher).
## HUD/Funk:  wave_phase() storm|down|window|up, seconds_to_window(), seconds_to_storm(), gust() 0..1.
## Schnee: feine, unregelmaessige Flocken (Fern-/Nahschicht) plus bodennahes Treibschnee-Band in Boeen.

signal window_changed(open: bool)
signal mode_changed(mode: String)
signal wave_warning(kind: String, seconds: float)

const RainScript = preload("res://game/vfx/weather.gd")

@export var mode: String = "snow"
@export_range(0.0, 1.0) var base_intensity: float = 0.75      ## Sturmstaerke auf dem Wellenkamm
@export_range(0.0, 1.0) var window_intensity: float = 0.18    ## Staerke im Sichtfenster
@export var storm_duration: Vector2 = Vector2(24.0, 34.0)     ## Sturmphase (s, zufaellig)
@export var window_duration: Vector2 = Vector2(24.0, 32.0)    ## Sichtfenster (s, zufaellig)
@export var ramp_time: float = 5.0                            ## Uebergang Sturm <-> Fenster (s)
@export var warn_time: float = 10.0                           ## wave_warning so viele s vor dem Wechsel
@export var wind_base: Vector3 = Vector3(7.0, 0.0, 2.5)       ## Grundwind (m/s) bei voller Staerke
@export var particle_amount: int = 6000
@export var fall_speed: float = 2.2
@export var snow_color: Color = Color(0.92, 0.94, 0.98)
@export var fog_color: Color = Color(0.78, 0.81, 0.86)
@export var clear_fog_density: float = 0.0035                 ## Tiefennebel bei Intensitaet 0
@export var storm_fog_density: float = 0.013                  ## ... bei Intensitaet 1 (~175 m Sicht)
@export var volumetric_max: float = 0.012
@export var drift_amount: int = 900                           ## Treibschnee-Partikel (bodennah, in Boeen)
@export var window_threshold: float = 0.6                     ## visibility() ab der ein Fenster "offen" ist
@export var manage_environment: bool = true
@export var muffle: bool = true
@export var wind_volume_db: Vector2 = Vector2(-30.0, -7.0)
@export var wind_sound: String = "alpenpass_blizzard_loop"    ## Fallback: amb_wind
@export var seed_value: int = 1506

var intensity: float = 0.0          ## aktuelle (geglaettete) Staerke 0..1
var _target: float = 0.0
var _blend: float = 3.0
var _waves: bool = true
var _wave_state: String = "storm"   ## storm | down | window | up
var _wave_t: float = 0.0
var _hold_t: float = 0.0
var _forced: String = ""            ## "" | "window" | "storm" (nur ohne Wellen / andere Modi)
var _forced_t: float = 0.0
var _next_hold: float = -1.0        ## erzwungene Dauer der naechsten Fenster-/Sturmphase
var _warned: bool = false
var _gust: float = 0.0
var _manual: float = -1.0
var _win_open: bool = false
var _t: float = 0.0
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _wind := Vector3.ZERO

var _far: GPUParticles3D
var _near: GPUParticles3D
var _far_mat: ParticleProcessMaterial
var _near_mat: ParticleProcessMaterial
var _drift: GPUParticles3D
var _drift_mat: ParticleProcessMaterial
var _flake_tex: Texture2D
var _rain: Node3D
var _wind_snd: AudioStreamPlayer
var _env: Environment
var _env_saved: Dictionary = {}
var _lp: AudioEffectLowPassFilter
var _lp_bus: int = -1

func _ready() -> void:
	_rng.seed = seed_value
	_noise.seed = seed_value
	_noise.frequency = 1.0
	_hold_t = _rng.randf_range(storm_duration.x, storm_duration.y) * 0.5
	_build_snow()
	_build_audio()
	_capture_env.call_deferred()
	_apply_mode(true)

func _exit_tree() -> void:
	_restore_env()
	if _lp != null and _lp_bus >= 0 and _lp_bus < AudioServer.bus_count:
		for i in AudioServer.get_bus_effect_count(_lp_bus):
			if AudioServer.get_bus_effect(_lp_bus, i) == _lp:
				AudioServer.remove_bus_effect(_lp_bus, i)
				break
	_lp = null

# ------------------------------------------------------------------ Oeffentlich

func set_mode(m: String, blend: float = 3.0) -> void:
	if m == mode:
		return
	mode = m
	_blend = maxf(blend, 0.05)
	_apply_mode(false)
	mode_changed.emit(mode)

## Feste Staerke (schaltet die Wellen ab); v < 0 gibt die Wellen wieder frei.
func set_intensity(v: float, blend: float = 3.0) -> void:
	_manual = v
	_blend = maxf(blend, 0.05)

func set_waves(on: bool) -> void:
	_waves = on

## Erzwingt ein Sichtfenster fuer dauer Sekunden (Skript-Momente, Tutorials). Laeuft ueber die Wellen
## (Uebergang + Countdown bleiben stimmig); ohne Wellen als harte Vorgabe.
func open_window(dauer: float) -> void:
	if mode == "blizzard" and _waves and _manual < 0.0:
		_forced = ""
		match _wave_state:
			"window":
				_hold_t = maxf(_hold_t, dauer)
			"down":
				_next_hold = dauer
			_:
				_wave_state = "down"
				_wave_t = 0.0
				_hold_t = ramp_time
				_next_hold = dauer
				_warned = true
		return
	_forced = "window"
	_forced_t = dauer

## Erzwingt Sturm (kein Fenster) fuer dauer Sekunden.
func close_window(dauer: float) -> void:
	if mode == "blizzard" and _waves and _manual < 0.0:
		_forced = ""
		match _wave_state:
			"storm":
				_hold_t = maxf(_hold_t, dauer)
			"up":
				_next_hold = dauer
			_:
				_wave_state = "up"
				_wave_t = 0.0
				_hold_t = ramp_time
				_next_hold = dauer
				_warned = true
		return
	_forced = "storm"
	_forced_t = dauer

func wave_phase() -> String:
	if _forced != "":
		return _forced
	return _wave_state if (mode == "blizzard" and _waves) else "storm"

## Sekunden, bis das naechste Sichtfenster offen ist (0 = jetzt offen).
func seconds_to_window() -> float:
	match wave_phase():
		"window":
			return 0.0
		"down":
			return maxf(_hold_t, 0.0)
		"storm":
			return maxf(_hold_t, 0.0) + ramp_time
		"up":
			return maxf(_hold_t, 0.0) + storm_duration.x + ramp_time
	return 0.0

## Sekunden, bis der Sturm wieder zuzieht (nur im Fenster/Uebergang sinnvoll).
func seconds_to_storm() -> float:
	match wave_phase():
		"window":
			return maxf(_hold_t, 0.0)
		"down":
			return maxf(_hold_t, 0.0) + window_duration.x
	return 0.0

## Boeenstaerke 0..1 (Treibschnee, HUD).
func gust() -> float:
	return _gust

## 0 = volle Sturmsicht, 1 = Sicht wie im Fenster (oder besser).
func visibility() -> float:
	var lo := 2.302585 / maxf(storm_fog_density, 0.0001)
	var hi := 2.302585 / maxf(_fog_at(window_intensity), 0.0001)
	return clampf((visibility_range() - lo) / maxf(hi - lo, 1.0), 0.0, 1.0)

## Sichtweite (m), bei der der Kontrast auf 10 % faellt.
func visibility_range() -> float:
	return 2.302585 / maxf(_fog_density(), 0.0001)

func is_window_open() -> bool:
	return visibility() >= window_threshold

func wind() -> Vector3:
	return _wind

## Faktor fuer Gegner-Sichtweiten (0.55 im Sturm .. 1 klar).
func sight_factor() -> float:
	return lerpf(0.55, 1.0, visibility())

## Sekunden bis zum naechsten Wellenwechsel (fuer Bots/HUD, grob).
func time_to_change() -> float:
	return _hold_t

# ------------------------------------------------------------------ Aufbau

## 2x2-Atlas unregelmaessiger Flocken (Klumpen aus 3-6 Kernen, weiche Kante) statt runder Punkte.
func _flake_texture() -> Texture2D:
	var n := 32
	var img := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = 4711
	for cell in 4:
		var ox := (cell % 2) * n
		var oy := (cell / 2) * n
		var blobs: Array[Vector3] = []
		for b in r.randi_range(3, 6):
			blobs.append(Vector3(r.randf_range(-5.0, 5.0), r.randf_range(-5.0, 5.0), r.randf_range(2.5, 5.5)))
		for y in n:
			for x in n:
				var a := 0.0
				for bl in blobs:
					var d := Vector2(x - n * 0.5 + 0.5 - bl.x, y - n * 0.5 + 0.5 - bl.y).length() / bl.z
					a = maxf(a, clampf(1.0 - d, 0.0, 1.0))
				img.set_pixel(ox + x, oy + y, Color(1, 1, 1, pow(a, 1.6)))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Weicher Fleck fuer Treibschnee (ueber das Quad in Windrichtung gestreckt).
func _streak_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _flake_mat(size_px: float, streak: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = snow_color
	if streak:
		m.albedo_texture = _streak_texture()
	else:
		if _flake_tex == null:
			_flake_tex = _flake_texture()
		m.albedo_texture = _flake_tex
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
	m.disable_receive_shadows = true
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = size_px
	return m

func _make_emitter(amount: int, box: Vector3, size: float, life: float, streak: bool = false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(amount, 16)
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.fixed_fps = 30
	p.interpolate = true
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = fall_speed * 0.6
	pm.initial_velocity_max = fall_speed * 1.3
	pm.gravity = Vector3(0, -fall_speed, 0)
	pm.damping_min = 0.4
	pm.damping_max = 1.2
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 2.5
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.25
	pm.color = Color(1, 1, 1, 0.85)
	if not streak:
		pm.anim_offset_min = 0.0
		pm.anim_offset_max = 1.0
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -90.0
		pm.angular_velocity_max = 90.0
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _flake_mat(size * 6.0, streak)
	p.draw_pass_1 = q
	add_child(p)
	return p

func _build_snow() -> void:
	_far = _make_emitter(particle_amount, Vector3(26.0, 9.0, 26.0), 0.04, 6.0)
	_far.name = "SnowFar"
	_far_mat = _far.process_material as ParticleProcessMaterial
	_near = _make_emitter(maxi(particle_amount / 5, 64), Vector3(5.0, 3.5, 5.0), 0.026, 2.2)
	_near.name = "SnowNear"
	_near_mat = _near.process_material as ParticleProcessMaterial
	_near_mat.scale_min = 0.5
	_near_mat.scale_max = 1.6
	# Treibschnee: flache Schicht knapp ueber dem Boden, schnell in Windrichtung, nur in Boeen dicht
	if drift_amount > 0:
		_drift = _make_emitter(drift_amount, Vector3(18.0, 0.6, 18.0), 1.0, 1.6, true)
		_drift.name = "SnowDrift"
		_drift_mat = _drift.process_material as ParticleProcessMaterial
		_drift_mat.direction = Vector3(1, 0.05, 0)
		_drift_mat.spread = 8.0
		_drift_mat.gravity = Vector3.ZERO
		_drift_mat.damping_min = 0.0
		_drift_mat.damping_max = 0.2
		_drift_mat.scale_min = 0.6
		_drift_mat.scale_max = 1.8
		_drift_mat.color = Color(1, 1, 1, 0.16)
		_drift_mat.turbulence_noise_strength = 1.2
		_drift_mat.turbulence_influence_max = 0.12
		(_drift.draw_pass_1 as QuadMesh).size = Vector2(2.4, 0.5)

func _build_audio() -> void:
	var nm := wind_sound if ResourceLoader.exists("res://assets/sfx/%s.ogg" % wind_sound) else "amb_wind"
	var path := "res://assets/sfx/%s.ogg" % nm
	if not ResourceLoader.exists(path):
		return
	var st := load(path) as AudioStreamOggVorbis
	if st == null:
		return
	st = st.duplicate() as AudioStreamOggVorbis
	st.loop = true
	_wind_snd = AudioStreamPlayer.new()
	_wind_snd.stream = st
	_wind_snd.bus = &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master"
	_wind_snd.volume_db = wind_volume_db.x
	add_child(_wind_snd)
	_wind_snd.play()
	if muffle:
		_lp_bus = AudioServer.get_bus_index(&"SFX")
		if _lp_bus >= 0:
			_lp = AudioEffectLowPassFilter.new()
			_lp.cutoff_hz = 20000.0
			_lp.resonance = 0.5
			AudioServer.add_bus_effect(_lp_bus, _lp)

func _capture_env() -> void:
	if not manage_environment or not is_inside_tree():
		return
	var we: WorldEnvironment = null
	var scene := get_tree().current_scene
	for n in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		we = n as WorldEnvironment
		if scene != null and scene.is_ancestor_of(n):
			break
	if we == null or we.environment == null:
		return
	_env = we.environment
	_env_saved = {
		"fog_enabled": _env.fog_enabled, "fog_density": _env.fog_density, "fog_light_color": _env.fog_light_color,
		"fog_sky_affect": _env.fog_sky_affect, "fog_aerial_perspective": _env.fog_aerial_perspective,
		"volumetric_fog_enabled": _env.volumetric_fog_enabled, "volumetric_fog_density": _env.volumetric_fog_density,
		"volumetric_fog_albedo": _env.volumetric_fog_albedo,
	}
	_env.fog_enabled = true
	_env.fog_light_color = fog_color
	_env.fog_sky_affect = 1.0
	_env.fog_aerial_perspective = 0.0
	_env.volumetric_fog_enabled = true
	_env.volumetric_fog_albedo = fog_color

func _restore_env() -> void:
	if _env == null or _env_saved.is_empty():
		return
	for k: String in _env_saved:
		_env.set(k, _env_saved[k])
	_env_saved.clear()

func _apply_mode(instant: bool) -> void:
	var snowy := mode == "snow" or mode == "blizzard"
	if _far != null:
		_far.emitting = snowy
		_near.emitting = snowy and mode == "blizzard"
		if _drift != null:
			_drift.emitting = mode == "blizzard"
	if mode == "rain":
		if _rain == null:
			_rain = RainScript.new()
			_rain.set("lightning", false)
			add_child(_rain)
	elif _rain != null:
		_rain.queue_free()
		_rain = null
	_target = _mode_target()
	if instant:
		intensity = _target

func _mode_target() -> float:
	if _manual >= 0.0:
		return _manual
	match mode:
		"clear":
			return 0.0
		"snow":
			return 0.25
		"rain":
			return 0.4
		"blizzard":
			if _forced == "window":
				return window_intensity
			if _forced == "storm":
				return base_intensity
			if not _waves:
				return base_intensity
			match _wave_state:
				"window":
					return window_intensity
				"down":
					return lerpf(base_intensity, window_intensity, clampf(_wave_t / ramp_time, 0.0, 1.0))
				"up":
					return lerpf(window_intensity, base_intensity, clampf(_wave_t / ramp_time, 0.0, 1.0))
			return base_intensity
	return 0.0

func _fog_density() -> float:
	return _fog_at(intensity)

func _fog_at(i: float) -> float:
	return lerpf(clear_fog_density, storm_fog_density, pow(clampf(i, 0.0, 1.0), 1.25))

# ------------------------------------------------------------------ Laufzeit

func _process(delta: float) -> void:
	_t += delta
	_tick_waves(delta)
	_target = _mode_target()
	# Geglaettete Staerke plus feine Boeen (nur im Sturm)
	var k := 1.0 - exp(-delta * 3.0 / maxf(_blend * 0.5, 0.05))
	intensity = lerpf(intensity, _target, k)
	var gust := 0.06 * _noise.get_noise_1d(_t * 0.7) * (1.0 if mode == "blizzard" else 0.0)
	var eff := clampf(intensity + gust, 0.0, 1.0)
	_gust = clampf((0.5 + 1.6 * _noise.get_noise_1d(_t * 0.22 + 300.0)) * (0.35 + intensity), 0.0, 1.0) if mode == "blizzard" else 0.0
	# Wind: Grundwind skaliert mit der Staerke, Boeen ueber Rauschen, Richtung pendelt
	var wk := (0.25 + eff) * (1.0 + 0.3 * _noise.get_noise_1d(_t * 0.05 + 50.0) + 0.12 * _noise.get_noise_1d(_t * 0.6 + 90.0))
	_wind = wind_base.rotated(Vector3.UP, 0.25 * _noise.get_noise_1d(_t * 0.04 + 200.0)) * wk
	_update_particles(eff)
	_update_env(eff)
	_update_audio(eff)
	var open := is_window_open()
	if open != _win_open:
		_win_open = open
		window_changed.emit(open)
	if _rain != null:
		_rain.set("rain_strength", eff)

func _tick_waves(delta: float) -> void:
	if _forced != "":
		_forced_t -= delta
		if _forced_t <= 0.0:
			_forced = ""
	if mode != "blizzard" or not _waves:
		return
	_wave_t += delta
	_hold_t -= delta
	# Vorwarnung (Funk/HUD): "Boee laesst nach in 10 s" bzw. "Sturm kommt zurueck"
	if not _warned and (_wave_state == "storm" or _wave_state == "window"):
		var left := _hold_t + (ramp_time if _wave_state == "storm" else 0.0)
		if left <= warn_time:
			_warned = true
			wave_warning.emit("window" if _wave_state == "storm" else "storm", left)
	match _wave_state:
		"storm":
			if _hold_t <= 0.0:
				_wave_state = "down"
				_wave_t = 0.0
				_hold_t = ramp_time
		"down":
			if _hold_t <= 0.0:
				_wave_state = "window"
				_wave_t = 0.0
				_hold_t = _next_hold if _next_hold > 0.0 else _rng.randf_range(window_duration.x, window_duration.y)
				_next_hold = -1.0
				_warned = false
		"window":
			if _hold_t <= 0.0:
				_wave_state = "up"
				_wave_t = 0.0
				_hold_t = ramp_time
		"up":
			if _hold_t <= 0.0:
				_wave_state = "storm"
				_wave_t = 0.0
				_hold_t = _next_hold if _next_hold > 0.0 else _rng.randf_range(storm_duration.x, storm_duration.y)
				_next_hold = -1.0
				_warned = false

func _update_particles(eff: float) -> void:
	if _far == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var up_wind := -_wind * 1.2
		up_wind.y = 0.0
		_far.global_position = cam.global_position + Vector3(0, 6.0, 0) + up_wind
		_near.global_position = cam.global_position + Vector3(0, 1.5, 0) + up_wind * 0.25
	var g := Vector3(_wind.x, -fall_speed * (1.0 + eff), _wind.z)
	_far_mat.gravity = g
	_near_mat.gravity = g * 1.6
	_far_mat.turbulence_noise_strength = 1.5 + eff * 4.0
	_far.amount_ratio = clampf(0.15 + eff * 0.95, 0.0, 1.0)
	_near.amount_ratio = clampf((eff - 0.3) * 1.5, 0.0, 1.0)
	if _drift != null:
		if cam != null:
			_drift.global_position = Vector3(cam.global_position.x, cam.global_position.y - 1.2, cam.global_position.z) - _wind * 0.9
		var wl := Vector3(_wind.x, 0.0, _wind.z)
		var ws := maxf(wl.length(), 0.1)
		_drift_mat.direction = (wl / ws) + Vector3(0, 0.04, 0)
		_drift_mat.initial_velocity_min = ws * 1.3
		_drift_mat.initial_velocity_max = ws * 2.2
		_drift.amount_ratio = clampf(_gust * 1.2 - 0.15, 0.0, 1.0) * clampf(eff * 1.4, 0.0, 1.0)

func _update_env(_eff: float) -> void:
	if _env == null or _env_saved.is_empty():
		return
	_env.fog_density = _fog_density()
	_env.volumetric_fog_density = volumetric_max * clampf(intensity, 0.0, 1.0)

func _update_audio(eff: float) -> void:
	if _wind_snd != null:
		var on := mode != "clear"
		var target := lerpf(wind_volume_db.x, wind_volume_db.y, eff) if on else -60.0
		_wind_snd.volume_db = lerpf(_wind_snd.volume_db, target, 0.05)
		_wind_snd.pitch_scale = 0.9 + 0.2 * eff
	if _lp != null:
		_lp.cutoff_hz = lerpf(20000.0, 2600.0, pow(clampf(eff, 0.0, 1.0), 0.8)) if mode == "blizzard" or mode == "snow" else 20000.0
