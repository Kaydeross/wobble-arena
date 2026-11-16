class_name PackMaps
extends RefCounted
## The procedural arenas of the DLC packs (Kitchen "On Fire", Xmas "Ho Ho Ho", Australia "Hey Mate"), registered the way
## Construction's `sitegen` is: Content.add_extra_maps adds register(header) entries (name, look, `only` = the owning pack id, so no
## ordinary mode lists them; the wizard's pack filter is the hub phase's job), and MapBuilder.build completes them with
## generate(current_seed). Seeded like SiteMap: a local mulberry32, same seed = same level, cached per (map, seed).
##   PackMaps.set_seed(7); var node := MapBuilder.build("kitchen_chaos")
## Hazards travel in the map as `zones` (logic/pack_zones.gd), glowing boxes as `boxStyles` (MapBuilder reads them like map_look.json).

const IDS := ["kitchen_chaos", "toy_workshop", "backyard_bbq"]
const PACK_OF := {"kitchen_chaos": "kitchen", "toy_workshop": "xmas", "backyard_bbq": "australia"}
const U32 := 0xFFFFFFFF
const CACHE_MAX := 9
const ATTEMPTS := 12

static var current_seed := 1
static var _cache: Dictionary = {}


static func has(id: String) -> bool:
	return PACK_OF.has(id)


static func set_seed(s: int) -> void:
	current_seed = absi(s) & U32


## The maps.json entry without a layout (Content registers it; MapBuilder.build completes it).
static func header(id: String) -> Dictionary:
	match id:
		KitchenMap.ID: return KitchenMap.header()
		ToyWorkshopMap.ID: return ToyWorkshopMap.header()
		BackyardBbqMap.ID: return BackyardBbqMap.header()
	return {}


## Content.add_extra_maps: add every pack arena's header to the map table (does not replace an existing entry).
static func register(m: Dictionary) -> Dictionary:
	for id: String in IDS:
		if not m.has(id): m[id] = header(id)
	return m


static func _try(id: String, sd: int, attempt: int) -> Dictionary:
	match id:
		KitchenMap.ID: return KitchenMap.try_layout(sd, attempt)
		ToyWorkshopMap.ID: return ToyWorkshopMap.try_layout(sd, attempt)
		BackyardBbqMap.ID: return BackyardBbqMap.try_layout(sd, attempt)
	return {}


## The full result for (id, seed): {map, ok, attempt, seed, props, ignore, half}. Cached.
static func layout(id: String, seed: int) -> Dictionary:
	var sd := absi(seed) & U32
	var key := "%s:%d" % [id, sd]
	if _cache.has(key): return _cache[key]
	var res: Dictionary = {}
	for attempt in ATTEMPTS:
		res = _try(id, sd, attempt)
		if res.is_empty() or bool(res["ok"]): break
	if _cache.size() >= CACHE_MAX: _cache.clear()
	_cache[key] = res
	return res


## The complete level for (id, seed) (a deep copy: callers may change it).
static func generate(id: String, seed: int) -> Dictionary:
	var L := layout(id, seed)
	if L.is_empty(): return {}
	return (L["map"] as Dictionary).duplicate(true)
