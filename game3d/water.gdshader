shader_type spatial;
// The fountain pool's water (the toy kit's "Water" material): rings drifting outward.
// Works from model-space position (the kit has no UVs).

uniform vec4 water_color : source_color = vec4(0.5, 0.83, 1.0, 1.0);

varying vec3 p;

void vertex() {
	p = VERTEX;
}

void fragment() {
	vec3 c = water_color.rgb;
	float f;
	// Pool: rings drifting outward from the centre.
	float r = length(p.xz);
	f = smoothstep(0.8, 1.0, fract(r * 5.0 - TIME * 0.55)) * 0.55;
	ALBEDO = mix(c, vec3(1.0), f * 0.75);
	EMISSION = c * 0.18 + vec3(f * 0.3);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
