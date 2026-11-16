class_name AdUi
extends RefCounted
## Shared monetization UI policy: the one visibility test the three rewarded placements (Double coins, 2x daily bonus,
## Arcade continue) and the Remove ads / Restore purchases rows use. Everything is looked up lazily from the scene tree,
## because a few tests load this script before the autoloads are registered as globals. A real AdMob / StoreKit provider
## only has to implement the Ads / Entitlements provider contracts; with none registered nothing here is visible.

const DOUBLE_COINS := "double_coins"
const DAILY_BONUS := "daily_bonus"
const ARCADE_CONTINUE := "arcade_continue"
const DAILY_BONUS_DAY := "ads_daily_bonus_day"   ## Settings key: the quest day whose 2x bonus was already granted

static func _root() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null

static func ads() -> Node:
	var r := _root()
	return r.get_node_or_null("Ads") if r != null else null

static func entitlements() -> Node:
	var r := _root()
	return r.get_node_or_null("Entitlements") if r != null else null

static func save() -> Node:
	var r := _root()
	return r.get_node_or_null("Save") if r != null else null

static func settings() -> Node:
	var r := _root()
	return r.get_node_or_null("Settings") if r != null else null

static func kids_mode() -> bool:
	var st := settings()
	return st != null and bool(st.call("get_value", "kids_mode", false))

static func owns_remove_ads() -> bool:
	var e := entitlements()
	return e != null and bool(e.call("has", "remove_ads"))

## The single visibility rule for every rewarded placement: a registered provider, ads on, consent resolved, not in a
## match / online lobby, not in kids mode, and not in the first-session grace for interstitials. `placement` names the
## reward (the three ids above) so a provider can report which one finished.
static func rewarded_visible(placement: String) -> bool:
	if placement == "": return false
	var a := ads()
	if a == null or not bool(a.call("has_provider")): return false
	if kids_mode(): return false
	return bool(a.call("can_request", "rewarded"))

## Remove ads / Restore purchases: a StoreKit provider is registered, the purchases kill switch is off and the player is
## not in kids mode. The local owned cache alone (Entitlements.has) never makes these rows appear.
static func purchases_visible() -> bool:
	var e := entitlements()
	if e == null or not bool(e.call("has_provider")): return false
	if kids_mode(): return false
	var r := _root()
	var rc: Node = r.get_node_or_null("RemoteConfig") if r != null else null
	return rc != null and not bool(rc.call("killed", "purchases"))

## Starts the provider's preload while a placement button is on screen (a no-op once it is loaded or not allowed).
static func prepare(placement: String) -> void:
	if not rewarded_visible(placement) or owns_remove_ads(): return
	var a := ads()
	if a == null: return
	if not bool(a.call("can_show", "rewarded")): a.call("request_load", "rewarded")

## Shows `placement` once and calls on_result(granted) after the provider's verified completion. With Remove ads owned
## there is no video: the same button grants the perk immediately. Returns false when nothing was requested.
static func request_reward(placement: String, on_result: Callable) -> bool:
	if not rewarded_visible(placement): return false
	if owns_remove_ads():
		on_result.call(true)
		return true
	var a := ads()
	if a == null or not a.has_method("show_rewarded"): return false
	if not bool(a.call("can_show", "rewarded")):
		a.call("request_load", "rewarded")          # a provider may load synchronously; otherwise the next tap shows
		if not bool(a.call("can_show", "rewarded")): return false
	var sig := a.get("reward_result") as Signal
	var cb := func(granted: bool, p: String) -> void:
		# The requester may have been freed while the ad was up (scene change): never call into a dead panel.
		if p == placement and on_result.is_valid(): on_result.call(granted)
	sig.connect(cb, CONNECT_ONE_SHOT)
	if not bool(a.call("show_rewarded", placement)):
		if sig.is_connected(cb): sig.disconnect(cb)
		return false
	return true
