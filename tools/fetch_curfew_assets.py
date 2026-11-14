# Laedt CC0-Assets von Poly Haven (1K) fuer curfew/hafen in ein eigenes Verzeichnis.
# Aufruf: python -I fetch_polyhaven.py <zielordner>
# Texturen -> <ziel>/textures/<id>/{diffuse,normal,arm}.jpg ; Modelle -> <ziel>/models/<id>/<id>.gltf (+bin, Texturen)
import json, os, sys, urllib.request

TEXTURES = ["long_white_tiles", "concrete_wall_006", "concrete_floor_worn_001"]
MODELS = ["vintage_radio_transceiver", "worn_metal_rack", "television_02", "retro_multimeter", "wall_clock",
          "desk_lamp_arm_01", "metal_stool_01", "ocean_buoy"]
UA = {"User-Agent": "asset-fetch/1.0"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=60) as r:
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
        lic = info.get("license", "CC0") if isinstance(info, dict) else "?"
        print(a, "type", info.get("type"), "license", lic)
    for t in TEXTURES:
        fj = json.loads(get("https://api.polyhaven.com/files/" + t))
        d = os.path.join(root, "textures", t)
        for key, name in (("Diffuse", "diffuse.jpg"), ("nor_gl", "normal.jpg"), ("arm", "arm.jpg")):
            save(fj[key]["1k"]["jpg"]["url"], os.path.join(d, name))
    for m in MODELS:
        fj = json.loads(get("https://api.polyhaven.com/files/" + m))
        g = fj["gltf"]["1k"]["gltf"]
        d = os.path.join(root, "models", m)
        save(g["url"], os.path.join(d, m + ".gltf"))
        for rel, inc in g.get("include", {}).items():
            rel = rel.replace("\\", "/")
            if ".." in rel.split("/"):
                continue
            save(inc["url"], os.path.join(d, *rel.split("/")))


if __name__ == "__main__":
    main()
