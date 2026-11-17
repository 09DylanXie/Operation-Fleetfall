class_name PlayerController
extends Node
## Mouse/keyboard control for the human player.
##   Left drag ........ box-select ships        Left click ...... select ship / shipyard
##   Right click ...... move, or focus-fire a spotted enemy (submarines: fire torpedoes,
##                      carriers: point the air wing at that ship)
##   Right click on one of your own docks (or its island / base) sends the selection there
##   for repairs. Right click with a shipyard selected sets its rally point.
##   R toggles range rings between "selected ships" and "all my ships".
##   X stop   Ctrl+A select all   H home base   1-6 build   U upgrade   C cancel last   Esc deselect

signal selection_changed

const CLICK_THRESHOLD: float = 6.0
const PICK_RADIUS: float = 26.0
const DOCK_PICK_RADIUS: float = 45.0

var team: int = 0
var match_ref: Match = null
var input_enabled: bool = true
var selected_ships: Array[Ship] = []
var selected_yard: Shipyard = null
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_current: Vector2 = Vector2.ZERO


func setup(p_match: Match, p_team: int) -> void:
	match_ref = p_match
	team = p_team


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return match_ref.get_canvas_transform().affine_inverse() * screen_pos


func world_to_screen(world_pos: Vector2) -> Vector2:
	return match_ref.get_canvas_transform() * world_pos


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or match_ref == null or match_ref.is_over:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				drag_start = mb.position
				drag_current = mb.position
			elif dragging:
				dragging = false
				drag_current = mb.position
				if drag_start.distance_to(drag_current) < CLICK_THRESHOLD:
					_click_select(screen_to_world(mb.position), mb.shift_pressed)
				else:
					_box_select(drag_start, drag_current, mb.shift_pressed)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			issue_order_at(screen_to_world(mb.position))
	elif event is InputEventMouseMotion and dragging:
		drag_current = (event as InputEventMouseMotion).position
	elif event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.pressed and not key.echo:
			_handle_key(key)


func _handle_key(key: InputEventKey) -> void:
	match key.keycode:
		KEY_X:
			for ship: Ship in selected_ships:
				ship.order_stop()
		KEY_ESCAPE:
			clear_selection()
		KEY_R:
			match_ref.show_all_ranges = not match_ref.show_all_ranges
		KEY_H:
			select_yard(match_ref.bases[team].shipyard)
			if match_ref.camera != null:
				match_ref.camera.position = match_ref.bases[team].position
		KEY_A:
			if key.ctrl_pressed:
				set_selected_ships(match_ref.ships_of(team))
		KEY_U:
			if selected_yard != null:
				request_upgrade()
		KEY_C:
			if selected_yard != null:
				selected_yard.cancel_last()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if selected_yard != null:
				var classes: Array[ShipStats.ShipClass] = GameData.all_classes()
				request_build(classes[int(key.keycode) - int(KEY_1)])


# --- Selection --------------------------------------------------------------

func _prune_selection() -> void:
	var alive: Array[Ship] = []
	for ship: Ship in selected_ships:
		if ship.is_alive():
			alive.append(ship)
		else:
			ship.selected = false
	if alive.size() != selected_ships.size():
		selected_ships = alive
		selection_changed.emit()
	if selected_yard != null and selected_yard.team != team:
		select_yard(null)


func _process(_delta: float) -> void:
	_prune_selection()


func clear_selection() -> void:
	set_selected_ships([])
	select_yard(null)


func set_selected_ships(list: Array[Ship]) -> void:
	for ship: Ship in selected_ships:
		ship.selected = false
	selected_ships = []
	for ship: Ship in list:
		if ship.is_combat_ready() and ship.team == team and not selected_ships.has(ship):
			ship.selected = true
			selected_ships.append(ship)
	if not selected_ships.is_empty():
		_set_yard_highlight(false)
		selected_yard = null
	selection_changed.emit()


func select_yard(yard: Shipyard) -> void:
	_set_yard_highlight(false)
	selected_yard = yard
	if yard != null:
		for ship: Ship in selected_ships:
			ship.selected = false
		selected_ships = []
	_set_yard_highlight(true)
	selection_changed.emit()


func _set_yard_highlight(value: bool) -> void:
	if selected_yard == null:
		return
	var site: Node = selected_yard.get_parent()
	if site is Island:
		(site as Island).selected = value
	elif site is HomeBase:
		(site as HomeBase).selected = value


func _click_select(world_pos: Vector2, additive: bool) -> void:
	var best: Ship = null
	var best_dist: float = INF
	for ship: Ship in match_ref.ships_of(team):
		var dist: float = ship.position.distance_to(world_pos)
		if dist <= maxf(PICK_RADIUS, ship.hit_radius()) and dist < best_dist:
			best_dist = dist
			best = ship
	if best != null:
		var list: Array[Ship] = []
		if additive:
			list.assign(selected_ships)
		list.append(best)
		set_selected_ships(list)
		return
	for yard: Shipyard in match_ref.yards_of(team):
		if yard.site_position.distance_to(world_pos) <= yard.site_radius + 20.0:
			select_yard(yard)
			return
	if not additive:
		clear_selection()


func _box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	var wa: Vector2 = screen_to_world(a)
	var wb: Vector2 = screen_to_world(b)
	var rect: Rect2 = Rect2(wa, wb - wa).abs()
	var list: Array[Ship] = []
	if additive:
		list.assign(selected_ships)
	for ship: Ship in match_ref.ships_of(team):
		if rect.has_point(ship.position):
			list.append(ship)
	set_selected_ships(list)


# --- Orders -----------------------------------------------------------------

func enemy_at(world_pos: Vector2) -> Combatant:
	var best: Combatant = null
	var best_dist: float = INF
	for enemy: Combatant in match_ref.vision.spotted_enemies(team):
		if not enemy.is_alive():
			continue
		var dist: float = enemy.position.distance_to(world_pos)
		if dist <= maxf(PICK_RADIUS, enemy.hit_radius()) and dist < best_dist:
			best_dist = dist
			best = enemy
	if best != null:
		return best
	# An enemy-held island can be ordered attacked before it is spotted: everyone knows where it is.
	for fort: IslandGarrison in match_ref.garrisons:
		if fort.team == 1 - team and fort.position.distance_to(world_pos) <= fort.hit_radius():
			return fort
	return null


## The player's own yard whose dock, island or base is under the cursor.
func own_dock_at(world_pos: Vector2) -> Shipyard:
	for yard: Shipyard in match_ref.yards_of(team):
		if yard.slip_position.distance_to(world_pos) <= DOCK_PICK_RADIUS \
				or yard.site_position.distance_to(world_pos) <= yard.site_radius + 10.0:
			return yard
	return null


func order_dock(yard: Shipyard) -> void:
	_prune_selection()
	if yard == null or yard.team != team or selected_ships.is_empty():
		return
	match_ref.order_group_dock(selected_ships, yard)
	if match_ref.hud == null:
		return
	# Tell the player up front if some of these ships will not be repaired there.
	var problem: String = ""
	for ship: Ship in selected_ships:
		problem = yard.repair_block_reason(ship)
		if problem != "":
			break
	if problem == "":
		match_ref.hud.notify("Docking at %s for repairs" % yard.site_name)
	else:
		match_ref.hud.notify("Docking at %s - %s" % [yard.site_name, problem])


func issue_order_at(world_pos: Vector2) -> void:
	_prune_selection()
	if selected_ships.is_empty():
		if selected_yard != null:
			selected_yard.rally_point = match_ref.nav.nearest_free(world_pos, false)
		return
	var target: Combatant = enemy_at(world_pos)
	if target != null:
		for ship: Ship in selected_ships:
			if ship.order_attack(target) or match_ref.hud == null:
				continue
			if target.is_home_base() and ship.stats.is_submarine:
				match_ref.hud.notify("Submarines cannot attack the Home Base")
			elif target.is_structure() and ship.stats.is_submarine:
				match_ref.hud.notify("Submarines cannot attack an island garrison")
			elif target.is_submarine() and not ship.stats.can_target_submarines:
				match_ref.hud.notify("%ss cannot target Submarines" % ship.stats.display_name)
		return
	var dock: Shipyard = own_dock_at(world_pos)
	if dock != null:
		order_dock(dock)
		return
	match_ref.order_group_move(selected_ships, world_pos)


func request_build(ship_class: ShipStats.ShipClass) -> bool:
	if selected_yard == null:
		return false
	var reason: String = selected_yard.try_enqueue_ship(ship_class)
	if reason != "" and match_ref.hud != null:
		match_ref.hud.notify(reason)
	return reason == ""


func request_upgrade() -> bool:
	if selected_yard == null:
		return false
	var reason: String = selected_yard.try_enqueue_upgrade()
	if reason != "" and match_ref.hud != null:
		match_ref.hud.notify(reason)
	return reason == ""
