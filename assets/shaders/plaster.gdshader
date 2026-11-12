// Mud plaster over sun-dried brick: the walls of houses and the upper works
// of the fortifications. Vertex alpha carries height up the wall (0 base, 1 top).
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform vec3 plaster_color : source_color = vec3(0.78, 0.69, 0.54);
uniform vec3 brick_color : source_color = vec3(0.60, 0.47, 0.33);
uniform vec2 brick_size = vec2(0.52, 0.13);
uniform float reveal = 0.35;
uniform float bump = 1.0;
uniform float soot = 0.0;

float brick_mask(vec2 uv, out vec2 id) {
	float row = floor(uv.y / brick_size.y);
	float x = uv.x / brick_size.x + 0.5 * mod(row, 2.0);
	id = vec2(floor(x), row);
	vec2 f = vec2(fract(x) * brick_size.x, uv.y - row * brick_size.y);
	vec2 d = min(f, brick_size - f);
	return smoothstep(0.0, 0.014, min(d.x, d.y));
}

float reveal_mask(vec2 uv, float height) {
	// Plaster falls away in patches, soonest near the ground.
	float n = fbm(uv * 0.55 + 31.0) * 0.7 + fbm(uv * 2.6 + 3.0) * 0.3;
	float low = 1.0 - smoothstep(0.0, 0.45, height);
	float thr = 0.98 - reveal * 0.62 - low * 0.10 * step(0.01, reveal);
	return smoothstep(thr, thr + 0.05, n);
}

float surface(vec2 uv, float height, float fade) {
	vec2 id;
	float bm = brick_mask(uv, id);
	float rv = reveal_mask(uv, height);
	float plaster_h = 0.014 + (fbm(uv * 5.0) - 0.5) * 0.012 * fade;
	float brick_h = bm * 0.008 * fade + (vnoise(uv * 30.0) - 0.5) * 0.002 * fade;
	return mix(plaster_h, brick_h, rv);
}

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

void fragment() {
	float height = COLOR.a;
	float fade = detail_fade(uv_m, brick_size.y);
	vec2 id;
	float bm = brick_mask(uv_m, id);
	float rv = reveal_mask(uv_m, height);
	vec3 plaster = plaster_color * COLOR.rgb;
	float blotch = fbm(uv_m * 1.3);
	plaster *= 0.84 + 0.30 * blotch;
	// Straw temper flecks in the mud.
	float fleck = smoothstep(0.80, 0.88, vnoise(uv_m * vec2(60.0, 22.0)));
	plaster = mix(plaster, plaster * vec3(1.18, 1.14, 0.95), fleck * 0.35 * fade);
	// Splash zone at the foot of the wall and wash-down from the top.
	float damp = (1.0 - smoothstep(0.0, 0.22, height)) * (0.5 + 0.5 * fbm(uv_m * 2.0));
	plaster = mix(plaster, plaster * vec3(0.60, 0.55, 0.48), damp * 0.75);
	float streak = smoothstep(0.5, 0.85, fbm(vec2(uv_m.x * 3.0, uv_m.y * 0.25))) * smoothstep(0.35, 1.0, height);
	plaster = mix(plaster, plaster * vec3(0.72, 0.68, 0.62), streak * 0.5);
	vec3 brick = brick_color * (0.8 + 0.4 * hash21(id)) * mix(0.45, 1.0, mix(1.0, bm, fade));
	vec3 col = mix(plaster, brick, rv);
	col = mix(col, vec3(0.045, 0.04, 0.035), soot * smoothstep(0.25, 0.85, fbm(uv_m * 0.45 + 7.0) + height * 0.3));
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.15;
	if (fade > 0.01 && detail_scale > 0.5) {
		float e = 0.012;
		float h0 = surface(uv_m, height, fade);
		vec2 grad = vec2(surface(uv_m + vec2(e, 0.0), height, fade) - h0,
			surface(uv_m + vec2(0.0, e), height, fade) - h0) / e;
		NORMAL = bump_normal(grad, bump * fade, VIEW_MATRIX);
	}
}
