shader_type spatial;
render_mode cull_disabled;
// Crossed-quad flora. Only the top vertices carry sway (UV2.x) so plants
// stay rooted while their heads wave in the wind.

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.001) {
		float phase = wp.x * 0.7 + wp.z * 0.6;
		VERTEX.x += sin(TIME * 2.1 + phase) * 0.09 * sway;
		VERTEX.z += cos(TIME * 1.7 + phase * 1.3) * 0.07 * sway;
	}
}

void fragment() {
	// Vertex colors arrive sRGB; albedo must be linear.
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.9;
	SPECULAR = 0.1;
	EMISSION = pow(COLOR.rgb, vec3(2.2)) * UV2.y;
}
