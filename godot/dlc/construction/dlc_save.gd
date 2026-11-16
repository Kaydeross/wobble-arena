class_name DlcSave
extends RefCounted
## The DLC part of the profile: blob key "dlc" (Godot only; the web game ignores unknown keys, an old save
## without it loads as fresh). {v: 2, owned: bool, arcade_best: {easy|normal|nightmare: int, furthest Arcade stage cleared, 0 = none},
## arcade_clears: {easy|normal|nightmare: Array of stage ids cleared at least once}, bonus: bool (the developer-code coins were paid),
## packs: {pack id: {owned, arcade_best, arcade_clears}}}.
## MULTI-PACK (versioned): the Construction DLC keeps its original top-level fields (owned, arcade_best, arcade_clears), so
## every save from before the extra packs keeps its ownership, its Arcade progress and its hat with no rewrite at all; the
## other packs (kitchen, xmas, australia, ...) live under `packs[id]` in the same shape. `v` is the blob version: a blob
## without it (or with 1) is the pre-multipack shape; clean() migrates it to v 2 (adds `packs`, changes nothing else).
## The developer code (Save.codes "dev") owns every pack. Every helper takes the pack id last ("" = Construction).
## Saves from before the difficulties kept arcade_best as one int and arcade_clears as one Array: both were played at the old
## balance, which is now Nightmare, so clean() moves them under "nightmare".

const DIFFS := ["easy", "normal", "nightmare"]
const VERSION := 2
const BASE_PACK := "construction"           ## the pack stored at the top level (its saves predate the extra packs)
const MAX_PACKS := 16

static func _slot_fresh() -> Dictionary:
	var best := {}
	var clears := {}
	for k: String in DIFFS:
		best[k] = 0
		clears[k] = []
	return {"owned": false, "arcade_best": best, "arcade_clears": clears}

static func fresh() -> Dictionary:
	var d := _slot_fresh()
	d["bonus"] = false
	d["packs"] = {}
	d["v"] = VERSION
	return d

static func is_base(pack: String) -> bool:
	return pack == "" or pack == BASE_PACK

static func _valid_pack(id: String) -> bool:
	if id.length() < 1 or id.length() > 32: return false
	for i in id.length():
		var c := id.unicode_at(i)
		var ok := (c >= 97 and c <= 122) or (i > 0 and ((c >= 48 and c <= 57) or c == 95 or c == 45))
		if not ok: return false
	return true

## The progress dictionary of `pack` inside the dlc dictionary `d`: `d` itself for Construction, else packs[id]
## (created when `create`; an empty read-only stand-in otherwise, so a read never grows the save).
static func slot(d: Dictionary, pack: String = "", create: bool = false) -> Dictionary:
	if is_base(pack): return d
	if not d.get("packs") is Dictionary:
		if not create: return _slot_fresh()
		d["packs"] = {}
	var ps: Dictionary = d["packs"]
	if not ps.get(pack) is Dictionary:
		if not create: return _slot_fresh()
		ps[pack] = _slot_fresh()
	return ps[pack]

## Is the pack bought (or unlocked by the developer code)? `codes` = Save.codes.
static func owns(d: Dictionary, codes: Array, pack: String = "") -> bool:
	if codes.has("dev"): return true
	return bool(slot(d, pack).get("owned", false))

static func set_owned(d: Dictionary, pack: String, on: bool) -> void:
	slot(d, pack, true)["owned"] = on

static func is_fresh(d: Dictionary) -> bool:
	return d == fresh()

## Pack ids with a saved slot.
static func pack_ids(d: Dictionary) -> Array:
	return (d.get("packs", {}) as Dictionary).keys() if d.get("packs") is Dictionary else []

static func _clean_ids(c: Variant) -> Array:
	var out: Array = []
	if c is Array:
		for id in c:
			if id is String and (id as String).length() <= 32 and not out.has(id) and out.size() < 32:
				out.append(id)
	return out

static func _clean_best(b: Variant) -> int:
	return clampi(int(b), 0, 99) if (b is int or b is float) and is_finite(float(b)) else 0

## One pack's progress, cleaned (the old single int / Array shapes of the Construction Arcade are handled by the caller).
static func _clean_slot(d: Dictionary) -> Dictionary:
	var out := _slot_fresh()
	out["owned"] = d.get("owned") is bool and d["owned"]
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

## A clean copy of whatever the blob carried: wrong types and unknown stage ids are dropped; the old single values
## (int / Array) become the Nightmare progress. MIGRATION: a blob of any older version (no `v`, or 1: only the Construction
## fields, as every save before the extra packs wrote them) keeps its Construction ownership, bonus and Arcade progress
## exactly and gains an empty `packs`; the result is always the current version.
static func clean(v: Variant) -> Dictionary:
	var out := fresh()
	if not (v is Dictionary): return out
	var d: Dictionary = v
	var base := _clean_slot(d)
	for k: String in base: out[k] = base[k]
	out["bonus"] = d.get("bonus") is bool and d["bonus"]
	if d.get("packs") is Dictionary:
		var ps: Dictionary = d["packs"]
		var ids: Array = ps.keys()
		ids.sort()
		for id: Variant in ids:
			if not (id is String) or not _valid_pack(id) or id == BASE_PACK or not (ps[id] is Dictionary): continue
			if (out["packs"] as Dictionary).size() >= MAX_PACKS: break
			out["packs"][id] = _clean_slot(ps[id])
	return out

static func norm(diff: String) -> String:
	return diff if DIFFS.has(diff) else "normal"

## Arcade progress helpers (dlc/construction/arcade_manager.gd). The victory is remembered as the pseudo stage id "_victory"
## in that difficulty's arcade_clears (so the blob keeps its shape). A victory on Normal or Nightmare owns the exclusive
## Site Foreman hat; an Easy victory pays coins only.
const VICTORY := "_victory"
const HAT_DIFFS := ["normal", "nightmare"]

static func has_cleared(d: Dictionary, id: String, diff: String, pack: String = "") -> bool:
	return ((slot(d, pack).get("arcade_clears", {}) as Dictionary).get(norm(diff), []) as Array).has(id)

static func mark_cleared(d: Dictionary, id: String, diff: String, pack: String = "") -> void:
	var cl: Dictionary = slot(d, pack, true)["arcade_clears"]
	if not cl.has(norm(diff)): cl[norm(diff)] = []
	if not (cl[norm(diff)] as Array).has(id): (cl[norm(diff)] as Array).append(id)

static func best(d: Dictionary, diff: String, pack: String = "") -> int:
	return int((slot(d, pack).get("arcade_best", {}) as Dictionary).get(norm(diff), 0))

static func set_best(d: Dictionary, diff: String, stage_no: int, pack: String = "") -> void:
	(slot(d, pack, true)["arcade_best"] as Dictionary)[norm(diff)] = maxi(best(d, diff, pack), stage_no)

static func won_diff(d: Dictionary, diff: String, pack: String = "") -> bool:
	return has_cleared(d, VICTORY, diff, pack)

## The pack's victory hat is owned (a victory on Normal or Nightmare).
static func won_arcade(d: Dictionary, pack: String = "") -> bool:
	for k: String in HAT_DIFFS:
		if won_diff(d, k, pack): return true
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
