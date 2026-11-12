// Shockwave / landing / bounce-pad ring (FxSystem "rings" pool): one flat quad per ring, the band drawn here.
// The MultiMesh instance colour arrives in COLOR (rgb tint, a = fade over the ring's life).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float band = smoothstep(0.66, 0.84, r) * (1.0 - smoothstep(0.9, 1.0, r));
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a * band;
}
