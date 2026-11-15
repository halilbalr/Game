// Worked bronze, gold and silver: hammer marks, tarnish in the hollows, and
// for scale armour the overlapping rows of small plates.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.83, 0.56, 0.27);
uniform float rough = 0.3;
uniform float hammer = 1.0;   // depth of the planishing marks
uniform float tarnish = 0.3;  // how much dark patina sits on it
uniform float scales = 0.0;   // rows per metre; 0 for plate
// 1 on desktops; 0 on phones, where the hammer marks are dropped.
uniform float detail_scale = 1.0;

varying vec3 lp;
varying vec3 ln;

float h3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float n3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), u.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), u.x), u.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), u.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
}

void fragment() {
	// Which metal, from the vertex alpha (see Sculpt.METAL); a full alpha
	// means "as the material's own settings say".
	float m_rough = rough;
	float m_hammer = hammer;
	float m_tarnish = tarnish;
	float m_scales = scales;
	int kind = int(floor(COLOR.a * 10.0));
	if (kind < 10) {
		m_scales = 0.0;
		if (kind == 9) { m_rough = 0.3; m_tarnish = 0.3; m_hammer = 1.0; }          // bronze
		else if (kind == 7) { m_rough = 0.5; m_tarnish = 0.55; m_hammer = 1.0; }    // dull bronze
		else if (kind == 5) { m_rough = 0.24; m_tarnish = 0.05; m_hammer = 0.6; }   // gold
		else if (kind == 3) { m_rough = 0.3; m_tarnish = 0.35; m_hammer = 0.5; }    // silver
		else { m_rough = 0.38; m_tarnish = 0.3; m_hammer = 0.4; m_scales = 34.0; }  // scale armour
	}
	vec3 col = base_color * pow(COLOR.rgb, vec3(2.2));
	float broad = n3(lp * 7.0) * 0.6 + n3(lp * 19.0) * 0.4;
	float grime = smoothstep(0.5, 0.82, broad) * m_tarnish;
	col *= 0.9 + 0.2 * broad;
	col = mix(col, col * vec3(0.38, 0.42, 0.32), grime);
	float r = m_rough + 0.3 * grime;
	vec3 bend = vec3(0.0);
	if (m_scales > 0.0) {
		// Rows round the body, each row half a scale along from the last.
		float a = atan(lp.z, lp.x) * 0.16 * m_scales;
		float y = lp.y * m_scales;
		float row = floor(y);
		vec2 f = vec2(fract(a + 0.5 * row), fract(y));
		float lip = smoothstep(0.0, 0.16, f.y) * smoothstep(0.0, 0.1, min(f.x, 1.0 - f.x));
		col *= mix(0.3, 1.0, lip) * (0.85 + 0.3 * h3(vec3(floor(a + 0.5 * row), row, 1.0)));
		bend.y = (f.y - 0.6) * 0.9;
		r += 0.1;
	}
	if (detail_scale > 0.5 && m_hammer > 0.0) {
		// Each dent tips the surface a little its own way.
		vec3 q = lp * 55.0;
		bend += (vec3(n3(q), n3(q + 17.3), n3(q + 41.9)) - 0.5) * 0.22 * m_hammer;
		r += (n3(q * 0.5 + 5.0) - 0.5) * 0.12 * m_hammer;
	}
	ALBEDO = col;
	METALLIC = 1.0;
	ROUGHNESS = clamp(r, 0.14, 0.95);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * mat3(MODEL_MATRIX) * bend);
}
