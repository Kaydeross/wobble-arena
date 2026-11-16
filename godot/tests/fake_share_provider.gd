extends RefCounted
## Test double for the Share provider contract (docs/SHARE.md): accepts every share and records the calls.

var calls: Array = []

func share_image(path: String, text: String) -> bool:
	calls.append({"path": path, "text": text})
	return true
