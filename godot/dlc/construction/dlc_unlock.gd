class_name DlcUnlock
extends RefCounted
## The DLC unlock for every pack (Construction, On Fire, Ho Ho Ho, Hey Mate; ids in dlc/pack_registry.gd): bought with coins
## (PRICE, or the pack's own `price` in its hub.json) or opened by the developer code. Every function takes the pack id last
## ("" = Construction, so every older call is unchanged); the profile part per pack is DlcSave (Save.dlc). The code is never stored: only
## its salted SHA-256 (DEV_HASH) is compared, and it is never logged. The state lives in the profile (Save.dlc, blob key
## "dlc"; Save.codes gets "dev" for the developer code).
## The developer code unlocks the DLC and EVERYTHING else: every outfit, every emote, every class (the secret ones too)
## and 5000 coins once. Three wrong tries in a row start a short cooldown.

const PRICE := 1500
const SALT := "wobblers-arena-dlc-v1:"
const DEV_HASH := "681c91ace53b79550c9eb56e21e7b2c9fb777ad93590db4128bfaedfd2ac52a5"
const DEV_COINS := 5000
const MAX_TRIES := 3
const COOLDOWN_MS := 1500

static var _wrong := 0
static var _locked_until := 0

static func _sv(sv: Object) -> Object:
	return sv if sv != null else Save

## Is `pack` one this build sells? Construction always; every other pack needs its hub file (PackRegistry).
static func known(pack: String = "") -> bool:
	return DlcSave.is_base(pack) or PackRegistry.has(pack)

## Has the DLC: bought, or the developer code was used. A pack this build does not know is never owned.
static func owned(sv: Object = null, pack: String = "") -> bool:
	if not known(pack): return false
	var s := _sv(sv)
	return DlcSave.owns(s.dlc, s.codes, pack)

static func price(pack: String = "") -> int:
	return PRICE if DlcSave.is_base(pack) else PackRegistry.price(pack)

## Coins still missing for the DLC (0 when affordable).
static func missing(sv: Object = null, pack: String = "") -> int:
	return maxi(0, price(pack) - int(_sv(sv).coins))

## Buys the DLC with coins. false when owned already, unknown or too poor (nothing changes). Once per pack.
static func buy(sv: Object = null, pack: String = "") -> bool:
	var s := _sv(sv)
	if not known(pack) or owned(s, pack) or int(s.coins) < price(pack): return false
	var pid := DlcSave.BASE_PACK if DlcSave.is_base(pack) else pack
	s.coins = int(s.coins) - price(pack)
	DlcSave.set_owned(s.dlc, pid, true)
	grant_pack_items(s, pid)
	if s.has_method("_wallet_active") and bool(s.call("_wallet_active")) and s.get("cloud") != null:
		s.get("cloud").wallet_spend("dlc", pid, price(pack))   # signed in: the server confirms the 1500-coin purchase
	s.commit()
	return true

## Phase B hook (cosmetics): gives a pack's outfits once, through LockerData.grant_pack_skins(Save, pack) when it exists
## (looked up by name, so this tree runs with or without it). Called on purchase, on load for owners and by the dev code.
static func grant_pack_items(s: Object, pack: String) -> void:
	var ld: Variant = load("res://ui/locker_data.gd")
	if ld != null and ld.has_method("grant_pack_skins"): ld.grant_pack_skins(s, pack)

## Every owned pack's grant (a load, the dev code).
static func grant_owned(s: Object) -> void:
	for id: String in PackRegistry.ids():
		if owned(s, id): grant_pack_items(s, id)

static func hash_of(code: String) -> String:
	return (SALT + code.strip_edges()).sha256_text()

## Seconds left of the wrong-code cooldown (0 = none).
static func cooldown_left() -> float:
	return maxf(0.0, (_locked_until - Time.get_ticks_msec()) / 1000.0)

static func reset_attempts() -> void:
	_wrong = 0
	_locked_until = 0

## The developer code works in debug / editor builds only; a release export refuses it (and the 7-tap entry is hidden).
static func dev_code_allowed() -> bool:
	return not OS.has_feature("release")

## The developer code (exact, case-sensitive; spaces round it are ignored). true = DLC and everything else unlocked.
static func redeem(code: String, sv: Object = null) -> bool:
	return redeem_with(code, DEV_HASH, sv)

## redeem() against any hash (tests use a throwaway code / hash pair; the game always passes DEV_HASH).
static func redeem_with(code: String, hash: String, sv: Object = null) -> bool:
	if not dev_code_allowed(): return false
	if cooldown_left() > 0.0: return false
	if hash_of(code) != hash:
		_wrong += 1
		if _wrong >= MAX_TRIES:
			_wrong = 0
			_locked_until = Time.get_ticks_msec() + COOLDOWN_MS
		return false
	_wrong = 0
	var s := _sv(sv)
	s.dlc["owned"] = true
	if not s.codes.has("dev"): s.codes.append("dev")
	unlock_everything(s)
	grant_owned(s)
	if not bool(s.dlc.get("bonus", false)):
		s.dlc["bonus"] = true
		s.coins = int(s.coins) + DEV_COINS
	s.commit()
	return true

## Every outfit (shop and code ones), every emote and every extra class (secret ones too) into the profile.
static func unlock_everything(s: Object) -> void:
	for k: String in LockerData.all_skins():
		if WobblerLooks.skin_def(k).size() > 0 and not s.skins.has(k): s.skins.append(k)
	for id: String in LockerData.all_emotes():
		if not s.owned.has(id): s.owned.append(id)
	for id: String in ExtraClasses.data().keys():
		if not s.classes.has(id): s.classes.append(id)
