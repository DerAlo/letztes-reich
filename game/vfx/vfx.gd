extends Node
## Effekt-Spawner (Autoload). Besitzer: VFX/Level-Agent.
## Pools fuer Explosionen und Einschlaege, Decals (Brandflecken, Einschusslocher), Truemmer-Verwaltung.

const VfxLib = preload("res://game/vfx/vfx_lib.gd")
const ExplosionScript = preload("res://game/vfx/explosion.gd")
const ImpactScript = preload("res://game/vfx/impact_fx.gd")
const WorldAudioScript = preload("res://game/vfx/world_audio.gd")
const BloodScript = preload("res://game/vfx/blood_fx.gd")

const MAX_EXPLOSIONS := 6
const MAX_IMPACTS := 14
const MAX_DECALS := 48
const MAX_DEBRIS := 90

@export var ground_collider_enabled: bool = true
@export var decal_lifetime: float = 45.0

var _expl_free: Array[Node3D] = []
var _expl_all: Array[Node3D] = []
var _impact_free: Array[Node3D] = []
var _impact_count: int = 0
var _cloud_free: Array[Node3D] = []
var _cloud_count: int = 0
var _decals: Array[Decal] = []
var _debris_count: int = 0
var _debris_mat: StandardMaterial3D
var _ground_col: GPUParticlesCollisionBox3D
var audio: Node   ## world_audio.gd (Welt-Sounds, Ambient)
var blood: Node   ## blood_fx.gd (Treffer-Spruehstoss, Blut-Decals, Lachen)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	audio = WorldAudioScript.new()
	audio.name = "WorldAudio"
	add_child(audio)
	blood = BloodScript.new()
	blood.name = "Blood"
	add_child(blood)
	if ground_collider_enabled:
		_ground_col = GPUParticlesCollisionBox3D.new()
		_ground_col.size = Vector3(800, 2, 800)
		_ground_col.position = Vector3(0, -1.0, 0)
		add_child(_ground_col)
	# Vorab zwei Explosionen bauen, damit die erste im Spiel nicht ruckelt.
	for i in 2:
		_make_explosion()

# --- Oeffentliche API ------------------------------------------------------

func spawn_explosion(position: Vector3, scale: float = 1.0) -> void:
	var e: Node3D = null
	if not _expl_free.is_empty():
		e = _expl_free.pop_back()
	elif _expl_all.size() < MAX_EXPLOSIONS:
		e = _make_explosion()
		_expl_free.erase(e)
	else:
		e = _expl_all[0]
		_expl_all.erase(e)
		_expl_all.append(e)
	e.call("play", position, scale)
	audio.call("explosion", position, scale)

func spawn_impact(position: Vector3, normal: Vector3, surface: String = "concrete") -> void:
	var n := normal if normal.length() > 0.01 else Vector3.UP
	if surface == "flesh" or surface == "blood":
		spawn_blood(position, n)
		audio.call("impact", position, surface)
		return
	var fx := _get_impact(false)
	fx.call("play", surface, position, n.normalized(), 1.25)   # etwas kraeftigere Einschlaege (nur Optik)
	audio.call("impact", position, surface)
	spawn_decal(position, n, "res://assets/vfx/bullet_hole.png", Vector3(0.28, 0.4, 0.28), 30.0, randf() * TAU)

## Vorbeiflug-Pfeifen einer Kugel an pos (z. B. naechster Punkt einer Fehlschuss-Bahn zur Kamera).
func play_whiz(pos: Vector3) -> void:
	audio.call("whiz", pos)

## Bequem: pfeift nur, wenn die Bahn from->to naeher als max_dist an der Kamera vorbeifuehrt.
func play_whiz_along(from: Vector3, to: Vector3, max_dist: float = 3.5) -> bool:
	return audio.call("whiz_along", from, to, max_dist)

## Beliebiger Welt-One-Shot (res://assets/sfx/<name>.ogg) auf dem SFX-Bus.
func play_sfx_3d(sfx_name: String, pos: Vector3, volume_db: float = 0.0, unit_size: float = 10.0, max_dist: float = 120.0) -> void:
	audio.call("play_3d", sfx_name, pos, volume_db, unit_size, max_dist)

## Ambient-Bett manuell schalten (sonst automatisch, solange Feuer im Level sind).
func set_ambient(on: bool) -> void:
	audio.call("set_ambient", on)

## Blut-Treffer (blood_fx.gd). dir = Flugrichtung des Geschosses (ZERO = unbekannt, dann -normal);
## strength 1 = Rumpf, ~1.6 Kopftreffer, ~1.5 Scharfschuetzengewehr. Mehrfachmeldungen desselben
## Treffers im selben Frame (Gegner + Waffe) werden zusammengefasst.
func spawn_blood(position: Vector3, normal: Vector3, dir: Vector3 = Vector3.ZERO, strength: float = 1.0) -> void:
	blood.call("spawn", position, normal, dir, strength)

## Blutet dieses Ziel? (false: Fahrzeuge, Drohnen, Meta "surface" != flesh; Hitboxen werden aufgeloest)
func is_bleeder(target: Node) -> bool:
	return BloodScript.is_bleeder(target)

## Grosse Staubwolke (z. B. einstuerzende Fassade). size = Radius in m ca.
func spawn_dust_cloud(position: Vector3, size: float = 3.0) -> void:
	var fx := _get_impact(true)
	fx.call("play", "cloud", position, Vector3.UP, size)

## Brandfleck am Boden.
func spawn_scorch(position: Vector3, normal: Vector3, size: float, lifetime: float = -1.0) -> void:
	spawn_decal(position, normal, "res://assets/vfx/burn_mark.png", Vector3(size, 2.5 + size * 0.4, size), lifetime, randf() * TAU)

func spawn_decal(position: Vector3, normal: Vector3, tex_path: String, size: Vector3, lifetime: float = -1.0, yaw: float = 0.0) -> void:
	if lifetime < 0.0:
		lifetime = decal_lifetime
	var d: Decal
	if _decals.size() >= MAX_DECALS:
		d = _decals.pop_front()
		if not is_instance_valid(d):
			return
	else:
		d = Decal.new()
		d.cull_mask = 1 # nur Layer 1 (Welt); Partikel/Charaktere bleiben sauber
		d.upper_fade = 0.2
		d.lower_fade = 0.3
		d.normal_fade = 0.4
		add_child(d)
	_decals.append(d)
	d.texture_albedo = VfxLib.tex(tex_path)
	d.size = size
	d.modulate = Color(1, 1, 1, 1)
	d.global_transform = Transform3D(VfxLib.basis_from_normal(normal, yaw), position + normal.normalized() * 0.0)
	var tw := d.create_tween()
	tw.tween_interval(lifetime)
	tw.tween_property(d, "modulate:a", 0.0, 4.0)

func debris_material() -> StandardMaterial3D:
	if _debris_mat == null:
		_debris_mat = StandardMaterial3D.new()
		_debris_mat.albedo_texture = VfxLib.tex("res://assets/textures/concrete_wall_008/diffuse.jpg")
		_debris_mat.albedo_color = Color(0.45, 0.42, 0.4)
		_debris_mat.uv1_triplanar = true
		_debris_mat.uv1_world_triplanar = false
		_debris_mat.uv1_scale = Vector3(1.5, 1.5, 1.5)
		_debris_mat.roughness = 0.95
	return _debris_mat

## Gibt false zurueck (und gibt body frei), wenn das Truemmer-Limit erreicht ist.
## Hoechstens so viele neue Truemmer-Koerper pro Frame (mehrere Bomben im selben Frame
## liessen sonst die Physik in eine Todesspirale laufen: 72 Koerper -> 3 FPS).
const MAX_DEBRIS_PER_FRAME := 12
var _debris_frame: int = -1
var _debris_in_frame: int = 0

func add_debris(body: Node3D) -> bool:
	var f := Engine.get_process_frames()
	if f != _debris_frame:
		_debris_frame = f
		_debris_in_frame = 0
	if _debris_count >= MAX_DEBRIS or _debris_in_frame >= MAX_DEBRIS_PER_FRAME:
		body.queue_free()
		return false
	_debris_count += 1
	_debris_in_frame += 1
	add_child(body)
	return true

func schedule_free(body: Node3D, after: float) -> void:
	var tw := body.create_tween()
	tw.tween_interval(after)
	tw.tween_property(body, "scale", Vector3.ONE * 0.05, 0.6)
	tw.tween_callback(func() -> void:
		_debris_count = maxi(_debris_count - 1, 0)
		body.queue_free())

# --- Vorwaermen (Ladebildschirm) ---------------------------------------------

## Alle Effekt-Varianten einmal sichtbar vor der Kamera abspielen (Shader-/Pipeline-Kompilierung, Partikel-
## Compute-Shader, Schatten der Explosionslichter, Truemmer, Decals), ohne Ton. Danach warmup_end() aufrufen.
## Ohne das kompilierte die erste Bombe im Spiel ~20 Pipelines (rail_yard: 288 ms Ruckler).
func warmup_begin(at: Vector3, fwd: Vector3) -> void:
	var was := bool(audio.get("enabled"))
	audio.set("enabled", false)
	audio.call("prewarm")
	var side := fwd.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	spawn_explosion(at + fwd * 4.0, 0.6)
	var i := 0
	for surf in ["concrete", "metal", "wood", "dirt"]:
		spawn_impact(at + side * (float(i) - 2.0) * 0.6 + Vector3.UP * 1.2, -fwd, surf)
		i += 1
	blood.call("spawn", at + side * 1.2 + Vector3.UP * 1.2, -fwd, fwd, 1.6)   # Blut-Shader/Partikel vorkompilieren
	spawn_dust_cloud(at + fwd * 2.0 - side * 2.0, 2.0)
	spawn_scorch(at + fwd * 2.0, Vector3.UP, 2.0, 1.0)
	# Pools ganz auffuellen: jeder neue Einschlag-Effekt baut Partikel, Materialien und Kurven-Texturen beim
	# ersten Bedarf, sonst mitten im Feuergefecht (bis zu 14 + 4 Mal)
	var k := 0
	while _impact_count < MAX_IMPACTS:
		_get_impact(false).call("play", "dirt", at + fwd * 3.0 + side * (float(k % 5) - 2.0) * 0.5, -fwd, 0.6)
		k += 1
	while _cloud_count < 4:
		_get_impact(true).call("play", "cloud", at + fwd * 3.0, Vector3.UP, 1.0)
	# Explosions-Pool ebenso: mehrere gleichzeitige Detonationen (rail_yard Bombenteppich, 3+ Bomben) bauten
	# neue Explosionen mitten im Spiel (10 Partikelsysteme, +14 Pipelines, 120 ms)
	var ei := 0
	while _expl_all.size() < MAX_EXPLOSIONS or not _expl_free.is_empty():
		spawn_explosion(at + fwd * (6.0 + float(ei) * 1.5), 1.0)
		ei += 1
	audio.set("enabled", was)

func warmup_end() -> void:
	for e in _expl_all:
		if e.call("is_busy"):
			e.call("reset")
	for c in get_children():
		if c is RigidBody3D:
			c.queue_free()
		elif c.get_script() == ImpactScript:
			c.call("reset")
	_debris_count = 0
	blood.call("clear")
	for d in _decals:
		if is_instance_valid(d):
			d.queue_free()
	_decals.clear()

# --- Pools -----------------------------------------------------------------

func _make_explosion() -> Node3D:
	var e: Node3D = ExplosionScript.new()
	add_child(e)
	e.visible = false
	e.connect("finished", _on_explosion_finished)
	_expl_all.append(e)
	_expl_free.append(e)
	return e

func _on_explosion_finished(e: Node3D) -> void:
	if not _expl_free.has(e):
		_expl_free.append(e)

func _get_impact(big: bool) -> Node3D:
	var pool := _cloud_free if big else _impact_free
	if not pool.is_empty():
		return pool.pop_back()
	var count := _cloud_count if big else _impact_count
	var limit := 4 if big else MAX_IMPACTS
	if count >= limit:
		# Pool erschoepft: ersten wiederverwenden (ggf. noch aktiv, Effekt wird neu gestartet)
		var all := get_children().filter(func(c: Node) -> bool: return c.get_script() == ImpactScript and c.big == big)
		return all[randi() % all.size()]
	var fx: Node3D = ImpactScript.new()
	fx.big = big
	add_child(fx)
	fx.connect("finished", func(f: Node3D) -> void:
		var p := _cloud_free if big else _impact_free
		if not p.has(f):
			p.append(f))
	if big:
		_cloud_count += 1
	else:
		_impact_count += 1
	return fx
