# Laedt CC0-Assets von Poly Haven (1K) fuer die Innenraeume (Kanzleramt, Bunker) in ein eigenes Verzeichnis.
# Aufruf: python -I tools/fetch_interior_assets.py <zielordner>   (z. B. assets/environment/interior)
# Texturen -> <ziel>/textures/<id>/{diffuse,normal,arm}.jpg ; Modelle -> <ziel>/models/<id>/<id>.gltf (+bin, Texturen)
import json, os, sys, urllib.request

TEXTURES = ["american_walnut_veneer", "poly_wool_herringbone",
            # Kanzleramt Realismus-Durchgang: Rauputzdecke, heller Wandputz, Kassetten-Holzpaneele
            "ceiling_interior", "white_plaster_02", "wooden_panels"]
MODELS = [
    # Kanzleramt
    "fancy_picture_frame_01", "fancy_picture_frame_02", "hanging_picture_frame_02",
    "Shelf_01", "drawer_cabinet", "potted_plant_02",
    "office_notepads", "binder_notebook", "stationery_supplies", "marble_bust_01", "fire_alarm",
    # Bunker (Zuendraum) + beide
    "korean_fire_extinguisher_01", "steel_frame_shelves_01", "industrial_caged_sconce", "metal_toolbox",
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
