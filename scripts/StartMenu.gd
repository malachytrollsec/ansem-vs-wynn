extends Control
## Title screen: pick your meme king, then start the war.

var selected_king := "fartcoin"
var pressure := "standard"
var arena_idx := 0
var f_display: FontFile
var f_ui: FontFile
var cards := {}
var pressure_btns := {}
var arena_lbl: Label
var wager_lbl: Label
var wallet_btn: Button
var wallet_status_lbl: Label
var mp_btn: Button
var leaderboard_panel: PanelContainer
var leaderboard_list: VBoxContainer
var leaderboard_status_lbl: Label
var center_holder: CenterContainer
var menu_box: VBoxContainer
var title_logo: TextureRect
var lobby: Control
var net_status_lbl: Label
var net_roster_lbl: Label
var room_edit: LineEdit
var url_edit: LineEdit
var room_share_lbl: Label
var wager_status_lbl: Label
var wager_accept_btn: Button
var wager_decline_btn: Button
var peer_wager_offer := {}
var wager_ticket_accepted := false
var _last_offer_key := ""
var _leaderboard_sync_id := 0

const UI_RD_PANEL := "res://assets/ui/ui_rd_panel_medium.png"
const UI_RD_PANEL_LARGE := "res://assets/ui/ui_rd_panel_large.png"
const UI_RD_BUTTON := "res://assets/ui/ui_rd_status_bar.png"
const UI_RD_BUTTON_HOVER := "res://assets/ui/ui_rd_status_bar_blue.png"
const MAIN_MENU_LOGO := "res://assets/ui/main_menu_logo.png"

func _flat_menu_panel() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Game.COL_PANEL
	sb.border_color = Game.COL_EDGE
	sb.set_border_width_all(2)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _texture_style(path: String, margin := 20.0, content := 8.0, tint := Color.WHITE) -> StyleBox:
	var tex: Texture2D = load(path)
	if tex == null:
		return _flat_menu_panel()
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = minf(margin, 18.0)
	sb.texture_margin_bottom = minf(margin, 18.0)
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = maxf(4.0, content - 2.0)
	sb.content_margin_bottom = maxf(4.0, content - 2.0)
	sb.modulate_color = tint
	return sb

func _button_style(active := false, pressed := false) -> StyleBox:
	var tint := Color(1.08, 1.08, 1.08, 1.0) if active else Color(0.92, 0.96, 1.0, 1.0)
	if pressed:
		tint = Color(0.7, 0.75, 0.86, 1.0)
	return _texture_style(UI_RD_BUTTON_HOVER if active else UI_RD_BUTTON, 18.0, 11.0, tint)

func _ready() -> void:
	f_display = load("res://assets/fonts/press-start-2p.ttf")
	f_ui = load("res://assets/fonts/silkscreen.ttf")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Game.publish_web_state({"scene": "menu", "netMode": Game.net_mode, "myTeam": Game.my_team, "selectedKing": selected_king})

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Game.COL_INK
	add_child(bg)
	var band := ColorRect.new()
	band.set_anchors_preset(Control.PRESET_FULL_RECT)
	band.color = Color(Game.COL_ACCENT, 0.05)
	add_child(band)

	# wallet connect (top-right)
	wallet_btn = _small_button("CONNECT PHANTOM")
	wallet_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet_btn.offset_left = -224
	wallet_btn.offset_right = -16
	wallet_btn.offset_top = 16
	wallet_btn.offset_bottom = 48
	wallet_btn.custom_minimum_size = Vector2(208, 32)
	add_child(wallet_btn)
	wallet_btn.pressed.connect(func(): Wallet.connect_wallet())
	Wallet.changed.connect(_refresh_wallet)

	# multiplayer (below wallet)
	mp_btn = _small_button("MULTIPLAYER")
	mp_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mp_btn.offset_left = -224
	mp_btn.offset_right = -16
	mp_btn.offset_top = 56
	mp_btn.offset_bottom = 88
	mp_btn.custom_minimum_size = Vector2(208, 32)
	add_child(mp_btn)
	mp_btn.pressed.connect(_toggle_lobby)

	wallet_status_lbl = _label("", f_ui, 8, Game.COL_MUTED)
	wallet_status_lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	wallet_status_lbl.offset_left = -252
	wallet_status_lbl.offset_right = -12
	wallet_status_lbl.offset_top = 94
	wallet_status_lbl.offset_bottom = 132
	wallet_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wallet_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	wallet_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(wallet_status_lbl)
	_refresh_wallet()

	# persistent leaderboard (top-left, local fallback while the web board loads)
	leaderboard_panel = PanelContainer.new()
	leaderboard_panel.add_theme_stylebox_override("panel", _menu_panel())
	leaderboard_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	leaderboard_panel.offset_left = 16
	leaderboard_panel.offset_right = 318
	leaderboard_panel.offset_top = 16
	leaderboard_panel.custom_minimum_size = Vector2(302, 0)
	add_child(leaderboard_panel)
	var lbvb := VBoxContainer.new()
	lbvb.add_theme_constant_override("separation", 4)
	leaderboard_panel.add_child(lbvb)
	var lbh := _label("LEADERBOARD", f_ui, 11, Game.COL_ACCENT_BRIGHT)
	lbh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbvb.add_child(lbh)
	leaderboard_status_lbl = _label("LOCAL RECORDS", f_ui, 8, Game.COL_MUTED)
	leaderboard_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbvb.add_child(leaderboard_status_lbl)
	leaderboard_list = VBoxContainer.new()
	leaderboard_list.add_theme_constant_override("separation", 2)
	lbvb.add_child(leaderboard_list)
	_refresh_leaderboard_panel()

	center_holder = CenterContainer.new()
	center_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center_holder)
	var vb := VBoxContainer.new()
	menu_box = vb
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_theme_constant_override("separation", 10)
	center_holder.add_child(menu_box)

	title_logo = TextureRect.new()
	title_logo.texture = load(MAIN_MENU_LOGO)
	title_logo.custom_minimum_size = Vector2(520, 144)
	title_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	title_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(title_logo)
	vb.add_child(_label("FOUR MEME KINGS. ONE PIXEL WAR.", f_ui, 13, Game.COL_MUTED))
	vb.add_child(_label("CHOOSE YOUR KING", f_ui, 14, Game.COL_BONE))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for k in Game.KINGS.keys():
		row.add_child(_card(k))

	var setup_row := HBoxContainer.new()
	setup_row.alignment = BoxContainer.ALIGNMENT_CENTER
	setup_row.add_theme_constant_override("separation", 34)
	vb.add_child(setup_row)

	var pressure_col := VBoxContainer.new()
	pressure_col.alignment = BoxContainer.ALIGNMENT_CENTER
	pressure_col.add_theme_constant_override("separation", 6)
	setup_row.add_child(pressure_col)
	pressure_col.add_child(_label("PRESSURE", f_ui, 10, Game.COL_MUTED))
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	prow.add_theme_constant_override("separation", 8)
	pressure_col.add_child(prow)
	for p in ["standard", "rush", "siege"]:
		var pp: String = p
		var pb := _small_button(pp.to_upper())
		pb.pressed.connect(func():
			pressure = pp
			_refresh_setup())
		pressure_btns[pp] = pb
		prow.add_child(pb)

	var arena_col := VBoxContainer.new()
	arena_col.alignment = BoxContainer.ALIGNMENT_CENTER
	arena_col.add_theme_constant_override("separation", 6)
	setup_row.add_child(arena_col)
	arena_col.add_child(_label("ARENA", f_ui, 10, Game.COL_MUTED))
	var arow := HBoxContainer.new()
	arow.alignment = BoxContainer.ALIGNMENT_CENTER
	arow.add_theme_constant_override("separation", 8)
	arena_col.add_child(arow)
	var lb := _small_button("<")
	lb.pressed.connect(func(): _cycle_arena(-1))
	arow.add_child(lb)
	arena_lbl = _label(Game.ARENAS[Game.ARENA_ORDER[arena_idx]]["label"], f_ui, 14, Game.COL_ACCENT_BRIGHT)
	arena_lbl.custom_minimum_size = Vector2(150, 0)
	arow.add_child(arena_lbl)
	var rb := _small_button(">")
	rb.pressed.connect(func(): _cycle_arena(1))
	arow.add_child(rb)

	var wager_col := VBoxContainer.new()
	wager_col.alignment = BoxContainer.ALIGNMENT_CENTER
	wager_col.add_theme_constant_override("separation", 6)
	setup_row.add_child(wager_col)
	wager_col.add_child(_label("WAGER", f_ui, 10, Game.COL_MUTED))
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 8)
	wager_col.add_child(wrow)
	var wminus := _small_button("-")
	wminus.pressed.connect(func(): _bump_wager(-50))
	wrow.add_child(wminus)
	wager_lbl = _label("", f_ui, 14, Game.COL_ACCENT_BRIGHT)
	wager_lbl.custom_minimum_size = Vector2(230, 0)
	wrow.add_child(wager_lbl)
	var wplus := _small_button("+")
	wplus.pressed.connect(func(): _bump_wager(50))
	wrow.add_child(wplus)
	_refresh_wager()

	var start := Button.new()
	start.text = "START WAR"
	start.add_theme_font_override("font", f_ui)
	start.add_theme_font_size_override("font_size", 16)
	start.add_theme_color_override("font_color", Game.COL_INK)
	start.custom_minimum_size = Vector2(760, 50)
	start.add_theme_stylebox_override("normal", _button_style(true))
	start.add_theme_stylebox_override("hover", _button_style(true))
	start.add_theme_stylebox_override("pressed", _button_style(true, true))
	start.pressed.connect(_start)
	vb.add_child(start)

	# lobby last so it overlays the whole menu
	_build_lobby()
	move_child(wallet_btn, get_child_count() - 1)
	move_child(mp_btn, get_child_count() - 1)
	move_child(wallet_status_lbl, get_child_count() - 1)
	move_child(lobby, get_child_count() - 1)
	Net.status_changed.connect(func(t): if net_status_lbl: net_status_lbl.text = t)
	Net.roster_changed.connect(_refresh_roster)
	Net.got_message.connect(_on_room_message)
	Net.launch_match.connect(_on_launch_match)
	get_viewport().size_changed.connect(_apply_responsive_layout)

	_apply_url_params()
	_highlight()
	_refresh_setup()
	_apply_responsive_layout()
	_request_web_leaderboard()
	if "--shot" in OS.get_cmdline_args() or "--shot" in OS.get_cmdline_user_args():
		_capture()
	if "--room-links-smoke" in OS.get_cmdline_args() or "--room-links-smoke" in OS.get_cmdline_user_args():
		call_deferred("_room_links_smoke")

func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", f_ui)
	b.add_theme_font_size_override("font_size", 10)
	b.add_theme_color_override("font_color", Game.COL_BONE)
	b.custom_minimum_size = Vector2(112, 34)
	b.add_theme_stylebox_override("normal", _button_style(false))
	b.add_theme_stylebox_override("hover", _button_style(true))
	b.add_theme_stylebox_override("pressed", _button_style(false, true))
	return b

func _menu_panel() -> StyleBox:
	return _texture_style(UI_RD_PANEL, 22.0, 18.0)

func _refresh_wallet() -> void:
	if Wallet.verified:
		wallet_btn.text = "SOL  " + Wallet.short()
		wallet_btn.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
		_set_wallet_status("VERIFIED SOL WAGER\nSIGNED LEADERBOARD", Game.COL_ACCENT_BRIGHT)
	elif Wallet.last_error != "":
		wallet_btn.text = "CONNECT PHANTOM"
		wallet_btn.add_theme_color_override("font_color", Game.COL_BONE)
		var status := "TICKET MODE ACTIVE\nPHANTOM NOT FOUND" if Wallet.last_error == "Phantom not found" else "TICKET MODE ACTIVE\nSIGNATURE NEEDED"
		_set_wallet_status(status, Game.COL_MUTED)
	elif Wallet.connected:
		wallet_btn.text = "VERIFYING"
		wallet_btn.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
		_set_wallet_status("SIGN WALLET MESSAGE\nSOL BOARD PENDING", Game.COL_ACCENT_BRIGHT)
	else:
		wallet_btn.text = "CONNECT PHANTOM"
		wallet_btn.add_theme_color_override("font_color", Game.COL_BONE)
		_set_wallet_status("TICKET MODE ACTIVE\nCONNECT FOR SOL", Game.COL_MUTED)
	_refresh_wager()

func _set_wallet_status(text: String, col: Color) -> void:
	if not is_instance_valid(wallet_status_lbl):
		return
	wallet_status_lbl.text = text
	wallet_status_lbl.add_theme_color_override("font_color", col)

func _refresh_leaderboard_panel(entries := [], remote := false) -> void:
	if not is_instance_valid(leaderboard_list):
		return
	for child in leaderboard_list.get_children():
		child.queue_free()
	if is_instance_valid(leaderboard_status_lbl):
		leaderboard_status_lbl.text = "WEB BOARD" if remote else "LOCAL RECORDS"
	var printed := 0
	if remote:
		for item in entries:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var row := _leaderboard_web_row(item, printed + 1)
			leaderboard_list.add_child(row)
			printed += 1
			if printed >= 5:
				break
	if printed == 0:
		if remote and is_instance_valid(leaderboard_status_lbl):
			leaderboard_status_lbl.text = "WEB BOARD EMPTY"
		for k in Game.KINGS.keys():
			var rec: Dictionary = Game.board.get(k, {"wins": 0, "losses": 0})
			var row2 := _label("%-10s %2dW / %2dL" % [String(Game.KINGS[k]["name"]), int(rec["wins"]), int(rec["losses"])], f_ui, 9, Game.KINGS[k]["color"])
			row2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			leaderboard_list.add_child(row2)

func _leaderboard_web_row(item: Dictionary, rank: int) -> Label:
	var king_id := _valid_king(String(item.get("kingId", item.get("king", ""))))
	var col: Color = Game.KINGS.get(king_id, {}).get("color", Game.COL_BONE)
	var name := String(Game.KINGS.get(king_id, {}).get("name", item.get("king", "?")))
	var score := int(item.get("score", 0))
	var result := String(item.get("result", "")).to_upper().left(1)
	var unit := String(item.get("wagerUnit", "SOL" if bool(item.get("verified", false)) else "ticket")).to_upper()
	var tag := "SOL" if unit == "SOL" else "TKT"
	var row := _label("#%d %-8s %s %4d %s" % [rank, name.left(8), result, score, tag], f_ui, 9, col)
	row.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.clip_text = true
	return row

func _request_web_leaderboard() -> void:
	if not OS.has_feature("web"):
		return
	_leaderboard_sync_id += 1
	if is_instance_valid(leaderboard_status_lbl):
		leaderboard_status_lbl.text = "SYNCING WEB BOARD"
	JavaScriptBridge.eval("""
(function(){
  window.__memepireLeaderboardStatus = 'loading';
  fetch('/leaderboard', {cache: 'no-store'}).then(function(res){ return res.json(); }).then(function(data){
    window.__memepireLeaderboard = data || {};
    window.__memepireLeaderboardStatus = 'ready';
    window.__memepireState = Object.assign(window.__memepireState || {}, {
      leaderboardLoaded: true,
      leaderboardRows: ((data && data.entries) || []).length
    });
  }).catch(function(err){
    window.__memepireLeaderboardStatus = 'error';
    window.__memepireLeaderboardError = String(err && err.message || err);
  });
  return true;
})()
	""", true)
	_poll_web_leaderboard(_leaderboard_sync_id, 0)

func _poll_web_leaderboard(sync_id: int, attempt: int) -> void:
	await get_tree().create_timer(0.35).timeout
	if sync_id != _leaderboard_sync_id:
		return
	if _read_web_leaderboard():
		return
	if attempt < 16:
		_poll_web_leaderboard(sync_id, attempt + 1)
	elif is_instance_valid(leaderboard_status_lbl):
		var status := _web_leaderboard_status()
		leaderboard_status_lbl.text = "WEB BOARD ERROR" if status == "error" else "LOCAL RECORDS"
		leaderboard_status_lbl.add_theme_color_override("font_color", Game.COL_ENEMY if status == "error" else Game.COL_MUTED)

func _read_web_leaderboard() -> bool:
	if not OS.has_feature("web"):
		return false
	if _web_leaderboard_status() == "error":
		if is_instance_valid(leaderboard_status_lbl):
			leaderboard_status_lbl.text = "WEB BOARD ERROR"
			leaderboard_status_lbl.add_theme_color_override("font_color", Game.COL_ENEMY)
		return false
	var raw = JavaScriptBridge.eval("JSON.stringify(window.__memepireLeaderboard || {})", true)
	if raw == null:
		return false
	var text := String(raw)
	if text == "" or text == "{}":
		return false
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var entries = parsed.get("entries", [])
	if typeof(entries) != TYPE_ARRAY:
		return false
	_refresh_leaderboard_panel(entries, true)
	return true

func _web_leaderboard_status() -> String:
	if not OS.has_feature("web"):
		return ""
	var status = JavaScriptBridge.eval("window.__memepireLeaderboardStatus || ''", true)
	return String(status) if status != null else ""

func _wager_unit_label() -> String:
	return "SOL" if Wallet.verified else "ticket"

func _wager_mode_label() -> String:
	return "verified SOL" if Wallet.verified else "ticket"

func _refresh_wager() -> void:
	if not is_instance_valid(wager_lbl):
		return
	if Game.wager_stake <= 0:
		wager_lbl.text = "NO TICKET"
	else:
		var unit := _wager_unit_label().to_upper()
		wager_lbl.text = "%s %d  TAX %d  WIN %d" % [unit, Game.wager_stake, Game.wager_tax(), Game.wager_payout(true)]

func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var display := _display_size()
	var portrait := display.y > display.x * 1.15
	if is_instance_valid(center_holder):
		center_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		var lift := vp.y * 0.34 if portrait else 0.0
		center_holder.offset_left = 0
		center_holder.offset_right = 0
		center_holder.offset_top = -lift
		center_holder.offset_bottom = -lift
	if is_instance_valid(menu_box):
		menu_box.pivot_offset = menu_box.size * 0.5
		menu_box.scale = Vector2(1.22, 1.22) if portrait else Vector2.ONE
	if is_instance_valid(title_logo):
		title_logo.custom_minimum_size = Vector2(330, 110) if portrait else Vector2(520, 144)
	if is_instance_valid(leaderboard_panel):
		leaderboard_panel.visible = not portrait
	if is_instance_valid(wallet_btn):
		var top := 10.0 if portrait else 16.0
		var width := 156.0 if portrait else 208.0
		wallet_btn.offset_left = -width - 10.0
		wallet_btn.offset_right = -10.0
		wallet_btn.offset_top = top
		wallet_btn.offset_bottom = top + 30.0
		wallet_btn.custom_minimum_size = Vector2(width, 30)
	if is_instance_valid(mp_btn):
		var top := 46.0 if portrait else 56.0
		var width := 156.0 if portrait else 208.0
		mp_btn.offset_left = -width - 10.0
		mp_btn.offset_right = -10.0
		mp_btn.offset_top = top
		mp_btn.offset_bottom = top + 30.0
		mp_btn.custom_minimum_size = Vector2(width, 30)
	if is_instance_valid(wallet_status_lbl):
		var width := 172.0 if portrait else 240.0
		var top := 82.0 if portrait else 94.0
		wallet_status_lbl.offset_left = -width - 12.0
		wallet_status_lbl.offset_right = -12.0
		wallet_status_lbl.offset_top = top
		wallet_status_lbl.offset_bottom = top + 42.0
		wallet_status_lbl.add_theme_font_size_override("font_size", 7 if portrait else 8)

func _display_size() -> Vector2:
	if OS.has_feature("web"):
		var w = JavaScriptBridge.eval("window.innerWidth || 0", true)
		var h = JavaScriptBridge.eval("window.innerHeight || 0", true)
		var display := Vector2(float(w), float(h))
		if display.x > 0 and display.y > 0:
			return display
	return Vector2(get_window().size)

func _bump_wager(d: int) -> void:
	Game.wager_stake = clampi(Game.wager_stake + d, 0, 5000)
	_last_offer_key = ""
	wager_ticket_accepted = false
	peer_wager_offer.clear()
	_refresh_wager()
	_refresh_room_share()
	_set_wager_status("%s wager updated" % _wager_mode_label())
	_send_wager_offer_soon()

func _line_edit(val: String) -> LineEdit:
	var le := LineEdit.new()
	le.text = val
	le.add_theme_font_override("font", f_ui)
	le.add_theme_font_size_override("font_size", 12)
	le.custom_minimum_size = Vector2(320, 32)
	le.alignment = HORIZONTAL_ALIGNMENT_CENTER
	return le

func _build_lobby() -> void:
	lobby = Control.new()
	lobby.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.visible = false
	add_child(lobby)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	lobby.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	lobby.add_child(cc)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _menu_panel())
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	vb.add_child(_label("MULTIPLAYER ROOM", f_display, 18, Game.COL_ACCENT_BRIGHT))
	vb.add_child(_label("Same relay as this web build (/room).", f_ui, 10, Game.COL_MUTED))
	vb.add_child(_label("RELAY URL", f_ui, 10, Game.COL_MUTED))
	url_edit = _line_edit(Net.relay_url)
	vb.add_child(url_edit)
	vb.add_child(_label("ROOM CODE", f_ui, 10, Game.COL_MUTED))
	room_edit = _line_edit("MEMES")
	vb.add_child(room_edit)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_CENTER
	brow.add_theme_constant_override("separation", 10)
	vb.add_child(brow)
	var hostb := _small_button("HOST")
	hostb.pressed.connect(_net_host)
	brow.add_child(hostb)
	var joinb := _small_button("JOIN")
	joinb.pressed.connect(_net_join)
	brow.add_child(joinb)
	var copyb := _small_button("COPY LINKS")
	copyb.custom_minimum_size = Vector2(118, 32)
	copyb.pressed.connect(_copy_room_links)
	brow.add_child(copyb)
	net_status_lbl = _label("offline", f_ui, 12, Game.COL_BONE)
	vb.add_child(net_status_lbl)
	net_roster_lbl = _label("no commanders yet", f_ui, 11, Game.COL_MUTED)
	vb.add_child(net_roster_lbl)
	room_share_lbl = _label("room links ready", f_ui, 10, Game.COL_MUTED)
	vb.add_child(room_share_lbl)
	wager_status_lbl = _label("%s offer waits for opponent" % _wager_mode_label(), f_ui, 10, Game.COL_MUTED)
	vb.add_child(wager_status_lbl)
	var ticket_row := HBoxContainer.new()
	ticket_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ticket_row.add_theme_constant_override("separation", 10)
	vb.add_child(ticket_row)
	wager_accept_btn = _small_button("ACCEPT")
	wager_accept_btn.disabled = true
	wager_accept_btn.pressed.connect(_accept_wager)
	ticket_row.add_child(wager_accept_btn)
	wager_decline_btn = _small_button("DECLINE")
	wager_decline_btn.disabled = true
	wager_decline_btn.pressed.connect(_decline_wager)
	ticket_row.add_child(wager_decline_btn)
	var brow2 := HBoxContainer.new()
	brow2.alignment = BoxContainer.ALIGNMENT_CENTER
	brow2.add_theme_constant_override("separation", 10)
	vb.add_child(brow2)
	var launchb := _small_button("LAUNCH (HOST)")
	launchb.custom_minimum_size = Vector2(140, 32)
	launchb.pressed.connect(_net_launch)
	brow2.add_child(launchb)
	var closeb := _small_button("CLOSE")
	closeb.pressed.connect(_toggle_lobby)
	brow2.add_child(closeb)

func _toggle_lobby() -> void:
	lobby.visible = not lobby.visible
	if lobby.visible:
		url_edit.text = Net.relay_url
		_refresh_room_share()

func _origin_url() -> String:
	if not OS.has_feature("web"):
		return "http://127.0.0.1:8799"
	var origin = JavaScriptBridge.eval("window.location.origin || ''", true)
	if origin == null or String(origin) == "":
		return "http://127.0.0.1:8799"
	return String(origin)

func _room_code() -> String:
	var code := room_edit.text.strip_edges().to_upper()
	return code if code != "" else "MEMES"

func _room_links_text() -> String:
	var room := _room_code()
	var origin := _origin_url()
	var stake := str(Game.wager_stake)
	var rival := _selected_rival()
	return "Age of Memepires room %s\nHost: %s/?room=%s&host=1&stake=%s&king=%s&rival=%s\nJoin: %s/?room=%s&join=1&stake=%s&king=%s&rival=%s\nRoom Kit: %s/room-kit?room=%s&player=%s&rival=%s" % [
		room,
		origin, room.uri_encode(), stake, selected_king.uri_encode(), rival.uri_encode(),
		origin, room.uri_encode(), stake, rival.uri_encode(), selected_king.uri_encode(),
		origin, room.uri_encode(), selected_king.uri_encode(), rival.uri_encode(),
	]

func _room_links_smoke() -> void:
	selected_king = "doge"
	Game.rival_king = "pepe"
	Game.wager_stake = 500
	room_edit.text = "MEMES"
	var links := _room_links_text()
	var host_ok := links.contains("Host: http://127.0.0.1:8799/?room=MEMES&host=1&stake=500&king=doge&rival=pepe")
	var join_ok := links.contains("Join: http://127.0.0.1:8799/?room=MEMES&join=1&stake=500&king=pepe&rival=doge")
	print("ROOM_LINKS_SMOKE host=%s join=%s" % [str(host_ok).to_lower(), str(join_ok).to_lower()])
	get_tree().quit(0 if host_ok and join_ok else 1)

func _refresh_room_share() -> void:
	if room_share_lbl:
		room_share_lbl.text = "share code %s | %s %d | tax %d" % [_room_code(), _wager_unit_label().to_upper(), Game.wager_stake, Game.wager_tax()]

func _set_wager_status(text: String, can_answer := false) -> void:
	if wager_status_lbl:
		wager_status_lbl.text = text
	if wager_accept_btn:
		wager_accept_btn.disabled = not can_answer
	if wager_decline_btn:
		wager_decline_btn.disabled = not can_answer

func _local_wager_packet(status := "open") -> Dictionary:
	var unit := "SOL" if Wallet.verified else "ticket"
	return {
		"ticketId": "%s-%s-%d" % [_room_code(), selected_king, Game.wager_stake],
		"wagerStatus": status,
		"unit": unit,
		"verified": Wallet.verified,
		"wallet": Wallet.address if Wallet.verified else "",
		"walletLabel": Wallet.short() if Wallet.verified else "Ticket mode",
		"stake": Game.wager_stake,
		"tax": Game.wager_tax(),
		"net": Game.wager_net(),
		"winPayout": Game.wager_payout(true),
		"fromKing": selected_king,
		"fromLabel": String(Game.KINGS[selected_king]["name"]),
	}

func _send_wager_offer_soon() -> void:
	if not is_inside_tree():
		return
	call_deferred("_maybe_send_wager_offer")

func _maybe_send_wager_offer() -> void:
	if not Net.connected or Net.roster.is_empty():
		return
	var packet := _local_wager_packet("open")
	var key := "%s:%s:%s" % [Net.role, _room_code(), String(packet.get("ticketId", ""))]
	if key == _last_offer_key:
		return
	_last_offer_key = key
	Net.send_msg({"type": "wager-offer", "wager": packet, "identity": {"label": String(packet.get("fromLabel", "")), "king": selected_king}})
	_set_wager_status("%s offered: stake %d, win %d" % [String(packet.get("unit", "ticket")).to_upper(), int(packet.get("stake", 0)), int(packet.get("winPayout", 0))])

func _on_room_message(msg: Dictionary) -> void:
	var typ := String(msg.get("type", ""))
	if typ == "wager-offer":
		var wager = msg.get("wager", {})
		if typeof(wager) != TYPE_DICTIONARY:
			return
		peer_wager_offer = wager.duplicate()
		var stake := int(peer_wager_offer.get("stake", 0))
		var payout := int(peer_wager_offer.get("winPayout", 0))
		var label := String(peer_wager_offer.get("fromLabel", msg.get("from", "peer")))
		var unit := String(peer_wager_offer.get("unit", "SOL" if bool(peer_wager_offer.get("verified", false)) else "ticket"))
		_set_wager_status("%s offers %s %d, win %d" % [label, unit.to_upper(), stake, payout], true)
		Game.publish_web_state({"peerWagerOffer": peer_wager_offer})
	elif typ == "wager-receipt":
		var receipt = msg.get("wager", {})
		if typeof(receipt) != TYPE_DICTIONARY:
			return
		var status := String(receipt.get("wagerStatus", "seen"))
		wager_ticket_accepted = status == "accepted"
		var unit := String(receipt.get("unit", "ticket")).to_upper()
		_set_wager_status("peer %s %s %s" % [status, unit, String(receipt.get("ticketId", ""))])
		Game.publish_web_state({"wagerReceipt": receipt})

func _send_wager_receipt(status: String) -> void:
	if peer_wager_offer.is_empty() or not Net.connected:
		return
	var receipt := peer_wager_offer.duplicate()
	receipt["wagerStatus"] = status
	receipt["fromKing"] = selected_king
	receipt["fromLabel"] = String(Game.KINGS[selected_king]["name"])
	wager_ticket_accepted = status == "accepted"
	Net.send_msg({"type": "wager-receipt", "wager": receipt, "identity": {"label": String(receipt.get("fromLabel", "")), "king": selected_king}})
	_set_wager_status("you %s %s %s" % [status, String(receipt.get("unit", "ticket")).to_upper(), String(receipt.get("ticketId", ""))])
	Game.publish_web_state({"wagerReceipt": receipt})

func _accept_wager() -> void:
	_send_wager_receipt("accepted")

func _decline_wager() -> void:
	_send_wager_receipt("declined")

func _web_query_params() -> Dictionary:
	if not OS.has_feature("web"):
		return {}
	var raw = JavaScriptBridge.eval("window.location.search || ''", true)
	var qs := String(raw)
	if qs.begins_with("?"):
		qs = qs.substr(1)
	var out := {}
	for pair in qs.split("&", false):
		var eq := pair.find("=")
		var key := pair.substr(0, eq if eq >= 0 else pair.length()).uri_decode()
		var val := "1" if eq < 0 else pair.substr(eq + 1).uri_decode()
		if key != "":
			out[key] = val
	return out

func _truthy(v) -> bool:
	var s := String(v).strip_edges().to_lower()
	return ["1", "true", "yes", "on", "host", "join"].has(s)

func _valid_king(v: String) -> String:
	var key := v.strip_edges().to_lower().replace("$", "")
	return key if Game.KINGS.has(key) else ""

func _selected_rival() -> String:
	var rival := _valid_king(Game.rival_king)
	if rival != "" and rival != selected_king:
		return rival
	for k in Game.KINGS.keys():
		if k != selected_king:
			return k
	return "pepe"

func _set_arena(id: String) -> void:
	var key := id.strip_edges().to_lower()
	if not Game.ARENAS.has(key):
		return
	var idx := Game.ARENA_ORDER.find(key)
	if idx >= 0:
		arena_idx = idx
		arena_lbl.text = Game.ARENAS[key]["label"]

func _set_pressure(id: String) -> void:
	var key := id.strip_edges().to_lower()
	if ["standard", "rush", "siege"].has(key):
		pressure = key

func _apply_url_params() -> void:
	var params := _web_query_params()
	if params.is_empty():
		return
	var room := String(params.get("room", "")).strip_edges()
	if room != "":
		room_edit.text = room.to_upper()
	var relay := String(params.get("relay", "")).strip_edges()
	if relay.begins_with("ws"):
		Net.relay_url = relay
		url_edit.text = relay
	var king := _valid_king(String(params.get("king", params.get("player", ""))))
	if king != "":
		selected_king = king
	var rival := _valid_king(String(params.get("rival", params.get("opponent", ""))))
	if rival != "" and rival != selected_king:
		Game.rival_king = rival
	var stake := String(params.get("stake", "")).strip_edges()
	if stake != "":
		Game.wager_stake = clampi(int(stake), 0, 5000)
		_last_offer_key = ""
		wager_ticket_accepted = false
	_set_pressure(String(params.get("pressure", "")))
	_set_arena(String(params.get("arena", params.get("map", ""))))
	_refresh_wager()
	_refresh_room_share()
	Game.publish_web_state({
		"urlParamsApplied": true,
		"room": _room_code(),
		"selectedKing": selected_king,
		"rivalKing": _selected_rival(),
		"pressure": pressure,
		"arena": Game.ARENA_ORDER[arena_idx],
		"wagerStake": Game.wager_stake,
	})
	var role := String(params.get("roomRole", "")).strip_edges().to_lower()
	if _truthy(params.get("host", "")) or role == "host":
		lobby.visible = true
		call_deferred("_net_host")
	elif _truthy(params.get("join", "")) or role == "join":
		lobby.visible = true
		call_deferred("_net_join")
	elif _truthy(params.get("start", "")):
		call_deferred("_start")

func _copy_room_links() -> void:
	var text := _room_links_text()
	DisplayServer.clipboard_set(text)
	if room_share_lbl:
		room_share_lbl.text = "copied room links for %s" % _room_code()
	Game.publish_web_state({"copiedRoom": _room_code(), "copiedRoomLinks": text})

func _refresh_roster() -> void:
	if not net_roster_lbl:
		return
	if Net.roster.is_empty():
		net_roster_lbl.text = "waiting for opponent…"
		_set_wager_status("%s offer waits for opponent" % _wager_mode_label())
		return
	var names := []
	for p in Net.roster:
		names.append(String(p.get("label", "?")))
	net_roster_lbl.text = "in room: " + ", ".join(names)
	_send_wager_offer_soon()

func _net_host() -> void:
	Game.player_king = selected_king
	Game.net_mode = "host"
	Game.my_team = 0
	Net.relay_url = url_edit.text.strip_edges()
	_last_offer_key = ""
	wager_ticket_accepted = false
	peer_wager_offer.clear()
	_refresh_room_share()
	_set_wager_status("hosting %s room" % _wager_mode_label())
	Game.publish_web_state({"scene": "menu", "netMode": Game.net_mode, "myTeam": Game.my_team, "selectedKing": selected_king})
	Net.host_room(room_edit.text.strip_edges())
	_send_wager_offer_soon()

func _net_join() -> void:
	Game.player_king = selected_king
	Game.net_mode = "join"
	Game.my_team = 1
	Net.relay_url = url_edit.text.strip_edges()
	_last_offer_key = ""
	wager_ticket_accepted = false
	peer_wager_offer.clear()
	_refresh_room_share()
	_set_wager_status("joining %s room" % _wager_mode_label())
	Game.publish_web_state({"scene": "menu", "netMode": Game.net_mode, "myTeam": Game.my_team, "selectedKing": selected_king})
	Net.join_room(room_edit.text.strip_edges())
	_send_wager_offer_soon()

func _net_launch() -> void:
	if not Net.connected:
		net_status_lbl.text = "host or join a room first"
		return
	if Net.role != "host":
		net_status_lbl.text = "waiting for host to launch"
		return
	if Net.roster.is_empty():
		net_status_lbl.text = "waiting for opponent"
		return
	if Game.wager_stake > 0 and not wager_ticket_accepted:
		net_status_lbl.text = "waiting for accepted wager"
		_set_wager_status("waiting for accepted %s" % _wager_mode_label())
		return
	Game.player_king = selected_king
	Game.net_mode = "host"
	Game.my_team = 0
	Net.launch(Game.ARENA_ORDER[arena_idx], pressure)

func _on_launch_match(cfg: Dictionary) -> void:
	Game.pressure = String(cfg.get("pressure", pressure))
	Game.arena = String(cfg.get("arena", Game.ARENA_ORDER[arena_idx]))
	var launch_wager = cfg.get("wager", {})
	if typeof(launch_wager) == TYPE_DICTIONARY and launch_wager.has("stake"):
		Game.wager_stake = clampi(int(launch_wager.get("stake", Game.wager_stake)), 0, 5000)
	Game.net_mode = "host" if Net.role == "host" else "join"
	Game.my_team = 0 if Net.role == "host" else 1
	var host_king := String(cfg.get("host_king", "fartcoin"))
	if Net.role == "join":
		Game.player_king = host_king
		Game.rival_king = selected_king
	else:
		Game.player_king = selected_king
		var rival := ""
		for p in Net.roster:
			if String(p.get("king", "")) != "" and String(p["king"]) != selected_king:
				rival = String(p["king"])
				break
		if rival == "" or rival == selected_king:
			for k in Game.KINGS.keys():
				if k != selected_king:
					rival = k
					break
		Game.rival_king = rival
	Game.publish_web_state({"scene": "launching", "netMode": Game.net_mode, "myTeam": Game.my_team, "playerKing": Game.player_king, "rivalKing": Game.rival_king})
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _cycle_arena(d: int) -> void:
	arena_idx = (arena_idx + d + Game.ARENA_ORDER.size()) % Game.ARENA_ORDER.size()
	arena_lbl.text = Game.ARENAS[Game.ARENA_ORDER[arena_idx]]["label"]

func _refresh_setup() -> void:
	for p in pressure_btns:
		if p == pressure:
			pressure_btns[p].add_theme_stylebox_override("normal", _button_style(true))
			pressure_btns[p].add_theme_stylebox_override("hover", _button_style(true))
		else:
			pressure_btns[p].add_theme_stylebox_override("normal", _button_style(false))
			pressure_btns[p].add_theme_stylebox_override("hover", _button_style(true))
		pressure_btns[p].queue_redraw()

func _label(text: String, font: FontFile, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

func _card(king: String) -> Button:
	var data: Dictionary = Game.KINGS[king]
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 178)
	b.add_theme_stylebox_override("normal", _texture_style(UI_RD_PANEL, 22.0, 8.0))
	b.add_theme_stylebox_override("hover", _texture_style(UI_RD_PANEL_LARGE, 26.0, 8.0, Color(1.08, 1.08, 1.08, 1.0)))
	b.add_theme_stylebox_override("pressed", _texture_style(UI_RD_PANEL, 22.0, 8.0, Color(0.78, 0.82, 0.92, 1.0)))
	b.pressed.connect(func():
		selected_king = king
		_highlight())
	cards[king] = b

	var inset := MarginContainer.new()
	inset.set_anchors_preset(Control.PRESET_FULL_RECT)
	inset.offset_left = 22
	inset.offset_right = -22
	inset.offset_top = 24
	inset.offset_bottom = -30
	inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(inset)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inset.add_child(col)

	var port := TextureRect.new()
	port.texture = load("res://assets/portraits/king_portrait_%s.png" % king)
	port.custom_minimum_size = Vector2(76, 72)
	port.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	port.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(port)
	var nm := _label(data["name"], f_ui, 11, data["color"])
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var kd := _label(data["kingdom"], f_ui, 8, Game.COL_MUTED)
	kd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(kd)
	return b

func _highlight() -> void:
	for k in cards:
		if k == selected_king:
			cards[k].add_theme_stylebox_override("normal", _texture_style(UI_RD_PANEL_LARGE, 26.0, 8.0, Color(1.05, 1.08, 1.1, 1.0)))
			cards[k].add_theme_stylebox_override("hover", _texture_style(UI_RD_PANEL_LARGE, 26.0, 8.0, Color(1.12, 1.12, 1.12, 1.0)))
		else:
			cards[k].add_theme_stylebox_override("normal", _texture_style(UI_RD_PANEL, 22.0, 8.0, Color(0.88, 0.92, 1.0, 1.0)))
			cards[k].add_theme_stylebox_override("hover", _texture_style(UI_RD_PANEL_LARGE, 26.0, 8.0, Color(1.08, 1.08, 1.08, 1.0)))
		cards[k].queue_redraw()

func _start() -> void:
	Game.net_mode = ""
	Game.my_team = 0
	Game.player_king = selected_king
	Game.rival_king = _selected_rival()
	Game.pressure = pressure
	Game.arena = Game.ARENA_ORDER[arena_idx]
	get_tree().change_scene_to_file("res://scenes/Main.tscn")

func _capture() -> void:
	if "--lobby" in OS.get_cmdline_user_args():
		lobby.visible = true
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_preview.png")
	print("SHOT_SAVED")
	get_tree().quit()
