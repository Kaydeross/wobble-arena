// Gentle screen vignette (MID / HIGH tiers): darkens the corners a little, drawn under the HUD.
shader_type canvas_item;

uniform float strength = 0.16;
uniform float inner = 0.7;
uniform float outer = 1.25;

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	p.x *= mix(1.0, aspect, 0.5);
	float k = smoothstep(inner, outer, length(p));
	COLOR = vec4(0.02, 0.03, 0.06, k * strength);
}
