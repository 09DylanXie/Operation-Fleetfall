class_name CameraRig
extends Camera2D
## RTS camera: WASD / arrow keys pan, mouse wheel zooms, middle-mouse drag pans.

const PAN_SPEED: float = 1100.0
const ZOOM_MIN: float = 0.72
const ZOOM_MAX: float = 4.6
const ZOOM_STEP: float = 1.12
## Zoom is cosmetic: the world, its distances and speeds never change. The UI is laid out
## for a 1920x1080 (FHD) canvas, which is 1.2x wider than the old 1600x900 one, so every
## zoom value carries that 1.2 factor to show the same slice of sea. On top of that the
## default view is 20% closer than before (1.4 * 1.2 * 1.2); the minimum zoom still shows
## as much of the map as it used to.
const DEFAULT_ZOOM: float = 2.016

var match_ref: Match = null
var _mid_drag: bool = false


func setup(p_match: Match) -> void:
	match_ref = p_match
	var size: Vector2 = p_match.map_data.size
	limit_left = -200
	limit_top = -200
	limit_right = int(size.x) + 200
	limit_bottom = int(size.y) + 200
	zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	position_smoothing_enabled = false


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) and not Input.is_physical_key_pressed(KEY_CTRL):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x
	_clamp_to_map()


func _clamp_to_map() -> void:
	if match_ref == null:
		return
	# Keep the camera centre where the view actually is, so panning never feels
	# "stuck" behind the camera limits at the edge of the map.
	var half: Vector2 = get_viewport_rect().size / zoom.x * 0.5
	var lo: Vector2 = Vector2(float(limit_left), float(limit_top)) + half
	var hi: Vector2 = Vector2(float(limit_right), float(limit_bottom)) - half
	var center: Vector2 = match_ref.map_data.size * 0.5
	position.x = clampf(position.x, lo.x, hi.x) if lo.x <= hi.x else center.x
	position.y = clampf(position.y, lo.y, hi.y) if lo.y <= hi.y else center.y


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(zoom.x * ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(zoom.x / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_drag = mb.pressed
	elif event is InputEventMouseMotion and _mid_drag:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		_clamp_to_map()


func _set_zoom(value: float) -> void:
	var z: float = clampf(value, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)


## World-space rectangle currently on screen.
func view_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size / zoom.x
	return Rect2(get_screen_center_position() - view * 0.5, view)
