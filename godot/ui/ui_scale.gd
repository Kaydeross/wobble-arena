class_name UiScale
extends RefCounted
## Global UI size (Settings `ui_scale`: auto | small | normal | large), applied by the Tier autoload as the root
## window's content_scale_factor, so every menu, sheet, HUD panel and the touch layer grow together.
##
## The layouts are designed on a 1170x540 canvas (project.godot, stretch canvas_items + aspect expand) with touch
## targets at least DESIGN_TOUCH canvas px. On an iPhone 15 landscape (852x393 pt) that is 44 pt, but on a 667x375
## iPhone SE the canvas is width-bound (1170x658) and the same buttons are only ~34 pt. Every touch mode therefore
## shrinks the canvas until DESIGN_TOUCH px are at least MIN_TOUCH pt. `small` remains denser on mouse-driven devices;
## `large` adds LARGE on top, still never below MIN_CANVAS; `auto` = `normal` on touch screens and `small` with a mouse.
## Tests call the static functions with a window size in points; the autoload passes the real window and screen.

const BASE := Vector2(1170, 540)    ## project.godot viewport size
const MIN_TOUCH := 44.0             ## pt, Apple's minimum touch target
const DESIGN_TOUCH := 60.0          ## canvas px of the smallest touch targets in the layouts
const MIN_CANVAS := Vector2(900, 500)   ## the narrowest / shortest landscape canvas the layouts are checked at
const LARGE := 1.15
const MODES := ["auto", "small", "normal", "large"]

## content_scale_factor for a window of `win_pt` points (`touch`: the device is used with fingers).
static func factor(win_pt: Vector2, mode: String, touch: bool) -> float:
	if win_pt.x < 200.0 or win_pt.y < 200.0: return 1.0
	if mode == "auto": mode = "normal" if touch else "small"
	if win_pt.y > win_pt.x: return 1.0             # portrait shows the landscape layout scaled down
	var k := minf(win_pt.x / BASE.x, win_pt.y / BASE.y)       # pt per canvas px at factor 1
	var want := maxf(1.0, MIN_TOUCH / DESIGN_TOUCH / k)
	if mode == "small" and not touch: return 1.0
	if mode == "large": want *= LARGE
	# never a canvas smaller than MIN_CANVAS (the layouts would overflow), never below the designed size
	var cap := minf(win_pt.x / MIN_CANVAS.x, win_pt.y / MIN_CANVAS.y) / k
	return maxf(1.0, minf(want, maxf(cap, 1.0)))

## The 2D canvas size Godot uses for that window (stretch canvas_items, aspect expand, content scale factor).
static func canvas_size(win_pt: Vector2, mode := "normal", touch := true) -> Vector2:
	var k := minf(win_pt.x / BASE.x, win_pt.y / BASE.y) * factor(win_pt, mode, touch)
	return (win_pt / k).round()

## Points per canvas px for that window.
static func pt_per_px(win_pt: Vector2, mode := "normal", touch := true) -> float:
	return win_pt.x / canvas_size(win_pt, mode, touch).x

## Device pixels per point of the screen the game runs on (iOS / web: the screen scale, Android: dpi / 160).
static func px_per_pt() -> float:
	if OS.has_feature("android"):
		return maxf(1.0, DisplayServer.screen_get_dpi() / 160.0)
	if OS.has_feature("ios") or OS.has_feature("web"):
		return maxf(1.0, DisplayServer.screen_get_scale())
	return 1.0   # desktop: window pixels are what the mouse sees
