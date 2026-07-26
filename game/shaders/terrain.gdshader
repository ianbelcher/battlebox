shader_type spatial;
// Solid voxel surface: vertex colors carry albedo * baked AO * face shading.
// UV2.x = wind sway strength (leaves), UV2.y = emissive energy (lanterns).

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = UV2.x;
	if (sway > 0.001) {
		float phase = wp.x * 0.35 + wp.z * 0.28;
		VERTEX.x += sin(TIME * 1.6 + phase) * 0.06 * sway;
		VERTEX.z += cos(TIME * 1.25 + phase * 1.2) * 0.05 * sway;
	}
}

void fragment() {
	// Vertex colors arrive sRGB; albedo must be linear.
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ROUGHNESS = 0.95;
	SPECULAR = 0.12;
	EMISSION = pow(COLOR.rgb, vec3(2.2)) * UV2.y;
}
