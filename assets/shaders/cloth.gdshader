// Woven wool and linen: awnings, tents, sails, cloaks. Two-sided.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform float weave = 520.0;
uniform float stripe = 0.0;
uniform vec3 stripe_color : source_color = vec3(0.45, 0.10, 0.08);
uniform float sway = 0.0;

void vertex() {
	if (sway > 0.0) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float amt = sway * COLOR.a;
		VERTEX.y += sin(TIME * 1.7 + wp.x * 0.9 + wp.z * 0.7) * 0.05 * amt;
		VERTEX.x += sin(TIME * 1.1 + wp.z * 1.3) * 0.03 * amt;
	}
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

void fragment() {
	float fade = detail_fade(uv_m, 2.0 / weave);
	float wv = sin(uv_m.x * weave) * sin(uv_m.y * weave);
	vec3 col = COLOR.rgb * (0.86 + 0.22 * fbm(uv_m * 3.0));
	if (stripe > 0.0) {
		float s = smoothstep(0.42, 0.45, abs(fract(uv_m.x * stripe) - 0.5));
		col = mix(col, stripe_color, s * 0.85);
	}
	col *= 1.0 + 0.10 * wv * fade;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
