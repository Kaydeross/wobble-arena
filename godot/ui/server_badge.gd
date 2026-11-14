class_name ServerBadge
extends PanelContainer
## A small reusable chip that names the server this player is on: "Official server · homeserver.tailcc5a5.ts.net",
## tinted by ServerInfo kind (green Official / amber Local / blue Custom), with the full URL in the tooltip.
## Screens add it themselves — `ServerBadge.new()` then setup(url) — so the title redesign can drop one into its header
## without touching ServerInfo. Nothing here talks to the network.

var info: Dictionary = {}
var label: Label

func _init() -> void:
	name = "ServerBadge"
	theme_type_variation = &"ChipPanel"
	mouse_filter = Control.MOUSE_FILTER_PASS
	label = Label.new()
	label.name = "Text"
	label.add_theme_font_size_override("font_size", 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)

## Point the badge at a URL ("" = the current Settings.server_url) and redraw it.
func setup(url: String = "") -> void:
	info = ServerInfo.classify(url)
	if label == null:   # _init may not have run yet if the caller built the node by script, but be safe
		label = get_node_or_null("Text") as Label
	if label != null: _apply()

## Re-read the current server (call after the settings change; the badge is not a listener).
func refresh() -> void:
	setup("")

## What the chip says (tests and tooltips).
func text() -> String:
	return label.text if label != null else ""

func kind() -> String:
	return str(info.get("kind", ""))

func host() -> String:
	return str(info.get("host", ""))

func _apply() -> void:
	label.text = "%s · %s" % [TranslationServer.translate(str(info.get("label", ""))), str(info.get("host", ""))]
	label.add_theme_color_override("font_color", info.get("color", UiTheme.TEXT))
	tooltip_text = str(info.get("url", ""))
