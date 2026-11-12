extends SceneTree
## Title-screen layout test (headless): instances scenes/main.tscn in a viewport the size of the stretched canvas
## for several window sizes (iPhone landscape 852x393, 1170x540, 1280x720, iPhone portrait 390x844), with and
## without phone safe-area insets, and checks that the main controls stay inside the safe area, do not overlap
## each other and that no label is squeezed below its text size.
##   godot --headless --path godot --script res://tests/ui_layout_test.gd -- --no-save   (npm run test:godot-ui)

const BASE := Vector2(1170, 540)   ## project.godot viewport size (stretch canvas_items, aspect expand)
## window size in points, safe-area insets in points (left, top, right, bottom) like an iPhone 15 / 16
const CASES := [
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1170, 540), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1280, 720), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(390, 844), [0.0, 59.0, 0.0, 34.0]],
]
## Controls (paths under Main) that must not overlap each other.
const BLOCKS := ["Safe/Col/Top/Logo", "Safe/Col/Top/GuestChip", "Safe/Col/Body/Play", "Safe/Col/Body/Picks", "Safe/Col/Tip", "Safe/Col/Build"]
const INSIDE := ["Safe/Col/Body/Picks/Box/ClassRow/Class", "Safe/Col/Body/Picks/Box/MapRow/Map", "Safe/Col/Body/Picks/Box/FpsRow/Fps"]

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

## The 2D canvas size Godot uses for a window (stretch mode canvas_items, aspect expand).
static func canvas_size(win: Vector2) -> Vector2:
	var k := minf(win.x / BASE.x, win.y / BASE.y)
	return (win / k).round()

func _run() -> void:
	for c: Array in CASES:
		for with_insets in [false, true]:
			await _case(c[0], c[1] if with_insets else [0.0, 0.0, 0.0, 0.0])
	SafeArea.override = []
	print("UI ok" if fails == 0 else "UI layout checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _case(win: Vector2, ins_pt: Array) -> void:
	var cs := canvas_size(win)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	for i in 4:
		await process_frame
	var tag := "%dx%d%s" % [win.x, win.y, " safe" if ins_pt != [0.0, 0.0, 0.0, 0.0] else ""]
	var safe := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	var rects := {}
	for p: String in BLOCKS + INSIDE:
		var n: Control = main.get_node(p)
		var r := n.get_global_rect()
		rects[p] = r
		check(n.is_visible_in_tree(), "%s %s visible" % [tag, p])
		check(r.size.x >= 1.0 and r.size.y >= 1.0, "%s %s has a size (%s)" % [tag, p, r])
		check(safe.grow(0.5).encloses(r), "%s %s %s inside the safe area %s" % [tag, p, r, safe])
	for i in BLOCKS.size():
		for j in range(i + 1, BLOCKS.size()):
			var a: Rect2 = rects[BLOCKS[i]]
			var b: Rect2 = rects[BLOCKS[j]]
			check(not a.grow(-0.5).intersects(b.grow(-0.5)), "%s %s %s overlaps %s %s" % [tag, BLOCKS[i], a, BLOCKS[j], b])
	# the whole column fits (containers would otherwise overflow past the bottom)
	var col: Control = main.get_node("Safe/Col")
	check(col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, col.get_combined_minimum_size().y, safe.size.y])
	_labels_fit(main, tag)
	print("UI %s canvas %dx%d checked" % [tag, cs.x, cs.y])
	vp.queue_free()
	await process_frame

## No label is narrower than its text (clipped) unless it is meant to clip or wrap.
func _labels_fit(n: Node, tag: String) -> void:
	if n is Label and n.is_visible_in_tree():
		var l := n as Label
		if not l.clip_text and l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var need := l.get_minimum_size()
			check(l.size.x + 0.5 >= need.x and l.size.y + 0.5 >= need.y, "%s label '%s' clipped (%s < %s)" % [tag, l.text, l.size, need])
	for c in n.get_children():
		_labels_fit(c, tag)
