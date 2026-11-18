class_name DockArt
extends RefCounted
## Draws the dock of a shipyard site as part of the land: a reclaimed concrete wharf built
## out from the shore, with warehouses and a crane on it and two jetty arms enclosing the
## slip where hulls are laid down. Shared by islands and Home Bases.

const CONCRETE: Color = Color(0.58, 0.58, 0.55)
const CONCRETE_DARK: Color = Color(0.42, 0.42, 0.4)
const FILL: Color = Color(0.74, 0.68, 0.5)
const SHED: Color = Color(0.38, 0.41, 0.36)
const CRANE: Color = Color(0.85, 0.68, 0.22)
const BERTH_HALF_LENGTH: float = 20.0
const BERTH_HALF_WIDTH: float = 17.0


## `canvas` is the site node (its origin is the site centre).
static func draw(canvas: CanvasItem, yard: Shipyard, site_position: Vector2, local_team: int) -> void:
	if yard == null:
		return
	var slip: Vector2 = yard.slip_position - site_position
	var dir: Vector2 = Vector2.from_angle(yard.slip_rotation)
	var side: Vector2 = dir.orthogonal()
	var built: bool = yard.tier > 0
	var alpha: float = 1.0 if built else 0.6
	var team_color: Color = Color(0.8, 0.8, 0.78) if not yard.has_owner() else Ship.TEAM_COLORS[yard.team]
	var back: Vector2 = slip - dir * BERTH_HALF_LENGTH
	var shore: Vector2 = dir * yard.site_radius * 0.55
	var apron_w: float = BERTH_HALF_WIDTH + 14.0
	# Land fill joining the wharf to the beach, then the concrete apron on top.
	var fill: PackedVector2Array = PackedVector2Array([shore - side * (apron_w + 18.0), back - side * (apron_w + 6.0),
		back + side * (apron_w + 6.0), shore + side * (apron_w + 18.0)])
	canvas.draw_colored_polygon(fill, Color(FILL, alpha))
	var apron: PackedVector2Array = PackedVector2Array([shore - side * apron_w + dir * 6.0, back - side * apron_w,
		back + side * apron_w, shore + side * apron_w + dir * 6.0])
	canvas.draw_colored_polygon(apron, Color(CONCRETE, alpha))
	var edge: PackedVector2Array = apron.duplicate()
	edge.append(apron[0])
	canvas.draw_polyline(edge, Color(CONCRETE_DARK, alpha), 1.5)
	# Team-painted quay edge along the waterfront.
	canvas.draw_line(back - side * apron_w, back + side * apron_w, Color(team_color, 0.9 * alpha), 2.5)
	# Jetty arms either side of the slip.
	var tip: Vector2 = slip + dir * (BERTH_HALF_LENGTH + 10.0)
	for sign: float in [-1.0, 1.0]:
		var off: Vector2 = side * (BERTH_HALF_WIDTH + 3.0) * sign
		canvas.draw_line(back + off, tip + off, Color(CONCRETE_DARK, alpha), 7.0)
		canvas.draw_line(back + off, tip + off, Color(CONCRETE, alpha), 5.0)
		# Bollards.
		for b: int in 3:
			canvas.draw_circle(back + off + dir * (8.0 + float(b) * 14.0), 1.2, Color(0.2, 0.2, 0.2, alpha))
	if not built:
		return
	# Warehouses with ridge lines, and a gantry crane on the port-side arm.
	var mid: Vector2 = (shore + back) * 0.5
	for s: float in [-1.0, 1.0]:
		var at: Vector2 = mid + side * s * apron_w * 0.5
		var shed: PackedVector2Array = PackedVector2Array([at - dir * 9.0 - side * 7.0, at + dir * 9.0 - side * 7.0,
			at + dir * 9.0 + side * 7.0, at - dir * 9.0 + side * 7.0])
		canvas.draw_colored_polygon(shed, SHED)
		canvas.draw_line(at - dir * 9.0, at + dir * 9.0, Color(0.27, 0.29, 0.25), 1.0)
	var crane: Vector2 = back - side * (BERTH_HALF_WIDTH + 3.0) + dir * 10.0
	canvas.draw_rect(Rect2(crane - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), CRANE)
	canvas.draw_line(crane, crane + side * BERTH_HALF_WIDTH * 0.9 + dir * 6.0, CRANE, 2.0)
	if yard.team != local_team or local_team < 0:
		return
	# The local player's docks show their repair zone and what the yard is doing.
	var zone: Color = Color(0.45, 1.0, 0.55, 0.13)
	if yard.is_building():
		zone = Color(1.0, 0.85, 0.3, 0.13)
	canvas.draw_arc(slip, GameData.balance().dock_radius, 0.0, TAU, 72, zone, 1.0, true)
	if yard.repairing > 0:
		var badge: Vector2 = slip - dir * (BERTH_HALF_LENGTH + 14.0)
		canvas.draw_circle(badge, 8.0, Color(0.1, 0.2, 0.12, 0.9))
		canvas.draw_rect(Rect2(badge - Vector2(5.0, 1.5), Vector2(10.0, 3.0)), Color(0.45, 1.0, 0.55))
		canvas.draw_rect(Rect2(badge - Vector2(1.5, 5.0), Vector2(3.0, 10.0)), Color(0.45, 1.0, 0.55))
