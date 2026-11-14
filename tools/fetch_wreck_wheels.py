# Laedt die CC0-Modelle "rusted_wheel_rim_01/02" (Poly Haven, 1K glTF) fuer die Fahrzeugwracks in einen eigenen Ordner.
# Aufruf: python -I tools/fetch_wreck_wheels.py <neuer_zielordner>
# Danach <ziel>/models/<id>/ nach assets/props/vehicles_wreck/<id>/ kopieren.
import json, os, sys, urllib.request

MODELS = ["rusted_wheel_rim_01", "rusted_wheel_rim_02"]
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
    for m in MODELS:
        info = json.loads(get("https://api.polyhaven.com/info/" + m))
        print(m, "type", info.get("type"), "authors", list(info.get("authors", {}).keys()), "license CC0")
        fj = json.loads(get("https://api.polyhaven.com/files/" + m))
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
