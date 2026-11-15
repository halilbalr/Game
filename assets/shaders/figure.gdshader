// Skin, cloth, hair and leather on figures and gear. Colour is painted per
// vertex; this adds what paint cannot: the grain of skin, the weave of wool,
// the dapple of an ox-hide, a sheen where light grazes. Noise is taken from
// the part's own space, so it stays put as the limb moves.
shader_type spatial;

uniform float rough = 0.7;
uniform float grain = 0.12;      // mottling, as a share of brightness
uniform float grain_size = 60.0; // blotches per metre
uniform float weave = 0.0;       // threads per metre; 0 for none
uniform float dapple = 0.0;      // ox-hide patches: 0 plain, 1 bold
uniform float sheen = 0.0;       // rim light, for skin and hair
uniform float strands = 0.0;     // streaks along the part's height, for hair
// 1 on desktops; 0 on phones, where the fine weave is dropped.
uniform float detail_scale = 1.0;

varying vec3 lp;

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
}

void fragment() {
	// What this is made of, from the vertex alpha (see Sculpt.KIND); a full
	// alpha means "as the material's own settings say".
	float m_rough = rough;
	float m_grain = grain;
	float m_size = grain_size;
	float m_weave = weave;
	float m_dapple = dapple;
	float m_sheen = sheen;
	float m_strands = strands;
	int kind = int(floor(COLOR.a * 10.0));
	if (kind < 10) {
		m_weave = 0.0; m_dapple = 0.0; m_sheen = 0.0; m_strands = 0.0;
		if (kind == 9) { m_rough = 0.58; m_grain = 0.07; m_size = 90.0; m_sheen = 0.22; }       // skin
		else if (kind == 8) { m_rough = 0.5; m_grain = 0.1; m_size = 60.0; m_strands = 0.5; m_sheen = 0.12; } // hair
		else if (kind == 7) { m_rough = 0.92; m_grain = 0.1; m_size = 25.0; m_weave = 900.0; }  // wool, linen
		else if (kind == 6) { m_rough = 0.62; m_grain = 0.2; m_size = 40.0; }                    // leather
		else if (kind == 5) { m_rough = 0.7; m_grain = 0.14; m_size = 30.0; m_dapple = 1.0; }    // ox-hide
		else if (kind == 4) { m_rough = 0.12; m_grain = 0.0; }                                    // eye
		else if (kind == 3) { m_rough = 0.4; m_grain = 0.08; m_size = 50.0; }                    // ivory
		else { m_rough = 0.8; m_grain = 0.08; m_size = 60.0; }
	}
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	float n = n3(lp * m_size) * 0.65 + n3(lp * m_size * 2.7) * 0.35;
	col *= 1.0 + m_grain * (n - 0.5) * 2.0;
	if (m_dapple > 0.0) {
		// Brown-and-white or black-and-white hides, as on the frescoes.
		float d = n3(lp * 4.2 + 3.1) * 0.7 + n3(lp * 9.5) * 0.3;
		col = mix(col, vec3(0.03, 0.022, 0.018), smoothstep(0.56, 0.6, d) * m_dapple);
		col = mix(col, vec3(0.62, 0.57, 0.47), smoothstep(0.4, 0.36, d) * m_dapple * 0.8);
		// Hair lies one way across the hide.
		col *= 0.92 + 0.16 * n3(vec3(lp.x * 30.0, lp.y * 240.0, lp.z * 30.0));
	}
	if (m_strands > 0.0) {
		col *= 1.0 + m_strands * (n3(vec3(lp.x * 260.0, lp.y * 14.0, lp.z * 260.0)) - 0.5);
	}
	if (m_weave > 0.0 && detail_scale > 0.5) {
		float fw = fwidth(lp.y) * m_weave;
		float fade = clamp(1.6 - fw, 0.0, 1.0);
		vec3 w = sin(lp * m_weave);
		col *= 1.0 + 0.13 * (w.x * w.y + w.y * w.z) * fade;
	}
	ALBEDO = col;
	ROUGHNESS = m_rough;
	SPECULAR = 0.35;
	RIM = m_sheen;
	RIM_TINT = 0.6;
}
