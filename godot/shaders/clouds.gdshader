// Drifting flat cloud layer (MID / HIGH tiers): one big horizontal quad high over the level, value-noise blobs with a
// crisp edge (stylised, like the web game's flat clouds), scrolling slowly with TIME, faded out before the camera's
// far plane so its edge never shows. One draw call, no textures.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 col : source_color = vec3(1.0);
uniform vec3 shade : source_color = vec3(0.85, 0.9, 0.97);
uniform float cover = 0.62;
uniform float opacity = 0.75;
uniform vec2 drift = vec2(1.6, 0.5);
uniform float scale = 120.0;
uniform float fade0 = 200.0;
uniform float fade1 = 340.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = (wpos.xz + drift * TIME) / scale;
	float n = vnoise(uv) * 0.6 + vnoise(uv * 2.13 + 7.1) * 0.28 + vnoise(uv * 4.7 + 3.3) * 0.12;
	float aa = fwidth(n) * 1.2 + 1e-4;
	float a = smoothstep(cover, cover + aa + 0.015, n);
	float r = length(wpos.xz);
	a *= 1.0 - smoothstep(fade0, fade1, r);
	a *= smoothstep(10.0, 40.0, wpos.y - CAMERA_POSITION_WORLD.y);   // only seen from well below (not the high preview camera)
	ALBEDO = mix(shade, col, smoothstep(cover, cover + 0.14, n));
	ALPHA = a * opacity;
}
