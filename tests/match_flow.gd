extends Node
## End-to-end flow check on the real game, starting where F5 starts:
## start menu -> pick Medium -> play -> destroy the enemy base -> VICTORY screen -> "New Match"
## -> fresh match -> lose the Home Base -> DEFEAT screen -> "Main Menu" -> pick Small -> small map.
##
## Run:  godot --headless --path . --fixed-fps 60 res://tests/match_flow.tscn
##
## With "-- --size=large" it checks the command-line path instead: the menu is skipped
## once, and going back to the menu afterwards works and its choice wins.

var is_driver: bool = false
var _failures: int = 0


func _ready() -> void:
	if is_driver:
		_drive.call_deferred()
		return
	# Hand over to a driver that lives on the root so it survives scene changes.
	var driver: Node = Node.new()
	driver.set_script(get_script())
	driver.set("is_driver", true)
	driver.name = "MatchFlowDriver"
	get_tree().root.add_child.call_deferred(driver)


func _check(condition: bool, message: String) -> void:
	print("  [%s] %s" % ["ok" if condition else "FAIL", message])
	if not condition:
		_failures += 1


func _frames(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame


func _current_match() -> Match:
	return get_tree().current_scene as Match


func _drive_cmdline() -> void:
	_check(get_tree().change_scene_to_file(GameSettings.MENU_SCENE) == OK, "start menu loads")
	await _frames(5)
	var auto: Match = _current_match()
	_check(auto != null and auto.map_data.size == GameData.map_config_for(MapConfig.Size.LARGE).map_size,
		"--size=large skips the menu and starts a large match")
	if auto != null:
		auto.hud._on_main_menu_pressed()
		await _frames(40)
		var menu: MainMenu = get_tree().current_scene as MainMenu
		_check(menu != null, "Main Menu still opens the menu after a command-line start")
		if menu != null:
			menu.size_buttons[0].pressed.emit()
			await _frames(5)
			var picked: Match = _current_match()
			_check(picked != null and picked.map_data.size == GameData.map_config_for(MapConfig.Size.SMALL).map_size,
				"the menu's choice beats the command line afterwards")
	print("MATCH FLOW " + ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _drive() -> void:
	if OS.get_cmdline_user_args().has("--size=large"):
		await _drive_cmdline()
		return
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	_check(main_scene == GameSettings.MENU_SCENE, "the game starts in the start menu (%s)" % main_scene)
	_check(get_tree().change_scene_to_file(main_scene) == OK, "start menu loads")
	await _frames(5)
	var menu: MainMenu = get_tree().current_scene as MainMenu
	_check(menu != null, "the first scene is the start menu")
	if menu == null:
		get_tree().quit(1)
		return
	_check(menu.size_buttons.size() == 3 and menu.size_buttons[0].text == "Small" and menu.size_buttons[1].text == "Medium"
		and menu.size_buttons[2].text == "Large", "it offers Small, Medium and Large maps")
	_check(menu.difficulty_buttons.size() == 3 and menu.difficulty_buttons[0].text == "Easy"
		and menu.difficulty_buttons[1].text == "Medium" and menu.difficulty_buttons[2].text == "Hard",
		"it offers Easy, Medium and Hard AI")
	_check(menu.difficulty_buttons[1].button_pressed and GameSettings.ai_difficulty == GameSettings.Difficulty.MEDIUM,
		"Medium is preselected")
	menu.difficulty_buttons[0].pressed.emit()
	_check(GameSettings.ai_difficulty == GameSettings.Difficulty.EASY and menu.difficulty_buttons[0].button_pressed
		and not menu.difficulty_buttons[1].button_pressed, "clicking Easy selects it")
	await _frames(30)
	_check(get_tree().current_scene == menu, "nothing starts until a size is chosen")
	menu.size_buttons[1].pressed.emit()
	await _frames(5)
	var first: Match = _current_match()
	_check(first != null, "choosing a size starts a match")
	if first == null:
		get_tree().quit(1)
		return
	var first_id: int = first.get_instance_id()
	var medium: Vector2 = GameData.map_config_for(MapConfig.Size.MEDIUM).map_size
	_check(first.map_data.size == medium, "Medium gives the medium map (%s)" % first.map_data.size)
	_check(first.hud != null and first.player != null and first.fog != null and first.camera != null,
		"HUD, player controller, fog and camera exist")
	_check(first.local_team == 0 and first.ai_controllers.size() == 1, "human (team 0) versus one AI")
	_check(first.ai_controllers.size() == 1 and first.ai_controllers[0].difficulty == GameSettings.Difficulty.EASY,
		"the AI plays at the difficulty chosen in the menu")
	_check(first.islands.size() >= 10 and first.bases.size() == 2, "generated map has islands and two bases")
	await _frames(1200)
	_check(first.sim_time > 19.0, "simulation advanced 20s (sim_time %.1f)" % first.sim_time)
	_check(first.economy.ticks_paid == 1, "first supply tick arrived")
	_check(first.fleet_count(1) > 0, "the AI has started building (%d hulls)" % first.fleet_count(1))
	_check(not first.hud._end_panel.visible, "no end screen while playing")
	first.hud._on_menu_button_pressed()
	await _frames(5)
	_check(_current_match() == first, "one click on Menu does not abandon a running match")

	first.bases[1].kill()
	await _frames(5)
	_check(first.is_over and first.winner == 0, "enemy base destroyed -> match over, player wins")
	_check(first.hud._end_panel.visible and first.hud._end_label.text == "VICTORY", "VICTORY screen shown")
	var frozen: float = first.sim_time
	await _frames(120)
	_check(is_equal_approx(first.sim_time, frozen), "simulation is frozen on the end screen")

	first.hud._on_new_match_pressed()
	await _frames(300)
	var second: Match = _current_match()
	_check(second != null and second.get_instance_id() != first_id, "New Match builds a fresh match")
	if second == null:
		get_tree().quit(1)
		return
	_check(not is_instance_id_valid(first_id), "the previous match was freed")
	_check(not second.is_over and second.winner == -1, "the new match is live")
	_check(second.sim_time > 4.0 and second.sim_time < 6.0, "its clock restarted (sim_time %.1f)" % second.sim_time)
	_check(second.map_data.size == medium, "New Match keeps the chosen map size")
	_check(second.ai_controllers.size() == 1 and second.ai_controllers[0].difficulty == GameSettings.Difficulty.EASY,
		"New Match keeps the chosen difficulty")
	_check(second.bases[0].is_alive() and second.bases[1].is_alive(), "both bases are standing again")
	_check(second.economy.gold[0] == GameData.balance().start_gold, "the bank was reset")
	_check(second.hud != null and not second.hud._end_panel.visible, "new HUD without an end screen")

	second.bases[0].kill()
	await _frames(5)
	_check(second.is_over and second.winner == 1, "losing the Home Base ends the match")
	_check(second.hud._end_label.text == "DEFEAT", "DEFEAT screen shown")

	second.hud._on_main_menu_pressed()
	await _frames(5)
	var menu_again: MainMenu = get_tree().current_scene as MainMenu
	_check(menu_again != null, "Main Menu on the end screen returns to the start menu")
	if menu_again == null:
		get_tree().quit(1)
		return
	_check(menu_again.difficulty_buttons[0].button_pressed, "the menu remembers the chosen difficulty")
	menu_again.size_buttons[0].pressed.emit()
	await _frames(5)
	var small_match: Match = _current_match()
	var small: Vector2 = GameData.map_config_for(MapConfig.Size.SMALL).map_size
	_check(small_match != null and small_match.map_data.size == small, "Small gives the small map")
	if small_match != null:
		await _frames(600)
		_check(small_match.sim_time > 9.0 and small_match.fleet_count(1) > 0, "the small match runs and the AI builds")
		small_match.hud._on_menu_button_pressed()
		small_match.hud._on_menu_button_pressed()
		await _frames(5)
		_check(get_tree().current_scene is MainMenu, "clicking Menu twice leaves a running match")
		var menu_third: MainMenu = get_tree().current_scene as MainMenu
		if menu_third != null:
			menu_third.size_buttons[2].pressed.emit()
			await _frames(5)
			var large_match: Match = _current_match()
			_check(large_match != null and large_match.map_data.size == GameData.map_config_for(MapConfig.Size.LARGE).map_size,
				"Large gives the large map")

	print("MATCH FLOW " + ("PASSED" if _failures == 0 else "FAILED (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
