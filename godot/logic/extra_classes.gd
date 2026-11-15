class_name ExtraClasses
extends RefCounted
## Godot-only classes, two sources merged by data():
##   - the built-in res://data/extra/classes.json: Bulwark, Zippy and Ace cost coins (Shop, Class tab); Boo, Champ and
##     Rampage are secret (a ??? silhouette) until a lifetime stat unlocks them (SaveProfile.owns_class);
##   - every DLC pack's `classes` section (res://data/extra/<pack_id>/pack.json), scanned by Content.load_dlc_packs().
## Built-ins win: a pack can add a class, never override one.
## Same multipliers as shared/classes.json, so FighterState.set_class needs nothing new. Bots never pick them
## (MatchSim.BOT_CLASS_ORDER), so the JS parity / hash tests are untouched. merge() adds them to a classes table
## (Content, Combat.load_content, WobblerLooks.data); a web peer that does not know the id shows a Wobbler.

const PATH := "res://data/extra/classes.json"   ## the built-in Godot-only classes (ships with the app, not a DLC pack)

static var _d: Dictionary = {}
static var _gen := -1

static func data() -> Dictionary:
	var content: Variant = load("res://autoload/content.gd")
	var gen: int = content.generation() if content != null else 0
	if gen != _gen:                                          # rebuild only when the pack registry changed (reload())
		_d = _read_builtin()
		if content != null:
			var packs: Variant = content.pack_tables("classes")   # lazily scans the manifests on first use
			if packs is Dictionary:
				for k: String in packs:
					if not _d.has(k): _d[k] = packs[k]
			gen = content.generation()                           # the lazy scan may have bumped it
		_gen = gen
	return _d

static func _read_builtin() -> Dictionary:
	var out := {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	if v is Dictionary:
		for k: String in v:
			if v[k] is Dictionary: out[k] = v[k]
	return out

## Adds the extra classes that `classes` does not have yet (in place; returns it).
static func merge(classes: Variant) -> Dictionary:
	var c: Dictionary = classes if classes is Dictionary else {}
	var d := data()
	for k: String in d:
		if not c.has(k): c[k] = d[k]
	return c

static func is_extra(id: String) -> bool:
	return data().has(id)

static func price(id: String) -> int:
	return int(data().get(id, {}).get("price", 0))

static func unlock(id: String) -> Dictionary:
	var u: Variant = data().get(id, {}).get("unlock")
	return u if u is Dictionary else {}

static func is_hidden(id: String) -> bool:
	return bool(data().get(id, {}).get("hidden", false))

static func rarity(id: String) -> String:
	return str(data().get(id, {}).get("rar", "common"))
