extends Enemy
## Scharfschuetze: haelt Abstand, schiesst Einzelschuesse mit hohem Schaden – aber nie ohne Vorwarnung:
## 1.4 s Zielphase mit sichtbarem Laser (Streuung zieht sich zusammen) und Glint am Zielfernrohr.
## Reisst die Sichtlinie ab, wird der Schuss abgebrochen (Deckung lohnt sich).

const AIM_TIME := 1.4
const LASER_COLOR := Color(1.0, 0.12, 0.08)

static var _glint_tex: Texture2D = null

var _aim_left: float = 0.0
var _aim_off: Vector3 = Vector3.ZERO
var _laser: MeshInstance3D = null
var _laser_mat: StandardMaterial3D = null
var _glint: MeshInstance3D = null
var _glint_mat: StandardMaterial3D = null

func _ready() -> void:
	super._ready()
	_build_aim_fx()

func _build_aim_fx() -> void:
	_laser_mat = StandardMaterial3D.new()
	_laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_laser_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_laser_mat.albedo_color = Color(LASER_COLOR, 0.5)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.014, 0.014, 1.0)
	_laser = MeshInstance3D.new()
	_laser.name = "AimLaser"
	_laser.mesh = bm
	_laser.material_override = _laser_mat
	_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)
	if _glint_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.18, Color(1.0, 0.9, 0.75, 0.85))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_glint_tex = gt
	_glint_mat = StandardMaterial3D.new()
	_glint_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glint_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glint_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_glint_mat.albedo_texture = _glint_tex
	_glint_mat.albedo_color = Color(1.0, 0.85, 0.7, 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(0.55, 0.55)
	_glint = MeshInstance3D.new()
	_glint.name = "ScopeGlint"
	_glint.mesh = q
	_glint.material_override = _glint_mat
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.visible = false
	var tip: Node3D = _soldier.scope_tip if _soldier != null and _soldier.scope_tip != null else _muzzle
	if tip != null:
		tip.add_child(_glint)
	else:
		add_child(_glint)

func _start_burst() -> void:
	_burst_left = 1
	_aim_left = AIM_TIME
	_shot_timer = AIM_TIME
	_open_bursts += 1
	var a := rng.randf() * TAU
	_aim_off = Vector3(cos(a), rng.randf_range(-0.6, 0.6), sin(a)).normalized()

func _tick_firing(delta: float) -> bool:
	if _burst_left <= 0:
		_show_aim(false)
		return false
	if not _los or _player == null:
		_burst_left = 0
		_pause_timer = rng.randf_range(0.9, 1.6)
		_show_aim(false)
		return false
	_aim_left -= delta
	_update_aim(clampf(_aim_left / AIM_TIME, 0.0, 1.0))
	if _aim_left <= 0.0:
		_fire_shot()
		_burst_left = 0
		_pause_timer = rng.randf_range(burst_pause_min, burst_pause_max)
		_show_aim(false)
		return false
	return true

func _update_aim(k: float) -> void:
	if _laser == null or _muzzle == null:
		return
	var from := _muzzle.global_position
	var to := _player_chest() + _aim_off * lerpf(0.05, 0.6, k)
	var d := from.distance_to(to)
	if d < 0.1:
		return
	_laser.visible = true
	var basis := Basis.looking_at((to - from) / d, Vector3.UP if absf((to - from).normalized().y) < 0.98 else Vector3.RIGHT)
	_laser.global_transform = Transform3D(basis.scaled(Vector3(1, 1, d)), (from + to) * 0.5)
	_laser_mat.albedo_color = Color(LASER_COLOR, lerpf(0.85, 0.3, k))
	_glint.visible = true
	var pulse := 0.75 + 0.25 * sin(_age * 18.0)
	_glint.scale = Vector3.ONE * lerpf(1.35, 0.8, k) * pulse

func _show_aim(on: bool) -> void:
	if _laser != null:
		_laser.visible = on
	if _glint != null:
		_glint.visible = on

func _process(_delta: float) -> void:
	if (_burst_left <= 0 or state == State.DEAD) and _laser != null and _laser.visible:
		_show_aim(false)

func _on_death() -> void:
	_show_aim(false)
	super._on_death()
