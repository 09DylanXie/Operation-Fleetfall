class_name HomeBase
extends Combatant
## Fortified harbor. Destroying the enemy's ends the match. Hosts the starting
## Shipyard, detects submarines, and is immune to submarine weapons.

var radius: float = 80.0
var shipyard: Shipyard = null
var selected: bool = false


func setup(p_team: int, p_match: Match, p_position: Vector2) -> void:
	var balance: GameBalance = GameData.balance()
	team = p_team
	match_ref = p_match
	position = p_position
	radius = balance.home_base_radius
	max_hp = balance.home_base_hp
	hp = max_hp
	base_armor = balance.home_base_armor


func _ready() -> void:
	var balance: GameBalance = GameData.balance()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = radius
	(get_node("Hitbox") as CollisionShape2D).shape = circle
	configure_layers()
	shipyard = Shipyard.new()
	shipyard.name = "Shipyard"
	shipyard.match_ref = match_ref
	shipyard.team = team
	shipyard.tier = balance.home_shipyard_start_tier
	shipyard.max_tier = balance.home_shipyard_max_tier
	shipyard.site_name = "Home Base"
	shipyard.site_position = position
	shipyard.site_radius = radius
	add_child(shipyard)


func is_home_base() -> bool:
	return true


func hit_radius() -> float:
	return radius


func range_padding() -> float:
	return radius * 0.8


func income() -> Vector2i:
	var balance: GameBalance = GameData.balance()
	return Vector2i(balance.home_gold, balance.home_steel)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var color: Color = Ship.TEAM_COLORS[team]
	# Reef, beach and the fortress island under the dock.
	draw_circle(Vector2.ZERO, radius + 16.0, Color(0.2, 0.55, 0.58, 0.5))
	draw_arc(Vector2.ZERO, radius + 16.0, 0.0, TAU, 56, Color(0.85, 0.95, 0.97, 0.5), 1.5)
	draw_circle(Vector2.ZERO, radius, Color(0.8, 0.73, 0.54))
	draw_circle(Vector2.ZERO, radius * 0.86, Color(0.17, 0.34, 0.18))
	DockArt.draw(self, shipyard, position, match_ref.local_team if match_ref != null else -1)
	# Octagonal concrete fort with a coastal gun at every other corner.
	var wall: PackedVector2Array = PackedVector2Array()
	for i: int in 8:
		wall.append(Vector2.from_angle(PI / 8.0 + TAU * float(i) / 8.0) * radius * 0.68)
	draw_colored_polygon(wall, Color(0.5, 0.5, 0.48))
	var rim: PackedVector2Array = wall.duplicate()
	rim.append(wall[0])
	draw_polyline(rim, Color(0.32, 0.32, 0.31), 3.0)
	for i: int in 4:
		var a: float = PI / 8.0 + TAU * float(i * 2) / 8.0
		var at: Vector2 = Vector2.from_angle(a) * radius * 0.68
		draw_circle(at, 8.0, Color(0.4, 0.4, 0.38))
		draw_line(at, at + Vector2.from_angle(a) * 14.0, Color(0.18, 0.18, 0.18), 2.5)
		draw_circle(at, 5.0, Color(0.6, 0.61, 0.6))
	# Headquarters block, radar and the team colours.
	var s: float = radius * 0.3
	draw_rect(Rect2(Vector2(-s, -s * 0.8), Vector2(s * 2.0, s * 1.6)), Color(0.36, 0.37, 0.36))
	draw_rect(Rect2(Vector2(-s * 0.7, -s * 0.5), Vector2(s * 1.4, s * 1.0)), color.darkened(0.2))
	draw_rect(Rect2(Vector2(-s * 0.35, -s * 0.25), Vector2(s * 0.7, s * 0.5)), color.lightened(0.2))
	var radar: Vector2 = Vector2(radius * 0.38, -radius * 0.32)
	draw_circle(radar, 4.0, Color(0.3, 0.3, 0.3))
	var sweep: float = Time.get_ticks_msec() * 0.002
	draw_line(radar - Vector2.from_angle(sweep) * 7.0, radar + Vector2.from_angle(sweep) * 7.0, Color(0.75, 0.77, 0.78), 2.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 56, color, 4.0 if selected else 2.5)
	if shipyard != null:
		for i: int in shipyard.max_tier:
			var pip: Vector2 = Vector2(-6.0 + 12.0 * float(i), radius * 0.6)
			draw_circle(pip, 4.5, Color(0.1, 0.1, 0.1))
			if i < shipyard.tier:
				draw_circle(pip, 3.2, Color(1.0, 0.85, 0.3))
	var bar_w: float = radius * 1.8
	var bar_pos: Vector2 = Vector2(-bar_w * 0.5, -radius - 18.0)
	var frac: float = clampf(hp / max_hp, 0.0, 1.0)
	draw_rect(Rect2(bar_pos, Vector2(bar_w, 7.0)), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(bar_pos, Vector2(bar_w * frac, 7.0)), Color(0.3, 0.9, 0.35) if frac > 0.4 else Color(0.95, 0.3, 0.2))
