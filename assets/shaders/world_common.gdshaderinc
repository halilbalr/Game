// Shared by every architectural shader: metric texture coordinates derived
// from world position and face normal, so generated geometry needs no UVs.

uniform bool local_space = false;
// 1 on desktops; 0 on phones, where the bump pass and half the noise octaves are dropped.
uniform float detail_scale = 1.0;

varying vec2 uv_m;
varying vec3 w_pos;
varying vec3 w_nrm;
varying flat vec3 w_udir;
varying flat vec3 w_vdir;

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	int octaves = detail_scale > 0.5 ? 4 : 2;
	for (int i = 0; i < octaves; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	// Two octaves sum to 0.75 where four sum to 0.94: keep the same brightness.
	return detail_scale > 0.5 ? s : s * 1.25;
}

// Distance to the nearest cell edge of a Voronoi tiling, plus the cell id.
float voronoi_edge(vec2 p, out vec2 cell_id) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			float d = dot(r, r);
			if (d < md) { md = d; mr = r; mg = g; }
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + o - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	cell_id = n + mg;
	return md;
}

// Call from vertex(): fills the varyings above.
#define WORLD_UV(vertex, normal, model) { \
	vec3 wu_p = local_space ? vertex : (model * vec4(vertex, 1.0)).xyz; \
	vec3 wu_n = local_space ? normalize(normal) : normalize(mat3(model) * normal); \
	vec3 wu_u; \
	vec3 wu_v; \
	if (abs(wu_n.y) > 0.92) { \
		wu_u = vec3(1.0, 0.0, 0.0); \
		wu_v = vec3(0.0, 0.0, 1.0); \
	} else { \
		wu_u = normalize(cross(vec3(0.0, 1.0, 0.0), wu_n)); \
		wu_v = vec3(0.0, 1.0, 0.0); \
	} \
	uv_m = vec2(dot(wu_p, wu_u), dot(wu_p, wu_v)); \
	w_pos = (model * vec4(vertex, 1.0)).xyz; \
	if (local_space) { \
		wu_u = normalize(mat3(model) * wu_u); \
		wu_v = normalize(mat3(model) * wu_v); \
		wu_n = normalize(mat3(model) * wu_n); \
	} \
	w_nrm = wu_n; \
	w_udir = wu_u; \
	w_vdir = wu_v; \
}

// Bends the shading normal by a height-field gradient given in metres.
vec3 bump_normal(vec2 grad, float strength, mat4 view) {
	vec3 n = normalize(w_nrm);
	vec3 t = normalize(w_udir - n * dot(w_udir, n));
	vec3 b = normalize(w_vdir - n * dot(w_vdir, n));
	vec3 wn = normalize(n - strength * (grad.x * t + grad.y * b));
	return normalize((view * vec4(wn, 0.0)).xyz);
}

// 1 near the camera, 0 where a texel of the given size would alias.
float detail_fade(vec2 uv, float feature) {
	float fw = max(length(dFdx(uv)), length(dFdy(uv)));
	return clamp(1.5 - fw / (feature * 0.5), 0.0, 1.0);
}
