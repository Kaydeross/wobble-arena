extends SceneTree
## Pictures of breakable props (needs a real renderer, opens a window):
##   godot --path godot --resolution 960x540 --script res://tests/destruct_shots.gd -- --no-save --out DIR [map ...]
## For each map: a breakable (one with decor on it, a tree crown, when there is one) before, then a strip of moments
## after it breaks (shatter, settle, sink). Saves DIR/destruct-<map>-<step>.png.

const FRAME := 1.0 / 60.0
const STEPS := [["0-before", 0], ["1-break", 4], ["2-fly", 14], ["3-settle", 45], ["4-sink", 100], ["5-gone", 170]]

var out_dir := "."
var ids: Array = []
var k := 0
var world: Node
var step := 0
var frames := 0
var prop := -1

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]; i += 1
		elif not a[i].begins_with("--"): ids.append(a[i])
		i += 1
	if ids.is_empty(): ids = ["beach", "haunted", "candy", "arena"]
	Engine.max_fps = 60                 # the strip's moments are frame counts
	process_frame.connect(_next, CONNECT_ONE_SHOT)

func _next() -> void:
	if world: world.free(); world = null
	if k >= ids.size():
		quit(0); return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = ids[k]
	world.auto_run = false
	world.bot_count = 0
	world.rng_seed = 777
	world.dyn_choice = "off"
	root.add_child(world)
	world.touch.visible = false
	for n in ["UI", "HUD"]:
		var ui := world.get_node_or_null(n)
		if ui is CanvasItem: (ui as CanvasItem).visible = false
		elif ui is CanvasLayer: (ui as CanvasLayer).visible = false
	world.set_process(false)
	for v in world.views.values(): v.visible = false
	var d: Destruct = world.sim.destruct
	prop = -1
	if d != null:
		for i in d.props.size():
			if d.props[i].get("crown") != null: prop = i; break
		if prop < 0 and d.props.size() > 0: prop = 0
	print("MAP ", ids[k], " props=", d.total() if d else 0, " pick=", prop, " crown=", d != null and prop >= 0 and d.props[prop].get("crown") != null)
	if prop < 0:
		k += 1; _next.call_deferred(); return
	var p: Dictionary = d.props[prop]
	var c := Vector3(float(p["x"]), float(p["bottom"]) + float(p["h"]) * 0.5, float(p["z"]))
	var cam: Camera3D = world.cam
	cam.fov = 55.0
	var dist := 6.0 + float(p["h"]) * 0.9
	cam.look_at_from_position(c + Vector3(dist * 0.8, float(p["h"]) * 0.5 + 1.6, dist * 0.6), c + Vector3(0, 0.3, 0), Vector3.UP)
	step = 0; frames = 0
	process_frame.connect(_frame)

func _frame() -> void:
	frames += 1
	if frames < 10: return
	var t := frames - 10
	if t == 1:
		var d: Destruct = world.sim.destruct
		d.break_hit(prop, 1.0e6, [-0.8, 0.0, -0.6])
		world.present(0.0)
	if step < STEPS.size() and t == int(STEPS[step][1]) + (0 if step == 0 else 1):
		await RenderingServer.frame_post_draw
		var path := out_dir.path_join("destruct-%s-%s.png" % [ids[k], STEPS[step][0]])
		root.get_texture().get_image().save_png(path)
		print("SHOT ", path)
		step += 1
	if step >= STEPS.size():
		process_frame.disconnect(_frame)
		k += 1
		_next.call_deferred()
