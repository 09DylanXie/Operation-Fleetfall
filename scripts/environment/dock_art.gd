class_name DockArt
extends RefCounted
## Draws the dock of a shipyard site: a short pier from the shore and two slim quays
## marking the slip where hulls are laid down. Shared by islands and Home Bases. Kept
## small on purpose so it does not clutter the water around the site.

const WOOD: Color = Color(0.46, 0.34, 0.22)
const NEUTRAL: Color = Color(0.72, 0.72, 0.7)
const BERTH_HALF_LENGTH: float = 20.0
const BERTH_HALF_WIDTH: float = 13.0


## `canvas` is the site node (its origin is the site centre).
static func draw(canvas: CanvasItem, yard: Shipyard, site_position: Vector2, local_team: int) -> void:
	if yard == null:
		return
	var slip: Vector2 = yard.slip_position - site_position
	var dir: Vector2 = Vector2.from_angle(yard.slip_rotation)
	var side: Vector2 = dir.orthogonal()
	var color: Color = NEUTRAL if not yard.has_owner() else Ship.TEAM_COLORS[yard.team]
	# A site with no shipyard built yet only shows a faint pier.
	var alpha: float = 0.9 if yard.tier > 0 else 0.45
	var wood: Color = Color(WOOD.r, WOOD.g, WOOD.b, alpha)
	var quay: Color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, alpha)
	var back: Vector2 = slip - dir * BERTH_HALF_LENGTH
	canvas.draw_line(dir * yard.site_radius * 0.9, back, wood, 6.0)
	canvas.draw_line(back - side * BERTH_HALF_WIDTH, back + side * BERTH_HALF_WIDTH, wood, 4.0)
	for sign: float in [-1.0, 1.0]:
		var edge: Vector2 = side * BERTH_HALF_WIDTH * sign
		canvas.draw_line(back + edge, slip + dir * BERTH_HALF_LENGTH + edge, quay, 3.0)
	# Crane at the head of the berth.
	var crane: Vector2 = back + side * BERTH_HALF_WIDTH
	canvas.draw_rect(Rect2(crane - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), Color(0.9, 0.75, 0.25, alpha))
	if yard.tier <= 0 or yard.team != local_team or local_team < 0:
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
