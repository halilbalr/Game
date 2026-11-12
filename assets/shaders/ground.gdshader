// Terrain of the Troad: packed earth in the streets, dry summer grass on the
// plain, scree on the scarp. Vertex colour: R dirt/path, G grass, B rock, A wet.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform vec3 dirt_color : source_color = vec3(0.50, 0.40, 0.28);
uniform vec3 grass_color : source_color = vec3(0.50, 0.46, 0.24);
uniform vec3 grass_green : source_color = vec3(0.28, 0.33, 0.14);
uniform vec3 rock_color : source_color = vec3(0.56, 0.52, 0.45);
uniform float soot = 0.0;

varying vec3 blend;

float surface(vec2 p, vec3 w, float fade) {
	float dirt = (fbm(p * 2.5) - 0.5) * 0.03 + smoothstep(0.72, 0.9, vnoise(p * 9.0)) * 0.012 * fade;
	float grass = (vnoise(p * vec2(18.0, 23.0)) - 0.5) * 0.05 * fade + (fbm(p * 1.1) - 0.5) * 0.05;
	float rock = (fbm(p * 1.7) - 0.5) * 0.14 + (vnoise(p * 12.0) - 0.5) * 0.02 * fade;
	return dirt * w.r + grass * w.g + rock * w.b;
}

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
	blend = COLOR.rgb;
}

void fragment() {
	vec2 p = w_pos.xz;
	float fade = detail_fade(p, 0.12);
	float far_fade = detail_fade(p, 2.0);
	vec3 w = max(blend, vec3(0.0));
	// Break up the blend borders so paths do not end in straight lines.
	float n = fbm(p * 0.35) - 0.5;
	w.r = clamp(w.r + n * 0.5, 0.0, 1.0);
	float slope = 1.0 - clamp(normalize(w_nrm).y, 0.0, 1.0);
	w.b = clamp(w.b + smoothstep(0.22, 0.5, slope), 0.0, 1.0);
	w.g = clamp(w.g * (1.0 - w.r) * (1.0 - w.b), 0.0, 1.0);
	w.r = clamp(w.r * (1.0 - w.b * 0.6), 0.0, 1.0);
	float total = max(w.r + w.g + w.b, 0.001);
	w /= total;

	float big = fbm(p * 0.045);
	vec3 dirt = dirt_color * (0.82 + 0.36 * fbm(p * 1.9));
	dirt = mix(dirt, dirt * vec3(0.72, 0.68, 0.62), smoothstep(0.55, 0.8, fbm(p * 0.6 + 4.0)));
	float pebble = smoothstep(0.74, 0.9, vnoise(p * 9.0)) * fade;
	dirt = mix(dirt, rock_color * 0.95, pebble * 0.6);

	float patch = smoothstep(0.35, 0.7, fbm(p * 0.12 + 9.0));
	vec3 grass = mix(grass_color, grass_green, patch * 0.75);
	float blades = vnoise(p * vec2(26.0, 31.0));
	grass *= 0.72 + 0.45 * mix(0.5, blades, fade) + 0.2 * (big - 0.5);
	grass = mix(grass, dirt, smoothstep(0.62, 0.8, fbm(p * 0.9 + 2.0)) * 0.55);

	vec3 rock = rock_color * (0.75 + 0.5 * fbm(p * 1.4));
	rock = mix(rock, dirt, smoothstep(0.4, 0.75, fbm(p * 0.8 + 17.0)) * 0.5);

	vec3 col = dirt * w.r + grass * w.g + rock * w.b;
	col *= 0.9 + 0.2 * mix(0.5, big, far_fade);
	col = mix(col, vec3(0.05, 0.045, 0.04), soot * smoothstep(0.3, 0.8, fbm(p * 0.3)));
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.12;
	if (fade > 0.01) {
		float e = 0.03;
		float h0 = surface(p, w, fade);
		vec2 grad = vec2(surface(p + vec2(e, 0.0), w, fade) - h0, surface(p + vec2(0.0, e), w, fade) - h0) / e;
		vec3 nrm = normalize(w_nrm);
		vec3 wn = normalize(nrm - vec3(grad.x, 0.0, grad.y) * 0.9 * fade);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
}
