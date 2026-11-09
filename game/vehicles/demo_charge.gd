class_name DemoCharge
extends Area3D
## Sprengladungspunkt. Spieler haelt "interact" (E) 1,5 s in Reichweite -> Ladung sitzt, piept 4 s
## (immer schneller), dann target.destroy() (bzw. take_damage(99999, ...)) und Combat.explode.
## Autopilot (Game.arg("autopilot")): setzt die Ladung automatisch, sobald der Spieler < 2,5 m entfernt ist.
## Position = Stelle, an der die Ladung haftet (z. B. Panzerwanne, Brueckenpfeiler).

signal planted
signal detonated

const VF = preload("res://game/vehicles/vehicle_fx.gd")

@export var target: Node                          ## Ziel (destroy() oder take_damage); darf null sein
@export var hold_time: float = 1.5
@export var fuse_time: float = 4.0
@export var reach: float = 2.6                    ## Interaktionsradius (m)
@export var blast_radius: float = 7.0
@export var blast_damage: float = 160.0
@export var prompt_text: String = "[E] Sprengladung anbringen"

var is_planted: bool = false
var is_detonated: bool = false

var _hold: float = 0.0
var _fuse: float = 0.0
var _beep_t: float = 0.0
var _label: Label3D
var _charge: Node3D
var _led_mat: StandardMaterial3D
var _led_light: OmniLight3D
var _ghost: Node3D
var _t: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = VF.LAYER_PLAYER
	monitorable = false
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = reach
	cs.shape = sp
	add_child(cs)
	_build_visuals()

func _build_visuals() -> void:
	_label = Label3D.new()
	_label.text = prompt_text
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0011
	_label.font_size = 26
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.92, 0.6)
	_label.position = Vector3(0, 0.55, 0)
	_label.visible = false
	add_child(_label)
	# Markierung vor dem Anbringen: pulsierender Umriss der Ladung
	_ghost = Node3D.new()
	add_child(_ghost)
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(1.0, 0.85, 0.3, 0.25)
	gm.no_depth_test = false
	VF.mesh_node(_ghost, VF.box(Vector3(0.34, 0.2, 0.12)), gm)
	# eigentliche Ladung (unsichtbar bis zum Anbringen): zwei Bloecke, Klebeband, Zuender, Draehte, LED
	_charge = Node3D.new()
	_charge.visible = false
	add_child(_charge)
	var block := VF.mat("c4_block", Color(0.52, 0.5, 0.4), 0.85, 0.0)
	var tape := VF.mat("c4_tape", Color(0.12, 0.12, 0.11), 0.5, 0.0)
	var box := VF.mat("c4_det", Color(0.15, 0.17, 0.14), 0.45, 0.3)
	VF.mesh_node(_charge, VF.box(Vector3(0.3, 0.08, 0.1)), block, Vector3(0, 0.045, 0))
	VF.mesh_node(_charge, VF.box(Vector3(0.3, 0.08, 0.1)), block, Vector3(0, -0.045, 0))
	for x in [-0.09, 0.09]:
		VF.mesh_node(_charge, VF.box(Vector3(0.035, 0.18, 0.11)), tape, Vector3(x, 0, 0))
	VF.mesh_node(_charge, VF.box(Vector3(0.1, 0.06, 0.05)), box, Vector3(0, 0, 0.07))
	var wire_r := VF.mat("c4_wire_r", Color(0.6, 0.05, 0.03), 0.5, 0.0)
	var wire_b := VF.mat("c4_wire_b", Color(0.1, 0.15, 0.5), 0.5, 0.0)
	VF.mesh_node(_charge, VF.cyl(0.006, 0.006, 0.18, 6), wire_r, Vector3(-0.07, 0.07, 0.06), Vector3(0, 0, 60))
	VF.mesh_node(_charge, VF.cyl(0.006, 0.006, 0.16, 6), wire_b, Vector3(0.07, 0.06, 0.06), Vector3(0, 0, -55))
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.3, 0.0, 0.0)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(1.0, 0.05, 0.02)
	_led_mat.emission_energy_multiplier = 0.0
	VF.mesh_node(_charge, VF.sphere(0.012, -1.0, 8), _led_mat, Vector3(0.03, 0.02, 0.097))
	_led_light = OmniLight3D.new()
	_led_light.light_color = Color(1.0, 0.1, 0.05)
	_led_light.light_energy = 0.0
	_led_light.omni_range = 1.6
	_led_light.position = Vector3(0, 0.03, 0.2)
	_charge.add_child(_led_light)

func _player_dist() -> float:
	var p := Game.get_player() as Node3D
	if p == null:
		return INF
	return p.global_position.distance_to(global_position) if p.is_inside_tree() else INF

func _physics_process(delta: float) -> void:
	_t += delta
	if is_detonated:
		return
	if is_planted:
		_tick_fuse(delta)
		return
	var d := _player_dist()
	var near := d <= reach + 0.9  # Kapselhoehe/Abstand des Spielers grosszuegig behandeln
	_ghost.visible = true
	var gm := (_ghost.get_child(0) as MeshInstance3D).material_override as StandardMaterial3D
	gm.albedo_color.a = 0.15 + 0.15 * sin(_t * 4.0)
	if Game.arg("autopilot") and d < 2.5:
		plant()
		return
	_label.visible = near
	if near and Input.is_action_pressed("interact"):
		_hold += delta
		var bars := int(clampf(_hold / hold_time, 0.0, 1.0) * 10.0)
		_label.text = "Anbringen  [" + "|".repeat(bars) + ".".repeat(10 - bars) + "]"
		if _hold >= hold_time:
			plant()
	else:
		if _hold > 0.0:
			_label.text = prompt_text
		_hold = 0.0

## Bringt die Ladung an (auch direkt per Skript aufrufbar).
func plant() -> void:
	if is_planted or is_detonated:
		return
	is_planted = true
	_fuse = 0.0
	_beep_t = 0.0
	_label.visible = false
	_ghost.visible = false
	_charge.visible = true
	VF.play_at(self, "veh_charge_plant", global_position, -2.0, 4.0, 40.0)
	planted.emit()

func _tick_fuse(delta: float) -> void:
	_fuse += delta
	var k := clampf(_fuse / fuse_time, 0.0, 1.0)
	var interval := lerpf(0.55, 0.07, k * k)
	_beep_t -= delta
	if _beep_t <= 0.0:
		_beep_t = interval
		VF.play_at(self, "veh_charge_beep", global_position, 0.0, 5.0, 60.0, 1.0 + k * 0.25)
		_led_mat.emission_energy_multiplier = 8.0
		_led_light.light_energy = 1.5
	else:
		_led_mat.emission_energy_multiplier = move_toward(_led_mat.emission_energy_multiplier, 0.0, delta * 60.0)
		_led_light.light_energy = move_toward(_led_light.light_energy, 0.0, delta * 12.0)
	if _fuse >= fuse_time:
		detonate()

## Zuendet sofort.
func detonate() -> void:
	if is_detonated:
		return
	is_planted = true
	is_detonated = true
	_charge.visible = false
	_ghost.visible = false
	_label.visible = false
	var pos := global_position
	Combat.explode(pos, blast_radius, blast_damage, self, 2.2)
	VFX.spawn_dust_cloud(pos, 4.0)
	if target != null and is_instance_valid(target):
		if target.has_method("destroy"):
			target.call("destroy")
		elif target.has_method("take_damage"):
			target.call("take_damage", 99999.0, self, pos, Vector3.UP)
	detonated.emit()
	get_tree().create_timer(3.0, false).timeout.connect(queue_free)
