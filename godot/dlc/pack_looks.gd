class_name PackLooks
extends RefCounted
## The cosmetics of the three DLC packs, looked up by WobblerLooks (hat_parts / skin_parts) and listed by data/extra/locker.json
## (`extra_hats`, `extra_skins`, `pack_items`). Each pack file (godot/dlc/<pack>/<pack>_looks.gd) holds its hats and outfits as part
## lists in the WobblerLooks format: [parent, geo, colour, pos, rot?, scale? | {"glow": hex, "glow_k": k}].


static func hat(id: String) -> Array:
	if KitchenLooks.HAT_IDS.has(id): return KitchenLooks.hat(id)
	if XmasLooks.HAT_IDS.has(id): return XmasLooks.hat(id)
	if AustraliaLooks.HAT_IDS.has(id): return AustraliaLooks.hat(id)
	return []


static func skin(id: String) -> Array:
	if KitchenLooks.SKIN_IDS.has(id): return KitchenLooks.skin(id)
	if XmasLooks.SKIN_IDS.has(id): return XmasLooks.skin(id)
	if AustraliaLooks.SKIN_IDS.has(id): return AustraliaLooks.skin(id)
	return []


## Outfits that replace the whole head and torso (no ears / nose / mouth are added to them).
static func replaces_head(id: String) -> bool:
	return KitchenLooks.FULL_BODY.has(id) or XmasLooks.FULL_BODY.has(id) or AustraliaLooks.FULL_BODY.has(id)


static func all_hat_ids() -> Array:
	return KitchenLooks.HAT_IDS + XmasLooks.HAT_IDS + AustraliaLooks.HAT_IDS


static func all_skin_ids() -> Array:
	return KitchenLooks.SKIN_IDS + XmasLooks.SKIN_IDS + AustraliaLooks.SKIN_IDS
