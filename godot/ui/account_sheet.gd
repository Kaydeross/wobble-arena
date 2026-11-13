class_name AccountSheet
extends Control
## The Account sheet (opened from the title's "Guest" / "Signed in as NAME" chip): a dimmed backdrop and one card that
## shows one page at a time, all driven by AccountApi (Save.cloud):
##   guest     "Pick a name": one field + Play (claims the name, no password); "I have a password" opens log in
##   login     username or email, password, "Forgot password?"
##   reset     username or email, recovery code, new password
##   code      the recovery code, shown once, with Copy
##   signed    who you are, the sync line ("Saved to cloud 2 min ago"), Protect my name with a password (name-only
##             accounts) or Change password, Log out, Delete account
##   protect   a new password for a name-only account (a recovery code follows)
##   password  current + new password
##   delete    password + type DELETE to confirm (App Store 5.1.1(v): in-app account deletion)
##   conflict  this device and the cloud differ: Keep this device / Use cloud
## Big touch targets (ROW_H rows), plain words, the shared theme.

signal closed

const PAGES := ["guest", "login", "reset", "code", "signed", "protect", "password", "delete", "conflict"]
const ROW_H := 62.0                  ## canvas px: 45 pt on an iPhone in landscape (Apple asks 44)
const CONFIRM_WORD := "DELETE"

var api: AccountApi
var page := ""
var card: PanelContainer
var title_l: Label
var msg_l: Label
var pages := {}                     ## page name -> VBoxContainer
var ui := {}                        ## "page/Name" -> Control
var code := ""                      ## the recovery code on the code page
var _after_code := ""               ## page to show after "I saved it"
var _sync_t := 0.0
var _logout_armed := false          ## a name-only account was asked "log out anyway?"

func _init() -> void:
	name = "Account"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func _ready() -> void:
	_build()
	if api == null:
		var sv := get_tree().root.get_node_or_null("Save")
		if sv: api = sv.cloud
	if api:
		api.done.connect(_on_done)
		api.changed.connect(refresh)
		api.recovery.connect(_on_recovery)
		api.conflict.connect(func(_i: Dictionary) -> void: open("conflict"))
	JuicyButton.attach_all(self)

func _process(dt: float) -> void:
	if not visible: return
	_sync_t -= dt
	if _sync_t <= 0.0:                    # "2 min ago" keeps counting while the sheet is open
		_sync_t = 5.0
		refresh()

# ============================== building ==============================

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed and page in ["guest", "signed"]: close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(580, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.text = "Account"
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 30)
	box.add_child(title_l)
	var holder := VBoxContainer.new()
	holder.name = "Pages"
	box.add_child(holder)
	msg_l = Label.new()
	msg_l.name = "Msg"
	msg_l.theme_type_variation = &"MutedLabel"
	msg_l.add_theme_font_size_override("font_size", 17)
	msg_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_l.custom_minimum_size = Vector2(0, 22)
	box.add_child(msg_l)

	var p := _page(holder, "guest")
	_text(p, "Info", "Pick a name to play online and keep your coins, outfits and stats in the cloud. No password needed.")
	_field(p, "guest", "Name", "Your name (3 to 16 letters or numbers)", false)
	_row(p, "Row", [_btn("guest", "Close", "Close", false, close), _btn("guest", "Go", "Play", true, _do_claim)])
	var have := _btn("guest", "Login", "I have a password", false, open.bind("login"))
	have.flat = true
	have.add_theme_color_override("font_color", UiTheme.MUTED)
	p.add_child(have)
	var keep := _text(p, "Note", "Names nobody uses for 30 days are freed.")
	keep.add_theme_color_override("font_color", UiTheme.MUTED)
	keep.add_theme_font_size_override("font_size", 16)

	p = _page(holder, "login")
	_field(p, "login", "User", "Username or email", false)
	_field(p, "login", "Pass", "Password", true)
	_row(p, "Row", [_btn("login", "Back", "Back", false, open.bind("guest")), _btn("login", "Go", "Log in", true, _do_login)])
	var forgot := _btn("login", "Forgot", "Forgot your password?", false, open.bind("reset"))
	forgot.flat = true
	forgot.add_theme_color_override("font_color", UiTheme.MUTED)
	p.add_child(forgot)

	p = _page(holder, "reset")
	_field(p, "reset", "User", "Username or email", false)
	_field(p, "reset", "Code", "Recovery code (XXXX-XXXX-XXXX-XXXX)", false)
	_field(p, "reset", "Pass", "New password (6 or more characters)", true)
	_row(p, "Row", [_btn("reset", "Back", "Back", false, open.bind("login")), _btn("reset", "Go", "Set new password", true, _do_reset)])

	p = _page(holder, "code")
	_text(p, "Info", "Your recovery code. Write it down or copy it somewhere safe: if you forget your password, it's the only way back in. It's shown only once.")
	var cl := Label.new()
	cl.name = "Code"
	cl.add_theme_font_size_override("font_size", 34)
	cl.add_theme_font_override("font", UiTheme.font(700))
	cl.add_theme_color_override("font_color", UiTheme.ACCENT)
	cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(cl)
	ui["code/Code"] = cl
	_row(p, "Row", [_btn("code", "Copy", "Copy", false, _copy_code), _btn("code", "Go", "I saved it", true, _code_done)])

	p = _page(holder, "signed")
	var who := Label.new()
	who.name = "Who"
	who.add_theme_font_size_override("font_size", 24)
	who.add_theme_font_override("font", UiTheme.font(700))
	who.clip_text = true
	who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	p.add_child(who)
	ui["signed/Who"] = who
	_text(p, "Sync", "")
	var pb := _btn("signed", "Protect", "Protect my name with a password", true, open.bind("protect"))
	pb.tooltip_text = "No password yet: this name only works on this device."
	p.add_child(pb)
	_row(p, "Row", [_btn("signed", "Password", "Change password", false, open.bind("password")), _btn("signed", "Logout", "Log out", false, _do_logout)])
	var del := _btn("signed", "Delete", "Delete account", false, open.bind("delete"))
	del.add_theme_color_override("font_color", UiTheme.BAD)
	del.add_theme_color_override("font_hover_color", UiTheme.BAD)
	_row(p, "Row2", [del, _btn("signed", "Close", "Close", true, close)])

	p = _page(holder, "protect")
	_field(p, "protect", "Pass", "New password (6 or more characters)", true)
	_row(p, "Row", [_btn("protect", "Back", "Back", false, open.bind("signed")), _btn("protect", "Go", "Set password", true, _do_protect)])

	p = _page(holder, "password")
	_field(p, "password", "Old", "Current password", true)
	_field(p, "password", "New", "New password (6 or more characters)", true)
	_row(p, "Row", [_btn("password", "Back", "Back", false, open.bind("signed")), _btn("password", "Go", "Change password", true, _do_password)])

	p = _page(holder, "delete")
	_text(p, "Info", "")
	_field(p, "delete", "Pass", "Your password", true)
	_field(p, "delete", "Confirm", tr("Type %s to confirm") % CONFIRM_WORD, false)
	var dg := _btn("delete", "Go", "Delete account", false, _do_delete)
	dg.add_theme_color_override("font_color", UiTheme.BAD)
	dg.add_theme_color_override("font_hover_color", UiTheme.BAD)
	_row(p, "Row", [_btn("delete", "Back", "Back", false, open.bind("signed")), dg])
	for k in ["delete/Pass", "delete/Confirm"]:
		(ui[k] as LineEdit).text_changed.connect(func(_t: String) -> void: _delete_ready())

	p = _page(holder, "conflict")
	_text(p, "Info", "This account has different progress saved in the cloud. Which one do you want to keep? The other one is replaced.")
	_text(p, "Local", "")
	_text(p, "Cloud", "")
	_row(p, "Row", [_btn("conflict", "Keep", "Keep this device", false, _keep), _btn("conflict", "Use", "Use cloud", false, _use)])

func _page(holder: Control, n: String) -> VBoxContainer:
	var p := VBoxContainer.new()
	p.name = n.capitalize()
	p.add_theme_constant_override("separation", 10)
	p.visible = false
	holder.add_child(p)
	pages[n] = p
	return p

func _text(p: Control, n: String, t: String) -> Label:
	var l := Label.new()
	l.name = n
	l.text = t
	l.add_theme_font_size_override("font_size", 18)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(0, 22)
	p.add_child(l)
	ui[_key(p, n)] = l
	return l

func _key(p: Control, n: String) -> String:
	for k: String in pages:
		if pages[k] == p: return k + "/" + n
	return n

func _field(p: Control, pg: String, n: String, hint: String, secret: bool) -> LineEdit:
	var f := LineEdit.new()
	f.name = n
	f.placeholder_text = hint
	f.secret = secret
	f.custom_minimum_size = Vector2(0, ROW_H)
	f.add_theme_font_size_override("font_size", 20)
	f.max_length = 100
	f.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_PASSWORD if secret else (LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS if n == "Email" else LineEdit.KEYBOARD_TYPE_DEFAULT)
	f.text_submitted.connect(func(_t: String) -> void: _submit(pg))
	p.add_child(f)
	ui[pg + "/" + n] = f
	return f

func _btn(pg: String, n: String, t: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = t
	if primary: b.theme_type_variation = &"PrimaryButton"
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 21)
	b.pressed.connect(cb)
	ui[pg + "/" + n] = b
	return b

func _row(p: Control, n: String, items: Array) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = n
	r.add_theme_constant_override("separation", 10)
	for c: Control in items: r.add_child(c)
	p.add_child(r)
	return r

# ============================== pages ==============================

## Show the sheet on `pg` ("" = guest or signed, or the waiting conflict).
func open(pg := "") -> void:
	if pg == "":
		pg = "conflict" if api and not api.pending.is_empty() else ("signed" if api and api.signed_in() else "guest")
	if page != pg: msg_l.text = ""
	_logout_armed = false
	page = pg
	visible = true
	for k: String in pages: pages[k].visible = k == pg
	title_l.text = {"guest": "Pick a name", "login": "Log in", "protect": "Protect my name", "reset": "Forgot password",
		"code": "Recovery code", "signed": "Account", "password": "Change password", "delete": "Delete account",
		"conflict": "Which progress?"}[pg]
	if pg == "delete":
		(ui["delete/Pass"] as LineEdit).text = ""
		(ui["delete/Confirm"] as LineEdit).text = ""
	_busy(false)
	refresh()
	if Tier.is_pc():
		var first := _first_field(pages[pg])
		if first: first.grab_focus.call_deferred()

func close() -> void:
	visible = false
	page = ""
	closed.emit()

## One step back (Escape, controller B, Android back): a form returns to the page it came from, the two home pages
## close the sheet. The recovery code and the conflict question wait for an answer (true = handled anyway).
func back() -> bool:
	match page:
		"guest", "signed": close()
		"login": open("guest")
		"reset": open("login")
		"protect", "password", "delete": open("signed")
	return true

func _unhandled_input(e: InputEvent) -> void:
	if visible and e.is_action_pressed("ui_cancel") and not e.is_echo():
		back()
		get_viewport().set_input_as_handled()

func _first_field(n: Node) -> Control:
	for c in n.get_children():
		if c is LineEdit: return c
	return null

## Texts that follow the account state (who, sync line, conflict summaries, delete warning).
func refresh() -> void:
	if api == null or pages.is_empty(): return
	(ui["signed/Who"] as Label).text = tr("Signed in as %s") % api.user()
	(ui["signed/Protect"] as Control).visible = not api.has_password
	(ui["signed/Password"] as Control).visible = api.has_password
	var sync := api.sync_text()
	var em := api.email()
	(ui["signed/Sync"] as Label).text = (em + "\n" if em != "" else "") + (sync if sync != "" else tr("Saved on this device"))
	(ui["delete/Info"] as Label).text = tr("This deletes the account %s and its cloud save for good. It can't be undone. This device starts again as a new guest.") % api.user()
	var ci := api.conflict_info()
	if not ci.is_empty():
		(ui["conflict/Local"] as Label).text = tr("This device: %s") % str(ci["local"])
		(ui["conflict/Cloud"] as Label).text = tr("Cloud: %s") % str(ci["cloud"])
	if page == "signed" and not api.signed_in(): open("guest")
	elif page == "guest" and api.signed_in(): open("signed")
	_delete_ready()

func _delete_ready() -> void:
	if not ui.has("delete/Go"): return
	(ui["delete/Go"] as Button).disabled = (ui["delete/Confirm"] as LineEdit).text.strip_edges().to_upper() != CONFIRM_WORD \
		or (ui["delete/Pass"] as LineEdit).text == ""

func _busy(on: bool) -> void:
	for k: String in ui:
		if k.ends_with("/Go") and ui[k] is Button: (ui[k] as Button).disabled = on
	if not on: _delete_ready()
	if on: msg_l.text = "One moment…"

func _submit(pg: String) -> void:
	match pg:
		"guest": _do_claim()
		"protect": _do_protect()
		"login": _do_login()
		"reset": _do_reset()
		"password": _do_password()

func _txt(k: String) -> String:
	return (ui[k] as LineEdit).text

func _do_claim() -> void:
	_busy(true); api.claim(_txt("guest/Name"))

func _do_protect() -> void:
	_busy(true); api.protect(_txt("protect/Pass"))

func _do_login() -> void:
	_busy(true); api.login(_txt("login/User"), _txt("login/Pass"))

func _do_reset() -> void:
	_busy(true); api.reset(_txt("reset/User"), _txt("reset/Code"), _txt("reset/Pass"))

func _do_password() -> void:
	_busy(true); api.change_password(_txt("password/Old"), _txt("password/New"))

func _do_logout() -> void:
	if not api.has_password and not _logout_armed:         # a name with no password can't be logged back in: ask once more
		_logout_armed = true
		msg_l.text = "No password yet. If you log out, this name is lost to you. Tap Log out again to leave it, or protect it first."
		return
	_busy(true); api.logout()

func _do_delete() -> void:
	if _txt("delete/Confirm").strip_edges().to_upper() != CONFIRM_WORD: return
	_busy(true); api.delete_account(_txt("delete/Pass"))

func _keep() -> void:
	api.keep_device(); open("signed")

func _use() -> void:
	api.use_cloud(); open("signed")

func _copy_code() -> void:
	DisplayServer.clipboard_set(code)
	msg_l.text = "Copied."

func _code_done() -> void:
	code = ""
	(ui["code/Code"] as Label).text = ""
	open(_after_code if _after_code != "" else "")

func _on_recovery(c: String) -> void:
	code = c
	(ui["code/Code"] as Label).text = c

func _on_done(op: String, ok: bool, m: String) -> void:
	_busy(false)
	for k in ["protect/Pass", "login/Pass", "reset/Pass", "password/Old", "password/New", "delete/Pass"]:
		if ok: (ui[k] as LineEdit).text = ""
	if not visible: return                # (the online panel's login: its status line says it; a conflict opens the sheet)
	if ok:
		match op:
			"claim", "login", "reset":
				_after_code = "conflict" if not api.pending.is_empty() else "signed"
				if code != "": open("code")
				else: open(_after_code)
			"recovery": open("code")
			"protect":
				_after_code = "signed"
				open("code" if code != "" else "signed")
			"password": open("signed")
			"logout", "delete": open("guest")
	msg_l.text = m
