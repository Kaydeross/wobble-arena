extends SceneTree
## Pack selector + pack transition screenshots (needs a real renderer, opens a window; run by hand, never in CI):
##   godot --path godot --resolution 852x393 --script res://tests/pack_selector_shots.gd -- --no-save --shot transitions --dir DIR
##   godot --path godot --resolution 852x393 --script res://tests/pack_selector_shots.gd -- --no-save --shot selector --dir DIR [--lang fr]
## transitions: 4 frames (p = 0.1, 0.35, 0.6, 0.9) per pack, drawn over the real title, each exact (the transition is scrubbed, no clock).
## selector: every pack centred, locked and owned.
var ps: Array = [0.1, 0.25, 0.4, 0.5, 0.6, 0.75, 0.9]
var shot := "transitions"
var dir := "/private/tmp/claude-501/pack-shots/E1"
var queue: Array = []
var wait := 0
var cur: Array = []
var main: Control
var tr_node: PackTransition

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--dir" and k + 1 < a.size(): dir = a[k + 1]
		elif a[k] == "--ps" and k + 1 < a.size():
			ps = []
			for x: String in a[k + 1].split(","): ps.append(float(x))
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var a := OS.get_cmdline_user_args()
	var lang := "en"
	for k in a.size():
		if a[k] == "--lang" and k + 1 < a.size(): lang = a[k + 1]
	if lang != "en": root.get_node("Lang").apply(lang)
	DirAccess.make_dir_recursive_absolute(dir)
	var content: Node = root.get_node("Content")
	for kv in [["kitchen_chaos", "Kitchen Chaos"], ["toy_workshop", "Toy Workshop"], ["backyard_bbq", "Backyard BBQ"]]:
		if not content.maps.has(kv[0]):
			var m: Dictionary = (content.maps["arena"] as Dictionary).duplicate(true)
			m["name"] = kv[1]
			content.maps[kv[0]] = m
	root.get_node("Save").coins = 2300
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	root.add_child(main)
	if shot == "transitions":
		for pk: String in ["construction", "kitchen", "xmas", "australia"]:
			for p: float in ps:
				queue.append([pk, p, "%s/transition-%s-%d.png" % [dir, pk, int(p * 100)]])
	else:
		for pk: String in ["construction", "kitchen", "xmas", "australia"]:
			for own: bool in [false, true]:
				queue.append([pk, own, "%s/selector-%s-%s-%s.png" % [dir, pk, "owned" if own else "locked", lang]])
	wait = 30
	process_frame.connect(_step)

func _step() -> void:
	wait -= 1
	if wait > 0: return
	if not cur.is_empty():
		var img := root.get_texture().get_image()
		img.save_png(cur[2])
		print("SHOT ", cur[2])
		if tr_node != null and is_instance_valid(tr_node):
			tr_node.finished = true
			tr_node.free()
			tr_node = null
	if queue.is_empty():
		quit(0)
		return
	cur = queue.pop_front()
	if shot == "transitions":
		PackTransition.force_run = true
		var n := PackTransition.new()
		n.setup(cur[0], Callable(), Callable())
		n.manual = true
		root.add_child(n)
		n.scrub(cur[1])
		tr_node = n
		wait = 3
	else:
		var sv: Node = root.get_node("Save")
		sv.dlc = DlcSave.fresh()
		sv.codes = []
		if cur[1]: DlcSave.set_owned(sv.dlc, "construction" if cur[0] == "construction" else cur[0], true)
		main.open_packs(cur[0])
		wait = 40
