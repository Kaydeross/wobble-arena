extends Node
## Player preferences (autoload `Settings`): flat key/value store persisted with ConfigFile at user://settings.cfg.
## Defaults mirror the web game's `settings`/`TC` objects (public/index.html ~1449, ~9154). Later phases add keys here.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"
const DEFAULTS := {
	"sens": 1.0,            # look sensitivity multiplier
	"fov": 72.0,            # vertical field of view
	"cam_dist": 1.0,        # camera distance multiplier
	"invert_y": false,
	"touch_mode": "auto",   # auto | on | off
	"touch_lefty": false,
	"touch_scale": 1.0,
	"touch_opacity": 0.85,
	"touch_assist": true,
	"class": "wobbler",     # character class (shared/classes.json id)
	"color": 0x39b5a8,      # body colour (the web player's default)
}

var _cfg := ConfigFile.new()
var persist := true   ## tests turn this off so they never write the user's file

func _init() -> void:
	if OS.get_cmdline_user_args().has("--no-save"):
		persist = false
		return
	_cfg.load(PATH)   # missing file = defaults

func get_value(key: String, default: Variant = null) -> Variant:
	if default == null:
		default = DEFAULTS.get(key)
	return _cfg.get_value(SECTION, key, default)

func set_value(key: String, value: Variant) -> void:
	if _cfg.has_section_key(SECTION, key) and _cfg.get_value(SECTION, key) == value:
		return
	_cfg.set_value(SECTION, key, value)
	if persist:
		_cfg.save(PATH)
	changed.emit(key, value)

func reset(key: String) -> void:
	if _cfg.has_section_key(SECTION, key):
		_cfg.erase_section_key(SECTION, key)
		if persist:
			_cfg.save(PATH)
		changed.emit(key, get_value(key))
