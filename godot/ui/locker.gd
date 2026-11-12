class_name LockerScreen
extends VBoxContainer
## The Locker and the Shop (title screen: Locker / Shop), one screen in two modes, built in code in the UiTheme look
## like ui/setup_wizard.gd. Matches the web game's build 75 store pages: your wobbler big on the left (a live 3D
## render, ui/locker_stage.gd, turning; it wears whatever card you tap: try before you buy), a card grid on the right
## (DragScroll: drag + fling, a tap picks), the coins top right, Back and one action button at the bottom.
##   Locker tabs: Outfits, Hats, Colours, Emotes, Class. Owned items first; locked outfits / emotes show a padlock and
##            their price and can be bought from here too. Colours, hats and classes are free (web).
##   Shop tabs:   Outfits, Emotes (only what is for sale, cheapest first).
## The action button says what a tap would do: Wear / Equip / Pick, Wearing, Buy (opens a confirm card), or
## "Need N more coins" (says how to earn them). Everything goes through the Save autoload (autoload/save.gd), which
## also mirrors the look into Settings, so the setup wizard and the match use it.

signal closed

const LOCKER_TABS := ["skin", "hat", "color", "emote", "class"]
const SHOP_TABS := ["skin", "emote"]
const TAB_NAMES := {"skin": "Outfits", "hat": "Hats", "color": "Colours", "emote": "Emotes", "class": "Class"}
const CARD := Vector2(150, 156)
const GAP := 12
const PREVIEW_W := 250.0
const MSG_TIME := 3.5

var shop := false
var tab := "skin"
var sel := {}                   ## tab -> the key of the picked card
var stage: LockerStage
var title_l: Label
var sub_l: Label
var coins_l: Label
var name_l: Label
var info_l: Label
var msg_l: Label
var action_b: Button
var back_b: Button
var switch_b: Button
var preview_tr: TextureRect
var tab_row: HBoxContainer
var tab_bs := {}
var scroll: DragScroll
var grid: GridContainer
var fade: Control
var cards := {}                 ## key -> card Button (current tab)
var arts := {}                  ## bake key -> TextureRect
var confirm: Control
var confirm_title: Label
var confirm_sub: Label
var confirm_buy: Button
var pending := []               ## [kind, key] waiting for the confirm card
var _msg_t := 0.0
var _heavy: Font

func _init() -> void:
	name = "Locker"
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL

# ============================== data per tab ==============================

func tabs() -> Array:
	return SHOP_TABS if shop else LOCKER_TABS

static func save() -> SaveProfile:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Save")

## The cards of a tab, in order.
func items(t: String) -> Array:
	var sv := save()
	var out: Array = []
	match t:
		"skin":
			if shop: return LockerData.shop_skins()
			var mine: Array = sv.skins.duplicate()
			mine.erase("none")
			mine.sort_custom(func(a: String, b: String) -> bool: return LockerData.rarity_rank(LockerData.skin_rarity(a)) < LockerData.rarity_rank(LockerData.skin_rarity(b)))
			out = ["none"] + mine
			for k: String in LockerData.shop_skins():
				if not out.has(k): out.append(k)
		"hat":
			out = LockerData.hats()
		"color":
			for c: int in LockerData.swatch(): out.append(str(c))
		"emote":
			if shop: return LockerData.shop_emotes()
			var mine: Array = sv.owned.duplicate()
			mine.sort_custom(func(a: String, b: String) -> bool: return LockerData.rarity_rank(LockerData.emote_rarity(a)) < LockerData.rarity_rank(LockerData.emote_rarity(b)))
			out = mine
			for k: String in LockerData.shop_emotes():
				if not out.has(k): out.append(k)
			for k: String in LockerData.all_emotes():             # outfit emotes: shown, locked, "comes with ..."
				if not out.has(k) and LockerData.emote(k).has("skin"): out.append(k)
		"class":
			out = WobblerLooks.data("classes").keys()
	return out

static func is_owned(t: String, k: String) -> bool:
	if t == "skin": return save().owns_skin(k)
	if t == "emote": return save().owns_emote(k)
	return true

static func is_worn(t: String, k: String) -> bool:
	var lk: Dictionary = save().look
	match t:
		"skin": return lk["skin"] == k
		"hat": return lk["hat"] == k
		"color": return str(lk["color"]) == k
		"class": return lk["cls"] == k
		"emote": return save().slots[0] == k
	return false

static func item_name(t: String, k: String) -> String:
	match t:
		"skin": return LockerData.skin_name(k)
		"hat": return LockerData.hat_name(k)
		"color": return LockerData.color_name(int(k))
		"emote": return LockerData.emote_name(k)
		"class": return str(WobblerLooks.data("classes").get(k, {}).get("name", k))
	return k

static func rarity(t: String, k: String) -> String:
	if t == "skin": return LockerData.skin_rarity(k)
	if t == "emote": return LockerData.emote_rarity(k)
	return "common"

## The worn look with this card tried on.
static func try_look(t: String, k: String) -> Dictionary:
	var lk: Dictionary = save().look.duplicate()
	match t:
		"skin": lk["skin"] = k
		"hat": lk["hat"] = k
		"color": lk["color"] = int(k)
		"class": lk["cls"] = k
	return lk

## The render key + look for a card's art (null art for colours and emotes).
static func bake_entry(t: String, k: String) -> Array:
	var lk: Dictionary = save().look.duplicate()
	match t:
		"skin": lk["skin"] = k; return ["skin:" + k, lk]
		"hat": lk["skin"] = "none"; lk["hat"] = k; lk["frame"] = "head"; return ["hat:" + k, lk]
		"class": lk["cls"] = k; return ["cls:" + k, lk]
	return []

# ============================== open / close ==============================

## Opens the Locker (shop = false) or the Shop on tab `t` ("" = the first), the worn item picked.
func open(p_shop: bool, t: String = "") -> void:
	shop = p_shop
	if not is_node_ready(): return
	tab = t if tabs().has(t) else tabs()[0]
	sel.clear()
	_build_tabs()
	_show_tab(tab)
	stage.preview(save().look)
	_set_msg("")
	stage.active = is_visible_in_tree()
	if Tier.is_pc(): back_b.grab_focus.call_deferred()

func close() -> void:
	show_confirm(false)
	closed.emit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and stage:
		stage.active = is_visible_in_tree()

func _unhandled_input(e: InputEvent) -> void:
	if is_visible_in_tree() and e.is_action_pressed("ui_cancel"):
		if confirm.visible: show_confirm(false)
		else: close()
		get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= dt
		if _msg_t <= 0.0: _set_msg("")

# ============================== build ==============================

func _ready() -> void:
	_heavy = UiTheme.font(700)
	stage = LockerStage.new()
	add_child(stage)
	stage.baked_one.connect(_on_baked)
	_build_head()
	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	add_child(body)
	_build_preview(body)
	var right := VBoxContainer.new()
	right.name = "Right"
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	tab_row = HBoxContainer.new()
	tab_row.name = "Tabs"
	tab_row.add_theme_constant_override("separation", 6)
	right.add_child(tab_row)
	_build_grid(right)
	_build_foot()
	_build_confirm()
	save().changed.connect(_refresh_coins)
	JuicyButton.attach_all(self)
	open(shop, tab)

func _label(text: String, size: int, variation := "", clip := false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "": l.theme_type_variation = variation
	l.add_theme_font_size_override("font_size", size)
	if clip:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_head() -> void:
	var head := HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	title_l = _label("Locker", 36, "TitleLabel")
	title_l.name = "Title"
	head.add_child(title_l)
	sub_l = _label("", 18, "MutedLabel", true)
	sub_l.name = "Sub"
	sub_l.size_flags_horizontal = SIZE_EXPAND_FILL
	sub_l.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(sub_l)
	var chip := PanelContainer.new()
	chip.name = "Coins"
	chip.theme_type_variation = &"ChipPanel"
	chip.size_flags_vertical = SIZE_SHRINK_CENTER
	chip.tooltip_text = "Your coins. Earn them from K.O.s and finished matches"
	head.add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)
	var ic := LockerIcon.new("coin", 22)
	row.add_child(ic)
	coins_l = _label("0", 20)
	coins_l.name = "N"
	coins_l.add_theme_font_override("font", _heavy)
	coins_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	row.add_child(coins_l)
	switch_b = Button.new()
	switch_b.name = "Switch"
	switch_b.custom_minimum_size = Vector2(120, 60)
	switch_b.add_theme_font_size_override("font_size", 20)
	switch_b.pressed.connect(func() -> void: open(not shop))
	head.add_child(switch_b)

func _build_preview(body: Control) -> void:
	var p := PanelContainer.new()
	p.name = "Preview"
	p.custom_minimum_size = Vector2(PREVIEW_W, 0)
	body.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	preview_tr = TextureRect.new()
	preview_tr.name = "Render"
	preview_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_tr.size_flags_vertical = SIZE_EXPAND_FILL
	preview_tr.custom_minimum_size = Vector2(0, 120)
	preview_tr.texture = stage.get_texture()
	preview_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(preview_tr)
	name_l = _label("", 22, "", true)
	name_l.name = "Name"
	name_l.add_theme_font_override("font", _heavy)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_l)
	info_l = _label("", 15, "MutedLabel", true)
	info_l.name = "Info"
	info_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info_l)

func _build_grid(parent: Control) -> void:
	var frame := Control.new()
	frame.name = "Frame"
	frame.size_flags_vertical = SIZE_EXPAND_FILL
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	scroll = DragScroll.new()
	scroll.name = "Scroll"
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(scroll)
	grid = GridContainer.new()
	grid.name = "Grid"
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", GAP)
	grid.add_theme_constant_override("v_separation", GAP)
	scroll.add_child(grid)
	fade = SetupWizard.EdgeFade.new(scroll)
	fade.name = "Fade"
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_child(fade)
	scroll.tapped.connect(func(c: Control) -> void:
		var j := c.get_node_or_null("Juicy")
		if j: j._release())
	scroll.resized.connect(_reflow)

func _reflow() -> void:
	var w := scroll.size.x - 16.0
	grid.columns = clampi(int((w + GAP) / (CARD.x + GAP)), 1, maxi(1, grid.get_child_count()))
	fade.queue_redraw()

func _build_foot() -> void:
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	foot.add_theme_constant_override("separation", 12)
	add_child(foot)
	back_b = Button.new()
	back_b.name = "Back"
	back_b.text = "Back"
	back_b.custom_minimum_size = Vector2(124, 60)
	back_b.pressed.connect(close)
	foot.add_child(back_b)
	msg_l = _label("", 18, "", true)
	msg_l.name = "Msg"
	msg_l.size_flags_horizontal = SIZE_EXPAND_FILL
	msg_l.size_flags_vertical = SIZE_SHRINK_CENTER
	msg_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_child(msg_l)
	action_b = Button.new()
	action_b.name = "Action"
	action_b.custom_minimum_size = Vector2(250, 60)
	action_b.add_theme_font_size_override("font_size", 24)
	action_b.clip_text = true
	action_b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_b.pressed.connect(act)
	foot.add_child(action_b)

func _build_tabs() -> void:
	for c in tab_row.get_children(): tab_row.remove_child(c); c.queue_free()
	tab_bs.clear()
	var g := ButtonGroup.new()
	for t: String in tabs():
		var b := Button.new()
		b.name = TAB_NAMES[t]
		b.text = TAB_NAMES[t]
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(0, 60)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_show_tab.bind(t))
		tab_row.add_child(b)
		tab_bs[t] = b
		JuicyButton.attach(b)
	title_l.text = "Shop" if shop else "Locker"
	switch_b.text = "Locker" if shop else "Shop"
	switch_b.tooltip_text = "Your outfits, hats, colours and emotes" if shop else "Buy outfits and emotes with coins"

func _build_confirm() -> void:
	confirm = Control.new()
	confirm.name = "Confirm"
	confirm.top_level = true
	confirm.visible = false
	add_child(confirm)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: show_confirm(false))
	confirm.add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirm.add_child(cc)
	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(460, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	confirm_title = _label("", 30, "TitleLabel")
	confirm_title.name = "Q"
	confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(confirm_title)
	confirm_sub = _label("", 19, "MutedLabel")
	confirm_sub.name = "Sub"
	confirm_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(confirm_sub)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var no := Button.new()
	no.name = "Cancel"
	no.text = "Cancel"
	no.custom_minimum_size = Vector2(0, 60)
	no.size_flags_horizontal = SIZE_EXPAND_FILL
	no.pressed.connect(show_confirm.bind(false))
	row.add_child(no)
	confirm_buy = Button.new()
	confirm_buy.name = "Buy"
	confirm_buy.text = "Buy"
	confirm_buy.theme_type_variation = &"PrimaryButton"
	confirm_buy.add_theme_font_size_override("font_size", 26)
	confirm_buy.custom_minimum_size = Vector2(0, 60)
	confirm_buy.size_flags_horizontal = SIZE_EXPAND_FILL
	confirm_buy.pressed.connect(buy_confirmed)
	row.add_child(confirm_buy)

func show_confirm(on: bool) -> void:
	if confirm == null: return
	confirm.visible = on
	if on:
		confirm.position = Vector2.ZERO
		confirm.size = get_viewport_rect().size
		if Tier.is_pc(): confirm_buy.grab_focus.call_deferred()
	else:
		pending = []

# ============================== tabs + cards ==============================

func _show_tab(t: String) -> void:
	tab = t
	for k: String in tab_bs: (tab_bs[k] as Button).set_pressed_no_signal(k == t)
	_rebuild()
	if not sel.has(t):
		var keys := items(t)
		var pick := ""
		for k: String in keys:
			if is_worn(t, k): pick = k; break
		sel[t] = pick if pick != "" else (keys[0] if keys.size() > 0 else "")
	_select_card(sel[t], false)
	_reveal.call_deferred()

func _rebuild() -> void:
	for c in grid.get_children(): grid.remove_child(c); c.queue_free()
	cards.clear()
	arts.clear()
	var keys := items(tab)
	var bake: Array = []
	var grp := ButtonGroup.new()
	grp.allow_unpress = false
	for k: String in keys:
		var b := _card(tab, k)
		b.button_group = grp
		grid.add_child(b)
		scroll.add_card(b)
		b.pressed.connect(_select_card.bind(k))
		cards[k] = b
		var be := bake_entry(tab, k)
		if be.size() == 2:
			stage.looks[be[0]] = be[1]
			bake.append(be[0])
	_reflow()
	if bake.size() > 0: stage.bake(bake)
	sub_l.text = _tab_hint()

func _tab_hint() -> String:
	if shop: return "Earn coins: K.O. +5, match +40, win +60."
	match tab:
		"skin": return "Tap an outfit to try it on."
		"hat": return "Hats are free to wear."
		"color": return "Shows when you wear no outfit."
		"emote": return "Tap to see it. Equip puts it on T."
		"class": return "Size and moves. All free."
	return ""

func _reveal() -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	var k: String = sel.get(tab, "")
	if cards.has(k): scroll.reveal(cards[k])

func _on_baked(id: String) -> void:
	if arts.has(id): (arts[id] as TextureRect).texture = stage.baked.get(id)

## A card: rarity edge, art (3D render, colour swatch or emote icon), name, and a line with the state or price.
func _card(t: String, k: String) -> Button:
	var b := Button.new()
	b.name = k
	b.toggle_mode = true
	b.custom_minimum_size = CARD
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	var own := is_owned(t, k)
	var rc := LockerData.rarity_color(rarity(t, k))
	var n := UiTheme.box(UiTheme.PANEL_HI if own else Color(0.08, 0.17, 0.2, 0.92), 16, Color(rc, 0.75), 2, 4, 5, rc.darkened(0.3))
	n.border_width_bottom = 5
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = h.bg_color.lightened(0.08)
	var s := UiTheme.box(Color(0.15, 0.33, 0.37, 0.96), 16, UiTheme.ACCENT, 3, 8, 6, UiTheme.ACCENT_DARK)
	s.border_width_bottom = 6
	var f := UiTheme.box(Color.TRANSPARENT, 19, Color.WHITE, 3, 0)
	f.draw_center = false
	f.expand_margin_left = 3; f.expand_margin_right = 3; f.expand_margin_top = 3; f.expand_margin_bottom = 3
	for kv in [["normal", n], ["hover", h], ["pressed", s], ["hover_pressed", s], ["disabled", n], ["focus", f]]:
		b.add_theme_stylebox_override(kv[0], kv[1])
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]: m.add_theme_constant_override("margin_" + side, 10)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 10)
	b.add_child(m)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	m.add_child(v)
	var art := _art(t, k)
	art.name = "Art"
	art.size_flags_vertical = SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var nl := _label(item_name(t, k), 18, "", true)
	nl.name = "Name"
	nl.add_theme_font_override("font", _heavy)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var row := HBoxContainer.new()
	row.name = "State"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)
	var st := _label("", 15, "MutedLabel")
	st.name = "L"
	if is_worn(t, k):
		row.add_child(LockerIcon.new("check", 16))
		st.text = "Equipped" if t == "emote" else "Wearing" if t != "class" else "Picked"
		st.add_theme_color_override("font_color", UiTheme.GOOD)
	elif own:
		st.text = LockerData.rarity_label(rarity(t, k)) if t == "skin" or t == "emote" else "Free"
		st.add_theme_color_override("font_color", rc.lightened(0.25))
	elif t == "emote" and not LockerData.is_shop_emote(k):
		row.add_child(LockerIcon.new("lock", 16))
		st.text = "With an outfit"
	else:
		row.add_child(LockerIcon.new("coin", 16))
		st.text = str(save().price_of(t, k))
		st.add_theme_color_override("font_color", UiTheme.ACCENT if save().coins >= save().price_of(t, k) else UiTheme.MUTED)
	row.add_child(st)
	if not own:                                   # padlock badge in the corner
		var lock := LockerIcon.new("lock", 22)
		lock.name = "Lock"
		b.add_child(lock)
		lock.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lock.offset_left = -32; lock.offset_right = -10; lock.offset_top = 10; lock.offset_bottom = 32
	return b

func _art(t: String, k: String) -> Control:
	match t:
		"color":
			var sw := LockerIcon.new("swatch", 70)
			sw.color = Color.hex((int(k) << 8) | 0xff)
			return sw
		"emote":
			var l := _label(str(LockerData.emote(k).get("ico", "?")), 46)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			return l
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(0, 80)
	var be := bake_entry(t, k)
	if be.size() == 2:
		tr.texture = stage.baked.get(be[0])
		arts[be[0]] = tr
	return tr

# ============================== picking + the action ==============================

## Picks a card: it shows on the wobbler (an emote plays), the action button follows.
func _select_card(k: String, play := true) -> void:
	sel[tab] = k
	for ck: String in cards: (cards[ck] as Button).set_pressed_no_signal(ck == k)
	var lk := try_look(tab, k)
	stage.preview(lk)
	if tab == "emote" and play and k != "": stage.emote(k)
	_refresh()

func picked() -> String:
	return sel.get(tab, "")

func kind() -> String:
	return tab if tab == "skin" or tab == "emote" else ""

## What the action button does for the picked card: "wear" | "worn" | "buy" | "coins" | "locked".
func action_state() -> String:
	var k := picked()
	if k == "": return "locked"
	if is_owned(tab, k): return "worn" if is_worn(tab, k) else "wear"
	match save().buy_check(tab, k):
		"ok": return "buy"
		"coins": return "coins"
	return "locked"

func _refresh() -> void:
	_refresh_coins()
	var k := picked()
	var st := action_state()
	var verb: String = {"skin": "Wear", "hat": "Wear", "color": "Use colour", "emote": "Equip", "class": "Pick"}[tab]
	var done: String = {"skin": "Wearing", "hat": "Wearing", "color": "Using it", "emote": "Equipped", "class": "Picked"}[tab]
	action_b.disabled = st == "worn" or st == "locked"
	action_b.theme_type_variation = &"PrimaryButton" if st == "wear" or st == "buy" else &""
	action_b.add_theme_font_size_override("font_size", 24)
	match st:
		"wear": action_b.text = verb
		"worn": action_b.text = done
		"buy": action_b.text = "Buy for %d" % save().price_of(tab, k)
		"coins": action_b.text = "Need %d more" % save().missing(tab, k)
		"locked": action_b.text = "Not for sale"
	name_l.text = item_name(tab, k) if k != "" else ""
	info_l.text = _info(tab, k)
	info_l.tooltip_text = info_l.text

func _info(t: String, k: String) -> String:
	if k == "": return ""
	var parts: Array = []
	if t == "skin" or t == "emote": parts.append(LockerData.rarity_label(rarity(t, k)))
	if t == "emote":
		var e := LockerData.emote(k)
		if e.has("skin"): parts.append("Comes with " + LockerData.skin_name(str(e["skin"])))
		else: parts.append(str(e.get("blurb", "")))
	elif t == "skin":
		var ems := LockerData.skin_emotes(k)
		if ems.size() > 0: parts.append("Comes with " + LockerData.emote_name(ems[0]))
		elif not is_owned(t, k): parts.append("%d coins" % LockerData.skin_price(k))
	elif t == "class":
		parts.append(str(WobblerLooks.data("classes").get(k, {}).get("tag", "")))
	return " · ".join(parts)

func _refresh_coins() -> void:
	if coins_l: coins_l.text = str(save().coins)

## The action button.
func act() -> void:
	var k := picked()
	match action_state():
		"wear": wear(k)
		"buy":
			pending = [tab, k]
			confirm_title.text = "Buy %s?" % item_name(tab, k)
			confirm_sub.text = "%d coins. You have %d." % [save().price_of(tab, k), save().coins]
			confirm_buy.text = "Buy for %d" % save().price_of(tab, k)
			show_confirm(true)
		"coins":
			_set_msg("You need %d more coins. Score K.O.s and finish matches to earn them." % save().missing(tab, k), UiTheme.WARN)
			_shake(action_b)

func wear(k: String) -> bool:
	var sv := save()
	var ok := false
	match tab:
		"skin": ok = sv.wear_skin(k); stage.forget("cls:")
		"hat": ok = sv.set_hat(k); stage.forget("skin:"); stage.forget("cls:")
		"color": ok = sv.set_color(int(k)); stage.forget("hat:"); stage.forget("cls:"); stage.forget("skin:")
		"class": ok = sv.set_class(k); stage.forget("skin:"); stage.forget("hat:")
		"emote": ok = sv.equip_emote(k, 0)
	if ok:
		_set_msg(("%s is on T and first in the emote button." if tab == "emote" else "Now wearing %s." if tab != "class" else "You play as %s.") % item_name(tab, k), UiTheme.GOOD)
		Sfx.play("click")
		_redraw_keep()
	return ok

## The confirm card's Buy.
func buy_confirmed() -> String:
	if pending.size() != 2:
		show_confirm(false)
		return ""
	var t: String = pending[0]
	var k: String = pending[1]
	var r := save().buy(t, k)
	show_confirm(false)
	match r:
		"ok":
			var extra := ""
			if t == "skin":
				extra = " You're wearing it."
				var ems := LockerData.skin_emotes(k)
				if ems.size() > 0: extra += " You also got " + LockerData.emote_name(ems[0]) + "."
				stage.forget("cls:")
			_set_msg("Bought %s!%s" % [item_name(t, k), extra], UiTheme.GOOD)
			Sfx.play("pickup")
		"coins": _set_msg("You need %d more coins." % save().missing(t, k), UiTheme.WARN)
		_: _set_msg("You can't buy that.", UiTheme.WARN)
	_redraw_keep()
	return r

## Rebuild the cards (owned / worn changed), keeping the pick and the scroll position.
func _redraw_keep() -> void:
	var sv := scroll.scroll_vertical
	var k := picked()
	_rebuild()
	_select_card(k, false)
	scroll.scroll_vertical = sv

func _set_msg(t: String, c: Color = UiTheme.TEXT) -> void:
	if msg_l == null: return
	msg_l.text = t
	msg_l.tooltip_text = t
	msg_l.add_theme_color_override("font_color", c)
	_msg_t = MSG_TIME if t != "" else 0.0

## A short warm flash on the button (not a position shake: the button lives in a container).
func _shake(c: Control) -> void:
	var tw := c.create_tween()
	tw.tween_property(c, "self_modulate", Color(1.0, 0.55, 0.45), 0.08)
	tw.tween_property(c, "self_modulate", Color.WHITE, 0.3)

# ============================== icons (vector, no image files) ==============================

## coin (gold disc), lock (padlock), check (tick), swatch (a colour disc with a rim).
class LockerIcon extends Control:
	var kind := "coin"
	var color := Color.WHITE

	func _init(k: String, s: float) -> void:
		kind = k
		custom_minimum_size = Vector2(s, s)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER if k != "swatch" else Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size / 2.0
		match kind:
			"coin":
				draw_circle(c, s * 0.5, Color("#c79a2c"))
				draw_circle(c, s * 0.4, UiTheme.ACCENT)
				draw_rect(Rect2(c - Vector2(s * 0.07, s * 0.2), Vector2(s * 0.14, s * 0.4)), Color("#c79a2c"))
			"lock":
				var w := s * 0.7
				var body := Rect2(c.x - w / 2.0, c.y - s * 0.05, w, s * 0.5)
				draw_arc(Vector2(c.x, body.position.y), w * 0.32, PI, TAU, 12, Color(1, 1, 1, 0.9), s * 0.12, true)
				draw_rect(body, Color(1, 1, 1, 0.92))
				draw_circle(Vector2(c.x, body.position.y + body.size.y * 0.45), s * 0.07, UiTheme.INK)
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.35, 0), c + Vector2(-s * 0.08, s * 0.28), c + Vector2(s * 0.38, -s * 0.3)]), UiTheme.GOOD, s * 0.16, true)
			"swatch":
				var r := minf(s * 0.5, 40.0)
				draw_circle(c, r + 3.0, Color(1, 1, 1, 0.85))
				draw_circle(c, r, color)
