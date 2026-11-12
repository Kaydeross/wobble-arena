class_name ExtraClasses
extends RefCounted
## Godot-only classes (res://data/extra/classes.json): Bulwark, Zippy and Ace cost coins (Locker, Class tab); Boo,
## Champ and Rampage are secret (a ??? silhouette) until a lifetime stat unlocks them (SaveProfile.owns_class).
## Same multipliers as shared/classes.json, so FighterState.set_class needs nothing new. Bots never pick them
## (MatchSim.BOT_CLASS_ORDER), so the JS parity / hash tests are untouched. merge() adds them to a classes table
## (Content, Combat.load_content, WobblerLooks.data); a web peer that does not know the id shows a Wobbler.

const PATH := "res://data/extra/classes.json"

static var _d: Dictionary = {}

static func data() -> Dictionary:
	if _d.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_d = {}
		if v is Dictionary:
			for k: String in v:
				if v[k] is Dictionary: _d[k] = v[k]
	return _d

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
