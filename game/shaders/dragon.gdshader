shader_type spatial;
// The Meshy dragon's auto-rig has no wing bones, so the wings flap here:
// vertices rise/fold with distance from the body midline. Works on the
// post-skinning vertex stream, so bone poses (tail sway) combine freely.
uniform sampler2D albedo_tex: source_color;
uniform float wing_x0 = 0.0;     // |x| where the wing starts (model units)
uniform float flap_amount = 0.9; // vertical travel per unit of reach
uniform float flap_speed = 4.2;

void vertex() {
	float reach = max(abs(VERTEX.x) - wing_x0, 0.0);
	float flap = sin(TIME * flap_speed) * flap_amount;
	VERTEX.y += reach * flap;
	// Wings fold slightly inward at the top of the beat.
	VERTEX.x -= sign(VERTEX.x) * reach * abs(flap) * 0.3;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = 0.85;
	SPECULAR = 0.15;
}
