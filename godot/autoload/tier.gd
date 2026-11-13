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

## Headless runs have no real window (64x64): the UI scale stays 1 unless a test turns this on (tests/hud_test.gd).
var force_ui_scale := false

func _ready() -> void:
	# Settings is the next autoload: hook the UI scale up once every autoload is in the tree
	_hook_ui_scale.call_deferred()

func _hook_ui_scale() -> void:
	var root := get_tree().root
	root.size_changed.connect(apply_ui_scale)
	var st := root.get_node_or_null("Settings")
	if st: st.changed.connect(func(k: String, _v: Variant) -> void: if k == "ui_scale" or k == "touch_mode": apply_ui_scale())
	apply_ui_scale()

## The global UI size (Settings `ui_scale`, UiScale): the root window's content scale factor, so every menu, the HUD
## and the touch layer keep 44 pt touch targets on small phones. Called on start, on a resize and when it changes.
func apply_ui_scale() -> void:
	var root := get_tree().root if is_inside_tree() else null
	if root == null or (DisplayServer.get_name() == "headless" and not force_ui_scale): return
	var st := root.get_node_or_null("Settings")
	var mode := str(st.get_value("ui_scale", "auto")) if st else "auto"
	var touch := touch_default() or (st != null and str(st.get_value("touch_mode", "auto")) == "on")
	var f := UiScale.factor(Vector2(root.size) / UiScale.px_per_pt(), mode, touch)
	if not is_equal_approx(root.content_scale_factor, f):
		root.content_scale_factor = f

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

## Graphics quality the look follows (docs/GRAPHICS.md): HIGH = PC (Forward+), MID = phones (Mobile renderer, the
## iPhone 12 budget), LOW = web (Compatibility). Every post effect, shader variant and extra scenery layer checks this.
enum Quality { LOW, MID, HIGH }

func quality() -> Quality:
	var q := max_quality()
	var st := get_node_or_null("/root/Settings") if is_inside_tree() else null
	if st:   # Settings > Graphics > Effects: lower than the device can do saves battery; never higher than its renderer
		var want: int = {"low": Quality.LOW, "medium": Quality.MID, "high": Quality.HIGH}.get(str(st.get_value("fx_quality", "auto")), q)
		return mini(want, q) as Quality
	return q

## What this device's renderer can do (the "Auto" effects level).
func max_quality() -> Quality:
	match kind:
		Kind.PC: return Quality.HIGH
		Kind.MOBILE: return Quality.MID
	return Quality.LOW

## The Tier autoload's quality as an int (0 LOW, 1 MID, 2 HIGH) from static code (MapBuilder, Wobbler, Gfx); HIGH
## when the autoload is not there.
static func q() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var t: Node = tree.root.get_node_or_null("Tier") if tree and tree.root else null
	return int(t.quality()) if t else 2

## Directional shadow settings for the sun. `area` is the map's shadow half-size (maps.json `shadow`, default 32).
## HIGH: 3 PSSM cascades (crisp near the fighters, the whole level in range), soft PCF blur. MID: 2 cascades, a
## little blur (2048 map, soft filter quality 1 in project.godot). LOW: one orthogonal map, no blur; fighters use
## blob shadows there (BlobShadow) and do not cast.
func configure_sun(sun: DirectionalLight3D, area: float) -> void:
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.0
	match kind:
		Kind.PC:
			sun.shadow_normal_bias = 2.0     # 4 cascades + PCF blur show acne on sunlit flat faces at the default
			sun.shadow_bias = 0.06
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_split_1 = 0.08
			sun.directional_shadow_split_2 = 0.22
			sun.directional_shadow_split_3 = 0.5
			sun.directional_shadow_blend_splits = true
			sun.directional_shadow_max_distance = area * 2.6
			sun.directional_shadow_fade_start = 0.85
			sun.shadow_blur = 1.3
			sun.shadow_opacity = 0.92
		Kind.MOBILE:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_split_1 = 0.22
			sun.directional_shadow_blend_splits = false
			sun.directional_shadow_max_distance = area * 1.9
			sun.directional_shadow_fade_start = 0.8
			sun.shadow_blur = 1.2
			sun.shadow_opacity = 0.9
		_:
			# one cascade: cheapest in WebGL
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = area * 1.6
			sun.shadow_blur = 1.0
			sun.shadow_opacity = 0.85

## Viewport-level quality switches (MSAA, scaling). Called once by World.
func configure_viewport(vp: Viewport) -> void:
	match kind:
		Kind.PC:
			vp.msaa_3d = Viewport.MSAA_4X
		Kind.MOBILE:
			vp.msaa_3d = Viewport.MSAA_2X
		Kind.WEB:
			vp.msaa_3d = Viewport.MSAA_DISABLED
