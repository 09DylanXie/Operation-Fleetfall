class_name MainMenu
extends Control
## Start menu: pick the AI difficulty and a map size, then the skirmish begins. Built in
## code so the scene file stays trivial.
##
## Command-line user args (after "--") skip the menu: --size=small|medium|large,
## --difficulty=easy|medium|hard, --seed=N, --ai-vs-ai or --skip-menu start a match
## straight away.

const BLURBS: Array[String] = [
	"A tight archipelago. The fleets meet within minutes.",
	"The standard battlefield.",
	"Open ocean and many islands. Long campaigns, room to flank.",
]

const DIFFICULTY_BLURBS: Array[String] = [
	"Easy - the enemy commands one ship every 3 seconds and builds slowly.",
	"Medium - the enemy commands one ship at a time.",
	"Hard - the enemy commands its whole fleet at once.",
]

## One button per MapConfig.Size, in enum order. Pressing one starts the match.
var size_buttons: Array[Button] = []
## One toggle per GameSettings.Difficulty, in enum order.
var difficulty_buttons: Array[Button] = []
var _difficulty_label: Label = null
var _starting: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var first_time: bool = not GameSettings.menu_shown
	GameSettings.menu_shown = true
	var auto_start: bool = false
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
		if not auto_start:
			# A player opening the game meets Medium first; Hard stays the headless default.
			GameSettings.ai_difficulty = GameSettings.Difficulty.MEDIUM
	_build_ui()
	if auto_start:
		start_match.call_deferred(GameSettings.map_size)


func _make_label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _build_ui() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	column.add_child(_make_label("OPERATION: FLEETFALL", 64, Color(0.92, 0.96, 1.0)))
	column.add_child(_make_label("Naval skirmish - capture islands, build a fleet, sink the enemy Home Base",
		18, Color(0.7, 0.82, 0.92)))
	var gap: Control = Control.new()
	gap.custom_minimum_size = Vector2(0.0, 20.0)
	column.add_child(gap)
	column.add_child(_make_label("AI difficulty", 24, Color(1.0, 0.86, 0.35)))
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
	_difficulty_label = _make_label(DIFFICULTY_BLURBS[int(GameSettings.ai_difficulty)], 15, Color(0.82, 0.88, 0.94))
	column.add_child(_difficulty_label)
	var gap_size: Control = Control.new()
	gap_size.custom_minimum_size = Vector2(0.0, 12.0)
	column.add_child(gap_size)
	column.add_child(_make_label("Choose a map size to start", 24, Color(1.0, 0.86, 0.35)))
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
		button.pressed.connect(start_match.bind(size))
		card.add_child(button)
		size_buttons.append(button)
		var details: Label = _make_label("%d x %d\n%d capturable islands, %d cover islands\n%s" % [
			int(cfg.map_size.x), int(cfg.map_size.y), cfg.capturable_islands(), cfg.cover_per_side * 2,
			BLURBS[int(size)]], 14, Color(0.82, 0.88, 0.94))
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.custom_minimum_size = Vector2(290.0, 0.0)
		card.add_child(details)
	size_buttons[int(GameSettings.map_size)].grab_focus.call_deferred()
	var gap2: Control = Control.new()
	gap2.custom_minimum_size = Vector2(0.0, 20.0)
	column.add_child(gap2)
	var quit_row: CenterContainer = CenterContainer.new()
	column.add_child(quit_row)
	var quit: Button = Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(160.0, 40.0)
	quit.pressed.connect(func() -> void: get_tree().quit())
	quit_row.add_child(quit)


func select_difficulty(level: GameSettings.Difficulty) -> void:
	GameSettings.ai_difficulty = level
	difficulty_buttons[int(level)].button_pressed = true
	if _difficulty_label != null:
		_difficulty_label.text = DIFFICULTY_BLURBS[int(level)]


func start_match(size: MapConfig.Size) -> void:
	if _starting:
		return
	_starting = true
	GameSettings.map_size = size
	get_tree().change_scene_to_file(GameSettings.MATCH_SCENE)


func _draw() -> void:
	# Sea, a few islands and two task forces as a backdrop.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.16, 0.26))
	for i: int in 9:
		var y: float = size.y * (0.08 + 0.11 * float(i))
		draw_line(Vector2(0.0, y), Vector2(size.x, y + 30.0), Color(0.16, 0.34, 0.48, 0.35), 1.5)
	for spot: Vector3 in [Vector3(0.12, 0.2, 70.0), Vector3(0.86, 0.3, 95.0), Vector3(0.2, 0.84, 110.0),
			Vector3(0.78, 0.82, 60.0)]:
		var at: Vector2 = Vector2(size.x * spot.x, size.y * spot.y)
		draw_circle(at, spot.z * 1.5, Color(0.16, 0.42, 0.5, 0.35))
		draw_circle(at, spot.z, Color(0.78, 0.7, 0.5))
		draw_circle(at, spot.z * 0.78, Color(0.24, 0.42, 0.24))
	for team: int in 2:
		var color: Color = Ship.TEAM_COLORS[team]
		for i: int in 4:
			var at: Vector2 = Vector2(size.x * (0.04 + 0.04 * float(i)) if team == 0 else size.x * (0.96 - 0.04 * float(i)),
				size.y * (0.47 + 0.035 * float(i % 2)))
			var bow: float = 1.0 if team == 0 else -1.0
			draw_colored_polygon(PackedVector2Array([at + Vector2(26.0 * bow, 0.0), at + Vector2(10.0 * bow, 7.0),
				at + Vector2(-24.0 * bow, 6.0), at + Vector2(-24.0 * bow, -6.0), at + Vector2(10.0 * bow, -7.0)]),
				Color(color.r * 0.75, color.g * 0.75, color.b * 0.75))
