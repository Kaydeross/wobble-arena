// Level boxes (MID / HIGH tiers, docs/GRAPHICS.md): flat colour, no textures. Soft cel sun light, a darker band
// where a side meets the ground (cheap contact AO), darker vertical corners, a light bevel along top edges.
// UV = position on the face in metres (v up on side faces), UV2 = the face's size: MapBuilder._append_box.
// grid > 0: the Practice Range's prototype grid (web protoMat): 1 m and 5 m lines, a soft 5 m checker, tone noise.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 albedo : source_color = vec3(0.8);
uniform float edge_dark = 0.13;
uniform float foot_dark = 0.16;
uniform float bevel = 0.6;
uniform float grid = 0.0;
uniform float grid_minor = 0.08;
uniform float grid_major = 0.16;
uniform float cel = 0.35;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

float proto_line(vec2 uv, float cell, float w) {
	vec2 f = abs(fract(uv / cell - 0.5) - 0.5) * cell;
	float d = min(f.x, f.y);
	float aa = fwidth(d) * 1.5 + 1e-4;
	return 1.0 - smoothstep(w, w + aa, d);
}

float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

void fragment() {
	vec3 c = albedo;
	vec2 sz = UV2;
	vec2 d2 = min(UV, sz - UV);
	float up = step(0.6, wnrm.y);
	float side = 1.0 - step(0.6, abs(wnrm.y));
	float aa = fwidth(UV.x) + fwidth(UV.y) + 1e-4;
	// side faces: darker foot (where the box meets the floor) and vertical corners, lighter top lip
	float foot = 1.0 - smoothstep(0.0, min(0.45, sz.y * 0.3) + aa, UV.y);
	float corner = 1.0 - smoothstep(0.0, 0.1 + aa, d2.x);
	float lip = 1.0 - smoothstep(0.0, 0.07 + aa, sz.y - UV.y);
	c *= 1.0 - side * (foot_dark * foot + edge_dark * corner * 0.7);
	c = mix(c, c * 1.15 + 0.025, side * lip * bevel);
	// top faces: a thin bright bevel round the rim
	float rim = 1.0 - smoothstep(0.0, 0.09 + aa, min(d2.x, d2.y));
	c = mix(c, c * 1.16 + 0.03, up * rim * bevel * 1.2);
	if (grid > 0.0) {
		vec3 an = abs(wnrm);
		vec2 uv = an.y > 0.6 ? wpos.xz : (an.x > an.z ? wpos.zy : wpos.xy);
		float g1 = proto_line(uv, 1.0, 0.018);
		float g5 = proto_line(uv, 5.0, 0.04);
		float ck = mod(floor(uv.x / 5.0) + floor(uv.y / 5.0), 2.0);
		float nz = hash2(floor(uv));
		c *= (1.0 - grid_minor * g1 - grid_major * g5) * (0.975 + 0.035 * ck) * (0.985 + 0.03 * nz);
	}
	ALBEDO = c;
	ROUGHNESS = 0.92;
}

// soft cel: a quick ramp from shade to light round the terminator instead of a long lambert gradient
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lam = clamp(ndl, 0.0, 1.0);
	float ramp = smoothstep(-0.02, 0.32, ndl) * 0.8 + lam * 0.2;
	DIFFUSE_LIGHT += mix(lam, ramp, cel) * ATTENUATION * LIGHT_COLOR / PI;
}
