class_name DockArt
extends RefCounted
## Draws the dock of a shipyard site as part of the land: a wharf built out from the shore
## with two jetty arms enclosing the slip where hulls are laid down. Each tier looks
## different: Tier 1 is a timber jetty with one shed and a derrick, Tier 2 a concrete wharf
## with warehouses, a gantry crane and fuel tanks, Tier 3 a naval base with a dry-dock gate,
## two hammerhead cranes, a fabrication hall and lit jetty heads. Shared by islands and
## Home Bases.

const CONCRETE: Color = Color(0.58, 0.58, 0.55)
const CONCRETE_DARK: Color = Color(0.42, 0.42, 0.4)
const FILL: Color = Color(0.74, 0.68, 0.5)
const SHED: Color = Color(0.38, 0.41, 0.36)
const CRANE: Color = Color(0.85, 0.68, 0.22)
const CRANE_DARK: Color = Color(0.25, 0.2, 0.08)
const TIMBER: Color = Color(0.5, 0.36, 0.22)
const TIMBER_DARK: Color = Color(0.33, 0.23, 0.14)
const ROOF_RED: Color = Color(0.55, 0.25, 0.2)
const HALL: Color = Color(0.3, 0.34, 0.38)
const TANK: Color = Color(0.72, 0.72, 0.68)
const HAZARD: Color = Color(0.95, 0.78, 0.15)
const BERTH_HALF_LENGTH: float = 20.0
const BERTH_HALF_WIDTH: float = 17.0


## `canvas` is the site node (its origin is the site centre).
static func draw(canvas: CanvasItem, yard: Shipyard, site_position: Vector2, local_team: int) -> void:
	if yard == null:
		return
	var slip: Vector2 = yard.slip_position - site_position
	var dir: Vector2 = Vector2.from_angle(yard.slip_rotation)
	var side: Vector2 = dir.orthogonal()
	var tier: int = yard.tier
	var built: bool = tier > 0
	var timber: bool = tier <= 1
	var alpha: float = 1.0 if built else 0.6
	var team_color: Color = Color(0.8, 0.8, 0.78) if not yard.has_owner() else Ship.TEAM_COLORS[yard.team]
	var back: Vector2 = slip - dir * BERTH_HALF_LENGTH
	var shore: Vector2 = dir * yard.site_radius * 0.55
	# Bigger yards reclaim a wider apron.
	var apron_w: float = BERTH_HALF_WIDTH + (10.0 if tier <= 1 else (14.0 if tier == 2 else 19.0))
	# Land fill joining the wharf to the beach, then the deck on top.
	var fill: PackedVector2Array = PackedVector2Array([shore - side * (apron_w + 18.0), back - side * (apron_w + 6.0),
		back + side * (apron_w + 6.0), shore + side * (apron_w + 18.0)])
	canvas.draw_colored_polygon(fill, Color(FILL, alpha))
	var apron: PackedVector2Array = PackedVector2Array([shore - side * apron_w + dir * 6.0, back - side * apron_w,
		back + side * apron_w, shore + side * apron_w + dir * 6.0])
	canvas.draw_colored_polygon(apron, Color(TIMBER if timber else CONCRETE, alpha))
	if timber:
		# Plank seams across the timber deck.
		for i: int in 7:
			var u: float = (float(i) + 0.5) / 7.0
			canvas.draw_line(apron[0].lerp(apron[1], u), apron[3].lerp(apron[2], u),
				Color(TIMBER_DARK, 0.6 * alpha), 0.8)
	var edge: PackedVector2Array = apron.duplicate()
	edge.append(apron[0])
	canvas.draw_polyline(edge, Color(TIMBER_DARK if timber else CONCRETE_DARK, alpha), 1.5)
	# Team-painted quay edge along the waterfront.
	canvas.draw_line(back - side * apron_w, back + side * apron_w, Color(team_color, 0.9 * alpha), 2.5)
	# Jetty arms either side of the slip: timber piers up to Tier 1, concrete moles above
	# that, longer and lit at Tier 3.
	var reach: float = 6.0 if tier <= 1 else (10.0 if tier == 2 else 14.0)
	var tip: Vector2 = slip + dir * (BERTH_HALF_LENGTH + reach)
	for sign: float in [-1.0, 1.0]:
		var off: Vector2 = side * (BERTH_HALF_WIDTH + 3.0) * sign
		if timber:
			canvas.draw_line(back + off, tip + off, Color(TIMBER_DARK, alpha), 6.0)
			canvas.draw_line(back + off, tip + off, Color(TIMBER, alpha), 4.0)
			for b: int in 4:
				canvas.draw_circle(back + off + dir * (5.0 + float(b) * 11.0), 1.4, Color(TIMBER_DARK, alpha))
			continue
		var width: float = 7.0 if tier == 2 else 9.0
		canvas.draw_line(back + off, tip + off, Color(CONCRETE_DARK, alpha), width)
		canvas.draw_line(back + off, tip + off, Color(CONCRETE, alpha), width - 2.0)
		for b: int in 3:
			canvas.draw_circle(back + off + dir * (8.0 + float(b) * 14.0), 1.2, Color(0.2, 0.2, 0.2, alpha))
		if tier >= 3:
			# Navigation lights on the jetty heads: green to starboard, red to port.
			canvas.draw_circle(tip + off, 2.6, Color(0.1, 0.1, 0.1))
			canvas.draw_circle(tip + off, 1.7, Color(0.3, 1.0, 0.4) if sign > 0.0 else Color(1.0, 0.3, 0.25))
	if not built:
		return
	var mid: Vector2 = (shore + back) * 0.5
	match tier:
		1:
			_tier_one(canvas, mid, back, dir, side, apron_w)
		2:
			_tier_two(canvas, mid, back, shore, dir, side, apron_w)
		_:
			_tier_three(canvas, mid, back, shore, dir, side, apron_w, team_color)
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


## A rectangle `half_l` along the slip axis and `half_w` across it, centred on `at`.
static func _box(canvas: CanvasItem, at: Vector2, dir: Vector2, side: Vector2, half_l: float, half_w: float,
		color: Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([at - dir * half_l - side * half_w,
		at + dir * half_l - side * half_w, at + dir * half_l + side * half_w, at - dir * half_l + side * half_w]), color)


## Tier 1: one tin shed, a wooden derrick on the port pier and a stack of crates.
static func _tier_one(canvas: CanvasItem, mid: Vector2, back: Vector2, dir: Vector2, side: Vector2,
		apron_w: float) -> void:
	var at: Vector2 = mid + side * apron_w * 0.45
	_box(canvas, at, dir, side, 7.0, 5.5, SHED)
	canvas.draw_line(at - dir * 7.0, at + dir * 7.0, Color(0.27, 0.29, 0.25), 1.0)
	var post: Vector2 = back - side * (BERTH_HALF_WIDTH + 3.0) + dir * 8.0
	canvas.draw_circle(post, 2.2, TIMBER_DARK)
	canvas.draw_line(post, post + side * BERTH_HALF_WIDTH * 0.6 + dir * 4.0, TIMBER_DARK, 1.4)
	for i: int in 3:
		var crate: Vector2 = mid - side * apron_w * 0.4 + dir * (float(i) - 1.0) * 4.5
		_box(canvas, crate, dir, side, 1.8, 1.8, Color(0.62, 0.48, 0.3))


## Tier 2: two warehouses, a gantry crane on the port arm and a pair of fuel tanks.
static func _tier_two(canvas: CanvasItem, mid: Vector2, back: Vector2, shore: Vector2, dir: Vector2,
		side: Vector2, apron_w: float) -> void:
	for s: float in [-1.0, 1.0]:
		var at: Vector2 = mid + side * s * apron_w * 0.5
		_box(canvas, at, dir, side, 9.0, 7.0, SHED)
		canvas.draw_line(at - dir * 9.0, at + dir * 9.0, Color(0.27, 0.29, 0.25), 1.0)
	var crane: Vector2 = back - side * (BERTH_HALF_WIDTH + 3.0) + dir * 10.0
	canvas.draw_rect(Rect2(crane - Vector2(3.5, 3.5), Vector2(7.0, 7.0)), CRANE)
	canvas.draw_line(crane, crane + side * BERTH_HALF_WIDTH * 0.9 + dir * 6.0, CRANE, 2.0)
	for i: int in 2:
		var tank: Vector2 = shore.lerp(mid, 0.35) + side * (float(i) - 0.5) * 11.0
		canvas.draw_circle(tank, 4.6, Color(0.3, 0.3, 0.28))
		canvas.draw_circle(tank, 3.8, TANK)


## Tier 3: a hazard-striped dry-dock gate across the slip, a long fabrication hall in team
## trim, red-roofed stores, two hammerhead cranes (one on each arm) and a fuel farm.
static func _tier_three(canvas: CanvasItem, mid: Vector2, back: Vector2, shore: Vector2, dir: Vector2,
		side: Vector2, apron_w: float, team_color: Color) -> void:
	var gate_a: Vector2 = back - side * BERTH_HALF_WIDTH
	var gate_b: Vector2 = back + side * BERTH_HALF_WIDTH
	canvas.draw_line(gate_a, gate_b, Color(0.12, 0.12, 0.12), 4.5)
	for i: int in 3:
		var u: float = float(i * 2) / 6.0
		canvas.draw_line(gate_a.lerp(gate_b, u), gate_a.lerp(gate_b, u + 1.0 / 6.0), HAZARD, 3.0)
	var hall: Vector2 = mid + dir * 2.0
	_box(canvas, hall, dir, side, 12.0, 8.0, HALL)
	for i: int in 4:
		var x: Vector2 = hall + dir * (-9.0 + float(i) * 6.0)
		canvas.draw_line(x - side * 8.0, x + side * 8.0, Color(0.22, 0.25, 0.28), 1.0)
	canvas.draw_line(hall - dir * 12.0, hall + dir * 12.0, Color(team_color, 0.8), 1.2)
	for s: float in [-1.0, 1.0]:
		var at: Vector2 = mid + side * s * apron_w * 0.72
		_box(canvas, at, dir, side, 8.0, 4.5, ROOF_RED)
		canvas.draw_line(at - dir * 8.0, at + dir * 8.0, Color(0.38, 0.17, 0.14), 1.0)
	for s: float in [-1.0, 1.0]:
		var tower: Vector2 = back + side * (BERTH_HALF_WIDTH + 3.0) * s + dir * (8.0 if s < 0.0 else 26.0)
		var jib_a: Vector2 = tower + side * 7.0 * s
		var jib_b: Vector2 = tower - side * BERTH_HALF_WIDTH * 1.05 * s
		canvas.draw_line(jib_a, jib_b, CRANE_DARK, 3.4)
		canvas.draw_line(jib_a, jib_b, CRANE, 2.2)
		canvas.draw_rect(Rect2(tower - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), CRANE_DARK)
		canvas.draw_rect(Rect2(tower - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), CRANE)
	for i: int in 3:
		var tank: Vector2 = shore.lerp(mid, 0.25) + side * (float(i) - 1.0) * 10.5
		canvas.draw_circle(tank, 4.4, Color(0.3, 0.3, 0.28))
		canvas.draw_circle(tank, 3.6, TANK)
		canvas.draw_arc(tank, 2.2, 0.0, TAU, 12, Color(team_color, 0.7), 1.0)
