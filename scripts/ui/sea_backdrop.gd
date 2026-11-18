class_name SeaBackdrop
extends Control
## Animated backdrop for the start menu and the lobby: a deep sea fading to the horizon,
## rolling swell lines, islands and two task forces steaming toward each other, with the
## odd gun flash on the horizon. Cosmetic only (driven by its own clock).

var _time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 16.0 or h < 16.0:
		return
	# Sky-to-sea gradient.
	var top: Color = Color(0.02, 0.06, 0.12)
	var mid: Color = Color(0.04, 0.17, 0.28)
	var low: Color = Color(0.03, 0.11, 0.2)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0.0), Vector2(w, h * 0.55), Vector2(0.0, h * 0.55)]),
		PackedColorArray([top, top, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0.0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0.0, h)]),
		PackedColorArray([mid, mid, low, low]))
	# Swell lines.
	for i: int in 14:
		var base_y: float = h * (0.05 + 0.07 * float(i))
		var amp: float = 6.0 + 3.0 * float(i % 3)
		var speed: float = 0.35 + 0.08 * float(i % 4)
		var points: PackedVector2Array = PackedVector2Array()
		var x: float = -20.0
		while x <= w + 20.0:
			points.append(Vector2(x, base_y + sin(x * 0.006 + _time * speed + float(i) * 1.7) * amp
				+ sin(x * 0.017 - _time * speed * 1.6) * amp * 0.3))
			x += 24.0
		draw_polyline(points, Color(0.3, 0.55, 0.72, 0.12 + 0.04 * float(i % 3)), 1.6, true)
	# Islands with surf.
	for spot: Vector3 in [Vector3(0.1, 0.2, 70.0), Vector3(0.88, 0.28, 95.0), Vector3(0.17, 0.86, 110.0),
			Vector3(0.8, 0.84, 60.0), Vector3(0.52, 0.08, 40.0)]:
		var at: Vector2 = Vector2(w * spot.x, h * spot.y)
		var surf: float = 1.0 + 0.04 * sin(_time * 1.3 + spot.x * 9.0)
		draw_circle(at, spot.z * 1.55 * surf, Color(0.18, 0.45, 0.55, 0.22))
		draw_circle(at, spot.z * 1.12, Color(0.9, 0.94, 0.95, 0.25))
		draw_circle(at, spot.z, Color(0.78, 0.7, 0.5))
		draw_circle(at + Vector2(-spot.z * 0.06, -spot.z * 0.05), spot.z * 0.78, Color(0.22, 0.4, 0.22))
		draw_circle(at + Vector2(spot.z * 0.12, spot.z * 0.1), spot.z * 0.42, Color(0.3, 0.5, 0.28))
	# Two task forces closing.
	for team: int in 2:
		var color: Color = Ship.TEAM_COLORS[team]
		var bow: float = 1.0 if team == 0 else -1.0
		var drift: float = fmod(_time * 14.0, w * 0.25)
		for i: int in 5:
			var x: float = w * (0.02 + 0.045 * float(i)) + drift if team == 0 else w * (0.98 - 0.045 * float(i)) - drift
			var at: Vector2 = Vector2(x, h * (0.46 + 0.04 * float(i % 2)) + sin(_time * 1.2 + float(i)) * 2.0)
			var length: float = 30.0 - 4.0 * float(i % 3)
			draw_line(at - Vector2(length * bow, 0.0), at - Vector2(length * 3.2 * bow, 0.0),
				Color(0.85, 0.95, 1.0, 0.18), 5.0)
			draw_colored_polygon(PackedVector2Array([at + Vector2(length * bow, 0.0), at + Vector2(length * 0.4 * bow, 7.0),
				at + Vector2(-length * bow, 6.0), at + Vector2(-length * bow, -6.0), at + Vector2(length * 0.4 * bow, -7.0)]),
				Color(color.r * 0.8, color.g * 0.8, color.b * 0.8))
			draw_rect(Rect2(at + Vector2(-6.0, -3.0), Vector2(12.0, 6.0)), Color(0.75, 0.78, 0.8))
	# Distant gunfire.
	for i: int in 3:
		var phase: float = fmod(_time * 0.5 + float(i) * 0.37, 1.0)
		if phase < 0.06:
			var at: Vector2 = Vector2(w * (0.35 + 0.15 * float(i)), h * (0.44 + 0.05 * float(i % 2)))
			draw_circle(at, 10.0 * (1.0 - phase / 0.06), Color(1.0, 0.8, 0.4, 0.8))
	# Vignette.
	var edge: Color = Color(0.0, 0.0, 0.0, 0.45)
	var clear: Color = Color(0.0, 0.0, 0.0, 0.0)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0.0), Vector2(w, h * 0.18), Vector2(0.0, h * 0.18)]),
		PackedColorArray([edge, edge, clear, clear]))
	draw_polygon(PackedVector2Array([Vector2(0.0, h * 0.82), Vector2(w, h * 0.82), Vector2(w, h), Vector2(0.0, h)]),
		PackedColorArray([clear, clear, edge, edge]))
