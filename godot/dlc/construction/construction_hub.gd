class_name ConstructionHub
extends UiPage
## The Construction hub (title: the yellow Construction banner): two big cards, CLASSIC (up to 8 fighters on a random
## building site, offline) and ARCADE (boss rush, built by dlc/construction/arcade_manager.gd when it exists).
## Locked (DLC not owned: DlcUnlock): the cards are dimmed with a padlock, "Unlock for N coins" buys it ("Need N more"
## when short) and "Enter code" opens the code sheet. Owned: Classic opens a small pre-match card (bots 1..7, bot skill,
## the site seed with Random / Re-roll, Start). Start writes the Settings keys mode, bots, difficulty, offline_map
## ("sitegen" when that map exists, else "siteyard") and site_seed (0 = a new site every match), then `start_requested`
## (scripts/main.gd: play_offline). Arcade: `arcade_requested` (the arcade manager hooks it), "Coming soon" until it exists.
## The Arcade card is the SOLO run; the two-seat online co-op run is an online room now (Play online > Host a room >
## Room type: Arcade co-op, scripts/main.gd: host_room), so this hub has no co-op entry point.
## The difficulty step also has the co-op friendly-fire toggle (Settings arcade_ff, off by default; the online co-op room
## reads it and it travels in start.arc.ff).

signal start_requested(opts: Dictionary)
signal arcade_requested

const ARCADE_MANAGER := "res://dlc/construction/arcade_manager.gd"
const BOT_MIN := 1
const BOT_MAX := 7
const DIFFS := ["easy", "normal", "hard", "insane"]
const SEED_MAX := 999999
const TOUCH := 62.0
const CARD_H := 224.0

var bots := BOT_MAX               ## default 7: eight fighters
var diff := "normal"
var site_seed := 0                ## 0 = random per match
var coins_l: Label
var main_view: VBoxContainer
var classic_card: Button
var arcade_card: Button
var classic_b: Button             ## the cards themselves (the tap targets)
var arcade_b: Button
var buy_row: HBoxContainer
var buy_b: Button
var code_b: Button
var pre: PanelContainer
var seed_l: Label
var start_b: Button
var code_sheet: DlcCodeSheet
var arc_step := 0                 ## the Arcade flow: 0 = the cards, 1 = pick the class, 2 = pick the difficulty
var arc_diff := "normal"
var arc_wizard: SetupWizard       ## the Character page of the setup wizard (class_only), reused as the Arcade's class step
var arc_class_box: VBoxContainer
var arc_diff_box: HBoxContainer
var arc_foot: HBoxContainer
var arc_next: Button
var arc_ff: CheckButton           ## co-op friendly fire (Settings arcade_ff; off by default; the online co-op room reads it)
var _diff_cards := {}             ## difficulty id -> its card Button
var _bot_bs := {}
var _diff_bs := {}
var _locks: Array = []            ## the padlock controls (shown while locked)
var _tags := {}                   ## card -> its footer label

func _init() -> void:
	super._init()
	name = "ConstructionHub"

func _ready() -> void:
	build_frame("Construction")
	var sp := Control.new()
	sp.name = "Spacer"
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
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
	main_view = VBoxContainer.new()
	main_view.name = "Main"
	main_view.size_flags_vertical = SIZE_EXPAND_FILL
	main_view.alignment = BoxContainer.ALIGNMENT_CENTER
	main_view.add_theme_constant_override("separation", UiTheme.SP_3)
	col.add_child(main_view)
	var cards := HBoxContainer.new()
	cards.name = "Cards"
	cards.add_theme_constant_override("separation", UiTheme.SP_4)
	main_view.add_child(cards)
	classic_card = _card("Classic", "Classic", "Up to 8 on a random building site. Hard hats on, tools out.")
	cards.add_child(classic_card)
	arcade_card = _card("Arcade", "Arcade", "Boss rush: Tradies, Engineer, Designer, Supervisor, Project Manager, then the Client.")
	cards.add_child(arcade_card)
	cards.resized.connect(fit_cards.call_deferred)
	classic_b = classic_card
	arcade_b = arcade_card
	classic_b.pressed.connect(open_pre)
	arcade_b.pressed.connect(func() -> void: if arcade_ready(): show_arcade(1))
	buy_row = HBoxContainer.new()
	buy_row.name = "BuyRow"
	buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	buy_row.add_theme_constant_override("separation", UiTheme.SP_4)
	main_view.add_child(buy_row)
	buy_b = Button.new()
	buy_b.name = "Buy"
	buy_b.theme_type_variation = &"PrimaryButton"
	buy_b.custom_minimum_size = Vector2(320, TOUCH)
	buy_b.add_theme_font_size_override("font_size", 22)
	buy_b.pressed.connect(buy)
	buy_row.add_child(buy_b)
	code_b = Button.new()
	code_b.name = "Code"
	code_b.text = "Enter code"
	code_b.custom_minimum_size = Vector2(220, TOUCH)
	code_b.add_theme_font_size_override("font_size", 22)
	code_b.pressed.connect(open_code)
	buy_row.add_child(code_b)
	_build_pre()
	_build_arcade()
	code_sheet = DlcCodeSheet.new()
	add_child(code_sheet)
	code_sheet.redeemed.connect(refresh)
	code_sheet.closed.connect(func() -> void:
		refresh()
		if Tier.is_pc() and visible: (code_b if code_b.is_visible_in_tree() else classic_b).grab_focus.call_deferred())
	JuicyButton.attach_all(buy_row)
	Save.changed.connect(func() -> void: if visible: refresh())
	super._ready()

func open() -> void:
	super.open()
	diff = str(Settings.get_value("difficulty", "normal"))
	if not DIFFS.has(diff): diff = "normal"
	site_seed = clampi(int(Settings.get_value("site_seed", 0)), 0, SEED_MAX)
	arc_diff = DlcSave.norm(str(Settings.get_value("arcade_diff", "normal")))
	if arc_ff != null: arc_ff.set_pressed_no_signal(bool(Settings.get_value("arcade_ff", false)))
	show_arcade(0)
	show_pre(false)
	refresh()
	if Tier.is_pc(): (classic_b if DlcUnlock.owned() else buy_b).grab_focus.call_deferred()

func back() -> bool:
	if code_sheet.visible: return code_sheet.back()
	if arc_step > 0:
		show_arcade(arc_step - 1)
		return true
	if pre.visible:
		show_pre(false)
		return true
	close()
	return true

# ---------------- the cards ----------------

## One big card (a button, like the wizard's cards): hazard tape on top, the name (and a padlock while locked), the
## description and a footer line. The card is as tall as its words need (fit_cards).
func _card(node_name: String, title: String, desc: String) -> Button:
	var c := Button.new()
	c.name = node_name
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(0, CARD_H)
	for st: String in ["normal", "disabled", "pressed", "hover_pressed", "hover", "focus"]:
		var sb := UiTheme.box(Color(0.075, 0.2, 0.245, 0.96), UiTheme.RADIUS, ConstructionStyle.YELLOW, 3, 6)
		if st == "hover": sb.bg_color = Color(0.1, 0.26, 0.31, 0.98)
		if st == "pressed" or st == "hover_pressed": sb.bg_color = Color(0.05, 0.15, 0.19, 1.0)
		if st == "focus":
			sb.draw_center = false
			sb.border_color = Color.WHITE
			sb.shadow_size = 0
		c.add_theme_stylebox_override(st, sb)
	var m := MarginContainer.new()
	m.name = "Margin"
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]: m.add_theme_constant_override("margin_" + side, UiTheme.SP_4)
	for side: String in ["top", "bottom"]: m.add_theme_constant_override("margin_" + side, UiTheme.SP_3)
	c.add_child(m)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", UiTheme.SP_2)
	m.add_child(v)
	var tape := ConstructionStyle.Hazard.new()
	tape.name = "Tape"
	tape.custom_minimum_size = Vector2(0, 12)
	v.add_child(tape)
	var top := HBoxContainer.new()
	top.name = "Top"
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", UiTheme.SP_3)
	v.add_child(top)
	var t := Label.new()
	t.name = "Name"
	t.text = title
	t.add_theme_font_size_override("font_size", 36)
	t.add_theme_font_override("font", UiTheme.font(700))
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(t)
	var lock := ConstructionStyle.Padlock.new()
	lock.name = "Lock"
	lock.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(lock)
	_locks.append(lock)
	var d := Label.new()
	d.name = "Desc"
	d.text = desc
	d.theme_type_variation = &"MutedLabel"
	d.add_theme_font_size_override("font_size", 20)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(120, 0)
	d.size_flags_vertical = SIZE_EXPAND_FILL
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(d)
	var tag := Label.new()
	tag.name = "Tag"
	tag.add_theme_font_size_override("font_size", 20)
	tag.add_theme_font_override("font", UiTheme.font(700))
	tag.add_theme_color_override("font_color", UiTheme.ACCENT)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(tag)
	_tags[c] = tag
	return c

## Both cards as tall as the taller one's words need (never under CARD_H): a button's own minimum ignores what is
## inside it, so the height is set from the stack here, once the wrapped lines are known.
func fit_cards() -> void:
	var h := CARD_H
	for c: Button in [classic_card, arcade_card]:
		var st := c.get_node("Margin/Stack") as Control
		h = maxf(h, st.get_combined_minimum_size().y + 2.0 * UiTheme.SP_3)
	for c: Button in [classic_card, arcade_card]:
		if not is_equal_approx(c.custom_minimum_size.y, h): c.custom_minimum_size.y = h

## Is the Arcade mode built yet (unit D adds the manager)?
static func arcade_ready() -> bool:
	return ResourceLoader.exists(ARCADE_MANAGER)

func refresh() -> void:
	if buy_b == null: return
	var own := DlcUnlock.owned()
	coins_l.text = str(Save.coins)
	for l: Control in _locks: l.visible = not own
	var arc := arcade_ready()
	classic_card.modulate = Color.WHITE if own else Color(1, 1, 1, 0.55)
	arcade_card.modulate = Color.WHITE if own and arc else Color(1, 1, 1, 0.55)
	classic_b.disabled = not own
	arcade_b.disabled = not own or not arc
	var best := DlcSave.best(Save.dlc, arc_diff)
	var ct := tr("Play") if own else tr("Unlock to play")
	var at := ""
	if not arc: at = tr("Coming soon")
	elif not own: at = tr("Unlock to play")
	else: at = tr("Best: stage %d/%d") % [best, ArcadeManager.count()] if best > 0 else tr("Play")
	(_tags[classic_card] as Label).text = ct
	(_tags[arcade_card] as Label).text = at
	for c: Button in [classic_card, arcade_card]:
		(_tags[c] as Label).visible = (_tags[c] as Label).text != ""
	buy_row.visible = not own
	var miss := DlcUnlock.missing()
	buy_b.text = (tr("Unlock for %d coins") % DlcUnlock.price()) if miss <= 0 else tr("Need %d more") % miss
	buy_b.disabled = miss > 0
	classic_b.tooltip_text = "" if own else tr("Unlock Construction first")
	fit_cards.call_deferred()

func buy() -> bool:
	if not DlcUnlock.buy(): return false
	Sfx.play("pickup")
	refresh()
	return true

func open_code() -> void:
	code_sheet.open()

# ---------------- the Arcade flow: class, then difficulty, then Start ----------------

const DIFF_COLORS := {"easy": Color("#5fd37a"), "normal": Color("#ffb637"), "nightmare": Color("#ff5a4d")}
const DIFF_CARD_H := 168.0

func _build_arcade() -> void:
	arc_class_box = VBoxContainer.new()
	arc_class_box.name = "ArcadeClass"
	arc_class_box.visible = false
	arc_class_box.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(arc_class_box)
	arc_diff_box = HBoxContainer.new()
	arc_diff_box.name = "ArcadeDifficulty"
	arc_diff_box.visible = false
	arc_diff_box.size_flags_vertical = SIZE_EXPAND_FILL
	arc_diff_box.alignment = BoxContainer.ALIGNMENT_CENTER
	arc_diff_box.add_theme_constant_override("separation", UiTheme.SP_3)
	col.add_child(arc_diff_box)
	var grp := ButtonGroup.new()
	for d: String in DlcSave.DIFFS:
		var c := _diff_card(d, grp)
		arc_diff_box.add_child(c)
		_diff_cards[d] = c
	arc_diff_box.resized.connect(fit_diff_cards.call_deferred)
	arc_foot = HBoxContainer.new()
	arc_foot.name = "ArcadeFoot"
	arc_foot.visible = false
	arc_foot.alignment = BoxContainer.ALIGNMENT_CENTER
	arc_foot.add_theme_constant_override("separation", UiTheme.SP_3)
	col.add_child(arc_foot)
	arc_next = Button.new()
	arc_next.name = "ArcadeNext"
	arc_next.theme_type_variation = &"PrimaryButton"
	arc_next.custom_minimum_size = Vector2(300, 62)
	arc_next.add_theme_font_size_override("font_size", 28)
	arc_next.pressed.connect(arcade_next)
	arc_foot.add_child(arc_next)
	# Co-op friendly fire (owner decision: off by default). A plain English label like before, shown on the difficulty
	# step only; it writes Settings arcade_ff, which the online co-op room (hosted from Play online) reads for its run.
	arc_ff = CheckButton.new()
	arc_ff.name = "ArcadeFF"
	arc_ff.text = "Friendly fire"
	arc_ff.tooltip_text = "Online co-op: let the two players hurt each other. Off by default."
	arc_ff.add_theme_font_size_override("font_size", 20)
	arc_ff.custom_minimum_size = Vector2(0, 48)
	arc_ff.toggled.connect(_set_arc_ff)
	arc_foot.add_child(arc_ff)
	JuicyButton.attach_all(arc_foot)

func _diff_card(d: String, grp: ButtonGroup) -> Button:
	var accent: Color = DIFF_COLORS[d]
	var c := Button.new()
	c.name = d
	c.toggle_mode = true
	c.button_group = grp
	c.size_flags_horizontal = SIZE_EXPAND_FILL
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	c.custom_minimum_size = Vector2(0, DIFF_CARD_H)
	for st: String in ["normal", "disabled", "pressed", "hover_pressed", "hover", "focus"]:
		var sel := st == "pressed" or st == "hover_pressed"
		var sb := UiTheme.box(Color(0.075, 0.2, 0.245, 0.96).lerp(accent, 0.22 if sel else 0.0), UiTheme.RADIUS, accent if sel else accent.darkened(0.45), 5 if sel else 3, 6)
		if st == "hover": sb.bg_color = Color(0.1, 0.26, 0.31, 0.98)
		if st == "focus":
			sb.draw_center = false
			sb.border_color = Color.WHITE
			sb.shadow_size = 0
		c.add_theme_stylebox_override(st, sb)
	var m := MarginContainer.new()
	m.name = "Margin"
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + side, UiTheme.SP_3)
	c.add_child(m)
	var v := VBoxContainer.new()
	v.name = "Stack"
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", UiTheme.SP_2)
	m.add_child(v)
	var n := Label.new()
	n.name = "Name"
	n.add_theme_font_size_override("font_size", 28)
	n.add_theme_font_override("font", UiTheme.font(700))
	n.add_theme_color_override("font_color", accent)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var ds := Label.new()
	ds.name = "Desc"
	ds.theme_type_variation = &"MutedLabel"
	ds.add_theme_font_size_override("font_size", 19)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(60, 0)
	ds.size_flags_vertical = SIZE_EXPAND_FILL
	ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ds)
	var b := Label.new()
	b.name = "Best"
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_font_override("font", UiTheme.font(700))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(b)
	c.pressed.connect(pick_diff.bind(d))
	return c

## The three difficulty cards as tall as the longest words need (never under DIFF_CARD_H): a button's own minimum ignores what is inside it.
func fit_diff_cards() -> void:
	var h := DIFF_CARD_H
	for c: Button in _diff_cards.values():
		h = maxf(h, (c.get_node("Margin/Stack") as Control).get_combined_minimum_size().y + 2.0 * UiTheme.SP_3)
	for c: Button in _diff_cards.values():
		if not is_equal_approx(c.custom_minimum_size.y, h): c.custom_minimum_size.y = h

static func diff_name(d: String) -> String:
	return {"easy": "Easy", "normal": "Normal", "nightmare": "Nightmare"}.get(d, "Normal")

static func diff_desc(d: String) -> String:
	return {"easy": "Softer foes, fewer hazards, five lives. A relaxed first run.",
		"normal": "A fair fight with four lives. Bosses still bite.",
		"nightmare": "The full boss rush: tough bosses, three lives, the best coin rewards."}.get(d, "")

## "Best: stage 4/6", "Cleared" or "Not played yet" for a difficulty.
func best_text(d: String) -> String:
	var b := DlcSave.best(Save.dlc, d)
	if b >= ArcadeManager.count() or DlcSave.won_diff(Save.dlc, d): return tr("Cleared")
	return tr("Best: stage %d/%d") % [b, ArcadeManager.count()] if b > 0 else tr("Not played yet")

## step 0 = the two cards, 1 = class, 2 = difficulty (the Arcade flow replaces the cards).
func show_arcade(step: int) -> void:
	if step > 0 and not DlcUnlock.owned(): step = 0
	arc_step = step
	var on := step > 0
	main_view.visible = not on and not pre.visible
	arc_class_box.visible = step == 1
	arc_diff_box.visible = step == 2
	arc_foot.visible = on
	arc_ff.visible = step == 2                     # the co-op/difficulty step owns the friendly-fire option
	if step == 2: arc_ff.set_pressed_no_signal(bool(Settings.get_value("arcade_ff", false)))
	if step == 1:
		if arc_wizard == null:
			arc_wizard = SetupWizard.new()
			arc_wizard.class_only = true
			arc_wizard.name = "Wizard"
			arc_wizard.size_flags_vertical = SIZE_EXPAND_FILL
			arc_class_box.add_child(arc_wizard)
		else:
			arc_wizard.go(SetupWizard.P_CHAR)
		title_l.text = tr("Pick your character")
		arc_next.text = tr("Next")
	elif step == 2:
		title_l.text = tr("Pick a difficulty")
		arc_next.text = tr("Start")
		for d: String in _diff_cards:
			var c: Button = _diff_cards[d]
			(c.get_node("Margin/Stack/Name") as Label).text = tr(diff_name(d))
			(c.get_node("Margin/Stack/Desc") as Label).text = tr(diff_desc(d))
			(c.get_node("Margin/Stack/Best") as Label).text = best_text(d)
			c.set_pressed_no_signal(d == arc_diff)
		fit_diff_cards.call_deferred()
		if Tier.is_pc(): (_diff_cards[arc_diff] as Button).grab_focus.call_deferred()
	else:
		title_l.text = tr("Construction")
		if Tier.is_pc() and is_visible_in_tree(): (classic_b if DlcUnlock.owned() else buy_b).grab_focus.call_deferred()

func pick_diff(d: String) -> void:
	arc_diff = DlcSave.norm(d)
	Settings.set_value("arcade_diff", arc_diff)
	for k: String in _diff_cards: (_diff_cards[k] as Button).set_pressed_no_signal(k == arc_diff)
	refresh()

## The co-op friendly-fire toggle: remembered in Settings (read by the online Arcade co-op room's begin_host).
func _set_arc_ff(on: bool) -> void:
	Settings.set_value("arcade_ff", on)

## The class a run starts with: the wizard's pick (the Settings "class" it keeps), else the saved class.
func arcade_class() -> String:
	var id := arc_wizard.cls if arc_wizard != null else str(Settings.get_value("class", "wobbler"))
	return id if Content.classes.has(id) and SetupWizard.owns_class(id) else "wobbler"

## Next on the class step, Start on the difficulty step (which hands over to main.play_arcade).
func arcade_next() -> void:
	if arc_step == 1:
		show_arcade(2)
	elif arc_step == 2:
		Settings.set_value("arcade_diff", arc_diff)
		Settings.set_value("class", arcade_class())
		arcade_requested.emit()

# ---------------- the pre-match card ----------------

func _build_pre() -> void:
	pre = PanelContainer.new()
	pre.name = "PreMatch"
	pre.visible = false
	pre.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(pre)
	var v := VBoxContainer.new()
	v.name = "Rows"
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", UiTheme.SP_3)
	pre.add_child(v)
	var ns: Array = []
	for n in range(BOT_MIN, BOT_MAX + 1): ns.append(n)
	_pills(v, "Bots", "Bots", ns, ns, _bot_bs, set_bots, 64)
	var dn: Array = []
	for d: String in DIFFS: dn.append(tr(d.capitalize()))
	_pills(v, "Skill", "Bot skill", DIFFS, dn, _diff_bs, set_diff, 100)
	var sr := HBoxContainer.new()
	sr.name = "Seed"
	sr.add_theme_constant_override("separation", UiTheme.SP_3)
	v.add_child(sr)
	var sl := _label("Site seed", 18, "MutedLabel")
	sl.custom_minimum_size = Vector2(124, 0)
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sr.add_child(sl)
	seed_l = _label("", 24, "")
	seed_l.name = "Value"
	seed_l.add_theme_font_override("font", UiTheme.font(700))
	seed_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	seed_l.size_flags_horizontal = SIZE_EXPAND_FILL
	seed_l.size_flags_vertical = SIZE_SHRINK_CENTER
	sr.add_child(seed_l)
	var rb := Button.new()
	rb.name = "Random"
	rb.text = "Random"
	rb.custom_minimum_size = Vector2(150, TOUCH)
	rb.add_theme_font_size_override("font_size", 20)
	rb.pressed.connect(set_seed.bind(0))
	sr.add_child(rb)
	var rr := Button.new()
	rr.name = "Reroll"
	rr.text = "Re-roll"
	rr.custom_minimum_size = Vector2(150, TOUCH)
	rr.add_theme_font_size_override("font_size", 20)
	rr.pressed.connect(reroll)
	sr.add_child(rr)
	start_b = Button.new()
	start_b.name = "Start"
	start_b.text = "Start"
	start_b.theme_type_variation = &"PrimaryButton"
	start_b.custom_minimum_size = Vector2(340, 70)
	start_b.size_flags_horizontal = SIZE_SHRINK_CENTER
	start_b.add_theme_font_size_override("font_size", 30)
	start_b.pressed.connect(start)
	v.add_child(start_b)
	JuicyButton.attach_all(pre)

func _label(text: String, size: int, variation: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if variation != "": l.theme_type_variation = StringName(variation)
	return l

func _pills(parent: Control, row_name: String, label: String, keys: Array, names: Array, store: Dictionary, on_pick: Callable, min_w: float) -> void:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	parent.add_child(row)
	var l := _label(label, 18, "MutedLabel")
	l.custom_minimum_size = Vector2(124, 0)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(l)
	var g := ButtonGroup.new()
	for i in keys.size():
		var b := Button.new()
		b.name = "P" + str(keys[i])
		b.text = str(names[i])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(min_w, TOUCH)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(on_pick.bind(keys[i]))
		row.add_child(b)
		store[keys[i]] = b

func open_pre() -> void:
	if not DlcUnlock.owned(): return
	show_pre(true)

## The pre-match card instead of the two big cards (and the page title says Classic).
func show_pre(on: bool) -> void:
	pre.visible = on
	main_view.visible = not on and arc_step == 0
	title_l.text = tr("Classic") if on else tr("Construction")
	if on:
		_select()
		if Tier.is_pc(): start_b.grab_focus.call_deferred()
	elif Tier.is_pc() and is_visible_in_tree():
		(classic_b if DlcUnlock.owned() else buy_b).grab_focus.call_deferred()

func set_bots(n: int) -> void:
	bots = clampi(n, BOT_MIN, BOT_MAX)
	_select()

func set_diff(d: String) -> void:
	diff = d
	Settings.set_value("difficulty", d)
	_select()

func set_seed(n: int) -> void:
	site_seed = clampi(n, 0, SEED_MAX)
	_select()

## A new fixed site: the same seed builds the same site, so a good one can be played again.
func reroll() -> void:
	set_seed(randi_range(1, SEED_MAX))

func _select() -> void:
	for n: int in _bot_bs: (_bot_bs[n] as Button).set_pressed_no_signal(n == bots)
	for d: String in _diff_bs: (_diff_bs[d] as Button).set_pressed_no_signal(d == diff)
	seed_l.text = tr("Random") if site_seed == 0 else tr("Seed %d") % site_seed
	seed_l.tooltip_text = tr("Random: a new site every match. Re-roll fixes a seed, so the same site comes back.")

## The arena id Start uses: the procedural site when it exists, else Site Yard.
static func site_map() -> String:
	return "sitegen" if Content.maps.has("sitegen") else "siteyard"

## Start: the Settings keys the match reads, then the offline match (scripts/main.gd: play_offline).
func start() -> void:
	if not DlcUnlock.owned(): return
	var mp := site_map()
	Settings.set_value("mode", "construction")
	Settings.set_value("bots", bots)
	Settings.set_value("difficulty", diff)
	Settings.set_value("offline_map", mp)
	Settings.set_value("site_seed", site_seed)
	start_requested.emit({"mode": "construction", "map": mp, "bots": bots, "difficulty": diff})
