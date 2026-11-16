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

const SIL_FILL := Color(0.03, 0.06, 0.09)       ## a masked item: this flat dark fill ...
const SIL_RIM := 0.05                            ## ... and a rim of this width (model units) in the rarity colour

func pose(id: String, yaw: float) -> void:
	var lk: Dictionary = looks.get(id, {})
	if lk.is_empty():
		super.pose(id, yaw)
		_flat(false)
		return
	_set_frame(str(lk.get("frame", "body")))
	_wob.stop_emote()
	_wob.setup(str(lk.get("cls", "wobbler")), str(lk.get("skin", "none")), str(lk.get("hat", "none")), int(lk.get("color", WobblerLooks.DEFAULT_COLOR)))
	_wob.set_weapon("")
	_wob.apply_state({"pos": Vector3.ZERO, "vel": Vector3.ZERO, "yaw": 0.0, "grounded": true, "aim": Vector3(0, -1, 0.35)})   # arm down: a compact pose to fit
	for i in 90: _wob.animate(1.0 / 60.0)
	_flat(lk.has("mask"), Color(lk.get("mask", "ffffff")))
	_pivot.rotation.y = 0.0
	fit_camera()
	_pivot.rotation.y = yaw
	current = id

## A masked item (look["mask"] = the rim colour as a hex string) is drawn as a silhouette: every mesh gets one flat unlit dark
## material (no colour, no texture, no detail) with an inverted-hull rim in `rim`, and the pedestal is hidden. The model never
## shows in its own materials. Baked once, so no per-frame cost; plain materials work on every renderer.
func _flat(on: bool, rim := Color.WHITE) -> void:
	var ped := get_node_or_null("Pedestal") as MeshInstance3D
	if ped != null: ped.visible = not on
	var mat: StandardMaterial3D = null
	if on:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = SIL_FILL
		var hull := StandardMaterial3D.new()
		hull.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hull.albedo_color = rim
		hull.cull_mode = BaseMaterial3D.CULL_FRONT
		hull.grow = true
		hull.grow_amount = SIL_RIM
		mat.next_pass = hull
	for n: Node in _wob.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = mat
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
