extends Node
## Globaler Event-Bus. Nur Signale, keine Logik.

signal player_damaged(amount: float, source: Node)
signal player_died
signal player_respawned
signal enemy_damaged(enemy: Node, amount: float)
signal enemy_killed(enemy: Node)
signal explosion(position: Vector3, radius: float, strength: float)
signal weapon_fired(weapon: Node)
signal checkpoint_reached(id: String)
signal level_completed

# --- Story (Runde 3) ---
## Funkspruch als Untertitel (+ Funkrauschen). speaker z. B. "Hauptmann Weber", duration in s (0 = automatisch nach Textlaenge).
signal story_radio(speaker: String, text: String, duration: float)
## Aktuelles Missionsziel oben links (leerer Text = ausblenden).
signal story_objective(text: String)
## Kurzer Kino-Moment: Letterbox-Balken ein/aus (Set-Pieces).
signal story_cinematic(active: bool)
