extends Node
## Provider-neutral sharing. A native sheet (StoreKit/UIActivityViewController on iOS, an Android Intent, or a desktop
## adapter) is injected with `set_provider`; this layer owns only the contract and the "is a sheet available?" question.
## Nothing third-party is bundled here and no image leaves the device until the provider hands the path to the OS.
## Docs: docs/SHARE.md.

signal shared(ok: bool, path: String)

var _provider: Object

## The provider contract: `share_image(path: String, text: String) -> bool` (true = the sheet accepted the request).
func set_provider(provider: Object) -> void:
	_provider = provider

## True only when a provider exposing the contract is registered: the results panel adds its Share control from this.
func has_provider() -> bool:
	return _provider != null and _provider.has_method("share_image")

## Hand one local PNG to the provider. Returns false when no provider exists or it refuses.
func share_image(path: String, text: String = "") -> bool:
	if not has_provider():
		return false
	var ok := _accepted(_provider.call("share_image", path, text))
	shared.emit(ok, path)
	return ok

## A provider may return nothing (void) or an explicit bool. Only `false` means refused.
static func _accepted(v: Variant) -> bool:
	return v != false
