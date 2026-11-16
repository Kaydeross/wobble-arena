extends SceneTree
## Multi-pack screenshots (needs a real renderer, opens a window):
##   godot --path godot --resolution 852x393 --script res://tests/pack_shots.gd -- --no-save --shot showcase|idle|hub|prematch --pack kitchen [--owned] [--lang fr] --out FILE.png
## Pack arenas that this tree does not have yet (phase C) get a stand-in entry (a copy of 'arena', only its name differs) so the
## packs show up at all; the images say nothing about the real arenas.
var shot := "showcase"
var pack := "kitchen"
var owned := false
var out := "shot.png"
var frames := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for k in a.size():
		if a[k] == "--shot" and k + 1 < a.size(): shot = a[k + 1]
		elif a[k] == "--pack" and k + 1 < a.size(): pack = a[k + 1]
		elif a[k] == "--out" and k + 1 < a.size(): out = a[k + 1]
		elif a[k] == "--owned": owned = true
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
	var m: Control = load("res://scenes/main.tscn").instantiate()
	m.auto_intro = false
	m.auto_news = false
	root.add_child(m)
	if shot == "showcase" or shot == "idle":
		var i := 0
		for k in m.showcase.packs.size():
			if m.showcase.packs[k].pack_id == pack: i = k
		m.showcase._swap_to(i)
		if shot == "showcase": m.showcase.snap(true)
	else:
		m.open_hub(pack)
		if shot == "prematch": m.hub.open_pre()
	frames = 40
	process_frame.connect(_wait)

func _wait() -> void:
	frames -= 1
	if frames > 0: return
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("SHOT ", out)
	quit(0)
