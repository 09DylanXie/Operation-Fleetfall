class_name HUD
extends CanvasLayer
## Heads-up display: resource bar, selection/shipyard panel, minimap,
## drag-selection box, notifications and the end-of-match screen.
## Built in code so the scene file stays trivial.

const REFRESH_INTERVAL: float = 0.1

var match_ref: Match = null
var _root: Control = null
var _gold_label: Label = null
var _steel_label: Label = null
var _fleet_label: Label = null
var _tick_label: Label = null
var _time_label: Label = null
var _ranges_toggle: CheckButton = null
var _menu_button: Button = null
var _menu_armed: float = 0.0
var _info_label: Label = null
var _queue_label: Label = null
var _build_box: VBoxContainer = null
var _build_buttons: Dictionary[int, Button] = {}
var _upgrade_button: Button = null
var _cancel_button: Button = null
var _radar_button: Button = null
var _notice_label: Label = null
var _notice_time: float = 0.0
var _selection_box: SelectionBox = null
var _end_panel: PanelContainer = null
var _end_label: Label = null
var _again_button: Button = null
var _leave_button: Button = null
## Shown when the local side is knocked out while the match goes on: spectate or leave.
var _defeat_panel: PanelContainer = null
var _defeat_label: Label = null
var _defeat_leave: Button = null
var _minimap: Minimap = null
var _refresh: float = 0.0
var _header_label: Label = null
var _hp_bar: ProgressBar = null
var _hp_text: Label = null
var _queue_bar: ProgressBar = null
## The bottom-left selection / shop panel (refitted to its contents every refresh).
var _panel: PanelContainer = null
var _supply_icon: UITheme.Icon = null
var _gold_chip: Control = null
var _steel_chip: Control = null
var _fleet_chip: Control = null
var _sound_button: Button = null
## Music / effects volume panel, dropped down from the top bar's Sound button.
var sound_panel: SoundPanel = null
var _notice_panel: PanelContainer = null
var _icons_set: bool = false
var _last_gold: int = -1
var _last_steel: int = -1
var _last_fleet: int = -1
var _owners: Dictionary[Island, int] = {}
var _ready_ships: int = -1
var _base_hp: float = -1.0
var _base_alarm: float = 0.0
var _pause_button: Button = null
var _pause_overlay: Control = null
var _miners: Dictionary[Ship, bool] = {}


class SelectionBox extends Control:
	var controller: PlayerController = null

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if controller == null or not controller.dragging:
			return
		var rect: Rect2 = Rect2(controller.drag_start, controller.drag_current - controller.drag_start).abs()
		draw_rect(rect, Color(0.5, 1.0, 0.55, 0.12))
		draw_rect(rect, Color(0.5, 1.0, 0.55, 0.9), false, 1.5)


func setup(p_match: Match) -> void:
	match_ref = p_match
	# The HUD keeps running while the game is paused (single player).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	match_ref.match_ended.connect(_on_match_ended)
	match_ref.team_eliminated.connect(_on_team_eliminated)
	if Net.is_online():
		_again_button.text = "Back to Lobby"
		_again_button.visible = Net.is_host()
		_leave_button.text = "Leave game"
		_menu_button.tooltip_text = "Leave this LAN game and go back to the start menu"
	if match_ref.player != null:
		_selection_box.controller = match_ref.player
	_refresh_all()


func _make_label(text: String, font_size: int = 18) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.build()
	add_child(_root)

	_selection_box = SelectionBox.new()
	_selection_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_selection_box)

	# Top resource bar.
	var top: PanelContainer = PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	var top_style: StyleBoxFlat = UITheme.box(Color(0.03, 0.065, 0.11, 0.94), UITheme.BRASS_DIM, 0, 0)
	top_style.border_width_bottom = 2
	top_style.shadow_color = Color(0.0, 0.0, 0.0, 0.4)
	top_style.shadow_size = 6
	UITheme.pad(top_style, 10, 5)
	top.add_theme_stylebox_override("panel", top_style)
	_root.add_child(top)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	top.add_child(bar)
	_gold_label = _make_label("Gold")
	_gold_label.add_theme_color_override("font_color", UITheme.GOLD)
	_steel_label = _make_label("Steel")
	_steel_label.add_theme_color_override("font_color", UITheme.STEEL_TEXT)
	_fleet_label = _make_label("Fleet")
	_tick_label = _make_label("Supply")
	_tick_label.add_theme_font_size_override("font_size", 15)
	_time_label = _make_label("00:00")
	_supply_icon = UITheme.Icon.new(UITheme.Icon.Shape.CLOCK)
	_gold_chip = _chip(bar, UITheme.Icon.new(UITheme.Icon.Shape.COIN), _gold_label, "Gold: banked (+ per supply tick)")
	_steel_chip = _chip(bar, UITheme.Icon.new(UITheme.Icon.Shape.INGOT), _steel_label, "Steel: banked (+ per supply tick)")
	_fleet_chip = _chip(bar, UITheme.Icon.new(UITheme.Icon.Shape.SHIP), _fleet_label, "Ships afloat and on the slips / fleet cap")
	_chip(bar, _supply_icon, _tick_label, "Gold and Steel arrive every %ds" % int(GameData.balance().tick_interval))
	_chip(bar, null, _time_label, "Match time")
	_ranges_toggle = CheckButton.new()
	_ranges_toggle.text = "Ranges: all my ships (R)"
	_ranges_toggle.tooltip_text = "Off: range rings on selected ships only. On: on every ship you own.\nGold = guns, cyan = torpedoes, violet = aircraft. Enemy ranges are never shown."
	_ranges_toggle.focus_mode = Control.FOCUS_NONE
	_ranges_toggle.button_pressed = match_ref.show_all_ranges
	_ranges_toggle.toggled.connect(_on_ranges_toggled)
	bar.add_child(_ranges_toggle)
	var help: Label = _make_label(
		"RMB move/attack/dock  WASD pan  Scroll/pinch zoom  H base  X stop", 13)
	help.modulate = Color(1, 1, 1, 0.65)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.clip_text = true
	bar.add_child(help)
	if not match_ref.ai_controllers.is_empty():
		var level: GameSettings.Difficulty = match_ref.ai_controllers[0].difficulty
		var ai_label: Label = _make_label("AI: %s" % GameSettings.difficulty_name(level), 13)
		ai_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
		bar.add_child(ai_label)
	_pause_button = Button.new()
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.tooltip_text = "Pause the game (P). Not available in LAN games."
	_pause_button.text = "Pause (P)"
	_pause_button.visible = not Net.is_online()
	_pause_button.pressed.connect(toggle_pause)
	bar.add_child(_pause_button)
	_sound_button = Button.new()
	_sound_button.focus_mode = Control.FOCUS_NONE
	_sound_button.tooltip_text = "Music and effects volume (M mutes everything)"
	_sound_button.pressed.connect(toggle_sound_panel)
	bar.add_child(_sound_button)
	_update_sound_button()
	Sfx.mute_changed.connect(_on_mute_changed)
	_menu_button = Button.new()
	_menu_button.theme_type_variation = "DangerButton"
	_menu_button.text = "Menu"
	_menu_button.tooltip_text = "Leave this match and go back to the start menu"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.pressed.connect(_on_menu_button_pressed)
	bar.add_child(_menu_button)

	# Bottom-left selection / production panel.
	# A wide, low, see-through strip so the battle shows through it.
	var panel: PanelContainer = PanelContainer.new()
	_panel = panel
	panel.custom_minimum_size = Vector2(470.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.55),
		Color(UITheme.BRASS_DIM.r, UITheme.BRASS_DIM.g, UITheme.BRASS_DIM.b, 0.5), 1, 6)
	UITheme.pad(panel_style, 10, 7)
	panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(panel)
	# Pinned to the bottom-left corner; refitted to its contents in _fit_panel().
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 10.0
	panel.offset_right = 480.0
	panel.offset_top = -160.0
	panel.offset_bottom = -10.0
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	_header_label = _make_label("", 19)
	_header_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.62))
	_header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_label.clip_text = true
	header.add_child(_header_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(170.0, 20.0)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_hp_bar)
	_hp_text = _make_label("", 12)
	_hp_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_text.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_hp_text.add_theme_constant_override("outline_size", 3)
	_hp_bar.add_child(_hp_text)
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(UITheme.BRASS.r, UITheme.BRASS.g, UITheme.BRASS.b, 0.3)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	column.add_child(rule)
	_info_label = _make_label("No selection", 15)
	_info_label.add_theme_color_override("font_color", Color(0.86, 0.9, 0.95))
	column.add_child(_info_label)
	_build_box = VBoxContainer.new()
	column.add_child(_build_box)
	_build_box.add_theme_constant_override("separation", 5)
	# Every class in one row of cards, smallest to largest, in hotkey order (1-9, 0, -, =).
	var grid: GridContainer = GridContainer.new()
	grid.columns = GameData.all_classes().size()
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_build_box.add_child(grid)
	var index: int = 0
	for cls: ShipStats.ShipClass in GameData.all_classes():
		var stats: ShipStats = GameData.ship(cls)
		var button: Button = Button.new()
		var hotkey: String = PlayerController.BUILD_KEY_LABELS[index] if index < PlayerController.BUILD_KEY_LABELS.size() else ""
		button.text = "%s  %s\n%dG %dS" % [hotkey, stats.code, stats.gold_cost, stats.steel_cost]
		button.tooltip_text = "%s - Tier %d shipyard, %ds build" % [
			stats.display_name, stats.required_shipyard_tier, int(stats.build_time)]
		button.theme_type_variation = "FlatButton"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(100.0, 64.0)
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_constant_override("icon_max_width", 60)
		button.add_theme_constant_override("h_separation", 2)
		button.expand_icon = false
		# Tier colour as a thin bar along the top of the card.
		var stripe: ColorRect = ColorRect.new()
		stripe.color = UITheme.TIER_COLORS[clampi(stats.required_shipyard_tier - 1, 0, 2)]
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stripe.set_anchors_preset(Control.PRESET_TOP_WIDE)
		stripe.offset_left = 4.0
		stripe.offset_right = -4.0
		stripe.offset_top = 1.0
		stripe.offset_bottom = 3.0
		button.add_child(stripe)
		button.pressed.connect(_on_build_pressed.bind(cls))
		grid.add_child(button)
		_build_buttons[int(cls)] = button
		index += 1
	var row: HBoxContainer = HBoxContainer.new()
	_build_box.add_child(row)
	row.add_theme_constant_override("separation", 6)
	_upgrade_button = Button.new()
	_upgrade_button.theme_type_variation = "FlatAccentButton"
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	row.add_child(_upgrade_button)
	_cancel_button = Button.new()
	_cancel_button.text = "C  Cancel last"
	_cancel_button.theme_type_variation = "FlatDangerButton"
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)
	_radar_button = Button.new()
	_radar_button.theme_type_variation = "FlatButton"
	_radar_button.focus_mode = Control.FOCUS_NONE
	_radar_button.tooltip_text = "Radar gives this island a Destroyer's spotting range"
	_radar_button.pressed.connect(_on_radar_pressed)
	row.add_child(_radar_button)
	# The production queue sits beside the yard buttons, keeping the panel low.
	var queue_column: VBoxContainer = VBoxContainer.new()
	queue_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	queue_column.alignment = BoxContainer.ALIGNMENT_CENTER
	queue_column.add_theme_constant_override("separation", 2)
	row.add_child(queue_column)
	_queue_label = _make_label("", 13)
	_queue_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	_queue_label.clip_text = true
	_queue_label.custom_minimum_size = Vector2(160.0, 0.0)
	queue_column.add_child(_queue_label)
	_queue_bar = ProgressBar.new()
	_queue_bar.show_percentage = false
	_queue_bar.custom_minimum_size = Vector2(0.0, 8.0)
	_queue_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var queue_fill: StyleBoxFlat = UITheme.box(UITheme.BRASS, Color(0, 0, 0, 0), 0, 4)
	_queue_bar.add_theme_stylebox_override("fill", queue_fill)
	queue_column.add_child(_queue_bar)

	# Minimap, bottom-right.
	_minimap = Minimap.new()
	_minimap.setup(match_ref)
	var map_size: Vector2 = match_ref.map_data.size
	var mini_w: float = 300.0 if map_size.x > map_size.y * 1.2 else 230.0
	var mini_h: float = mini_w * map_size.y / map_size.x
	_minimap.custom_minimum_size = Vector2(mini_w, mini_h)
	var frame: Panel = Panel.new()
	var frame_style: StyleBoxFlat = UITheme.box(Color(0.02, 0.05, 0.09, 0.9), UITheme.BRASS_DIM, 2, 6)
	frame_style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	frame_style.shadow_size = 8
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(frame)
	frame.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	frame.offset_left = -mini_w - 15.0
	frame.offset_top = -mini_h - 15.0
	frame.offset_right = -5.0
	frame.offset_bottom = -5.0
	_root.add_child(_minimap)
	# Pinned to the bottom-right corner with a 10px margin (offsets are relative to the anchors).
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -mini_w - 10.0
	_minimap.offset_top = -mini_h - 10.0
	_minimap.offset_right = -10.0
	_minimap.offset_bottom = -10.0

	# Notifications.
	var notice_strip: CenterContainer = CenterContainer.new()
	notice_strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	notice_strip.offset_top = 62.0
	notice_strip.offset_bottom = 110.0
	notice_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(notice_strip)
	_notice_panel = PanelContainer.new()
	var banner: StyleBoxFlat = UITheme.box(Color(0.12, 0.07, 0.02, 0.92), UITheme.BRASS, 2, 8)
	banner.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	banner.shadow_size = 10
	UITheme.pad(banner, 22, 8)
	_notice_panel.add_theme_stylebox_override("panel", banner)
	_notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.visible = false
	notice_strip.add_child(_notice_panel)
	_notice_label = _make_label("", 20)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notice_panel.add_child(_notice_label)

	# End-of-match overlay.
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.custom_minimum_size = Vector2(480.0, 230.0)
	_end_panel.visible = false
	var end_style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.96), UITheme.BRASS, 3, 14)
	end_style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	end_style.shadow_size = 24
	UITheme.pad(end_style, 30, 22)
	_end_panel.add_theme_stylebox_override("panel", end_style)
	_root.add_child(_end_panel)
	var end_column: VBoxContainer = VBoxContainer.new()
	end_column.alignment = BoxContainer.ALIGNMENT_CENTER
	end_column.add_theme_constant_override("separation", 10)
	_end_panel.add_child(end_column)
	_end_label = _make_label("", 56)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_end_label.add_theme_constant_override("outline_size", 12)
	end_column.add_child(_end_label)
	_again_button = Button.new()
	_again_button.text = "New Match"
	_again_button.theme_type_variation = "AccentButton"
	_again_button.custom_minimum_size = Vector2(0.0, 44.0)
	_again_button.pressed.connect(_on_new_match_pressed)
	end_column.add_child(_again_button)
	_leave_button = Button.new()
	_leave_button.text = "Main Menu (change map size)"
	_leave_button.custom_minimum_size = Vector2(0.0, 40.0)
	_leave_button.pressed.connect(_on_main_menu_pressed)
	end_column.add_child(_leave_button)
	_build_defeat_panel()
	_build_pause_overlay()
	sound_panel = SoundPanel.new()
	sound_panel.visible = false
	sound_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sound_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	sound_panel.offset_top = 52.0
	sound_panel.offset_right = -10.0
	sound_panel.closed.connect(func() -> void: sound_panel.visible = false)
	_root.add_child(sound_panel)
	UITheme.liven(_root)


func _build_defeat_panel() -> void:
	_defeat_panel = PanelContainer.new()
	_defeat_panel.name = "DefeatPanel"
	_defeat_panel.set_anchors_preset(Control.PRESET_CENTER)
	_defeat_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_defeat_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_defeat_panel.custom_minimum_size = Vector2(520.0, 240.0)
	_defeat_panel.visible = false
	var style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.96), UITheme.BRASS, 3, 14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 24
	UITheme.pad(style, 30, 22)
	_defeat_panel.add_theme_stylebox_override("panel", style)
	_root.add_child(_defeat_panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	_defeat_panel.add_child(column)
	var title: Label = _make_label("DEFEATED", 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("outline_size", 12)
	column.add_child(title)
	_defeat_label = _make_label("", 17)
	_defeat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_defeat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_defeat_label)
	var spectate: Button = Button.new()
	spectate.name = "Spectate"
	spectate.text = "Spectate"
	spectate.theme_type_variation = "AccentButton"
	spectate.custom_minimum_size = Vector2(0.0, 44.0)
	spectate.pressed.connect(spectate_match)
	column.add_child(spectate)
	_defeat_leave = Button.new()
	_defeat_leave.name = "Leave"
	_defeat_leave.custom_minimum_size = Vector2(0.0, 40.0)
	_defeat_leave.theme_type_variation = "DangerButton"
	_defeat_leave.pressed.connect(_on_main_menu_pressed)
	column.add_child(_defeat_leave)


func defeat_panel_shown() -> bool:
	return _defeat_panel != null and _defeat_panel.visible


## Watch the rest of the match with the fog lifted (after the local side is knocked out).
func spectate_match() -> void:
	_defeat_panel.visible = false
	match_ref.spectator = true
	if match_ref.fog != null:
		match_ref.fog.visible = false
	if match_ref.player != null:
		match_ref.player.clear_selection()
	notify("Spectating - the whole sea is in view")


func _build_pause_overlay() -> void:
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.offset_top = 44.0
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.visible = false
	_root.add_child(_pause_overlay)
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_overlay.add_child(center)
	var card: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.96), UITheme.BRASS, 3, 14)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 24
	UITheme.pad(style, 40, 24)
	card.add_theme_stylebox_override("panel", style)
	center.add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var title: Label = _make_label("PAUSED", 52)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	column.add_child(title)
	var hint: Label = _make_label("The battle is on hold. Press P to carry on.", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	column.add_child(hint)
	var resume: Button = Button.new()
	resume.text = "Resume"
	resume.theme_type_variation = "AccentButton"
	resume.custom_minimum_size = Vector2(240.0, 46.0)
	resume.add_theme_font_size_override("font_size", 20)
	resume.focus_mode = Control.FOCUS_NONE
	resume.pressed.connect(toggle_pause)
	column.add_child(resume)
	var leave: Button = Button.new()
	leave.text = "Main Menu"
	leave.custom_minimum_size = Vector2(240.0, 40.0)
	leave.focus_mode = Control.FOCUS_NONE
	leave.pressed.connect(_on_main_menu_pressed)
	column.add_child(leave)


func is_paused() -> bool:
	return _pause_overlay != null and _pause_overlay.visible


## Single player only: freezes the whole match (the HUD and sound keep running).
func toggle_pause() -> void:
	set_paused(not is_paused())


func set_paused(value: bool) -> void:
	if value and (Net.is_online() or match_ref == null or match_ref.is_over):
		return
	if not is_inside_tree():
		return
	get_tree().paused = value
	_pause_overlay.visible = value
	_pause_button.text = "Resume (P)" if value else "Pause (P)"
	if value:
		_pause_overlay.modulate.a = 0.0
		var tween: Tween = _pause_overlay.create_tween()
		tween.tween_property(_pause_overlay, "modulate:a", 1.0, 0.15)


func _exit_tree() -> void:
	if is_paused():
		get_tree().paused = false
	if Sfx.mute_changed.is_connected(_on_mute_changed):
		Sfx.mute_changed.disconnect(_on_mute_changed)


## A rounded "chip" on the top bar: an icon and a value.
func _chip(bar: HBoxContainer, icon: Control, label: Label, tip: String) -> PanelContainer:
	var chip: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = UITheme.box(Color(0.015, 0.04, 0.075, 0.85), Color(0.24, 0.36, 0.48, 0.8), 1, 12)
	UITheme.pad(style, 10, 2)
	chip.add_theme_stylebox_override("panel", style)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	row.add_child(label)
	bar.add_child(chip)
	return chip


## Mute / unmute everything (M).
func toggle_sound() -> void:
	Sfx.toggle_mute()


## Shows or hides the volume panel (the top bar's Sound button).
func toggle_sound_panel() -> void:
	if sound_panel == null:
		return
	sound_panel.visible = not sound_panel.visible
	if sound_panel.visible:
		sound_panel.refresh()


func _on_mute_changed(_muted: bool) -> void:
	_update_sound_button()
	if sound_panel != null:
		sound_panel.refresh()


func _update_sound_button() -> void:
	_sound_button.text = "Sound: muted (M)" if Sfx.muted else "Sound"


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_M:
		toggle_sound()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_P and not Net.is_online():
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_E and key.shift_pressed:
		toggle_sandbox()
		get_viewport().set_input_as_handled()


## Secret sandbox mode (Shift+E): infinite resources for the local side. In a LAN game it is
## a command like any other: the host toggles it for the sender's side and answers with the notice.
func toggle_sandbox() -> void:
	if match_ref == null or match_ref.is_over or match_ref.local_team < 0:
		return
	var note: String = match_ref.command({"type": "sandbox"})
	if note != "":
		notify(note)
	_refresh_all()


## Build cards show the ship itself once the hull art is baked.
func _set_build_icons() -> void:
	if _icons_set:
		return
	var team: int = maxi(match_ref.local_team, 0)
	for cls: ShipStats.ShipClass in GameData.all_classes():
		var texture: Texture2D = ShipArt.baked.get(ShipArt.sprite_key(cls, ShipArt.SPRITE_BODY, team)) as Texture2D
		if texture == null:
			return
		_build_buttons[int(cls)].icon = texture
	_icons_set = true


func notify(text: String) -> void:
	if _notice_label == null:
		return
	_notice_label.text = text
	_notice_time = 2.5
	_notice_panel.visible = text != ""
	_notice_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_notice_panel.pivot_offset = _notice_panel.size * 0.5
	_notice_panel.scale = Vector2(1.08, 1.08)
	var tween: Tween = _notice_panel.create_tween()
	tween.tween_property(_notice_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func last_notice() -> String:
	return _notice_label.text if _notice_label != null else ""


func _process(delta: float) -> void:
	if match_ref == null:
		return
	if _notice_time > 0.0:
		_notice_time -= delta
		_notice_panel.modulate.a = clampf(_notice_time / 0.5, 0.0, 1.0)
		if _notice_time <= 0.0:
			_notice_label.text = ""
			_notice_panel.visible = false
	_base_alarm = maxf(0.0, _base_alarm - delta)
	if _menu_armed > 0.0:
		_menu_armed -= delta
		if _menu_armed <= 0.0:
			_menu_button.text = "Menu"
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_INTERVAL
		_refresh_all()


func _refresh_all() -> void:
	var team: int = maxi(match_ref.local_team, 0)
	var economy: Economy = match_ref.economy
	var income: Vector2i = economy.income_for(team)
	_gold_label.text = "%d  +%d" % [economy.gold[team], income.x]
	_steel_label.text = "%d  +%d" % [economy.steel[team], income.y]
	if economy.infinite[team]:
		_gold_label.text = "∞"
		_steel_label.text = "∞"
	var fleet: int = match_ref.fleet_count(team)
	var cap: int = match_ref.fleet_cap(team)
	_fleet_label.text = "%d / %d" % [fleet, cap]
	_fleet_label.add_theme_color_override("font_color", UITheme.BAD if fleet >= cap else UITheme.TEXT)
	_tick_label.text = "Supply %ds" % int(ceil(economy.time_to_tick))
	_supply_icon.progress = 1.0 - clampf(economy.time_to_tick / maxf(GameData.balance().tick_interval, 0.1), 0.0, 1.0)
	_supply_icon.queue_redraw()
	_pulse_values(economy.gold[team], economy.steel[team], fleet)
	if not _icons_set:
		_set_build_icons()
	_watch_events(team)
	var seconds: int = int(match_ref.sim_time)
	_time_label.text = "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]
	_ranges_toggle.set_pressed_no_signal(match_ref.show_all_ranges)
	_refresh_selection(team)
	_fit_panel()


## Shrinks or grows the shop panel to its contents, keeping it pinned bottom-left.
func _fit_panel() -> void:
	var fit: Vector2 = _panel.get_combined_minimum_size()
	_panel.offset_right = _panel.offset_left + fit.x
	_panel.offset_top = _panel.offset_bottom - fit.y


## Resource chips flash when their value moves: brighter for a gain.
func _pulse_values(gold: int, steel: int, fleet: int) -> void:
	if _last_gold >= 0:
		if gold != _last_gold:
			UITheme.flash(_gold_chip, Color(1.7, 1.5, 0.9) if gold > _last_gold else Color(1.3, 0.8, 0.8))
		if steel != _last_steel:
			UITheme.flash(_steel_chip, Color(1.3, 1.5, 1.8) if steel > _last_steel else Color(1.3, 0.8, 0.8))
		if fleet != _last_fleet:
			UITheme.flash(_fleet_chip)
	_last_gold = gold
	_last_steel = steel
	_last_fleet = fleet


## Interface sounds for what happens to the local side: islands taken or lost, ships
## launched, the Home Base under fire.
func _watch_events(team: int) -> void:
	if match_ref.local_team < 0 or match_ref.eliminated[team]:
		return
	for island: Island in match_ref.islands:
		var owner: int = island.owner_team
		if _owners.has(island):
			var before: int = _owners[island]
			if owner == team and before != team:
				Sfx.ui("capture")
			elif before == team and owner != team:
				Sfx.ui("alert")
		_owners[island] = owner
	for ship: Ship in match_ref.ships_of(team):
		if not ship.stats.mines_islands:
			continue
		var mine: Island = ship.shown_mining_island()
		if mine != null and not _miners.get(ship, false):
			Sfx.ui("build_done")
			notify("Resource Ship mining %s: +%dG / +%dS per supply tick" % [mine.display_name(),
				GameData.balance().minor_gold, GameData.balance().minor_steel])
		_miners[ship] = mine != null
	for ship: Ship in _miners.keys():
		if not is_instance_valid(ship) or not ship.is_alive():
			_miners.erase(ship)
	var afloat: int = match_ref.ships_of(team).size()
	if _ready_ships >= 0 and afloat > _ready_ships:
		Sfx.ui("build_done")
	_ready_ships = afloat
	if team < match_ref.bases.size() and is_instance_valid(match_ref.bases[team]):
		var hp: float = match_ref.bases[team].hp
		if _base_hp >= 0.0 and hp < _base_hp - 0.5 and _base_alarm <= 0.0:
			_base_alarm = 20.0
			Sfx.ui("alert")
			notify("Your Home Base is under attack!")
		_base_hp = hp


func _refresh_selection(team: int) -> void:
	var controller: PlayerController = match_ref.player
	if controller == null or match_ref.local_team < 0 or match_ref.eliminated[match_ref.local_team]:
		_info_label.text = "Spectating" if match_ref.local_team >= 0 or Net.is_online() else "Spectating  (AI vs AI)"
		_header_label.text = "Observer"
		_hp_bar.visible = false
		_build_box.visible = false
		return
	var yard: Shipyard = controller.selected_yard
	_build_box.visible = yard != null
	if yard != null:
		var dock_line: String = "Dock: no shipyard built - no repairs"
		if yard.tier > 0:
			if yard.is_building():
				dock_line = "Dock: no repairs while the yard is building"
			elif yard.repairing > 0:
				dock_line = "Dock: repairing %d ship%s" % [yard.repairing, "" if yard.repairing == 1 else "s"]
			else:
				dock_line = "Dock: free - repairs ships a Tier %d yard can build" % yard.tier
		var site: Island = yard.get_parent() as Island
		if site != null and site.garrison != null and site.garrison.is_alive():
			dock_line += "\nGarrison %d / %d HP - if it falls, the island and its shipyard are lost" % [
				int(ceil(site.garrison.hp)), int(site.garrison.max_hp)]
			if site.has_air_base():
				dock_line += "\nAir base: %d / %d bomber squadrons up%s" % [site.garrison.airborne_squadrons(),
					GameData.balance().air_base_squadrons, "   Radar: on" if site.has_radar else ""]
		_header_label.text = "%s  -  Shipyard Tier %d / %d" % [yard.site_name, yard.tier, yard.max_tier]
		_hp_bar.visible = site != null and site.garrison != null and site.garrison.is_alive()
		if _hp_bar.visible:
			_show_hp(site.garrison.hp, site.garrison.max_hp)
		elif yard.get_parent() is HomeBase:
			var base: HomeBase = yard.get_parent() as HomeBase
			_hp_bar.visible = true
			_show_hp(base.hp, base.max_hp)
		_info_label.text = "Orders are paid in full when queued and refunded if cancelled. Right-click water sets the rally point.\n%s" % dock_line
		var balance: GameBalance = GameData.balance()
		_radar_button.visible = site != null and site.kind == Island.Kind.MAJOR
		if site != null:
			_radar_button.text = "Radar: built" if site.has_radar else "Radar  %dG / %dS" % [
				balance.radar_gold_cost, balance.radar_steel_cost]
			_radar_button.disabled = site.radar_block_reason(team) != "" or not match_ref.economy.can_afford(
				team, balance.radar_gold_cost, balance.radar_steel_cost)
		for cls: ShipStats.ShipClass in GameData.all_classes():
			var stats: ShipStats = GameData.ship(cls)
			var button: Button = _build_buttons[int(cls)]
			var limit: String = match_ref.class_limit_reason(team, cls)
			var buildable: bool = yard.can_build_class(cls) and limit == ""
			var affordable: bool = match_ref.economy.can_afford(team, stats.gold_cost, stats.steel_cost)
			button.disabled = not buildable or not affordable
			if stats.max_active > 0 or stats.max_per_game > 0:
				_show_class_limit(button, cls, team, limit)
			# Short of money (but the yard could build it): tinted red rather than greyed out.
			button.modulate = Color(1.0, 0.62, 0.58) if buildable and not affordable else Color.WHITE
		if yard.tier < yard.max_tier:
			var cost: Vector2i = yard.upgrade_cost()
			var verb: String = "Build" if yard.tier == 0 else "Upgrade to"
			_upgrade_button.text = "U  %s Tier %d yard  %dG / %dS" % [verb, yard.tier + 1, cost.x, cost.y]
			_upgrade_button.disabled = not yard.can_upgrade()
		else:
			_upgrade_button.text = "Shipyard at max tier"
			_upgrade_button.disabled = true
		_cancel_button.disabled = not yard.can_cancel()
		var parts: PackedStringArray = PackedStringArray()
		for order: Shipyard.BuildOrder in yard.queue:
			if parts.is_empty():
				parts.append("%s %d%%" % [order.label(), int(order.progress() * 100.0)])
			else:
				parts.append(order.label())
		_queue_label.text = "Queue: " + (", ".join(parts) if not parts.is_empty() else "empty")
		_queue_bar.value = yard.queue[0].progress() * 100.0 if not yard.queue.is_empty() else 0.0
		return
	var ships: Array[Ship] = controller.selected_ships
	if ships.is_empty():
		_header_label.text = "No selection"
		_hp_bar.visible = false
		_info_label.text = "Drag or click to select ships.\nSelect your Home Base (H) to build ships."
	elif ships.size() == 1:
		var ship: Ship = ships[0]
		var lines: PackedStringArray = PackedStringArray()
		_header_label.text = "%s  (%s)" % [ship.stats.display_name, ship.stats.code]
		_hp_bar.visible = true
		_show_hp(ship.hp, ship.max_hp)
		lines.append("Armor %d%% (effective %d%%)   Speed %d%%" % [
			int(round(ship.base_armor * 100.0)), int(round(ship.effective_armor() * 100.0)),
			int(round(ship.stats.speed_factor * 100.0))])
		if ship.stats.has_guns():
			lines.append("Guns: reload %.1fs%s" % [ship.gun_cooldown(),
				"" if ship.stats.can_target_submarines else "   (cannot target Submarines)"])
		if ship.stats.torpedo_mode == ShipStats.TorpedoMode.AUTO_BROADSIDE:
			lines.append("Torpedoes (auto, broadside only): %.0fs" % ship.torpedo_cooldown())
		elif ship.stats.torpedo_mode == ShipStats.TorpedoMode.MANUAL_BOW_STERN:
			lines.append("Torpedoes (right-click a ship to fire): %.0fs" % ship.torpedo_cooldown())
			if ship.reveal_timer > 0.0:
				lines.append("REVEALED for %.0fs" % ship.reveal_timer)
		if ship.stats.has_periodic_aa():
			lines.append("Flak (auto): %d%% per squadron within %d every %.0fs   next %s" % [
				int(round(ship.stats.periodic_aa_chance * 100.0)), int(ship.stats.periodic_aa_range),
				ship.stats.periodic_aa_interval,
				"ready" if ship.flak_cooldown() <= 0.0 else "%.1fs" % ship.flak_cooldown()])
		if ship.stats.has_depth_charges():
			lines.append("Depth charges (auto, subs within %d): %s" % [int(ship.stats.depth_charge_range),
				"ready" if ship.depth_charge_cooldown() <= 0.0 else "%.1fs" % ship.depth_charge_cooldown()])
		if ship.stats.has_planes():
			lines.append("Squadrons airborne %d   next: dive %.0fs  torpedo %.0fs  depth %.0fs" % [
				ship.airborne_squadrons(), ship.plane_cooldown(), ship.torpedo_bomber_cooldown(),
				ship.depth_bomber_cooldown()])
			if ship.strike_target != null:
				lines.append("Air strike on your target - X hands the air wing back")
			elif ship.air_target() != null:
				lines.append("Air wing engaging on its own - right-click picks its target")
			else:
				lines.append("Air wing launches on its own - right-click picks its target")
		if ship.stats.mines_islands:
			var mine: Island = ship.shown_mining_island()
			if mine != null:
				lines.append("Mining %s: +%dG / +%dS per supply tick" % [mine.display_name(),
					GameData.balance().minor_gold, GameData.balance().minor_steel])
			elif ship.blocked_mining_island() != null:
				lines.append("Not mining - another of your Resource Ships already mines %s" %
					ship.blocked_mining_island().display_name())
			else:
				lines.append("Not mining - stop next to an island you do not own to mine it")
		elif ship.stats.is_support():
			lines.append("Unarmed - spots surface ships out to %d" % int(ship.stats.spotting_range))
		var dock: Shipyard = match_ref.dock_of(ship)
		if dock != null:
			var reason: String = dock.repair_block_reason(ship)
			if reason != "":
				lines.append("In dock at %s: %s" % [dock.site_name, reason])
			elif ship.hp >= ship.max_hp:
				lines.append("In dock at %s: fully repaired" % dock.site_name)
			else:
				lines.append("In dock at %s: repairing +%d HP/s" % [dock.site_name,
					int(round(ship.max_hp * GameData.balance().repair_rate))])
		elif ship.hp < ship.max_hp:
			lines.append("Damaged - right-click one of your docks to repair")
		_info_label.text = "\n".join(lines)
	else:
		var counts: Dictionary[String, int] = {}
		for ship: Ship in ships:
			counts[ship.stats.code] = counts.get(ship.stats.code, 0) + 1
		var parts: PackedStringArray = PackedStringArray()
		for code: String in counts.keys():
			parts.append("%d %s" % [counts[code], code])
		_header_label.text = "%d ships selected" % ships.size()
		var total: float = 0.0
		var most: float = 0.0
		for ship: Ship in ships:
			total += ship.hp
			most += ship.max_hp
		_hp_bar.visible = true
		_show_hp(total, most)
		_info_label.text = "  ".join(parts)


## Limited classes (SBB, SCV) show how many the side has against the limit on the card,
## and the reason in the tooltip when the limit stops another order.
func _show_class_limit(button: Button, cls: ShipStats.ShipClass, team: int, limit: String) -> void:
	var stats: ShipStats = GameData.ship(cls)
	var index: int = GameData.all_classes().find(cls)
	var hotkey: String = PlayerController.BUILD_KEY_LABELS[index] if index >= 0 and index < PlayerController.BUILD_KEY_LABELS.size() else ""
	var have: int = match_ref.class_count(team, cls).x
	var tag: String = " %d/%d" % [have, stats.max_active] if stats.max_active > 0 else ""
	button.text = "%s  %s%s\n%dG %dS" % [hotkey, stats.code, tag, stats.gold_cost, stats.steel_cost]
	var tip: String = "%s - Tier %d shipyard, %ds build" % [stats.display_name, stats.required_shipyard_tier, int(stats.build_time)]
	if stats.max_active > 0:
		tip += "\nAt most %d at a time" % stats.max_active
	if stats.max_per_game > 0:
		tip += "\n%d per game: %d launched" % [stats.max_per_game, match_ref.launched_count(team, cls)]
	if limit != "":
		tip += "\n" + limit
	button.tooltip_text = tip


## Hit points as a gauge that runs from green through amber to red.
func _show_hp(hp: float, max_hp: float) -> void:
	var share: float = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_bar.value = share * 100.0
	_hp_text.text = "HP %d / %d" % [int(ceil(hp)), int(max_hp)]
	var fill: StyleBoxFlat = _hp_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	if share > 0.5:
		fill.bg_color = UITheme.GOOD.lerp(Color(0.95, 0.8, 0.3), (1.0 - share) * 2.0)
	else:
		fill.bg_color = Color(0.95, 0.8, 0.3).lerp(UITheme.BAD, (0.5 - share) * 2.0)
	_hp_bar.add_theme_stylebox_override("fill", fill)


func _on_build_pressed(ship_class: ShipStats.ShipClass) -> void:
	if match_ref.player != null:
		match_ref.player.request_build(ship_class)


func _on_ranges_toggled(pressed: bool) -> void:
	match_ref.show_all_ranges = pressed


func _on_upgrade_pressed() -> void:
	if match_ref.player != null:
		match_ref.player.request_upgrade()


func _on_cancel_pressed() -> void:
	if match_ref.player != null:
		match_ref.player.request_cancel()


func _on_radar_pressed() -> void:
	if match_ref.player != null:
		match_ref.player.request_radar()


func _on_match_ended(winning_team: int) -> void:
	_defeat_panel.visible = false
	_end_panel.visible = true
	_end_panel.pivot_offset = _end_panel.size * 0.5
	_end_panel.scale = Vector2(0.6, 0.6)
	_end_panel.modulate.a = 0.0
	var tween: Tween = _end_panel.create_tween().set_parallel()
	tween.tween_property(_end_panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_end_panel, "modulate:a", 1.0, 0.3)
	var won: bool = match_ref.local_team >= 0 and match_ref.are_allies(winning_team, match_ref.local_team)
	Sfx.ui("capture" if won else "alert")
	if match_ref.local_team < 0:
		_end_label.text = "%s WINS" % match_ref.side_names[winning_team].to_upper() if winning_team >= 0 else "DRAW"
	elif match_ref.are_allies(winning_team, match_ref.local_team):
		_end_label.text = "VICTORY"
		_end_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.45))
	else:
		_end_label.text = "DEFEAT"
		_end_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


## A side lost its Home Base and the match goes on without it.
func _on_team_eliminated(team: int) -> void:
	var local: int = match_ref.local_team
	if team == local:
		if match_ref.player != null:
			match_ref.player.clear_selection()
		# The match goes on without you: spectate the rest or leave.
		var allies_fight: bool = match_ref.living_alliances().has(match_ref.alliance[local])
		_defeat_label.text = "Your Home Base has fallen. %s
Spectate the rest of the match with the whole sea in view, or leave." % (
			"Your allies fight on." if allies_fight else "The battle goes on without you.")
		if Net.is_online() and Net.is_host():
			_defeat_leave.text = "Leave (ends the game for everyone)"
		else:
			_defeat_leave.text = "Leave game" if Net.is_online() else "Main Menu"
		_defeat_panel.visible = true
	else:
		notify("%s has lost their Home Base" % match_ref.side_names[team])


## Same map size again, new random map (in a LAN game: the host takes everyone back to the lobby).
func _on_new_match_pressed() -> void:
	set_paused(false)
	if Net.is_online():
		Net.return_to_lobby()
		return
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	set_paused(false)
	Net.leave()
	get_tree().change_scene_to_file(GameSettings.MENU_SCENE)


## Leaving a running match takes a second click, so a stray one cannot throw the game away.
func _on_menu_button_pressed() -> void:
	if match_ref.is_over or _menu_armed > 0.0:
		_on_main_menu_pressed()
		return
	_menu_armed = 3.0
	_menu_button.text = "Leave match? Click again"
