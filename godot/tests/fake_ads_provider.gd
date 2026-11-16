extends RefCounted
## Test-only rewarded-ad provider (the contract from the brief): load marks the placement ready, show completes it.
## Kept as its own file, not an inner class, because a `--script` SceneTree test with an inner class leaves the headless
## renderer's RID cleanup incomplete under Godot 4.7.2 (shutdown-only leak warnings, not a gameplay failure).
var ads: Node
var calls: Array = []
var finish := true

func load(placement: String) -> void:
	calls.append("load:" + placement)
	if ads != null: ads.mark_loaded(placement, true)

func show(placement: String, reward := "") -> void:
	calls.append("show:" + placement + (":" + reward if reward != "" else ""))
	if not finish or ads == null: return
	if placement == "interstitial": ads.finish_interstitial(true)
	else: ads.finish_rewarded(reward, true)
