shader_type spatial;
// Facade shader for diorama buildings: matte walls, darker roofs and a grid of windows, some
// lit warm. The window grid is laid out in world space so any box gets windows for free.

uniform vec3 body : source_color = vec3(0.85, 0.82, 0.78);
uniform vec3 roof : source_color = vec3(0.32, 0.34, 0.4);
uniform vec3 window_light : source_color = vec3(1.0, 0.76, 0.45);
uniform float glow = 3.0;
uniform float floors = 11.0;  // window rows per world unit
uniform float columns = 10.0;  // window columns per world unit
uniform float lit_ratio = 0.55;
uniform float street = 0.2;  // no windows below this height
uniform bool windows = true;

varying vec3 wpos;
varying vec3 wnorm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = body;
	float lit = 0.0;
	if (wnorm.y > 0.6) {
		col = roof;
	} else if (windows) {
		float u = abs(wnorm.x) > abs(wnorm.z) ? wpos.z : wpos.x;
		vec2 cell = vec2(u * columns, wpos.y * floors);
		vec2 f = fract(cell);
		float win = step(0.26, f.x) * step(f.x, 0.74) * step(0.28, f.y) * step(f.y, 0.78);
		win *= step(street, wpos.y);
		float on = step(1.0 - lit_ratio, hash(floor(cell) + floor(wnorm.xz * 3.0) * 17.0));
		col = mix(col, vec3(0.08, 0.1, 0.16), win);
		lit = win * on;
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
	EMISSION = window_light * lit * glow;
}
