// Coursed limestone ashlar, as in the Troy VI citadel walls.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.74, 0.68, 0.55);
uniform vec3 joint_color : source_color = vec3(0.22, 0.19, 0.15);
uniform vec2 block_size = vec2(0.95, 0.46);
uniform float bevel = 0.035;
uniform float variation = 0.16;
uniform float bump = 1.0;
uniform float weathering = 0.55;
uniform float soot = 0.0;

float block_height(vec2 uv, out vec2 id, out float edge) {
	float row = floor(uv.y / block_size.y);
	float w = block_size.x * mix(0.75, 1.55, hash11(row * 1.37 + 3.1));
	float off = hash11(row + 17.0) * w * 3.0;
	float x = (uv.x + off) / w;
	id = vec2(floor(x), row);
	vec2 cell = vec2(w, block_size.y);
	vec2 f = vec2(fract(x) * w, uv.y - row * block_size.y);
	vec2 d = min(f, cell - f);
	edge = min(d.x, d.y);
	float h = smoothstep(0.0, bevel, edge);
	// Each block sits a little proud or shy of its neighbours.
	h *= 0.82 + 0.18 * hash21(id + 4.7);
	return h;
}

float surface(vec2 uv, float fade) {
	vec2 id;
	float edge;
	float h = block_height(uv, id, edge) * 0.022;
	h += (fbm(uv * 9.0) - 0.5) * 0.010 * fade;
	h += (vnoise(uv * 38.0) - 0.5) * 0.003 * fade;
	return h;
}

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

void fragment() {
	vec2 id;
	float edge;
	float fade = detail_fade(uv_m, block_size.y);
	float blk = block_height(uv_m, id, edge);
	float tint = (hash21(id) - 0.5) * 2.0 * variation;
	vec3 stone = base_color * (1.0 + tint);
	stone = mix(stone, stone * vec3(1.06, 0.98, 0.86), hash21(id + 9.1) * 0.5);
	float grain = fbm(uv_m * 6.0);
	stone *= 0.82 + 0.36 * grain;
	// Rain streaks and lichen run down from the top of each course.
	float streak = fbm(vec2(uv_m.x * 2.4, uv_m.y * 0.22));
	float lichen = smoothstep(0.55, 0.8, fbm(uv_m * 0.7 + 11.0));
	stone = mix(stone, stone * vec3(0.62, 0.60, 0.55), smoothstep(0.45, 0.8, streak) * weathering);
	stone = mix(stone, vec3(0.42, 0.43, 0.30), lichen * 0.28 * weathering);
	stone = mix(stone, vec3(0.05, 0.045, 0.04), soot * smoothstep(0.3, 0.9, fbm(uv_m * 0.5 + 3.0)));
	vec3 col = mix(joint_color, stone, mix(1.0, blk, fade)) * COLOR.rgb;
	ALBEDO = col;
	ROUGHNESS = 0.93 - 0.08 * grain;
	SPECULAR = 0.25;
	AO = mix(1.0, 0.55 + 0.45 * blk, fade);
	AO_LIGHT_AFFECT = 0.4;
	if (fade > 0.01 && detail_scale > 0.5) {
		float e = 0.012;
		float h0 = surface(uv_m, fade);
		vec2 grad = vec2(surface(uv_m + vec2(e, 0.0), fade) - h0, surface(uv_m + vec2(0.0, e), fade) - h0) / e;
		NORMAL = bump_normal(grad, bump * fade, VIEW_MATRIX);
	}
}
