class_name WeatherFront
extends Node2D
## A roaming cyclone. Ships inside it have their spotting range cut sharply.

var radius: float = 420.0
var speed: float = 24.0
var match_ref: Match = null
var _waypoint: Vector2 = Vector2.ZERO
var _spin: float = 0.0


func _enter_tree() -> void:
	add_to_group("weather_fronts")


func setup(p_match: Match, p_position: Vector2, p_radius: float, p_speed: float) -> void:
	match_ref = p_match
	position = p_position
	radius = p_radius
	speed = p_speed
	_pick_waypoint()


func _pick_waypoint() -> void:
	if match_ref.map_data.circular:
		_waypoint = match_ref.map_data.random_point(match_ref.rng, 0.82)
		return
	var size: Vector2 = match_ref.map_data.size
	_waypoint = Vector2(match_ref.rng.randf_range(size.x * 0.12, size.x * 0.88),
		match_ref.rng.randf_range(size.y * 0.1, size.y * 0.9))


func contains(point: Vector2) -> bool:
	return position.distance_squared_to(point) <= radius * radius


func _physics_process(delta: float) -> void:
	if match_ref == null or match_ref.is_over or match_ref.replica:
		return
	var to_wp: Vector2 = _waypoint - position
	if to_wp.length() < 30.0:
		_pick_waypoint()
		return
	position += to_wp.normalized() * speed * delta


func _process(delta: float) -> void:
	_spin += delta * 0.35
	_time += delta
	if _flash > 0.0:
		_flash -= delta
	_bolt_cd -= delta
	if _bolt_cd <= 0.0:
		# Lightning at a cosmetic random spot every few seconds.
		_bolt_cd = randf_range(1.5, 4.5)
		_flash = 0.18
		_bolt = _make_bolt(Vector2.from_angle(randf() * TAU) * radius * randf_range(0.2, 0.75))
	queue_redraw()


const CLOUD_DARK: Color = Color(0.2, 0.23, 0.29)
const CLOUD_MID: Color = Color(0.36, 0.4, 0.47)
const CLOUD_LIGHT: Color = Color(0.7, 0.74, 0.8)
const RAIN: Color = Color(0.75, 0.82, 0.92)
const WIND_STREAK: Color = Color(0.92, 0.95, 1.0)
const RAIN_DROPS: int = 100
const WIND_STREAKS: int = 28
const ARMS: int = 3

var _time: float = 0.0
var _flash: float = 0.0
var _bolt_cd: float = 2.0
var _bolt: PackedVector2Array = PackedVector2Array()


func _r(i: int) -> float:
	return float(hash(i * 7919 + 17) & 0xffff) / 65535.0


func _make_bolt(at: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array([at])
	var dir: Vector2 = Vector2.from_angle(randf() * TAU)
	var p: Vector2 = at
	for i: int in 7:
		p += dir.rotated(randf_range(-0.7, 0.7)) * randf_range(14.0, 30.0)
		pts.append(p)
	return pts


## A swirling cyclone: dark spiral cloud bands around a clear eye, driving rain, wind
## streaks racing round the centre and the odd lightning strike.
func _draw() -> void:
	# Overcast shadow over the whole front, darker toward the core.
	draw_circle(Vector2.ZERO, radius, Color(CLOUD_DARK, 0.22))
	draw_circle(Vector2.ZERO, radius * 0.75, Color(CLOUD_DARK, 0.16))
	draw_circle(Vector2.ZERO, radius * 0.45, Color(CLOUD_DARK, 0.14))
	# Spiral cloud arms made of overlapping puffs, turning slowly.
	for arm: int in ARMS:
		var arm_start: float = _spin + TAU * float(arm) / float(ARMS)
		for k: int in 11:
			var f: float = float(k) / 10.0
			var a: float = arm_start + f * 3.2
			var dist: float = radius * (0.16 + 0.8 * f)
			var at: Vector2 = Vector2.from_angle(a) * dist
			var puff: float = radius * (0.14 + 0.06 * sin(_time * 0.7 + float(k + arm * 5)))
			draw_circle(at, puff, Color(CLOUD_MID, 0.3 * (1.0 - f * 0.5)))
			draw_circle(at + Vector2(-puff * 0.25, -puff * 0.25), puff * 0.6, Color(CLOUD_LIGHT, 0.18 * (1.0 - f * 0.6)))
	# The eye: a ring of bright cloud wall around calmer water.
	draw_arc(Vector2.ZERO, radius * 0.13, 0.0, TAU, 40, Color(CLOUD_LIGHT, 0.35), radius * 0.05)
	# Rain: short slanted streaks falling with the wind, each looping on its own clock.
	for i: int in RAIN_DROPS:
		var phase: float = fmod(_time * (1.4 + _r(i) * 0.8) + _r(i + 300), 1.0)
		var a: float = _r(i + 600) * TAU + _spin * 1.5
		var dist: float = radius * sqrt(_r(i + 900)) * 0.95
		if dist < radius * 0.14:
			continue
		var at: Vector2 = Vector2.from_angle(a) * dist
		var wind: Vector2 = Vector2.from_angle(a + PI * 0.5) * 9.0 + Vector2(3.0, 8.0)
		var head: Vector2 = at + wind * phase * 2.0
		draw_line(head, head - wind, Color(RAIN, 0.5 * sin(phase * PI)), 1.0)
	# Wind streaks racing round the centre.
	for i: int in WIND_STREAKS:
		var dist: float = radius * (0.25 + 0.7 * _r(i + 1200))
		var rate: float = (1.4 - dist / radius) * 1.6
		var a: float = _r(i + 1500) * TAU + _time * rate
		var length: float = 0.18 + 0.2 * _r(i + 1800)
		var pts: PackedVector2Array = PackedVector2Array()
		var cols: PackedColorArray = PackedColorArray()
		for s: int in 6:
			var f: float = float(s) / 5.0
			pts.append(Vector2.from_angle(a - length * (1.0 - f)) * (dist - 6.0 * (1.0 - f)))
			cols.append(Color(WIND_STREAK, 0.45 * f))
		draw_polyline_colors(pts, cols, 1.3)
	# Lightning.
	if _flash > 0.0 and _bolt.size() > 1:
		var k: float = _flash / 0.18
		draw_circle(_bolt[0], 60.0, Color(0.85, 0.9, 1.0, 0.18 * k))
		draw_polyline(_bolt, Color(0.75, 0.85, 1.0, 0.6 * k), 4.0)
		draw_polyline(_bolt, Color(1.0, 1.0, 1.0, k), 1.5)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 72, Color(0.8, 0.85, 0.92, 0.3), 2.0)
