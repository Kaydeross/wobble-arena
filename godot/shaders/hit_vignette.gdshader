// Angular damage vignette. The twelve-sided edge and hard facet breaks match the game's
// low-poly silhouettes; intensity is driven only by presentation events.
shader_type canvas_item;

uniform float intensity = 0.0;
uniform vec4 hit_color : source_color = vec4(1.0, 0.18, 0.1, 1.0);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = atan(p.y, p.x);
	float sector = 6.28318530718 / 12.0;
	float local = mod(a + sector * 0.5, sector) - sector * 0.5;
	float poly_r = length(p) * cos(local) / cos(sector * 0.5);
	float edge = smoothstep(0.72, 0.92, poly_r) * (1.0 - smoothstep(1.3, 1.62, poly_r));
	float facets = 0.68 + 0.32 * abs(cos(a * 6.0));
	float pulse = 0.82 + 0.18 * cos(a * 12.0);
	COLOR = vec4(hit_color.rgb, intensity * 0.46 * edge * facets * pulse);
}
