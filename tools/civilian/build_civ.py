# Blender 4.2 + MPFB2: Zivil-Reisende (Nachtzug) aus MakeHuman-CC0-Assets, in festen Posen gebacken.
# Vorlage: tools/vip/build_vip.py. Aufruf (Blender 4.2 + MPFB 2.0.18 mit CC0-Asset-Packs, OHNE --factory-startup):
#   python prep_civ.py <tex_dir> <kind>
#   blender -b --python build_civ.py -- <tex_dir> <out.glb> --kind=mantel|jacke|alt|frau|frau2|voss|kaempfer|praesidentin|abgeordneter
#           [--poses=seat,cower,lie] [--preview=<png-praefix>]
# --poses waehlt die gebackenen Posen (Standard: seat,cower,lie fuer den Nachtzug). Weitere Posen:
#   "stand" (steht locker, Arme haengend; Ursprung Becken x/y, z=0 an den Sohlen),
#   "bound_seat" (Geisel sitzend, Haende hinter dem Ruecken/der Lehne; Ursprung wie seat),
#   "kneel" (Geisel kniend, Haende auf dem Ruecken, Kopf gesenkt; Ursprung Becken x/y, z=0 tiefster Punkt).
# Ergebnis: GLB ohne Skelett mit drei statischen Mesh-Objekten "seat" (sitzt auf Bank, Sohlen bei z=0),
# "cower" (kauert auf dem Boden, Arme ueber dem Kopf) und "lie" (Rueckenlage mit angezogenen Knien,
# stehend modelliert; im Spiel hingelegt). Posen ueber Knochenrotation (MPFB-"game_engine"-Rig), eingefroren.
# Ursprung: seat = Becken-Mitte x/y, z=0 an der Gesaess-Unterkante; cower = Becken x/y, z=0 tiefster Punkt;
# lie = Becken x/z, y=0 an der Rueckseite (hinterster Punkt). Blender: vorn = -Y, links = +X.
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT_GLB = argv[0], argv[1]
KIND = "mantel"
PREVIEW = ""
POSES = ["seat", "cower", "lie"]
for a in argv[2:]:
    if a.startswith("--kind="):
        KIND = a[7:]
    elif a.startswith("--poses="):
        POSES = [x for x in a[8:].split(",") if x]
    elif a.startswith("--preview="):
        PREVIEW = a[10:]
BUDGET = 22000   # Dreiecke je Pose (Godot erzeugt beim Import zusaetzlich LODs)

C = "clothes/"
CFG = {
    "mantel": {"gender": 1.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
               "macro": {"age": 0.55, "muscle": 0.5, "weight": 0.62, "height": 0.52, "proportions": 0.7},
               "face": {"head/head-square": 0.2, "nose/nose-hump-incr": 0.2, "chin/chin-width-incr": 0.2},
               "hair": "short02", "suit": C + "toigo_male_double-breasted_suit/toigo_male_double-breasted_suit.mhclo",
               "shoes": C + "shoes01/shoes01.mhclo"},
    "jacke": {"gender": 1.0, "race": {"caucasian": 0.92, "asian": 0.04, "african": 0.04},
              "macro": {"age": 0.3, "muscle": 0.55, "weight": 0.45, "height": 0.6, "proportions": 0.8},
              "face": {"head/head-oval": 0.3, "chin/chin-prominent-incr": 0.15},
              "hair": "short03", "suit": C + "male_casualsuit05/male_casualsuit05.mhclo",
              "shoes": C + "toigo_ankle_boots_male/toigo_ankle_boots_male.mhclo"},
    "alt": {"gender": 1.0, "race": {"caucasian": 0.96, "asian": 0.02, "african": 0.02},
            "macro": {"age": 0.88, "muscle": 0.35, "weight": 0.55, "height": 0.45, "proportions": 0.65},
            "face": {"head/head-age-incr": 0.7, "nose/nose-scale-vert-incr": 0.2, "head/head-oval": 0.2},
            "hair": "short01", "suit": C + "toigo_male_suit_3/toigo_male_suit_3.mhclo",
            "shoes": C + "shoes01/shoes01.mhclo"},
    "frau": {"gender": 0.0, "race": {"caucasian": 0.95, "asian": 0.03, "african": 0.02},
             "macro": {"age": 0.5, "muscle": 0.45, "weight": 0.5, "height": 0.48, "proportions": 0.75, "cupsize": 0.5},
             "face": {"head/head-oval": 0.3},
             "hair": "bob01", "suit": C + "toigo_female_suit/toigo_female_suit.mhclo",
             "shoes": C + "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"},
    "frau2": {"gender": 0.0, "race": {"caucasian": 0.05, "asian": 0.05, "african": 0.9},
              "macro": {"age": 0.3, "muscle": 0.5, "weight": 0.45, "height": 0.55, "proportions": 0.8, "cupsize": 0.45},
              "face": {"head/head-oval": 0.2},
              "hair": "ponytail01", "suit": C + "female_elegantsuit01/female_elegantsuit01.mhclo",
              "shoes": C + "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"},
    "voss": {"gender": 1.0, "race": {"caucasian": 0.95, "asian": 0.02, "african": 0.03},
             "macro": {"age": 0.72, "muscle": 0.55, "weight": 0.52, "height": 0.58, "proportions": 0.75},
             "face": {"head/head-age-incr": 0.4, "head/head-rectangular": 0.3, "nose/nose-hump-incr": 0.35,
                      "chin/chin-prominent-incr": 0.2, "eyebrows/eyebrows-trans-down": 0.3,
                      "cheek/l-cheek-bones-incr": 0.25, "cheek/r-cheek-bones-incr": 0.25},
             "hair": "short04", "suit": C + "toigo_male_double-breasted_suit/toigo_male_double-breasted_suit.mhclo",
             "shoes": C + "toigo_ankle_boots_male/toigo_ankle_boots_male.mhclo"},
    "kaempfer": {"gender": 1.0, "race": {"caucasian": 0.9, "asian": 0.04, "african": 0.06},
                 "macro": {"age": 0.42, "muscle": 0.62, "weight": 0.5, "height": 0.55, "proportions": 0.8},
                 "face": {"head/head-square": 0.3, "chin/chin-width-incr": 0.2, "nose/nose-hump-incr": 0.15},
                 "hair": "short02", "suit": C + "male_casualsuit01/male_casualsuit01.mhclo",
                 "shoes": C + "toigo_ankle_boots_male/toigo_ankle_boots_male.mhclo"},
    "praesidentin": {"gender": 0.0, "race": {"caucasian": 0.96, "asian": 0.02, "african": 0.02},
                     "macro": {"age": 0.78, "muscle": 0.45, "weight": 0.5, "height": 0.52, "proportions": 0.75,
                               "cupsize": 0.45},
                     "face": {"head/head-age-incr": 0.35, "head/head-oval": 0.3, "chin/chin-prominent-incr": 0.15,
                              "nose/nose-scale-vert-incr": 0.1},
                     "hair": "ponytail01",   # bob01-Pony verdeckte das Gesicht
                     "suit": C + "toigo_female_double-breasted_suit/toigo_female_double-breasted_suit.mhclo",
                     "shoes": C + "toigo_ankle_boots_female/toigo_ankle_boots_female.mhclo"},
    "abgeordneter": {"gender": 1.0, "race": {"caucasian": 0.94, "asian": 0.03, "african": 0.03},
                     "macro": {"age": 0.66, "muscle": 0.45, "weight": 0.66, "height": 0.5, "proportions": 0.7},
                     "face": {"head/head-round": 0.3, "chin/chin-width-incr": 0.15, "head/head-age-incr": 0.2},
                     "hair": "short01",
                     "suit": C + "toigo_male_suit_tie_and_jacket/toigo_male_suit_tie_and_jacket.mhclo",
                     "shoes": C + "shoes01/shoes01.mhclo"},
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
# Fuesse in den Schuhen weg (unterhalb der Schuhoberkante)
shoes = parts["shoes"]
stop = max((shoes.matrix_world @ v.co).z for v in shoes.data.vertices)
print("[civ] Schuhoberkante:", stop)
delete_verts(body, lambda v, dl: v.co.z < stop - 0.03)

# ---------------------------------------------------------------- Materialien
def make_mat(name, img, rough=0.6, alpha=False):
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
    return m

MATS = {
    "skin": make_mat("skin", "skin.jpg", 0.55), "eye": make_mat("eye", "eye.jpg", 0.15),
    "brow": make_mat("brow", "brow.png", 0.8, True), "lash": make_mat("lash", "lash.png", 0.8, True),
    "hair": make_mat("hair", "hair.png", 0.7, True), "suit": make_mat("suit", "suit.jpg", 0.9),
    "shoes": make_mat("shoes", "shoes.jpg", 0.35),
}
def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
set_mat(body, MATS["skin"])
for k, o in parts.items():
    set_mat(o, MATS[k])

# ---------------------------------------------------------------- zusammenfuegen + Budget
def ntri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
for o in meshes:
    print("[civ] tris", o.name, ntri(o))
est = sum(ntri(o) for o in meshes)
def decimate(o, ratio):
    activate(o)
    dm = o.modifiers.new("Dec", "DECIMATE")
    dm.ratio = ratio
    while o.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")
if est > BUDGET:
    # Schuhe/Anzug/Koerper (unter der Kleidung schon ausgeduennt) moderat reduzieren, Kopfdetails bleiben
    for key, cap in (("shoes", 1800), ("suit", 8000), ("hair", 5000)):
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
print("[civ] Dreiecke gesamt", ntri(body))

# ---------------------------------------------------------------- Posen
activate(rig)
bpy.ops.object.mode_set(mode="POSE")
PB = rig.pose.bones
print("[civ] Knochen:", [b.name for b in PB if "_0" not in b.name or b.name.startswith("spine") or b.name.startswith("neck")][:40])

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
def pose_seat():
    aim("spine_01", "spine_02", (0, 0.16, 1))
    aim("spine_02", "spine_03", (0, 0.08, 1))
    aim("spine_03", "neck_01", (0, -0.02, 1))
    aim("neck_01", "head", (0, -0.18, 1))
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.1, -1.0, SEAT_TZ[0]))
        aim("calf_" + s, "foot_" + s, (sg * 0.03, -0.06, -1.0))
        aim("foot_" + s, "ball_" + s, FOOT_REST[s])
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.16, -0.12, -1.0))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.32, -1.0, -0.42))
        curl(s, 0.6)

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
    # Rueckenlage mit angezogenen Knien (passt aufs 1,5-m-Bett); "vorn" (-Y) wird im Spiel "oben"
    arms_down()
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.12, -0.62, -0.78))
        aim("calf_" + s, "foot_" + s, (sg * 0.02, 0.6, -0.8))
        aim("foot_" + s, "ball_" + s, (0, -0.45, -0.9))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.35, -0.6, -0.7))
    aim("neck_01", "head", (0, -0.25, 1))

def nod(deg):
    # Kopf nicken (positiv = Blick nach unten): Kopf- und Halsknochen um die Querachse drehen
    twist("neck_01", (1, 0, 0), deg * 0.35)
    twist("head", (1, 0, 0), deg * 0.65)

def arms_bound():
    # Haende hinter dem Ruecken (gefesselt): Oberarme nach hinten unten, Unterarme zur Mitte
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("upperarm_" + s, "lowerarm_" + s, (sg * 0.18, 0.42, -1.0))
        aim("lowerarm_" + s, "hand_" + s, (-sg * 0.85, 0.32, -0.3))
        curl(s, 0.7)

def pose_stand():
    # locker stehend: Gewicht leicht auf dem rechten Bein, Arme haengend, Blick leicht gesenkt
    arms_down()
    aim("thigh_l", "calf_l", (0.06, -0.06, -1.0))
    aim("calf_l", "foot_l", (0.02, 0.0, -1.0))
    aim("thigh_r", "calf_r", (-0.02, 0.0, -1.0))
    aim("foot_l", "ball_l", FOOT_REST["l"])
    aim("foot_r", "ball_r", FOOT_REST["r"])
    nod(6.0)
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("lowerarm_" + s, "hand_" + s, (sg * 0.02, -0.2, -1.0))

def pose_bound_seat():
    pose_seat()
    arms_bound()
    nod(22.0)

def pose_kneel():
    # kniend: Oberschenkel senkrecht, Unterschenkel flach nach hinten, Fussruecken am Boden
    for s, sg in (("l", 1.0), ("r", -1.0)):
        aim("thigh_" + s, "calf_" + s, (sg * 0.07, -0.08, -1.0))
        aim("calf_" + s, "foot_" + s, (sg * 0.02, 1.0, -0.08))
        aim("foot_" + s, "ball_" + s, (0, 1.0, -0.12))
    aim("spine_02", "spine_03", (0, -0.06, 1))
    aim("spine_03", "neck_01", (0, -0.15, 1))
    arms_bound()
    nod(24.0)

def seat_drop():
    # Abstand Sohle -> Gesaess-Unterkante der aktuellen Pose (Weltkoordinaten)
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

def bake(name, fn):
    reset_pose()
    fn()
    if name in ("seat", "bound_seat"):
        # Oberschenkel so weit neigen, dass die Fuesse bei 0,46 m Sitzhoehe den Boden erreichen
        for _i in range(6):
            d = seat_drop()
            if d >= 0.445 or SEAT_TZ[0] < -0.6:
                break
            SEAT_TZ[0] -= min(0.25, (0.455 - d) * 1.6)
            reset_pose()
            fn()
        print("[civ] %s: Oberschenkel-Neigung z=%.2f" % (name, SEAT_TZ[0]))
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=False, depsgraph=dg)
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.matrix_world = body.matrix_world.copy()
    pel = rig.matrix_world @ ((PB["thigh_l"].head + PB["thigh_r"].head) * 0.5)
    me.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    vs = [v.co.copy() for v in me.vertices]
    zmin = min(v.z for v in vs)
    if name in ("seat", "bound_seat"):
        # Gesaess-Unterkante: tiefster Punkt im Bereich hinter den Knien unter dem Becken
        zs = [v.z for v in vs if abs(v.y - pel.y) < 0.12 and abs(v.x - pel.x) < 0.2 and v.z < pel.z]
        o_ = Vector((pel.x, pel.y, min(zs)))
        print("[civ] %s: Sohle %.3f unter Gesaess, Huefte %.3f ueber Gesaess, Kopf %.3f, Rueckseite y %.3f" % (
            name, o_.z - zmin, pel.z - o_.z, max(v.z for v in vs) - o_.z, max(v.y for v in vs) - pel.y))
    elif name == "lie":
        o_ = Vector((pel.x, max(v.y for v in vs), pel.z))
        print("[civ] lie: Kopf %.3f, Fuesse %.3f (entlang z ab Becken), Ruecken->Becken %.3f" % (
            max(v.z for v in vs) - pel.z, zmin - pel.z, o_.y - pel.y))
    else:
        o_ = Vector((pel.x, pel.y, zmin))
        print("[civ] %s: Huefte %.3f, Kopf %.3f" % (name, pel.z - zmin, max(v.z for v in vs) - zmin))
    me.transform(Matrix.Translation(-o_))
    for p in me.polygons:
        p.use_smooth = True
    return o

POSE_FN = {"seat": pose_seat, "cower": pose_cower, "lie": pose_lie, "stand": pose_stand,
           "bound_seat": pose_bound_seat, "kneel": pose_kneel}
baked = [bake(p, POSE_FN[p]) for p in POSES]
reset_pose()
bpy.ops.object.mode_set(mode="OBJECT")
bpy.data.objects.remove(body, do_unlink=True)
bpy.data.objects.remove(rig, do_unlink=True)
for o in list(bpy.data.objects):
    if o not in baked:
        bpy.data.objects.remove(o, do_unlink=True)

if PREVIEW:
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.view_settings.view_transform = "Standard"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x = 360
    sc.render.resolution_y = 480
    cam_d = bpy.data.cameras.new("cam")
    cam_d.lens = 50
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for o in baked:
        for x in baked:
            x.hide_render = x is not o
        for view, loc in (("front", Vector((1.6, -3.2, 1.2))), ("side", Vector((3.4, 0.0, 1.0)))):
            tgt = Vector((0, -0.1, 0.9 if o.name == "stand" else 0.45))
            if o.name == "lie":
                loc = Vector((loc.x, loc.y, 1.0))
                tgt = Vector((0, -0.2, 0.0))
            cam.location = loc
            cam.rotation_euler = (tgt - loc).to_track_quat("-Z", "Y").to_euler()
            sc.render.filepath = "%s_%s_%s.png" % (PREVIEW, o.name, view)
            bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    for o in baked:
        o.hide_render = False

bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                          export_skins=False, export_animations=False, export_morph=False, export_yup=True,
                          export_image_format="AUTO", export_texcoords=True, export_normals=True,
                          export_tangents=False, export_attributes=False)
print("[civ] exportiert", OUT_GLB)
