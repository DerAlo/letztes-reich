# Laedt CC0-Assets von Poly Haven (1K) fuer den Realismus-Durchgang (Technikraeume, Truemmer, Daecher).
# Aufruf: python -I tools/fetch_realism_assets.py <zielordner>   (z. B. assets/environment/realism)
# Texturen -> <ziel>/textures/<id>/{diffuse,normal,arm}.jpg ; Modelle -> <ziel>/models/<id>/<id>.gltf (+bin, Texturen)
import json, os, sys, urllib.request

TEXTURES = ["brick_gravel", "concrete_debris", "square_tiled_wall"]
MODELS = [
    # Versorgungskeller / Fernmeldestelle / Truemmer (Realismus-Durchgang curfew, kanalisation, ep_lena)
    # (utility_box_01, Barrel_01, cement_bag liegen schon unter river/models, painted_plaster_wall unter facade/textures)
    "steel_frame_shelves_02", "metal_tool_chest",
]
UA = {"User-Agent": "asset-fetch/1.0"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read()


def save(url, path):
    if os.path.exists(path) and os.path.getsize(path) > 0:
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = get(url)
    with open(path, "wb") as f:
        f.write(data)
    print("  ", path, len(data))


def main():
    root = os.path.abspath(sys.argv[1])
    for a in TEXTURES + MODELS:
        info = json.loads(get("https://api.polyhaven.com/info/" + a))
        print(a, "type", info.get("type"), "authors", ascii(list(info.get("authors", {}).keys())), "license CC0")
    for t in TEXTURES:
        fj = json.loads(get("https://api.polyhaven.com/files/" + t))
        d = os.path.join(root, "textures", t)
        for key, name in (("Diffuse", "diffuse.jpg"), ("nor_gl", "normal.jpg"), ("arm", "arm.jpg")):
            if key not in fj:
                print(t, "ohne", key)
                continue
            save(fj[key]["1k"]["jpg"]["url"], os.path.join(d, name))
    for m in MODELS:
        fj = json.loads(get("https://api.polyhaven.com/files/" + m))
        if "gltf" not in fj:
            print(m, "kein glTF, Formate:", list(fj.keys()))
            continue
        g = fj["gltf"]["1k"]["gltf"]
        d = os.path.join(root, "models", m)
        save(g["url"], os.path.join(d, m + ".gltf"))
        for rel, inc in g.get("include", {}).items():
            rel = rel.replace("\\", "/")
            if ".." in rel.split("/") or rel.startswith("/"):
                continue
            save(inc["url"], os.path.join(d, *rel.split("/")))


if __name__ == "__main__":
    main()
