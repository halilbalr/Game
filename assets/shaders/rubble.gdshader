// Unworked fieldstone laid in mud: house footings, terraces, paving.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.62, 0.57, 0.48);
uniform vec3 joint_color : source_color = vec3(0.25, 0.21, 0.16);
uniform float stone_scale = 3.2;
uniform float joint_width = 0.045;
uniform float variation = 0.22;
uniform float bump = 1.0;
uniform float polish = 0.0;

float surface(vec2 uv, float fade) {
	vec2 id;
	float e = voronoi_edge(uv * stone_scale, id) / stone_scale;
	float h = smoothstep(0.0, joint_width, e) * 0.02;
	h += (fbm(uv * 11.0) - 0.5) * 0.008 * fade * (1.0 - polish * 0.7);
	return h;
}

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

void fragment() {
	float fade = detail_fade(uv_m, 0.6 / stone_scale);
	vec2 id;
	float e = voronoi_edge(uv_m * stone_scale, id) / stone_scale;
	float m = smoothstep(0.0, joint_width, e);
	vec3 stone = base_color * (1.0 + (hash21(id) - 0.5) * 2.0 * variation);
	stone = mix(stone, stone * vec3(0.9, 0.86, 0.95), hash21(id + 5.5) * 0.4);
	stone *= 0.85 + 0.3 * fbm(uv_m * 7.0);
	vec3 col = mix(joint_color, stone, mix(1.0, m, fade)) * COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = mix(0.94, 0.62, polish * m);
	SPECULAR = 0.25;
	AO = mix(1.0, 0.6 + 0.4 * m, fade);
	if (fade > 0.01 && detail_scale > 0.5) {
		float d = 0.012;
		float h0 = surface(uv_m, fade);
		vec2 grad = vec2(surface(uv_m + vec2(d, 0.0), fade) - h0, surface(uv_m + vec2(0.0, d), fade) - h0) / d;
		NORMAL = bump_normal(grad, bump * fade, VIEW_MATRIX);
	}
}
