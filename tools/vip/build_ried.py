# Blender 4.2 + MPFB2: General von Riedhammer aus MakeHuman-CC0-Assets bauen und als GLB exportieren.
# Aufruf (Blender 4.2 + MPFB 2.0.18 mit CC0-Asset-Packs, OHNE --factory-startup):
#   python prep_tex.py <tex_dir>  ;  blender -b --python build_ried.py -- <tex_dir> <out.glb> [out.blend]
# Pfade D/TG unten auf die lokale MPFB-Installation anpassen.
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, OUT_GLB = argv[0], argv[1]
OUT_BLEND = argv[2] if len(argv) > 2 else ""

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
TG = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/user_default/mpfb/data/targets"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

macro = {"gender": 1.0, "age": 0.76, "muscle": 0.62, "weight": 0.56, "proportions": 0.8,
         "height": 0.56, "cupsize": 0.5, "firmness": 0.5,
         "race": {"asian": 0.03, "caucasian": 0.94, "african": 0.03}}
body = HumanService.create_human(macro_detail_dict=macro, scale=0.1)

# Gesicht: kantig, markantes Kinn, schmale Wangen
FACE = {
    "head/head-square": 0.35, "chin/chin-prominent-incr": 0.35, "chin/chin-width-incr": 0.2,
    "cheek/l-cheek-bones-incr": 0.3, "cheek/r-cheek-bones-incr": 0.3,
    "eyebrows/eyebrows-trans-down": 0.25, "nose/nose-hump-incr": 0.3,
    "neck/neck-scale-horiz-incr": 0.25,
}
for t, w in FACE.items():
    p = os.path.join(TG, t + ".target.gz")
    if os.path.isfile(p):
        TargetService.load_target(body, p, weight=w)
    else:
        print("[ried] Target fehlt:", t)

rig = HumanService.add_builtin_rig(body, "game_engine")

ASSETS = [
    ("eyes/low-poly/low-poly.mhclo", "Eyes", "eye"),
    ("eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows", "brow"),
    ("eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "lash"),
    ("hair/short02/short02.mhclo", "Hair", "hair"),
    ("clothes/male_elegantsuit01/male_elegantsuit01.mhclo", "Clothes", "suit"),
    ("clothes/culturalibre_hero_boots_2/culturalibre_hero_boots_2.mhclo", "Clothes", "boots"),
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
print("[ried] Stiefelschaft oben:", btop)
suit = parts["suit"]
delete_verts(suit, lambda v, dl: v.co.z < btop - 0.05)
# Hosenbeine zum Stiefelschaft hin einziehen (in die Stiefel gesteckt statt Anzughose)
for s_ in (1, -1):
    top = [boots.matrix_world @ v.co for v in boots.data.vertices
           if (boots.matrix_world @ v.co).z > btop - 0.03 and v.co.x * s_ > 0]
    if not top:
        continue
    bc = sum(top, Vector()) / len(top)
    rb = sum(((p - bc).xy.length for p in top), 0.0) / len(top)
    print("[ried] Schaft", s_, tuple(round(c, 3) for c in bc), "r", round(rb, 3))
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

def aim(pb, child, target):
    cur = rig.pose.bones[child].head - pb.head
    q = cur.normalized().rotation_difference(target.normalized())
    axis, ang = q.to_axis_angle()
    rot_bone_world(pb, axis, ang)

for side, s in (("l", 1.0), ("r", -1.0)):
    ua = rig.pose.bones["upperarm_" + side]
    la = rig.pose.bones["lowerarm_" + side]
    hd = rig.pose.bones["hand_" + side]
    print("[ried] vorher", side, ua.head, la.head, hd.head)
    aim(ua, "lowerarm_" + side, Vector((s * 0.12, 0.02, -1.0)))
    aim(la, "hand_" + side, Vector((s * 0.02, -0.2, -1.0)))
    print("[ried] nachher", side, ua.head, la.head, hd.head)
    # Finger leicht gekruemmt
    for f in ("index", "middle", "ring", "pinky"):
        for j in ("01", "02", "03"):
            pb = rig.pose.bones.get("%s_%s_%s" % (f, j, side))
            if pb:
                pb.rotation_mode = "XYZ"
                pass
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
print("[ried] Koerpergroesse:", TOP, "Kopfgelenk:", HEAD_H)

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
CAPC = make_mat("cap_cloth", None, 0.9, color=(0.085, 0.10, 0.08, 1))
BAND = make_mat("cap_band", None, 0.95, color=(0.022, 0.03, 0.022, 1))
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
print("[ried] Kopf-Ellipse", rx, ry, cy)
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
piping = new_obj("CapPiping", bm, GOLD)

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
cap_gold = new_obj("CapGold", bm, GOLD)
# Kokarde (Bandmitte vorn, ueber der Kordel)
bm = bmesh.new()
kc = Vector((0, cy - ry - 0.0045, zb + 0.026))
ring_o = [bm.verts.new(kc + Vector((math.sin(2 * math.pi * i / 20) * 0.0075, 0, math.cos(2 * math.pi * i / 20) * 0.0075))) for i in range(20)]
f = bm.faces.new(ring_o)
f.normal_update()
if f.normal.y > 0:
    f.normal_flip()
kok = new_obj("CapCockade", bm, RED)

# Haare unter der Muetze an den Schaedel ziehen (stehen sonst durch Band/Krone)
hair = parts["hair"]
for v in hair.data.vertices:
    if v.co.z < zb - 0.004:
        continue
    e = math.sqrt((v.co.x / (rx - 0.004)) ** 2 + ((v.co.y - cy) / (ry - 0.004)) ** 2)
    if e > 1.0:
        v.co.x /= e
        v.co.y = cy + (v.co.y - cy) / e

# Muetzenteile zu einem Objekt "Cap" zusammenfuehren
capparts = [band, crown, piping, visor, cap_gold, kok]
activate(capparts[0])
for o in capparts[1:]:
    o.select_set(True)
bpy.ops.object.join()
cap = bpy.context.object
cap.name = "Cap"
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
print("[ried] Halsansatz", neck_z)
tabs = bmesh.new(); tabgold = bmesh.new()
for s in (-1, 1):
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
board = new_obj("Boards", sb, GOLD)
board_r = new_obj("BoardsRed", sr, RED)

# Koppel: braunes Lederkoppel um die Taille mit Rahmenschnalle (Messing)
BELT = make_mat("belt", None, 0.4, color=(0.032, 0.016, 0.007, 1))
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
buckle_o = new_obj("Buckle", bk, GOLD)
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

# ---------------------------------------------------------------- zusammenfuegen
allm = [body] + list(parts.values()) + [tabs_o, tabg_o, rib_o, board, board_r, belt_o, buckle_o]
activate(body)
for o in allm[1:]:
    o.select_set(True)
bpy.ops.object.join()
body = bpy.context.object
body.name = "Body"
# Material-Duplikate zusammenlegen
tri = sum(len(p.vertices) - 2 for p in body.data.polygons)
tri_cap = sum(len(p.vertices) - 2 for p in cap.data.polygons)
print("[ried] Dreiecke Body", tri, "Cap", tri_cap)
cap.parent = None
# Kopfgelenk / Schulter / Huefte ausgeben (Blender Z-up)
for b in ("head", "neck_01", "upperarm_l", "upperarm_r", "thigh_l", "thigh_r", "hand_l"):
    print("[ried] Knochen", b, tuple(round(c, 4) for c in (rig.matrix_world @ rig.data.bones[b].head_local)))

if OUT_BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for x in bpy.context.selected_objects:
    x.select_set(False)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                          export_skins=True, export_animations=False, export_morph=False, export_yup=True,
                          export_image_format="AUTO", export_texcoords=True, export_normals=True,
                          export_tangents=False, export_attributes=False)
print("[ried] exportiert", OUT_GLB)
