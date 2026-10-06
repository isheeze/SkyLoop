shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
// A sea of sunset clouds far below the floating city. Value-noise FBM, lit from one side by
// comparing density with a sample nudged toward the sun.

uniform vec3 deep : source_color = vec3(0.55, 0.6, 0.86);
uniform vec3 shade : source_color = vec3(0.62, 0.56, 0.78);
uniform vec3 lit : source_color = vec3(1.0, 0.78, 0.66);
uniform vec3 glow : source_color = vec3(1.0, 0.93, 0.82);
uniform vec2 sun_dir = vec2(-0.7, -0.5);
uniform float scale = 0.025;
uniform float speed = 0.004;
uniform float coverage = 0.36;

varying vec3 wpos;

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

float density(vec2 p) {
	float n = texture(noise_tex, p).r * 0.65 + texture(noise_tex, p * 2.3 + vec2(0.37, 0.71)).r * 0.35;
	return smoothstep(coverage, coverage + 0.25, n);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz * scale + vec2(TIME * speed, TIME * speed * 0.4);
	float d = density(p);
	float d2 = density(p + normalize(sun_dir) * 0.012);
	float light = clamp(0.55 + (d - d2) * 4.0, 0.0, 1.0);
	vec3 cloud = mix(shade, lit, light);
	cloud = mix(cloud, glow, pow(light, 4.0) * 0.6);
	vec3 col = mix(deep, cloud, d);
	// Fade toward a hazy horizon so the plane has no visible edge.
	float dist = length(wpos.xz);
	col = mix(col, vec3(1.0, 0.78, 0.65), smoothstep(60.0, 260.0, dist));
	ALBEDO = col;
}
