"""Duennt eine Sketchfab-glTF-Szene (scene.gltf + scene.bin + textures/) fuer das Spiel aus.

- behaelt nur die Knoten-Teilbaeume mit den angegebenen Namen (--keep, kommagetrennt; leer = alles)
- wirft Knoten weg, deren Name einen der --drop-Teilstrings enthaelt (z. B. LOD1,LOD2,Man_ref)
- schreibt nur die noch benutzten Meshes/Accessoren/BufferViews/Materialien/Texturen/Bilder
- verkleinert Texturen auf --max (Standard 1024, Overrides per --tex muster=groesse)
- speichert Texturen ohne Alphakanal als JPEG (Qualitaet 90), mit Alpha als PNG

Aufruf: python tools/prune_gltf.py <quelle> <ziel> [--keep a,b] [--drop x,y] [--max 1024] [--tex Billboard=512]
"""
import argparse
import json
import os
import shutil
import struct

from PIL import Image


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--keep", default="")
    ap.add_argument("--drop", default="")
    ap.add_argument("--max", type=int, default=1024)
    ap.add_argument("--tex", action="append", default=[])
    a = ap.parse_args()
    g = json.load(open(os.path.join(a.src, "scene.gltf"), encoding="utf-8"))
    binb = open(os.path.join(a.src, "scene.bin"), "rb").read()
    nodes = g["nodes"]
    keep_names = [k for k in a.keep.split(",") if k]
    drops = [d for d in a.drop.split(",") if d]
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get("children", []):
            parent[c] = i

    def dropped(i):
        nm = nodes[i].get("name", "")
        return any(d in nm for d in drops)

    keep = set()

    def take(i):
        if dropped(i):
            return
        keep.add(i)
        for c in nodes[i].get("children", []):
            take(c)

    roots = g["scenes"][g.get("scene", 0)]["nodes"]
    if keep_names:
        for i, n in enumerate(nodes):
            if n.get("name") in keep_names:
                take(i)
                p = parent.get(i)
                while p is not None:
                    keep.add(p)
                    p = parent.get(p)
    else:
        for r in roots:
            take(r)
    order = sorted(keep)
    nmap = {o: k for k, o in enumerate(order)}
    meshes, mmap = [], {}
    new_nodes = []
    for o in order:
        n = dict(nodes[o])
        if "children" in n:
            ch = [nmap[c] for c in n["children"] if c in nmap]
            if ch:
                n["children"] = ch
            else:
                del n["children"]
        if "mesh" in n:
            m = n["mesh"]
            if m not in mmap:
                mmap[m] = len(meshes)
                meshes.append(json.loads(json.dumps(g["meshes"][m])))
            n["mesh"] = mmap[m]
        n.pop("skin", None)
        n.pop("camera", None)
        new_nodes.append(n)
    # Accessoren / Materialien einsammeln
    acc_map, accs = {}, []
    mat_map, mats = {}, []

    def acc(i):
        if i not in acc_map:
            acc_map[i] = len(accs)
            accs.append(dict(g["accessors"][i]))
        return acc_map[i]

    for m in meshes:
        for p in m["primitives"]:
            p["attributes"] = {k: acc(v) for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc(p["indices"])
            if "targets" in p:
                p["targets"] = [{k: acc(v) for k, v in t.items()} for t in p["targets"]]
            if "material" in p:
                mi = p["material"]
                if mi not in mat_map:
                    mat_map[mi] = len(mats)
                    mats.append(json.loads(json.dumps(g["materials"][mi])))
                p["material"] = mat_map[mi]
    # je Accessor ein eigener, dicht gepackter BufferView (Sketchfab legt alle Meshes in gemeinsame Views;
    # ganze Views zu kopieren wuerde die verworfenen Meshes mitschleppen)
    bvs = []
    out = bytearray()
    ncomp = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
    csize = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
    for ac in accs:
        if "sparse" in ac:
            raise SystemExit("sparse accessors nicht unterstuetzt")
        if "bufferView" not in ac:
            continue
        v = g["bufferViews"][ac["bufferView"]]
        esz = ncomp[ac["type"]] * csize[ac["componentType"]]
        stride = v.get("byteStride", esz)
        base = v.get("byteOffset", 0) + ac.get("byteOffset", 0)
        while len(out) % 4:
            out.append(0)
        start = len(out)
        if stride == esz:
            out += binb[base:base + esz * ac["count"]]
        else:
            for k in range(ac["count"]):
                out += binb[base + k * stride:base + k * stride + esz]
        nv = {"buffer": 0, "byteOffset": start, "byteLength": len(out) - start}
        if "target" in v:
            nv["target"] = v["target"]
        ac["bufferView"] = len(bvs)
        ac.pop("byteOffset", None)
        bvs.append(nv)
    # Texturen
    tex_map, texs = {}, []
    img_map, imgs = {}, []

    def tex(i):
        if i not in tex_map:
            t = dict(g["textures"][i])
            si = t.get("source")
            if si is not None:
                if si not in img_map:
                    img_map[si] = len(imgs)
                    imgs.append(dict(g["images"][si]))
                t["source"] = img_map[si]
            tex_map[i] = len(texs)
            texs.append(t)
        return tex_map[i]

    def fix(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k.endswith("Texture") and isinstance(v, dict) and "index" in v:
                    v["index"] = tex(v["index"])
                    fix(v)
                else:
                    fix(v)
        elif isinstance(o, list):
            for v in o:
                fix(v)

    for m in mats:
        fix(m)
    os.makedirs(os.path.join(a.dst, "textures"), exist_ok=True)
    overrides = []
    for t in a.tex:
        pat, sz = t.split("=")
        overrides.append((pat, int(sz)))
    for im in imgs:
        uri = im["uri"]
        src = os.path.join(a.src, uri.replace("%20", " "))
        mx = a.max
        for pat, sz in overrides:
            if pat in uri:
                mx = sz
        img = Image.open(src)
        img.load()
        if max(img.size) > mx:
            f = mx / max(img.size)
            img = img.resize((max(1, round(img.size[0] * f)), max(1, round(img.size[1] * f))), Image.LANCZOS)
        has_alpha = img.mode in ("RGBA", "LA") and img.getchannel("A").getextrema()[0] < 250
        base = os.path.splitext(os.path.basename(uri))[0]
        if has_alpha:
            nuri = "textures/" + base + ".png"
            img.save(os.path.join(a.dst, nuri), optimize=True)
            im["mimeType"] = "image/png"
        else:
            nuri = "textures/" + base + ".jpg"
            img.convert("RGB").save(os.path.join(a.dst, nuri), quality=90)
            im["mimeType"] = "image/jpeg"
        im["uri"] = nuri
    g2 = {k: v for k, v in g.items() if k in ("asset", "extensionsUsed", "extensionsRequired", "samplers")}
    g2["scene"] = 0
    g2["scenes"] = [{"nodes": [nmap[r] for r in roots if r in nmap]}]
    g2["nodes"] = new_nodes
    g2["meshes"] = meshes
    g2["accessors"] = accs
    g2["bufferViews"] = bvs
    g2["buffers"] = [{"byteLength": len(out), "uri": "scene.bin"}]
    g2["materials"] = mats
    if texs:
        g2["textures"] = texs
        g2["images"] = imgs
    open(os.path.join(a.dst, "scene.bin"), "wb").write(out)
    json.dump(g2, open(os.path.join(a.dst, "scene.gltf"), "w", encoding="utf-8"), indent=1)
    lic = os.path.join(a.src, "license.txt")
    if os.path.exists(lic):
        shutil.copy(lic, os.path.join(a.dst, "license.txt"))
    tot = sum(os.path.getsize(os.path.join(r, f)) for r, _, fs in os.walk(a.dst) for f in fs)
    print("%s: %d Knoten, %d Meshes, %d Materialien, %d Bilder, %.1f MB" % (a.dst, len(new_nodes), len(meshes), len(mats), len(imgs), tot / 1e6))


if __name__ == "__main__":
    main()
