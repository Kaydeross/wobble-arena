class_name PackRegistry
extends RefCounted
## The multi-pack DLC registry: every DLC pack that has a hub file (res://data/extra/<pack>/hub.json, next to its
## pack.json), in the hub's order. ONE code path for Construction, On Fire (kitchen), Ho Ho Ho (xmas) and Hey Mate
## (australia): the hub, the setup wizard, Quick Play, DlcUnlock / DlcSave, ArcadeManager / ArcadeCoop and the title
## showcase all ask this class which packs exist, which game mode and arenas a pack has, and what it costs. Nothing here
## is per pack: a new pack is a folder with a pack.json and a hub.json (plus a dlc/packs/<id>.tres for the title).
##
## hub.json fields (all optional except `mode`; `_`-keys are author notes):
##   order        sort key in the hub's pack row (default 99; Construction = 0, the shipped order)
##   mode         the pack's classic game mode id (a key of the pack's modes section; same as the pack id by convention)
##   maps         the arenas that mode may use (ModeRules.maps_for; the pack's own arena ids from its map generators)
##   arcade_maps  the arena the Arcade run plays on: the first one that exists in the build wins (default `maps`)
##   wizard       true = owners get the pack's mode as a game type in the setup wizard and in Quick Play (Construction: false,
##                it lives behind the title banner / hub only)
##   price        coins (default DlcUnlock.PRICE, 1500)
##   classic_desc / arcade_desc   the two hub card lines (English tr() keys; empty = the built-in Construction text)
##   victory_hat  the Arcade victory hat id ("" = none): listed in the Walldrobe only after a Normal / Nightmare win
##   hats         the pack's own hat ids: listed only while the pack is owned (never for a non-owner)
##   seed_map     the map id whose generator takes a seed (the hub shows the Site seed row only for it; Construction: sitegen)
## This script must compile without the autoloads (ModeRules / QuickPlay load it lazily from --script tests), so the
## profile and the Content registry are looked up at runtime, never named.

const DEFAULT_PRICE := 1500
const DIR := "res://data/extra/"
const FILE := "hub.json"

static var _cache: Dictionary = {}           ## pack id -> parsed hub.json ({} = none)
static var _gen := -1                        ## Content registry generation the cache belongs to
static var _mode_pack: Dictionary = {}       ## game mode id -> pack id (built once per generation: bots ask on every crate)
static var _ids: Array = []                  ## ids() once per generation
static var _built := false

static func _content() -> Variant:
	return load("res://autoload/content.gd")

static func _fresh() -> void:
	var c: Variant = _content()
	var g := int(c.generation()) if c != null else 0
	if g != _gen:
		_gen = g
		_cache.clear()
		_mode_pack.clear()
		_ids = []
		_built = false

## Test hook: forget what was read (a test that writes a synthetic hub.json).
static func reset() -> void:
	_cache.clear()
	_mode_pack.clear()
	_ids = []
	_built = false
	_gen = -1

static func _read(id: String) -> Dictionary:
	_fresh()
	if _cache.has(id): return _cache[id]
	var out := {}
	var c: Variant = _content()
	var pk: Dictionary = c.pack(id) if c != null else {}
	if not pk.is_empty():
		var path := str(pk.get("dir", DIR + id)).path_join(FILE)
		if FileAccess.file_exists(path):
			var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if v is Dictionary and str((v as Dictionary).get("mode", "")) != "": out = v
	_cache[id] = out
	return out

## Every pack with a hub file, in hub order (order, then id).
static func ids() -> Array:
	_fresh()
	if _built: return _ids.duplicate()
	var c: Variant = _content()
	var out: Array = []
	if c == null: return out
	for id: String in c.pack_ids():
		if not _read(id).is_empty(): out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var oa := int(_read(a).get("order", 99))
		var ob := int(_read(b).get("order", 99))
		return oa < ob or (oa == ob and a < b))
	_ids = out
	for id: String in out:
		var m := str(_read(id).get("mode", ""))
		if m != "" and not _mode_pack.has(m): _mode_pack[m] = id
	_built = true
	return out.duplicate()

static func has(id: String) -> bool:
	return id != "" and not _read(id).is_empty()

static func info(id: String) -> Dictionary:
	return _read(id).duplicate(true)

## The pack's display name (English key) from its manifest.
static func display_name(id: String) -> String:
	var c: Variant = _content()
	return str(c.pack(id).get("name", id)) if c != null else id

static func mode_of(id: String) -> String:
	return str(_read(id).get("mode", ""))

## The pack that owns game mode `mode` ("" = a normal mode).
static func pack_of_mode(mode: String) -> String:
	if mode == "": return ""
	ids()
	return str(_mode_pack.get(mode, ""))

static func is_pack_mode(mode: String) -> bool:
	return pack_of_mode(mode) != ""

static func price(id: String) -> int:
	return maxi(0, int(_read(id).get("price", DEFAULT_PRICE)))

static func in_wizard(id: String) -> bool:
	return bool(_read(id).get("wizard", false))

## The arenas the pack's mode offers (ModeRules.maps_for), in the file's order.
static func maps(id: String) -> Array:
	var m: Variant = _read(id).get("maps", [])
	return (m as Array).duplicate() if m is Array else []

## The mode's arenas for ModeRules.maps_for ([] for a normal mode).
static func maps_for_mode(mode: String) -> Array:
	var id := pack_of_mode(mode)
	return maps(id) if id != "" else []

## The arenas of `maps` that exist in this build (Content.maps), in order. A pack whose arenas are not built yet has none.
static func real_maps(id: String, content_maps: Dictionary) -> Array:
	return maps(id).filter(func(m: Variant) -> bool: return content_maps.has(str(m)))

## The arena the Arcade run plays on: the first of `arcade_maps` (else `maps`) that exists, "" when none does.
static func arcade_map(id: String, content_maps: Dictionary) -> String:
	var l: Variant = _read(id).get("arcade_maps", _read(id).get("maps", []))
	if l is Array:
		for m: Variant in l:
			if content_maps.has(str(m)): return str(m)
	return ""

static func seed_map(id: String) -> String:
	return str(_read(id).get("seed_map", ""))

static func victory_hat(id: String) -> String:
	return str(_read(id).get("victory_hat", ""))

static func hats(id: String) -> Array:
	var h: Variant = _read(id).get("hats", [])
	return (h as Array).duplicate() if h is Array else []

## The pack's presentation resource (res://dlc/packs/<id>.tres: DLCPackData, the title showcase's data), null if none.
static func style(id: String) -> Resource:
	var path := "res://dlc/packs/%s.tres" % id
	return load(path) if ResourceLoader.exists(path) else null

## The pack's colour (its .tres accent; Construction yellow when there is none).
static func accent(id: String) -> Color:
	var r: Resource = style(id)
	return r.get("accent_color") if r != null else Color("#ffc21a")

## The second tape / stripe colour of the pack's livery.
static func stripe(id: String) -> Color:
	var r: Resource = style(id)
	return r.get("stripe_color") if r != null else Color("#14120b")

## The 2D badge kind (PackBadge) of the pack.
static func badge(id: String) -> String:
	var r: Resource = style(id)
	return str(r.call("badge_kind")) if r != null else ""

static func text(id: String, key: String) -> String:
	return str(_read(id).get(key, ""))

## The pack's stage table file (its manifest's `stages` section), "" when there is none.
static func stages_path(id: String) -> String:
	var c: Variant = _content()
	return str(c.pack_section_file(id, "stages")) if c != null else ""

# ---------------- the profile (looked up lazily: no autoload name in this script) ----------------

static func _save() -> Object:
	var loop := Engine.get_main_loop()
	return (loop as SceneTree).root.get_node_or_null("Save") if loop is SceneTree else null

## Does the profile own pack `id`? A pack the registry does not know is never owned. `sv` = a profile (tests), else Save.
static func owned(id: String, sv: Object = null) -> bool:
	if not has(id): return false
	var s := sv if sv != null else _save()
	if s == null: return false
	return DlcSave.owns(s.dlc, s.codes, id)

## The packs the profile owns, in hub order.
static func owned_ids(sv: Object = null) -> Array:
	return ids().filter(func(id: String) -> bool: return owned(id, sv))

## Does the profile own the pack of game mode `mode`? true for a normal mode (nothing to own) and for Construction's
## mode, which keeps its original gate (its hub; the world never refused it, and its tests run it unowned).
static func mode_owned(mode: String, sv: Object = null) -> bool:
	var id := pack_of_mode(mode)
	return id == "" or DlcSave.is_base(id) or owned(id, sv)

## `mode` unless it is a pack mode the player does not own (then "classic"): the one gate every start path runs through.
static func allowed_mode(mode: String, sv: Object = null) -> String:
	return mode if mode_owned(mode, sv) else "classic"

## The pack game modes the setup wizard and Quick Play list for this profile: owned packs with `wizard`, whose arenas exist.
static func wizard_modes(content_maps: Dictionary, sv: Object = null) -> Array:
	var out: Array = []
	for id: String in ids():
		if in_wizard(id) and owned(id, sv) and not real_maps(id, content_maps).is_empty(): out.append(mode_of(id))
	return out

## Hats a profile must not see: the pack hats of packs it does not own and the victory hat until that win.
static func hidden_hats(sv: Object = null) -> Array:
	var out: Array = []
	var s := sv if sv != null else _save()
	for id: String in ids():
		var own := owned(id, sv)
		if not own: out.append_array(hats(id))
		var vh := victory_hat(id)
		if vh != "" and not (s != null and DlcSave.won_arcade(s.dlc, id)): out.append(vh)
	return out
