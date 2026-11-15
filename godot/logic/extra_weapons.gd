class_name ExtraWeapons
extends RefCounted
## Godot-only weapons from the DLC packs: every pack.json `weapons` section, e.g.
## res://data/extra/construction/pack.json -> construction/weapons.json (Pipe Wrench, Nail Gun, Jackhammer, Spirit Level,
## Tape Measure, Cement Bucket, Cone Launcher, Angle Grinder, Cordless Drill).
## The manifests are scanned by Content.load_dlc_packs(); data() reads the merged section tables from the Content pack
## registry (no hardcoded path here). merge() adds them to a weapons dictionary if missing, like ExtraClasses.merge.

static var _d: Dictionary = {}
static var _gen := -1

## Every pack's `weapons` table, merged in deterministic pack order ({id: weapon}).
static func data() -> Dictionary:
	var content: Variant = load("res://autoload/content.gd")
	if content == null: return {}
	var gen: int = content.generation()
	if gen != _gen:                                          # rebuild only when the pack registry changed (reload())
		var tables: Variant = content.pack_tables("weapons")  # lazily scans the manifests on first use
		_d = tables if tables is Dictionary else {}
		_gen = content.generation()                           # the lazy scan may have bumped it
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
