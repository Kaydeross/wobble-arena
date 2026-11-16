extends RefCounted
## Test-only StoreKit / Play provider: every purchase and restore is accepted; `owned()` only reports ids that were
## bought through `purchase()`. A separate file (not an inner class) for the reason in fake_ads_provider.gd.
var owned_ids: Array = []

func purchase(id: String) -> bool:
	owned_ids.append(id)
	return true

func restore() -> bool:
	return true

func owned(id: String) -> bool:
	return owned_ids.has(id)
