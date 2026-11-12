class_name FpArms
extends Node3D
## Erste-Person-Arme (Ärmel + Handschuhe) am Viewmodel.
## Hängt im Kameraraum der Waffe (Geschwister des Pivots): Schultern bleiben am Körper, die Hände werden
## jedes Bild per Zwei-Knochen-IK an Griff/Handschutz des (federnden, rückstoßenden) Pivots gesetzt.
## Modell: assets/characters/fp_arms/fp_arms.scn (Bake: game/weapons/tools/bake_fp_arms.gd), CC BY 4.0 Cransh.

const SCENE := "res://assets/characters/fp_arms/fp_arms.scn"
const VIEW_LAYER_BIT: int = 1 << 19
const SIDES := ["L", "R"]
## Schultergelenke im Kameraraum (das Rig hat sie direkt am Auge -> Arme füllten das Bild)
const SHOULDER_R := Vector3(0.19, -0.24, 0.07)
const SHOULDER_L := Vector3(-0.19, -0.24, 0.07)
## Waffenspezifischer Schulterversatz (vor add_child setzen; x wird für links gespiegelt)
var shoulder_off: Vector3 = Vector3.ZERO
## Längenfaktoren Oberarm / Unterarm (FPS-Rig ist gestaucht; Ziel ~0,29 m / ~0,25 m)
const UPPER_SCALE := 2.2
const FORE_SCALE := 1.3

var sk: Skeleton3D
var _ok: bool = false
var _sk_rot_inv: Basis                     # Kameraraum -> Skelettraum (nur Rotation)
var _sk_inv: Transform3D
var _base: Array = []                      # gebackene lokale Posen [pos, rot] je Knochen
var _b: Dictionary = {}                    # side -> {clav, up, fore, tw: [3], ctrl, hand, fingers: []}
var _hand_cam: Dictionary = {}             # side -> Hand-Basis (Kameraraum, Griffhaltung aus dem Rig)
var _pole_cam: Dictionary = {}             # side -> Ellbogen-Polziel (Kameraraum)
var _len: Dictionary = {}                  # side -> [Oberarm, Unterarm] (Skelettraum)
var _twist_ref: Dictionary = {}            # side -> Basis Hand relativ zu Twist-Ende (gebacken)
var _mirror_grip: bool = false             # Stützhand mit gespiegelter Griffhaltung (Pistole)

func _ready() -> void:
	if not ResourceLoader.exists(SCENE):
		return
	var inst: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(inst)
	sk = inst.get_node("Skeleton") as Skeleton3D
	for mi: MeshInstance3D in inst.find_children("*", "MeshInstance3D", true, false):
		mi.layers = VIEW_LAYER_BIT
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 0.5
	for i in sk.get_bone_count():
		_base.append([sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i)])
	var st: Transform3D = inst.transform * sk.transform
	_sk_inv = st.affine_inverse()
	_sk_rot_inv = st.basis.orthonormalized().inverse()
	var srot: Basis = st.basis.orthonormalized()
	_fit_body()
	for s: String in SIDES:
		var d := {
			"clav": _fb("Arm_%s_" % s), "up": _fb("UpArm_%s_" % s), "fore": _fb("Forearm_%s_" % s),
			"tw": [_fb("BoneTwist_03.%s_" % s), _fb("BoneTwist_02.%s_" % s), _fb("BoneTwist_01.%s_" % s)],
			"ctrl": _fb("IK_Hand_Cntrl_%s_" % s), "hand": _fb("Hand_%s_" % s), "fingers": [],
		}
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).begins_with("Bone_%s." % s):
				d.fingers.append(i)
		_b[s] = d
		var hg: Transform3D = sk.get_bone_global_pose(d.hand)
		_hand_cam[s] = (srot * hg.basis.orthonormalized())
		var up_o: Vector3 = sk.get_bone_global_pose(d.up).origin
		var fo_o: Vector3 = sk.get_bone_global_pose(d.fore).origin
		var we: int = _fb("BoneTwist_01.%s_end" % s)
		var wrist: Vector3 = sk.get_bone_global_pose(we).origin if we >= 0 else hg.origin
		_len[s] = [up_o.distance_to(fo_o), fo_o.distance_to(wrist)]
		var tw_end: Basis = sk.get_bone_global_pose(d.tw[2]).basis.orthonormalized()
		_twist_ref[s] = tw_end.inverse() * hg.basis.orthonormalized()
		# Ellbogen nach unten-außen (die Rig-Polziele liegen auf Schulterhöhe -> Ellbogen kippte nach oben)
		_pole_cam[s] = Vector3(0.4 * (-1.0 if s == "L" else 1.0), -0.6, -0.05)
	_ok = true

## Schultern versetzen und Ober-/Unterarm strecken (wird zur neuen Grundpose).
func _fit_body() -> void:
	for s: String in SIDES:
		var clav: int = _fb("Arm_%s_" % s)
		var up: int = _fb("UpArm_%s_" % s)
		var fore: int = _fb("Forearm_%s_" % s)
		var want: Vector3 = _sk_inv * ((SHOULDER_R if s == "R" else SHOULDER_L) + shoulder_off * Vector3(1.0 if s == "R" else -1.0, 1.0, 1.0))
		var shift: Vector3 = want - sk.get_bone_global_pose(up).origin
		var par: int = sk.get_bone_parent(clav)
		var pb: Basis = sk.get_bone_global_pose(par).basis.orthonormalized() if par >= 0 else Basis()
		sk.set_bone_pose_position(clav, sk.get_bone_pose_position(clav) + pb.inverse() * shift)
		sk.set_bone_pose_position(fore, sk.get_bone_pose_position(fore) * UPPER_SCALE)
		for t in [_fb("BoneTwist_02.%s_" % s), _fb("BoneTwist_01.%s_" % s)]:
			sk.set_bone_pose_position(t, sk.get_bone_pose_position(t) * FORE_SCALE)
	for i in sk.get_bone_count():
		_base[i] = [sk.get_bone_pose_position(i), sk.get_bone_pose_rotation(i)]

func _fb(prefix: String) -> int:
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).begins_with(prefix):
			return i
	return -1

func set_pole(side: String, p: Vector3) -> void:
	_pole_cam[side] = p

## Basis der gebackenen Griffhand (Kameraraum). mirrored: rechte Griffhaltung auf links gespiegelt.
func grip_basis(side: String, mirrored: bool = false) -> Basis:
	if mirrored:
		var m := Basis(Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
		var other: String = "R" if side == "L" else "L"
		return m * (_hand_cam[other] as Basis) * m
	return _hand_cam[side]

## Stützhand-Finger: gespiegelte Griff-Finger der anderen Hand (open: 0 = gebacken, 1 = Ruhe/gestreckt).
func set_support_fingers(side: String, mirrored: bool, open: float, thumb_open: float = 0.0, thumb_own: bool = false, thumb_rot: Vector3 = Vector3.ZERO) -> void:
	if not _ok:
		return
	_mirror_grip = mirrored
	var other: String = "R" if side == "L" else "L"
	var fl: Array = _b[side].fingers
	var fo: Array = _b[other].fingers
	for k in fl.size():
		var i: int = fl[k]
		var q: Quaternion = _base[i][1]
		var num: int = sk.get_bone_name(i).substr(7, 3).to_int()
		if mirrored and k < fo.size() and not (thumb_own and num >= 20):
			# Zeigefinger der Stützhand liegt nicht am Abzug: Krümmung des Mittelfingers übernehmen
			var ko: int = k + 4 if num >= 5 and num <= 7 else k
			var qo: Quaternion = _base[fo[ko]][1]
			q = Quaternion(qo.x, -qo.y, -qo.z, qo.w)
		var o: float = thumb_open if num >= 20 else open
		if o > 0.0:
			q = q.slerp(sk.get_bone_rest(i).basis.get_rotation_quaternion(), o)
		if num == 20 and thumb_rot != Vector3.ZERO:
			q = q * Quaternion.from_euler(thumb_rot * (PI / 180.0))
		sk.set_bone_pose_rotation(i, q)

## Zeigefinger der Griffhand aus der Abzugs-Krümmung lösen (0 = gebacken, 1 = Ruhe/gestreckt): am Rahmen entlang.
func set_trigger_finger(side: String, open: float) -> void:
	if not _ok:
		return
	for i: int in _b[side].fingers:
		var num: int = sk.get_bone_name(i).substr(7, 3).to_int()
		if num >= 5 and num <= 7:
			var q: Quaternion = _base[i][1]
			sk.set_bone_pose_rotation(i, q.slerp(sk.get_bone_rest(i).basis.get_rotation_quaternion(), open))

## Hände setzen: Ziele im Kameraraum (Transform der Handwurzel). w_*: 0 = Hand bleibt in gebackener Pose.
func solve(hand_r: Transform3D, hand_l: Transform3D) -> void:
	if not _ok:
		return
	_solve_side("R", hand_r)
	_solve_side("L", hand_l)

func _solve_side(s: String, target_cam: Transform3D) -> void:
	var d: Dictionary = _b[s]
	# Kette auf die gebackene Pose zurück
	for key in ["clav", "up", "fore", "ctrl", "hand"]:
		_reset(d[key])
	for t: int in d.tw:
		_reset(t)
	var tgt := Transform3D(_sk_rot_inv * target_cam.basis, _sk_inv * target_cam.origin)
	var a: float = _len[s][0]
	var b: float = _len[s][1]
	var sh: Vector3 = sk.get_bone_global_pose(d.up).origin
	var to_t: Vector3 = tgt.origin - sh
	var dist: float = to_t.length()
	var reach: float = (a + b) * 0.985
	if dist > reach:
		# Schulter nach vorn schieben (Schlüsselbein) statt die Hand von der Waffe zu lösen
		var shift: Vector3 = to_t.normalized() * (dist - reach)
		var par: int = sk.get_bone_parent(d.clav)
		var pb: Basis = sk.get_bone_global_pose(par).basis if par >= 0 else Basis()
		sk.set_bone_pose_position(d.clav, (_base[d.clav][0] as Vector3) + pb.inverse() * shift)
		sh = sk.get_bone_global_pose(d.up).origin
		to_t = tgt.origin - sh
		dist = to_t.length()
	dist = clampf(dist, absf(a - b) + 0.001, (a + b) * 0.9999)
	var dir: Vector3 = to_t.normalized()
	var pole: Vector3 = _sk_inv * (_pole_cam[s] as Vector3)
	var pv: Vector3 = (pole - sh) - dir * dir.dot(pole - sh)
	if pv.length() < 1e-5:
		pv = Vector3.DOWN
	pv = pv.normalized()
	var x: float = (a * a - b * b + dist * dist) / (2.0 * dist)
	var h: float = sqrt(maxf(a * a - x * x, 0.0))
	var elbow: Vector3 = sh + dir * x + pv * h
	# Oberarm: Ebene (Oberarm, Unterarm) der gebackenen Pose auf die neue Ebene drehen
	var g_up: Transform3D = sk.get_bone_global_pose(d.up)
	var g_fo: Transform3D = sk.get_bone_global_pose(d.fore)
	var u0: Vector3 = (g_fo.origin - g_up.origin).normalized()
	var f0: Vector3 = (sk.get_bone_global_pose(d.tw[2]).origin - g_fo.origin)
	f0 = (f0 if f0.length() > 1e-5 else g_fo.basis.y).normalized()
	var u1: Vector3 = (elbow - sh).normalized()
	var f1: Vector3 = (tgt.origin - elbow).normalized()
	var r: Basis = _frame(u1, f1) * _frame(u0, f0).inverse()
	_set_global_basis(d.up, r * g_up.basis)
	# Unterarm: Scharnier auf die Zielrichtung
	g_fo = sk.get_bone_global_pose(d.fore)
	var fcur: Vector3 = (sk.get_bone_global_pose(d.tw[2]).origin - g_fo.origin)
	fcur = (fcur if fcur.length() > 1e-5 else g_fo.basis.y).normalized()
	_set_global_basis(d.fore, Basis(_rot_between(fcur, f1)) * g_fo.basis)
	# Hand: IK-Controller so setzen, dass die Hand auf dem Ziel liegt
	var hand_local: Transform3D = Transform3D(Basis(_base[d.hand][1]), _base[d.hand][0])
	var ctrl_g: Transform3D = tgt * hand_local.affine_inverse()
	var cp: int = sk.get_bone_parent(d.ctrl)
	var pg: Transform3D = sk.get_bone_global_pose(cp) if cp >= 0 else Transform3D()
	var cl: Transform3D = pg.affine_inverse() * ctrl_g
	sk.set_bone_pose_position(d.ctrl, cl.origin)
	sk.set_bone_pose_rotation(d.ctrl, cl.basis.orthonormalized().get_rotation_quaternion())
	# Unterarm-Drehung (Pronation) auf die Twist-Knochen verteilen
	var cur_end: Basis = sk.get_bone_global_pose(d.tw[2]).basis.orthonormalized()
	var want_end: Basis = tgt.basis.orthonormalized() * (_twist_ref[s] as Basis).inverse()
	var dq: Quaternion = (cur_end.inverse() * want_end).get_rotation_quaternion()
	var ang: float = 2.0 * atan2(dq.y, dq.w)
	ang = wrapf(ang, -PI, PI)
	for t: int in d.tw:
		sk.set_bone_pose_rotation(t, (_base[t][1] as Quaternion) * Quaternion(Vector3.UP, ang / 3.0))

func _reset(i: int) -> void:
	sk.set_bone_pose_position(i, _base[i][0])
	sk.set_bone_pose_rotation(i, _base[i][1])

func _set_global_basis(i: int, g: Basis) -> void:
	var p: int = sk.get_bone_parent(i)
	var pb: Basis = sk.get_bone_global_pose(p).basis.orthonormalized() if p >= 0 else Basis()
	sk.set_bone_pose_rotation(i, (pb.inverse() * g.orthonormalized()).get_rotation_quaternion())

## Orthonormaler Rahmen aus Richtung a und Ebenenvektor b.
static func _frame(a: Vector3, b: Vector3) -> Basis:
	var n: Vector3 = a.cross(b)
	if n.length() < 1e-5:
		n = a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT)
	n = n.normalized()
	return Basis(a, n, a.cross(n).normalized())

static func _rot_between(a: Vector3, b: Vector3) -> Quaternion:
	var c: Vector3 = a.cross(b)
	var dt: float = a.dot(b)
	if c.length() < 1e-6:
		return Quaternion.IDENTITY
	return Quaternion(c.normalized(), atan2(c.length(), dt))
