// Sawn and adzed timber: beams, doors, the horse.
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

#include "world_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.36, 0.24, 0.14);
uniform float plank_width = 0.24;
uniform bool grain_vertical = false;
uniform float weathered = 0.3;
uniform float bump = 1.0;
uniform float soot = 0.0;

vec2 plank_uv(vec2 uv) {
	return grain_vertical ? uv.yx : uv;
}

float surface(vec2 uv, float fade, out float plank_id, out float gap) {
	vec2 p = plank_uv(uv);
	plank_id = floor(p.y / plank_width);
	float f = fract(p.y / plank_width) * plank_width;
	gap = smoothstep(0.0, 0.012, min(f, plank_width - f));
	float grain = fbm(vec2(p.x * 1.6 + plank_id * 13.0, p.y * 42.0));
	return gap * 0.012 + (grain - 0.5) * 0.004 * fade;
}

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

void fragment() {
	float fade = detail_fade(uv_m, plank_width * 0.5);
	float pid;
	float gap;
	float h0 = surface(uv_m, fade, pid, gap);
	vec2 p = plank_uv(uv_m);
	float grain = fbm(vec2(p.x * 1.6 + pid * 13.0, p.y * 42.0));
	float rings = sin((p.y + vnoise(vec2(p.x * 0.8, pid)) * 0.08) * 160.0) * 0.5 + 0.5;
	vec3 wood = base_color * (0.8 + 0.4 * hash11(pid + 2.0));
	wood *= 0.75 + 0.35 * grain + 0.10 * rings * fade;
	vec3 grey = vec3(dot(wood, vec3(0.33))) * vec3(1.05, 1.0, 0.92) * 1.25;
	wood = mix(wood, grey, weathered * (0.4 + 0.6 * fbm(uv_m * 0.9)));
	wood = mix(wood, vec3(0.03, 0.028, 0.025), soot * smoothstep(0.2, 0.8, fbm(uv_m * 0.6)));
	ALBEDO = wood * mix(1.0, 0.25 + 0.75 * gap, fade) * COLOR.rgb;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	if (fade > 0.01) {
		float e = 0.006;
		float a;
		float b;
		vec2 grad = vec2(surface(uv_m + vec2(e, 0.0), fade, a, b) - h0,
			surface(uv_m + vec2(0.0, e), fade, a, b) - h0) / e;
		NORMAL = bump_normal(grad, bump * fade, VIEW_MATRIX);
	}
}
