// Aegean islands: wet sand at the waterline, scrub and dry grass on the
// gentle slopes, pale limestone where it is too steep for anything to hold.
shader_type spatial;

#include "world_common.gdshaderinc"

uniform vec3 sand : source_color = vec3(0.72, 0.64, 0.48);
uniform vec3 wet_sand : source_color = vec3(0.42, 0.37, 0.28);
uniform vec3 rock : source_color = vec3(0.64, 0.61, 0.55);
uniform vec3 scrub : source_color = vec3(0.30, 0.34, 0.17);
uniform vec3 grass : source_color = vec3(0.58, 0.52, 0.30);
uniform float meadow = 0.0; // 1: green and flowering (the Sirens' meadow)

void vertex() {
	WORLD_UV(VERTEX, NORMAL, MODEL_MATRIX)
}

// Limestone on a face, at (across, up) [param f]. Adds its bedding joint
// strength to [param joint].
vec3 cliff(vec2 f, vec3 base, inout float joint) {
	float blocks = fbm(f * vec2(0.06, 0.18));
	float grain = fbm(f * 0.7 + 7.0);
	// Bedding: layers of limestone a few metres thick, wavering.
	float bed = sin(f.y * 0.45 + blocks * 7.0 + sin(f.y * 0.13) * 2.0);
	float j = smoothstep(0.93, 0.995, abs(bed)) * smoothstep(0.3, 0.6, grain + blocks * 0.5);
	joint += j;
	// Upright cracks between the blocks, staggered from layer to layer.
	float crack = smoothstep(0.47, 0.497, abs(fract(f.x * 0.11 + floor(f.y * 0.45 / 3.14159) * 0.37 + blocks) - 0.5));
	float speck = fbm(f * 2.6 + 3.0);
	// Rain-streaks of darker weathering hanging down from each ledge.
	float streak = smoothstep(0.55, 0.85, fbm(vec2(f.x * 0.35, f.y * 0.03) + 11.0));
	vec3 stone = base * (0.72 + 0.4 * grain) * (0.86 + 0.26 * blocks) * (0.85 + 0.3 * speck);
	stone *= 1.0 - 0.3 * j - 0.25 * crack - 0.16 * streak;
	return mix(stone, stone * vec3(1.05, 0.97, 0.86), smoothstep(0.4, 0.7, blocks));
}

void fragment() {
	float up = normalize(w_nrm).y;
	float y = w_pos.y;
	float n = fbm(w_pos.xz * 0.08);
	float fine = fbm(w_pos.xz * 0.9 + 3.0);
	vec3 green = mix(grass, scrub, smoothstep(0.35, 0.65, n));
	green = mix(green, vec3(0.22, 0.4, 0.14), meadow);
	vec3 col = green;
	// Steep ground is bare stone, banded by its bedding.
	float steep = smoothstep(0.82, 0.62, up + (n - 0.5) * 0.2);
	// On a cliff face the ground plane's noise runs straight down the rock
	// in streaks: sample the face itself instead, once looking along x and
	// once along z, blended by which way the face turns.
	vec3 an = abs(normalize(w_nrm));
	vec2 wt = pow(an.xz, vec2(4.0));
	wt /= max(wt.x + wt.y, 1e-4);
	float joint = 0.0;
	vec3 stone = cliff(vec2(w_pos.z, y), rock, joint) * wt.x + cliff(vec2(w_pos.x, y), rock, joint) * wt.y;
	joint *= 0.5;
	col = mix(col, stone, steep);
	// Sand on the shore, darker where the sea wets it.
	float shore = smoothstep(2.2, 1.0, y + (n - 0.5) * 0.8);
	col = mix(col, mix(sand, wet_sand, smoothstep(0.9, 0.1, y)) * (0.9 + 0.2 * fine), shore * (1.0 - steep * 0.6));
	// Flowers in the meadow.
	if (meadow > 0.0) {
		float f = step(0.93, hash21(floor(w_pos.xz * 3.0)));
		col = mix(col, vec3(0.9, 0.85, 0.5), f * meadow * (1.0 - steep) * (1.0 - shore));
	}
	ALBEDO = col * mix(0.85 + 0.25 * fine, 1.0, steep);
	ROUGHNESS = mix(0.95, 0.6, shore * smoothstep(0.9, 0.0, y));
	if (detail_scale > 0.5) {
		float e = 0.15;
		float h0 = fbm(uv_m * 1.3);
		vec2 g = vec2(fbm((uv_m + vec2(e, 0.0)) * 1.3) - h0, fbm((uv_m + vec2(0.0, e)) * 1.3) - h0) / e;
		// The ground's bump is projected per vertex and smears on a curved
		// cliff: there, only the ledges where the bedding joints cut back.
		g = g * (1.0 - steep) + vec2(0.0, -0.8 * joint) * steep;
		NORMAL = bump_normal(g, 0.35 * (0.4 + steep), VIEW_MATRIX);
	}
}
