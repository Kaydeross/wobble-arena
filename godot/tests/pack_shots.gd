extends SceneTree
## DLC pack pictures: weapons and cosmetics of the Kitchen, Xmas and Australia packs (needs a real renderer, opens a window):
##   godot --path godot --resolution 1280x720 --script res://tests/pack_shots.gd -- --no-save --out DIR [--what weapons|held|looks|all] [--pack kitchen|xmas|australia]
## weapons: DIR/weapons-<pack>.png (three-quarter view), DIR/weapons-<pack>-side.png (side-on silhouettes) and DIR/weapon-<id>.png (each alone, big)
## held:    DIR/held-<pack>.png (six Wobblers holding the pack weapons) and DIR/held-<id>.png (one close-up each)
## looks:   DIR/looks-<pack>.png (every hat and outfit of the pack, front then back) and DIR/look-<id>.png (a close-up of each)

const PACKS := {
	"kitchen": ["fryingpan", "cleaver", "flambetorch", "rollingpin", "peppergrinder", "souppot"],
	"xmas": ["candycane", "snowballcannon", "giftbomb", "tinselwhip", "ornamentlauncher", "toymallet"],
	"australia": ["cricketbat", "aussieboomerang", "thongslapper", "vegemitejar", "bbqtongs", "didgeridooblaster"],
}

const GUNS := ["flambetorch", "peppergrinder", "snowballcannon", "ornamentlauncher", "didgeridooblaster"]

var out_dir := "."
var what := "all"
var only := ""
var stage: Node3D


func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--out" and i + 1 < a.size(): out_dir = a[i + 1]
		elif a[i] == "--what" and i + 1 < a.size(): what = a[i + 1]
		elif a[i] == "--pack" and i + 1 < a.size(): only = a[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name))
	print("SHOT ", name)


func _frames(n: int) -> void:
	for i in n: await process_frame


func _go() -> void:
	for pack: String in PACKS:
		if only != "" and only != pack: continue
		if what == "all" or what == "weapons": await _weapons(pack)
		if what == "all" or what == "held": await _held(pack)
		if what == "all" or what == "looks": await _looks(pack)
	quit(0)


func _stage(bg := 0xbfe3f2) -> void:
	stage = Node3D.new()
	root.add_child(stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.hex(bg << 8 | 0xff)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.hex(0xdfe9eeff)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.1
	stage.add_child(sun)
	sun.look_at_from_position(Vector3(2.2, 3.8, 3.2), Vector3.ZERO, Vector3.UP)


func _end_stage() -> void:
	stage.queue_free()
	await _frames(2)


func _model(key: String, h: float) -> Node3D:       # a weapon centred and scaled to fit height h
	var m := WeaponModels.build(key)
	var bb := WeaponModels.bounds(m)
	var holder := Node3D.new()
	m.position = -bb.get_center()
	holder.add_child(m)
	holder.scale = Vector3.ONE * (h / maxf(bb.size.x, maxf(bb.size.y, bb.size.z)))
	return holder


func _weapons(pack: String) -> void:
	var keys: Array = PACKS[pack]
	for side in [false, true]:
		_stage()
		var cam := Camera3D.new()
		cam.fov = 30
		stage.add_child(cam)
		cam.current = true
		for i in keys.size():
			var holder := _model(keys[i], 3.0)
			var outer := Node3D.new()
			outer.position = Vector3((i % 3 - 1) * 3.6, (0.5 - i / 3) * 3.8, 0)
			if not side:
				outer.rotation.y = deg_to_rad(-55)
				outer.rotation.z = deg_to_rad(18)
			elif keys[i] in GUNS:
				outer.rotation.y = deg_to_rad(-90)                  # guns side-on: the barrel and the grip in profile
			outer.add_child(holder)
			stage.add_child(outer)
		cam.look_at_from_position(Vector3(0, 0, 17.0), Vector3.ZERO, Vector3.UP)
		await _frames(6)
		await _save("weapons-%s%s.png" % [pack, "-side" if side else ""])
		await _end_stage()
	for k: String in keys:
		_stage()
		var cam := Camera3D.new()
		cam.fov = 30
		stage.add_child(cam)
		cam.current = true
		var outer := Node3D.new()
		outer.rotation.y = deg_to_rad(-40)
		outer.rotation.z = deg_to_rad(14)
		outer.add_child(_model(k, 3.4))
		stage.add_child(outer)
		cam.look_at_from_position(Vector3(0, 0, 9.0), Vector3.ZERO, Vector3.UP)
		await _frames(4)
		await _save("weapon-%s.png" % k)
		await _end_stage()


func _wobbler(skin: String, hat: String, weapon: String, pos: Vector3, yaw: float) -> Wobbler:
	var w: Wobbler = load("res://actors/wobbler.tscn").instantiate()
	stage.add_child(w)
	w.position = pos
	w.set_skin(skin)
	w.set_hat(hat)
	if weapon != "": w.set_weapon(weapon)
	w.set_meta("yaw", yaw)
	w.set_meta("weapon", weapon)
	return w


func _settle(ws: Array) -> void:
	for f in 24:
		for w: Wobbler in ws:
			w.apply_state({"pos": w.position, "vel": Vector3.ZERO, "yaw": float(w.get_meta("yaw")), "grounded": true,
				"aim": Vector3(0.45, -0.4, 0.8).normalized(), "weapon": str(w.get_meta("weapon"))})
			w.animate(1.0 / 60.0)
		await process_frame


func _held(pack: String) -> void:
	var keys: Array = PACKS[pack]
	_stage()
	var cam := Camera3D.new()
	cam.fov = 30
	stage.add_child(cam)
	cam.current = true
	var ws: Array = []
	for i in keys.size():
		ws.append(_wobbler("none", "none", keys[i], Vector3((i % 3 - 1) * 3.6, -(i / 3) * 3.6 + 1.2, 0), 0.5))
	await _settle(ws)
	cam.look_at_from_position(Vector3(0, -1.0, 26.0), Vector3(0, -1.0, 0), Vector3.UP)
	await _frames(2)
	await _save("held-%s.png" % pack)
	for w: Wobbler in ws: w.queue_free()
	await _frames(2)
	for k: String in keys:
		var w := _wobbler("none", "none", k, Vector3.ZERO, 0.55)
		await _settle([w])
		cam.look_at_from_position(Vector3(1.0, 1.1, 7.2), Vector3(0.1, 0.6, 0), Vector3.UP)
		await _frames(2)
		await _save("held-%s.png" % k)
		w.queue_free()
		await _frames(2)
	await _end_stage()


func _looks(pack: String) -> void:
	var pi: Dictionary = (LockerData.data().get("pack_items", {}) as Dictionary).get(pack, {})
	var hats: Array = (pi.get("hats", []) as Array).duplicate()
	hats.append_array((pi.get("arcade_hats", {}) as Dictionary).values())
	var skins: Array = pi.get("skins", [])
	var items: Array = []
	for h in hats: items.append(["none", h, h])
	for s in skins: items.append([s, "none", s])
	for s in skins:                                         # the outfit with the pack's first hat
		if hats.size() > 0: items.append([s, hats[0], s + "+" + str(hats[0])])
	_stage()
	var cam := Camera3D.new()
	cam.fov = 30
	stage.add_child(cam)
	cam.current = true
	var cols := 5
	for back in [false, true]:
		var ws: Array = []
		for i in items.size():
			var it: Array = items[i]
			ws.append(_wobbler(it[0], it[1], "", Vector3((i % cols - (cols - 1) / 2.0) * 2.5, -(i / cols) * 3.3, 0), (PI - 0.4) if back else 0.4))
		await _settle(ws)
		var rows := (items.size() + cols - 1) / cols
		cam.look_at_from_position(Vector3(0, -(rows - 1) * 1.65 + 0.6, 22.0 + rows * 3.0), Vector3(0, -(rows - 1) * 1.65 + 0.6, 0), Vector3.UP)
		await _frames(2)
		await _save("looks-%s%s.png" % [pack, "-back" if back else ""])
		for w: Wobbler in ws: w.queue_free()
		await _frames(2)
	for it: Array in items:
		var w := _wobbler(it[0], it[1], "", Vector3.ZERO, 0.45)
		await _settle([w])
		cam.fov = 28
		cam.look_at_from_position(Vector3(0.6, 1.7, 8.5), Vector3(0, 1.2, 0), Vector3.UP)
		await _frames(2)
		await _save("look-%s.png" % it[2])
		w.queue_free()
		await _frames(2)
	await _end_stage()
