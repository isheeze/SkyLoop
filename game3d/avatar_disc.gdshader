shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// A round portrait with a coloured ring: the face on top of a player's puck.

uniform sampler2D portrait : source_color, filter_linear_mipmap;
uniform vec4 ring_color : source_color = vec4(1.0);
uniform float ring_width = 0.11;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p) * 2.0;
	float aa = fwidth(r) * 1.2;
	if (r > 1.0) {
		discard;
	}
	vec3 face = texture(portrait, UV * 0.92 + 0.04).rgb;
	float ring = smoothstep(1.0 - ring_width - aa, 1.0 - ring_width, r);
	ALBEDO = mix(face, ring_color.rgb, ring);
	// Soft antialiased edge without blending: dither the last pixel.
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA = 1.0 - smoothstep(1.0 - aa, 1.0, r);
}
