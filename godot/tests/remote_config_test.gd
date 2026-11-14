extends SceneTree
## tests/test-remote-config.js starts the real server and checks the bundled/remote policy boundary.

const RC = preload("res://autoload/remote_config.gd")

func _init() -> void:
	var fallback := RC.read_config(RC.BUNDLED_PATH)
	assert(not fallback.is_empty(), "bundled remote config is missing")
	var clean := RC.validate({
		"schema": 99,
		"featured_mode": "bad id",
		"news": "x".repeat(300),
		"minimum_version": "nope",
		"ads": {
			"enabled": true,
			"interstitial_every_matches": 999,
			"interstitial_min_gap_s": 1,
			"first_session_grace_s": -4,
			"rewarded_enabled": true,
		},
		"kill_switches": {"ads": true},
		"secret": {"server": "must not pass through"},
	})
	assert(clean["schema"] == 1)
	assert(clean["featured_mode"] == "classic")
	assert(clean["news"].length() == 160)
	assert(clean["minimum_version"] == "0.3.0")
	assert(clean["ads"]["interstitial_every_matches"] == 20)
	assert(clean["ads"]["interstitial_min_gap_s"] == 30)
	assert(clean["ads"]["first_session_grace_s"] == 0)
	assert(clean["kill_switches"]["ads"])
	assert(not clean.has("secret"))
	assert(RC.version_less("0.2.9", "0.3.0"))
	assert(not RC.version_less("0.3.0", "0.3.0"))
	assert(RC.version_less("0.3.0", "1.0.0"))
	print("REMOTE_CONFIG ok")
	quit(0)
