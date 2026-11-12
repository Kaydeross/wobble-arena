extends Label
## Shows the version and build number so a build can be recognised on a device.
## tools/build-ios.sh writes res://build_info.cfg; without it (editor runs) this shows "dev".

func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var build := "dev"
	var cfg := ConfigFile.new()
	if cfg.load("res://build_info.cfg") == OK:
		version = str(cfg.get_value("build", "version", version))
		build = str(cfg.get_value("build", "number", build))
		var commit := str(cfg.get_value("build", "commit", ""))
		if commit != "":
			build += " (" + commit + ")"
	text = "v%s  build %s" % [version, build]
