// First-person arms, weapon and shield. Depth is pulled toward the camera so
// a long spear never pokes through a wall or a man standing close.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 tint : source_color = vec3(1.0);
uniform float metal = 0.0;
uniform float rough = 0.75;
uniform bool use_vertex_color = true;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Reverse-Z: the near plane is at z == w.
	POSITION.z = mix(POSITION.z, POSITION.w, 0.86);
}

void fragment() {
	vec3 vc = use_vertex_color ? pow(COLOR.rgb, vec3(2.2)) : vec3(1.0);
	ALBEDO = vc * tint;
	METALLIC = metal;
	ROUGHNESS = rough;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
