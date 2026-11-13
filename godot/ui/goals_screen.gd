class_name GoalsScreen
extends UiPage
## The Goals screen (title: Goals): coin goals from logic/quests.gd through the Save autoload, in one phone-style list
## (DragScroll): today's three goals and the bonus for all three, this week's challenge, then the one-time milestones.
## Each row: the goal, a progress bar with "p / n", and a button that says the reward ("+100", disabled), "Claim +100"
## (done: tap to get the coins) or "Claimed". The header shows your coins and the play streak.

const ROW_H := 72.0
const TOUCH := 62.0                ## canvas px: 45 pt on an iPhone in landscape (Apple asks 44)
const BTN_W := 176.0

var scroll: DragScroll
var rows: VBoxContainer
var coins_l: Label
var streak_l: Label
var claim_bs := {}                 ## goal key -> its button

func _init() -> void:
	super._init()
	name = "Goals"

func _ready() -> void:
	build_frame("Goals")
	streak_l = Label.new()
	streak_l.name = "Streak"
	streak_l.theme_type_variation = &"MutedLabel"
	streak_l.add_theme_font_size_override("font_size", 17)
	streak_l.size_flags_horizontal = SIZE_EXPAND_FILL
	streak_l.size_flags_vertical = SIZE_SHRINK_CENTER
	streak_l.clip_text = true
	streak_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(streak_l)
	var chip := PanelContainer.new()
	chip.name = "Coins"
	chip.theme_type_variation = &"ChipPanel"
	chip.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	row.add_child(LockerScreen.LockerIcon.new("coin", 22))
	coins_l = Label.new()
	coins_l.name = "N"
	coins_l.add_theme_font_size_override("font_size", 20)
	coins_l.add_theme_font_override("font", UiTheme.font(700))
	coins_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(coins_l)
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
	Save.changed.connect(func() -> void: if visible: _refresh_head())
	super._ready()

func open() -> void:
	super.open()
	refresh()

## Rebuilds the list from the save (after a claim, or when opened).
func refresh() -> void:
	if rows == null: return
	for c in rows.get_children(): rows.remove_child(c); c.queue_free()
	claim_bs.clear()
	var group := ""
	for r: Dictionary in Save.goal_rows():
		var g: String = {"daily": "Today", "bonus": "Today", "weekly": "This week", "ach": "Milestones"}[r["group"]]
		if g != group:
			group = g
			_section(g)
		_row(r)
	JuicyButton.attach_all(rows)
	_refresh_head()

func _refresh_head() -> void:
	coins_l.text = str(Save.coins)
	var n := int(Save.quests.get("streak", {}).get("n", 0))
	var on := int(Save.quests.get("streak", {}).get("last", -1)) >= Save.quest_day() - 1
	streak_l.text = "Play streak: %d day%s. First win of the day pays a bonus. Roll on!" % [n, "" if n == 1 else "s"] if on and n > 0 \
		else "Win a match each day to build a streak. Wobble daily!"
	streak_l.tooltip_text = streak_l.text

func _section(t: String) -> void:
	var l := Label.new()
	l.name = "Sec_" + t.replace(" ", "")
	l.text = t
	l.theme_type_variation = &"TitleLabel"
	l.add_theme_font_size_override("font_size", 24)
	rows.add_child(l)

func _row(r: Dictionary) -> void:
	var key: String = r["key"]
	var row := HBoxContainer.new()
	row.name = "G_" + key.replace(":", "_")
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 14)
	rows.add_child(row)
	var v := VBoxContainer.new()
	v.name = "Words"
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_theme_constant_override("separation", 4)
	row.add_child(v)
	var t := Label.new()
	t.name = "Label"
	t.text = r["text"]
	t.add_theme_font_size_override("font_size", 21)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(160, 0)
	v.add_child(t)
	var pr := HBoxContainer.new()
	pr.name = "Progress"
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_theme_constant_override("separation", 10)
	v.add_child(pr)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.show_percentage = false
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(80, 12)
	bar.max_value = maxi(1, int(r["n"]))
	bar.value = int(r["p"])
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", UiTheme.box(Color(0, 0, 0, 0.35), 6, Color(1, 1, 1, 0.12), 1, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.GOOD if r["done"] else UiTheme.ACCENT, 6, Color.TRANSPARENT, 0, 0))
	pr.add_child(bar)
	var n := Label.new()
	n.name = "N"
	n.text = "%d / %d" % [int(r["p"]), int(r["n"])]
	n.theme_type_variation = &"MutedLabel"
	n.add_theme_font_size_override("font_size", 15)
	pr.add_child(n)
	var b := Button.new()
	b.name = "Claim"
	b.custom_minimum_size = Vector2(BTN_W, TOUCH)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 20)
	if r["claimed"]:
		b.text = "Claimed"
		b.disabled = true
	elif r["done"]:
		b.text = "Claim +%d" % int(r["coins"])
		b.theme_type_variation = &"PrimaryButton"
	else:
		b.text = "+%d" % int(r["coins"])
		b.disabled = true
		b.tooltip_text = "Finish the goal to claim %d coins" % int(r["coins"])
	b.pressed.connect(claim.bind(key))
	row.add_child(b)
	scroll.add_card(b)
	claim_bs[key] = b

## Claims a goal (its button): the coins go to your wallet. Returns the coins.
func claim(key: String) -> int:
	var got := Save.claim_goal(key)
	if got > 0:
		Sfx.play("pickup")
		var sv := scroll.scroll_vertical
		refresh()
		scroll.scroll_vertical = sv
	return got
