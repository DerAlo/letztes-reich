class_name SoldierIK
extends SkeletonModifier3D
## Prozedurale Oberkoerper-Pose fuer Soldaten (laeuft nach dem AnimationTree):
## 1. Wirbelsaeule (Abdomen/Torso/Chest) dreht sich anteilig in Zielrichtung (Yaw/Pitch).
## 2. Waffen-Frame W wird an der Schulter (Chest-lokal) verankert und zeigt auf das Ziel
##    (aim_weight 1) bzw. in Low-Ready (0). Rueckstoss/Nachladen verschieben W.
## 3. Beide Arme per analytischer Zwei-Knochen-IK an Griff (rechts) und Handschutz (links).
## Arbeitet im Skelett-Raum: +Z = Blickrichtung des Modells, +X = linke Koerperseite, Meter.
## Knochennamen sind die des SWAT-Rigs (siehe tools/bake_soldier.gd); ein Mixamo-Rig wird beim
## Bake auf dieselben Namen gebracht.

var aim_yaw: float = 0.0
var aim_pitch: float = 0.0
var aim_weight: float = 0.0
var recoil: float = 0.0
var reload_t: float = -1.0           # <0 aus, sonst 0..1 Fortschritt
var spine_weight: float = 1.0

## Schaftkappe (Kolbenende) in Chest-lokalen Koordinaten.
var shoulder_pocket := Vector3(-0.085, 0.12, 0.07)
## Abstand Kolbenende -> Griff entlang der Waffe.
var stock_length: float = 0.31
## Handgelenk-Transform relativ zum Waffen-Frame (rechts am Griff, links am Handschutz).
var grip_r := Transform3D.IDENTITY
var grip_l := Transform3D.IDENTITY
var pole_r := Vector3(1.0, -1.0, 0.35)
var pole_l := Vector3(-0.6, -1.0, 0.0)
## Fingerkruemmung je Gelenk [Grundgelenk, Mittel, End] in rad (Beugung zur Handflaeche).
var curl_r := Vector3(1.25, 1.35, 0.7)
var curl_r_index := Vector3(0.35, 0.7, 0.35)
var curl_l := Vector3(1.0, 1.15, 0.6)
var curl_thumb := Vector3(0.25, 0.45, 0.4)

## Ergebnis des letzten Durchlaufs (Skelett-Raum)
var weapon_xform := Transform3D.IDENTITY

var _b: Dictionary = {}
var _ok: bool = false
var _fingers: Array = []

const SPINE := [["Abdomen", 0.25], ["Torso", 0.35], ["Chest", 0.4]]

static func hand_basis(fingers: Vector3, back: Vector3) -> Basis:
	var y := fingers.normalized()
	var x := y.cross(back).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func setup_bones() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	for nm in ["Abdomen", "Torso", "Chest", "Shoulder.L", "UpperArm.L", "LowerArm.L", "Wrist.L",
			"Shoulder.R", "UpperArm.R", "LowerArm.R", "Wrist.R"]:
		_b[nm] = sk.find_bone(nm)
		if _b[nm] < 0:
			push_warning("SoldierIK: bone missing " + nm)
			return
	_fingers.clear()
	for side in ["L", "R"]:
		for f in ["Index", "Middle", "Ring", "Pinky", "Thumb"]:
			for j in 3:
				var fi := sk.find_bone("%s%d.%s" % [f, j + 1, side])
				if fi >= 0:
					_fingers.append([fi, side, f, j, sk.get_bone_rest(fi).basis.get_rotation_quaternion()])
	_ok = true

func _process_modification() -> void:
	if not _ok:
		setup_bones()
		if not _ok:
			return
	var sk := get_skeleton()
	# 1. Wirbelsaeule
	var sy := aim_yaw * spine_weight
	var sp := aim_pitch * spine_weight * lerpf(0.4, 1.0, aim_weight)
	for e in SPINE:
		var bi: int = _b[e[0]]
		var f: float = e[1]
		var r := Basis(Vector3.UP, sy * f) * Basis(Vector3.RIGHT, -sp * f)
		var g := sk.get_bone_global_pose(bi)
		var pg := sk.get_bone_global_pose(sk.get_bone_parent(bi))
		sk.set_bone_pose_rotation(bi, (pg.basis.inverse() * (r * g.basis)).get_rotation_quaternion())
	# 2. Waffen-Frame
	var chest := sk.get_bone_global_pose(_b["Chest"])
	chest.basis = chest.basis.orthonormalized()
	var d_aim := Basis(Vector3.UP, aim_yaw) * Basis(Vector3.RIGHT, -aim_pitch) * Vector3.BACK
	var wb_aim := Basis.looking_at(d_aim, Vector3.UP)
	var butt_aim := chest * shoulder_pocket
	var w_aim := Transform3D(wb_aim, butt_aim + wb_aim * Vector3(0, 0, -stock_length))
	var d_low := Basis(Vector3.UP, aim_yaw * 0.5 + 0.45) * Basis(Vector3.RIGHT, deg_to_rad(28.0)) * Vector3.BACK
	var wb_low := Basis.looking_at(d_low, Vector3.UP)
	var butt_low := chest * (shoulder_pocket + Vector3(0.05, -0.1, 0.04))
	var w_low := Transform3D(wb_low, butt_low + wb_low * Vector3(0, 0, -stock_length))
	var w := w_low.interpolate_with(w_aim, clampf(aim_weight, 0.0, 1.0))
	if recoil > 0.0:
		w = w * Transform3D(Basis(Vector3.RIGHT, recoil * 0.1), Vector3(0, recoil * 0.008, recoil * 0.045))
	var left_target := w * grip_l
	if reload_t >= 0.0:
		var rt := reload_t
		var tilt := smoothstep(0.0, 0.12, rt) * (1.0 - smoothstep(0.85, 1.0, rt))
		w = w * Transform3D(Basis(Vector3.FORWARD, deg_to_rad(-35.0) * tilt) * Basis(Vector3.RIGHT, deg_to_rad(18.0) * tilt), Vector3(0.03, 0.05, 0.0) * tilt)
		var mag := w * Transform3D(grip_l.basis.rotated(Vector3.FORWARD, 0.6), Vector3(-0.03, -0.17, -0.07))
		var pouch := Transform3D(chest.basis * Basis(Vector3.RIGHT, -1.2), chest * Vector3(0.1, -0.16, 0.16))
		var grip := w * grip_l
		if rt < 0.2:
			left_target = grip.interpolate_with(mag, smoothstep(0.05, 0.2, rt))
		elif rt < 0.45:
			left_target = mag.interpolate_with(pouch, smoothstep(0.2, 0.45, rt))
		elif rt < 0.7:
			left_target = pouch.interpolate_with(mag, smoothstep(0.5, 0.7, rt))
		else:
			left_target = mag.interpolate_with(grip, smoothstep(0.75, 0.95, rt))
	weapon_xform = w
	# 3. Arme
	_ik_arm(sk, "R", w * grip_r, w.basis * pole_r)
	_ik_arm(sk, "L", left_target, w.basis * pole_l)
	# 4. Finger um Griff/Handschutz schliessen
	for fd in _fingers:
		var c: Vector3
		if fd[2] == "Thumb":
			c = curl_thumb
		elif fd[1] == "R":
			c = curl_r_index if fd[2] == "Index" else curl_r
		else:
			c = curl_l
		var ang: float = c[fd[3]]
		sk.set_bone_pose_rotation(fd[0], fd[4] * Quaternion(Vector3.RIGHT, -ang))

func _ik_arm(sk: Skeleton3D, side: String, target: Transform3D, pole: Vector3) -> void:
	var sh: int = _b["Shoulder." + side]
	var up: int = _b["UpperArm." + side]
	var lo: int = _b["LowerArm." + side]
	var ha: int = _b["Wrist." + side]
	var pg := sk.get_bone_global_pose(sk.get_bone_parent(sh))
	pg.basis = pg.basis.orthonormalized()
	var sh_rest := sk.get_bone_rest(sh)
	var sh_g := pg * sh_rest
	var up_rest := sk.get_bone_rest(up)
	var up_g := sh_g * up_rest
	var lo_rest := sk.get_bone_rest(lo)
	var ha_rest := sk.get_bone_rest(ha)
	var l1 := lo_rest.origin.length()
	var l2 := ha_rest.origin.length()
	var a := up_g.origin
	var v := target.origin - a
	var dist := clampf(v.length(), 0.05, (l1 + l2) * 0.999)
	var n := v.normalized()
	var pv := pole - n * n.dot(pole)
	if pv.length_squared() < 1e-6:
		pv = Vector3.DOWN - n * n.dot(Vector3.DOWN)
	pv = pv.normalized()
	var x := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var elbow := a + n * x + pv * h
	var wrist := a + n * dist
	var bend_n := (elbow - a).cross(wrist - elbow)
	# Oberarm
	var want1 := (elbow - a).normalized()
	var cur1 := (up_g.basis * lo_rest.origin).normalized()
	var up_b := Basis(Quaternion(cur1, want1)) * up_g.basis
	up_b = _twist_align(up_b, want1, bend_n)
	# Unterarm
	var lo_g := Transform3D(up_b, a) * lo_rest
	var want2 := (wrist - lo_g.origin).normalized()
	var cur2 := (lo_g.basis * ha_rest.origin).normalized()
	var lo_b := Basis(Quaternion(cur2, want2)) * lo_g.basis
	lo_b = _twist_align(lo_b, want2, bend_n)
	# Hand
	var ha_b := target.basis.orthonormalized()
	sk.set_bone_pose_rotation(sh, sh_rest.basis.get_rotation_quaternion())
	sk.set_bone_pose_rotation(up, (sh_g.basis.inverse() * up_b).get_rotation_quaternion())
	sk.set_bone_pose_rotation(lo, (up_b.inverse() * lo_b).get_rotation_quaternion())
	sk.set_bone_pose_rotation(ha, (lo_b.inverse() * ha_b).get_rotation_quaternion())

## Dreht b um die Achse axis so, dass die lokale X-Achse (Beuge-Achse) parallel zu bend liegt
## (kleinster Winkel, Vorzeichen egal).
func _twist_align(b: Basis, axis: Vector3, bend: Vector3) -> Basis:
	if bend.length_squared() < 1e-8:
		return b
	var t := (bend - axis * axis.dot(bend)).normalized()
	var x := b.x - axis * axis.dot(b.x)
	if x.length_squared() < 1e-8:
		return b
	x = x.normalized()
	if x.dot(t) < 0.0:
		t = -t
	var ang := x.signed_angle_to(t, axis)
	return Basis(axis, ang) * b
