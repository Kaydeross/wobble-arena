extends Node
## Store-neutral owned rights. A native StoreKit/Play adapter reports verified purchases here; gameplay asks only
## `has()` and never imports a store API. The local copy is an offline cache, not proof of purchase: restore/settlement
## must remain available when the network returns.

signal changed(id: String, owned: bool)

const REMOVE_ADS := "remove_ads"
const KNOWN := [REMOVE_ADS]
const CACHE_PREFIX := "entitlement_"

var _owned := {}
var _provider: Object

func _ready() -> void:
	for id: String in KNOWN:
		_owned[id] = bool(Settings.get_value(CACHE_PREFIX + id, false))

func has(id: String) -> bool:
	return bool(_owned.get(id, false))

func remove_ads() -> bool:
	return has(REMOVE_ADS)

## Register a provider exposing `purchase(id)`, `restore()` and `owned(id)`. This keeps plugin choice replaceable during
## the StoreKit sandbox comparison.
func set_provider(provider: Object) -> void:
	_provider = provider

func purchase(id: String) -> bool:
	if id not in KNOWN or _provider == null or not _provider.has_method("purchase"):
		return false
	return _accepted(_provider.call("purchase", id))

func restore() -> bool:
	if _provider == null or not _provider.has_method("restore"):
		return false
	return _accepted(_provider.call("restore"))

## A provider's purchase/restore may return nothing (void) or an explicit bool. Only `false` means refused.
static func _accepted(v: Variant) -> bool:
	return v != false

## Call only with a provider-verified purchase or a successful restore receipt.
func grant_verified(id: String) -> void:
	if id not in KNOWN: return
	_owned[id] = true
	Settings.set_value(CACHE_PREFIX + id, true)
	changed.emit(id, true)

func revoke(id: String) -> void:
	if id not in KNOWN: return
	_owned[id] = false
	Settings.set_value(CACHE_PREFIX + id, false)
	changed.emit(id, false)

## A provider can refresh the cache after receipt validation. Unverified client JSON never calls this.
func refresh_from_provider() -> void:
	if _provider == null or not _provider.has_method("owned"):
		return
	for id: String in KNOWN:
		if _provider.call("owned", id) == true and not has(id):
			grant_verified(id)
