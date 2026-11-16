class_name DLCPacks
extends RefCounted
## The DLC packs the title showcase cycles through (ui/title_showcase.gd), in order. An explicit list of .tres paths:
## DirAccess cannot be trusted to list res:// in an exported build (resources are remapped / packed), so a new pack is
## one more line here plus its DLCPackData .tres (dlc/dlc_pack_data.gd).
## Tests add packs with `extra` (resources built in code; never saved).

const PATHS: Array[String] = [
	"res://dlc/packs/construction.tres",
	"res://dlc/packs/kitchen.tres",
	"res://dlc/packs/xmas.tres",
	"res://dlc/packs/australia.tres",
]

static var only: Array = []           ## tests: restrict the shipped packs to these ids (empty = all of them; the old one-pack showcase tests use ["construction"])
static var extra: Array = []          ## tests: more DLCPackData after the shipped ones

## Every pack that loads and is valid (its weapons and arena exist in this build), shipped ones first.
static func all(weapons: Dictionary, maps: Dictionary) -> Array[DLCPackData]:
	var out: Array[DLCPackData] = []
	var seen := {}
	var list: Array = []
	for p: String in PATHS:
		if ResourceLoader.exists(p):
			var r: Variant = load(p)
			if only.is_empty() or (r is DLCPackData and only.has((r as DLCPackData).pack_id)): list.append(r)
		else: push_warning("DLC pack %s is missing" % p)
	list.append_array(extra)
	for r: Variant in list:
		var d := r as DLCPackData
		if d == null: continue
		var why := d.problem(weapons, maps)
		if why != "" or seen.has(d.pack_id):
			push_warning("DLC pack '%s' skipped: %s" % [d.pack_id, why if why != "" else "duplicate id"])
			continue
		seen[d.pack_id] = true
		out.append(d)
	return out

static func find(id: String, weapons: Dictionary, maps: Dictionary) -> DLCPackData:
	for d: DLCPackData in all(weapons, maps):
		if d.pack_id == id: return d
	return null
