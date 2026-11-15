extends Node
## Game data (autoload `Content`). Reads res://data/*.json, which tools/sync-shared.js copies from shared/ (the source of truth).
## Do not edit res://data by hand: change public/index.html, then `npm run content`. Exception: res://data/extra/
## (Godot-only data, not copied from shared/) is loaded in two ways:
##   - built-in Godot extras: data/extra/modes.json and data/extra/classes.json, merged by ModeRules.merge_extra /
##     ExtraClasses.merge (they ship with the app, so they are not a DLC pack);
##   - DLC packs: every res://data/extra/<pack_id>/pack.json (docs/CONSTRUCTION_DLC.md "DLC pack manifest"), scanned by
##     load_dlc_packs() in deterministic (sorted pack id) order and merged through ExtraWeapons / ExtraClasses /
##     ModeRules. Content also publishes the registry (pack_section_file / pack_paths / pack_tables) for code that reads
##     one table itself, e.g. ArcadeCoop's stage table.
## A malformed manifest is reported with push_error and its pack is skipped: a broken DLC never stops the game or reload().

const DATA_DIR := "res://data/"
## Where DLC packs live: res://data/extra/<pack_id>/pack.json.
const EXTRA_DIR := "res://data/extra/"
const PACK_FILE := "pack.json"

# ============================== parsed-JSON cache ==============================
## Parsed content is immutable between releases. Every data file is decoded ONCE per process and each caller receives a
## deep copy (`duplicate(true)` for objects/arrays), so a match can merge or alter its own tuning without changing the
## cache or another match. `reload()` (and a DLC-pack re-scan) invalidates the cache: cache_generation() changes and the
## next read decodes again. Static so headless tests and plain logic classes (MatchSim) share the SAME cache as the
## autoload, and so a script compiled before the autoload exists can call `load("res://autoload/content.gd").read_json`.
const JSON_CACHE_MAX := 256                  ## bounded: FIFO eviction, far above the ~40 data files a build ships
static var _json_cache: Dictionary = {}      ## res:// path -> pristine parsed Variant (never handed out)
static var _json_order: Array[String] = []   ## insertion order for the FIFO bound
static var _json_parses := 0                 ## real JSON.parse_string calls (cache misses for an existing file)
static var _json_hits := 0
static var _json_parse_by_path: Dictionary = {}
static var _cache_generation := 0

## Bumped whenever the parsed-JSON cache is invalidated: reload() / a DLC-pack re-scan (see load_dlc_packs()).
## A reader that holds parsed tables can compare it to notice that content changed on disk.
static func cache_generation() -> int:
	return _cache_generation

## JSON.parse_string calls so far (all paths / one path): 1 per shipped file per process, 0 per extra match.
static func json_parses() -> int:
	return _json_parses

static func json_parse_count(path: String) -> int:
	return int(_json_parse_by_path.get(path, 0))

## Cache hits so far: reads served from the cache instead of the file (the 0-parse-per-match half of the budget).
static func json_cache_hits() -> int:
	return _json_hits

static func json_cache_entries() -> int:
	return _json_cache.size()

## Test helper: clears the counters but KEEPS the cache (so "1 parse/file/process" can be measured from a known start).
static func reset_json_cache_counters() -> void:
	_json_parses = 0
	_json_hits = 0
	_json_parse_by_path = {}

## Drops every cached parse and bumps the generation. reload() and load_dlc_packs() call it: a re-scan may change pack
## files on disk, and a release update must never keep a stale decode. Matches already holding their copies are safe.
static func _invalidate_json_cache() -> void:
	_json_cache.clear()
	_json_order.clear()
	_cache_generation += 1

## One JSON file parsed at most once per process (until reload()): returns a deep copy for objects/arrays, the scalar as
## is, and null when the file is missing or malformed. Static: usable without the autoload (headless tests, logic).
static func read_json(path: String) -> Variant:
	var value: Variant
	if _json_cache.has(path):
		_json_hits += 1
		value = _json_cache[path]
	else:
		if not FileAccess.file_exists(path):
			return null
		_json_parses += 1
		_json_parse_by_path[path] = int(_json_parse_by_path.get(path, 0)) + 1
		value = JSON.parse_string(FileAccess.get_file_as_string(path))
		if value == null:
			return null                                  # malformed: report to the caller, never cache a failure
		_json_cache[path] = value
		_json_order.append(path)
		while _json_order.size() > JSON_CACHE_MAX:       # bounded cache: drop the oldest decodes
			_json_cache.erase(_json_order[0])
			_json_order.remove_at(0)
	if value is Dictionary or value is Array:
		return (value as Variant).duplicate(true)
	return value

var weapons: Dictionary = {}
var modes: Dictionary = {}
var classes: Dictionary = {}
var cosmetics: Dictionary = {}
var difficulties: Dictionary = {}
var crate_rates: Dictionary = {}
var drops: Dictionary = {}
var maps: Dictionary = {}

## The DLC pack registry: Array of {id, name, version, requires: Array, dir, sections: {name: res:// path}}, sorted by
## id. Static so headless tests and logic hooks (ExtraWeapons, ExtraClasses, ModeRules) can read it without the autoload
## instance, and so a script compiled before the autoload exists can do:
##   load("res://autoload/content.gd").pack_section_file("construction", "stages")
static var _packs: Array = []
static var _packs_loaded := false
## Bumped by load_dlc_packs(); the merge hooks cache their tables against it, so a reload() re-reads the packs.
static var _generation := 0
## Why the last scan skipped a pack (also push_error'd); cleared by every scan.
static var _scan_errors: Array = []

## Manifest sections this build consumes: weapons/classes/modes are merged by the hooks, stages is only published as a
## path (ArcadeCoop.table reads it). Anything else is either a documented future section or ignored with a warning.
const PACK_SECTIONS := ["weapons", "classes", "modes", "stages"]
## Documented pack sections a newer DLC may ship; this build warns and ignores them instead of failing the pack.
const PACK_RESERVED := ["maps", "cosmetics", "strings"]

func _init() -> void:
	reload()

## Levels of the removed Pillars mode: still in the generated web export (maps.json), never used by the Godot game.
const REMOVED_MAPS := ["pillars", "pillars2"]

func reload() -> void:
	_invalidate_json_cache()                             # a reload must re-decode every file (pack changes included)
	load_dlc_packs()                                     # scan res://data/extra/*/pack.json before the hooks below merge
	weapons = ExtraWeapons.merge(load_json("weapons"))   # shared weapons + every pack's `weapons` section (construction: the 9 tools)
	modes = ModeRules.merge_extra(load_json("modes"))   # shared modes + built-in Godot modes + every pack's `modes` section
	classes = ExtraClasses.merge(load_json("classes"))   # shared classes + built-in Godot classes + every pack's `classes` section
	cosmetics = load_json("cosmetics")
	difficulties = load_json("difficulties")
	crate_rates = load_json("crate-rates")
	drops = load_json("drops")
	maps = load_json("maps")
	for gone: String in REMOVED_MAPS: maps.erase(gone)
	modes.erase("pillars")
	add_extra_maps(maps)

## Levels the web export leaves out, added for the wizard: the
## Sandbox arena 'custom' (MapBuilder.custom_map with the defaults; MapBuilder.build("custom") uses the saved layout) and the
## Construction DLC's generated 'sitegen' (SiteMap.header(): the look and name; the boxes and spots come with MapBuilder.build).
static func add_extra_maps(m: Dictionary) -> Dictionary:
	if not m.has("custom"): m["custom"] = MapBuilder.custom_map({})
	if not m.has(SiteMap.ID): m[SiteMap.ID] = SiteMap.header()   # Building Site (Construction DLC): MapBuilder.build generates the layout from SiteMap.current_seed
	return m

## One data file as a Dictionary ({} and an error if missing or invalid), through the parsed-JSON cache and already a
## deep copy: the autoload's merges mutate their copy, never the cache. Static so headless tests can use it without the
## autoload.
static func load_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name + ".json"
	if not FileAccess.file_exists(path):
		push_error("Content: missing " + path)
		return {}
	var v: Variant = read_json(path)
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

# ============================== DLC packs ==============================

## Scan `<root>/<pack_id>/pack.json` and return the validated registry sorted by pack id. Never throws: a malformed
## manifest is push_error'd (and kept in scan_errors()) and only that pack is skipped. `root` exists so a headless test
## can scan a synthetic directory (user://) without writing into res://.
static func scan_dlc_packs(root: String = EXTRA_DIR) -> Array:
	_scan_errors = []
	var out: Array = []
	if not DirAccess.dir_exists_absolute(root):
		_err("missing DLC pack directory " + root)
		return out
	var seen := {}
	var dirs := DirAccess.get_directories_at(root)
	dirs.sort()                                             # deterministic discovery; the registry is sorted by id below
	for dir: String in dirs:
		var manifest_path := root.path_join(dir).path_join(PACK_FILE)
		if not FileAccess.file_exists(manifest_path): continue   # not a pack dir (decor/, or a future data/extra/*.json table)
		var pack := _read_pack(manifest_path, dir, root)
		if pack.is_empty(): continue
		var id := str(pack["id"])
		if seen.has(id):
			_err("duplicate pack id '%s' (%s and %s)" % [id, seen[id], manifest_path])
			continue
		seen[id] = manifest_path
		out.append(pack)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	# requires: fail closed. A pack whose dependency did not scan (itself malformed, or a pack it needs is missing) is
	# skipped instead of being merged half-working; repeat because dropping one pack may orphan another.
	var dropped := true
	while dropped:
		dropped = false
		for i in range(out.size() - 1, -1, -1):
			var p: Dictionary = out[i]
			var id := str(p["id"])
			for req: String in p["requires"]:
				if req == id or not _pack_in(out, req):
					_err("pack '%s' requires missing pack '%s'; the pack is ignored" % [id, req])
					out.remove_at(i)
					dropped = true
					break
	return out

static func _pack_in(packs: Array, id: String) -> bool:
	for p: Dictionary in packs:
		if str(p["id"]) == id: return true
	return false

## One manifest -> {id, name, version, requires, dir, sections}. {} (and a push_error) when it is malformed: a pack is
## all-or-nothing, so a broken declared section rejects the whole pack (no half-shipped DLC); `_`-prefixed and reserved
## sections never reject it.
static func _read_pack(path: String, dir_name: String, root: String) -> Dictionary:
	var parsed: Variant = read_json(path)                # cached: the registry and pack_tables share one decode
	if not (parsed is Dictionary):
		_err("malformed manifest (not a JSON object): " + path)
		return {}
	var m: Dictionary = parsed
	var id := str(m.get("id", ""))
	if id == "":
		_err("manifest without an id: " + path)
		return {}
	if not _valid_id(id):
		_err("invalid pack id '%s' (lowercase letters, digits, '_' or '-', starting with a letter): %s" % [id, path])
		return {}
	if id != dir_name:
		_err("pack id '%s' does not match its directory '%s': %s" % [id, dir_name, path])
		return {}
	var name := str(m.get("name", ""))
	if name == "":
		_err("pack '%s' has no name: %s" % [id, path])
		return {}
	var version := 1
	if m.has("version"):
		var v: Variant = m["version"]
		if not (v is int or v is float) or int(v) < 1:
			_err("pack '%s' version must be an integer >= 1: %s" % [id, path])
			return {}
		version = int(v)
	var requires: Array = []
	if m.has("requires"):
		var rq: Variant = m["requires"]
		if not (rq is Array):
			_err("pack '%s' requires must be an array of pack ids: %s" % [id, path])
			return {}
		for r: Variant in rq:
			if not (r is String) or str(r) == "":
				_err("pack '%s' requires must be an array of pack ids: %s" % [id, path])
				return {}
			requires.append(str(r))
	var sections := {}
	var base := root.path_join(dir_name)
	for key: String in m:
		if key.begins_with("_"): continue                        # author comments, like the shipped JSON tables
		if key in ["id", "name", "version", "requires"]: continue
		if not PACK_SECTIONS.has(key):
			if PACK_RESERVED.has(key):
				push_warning("Content: pack '%s' declares reserved section '%s' (ignored by this build)" % [id, key])
			else:
				push_warning("Content: pack '%s' has an unknown key '%s' (ignored)" % [id, key])
			continue
		var rel := str(m[key])
		if rel == "" or rel.begins_with("/") or rel.contains("..") or rel.contains("://"):
			_err("pack '%s' section '%s' must be a file path inside the pack: %s" % [id, key, path])
			return {}
		var file_path := base.path_join(rel)
		if not FileAccess.file_exists(file_path):
			_err("pack '%s' section '%s' file is missing: %s" % [id, key, file_path])
			return {}
		var v: Variant = read_json(file_path)             # cached: validated once, decoded once per process
		if not (v is Dictionary):
			_err("pack '%s' section '%s' is not a JSON object: %s" % [id, key, file_path])
			return {}
		sections[key] = file_path
	return {"id": id, "name": name, "version": version, "requires": requires, "dir": base, "sections": sections}

static func _valid_id(id: String) -> bool:
	if id.is_empty(): return false
	var first := id[0]
	if first < "a" or first > "z": return false
	for i in id.length():
		var c := id[i]
		var ok := (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_" or c == "-"
		if not ok: return false
	return true

## Scan the shipped DLC packs (res://data/extra/*/pack.json), store the registry and return it. Called by reload() on
## startup; also the public entry point for tools and tests (Content.load_dlc_packs()). The static accessors below do the
## same lazily when a script calls them before the autoload exists.
func load_dlc_packs() -> Array:
	_invalidate_json_cache()                             # a re-scan may have changed the pack files on disk
	return _store_packs(scan_dlc_packs())

## Store a scanned registry (bumps the generation the merge hooks cache against). Static so lazy access works without
## the autoload instance; a synthetic scan (tests) can be stored with it too.
static func _store_packs(packs: Array) -> Array:
	_packs = packs
	_packs_loaded = true
	_generation += 1
	return _packs

## The registry, lazily scanned on first use so `load("res://autoload/content.gd").pack_*` works without the autoload.
static func packs() -> Array:
	_ensure_packs()
	return _packs.duplicate()

static func pack_ids() -> Array:
	_ensure_packs()
	var out: Array = []
	for p: Dictionary in _packs: out.append(str(p["id"]))
	return out

## One pack entry ({} when unknown).
static func pack(id: String) -> Dictionary:
	_ensure_packs()
	for p: Dictionary in _packs:
		if str(p["id"]) == id: return p
	return {}

## The res:// path of one pack section file ("" when the pack or section is not there). This is how code that owns a
## table (ArcadeCoop's stage table) follows the manifest instead of hardcoding a path.
static func pack_section_file(pack_id: String, section: String) -> String:
	_ensure_packs()
	for p: Dictionary in _packs:
		if str(p["id"]) == pack_id:
			return str((p["sections"] as Dictionary).get(section, ""))
	return ""

## Every pack's section file, in deterministic (sorted pack id) order: the merge order for ModeRules.merge_extra.
static func pack_paths(section: String) -> Array:
	_ensure_packs()
	var out: Array = []
	for p: Dictionary in _packs:
		var f := str((p["sections"] as Dictionary).get(section, ""))
		if f != "": out.append(f)
	return out

## The merged table of one section over every pack, in deterministic (sorted pack id) order. `_`-prefixed keys (author
## comments) and non-object values are skipped, like the built-in tables. Two packs defining the same key is a data error:
## push_error and the first pack (sorted) wins, so the result is deterministic.
static func pack_tables(section: String) -> Dictionary:
	_ensure_packs()
	var out := {}
	var owner := {}
	for p: Dictionary in _packs:
		var file := str((p["sections"] as Dictionary).get(section, ""))
		if file == "": continue
		var v: Variant = read_json(file)                         # same cached decode as the scan/merge hooks
		if not (v is Dictionary): continue                       # validated at scan time; never crashes a match
		for k: String in v:
			if k.begins_with("_") or not (v[k] is Dictionary): continue
			if out.has(k):
				push_error("Content: pack section '%s' key '%s' is in both '%s' and '%s' (first wins)" % [section, k, owner[k], p["id"]])
				continue
			out[k] = v[k]
			owner[k] = str(p["id"])
	return out

## Bumped by load_dlc_packs(); the ExtraWeapons/ExtraClasses/ModeRules caches compare it to notice a reload().
static func generation() -> int:
	return _generation

## Why the last scan dropped packs ("" records nothing): the tests assert a malformed manifest is reported, not fatal.
static func scan_errors() -> Array:
	return _scan_errors.duplicate()

static func _ensure_packs() -> void:
	if not _packs_loaded: _store_packs(scan_dlc_packs())

static func _err(msg: String) -> void:
	_scan_errors.append(msg)
	push_error("Content: " + msg)
