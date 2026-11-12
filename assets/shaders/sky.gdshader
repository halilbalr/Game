// One sky for every hour of the siege: Aegean noon, the long gold of evening,
// and the starlit night the city fell. Driven by uniforms from Atmosphere.
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.16, 0.34, 0.66);
uniform vec3 horizon_color : source_color = vec3(0.70, 0.80, 0.90);
uniform vec3 ground_color : source_color = vec3(0.30, 0.27, 0.22);
uniform vec3 sun_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float sun_size = 0.022;
uniform float sun_glow = 0.6;
uniform float sun_disk_energy = 12.0;
uniform bool moon = false;
uniform float star_intensity = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.55, 0.60, 0.70);
uniform float cloud_cover = 0.35;
uniform float cloud_speed = 0.004;
uniform vec3 fire_color : source_color = vec3(1.0, 0.35, 0.08);
uniform float fire_glow = 0.0;
uniform float exposure = 1.0;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 5; i++) {
		s += a * vnoise(p);
		p = p * 2.02 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return s;
}

float stars(vec3 dir) {
	vec3 p = dir * 190.0;
	vec3 cell = floor(p);
	vec3 f = fract(p) - 0.5;
	float h = hash31(cell);
	float present = step(0.972, h);
	vec3 off = vec3(hash31(cell + 3.1), hash31(cell + 7.7), hash31(cell + 13.3)) - 0.5;
	float d = length(f - off * 0.6);
	float size = mix(0.035, 0.11, hash31(cell + 21.0));
	float twinkle = 0.75 + 0.25 * sin(TIME * (1.5 + h * 4.0) + h * 40.0);
	return present * smoothstep(size, 0.0, d) * (0.4 + 1.6 * hash31(cell + 5.0)) * twinkle;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float h = dir.y;
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(h, 0.0, 1.0), 0.42));
	if (h < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}

	vec3 light = sun_color;
	float sd = 0.0;
	if (LIGHT0_ENABLED) {
		sd = max(dot(dir, LIGHT0_DIRECTION), 0.0);
		// Forward-scatter haze around the light, widest near the horizon.
		float haze = pow(sd, 6.0) * 0.35 + pow(sd, 48.0) * 0.6;
		col += light * haze * sun_glow * (1.0 - clamp(h, 0.0, 1.0) * 0.5);
	}

	if (star_intensity > 0.0 && h > -0.02) {
		float fade = smoothstep(-0.02, 0.25, h);
		col += vec3(0.85, 0.9, 1.0) * stars(dir) * star_intensity * fade;
		// The river of the sky: a faint band of unresolved stars.
		vec3 axis = normalize(vec3(0.35, 0.5, 0.8));
		float band = exp(-pow(dot(dir, axis) * 5.0, 2.0));
		col += vec3(0.5, 0.56, 0.7) * band * fbm(dir.xz * 6.0 + dir.y * 3.0) * 0.05 * star_intensity * fade;
	}

	float disk = 0.0;
	if (LIGHT0_ENABLED) {
		float ang = acos(clamp(dot(dir, LIGHT0_DIRECTION), -1.0, 1.0));
		disk = smoothstep(sun_size, sun_size * 0.82, ang);
		if (moon) {
			// Mottled lunar face.
			float maria = fbm(dir.xy * 60.0 + dir.z * 40.0);
			col = mix(col, light * sun_disk_energy * (0.65 + 0.5 * maria), disk);
		} else {
			col += light * sun_disk_energy * disk;
		}
	}

	if (cloud_cover > 0.0 && h > 0.0) {
		vec2 cuv = dir.xz / (h + 0.12);
		cuv += vec2(TIME * cloud_speed, TIME * cloud_speed * 0.4);
		float dens = fbm(cuv * 0.55);
		float detail = fbm(cuv * 2.3 + 5.0);
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, dens * 0.75 + detail * 0.25);
		float lit = clamp(0.55 + 0.45 * (dens - detail) * 2.0 + pow(sd, 4.0) * 0.5, 0.0, 1.0);
		vec3 ccol = mix(cloud_shadow, cloud_color, lit);
		ccol += light * pow(sd, 10.0) * 0.5 * sun_glow;
		float horizon_fade = smoothstep(0.0, 0.18, h);
		col = mix(col, ccol, c * horizon_fade * 0.92 * (1.0 - disk * 0.5));
	}

	if (fire_glow > 0.0) {
		// Underlight from a burning city: strongest low on the sky.
		float low = exp(-max(h, 0.0) * 4.5);
		float flicker = 0.85 + 0.15 * sin(TIME * 2.3) * sin(TIME * 3.7 + 1.0);
		float smoke = fbm(dir.xz * 3.0 / (abs(h) + 0.3) + vec2(TIME * 0.02, 0.0));
		col = mix(col, col * 0.4, smoke * fire_glow * 0.6 * smoothstep(0.0, 0.4, h));
		col += fire_color * low * fire_glow * flicker * (0.5 + 0.7 * smoke);
	}

	COLOR = col * exposure;
}
