class_name PlayerController
extends Node
## Mouse/keyboard control for the human player.
##   Left drag ........ box-select ships        Left click ...... select ship / shipyard
##   Right click ...... move, or focus-fire a spotted enemy (submarines: fire torpedoes,
##                      carriers: point the air wing at that ship)
##   Right click on one of your own docks (or its island / base) sends the selection there
##   for repairs. Right click with a shipyard selected sets its rally point.
##   R toggles range rings between "selected ships" and "all my ships".
##   X stop   Ctrl+A select all   H home base   1-9, 0, -, = build (shop order)
##   U upgrade   C cancel last   Esc deselect
## With ships selected the cursor is a downward arrow (move), or a crosshair over an enemy;
## orders show a ripple where they land (OrderFeedback) or a red bracket on the target.

signal selection_changed

const CLICK_THRESHOLD: float = 6.0
const PICK_RADIUS: float = 26.0
const DOCK_PICK_RADIUS: float = 45.0
## Build hotkeys, one per class in GameData.all_classes() order, and their card labels.
const BUILD_KEYS: Array[Key] = [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0,
	KEY_MINUS, KEY_EQUAL]
const BUILD_KEY_LABELS: PackedStringArray = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]

enum CursorMode { DEFAULT, MOVE, ATTACK }

var team: int = 0
var match_ref: Match = null
var input_enabled: bool = true
var selected_ships: Array[Ship] = []
var selected_yard: Shipyard = null
var dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var drag_current: Vector2 = Vector2.ZERO
var cursor_mode: CursorMode = CursorMode.DEFAULT
var _cursors: Dictionary[int, Array] = {}


func setup(p_match: Match, p_team: int) -> void:
	match_ref = p_match
	team = p_team


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return match_ref.get_canvas_transform().affine_inverse() * screen_pos


func world_to_screen(world_pos: Vector2) -> Vector2:
	return match_ref.get_canvas_transform() * world_pos


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or match_ref == null or match_ref.is_over or match_ref.eliminated[team]:
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
			_prune_selection()
			if not selected_ships.is_empty():
				_send({"type": "stop", "ships": match_ref.ship_ids(selected_ships)})
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
			request_cancel()
		_:
			var index: int = BUILD_KEYS.find(key.keycode)
			if index >= 0 and selected_yard != null:
				var classes: Array[ShipStats.ShipClass] = GameData.all_classes()
				if index < classes.size():
					request_build(classes[index])


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
	_update_cursor()


# --- Cursor -------------------------------------------------------------------

## The cursor the player should see now: a crosshair over a spotted enemy and a downward
## arrow over open water while ships are selected; the normal pointer otherwise (and over
## the HUD).
func wanted_cursor(screen_pos: Vector2) -> CursorMode:
	if not input_enabled or match_ref == null or match_ref.is_over or selected_ships.is_empty():
		return CursorMode.DEFAULT
	if match_ref.local_team >= 0 and match_ref.eliminated[team]:
		return CursorMode.DEFAULT
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.gui_get_hovered_control() != null:
		return CursorMode.DEFAULT
	return CursorMode.ATTACK if enemy_at(screen_to_world(screen_pos)) != null else CursorMode.MOVE


func _update_cursor() -> void:
	if DisplayServer.get_name() == "headless" or get_viewport() == null:
		return
	var mode: CursorMode = wanted_cursor(get_viewport().get_mouse_position())
	if mode == cursor_mode:
		return
	cursor_mode = mode
	if mode == CursorMode.DEFAULT:
		Input.set_custom_mouse_cursor(null)
		return
	if not _cursors.has(int(mode)):
		_cursors[int(mode)] = OrderFeedback.make_attack_cursor() if mode == CursorMode.ATTACK 			else OrderFeedback.make_move_cursor()
	var cursor: Array = _cursors[int(mode)]
	Input.set_custom_mouse_cursor(cursor[0], Input.CURSOR_ARROW, cursor[1])


func _exit_tree() -> void:
	if cursor_mode != CursorMode.DEFAULT:
		Input.set_custom_mouse_cursor(null)
		cursor_mode = CursorMode.DEFAULT


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
		if fort.is_alive() and fort.is_enemy_of(team) and fort.position.distance_to(world_pos) <= fort.hit_radius():
			return fort
	return null


## The player's own yard whose dock, island or base is under the cursor.
func own_dock_at(world_pos: Vector2) -> Shipyard:
	for yard: Shipyard in match_ref.yards_of(team):
		if yard.slip_position.distance_to(world_pos) <= DOCK_PICK_RADIUS \
				or yard.site_position.distance_to(world_pos) <= yard.site_radius + 10.0:
			return yard
	return null


## Every order goes to the Match as a command (and from a LAN client on to the host).
## Shows the notice that comes back, if any, and returns it.
func _send(cmd: Dictionary) -> String:
	var note: String = match_ref.command(cmd)
	if note != "" and match_ref.hud != null:
		match_ref.hud.notify(note)
	return note


func order_dock(yard: Shipyard) -> void:
	_prune_selection()
	if yard == null or yard.team != team or selected_ships.is_empty():
		return
	_send({"type": "dock", "ships": match_ref.ship_ids(selected_ships), "yard": match_ref.yards.find(yard)})


func issue_order_at(world_pos: Vector2) -> void:
	_prune_selection()
	if selected_ships.is_empty():
		if selected_yard != null:
			if _send({"type": "rally", "yard": match_ref.yards.find(selected_yard), "x": world_pos.x, "y": world_pos.y}) == "":
				_feedback_ping(world_pos, OrderFeedback.RALLY_COLOR)
		return
	var ids: Array[int] = match_ref.ship_ids(selected_ships)
	var target: Combatant = enemy_at(world_pos)
	if target != null:
		_send({"type": "attack", "ships": ids, "target": match_ref.combatant_ref(target)})
		if match_ref.order_feedback != null:
			match_ref.order_feedback.lock_on(target)
		return
	var dock: Shipyard = own_dock_at(world_pos)
	if dock != null:
		order_dock(dock)
		_feedback_ping(dock.dock_point(), OrderFeedback.MOVE_COLOR)
		return
	if _send({"type": "move", "ships": ids, "x": world_pos.x, "y": world_pos.y}) == "":
		_feedback_ping(world_pos, OrderFeedback.MOVE_COLOR)


func _feedback_ping(at: Vector2, color: Color) -> void:
	if match_ref.order_feedback != null:
		match_ref.order_feedback.ping(at, color)


## True if the order was accepted (on a LAN client: sent - the host answers with a notice
## if it refuses).
func request_build(ship_class: ShipStats.ShipClass) -> bool:
	if selected_yard == null:
		return false
	return _send({"type": "build", "yard": match_ref.yards.find(selected_yard), "cls": int(ship_class)}) == ""


func request_upgrade() -> bool:
	if selected_yard == null:
		return false
	return _send({"type": "upgrade", "yard": match_ref.yards.find(selected_yard)}) == ""


func request_cancel() -> void:
	if selected_yard != null:
		_send({"type": "cancel", "yard": match_ref.yards.find(selected_yard)})


## Buys radar for the selected island (a Major island with a Tier 3 shipyard).
func request_radar() -> void:
	if selected_yard != null:
		_send({"type": "radar", "yard": match_ref.yards.find(selected_yard)})
