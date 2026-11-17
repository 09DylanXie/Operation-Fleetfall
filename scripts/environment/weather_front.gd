class_name WeatherFront
extends Node2D
## A roaming cyclone. Ships inside it have their spotting range cut sharply.

var radius: float = 420.0
var speed: float = 24.0
var match_ref: Match = null
var _waypoint: Vector2 = Vector2.ZERO
var _spin: float = 0.0


func setup(p_match: Match, p_position: Vector2, p_radius: float, p_speed: float) -> void:
	match_ref = p_match
	position = p_position
	radius = p_radius
	speed = p_speed
	_pick_waypoint()


func _pick_waypoint() -> void:
	var size: Vector2 = match_ref.map_data.size
	_waypoint = Vector2(match_ref.rng.randf_range(size.x * 0.12, size.x * 0.88),
		match_ref.rng.randf_range(size.y * 0.1, size.y * 0.9))


func contains(point: Vector2) -> bool:
	return position.distance_squared_to(point) <= radius * radius


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over:
		return
	var to_wp: Vector2 = _waypoint - position
	if to_wp.length() < 30.0:
		_pick_waypoint()
		return
	position += to_wp.normalized() * speed * delta


func _process(delta: float) -> void:
	_spin += delta * 0.35
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.62, 0.66, 0.72, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.62, Color(0.55, 0.6, 0.68, 0.16))
	for i: int in 4:
		var start: float = _spin + TAU * float(i) / 4.0
		draw_arc(Vector2.ZERO, radius * (0.35 + 0.16 * float(i)), start, start + 1.9, 24,
			Color(0.9, 0.93, 0.97, 0.3), 3.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(0.85, 0.88, 0.92, 0.35), 2.0)
