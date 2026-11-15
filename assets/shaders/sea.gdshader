// The open sea: a swell of long waves the game can compute too (see
// Sea.height), so a ship rides exactly the water that is drawn, and an
// optional whirlpool (Charybdis) that draws the surface down into a funnel.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.012, 0.06, 0.13);
uniform vec3 shallow_color : source_color = vec3(0.04, 0.27, 0.30);
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform float sea_time = 0.0;
uniform float swell = 1.0;      // wave height scale: 1 a fair day, 3 a storm
// Whirlpool: centre x, z, radius of the funnel, depth at its eye.
uniform vec4 vortex = vec4(0.0, 0.0, 0.0, 0.0);
uniform float vortex_spin = 0.0;
// 1 on desktops; 0 on phones, where the fine ripples are dropped.
uniform float detail_scale = 1.0;
// The sea floor near the islands (see Sea.set_floor): height as (h + 12) / 16
// over ground_rect (x, z of the corner, width, depth in metres; 0 for none).
uniform sampler2D ground_tex : filter_linear, repeat_disable;
uniform vec4 ground_rect = vec4(0.0);
uniform vec3 sand_water : source_color = vec3(0.16, 0.5, 0.46);
// The ship's hull, kept dry inside: centre x, z, then sin and cos of its
// heading; hull_size is the half beam and half length (0 for no ship). The
// plan follows Ship._half_beam; keep the two in step.
uniform vec4 hull_xf = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 hull_size = vec2(0.0);

varying vec3 w_pos;
varying float crest;

// Keep in step with Sea.WAVES in src/sea/sea.gd: direction x, z, wavelength, amplitude.
const vec4 W0 = vec4(1.0, 0.25, 46.0, 0.34);
const vec4 W1 = vec4(0.55, 0.85, 23.0, 0.18);
const vec4 W2 = vec4(-0.4, 0.92, 11.0, 0.08);
const vec4 W3 = vec4(0.9, -0.45, 6.5, 0.04);

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Height and slope (dh/dx, dh/dz) of one wave.
vec3 wave(vec4 w, vec2 p) {
	vec2 d = normalize(w.xy);
	float k = 6.2831853 / w.z;
	float c = sqrt(9.8 / k);
	float ph = k * (dot(d, p) - c * sea_time);
	float a = w.w * swell;
	return vec3(a * sin(ph), a * k * cos(ph) * d);
}

vec3 swell_at(vec2 p) {
	return wave(W0, p) + wave(W1, p) + wave(W2, p) + wave(W3, p);
}

// The whirlpool's draw-down and its slope.
vec3 funnel(vec2 p) {
	if (vortex.z <= 0.0) {
		return vec3(0.0);
	}
	vec2 o = p - vortex.xy;
	float r = length(o) / vortex.z;
	float f = vortex.w / (1.0 + 9.0 * r * r);
	float dfdr = -vortex.w * 18.0 * r / pow(1.0 + 9.0 * r * r, 2.0) / vortex.z;
	vec2 dir = length(o) > 0.001 ? o / length(o) : vec2(0.0);
	return vec3(-f, -dfdr * dir);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 s = swell_at(wp.xz) + funnel(wp.xz);
	VERTEX.y += s.x;
	crest = s.x / max(swell * 0.5, 0.05);
	w_pos = wp + vec3(0.0, s.x, 0.0);
}

void fragment() {
	vec2 p = w_pos.xz;
	if (hull_size.x > 0.0) {
		// The hull's own plan (Ship._half_beam): full beam amidships, narrowing
		// to the stem and the stern, so no water shows anywhere inside her.
		vec2 o = p - hull_xf.xy;
		float across = o.x * hull_xf.w - o.y * hull_xf.z;
		float f = (o.x * hull_xf.z + o.y * hull_xf.w) / hull_size.y;
		if (abs(f) < 1.0) {
			float half_beam = hull_size.x * pow(max(cos(f * 1.5707963), 0.0), 0.55);
			if (abs(across) < half_beam) {
				discard;
			}
		}
	}
	vec3 s = swell_at(p) + funnel(p);
	vec2 grad = s.yz;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist / 1800.0, 0.1, 1.0);
	// Ripples on the swell, swirling in the whirlpool.
	vec2 q = p;
	if (vortex.z > 0.0) {
		vec2 o = p - vortex.xy;
		float r = length(o);
		float ang = atan(o.y, o.x) + vortex_spin * sea_time * 3.0 / (1.0 + r * 0.05);
		q = vortex.xy + vec2(cos(ang), sin(ang)) * r;
	}
	if (detail_scale > 0.5) {
		float e = 0.3;
		float t = sea_time * 0.6;
		float n0 = vnoise(q * 0.9 + vec2(t, t * 0.7)) + 0.5 * vnoise(q * 2.7 - vec2(t * 1.3, t * 0.4));
		float nx = vnoise((q + vec2(e, 0.0)) * 0.9 + vec2(t, t * 0.7)) + 0.5 * vnoise((q + vec2(e, 0.0)) * 2.7 - vec2(t * 1.3, t * 0.4));
		float nz = vnoise((q + vec2(0.0, e)) * 0.9 + vec2(t, t * 0.7)) + 0.5 * vnoise((q + vec2(0.0, e)) * 2.7 - vec2(t * 1.3, t * 0.4));
		grad += vec2(nx - n0, nz - n0) / e * 0.12 * fade * swell;
		// Cat's-paws: the finest ripples, close by, where the sun glitters.
		float near = clamp(1.0 - dist / 120.0, 0.0, 1.0);
		float e2 = 0.08;
		vec2 r = q * 6.5 + vec2(-t * 2.1, t * 1.6);
		float m0 = vnoise(r);
		grad += vec2(vnoise(r + vec2(e2 * 6.5, 0.0)) - m0, vnoise(r + vec2(0.0, e2 * 6.5)) - m0) / e2 * 0.018 * near;
	}
	vec3 wn = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	vec3 col = mix(shallow_color, deep_color, clamp(0.35 + fres, 0.0, 1.0));
	// Light through the thin top of a wave, and foam breaking on the crests.
	col += shallow_color * 0.6 * clamp(crest, 0.0, 1.0);
	float foam = smoothstep(0.85, 1.25, crest + (vnoise(p * 1.7 + sea_time * 0.3) - 0.5) * 0.6) * fade;
	// Lace: the foam a breaking crest leaves on the back of the wave, in
	// threads drawn out along the swell.
	vec2 along = normalize(W0.xy);
	vec2 lp = vec2(dot(p, along), dot(p, vec2(-along.y, along.x)));
	float lace = vnoise(lp * vec2(0.35, 1.6) + vec2(sea_time * 0.15, 0.0)) * vnoise(lp * vec2(1.1, 3.4) - sea_time * 0.1);
	foam = max(foam, smoothstep(0.4, 0.66, lace) * smoothstep(0.0, 0.7, crest) * 0.4 * fade * min(swell, 1.5));
	if (vortex.z > 0.0) {
		float r = length(p - vortex.xy) / vortex.z;
		foam = max(foam, smoothstep(1.2, 0.2, r) * (0.4 + 0.6 * vnoise(q * 0.8)));
	}
	// The shallows: turquoise over pale sand, and the surf breaking at the
	// waterline in bands that roll in to the beach.
	if (ground_rect.z > 0.0) {
		vec2 uv = (p - ground_rect.xy) / ground_rect.zw;
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			float floor_h = texture(ground_tex, uv).r * 16.0 - 12.0;
			float depth = w_pos.y - floor_h;
			col = mix(col, sand_water * (0.85 + 0.3 * vnoise(p * 0.2)), smoothstep(9.0, 0.8, depth) * 0.85);
			float roll = fract(floor_h * 0.55 + sea_time * 0.22 + vnoise(p * 0.12) * 0.9);
			float band = smoothstep(0.0, 0.12, roll) * smoothstep(0.45, 0.12, roll) * smoothstep(3.2, 0.6, depth);
			float wash = smoothstep(0.9, 0.05, depth);
			float churn = 0.6 + 0.4 * vnoise(p * 1.4 - sea_time * 0.4);
			foam = max(foam, clamp(max(band, wash) * churn, 0.0, 1.0));
		}
	}
	ALBEDO = mix(col, foam_color, foam * 0.8);
	ROUGHNESS = mix(0.06 + 0.12 * (1.0 - fade), 0.7, foam);
	SPECULAR = 0.6;
}
