// The open sea: a swell of long waves the game can compute too (see
// Sea.height), so a ship rides exactly the water that is drawn, and an
// optional whirlpool (Charybdis) that draws the surface down into a funnel.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.02, 0.09, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.28, 0.32);
uniform vec3 foam_color : source_color = vec3(0.86, 0.9, 0.9);
uniform float sea_time = 0.0;
uniform float swell = 1.0;      // wave height scale: 1 a fair day, 3 a storm
// Whirlpool: centre x, z, radius of the funnel, depth at its eye.
uniform vec4 vortex = vec4(0.0, 0.0, 0.0, 0.0);
uniform float vortex_spin = 0.0;
// 1 on desktops; 0 on phones, where the fine ripples are dropped.
uniform float detail_scale = 1.0;

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
	}
	vec3 wn = normalize(vec3(-grad.x, 1.0, -grad.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	vec3 col = mix(shallow_color, deep_color, clamp(0.35 + fres, 0.0, 1.0));
	// Light through the thin top of a wave, and foam breaking on the crests.
	col += shallow_color * 0.6 * clamp(crest, 0.0, 1.0);
	float foam = smoothstep(0.7, 1.1, crest + (vnoise(p * 1.7 + sea_time * 0.3) - 0.5) * 0.6) * fade;
	if (vortex.z > 0.0) {
		float r = length(p - vortex.xy) / vortex.z;
		foam = max(foam, smoothstep(1.2, 0.2, r) * (0.4 + 0.6 * vnoise(q * 0.8)));
	}
	ALBEDO = mix(col, foam_color, foam * 0.8);
	ROUGHNESS = mix(0.06 + 0.12 * (1.0 - fade), 0.7, foam);
	SPECULAR = 0.6;
}
