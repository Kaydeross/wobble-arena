class_name LockerData
extends RefCounted
## The cosmetics catalogue for the Walldrobe, the Shop and the emote wheel: the web game's SKIN_SHOP, CODE_SKINS,
## FREE_SKINS, EMOTES, HAT_LABEL / HAT_ICON and the rarities (public/index.html ~4325, ~4775, ~4215, ~4936), copied
## into res://data/extra/locker.json (Godot-only data; tests/save_test.gd checks the prices still match the web game).
## Outfit looks (colours, names) come from cosmetics.json (shared/), hats from WobblerLooks.HATS.
## Rules (web): colours and hats are free; 8 outfits are free, the rest are bought in the Shop; Developer / Beta Tester
## come only from a redeem code; emotes cost coins except Wobble Dance (everyone has it), the two code emotes and the
## outfit emotes (Grand Pirouette comes with Ballerina Cappuccina and is never sold on its own).

const PATH := "res://data/extra/locker.json"
const RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "mythic"]
## web .ecard.r-* colours (build 75 store look)
const RAR_COL := {"common": Color("#8b96a3"), "uncommon": Color("#3fd070"), "rare": Color("#4a9cf0"),
	"epic": Color("#b86cf0"), "legendary": Color("#ffb02e"), "mythic": Color("#ff3d9a")}
## Names for the colour swatches (cosmetics.json swatch order).
const SWATCH_NAMES := ["Teal", "Red", "Blue", "Yellow", "Purple", "Green", "Orange", "White"]

static var _d: Dictionary = {}

static func data() -> Dictionary:
	if _d.is_empty():
		var v = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_d = v if v is Dictionary else {}
		if _d.is_empty(): push_error("LockerData: missing or invalid " + PATH)
	return _d

static func cosmetics() -> Dictionary:
	return WobblerLooks.data("cosmetics")

# ---------------- outfits ----------------

## Every outfit key in cosmetics.json (not "none").
static func all_skins() -> Array:
	return cosmetics().get("skins", {}).keys()

static func free_skins() -> Array:
	return data().get("free_skins", [])

static func is_shop_skin(k: String) -> bool:
	return data().get("skin_shop", {}).has(k)

static func is_code_skin(k: String) -> bool:
	return data().get("code_skins", {}).has(k)

static func skin_price(k: String) -> int:
	return int((data().get("skin_shop", {}).get(k, [0]) as Array)[0])

static func skin_rarity(k: String) -> String:
	if k == "none" or free_skins().has(k): return "common"
	if is_code_skin(k): return str(data()["code_skins"][k])
	return str((data().get("skin_shop", {}).get(k, [0, "common"]) as Array)[1])

static func skin_name(k: String) -> String:
	if k == "none": return "No outfit"
	return str(cosmetics().get("skins", {}).get(k, {}).get("name", k.capitalize()))

## Shop outfits, cheapest first (web renderShop).
static func shop_skins() -> Array:
	var ks: Array = data().get("skin_shop", {}).keys()
	ks.sort_custom(func(a: String, b: String) -> bool: return skin_price(a) < skin_price(b) or (skin_price(a) == skin_price(b) and a < b))
	return ks

## The emotes that only come with outfit `k` (web SKIN_EMOTES).
static func skin_emotes(k: String) -> Array:
	var out: Array = []
	var em: Dictionary = data().get("emotes", {})
	for id: String in em:
		if str(em[id].get("skin", "")) == k: out.append(id)
	return out

# ---------------- emotes ----------------

static func emote(id: String) -> Dictionary:
	return data().get("emotes", {}).get(id, {})

static func all_emotes() -> Array:
	return data().get("emotes", {}).keys()

static func emote_name(id: String) -> String:
	return str(emote(id).get("name", id))

static func emote_price(id: String) -> int:
	return int(emote(id).get("price", 0))

static func emote_rarity(id: String) -> String:
	return str(emote(id).get("rar", "common"))

## Sold in the Shop: has a price, not a code emote, not an outfit emote.
static func is_shop_emote(id: String) -> bool:
	var e := emote(id)
	return not e.is_empty() and int(e.get("price", 0)) > 0 and not e.get("code", false) and not e.has("skin")

static func shop_emotes() -> Array:
	var out: Array = []
	for id: String in all_emotes():
		if is_shop_emote(id): out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return emote_price(a) < emote_price(b) or (emote_price(a) == emote_price(b) and a < b))
	return out

# ---------------- hats, colours, rarity ----------------

static func hats() -> Array:
	var all: Array = cosmetics().get("hats", ["none"])
	var ex := DlcSave.exclusive_hats()
	var tree := Engine.get_main_loop() as SceneTree          # (the Save autoload by path: this script must compile without it, like in the --script tests)
	var sv: Node = tree.root.get_node_or_null("Save") if tree != null else null
	if ex.is_empty() or (sv != null and DlcSave.won_arcade(sv.dlc)): return all     # the Arcade victory hat is listed only once it is won
	return all.filter(func(h: String) -> bool: return not ex.has(h))

static func hat_name(h: String) -> String:
	return str(data().get("hat_label", {}).get(h, h.capitalize()))

## The colour swatches as ints (JSON numbers parse as floats).
static func swatch() -> Array:
	var out: Array = []
	for c in cosmetics().get("swatch", [WobblerLooks.DEFAULT_COLOR]): out.append(int(c))
	return out

static func color_name(c: int) -> String:
	var i := swatch().find(c)
	return SWATCH_NAMES[i] if i >= 0 and i < SWATCH_NAMES.size() else "Colour"

static func rarity_label(r: String) -> String:
	return str(data().get("rar_label", {}).get(r, r.capitalize()))

static func rarity_rank(r: String) -> int:
	return int(data().get("rar_rank", {}).get(r, 9))

static func rarity_color(r: String) -> Color:
	return RAR_COL.get(r, RAR_COL["common"])
