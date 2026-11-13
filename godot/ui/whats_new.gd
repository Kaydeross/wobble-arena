class_name WhatsNew
extends UiPage
## The What's new card (title: What's new): the patch notes from data/extra/news.json, newest first, in the same phone-style
## page as the Goals screen (UiPage frame, DragScroll list). Each entry is a heading button "v<version> · <title>" and
## its notes as "• note" lines; the newest entry starts open, the older ones fold away until you tap their heading.
## main.gd opens it once by itself when the newest version is one the player has not seen (Save.last_seen_news) and
## from the "What's new" button; opening it stores the newest version as seen.

const PATH := "res://data/extra/news.json"
const TOUCH := 62.0                ## canvas px: 45 pt on an iPhone in landscape (Apple asks 44)

var scroll: DragScroll
var rows: VBoxContainer
var entries: Array = []            ## [{version, title, notes}] newest first
var heads := {}                    ## version -> its heading button
var bodies := {}                   ## version -> its notes box

func _init() -> void:
	super._init()
	name = "WhatsNew"

## The entries of news.json, newest first (cleaned: only entries with a version; notes are strings). [] if unreadable.
static func load_entries(path: String = PATH) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path): return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary) or not (d.get("entries") is Array): return out
	for e: Variant in d["entries"]:
		if not (e is Dictionary): continue
		var v := str(e.get("version", ""))
		if v == "": continue
		var notes: Array = []
		if e.get("notes") is Array:
			for n: Variant in e["notes"]: notes.append(str(n))
		out.append({"version": v, "title": str(e.get("title", "")), "notes": notes})
	return out

## The newest version in the notes ("" if there are none).
static func newest_version(path: String = PATH) -> String:
	var all := load_entries(path)
	return "" if all.is_empty() else str(all[0]["version"])

func _ready() -> void:
	build_frame("What's new")
	var page := PanelContainer.new()
	page.name = "Page"
	page.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(page)
	scroll = DragScroll.new()
	scroll.name = "Scroll"
	page.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	scroll.tapped.connect(func(c: Control) -> void:
		var j := c.get_node_or_null("Juicy")
		if j: j._release())
	super._ready()

func open() -> void:
	super.open()
	refresh()
	var v := newest_version()
	if v != "": Save.mark_news_seen(v)

## Rebuilds the list from news.json.
func refresh() -> void:
	if rows == null: return
	for c in rows.get_children(): rows.remove_child(c); c.queue_free()
	heads.clear()
	bodies.clear()
	entries = load_entries()
	if entries.is_empty():
		var l := Label.new()
		l.name = "Empty"
		l.text = "No patch notes yet"
		l.theme_type_variation = &"MutedLabel"
		l.add_theme_font_size_override("font_size", 21)
		rows.add_child(l)
		return
	for i in entries.size():
		_entry(entries[i] as Dictionary, i == 0)
	JuicyButton.attach_all(rows)

func _entry(e: Dictionary, open_it: bool) -> void:
	var v: String = e["version"]
	var key := v.replace(".", "_")
	var h := Button.new()
	h.name = "Head_" + key
	h.text = "v%s · %s" % [v, e["title"]] if e["title"] != "" else "v" + v
	h.alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.custom_minimum_size = Vector2(0, TOUCH)
	h.add_theme_font_size_override("font_size", 24)
	h.add_theme_font_override("font", UiTheme.font(700))
	h.clip_text = true
	h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	rows.add_child(h)
	scroll.add_card(h)
	heads[v] = h
	var body := VBoxContainer.new()
	body.name = "Notes_" + key
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_constant_override("separation", 6)
	body.visible = open_it
	rows.add_child(body)
	bodies[v] = body
	for n: String in e["notes"]:
		var l := Label.new()
		l.name = "Note"
		l.text = "• " + n
		l.add_theme_font_size_override("font_size", 20)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(160, 0)
		l.size_flags_horizontal = SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		body.add_child(l)
	h.pressed.connect(toggle.bind(v))

## Folds an entry open or shut (its heading button).
func toggle(version: String) -> void:
	var b: Control = bodies.get(version)
	if b != null: b.visible = not b.visible
