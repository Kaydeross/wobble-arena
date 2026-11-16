shader_type canvas_item;
// The On Fire pack's transition: a kitchen ignition. A ring of fire spreads from the stove burner in the middle of the screen
// (`cover` 0..1; blue gas at first, then orange and red), heat haze bends the picture just ahead of the front, and later the
// fire thins into steam and smoke that dissolves away (`reveal` 0..1) with a soft edge. One fullscreen ColorRect; every value
// is a function of the uniforms (no TIME), so a screenshot at any moment is exact.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float cover = 0.0;
uniform float reveal = 0.0;
uniform float ftime = 0.0;
uniform float aspect = 1.78;
uniform float blue = 1.0;
uniform float haze = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { return vnoise(p) * 0.55 + vnoise(p * 2.1 + 3.7) * 0.3 + vnoise(p * 4.3 - 1.9) * 0.15; }

void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float r = length(d);
	float ang = atan(d.y, d.x) / 6.28318;
	float maxr = length(vec2(aspect, 1.0) * 0.5) + 0.4;
	// the front rolls outward; its edge is a slow sum of angular waves, so it licks rather than jags
	float rough = 0.6 * sin(ang * 6.28318 * 5.0 + ftime * 1.7) + 0.4 * sin(ang * 6.28318 * 11.0 - ftime * 2.3 + 1.7);
	float front = cover * maxr + rough * 0.05 * smoothstep(0.0, 0.2, cover) * (1.0 - smoothstep(0.8, 1.0, cover));
	float d_in = front - r;
	float fire_a = smoothstep(0.0, 0.08, d_in);
	// the body: charred pan-black with churning embers, red and orange nearer the front, blue gas on the very edge early on
	float n = fbm(d * 3.0 + vec2(0.0, -ftime * 0.5));
	float heat = clamp(1.0 - smoothstep(0.0, 0.5, d_in) + (n - 0.5) * 0.45, 0.0, 1.0);
	vec3 col = mix(vec3(0.12, 0.04, 0.03), vec3(0.42, 0.11, 0.04), n);
	col = mix(col, vec3(0.86, 0.14, 0.05), smoothstep(0.15, 0.5, heat));
	col = mix(col, vec3(1.0, 0.52, 0.08), smoothstep(0.45, 0.78, heat));
	col = mix(col, vec3(1.0, 0.92, 0.55), smoothstep(0.8, 1.0, heat) * (1.0 - blue * 0.6));
	col = mix(col, vec3(0.3, 0.62, 1.0), blue * smoothstep(0.35, 0.95, heat));
	// the reveal: the fire cools to steam and the smoke dissolves, soft edged
	float n2 = fbm(UV * vec2(aspect, 1.0) * 2.4 + vec2(ftime * 0.12, -ftime * 0.22));
	float clear = smoothstep(n2 - 0.2, n2 + 0.2, reveal * 1.75 - 0.35);
	float edge = clear * (1.0 - clear) * 4.0;
	vec3 steam = vec3(0.84, 0.83, 0.86);
	col = mix(col, steam, smoothstep(0.0, 0.7, reveal) * 0.85 + edge * 0.15);
	fire_a *= 1.0 - clear;
	// heat haze: the picture just ahead of the front wobbles
	float hz = (1.0 - smoothstep(0.0, 0.3, -d_in)) * step(d_in, 0.0) * smoothstep(0.02, 0.12, cover) * haze * (1.0 - smoothstep(0.9, 1.0, cover));
	vec3 dist = vec3(0.0);
	if (hz > 0.001) {
		vec2 off = vec2(sin(UV.y * 70.0 + ftime * 5.0) + sin(UV.y * 31.0 - ftime * 3.0), cos(UV.x * 55.0 - ftime * 4.0)) * 0.0045 * hz;
		dist = texture(screen_tex, SCREEN_UV + off).rgb;
	}
	float a = fire_a + hz * (1.0 - fire_a);
	if (a < 0.002) { discard; }
	vec3 rgb = (col * fire_a + dist * hz * (1.0 - fire_a)) / a;
	COLOR = vec4(rgb, a);
}
