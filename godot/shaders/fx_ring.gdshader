// Shockwave / landing / bounce-pad ring (FxSystem "rings" pool): one flat quad per ring.
// The band is a deliberately faceted polygon with hot and dark edges, matching the low-poly world.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float sector = 6.28318530718 / 12.0;
	float local = mod(a + sector * 0.5, sector) - sector * 0.5;
	// Transform the circular distance into a twelve-sided polygon without a texture.
	float r = length(p) * cos(local) / cos(sector * 0.5);
	float hot = smoothstep(0.68, 0.78, r) * (1.0 - smoothstep(0.82, 0.9, r));
	float wake = smoothstep(0.82, 0.9, r) * (1.0 - smoothstep(0.96, 1.02, r));
	float broken = mix(0.58, 1.0, smoothstep(0.12, 0.34, abs(sin(a * 6.0))));
	vec3 edge_col = mix(COLOR.rgb * 0.34, vec3(1.0, 0.95, 0.76), hot);
	ALBEDO = edge_col;
	ALPHA = COLOR.a * (hot + wake * 0.24) * broken;
}
