// Contact shadow blob under a fighter (LOW tier, where fighters do not cast real shadows): a soft dark disc on a quad.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform float strength = 0.38;
uniform float fade = 1.0;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	ALBEDO = vec3(0.0);
	ALPHA = strength * (1.0 - smoothstep(0.35, 1.0, r)) * fade;
}
