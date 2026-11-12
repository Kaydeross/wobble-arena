extends Node
## Render/platform tier (autoload `Tier`). PC = Forward+ desktop, MOBILE = iOS/Android (Mobile renderer), WEB = web export (Compatibility).
## Heavy effects and per-platform defaults check this instead of OS features directly.
## Override for testing: pass `-- --tier=pc|mobile|web` on the command line.

enum Kind { PC, MOBILE, WEB }

var kind: Kind = Kind.PC

func _init() -> void:
	kind = detect()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tier="):
			var n := a.substr(7).to_upper()
			if Kind.has(n):
				kind = Kind[n]

static func detect() -> Kind:
	if OS.has_feature("web"):
		return Kind.WEB
	if OS.has_feature("mobile") or OS.has_feature("ios") or OS.has_feature("android"):
		return Kind.MOBILE
	return Kind.PC

func is_pc() -> bool:
	return kind == Kind.PC

func is_mobile() -> bool:
	return kind == Kind.MOBILE

func is_web() -> bool:
	return kind == Kind.WEB

func tier_name() -> String:
	return Kind.keys()[kind]

## True when the on-screen touch controls should show by default (phones/tablets, or a web page on a touch device).
func touch_default() -> bool:
	if kind == Kind.MOBILE:
		return true
	if kind == Kind.WEB:
		return DisplayServer.is_touchscreen_available()
	return false

## Directional shadow settings for the sun. `area` is the map's shadow half-size (maps.json `shadow`, default 32).
func configure_sun(sun: DirectionalLight3D, area: float) -> void:
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.5 if kind == Kind.PC else 1.0
	match kind:
		Kind.PC:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = area * 2.4
		_:
			# one cascade: cheapest on phones and in WebGL
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = area * 1.6

## Viewport-level quality switches (MSAA, scaling). Called once by World.
func configure_viewport(vp: Viewport) -> void:
	match kind:
		Kind.PC:
			vp.msaa_3d = Viewport.MSAA_4X
		Kind.MOBILE:
			vp.msaa_3d = Viewport.MSAA_2X
		Kind.WEB:
			vp.msaa_3d = Viewport.MSAA_DISABLED
