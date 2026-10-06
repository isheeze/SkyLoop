shader_type canvas_item;
// Crops a texture to an antialiased circle (for portraits).

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = length(UV - vec2(0.5));
	c.a *= 1.0 - smoothstep(0.49, 0.5, d);
	COLOR = c;
}
