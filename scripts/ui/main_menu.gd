class_name MainMenu
extends Control
## Start menu: pick the AI difficulty, the number of AI opponents and a map size, then the
## skirmish begins - or host / join a LAN game. Built in code so the scene file stays trivial.
##
## Command-line user args (after "--") skip the menu: --size=small|medium|large,
## --difficulty=easy|medium|hard, --seed=N, --ai-vs-ai or --skip-menu start a match
## straight away; --host opens a LAN lobby and --join=ADDRESS joins one (with --name=NAME
## and --port=N).

const BLURBS: Array[String] = [
	"A tight archipelago. The fleets meet within minutes.",
	"The standard battlefield.",
	"Open ocean and many islands. Long campaigns, room to flank.",
]

const DIFFICULTY_BLURBS: Array[String] = [
	"Easy - the enemy commands one ship every 5 seconds and builds slowly.",
	"Medium - the enemy commands one ship at a time.",
	"Hard - the enemy commands its whole fleet at once.",
]

## One button per MapConfig.Size, in enum order. Pressing one starts the match.
var size_buttons: Array[Button] = []
## One toggle per GameSettings.Difficulty, in enum order.
var difficulty_buttons: Array[Button] = []
## One toggle per number of AI opponents (1 to 3).
var opponent_buttons: Array[Button] = []
var _difficulty_label: Label = null
var _name_edit: LineEdit = null
var _address_edit: LineEdit = null
var _net_status: Label = null
var _lan_list: VBoxContainer = null
var _starting: bool = false
## The title screen shown when the game opens; Start reveals the menu.
var start_screen: Control = null
var _menu_root: Control = null
## The How to Play or Credits page while one is open (MenuPages.build_page), else null.
var page: Control = null
## The music / effects volume panel, shown over the menu by the Sound button.
var sound_overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var first_time: bool = not GameSettings.menu_shown
	GameSettings.menu_shown = true
	var auto_start: bool = false
	var net_action: String = ""
	var join_address: String = ""
	Net.leave()
	if first_time:
		# The command line skips the menu once, at launch.
		for arg: String in OS.get_cmdline_user_args():
			if arg.begins_with("--size="):
				GameSettings.map_size = GameSettings.size_from_name(arg.trim_prefix("--size="))
				auto_start = true
			elif arg.begins_with("--difficulty="):
				GameSettings.ai_difficulty = GameSettings.difficulty_from_name(arg.trim_prefix("--difficulty="))
				auto_start = true
			elif arg == "--ai-vs-ai" or arg == "--skip-menu" or arg.begins_with("--seed="):
				auto_start = true
			elif arg == "--host":
				net_action = "host"
			elif arg.begins_with("--join="):
				net_action = "join"
				join_address = arg.trim_prefix("--join=")
			elif arg.begins_with("--name="):
				Net.player_name = NetSession.clean_name(arg.trim_prefix("--name="), Net.player_name)
			elif arg.begins_with("--port="):
				Net.port = clampi(int(arg.trim_prefix("--port=")), 1024, 65535)
		if not auto_start:
			# A player opening the game meets Medium first; Hard stays the headless default.
			GameSettings.ai_difficulty = GameSettings.Difficulty.MEDIUM
	_build_ui()
	if first_time and not auto_start and net_action == "":
		_build_start_screen()
	if Net.last_error != "":
		_net_status.text = Net.last_error
		Net.last_error = ""
	var browse_problem: String = Net.discovery.start_browsing()
	Net.discovery.games_changed.connect(_refresh_lan_games)
	_refresh_lan_games(browse_problem)
	if net_action == "host":
		host_game.call_deferred()
	elif net_action == "join":
		_address_edit.text = join_address
		join_game.call_deferred()
	elif auto_start:
		start_match.call_deferred(GameSettings.map_size)


func _make_label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_ui() -> void:
	theme = UITheme.build()
	add_child(SeaBackdrop.new())
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_menu_root = center
	var sheet: PanelContainer = PanelContainer.new()
	var card_style: StyleBoxFlat = UITheme.box(Color(0.03, 0.07, 0.12, 0.8), UITheme.BRASS_DIM, 2, 14)
	card_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	card_style.shadow_size = 18
	UITheme.pad(card_style, 34, 18)
	sheet.add_theme_stylebox_override("panel", card_style)
	center.add_child(sheet)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	sheet.add_child(column)
	column.add_child(_make_title())
	column.add_child(_make_label("Naval skirmish - capture islands, build a fleet, sink the enemy Home Base",
		18, Color(0.7, 0.82, 0.92)))
	column.add_child(_make_rule())
	column.add_child(_make_label("AI difficulty", 24, UITheme.GOLD))
	var level_row: HBoxContainer = HBoxContainer.new()
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	level_row.add_theme_constant_override("separation", 12)
	column.add_child(level_row)
	var group: ButtonGroup = ButtonGroup.new()
	for level: GameSettings.Difficulty in [GameSettings.Difficulty.EASY, GameSettings.Difficulty.MEDIUM,
			GameSettings.Difficulty.HARD]:
		var toggle: Button = Button.new()
		toggle.text = GameSettings.difficulty_name(level)
		toggle.toggle_mode = true
		toggle.button_group = group
		toggle.custom_minimum_size = Vector2(150.0, 44.0)
		toggle.add_theme_font_size_override("font_size", 20)
		toggle.button_pressed = level == GameSettings.ai_difficulty
		toggle.pressed.connect(select_difficulty.bind(level))
		level_row.add_child(toggle)
		difficulty_buttons.append(toggle)
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(30.0, 0.0)
	level_row.add_child(spacer)
	level_row.add_child(_make_label("Opponents", 20, Color(1.0, 0.86, 0.35)))
	var opponents: ButtonGroup = ButtonGroup.new()
	for count: int in range(1, Layers.MAX_TEAMS):
		var pick: Button = Button.new()
		pick.text = str(count)
		pick.toggle_mode = true
		pick.button_group = opponents
		pick.custom_minimum_size = Vector2(52.0, 44.0)
		pick.add_theme_font_size_override("font_size", 20)
		pick.tooltip_text = "Number of AI fleets. Every fleet gets its own base round the rim of the sea."
		pick.button_pressed = count == GameSettings.ai_opponents
		pick.pressed.connect(select_opponents.bind(count))
		level_row.add_child(pick)
		opponent_buttons.append(pick)
	_difficulty_label = _make_label(DIFFICULTY_BLURBS[int(GameSettings.ai_difficulty)], 15, Color(0.82, 0.88, 0.94))
	column.add_child(_difficulty_label)
	var gap_size: Control = Control.new()
	gap_size.custom_minimum_size = Vector2(0.0, 12.0)
	column.add_child(gap_size)
	column.add_child(_make_rule())
	column.add_child(_make_label("Choose a map size to start", 24, UITheme.GOLD))
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	column.add_child(row)
	for size: MapConfig.Size in [MapConfig.Size.SMALL, MapConfig.Size.MEDIUM, MapConfig.Size.LARGE]:
		var cfg: MapConfig = GameData.map_config_for(size)
		var card: VBoxContainer = VBoxContainer.new()
		card.add_theme_constant_override("separation", 8)
		row.add_child(card)
		var button: Button = Button.new()
		button.text = GameSettings.size_name(size)
		button.custom_minimum_size = Vector2(290.0, 84.0)
		button.add_theme_font_size_override("font_size", 30)
		button.theme_type_variation = "AccentButton"
		button.tooltip_text = "Start a skirmish on a %s map" % GameSettings.size_name(size).to_lower()
		button.pressed.connect(start_match.bind(size))
		card.add_child(button)
		size_buttons.append(button)
		var details: Label = _make_label("Round sea, %d across for two fleets\n%d capturable islands, %d cover islands\n%s" % [
			int(cfg.size_for(2).x), cfg.capturable_islands(2), cfg.cover_per_side * 2,
			BLURBS[int(size)]], 14, Color(0.82, 0.88, 0.94))
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.custom_minimum_size = Vector2(290.0, 0.0)
		card.add_child(details)
	size_buttons[int(GameSettings.map_size)].grab_focus.call_deferred()
	column.add_child(_make_rule())
	column.add_child(_make_label("LAN multiplayer - up to four players, allies or rivals", 24, UITheme.GOLD))
	var net_row: HBoxContainer = HBoxContainer.new()
	net_row.alignment = BoxContainer.ALIGNMENT_CENTER
	net_row.add_theme_constant_override("separation", 10)
	column.add_child(net_row)
	net_row.add_child(_make_label("Name", 18))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = NetSession.MAX_NAME_LENGTH
	_name_edit.custom_minimum_size = Vector2(170.0, 40.0)
	net_row.add_child(_name_edit)
	var host_button: Button = Button.new()
	host_button.text = "Host LAN Game"
	host_button.custom_minimum_size = Vector2(170.0, 40.0)
	host_button.pressed.connect(host_game)
	net_row.add_child(host_button)
	var gap_net: Control = Control.new()
	gap_net.custom_minimum_size = Vector2(24.0, 0.0)
	net_row.add_child(gap_net)
	_address_edit = LineEdit.new()
	_address_edit.placeholder_text = "Host address, e.g. 192.168.1.20"
	_address_edit.custom_minimum_size = Vector2(250.0, 40.0)
	_address_edit.text_submitted.connect(func(_text: String) -> void: join_game())
	net_row.add_child(_address_edit)
	var join_button: Button = Button.new()
	join_button.text = "Join"
	join_button.custom_minimum_size = Vector2(100.0, 40.0)
	join_button.pressed.connect(join_game)
	net_row.add_child(join_button)
	_net_status = _make_label("", 15, Color(1.0, 0.7, 0.45))
	column.add_child(_net_status)
	column.add_child(_make_label("Games on your network", 18, Color(0.75, 0.88, 1.0)))
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 4)
	column.add_child(_lan_list)
	column.add_child(_make_rule())
	var quit_row: HBoxContainer = _make_info_row()
	column.add_child(quit_row)
	var quit: Button = Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(160.0, 40.0)
	quit.theme_type_variation = "DangerButton"
	quit.pressed.connect(func() -> void: get_tree().quit())
	quit_row.add_child(quit)
	UITheme.liven(self)


## How to Play / Credits / Sound buttons in a centred row.
func _make_info_row() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for entry: Array in [["How to Play", open_guide, "Controls, rules and the fleet roster"],
			["Credits", open_credits, "Who made the game and its music"],
			["Sound", toggle_sound_panel, "Music and effects volume"]]:
		var button: Button = Button.new()
		button.text = String(entry[0])
		button.custom_minimum_size = Vector2(160.0, 40.0)
		button.tooltip_text = String(entry[2])
		button.pressed.connect(entry[1] as Callable)
		row.add_child(button)
	return row


## Title screen: the game's name over the animated sea and a big Start button.
func _build_start_screen() -> void:
	_menu_root.visible = false
	start_screen = CenterContainer.new()
	start_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(start_screen)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	start_screen.add_child(column)
	var title: Control = _make_title()
	var big: Label = title.get_child(0) as Label
	big.add_theme_font_size_override("font_size", 92)
	title.custom_minimum_size = Vector2(1000.0, 120.0)
	column.add_child(title)
	column.add_child(_make_label("A WWII naval strategy game", 24, Color(0.75, 0.86, 0.95)))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 40.0)
	column.add_child(gap)
	var holder: CenterContainer = CenterContainer.new()
	column.add_child(holder)
	var start: Button = Button.new()
	start.text = "START"
	start.theme_type_variation = "AccentButton"
	start.custom_minimum_size = Vector2(320.0, 86.0)
	start.add_theme_font_size_override("font_size", 40)
	start.pressed.connect(press_start)
	holder.add_child(start)
	var glow: Tween = start.create_tween().set_loops()
	glow.tween_property(start, "modulate", Color(1.25, 1.18, 1.0), 0.9).set_trans(Tween.TRANS_SINE)
	glow.tween_property(start, "modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	start.grab_focus.call_deferred()
	column.add_child(_make_info_row())
	var quit_holder: CenterContainer = CenterContainer.new()
	column.add_child(quit_holder)
	var quit: Button = Button.new()
	quit.text = "Quit"
	quit.theme_type_variation = "DangerButton"
	quit.custom_minimum_size = Vector2(160.0, 40.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	quit_holder.add_child(quit)
	column.add_child(_make_label("Press Start or Enter", 14, Color(0.6, 0.7, 0.8)))
	UITheme.liven(start_screen)


## Leaves the title screen for the menu.
func press_start() -> void:
	if start_screen == null:
		return
	var leaving: Control = start_screen
	start_screen = null
	_menu_root.visible = true
	_menu_root.modulate.a = 0.0
	var tween: Tween = create_tween().set_parallel()
	tween.tween_property(leaving, "modulate:a", 0.0, 0.25)
	tween.tween_property(_menu_root, "modulate:a", 1.0, 0.35)
	tween.chain().tween_callback(leaving.queue_free)
	size_buttons[int(GameSettings.map_size)].grab_focus.call_deferred()


## The game's name, with an outline and a slow bob like a ship on the swell.
func _make_title() -> Control:
	var holder: Control = Control.new()
	holder.custom_minimum_size = Vector2(0.0, 86.0)
	var title: Label = _make_label("OPERATION: FLEETFALL", 64, Color(1.0, 0.93, 0.74))
	title.add_theme_color_override("font_outline_color", Color(0.12, 0.07, 0.02))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(title)
	# The label is made while the holder is still 0 wide, so it grows to its text width and
	# keeps that as an offset, pushing the centred title right. Re-fit it once laid out.
	holder.resized.connect(func() -> void:
		title.offset_left = 0.0
		title.offset_right = 0.0)
	var bob: Tween = title.create_tween().set_loops()
	bob.tween_property(title, "position:y", -4.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(title, "position:y", 4.0, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return holder


## A thin brass divider between sections.
func _make_rule() -> Control:
	var rule: ColorRect = ColorRect.new()
	rule.color = Color(UITheme.BRASS.r, UITheme.BRASS.g, UITheme.BRASS.b, 0.35)
	rule.custom_minimum_size = Vector2(0.0, 2.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## Opens the How to Play page.
func open_guide() -> void:
	_open_page("How to Play", MenuPages.guide_bbcode())


## Opens the Credits page.
func open_credits() -> void:
	_open_page("Credits", MenuPages.credits_bbcode())


func _open_page(title: String, bbcode: String) -> void:
	close_page()
	_hide_sound_panel()
	page = MenuPages.build_page(title, bbcode, close_page)
	add_child(page)
	page.modulate.a = 0.0
	page.create_tween().tween_property(page, "modulate:a", 1.0, 0.2)


## Closes the How to Play or Credits page.
func close_page() -> void:
	if page == null:
		return
	page.queue_free()
	page = null
	if start_screen == null and not size_buttons.is_empty():
		size_buttons[int(GameSettings.map_size)].grab_focus.call_deferred()


## Shows or hides the music / effects volume panel.
func toggle_sound_panel() -> void:
	if sound_overlay != null:
		_hide_sound_panel()
		return
	sound_overlay = Control.new()
	sound_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	sound_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.05, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	sound_overlay.add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sound_overlay.add_child(center)
	var panel: SoundPanel = SoundPanel.new()
	panel.closed.connect(_hide_sound_panel)
	center.add_child(panel)
	add_child(sound_overlay)


func _hide_sound_panel() -> void:
	if sound_overlay != null:
		sound_overlay.queue_free()
		sound_overlay = null


func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	if page != null:
		close_page()
		get_viewport().set_input_as_handled()
	elif sound_overlay != null:
		_hide_sound_panel()
		get_viewport().set_input_as_handled()


func select_difficulty(level: GameSettings.Difficulty) -> void:
	GameSettings.ai_difficulty = level
	difficulty_buttons[int(level)].button_pressed = true
	if _difficulty_label != null:
		_difficulty_label.text = DIFFICULTY_BLURBS[int(level)]


func select_opponents(count: int) -> void:
	GameSettings.ai_opponents = clampi(count, 1, Layers.MAX_TEAMS - 1)
	opponent_buttons[GameSettings.ai_opponents - 1].button_pressed = true


func _take_name() -> void:
	if _name_edit != null:
		Net.player_name = NetSession.clean_name(_name_edit.text, "Admiral")


func host_game() -> void:
	_take_name()
	var problem: String = Net.host_game(Net.port)
	if problem != "":
		_net_status.text = problem
		return
	get_tree().change_scene_to_file(NetSession.LOBBY_SCENE)


func _exit_tree() -> void:
	if Net.discovery != null:
		Net.discovery.stop_browsing()
		if Net.discovery.games_changed.is_connected(_refresh_lan_games):
			Net.discovery.games_changed.disconnect(_refresh_lan_games)


## One row per LAN game heard: host name, players, Join.
func _refresh_lan_games(problem: String = "") -> void:
	if _lan_list == null:
		return
	for child: Node in _lan_list.get_children():
		child.queue_free()
	var found: Array[Dictionary] = Net.discovery.games()
	if found.is_empty():
		var text: String = problem if problem != "" else "Looking for games ... (a hosted game shows up here by itself)"
		_lan_list.add_child(_make_label(text, 15, Color(0.7, 0.76, 0.82)))
		return
	for game: Dictionary in found:
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 14)
		var ok: bool = int(game["protocol"]) == NetSession.PROTOCOL
		var seats: int = int(game["seats"])
		var running: bool = bool(game.get("in_match", false))
		var watch: bool = int(game.get("watch", 0)) > 0
		var state: String = "in progress, %d playing" % int(game["players"]) if running else 			"%d playing, %d open seat%s" % [int(game["players"]), seats, "" if seats == 1 else "s"]
		var label: Label = _make_label("%s's game  -  %s%s" % [String(game["name"]), state,
			"" if ok else "  (different version)"], 17)
		label.custom_minimum_size = Vector2(460.0, 0.0)
		row.add_child(label)
		var join: Button = Button.new()
		# A running game, or a full lobby, can still be joined to watch.
		var spectate: bool = running or seats <= 0
		join.text = "Spectate" if spectate else "Join"
		join.custom_minimum_size = Vector2(110.0, 36.0)
		join.disabled = not ok or (spectate and not watch)
		var address: String = String(game["address"])
		var game_port: int = int(game["port"])
		join.pressed.connect(func() -> void:
			_address_edit.text = address
			join_game(game_port))
		row.add_child(join)
		_lan_list.add_child(row)
	UITheme.liven(_lan_list)


func join_game(game_port: int = -1) -> void:
	_take_name()
	var address: String = _address_edit.text.strip_edges()
	if address == "":
		_net_status.text = "Pick a game from the list, or type the host's address (the host's lobby shows it)"
		return
	var problem: String = Net.join_game(address, game_port if game_port > 0 else Net.port)
	if problem != "":
		_net_status.text = problem
		return
	get_tree().change_scene_to_file(NetSession.LOBBY_SCENE)


func start_match(size: MapConfig.Size) -> void:
	if _starting:
		return
	_starting = true
	GameSettings.map_size = size
	get_tree().change_scene_to_file(GameSettings.MATCH_SCENE)


## The animated sea behind the menu is a SeaBackdrop child.
