extends SceneTree
## Diagnose "Clownschuhe": skinnt die Fuss-Vertices der gebackenen Soldaten-Rigs auf der CPU ueber alle Frames
## aller Animationen und meldet Verzerrungen (Fusslaenge/-hoehe ggue. Ruhepose), Knochen-Scale != 1 und
## welche Knochen die Fuss-Vertices beeinflussen.
##   godot --headless --path . -s res://game/enemies/tools/check_feet.gd

const RIGS := ["res://assets/characters/soldier_mh/soldier_mh_a.scn", "res://assets/characters/soldier_mh/soldier_mh_b.scn",
	"res://assets/characters/soldier_mh/soldier_mh_c.scn", "res://assets/characters/soldier_op/soldier_op.scn",
	"res://assets/characters/soldier/soldier_rig.scn"]

func _find_all(n: Node, cls: String, out: Array) -> void:
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		_find_all(c, cls, out)

func _init() -> void:
	for path in RIGS:
		if not ResourceLoader.exists(path):
			continue
		_check(path)
	quit()

var G: Array[Transform3D] = []
var GR: Array[Transform3D] = []

## Globale Posen selbst berechnen (Skeleton3D aktualisiert ausserhalb des Frames nicht synchron)
func _apply(sk: Skeleton3D, a: Animation, t: float) -> void:
	var n := sk.get_bone_count()
	var loc: Array[Transform3D] = []
	for i in n:
		loc.append(sk.get_bone_rest(i))
	if a != null:
		for tr in a.get_track_count():
			var b := sk.find_bone(String(a.track_get_path(tr).get_concatenated_subnames()))
			if b < 0:
				continue
			var l: Transform3D = loc[b]
			match a.track_get_type(tr):
				Animation.TYPE_ROTATION_3D:
					var sc := l.basis.get_scale()
					l.basis = Basis(a.rotation_track_interpolate(tr, t)) * Basis.from_scale(sc)
				Animation.TYPE_POSITION_3D:
					l.origin = a.position_track_interpolate(tr, t)
				Animation.TYPE_SCALE_3D:
					l.basis = Basis(l.basis.get_rotation_quaternion()) * Basis.from_scale(a.scale_track_interpolate(tr, t))
			loc[b] = l
	G.resize(n)
	var done := PackedByteArray()
	done.resize(n)
	for k in n:
		for i in n:
			if done[i]:
				continue
			var p := sk.get_bone_parent(i)
			if p < 0:
				G[i] = loc[i]
				done[i] = 1
			elif done[p]:
				G[i] = G[p] * loc[i]
				done[i] = 1

func _check(path: String) -> void:
	var rig: Node = (load(path) as PackedScene).instantiate()
	root.add_child(rig)
	var sks := []
	_find_all(rig, "Skeleton3D", sks)
	var sk: Skeleton3D = sks[0]
	var aps := []
	_find_all(rig, "AnimationPlayer", aps)
	var ap: AnimationPlayer = aps[0]
	var mis := []
	_find_all(sk, "MeshInstance3D", mis)
	print("=== %s  bones=%d meshes=%d anims=%d" % [path.get_file(), sk.get_bone_count(), mis.size(), ap.get_animation_list().size()])
	var foot_b := [sk.find_bone("Foot.L"), sk.find_bone("Foot.R")]
	# Fuss-Vertices sammeln: [mesh, surface-verts, bind-xf] nach Seite
	var sets := [[], []]   # je Seite: Liste von [pos, bones(PackedInt32), weights, bindbones(Array)]
	var infl := [{}, {}]
	_apply(sk, null, 0.0)
	GR = G.duplicate()
	for mi: MeshInstance3D in mis:
		if mi.skin == null or mi.mesh == null:
			continue
		var skin := mi.skin
		var bindbone := []
		for j in skin.get_bind_count():
			var bn := String(skin.get_bind_name(j))
			bindbone.append(sk.find_bone(bn) if bn != "" else skin.get_bind_bone(j))
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var arr := am.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bs.is_empty():
				continue
			var per := bs.size() / vs.size()
			for i in vs.size():
				# Ruhepose-Position
				var p := Vector3.ZERO
				var ww := 0.0
				var bl := []
				var wl := []
				var foot_side := -1
				for k in per:
					var w := ws[i * per + k]
					if w <= 0.0:
						continue
					var j := bs[i * per + k]
					var b: int = bindbone[j]
					p += (GR[b] * skin.get_bind_pose(j) * vs[i]) * w
					ww += w
					bl.append(j)
					wl.append(w)
				if ww <= 0.0:
					continue
				p /= ww
				if p.y > 0.16:
					continue
				var side := 0 if p.x > 0.0 else 1
				var e := [p, bl, wl, bindbone, skin, mi.name]
				sets[side].append(e)
				for k in bl.size():
					var bn2 := sk.get_bone_name(bindbone[bl[k]])
					infl[side][bn2] = float(infl[side].get(bn2, 0.0)) + wl[k]
	for side in 2:
		print("  Seite %d: %d Fuss-Vertices, Einfluss: %s" % [side, sets[side].size(), infl[side]])
	# Ruhe-Ausdehnung im Fussraum
	var rest_ext := [_extent(sk, sets[0], foot_b[0]), _extent(sk, sets[1], foot_b[1])]
	print("  Ruhe-Ausdehnung (Fussraum) L=%s R=%s" % [rest_ext[0], rest_ext[1]])
	for an in (ap.get_animation_list() if OS.get_cmdline_user_args().has("--anims") else []):
		var a := ap.get_animation(an)
		var worst := 0.0
		var wt := 0.0
		var wside := 0
		var wext := Vector3.ZERO
		var nscale := 0
		for tr in a.get_track_count():
			if a.track_get_type(tr) == Animation.TYPE_SCALE_3D:
				nscale += 1
		var t := 0.0
		while t <= a.length + 0.001:
			_apply(sk, a, t)
			for side in 2:
				var ex := _extent(sk, sets[side], foot_b[side])
				var r: Vector3 = rest_ext[side]
				var d := maxf(maxf(ex.x / r.x, ex.y / r.y), ex.z / r.z)
				if d > worst:
					worst = d
					wt = t
					wside = side
					wext = ex
			t += 1.0 / 30.0
		var flag := "  <<<" if worst > 1.15 else ""
		print("  %-14s len=%.2f scaleTracks=%d  max Fuss-Ausdehnung x%.2f (Seite %d, t=%.2f, ext=%s)%s" % [an, a.length, nscale, worst, wside, wt, wext, flag])
	_check_lods(sk, mis, ap)
	rig.queue_free()

## LOD-Stufen: Dreiecke im Bein-/Fussbereich, deren Kanten sich in der Animation stark strecken
## (Vertices verschiedener Knochen zu einem Dreieck verbunden).
func _check_lods(sk: Skeleton3D, mis: Array, ap: AnimationPlayer) -> void:
	for mi: MeshInstance3D in mis:
		if mi.skin == null:
			continue
		var skin := mi.skin
		var bindbone := []
		for j in skin.get_bind_count():
			var bn := String(skin.get_bind_name(j))
			bindbone.append(sk.find_bone(bn) if bn != "" else skin.get_bind_bone(j))
		var am := mi.mesh as ArrayMesh
		for s in am.get_surface_count():
			var arr := am.surface_get_arrays(s)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bs: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var ws: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if bs.is_empty():
				continue
			var per := bs.size() / vs.size()
			var lods := [arr[Mesh.ARRAY_INDEX]]
			var sd: Dictionary = RenderingServer.mesh_get_surface(am.get_rid(), s)
			var big := vs.size() > 65535
			for ld in sd.get("lods", []):
				var raw: PackedByteArray = ld["index_data"]
				var li32 := PackedInt32Array()
				if big:
					li32 = raw.to_int32_array()
				else:
					li32.resize(raw.size() / 2)
					for q in li32.size():
						li32[q] = raw.decode_u16(q * 2)
				lods.append(li32)
			# Ruhepositionen
			var rp := PackedVector3Array()
			rp.resize(vs.size())
			for i in vs.size():
				var p := Vector3.ZERO
				var ww := 0.0
				for k in per:
					var w := ws[i * per + k]
					if w > 0.0:
						p += (GR[bindbone[bs[i * per + k]]] * skin.get_bind_pose(bs[i * per + k]) * vs[i]) * w
						ww += w
				rp[i] = p / maxf(ww, 1e-6)
			for li in lods.size():
				var ix: PackedInt32Array = lods[li]
				var worst := 1.0
				var wa := ""
				var wy := 0.0
				var tris := []
				for t in range(0, ix.size(), 3):
					var miny := minf(rp[ix[t]].y, minf(rp[ix[t + 1]].y, rp[ix[t + 2]].y))
					if miny < 0.25:
						tris.append(t)
				for an in ["walk", "run_fwd", "sprint", "run_back", "run_left", "run_right", "crouch_walk"]:
					if not ap.has_animation(an):
						continue
					var a := ap.get_animation(an)
					var tt := 0.0
					while tt <= a.length:
						_apply(sk, a, tt)
						var cache := {}
						for t in tris:
							for e in 3:
								var i0: int = ix[t + e]
								var i1: int = ix[t + (e + 1) % 3]
								var rl := rp[i0].distance_to(rp[i1])
								if rl < 0.004:
									continue
								var p0: Vector3 = _skin_v(i0, rp, bs, ws, per, bindbone, cache)
								var p1: Vector3 = _skin_v(i1, rp, bs, ws, per, bindbone, cache)
								var r := p0.distance_to(p1) / rl
								if r > worst:
									worst = r
									wa = "%s t=%.2f" % [an, tt]
									wy = rp[i0].y
						tt += 2.0 / 30.0
				print("  LOD %d %s/%d: %d Idx, Bein-Dreiecke %d, max Kantenstreckung x%.2f (%s, y=%.2f)" % [li, mi.name, s, ix.size(), tris.size(), worst, wa, wy])

func _skin_v(i: int, rp: PackedVector3Array, bs: PackedInt32Array, ws: PackedFloat32Array, per: int, bindbone: Array, cache: Dictionary) -> Vector3:
	if cache.has(i):
		return cache[i]
	var p := Vector3.ZERO
	var ww := 0.0
	for k in per:
		var w := ws[i * per + k]
		if w > 0.0:
			var b: int = bindbone[bs[i * per + k]]
			p += (G[b] * GR[b].affine_inverse() * rp[i]) * w
			ww += w
	p /= maxf(ww, 1e-6)
	cache[i] = p
	return p

## Ausdehnung der Fuss-Vertices im lokalen Raum des Fussknochens (Bounding-Box-Groesse)
func _extent(sk: Skeleton3D, set: Array, fb: int) -> Vector3:
	var inv := G[fb].affine_inverse()
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := -mn
	for e in set:
		var bl: Array = e[1]
		var wl: Array = e[2]
		var bb: Array = e[3]
		var skin: Skin = e[4]
		var p := Vector3.ZERO
		var ww := 0.0
		# Original-Vertex steht nicht im Eintrag -> aus Ruhepos zurueckrechnen ist teuer; daher e[0] ist Ruhepos
		# im Skelettraum: Skinning-Matrix = global_pose * bind = global_pose * inv(global_rest) (Bind = inv rest)
		for k in bl.size():
			var b: int = bb[bl[k]]
			p += (G[b] * GR[b].affine_inverse() * e[0]) * wl[k]
			ww += wl[k]
		p = inv * (p / ww)
		mn = mn.min(p)
		mx = mx.max(p)
	return mx - mn
