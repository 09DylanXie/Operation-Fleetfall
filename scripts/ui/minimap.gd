class_name Minimap
extends Control
## Overview of the whole map. Shows only what the local team may know:
## terrain, node ownership, own ships and currently spotted enemies. Click to move the camera.

var match_ref: Match = null


func setup(p_match: Match) -> void:
	match_ref = p_match
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(_delta: float) -> void:
	queue_redraw()


func _scale() -> Vector2:
	var map_size: Vector2 = match_ref.map_data.size
	return Vector2(size.x / map_size.x, size.y / map_size.y)


func _gui_input(event: InputEvent) -> void:
	if match_ref == null or match_ref.camera == null:
		return
	var pressed: bool = false
	var at: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		at = mb.position
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		pressed = (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		at = mm.position
	if pressed:
		var s: Vector2 = _scale()
		match_ref.camera.position = Vector2(at.x / s.x, at.y / s.y)
		accept_event()


func _draw() -> void:
	if match_ref == null or match_ref.map_data == null:
		return
	var s: Vector2 = _scale()
	var map: MapData = match_ref.map_data
	if map.circular:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.08, 0.95))
		draw_circle(map.center() * s, map.radius() * s.x, Color(0.05, 0.14, 0.22))
		draw_arc(map.center() * s, map.radius() * s.x, 0.0, TAU, 64, Color(0.5, 0.75, 0.9, 0.5), 1.0)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.14, 0.22, 0.95))
	for front: WeatherFront in match_ref.fronts:
		draw_circle(front.position * s, front.radius * s.x, Color(0.8, 0.84, 0.9, 0.18))
	for island: Island in match_ref.islands:
		var color: Color = Color(0.55, 0.52, 0.4)
		if island.is_capturable():
			color = Color(0.8, 0.8, 0.8) if island.owner_team < 0 else Ship.TEAM_COLORS[island.owner_team]
			if island.kind == Island.Kind.MINOR:
				draw_arc(island.position * s, island.shallow_radius * s.x, 0.0, TAU, 20, Color(0.4, 0.75, 0.8, 0.5), 1.0)
		draw_circle(island.position * s, maxf(2.5, island.radius * s.x), color)
	for base: HomeBase in match_ref.bases:
		if base.is_alive():
			var p: Vector2 = base.position * s
			draw_rect(Rect2(p - Vector2(5.0, 5.0), Vector2(10.0, 10.0)), Ship.TEAM_COLORS[base.team])
	for ship: Ship in match_ref.ships:
		if ship.is_alive() and match_ref.is_combatant_visible_to_local(ship):
			draw_circle(ship.position * s, 2.0, Ship.TEAM_COLORS[ship.team])
	if match_ref.camera != null:
		var view: Rect2 = match_ref.camera.view_rect()
		draw_rect(Rect2(view.position * s, view.size * s), Color(1, 1, 1, 0.8), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.6, 0.8, 0.95, 0.7), false, 1.5)
