shader_type canvas_item;
// Softly fades the painting's top and bottom edges into the sky behind it, so a 3:4 painting
// sits seamlessly on any phone height.

uniform float top_fade = 0.10;
uniform float bottom_fade = 0.12;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = smoothstep(0.0, top_fade, UV.y) * smoothstep(1.0, 1.0 - bottom_fade, UV.y);
	a *= smoothstep(0.0, 0.04, UV.x) * smoothstep(1.0, 0.96, UV.x);
	COLOR = vec4(c.rgb, c.a * a);
}
