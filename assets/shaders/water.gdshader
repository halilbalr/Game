// The Scamander and the wine-dark sea beyond the plain.
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec3 deep_color : source_color = vec3(0.03, 0.10, 0.16);
uniform vec3 shallow_color : source_color = vec3(0.10, 0.26, 0.28);
uniform float wave_scale = 0.08;
uniform float wave_speed = 0.35;
uniform float roughness = 0.08;

varying vec3 w_pos;

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

float waves(vec2 p) {
	float t = TIME * wave_speed;
	float h = vnoise(p * wave_scale * 3.0 + vec2(t, t * 0.6)) * 0.5;
	h += vnoise(p * wave_scale * 9.0 - vec2(t * 1.3, t * 0.4)) * 0.3;
	h += vnoise(p * wave_scale * 27.0 + vec2(t * 0.7, -t)) * 0.2;
	return h;
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = w_pos.xz;
	float e = 0.4;
	float h0 = waves(p);
	vec2 grad = vec2(waves(p + vec2(e, 0.0)) - h0, waves(p + vec2(0.0, e)) - h0) / e;
	float dist = length(w_pos - CAMERA_POSITION_WORLD);
	float fade = clamp(1.0 - dist / 2500.0, 0.15, 1.0);
	vec3 wn = normalize(vec3(-grad.x * 1.6 * fade, 1.0, -grad.y * 1.6 * fade));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow_color, deep_color, clamp(0.4 + fres, 0.0, 1.0));
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ROUGHNESS = roughness + 0.1 * (1.0 - fade);
}
