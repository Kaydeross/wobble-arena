class_name DlcUnlock
extends RefCounted
## The Construction DLC unlock: bought with coins (PRICE) or opened by the developer code. The code is never stored: only
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

## Has the DLC: bought, or the developer code was used.
static func owned(sv: Object = null) -> bool:
	var s := _sv(sv)
	return bool(s.dlc.get("owned", false)) or s.codes.has("dev")

static func price() -> int:
	return PRICE

## Coins still missing for the DLC (0 when affordable).
static func missing(sv: Object = null) -> int:
	return maxi(0, PRICE - int(_sv(sv).coins))

## Buys the DLC with coins. false when owned already or too poor (nothing changes).
static func buy(sv: Object = null) -> bool:
	var s := _sv(sv)
	if owned(s) or int(s.coins) < PRICE: return false
	s.coins = int(s.coins) - PRICE
	s.dlc["owned"] = true
	s.commit()
	return true

static func hash_of(code: String) -> String:
	return (SALT + code.strip_edges()).sha256_text()

## Seconds left of the wrong-code cooldown (0 = none).
static func cooldown_left() -> float:
	return maxf(0.0, (_locked_until - Time.get_ticks_msec()) / 1000.0)

static func reset_attempts() -> void:
	_wrong = 0
	_locked_until = 0

## The developer code (exact, case-sensitive; spaces round it are ignored). true = DLC and everything else unlocked.
static func redeem(code: String, sv: Object = null) -> bool:
	return redeem_with(code, DEV_HASH, sv)

## redeem() against any hash (tests use a throwaway code / hash pair; the game always passes DEV_HASH).
static func redeem_with(code: String, hash: String, sv: Object = null) -> bool:
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
