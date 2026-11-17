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
var _notice_label: Label = null
var _notice_time: float = 0.0
var _selection_box: SelectionBox = null
var _end_panel: PanelContainer = null
var _end_label: Label = null
var _minimap: Minimap = null
var _refresh: float = 0.0


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
	_build_ui()
	match_ref.match_ended.connect(_on_match_ended)
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
	add_child(_root)

	_selection_box = SelectionBox.new()
	_selection_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_selection_box)

	# Top resource bar.
	var top: PanelContainer = PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(top)
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 36)
	var inset: Control = Control.new()
	inset.custom_minimum_size = Vector2(4.0, 0.0)
	bar.add_child(inset)
	top.add_child(bar)
	_gold_label = _make_label("Gold")
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	_steel_label = _make_label("Steel")
	_steel_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	_fleet_label = _make_label("Fleet")
	_tick_label = _make_label("Supply")
	_time_label = _make_label("00:00")
	for label: Label in [_gold_label, _steel_label, _fleet_label, _tick_label, _time_label]:
		bar.add_child(label)
	_ranges_toggle = CheckButton.new()
	_ranges_toggle.text = "Ranges: all my ships (R)"
	_ranges_toggle.tooltip_text = "Off: range rings on selected ships only. On: on every ship you own.\nGold = guns, cyan = torpedoes, violet = aircraft. Enemy ranges are never shown."
	_ranges_toggle.focus_mode = Control.FOCUS_NONE
	_ranges_toggle.button_pressed = match_ref.show_all_ranges
	_ranges_toggle.toggled.connect(_on_ranges_toggled)
	bar.add_child(_ranges_toggle)
	var help: Label = _make_label(
		"RMB move/attack/dock  WASD pan  Wheel zoom  H base  X stop", 13)
	help.modulate = Color(1, 1, 1, 0.65)
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help.clip_text = true
	bar.add_child(help)
	if not match_ref.ai_controllers.is_empty():
		var level: GameSettings.Difficulty = match_ref.ai_controllers[0].difficulty
		var ai_label: Label = _make_label("AI: %s" % GameSettings.difficulty_name(level), 13)
		ai_label.modulate = Color(1, 1, 1, 0.8)
		bar.add_child(ai_label)
	_menu_button = Button.new()
	_menu_button.text = "Menu"
	_menu_button.tooltip_text = "Leave this match and go back to the start menu"
	_menu_button.focus_mode = Control.FOCUS_NONE
	_menu_button.pressed.connect(_on_menu_button_pressed)
	bar.add_child(_menu_button)
	var edge: Control = Control.new()
	edge.custom_minimum_size = Vector2(4.0, 0.0)
	bar.add_child(edge)

	# Bottom-left selection / production panel.
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(430.0, 150.0)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(panel)
	# Pinned to the bottom-left corner; grows upward when the build menu is shown.
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = 10.0
	panel.offset_right = 440.0
	panel.offset_top = -160.0
	panel.offset_bottom = -10.0
	var column: VBoxContainer = VBoxContainer.new()
	panel.add_child(column)
	_info_label = _make_label("No selection", 15)
	column.add_child(_info_label)
	_build_box = VBoxContainer.new()
	column.add_child(_build_box)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	_build_box.add_child(grid)
	var index: int = 1
	for cls: ShipStats.ShipClass in GameData.all_classes():
		var stats: ShipStats = GameData.ship(cls)
		var button: Button = Button.new()
		button.text = "%d  %s  %dG / %dS" % [index, stats.code, stats.gold_cost, stats.steel_cost]
		button.tooltip_text = "%s - Tier %d shipyard, %ds build" % [
			stats.display_name, stats.required_shipyard_tier, int(stats.build_time)]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_on_build_pressed.bind(cls))
		grid.add_child(button)
		_build_buttons[int(cls)] = button
		index += 1
	var row: HBoxContainer = HBoxContainer.new()
	_build_box.add_child(row)
	_upgrade_button = Button.new()
	_upgrade_button.focus_mode = Control.FOCUS_NONE
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	row.add_child(_upgrade_button)
	_cancel_button = Button.new()
	_cancel_button.text = "C  Cancel last"
	_cancel_button.focus_mode = Control.FOCUS_NONE
	_cancel_button.pressed.connect(_on_cancel_pressed)
	row.add_child(_cancel_button)
	_queue_label = _make_label("", 14)
	_build_box.add_child(_queue_label)

	# Minimap, bottom-right.
	_minimap = Minimap.new()
	_minimap.setup(match_ref)
	var map_size: Vector2 = match_ref.map_data.size
	var mini_w: float = 300.0
	var mini_h: float = mini_w * map_size.y / map_size.x
	_minimap.custom_minimum_size = Vector2(mini_w, mini_h)
	_root.add_child(_minimap)
	# Pinned to the bottom-right corner with a 10px margin (offsets are relative to the anchors).
	_minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_minimap.offset_left = -mini_w - 10.0
	_minimap.offset_top = -mini_h - 10.0
	_minimap.offset_right = -10.0
	_minimap.offset_bottom = -10.0

	# Notifications.
	_notice_label = _make_label("", 20)
	_notice_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notice_label.position = Vector2(0.0, 60.0)
	_notice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
	_notice_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notice_label)

	# End-of-match overlay.
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_panel.custom_minimum_size = Vector2(420.0, 180.0)
	_end_panel.visible = false
	_root.add_child(_end_panel)
	var end_column: VBoxContainer = VBoxContainer.new()
	end_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_panel.add_child(end_column)
	_end_label = _make_label("", 44)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_column.add_child(_end_label)
	var again: Button = Button.new()
	again.text = "New Match"
	again.pressed.connect(_on_new_match_pressed)
	end_column.add_child(again)
	var to_menu: Button = Button.new()
	to_menu.text = "Main Menu (change map size)"
	to_menu.pressed.connect(_on_main_menu_pressed)
	end_column.add_child(to_menu)


func notify(text: String) -> void:
	if _notice_label == null:
		return
	_notice_label.text = text
	_notice_time = 2.5


func last_notice() -> String:
	return _notice_label.text if _notice_label != null else ""


func _process(delta: float) -> void:
	if match_ref == null:
		return
	if _notice_time > 0.0:
		_notice_time -= delta
		if _notice_time <= 0.0:
			_notice_label.text = ""
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
	_gold_label.text = "Gold %d  (+%d)" % [economy.gold[team], income.x]
	_steel_label.text = "Steel %d  (+%d)" % [economy.steel[team], income.y]
	_fleet_label.text = "Fleet %d / %d" % [match_ref.fleet_count(team), GameData.balance().fleet_cap]
	_tick_label.text = "Supply in %ds" % int(ceil(economy.time_to_tick))
	var seconds: int = int(match_ref.sim_time)
	_time_label.text = "%02d:%02d" % [floori(float(seconds) / 60.0), seconds % 60]
	_ranges_toggle.set_pressed_no_signal(match_ref.show_all_ranges)
	_refresh_selection(team)


func _refresh_selection(team: int) -> void:
	var controller: PlayerController = match_ref.player
	if controller == null or match_ref.local_team < 0:
		_info_label.text = "Spectating  (AI vs AI)"
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
		_info_label.text = "%s - Shipyard Tier %d / %d\nOrders are paid for when they start. Right-click water sets the rally point.\n%s" % [
			yard.site_name, yard.tier, yard.max_tier, dock_line]
		for cls: ShipStats.ShipClass in GameData.all_classes():
			var stats: ShipStats = GameData.ship(cls)
			var button: Button = _build_buttons[int(cls)]
			# Orders are paid for when they start, so an order you cannot afford yet can still be queued.
			button.disabled = not yard.can_build_class(cls)
			button.modulate = Color.WHITE if match_ref.economy.can_afford(
				team, stats.gold_cost, stats.steel_cost) else Color(1.0, 0.8, 0.6)
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
			if order.paid:
				parts.append("%s %d%%" % [order.label(), int(order.progress() * 100.0)])
			elif parts.is_empty():
				parts.append("%s (waiting for %dG / %dS)" % [order.label(), order.gold, order.steel])
			else:
				parts.append(order.label())
		_queue_label.text = "Queue: " + (", ".join(parts) if not parts.is_empty() else "empty")
		return
	var ships: Array[Ship] = controller.selected_ships
	if ships.is_empty():
		_info_label.text = "No selection\nSelect your Home Base (H) to build ships."
	elif ships.size() == 1:
		var ship: Ship = ships[0]
		var lines: PackedStringArray = PackedStringArray()
		lines.append("%s (%s)   HP %d / %d" % [ship.stats.display_name, ship.stats.code, int(ship.hp), int(ship.max_hp)])
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
		if ship.stats.has_depth_charges():
			lines.append("Depth charges (auto, subs within %d): %s" % [int(ship.stats.depth_charge_range),
				"ready" if ship.depth_charge_cooldown() <= 0.0 else "%.1fs" % ship.depth_charge_cooldown()])
		if ship.stats.has_planes():
			lines.append("Squadrons airborne %d / %d   next launch %.0fs" % [
				ship.airborne_squadrons(), ship.stats.max_squadrons, ship.plane_cooldown()])
			if ship.strike_target != null:
				lines.append("Air strike on your target - X hands the air wing back")
			elif ship.air_target() != null:
				lines.append("Air wing engaging on its own - right-click picks its target")
			else:
				lines.append("Air wing launches on its own - right-click picks its target")
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
		_info_label.text = "%d ships selected\n%s" % [ships.size(), "  ".join(parts)]


func _on_build_pressed(ship_class: ShipStats.ShipClass) -> void:
	if match_ref.player != null:
		match_ref.player.request_build(ship_class)


func _on_ranges_toggled(pressed: bool) -> void:
	match_ref.show_all_ranges = pressed


func _on_upgrade_pressed() -> void:
	if match_ref.player != null:
		match_ref.player.request_upgrade()


func _on_cancel_pressed() -> void:
	if match_ref.player != null and match_ref.player.selected_yard != null:
		match_ref.player.selected_yard.cancel_last()


func _on_match_ended(winning_team: int) -> void:
	_end_panel.visible = true
	if match_ref.local_team < 0:
		_end_label.text = "TEAM %d WINS" % (winning_team + 1)
	elif winning_team == match_ref.local_team:
		_end_label.text = "VICTORY"
		_end_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))
	else:
		_end_label.text = "DEFEAT"
		_end_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))


## Same map size again, new random map.
func _on_new_match_pressed() -> void:
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(GameSettings.MENU_SCENE)


## Leaving a running match takes a second click, so a stray one cannot throw the game away.
func _on_menu_button_pressed() -> void:
	if match_ref.is_over or _menu_armed > 0.0:
		_on_main_menu_pressed()
		return
	_menu_armed = 3.0
	_menu_button.text = "Leave match? Click again"
