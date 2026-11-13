class_name DlcSave
extends RefCounted
## The Construction DLC part of the profile: blob key "dlc" (Godot only; the web game ignores unknown keys, an old save
## without it loads as fresh). {owned: bool, arcade_best: {easy|normal|nightmare: int, furthest Arcade stage cleared, 0 = none},
## arcade_clears: {easy|normal|nightmare: Array of stage ids cleared at least once}, bonus: bool (the developer-code coins were paid)}.
## Saves from before the difficulties kept arcade_best as one int and arcade_clears as one Array: both were played at the old
## balance, which is now Nightmare, so clean() moves them under "nightmare".

const DIFFS := ["easy", "normal", "nightmare"]

static func fresh() -> Dictionary:
	var best := {}
	var clears := {}
	for k: String in DIFFS:
		best[k] = 0
		clears[k] = []
	return {"owned": false, "arcade_best": best, "arcade_clears": clears, "bonus": false}

static func is_fresh(d: Dictionary) -> bool:
	return d == fresh()

static func _clean_ids(c: Variant) -> Array:
	var out: Array = []
	if c is Array:
		for id in c:
			if id is String and (id as String).length() <= 32 and not out.has(id) and out.size() < 32:
				out.append(id)
	return out

static func _clean_best(b: Variant) -> int:
	return clampi(int(b), 0, 99) if (b is int or b is float) and is_finite(float(b)) else 0

## A clean copy of whatever the blob carried: wrong types and unknown stage ids are dropped; the old single values
## (int / Array) become the Nightmare progress.
static func clean(v: Variant) -> Dictionary:
	var out := fresh()
	if not (v is Dictionary): return out
	var d: Dictionary = v
	out["owned"] = d.get("owned") is bool and d["owned"]
	out["bonus"] = d.get("bonus") is bool and d["bonus"]
	var b: Variant = d.get("arcade_best")
	if b is Dictionary:
		for k: String in DIFFS: out["arcade_best"][k] = _clean_best((b as Dictionary).get(k))
	else:
		out["arcade_best"]["nightmare"] = _clean_best(b)
	var c: Variant = d.get("arcade_clears")
	if c is Dictionary:
		for k: String in DIFFS: out["arcade_clears"][k] = _clean_ids((c as Dictionary).get(k))
	else:
		out["arcade_clears"]["nightmare"] = _clean_ids(c)
	return out

static func norm(diff: String) -> String:
	return diff if DIFFS.has(diff) else "normal"

## Arcade progress helpers (dlc/construction/arcade_manager.gd). The victory is remembered as the pseudo stage id "_victory"
## in that difficulty's arcade_clears (so the blob keeps its shape). A victory on Normal or Nightmare owns the exclusive
## Site Foreman hat; an Easy victory pays coins only.
const VICTORY := "_victory"
const HAT_DIFFS := ["normal", "nightmare"]

static func has_cleared(d: Dictionary, id: String, diff: String) -> bool:
	return ((d.get("arcade_clears", {}) as Dictionary).get(norm(diff), []) as Array).has(id)

static func mark_cleared(d: Dictionary, id: String, diff: String) -> void:
	var cl: Dictionary = d["arcade_clears"]
	if not cl.has(norm(diff)): cl[norm(diff)] = []
	if not (cl[norm(diff)] as Array).has(id): (cl[norm(diff)] as Array).append(id)

static func best(d: Dictionary, diff: String) -> int:
	return int((d.get("arcade_best", {}) as Dictionary).get(norm(diff), 0))

static func set_best(d: Dictionary, diff: String, stage_no: int) -> void:
	(d["arcade_best"] as Dictionary)[norm(diff)] = maxi(best(d, diff), stage_no)

static func won_diff(d: Dictionary, diff: String) -> bool:
	return has_cleared(d, VICTORY, diff)

## The Site Foreman hat is owned (a victory on Normal or Nightmare).
static func won_arcade(d: Dictionary) -> bool:
	for k: String in HAT_DIFFS:
		if won_diff(d, k): return true
	return false

## Hats only the Arcade victory unlocks (data/extra/locker.json `exclusive_hats`).
static var _exclusive: Array = []
static var _exclusive_read := false
static func exclusive_hats() -> Array:
	if not _exclusive_read:
		_exclusive_read = true
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/extra/locker.json"))
		_exclusive = (v as Dictionary).get("exclusive_hats", []) if v is Dictionary else []
	return _exclusive
