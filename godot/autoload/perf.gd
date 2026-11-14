extends Node
## Applies the performance preferences (autoload `Perf`), once at start and whenever they change:
##   Settings > Graphics > "Frame rate cap"   30 / 60 / 120 / Unlimited -> Engine.max_fps. The main battery and heat
##                                           control on a phone; a cap also keeps a 90/120 Hz display from rendering
##                                           frames nobody asked for.
##   Settings > Graphics > "Render scale"     0.6 .. 1.0 -> the root viewport's scaling_3d_scale. The 3D scene is
##                                           rendered at a lower resolution while the interface stays full-resolution.
## Headless and `--no-save` test runs are never capped: a cap would make every test that waits for frames run at 60 fps
## instead of as fast as the machine can go, and the graphics benchmark must be able to run with vsync off. The setting
## is still stored and applied as soon as the game runs normally.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(_on_setting)
	apply()

## A test or benchmark run (`--no-save` is what every tools/test-*.js passes) owns Engine.max_fps itself.
static func _test_run() -> bool:
	return OS.get_cmdline_user_args().has("--no-save")

func _on_setting(key: String, _value: Variant) -> void:
	if key == "fps_cap" or key == "render_scale":
		apply()

## The Engine.max_fps value the current setting asks for (0 = unlimited). Pure, so tests can check the mapping.
static func target_fps(cap: int) -> int:
	return maxi(cap, 0)

func apply() -> void:
	var cap := int(Settings.get_value("fps_cap", 60))
	Engine.max_fps = target_fps(cap) if DisplayServer.get_name() != "headless" and not _test_run() else 0
	var rs := clampf(float(Settings.get_value("render_scale", 1.0)), 0.5, 1.0)
	if is_inside_tree() and get_tree().root != null:
		get_tree().root.scaling_3d_scale = rs
