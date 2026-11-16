extends SceneTree
## Pack landing screenshots (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/pack_landing_shots.gd -- --no-save --pack kitchen [--owned] [--lang fr]
##        [--times 0.6,2.4,4.2] --out /private/tmp/claude-501/pack-shots/E2/kitchen_locked_852x393.png
## One run = one pack / state / size; --times takes one picture per listed second (the file name gets _t<N>), animated scenes differ between them.
## Pack arenas this tree does not have get a stand-in so the packs show up at all (the images then say nothing about the real arenas).
var pack := "kitchen"
var owned := false
var out := "shot.png"
var times: Array = [0.8]
var t := 0.0
var shot_i := 0
var main: Control

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--pack" and k + 1 < a.size(): pack = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
		elif a[k] == "--owned": owned = true
		elif a[k] == "--times" and k + 1 < a.size():
			times = []
			for s: String in a[k + 1].split(","): times.append(float(s))
	process_frame.connect(_start, CONNECT_ONE_SHOT)

func _start() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--lang" and k + 1 < a.size(): root.get_node("Lang").apply(a[k + 1])
	var content: Node = root.get_node("Content")
	for kv in [["kitchen_chaos", "Kitchen Chaos"], ["toy_workshop", "Toy Workshop"], ["backyard_bbq", "Backyard BBQ"]]:
		if not content.maps.has(kv[0]):
			var m: Dictionary = (content.maps["arena"] as Dictionary).duplicate(true)
			m["name"] = kv[1]
			content.maps[kv[0]] = m
	var sv: Node = root.get_node("Save")
	sv.coins = 2300
	if owned: DlcSave.set_owned(sv.dlc, pack, true)
	main = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	root.add_child(main)
	main.open_hub(pack)
	process_frame.connect(_tick)

func _tick() -> void:
	t += 1.0 / 60.0 if Engine.max_fps <= 0 else 1.0 / float(Engine.max_fps)
	t = maxf(t, float(Time.get_ticks_msec()) / 1000.0 - start_ms)
	if shot_i >= times.size():
		quit(0)
		return
	if t < float(times[shot_i]): return
	var img := root.get_texture().get_image()
	var path := out if times.size() == 1 else out.get_basename() + "_t%d" % shot_i + "." + out.get_extension()
	img.save_png(path)
	print("SHOT ", path, " ", img.get_size())
	shot_i += 1

var start_ms := float(Time.get_ticks_msec()) / 1000.0
