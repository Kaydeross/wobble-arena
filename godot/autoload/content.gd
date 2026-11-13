extends Node
## Game data (autoload `Content`). Reads res://data/*.json, which tools/sync-shared.js copies from shared/ (the source of truth).
## Do not edit res://data by hand: change public/index.html, then `npm run content`. Exception: res://data/extra/
## (Godot-only modes and classes, not copied from shared/; ModeRules.merge_extra / ExtraClasses.merge add them).

const DATA_DIR := "res://data/"

var weapons: Dictionary = {}
var modes: Dictionary = {}
var classes: Dictionary = {}
var cosmetics: Dictionary = {}
var difficulties: Dictionary = {}
var crate_rates: Dictionary = {}
var drops: Dictionary = {}
var maps: Dictionary = {}

func _init() -> void:
	reload()

func reload() -> void:
	weapons = ExtraWeapons.merge(load_json("weapons"))   # + Godot-only weapons (res://data/extra/construction/weapons.json)
	modes = ModeRules.merge_extra(load_json("modes"))   # + Godot-only modes (res://data/extra/modes.json)
	classes = ExtraClasses.merge(load_json("classes"))   # + Godot-only classes (res://data/extra/classes.json)
	cosmetics = load_json("cosmetics")
	difficulties = load_json("difficulties")
	crate_rates = load_json("crate-rates")
	drops = load_json("drops")
	maps = load_json("maps")
	add_extra_maps(maps)

## Levels the web export leaves out, added for the wizard: Lava Pillars (PillarsMap.lava_entry, from Pillars) and the
## Sandbox arena 'custom' (MapBuilder.custom_map with the defaults; MapBuilder.build("custom") uses the saved layout).
static func add_extra_maps(m: Dictionary) -> Dictionary:
	if m.has("pillars") and not m.has("pillars2"): m["pillars2"] = PillarsMap.lava_entry(m["pillars"])
	if not m.has("custom"): m["custom"] = MapBuilder.custom_map({})
	return m

## One data file as a Dictionary ({} and an error if missing or invalid). Static so headless tests can use it without the autoload.
static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name + ".json"
	if not FileAccess.file_exists(path):
		push_error("Content: missing " + path)
		return {}
	var v = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary):
		push_error("Content: invalid JSON in " + path)
		return {}
	return v

func map_ids() -> Array:
	return maps.keys()

func get_map(id: String) -> Dictionary:
	return maps.get(id, {})

func get_weapon(key: String) -> Dictionary:
	return weapons.get(key, {})

func get_class_data(id: String) -> Dictionary:
	return classes.get(id, {})
