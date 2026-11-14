# Laedt CC0-Vegetations-Assets von Poly Haven (1K) fuer den Vegetations-/Bodenpass in ein eigenes Verzeichnis.
# Aufruf: python -I fetch_vegetation_assets.py <zielordner>
# Modelle -> <ziel>/models/<id>/<id>.gltf (+bin, Texturen). Danach von Hand nach
# assets/environment/vegetation/models/<id>/ uebernehmen (nur geprueft CC0, siehe assets/CREDITS_ASSETS.md).
import json, os, sys, urllib.request

MODELS = [
    "tree_stump_02",          # zweiter Baumstumpf (baltic_night)
    "grass_medium_02",        # Wiesengras-Bueschel
    "dandelion_01",           # Loewenzahn (Blueten-Akzente)
    "weed_plant_02",          # Unkraut (Gleise, Industrie)
    "nettle_plant",           # Brennnessel (Ufer, Brachen)
    "rock_moss_set_02",       # bemooste Steine
    "stone_01",               # Kiesel/Steine (geladen, aber nicht uebernommen: 53k Dreiecke fuer 15 cm)
    "dry_branches_medium_01", # Reisig im Wald
]
UA = {"User-Agent": "asset-fetch/1.0"}


def get(url):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r:
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
    ok = []
    for a in MODELS:
        info = json.loads(get("https://api.polyhaven.com/info/" + a))
        # Poly Haven veroeffentlicht ausschliesslich CC0; das Info-Feld fehlt meist -> Standard CC0
        lic = info.get("license", "CC0") if isinstance(info, dict) else "?"
        authors = ", ".join(info.get("authors", {}).keys()) if isinstance(info, dict) else "?"
        print(a, "type", info.get("type"), "license", lic, "authors", authors)
        if lic.upper() != "CC0":
            print("   -> uebersprungen (keine CC0-Lizenz)")
            continue
        ok.append(a)
    for m in ok:
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
