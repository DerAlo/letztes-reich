# Blender 4.2 + MPFB2: Nachtzug-Reisende als SKINNED glTF mit Posen-Animationen (Idle: Atmen, Kopfbewegung).
# Texturen vorher: python prep_civ_nz.py <tex_dir> <kind>
# Aufruf (Blender 4.2 + MPFB 2.0.18 mit CC0-Asset-Packs, OHNE --factory-startup):
#   blender -b --python build_civ_nz.py -- <tex_dir> <out.glb> --kind=<kind> [--static=lie] [--preview=<png-praefix>]
# Ergebnis (Standard): GLB mit Skelett (MPFB "game_engine", 53 Knochen) + einem Mesh "Figure" und je einer
#   Schleifen-Animation pro Pose: seat (Haende im Schoss), seat_table (Unterarme auf dem Tisch), seat_lean (doest,
#   Arme verschraenkt), seat_cross (Beine uebereinander, Blick zum Fenster links), duck (sitzend zusammengekauert,
#   Haende im Nacken – Kampf), cower (kauert am Boden). Jede Pose 8 s: Atmen + langsame Blickwechsel.
#   Ursprung je Pose ueber die Root-Knochen-Verschiebung: Sitzposen = Becken x/y, z=0 an der Gesaess-Unterkante
#   (Sitzflaeche 0,46 m); cower = Becken x/y, z=0 tiefster Punkt. Blender: vorn = -Y, links = +X.
# --static=lie: stattdessen statisches Mesh "lie" (Rueckenlage, stehend modelliert; wie build_civ.py) fuer Schlafende.
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix, Quaternion

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT_GLB = argv[0], argv[1]
KIND = "tweed"
PREVIEW = ""
STATIC = ""
for a in argv[2:]:
    if a.startswith("--kind="):
        KIND = a[7:]
    elif a.startswith("--static="):
        STATIC = a[9:]
    elif a.startswith("--preview="):
        PREVIEW = a[10:]
BUDGET = 24000
DEBUG = "--debug" in argv

C = "clothes/"
BM = C + "toigo_ankle_boots_male/toigo_ankle_boots_male.mhclo"
BF = C + "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"
S1 = C + "shoes01/shoes01.mhclo"
CFG = {
    "tweed": {"gender": 1.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
              "macro": {"age": 0.62, "muscle": 0.45, "weight": 0.66, "height": 0.5, "proportions": 0.7},
              "face": {"head/head-square": 0.25, "nose/nose-hump-incr": 0.3, "chin/chin-width-incr": 0.2,
                       "head/head-age-incr": 0.3},
              "hair": "short02", "suit": C + "toigo_male_double-breasted_suit/toigo_male_double-breasted_suit.mhclo",
              "shoes": S1},
    "pulli": {"gender": 1.0, "race": {"caucasian": 0.93, "asian": 0.03, "african": 0.04},
              "macro": {"age": 0.4, "muscle": 0.5, "weight": 0.5, "height": 0.58, "proportions": 0.8},
              "face": {"head/head-oval": 0.3, "chin/chin-prominent-incr": 0.2, "nose/nose-scale-vert-incr": 0.15},
              "hair": "short03", "suit": C + "male_casualsuit02/male_casualsuit02.mhclo", "shoes": BM},
    "hemd": {"gender": 1.0, "race": {"caucasian": 0.1, "asian": 0.88, "african": 0.02},
             "macro": {"age": 0.27, "muscle": 0.5, "weight": 0.42, "height": 0.5, "proportions": 0.8},
             "face": {"head/head-oval": 0.2},
             "hair": "short04", "suit": C + "male_casualsuit03/male_casualsuit03.mhclo",
             "shoes": C + "shoes04/shoes04.mhclo"},
    "jacke": {"gender": 1.0, "race": {"caucasian": 0.05, "asian": 0.02, "african": 0.93},
              "macro": {"age": 0.45, "muscle": 0.6, "weight": 0.55, "height": 0.62, "proportions": 0.8},
              "face": {"head/head-square": 0.2, "chin/chin-width-incr": 0.15},
              "hair": "short01", "suit": C + "male_casualsuit05/male_casualsuit05.mhclo", "shoes": BM},
    "anzug": {"gender": 1.0, "race": {"caucasian": 0.94, "asian": 0.03, "african": 0.03},
              "macro": {"age": 0.5, "muscle": 0.5, "weight": 0.58, "height": 0.55, "proportions": 0.75},
              "face": {"head/head-rectangular": 0.3, "nose/nose-hump-incr": 0.15, "chin/chin-prominent-incr": 0.2},
              "hair": "short04", "suit": C + "male_elegantsuit01/male_elegantsuit01.mhclo", "shoes": S1},
    "blazer": {"gender": 0.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
               "macro": {"age": 0.5, "muscle": 0.45, "weight": 0.52, "height": 0.5, "proportions": 0.75, "cupsize": 0.5},
               "face": {"head/head-oval": 0.3, "nose/nose-scale-vert-incr": 0.1},
               "hair": "bob02", "suit": C + "toigo_female_suit_2/toigo_female_suit_2.mhclo", "shoes": BF},
    "bluse": {"gender": 0.0, "race": {"caucasian": 0.05, "asian": 0.05, "african": 0.9},
              "macro": {"age": 0.3, "muscle": 0.5, "weight": 0.45, "height": 0.55, "proportions": 0.8, "cupsize": 0.45},
              "face": {"head/head-oval": 0.2},
              "hair": "ponytail01", "suit": C + "female_elegantsuit01/female_elegantsuit01.mhclo", "shoes": BF},
    "dame": {"gender": 0.0, "race": {"caucasian": 0.96, "asian": 0.02, "african": 0.02},
             "macro": {"age": 0.82, "muscle": 0.4, "weight": 0.58, "height": 0.45, "proportions": 0.7, "cupsize": 0.5},
             "face": {"head/head-age-incr": 0.5, "head/head-round": 0.2},
             "hair": "bob01", "suit": C + "toigo_female_double-breasted_suit/toigo_female_double-breasted_suit.mhclo",
             "shoes": BF},
    "alt": {"gender": 1.0, "race": {"caucasian": 0.96, "asian": 0.02, "african": 0.02},
            "macro": {"age": 0.9, "muscle": 0.35, "weight": 0.55, "height": 0.45, "proportions": 0.65},
            "face": {"head/head-age-incr": 0.8, "nose/nose-scale-vert-incr": 0.25, "head/head-oval": 0.2},
            "hair": "short01", "suit": C + "toigo_male_suit_3/toigo_male_suit_3.mhclo", "shoes": S1},
    "kostuem": {"gender": 0.0, "race": {"caucasian": 0.08, "asian": 0.9, "african": 0.02},
                "macro": {"age": 0.55, "muscle": 0.45, "weight": 0.5, "height": 0.45, "proportions": 0.75, "cupsize": 0.45},
                "face": {"head/head-oval": 0.25},
                "hair": "long01", "suit": C + "toigo_female_suit/toigo_female_suit.mhclo", "shoes": BF},
    "schlaf_m": {"gender": 1.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
                 "macro": {"age": 0.35, "muscle": 0.5, "weight": 0.5, "height": 0.55, "proportions": 0.8},
                 "face": {"head/head-oval": 0.2},
                 "hair": "short02", "suit": C + "male_casualsuit06/male_casualsuit06.mhclo", "shoes": S1},
    "schlaf_f": {"gender": 0.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
                 "macro": {"age": 0.35, "muscle": 0.45, "weight": 0.48, "height": 0.5, "proportions": 0.8, "cupsize": 0.5},
                 "face": {"head/head-oval": 0.3},
                 "hair": "ponytail01", "suit": C + "female_casualsuit01/female_casualsuit01.mhclo", "shoes": BF},
}[KIND]
print("[civ] Figur:", KIND)

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
TG = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/user_default/mpfb/data/targets"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

macro = {"gender": CFG["gender"], "cupsize": 0.5, "firmness": 0.5, "race": CFG["race"]}
macro.update(CFG["macro"])
body = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
for t, w in CFG["face"].items():
    p = os.path.join(TG, t + ".target.gz")
    if os.path.isfile(p):
        TargetService.load_target(body, p, weight=w)
    else:
        print("[civ] Target fehlt:", t)

rig = HumanService.add_builtin_rig(body, "game_engine")

ASSETS = [
    ("eyes/low-poly/low-poly.mhclo", "Eyes", "eye"),
    ("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows", "brow"),
    ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "lash"),
    ("hair/%s/%s.mhclo" % (CFG["hair"], CFG["hair"]), "Hair", "hair"),
    (CFG["suit"], "Clothes", "suit"),
    (CFG["shoes"], "Clothes", "shoes"),
]
parts = {}
for rel, typ, key in ASSETS:
    parts[key] = HumanService.add_mhclo_asset(os.path.join(D, rel), body, asset_type=typ, subdiv_levels=0,
                                              material_type="MAKESKIN")

def activate(o):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)

meshes = [body] + list(parts.values())
for o in meshes:
    activate(o)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type in ("SUBSURF", "MASK"):
            o.modifiers.remove(m)

def delete_verts(o, pred):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    dl = bm.verts.layers.deform.active
    kill = [v for v in bm.verts if pred(v, dl)]
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(o.data)
    bm.free()

gi = {g.name: g.index for g in body.vertex_groups}
body_idx = gi.get("body")
del_idx = [i for n, i in gi.items() if n.startswith("Delete.")]
delete_verts(body, lambda v, dl: (body_idx not in v[dl]) or any(i in v[dl] and v[dl][i] > 0.5 for i in del_idx))
shoes = parts["shoes"]
stop = max((shoes.matrix_world @ v.co).z for v in shoes.data.vertices)
delete_verts(body, lambda v, dl: v.co.z < stop - 0.03)

# ---------------------------------------------------------------- Materialien
def make_mat(name, img, rough=0.6, alpha=False, normal=None, nstrength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, img))
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha:
        nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        m.blend_method = "CLIP"
    if normal and os.path.isfile(os.path.join(TEX, normal)):
        nt_ = nt.nodes.new("ShaderNodeTexImage")
        nt_.image = bpy.data.images.load(os.path.join(TEX, normal))
        nt_.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = nstrength
        nt.links.new(nt_.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m

MATS = {
    "skin": make_mat("skin", "skin.jpg", 0.55), "eye": make_mat("eye", "eye.jpg", 0.15),
    "brow": make_mat("brow", "brow.png", 0.8, True), "lash": make_mat("lash", "lash.png", 0.8, True),
    "hair": make_mat("hair", "hair.png", 0.7, True, "hair_n.png"),
    "suit": make_mat("suit", "suit.jpg", 0.9, False, "suit_n.png"),
    "shoes": make_mat("shoes", "shoes.jpg", 0.35, False, "shoes_n.png"),
}
def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
set_mat(body, MATS["skin"])
for k, o in parts.items():
    set_mat(o, MATS[k])

def ntri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
est = sum(ntri(o) for o in meshes)
def decimate(o, ratio):
    activate(o)
    dm = o.modifiers.new("Dec", "DECIMATE")
    dm.ratio = ratio
    while o.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")
if est > BUDGET:
    for key, cap in (("shoes", 1800), ("suit", 9000), ("hair", 5500)):
        if key in parts and ntri(parts[key]) > cap:
            decimate(parts[key], cap / ntri(parts[key]))
    est = sum(ntri(o) for o in meshes)
    if est > BUDGET:
        decimate(body, max(0.5, 1.0 - (est - BUDGET) / ntri(body)))
activate(body)
for o in meshes[1:]:
    o.select_set(True)
bpy.ops.object.join()
body = bpy.context.object
body.name = "Figure"
for p in body.data.polygons:
    p.use_smooth = True
print("[civ] Dreiecke gesamt", ntri(body))

# ---------------------------------------------------------------- Posen-Werkzeuge
activate(rig)
bpy.ops.object.mode_set(mode="POSE")
PB = rig.pose.bones
for pb in PB:
    pb.rotation_mode = "QUATERNION"

def upd():
    bpy.context.view_layer.update()

def rot_bone_world(pb, axis, ang):
    h = rig.matrix_world @ pb.head
    R = Matrix.Translation(h) @ Matrix.Rotation(ang, 4, axis) @ Matrix.Translation(-h)
    pb.matrix = rig.matrix_world.inverted() @ R @ rig.matrix_world @ pb.matrix
    upd()

def aim(bone, child, target):
    pb = PB[bone]
    cur = PB[child].head - pb.head
    q = cur.normalized().rotation_difference(Vector(target).normalized())
    axis, ang = q.to_axis_angle()
    rot_bone_world(pb, axis, ang)

def twist(bone, axis, deg):
    rot_bone_world(PB[bone], Vector(axis).normalized(), math.radians(deg))

def local_axis(bone, i):
    m = (rig.matrix_world.to_3x3() @ PB[bone].matrix.to_3x3())
    return Vector((m[0][i], m[1][i], m[2][i])).normalized()

def twist_local(bone, i, deg):
    """Drehung um die eigene Knochenachse i (0=x quer, 1=y laengs, 2=z)."""
    rot_bone_world(PB[bone], local_axis(bone, i), math.radians(deg))

def curl(side, amount):
    CURL = {"01": 30.0, "02": 42.0, "03": 28.0}
    for f in ("index", "middle", "ring", "pinky", "thumb"):
        for j in ("01", "02", "03"):
            pb = PB.get("%s_%s_%s" % (f, j, side))
            if pb is None:
                continue
            ang = CURL[j] * amount * (0.45 if f == "thumb" else 1.0)
            ax = (rig.matrix_world.to_3x3() @ pb.matrix.to_3x3() @ Vector((1, 0, 0))).normalized()
            rot_bone_world(pb, ax, math.radians(ang))

def reset_pose():
    for pb in PB:
        pb.matrix_basis = Matrix.Identity(4)
    upd()

def dirv(a, b):
    return (PB[b].head - PB[a].head).normalized()

reset_pose()
FOOT_REST = {s: dirv("foot_" + s, "ball_" + s) for s in ("l", "r")}

def arms_down():
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.13, 0.03, -1.0))
        aim("lowerarm_" + s, "hand_" + s, (sg * 0.04, -0.12, -1.0))
        curl(s, 0.5)

SEAT_TZ = [-0.12]
def seat_legs():
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.1, -1.0, SEAT_TZ[0]))
        aim("calf_" + s, "foot_" + s, (sg * 0.03, -0.06, -1.0))
        aim("foot_" + s, "ball_" + s, FOOT_REST[s])

def seat_spine(back=0.16, mid=0.08, top=-0.02, neck=-0.18):
    aim("spine_01", "spine_02", (0, back, 1))
    aim("spine_02", "spine_03", (0, mid, 1))
    aim("spine_03", "neck_01", (0, top, 1))
    aim("neck_01", "head", (0, neck, 1))

def pose_seat():
    seat_spine()
    seat_legs()
    # Haende locker im Schoss, leicht asymmetrisch (rechte Hand auf der linken)
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.16, -0.12, -1.0))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.32, -1.0, -0.42 if s == "l" else -0.32))
        curl(s, 0.55 if s == "l" else 0.35)

TFWD = 0.13   # am Tisch rutscht man auf der Bank nach vorn

def reach(bone, child, pt):
    """Knochen so drehen, dass er (vom eigenen Kopf aus) auf den Weltpunkt pt zeigt."""
    aim(bone, child, Vector(pt) - rig.matrix_world @ PB[bone].head)

def pose_seat_table():
    # vorgebeugt, Unterarme auf dem Tisch (Tischplatte 0,295 m ueber der Sitzflaeche, Kante 0,46 m vor dem Becken)
    seat_spine(back=-0.5, mid=-0.7, top=-0.68, neck=-0.45)
    seat_legs()
    o_ = anchor_quiet(True)
    if DEBUG:
        for b in ("pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"):
            print("[dbg]", b, tuple(round(x, 3) for x in rig.matrix_world @ PB[b].head))
    for s, sg in (("l", 1.0), ("r", -1.0)):
        reach("upperarm_" + s, "lowerarm_" + s, o_ + Vector((sg * 0.25, -0.5 + TFWD, 0.33)))
        reach("lowerarm_" + s, "hand_" + s, o_ + Vector((-sg * 0.02, (-0.74 if s == "l" else -0.7) + TFWD, 0.32)))
        curl(s, 0.45 if s == "l" else 0.7)

def pose_seat_lean():
    # doest: zurueckgelehnt, Arme vor der Brust verschraenkt, Kopf zur Seite gesunken
    seat_spine(back=0.26, mid=0.14, top=0.02, neck=-0.1)
    seat_legs()
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.2, -0.28, -1.0))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 1.0, -0.42, 0.3 if s == "l" else 0.38))
        curl(s, 0.6)
    twist_local("head", 2, 14.0)
    twist_local("neck_01", 2, 6.0)
    nod(14.0)

def pose_seat_cross():
    # Knoechel uebereinander, Fuesse etwas vor, rechte Hand im Schoss, linke liegt auf dem linken Oberschenkel
    # (14.11.: schwebte vorher waagerecht ueber dem Bein); Blick nach links (Fenster)
    seat_spine(back=0.2, mid=0.1, top=0.0, neck=-0.16)
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.06, -1.0, SEAT_TZ[0] - 0.05))
        aim("foot_" + s, "ball_" + s, FOOT_REST[s])
    aim("calf_l", "foot_l", (-0.32, -0.3, -1.0))
    aim("calf_r", "foot_r", (0.16, -0.3, -1.0))
    aim("foot_l", "ball_l", (-0.15, -1.0, -0.15))
    aim("foot_r", "ball_r", (0.1, -1.0, -0.3))
    aim("upperarm_l", "lowerarm_l", (0.12, -0.2, -1.0))
    aim("lowerarm_l", "hand_l", (-0.14, -1.0, -0.72))
    curl("l", 0.4)
    aim("upperarm_r", "lowerarm_r", (-0.06, -0.16, -1.0))
    aim("lowerarm_r", "hand_r", (0.42, -1.0, -0.62))
    curl("r", 0.55)
    twist_local("head", 1, 26.0)
    twist_local("neck_01", 1, 10.0)

def pose_duck():
    # Kampf: tief nach vorn zusammengekauert, Brust auf den Oberschenkeln, Haende schuetzen den Hinterkopf
    seat_legs()
    aim("spine_01", "spine_02", (0, -0.9, 0.42))
    aim("spine_02", "spine_03", (0, -1.0, 0.05))
    aim("spine_03", "neck_01", (0, -1.0, -0.28))
    aim("neck_01", "head", (0, -0.35, -0.94))
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.45, -0.85, -0.25))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.7, 0.25, 0.4))
        curl(s, 0.8)

def pose_cower():
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.2, -0.62, 0.78))
        aim("calf_" + s, "foot_" + s, (sg * 0.02, 0.38, -1.0))
        aim("foot_" + s, "ball_" + s, FOOT_REST[s])
    aim("spine_01", "spine_02", (0, -0.55, 1))
    aim("spine_02", "spine_03", (0, -0.75, 1))
    aim("spine_03", "neck_01", (0, -0.9, 1))
    aim("neck_01", "head", (0, -1.0, 0.45))
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.35, -0.75, 0.55))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.85, 0.15, 0.5))
        curl(s, 1.0)

def pose_lie():
    arms_down()
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.12, -0.62, -0.78))
        aim("calf_" + s, "foot_" + s, (sg * 0.02, 0.6, -0.8))
        aim("foot_" + s, "ball_" + s, (0, -0.45, -0.9))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.35, -0.6, -0.7))
    aim("neck_01", "head", (0, -0.25, 1))

def nod(deg):
    twist_local("neck_01", 0, deg * 0.35)
    twist_local("head", 0, deg * 0.65)

def breathe(b):
    # Einatmen: Brustkorb hebt sich (Wirbelsaeule streckt sich minimal), Schultern gehen leicht hoch
    twist_local("spine_02", 0, -1.1 * b)
    twist_local("spine_03", 0, -1.3 * b)
    for s, sg in (("l", 1.0), ("r", -1.0)):
        twist_local("clavicle_" + s, 2, sg * 1.4 * b)

def look(yaw, pitch):
    if abs(yaw) > 0.01:
        twist_local("neck_01", 1, yaw * 0.35)
        twist_local("head", 1, yaw * 0.65)
    if abs(pitch) > 0.01:
        nod(pitch)

def seat_drop():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    mw = body.matrix_world
    pel = rig.matrix_world @ ((PB["thigh_l"].head + PB["thigh_r"].head) * 0.5)
    vs = [mw @ v.co for v in me.vertices]
    zs = [v.z for v in vs if abs(v.y - pel.y) < 0.12 and abs(v.x - pel.x) < 0.2 and v.z < pel.z]
    d = min(zs) - min(v.z for v in vs)
    ev.to_mesh_clear()
    return d

def anchor_quiet(seated):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    mw = body.matrix_world
    vs = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    pel = rig.matrix_world @ ((PB["thigh_l"].head + PB["thigh_r"].head) * 0.5)
    zs = [v.z for v in vs if abs(v.y - pel.y) < 0.12 and abs(v.x - pel.x) < 0.2 and v.z < pel.z]
    return Vector((pel.x, pel.y, min(zs)))

def anchor(seated):
    """Weltpunkt, der im Ursprung liegen soll (aktuelle Pose)."""
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    mw = body.matrix_world
    vs = [mw @ v.co for v in me.vertices]
    ev.to_mesh_clear()
    pel = rig.matrix_world @ ((PB["thigh_l"].head + PB["thigh_r"].head) * 0.5)
    zmin = min(v.z for v in vs)
    if seated:
        zs = [v.z for v in vs if abs(v.y - pel.y) < 0.12 and abs(v.x - pel.x) < 0.2 and v.z < pel.z]
        o_ = Vector((pel.x, pel.y, min(zs)))
        print("[civ]   Sohle %.3f unter Gesaess, Kopf %.3f ueber Gesaess" % (o_.z - zmin, max(v.z for v in vs) - o_.z))
    else:
        o_ = Vector((pel.x, pel.y, zmin))
        print("[civ]   Kopf %.3f ueber Boden" % (max(v.z for v in vs) - zmin))
    return o_

def shift_root(off):
    pb = PB["Root"]
    T = Matrix.Translation(off)
    pb.matrix = rig.matrix_world.inverted() @ T @ rig.matrix_world @ pb.matrix
    upd()

# Sitz-Oberschenkelneigung so, dass die Fuesse bei 0,46 m Sitzhoehe den Boden erreichen
reset_pose()
pose_seat()
for _i in range(6):
    d = seat_drop()
    if d >= 0.445 or SEAT_TZ[0] < -0.6:
        break
    SEAT_TZ[0] -= min(0.25, (0.455 - d) * 1.6)
    reset_pose()
    pose_seat()
print("[civ] Oberschenkel-Neigung z=%.2f" % SEAT_TZ[0])

FPS = 24
LEN = 8   # Sekunden je Schleife
# Pro Sekunde ein Schluessel: (Atem 0..1, Blick-Gier, Blick-Nicken)
LOOK = {
    "seat": [(0, 0, 0), (0.5, 0, 0), (1, -8, 2), (0.5, -12, 3), (0, -10, 2), (0.5, 0, 0), (1, 6, -2), (0.5, 3, 0)],
    "seat_table": [(0, 0, 0), (0.5, 0, 4), (1, 0, 8), (0.5, 4, 6), (0, 10, 0), (0.5, 12, -2), (1, 4, 2), (0.5, 0, 2)],
    "seat_lean": [(0, 0, 0), (0.4, 0, 0.5), (0.8, 0, 1), (0.6, 0, 1), (0.2, 0, 0.5), (0, 0, 0), (0.4, -2, 0), (0.6, -1, 0)],
    "seat_cross": [(0, 0, 0), (0.5, 0, 0), (1, 6, 2), (0.5, 8, 3), (0, 8, 2), (0.5, -10, 0), (1, -14, -2), (0.5, -6, 0)],
    "duck": [(0, 0, 0), (1, 0, 0), (0, 2, 0), (1, 0, 0), (0, -2, 0), (1, 0, 0), (0, 0, 0), (1, 0, 0)],
    "cower": [(0, 0, 0), (1, 3, 0), (0, 6, -4), (1, 3, 0), (0, 0, 0), (1, -4, 0), (0, -6, -4), (1, -2, 0)],
}
POSES = [("seat", pose_seat, True), ("seat_table", pose_seat_table, True), ("seat_lean", pose_seat_lean, True),
         ("seat_cross", pose_seat_cross, True), ("duck", pose_duck, True), ("cower", pose_cower, False)]

def key_all(frame, prev):
    for pb in PB:
        q = pb.rotation_quaternion.copy()
        if pb.name in prev and prev[pb.name].dot(q) < 0.0:
            q.negate()
            pb.rotation_quaternion = q
        prev[pb.name] = q.copy()
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if pb.name == "Root":
            pb.keyframe_insert("location", frame=frame)

def build_action(name, fn, seated):
    reset_pose()
    fn()
    off = -anchor(seated)
    if name == "seat_table":
        off.y -= TFWD
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = act
    prev = {}
    keys = LOOK[name]
    for i in range(LEN + 1):
        b, yaw, pitch = keys[i % LEN]
        reset_pose()
        fn()
        breathe(b)
        look(yaw, pitch)
        shift_root(off)
        key_all(1 + i * FPS, prev)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = "AUTO_CLAMPED"
            kp.handle_right_type = "AUTO_CLAMPED"
    rig.animation_data.action = None
    print("[civ] Aktion", name, "fertig")
    return act

def preview_pose(name, fn, seated):
    # Workbench-Vorschau einer Pose mit Tisch-/Bank-Andeutung
    reset_pose()
    fn()
    off = -anchor(seated)
    if name == "seat_table":
        off.y -= TFWD
    shift_root(off)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.view_settings.view_transform = "Standard"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 360
    sc.render.resolution_y = 420
    props = []
    if seated:
        bpy.ops.object.mode_set(mode="OBJECT")
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.02, -0.23))
        bench = bpy.context.object; bench.scale = (0.9, 0.5, 0.46); props.append(bench)
        if name in ("seat_table", "duck"):
            bpy.ops.mesh.primitive_cube_add(size=1, location=(0, -0.51 - 0.44, 0.28))
            t = bpy.context.object; t.scale = (0.78, 0.88, 0.04); props.append(t)
        activate(rig)
        bpy.ops.object.mode_set(mode="POSE")
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 45
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for view, loc in (("front", Vector((1.3, -2.6, 1.0))), ("side", Vector((2.8, -0.2, 0.6)))):
        tgt = Vector((0, -0.15, 0.35 if seated else 0.4))
        cam.location = loc
        cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = "%s_%s_%s.png" % (PREVIEW, name, view)
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    for p in props:
        bpy.data.objects.remove(p, do_unlink=True)
    activate(rig)
    bpy.ops.object.mode_set(mode="POSE")

if STATIC:
    # Schlafende: statisches Mesh wie build_civ.py (Rueckenlage, stehend modelliert)
    reset_pose()
    pose_lie()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=dg)
    o = bpy.data.objects.new("lie", me)
    bpy.context.scene.collection.objects.link(o)
    me.transform(body.matrix_world)
    pel = rig.matrix_world @ ((PB["thigh_l"].head + PB["thigh_r"].head) * 0.5)
    vs = [v.co.copy() for v in me.vertices]
    o_ = Vector((pel.x, max(v.y for v in vs), pel.z))
    me.transform(Matrix.Translation(-o_))
    for p in me.polygons:
        p.use_smooth = True
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.data.objects.remove(body, do_unlink=True)
    bpy.data.objects.remove(rig, do_unlink=True)
    for x in list(bpy.data.objects):
        if x is not o:
            bpy.data.objects.remove(x, do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                              export_skins=False, export_animations=False, export_morph=False, export_yup=True,
                              export_image_format="AUTO", export_texcoords=True, export_normals=True,
                              export_tangents=True, export_attributes=False)
    print("[civ] exportiert (statisch)", OUT_GLB)
    sys.exit(0)

if PREVIEW:
    for name, fn, seated in POSES:
        preview_pose(name, fn, seated)

for name, fn, seated in POSES:
    build_action(name, fn, seated)
reset_pose()
bpy.ops.object.mode_set(mode="OBJECT")
for x in list(bpy.data.objects):
    if x not in (body, rig):
        bpy.data.objects.remove(x, do_unlink=True)
bpy.context.scene.frame_start = 1
bpy.context.scene.frame_end = 1 + LEN * FPS
bpy.context.scene.render.fps = FPS
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                          export_skins=True, export_animations=True, export_animation_mode="ACTIONS",
                          export_force_sampling=True, export_frame_step=3, export_anim_slide_to_zero=True, export_optimize_animation_size=True,
                          export_morph=False, export_yup=True, export_image_format="AUTO", export_texcoords=True,
                          export_normals=True, export_tangents=True, export_attributes=False, export_def_bones=False)
print("[civ] exportiert", OUT_GLB)
