class_name LockerStage
extends CharacterStage
## The Walldrobe / Shop 3D stage: CharacterStage (same lights, pedestal, one SubViewport) posing any look, not only the
## one in Settings. Looks are registered under a key: `looks[key] = {cls, skin, hat, color, frame}` (frame "head"
## moves the camera in for hat cards), then bake(keys) renders each once into `baked[key]` (queued: a second
## bake() call while one runs is added to it) and preview(look) shows a look live, slowly turning, with an optional
## emote playing on it (emote(id)).
## The camera fits itself to every look (fit_camera): the visible meshes' bounds, wide enough for the model to turn,
## so tall hats (wizard, bunny ears, cone, halo), big classes and outfits taller than the head are never cut off.

const BODY_CAM := [Vector3(0, 1.55, 5.3), Vector3(0, 1.0, 0)]
const HEAD_CAM := [Vector3(0, 2.45, 3.0), Vector3(0, 2.05, 0)]

var looks := {}                 ## key -> look
var _queue: Array = []

static func look_key(lk: Dictionary) -> String:
	return "live|%s|%s|%s|%d" % [lk.get("cls", "wobbler"), lk.get("skin", "none"), lk.get("hat", "none"), int(lk.get("color", 0))]

func pose(id: String, yaw: float) -> void:
	var lk: Dictionary = looks.get(id, {})
	if lk.is_empty():
		super.pose(id, yaw)
		return
	_set_frame(str(lk.get("frame", "body")))
	_wob.stop_emote()
	_wob.setup(str(lk.get("cls", "wobbler")), str(lk.get("skin", "none")), str(lk.get("hat", "none")), int(lk.get("color", WobblerLooks.DEFAULT_COLOR)))
	_wob.set_weapon("")
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -1, 0.35)})   # arm down: a compact pose to fit
	for i in 90: _wob.animate(1.0 / 60.0)
	_pivot.rotation.y = 0.0
	fit_camera()
	_pivot.rotation.y = yaw
	current = id

## Renders every key once (queued behind a bake already running).
func bake(ids: Array) -> void:
	for id: String in ids:
		if not baked.has(id) and not _queue.has(id): _queue.append(id)
	if is_baking(): return
	while not _queue.is_empty():
		var batch := _queue.duplicate()
		_queue.clear()
		await super.bake(batch)
		if not is_inside_tree(): return

## Forget the renders whose key starts with `prefix` (the look they were made with changed).
func forget(prefix: String) -> void:
	for k: String in baked.keys():
		if k.begins_with(prefix): baked.erase(k)

## Show `lk` live (turning) on the stage.
func preview(lk: Dictionary) -> void:
	var key := look_key(lk)
	var l2 := lk.duplicate()
	l2["frame"] = "body"
	looks[key] = l2
	live(key)

## Plays an emote on the live look (the wobbler stops turning while it dances).
func emote(id: String) -> bool:
	return _wob.play_emote(id)

func wobbler() -> Wobbler:
	return _wob

func _process(dt: float) -> void:
	if not _wob.is_emoting():
		super._process(dt)
		return
	_pivot.rotation.y = lerp_angle(_pivot.rotation.y, 0.35, minf(1.0, dt * 4.0))   # face the camera while dancing
	_spin = _pivot.rotation.y
	_wob.animate(dt)
