extends RefCounted
## Gemeinsamer Bake-Schritt fuer die Fortbewegungs-Schleifen der Soldaten-Rigs (bake_soldier_mh/op.gd):
## "Sync-Gruppe" wie in AAA-Engines, damit sich gemischte Lauf-Clips nicht gegenseitig die Beine verheddern.
## - natuerliche Geschwindigkeit (Vektor im Rig-Raum) aus dem Standbein bzw. der Wurzel-Drift messen,
## - Clip zyklisch so verschieben, dass der LINKE Fuss bei t=0 aufsetzt (gleiche Phase in allen Clips),
## - auf eine gemeinsame Zykluslaenge CYCLE umtakten (die Kadenz stellt die Laufzeit per TimeScale wieder her).
## Vorher liefen z. B. run_fwd (0.89 s) und sprint (1.18 s) mit eigener Phase gegeneinander -> bei 3 m/s
## (Lena) schoben sich die Schrittzyklen auseinander: Fuesse kreuzten, schleiften, "stolperten".

const CYCLE := 0.8
## Anteil der rechnerischen Hueftanhebung beim Schrittlaengen-Warp (1 = Beinstreckung exakt wie im Original)
const HIP_LIFT := 0.8

## rec: je Fuss Liste [Bodenabstand, x, z] pro Frame (Frames 0..N, N = Schleifenende = Anfang).
## drift_v: Wurzel-Geschwindigkeit des Quell-Clips (Rig-Raum, m/s) oder ZERO (Clip am Platz).
static func sync_loop(a: Animation, rec: Array, fps: float, drift_v: Vector2) -> Dictionary:
	var vel := drift_v
	if OS.get_cmdline_user_args().has("--dump"):
		for fi in rec[0].size():
			print("    f%02d L %.3f x %.3f z %.3f | R %.3f x %.3f z %.3f" % [fi, rec[0][fi][0], rec[0][fi][1], rec[0][fi][2], rec[1][fi][0], rec[1][fi][1], rec[1][fi][2]])
	if vel.length() < 0.05:
		vel = stance_vel(rec, fps)
	# Aufsetzen links: erster Frame unter (min + 2 cm) nach einem Frame darueber (zyklisch)
	var l: Array = rec[0]
	var n := l.size() - 1   # letzter Frame == erster
	var mn := 99.0
	var fmin := 0
	for fi in n:
		if float(l[fi][0]) < mn:
			mn = l[fi][0]
			fmin = fi
	var land := fmin
	var thr := mn + 0.02
	for fi in n:
		var prev := (fi - 1 + n) % n
		if float(l[fi][0]) < thr and float(l[prev][0]) >= thr:
			land = fi
			break
	var t0 := minf(land / fps, a.length)
	var b := Animation.new()
	b.length = CYCLE
	b.loop_mode = Animation.LOOP_LINEAR
	var len0 := a.length
	var steps := maxi(n, 8)
	for tr in a.get_track_count():
		var typ := a.track_get_type(tr)
		var nt := b.add_track(typ)
		b.track_set_path(nt, a.track_get_path(tr))
		for i in steps + 1:
			var u := float(i) / steps
			var ts := fmod(t0 + u * len0, len0)
			if i == steps:
				ts = t0   # exakt gleicher Wert wie bei u=0 (nahtlose Schleife)
			match typ:
				Animation.TYPE_ROTATION_3D:
					b.rotation_track_insert_key(nt, u * CYCLE, a.rotation_track_interpolate(tr, ts))
				Animation.TYPE_POSITION_3D:
					b.position_track_insert_key(nt, u * CYCLE, a.position_track_interpolate(tr, ts))
				Animation.TYPE_SCALE_3D:
					b.scale_track_insert_key(nt, u * CYCLE, a.scale_track_interpolate(tr, ts))
	return {"anim": b, "vel": vel, "stride": vel.length() * len0, "t0": t0, "len": len0}

## Natuerliche Geschwindigkeit eines Clips am Platz (Rig-Raum x, z): Median der Standbein-Gleitgeschwindigkeit.
## rec: je Fuss Liste [Bodenabstand, x, z] pro Frame.
static func stance_vel(rec: Array, fps: float) -> Vector2:
	var vx: Array[float] = []
	var vz: Array[float] = []
	for tol in [0.02, 0.04, 0.07]:
		if vx.size() > 2:
			break
		vx.clear()
		vz.clear()
		for j in 2:
			var mn := 99.0
			for r in rec[j]:
				mn = minf(mn, r[0])
			for fi in range(1, rec[j].size()):
				if rec[j][fi][0] < mn + tol and rec[j][fi - 1][0] < mn + tol:
					vx.append(-(float(rec[j][fi][1]) - float(rec[j][fi - 1][1])) * fps)
					vz.append(-(float(rec[j][fi][2]) - float(rec[j][fi - 1][2])) * fps)
	if vx.size() > 2:
		vx.sort()
		vz.sort()
		return Vector2(vx[vx.size() / 2], vz[vz.size() / 2])
	return Vector2.ZERO

## Schrittlaengen-Warp ("stride warping"): die UAL-Lauf-Clips sind federnde Bounding-Laeufe (Jog: 2,1 Schritte/s,
## Standbein ~5,3 m/s, Sprint: Standbein ~8 m/s). Fuer realistische Kadenz (2,8-3,2 Schritte/s) bei 3-5,5 m/s
## wird der Fussweg relativ zum Hueftgelenk in Laufrichtung (Rig +Z) mit w skaliert und das Bein per
## Zwei-Knochen-IK neu geloest (Knie-Pol = Original-Knie, Fussorientierung bleibt).
## g: globale Knochen-Transformationen eines Frames (wird veraendert); legs: [[Ober, Unter, Fuss], ...].
static func warp_legs(g: Array[Transform3D], parents: PackedInt32Array, order: PackedInt32Array, legs: Array, w: float) -> void:
	if is_equal_approx(w, 1.0):
		return
	var old := g.duplicate()
	var moved := {}
	# Huefte anheben, damit das Bein bei kuerzerem Schritt nicht staerker einknickt (Beinstreckung wie im
	# Original); gewichtet nach dem tieferen Fuss (weiches Minimum, stetig ueber den ganzen Zyklus).
	var ankles: Array[Vector3] = []
	var low := 99.0
	for leg in legs:
		ankles.append(g[leg[2]].origin)
		low = minf(low, g[leg[2]].origin.y)
	var lift := 0.0
	var wsum := 0.0
	for li in legs.size():
		var hp: Vector3 = g[legs[li][0]].origin
		var dy := hp.y - ankles[li].y
		var dz := ankles[li].z - hp.z
		var c := exp(-(ankles[li].y - low) / 0.04)
		lift += c * (sqrt(dy * dy + dz * dz * (1.0 - w * w)) - dy)
		wsum += c
	lift = HIP_LIFT * lift / maxf(wsum, 1e-6)
	for i in g.size():
		if parents[i] >= 0:   # Wurzel bleibt (wird nicht gekeyt), alles darunter hebt sich
			g[i].origin.y += lift
	for li in legs.size():
		var leg: Array = legs[li]
		var ul: int = leg[0]
		var ll: int = leg[1]
		var ft: int = leg[2]
		var h: Vector3 = g[ul].origin
		var k: Vector3 = g[ll].origin
		var a: Vector3 = ankles[li]
		var l1 := h.distance_to(k)
		var l2 := k.distance_to(g[ft].origin)
		var t := a
		t.z = h.z + (a.z - h.z) * w
		var ht := t - h
		var d := clampf(ht.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
		var dir := ht.normalized()
		var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
		var hh := sqrt(maxf(l1 * l1 - along * along, 0.0))
		# Knie-Pol aus der Original-Kniestellung (senkrecht zur Original-Huefte-Knoechel-Linie) plus etwas
		# "Knie nach vorn" (+Z), damit ein fast gestrecktes Bein (Abdruck) nicht zur Gegenseite umklappt
		var d0 := (g[ft].origin - h).normalized()
		var pole := (k - h) - d0 * (k - h).dot(d0) + Vector3(0, 0, 0.03)
		pole = (pole - dir * pole.dot(dir)).normalized()
		var k2 := h + dir * along + pole * hh
		var q1 := Quaternion((k - h).normalized(), (k2 - h).normalized())
		g[ul] = Transform3D(Basis(q1) * g[ul].basis, h)
		var lo_dir := Basis(q1) * (g[ft].origin - k).normalized()
		var a2 := k2 + (t - k2).normalized() * l2
		var q2 := Quaternion(lo_dir, (a2 - k2).normalized())
		g[ll] = Transform3D(Basis(q2) * Basis(q1) * g[ll].basis, k2)
		g[ft] = Transform3D(g[ft].basis, a2)
		moved[ul] = true
		moved[ll] = true
		moved[ft] = true
	for i in order:
		var p := parents[i]
		if p < 0 or moved.has(i) or not moved.has(p):
			continue
		g[i] = g[p] * ((old[p] as Transform3D).affine_inverse() * (old[i] as Transform3D))
		moved[i] = true

## Richtungs-Warp ("orientation warping", gebacken): Unterkoerper samt Fussweg um deg Grad um die Hochachse
## durch die Huefte drehen (+ = nach links, Rig +X) und die Wirbelsaeule (spine, Unterkoerper -> Brust) zu
## gleichen Teilen zurueckdrehen, sodass Brust, Kopf und Arme weiter nach vorn zeigen. Ergibt aus einem sauberen
## Vorwaertslauf einen Schraeglauf mit identischer Fussphase (Sync-Gruppe) und ohne Fussgleiten.
static func yaw_warp(g: Array[Transform3D], parents: PackedInt32Array, order: PackedInt32Array, hips: int, spine: Array, deg: float) -> void:
	if is_zero_approx(deg):
		return
	var th := deg_to_rad(deg)
	var piv: Vector3 = g[hips].origin
	var r := Basis(Vector3.UP, th)
	for i in g.size():
		if parents[i] >= 0:
			g[i] = Transform3D(r * g[i].basis, piv + r * (g[i].origin - piv))
	var share := -th / maxf(spine.size(), 1)
	for sb in spine:
		var sub := {sb: true}
		for i in order:
			if parents[i] >= 0 and sub.has(parents[i]):
				sub[i] = true
		var p2: Vector3 = g[sb].origin
		var r2 := Basis(Vector3.UP, share)
		for i in sub:
			g[i] = Transform3D(r2 * g[i].basis, p2 + r2 * (g[i].origin - p2))

## Kontakt-Toleranz (m ueber dem tiefsten Punkt des Beins) und Ein-/Ausblend-Frames der Fuss-Verriegelung
const LOCK_TOL := 0.05
const LOCK_RAMP := 3

## Fuss-Verriegelung ("foot locking", gebacken) fuer die SWAT-Laeufe (Rueckwaerts-/Seitlauf und die gedrehten
## Rueckwaerts-schraeg-Varianten): im Quell-Clip gleitet das Standbein nicht gleichmaessig mit der
## Clip-Geschwindigkeit mit (Run_Back: rechter Ballen rutscht pro Bodenkontakt ~12 cm vor/zurueck und schwebt
## 1,5 cm hoeher als der linke). Je Bodenkontakt wird der Kontaktpunkt (Ballen oder Knoechel, je nachdem was
## tiefer ist) auf eine Gerade mit -vel gelegt, das schwebende Bein auf die Hoehe des anderen gesenkt und das Bein
## per Zwei-Knochen-IK nachgefuehrt (Fussorientierung bleibt). Zur Laufzeit koppelt TimeScale die Kadenz an
## vel -> das Standbein steht still.
## gs: je Frame globale Knochen-Transformationen (Frames 0..N, N == 0), wird veraendert.
## vel: Rig-Raum-Geschwindigkeit (x, z) wie in der Bake-Meta "loco"; ZERO = aus dem Standbein messen (stance_vel).
## Debug: -- --lockdbg gibt je Bein Kontakt-Segmente und groesste Korrektur aus.
static func lock_feet(gs: Array, parents: PackedInt32Array, order: PackedInt32Array, legs: Array, toes: Array, ground: Array, vel: Vector2, fps: float) -> void:
	var nf := gs.size() - 1
	if nf < 6:
		return
	var hts := [[], []]
	var mns := [99.0, 99.0]
	var rec := [[], []]
	for j in 2:
		for f in nf + 1:
			var g: Array[Transform3D] = gs[f]
			var h: float = g[legs[j][2]].origin.y - ground[j]
			if toes[j] >= 0:
				h = minf(h, g[toes[j]].origin.y - ground[2 + j])
			rec[j].append([h, g[legs[j][2]].origin.x, g[legs[j][2]].origin.z])
			if f < nf:
				hts[j].append(h)
				mns[j] = minf(mns[j], h)
	if vel.length() < 0.05:
		vel = stance_vel(rec, fps)   # wie sync_loop (Clip am Platz)
	var v3 := Vector3(vel.x, 0.0, vel.y)
	var mn_all := minf(mns[0], mns[1])
	for j in 2:
		var ft: int = legs[j][2]
		var tb: int = toes[j] if toes[j] >= 0 else ft
		var corr: Array[Vector3] = []
		var wgt: Array[float] = []
		corr.resize(nf)
		wgt.resize(nf)
		wgt.fill(0.0)
		var c: Array[bool] = []
		for f in nf:
			c.append(hts[j][f] < mns[j] + LOCK_TOL)
		var s0 := c.find(false)
		if s0 < 0:
			continue
		var segs := []
		var cur := []
		for i in nf + 1:
			var f := (s0 + i) % nf
			if i < nf and c[f]:
				cur.append(f)
			elif not cur.is_empty():
				segs.append(cur)
				cur = []
		for seg in segs:
			if seg.size() < 2:
				continue
			var mid: int = seg.size() / 2
			var gm: Array[Transform3D] = gs[seg[mid]]
			var anc_a: Vector3 = gm[ft].origin
			var anc_t: Vector3 = gm[tb].origin
			var dy: float = -(mns[j] - mn_all)
			for off in range(-LOCK_RAMP, seg.size() + LOCK_RAMP):
				var f := posmod(int(seg[0]) + off, nf)
				var dt := float(off - mid) / fps
				var g: Array[Transform3D] = gs[f]
				var ha: float = g[ft].origin.y - ground[j]
				var ht: float = (g[tb].origin.y - ground[2 + j]) if tb != ft else ha
				var wt := clampf(0.5 + (ha - ht) / 0.04, 0.0, 1.0)   # 1 = Ballen ist der Kontaktpunkt
				var da := anc_a - v3 * dt - g[ft].origin
				var dtoe := anc_t - v3 * dt - g[tb].origin
				var d := da.lerp(dtoe, wt)
				d.y = dy
				var w := 1.0
				if off < 0:
					w = smoothstep(0.0, 1.0, 1.0 - float(-off) / (LOCK_RAMP + 1))
				elif off >= seg.size():
					w = smoothstep(0.0, 1.0, 1.0 - float(off - seg.size() + 1) / (LOCK_RAMP + 1))
				if w > wgt[f]:
					wgt[f] = w
					corr[f] = d
		if OS.get_cmdline_user_args().has("--lockdbg"):
			var mx := 0.0
			for f in nf:
				if wgt[f] > 0.0:
					mx = maxf(mx, corr[f].length())
			print("    lock leg %d: segs=%d min=%.3f max_corr=%.3f" % [j, segs.size(), mns[j], mx])
		for f in nf + 1:
			var fi := f % nf
			if wgt[fi] <= 0.0:
				continue
			var g: Array[Transform3D] = gs[f]
			var old := g.duplicate()
			_ik_leg(g, legs[j], g[ft].origin + corr[fi] * wgt[fi])
			var moved := {legs[j][0]: true, legs[j][1]: true, ft: true}
			for i in order:
				var p := parents[i]
				if p < 0 or moved.has(i) or not moved.has(p):
					continue
				g[i] = g[p] * ((old[p] as Transform3D).affine_inverse() * (old[i] as Transform3D))
				moved[i] = true
			gs[f] = g

## Zwei-Knochen-IK: Knoechel des Beins leg [Ober, Unter, Fuss] nach t, Knie-Pol aus der bisherigen Kniestellung,
## Fussorientierung bleibt (Kinder des Fusses fuehrt der Aufrufer nach).
static func _ik_leg(g: Array[Transform3D], leg: Array, t: Vector3) -> void:
	var ul: int = leg[0]
	var ll: int = leg[1]
	var ft: int = leg[2]
	var h: Vector3 = g[ul].origin
	var k: Vector3 = g[ll].origin
	var a: Vector3 = g[ft].origin
	var l1 := h.distance_to(k)
	var l2 := k.distance_to(a)
	var ht := t - h
	var d := clampf(ht.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := ht.normalized()
	var along := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hh := sqrt(maxf(l1 * l1 - along * along, 0.0))
	var d0 := (a - h).normalized()
	var pole := (k - h) - d0 * (k - h).dot(d0)
	pole = pole - dir * pole.dot(dir)
	if pole.length() < 1e-5:
		pole = g[ul].basis.z
		pole = pole - dir * pole.dot(dir)
	pole = pole.normalized()
	var k2 := h + dir * along + pole * hh
	var q1 := Quaternion((k - h).normalized(), (k2 - h).normalized())
	g[ul] = Transform3D(Basis(q1) * g[ul].basis, h)
	var lo_dir := Basis(q1) * (a - k).normalized()
	var a2 := k2 + (t - k2).normalized() * l2
	var q2 := Quaternion(lo_dir, (a2 - k2).normalized())
	g[ll] = Transform3D(Basis(q2) * Basis(q1) * g[ll].basis, k2)
	g[ft] = Transform3D(g[ft].basis, a2)
