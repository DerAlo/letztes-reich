// Fenster- und Tueroeffnungen des Wasserflugzeugs (villa_seaplane.gd) im Rumpf-Objektraum
// (Ursprung = Wasserlinie, Nase -Z). Negativ = innen. Gemeinsam fuer Lack- und Glas-Shader.

float sp_rbox(vec2 p, vec2 c, vec2 hs, float r) {
	vec2 q = abs(p - c) - hs + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Seitenfenster (Pilotentuer, hintere Kabinentuer, kleines Heckfenster) und Windschutzscheibe
float sp_window_sd(vec3 p) {
	float d = 1000.0;
	vec2 zy = vec2(p.z, p.y);
	if (abs(p.x) > 0.3) {
		d = min(d, sp_rbox(zy, vec2(-1.06, 2.35), vec2(0.43, 0.30), 0.07));
		d = min(d, sp_rbox(zy, vec2(0.17, 2.34), vec2(0.43, 0.29), 0.07));
		d = min(d, sp_rbox(zy, vec2(1.10, 2.33), vec2(0.25, 0.21), 0.08));
	}
	if (p.z < -1.5 && p.y > 2.2) {
		float ws = max(max(-2.02 - p.z, p.z + 1.63), 2.43 - p.y);
		ws = max(ws, 0.016 - abs(p.x));
		d = min(d, ws);
	}
	return d;
}

// Hintere Kabinentuer (Kontur, beide Seiten gleich; nur links beweglich)
float sp_door_sd(vec3 p) {
	return sp_rbox(vec2(p.z, p.y), vec2(0.18, 2.04), vec2(0.53, 0.64), 0.06);
}

// Pilotentuer (nur Fuge)
float sp_pilot_door_sd(vec3 p) {
	return sp_rbox(vec2(p.z, p.y), vec2(-1.04, 2.05), vec2(0.5, 0.65), 0.06);
}
