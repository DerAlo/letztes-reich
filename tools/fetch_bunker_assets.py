# Laedt CC0-Texturen fuer den Bunker (Letztes Gefecht) nach assets/environment/bunker/textures/.
# Aufruf: python -I tools/fetch_bunker_assets.py <zielordner>   (z. B. assets/environment/bunker/textures)
# Poly Haven (1K): <ziel>/<id>/{diffuse,normal,arm}.jpg
# ambientCG (1K-JPG, Poly Haven hat kein Papier): <ziel>/<name>/{diffuse,normal,rough}.jpg
import io, json, os, sys, urllib.request, zipfile

POLYHAVEN = {"brown_leather": "brown_leather", "metal_plate": "metal_plate",
             # Realismus-Durchgang Lagezentrum/Technik: Schalungsbeton, gruen gestrichener Sockel, Estrich mit Bodenfarbe
             "concrete_wall_004": "concrete_wall_004", "painted_concrete": "painted_concrete",
             "concrete_floor_painted": "concrete_floor_painted"}
AMBIENTCG = {"paper_creased": "Paper003"}
UA = {"User-Agent": "asset-fetch/1.0"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=90) as r:
        return r.read()


def save_bytes(data, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    print("  ", path, len(data))


def main():
    root = os.path.abspath(sys.argv[1])
    for local, a in POLYHAVEN.items():
        info = json.loads(get("https://api.polyhaven.com/info/" + a))
        print(a, "authors", list(info.get("authors", {}).keys()), "license CC0")
        fj = json.loads(get("https://api.polyhaven.com/files/" + a))
        d = os.path.join(root, local)
        for key, name in (("Diffuse", "diffuse.jpg"), ("nor_gl", "normal.jpg"), ("arm", "arm.jpg")):
            p = os.path.join(d, name)
            if not (os.path.exists(p) and os.path.getsize(p) > 0):
                save_bytes(get(fj[key]["1k"]["jpg"]["url"]), p)
    for local, a in AMBIENTCG.items():
        d = os.path.join(root, local)
        if os.path.exists(os.path.join(d, "diffuse.jpg")):
            continue
        z = zipfile.ZipFile(io.BytesIO(get("https://ambientcg.com/get?file=%s_1K-JPG.zip" % a)))
        print(a, "ambientCG CC0", z.namelist())
        for suffix, name in (("_Color.jpg", "diffuse.jpg"), ("_NormalGL.jpg", "normal.jpg"), ("_Roughness.jpg", "rough.jpg")):
            for n in z.namelist():
                if n.endswith(suffix) and "/" not in n and ".." not in n:
                    save_bytes(z.read(n), os.path.join(d, name))


if __name__ == "__main__":
    main()
