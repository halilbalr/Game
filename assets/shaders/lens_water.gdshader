// Water drops on the lens (see src/ui/lens_water.gd). Each drop bends the
// picture behind it the way a bead of water does (turned about, magnified),
// with a dark rim and a glint; a fresh splash also runs a sheet of water
// across the whole view, rippling it. Runs on every renderer, as a canvas
// shader reading the screen.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
// x, y in screen UV, radius as a share of the screen height, life 1..0.
uniform vec4 drops[24];
uniform float sheet = 0.0;
uniform float aspect = 1.78;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 bend = vec2(0.0);
	float rim = 0.0;
	float glint = 0.0;
	float wet = 0.0;
	for (int i = 0; i < 24; i++) {
		vec4 d = drops[i];
		if (d.w <= 0.0) {
			continue;
		}
		vec2 o = (uv - d.xy) * vec2(aspect, 1.0);
		// A drying drop shrinks and flattens; a running one is drawn out above.
		float r = d.z * (0.55 + 0.45 * d.w);
		o.y *= o.y < 0.0 ? 0.75 : 1.0;
		float k = length(o) / r;
		if (k < 1.0) {
			float cap = sqrt(1.0 - k * k);
			// The bead turns the view about and magnifies it.
			bend += -o / vec2(aspect, 1.0) * (0.9 + 0.6 * cap) * d.w;
			rim = max(rim, smoothstep(0.7, 1.0, k) * d.w);
			glint = max(glint, smoothstep(0.32, 0.0, length(o / r - vec2(-0.3, -0.35))) * d.w);
			wet = max(wet, d.w);
		}
	}
	vec2 ripple = vec2(sin(uv.y * 38.0 + TIME * 9.0), cos(uv.x * 31.0 - TIME * 7.0)) * 0.007 * sheet;
	vec2 suv = clamp(uv + bend + ripple, vec2(0.001), vec2(0.999));
	vec3 c = texture(screen_tex, suv).rgb;
	if (sheet > 0.0) {
		// Smeared by the running water: a few taps around the point.
		vec2 s = vec2(0.006, 0.004) * sheet;
		c = (c + texture(screen_tex, suv + s).rgb + texture(screen_tex, suv - s).rgb
			+ texture(screen_tex, suv + vec2(s.x, -s.y)).rgb) * 0.25;
	}
	c = c * (1.0 - 0.45 * rim) + vec3(glint * 0.55) + vec3(0.02, 0.04, 0.05) * sheet;
	float a = max(wet, sheet);
	COLOR = vec4(c, a > 0.001 ? 1.0 : 0.0);
}
