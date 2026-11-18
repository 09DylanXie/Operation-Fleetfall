class_name OrderFeedback
extends Node2D
## Cosmetic order feedback for the local player, drawn in the world above the fog: an
## impact ripple with a dropping arrow where a move / dock / rally order lands, and a brief
## red lock-on bracket around an enemy ordered attacked. Also builds the order cursors
## (a downward arrow for moving, a crosshair over an enemy). Runs on its own clock and never
## touches the simulation.

const PING_TIME: float = 0.8
const LOCK_TIME: float = 1.2
const MOVE_COLOR: Color = Color(0.5, 1.0, 0.55)
const RALLY_COLOR: Color = Color(1.0, 0.85, 0.35)
const ATTACK_COLOR: Color = Color(1.0, 0.3, 0.25)
const OUTLINE: Color = Color(0.03, 0.07, 0.05, 0.9)
## Cursor images are this many pixels square.
const CURSOR_SIZE: int = 26

## Each ping: [position, colour, age]. Each lock: [target, age].
var _pings: Array[Array] = []
var _locks: Array[Array] = []


func _ready() -> void:
	# Above the fog (z 50), so the player always sees where an order went.
	z_index = 60


## Ripple and dropping arrow at a move / dock / rally point.
func ping(at: Vector2, color: Color = MOVE_COLOR) -> void:
	_pings.append([at, color, 0.0])
	queue_redraw()


## Brief red bracket on an enemy that was just ordered attacked; it follows the target.
func lock_on(target: Combatant) -> void:
	if target == null:
		return
	for lock: Array in _locks:
		if lock[0] == target:
			lock[1] = 0.0
			return
	_locks.append([target, 0.0])
	queue_redraw()


func active_count() -> int:
	return _pings.size() + _locks.size()


func _process(delta: float) -> void:
	if _pings.is_empty() and _locks.is_empty():
		return
	for i: int in range(_pings.size() - 1, -1, -1):
		_pings[i][2] += delta
		if _pings[i][2] >= PING_TIME:
			_pings.remove_at(i)
	for i: int in range(_locks.size() - 1, -1, -1):
		_locks[i][1] += delta
		var target: Combatant = _locks[i][0] as Combatant
		if _locks[i][1] >= LOCK_TIME or not is_instance_valid(target) or not target.is_alive():
			_locks.remove_at(i)
	queue_redraw()


## World units per screen pixel, so markers keep their size at any zoom.
func _px() -> float:
	var zoom: float = get_canvas_transform().get_scale().x
	return 1.0 / maxf(zoom, 0.01)


func _draw() -> void:
	var px: float = _px()
	for p: Array in _pings:
		_draw_ping(p[0], p[1], p[2] / PING_TIME, px)
	for lock: Array in _locks:
		var target: Combatant = lock[0] as Combatant
		if is_instance_valid(target):
			_draw_lock(target, lock[1] / LOCK_TIME, px)


func _draw_ping(at: Vector2, color: Color, k: float, px: float) -> void:
	# Two splash rings spreading out from the impact.
	for ring: int in 2:
		var rk: float = clampf((k - 0.18 * float(ring)) / 0.82, 0.0, 1.0)
		if rk <= 0.0:
			continue
		var r: float = lerpf(3.0, 18.0, 1.0 - pow(1.0 - rk, 3.0)) * px
		var fade: float = 1.0 - rk
		draw_arc(at, r, 0.0, TAU, 32, Color(OUTLINE, 0.5 * fade), 3.5 * px, true)
		draw_arc(at, r, 0.0, TAU, 32, Color(color, 0.95 * fade), 1.8 * px, true)
	# The arrow drops onto the spot, holds a moment, then fades.
	var drop: float = clampf(k / 0.3, 0.0, 1.0)
	var lift: float = (1.0 - drop * drop) * 20.0
	var alpha: float = 1.0 if k < 0.55 else clampf(1.0 - (k - 0.55) / 0.45, 0.0, 1.0)
	var squash: float = 1.0
	if drop >= 1.0 and k < 0.42:
		squash = 1.0 - 0.18 * sin((k - 0.3) / 0.12 * PI)
	var tip: Vector2 = at + Vector2(0.0, -lift * px)
	var shape: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in arrow_shape(15.0):
		shape.append(tip + Vector2(v.x * (2.0 - squash), v.y * squash) * px)
	var rim: PackedVector2Array = shape.duplicate()
	rim.append(shape[0])
	draw_colored_polygon(shape, Color(color, alpha))
	draw_polyline(rim, Color(OUTLINE, alpha), 1.5 * px, true)
	# Bright flash where it lands.
	if k < 0.35:
		draw_circle(at, (2.0 + 3.5 * k) * px, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - k / 0.35)))


func _draw_lock(target: Combatant, k: float, px: float) -> void:
	var at: Vector2 = target.position
	var half: float = target.hit_radius() + 4.0 * px
	# Brackets snap in from wide, then pulse until they fade.
	var snap: float = clampf(k / 0.15, 0.0, 1.0)
	half *= lerpf(1.35, 1.0, 1.0 - pow(1.0 - snap, 3.0))
	var alpha: float = (0.75 + 0.25 * sin(k * TAU * 3.0)) * clampf((1.0 - k) / 0.3, 0.0, 1.0)
	if k < 0.3:
		draw_circle(at, half * 0.8, Color(ATTACK_COLOR, 0.2 * (1.0 - k / 0.3)))
	var arm: float = half * 0.35
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c: Vector2 = at + corner * half
		var pts: PackedVector2Array = PackedVector2Array([c - Vector2(corner.x * arm, 0.0), c,
			c - Vector2(0.0, corner.y * arm)])
		draw_polyline(pts, Color(OUTLINE, alpha * 0.8), 3.5 * px, true)
		draw_polyline(pts, Color(ATTACK_COLOR, alpha), 1.8 * px, true)


## A downward arrow `height` tall with its tip at the origin (pointing +y).
static func arrow_shape(height: float) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in [Vector2(0.0, 0.0), Vector2(-0.5, -0.55), Vector2(-0.19, -0.55), Vector2(-0.19, -1.0),
			Vector2(0.19, -1.0), Vector2(0.19, -0.55), Vector2(0.5, -0.55)]:
		pts.append(v * height)
	return pts


# --- Cursors ------------------------------------------------------------------

## The move cursor (downward arrow) and its hotspot at the arrow's tip.
static func make_move_cursor() -> Array:
	var s: float = float(CURSOR_SIZE)
	var tip: Vector2 = Vector2(s * 0.5, s - 2.5)
	var shape: PackedVector2Array = PackedVector2Array()
	for v: Vector2 in arrow_shape(s - 5.0):
		shape.append(tip + v)
	var tex: ImageTexture = _rasterize(func(p: Vector2) -> float: return _polygon_distance(p, shape), MOVE_COLOR)
	return [tex, tip]


## The attack cursor (crosshair) and its hotspot in the middle.
static func make_attack_cursor() -> Array:
	var s: float = float(CURSOR_SIZE)
	var c: Vector2 = Vector2(s, s) * 0.5
	var r: float = s * 0.3
	var sdf: Callable = func(p: Vector2) -> float:
		var d: float = absf(p.distance_to(c) - r) - 0.9
		for dir: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var a: Vector2 = c + dir * r * 0.45
			var b: Vector2 = c + dir * (s * 0.5 - 2.0)
			d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) - 0.9)
		return minf(d, p.distance_to(c) - 1.2)
	return [_rasterize(sdf, ATTACK_COLOR), c]


## Draws a shape given by its signed distance (pixels, negative inside) with a dark rim.
static func _rasterize(sdf: Callable, fill: Color) -> ImageTexture:
	var image: Image = Image.create_empty(CURSOR_SIZE, CURSOR_SIZE, false, Image.FORMAT_RGBA8)
	for y: int in CURSOR_SIZE:
		for x: int in CURSOR_SIZE:
			var d: float = sdf.call(Vector2(float(x) + 0.5, float(y) + 0.5))
			var body: float = clampf(0.5 - d, 0.0, 1.0)
			var rim: float = clampf(1.8 - d, 0.0, 1.0)
			var color: Color = Color(OUTLINE.r, OUTLINE.g, OUTLINE.b).lerp(fill, body)
			color.a = maxf(body, rim * OUTLINE.a)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _polygon_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best: float = INF
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return -best if Geometry2D.is_point_in_polygon(p, poly) else best
