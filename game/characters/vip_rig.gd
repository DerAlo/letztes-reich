extends Node
## Treiber fuer realistische VIP-Modelle (geriggtes GLB): uebertraegt die Drehung der Gelenk-Nodes
## (arms/legs/head aus VipModels-API) auf die Knochen des Skeleton3D. Die Nodes sitzen exakt auf den
## Gelenkpunkten der Knochen, daher dreht sich alles, was Level-Skripte an einen Arm-Node haengen
## (Koffer, Granate ...), um denselben Punkt wie der Arm des Modells.
## Cutscenes bleiben unveraendert: sie drehen weiterhin nur rotation.x der Nodes.
##
## Fortbewegung: Die VIP-GLBs haben keine Animationen. Bewegt ein Level/eine Cutscene die Figur (Tween auf
## position/global_position), misst der Treiber die Geschwindigkeit des Root-Nodes (lokal zum Eltern-Node,
## d. h. Mitfahren in Fahrzeugen zaehlt nicht) und legt einen prozeduralen Geh-/Laufzyklus darueber:
## Oberschenkel, Knie, Fuss, Becken-Wippen, Oberkoerper-Vorlage und Armschwung (nur bei haengendem Arm,
## Posen wie "Haende hoch"/Pistole bleiben unangetastet). Schrittlaenge folgt dem Tempo (kein Gleiten),
## im Stand geht alles auf die Ruhelage zurueck.

var skel: Skeleton3D
## Je Eintrag: {"bone": int, "node": Node3D, "s": Basis (Root->Skelett), "g": Basis (globale Ruhelage),
##              "p": Basis (globale Ruhelage des Elternknochens, invertiert), "key": "arm_l"/"leg_r"/...}
var links: Array[Dictionary] = []
## Fortbewegung (von VipModels._make_real gesetzt): Root der Figur, Modell-Halter (Becken-Wippen),
## Zusatzknochen {name: {"bone", "g", "p"}} (calf/foot/lowerarm/spine_01), Root->Skelett-Basis.
var root: Node3D
var holder: Node3D
var extra: Dictionary = {}
var s_basis: Basis = Basis.IDENTITY

var _last: Array[Basis] = []
var _extra_last: Dictionary = {}
var _prev_pos := Vector3.ZERO
var _has_prev := false
var _spd := 0.0          # geglaettete Bodengeschwindigkeit (m/s, >= 0)
var _dir := 1.0          # +1 vorwaerts, -1 rueckwaerts
var _phase := 0.0
var _walk_on := false    # Zyklus aktiv (oder klingt noch aus)
var _holder_y := 0.0
var _off: Dictionary = {}    # key -> Winkel (rad, Root-Raum um X) fuer die Gelenk-Nodes

const TELEPORT := 1.5    # m pro Frame: darueber Sprung (Checkpoint/Cutscene-Skip), kein Laufen

## Idle-Leben im Stand (additiv auf die Pose der Level/Cutscenes): Atmen (Brustkorb hebt sich, Schultern gehen
## mit, Hals gleicht aus), langsames Gewichtsverlagern (Becken kippt, Oberschenkel/Ruecken gleichen aus, das
## entlastete Knie beugt sich leicht), Blickwechsel (Kopf/Hals, ab und zu zum Spieler), haengende Unterarme minimal.
## Je Figur zufaellige Frequenzen/Phasen. Nur in Kamera-Naehe (IDLE_RANGE), blendet beim Gehen/Laufen aus, aus bei
## Pause, liegender/gekippter Figur (Tod/Sturz), idle_enabled = false oder Meta "no_idle" am Root.
var idle_enabled: bool = true
const IDLE_RANGE := 25.0
const IDLE_BONES := ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "clavicle_l", "clavicle_r",
	"calf_l", "calf_r", "foot_l", "foot_r", "lowerarm_l", "lowerarm_r"]
var _idle_w := 0.0
var _it := 0.0
var _rng := RandomNumberGenerator.new()
var _br_f := 0.24        # Atemfrequenz (Hz)
var _br_ph := 0.0
var _sw_f := 0.1         # Gewichtsverlagerung (Hz, zwei ueberlagerte Wellen)
var _sw_f2 := 0.037
var _sw_ph := 0.0
var _sw_ph2 := 0.0
var _look := Vector2.ZERO        # x Yaw, y Pitch (rad)
var _look_v := Vector2.ZERO
var _look_tgt := Vector2.ZERO
var _look_hold := 0.0
var _idle_b: Dictionary = {}     # Zusatzknochen -> Basis (Root-Raum), wird mit dem Geh-Winkel verknuepft
var _offb: Dictionary = {}       # Gelenk-Node-Key -> Basis (Root-Raum), additiv auf die Node-Drehung

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last.resize(links.size())
	if holder != null:
		_holder_y = holder.position.y
	_rng.randomize()
	_br_f = _rng.randf_range(0.2, 0.28)
	_br_ph = _rng.randf() * TAU
	_sw_f = _rng.randf_range(0.075, 0.12)
	_sw_f2 = _rng.randf_range(0.03, 0.05)
	_sw_ph = _rng.randf() * TAU
	_sw_ph2 = _rng.randf() * TAU
	_look_hold = _rng.randf_range(0.5, 3.0)
	_apply(true)

func _process(dt: float) -> void:
	_walk(dt)
	_idle(dt)
	_apply(false)

func _apply(force: bool) -> void:
	if skel == null or not is_instance_valid(skel):
		return
	for i in links.size():
		var l: Dictionary = links[i]
		var n := l["node"] as Node3D
		if not is_instance_valid(n):
			continue
		var b := n.basis
		var a: float = _off.get(l.get("key", ""), 0.0)
		if a != 0.0:
			b = Basis(Vector3.RIGHT, a) * b.orthonormalized()
		if _offb.has(l.get("key", "")):
			b = (_offb[l["key"]] as Basis) * b.orthonormalized()
		if not force and b.is_equal_approx(_last[i]):
			continue
		_last[i] = b
		var s: Basis = l["s"]
		var rs := s.inverse() * b.orthonormalized() * s          # Drehung im Skelettraum
		_pose(int(l["bone"]), rs, l["g"], l["p"])

func _pose(bone: int, rs: Basis, g: Basis, p_inv: Basis) -> void:
	var local := p_inv * (rs * g)
	skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion())

## Zusatzknochen um a (rad, Root-Raum um X) relativ zur Ruhelage drehen (Eltern-Drehung wird vererbt).
func _pose_extra(bname: String, a: float, force: bool = false) -> void:
	if not extra.has(bname):
		return
	if not force and is_equal_approx(float(_extra_last.get(bname, 0.0)), a) and _extra_last.has(bname):
		return
	_extra_last[bname] = a
	var e: Dictionary = extra[bname]
	var rb := Basis(Vector3.RIGHT, a)
	if _idle_b.has(bname):
		rb = (_idle_b[bname] as Basis) * rb
	var rs := s_basis.inverse() * rb * s_basis
	_pose(int(e["bone"]), rs, e["g"], e["p"])

func _walk(dt: float) -> void:
	if root == null or not is_instance_valid(root) or dt <= 0.0:
		return
	var p := root.position
	var v := 0.0
	var fwd := 1.0
	if _has_prev:
		var d := p - _prev_pos
		d.y = 0.0
		var dist := d.length()
		if dist < TELEPORT:
			v = dist / dt
			if dist > 1e-5:
				var f := -root.basis.z
				f.y = 0.0
				fwd = 1.0 if f.dot(d) >= -0.3 * dist else -1.0
	_prev_pos = p
	_has_prev = true
	if v > 8.0:
		v = 0.0    # Ruckler/Teleport ueber mehrere Frames
	# Glaettung: schnell anlaufen, etwas langsamer auslaufen (Tween-Enden sind abrupt)
	_spd = lerpf(_spd, v, clampf(dt * (10.0 if v > _spd else 7.0), 0.0, 1.0))
	if v > 0.05:
		_dir = fwd
	if _spd < 0.02 and not _walk_on:
		return
	var amp := smoothstep(0.06, 0.6, _spd)
	var run := smoothstep(2.3, 3.6, _spd)
	if amp < 0.002:
		_spd = 0.0
		_reset_walk()
		return
	_walk_on = true
	# Schrittlaenge (voller Zyklus = zwei Schritte) waechst mit dem Tempo -> Fuesse "greifen" den Boden
	var stride := lerpf(clampf(0.75 + 0.42 * _spd, 0.8, 1.55), clampf(1.3 + 0.38 * _spd, 2.0, 2.8), run)
	_phase = fmod(_phase + _spd * dt / stride * TAU * _dir, TAU * 64.0)
	var slow := clampf(_spd / 1.2, 0.35, 1.0)          # langsames Schlurfen: kleinere Ausschlaege
	var thigh_a := lerpf(0.36, 0.62, run) * amp * slow
	var knee_base := lerpf(0.07, 0.3, run) * amp
	var knee_a := lerpf(0.95, 1.65, run) * amp * slow
	for i in 2:
		var ph := _phase + float(i) * PI
		var sn := sin(ph)
		var thigh := thigh_a * sn + 0.12 * run * amp
		var knee := knee_base + knee_a * pow(maxf(0.0, cos(ph + 0.3)), 2.0)
		var side := "l" if i == 0 else "r"
		_off["leg_" + side] = thigh
		_pose_extra("calf_" + side, -knee)
		# Fuss etwa waagerecht halten, beim Abstossen (Bein hinten) Zehen leicht strecken
		var toe := -0.25 * amp * maxf(0.0, -sn) * maxf(0.0, cos(ph))
		_pose_extra("foot_" + side, (knee - thigh) * 0.8 + toe)
		# Arm gegengleich zum Bein derselben Seite, nur wenn der Arm (Node) ungefaehr haengt
		var arm_key := "arm_" + side
		var w := 1.0
		for l: Dictionary in links:
			if l.get("key", "") == arm_key and is_instance_valid(l["node"]):
				w = 1.0 - smoothstep(0.05, 0.3, absf((l["node"] as Node3D).rotation.x))
				break
		var arm_a := lerpf(0.26, 0.55, run) * amp * slow * w
		_off[arm_key] = -arm_a * sn
		_pose_extra("lowerarm_" + side, (lerpf(0.12, 1.25, run) + 0.15 * maxf(0.0, -sn)) * amp * w)
	_pose_extra("spine_01", -(0.035 + 0.13 * run) * amp)
	if holder != null and is_instance_valid(holder):
		var bob := lerpf(0.022, -0.035, run) * cos(2.0 * _phase) - (0.012 + 0.045 * run)
		holder.position.y = _holder_y + bob * amp

func _reset_walk() -> void:
	if not _walk_on:
		return
	_walk_on = false
	_off.clear()
	for bname: String in extra:
		_pose_extra(bname, 0.0)
	if holder != null and is_instance_valid(holder):
		holder.position.y = _holder_y

# ------------------------------------------------------------------ Idle-Leben

## Soll-Staerke des Idle-Lebens (0 = aus): steht, ist sichtbar, aufrecht, nahe der Kamera.
func _idle_want() -> float:
	if not idle_enabled or root == null or not is_instance_valid(root) or not root.is_inside_tree():
		return 0.0
	if root.has_meta("no_idle") or not root.is_visible_in_tree():
		return 0.0
	if root.global_basis.y.normalized().dot(Vector3.UP) < 0.85:
		return 0.0
	if holder != null and is_instance_valid(holder) and holder.global_basis.y.normalized().dot(Vector3.UP) < 0.85:
		return 0.0
	var cam := root.get_viewport().get_camera_3d()
	if cam == null or cam.global_position.distance_squared_to(root.global_position) > IDLE_RANGE * IDLE_RANGE:
		return 0.0
	return 1.0 - smoothstep(0.03, 0.35, _spd)

func _idle(dt: float) -> void:
	if dt <= 0.0 or skel == null or not is_instance_valid(skel) or get_tree().paused:
		return
	_idle_w = move_toward(_idle_w, _idle_want(), dt * 1.5)
	if _idle_w <= 0.0:
		if not _idle_b.is_empty() or not _offb.is_empty():
			var had := _idle_b.keys()
			_idle_b.clear()
			_offb.clear()
			for bname: String in had:
				_pose_extra(bname, float(_extra_last.get(bname, 0.0)), true)
		return
	_it += dt
	var w := _idle_w
	var t := _it
	# Atmen: Einatmen etwas kuerzer als Ausatmen (verzerrte Sinuswelle), -1 .. 1
	var ph := fmod(t * _br_f * TAU + _br_ph, TAU)
	var br := sin(ph + 0.35 * sin(ph)) * w
	# Gewichtsverlagerung: zwei langsame Wellen, an den Enden verweilend
	var s := 0.7 * sin(t * _sw_f * TAU + _sw_ph) + 0.3 * sin(t * _sw_f2 * TAU + _sw_ph2)
	s = tanh(2.2 * s) / tanh(2.2) * w
	var roll := 0.021 * s                       # Becken kippt ~1,2 Grad (+: rechte Huefte hoch)
	var kl := 0.07 * maxf(0.0, s)               # entlastetes Knie (Seite der tiefen Huefte)
	var kr := 0.07 * maxf(0.0, -s)
	_idle_look(dt)
	var yaw := _look.x * w
	var pitch := _look.y * w
	var nod := 0.006 * sin(t * 0.53 + _br_ph) * w    # kleine Eigenbewegung des Kopfes
	var hang := [_hang("arm_l"), _hang("arm_r")]
	_idle_b["pelvis"] = Basis(Vector3.FORWARD, -roll) * Basis(Vector3.UP, 0.35 * roll)
	_idle_b["spine_01"] = Basis(Vector3.FORWARD, 0.75 * roll)
	_idle_b["spine_02"] = Basis(Vector3.RIGHT, 0.009 * br) * Basis(Vector3.FORWARD, 0.2 * roll)
	_idle_b["spine_03"] = Basis(Vector3.RIGHT, 0.014 * br)
	_idle_b["neck_01"] = Basis(Vector3.UP, 0.35 * yaw) * Basis(Vector3.RIGHT, -0.02 * br + 0.4 * pitch)
	_idle_b["clavicle_l"] = Basis(Vector3.FORWARD, 0.012 * br)
	_idle_b["clavicle_r"] = Basis(Vector3.FORWARD, -0.012 * br)
	_idle_b["calf_l"] = Basis(Vector3.RIGHT, -kl)
	_idle_b["calf_r"] = Basis(Vector3.RIGHT, -kr)
	_idle_b["foot_l"] = Basis(Vector3.RIGHT, 0.5 * kl)
	_idle_b["foot_r"] = Basis(Vector3.RIGHT, 0.5 * kr)
	_idle_b["lowerarm_l"] = Basis(Vector3.RIGHT, (0.025 + 0.01 * br) * w * float(hang[0]))
	_idle_b["lowerarm_r"] = Basis(Vector3.RIGHT, (0.025 + 0.01 * br) * w * float(hang[1]))
	# Oberschenkel gleichen die Beckenkippung aus (Beine bleiben senkrecht), entlastetes Bein leicht vor
	_offb["leg_l"] = Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, 0.5 * kl)
	_offb["leg_r"] = Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, 0.5 * kr)
	_offb["head"] = Basis(Vector3.UP, 0.65 * yaw) * Basis(Vector3.RIGHT, 0.6 * pitch + nod)
	for bname: String in _idle_b:
		_pose_extra(bname, float(_extra_last.get(bname, 0.0)), true)

## 1 = Arm (Gelenk-Node) haengt ungefaehr, 0 = Pose (Haende hoch, Funkgeraet ...).
func _hang(key: String) -> float:
	for l: Dictionary in links:
		if l.get("key", "") == key and is_instance_valid(l["node"]):
			return 1.0 - smoothstep(0.05, 0.3, absf((l["node"] as Node3D).rotation.x))
	return 1.0

## Blickwechsel: Ziel halten, dann neues waehlen (meist geradeaus/leicht seitlich, manchmal deutlich, ab und zu
## zum nahen Spieler); gedaempfte Feder -> zuegige, weich auslaufende Kopfdrehung.
func _idle_look(dt: float) -> void:
	_look_hold -= dt
	if _look_hold <= 0.0:
		_look_hold = _rng.randf_range(1.6, 5.5)
		var r := _rng.randf()
		var tgt := Vector2.ZERO
		var pl := get_tree().get_first_node_in_group("player") as Node3D
		if r < 0.3 and pl != null and _player_look(pl, tgt):
			tgt = _look_tgt
		elif r < 0.6:
			tgt = Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.05, 0.04))
		else:
			var sgn := -1.0 if _rng.randf() < 0.5 else 1.0
			tgt = Vector2(sgn * _rng.randf_range(0.2, 0.5), _rng.randf_range(-0.08, 0.05))
		_look_tgt = tgt
	var k := 22.0
	_look_v += ((_look_tgt - _look) * k - _look_v * 2.0 * sqrt(k)) * dt
	_look += _look_v * dt

## Blickrichtung zum Spieler (Root-Raum), nur wenn nah und grob vor der Figur; setzt _look_tgt.
func _player_look(pl: Node3D, _unused: Vector2) -> bool:
	var head_p := root.global_position + Vector3(0.0, 1.6, 0.0)
	var d := pl.global_position + Vector3(0.0, 1.5, 0.0) - head_p
	if d.length() > 9.0:
		return false
	var l := root.global_basis.inverse() * d
	var yaw := atan2(-l.x, -l.z)
	if absf(yaw) > 1.0:
		return false
	_look_tgt = Vector2(clampf(yaw, -0.6, 0.6), clampf(atan2(l.y, Vector2(l.x, l.z).length()), -0.25, 0.2))
	return true
