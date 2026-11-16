class_name DLCPackData
extends Resource
## One DLC pack as the title screen's showcase presents it (ui/title_showcase.gd): the crane lowers this pack's
## container, its weapons hang on the racks inside, "TEST IN <arena>" starts a test drive on its arena. Pure data, so a
## future pack is a new .tres listed in DLCPacks.PATHS (dlc/dlc_packs.gd): no showcase code changes.
## The content itself (weapon stats, the arena, the unlock) stays where it is: `weapon_ids` are ids in Content.weapons
## (the pack's data/extra/<pack_id>/weapons.json), `arena_id` an id in Content.maps, and ownership is read LIVE from the
## profile by is_unlocked (never stored here: a .tres bool would go stale the moment the player buys the pack).

## The pack's id: the data/extra/<id>/pack.json manifest id (Content.pack_ids()).
@export var pack_id := ""
@export var display_name := ""              ## English (the i18n key), shown on the container and the pack header
@export var subtitle := ""                  ## English (the i18n key), e.g. "9 Weapons + Site Yard"
@export var accent_color := Color("#ffc21a")
@export var weapon_ids: Array[String] = []  ## shown on the racks, left to right, top row first
@export var arena_id := ""                  ## the arena the test drive plays on (and the arena badge on the rack)
## How the container is painted: "hazard" (accent body, stripes of the accent and `stripe_color` along the door feet),
## "plain" (no stripes). Unknown styles fall back to "hazard". `body_color` (alpha 0 = the accent) paints the walls and
## doors, `stripe_color` is the second stripe colour (Construction: black), so each pack has its own livery.
@export var container_style := "hazard"
@export var body_color := Color(0, 0, 0, 0)
@export var stripe_color := Color("#14120b")
## The hat the wobbler wears while a weapon of this pack is previewed ("" = keeps its own hat). Preview only.
@export var badge_icon := ""
## The 2D badge drawn in the title header and the hub's pack cards (ui/pack_badge.gd): "hardhat", "chef", "santa" or "cork".
## "" = the badge_icon.
@export var badge_art := ""
## The game mode the test drive runs (its crate pool must allow the pack's weapons).
@export var test_mode := "classic"
## Which unlock the pack uses: "construction" or "pack" = DlcUnlock for this pack_id (coins or the developer code,
## dlc/construction/dlc_unlock.gd; per-pack ownership in Save.dlc). "" = always unlocked (free packs).
@export var unlock_kind := ""

## Tests only: a Callable returning bool that replaces the ownership lookup for this pack (never set by the game).
var unlock_probe := Callable()

## Owned right now: asked from the profile every time (Save.dlc / Save.codes through DlcUnlock), never cached.
var is_unlocked: bool:
	get: return unlocked()

func unlocked() -> bool:
	if unlock_probe.is_valid(): return bool(unlock_probe.call())
	match unlock_kind:
		"": return true
		"construction": return DlcUnlock.owned()
		"pack": return DlcUnlock.owned(null, pack_id)
	return false

## The 2D badge kind (ui/pack_badge.gd).
func badge_kind() -> String:
	return badge_art if badge_art != "" else badge_icon

## The container wall colour.
func body() -> Color:
	return body_color if body_color.a > 0.01 else accent_color

## The weapon ids that are real weapons in `weapons` (Content.weapons): a pack never shows a tool the build cannot give.
func real_weapons(weapons: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in weapon_ids:
		if weapons.has(id) and not out.has(id): out.append(id)
	return out

## Why this pack cannot be shown ("" = fine): used by DLCPacks.all() to skip a broken pack instead of breaking the title.
func problem(weapons: Dictionary, maps: Dictionary) -> String:
	if pack_id == "" or display_name == "": return "no pack_id / display_name"
	if real_weapons(weapons).is_empty(): return "none of its weapon_ids exist"
	if not maps.has(arena_id): return "arena '%s' does not exist" % arena_id
	return ""
