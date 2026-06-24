extends CanvasLayer
## Blue pixel HUD: resource bar (top) + command card (bottom).

var main: Node = null
var f_display: FontFile
var f_ui: FontFile
var f_read: FontFile

var lbl_food: Label
var lbl_timber: Label
var lbl_memp: Label
var lbl_pop: Label
var lbl_kills: Label
var lbl_wave: Label
var lbl_wager: Label
var lbl_queue: Label
var lbl_threat: Label
var lbl_sel: Label
var lbl_sel_comp: Label
var lbl_sel_health: Label
var lbl_tech: Label
var lbl_groups: Label
var lbl_mode: Label
var btn_pause: Button
var btn_speed: Button
var btn_power: Button
var btn_zoom: Button
var log_label: Label
var obj_rows: Array = []
var _cost_buttons: Array = []
var _cmd_buttons: Array = []
var _ctrl_buttons: Array = []
var _side_buttons: Array = []
var topbar: Control
var command_card: PanelContainer
var command_row: HFlowContainer
var command_status: VBoxContainer
var control_bar: HFlowContainer
var side_panel: PanelContainer
var portrait_build_frame: PanelContainer
var portrait_build_row: HFlowContainer
var objectives_panel: PanelContainer
var log_panel: PanelContainer
var minimap_frame: PanelContainer
var minimap_view: Control
var matchup_holder: Control
var _portrait_build_buttons: Array = []

const RESOURCE_ICONS := {
	"food": "res://assets/ui/ui_food_icon.png",
	"timber": "res://assets/ui/ui_timber_icon.png",
	"memp": "res://assets/ui/ui_memp_icon.png",
}

const COMMAND_ICONS := {
	"villager": "res://assets/ui/command_icon_villager.png",
	"swordsman": "res://assets/ui/command_icon_swordsman.png",
	"archer": "res://assets/ui/command_icon_archer.png",
	"lancer": "res://assets/ui/command_icon_lancer.png",
	"siege": "res://assets/ui/command_icon_siege.png",
	"house": "res://assets/ui/command_icon_house.png",
	"forge": "res://assets/ui/command_icon_forge.png",
	"tower": "res://assets/ui/command_icon_tower.png",
	"market": "res://assets/ui/command_icon_market.png",
	"upgrade_atk": "res://assets/ui/command_icon_swordsman.png",
	"upgrade_armor": "res://assets/ui/command_icon_forge.png",
	"upgrade_eco": "res://assets/ui/command_icon_market.png",
}

const CONTROL_ICONS := {
	"army": "res://assets/ui/control_icon_army.png",
	"attack": "res://assets/ui/control_icon_attack.png",
	"concede": "res://assets/ui/control_icon_concede.png",
	"defend": "res://assets/ui/control_icon_hold.png",
	"gather": "res://assets/ui/control_icon_gather.png",
	"hold": "res://assets/ui/control_icon_hold.png",
	"pause": "res://assets/ui/control_icon_pause.png",
	"power": "res://assets/ui/control_icon_power.png",
	"rally": "res://assets/ui/control_icon_rally.png",
	"speed": "res://assets/ui/control_icon_speed.png",
	"workers": "res://assets/ui/control_icon_workers.png",
	"zoom": "res://assets/ui/control_icon_speed.png",
}

const UI_RD_PANEL := "res://assets/ui/ui_rd_panel_medium.png"
const UI_RD_PANEL_LARGE := "res://assets/ui/ui_rd_panel_large.png"
const UI_RD_BUTTON := "res://assets/ui/ui_rd_status_bar.png"
const UI_RD_BUTTON_HOVER := "res://assets/ui/ui_rd_status_bar_blue.png"

func _texture_style(path: String, margin := 24.0, content := 8.0, tint := Color.WHITE) -> StyleBox:
	var tex: Texture2D = load(path)
	if tex == null:
		return _flat_panel(false)
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

func _ready() -> void:
	main = get_parent()
	f_display = load("res://assets/fonts/press-start-2p.ttf")
	f_ui = load("res://assets/fonts/silkscreen.ttf")
	f_read = load("res://assets/fonts/vt323.ttf")
	_build_topbar()
	_build_command_card()
	_build_control_bar()
	_build_side_panel()
	_build_portrait_build_bar()
	_build_objectives_panel()
	_build_log_panel()
	_build_minimap()
	_build_matchup()
	Game.resources_changed.connect(_refresh)
	Game.selection_changed.connect(_on_selection)
	Game.logged.connect(_on_log)
	get_viewport().size_changed.connect(_apply_responsive_layout)
	_apply_responsive_layout()
	_refresh()
	_on_log("")

func _flat_panel(hi := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var bg := Game.COL_PANEL_HI if hi else Game.COL_PANEL
	bg.a = 0.94
	sb.bg_color = bg
	sb.border_color = Game.COL_EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	# top cyan highlight line
	sb.shadow_color = Color(Game.COL_ACCENT_BRIGHT, 0.18)
	return sb

func _panel(hi := false) -> StyleBox:
	var tint := Color(1.0, 1.0, 1.0, 1.0) if hi else Color(0.92, 0.96, 1.0, 1.0)
	return _texture_style(UI_RD_PANEL_LARGE if hi else UI_RD_PANEL, 28.0 if hi else 22.0, 7.0, tint)

func _chip(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel())
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f_ui)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Game.COL_BONE)
	p.add_child(l)
	return p

func _value_chip(text: String, icon_key := "") -> Array:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _panel())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	p.add_child(row)
	if icon_key != "" and RESOURCE_ICONS.has(icon_key):
		var icon := TextureRect.new()
		icon.texture = load(RESOURCE_ICONS[icon_key])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f_ui)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Game.COL_BONE)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return [p, l]

func _accent_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", f_ui)
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", Game.COL_BONE)
	b.add_theme_color_override("font_hover_color", Game.COL_ACCENT_BRIGHT)
	b.custom_minimum_size = Vector2(96, 34)
	var normal := _texture_style(UI_RD_BUTTON, 18.0, 5.0)
	var hover := _texture_style(UI_RD_BUTTON_HOVER, 18.0, 5.0, Color(1.08, 1.08, 1.08, 1.0))
	var pressed := _texture_style(UI_RD_BUTTON, 18.0, 5.0, Color(0.72, 0.78, 0.9, 1.0))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	return b

func _apply_command_icon(b: Button, kind: String) -> void:
	var path: String = COMMAND_ICONS.get(kind, "")
	if path == "":
		return
	var tex := load(path)
	if tex == null:
		return
	b.icon = tex
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_spacing", 5)

func _apply_control_icon(b: Button, kind: String) -> void:
	var path: String = CONTROL_ICONS.get(kind, "")
	if path == "":
		return
	var tex := load(path)
	if tex == null:
		return
	b.icon = tex
	b.expand_icon = false
	b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_constant_override("icon_spacing", 3)

func _build_topbar() -> void:
	var bar := HFlowContainer.new()
	topbar = bar
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 10
	bar.offset_top = 8
	bar.offset_right = -10
	bar.add_theme_constant_override("separation", 8)
	bar.add_theme_constant_override("v_separation", 6)
	add_child(bar)

	# brand
	var brand := Label.new()
	brand.text = "AGE OF MEMEPIRES"
	brand.add_theme_font_override("font", f_display)
	brand.add_theme_font_size_override("font_size", 14)
	brand.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	var bp := PanelContainer.new()
	bp.add_theme_stylebox_override("panel", _panel())
	bp.add_child(brand)
	bar.add_child(bp)

	var r1 = _value_chip("FOOD 0", "food"); lbl_food = r1[1]; bar.add_child(r1[0])
	var r2 = _value_chip("TIMBER 0", "timber"); lbl_timber = r2[1]; bar.add_child(r2[0])
	var r3 = _value_chip("MEMP 0", "memp"); lbl_memp = r3[1]; bar.add_child(r3[0])
	var r4 = _value_chip("POP 0/0"); lbl_pop = r4[1]; bar.add_child(r4[0])
	var r5 = _value_chip("KILLS 0"); lbl_kills = r5[1]; bar.add_child(r5[0])
	var rw = _value_chip("WAVE 0"); lbl_wave = rw[1]; bar.add_child(rw[0])
	var rb = _value_chip("BET 0"); lbl_wager = rb[1]; bar.add_child(rb[0])
	var r6 = _value_chip("QUEUE 0"); lbl_queue = r6[1]; bar.add_child(r6[0])
	var r7 = _value_chip("BASE CLEAR"); lbl_threat = r7[1]; bar.add_child(r7[0])

func _build_command_card() -> void:
	var card := PanelContainer.new()
	command_card = card
	card.add_theme_stylebox_override("panel", _panel())
	card.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	card.offset_left = 268
	card.offset_right = -10
	card.offset_top = -66
	card.offset_bottom = -8
	add_child(card)

	var row := HFlowContainer.new()
	command_row = row
	row.add_theme_constant_override("separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	card.add_child(row)

	var status := VBoxContainer.new()
	command_status = status
	status.add_theme_constant_override("separation", 2)
	status.custom_minimum_size = Vector2(148, 0)
	row.add_child(status)

	var sel := Label.new()
	sel.text = "SELECTED 0"
	sel.add_theme_font_override("font", f_ui)
	sel.add_theme_font_size_override("font_size", 12)
	sel.add_theme_color_override("font_color", Game.COL_MUTED)
	sel.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl_sel = sel
	status.add_child(sel)

	lbl_mode = Label.new()
	lbl_mode.text = "READY"
	lbl_mode.add_theme_font_override("font", f_ui)
	lbl_mode.add_theme_font_size_override("font_size", 10)
	lbl_mode.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	lbl_mode.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_child(lbl_mode)

	lbl_sel_comp = Label.new()
	lbl_sel_comp.text = "NO UNITS"
	lbl_sel_comp.add_theme_font_override("font", f_ui)
	lbl_sel_comp.add_theme_font_size_override("font_size", 9)
	lbl_sel_comp.add_theme_color_override("font_color", Game.COL_BONE)
	lbl_sel_comp.clip_text = true
	status.add_child(lbl_sel_comp)

	lbl_sel_health = Label.new()
	lbl_sel_health.text = "HP --  IDLE"
	lbl_sel_health.add_theme_font_override("font", f_ui)
	lbl_sel_health.add_theme_font_size_override("font_size", 9)
	lbl_sel_health.add_theme_color_override("font_color", Game.COL_MUTED)
	lbl_sel_health.clip_text = true
	status.add_child(lbl_sel_health)

	lbl_tech = Label.new()
	lbl_tech.text = "TECH A+0 R+0 E100%"
	lbl_tech.add_theme_font_override("font", f_ui)
	lbl_tech.add_theme_font_size_override("font_size", 9)
	lbl_tech.add_theme_color_override("font_color", Game.COL_MUTED)
	lbl_tech.clip_text = true
	status.add_child(lbl_tech)

	lbl_groups = Label.new()
	lbl_groups.text = "GROUPS 1:- 2:- 3:- 4:- 5:-"
	lbl_groups.add_theme_font_override("font", f_ui)
	lbl_groups.add_theme_font_size_override("font_size", 8)
	lbl_groups.add_theme_color_override("font_color", Game.COL_MUTED)
	lbl_groups.clip_text = true
	status.add_child(lbl_groups)

	for k in Game.UNIT_KINDS:
		var kind: String = k
		row.add_child(_cmd_button(Game.UNIT_NAME[kind], kind, func(): main.train_unit(kind)))

func _cmd_button(text: String, kind: String, action: Callable) -> Button:
	var b := _accent_button(text)
	_apply_command_icon(b, kind)
	b.tooltip_text = "%s: train for %s" % [text, Game.cost_text(kind)]
	b.pressed.connect(action)
	_cost_buttons.append({"btn": b, "kind": kind, "label": text})
	_cmd_buttons.append(b)
	return b

func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f_ui)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	return l

func _side_button(text: String, kind: String, action: Callable) -> Button:
	var b := _accent_button(text)
	_apply_command_icon(b, kind)
	b.custom_minimum_size = Vector2(174, 31)
	b.tooltip_text = "%s: %s" % [text, Game.cost_text(kind)]
	b.pressed.connect(action)
	_cost_buttons.append({"btn": b, "kind": kind, "label": text})
	_side_buttons.append(b)
	return b

func _build_side_panel() -> void:
	var panel := PanelContainer.new()
	side_panel = panel
	panel.add_theme_stylebox_override("panel", _panel())
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -198
	panel.offset_right = -10
	panel.offset_top = 126
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	vb.add_child(_section_label("BUILD"))
	vb.add_child(_side_button("HOUSE  +6 POP", "house", func(): main.begin_build("house")))
	vb.add_child(_side_button("FORGE", "forge", func(): main.begin_build("forge")))
	vb.add_child(_side_button("TOWER", "tower", func(): main.begin_build("tower")))
	vb.add_child(_side_button("MARKET", "market", func(): main.begin_build("market")))
	vb.add_child(_section_label("TECH"))
	vb.add_child(_side_button("ATTACK  +3", "upgrade_atk", func(): main.do_research("upgrade_atk")))
	vb.add_child(_side_button("ARMOR  +2", "upgrade_armor", func(): main.do_research("upgrade_armor")))
	vb.add_child(_side_button("ECONOMY  +25%", "upgrade_eco", func(): main.do_research("upgrade_eco")))

func _portrait_build_button(text: String, kind: String, action: Callable) -> Button:
	var b := _accent_button(text)
	_apply_command_icon(b, kind)
	b.add_theme_font_size_override("font_size", 9)
	b.custom_minimum_size = Vector2(74, 30)
	b.tooltip_text = "%s: %s" % [text, Game.cost_text(kind)]
	b.pressed.connect(action)
	_cost_buttons.append({"btn": b, "kind": kind, "label": text})
	_portrait_build_buttons.append(b)
	return b

func _build_portrait_build_bar() -> void:
	var panel := PanelContainer.new()
	portrait_build_frame = panel
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _panel())
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 268
	panel.offset_right = -10
	panel.offset_top = -150
	panel.offset_bottom = -116
	add_child(panel)

	var row := HFlowContainer.new()
	portrait_build_row = row
	row.add_theme_constant_override("separation", 5)
	row.add_theme_constant_override("v_separation", 4)
	panel.add_child(row)
	row.add_child(_portrait_build_button("HOUSE", "house", func(): main.begin_build("house")))
	row.add_child(_portrait_build_button("FORGE", "forge", func(): main.begin_build("forge")))
	row.add_child(_portrait_build_button("TOWER", "tower", func(): main.begin_build("tower")))
	row.add_child(_portrait_build_button("MARKET", "market", func(): main.begin_build("market")))
	row.add_child(_portrait_build_button("ATK", "upgrade_atk", func(): main.do_research("upgrade_atk")))
	row.add_child(_portrait_build_button("ARM", "upgrade_armor", func(): main.do_research("upgrade_armor")))
	row.add_child(_portrait_build_button("ECO", "upgrade_eco", func(): main.do_research("upgrade_eco")))

func _ctrl_button(text: String, icon_key: String, action: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text if icon_key == "speed" or icon_key == "zoom" else ""
	b.add_theme_font_override("font", f_ui)
	b.add_theme_font_size_override("font_size", 9)
	b.add_theme_color_override("font_color", Game.COL_BONE)
	b.add_theme_color_override("font_hover_color", Game.COL_ACCENT_BRIGHT)
	b.custom_minimum_size = Vector2(44, 34)
	_apply_control_icon(b, icon_key)
	var sb := _texture_style(UI_RD_BUTTON, 12.0, 5.0, Color(0.9, 0.94, 1.0, 1.0))
	var hov := _texture_style(UI_RD_BUTTON_HOVER, 12.0, 5.0, Color(1.08, 1.08, 1.08, 1.0))
	var prs := _texture_style(UI_RD_BUTTON, 12.0, 5.0, Color(0.68, 0.72, 0.82, 1.0))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", prs)
	b.tooltip_text = tip if tip != "" else text.capitalize()
	b.pressed.connect(action)
	_ctrl_buttons.append(b)
	return b

func _build_control_bar() -> void:
	var bar := HFlowContainer.new()
	control_bar = bar
	bar.add_theme_constant_override("separation", 6)
	bar.add_theme_constant_override("v_separation", 5)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 268
	bar.offset_right = -10
	bar.offset_top = -104
	bar.offset_bottom = -68
	add_child(bar)

	btn_power = _ctrl_button("PWR", "power", func(): main.cmd_power(), "Power: heal all units")
	bar.add_child(btn_power)
	bar.add_child(_ctrl_button("ALL", "army", func(): main.cmd_select_army(), "Select combat units"))
	bar.add_child(_ctrl_button("DEF", "defend", func(): main.cmd_defend_base(), "Defend base"))
	bar.add_child(_ctrl_button("VIL", "workers", func(): main.cmd_select_villagers(), "Select villagers"))
	bar.add_child(_ctrl_button("GTH", "gather", func(): main.cmd_gather(), "Gather nearest resources"))
	bar.add_child(_ctrl_button("ATK", "attack", func(): main.cmd_attack_move(), "Attack move"))
	bar.add_child(_ctrl_button("HLD", "hold", func(): main.cmd_hold(), "Hold position"))
	bar.add_child(_ctrl_button("RLY", "rally", func(): main.cmd_rally(), "Set rally point"))
	btn_pause = _ctrl_button("PAUS", "pause", func(): main.cmd_pause(), "Pause or resume")
	bar.add_child(btn_pause)
	btn_speed = _ctrl_button("1X", "speed", func(): main.cmd_speed(), "Cycle game speed")
	bar.add_child(btn_speed)
	bar.add_child(_ctrl_button("Z-", "zoom", func(): main.cmd_zoom_out(), "Zoom out"))
	btn_zoom = _ctrl_button("100", "zoom", func(): main.cmd_zoom_reset(), "Reset zoom")
	bar.add_child(btn_zoom)
	bar.add_child(_ctrl_button("Z+", "zoom", func(): main.cmd_zoom_in(), "Zoom in"))
	bar.add_child(_ctrl_button("GG", "concede", func(): main.cmd_concede(), "Concede match"))

func _process(_delta: float) -> void:
	if main == null or not is_instance_valid(main):
		return
	_refresh_queue_summary()
	if main.threat:
		lbl_threat.text = "UNDER ATTACK"
		lbl_threat.add_theme_color_override("font_color", Color("ff8a6a"))
	else:
		lbl_threat.text = "BASE CLEAR"
		lbl_threat.add_theme_color_override("font_color", Game.COL_BONE)
	if main.build_mode != "":
		lbl_mode.text = "PLACING %s" % String(main.build_mode).to_upper()
		lbl_mode.add_theme_color_override("font_color", Color("ffd15c"))
	elif main.rally_set:
		lbl_mode.text = "RALLY TARGET"
		lbl_mode.add_theme_color_override("font_color", Color("ffd15c"))
	else:
		lbl_mode.text = "READY"
		lbl_mode.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	_refresh_selection_summary()
	_refresh_tech_summary()
	_refresh_control_groups()
	if main.power_cd > 0.0:
		btn_power.text = "PWR %ds" % int(ceil(main.power_cd))
		btn_power.disabled = true
	else:
		btn_power.text = "PWR"
		btn_power.disabled = false
	btn_pause.text = ""
	btn_speed.text = "%dX" % int(Engine.time_scale)
	if btn_zoom and main.has_method("hud_zoom_label"):
		btn_zoom.text = main.hud_zoom_label()
	for o in obj_rows:
		var done: bool = o["pred"].call()
		o["label"].text = ("[X] " if done else "[ ] ") + o["text"]
		o["label"].add_theme_color_override("font_color", Color("43c865") if done else Game.COL_MUTED)

func _portrait(king: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/portraits/king_portrait_%s.png" % king)
	t.custom_minimum_size = Vector2(32, 32)
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

func _name_label(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", f_ui)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _build_matchup() -> void:
	var holder := CenterContainer.new()
	matchup_holder = holder
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 42
	holder.offset_bottom = 86
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel())
	holder.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var pk: Dictionary = Game.KINGS[Game.player_king]
	var rk: Dictionary = Game.KINGS[Game.rival_king]
	row.add_child(_portrait(Game.player_king))
	row.add_child(_name_label(pk["name"], pk["color"]))
	var vs := Label.new()
	vs.text = "VS"
	vs.add_theme_font_override("font", f_display)
	vs.add_theme_font_size_override("font_size", 11)
	vs.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(vs)
	row.add_child(_name_label(rk["name"], rk["color"]))
	row.add_child(_portrait(Game.rival_king))

func _build_objectives_panel() -> void:
	var panel := PanelContainer.new()
	objectives_panel = panel
	panel.add_theme_stylebox_override("panel", _panel())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 10
	panel.offset_right = 230
	panel.offset_top = 96
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_section_label("OBJECTIVES"))
	var defs := [
		["Reach 400 food", func(): return main.hud_food() >= 400],
		["Field 6 units", func(): return main.hud_pop() >= 6],
		["Build a Forge", func(): return main.hud_has_forge()],
		["Survive wave 3", func(): return Game.wave >= 3],
		["Crush enemy keep", func(): return main.hud_enemy_keep_destroyed()],
	]
	for d in defs:
		var l := Label.new()
		l.add_theme_font_override("font", f_ui)
		l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", Game.COL_MUTED)
		vb.add_child(l)
		obj_rows.append({"label": l, "text": d[0], "pred": d[1]})

func _build_log_panel() -> void:
	var panel := PanelContainer.new()
	log_panel = panel
	panel.add_theme_stylebox_override("panel", _panel())
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 10
	panel.offset_right = 230
	panel.offset_top = 246
	panel.offset_bottom = 438
	add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	vb.add_child(_section_label("BATTLE LOG"))
	log_label = Label.new()
	log_label.add_theme_font_override("font", f_read)
	log_label.add_theme_font_size_override("font_size", 15)
	log_label.add_theme_color_override("font_color", Game.COL_MUTED)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.custom_minimum_size = Vector2(210, 140)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	vb.add_child(log_label)

func _on_log(_t: String) -> void:
	var n := Game.log_lines.size()
	var start := maxi(0, n - 9)
	log_label.text = "\n".join(Game.log_lines.slice(start, n))

func _build_minimap() -> void:
	var frame := PanelContainer.new()
	minimap_frame = frame
	frame.add_theme_stylebox_override("panel", _panel())
	frame.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	frame.offset_left = 10
	frame.offset_right = 258
	frame.offset_top = -230
	frame.offset_bottom = -8
	add_child(frame)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	frame.add_child(vb)
	vb.add_child(_section_label("MINIMAP"))
	var mm := preload("res://scripts/MiniMap.gd").new()
	mm.main = main
	minimap_view = mm
	mm.custom_minimum_size = Vector2(228, 156)
	vb.add_child(mm)

func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var display := _display_size()
	var portrait := display.y > display.x * 1.15
	var compact := portrait or vp.x < 1180.0 or vp.y < 680.0
	var tiny := portrait or vp.x < 980.0 or vp.y < 560.0
	var edge := 8.0 if compact else 10.0
	var gap := 10.0 if compact else 12.0
	var map_w := 248.0
	var map_h := 222.0
	if compact:
		map_w = 220.0
		map_h = 198.0
	if portrait:
		map_w = 132.0
		map_h = 126.0
	var left_lane := edge + map_w + gap
	var side_w := 176.0 if compact else 198.0
	var bottom_right := -edge
	if not portrait:
		bottom_right = -edge - side_w - gap
	var ctrl_w := 40.0 if compact else 44.0
	var cmd_w := 104.0 if compact else 120.0
	if portrait:
		ctrl_w = 38.0
		cmd_w = 90.0
	var bottom_scale := Vector2.ONE

	if is_instance_valid(topbar):
		topbar.scale = Vector2.ONE
		topbar.offset_left = edge
		topbar.offset_top = edge
		topbar.offset_right = -edge

	if is_instance_valid(matchup_holder):
		matchup_holder.scale = Vector2.ONE
		matchup_holder.offset_top = 82.0 if portrait else 96.0 if compact else 88.0
		matchup_holder.offset_bottom = 126.0 if portrait else 140.0 if compact else 132.0

	if is_instance_valid(side_panel):
		side_panel.visible = not portrait
		side_panel.scale = Vector2.ONE
		side_panel.offset_left = -side_w
		side_panel.offset_right = -edge
		side_panel.offset_top = 132.0 if compact else 126.0
		for b in _side_buttons:
			b.custom_minimum_size = Vector2(side_w - 24.0, 34.0 if compact else 36.0)

	if is_instance_valid(portrait_build_frame):
		portrait_build_frame.visible = portrait
		portrait_build_frame.scale = Vector2.ONE
		portrait_build_frame.offset_left = left_lane
		portrait_build_frame.offset_right = -edge
		portrait_build_frame.offset_top = -172.0
		portrait_build_frame.offset_bottom = -128.0
		if is_instance_valid(portrait_build_row):
			portrait_build_row.add_theme_constant_override("separation", 4)
			portrait_build_row.add_theme_constant_override("v_separation", 4)
		for b in _portrait_build_buttons:
			b.custom_minimum_size = Vector2(62.0, 28.0)

	if is_instance_valid(minimap_frame):
		minimap_frame.scale = Vector2.ONE
		minimap_frame.offset_left = edge
		minimap_frame.offset_right = edge + map_w
		minimap_frame.offset_top = -map_h - (18.0 if portrait else 10.0 if compact else 0.0)
		minimap_frame.offset_bottom = -edge - (10.0 if portrait else 0.0)
	if is_instance_valid(minimap_view):
		minimap_view.custom_minimum_size = Vector2(map_w - 20.0, map_h - 58.0)

	if is_instance_valid(control_bar):
		control_bar.scale = bottom_scale
		control_bar.offset_left = left_lane
		control_bar.offset_right = bottom_right
		control_bar.offset_top = -250.0 if portrait else -244.0 if compact else -250.0
		control_bar.offset_bottom = -174.0 if portrait else -170.0 if compact else -172.0
		control_bar.add_theme_constant_override("separation", 3 if compact else 4)
		control_bar.add_theme_constant_override("v_separation", 3 if compact else 4)
		for b in _ctrl_buttons:
			b.custom_minimum_size = Vector2(ctrl_w, 30.0 if portrait else 34.0)

	if is_instance_valid(command_card):
		command_card.scale = bottom_scale
		command_card.offset_left = left_lane
		command_card.offset_right = bottom_right
		command_card.offset_top = -86.0
		command_card.offset_bottom = -edge
		if is_instance_valid(command_status):
			command_status.custom_minimum_size = Vector2(104.0 if portrait else 148.0, 0)
		if is_instance_valid(command_row):
			command_row.add_theme_constant_override("separation", 5 if compact else 8)
			command_row.add_theme_constant_override("v_separation", 5 if compact else 6)
		for b in _cmd_buttons:
			b.custom_minimum_size = Vector2(cmd_w, 44.0 if portrait else 48.0)

	if is_instance_valid(objectives_panel):
		objectives_panel.visible = not tiny
		objectives_panel.offset_left = edge
		objectives_panel.offset_right = edge + (214.0 if compact else 220.0)
		objectives_panel.offset_top = 96.0 if not compact else 102.0

	if is_instance_valid(log_panel):
		log_panel.visible = not tiny
		log_panel.offset_left = edge
		log_panel.offset_right = edge + (220.0 if compact else 220.0)
		log_panel.offset_top = 246.0 if not compact else 250.0
		log_panel.offset_bottom = 438.0 if not compact else 410.0

func _display_size() -> Vector2:
	if OS.has_feature("web"):
		var w = JavaScriptBridge.eval("window.innerWidth || 0", true)
		var h = JavaScriptBridge.eval("window.innerHeight || 0", true)
		var display := Vector2(float(w), float(h))
		if display.x > 0 and display.y > 0:
			return display
	return Vector2(get_window().size)

func _refresh() -> void:
	lbl_food.text = "FOOD %d" % main.hud_food()
	lbl_timber.text = "TIMBER %d" % main.hud_timber()
	lbl_memp.text = "MEMP %d" % main.hud_memp()
	lbl_pop.text = "POP %d/%d" % [main.hud_pop(), main.hud_pop_cap()]
	lbl_kills.text = "KILLS %d" % Game.kills
	lbl_wave.text = "WAVE %d" % Game.wave
	lbl_wager.text = "%s %d NET %d" % ["SOL" if Wallet.verified else "TKT", Game.wager_stake, Game.wager_net()]
	_refresh_tech_summary()
	for entry in _cost_buttons:
		var kind: String = entry["kind"]
		var afford: bool = main.hud_can_afford(kind)
		var b: Button = entry["btn"]
		var cost := Game.cost_text(kind)
		b.text = String(entry.get("label", kind.to_upper())) if cost == "" else "%s  %s" % [String(entry.get("label", kind.to_upper())), cost]
		b.disabled = not afford
		b.modulate = Color(1, 1, 1, 1.0) if afford else Color(1, 1, 1, 0.45)

func _on_selection(count: int) -> void:
	lbl_sel.text = "SELECTED %d" % count
	_refresh_selection_summary()

func _refresh_selection_summary() -> void:
	if main == null or not is_instance_valid(main) or not main.has_method("hud_selection_summary"):
		return
	var summary: Dictionary = main.hud_selection_summary()
	var count := int(summary.get("count", 0))
	lbl_sel.text = "SELECTED %d" % count
	lbl_sel_comp.text = String(summary.get("composition", "NO UNITS"))
	if count <= 0:
		lbl_sel_health.text = "HP --  IDLE"
		lbl_sel_health.add_theme_color_override("font_color", Game.COL_MUTED)
		return
	var hp := int(summary.get("avgHp", 0))
	lbl_sel_health.text = "HP %d%%  %s" % [hp, String(summary.get("order", "IDLE"))]
	var hp_col := Color("43c865")
	if hp < 35:
		hp_col = Color("ff665a")
	elif hp < 70:
		hp_col = Color("ffd15c")
	lbl_sel_health.add_theme_color_override("font_color", hp_col)

func _refresh_tech_summary() -> void:
	if main == null or not is_instance_valid(main) or not main.has_method("hud_tech_summary"):
		return
	var summary: Dictionary = main.hud_tech_summary()
	var atk := int(summary.get("atk", 0))
	var armor := int(summary.get("armor", 0))
	var eco := int(summary.get("ecoPct", 100))
	lbl_tech.text = "TECH A+%d R+%d E%d%%" % [atk, armor, eco]
	var active := atk > 0 or armor > 0 or eco > 100 or bool(summary.get("forge", false))
	lbl_tech.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT if active else Game.COL_MUTED)

func _refresh_control_groups() -> void:
	if main == null or not is_instance_valid(main) or not main.has_method("hud_control_group_counts"):
		return
	var counts: Dictionary = main.hud_control_group_counts()
	var parts: Array[String] = []
	var any := false
	for slot in range(1, 6):
		var n := int(counts.get(slot, 0))
		parts.append("%d:%s" % [slot, str(n) if n > 0 else "-"])
		any = any or n > 0
	lbl_groups.text = "GROUPS " + " ".join(parts)
	lbl_groups.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT if any else Game.COL_MUTED)

func _refresh_queue_summary() -> void:
	if main == null or not is_instance_valid(main):
		return
	if not main.has_method("hud_queue_summary"):
		lbl_queue.text = "QUEUE %d" % main.train_queue.size()
		return
	var summary: Dictionary = main.hud_queue_summary()
	var count := int(summary.get("count", 0))
	var name := String(summary.get("name", ""))
	var pct := int(summary.get("pct", 0))
	if count <= 0:
		lbl_queue.text = "QUEUE 0"
		lbl_queue.add_theme_color_override("font_color", Game.COL_BONE)
	elif name == "":
		lbl_queue.text = "QUEUE %d" % count
		lbl_queue.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
	else:
		lbl_queue.text = "QUEUE %d %s %d%%" % [count, name, pct]
		lbl_queue.add_theme_color_override("font_color", Game.COL_ACCENT_BRIGHT)
