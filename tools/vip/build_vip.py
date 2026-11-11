# Blender 4.2 + MPFB2: General von Riedhammer aus MakeHuman-CC0-Assets bauen und als GLB exportieren.
# Aufruf (Blender 4.2 + MPFB 2.0.18 mit CC0-Asset-Packs, OHNE --factory-startup):
#   python prep_tex.py <tex_dir>  ;  blender -b --python build_ried.py -- <tex_dir> <out.glb> [out.blend]
# Pfade D/TG unten auf die lokale MPFB-Installation anpassen.
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT_GLB = argv[0], argv[1]
KIND = "riedhammer"
OUT_BLEND = ""
for a in argv[2:]:
    if a.startswith("--kind="):
        KIND = a[7:]
    else:
        OUT_BLEND = a

# Figuren-Steckbriefe (alle Assets MakeHuman-System-Assets, CC0; eigene Geometrie fuer Muetzen/Abzeichen)
BOOTS_TALL = "clothes/culturalibre_hero_boots_2/culturalibre_hero_boots_2.mhclo"
ELEGANT = "clothes/male_elegantsuit01/male_elegantsuit01.mhclo"
CASUAL5 = "clothes/male_casualsuit05/male_casualsuit05.mhclo"
_WEBER_BODY = {"macro": {"age": 0.74, "muscle": 0.42, "weight": 0.52, "height": 0.5, "proportions": 0.7},
               "face": {"head/head-oval": 0.3, "head/head-age-incr": 0.35, "nose/nose-hump-incr": 0.15,
                        "chin/chin-prominent-decr": 0.15, "eyebrows/eyebrows-trans-down": 0.15}}
CFG = {
    "riedhammer": {
        "macro": {"age": 0.8, "muscle": 0.62, "weight": 0.56, "height": 0.56, "proportions": 0.8},
        "face": {"head/head-square": 0.35, "chin/chin-prominent-incr": 0.35, "chin/chin-width-incr": 0.2,
                 "cheek/l-cheek-bones-incr": 0.3, "cheek/r-cheek-bones-incr": 0.3,
                 "eyebrows/eyebrows-trans-down": 0.25, "nose/nose-hump-incr": 0.3,
                 "neck/neck-scale-horiz-incr": 0.25, "head/head-age-incr": 0.6},
        "hair": "short02", "suit": ELEGANT, "boots": BOOTS_TALL, "tuck": True,
        "cap": "peaked", "tabs": True, "boards": "gold", "ribbons": True, "belt": True,
        "armband": False, "glasses": False, "collar": True},
    "weber": dict(_WEBER_BODY, **{
        "hair": "short01", "suit": "clothes/toigo_male_suit_tie_and_jacket/toigo_male_suit_tie_and_jacket.mhclo",
        "boots": "clothes/toigo_ankle_boots_male/toigo_ankle_boots_male.mhclo", "tuck": False,
        "cap": None, "tabs": False, "boards": None, "ribbons": False, "belt": False,
        "armband": False, "glasses": True, "collar": False}),
    "weber_uniform": dict(_WEBER_BODY, **{
        "hair": "short01", "suit": ELEGANT, "boots": BOOTS_TALL, "tuck": True,
        "cap": "peaked", "tabs": False, "boards": "silver", "ribbons": False, "belt": True,
        "armband": True, "glasses": True, "collar": True}),
    "falk": {
        "macro": {"age": 0.64, "muscle": 0.8, "weight": 0.6, "height": 0.62, "proportions": 0.8},
        "face": {"head/head-square": 0.5, "chin/chin-width-incr": 0.35, "neck/neck-scale-horiz-incr": 0.4,
                 "eyebrows/eyebrows-trans-down": 0.35, "cheek/l-cheek-bones-incr": 0.2,
                 "cheek/r-cheek-bones-incr": 0.2},
        "hair": "short02", "buzz": True, "suit": CASUAL5, "boots": BOOTS_TALL, "tuck": True,
        "cap": "beret", "tabs": False, "boards": None, "ribbons": False, "belt": True,
        "armband": True, "glasses": False, "collar": False},
    "graumantel": {
        "macro": {"age": 0.6, "muscle": 0.6, "weight": 0.55, "height": 0.55, "proportions": 0.75},
        "face": {"head/head-rectangular": 0.3, "chin/chin-prominent-incr": 0.2},
        "hair": "short02", "suit": CASUAL5, "boots": BOOTS_TALL, "tuck": True,
        "cap": "field", "tabs": False, "boards": None, "ribbons": False, "belt": True,
        "armband": True, "glasses": False, "collar": False},
}[KIND]
print("[vip] Figur:", KIND)

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
TG = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/user_default/mpfb/data/targets"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

macro = {"gender": 1.0, "cupsize": 0.5, "firmness": 0.5,
         "race": {"asian": 0.03, "caucasian": 0.94, "african": 0.03}}
macro.update(CFG["macro"])
body = HumanService.create_human(macro_detail_dict=macro, scale=0.1)

FACE = CFG["face"]
for t, w in FACE.items():
    p = os.path.join(TG, t + ".target.gz")
    if os.path.isfile(p):
        TargetService.load_target(body, p, weight=w)
    else:
        print("[vip] Target fehlt:", t)

rig = HumanService.add_builtin_rig(body, "game_engine")

ASSETS = [
    ("eyes/low-poly/low-poly.mhclo", "Eyes", "eye"),
    ("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows", "brow"),
    ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "lash"),
    ("hair/%s/%s.mhclo" % (CFG["hair"], CFG["hair"]), "Hair", "hair"),
    (CFG["suit"], "Clothes", "suit"),
    (CFG["boots"], "Clothes", "boots"),
]
parts = {}
for rel, typ, key in ASSETS:
    o = HumanService.add_mhclo_asset(os.path.join(D, rel), body, asset_type=typ, subdiv_levels=0,
                                     material_type="MAKESKIN")
    parts[key] = o

def activate(o):
    bpy.ops.object.mode_set(mode="OBJECT") if bpy.context.object and bpy.context.object.mode != "OBJECT" else None
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)

meshes = [body] + list(parts.values())
# Shape-Keys einbacken, Unterteilung/Masken entfernen
for o in meshes:
    activate(o)
    if o.data.shape_keys:
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)
    for m in list(o.modifiers):
        if m.type in ("SUBSURF", "MASK"):
            o.modifiers.remove(m)

# Basismesh: Helfer und verdeckte Koerperteile loeschen
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

# Hosenbeine im Stiefel entfernen
boots = parts["boots"]
btop = max((boots.matrix_world @ v.co).z for v in boots.data.vertices)
print("[vip] Stiefelschaft oben:", btop)
suit = parts["suit"]
if CFG["tuck"]:
    delete_verts(suit, lambda v, dl: v.co.z < btop - 0.05)
# Hosenbeine zum Stiefelschaft hin einziehen (in die Stiefel gesteckt statt Anzughose)
for s_ in ((1, -1) if CFG["tuck"] else ()):
    top = [boots.matrix_world @ v.co for v in boots.data.vertices
           if (boots.matrix_world @ v.co).z > btop - 0.03 and v.co.x * s_ > 0]
    if not top:
        continue
    bc = sum(top, Vector()) / len(top)
    rb = sum(((p - bc).xy.length for p in top), 0.0) / len(top)
    print("[vip] Schaft", s_, tuple(round(c, 3) for c in bc), "r", round(rb, 3))
    H = 0.22
    for v in suit.data.vertices:
        if v.co.x * s_ <= 0 or v.co.z > btop + H:
            continue
        w = min(1.0, max(0.0, (btop + H - v.co.z) / H))
        w = w * w * (3 - 2 * w)
        d = Vector((v.co.x - bc.x, v.co.y - bc.y))
        lim = rb + 0.006 + 0.03 * max(0.0, v.co.z - btop) / H
        if d.length > lim:
            nd = d.normalized() * (d.length + (lim - d.length) * w)
            v.co.x = bc.x + nd.x; v.co.y = bc.y + nd.y
# Koerper unter den Stiefeln weg
delete_verts(body, lambda v, dl: v.co.z < btop - 0.04 and abs(v.co.x) > 0.0)

# Materialien
def make_mat(name, img, rough=0.6, metal=0.0, alpha=False, color=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if img:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(TEX, img))
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha:
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            m.blend_method = "CLIP"
    elif color:
        bsdf.inputs["Base Color"].default_value = color
    return m

MATS = {
    "skin": make_mat("skin", "skin.jpg", 0.55), "eye": make_mat("eye", "eye.jpg", 0.15),
    "brow": make_mat("brow", "brow.png", 0.8, alpha=True), "lash": make_mat("lash", "lash.png", 0.8, alpha=True),
    "hair": make_mat("hair", "hair.png", 0.7, alpha=True), "suit": make_mat("suit", "suit.jpg", 0.85),
    "boots": make_mat("boots", "boots.jpg", 0.3),
}
def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
set_mat(body, MATS["skin"])
for k, o in parts.items():
    set_mat(o, MATS[k])

# ---------------------------------------------------------------- Ruhepose: Arme haengen
activate(rig)
bpy.ops.object.mode_set(mode="POSE")
def rot_bone_world(pb, axis, ang):
    h = rig.matrix_world @ pb.head
    R = Matrix.Translation(h) @ Matrix.Rotation(ang, 4, axis) @ Matrix.Translation(-h)
    pb.matrix = rig.matrix_world.inverted() @ R @ rig.matrix_world @ pb.matrix
    bpy.context.view_layer.update()

FINGER_SIGN = float(os.environ.get("VIP_FINGER_SIGN", "1"))

def aim(pb, child, target):
    cur = rig.pose.bones[child].head - pb.head
    q = cur.normalized().rotation_difference(target.normalized())
    axis, ang = q.to_axis_angle()
    rot_bone_world(pb, axis, ang)

for side, s in (("l", 1.0), ("r", -1.0)):
    ua = rig.pose.bones["upperarm_" + side]
    la = rig.pose.bones["lowerarm_" + side]
    hd = rig.pose.bones["hand_" + side]
    print("[vip] vorher", side, ua.head, la.head, hd.head)
    aim(ua, "lowerarm_" + side, Vector((s * 0.12, 0.02, -1.0)))
    aim(la, "hand_" + side, Vector((s * 0.02, -0.2, -1.0)))
    print("[vip] nachher", side, ua.head, la.head, hd.head)
    # Finger zur lockeren Faust gekruemmt (Griff fuer Granate/Pistole/Koffer), Beugung um die lokale X-Achse
    CURL = {"01": 38.0, "02": 52.0, "03": 34.0}
    for f in ("index", "middle", "ring", "pinky", "thumb"):
        for j in ("01", "02", "03"):
            pb = rig.pose.bones.get("%s_%s_%s" % (f, j, side))
            if pb is None:
                continue
            ang = CURL[j] * (0.45 if f == "thumb" else 1.0) * (1.08 if f in ("ring", "pinky") else 1.0)
            ax = (rig.matrix_world.to_3x3() @ pb.matrix.to_3x3() @ Vector((1, 0, 0))).normalized()
            rot_bone_world(pb, ax, math.radians(ang) * FINGER_SIGN)
bpy.context.view_layer.update()
bpy.ops.object.mode_set(mode="OBJECT")

# Pose als Ruhelage anwenden
for o in meshes:
    activate(o)
    for m in list(o.modifiers):
        if m.type == "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=m.name)
activate(rig)
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode="OBJECT")
for o in meshes:
    m = o.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    o.parent = rig

# ---------------------------------------------------------------- Ausstattung (eigene Geometrie)
dg = bpy.context.evaluated_depsgraph_get()
suit_bvh = BVHTree.FromObject(suit, dg)
body_bvh = BVHTree.FromObject(body, dg)
head_b = rig.data.bones["head"]
neck_b = rig.data.bones["neck_01"]
HEAD_H = rig.matrix_world @ head_b.head_local
zs = [v.co.z for v in body.data.vertices]
TOP = max(zs)
print("[vip] Koerpergroesse:", TOP, "Kopfgelenk:", HEAD_H)

if CFG.get("buzz"):
    # Kurzhaarschnitt: Haarkarten dicht auf die Kopfhaut legen
    hair_ = parts["hair"]
    for v in hair_.data.vertices:
        loc, nrm, _i, _d = body_bvh.find_nearest(v.co)
        if loc is not None:
            v.co = loc + nrm.normalized() * 0.0025

def new_obj(name, bm, mat):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(mat)
    for p in o.data.polygons:
        p.use_smooth = True
    return o

def skin_to(o, bone):
    g = o.vertex_groups.new(name=bone)
    g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
    m = o.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    o.parent = rig

def head_slice(z, band=0.006):
    pts = [v.co for v in body.data.vertices if abs(v.co.z - z) < band and abs(v.co.x) < 0.12
           and abs(v.co.y - HEAD_H.y) < 0.16]
    xs = [p.x for p in pts]; ys = [p.y for p in pts]
    return (max(xs) - min(xs)) * 0.5, (max(ys) - min(ys)) * 0.5, (max(ys) + min(ys)) * 0.5

GOLD = make_mat("gold", None, 0.4, 0.9, color=(0.62, 0.44, 0.15, 1))
SILVER = make_mat("silver", None, 0.35, 0.9, color=(0.62, 0.64, 0.66, 1))
TRIM = SILVER if KIND in ("weber_uniform", "falk") else GOLD
CAPC = make_mat("cap_cloth", None, 0.9, color={
    "falk": (0.012, 0.012, 0.014, 1), "graumantel": (0.16, 0.17, 0.17, 1)}.get(KIND, (0.085, 0.10, 0.08, 1)))
BAND = make_mat("cap_band", None, 0.95, color=(0.008, 0.008, 0.008, 1) if KIND == "falk" else (0.022, 0.03, 0.022, 1))
VISOR = make_mat("visor", None, 0.15, color=(0.01, 0.01, 0.01, 1))
RED = make_mat("tab_red", None, 0.85, color=(0.20, 0.008, 0.01, 1))

def orient(bm, outward):
    # Flaechen so drehen, dass ihre Normale zu outward(face_center) zeigt
    for f in bm.faces:
        f.normal_update()
        if f.normal.dot(outward(f.calc_center_median())) < 0:
            f.normal_flip()

# Schirmmuetze: Band umschliesst den Kopf knapp ueber den Brauen
zb = TOP - 0.064
rx, ry, cy = head_slice(zb + 0.012)
rx += 0.011; ry += 0.013
print("[vip] Kopf-Ellipse", rx, ry, cy)
OUTW = lambda c: Vector((c.x, c.y - cy, 0.0))

def ring(bm, z, ax, ay, n=48, dy=0.0, zfront=0.0, cyy=None):
    c = cy if cyy is None else cyy
    vs = []
    for i in range(n):
        a = 2 * math.pi * i / n
        x, y = math.sin(a) * ax, -math.cos(a) * ay   # a=0 vorn (-Y)
        front = max(0.0, -y / ay)
        vs.append(bm.verts.new((x, c + y + dy, z + zfront * front ** 2)))
    return vs

def bridge(bm, a, b):
    n = len(a)
    for i in range(n):
        bm.faces.new((a[i], a[(i + 1) % n], b[(i + 1) % n], b[i]))

def build_peaked():
    bm = bmesh.new()
    r0 = ring(bm, zb, rx, ry)
    r1 = ring(bm, zb + 0.036, rx + 0.002, ry + 0.002)
    bridge(bm, r0, r1)
    ri = ring(bm, zb, rx - 0.006, ry - 0.006)
    bridge(bm, ri, r0)
    orient(bm, lambda c: OUTW(c) + Vector((0, 0, -0.02)))
    R0 = [v.co.copy() for v in r0]; R1 = [v.co.copy() for v in r1]
    band = new_obj("CapBand", bm, BAND)

    bm = bmesh.new()
    c0 = ring(bm, zb + 0.034, rx + 0.002, ry + 0.002)
    c1 = ring(bm, zb + 0.058, rx * 1.10, ry * 1.16, dy=-0.003, zfront=0.012)
    c2 = ring(bm, zb + 0.076, rx * 1.24, ry * 1.34, dy=-0.006, zfront=0.028)
    c3 = ring(bm, zb + 0.082, rx * 1.20, ry * 1.30, dy=-0.006, zfront=0.029)
    bridge(bm, c0, c1); bridge(bm, c1, c2); bridge(bm, c2, c3)
    C2 = [v.co.copy() for v in c2]
    ctr = bm.verts.new((0, cy - 0.006, zb + 0.090))
    n = len(c3)
    for i in range(n):
        bm.faces.new((c3[i], c3[(i + 1) % n], ctr))
    orient(bm, lambda c: OUTW(c) + Vector((0, 0, max(0.0, c.z - zb - 0.07) * 4)))
    crown = new_obj("CapCrown", bm, CAPC)

    # Paspel (gold) an Kronenrand und Bandkanten
    def cord(bm, ringpts, r=0.0022, k=6):
        n = len(ringpts)
        loops = []
        for i in range(n):
            p = Vector(ringpts[i]); q = Vector(ringpts[(i + 1) % n]); o_ = Vector(ringpts[i - 1])
            t = (q - o_).normalized()
            a = t.cross(Vector((0, 0, 1))).normalized()
            b = t.cross(a).normalized()
            loops.append([bm.verts.new(p + (a * math.cos(2 * math.pi * j / k) + b * math.sin(2 * math.pi * j / k)) * r) for j in range(k)])
        for i in range(n):
            A, B = loops[i], loops[(i + 1) % n]
            for j in range(k):
                bm.faces.new((A[j], A[(j + 1) % k], B[(j + 1) % k], B[j]))

    bm = bmesh.new()
    cord(bm, C2)
    cord(bm, R0, 0.0016)
    cord(bm, R1, 0.0016)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    piping = new_obj("CapPiping", bm, TRIM)

    # Schirm: halbe Ellipse vorn, leicht nach unten geneigt
    bm = bmesh.new()
    inner, outer = [], []
    NV = 24
    for i in range(NV + 1):
        a = math.pi * (-0.5 + i / NV) * 0.98
        x, y = math.sin(a) * (rx + 0.002), -math.cos(a) * (ry + 0.002)
        inner.append(bm.verts.new((x, cy + y, zb + 0.002)))
        L = 0.052 * math.cos(a) ** 0.7
        out = Vector((x, y, 0)).normalized()
        outer.append(bm.verts.new((x + out.x * L, cy + y + out.y * L, zb + 0.002 - L * 0.42)))
    for i in range(NV):
        bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
    orient(bm, lambda c: Vector((0, 0, 1)))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.0035)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    visor = new_obj("CapVisor", bm, VISOR)

    # Kinnkordel (gold) vorn ueber dem Schirm + erfundenes Emblem
    bm = bmesh.new()
    pts = []
    for i in range(17):
        a = math.pi * (-0.36 + 0.72 * i / 16)
        pts.append(Vector((math.sin(a) * (rx + 0.0042), cy - math.cos(a) * (ry + 0.0042), zb + 0.008)))
    for off in (0.0, 0.005):
        seg = [p + Vector((0, 0, off)) for p in pts]
        k = 6; r = 0.0022; loops = []
        for i, p in enumerate(seg):
            t = (seg[min(i + 1, len(seg) - 1)] - seg[max(i - 1, 0)]).normalized()
            a_ = t.cross(Vector((0, 0, 1))).normalized(); b_ = t.cross(a_).normalized()
            loops.append([bm.verts.new(p + (a_ * math.cos(2 * math.pi * j / k) + b_ * math.sin(2 * math.pi * j / k)) * r) for j in range(k)])
        for i in range(len(loops) - 1):
            A, B = loops[i], loops[i + 1]
            for j in range(k):
                bm.faces.new((A[j], A[(j + 1) % k], B[(j + 1) % k], B[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    # Emblem (erfunden): gebrochener Ring mit senkrechter Klinge und Parierstange, vorn an der Krone
    ez = zb + 0.056; ey = cy - (ry * 1.17) - 0.006
    emb = []
    def disc_ring(bm, c, r0_, r1_, a0, a1, n=20):
        vs_in, vs_out = [], []
        for i in range(n + 1):
            a = a0 + (a1 - a0) * i / n
            vs_in.append(bm.verts.new(c + Vector((math.sin(a) * r0_, 0, math.cos(a) * r0_))))
            vs_out.append(bm.verts.new(c + Vector((math.sin(a) * r1_, 0, math.cos(a) * r1_))))
        for i in range(n):
            emb.append(bm.faces.new((vs_in[i], vs_out[i], vs_out[i + 1], vs_in[i + 1])))
    ec = Vector((0, ey, ez))
    disc_ring(bm, ec, 0.0095, 0.0135, math.radians(25), math.radians(335))
    blade = [(-0.0024, -0.016), (0.0024, -0.016), (0.0024, 0.010), (0.0, 0.018), (-0.0024, 0.010)]
    emb.append(bm.faces.new([bm.verts.new(ec + Vector((x, -0.0015, z))) for x, z in blade]))
    emb.append(bm.faces.new([bm.verts.new(ec + Vector((x, -0.0016, z))) for x, z in
                             [(-0.007, -0.0095), (0.007, -0.0095), (0.007, -0.007), (-0.007, -0.007)]]))
    for f in emb:
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
    emb_geo = bmesh.ops.extrude_face_region(bm, geom=emb)
    for v in [e for e in emb_geo["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.y += 0.0015
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    cap_gold = new_obj("CapGold", bm, TRIM)
    # Kokarde (Bandmitte vorn, ueber der Kordel)
    bm = bmesh.new()
    kc = Vector((0, cy - ry - 0.0045, zb + 0.026))
    ring_o = [bm.verts.new(kc + Vector((math.sin(2 * math.pi * i / 20) * 0.0075, 0, math.cos(2 * math.pi * i / 20) * 0.0075))) for i in range(20)]
    f = bm.faces.new(ring_o)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    kok = new_obj("CapCockade", bm, RED)
    return [band, crown, piping, visor, cap_gold, kok]


def build_beret():
    # Barett: schmales Lederband, weiche, nach rechts gezogene Krone, kleines Abzeichen vorn links
    bm = bmesh.new()
    r0 = ring(bm, zb + 0.004, rx + 0.001, ry + 0.001)
    r1 = ring(bm, zb + 0.018, rx + 0.003, ry + 0.003)
    bridge(bm, r0, r1)
    orient(bm, lambda c: OUTW(c))
    band = new_obj("CapBand", bm, BAND)
    bm = bmesh.new()
    c0 = ring(bm, zb + 0.016, rx + 0.003, ry + 0.003)
    rings = [c0]
    for z, k, sx in ((0.03, 1.10, 0.012), (0.048, 1.24, 0.03), (0.062, 1.27, 0.046), (0.071, 1.06, 0.05)):
        rr = ring(bm, zb + z, rx * k, ry * (k * 0.98), dy=0.004)
        for v in rr:
            v.co.x -= sx   # Krone zur rechten Kopfseite (Blender -X) gezogen
            v.co.z -= 0.02 * max(0.0, -v.co.x / rx)   # zur Zugseite hin tiefer
        rings.append(rr)
    for i in range(len(rings) - 1):
        bridge(bm, rings[i], rings[i + 1])
    ctr = bm.verts.new((-0.045, cy + 0.004, zb + 0.073))
    last = rings[-1]; n = len(last)
    for i in range(n):
        bm.faces.new((last[i], last[(i + 1) % n], ctr))
    orient(bm, lambda c: OUTW(c) + Vector((0, 0, max(0.0, c.z - zb - 0.05) * 6)))
    crown = new_obj("CapCrown", bm, CAPC)
    bm = bmesh.new()
    bc = Vector((0.032, cy - ry - 0.004, zb + 0.034))
    vs = [bm.verts.new(bc + Vector((math.sin(2 * math.pi * i / 12) * 0.011, 0, math.cos(2 * math.pi * i / 12) * 0.013)))
          for i in range(12)]
    f = bm.faces.new(vs)
    f.normal_update()
    if f.normal.y > 0:
        f.normal_flip()
    return [band, crown, new_obj("CapBadge", bm, TRIM)]

def build_field():
    # Feldmuetze: weiche Krone mit kurzem Stoffschirm, alles im Mantelstoff
    bm = bmesh.new()
    c0 = ring(bm, zb, rx + 0.004, ry + 0.004)
    c1 = ring(bm, zb + 0.04, rx * 1.03 + 0.004, ry * 1.05 + 0.004, zfront=0.006)
    c2 = ring(bm, zb + 0.066, rx * 1.0, ry * 1.03, zfront=0.008)
    c3 = ring(bm, zb + 0.071, rx * 0.86, ry * 0.9, zfront=0.008)
    ci = ring(bm, zb, rx - 0.004, ry - 0.004)
    bridge(bm, ci, c0); bridge(bm, c0, c1); bridge(bm, c1, c2); bridge(bm, c2, c3)
    ctr = bm.verts.new((0, cy, zb + 0.074))
    n = len(c3)
    for i in range(n):
        bm.faces.new((c3[i], c3[(i + 1) % n], ctr))
    orient(bm, lambda c: OUTW(c) + Vector((0, 0, max(0.0, c.z - zb - 0.06) * 6)) + Vector((0, 0, -0.02)))
    crown = new_obj("CapCrown", bm, CAPC)
    bm = bmesh.new()
    inner, outer = [], []
    NV = 16
    for i in range(NV + 1):
        a = math.pi * (-0.5 + i / NV) * 0.9
        x, y = math.sin(a) * (rx + 0.005), -math.cos(a) * (ry + 0.005)
        inner.append(bm.verts.new((x, cy + y, zb + 0.004)))
        L = 0.046 * math.cos(a) ** 0.8
        out = Vector((x, y, 0)).normalized()
        outer.append(bm.verts.new((x + out.x * L, cy + y + out.y * L, zb + 0.004 - L * 0.3)))
    for i in range(NV):
        bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
    orient(bm, lambda c: Vector((0, 0, 1)))
    bmesh.ops.solidify(bm, geom=bm.faces[:], thickness=0.004)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return [crown, new_obj("CapVisor", bm, CAPC)]

capparts = {"peaked": build_peaked, "beret": build_beret, "field": build_field}[CFG["cap"]]() if CFG["cap"] else []

# Haare unter der Muetze an den Schaedel ziehen (stehen sonst durch Band/Krone)
hair = parts["hair"]
for v in (hair.data.vertices if capparts else ()):
    if v.co.z < zb - 0.004:
        continue
    e = math.sqrt((v.co.x / (rx - 0.004)) ** 2 + ((v.co.y - cy) / (ry - 0.004)) ** 2)
    if e > 1.0:
        v.co.x /= e
        v.co.y = cy + (v.co.y - cy) / e

# vollstaendig von der Muetze verdeckte Haarkarten entfernen (Dreiecksbudget)
if capparts:
    delete_verts(hair, lambda v, dl: v.co.z > zb + 0.016)

# Muetzenteile zu einem Objekt "Cap" zusammenfuehren
cap = None
if capparts:
    activate(capparts[0])
    for o in capparts[1:]:
        o.select_set(True)
    bpy.ops.object.join()
    cap = bpy.context.object
    cap.name = "Cap"
    if CFG["cap"] == "peaked":
        # leicht nach hinten gekippt sitzen (Front hoch)
        cap_pivot = Vector((0, cy, zb))
        cap.data.transform(Matrix.Translation(cap_pivot) @ Matrix.Rotation(math.radians(-3), 4, "X") @ Matrix.Translation(-cap_pivot))

# ---------------------------------------------------------------- Uniform-Abzeichen
def surf(bvh, origin, direction):
    hit = bvh.ray_cast(origin, direction)
    return hit

def patch(bm, center, normal, up, w, h, off=0.0025):
    n = normal.normalized(); u = (up - n * up.dot(n)).normalized(); r = u.cross(n).normalized()
    c = center + n * off
    vs = [bm.verts.new(c + r * x * w * 0.5 + u * y * h * 0.5) for x, y in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    return bm.faces.new(vs)

neck_z = (rig.matrix_world @ neck_b.head_local).z
print("[vip] Halsansatz", neck_z)
# Geschlossener Stehkragen (eigene Geometrie) um den Hals, Hemd/Krawatte im Anzug-Textur umgefaerbt
collar_o = None
collar_bvh = None
def neck_slice(z, band=0.005):
    pts = [v.co for v in body.data.vertices if abs(v.co.z - z) < band and abs(v.co.x) < 0.09
           and abs(v.co.y - HEAD_H.y) < 0.12]
    xs = [p.x for p in pts]; ys = [p.y for p in pts]
    return (max(xs) - min(xs)) * 0.5, (max(ys) - min(ys)) * 0.5, (max(ys) + min(ys)) * 0.5
if CFG["collar"]:
    bm = bmesh.new()
    rings = []
    CZ = [(-0.06, 0.016), (-0.035, 0.011), (-0.012, 0.0085), (0.006, 0.0085)]
    for dz, off in CZ:
        z = neck_z + dz
        nx, ny, ncy = neck_slice(z)
        rr = ring(bm, z, nx + off, ny + off, n=32, cyy=ncy, zfront=-0.012)
        rings.append(rr)
    for i in range(len(rings) - 1):
        bridge(bm, rings[i], rings[i + 1])
    # Oberkante nach innen umschlagen (Materialstaerke)
    top = rings[-1]
    inner = []
    for v in top:
        nx, ny, ncy = neck_slice(neck_z + 0.006)
        d = Vector((v.co.x, v.co.y - ncy, 0)).normalized()
        inner.append(bm.verts.new(v.co - d * 0.004 + Vector((0, 0, -0.003))))
    bridge(bm, top, inner)
    NCY = neck_slice(neck_z - 0.02)[2]
    orient(bm, lambda c: Vector((c.x, c.y - NCY, 0.0)))
    COLM = make_mat("suit_collar", None, 0.9, color=(0.075, 0.088, 0.068, 1))
    collar_o = new_obj("Collar", bm, COLM)
    # einfarbige UVs auf eine Stoffstelle der Anzugtextur (Ruecken)
    uvl = collar_o.data.uv_layers.new(name=body.data.uv_layers.active.name)
    for poly in collar_o.data.polygons:
        for li in poly.loop_indices:
            co = collar_o.data.vertices[collar_o.data.loops[li].vertex_index].co
            a = math.atan2(co.x, -(co.y - NCY)) / (2 * math.pi) + 0.5
            uvl.data[li].uv = (0.50 + 0.12 * a, 0.56 + 1.0 * (co.z - (neck_z - 0.07)))
    skin_to(collar_o, "neck_01")
    collar_bvh = BVHTree.FromObject(collar_o, bpy.context.evaluated_depsgraph_get())

tabs = bmesh.new(); tabgold = bmesh.new()
for s in ((-1, 1) if CFG["tabs"] else ()):
    if collar_bvh is not None:
        # Kragenspiegel vorn auf dem Stehkragen (waagrecht)
        nz = neck_z - 0.024
        o = Vector((s * 0.05, -0.4, nz))
        hit = collar_bvh.ray_cast(o, Vector((0, 1, 0)))
        if hit[0] is not None:
            p, nrm = hit[0], hit[1]
            up = Vector((0, 0, 1))
            patch(tabs, p, nrm, up, 0.034, 0.022, off=0.0015)
            n_ = nrm.normalized(); u = (up - n_ * up.dot(n_)).normalized(); r = u.cross(n_).normalized()
            for dz in (-0.0055, 0.0055):
                patch(tabgold, p + u * dz, nrm, up, 0.027, 0.003, off=0.0025)
            patch(tabgold, p - r * s * 0.012, nrm, up, 0.003, 0.014, off=0.0026)
        continue
    # Kragenspiegel oben auf dem Revers, parallel zur Kragenkante
    o = Vector((s * 0.068, -0.4, neck_z - 0.058))
    hit = suit_bvh.ray_cast(o, Vector((0, 1, 0)))
    if hit[0] is not None:
        p, nrm = hit[0], hit[1]
        up = Vector((s * -0.45, 0, 1))
        patch(tabs, p, nrm, up, 0.026, 0.044, off=0.0022)
        n_ = nrm.normalized(); u = (up - n_ * up.dot(n_)).normalized(); r = u.cross(n_).normalized()
        # Goldstickerei: zwei Laengslitzen + Querschlag oben
        for dx in (-0.0055, 0.0055):
            patch(tabgold, p + r * dx, nrm, up, 0.0035, 0.034, off=0.0032)
        patch(tabgold, p + u * 0.014, nrm, up, 0.015, 0.003, off=0.0033)
for bm_ in (tabs, tabgold):
    for f in bm_.faces:
        f.normal_update()
        if f.normal.y > 0:
            f.normal_flip()
tabs_o = new_obj("CollarTabs", tabs, RED)
tabs_o.data.materials.clear(); tabs_o.data.materials.append(RED)
tabg_o = new_obj("CollarGold", tabgold, GOLD)

# Schulterstuecke: geflochtene Goldplatte auf karmesinroter Unterlage, von Kragen bis Schulternaht
def strip(bm, pts, nrms, across, width, h_fn, thick):
    rows = []
    NJ = 6
    for i, (p, n_) in enumerate(zip(pts, nrms)):
        a = (across - n_ * across.dot(n_)).normalized()
        row = []
        for j in range(NJ + 1):
            t = -1 + 2 * j / NJ
            # abgerundetes Ende am Kragen (i == 0)
            w = width * 0.5
            if i == 0:
                w *= 0.55
            elif i == 1:
                w *= 0.85
            row.append(bm.verts.new(p + a * t * w + n_ * h_fn(i, j, t)))
        rows.append(row)
    top = []
    for i in range(len(rows) - 1):
        for j in range(NJ):
            top.append(bm.faces.new((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1])))
    for f in top:
        f.normal_update()
        c = f.calc_center_median()
        if f.normal.z < 0:
            f.normal_flip()
    bmesh.ops.solidify(bm, geom=top, thickness=thick)

sb = bmesh.new(); sr = bmesh.new()
for s, side in ((1, "l"), (-1, "r")):
    sh = rig.matrix_world @ rig.data.bones["upperarm_" + side].head_local
    pts, nrms = [], []
    NI = 13
    x0, x1 = 0.085, abs(sh.x) + 0.012
    for t in range(NI + 1):
        x = s * (x0 + (x1 - x0) * t / NI)
        hit = suit_bvh.ray_cast(Vector((x, sh.y + 0.004, sh.z + 0.35)), Vector((0, 0, -1)))
        if hit[0] is None:
            continue
        pts.append(hit[0]); nrms.append(hit[1].normalized() if hit[1].z > 0 else Vector((0, 0, 1)))
    if len(pts) < 4:
        continue
    # Normalen glaetten
    sm = []
    for i in range(len(nrms)):
        acc = nrms[max(0, i - 1)] + nrms[i] * 2 + nrms[min(len(nrms) - 1, i + 1)]
        sm.append(acc.normalized())
    # Unterlage (rot), etwas breiter
    strip(sr, pts, sm, Vector((0, 1, 0)), 0.056, lambda i, j, t: 0.0035, 0.002)
    # Geflecht: Wuelste quer zur Laenge, versetzt je Litze
    def braid(i, j, t):
        ph = i + (0.5 if j % 2 else 0.0)
        bump = 0.0024 * (0.5 + 0.5 * math.cos(math.pi * ph))
        edge = 1.0 - 0.45 * t * t
        return 0.0058 + bump * edge
    strip(sb, pts, sm, Vector((0, 1, 0)), 0.046, braid, 0.002)
    # Knopf am Kragenende
    bc = pts[1] + sm[1] * 0.0085
    for v in bmesh.ops.create_uvsphere(sb, u_segments=8, v_segments=5, radius=0.0045)["verts"]:
        v.co = Vector((v.co.x, v.co.y, v.co.z * 0.5)) + bc
board = new_obj("Boards", sb, SILVER if CFG["boards"] == "silver" else GOLD)
board_r = new_obj("BoardsRed", sr, RED if CFG["boards"] == "gold" else BAND)

# Koppel: braunes Lederkoppel um die Taille mit Rahmenschnalle (Messing)
BELT = make_mat("belt", None, 0.4, color=(0.012, 0.012, 0.012, 1) if KIND in ("falk", "graumantel")
                else (0.032, 0.016, 0.007, 1))
bt = bmesh.new(); bk = bmesh.new()
zw = (rig.matrix_world @ rig.data.bones["spine_01"].head_local).z + 0.02
yc = (rig.matrix_world @ rig.data.bones["spine_01"].head_local).y
NB = 40
rows = []
for dz in (-0.022, 0.022):
    row = []
    for i in range(NB):
        a = 2 * math.pi * i / NB
        d = Vector((math.sin(a), -math.cos(a), 0))
        o = Vector((0, yc, zw + dz))
        hit = suit_bvh.ray_cast(o, d, 0.4)
        p = hit[0] if hit[0] is not None else o + d * 0.15
        row.append(p + d * 0.005)
    rows.append(row)
vs = [[bt.verts.new(p) for p in row] for row in rows]
for i in range(NB):
    bt.faces.new((vs[0][i], vs[0][(i + 1) % NB], vs[1][(i + 1) % NB], vs[1][i]))
for f in bt.faces:
    f.normal_update()
    c = f.calc_center_median()
    if f.normal.dot(Vector((c.x, c.y - yc, 0))) < 0:
        f.normal_flip()
bmesh.ops.solidify(bt, geom=bt.faces[:], thickness=-0.003)
belt_o = new_obj("Belt", bt, BELT)
# Schnalle vorn
fc = (rows[0][0] + rows[1][0]) * 0.5 + Vector((0, -0.003, 0))
for (x0, z0, x1, z1) in ((-0.026, -0.024, 0.026, -0.018), (-0.026, 0.018, 0.026, 0.024),
                         (-0.026, -0.024, -0.020, 0.024), (0.020, -0.024, 0.026, 0.024), (-0.003, -0.018, 0.003, 0.018)):
    bmesh.ops.create_cube(bk, size=1.0, matrix=Matrix.Translation(fc + Vector(((x0 + x1) / 2, 0, (z0 + z1) / 2)))
                          @ Matrix.Diagonal((x1 - x0, 0.004, z1 - z0, 1)))
buckle_o = new_obj("Buckle", bk, GOLD if KIND == "riedhammer" else SILVER)
for p in buckle_o.data.polygons:
    p.use_smooth = False
skin_to(belt_o, "spine_01"); skin_to(buckle_o, "spine_01")

# Ordensspange links auf der Brust (erfundene Farben)
rib = bmesh.new()
RIBC = [(0.5, 0.05, 0.05, 1), (0.05, 0.12, 0.35, 1), (0.85, 0.75, 0.3, 1), (0.1, 0.3, 0.12, 1), (0.6, 0.6, 0.62, 1), (0.4, 0.05, 0.25, 1)]
ribmats = []
rib_o = None
spine = rig.matrix_world @ rig.data.bones["spine_03"].head_local
for row in range(2):
    for col in range(3):
        o = Vector((0.065 + (col - 1) * 0.024 + row * 0.012 * 0, -0.4, spine.z + 0.07 - row * 0.012))
        hit = suit_bvh.ray_cast(o, Vector((0, 1, 0)))
        if hit[0] is None:
            continue
        f = patch(rib, hit[0], hit[1], Vector((0, 0, 1)), 0.023, 0.0105, off=0.004)
        f.material_index = (row * 3 + col) % len(RIBC)
me = bpy.data.meshes.new("Ribbons")
rib.to_mesh(me); rib.free()
rib_o = bpy.data.objects.new("Ribbons", me)
bpy.context.scene.collection.objects.link(rib_o)
for i, c in enumerate(RIBC):
    rib_o.data.materials.append(make_mat("ribbon%d" % i, None, 0.7, color=c))

skin_to(tabs_o, "spine_03"); skin_to(tabg_o, "spine_03"); skin_to(rib_o, "spine_03")
for bo in (board, board_r):
    skin_to(bo, "clavicle_l")
    g = bo.vertex_groups.new(name="clavicle_r")
    gl = bo.vertex_groups["clavicle_l"]
    for v in bo.data.vertices:
        if v.co.x < 0:
            gl.remove([v.index]); g.add([v.index], 1.0, "REPLACE")


# ---------------------------------------------------------------- Armbinde, Brille, Waffenrockknoepfe
# Rundprofil entlang eines geschlossenen Punktrings
def cord(bm, ringpts, r=0.0022, k=6):
    n = len(ringpts)
    loops = []
    for i in range(n):
        p = Vector(ringpts[i]); q = Vector(ringpts[(i + 1) % n]); o_ = Vector(ringpts[i - 1])
        t = (q - o_).normalized()
        a = t.cross(Vector((0, 0, 1))).normalized()
        b = t.cross(a).normalized()
        loops.append([bm.verts.new(p + (a * math.cos(2 * math.pi * j / k) + b * math.sin(2 * math.pi * j / k)) * r) for j in range(k)])
    for i in range(n):
        A, B = loops[i], loops[(i + 1) % n]
        for j in range(k):
            bm.faces.new((A[j], A[(j + 1) % k], B[(j + 1) % k], B[j]))

extras = []
ARMB = make_mat("armband", None, 0.6, color=(1.0, 0.6, 0.12, 1))
if CFG["armband"]:
    # Amber-Armbinde am linken Oberarm (Blender +X), Ring dicht auf dem Aermel
    ua = rig.data.bones["upperarm_l"]
    a0 = rig.matrix_world @ ua.head_local; a1 = rig.matrix_world @ ua.tail_local
    axis = (a1 - a0).normalized()
    side_ = axis.cross(Vector((0, 1, 0))).normalized(); fwd = axis.cross(side_).normalized()
    bm = bmesh.new(); rows = []
    for t in (0.36, 0.5):
        c = a0 + (a1 - a0) * t
        row = []
        for i in range(24):
            ang = 2 * math.pi * i / 24
            d = side_ * math.cos(ang) + fwd * math.sin(ang)
            hit = suit_bvh.ray_cast(c + d * 0.2, -d, 0.25)
            pnt = hit[0] if hit[0] is not None else c + d * 0.05
            row.append(bm.verts.new(pnt + d * 0.003))
        rows.append(row)
    bridge(bm, rows[0], rows[1])
    for f in bm.faces:
        f.normal_update()
        cc = f.calc_center_median() - a0
        if f.normal.dot(cc - axis * cc.dot(axis)) < 0:
            f.normal_flip()
    arm_o = new_obj("Armband", bm, ARMB)
    skin_to(arm_o, "upperarm_l")
    extras.append(arm_o)

GLASS = make_mat("glasses", None, 0.3, 0.8, color=(0.04, 0.04, 0.045, 1))
glasses_o = None
if CFG["glasses"]:
    eye = parts["eye"]
    bm = bmesh.new()
    centers = []
    for sg in (1, -1):
        vs = [v.co for v in eye.data.vertices if v.co.x * sg > 0]
        c = sum(vs, Vector()) / len(vs)
        front = min(v.y for v in vs)
        centers.append(Vector((c.x, front - 0.014, c.z + 0.002)))
    for c in centers:
        pts = [c + Vector((math.cos(2 * math.pi * i / 24) * 0.024, 0.0, math.sin(2 * math.pi * i / 24) * 0.0175))
               for i in range(24)]
        # leicht gewoelbt: Aussenrand etwas weiter hinten
        pts = [p_ + Vector((0, 0.004 * ((p_.x - c.x) / 0.024) ** 2, 0)) for p_ in pts]
        cord(bm, pts, 0.0013, 6)
    # Steg und Buegel bis hinters Ohr
    def bar(p0, p1, r=0.0012, k=6):
        t = (p1 - p0).normalized()
        a_ = t.cross(Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))).normalized(); b_ = t.cross(a_)
        A = [bm.verts.new(p0 + (a_ * math.cos(2 * math.pi * j / k) + b_ * math.sin(2 * math.pi * j / k)) * r) for j in range(k)]
        B = [bm.verts.new(p1 + (a_ * math.cos(2 * math.pi * j / k) + b_ * math.sin(2 * math.pi * j / k)) * r) for j in range(k)]
        for j in range(k):
            bm.faces.new((A[j], A[(j + 1) % k], B[(j + 1) % k], B[j]))
    cl, cr = centers
    bar(cl - Vector((0.024, 0, -0.004)), cr + Vector((0.024, 0, 0.004)))
    for c, sg in ((cl, 1), (cr, -1)):
        p0 = c + Vector((sg * 0.024, 0.002, 0.003))
        hx, hy, hcy = head_slice(c.z, 0.008)
        p1 = Vector((sg * (hx + 0.004), hcy + 0.01, c.z + 0.004))
        hit = body_bvh.ray_cast(Vector((sg * 0.2, p1.y, p1.z)), Vector((-sg, 0, 0)), 0.3)
        if hit[0] is not None:
            p1 = Vector((hit[0].x + sg * 0.004, p1.y, p1.z))
        pm = Vector((p1.x, p0.y + 0.012, p0.z))
        bar(p0, pm); bar(pm, p1)
    # Glaeser (fast unsichtbar, nur Glanz)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    glasses_o = new_obj("Glasses", bm, GLASS)
    skin_to(glasses_o, "head")
    extras.append(glasses_o)

if CFG["collar"]:
    # Waffenrock-Knopfleiste im (umgefaerbten) Ausschnitt
    bm = bmesh.new()
    for k in range(4):
        z = neck_z - 0.075 - k * 0.055
        hit = suit_bvh.ray_cast(Vector((0, -0.4, z)), Vector((0, 1, 0)))
        if hit[0] is None:
            continue
        for v in bmesh.ops.create_uvsphere(bm, u_segments=8, v_segments=5, radius=0.0062)["verts"]:
            v.co = Vector((v.co.x, v.co.y * 0.45, v.co.z)) + hit[0] + Vector((0, -0.002, 0))
    btn_o = new_obj("Buttons", bm, TRIM)
    skin_to(btn_o, "spine_03")
    extras.append(btn_o)
    extras.append(collar_o)

# ---------------------------------------------------------------- zusammenfuegen
for o in [body] + list(parts.values()):
    print("[vip] tris", o.name, sum(len(p.vertices) - 2 for p in o.data.polygons))
# Dreiecksbudget < 40k: Anzug bei Bedarf vorsichtig reduzieren (Planar-Decimate erhaelt Silhouette/UVs)
def ntri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
cap_t = ntri(cap) if cap else 0
est = sum(ntri(o) for o in [body] + list(parts.values())) + cap_t + 2600
if est > 39000:
    sm_ = parts["suit"]
    ratio = max(0.6, 1.0 - (est - 38500) / ntri(sm_))
    activate(sm_)
    dm = sm_.modifiers.new("Dec", "DECIMATE")
    dm.ratio = ratio
    dm.use_collapse_triangulate = True
    # vor dem Armature-Modifier anwenden
    while sm_.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")
    print("[vip] Anzug reduziert auf", ntri(sm_), "ratio", round(ratio, 3))
keep = [tabs_o, tabg_o] if CFG["tabs"] else []
keep += [rib_o] if CFG["ribbons"] else []
keep += [board, board_r] if CFG["boards"] else []
keep += [belt_o, buckle_o] if CFG["belt"] else []
for o in (tabs_o, tabg_o, rib_o, board, board_r, belt_o, buckle_o):
    if o not in keep:
        bpy.data.objects.remove(o, do_unlink=True)
allm = [body] + list(parts.values()) + keep + extras
activate(body)
for o in allm[1:]:
    o.select_set(True)
bpy.ops.object.join()
body = bpy.context.object
body.name = "Body"
# Material-Duplikate zusammenlegen
tri = sum(len(p.vertices) - 2 for p in body.data.polygons)
tri_cap = sum(len(p.vertices) - 2 for p in cap.data.polygons) if cap else 0
print("[vip] Dreiecke Body", tri, "Cap", tri_cap, "Summe", tri + tri_cap)
if cap:
    cap.parent = None
# Kopfgelenk / Schulter / Huefte ausgeben (Blender Z-up)
for b in ("head", "neck_01", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r", "hand_l"):
    print("[vip] Knochen", b, tuple(round(c, 4) for c in (rig.matrix_world @ rig.data.bones[b].head_local)))

if OUT_BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for x in bpy.context.selected_objects:
    x.select_set(False)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                          export_skins=True, export_animations=False, export_morph=False, export_yup=True,
                          export_image_format="AUTO", export_texcoords=True, export_normals=True,
                          export_tangents=False, export_attributes=False)
print("[vip] exportiert", OUT_GLB)
