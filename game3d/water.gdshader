shader_type spatial;
// Flowing water for the toy kit's "Water" surfaces: streaks race down the waterfalls, rings
// ripple out across the fountain pool. Works from model-space position (the kit has no UVs).

uniform vec4 water_color : source_color = vec4(0.5, 0.83, 1.0, 1.0);
uniform float speed = 1.7;

varying vec3 p;
varying vec3 n;

void vertex() {
	p = VERTEX;
	n = NORMAL;
}

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

void fragment() {
	vec3 c = water_color.rgb;
	float f;
	if (abs(n.y) < 0.6) {
		// Falling: soft vertical streaks (wiggling a little as they fall) lit by gentle pulses
		// sliding down; brighter near the lip where the water breaks.
		float w = p.x + p.z;
		float streak = 0.5 + 0.5 * sin(w * 46.0 + sin(p.y * 2.5 + TIME * 1.3) * 0.8);
		float pulse = 0.5 + 0.5 * sin(p.y * 4.0 + TIME * speed * 3.5 + hash(floor(w * 9.0)) * 6.0);
		f = smoothstep(0.55, 1.0, streak) * (0.25 + 0.4 * pulse);
		f += clamp(p.y * 0.6 + 0.3, 0.0, 0.35);
	} else {
		// Pool: rings drifting outward from the centre.
		float r = length(p.xz);
		f = smoothstep(0.8, 1.0, fract(r * 5.0 - TIME * 0.55)) * 0.55;
	}
	ALBEDO = mix(c, vec3(1.0), f * 0.75);
	EMISSION = c * 0.18 + vec3(f * 0.3);
	ROUGHNESS = 0.12;
	SPECULAR = 0.6;
}
