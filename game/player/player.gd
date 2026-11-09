class_name Player
extends CharacterBody3D
## Ego-Shooter-Spieler: CoD-artige Bewegung (Sprint, Ducken, Hinlegen, Slide, Mantle, Step-up),
## ADS, Waffen, Granaten, Gesundheit, Shake.
## Externe Steuerung (Bot/Debug): external_input = true und das Dictionary `ext` füllen.
## Yaw/Pitch in Grad; yaw = rotation_degrees.y (Godot-Konvention, + = nach links).

const VIEW_LAYER_BIT: int = 1 << 19
const RIFLE_SCENE: PackedScene = preload("res://game/weapons/g36c.tscn")
const PISTOL_SCENE: PackedScene = preload("res://game/weapons/pistol.tscn")
const GRENADE_SCENE: PackedScene = preload("res://game/weapons/grenade.tscn")

enum Stance { STAND, CROUCH, PRONE }

@export_group("Movement")
@export var walk_speed: float = 4.6
@export var sprint_speed: float = 7.4
@export var crouch_speed: float = 2.3
@export var prone_speed: float = 0.9
@export var ads_speed_mult: float = 0.6
@export var ground_accel: float = 48.0
@export var ground_friction: float = 36.0
@export var air_accel: float = 7.0
@export var jump_velocity: float = 4.8
@export var gravity: float = 14.5
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.2
@export var prone_height: float = 0.8         # Kapsel-Minimum (2 x Radius)
@export var eye_offset: float = 0.2           # Augenhöhe = Höhe - eye_offset (Stehen/Ducken)
@export var prone_eye: float = 0.35
@export var crouch_rate: float = 7.0          # m/s Höhenänderung Stehen <-> Ducken
@export var prone_rate: float = 2.4           # m/s Höhenänderung zum/vom Liegen
@export var step_height: float = 0.35

@export_group("Slide")
@export var slide_time: float = 0.9
@export var slide_boost: float = 1.22         # Startgeschwindigkeit = max(v, sprint) x boost
@export var slide_eye_drop: float = 0.2       # zusätzlich unter Ducken-Augenhöhe
@export var slide_roll: float = 6.0
@export var slide_fov_add: float = 8.0

@export_group("Mantle")
@export var mantle_max_height: float = 1.6
@export var mantle_min_time: float = 0.4
@export var mantle_max_time: float = 0.6

@export_group("View")
@export var mouse_sens: float = 0.075         # Grad pro Pixel
@export var fov_base: float = 76.0
@export var fov_sprint_add: float = 5.0
@export var weapon_fov: float = 52.0
@export var max_pitch: float = 89.0
## Schrittlängen (m pro Schritt): Kadenz = Geschwindigkeit / Schrittlänge
@export var stride_walk: float = 1.5
@export var stride_sprint: float = 2.1
@export var stride_crouch: float = 0.9
@export var stride_prone: float = 0.6
## Kopf-Bob: vertikal (Dip beim Auftreten) / seitliches Pendeln (m)
@export var bob_walk: float = 0.022
@export var bob_walk_side: float = 0.025
@export var bob_sprint: float = 0.04
@export var bob_sprint_side: float = 0.045
@export var roll_strafe: float = 1.6          # Grad Kamera-Roll beim Strafen
@export var recoil_follow: float = 28.0       # wie schnell die Sicht dem Rückstoß folgt
@export var recoil_recover: float = 7.0       # Rückkehr zur Zielposition

@export_group("Health")
@export var max_health: float = 100.0
@export var regen_delay: float = 4.0
@export var regen_rate: float = 35.0
@export var respawn_delay: float = 2.0

@export_group("Shake")
@export var trauma_decay: float = 1.1
@export var shake_max_angle: float = 4.0      # Grad bei trauma=1
@export var shake_max_offset: float = 0.08
@export var shake_speed: float = 24.0
@export var explosion_shake_range: float = 3.5  # Vielfaches des Radius
@export var shot_trauma_cap: float = 0.3

@export_group("Grenades")
@export var grenades_start: int = 4
@export var throw_speed: float = 14.0
@export var throw_up: float = 3.2
@export var throw_delay: float = 0.18
@export var throw_cooldown: float = 0.9

# --- Externe Steuerung (Vertrag) ---
var external_input: bool = false
var ext: Dictionary = {
	"move": Vector2.ZERO, "look": Vector2.ZERO,
	"fire": false, "aim": false, "sprint": false, "crouch": false,
	"jump": false, "reload": false, "grenade": false, "prone": false, "interact": false,
}
# optionale Zusatzschlüssel: ext["weapon"] = 1|2|3 (Waffe wählen, wird zurückgesetzt)
# ext["interact"] = true: Pickup aufnehmen / Kiste benutzen (Flanke, wird zurückgesetzt)
# Slide: sprint + crouch-Flanke; Mantle: jump vor einer Kante (beides automatisch)

var health: float = 100.0
var grenades: int = 4
var weapons: Array[Weapon] = []
var weapon_index: int = 0
var weapon: Weapon = null
var trauma: float = 0.0

var yaw: float = 0.0       # Grad
var pitch: float = 0.0     # Grad
var dead: bool = false
var stance: int = Stance.STAND
## Für Gegner (enemy.gd liest zuerst is_crouching): geduckt, liegend oder rutschend
var is_crouching: bool = false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon_root: Node3D = $Head/Camera3D/WeaponRoot
@onready var weapon_cam: Camera3D = $WeaponLayer/Container/WeaponViewport/WeaponCam
@onready var weapon_viewport: SubViewport = $WeaponLayer/Container/WeaponViewport
@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var hud: Node = get_node_or_null("HUD")
@onready var sfx_nodes: Array[AudioStreamPlayer3D] = [$Sfx/A, $Sfx/B, $Sfx/C, $Sfx/D]

var _mouse_accum: Vector2 = Vector2.ZERO
var _pending_weapon: int = 0      # 1/2 direkt, 10 nächste, 11 vorige, 20 letzte
var _in_move: Vector2 = Vector2.ZERO
var _in_fire: bool = false
var _in_fire_edge: bool = false
var _in_aim: bool = false
var _in_sprint: bool = false
var _in_crouch: bool = false
var _in_jump: bool = false
var _jump_held: bool = false
var _in_reload: bool = false
var _in_grenade: bool = false
var _prev_fire: bool = false
var _prev_crouch_in: bool = false
var _prone_toggle_req: bool = false

var _height_cur: float = 1.8
var _crouch_amt: float = 0.0      # 0 stehen .. 1 geduckt (aus der Höhe)
var _prone_amt: float = 0.0       # 0 geduckt .. 1 liegend
var _prone_latched: bool = false
var _crouch_toggle: bool = false      # Tastatur: C schaltet Ducken um
var _in_crouch_hold: bool = false     # Tastatur: Strg gehalten
var _prev_sprint_fwd: bool = false
var _in_interact: bool = false
var _interact_hint: String = ""
var _sprint_block: float = 0.0        # Feuern bricht den Sprint ab (Tastatur)
var _since_sprint: float = 10.0       # Zeit seit Sprint-Ende (Sprint-zu-Feuer)
var _wall_amt: float = 0.0            # 0..1 Wand direkt vor der Mündung
var _bot_ammo: bool = false           # Autopilot: Reserve fällt nie unter ein Magazin
var _pickup_cd: float = 0.0
var drops: DropManager = null
var _ads: float = 0.0
var _sprint_amt: float = 0.0
var _sprinting: bool = false
var _crouching: bool = false
var _move_ratio: float = 0.0
var _since_damage: float = 99.0
var _respawn_t: float = 0.0
var _recoil_target: Vector2 = Vector2.ZERO    # x yaw, y pitch (Grad)
var _recoil_cur: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0       # ein Schritt = PI
var _bob_v: float = 0.0
var _bob_h: float = 0.0
var _wbob: float = 0.0
var _was_on_floor: bool = true
var _land_dip: float = 0.0
var _last_fall_speed: float = 0.0
var _step_smooth: float = 0.0
var _jump_buf: float = 0.0
# Slide
var _sliding: bool = false
var _slide_t: float = 0.0
var _slide_air: float = 0.0
var _slide_dir: Vector3 = Vector3.FORWARD
var _slide_v0: float = 0.0
var _slide_amt: float = 0.0
var _dust: GPUParticles3D
# Mantle
var _mantling: bool = false
var _mantle_t: float = 0.0
var _mantle_dur: float = 0.5
var _mantle_from: Vector3 = Vector3.ZERO
var _mantle_to: Vector3 = Vector3.ZERO
var _mantle_cd: float = 0.0
var _mantle_amt: float = 0.0
var _mantle_wave: float = 0.0
# Waffenwechsel: 0 = keiner, 1 = wegstecken, 2 = ziehen
var _switch_phase: int = 0
var _switch_t: float = 0.0
var _switch_to: int = 0
var _holster: float = 0.0
var _last_weapon_index: int = 1
var _throw_cd: float = 0.0
var _throw_pending: float = -1.0
var _noise: FastNoiseLite
var _noise_t: float = 0.0
var _look_rate: Vector2 = Vector2.ZERO
var _sfx_i: int = 0
var _spawn_pos: Vector3 = Vector3.ZERO
var _spawn_yaw: float = 0.0
var _spawn_captured: bool = false
var _checkpoint_pos: Variant = null
var _checkpoint_yaw: float = 0.0
var _checkpoint_id: String = ""
var _death_roll: float = 0.0
var _capsule: CapsuleShape3D

func _ready() -> void:
	add_to_group("player")
	add_to_group("damageable")
	collision_layer = 2
	collision_mask = 1 | 16         # world + move_block (grobe Bewegungs-Kollision der Props)
	floor_snap_length = 0.4
	health = max_health
	grenades = grenades_start
	yaw = rotation_degrees.y
	_ensure_actions()
	_capsule = body_shape.shape as CapsuleShape3D
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = randi()
	_noise.frequency = 1.0
	_setup_camera()
	_setup_weapons()
	_build_dust()
	for n in sfx_nodes:
		n.max_polyphony = 3          # Schuss-Nachhall überlappt bei Dauerfeuer
		n.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		n.panning_strength = 0.0
	_height_cur = stand_height
	_apply_height_shape(_height_cur)
	Events.explosion.connect(_on_explosion)
	Events.checkpoint_reached.connect(_on_checkpoint)
	if not external_input:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _setup_camera() -> void:
	camera.fov = fov_base
	camera.cull_mask = 0xFFFFF & ~VIEW_LAYER_BIT       # Weltkamera sieht das Viewmodel nicht
	camera.current = true
	weapon_cam.cull_mask = VIEW_LAYER_BIT
	weapon_cam.fov = weapon_fov
	weapon_cam.near = 0.01
	weapon_cam.far = 5.0
	weapon_cam.current = true                          # nur in seinem SubViewport
	# Eigene Umgebung: konsistente Beleuchtung, transparenter Hintergrund
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	# Kontrastreicher Himmel (heller Zenit, dunkler Boden): Reflexionen modellieren die Formen,
	# statt das Viewmodel gleichmaessig grau auszuleuchten.
	sm.sky_top_color = Color(0.62, 0.7, 0.82)
	sm.sky_horizon_color = Color(0.78, 0.74, 0.68)
	sm.sky_curve = 0.12
	sm.ground_bottom_color = Color(0.05, 0.048, 0.045)
	sm.ground_horizon_color = Color(0.32, 0.3, 0.28)
	sm.ground_curve = 0.05
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	weapon_cam.environment = env
	# Kante- und Fuelllicht nur fuer das Viewmodel (Layer 20, ohne Schatten, wandert mit der Kamera)
	_add_view_light("ViewRim", Vector3(-28.0, 155.0, 0.0), Color(0.85, 0.9, 1.0), 0.9, 0.6)
	_add_view_light("ViewFill", Vector3(-12.0, -35.0, 0.0), Color(1.0, 0.92, 0.82), 0.28, 0.0)
	weapon_viewport.transparent_bg = true
	weapon_viewport.msaa_3d = Viewport.MSAA_4X
	weapon_viewport.own_world_3d = false
	weapon_viewport.handle_input_locally = false
	weapon_viewport.gui_disable_input = true

func _add_view_light(n: String, rot_deg: Vector3, col: Color, energy: float, spec: float) -> void:
	var l := DirectionalLight3D.new()
	l.name = n
	l.rotation_degrees = rot_deg
	l.light_color = col
	l.light_energy = energy
	l.light_specular = spec
	l.light_cull_mask = VIEW_LAYER_BIT
	l.shadow_enabled = false
	l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	weapon_cam.add_child(l)

func _setup_weapons() -> void:
	for sc in [RIFLE_SCENE, PISTOL_SCENE]:
		var w := (sc as PackedScene).instantiate() as Weapon
		weapon_root.add_child(w)
		w.setup(self)
		w.fired.connect(_on_weapon_fired)
		w.hit_confirmed.connect(_on_hit_confirmed)
		weapons.append(w)
	weapon_index = 0
	weapon = weapons[0]
	weapon.set_active(true)
	_bot_ammo = str(Game.arg("autopilot", "")) not in ["", "false", "0"]
	drops = DropManager.new()
	drops.name = "DropManager"
	drops.player = self
	add_child(drops)

## Staubwolke an den Füßen beim Rutschen.
func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.name = "SlideDust"
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.25
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 1.1
	pm.gravity = Vector3(0, 0.25, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.15, Color(1, 1, 1, 1.0))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	pm.color = Color(0.56, 0.52, 0.45, 0.35)
	_dust.process_material = pm
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = mat
	_dust.draw_pass_1 = q
	_dust.amount = 36
	_dust.lifetime = 1.0
	_dust.local_coords = false
	_dust.emitting = false
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.position = Vector3(0, 0.1, -0.2)
	add_child(_dust)

func _ensure_actions() -> void:
	var defs := {
		"weapon_1": KEY_1, "weapon_2": KEY_2, "weapon_3": KEY_3, "prone": KEY_Z, "weapon_last": KEY_Q,
		"crouch_hold": KEY_CTRL, "interact": KEY_E,
	}
	for a in defs:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var ev := InputEventKey.new()
			ev.physical_keycode = defs[a]
			InputMap.action_add_event(a, ev)
	for a in ["weapon_next", "weapon_prev"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_WHEEL_DOWN if a == "weapon_next" else MOUSE_BUTTON_WHEEL_UP
			InputMap.action_add_event(a, mb)

# ================================================================= Eingabe

func _unhandled_input(event: InputEvent) -> void:
	if external_input:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_accum += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed("weapon_1"):
		_pending_weapon = 1
	elif event.is_action_pressed("weapon_2"):
		_pending_weapon = 2
	elif event.is_action_pressed("weapon_3"):
		_pending_weapon = 3
	elif event.is_action_pressed("weapon_next"):
		_pending_weapon = 10
	elif event.is_action_pressed("weapon_prev"):
		_pending_weapon = 11
	elif event.is_action_pressed("weapon_last"):
		_pending_weapon = 20
	elif event.is_action_pressed("prone") and not event.is_echo():
		_prone_toggle_req = true

func _read_input() -> void:
	if external_input:
		_in_move = (ext.get("move", Vector2.ZERO) as Vector2).limit_length(1.0)
		_in_fire = bool(ext.get("fire", false))
		_in_aim = bool(ext.get("aim", false))
		_in_sprint = bool(ext.get("sprint", false))
		_in_crouch = bool(ext.get("crouch", false))
		_in_jump = bool(ext.get("jump", false))
		_jump_held = false
		_in_reload = bool(ext.get("reload", false))
		_in_grenade = bool(ext.get("grenade", false))
		ext["jump"] = false
		ext["reload"] = false
		ext["grenade"] = false
		_in_interact = _in_interact or bool(ext.get("interact", false))
		ext["interact"] = false
		var sel: int = int(ext.get("weapon", 0))
		if sel != 0:
			_pending_weapon = sel
			ext["weapon"] = 0
	else:
		var cap: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		_in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward") if cap else Vector2.ZERO
		_in_fire = cap and Input.is_action_pressed("fire")
		_in_aim = cap and Input.is_action_pressed("aim")
		_in_sprint = Input.is_action_pressed("sprint")
		_in_crouch = cap and Input.is_action_pressed("crouch")
		_in_crouch_hold = cap and InputMap.has_action("crouch_hold") and Input.is_action_pressed("crouch_hold")
		_in_jump = cap and Input.is_action_just_pressed("jump")
		_jump_held = cap and Input.is_action_pressed("jump")
		_in_reload = cap and Input.is_action_just_pressed("reload")
		_in_grenade = cap and Input.is_action_just_pressed("grenade")
		_in_interact = _in_interact or (cap and Input.is_action_just_pressed("interact"))
	_in_fire_edge = _in_fire and not _prev_fire
	_prev_fire = _in_fire

# ================================================================= Blick (pro Frame)

func _process(delta: float) -> void:
	if not dead:
		var dyaw: float = 0.0
		var dpitch: float = 0.0
		var aim_scale: float = lerpf(1.0, 0.55, _ads)
		if external_input:
			var l: Vector2 = ext.get("look", Vector2.ZERO)
			dyaw = -l.x * delta
			dpitch = l.y * delta
		else:
			dyaw = -_mouse_accum.x * mouse_sens * aim_scale
			dpitch = -_mouse_accum.y * mouse_sens * aim_scale
		_mouse_accum = Vector2.ZERO
		# Gegenzug gegen den Rückstoß "frisst" den noch offenen Rückstoß-Versatz, statt die Basis-
		# Blickrichtung zu verschieben. So landet die Sicht nach der Salve wieder am Ausgangspunkt,
		# egal ob der Spieler gegengezogen hat oder nicht.
		if dpitch < 0.0 and _recoil_target.y > 0.0:
			var a: float = minf(-dpitch, _recoil_target.y)
			_recoil_target.y -= a
			_recoil_cur.y -= a
			dpitch += a
		if absf(dyaw) > 0.0 and absf(_recoil_target.x) > 0.0 and signf(-dyaw) == -signf(_recoil_target.x):
			var b: float = minf(absf(dyaw), absf(_recoil_target.x))
			_recoil_target.x -= signf(_recoil_target.x) * b
			_recoil_cur.x -= signf(_recoil_cur.x) * minf(b, absf(_recoil_cur.x))
			dyaw -= signf(dyaw) * b
		yaw += dyaw
		pitch = clampf(pitch + dpitch, -max_pitch, max_pitch)
		_look_rate = _look_rate.lerp(Vector2(-dyaw, dpitch) / maxf(delta, 0.0001), 1.0 - exp(-14.0 * delta))
	else:
		_look_rate = _look_rate.lerp(Vector2.ZERO, 0.2)
	# Rückstoß: Sicht folgt dem Ziel, Ziel erholt sich
	_recoil_cur = _recoil_cur.lerp(_recoil_target, 1.0 - exp(-recoil_follow * delta))
	# Während der Salve kaum Rückkehr (Muster bleibt lesbar), danach zügig zur Ausgangsposition
	var since: float = weapon.time_since_shot() if weapon else 10.0
	var rec_k: float = 0.25 if since < 0.12 else 1.0
	_recoil_target = _recoil_target.move_toward(Vector2.ZERO, recoil_recover * rec_k * delta * maxf(0.25, _recoil_target.length()))
	_update_camera(delta)

func _eye_height(h: float) -> float:
	if h >= crouch_height:
		return h - eye_offset
	var k: float = clampf((h - prone_height) / maxf(crouch_height - prone_height, 0.01), 0.0, 1.0)
	return lerpf(prone_eye, crouch_height - eye_offset, k)

func _stride() -> float:
	if _sprinting:
		return stride_sprint
	match stance:
		Stance.PRONE:
			return stride_prone
		Stance.CROUCH:
			return stride_crouch
	return stride_walk

func _update_camera(delta: float) -> void:
	rotation_degrees.y = yaw
	head.rotation_degrees = Vector3(pitch + _recoil_cur.y, -_recoil_cur.x, 0.0)
	var spd: float = Vector2(velocity.x, velocity.z).length()
	var grounded: bool = is_on_floor()
	# Slide / Mantle Überblendung
	_slide_amt = lerpf(_slide_amt, 1.0 if _sliding else 0.0, 1.0 - exp(-12.0 * delta))
	_mantle_amt = lerpf(_mantle_amt, 1.0 if _mantling else 0.0, 1.0 - exp(-16.0 * delta))
	_step_smooth = lerpf(_step_smooth, 0.0, 1.0 - exp(-12.0 * delta))
	# Augenhöhe
	var eye_y: float = _eye_height(_height_cur) - slide_eye_drop * _slide_amt - 0.12 * _mantle_wave + _step_smooth
	if dead:
		_death_roll = lerpf(_death_roll, 65.0, 1.0 - exp(-3.0 * delta))
		eye_y = lerpf(head.position.y, 0.35, 1.0 - exp(-4.0 * delta))
	head.position.y = eye_y
	# Trauma-Shake
	trauma = maxf(0.0, trauma - trauma_decay * delta)
	_noise_t += delta * shake_speed
	var s: float = trauma * trauma
	var sh_pitch: float = _noise.get_noise_2d(_noise_t, 0.0) * shake_max_angle * s
	var sh_yaw: float = _noise.get_noise_2d(_noise_t, 100.0) * shake_max_angle * s
	var sh_roll: float = _noise.get_noise_2d(_noise_t, 200.0) * shake_max_angle * 1.2 * s
	var sh_off := Vector3(_noise.get_noise_2d(_noise_t, 300.0), _noise.get_noise_2d(_noise_t, 400.0), 0.0) * shake_max_offset * s
	# Schritt-Kadenz: Phase aus zurückgelegter Strecke (ein Schritt = PI), Schrittgeräusch beim Auftreten
	var tv: float = 0.0
	var th: float = 0.0
	var walking: bool = grounded and spd > 0.4 and not dead and not _sliding and not _mantling
	if walking:
		var old_phase: float = _bob_phase
		_bob_phase += spd * delta / _stride() * PI
		if floori(old_phase / PI) != floori(_bob_phase / PI):
			if stance == Stance.PRONE:
				if fmod(floorf(_bob_phase / PI), 2.0) == 0.0:
					play_sfx("player_prone", 0.2, 6.0)
			else:
				play_sfx("footstep", 0.1)
		var nominal: float = walk_speed
		if _sprinting:
			tv = bob_sprint
			th = bob_sprint_side
			nominal = sprint_speed
		elif stance == Stance.PRONE:
			tv = 0.008
			th = 0.022
			nominal = prone_speed
		elif stance == Stance.CROUCH:
			tv = bob_walk * 0.55
			th = bob_walk_side * 0.65
			nominal = crouch_speed
		else:
			tv = bob_walk
			th = bob_walk_side
		var k: float = clampf(spd / maxf(nominal, 0.1), 0.0, 1.2)
		tv *= k
		th *= k
	_bob_v = lerpf(_bob_v, tv, 1.0 - exp(-8.0 * delta))
	_bob_h = lerpf(_bob_h, th, 1.0 - exp(-8.0 * delta))
	_wbob = lerpf(_wbob, clampf(spd / walk_speed, 0.0, 1.5) if walking else 0.0, 1.0 - exp(-8.0 * delta))
	var sn: float = sin(_bob_phase)
	var dip: float = 1.0 - absf(sn)                      # 1 beim Auftreten
	var bob := Vector3(sn * _bob_h, (0.363 - dip) * _bob_v, 0.0)
	var bob_roll: float = sn * 0.6 * (_bob_h / 0.025)
	var bob_pitch: float = -dip * dip * 0.5 * (_bob_v / 0.022)
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-9.0 * delta))
	# Roll beim Strafen, Slide-Kippen, Mantle-Nicken
	var side: float = (basis.inverse() * velocity).x / maxf(walk_speed, 0.1)
	if _mantling:
		side = 0.0
	var roll: float = -side * roll_strafe + sh_roll + bob_roll + slide_roll * _slide_amt \
			+ 4.0 * _mantle_wave - _death_roll * (1.0 if dead else 0.0)
	camera.position = bob + sh_off + Vector3(0.0, -_land_dip, 0.0)
	camera.rotation_degrees = Vector3(sh_pitch + bob_pitch - 7.0 * _mantle_wave, sh_yaw, roll)
	# FOV
	var target_fov: float = fov_base + fov_sprint_add * _sprint_amt + slide_fov_add * _slide_amt
	if weapon:
		var ads_e: float = _ads * _ads * (3.0 - 2.0 * _ads)
		target_fov = lerpf(target_fov, weapon.ads_fov, ads_e)
	camera.fov = target_fov
	# Waffen-Kamera folgt der Hauptkamera
	weapon_cam.global_transform = camera.global_transform
	weapon_cam.fov = weapon_fov
	# Viewmodel
	if weapon:
		var vel_local: Vector3 = camera.global_basis.inverse() * velocity
		if _mantling:
			vel_local = Vector3.ZERO
		weapon.animate(delta, {
			"look_rate": _look_rate, "vel_local": vel_local, "ads": _ads, "sprint": _sprint_amt,
			"bob_phase": _bob_phase, "bob_amt": _wbob, "holster": _holster,
			"crouch": _crouch_amt, "prone": _prone_amt, "slide": _slide_amt,
			"mantle": _mantle_amt, "airborne": not grounded and not _mantling, "wall": _wall_amt,
		})

# ================================================================= Physik / Logik

func _physics_process(delta: float) -> void:
	if not _spawn_captured:
		_spawn_captured = true
		_spawn_pos = global_position
		_spawn_yaw = yaw
	_read_input()
	if dead:
		_physics_dead(delta)
		return
	_update_movement(delta)
	_update_weapons(delta)
	_update_grenades(delta)
	_update_health(delta)

func _physics_dead(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ground_friction * delta)
	velocity.z = move_toward(velocity.z, 0.0, ground_friction * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	move_and_slide()
	weapon.tick(delta)
	_ads = move_toward(_ads, 0.0, delta * 8.0)
	_sprint_amt = move_toward(_sprint_amt, 0.0, delta * 8.0)
	_respawn_t -= delta
	if _respawn_t <= 0.0:
		respawn()

func _update_movement(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	_mantle_cd = maxf(0.0, _mantle_cd - delta)
	_jump_buf = maxf(0.0, _jump_buf - delta)
	if _in_jump:
		_jump_buf = 0.6
	if _mantling:
		_update_mantle(delta)
		return
	_update_stance(delta, on_floor)
	# Sprint: nur vorwärts, stehend, am Boden, nicht beim Zielen
	var moving_fwd: bool = _in_move.y > 0.3
	var was_sprinting: bool = _sprinting
	_sprint_block = maxf(0.0, _sprint_block - delta)
	_sprinting = _in_sprint and moving_fwd and stance == Stance.STAND and not _sliding and not _in_aim \
			and on_floor and _switch_phase == 0 and _sprint_block <= 0.0
	if not _sprinting and was_sprinting and not on_floor and not _sliding:
		_sprinting = was_sprinting     # Sprint in der Luft beibehalten
	_sprint_amt = move_toward(_sprint_amt, 1.0 if _sprinting else 0.0, delta * 7.0)
	# ADS
	var ads_target: bool = _in_aim and not _sprinting
	var ads_rate: float = weapon.ads_speed if weapon else 10.0
	_ads = move_toward(_ads, 1.0 if ads_target else 0.0, ads_rate * delta)
	# Zielgeschwindigkeit
	var speed: float = walk_speed
	if _sprinting:
		speed = sprint_speed
	elif stance == Stance.PRONE:
		speed = prone_speed
	elif stance == Stance.CROUCH:
		speed = crouch_speed
	speed *= lerpf(1.0, ads_speed_mult, _ads)
	if weapon:
		speed *= weapon.move_speed_mult
	var wish: Vector3 = (basis * Vector3(_in_move.x, 0.0, -_in_move.y))
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if _sliding:
		_slide_velocity(delta, on_floor, wish)
	else:
		var target: Vector3 = wish * speed
		if on_floor:
			var rate: float = ground_accel if wish.length_squared() > 0.001 else ground_friction
			hv = hv.move_toward(target, rate * delta)
		else:
			if wish.length_squared() > 0.001:
				hv = hv.move_toward(target, air_accel * delta)
		velocity.x = hv.x
		velocity.z = hv.z
	# Schwerkraft + Sprung / Mantle
	if on_floor:
		if not _was_on_floor and _last_fall_speed < -3.0:
			_land_dip = clampf(-_last_fall_speed * 0.012, 0.0, 0.12)
			add_trauma(clampf(-_last_fall_speed * 0.02, 0.0, 0.25))
			if weapon:
				weapon.land_impulse(clampf(-_last_fall_speed / 9.0, 0.2, 1.3))
			play_sfx("land")
		if velocity.y < 0.0:
			velocity.y = 0.0
		if _in_jump:
			if _handle_jump():
				return
	else:
		velocity.y -= gravity * delta
		if (_jump_held or _jump_buf > 0.0) and _try_mantle(false):
			return
	_last_fall_speed = velocity.y
	_was_on_floor = on_floor
	# Step-up (kleine Kanten), danach normale Bewegung
	var stepped: bool = on_floor and _try_step_up(delta)
	if stepped:
		var keep := Vector3(velocity.x, 0.0, velocity.z)
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		velocity.x = keep.x
		velocity.z = keep.z
	else:
		move_and_slide()
	var real_h: float = Vector2(get_real_velocity().x, get_real_velocity().z).length()
	_move_ratio = clampf(Vector2(velocity.x, velocity.z).length() / sprint_speed, 0.0, 1.0)
	if _sliding and _slide_t > 0.15 and real_h < 1.2:
		_end_slide(false)                # gegen eine Wand gerutscht
	is_crouching = stance != Stance.STAND or _sliding

## Sprung am Boden: Aufstehen aus dem Liegen, Slide-Sprung, Mantle oder normaler Sprung.
## true = Bewegung für diesen Frame bereits erledigt (Mantle gestartet).
func _handle_jump() -> bool:
	if stance == Stance.PRONE:
		return false                      # Aufstehen erledigt _update_stance
	if _sliding:
		if _space_for(stand_height):
			_end_slide(true)
			velocity.y = jump_velocity
			play_sfx("jump", 0.05)
		return false
	if _try_mantle(true):
		return true
	if not (stance == Stance.CROUCH and _crouch_amt > 0.5):
		velocity.y = jump_velocity
		play_sfx("jump", 0.05)
	return false

# ----------------------------------------------------------------- Haltung

func _height_for(st: int) -> float:
	match st:
		Stance.PRONE:
			return prone_height
		Stance.CROUCH:
			return crouch_height
	return stand_height

## Platz nach oben, um auf Höhe h zu wachsen?
func _space_for(h: float) -> bool:
	var dh: float = h - _height_cur
	if dh <= 0.001:
		return true
	return not test_move(global_transform, Vector3(0.0, dh + 0.03, 0.0))

func _update_stance(delta: float, on_floor: bool) -> void:
	var crouch_edge: bool = _in_crouch and not _prev_crouch_in
	_prev_crouch_in = _in_crouch
	var sprint_fwd: bool = _in_sprint and _in_move.y > 0.3
	var sprint_edge: bool = sprint_fwd and not _prev_sprint_fwd
	_prev_sprint_fwd = sprint_fwd
	if external_input:
		# Vertrag: ext.crouch ist ein Haltezustand, ext.prone ein Zustand (kein Toggle)
		if crouch_edge and not _sliding and stance == Stance.STAND and on_floor and sprint_fwd 				and Vector2(velocity.x, velocity.z).length() > walk_speed + 0.5:
			_start_slide()
		_prone_latched = bool(ext.get("prone", false))
		_crouch_toggle = false
		if stance == Stance.PRONE and not _prone_latched:
			_in_jump = false
	else:
		# C = Ducken umschalten (Sprint + C = Slide), Strg halten = geduckt, Z = Hinlegen umschalten
		if crouch_edge and not _sliding and stance == Stance.STAND and on_floor and sprint_fwd 				and Vector2(velocity.x, velocity.z).length() > walk_speed + 0.5:
			_start_slide()
			crouch_edge = false
		if _prone_toggle_req:
			_prone_latched = not _prone_latched
			_crouch_toggle = false
		_prone_toggle_req = false
		if crouch_edge and not _sliding:
			if _prone_latched:
				_prone_latched = false        # C aus dem Liegen -> geduckt
				_crouch_toggle = true
			else:
				_crouch_toggle = not _crouch_toggle
		# Springen oder (neu) Sprinten steht auf
		if _crouch_toggle and (_in_jump or sprint_edge):
			_crouch_toggle = false
			if stance != Stance.STAND:
				_in_jump = false              # Sprung nur zum Aufstehen
		if _prone_latched and stance == Stance.PRONE and (_in_jump or sprint_edge):
			_prone_latched = false
			_in_jump = false
	# Gewünschte Haltung
	var want: int = Stance.STAND
	if _sliding:
		want = Stance.CROUCH
	elif _prone_latched and (on_floor or stance == Stance.PRONE):
		want = Stance.PRONE
	elif (_in_crouch if external_input else (_crouch_toggle or _in_crouch_hold)):
		want = Stance.CROUCH
	var target_h: float = _height_for(want)
	# Aufstehen nur, wenn oben frei
	if target_h > _height_cur + 0.001 and not _space_for(target_h):
		if want == Stance.STAND and _height_cur < crouch_height - 0.001 and _space_for(crouch_height):
			target_h = crouch_height
		else:
			target_h = _height_cur
	var new_stance: int = Stance.CROUCH
	if target_h > crouch_height + 0.05:
		new_stance = Stance.STAND
	elif target_h < crouch_height - 0.05:
		new_stance = Stance.PRONE
	if new_stance == Stance.PRONE and stance != Stance.PRONE:
		play_sfx("player_prone", 0.05)
		_sprinting = false
		if weapon:
			weapon.add_impulse(Vector3(0.0, -0.3, 0.0), Vector3(-50.0, 0.0, -30.0))
	stance = new_stance
	_crouching = stance == Stance.CROUCH or _sliding
	var rate: float = prone_rate if minf(target_h, _height_cur) < crouch_height - 0.01 else crouch_rate
	_height_cur = move_toward(_height_cur, target_h, rate * delta)
	_apply_height_shape(_height_cur)

func _apply_height_shape(h: float) -> void:
	_capsule.height = maxf(h, _capsule.radius * 2.0)
	body_shape.position.y = _capsule.height * 0.5
	_crouch_amt = clampf((stand_height - h) / (stand_height - crouch_height), 0.0, 1.0)
	_prone_amt = clampf((crouch_height - h) / maxf(crouch_height - prone_height, 0.01), 0.0, 1.0)

# ----------------------------------------------------------------- Slide

func _start_slide() -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	_sliding = true
	_slide_t = 0.0
	_slide_air = 0.0
	_slide_dir = hv.normalized() if hv.length() > 0.1 else -basis.z
	_slide_v0 = maxf(hv.length(), sprint_speed) * slide_boost
	_sprinting = false
	_dust.emitting = true
	play_sfx("player_slide", 0.05)
	if weapon:
		weapon.add_impulse(Vector3(0.0, -0.2, 0.05), Vector3(-25.0, 0.0, 35.0))

func _end_slide(jumped: bool) -> void:
	if not _sliding:
		return
	_sliding = false
	_dust.emitting = false
	if not external_input and not jumped:
		_crouch_toggle = true             # Tastatur: danach geduckt bleiben

func _slide_velocity(delta: float, on_floor: bool, wish: Vector3) -> void:
	_slide_t += delta
	var x: float = clampf(_slide_t / slide_time, 0.0, 1.0)
	var spd: float = lerpf(crouch_speed, _slide_v0, pow(1.0 - x, 1.6))
	if wish.length_squared() > 0.01:     # leicht lenkbar
		_slide_dir = _slide_dir.slerp(wish.normalized(), clampf(1.4 * delta, 0.0, 1.0)).normalized()
	velocity.x = _slide_dir.x * spd
	velocity.z = _slide_dir.z * spd
	if not on_floor:
		_slide_air += delta
	else:
		_slide_air = 0.0
	if x >= 1.0 or _slide_air > 0.25:
		_end_slide(false)

# ----------------------------------------------------------------- Mantle / Step-up

## Kante vor dem Spieler (0.35..1.6 m) erkennen und hochziehen. true = Mantle gestartet.
func _try_mantle(on_floor: bool) -> bool:
	if stance == Stance.PRONE or _sliding or _mantling or _mantle_cd > 0.0 or dead:
		return false
	var wish: Vector3 = basis * Vector3(_in_move.x, 0.0, -_in_move.y)
	var dir: Vector3 = -basis.z
	if wish.length() > 0.3:
		dir = wish
	elif not on_floor:
		return false                      # in der Luft nur mit Bewegungswunsch
	dir.y = 0.0
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	var space := get_world_3d().direct_space_state
	var feet: Vector3 = global_position
	var ex: Array[RID] = [get_rid()]
	var wall_d: float = 99.0
	for hgt: float in [0.25, 0.6, 1.0, 1.45]:
		var o: Vector3 = feet + Vector3(0.0, hgt, 0.0)
		var q := PhysicsRayQueryParameters3D.create(o, o + dir * 0.95, 1, ex)
		var r: Dictionary = space.intersect_ray(q)
		if not r.is_empty() and absf((r.normal as Vector3).y) < 0.6:
			wall_d = minf(wall_d, o.distance_to(r.position))
	if wall_d > 0.9:
		return false
	var min_h: float = 0.36 if on_floor else 0.12
	for extra: float in [0.45, 0.3]:
		var px: Vector3 = feet + dir * (wall_d + extra)
		var top: Vector3 = px + Vector3(0.0, mantle_max_height + 0.45, 0.0)
		var q2 := PhysicsRayQueryParameters3D.create(top, px + Vector3(0.0, min_h - 0.05, 0.0), 1, ex)
		var r2: Dictionary = space.intersect_ray(q2)
		if r2.is_empty() or (r2.normal as Vector3).y < 0.7:
			continue
		var ledge_y: float = (r2.position as Vector3).y
		var h: float = ledge_y - feet.y
		if h < min_h or h > mantle_max_height:
			continue
		var target := Vector3(px.x, ledge_y + 0.03, px.z)
		if _mantle_path_clear(feet, target, dir):
			_start_mantle(target, h, false)
			return true
		# Mit geduckter Kapsel versuchen (niedrige Decke über der Kante)
		var old_h: float = _height_cur
		if old_h > crouch_height:
			_apply_height_shape(crouch_height)
			if _mantle_path_clear(feet, target, dir):
				_height_cur = crouch_height
				stance = Stance.CROUCH
				_start_mantle(target, h, true)
				return true
			_apply_height_shape(old_h)
	return false

func _mantle_path_clear(feet: Vector3, target: Vector3, dir: Vector3) -> bool:
	var t: Transform3D = global_transform
	t.origin -= dir * 0.03
	var up := Vector3(0.0, target.y - feet.y + 0.03, 0.0)
	if test_move(t, up):
		return false
	t.origin += up
	var horiz := Vector3(target.x - t.origin.x, 0.0, target.z - t.origin.z)
	return not test_move(t, horiz)

func _start_mantle(target: Vector3, h: float, crouched: bool) -> void:
	_mantling = true
	_mantle_t = 0.0
	_mantle_from = global_position
	_mantle_to = target
	_mantle_dur = clampf(mantle_min_time + (mantle_max_time - mantle_min_time) * (h / mantle_max_height),
			mantle_min_time, mantle_max_time)
	velocity = Vector3.ZERO
	_sprinting = false
	_jump_buf = 0.0
	if crouched and not external_input:
		_crouch_toggle = true
	play_sfx("player_mantle", 0.05)
	if weapon:
		weapon.add_impulse(Vector3(0.0, -0.25, 0.0), Vector3(-40.0, 0.0, 25.0))

func _update_mantle(delta: float) -> void:
	_mantle_t += delta
	var u: float = clampf(_mantle_t / _mantle_dur, 0.0, 1.0)
	var dy: float = _mantle_to.y - _mantle_from.y
	var hz := Vector3(_mantle_to.x - _mantle_from.x, 0.0, _mantle_to.z - _mantle_from.z)
	var ru: float = clampf(u / 0.65, 0.0, 1.0)
	var rise: float = 1.0 - pow(1.0 - ru, 3.0)          # schnell hoch, oben abbremsen
	var fw: float = 0.15 * ru if u < 0.65 else 0.15 + 0.85 * smoothstep(0.65, 1.0, u)
	var p: Vector3 = _mantle_from + Vector3(0.0, dy * rise, 0.0) + hz * fw
	var prev: Vector3 = global_position
	global_position = p
	velocity = (p - prev) / maxf(delta, 0.0001)
	_mantle_wave = sin(u * PI)
	_sprint_amt = move_toward(_sprint_amt, 0.0, delta * 8.0)
	_ads = move_toward(_ads, 0.0, delta * 8.0)
	if u >= 1.0:
		_mantling = false
		_mantle_wave = 0.0
		_mantle_cd = 0.25
		var d: Vector3 = hz.normalized() if hz.length() > 0.01 else Vector3.ZERO
		velocity = d * walk_speed * 0.5
		_was_on_floor = true
		_last_fall_speed = 0.0
		apply_floor_snap()

## Kleine Kanten (bis step_height) ohne Sprung überwinden. true = Spieler wurde versetzt.
func _try_step_up(delta: float) -> bool:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if hv.length() < 0.5:
		return false
	var motion: Vector3 = hv * delta
	var col := KinematicCollision3D.new()
	if not test_move(global_transform, motion, col):
		return false
	if col.get_normal().y > 0.7:
		return false                      # Rampe, kein Absatz
	var t: Transform3D = global_transform
	var up := Vector3(0.0, step_height, 0.0)
	if test_move(t, up):
		return false
	t.origin += up
	var fwd: Vector3 = hv.normalized() * maxf(motion.length(), 0.2)
	if test_move(t, fwd):
		return false
	t.origin += fwd
	var col2 := KinematicCollision3D.new()
	if not test_move(t, -up - Vector3(0.0, 0.05, 0.0), col2):
		return false                      # dahinter kein Boden
	if col2.get_normal().y < 0.6:
		return false
	t.origin += col2.get_travel()
	var dy: float = t.origin.y - global_position.y
	if dy < 0.03:
		return false
	global_position = t.origin
	_step_smooth -= dy                    # Kamera fängt die Stufe weich ab
	return true

# ----------------------------------------------------------------- Waffen

func _update_weapons(delta: float) -> void:
	# Waffenwechsel: wegstecken -> tauschen -> ziehen
	if _switch_phase == 1:
		_switch_t += delta
		var ht: float = maxf(weapon.holster_time, 0.01)
		var u: float = clampf(_switch_t / ht, 0.0, 1.0)
		_holster = u * u
		if u >= 1.0:
			_do_switch(_switch_to)
			_switch_phase = 2
			_switch_t = 0.0
	elif _switch_phase == 2:
		_switch_t += delta
		var dt: float = maxf(weapon.draw_time, 0.01)
		var u2: float = clampf(_switch_t / dt, 0.0, 1.0)
		# Ease-out-back: leichtes Überschwingen nach oben
		var c1: float = 1.2
		var c3: float = c1 + 1.0
		var e: float = 1.0 + c3 * pow(u2 - 1.0, 3.0) + c1 * pow(u2 - 1.0, 2.0)
		_holster = 1.0 - e
		if u2 >= 1.0:
			_switch_phase = 0
			_holster = 0.0
	if _pending_weapon != 0:
		var want: int = weapon_index
		match _pending_weapon:
			1:
				want = 0
			2:
				want = 1
			3:
				want = 2 if weapons.size() > 2 else weapon_index
			10:
				want = (weapon_index + 1) % weapons.size()
			11:
				want = (weapon_index - 1 + weapons.size()) % weapons.size()
			20:
				want = clampi(_last_weapon_index, 0, weapons.size() - 1)
		_pending_weapon = 0
		if want != weapon_index and _switch_phase == 0 and not _mantling:
			_switch_to = want
			_switch_phase = 1
			_switch_t = 0.0
			weapon.cancel_reload()
	weapon.tick(delta)
	var busy: bool = _switch_phase != 0 or _mantling
	_update_wall()
	_update_pickups(delta, busy)
	if _bot_ammo:
		_bot_top_up()
	# Sprint-zu-Feuer: Feuern (Tastatur) beendet den Sprint, geschossen wird erst nach kurzer Absenkzeit
	if _in_fire and not external_input:
		_sprint_block = 0.4
		_sprinting = false
	if _sprinting:
		_since_sprint = 0.0
	else:
		_since_sprint += delta
	var sprint_lock: bool = _sprinting or _since_sprint < weapon.sprint_to_fire
	var wall_lock: bool = _wall_amt > 0.75 and not external_input
	# Nachladen
	if _in_reload and not busy and not _sprinting:
		weapon.start_reload()
	# Feuern
	var trigger: bool = _in_fire if (weapon.full_auto or external_input) else _in_fire_edge
	if not _in_fire:
		weapon.reset_trigger()
	if trigger and not busy and not sprint_lock and not wall_lock:
		if weapon.ammo_mag <= 0:
			if _in_fire_edge or weapon.full_auto:
				weapon.notify_dry()
			if weapon.can_reload():
				weapon.start_reload()
		elif weapon.ready_to_fire():
			if weapon.try_fire(camera, _ads, _move_ratio, _crouching, not is_on_floor(), stance == Stance.PRONE):
				_recoil_target += weapon.last_recoil * (0.75 if stance == Stance.PRONE else 1.0)
				_recoil_target.y = minf(_recoil_target.y, 14.0)
				_recoil_target.x = clampf(_recoil_target.x, -6.0, 6.0)
	# Leeres Magazin automatisch nachladen
	if weapon.ammo_mag <= 0 and weapon.can_reload() and not busy:
		weapon.start_reload()

func _do_switch(idx: int) -> void:
	weapon.set_active(false)
	_last_weapon_index = weapon_index
	weapon_index = idx
	weapon = weapons[idx]
	weapon.set_active(true)
	play_sfx("weapon_switch")

func _on_weapon_fired(w: Weapon) -> void:
	add_trauma(minf(w.shot_trauma, maxf(0.0, shot_trauma_cap - trauma)))
	Events.weapon_fired.emit(w)

func _on_hit_confirmed(killed: bool, headshot: bool) -> void:
	if hud and hud.has_method("show_hitmarker"):
		hud.call("show_hitmarker", killed, headshot)
	play_sfx("hitmarker_kill" if killed else "hitmarker")
	if headshot:
		play_sfx("headshot", 0.03)

func add_ammo(amount_rifle: int, amount_pistol: int = 0) -> void:
	weapons[0].add_reserve(amount_rifle)
	weapons[1].add_reserve(amount_pistol)

# ----------------------------------------------------------------- Inventar / Pickups

func get_weapon(id: String) -> Weapon:
	for w in weapons:
		if w.weapon_id == id:
			return w
	return null

func weapon_for_ammo(ammo: String) -> Weapon:
	for w in weapons:
		if w.ammo_type == ammo:
			return w
	return null

func needs_ammo() -> bool:
	for w in weapons:
		if not w.is_launcher() and w.ammo_reserve < w.reserve_start:
			return true
	return grenades < grenades_start

## Munitionskiste: Reserve aller Waffen (außer Panzerfaust) auf Startwert, Granaten auf Startzahl.
func refill_from_crate() -> void:
	for w in weapons:
		if not w.is_launcher():
			w.ammo_reserve = maxi(w.ammo_reserve, w.reserve_start)
	grenades = maxi(grenades, grenades_start)
	play_sfx("ammo_pickup", 0.05)

func on_ammo_collected(amount: int, _ammo: String) -> void:
	if amount > 0 and _pickup_cd <= 0.0:
		play_sfx("ammo_pickup", 0.08)
		_pickup_cd = 0.25

## Waffe aufnehmen. Primärwaffe (Slot 0) wird ersetzt; die alte kommt als {id, mag, reserve} zurück
## (der Aufrufer legt sie als Pickup ab). Panzerfaust (Slot 2) wird Waffe 3. Die neue Waffe wird gezogen.
func give_weapon(id: String, mag: int, reserve: int) -> Dictionary:
	var existing: Weapon = get_weapon(id)
	if existing != null:
		existing.add_reserve(mag + reserve)
		return {}
	var w: Weapon = WeaponDefs.instantiate(id)
	if w == null or w.slot == 1:
		if w:
			w.free()
		return {}
	weapon_root.add_child(w)
	w.setup(self)
	w.fired.connect(_on_weapon_fired)
	w.hit_confirmed.connect(_on_hit_confirmed)
	w.set_active(false)
	w.ammo_mag = clampi(mag, 0, w.mag_size)
	w.ammo_reserve = clampi(reserve, 0, w.reserve_max)
	var old: Dictionary = {}
	var idx: int
	if w.slot == 0:
		var prev: Weapon = weapons[0]
		old = {"id": prev.weapon_id, "mag": prev.ammo_mag, "reserve": prev.ammo_reserve}
		prev.cancel_reload()
		prev.set_active(false)
		weapons[0] = w
		prev.queue_free()
		idx = 0
		if weapon == prev:
			weapon = w
			weapon_index = 0
	else:
		weapons.append(w)
		idx = weapons.size() - 1
	# Neue Waffe sofort ziehen
	if weapon != w:
		weapon.cancel_reload()
		weapon.set_active(false)
		_last_weapon_index = weapon_index
	weapon_index = idx
	weapon = w
	weapon.set_active(true)
	_switch_phase = 2
	_switch_t = 0.0
	_holster = 1.0
	play_sfx("weapon_switch")
	return old

## Wand vor der Mündung (Strahl entlang der Blickrichtung, nur Welt): Viewmodel zieht sich zurück.
func _update_wall() -> void:
	var reach: float = 0.95 if weapon.is_long() else 0.6
	var from: Vector3 = camera.global_position
	var to: Vector3 = from - camera.global_basis.z * reach
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	var res: Dictionary = get_world_3d().direct_space_state.intersect_ray(q)
	var target: float = 0.0
	if not res.is_empty() and not _mantling:
		var d: float = from.distance_to(res.position)
		target = clampf(1.0 - (d - reach * 0.4) / (reach * 0.6), 0.0, 1.0)
	_wall_amt = target

## Pickups in Reichweite: Munition automatisch, Waffen/Kisten per [E] (HUD-Hinweis).
func _update_pickups(delta: float, busy: bool) -> void:
	_pickup_cd = maxf(0.0, _pickup_cd - delta)
	_interact_hint = ""
	var target: Pickup = null
	var best: float = INF
	var fwd: Vector3 = -camera.global_basis.z
	for n in get_tree().get_nodes_in_group("pickup"):
		var pk: Pickup = n as Pickup
		if pk == null or pk.is_queued_for_deletion() or not pk.in_range(self):
			continue
		if pk.auto_collect(self):
			continue
		var txt: String = pk.interact_text(self)
		if txt == "":
			continue
		var dv: Vector3 = pk.global_position - camera.global_position
		var score: float = dv.length() - 0.8 * fwd.dot(dv.normalized())
		if score < best:
			best = score
			target = pk
			_interact_hint = txt
	if _in_interact and target != null and not busy and not dead:
		target.interact(self)
		_interact_hint = ""
	_in_interact = false

## Autopilot: kein Scheitern an Munitionsmangel (die Simulation prüft Bewegung/Kampf, nicht Ressourcen).
func _bot_top_up() -> void:
	for w in weapons:
		if not w.is_launcher() and w.ammo_reserve < w.mag_size:
			w.ammo_reserve = mini(w.mag_size * 2, w.reserve_max)

func add_grenades(n: int) -> void:
	grenades = mini(grenades + n, 6)

# ----------------------------------------------------------------- Granaten

func _update_grenades(delta: float) -> void:
	_throw_cd = maxf(0.0, _throw_cd - delta)
	if _throw_pending >= 0.0:
		_throw_pending -= delta
		if _throw_pending < 0.0:
			_spawn_grenade()
	if _in_grenade and grenades > 0 and _throw_cd <= 0.0 and _throw_pending < 0.0 and _switch_phase == 0 \
			and not _mantling:
		_throw_pending = throw_delay
		_throw_cd = throw_cooldown
		weapon.cancel_reload()
		play_sfx("grenade_throw")

func _spawn_grenade() -> void:
	if grenades <= 0 or dead:
		return
	grenades -= 1
	var g := GRENADE_SCENE.instantiate() as Grenade
	var parent: Node = get_tree().current_scene
	if parent == null:
		parent = get_parent()
	parent.add_child(g)
	var cb: Basis = camera.global_basis
	var fwd: Vector3 = -cb.z
	g.global_position = camera.global_position + fwd * 0.55 + cb.x * 0.12 - cb.y * 0.12
	g.linear_velocity = fwd * throw_speed + Vector3.UP * throw_up + velocity * 0.7
	g.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	g.setup(self)
	add_trauma(0.08)

# ----------------------------------------------------------------- Gesundheit

func _update_health(delta: float) -> void:
	_since_damage += delta
	if health < max_health and _since_damage >= regen_delay:
		health = minf(max_health, health + regen_rate * delta)

func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if dead or amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_since_damage = 0.0
	Events.player_damaged.emit(amount, source)
	add_trauma(clampf(0.2 + amount / 100.0 * 0.5, 0.0, 0.7))
	# Richtung des Angreifers relativ zur Blickrichtung
	var from_pos: Variant = null
	if source is Node3D and source != self:
		from_pos = (source as Node3D).global_position
	elif hit_position != Vector3.ZERO:
		from_pos = hit_position
	var angle: float = NAN
	if from_pos != null:
		var d: Vector3 = (from_pos as Vector3) - global_position
		d.y = 0.0
		if d.length() > 0.5:
			var local: Vector3 = camera.global_basis.inverse() * d.normalized()
			angle = atan2(local.x, -local.z)
	if hud and hud.has_method("show_damage"):
		hud.call("show_damage", angle, amount)
	play_sfx("player_hurt", 0.05)
	if health <= 0.0:
		_die()

func is_alive() -> bool:
	return not dead

func heal(amount: float) -> void:
	health = minf(max_health, health + amount)

func _die() -> void:
	dead = true
	_respawn_t = respawn_delay
	_death_roll = 0.0
	weapon.cancel_reload()
	_throw_pending = -1.0
	_pending_weapon = 0
	_end_slide(true)
	_mantling = false
	_mantle_wave = 0.0
	Events.player_died.emit()
	if hud and hud.has_method("show_death"):
		hud.call("show_death")
	play_sfx("player_death")

func respawn() -> void:
	var pos: Vector3 = _spawn_pos
	var y: float = _spawn_yaw
	if _checkpoint_pos != null:
		pos = _checkpoint_pos as Vector3
		y = _checkpoint_yaw
	else:
		var marker: Node = get_tree().get_first_node_in_group("player_spawn")
		if marker is Node3D:
			pos = (marker as Node3D).global_position
			y = (marker as Node3D).global_rotation_degrees.y
	dead = false
	health = max_health
	_since_damage = 99.0
	global_position = pos + Vector3(0.0, 0.05, 0.0)
	velocity = Vector3.ZERO
	yaw = y
	pitch = 0.0
	_recoil_cur = Vector2.ZERO
	_recoil_target = Vector2.ZERO
	_death_roll = 0.0
	trauma = 0.0
	grenades = maxi(grenades, grenades_start)
	# Haltung zurücksetzen
	_sliding = false
	_dust.emitting = false
	_mantling = false
	_mantle_wave = 0.0
	_prone_latched = false
	_crouch_toggle = false
	stance = Stance.STAND
	is_crouching = false
	_height_cur = stand_height
	_apply_height_shape(_height_cur)
	_switch_phase = 0
	_holster = 0.0
	for w in weapons:
		w.refill()
	_sprint_block = 0.0
	_since_sprint = 10.0
	_wall_amt = 0.0
	if weapon_index != 0:
		_do_switch(0)
	if hud and hud.has_method("hide_death"):
		hud.call("hide_death")
	Events.player_respawned.emit()

func _on_checkpoint(id: String) -> void:
	_checkpoint_pos = global_position
	_checkpoint_yaw = yaw
	_checkpoint_id = id

# ----------------------------------------------------------------- Shake

func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _on_explosion(pos: Vector3, radius: float, _strength: float) -> void:
	var dist: float = global_position.distance_to(pos)
	var reach: float = maxf(radius * explosion_shake_range, 10.0)
	if dist < reach:
		add_trauma(clampf(1.0 - dist / reach, 0.0, 1.0) * 0.95 + 0.05)

# ----------------------------------------------------------------- Audio

## SFX-Hook: bleibt stumm, solange res://assets/sfx/<name>.ogg|.wav fehlt.
func play_sfx(sfx_name: String, pitch_jitter: float = 0.0, vol_jitter_db: float = 0.0) -> void:
	if Sfx.get_variants(sfx_name).is_empty():
		return
	_sfx_i = (_sfx_i + 1) % sfx_nodes.size()
	Sfx.play_on(sfx_nodes[_sfx_i], sfx_name, pitch_jitter, vol_jitter_db)

# ================================================================= Öffentliche API

func set_view(yaw_deg: float, pitch_deg: float) -> void:
	yaw = yaw_deg
	pitch = clampf(pitch_deg, -max_pitch, max_pitch)
	_recoil_cur = Vector2.ZERO
	_recoil_target = Vector2.ZERO
	_update_camera(0.0)

## Sofort auf einen Weltpunkt zielen (Rückstoß-Offset wird mit eingerechnet).
func look_at_point(p: Vector3) -> void:
	var from: Vector3 = camera.global_position
	var d: Vector3 = p - from
	if d.length() < 0.001:
		return
	var want_yaw: float = rad_to_deg(atan2(-d.x, -d.z))
	var horiz: float = Vector2(d.x, d.z).length()
	var want_pitch: float = rad_to_deg(atan2(d.y, horiz))
	yaw = want_yaw + _recoil_cur.x
	pitch = clampf(want_pitch - _recoil_cur.y, -max_pitch, max_pitch)
	_update_camera(0.0)

func get_camera() -> Camera3D:
	return camera

func _stance_name() -> String:
	match stance:
		Stance.PRONE:
			return "prone"
		Stance.CROUCH:
			return "crouch"
	return "stand"

func get_status() -> Dictionary:
	return {
		"alive": not dead,
		"health": health,
		"max_health": max_health,
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": yaw,
		"pitch": pitch,
		"weapon": weapon.weapon_id,
		"weapon_index": weapon_index + 1,
		"ammo_mag": weapon.ammo_mag,
		"ammo_reserve": weapon.ammo_reserve,
		"grenades": grenades,
		"reloading": weapon.reloading,
		"aiming": _ads > 0.5,
		"stance": _stance_name(),
		"prone": stance == Stance.PRONE,
		"sliding": _sliding,
		"mantling": _mantling,
	}

## Zusatzdaten für das HUD.
func get_hud_info() -> Dictionary:
	var names: Array[String] = []
	for w in weapons:
		names.append(w.display_name)
	return {
		"alive": not dead,
		"health": health,
		"max_health": max_health,
		"weapon_name": weapon.display_name,
		"weapon_index": weapon_index,
		"weapon_names": names,
		"interact_hint": _interact_hint,
		"ammo_type": weapon.ammo_type,
		"switching": _switch_phase != 0,
		"ammo_mag": weapon.ammo_mag,
		"mag_size": weapon.mag_size,
		"ammo_reserve": weapon.ammo_reserve,
		"grenades": grenades,
		"reloading": weapon.reloading,
		"reload_progress": weapon.reload_progress(),
		"spread_deg": weapon.current_spread(_ads, _move_ratio, _crouching, not is_on_floor() and not _mantling,
				stance == Stance.PRONE),
		"fov": camera.fov,
		"ads": _ads,
		"sprint": _sprint_amt,
		"stance": _stance_name(),
		"sliding": _sliding,
	}
