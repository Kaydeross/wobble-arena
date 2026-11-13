class_name SafeArea
extends RefCounted
## Safe-area insets (notch / Dynamic Island, home indicator) in canvas units, shared by the title screen, the HUD and
## the touch layer. Phones only: on desktop the OS "safe area" is the screen minus the dock and says nothing about
## our window. Tests set `SafeArea.override` to fake a phone ([left, top, right, bottom] in canvas units).

static var override: Array = []

## [left, top, right, bottom] in the canvas units of `vp` (the stretched 2D canvas).
static func insets(vp: Viewport) -> Array:
	if override.size() == 4:
		return override.duplicate()
	var out := [0.0, 0.0, 0.0, 0.0]
	# the Tier autoload is looked up by path so test scripts (--script) that use this class still compile
	var tier: Node = vp.get_tree().root.get_node_or_null("Tier") if vp and vp.is_inside_tree() else null
	if vp == null or tier == null or not tier.is_mobile() or DisplayServer.get_name() == "headless":
		return out
	var sa := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	var wp := DisplayServer.window_get_position()
	if ws.x <= 0 or ws.y <= 0 or sa.size.x <= 0:
		return out
	var k := vp.get_visible_rect().size / Vector2(ws)
	var left := maxf(0, sa.position.x - wp.x)
	var top := maxf(0, sa.position.y - wp.y)
	var right := maxf(0, (wp.x + ws.x) - sa.end.x)
	var bottom := maxf(0, (wp.y + ws.y) - sa.end.y)
	for cutout: Rect2 in DisplayServer.get_display_cutouts():
		if cutout.position.x <= wp.x and cutout.end.x > wp.x:
			left = maxf(left, cutout.end.x - wp.x)
		if cutout.end.x >= wp.x + ws.x and cutout.position.x < wp.x + ws.x:
			right = maxf(right, (wp.x + ws.x) - cutout.position.x)
		if cutout.position.y <= wp.y and cutout.end.y > wp.y:
			top = maxf(top, cutout.end.y - wp.y)
		if cutout.end.y >= wp.y + ws.y and cutout.position.y < wp.y + ws.y:
			bottom = maxf(bottom, (wp.y + ws.y) - cutout.position.y)
	return [left * k.x, top * k.y, right * k.x, bottom * k.y]

## The visible canvas rect minus the insets.
static func rect(vp: Viewport) -> Rect2:
	var r := vp.get_visible_rect()
	var i := insets(vp)
	return Rect2(r.position + Vector2(i[0], i[1]), r.size - Vector2(i[0] + i[2], i[1] + i[3]))
