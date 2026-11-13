class_name DlcSave
extends RefCounted
## The Construction DLC part of the profile: blob key "dlc" (Godot only; the web game ignores unknown keys, an old save
## without it loads as fresh). {owned: bool, arcade_best: int (furthest Arcade stage cleared, 0 = none),
## arcade_clears: Array of stage ids cleared at least once, bonus: bool (the developer-code coins were paid)}.

static func fresh() -> Dictionary:
	return {"owned": false, "arcade_best": 0, "arcade_clears": [], "bonus": false}

static func is_fresh(d: Dictionary) -> bool:
	return d == fresh()

## A clean copy of whatever the blob carried: wrong types and unknown stage ids are dropped.
static func clean(v: Variant) -> Dictionary:
	var out := fresh()
	if not (v is Dictionary): return out
	var d: Dictionary = v
	out["owned"] = d.get("owned") == true
	out["bonus"] = d.get("bonus") == true
	var b: Variant = d.get("arcade_best")
	if (b is int or b is float) and is_finite(float(b)): out["arcade_best"] = clampi(int(b), 0, 99)
	var c: Variant = d.get("arcade_clears")
	if c is Array:
		for id in c:
			if id is String and (id as String).length() <= 32 and not out["arcade_clears"].has(id) and out["arcade_clears"].size() < 32:
				out["arcade_clears"].append(id)
	return out
