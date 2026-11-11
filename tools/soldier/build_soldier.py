# Blender 4.2 + MPFB2: realistischer Gegner-Soldat aus MakeHuman-CC0-Assets (Vorlage: tools/vip/build_vip.py).
# Aufruf (Blender 4.2 + MPFB 2.0.18 mit CC0-Asset-Packs, OHNE --factory-startup):
#   python prep_soldier.py <tex_dir> <helmet_dir>
#   blender -b --python build_soldier.py -- <tex_dir> <helmet_dir> <out.glb> --var=a|b|c [out.blend]
# Ergebnis: geriggtes GLB (MPFB-"game_engine"-Skelett, Knochen auf die SWAT-Namen der Soldaten-Pipeline
# umbenannt), Objekte "Body" (Haut/Augen/Brauen/Wimpern/Haar/Uniform/Stiefel) und "Helmet" (M1, an "Head").
# Knochenachsen werden fuer SoldierIK vereinheitlicht: Wirbelsaeule/Beine/Arme lokal +Z = vorn,
# Hand/Finger lokal +Z = Handruecken, Fuesse +Z = oben (Godot: +Z vorn, +X linke Koerperseite).
import bpy, bmesh, math, sys, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

argv = sys.argv[sys.argv.index("--") + 1:]
TEX, HELM_DIR, OUT_GLB = argv[0], argv[1], argv[2]
VAR = "a"
OUT_BLEND = ""
for a in argv[3:]:
    if a.startswith("--var="):
        VAR = a[6:]
    else:
        OUT_BLEND = a
BUDGET = 15000   # Dreiecke LOD0 (Body + Helm)

# Drei Gesichter/Statur-Varianten; gleiche Groesse (+-2 %), damit die Clips ueberall sauber sitzen
CFG = {
    "a": {"macro": {"age": 0.42, "muscle": 0.62, "weight": 0.5, "height": 0.55, "proportions": 0.75},
          "face": {"head/head-square": 0.25, "chin/chin-prominent-incr": 0.2, "nose/nose-hump-incr": 0.1,
                   "eyebrows/eyebrows-trans-down": 0.2, "neck/neck-scale-horiz-incr": 0.3}},
    "b": {"macro": {"age": 0.62, "muscle": 0.6, "weight": 0.6, "height": 0.52, "proportions": 0.7},
          "face": {"head/head-rectangular": 0.35, "chin/chin-width-incr": 0.3, "nose/nose-scale-horiz-incr": 0.25,
                   "cheek/l-cheek-bones-incr": 0.25, "cheek/r-cheek-bones-incr": 0.25,
                   "eyebrows/eyebrows-trans-down": 0.3, "head/head-age-incr": 0.25, "neck/neck-scale-horiz-incr": 0.4}},
    "c": {"macro": {"age": 0.48, "muscle": 0.56, "weight": 0.44, "height": 0.58, "proportions": 0.8},
          "face": {"head/head-oval": 0.3, "chin/chin-prominent-decr": 0.15, "nose/nose-point-width-decr": 0.3,
                   "nose/nose-trans-down": 0.2, "head/head-scale-horiz-decr": 0.12}},
}[VAR]
print("[soldier] Variante:", VAR)

from bl_ext.user_default.mpfb.services.humanservice import HumanService
from bl_ext.user_default.mpfb.services.targetservice import TargetService

D = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/.user/user_default/mpfb/data"
TG = r"C:/Users/snofl/AppData/Local/Temp/b42/portable/extensions/user_default/mpfb/data/targets"

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

macro = {"gender": 1.0, "cupsize": 0.5, "firmness": 0.5,
         "race": {"asian": 0.04, "caucasian": 0.92, "african": 0.04}}
macro.update(CFG["macro"])
body = HumanService.create_human(macro_detail_dict=macro, scale=0.1)
for t, w in CFG["face"].items():
    p = os.path.join(TG, t + ".target.gz")
    if os.path.isfile(p):
        TargetService.load_target(body, p, weight=w)
    else:
        print("[soldier] Target fehlt:", t)

rig = HumanService.add_builtin_rig(body, "game_engine")

ASSETS = [
    (D + "/eyes/low-poly/low-poly.mhclo", "Eyes", "eye"),
    (D + "/eyebrows/eyebrow001/eyebrow001.mhclo", "Eyebrows", "brow"),
    (D + "/eyelashes/eyelashes01/eyelashes01.mhclo", "Eyelashes", "lash"),
    (D + "/hair/short02/short02.mhclo", "Hair", "hair"),
    (D + "/clothes/male_casualsuit01/male_casualsuit01.mhclo", "Clothes", "suit"),
    (D + "/clothes/culturalibre_hero_boots_2/culturalibre_hero_boots_2.mhclo", "Clothes", "boots"),
    (os.path.join(HELM_DIR, "mrgreaterthan_m1_helmet.mhclo"), "Clothes", "helmet"),
]
parts = {}
for path, typ, key in ASSETS:
    parts[key] = HumanService.add_mhclo_asset(path, body, asset_type=typ, subdiv_levels=0, material_type="MAKESKIN")

def activate(o):
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for x in bpy.context.selected_objects:
        x.select_set(False)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)

def ntri(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)

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

# Basismesh: Helfer und von Kleidung verdeckte Koerperteile loeschen
gi = {g.name: g.index for g in body.vertex_groups}
body_idx = gi.get("body")
del_idx = [i for n, i in gi.items() if n.startswith("Delete.")]
delete_verts(body, lambda v, dl: (body_idx not in v[dl]) or any(i in v[dl] and v[dl][i] > 0.5 for i in del_idx))

# Hose in die Stiefel stecken (Schuhe des Freizeitanzugs liegen darunter und fallen weg)
boots = parts["boots"]
suit = parts["suit"]
btop = max((boots.matrix_world @ v.co).z for v in boots.data.vertices)
print("[soldier] Stiefelschaft oben:", round(btop, 3))
delete_verts(suit, lambda v, dl: v.co.z < btop - 0.05)
for s_ in (1, -1):
    top = [boots.matrix_world @ v.co for v in boots.data.vertices
           if (boots.matrix_world @ v.co).z > btop - 0.03 and v.co.x * s_ > 0]
    if not top:
        continue
    bc = sum(top, Vector()) / len(top)
    rb = sum(((p - bc).xy.length for p in top), 0.0) / len(top)
    H = 0.2
    for v in suit.data.vertices:
        if v.co.x * s_ <= 0 or v.co.z > btop + H:
            continue
        w = min(1.0, max(0.0, (btop + H - v.co.z) / H))
        w = w * w * (3 - 2 * w)
        d = Vector((v.co.x - bc.x, v.co.y - bc.y))
        # leicht gebauschte Hose ueber dem Schaft (Feldhose, keine Anzughose)
        lim = rb + 0.008 + 0.035 * max(0.0, v.co.z - btop) / H
        if d.length > lim:
            nd = d.normalized() * (d.length + (lim - d.length) * w)
            v.co.x = bc.x + nd.x; v.co.y = bc.y + nd.y
delete_verts(body, lambda v, dl: v.co.z < btop - 0.04)

# Kurzhaarschnitt (Buzz Cut): Haarkarten dicht auf die Kopfhaut -> nichts sticht durch den Helm
dg = bpy.context.evaluated_depsgraph_get()
body_bvh = BVHTree.FromObject(body, dg)
hair = parts["hair"]
for v in hair.data.vertices:
    loc, nrm, _i, _d = body_bvh.find_nearest(v.co)
    if loc is not None:
        v.co = loc + nrm.normalized() * 0.0022

# Helm: vollstaendig an den Kopfknochen binden (starr), Polygone stark reduzieren
helmet = parts["helmet"]
print("[soldier] Helm roh:", ntri(helmet))

# ---------------------------------------------------------------- Materialien
def make_mat(name, img, rough=0.6, metal=0.0, alpha=False, color=None, normal=None):
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
    if normal:
        nt_ = nt.nodes.new("ShaderNodeTexImage")
        nt_.image = bpy.data.images.load(os.path.join(TEX, normal))
        nt_.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nt_.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m

MATS = {
    "skin": make_mat("Skin_" + VAR, "skin_%s.jpg" % VAR, 0.55), "eye": make_mat("Eye", "eye.jpg", 0.15),
    "brow": make_mat("Brow", "brow.png", 0.8, alpha=True), "lash": make_mat("Lash", "lash.png", 0.8, alpha=True),
    "hair": make_mat("Hair", "hair.png", 0.8, alpha=True),
    "suit": make_mat("Uniform", "suit.jpg", 0.85, normal="suit_n.jpg"),
    "boots": make_mat("Boots", "boots.jpg", 0.35),
    "helmet": make_mat("Helmet", "helmet.jpg", 0.7, normal="helmet_n.jpg"),
}
def set_mat(o, m):
    o.data.materials.clear()
    o.data.materials.append(m)
set_mat(body, MATS["skin"])
for k, o in parts.items():
    set_mat(o, MATS[k])

# ---------------------------------------------------------------- Polygon-Budget (LOD0 ~15k)
def decimate(o, ratio, planar=False):
    activate(o)
    dm = o.modifiers.new("Dec", "DECIMATE")
    if planar:
        dm.decimate_type = "DISSOLVE"
        dm.angle_limit = math.radians(ratio)
    else:
        dm.ratio = ratio
        dm.use_collapse_triangulate = True
    while o.modifiers[0].name != "Dec":
        bpy.ops.object.modifier_move_up(modifier="Dec")
    bpy.ops.object.modifier_apply(modifier="Dec")

# Helm (36k Quads): Blenders Kollaps-Dezimierung bleibt auf dem Originalnetz bei ~8k stehen (duenne
# Doppelschale). Daher: Voxel-Remesh (sauberes geschlossenes Netz) -> Kollaps auf ~1.8k -> UVs vom
# Original per Data-Transfer zurueckholen.
activate(helmet)
src = helmet.copy(); src.data = helmet.data.copy()
bpy.context.collection.objects.link(src)
helmet.modifiers.clear()
ext = max(max(v.co[i] for v in helmet.data.vertices) - min(v.co[i] for v in helmet.data.vertices) for i in range(3))
rm = helmet.modifiers.new("Rem", "REMESH")
rm.mode = "VOXEL"; rm.voxel_size = ext / 110.0; rm.use_smooth_shade = True
bpy.ops.object.modifier_apply(modifier="Rem")
decimate(helmet, 1800.0 / max(1, ntri(helmet)))
dt = helmet.modifiers.new("UVx", "DATA_TRANSFER")
dt.object = src; dt.use_loop_data = True; dt.data_types_loops = {"UV"}; dt.loop_mapping = "POLYINTERP_NEAREST"
bpy.ops.object.modifier_apply(modifier="UVx")
bpy.data.objects.remove(src, do_unlink=True)
for p in helmet.data.polygons:
    p.use_smooth = True
print("[soldier] Helm reduziert:", ntri(helmet))

# (Verdeckte Haut entfernen schon die Delete.*-Gruppen der Uniform: uebrig sind praktisch nur Kopf, Hals, Haende.)
# Wimpern sind auf Spieldistanz unsichtbar und kosten Alpha-Overdraw
bpy.data.objects.remove(parts.pop("lash"), do_unlink=True)
cnt = {k: ntri(o) for k, o in parts.items()}
cnt["body"] = ntri(body)
print("[soldier] Dreiecke vorher:", cnt)
fixed = cnt["eye"] + cnt["brow"] + cnt["helmet"]
flex = {"body": cnt["body"], "suit": cnt["suit"], "boots": cnt["boots"], "hair": cnt["hair"]}
avail = BUDGET - fixed
tot = sum(flex.values())
if tot > avail:
    # Haut (Gesicht!) schonender reduzieren als Kleidung
    wgt = {"body": 0.6, "suit": 1.0, "boots": 1.2, "hair": 1.6}
    # gemeinsamen Faktor f suchen: sum(n * min(1, f / w)) = avail
    lo_, hi_ = 0.05, 1.0
    for _ in range(40):
        f = (lo_ + hi_) * 0.5
        s = sum(n * min(1.0, f / wgt[k]) for k, n in flex.items())
        lo_, hi_ = (f, hi_) if s < avail else (lo_, f)
    for k, n in flex.items():
        r = min(1.0, lo_ / wgt[k])
        if r < 0.995:
            decimate(body if k == "body" else parts[k], r)
print("[soldier] Dreiecke nachher:", {"body": ntri(body), **{k: ntri(o) for k, o in parts.items()}})

# ---------------------------------------------------------------- Knochen: SWAT-Namen + einheitliche Achsen
REN = {"pelvis": "Hips", "spine_01": "Abdomen", "spine_02": "Torso", "spine_03": "Chest", "neck_01": "Neck",
       "head": "Head"}
for s, S in (("l", "L"), ("r", "R")):
    REN.update({"clavicle_" + s: "Shoulder." + S, "upperarm_" + s: "UpperArm." + S, "lowerarm_" + s: "LowerArm." + S,
                "hand_" + s: "Wrist." + S, "thigh_" + s: "UpperLeg." + S, "calf_" + s: "LowerLeg." + S,
                "foot_" + s: "Foot." + S, "ball_" + s: "Toes." + S})
    for f in ("index", "middle", "ring", "pinky", "thumb"):
        for j in (1, 2, 3):
            REN["%s_%02d_%s" % (f, j, s)] = "%s%d.%s" % (f.capitalize(), j, S)

activate(rig)
bpy.ops.object.mode_set(mode="EDIT")
eb = rig.data.edit_bones
FRONT = Vector((0, -1, 0))
UP = Vector((0, 0, 1))
def back_of_hand(side):
    h = eb["hand_" + side]
    fing = (eb["middle_01_" + side].head - h.head).normalized()
    th = eb["thumb_01_" + side].head - h.head
    th = (th - fing * th.dot(fing)).normalized()
    n = fing.cross(th)
    return (-n if side == "l" else n).normalized()
BOH = {s: back_of_hand(s) for s in ("l", "r")}
print("[soldier] Handruecken", {k: tuple(round(c, 2) for c in v) for k, v in BOH.items()})
for b in eb:
    n = b.name
    if n == "Root":
        continue
    side = n[-1] if n[-2:] in ("_l", "_r") else ""
    if n.startswith(("hand_", "index", "middle", "ring", "pinky", "thumb")):
        b.align_roll(BOH[side])
    elif n.startswith(("foot_", "ball_")):
        b.align_roll(UP)
    else:
        b.align_roll(FRONT)
bpy.ops.object.mode_set(mode="OBJECT")
for o in [body] + list(parts.values()):
    for g in o.vertex_groups:
        if g.name in REN:
            g.name = REN[g.name]
for b in rig.data.bones:
    if b.name in REN:
        b.name = REN[b.name]
for o in [body] + list(parts.values()):
    for g in o.vertex_groups:
        if g.name in REN:
            g.name = REN[g.name]

# Helm starr an "Head" (Gewichte ersetzen)
for g in list(helmet.vertex_groups):
    helmet.vertex_groups.remove(g)
hg = helmet.vertex_groups.new(name="Head")
hg.add(list(range(len(helmet.data.vertices))), 1.0, "REPLACE")

# ---------------------------------------------------------------- zusammenfuegen
allm = [body] + [o for k, o in parts.items() if k != "helmet"]
activate(body)
for o in allm[1:]:
    o.select_set(True)
bpy.ops.object.join()
body = bpy.context.object
body.name = "Body"
helmet.name = "Helmet"
for o in (body, helmet):
    if not any(m.type == "ARMATURE" for m in o.modifiers):
        m = o.modifiers.new("Armature", "ARMATURE")
        m.object = rig
    o.parent = rig
print("[soldier] Dreiecke Body", ntri(body), "Helm", ntri(helmet), "Summe", ntri(body) + ntri(helmet))
for b in ("Hips", "Chest", "Neck", "Head", "UpperArm.L", "Wrist.R", "UpperLeg.L", "Foot.L"):
    bb = rig.data.bones[b]
    print("[soldier] Knochen", b, tuple(round(c, 4) for c in (rig.matrix_world @ bb.head_local)),
          "z", tuple(round(c, 2) for c in (rig.matrix_world.to_3x3() @ bb.matrix_local.to_3x3() @ Vector((0, 0, 1)))))
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
print("[soldier] Hoehe", round(max(zs), 3))

if OUT_BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
for x in bpy.context.selected_objects:
    x.select_set(False)
bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=False, export_apply=False,
                          export_skins=True, export_animations=False, export_morph=False, export_yup=True,
                          export_image_format="NONE", export_texcoords=True, export_normals=True,
                          export_tangents=False, export_attributes=False)
print("[soldier] exportiert", OUT_GLB)
