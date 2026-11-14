extends StaticBody3D
## Zerstoerbare Deckung (Runde 7, Welle 4, systeme-c).
##
## Ein Deckungsobjekt besteht aus wenigen "Bloecken" (Planken, Ziegelfelder, Sandsack-Gruppen, Kisten,
## eine Scheibe). Jeder Block hat eigene Trefferpunkte, ein eigenes Mesh und eine eigene CollisionShape
## im selben StaticBody3D. Treffer beschaedigen den getroffenen Block (Stufe: heil -> angeschlagen ->
## weg); weggeschossene Bloecke sind echte Loecher (Kollision aus). Faellt zu viel weg, stuerzt der Rest
## ein (Staub, ein paar Truemmer-RigidBodies mit Lebensdauer und Obergrenze, flacher Schutt ohne Kollision).
##
## Arten (KINDS):  "crate" (Kistenstapel), "planks" (Bretterwand), "sandbag" (Sandsack-Stellung),
##                 "brick" (Ziegelmauer-Segment), "glass" (Glasscheibe im Rahmen)
##
## Schadenswege (ohne Aenderung an weapon.gd):
##  - Kugeln (Spieler-Waffe, IFV-MG, ...): take_damage() ueber den Collider. Die Waffe ruft vorher
##    set_shot_dir() auf (Panzer-Schnittstelle) -> exakte Schussrichtung fuer den Durchschuss.
##  - Explosionen: Combat.explode -> Gruppe "damageable", Combat.explosion_active = true. Der Schaden wird
##    nach Abstand auf die Bloecke verteilt.
##  - Gegner-Fehlschuesse: enemy.gd ruft take_bullet() (additiver Hook).
## is_alive() ist nur waehrend einer Explosion true: so verteilt Combat Flaechenschaden, aber die
## Spieler-Waffe zeigt beim Beschuss von Deckung keinen Treffer-Marker.
##
## Durchschuss: Holz/Glas lassen Kugeln mit reduziertem Schaden durch (Folge-Ray hinter dem Treffer,
## max. 2 Durchschuesse), Sandsack/Mauer nicht.
##
## Navmesh: Die Level backen das Objekt beim Start als Hindernis (Layer 1). Beim Zerstoeren wird nur die
## Kollision entfernt; das Navmesh bleibt unveraendert -> kein neues Hindernis, keine Falle fuer Bots.
## Deckungspunkte (Gruppe "cover_point") vor/hinter dem Objekt verschwinden beim Einsturz; Gegner, die
## sie besetzen, bekommen on_cover_lost() (enemy.gd) und suchen neue Deckung.
##
## Ruhezustand: kein _process/_physics_process, keine Timer. Kosten nur bei Treffern.
##
## Nutzung:
##   const Destructible := preload("res://game/systems/destructible.gd")
##   var d := Destructible.spawn(world, "brick", Vector3(3, 0, -40), 90.0, {"width": 3.0})
##   d.destroyed.connect(...)

signal damaged(block: int, stage: int)   ## stage: 1 = angeschlagen, 2 = weg
signal destroyed                         ## alles weg (Einsturz oder letzter Block)

const PH := preload("res://game/levels/ph_props.gd")
const LAYER_WORLD := 1
const HIT_MASK := 1 | 2 | 4               ## wie weapon.gd: world + player + enemy
const DEBRIS_LAYER := 8
const MAX_DEBRIS := 24                    ## Truemmer-RigidBodies aller Objekte zusammen
const DEBRIS_LIFE := 5.0
const MAX_PEN_DEPTH := 2
const ENEMY_SHOT_MULT := 3.0              ## Gegner-damage_per_hit ist auf 100 Spieler-HP skaliert
const HIT_SFX_GAP_MS := 90

## Werte pro Art. hp = Trefferpunkte pro Block, bullet/expl = Schadensfaktor fuer Kugeln/Explosionen,
## pen = Schadensanteil, der durchschlaegt (0 = kein Durchschuss), collapse = Anteil verlorener Bloecke,
## ab dem der Rest einstuerzt (1.0 = nie), support = Bloecke ohne Unterbau fallen mit,
## hole_cap = Anteil der Bloecke, den Kugeln hoechstens herausschiessen koennen (Rest nur per Explosion).
const KINDS := {
	"crate":   {"hp": 160.0, "bullet": 1.0,  "expl": 3.0,  "pen": 0.55, "collapse": 1.0,  "support": true,
				"surface": "wood", "height": 1.45, "depth": 1.0, "width": 1.1},
	"planks":  {"hp": 45.0,  "bullet": 1.0,  "expl": 4.0,  "pen": 0.7,  "collapse": 0.55, "support": false,
				"surface": "wood", "height": 1.7, "depth": 0.1, "width": 2.4},
	"sandbag": {"hp": 90.0,  "bullet": 0.0,  "expl": 1.0,  "pen": 0.0,  "collapse": 1.0,  "support": true,
				"surface": "sand", "height": 1.05, "depth": 0.8, "width": 2.6},
	"brick":   {"hp": 120.0, "bullet": 0.3, "expl": 1.0,  "pen": 0.0,  "collapse": 0.4,  "support": false, "hole_cap": 0.3,
				"surface": "concrete", "height": 2.1, "depth": 0.3, "width": 3.0},
	"glass":   {"hp": 1.0,   "bullet": 1.0,  "expl": 10.0, "pen": 0.9,  "collapse": 1.0,  "support": false,
				"surface": "glass", "height": 2.0, "depth": 0.04, "width": 2.0},
}

static var _debris_live: int = 0
static var _mats: Dictionary = {}
static var _pen_depth: int = 0

@export var kind: String = "crate"
@export var width: float = 0.0          ## 0 = Standard der Art
@export var height: float = 0.0
@export var cover_points: bool = true   ## eigene Deckungspunkte vor/hinter dem Objekt

var _def: Dictionary = {}
var _size := Vector3.ONE
var _centers: Array[Vector3] = []       ## Block-Mittelpunkte (lokal)
var _sizes: Array[Vector3] = []
var _cols: PackedInt32Array = PackedInt32Array()
var _rows: PackedInt32Array = PackedInt32Array()
var _hp: PackedFloat32Array = PackedFloat32Array()
var _visual: Array[Node3D] = []
var _shapes: Array[CollisionShape3D] = []
var _alive_count: int = 0
var _destroyed: bool = false
var _shot_dir := Vector3.ZERO
var _last_sfx_ms: int = 0
var _covers: Array[Marker3D] = []
var _frame: Node3D = null
var _in_blast: bool = false

# ================================================================== Erzeugen

## Bequem: Objekt bauen, unter parent haengen und platzieren. opts: width, height, cover_points.
static func spawn(parent: Node, p_kind: String, pos: Vector3, yaw_deg: float = 0.0, opts: Dictionary = {}) -> StaticBody3D:
	var d: StaticBody3D = (load("res://game/systems/destructible.gd") as GDScript).new()
	d.set("kind", p_kind)
	d.set("width", float(opts.get("width", 0.0)))
	d.set("height", float(opts.get("height", 0.0)))
	d.set("cover_points", bool(opts.get("cover_points", true)))
	d.name = "Destructible_%s_%d" % [p_kind, parent.get_child_count()]
	d.position = pos
	d.rotation_degrees.y = yaw_deg
	parent.add_child(d)
	return d

func _init() -> void:
	collision_layer = LAYER_WORLD
	collision_mask = 0

func _enter_tree() -> void:
	# Bauen schon beim Einhaengen (vor _ready), damit ein direkt folgender Navmesh-Bake die Formen sieht.
	if _def.is_empty():
		_build()

func _ready() -> void:
	add_to_group("damageable")
	add_to_group("destructible")

func _build() -> void:
	if not KINDS.has(kind):
		push_warning("[destructible] unbekannte Art '%s' -> crate" % kind)
		kind = "crate"
	_def = KINDS[kind]
	_size = Vector3(width if width > 0.0 else float(_def["width"]), height if height > 0.0 else float(_def["height"]), float(_def["depth"]))
	set_meta("surface", str(_def["surface"]))
	set_meta("no_fit", true)   # PropCollision nicht anfassen (hat ohnehin ein Skript)
	match kind:
		"crate": _layout_crates()
		"planks": _layout_grid(maxi(int(round(_size.x / 0.4)), 2), 2, 0.012)
		"sandbag": _layout_grid(maxi(int(round(_size.x / 0.9)), 1), 2, 0.0)
		"brick": _layout_grid(maxi(int(round(_size.x / 0.6)), 2), 4, 0.0)
		"glass": _layout_glass()
	for i in _centers.size():
		_hp.append(float(_def["hp"]))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var s := _sizes[i]
		if kind == "glass":
			s.z = 0.08   # duenne Scheibe trotzdem sicher treffbar
		bs.size = s
		cs.shape = bs
		cs.position = _centers[i]
		add_child(cs)
		_shapes.append(cs)
		var v := _make_block_visual(i)
		v.position = _centers[i]
		add_child(v)
		_visual.append(v)
	_alive_count = _centers.size()
	if cover_points and kind != "glass":
		_make_cover_points()

func _add_block(center: Vector3, size: Vector3, col: int, row: int) -> void:
	_centers.append(center)
	_sizes.append(size)
	_cols.append(col)
	_rows.append(row)

func _layout_grid(cols: int, rows: int, gap: float) -> void:
	var bw := _size.x / cols
	var bh := _size.y / rows
	for r in rows:
		for c in cols:
			var x := -_size.x * 0.5 + bw * (c + 0.5)
			_add_block(Vector3(x, bh * (r + 0.5), 0.0), Vector3(bw - gap, bh, _size.z), c, r)

func _layout_crates() -> void:
	# Kistenstapel: grosse Kiste unten, kleinere oben drauf
	var w := _size.x
	var h0 := _size.y * 0.55
	var h1 := _size.y - h0
	_add_block(Vector3(0, h0 * 0.5, 0), Vector3(w, h0, _size.z), 0, 0)
	_add_block(Vector3(w * 0.06, h0 + h1 * 0.5, -0.04), Vector3(w * 0.8, h1, _size.z * 0.85), 0, 1)

func _layout_glass() -> void:
	var sill := 0.12
	_add_block(Vector3(0, sill + (_size.y - sill) * 0.5, 0), Vector3(_size.x - 0.1, _size.y - sill - 0.05, _size.z), 0, 0)
	# Rahmen (nur Optik, keine Kollision): Pfosten, Sockel, Kaempfer
	_frame = Node3D.new()
	add_child(_frame)
	var fm := _mat("frame")
	_box_into(_frame, Vector3(0.06, _size.y, 0.08), Vector3(-_size.x * 0.5 + 0.03, _size.y * 0.5, 0), fm)
	_box_into(_frame, Vector3(0.06, _size.y, 0.08), Vector3(_size.x * 0.5 - 0.03, _size.y * 0.5, 0), fm)
	_box_into(_frame, Vector3(_size.x, sill, 0.1), Vector3(0, sill * 0.5, 0), fm)
	_box_into(_frame, Vector3(_size.x, 0.06, 0.08), Vector3(0, _size.y - 0.03, 0), fm)

# ================================================================== Optik

static func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.roughness = 0.9
	match key:
		"wood":
			m.albedo_color = Color(0.46, 0.33, 0.2)
		"wood_dark":
			m.albedo_color = Color(0.3, 0.21, 0.13)
		"wood_raw":   # frische Splitterkanten
			m.albedo_color = Color(0.68, 0.53, 0.34)
		"crate":
			m.albedo_color = Color(0.36, 0.33, 0.2)
		"crate_dark":
			m.albedo_color = Color(0.22, 0.2, 0.12)
		"sand", "sand_dark":
			# Jute (Poly Haven hessian_230, CC0) wie die Sandsaecke aus ph_props.gd
			m.albedo_texture = load(PH.HESSIAN + "diffuse.jpg")
			m.normal_enabled = true
			m.normal_texture = load(PH.HESSIAN + "normal.jpg")
			m.normal_scale = 1.3
			m.albedo_color = Color(0.86, 0.8, 0.68) if key == "sand" else Color(0.55, 0.5, 0.42)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 3.0
			m.roughness = 0.95
		"brick", "brick_dark":
			m.albedo_texture = load("res://assets/textures/brick_wall_02/diffuse.jpg")
			m.normal_enabled = true
			m.normal_texture = load("res://assets/textures/brick_wall_02/normal.jpg")
			m.albedo_color = Color(1, 1, 1) if key == "brick" else Color(0.55, 0.5, 0.48)
			m.uv1_triplanar = true
			m.uv1_world_triplanar = true
			m.uv1_scale = Vector3.ONE * 0.5
		"glass":
			m.albedo_color = Color(0.62, 0.75, 0.78, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.05
			m.metallic = 0.3
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"frame":
			m.albedo_color = Color(0.16, 0.17, 0.17)
			m.metallic = 0.6
			m.roughness = 0.5
		"rubble":
			m.albedo_texture = load("res://assets/textures/concrete_wall_008/diffuse.jpg")
			m.albedo_color = Color(0.45, 0.4, 0.37)
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 1.2
	_mats[key] = m
	return m

static func _box_into(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

## Block-Optik in lokalem Block-Raum (Ursprung = Blockmitte).
func _make_block_visual(i: int) -> Node3D:
	var root := Node3D.new()
	var s := _sizes[i]
	var h := hash(Vector3i(int(global_position.x * 10.0), _cols[i], _rows[i]))
	var jitter := float(h % 1000) / 1000.0
	match kind:
		"crate":
			_box_into(root, s * 0.98, Vector3.ZERO, _mat("crate"))
			# Kanten-Latten auf Vorder-/Rueckseite + Querlatte
			var lm := _mat("crate_dark")
			for sz: float in [-1.0, 1.0]:
				var z := sz * (s.z * 0.5 + 0.005)
				_box_into(root, Vector3(s.x, 0.08, 0.02), Vector3(0, s.y * 0.5 - 0.04, z), lm)
				_box_into(root, Vector3(s.x, 0.08, 0.02), Vector3(0, -s.y * 0.5 + 0.04, z), lm)
				_box_into(root, Vector3(0.08, s.y, 0.02), Vector3(s.x * 0.5 - 0.04, 0, z), lm)
				_box_into(root, Vector3(0.08, s.y, 0.02), Vector3(-s.x * 0.5 + 0.04, 0, z), lm)
				_box_into(root, Vector3(s.x * 1.1, 0.07, 0.02), Vector3(0, 0, z), lm, Vector3(0, 0, rad_to_deg(atan2(s.y, s.x))))
		"planks":
			var m := _mat("wood") if jitter > 0.3 else _mat("wood_dark")
			_box_into(root, s, Vector3.ZERO, m, Vector3(0, 0, (jitter - 0.5) * 1.5))
			# Querlatte hinten (pro Block, faellt mit dem Brett)
			_box_into(root, Vector3(s.x + 0.01, 0.1, 0.03), Vector3(0, s.y * 0.2 - s.y * 0.1, -s.z * 0.5 - 0.015), _mat("wood_dark"))
		"sandbag":
			# 2 Lagen Saecke pro Block, versetzt, leicht gedreht
			var m := _mat("sand")
			var lay := 2
			var bag_h := s.y / lay
			for l in lay:
				var n := maxi(int(round(s.x / 0.45)), 1)
				for k in n:
					var bx := -s.x * 0.5 + s.x / n * (k + 0.5) + (0.11 if l % 2 == 1 else 0.0) * (1.0 if k < n - 1 else -1.0)
					# gefuellter Jutesack (Kissenform aus ph_props.gd) statt Quader: Laengsseite nach lokal z
					var mi := MeshInstance3D.new()
					mi.mesh = PH.sandbag_mesh()
					mi.material_override = m
					mi.position = Vector3(bx, -s.y * 0.5 + bag_h * (l + 0.5) - bag_h * 0.04, (jitter - 0.5) * 0.06)
					mi.rotation_degrees = Vector3(0, (jitter - 0.5) * 10.0 + k * 3.0, (float(k % 2) - 0.5) * 3.0)
					mi.scale = Vector3(s.x / n * 1.04 / PH.BAG.x, bag_h * 1.08 / PH.BAG.y, s.z * 0.95 / PH.BAG.z)
					root.add_child(mi)
		"brick":
			_box_into(root, s, Vector3.ZERO, _mat("brick"))
		"glass":
			var mi := _box_into(root, Vector3(s.x, s.y, 0.012), Vector3.ZERO, _mat("glass"))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root

## Angeschlagen: dunkler, leicht verschoben/eingedrueckt (keine neuen Nodes ausser bei Holz).
func _show_damaged(i: int) -> void:
	var v := _visual[i]
	match kind:
		"crate":
			for c in v.get_children():
				if c is MeshInstance3D and (c as MeshInstance3D).material_override == _mat("crate"):
					(c as MeshInstance3D).material_override = _mat("crate_dark")
			v.rotation_degrees = Vector3(randf_range(-3, 3), randf_range(-6, 6), randf_range(-3, 3))
			_box_into(v, Vector3(_sizes[i].x * 0.5, 0.05, 0.03), Vector3(randf_range(-0.2, 0.2), _sizes[i].y * 0.25, _sizes[i].z * 0.5 + 0.02), _mat("wood_raw"), Vector3(0, 0, randf_range(-30, 30)))
		"planks":
			v.rotation_degrees.z += randf_range(-6.0, 6.0)
			v.position.z += randf_range(-0.02, 0.02)
			_box_into(v, Vector3(_sizes[i].x * 0.9, 0.04, 0.02), Vector3(0, randf_range(-0.2, 0.2), _sizes[i].z * 0.5 + 0.01), _mat("wood_raw"), Vector3(0, 0, randf_range(-35, 35)))
		"sandbag":
			for c in v.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = _mat("sand_dark")
			v.scale = Vector3(1.0, 0.8, 1.05)
			v.position.y = _centers[i].y - _sizes[i].y * 0.1
		"brick":
			for c in v.get_children():
				if c is MeshInstance3D:
					(c as MeshInstance3D).material_override = _mat("brick_dark")
			v.scale = Vector3(0.94, 0.94, 0.75)
			v.rotation_degrees = Vector3(randf_range(-2, 2), randf_range(-3, 3), randf_range(-3, 3))

# ================================================================== Deckungspunkte

func _make_cover_points() -> void:
	var off := _size.z * 0.5 + 0.85
	var xs: Array[float] = [0.0]
	if _size.x > 2.4:
		xs = [-_size.x * 0.25, _size.x * 0.25]
	for side: float in [-1.0, 1.0]:
		for x in xs:
			var m := Marker3D.new()
			m.position = Vector3(x, 0.0, side * off)
			m.add_to_group("cover_point")
			m.set_meta("destructible", true)
			add_child(m)
			_covers.append(m)

func _drop_cover_points() -> void:
	var enemies := get_tree().get_nodes_in_group("enemy") if is_inside_tree() else []
	for m in _covers:
		if is_instance_valid(m):
			m.remove_from_group("cover_point")
	for m in _covers:
		if not is_instance_valid(m):
			continue
		for e in enemies:
			if is_instance_valid(e) and e.has_method("on_cover_lost"):
				e.call("on_cover_lost", m)
	_covers.clear()
	# Gegner direkt dahinter ohne eigenen Punkt: kurz aufschrecken (neue Deckung bei naechster Entscheidung)
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var lp := to_local((e as Node3D).global_position)
		if absf(lp.x) < _size.x * 0.5 + 1.0 and absf(lp.z) < _size.z * 0.5 + 1.6 and e.has_method("on_cover_lost"):
			e.call("on_cover_lost", self)

# ================================================================== Schaden (Schnittstelle)

## Panzer-Schnittstelle der Waffen: exakte Schussrichtung vor take_damage.
func set_shot_dir(dir: Vector3) -> void:
	_shot_dir = dir

func armor_deflected() -> bool:
	return false

func armor_blocks_blood() -> bool:
	return true

## Nur waehrend Combat.explode "lebendig" (Flaechenschaden ja, Treffer-Marker der Waffe nein).
func is_alive() -> bool:
	return not _destroyed and bool(Combat.get("explosion_active"))

func is_destroyed() -> bool:
	return _destroyed

## 0 = heil, 1 = beschaedigt, 2 = zerstoert
func get_stage() -> int:
	if _destroyed:
		return 2
	for i in _hp.size():
		if _hp[i] < float(_def["hp"]):
			return 1
	return 0

## Anteil verbliebener Bloecke (0..1).
func get_integrity() -> float:
	return float(_alive_count) / maxf(float(_centers.size()), 1.0)

func get_damage_points() -> Array[Vector3]:
	var pts: Array[Vector3] = []
	for i in _centers.size():
		if _hp[i] > 0.0:
			pts.append(to_global(_centers[i]))
	if pts.is_empty():
		pts.append(global_position)
	return pts

func get_collision_rids() -> Array[RID]:
	return [get_rid()]

## Standard-Schadensweg (Kugeln ueber den Collider, Explosionen ueber Combat).
func take_damage(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3) -> void:
	if _destroyed or amount <= 0.0:
		return
	if bool(Combat.get("explosion_active")):
		_blast(amount * float(_def["expl"]), hit_position)
		return
	var dir := _shot_dir
	_shot_dir = Vector3.ZERO
	if dir.length() < 0.5:
		dir = _guess_dir(source, hit_position, hit_normal)
	_bullet(amount, source, hit_position, hit_normal, dir, true)

## Kugel mit bekannter Richtung (z. B. Gegner-Fehlschuss aus enemy.gd). from_enemy: Gegner-Schaden skalieren,
## kein Durchschuss (der Spieler soll hinter Holz nicht von Fehlschuessen erwischt werden).
func take_bullet(amount: float, source: Node, hit_position: Vector3, hit_normal: Vector3, dir: Vector3, from_enemy: bool = true) -> void:
	if _destroyed or amount <= 0.0:
		return
	_bullet(amount * (ENEMY_SHOT_MULT if from_enemy else 1.0), source, hit_position, hit_normal, dir, not from_enemy)

## Sofort einstuerzen lassen (Skript-Events).
func destroy() -> void:
	if not _destroyed:
		_collapse()

# ================================================================== Schaden (intern)

func _guess_dir(source: Node, hit: Vector3, normal: Vector3) -> Vector3:
	var from := Vector3.INF
	if source != null and is_instance_valid(source):
		if source.is_in_group("player"):
			var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
			if cam != null:
				from = cam.global_position
		if from == Vector3.INF and source is Node3D:
			from = (source as Node3D).global_position + Vector3.UP * 1.5
	if from != Vector3.INF and from.distance_to(hit) > 0.2:
		return (hit - from).normalized()
	return -normal.normalized() if normal.length() > 0.01 else Vector3.FORWARD

func _block_at(world_pos: Vector3) -> int:
	var lp := to_local(world_pos)
	var best := -1
	var best_d := INF
	for i in _centers.size():
		if _hp[i] <= 0.0:
			continue
		var c := _centers[i]
		var s := _sizes[i]
		var dx := maxf(absf(lp.x - c.x) - s.x * 0.5, 0.0)
		var dy := maxf(absf(lp.y - c.y) - s.y * 0.5, 0.0)
		var dz := maxf(absf(lp.z - c.z) - s.z * 0.5, 0.0)
		var d := dx * dx + dy * dy + dz * dz
		if d < best_d:
			best_d = d
			best = i
	return best

func _bullet(amount: float, source: Node, hit: Vector3, normal: Vector3, dir: Vector3, allow_pen: bool) -> void:
	var surface := str(_def["surface"])
	var dmg := amount * float(_def["bullet"])
	if kind != "glass":
		VFX.spawn_impact(hit, normal, surface)
		_hit_sfx(hit)
	var blk := _block_at(hit)
	if blk >= 0 and dmg > 0.0:
		_damage_block(blk, dmg, normal)
	var pen := float(_def["pen"])
	if allow_pen and pen > 0.0 and _pen_depth < MAX_PEN_DEPTH:
		_penetrate(hit, dir, amount * pen, source)

func _hit_sfx(at: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_sfx_ms < HIT_SFX_GAP_MS:
		return
	_last_sfx_ms = now
	match kind:
		"crate", "planks":
			_sfx("destruct_wood_hit", at, -4.0, randf_range(0.85, 1.15))
		"sandbag":
			_sfx("destruct_sand_burst", at, -14.0, randf_range(1.3, 1.6))

func _sfx(sfx_name: String, at: Vector3, vol: float = 0.0, pitch: float = 1.0) -> void:
	if VFX.audio != null and is_inside_tree():
		VFX.audio.call("play_3d", sfx_name, at, vol, 10.0, 140.0, pitch)

## Explosionsschaden auf die Bloecke verteilen (naher Block voll, weiter weg weniger).
func _blast(amount: float, at: Vector3) -> void:
	var spread := 1.6 + amount / 120.0
	var lost_before := _alive_count
	_in_blast = true
	for i in _centers.size():
		if _hp[i] <= 0.0:
			continue
		var d := to_global(_centers[i]).distance_to(at)
		var f := clampf(1.0 - d / spread, 0.0, 1.0)
		if f <= 0.0:
			continue
		var n := (to_global(_centers[i]) - at).normalized()
		_damage_block(i, amount * (0.35 + 0.65 * f), -n)
		if _destroyed:
			break
	_in_blast = false
	if not _destroyed and lost_before != _alive_count:
		VFX.spawn_dust_cloud(at, 1.6 + amount / 160.0)

func _damage_block(i: int, dmg: float, normal: Vector3) -> void:
	if _hp[i] <= 0.0 or _destroyed:
		return
	var max_hp := float(_def["hp"])
	var before := _hp[i]
	_hp[i] = before - dmg
	if _hp[i] <= 0.0 and not _in_blast and (1.0 - float(_alive_count - 1) / float(_centers.size())) > float(_def.get("hole_cap", 1.0)):
		_hp[i] = minf(before, 1.0)   # Kugeln reissen nur Loecher; der Einsturz braucht eine Explosion
	if _hp[i] <= 0.0:
		_break_block(i, normal)
		return
	if before >= max_hp * 0.5 and _hp[i] < max_hp * 0.5:
		_show_damaged(i)
		damaged.emit(i, 1)

func _break_block(i: int, normal: Vector3) -> void:
	_hp[i] = 0.0
	_alive_count -= 1
	var center := to_global(_centers[i])
	_visual[i].visible = false
	_shapes[i].set_deferred("disabled", true)
	damaged.emit(i, 2)
	match kind:
		"glass":
			_sfx("destruct_glass", center, 2.0, randf_range(0.9, 1.1))
			_shards(center)
		"crate", "planks":
			_sfx("destruct_wood_break", center, 0.0, randf_range(0.9, 1.1))
			VFX.spawn_impact(center, normal, "wood")
			_debris(center, _sizes[i] * 0.45, 2, "wood_raw")
		"sandbag":
			_sfx("destruct_sand_burst", center, -2.0, randf_range(0.9, 1.1))
			VFX.spawn_dust_cloud(center, 1.2)
			_debris(center, Vector3(0.4, 0.15, 0.3), 1, "sand_dark")
		"brick":
			_sfx("destruct_brick_crumble", center, -2.0, randf_range(0.9, 1.15))
			VFX.spawn_impact(center, normal, "concrete")
			_debris(center, _sizes[i] * 0.4, 2, "brick")
	# ohne Unterbau faellt, was drauf liegt (Kisten, Sandsaecke)
	if bool(_def["support"]):
		for j in _centers.size():
			if _hp[j] > 0.0 and _cols[j] == _cols[i] and _rows[j] == _rows[i] + 1:
				_break_block(j, normal)
	if _alive_count <= 0:
		_finish()
		return
	var lost := 1.0 - get_integrity()
	if lost >= float(_def["collapse"]) and float(_def["collapse"]) < 1.0:
		_collapse()

## Rest stuerzt ein: alle Bloecke weg, grosse Staubwolke, Schutt.
func _collapse() -> void:
	if _destroyed:
		return
	var c := to_global(Vector3(0, _size.y * 0.4, 0))
	var n := 0
	for i in _centers.size():
		if _hp[i] > 0.0:
			_hp[i] = 0.0
			_visual[i].visible = false
			_shapes[i].set_deferred("disabled", true)
			if n < 4:
				_debris(to_global(_centers[i]), _sizes[i] * 0.5, 1, "brick" if kind == "brick" else ("sand_dark" if kind == "sandbag" else "wood_raw"))
			n += 1
	_alive_count = 0
	VFX.spawn_dust_cloud(c, 2.0 + _size.x * 0.5)
	_sfx("destruct_collapse" if kind == "brick" or kind == "sandbag" else "destruct_wood_break", c, 3.0, randf_range(0.9, 1.05))
	_finish()

func _finish() -> void:
	if _destroyed:
		return
	_destroyed = true
	remove_from_group("damageable")
	_rubble()
	_drop_cover_points()
	destroyed.emit()

## Flacher Schutt ohne Kollision (kein Hindernis, Navmesh bleibt gueltig).
func _rubble() -> void:
	if kind == "glass":
		return
	var m := _mat("rubble")
	match kind:
		"crate", "planks": m = _mat("wood_dark")
		"sandbag": m = _mat("sand_dark")
		"brick": m = _mat("brick_dark")
	var pile := Node3D.new()
	pile.name = "Rubble"
	add_child(pile)
	var n := clampi(int(_size.x * 3.0), 3, 9)
	for k in n:
		var s := Vector3(randf_range(0.25, 0.6), randf_range(0.05, 0.16), randf_range(0.2, 0.45))
		var mi := _box_into(pile, s, Vector3(randf_range(-_size.x * 0.5, _size.x * 0.5), s.y * 0.5, randf_range(-0.5, 0.5)), m,
			Vector3(randf_range(-8, 8), randf_range(0, 180), randf_range(-8, 8)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ================================================================== Durchschuss

func _penetrate(hit: Vector3, dir: Vector3, dmg: float, source: Node) -> void:
	if not is_inside_tree() or dir.length() < 0.5:
		return
	var excl: Array[RID] = [get_rid()]
	if source is CollisionObject3D:
		excl.append((source as CollisionObject3D).get_rid())
	var from := hit + dir * 0.02
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 120.0, HIT_MASK, excl)
	q.collide_with_areas = true
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return
	var col: Object = res["collider"]
	var pos: Vector3 = res["position"]
	var nrm: Vector3 = res["normal"]
	var target := _find_damageable(col, source)
	if target == null:
		var surface := "concrete"
		if col is Node:
			surface = str((col as Node).get_meta("surface", "concrete"))
		VFX.spawn_impact(pos, nrm, surface)
		return
	_pen_depth += 1
	if target.has_method("take_bullet") and target.get_script() == get_script():
		target.call("take_bullet", dmg, source, pos, nrm, dir, false)
	else:
		var was_alive: bool = (not target.has_method("is_alive")) or bool(target.call("is_alive"))
		if target.has_method("set_shot_dir"):
			target.call("set_shot_dir", dir)
		target.call("take_damage", dmg, source, pos, nrm)
		var is_enemy := target.is_in_group("enemy") or (target.has_method("get_enemy") and target.call("get_enemy") is Node and (target.call("get_enemy") as Node).is_in_group("enemy"))
		if is_enemy:
			VFX.spawn_blood(pos, nrm, dir)
			if was_alive and source != null and is_instance_valid(source) and source.has_method("_on_hit_confirmed"):
				var killed: bool = target.has_method("is_alive") and not bool(target.call("is_alive"))
				source.call("_on_hit_confirmed", killed, false)
	_pen_depth -= 1

static func _find_damageable(n: Object, source: Node) -> Node:
	var node := n as Node
	var depth := 0
	while node != null and depth < 6:
		if node.has_method("take_damage") and node != source:
			return node
		node = node.get_parent()
		depth += 1
	return null

# ================================================================== Truemmer

func _debris(at: Vector3, max_size: Vector3, count: int, mat_key: String) -> void:
	for k in count:
		if _debris_live >= MAX_DEBRIS or not is_inside_tree():
			return
		var rb := RigidBody3D.new()
		rb.collision_layer = DEBRIS_LAYER
		rb.collision_mask = LAYER_WORLD
		var s := Vector3(randf_range(0.4, 1.0) * max_size.x, randf_range(0.4, 1.0) * max_size.y, randf_range(0.4, 1.0) * max_size.z)
		s = s.clamp(Vector3.ONE * 0.06, Vector3.ONE * 0.6)
		rb.mass = clampf(s.x * s.y * s.z * 400.0, 0.5, 30.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = s
		cs.shape = bs
		rb.add_child(cs)
		var mi := _box_into(rb, s, Vector3.ZERO, _mat(mat_key))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not VFX.add_debris(rb):
			return
		_debris_live += 1
		rb.global_position = at + Vector3(randf_range(-0.2, 0.2), randf_range(0.0, 0.2), randf_range(-0.2, 0.2))
		rb.linear_velocity = Vector3(randf_range(-2.5, 2.5), randf_range(0.5, 3.0), randf_range(-2.5, 2.5))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
		rb.tree_exited.connect(func() -> void: _debris_live = maxi(_debris_live - 1, 0))
		VFX.schedule_free(rb, DEBRIS_LIFE)

## Glassplitter: ein paar kleine flache Scherben (zaehlen gegen dieselbe Obergrenze).
func _shards(at: Vector3) -> void:
	VFX.spawn_dust_cloud(at, 0.6)
	for k in 5:
		if _debris_live >= MAX_DEBRIS or not is_inside_tree():
			return
		var rb := RigidBody3D.new()
		rb.collision_layer = DEBRIS_LAYER
		rb.collision_mask = LAYER_WORLD
		rb.mass = 0.3
		var s := Vector3(randf_range(0.08, 0.3), randf_range(0.08, 0.35), 0.01)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(s.x, s.y, 0.03)
		cs.shape = bs
		rb.add_child(cs)
		var mi := _box_into(rb, s, Vector3.ZERO, _mat("glass"))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not VFX.add_debris(rb):
			return
		_debris_live += 1
		rb.global_position = at + global_basis * Vector3(randf_range(-_size.x * 0.4, _size.x * 0.4), randf_range(-0.6, 0.6), 0.0)
		rb.linear_velocity = global_basis * Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.5), randf_range(-2.5, 2.5))
		rb.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
		rb.tree_exited.connect(func() -> void: _debris_live = maxi(_debris_live - 1, 0))
		VFX.schedule_free(rb, 3.0)
