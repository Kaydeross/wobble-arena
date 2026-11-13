class_name ExtraWeapons
extends RefCounted
## Godot-only construction weapons (res://data/extra/construction/weapons.json):
## Pipe Wrench, Nail Gun, Jackhammer, Spirit Level, Tape Measure, Cement Bucket,
## Cone Launcher, Angle Grinder, Cordless Drill.
## Modelled on ExtraClasses. merge() adds them to weapons dictionary if missing.

const PATH := "res://data/extra/construction/weapons.json"

static var _d: Dictionary = {}

static func data() -> Dictionary:
	if _d.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_d = {}
		if v is Dictionary:
			for k: String in v:
				if not k.begins_with("_") and v[k] is Dictionary:
					_d[k] = v[k]
	return _d

## Adds extra weapons that `weapons` does not have yet (in place; returns it).
static func merge(weapons: Variant) -> Dictionary:
	var w: Dictionary = weapons if weapons is Dictionary else {}
	var d := data()
	for k: String in d:
		if not w.has(k):
			w[k] = d[k]
	return w

static func is_extra(id: String) -> bool:
	return data().has(id)

static func ids() -> Array:
	return data().keys()
