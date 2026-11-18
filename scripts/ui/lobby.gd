class_name Lobby
extends Control
## LAN lobby: four seats, each a human player, an AI, open or closed, with a team number
## (same team = allies). The host picks the map size and AI difficulty and starts the game;
## joined players may change their own team. Built in code so the scene file stays trivial.

const KIND_LABELS: Array[String] = ["Open", "Closed", "AI"]

var _title: Label = null
var _address_label: Label = null
var _status_label: Label = null
var _rows: VBoxContainer = null
var _size_option: OptionButton = null
var _difficulty_option: OptionButton = null
var _start_button: Button = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	Net.lobby_changed.connect(_refresh)
	Net.status_changed.connect(_on_status)
	_refresh()


func _make_label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_ui() -> void:
	theme = UITheme.build()
	add_child(SeaBackdrop.new())
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760.0, 0.0)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_title = _make_label("LAN GAME", 40, Color(1.0, 0.93, 0.74))
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	_title.add_theme_constant_override("outline_size", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_address_label = _make_label("", 16, Color(0.75, 0.88, 1.0))
	_address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_address_label)
	column.add_child(_make_label("Seats - players on the same team are allies", 20, UITheme.GOLD))
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	var settings: HBoxContainer = HBoxContainer.new()
	settings.add_theme_constant_override("separation", 12)
	column.add_child(settings)
	settings.add_child(_make_label("Map", 18))
	_size_option = OptionButton.new()
	for size: MapConfig.Size in [MapConfig.Size.SMALL, MapConfig.Size.MEDIUM, MapConfig.Size.LARGE]:
		_size_option.add_item(GameSettings.size_name(size), int(size))
	_size_option.item_selected.connect(func(index: int) -> void: Net.set_map_size(index))
	settings.add_child(_size_option)
	settings.add_child(_make_label("   AI difficulty", 18))
	_difficulty_option = OptionButton.new()
	for level: GameSettings.Difficulty in [GameSettings.Difficulty.EASY, GameSettings.Difficulty.MEDIUM,
			GameSettings.Difficulty.HARD]:
		_difficulty_option.add_item(GameSettings.difficulty_name(level), int(level))
	_difficulty_option.item_selected.connect(func(index: int) -> void: Net.set_difficulty(index))
	settings.add_child(_difficulty_option)
	_status_label = _make_label("", 15, Color(1.0, 0.8, 0.45))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	column.add_child(buttons)
	_start_button = Button.new()
	_start_button.text = "Start Game"
	_start_button.custom_minimum_size = Vector2(200.0, 46.0)
	_start_button.theme_type_variation = "AccentButton"
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)
	var leave: Button = Button.new()
	leave.text = "Leave"
	leave.custom_minimum_size = Vector2(140.0, 46.0)
	leave.theme_type_variation = "DangerButton"
	leave.pressed.connect(_on_leave_pressed)
	buttons.add_child(leave)
	UITheme.liven(self)


func _refresh() -> void:
	if not Net.is_online():
		return
	var host: bool = Net.is_host()
	if host:
		var addresses: PackedStringArray = NetSession.lan_addresses()
		_address_label.text = "Others join with: %s   (port %d)" % [
			", ".join(addresses) if not addresses.is_empty() else "this computer's LAN IP", Net.port]
	else:
		_address_label.text = "Waiting for the host to start the game"
	for child: Node in _rows.get_children():
		child.queue_free()
	var me: int = Net.my_peer_id()
	# Sides are numbered among the filled seats when the game starts, so that is the colour
	# each seat will play in.
	var filled: Array[int] = Net.filled_slots()
	for i: int in Net.slots.size():
		_rows.add_child(_make_row(i, Net.slots[i], host, me, filled.find(i)))
	UITheme.liven(_rows)
	_size_option.select(Net.map_size)
	_difficulty_option.select(Net.difficulty)
	_size_option.disabled = not host
	_difficulty_option.disabled = not host
	_start_button.visible = host
	var problem: String = Net.start_problem()
	_start_button.disabled = problem != ""
	if host:
		_status_label.text = problem
	elif Net.slot_of(me) < 0:
		_status_label.text = "Connecting to the host ..."
	else:
		_status_label.text = ""


func _make_row(index: int, slot: Dictionary, host: bool, me: int, side: int) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var swatch: Panel = Panel.new()
	var swatch_style: StyleBoxFlat = UITheme.box(Ship.TEAM_COLORS[side] if side >= 0 else Color(0.4, 0.45, 0.5, 0.5),
		Color(1.0, 1.0, 1.0, 0.5), 1, 9)
	swatch.add_theme_stylebox_override("panel", swatch_style)
	swatch.custom_minimum_size = Vector2(18.0, 18.0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var kind: int = int(slot["kind"])
	var label: Label = _make_label("", 18)
	label.custom_minimum_size = Vector2(300.0, 0.0)
	var mine: bool = kind == NetSession.Slot.HUMAN and int(slot["peer"]) == me
	if kind == NetSession.Slot.HUMAN:
		label.text = "%s%s%s" % [String(slot["name"]), "  (host)" if int(slot["peer"]) == 1 else "",
			"  - you" if mine else ""]
		row.add_child(label)
	elif host:
		var kinds: OptionButton = OptionButton.new()
		for k: int in KIND_LABELS.size():
			kinds.add_item(KIND_LABELS[k], k)
		kinds.select(kind)
		kinds.custom_minimum_size = Vector2(300.0, 0.0)
		kinds.item_selected.connect(func(choice: int) -> void: Net.set_slot_kind(index, choice as NetSession.Slot))
		row.add_child(kinds)
	else:
		label.text = KIND_LABELS[kind] if kind < KIND_LABELS.size() else "?"
		label.modulate = Color(1, 1, 1, 0.6)
		row.add_child(label)
	row.add_child(_make_label("Team", 18))
	var team: OptionButton = OptionButton.new()
	for t: int in Layers.MAX_TEAMS:
		team.add_item(str(t + 1), t + 1)
	team.select(int(slot["team"]) - 1)
	team.disabled = not (host or mine) or kind == NetSession.Slot.OPEN or kind == NetSession.Slot.CLOSED
	team.item_selected.connect(func(choice: int) -> void:
		if mine:
			Net.request_team(choice + 1)
		else:
			Net.set_slot_team(index, choice + 1))
	row.add_child(team)
	return row


func _on_status(text: String) -> void:
	_status_label.text = text


func _on_start_pressed() -> void:
	var problem: String = Net.start_match()
	if problem != "":
		_status_label.text = problem


func _on_leave_pressed() -> void:
	Net.leave()
	get_tree().change_scene_to_file(GameSettings.MENU_SCENE)


## The animated sea behind the lobby is a SeaBackdrop child.
